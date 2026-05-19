import Foundation
import Network
import os.log

actor JumpHostTransportManager {
    private final class RelayTaskState: @unchecked Sendable {
        private let lock = NSLock()
        private var didFinish = false

        func finishOnce() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didFinish else { return false }
            didFinish = true
            return true
        }
    }

    private struct ActiveTunnel {
        let listener: NWListener
        let boundPort: UInt16
        let bridgeTask: Task<Void, Never>
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VVTerm", category: "JumpHostTransport")
    private var activeTunnel: ActiveTunnel?

    func connect(
        via jumpClient: SSHClient,
        to targetServer: Server
    ) async throws -> UInt16 {
        await disconnect()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: .any)

        let listenerPort = try await withCheckedThrowingContinuation { continuation in
            let completion = RelayTaskState()

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard completion.finishOnce(),
                          let port = listener.port?.rawValue else { return }
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard completion.finishOnce() else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard completion.finishOnce() else { return }
                    continuation.resume(
                        throwing: SSHError.connectionFailed(
                            String(localized: "Jump host listener cancelled")
                        )
                    )
                default:
                    break
                }
            }

            listener.start(queue: .global(qos: .userInitiated))
        }

        let bridgeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runAcceptLoop(listener: listener, jumpClient: jumpClient, targetServer: targetServer)
        }
        activeTunnel = ActiveTunnel(listener: listener, boundPort: listenerPort, bridgeTask: bridgeTask)
        return listenerPort
    }

    func disconnect() async {
        guard let activeTunnel else { return }
        self.activeTunnel = nil
        activeTunnel.listener.cancel()
        activeTunnel.bridgeTask.cancel()
    }

    private func runAcceptLoop(
        listener: NWListener,
        jumpClient: SSHClient,
        targetServer: Server
    ) async {
        let queue = DispatchQueue(label: "com.vivy.vvterm.jump-host.listener")

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: queue)
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.handleConnection(connection, jumpClient: jumpClient, targetServer: targetServer)
            }
        }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func handleConnection(
        _ connection: NWConnection,
        jumpClient: SSHClient,
        targetServer: Server
    ) async {
        defer {
            connection.cancel()
        }

        do {
            let channel = try await jumpClient.openDirectTCPIPChannel(
                host: targetServer.host,
                port: targetServer.port
            )
            defer {
                Task {
                    await jumpClient.closeForwardChannel(channel.id)
                }
            }

            async let upstream: Void = relayFromLocalConnection(connection, to: jumpClient, channelId: channel.id)
            async let downstream: Void = relayToLocalConnection(connection, from: channel.stream)
            _ = try await (upstream, downstream)
        } catch {
            logger.warning("Jump host bridge failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func relayFromLocalConnection(
        _ connection: NWConnection,
        to jumpClient: SSHClient,
        channelId: UUID
    ) async throws {
        while true {
            let data = try await receive(from: connection)
            if data.isEmpty {
                return
            }
            try await jumpClient.writeForwardData(data, to: channelId)
        }
    }

    private func relayToLocalConnection(
        _ connection: NWConnection,
        from stream: AsyncStream<Data>
    ) async throws {
        for await data in stream {
            if data.isEmpty {
                continue
            }
            try await send(data, over: connection)
        }
    }

    private func receive(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }
                if isComplete {
                    continuation.resume(returning: Data())
                    return
                }
                continuation.resume(returning: Data())
            }
        }
    }

    private func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
