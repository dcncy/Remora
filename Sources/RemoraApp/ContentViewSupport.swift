import SwiftUI
import RemoraCore

struct ActiveRuntimeConnectionState: Equatable {
    var runtimeID: ObjectIdentifier?
    var connectionMode: ConnectionMode?
    var connectionState: String
    var hostID: UUID?
}

struct HostExportDraft: Equatable {
    var scope: HostExportScope = .all
    var format: HostExportFormat = .json
    var includeSavedPasswords = false
}

struct PendingHostDeletion: Identifiable, Equatable {
    let id: UUID
    let name: String
    let address: String
}

struct PendingGroupDeletion: Identifiable, Equatable {
    let id: String
    let hostCount: Int
    var deleteHosts: Bool
}

struct HoveredSessionMetricsTooltip: Equatable {
    let tabID: UUID
    let hostTitle: String
    let connectionState: String
    let snapshot: ServerResourceMetricsSnapshot?
    let isLoading: Bool
    let errorMessage: String?
}

struct SessionMetricsButtonAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum SSHRefreshActionDecision: Equatable {
    case refresh
    case reconnect

    static func resolve(connectionState: String, hasReconnectableHost: Bool) -> SSHRefreshActionDecision {
        let isConnected = connectionState.hasPrefix("Connected")
        let isConnecting = connectionState == "Connecting"
        let isWaiting = connectionState.hasPrefix("Waiting")

        guard hasReconnectableHost else {
            return .refresh
        }

        if isConnected || isConnecting || isWaiting {
            return .refresh
        }

        return .reconnect
    }
}

enum SidebarDragPayload: Equatable {
    case host(UUID)
    case group(String)

    private static let hostPrefix = "host:"
    private static let groupPrefix = "group:"

    var rawValue: String {
        switch self {
        case .host(let id):
            return "\(Self.hostPrefix)\(id.uuidString)"
        case .group(let name):
            return "\(Self.groupPrefix)\(name)"
        }
    }

    init?(_ rawValue: String) {
        if rawValue.hasPrefix(Self.hostPrefix) {
            let suffix = String(rawValue.dropFirst(Self.hostPrefix.count))
            guard let id = UUID(uuidString: suffix) else { return nil }
            self = .host(id)
            return
        }

        if rawValue.hasPrefix(Self.groupPrefix) {
            let suffix = String(rawValue.dropFirst(Self.groupPrefix.count))
            guard !suffix.isEmpty else { return nil }
            self = .group(suffix)
            return
        }

        return nil
    }
}
