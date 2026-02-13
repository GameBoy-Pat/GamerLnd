// UserListItem.swift
// Model for a single game entry inside a user-created list.
// MVP schema aligned to Firestore /lists/{listId}/items/{itemId}:
// - id                : String (doc id)
// - list_id           : String (convenience; we inject this client-side when parsing)
// - game_id           : Int
// - game_name         : String
// - cover_image_id    : String? (IGDB image_id, e.g. "abc123def")
// - order             : Int? (rank/position within tier or ranked list)
// - tier              : String? (tier label; nil/"" means Pool/Unassigned)
// - added_at          : Timestamp
//
// NOTES:
// • We accept both "cover_image_id" and legacy "cover.image_id" shapes.
// • We parse added_at as Timestamp -> Date.
// • Properties used by UI (order/tier) are mutable so views can rearrange before persisting.

import Foundation
import FirebaseFirestore

struct UserListItem: Identifiable, Codable, Equatable {
    // Firestore document id
    let id: String

    // Parent list id (we inject when parsing; not necessarily stored on the doc)
    let listId: String

    // IGDB identifiers / display
    let gameId: Int
    let gameName: String

    // Optional quick display
    var coverImageId: String?
    let releaseYear: Int?

    // Ordering & tiering
    var order: Int?
    var tier: String?

    // Metadata
    let addedAt: Date?

    // Designated init
    init(
        id: String,
        listId: String,
        gameId: Int,
        gameName: String,
        coverImageId: String? = nil,
        releaseYear: Int? = nil,
        order: Int? = nil,
        tier: String? = nil,
        addedAt: Date? = nil
    ) {
        self.id = id
        self.listId = listId
        self.gameId = gameId
        self.gameName = gameName
        self.coverImageId = coverImageId
        self.releaseYear = releaseYear
        self.order = order
        self.tier = tier
        self.addedAt = addedAt
    }

    // Parse from Firestore dictionary (tolerant to legacy shapes)
    init?(id: String, data: [String: Any]) {
        // listId is injected by caller (ListDetailView does this). Fall back to explicit field if present.
        let parsedListId = (data["list_id"] as? String) ?? ""
        guard !parsedListId.isEmpty else { return nil }

        // game_id
        let gid: Int
        if let i = data["game_id"] as? Int {
            gid = i
        } else if let n = data["game_id"] as? NSNumber {
            gid = n.intValue
        } else {
            return nil
        }

        // game_name
        let gname = (data["game_name"] as? String) ?? "Game #\(gid)"

        // cover_image_id (prefer flat), fallback to embedded "cover.image_id"
        var cov: String? = nil
        if let flat = data["cover_image_id"] as? String, !flat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cov = flat
        } else if let cover = data["cover"] as? [String: Any],
                  let embedded = cover["image_id"] as? String,
                  !embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cov = embedded
        }

        // release_year (optional)
        var ryear: Int? = nil
        if let y = data["release_year"] as? Int {
            ryear = y
        } else if let yn = data["release_year"] as? NSNumber {
            ryear = yn.intValue
        }

        // order (optional)
        var ord: Int? = nil
        if let o = data["order"] as? Int {
            ord = o
        } else if let on = data["order"] as? NSNumber {
            ord = on.intValue
        }

        // tier (optional; empty string = unassigned)
        let tr = (data["tier"] as? String)

        // added_at (Timestamp -> Date)
        var added: Date? = nil
        if let ts = data["added_at"] as? Timestamp {
            added = ts.dateValue()
        } else if let seconds = (data["added_at_seconds"] as? NSNumber)?.doubleValue {
            added = Date(timeIntervalSince1970: seconds)
        }

        self.id = id
        self.listId = parsedListId
        self.gameId = gid
        self.gameName = gname
        self.coverImageId = cov
        self.releaseYear = ryear
        self.order = ord
        self.tier = tr
        self.addedAt = added
    }
}
