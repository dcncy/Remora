import Testing
import Foundation
import RemoraCore
@testable import RemoraApp

struct FileManagerContextMenuTests {
    @Test
    func downloadActionStaysEnabledForDirectories() {
        #expect(FileManagerContextMenuPolicy.isDownloadDisabled(isDirectory: false) == false)
        #expect(FileManagerContextMenuPolicy.isDownloadDisabled(isDirectory: true) == false)
    }

    @Test
    func batchDownloadIncludesSelectedDirectories() {
        let selectedPaths: Set<String> = ["/logs", "/README.txt"]

        #expect(FileManagerContextMenuPolicy.downloadablePaths(for: selectedPaths) == ["/README.txt", "/logs"])
        #expect(FileManagerContextMenuPolicy.isBatchDownloadDisabled(selectedPaths: selectedPaths) == false)
    }

    @Test
    func detailCopyPathFallsBackToCurrentDirectoryWhenContextMenuOpensOnBlankArea() {
        #expect(
            FileManagerContextCopyPathResolver.detailTargetPath(
                currentPath: "/var/www",
                clickedEntryPath: nil
            ) == "/var/www"
        )
    }

    @Test
    func detailCopyPathUsesClickedEntryWhenContextMenuOpensOnRow() {
        let file = RemoteFileEntry(
            name: "README.md",
            path: "/var/www/README.md",
            size: 128,
            isDirectory: false,
            modifiedAt: Date()
        )

        #expect(
            FileManagerContextCopyPathResolver.detailTargetPath(
                currentPath: "/var/www",
                clickedEntryPath: file.path
            ) == "/var/www/README.md"
        )
    }

    @Test
    func sidebarCopyPathResolvesQuickPathAndRoot() {
        #expect(FileManagerContextCopyPathResolver.sidebarTargetPath(clickedItemPath: "/") == "/")
        #expect(FileManagerContextCopyPathResolver.sidebarTargetPath(clickedItemPath: "/srv/app") == "/srv/app")
        #expect(FileManagerContextCopyPathResolver.sidebarTargetPath(clickedItemPath: nil) == nil)
    }

    @MainActor
    @Test
    func toolbarCopyPathUsesCurrentToolbarPath() {
        let toolbar = FileManagerWindowToolbar()
        var copiedPath: String?
        toolbar.onCopyCurrentPath = { path in
            copiedPath = path
        }

        toolbar.update(currentPath: "/srv/releases/app", canGoBack: true, canGoForward: false)
        toolbar.pathControl.onCopyPath?()

        #expect(copiedPath == "/srv/releases/app")
    }

    @Test
    func pasteTargetDirectoryUsesClickedDirectoryOtherwiseFallsBackToCurrentDirectory() {
        let directory = RemoteFileEntry(
            name: "logs",
            path: "/srv/app/logs",
            size: 0,
            isDirectory: true,
            modifiedAt: Date()
        )
        let file = RemoteFileEntry(
            name: "README.md",
            path: "/srv/app/README.md",
            size: 32,
            isDirectory: false,
            modifiedAt: Date()
        )

        #expect(FileManagerPasteTargetResolver.targetDirectory(currentPath: "/srv/app", clickedEntry: directory) == "/srv/app/logs")
        #expect(FileManagerPasteTargetResolver.targetDirectory(currentPath: "/srv/app", clickedEntry: file) == "/srv/app")
        #expect(FileManagerPasteTargetResolver.targetDirectory(currentPath: "/srv/app", clickedEntry: nil) == "/srv/app")
    }
}
