import Foundation

enum EditorBridgeMessageType: String, Decodable {
    case ready
    case change
    case selectionChange
    case saveRequested
    case debug
    case error
}

struct EditorBridgeMessage: Decodable {
    let type: EditorBridgeMessageType
    let revision: Int?
    let from: Int?
    let to: Int?
    let message: String?
}

enum EditorTextSyncMode {
    case continuous
    case onDemand
}

enum EditorDebugLog {
    static func log(_ message: @autoclosure () -> String) {
        print("[RemoraEditor] \(message())")
    }
}
