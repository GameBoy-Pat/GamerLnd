// ReviewPrompter.swift
// Very lightweight heuristic to request in-app review after positive actions.

import Foundation
import FirebaseAuth

final class ReviewPrompter {
    enum Event { case logSaved, comment, like, follow }

    static let shared = ReviewPrompter()
    private init() {}

    private let keyBase = "review.counter"
    private let lastKeyBase = "review.lastTs"

    private func scopedKey(_ base: String) -> String {
        let uid = Auth.auth().currentUser?.uid ?? "anon"
        return "\(base).\(uid)"
    }

    func bump(_ event: Event, completion: @escaping (Bool) -> Void) {
        let key = scopedKey(keyBase)
        let lastKey = scopedKey(lastKeyBase)
        var count = UserDefaults.standard.integer(forKey: key)
        count += 1
        UserDefaults.standard.set(count, forKey: key)

        let lastTs = UserDefaults.standard.double(forKey: lastKey)
        let now = Date().timeIntervalSince1970

        // Prompt conditions: at least 5 positive actions and >7 days since last prompt
        if count >= 5 && (now - lastTs) > (7 * 24 * 3600) {
            UserDefaults.standard.set(0, forKey: key)
            UserDefaults.standard.set(now, forKey: lastKey)
            completion(true)
        } else {
            completion(false)
        }
    }
}
