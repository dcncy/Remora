import SwiftUI

struct RemoteTextEditorRepresentable: View {
    @Binding private var text: String
    private let language: EditorLanguage
    private let path: String?
    private let isEditable: Bool
    private let autoScrollToBottom: Bool
    private let syncMode: EditorTextSyncMode
    private let saveRequestID: Int
    private let contentVersion: Int
    private let onChange: ((Int) -> Void)?
    private let onSaveRequested: ((String) -> Void)?
    private let onError: ((String) -> Void)?

    init(
        text: Binding<String>,
        language: EditorLanguage = .plain,
        path: String? = nil,
        isEditable: Bool,
        autoScrollToBottom: Bool = false,
        syncMode: EditorTextSyncMode = .continuous,
        saveRequestID: Int = 0,
        contentVersion: Int = 0,
        onChange: ((Int) -> Void)? = nil,
        onSaveRequested: ((String) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        _text = text
        self.language = language
        self.path = path
        self.isEditable = isEditable
        self.autoScrollToBottom = autoScrollToBottom
        self.syncMode = syncMode
        self.saveRequestID = saveRequestID
        self.contentVersion = contentVersion
        self.onChange = onChange
        self.onSaveRequested = onSaveRequested
        self.onError = onError
    }

    var body: some View {
        RemoraEditorWebView(
            document: EditorDocument(
                path: path,
                text: text,
                language: language,
                isEditable: isEditable,
                lineWrapping: true
            ),
            saveRequestID: saveRequestID,
            contentVersion: contentVersion,
            syncMode: syncMode,
            autoScrollToBottom: autoScrollToBottom,
            onReady: nil,
            onChange: onChange,
            onTextChange: { newText in
                text = newText
            },
            onSaveRequested: onSaveRequested,
            onError: onError
        )
    }
}
