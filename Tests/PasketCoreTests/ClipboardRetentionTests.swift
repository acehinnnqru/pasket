import AppKit
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct ClipboardRetentionTests {
    private let unlimited = ClipboardRetention(maximumItems: nil, maximumTextBytes: nil,
                                                maximumImageBytes: nil, maximumAgeDays: nil)

    @Test func defaultsAndInvalidLimits() {
        #expect(ClipboardRetention.default.maximumItems == 2_026)
        #expect(ClipboardRetention.default.maximumTextBytes == 50 * ClipboardRetention.mebibyte)
        #expect(ClipboardRetention.default.maximumImageBytes == 500 * ClipboardRetention.mebibyte)
        #expect(ClipboardRetention.default.maximumAgeDays == 60)
        #expect(unlimited.isValid)
        #expect(!ClipboardRetention(maximumItems: 0).isValid)
        #expect(!ClipboardRetention(maximumTextBytes: -1).isValid)
        #expect(!ClipboardRetention(maximumImageBytes: Int.max).isValid)
        #expect(!ClipboardRetention(maximumAgeDays: 0).isValid)
    }

    @Test func categoryLimitsDeleteOnlyMatchingEntriesAndIgnoreOriginalFileSize() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let now = Date()
        let oldText = ClipboardItem.text("Old text", source: .unknown, at: now.addingTimeInterval(-5))
        let oldImage = image("old", bytes: 10, at: now.addingTimeInterval(-4))
        let link = ClipboardItem.text("https://example.com", source: .unknown, at: now.addingTimeInterval(-3))
        let email = ClipboardItem.text("a@example.com", source: .unknown, at: now.addingTimeInterval(-2))
        let newImage = image("new", bytes: 10, at: now.addingTimeInterval(-1))
        let file = ClipboardItem(kind: .file, title: "Original", content: fixture.original.path,
                                 source: .unknown, copiedAt: now.addingTimeInterval(-10), fingerprint: "file",
                                 files: [ClipboardFile(path: fixture.original.path, name: "Original", byteCount: 9_000_000_000)])
        let entries = [oldText, oldImage, link, email, newImage, file]
        try await fixture.persistence.save(ClipboardHistory(items: entries, retention: unlimited))
        let settings = ClipboardRetention(maximumItems: nil, maximumTextBytes: link.textByteCount + email.textByteCount,
                                          maximumImageBytes: 10, maximumAgeDays: nil)
        let plan = try await fixture.persistence.previewRetention(settings)
        #expect(Set(plan.entries.map(\.id)) == Set([oldText.id.uuidString, oldImage.id.uuidString]))
        // These synthetic images have no files on disk, so only their records release space.
        #expect(plan.estimatedBytes == plan.entries.reduce(0) { $0 + $1.recordBytes })
        #expect(try await fixture.persistence.page().totalCount == entries.count)
        #expect(try await fixture.persistence.loadSettings().retention == unlimited)
        let result = try await fixture.persistence.applyRetention(settings, confirmed: plan)
        guard case .applied = result else { Issue.record("Expected confirmed cleanup to apply"); return }
        #expect(Set(try await fixture.persistence.load().items.map(\.id)) == Set([link.id, email.id, newImage.id, file.id]))
        #expect(try Data(contentsOf: fixture.original) == Data("Original file".utf8))
    }

    @Test func overlappingRulesCountEachVictimOnceAndRemoveOldestInOrder() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let now = Date()
        let expired = ClipboardItem.text("Expired", source: .unknown, at: now.addingTimeInterval(-61 * 86_400))
        let oldImage = image("old", bytes: 10, at: now.addingTimeInterval(-4))
        let oldText = ClipboardItem.text("Old", source: .unknown, at: now.addingTimeInterval(-3))
        let newImage = image("new", bytes: 10, at: now.addingTimeInterval(-2))
        let newText = ClipboardItem.text("New", source: .unknown, at: now.addingTimeInterval(-1))
        try await fixture.persistence.save(ClipboardHistory(items: [expired, oldImage, oldText, newImage, newText], retention: unlimited))
        let settings = ClipboardRetention(maximumItems: 1, maximumTextBytes: 3, maximumImageBytes: 10, maximumAgeDays: 60)
        let plan = try await fixture.persistence.previewRetention(settings, now: now)
        #expect(plan.count == 4)
        #expect(Set(plan.entries.map(\.id)).count == 4)
        _ = try await fixture.persistence.applyRetention(settings, confirmed: plan, now: now)
        #expect(try await fixture.persistence.load().items.map(\.id) == [newText.id])
    }

    @Test func overflowInOneCategoryDoesNotDeleteNewerOrUnrelatedRecords() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let now = Date()
        let newest = ClipboardItem.text("Keep", source: .unknown, at: now)
        let large = ClipboardItem.text("Too large", source: .unknown, at: now.addingTimeInterval(-1))
        let oldest = ClipboardItem.text("x", source: .unknown, at: now.addingTimeInterval(-2))
        let picture = image("independent", bytes: 100, at: now.addingTimeInterval(-3))
        try await fixture.persistence.save(ClipboardHistory(items: [newest, large, oldest, picture], retention: unlimited))
        let settings = ClipboardRetention(maximumItems: nil, maximumTextBytes: 5, maximumImageBytes: nil, maximumAgeDays: nil)
        let plan = try await fixture.persistence.previewRetention(settings)
        #expect(Set(plan.entries.map(\.id)) == Set([large.id.uuidString, oldest.id.uuidString]))
    }

    @Test func changedVictimsRequireConfirmationEvenWhenCountAndSpaceMatch() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let now = Date()
        let oldest = ClipboardItem.text("Same A", source: .unknown, at: now.addingTimeInterval(-2))
        let newest = ClipboardItem.text("Same B", source: .unknown, at: now.addingTimeInterval(-1))
        try await fixture.persistence.save(ClipboardHistory(items: [oldest, newest], retention: unlimited))
        let settings = ClipboardRetention(maximumItems: 1, maximumTextBytes: nil, maximumImageBytes: nil, maximumAgeDays: nil)
        let preview = try await fixture.persistence.applyRetention(settings)
        guard case .confirmationRequired(let plan) = preview else { Issue.record("Expected confirmation"); return }
        #expect(plan.entries.first?.id == oldest.id.uuidString)
        try await fixture.persistence.apply([.touch(oldest.id, now)])
        let result = try await fixture.persistence.applyRetention(settings, confirmed: plan)
        guard case .confirmationRequired(let updated) = result else { Issue.record("Expected updated confirmation"); return }
        #expect(updated.entries.first?.id == newest.id.uuidString)
        #expect(updated.count == plan.count)
        #expect(updated.estimatedBytes == plan.estimatedBytes)
        #expect(try await fixture.persistence.page().totalCount == 2)
        #expect(try await fixture.persistence.loadSettings().retention == unlimited)
        _ = try await fixture.persistence.applyRetention(settings, confirmed: updated)
        #expect(try await fixture.persistence.load().items.map(\.id) == [oldest.id])
    }

    @Test func newlyExpiredEntriesRequireUpdatedConfirmation() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let now = Date()
        let expired = ClipboardItem.text("Expired", source: .unknown, at: now.addingTimeInterval(-61 * 86_400))
        let expiring = ClipboardItem.text("Expiring", source: .unknown, at: now.addingTimeInterval(-59 * 86_400))
        try await fixture.persistence.save(ClipboardHistory(items: [expired, expiring], retention: unlimited))
        let plan = try await fixture.persistence.previewRetention(.default, now: now)
        #expect(plan.count == 1)
        let result = try await fixture.persistence.applyRetention(.default, confirmed: plan, now: now.addingTimeInterval(2 * 86_400))
        guard case .confirmationRequired(let updated) = result else { Issue.record("Expected updated confirmation"); return }
        #expect(updated.count == 2)
        #expect(try await fixture.persistence.page().totalCount == 2)
    }

    @Test func copyingRenewsExpiryButReadingDoesNot() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let now = Date()
        let viewed = ClipboardItem.text("Viewed", source: .unknown, at: now)
        let copied = ClipboardItem.text("Copied", source: .unknown, at: now)
        try await fixture.persistence.save(ClipboardHistory(items: [viewed, copied], retention: unlimited))
        _ = try await fixture.persistence.item(viewed.id)
        try await fixture.persistence.apply([.touch(copied.id, now.addingTimeInterval(2 * 86_400))])
        let plan = try await fixture.persistence.previewRetention(.default, now: now.addingTimeInterval(61 * 86_400))
        #expect(plan.entries.map(\.id) == [viewed.id.uuidString])
    }

    @Test func settingsPersistAndOtherPreferencesDoNotResetThem() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let settings = ClipboardRetention(maximumItems: 9, maximumTextBytes: nil, maximumImageBytes: 8_000_000, maximumAgeDays: 7)
        let result = try await fixture.persistence.applyRetention(settings)
        guard case .applied = result else { Issue.record("Empty history should not require confirmation"); return }
        try await fixture.persistence.apply([.settings(isPaused: true)])
        #expect(try await ClipboardPersistence(directory: fixture.directory).loadSettings().retention == settings)
        let entries = (0..<12).map { ClipboardItem.text("Record \($0)", source: .unknown, at: Date()) }
        try await fixture.persistence.apply(entries.map(ClipboardMutation.upsert))
        #expect(try await fixture.persistence.page().totalCount == 9)
        _ = try await fixture.persistence.applyRetention(unlimited)
        try await fixture.persistence.apply(entries.map(ClipboardMutation.upsert))
        #expect(try await fixture.persistence.page().totalCount == 12)
    }

    @Test func legacySettingsWaitForReviewWithoutDeletingOnStartupOrOtherWrites() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let expired = ClipboardItem.text("Older history", source: .unknown, at: Date().addingTimeInterval(-70 * 86_400))
        let history = ClipboardHistory(items: [expired], retention: nil)
        try JSONEncoder().encode(history).write(to: fixture.directory.appendingPathComponent("history.json"))
        let pasteboard = NSPasteboard(name: .init("pasket-retention-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let store = ClipboardStore(directory: fixture.directory, pasteboard: pasteboard)
        await store.start()
        #expect(store.needsRetentionReview)
        #expect(store.totalCount == 1)
        store.setPaused(true)
        await store.flush()
        await store.checkRetention()
        #expect(store.totalCount == 1)
        #expect(try await fixture.persistence.loadSettings().retention == nil)
        let plan = try #require(await store.applyRetention(.default))
        #expect(plan.count == 1)
        #expect(store.needsRetentionReview)
        #expect(store.totalCount == 1)
        // Leaving the preview without confirming is cancellation: both settings and history are unchanged.
        #expect(try await fixture.persistence.loadSettings().retention == nil)
        _ = await store.applyRetention(.default, confirmed: plan)
        #expect(!store.needsRetentionReview)
        #expect(store.totalCount == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.original.path))
        store.stop()
        await store.flush()
    }

    @Test func maintenanceExpiresHistoryWhilePausedAndLeavesTheClipboardUntouched() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let item = ClipboardItem.text("History", source: .unknown, at: Date())
        try await fixture.persistence.save(ClipboardHistory(isPaused: true, items: [item]))
        let pasteboard = NSPasteboard(name: .init("pasket-retention-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Current clipboard", forType: .string)
        let store = ClipboardStore(directory: fixture.directory, pasteboard: pasteboard)
        await store.start()
        let database = try ClipboardDatabase(url: fixture.directory.appendingPathComponent("history.sqlite"))
        try database.execute("UPDATE items SET copied_at = ?", [.real(Date().addingTimeInterval(-61 * 86_400).timeIntervalSinceReferenceDate)])
        await store.checkRetention()
        #expect(store.isPaused)
        #expect(store.totalCount == 0)
        #expect(pasteboard.string(forType: .string) == "Current clipboard")
        store.stop()
        await store.flush()
    }

    @Test func failedCleanupRollsBackSettingsAndKeepsImagesUntilConfirmedRetry() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let picture = try await fixture.persistence.importImage(png(), source: .unknown, at: Date())
        try await fixture.persistence.save(ClipboardHistory(items: [picture], retention: unlimited))
        let payload = try #require(picture.image)
        let settings = ClipboardRetention(maximumItems: nil, maximumTextBytes: nil, maximumImageBytes: 1, maximumAgeDays: nil)
        let plan = try await fixture.persistence.previewRetention(settings)
        let database = try ClipboardDatabase(url: fixture.directory.appendingPathComponent("history.sqlite"))
        #expect(plan.estimatedBytes == plan.entries.reduce(0) { $0 + $1.recordBytes } + picture.imageByteCount)
        try database.execute("CREATE TRIGGER fail_cleanup BEFORE DELETE ON items BEGIN SELECT RAISE(ABORT, 'Simulated failure'); END")
        await #expect(throws: ClipboardDatabaseError.self) {
            try await fixture.persistence.applyRetention(settings, confirmed: plan)
        }
        #expect(try await fixture.persistence.loadSettings().retention == unlimited)
        #expect(try await fixture.persistence.page().totalCount == 1)
        #expect(try await fixture.persistence.imageData(payload).isEmpty == false)
        try database.execute("DROP TRIGGER fail_cleanup")
        _ = try await fixture.persistence.applyRetention(settings, confirmed: plan)
        #expect(try await fixture.persistence.page().totalCount == 0)
        await #expect(throws: ClipboardStorageError.self) { try await fixture.persistence.imageData(payload) }
    }

    @Test func imagesExceedingTheEntireBudgetAreSkippedWithoutEvictingExistingHistory() async throws {
        let fixture = try RetentionFixture()
        defer { fixture.remove() }
        let existing = ClipboardItem.text("Keep existing history", source: .unknown, at: Date())
        let settings = ClipboardRetention(maximumItems: nil, maximumTextBytes: nil, maximumImageBytes: 1, maximumAgeDays: nil)
        try await fixture.persistence.save(ClipboardHistory(items: [existing], retention: settings))
        await #expect(throws: ClipboardStorageError.imageBudget) {
            try await fixture.persistence.importImage(png(), source: .unknown, at: Date())
        }
        #expect(try await fixture.persistence.load().items.map(\.id) == [existing.id])
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Images").path))
    }

    private func image(_ name: String, bytes: Int, at date: Date) -> ClipboardItem {
        let hash = ClipboardItem.digest(Data(name.utf8))
        return ClipboardItem(kind: .image, title: name, content: "Image", source: .unknown, copiedAt: date,
                             fingerprint: hash, image: ClipboardImage(fileName: hash + ".png", thumbnailName: hash + ".thumb.png",
                                                                      byteCount: bytes - 1, thumbnailByteCount: 1, width: 2, height: 2))
    }

    private func png() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor private struct RetentionFixture {
    let directory: URL
    let original: URL
    let persistence: ClipboardPersistence

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("pasket-retention-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        original = directory.appendingPathComponent("original.txt")
        try Data("Original file".utf8).write(to: original)
        persistence = ClipboardPersistence(directory: directory)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
