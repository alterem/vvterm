import SwiftUI

struct WorkspaceFolderFormSheet: View {
    @ObservedObject var serverManager: ServerManager
    let workspace: Workspace
    let folder: WorkspaceServerFolder?
    let parentFolder: WorkspaceServerFolder?
    let onSave: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var folderToDelete: WorkspaceServerFolder?
    @FocusState private var isNameFieldFocused: Bool

    private var isEditing: Bool { folder != nil }

    init(
        serverManager: ServerManager,
        workspace: Workspace,
        folder: WorkspaceServerFolder? = nil,
        parentFolder: WorkspaceServerFolder? = nil,
        onSave: @escaping (Workspace) -> Void
    ) {
        self.serverManager = serverManager
        self.workspace = workspace
        self.folder = folder
        if let folder,
           let parentId = folder.parentId {
            self.parentFolder = workspace.folder(withId: parentId)
        } else {
            self.parentFolder = parentFolder
        }
        self.onSave = onSave
        _name = State(initialValue: folder?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Folder name", text: $name)
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                saveFolder()
                            }
                        }
                }

                if let parentFolder {
                    Section("Location") {
                        Text(serverManager.folderDisplayName(parentFolder, in: workspace))
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                if let folder {
                    Section {
                        Button(role: .destructive) {
                            folderToDelete = folder
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Folder")
                                Spacer()
                            }
                        }
                    } footer: {
                        let count = serverManager.servers(in: workspace, environment: nil)
                            .filter { $0.folderId == folder.id }
                            .count
                        if count > 0 {
                            Text("Deleting this folder will keep its servers in the workspace and move them out of the folder.")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? String(localized: "Edit Folder") : String(localized: "New Folder"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? String(localized: "Save") : String(localized: "Create")) {
                        saveFolder()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    isNameFieldFocused = true
                }
            }
            .alert("Delete Folder?", isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteFolder()
                }
            } message: {
                Text("Servers in this folder will remain in the workspace.")
            }
        }
    }

    private func saveFolder() {
        isSaving = true
        error = nil

        Task {
            do {
                let refreshedWorkspace = serverManager.workspace(withId: workspace.id) ?? workspace

                if let folder {
                    var updatedFolder = folder
                    updatedFolder.name = name
                    let updatedWorkspace = try await serverManager.updateFolder(updatedFolder, in: refreshedWorkspace)
                    await MainActor.run {
                        onSave(updatedWorkspace)
                        dismiss()
                    }
                } else {
                    _ = try await serverManager.createFolder(
                        name: name,
                        in: refreshedWorkspace,
                        parentId: parentFolder?.id
                    )
                    let updatedWorkspace = serverManager.workspace(withId: refreshedWorkspace.id) ?? refreshedWorkspace
                    await MainActor.run {
                        onSave(updatedWorkspace)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isSaving = false
                }
            }
        }
    }

    private func deleteFolder() {
        guard let folder else { return }

        Task {
            do {
                let refreshedWorkspace = serverManager.workspace(withId: workspace.id) ?? workspace
                let updatedWorkspace = try await serverManager.deleteFolder(folder, in: refreshedWorkspace)
                await MainActor.run {
                    onSave(updatedWorkspace)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    WorkspaceFolderFormSheet(
        serverManager: ServerManager.shared,
        workspace: Workspace(name: "Default"),
        onSave: { _ in }
    )
}
