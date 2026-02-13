import UserNotifications
import SwiftUI

enum PushCategory: String {
    case comment = "COMMENT_CATEGORY"
    case like = "LIKE_CATEGORY"
    case follow = "FOLLOW_CATEGORY"
}

final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushManager()

    func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: PushCategory.comment.rawValue, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: PushCategory.like.rawValue, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: PushCategory.follow.rawValue, actions: [], intentIdentifiers: [], options: [])
        ]
        center.setNotificationCategories(categories)
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    // foreground handling
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
