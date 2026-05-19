import SwiftUI

struct TerminalSnippetFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var snippetManager: TerminalSnippetManager

    let snippet: TerminalSnippetEntry?

    @State private var name: String
    @State private var content: String
    @State private var description: String
    @State private var sendBehavior: TerminalSnippetSendBehavior
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool {
        snippet != nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (isEditing || snippetManager.canCreateSnippet)
    }

    init(snippet: TerminalSnippetEntry? = nil) {
        self.snippet = snippet
        _name = State(initialValue: snippet?.name ?? "")
        _content = State(initialValue: snippet?.content ?? "")
        _description = State(initialValue: snippet?.description ?? "")
        _sendBehavior = State(initialValue: snippet?.sendBehavior ?? .insert)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name"), text: $name)
                } header: {
                    Text(String(localized: "Name"))
                } footer: {
                    Text(
                        String(
                            format: String(localized: "%lld/%lld characters"),
                            Int64(name.count),
                            Int64(TerminalSnippetLibrary.maxNameLength)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 180)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text(String(localized: "Code Block"))
                } footer: {
                    Text(
                        String(
                            format: String(localized: "%lld/%lld characters"),
                            Int64(content.count),
                            Int64(TerminalSnippetLibrary.maxContentLength)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $description)
                        .frame(minHeight: 96)
                } header: {
                    Text(String(localized: "Description"))
                } footer: {
                    Text(
                        String(
                            format: String(localized: "%lld/%lld characters"),
                            Int64(description.count),
                            Int64(TerminalSnippetLibrary.maxDescriptionLength)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Picker(String(localized: "Default Send Behavior"), selection: $sendBehavior) {
                        ForEach(TerminalSnippetSendBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(String(localized: "Code blocks default to insert-only so they do not run immediately."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Text(String(localized: "Delete Code Block"))
                                Spacer()
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                isEditing
                    ? String(localized: "Edit Code Block")
                    : String(localized: "New Code Block")
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSnippet()
                    }
                    .disabled(!canSave)
                }
            }
            .alert(String(localized: "Delete Code Block?"), isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    guard let snippet else { return }
                    snippetManager.deleteSnippet(id: snippet.id)
                    dismiss()
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private func saveSnippet() {
        do {
            if let snippet {
                try snippetManager.updateSnippet(
                    id: snippet.id,
                    name: name,
                    content: content,
                    description: description,
                    sendBehavior: sendBehavior
                )
            } else {
                _ = try snippetManager.createSnippet(
                    name: name,
                    content: content,
                    description: description,
                    sendBehavior: sendBehavior
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
