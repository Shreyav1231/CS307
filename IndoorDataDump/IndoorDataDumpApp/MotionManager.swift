import Foundation
import Combine
import CoreMotion

final class MotionManager: ObservableObject {
    private let mm = CMMotionManager()
    private let q = OperationQueue()

    @Published var latest: CMDeviceMotion?

    func start() {
        guard mm.isDeviceMotionAvailable else { return }
        mm.deviceMotionUpdateInterval = 1.0 / 50.0  // 50 Hz

        mm.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: q) { [weak self] motion, _ in
            guard let motion else { return }
            DispatchQueue.main.async {
                self?.latest = motion
            }
        }
    }

    func stop() {
        mm.stopDeviceMotionUpdates()
    }
}

