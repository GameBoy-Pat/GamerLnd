// ReportService.swift
// Simple UGC reporting to Firestore.

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum ReportTargetType: String, Codable {
    case log
    case comment
    case user
}

enum ReportReason: String, CaseIterable, Identifiable {
    case spam = "Spam"
    case harassment = "Harassment"
    case hate = "Hate or abuse"
    case nudity = "Nudity"
    case violence = "Violence"
    case other = "Other"
    var id: String { rawValue }
}

final class ReportService {
    static let shared = ReportService()
    private init() {}

    private let db = Firestore.firestore()

    func submit(
        targetType: ReportTargetType,
        targetId: String,
        targetUserId: String?,
        reason: ReportReason,
        notes: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let reporterId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in."])))
            return
        }

        let reportId = UUID().uuidString
        var payload: [String: Any] = [
            "id": reportId,
            "type": targetType.rawValue,
            "target_id": targetId,
            "reporter_id": reporterId,
            "reason": reason.rawValue,
            "created_at": Timestamp(date: Date())
        ]
        if let targetUserId = targetUserId { payload["target_user_id"] = targetUserId }
        if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        db.collection("reports").document(reportId).setData(payload) { err in
            if let err = err { completion(.failure(err)) }
            else { completion(.success(())) }
        }
    }
}
