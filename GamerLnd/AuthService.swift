// AuthService.swift
// Authentication helpers (Firebase Auth + Firestore user bootstrap + account deletion).
// BEGINNERS:
// • Keep auth logic in one place so views stay simple.
// • On signup, we create /users/{uid} so the rest of the app can read names, etc.
// • deleteAccount() tries to delete the user's documents (users, user_stats, follows, likes, logs, gamification docs)
//   and then deletes the Auth user. Some deletes are "best-effort" due to Firestore limits.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import os.log

final class AuthService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = AuthService()
    private override init() { super.init() }

    private let db = Firestore.firestore()
    private var currentNonce: String?
    private var appleCompletion: ((Result<User, Error>) -> Void)?
    private weak var presentationAnchor: UIWindow?

    // MARK: - Public API

    /// Sign in with email/password.
    func signIn(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error { completion(.failure(error)); return }
            guard let user = result?.user else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user session."])))
                return
            }
            self.ensureUserProfile(user: user, explicitUsername: nil) { _ in
                os_log("AuthService: signed in %@", log: .default, type: .info, user.uid)
                completion(.success(user))
            }
        }
    }

    /// Create user with email/password and bootstrap the `/users/{uid}` doc.
    func signUp(email: String, password: String, username: String?, completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error { completion(.failure(error)); return }
            guard let user = result?.user else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user after signup."])))
                return
            }
            // After creating the auth user, create their public profile document.
            self.ensureUserProfile(user: user, explicitUsername: username) { profResult in
                switch profResult {
                case .success:
                    os_log("AuthService: profile created for %@", log: .default, type: .info, user.uid)
                    completion(.success(user))
                case .failure(let err):
                    os_log("AuthService: profile create failed %@", log: .default, type: .error, err.localizedDescription)
                    completion(.failure(err))
                }
            }
        }
    }

    /// Sign out the current user.
    func signOut() -> Result<Void, Error> {
        do {
            try Auth.auth().signOut()
            os_log("AuthService: signed out", log: .default, type: .info)
            return .success(())
        } catch {
            os_log("AuthService: signout error %@", log: .default, type: .error, error.localizedDescription)
            return .failure(error)
        }
    }

    // MARK: - Sign in with Apple

    func signInWithApple(presentationAnchor: UIWindow, completion: @escaping (Result<User, Error>) -> Void) {
        let nonce = randomNonceString()
        currentNonce = nonce
        appleCompletion = completion
        self.presentationAnchor = presentationAnchor

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationAnchor ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            appleCompletion?(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credential."])))
            appleCompletion = nil
            return
        }

        guard let nonce = currentNonce else {
            appleCompletion?(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid login state."])))
            appleCompletion = nil
            return
        }

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            appleCompletion?(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch Apple identity token."])))
            appleCompletion = nil
            return
        }

        let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)
        Auth.auth().signIn(with: credential) { result, error in
            if let error = error {
                self.appleCompletion?(.failure(error))
                self.appleCompletion = nil
                return
            }
            guard let user = result?.user else {
                self.appleCompletion?(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user session."])))
                self.appleCompletion = nil
                return
            }
            self.ensureUserProfile(user: user, explicitUsername: nil) { _ in
                self.appleCompletion?(.success(user))
                self.appleCompletion = nil
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        var message = error.localizedDescription
        if let asErr = error as? ASAuthorizationError {
            message = "Apple Sign-In failed (\(asErr.code.rawValue)). \(asErr.localizedDescription)"
        }
        let wrapped = NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: nsError.userInfo.merging([NSLocalizedDescriptionKey: message]) { _, new in new }
        )
        appleCompletion?(.failure(wrapped))
        appleCompletion = nil
    }

    // MARK: - Account Deletion (best-effort cleanup then Auth delete)
    // IMPORTANT: For production, consider moving heavy deletes to Cloud Functions.

    func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No signed-in user."])))
            return
        }
        let uid = user.uid

        // Step 1: best-effort data cleanup
        bestEffortCleanup(uid: uid) { cleanupError in
            if let cleanupError = cleanupError {
                os_log("AuthService: cleanup encountered error: %@", log: .default, type: .error, cleanupError.localizedDescription)
                // We proceed to try deleting the auth user anyway.
            }
            // Step 2: delete Auth user
            user.delete { authErr in
                if let authErr = authErr {
                    completion(.failure(authErr))
                } else {
                    os_log("AuthService: account deleted for %@", log: .default, type: .info, uid)
                    completion(.success(()))
                }
            }
        }
    }

    /// Deletes user-owned docs from key collections. Some are chunked to avoid limits.
    private func bestEffortCleanup(uid: String, completion: @escaping (Error?) -> Void) {
        let group = DispatchGroup()
        var firstError: Error?

        // Helper to run a query and delete up to N docs.
        func deleteQuery(_ query: Query, limit: Int = 300) {
            group.enter()
            query.limit(to: limit).getDocuments { snap, err in
                if let err = err { if firstError == nil { firstError = err }; group.leave(); return }
                let docs = snap?.documents ?? []
                let batch = self.db.batch()
                docs.forEach { batch.deleteDocument($0.reference) }
                batch.commit { bErr in
                    if let bErr = bErr, firstError == nil { firstError = bErr }
                    group.leave()
                }
            }
        }

        // /users/{uid}
        group.enter()
        db.collection("users").document(uid).delete { err in
            if let err = err, firstError == nil { firstError = err }
            group.leave()
        }

        // /user_stats/{uid}
        group.enter()
        db.collection("user_stats").document(uid).delete { err in
            if let err = err, firstError == nil { firstError = err }
            group.leave()
        }

        // Follows: as follower and as followed
        deleteQuery(db.collection("follows").whereField("follower_id", isEqualTo: uid))
        deleteQuery(db.collection("follows").whereField("followed_id", isEqualTo: uid))

        // Likes by this user
        deleteQuery(db.collection("review_likes").whereField("user_id", isEqualTo: uid))

        // Comments by this user
        deleteQuery(db.collection("review_comments").whereField("user_id", isEqualTo: uid))

        // Game logs created by this user
        deleteQuery(db.collection("game_logs").whereField("user_id", isEqualTo: uid))

        // Notifications for this user (recipient) and notifications they created (if any)
        deleteQuery(db.collection("notifications").whereField("user_id", isEqualTo: uid))
        deleteQuery(db.collection("notifications").whereField("creator_id", isEqualTo: uid))

        // Gamification / progression state
        deleteQuery(db.collection("daily_objectives").whereField("user_id", isEqualTo: uid))
        deleteQuery(db.collection("weekly_objectives").whereField("user_id", isEqualTo: uid))
        deleteQuery(db.collection("user_achievements").whereField("user_id", isEqualTo: uid))
        deleteQuery(db.collection("user_secret_unlocks").whereField("user_id", isEqualTo: uid))

        // Metrics / references
        group.enter()
        db.collection("user_metrics").document(uid).delete { err in
            if let err = err, firstError == nil { firstError = err }
            group.leave()
        }

        // Lists owned by this user
        deleteQuery(db.collection("lists").whereField("owner_id", isEqualTo: uid))

        group.notify(queue: .main) {
            completion(firstError) // nil on best-effort success
        }
    }

    // MARK: - Bootstrap user profile

    /// Create /users/{uid} if missing. Idempotent.
    private func ensureUserProfile(user: User, explicitUsername: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        let uid = user.uid
        let docRef = db.collection("users").document(uid)
        docRef.getDocument { snap, _ in
            if let snap = snap, snap.exists {
                completion(.success(())) // already exists
                return
            }
            // Derive a simple default username from email before @ if none provided.
            let derivedUsername: String = {
                if let given = explicitUsername, !given.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return given
                }
                if let email = user.email, let handle = email.split(separator: "@").first {
                    return String(handle)
                }
                return "user_" + uid.prefix(6)
            }()
            let safeUsername: String = ContentModeration.containsForbiddenProfileText(derivedUsername)
                ? "user_" + uid.prefix(6)
                : derivedUsername

            let payload: [String: Any] = [
                "id": uid,
                "email": user.email ?? "",
                "display_name": safeUsername,
                "display_name_lower": safeUsername.lowercased(),
                "username": safeUsername.lowercased(),
                "username_lower": safeUsername.lowercased(),
                "handle": safeUsername.lowercased(),
                "search_prefix": UserProfile.searchPrefixes(username: safeUsername, handle: safeUsername.lowercased()),
                "bio": "",
                "profile_picture_url": "",
                "created_at": Timestamp(date: Date())
            ]
            docRef.setData(payload) { err in
                if let err = err { completion(.failure(err)) }
                else { completion(.success(())) }
            }
        }
    }
}

// MARK: - Nonce helpers

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        var randoms = [UInt8](repeating: 0, count: 16)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed.")
        }

        randoms.forEach { random in
            if remainingLength == 0 { return }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }

    return result
}

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.compactMap { String(format: "%02x", $0) }.joined()
}
