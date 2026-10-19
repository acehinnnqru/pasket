import AppKit
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct ClipboardTests {
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
        #expect(fixture.store.items.first?.content == accepted)
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
        fixture.store.reconcileSelection()
        #expect(fixture.store.filteredItems.count == 1)
        #expect(fixture.store.selectedItem?.previewText.count == 500)
        #expect(fixture.store.selectedItem?.previewText.contains("hidden-tail") == false)
        #expect(await fixture.store.copySelection())
        #expect(fixture.pasteboard.string(forType: .string) == text)
        fixture.store.pollClipboard()
        await fixture.store.flush()
        #expect(fixture.store.items.count == 3)
        fixture.store.query = ""
        fixture.store.filter = .links
        fixture.store.reconcileSelection()
        #expect(fixture.store.filteredItems.map(\.kind) == [.link])
        fixture.store.filter = .emails
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
        let persistence = ClipboardPersistence(directory: fixture.directory)
        try await persistence.save(ClipboardHistory(version: 99))
        let url = fixture.directory.appendingPathComponent("history.json")
        let original = try Data(contentsOf: url)
        await fixture.start()
        #expect(fixture.store.isStorageBlocked)
        #expect(fixture.store.storageError?.contains("newer version") == true)
        #expect(try Data(contentsOf: url) == original)
        await fixture.cleanUp()
    }

    @Test func retentionKeepsTheNewestThousandRecords() async throws {
        let fixture = try Fixture()
        let items = (0..<1_001).map {
            ClipboardItem.text("Item \($0)", source: .unknown, at: Date().addingTimeInterval(-Double($0)))
        }
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: items))
        await fixture.start()
        #expect(fixture.store.items.count == 1_000)
        #expect(fixture.store.items.first?.content == "Item 0")
        #expect(fixture.store.items.last?.content == "Item 999")
        await fixture.copy("newest")
        await fixture.restart()
        #expect(fixture.store.items.count == 1_000)
        #expect(fixture.store.items.first?.content == "newest")
        #expect(fixture.store.items.last?.content == "Item 998")
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
        #expect(item.files.first?.path == screenshotURL.path)
        #expect(item.image == nil)
        fixture.store.filter = .images
        fixture.store.reconcileSelection()
        #expect(fixture.store.filteredItems.map(\.id) == [item.id])
        fixture.store.filter = .files
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
        #expect(fixture.store.imageStorageBytes == ClipboardLimits.totalImageBytes)
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
        let historyURL = fixture.directory.appendingPathComponent("history.json")
        let imageURL = fixture.directory.appendingPathComponent("Images").appendingPathComponent(image.fileName)
        try FileManager.default.removeItem(at: historyURL)
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)
        fixture.store.delete(item.id)
        await fixture.store.flush()
        #expect(fixture.store.storageError != nil)
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
        try FileManager.default.removeItem(at: historyURL)
        await fixture.store.retryStorage()
        #expect(fixture.store.storageError == nil)
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
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
        fixture.store.delete(item.id)
        await fixture.store.flush()
        #expect(FileManager.default.fileExists(atPath: urls[1].path))
        await fixture.cleanUp()
    }

    @Test func legacyHistoryLoadsWithoutFolderPermissions() throws {
        let data = Data(#"{"version":1,"isPaused":false,"items":[]}"#.utf8)
        let history = try JSONDecoder().decode(ClipboardHistory.self, from: data)
        #expect(history.authorizedFolders.isEmpty)
    }

    @Test func folderAuthorizationCoversExistingAndFutureImageFilesAfterRestart() async throws {
        let fixture = try Fixture()
        let originals = fixture.directory.appendingPathComponent("Originals", isDirectory: true)
        let nested = originals.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let first = originals.appendingPathComponent("First.png")
        let second = nested.appendingPathComponent("Second.png")
        let imageData = try Self.smallPNG()
        try imageData.write(to: first)
        let file = ClipboardFile(path: first.path, name: first.lastPathComponent)
        let item = ClipboardItem(kind: .file, title: file.name, content: file.path, source: .unknown,
                                 copiedAt: Date(), fingerprint: "existing-folder-image", files: [file])
        try await ClipboardPersistence(directory: fixture.directory).save(ClipboardHistory(items: [item]))
        await fixture.start()
        try await fixture.store.addAuthorizedFolder(originals)
        #expect(fixture.store.items.first?.id == item.id)
        #expect(fixture.store.authorizedFolders.count == 1)
        await fixture.restart()
        let folder = try #require(fixture.store.authorizedFolders.first)
        #expect(folder.isSecurityScoped == true)
        #expect(folder.bookmark != nil)
        #expect(fixture.store.unavailableItems.isEmpty)
        #expect(await fixture.store.copySelection())
        await fixture.store.loadPreview(for: fixture.store.selectedItem)
        #expect(fixture.store.previewImage != nil)

        // A new nested file uses the same grant without adding another authorized folder.
        try imageData.write(to: second)
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.writeObjects([second as NSURL]))
        fixture.store.pollClipboard()
        await fixture.store.flush()
        await fixture.restart()
        let newItem = try #require(fixture.store.items.first)
        let storedPath = try #require(newItem.files.first?.path)
        let storedIdentity = try URL(fileURLWithPath: storedPath).resourceValues(forKeys: [.fileResourceIdentifierKey])
            .fileResourceIdentifier as? NSObject
        let originalIdentity = try second.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
        #expect(storedIdentity != nil && storedIdentity == originalIdentity)
        #expect(ClipboardFileAccess.contains(folder, path: storedPath))
        #expect(fixture.store.authorizedFolders == [folder])
        await fixture.store.loadThumbnail(for: newItem)
        await fixture.store.loadPreview(for: newItem)
        #expect(fixture.store.thumbnails[newItem.id] != nil)
        #expect(fixture.store.previewImage != nil)
        #expect(await fixture.store.copySelection())
        #expect(fixture.store.imageStorageBytes == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Images").path))

        try FileManager.default.removeItem(at: second)
        await fixture.store.refreshFileAvailability()
        #expect(fixture.store.unavailableItems.contains(newItem.id))
        #expect(fixture.store.previewImage == nil)
        #expect(await fixture.store.copySelection() == false)
        #expect(FileManager.default.fileExists(atPath: first.path))
        await fixture.cleanUp()
    }

    @Test func folderGrantsCanBeReplacedAndRemovedWithoutDeletingFilesOrHistory() async throws {
        let fixture = try Fixture()
        let folderURL = fixture.directory.appendingPathComponent("Originals", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let original = folderURL.appendingPathComponent("Keep.txt")
        try Data("Keep this file".utf8).write(to: original)
        await fixture.start()
        await fixture.copy("Keep this entry")
        try await fixture.store.addAuthorizedFolder(folderURL)
        try await fixture.store.addAuthorizedFolder(folderURL)
        #expect(fixture.store.authorizedFolders.count == 1)
        await fixture.restart()
        let path = try #require(fixture.store.authorizedFolders.first?.path)
        await fixture.store.removeAuthorizedFolder(path)
        await fixture.restart()
        #expect(fixture.store.authorizedFolders.isEmpty)
        #expect(fixture.store.items.first?.content == "Keep this entry")
        #expect(try String(contentsOf: original, encoding: .utf8) == "Keep this file")
        await fixture.cleanUp()
    }

    @Test func folderGrantUsesDirectoryBoundariesAndResolvesChildrenWithoutChildBookmarks() async throws {
        let fixture = try Fixture()
        let folderURL = fixture.directory.appendingPathComponent("Images", isDirectory: true)
        let childURL = folderURL.appendingPathComponent("Nested/Image.png")
        try FileManager.default.createDirectory(at: childURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let imageData = try Self.smallPNG()
        try imageData.write(to: childURL)
        let folder = try ClipboardFileAccess.captureFolder(folderURL)
        let child = ClipboardFile(path: childURL.path, name: childURL.lastPathComponent)
        #expect(ClipboardFileAccess.contains(folder, path: child.path))
        #expect(!ClipboardFileAccess.contains(folder, path: folderURL.path + "-Other/Image.png"))
        #expect(!ClipboardFileAccess.contains(folder, path: folderURL.path + "/../Outside.png"))
        try ClipboardFileAccess.withResolvedFiles([child], authorizedFolders: [folder]) { urls, updated in
            let contents = try Data(contentsOf: urls[0])
            #expect(contents == imageData)
            #expect(updated[0].bookmark == nil)
            #expect(updated[0].isSecurityScoped == nil)
        }
        let persistence = ClipboardPersistence(directory: fixture.directory.appendingPathComponent("History"))
        let preview = try await persistence.previewImageFile(child, authorizedFolders: [folder])
        #expect(preview.image.width == 8)
        #expect(preview.image.height == 6)
        await fixture.cleanUp()
    }

    @Test func authorizingAFileAsAFolderFailsWithoutRecordingAGrant() async throws {
        let fixture = try Fixture()
        let fileURL = fixture.directory.appendingPathComponent("File.txt")
        try Data("Not a folder".utf8).write(to: fileURL)
        await fixture.start()
        await #expect(throws: (any Error).self) { try await fixture.store.addAuthorizedFolder(fileURL) }
        #expect(fixture.store.authorizedFolders.isEmpty)
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

    init() throws {
        let root = ProcessInfo.processInfo.environment["PASKET_TEST_DIRECTORY"] ?? NSTemporaryDirectory()
        directory = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("pasket-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ClipboardStore(directory: directory, pasteboard: pasteboard)
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
        store = ClipboardStore(directory: directory, pasteboard: pasteboard)
        await start()
    }

    func cleanUp() async {
        store.stop()
        await store.flush()
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }
}
