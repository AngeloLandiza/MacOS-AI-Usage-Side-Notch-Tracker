import Foundation
import SwiftUI

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    nonisolated static let scaleRange: ClosedRange<Double> = 0.8...1.4

    @Published var autoHide: Bool {
        didSet { UserDefaults.standard.set(autoHide, forKey: "autoHide") }
    }

    /// Multiplier applied to the notch's dimensions (rings, labels, width).
    @Published var scale: Double {
        didSet { UserDefaults.standard.set(scale, forKey: "notchScale") }
    }

    init() {
        autoHide = UserDefaults.standard.bool(forKey: "autoHide")
        let stored = UserDefaults.standard.double(forKey: "notchScale")
        scale = stored == 0 ? 1.0 : stored.clamped(to: Self.scaleRange)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
