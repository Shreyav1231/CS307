import SwiftUI
import Foundation

struct ExportView: View {
    @ObservedObject var app: AppState

    struct ShareItem: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    @State private var shareItem: ShareItem? = nil
    @State private var showError = false
    @State private var errorMsg = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // MARK: - Stats
                GroupBox("Session Stats") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Locations captured: \(app.sessions.count)")
                        
                        let totalCaptures = app.sessions.reduce(0) { $0 + $1.averagedFromCount }
                        if totalCaptures != app.sessions.count {
                            Text("Total captures: \(totalCaptures) (averaged into \(app.sessions.count) locations)")
                                .foregroundStyle(.secondary)
                        }
                        
                        let bleCount = app.sessions.reduce(0) { $0 + $1.bleSamples.count }
                        Text("Total BLE readings: \(bleCount)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                
                // MARK: - Export All
                GroupBox("Export All Data") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("📦 Export All Datasets (6 files)") {
                            exportAll()
                        }
                        .disabled(app.sessions.isEmpty)
                        .buttonStyle(.borderedProminent)
                        
                        Text("""
                        Exports:
                        • master_dataset.csv - Everything for reference
                        • ble_fingerprinting.csv - BLE signals + map position
                        • magnetic_fingerprinting.csv - Magnetic field + map position
                        • floor_detection.csv - Barometer/altitude + floor
                        • ibeacon_trilateration.csv - iBeacon data for 3-circle method
                        • ibeacon_registry_template.csv - Template to fill beacon positions
                        """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // MARK: - Individual Exports
                GroupBox("Individual Datasets") {
                    VStack(alignment: .leading, spacing: 12) {
                        
                        ExportButton(title: "Master Dataset", icon: "doc.fill") {
                            try writeMasterDataset()
                        }
                        
                        ExportButton(title: "BLE Fingerprinting", icon: "antenna.radiowaves.left.and.right") {
                            try writeBLEFingerprinting()
                        }
                        
                        ExportButton(title: "Magnetic Fingerprinting", icon: "location.north.fill") {
                            try writeMagneticFingerprinting()
                        }
                        
                        ExportButton(title: "Floor Detection", icon: "building.2.fill") {
                            try writeFloorDetection()
                        }
                        
                        ExportButton(title: "iBeacon Trilateration", icon: "point.3.connected.trianglepath.dotted") {
                            try writeIBeaconTrilateration()
                        }
                    }
                }
                
                Divider()
                
                // MARK: - Clear
                Button("Clear All Sessions") {
                    app.sessions.removeAll()
                }
                .foregroundStyle(.red)
                
                Spacer()
            }
            .padding()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.urls)
        }
        .alert("Export failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMsg)
        }
    }
    
    // MARK: - Export All
    
    private func exportAll() {
        do {
            var urls: [URL] = []
            urls.append(try writeMasterDataset())
            urls.append(try writeBLEFingerprinting())
            urls.append(try writeMagneticFingerprinting())
            urls.append(try writeFloorDetection())
            urls.append(try writeIBeaconTrilateration())
            urls.append(try writeIBeaconRegistryTemplate())
            shareItem = ShareItem(urls: urls)
        } catch {
            errorMsg = error.localizedDescription
            showError = true
        }
    }
    
    // MARK: - Helper View
    
    @ViewBuilder
    private func ExportButton(title: String, icon: String, action: @escaping () throws -> URL) -> some View {
        Button {
            do {
                let url = try action()
                shareItem = ShareItem(urls: [url])
            } catch {
                errorMsg = error.localizedDescription
                showError = true
            }
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(app.sessions.isEmpty)
    }
    
    // MARK: - File Writers
    
    private var docsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    /// 1. MASTER DATASET - Everything captured (for reference/debugging)
    private func writeMasterDataset() throws -> URL {
        let url = docsDir.appendingPathComponent("master_dataset.csv")
        
        let header = [
            // Identity
            "location_id",
            "timestamp",
            "captures_averaged",
            
            // Map Position (GROUND TRUTH)
            "floor_page",
            "map_x",
            "map_y",
            
            // GPS
            "gps_lat",
            "gps_lon",
            "gps_accuracy_m",
            
            // Magnetic Field
            "magnetic_field_uT",
            
            // Barometer
            "pressure_kPa",
            "relative_altitude_m",
            
            // BLE Summary
            "ble_devices_count",
            "ble_readings_count",
            "ibeacon_readings_count",
            
            // Data Quality
            "sensor_samples"
        ].joined(separator: ",")
        
        var lines = [header]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        for s in app.sessions {
            let cols: [String] = [
                s.id.uuidString,
                iso.string(from: s.timestamp),
                "\(s.averagedFromCount)",
                "\(s.anchor.pageIndex + 1)",
                fmt(s.anchor.xPDF, 1),
                fmt(s.anchor.yPDF, 1),
                fmt(s.summary.lat, 6),
                fmt(s.summary.lon, 6),
                fmt(s.summary.hAccM, 1),
                fmt(s.summary.magNormUT, 2),
                fmt(s.summary.pressureKPa, 3),
                fmt(s.summary.relAltM, 3),
                "\(s.summary.bleUniqueDevices)",
                "\(s.summary.bleSampleCount)",
                "\(s.summary.bleIBeaconSampleCount)",
                "\(s.summary.sampleCount)"
            ]
            lines.append(cols.joined(separator: ","))
        }
        
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    /// 2. BLE FINGERPRINTING - Device signals per location (pivoted for ML)
    /// Each row = one location, columns = device RSSI values
    private func writeBLEFingerprinting() throws -> URL {
        let url = docsDir.appendingPathComponent("ble_fingerprinting.csv")
        
        // Collect all unique device keys across all sessions
        var allDeviceKeys = Set<String>()
        for s in app.sessions {
            for sample in s.bleSamples {
                allDeviceKeys.insert(sample.deviceKey)
            }
        }
        let sortedDevices = allDeviceKeys.sorted()
        
        // Header: location info + one column per device
        var header = ["location_id", "floor_page", "map_x", "map_y"]
        header.append(contentsOf: sortedDevices.map { "ble_\($0.prefix(8))" })
        
        var lines = [header.joined(separator: ",")]
        
        for s in app.sessions {
            // Calculate median RSSI per device at this location
            var deviceRSSI: [String: [Int]] = [:]
            for sample in s.bleSamples {
                deviceRSSI[sample.deviceKey, default: []].append(sample.rssi)
            }
            
            var cols: [String] = [
                s.id.uuidString,
                "\(s.anchor.pageIndex + 1)",
                fmt(s.anchor.xPDF, 1),
                fmt(s.anchor.yPDF, 1)
            ]
            
            // Add RSSI for each device (median, or -100 if not seen)
            for device in sortedDevices {
                if let rssis = deviceRSSI[device], !rssis.isEmpty {
                    let median = rssis.sorted()[rssis.count / 2]
                    cols.append("\(median)")
                } else {
                    cols.append("-100") // Not detected = very weak signal
                }
            }
            
            lines.append(cols.joined(separator: ","))
        }
        
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    /// 3. MAGNETIC FINGERPRINTING - Magnetic field + map position
    private func writeMagneticFingerprinting() throws -> URL {
        let url = docsDir.appendingPathComponent("magnetic_fingerprinting.csv")
        
        let header = [
            "location_id",
            "floor_page",
            "map_x",
            "map_y",
            "magnetic_field_uT"
        ].joined(separator: ",")
        
        var lines = [header]
        
        for s in app.sessions {
            guard let mag = s.summary.magNormUT else { continue }
            
            let cols: [String] = [
                s.id.uuidString,
                "\(s.anchor.pageIndex + 1)",
                fmt(s.anchor.xPDF, 1),
                fmt(s.anchor.yPDF, 1),
                fmt(mag, 2)
            ]
            lines.append(cols.joined(separator: ","))
        }
        
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    /// 4. FLOOR DETECTION - Barometer + altitude + floor page
    private func writeFloorDetection() throws -> URL {
        let url = docsDir.appendingPathComponent("floor_detection.csv")
        
        let header = [
            "location_id",
            "floor_page",           // This is what you're trying to predict
            "pressure_kPa",
            "relative_altitude_m",
            "gps_lat",              // Include GPS for outdoor reference
            "gps_lon"
        ].joined(separator: ",")
        
        var lines = [header]
        
        for s in app.sessions {
            let cols: [String] = [
                s.id.uuidString,
                "\(s.anchor.pageIndex + 1)",
                fmt(s.summary.pressureKPa, 4),
                fmt(s.summary.relAltM, 3),
                fmt(s.summary.lat, 6),
                fmt(s.summary.lon, 6)
            ]
            lines.append(cols.joined(separator: ","))
        }
        
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    /// 5. iBEACON TRILATERATION - iBeacon signals for 3-circle method
    /// Each row = one iBeacon reading at one location
    private func writeIBeaconTrilateration() throws -> URL {
        let url = docsDir.appendingPathComponent("ibeacon_trilateration.csv")
        
        let header = [
            "location_id",
            "floor_page",
            "map_x",
            "map_y",
            
            // iBeacon identification (use this to look up beacon position)
            "ibeacon_uuid",
            "ibeacon_major",
            "ibeacon_minor",
            
            // Signal data
            "rssi_mean",
            "rssi_median",
            "rssi_std",
            "reading_count",
            
            // Estimated distance (you'll need to calibrate tx_power and n)
            "estimated_distance_m"
        ].joined(separator: ",")
        
        var lines = [header]
        
        for s in app.sessions {
            // Group iBeacon samples by beacon identity
            let ibeaconSamples = s.bleSamples.filter { $0.isIBeacon }
            
            // Group by UUID+Major+Minor
            var grouped: [String: [BLESample]] = [:]
            for sample in ibeaconSamples {
                guard let uuid = sample.iBeaconUUID,
                      let major = sample.iBeaconMajor,
                      let minor = sample.iBeaconMinor else { continue }
                let key = "\(uuid)|\(major)|\(minor)"
                grouped[key, default: []].append(sample)
            }
            
            for (key, samples) in grouped {
                let parts = key.split(separator: "|")
                guard parts.count == 3 else { continue }
                
                let rssis = samples.map { $0.rssi }
                let mean = Double(rssis.reduce(0, +)) / Double(rssis.count)
                let sorted = rssis.sorted()
                let median = Double(sorted[sorted.count / 2])
                let std = stddev(rssis)
                
                // Estimate distance (default calibration - you should tune these!)
                let txPower: Double = -59  // RSSI at 1 meter
                let n: Double = 2.5        // Path loss exponent (2.5-4.0 indoors)
                let distance = pow(10, (txPower - median) / (10 * n))
                
                let cols: [String] = [
                    s.id.uuidString,
                    "\(s.anchor.pageIndex + 1)",
                    fmt(s.anchor.xPDF, 1),
                    fmt(s.anchor.yPDF, 1),
                    String(parts[0]),
                    String(parts[1]),
                    String(parts[2]),
                    fmt(mean, 1),
                    fmt(median, 1),
                    fmt(std, 2),
                    "\(samples.count)",
                    fmt(distance, 2)
                ]
                lines.append(cols.joined(separator: ","))
            }
        }
        
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    /// 6. iBEACON REGISTRY TEMPLATE - Fill in beacon GPS positions
    private func writeIBeaconRegistryTemplate() throws -> URL {
        let url = docsDir.appendingPathComponent("ibeacon_registry_template.csv")
        
        // Collect all unique iBeacons
        var beacons = Set<String>()
        for s in app.sessions {
            for sample in s.bleSamples where sample.isIBeacon {
                if let uuid = sample.iBeaconUUID,
                   let major = sample.iBeaconMajor,
                   let minor = sample.iBeaconMinor {
                    beacons.insert("\(uuid)|\(major)|\(minor)")
                }
            }
        }
        
        let header = [
            "ibeacon_uuid",
            "ibeacon_major",
            "ibeacon_minor",
            "beacon_gps_lat",        // YOU FILL THIS IN
            "beacon_gps_lon",        // YOU FILL THIS IN
            "beacon_floor_page",     // YOU FILL THIS IN
            "beacon_map_x",          // YOU FILL THIS IN (optional)
            "beacon_map_y",          // YOU FILL THIS IN (optional)
            "tx_power_dBm",          // Calibrated TX power at 1m (default -59)
            "notes"
        ].joined(separator: ",")
        
        var lines = [header]
        
        for beacon in beacons.sorted() {
            let parts = beacon.split(separator: "|")
            guard parts.count == 3 else { continue }
            
            let cols: [String] = [
                String(parts[0]),
                String(parts[1]),
                String(parts[2]),
                "",  // beacon_gps_lat - FILL IN
                "",  // beacon_gps_lon - FILL IN
                "",  // beacon_floor_page - FILL IN
                "",  // beacon_map_x - FILL IN
                "",  // beacon_map_y - FILL IN
                "-59",  // default tx_power
                ""   // notes
            ]
            lines.append(cols.joined(separator: ","))
        }
        
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    // MARK: - Helpers
    
    private func fmt(_ value: Double?, _ decimals: Int) -> String {
        guard let v = value else { return "" }
        return String(format: "%.\(decimals)f", v)
    }
    
    private func stddev(_ values: [Int]) -> Double? {
        guard values.count >= 2 else { return nil }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }
    
    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
