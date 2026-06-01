import Foundation
import RemoraCore

enum FileManagerLegacyFormatting {
    static let remoteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func remoteDateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = remoteDateFormatter
        formatter.locale = AppLanguageMode.preferredLocale()
        return formatter.string(from: date)
    }

    static func permissionString(for entry: RemoteFileEntry) -> String {
        guard let permission = entry.permissions else {
            return entry.isDirectory ? "d---------" : "----------"
        }
        return permissionString(mode: permission, isDirectory: entry.isDirectory)
    }

    static func permissionString(mode: UInt16, isDirectory: Bool) -> String {
        let prefix = isDirectory ? "d" : "-"
        let owner = permissionTriad((mode >> 6) & 0b111)
        let group = permissionTriad((mode >> 3) & 0b111)
        let other = permissionTriad(mode & 0b111)
        return "\(prefix)\(owner)\(group)\(other)"
    }

    static func permissionTriad(_ value: UInt16) -> String {
        let readable = (value & 0b100) != 0 ? "r" : "-"
        let writable = (value & 0b010) != 0 ? "w" : "-"
        let executable = (value & 0b001) != 0 ? "x" : "-"
        return "\(readable)\(writable)\(executable)"
    }

    static func kindString(for entry: RemoteFileEntry) -> String {
        entry.isDirectory ? tr("Folder") : tr("File")
    }
}
