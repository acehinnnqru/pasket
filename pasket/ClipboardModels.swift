import Foundation
import CryptoKit
import UniformTypeIdentifiers

nonisolated enum ClipboardKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case text, image, file, link, email

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        case .link: "link"
        case .email: "at"
        }
    }
}

nonisolated enum ClipboardFilter: String, CaseIterable, Identifiable, Sendable {
    case all, text, images, files, links, emails

    var id: Self { self }
    var kind: ClipboardKind? {
        switch self {
        case .all: nil
        case .text: .text
        case .images: .image
        case .files: .file
        case .links: .link
        case .emails: .email
        }
    }
    var title: String {
        switch self {
        case .all: "All Types"
        case .text: "Text"
        case .images: "Images"
        case .files: "Files"
        case .links: "Links"
        case .emails: "Emails"
        }
    }
    var symbol: String { kind?.symbol ?? "list.bullet" }
}

nonisolated struct ClipboardSource: Codable, Sendable {
    var name: String
    var bundleIdentifier: String?
    static let unknown = ClipboardSource(name: "Unknown App")
}

nonisolated struct ClipboardFile: Codable, Sendable, Equatable {
    var path: String
    var name: String
    var bookmark: Data?
    var byteCount: Int?
    var isSecurityScoped: Bool? = nil

    var isImage: Bool {
        UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension)?.conforms(to: .image) == true
    }
}

nonisolated struct ClipboardImage: Codable, Sendable {
    var fileName: String
    var thumbnailName: String
    var byteCount: Int
    var thumbnailByteCount: Int
    var width: Int
    var height: Int
}

nonisolated struct ClipboardItem: Identifiable, Codable, Sendable {
    var id = UUID()
    var kind: ClipboardKind
    var title: String
    var content: String
    var source: ClipboardSource
    var copiedAt: Date
    var fingerprint: String
    var image: ClipboardImage?
    var files: [ClipboardFile] = []

    var previewText: String { String(content.prefix(500)) }
    var hasTruncatedPreview: Bool { content.count > 500 }
    var textByteCount: Int { [.text, .link, .email].contains(kind) ? content.utf8.count : 0 }
    var imageByteCount: Int { image.map { $0.byteCount + $0.thumbnailByteCount } ?? 0 }
    var imageFile: ClipboardFile? { kind == .file && files.count == 1 && files[0].isImage ? files[0] : nil }
    var hasImagePreview: Bool { kind == .image || imageFile != nil }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func text(_ text: String, source: ClipboardSource, at date: Date) -> ClipboardItem {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return ClipboardItem(kind: classify(text), title: String(firstLine.prefix(120)), content: text,
                             source: source, copiedAt: date, fingerprint: "text:" + digest(Data(text.utf8)))
    }

    static func classify(_ text: String) -> ClipboardKind {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains(where: \.isWhitespace),
           let url = URLComponents(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           let host = url.host, !host.isEmpty, url.url != nil {
            return .link
        }
        let emailPattern = #"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$"#
        if value.range(of: emailPattern, options: .regularExpression) != nil,
           let local = value.split(separator: "@").first, !local.hasPrefix("."), !local.hasSuffix("."),
           !local.contains("..") {
            return .email
        }
        return .text
    }
}

nonisolated struct ClipboardHistory: Codable, Sendable {
    var version = 1
    var isPaused = false
    var items: [ClipboardItem] = []
    var authorizedFolders: [ClipboardFile] = []

    init(version: Int = 1, isPaused: Bool = false, items: [ClipboardItem] = [], authorizedFolders: [ClipboardFile] = []) {
        self.version = version
        self.isPaused = isPaused
        self.items = items
        self.authorizedFolders = authorizedFolders
    }

    private enum CodingKeys: String, CodingKey { case version, isPaused, items, authorizedFolders }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        isPaused = try container.decode(Bool.self, forKey: .isPaused)
        items = try container.decode([ClipboardItem].self, forKey: .items)
        authorizedFolders = try container.decodeIfPresent([ClipboardFile].self, forKey: .authorizedFolders) ?? []
    }
}

nonisolated enum ClipboardLimits {
    static let textCharacters = 2_000
    static let items = 1_000
    static let textBytes = 50 * 1_024 * 1_024
    static let imageBytes = 20 * 1_024 * 1_024
    static let totalImageBytes = 500 * 1_024 * 1_024
    static let imagePixels = 40_000_000
}
