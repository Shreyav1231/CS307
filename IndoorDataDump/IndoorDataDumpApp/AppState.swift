import Foundation
import Combine

final class AppState: ObservableObject {
    
    // MARK: - File paths for persistence
    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    private static var sessionsFileURL: URL {
        documentsDirectory.appendingPathComponent("sessions.json")
    }
    private static var markersFileURL: URL {
        documentsDirectory.appendingPathComponent("markers.json")
    }
    private static let pdfURLKey = "savedPDFURL"
    private static let selectedAnchorKey = "selectedAnchor"
    private static let lastCapturedAnchorKey = "lastCapturedAnchor"
    
    @Published var pdfURL: URL? = nil {
        didSet {
            // Clear markers when importing a NEW PDF (different file)
            if let newURL = pdfURL, let oldURL = oldValue {
                if newURL.lastPathComponent != oldURL.lastPathComponent {
                    clearAllMarkers()
                }
            }
            savePDFURL()
        }
    }

    // current selection (red)
    @Published var selectedAnchor: SelectedAnchor? = nil {
        didSet { saveAnchors() }
    }

    // last successfully captured point (orange)
    @Published var lastCapturedAnchor: SelectedAnchor? = nil {
        didSet { saveAnchors() }
    }

    @Published var sessions: [CaptureSession] = [] {
        didSet { saveSessions() }
    }
    
    // Per-page marker storage: pageIndex -> [MarkerPoint]
    @Published var pageMarkers: [Int: [MarkerPoint]] = [:] {
        didSet { saveMarkers() }
    }
    
    // MARK: - Initialization
    
    init() {
        loadAll()
    }
    
    // MARK: - Marker Management
    
    // Add a marker for the given page
    func addMarker(pageIndex: Int, x: Double, y: Double, captureCount: Int = 1) {
        var markers = pageMarkers[pageIndex] ?? []
        
        // Check if there's already a marker very close (for averaging display)
        let threshold: Double = 18.0
        if let idx = markers.firstIndex(where: { hypot($0.x - x, $0.y - y) <= threshold }) {
            // Merge with existing marker
            let old = markers[idx]
            let n = Double(old.captureCount)
            markers[idx] = MarkerPoint(
                x: (old.x * n + x) / (n + 1),
                y: (old.y * n + y) / (n + 1),
                captureCount: old.captureCount + captureCount
            )
        } else {
            markers.append(MarkerPoint(x: x, y: y, captureCount: captureCount))
        }
        
        pageMarkers[pageIndex] = markers
    }
    
    // Clear markers for a specific page
    func clearMarkers(forPage pageIndex: Int) {
        pageMarkers[pageIndex] = []
        // Also clear sessions for this page
        sessions.removeAll { $0.anchor.pageIndex == pageIndex }
    }
    
    // Clear all markers
    func clearAllMarkers() {
        pageMarkers.removeAll()
        sessions.removeAll()
        selectedAnchor = nil
        lastCapturedAnchor = nil
    }
    
    // MARK: - Persistence: Save
    
    private func savePDFURL() {
        if let url = pdfURL {
            UserDefaults.standard.set(url.path, forKey: Self.pdfURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pdfURLKey)
        }
    }
    
    private func saveAnchors() {
        if let data = try? JSONEncoder().encode(selectedAnchor) {
            UserDefaults.standard.set(data, forKey: Self.selectedAnchorKey)
        }
        if let data = try? JSONEncoder().encode(lastCapturedAnchor) {
            UserDefaults.standard.set(data, forKey: Self.lastCapturedAnchorKey)
        }
    }
    
    private func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: Self.sessionsFileURL, options: .atomic)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }
    
    private func saveMarkers() {
        do {
            let data = try JSONEncoder().encode(pageMarkers)
            try data.write(to: Self.markersFileURL, options: .atomic)
        } catch {
            print("Failed to save markers: \(error)")
        }
    }
    
    // MARK: - Persistence: Load
    
    private func loadAll() {
        loadPDFURL()
        loadAnchors()
        loadSessions()
        loadMarkers()
    }
    
    private func loadPDFURL() {
        if let path = UserDefaults.standard.string(forKey: Self.pdfURLKey) {
            let url = URL(fileURLWithPath: path)
            // Only restore if file still exists
            if FileManager.default.fileExists(atPath: path) {
                pdfURL = url
            }
        }
    }
    
    private func loadAnchors() {
        if let data = UserDefaults.standard.data(forKey: Self.selectedAnchorKey),
           let anchor = try? JSONDecoder().decode(SelectedAnchor?.self, from: data) {
            selectedAnchor = anchor
        }
        if let data = UserDefaults.standard.data(forKey: Self.lastCapturedAnchorKey),
           let anchor = try? JSONDecoder().decode(SelectedAnchor?.self, from: data) {
            lastCapturedAnchor = anchor
        }
    }
    
    private func loadSessions() {
        do {
            let data = try Data(contentsOf: Self.sessionsFileURL)
            sessions = try JSONDecoder().decode([CaptureSession].self, from: data)
        } catch {
            // File doesn't exist yet or decode failed - start fresh
            sessions = []
        }
    }
    
    private func loadMarkers() {
        do {
            let data = try Data(contentsOf: Self.markersFileURL)
            pageMarkers = try JSONDecoder().decode([Int: [MarkerPoint]].self, from: data)
        } catch {
            // File doesn't exist yet or decode failed - start fresh
            pageMarkers = [:]
        }
    }
}

// Represents a persistent marker on the floor plan
struct MarkerPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var captureCount: Int
}
