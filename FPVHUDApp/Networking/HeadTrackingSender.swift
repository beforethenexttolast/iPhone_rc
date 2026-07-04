import Foundation
import Network

final class HeadTrackingSender {
    var onStatus: ((HeadTrackingSenderStatus) -> Void)?

    private var connection: NWConnection?
    private var sequence: UInt32 = 0
    private var packetsSent: UInt64 = 0
    private var sendTimestamps: [Date] = []
    private var lastSendAt: Date?
    private var lastErrorText: String?
    private let queue = DispatchQueue(label: "fpvhud.headtracking.udp")

    func configure(host: String, port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            queue.async { [weak self] in
                self?.stopOnQueue()
                self?.lastErrorText = "Invalid head tracking UDP port"
                self?.emitStatus(isConfigured: false)
            }
            return
        }

        queue.async { [weak self] in
            self?.configureOnQueue(host: host, port: nwPort)
        }
    }

    private func configureOnQueue(host: String, port: NWEndpoint.Port) {
        stopOnQueue()

        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case let .failed(error) = state {
                self.queue.async {
                    self.lastErrorText = error.localizedDescription
                    self.emitStatus(isConfigured: false)
                }
            }
        }
        connection?.start(queue: queue)
        lastErrorText = nil
        emitStatus(isConfigured: true)
    }

    func send(
        yawDeg: Double,
        pitchDeg: Double,
        rollDeg: Double,
        trackingEnabled: Bool,
        centered: Bool,
        timeoutMs: UInt16
    ) {
        queue.async { [weak self] in
            self?.sendOnQueue(
                yawDeg: yawDeg,
                pitchDeg: pitchDeg,
                rollDeg: rollDeg,
                trackingEnabled: trackingEnabled,
                centered: centered,
                timeoutMs: timeoutMs
            )
        }
    }

    private func sendOnQueue(
        yawDeg: Double,
        pitchDeg: Double,
        rollDeg: Double,
        trackingEnabled: Bool,
        centered: Bool,
        timeoutMs: UInt16
    ) {
        guard let connection else {
            lastErrorText = "Head tracking UDP not configured"
            emitStatus(isConfigured: false)
            return
        }

        sequence &+= 1

        let packet = HeadTrackingPacket(
            seq: sequence,
            timestampMs: UInt64(Date().timeIntervalSince1970 * 1000),
            yawDeg: yawDeg,
            pitchDeg: pitchDeg,
            rollDeg: rollDeg,
            trackingEnabled: trackingEnabled,
            centered: centered,
            timeoutMs: timeoutMs
        )

        do {
            let data = try JSONEncoder().encode(packet)
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.queue.async {
                    if let error {
                        self.lastErrorText = error.localizedDescription
                    } else {
                        self.packetsSent &+= 1
                        self.lastSendAt = Date()
                        self.lastErrorText = nil
                        self.recordSendTimestamp(self.lastSendAt!)
                    }
                    self.emitStatus(isConfigured: true)
                }
            })
        } catch {
            lastErrorText = "Could not encode head tracking JSON"
            emitStatus(isConfigured: true)
        }
    }

    func refreshStatus() {
        queue.async {
            self.trimSendTimestamps(now: Date())
            self.emitStatus(isConfigured: self.connection != nil)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        connection?.cancel()
        connection = nil
        sendTimestamps.removeAll()
        emitStatus(isConfigured: false)
    }

    private func recordSendTimestamp(_ date: Date) {
        sendTimestamps.append(date)
        trimSendTimestamps(now: date)
    }

    private func trimSendTimestamps(now: Date) {
        let cutoff = now.addingTimeInterval(-1)
        sendTimestamps.removeAll { $0 < cutoff }
    }

    private func emitStatus(isConfigured: Bool) {
        let rate = lastSendAt == nil ? 0 : Double(sendTimestamps.count)
        onStatus?(
            HeadTrackingSenderStatus(
                isConfigured: isConfigured,
                packetsSent: packetsSent,
                packetRateHz: rate,
                lastSendAt: lastSendAt,
                lastErrorText: lastErrorText
            )
        )
    }
}
