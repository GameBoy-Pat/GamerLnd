// Analytics.swift
// Thin facade over Firebase Analytics to avoid name/overload clashes.

import Foundation
import FirebaseAnalytics

/// Use `Analytics.logEvent(_:parameters:)` in the app code (kept for backwards compatibility).
/// Under the hood we forward to FirebaseAnalytics.Analytics.
typealias Analytics = AppAnalytics

enum AppAnalytics {
    /// Generic logger — mirrors Firebase's signature.
    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        #if DEBUG
        return
        #else
        FirebaseAnalytics.Analytics.logEvent(name, parameters: parameters)
        #endif
    }

    /// Standardized screen view event.
    static func screen(_ name: String) {
        #if DEBUG
        return
        #else
        FirebaseAnalytics.Analytics.logEvent(
            AnalyticsEventScreenView,
            parameters: [AnalyticsParameterScreenName: name]
        )
        #endif
    }

    // MARK: - Convenience helpers (optional but handy)

    static func search(query: String, scope: String, resultCount: Int) {
        logEvent("search", parameters: [
            "query": query,
            "scope": scope,                // "games" | "users" | "both"
            "result_count": resultCount
        ])
    }

    static func viewProfile(userId: String) {
        logEvent("view_profile", parameters: ["user_id": userId])
    }

    static func follow(targetUserId: String, becameFollowing: Bool) {
        logEvent("follow_toggle", parameters: [
            "target_user_id": targetUserId,
            "following": becameFollowing
        ])
    }

    static func viewGame(gameId: Int, source: String? = nil) {
        var p: [String: Any] = ["game_id": gameId]
        if let s = source { p["source"] = s } // e.g. "feed", "explore", "profile_recent"
        logEvent("view_game", parameters: p)
    }

    static func viewLog(logId: String, gameId: Int) {
        logEvent("view_log", parameters: [
            "log_id": logId,
            "game_id": gameId
        ])
    }

    static func addComment(logId: String) {
        logEvent("add_comment", parameters: ["log_id": logId])
    }

    static func openList(listId: String, type: String, itemCount: Int) {
        logEvent("open_list", parameters: [
            "list_id": listId,
            "type": type,                // regular | ranked | tiered
            "item_count": itemCount
        ])
    }
}
