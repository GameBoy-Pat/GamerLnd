// Haptics.swift
// Centralized haptics. Matches call sites used across the app (tap, success, commit, softImpact).

import UIKit

enum Haptic {
    case tap
    case success
    case warning
    case error
    case softImpact
    case rigidImpact
    case selection
}

enum Haptics {
    static func play(_ h: Haptic) {
        switch h {
        case .tap:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .softImpact:
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.prepare(); gen.impactOccurred()
        case .rigidImpact:
            let gen = UIImpactFeedbackGenerator(style: .rigid)
            gen.prepare(); gen.impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // Convenience aliases used in older code paths
    static func tap() { play(.tap) }
    static func success() { play(.success) }
    static func commit() { play(.rigidImpact) }
    static func softImpact() { play(.softImpact) }
    static func select() { play(.selection) }
}
