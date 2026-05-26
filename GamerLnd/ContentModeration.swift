import Foundation

enum ContentModeration {
    static let censorReviewsKey = "censorProfanityInReviews"
    static let censorCommentsKey = "censorProfanityInComments"

    // Intentionally conservative beta list: common profanity + a few clear slurs.
    private static let blockedRoots: [String] = [
        "asshole", "bastard", "bitch", "bullshit", "cock", "cunt", "dick",
        "faggot", "fuck", "motherfucker", "nigger", "piss", "shit", "slut", "whore"
    ]

    private static let leetMap: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"
    ]

    static func shouldCensorReviews() -> Bool {
        if UserDefaults.standard.object(forKey: censorReviewsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: censorReviewsKey)
    }

    static func shouldCensorComments() -> Bool {
        if UserDefaults.standard.object(forKey: censorCommentsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: censorCommentsKey)
    }

    static func containsForbiddenProfileText(_ value: String) -> Bool {
        let normalized = normalizedToken(value)
        guard !normalized.isEmpty else { return false }
        return blockedRoots.contains { normalized.contains($0) }
    }

    static func displayReviewText(_ value: String?) -> String {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        guard shouldCensorReviews() else { return raw }
        return censoredProfanity(in: raw)
    }

    static func displayCommentText(_ value: String?) -> String {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        guard shouldCensorComments() else { return raw }
        return censoredProfanity(in: raw)
    }

    private static func censoredProfanity(in text: String) -> String {
        let pattern = #"[A-Za-z0-9@'$]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text

        let matches = regex.matches(in: text, options: [], range: nsRange).reversed()
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let word = String(text[range])
            if isBlockedWord(word) {
                result.replaceSubrange(range, with: censoredReplacement(for: word))
            }
        }
        return result
    }

    private static func isBlockedWord(_ word: String) -> Bool {
        let normalized = normalizedToken(word)
        guard !normalized.isEmpty else { return false }
        return blockedRoots.contains { root in
            normalized == root || normalized.hasPrefix(root)
        }
    }

    private static func normalizedToken(_ value: String) -> String {
        let lowered = value.lowercased()
        let remapped = lowered.map { leetMap[$0] ?? $0 }
        return String(remapped.filter { $0.isLetter })
    }

    private static func censoredReplacement(for word: String) -> String {
        guard let first = word.first else { return word }
        return "\(first)***"
    }
}
