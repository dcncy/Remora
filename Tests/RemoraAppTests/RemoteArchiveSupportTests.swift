import Foundation
import Testing
@testable import RemoraApp
@testable import RemoraCore

struct RemoteArchiveSupportTests {
    @Test
    func capabilityProbeParsesAvailableTools() {
        let toolchain = RemoteArchiveCommandBuilder.parseCapabilityProbeOutput(
            """
            tar=OK
            zip=OK
            unzip=MISSING
            sevenZip=7zz
            unrar=MISSING
            gzip=OK
            """
        )

        #expect(toolchain.tarAvailable)
        #expect(toolchain.zipAvailable)
        #expect(toolchain.unzipAvailable == false)
        #expect(toolchain.sevenZipCommand == "7zz")
        #expect(toolchain.unrarAvailable == false)
        #expect(toolchain.gzipAvailable)
    }

    @Test
    func sameNameDirectoryDropsArchiveSuffix() {
        #expect(
            RemoteArchiveCommandBuilder.sameNameDirectory(
                for: "/home/app/logs.tar.gz",
                format: .tarGz
            ) == "/home/app/logs"
        )
        #expect(
            RemoteArchiveCommandBuilder.sameNameDirectory(
                for: "/backup/demo.7z",
                format: .sevenZip
            ) == "/backup/demo"
        )
    }

    @Test
    func unsafeArchiveEntriesAreRejected() throws {
        #expect(throws: ArchiveSupportError.self) {
            try RemoteArchiveCommandBuilder.validateSafeArchiveEntries([
                "logs/app.log",
                "../etc/passwd",
            ])
        }
    }

    @Test
    func compressionScriptUsesRemoteCommandsOnly() throws {
        let toolchain = RemoteArchiveToolchain(
            tarAvailable: true,
            zipAvailable: true,
            unzipAvailable: true,
            sevenZipCommand: "7z",
            unrarAvailable: true,
            gzipAvailable: true
        )

        let script = try RemoteArchiveCommandBuilder.compressionScript(
            parentDirectory: "/srv/app",
            sourceNames: ["logs", "README.md"],
            destinationPath: "/srv/app/archive.tar.gz",
            format: .tarGz,
            toolchain: toolchain
        )

        #expect(script.contains("tar -czf"))
        #expect(script.contains("-C '/srv/app'"))
        #expect(script.contains("'logs' 'README.md'"))
        #expect(!script.contains("upload"))
        #expect(!script.contains("download"))
    }

    @Test
    func mockSFTPClientExecutesRemoteArchiveRoundTrip() async throws {
        let client = MockSFTPClient()
        let toolchain = RemoteArchiveToolchain(
            tarAvailable: true,
            zipAvailable: true,
            unzipAvailable: true,
            sevenZipCommand: "7z",
            unrarAvailable: true,
            gzipAvailable: true
        )

        let compressCommand = try RemoteArchiveCommandBuilder.compressionScript(
            parentDirectory: "/",
            sourceNames: ["logs"],
            destinationPath: "/logs-backup.tar.gz",
            format: .tarGz,
            toolchain: toolchain
        )
        _ = try await client.executeRemoteShellCommand(compressCommand, timeout: 30)

        let archive = try await client.stat(path: "/logs-backup.tar.gz")
        #expect(archive.isDirectory == false)

        let listCommand = try RemoteArchiveCommandBuilder.listArchiveEntriesScript(
            archivePath: "/logs-backup.tar.gz",
            format: .tarGz,
            toolchain: toolchain
        )
        let listed = try await client.executeRemoteShellCommand(listCommand, timeout: 30)
        #expect(listed.contains("logs/app.log"))

        let extractCommand = try RemoteArchiveCommandBuilder.extractArchiveScript(
            archivePath: "/logs-backup.tar.gz",
            destinationDirectory: "/restored",
            format: .tarGz,
            toolchain: toolchain
        )
        _ = try await client.executeRemoteShellCommand(extractCommand, timeout: 30)

        let restored = try await client.stat(path: "/restored/logs/app.log")
        #expect(restored.isDirectory == false)
    }

    @MainActor
    @Test
    func remoteClipboardTracksConnectionMetadata() async throws {
        let vm = FileTransferViewModel(sftpClient: MockSFTPClient(), remoteDirectoryPath: "/logs")
        vm.bindSFTPClient(MockSFTPClient(), bindingKey: "host-a", initialRemoteDirectory: "/logs")
        vm.copyRemoteEntries(paths: ["/logs/app.log"], mode: .copy)

        let clipboard = try #require(vm.remoteClipboard)
        #expect(clipboard.sourceConnectionID == "host-a")
        #expect(clipboard.sourceParentDirectory == "/logs")
        #expect(clipboard.items.map(\.name) == ["app.log"])
    }

    @MainActor
    @Test
    func pasteIsBlockedAcrossConnections() async throws {
        let vm = FileTransferViewModel(sftpClient: MockSFTPClient(), remoteDirectoryPath: "/")
        vm.bindSFTPClient(MockSFTPClient(), bindingKey: "host-a", initialRemoteDirectory: "/")
        vm.copyRemoteEntries(paths: ["/logs/app.log"], mode: .copy)
        vm.bindSFTPClient(MockSFTPClient(), bindingKey: "host-b", initialRemoteDirectory: "/")

        let result = await vm.pasteRemoteEntriesResult(into: "/")
        #expect(result == .blockedCrossConnection)
    }

    @MainActor
    @Test
    func cloneNamingUsesCopySuffixAndPreservesCompoundExtension() async throws {
        let vm = FileTransferViewModel(sftpClient: MockSFTPClient(), remoteDirectoryPath: "/")
        let next = try await vm.nextClonePathForTests("/archive.tar.gz", isDirectory: false)
        #expect(next == "/archive copy.tar.gz")
    }

    @MainActor
    @Test
    func pasteKeepsClipboardForCopyButClearsForCut() async throws {
        let copyVM = FileTransferViewModel(sftpClient: MockSFTPClient(), remoteDirectoryPath: "/")
        copyVM.bindSFTPClient(MockSFTPClient(), bindingKey: "host-a", initialRemoteDirectory: "/")
        copyVM.copyRemoteEntries(paths: ["/README.txt"], mode: .copy)
        let copyResult = await copyVM.pasteRemoteEntriesResult(into: "/logs")
        #expect(copyResult == .success(destinationDirectory: "/logs", pastedCount: 1, clearsClipboard: false))
        #expect(copyVM.remoteClipboard != nil)

        let cutVM = FileTransferViewModel(sftpClient: MockSFTPClient(), remoteDirectoryPath: "/")
        cutVM.bindSFTPClient(MockSFTPClient(), bindingKey: "host-a", initialRemoteDirectory: "/")
        cutVM.copyRemoteEntries(paths: ["/README.txt"], mode: .cut)
        let cutResult = await cutVM.pasteRemoteEntriesResult(into: "/logs")
        #expect(cutResult == .success(destinationDirectory: "/logs", pastedCount: 1, clearsClipboard: true))
        #expect(cutVM.remoteClipboard == nil)
    }

    @MainActor
    @Test
    func moveRemoteEntriesResultReturnsMovedCount() async throws {
        let vm = FileTransferViewModel(sftpClient: MockSFTPClient(), remoteDirectoryPath: "/")
        let movedCount = await vm.moveRemoteEntriesResult(paths: ["/README.txt"], toDirectory: "/logs")
        #expect(movedCount == 1)
        await vm.refreshRemoteEntries()
        vm.navigateRemote(to: "/logs")
        await vm.refreshRemoteEntries()
        #expect(vm.remoteEntries.contains(where: { $0.path == "/logs/README.txt" }))
    }
}
