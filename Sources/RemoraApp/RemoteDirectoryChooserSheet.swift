import SwiftUI

@MainActor
final class RemoteDirectoryChooserViewModel: ObservableObject {
    struct DirectoryRow: Identifiable, Equatable {
        var path: String
        var name: String
        var id: String { path }
    }

    @Published var currentPath: String
    @Published private(set) var directories: [DirectoryRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let fileTransfer: FileTransferViewModel

    init(initialPath: String, fileTransfer: FileTransferViewModel) {
        self.currentPath = initialPath
        self.fileTransfer = fileTransfer
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let entries = try await fileTransfer.listRemoteDirectory(path: currentPath, preferCachedFirst: true)
            directories = entries
                .filter(\.isDirectory)
                .map { entry in
                    DirectoryRow(path: entry.path, name: entry.name)
                }
        } catch {
            directories = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func open(_ row: DirectoryRow) async {
        currentPath = row.path
        await load()
    }

    func goToParent() async {
        let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        currentPath = parent.isEmpty ? "/" : parent
        await load()
    }
}

struct RemoteDirectoryChooserSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: RemoteDirectoryChooserViewModel
    let onConfirm: (String) -> Void

    init(
        initialPath: String,
        fileTransfer: FileTransferViewModel,
        onConfirm: @escaping (String) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: RemoteDirectoryChooserViewModel(
                initialPath: initialPath,
                fileTransfer: fileTransfer
            )
        )
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Select Destination Directory"))
                .font(.headline)

            HStack(spacing: 8) {
                Button(tr("Up")) {
                    Task { await viewModel.goToParent() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.currentPath == "/" || viewModel.isLoading)

                Text(viewModel.currentPath)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Failed to load remote directory"))
                            .font(.subheadline.weight(.semibold))
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    List(viewModel.directories) { row in
                        Button {
                            Task { await viewModel.open(row) }
                        } label: {
                            Label(row.name, systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button(tr("Cancel")) { dismiss() }
                    .buttonStyle(.bordered)
                Button(tr("Move To")) {
                    onConfirm(viewModel.currentPath)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
            }
        }
        .padding(16)
        .frame(width: 460, height: 420)
        .task {
            await viewModel.load()
        }
    }
}
