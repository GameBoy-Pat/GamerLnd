// ProfileEditView.swift
// Simple profile editor for avatar, bio, and username.
// THIS PASS:
// • Users can pick a profile image; we upload to Firebase Storage at avatars/{uid}.jpg
// • Saved download URL is written to /users/{uid}.avatar_url
// • Keeps username & bio editing.
// • Default dark theme + error handling.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI

struct ProfileEditView: View {
    let userId: String
    @Binding var isPresented: Bool

    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var avatarURL: String = ""

    @State private var isSaving: Bool = false
    @State private var errorText: String = ""

    // Image picking
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImageData: Data? = nil
    @State private var isUploading: Bool = false

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            // Preview of current avatar or picked image
                            if let data = pickedImageData, let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                            } else if !avatarURL.isEmpty {
                                AsyncImage(url: URL(string: avatarURL)) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill()
                                    } else if case .empty = phase {
                                        ProgressView().tint(ColorTheme.accent)
                                    } else {
                                        Image(systemName: "person.fill")
                                            .resizable().scaledToFit().padding(16)
                                            .foregroundColor(.white)
                                            .background(Color.gray.opacity(0.4))
                                    }
                                }
                            } else {
                                Image(systemName: "person.fill")
                                    .resizable().scaledToFit().padding(16)
                                    .foregroundColor(.white)
                                    .background(Color.gray.opacity(0.4))
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))

                        PhotosPicker(selection: $pickedItem, matching: .images, preferredItemEncoding: .automatic) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text("Change Profile Image")
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .onChange(of: pickedItem) { _, _ in loadPickedData() }

                        if isUploading {
                            ProgressView("Uploading…").tint(ColorTheme.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(ColorTheme.surface)

                Section(header: Text("Public")) {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                }
                .listRowBackground(ColorTheme.surface)

                if !errorText.isEmpty {
                    Text(errorText).foregroundColor(ColorTheme.highlight).font(.caption)
                        .listRowBackground(ColorTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ColorTheme.background)
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(ColorTheme.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView().tint(ColorTheme.accent) }
                        else { Text("Save").bold() }
                    }
                    .disabled(isSaving || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploading)
                }
            }
            .onAppear { load() }
        }
        .tint(ColorTheme.accent)
    }

    // MARK: - Loading

    private func load() {
        db.collection("users").document(userId).getDocument { snap, _ in
            let d = snap?.data() ?? [:]
            username = (d["username"] as? String) ?? ""
            bio = (d["bio"] as? String) ?? ""
            avatarURL = (d["avatar_url"] as? String) ?? ""
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true; errorText = ""

        var patch: [String: Any] = [
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "bio": bio
        ]
        if !avatarURL.isEmpty {
            patch["avatar_url"] = avatarURL
        }

        db.collection("users").document(userId).setData(patch, merge: true) { err in
            isSaving = false
            if let err = err {
                errorText = err.localizedDescription
            } else {
                isPresented = false
            }
        }
    }

    // MARK: - Image Picker

    private func loadPickedData() {
        guard let item = pickedItem else { return }
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        pickedImageData = data
                    }
                    await uploadAvatar(data: data)
                }
            } catch {
                await MainActor.run {
                    errorText = "Failed to read image."
                }
            }
        }
    }

    private func uploadAvatar(data: Data) async {
        await MainActor.run { isUploading = true; errorText = "" }
        // Compress to a reasonable size
        let maxKB = 500
        let jpegData: Data
        if let ui = UIImage(data: data),
           let compressed = ui.jpegData(compressionQuality: 0.8),
           compressed.count <= maxKB * 1024 {
            jpegData = compressed
        } else if let ui = UIImage(data: data),
                  let compressed = ui.jpegData(compressionQuality: 0.65) {
            jpegData = compressed
        } else {
            jpegData = data
        }

        let ref = storage.reference().child("avatars/\(userId).jpg")
        do {
            _ = try await ref.putDataAsync(jpegData, metadata: {
                let meta = StorageMetadata()
                meta.contentType = "image/jpeg"
                return meta
            }())
            let url = try await ref.downloadURL()
            await MainActor.run {
                self.avatarURL = url.absoluteString
                self.isUploading = false
            }
        } catch {
            await MainActor.run {
                self.errorText = error.localizedDescription
                self.isUploading = false
            }
        }
    }
}
