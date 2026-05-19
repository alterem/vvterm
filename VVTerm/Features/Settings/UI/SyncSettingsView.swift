//
//  SyncSettingsView.swift
//  VVTerm
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - Sync Settings View

struct SyncSettingsView: View {
    @ObservedObject private var cloudKit = CloudKitManager.shared
    @ObservedObject private var webDAV = WebDAVSyncManager.shared
    @ObservedObject private var serverManager = ServerManager.shared
    @EnvironmentObject private var terminalThemeManager: TerminalThemeManager
    @EnvironmentObject private var terminalAccessory: TerminalAccessoryPreferencesManager
    @EnvironmentObject private var terminalSnippetManager: TerminalSnippetManager
    @AppStorage(SyncSettings.enabledKey) private var syncEnabled = false
    @AppStorage(WebDAVSyncSettings.enabledKey) private var webDAVEnabled = false
    @AppStorage(WebDAVSyncSettings.serverURLKey) private var webDAVServerURL = ""
    @AppStorage(WebDAVSyncSettings.usernameKey) private var webDAVUsername = ""
    @AppStorage(WebDAVSyncSettings.remotePathKey) private var webDAVRemotePath = WebDAVSyncSettings.defaultRemotePath
    @State private var webDAVPassword = ""
    @State private var isExportingServers = false
    @State private var serverExportDocument: ServerExportWorkbookDocument?
    @State private var serverExportFilename = "VVTerm-Servers.xlsx"
    @State private var isServerExporterPresented = false
    @State private var isServerImporterPresented = false
    @State private var isImportingServers = false
    @State private var importMessage: String?
    @State private var exportError: String?
    @State private var webDAVConfirmationAction: WebDAVConfirmationAction?

    var body: some View {
        Form {
            iCloudSection

            if syncEnabled {
                syncStatusSection
                dataSection
            }

            serverExportSection
            serverImportSection
            webDAVSection

            // Debug section when CloudKit is unavailable
            if syncEnabled && !cloudKit.isAvailable {
                troubleshootingSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadWebDAVPassword()
        }
        .onChangeCompat(of: syncEnabled) { enabled in
            cloudKit.handleSyncToggle(enabled)
            if enabled {
                Task {
                    await serverManager.loadData()
                    await terminalAccessory.refreshFromCloud()
                }
            }
        }
        .fileExporter(
            isPresented: $isServerExporterPresented,
            document: serverExportDocument,
            contentType: ServerExportWorkbookDocument.contentType,
            defaultFilename: serverExportFilename
        ) { result in
            handleServerExportCompletion(result)
        }
        .fileImporter(
            isPresented: $isServerImporterPresented,
            allowedContentTypes: [ServerExportWorkbookDocument.contentType, .spreadsheet, .data],
            allowsMultipleSelection: false
        ) { result in
            handleVVTermExcelImport(result)
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert(
            webDAVConfirmationAction?.title ?? "",
            isPresented: Binding(
                get: { webDAVConfirmationAction != nil },
                set: { if !$0 { webDAVConfirmationAction = nil } }
            ),
            presenting: webDAVConfirmationAction
        ) { action in
            Button("Cancel", role: .cancel) {
                webDAVConfirmationAction = nil
            }
            Button(action.confirmButtonTitle, role: action.isDestructive ? .destructive : nil) {
                let operation = action.operation
                webDAVConfirmationAction = nil
                Task {
                    saveWebDAVPassword()
                    await performWebDAVOperation(operation)
                }
            }
        } message: { action in
            Text(action.message)
        }
        .alert("Import Result", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var iCloudSection: some View {
        Section {
            Toggle("Enable iCloud Sync", isOn: $syncEnabled)

            HStack {
                Label("iCloud Account", systemImage: "icloud")
                Spacer()
                statusBadge
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Sync servers, workspaces, themes, and keyboard accessory settings across all your Apple devices.")
        }
    }

    private var syncStatusSection: some View {
        Section("Sync Status") {
            HStack {
                Text("Status")
                Spacer()
                syncStatusView
            }

            if let lastSync = cloudKit.lastSyncDate {
                HStack {
                    Text("Last Synced")
                    Spacer()
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            if case .error(let message) = cloudKit.syncStatus {
                HStack {
                    Text("Error")
                    Spacer()
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var serverExportSection: some View {
        Section("Server Export") {
            HStack {
                Label("Servers", systemImage: "server.rack")
                Spacer()
                Text(String(serverManager.servers.count))
                    .foregroundStyle(.secondary)
            }

            Button {
                exportServers()
            } label: {
                Label("Export Servers", systemImage: "square.and.arrow.up")
            }
            .disabled(serverManager.servers.isEmpty || isExportingServers)
        }
    }

    private var serverImportSection: some View {
        Section {
            Button {
                importVVTermExcel()
            } label: {
                Label("Import from Excel", systemImage: "square.and.arrow.down")
            }
            .disabled(isImportingServers)

            Button {
                importSecureCRTSessions()
            } label: {
                Label("Import SecureCRT Sessions", systemImage: "folder.badge.plus")
            }
            .disabled(isImportingServers)
        } header: {
            Text("Server Import")
        } footer: {
            Text("Import VVTerm Excel exports or batch-import SSH sessions from the SecureCRT Sessions folder.")
        }
    }

    private var troubleshootingSection: some View {
        Section {
            HStack {
                Text("Account Status")
                Spacer()
                Text(cloudKit.accountStatusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Container")
                Spacer()
                Text(String(localized: "iCloud.app.vivy.VivyTerm"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await cloudKit.forceSync()
                }
            } label: {
                Label("Re-check iCloud Status", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Troubleshooting")
        } footer: {
            Text("Make sure you are signed into iCloud in Settings and iCloud Drive is enabled. Check Console.app for 'CloudKit' logs for more details.")
        }
    }

    private var webDAVSection: some View {
        Section {
            Toggle("Enable WebDAV Sync", isOn: $webDAVEnabled)

            if webDAVEnabled {
                TextField("Server URL", text: $webDAVServerURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    #endif

                TextField("Username", text: $webDAVUsername)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .textContentType(.username)

                SecureField("Password", text: $webDAVPassword)
                    .textContentType(.password)

                TextField("Remote file", text: $webDAVRemotePath)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                HStack {
                    Text("Status")
                    Spacer()
                    webDAVStatus
                }

                Button {
                    Task {
                        saveWebDAVPassword()
                        await webDAV.testConnection()
                    }
                } label: {
                    Label("Test WebDAV Connection", systemImage: "checkmark.circle")
                }
                .disabled(webDAV.isSyncing)

                Button {
                    webDAVConfirmationAction = .upload(message: webDAVBackupScopeMessage)
                } label: {
                    Label("Upload Local Data", systemImage: "arrow.up.doc")
                }
                .disabled(webDAV.isSyncing)
                .help(Text("Review the WebDAV backup scope before uploading"))

                Button {
                    webDAVConfirmationAction = .download(message: webDAVRestoreScopeMessage)
                } label: {
                    Label("Download WebDAV Data", systemImage: "arrow.down.doc")
                }
                .disabled(webDAV.isSyncing)
            }
        } header: {
            Text("WebDAV")
        } footer: {
            Text(String(localized: "WebDAV sync stores a JSON snapshot of your server metadata, workspace data, terminal themes, accessory settings, and code blocks. Passwords and SSH keys stay in this device's Keychain."))
        }
    }

    private var dataSection: some View {
        Section("Data") {
            dataCountRow(
                title: String(localized: "Workspaces"),
                systemImage: "folder",
                count: serverManager.workspaces.count
            )
            dataCountRow(
                title: String(localized: "Servers"),
                systemImage: "server.rack",
                count: serverManager.servers.count
            )
            dataCountRow(
                title: String(localized: "Custom Themes"),
                systemImage: "paintpalette",
                count: customThemeCount
            )
            dataCountRow(
                title: String(localized: "Accessory Items"),
                systemImage: "keyboard",
                count: terminalAccessory.profile.layout.activeItems.count
            )
            dataCountRow(
                title: String(localized: "Custom Actions"),
                systemImage: "command.square",
                count: terminalAccessory.customActions.count
            )
            dataCountRow(
                title: String(localized: "Code Blocks"),
                systemImage: "curlybraces.square",
                count: terminalSnippetManager.snippets.count
            )
        }
    }

    private func dataCountRow(title: String, systemImage: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(String(count))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var webDAVStatus: some View {
        if webDAV.isSyncing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(webDAV.statusMessage)
            }
            .font(.caption)
            .foregroundStyle(.orange)
        } else if let error = webDAV.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.trailing)
        } else {
            Text(webDAVEnabled ? webDAV.statusMessage : String(localized: "Disabled"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadWebDAVPassword() {
        webDAVPassword = (try? KeychainManager.shared.getWebDAVPassword()) ?? ""
    }

    private func saveWebDAVPassword() {
        do {
            if webDAVPassword.isEmpty {
                KeychainManager.shared.deleteWebDAVPassword()
            } else {
                try KeychainManager.shared.storeWebDAVPassword(webDAVPassword)
            }
        } catch {
            webDAV.lastError = error.localizedDescription
        }
    }

    private var customThemeCount: Int {
        terminalThemeManager.customThemes.filter { !$0.isDeleted }.count
    }

    private var webDAVBackupScopeMessage: String {
        [
            String(localized: "Upload these local items to WebDAV?"),
            String(localized: "Servers and workspaces: host, port, username, workspace, and other connection metadata."),
            String(localized: "Terminal settings: custom themes and active theme preferences."),
            String(localized: "Accessory settings: accessory bar layout and custom actions."),
            String(localized: "Code blocks: global code block names, content, descriptions, and send behavior."),
            String(localized: "Not included: passwords, SSH keys, and other Keychain-only secrets.")
        ].joined(separator: "\n\n")
    }

    private var webDAVRestoreScopeMessage: String {
        [
            String(localized: "Download and merge WebDAV data into this device?"),
            String(localized: "WebDAV restore can update server metadata, workspaces, themes, accessory settings, and code blocks."),
            String(localized: "Local passwords and SSH keys remain on this device and are never restored from WebDAV."),
            String(localized: "When the same item exists in both places, the newest version is kept.")
        ].joined(separator: "\n\n")
    }

    private func performWebDAVOperation(_ operation: WebDAVOperation) async {
        switch operation {
        case .upload:
            await webDAV.uploadCurrentSnapshot()
        case .download:
            await webDAV.downloadAndApplySnapshot()
        }
    }

    private func exportServers() {
        guard !isExportingServers else { return }
        isExportingServers = true

        Task { @MainActor in
            defer { isExportingServers = false }

            do {
                let package = try ServerExportManager.shared.makeExportPackage(
                    servers: serverManager.servers,
                    workspaces: serverManager.workspaces
                )
                serverExportDocument = ServerExportWorkbookDocument(data: package.data)
                serverExportFilename = package.filename
                isServerExporterPresented = true
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func importVVTermExcel() {
        #if os(iOS)
        isServerImporterPresented = true
        #else
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [ServerExportWorkbookDocument.contentType, .spreadsheet, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleSelectedVVTermExcel(url)
        #endif
    }

    private func importSecureCRTSessions() {
        #if os(iOS)
        importMessage = String(localized: "SecureCRT session folder import is available on macOS.")
        #else
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.message = String(localized: "Choose the SecureCRT Sessions folder.")
        if let defaultDirectory = defaultSecureCRTSessionsDirectory() {
            panel.directoryURL = defaultDirectory
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleSelectedSecureCRTSessionsDirectory(url)
        #endif
    }

    #if os(macOS)
    private func defaultSecureCRTSessionsDirectory() -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VanDyke/SecureCRT/Config/Sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return url
    }
    #endif

    private func handleVVTermExcelImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            handleSelectedVVTermExcel(url)
        case .failure(let error):
            importMessage = error.localizedDescription
        }
    }

    private func handleSelectedVVTermExcel(_ url: URL) {
        performServerImport {
            try ServerImportManager.shared.previewVVTermExcelImport(from: url)
        }
    }

    private func handleSelectedSecureCRTSessionsDirectory(_ url: URL) {
        performServerImport {
            try ServerImportManager.shared.previewSecureCRTImport(fromSessionsDirectory: url)
        }
    }

    private func performServerImport(previewLoader: @escaping () throws -> ServerImportPreview) {
        guard !isImportingServers else { return }
        isImportingServers = true

        Task { @MainActor in
            defer { isImportingServers = false }

            do {
                let preview = try previewLoader()
                guard !preview.items.isEmpty else {
                    importMessage = String(localized: "No importable servers were found.")
                    return
                }

                let result = try await ServerImportManager.shared.applyImportPreview(preview, into: serverManager)
                importMessage = importSummary(from: result)
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    private func importSummary(from result: ServerImportResult) -> String {
        if result.skippedCount > 0 {
            return String(
                format: String(localized: "Imported %1$d servers across %2$d workspaces. Skipped %3$d duplicates."),
                result.importedCount,
                result.workspaceCount,
                result.skippedCount
            )
        }

        return String(
            format: String(localized: "Imported %1$d servers across %2$d workspaces."),
            result.importedCount,
            result.workspaceCount
        )
    }

    private func handleServerExportCompletion(_ result: Result<URL, Error>) {
        isServerExporterPresented = false
        serverExportDocument = nil

        if case .failure(let error) = result {
            let nsError = error as NSError
            guard nsError.code != NSUserCancelledError else { return }
            exportError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if !syncEnabled {
            Label("Disabled", systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if cloudKit.isAvailable {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label("Not Available", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var syncStatusView: some View {
        switch cloudKit.syncStatus {
        case .idle:
            Label("Synced", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .syncing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing...")
            }
            .foregroundStyle(.orange)
        case .error:
            Label("Error", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .offline:
            Label("Offline", systemImage: "wifi.slash")
                .foregroundStyle(.secondary)
        case .disabled:
            Label("Disabled", systemImage: "pause.circle")
                .foregroundStyle(.secondary)
        }
    }

}

private enum WebDAVOperation {
    case upload
    case download
}

private struct WebDAVConfirmationAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmButtonTitle: String
    let isDestructive: Bool
    let operation: WebDAVOperation

    static func upload(message: String) -> WebDAVConfirmationAction {
        WebDAVConfirmationAction(
            title: String(localized: "Upload to WebDAV?"),
            message: message,
            confirmButtonTitle: String(localized: "Upload"),
            isDestructive: false,
            operation: .upload
        )
    }

    static func download(message: String) -> WebDAVConfirmationAction {
        WebDAVConfirmationAction(
            title: String(localized: "Restore from WebDAV?"),
            message: message,
            confirmButtonTitle: String(localized: "Download"),
            isDestructive: false,
            operation: .download
        )
    }
}
