// AnalyticsService.swift
// Thin wrapper utilities that sit on top of our AppAnalytics (aliased as `Analytics`)
// and Crashlytics. No direct FirebaseAnalytics static calls here to avoid name clashes
// with our `typealias Analytics = AppAnalytics`.

import Foundation
import FirebaseCrashlytics

/// If you need direct Firebase Analytics features, prefer calling through `Analytics`
/// (our AppAnalytics wrapper) so we keep one surface area across the app.
final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}

    // MARK: - Common logging to Crashlytics

    func log(_ message: String, keys: [String: Any]? = nil) {
        Crashlytics.crashlytics().log(message)
        if let keys = keys {
            for (k, v) in keys {
                Crashlytics.crashlytics().setCustomValue(v, forKey: k)
            }
        }
    }

    // MARK: - User identity / properties

    /// Set the current user context for analytics + crash logs.
    /// We scope identity to Crashlytics (and optionally emit an analytics event),
    /// since our `AppAnalytics` wrapper does not expose a `setUser` API.
    func setUser(id: String?, username: String?) {
        // Crashlytics user identity
        if let id = id, !id.isEmpty {
            Crashlytics.crashlytics().setUserID(id)
        } else {
            // Clearing: Crashlytics requires a string; use empty
            Crashlytics.crashlytics().setUserID("")
        }

        if let username = username {
            Crashlytics.crashlytics().setCustomValue(username, forKey: "username")
        }

        // (Optional) Emit a lightweight analytics event so we can correlate sessions.
        // Safe no-op if your AppAnalytics ignores unrecognized parameter keys.
        Analytics.logEvent("user_context_set", parameters: [
            "has_id": id != nil,
            "has_username": username != nil
        ])
    }

    // MARK: - Screens

    func screen(_ name: String) {
        Analytics.screen(name)
    }

    // MARK: - Events (examples)

    func trackSearchSubmitted(query: String, resultsCount: Int) {
        Analytics.logEvent("search_submit", parameters: [
            "query": query,
            "results_count": resultsCount
        ])
    }

    func trackSearchTyping(query: String) {
        Analytics.logEvent("search_typing", parameters: [
            "query_len": query.count
        ])
    }

    func trackLogSaved(gameId: Int, rating: Double?, hasReview: Bool) {
        var params: [String: Any] = [
            "game_id": gameId,
            "has_review": hasReview
        ]
        if let rating = rating { params["rating"] = rating }
        Analytics.logEvent("log_saved", parameters: params)
    }

    func trackLike(logId: String, didLike: Bool) {
        Analytics.logEvent(didLike ? "like_added" : "like_removed", parameters: [
            "log_id": logId
        ])
    }

    func trackFollow(targetUserId: String, nowFollowing: Bool) {
        Analytics.logEvent(nowFollowing ? "follow_added" : "follow_removed", parameters: [
            "target_user_id": targetUserId
        ])
    }

    func trackListUpdated(listId: String, type: String, itemCount: Int) {
        Analytics.logEvent("list_updated", parameters: [
            "list_id": listId,
            "type": type,
            "count": itemCount
        ])
    }

    func trackError(_ error: Error, context: String) {
        Crashlytics.crashlytics().record(error: error)
        log("error: \(context)", keys: ["localizedDescription": error.localizedDescription])
        Analytics.logEvent("error", parameters: [
            "context": context,
            "message": error.localizedDescription
        ])
    }
}
