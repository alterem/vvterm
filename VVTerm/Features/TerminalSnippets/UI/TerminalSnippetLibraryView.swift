import SwiftUI

struct TerminalSnippetLibraryView: View {
    @EnvironmentObject private var snippetManager: TerminalSnippetManager

    @State private var searchText = ""
    @State private var showingCreateSheet = false
    @State private var editingSnippet: TerminalSnippetEntry?

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
        List {
            if filteredSnippets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        searchText.isEmpty
                            ? String(localized: "No code blocks yet.")
                            : String(localized: "No matching code blocks.")
                    )
                        .foregroundStyle(.secondary)
                    if searchText.isEmpty {
                        Text(String(localized: "Create reusable code blocks for the current terminal."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)
            } else {
                ForEach(filteredSnippets) { snippet in
                    Button {
                        editingSnippet = snippet
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
                    .help(Text(String(localized: "Edit this code block")))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Edit") {
                            editingSnippet = snippet
                        }
                        .tint(.blue)

                        Button("Delete", role: .destructive) {
                            snippetManager.deleteSnippet(id: snippet.id)
                        }
                    }
                    .contextMenu {
                        Button("Edit") {
                            editingSnippet = snippet
                        }

                        Button("Delete", role: .destructive) {
                            snippetManager.deleteSnippet(id: snippet.id)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: Text(String(localized: "Search code blocks")))
        .navigationTitle(String(localized: "Code Blocks"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!snippetManager.canCreateSnippet)
                .help(Text(String(localized: "Add a code block")))
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(
                String(
                    format: String(localized: "%lld/%lld code blocks"),
                    Int64(snippetManager.snippets.count),
                    Int64(TerminalSnippetLibrary.maxEntries)
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showingCreateSheet) {
            TerminalSnippetFormView()
                .environmentObject(snippetManager)
        }
        .sheet(item: $editingSnippet) { snippet in
            TerminalSnippetFormView(snippet: snippet)
                .environmentObject(snippetManager)
        }
    }
}
