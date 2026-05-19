import SwiftUI

struct TerminalSnippetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var snippetManager: TerminalSnippetManager

    let onInsert: (TerminalSnippetEntry) -> Void
    let onManage: () -> Void

    @State private var searchText = ""

    private var filteredSnippets: [TerminalSnippetEntry] {
        let snippets = snippetManager.snippets
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snippets }

        return snippets.filter { snippet in
            snippet.name.localizedCaseInsensitiveContains(query) ||
            snippet.description.localizedCaseInsensitiveContains(query) ||
            snippet.content.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredSnippets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            searchText.isEmpty
                                ? String(localized: "No code blocks available.")
                                : String(localized: "No matching code blocks.")
                        )
                            .foregroundStyle(.secondary)
                        if searchText.isEmpty {
                            Text(String(localized: "Create code blocks in Settings > Code Blocks, then insert them into the current terminal here."))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                dismiss()
                                onManage()
                            } label: {
                                Label(String(localized: "Open Settings > Code Blocks"), systemImage: "gear")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 12)
                } else {
                    ForEach(filteredSnippets) { snippet in
                        Button {
                            onInsert(snippet)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(snippet.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(snippet.sendBehavior.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                if !snippet.description.isEmpty {
                                    Text(snippet.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Text(snippet.contentPreview)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(Text(String(localized: "Insert this code block into the current terminal")))
                    }
                }
            }
            .searchable(text: $searchText, prompt: Text(String(localized: "Search code blocks")))
            .navigationTitle(String(localized: "Code Blocks"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                        onManage()
                    } label: {
                        Text(String(localized: "Manage"))
                    }
                    .help(Text(String(localized: "Open Settings > Code Blocks")))
                }
            }
        }
    }
}
