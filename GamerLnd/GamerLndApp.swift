// GamerLndApp.swift
// Default dark mode flag + Firebase bootstrap

import SwiftUI
import FirebaseCore
import FirebaseCrashlytics
import FirebaseAnalytics
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

@main
struct GamerLndApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    init() {
        // Force dark for now.
        UserDefaults.standard.register(defaults: ["useDarkMode": true, "themeMode": "dark"])
        URLCache.shared.memoryCapacity = 24 * 1024 * 1024
        URLCache.shared.diskCapacity = 120 * 1024 * 1024
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .ignoresSafeArea(.keyboard, edges: .all)
                .onAppear {
                    Analytics.screen("app_root")
                    Analytics.logEvent("app_open", parameters: ["source": "cold_start"])
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    private var memoryWarningObserver: NSObjectProtocol?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        #if canImport(FirebaseAppCheck)
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(GamerLndAppCheckProviderFactory())
        #endif
        #endif
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #if DEBUG
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(false)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #endif
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            ImageCache.shared.clear()
            AvatarCacheManager.clear()
            URLCache.shared.removeAllCachedResponses()
        }
        Analytics.logEvent("app_launch", parameters: ["via": "didFinishLaunching"])
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

#if canImport(FirebaseAppCheck)
final class GamerLndAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider {
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        } else {
            return DeviceCheckProvider(app: app)
        }
    }
}
#endif
