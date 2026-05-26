// NotificationService.swift
// Helper to write notifications that comply with Firestore rules.
// THIS PASS:
// • Ensure we write creator_id and created_at fields (required by rules).
// • Keep types limited to "like" / "comment" per rules.

import Foundation
import FirebaseAuth
import FirebaseFirestore

final class NotificationService {
    static let shared = NotificationService()
    private let db = Firestore.firestore()

    enum NotifType: String {
        case like, comment
    }

    /// Create a notification from the current user (actor) to the recipient.
    /// - Parameters:
    ///   - toUserId: recipient user id
    ///   - relatedLogId: game log id this notif references
    ///   - type: like/comment
    func create(toUserId: String, relatedLogId: String, type: NotifType) {
        guard let me = Auth.auth().currentUser?.uid else { return }
        // If you try to notify yourself, silently ignore.
        guard me != toUserId else { return }

        let id = deterministicId(creatorId: me, toUserId: toUserId, relatedLogId: relatedLogId, type: type)
        let payload: [String: Any] = [
            "id": id,
            "user_id": toUserId,           // recipient
            "creator_id": me,              // actor (required by rules)
            "type": type.rawValue,         // "like" | "comment"
            "log_id": relatedLogId,
            "created_at": Timestamp(date: Date())
        ]
        db.collection("notifications").document(id).setData(payload, merge: false)
    }

    func delete(toUserId: String, relatedLogId: String, type: NotifType) {
        guard let me = Auth.auth().currentUser?.uid else { return }
        let id = deterministicId(creatorId: me, toUserId: toUserId, relatedLogId: relatedLogId, type: type)
        db.collection("notifications").document(id).delete()
    }

    private func deterministicId(creatorId: String, toUserId: String, relatedLogId: String, type: NotifType) -> String {
        "\(creatorId)_\(toUserId)_\(relatedLogId)_\(type.rawValue)"
    }
}
