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
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let softImpactGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let successGenerator = UINotificationFeedbackGenerator()
    private static let warningGenerator = UINotificationFeedbackGenerator()
    private static let errorGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func play(_ h: Haptic) {
        switch h {
        case .tap:
            lightImpact.prepare()
            lightImpact.impactOccurred()
        case .success:
            successGenerator.prepare()
            successGenerator.notificationOccurred(.success)
        case .warning:
            warningGenerator.prepare()
            warningGenerator.notificationOccurred(.warning)
        case .error:
            errorGenerator.prepare()
            errorGenerator.notificationOccurred(.error)
        case .softImpact:
            softImpactGenerator.prepare()
            softImpactGenerator.impactOccurred()
        case .rigidImpact:
            rigidImpactGenerator.prepare()
            rigidImpactGenerator.impactOccurred()
        case .selection:
            selectionGenerator.prepare()
            selectionGenerator.selectionChanged()
        }
    }

    // Convenience aliases used in older code paths
    static func tap() { play(.tap) }
    static func success() { play(.success) }
    static func commit() { play(.rigidImpact) }
    static func softImpact() { play(.softImpact) }
    static func select() { play(.selection) }
}
