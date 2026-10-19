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

    static func captureFolder(_ url: URL) throws -> ClipboardFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        // A folder grant must never silently fall back to a bookmark without persistent access.
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        return ClipboardFile(path: canonical.path, name: canonical.lastPathComponent, bookmark: bookmark, isSecurityScoped: true)
    }

    static func contains(_ folder: ClipboardFile, path: String) -> Bool {
        relativeComponents(path, to: folder.path) != nil
    }

    private static func relativeComponents(_ path: String, to folder: String) -> [String]? {
        let root = URL(fileURLWithPath: folder).standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let child = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard child.starts(with: root) else { return nil }
        return Array(child.dropFirst(root.count))
    }

    static func refreshedFolders(_ folders: [ClipboardFile]) -> [ClipboardFile] {
        folders.map { folder in
            var stale = false
            guard folder.isSecurityScoped == true, let bookmark = folder.bookmark,
                  let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  stale || url.path != folder.path else { return folder }
            return (try? captureFolder(url)) ?? folder
        }
    }

    static func withResolvedFiles<T>(_ files: [ClipboardFile], authorizedFolders: [ClipboardFile] = [],
                                     body: ([URL], [ClipboardFile]) throws -> T) throws -> T {
        var accessedURLs: [URL] = []
        defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        // Keep folder scopes open until all reading or pasteboard writing has finished.
        var resolvedFolders: [(ClipboardFile, URL)] = []
        for folder in authorizedFolders where folder.isSecurityScoped == true {
            var stale = false
            guard let bookmark = folder.bookmark,
                  let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                     relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            if url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
            resolvedFolders.append((folder, url))
        }
        var urls: [URL] = []
        var updatedFiles: [ClipboardFile] = []
        for file in files {
            var stale = false
            let options: URL.BookmarkResolutionOptions = file.isSecurityScoped == true
                ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting]
            let bookmarked = file.bookmark.flatMap {
                try? URL(resolvingBookmarkData: $0, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
            }
            let relocated = resolvedFolders.lazy.compactMap { folder, root -> URL? in
                guard let suffix = relativeComponents(file.path, to: folder.path) else { return nil }
                return suffix.reduce(root) { $0.appendingPathComponent($1) }
            }.first
            let url = bookmarked ?? relocated ?? URL(fileURLWithPath: file.path)
            if url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw CocoaError(.fileReadNoPermission)
            }
            urls.append(url)
            if resolvedFolders.contains(where: { contains(
                ClipboardFile(path: $0.1.path, name: $0.1.lastPathComponent), path: url.path
            ) }) {
                // Reuse the folder grant without creating a separate grant for each child.
                var updated = file
                updated.path = url.path
                updated.name = url.lastPathComponent
                updatedFiles.append(updated)
            } else {
                // Upgrade legacy bookmarks while the file remains accessible.
                updatedFiles.append(stale || url.path != file.path || file.isSecurityScoped != true ? capture(url) : file)
            }
        }
        return try body(urls, updatedFiles)
    }

    static func areAvailable(_ files: [ClipboardFile], authorizedFolders: [ClipboardFile] = []) -> Bool {
        (try? withResolvedFiles(files, authorizedFolders: authorizedFolders) { _, _ in true }) ?? false
    }
}
