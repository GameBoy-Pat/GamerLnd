// ReviewPromptManager.swift
// Gentle in-app review prompting with simple heuristics.

import Foundation
import StoreKit
import FirebaseAuth

final class ReviewPromptManager {
    static let shared = ReviewPromptManager()

    private let minActionsBeforePrompt = 4       // tune: how active before prompting
    private let minDaysBetweenPrompts = 90       // Apple will also throttle internally

    private let actionsKeyBase = "review.actions.count"
    private let lastPromptKeyBase = "review.last.prompt.date"

    private init() {}

    private func scopedKey(_ base: String) -> String {
        let uid = Auth.auth().currentUser?.uid ?? "anon"
        return "\(base).\(uid)"
    }

    func registerUserAction() {
        let key = scopedKey(actionsKeyBase)
        let c = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(c, forKey: key)
    }

    func maybePrompt(in scene: UIWindowScene?) {
        // Enough activity?
        let actionsKey = scopedKey(actionsKeyBase)
        let lastPromptKey = scopedKey(lastPromptKeyBase)
        let actions = UserDefaults.standard.integer(forKey: actionsKey)
        guard actions >= minActionsBeforePrompt else { return }

        // Long enough since last prompt?
        if let last = UserDefaults.standard.object(forKey: lastPromptKey) as? Date {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            guard days >= minDaysBetweenPrompts else { return }
        }

        // Ask politely
        if let scene = scene {
            Task { @MainActor in
                if #available(iOS 18.0, *) {
                    AppStore.requestReview(in: scene)
                } else {
                    SKStoreReviewController.requestReview(in: scene)
                }
            }
            UserDefaults.standard.set(Date(), forKey: lastPromptKey)
            // Optional: reset counter or keep counting—your call
            UserDefaults.standard.set(0, forKey: actionsKey)
        }
    }
}
