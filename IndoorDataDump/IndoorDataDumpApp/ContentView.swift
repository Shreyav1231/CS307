import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppState()

    var body: some View {
        TabView {
            FloorPlanView(app: app)
                .tabItem { Label("Plan", systemImage: "map") }

            CaptureView(app: app)
                .tabItem { Label("Capture", systemImage: "dot.radiowaves.left.and.right") }

            ExportView(app: app)
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
    }
}


