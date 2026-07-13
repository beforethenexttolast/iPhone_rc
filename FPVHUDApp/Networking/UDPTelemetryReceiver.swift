import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

final class UDPTelemetryReceiver: TelemetryReceiver {
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
        let telemetryPort = settings.telemetryPort
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: telemetryPort)) else {
            return
        }

        queue.async { [weak self] in
            self?.startOnQueue(port: port, telemetryPort: telemetryPort)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue(emitIdle: true)
        }
    }

    private func startOnQueue(port: NWEndpoint.Port, telemetryPort: Int) {
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
            listener.service = TelemetryDiscoveryAdvertisement.listenerService(
                telemetryPort: telemetryPort
            )
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
            lastPacketReceivedAt = Date()
            latestState = try TelemetryJSONDecoder.decodeState(from: data, previous: latestState)
            latestState.linkState = .connected
            onTelemetry?(latestState)
            emitStatus()
        } catch {
            malformedPacketCount += 1
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

enum TelemetryDiscoveryAdvertisement {
    static let serviceType = "_w17hud._udp"
    static let serviceTypeWithDomain = "_w17hud._udp.local."
    static let contractVersion = "1"
    static let role = "hud"

    static func listenerService(
        telemetryPort: Int,
        deviceName: String = currentDeviceName(),
        supportsHeadTracking: Bool = true
    ) -> NWListener.Service {
        NWListener.Service(
            name: instanceName(deviceName: deviceName),
            type: serviceType,
            domain: nil,
            txtRecord: NWTXTRecord(
                txtRecordValues(
                    telemetryPort: telemetryPort,
                    deviceName: deviceName,
                    supportsHeadTracking: supportsHeadTracking
                )
            )
        )
    }

    static func instanceName(deviceName: String) -> String {
        "W17 HUD (\(shortDeviceName(deviceName)))"
    }

    static func txtRecordValues(
        telemetryPort: Int,
        deviceName: String,
        supportsHeadTracking: Bool = true
    ) -> [String: String] {
        [
            "v": contractVersion,
            "role": role,
            "tport": String(telemetryPort),
            "feat": supportsHeadTracking ? "w2,w3" : "w2",
            "dev": shortDeviceName(deviceName)
        ]
    }

    static func shortDeviceName(_ rawName: String) -> String {
        let ascii = rawName.unicodeScalars.map { scalar -> Character in
            guard scalar.isASCII, !CharacterSet.controlCharacters.contains(scalar) else {
                return " "
            }
            return Character(scalar)
        }
        let trimmed = String(ascii)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        let fallback = trimmed.isEmpty ? "iPhone" : trimmed
        return String(fallback.prefix(32))
    }

    private static func currentDeviceName() -> String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "iPhone"
        #endif
    }
}
