import SwiftUI
import Combine
import CoreMotion
import CoreLocation

struct CaptureView: View {
    @ObservedObject var app: AppState

    @StateObject private var motion = MotionManager()
    @StateObject private var alt = AltimeterManager()
    @StateObject private var loc = LocationManager()

    // BLE
    @StateObject private var ble = BLEScanner()

    @State private var rolling: [Sample] = []

    private let prewarmSeconds: Double = 3.0
    private let captureSeconds: Double = 6.0

    @State private var isCapturing = false
    @State private var captureEndsAt: Date? = nil
    
    // Threshold for considering two points as "same location"
    private let sameLocationThreshold: Double = 18.0

    // 20 Hz sampling into the buffer
    private let timer = Timer.publish(every: 1.0/20.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            GroupBox("Selected Point") {
                if let a = app.selectedAnchor {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Page: \(a.pageIndex + 1)  |  X: \(Int(a.xPDF))  Y: \(Int(a.yPDF))")
                            .font(.callout)
                        
                        // Show if this location has existing captures
                        let existingCount = countCapturesNearLocation(a)
                        if existingCount > 0 {
                            Text("📍 \(existingCount) capture\(existingCount == 1 ? "" : "s") at this location - data will be averaged")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                } else {
                    Text("Go to Plan tab and tap a point first.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Capture") {
                HStack {
                    Button(isCapturing ? "Capturing…" : "Auto Collect") {
                        startCapture()
                    }
                    .disabled(app.selectedAnchor == nil || isCapturing)

                    Spacer()

                    if let end = captureEndsAt, isCapturing {
                        Text("Ends: \(end.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Uses \(Int(prewarmSeconds))s prewarm + \(Int(captureSeconds))s capture (buffered)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox("Live (sanity check)") {
                VStack(alignment: .leading, spacing: 6) {
                    // GPS
                    if let l = loc.latest {
                        Text("GPS: \(l.coordinate.latitude, specifier: "%.6f"), \(l.coordinate.longitude, specifier: "%.6f")")
                        Text("hAcc (m): \(l.horizontalAccuracy, specifier: "%.1f")  speed: \(validSpeed(l), specifier: "%.2f")  course: \(validCourse(l), specifier: "%.1f")")
                    } else {
                        Text("GPS: (waiting…)  auth=\(authText(loc.authorization))")
                            .foregroundStyle(.secondary)
                    }

                    // Magnetometer (and gyro axes, not summarized)
                    if let m = motion.latest {
                        let mag = m.magneticField.field
                        Text("Mag µT: x \(mag.x, specifier: "%.1f")  y \(mag.y, specifier: "%.1f")  z \(mag.z, specifier: "%.1f")")

                        let g = m.rotationRate
                        Text("Gyro: x \(g.x, specifier: "%.2f")  y \(g.y, specifier: "%.2f")  z \(g.z, specifier: "%.2f")")
                    } else {
                        Text("Motion: (starting…)").foregroundStyle(.secondary)
                    }

                    // Barometer
                    if let p = alt.pressure_kPa {
                        Text("Pressure kPa: \(p, specifier: "%.3f")")
                    } else {
                        Text("Pressure: (starting…)").foregroundStyle(.secondary)
                    }

                    if let ra = alt.relAlt_m {
                        Text("Rel Alt m: \(ra, specifier: "%.3f")")
                    } else {
                        Text("Rel Alt: (starting…)").foregroundStyle(.secondary)
                    }

                    // BLE
                    let snap = ble.snapshotSummary()
                    Text("BLE: \(ble.stateDescription)  scanning=\(ble.isScanning ? "yes" : "no")  unique=\(snap.uniqueDevices)  samples=\(snap.totalSamples)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            if let last = app.sessions.last {
                GroupBox("Last Summary") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Samples: \(last.summary.sampleCount)")
                        Text("GPS: \(fmt6(last.summary.lat)), \(fmt6(last.summary.lon))  hAcc(m): \(fmt1(last.summary.hAccM))")
                        Text("Mag norm (µT): \(fmt4(last.summary.magNormUT))")
                        Text("Pressure kPa: \(fmt4(last.summary.pressureKPa))")
                        Text("Rel Alt m: \(fmt4(last.summary.relAltM))")
                        Text("BLE unique: \(last.summary.bleUniqueDevices)  BLE samples: \(last.summary.bleSampleCount)  iBeacon samples: \(last.summary.bleIBeaconSampleCount)")
                        
                        if last.averagedFromCount > 1 {
                            Text("📊 Averaged from \(last.averagedFromCount) captures")
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            motion.start()
            alt.start()
            loc.start()
        }
        .onDisappear {
            motion.stop()
            alt.stop()
            loc.stop()
        }
        .onReceive(timer) { _ in
            tickSample()
        }
    }
    
    /// Count existing captures near a given anchor location
    private func countCapturesNearLocation(_ anchor: SelectedAnchor) -> Int {
        return app.sessions.filter { session in
            session.anchor.pageIndex == anchor.pageIndex &&
            hypot(session.anchor.xPDF - anchor.xPDF, session.anchor.yPDF - anchor.yPDF) <= sameLocationThreshold
        }.count
    }

    private func tickSample() {
        let now = Date()
        var s = Sample(t: now)

        // GPS snapshot
        if let l = loc.latest {
            s.lat = l.coordinate.latitude
            s.lon = l.coordinate.longitude
            s.hAccM = l.horizontalAccuracy
            s.speedMps = (l.speed >= 0) ? l.speed : nil
            s.courseDeg = (l.course >= 0) ? l.course : nil
        }

        // Motion snapshot (mag + gyro axes)
        if let m = motion.latest {
            let mag = m.magneticField.field
            s.magX = mag.x
            s.magY = mag.y
            s.magZ = mag.z

            let g = m.rotationRate
            s.gyroX = g.x
            s.gyroY = g.y
            s.gyroZ = g.z
        }

        // Barometer snapshot
        s.pressureKPa = alt.pressure_kPa
        s.relAltM = alt.relAlt_m

        rolling.append(s)

        // keep last 30 seconds
        let cutoff = now.addingTimeInterval(-30.0)
        while let first = rolling.first, first.t < cutoff {
            rolling.removeFirst()
        }
    }

    private func startCapture() {
        guard let anchor = app.selectedAnchor else { return }
        isCapturing = true

        let start = Date()
        let end = start.addingTimeInterval(captureSeconds)
        captureEndsAt = end

        // BLE session id (independent of CaptureSession UUID)
        let bleSessionID = UUID().uuidString
        ble.start(sessionID: bleSessionID)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(captureSeconds * 1_000_000_000))

            // Stop BLE and get raw samples
            let bleSamples = ble.stopAndGetSamples()
            let uniqueBLE = Set(bleSamples.map { $0.deviceKey }).count
            let ibeaconCount = bleSamples.filter { $0.isIBeacon }.count

            // Use buffered prewarm for other sensors
            let usedStart = start.addingTimeInterval(-prewarmSeconds)
            let usedEnd = end
            let usedSamples = rolling.filter { $0.t >= usedStart && $0.t <= usedEnd }

            var summary = summarize(samples: usedSamples, windowCount: 5)
            summary.bleUniqueDevices = uniqueBLE
            summary.bleSampleCount = bleSamples.count
            summary.bleIBeaconSampleCount = ibeaconCount

            var session = CaptureSession(
                timestamp: start,
                anchor: anchor,
                summary: summary,
                samples: usedSamples,
                bleSamples: bleSamples
            )

            await MainActor.run {
                // Check for existing sessions at the same location and average
                let existingSessions = app.sessions.filter { s in
                    s.anchor.pageIndex == anchor.pageIndex &&
                    hypot(s.anchor.xPDF - anchor.xPDF, s.anchor.yPDF - anchor.yPDF) <= sameLocationThreshold
                }
                
                if !existingSessions.isEmpty {
                    // Average with existing sessions
                    session = averageSessions(existing: existingSessions, new: session)
                    
                    // Remove old sessions at this location
                    app.sessions.removeAll { s in
                        s.anchor.pageIndex == anchor.pageIndex &&
                        hypot(s.anchor.xPDF - anchor.xPDF, s.anchor.yPDF - anchor.yPDF) <= sameLocationThreshold
                    }
                }
                
                app.sessions.append(session)
                
                // Add persistent marker
                app.addMarker(pageIndex: anchor.pageIndex, x: anchor.xPDF, y: anchor.yPDF)
                
                app.lastCapturedAnchor = anchor
                isCapturing = false
                captureEndsAt = nil
            }
        }
    }
    
    /// Averages multiple sessions at the same location
    private func averageSessions(existing: [CaptureSession], new: CaptureSession) -> CaptureSession {
        // Combine all sessions including the new one
        var allSessions = existing
        allSessions.append(new)
        
        let totalCount = allSessions.reduce(0) { $0 + $1.averagedFromCount }
        
        // Average the summaries
        let avgSummary = averageSummaries(allSessions.map { $0.summary })
        
        // Combine all BLE samples for fingerprinting (more data = better)
        let combinedBLESamples = allSessions.flatMap { $0.bleSamples }
        
        // Use the newest anchor position
        let avgAnchor = SelectedAnchor(
            pageIndex: new.anchor.pageIndex,
            xPDF: allSessions.map { $0.anchor.xPDF }.reduce(0, +) / Double(allSessions.count),
            yPDF: allSessions.map { $0.anchor.yPDF }.reduce(0, +) / Double(allSessions.count)
        )
        
        return CaptureSession(
            timestamp: new.timestamp,
            anchor: avgAnchor,
            summary: avgSummary,
            samples: new.samples,  // Keep only the newest raw samples
            bleSamples: combinedBLESamples,
            averagedFromCount: totalCount
        )
    }
    
    /// Averages multiple capture summaries
    private func averageSummaries(_ summaries: [CaptureSummary]) -> CaptureSummary {
        guard !summaries.isEmpty else {
            return CaptureSummary(
                lat: nil, lon: nil, hAccM: nil,
                magNormUT: nil, pressureKPa: nil, relAltM: nil,
                bleUniqueDevices: 0, bleSampleCount: 0, bleIBeaconSampleCount: 0,
                sampleCount: 0
            )
        }
        
        func avgOpt(_ values: [Double?]) -> Double? {
            let valid = values.compactMap { $0 }
            guard !valid.isEmpty else { return nil }
            return valid.reduce(0, +) / Double(valid.count)
        }
        
        return CaptureSummary(
            lat: avgOpt(summaries.map { $0.lat }),
            lon: avgOpt(summaries.map { $0.lon }),
            hAccM: avgOpt(summaries.map { $0.hAccM }),
            magNormUT: avgOpt(summaries.map { $0.magNormUT }),
            pressureKPa: avgOpt(summaries.map { $0.pressureKPa }),
            relAltM: avgOpt(summaries.map { $0.relAltM }),
            bleUniqueDevices: summaries.map { $0.bleUniqueDevices }.reduce(0, +),
            bleSampleCount: summaries.map { $0.bleSampleCount }.reduce(0, +),
            bleIBeaconSampleCount: summaries.map { $0.bleIBeaconSampleCount }.reduce(0, +),
            sampleCount: summaries.map { $0.sampleCount }.reduce(0, +)
        )
    }

    // Median of window means (your existing approach)
    private func summarize(samples: [Sample], windowCount: Int) -> CaptureSummary {
        guard samples.count >= 2 else {
            return CaptureSummary(
                lat: nil, lon: nil, hAccM: nil,
                magNormUT: nil, pressureKPa: nil, relAltM: nil,
                bleUniqueDevices: 0, bleSampleCount: 0, bleIBeaconSampleCount: 0,
                sampleCount: samples.count
            )
        }

        let t0 = samples.first!.t
        let t1 = samples.last!.t
        let total = t1.timeIntervalSince(t0)
        let w = max(total / Double(windowCount), 0.001)

        func windowMeans(_ values: (Sample) -> Double?) -> [Double] {
            var means: [Double] = []
            for i in 0..<windowCount {
                let a = t0.addingTimeInterval(Double(i) * w)
                let b = t0.addingTimeInterval(Double(i + 1) * w)
                let vs = samples.compactMap { s -> Double? in
                    guard s.t >= a && s.t < b else { return nil }
                    return values(s)
                }
                if let m = mean(vs) { means.append(m) }
            }
            return means
        }

        func magNorm(_ s: Sample) -> Double? {
            guard let x = s.magX, let y = s.magY, let z = s.magZ else { return nil }
            return (x*x + y*y + z*z).squareRoot()
        }

        let latMed  = median(windowMeans { $0.lat })
        let lonMed  = median(windowMeans { $0.lon })
        let hAccMed = median(windowMeans { $0.hAccM })

        let magMed  = median(windowMeans(magNorm))
        let pMed    = median(windowMeans { $0.pressureKPa })
        let raMed   = median(windowMeans { $0.relAltM })

        return CaptureSummary(
            lat: latMed,
            lon: lonMed,
            hAccM: hAccMed,
            magNormUT: magMed,
            pressureKPa: pMed,
            relAltM: raMed,
            bleUniqueDevices: 0,
            bleSampleCount: 0,
            bleIBeaconSampleCount: 0,
            sampleCount: samples.count
        )
    }

    private func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        if s.count % 2 == 1 { return s[s.count / 2] }
        return (s[s.count/2 - 1] + s[s.count/2]) / 2.0
    }

    // Formatting helpers
    private func fmt6(_ x: Double?) -> String {
        guard let x else { return "—" }
        return String(format: "%.6f", x)
    }
    private func fmt4(_ x: Double?) -> String {
        guard let x else { return "—" }
        return String(format: "%.4f", x)
    }
    private func fmt1(_ x: Double?) -> String {
        guard let x else { return "—" }
        return String(format: "%.1f", x)
    }

    private func authText(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        @unknown default: return "unknown"
        }
    }

    private func validSpeed(_ l: CLLocation) -> Double { (l.speed >= 0) ? l.speed : 0.0 }
    private func validCourse(_ l: CLLocation) -> Double { (l.course >= 0) ? l.course : 0.0 }
}

