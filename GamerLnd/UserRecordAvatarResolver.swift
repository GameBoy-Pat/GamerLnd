import Foundation

enum UserRecordAvatarResolver {
    static func url(from data: [String: Any]) -> String? {
        let candidates = [
            data["avatar_url"] as? String,
            data["profile_picture_url"] as? String
        ]

        for candidate in candidates {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }
}
