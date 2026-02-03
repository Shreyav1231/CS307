import Foundation
import Combine
import CoreBluetooth
import CryptoKit

// One raw BLE observation ("sample") during a session
struct BLESample: Codable, Hashable {
    var sessionID: String
    var tOffsetMs: Int
    var deviceKey: String          // hashed stable key
    var rawPeripheralID: String    // peripheral.identifier.uuidString (debug/stability)
    var rssi: Int

    var localName: String?
    var isIBeacon: Bool
    var iBeaconUUID: String?
    var iBeaconMajor: Int?
    var iBeaconMinor: Int?
}

private func sha256Hex(_ s: String) -> String {
    let digest = SHA256.hash(data: Data(s.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

// Parses iBeacon payload from manufacturer data if present.
// iBeacon format inside manufacturer data:
// [0..1] Apple company ID 0x004C (little endian => 4C 00)
// [2] type = 0x02
// [3] len  = 0x15
// [4..19] UUID (16 bytes)
// [20..21] major (big endian)
// [22..23] minor (big endian)
// [24] tx power
private func parseIBeacon(from advertisementData: [String: Any]) -> (uuid: UUID, major: Int, minor: Int)? {
    guard let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return nil }
    let bytes = [UInt8](mfg)
    guard bytes.count >= 25 else { return nil }

    // Apple company ID 0x004C => 4C 00
    guard bytes[0] == 0x4C, bytes[1] == 0x00 else { return nil }
    guard bytes[2] == 0x02, bytes[3] == 0x15 else { return nil }

    let uuid = UUID(uuid: (
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15],
        bytes[16], bytes[17], bytes[18], bytes[19]
    ))

    let major = (Int(bytes[20]) << 8) | Int(bytes[21])
    let minor = (Int(bytes[22]) << 8) | Int(bytes[23])

    return (uuid, major, minor)
}

final class BLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published private(set) var isScanning = false
    @Published private(set) var stateDescription: String = "unknown"

    private var central: CBCentralManager!
    private let queue = DispatchQueue(label: "ble.scanner.queue")

    private var startTime: Date?
    private var currentSessionID: String?
    private var pendingStart = false

    private var samples: [BLESample] = []
    private var seenCount: [String: Int] = [:] // deviceKey -> sample count

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let desc: String
        switch central.state {
        case .poweredOn: desc = "poweredOn"
        case .poweredOff: desc = "poweredOff"
        case .unauthorized: desc = "unauthorized"
        case .unsupported: desc = "unsupported"
        case .resetting: desc = "resetting"
        case .unknown: fallthrough
        @unknown default: desc = "unknown"
        }

        DispatchQueue.main.async { self.stateDescription = desc }

        if central.state == .poweredOn && pendingStart {
            pendingStart = false
            startScanInternal()
        }
    }

    /// Call at capture start
    func start(sessionID: String) {
        queue.async {
            self.currentSessionID = sessionID
            self.startTime = Date()
            self.samples.removeAll(keepingCapacity: true)
            self.seenCount.removeAll(keepingCapacity: true)

            if self.central.state == .poweredOn {
                self.startScanInternal()
            } else {
                self.pendingStart = true
            }
        }
    }

    /// Call at capture end
    func stopAndGetSamples() -> [BLESample] {
        var out: [BLESample] = []
        queue.sync {
            if self.central.isScanning { self.central.stopScan() }
            self.pendingStart = false
            self.isScanning = false
            out = self.samples
            self.samples = []
            self.seenCount = [:]
            self.startTime = nil
            self.currentSessionID = nil
        }
        DispatchQueue.main.async { self.isScanning = false }
        return out
    }

    func snapshotSummary() -> (uniqueDevices: Int, totalSamples: Int) {
        var u = 0
        var t = 0
        queue.sync {
            u = seenCount.keys.count
            t = samples.count
        }
        return (u, t)
    }

    private func startScanInternal() {
        guard !central.isScanning else { return }

        let opts: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ]
        central.scanForPeripherals(withServices: nil, options: opts)

        DispatchQueue.main.async { self.isScanning = true }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        guard let sessionID = currentSessionID,
              let startTime = startTime else { return }

        let tOffset = Int(Date().timeIntervalSince(startTime) * 1000.0)

        // local name if present; peripheral.name often nil unless connected
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name

        let rawID = peripheral.identifier.uuidString
        let deviceKey = sha256Hex(rawID)

        let beacon = parseIBeacon(from: advertisementData)

        let sample = BLESample(
            sessionID: sessionID,
            tOffsetMs: tOffset,
            deviceKey: deviceKey,
            rawPeripheralID: rawID,
            rssi: RSSI.intValue,
            localName: localName,
            isIBeacon: beacon != nil,
            iBeaconUUID: beacon?.uuid.uuidString,
            iBeaconMajor: beacon?.major,
            iBeaconMinor: beacon?.minor
        )

        samples.append(sample)
        seenCount[deviceKey, default: 0] += 1
    }
}

