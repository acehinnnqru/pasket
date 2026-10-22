import Foundation

nonisolated struct ClipboardRetention: Codable, Equatable, Sendable {
    static let mebibyte = 1_024 * 1_024
    static let `default` = ClipboardRetention()

    var maximumItems: Int? = 2_026
    var maximumTextBytes: Int? = 50 * mebibyte
    var maximumImageBytes: Int? = 500 * mebibyte
    var maximumAgeDays: Int? = 60
    var autoRecycleUnavailableFiles = false

    var isValid: Bool {
        [maximumItems, maximumTextBytes, maximumImageBytes, maximumAgeDays]
            .allSatisfy { $0.map { $0 > 0 && $0 <= Int.max / Self.mebibyte } ?? true }
    }
}

extension ClipboardRetention {
    nonisolated private enum CodingKeys: String, CodingKey {
        case maximumItems, maximumTextBytes, maximumImageBytes, maximumAgeDays, autoRecycleUnavailableFiles
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maximumItems = try container.decodeIfPresent(Int.self, forKey: .maximumItems)
        maximumTextBytes = try container.decodeIfPresent(Int.self, forKey: .maximumTextBytes)
        maximumImageBytes = try container.decodeIfPresent(Int.self, forKey: .maximumImageBytes)
        maximumAgeDays = try container.decodeIfPresent(Int.self, forKey: .maximumAgeDays)
        autoRecycleUnavailableFiles = try container.decodeIfPresent(Bool.self, forKey: .autoRecycleUnavailableFiles) ?? false
    }
}

// Only small storage summaries are read when planning cleanup, never full text or images.
nonisolated struct ClipboardRetentionEntry: Equatable, Sendable {
    var id: String
    var copiedAt: Date
    var textBytes: Int
    var imageBytes: Int
    var recordBytes: Int
    var imageName: String
    var thumbnailName: String
}

nonisolated struct ClipboardRetentionPlan: Equatable, Sendable {
    var settings: ClipboardRetention
    var entries: [ClipboardRetentionEntry]
    var estimatedBytes: Int
    var count: Int { entries.count }
}

nonisolated enum ClipboardRetentionResult: Sendable {
    case applied
    case confirmationRequired(ClipboardRetentionPlan)
}
