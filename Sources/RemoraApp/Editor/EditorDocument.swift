import Foundation

struct EditorDocument: Identifiable, Equatable {
    let id: UUID
    var path: String?
    var text: String
    var language: EditorLanguage
    var isEditable: Bool
    var lineWrapping: Bool

    init(
        id: UUID = UUID(),
        path: String? = nil,
        text: String = "",
        language: EditorLanguage = .plain,
        isEditable: Bool = true,
        lineWrapping: Bool = true
    ) {
        self.id = id
        self.path = path
        self.text = text
        self.language = language
        self.isEditable = isEditable
        self.lineWrapping = lineWrapping
    }
}
