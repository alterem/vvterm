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
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    #if os(iOS)
    private var iOSBody: some View {
        NavigationStack {
            iOSContent
                .background(Color(uiColor: .systemGroupedBackground))
            .searchable(text: $searchText, prompt: Text(String(localized: "Search code blocks")))
            .navigationTitle(String(localized: "Code Blocks"))
            .navigationBarTitleDisplayMode(.inline)
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

    private var iOSContent: some View {
        Group {
            if filteredSnippets.isEmpty {
                ScrollView {
                    emptyState
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredSnippets) { snippet in
                            iOSSnippetRow(for: snippet)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func iOSSnippetRow(for snippet: TerminalSnippetEntry) -> some View {
        Button {
            onInsert(snippet)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(Text(String(localized: "Insert this code block into the current terminal")))
    }
    #endif

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                if filteredSnippets.isEmpty {
                    VStack {
                        Spacer(minLength: 0)
                        emptyState
                            .frame(maxWidth: 360)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredSnippets) { snippet in
                                macSnippetRow(for: snippet)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            footer
        }
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 760, minHeight: 420, idealHeight: 520, maxHeight: 680)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Code Blocks"))
                    .font(.title3.weight(.semibold))
                Text(String(localized: "Manage reusable code blocks for any terminal"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            SearchField(placeholder: "Search code blocks", text: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: 280)
                .background(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func macSnippetRow(for snippet: TerminalSnippetEntry) -> some View {
        Button {
            onInsert(snippet)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(Text(String(localized: "Insert this code block into the current terminal")))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(
                String(
                    format: String(localized: "%lld/%lld code blocks"),
                    Int64(snippetManager.snippets.count),
                    Int64(TerminalSnippetLibrary.maxEntries)
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button("Close") {
                dismiss()
            }

            Button("Manage") {
                dismiss()
                onManage()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    #endif

    private var emptyState: some View {
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
    }
}
