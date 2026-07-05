import Foundation
import Network

struct RTPHeader: Equatable {
    var version: UInt8
    var padding: Bool
    var extensionHeader: Bool
    var csrcCount: UInt8
    var marker: Bool
    var payloadType: UInt8
    var sequenceNumber: UInt16
    var timestamp: UInt32
    var ssrc: UInt32
    var headerLength: Int
}

struct H265NALInspection: Equatable {
    var packetType: UInt8
    var nalUnitType: UInt8?
    var isFragmentationUnit: Bool
    var isAggregationPacket: Bool
    var isVPS: Bool
    var isSPS: Bool
    var isPPS: Bool

    var displayName: String {
        guard let nalUnitType else { return "Unknown" }
        switch nalUnitType {
        case 32: return "VPS (32)"
        case 33: return "SPS (33)"
        case 34: return "PPS (34)"
        case 48: return "AP (48)"
        case 49: return "FU (49)"
        case 50: return "PACI (50)"
        default: return "NAL \(nalUnitType)"
        }
    }
}

enum RTPParseError: Error, Equatable {
    case packetTooShort
    case invalidVersion(UInt8)
    case unsupportedExtension
    case missingPayload
}

enum RTPDiagnosticParser {
    static func parseHeader(_ data: Data) throws -> RTPHeader {
        guard data.count >= 12 else { throw RTPParseError.packetTooShort }

        let bytes = [UInt8](data.prefix(12))
        let version = bytes[0] >> 6
        guard version == 2 else { throw RTPParseError.invalidVersion(version) }

        let csrcCount = bytes[0] & 0x0F
        let headerLength = 12 + Int(csrcCount) * 4
        guard data.count >= headerLength else { throw RTPParseError.packetTooShort }

        return RTPHeader(
            version: version,
            padding: (bytes[0] & 0x20) != 0,
            extensionHeader: (bytes[0] & 0x10) != 0,
            csrcCount: csrcCount,
            marker: (bytes[1] & 0x80) != 0,
            payloadType: bytes[1] & 0x7F,
            sequenceNumber: UInt16(bytes[2]) << 8 | UInt16(bytes[3]),
            timestamp: UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7]),
            ssrc: UInt32(bytes[8]) << 24 | UInt32(bytes[9]) << 16 | UInt32(bytes[10]) << 8 | UInt32(bytes[11]),
            headerLength: headerLength
        )
    }

    static func inspectH265Payload(_ data: Data, header: RTPHeader) throws -> H265NALInspection {
        guard !header.extensionHeader else { throw RTPParseError.unsupportedExtension }
        guard data.count >= header.headerLength + 2 else { throw RTPParseError.missingPayload }

        let payload = [UInt8](data.dropFirst(header.headerLength))
        let packetType = (payload[0] >> 1) & 0x3F
        let nalUnitType: UInt8?

        if packetType == 49, payload.count >= 3 {
            nalUnitType = payload[2] & 0x3F
        } else {
            nalUnitType = packetType
        }

        return H265NALInspection(
            packetType: packetType,
            nalUnitType: nalUnitType,
            isFragmentationUnit: packetType == 49,
            isAggregationPacket: packetType == 48,
            isVPS: nalUnitType == 32,
            isSPS: nalUnitType == 33,
            isPPS: nalUnitType == 34
        )
    }
}

struct APFPVDiagnosticStatus: Equatable {
    var isEnabled: Bool = false
    var isListening: Bool = false
    var port: Int = FutureRTPHEVCReceiver.plannedDefaultPort
    var packetsReceived: UInt64 = 0
    var packetsPerSecond: Double = 0
    var bitrateKbps: Double = 0
    var sequenceGaps: UInt64 = 0
    var outOfOrderPackets: UInt64 = 0
    var malformedPackets: UInt64 = 0
    var lastPacketReceivedAt: Date?
    var lastPacketAge: TimeInterval?
    var lastVersion: UInt8?
    var lastPayloadType: UInt8?
    var lastSequenceNumber: UInt16?
    var lastTimestamp: UInt32?
    var lastSSRC: UInt32?
    var lastNALUnitType: UInt8?
    var lastNALDescription: String?
    var seenVPS: Bool = false
    var seenSPS: Bool = false
    var seenPPS: Bool = false
    var warningText: String?

    static let idle = APFPVDiagnosticStatus()
}

final class APFPVDiagnosticReceiver {
    var onStatus: ((APFPVDiagnosticStatus) -> Void)?

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var status = APFPVDiagnosticStatus.idle
    private var lastSequenceNumber: UInt16?
    private var packetSamples: [(Date, Int)] = []
    private var statsTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "fpvhud.apfpv.diagnostic.udp")

    func start(port: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return
        }

        queue.async { [weak self] in
            self?.startOnQueue(port: port, nwPort: nwPort)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue(emitIdle: true)
        }
    }

    func refreshStatus() {
        queue.async { [weak self] in
            guard let self else { return }
            self.updateRateFields(now: Date())
            self.emitStatus()
        }
    }

    private func startOnQueue(port: Int, nwPort: NWEndpoint.Port) {
        stopOnQueue(emitIdle: false)

        status = APFPVDiagnosticStatus(isEnabled: true, isListening: false, port: port)
        do {
            let listener = try NWListener(using: .udp, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection)
                connection.start(queue: self.queue)
                self.receive(on: connection)
            }
            listener.start(queue: queue)
            self.listener = listener
            status.isListening = true
            status.warningText = nil
            startStatsTimer()
            emitStatus()
        } catch {
            status.isListening = false
            status.warningText = "APFPV diagnostic UDP listener failed"
            emitStatus()
        }
    }

    private func stopOnQueue(emitIdle: Bool) {
        statsTimer?.cancel()
        statsTimer = nil
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        lastSequenceNumber = nil
        packetSamples.removeAll()
        if emitIdle {
            status = .idle
            emitStatus()
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            guard self.listener != nil else { return }
            guard error == nil else {
                self.status.warningText = "APFPV diagnostic receive error"
                self.emitStatus()
                return
            }
            if let data {
                self.parse(data)
            }
            self.receive(on: connection)
        }
    }

    private func parse(_ data: Data) {
        let now = Date()
        do {
            let header = try RTPDiagnosticParser.parseHeader(data)
            let nal = try? RTPDiagnosticParser.inspectH265Payload(data, header: header)

            status.packetsReceived &+= 1
            status.lastPacketReceivedAt = now
            status.lastVersion = header.version
            status.lastPayloadType = header.payloadType
            status.lastSequenceNumber = header.sequenceNumber
            status.lastTimestamp = header.timestamp
            status.lastSSRC = header.ssrc
            status.lastNALUnitType = nal?.nalUnitType
            status.lastNALDescription = nal?.displayName
            status.seenVPS = status.seenVPS || (nal?.isVPS ?? false)
            status.seenSPS = status.seenSPS || (nal?.isSPS ?? false)
            status.seenPPS = status.seenPPS || (nal?.isPPS ?? false)
            status.warningText = nil
            updateSequenceStats(sequenceNumber: header.sequenceNumber)
            packetSamples.append((now, data.count))
            updateRateFields(now: now)
            emitStatus()
        } catch {
            status.malformedPackets &+= 1
            status.warningText = "Malformed RTP packet"
            emitStatus()
        }
    }

    private func updateSequenceStats(sequenceNumber: UInt16) {
        guard let previous = lastSequenceNumber else {
            lastSequenceNumber = sequenceNumber
            return
        }

        let expected = previous &+ 1
        if sequenceNumber == expected {
            lastSequenceNumber = sequenceNumber
            return
        }

        if sequenceNumberIsBehind(sequenceNumber, expected) {
            status.outOfOrderPackets &+= 1
            return
        }

        status.sequenceGaps &+= UInt64(sequenceDistance(from: expected, to: sequenceNumber))
        lastSequenceNumber = sequenceNumber
    }

    private func sequenceDistance(from start: UInt16, to end: UInt16) -> UInt16 {
        end &- start
    }

    private func sequenceNumberIsBehind(_ sequence: UInt16, _ reference: UInt16) -> Bool {
        let diff = sequence &- reference
        return diff > 32768
    }

    private func startStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.updateRateFields(now: Date())
            self.emitStatus()
        }
        timer.resume()
        statsTimer = timer
    }

    private func updateRateFields(now: Date) {
        let cutoff = now.addingTimeInterval(-1)
        packetSamples.removeAll { $0.0 < cutoff }
        status.packetsPerSecond = Double(packetSamples.count)
        let bytesPerSecond = packetSamples.reduce(0) { $0 + $1.1 }
        status.bitrateKbps = Double(bytesPerSecond * 8) / 1000.0
        status.lastPacketAge = status.lastPacketReceivedAt.map { now.timeIntervalSince($0) }
    }

    private func emitStatus() {
        onStatus?(status)
    }
}
