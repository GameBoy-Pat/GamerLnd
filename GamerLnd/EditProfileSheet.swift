//
//  EditProfileSheet.swift
//  GamerLnd
//
//  Created by Patrick  Flood on 10/2/25.
//


// EditProfileSheet.swift
// Full-screen sheet to edit Display Name and @username (unique), plus bio.
// BEGINNERS:
// • Validates in real time. Username must be unique, 3–20 chars, [a-z0-9_], lowercased.
// • On Save: checks uniqueness, writes to /users/{uid}, updates username_lower + search_prefix,
//   and timestamps (created_at if missing, updated_at always).

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EditProfileSheet: View {
    let userId: String

    // Inputs
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""

    // Validation state
    @State private var nameError: String? = nil
    @State private var usernameError: String? = nil
    @State private var bioError: String? = nil
    @State private var saving: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Display Name")) {
                    TextField("Your name", text: $displayName)
                        .onChange(of: displayName) { _, newValue in
                            if newValue.count > ProfileIdentityValidator.maxDisplayNameLength {
                                displayName = String(newValue.prefix(ProfileIdentityValidator.maxDisplayNameLength))
                            }
                            validateName()
                        }
                    if let e = nameError {
                        Text(e).foregroundColor(ColorTheme.highlight).font(.caption)
                    }
                }

                Section(header: Text("Username")) {
                    HStack {
                        Text("@").foregroundColor(ColorTheme.subtext)
                        TextField("username", text: $username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: username) { _, _ in
                                username = ProfileIdentityValidator.sanitizedHandleInput(username)
                                validateUsernameFormat()
                            }
                    }
                    if let e = usernameError {
                        Text(e).foregroundColor(ColorTheme.highlight).font(.caption)
                    }
                }

                Section(header: Text("Bio")) {
                    TextEditor(text: $bio)
                        .frame(minHeight: 100)
                        .onChange(of: bio) { _, _ in validateBio() }
                    HStack {
                        Spacer()
                        Text("\(bio.count)/160").font(.caption).foregroundColor(ColorTheme.subtext)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ColorTheme.background)
            .navigationBarTitle("Edit Profile", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving || !allValid)
                }
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - Load existing

    private func load() {
        db.collection("users").document(userId).getDocument { doc, _ in
            let data = doc?.data() ?? [:]
            self.displayName = (data["display_name"] as? String) ?? (data["username"] as? String) ?? ""
            self.username = ((data["username"] as? String) ?? (data["handle"] as? String) ?? "").lowercased()
            self.bio = (data["bio"] as? String) ?? ""
            validateAll()
        }
    }

    // MARK: - Validation

    private var allValid: Bool {
        return nameError == nil && usernameError == nil && bioError == nil && !displayName.isEmpty && !username.isEmpty
    }

    private func validateAll() {
        validateName()
        validateUsernameFormat()
        validateBio()
    }

    private func validateName() {
        nameError = ProfileIdentityValidator.displayNameError(displayName)
    }

    private func validateUsernameFormat() {
        usernameError = ProfileIdentityValidator.handleError(username)
    }

    private func validateBio() {
        bioError = (bio.count <= 160) ? nil : "Bio must be ≤ 160 characters."
    }

    // MARK: - Save flow

    private func save() {
        validateAll()
        guard allValid else { return }
        saving = true

        let normalizedUsername = ProfileIdentityValidator.sanitizedHandleInput(username)

        // Uniqueness check (allow my own doc)
        db.collection("users")
            .whereField("username_lower", isEqualTo: normalizedUsername)
            .limit(to: 1)
            .getDocuments { snap, _ in
                let takenByOther = (snap?.documents ?? []).contains { $0.documentID != self.userId }
                if takenByOther {
                    self.usernameError = "That username is taken."
                    self.saving = false
                    return
                }
                self.db.collection("users")
                    .whereField("handle", isEqualTo: normalizedUsername)
                    .limit(to: 1)
                    .getDocuments { handleSnap, _ in
                        let handleTakenByOther = (handleSnap?.documents ?? []).contains { $0.documentID != self.userId }
                        if handleTakenByOther {
                            self.usernameError = "That username is taken."
                            self.saving = false
                            return
                        }
                        self.writeProfile(username: normalizedUsername)
                    }
            }
    }

    private func writeProfile(username: String) {
        guard let current = Auth.auth().currentUser, current.uid == userId else {
            self.saving = false
            return
        }
        let now = Timestamp(date: Date())
        let docRef = db.collection("users").document(userId)

        docRef.getDocument { doc, _ in
            let existed = (doc?.exists == true)
            var data: [String: Any] = [
                "id": self.userId,
                "display_name": self.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                "display_name_lower": self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                "username": username,
                "username_lower": username.lowercased(),
                "handle": username,
                "bio": self.bio,
                "updated_at": now,
                "search_prefix": UserProfile.searchPrefixes(username: self.displayName, handle: username)
            ]
            if !existed {
                data["created_at"] = now
                if let email = current.email { data["email"] = email }
            }
            docRef.setData(data, merge: true) { _ in
                self.saving = false
                self.dismiss()
            }
        }
    }
}
