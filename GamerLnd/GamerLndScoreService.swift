// GamerLndScoreService.swift
// Computes and caches "GamerLnd Rating" (average rating across all logs for a game).
// THIS PASS:
// • Remove `whereField("rating", isGreaterThan: 0)` to avoid composite index requirements.
// • Filter ratings client-side (safer for MVP and fewer Firestore index errors).
// • Robust number parsing (Double or NSNumber) and error fallback.

import Foundation
import FirebaseFirestore

final class GamerLndScoreService {
    static let shared = GamerLndScoreService()
    private init() {}

    private let db = Firestore.firestore()
    private var cache: [Int: (avg: Double?, count: Int)] = [:]

    /// Fetch average rating for a game id. Uses simple in-memory cache.
    /// BEGINNERS:
    /// - We query logs for this game id, then compute the average of any rating > 0.
    /// - If nothing found, we return (nil, 0) so the UI shows the CTA: "Be the first to rate this game!"
    func fetchAverage(gameId: Int, completion: @escaping (Double?, Int) -> Void) {
        if let cached = cache[gameId] {
            completion(cached.avg, cached.count)
            return
        }

        db.collection("game_logs")
            .whereField("game_id", isEqualTo: gameId)
            .limit(to: 500) // MVP cap; can be paginated/refined later
            .getDocuments { snap, err in
                if let err = err {
                    // On any error, avoid crashing and return "no ratings yet" so the UI shows a CTA.
                    print("GamerLndScoreService error for game \(gameId): \(err.localizedDescription)")
                    self.cache[gameId] = (avg: nil, count: 0)
                    completion(nil, 0)
                    return
                }

                let docs = snap?.documents ?? []
                // Extract rating as Double from either Double or NSNumber
                let ratings: [Double] = docs.compactMap { d in
                    if let dd = d.data()["rating"] as? Double { return dd }
                    if let num = d.data()["rating"] as? NSNumber { return num.doubleValue }
                    return nil
                }
                .filter { $0 > 0 }

                if ratings.isEmpty {
                    self.cache[gameId] = (avg: nil, count: 0)
                    completion(nil, 0)
                } else {
                    let sum = ratings.reduce(0, +)
                    let avg = sum / Double(ratings.count)
                    self.cache[gameId] = (avg: avg, count: ratings.count)
                    completion(avg, ratings.count)
                }
            }
    }

    func invalidate(gameId: Int) {
        cache[gameId] = nil
    }
}

extension Notification.Name {
    static let gamerLndRatingUpdated = Notification.Name("gamerlnd_rating_updated")
}
