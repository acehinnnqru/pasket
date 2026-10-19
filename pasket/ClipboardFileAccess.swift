import AppKit

nonisolated enum ClipboardFileAccess {
    static func capture(_ url: URL) -> ClipboardFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let scopedBookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                 includingResourceValuesForKeys: nil, relativeTo: nil)
        let bookmark = scopedBookmark ?? (try? url.bookmarkData(options: [.minimalBookmark, .withoutImplicitSecurityScope],
                                                              includingResourceValuesForKeys: nil, relativeTo: nil))
        return ClipboardFile(path: url.path, name: url.lastPathComponent,
                             bookmark: bookmark,
                             byteCount: (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                             isSecurityScoped: scopedBookmark != nil)
    }

    static func withResolvedFiles<T>(_ files: [ClipboardFile], body: ([URL], [ClipboardFile]) throws -> T) throws -> T {
        var accessedURLs: [URL] = []
        defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        var urls: [URL] = []
        var updatedFiles: [ClipboardFile] = []
        for file in files {
            var stale = false
            let options: URL.BookmarkResolutionOptions = file.isSecurityScoped == true
                ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting]
            let bookmarked = file.bookmark.flatMap {
                try? URL(resolvingBookmarkData: $0, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
            }
            let url = bookmarked ?? URL(fileURLWithPath: file.path)
            if url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw CocoaError(.fileReadNoPermission)
            }
            urls.append(url)
            // Upgrade legacy bookmarks while the file remains accessible.
            updatedFiles.append(stale || url.path != file.path || file.isSecurityScoped != true ? capture(url) : file)
        }
        return try body(urls, updatedFiles)
    }

    static func areAvailable(_ files: [ClipboardFile]) -> Bool {
        (try? withResolvedFiles(files) { _, _ in true }) ?? false
    }
}
