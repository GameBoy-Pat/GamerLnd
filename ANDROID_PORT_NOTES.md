# Android Port Notes

Recommended approach: native Android with Kotlin + Jetpack Compose.

Why this is the best fit
- The current app is already strongly platform-native on iOS.
- Firebase has first-class Android support for the services GamerLnd already uses.
- Kotlin + Jetpack Compose is the cleanest path for matching the current product while keeping long-term maintainability strong.

Recommended stack
- Kotlin
- Jetpack Compose
- Firebase Auth
- Firestore
- Firebase Storage
- Firebase Messaging
- Firebase Crashlytics

Architecture recommendation
- Keep the IGDB integration behind a small service/repository abstraction.
- Mirror the current iOS feature areas with Android-specific view models and repositories rather than trying to translate SwiftUI structure directly.
- Prefer a clean Compose navigation graph and shared domain models where practical.

MVP screen set for Android
- Auth
- Feed
- Game detail
- Log / review
- Profile

Launch recommendation
- Do not chase full parity first.
- Get core account, feed, logging, review, save, and profile flows stable first.
- Bring over advanced list/tier/overlay polish after the MVP is solid.
