import Foundation
import Network

final class UDPTelemetryReceiver: TelemetrySource {
    var onTelemetry: ((TelemetryState) -> Void)?
    var onStatus: ((TelemetryReceiverStatus) -> Void)?

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var latestState = TelemetryState.demo
    private var startedAt: Date?
    private var lastPacketReceivedAt: Date?
    private var malformedPacketCount = 0
    private var stalenessTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "fpvhud.telemetry.udp")

    func start(settings: AppSettings) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: settings.telemetryPort)) else {
            return
        }

        queue.async { [weak self] in
            self?.startOnQueue(port: port)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue(emitIdle: true)
        }
    }

    private func startOnQueue(port: NWEndpoint.Port) {
        stopOnQueue(emitIdle: false)

        do {
            startedAt = Date()
            latestState = TelemetryState.demo
            latestState.mode = .udp
            latestState.linkState = .connecting
            latestState.warningText = "WAITING FOR TELEMETRY"
            latestState.staleDataWarnings = [.telemetry]
            onTelemetry?(latestState)
            emitStatus(warningText: "Waiting for UDP telemetry")

            let listener = try NWListener(using: .udp, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection)
                connection.start(queue: self.queue)
                self.receive(on: connection)
            }
            listener.start(queue: queue)
            self.listener = listener
            startStalenessTimer()
        } catch {
            startedAt = nil
            latestState.linkState = .disconnected
            latestState.warningText = "UDP LISTENER FAILED"
            onTelemetry?(latestState)
            emitStatus(warningText: "UDP listener failed")
        }
    }

    private func stopOnQueue(emitIdle: Bool) {
        stalenessTimer?.cancel()
        stalenessTimer = nil
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        startedAt = nil
        lastPacketReceivedAt = nil
        if emitIdle {
            onStatus?(.idle)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            guard self.listener != nil else { return }
            guard error == nil else { return }
            if let data {
                self.parse(data)
            }
            self.receive(on: connection)
        }
    }

    private func parse(_ data: Data) {
        do {
            let packet = try JSONDecoder().decode(IncomingTelemetryPacket.self, from: data)
            lastPacketReceivedAt = Date()
            latestState = packet.merged(with: latestState)
            latestState.linkState = .connected
            onTelemetry?(latestState)
            emitStatus()
        } catch {
            malformedPacketCount += 1
            latestState.linkState = .degraded
            latestState.warningText = "BAD TELEMETRY PACKET"
            onTelemetry?(latestState)
            emitStatus(warningText: "Malformed telemetry JSON")
        }
    }

    private func startStalenessTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.evaluateStaleness()
        }
        timer.resume()
        stalenessTimer = timer
    }

    private func evaluateStaleness() {
        guard listener != nil else { return }

        let now = Date()
        let age: TimeInterval
        if let lastPacketReceivedAt {
            age = now.timeIntervalSince(lastPacketReceivedAt)
        } else if let startedAt {
            age = now.timeIntervalSince(startedAt)
        } else {
            age = 0
        }

        switch TelemetryFreshness.evaluate(age: age) {
        case .dataLost:
            latestState.linkState = .disconnected
            latestState.warningText = "TELEMETRY DATA LOST >3S"
            latestState.staleDataWarnings = mergedWarnings(latestState.staleDataWarnings, adding: .telemetry)
            onTelemetry?(latestState)
            emitStatus(warningText: "Telemetry data lost")
        case .staleWarning:
            latestState.linkState = .degraded
            latestState.warningText = "TELEMETRY STALE >1S"
            latestState.staleDataWarnings = mergedWarnings(latestState.staleDataWarnings, adding: .telemetry)
            onTelemetry?(latestState)
            emitStatus(warningText: "Telemetry stale")
        case .live:
            emitStatus()
        }
    }

    private func emitStatus(warningText: String? = nil) {
        let age = lastPacketReceivedAt.map { Date().timeIntervalSince($0) }
        onStatus?(
            TelemetryReceiverStatus(
                isListening: listener != nil || startedAt != nil,
                lastPacketReceivedAt: lastPacketReceivedAt,
                lastPacketAge: age,
                malformedPacketCount: malformedPacketCount,
                warningText: warningText
            )
        )
    }

    private func mergedWarnings(
        _ warnings: [StaleDataWarning],
        adding warning: StaleDataWarning
    ) -> [StaleDataWarning] {
        warnings.contains(warning) ? warnings : warnings + [warning]
    }
}
