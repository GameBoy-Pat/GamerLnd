// DraftService.swift
// Handles saving/loading/deleting draft logs per user.
// NOTE FOR BEGINNERS:
// • We store each draft under /drafts with fields user_id, game_id, status, rating?, review?, cover?, updated_at.
// • Security rules require user_id == current user and updated_at is a timestamp.
// • Queries: where user_id == me + order by updated_at desc (needs composite index).
// • The Draft model below implements Equatable/Hashable MANUALLY using only `id`
//   because Timestamp and [String: Any] are not Hashable.

import Foundation
import FirebaseAuth
import FirebaseFirestore

final class DraftService {
    static let shared = DraftService()
    private let db = Firestore.firestore()

    /// Save/overwrite a draft for the current user.
    /// - Parameters:
    ///   - gameId: IGDB game id
    ///   - text: optional review text
    ///   - rating: optional rating (0–10)
    ///   - statusRaw: GameStatus raw value
    ///   - cover: optional cover dictionary (id/image_id)
    func saveDraft(gameId: Int,
                   text: String?,
                   rating: Double?,
                   statusRaw: String,
                   cover: [String: Any]?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Use a deterministic document id per (uid, gameId) so we overwrite cleanly.
        let docId = "\(uid)_\(gameId)"
        var data: [String: Any] = [
            "id": docId,
            "user_id": uid,                         // required by security rules
            "game_id": gameId,
            "status": statusRaw,
            "updated_at": Timestamp(date: Date())   // used for ordering
        ]
        if let t = text { data["review"] = t }
        if let r = rating { data["rating"] = r }
        if let c = cover { data["cover"] = c }

        db.collection("drafts").document(docId).setData(data, merge: true)
    }

    /// Fetch current user's drafts ordered by most recently updated.
    func fetchMyDrafts(completion: @escaping ([Draft]) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { completion([]); return }
        db.collection("drafts")
            .whereField("user_id", isEqualTo: uid)
            .order(by: "updated_at", descending: true) // requires composite index
            .limit(to: 100)
            .getDocuments { snap, _ in
                let list: [Draft] = (snap?.documents ?? []).compactMap { d in
                    let data = d.data()
                    guard
                        let gid = data["game_id"] as? Int,
                        let status = data["status"] as? String,
                        let updated = data["updated_at"] as? Timestamp
                    else { return nil }
                    let rating = data["rating"] as? Double
                    let review = data["review"] as? String
                    var cover: [String: Any]? = nil
                    if let c = data["cover"] as? [String: Any] { cover = c }
                    return Draft(id: d.documentID, gameId: gid, statusRaw: status, rating: rating, review: review, updatedAt: updated, cover: cover)
                }
                completion(list)
            }
    }

    /// Delete a draft (only your own per security rules).
    func deleteDraft(id: String, completion: (() -> Void)? = nil) {
        db.collection("drafts").document(id).delete { _ in completion?() }
    }
}

// MARK: - Model

/// Lightweight local model for DraftsView.
/// We implement Equatable/Hashable manually using only `id` so the compiler
/// doesn't try to hash non-Hashable fields like Timestamp or [String: Any].
struct Draft: Identifiable, Equatable, Hashable {
    let id: String
    let gameId: Int
    let statusRaw: String
    let rating: Double?
    let review: String?
    let updatedAt: Timestamp
    let cover: [String: Any]?

    // Equatable: drafts are the same if their ids match.
    static func == (lhs: Draft, rhs: Draft) -> Bool {
        return lhs.id == rhs.id
    }

    // Hashable: hash only the stable identifier.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
