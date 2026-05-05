import Foundation

@MainActor
final class RemoteTextEditorViewModel: ObservableObject {
    enum SaveStatus: Equatable {
        case idle
        case saving
        case failed(String)
    }

    @Published var text: String = ""
    @Published private(set) var encodingLabel: String = "UTF-8"
    @Published private(set) var isLoading = false
    @Published private(set) var isDirty = false
    @Published private(set) var saveStatus: SaveStatus = .idle
    @Published var errorMessage: String?

    let path: String
    let language: EditorLanguage

    private let fileTransfer: FileTransferViewModel
    private let loadOptions: RemoteTextDocumentLoadOptions
    private var expectedModifiedAt: Date?
    private var saveRequestGeneration = 0
    private var contentVersionGeneration = 0

    init(
        path: String,
        loadOptions: RemoteTextDocumentLoadOptions = RemoteTextDocumentLoadOptions(),
        fileTransfer: FileTransferViewModel
    ) {
        self.path = path
        self.loadOptions = loadOptions
        self.fileTransfer = fileTransfer
        self.language = .infer(from: path)
    }

    var saveRequestID: Int {
        saveRequestGeneration
    }

    var contentVersion: Int {
        contentVersionGeneration
    }

    func load() async {
        isLoading = true
        EditorDebugLog.log("viewModel.load path=\(path)")
        defer { isLoading = false }

        do {
            let doc = try await fileTransfer.loadTextDocument(path: path, options: loadOptions)
            text = doc.text
            encodingLabel = doc.encoding
            expectedModifiedAt = doc.modifiedAt
            contentVersionGeneration += 1
            isDirty = false
            EditorDebugLog.log("viewModel.load success chars=\(doc.text.count) contentVersion=\(contentVersionGeneration)")
            errorMessage = nil
        } catch let error as RemoteTextDocumentError {
            switch error {
            case .fileTooLarge(let actualBytes, let maxBytes):
                let actualText = ByteSizeFormatter.format(actualBytes)
                let maxText = ByteSizeFormatter.format(maxBytes)
                errorMessage = String(
                    format: tr("File is too large to edit in-app (%@ > %@). Please download and open it locally."),
                    actualText,
                    maxText
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestSave() {
        guard !isLoading, saveStatus != .saving else { return }
        saveRequestGeneration += 1
        EditorDebugLog.log("viewModel.requestSave saveRequestID=\(saveRequestGeneration)")
    }

    func markDirty() {
        if !isDirty {
            isDirty = true
            EditorDebugLog.log("viewModel.markDirty")
        }
    }

    func save(text: String) async {
        saveStatus = .saving
        self.text = text
        EditorDebugLog.log("viewModel.save begin chars=\(text.count)")

        do {
            expectedModifiedAt = try await fileTransfer.saveTextDocument(
                path: path,
                text: text,
                expectedModifiedAt: expectedModifiedAt
            )
            self.text = text
            contentVersionGeneration += 1
            isDirty = false
            saveStatus = .idle
            EditorDebugLog.log("viewModel.save success contentVersion=\(contentVersionGeneration)")
            errorMessage = nil
        } catch {
            saveStatus = .failed(error.localizedDescription)
            EditorDebugLog.log("viewModel.save failed error=\(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func queueDownload() async -> Bool {
        do {
            try await fileTransfer.enqueueDownload(path: path)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
