import AppKit
import Observation
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct ClipboardTests {
    @Test func filterMemoryStartsOnDismissalAndExpiresOnReopening() async throws {
        let suite = "PasketFilterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = try Fixture(filterPreferences: ClipboardFilterPreferences(defaults: defaults))
        await fixture.start()
        await fixture.copy("https://example.com")
        await fixture.copy("Some text")
        let openedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        fixture.store.prepareForPresentation(at: openedAt)
        fixture.store.filter = .links
        fixture.store.query = "no matching entry"
        await fixture.store.flush()

        let closedAt = openedAt.addingTimeInterval(600)
        fixture.store.invalidatePresentation(at: closedAt)
        fixture.store.prepareForPresentation(at: closedAt.addingTimeInterval(59.999))
        await fixture.store.flush()
        #expect(fixture.store.filter == .links)
        #expect(fixture.store.query.isEmpty)
        #expect(fixture.store.filteredItems.map(\.content) == ["https://example.com"])
        #expect(fixture.store.selectedItem?.kind == .link)

        let nextClose = closedAt.addingTimeInterval(100)
        fixture.store.invalidatePresentation(at: nextClose)
        fixture.store.invalidatePresentation(at: nextClose.addingTimeInterval(30))
        fixture.store.prepareForPresentation(at: nextClose.addingTimeInterval(60))
        await fixture.store.flush()
        #expect(fixture.store.filter == .all)
        #expect(fixture.store.filteredItems.count == 2)
        await fixture.cleanUp()
    }

    @Test func filterMemoryChangesApplyOnNextOpenAndActiveFilterDoesNotSurviveRelaunch() async throws {
        let suite = "PasketFilterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ClipboardFilterPreferences(defaults: defaults)
        let fixture = try Fixture(filterPreferences: preferences)
        await fixture.start()
        let closedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        fixture.store.prepareForPresentation(at: closedAt.addingTimeInterval(-10))
        fixture.store.filter = .images
        fixture.store.invalidatePresentation(at: closedAt)
        preferences.select(.never)
        fixture.store.prepareForPresentation(at: closedAt.addingTimeInterval(1))
        #expect(fixture.store.filter == .all)

        preferences.select(.untilQuit)
        fixture.store.filter = .files
        fixture.store.invalidatePresentation(at: closedAt.addingTimeInterval(2))
        fixture.store.prepareForPresentation(at: closedAt.addingTimeInterval(86_400))
        #expect(fixture.store.filter == .files)
        await fixture.restart()
        fixture.store.prepareForPresentation()
        #expect(fixture.store.filterPreferences.memory == .untilQuit)
        #expect(fixture.store.filter == .all)
        await fixture.cleanUp()
    }

    #if DEBUG
    @Test func debugModeIsolatesSamplesAndPreservesRealHistory() async throws {
        let fixture = try Fixture()
        await fixture.start()
        await fixture.copy("Private clipboard content")
        let originalID = try #require(fixture.store.items.first?.id)
        fixture.store.query = "Private"
        fixture.store.filter = .text

        fixture.store.setDebugMode(true)
        #expect(fixture.store.query.isEmpty)
        #expect(fixture.store.filter == .all)
        #expect(!fixture.store.filteredItems.isEmpty)
        #expect(!fixture.store.displayedItems.contains { $0.id == originalID || $0.content.contains("Private") })
        #expect(fixture.store.selectedItem?.id == fixture.store.displayedItems.first?.id)
        #expect(!fixture.store.canCopySelection)
        #expect(await fixture.store.copySelection() == false)
        #expect(fixture.pasteboard.string(forType: .string) == "Private clipboard content")

        fixture.store.delete(originalID)
        fixture.store.clearHistory()
        await fixture.store.deleteUnavailableFiles()
        fixture.store.setPaused(true)
        await fixture.copy("Copied during screenshot mode")
        #expect(fixture.store.items.map(\.id) == [originalID])
        #expect(!fixture.store.isPaused)

        fixture.store.setDebugMode(false)
        #expect(fixture.store.selectedItem?.id == originalID)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        #expect(fixture.store.items.map(\.id) == [originalID])
        await fixture.copy("Copied after screenshot mode")
        #expect(fixture.store.items.count == 2)
        await fixture.restart()
        #expect(!fixture.store.isDebugMode)
        #expect(fixture.store.items.map(\.content) == ["Copied after screenshot mode", "Private clipboard content"])
        await fixture.cleanUp()
    }

    @Test func debugSamplesSupportFiltersSearchAndImagePreviews() async throws {
        let fixture = try Fixture()
        await fixture.start()
        fixture.store.setPaused(true)
        fixture.store.setDebugMode(true)
        #expect(Set(fixture.store.displayedItems.map(\.kind)) == Set(ClipboardKind.allCases))
        let sections = ClipboardHistorySection.grouping(fixture.store.displayedItems)
        #expect(sections.map(\.period) == ClipboardHistoryPeriod.allCases)
        #expect(sections.allSatisfy { $0.items.count == 2 })
        fixture.store.query = "example.com"
        #expect(!fixture.store.filteredItems.isEmpty)
        #expect(fixture.store.filteredItems.allSatisfy { [.email, .link].contains($0.kind) })
        fixture.store.prepareForPresentation()
        fixture.store.filter = .images
        fixture.store.reconcileSelection()
        let image = try #require(fixture.store.selectedItem)
        await fixture.store.loadThumbnail(for: image)
        await fixture.store.loadPreview(for: image)
        #expect(fixture.store.thumbnails[image.id] != nil)
        #expect(fixture.store.previewImage != nil)
        #expect(fixture.store.previewID == image.id)
        #expect(fixture.store.unavailableItems.isEmpty)
        fixture.store.setDebugMode(false)
        #expect(fixture.store.previewImage == nil)
        #expect(fixture.store.displayedItems.isEmpty)
        #expect(fixture.store.isPaused)
        await fixture.copy("Still paused")
        #expect(fixture.store.items.isEmpty)
        await fixture.cleanUp()
    }
    #endif

    @Test func classificationRequiresAnEntireLinkOrEmail() {
        #expect(ClipboardItem.classify("https://example.com/path?q=1") == .link)
        #expect(ClipboardItem.classify(" \nhttps://example.com/path\n") == .link)
        #expect(ClipboardItem.classify("hello+test@example.com") == .email)
        #expect(ClipboardItem.classify("See https://example.com") == .text)
        #expect(ClipboardItem.classify("Contact hello@example.com today") == .text)
        #expect(ClipboardItem.classify("file:///tmp/example.txt") == .text)
        #expect(ClipboardItem.classify("bad..address@example.com") == .text)
    }

    @Test func legacyJSONMigratesOnceWithoutChangingItsContents() async throws {
        let fixture = try Fixture()
        let persistence = ClipboardPersistence(directory: fixture.directory)
        let image = try await persistence.importImage(Self.smallPNG(), source: .unknown, at: Date())
        let text = ClipboardItem.text(" \nhttps://example.com/path\n", source: .unknown, at: Date().addingTimeInterval(1))
        let history = ClipboardHistory(isPaused: true, items: [text, image])
        let legacyURL = fixture.directory.appendingPathComponent("history.json")
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(history)) as? [String: Any])
        legacy["authorizedFolders"] = [["path": fixture.directory.path, "name": "Legacy folder",
                                         "bookmark": "AQID", "isSecurityScoped": true]]
        let original = try JSONSerialization.data(withJSONObject: legacy)
        try original.write(to: legacyURL)
        await fixture.start()
        #expect(!fixture.store.isStorageBlocked)
        #expect(fixture.store.isPaused)
        #expect(fixture.store.items.map(\.id) == [text.id, image.id])
        #expect(try await persistence.imageData(try #require(image.image)).isEmpty == false)
        #expect(try Data(contentsOf: legacyURL) == original)
        fixture.store.delete(text.id)
        await fixture.restart()
        #expect(fixture.store.items.map(\.id) == [image.id])
        #expect(try Data(contentsOf: legacyURL) == original)
        await fixture.cleanUp()
    }

    @Test func pagesLoadSummariesAndSearchUnloadedFullBodies() async throws {
        let fixture = try Fixture()
        let now = Date()
        let items = (0..<125).map { index in
            ClipboardItem.text(String(repeating: "a", count: 700) + " tail-\(index)-café-中文-%_",
                               source: .unknown, at: now.addingTimeInterval(-Double(index)))
        }
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: items))
        await fixture.start()
        #expect(fixture.store.totalCount == 125)
        #expect(fixture.store.items.count == 50)
        #expect(fixture.store.items.allSatisfy { $0.content.count == 500 })
        #expect(fixture.store.selectedItem?.content == items[0].content)
        await fixture.store.loadMore()
        #expect(fixture.store.items.count == 100)
        #expect(Set(fixture.store.items.map(\.id)).count == 100)
        fixture.store.query = "TAIL-124-CAFE-中文-%_"
        await fixture.store.flush()
        #expect(fixture.store.filteredItems.map(\.id) == [items[124].id])
        #expect(fixture.store.totalCount == 125)
        #expect(await fixture.store.copySelection())
        #expect(fixture.pasteboard.string(forType: .string) == items[124].content)
        await fixture.store.flush()
        fixture.store.query = ""
        await fixture.store.flush()
        #expect(fixture.store.items.count == 50)
        #expect(fixture.store.items.first?.id == items[124].id)
        await fixture.cleanUp()
    }

    @Test(arguments: [false, true])
    func searchPublishesFullDetailsBeforeFinishing(keepsSelection: Bool) async throws {
        let fixture = try Fixture()
        let now = Date()
        let first = ClipboardItem.text(String(repeating: "a", count: 700) + " shared first",
                                       source: .unknown, at: now)
        let second = ClipboardItem.text(String(repeating: "b", count: 800) + " shared second",
                                        source: .unknown, at: now.addingTimeInterval(-1))
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: [first, second]))
        await fixture.start()
        let store = fixture.store
        let expected = keepsSelection ? first : second
        store.query = keepsSelection ? "shared" : "second"
        #expect(store.isSearching)
        withObservationTracking {
            _ = store.isSearching
        } onChange: {
            MainActor.assumeIsolated {
                #expect(store.selectedItem?.id == expected.id)
                #expect(store.selectedItem?.content == expected.content)
            }
        }
        await store.flush()
        #expect(!store.isSearching)
        #expect(store.selectedItem?.content == expected.content)
        #expect(store.items.allSatisfy { $0.content.count == 500 })
        await fixture.cleanUp()
    }

    @Test func pasteStaysAvailableDuringSearchAndCopiesTheLatestResult() async throws {
        let fixture = try Fixture()
        await fixture.start()
        let text = String(repeating: "a", count: 700) + " target"
        await fixture.copy(text)
        await fixture.copy("previous selection")
        fixture.store.selectedID = fixture.store.items.first?.id
        #expect(fixture.store.selectedItem?.content == "previous selection")

        fixture.store.query = "previous"
        fixture.store.query = "target"
        #expect(fixture.store.isSearching)
        #expect(fixture.store.canCopySelection)
        #expect(await fixture.store.copySelection())
        #expect(fixture.pasteboard.string(forType: .string) == text)
        #expect(!fixture.store.isSearching)
        await fixture.cleanUp()
    }

    @Test func pasteDuringSearchDoesNotCopyWhenTheLatestResultsAreEmpty() async throws {
        let fixture = try Fixture()
        await fixture.start()
        await fixture.copy("previous selection")
        let changeCount = fixture.pasteboard.changeCount

        fixture.store.query = "no matching item"
        #expect(fixture.store.isSearching)
        #expect(fixture.store.canCopySelection)
        #expect(await fixture.store.copySelection() == false)
        #expect(fixture.pasteboard.changeCount == changeCount)
        #expect(!fixture.store.canCopySelection)
        #expect(!fixture.store.isCopying)
        await fixture.cleanUp()
    }

    @Test func repeatingAnUnloadedItemPreservesItsIdentity() async throws {
        let fixture = try Fixture()
        let now = Date()
        let items = (0..<75).map {
            ClipboardItem.text("Item \($0)", source: .unknown, at: now.addingTimeInterval(-Double($0)))
        }
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: items))
        await fixture.start()
        #expect(!fixture.store.items.contains { $0.id == items[74].id })
        await fixture.copy(items[74].content)
        #expect(fixture.store.totalCount == 75)
        #expect(fixture.store.items.first?.id == items[74].id)
        await fixture.store.loadMore()
        #expect(fixture.store.items.count == 75)
        #expect(Set(fixture.store.items.map(\.id)).count == 75)
        #expect(!fixture.store.hasMoreItems)
        await fixture.cleanUp()
    }

    @Test func keyboardNavigationLoadsTheNextPage() async throws {
        let fixture = try Fixture()
        let now = Date()
        let items = (0..<65).map {
            ClipboardItem.text("Item \($0)", source: .unknown, at: now.addingTimeInterval(-Double($0)))
        }
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: items))
        await fixture.start()
        fixture.store.selectedID = items[49].id
        fixture.store.moveSelection(by: 1)
        await fixture.store.flush()
        #expect(fixture.store.selectedID == items[50].id)
        #expect(fixture.store.items.count == 65)
        #expect(!fixture.store.hasMoreItems)
        await fixture.cleanUp()
    }

    @Test func deletingAPendingDuplicateUsesItsFingerprint() async throws {
        let fixture = try Fixture()
        let persistence = ClipboardPersistence(directory: fixture.directory)
        let original = ClipboardItem.text("Repeated", source: .unknown, at: Date())
        let repeated = ClipboardItem.text("Repeated", source: .unknown, at: Date())
        try await persistence.apply([.upsert(original)])
        try await persistence.apply([.upsert(repeated), .deleteFingerprint(repeated.fingerprint)])
        #expect(try await persistence.page().totalCount == 0)
        await fixture.cleanUp()
    }

    @Test(arguments: [false, true])
    func mediaImportedAndClearedInOneTransactionIsCollected(commitFirst: Bool) async throws {
        let fixture = try Fixture()
        let persistence = ClipboardPersistence(directory: fixture.directory)
        let png = try Self.smallPNG()
        let first = try await persistence.importImage(png, source: .unknown, at: Date())
        if commitFirst { try await persistence.apply([.upsert(first), .completeImageImport(first.id)]) }
        // A second in-flight capture of the same pixels still needs these files.
        let second = try await persistence.importImage(png, source: .unknown, at: Date())
        if commitFirst { try await persistence.apply([.settings(isPaused: false)]) }
        let image = try #require(first.image)
        try await persistence.apply([.upsert(first), .completeImageImport(first.id), .clear])
        #expect(try await persistence.imageData(image).isEmpty == false)
        try await persistence.discardImportedImage(second)
        await #expect(throws: ClipboardStorageError.self) { try await persistence.imageData(image) }
        await fixture.cleanUp()
    }

    @Test func equalTimestampsHaveStablePagesAndQueryChangesDiscardOlderResults() async throws {
        let fixture = try Fixture()
        let now = Date()
        let items = (0..<110).map { ClipboardItem.text("Item \($0)", source: .unknown, at: now) }
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: items))
        await fixture.start()
        await fixture.store.loadMore()
        await fixture.store.loadMore()
        #expect(fixture.store.items.map(\.id) == items.map(\.id))
        fixture.store.query = "Item 1"
        fixture.store.query = "Item 109"
        fixture.store.filter = .links
        fixture.store.filter = .text
        await fixture.store.flush()
        #expect(fixture.store.items.map(\.id) == [items[109].id])
        #expect(!fixture.store.isSearching)
        fixture.store.clearHistory()
        await fixture.restart()
        #expect(fixture.store.totalCount == 0)
        await fixture.cleanUp()
    }

    @Test func databaseMutationsAreIncrementalAndRollBackTogether() async throws {
        let fixture = try Fixture()
        let persistence = ClipboardPersistence(directory: fixture.directory)
        let first = ClipboardItem.text("First", source: .unknown, at: Date())
        let second = ClipboardItem.text("Second", source: .unknown, at: Date())
        try await persistence.save(ClipboardHistory(items: [first]))
        let database = try ClipboardDatabase(url: fixture.directory.appendingPathComponent("history.sqlite"))
        try database.execute("""
            CREATE TRIGGER protect_existing_item BEFORE UPDATE ON items
            WHEN old.id = '\(first.id.uuidString)'
            BEGIN SELECT RAISE(ABORT, 'Unchanged rows must not be rewritten'); END
            """)
        try await persistence.apply([.upsert(second)])
        var invalid = ClipboardItem.text("Invalid", source: .unknown, at: Date())
        invalid.kind = .image
        await #expect(throws: ClipboardStorageError.self) {
            try await persistence.apply([.delete(first.id), .upsert(invalid)])
        }
        #expect(try await persistence.page().totalCount == 2)
        #expect(try await persistence.item(first.id)?.content == "First")
        await fixture.cleanUp()
    }

    @Test func corruptAndFutureDatabasesArePreservedWithoutFallingBackToJSON() async throws {
        for future in [false, true] {
            let fixture = try Fixture()
            let url = fixture.directory.appendingPathComponent("history.sqlite")
            if future {
                let database = try ClipboardDatabase(url: url)
                try database.execute("PRAGMA user_version = 99")
            } else {
                try Data("Invalid database".utf8).write(to: url)
            }
            let original = try Data(contentsOf: url)
            try JSONEncoder().encode(ClipboardHistory()).write(to: fixture.directory.appendingPathComponent("history.json"))
            await fixture.start()
            #expect(fixture.store.isStorageBlocked)
            await fixture.copy("Must not overwrite")
            #expect(try Data(contentsOf: url) == original)
            await fixture.cleanUp()
        }
    }

    @Test func textHashingAndSearchPreserveEmbeddedNulls() async throws {
        let fixture = try Fixture()
        let persistence = ClipboardPersistence(directory: fixture.directory)
        let text = "Before\0After 中文"
        let item = ClipboardItem.text(text, source: .unknown, at: Date())
        try await persistence.apply([.upsert(item)])
        #expect(try await persistence.page(query: "After 中文").items.map(\.id) == [item.id])
        #expect(try await persistence.item(item.id)?.content == text)
        await fixture.cleanUp()
    }

    @Test func startupDoesNotImportTheExistingClipboard() async throws {
        let fixture = try Fixture()
        fixture.write("Existing content")
        await fixture.start()
        fixture.store.pollClipboard()
        await fixture.store.flush()
        #expect(fixture.store.items.isEmpty)
        await fixture.cleanUp()
    }

    @Test func textLimitsCountCharactersAndLeaveTheClipboardUntouched() async throws {
        let fixture = try Fixture()
        await fixture.start()
        let accepted = String(repeating: "👩🏽‍💻", count: 2_000)
        await fixture.copy(accepted)
        #expect(fixture.store.selectedItem?.content == accepted)
        #expect(fixture.store.items.first?.content.count == 500)
        let oversized = accepted + "x"
        await fixture.copy(oversized)
        #expect(fixture.store.items.count == 1)
        #expect(fixture.store.notice?.contains("2,000") == true)
        #expect(fixture.pasteboard.string(forType: .string) == oversized)
        await fixture.cleanUp()
    }

    @Test func repeatedContentKeepsItsIdentityAndMovesToTheTop() async throws {
        let fixture = try Fixture()
        await fixture.start()
        await fixture.copy("first\n  keep whitespace")
        let original = try #require(fixture.store.items.first)
        await fixture.copy("second")
        fixture.store.selectedID = fixture.store.items.first?.id
        let selection = fixture.store.selectedID
        await fixture.copy(original.content)
        #expect(fixture.store.items.count == 2)
        #expect(fixture.store.items.first?.id == original.id)
        #expect(fixture.store.items.first!.copiedAt >= original.copiedAt)
        #expect(fixture.store.selectedID == selection)
        await fixture.copy(original.content + " ")
        #expect(fixture.store.items.count == 3)
        await fixture.cleanUp()
    }

    @Test func searchUsesTheFullBodyAndFiltersByDetectedType() async throws {
        let fixture = try Fixture()
        await fixture.start()
        let text = String(repeating: "a", count: 600) + " hidden-tail"
        await fixture.copy(text)
        await fixture.copy("https://example.com")
        await fixture.copy("test@example.com")
        fixture.store.query = "hidden-tail"
        await fixture.store.flush()
        fixture.store.reconcileSelection()
        #expect(fixture.store.filteredItems.count == 1)
        #expect(fixture.store.selectedItem?.content == text)
        #expect(await fixture.store.copySelection())
        #expect(fixture.pasteboard.string(forType: .string) == text)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        #expect(fixture.store.totalCount == 3)
        fixture.store.query = ""
        fixture.store.filter = .links
        await fixture.store.flush()
        fixture.store.reconcileSelection()
        #expect(fixture.store.filteredItems.map(\.kind) == [.link])
        fixture.store.filter = .emails
        await fixture.store.flush()
        fixture.store.reconcileSelection()
        #expect(fixture.store.filteredItems.map(\.kind) == [.email])
        await fixture.cleanUp()
    }

    @Test func pausePersistsAndResumeDoesNotBackfill() async throws {
        let fixture = try Fixture()
        await fixture.start()
        await fixture.copy("saved")
        fixture.store.setPaused(true)
        await fixture.copy("paused copy")
        await fixture.restart()
        #expect(fixture.store.isPaused)
        #expect(fixture.store.items.map(\.content) == ["saved"])
        fixture.write("another paused copy")
        fixture.store.setPaused(false)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        #expect(fixture.store.items.map(\.content) == ["saved"])
        await fixture.copy("new copy")
        #expect(fixture.store.items.map(\.content) == ["new copy", "saved"])
        await fixture.cleanUp()
    }

    @Test func deleteAndClearSurviveRestartWithoutChangingTheClipboard() async throws {
        let fixture = try Fixture()
        await fixture.start()
        await fixture.copy("first")
        await fixture.copy("second")
        let id = try #require(fixture.store.items.last?.id)
        fixture.store.delete(id)
        await fixture.restart()
        #expect(fixture.store.items.map(\.content) == ["second"])
        fixture.store.clearHistory()
        await fixture.restart()
        #expect(fixture.store.items.isEmpty)
        #expect(fixture.pasteboard.string(forType: .string) == "second")
        await fixture.cleanUp()
    }

    @Test func deletionDoesNotDiscardAnUnrelatedQueuedCopy() async throws {
        let fixture = try Fixture()
        await fixture.start()
        await fixture.copy("delete this")
        let id = try #require(fixture.store.items.first?.id)
        fixture.write("keep this new copy")
        fixture.store.pollClipboard()
        fixture.store.delete(id)
        await fixture.store.flush()
        #expect(fixture.store.items.map(\.content) == ["keep this new copy"])
        fixture.write("keep this new copy")
        fixture.store.pollClipboard()
        fixture.store.delete(try #require(fixture.store.items.first?.id))
        await fixture.store.flush()
        #expect(fixture.store.items.isEmpty)
        await fixture.cleanUp()
    }

    @Test func confidentialAndTransientContentIsSkipped() async throws {
        let fixture = try Fixture()
        await fixture.start()
        for type in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
            fixture.write("Do not store this")
            fixture.pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(type))
            fixture.store.pollClipboard()
            await fixture.store.flush()
            #expect(fixture.store.items.isEmpty)
        }
        await fixture.cleanUp()
    }

    @Test func sourceMetadataAndIdentitySurvivePersistence() async throws {
        let fixture = try Fixture()
        let item = ClipboardItem.text("source test", source: ClipboardSource(name: "Test Editor", bundleIdentifier: "test.editor"), at: Date())
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: [item]))
        await fixture.start()
        #expect(fixture.store.items.first?.id == item.id)
        #expect(fixture.store.items.first?.source.bundleIdentifier == "test.editor")
        fixture.store.query = "Test Editor"
        await fixture.store.flush()
        #expect(fixture.store.filteredItems.count == 1)
        await fixture.cleanUp()
    }

    @Test func corruptedHistoryIsPreservedAndCollectionStops() async throws {
        let fixture = try Fixture()
        let url = fixture.directory.appendingPathComponent("history.json")
        let damaged = Data("{ broken history".utf8)
        try damaged.write(to: url)
        await fixture.start()
        #expect(fixture.store.isStorageBlocked)
        #expect(fixture.store.storageError != nil)
        await fixture.copy("must not overwrite")
        fixture.store.clearHistory()
        await fixture.store.flush()
        #expect(try Data(contentsOf: url) == damaged)
        await fixture.cleanUp()
    }

    @Test func unsupportedHistoryVersionIsPreserved() async throws {
        let fixture = try Fixture()
        let url = fixture.directory.appendingPathComponent("history.json")
        try JSONEncoder().encode(ClipboardHistory(version: 99)).write(to: url)
        let original = try Data(contentsOf: url)
        await fixture.start()
        #expect(fixture.store.isStorageBlocked)
        #expect(fixture.store.storageError?.contains("newer version") == true)
        #expect(try Data(contentsOf: url) == original)
        await fixture.cleanUp()
    }

    @Test func retentionKeepsTheNewest2026Records() async throws {
        let fixture = try Fixture()
        let items = (0..<2_027).map {
            ClipboardItem.text("Item \($0)", source: .unknown, at: Date().addingTimeInterval(-Double($0)))
        }
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: items))
        await fixture.start()
        #expect(fixture.store.totalCount == 2_026)
        #expect(fixture.store.items.count == 50)
        #expect(fixture.store.items.first?.content == "Item 0")
        let persistence = ClipboardPersistence(directory: fixture.directory)
        #expect(try await persistence.page(limit: 1, offset: 2_025).items.last?.content == "Item 2025")
        await fixture.copy("newest")
        await fixture.restart()
        #expect(fixture.store.totalCount == 2_026)
        #expect(fixture.store.items.first?.content == "newest")
        #expect(try await persistence.page(limit: 1, offset: 2_025).items.last?.content == "Item 2024")
        await fixture.cleanUp()
    }

    @Test func imagesHaveRealThumbnailsAndCanBeCopiedAfterRestart() async throws {
        let fixture = try Fixture()
        await fixture.start()
        let png = try Self.smallPNG()
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setData(png, forType: .png)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let item = try #require(fixture.store.items.first)
        #expect(item.kind == .image)
        #expect(item.image?.width == 8)
        #expect(item.image?.height == 6)
        await fixture.store.loadThumbnail(for: item)
        #expect(fixture.store.thumbnails[item.id] != nil)
        await fixture.restart()
        #expect(await fixture.store.copySelection())
        #expect(fixture.pasteboard.data(forType: .png) != nil)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        #expect(fixture.store.items.count == 1)
        fixture.store.clearHistory()
        await fixture.store.flush()
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.appendingPathComponent("Images").path)
        #expect(files.isEmpty)
        await fixture.cleanUp()
    }

    @Test(arguments: [false, true])
    func screenshotFileHasPreviewsWithoutSavingACopy(hasImageRepresentation: Bool) async throws {
        let fixture = try Fixture()
        await fixture.start()
        let png = try Self.smallPNG()
        let screenshotURL = fixture.directory.appendingPathComponent("Temporary Screenshot.png")
        try png.write(to: screenshotURL)
        fixture.pasteboard.clearContents()
        fixture.pasteboard.writeObjects([screenshotURL as NSURL])
        if hasImageRepresentation {
            fixture.pasteboard.setData(png, forType: .png)
        }
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let item = try #require(fixture.store.selectedItem)
        #expect(item.kind == .file)
        #expect(item.files.first?.path == screenshotURL.resolvingSymlinksInPath().path)
        #expect(item.image == nil)
        fixture.store.filter = .images
        await fixture.store.flush()
        fixture.store.reconcileSelection()
        #expect(fixture.store.filteredItems.map(\.id) == [item.id])
        fixture.store.filter = .files
        await fixture.store.flush()
        #expect(fixture.store.filteredItems.map(\.id) == [item.id])
        await fixture.store.loadThumbnail(for: item)
        await fixture.store.loadPreview(for: item)
        #expect(fixture.store.thumbnails[item.id] != nil)
        #expect(fixture.store.previewImage != nil)
        #expect(await fixture.store.copySelection())
        let copied = fixture.pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(copied?.map { $0.resolvingSymlinksInPath() } == [screenshotURL.resolvingSymlinksInPath()])
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Images").path))
        try FileManager.default.removeItem(at: screenshotURL)
        await fixture.store.refreshFileAvailability()
        #expect(fixture.store.thumbnails[item.id] == nil)
        #expect(fixture.store.previewImage == nil)
        await fixture.restart()
        let restored = try #require(fixture.store.selectedItem)
        #expect(restored.id == item.id)
        await fixture.store.loadThumbnail(for: restored)
        await fixture.store.loadPreview(for: restored)
        #expect(fixture.store.thumbnails[restored.id] == nil)
        #expect(fixture.store.previewImage == nil)
        #expect(fixture.store.missingPreviews.contains(restored.id))
        #expect(!fixture.store.canCopySelection)
        await fixture.cleanUp()
    }

    @Test func existingImageFileReferencesHavePreviewsWithoutMigration() async throws {
        let fixture = try Fixture()
        let url = fixture.directory.appendingPathComponent("Legacy Screenshot.png")
        try Self.smallPNG().write(to: url)
        let source = ClipboardSource(name: "Screenshot Tool", bundleIdentifier: "test.screenshot")
        let item = ClipboardItem(kind: .file, title: url.lastPathComponent, content: url.path, source: source,
                                 copiedAt: Date(), fingerprint: "legacy-image-file", files: [ClipboardFileAccess.capture(url)])
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: [item]))
        await fixture.start()
        let restored = try #require(fixture.store.selectedItem)
        #expect(restored.kind == .file)
        #expect(restored.id == item.id)
        #expect(restored.source.bundleIdentifier == source.bundleIdentifier)
        #expect(restored.copiedAt == item.copiedAt)
        fixture.store.filter = .images
        await fixture.store.flush()
        #expect(fixture.store.filteredItems.map(\.id) == [item.id])
        await fixture.restart()
        await fixture.store.loadThumbnail(for: try #require(fixture.store.selectedItem))
        await fixture.store.loadPreview(for: fixture.store.selectedItem)
        #expect(fixture.store.thumbnails[item.id] != nil)
        #expect(fixture.store.previewImage != nil)
        #expect(await fixture.store.copySelection())
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Images").path))
        await fixture.cleanUp()
    }

    @Test func expiredLegacyScreenshotReferencesKeepAnUnavailablePreview() async throws {
        let fixture = try Fixture()
        let path = fixture.directory.appendingPathComponent("Expired Screenshot.png").path
        let file = ClipboardFile(path: path, name: "Expired Screenshot.png")
        let item = ClipboardItem(kind: .file, title: file.name, content: path, source: .unknown,
                                 copiedAt: Date(), fingerprint: "expired-image-file", files: [file])
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: [item]))
        await fixture.start()
        #expect(fixture.store.selectedItem?.hasImagePreview == true)
        await fixture.store.loadThumbnail(for: item)
        await fixture.store.loadPreview(for: item)
        #expect(fixture.store.thumbnails[item.id] == nil)
        #expect(fixture.store.previewImage == nil)
        #expect(fixture.store.missingPreviews.contains(item.id))
        #expect(!fixture.store.canCopySelection)
        await fixture.cleanUp()
    }

    @Test func multipleImageFilesRemainAGroupOfFileReferences() async throws {
        let fixture = try Fixture()
        await fixture.start()
        let urls = ["First.png", "Second.png"].map { fixture.directory.appendingPathComponent($0) }
        for url in urls { try Self.smallPNG().write(to: url) }
        fixture.pasteboard.clearContents()
        fixture.pasteboard.writeObjects(urls as [NSURL])
        fixture.store.pollClipboard()
        await fixture.store.flush()
        #expect(fixture.store.selectedItem?.kind == .file)
        #expect(fixture.store.selectedItem?.files.count == 2)
        #expect(fixture.store.selectedItem?.hasImagePreview == false)
        #expect(await fixture.store.copySelection())
        await fixture.cleanUp()
    }

    @Test func imageSizeLimitDoesNotSaveOversizedPayloads() async throws {
        let fixture = try Fixture()
        await fixture.start()
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setData(Data(repeating: 0, count: ClipboardLimits.imageBytes + 1), forType: .png)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        #expect(fixture.store.items.isEmpty)
        #expect(fixture.store.notice?.contains("20 MB") == true)
        await fixture.cleanUp()
    }

    @Test(arguments: [false, true])
    func thumbnailFailureDoesNotPreventPreviewingOrCopyingTheOriginalImage(corruptThumbnail: Bool) async throws {
        let fixture = try Fixture()
        await fixture.start()
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setData(try Self.smallPNG(), forType: .png)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let item = try #require(fixture.store.items.first)
        let image = try #require(item.image)
        let thumbnailURL = fixture.directory.appendingPathComponent("Images").appendingPathComponent(image.thumbnailName)
        if corruptThumbnail {
            try Data("Invalid thumbnail".utf8).write(to: thumbnailURL)
        } else {
            try FileManager.default.removeItem(at: thumbnailURL)
        }
        await fixture.store.loadThumbnail(for: item)
        #expect(fixture.store.thumbnails[item.id] == nil)
        await fixture.store.loadPreview(for: item)
        #expect(fixture.store.previewID == item.id)
        #expect(fixture.store.previewImage != nil)
        #expect(!fixture.store.missingPreviews.contains(item.id))
        #expect(fixture.store.canCopySelection)
        #expect(await fixture.store.copySelection())
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("Images").appendingPathComponent(image.fileName))
        #expect(await fixture.store.copySelection() == false)
        #expect(fixture.store.unavailableItems.contains(item.id))
        await fixture.cleanUp()
    }

    @Test func previewUsesTheOriginalWithBoundedResolutionAndClearsOnSelectionChange() async throws {
        let fixture = try Fixture()
        await fixture.start()
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setData(try Self.smallPNG(width: 2_000, height: 1_000), forType: .png)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let item = try #require(fixture.store.selectedItem)
        await fixture.store.loadThumbnail(for: item)
        await fixture.store.loadPreview(for: item)
        let thumbnail = try #require(fixture.store.thumbnails[item.id])
        let preview = try #require(fixture.store.previewImage)
        #expect(thumbnail.size.width == 480)
        #expect(preview.size.width == 1_600)
        #expect(preview.size.height == 800)
        await fixture.copy("Select text instead")
        fixture.store.selectedID = fixture.store.items.first?.id
        await fixture.store.loadPreview(for: fixture.store.selectedItem)
        #expect(fixture.store.previewID == nil)
        #expect(fixture.store.previewImage == nil)
        fixture.store.selectedID = item.id
        await fixture.store.loadPreview(for: item)
        fixture.store.delete(item.id)
        #expect(fixture.store.previewImage == nil)
        await fixture.cleanUp()
    }

    @Test func missingOriginalReportsPreviewFailureEvenWhenThumbnailExists() async throws {
        let fixture = try Fixture()
        await fixture.start()
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setData(try Self.smallPNG(), forType: .png)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let item = try #require(fixture.store.selectedItem)
        let image = try #require(item.image)
        await fixture.store.loadThumbnail(for: item)
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("Images").appendingPathComponent(image.fileName))
        await fixture.store.loadPreview(for: item)
        #expect(fixture.store.thumbnails[item.id] != nil)
        #expect(fixture.store.previewImage == nil)
        #expect(fixture.store.missingPreviews.contains(item.id))
        #expect(fixture.store.unavailableItems.contains(item.id))
        #expect(!fixture.store.canCopySelection)
        await fixture.cleanUp()
    }

    @Test func imageBudgetRetainsTheNewestFiveHundredMegabytes() async throws {
        let fixture = try Fixture()
        let items = (0..<26).map { index in
            let hash = ClipboardItem.digest(Data("Image \(index)".utf8))
            return ClipboardItem(kind: .image, title: "Image \(index)", content: "8 × 6", source: .unknown,
                                 copiedAt: Date().addingTimeInterval(-Double(index)), fingerprint: "image:" + hash,
                                 image: ClipboardImage(fileName: hash + ".png", thumbnailName: hash + ".thumb.png",
                                                       byteCount: ClipboardLimits.imageBytes, thumbnailByteCount: 0, width: 8, height: 6))
        }
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: items))
        await fixture.start()
        #expect(fixture.store.items.count == 25)
        #expect(fixture.store.imageStorageBytes == ClipboardRetention.default.maximumImageBytes)
        #expect(fixture.store.items.last?.title == "Image 24")
        await fixture.cleanUp()
    }

    @Test func failedDeletionSaveKeepsMediaUntilRetrySucceeds() async throws {
        let fixture = try Fixture()
        await fixture.start()
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setData(try Self.smallPNG(), forType: .png)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let item = try #require(fixture.store.items.first)
        let image = try #require(item.image)
        let historyURL = fixture.directory.appendingPathComponent("history.sqlite")
        let imageURL = fixture.directory.appendingPathComponent("Images").appendingPathComponent(image.fileName)
        let original = try Data(contentsOf: historyURL)
        try FileManager.default.removeItem(at: historyURL)
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)
        fixture.store.delete(item.id)
        await fixture.store.flush()
        #expect(fixture.store.storageError != nil)
        #expect(fixture.store.toasts.current?.action == .retryStorage)
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
        let text = String(repeating: "a", count: 900) + " unsaved tail"
        await fixture.copy(text)
        #expect(fixture.store.selectedItem?.content == text)
        try FileManager.default.removeItem(at: historyURL)
        try original.write(to: historyURL)
        await fixture.store.retryStorage()
        #expect(fixture.store.storageError == nil)
        #expect(!fixture.store.toasts.messages.contains { $0.source == .storage })
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
        #expect(fixture.store.items.count == 1)
        #expect(fixture.store.selectedItem?.content == text)
        #expect(await fixture.store.copySelection())
        #expect(fixture.pasteboard.string(forType: .string) == text)
        await fixture.cleanUp()
    }

    @Test func pendingImageImportsAreProtectedFromUnrelatedSaves() async throws {
        let fixture = try Fixture()
        let persistence = ClipboardPersistence(directory: fixture.directory)
        let item = try await persistence.importImage(Self.smallPNG(), source: .unknown, at: Date())
        let image = try #require(item.image)
        try await persistence.save(ClipboardHistory())
        #expect(try await persistence.imageData(image).isEmpty == false)
        try await persistence.save(ClipboardHistory(items: [item]))
        try await persistence.save(ClipboardHistory())
        await #expect(throws: ClipboardStorageError.self) { try await persistence.imageData(image) }
        await fixture.cleanUp()
    }

    @Test func multipleFilesRemainReferencesAndMissingOriginalsAreReported() async throws {
        let fixture = try Fixture()
        await fixture.start()
        let urls = ["First.txt", "Second.txt"].map { fixture.directory.appendingPathComponent($0) }
        for url in urls { try Data("File content".utf8).write(to: url) }
        fixture.pasteboard.clearContents()
        fixture.pasteboard.writeObjects(urls as [NSURL])
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let item = try #require(fixture.store.items.first)
        #expect(item.kind == .file)
        #expect(item.files.count == 2)
        await fixture.restart()
        #expect(await fixture.store.copySelection())
        let copied = fixture.pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(copied?.count == 2)
        try FileManager.default.removeItem(at: urls[0])
        await fixture.store.refreshFileAvailability()
        #expect(fixture.store.unavailableItems.contains(item.id))
        #expect(await fixture.store.copySelection() == false)
        #expect(fixture.store.copyError != nil)
        #expect(fixture.store.toasts.current?.source == .copy)
        #expect(fixture.store.toasts.current?.style == .error)
        fixture.store.delete(item.id)
        await fixture.store.flush()
        #expect(FileManager.default.fileExists(atPath: urls[1].path))
        await fixture.cleanUp()
    }

    @Test func deletingUnavailableFilesScansAllHistoryAndKeepsOriginalFiles() async throws {
        let fixture = try Fixture()
        let persistence = ClipboardPersistence(directory: fixture.directory)
        let originalURL = fixture.directory.appendingPathComponent("Readable.png")
        let originalData = Data("Readable file without an image preview".utf8)
        try originalData.write(to: originalURL)
        let readable = ClipboardFileAccess.capture(originalURL)
        let missing = ClipboardFile(path: fixture.directory.appendingPathComponent("Missing.txt").path, name: "Missing.txt")
        let now = Date()
        let unavailable = ClipboardItem(kind: .file, title: "Missing file", content: missing.path, source: .unknown,
                                        copiedAt: now.addingTimeInterval(-100), fingerprint: "missing", files: [missing])
        let partialGroup = ClipboardItem(kind: .file, title: "Partially missing group", content: "Group", source: .unknown,
                                         copiedAt: now.addingTimeInterval(-101), fingerprint: "group", files: [readable, missing])
        let available = ClipboardItem(kind: .file, title: "Readable file", content: readable.path, source: .unknown,
                                      copiedAt: now.addingTimeInterval(-102), fingerprint: "readable", files: [readable])
        let image = try await persistence.importImage(Self.smallPNG(), source: .unknown, at: now.addingTimeInterval(-103))
        let texts = (0..<55).map {
            ClipboardItem.text("Visible text \($0)", source: .unknown, at: now.addingTimeInterval(-Double($0)))
        }
        try await persistence.save(ClipboardHistory(items: texts + [unavailable, partialGroup, available, image]))
        await fixture.start()
        #expect(fixture.store.items.count == 50)
        #expect(!fixture.store.items.contains { $0.kind == .file })
        fixture.store.filter = .text
        fixture.store.query = "Visible"
        await fixture.store.flush()
        fixture.write("Keep the clipboard unchanged")
        let changeCount = fixture.pasteboard.changeCount

        await fixture.store.deleteUnavailableFiles()
        await fixture.store.flush()

        let expectedIDs = Set((texts + [available, image]).map(\.id))
        #expect(Set(try await persistence.load().items.map(\.id)) == expectedIDs)
        #expect(fixture.store.totalCount == expectedIDs.count)
        #expect(fixture.store.matchingCount == texts.count)
        #expect(fixture.store.filter == .text)
        #expect(fixture.store.query == "Visible")
        #expect(fixture.pasteboard.changeCount == changeCount)
        #expect(try Data(contentsOf: originalURL) == originalData)
        #expect(try await persistence.imageData(try #require(image.image)).isEmpty == false)
        #expect(!fixture.store.isDeletingUnavailableFiles)
        #expect(fixture.store.storageError == nil)
        let completion = try #require(fixture.store.toasts.current)
        #expect(completion.style == .success)
        #expect(completion.message == "Unavailable file entries removed.")
        await fixture.store.deleteUnavailableFiles()
        #expect(fixture.store.toasts.current?.id != completion.id)
        #expect(Set(try await persistence.load().items.map(\.id)) == expectedIDs)
        await fixture.restart()
        #expect(fixture.store.totalCount == expectedIDs.count)
        await fixture.cleanUp()
    }

    @Test func deletingUnavailableFilesRechecksAvailabilityAndReconcilesSelection() async throws {
        let fixture = try Fixture()
        await fixture.start()
        await fixture.copy("Keep this text")
        let textID = try #require(fixture.store.items.first?.id)
        let url = fixture.directory.appendingPathComponent("Restored.png")
        try Self.smallPNG().write(to: url)
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.writeObjects([url as NSURL]))
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let file = try #require(fixture.store.items.first)
        fixture.store.selectedID = file.id
        try FileManager.default.removeItem(at: url)
        await fixture.store.refreshFileAvailability()
        #expect(fixture.store.unavailableItems.contains(file.id))
        try Self.smallPNG().write(to: url)

        await fixture.store.deleteUnavailableFiles()
        #expect(fixture.store.items.contains { $0.id == file.id })
        #expect(!fixture.store.unavailableItems.contains(file.id))
        await fixture.store.loadThumbnail(for: file)
        await fixture.store.loadPreview(for: file)
        #expect(fixture.store.previewID == file.id)
        try FileManager.default.removeItem(at: url)

        await fixture.store.deleteUnavailableFiles()
        #expect(fixture.store.items.map(\.id) == [textID])
        #expect(fixture.store.selectedID == textID)
        #expect(fixture.store.thumbnails[file.id] == nil)
        #expect(fixture.store.previewID == nil)
        #expect(!fixture.store.unavailableItems.contains(file.id))
        #expect(!fixture.store.missingPreviews.contains(file.id))
        await fixture.restart()
        #expect(fixture.store.items.map(\.id) == [textID])
        await fixture.cleanUp()
    }

    @Test func legacyHistoryLoadsWithoutFileAccessSettings() throws {
        let data = Data(#"{"version":1,"isPaused":false,"items":[]}"#.utf8)
        let history = try JSONDecoder().decode(ClipboardHistory.self, from: data)
        #expect(history.items.isEmpty)
        #expect(!history.isPaused)
    }

    @Test func legacyDatabaseFolderPermissionsAreIgnoredAndDroppedOnSave() async throws {
        let fixture = try Fixture()
        let persistence = ClipboardPersistence(directory: fixture.directory)
        let item = ClipboardItem.text("Keep this history", source: .unknown, at: Date())
        try await persistence.save(ClipboardHistory(items: [item]))
        var settings = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ClipboardHistory())) as? [String: Any])
        settings["authorizedFolders"] = [["path": fixture.directory.path, "name": "Legacy folder",
                                           "bookmark": "AQID", "isSecurityScoped": true]]
        let database = try ClipboardDatabase(url: fixture.directory.appendingPathComponent("history.sqlite"))
        try database.execute("UPDATE settings SET payload = ? WHERE id = 1",
                             [.blob(try JSONSerialization.data(withJSONObject: settings))])
        await fixture.start()
        #expect(!fixture.store.isStorageBlocked)
        #expect(fixture.store.items.map(\.id) == [item.id])
        fixture.store.setPaused(true)
        await fixture.restart()
        #expect(fixture.store.isPaused)
        #expect(fixture.store.items.map(\.id) == [item.id])
        try database.query("SELECT payload FROM settings WHERE id = 1") {
            let saved = try #require(JSONSerialization.jsonObject(with: ClipboardDatabase.data($0, 0)) as? [String: Any])
            #expect(saved["authorizedFolders"] == nil)
        }
        await fixture.cleanUp()
    }

    @Test func unreadableImagePreviewDoesNotInvalidateAReadableFile() async throws {
        let fixture = try Fixture()
        await fixture.start()
        let url = fixture.directory.appendingPathComponent("Unsupported.png")
        let original = Data("Readable file without a decodable image".utf8)
        try original.write(to: url)
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.writeObjects([url as NSURL]))
        fixture.store.pollClipboard()
        await fixture.store.flush()
        await fixture.restart()
        let item = try #require(fixture.store.selectedItem)
        #expect(item.kind == .file)
        await fixture.store.loadThumbnail(for: item)
        await fixture.store.loadPreview(for: item)
        #expect(fixture.store.thumbnails[item.id] == nil)
        #expect(fixture.store.previewImage == nil)
        #expect(fixture.store.missingPreviews.contains(item.id))
        #expect(!fixture.store.unavailableItems.contains(item.id))
        #expect(fixture.store.canCopySelection)
        #expect(await fixture.store.copySelection())
        let copied = fixture.pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(copied?.map { $0.resolvingSymlinksInPath() } == [url.resolvingSymlinksInPath()])
        #expect(try Data(contentsOf: url) == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Images").path))
        await fixture.cleanUp()
    }

    @Test func recopyingAnUnavailableFileRefreshesTheExistingEntry() async throws {
        let fixture = try Fixture()
        await fixture.start()
        let url = fixture.directory.appendingPathComponent("Original.png")
        try Self.smallPNG().write(to: url)
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.writeObjects([url as NSURL]))
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let item = try #require(fixture.store.selectedItem)
        await fixture.store.loadPreview(for: item)
        #expect(fixture.store.previewImage != nil)
        try FileManager.default.removeItem(at: url)
        await fixture.store.refreshFileAvailability()
        #expect(fixture.store.unavailableItems.contains(item.id))
        #expect(fixture.store.missingPreviews.contains(item.id))
        #expect(!fixture.store.canCopySelection)

        try Self.smallPNG(width: 12, height: 10).write(to: url)
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.writeObjects([url as NSURL]))
        fixture.store.pollClipboard()
        await fixture.store.flush()
        let refreshed = try #require(fixture.store.selectedItem)
        #expect(refreshed.id == item.id)
        #expect(fixture.store.items.count == 1)
        #expect(!fixture.store.unavailableItems.contains(item.id))
        #expect(!fixture.store.missingPreviews.contains(item.id))
        #expect(fixture.store.canCopySelection)
        await fixture.store.loadThumbnail(for: refreshed)
        await fixture.store.loadPreview(for: refreshed)
        #expect(fixture.store.thumbnails[item.id] != nil)
        #expect(fixture.store.previewImage?.size == NSSize(width: 12, height: 10))
        #expect(await fixture.store.copySelection())
        await fixture.restart()
        #expect(fixture.store.items.count == 1)
        #expect(fixture.store.selectedItem?.id == item.id)
        #expect(fixture.store.canCopySelection)
        await fixture.cleanUp()
    }

    @Test func readOnlyScopedBookmarksPersistAndResolve() async throws {
        let fixture = try Fixture()
        let url = fixture.directory.appendingPathComponent("Bookmarked.txt")
        let original = Data("Bookmarked content".utf8)
        try original.write(to: url)
        let file = ClipboardFileAccess.capture(url)
        #expect(file.isSecurityScoped == true)
        #expect(file.bookmark != nil)
        let stored = try JSONDecoder().decode(ClipboardFile.self, from: JSONEncoder().encode(file))
        #expect(stored.isSecurityScoped == true)
        let data = try ClipboardFileAccess.withResolvedFiles([stored]) { urls, _ in
            try Data(contentsOf: #require(urls.first))
        }
        #expect(data == original)
        await fixture.cleanUp()
    }

    @Test func legacyBookmarksUpgradeWhenCopiedAndPersistTheUpgrade() async throws {
        let fixture = try Fixture()
        let url = fixture.directory.appendingPathComponent("Legacy.txt")
        try Data("Legacy content".utf8).write(to: url)
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let legacy = ClipboardFile(path: url.path, name: url.lastPathComponent, bookmark: bookmark, byteCount: 14)
        let legacyData = try JSONEncoder().encode(legacy)
        #expect(!String(decoding: legacyData, as: UTF8.self).contains("isSecurityScoped"))
        let decoded = try JSONDecoder().decode(ClipboardFile.self, from: legacyData)
        #expect(decoded.isSecurityScoped == nil)
        let item = ClipboardItem(kind: .file, title: legacy.name, content: legacy.path, source: .unknown,
                                 copiedAt: Date(), fingerprint: "legacy-file", files: [decoded])
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: [item]))
        await fixture.start()
        #expect(await fixture.store.copySelection())
        await fixture.restart()
        #expect(fixture.store.items.first?.files.first?.isSecurityScoped == true)
        #expect(await fixture.store.copySelection())
        await fixture.cleanUp()
    }

    private static func smallPNG(width: Int = 8, height: Int = 6) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        context.cgContext.setFillColor(NSColor(deviceRed: 0.2, green: 0.4, blue: 0.8, alpha: 1).cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class Fixture {
    let directory: URL
    let pasteboard = NSPasteboard.withUniqueName()
    var store: ClipboardStore

    init(filterPreferences: ClipboardFilterPreferences? = nil) throws {
        let root = ProcessInfo.processInfo.environment["PASKET_TEST_DIRECTORY"] ?? NSTemporaryDirectory()
        directory = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("pasket-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ClipboardStore(directory: directory, pasteboard: pasteboard, filterPreferences: filterPreferences)
    }

    func start() async {
        await store.start()
        await store.flush()
    }

    func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func copy(_ text: String) async {
        write(text)
        store.pollClipboard()
        await store.flush()
    }

    func restart() async {
        store.stop()
        await store.flush()
        store = ClipboardStore(directory: directory, pasteboard: pasteboard, filterPreferences: store.filterPreferences)
        await start()
    }

    func cleanUp() async {
        store.stop()
        await store.flush()
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }
}
