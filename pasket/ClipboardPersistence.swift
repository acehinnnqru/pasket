import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ClipboardStorageError: LocalizedError {
    case unsupportedVersion, invalidImage, largeImage, invalidHistory, missingImage

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This history was created by a newer version of Pasket. It has been left unchanged."
        case .invalidImage: "This image could not be saved."
        case .largeImage: "Image not saved: the limit is 20 MB and 40 million pixels."
        case .invalidHistory: "The history file is damaged. It has been left unchanged."
        case .missingImage: "This saved image is unavailable. You can delete its history entry."
        }
    }
}

actor ClipboardPersistence {
    let directory: URL
    private var committedImageNames: Set<String> = []
    private var pendingImageNames: Set<String> = []
    private var mediaDirectory: URL { directory.appendingPathComponent("Images", isDirectory: true) }
    private var historyURL: URL { directory.appendingPathComponent("history.json") }

    init(directory: URL) { self.directory = directory }

    static func applicationDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pasket", isDirectory: true)
    }

    func load() throws -> ClipboardHistory {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return ClipboardHistory() }
        let data = try Data(contentsOf: historyURL)
        let history = try JSONDecoder().decode(ClipboardHistory.self, from: data)
        guard history.version == 1 else { throw ClipboardStorageError.unsupportedVersion }
        guard Set(history.items.map(\.id)).count == history.items.count,
              history.items.allSatisfy({ item in
                  if let image = item.image {
                      return item.kind == .image && validImageNames(image) && image.byteCount >= 0 && image.thumbnailByteCount >= 0
                  }
                  if item.kind == .image { return false }
                  if item.kind == .file { return !item.files.isEmpty }
                  return item.content.count <= ClipboardLimits.textCharacters
              }) else { throw ClipboardStorageError.invalidHistory }
        committedImageNames = imageNames(in: history.items)
        try cleanImages()
        return history
    }

    func save(_ history: ClipboardHistory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(history)
        try data.write(to: historyURL, options: .atomic)
        committedImageNames = imageNames(in: history.items)
        pendingImageNames.subtract(committedImageNames)
        try cleanImages()
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
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        pendingImageNames.formUnion([payload.fileName, payload.thumbnailName])
        try (png as Data).write(to: mediaDirectory.appendingPathComponent(payload.fileName), options: .atomic)
        try (thumbnailData as Data).write(to: mediaDirectory.appendingPathComponent(payload.thumbnailName), options: .atomic)
        return ClipboardItem(kind: .image, title: "Image · \(image.width) × \(image.height)", content: "\(image.width) × \(image.height)",
                             source: source, copiedAt: date, fingerprint: "image:" + hash, image: payload)
    }

    func imageData(_ image: ClipboardImage, thumbnail: Bool = false) throws -> Data {
        guard validImageNames(image) else { throw ClipboardStorageError.invalidHistory }
        let url = mediaDirectory.appendingPathComponent(thumbnail ? image.thumbnailName : image.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ClipboardStorageError.missingImage }
        return try Data(contentsOf: url)
    }

    func hasImage(_ image: ClipboardImage) -> Bool {
        validImageNames(image) && FileManager.default.isReadableFile(atPath: mediaDirectory.appendingPathComponent(image.fileName).path)
    }

    func discardImportedImage(_ image: ClipboardImage) throws {
        pendingImageNames.subtract([image.fileName, image.thumbnailName])
        try cleanImages()
    }

    private func imageNames(in items: [ClipboardItem]) -> Set<String> {
        Set(items.compactMap(\.image).flatMap { [$0.fileName, $0.thumbnailName] })
    }

    private func cleanImages() throws {
        guard FileManager.default.fileExists(atPath: mediaDirectory.path) else { return }
        let names = committedImageNames.union(pendingImageNames)
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
