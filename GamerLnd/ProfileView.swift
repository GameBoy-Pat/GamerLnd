// ProfileView.swift
// User profile with refined header, live username availability check,
// PhotosPicker-based profile image, tighter header spacing, keyboard-aware stats sheet,
// section reordering, and no-flicker loads.

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import os.log
import Combine

struct ProfileView: View {
    private struct SnapshotCache {
        var followers: Int
        var following: Int
        var avgUserRating: Double?
        var avgUserRatingCount: Int
        var rewardXP: Int
        var displayedRewardXP: Int
        var rewardThemeRaw: String
        var recentLogs: [GameLog]
        var dailyObjectives: ObjectiveAssignment?
        var weeklyObjectives: ObjectiveAssignment?
        var achievementStates: [String: UserAchievementState]
        var achievementCatalog: [AchievementDefinition]
        var secretCatalog: [SecretUnlockDefinition]
        var discoveredSecrets: [UserSecretUnlockState]
        var nextHintSecret: SecretUnlockDefinition?
    }

    private static var snapshotCache: [String: SnapshotCache] = [:]

    let userId: String

    // User (lite)
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var avatarUrl: String? = nil
    @State private var youtubeURL: String = ""
    @State private var twitchURL: String = ""
    @State private var tiktokURL: String = ""

    // Follow stats
    @State private var followers: Int = 0
    @State private var following: Int = 0
    @State private var avgUserRating: Double? = nil
    @State private var avgUserRatingCount: Int = 0
    @State private var rewardXP: Int = 0
    @State private var displayedRewardXP: Int = 0
    @State private var rewardTheme: RewardService.Theme = .xp
    @State private var isTrustedGamer: Bool = false
    @State private var isFounder: Bool = false
    @State private var isUpdatingTrusted: Bool = false
    @State private var showTrustedConfirm: Bool = false
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
        let tierTextColors: [String]?
    }
    @State private var lists: [UserListLite] = []
    @State private var listPreviewCovers: [String: [String]] = [:]  // listId → [imageIds up to 4]
    @State private var isLoadingLists: Bool = false
    @State private var pinnedListIds: Set<String> = []
    @State private var isUpdatingPinnedLists: Set<String> = []

    // Favorites / Watchlist
    @State private var favoriteGame: Game? = nil
    @State private var watchlist: [Game] = []
    @State private var watchlistAddedAt: [Int: Date] = [:]
    @State private var hasLoadedSavedSection: Bool = false
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
    @State private var createdListNavigationTarget: UserList? = nil
    @State private var showCreatedListNavigation: Bool = false
    @State private var showEditProfile: Bool = false
    @State private var showStats: Bool = false
    @State private var showFollowersSheet: Bool = false
    @State private var showFollowingSheet: Bool = false
    @State private var activeLogListMode: LogListMode? = nil
    @State private var showDraftsSheet: Bool = false
    @State private var showRewardHistoryOverlay: Bool = false
    @State private var showResetGamificationConfirm: Bool = false
    @State private var dragToast: String? = nil
    @State private var showSectionInfoOverlay: Bool = false
    @State private var sectionInfoTitle: String = ""
    @State private var sectionInfoText: String = ""
    @State private var sectionInfoSystemImage: String = "info.circle"
    @State private var sectionInfoAssetName: String? = nil
    @State private var isEditingSavedGames: Bool = false
    @State private var isEditingReferences: Bool = false
    @State private var references: [LogReferenceEntry] = []
    @State private var hasLoadedReferencesSection: Bool = false
    @State private var savedGamesSort: SavedGamesSort = .recent
    @State private var rewardEvents: [(id: String, type: String, delta: Int, at: Date)] = []
    @State private var headerCompact: Bool = true
    @State private var dailyObjectives: ObjectiveAssignment? = nil
    @State private var weeklyObjectives: ObjectiveAssignment? = nil
    @State private var achievementStates: [String: UserAchievementState] = [:]
    @State private var achievementCatalog: [AchievementDefinition] = []
    @State private var secretCatalog: [SecretUnlockDefinition] = []
    @State private var discoveredSecrets: [UserSecretUnlockState] = []
    @State private var nextHintSecret: SecretUnlockDefinition? = nil
    @State private var showAchievementBoardOverlay: Bool = false
    @State private var selectedAchievementTile: AchievementDefinition? = nil
    @State private var showSecretHintOverlay: Bool = false
    @State private var showSecretQuestListOverlay: Bool = false
    @State private var showTileInfoOverlay: Bool = false
    @State private var showQuestBoardInfoOverlay: Bool = false
    @State private var claimingObjectiveIDs: Set<String> = []
    @State private var claimingQuestIDs: Set<String> = []
    @State private var claimingSecretIDs: Set<String> = []
    @State private var rewardDeltaToast: String? = nil
    @State private var rewardDeltaToastIcon: String = "sparkles"
    @State private var hasLoadedRecentSection: Bool = false
    @State private var hasLoadedListsSection: Bool = false
    @State private var isAnimatingRewardXP: Bool = false
    @State private var pendingRewardAnimationTotal: Int? = nil
    @State private var pendingRewardAnimationDelta: Int = 0
    @State private var recentOptimisticRewardSignature: String? = nil
    @State private var recentOptimisticRewardAt: Date? = nil
    @State private var rewardsPageSelection: Int? = 0
    @AppStorage("hasSeenQuestBoardIntro") private var hasSeenQuestBoardIntro: Bool = false
    @State private var showQuestBoardIntroAlert: Bool = false

    private enum LogListMode {
        case logged
        case reviews
    }

    // Reorder sections
    enum SectionKind: String, CaseIterable, Identifiable {
        case rewards = "Rewards"
        case saved = "Saved Games"
        case references = "References"
        case lists = "Lists"
        case recent = "Recently Logged"
        var id: String { rawValue }

        var tabTitle: String {
            switch self {
            case .rewards: return ""
            case .saved: return "Saved"
            case .references: return "Refs"
            case .lists: return "Lists"
            case .recent: return "Logged"
            }
        }
    }
    @State private var sectionsOrder: [SectionKind] = [.rewards, .saved, .references, .lists, .recent]
    @State private var showReorderSections: Bool = false
    @State private var selectedPrimarySection: SectionKind = .rewards

    private enum SavedGamesSort: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case az = "A–Z"
        case za = "Z–A"

        var id: String { rawValue }
    }
    private enum ListsSort: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case az = "A–Z"
        case za = "Z–A"

        var id: String { rawValue }
    }
    private enum ReferencesSort: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case gameAZ = "Game A–Z"
        case creatorAZ = "User A–Z"

        var id: String { rawValue }
    }
    @State private var selectedListFilter: ListDisplayFilter = .all
    @State private var listsSort: ListsSort = .recent
    @State private var referencesSort: ReferencesSort = .recent

    enum ListDisplayFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case standard = "Standard"
        case ranked = "Ranked"
        case tiered = "Tiered"
        var id: String { rawValue }
    }

    // Services
    private let db = Firestore.firestore()
    private let igdb = IGDBService()
    private let founderUID = "H1mDXa3Iv0cGWFb9GNZXVPRYgxf2"

    private var visibleSections: [SectionKind] {
        if isMe { return sectionsOrder }
        return sectionsOrder.filter { $0 == .lists }
    }

    private var filteredLists: [UserListLite] {
        let base: [UserListLite]
        switch selectedListFilter {
        case .all:
            base = lists
        case .standard:
            base = lists.filter { $0.type.lowercased() == "regular" }
        case .ranked:
            base = lists.filter { $0.type.lowercased() == "ranked" }
        case .tiered:
            base = lists.filter { $0.type.lowercased() == "tiered" }
        }

        let sorted: [UserListLite]
        switch listsSort {
        case .recent:
            sorted = base.sorted {
                ($0.updatedAt?.dateValue() ?? .distantPast) > ($1.updatedAt?.dateValue() ?? .distantPast)
            }
        case .az:
            sorted = base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .za:
            sorted = base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
        return sortedPinnedFirst(sorted)
    }

    private func sortedPinnedFirst(_ items: [UserListLite]) -> [UserListLite] {
        let pinned = items.filter { pinnedListIds.contains($0.id) }
        let unpinned = items.filter { !pinnedListIds.contains($0.id) }
        return pinned + unpinned
    }

    private var resolvedDisplayName: String {
        displayName.isEmpty ? " " : displayName
    }

    private var resolvedUsername: String {
        username.isEmpty ? " " : username
    }

    private var creatorLinks: [(label: String, assetName: String, icon: String, color: Color, url: String)] {
        var links: [(String, String, String, Color, String)] = []
        if !youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            links.append(("YouTube", "icon_youtube", "play.rectangle.fill", .red, youtubeURL))
        }
        if !twitchURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            links.append(("Twitch", "icon_twitch", "tv.fill", Color(red: 145/255, green: 70/255, blue: 255/255), twitchURL))
        }
        if !tiktokURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            links.append(("TikTok", "icon_tiktok", "music.note", ColorTheme.accent, tiktokURL))
        }
        return links
    }

    private var profileCacheKey: String {
        "profile.cache.\(userId)"
    }

    private var displayedWatchlist: [Game] {
        switch savedGamesSort {
        case .recent:
            return watchlist.sorted {
                let lhs = watchlistAddedAt[$0.id] ?? .distantPast
                let rhs = watchlistAddedAt[$1.id] ?? .distantPast
                if lhs == rhs {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhs > rhs
            }
        case .az:
            return watchlist.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .za:
            return watchlist.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }
    }

    private var displayedReferences: [LogReferenceEntry] {
        switch referencesSort {
        case .recent:
            return references.sorted { ($0.addedAt?.dateValue() ?? .distantPast) > ($1.addedAt?.dateValue() ?? .distantPast) }
        case .gameAZ:
            return references.sorted { $0.gameName.localizedCaseInsensitiveCompare($1.gameName) == .orderedAscending }
        case .creatorAZ:
            return references.sorted { $0.authorName.localizedCaseInsensitiveCompare($1.authorName) == .orderedAscending }
        }
    }

    var body: some View {
        profileBody
    }

    private var profileBody: some View {
        profilePresentationView
    }

    private var profileBaseView: AnyView {
        AnyView(
            ZStack {
                loadedProfileBody
                profileOverlayLayer
                NavigationLink(
                    isActive: $showCreatedListNavigation,
                    destination: {
                        Group {
                            if let target = createdListNavigationTarget {
                                ListDetailView(list: target, isOwner: true)
                            } else {
                                EmptyView()
                            }
                        }
                    },
                    label: { EmptyView() }
                )
                .hidden()
            }
            .background(ColorTheme.background.ignoresSafeArea())
        )
    }

    private var profileLifecycleView: AnyView {
        let receivedView = profileBaseView
            .navigationTitle("")
            .onAppear(perform: handleProfileAppear)
            .onReceive(NotificationCenter.default.publisher(for: .rewardXPAwarded), perform: handleRewardNotification)
            .onReceive(NotificationCenter.default.publisher(for: .gameLogChanged)) { note in
                guard let changedUserId = note.userInfo?["user_id"] as? String, changedUserId == userId else { return }
                loadRecentLogs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .gamificationUpdated), perform: handleGamificationUpdatedNotification)
            .onReceive(NotificationCenter.default.publisher(for: .openProfileRewardsPage)) { note in
                selectedPrimarySection = .rewards
                if let page = note.userInfo?["page"] as? Int {
                    rewardsPageSelection = page
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .referencesUpdated)) { _ in
                if isMe {
                    loadReferences()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refreshTimeSensitiveProfileData()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                refreshTimeSensitiveProfileData()
            }

        let observedView = receivedView
            .onChange(of: sectionsOrder) { _, _ in handleSectionsOrderChange() }
            .onChange(of: selectedPrimarySection) { _, _ in
                loadSelectedSectionData(force: false)
                playPendingRewardAnimationIfPossible()
                maybeShowQuestBoardIntro()
            }
            .onChange(of: showRewardHistoryOverlay) { _, _ in playPendingRewardAnimationIfPossible() }
            .onChange(of: showAchievementBoardOverlay) { _, _ in
                playPendingRewardAnimationIfPossible()
                postProfileOverlayVisibility()
            }
            .onChange(of: showQuestBoardInfoOverlay) { _, _ in
                postProfileOverlayVisibility()
            }
            .onChange(of: showSecretHintOverlay) { _, _ in playPendingRewardAnimationIfPossible() }
            .onChange(of: showSecretQuestListOverlay) { _, _ in playPendingRewardAnimationIfPossible() }
            .onChange(of: showTileInfoOverlay) { _, _ in playPendingRewardAnimationIfPossible() }
            .onChange(of: isAnyProfileOverlayPresented) { _, _ in postProfileOverlayVisibility() }

        let lifecycleView = observedView
            .alert("Quest Board", isPresented: $showQuestBoardIntroAlert) {
                Button("OK") {
                    hasSeenQuestBoardIntro = true
                }
            } message: {
                Text("The Quest Board lives here in the GamerLnd tab. Tap Open to see the full board and claim XP from completed quests.")
            }
            .onAppear {
                postProfileOverlayVisibility()
                maybeShowQuestBoardIntro()
            }
            .onDisappear {
                NotificationCenter.default.post(
                    name: .profileOverlayVisibilityChanged,
                    object: nil,
                    userInfo: ["is_presented": false]
                )
            }
        return AnyView(lifecycleView)
    }

    private var profilePresentationView: AnyView {
        let settingsWrapped = AnyView(
            profileLifecycleView
                .sheet(isPresented: $showSettingsSheet) {
                    SettingsSheet(
                        isFounder: isFounder,
                        onResetGamification: isFounder ? {
                            showSettingsSheet = false
                            showResetGamificationConfirm = true
                        } : nil,
                        onRevealQuestBoard: isFounder ? {
                            revealQuestBoardForFounder()
                        } : nil,
                        onTriggerTestSecretQuest: isFounder ? {
                            SecretUnlockService.shared.triggerNextTestSecret(userId: userId)
                        } : nil
                    )
                    .preferredColorScheme(ColorTheme.preferredScheme)
                }
        )

        let followWrapped = AnyView(
            settingsWrapped
                .sheet(isPresented: $showFollowersSheet) {
                    NavigationView { FollowListView(userId: userId, mode: .followers) }
                        .preferredColorScheme(ColorTheme.preferredScheme)
                }
                .sheet(isPresented: $showFollowingSheet) {
                    NavigationView { FollowListView(userId: userId, mode: .following) }
                        .preferredColorScheme(ColorTheme.preferredScheme)
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
                        onSaved: { favorite, watchlist, playStyle, platform, genre, franchise in
                            self.favoriteGame = favorite
                            self.watchlist = watchlist
                            self.favoritePlayStyle = playStyle
                            self.favoritePlatform = platform
                            self.favoriteGenre = genre
                            self.favoriteFranchise = franchise
                        }
                    )
                    .preferredColorScheme(ColorTheme.preferredScheme)
                }
        )

        let alertsWrapped = AnyView(
            followWrapped
                .alert("Reset Gamification?", isPresented: $showResetGamificationConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        resetGamificationData()
                    }
                } message: {
                    Text("This clears your XP, challenges, quests, secret quests, and metrics for testing.")
                }
        )

        let draftsWrapped = AnyView(
            alertsWrapped
                .sheet(isPresented: $showDraftsSheet) {
                    DraftsView().preferredColorScheme(ColorTheme.preferredScheme)
                }
                .sheet(isPresented: $showNewListSheet) {
                    ListEditorSheet(ownerId: userId, onCreated: { newList in
                        loadLists()
                        createdListNavigationTarget = newList
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showCreatedListNavigation = true
                        }
                    })
                        .preferredColorScheme(ColorTheme.preferredScheme)
                }
        )

        let editWrapped = AnyView(
            draftsWrapped
                .sheet(isPresented: $showEditProfile) {
                    ProfileEditSheet(
                        userId: userId,
                        currentDisplayName: displayName,
                        currentUsername: username,
                        currentBio: bio,
                        currentAvatarUrl: avatarUrl,
                        currentYouTubeURL: youtubeURL,
                        currentTwitchURL: twitchURL,
                        currentTikTokURL: tiktokURL,
                        sectionsOrder: $sectionsOrder,
                        onSaved: { newDisplayName, newUsername, newBio, newAvatar, newYouTubeURL, newTwitchURL, newTikTokURL in
                            self.displayName = newDisplayName
                            self.username = newUsername
                            self.bio = newBio
                            self.avatarUrl = newAvatar
                            self.youtubeURL = newYouTubeURL
                            self.twitchURL = newTwitchURL
                            self.tiktokURL = newTikTokURL
                        },
                        onReorderSaved: { order in self.sectionsOrder = order }
                    )
                    .preferredColorScheme(ColorTheme.preferredScheme)
                }
        )

        return AnyView(
            editWrapped
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
        )
    }

    @ViewBuilder
    private var profileOverlayLayer: some View {
        if isLoadingProfile && hasLoadedOnce == true {
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
        if showRewardHistoryOverlay {
            rewardHistoryOverlay
                .transition(.opacity)
                .zIndex(1000)
        }
        if showAchievementBoardOverlay {
            achievementBoardOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(1003)
        }
        if showQuestBoardInfoOverlay {
            questBoardInfoOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(1004)
        }
        if showSecretQuestListOverlay {
            secretQuestOverlay
                .transition(.opacity)
                .zIndex(1005)
        }
        if showSecretHintOverlay && !showAchievementBoardOverlay, let nextHintSecret {
            standaloneSecretHintOverlay(secret: nextHintSecret)
                .transition(.opacity)
                .zIndex(1006)
        }
        if let mode = activeLogListMode {
            logListOverlay(mode: mode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(1004)
        }
        if showSectionInfoOverlay {
            sectionInfoOverlay
                .transition(.opacity)
                .zIndex(1007)
        }
    }

    private func handleProfileAppear() {
        restoreCachedSnapshotIfNeeded()
        let me = Auth.auth().currentUser?.uid ?? ""
        self.isMe = (me == userId)
        self.isFounder = (me == founderUID)
        if !isMe {
            selectedPrimarySection = .lists
        } else if !visibleSections.contains(selectedPrimarySection), let first = visibleSections.first {
            selectedPrimarySection = first
        }
        loadUser()
        loadFollows()
        loadUserRatingAverage()
        loadRewardState()
        loadLists()
        loadRecentLogs()
        loadSelectedSectionData(force: true)
        AnalyticsService.shared.screen("Profile")
        playPendingRewardAnimationIfPossible()
    }

    private func handleRewardNotification(_ note: Notification) {
        guard isMe else { return }
        let total = note.userInfo?["total"] as? Int
        let delta = note.userInfo?["delta"] as? Int ?? 0
        if let total {
            let signature = "\(total):\(delta)"
            let isDuplicateOptimistic = recentOptimisticRewardSignature == signature
                && (recentOptimisticRewardAt?.timeIntervalSinceNow ?? -99) > -1.5

            if isDuplicateOptimistic {
                rewardXP = max(rewardXP, total)
                if pendingRewardAnimationTotal == nil && !isAnimatingRewardXP && canPlayRewardAnimation {
                    displayedRewardXP = max(displayedRewardXP, total)
                }
            } else {
                queueOrApplyRewardUpdate(total: total, delta: delta)
            }
        } else {
            loadRewardState()
        }
        if let raw = note.userInfo?["theme"] as? String {
            rewardTheme = RewardService.Theme(rawValue: raw) ?? rewardTheme
        }
        loadGamificationState()
    }

    private func handleGamificationUpdatedNotification(_ note: Notification) {
        guard isMe else { return }
        if let changedUserId = note.userInfo?["user_id"] as? String, changedUserId != userId {
            return
        }
        loadRewardState()
        loadGamificationState()
    }

    private func maybeShowQuestBoardIntro() {
        guard isMe else { return }
        guard selectedPrimarySection == .rewards else { return }
        guard !hasSeenQuestBoardIntro else { return }
        showQuestBoardIntroAlert = true
    }

    private var isAnyProfileOverlayPresented: Bool {
        showRewardHistoryOverlay
            || showAchievementBoardOverlay
            || showQuestBoardInfoOverlay
            || showSecretQuestListOverlay
            || showSecretHintOverlay
            || showTileInfoOverlay
            || showSectionInfoOverlay
            || activeLogListMode != nil
    }

    private func postProfileOverlayVisibility() {
        NotificationCenter.default.post(
            name: .profileOverlayVisibilityChanged,
            object: nil,
            userInfo: ["is_presented": isAnyProfileOverlayPresented]
        )
    }

    private func handleSectionsOrderChange() {
        if !visibleSections.contains(selectedPrimarySection), let first = visibleSections.first {
            selectedPrimarySection = first
        }
    }

    private var loadedProfileBody: some View {
        VStack(spacing: 0) {
            header
            sectionBody
        }
        .background(ColorTheme.background)
        .overlay(alignment: .top) {
            dragToastView
        }
    }

    private var sectionBody: some View {
        VStack(spacing: 8) {
            if visibleSections.count > 1 {
                profileSectionTabs
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            if selectedPrimarySection == .rewards {
                selectedSectionContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                selectedSectionContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedPrimarySection {
        case .rewards:
            rewardsBlock
        case .saved:
            savedGamesBlock
        case .references:
            referencesBlock
        case .lists:
            listsBlock
        case .recent:
            recentBlock
        }
    }

    @ViewBuilder
    private var dragToastView: some View {
        if let msg = dragToast {
            Text(msg)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func logListOverlay(mode: LogListMode) -> some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { activeLogListMode = nil }

            UserLogsListView(
                title: mode == .logged ? "Logged Games" : "Reviewed Games",
                logs: mode == .logged ? recentLogs : recentLogs.filter { ($0.review ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false },
                gameNames: gameNames,
                reviewsOnly: mode == .reviews,
                onClose: { activeLogListMode = nil },
                onOpenLog: { log, gameName in
                    NotificationCenter.default.post(
                        name: .openGlobalGameLogPreviewRequested,
                        object: log,
                        userInfo: [
                            "game_name": gameName,
                            "focus_comment": false
                        ]
                    )
                    activeLogListMode = nil
                }
            )
            .frame(width: min(UIScreen.main.bounds.width - 24, 390),
                   height: min(UIScreen.main.bounds.height - 110, 760))
            .background(RoundedRectangle(cornerRadius: 18).fill(ColorTheme.background))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
            .padding(.horizontal, 12)
        }
    }

    private var profileSectionTabs: some View {
        HStack(spacing: 8) {
            ForEach(visibleSections) { section in
                let isSelected = selectedPrimarySection == section
                Button {
                    guard selectedPrimarySection != section else { return }
                    Haptics.select()
                    selectedPrimarySection = section
                } label: {
                    HStack(spacing: 6) {
                        if section == .rewards {
                            rewardsTabIcon(isSelected: isSelected)
                        } else {
                            Text(section.tabTitle)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(isSelected ? ColorTheme.accent : ColorTheme.subtext)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? .black : ColorTheme.background.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        isSelected ? ColorTheme.accent : ColorTheme.separator,
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func rewardsTabIcon(isSelected: Bool) -> some View {
        let preferredAsset = isSelected ? "g_tab_land" : "inactive_g_tab_land"
        if UIImage(named: preferredAsset) != nil {
            rewardsTabImage(preferredAsset, isSelected: isSelected)
        } else if UIImage(named: "g_tab_land") != nil {
            rewardsTabImage("g_tab_land", isSelected: isSelected)
        } else if UIImage(named: "large_land_g_tab") != nil {
            rewardsTabImage("large_land_g_tab", isSelected: isSelected)
        } else if UIImage(named: "land_g_tab") != nil {
            rewardsTabImage("land_g_tab", isSelected: isSelected)
        } else {
            Image("icon")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? .black : Color.clear)
                )
        }
    }

    private func rewardsTabImage(_ name: String, isSelected: Bool) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 56, height: 56)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            .offset(y: -8)
            .clipped()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: headerCompact ? 4 : 10)

            HStack(alignment: .center, spacing: 10) {
                AvatarView(name: resolvedDisplayName, size: headerCompact ? 58 : 80, avatarURL: avatarUrl)
                    .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(resolvedDisplayName)
                            .font((headerCompact ? Font.headline : Font.title3).weight(.bold))
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(1)
                            .redacted(reason: displayName.isEmpty ? .placeholder : [])
                        if isTrustedGamer {
                            Image("trusted_flag")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(ColorTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        if isFounder {
                            Button {
                                showTrustedConfirm = true
                            } label: {
                                HStack(spacing: 4) {
                                    if isUpdatingTrusted {
                                        ProgressView().tint(ColorTheme.gold)
                                    } else {
                                        Image(systemName: isTrustedGamer ? "minus.circle.fill" : "plus.circle.fill")
                                            .font(.caption2.weight(.semibold))
                                        Text(isTrustedGamer ? "Remove" : "Assign")
                                            .font(.caption2.weight(.semibold))
                                    }
                                }
                                .foregroundColor(ColorTheme.gold)
                            }
                            .buttonStyle(.plain)
                            .disabled(isUpdatingTrusted)
                        }
                    }
                    Text(username.isEmpty ? "@ " : "@\(resolvedUsername)")
                        .font(.footnote)
                        .foregroundColor(ColorTheme.subtext)
                        .redacted(reason: username.isEmpty ? .placeholder : [])
                }
                Spacer(minLength: 0)
                if isMe {
                    HStack(spacing: 8) {
                        Button {
                            Haptics.tap()
                            showDraftsSheet = true
                        } label: {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(ColorTheme.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                                )
                                .foregroundColor(ColorTheme.accent)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                showEditProfile = true
                            } label: {
                                Label("Edit Profile", systemImage: "person.crop.circle.badge.checkmark")
                            }

                            Button {
                                showReorderSections = true
                            } label: {
                                Label("Arrange Sections", systemImage: "arrow.up.arrow.down.circle")
                            }

                            Divider()

                            Button {
                                showSettingsSheet = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(ColorTheme.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                                )
                                .foregroundColor(ColorTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Bio
            if !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bio)
                    .font(.caption)
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            if !creatorLinks.isEmpty {
                HStack(spacing: 10) {
                    ForEach(creatorLinks, id: \.label) { link in
                        Button {
                            openExternalProfileLink(link.url)
                        } label: {
                            HStack(spacing: 6) {
                                creatorLinkIcon(assetName: link.assetName, fallbackSystemName: link.icon, color: link.color)
                                    .frame(width: 18, height: 18)
                                Text(link.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(ColorTheme.surface)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(ColorTheme.separator, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }

            // Stats row (+ more stats)
            statsRow
                .padding(.bottom, 6)

            if !isMe {
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
        .padding(.bottom, 8)
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

    private func ratingStatBlock(avg: Double, label: String) -> some View {
        VStack(spacing: 2) {
            RatingHeartBadge(value: avg, size: 28)
            Text(label)
                .font(.caption)
                .foregroundColor(ColorTheme.subtext)
        }
        .frame(maxWidth: .infinity)
    }

    private var statsRow: some View {
        let loggedCount = recentLogs.count
        let reviewsCount = recentLogs.reduce(0) { acc, log in
            if let t = log.review, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return acc + 1 }
            return acc
        }

        return VStack(spacing: 10) {
            if isMe {
                HStack(spacing: 0) {
                    statBlock(value: followers, label: "Followers") { showFollowersSheet = true }
                    Divider().frame(height: 26).opacity(0.4)
                    statBlock(value: following, label: "Following") { showFollowingSheet = true }
                    Divider().frame(height: 26).opacity(0.4)
                    statBlock(value: loggedCount, label: "Logged") { activeLogListMode = .logged }
                    Divider().frame(height: 26).opacity(0.4)
                    statBlock(value: reviewsCount, label: "Reviews") { activeLogListMode = .reviews }
                    Divider().frame(height: 26).opacity(0.4)
                    ratingStatBlock(avg: avgUserRating ?? 0.0, label: "User Avg")
                }
            } else {
                HStack(spacing: 0) {
                    statBlock(value: followers, label: "Followers") { showFollowersSheet = true }
                    Divider().frame(height: 26).opacity(0.4)
                    statBlock(value: following, label: "Following") { showFollowingSheet = true }
                }
            }

            if isMe {
                HStack(spacing: 10) {
                    Button {
                        showStats = true
                        Haptics.select()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.fill")
                            Text("Insights")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insights")
                }
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

    private var rewardProgressCard: some View {
        let info = RewardService.levelInfo(for: displayedRewardXP)
        let nextReward = nextRewardLevel(from: info.level)
        let barHeight: CGFloat = headerCompact ? 8 : 10
        let levelGradient = LinearGradient(
            colors: [ColorTheme.gold, ColorTheme.xpGreen],
            startPoint: .leading,
            endPoint: .trailing
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Text("GL \(info.level)")
                    Text("GamerLnd Level")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                Text("\(info.totalXP) \(rewardTheme.displayUnit)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ColorTheme.separator.opacity(0.24))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(levelGradient)
                        .frame(width: max(6, geo.size.width * info.progress))
                }
            }
            .frame(height: barHeight)

            Text("\(info.xpToNext) XP to GL \(info.level + 1)")
                .font(.caption2)
                .foregroundColor(ColorTheme.subtext)
            HStack {
                Text("Next reward at GL \(nextReward)")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.subtext)
                Spacer()
                Button {
                    showRewardHistoryOverlay = true
                } label: {
                    Text("XP History")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, headerCompact ? 8 : 10)
        .padding(.vertical, headerCompact ? 7 : 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(levelGradient, lineWidth: 1.2)
        )
        .overlay(alignment: .topTrailing) {
            if let rewardDeltaToast {
                let border = LinearGradient(
                    colors: [ColorTheme.xpGreen, ColorTheme.gold],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                HStack(spacing: 8) {
                    Image(systemName: rewardDeltaToastIcon)
                        .foregroundColor(ColorTheme.gold)
                    Text(rewardDeltaToast)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ColorTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1.2))
                )
                .offset(x: -8, y: -14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var rewardsBlock: some View {
        RewardsSectionView(
            rewardProgressCard: AnyView(rewardProgressCard),
            achievementPreviewCard: AnyView(achievementPreviewCard),
            secretQuestPreviewCard: AnyView(
                Group {
                    if !discoveredSecrets.isEmpty {
                        secretQuestPreviewCard
                    }
                }
            ),
            dailyObjectives: dailyObjectives,
            weeklyObjectives: weeklyObjectives,
            claimingObjectiveIDs: claimingObjectiveIDs,
            pageSelection: $rewardsPageSelection,
            onClaimObjective: { objective, assignment in
                claimObjective(objective, assignment: assignment)
            }
        )
    }

    private func claimObjective(_ objective: ObjectiveProgressEntry, assignment: ObjectiveAssignment) {
        guard !claimingObjectiveIDs.contains(objective.id) else { return }
        claimingObjectiveIDs.insert(objective.id)
        ObjectiveService.shared.claimObjectiveXP(assignment: assignment, objectiveId: objective.id) { granted in
            DispatchQueue.main.async {
                claimingObjectiveIDs.remove(objective.id)
                if granted <= 0 {
                    loadRewardState()
                }
                loadGamificationState()
            }
        }
    }

    private func claimSecret(state: UserSecretUnlockState) {
        guard !claimingSecretIDs.contains(state.secretId) else { return }
        claimingSecretIDs.insert(state.secretId)
        SecretUnlockService.shared.claimSecretXP(userId: userId, secretId: state.secretId) { granted in
            DispatchQueue.main.async {
                claimingSecretIDs.remove(state.secretId)
                if granted <= 0 {
                    loadRewardState()
                }
                loadGamificationState()
            }
        }
    }

    private var achievementPreviewCard: some View {
        let completed = achievementStates.values.filter { $0.state == .completed }.count
        let hinted = boardAchievements.filter { (achievementStates[$0.id]?.state ?? defaultAchievementState(for: $0)) == .hinted }.count
        let total = boardAchievements.count
        let completedByRarity: [RewardRarity: Int] = Dictionary(uniqueKeysWithValues: RewardRarity.allCases.map { rarity in
            (rarity, boardAchievements.filter { achievement in
                achievement.rarity == rarity && (achievementStates[achievement.id]?.state == .completed)
            }.count)
        })

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quest Board")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Text("\(completed)/\(max(1, total)) completed")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                    Text("\(hinted) hinted")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                }
                Spacer()
                Button {
                    showAchievementBoardOverlay = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.3x3.fill")
                        Text("Open")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                compactAchievementCountPill(title: "Hints Available", value: hinted)
                compactAchievementCountPill(title: "Quests Completed", value: completed)
            }

            VStack(spacing: 6) {
                rarityProgressRow(
                    title: previewRarityLabel(for: .common, completedCount: completedByRarity[.common] ?? 0),
                    value: completedByRarity[.common] ?? 0,
                    tint: rarityColor(for: .common)
                )
                rarityProgressRow(
                    title: previewRarityLabel(for: .rare, completedCount: completedByRarity[.rare] ?? 0),
                    value: completedByRarity[.rare] ?? 0,
                    tint: rarityColor(for: .rare)
                )
                rarityProgressRow(
                    title: previewRarityLabel(for: .epic, completedCount: completedByRarity[.epic] ?? 0),
                    value: completedByRarity[.epic] ?? 0,
                    tint: rarityColor(for: .epic)
                )
                rarityProgressRow(
                    title: previewRarityLabel(for: .legendary, completedCount: completedByRarity[.legendary] ?? 0),
                    value: completedByRarity[.legendary] ?? 0,
                    tint: rarityColor(for: .legendary)
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private func compactAchievementCountPill(title: String, value: Int, outline: Color = ColorTheme.separator) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.weight(.bold))
                .foregroundColor(ColorTheme.text)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(ColorTheme.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.background.opacity(0.38)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(outline.opacity(0.7), lineWidth: 1))
    }

    private var secretQuestPreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Secret Quests")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Text(discoveredSecrets.isEmpty ? "No discoveries yet" : "Found \(discoveredSecrets.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(discoveredSecrets.isEmpty ? ColorTheme.subtext : ColorTheme.accent)
                }
                Spacer()
                Button {
                    showSecretQuestListOverlay = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Open")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if let state = discoveredSecrets.first {
                let secret = secretCatalog.first(where: { $0.id == state.secretId })
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(secret?.title ?? "Secret Quest")
                            .font(.caption.weight(.medium))
                            .foregroundColor(ColorTheme.text)
                        Text(state.claimed ? "Complete" : "Ready to claim")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(state.claimed ? ColorTheme.subtext : ColorTheme.accent)
                    }
                    Spacer()
                    Text(secret.map { visibleRarityLabel(for: $0.rarity) } ?? "?")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(rarityColor(for: secret?.rarity ?? .rare))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.background.opacity(0.38)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator.opacity(0.8), lineWidth: 1))
            } else if nextHintSecret != nil {
                HStack {
                    Text("A new clue is waiting.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Text("Clue")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.background.opacity(0.38)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator.opacity(0.8), lineWidth: 1))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private func rarityProgressRow(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 20, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ColorTheme.separator.opacity(0.2))
                    Capsule().fill(tint.opacity(0.9))
                        .frame(width: min(geo.size.width, CGFloat(max(0, value)) * 14))
                }
            }
            .frame(height: 6)
            Text("\(value)")
                .font(.caption2.weight(.semibold))
                .foregroundColor(ColorTheme.text)
                .frame(width: 18, alignment: .trailing)
        }
        .frame(height: 14)
    }

    private var secretDiscoveriesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Secret Quests")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                Text("Found \(discoveredSecrets.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
            }

            VStack(spacing: 6) {
                ForEach(discoveredSecrets.prefix(4), id: \.id) { state in
                    let secret = secretCatalog.first(where: { $0.id == state.secretId })
                    let isClaimed = state.claimed
                    let isClaimable = secret != nil && !isClaimed
                    Button {
                        guard let secret, isClaimable, !claimingSecretIDs.contains(state.secretId) else { return }
                        claimingSecretIDs.insert(state.secretId)
                        SecretUnlockService.shared.claimSecretXP(userId: userId, secretId: secret.id) { granted in
                            DispatchQueue.main.async {
                                claimingSecretIDs.remove(state.secretId)
                                if granted <= 0 {
                                    loadRewardState()
                                }
                                loadGamificationState()
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(secret?.title ?? "Secret Quest")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(ColorTheme.text)
                                if let secret {
                                    if isClaimed {
                                        Text("Complete")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(ColorTheme.subtext)
                                    } else {
                                        Text("Claim +\(secret.xpReward)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(ColorTheme.accent)
                                    }
                                }
                            }
                            Spacer()
                            if claimingSecretIDs.contains(state.secretId) {
                                ProgressView()
                                    .tint(ColorTheme.accent)
                                    .scaleEffect(0.75)
                            } else {
                                Text(secret.map { rarityLabel(for: $0.rarity) } ?? "?")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(rarityColor(for: secret?.rarity ?? .rare))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isClaimed ? ColorTheme.separator : ColorTheme.accent.opacity(0.7), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isClaimable || claimingSecretIDs.contains(state.secretId))
                }

                if nextHintSecret != nil {
                    Button {
                        selectedAchievementTile = nil
                        showSecretHintOverlay = true
                        showAchievementBoardOverlay = true
                    } label: {
                        HStack {
                            Text("?????")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                            Spacer()
                            Text("Clue")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(ColorTheme.accent)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("All Secret Quests Found")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private func tileFill(for achievement: AchievementDefinition, state: AchievementTileState) -> Color {
        let achievementState = achievementStates[achievement.id]
        let isClaimedCompletion = state == .completed && (achievementState?.claimed ?? false)
        switch state {
        case .completed:
            return isClaimedCompletion ? ColorTheme.black : ColorTheme.gold
        case .hinted:
            return ColorTheme.separator.opacity(0.25)
        case .hidden:
            return ColorTheme.separator.opacity(0.12)
        }
    }

    private var boardAchievements: [AchievementDefinition] {
        achievementCatalog
            .filter { !$0.isSecret }
            .sorted {
                ($0.tileRow ?? Int.max, $0.tileColumn ?? Int.max, $0.code)
                < ($1.tileRow ?? Int.max, $1.tileColumn ?? Int.max, $1.code)
            }
    }

    private func defaultAchievementState(for achievement: AchievementDefinition) -> AchievementTileState {
        _ = achievement
        return .hidden
    }

    private func rarityColor(for rarity: RewardRarity) -> Color {
        switch rarity {
        case .common: return .white
        case .rare: return .blue
        case .epic: return ColorTheme.xpGreen
        case .legendary: return Color("SecondaryHighlightColor")
        }
    }

    private func rarityLabel(for rarity: RewardRarity) -> String {
        switch rarity {
        case .common: return "I"
        case .rare: return "II"
        case .epic: return "III"
        case .legendary: return "IV"
        }
    }

    private func previewRarityLabel(for rarity: RewardRarity, completedCount: Int) -> String {
        switch rarity {
        case .common:
            return rarityLabel(for: rarity)
        case .rare, .epic, .legendary:
            return completedCount > 0 ? rarityLabel(for: rarity) : "?"
        }
    }

    private func visibleRarityLabel(for rarity: RewardRarity) -> String {
        switch rarity {
        case .common:
            return rarityLabel(for: rarity)
        case .rare, .epic, .legendary:
            let completedCount = boardAchievements.filter { achievement in
                achievement.rarity == rarity && (achievementStates[achievement.id]?.state == .completed)
            }.count
            return completedCount > 0 ? rarityLabel(for: rarity) : "?"
        }
    }

    private var achievementBoardOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    dismissAchievementBoardOverlay()
                }
            achievementBoardPanel
            achievementBoardModalOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { postProfileOverlayVisibility() }
        .onDisappear { postProfileOverlayVisibility() }
    }

    private var achievementBoardPanel: some View {
        GeometryReader { proxy in
            let outerHorizontal: CGFloat = 18
            let outerVertical: CGFloat = 20
            let spacing: CGFloat = 5
            let panelWidth = min(proxy.size.width - (outerHorizontal * 2), 382)
            let tileSize = max(
                24,
                ((panelWidth - 36) - (CGFloat(AchievementService.shared.boardColumns - 1) * spacing))
                    / CGFloat(AchievementService.shared.boardColumns)
            )
            let gridHeight = (tileSize * CGFloat(AchievementService.shared.boardRows))
                + (spacing * CGFloat(AchievementService.shared.boardRows - 1))
            let desiredPanelHeight = gridHeight + 126
            let panelHeight = min(proxy.size.height - (outerVertical * 2), desiredPanelHeight)

            VStack(alignment: .leading, spacing: 12) {
                achievementBoardHeader
                achievementBoardGrid(tileSize: tileSize, spacing: spacing)
            }
            .padding(.top, 16)
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
            .frame(width: panelWidth, height: panelHeight, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ColorTheme.black.opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ColorTheme.separator, lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, outerHorizontal)
            .padding(.vertical, outerVertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var achievementBoardCompletedCount: Int {
        achievementStates.values.filter { $0.state == .completed }.count
    }

    private var achievementBoardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Quest Board")
                        .font(.title3.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Button {
                        showQuestBoardInfoOverlay = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(ColorTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(achievementBoardCompletedCount) completed")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
            }
            Spacer()
            Button {
                dismissAchievementBoardOverlay()
            } label: {
                OverlayCloseButton()
            }
            .buttonStyle(.plain)
        }
    }

    private var questBoardInfoOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { showQuestBoardInfoOverlay = false }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("How Quest Board Works")
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Button {
                        showQuestBoardInfoOverlay = false
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }

                Text("Hidden tiles stay hidden until a neighboring quest is completed.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)

                Text("Complete quests to reveal adjacent clues. As you progress, more of the board opens up and the path becomes clearer.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: min(UIScreen.main.bounds.width - 32, 360))
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ColorTheme.background)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
        }
    }

    private func achievementBoardGrid(tileSize: CGFloat, spacing: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.fixed(tileSize), spacing: spacing), count: AchievementService.shared.boardColumns)
        let totalTiles = AchievementService.shared.boardRows * AchievementService.shared.boardColumns
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(0..<totalTiles, id: \.self) { index in
                let row = index / AchievementService.shared.boardColumns
                let col = index % AchievementService.shared.boardColumns
                let achievement = boardAchievements.first(where: { $0.tileRow == row && $0.tileColumn == col })
                achievementBoardTile(achievement: achievement)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var achievementBoardModalOverlay: some View {
        if showTileInfoOverlay, let selectedAchievementTile {
            ZStack {
                Color.black.opacity(0.50)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showTileInfoOverlay = false
                        self.selectedAchievementTile = nil
                    }

                achievementBoardDetailCard(achievement: selectedAchievementTile)
                    .frame(width: min(UIScreen.main.bounds.width - 48, 340))
            }
        } else if showSecretHintOverlay, let nextHintSecret {
            ZStack {
                Color.black.opacity(0.50)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showSecretHintOverlay = false
                    }

                secretHintCard(secret: nextHintSecret)
                    .frame(width: min(UIScreen.main.bounds.width - 48, 340))
            }
        }
    }

    private func dismissAchievementBoardOverlay() {
        showAchievementBoardOverlay = false
        selectedAchievementTile = nil
        showSecretHintOverlay = false
        showTileInfoOverlay = false
    }

    private func tileBorderColor(for achievement: AchievementDefinition, state: AchievementTileState) -> Color {
        switch state {
        case .hinted:
            return rarityColor(for: achievement.rarity)
        case .completed:
            let isClaimed = achievementStates[achievement.id]?.claimed ?? false
            return isClaimed ? ColorTheme.gold : ColorTheme.separator.opacity(0.55)
        case .hidden:
            return ColorTheme.separator.opacity(0.55)
        }
    }

    private func achievementBoardTile(achievement: AchievementDefinition?) -> some View {
        if let achievement {
            let state = achievementStates[achievement.id]?.state ?? defaultAchievementState(for: achievement)
            return AnyView(
                Button {
                    guard state != .hidden else { return }
                    selectedAchievementTile = achievement
                    showSecretHintOverlay = false
                    showTileInfoOverlay = true
                } label: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tileFill(for: achievement, state: state))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(tileBorderColor(for: achievement, state: state), lineWidth: 1.2)
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            switch state {
                            case .completed:
                                let isClaimed = achievementStates[achievement.id]?.claimed ?? false
                                VStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(isClaimed ? ColorTheme.gold : ColorTheme.black)
                                    Text(achievement.title)
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(isClaimed ? ColorTheme.gold : ColorTheme.black)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .padding(.horizontal, 3)
                                }
                            case .hinted:
                                VStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(rarityColor(for: achievement.rarity))
                                }
                            case .hidden:
                                Image(systemName: "questionmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(ColorTheme.subtext)
                            }
                        }
                }
                .buttonStyle(.plain)
            )
        } else {
            return AnyView(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ColorTheme.separator.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ColorTheme.separator.opacity(0.55), lineWidth: 1)
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "questionmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ColorTheme.subtext)
                    }
            )
        }
    }

    private func achievementBoardDetailCard(achievement: AchievementDefinition) -> some View {
        let achievementState = achievementStates[achievement.id]
        let state = achievementState?.state ?? defaultAchievementState(for: achievement)
        let isClaimable = state == .completed && !(achievementState?.claimed ?? false)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(state == .completed ? achievement.title : "Quest Hint")
                    .font(.headline.weight(.bold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                Text(visibleRarityLabel(for: achievement.rarity))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(rarityColor(for: achievement.rarity))
                Button {
                    showTileInfoOverlay = false
                    selectedAchievementTile = nil
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
            }

            Text(state == .completed ? achievement.detail : achievement.hintText)
                .font(.caption)
                .foregroundColor(ColorTheme.subtext)

            if state == .completed {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text("+\(achievement.xpReward) XP")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.accent)
                        if let achievementState, achievementState.claimed, !achievement.unlockableRewardIds.isEmpty {
                            Text("Unlockable Earned")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ColorTheme.gold)
                        }
                    }

                    if isClaimable {
                        Button {
                            guard !claimingQuestIDs.contains(achievement.id) else { return }
                            claimingQuestIDs.insert(achievement.id)
                            AchievementService.shared.claimQuestXP(userId: userId, achievementId: achievement.id) { granted in
                                DispatchQueue.main.async {
                                    claimingQuestIDs.remove(achievement.id)
                                    if granted <= 0 {
                                        loadRewardState()
                                    }
                                    loadGamificationState()
                                }
                            }
                        } label: {
                            HStack {
                                if claimingQuestIDs.contains(achievement.id) {
                                    ProgressView()
                                        .tint(ColorTheme.accent)
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Claim +\(achievement.xpReward)")
                                        .font(.caption.weight(.bold))
                                }
                                Spacer()
                                Text("Quest Complete")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundColor(ColorTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(ColorTheme.surface.opacity(0.82))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(ColorTheme.accent.opacity(0.8), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(claimingQuestIDs.contains(achievement.id))
                    } else {
                        Text("Complete")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.subtext)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(ColorTheme.surface.opacity(0.82))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(ColorTheme.separator, lineWidth: 1)
                            )
                    }
                }
            } else {
                Text("Complete it to reveal the full requirement and reward.")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.subtext)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(rarityColor(for: achievement.rarity).opacity(0.45), lineWidth: 1))
    }

    private var secretQuestOverlay: some View {
        ZStack {
            Color.black.opacity(0.56)
                .ignoresSafeArea()
                .onTapGesture {
                    showSecretQuestListOverlay = false
                }

            secretQuestBoardCard
                .frame(width: min(UIScreen.main.bounds.width - 48, 340))
        }
    }

    private func standaloneSecretHintOverlay(secret: SecretUnlockDefinition) -> some View {
        ZStack {
            Color.black.opacity(0.50)
                .ignoresSafeArea()
                .onTapGesture {
                    showSecretHintOverlay = false
                }

            secretHintCard(secret: secret)
                .frame(width: min(UIScreen.main.bounds.width - 48, 340))
        }
    }

    private var secretQuestBoardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Secret Quests")
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Text("Found \(discoveredSecrets.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }
                Spacer()
                Button {
                    showSecretQuestListOverlay = false
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
            }

            if !discoveredSecrets.isEmpty {
                VStack(spacing: 8) {
                    ForEach(discoveredSecrets, id: \.id) { state in
                        let secret = secretCatalog.first(where: { $0.id == state.secretId })
                        let isClaiming = claimingSecretIDs.contains(state.secretId)
                        Button {
                            guard !state.claimed, secret != nil, !isClaiming else { return }
                            claimSecret(state: state)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(secret?.title ?? "Secret Quest")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(ColorTheme.text)
                                    Text(state.claimed ? "Complete" : "Claim +\(secret?.xpReward ?? 0)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(state.claimed ? ColorTheme.subtext : ColorTheme.accent)
                                }
                                Spacer()
                                if isClaiming {
                                    ProgressView()
                                        .tint(ColorTheme.accent)
                                        .scaleEffect(0.7)
                                } else {
                                    Text(secret.map { rarityLabel(for: $0.rarity) } ?? "?")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(rarityColor(for: secret?.rarity ?? .rare))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface.opacity(0.82)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(state.claimed ? ColorTheme.separator : ColorTheme.accent.opacity(0.7), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(state.claimed || secret == nil || isClaiming)
                    }
                }
            }

            if !discoveredSecrets.isEmpty, let nextHintSecret {
                Button {
                    showSecretQuestListOverlay = false
                    showSecretHintOverlay = true
                } label: {
                    HStack {
                        Text("???")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                        Spacer()
                        Text(visibleRarityLabel(for: nextHintSecret.rarity))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(rarityColor(for: nextHintSecret.rarity))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface.opacity(0.82)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.accent.opacity(0.35), lineWidth: 1))
    }

    private func secretHintCard(secret: SecretUnlockDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Next Secret Quest Hint")
                    .font(.headline.weight(.bold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                Text(visibleRarityLabel(for: secret.rarity))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(rarityColor(for: secret.rarity))
                Button {
                    showSecretHintOverlay = false
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
            }
            Text(secret.hintText)
                .font(.caption)
                .foregroundColor(ColorTheme.subtext)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(rarityColor(for: secret.rarity).opacity(0.45), lineWidth: 1))
    }

    private var compactRewardProgressCard: some View {
        let info = RewardService.levelInfo(for: rewardXP)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Lv \(info.level)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                Text("\(info.totalXP)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(ColorTheme.separator.opacity(0.2))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [ColorTheme.accent, ColorTheme.gold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * info.progress))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func nextRewardLevel(from currentLevel: Int) -> Int {
        let lv = max(1, currentLevel)
        if lv < 25 {
            return ((lv / 5) + 1) * 5
        } else if lv < 50 {
            return ((lv / 10) + 1) * 10
        } else if lv < 100 {
            return ((lv / 25) + 1) * 25
        } else {
            return ((lv / 50) + 1) * 50
        }
    }

    private var rewardHistoryOverlay: some View {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let visibleRewardEvents = rewardEvents.filter { $0.at >= cutoffDate }
        return ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { showRewardHistoryOverlay = false }

            VStack {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text("XP History")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                        Spacer()
                        Button {
                            showRewardHistoryOverlay = false
                        } label: {
                            OverlayCloseButton()
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            showRewardHistoryOverlay = false
                            selectedPrimarySection = .rewards
                            rewardsPageSelection = 0
                        } label: {
                            Image(systemName: "square.grid.3x3.fill")
                                .font(.body.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showRewardHistoryOverlay = false
                            selectedPrimarySection = .rewards
                            rewardsPageSelection = 1
                        } label: {
                            Image(systemName: "flag.checkered.2.crossed")
                                .font(.body.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    if visibleRewardEvents.isEmpty {
                        Text("No XP activity yet.")
                            .font(.footnote)
                            .foregroundColor(ColorTheme.subtext)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(Array(visibleRewardEvents.prefix(120)), id: \.id) { e in
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(readableRewardType(e.type))
                                                .font(.footnote)
                                                .foregroundColor(ColorTheme.text)
                                            Text(rewardHistoryTimestamp(for: e.at))
                                                .font(.caption2)
                                                .foregroundColor(ColorTheme.subtext)
                                        }
                                        Spacer()
                                        Text("+\(e.delta)")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundColor(ColorTheme.accent)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(ColorTheme.surface)
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 340)
                    }
                }
                .padding(14)
                .frame(width: min(UIScreen.main.bounds.width - 34, 360), alignment: .top)
                .frame(maxHeight: min(UIScreen.main.bounds.height - 140, 640), alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(ColorTheme.black.opacity(0.94))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ColorTheme.separator, lineWidth: 1))
                )
                .padding(.horizontal, 20)
                Spacer()
            }
            .padding(.top, 84)
        }
    }

    private func readableRewardType(_ raw: String) -> String {
        switch raw {
        case "base_rating": return "Rated a Game"
        case "base_review": return "Wrote a Review"
        case "save_game": return "Saved a Game"
        case "list_add": return "Added to List"
        case "list_create": return "Created a List"
        case "daily_objective_complete", "weekly_objective_complete": return "Challenge Claimed"
        case "achievement_complete": return "Quest Claimed"
        case "secret_unlock": return "Secret Quest Claimed"
        case "first_action_bonus": return "Daily Bonus"
        default: return "Activity"
        }
    }

    private func rewardHistoryTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var savedGamesColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 98, maximum: 116), spacing: 6),
            GridItem(.flexible(minimum: 98, maximum: 116), spacing: 6),
            GridItem(.flexible(minimum: 98, maximum: 116), spacing: 6)
        ]
    }

    // MARK: - Sections

    private var savedGamesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeaderWithInfo(title: "Saved Games", info: "Saved Games are titles you want to keep track of for later. This is where you can quickly revisit games you saved from around the app.", systemImage: "tray.and.arrow.down.fill")
                Spacer()
                if !watchlist.isEmpty {
                    Menu {
                        Picker("Sort Saved Games", selection: $savedGamesSort) {
                            ForEach(SavedGamesSort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(savedGamesSort.rawValue)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                }
                if isMe && !watchlist.isEmpty {
                    Button(isEditingSavedGames ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingSavedGames.toggle()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                }
            }

            if watchlist.isEmpty {
                if isMe {
                    Button {
                        NotificationCenter.default.post(name: .switchToExplore, object: nil)
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(ColorTheme.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(ColorTheme.accent)
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add saved games")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                                Text("Save games from Explore to build this section.")
                                    .font(.footnote)
                                    .foregroundColor(ColorTheme.subtext)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(ColorTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                } else {
                    Text("No saved games yet.")
                        .font(.footnote)
                        .foregroundColor(ColorTheme.subtext)
                        .padding(.top, 6)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    HStack {
                        Spacer(minLength: 0)
                        LazyVGrid(columns: savedGamesColumns, alignment: .center, spacing: 14) {
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
                                .frame(width: 96, height: 128)
                                .frame(width: 102, height: 178, alignment: .top)
                            }
                            .buttonStyle(.plain)

                            ForEach(displayedWatchlist, id: \.id) { g in
                                savedGameTile(for: g)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .padding(.bottom, 72)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var listsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with inline "New List" on the right
            HStack {
                sectionHeaderWithInfo(title: "Lists", info: "Lists are your curated game collections. Use them for rankings, tiers, themes, and public sharing, then add games into them over time.", systemImage: "text.badge.plus")
                Spacer()
                if !filteredLists.isEmpty {
                    Menu {
                        Picker("Sort Lists", selection: $listsSort) {
                            ForEach(ListsSort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(listsSort.rawValue)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                }
                if isMe {
                    Button {
                        showNewListSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("New List").bold()
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                        .foregroundColor(ColorTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ListDisplayFilter.allCases) { filter in
                        Button {
                            selectedListFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(selectedListFilter == filter ? ColorTheme.accent : ColorTheme.subtext)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedListFilter == filter ? .black : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(
                                                selectedListFilter == filter ? ColorTheme.accent : ColorTheme.separator,
                                                lineWidth: 1
                                            )
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if isLoadingLists {
                Text("Loading lists…")
                    .foregroundColor(ColorTheme.subtext)
                    .font(.footnote)
                    .padding(.horizontal, 2)
            } else if filteredLists.isEmpty {
                Text(selectedListFilter == .all
                     ? (isMe ? "You haven’t created any lists yet." : "No lists yet.")
                     : "No \(selectedListFilter.rawValue.lowercased()) lists yet.")
                    .foregroundColor(ColorTheme.subtext)
                    .font(.footnote)
                    .padding(.horizontal, 2)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredLists) { l in
                            NavigationLink(
                                destination: ListDetailView(
                                    list: convertToUserList(l),
                                    isOwner: isMe
                                )
                            ) {
                                ListRectangleCard(
                                    list: l,
                                    previewImageIds: listPreviewCovers[l.id] ?? [],
                                    cardWidth: 0,
                                    cardHeight: 184,
                                    previewSide: 124,
                                    showTypeLabel: selectedListFilter == .all,
                                    isPinned: pinnedListIds.contains(l.id),
                                    showPinButton: isMe,
                                    isPinBusy: isUpdatingPinnedLists.contains(l.id),
                                    onTogglePin: {
                                        togglePinnedList(l.id)
                                    }
                                )
                                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                                    handleDrop(providers: providers, onto: l)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // remove extra top padding so it hugs the header
    }

    private var recentBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderWithInfo(title: "Recently Logged", info: "Recently Logged is your running history of game logs, so you can quickly revisit the games you rated, reviewed, or logged most recently.", systemImage: "")

            if recentLogs.isEmpty {
                Text(isMe ? "You haven’t logged any games yet." : "No logs yet.")
                    .foregroundColor(ColorTheme.subtext)
                    .font(.footnote)
                    .padding(.horizontal, 2)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(recentLogs, id: \.id) { log in
                            let cached = gameNames[log.gameId]
                            let title = (cached == "Unknown Game" || cached == nil || cached?.hasPrefix("Game #") == true)
                                ? (log.gameName ?? "Loading…")
                                : (cached ?? "Loading…")
                            let avg = avgCache[log.gameId]?.avg
                            let count = avgCache[log.gameId]?.count ?? 0
                            Button {
                                NotificationCenter.default.post(
                                    name: .openGlobalGameLogPreviewRequested,
                                    object: log,
                                    userInfo: [
                                        "game_name": title,
                                        "username": displayName,
                                        "focus_comment": false
                                    ]
                                )
                            } label: {
                                RecentLogRowCard(
                                    log: log,
                                    title: title,
                                    avg: avg,
                                    count: count
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func savedGameTile(for g: Game) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .center, spacing: 6) {
                if let img = g.cover?.imageId {
                    GameCoverImage(id: img, preset: .custom(width: 96), cornerRadius: 8)
                        .frame(width: 96, height: 128)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ColorTheme.separator.opacity(0.25))
                        .frame(width: 96, height: 128)
                }
                Text(g.name)
                    .font(.caption)
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 178, maxHeight: 178, alignment: .top)

            if isEditingSavedGames {
                Button {
                    removeFromSavedGames(g)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundColor(ColorTheme.highlight)
                        .background(Circle().fill(ColorTheme.surface))
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: -8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingSavedGames {
                NotificationCenter.default.post(
                    name: .openGlobalGameLogEditorRequested,
                    object: g
                )
            }
        }
        .onDrag {
            guard isMe else { return NSItemProvider() }
            return NSItemProvider(object: "\(g.id)" as NSString)
        }
    }

    private var referencesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeaderWithInfo(title: "References", info: "References are other users' game logs you saved privately so you can revisit them later.", systemImage: "doc.badge.plus")
                Spacer()
                if !references.isEmpty {
                    Menu {
                        Picker("Sort References", selection: $referencesSort) {
                            ForEach(ReferencesSort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(referencesSort.rawValue)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                }
                if isMe && !references.isEmpty {
                    Button(isEditingReferences ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingReferences.toggle()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                if references.isEmpty {
                    Text("Save logs as references for later.")
                        .font(.footnote)
                        .foregroundColor(ColorTheme.subtext)
                        .padding(.top, 6)
                } else {
                    VStack(spacing: 10) {
                        ForEach(displayedReferences) { reference in
                            referenceRow(reference)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func referenceRow(_ reference: LogReferenceEntry) -> some View {
        let accentColor: Color = {
            if let rating = reference.rating, rating > 0 {
                return ColorTheme.ratingBandColor(for: rating)
            }
            return ColorTheme.separator
        }()
        return HStack(spacing: 12) {
            if let coverId = reference.coverId, !coverId.isEmpty {
                GameCoverImage(id: coverId, preset: .small, cornerRadius: 8)
                    .frame(width: 52, height: 70)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ColorTheme.separator.opacity(0.25))
                    .frame(width: 52, height: 70)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(reference.authorName)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(ColorTheme.accent)
                    .lineLimit(1)
                Text(reference.gameName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if let preview = reference.reviewPreview, !preview.isEmpty {
                    Text(ContentModeration.displayReviewText(preview))
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("Saved for later reference")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            VStack {
                if let rating = reference.rating, rating > 0 {
                    RatingHeartBadge(value: rating, size: 44)
                }
            }
            .frame(width: 58)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.85), lineWidth: 1.2)
        )
        .overlay(alignment: .topTrailing) {
            if isEditingReferences {
                Button {
                    removeReference(reference)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 22, height: 22)
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if !isEditingReferences {
                openReference(reference)
            }
        }
    }

    // MARK: - Loads

    private func loadUser() {
        restoreCachedProfileIfNeeded()
        if !hasLoadedOnce && displayName.isEmpty && username.isEmpty {
            isLoadingProfile = true
        }

        let ref = db.collection("users").document(userId)
        ref.getDocument(source: .cache) { doc, _ in
            if let data = doc?.data(), !data.isEmpty {
                DispatchQueue.main.async {
                    self.applyUserData(data)
                    self.isLoadingProfile = false
                    self.hasLoadedOnce = true
                }
            }
        }
        ref.getDocument(source: .server) { doc, _ in
            let data = doc?.data() ?? [:]
            DispatchQueue.main.async {
                self.applyUserData(data)
                self.isLoadingProfile = false
                self.hasLoadedOnce = true
            }
        }
    }

    private func applyUserData(_ data: [String: Any]) {
        let currentUsername = self.username
        let currentDisplayName = self.displayName

        let fetchedUsername = (data["username"] as? String) ?? (data["email"] as? String) ?? currentUsername
        self.username = fetchedUsername
        self.displayName = (data["display_name"] as? String) ?? (data["username"] as? String) ?? (data["email"] as? String) ?? currentDisplayName

        self.bio = String(((data["bio"] as? String) ?? self.bio).prefix(120))
        self.avatarUrl = UserRecordAvatarResolver.url(from: data)
        self.youtubeURL = (data["youtube_url"] as? String) ?? ""
        self.twitchURL = (data["twitch_url"] as? String) ?? ""
        self.tiktokURL = (data["tiktok_url"] as? String) ?? ""
        self.isTrustedGamer = (data["is_trusted_gamer"] as? Bool) ?? false
        self.pinnedListIds = Set((data["pinned_list_ids"] as? [String]) ?? [])

        if let fav = data["favorite_game"] as? [String: Any] {
            self.favoriteGame = self.gameFromDict(fav)
        }
        if let watch = data["watchlist_games"] as? [[String: Any]] {
            self.watchlist = watch.compactMap { self.gameFromDict($0) }
            self.watchlistAddedAt = Dictionary(uniqueKeysWithValues: watch.compactMap { entry in
                guard let id = entry["id"] as? Int else { return nil }
                let added = (entry["added_at"] as? Timestamp)?.dateValue() ?? .distantPast
                return (id, added)
            })
            self.hydrateWatchlistNamesIfNeeded()
            self.hasLoadedSavedSection = true
        } else {
            self.watchlist = []
            self.watchlistAddedAt = [:]
            self.hasLoadedSavedSection = true
        }
        self.favoritePlayStyle = (data["favorite_play_style"] as? String) ?? ""
        self.favoritePlatform = (data["favorite_platform"] as? String) ?? ""
        self.favoriteGenre = (data["favorite_genre"] as? String) ?? ""
        self.favoriteFranchise = (data["favorite_franchise"] as? String) ?? ""
        if let rawTheme = data["reward_theme"] as? String {
            self.rewardTheme = RewardService.Theme(rawValue: rawTheme) ?? .xp
        } else {
            self.rewardTheme = RewardService.shared.currentTheme(for: self.userId)
        }

        if !self.isMe {
            InteractionService.shared.isFollowing(targetUserId: self.userId) { state in
                self.isFollowing = state
            }
        }

        if let orderRaw = data["sections_order"] as? [String] {
            var mapped = orderRaw.compactMap { SectionKind(rawValue: $0) }
            if self.isMe && !mapped.contains(.rewards) {
                mapped.insert(.rewards, at: 0)
            }
            if self.isMe && !mapped.contains(.references) {
                let insertIndex = min(2, mapped.count)
                mapped.insert(.references, at: insertIndex)
            }
            if !mapped.isEmpty {
                self.sectionsOrder = mapped
            }
        }

        cacheProfileData(data)
    }

    private func restoreCachedProfileIfNeeded() {
        guard let cached = UserDefaults.standard.dictionary(forKey: profileCacheKey), !cached.isEmpty else { return }
        applyUserData(cached)
    }

    private func cacheProfileData(_ data: [String: Any]) {
        var payload: [String: Any] = [:]
        payload["username"] = data["username"] as? String
        payload["display_name"] = data["display_name"] as? String
        payload["email"] = data["email"] as? String
        payload["bio"] = data["bio"] as? String
        payload["avatar_url"] = UserRecordAvatarResolver.url(from: data)
        payload["is_trusted_gamer"] = data["is_trusted_gamer"] as? Bool
        payload["favorite_play_style"] = data["favorite_play_style"] as? String
        payload["favorite_platform"] = data["favorite_platform"] as? String
        payload["favorite_genre"] = data["favorite_genre"] as? String
        payload["favorite_franchise"] = data["favorite_franchise"] as? String
        payload["reward_theme"] = data["reward_theme"] as? String
        payload["sections_order"] = data["sections_order"] as? [String]
        payload["pinned_list_ids"] = data["pinned_list_ids"] as? [String]
        payload["favorite_game"] = data["favorite_game"] as? [String: Any]
        payload["watchlist_games"] = data["watchlist_games"] as? [[String: Any]]
        if let plistPayload = propertyListValue(from: payload) {
            UserDefaults.standard.set(plistPayload, forKey: profileCacheKey)
        }
    }

    private func restoreCachedSnapshotIfNeeded() {
        guard let snapshot = Self.snapshotCache[userId] else { return }
        followers = snapshot.followers
        following = snapshot.following
        avgUserRating = snapshot.avgUserRating
        avgUserRatingCount = snapshot.avgUserRatingCount
        rewardXP = snapshot.rewardXP
        displayedRewardXP = snapshot.displayedRewardXP
        rewardTheme = RewardService.Theme(rawValue: snapshot.rewardThemeRaw) ?? rewardTheme
        recentLogs = snapshot.recentLogs
        dailyObjectives = snapshot.dailyObjectives
        weeklyObjectives = snapshot.weeklyObjectives
        achievementStates = snapshot.achievementStates
        achievementCatalog = snapshot.achievementCatalog
        secretCatalog = snapshot.secretCatalog
        discoveredSecrets = snapshot.discoveredSecrets
        nextHintSecret = snapshot.nextHintSecret
    }

    private func cacheSnapshot() {
        Self.snapshotCache[userId] = SnapshotCache(
            followers: followers,
            following: following,
            avgUserRating: avgUserRating,
            avgUserRatingCount: avgUserRatingCount,
            rewardXP: rewardXP,
            displayedRewardXP: displayedRewardXP,
            rewardThemeRaw: rewardTheme.rawValue,
            recentLogs: recentLogs,
            dailyObjectives: dailyObjectives,
            weeklyObjectives: weeklyObjectives,
            achievementStates: achievementStates,
            achievementCatalog: achievementCatalog,
            secretCatalog: secretCatalog,
            discoveredSecrets: discoveredSecrets,
            nextHintSecret: nextHintSecret
        )
    }

    private func propertyListValue(from value: Any) -> Any? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let double as Double:
            return double
        case let array as [Any]:
            return array.compactMap { propertyListValue(from: $0) }
        case let dict as [String: Any]:
            var sanitized: [String: Any] = [:]
            for (key, nestedValue) in dict {
                if let cleaned = propertyListValue(from: nestedValue) {
                    sanitized[key] = cleaned
                }
            }
            return sanitized
        case Optional<Any>.none:
            return nil
        default:
            return nil
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
                self.cacheSnapshot()
            }
        db.collection("follows")
            .whereField("follower_id", isEqualTo: userId)
            .getDocuments { snap, _ in
                self.following = snap?.documents.count ?? self.following
                self.cacheSnapshot()
            }
    }

    private func toggleTrustedGamer() {
        guard isFounder else { return }
        isUpdatingTrusted = true
        let next = !isTrustedGamer
        let actor = Auth.auth().currentUser?.uid ?? ""
        db.collection("users").document(userId).setData([
            "is_trusted_gamer": next
        ], merge: true) { err in
            DispatchQueue.main.async {
                isUpdatingTrusted = false
                if err == nil {
                    isTrustedGamer = next
                    if !actor.isEmpty {
                        self.db.collection("trusted_role_events").document().setData([
                            "actor_uid": actor,
                            "target_uid": self.userId,
                            "set_to": next,
                            "created_at": FieldValue.serverTimestamp()
                        ], merge: false)
                    }
                }
            }
        }
    }

    private func loadRewardState() {
        rewardTheme = RewardService.shared.currentTheme(for: userId)
        db.collection("user_stats").document(userId).getDocument { snap, _ in
            let data = snap?.data() ?? [:]
            let xp = (data["reward_xp_total"] as? Int)
                ?? (data["reward_xp_total"] as? NSNumber)?.intValue
                ?? ((data["reward_state"] as? [String: Any])?["total_xp"] as? Int)
                ?? (((data["reward_state"] as? [String: Any])?["total_xp"] as? NSNumber)?.intValue)
                ?? 0
            let parsedEvents = parseRewardEvents(data["reward_events"] as? [[String: Any]] ?? [])
            DispatchQueue.main.async {
                let pendingTotal = self.pendingRewardAnimationTotal ?? 0
                let resolvedXP = self.isAnimatingRewardXP ? max(self.rewardXP, xp, pendingTotal) : max(xp, pendingTotal)
                rewardXP = max(0, resolvedXP)
                if !isAnimatingRewardXP && pendingRewardAnimationTotal == nil {
                    displayedRewardXP = max(0, resolvedXP)
                }
                rewardEvents = parsedEvents
                self.cacheSnapshot()
            }
        }
    }

    private var canPlayRewardAnimation: Bool {
        isMe
            && selectedPrimarySection == .rewards
            && !showRewardHistoryOverlay
            && !showAchievementBoardOverlay
            && !showSecretHintOverlay
            && !showSecretQuestListOverlay
            && !showTileInfoOverlay
    }

    private func applyOptimisticRewardGrant(delta: Int) {
        guard delta > 0 else { return }
        let baseline = max(rewardXP, displayedRewardXP, pendingRewardAnimationTotal ?? 0)
        let optimisticTotal = baseline + delta
        recentOptimisticRewardSignature = "\(optimisticTotal):\(delta)"
        recentOptimisticRewardAt = Date()
        queueOrApplyRewardUpdate(total: optimisticTotal, delta: delta)
    }

    private func queueOrApplyRewardUpdate(total: Int, delta: Int) {
        let clampedTotal = max(0, total)
        rewardXP = clampedTotal

        guard delta > 0 else {
            if !isAnimatingRewardXP && pendingRewardAnimationTotal == nil {
                displayedRewardXP = clampedTotal
                cacheSnapshot()
            }
            return
        }

        if canPlayRewardAnimation && !isAnimatingRewardXP {
            handleRewardXPUpdate(total: clampedTotal, delta: delta)
        } else {
            pendingRewardAnimationTotal = clampedTotal
            pendingRewardAnimationDelta += delta
        }
    }

    private func playPendingRewardAnimationIfPossible() {
        guard canPlayRewardAnimation, !isAnimatingRewardXP else { return }
        guard let total = pendingRewardAnimationTotal, pendingRewardAnimationDelta > 0 else {
            if canPlayRewardAnimation, let total = pendingRewardAnimationTotal, pendingRewardAnimationDelta <= 0 {
                displayedRewardXP = max(displayedRewardXP, total)
                pendingRewardAnimationTotal = nil
                cacheSnapshot()
            }
            return
        }

        let delta = pendingRewardAnimationDelta
        pendingRewardAnimationTotal = nil
        pendingRewardAnimationDelta = 0
        handleRewardXPUpdate(total: total, delta: delta)
    }

    private func handleRewardXPUpdate(total: Int, delta: Int) {
        let clampedTotal = max(0, total)
        rewardXP = clampedTotal
        if delta <= 0 {
            if !isAnimatingRewardXP {
                displayedRewardXP = clampedTotal
                cacheSnapshot()
            }
            return
        }

        let start = max(0, displayedRewardXP)
        let end = clampedTotal
        isAnimatingRewardXP = true
        rewardDeltaToastIcon = "arrow.up.circle.fill"
        rewardDeltaToast = "+\(delta) \(rewardTheme.displayUnit)"

        let steps = max(10, min(28, delta))
        for step in 1...steps {
            let delay = 0.052 * Double(step)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let progress = Double(step) / Double(steps)
                displayedRewardXP = start + Int(round(Double(end - start) * progress))
                if step == steps {
                    isAnimatingRewardXP = false
                    playPendingRewardAnimationIfPossible()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            rewardDeltaToast = nil
                            self.cacheSnapshot()
                        }
                    }
                }
            }
        }
    }

    private func loadSelectedSectionData(force: Bool) {
        switch selectedPrimarySection {
        case .rewards:
            if force || shouldRefreshGamificationState {
                loadGamificationState()
            }
        case .saved:
            if force || !hasLoadedSavedSection {
                loadUser()
            }
        case .references:
            if force || !hasLoadedReferencesSection {
                loadReferences()
            }
        case .lists:
            if force || !hasLoadedListsSection {
                loadLists()
            }
        case .recent:
            if force || !hasLoadedRecentSection {
                loadRecentLogs()
            }
        }
    }

    private var shouldRefreshGamificationState: Bool {
        let now = Date()
        guard isMe else {
            return dailyObjectives == nil || weeklyObjectives == nil || achievementCatalog.isEmpty
        }
        return dailyObjectives == nil
            || weeklyObjectives == nil
            || achievementCatalog.isEmpty
            || dailyObjectives?.periodKey != ObjectiveService.dayKey(for: now)
            || weeklyObjectives?.periodKey != ObjectiveService.weekKey(for: now)
    }

    private func refreshTimeSensitiveProfileData() {
        if selectedPrimarySection == .rewards || shouldRefreshGamificationState {
            loadGamificationState()
            if isMe {
                loadRewardState()
            }
        }
    }

    private func loadGamificationState() {
        if isMe {
            let quickLevel = max(1, RewardService.levelInfo(for: max(rewardXP, displayedRewardXP)).level)
            let now = Date()
            if dailyObjectives == nil || dailyObjectives?.periodKey != ObjectiveService.dayKey(for: now) {
                dailyObjectives = ObjectiveService.shared.quickAssignment(
                    userId: userId,
                    window: .daily,
                    date: now,
                    userLevel: quickLevel
                )
            }
            if weeklyObjectives == nil || weeklyObjectives?.periodKey != ObjectiveService.weekKey(for: now) {
                weeklyObjectives = ObjectiveService.shared.quickAssignment(
                    userId: userId,
                    window: .weekly,
                    date: now,
                    userLevel: quickLevel
                )
            }
            cacheSnapshot()

            ObjectiveService.shared.ensureDailyObjectives(userId: userId) { result in
                DispatchQueue.main.async {
                    if case .success(let assignment) = result {
                        self.dailyObjectives = assignment
                        self.cacheSnapshot()
                    } else {
                        self.cacheSnapshot()
                    }
                }
            }
            ObjectiveService.shared.ensureWeeklyObjectives(userId: userId) { result in
                DispatchQueue.main.async {
                    if case .success(let assignment) = result {
                        self.weeklyObjectives = assignment
                        self.cacheSnapshot()
                    } else {
                        self.cacheSnapshot()
                    }
                }
            }
        } else {
            dailyObjectives = nil
            weeklyObjectives = nil
        }
        AchievementService.shared.fetchAchievementCatalog { catalog in
            DispatchQueue.main.async {
                self.achievementCatalog = catalog
                self.cacheSnapshot()
            }
        }
        AchievementService.shared.fetchUserAchievements(userId: userId) { states in
            DispatchQueue.main.async {
                var mapped: [String: UserAchievementState] = [:]
                for state in states {
                    let existing = mapped[state.achievementId]
                    if existing == nil {
                        mapped[state.achievementId] = state
                        continue
                    }
                    let existingDate = existing?.completedAt?.dateValue() ?? existing?.revealedAt?.dateValue() ?? .distantPast
                    let newDate = state.completedAt?.dateValue() ?? state.revealedAt?.dateValue() ?? .distantPast
                    if newDate >= existingDate {
                        mapped[state.achievementId] = state
                    }
                }
                self.achievementStates = mapped
                self.cacheSnapshot()
            }
        }
        SecretUnlockService.shared.fetchSecretCatalog { catalog in
            DispatchQueue.main.async {
                self.secretCatalog = catalog
                self.cacheSnapshot()
            }
        }
        SecretUnlockService.shared.fetchUserSecrets(userId: userId) { states in
            DispatchQueue.main.async {
                self.discoveredSecrets = states
                if states.isEmpty {
                    self.nextHintSecret = nil
                }
                self.cacheSnapshot()
            }
        }
        SecretUnlockService.shared.fetchNextHintSecret(userId: userId) { secret in
            DispatchQueue.main.async {
                self.nextHintSecret = secret
                self.cacheSnapshot()
            }
        }
    }

    private func gamificationDayKey(for date: Date) -> String {
        ObjectiveService.dayKey(for: date)
    }

    private func gamificationWeekKey(for date: Date) -> String {
        ObjectiveService.weekKey(for: date)
    }

    private func resetGamificationData() {
        guard isMe, isFounder else { return }

        let statsRef = db.collection("user_stats").document(userId)
        let metricsRef = db.collection("user_metrics").document(userId)

        statsRef.getDocument { snap, _ in
            let currentVersion = (snap?.data()?["reward_reset_version"] as? Int)
                ?? (snap?.data()?["reward_reset_version"] as? NSNumber)?.intValue
                ?? 0
            let nextVersion = currentVersion + 1

            statsRef.setData([
                "reward_xp_total": 0,
                "reward_level": 1,
                "reward_events": [],
                "reward_reset_version": nextVersion,
                "reward_state": [
                    "total_xp": 0,
                    "level": 1,
                    "normal_xp_earned_today": 0,
                    "normal_xp_day_key": self.gamificationDayKey(for: Date())
                ],
                "reward_updated_at": FieldValue.serverTimestamp()
            ], merge: true)

            metricsRef.setData([
                "user_id": self.userId,
                "rated_games_count": 0,
                "reviewed_games_count": 0,
                "log_actions_count": 0,
                "saved_games_count": 0,
                "list_items_added_count": 0,
                "lists_created_count": 0,
                "likes_given_count": 0,
                "comments_written_count": 0,
                "follows_count": 0,
                "flagged_games_count": 0,
                "view_actions_count": 0,
                "perfect_ten_ratings_count": 0,
                "double_take_ratings_count": 0,
                "rabid_rater_best_count": 0,
                "retro_saved_games_count": 0,
                "ratings_by_day": [:],
                "retro_reviews_count": 0,
                "retro_games_logged_count": 0,
                "reviews_by_day": [:],
                "saves_by_day": [:],
                "list_adds_by_day": [:],
                "list_creations_by_day": [:],
                "logging_actions_by_day": [:],
                "action_categories_by_day": [:],
                "objective_completions_by_day": [:],
                "daily_objective_completions_by_day": [:],
                "quest_completions_by_day": [:],
                "collection_habit_sessions_completed": 0,
                "updated_at": FieldValue.serverTimestamp()
            ], merge: true)

            ObjectiveService.shared.resetDailyObjectives(userId: self.userId) { result in
                DispatchQueue.main.async {
                    if case .success(let assignment) = result {
                        self.dailyObjectives = assignment
                        self.cacheSnapshot()
                    }
                }
            }

            ObjectiveService.shared.resetWeeklyObjectives(userId: self.userId) { result in
                DispatchQueue.main.async {
                    if case .success(let assignment) = result {
                        self.weeklyObjectives = assignment
                        self.cacheSnapshot()
                    }
                }
            }

            self.db.collection("user_achievements")
                .whereField("user_id", isEqualTo: self.userId)
                .getDocuments { snap, _ in
                    (snap?.documents ?? []).forEach { doc in
                        let achievementId = (doc.data()["achievement_id"] as? String) ?? doc.documentID
                        doc.reference.setData([
                            "user_id": self.userId,
                            "achievement_id": achievementId,
                            "state": AchievementTileState.hidden.rawValue,
                            "progress_current": 0,
                            "progress_target": 0,
                            "xp_granted": 0,
                            "completed_at": FieldValue.delete(),
                            "revealed_at": FieldValue.delete()
                        ], merge: true)
                    }
                    DispatchQueue.main.async {
                        self.achievementStates = [:]
                    }
                }

            self.db.collection("user_secret_unlocks")
                .whereField("user_id", isEqualTo: self.userId)
                .getDocuments { snap, _ in
                    (snap?.documents ?? []).forEach { doc in
                        doc.reference.setData([
                            "user_id": self.userId,
                            "claimed": false,
                            "xp_granted": 0,
                            "unlockables_granted": [],
                            "discovery_order": FieldValue.delete(),
                            "discovered_at": FieldValue.delete()
                        ], merge: true)
                    }
                    DispatchQueue.main.async {
                        self.discoveredSecrets = []
                        self.nextHintSecret = nil
                        self.cacheSnapshot()
                    }
                }

            DispatchQueue.main.async {
                self.rewardXP = 0
                self.rewardEvents = []
                NotificationCenter.default.post(
                    name: .gamificationUpdated,
                    object: nil,
                    userInfo: ["user_id": self.userId]
                )
                self.loadGamificationState()
            }
        }
    }

    private func revealQuestBoardForFounder() {
        guard isMe, isFounder else { return }

        AchievementService.shared.fetchAchievementCatalog { catalog in
            AchievementService.shared.fetchUserAchievements(userId: userId) { states in
                let stateByAchievement = Dictionary(uniqueKeysWithValues: states.map { ($0.achievementId, $0) })
                let batch = db.batch()

                for definition in catalog where definition.active && !definition.isSecret {
                    let ref = db.collection("user_achievements").document("\(userId)_\(definition.id)")
                    let existing = stateByAchievement[definition.id]
                    let resolvedState: AchievementTileState = (existing?.state == .completed) ? .completed : .hinted

                    var payload: [String: Any] = [
                        "user_id": userId,
                        "achievement_id": definition.id,
                        "state": resolvedState.rawValue,
                        "progress_current": existing?.progressCurrent ?? 0,
                        "progress_target": max(existing?.progressTarget ?? 0, definition.progressTarget),
                        "claimed": existing?.claimed ?? false,
                        "xp_granted": existing?.xpGranted ?? 0,
                        "unlockables_granted": existing?.unlockablesGranted ?? []
                    ]

                    if existing?.revealedAt == nil {
                        payload["revealed_at"] = Timestamp(date: Date())
                    }
                    if let completedAt = existing?.completedAt {
                        payload["completed_at"] = completedAt
                    }

                    batch.setData(payload, forDocument: ref, merge: true)
                }

                batch.commit { _ in
                    DispatchQueue.main.async {
                        loadGamificationState()
                    }
                }
            }
        }
    }

    private func parseRewardEvents(_ raw: [[String: Any]]) -> [(id: String, type: String, delta: Int, at: Date)] {
        let mapped: [(id: String, type: String, delta: Int, at: Date)] = raw.compactMap { item in
            let id = (item["id"] as? String) ?? UUID().uuidString
            let type = (item["type"] as? String) ?? "action"
            let delta = (item["delta"] as? Int)
                ?? (item["delta"] as? NSNumber)?.intValue
                ?? 0
            let atDate: Date
            if let ts = item["at"] as? Timestamp {
                atDate = ts.dateValue()
            } else {
                atDate = .distantPast
            }
            guard delta > 0 else { return nil }
            return (id, type, delta, atDate)
        }
        return mapped.sorted { $0.at > $1.at }
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
                self.hasLoadedRecentSection = true
                self.cacheSnapshot()

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

    private func loadReferences() {
        guard isMe else {
            references = []
            hasLoadedReferencesSection = true
            return
        }
        let cachedRaw = UserDefaults.standard.array(forKey: glReferenceCacheKey(for: userId)) as? [[String: Any]] ?? []
        let cached = glDeserializeReferencePayloadsFromCache(cachedRaw)
        if !cached.isEmpty {
            self.references = cached.compactMap { data in
                guard let id = data["id"] as? String,
                      let logId = data["log_id"] as? String,
                      let gameId = data["game_id"] as? Int ?? (data["game_id"] as? NSNumber)?.intValue
                else { return nil }
                return LogReferenceEntry(
                    id: id,
                    userId: data["user_id"] as? String ?? self.userId,
                    logId: logId,
                    logOwnerId: data["log_owner_id"] as? String ?? "",
                    gameId: gameId,
                    gameName: {
                        let value = (data["game_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return value.isEmpty ? "Game" : value
                    }(),
                    authorName: {
                        let value = (data["author_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return value.isEmpty ? "User" : value
                    }(),
                    authorAvatarUrl: data["author_avatar_url"] as? String,
                    coverId: data["cover_id"] as? String,
                    rating: data["rating"] as? Double ?? (data["rating"] as? NSNumber)?.doubleValue,
                    reviewPreview: (data["review_preview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    addedAt: data["added_at"] as? Timestamp
                )
            }.sorted { lhs, rhs in
                (lhs.addedAt?.dateValue() ?? .distantPast) > (rhs.addedAt?.dateValue() ?? .distantPast)
            }
        }
        db.collection("users").document(userId).getDocument { snap, _ in
            let raw = snap?.data()?["log_references"] as? [[String: Any]] ?? []
            UserDefaults.standard.set(glSerializeReferencePayloadsForCache(raw), forKey: glReferenceCacheKey(for: self.userId))
            self.references = raw.compactMap { data in
                guard let id = data["id"] as? String,
                      let logId = data["log_id"] as? String,
                      let gameId = data["game_id"] as? Int ?? (data["game_id"] as? NSNumber)?.intValue
                else { return nil }
                return LogReferenceEntry(
                    id: id,
                    userId: data["user_id"] as? String ?? self.userId,
                    logId: logId,
                    logOwnerId: data["log_owner_id"] as? String ?? "",
                    gameId: gameId,
                    gameName: {
                        let value = (data["game_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return value.isEmpty ? "Game" : value
                    }(),
                    authorName: {
                        let value = (data["author_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return value.isEmpty ? "User" : value
                    }(),
                    authorAvatarUrl: data["author_avatar_url"] as? String,
                    coverId: data["cover_id"] as? String,
                    rating: data["rating"] as? Double ?? (data["rating"] as? NSNumber)?.doubleValue,
                    reviewPreview: (data["review_preview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    addedAt: data["added_at"] as? Timestamp
                )
            }.sorted { lhs, rhs in
                (lhs.addedAt?.dateValue() ?? .distantPast) > (rhs.addedAt?.dateValue() ?? .distantPast)
            }
            self.hasLoadedReferencesSection = true
        }
    }

    private func openReference(_ reference: LogReferenceEntry) {
        db.collection("game_logs").document(reference.logId).getDocument { snap, _ in
            guard let data = snap?.data(),
                  let log = Self.parseGameLog(docIdFallback: reference.logId, data: data) else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .openGlobalGameLogPreviewRequested,
                    object: log,
                    userInfo: [
                        "game_name": reference.gameName,
                        "username": reference.authorName,
                        "focus_comment": false
                    ]
                )
            }
        }
    }

    private func referenceToDict(_ reference: LogReferenceEntry) -> [String: Any] {
        var payload: [String: Any] = [
            "id": reference.id,
            "user_id": reference.userId,
            "log_id": reference.logId,
            "log_owner_id": reference.logOwnerId,
            "game_id": reference.gameId,
            "game_name": reference.gameName,
            "added_at": reference.addedAt ?? Timestamp(date: Date())
        ]
        if let authorAvatarUrl = reference.authorAvatarUrl, !authorAvatarUrl.isEmpty {
            payload["author_avatar_url"] = authorAvatarUrl
        }
        if let coverId = reference.coverId, !coverId.isEmpty {
            payload["cover_id"] = coverId
        }
        if let rating = reference.rating {
            payload["rating"] = rating
        }
        if let reviewPreview = reference.reviewPreview, !reviewPreview.isEmpty {
            payload["review_preview"] = reviewPreview
        }
        payload["author_name"] = reference.authorName
        return payload
    }

    private func removeReference(_ reference: LogReferenceEntry) {
        guard isMe else { return }
        let userRef = db.collection("users").document(userId)
        var updated = references
        updated.removeAll { $0.id == reference.id }
        references = updated
        let payload = updated.map { referenceToDict($0) }
        UserDefaults.standard.set(glSerializeReferencePayloadsForCache(payload), forKey: glReferenceCacheKey(for: userId))
        userRef.setData(["log_references": payload], merge: true)
    }

    private func openExternalProfileLink(_ urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private func creatorLinkIcon(assetName: String, fallbackSystemName: String, color: Color) -> some View {
        if let image = UIImage(named: assetName) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
        } else {
            switch assetName {
            case "icon_youtube":
                SocialBrandIconView(platform: "youtube")
            case "icon_tiktok":
                SocialBrandIconView(platform: "tiktok")
            case "icon_twitch":
                SocialBrandIconView(platform: "twitch")
            default:
                Image(systemName: fallbackSystemName)
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
            }
        }
    }

    private var sectionInfoOverlay: some View {
        return ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { showSectionInfoOverlay = false }

            sectionInfoOverlayCard
        }
    }

    private var sectionInfoOverlayCard: some View {
        let cardWidth = min(UIScreen.main.bounds.width - 32, 360)
        let cardHeight = min(UIScreen.main.bounds.height - 130, 380)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button {
                    showSectionInfoOverlay = false
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
            }

            Text(sectionInfoTitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(ColorTheme.text)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionInfoVisualCard

                    Text("These sections help organize your profile into progression, saved titles, private references, recent activity, and public curation.")
                        .font(.footnote)
                        .foregroundColor(ColorTheme.subtext)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(width: cardWidth, height: cardHeight)
        .background(sectionInfoOverlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var sectionInfoVisualCard: some View {
        HStack(spacing: 12) {
            if !(sectionInfoSystemImage.isEmpty && sectionInfoAssetName == nil) {
                sectionInfoIconView
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text((sectionInfoSystemImage.isEmpty && sectionInfoAssetName == nil) ? "What this tab is for" : "Look for this icon on game cards")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Text(sectionInfoText)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ColorTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ColorTheme.accent.opacity(0.55), lineWidth: 1)
        )
    }

    private var sectionInfoIconView: AnyView {
        if sectionInfoSystemImage.isEmpty && sectionInfoAssetName == nil {
            return AnyView(EmptyView())
        }
        if let asset = sectionInfoAssetName {
            return AnyView(
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(ColorTheme.accent)
            )
        } else {
            return AnyView(
                Image(systemName: sectionInfoSystemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(ColorTheme.accent)
            )
        }
    }

    private var sectionInfoOverlayBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(ColorTheme.background)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ColorTheme.separator.opacity(0.75), lineWidth: 1)
            )
    }

    private func sectionHeaderWithInfo(title: String, info: String, systemImage: String = "info.circle", assetName: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundColor(ColorTheme.text)
            Button {
                sectionInfoTitle = title
                sectionInfoText = info
                sectionInfoSystemImage = systemImage
                sectionInfoAssetName = assetName
                showSectionInfoOverlay = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
            }
            .buttonStyle(.plain)
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
                    self.cacheSnapshot()
                } else {
                    self.avgUserRatingCount = ratings.count
                    self.avgUserRating = ratings.reduce(0, +) / Double(ratings.count)
                    self.cacheSnapshot()
                }
            }
    }

    private func loadLists() {
        DispatchQueue.main.async {
            self.isLoadingLists = true
        }
        var query: Query = db.collection("lists")
            .whereField("owner_id", isEqualTo: userId)
            .order(by: "updated_at", descending: true)
            .limit(to: 20)

        // Non-owners should only ever see public lists on profile.
        if !isMe {
            query = db.collection("lists")
                .whereField("owner_id", isEqualTo: userId)
                .whereField("is_public", isEqualTo: true)
                .order(by: "updated_at", descending: true)
                .limit(to: 20)
        }

        query.getDocuments { snap, _ in
            let fetchedLists: [UserListLite] = (snap?.documents ?? []).compactMap { d -> UserListLite? in
                let data = d.data()
                let id = (data["id"] as? String) ?? d.documentID
                let title = (data["title"] as? String) ?? "Untitled"
                let count = (data["item_count"] as? Int) ?? 0
                let isPublic = (data["is_public"] as? Bool) ?? true
                if !self.isMe && !isPublic { return nil }
                let updatedAt = data["updated_at"] as? Timestamp
                let type = (data["type"] as? String) ?? "regular"
                let previewIds = data["preview_cover_ids"] as? [String]
                let tierLabels = data["tier_labels"] as? [String]
                let tierColors = data["tier_colors"] as? [String]
                let tierTextColors = data["tier_text_colors"] as? [String]
                return UserListLite(
                    id: id, title: title, itemCount: count, isPublic: isPublic,
                    updatedAt: updatedAt, type: type,
                    previewCoverIds: previewIds, rawItemsArray: nil,
                    tierLabels: tierLabels, tierColors: tierColors, tierTextColors: tierTextColors
                )
            }

            DispatchQueue.main.async {
                self.lists = fetchedLists
                self.isLoadingLists = false
                self.hasLoadedListsSection = true

                // Load previews
                self.listPreviewCovers.removeAll()
                for lid in fetchedLists.map({ $0.id }) {
                    if let cached = fetchedLists.first(where: { $0.id == lid })?.previewCoverIds, !cached.isEmpty {
                        self.listPreviewCovers[lid] = Array(cached.prefix(4))
                    } else {
                        self.loadPreviewForList(listId: lid)
                    }
                }
            }
        }
    }

    private func togglePinnedList(_ listId: String) {
        guard isMe, !isUpdatingPinnedLists.contains(listId) else { return }
        isUpdatingPinnedLists.insert(listId)

        let wasPinned = pinnedListIds.contains(listId)
        if wasPinned {
            pinnedListIds.remove(listId)
        } else {
            pinnedListIds.insert(listId)
        }

        let pinnedArray = Array(pinnedListIds)
        db.collection("users").document(userId).setData([
            "pinned_list_ids": pinnedArray
        ], merge: true) { error in
            DispatchQueue.main.async {
                self.isUpdatingPinnedLists.remove(listId)
                if let error {
                    if wasPinned {
                        self.pinnedListIds.insert(listId)
                    } else {
                        self.pinnedListIds.remove(listId)
                    }
                    os_log("Could not update pinned lists: %{public}@", error.localizedDescription)
                    Haptics.play(.error)
                } else {
                    Haptics.softImpact()
                    if var cached = UserDefaults.standard.dictionary(forKey: self.profileCacheKey) {
                        cached["pinned_list_ids"] = Array(self.pinnedListIds)
                        if let plistPayload = self.propertyListValue(from: cached) {
                            UserDefaults.standard.set(plistPayload, forKey: self.profileCacheKey)
                        }
                    }
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
        igdb.fetchGamesByIds(ids: slice) { result in
            switch result {
            case .success(let games):
                let fetched = games.compactMap { $0.cover?.imageId }
                DispatchQueue.main.async {
                    completion(Array(fetched.prefix(take)))
                }
            case .failure:
                DispatchQueue.main.async {
                    completion([])
                }
            }
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
        let containsSpoilers = data["review_contains_spoilers"] as? Bool ?? false
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
            rating: rating, review: review, containsSpoilers: containsSpoilers, isLiked: isLiked, cover: cover
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
        let defaultTierTextColors = ["#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF"]
        let tierLabels = (listType == .tiered) ? (lite.tierLabels ?? defaultTierLabels) : []
        let tierColors = (listType == .tiered) ? (lite.tierColors ?? defaultTierColors) : []
        let tierTextColors = (listType == .tiered) ? (lite.tierTextColors ?? defaultTierTextColors) : []

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
            tierColors: tierColors,
            tierTextColors: tierTextColors
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
        dict["added_at"] = Timestamp(date: watchlistAddedAt[game.id] ?? Date())
        return dict
    }

    // MARK: - Saved Games + Drag to List

    private func removeFromSavedGames(_ game: Game) {
        watchlist.removeAll { $0.id == game.id }
        watchlistAddedAt.removeValue(forKey: game.id)
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

private struct RewardObjectiveCardView: View {
    let title: String
    let assignment: ObjectiveAssignment?
    let emptyText: String
    let maxVisible: Int
    let claimingIDs: Set<String>
    let onClaim: (ObjectiveProgressEntry, ObjectiveAssignment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                if let assignment {
                    let completed = assignment.objectives.filter(\.completed).count
                    Text("\(completed)/\(assignment.objectives.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }
            }

            Text(assignment?.window == .weekly ? ObjectiveService.nextWeeklyResetText() : ObjectiveService.nextDailyResetText())
                .font(.caption2)
                .foregroundColor(ColorTheme.subtext)

            if let assignment, !assignment.objectives.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(assignment.objectives.prefix(maxVisible)), id: \.id) { objective in
                        RewardObjectiveRowView(
                            objective: objective,
                            isClaiming: claimingIDs.contains(objective.id)
                        ) {
                            onClaim(objective, assignment)
                        }
                    }
                }
            } else {
                Text(emptyText)
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
    }
}

private struct RewardObjectiveRowView: View {
    let objective: ObjectiveProgressEntry
    let isClaiming: Bool
    let onClaim: () -> Void

    private var isClaimable: Bool {
        objective.completed && !objective.claimed
    }

    private var progressRatio: CGFloat {
        CGFloat(min(1, max(0, Double(objective.progress) / Double(max(1, objective.target)))))
    }

    var body: some View {
        Button {
            guard isClaimable, !isClaiming else { return }
            onClaim()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(objective.title)
                        .font(.caption.weight(.medium))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    trailingStatus
                }

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(ColorTheme.separator.opacity(0.18))
                        .frame(height: 6)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: [ColorTheme.accent, ColorTheme.xpGreen],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progressRatio, height: 6)
                    }
                    .frame(height: 6)
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface.opacity(objective.claimed ? 0.75 : 1)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(objective.completed ? ColorTheme.accent : ColorTheme.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isClaimable || isClaiming)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if objective.completed {
            if objective.claimed {
                Text("Complete")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.subtext)
            } else if isClaiming {
                ProgressView()
                    .tint(ColorTheme.accent)
                    .scaleEffect(0.7)
            } else {
                Text("Claim +\(objective.xpReward)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
            }
        } else {
            Text("\(objective.progress)/\(objective.target)")
                .font(.caption2.weight(.semibold))
                .foregroundColor(ColorTheme.subtext)
        }
    }
}

private struct RewardsSectionView: View {
    let rewardProgressCard: AnyView
    let achievementPreviewCard: AnyView
    let secretQuestPreviewCard: AnyView
    let dailyObjectives: ObjectiveAssignment?
    let weeklyObjectives: ObjectiveAssignment?
    let claimingObjectiveIDs: Set<String>
    @Binding var pageSelection: Int?
    let onClaimObjective: (ObjectiveProgressEntry, ObjectiveAssignment) -> Void
    @State private var showLoggingInfoOverlay: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            rewardProgressCard
            rewardsPageTabs
            rewardsPager
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay {
            if showLoggingInfoOverlay {
                loggingInfoOverlay
            }
        }
    }

    private var pagerHeight: CGFloat {
        min(max(UIScreen.main.bounds.height * 0.36, 280), 360)
    }

    private var rewardsPager: some View {
        TabView(selection: $pageSelection) {
            rewardsPage {
                achievementPreviewCard
                secretQuestPreviewCard
            }
            .tag(0 as Int?)

            rewardsPage {
                activeChallengesCard
            }
            .tag(1 as Int?)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pagerHeight)
    }

    private func rewardsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 2)
    }

    private var rewardsPageTabs: some View {
        HStack(spacing: 10) {
            pagerTab(index: 0, title: "Quests", icon: "square.grid.3x3.fill")
            pagerTab(index: 1, title: "Challenges", icon: "flag.checkered.2.crossed")
        }
        .padding(.top, 2)
    }

    private func pagerTab(index: Int, title: String, icon: String) -> some View {
        let isSelected = (pageSelection ?? 0) == index
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                pageSelection = index
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundColor(isSelected ? ColorTheme.accent : ColorTheme.subtext)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? ColorTheme.black : ColorTheme.background.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? ColorTheme.accent : ColorTheme.separator, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var activeChallengesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Challenges")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                }
                Button {
                    showLoggingInfoOverlay = true
                    Haptics.tap()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(ColorTheme.background.opacity(0.65)))
                }
                .buttonStyle(.plain)
                Spacer()
            }

            challengeSection(title: "Daily", assignment: dailyObjectives, emptyText: "No daily challenges yet.", maxVisible: 1)
            challengeSection(title: "Weekly", assignment: weeklyObjectives, emptyText: "No weekly challenge yet.", maxVisible: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private var loggingInfoOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { showLoggingInfoOverlay = false }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("What “Logging” Means")
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Button {
                        showLoggingInfoOverlay = false
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }

                Text("In GamerLnd, logging a game means doing any combination of the actions below.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    loggingInfoRow("Rate a game")
                    loggingInfoRow("Write a review")
                    loggingInfoRow("Save a game")
                    loggingInfoRow("Add a game to a list")
                }

                Text("So when a challenge mentions logging, logged, or logging a game, it refers to those actions.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                Text("When a challenge is completed, its XP can be claimed as a reward right from the Challenges section.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: min(UIScreen.main.bounds.width - 36, 340))
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ColorTheme.background)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
            )
        }
    }

    private func loggingInfoRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.accent)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(ColorTheme.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator.opacity(0.85), lineWidth: 1))
    }

    private func challengeSection(title: String, assignment: ObjectiveAssignment?, emptyText: String, maxVisible: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                if let assignment {
                    let completed = assignment.objectives.filter(\.completed).count
                    Text("\(completed)/\(assignment.objectives.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }
            }

            Text(assignment?.window == .weekly ? ObjectiveService.nextWeeklyResetText() : ObjectiveService.nextDailyResetText())
                .font(.caption2)
                .foregroundColor(ColorTheme.subtext)

            if let assignment, !assignment.objectives.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(assignment.objectives.prefix(maxVisible)), id: \.id) { objective in
                        RewardObjectiveRowView(
                            objective: objective,
                            isClaiming: claimingObjectiveIDs.contains(objective.id)
                        ) {
                            onClaimObjective(objective, assignment)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(ColorTheme.accent)
                        .scaleEffect(0.8)
                    Text("Refreshing challenges…")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.background.opacity(0.42)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator.opacity(0.8), lineWidth: 1))
    }
}

// MARK: - List Rectangle Card

private struct ListRectangleCard: View {
    let list: ProfileView.UserListLite
    let previewImageIds: [String]
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let previewSide: CGFloat
    let showTypeLabel: Bool
    let isPinned: Bool
    let showPinButton: Bool
    let isPinBusy: Bool
    let onTogglePin: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        if showPinButton {
                            Button {
                                onTogglePin()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(ColorTheme.surface)
                                        .frame(width: 28, height: 28)
                                        .overlay(Circle().stroke(isPinned ? ColorTheme.accent : ColorTheme.separator, lineWidth: 1))
                                    if isPinBusy {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .tint(ColorTheme.accent)
                                    } else {
                                        Image(systemName: isPinned ? "pin.fill" : "pin")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(isPinned ? ColorTheme.accent : ColorTheme.subtext)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded({}))
                        }
                        privacyCorner(isPublic: list.isPublic)
                    }
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
                    HStack(alignment: .top, spacing: 6) {
                        Text(list.title)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(2)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(ColorTheme.accent)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 2)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    if showTypeLabel {
                        Text(listTypeName(list.type))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.accent)
                    }
                    Text("\(list.itemCount) \(list.itemCount == 1 ? "game" : "games")")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                }
                .padding(10)
            }
        }
        .frame(maxWidth: cardWidth > 0 ? cardWidth : .infinity, minHeight: cardHeight, maxHeight: cardHeight)
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

    private func listTypeName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "tiered": return "Tiered"
        case "ranked": return "Ranked"
        default: return "Standard"
        }
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

    private let cardWidth: CGFloat? = nil
    private let cardHeight: CGFloat = 138
    private let coverCorner: CGFloat = 10
    private var accent: Color {
        if let r = log.rating, r > 0 { return ColorTheme.ratingBandColor(for: r) }
        return ColorTheme.separator
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.58), lineWidth: 1))

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    CompactAverageHeartIcon(avg: avg, count: count)
                }
            }
            .padding(.top, 10)
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                if let imgId = log.cover?.imageId {
                    GameCoverImage(id: imgId, preset: .custom(width: 93), cornerRadius: coverCorner)
                        .frame(width: 93, height: 124)
                        .overlay(
                            RoundedRectangle(cornerRadius: coverCorner)
                                .stroke(accent.opacity(0.72), lineWidth: 1.1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: coverCorner)
                        .fill(ColorTheme.separator.opacity(0.25))
                        .frame(width: 93, height: 124)
                        .overlay(
                            RoundedRectangle(cornerRadius: coverCorner)
                                .stroke(accent.opacity(0.72), lineWidth: 1.1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)

                    if let review = log.review, !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("“\(ContentModeration.displayReviewText(review))”")
                            .font(.caption)
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(2)
                    }

                    if let r = log.rating, r > 0 {
                        ratingHeartChip(value: r, size: 38)
                    }

                    Spacer(minLength: 2)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .frame(maxWidth: cardWidth ?? .infinity, minHeight: cardHeight, maxHeight: cardHeight)
    }
}

// MARK: - Compact GamerLnd Badge (reused)

private struct CompactAverageHeartIcon: View {
    let avg: Double?
    let count: Int

    var body: some View {
        Group {
            if let avg = avg, count > 0 {
                AverageHeartBadge(value: avg, size: 20)
            } else {
                EmptyView()
            }
        }
    }
}

private func ratingHeartChip(value: Double, size: CGFloat) -> some View {
    ZStack {
        PixelHeartIcon(
            color: ColorTheme.ratingBandColor(for: value),
            size: size,
            perfectScore: ColorTheme.isPerfectScore(value)
        )
        HeartValueText(text: formatRatingValue(value), size: size)
    }
}

private struct CompactGamerLndBadge: View {
    let avg: Double?
    let count: Int
    var body: some View {
        Group {
            if let avg = avg, count > 0 {
                AverageHeartBadge(value: avg, size: 16)
            } else {
                Image(systemName: "heart")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.surface))
            }
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
    let currentYouTubeURL: String
    let currentTwitchURL: String
    let currentTikTokURL: String

    @Binding var sectionsOrder: [ProfileView.SectionKind]

    var onSaved: (_ newDisplayName: String, _ newUsername: String, _ newBio: String, _ newAvatarUrl: String?, _ newYouTubeURL: String, _ newTwitchURL: String, _ newTikTokURL: String) -> Void
    var onReorderSaved: (_ newOrder: [ProfileView.SectionKind]) -> Void

    @Environment(\.dismiss) private var dismiss

    // Editable fields
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var avatarUrl: String? = nil
    @State private var youtubeURL: String = ""
    @State private var twitchURL: String = ""
    @State private var tiktokURL: String = ""

    // PhotosPicker
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImageData: Data? = nil
    @State private var showAvatarPolicyPrompt: Bool = false
    @State private var showAvatarPicker: Bool = false

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
                        .onChange(of: displayName) { _, newValue in
                            if newValue.count > ProfileIdentityValidator.maxDisplayNameLength {
                                displayName = String(newValue.prefix(ProfileIdentityValidator.maxDisplayNameLength))
                            }
                        }

                    HStack {
                        TextField("Username (unique)", text: $username)
                            .textInputAutocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: username) { _, newValue in
                                let sanitized = ProfileIdentityValidator.sanitizedHandleInput(newValue)
                                if sanitized != newValue {
                                    username = sanitized
                                }
                                if username.count > ProfileIdentityValidator.maxHandleLength {
                                    username = String(username.prefix(ProfileIdentityValidator.maxHandleLength))
                                }
                                usernameAvailable = nil
                                debounceUsernameCheck()
                            }

                        if let available = usernameAvailable {
                            Image(systemName: available ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundColor(available ? ColorTheme.accent : .red)
                        }
                    }

                    TextField(
                        "Bio",
                        text: Binding(
                            get: { bio },
                            set: { bio = String($0.prefix(88)) }
                        ),
                        axis: .vertical
                    )
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
                            } else {
                                AvatarView(
                                    name: displayName.isEmpty ? username : displayName,
                                    size: 64,
                                    avatarURL: avatarUrl
                                )
                            }

                            Spacer()
                        }
                        Button {
                            showAvatarPolicyPrompt = true
                        } label: {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text(pickedImageData == nil ? "Choose Image" : "Change Image")
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
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

                Section(header: Text("Creator Links")) {
                    TextField("YouTube Channel URL", text: $youtubeURL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)

                    TextField("Twitch Channel URL", text: $twitchURL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)

                    TextField("TikTok Profile URL", text: $tiktokURL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
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
                youtubeURL = currentYouTubeURL
                twitchURL = currentTwitchURL
                tiktokURL = currentTikTokURL
                // seed availability as true for the current username
                usernameAvailable = true
            }
            .alert("Profile Image Rules", isPresented: $showAvatarPolicyPrompt) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    showAvatarPicker = true
                }
            } message: {
                Text("Profile images must follow GamerLnd’s terms: no NSFW or sexual content, no explicit violence, no hateful imagery, no impersonation, and no illegal content. Breaking these rules can lead to image removal, account restrictions, or account suspension during beta and beyond.")
            }
            .photosPicker(isPresented: $showAvatarPicker, selection: $pickedItem, matching: .images)
        }
    }

    private func debounceUsernameCheck() {
        usernameCheckTask?.cancel()
        let task = DispatchWorkItem { checkUsername() }
        usernameCheckTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func checkUsername() {
        let uname = ProfileIdentityValidator.sanitizedHandleInput(username)
        guard !uname.isEmpty else { usernameAvailable = nil; return }
        if ProfileIdentityValidator.handleError(uname) != nil {
            usernameAvailable = false
            return
        }
        db.collection("users")
            .whereField("username_lower", isEqualTo: uname)
            .limit(to: 1)
            .getDocuments { snap, _ in
                // available if no doc, OR the only doc is this user
                let takenByOther = snap?.documents.first(where: { ($0.data()["id"] as? String) != userId }) != nil
                if takenByOther {
                    usernameAvailable = false
                    return
                }
                self.db.collection("users")
                    .whereField("handle", isEqualTo: uname)
                    .limit(to: 1)
                    .getDocuments { handleSnap, _ in
                        let handleTakenByOther = handleSnap?.documents.first(where: { ($0.data()["id"] as? String) != userId }) != nil
                        usernameAvailable = !handleTakenByOther
                    }
            }
    }

    private func save() {
        isSaving = true
        errorText = ""

        let disp = ProfileIdentityValidator.normalizedDisplayName(displayName)
        let uname = ProfileIdentityValidator.sanitizedHandleInput(username)
        let bioStored = String(bio.prefix(88))
        let ytStored = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let twitchStored = twitchURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let tiktokStored = tiktokURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let error = ProfileIdentityValidator.displayNameError(disp) {
            isSaving = false
            errorText = error
            return
        }

        if let error = ProfileIdentityValidator.handleError(uname) {
            isSaving = false
            errorText = error
            return
        }

        func finish(with newAvatarUrl: String?) {
            var payload: [String: Any] = [
                "display_name": disp,
                "display_name_lower": disp.lowercased(),
                "username": uname,
                "username_lower": uname.lowercased(),
                "handle": uname,
                "bio": bioStored,
                "search_prefix": UserProfile.searchPrefixes(username: disp, handle: uname),
                "youtube_url": ytStored,
                "twitch_url": twitchStored,
                "tiktok_url": tiktokStored
            ]
            if let url = newAvatarUrl {
                payload["avatar_url"] = url
                payload["profile_picture_url"] = url
            }

            db.collection("users").document(userId).setData(payload, merge: true) { err in
                isSaving = false
                if let err = err {
                    errorText = err.localizedDescription
                    return
                }
                onSaved(disp, uname, bioStored, newAvatarUrl ?? avatarUrl, ytStored, twitchStored, tiktokStored)
                Haptics.success()
                dismiss()
            }
        }

        // If a new image was selected, upload to Firebase Storage first.
        if let data = pickedImageData {
            AvatarUploadService.upload(userId: userId, imageData: data) { url, err in
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
                    if item == .rewards {
                        HStack(spacing: 10) {
                            Image("icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                            Text("G")
                        }
                    } else {
                        Text(item.tabTitle)
                    }
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
    let title: String
    let logs: [GameLog]
    let gameNames: [Int: String]
    let reviewsOnly: Bool
    let onClose: () -> Void
    let onOpenLog: (GameLog, String) -> Void
    @State private var sort: LogListSort = .recent
    @State private var selectedReviewLog: GameLog? = nil

    private enum LogListSort: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case az = "A–Z"
        case za = "Z–A"
        var id: String { rawValue }
    }

    private var displayedLogs: [GameLog] {
        switch sort {
        case .recent:
            return logs.sorted { $0.playDate.dateValue() > $1.playDate.dateValue() }
        case .az:
            return logs.sorted {
                let l = gameNames[$0.gameId] ?? $0.gameName ?? "Game"
                let r = gameNames[$1.gameId] ?? $1.gameName ?? "Game"
                return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
            }
        case .za:
            return logs.sorted {
                let l = gameNames[$0.gameId] ?? $0.gameName ?? "Game"
                let r = gameNames[$1.gameId] ?? $1.gameName ?? "Game"
                return l.localizedCaseInsensitiveCompare(r) == .orderedDescending
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(LogListSort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sort.rawValue)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                }
                Button {
                    onClose()
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            ScrollView {
                if displayedLogs.isEmpty {
                    Text(reviewsOnly ? "No reviewed games yet." : "No logged games yet.")
                        .font(.footnote)
                        .foregroundColor(ColorTheme.subtext)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    VStack(spacing: 8) {
                    ForEach(displayedLogs, id: \.id) { log in
                        let title = gameNames[log.gameId] ?? log.gameName ?? "Loading…"
                        HStack(spacing: 10) {
                            Button {
                                onOpenLog(log, title)
                            } label: {
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
                                            RatingHeartBadge(value: r, size: 28)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            if let review = log.review, !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    selectedReviewLog = log
                                } label: {
                                    Image(systemName: "text.quote")
                                        .font(.title3.weight(.semibold))
                                        .foregroundColor(ColorTheme.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    }
                    .padding(16)
                }
            }
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .overlay {
            if let log = selectedReviewLog {
                ZStack {
                    OverlayBackdrop()
                        .ignoresSafeArea()
                        .onTapGesture { selectedReviewLog = nil }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(gameNames[log.gameId] ?? log.gameName ?? "Review")
                                .font(.headline.weight(.bold))
                                .foregroundColor(ColorTheme.text)
                            Spacer()
                            Button {
                                selectedReviewLog = nil
                            } label: {
                                OverlayCloseButton()
                            }
                            .buttonStyle(.plain)
                        }
                        Text(ContentModeration.displayReviewText(log.review))
                            .font(.body)
                            .foregroundColor(ColorTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(width: min(UIScreen.main.bounds.width - 48, 360))
                    .background(RoundedRectangle(cornerRadius: 18).fill(ColorTheme.background))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Stats Sheet (Average rating rounded to 1 decimal + keyboard-aware search)

private struct StatsSheet: View {
    private enum InsightsRange: String, CaseIterable, Identifiable {
        case sevenDays = "7D"
        case thirtyDays = "30D"
        case sixMonths = "6M"
        case oneYear = "1Y"

        var id: String { rawValue }

        var title: String { rawValue }

        var days: Int {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .sixMonths: return 182
            case .oneYear: return 365
            }
        }
    }

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
    @State private var selectedRange: InsightsRange = .thirtyDays
    @State private var isLoadingInsights: Bool = false
    @State private var likesInRange: Int = 0
    @State private var commentsInRange: Int = 0
    @State private var impressionsInRange: Int = 0
    @State private var likesPreviousRange: Int = 0
    @State private var commentsPreviousRange: Int = 0
    @State private var impressionsPreviousRange: Int = 0
    @State private var topInsightsLogs: [InsightLogPerformance] = []
    @State private var selectedInsightLog: GameLog? = nil

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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("See how your logged games are performing.")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                        Text("Track likes, comments, and impressions across your selected time range.")
                            .font(.caption)
                            .foregroundColor(ColorTheme.subtext)
                    }
                    .padding(.horizontal, 16)

                    HStack(spacing: 8) {
                        ForEach(InsightsRange.allCases) { range in
                            let isSelected = selectedRange == range
                            Button {
                                selectedRange = range
                                loadInsightsAnalytics()
                            } label: {
                                Text(range.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(isSelected ? ColorTheme.accent : ColorTheme.subtext)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isSelected ? ColorTheme.black : ColorTheme.background.opacity(0.22))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(isSelected ? ColorTheme.accent : ColorTheme.separator, lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    if isLoadingInsights {
                        ProgressView()
                            .tint(ColorTheme.accent)
                            .padding(.top, 20)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            insightMetricCard(
                                label: "Likes",
                                value: likesInRange,
                                delta: likesInRange - likesPreviousRange,
                                accent: ColorTheme.accent
                            )
                            insightMetricCard(
                                label: "Comments",
                                value: commentsInRange,
                                delta: commentsInRange - commentsPreviousRange,
                                accent: ColorTheme.gold
                            )
                            insightMetricCard(
                                label: "Impressions",
                                value: impressionsInRange,
                                delta: impressionsInRange - impressionsPreviousRange,
                                accent: ColorTheme.xpGreen
                            )
                            insightMetricCard(
                                label: "Total Engagement",
                                value: likesInRange + commentsInRange,
                                delta: (likesInRange + commentsInRange) - (likesPreviousRange + commentsPreviousRange),
                                accent: ColorTheme.highlight
                            )
                        }
                        .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Game Logs")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if topInsightsLogs.isEmpty {
                                Text("No engagement activity yet for this range.")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.subtext)
                            } else {
                                ForEach(topInsightsLogs.prefix(3)) { log in
                                    insightLogRow(log)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, kb.height + 24)
                .animation(.easeOut(duration: 0.22), value: kb.height)
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        OverlayCloseButton()
                    }
                }
            }
            .onAppear {
                computeBasics()
                loadInsightsAnalytics()
            }
            .overlay {
                if let log = selectedInsightLog {
                    GameLogOverlayHost(
                        preview: .init(
                            gameLog: log,
                            gameName: log.gameName ?? "Game",
                            authorUsernameOverride: nil,
                            focusCommentOnAppear: false
                        )
                    ) {
                        selectedInsightLog = nil
                    }
                }
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

    private var statsGaugePanel: some View {
        let items: [(String, Double)] = [
            ("Followers", Double(followers)),
            ("Following", Double(following)),
            ("Logged", Double(totalLogs)),
            ("Reviews", Double(totalReviews)),
            ("Likes", Double(totalLikesReceived)),
            ("Avg Rating", avgUserRating ?? 0)
        ]
        let maxVal = max(items.map { $0.1 }.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 14) {
            ForEach(items, id: \.0) { item in
                statGaugeCard(
                    label: item.0,
                    valueText: item.0 == "Avg Rating" ? formatRatingValue(item.1) : "\(Int(item.1))",
                    progress: maxVal > 0 ? min(1, item.1 / maxVal) : 0,
                    accent: item.0 == "Avg Rating" ? ColorTheme.gold : ColorTheme.accent
                )
            }
        }
    }

    private func insightMetricCard(label: String, value: Int, delta: Int, accent: Color) -> some View {
        let previous = max(0, value - delta)
        let maxValue = max(value, previous, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.subtext)
            Text("\(value)")
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundColor(ColorTheme.text)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ColorTheme.separator.opacity(0.18))
                    .frame(height: 8)
                Capsule()
                    .fill(accent.opacity(0.35))
                    .frame(width: CGFloat(previous) / CGFloat(maxValue) * 120, height: 8)
                Capsule()
                    .fill(LinearGradient(colors: [accent, ColorTheme.xpGreen], startPoint: .leading, endPoint: .trailing))
                    .frame(width: CGFloat(value) / CGFloat(maxValue) * 120, height: 8)
            }
            Text(deltaText(delta))
                .font(.caption.weight(.semibold))
                .foregroundColor(delta >= 0 ? accent : ColorTheme.highlight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.55), lineWidth: 1))
    }

    private func insightLogRow(_ log: InsightLogPerformance) -> some View {
        Button {
            selectedInsightLog = log.gameLog
        } label: {
            HStack(spacing: 12) {
            if let coverId = log.coverId {
                GameCoverImage(id: coverId, preset: .small, cornerRadius: 8)
                    .frame(width: 46, height: 62)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ColorTheme.separator.opacity(0.22))
                    .frame(width: 46, height: 62)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(log.gameName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)
                Text(log.timestampText)
                    .font(.caption2)
                    .foregroundColor(ColorTheme.subtext)
                HStack(spacing: 10) {
                    metricChip("Likes \(log.likes)")
                    metricChip("Comments \(log.comments)")
                    metricChip("Views \(log.impressions)")
                }
            }
            Spacer()
        }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(ColorTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func metricChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(ColorTheme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.background.opacity(0.32)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator.opacity(0.8), lineWidth: 1))
    }

    private func deltaText(_ delta: Int) -> String {
        if delta == 0 { return "Flat vs previous range" }
        return delta > 0 ? "+\(delta) vs previous range" : "\(delta) vs previous range"
    }

    private func loadInsightsAnalytics() {
        isLoadingInsights = true
        let calendar = Calendar.current
        let endDate = Date()
        let currentStart = calendar.date(byAdding: .day, value: -selectedRange.days, to: endDate) ?? endDate
        let previousStart = calendar.date(byAdding: .day, value: -(selectedRange.days * 2), to: endDate) ?? currentStart

        db.collection("game_logs")
            .whereField("user_id", isEqualTo: userId)
            .limit(to: 1000)
            .getDocuments { snap, _ in
                let logs: [InsightLogPerformance] = (snap?.documents ?? []).compactMap { doc in
                    guard let parsed = parseInsightGameLog(docIdFallback: doc.documentID, data: doc.data()) else { return nil }
                    return InsightLogPerformance(
                        id: parsed.id,
                        gameLog: parsed,
                        gameName: parsed.gameName ?? "Game",
                        coverId: parsed.cover?.imageId,
                        timestamp: parsed.playDate.dateValue(),
                        likes: 0,
                        comments: 0,
                        impressions: 0
                    )
                }

                guard !logs.isEmpty else {
                    DispatchQueue.main.async {
                        likesInRange = 0
                        commentsInRange = 0
                        impressionsInRange = 0
                        likesPreviousRange = 0
                        commentsPreviousRange = 0
                        impressionsPreviousRange = 0
                        topInsightsLogs = []
                        isLoadingInsights = false
                    }
                    return
                }

                let group = DispatchGroup()
                var byLog = Dictionary(uniqueKeysWithValues: logs.map { ($0.id, $0) })
                var currentLikes = 0
                var previousLikes = 0
                var currentComments = 0
                var previousComments = 0
                var currentImpressions = 0
                var previousImpressions = 0

                for log in logs {
                    group.enter()
                    db.collection("review_likes")
                        .whereField("log_id", isEqualTo: log.id)
                        .whereField("created_at", isGreaterThanOrEqualTo: Timestamp(date: previousStart))
                        .getDocuments { snap, _ in
                            for doc in snap?.documents ?? [] {
                                guard let ts = doc.data()["created_at"] as? Timestamp else { continue }
                                if ts.dateValue() >= currentStart {
                                    currentLikes += 1
                                    if var item = byLog[log.id] {
                                        item.likes += 1
                                        byLog[log.id] = item
                                    }
                                } else {
                                    previousLikes += 1
                                }
                            }
                            group.leave()
                        }

                    group.enter()
                    db.collection("review_comments")
                        .whereField("log_id", isEqualTo: log.id)
                        .whereField("created_at", isGreaterThanOrEqualTo: Timestamp(date: previousStart))
                        .getDocuments { snap, _ in
                            for doc in snap?.documents ?? [] {
                                guard let ts = doc.data()["created_at"] as? Timestamp else { continue }
                                if ts.dateValue() >= currentStart {
                                    currentComments += 1
                                    if var item = byLog[log.id] {
                                        item.comments += 1
                                        byLog[log.id] = item
                                    }
                                } else {
                                    previousComments += 1
                                }
                            }
                            group.leave()
                        }

                    group.enter()
                    db.collection("log_impressions")
                        .whereField("log_id", isEqualTo: log.id)
                        .whereField("created_at", isGreaterThanOrEqualTo: Timestamp(date: previousStart))
                        .getDocuments { snap, _ in
                            for doc in snap?.documents ?? [] {
                                let data = doc.data()
                                let source = data["source"] as? String ?? ""
                                let viewerId = data["viewer_user_id"] as? String ?? ""
                                guard source == "feed", viewerId != userId else { continue }
                                guard let ts = data["created_at"] as? Timestamp else { continue }
                                if ts.dateValue() >= currentStart {
                                    currentImpressions += 1
                                    if var item = byLog[log.id] {
                                        item.impressions += 1
                                        byLog[log.id] = item
                                    }
                                } else {
                                    previousImpressions += 1
                                }
                            }
                            group.leave()
                        }
                }

                group.notify(queue: .main) {
                    likesInRange = currentLikes
                    commentsInRange = currentComments
                    impressionsInRange = currentImpressions
                    likesPreviousRange = previousLikes
                    commentsPreviousRange = previousComments
                    impressionsPreviousRange = previousImpressions
                    topInsightsLogs = Array(byLog.values)
                        .sorted { lhs, rhs in
                            let lhsScore = lhs.likes + lhs.comments + lhs.impressions
                            let rhsScore = rhs.likes + rhs.comments + rhs.impressions
                            if lhsScore != rhsScore { return lhsScore > rhsScore }
                            return lhs.timestamp > rhs.timestamp
                        }
                    isLoadingInsights = false
                }
            }
    }

    private func parseInsightGameLog(docIdFallback: String, data: [String: Any]) -> GameLog? {
        guard
            let userId = data["user_id"] as? String,
            let gameId = data["game_id"] as? Int ?? (data["game_id"] as? NSNumber)?.intValue,
            let statusRaw = data["status"] as? String,
            let playDate = data["play_date"] as? Timestamp
        else { return nil }
        let status = GameStatus(rawValue: statusRaw) ?? .inProgress
        let rating = data["rating"] as? Double ?? (data["rating"] as? NSNumber)?.doubleValue
        let review = data["review"] as? String
        let containsSpoilers = data["review_contains_spoilers"] as? Bool ?? false
        let isLiked = data["is_liked"] as? Bool ?? false
        var cover: Game.Cover? = nil
        if let coverDict = data["cover"] as? [String: Any],
           let imageId = coverDict["image_id"] as? String {
            cover = Game.Cover(id: coverDict["id"] as? Int, imageId: imageId)
        }
        let gameName = (data["game_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GameLog(
            id: (data["id"] as? String) ?? docIdFallback,
            userId: userId,
            gameId: gameId,
            gameName: gameName?.isEmpty == true ? nil : gameName,
            status: status,
            playDate: playDate,
            rating: rating,
            review: review,
            containsSpoilers: containsSpoilers,
            isLiked: isLiked,
            cover: cover
        )
    }

    private func statGaugeCard(label: String, valueText: String, progress: Double, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.subtext)
                Spacer()
                Text(valueText)
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundColor(ColorTheme.text)
            }

            Gauge(value: progress, in: 0...1) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(Gradient(colors: [accent, ColorTheme.xpGreen]))
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)

            GeometryReader { geo in
                let width = geo.size.width
                let needleX = max(10, min(width - 10, width * CGFloat(progress)))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ColorTheme.separator.opacity(0.18))
                        .frame(height: 8)
                    Capsule()
                        .fill(LinearGradient(colors: [accent, ColorTheme.xpGreen], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(14, width * CGFloat(progress)), height: 8)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 4, height: 18)
                        .offset(x: needleX - 2, y: -5)
                        .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
                }
            }
            .frame(height: 18)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ColorTheme.separator, lineWidth: 1))
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

private struct LogReferenceEntry: Identifiable {
    let id: String
    let userId: String
    let logId: String
    let logOwnerId: String
    let gameId: Int
    let gameName: String
    let authorName: String
    let authorAvatarUrl: String?
    let coverId: String?
    let rating: Double?
    let reviewPreview: String?
    let addedAt: Timestamp?
}

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

private struct InsightLogPerformance: Identifiable {
    let id: String
    let gameLog: GameLog
    let gameName: String
    let coverId: String?
    let timestamp: Date
    var likes: Int
    var comments: Int
    var impressions: Int

    var timestampText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
