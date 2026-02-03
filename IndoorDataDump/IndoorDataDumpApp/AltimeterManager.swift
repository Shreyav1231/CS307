import Foundation
import Combine
import CoreMotion

final class AltimeterManager: ObservableObject {
    @Published var pressure_kPa: Double?
    @Published var relAlt_m: Double?

    private let alt = CMAltimeter()

    func start() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        alt.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let d = data else { return }
            self?.pressure_kPa = d.pressure.doubleValue
            self?.relAlt_m = d.relativeAltitude.doubleValue
        }
    }

    func stop() {
        alt.stopRelativeAltitudeUpdates()
    }
}

