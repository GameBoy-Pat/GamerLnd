// SettingsSheet.swift
// App settings sheet with dark mode toggle, logout, privacy policy.
// BEGINNERS:
// • @AppStorage persists simple settings in UserDefaults across launches.
// • Logout uses FirebaseAuth.signOut() and dismisses the sheet.
// • Crashlytics debug button removed to simplify build setup.

import SwiftUI
import FirebaseAuth

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    // Persisted setting for theme; GamerLndApp registers a default of "dark".
    @AppStorage("themeMode") private var themeMode: String = "dark"

    // Local UI state
    @State private var showingPrivacy: Bool = false
    @State private var showingTerms: Bool = false
    @State private var showingSupport: Bool = false
    @State private var showingDeleteConfirm: Bool = false
    @State private var showingDeleteAuthSheet: Bool = false
    @State private var isDeleting: Bool = false
    @State private var errorText: String = ""
    @State private var deleteEmail: String = ""
    @State private var deletePassword: String = ""

    var body: some View {
        NavigationView {
            List {
                // Appearance
                Section(header: Text("Appearance").foregroundColor(ColorTheme.subtext)) {
                    Picker("Theme", selection: $themeMode) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("System").tag("system")
                    }
                    .pickerStyle(.segmented)
                    .tint(ColorTheme.accent)
                }
                .listRowBackground(ColorTheme.surface)

                // Account
                Section(header: Text("Account").foregroundColor(ColorTheme.subtext)) {
                    Button {
                        signOut()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log Out")
                        }
                        .foregroundColor(ColorTheme.highlight)
                    }
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.caption)
                            .foregroundColor(ColorTheme.highlight)
                    }
                }
                .listRowBackground(ColorTheme.surface)

                // About
                Section(header: Text("About").foregroundColor(ColorTheme.subtext)) {
                    Button {
                        showingPrivacy = true
                    } label: {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                            Text("Privacy Policy")
                        }
                        .foregroundColor(ColorTheme.accent)
                    }
                    Button {
                        showingTerms = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("Terms of Service")
                        }
                        .foregroundColor(ColorTheme.accent)
                    }
                    Button {
                        showingSupport = true
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle.fill")
                            Text("Support")
                        }
                        .foregroundColor(ColorTheme.accent)
                    }
                }
                .listRowBackground(ColorTheme.surface)

                // Danger Zone (at bottom to prevent accidental taps)
                Section(header: Text("Danger Zone").foregroundColor(ColorTheme.subtext)) {
                    Button {
                        beginDeleteFlow()
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text(isDeleting ? "Deleting..." : "Delete Account")
                        }
                        .foregroundColor(ColorTheme.highlight)
                    }
                    .disabled(isDeleting)
                }
                .listRowBackground(ColorTheme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ColorTheme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ColorTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingPrivacy) {
                PrivacyPolicyView()
                    .preferredColorScheme(ColorTheme.preferredScheme)
            }
            .sheet(isPresented: $showingTerms) {
                TermsOfServiceView()
                    .preferredColorScheme(ColorTheme.preferredScheme)
            }
            .sheet(isPresented: $showingSupport) {
                SupportView()
                    .preferredColorScheme(ColorTheme.preferredScheme)
            }
            .sheet(isPresented: $showingDeleteAuthSheet) {
                deleteAuthSheet
                    .preferredColorScheme(ColorTheme.preferredScheme)
            }
            .alert("Delete Account?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteAccount() }
            } message: {
                Text("This permanently deletes your account and data. This cannot be undone.")
            }
        }
        .tint(ColorTheme.accent)
        .preferredColorScheme(ColorTheme.preferredScheme)
        .presentationCornerRadius(16)
    }

    // MARK: - Actions

    private func signOut() {
        do {
            UserDefaults.standard.set(false, forKey: "pendingEmailVerification")
            try Auth.auth().signOut()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func beginDeleteFlow() {
        errorText = ""
        deleteEmail = Auth.auth().currentUser?.email ?? ""
        deletePassword = ""
        showingDeleteAuthSheet = true
    }

    private func confirmDeleteCredentials() {
        guard let user = Auth.auth().currentUser else {
            errorText = "No signed-in user."
            return
        }
        let providers = Set(user.providerData.map { $0.providerID })
        guard providers.contains("password") else {
            errorText = "This account does not use email/password. Log out and sign back in with your provider to delete."
            showingDeleteAuthSheet = false
            return
        }

        let trimmedEmail = deleteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !deletePassword.isEmpty else {
            errorText = "Enter email and password to confirm delete."
            return
        }

        isDeleting = true
        let credential = EmailAuthProvider.credential(withEmail: trimmedEmail, password: deletePassword)
        user.reauthenticate(with: credential) { _, err in
            DispatchQueue.main.async {
                isDeleting = false
                if let err = err {
                    errorText = err.localizedDescription
                    return
                }
                showingDeleteAuthSheet = false
                showingDeleteConfirm = true
            }
        }
    }

    private func deleteAccount() {
        isDeleting = true
        errorText = ""
        AuthService.shared.deleteAccount { result in
            isDeleting = false
            switch result {
            case .success:
                dismiss()
            case .failure(let err):
                errorText = err.localizedDescription
            }
        }
    }

    private var deleteAuthSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirm your email and password to delete your account.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)

                TextField("Email", text: $deleteEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ColorTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    )

                SecureField("Password", text: $deletePassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ColorTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    )

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(ColorTheme.highlight)
                }

                Button {
                    confirmDeleteCredentials()
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Confirm Delete")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ColorTheme.highlight)
                )
                .foregroundColor(.white)
                .disabled(isDeleting)

                Spacer()
            }
            .padding(16)
            .background(ColorTheme.background.ignoresSafeArea())
            .navigationTitle("Delete Account")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingDeleteAuthSheet = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ColorTheme.accent)
                    }
                }
            }
        }
        .presentationCornerRadius(16)
    }
}

// PREVIEW
#if DEBUG
struct SettingsSheet_Previews: PreviewProvider {
    static var previews: some View {
        SettingsSheet()
            .preferredColorScheme(ColorTheme.preferredScheme)
    }
}
#endif
