import Foundation
import Testing
@testable import VVTerm

@Suite(.serialized)
@MainActor
struct ServerJumpHostTests {
    @Test
    func availableJumpHostsExcludeCurrentServerAndCyclicCandidates() {
        let manager = ServerManager.shared
        let originalServers = manager.servers
        let originalWorkspaces = manager.workspaces

        let workspace = Workspace(name: "Main")
        let targetId = UUID()
        let jumpAId = UUID()
        let jumpBId = UUID()

        manager.workspaces = [workspace]
        manager.servers = [
            Server(
                id: targetId,
                workspaceId: workspace.id,
                jumpHostServerId: jumpAId,
                name: "Target",
                host: "target.example.com",
                username: "root"
            ),
            Server(
                id: jumpAId,
                workspaceId: workspace.id,
                jumpHostServerId: jumpBId,
                name: "Jump A",
                host: "jump-a.example.com",
                username: "root"
            ),
            Server(
                id: jumpBId,
                workspaceId: workspace.id,
                name: "Jump B",
                host: "jump-b.example.com",
                username: "root"
            )
        ]

        defer {
            manager.servers = originalServers
            manager.workspaces = originalWorkspaces
        }

        let candidates = manager.availableJumpHosts(in: workspace, excluding: targetId)
        #expect(candidates.map(\.id) == [jumpAId, jumpBId])
    }

    @Test
    func ensureServerAndJumpHostShareFolderUsesExistingTargetFolder() async throws {
        let manager = ServerManager.shared
        let originalServers = manager.servers
        let originalWorkspaces = manager.workspaces

        let folder = WorkspaceServerFolder(name: "Prod")
        let workspace = Workspace(name: "Main", folders: [folder])
        let targetId = UUID()
        let jumpId = UUID()

        manager.workspaces = [workspace]
        manager.servers = [
            Server(
                id: targetId,
                workspaceId: workspace.id,
                folderId: folder.id,
                jumpHostServerId: jumpId,
                name: "Target",
                host: "target.example.com",
                username: "root"
            ),
            Server(
                id: jumpId,
                workspaceId: workspace.id,
                name: "Jump",
                host: "jump.example.com",
                username: "root"
            )
        ]

        defer {
            manager.servers = originalServers
            manager.workspaces = originalWorkspaces
        }

        try await manager.ensureServerAndJumpHostShareFolder(serverId: targetId, jumpHostServerId: jumpId)

        #expect(manager.server(withId: targetId)?.folderId == folder.id)
        #expect(manager.server(withId: jumpId)?.folderId == folder.id)
    }

    @Test
    func serversReferencingJumpHostReturnsSortedReferencingServers() {
        let manager = ServerManager.shared
        let originalServers = manager.servers
        let originalWorkspaces = manager.workspaces

        let workspace = Workspace(name: "Main")
        let jumpId = UUID()

        manager.workspaces = [workspace]
        manager.servers = [
            Server(
                id: UUID(),
                workspaceId: workspace.id,
                jumpHostServerId: jumpId,
                name: "Zulu",
                host: "zulu.example.com",
                username: "root"
            ),
            Server(
                id: UUID(),
                workspaceId: workspace.id,
                jumpHostServerId: jumpId,
                name: "Alpha",
                host: "alpha.example.com",
                username: "root"
            ),
            Server(
                id: jumpId,
                workspaceId: workspace.id,
                name: "Jump",
                host: "jump.example.com",
                username: "root"
            ),
            Server(
                id: UUID(),
                workspaceId: workspace.id,
                name: "Standalone",
                host: "standalone.example.com",
                username: "root"
            )
        ]

        defer {
            manager.servers = originalServers
            manager.workspaces = originalWorkspaces
        }

        let referencing = manager.serversReferencingJumpHost(jumpId)
        #expect(referencing.map(\.name) == ["Alpha", "Zulu"])
    }
}
