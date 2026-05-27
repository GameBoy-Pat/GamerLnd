import Foundation

enum ProfileIdentityValidator {
    static let minDisplayNameLength = 2
    static let maxDisplayNameLength = 32
    static let minHandleLength = 3
    static let maxHandleLength = 20

    private static let allowedHandleScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")

    static func normalizedDisplayName(_ raw: String) -> String {
        raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func sanitizedHandleInput(_ raw: String) -> String {
        let lowered = raw
            .replacingOccurrences(of: "@", with: "")
            .lowercased()

        let filtered = lowered.unicodeScalars.filter { scalar in
            allowedHandleScalars.contains(scalar)
        }

        return String(String.UnicodeScalarView(filtered))
    }

    static func displayNameError(_ raw: String) -> String? {
        let normalized = normalizedDisplayName(raw)
        if normalized.count < minDisplayNameLength || normalized.count > maxDisplayNameLength {
            return "Display names must be \(minDisplayNameLength)-\(maxDisplayNameLength) characters."
        }
        if ContentModeration.containsForbiddenProfileText(normalized) {
            return "Display names cannot include profanity."
        }
        return nil
    }

    static func handleError(_ raw: String) -> String? {
        let handle = sanitizedHandleInput(raw)
        if handle.count < minHandleLength || handle.count > maxHandleLength {
            return "Handles must be \(minHandleLength)-\(maxHandleLength) characters."
        }
        if handle.range(of: "^[a-z0-9._-]+$", options: .regularExpression) == nil {
            return "Handles can use letters, numbers, ., _, and -"
        }
        if ContentModeration.containsForbiddenProfileText(handle) {
            return "Handles cannot include profanity."
        }
        return nil
    }
}
