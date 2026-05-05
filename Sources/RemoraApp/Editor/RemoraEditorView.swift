import SwiftUI

struct RemoraEditorView: View {
    @Binding var document: EditorDocument

    var saveRequestID: Int = 0
    var onReady: (() -> Void)? = nil
    var onChange: ((Int) -> Void)? = nil
    var onSaveRequested: ((String) -> Void)? = nil
    var onError: ((String) -> Void)? = nil

    var body: some View {
        RemoraEditorWebView(
            document: document,
            saveRequestID: saveRequestID,
            syncMode: .onDemand,
            autoScrollToBottom: false,
            onReady: onReady,
            onChange: onChange,
            onTextChange: nil,
            onSaveRequested: onSaveRequested,
            onError: onError
        )
    }
}
