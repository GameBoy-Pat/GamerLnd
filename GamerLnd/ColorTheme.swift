// ColorTheme.swift
// Unified app color scheme locked to dark mode for now.
// IMPORTANT (Beginners):
// • Views should reference ColorTheme.* instead of hardcoding colors.
// • GamerLnd is currently dark-mode only.

import SwiftUI
import UIKit

struct ColorTheme {
    // MARK: - Theme Switch
    static var preferredScheme: ColorScheme? {
        .dark
    }

    private static var isDark: Bool {
        true
    }

    // MARK: - Core Backgrounds
    static var background: Color {
        isDark ? Color(red: 0.06, green: 0.06, blue: 0.07)
               : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    static var surface: Color {
        isDark ? Color(red: 0.12, green: 0.12, blue: 0.13)
               : Color(red: 0.99, green: 0.99, blue: 1.00)
    }

    // MARK: - Text
    static var text: Color {
        isDark ? .white : .black
    }

    static var subtext: Color {
        isDark ? Color.white.opacity(0.74)
               : Color.black.opacity(0.7)
    }

    // MARK: - Accents
    static var accent: Color {
        gold
    }

    static var highlight: Color {
        Color("SecondaryHighlightColor")
    }

    static var gold: Color {
        Color(red: 250/255, green: 193/255, blue: 67/255)
    }

    static var xpGreen: Color {
        Color(red: 145/255, green: 222/255, blue: 139/255)
    }

    static var perfectScoreRainbow: [Color] {
        [
            Color(red: 1.00, green: 0.36, blue: 0.42),
            Color(red: 1.00, green: 0.61, blue: 0.22),
            Color(red: 0.98, green: 0.88, blue: 0.24),
            Color(red: 0.33, green: 0.88, blue: 0.48),
            Color(red: 0.28, green: 0.71, blue: 0.98),
            Color(red: 0.59, green: 0.42, blue: 0.98)
        ]
    }

    // MARK: - Utility
    static var separator: Color {
        isDark ? Color.white.opacity(0.12)
               : Color.black.opacity(0.08)
    }

    // Explicit helpers to keep existing code compiling
    static var green: Color { accent }
    static var black: Color { .black }
    static var success: Color { accent }
    static var danger: Color  { .red }
    static var warning: Color { .orange }

    static func ratingBandColor(for value: Double) -> Color {
        switch value {
        case ..<4.0: return .red
        case 4.0..<6.0: return .orange
        case 6.0..<7.0: return .yellow
        case 7.0..<8.0: return .green
        case 8.0..<9.0: return .blue
        default: return Color(red: 0.54, green: 0.34, blue: 0.96)
        }
    }

    static func isPerfectScore(_ value: Double) -> Bool {
        value >= 9.95
    }
}
