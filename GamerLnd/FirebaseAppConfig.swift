// FirebaseAppConfig.swift
// Initializes Firebase, Analytics, and Crashlytics once at app launch.

import SwiftUI
import FirebaseCore
import FirebaseCrashlytics
import os.log

final class FirebaseAppConfigurator {
    static let shared = FirebaseAppConfigurator()
    private var didConfigure = false

    private init() {}

    func configureIfNeeded() {
        guard !didConfigure else { return }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            os_log("Firebase configured", type: .info)
        }
        didConfigure = true
    }

    func setUser(id: String?, username: String?) {
        Crashlytics.crashlytics().setUserID(id ?? "anon")
        if let name = username, !name.isEmpty {
            Crashlytics.crashlytics().setCustomValue(name, forKey: "username")
        }
    }
}
