import AppKit
import Observation
import OSLog

@MainActor @Observable
final class ClipboardStore {
    let filterPreferences: ClipboardFilterPreferences
    let copyStatistics: HistoryStatistics
    let toasts = PasketToastCenter()
    let systemAccess = SystemAccessController()
    let pasteQueue: ClipboardPasteQueue
    var query = "" { didSet { if query != oldValue { scheduleReload() } } }
    var filter: ClipboardFilter = .all { didSet { if filter != oldValue { scheduleReload() } } }
    private(set) var selection = ClipboardSelection() {
        didSet { if selection.focusedID != oldValue.focusedID { selectedDetail = nil } }
    }
    var selectedID: ClipboardItem.ID? {
        get { selection.focusedID }
        set {
            selectsFirstResultOnReload = false
            selection.selectOnly(newValue)
        }
    }
    var selectedIDs: Set<UUID> { selection.ids }
    var markedIDs: Set<UUID> { selection.markedIDs }
    var selectedItems: [ClipboardItem] { filteredItems.filter { selectedIDs.contains($0.id) } }
    var presentationID = UUID()
    private(set) var copyError: String? {
        didSet { toasts.show(copyError, source: .copy, title: "Could Not Copy", style: .error) }
    }
    private(set) var storageError: String? {
        didSet { updateStorageToast() }
    }
    private(set) var notice: String?
    private(set) var isLoading = true
    private(set) var isPaused = false
    private(set) var isCopying = false
    private(set) var copiedChangeCount: Int?
    private(set) var isDeletingUnavailableFiles = false
    private(set) var clipboardAccessDenied = false {
        didSet {
            if !clipboardAccessDenied { systemAccess.dismiss(.clipboard) }
        }
    }
    private(set) var items: [ClipboardItem] = []
    private(set) var resultReferences: [ClipboardHistoryReference] = [] {
        didSet { if resultReferences != oldValue { layoutRevision = UUID() } }
    }
    private var resultsAreSearch = false
    private(set) var historyRevision = UUID()
    private(set) var failedHistoryIDs: Set<UUID> = []
    private(set) var totalCount = 0
    private(set) var matchingCount = 0
    private(set) var imageStorageBytes = 0
    private(set) var textStorageBytes = 0
    private(set) var retentionSettings = ClipboardRetention.default
    private(set) var needsRetentionReview = false {
        didSet { updateRetentionToast() }
    }
    private(set) var retentionError: String?
    private(set) var isApplyingRetention = false
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    private(set) var searchLevel = ClipboardSearch.Level.literal
    private(set) var isLoadingBroaderMatches = false
    var canLoadBroaderMatches: Bool {
        !isDebugMode && !ClipboardSearch(query).isEmpty && searchLevel.next != nil
    }
    private(set) var isSelectingRecentCopies = false
    private var recentCopies = ClipboardRecentCopies()
    private var recentSelectionIDs: [UUID]?
    private var selectedDetail: ClipboardItem?
    private(set) var thumbnails: [UUID: NSImage] = [:]
    private(set) var previewID: UUID?
    private(set) var previewImage: NSImage?
    private(set) var previewAnimatedImage: NSImage?
    private(set) var missingPreviews: Set<UUID> = []
    private(set) var unavailableItems: Set<UUID> = []

    #if DEBUG
    private(set) var isDebugMode = false
    private var debugItems: [ClipboardItem] = []
    #else
    var isDebugMode: Bool { false }
    #endif

    var displayedItems: [ClipboardItem] {
        #if DEBUG
        if isDebugMode { return debugItems }
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
    @ObservationIgnored private var pendingMutations: [ClipboardMutation] = []
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var queryGeneration = 0
    @ObservationIgnored private var publishedResult: (generation: Int, filter: ClipboardFilter)?
    @ObservationIgnored private var layoutRevision = UUID()
    @ObservationIgnored private var layoutCache = ClipboardHistoryLayout.Cache()
    @ObservationIgnored private var isPreparingPresentation = false
    @ObservationIgnored private var selectsFirstResultOnReload = false
    @ObservationIgnored private var loadedLimit = ClipboardHistoryLayout.pageSize
    @ObservationIgnored private var resetsLoadedResults = false
    private struct PageRequest: Hashable {
        let generation: Int
        let offset: Int
    }
    @ObservationIgnored private var pageLoads: [PageRequest: Task<Void, Never>] = [:]
    @ObservationIgnored private var historyPageError: String?
    @ObservationIgnored private var navigationTask: Task<Void, Never>?
    @ObservationIgnored private var retentionTimer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var isPresented = false
    @ObservationIgnored private var lastDismissedAt: Date?
    @ObservationIgnored private var lastAutoRecycleAt: Date?
    private let autoRecycleInterval: TimeInterval = 5 * 60
    private let pageSize = ClipboardHistoryLayout.pageSize

    init(directory: URL = ClipboardPersistence.applicationDirectory(), pasteboard: NSPasteboard = .general,
         filterPreferences: ClipboardFilterPreferences? = nil, statisticsDefaults: UserDefaults = .standard) {
        self.filterPreferences = filterPreferences ?? ClipboardFilterPreferences()
        copyStatistics = HistoryStatistics(defaults: statisticsDefaults, storageKey: "clipboardDailyCopyCounts")
        persistence = ClipboardPersistence(directory: directory)
        self.pasteboard = pasteboard
        pasteQueue = ClipboardPasteQueue(clipboardChangeCount: { pasteboard.changeCount })
        monitor = ClipboardMonitor(pasteboard: pasteboard)
        monitor.onCapture = { [weak self] capture in self?.enqueue(capture) }
        monitor.onNotice = { [weak self] message in self?.setNotice(message) }
        monitor.onAccessChange = { [weak self] denied in self?.clipboardAccessDenied = denied }
    }

    var filteredItems: [ClipboardItem] {
        if !isDebugMode { return items }
        let search = ClipboardSearch(query)
        return displayedItems.enumerated().compactMap { offset, item -> (item: ClipboardItem, rank: Double, offset: Int)? in
            guard filter == .images ? item.hasImagePreview : filter.kind == nil || filter.kind == item.kind else { return nil }
            let rank = search.rank(item)
            return rank > 0 ? (item, rank, offset) : nil
        }.sorted {
            $0.rank != $1.rank ? $0.rank > $1.rank : $0.offset < $1.offset
        }.map(\.item)
    }

    var historyReferences: [ClipboardHistoryReference] {
        isDebugMode ? filteredItems.map { ClipboardHistoryReference(id: $0.id, copiedAt: $0.copiedAt) }
            : resultReferences
    }

    func historyLayout(at date: Date) -> ClipboardHistoryLayout {
        if isDebugMode {
            return ClipboardHistoryLayout(historyReferences, at: date, query: query)
        }
        return layoutCache.layout(for: resultReferences, revision: layoutRevision, at: date, isSearch: resultsAreSearch)
    }

    private var selectionOrder: [UUID] {
        if isDebugMode { return filteredItems.map(\.id) }
        let indexed = Set(resultReferences.map(\.id))
        // Keep optimistic captures selectable until their write publishes the new index.
        return items.filter { !indexed.contains($0.id) }.map(\.id) + resultReferences.map(\.id)
    }

    var selectedItem: ClipboardItem? {
        guard let item = filteredItems.first(where: { $0.id == selectedID }) else { return nil }
        return !isDebugMode && selectedDetail?.id == item.id ? selectedDetail : item
    }
    var isStorageBlocked: Bool { storageBlocked }
    var canCopySelection: Bool {
        !isDebugMode && !selectedIDs.isEmpty && selectedItems.count == selectedIDs.count
            && selectedIDs.isDisjoint(with: unavailableItems) && !isLoading && !isCopying
    }
    var canCombineSelection: Bool { selectedItems.count == selectedIDs.count && ClipboardBatch.canCombine(selectedItems) }
    var hasMoreItems: Bool { !isDebugMode && items.count < matchingCount }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await load()
        if !stopRequested { monitor.start() }
        monitor.setPaused(shouldPauseMonitoring)
        await refreshFileAvailability()
        if !stopRequested { startRetentionChecks() }
    }

    func stop() {
        pasteQueue.cancel()
        stopRequested = true
        monitor.stop()
        retentionTimer?.invalidate()
        retentionTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    func resumeMonitoring() {
        stopRequested = false
        monitor.start()
        monitor.setPaused(shouldPauseMonitoring)
        startRetentionChecks()
    }

    private func load() async {
        isLoading = true
        do {
            let baseline = copyStatistics.isInitialized ? nil : try await persistence.historicalCopyCounts()
            let history = try await persistence.loadSettings()
            if let baseline {
                copyStatistics.initializeIfNeeded(with: baseline)
            }
            isPaused = history.isPaused
            retentionSettings = history.retention ?? .default
            needsRetentionReview = history.retention == nil
            storageBlocked = false
            storageError = nil
            if needsRetentionReview {
                let result = try await persistence.applyRetention(.default)
                if case .applied = result { needsRetentionReview = false }
            } else {
                try await persistence.apply([.maintenance])
            }
            try await refreshResults()
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
            persist([])
            await saveTask?.value
        }
    }

    func setPaused(_ paused: Bool) {
        guard !isDebugMode, !isLoading, !storageBlocked else { return }
        captureGeneration += 1
        isPaused = paused
        monitor.setPaused(shouldPauseMonitoring)
        setNotice(nil)
        persist([.settings(isPaused: isPaused)])
        if !paused { requestClipboardAccessIfNeeded() }
    }

    func requestClipboardAccessIfNeeded() {
        guard !isDebugMode, !isLoading, !storageBlocked else { return }
        clipboardAccessDenied = pasteboard.accessBehavior == .alwaysDeny
        if clipboardAccessDenied { systemAccess.present(.clipboard) }
    }

    func applyRetention(_ settings: ClipboardRetention,
                        confirmed: ClipboardRetentionPlan? = nil) async -> ClipboardRetentionPlan? {
        guard !isDebugMode, !isLoading, !storageBlocked, !isApplyingRetention else { return nil }
        isApplyingRetention = true
        defer { isApplyingRetention = false }
        retentionError = nil
        await flush()
        guard pendingMutations.isEmpty, storageError == nil else {
            retentionError = "Save pending history changes before applying history limits."
            return nil
        }
        do {
            let result = try await persistence.applyRetention(settings, confirmed: confirmed)
            switch result {
            case .confirmationRequired(let plan): return plan
            case .applied:
                retentionSettings = settings
                needsRetentionReview = false
                try await refreshResults()
            }
        } catch {
            retentionError = "Could not apply history limits. \(error.localizedDescription)"
        }
        return nil
    }

    func checkRetention() async {
        guard !stopRequested, !isDebugMode, !isLoading, !storageBlocked, !needsRetentionReview else { return }
        persist([.maintenance])
        await saveTask?.value
    }

    private func startRetentionChecks() {
        guard retentionTimer == nil else { return }
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkRetention() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkRetention() }
        }
    }

    func prepareForPresentation(at date: Date = .now) {
        recentSelectionIDs = nil
        isPreparingPresentation = true
        query = ""
        if !filterPreferences.memory.retainsFilter(closedAt: lastDismissedAt, reopeningAt: date) {
            filter = .all
        }
        isPreparingPresentation = false
        lastDismissedAt = nil
        isPresented = true
        selectedID = filteredItems.first?.id
        copyError = nil
        if !isDebugMode {
            updateRetentionToast()
            updateStorageToast()
        }
        presentationID = UUID()
        let status: String
        if reuseResultsForPresentation() {
            status = "reused"
        } else if scheduleReload() {
            // The current items may still belong to the previous search or type filter.
            selectsFirstResultOnReload = true
            status = "reload"
        } else {
            status = isDebugMode ? "debug" : "unavailable"
        }
        HistoryPerformance.signposter.emitEvent("History Presentation Result",
            "status=\(status, privacy: .public) references=\(self.resultReferences.count, privacy: .public)")
        Task { await refreshFileAvailability() }
    }

    private func reuseResultsForPresentation() -> Bool {
        guard !isLoading, !storageBlocked, !isDebugMode, !isSearching, !isApplyingRetention,
              storageError == nil, pendingMutations.isEmpty, !resultsAreSearch,
              publishedResult?.generation == queryGeneration, publishedResult?.filter == filter else { return false }
        // Discard page loads from the previous viewport before reducing the loaded summaries.
        queryGeneration += 1
        publishedResult?.generation = queryGeneration
        loadedLimit = pageSize
        if items.count > pageSize {
            items = Array(items.prefix(pageSize))
            pruneCaches()
        }
        return true
    }

    func invalidatePresentation(at date: Date = .now) {
        selectsFirstResultOnReload = false
        if isPresented {
            lastDismissedAt = date
            isPresented = false
            autoRecycleUnavailableFilesIfNeeded(at: date)
        }
        presentationID = UUID()
        toasts.dismissTransient()
        systemAccess.dismiss()
    }

    private func autoRecycleUnavailableFilesIfNeeded(at date: Date) {
        guard !stopRequested, !isDebugMode, !isLoading, !storageBlocked, !needsRetentionReview,
              !isDeletingUnavailableFiles, retentionSettings.autoRecycleUnavailableFiles,
              lastAutoRecycleAt.map({ date.timeIntervalSince($0) >= autoRecycleInterval }) ?? true else { return }
        // Reserve the interval before queuing work so rapid dismissals cannot schedule another scan.
        lastAutoRecycleAt = date
        persist([.deleteUnavailableFiles])
    }

    #if DEBUG
    func setDebugMode(_ enabled: Bool) {
        guard isDebugMode != enabled else { return }
        pasteQueue.cancel()
        captureGeneration += 1
        debugItems = enabled ? ClipboardSamples.makeItems() : []
        isDebugMode = enabled
        queryGeneration += 1
        queryTask?.cancel()
        isSearching = false
        monitor.setPaused(shouldPauseMonitoring)
        clearPreview()
        setNotice(nil)
        toasts.dismissAll()
        systemAccess.dismiss()
        prepareForPresentation()
    }
    #endif

    func reconcileSelection() {
        copyError = nil
        selection.reconcile(with: selectionOrder, fallback: filteredItems.first?.id)
    }

    func select(_ id: UUID, command: Bool = false, shift: Bool = false) {
        selectsFirstResultOnReload = false
        selection.select(id, in: selectionOrder, command: command, shift: shift)
        hydrateSelection()
        copyError = nil
    }

    func focusSelection(_ id: UUID) {
        selectsFirstResultOnReload = false
        selection.focus(id)
    }

    func toggleSelectionMark() {
        selectsFirstResultOnReload = false
        selection.toggleMark()
        copyError = nil
    }

    func hasRecentCopies(at date: Date = .now) -> Bool {
        !isDebugMode && recentCopies.batch(at: date).count > 1
    }

    func canSelectRecentCopies(at date: Date = .now) -> Bool {
        !isDebugMode && !isLoading && !isSearching && !isLoadingMore && !isSelectingRecentCopies
            && !isStorageBlocked && query.isEmpty && filter == .all
            && hasRecentCopies(at: date)
            && (recentSelectionIDs ?? recentCopies.batch(at: date)).count > 1
    }

    func selectRecentCopies() async {
        guard canSelectRecentCopies() else { return }
        let candidates = recentSelectionIDs ?? recentCopies.batch(at: .now)
        let presentation = presentationID
        isSelectingRecentCopies = true
        defer { isSelectingRecentCopies = false }
        // A burst may extend beyond the first page of history. Load it before selecting.
        while hasMoreItems && !Set(candidates).isSubset(of: Set(items.map(\.id))) {
            let previousCount = items.count
            await loadMore()
            guard presentationID == presentation, query.isEmpty, filter == .all,
                  !isDebugMode, !isLoading, !isStorageBlocked, !isSearching else { return }
            if items.count == previousCount { return }
        }
        let visibleIDs = Set(filteredItems.map(\.id))
        let available = candidates.filter { visibleIDs.contains($0) }
        guard available.count > 1 else { return }
        recentSelectionIDs = available
        selectsFirstResultOnReload = false
        selection.selectMarked(available)
        copyError = nil
    }

    private func moveSelection(to id: UUID, extending: Bool) {
        selectsFirstResultOnReload = false
        selection.move(to: id, in: selectionOrder, extending: extending)
        hydrateSelection()
        copyError = nil
    }

    func moveSelection(by offset: Int, extending: Bool = false) {
        let order = selectionOrder
        guard !order.isEmpty else { return }
        selectsFirstResultOnReload = false
        let current = order.firstIndex { $0 == selectedID } ?? (offset > 0 ? -1 : order.count)
        if offset > 0, current + offset >= order.count, canLoadBroaderMatches {
            let generation = queryGeneration
            navigationTask = Task { [weak self] in
                guard let self else { return }
                await loadBroaderMatches()
                guard generation == queryGeneration, selectionOrder.count > order.count else { return }
                moveSelection(to: selectionOrder[min(current + offset, selectionOrder.count - 1)], extending: extending)
            }
            return
        }
        moveSelection(to: order[min(max(current + offset, 0), order.count - 1)], extending: extending)
        copyError = nil
    }

    private func hydrateSelection() {
        guard !isDebugMode else { return }
        let loaded = Set(items.map(\.id))
        let missing = resultReferences.indices.filter { selectedIDs.contains(resultReferences[$0].id)
            && !loaded.contains(resultReferences[$0].id) }
        guard let first = missing.first, let last = missing.last else { return }
        navigationTask = Task { await loadHistory(in: first..<(last + 1)) }
    }

    func delete(_ id: UUID) {
        deleteItems([id])
    }

    func deleteItems(_ ids: Set<UUID>) {
        guard !isDebugMode, !storageBlocked, !isLoading, !isCopying else { return }
        let loaded = Set(items.map(\.id))
        if !ids.isSubset(of: loaded) {
            let indices = resultReferences.indices.filter { ids.contains(resultReferences[$0].id) }
            guard let first = indices.first, let last = indices.last else { return }
            let generation = queryGeneration
            navigationTask = Task {
                await loadHistory(in: first..<(last + 1))
                guard generation == queryGeneration, ids.isSubset(of: Set(items.map(\.id))) else { return }
                deleteItems(ids)
            }
            return
        }
        let deleted = items.filter { ids.contains($0.id) }
        guard !deleted.isEmpty else { return }
        if pasteQueue.entries.contains(where: { ids.contains($0.id) }) { pasteQueue.cancel() }
        let index = items.firstIndex(where: { ids.contains($0.id) }) ?? 0
        let cutoff = Date()
        for item in deleted { deletionCutoffs[item.fingerprint] = cutoff }
        let pendingCapture = captureTask
        Task { [weak self] in
            await pendingCapture?.value
            for item in deleted where self?.deletionCutoffs[item.fingerprint] == cutoff {
                self?.deletionCutoffs[item.fingerprint] = nil
            }
        }
        items.removeAll { ids.contains($0.id) }
        resultReferences.removeAll { ids.contains($0.id) }
        let fallback = items.isEmpty ? nil : items[min(index, items.count - 1)].id
        selection.reconcile(with: items.map(\.id), fallback: fallback)
        for item in deleted {
            let id = item.id
            thumbnails[id] = nil
            if previewID == id { clearPreview() }
            missingPreviews.remove(id)
            thumbnailOrder.removeAll { $0 == id }
            unavailableItems.remove(id)
        }
        reconcileSelection()
        totalCount = max(0, totalCount - deleted.count)
        matchingCount = max(0, matchingCount - deleted.count)
        persist(deleted.map { .deleteFingerprint($0.fingerprint) })
    }

    func deleteUnavailableFiles() async {
        guard !isDebugMode, !storageBlocked, !isLoading, !isDeletingUnavailableFiles else { return }
        isDeletingUnavailableFiles = true
        defer { isDeletingUnavailableFiles = false }
        // Finish existing captures so an older capture cannot restore a removed entry.
        await flush()
        guard !isDebugMode, !storageBlocked, storageError == nil else { return }
        persist([.deleteUnavailableFiles])
        await saveTask?.value
        guard storageError == nil else { return }
        await refreshFileAvailability()
        setNotice("Unavailable file entries removed.", style: .success)
    }

    func clearHistory() {
        guard !isDebugMode, !storageBlocked, !isLoading else { return }
        pasteQueue.cancel()
        captureGeneration += 1
        recentCopies = ClipboardRecentCopies()
        recentSelectionIDs = nil
        deletionCutoffs = [:]
        monitor.checkpoint()
        items = []
        resultReferences = []
        failedHistoryIDs = []
        historyRevision = UUID()
        totalCount = 0
        matchingCount = 0
        imageStorageBytes = 0
        selectedDetail = nil
        thumbnails = [:]
        clearPreview()
        missingPreviews = []
        thumbnailOrder = []
        unavailableItems = []
        selectedID = nil
        setNotice(nil)
        copyError = nil
        persist([.clear])
    }

    @discardableResult
    func copySelection(separator: ClipboardTextSeparator = .newline, reversed: Bool = false) async -> Bool {
        guard !pasteQueue.isPasting else { return false }
        pasteQueue.cancel()
        return await copyItems(separator: separator, reversed: reversed)
    }

    @discardableResult
    func copyItem(_ id: UUID, isCurrent: () -> Bool = { true }) async -> Bool {
        await copyItems([id], requestIsCurrent: isCurrent)
    }

    private func copyItems(_ requestedIDs: [UUID]? = nil, separator: ClipboardTextSeparator = .newline,
                           reversed: Bool = false, requestIsCurrent: () -> Bool = { true }) async -> Bool {
        guard !isDebugMode, !isCopying, !isLoading else { return false }
        copiedChangeCount = nil
        isCopying = true
        defer { isCopying = false }
        let presentation = presentationID
        let clipboardSnapshot = pasteboard.changeCount
        // Keep Paste available while searching, but resolve the latest results before copying.
        while isSearching {
            let generation = queryGeneration
            await queryTask?.value
            await saveTask?.value
            guard !Task.isCancelled, requestIsCurrent(), presentationID == presentation, !isDebugMode,
                  storageError == nil, pasteboard.changeCount == clipboardSnapshot else { return false }
            if generation == queryGeneration && isSearching { return false }
        }
        guard !Task.isCancelled, presentationID == presentation, !isDebugMode else { return false }
        let selectionSnapshot = selectedIDs
        var ids = requestedIDs ?? selectionOrder.filter { selectedIDs.contains($0) }
        if reversed { ids.reverse() }
        guard !ids.isEmpty else { return false }
        let generation = queryGeneration
        func isCurrent() -> Bool {
            !Task.isCancelled && requestIsCurrent() && pasteboard.changeCount == clipboardSnapshot
                && presentationID == presentation && generation == queryGeneration && !isDebugMode
                && (requestedIDs != nil || selectedIDs == selectionSnapshot)
        }
        var fullItems: [ClipboardItem] = []
        var failingItem: ClipboardItem?
        do {
            await saveTask?.value
            guard isCurrent() else { return false }
            for id in ids {
                let fullItem: ClipboardItem?
                if let pending = pendingItem(id) { fullItem = pending }
                else { fullItem = try await persistence.item(id) }
                guard isCurrent() else { return false }
                guard let fullItem else {
                    copyError = "An item is no longer available. Select the items again."
                    return false
                }
                fullItems.append(fullItem)
            }
            guard let first = fullItems.first else { return false }
            if fullItems.count > 1 && !ClipboardBatch.canCombine(fullItems) {
                copyError = ClipboardBatch.unsupportedMessage
                return false
            }
            failingItem = first
            switch first.kind {
            case .image:
                var images: [NSPasteboardItem] = []
                for item in fullItems {
                    failingItem = item
                    guard let image = item.image else { throw ClipboardStorageError.missingImage }
                    let data = try await persistence.imageData(image)
                    guard isCurrent() else { return false }
                    let representation = NSPasteboardItem()
                    let type: NSPasteboard.PasteboardType = image.isGIF ? .gifImage : .png
                    guard representation.setData(data, forType: type) else { throw CocoaError(.fileWriteUnknown) }
                    images.append(representation)
                }
                guard isCurrent() else { return false }
                pasteboard.clearContents()
                guard pasteboard.writeObjects(images) else { throw CocoaError(.fileWriteUnknown) }
                copiedChangeCount = pasteboard.changeCount
            case .file:
                try ClipboardFileAccess.withResolvedFiles(fullItems.flatMap(\.files)) { urls, updatedFiles in
                    pasteboard.clearContents()
                    guard pasteboard.writeObjects(urls as [NSURL]) else { throw CocoaError(.fileWriteUnknown) }
                    copiedChangeCount = pasteboard.changeCount
                    var offset = 0
                    for item in fullItems {
                        let end = offset + item.files.count
                        updateFiles(Array(updatedFiles[offset..<end]), for: item.id, replacing: item.files)
                        offset = end
                    }
                }
            default:
                pasteboard.clearContents()
                let text = fullItems.map(\.content).joined(separator: separator.value)
                guard pasteboard.setString(text, forType: .string) else { throw CocoaError(.fileWriteUnknown) }
                copiedChangeCount = pasteboard.changeCount
            }
            monitor.checkpoint()
            let now = Date()
            copyStatistics.recordEvent(at: now)
            var mutations: [ClipboardMutation] = []
            var recents: [ClipboardItem] = []
            for (index, item) in fullItems.enumerated() {
                let copiedAt = now.addingTimeInterval(-Double(index) * 0.001)
                if var recent = items.first(where: { $0.id == item.id }) {
                    recent.copiedAt = copiedAt
                    recents.append(recent)
                }
                mutations.append(.touch(item.id, copiedAt))
                unavailableItems.remove(item.id)
            }
            let copiedIDs = Set(ids)
            items.removeAll { copiedIDs.contains($0.id) }
            items.insert(contentsOf: recents, at: 0)
            persist(mutations)
            copyError = nil
            return true
        } catch {
            monitor.checkpoint()
            if fullItems.count == 1, let item = failingItem, item.kind == .file || item.kind == .image {
                unavailableItems.insert(item.id)
            }
            copyError = failingItem?.kind == .file
                ? "A file is unavailable. Copy the original files again or remove the unavailable entry."
                : "Could not copy this item. \(error.localizedDescription)"
            return false
        }
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
        if selectedDetail?.id == id { selectedDetail = items[index] }
        if persistChanges { persist([.upsert(items[index])]) }
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
        do {
            let thumbnail: NSImage?
            if let image = item.image {
                let bitmap = try await persistence.previewImage(image, thumbnail: true)
                thumbnail = NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
            } else if let file = item.imageFile {
                let preview = try await persistence.previewImageFile(file, thumbnail: true)
                guard thumbnailRequests[item.id] == thumbnailRequest else { return }
                updateFiles([preview.file], for: item.id, replacing: item.files)
                thumbnail = NSImage(cgImage: preview.image, size: NSSize(width: preview.image.width, height: preview.image.height))
            } else {
                return
            }
            guard thumbnailRequests[item.id] == thumbnailRequest,
                  items.contains(where: { $0.id == item.id }) else { return }
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
            if thumbnailRequests[item.id] == thumbnailRequest, items.contains(where: { $0.id == item.id }) {
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
            var animatedData: Data?
            if let image = item.image {
                preview = try await persistence.previewImage(image)
                if image.isGIF, !Task.isCancelled, previewRequestID == requestID {
                    animatedData = try? await persistence.imageData(image)
                }
            } else if let file = item.imageFile {
                let result = try await persistence.previewImageFile(file)
                guard previewRequestID == requestID else { return }
                updateFiles([result.file], for: item.id, replacing: item.files)
                preview = result.image
                animatedData = result.animatedData
            } else {
                return
            }
            guard !Task.isCancelled, previewRequestID == requestID, selectedItem?.id == item.id else { return }
            previewImage = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
            if let animatedData, let image = NSImage(data: animatedData), image.representations.contains(where: {
                guard let bitmap = $0 as? NSBitmapImageRep else { return false }
                return (bitmap.value(forProperty: .frameCount) as? Int ?? 0) > 1
            }) {
                previewAnimatedImage = image
            }
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
        previewAnimatedImage = nil
    }

    func refreshFileAvailability() async {
        fileAvailabilityGeneration += 1
        let generation = fileAvailabilityGeneration
        let fileItems = items.filter { $0.kind == .file }
        let result = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: fileItems.map { item in
                (item.id, try? ClipboardFileAccess.withResolvedFiles(item.files) { _, updated in updated })
            })
        }.value
        guard fileAvailabilityGeneration == generation else { return }
        var changed = false
        let currentIDs = Set(items.map(\.id))
        let imageFileIDs = Set(fileItems.filter(\.hasImagePreview).map(\.id))
        for item in fileItems where currentIDs.contains(item.id) {
            let id = item.id
            if let updated = result[id] ?? nil {
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
        if changed {
            let refreshed = items.filter { item in fileItems.contains { $0.id == item.id && $0.files != item.files } }
            persist(refreshed.map(ClipboardMutation.upsert))
        }
    }

    private func enqueue(_ capture: ClipboardCapture) {
        guard !isDebugMode else { return }
        pasteQueue.cancel()
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
                    if item.image != nil { try await persistence.discardImportedImage(item) }
                    return
                }
                if item.image != nil, !needsRetentionReview,
                   let budget = retentionSettings.maximumImageBytes, item.imageByteCount > budget {
                    try await persistence.discardImportedImage(item)
                    setNotice(ClipboardStorageError.imageBudget.localizedDescription)
                    return
                }
                insert(item)
            } catch {
                if generation == captureGeneration { setNotice(error.localizedDescription) }
            }
        }
    }

    private func insert(_ item: ClipboardItem) {
        copyStatistics.recordEvent(at: item.copiedAt)
        var recent = item
        if let existing = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            recent.id = items.remove(at: existing).id
        }
        // Only external captures enter a batch; pasting old history also updates copiedAt.
        recentCopies.record(recent.id, at: recent.copiedAt)
        if recent.kind == .file {
            fileAvailabilityGeneration += 1
            unavailableItems.remove(recent.id)
            missingPreviews.remove(recent.id)
            thumbnails[recent.id] = nil
            thumbnailRequests[recent.id] = nil
            thumbnailOrder.removeAll { $0 == recent.id }
            if previewID == recent.id { clearPreview() }
        }
        items.insert(recent, at: 0)
        setNotice(nil)
        reconcileSelection()
        persist([.upsert(recent)] + (item.image == nil ? [] : [.completeImageImport(item.id)]))
    }

    private func pruneCaches() {
        let ids = Set(items.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        if let previewID, !ids.contains(previewID) { clearPreview() }
        thumbnailOrder.removeAll { !ids.contains($0) }
        missingPreviews.formIntersection(ids)
        unavailableItems.formIntersection(ids)
    }

    private func setNotice(_ message: String?, style: PasketToast.Style = .warning) {
        notice = message
        toasts.show(message, source: .notice,
                    title: style == .success ? "Cleanup Complete" : "Clipboard Notice", style: style)
    }

    private func updateStorageToast() {
        toasts.show(storageError, source: .storage, title: "History Storage Needs Attention",
                    style: .error, action: .retryStorage)
    }

    private func updateRetentionToast() {
        toasts.show(needsRetentionReview
                    ? "Review history limits to enable automatic cleanup. Your existing history has been kept." : nil,
                    source: .retention, title: "Review History Limits",
                    style: .information, action: .reviewHistory)
    }

    private func persist(_ mutations: [ClipboardMutation]) {
        guard !storageBlocked else { return }
        pendingMutations.append(contentsOf: mutations)
        queryGeneration += 1
        let previousSave = saveTask
        saveTask = Task { [weak self, persistence] in
            await previousSave?.value
            guard let self else { return }
            let batch = pendingMutations
            do {
                if !batch.isEmpty {
                    try await persistence.apply(batch)
                    pendingMutations.removeFirst(batch.count)
                }
                storageError = nil
                if pendingMutations.isEmpty { try await refreshResults() }
            } catch {
                isSearching = false
                storageError = "History could not be saved. Changes may be lost after quitting. \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func scheduleReload() -> Bool {
        guard hasStarted, !isLoading, !storageBlocked, !isDebugMode, !isPreparingPresentation else { return false }
        loadedLimit = pageSize
        searchLevel = .literal
        resetsLoadedResults = true
        queryGeneration += 1
        let generation = queryGeneration
        queryTask?.cancel()
        isSearching = true
        queryTask = Task { [weak self] in
            guard let self else { return }
            await saveTask?.value
            guard !Task.isCancelled, generation == queryGeneration else { return }
            guard pendingMutations.isEmpty else { isSearching = false; return }
            do {
                try await refreshResults()
                if generation == queryGeneration { await refreshFileAvailability() }
            }
            catch is CancellationError { }
            catch { if generation == queryGeneration { storageError = "Could not search history. \(error.localizedDescription)" } }
            if generation == queryGeneration { isSearching = false }
        }
        return true
    }

    private func refreshResults(expanding: Bool = false) async throws {
        let generation = queryGeneration
        let requestedQuery = query
        let requestedFilter = filter
        let isSearch = !ClipboardSearch(requestedQuery).isEmpty
        let resets = resetsLoadedResults
        var level = resets ? ClipboardSearch.Level.literal : searchLevel
        if expanding, let next = level.next { level = next }
        let previousCount = expanding ? resultReferences.count : 0
        let limit = expanding ? loadedLimit + pageSize : loadedLimit
        var snapshot: ClipboardResultSnapshot
        repeat {
            snapshot = try await persistence.resultSnapshot(query: requestedQuery, filter: requestedFilter, limit: limit,
                retainingIDs: resets ? [] : Set(items.map(\.id)), level: level)
            guard generation == queryGeneration, !isDebugMode else { return }
            if !isSearch || snapshot.references.count > previousCount || level.next == nil { break }
            level = level.next!
        } while true
        let page = snapshot.page
        guard generation == queryGeneration, !isDebugMode else { return }
        // Publish the selected item's full metadata together with the result summaries.
        // If navigation changes during the read, resolve the latest selection first.
        var detail: ClipboardItem?
        while true {
            let previousSelection = selectedID
            let selectsFirst = selectsFirstResultOnReload
            let candidates = resets ? page.items.map(\.id) : snapshot.references.map(\.id)
            let nextSelection = selectsFirst ? page.items.first?.id
                : (candidates.first(where: { $0 == previousSelection }) ?? page.items.first?.id)
            if let nextSelection {
                detail = try await persistence.item(nextSelection)
            } else {
                detail = nil
            }
            guard generation == queryGeneration, !isDebugMode else { return }
            if selectedID == previousSelection, selectsFirstResultOnReload == selectsFirst { break }
        }
        items = page.items
        searchLevel = level
        loadedLimit = max(loadedLimit, min(limit, snapshot.references.count))
        resultReferences = snapshot.references
        resultsAreSearch = isSearch
        publishedResult = (generation, requestedFilter)
        failedHistoryIDs = []
        clearHistoryPageError()
        resetsLoadedResults = false
        historyRevision = UUID()
        totalCount = page.totalCount
        matchingCount = page.matchingCount
        imageStorageBytes = page.imageBytes
        textStorageBytes = page.textBytes
        pruneCaches()
        if selectsFirstResultOnReload { selectedID = page.items.first?.id }
        if resets { selection.reconcile(with: page.items.map(\.id), fallback: page.items.first?.id) }
        reconcileSelection()
        selectedDetail = detail
        isSearching = false
        hydrateSelection()
    }

    func loadMore() async {
        guard hasMoreItems, !isLoadingMore, !isSearching, !storageBlocked else { return }
        let loaded = Set(items.map(\.id))
        guard let index = resultReferences.firstIndex(where: { !loaded.contains($0.id) }) else { return }
        await loadHistory(in: index..<min(index + pageSize, resultReferences.count))
    }

    func loadBroaderMatches() async {
        guard canLoadBroaderMatches, !isLoadingBroaderMatches, !isLoadingMore,
              !isSearching, !isLoading, !storageBlocked else { return }
        isLoadingBroaderMatches = true
        defer { isLoadingBroaderMatches = false }
        let generation = queryGeneration
        await saveTask?.value
        guard generation == queryGeneration, pendingMutations.isEmpty else { return }
        do { try await refreshResults(expanding: true) }
        catch is CancellationError { }
        catch {
            if generation == queryGeneration { storageError = "Could not expand search. \(error.localizedDescription)" }
        }
    }

    func loadHistory(in range: Range<Int>) async {
        guard !isDebugMode, !isLoading, !isSearching, !storageBlocked, !range.isEmpty else { return }
        let generation = queryGeneration
        await saveTask?.value
        guard generation == queryGeneration, pendingMutations.isEmpty else { return }
        let start = max(0, range.lowerBound) / pageSize * pageSize
        let end = min(range.upperBound, resultReferences.count)
        guard start < end else { return }
        for offset in stride(from: start, to: end, by: pageSize) {
            guard !Task.isCancelled, generation == queryGeneration else { return }
            let request = PageRequest(generation: generation, offset: offset)
            if let task = pageLoads[request] { await task.value; continue }
            let references = Array(resultReferences[offset..<min(offset + pageSize, resultReferences.count)])
            let loaded = Set(items.map(\.id))
            if references.allSatisfy({ loaded.contains($0.id) }) { continue }
            isLoadingMore = true
            // The shared request survives a viewport task being cancelled during a fast drag.
            let task = Task { [self] in
                defer {
                    pageLoads[request] = nil
                    isLoadingMore = !pageLoads.isEmpty
                }
                do {
                    guard generation == queryGeneration else { return }
                    let page = try await persistence.page(query: query, filter: filter, limit: pageSize, offset: offset,
                                                          level: searchLevel)
                    guard generation == queryGeneration, !isDebugMode else { return }
                    // Offsets are meaningful only for the index that requested them.
                    guard page.items.map(\.id) == references.map(\.id) else {
                        try await refreshResults()
                        return
                    }
                    var loaded = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
                    for item in page.items { loaded[item.id] = item }
                    items = resultReferences.compactMap { loaded[$0.id] }
                    loadedLimit = max(pageSize, resultReferences.prefix { loaded[$0.id] != nil }.count)
                    failedHistoryIDs.subtract(references.map(\.id))
                    if failedHistoryIDs.isEmpty { clearHistoryPageError() }
                    await refreshFileAvailability()
                } catch {
                    guard generation == queryGeneration else { return }
                    failedHistoryIDs.formUnion(references.map(\.id))
                    historyPageError = "Could not load more history. \(error.localizedDescription)"
                    storageError = historyPageError
                }
            }
            pageLoads[request] = task
            await task.value
        }
    }

    private func clearHistoryPageError() {
        if let historyPageError, storageError == historyPageError { storageError = nil }
        historyPageError = nil
    }

    func loadSelection() async {
        guard !isDebugMode, let id = selectedID else { return }
        if let pending = pendingItem(id) { selectedDetail = pending; return }
        let generation = queryGeneration
        do {
            let detail = try await persistence.item(id)
            guard selectedID == id, generation == queryGeneration, !isDebugMode else { return }
            selectedDetail = detail
        } catch {
            copyError = "Could not load this item. \(error.localizedDescription)"
        }
    }

    private func pendingItem(_ id: UUID) -> ClipboardItem? {
        for case .upsert(let item) in pendingMutations.reversed() where item.id == id { return item }
        return nil
    }

    // Used by termination and tests to wait for queued imports and atomic writes.
    func flush() async {
        var generation: Int
        repeat {
            generation = queryGeneration
            await captureTask?.value
            await navigationTask?.value
            await queryTask?.value
            await saveTask?.value
            for task in Array(pageLoads.values) { await task.value }
        } while generation != queryGeneration || !pageLoads.isEmpty
        await loadSelection()
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
    static func makeItems() -> [ClipboardItem] {
        let date = Date()
        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: date) ?? date
        }
        var entries = [
            ClipboardItem.text("A little space for your next big idea.\n\nCollect the things that inspire you, keep useful details close, and pick up right where you left off.",
                               source: ClipboardSource(name: "Notes", bundleIdentifier: "com.apple.Notes"), at: date),
            ClipboardItem.text("https://example.com/design/journal",
                               source: ClipboardSource(name: "Safari", bundleIdentifier: "com.apple.Safari"), at: date),
            ClipboardItem(kind: .image, title: "Mountain afternoon", content: "Sample landscape illustration",
                          source: ClipboardSource(name: "Preview", bundleIdentifier: "com.apple.Preview"),
                          copiedAt: daysAgo(1), fingerprint: "sample:landscape",
                          image: ClipboardImage(fileName: "sample.png", thumbnailName: "sample-thumb.png",
                                                byteCount: 48_000, thumbnailByteCount: 4_000, width: 640, height: 400)),
            ClipboardItem.text("hello@example.com", source: ClipboardSource(name: "Mail", bundleIdentifier: "com.apple.mail"),
                               at: daysAgo(1)),
            ClipboardItem(kind: .file, title: "Brand Guidelines.pdf", content: "/Sample/Documents/Brand Guidelines.pdf",
                          source: ClipboardSource(name: "Finder", bundleIdentifier: "com.apple.finder"),
                          copiedAt: daysAgo(3), fingerprint: "sample:document",
                          files: [ClipboardFile(path: "/Sample/Documents/Brand Guidelines.pdf", name: "Brand Guidelines.pdf",
                                                byteCount: 2_400_000, isSecurityScoped: true)]),
            ClipboardItem.text("Weekend plans\nVisit the bookshop, find a sunny spot, and start a new chapter.",
                               source: ClipboardSource(name: "Notes", bundleIdentifier: "com.apple.Notes"), at: daysAgo(6)),
            ClipboardItem.text("Good design makes room for the things that matter.",
                               source: ClipboardSource(name: "Safari", bundleIdentifier: "com.apple.Safari"), at: daysAgo(12)),
            ClipboardItem.text("https://example.com/reading-list",
                               source: ClipboardSource(name: "Safari", bundleIdentifier: "com.apple.Safari"), at: daysAgo(24)),
            ClipboardItem.text("Project notes\nKeep the first version focused on the essentials.",
                               source: ClipboardSource(name: "Notes", bundleIdentifier: "com.apple.Notes"), at: daysAgo(45)),
            ClipboardItem.text("https://example.com/archive/inspiration",
                               source: ClipboardSource(name: "Safari", bundleIdentifier: "com.apple.Safari"), at: daysAgo(60))
        ]
        for index in entries.indices { entries[index].fingerprint = "sample:\(index)" }
        return entries
    }

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
