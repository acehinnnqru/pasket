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
    @ObservationIgnored private var thumbnailRequests: Set<UUID> = []
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
        return items.filter { item in
            (filter == .images ? item.hasImagePreview : filter.kind == nil || filter.kind == item.kind)
                && (search.isEmpty || [item.title, item.content, item.source.name, item.source.bundleIdentifier ?? ""].contains {
                    $0.localizedStandardContains(search)
                })
        }
    }

    var selectedItem: ClipboardItem? { filteredItems.first { $0.id == selectedID } }
    var isStorageBlocked: Bool { storageBlocked }
    var canCopySelection: Bool { selectedItem.map { !unavailableItems.contains($0.id) } == true && !isLoading && !isCopying }
    var imageStorageBytes: Int { items.reduce(0) { $0 + $1.imageByteCount } }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await load()
        if !stopRequested { monitor.start() }
        monitor.setPaused(isPaused || storageBlocked)
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
        monitor.setPaused(isPaused || storageBlocked)
    }

    private func load() async {
        isLoading = true
        do {
            let history = try await persistence.load()
            items = history.items
            isPaused = history.isPaused
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
            monitor.setPaused(isPaused || storageBlocked)
        } else {
            persist()
            await saveTask?.value
        }
    }

    func setPaused(_ paused: Bool) {
        guard !isLoading, !storageBlocked else { return }
        captureGeneration += 1
        isPaused = paused
        monitor.setPaused(paused)
        notice = nil
        persist()
    }

    func prepareForPresentation() {
        query = ""
        filter = .all
        selectedID = items.first?.id
        copyError = nil
        presentationID = UUID()
        Task { await refreshFileAvailability() }
    }

    func invalidatePresentation() { presentationID = UUID() }

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
        guard !storageBlocked, !isLoading, let deleted = items.first(where: { $0.id == id }) else { return }
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
        guard !storageBlocked, !isLoading else { return }
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
        guard let item = selectedItem, !isCopying, !isLoading else { return false }
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
                try ClipboardFileAccess.withResolvedFiles(item.files) { urls, updatedFiles in
                    pasteboard.clearContents()
                    guard pasteboard.writeObjects(urls as [NSURL]) else { throw CocoaError(.fileWriteUnknown) }
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index].files = updatedFiles
                    }
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
                ? "A file is missing or access has expired. Restore access or delete this entry."
                : "Could not copy this item. \(error.localizedDescription)"
            return false
        }
    }

    func restoreFileAccess(_ item: ClipboardItem) {
        guard item.kind == .file, !storageBlocked, !isLoading else { return }
        var replacements: [ClipboardFile] = []
        for file in item.files {
            let panel = NSOpenPanel()
            panel.message = "Select \(file.name) to restore access to this history entry."
            panel.prompt = "Restore Access"
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: file.path).deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            replacements.append(ClipboardFileAccess.capture(url))
        }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].files = replacements
        items[index].content = replacements.map(\.path).joined(separator: "\n")
        items[index].title = Self.fileTitle(replacements)
        items[index].fingerprint = Self.fileFingerprint(replacements)
        fileAvailabilityGeneration += 1
        unavailableItems.remove(item.id)
        thumbnails[item.id] = nil
        missingPreviews.remove(item.id)
        if previewID == item.id { clearPreview() }
        copyError = nil
        persist()
        let restoredItem = items[index]
        Task {
            await loadThumbnail(for: restoredItem)
            if selectedID == restoredItem.id { await loadPreview(for: restoredItem) }
        }
    }

    func loadThumbnail(for item: ClipboardItem) async {
        guard item.hasImagePreview, thumbnails[item.id] == nil, !thumbnailRequests.contains(item.id) else { return }
        thumbnailRequests.insert(item.id)
        defer { thumbnailRequests.remove(item.id) }
        do {
            let thumbnail: NSImage?
            if let image = item.image {
                thumbnail = NSImage(data: try await persistence.imageData(image, thumbnail: true))
            } else if let file = item.imageFile {
                let preview = try await persistence.previewImageFile(file, thumbnail: true)
                thumbnail = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
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
            let available = await isImageAvailable(item)
            if items.contains(where: { $0.id == item.id }) {
                if !available { unavailableItems.insert(item.id) }
            }
        }
    }

    func loadPreview(for item: ClipboardItem?) async {
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
                preview = try await persistence.previewImageFile(file)
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
        return await Task.detached(priority: .utility) { ClipboardFileAccess.areAvailable(files) }.value
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
        let availability = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: fileItems.map { ($0.id, ClipboardFileAccess.areAvailable($0.files)) })
        }.value
        guard fileAvailabilityGeneration == generation else { return }
        let currentIDs = Set(items.map(\.id))
        let imageFileIDs = Set(fileItems.filter(\.hasImagePreview).map(\.id))
        for (id, available) in availability where currentIDs.contains(id) {
            if available {
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
    }

    private func enqueue(_ capture: ClipboardCapture) {
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
        let snapshot = ClipboardHistory(isPaused: isPaused, items: items)
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
