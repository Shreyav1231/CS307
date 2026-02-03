import Foundation

struct Sample: Codable {
    var t: Date

    // GPS / CoreLocation
    var lat: Double?
    var lon: Double?
    var hAccM: Double?
    var speedMps: Double?
    var courseDeg: Double?

    // Magnetometer (µT) + Gyro (rad/s)
    var magX: Double?
    var magY: Double?
    var magZ: Double?
    var gyroX: Double?
    var gyroY: Double?
    var gyroZ: Double?

    // Barometer
    var pressureKPa: Double?
    var relAltM: Double?
}

struct CaptureSummary: Codable {
    // GPS summary
    var lat: Double?
    var lon: Double?
    var hAccM: Double?

    // Sensor summaries
    var magNormUT: Double?
    var pressureKPa: Double?
    var relAltM: Double?

    // BLE summaries (supports fingerprinting + trilateration later)
    var bleUniqueDevices: Int
    var bleSampleCount: Int
    var bleIBeaconSampleCount: Int

    var sampleCount: Int
}

struct CaptureSession: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date
    var anchor: SelectedAnchor
    var summary: CaptureSummary
    var samples: [Sample]

    // Raw BLE samples (the key dataset)
    var bleSamples: [BLESample]
    
    // How many captures were averaged to create this session
    var averagedFromCount: Int = 1
}

