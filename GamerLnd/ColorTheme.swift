// ColorTheme.swift
// Unified app color scheme with light/dark palettes.
// IMPORTANT (Beginners):
// • Views should reference ColorTheme.* instead of hardcoding colors.
// • GamerLnd enforces Dark Mode globally, but this setup keeps light mode support flexible.

import SwiftUI
import UIKit

struct ColorTheme {
    // MARK: - Theme Switch
    private static var themeMode: String {
        UserDefaults.standard.string(forKey: "themeMode") ?? "dark"
    }

    static var preferredScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private static var isDark: Bool {
        switch themeMode {
        case "light": return false
        case "dark": return true
        default:
            return UITraitCollection.current.userInterfaceStyle == .dark
        }
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
        Color("PrimaryAccentColor")
    }

    static var highlight: Color {
        Color("SecondaryHighlightColor")
    }

    static var gold: Color {
        Color(red: 241/255, green: 195/255, blue: 92/255)
    }

    // MARK: - Utility
    static var separator: Color {
        isDark ? Color.white.opacity(0.12)
               : Color.black.opacity(0.08)
    }

    // Explicit helpers to keep existing code compiling
    static var green: Color { .green }
    static var black: Color { .black }
    static var success: Color { .green }
    static var danger: Color  { .red }
    static var warning: Color { .orange }
}
