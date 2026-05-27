// LoginView.swift
// Login / Sign Up (full-screen, with hero art)
// THIS PASS:
// • Icon has rounded corners and is raised slightly.
// • "GamerLnd" title removed.
// • Login card moved lower (near-centered).
// • Preserves unique handle check + Firestore writes.
// • Input text is light for dark theme.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices

struct LoginView: View {
    @Binding var user: User?

    // Auth fields
    @State private var email = ""
    @State private var password = ""
    @State private var isSignup = false

    // Sign-up extras
    @State private var displayName = ""
    @State private var handle = ""

    // UI state
    @State private var errorMessage = ""
    @State private var infoMessage = ""
    @State private var displayNameError = ""
    @State private var handleError = ""
    @State private var showProfileSetup = false
    @State private var profileSetupUserId: String? = nil
    @State private var profileSetupAttempts: Int = 0
    @State private var showVerificationScreen = false
    @State private var verificationEmail: String = ""
    @State private var isBusy = false
    @State private var busyMessage = ""
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var focusedField: Field?
    @AppStorage("pendingEmailVerification") private var pendingEmailVerification: Bool = false

    private let db = Firestore.firestore()
    private let heroExpandedHeight: CGFloat = 280
    private let heroCollapsedHeight: CGFloat = 176

    enum Field {
        case email, password, displayName, handle
    }

    var body: some View {
        ZStack {
            // Background color
            ColorTheme.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                // Full-screen content with scrolling (keyboard friendly)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                    // HERO IMAGE
                    ZStack {
                        GeometryReader { geo in
                            let heroHeight = keyboardHeight > 0 ? heroCollapsedHeight : heroExpandedHeight
                            Image("land_image")
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: heroHeight)
                                .clipped()
                                .overlay(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            .black.opacity(0.0),
                                            .black.opacity(0.18),
                                            .black.opacity(0.42),
                                            .black.opacity(0.65)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        .frame(height: 280)

                        // App icon over hero (rounded corners, slightly higher)
                        Image("icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(radius: 10, y: 4)
                            .offset(y: keyboardHeight > 0 ? -18 : -44) // keep visible when keyboard is up
                            .accessibilityLabel(Text("GamerLnd"))
                    }

                    // Add extra spacer to push the card lower (more centered overall)
                    Spacer(minLength: 20)

                    // GLASS CARD WITH FIELDS
                    VStack(spacing: 16) {
                        // Sign in with Apple (required if other sign-in exists)
                        Button {
                            signInWithApple()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "applelogo")
                                Text("Sign in with Apple")
                                    .font(.footnote.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(isBusy)

                        Text("or")
                            .font(.caption2)
                            .foregroundColor(ColorTheme.subtext)

                        Group {
                            // Email
                            TextField("Email", text: $email)
                                .id(Field.email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .textContentType(.username)
                                .submitLabel(.next)
                                .foregroundColor(ColorTheme.text)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(ColorTheme.surface.opacity(0.65))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(ColorTheme.separator, lineWidth: 1)
                                        )
                                )
                                .focused($focusedField, equals: .email)
                                .disabled(isBusy)

                            // Password
                            SecureField("Password", text: $password)
                                .id(Field.password)
                                .textContentType(.password)
                                .submitLabel(isSignup ? .next : .go)
                                .foregroundColor(ColorTheme.text)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(ColorTheme.surface.opacity(0.65))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(ColorTheme.separator, lineWidth: 1)
                                        )
                                )
                                .focused($focusedField, equals: .password)
                                .disabled(isBusy)

                            if isSignup {
                                // Display Name
                                TextField("Display Name", text: $displayName)
                                    .id(Field.displayName)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled(false)
                                    .submitLabel(.next)
                                    .foregroundColor(ColorTheme.text)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(ColorTheme.surface.opacity(0.65))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(ColorTheme.separator, lineWidth: 1)
                                            )
                                    )
                                    .focused($focusedField, equals: .displayName)
                                    .onChange(of: displayName) { _, newValue in
                                        if newValue.count > ProfileIdentityValidator.maxDisplayNameLength {
                                            displayName = String(newValue.prefix(ProfileIdentityValidator.maxDisplayNameLength))
                                        }
                                        displayNameError = ProfileIdentityValidator.displayNameError(displayName) ?? ""
                                    }
                                    .disabled(isBusy)

                                // Handle
                                TextField("Handle (unique)", text: $handle)
                                    .id(Field.handle)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .textContentType(.nickname)
                                    .submitLabel(.done)
                                    .foregroundColor(ColorTheme.text)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(ColorTheme.surface.opacity(0.65))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(ColorTheme.separator, lineWidth: 1)
                                            )
                                    )
                                    .focused($focusedField, equals: .handle)
                                    .onChange(of: handle) { _, newValue in
                                        let sanitized = ProfileIdentityValidator.sanitizedHandleInput(newValue)
                                        if sanitized != newValue {
                                            handle = sanitized
                                        }
                                        if handle.count > ProfileIdentityValidator.maxHandleLength {
                                            handle = String(handle.prefix(ProfileIdentityValidator.maxHandleLength))
                                        }
                                        handleError = ProfileIdentityValidator.handleError(handle) ?? ""
                                    }
                                    .disabled(isBusy)
                            }
                        }

                        if isSignup && !displayNameError.isEmpty {
                            Text(displayNameError)
                                .foregroundColor(ColorTheme.highlight)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if isSignup && !handleError.isEmpty {
                            Text(handleError)
                                .foregroundColor(ColorTheme.highlight)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Primary action
                        Button {
                            hideKeyboard()
                            if isSignup { signUp() } else { logIn() }
                        } label: {
                            HStack(spacing: 10) {
                                if isBusy {
                                    ProgressView().tint(.black)
                                }
                                Text(isSignup ? "Create Account" : "Log In")
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ColorTheme.accent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(isBusy)

                        // Switch mode
                        if !isSignup {
                            HStack(spacing: 14) {
                                Button("Forgot password?") {
                                    sendPasswordReset()
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(ColorTheme.subtext)
                                .disabled(isBusy)

                                Button("Resend verification") {
                                    resendVerificationEmail()
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(ColorTheme.accent)
                                .disabled(isBusy)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(isSignup ? "Have an account? Log In" : "No account? Sign Up") {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0.1)) {
                                isSignup.toggle()
                                errorMessage = ""
                                infoMessage = ""
                            }
                        }
                        .foregroundColor(ColorTheme.accent)
                        .disabled(isBusy)

                        // Errors
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(ColorTheme.highlight)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !infoMessage.isEmpty {
                            Text(infoMessage)
                                .foregroundColor(ColorTheme.subtext)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .background(
                        // Frosted “glass” effect card
                        RoundedRectangle(cornerRadius: 16)
                            .fill(ColorTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(ColorTheme.separator, lineWidth: 1)
                            )
                    )
                    // Move the card down (previously was pulled up). This centers the form better.
                    .padding(.top, 24)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)

                    Spacer(minLength: 24)

                    // Footer
                    Text("By continuing you agree to our Terms & Privacy.")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, max(36, keyboardHeight * 0.68))
                }
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(field, anchor: .center)
                        }
                    }
                }
            }

            if isBusy {
                ZStack {
                    Color.black.opacity(0.38).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(ColorTheme.accent)
                        Text(busyMessage.isEmpty ? "Working..." : busyMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(ColorTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ColorTheme.separator, lineWidth: 1))
                    )
                    .padding(.horizontal, 24)
                }
            }
        }
        .onTapGesture { hideKeyboard() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            let screenHeight = UIScreen.main.bounds.height
            keyboardHeight = max(0, screenHeight - frame.origin.y)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                KeyboardDismissAccessoryButton {
                    focusedField = nil
                    hideKeyboard()
                }
            }
        }
        .preferredColorScheme(ColorTheme.preferredScheme)
        .sheet(isPresented: $showProfileSetup) {
            if let uid = profileSetupUserId {
                EditProfileSheet(userId: uid)
                    .preferredColorScheme(ColorTheme.preferredScheme)
            }
        }
        .fullScreenCover(isPresented: $showVerificationScreen) {
            verificationHelpView
                .preferredColorScheme(ColorTheme.preferredScheme)
        }
        .onReceive(NotificationCenter.default.publisher(for: .emailVerificationNotDetected)) { _ in
            isBusy = false
            busyMessage = ""
            errorMessage = "Email verification not detected yet. Verify your email, then return and log in."
            if verificationEmail.isEmpty {
                verificationEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            showVerificationScreen = true
        }
    }

    private func beginBusy(_ message: String) {
        busyMessage = message
        isBusy = true
        errorMessage = ""
    }

    private func endBusy() {
        isBusy = false
        busyMessage = ""
    }

    // MARK: - Auth

    private func logIn() {
        beginBusy("Logging you in...")
        AuthService.shared.signIn(email: email, password: password) { result in
            switch result {
            case .success(let user):
                // Block unverified email/password users
                let providers = user.providerData.map { $0.providerID }
                if providers.contains("password") {
                    user.reload { _ in
                        let refreshed = Auth.auth().currentUser ?? user
                        if !refreshed.isEmailVerified {
                            refreshed.sendEmailVerification(completion: nil)
                            try? Auth.auth().signOut()
                            pendingEmailVerification = true
                            verificationEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            showVerificationScreen = true
                            endBusy()
                            self.errorMessage = "Please verify your email before logging in. We just sent a verification email."
                            return
                        }
                        pendingEmailVerification = false
                        showVerificationScreen = false
                        NotificationCenter.default.post(name: .requestAuthRefreshAfterLogin, object: nil)
                        self.user = refreshed
                        checkProfileSetupIfNeeded(userId: refreshed.uid)
                    }
                } else {
                    pendingEmailVerification = false
                    NotificationCenter.default.post(name: .requestAuthRefreshAfterLogin, object: nil)
                    self.user = user
                    checkProfileSetupIfNeeded(userId: user.uid)
                }
            case .failure(let error):
                endBusy()
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func signUp() {
        beginBusy("Creating your account...")
        let cleanHandle = ProfileIdentityValidator.sanitizedHandleInput(handle)
        let cleanName = ProfileIdentityValidator.normalizedDisplayName(displayName)

        guard !cleanHandle.isEmpty, !cleanName.isEmpty else {
            endBusy()
            self.errorMessage = "Enter display name and handle."
            return
        }
        if let error = ProfileIdentityValidator.displayNameError(cleanName) {
            endBusy()
            self.errorMessage = error
            return
        }
        if let error = ProfileIdentityValidator.handleError(cleanHandle) {
            endBusy()
            self.errorMessage = error
            return
        }

        checkHandleAvailability(cleanHandle, excludingUserId: nil) { isAvailable in
            guard isAvailable else {
                self.endBusy()
                self.errorMessage = "Handle already taken."
                return
            }
            // Proceed create
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let e = error { self.endBusy(); self.errorMessage = e.localizedDescription; return }
                guard let user = result?.user else { return }
                let uid = user.uid
                let userDoc: [String: Any] = [
                    "id": uid,
                    "email": self.email,
                    "display_name": cleanName,
                    "display_name_lower": cleanName.lowercased(),
                    "username": cleanHandle,
                    "username_lower": cleanHandle,
                    "handle": cleanHandle,
                    "search_prefix": UserProfile.searchPrefixes(username: cleanName, handle: cleanHandle)
                ]
                db.collection("users").document(uid).setData(userDoc, merge: true) { err in
                    if let err = err { self.endBusy(); self.errorMessage = err.localizedDescription; return }
                    db.collection("user_stats").document(uid).setData(["followers": 0, "following": 0], merge: true)
                    user.sendEmailVerification(completion: nil)
                    self.pendingEmailVerification = true
                    self.verificationEmail = self.email
                    self.showVerificationScreen = true
                    _ = AuthService.shared.signOut()
                    self.endBusy()
                    self.isSignup = false
                    self.password = ""
                    self.handle = ""
                    self.displayName = ""
                    self.displayNameError = ""
                    self.handleError = ""
                    self.infoMessage = "Verification email sent. Check your inbox, then come back and tap Log In."
                }
            }
        }
    }

    private func sendPasswordReset() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter your email to reset your password."
            return
        }
        beginBusy("Sending reset email...")
        infoMessage = ""
        Auth.auth().sendPasswordReset(withEmail: trimmedEmail) { error in
            self.endBusy()
            if let error = error {
                self.errorMessage = error.localizedDescription
            } else {
                self.infoMessage = "Password reset email sent."
            }
        }
    }

    private func resendVerificationEmail() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Enter email and password to resend verification."
            return
        }

        beginBusy("Sending verification email...")
        infoMessage = ""

        Auth.auth().signIn(withEmail: trimmedEmail, password: password) { result, error in
            if let error = error {
                self.endBusy()
                self.errorMessage = error.localizedDescription
                return
            }
            guard let firebaseUser = result?.user else {
                self.endBusy()
                self.errorMessage = "Unable to resend verification email right now."
                return
            }
            if firebaseUser.isEmailVerified {
                self.endBusy()
                self.infoMessage = "Email is already verified."
                self.pendingEmailVerification = false
                try? Auth.auth().signOut()
                return
            }
            firebaseUser.sendEmailVerification { sendError in
                self.endBusy()
                if let sendError = sendError {
                    self.errorMessage = sendError.localizedDescription
                } else {
                    self.pendingEmailVerification = true
                    self.infoMessage = "Verification email sent."
                }
                try? Auth.auth().signOut()
            }
        }
    }

    private var verificationHelpView: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(ColorTheme.accent)

                Text("Verify Your Email")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.text)

                Text("We sent a verification link to:")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)

                Text(verificationEmail)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .multilineTextAlignment(.center)

                Text("Open your email, verify your account, then return here and tap Log In. We’ll show a loading message while we finish signing you in.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                HStack(spacing: 10) {
                    Button("Resend Email") {
                        resendVerificationEmail()
                    }
                    .buttonStyle(.bordered)
                    .tint(ColorTheme.subtext)

                    Button("Go to Login") {
                        _ = AuthService.shared.signOut()
                        showVerificationScreen = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ColorTheme.accent)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(ColorTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(ColorTheme.separator, lineWidth: 1))
            )
            .padding(.horizontal, 20)
        }
    }

    private func signInWithApple() {
        errorMessage = ""
        infoMessage = ""
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
            endBusy()
            self.errorMessage = "Unable to start Apple sign-in."
            return
        }
        AuthService.shared.signInWithApple(presentationAnchor: window) { result in
            switch result {
            case .success(let user):
                beginBusy("Finishing Apple sign-in...")
                self.user = user
                checkProfileSetupIfNeeded(userId: user.uid)
            case .failure(let error):
                self.endBusy()
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func checkProfileSetupIfNeeded(userId: String) {
        profileSetupUserId = userId
        profileSetupAttempts += 1
        db.collection("users").document(userId).getDocument { snap, _ in
            let data = snap?.data() ?? [:]
            let username = (data["username"] as? String) ?? ""
            let handle = (data["handle"] as? String) ?? ""
            let displayName = (data["display_name"] as? String) ?? ""
            let needsUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || username.lowercased().hasPrefix("user_")
                || username.contains("@")
            let needsHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let needsDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if needsUsername || needsHandle || needsDisplayName {
                self.endBusy()
                showProfileSetup = true
                return
            }
            if (snap?.exists != true) && profileSetupAttempts < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    checkProfileSetupIfNeeded(userId: userId)
                }
            } else {
                self.endBusy()
            }
        }
    }

    // MARK: - Helpers

    private func hideKeyboard() {
        focusedField = nil
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func checkHandleAvailability(_ handle: String, excludingUserId: String?, completion: @escaping (Bool) -> Void) {
        let normalized = ProfileIdentityValidator.sanitizedHandleInput(handle)
        guard !normalized.isEmpty else {
            completion(false)
            return
        }

        db.collection("users")
            .whereField("username_lower", isEqualTo: normalized)
            .limit(to: 1)
            .getDocuments { snap, _ in
                let usernameTaken = (snap?.documents ?? []).contains { doc in
                    let docUserId = (doc.data()["id"] as? String) ?? doc.documentID
                    return docUserId != excludingUserId
                }
                if usernameTaken {
                    completion(false)
                    return
                }

                self.db.collection("users")
                    .whereField("handle", isEqualTo: normalized)
                    .limit(to: 1)
                    .getDocuments { handleSnap, _ in
                        let handleTaken = (handleSnap?.documents ?? []).contains { doc in
                            let docUserId = (doc.data()["id"] as? String) ?? doc.documentID
                            return docUserId != excludingUserId
                        }
                        completion(!handleTaken)
                    }
            }
    }
}

// PREVIEW
#if DEBUG
import FirebaseCore

struct LoginView_Previews: PreviewProvider {
    struct Wrapper: View {
        @State var fakeUser: User? = nil
        var body: some View {
            LoginView(user: $fakeUser)
                .preferredColorScheme(ColorTheme.preferredScheme)
        }
    }
    static var previews: some View {
        Wrapper()
    }
}
#endif
