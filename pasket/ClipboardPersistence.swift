import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ClipboardMutation: Sendable {
    case upsert(ClipboardItem)
    case touch(UUID, Date)
    case delete(UUID)
    case deleteFingerprint(String)
    case clear
    case completeImageImport(UUID)
    case settings(isPaused: Bool, folders: [ClipboardFile])
    case maintenance
}

nonisolated struct ClipboardPage: Sendable {
    var items: [ClipboardItem]
    var matchingCount: Int
    var totalCount: Int
    var imageBytes: Int
    var textBytes: Int
}

nonisolated enum ClipboardStorageError: LocalizedError {
    case unsupportedVersion, invalidImage, largeImage, invalidHistory, missingImage, imageBudget, invalidRetention

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This history was created by a newer version of Pasket. It has been left unchanged."
        case .invalidImage: "This image could not be saved."
        case .largeImage: "Image not saved: the limit is 20 MB and 40 million pixels."
        case .invalidHistory: "The history file is damaged. It has been left unchanged."
        case .missingImage: "This saved image is unavailable. You can delete its history entry."
        case .imageBudget: "Image not saved: the image and its thumbnail exceed your image storage limit. Existing history has been kept."
        case .invalidRetention: "History limits must be positive whole numbers or Unlimited."
        }
    }
}

actor ClipboardPersistence {
    let directory: URL
    private var committedImageNames: Set<String> = []
    private var pendingImages: [UUID: Set<String>] = [:]
    private var mediaDirectory: URL { directory.appendingPathComponent("Images", isDirectory: true) }
    private var historyURL: URL { directory.appendingPathComponent("history.json") }
    private var databaseURL: URL { directory.appendingPathComponent("history.sqlite") }
    private var hasOpenedDatabase = false

    init(directory: URL) { self.directory = directory }

    static func applicationDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pasket", isDirectory: true)
    }

    func load() throws -> ClipboardHistory {
        let database = try openDatabase()
        var history = try settings(in: database)
        try database.query("SELECT payload FROM items ORDER BY copied_at DESC, position DESC, id") {
            history.items.append(try JSONDecoder().decode(ClipboardItem.self, from: ClipboardDatabase.data($0, 0)))
        }
        return history
    }

    func loadSettings() throws -> ClipboardHistory {
        try settings(in: openDatabase())
    }

    // Full snapshots are used by importers and fixtures; normal collection uses apply(_:).
    func save(_ history: ClipboardHistory) throws {
        try validate(history)
        let database = try openDatabase()
        try database.transaction {
            try database.execute("DELETE FROM items")
            for item in history.items.reversed() { try upsert(item, in: database) }
            try writeSettings(history, in: database)
            try enforceLimits(in: database)
        }
        for item in history.items { pendingImages[item.id] = nil }
        try didCommit(in: database)
    }

    func apply(_ mutations: [ClipboardMutation]) throws {
        let database = try openDatabase()
        try database.transaction {
            for mutation in mutations {
                switch mutation {
                case .upsert(let item): try upsert(item, in: database)
                case .touch(let id, let date):
                    if var item = try item(id, in: database) {
                        item.copiedAt = date
                        try upsert(item, in: database)
                    }
                case .delete(let id): try database.execute("DELETE FROM items WHERE id = ?", [.text(id.uuidString)])
                case .deleteFingerprint(let fingerprint):
                    try database.execute("DELETE FROM items WHERE fingerprint = ?", [.text(fingerprint)])
                case .clear: try database.execute("DELETE FROM items")
                case .completeImageImport: break
                case let .settings(paused, folders):
                    var history = try settings(in: database)
                    history.isPaused = paused
                    history.authorizedFolders = folders
                    try writeSettings(history, in: database)
                case .maintenance: break
                }
            }
            try enforceLimits(in: database)
        }
        for mutation in mutations {
            switch mutation {
            case .completeImageImport(let id): pendingImages[id] = nil
            case .upsert(let item): pendingImages[item.id] = nil
            default: break
            }
        }
        try didCommit(in: database)
    }

    func item(_ id: UUID) throws -> ClipboardItem? { try item(id, in: openDatabase()) }

    func page(query: String = "", filter: ClipboardFilter = .all, limit: Int = 50, offset: Int = 0) throws -> ClipboardPage {
        let database = try openDatabase()
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var predicates: [String] = []
        var values: [ClipboardDatabase.Value] = []
        if filter == .images { predicates.append("has_image_preview = 1") }
        else if let kind = filter.kind { predicates.append("kind = ?"); values.append(.text(kind.rawValue)) }
        if !search.isEmpty {
            predicates.append("(pasket_contains(title, ?) OR pasket_contains(content, ?) OR pasket_contains(source_name, ?) OR pasket_contains(source_bundle, ?))")
            values.append(contentsOf: Array(repeating: .text(search), count: 4))
        }
        let clause = predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND ")
        var items: [ClipboardItem] = []
        try database.query("SELECT summary FROM items" + clause + " ORDER BY copied_at DESC, position DESC, id LIMIT ? OFFSET ?",
                           values + [.integer(max(0, limit)), .integer(max(0, offset))]) {
            items.append(try JSONDecoder().decode(ClipboardItem.self, from: ClipboardDatabase.data($0, 0)))
        }
        return ClipboardPage(items: items, matchingCount: try database.integer("SELECT COUNT(*) FROM items" + clause, values),
                             totalCount: try database.integer("SELECT COUNT(*) FROM items"),
                             imageBytes: try database.integer("SELECT COALESCE(SUM(image_bytes), 0) FROM items"),
                             textBytes: try database.integer("SELECT COALESCE(SUM(text_bytes), 0) FROM items"))
    }

    private func validate(_ history: ClipboardHistory) throws {
        guard history.version == 1 else { throw ClipboardStorageError.unsupportedVersion }
        guard history.retention?.isValid != false else { throw ClipboardStorageError.invalidRetention }
        guard Set(history.items.map(\.id)).count == history.items.count,
              Set(history.authorizedFolders.map(\.path)).count == history.authorizedFolders.count,
              history.authorizedFolders.allSatisfy({ $0.isSecurityScoped == true && $0.bookmark != nil }),
              history.items.allSatisfy({ item in
                  if let image = item.image {
                      return item.kind == .image && validImageNames(image) && image.byteCount >= 0
                          && image.byteCount <= ClipboardLimits.imageBytes && image.thumbnailByteCount >= 0
                          && image.thumbnailByteCount <= ClipboardLimits.imageBytes
                  }
                  if item.kind == .image { return false }
                  if item.kind == .file { return !item.files.isEmpty }
                  return item.content.count <= ClipboardLimits.textCharacters
              }) else { throw ClipboardStorageError.invalidHistory }
    }

    private func openDatabase() throws -> ClipboardDatabase {
        if hasOpenedDatabase, !FileManager.default.fileExists(atPath: databaseURL.path) {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try ClipboardDatabase(url: databaseURL)
        let version = try database.integer("PRAGMA user_version")
        guard version <= 1 else { throw ClipboardStorageError.unsupportedVersion }
        guard version >= 0 else { throw ClipboardStorageError.invalidHistory }
        if version == 0 {
            guard try database.integer("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'") == 0 else {
                throw ClipboardStorageError.invalidHistory
            }
            var history = ClipboardHistory()
            if FileManager.default.fileExists(atPath: historyURL.path) {
                history = try JSONDecoder().decode(ClipboardHistory.self, from: Data(contentsOf: historyURL))
                try validate(history)
            }
            try database.transaction {
                try database.execute("""
                    CREATE TABLE items (
                        id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL UNIQUE, kind TEXT NOT NULL,
                        title TEXT NOT NULL, content TEXT NOT NULL, source_name TEXT NOT NULL, source_bundle TEXT NOT NULL,
                        copied_at REAL NOT NULL, position INTEGER NOT NULL, has_image_preview INTEGER NOT NULL,
                        text_bytes INTEGER NOT NULL, image_bytes INTEGER NOT NULL,
                        image_name TEXT NOT NULL, thumbnail_name TEXT NOT NULL, summary BLOB NOT NULL, payload BLOB NOT NULL
                    )
                    """)
                try database.execute("CREATE INDEX items_recency ON items(copied_at DESC, position DESC, id)")
                try database.execute("CREATE INDEX items_kind_recency ON items(kind, copied_at DESC, position DESC, id)")
                try database.execute("CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id = 1), payload BLOB NOT NULL)")
                for item in history.items.reversed() { try upsert(item, in: database) }
                try writeSettings(history, in: database)
                try enforceLimits(in: database)
                try database.execute("PRAGMA user_version = 1")
            }
        }
        // Only collect media after the schema and any legacy import have committed.
        if !hasOpenedDatabase {
            _ = try settings(in: database)
            try didCommit(in: database)
        }
        hasOpenedDatabase = true
        return database
    }

    private func settings(in database: ClipboardDatabase) throws -> ClipboardHistory {
        var history: ClipboardHistory?
        try database.query("SELECT payload FROM settings WHERE id = 1") {
            history = try JSONDecoder().decode(ClipboardHistory.self, from: ClipboardDatabase.data($0, 0))
        }
        guard let history else { throw ClipboardStorageError.invalidHistory }
        try validate(history)
        return history
    }

    private func writeSettings(_ history: ClipboardHistory, in database: ClipboardDatabase) throws {
        let settings = ClipboardHistory(isPaused: history.isPaused, authorizedFolders: history.authorizedFolders,
                                        retention: history.retention)
        try validate(settings)
        try database.execute("INSERT OR REPLACE INTO settings(id, payload) VALUES(1, ?)", [.blob(try JSONEncoder().encode(settings))])
    }

    private func item(_ id: UUID, in database: ClipboardDatabase) throws -> ClipboardItem? {
        var item: ClipboardItem?
        try database.query("SELECT payload FROM items WHERE id = ?", [.text(id.uuidString)]) {
            item = try JSONDecoder().decode(ClipboardItem.self, from: ClipboardDatabase.data($0, 0))
        }
        return item
    }

    private func upsert(_ incoming: ClipboardItem, in database: ClipboardDatabase) throws {
        var item = incoming
        try database.query("SELECT id FROM items WHERE fingerprint = ?", [.text(item.fingerprint)]) {
            guard let id = UUID(uuidString: ClipboardDatabase.text($0, 0)) else { throw ClipboardStorageError.invalidHistory }
            item.id = id
        }
        try validate(ClipboardHistory(items: [item]))
        if item.id != incoming.id {
            // Refreshed bookmarks can make two previously distinct paths converge.
            try database.execute("DELETE FROM items WHERE id = ?", [.text(incoming.id.uuidString)])
        }
        let position = try database.integer("SELECT COALESCE(MAX(position), 0) + 1 FROM items")
        var summary = item
        summary.content = String(item.content.prefix(500))
        let encoder = JSONEncoder()
        try database.execute("""
            INSERT INTO items VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                fingerprint=excluded.fingerprint, kind=excluded.kind, title=excluded.title, content=excluded.content,
                source_name=excluded.source_name, source_bundle=excluded.source_bundle, copied_at=excluded.copied_at,
                position=excluded.position, has_image_preview=excluded.has_image_preview,
                text_bytes=excluded.text_bytes, image_bytes=excluded.image_bytes,
                image_name=excluded.image_name, thumbnail_name=excluded.thumbnail_name,
                summary=excluded.summary, payload=excluded.payload
            """, [.text(item.id.uuidString), .text(item.fingerprint), .text(item.kind.rawValue), .text(item.title), .text(item.content),
                  .text(item.source.name), .text(item.source.bundleIdentifier ?? ""), .real(item.copiedAt.timeIntervalSinceReferenceDate),
                  .integer(position), .integer(item.hasImagePreview ? 1 : 0), .integer(item.textByteCount), .integer(item.imageByteCount),
                  .text(item.image?.fileName ?? ""), .text(item.image?.thumbnailName ?? ""),
                  .blob(try encoder.encode(summary)), .blob(try encoder.encode(item))])
    }

    private func enforceLimits(in database: ClipboardDatabase) throws {
        guard let retention = try settings(in: database).retention else { return }
        try delete(retentionPlan(retention, in: database, now: Date()), in: database)
    }

    func previewRetention(_ retention: ClipboardRetention, now: Date = Date()) throws -> ClipboardRetentionPlan {
        guard retention.isValid else { throw ClipboardStorageError.invalidRetention }
        return try retentionPlan(retention, in: openDatabase(), now: now)
    }

    // The preview is checked again inside the same transaction that saves settings and deletes rows.
    // Even a different set of victims with the same count and size requires another confirmation.
    func applyRetention(_ retention: ClipboardRetention, confirmed: ClipboardRetentionPlan? = nil,
                        now: Date = Date()) throws -> ClipboardRetentionResult {
        guard retention.isValid else { throw ClipboardStorageError.invalidRetention }
        let database = try openDatabase()
        var result = ClipboardRetentionResult.applied
        try database.transaction {
            let plan = try retentionPlan(retention, in: database, now: now)
            if plan.count > 0, plan != confirmed {
                result = .confirmationRequired(plan)
                return
            }
            var history = try settings(in: database)
            history.retention = retention
            try writeSettings(history, in: database)
            try delete(plan, in: database)
        }
        if case .applied = result { try didCommit(in: database) }
        return result
    }

    private func retentionPlan(_ retention: ClipboardRetention, in database: ClipboardDatabase,
                               now: Date) throws -> ClipboardRetentionPlan {
        var entries: [ClipboardRetentionEntry] = []
        try database.query("""
            SELECT id, copied_at, text_bytes, image_bytes,
                length(payload) + length(summary) + length(CAST(content AS BLOB))
                + length(CAST(title AS BLOB)) + length(CAST(source_name AS BLOB))
                + length(CAST(source_bundle AS BLOB)) + length(CAST(fingerprint AS BLOB)),
                image_name, thumbnail_name
            FROM items ORDER BY copied_at DESC, position DESC, id
            """) { row in
            entries.append(ClipboardRetentionEntry(
                id: ClipboardDatabase.text(row, 0), copiedAt: Date(timeIntervalSinceReferenceDate: ClipboardDatabase.real(row, 1)),
                textBytes: ClipboardDatabase.int(row, 2), imageBytes: ClipboardDatabase.int(row, 3),
                recordBytes: ClipboardDatabase.int(row, 4), imageName: ClipboardDatabase.text(row, 5),
                thumbnailName: ClipboardDatabase.text(row, 6)))
        }
        let cutoff = retention.maximumAgeDays.map { now.addingTimeInterval(-Double($0) * 86_400) }
        var remainingText = retention.maximumTextBytes ?? Int.max
        var remainingImages = retention.maximumImageBytes ?? Int.max
        var remainingItems = retention.maximumItems ?? Int.max
        var textExceeded = false
        var imagesExceeded = false
        var deleted: [ClipboardRetentionEntry] = []
        var survivingImages: Set<String> = []
        for entry in entries {
            var remove = cutoff.map { entry.copiedAt < $0 } ?? false
            if !remove, entry.textBytes > 0 {
                textExceeded = textExceeded || entry.textBytes > remainingText
                remove = textExceeded
                if !remove { remainingText -= entry.textBytes }
            }
            if !remove, entry.imageBytes > 0 {
                imagesExceeded = imagesExceeded || entry.imageBytes > remainingImages
                remove = imagesExceeded
                if !remove { remainingImages -= entry.imageBytes }
            }
            if !remove {
                remove = remainingItems == 0
                if !remove { remainingItems -= 1 }
            }
            if remove { deleted.append(entry) }
            else if !entry.imageName.isEmpty {
                survivingImages.insert(entry.imageName)
                survivingImages.insert(entry.thumbnailName)
            }
        }
        // Database records contain bookmarks and metadata, never the referenced original file bytes.
        // Shared or in-flight image files will not be released by this cleanup.
        let pending = pendingImages.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        var countedImages = survivingImages.union(pending)
        var bytes = 0
        for entry in deleted {
            bytes += entry.recordBytes
            for name in [entry.imageName, entry.thumbnailName] where isManagedImageName(name) {
                if countedImages.insert(name).inserted,
                   let size = try? mediaDirectory.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    bytes += size
                }
            }
        }
        return ClipboardRetentionPlan(settings: retention, entries: deleted, estimatedBytes: bytes)
    }

    private func delete(_ plan: ClipboardRetentionPlan, in database: ClipboardDatabase) throws {
        for entry in plan.entries {
            try database.execute("DELETE FROM items WHERE id = ?", [.text(entry.id)])
        }
    }

    private func didCommit(in database: ClipboardDatabase) throws {
        var names: Set<String> = []
        try database.query("SELECT image_name, thumbnail_name FROM items WHERE image_name != ''") {
            names.insert(ClipboardDatabase.text($0, 0))
            names.insert(ClipboardDatabase.text($0, 1))
        }
        committedImageNames = names
        try cleanImages()
        // Reclaim substantial free space without compacting the database on every copy.
        let pageSize = try database.integer("PRAGMA page_size")
        let freePages = try database.integer("PRAGMA freelist_count")
        let totalPages = try database.integer("PRAGMA page_count")
        if freePages > 0, freePages >= totalPages / 4, freePages * pageSize >= 4 * ClipboardRetention.mebibyte {
            try database.execute("VACUUM")
        }
    }

    func importImage(_ data: Data, source: ClipboardSource, at date: Date) throws -> ClipboardItem {
        guard data.count <= ClipboardLimits.imageBytes else { throw ClipboardStorageError.largeImage }
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ClipboardStorageError.invalidImage }
        guard width <= ClipboardLimits.imagePixels / height else { throw ClipboardStorageError.largeImage }
        let fullSizeOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                              kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                                              kCGImageSourceCreateThumbnailWithTransform: true,
                                              kCGImageSourceShouldCache: false]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, fullSizeOptions as CFDictionary)
        else { throw ClipboardStorageError.invalidImage }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)
        else { throw ClipboardStorageError.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ClipboardStorageError.invalidImage }
        guard png.length <= ClipboardLimits.imageBytes else { throw ClipboardStorageError.largeImage }

        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 480,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
        else { throw ClipboardStorageError.invalidImage }
        let thumbnailData = NSMutableData()
        guard let thumbnailDestination = CGImageDestinationCreateWithData(thumbnailData, UTType.png.identifier as CFString, 1, nil)
        else { throw ClipboardStorageError.invalidImage }
        CGImageDestinationAddImage(thumbnailDestination, thumbnail, nil)
        guard CGImageDestinationFinalize(thumbnailDestination) else { throw ClipboardStorageError.invalidImage }

        let hash = ClipboardItem.digest(png as Data)
        let payload = ClipboardImage(fileName: hash + ".png", thumbnailName: hash + ".thumb.png",
                                     byteCount: png.length, thumbnailByteCount: thumbnailData.length, width: image.width, height: image.height)
        if FileManager.default.fileExists(atPath: databaseURL.path),
           let budget = try settings(in: openDatabase()).retention?.maximumImageBytes,
           payload.byteCount + payload.thumbnailByteCount > budget {
            throw ClipboardStorageError.imageBudget
        }
        let item = ClipboardItem(kind: .image, title: "Image · \(image.width) × \(image.height)", content: "\(image.width) × \(image.height)",
                                 source: source, copiedAt: date, fingerprint: "image:" + hash, image: payload)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        pendingImages[item.id] = [payload.fileName, payload.thumbnailName]
        try (png as Data).write(to: mediaDirectory.appendingPathComponent(payload.fileName), options: .atomic)
        try (thumbnailData as Data).write(to: mediaDirectory.appendingPathComponent(payload.thumbnailName), options: .atomic)
        return item
    }

    func imageData(_ image: ClipboardImage, thumbnail: Bool = false) throws -> Data {
        guard validImageNames(image) else { throw ClipboardStorageError.invalidHistory }
        let url = mediaDirectory.appendingPathComponent(thumbnail ? image.thumbnailName : image.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ClipboardStorageError.missingImage }
        return try Data(contentsOf: url)
    }

    func previewImage(_ image: ClipboardImage) throws -> CGImage {
        guard validImageNames(image) else { throw ClipboardStorageError.invalidHistory }
        let url = mediaDirectory.appendingPathComponent(image.fileName)
        return try previewImage(at: url, maxPixelSize: 1_600)
    }

    func previewImageFile(_ file: ClipboardFile, thumbnail: Bool = false,
                          authorizedFolders: [ClipboardFile] = []) throws -> (image: CGImage, file: ClipboardFile) {
        try ClipboardFileAccess.withResolvedFiles([file], authorizedFolders: authorizedFolders) { urls, updated in
            (try previewImage(at: urls[0], maxPixelSize: thumbnail ? 480 : 1_600), updated[0])
        }
    }

    private func previewImage(at url: URL, maxPixelSize: Int) throws -> CGImage {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ClipboardStorageError.missingImage }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ClipboardStorageError.invalidImage }
        return preview
    }

    func hasImage(_ image: ClipboardImage) -> Bool {
        validImageNames(image) && FileManager.default.isReadableFile(atPath: mediaDirectory.appendingPathComponent(image.fileName).path)
    }

    func discardImportedImage(_ item: ClipboardItem) throws {
        pendingImages[item.id] = nil
        try cleanImages()
    }

    private func cleanImages() throws {
        guard FileManager.default.fileExists(atPath: mediaDirectory.path) else { return }
        let names = committedImageNames.union(pendingImages.values.reduce(into: Set<String>()) { $0.formUnion($1) })
        for file in try FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil) {
            // Only remove files owned by this storage format.
            if isManagedImageName(file.lastPathComponent), !names.contains(file.lastPathComponent) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    private func validImageNames(_ image: ClipboardImage) -> Bool {
        isManagedImageName(image.fileName) && image.thumbnailName == image.fileName.replacingOccurrences(of: ".png", with: ".thumb.png")
    }

    private func isManagedImageName(_ name: String) -> Bool {
        name.range(of: #"^[a-f0-9]{64}(?:\.thumb)?\.png$"#, options: .regularExpression) != nil
    }
}
