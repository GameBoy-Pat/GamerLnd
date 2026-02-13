// DataModels.swift
// Central app models used across views/services.
// THIS PASS:
// • Canonical UserLite lives here (remove any duplicate definitions in other files).
// • Keeps Game, GameLog, ReviewComment, UserProfile, UserProfileBrief as before.

import Foundation
import FirebaseFirestore

// MARK: - Game (IGDB)

struct Game: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    var cover: Cover?
    var firstReleaseDate: Int?
    var genres: [Genre]?
    var platforms: [Platform]?
    var rating: Double?
    var ratingCount: Int?
    var totalRatingCount: Int?
    var screenshots: [Screenshot]?

    enum CodingKeys: String, CodingKey {
        case id, name, cover, genres, platforms, rating, screenshots
        case firstReleaseDate = "first_release_date"
        case ratingCount = "rating_count"
        case totalRatingCount = "total_rating_count"
    }

    struct Cover: Codable, Hashable {
        var id: Int?
        var imageId: String
        enum CodingKeys: String, CodingKey { case id; case imageId = "image_id" }
    }

    struct Genre: Codable, Hashable { let id: Int; let name: String }
    struct Platform: Codable, Hashable { let id: Int; let name: String }
    struct Screenshot: Codable, Hashable {
        var id: Int?
        var imageId: String
        enum CodingKeys: String, CodingKey { case id; case imageId = "image_id" }
    }

    var computedReleaseYear: Int? {
        guard let unix = firstReleaseDate else { return nil }
        let d = Date(timeIntervalSince1970: TimeInterval(unix))
        return Calendar.current.dateComponents([.year], from: d).year
    }
}

// MARK: - Logging

enum GameStatus: String, Codable, CaseIterable {
    case inProgress = "in_progress"
    case completed = "completed"
    case notPlayed = "not_played"
}

struct GameLog: Identifiable, Hashable {
    let id: String
    let userId: String
    let gameId: Int
    let gameName: String?
    let status: GameStatus
    let playDate: Timestamp
    let rating: Double?
    let review: String?
    let isLiked: Bool
    let cover: Game.Cover?
}

// MARK: - Comments

struct ReviewComment: Identifiable, Hashable {
    let id: String
    let logId: String
    let userId: String
    let text: String
    let createdAt: Timestamp
}

// MARK: - Users

/// Firestore `/users/{uid}` profile document
struct UserProfile: Identifiable, Hashable {
    let id: String                    // == Firestore doc id (uid)
    var username: String              // display name (not unique)
    var handle: String                // unique, lowercase (no leading "@")
    var bio: String                   // up to 160 chars
    var avatarURL: String?            // optional
    var createdAt: Timestamp?
    var updatedAt: Timestamp?

    init(id: String,
         username: String,
         handle: String,
         bio: String = "",
         avatarURL: String? = nil,
         createdAt: Timestamp? = nil,
         updatedAt: Timestamp? = nil) {
        self.id = id
        self.username = username
        self.handle = handle
        self.bio = bio
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init?(docId: String, data: [String: Any]) {
        let uname = (data["username"] as? String) ?? ""
        let h = (data["handle"] as? String) ?? ""
        guard !uname.isEmpty, !h.isEmpty else { return nil }
        self.id = docId
        self.username = uname
        self.handle = h
        self.bio = (data["bio"] as? String) ?? ""
        self.avatarURL = (data["avatar_url"] as? String)
        self.createdAt = (data["created_at"] as? Timestamp)
        self.updatedAt = (data["updated_at"] as? Timestamp)
    }

    static func searchPrefixes(username: String, handle: String) -> [String] {
        let a = String(username.lowercased().prefix(1))
        let b = String(handle.lowercased().prefix(1))
        return Array(Set([a, b])).filter { !$0.isEmpty }
    }
}

/// Brief user used in lists/search
struct UserProfileBrief: Identifiable, Hashable {
    let id: String
    let username: String
    let handle: String?
    let displayName: String?
    let avatarUrl: String?
}

/// Canonical lightweight user for search screens
struct UserLite: Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
}
