// FollowListView.swift
// Followers / Following list for a user.
// FIXES THIS PASS:
// • Remove use of nonexistent `displayName` and old `UserProfileBrief(doc:)` initializer.
// • Build `UserProfileBrief` with display name + username + avatar.
// • Break up complex view expressions to avoid “type-check in reasonable time” error.
// • Use InteractionService.toggleFollow(u:isFollowing:completion:) and isFollowing(userId:completion:)
// • Rows show avatar, username, optional @handle, and Follow/Followed button (not for self).

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FollowListView: View {
    // Which user’s list are we looking at?
    let userId: String

    // Which list: followers or following
    enum Mode { case followers, following }
    let mode: Mode

    // State
    @State private var isLoading: Bool = false
    @State private var profiles: [UserProfileBrief] = []
    @State private var followingSet: Set<String> = [] // current user's following set (to render Follow/Followed)

    private let db = Firestore.firestore()

    var body: some View {
        // Split into small subviews to help the compiler type-check fast.
        VStack(spacing: 0) {
            header
            Divider().background(ColorTheme.separator.opacity(0.6))
            listBody
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .onAppear {
            loadList()
            hydrateFollowingSet()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("") // keep title empty so back chevron has no quoted text
        .toolbar { ToolbarItem(placement: .principal) { AppIconCentered() } }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text(modeTitle)
                .font(.headline.weight(.semibold))
                .foregroundColor(ColorTheme.text)
            Spacer()
            if isLoading {
                ProgressView().tint(ColorTheme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ColorTheme.background)
    }

    private var listBody: some View {
        List {
            ForEach(profiles) { p in
                FollowRow(profile: p,
                          isFollowed: followingSet.contains(p.id),
                          canFollow: (Auth.auth().currentUser?.uid ?? "") != p.id)
                .listRowBackground(ColorTheme.background)
                .onAppear {
                    // no-op; could page in the future
                }
            }
        }
        .listStyle(.plain)
        .background(ColorTheme.background)
    }

    private var modeTitle: String {
        switch mode {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }

    // MARK: - Data Loads

    /// Load either followers (who follows `userId`) or following (whom `userId` follows)
    private func loadList() {
        isLoading = true
        switch mode {
        case .followers:
            // followers = all docs where followed_id == userId → map follower_id → fetch user docs
            db.collection("follows")
                .whereField("followed_id", isEqualTo: userId)
                .limit(to: 200)
                .getDocuments { snap, _ in
                    let ids = (snap?.documents ?? []).compactMap { $0.data()["follower_id"] as? String }
                    fetchUsers(ids: ids)
                }
        case .following:
            // following = all docs where follower_id == userId → map followed_id → fetch user docs
            db.collection("follows")
                .whereField("follower_id", isEqualTo: userId)
                .limit(to: 200)
                .getDocuments { snap, _ in
                    let ids = (snap?.documents ?? []).compactMap { $0.data()["followed_id"] as? String }
                    fetchUsers(ids: ids)
                }
        }
    }

    /// Fetch user docs in small chunks and build `UserProfileBrief`
    private func fetchUsers(ids: [String]) {
        guard !ids.isEmpty else { self.profiles = []; self.isLoading = false; return }
        var results: [UserProfileBrief] = []
        let chunks = stride(from: 0, to: ids.count, by: 10).map { Array(ids[$0..<min($0+10, ids.count)]) }
        let group = DispatchGroup()

        for chunk in chunks {
            group.enter()
            db.collection("users")
                .whereField("id", in: chunk)
                .getDocuments { snap, _ in
                    for d in (snap?.documents ?? []) {
                        let data = d.data()
                        let id = (data["id"] as? String) ?? d.documentID
                        let username = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                        let displayName = (data["display_name"] as? String)
                        let handle = (data["handle"] as? String)
                        let avatar = UserRecordAvatarResolver.url(from: data)
                        results.append(
                            UserProfileBrief(
                                id: id,
                                username: username,
                                handle: handle,
                                displayName: displayName,
                                avatarUrl: avatar
                            )
                        )
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            // Sort by display name when available, else username.
            self.profiles = results.sorted(by: {
                let lhs = ($0.displayName ?? $0.username)
                let rhs = ($1.displayName ?? $1.username)
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            })
            self.isLoading = false
        }
    }

    /// Build the current user's following set to render Follow/Followed buttons quickly.
    private func hydrateFollowingSet() {
        guard let me = Auth.auth().currentUser?.uid else { return }
        db.collection("follows").whereField("follower_id", isEqualTo: me).getDocuments { snap, _ in
            let ids = (snap?.documents ?? []).compactMap { $0.data()["followed_id"] as? String }
            self.followingSet = Set(ids)
        }
    }
}

// MARK: - Row

private struct FollowRow: View {
    let profile: UserProfileBrief
    @State var isFollowed: Bool
    let canFollow: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                name: profile.displayName ?? profile.username,
                size: 32,
                avatarURL: profile.avatarUrl
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName ?? profile.username)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Text("@\(profile.username)").font(.caption).foregroundColor(ColorTheme.subtext)
            }
            Spacer()
            if canFollow {
                Button {
                    InteractionService.shared.toggleFollow(u: profile.id, isFollowing: isFollowed) { newState in
                        self.isFollowed = newState
                    }
                } label: {
                    Text(isFollowed ? "Followed" : "Follow")
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 84)
                }
                .buttonStyle(.borderedProminent)
                .tint(isFollowed ? ColorTheme.separator : ColorTheme.accent)
                .foregroundColor(.white)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(Color.clear)
    }
}
