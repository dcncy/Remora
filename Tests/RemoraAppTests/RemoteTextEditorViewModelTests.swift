import Foundation
import Testing
import RemoraCore
@testable import RemoraApp

struct RemoteTextEditorViewModelTests {
    @Test
    @MainActor
    func editorLoadsAndSavesTextThroughViewModel() async throws {
        let fileTransfer = FileTransferViewModel(
            sftpClient: MockSFTPClient(),
            remoteDirectoryPath: "/"
        )
        let viewModel = RemoteTextEditorViewModel(
            path: "/README.txt",
            fileTransfer: fileTransfer
        )

        await viewModel.load()
        #expect(viewModel.text.contains("Remora"))

        let updated = viewModel.text + "\nupdated"
        await viewModel.save(text: updated)
        #expect(viewModel.text.contains("updated"))
    }

    @Test
    @MainActor
    func editorCanQueueDownloadForCurrentFile() async throws {
        let fileTransfer = FileTransferViewModel(
            sftpClient: MockSFTPClient(),
            remoteDirectoryPath: "/"
        )
        let viewModel = RemoteTextEditorViewModel(
            path: "/README.txt",
            fileTransfer: fileTransfer
        )

        let queued = await viewModel.queueDownload()

        #expect(queued)
        #expect(fileTransfer.transferQueue.count == 1)
        #expect(fileTransfer.transferQueue.first?.direction == .download)
        #expect(fileTransfer.transferQueue.first?.sourcePath == "/README.txt")
    }
}
