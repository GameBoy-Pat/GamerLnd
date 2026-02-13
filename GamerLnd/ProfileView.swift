// ProfileView.swift
// User profile with refined header, live username availability check,
// PhotosPicker-based profile image, tighter header spacing, keyboard-aware stats sheet,
// section reordering, and no-flicker loads.

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import os.log
import Combine

struct ProfileView: View {
    let userId: String

    // User (lite)
    @State private var displayName: String = "User"
    @State private var username: String = "user"
    @State private var bio: String = ""
    @State private var avatarUrl: String? = nil

    // Follow stats
    @State private var followers: Int = 0
    @State private var following: Int = 0
    @State private var avgUserRating: Double? = nil
    @State private var avgUserRatingCount: Int = 0
    @State private var isMe: Bool = false
    @State private var isFollowing: Bool = false

    // Recently logged
    @State private var recentLogs: [GameLog] = []
    @State private var gameNames: [Int: String] = [:]
    @State private var avgCache: [Int: (avg: Double?, count: Int)] = [:]

    // Lists (lite)
    struct UserListLite: Identifiable {
        let id: String
        let title: String
        let itemCount: Int
        let isPublic: Bool
        let updatedAt: Timestamp?
        let type: String
        let previewCoverIds: [String]?
        let rawItemsArray: [[String: Any]]?
        let tierLabels: [String]?
        let tierColors: [String]?
    }
    @State private var lists: [UserListLite] = []
    @State private var listPreviewCovers: [String: [String]] = [:]  // listId → [imageIds up to 4]

    // Favorites / Watchlist
    @State private var favoriteGame: Game? = nil
    @State private var watchlist: [Game] = []
    @State private var favoritePlayStyle: String = ""
    @State private var favoritePlatform: String = ""
    @State private var favoriteGenre: String = ""
    @State private var favoriteFranchise: String = ""

    // Loading / flicker control
    @State private var isLoadingProfile: Bool = true
    @State private var hasLoadedOnce: Bool = false

    // Sheets
    @State private var showSettingsSheet: Bool = false
    @State private var showNewListSheet: Bool = false
    @State private var showEditProfile: Bool = false
    @State private var showStats: Bool = false
    @State private var showFollowersSheet: Bool = false
    @State private var showFollowingSheet: Bool = false
    @State private var showLogsSheet: Bool = false
    @State private var dragToast: String? = nil
    @State private var isEditingSavedGames: Bool = false
    @State private var savedGameForLog: Game? = nil

    // Reorder sections
    enum SectionKind: String, CaseIterable, Identifiable {
        case saved = "Saved Games"
        case lists = "Lists"
        case recent = "Recently Logged"
        var id: String { rawValue }
    }
    @State private var sectionsOrder: [SectionKind] = [.saved, .lists, .recent]
    @State private var showReorderSections: Bool = false

    // Services
    private let db = Firestore.firestore()
    private let igdb = IGDBService()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header (slightly smaller; centered; spaced from top)
                header

                // Scrollable sections
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(sectionsOrder.enumerated()), id: \.offset) { idx, section in
                            switch section {
                            case .saved:
                                savedGamesBlock
                            case .lists:
                                listsBlock
                            case .recent:
                                recentBlock
                            }
                            if idx < sectionsOrder.count - 1 {
                                Divider().opacity(0.25)
                            }
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.top, 6)
                }
                .background(ColorTheme.background)
                .overlay(alignment: .top) {
                    if let msg = dragToast {
                        Text(msg)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .background(ColorTheme.background.ignoresSafeArea())

            // Loading overlays (no full-screen flicker)
            if isLoadingProfile && hasLoadedOnce == false {
                ProgressView().tint(ColorTheme.accent)
            } else if isLoadingProfile && hasLoadedOnce == true {
                VStack {
                    HStack {
                        Spacer()
                        ProgressView().tint(ColorTheme.accent)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .navigationTitle("")
        .onAppear {
            let me = Auth.auth().currentUser?.uid ?? ""
            self.isMe = (me == userId)
            loadUser()
            loadFollows()
            loadRecentLogs()
            loadUserRatingAverage()
            loadLists()
            AnalyticsService.shared.screen("Profile")
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheet().preferredColorScheme(ColorTheme.preferredScheme)
        }
        .sheet(isPresented: $showFollowersSheet) {
            NavigationView { FollowListView(userId: userId, mode: .followers) }
                .preferredColorScheme(ColorTheme.preferredScheme)
        }
        .sheet(isPresented: $showFollowingSheet) {
            NavigationView { FollowListView(userId: userId, mode: .following) }
                .preferredColorScheme(ColorTheme.preferredScheme)
        }
        .sheet(isPresented: $showLogsSheet) {
            NavigationView { UserLogsListView(userId: userId, logs: recentLogs, gameNames: gameNames) }
                .preferredColorScheme(ColorTheme.preferredScheme)
        }
        .sheet(isPresented: $showNewListSheet) {
            NewListSheet(ownerId: userId) { loadLists() }
                .preferredColorScheme(ColorTheme.preferredScheme)
                .presentationDetents([.fraction(0.85)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(16)
        }
        .sheet(isPresented: $showEditProfile) {
            ProfileEditSheet(
                userId: userId,
                currentDisplayName: displayName,
                currentUsername: username,
                currentBio: bio,
                currentAvatarUrl: avatarUrl,
                sectionsOrder: $sectionsOrder,
                onSaved: { newDisplayName, newUsername, newBio, newAvatar in
                    self.displayName = newDisplayName
                    self.username = newUsername
                    self.bio = newBio
                    self.avatarUrl = newAvatar
                },
                onReorderSaved: { order in self.sectionsOrder = order }
            )
            .preferredColorScheme(ColorTheme.preferredScheme)
        }
        .sheet(isPresented: $showReorderSections) {
            ReorderSectionsView(
                order: $sectionsOrder,
                onSave: { newOrder in
                    sectionsOrder = newOrder
                    persistSectionsOrder(newOrder)
                }
            )
            .preferredColorScheme(ColorTheme.preferredScheme)
            .presentationDetents([.fraction(0.7)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(16)
        }
        .sheet(isPresented: $showStats) {
            StatsSheet(
                userId: userId,
                followers: followers,
                following: following,
                recentLogs: recentLogs,
                avgCache: avgCache,
                isOwner: isMe,
                favoriteGame: favoriteGame,
                watchlist: watchlist,
                favoritePlayStyle: favoritePlayStyle,
                favoritePlatform: favoritePlatform,
                favoriteGenre: favoriteGenre,
                favoriteFranchise: favoriteFranchise,
                onSaved: { fav, watch, playStyle, platform, genre, franchise in
                    favoriteGame = fav
                    watchlist = watch
                    favoritePlayStyle = playStyle
                    favoritePlatform = platform
                    favoriteGenre = genre
                    favoriteFranchise = franchise
                }
            )
            .preferredColorScheme(ColorTheme.preferredScheme)
            .presentationDetents([.fraction(0.85)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(16)
        }
        .sheet(item: $savedGameForLog) { game in
            GameDetailView(game: game)
                .preferredColorScheme(ColorTheme.preferredScheme)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 10) // slightly reduced top breathing room

            HStack(alignment: .center, spacing: 12) {
                AvatarView(name: displayName, size: 88, avatarURL: avatarUrl)
                    .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(1)
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.subtext)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            // Bio
            if !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bio)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            // Stats row (+ more stats)
            statsRow
                .padding(.bottom, 10)

            // Buttons row: Edit Profile + Reorder + Settings (adjacent)
            if isMe {
                HStack(spacing: 10) {
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                            Text("Edit Profile")
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(ColorTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                        )
                        .foregroundColor(ColorTheme.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showReorderSections = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.arrow.down.circle.fill")
                            Text("Reorder")
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(ColorTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                        )
                        .foregroundColor(ColorTheme.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showSettingsSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                            Text("Settings")
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(ColorTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                        )
                        .foregroundColor(ColorTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            } else {
                Button {
                    InteractionService.shared.toggleFollow(u: userId, isFollowing: isFollowing) { newState in
                        isFollowing = newState
                        followers = max(0, followers + (newState ? 1 : -1))
                        AnalyticsService.shared.trackFollow(targetUserId: userId, nowFollowing: newState)
                    }
                } label: {
                    Text(isFollowing ? "Followed" : "Follow")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            Group {
                                if isFollowing {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(ColorTheme.separator.opacity(0.25))
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(ColorTheme.surface)
                                }
                            }
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .foregroundColor(isFollowing ? ColorTheme.highlight : ColorTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        // Pull the next content upward to remove the large gap.
        .padding(.bottom, 12)
    }

    private func statBlock(value: Int, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Text(label)
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var statsRow: some View {
        let loggedCount = recentLogs.count
        let reviewsCount = recentLogs.reduce(0) { acc, log in
            if let t = log.review, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return acc + 1 }
            return acc
        }

        return VStack(spacing: 10) {
            HStack(spacing: 0) {
                statBlock(value: followers, label: "Followers") { showFollowersSheet = true }
                Divider().frame(height: 26).opacity(0.4)
                statBlock(value: following, label: "Following") { showFollowingSheet = true }
                Divider().frame(height: 26).opacity(0.4)
                statBlock(value: loggedCount, label: "Logged") { showLogsSheet = true }
            }

            HStack(spacing: 8) {
                miniStatChip(label: "Reviews", value: "\(reviewsCount)")
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(ColorTheme.highlight)
                    Text(String(format: "%.1f", avgUserRating ?? 0.0))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.highlight)
                    Text("avg")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                Spacer()
                Button {
                    showStats = true
                    Haptics.select()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                        Text("More Stats")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More Stats")
            }

            // Favorites summary (moved into stats block)
            if let fav = favoriteGame {
                HStack(spacing: 10) {
                    if let imgId = fav.cover?.imageId {
                        GameCoverImage(id: imgId, preset: .custom(width: 42), cornerRadius: 8)
                            .frame(width: 42, height: 56)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ColorTheme.separator.opacity(0.2))
                            .frame(width: 42, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Favorite Game")
                            .font(.caption2)
                            .foregroundColor(ColorTheme.subtext)
                        Text(fav.name)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(2)
                    }
                    Spacer()
                }
            } else {
                Text(isMe ? "Pick a favorite game in More Stats." : "No favorite game yet.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .padding(.horizontal, 16)
        .overlay(
            Rectangle()
                .fill(ColorTheme.separator.opacity(0.5))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func miniStatChip(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.text)
            Text(label)
                .font(.caption2)
                .foregroundColor(ColorTheme.subtext)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
    }

    // MARK: - Sections

    private var savedGamesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Saved Games")
                Spacer()
                if isMe && !watchlist.isEmpty {
                    Button(isEditingSavedGames ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingSavedGames.toggle()
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                }
            }

            if watchlist.isEmpty {
                Text(isMe ? "Add games to your saved games from Explore." : "No saved games yet.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button {
                            NotificationCenter.default.post(name: .switchToExplore, object: nil)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(ColorTheme.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(ColorTheme.accent)
                            }
                            .frame(width: 60, height: 80)
                            .frame(width: 84, height: 124, alignment: .top)
                        }
                        .buttonStyle(.plain)

                        ForEach(watchlist.prefix(12), id: \.id) { g in
                            ZStack(alignment: .topTrailing) {
                                VStack(alignment: .center, spacing: 6) {
                                    if let img = g.cover?.imageId {
                                        GameCoverImage(id: img, preset: .small, cornerRadius: 8)
                                            .frame(width: 60, height: 80)
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(ColorTheme.separator.opacity(0.25))
                                            .frame(width: 60, height: 80)
                                    }
                                    Text(g.name)
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.text)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: 84, height: 124, alignment: .top)

                                if isEditingSavedGames {
                                    Button {
                                        removeFromSavedGames(g)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(ColorTheme.highlight)
                                            .background(Circle().fill(ColorTheme.surface))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 6, y: -6)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isEditingSavedGames {
                                    savedGameForLog = g
                                }
                            }
                            .onDrag {
                                guard isMe else { return NSItemProvider() }
                                return NSItemProvider(object: "\(g.id)" as NSString)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var listsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with inline "New List" on the right
            HStack {
                SectionHeader(title: "Lists")
                Spacer()
                if isMe {
                    Button {
                        showNewListSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("New List").bold()
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                        .foregroundColor(ColorTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if lists.isEmpty {
                Text(isMe ? "You haven’t created any lists yet." : "No lists yet.")
                    .foregroundColor(ColorTheme.subtext)
                    .font(.footnote)
                    .padding(.horizontal, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(lists) { l in
                            NavigationLink(
                                destination: ListDetailView(
                                    list: convertToUserList(l),
                                    isOwner: isMe
                                )
                            ) {
                                ListRectangleCard(
                                    list: l,
                                    previewImageIds: listPreviewCovers[l.id] ?? [],
                                    cardWidth: 300,
                                    cardHeight: 172,
                                    previewSide: 112
                                )
                                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                                    handleDrop(providers: providers, onto: l)
                                }
                                .padding(.leading, l.id == lists.first?.id ? 16 : 0)
                                .padding(.trailing, l.id == lists.last?.id ? 16 : 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 16)
        // remove extra top padding so it hugs the header
    }

    private var recentBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Recently Logged")

            if recentLogs.isEmpty {
                Text(isMe ? "You haven’t logged any games yet." : "No logs yet.")
                    .foregroundColor(ColorTheme.subtext)
                    .font(.footnote)
                    .padding(.horizontal, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentLogs, id: \.id) { log in
                            let cached = gameNames[log.gameId]
                            let title = (cached == "Unknown Game" || cached == nil || cached?.hasPrefix("Game #") == true)
                                ? (log.gameName ?? "Loading…")
                                : (cached ?? "Loading…")
                            let avg = avgCache[log.gameId]?.avg
                            let count = avgCache[log.gameId]?.count ?? 0
                            NavigationLink(
                                destination: GameLogDetailView(
                                    gameLog: log,
                                    gameName: title,
                                    authorUsernameOverride: displayName,
                                    focusCommentOnAppear: false
                                )
                            ) {
                                RecentLogRowCard(
                                    log: log,
                                    title: title,
                                    avg: avg,
                                    count: count
                                )
                                .padding(.leading, log.id == recentLogs.first?.id ? 16 : 0)
                                .padding(.trailing, log.id == recentLogs.last?.id ? 16 : 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Loads

    private func loadUser() {
        if !hasLoadedOnce { isLoadingProfile = true }
        db.collection("users").document(userId).getDocument { doc, _ in
            let data = doc?.data() ?? [:]

            // Username (unique) + display name
            let fetchedUsername = (data["username"] as? String) ?? (data["email"] as? String) ?? username
            self.username = fetchedUsername
            self.displayName = (data["display_name"] as? String) ?? (data["username"] as? String) ?? (data["email"] as? String) ?? displayName

            self.bio = (data["bio"] as? String) ?? self.bio
            self.avatarUrl = data["avatar_url"] as? String

            if let fav = data["favorite_game"] as? [String: Any] {
                self.favoriteGame = self.gameFromDict(fav)
            }
            if let watch = data["watchlist_games"] as? [[String: Any]] {
                self.watchlist = watch.compactMap { self.gameFromDict($0) }
                self.hydrateWatchlistNamesIfNeeded()
            }
            self.favoritePlayStyle = (data["favorite_play_style"] as? String) ?? ""
            self.favoritePlatform = (data["favorite_platform"] as? String) ?? ""
            self.favoriteGenre = (data["favorite_genre"] as? String) ?? ""
            self.favoriteFranchise = (data["favorite_franchise"] as? String) ?? ""

            if !isMe {
                InteractionService.shared.isFollowing(targetUserId: userId) { state in
                    self.isFollowing = state
                }
            }

            if let orderRaw = data["sections_order"] as? [String] {
                let mapped = orderRaw.compactMap { SectionKind(rawValue: $0) }
                if !mapped.isEmpty {
                    self.sectionsOrder = mapped
                }
            }
            self.isLoadingProfile = false
            self.hasLoadedOnce = true
        }
    }

    private func persistSectionsOrder(_ order: [SectionKind]) {
        guard isMe, let uid = Auth.auth().currentUser?.uid else { return }
        let raw = order.map { $0.rawValue }
        db.collection("users").document(uid).setData(["sections_order": raw], merge: true)
    }

    private func hydrateWatchlistNamesIfNeeded() {
        let needs = watchlist.filter { game in
            let name = game.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty || name.hasPrefix("Game #") || name == "Unknown Game"
        }
        let ids = Array(Set(needs.map { $0.id }))
        guard !ids.isEmpty else { return }

        Task {
            let fetched = await GameNameCache.shared.fillAndGet(namesFor: ids)
            await MainActor.run {
                var changed = false
                var updated: [Game] = []
                updated.reserveCapacity(watchlist.count)
                for game in watchlist {
                    if let name = fetched[game.id], !name.isEmpty {
                        if game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || game.name.hasPrefix("Game #")
                            || game.name == "Unknown Game" {
                            let refreshed = Game(
                                id: game.id,
                                name: name,
                                cover: game.cover,
                                firstReleaseDate: game.firstReleaseDate,
                                genres: game.genres,
                                platforms: game.platforms,
                                rating: game.rating,
                                ratingCount: game.ratingCount,
                                totalRatingCount: game.totalRatingCount,
                                screenshots: game.screenshots
                            )
                            updated.append(refreshed)
                            changed = true
                            continue
                        }
                    }
                    updated.append(game)
                }
                if changed {
                    watchlist = updated
                    if isMe, let uid = Auth.auth().currentUser?.uid {
                        let payload = ["watchlist_games": watchlist.map { gameToDict($0) }]
                        db.collection("users").document(uid).setData(payload, merge: true)
                    }
                }
            }
        }
    }

    private func loadFollows() {
        db.collection("follows")
            .whereField("followed_id", isEqualTo: userId)
            .getDocuments { snap, _ in
                self.followers = snap?.documents.count ?? self.followers
            }
        db.collection("follows")
            .whereField("follower_id", isEqualTo: userId)
            .getDocuments { snap, _ in
                self.following = snap?.documents.count ?? self.following
            }
    }

    private func loadRecentLogs() {
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: userId)
            .order(by: "play_date", descending: true)
            .limit(to: 20)
            .getDocuments { snap, _ in
                let logs: [GameLog] = (snap?.documents ?? []).compactMap { d in
                    Self.parseGameLog(docIdFallback: d.documentID, data: d.data())
                }
                self.recentLogs = logs

                // Prime names + averages
                let gameIds = Array(Set(logs.map { $0.gameId }))
                Task {
                    let names = await GameNameCache.shared.fillAndGet(namesFor: gameIds)
                    await MainActor.run { for (gid, n) in names { self.gameNames[gid] = n } }
                }
                for gid in gameIds {
                    if self.avgCache[gid] == nil {
                        GamerLndScoreService.shared.fetchAverage(gameId: gid) { avg, count in
                            DispatchQueue.main.async {
                                self.avgCache[gid] = (avg, count)
                            }
                        }
                    }
                }
            }
    }

    private func loadUserRatingAverage() {
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: userId)
            .limit(to: 300)
            .getDocuments { snap, _ in
                let ratings: [Double] = (snap?.documents ?? []).compactMap { d in
                    if let r = d.data()["rating"] as? Double, r > 0 { return r }
                    if let rI = d.data()["rating"] as? Int, rI > 0 { return Double(rI) }
                    if let rN = d.data()["rating"] as? NSNumber, rN.doubleValue > 0 { return rN.doubleValue }
                    return nil
                }
                if ratings.isEmpty {
                    self.avgUserRating = nil
                    self.avgUserRatingCount = 0
                } else {
                    self.avgUserRatingCount = ratings.count
                    self.avgUserRating = ratings.reduce(0, +) / Double(ratings.count)
                }
            }
    }

    private func loadLists() {
        db.collection("lists")
            .whereField("owner_id", isEqualTo: userId)
            .order(by: "updated_at", descending: true)
            .limit(to: 20)
            .getDocuments { snap, _ in
                self.lists = (snap?.documents ?? []).compactMap { d in
                    let data = d.data()
                    let id = (data["id"] as? String) ?? d.documentID
                    let title = (data["title"] as? String) ?? "Untitled"
                    let count = (data["item_count"] as? Int) ?? 0
                    let isPublic = (data["is_public"] as? Bool) ?? true
                    let updatedAt = data["updated_at"] as? Timestamp
                    let type = (data["type"] as? String) ?? "regular"
                    let previewIds = data["preview_cover_ids"] as? [String]
                    let tierLabels = data["tier_labels"] as? [String]
                    let tierColors = data["tier_colors"] as? [String]
                    return UserListLite(
                        id: id, title: title, itemCount: count, isPublic: isPublic,
                        updatedAt: updatedAt, type: type,
                        previewCoverIds: previewIds, rawItemsArray: nil,
                        tierLabels: tierLabels, tierColors: tierColors
                    )
                }

                // Load previews
                self.listPreviewCovers.removeAll()
                for lid in self.lists.map({ $0.id }) {
                    if let cached = self.lists.first(where: { $0.id == lid })?.previewCoverIds, !cached.isEmpty {
                        self.listPreviewCovers[lid] = Array(cached.prefix(4))
                    } else {
                        self.loadPreviewForList(listId: lid)
                    }
                }
            }
    }

    /// Try subcollection first: /lists/{listId}/items. If none found, fallback to flat "list_items".
    private func loadPreviewForList(listId: String) {
        db.collection("lists").document(listId).collection("items")
            .limit(to: 12)
            .getDocuments { snap, err in
                if let err = err {
                    os_log("subcollection preview err (%{public}@): %{public}@", listId, err.localizedDescription)
                    self.loadPreviewFromFlatCollection(listId: listId)
                    return
                }
                let docs = snap?.documents ?? []
                let parsed = self.extractCoverIdsAndFallbackGameIds(from: docs)
                self.applyPreviewResult(listId: listId, parsed: parsed)
            }
    }

    private func loadPreviewFromFlatCollection(listId: String) {
        db.collection("list_items")
            .whereField("list_id", isEqualTo: listId)
            .limit(to: 12)
            .getDocuments { snap, _ in
                let docs = snap?.documents ?? []
                let parsed = self.extractCoverIdsAndFallbackGameIds(from: docs)
                self.applyPreviewResult(listId: listId, parsed: parsed)
            }
    }

    private func applyPreviewResult(listId: String, parsed: (coverIds: [String], fallbackGameIds: [Int])) {
        if !parsed.coverIds.isEmpty {
            DispatchQueue.main.async {
                self.listPreviewCovers[listId] = Array(parsed.coverIds.prefix(4))
            }
            return
        }
        if !parsed.fallbackGameIds.isEmpty {
            self.fetchFallbackCovers(for: parsed.fallbackGameIds, take: 4) { imgs in
                DispatchQueue.main.async {
                    self.listPreviewCovers[listId] = imgs
                }
            }
            return
        }
        DispatchQueue.main.async {
            self.listPreviewCovers[listId] = []
        }
    }

    /// Extract image ids and fallback game IDs.
    private func extractCoverIdsAndFallbackGameIds(from docs: [QueryDocumentSnapshot]) -> (coverIds: [String], fallbackGameIds: [Int]) {
        var coverIds: [String] = []
        var fallbackIds: [Int] = []

        for d in docs {
            let data = d.data()

            if let cov = data["cover"] as? [String: Any],
               let img = cov["image_id"] as? String, !img.isEmpty {
                coverIds.append(img); continue
            }
            if let img = data["cover_image_id"] as? String, !img.isEmpty {
                coverIds.append(img); continue
            }
            if let img = data["image_id"] as? String, !img.isEmpty {
                coverIds.append(img); continue
            }
            if let gid = data["game_id"] as? Int { fallbackIds.append(gid); continue }
            if let gid = data["gameId"] as? Int { fallbackIds.append(gid); continue }
        }
        return (coverIds, fallbackIds)
    }

    private func fetchFallbackCovers(for gameIds: [Int], take: Int, completion: @escaping ([String]) -> Void) {
        guard !gameIds.isEmpty else { completion([]); return }
        let unique = Array(Set(gameIds))
        let slice = Array(unique.prefix(max(take * 2, take)))
        let group = DispatchGroup()
        var fetched: [String] = []

        for gid in slice {
            group.enter()
            igdb.fetchGameById(id: gid) { result in
                if case .success(let g) = result, let id = g.cover?.imageId {
                    fetched.append(id)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(Array(fetched.prefix(take)))
        }
    }

    private func gameFromDict(_ dict: [String: Any]) -> Game? {
        let idVal = dict["id"] as? Int ?? (dict["id"] as? NSNumber)?.intValue
        guard let id = idVal else { return nil }
        let name = (dict["name"] as? String) ?? "Loading…"
        let coverId = dict["cover_id"] as? String
        let cover = coverId.map { Game.Cover(id: nil, imageId: $0) }
        return Game(
            id: id,
            name: name,
            cover: cover,
            firstReleaseDate: nil,
            genres: nil,
            platforms: nil,
            rating: nil,
            ratingCount: nil,
            totalRatingCount: nil,
            screenshots: nil
        )
    }

    // MARK: - Parser

    static func parseGameLog(docIdFallback: String, data: [String: Any]) -> GameLog? {
        guard
            let userId = data["user_id"] as? String,
            let gameId = data["game_id"] as? Int,
            let statusRaw = data["status"] as? String,
            let playDate = data["play_date"] as? Timestamp
        else { return nil }
        let status = GameStatus(rawValue: statusRaw) ?? .inProgress
        let rating = data["rating"] as? Double
        let review = data["review"] as? String
        let isLiked = data["is_liked"] as? Bool ?? false
        var cover: Game.Cover? = nil
        if let coverDict = data["cover"] as? [String: Any],
           let imageId = coverDict["image_id"] as? String {
            cover = Game.Cover(id: coverDict["id"] as? Int, imageId: imageId)
        }
        let gameName = (data["game_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GameLog(
            id: (data["id"] as? String) ?? docIdFallback,
            userId: userId, gameId: gameId, gameName: gameName?.isEmpty == true ? nil : gameName,
            status: status, playDate: playDate,
            rating: rating, review: review, isLiked: isLiked, cover: cover
        )
    }

    // MARK: - Adapter (UserListLite → UserList)

    private func convertToUserList(_ lite: UserListLite) -> UserList {
        let nowTs = Timestamp(date: Date())
        let updated = lite.updatedAt ?? nowTs
        let created = nowTs

        let listType = mapListType(from: lite.type)
        let defaultTierLabels = ["S", "A", "B", "C", "D"]
        let defaultTierColors = ["#E74C3C", "#E67E22", "#F1C40F", "#2ECC71", "#3498DB"]
        let tierLabels = (listType == .tiered) ? (lite.tierLabels ?? defaultTierLabels) : []
        let tierColors = (listType == .tiered) ? (lite.tierColors ?? defaultTierColors) : []

        return UserList(
            id: lite.id,
            ownerId: userId,
            title: lite.title,
            description: "",
            type: listType,
            isPublic: lite.isPublic,
            createdAt: created,
            updatedAt: updated,
            itemCount: lite.itemCount,
            tierLabels: tierLabels,
            tierColors: tierColors
        )
    }

    private func mapListType(from raw: String) -> ListType {
        switch raw.lowercased() {
        case "tiered": return .tiered
        case "ranked": return .ranked
        default:       return .regular
        }
    }

    private func gameToDict(_ game: Game) -> [String: Any] {
        var dict: [String: Any] = ["id": game.id, "name": game.name]
        if let img = game.cover?.imageId { dict["cover_id"] = img }
        return dict
    }

    // MARK: - Saved Games + Drag to List

    private func removeFromSavedGames(_ game: Game) {
        watchlist.removeAll { $0.id == game.id }
        guard let uid = Auth.auth().currentUser?.uid, uid == userId else { return }
        let payload = ["watchlist_games": watchlist.map { gameToDict($0) }]
        db.collection("users").document(uid).setData(payload, merge: true)
    }

    private func handleDrop(providers: [NSItemProvider], onto list: UserListLite) -> Bool {
        guard isMe else { return false }
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                let text = (item as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? (item as? String)
                guard let idStr = text, let gameId = Int(idStr) else { return }
                if let game = watchlist.first(where: { $0.id == gameId }) {
                    addGameToListFromDrag(list: list, game: game)
                }
            }
            return true
        }
        return false
    }

    private func addGameToListFromDrag(list: UserListLite, game: Game) {
        let listType = mapListType(from: list.type)
        let base = UserListItem(
            id: UUID().uuidString,
            listId: list.id,
            gameId: game.id,
            gameName: game.name,
            coverImageId: game.cover?.imageId,
            releaseYear: game.computedReleaseYear,
            order: nil,
            tier: nil,
            addedAt: Date()
        )

        let toastName = list.title
        func showToast() {
            withAnimation(.easeInOut(duration: 0.2)) {
                dragToast = "Added to \(toastName)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    dragToast = nil
                }
            }
        }

        switch listType {
        case .regular:
            ListsService.shared.addItems(listId: list.id, items: [base])
            updatePreviewCoversAfterDragAdd(listId: list.id, coverId: game.cover?.imageId)
            showToast()
        case .ranked, .tiered:
            fetchNextOrder(for: list.id) { next in
                var item = base
                item.order = next
                ListsService.shared.addItems(listId: list.id, items: [item])
                updatePreviewCoversAfterDragAdd(listId: list.id, coverId: game.cover?.imageId)
                showToast()
            }
        }
    }

    private func updatePreviewCoversAfterDragAdd(listId: String, coverId: String?) {
        guard let coverId, !coverId.isEmpty else { return }
        var current = listPreviewCovers[listId] ?? []
        if current.contains(coverId) { return }
        if current.count < 4 {
            current.append(coverId)
            listPreviewCovers[listId] = current
        }
    }

    private func fetchNextOrder(for listId: String, completion: @escaping (Int) -> Void) {
        db.collection("lists").document(listId)
            .collection("items")
            .order(by: "order", descending: true)
            .limit(to: 1)
            .getDocuments { snap, _ in
                let maxOrder: Int
                if let data = snap?.documents.first?.data(),
                   let val = data["order"] as? Int {
                    maxOrder = val
                } else if let data = snap?.documents.first?.data(),
                          let val = data["order"] as? NSNumber {
                    maxOrder = val.intValue
                } else {
                    maxOrder = -1
                }
                completion(maxOrder + 1)
            }
    }
}

// MARK: - Section Header (plain)

private struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundColor(ColorTheme.text)
            Spacer()
        }
    }
}

// MARK: - List Rectangle Card

private struct ListRectangleCard: View {
    let list: ProfileView.UserListLite
    let previewImageIds: [String]
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let previewSide: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    privacyCorner(isPublic: list.isPublic)
                        .padding(8)
                }

            HStack(spacing: 10) {
                // Left: preview area
                VStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        HStack(spacing: 6) { previewCell(0); previewCell(1) }
                        HStack(spacing: 6) { previewCell(2); previewCell(3) }
                    }
                    .padding(.vertical, 4)
                    .frame(width: previewSide, height: previewSide)
                    Spacer(minLength: 0)
                }
                .frame(width: previewSide)

                // Right: details
                VStack(alignment: .leading, spacing: 6) {
                    Text(list.title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)
                    Spacer(minLength: 2)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    listTypeChip(list.type)
                    Text("\(list.itemCount) \(list.itemCount == 1 ? "game" : "games")")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                }
                .padding(10)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder
    private func previewCell(_ idx: Int) -> some View {
        let w: CGFloat = 56
        let h: CGFloat = 75
        if idx < previewImageIds.count {
            GameCoverImage(id: previewImageIds[idx], preset: .small, cornerRadius: 8)
                .frame(width: w, height: h)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorTheme.separator.opacity(0.2))
                .frame(width: w, height: h)
                .overlay(
                    Group {
                        if list.type.lowercased() == "tiered" {
                            tierPreviewBadge()
                        } else {
                            Image(systemName: symbolForType(list.type))
                                .foregroundColor(ColorTheme.subtext)
                        }
                    }
                )
        }
    }

    private func listTypeChip(_ raw: String) -> some View {
        let name: String
        switch raw.lowercased() {
        case "tiered": name = "Tiered"
        case "ranked": name = "Ranked"
        default:       name = "Regular"
        }
        return Text(name)
            .font(.caption.weight(.semibold))
            .foregroundColor(ColorTheme.accent)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private func privacyCorner(isPublic: Bool) -> some View {
        let icon = isPublic ? "globe" : "lock.fill"
        return Image(systemName: icon)
            .font(.caption2.weight(.semibold))
            .foregroundColor(isPublic ? ColorTheme.subtext : ColorTheme.highlight)
            .padding(6)
            .background(Circle().fill(ColorTheme.surface))
            .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
    }

    private func symbolForType(_ raw: String) -> String {
        switch raw.lowercased() {
        case "tiered": return "square.grid.2x2"
        case "ranked": return "list.number"
        default:       return "list.bullet"
        }
    }

    private func tierPreviewBadge() -> some View {
        let labels = (list.tierLabels ?? ["S", "A", "B"]).prefix(3)
        let colors = (list.tierColors ?? ["#E74C3C","#E67E22","#F1C40F"]).prefix(3)
        return VStack(spacing: 3) {
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorFromHex(Array(colors)[min(idx, colors.count - 1)]))
                        .frame(width: 10, height: 10)
                    Text(label.isEmpty ? "T\(idx+1)" : label)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(ColorTheme.subtext)
                }
            }
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var v = trimmed
        if v.hasPrefix("#") { v.removeFirst() }
        guard v.count == 6, let num = Int(v, radix: 16) else {
            return ColorTheme.separator
        }
        let r = Double((num >> 16) & 0xFF) / 255.0
        let g = Double((num >> 8) & 0xFF) / 255.0
        let b = Double(num & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Recent Log Row Card

private struct RecentLogRowCard: View {
    let log: GameLog
    let title: String
    let avg: Double?
    let count: Int

    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 120
    private let coverCorner: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))

            HStack(spacing: 10) {
                if let imgId = log.cover?.imageId {
                    GameCoverImage(id: imgId, preset: .medium, cornerRadius: coverCorner)
                        .frame(width: 84, height: 112)
                } else {
                    RoundedRectangle(cornerRadius: coverCorner)
                        .fill(ColorTheme.separator.opacity(0.25))
                        .frame(width: 84, height: 112)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)

                    if let review = log.review, !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("“\(review)”")
                            .font(.caption)
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(2)
                    }

                    if let r = log.rating, r > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(ColorTheme.highlight)
                                .font(.caption)
                            Text(String(format: "%.1f", r))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundColor(ColorTheme.highlight)
                            Text("your rating")
                                .font(.caption2)
                                .foregroundColor(ColorTheme.subtext)
                        }
                    }

                    Spacer(minLength: 2)

                    CompactGamerLndBadge(avg: avg, count: count)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

// MARK: - Compact GamerLnd Badge (reused)

private struct CompactGamerLndBadge: View {
    let avg: Double?
    let count: Int
    var body: some View {
        Group {
            if let avg = avg, count > 0 {
                HStack(spacing: 6) {
                    Image("icon")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    Image(systemName: "heart.fill").foregroundColor(ColorTheme.highlight)
                    Text(String(format: "%.1f", avg))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.highlight)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ColorTheme.separator, lineWidth: 1))
            } else {
                HStack(spacing: 6) {
                    Image("icon")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    Text("Be the first to rate!")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ColorTheme.separator, lineWidth: 1))
            }
        }
    }
}

// MARK: - New List Sheet

private struct NewListSheet: View {
    let ownerId: String
    var onCreated: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var listTypeRaw: String = "regular" // regular / ranked / tiered
    @State private var isPublic: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorText: String = ""

    private let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description)
                }

                Section(header: Text("Type")) {
                    Picker("List Type", selection: $listTypeRaw) {
                        Text("Regular").tag("regular")
                        Text("Ranked").tag("ranked")
                        Text("Tiered").tag("tiered")
                    }
                    .pickerStyle(.segmented)
                }

                Section { Toggle("Public", isOn: $isPublic) }

                if !errorText.isEmpty {
                    Section { Text(errorText).foregroundColor(.red).font(.footnote) }
                }
            }
            .navigationBarTitle("New List", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Text("Create").bold() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { AppIconCentered() } }
    }

    private func save() {
        errorText = ""
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        let id = UUID().uuidString
        let now = Timestamp(date: Date())

        var payload: [String: Any] = [
            "id": id,
            "owner_id": ownerId,
            "title": trimmed,
            "description": description,
            "type": listTypeRaw,
            "is_public": isPublic,
            "item_count": 0,
            "created_at": now,
            "updated_at": now
        ]

        if listTypeRaw == "tiered" {
            payload["tier_labels"] = ["S", "A", "B", "C", "D"]
            payload["tier_colors"] = ["", "", "", "", ""]
        } else {
            payload["tier_labels"] = []
            payload["tier_colors"] = []
        }

        db.collection("lists").document(id).setData(payload) { err in
            isSaving = false
            if let err = err {
                errorText = err.localizedDescription
                return
            }
            AnalyticsService.shared.trackListUpdated(listId: id, type: listTypeRaw, itemCount: 0)
            onCreated()
            dismiss()
        }
    }
}

// MARK: - Edit Profile Sheet (+ Reorder Sections, live username check, PhotosPicker)

private struct ProfileEditSheet: View {
    let userId: String
    let currentDisplayName: String
    let currentUsername: String
    let currentBio: String
    let currentAvatarUrl: String?

    @Binding var sectionsOrder: [ProfileView.SectionKind]

    var onSaved: (_ newDisplayName: String, _ newUsername: String, _ newBio: String, _ newAvatarUrl: String?) -> Void
    var onReorderSaved: (_ newOrder: [ProfileView.SectionKind]) -> Void

    @Environment(\.dismiss) private var dismiss

    // Editable fields
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var avatarUrl: String? = nil

    // PhotosPicker
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImageData: Data? = nil

    // Save/validation state
    @State private var isSaving: Bool = false
    @State private var errorText: String = ""
    @State private var usernameAvailable: Bool? = nil
    @State private var usernameCheckTask: DispatchWorkItem? = nil

    private let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile")) {
                    TextField("Display Name", text: $displayName)

                    HStack {
                        TextField("Username (unique)", text: $username)
                            .textInputAutocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: username) { _, _ in
                                usernameAvailable = nil
                                debounceUsernameCheck()
                            }

                        if let available = usernameAvailable {
                            Image(systemName: available ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundColor(available ? .green : .red)
                        }
                    }

                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...5)

                    // Profile Image (PhotosPicker)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile Image")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            if let data = pickedImageData, let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                            } else if let url = avatarUrl, !url.isEmpty, let imgURL = URL(string: url) {
                                AsyncImage(url: imgURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        Image(systemName: "person.crop.circle.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .padding(8)
                                            .foregroundColor(ColorTheme.subtext)
                                    default:
                                        ProgressView()
                                    }
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 64, height: 64)
                                    .foregroundColor(ColorTheme.subtext)
                            }

                            Spacer()
                        }
                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text(pickedImageData == nil ? "Choose Image" : "Change Image")
                                Spacer()
                            }
                        }
                        .onChange(of: pickedItem) { _, newItem in
                            guard let item = newItem else { pickedImageData = nil; return }
                            Task {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    await MainActor.run {
                                        pickedImageData = data
                                    }
                                }
                            }
                        }
                    }
                }

                if !errorText.isEmpty {
                    Section { Text(errorText).foregroundColor(.red).font(.footnote) }
                }
            }
            .navigationBarTitle("Edit Profile", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save").bold() }
                    }
                    .disabled(isSaving
                              || displayName.trimmingCharacters(in: .whitespaces).isEmpty
                              || username.trimmingCharacters(in: .whitespaces).isEmpty
                              || usernameAvailable == false)
                }
            }
            .onAppear {
                displayName = currentDisplayName
                username = currentUsername
                bio = currentBio
                avatarUrl = currentAvatarUrl
                // seed availability as true for the current username
                usernameAvailable = true
            }
        }
    }

    private func debounceUsernameCheck() {
        usernameCheckTask?.cancel()
        let task = DispatchWorkItem { checkUsername() }
        usernameCheckTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func checkUsername() {
        let uname = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !uname.isEmpty else { usernameAvailable = nil; return }
        db.collection("users")
            .whereField("username_lower", isEqualTo: uname)
            .limit(to: 1)
            .getDocuments { snap, _ in
                // available if no doc, OR the only doc is this user
                let takenByOther = snap?.documents.first(where: { ($0.data()["id"] as? String) != userId }) != nil
                usernameAvailable = !takenByOther
            }
    }

    private func save() {
        isSaving = true
        errorText = ""

        let disp = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let uname = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let bioStored = bio

        func finish(with newAvatarUrl: String?) {
            var payload: [String: Any] = [
                "display_name": disp,
                "display_name_lower": disp.lowercased(),
                "username": uname,
                "username_lower": uname.lowercased(),
                "bio": bioStored,
                "search_prefix": UserProfile.searchPrefixes(username: disp, handle: uname)
            ]
            if let url = newAvatarUrl { payload["avatar_url"] = url }

            db.collection("users").document(userId).setData(payload, merge: true) { err in
                isSaving = false
                if let err = err {
                    errorText = err.localizedDescription
                    return
                }
                onSaved(disp, uname, bioStored, newAvatarUrl ?? avatarUrl)
                Haptics.success()
                dismiss()
            }
        }

        // If a new image was selected, upload to Firebase Storage first.
        if let data = pickedImageData {
            uploadProfileImage(userId: userId, data: data) { url, err in
                if let err = err {
                    self.isSaving = false
                    self.errorText = err.localizedDescription
                    return
                }
                finish(with: url)
            }
        } else {
            finish(with: nil)
        }
    }

    private func uploadProfileImage(userId: String, data: Data, completion: @escaping (String?, Error?) -> Void) {
        // Try to compress to JPEG to keep size reasonable
        var uploadData = data
        var contentType = "image/jpeg"
        if let ui = UIImage(data: data), let jpeg = ui.jpegData(compressionQuality: 0.9) {
            uploadData = jpeg
            contentType = "image/jpeg"
        } else {
            contentType = "image/*"
        }

        let ref = Storage.storage().reference().child("avatars/\(userId).jpg")
        let meta = StorageMetadata()
        meta.contentType = contentType
        ref.putData(uploadData, metadata: meta) { meta, err in
            if let err = err { completion(nil, err); return }
            let resolvedRef: StorageReference = ref
            func fetchURL(retries: Int) {
                resolvedRef.downloadURL { url, err in
                    if let url = url {
                        completion(url.absoluteString, nil)
                        return
                    }
                    if retries > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            fetchURL(retries: retries - 1)
                        }
                    } else {
                        completion(nil, err)
                    }
                }
            }
            fetchURL(retries: 2)
        }
    }
}

// MARK: - Reorder Sections View

private struct ReorderSectionsView: View {
    @Binding var order: [ProfileView.SectionKind]
    var onSave: (_ newOrder: [ProfileView.SectionKind]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var local: [ProfileView.SectionKind] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reorder Sections")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                Button("Save") {
                    onSave(local)
                    dismiss()
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(ColorTheme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            List {
                ForEach(local) { item in
                    Text(item.rawValue)
                }
                .onMove { indices, newOffset in
                    local.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        .onAppear { local = order }
    }
}

// MARK: - User Logs List (simple overlay)

private struct UserLogsListView: View {
    let userId: String
    let logs: [GameLog]
    let gameNames: [Int: String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logged Games")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(logs, id: \.id) { log in
                        let title = gameNames[log.gameId] ?? log.gameName ?? "Loading…"
                        NavigationLink(
                            destination: GameLogDetailView(
                                gameLog: log,
                                gameName: title,
                                authorUsernameOverride: nil,
                                focusCommentOnAppear: false
                            )
                        ) {
                            HStack(spacing: 10) {
                                if let img = log.cover?.imageId {
                                    GameCoverImage(id: img, preset: .small, cornerRadius: 8)
                                        .frame(width: 56, height: 75)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(ColorTheme.separator.opacity(0.25))
                                        .frame(width: 56, height: 75)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(ColorTheme.text)
                                        .lineLimit(2)
                                    if let r = log.rating, r > 0 {
                                        HStack(spacing: 6) {
                                            Image(systemName: "heart.fill")
                                                .foregroundColor(ColorTheme.highlight)
                                                .font(.caption)
                                            Text(String(format: "%.1f", r))
                                                .font(.caption.monospacedDigit().weight(.semibold))
                                                .foregroundColor(ColorTheme.highlight)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Stats Sheet (Average rating rounded to 1 decimal + keyboard-aware search)

private struct StatsSheet: View {
    let userId: String
    let followers: Int
    let following: Int
    let recentLogs: [GameLog]
    let avgCache: [Int: (avg: Double?, count: Int)]
    let isOwner: Bool
    let favoriteGame: Game?
    let watchlist: [Game]
    let favoritePlayStyle: String
    let favoritePlatform: String
    let favoriteGenre: String
    let favoriteFranchise: String
    let onSaved: (_ favorite: Game?, _ watchlist: [Game], _ playStyle: String, _ platform: String, _ genre: String, _ franchise: String) -> Void

    @Environment(\.dismiss) private var dismiss

    // Derived metrics
    @State private var avgUserRating: Double? = nil
    @State private var totalLogs: Int = 0
    @State private var totalReviews: Int = 0
    @State private var totalComments: Int = 0
    @State private var totalLikesReceived: Int = 0

    // Favorites / Watchlist
    @State private var favoriteGameState: Game? = nil
    @State private var watchlistState: [Game] = []
    @State private var favoritePlayStyleState: String = ""
    @State private var favoritePlatformState: String = ""
    @State private var favoriteGenreState: String = ""
    @State private var favoriteFranchiseState: String = ""

    @State private var favoriteSearchText: String = ""
    @State private var favoriteSearchResults: [Game] = []
    @State private var isSearchingFav: Bool = false

    @State private var watchlistSearchText: String = ""
    @State private var watchlistSearchResults: [Game] = []
    @State private var isSearchingWatchlist: Bool = false

    @State private var consoleSearchText: String = ""
    @State private var showStatsGraphs: Bool = false

    // Keyboard padding
    @StateObject private var kb = KeyboardState()

    private let db = Firestore.firestore()
    private let igdb = IGDBService()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Stats")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                            Spacer()
                            Button(showStatsGraphs ? "Numbers" : "Graphs") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showStatsGraphs.toggle()
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.accent)
                        }

                        if showStatsGraphs {
                            statsGraphPanel
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                statPill(label: "Followers", value: "\(followers)")
                                statPill(label: "Following", value: "\(following)")
                                statPill(label: "Logged Games", value: "\(totalLogs)")
                                statPill(label: "Reviews", value: "\(totalReviews)")
                                statPill(label: "Likes Received", value: "\(totalLikesReceived)")
                                let avgTxt = avgUserRating.map { String(format: "%.1f", $0) } ?? "—"
                                statPill(label: "Avg Rating", value: avgTxt)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    sectionCard("Favorite Game") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Favorite Game")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(ColorTheme.text)

                            if let fav = favoriteGameState {
                                HStack(spacing: 10) {
                                    if let img = fav.cover?.imageId {
                                        GameCoverImage(id: img, preset: .small, cornerRadius: 8).frame(width: 56, height: 75)
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(ColorTheme.separator.opacity(0.25))
                                            .frame(width: 56, height: 75)
                                    }
                                    Text(fav.name)
                                        .foregroundColor(ColorTheme.text)
                                        .lineLimit(2)
                                    Spacer()
                                    if isOwner {
                                        Button(role: .destructive) { favoriteGameState = nil } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                            } else {
                                Text(isOwner ? "Search and pick a favorite game." : "No favorite selected yet.")
                                    .font(.footnote)
                                    .foregroundColor(ColorTheme.subtext)
                            }

                            if isOwner {
                                HStack(spacing: 8) {
                                    TextField("Search games…", text: $favoriteSearchText, onCommit: { runSearch(target: .favorite) })
                                        .textInputAutocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))

                                    Button {
                                        favoriteSearchText = ""
                                        favoriteSearchResults = []
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(ColorTheme.subtext)
                                    }
                                    .opacity(favoriteSearchText.isEmpty ? 0 : 1)
                                }
                            }

                            if isOwner {
                                searchResultsList(results: favoriteSearchResults, isLoading: isSearchingFav) { g in
                                    favoriteGameState = g
                                    favoriteSearchText = ""
                                    favoriteSearchResults = []
                                    hideKeyboard()
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, kb.height + 24)
                .animation(.easeOut(duration: 0.22), value: kb.height)
            }
            .navigationTitle("More Stats")
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        hideKeyboard()
                        saveProfileExtras()
                    }
                }
            }
            .onAppear {
                computeBasics()
                fetchAggregates()
                seedInitialValues()
            }
        }
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline.monospacedDigit().weight(.semibold)).foregroundColor(ColorTheme.text)
            Text(label).font(.caption).foregroundColor(ColorTheme.subtext)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private var statsGraphPanel: some View {
        let items: [(String, Double)] = [
            ("Followers", Double(followers)),
            ("Following", Double(following)),
            ("Logged", Double(totalLogs)),
            ("Reviews", Double(totalReviews)),
            ("Likes", Double(totalLikesReceived)),
            ("Avg Rating", avgUserRating ?? 0)
        ]
        let maxVal = max(items.map { $0.1 }.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.0)
                            .font(.caption)
                            .foregroundColor(ColorTheme.subtext)
                        Spacer()
                        Text(item.0 == "Avg Rating" ? String(format: "%.1f", item.1) : "\(Int(item.1))")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                    }
                    GeometryReader { geo in
                        let width = geo.size.width * CGFloat(item.1 / maxVal)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ColorTheme.accent)
                            .frame(width: max(6, width), height: 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.surface))
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
            }
        }
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(ColorTheme.text)
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func searchResultsList(results: [Game], isLoading: Bool, onSelect: @escaping (Game) -> Void) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(results, id: \.id) { g in
                Button {
                    onSelect(g)
                } label: {
                    HStack(spacing: 10) {
                        if let img = g.cover?.imageId {
                            GameCoverImage(id: img, preset: .small, cornerRadius: 8).frame(width: 56, height: 75)
                        } else {
                            RoundedRectangle(cornerRadius: 8).fill(ColorTheme.separator.opacity(0.25)).frame(width: 56, height: 75)
                        }
                        Text(g.name).foregroundColor(ColorTheme.text).lineLimit(2)
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if isLoading {
                ProgressView().tint(ColorTheme.accent).padding(.top, 6)
            }
        }
    }

    private func seedInitialValues() {
        favoriteGameState = favoriteGame
        watchlistState = watchlist
        favoritePlayStyleState = favoritePlayStyle
        favoritePlatformState = favoritePlatform
        favoriteGenreState = favoriteGenre
        favoriteFranchiseState = favoriteFranchise
    }

    private func computeBasics() {
        totalLogs = recentLogs.count
        totalReviews = recentLogs.reduce(0) { acc, log in
            if let t = log.review, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return acc + 1 }
            return acc
        }
        let ratings = recentLogs.compactMap { $0.rating }
        if !ratings.isEmpty {
            avgUserRating = ratings.reduce(0, +) / Double(ratings.count)
        }
    }

    private func fetchAggregates() {
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: userId)
            .limit(to: 1000)
            .getDocuments { snap, _ in
                let ids = (snap?.documents ?? []).map { ($0.data()["id"] as? String) ?? $0.documentID }
                self.totalLogs = (snap?.documents.count ?? self.totalLogs)

                let ratings = (snap?.documents ?? []).compactMap { $0.data()["rating"] as? Double }
                if !ratings.isEmpty {
                    self.avgUserRating = ratings.reduce(0, +) / Double(ratings.count)
                }

                let group = DispatchGroup()
                var likes = 0
                var comments = 0

                for logId in ids.prefix(300) {
                    group.enter()
                    db.collection("review_likes").whereField("log_id", isEqualTo: logId).getDocuments { s, _ in
                        likes += (s?.documents.count ?? 0)
                        group.leave()
                    }
                    group.enter()
                    db.collection("review_comments").whereField("log_id", isEqualTo: logId).getDocuments { s, _ in
                        comments += (s?.documents.count ?? 0)
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    self.totalLikesReceived = likes
                    self.totalComments = comments
                }
            }
    }

    private enum SearchTarget { case favorite, watchlist }

    private func runSearch(target: SearchTarget) {
        let query = (target == .favorite ? favoriteSearchText : watchlistSearchText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if target == .favorite { isSearchingFav = true }
        else { isSearchingWatchlist = true }

        igdb.searchGames(query: query, year: nil, genre: nil) { result in
            DispatchQueue.main.async {
                let games = (try? result.get()) ?? []
                if target == .favorite {
                    favoriteSearchResults = games
                    isSearchingFav = false
                } else {
                    watchlistSearchResults = games
                    isSearchingWatchlist = false
                }
            }
        }
    }

    private func saveProfileExtras() {
        let playStyle = favoritePlayStyleState.trimmingCharacters(in: .whitespacesAndNewlines)
        let platform = favoritePlatformState.trimmingCharacters(in: .whitespacesAndNewlines)
        let genre = favoriteGenreState.trimmingCharacters(in: .whitespacesAndNewlines)
        let franchise = favoriteFranchiseState.trimmingCharacters(in: .whitespacesAndNewlines)

        var payload: [String: Any] = [
            "watchlist_games": watchlistState.map { gameToDict($0) },
            "favorite_play_style": playStyle,
            "favorite_platform": platform,
            "favorite_genre": genre,
            "favorite_franchise": franchise
        ]
        if let fav = favoriteGameState {
            payload["favorite_game"] = gameToDict(fav)
        } else {
            payload["favorite_game"] = FieldValue.delete()
        }

        guard isOwner else {
            onSaved(favoriteGameState, watchlistState, playStyle, platform, genre, franchise)
            dismiss()
            return
        }

        db.collection("users").document(userId).setData(payload, merge: true) { _ in
            onSaved(favoriteGameState, watchlistState, playStyle, platform, genre, franchise)
            dismiss()
        }
    }

    private func gameToDict(_ game: Game) -> [String: Any] {
        var dict: [String: Any] = ["id": game.id, "name": game.name]
        if let img = game.cover?.imageId { dict["cover_id"] = img }
        return dict
    }

}

// MARK: - Keyboard helpers

private final class KeyboardState: ObservableObject {
    @Published var height: CGFloat = 0

    private var willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
    private var willHide   = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
    private var cancellables = Set<AnyCancellable>()

    init() {
        willChange.merge(with: willHide).sink { note in
            guard let userInfo = note.userInfo,
                  let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
                self.height = 0
                return
            }
            let screen = UIScreen.main.bounds
            let overlap = max(0, screen.height - endFrame.origin.y)
            self.height = overlap
        }.store(in: &cancellables)
    }
}

private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
