// InteractionService.swift
// Centralized helpers for likes, comments, and follows.
// BEGINNERS:
// • We keep one shared singleton for simple access across views.
// • Likes are stored in /review_likes with fields {id, user_id, log_id, created_at}.
// • Follows are stored in /follows with fields {id, follower_id, followed_id, created_at}.
// • Notifications are created via NotificationService for "like" only (rules allow like/comment).
//   We DO NOT send a "follow" notification because your Firestore rules only allow
//   types in ['like','comment'].

import Foundation
import FirebaseAuth
import FirebaseFirestore

final class InteractionService {
    static let shared = InteractionService()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Likes

    /// Toggle like for a log. Creates/deletes /review_likes doc.
    /// - Parameters:
    ///   - log: target GameLog
    ///   - currentlyLiked: pass true if the caller's UI thinks the user has liked it
    ///   - completion: called on main after the write succeeds (UI should update)
    func toggleLike(log: GameLog,
                    currentlyLiked: Bool,
                    completion: @escaping () -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let likeId = "\(uid)_\(log.id)"
        let ref = db.collection("review_likes").document(likeId)

        if currentlyLiked {
            // UNLIKE: just delete the like document
            ref.delete { _ in
                DispatchQueue.main.async { completion() }
            }
        } else {
            // LIKE: write the document and create a notification to the log owner (if not self)
            let payload: [String: Any] = [
                "id": likeId,
                "user_id": uid,
                "log_id": log.id,
                "created_at": Timestamp(date: Date())
            ]
            ref.setData(payload, merge: false) { _ in
                // Send notification if liking someone else's log
                if uid != log.userId {
                    NotificationService.shared.create(
                        toUserId: log.userId,
                        relatedLogId: log.id,
                        type: .like
                    )
                }
                DispatchQueue.main.async { completion() }
            }
        }
    }

    // MARK: - Follows

    /// Is the current user following `targetUserId`?
    func isFollowing(targetUserId: String, completion: @escaping (Bool) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else { completion(false); return }
        let docId = "\(me)_\(targetUserId)"
        db.collection("follows").document(docId).getDocument { snap, _ in
            completion(snap?.exists == true)
        }
    }

    /// Toggle following of a user. Writes/deletes a deterministic doc id to avoid duplicates.
    /// - Parameters:
    ///   - u: target user id to follow/unfollow
    ///   - isFollowing: current UI state
    ///   - completion: returns the new state after the write (true if now following)
    func toggleFollow(u targetUserId: String,
                      isFollowing: Bool,
                      completion: @escaping (Bool) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else { completion(isFollowing); return }
        // Don't allow follow self (no-op)
        guard me != targetUserId else { completion(isFollowing); return }

        let docId = "\(me)_\(targetUserId)"
        let ref = db.collection("follows").document(docId)

        if isFollowing {
            // UNFOLLOW
            ref.delete { _ in
                DispatchQueue.main.async { completion(false) }
            }
        } else {
            // FOLLOW
            let payload: [String: Any] = [
                "id": docId,
                "follower_id": me,
                "followed_id": targetUserId,
                "created_at": Timestamp(date: Date())
            ]
            ref.setData(payload, merge: false) { _ in
                // NOTE: We do NOT send a "follow" notification due to security rules (allowed: like/comment).
                DispatchQueue.main.async { completion(true) }
            }
        }
    }

    // MARK: - Utility (optional)

    /// Fetch a set of userIds the current user follows. Handy for quick UI checks.
    func followingIdSet(completion: @escaping (Set<String>) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else { completion([]); return }
        db.collection("follows")
            .whereField("follower_id", isEqualTo: me)
            .getDocuments { snap, _ in
                let ids = (snap?.documents ?? []).compactMap { $0.data()["followed_id"] as? String }
                completion(Set(ids))
            }
    }
}
