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

    typealias LikeStateResult = (isLiked: Bool, count: Int)

    private func likeUserKey(from doc: QueryDocumentSnapshot) -> String {
        let data = doc.data()
        if let userId = (data["user_id"] as? String), !userId.isEmpty { return userId }
        if let userId = (data["userId"] as? String), !userId.isEmpty { return userId }
        if let userId = (data["uid"] as? String), !userId.isEmpty { return userId }
        if let prefix = doc.documentID.split(separator: "_").first, !prefix.isEmpty { return String(prefix) }
        return doc.documentID
    }

    private func likeUserKey(from data: [String: Any], documentId: String) -> String {
        if let userId = (data["user_id"] as? String), !userId.isEmpty { return userId }
        if let userId = (data["userId"] as? String), !userId.isEmpty { return userId }
        if let userId = (data["uid"] as? String), !userId.isEmpty { return userId }
        if let prefix = documentId.split(separator: "_").first, !prefix.isEmpty { return String(prefix) }
        return documentId
    }

    private func cleanupLikeDocuments(
        userId: String,
        logId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        db.collection("review_likes")
            .whereField("log_id", isEqualTo: logId)
            .getDocuments(source: .server) { snap, error in
                if let error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }

                let docs = (snap?.documents ?? []).filter { doc in
                    let data = doc.data()
                    let userField = (data["user_id"] as? String)
                        ?? (data["userId"] as? String)
                        ?? (data["uid"] as? String)
                    return userField == userId || doc.documentID.hasPrefix("\(userId)_")
                }
                guard !docs.isEmpty else {
                    DispatchQueue.main.async { completion(.success(())) }
                    return
                }

                let batch = self.db.batch()
                for doc in docs {
                    batch.deleteDocument(doc.reference)
                }

                batch.commit { commitError in
                    if let commitError {
                        DispatchQueue.main.async { completion(.failure(commitError)) }
                        return
                    }
                    DispatchQueue.main.async { completion(.success(())) }
                }
            }
    }

    // MARK: - Likes

    func fetchLikeState(
        logId: String,
        currentUserId: String,
        completion: @escaping (Result<LikeStateResult, Error>) -> Void
    ) {
        db.collection("review_likes")
            .whereField("log_id", isEqualTo: logId)
            .getDocuments(source: .server) { snap, error in
                if let error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }

                let docs = snap?.documents ?? []
                let uniqueUsers = Set(docs.map { self.likeUserKey(from: $0) })
                let isLiked = docs.contains { doc in
                    self.likeUserKey(from: doc) == currentUserId
                }
                DispatchQueue.main.async {
                    completion(.success((isLiked: isLiked, count: uniqueUsers.count)))
                }
            }
    }

    func setLikeState(
        log: GameLog,
        shouldLike: Bool,
        completion: @escaping (Result<LikeStateResult, Error>) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "InteractionService", code: 401, userInfo: [
                    NSLocalizedDescriptionKey: "You must be logged in to like a game log."
                ])))
            }
            return
        }
        let likeId = "\(uid)_\(log.id)"
        let ref = db.collection("review_likes").document(likeId)

        let finishByReadingServer: () -> Void = {
            self.fetchLikeState(logId: log.id, currentUserId: uid, completion: completion)
        }

        if !shouldLike {
            self.cleanupLikeDocuments(userId: uid, logId: log.id) { cleanupResult in
                switch cleanupResult {
                case .success:
                    if uid != log.userId {
                        NotificationService.shared.delete(
                            toUserId: log.userId,
                            relatedLogId: log.id,
                            type: .like
                        )
                    }
                    finishByReadingServer()
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }

        let payload: [String: Any] = [
            "id": likeId,
            "user_id": uid,
            "userId": uid,
            "uid": uid,
            "log_id": log.id,
            "created_at": Timestamp(date: Date())
        ]
        var enrichedPayload = payload
        if let displayName = Auth.auth().currentUser?.displayName, !displayName.isEmpty {
            enrichedPayload["author_name"] = displayName
        } else if let email = Auth.auth().currentUser?.email, !email.isEmpty {
            enrichedPayload["author_name"] = email
        }
        if let avatarURL = Auth.auth().currentUser?.photoURL?.absoluteString, !avatarURL.isEmpty {
            enrichedPayload["author_avatar_url"] = avatarURL
        }

        self.cleanupLikeDocuments(userId: uid, logId: log.id) { cleanupResult in
            switch cleanupResult {
            case .success:
                ref.setData(enrichedPayload, merge: false) { error in
                    if let error {
                        DispatchQueue.main.async { completion(.failure(error)) }
                        return
                    }
                    if uid != log.userId {
                        NotificationService.shared.create(
                            toUserId: log.userId,
                            relatedLogId: log.id,
                            type: .like
                        )
                    }
                    RewardService.shared.recordGamificationEvent(
                        RewardService.GamificationEvent(
                            userId: uid,
                            kind: .likeLog,
                            gameId: log.gameId,
                            releaseYear: nil,
                            reviewLength: nil,
                            ratingValue: nil,
                            searchQuery: nil,
                            sessionId: RewardService.activeSessionId,
                            occurredAt: Date()
                        )
                    )
                    finishByReadingServer()
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Set like state for a log using a deterministic doc id so there are only two real states:
    /// liked by the current user, or not liked by the current user.
    func setLike(log: GameLog,
                 shouldLike: Bool,
                 completion: @escaping (Result<Bool, Error>) -> Void) {
        setLikeState(log: log, shouldLike: shouldLike) { result in
            switch result {
            case .success(let state):
                completion(.success(state.isLiked))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Toggle like for callers that already know the current UI state.
    func toggleLike(log: GameLog,
                    currentlyLiked: Bool,
                    completion: @escaping (Result<Bool, Error>) -> Void) {
        setLike(log: log, shouldLike: !currentlyLiked, completion: completion)
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
                RewardService.shared.recordGamificationEvent(
                    RewardService.GamificationEvent(
                        userId: me,
                        kind: .followUser,
                        gameId: nil,
                        releaseYear: nil,
                        reviewLength: nil,
                        ratingValue: nil,
                        searchQuery: nil,
                        sessionId: RewardService.activeSessionId,
                        occurredAt: Date()
                    )
                )
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
