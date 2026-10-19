import AppKit
import Observation

@MainActor @Observable
final class ClipboardStore {
    var query = ""
    var filter: ClipboardFilter = .all
    var selectedID: ClipboardItem.ID?
    var presentationID = UUID()
    private(set) var copyError: String?
    private(set) var storageError: String?
    private(set) var notice: String?
    private(set) var isLoading = true
    private(set) var isPaused = false
    private(set) var isCopying = false
    private(set) var clipboardAccessDenied = false
    private(set) var items: [ClipboardItem] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]
    private(set) var previewID: UUID?
    private(set) var previewImage: NSImage?
    private(set) var missingPreviews: Set<UUID> = []
    private(set) var unavailableItems: Set<UUID> = []
    private(set) var authorizedFolders: [ClipboardFile] = []
    private(set) var folderAccessError: String?
    private(set) var folderAccessRevision = 0

    #if DEBUG
    private(set) var isDebugMode = false
    #else
    var isDebugMode: Bool { false }
    #endif

    var displayedItems: [ClipboardItem] {
        #if DEBUG
        if isDebugMode { return ClipboardSamples.items }
        #endif
        return items
    }

    private var shouldPauseMonitoring: Bool { isPaused || storageBlocked || isDebugMode }

    @ObservationIgnored private let persistence: ClipboardPersistence
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let monitor: ClipboardMonitor
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var captureGeneration = 0
    @ObservationIgnored private var storageBlocked = false
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var thumbnailOrder: [UUID] = []
    @ObservationIgnored private var thumbnailRequests: [UUID: UUID] = [:]
    @ObservationIgnored private var previewRequestID = UUID()
    @ObservationIgnored private var deletionCutoffs: [String: Date] = [:]
    @ObservationIgnored private var fileAvailabilityGeneration = 0

    init(directory: URL = ClipboardPersistence.applicationDirectory(), pasteboard: NSPasteboard = .general) {
        persistence = ClipboardPersistence(directory: directory)
        self.pasteboard = pasteboard
        monitor = ClipboardMonitor(pasteboard: pasteboard)
        monitor.onCapture = { [weak self] capture in self?.enqueue(capture) }
        monitor.onNotice = { [weak self] message in self?.notice = message }
        monitor.onAccessChange = { [weak self] denied in self?.clipboardAccessDenied = denied }
    }

    var filteredItems: [ClipboardItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return displayedItems.filter { item in
            (filter == .images ? item.hasImagePreview : filter.kind == nil || filter.kind == item.kind)
                && (search.isEmpty || [item.title, item.content, item.source.name, item.source.bundleIdentifier ?? ""].contains {
                    $0.localizedStandardContains(search)
                })
        }
    }

    var selectedItem: ClipboardItem? { filteredItems.first { $0.id == selectedID } }
    var isStorageBlocked: Bool { storageBlocked }
    var canCopySelection: Bool { !isDebugMode && selectedItem.map { !unavailableItems.contains($0.id) } == true && !isLoading && !isCopying }
    var imageStorageBytes: Int { items.reduce(0) { $0 + $1.imageByteCount } }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await load()
        if !stopRequested { monitor.start() }
        monitor.setPaused(shouldPauseMonitoring)
        if !storageBlocked { persist() }
        await refreshFileAvailability()
    }

    func stop() {
        stopRequested = true
        monitor.stop()
    }

    func resumeMonitoring() {
        stopRequested = false
        monitor.start()
        monitor.setPaused(shouldPauseMonitoring)
    }

    private func load() async {
        isLoading = true
        do {
            let history = try await persistence.load()
            items = history.items
            isPaused = history.isPaused
            authorizedFolders = history.authorizedFolders
            storageBlocked = false
            storageError = nil
            enforceLimits()
            selectedID = items.first?.id
        } catch {
            storageBlocked = true
            storageError = "Could not load history. \(error.localizedDescription) Collection is stopped. Retry after checking the history file."
        }
        isLoading = false
    }

    func retryStorage() async {
        if storageBlocked {
            await load()
            monitor.setPaused(shouldPauseMonitoring)
        } else {
            persist()
            await saveTask?.value
        }
    }

    func setPaused(_ paused: Bool) {
        guard !isDebugMode, !isLoading, !storageBlocked else { return }
        captureGeneration += 1
        isPaused = paused
        monitor.setPaused(shouldPauseMonitoring)
        notice = nil
        persist()
    }

    func prepareForPresentation() {
        query = ""
        filter = .all
        selectedID = displayedItems.first?.id
        copyError = nil
        presentationID = UUID()
        Task { await refreshFileAvailability() }
    }

    func invalidatePresentation() { presentationID = UUID() }

    #if DEBUG
    func setDebugMode(_ enabled: Bool) {
        guard isDebugMode != enabled else { return }
        captureGeneration += 1
        isDebugMode = enabled
        monitor.setPaused(shouldPauseMonitoring)
        clearPreview()
        notice = nil
        prepareForPresentation()
    }
    #endif

    func reconcileSelection() {
        copyError = nil
        if !filteredItems.contains(where: { $0.id == selectedID }) {
            selectedID = filteredItems.first?.id
        }
    }

    func moveSelection(by offset: Int) {
        let visibleItems = filteredItems
        guard !visibleItems.isEmpty else { return }
        let current = visibleItems.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : visibleItems.count)
        selectedID = visibleItems[min(max(current + offset, 0), visibleItems.count - 1)].id
        copyError = nil
    }

    func delete(_ id: UUID) {
        guard !isDebugMode, !storageBlocked, !isLoading, let deleted = items.first(where: { $0.id == id }) else { return }
        let cutoff = Date()
        deletionCutoffs[deleted.fingerprint] = cutoff
        let pendingCapture = captureTask
        Task { [weak self] in
            await pendingCapture?.value
            if self?.deletionCutoffs[deleted.fingerprint] == cutoff {
                self?.deletionCutoffs[deleted.fingerprint] = nil
            }
        }
        items.removeAll { $0.id == id }
        thumbnails[id] = nil
        if previewID == id { clearPreview() }
        missingPreviews.remove(id)
        thumbnailOrder.removeAll { $0 == id }
        unavailableItems.remove(id)
        reconcileSelection()
        persist()
    }

    func clearHistory() {
        guard !isDebugMode, !storageBlocked, !isLoading else { return }
        captureGeneration += 1
        deletionCutoffs = [:]
        monitor.checkpoint()
        items = []
        thumbnails = [:]
        clearPreview()
        missingPreviews = []
        thumbnailOrder = []
        unavailableItems = []
        selectedID = nil
        notice = nil
        copyError = nil
        persist()
    }

    @discardableResult
    func copySelection() async -> Bool {
        guard !isDebugMode, let item = selectedItem, !isCopying, !isLoading else { return false }
        isCopying = true
        defer { isCopying = false }
        let presentation = presentationID
        do {
            switch item.kind {
            case .image:
                guard let image = item.image else { return false }
                let data = try await persistence.imageData(image)
                guard presentationID == presentation, items.contains(where: { $0.id == item.id }) else { return false }
                pasteboard.clearContents()
                guard pasteboard.setData(data, forType: .png) else { throw CocoaError(.fileWriteUnknown) }
            case .file:
                try ClipboardFileAccess.withResolvedFiles(item.files, authorizedFolders: authorizedFolders) { urls, updatedFiles in
                    pasteboard.clearContents()
                    guard pasteboard.writeObjects(urls as [NSURL]) else { throw CocoaError(.fileWriteUnknown) }
                    updateFiles(updatedFiles, for: item.id, replacing: item.files, persistChanges: false)
                }
            default:
                pasteboard.clearContents()
                guard pasteboard.setString(item.content, forType: .string) else { throw CocoaError(.fileWriteUnknown) }
            }
            monitor.checkpoint()
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                var recent = items.remove(at: index)
                recent.copiedAt = Date()
                items.insert(recent, at: 0)
                persist()
            }
            unavailableItems.remove(item.id)
            copyError = nil
            return true
        } catch {
            monitor.checkpoint()
            if item.kind == .file || item.kind == .image { unavailableItems.insert(item.id) }
            copyError = item.kind == .file
                ? "A file is missing or needs permission. Authorize its folder or delete this entry."
                : "Could not copy this item. \(error.localizedDescription)"
            return false
        }
    }

    func restoreFileAccess(_ item: ClipboardItem) {
        guard !isDebugMode, item.kind == .file, !storageBlocked, !isLoading else { return }
        authorizeFolder(containing: item)
    }

    func authorizeFolder(containing item: ClipboardItem? = nil) {
        guard !isDebugMode, !storageBlocked, !isLoading else { return }
        let panel = NSOpenPanel()
        panel.message = "Allow read-only access to a folder and its subfolders for current and future history entries. Original files stay in place."
        panel.prompt = "Authorize Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let file = item?.files.first(where: { file in
            !authorizedFolders.contains { ClipboardFileAccess.contains($0, path: file.path) }
        }) ?? item?.files.first {
            panel.directoryURL = URL(fileURLWithPath: file.path).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let item, !item.files.contains(where: { ClipboardFileAccess.contains(
            ClipboardFile(path: url.path, name: url.lastPathComponent), path: $0.path
        ) }) {
            folderAccessError = "Choose a folder containing the original files."
            copyError = folderAccessError
            return
        }
        Task {
            do { try await addAuthorizedFolder(url) }
            catch {
                folderAccessError = "Could not save folder access. \(error.localizedDescription)"
                copyError = folderAccessError
            }
        }
    }

    func addAuthorizedFolder(_ url: URL) async throws {
        guard !isDebugMode, !storageBlocked, !isLoading else { return }
        let folder = try ClipboardFileAccess.captureFolder(url)
        authorizedFolders.removeAll { $0.path == folder.path }
        authorizedFolders.append(folder)
        await folderAccessDidChange()
    }

    func removeAuthorizedFolder(_ path: String) async {
        guard !isDebugMode, !storageBlocked, !isLoading else { return }
        authorizedFolders.removeAll { $0.path == path }
        await folderAccessDidChange()
    }

    private func folderAccessDidChange() async {
        folderAccessRevision += 1
        fileAvailabilityGeneration += 1
        let fileIDs = Set(items.filter { $0.kind == .file }.map(\.id))
        thumbnails = thumbnails.filter { !fileIDs.contains($0.key) }
        thumbnailRequests = thumbnailRequests.filter { !fileIDs.contains($0.key) }
        thumbnailOrder.removeAll { fileIDs.contains($0) }
        missingPreviews.subtract(fileIDs)
        if let previewID, fileIDs.contains(previewID) { clearPreview() }
        folderAccessError = nil
        copyError = nil
        persist()
        await refreshFileAvailability()
        if let selectedItem { await loadPreview(for: selectedItem) }
    }

    @discardableResult
    private func updateFiles(_ files: [ClipboardFile], for id: UUID, replacing original: [ClipboardFile],
                             persistChanges: Bool = true) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].files == original,
              files != original else { return false }
        items[index].files = files
        items[index].content = files.map(\.path).joined(separator: "\n")
        items[index].title = Self.fileTitle(files)
        items[index].fingerprint = Self.fileFingerprint(files)
        if persistChanges { persist() }
        return true
    }

    func loadThumbnail(for item: ClipboardItem) async {
        #if DEBUG
        if isDebugMode {
            if item.hasImagePreview { thumbnails[item.id] = ClipboardSamples.image }
            return
        }
        #endif
        guard item.hasImagePreview, thumbnails[item.id] == nil, thumbnailRequests[item.id] == nil else { return }
        let thumbnailRequest = UUID()
        thumbnailRequests[item.id] = thumbnailRequest
        defer { if thumbnailRequests[item.id] == thumbnailRequest { thumbnailRequests[item.id] = nil } }
        let accessRevision = folderAccessRevision
        do {
            let thumbnail: NSImage?
            if let image = item.image {
                thumbnail = NSImage(data: try await persistence.imageData(image, thumbnail: true))
            } else if let file = item.imageFile {
                let preview = try await persistence.previewImageFile(file, thumbnail: true, authorizedFolders: authorizedFolders)
                guard folderAccessRevision == accessRevision else { return }
                updateFiles([preview.file], for: item.id, replacing: item.files)
                thumbnail = NSImage(cgImage: preview.image, size: NSSize(width: preview.image.width, height: preview.image.height))
            } else {
                return
            }
            guard items.contains(where: { $0.id == item.id }) else { return }
            thumbnails[item.id] = thumbnail
            if thumbnails[item.id] != nil {
                thumbnailOrder.removeAll { $0 == item.id }
                thumbnailOrder.append(item.id)
                while thumbnailOrder.count > 32 {
                    let evictionIndex = thumbnailOrder.first == selectedID ? 1 : 0
                    let oldest = thumbnailOrder.remove(at: evictionIndex)
                    thumbnails[oldest] = nil
                }
            }
        } catch {
            guard folderAccessRevision == accessRevision else { return }
            let available = await isImageAvailable(item)
            if items.contains(where: { $0.id == item.id }) {
                if !available { unavailableItems.insert(item.id) }
            }
        }
    }

    func loadPreview(for item: ClipboardItem?) async {
        #if DEBUG
        if isDebugMode {
            clearPreview()
            if let item, item.hasImagePreview {
                previewID = item.id
                previewImage = ClipboardSamples.image
            }
            return
        }
        #endif
        guard let item, item.hasImagePreview else {
            clearPreview()
            return
        }
        guard previewID != item.id || previewImage == nil else { return }
        clearPreview()
        previewID = item.id
        missingPreviews.remove(item.id)
        let requestID = previewRequestID
        do {
            let preview: CGImage
            if let image = item.image {
                preview = try await persistence.previewImage(image)
            } else if let file = item.imageFile {
                let result = try await persistence.previewImageFile(file, authorizedFolders: authorizedFolders)
                guard previewRequestID == requestID else { return }
                updateFiles([result.file], for: item.id, replacing: item.files)
                preview = result.image
            } else {
                return
            }
            guard !Task.isCancelled, previewRequestID == requestID, selectedItem?.id == item.id else { return }
            previewImage = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
        } catch {
            let available = await isImageAvailable(item)
            guard !Task.isCancelled, previewRequestID == requestID, selectedItem?.id == item.id else { return }
            missingPreviews.insert(item.id)
            if !available { unavailableItems.insert(item.id) }
        }
    }

    private func isImageAvailable(_ item: ClipboardItem) async -> Bool {
        if let image = item.image { return await persistence.hasImage(image) }
        let files = item.files
        let folders = authorizedFolders
        return await Task.detached(priority: .utility) { ClipboardFileAccess.areAvailable(files, authorizedFolders: folders) }.value
    }

    private func clearPreview() {
        previewRequestID = UUID()
        previewID = nil
        previewImage = nil
    }

    func refreshFileAvailability() async {
        fileAvailabilityGeneration += 1
        let generation = fileAvailabilityGeneration
        let fileItems = items.filter { $0.kind == .file }
        let folders = authorizedFolders
        let result = await Task.detached(priority: .utility) {
            let files = Dictionary(uniqueKeysWithValues: fileItems.map { item in
                (item.id, try? ClipboardFileAccess.withResolvedFiles(item.files, authorizedFolders: folders) { _, updated in updated })
            })
            return (files, ClipboardFileAccess.refreshedFolders(folders))
        }.value
        guard fileAvailabilityGeneration == generation else { return }
        var changed = authorizedFolders != result.1
        if changed {
            authorizedFolders = result.1
        }
        let currentIDs = Set(items.map(\.id))
        let imageFileIDs = Set(fileItems.filter(\.hasImagePreview).map(\.id))
        for item in fileItems where currentIDs.contains(item.id) {
            let id = item.id
            if let updated = result.0[id] ?? nil {
                changed = updateFiles(updated, for: id, replacing: item.files, persistChanges: false) || changed
                unavailableItems.remove(id)
            } else {
                unavailableItems.insert(id)
                if imageFileIDs.contains(id) {
                    thumbnails[id] = nil
                    thumbnailOrder.removeAll { $0 == id }
                    if previewID == id { clearPreview() }
                    missingPreviews.insert(id)
                }
            }
        }
        if changed { persist() }
    }

    private func enqueue(_ capture: ClipboardCapture) {
        guard !isDebugMode else { return }
        let previous = captureTask
        let generation = captureGeneration
        captureTask = Task { [weak self] in
            await previous?.value
            guard let self, generation == captureGeneration, !isPaused, !storageBlocked else { return }
            do {
                let item: ClipboardItem
                switch capture {
                case let .text(text, source, date):
                    item = ClipboardItem.text(text, source: source, at: date)
                case let .image(data, source, date):
                    item = try await persistence.importImage(data, source: source, at: date)
                case let .files(files, source, date):
                    item = ClipboardItem(kind: .file, title: Self.fileTitle(files), content: files.map(\.path).joined(separator: "\n"),
                                         source: source, copiedAt: date, fingerprint: Self.fileFingerprint(files), files: files)
                }
                let deletedAfterCapture = deletionCutoffs[item.fingerprint].map { item.copiedAt <= $0 } ?? false
                guard generation == captureGeneration, !isPaused, !deletedAfterCapture else {
                    if let image = item.image { try await persistence.discardImportedImage(image) }
                    return
                }
                insert(item)
            } catch {
                if generation == captureGeneration { notice = error.localizedDescription }
            }
        }
    }

    private func insert(_ item: ClipboardItem) {
        var recent = item
        if let existing = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            recent.id = items.remove(at: existing).id
        }
        items.insert(recent, at: 0)
        notice = nil
        enforceLimits()
        reconcileSelection()
        persist()
    }

    private func enforceLimits() {
        var textBytes = 0
        var imageBytes = 0
        let kept = items.prefix(ClipboardLimits.items).prefix { item in
            textBytes += item.textByteCount
            imageBytes += item.imageByteCount
            return textBytes <= ClipboardLimits.textBytes && imageBytes <= ClipboardLimits.totalImageBytes
        }
        items = Array(kept)
        let ids = Set(items.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        if let previewID, !ids.contains(previewID) { clearPreview() }
        thumbnailOrder.removeAll { !ids.contains($0) }
        missingPreviews.formIntersection(ids)
        unavailableItems.formIntersection(ids)
    }

    private func persist() {
        guard !storageBlocked else { return }
        let snapshot = ClipboardHistory(isPaused: isPaused, items: items, authorizedFolders: authorizedFolders)
        let previousSave = saveTask
        saveTask = Task { [weak self, persistence] in
            await previousSave?.value
            do {
                try await persistence.save(snapshot)
                self?.storageError = nil
            } catch {
                self?.storageError = "History could not be saved. Changes may be lost after quitting. \(error.localizedDescription)"
            }
        }
    }

    // Used by termination and tests to wait for queued imports and atomic writes.
    func flush() async {
        await captureTask?.value
        await saveTask?.value
    }

    func pollClipboard() { monitor.poll() }

    private static func fileTitle(_ files: [ClipboardFile]) -> String {
        files.count == 1 ? files[0].name : "\(files.count) files · \(files.first?.name ?? "")"
    }

    private static func fileFingerprint(_ files: [ClipboardFile]) -> String {
        "files:" + ClipboardItem.digest((try? JSONEncoder().encode(files.map(\.path))) ?? Data())
    }
}

#if DEBUG
@MainActor
private enum ClipboardSamples {
    static let items: [ClipboardItem] = {
        let date = Date()
        var entries = [
            ClipboardItem.text("A little space for your next big idea.\n\nCollect the things that inspire you, keep useful details close, and pick up right where you left off.",
                               source: ClipboardSource(name: "Notes", bundleIdentifier: "com.apple.Notes"), at: date),
            ClipboardItem.text("https://example.com/design/journal",
                               source: ClipboardSource(name: "Safari", bundleIdentifier: "com.apple.Safari"), at: date.addingTimeInterval(-120)),
            ClipboardItem(kind: .image, title: "Mountain afternoon", content: "Sample landscape illustration",
                          source: ClipboardSource(name: "Preview", bundleIdentifier: "com.apple.Preview"),
                          copiedAt: date.addingTimeInterval(-300), fingerprint: "sample:landscape",
                          image: ClipboardImage(fileName: "sample.png", thumbnailName: "sample-thumb.png",
                                                byteCount: 48_000, thumbnailByteCount: 4_000, width: 640, height: 400)),
            ClipboardItem.text("hello@example.com", source: ClipboardSource(name: "Mail", bundleIdentifier: "com.apple.mail"),
                               at: date.addingTimeInterval(-600)),
            ClipboardItem(kind: .file, title: "Brand Guidelines.pdf", content: "/Sample/Documents/Brand Guidelines.pdf",
                          source: ClipboardSource(name: "Finder", bundleIdentifier: "com.apple.finder"),
                          copiedAt: date.addingTimeInterval(-900), fingerprint: "sample:document",
                          files: [ClipboardFile(path: "/Sample/Documents/Brand Guidelines.pdf", name: "Brand Guidelines.pdf",
                                                byteCount: 2_400_000, isSecurityScoped: true)]),
            ClipboardItem.text("Weekend plans\nVisit the bookshop, find a sunny spot, and start a new chapter.",
                               source: ClipboardSource(name: "Notes", bundleIdentifier: "com.apple.Notes"), at: date.addingTimeInterval(-1_200)),
            ClipboardItem.text("Good design makes room for the things that matter.",
                               source: ClipboardSource(name: "Safari", bundleIdentifier: "com.apple.Safari"), at: date.addingTimeInterval(-1_800)),
            ClipboardItem.text("https://example.com/reading-list",
                               source: ClipboardSource(name: "Safari", bundleIdentifier: "com.apple.Safari"), at: date.addingTimeInterval(-2_400))
        ]
        for index in entries.indices { entries[index].fingerprint = "sample:\(index)" }
        return entries
    }()

    static let image = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { bounds in
        NSColor(calibratedRed: 0.86, green: 0.92, blue: 0.95, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedRed: 0.97, green: 0.77, blue: 0.43, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 450, y: 260, width: 76, height: 76)).fill()
        for (points, color) in [
            ([NSPoint(x: 0, y: 0), NSPoint(x: 230, y: 320), NSPoint(x: 480, y: 0)],
             NSColor(calibratedRed: 0.42, green: 0.59, blue: 0.62, alpha: 1)),
            ([NSPoint(x: 200, y: 0), NSPoint(x: 470, y: 245), NSPoint(x: 720, y: 0)],
             NSColor(calibratedRed: 0.24, green: 0.43, blue: 0.45, alpha: 1))
        ] {
            color.setFill()
            let mountain = NSBezierPath()
            mountain.move(to: points[0])
            mountain.line(to: points[1])
            mountain.line(to: points[2])
            mountain.close()
            mountain.fill()
        }
        return true
    }
}
#endif
