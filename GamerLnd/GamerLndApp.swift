// GamerLndApp.swift
// Default dark mode flag + Firebase bootstrap

import SwiftUI
import FirebaseCore
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

@main
struct GamerLndApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("themeMode") private var themeMode: String = "dark"

    init() {
        // Force dark by default unless user overrides in Settings.
        UserDefaults.standard.register(defaults: ["useDarkMode": true, "themeMode": "dark"])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(preferredScheme)
                .onAppear {
                    Analytics.screen("app_root")
                    Analytics.logEvent("app_open", parameters: ["source": "cold_start"])
                }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
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
        Analytics.logEvent("app_launch", parameters: ["via": "didFinishLaunching"])
        return true
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
