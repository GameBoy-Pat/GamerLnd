// RatingsService.swift
// Computes the "GamerLnd Rating" by averaging all user ratings in Firestore for a given game.
// IMPORTANT FOR BEGINNERS:
// - We now *do not* filter by "rating" in the Firestore query. Some docs might have missing
//   or 0 ratings and mixed number types (Int/Double). Filtering in Firestore could exclude
//   legitimate docs or fail if the field is absent. Instead, we fetch all logs for the game
//   and filter/average safely on the client.
// - This avoids N/A issues when ratings exist but don’t match the previous query filter.

import Foundation
import FirebaseFirestore
import os.log

final class RatingsService {
    static let shared = RatingsService()
    private let db = Firestore.firestore()
    private init() {}

    /// Starts a real-time listener that calculates the average user rating for a game.
    /// - Parameters:
    ///   - gameId: The IGDB game id.
    ///   - onChange: Called with (average, count) whenever the underlying data changes.
    /// - Returns: A Firestore ListenerRegistration. Remove it on view disappear.
    @discardableResult
    func listenAverageRating(
        gameId: Int,
        onChange: @escaping (_ average: Double?, _ count: Int) -> Void
    ) -> ListenerRegistration {
        // NOTE: Only filter by game_id. We'll filter/validate ratings on the client.
        let query = db.collection("game_logs")
            .whereField("game_id", isEqualTo: gameId)

        os_log("RatingsService: attaching listener for game_id=%d", log: .default, type: .debug, gameId)

        let listener = query.addSnapshotListener { snapshot, error in
            if let error = error {
                os_log("RatingsService error: %@", log: .default, type: .error, error.localizedDescription)
                onChange(nil, 0)
                return
            }

            guard let docs = snapshot?.documents else {
                onChange(nil, 0)
                return
            }

            var sum: Double = 0
            var count: Int = 0

            for doc in docs {
                let data = doc.data()

                // Ratings can be stored as Double or Int. They can also be missing (nil).
                if let val = data["rating"] as? Double {
                    if val > 0, val <= 10 { // basic sanity range for hearts 1..10 (0 = no rating)
                        sum += val
                        count += 1
                    }
                } else if let valInt = data["rating"] as? Int {
                    let v = Double(valInt)
                    if v > 0, v <= 10 {
                        sum += v
                        count += 1
                    }
                }
            }

            let average = count > 0 ? (sum / Double(count)) : nil
            onChange(average, count)
        }

        return listener
    }
}
