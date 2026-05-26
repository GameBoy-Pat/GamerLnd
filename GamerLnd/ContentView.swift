// ContentView.swift
// Home (feed), Explore, Notifications, Profile.

import SwiftUI
import UIKit
import FirebaseAuth
@preconcurrency import FirebaseFirestore
import os.log

struct ContentView: View {
    private static let feedRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let feedAbsoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: Tabs
    enum Tab: Int, CaseIterable { case home = 0, explore, notifications, profile
        var icon: String {
            switch self {
            case .home: "house.fill"
            case .explore: "magnifyingglass.circle.fill"
            case .notifications: "bell.fill"
            case .profile: "person.fill"
            }
        }
        var label: String {
            switch self {
            case .home: "Home"
            case .explore: "Explore"
            case .notifications: "Notifications"
            case .profile: "Profile"
            }
        }
        func image(pointSize: CGFloat = 30,
                   weight: UIImage.SymbolWeight = .semibold,
                   scale: UIImage.SymbolScale = .large) -> Image {
            let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight, scale: scale)
            let ui = (UIImage(systemName: icon)?.applyingSymbolConfiguration(cfg)) ?? UIImage()
            return Image(uiImage: ui).renderingMode(.template)
        }
    }

    @State private var currentTab: Tab = .home
    @Namespace private var tabBarSelectionNS

    // Auth gate
    @State private var authListener: AuthStateDidChangeListenerHandle?
    @State private var isLoggedIn: Bool = false
    @State private var activeAuthUserId: String? = nil
    @State private var showVerificationLoginOverlay: Bool = false
    @State private var verificationOverlayText: String = ""
    @State private var isProcessingVerificationLogin: Bool = false

    // Feeds
    @State private var followingLogs: [FeedActivityItem] = []
    @State private var forYouLogs: [FeedActivityItem] = []
    @State private var followingIds: Set<String> = [] // user ids you follow
    @State private var followingLogIds: Set<String> = [] // log ids for de-dupe
    @State private var followingChunkLastDocs: [String: DocumentSnapshot] = [:]
    @State private var forYouIds: Set<String> = []
    @State private var isLoadingFollowing: Bool = false
    @State private var isLoadingForYou: Bool = false
    @State private var selectedFeed: String = "Following"
    @State private var selectedFeedFilter: FeedFilter = .both

    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var addToListGame: Game? = nil
    @State private var revealedReviews: Set<String> = []

    @State private var usernameCache: [String: String] = [:]
    @State private var displayNameCache: [String: String] = [:]
    @State private var avatarCache: [String: String] = [:]
    @State private var trustedCache: [String: Bool] = [:]
    @State private var gameNameCache: [Int: String] = [:]
    @State private var likedSet: Set<String> = []
    @State private var likeCounts: [String: Int] = [:]
    @State private var pendingLikeLogIds: Set<String> = []
    @State private var commentCounts: [String: Int] = [:]
    @State private var commentedLogIds: Set<String> = []
    @State private var avgCache: [Int: (avg: Double?, count: Int)] = [:]
    @State private var hasLogged: [Int: Bool] = [:]
    @State private var gamePublisherCache: [Int: String] = [:]
    @State private var gameYearCache: [Int: Int] = [:]
    @State private var showRatingsOverlay: Bool = false
    @State private var ratingsOverlayGameId: Int? = nil
    @State private var ratingsOverlayName: String = ""
    @State private var ratingsOverlayCover: Game.Cover? = nil
    @State private var ratingsOverlayAvg: Double? = nil
    @State private var ratingsOverlayList: [RatingsOverlayEntry] = []
    @State private var ratingsOverlayLoading: Bool = false
    @State private var ratingsOverlayFilter: String = "All"
    @State private var ratingsOverlayReviewEntry: RatingsOverlayEntry? = nil
    @State private var watchlistIds: Set<Int> = []
    @State private var showCreateMenu: Bool = false
    @State private var showBookmarksOverlay: Bool = false
    @State private var bookmarksSort: BookmarkSort = .recent
    @State private var bookmarksList: [BookmarkEntry] = []
    @State private var pendingSaveGame: Game? = nil
    @State private var publicLists: [UserList] = []
    @State private var listOwnerNames: [String: String] = [:]
    @State private var publicListPreviews: [String: [String]] = [:]
    @State private var logOverlayGame: Game? = nil
    @State private var logDetailOverlay: LogDetailOverlayContext? = nil
    @State private var expandedFeedItem: FeedActivityItem? = nil
    @State private var expandedFeedDetailsVisible: Bool = false
    @State private var flippedCards: Set<String> = []
    @State private var likePulseIds: Set<String> = []
    @State private var trackedImpressionKeys: Set<String> = []
    @State private var feedLoadTask: Task<Void, Never>? = nil
    @State private var isRefreshingFeed: Bool = false
    @State private var requestedNameIds: Set<Int> = []
    @State private var requestedAverageGameIds: Set<Int> = []
    @State private var requestedHasLoggedGameIds: Set<Int> = []
    @State private var lastRefreshAt: Date? = nil
    @State private var showFeedHint: Bool = true
    private enum RewardToastStyle {
        case standard
        case secret
    }

    @State private var rewardToastText: String = ""
    @State private var showRewardToast: Bool = false
    @State private var rewardToastIcon: String = "sparkles"
    @State private var rewardToastStyle: RewardToastStyle = .standard
    @State private var miniRewardXP: Int = 0
    @State private var displayedMiniRewardXP: Int = 0
    @State private var miniRewardTheme: RewardService.Theme = .xp
    @State private var miniRewardDeltaToast: String? = nil
    @State private var isAnimatingMiniRewardXP: Bool = false
    @State private var pendingMiniRewardAnimationTotal: Int? = nil
    @State private var pendingMiniRewardAnimationDelta: Int = 0
    @State private var pendingMiniRewardUnit: String = "XP"
    @State private var showMiniRewardHistoryOverlay: Bool = false
    @State private var miniRewardEvents: [(id: String, type: String, delta: Int, at: Date)] = []
    @State private var spoilerReviewItem: FeedActivityItem? = nil
    @State private var isNestedOverlayPresented: Bool = false
    @State private var lastGamificationEnsureAt: Date? = nil

    @State private var followLastDoc: DocumentSnapshot?
    @State private var forYouLastDoc: DocumentSnapshot?
    @State private var activityBadgeCount: Int = 0

    private let db = Firestore.firestore()
    private let igdb = IGDBService()

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @AppStorage("feedCardTheme") private var feedCardTheme: String = "colorRush"
    @AppStorage("pendingEmailVerification") private var pendingEmailVerification: Bool = false

    private let PAGE_SIZE = 20
    private let INITIAL_PAGE_SIZE = 12
    private let DAYS_BACK: Int = 365

    private let coverWidth: CGFloat = 141
    private let coverHeight: CGFloat = 188
    private let badgeReservedBottomPadding: CGFloat = 36

    private let bottomIconPointSize: CGFloat = 20
    private let headerPickerIconSize: CGFloat = 20

    private enum FeedFilter: String, CaseIterable, Identifiable {
        case both = "All"
        case logs = "Games"
        case lists = "Lists"

        var id: String { rawValue }
    }

    private var headerTitle: String { selectedFeed == "Following" ? "Your Feed" : "Trending" }
    @State private var profileOverlayPresented: Bool = false

    private var isAnyOverlayPresented: Bool {
        showRatingsOverlay
        || showBookmarksOverlay
        || showCreateMenu
        || logOverlayGame != nil
        || logDetailOverlay != nil
        || expandedFeedItem != nil
        || expandedFeedItem != nil
        || showMiniRewardHistoryOverlay
        || showVerificationLoginOverlay
        || addToListGame != nil
        || profileOverlayPresented
    }

    private var shouldBlurRootContent: Bool {
        showRatingsOverlay
        || showBookmarksOverlay
        || showCreateMenu
        || logOverlayGame != nil
        || logDetailOverlay != nil
        || showMiniRewardHistoryOverlay
        || showVerificationLoginOverlay
        || addToListGame != nil
    }

    private var isMiniRewardSuppressed: Bool {
        isAnyOverlayPresented || isNestedOverlayPresented
    }

    private var canShowMiniRewardSurface: Bool {
        isLoggedIn && (currentTab == .home || currentTab == .explore) && !isMiniRewardSuppressed
    }

    @ViewBuilder
    private var rootContentView: some View {
        if !isLoggedIn {
            loggedOutRootView
        } else {
            loggedInRootView
        }
    }

    @ViewBuilder
    private var loggedOutRootView: some View {
        if !hasSeenOnboarding {
            OnboardingView {
                hasSeenOnboarding = true
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LoginView(user: .constant(nil))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ColorTheme.background)
        }
    }

    private var loggedInTabContent: some View {
        Group {
            switch currentTab {
            case .home: homeView
            case .explore: exploreView
            case .notifications: notificationsView
            case .profile: profileView
            }
        }
    }

    private var loggedInRootView: some View {
        loggedInTabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)
            .blur(radius: shouldBlurRootContent ? 5 : 0)
    }

    @ViewBuilder
    private var tabBarLayer: some View {
        if isLoggedIn && !profileOverlayPresented {
            bottomSegmentedTabBar
                .padding(.bottom, 0)
                .ignoresSafeArea(edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .blur(radius: shouldBlurRootContent ? 4 : 0)
        }
    }

    @ViewBuilder
    private var profileOverlayNavCoverLayer: some View {
        EmptyView()
    }

    @ViewBuilder
    private var floatingButtonLayer: some View {
        if false {
            floatingCreateButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 20)
                .padding(.bottom, 96)
        }
    }

    @ViewBuilder
    private var primaryOverlayLayer: some View {
        if showRatingsOverlay {
            ratingsOverlayView()
                .transition(.opacity)
                .zIndex(995)
        }
    }

    @ViewBuilder
    private var feedExpansionLayer: some View {
        if let item = expandedFeedItem {
            expandedFeedPreviewOverlay(item: item)
                .transition(.opacity)
                .zIndex(965)
        }
    }

    @ViewBuilder
    private var secondaryOverlayLayer: some View {
        if showBookmarksOverlay {
            bookmarksOverlayView()
                .transition(.opacity)
        }
        if showCreateMenu {
            createMenuOverlay()
                .transition(.opacity)
        }
        if let game = logOverlayGame {
            logGameOverlay(game: game)
                .transition(.opacity)
                .zIndex(960)
        }
        if let ctx = logDetailOverlay {
            logDetailOverlayView(ctx: ctx)
                .transition(.opacity)
                .zIndex(970)
        }
        if let game = addToListGame {
            addToListOverlay(game: game)
                .transition(.opacity)
        }
        if showVerificationLoginOverlay {
            verificationLoginOverlay
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var miniRewardLayer: some View {
        if isLoggedIn && (currentTab == .home || currentTab == .explore) && !isMiniRewardSuppressed {
            miniRewardPill
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, currentTab == .home ? 66 : 54)
                .padding(.trailing, 12)
                .zIndex(900)
        }
        if isLoggedIn && currentTab == .home && showFeedHint && !isMiniRewardSuppressed {
            feedHintFloating
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 24)
                .padding(.trailing, 12)
                .transition(.opacity)
                .zIndex(901)
        }
        if isLoggedIn && (currentTab == .home || currentTab == .explore) && !isMiniRewardSuppressed, let miniRewardDeltaToast {
            miniRewardDeltaToastView(text: miniRewardDeltaToast)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 92)
                .padding(.trailing, 12)
                .zIndex(902)
        }
        if showMiniRewardHistoryOverlay {
            miniRewardHistoryOverlay
                .transition(.opacity)
                .zIndex(980)
        }
        if showRewardToast {
            rewardToastView
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(1000)
        }
    }

    private var mainScene: some View {
        ZStack(alignment: .bottom) {
            rootContentView
            tabBarLayer
            floatingButtonLayer
            profileOverlayNavCoverLayer
            primaryOverlayLayer
            feedExpansionLayer
            secondaryOverlayLayer
            miniRewardLayer
        }
        .ignoresSafeArea(.keyboard, edges: .all)
        .preferredColorScheme(.dark)
    }

    private var sceneWithLifecycleHandlers: some View {
        mainScene
            .onAppear {
                refreshAuthVerificationState()
                if Auth.auth().currentUser != nil {
                    activeAuthUserId = Auth.auth().currentUser?.uid
                    loadMiniRewardState()
                    loadActivityBadgeCount()
                    ensureGamificationAssignments()
                }
                authListener = Auth.auth().addStateDidChangeListener { _, user in
                    let wasLoggedIn = isLoggedIn
                    let previousUserId = activeAuthUserId
                    activeAuthUserId = user?.uid
                    if user == nil {
                        isLoggedIn = false
                    } else {
                        refreshAuthVerificationState()
                    }
                    let switchedAccounts = previousUserId != nil && previousUserId != user?.uid
                    if (!isLoggedIn && wasLoggedIn) || switchedAccounts {
                        followingLogs = []; forYouLogs = []
                        followingIds = []; followingLogIds = []; followingChunkLastDocs = [:]; forYouIds = []
                        followLastDoc = nil; forYouLastDoc = nil
                        likedSet = []; likeCounts = [:]; commentCounts = [:]; commentedLogIds = []
                        watchlistIds = []; bookmarksList = []; avgCache = [:]; gameNameCache = [:]
                        hasLogged = [:]
                        trustedCache = [:]
                        activityBadgeCount = 0
                        profileOverlayPresented = false
                        isNestedOverlayPresented = false
                        miniRewardXP = 0
                        displayedMiniRewardXP = 0
                    }
                    if isLoggedIn {
                        loadMiniRewardState()
                        loadActivityBadgeCount()
                        ensureGamificationAssignments()
                    }
                }
                if currentTab == .home { runFeedTask { await initialLoad() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refreshAuthVerificationState()
                if isLoggedIn { ensureGamificationAssignments() }
            }
            .onChange(of: currentTab) { _, newValue in
                if newValue != .profile {
                    profileOverlayPresented = false
                }
                if newValue == .notifications {
                    markActivityAsSeen()
                }
                if newValue == .home {
                    runFeedTask { await ensureLoadedSelectedFeed() }
                }
                playPendingMiniRewardAnimationIfPossible()
            }
            .onChange(of: canShowMiniRewardSurface) { _, isVisible in
                if isVisible {
                    playPendingMiniRewardAnimationIfPossible()
                }
            }
    }

    private var sceneWithNotificationHandlers: some View {
        sceneWithLifecycleHandlers
            .onReceive(NotificationCenter.default.publisher(for: .gamerLndRatingUpdated)) { note in
                guard let gid = note.userInfo?["game_id"] as? Int else { return }
                let isHomeRelevant = currentTab == .home
                let isOverlayRelevant = ratingsOverlayGameId == gid
                guard isHomeRelevant || isOverlayRelevant else { return }
                let visibleGameIds = Set(followingLogs.map { $0.gameLog.gameId })
                    .union(forYouLogs.map { $0.gameLog.gameId })
                let shouldRefresh = visibleGameIds.contains(gid) || ratingsOverlayGameId == gid
                guard shouldRefresh else { return }
                GamerLndScoreService.shared.fetchAverage(gameId: gid) { avg, count in
                    avgCache[gid] = (avg: avg, count: count)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .gameLogChanged)) { note in
                guard let logId = note.userInfo?["log_id"] as? String else { return }
                let isHomeRelevant = currentTab == .home
                let isOverlayRelevant = logDetailOverlay?.gameLog.id == logId || logOverlayGame?.id == (note.userInfo?["game_id"] as? Int)
                guard isHomeRelevant || isOverlayRelevant else { return }
                let isVisibleLog = followingLogs.contains(where: { $0.gameLog.id == logId }) ||
                    forYouLogs.contains(where: { $0.gameLog.id == logId })
                let deleted = (note.userInfo?["deleted"] as? Bool) ?? false
                if deleted {
                    followingLogs.removeAll { $0.gameLog.id == logId }
                    forYouLogs.removeAll { $0.gameLog.id == logId }
                    followingIds.remove(logId)
                    forYouIds.remove(logId)
                    return
                }
                guard isVisibleLog else { return }
                db.collection("game_logs").document(logId).getDocument { snap, _ in
                    guard let data = snap?.data(),
                          let updatedLog = Self.parseGameLog(docIdFallback: logId, data: data) else { return }
                    DispatchQueue.main.async {
                        func patch(_ items: inout [FeedActivityItem]) {
                            guard let idx = items.firstIndex(where: { $0.gameLog.id == logId }) else { return }
                            let existing = items[idx]
                            items[idx] = FeedActivityItem(
                                id: existing.id,
                                gameLog: updatedLog,
                                gameName: updatedLog.gameName ?? existing.gameName,
                                username: existing.username,
                                avatarUrl: existing.avatarUrl,
                                isTrustedGamer: existing.isTrustedGamer
                            )
                        }
                        patch(&followingLogs)
                        patch(&forYouLogs)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .gamificationUpdated)) { note in
                if let changedUserId = note.userInfo?["user_id"] as? String,
                   let currentUserId = Auth.auth().currentUser?.uid,
                   changedUserId != currentUserId {
                    return
                }
                loadMiniRewardState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToExplore)) { _ in
                currentTab = .explore
            }
    }

    var body: some View {
        sceneWithNotificationHandlers
            .onReceive(NotificationCenter.default.publisher(for: .rewardXPAwarded)) { note in
                guard let delta = note.userInfo?["delta"] as? Int, delta > 0 else { return }
                let raw = note.userInfo?["theme"] as? String
                let unit = RewardService.Theme(rawValue: raw ?? "")?.displayUnit ?? "XP"
                let reason = (note.userInfo?["reason"] as? String) ?? ""
                miniRewardXP = (note.userInfo?["total"] as? Int) ?? miniRewardXP
                miniRewardTheme = RewardService.Theme(rawValue: raw ?? "") ?? miniRewardTheme
                if shouldAnimateMiniReward(for: reason) {
                    queueOrApplyMiniRewardUpdate(total: miniRewardXP, delta: delta, unit: unit)
                } else if !isAnimatingMiniRewardXP && pendingMiniRewardAnimationTotal == nil {
                    displayedMiniRewardXP = miniRewardXP
                }
                guard currentTab != .profile else { return }
                presentRewardToast(text: "+\(delta) \(unit)", icon: "arrow.up.circle.fill")
            }
            .onReceive(NotificationCenter.default.publisher(for: .questCompleted)) { note in
                if let uid = Auth.auth().currentUser?.uid,
                   let changedUserId = note.userInfo?["user_id"] as? String,
                   changedUserId != uid {
                    return
                }
                let title = (note.userInfo?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                presentRewardToast(
                    text: title?.isEmpty == false ? "Quest Complete: \(title!)" : "Quest Complete",
                    icon: "checkmark.seal.fill",
                    style: .standard
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .secretQuestFound)) { note in
                if let uid = Auth.auth().currentUser?.uid,
                   let changedUserId = note.userInfo?["user_id"] as? String,
                   changedUserId != uid {
                    return
                }
                let title = (note.userInfo?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                presentRewardToast(
                    text: title?.isEmpty == false ? "Secret Quest Found: \(title!)" : "Secret Quest Found",
                    icon: "sparkles.rectangle.stack.fill",
                    style: .secret
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .challengesUpdated)) { note in
                if let uid = Auth.auth().currentUser?.uid,
                   let changedUserId = note.userInfo?["user_id"] as? String,
                   changedUserId != uid {
                    return
                }
                presentRewardToast(
                    text: "Challenges Updated",
                    icon: "flag.checkered.2.crossed",
                    style: .standard
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .logCommentsUpdated)) { note in
                guard let logId = note.userInfo?["log_id"] as? String else { return }
                let isHomeRelevant = currentTab == .home
                let isVisibleLog = followingLogs.contains(where: { $0.gameLog.id == logId }) ||
                    forYouLogs.contains(where: { $0.gameLog.id == logId }) ||
                    logDetailOverlay?.gameLog.id == logId
                guard isHomeRelevant || logDetailOverlay?.gameLog.id == logId else { return }
                guard isVisibleLog else { return }
                fetchCommentCount(for: logId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRatingsOverlayRequested)) { note in
                guard let gameId = note.userInfo?["game_id"] as? Int else { return }
                let gameName = (note.userInfo?["game_name"] as? String) ?? "Game"
                let avg = note.userInfo?["avg"] as? Double
                let coverImageId = note.userInfo?["cover_image_id"] as? String
                let cover = coverImageId.map { Game.Cover(id: nil, imageId: $0) }
                openRatingsOverlay(gameId: gameId, gameName: gameName, cover: cover, avg: avg)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nestedOverlayVisibilityChanged)) { note in
                isNestedOverlayPresented = note.userInfo?["visible"] as? Bool ?? false
                playPendingMiniRewardAnimationIfPossible()
            }
            .onReceive(NotificationCenter.default.publisher(for: .profileOverlayVisibilityChanged)) { note in
                profileOverlayPresented = note.userInfo?["is_presented"] as? Bool ?? false
                playPendingMiniRewardAnimationIfPossible()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGlobalGameLogEditorRequested)) { note in
                guard let game = note.object as? Game else { return }
                logOverlayGame = game
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGlobalGameLogPreviewRequested)) { note in
                guard let gameLog = note.object as? GameLog else { return }
                let gameName = (note.userInfo?["game_name"] as? String) ?? gameLog.gameName ?? "Game"
                let username = note.userInfo?["username"] as? String
                let focusComment = (note.userInfo?["focus_comment"] as? Bool) ?? false
                logDetailOverlay = LogDetailOverlayContext(
                    id: gameLog.id,
                    gameLog: gameLog,
                    gameName: gameName,
                    username: username ?? "",
                    focusComment: focusComment
                )
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .alert("Spoiler Warning", isPresented: Binding(
                get: { spoilerReviewItem != nil },
                set: { if !$0 { spoilerReviewItem = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    spoilerReviewItem = nil
                }
                Button("Read Review") {
                    if let item = spoilerReviewItem {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            _ = flippedCards.insert(item.gameLog.id)
                        }
                    }
                    spoilerReviewItem = nil
                }
            } message: {
                Text("This review was marked as containing spoilers. Do you still want to read it?")
            }
    }

    private var rewardToastView: some View {
        let borderColors: [Color] = {
            switch rewardToastStyle {
            case .standard:
                return [ColorTheme.xpGreen, ColorTheme.gold]
            case .secret:
                return [Color.blue, Color("SecondaryHighlightColor")]
            }
        }()
        let border = LinearGradient(
            colors: borderColors,
            startPoint: .leading,
            endPoint: .trailing
        )

        return VStack {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: rewardToastIcon)
                        .foregroundColor(ColorTheme.gold)
                    Text(rewardToastText)
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
                Spacer()
            }
            .padding(.top, 56)
            .padding(.leading, 16)
            Spacer()
        }
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presentRewardToast(text: String, icon: String, style: RewardToastStyle = .standard) {
        rewardToastText = text
        rewardToastIcon = icon
        rewardToastStyle = style
        withAnimation(.spring(response: 0.62, dampingFraction: 0.94)) {
            showRewardToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            withAnimation(.easeInOut(duration: 0.32)) {
                showRewardToast = false
            }
        }
    }

    private var miniRewardPill: some View {
        let info = RewardService.levelInfo(for: displayedMiniRewardXP)
        let levelGradient = LinearGradient(
            colors: [ColorTheme.gold, ColorTheme.xpGreen],
            startPoint: .leading,
            endPoint: .trailing
        )
        return Button {
            loadMiniRewardHistory()
            showMiniRewardHistoryOverlay = true
        } label: {
            HStack(spacing: 8) {
                Text("Lv \(info.level)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ColorTheme.separator.opacity(0.25))
                        Capsule().fill(levelGradient)
                        .frame(width: max(0, geo.size.width * info.progress))
                    }
                }
                .frame(width: 78, height: 6)
                Text(miniRewardTheme == .xp ? "XP" : String(miniRewardTheme.displayUnit.prefix(1)))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.gold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(ColorTheme.surface)
                    .overlay(Capsule().stroke(levelGradient, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private func loadMiniRewardState() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        miniRewardTheme = RewardService.shared.currentTheme(for: uid)
        db.collection("user_stats").document(uid).getDocument { snap, _ in
            let xp = (snap?.data()?["reward_xp_total"] as? Int)
                ?? (snap?.data()?["reward_xp_total"] as? NSNumber)?.intValue
                ?? ((snap?.data()?["reward_state"] as? [String: Any])?["total_xp"] as? Int)
                ?? (((snap?.data()?["reward_state"] as? [String: Any])?["total_xp"] as? NSNumber)?.intValue)
                ?? 0
            let rawEvents = snap?.data()?["reward_events"] as? [[String: Any]] ?? []
            let parsedEvents = rawEvents.compactMap { item -> (id: String, type: String, delta: Int, at: Date)? in
                let id = (item["id"] as? String) ?? UUID().uuidString
                let type = (item["type"] as? String) ?? "action"
                let delta = (item["delta"] as? Int) ?? (item["delta"] as? NSNumber)?.intValue ?? 0
                guard delta > 0 else { return nil }
                let at: Date = (item["at"] as? Timestamp)?.dateValue() ?? .distantPast
                return (id, type, delta, at)
            }.sorted { $0.at > $1.at }
            DispatchQueue.main.async {
                miniRewardXP = max(0, xp)
                if !isAnimatingMiniRewardXP && pendingMiniRewardAnimationTotal == nil {
                    displayedMiniRewardXP = max(0, xp)
                }
                miniRewardEvents = parsedEvents
            }
        }
    }

    private func shouldAnimateMiniReward(for reason: String) -> Bool {
        let parts = reason
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.contains(where: { ["base_rating", "base_review", "list_add", "save_game"].contains($0) })
    }

    private var canPlayMiniRewardAnimation: Bool {
        canShowMiniRewardSurface
    }

    private func queueOrApplyMiniRewardUpdate(total: Int, delta: Int, unit: String) {
        let clampedTotal = max(0, total)
        miniRewardXP = clampedTotal
        guard delta > 0 else {
            if !isAnimatingMiniRewardXP && pendingMiniRewardAnimationTotal == nil {
                displayedMiniRewardXP = clampedTotal
            }
            return
        }
        if canPlayMiniRewardAnimation && !isAnimatingMiniRewardXP {
            animateMiniRewardXP(to: clampedTotal, delta: delta, unit: unit)
        } else {
            pendingMiniRewardAnimationTotal = clampedTotal
            pendingMiniRewardAnimationDelta += delta
            pendingMiniRewardUnit = unit
        }
    }

    private func playPendingMiniRewardAnimationIfPossible() {
        guard canPlayMiniRewardAnimation, !isAnimatingMiniRewardXP else { return }
        guard let total = pendingMiniRewardAnimationTotal, pendingMiniRewardAnimationDelta > 0 else {
            if canPlayMiniRewardAnimation, let total = pendingMiniRewardAnimationTotal, pendingMiniRewardAnimationDelta <= 0 {
                displayedMiniRewardXP = max(displayedMiniRewardXP, total)
                pendingMiniRewardAnimationTotal = nil
            }
            return
        }
        let delta = pendingMiniRewardAnimationDelta
        let unit = pendingMiniRewardUnit
        pendingMiniRewardAnimationTotal = nil
        pendingMiniRewardAnimationDelta = 0
        animateMiniRewardXP(to: total, delta: delta, unit: unit)
    }

    private func animateMiniRewardXP(to total: Int, delta: Int, unit: String) {
        let end = max(0, total)
        let start = max(0, displayedMiniRewardXP)
        guard end >= start else {
            displayedMiniRewardXP = end
            return
        }

        miniRewardDeltaToast = "+\(delta) \(unit)"
        isAnimatingMiniRewardXP = true
        let steps = max(8, min(22, delta))
        for step in 1...steps {
            let delay = 0.045 * Double(step)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let progress = Double(step) / Double(steps)
                displayedMiniRewardXP = start + Int(round(Double(end - start) * progress))
                if step == steps {
                    isAnimatingMiniRewardXP = false
                    playPendingMiniRewardAnimationIfPossible()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        withAnimation(.easeOut(duration: 0.22)) {
                            miniRewardDeltaToast = nil
                        }
                    }
                }
            }
        }
    }

    private func miniRewardDeltaToastView(text: String) -> some View {
        let border = LinearGradient(
            colors: [ColorTheme.xpGreen, ColorTheme.gold],
            startPoint: .leading,
            endPoint: .trailing
        )
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(ColorTheme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ColorTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1.1))
            )
    }

    private func loadMiniRewardHistory() {
        loadMiniRewardState()
    }

    private func miniRewardHistoryTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var miniRewardHistoryOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { showMiniRewardHistoryOverlay = false }
            VStack {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text("XP History")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                        Spacer()
                        Button {
                            showMiniRewardHistoryOverlay = false
                        } label: {
                            OverlayCloseButton()
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            showMiniRewardHistoryOverlay = false
                            currentTab = .profile
                            NotificationCenter.default.post(name: .openProfileRewardsPage, object: nil, userInfo: ["page": 0])
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
                            showMiniRewardHistoryOverlay = false
                            currentTab = .profile
                            NotificationCenter.default.post(name: .openProfileRewardsPage, object: nil, userInfo: ["page": 1])
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

                    if miniRewardEvents.isEmpty {
                        Text("No XP activity yet.")
                            .font(.footnote)
                            .foregroundColor(ColorTheme.subtext)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(Array(miniRewardEvents.prefix(40)), id: \.id) { e in
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(e.type == "list_add" ? "Added to List" : "Logged / Rated / Reviewed")
                                                .font(.footnote)
                                                .foregroundColor(ColorTheme.text)
                                            Text(miniRewardHistoryTimestamp(for: e.at))
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

    private var verificationLoginOverlay: some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(ColorTheme.accent)
                Text(verificationOverlayText.isEmpty ? "Email verified. Logging you in..." : verificationOverlayText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(ColorTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
            )
            .padding(.horizontal, 24)
        }
    }

    private func shouldTreatAsLoggedIn(_ user: User?) -> Bool {
        guard let user else { return false }
        let providers = Set(user.providerData.map { $0.providerID })
        if providers.contains("password") {
            return user.isEmailVerified
        }
        return true
    }

    private func refreshAuthVerificationState() {
        guard let user = Auth.auth().currentUser else {
            isLoggedIn = false
            isProcessingVerificationLogin = false
            showVerificationLoginOverlay = false
            return
        }
        let providers = Set(user.providerData.map { $0.providerID })
        guard providers.contains("password") else {
            pendingEmailVerification = false
            isLoggedIn = true
            return
        }
        user.reload { _ in
            let refreshed = Auth.auth().currentUser
            guard let refreshed else {
                isLoggedIn = false
                isProcessingVerificationLogin = false
                showVerificationLoginOverlay = false
                return
            }
            if refreshed.isEmailVerified {
                if pendingEmailVerification {
                    guard !isProcessingVerificationLogin else { return }
                    isProcessingVerificationLogin = true
                    verificationOverlayText = "Email verified. Logging you in..."
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showVerificationLoginOverlay = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        pendingEmailVerification = false
                        isLoggedIn = true
                        isProcessingVerificationLogin = false
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showVerificationLoginOverlay = false
                        }
                    }
                } else {
                    isLoggedIn = true
                }
            } else {
                isLoggedIn = false
                isProcessingVerificationLogin = false
                showVerificationLoginOverlay = false
                if pendingEmailVerification {
                    NotificationCenter.default.post(name: .emailVerificationNotDetected, object: nil)
                }
            }
        }
    }

    private func ensureGamificationAssignments() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        if let last = lastGamificationEnsureAt, now.timeIntervalSince(last) < 30 {
            return
        }
        lastGamificationEnsureAt = now
        ObjectiveService.shared.ensureDailyObjectives(userId: uid) { _ in }
        ObjectiveService.shared.ensureWeeklyObjectives(userId: uid) { _ in }
    }

    private func loadActivityBadgeCount() {
        guard let uid = Auth.auth().currentUser?.uid else {
            activityBadgeCount = 0
            return
        }
        let lastSeen = lastSeenActivityDate(for: uid)
        let group = DispatchGroup()
        var notificationsTotal = 0
        var followsTotal = 0

        group.enter()
        db.collection("notifications")
            .whereField("user_id", isEqualTo: uid)
            .limit(to: 25)
            .getDocuments { snap, _ in
                notificationsTotal = (snap?.documents ?? []).reduce(into: 0) { partial, doc in
                    guard let ts = doc.data()["created_at"] as? Timestamp else { return }
                    if ts.dateValue() > lastSeen {
                        partial += 1
                    }
                }
                group.leave()
            }

        group.enter()
        db.collection("follows")
            .whereField("followed_id", isEqualTo: uid)
            .limit(to: 25)
            .getDocuments { snap, _ in
                followsTotal = (snap?.documents ?? []).reduce(into: 0) { partial, doc in
                    guard let ts = doc.data()["created_at"] as? Timestamp else { return }
                    if ts.dateValue() > lastSeen {
                        partial += 1
                    }
                }
                group.leave()
            }

        group.notify(queue: .main) {
            activityBadgeCount = notificationsTotal + followsTotal
        }
    }

    private func activitySeenKey(for uid: String) -> String {
        "activityBadgeLastSeenAt_\(uid)"
    }

    private func lastSeenActivityDate(for uid: String) -> Date {
        let raw = UserDefaults.standard.double(forKey: activitySeenKey(for: uid))
        if raw <= 0 { return .distantPast }
        return Date(timeIntervalSince1970: raw)
    }

    private func markActivityAsSeen() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: activitySeenKey(for: uid))
        activityBadgeCount = 0
    }

    // MARK: - Bottom segmented tab bar

    private var bottomSegmentedTabBar: some View {
        return HStack {
            Picker("", selection: $currentTab) {
                ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                    tab.image(pointSize: bottomIconPointSize, weight: .semibold, scale: .large)
                        .tag(tab)
                        .accessibilityLabel(Text(tab.label))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .tint(ColorTheme.accent)
            .padding(.horizontal, 0)
            .padding(.vertical, 0)
            .frame(height: 54)
            .onChange(of: currentTab) { _, _ in Haptics.select() }
        }
        .overlay {
            GeometryReader { geo in
                if activityBadgeCount > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                        .position(x: geo.size.width * 0.63, y: 9)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(ColorTheme.surface.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(ColorTheme.surface.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    // MARK: - Tab Content

    private var homeView: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        homeFeedScopePicker
                        homeFeedFilterButton
                    }
                    Spacer(minLength: 0)
                }
                .overlay(
                    Text(headerTitle)
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                        .accessibilityAddTraits(.isHeader)
                )
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 2)
                .animation(.none, value: selectedFeed)

                TabView(selection: $selectedFeed) {
                    feedPage(isFollowing: true)
                        .tag("Following")
                    feedPage(isFollowing: false)
                        .tag("For You")
                }
                .padding(.top, 6)
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { AppIconCentered() } }
            .background(ColorTheme.background)
            .onAppear {
                if followingLogs.isEmpty && forYouLogs.isEmpty {
                    Task { await initialLoad() }
                }
                if selectedFeedFilter != .logs {
                    Task { await loadPublicLists() }
                }
                showFeedHintTemporarily()
            }
            .onChange(of: selectedFeed) { _, _ in Task { await ensureLoadedSelectedFeed() } }
            .onChange(of: selectedFeed) { _, _ in showFeedHintTemporarily() }
            .onChange(of: selectedFeedFilter) { _, _ in
                if selectedFeedFilter != .logs {
                    Task { await loadPublicLists() }
                }
                showFeedHintTemporarily()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var exploreView: some View {
        NavigationView { ExploreView() }
            .navigationViewStyle(.stack)
            .ignoresSafeArea(.keyboard, edges: .all)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 68)
            }
    }

    private var notificationsView: some View {
        NavigationView { NotificationsView() }
            .navigationViewStyle(.stack)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 68)
            }
    }

    private var profileView: some View {
        NavigationView { ProfileView(userId: Auth.auth().currentUser?.uid ?? "") }
            .navigationViewStyle(.stack)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 68)
            }
    }

    // MARK: - Reward HUD

    // MARK: - Feed list / rows (unchanged from your version)

    private var isFollowingFeedSelected: Bool {
        selectedFeed == "Following"
    }

    private var currentFeedLogs: [FeedActivityItem] {
        isFollowingFeedSelected ? followingLogs : forYouLogs
    }

    private var followingPublicLists: [UserList] {
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        return publicLists.filter { followingIds.contains($0.ownerId) || $0.ownerId == currentUserId }
    }

    private var homeFeedScopePicker: some View {
        Picker("Feed Scope", selection: $selectedFeed) {
            Image(systemName: "person.2.fill")
                .tag("Following")
                .accessibilityLabel(Text("Your Feed"))
            Image(systemName: "flame.fill")
                .tag("For You")
                .accessibilityLabel(Text("Trending"))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .tint(ColorTheme.accent)
        .frame(width: 112, height: 32)
        .onChange(of: selectedFeed) { _, _ in Haptics.select() }
    }

    private var homeFeedFilterButton: some View {
        Menu {
            ForEach(FeedFilter.allCases) { option in
                Button {
                    selectedFeedFilter = option
                    Haptics.select()
                } label: {
                    if selectedFeedFilter == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(ColorTheme.text)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ColorTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ColorTheme.separator, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }


    private var trustedPicksStrip: some View {
        let trusted = Array(currentFeedLogs.filter { $0.isTrustedGamer }.prefix(6))
        return Group {
            if trusted.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Trusted Picks")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.subtext)
                            .padding(.trailing, 2)
                        ForEach(trusted, id: \.id) { item in
                            Button {
                                logDetailOverlay = LogDetailOverlayContext(
                                    id: item.id,
                                    gameLog: item.gameLog,
                                    gameName: displayGameName(item),
                                    username: item.username,
                                    focusComment: false
                                )
                            } label: {
                                HStack(spacing: 6) {
                                    AvatarView(name: item.username, size: 18, avatarURL: item.avatarUrl)
                                        .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                                    Text(item.username)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(ColorTheme.text)
                                        .lineLimit(1)
                                    Image("trusted_flag")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 12, height: 12)
                                        .foregroundStyle(ColorTheme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(ColorTheme.surface)
                                        .overlay(Capsule().stroke(ColorTheme.separator, lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func feedBody(isLoading: Bool, logs: [FeedActivityItem], isFollowing: Bool) -> some View {
        return Group {
            if isLoading && logs.isEmpty {
                FeedSkeletonList()
            } else if logs.isEmpty {
                Text("No recent activity. (Showing last \(DAYS_BACK) days.)")
                    .foregroundColor(ColorTheme.subtext)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            } else {
                LazyVStack(spacing: 6, pinnedViews: [.sectionHeaders]) {
                    Section(header: feedHeader(isFollowing: isFollowing)) {
                        ForEach(Array(logs.enumerated()), id: \.element.id) { index, item in
                            let isReviewOverlayOpen = flippedCards.contains(item.gameLog.id)
                            feedRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !isReviewOverlayOpen else { return }
                                    presentExpandedFeedPreview(for: item)
                                }
                                .onAppear {
                                    if index >= logs.count - 5 {
                                        Task { await loadMore(isFollowing: isFollowing) }
                                    }
                                }
                                .padding(.horizontal, 0)
                                .padding(.vertical, 0)
                        }

                        if (isFollowing ? isLoadingFollowing : isLoadingForYou) {
                            ProgressView().tint(ColorTheme.accent).padding(.vertical, 8)
                        }
                    }
                }
                .padding(.vertical, 4)
                .transaction { t in t.animation = nil }
            }
        }
    }

    private func feedListsBody(lists: [UserList], title: String) -> some View {
        Group {
            if lists.isEmpty {
                EmptyView()
            } else {
                LazyVStack(spacing: 6, pinnedViews: [.sectionHeaders]) {
                    Section(header: feedListsHeader(title: title)) {
                        ForEach(lists, id: \.id) { list in
                            NavigationLink(
                                destination: ListDetailView(list: list, isOwner: list.ownerId == Auth.auth().currentUser?.uid)
                            ) {
                                publicListRow(list: list)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
                .transaction { t in t.animation = nil }
            }
        }
    }

    private func feedListsHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.subtext)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(ColorTheme.background)
    }


    private func feedPage(isFollowing: Bool) -> some View {
        let isLoading = isFollowing ? isLoadingFollowing : isLoadingForYou
        let logs = isFollowing ? followingLogs : forYouLogs
        let lists = isFollowing ? followingPublicLists : publicLists
        let showsLogs = selectedFeedFilter != .lists
        let showsLists = selectedFeedFilter != .logs

        if showsLogs && isLoading && logs.isEmpty && !showsLists {
            return AnyView(
                FeedSkeletonList()
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 68)
            )
        }

        return AnyView(
            ScrollView {
                if showsLogs {
                    feedBody(isLoading: isLoading, logs: logs, isFollowing: isFollowing)
                }
                if showsLists {
                    feedListsBody(
                        lists: lists,
                        title: isFollowing ? "Lists For You" : "Trending Lists"
                    )
                }
            }
            .refreshable { await refreshCurrentFeed() }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 68)
            }
            .transaction { t in t.animation = nil }
        )
    }

    private func feedRow(item: FeedActivityItem) -> some View {
        return feedRowCard(item: item)
            .onAppear {
                trackFeedImpressionIfNeeded(for: item)
            }
    }

    private func feedRowCard(item: FeedActivityItem) -> FeedRowCard {
        let me = Auth.auth().currentUser?.uid ?? ""
        let isMine = (item.gameLog.userId == me)
        let displayName = item.username
        let gameId = item.gameLog.gameId
        let reviewText = ContentModeration.displayReviewText(item.gameLog.review)
        let isFlipped = flippedCards.contains(item.gameLog.id)
        let userRating = item.gameLog.rating ?? 0
        let publisher = gamePublisherCache[gameId]
        let releaseYear = gameYearCache[gameId]
        let averageEntry = avgCache[gameId]
        let timestamp = formattedTimestampLines(item.gameLog.playDate.dateValue())

        return FeedRowCard(
            item: item,
            displayName: displayName,
            gameTitle: displayGameName(item),
            isMine: isMine,
            reviewText: reviewText,
            isFlipped: isFlipped,
            userRating: userRating,
            publisher: publisher,
            releaseYear: releaseYear,
            averageRating: averageEntry?.avg,
            averageCount: averageEntry?.count ?? 0,
            commentCount: commentCounts[item.gameLog.id] ?? 0,
            isCommented: commentedLogIds.contains(item.gameLog.id),
            isSaved: watchlistIds.contains(gameId),
            likeCount: likeCounts[item.gameLog.id] ?? 0,
            isLiked: likedSet.contains(item.gameLog.id),
            isLikePending: pendingLikeLogIds.contains(item.gameLog.id),
            isLikePulsing: likePulseIds.contains(item.gameLog.id),
            feedCardTheme: feedCardTheme,
            timestampRelative: timestamp.relative,
            timestampAbsolute: timestamp.absolute,
            onOpenLog: {
                logDetailOverlay = LogDetailOverlayContext(
                    id: item.id,
                    gameLog: item.gameLog,
                    gameName: displayGameName(item),
                    username: item.username,
                    focusComment: false
                )
            },
            onOpenSpoilerReview: {
                spoilerReviewItem = item
            },
            onToggleReview: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    _ = flippedCards.insert(item.gameLog.id)
                }
            },
            onCloseReview: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = flippedCards.remove(item.gameLog.id)
                }
            },
            onOpenRatings: { avg in
                openRatingsOverlay(for: item, avg: avg)
            },
            onOpenAverageFallback: {
                logOverlayGame = Game(
                    id: item.gameLog.gameId,
                    name: item.gameName,
                    cover: item.gameLog.cover,
                    firstReleaseDate: nil, genres: nil, platforms: nil,
                    rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                )
            },
            onOpenOwnProfile: {
                currentTab = .profile
            },
            onAddToList: {
                addToListGame = Game(
                    id: gameId,
                    name: displayGameName(item),
                    cover: item.gameLog.cover,
                    firstReleaseDate: nil, genres: nil, platforms: nil,
                    rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                )
            },
            onSaveGame: {
                pendingSaveGame = Game(
                    id: gameId,
                    name: displayGameName(item),
                    cover: item.gameLog.cover,
                    firstReleaseDate: nil, genres: nil, platforms: nil,
                    rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                )
                openBookmarksOverlay()
            },
            onToggleLike: {
                handleFeedLikeToggle(for: item.gameLog)
            }
        )
    }

    private func feedCardFront(
        item: FeedActivityItem,
        displayName: String,
        isMine: Bool,
        userRating: Double,
        hasReview: Bool,
        gameId: Int,
        publisher: String?,
        releaseYear: Int?
    ) -> some View {
        let contentColumnHeight: CGFloat = coverHeight
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                profileHeaderLink(item: item, displayName: displayName, isMine: isMine)
                Spacer()
                gamerLndBadge(for: item)
            }

            ZStack(alignment: Alignment(horizontal: .trailing, vertical: .center)) {
                HStack(alignment: .top, spacing: 12) {
                    let thumbWidth: CGFloat = coverWidth
                    let thumbHeight: CGFloat = coverHeight
                    let cardAccent = userRating > 0 ? ColorTheme.ratingBandColor(for: userRating) : ColorTheme.separator
                    ZStack(alignment: .topTrailing) {
                        if let imgId = item.gameLog.cover?.imageId {
                            GameCoverImage(id: imgId, preset: .custom(width: thumbWidth), cornerRadius: 12)
                                .frame(width: thumbWidth, height: thumbHeight)
                                .clipped()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(cardAccent.opacity(0.72), lineWidth: 1.2)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ColorTheme.separator.opacity(0.2))
                                .frame(width: thumbWidth, height: thumbHeight)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(cardAccent.opacity(0.72), lineWidth: 1.2)
                                )
                        }

                    }

                    VStack(alignment: .leading, spacing: 6) {
                        let cardTitle = displayGameName(item)
                        Text(cardTitle)
                            .font(feedCardTitleFont(for: cardTitle))
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(3)
                            .minimumScaleFactor(0.84)
                            .allowsTightening(true)
                            .lineSpacing(1)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)

                        HStack(spacing: 6) {
                            if let publisher = publisher, !publisher.isEmpty {
                                Text(publisher)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.subtext)
                                    .lineLimit(1)
                            }
                            if let year = releaseYear {
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.subtext)
                                Text(String(year))
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.subtext)
                            }
                            Spacer(minLength: 0)
                        }

                        Rectangle()
                            .fill(cardAccent.opacity(0.58))
                            .frame(height: 1)

                        HStack(spacing: 8) {
                            if hasReview {
                                Button {
                                    if item.gameLog.containsSpoilers {
                                        spoilerReviewItem = item
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            _ = flippedCards.insert(item.gameLog.id)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "text.quote")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.white)
                                        ZStack {
                                            ForEach(0..<4, id: \.self) { i in
                                                let offsets: [CGSize] = [
                                                    CGSize(width: -0.6, height: 0),
                                                    CGSize(width: 0.6, height: 0),
                                                    CGSize(width: 0, height: -0.6),
                                                    CGSize(width: 0, height: 0.6)
                                                ]
                                                Text("Read Review")
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundColor(.black.opacity(0.55))
                                                    .offset(offsets[i])
                                            }
                                            Text("Read Review")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundColor(.white.opacity(0.99))
                                                .shadow(color: .black.opacity(0.35), radius: 0.8, x: 0, y: 0.6)
                                        }
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardAccent.opacity(0.62), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("No Review")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(ColorTheme.subtext)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardAccent.opacity(0.62), lineWidth: 1))
                                    .opacity(0.6)
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                                .highPriorityGesture(TapGesture().onEnded({}))
                            }
                            Spacer(minLength: 0)
                            if userRating > 0 {
                                ratingHeartText(
                                    text: formatRatingValue(userRating),
                                    color: ColorTheme.ratingBandColor(for: userRating),
                                    size: 60
                                )
                            } else {
                                ratingHeartText(
                                    text: "—",
                                    color: ColorTheme.subtext,
                                    size: 60,
                                    empty: true
                                )
                            }
                        }
                        .frame(height: 56, alignment: .center)
                        .padding(.top, 1)

                        Spacer(minLength: 6)

                        HStack(spacing: 12) {
                            Button {
                                logDetailOverlay = LogDetailOverlayContext(
                                    id: item.id,
                                    gameLog: item.gameLog,
                                    gameName: displayGameName(item),
                                    username: item.username,
                                    focusComment: false
                                )
                            } label: {
                                actionIcon(
                                    "bubble.right",
                                    count: commentCounts[item.gameLog.id] ?? 0,
                                    tint: commentedLogIds.contains(item.gameLog.id) ? ColorTheme.accent : .white,
                                    countHighlighted: commentedLogIds.contains(item.gameLog.id),
                                    size: .large
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                addToListGame = Game(
                                    id: gameId,
                                    name: displayGameName(item),
                                    cover: item.gameLog.cover,
                                    firstReleaseDate: nil, genres: nil, platforms: nil,
                                    rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                                )
                            } label: {
                                actionIcon("text.badge.plus", count: nil, size: .large)
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(ColorTheme.separator.opacity(0.45))
                                .frame(width: 1, height: 22)

                            Button {
                                pendingSaveGame = Game(
                                    id: gameId,
                                    name: displayGameName(item),
                                    cover: item.gameLog.cover,
                                    firstReleaseDate: nil, genres: nil, platforms: nil,
                                    rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                                )
                                openBookmarksOverlay()
                            } label: {
                                let isSaved = watchlistIds.contains(gameId)
                                actionIcon(isSaved ? "tray.and.arrow.down.fill" : "tray.and.arrow.down",
                                           count: nil,
                                           tint: isSaved ? ColorTheme.accent : .white,
                                           size: .large)
                            }
                            .buttonStyle(.plain)

                            let isLiked = likedSet.contains(item.gameLog.id)
                            let isLikePending = pendingLikeLogIds.contains(item.gameLog.id)
                            Button {
                                handleFeedLikeToggle(for: item.gameLog)
                            } label: {
                                actionIcon(isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                                           count: likeCounts[item.gameLog.id] ?? 0,
                                           tint: isLiked ? ColorTheme.accent : .white,
                                           countHighlighted: isLiked,
                                           size: .large)
                            }
                            .scaleEffect(likePulseIds.contains(item.gameLog.id) ? 1.14 : 1.0)
                            .buttonStyle(.plain)
                            .disabled(isLikePending)
                            .opacity(isLikePending ? 0.72 : 1)
                            .transaction { t in t.animation = nil }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 40, alignment: .center)
                        .padding(.top, 2)
                        .padding(.bottom, 0)

                    }
                    .frame(height: contentColumnHeight, alignment: .top)
                }

            }
        }
        .padding(14)
        .background(feedCardBackground(rating: userRating))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ColorTheme.separator, lineWidth: 1)
        )
        .shadow(color: Color(red: 0, green: 0, blue: 0).opacity(0.18), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    private func reviewOverlay(item: FeedActivityItem, reviewText: String, displayName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    AvatarView(name: displayName, size: 20, avatarURL: item.avatarUrl)
                        .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                    Text("\(displayName)’s review")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                    if item.isTrustedGamer {
                        trustedGamerBadge
                    }
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        _ = flippedCards.remove(item.gameLog.id)
                    }
                } label: {
                    OverlayCloseButton()
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            Text(displayGameName(item))
                .font(.caption2.weight(.semibold))
                .foregroundColor(ColorTheme.subtext)
                .frame(maxWidth: .infinity, alignment: .center)

            ScrollView {
                Text(ContentModeration.displayReviewText(reviewText))
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                NavigationLink(
                    destination: GameDetailView(
                        game: Game(
                            id: item.gameLog.gameId,
                            name: displayGameName(item),
                            cover: item.gameLog.cover,
                            firstReleaseDate: nil, genres: nil, platforms: nil,
                            rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                        )
                    )
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                        Text("Review this game")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(ColorTheme.black.opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator.opacity(0.6), lineWidth: 1))
        )
    }

    private func gamerLndBadge(for item: FeedActivityItem) -> some View {
        let key = item.gameLog.gameId
        let cached = avgCache[key]
        return Group {
            if let cached = cached, let avg = cached.avg, cached.count > 0 {
                Button {
                    openRatingsOverlay(for: item, avg: avg)
                } label: {
                    HStack(spacing: 0) {
                        AverageHeartBadge(value: avg, size: 26)
                    }
                    .padding(.trailing, 6)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    logOverlayGame = Game(
                        id: item.gameLog.gameId,
                        name: item.gameName,
                        cover: item.gameLog.cover,
                        firstReleaseDate: nil, genres: nil, platforms: nil,
                        rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                    )
                } label: {
                    HStack(spacing: 0) {
                        ratingHeartText(
                            text: "-",
                            color: ColorTheme.separator,
                            size: 26,
                            empty: true
                        )
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func profileHeaderLink(item: FeedActivityItem, displayName: String, isMine: Bool) -> some View {
        if isMine {
            Button {
                currentTab = .profile
            } label: {
                profileHeaderIdentity(item: item, displayName: displayName, isMine: isMine)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: ProfileView(userId: item.gameLog.userId)) {
                profileHeaderIdentity(item: item, displayName: displayName, isMine: isMine)
            }
            .buttonStyle(.plain)
        }
    }

    private func profileHeaderIdentity(item: FeedActivityItem, displayName: String, isMine: Bool) -> some View {
        return HStack(spacing: 8) {
            AvatarView(name: displayName, size: 28, avatarURL: item.avatarUrl)
                .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

            HStack(spacing: 3) {
                Text(displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if item.isTrustedGamer {
                    trustedGamerBadge
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            let timestamp = formattedTimestampLines(item.gameLog.playDate.dateValue())
            VStack(alignment: .trailing, spacing: 1) {
                Text(timestamp.relative)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(ColorTheme.subtext)
                    .lineLimit(1)
                Text(timestamp.absolute)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(ColorTheme.subtext.opacity(0.88))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 36, alignment: .leading)
    }


    private func addToListOverlay(game: Game) -> some View {
        ZStack {
            Color.black.opacity(0.64)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addToListGame = nil
                    }
                }

            AddToListSheet(ownerId: Auth.auth().currentUser?.uid ?? "", game: game) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    addToListGame = nil
                }
            }
                .preferredColorScheme(ColorTheme.preferredScheme)
                .frame(width: min(UIScreen.main.bounds.width - 20, 404), height: min(UIScreen.main.bounds.height - 80, 720))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ColorTheme.separator, lineWidth: 1)
                )
                .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func ratingHeartText(text: String, color: Color, size: CGFloat, empty: Bool = false) -> some View {
        ZStack {
            let numericValue = Double(text) ?? 0
            PixelHeartIcon(
                color: color,
                size: size,
                empty: empty,
                perfectScore: ColorTheme.isPerfectScore(numericValue)
            )
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let offsets: [CGSize] = [
                        CGSize(width: -0.9, height: 0),
                        CGSize(width: 0.9, height: 0),
                        CGSize(width: 0, height: -0.9),
                        CGSize(width: 0, height: 0.9)
                    ]
                    Text(text)
                        .font(.system(size: max(8, size * 0.315), weight: .heavy, design: .rounded))
                        .foregroundColor(.black.opacity(0.8))
                        .offset(offsets[i])
                }
                Text(text)
                    .font(.system(size: max(8, size * 0.315), weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(empty ? 0.82 : 0.99))
                    .shadow(color: .black.opacity(0.45), radius: 1.2, x: 0, y: 0.8)
            }
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .padding(.horizontal, max(2, size * 0.12))
            .offset(y: -max(0.6, size * 0.035))
        }
    }

    private var trustedGamerBadge: some View {
        Image("trusted_flag")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .foregroundStyle(ColorTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(4)
        .background(
            Capsule()
                .fill(ColorTheme.surface)
                .overlay(Capsule().stroke(ColorTheme.separator, lineWidth: 1))
        )
    }


    fileprivate enum ActionIconSize {
        case regular
        case large

        var container: CGFloat { self == .large ? 40 : 32 }
        var iconFont: Font { self == .large ? .body.weight(.semibold) : .footnote.weight(.semibold) }
        var countFont: Font { self == .large ? .caption.weight(.semibold) : .caption2.weight(.semibold) }
    }

    private func actionIcon(_ systemName: String, count: Int?, tint: Color = .white, countHighlighted: Bool = true, size: ActionIconSize = .regular) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(size.iconFont)
                .foregroundColor(tint)
                .frame(width: size.container, height: size.container)
                .contentShape(Circle())
            if let count = count {
                Text("\(min(max(count, 0), 99))")
                    .font(size.countFont)
                    .foregroundColor(countHighlighted ? .white : ColorTheme.subtext)
                    .shadow(color: .black.opacity(0.65), radius: 0.8, x: 0, y: 0.6)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(countHighlighted ? ColorTheme.accent : Color.clear)
                            .overlay(
                                Capsule().stroke(
                                    countHighlighted ? ColorTheme.accent : ColorTheme.separator.opacity(0.9),
                                    lineWidth: 1
                                )
                            )
                    )
                    .offset(x: 8, y: -6)
            }
        }
    }

    private func preloadLikeState(for logIds: [String]) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let unique = Array(Set(logIds)).filter { !($0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        guard !unique.isEmpty else { return }

        for chunkStart in stride(from: 0, to: unique.count, by: 10) {
            let chunk = Array(unique[chunkStart..<min(chunkStart + 10, unique.count)])
            db.collection("review_likes")
                .whereField("user_id", isEqualTo: uid)
                .whereField("log_id", in: chunk)
                .getDocuments { snap, _ in
                    let ids = Set((snap?.documents ?? []).compactMap { $0.data()["log_id"] as? String })
                    DispatchQueue.main.async {
                        self.likedSet.formUnion(ids)
                    }
                }
        }
    }

    private func preloadLikeCounts(for logIds: [String]) {
        let unique = Array(Set(logIds)).filter { !($0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        guard !unique.isEmpty else { return }

        for chunkStart in stride(from: 0, to: unique.count, by: 10) {
            let chunk = Array(unique[chunkStart..<min(chunkStart + 10, unique.count)])
            db.collection("review_likes")
                .whereField("log_id", in: chunk)
                .getDocuments { snap, _ in
                    let docs = snap?.documents ?? []
                    var counts: [String: Int] = [:]
                    for id in chunk { counts[id] = 0 }
                    for doc in docs {
                        if let logId = doc.data()["log_id"] as? String {
                            counts[logId, default: 0] += 1
                        }
                    }
                    DispatchQueue.main.async {
                        for (logId, count) in counts {
                            likeCounts[logId] = count
                        }
                    }
                }
        }
    }

    private func preloadCommentState(for logIds: [String]) {
        let unique = Array(Set(logIds)).filter { !($0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        guard !unique.isEmpty else { return }
        let currentUserId = Auth.auth().currentUser?.uid ?? ""

        for chunkStart in stride(from: 0, to: unique.count, by: 10) {
            let chunk = Array(unique[chunkStart..<min(chunkStart + 10, unique.count)])
            db.collection("review_comments")
                .whereField("log_id", in: chunk)
                .getDocuments { snap, _ in
                    let docs = snap?.documents ?? []
                    var counts: [String: Int] = [:]
                    var commented: Set<String> = []
                    for id in chunk { counts[id] = 0 }
                    for doc in docs {
                        let data = doc.data()
                        if let logId = data["log_id"] as? String {
                            counts[logId, default: 0] += 1
                            if !currentUserId.isEmpty,
                               (data["user_id"] as? String) == currentUserId {
                                commented.insert(logId)
                            }
                        }
                    }
                    DispatchQueue.main.async {
                        for (logId, count) in counts {
                            commentCounts[logId] = count
                        }
                        commentedLogIds.formUnion(commented)
                    }
                }
        }
    }

    private func trackFeedImpressionIfNeeded(for item: FeedActivityItem) {
        #if DEBUG
        return
        #else
        guard let viewerId = Auth.auth().currentUser?.uid else { return }
        guard viewerId != item.gameLog.userId else { return }
        let key = "\(viewerId)|feed|\(item.gameLog.id)"
        guard !trackedImpressionKeys.contains(key) else { return }
        trackedImpressionKeys.insert(key)
        db.collection("log_impressions").addDocument(data: [
            "log_id": item.gameLog.id,
            "log_owner_id": item.gameLog.userId,
            "viewer_user_id": viewerId,
            "source": "feed",
            "created_at": FieldValue.serverTimestamp()
        ])
        #endif
    }

    private func ratingBandColor(for value: Double) -> Color {
        ColorTheme.ratingBandColor(for: value)
    }

    private func feedCardTitleFont(for title: String) -> Font {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count

        if count <= 18 {
            return .system(size: 20, weight: .semibold, design: .default)
        } else if count <= 36 {
            return .system(size: 17, weight: .semibold, design: .default)
        } else if count <= 64 {
            return .system(size: 14.5, weight: .semibold, design: .default)
        } else {
            return .system(size: 13, weight: .semibold, design: .default)
        }
    }

    private func feedCardBackground(rating: Double) -> some View {
        let pair: (Color, Color)
        let accentStroke: Color
        let perfectScore = ColorTheme.isPerfectScore(rating)
        switch feedCardTheme {
        case "glass":
            pair = (ColorTheme.separator, ColorTheme.subtext)
            accentStroke = ColorTheme.separator
        default:
            if rating > 0 {
                if perfectScore {
                    pair = (ColorTheme.gold, ColorTheme.xpGreen)
                    accentStroke = ColorTheme.gold
                } else {
                    let c = ratingBandColor(for: rating)
                    pair = (c, c.opacity(0.65))
                    accentStroke = c
                }
            } else {
                pair = (ColorTheme.separator, ColorTheme.subtext)
                accentStroke = ColorTheme.separator
            }
        }
        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(ColorTheme.surface)
            if perfectScore {
                LinearGradient(
                    colors: ColorTheme.perfectScoreRainbow.map { $0.opacity(0.16) } + [ColorTheme.surface.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                LinearGradient(
                    colors: [pair.0.opacity(0.24), pair.1.opacity(0.14), ColorTheme.surface.opacity(0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: perfectScore
                            ? ColorTheme.perfectScoreRainbow.map { $0.opacity(0.34) }
                            : [Color.white.opacity(0.12), Color.clear, pair.0.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accentStroke.opacity(0.56), lineWidth: 1)
        }
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let relative = Self.feedRelativeFormatter.localizedString(for: date, relativeTo: Date())
        return "\(relative) • \(Self.feedAbsoluteFormatter.string(from: date))"
    }

    private func formattedTimestampLines(_ date: Date) -> (relative: String, absolute: String) {
        let relative = Self.feedRelativeFormatter.localizedString(for: date, relativeTo: Date())
        return (relative, Self.feedAbsoluteFormatter.string(from: date))
    }

    private func publicListRow(list: UserList) -> some View {
        HStack(alignment: .top, spacing: 12) {
            listPreviewStack(list.id)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(list.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                    Text(list.type.titleText)
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                }
                HStack(spacing: 6) {
                    let ownerName = listOwnerNames[list.ownerId] ?? "User"
                    Image(systemName: "person.fill.checkmark")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                    Text(ownerName)
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                    Text("• \(list.itemCount) games")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ColorTheme.background)
        .onAppear {
            if listOwnerNames[list.ownerId] == nil {
                Task { await fillListOwnerNamesIfNeeded([list.ownerId]) }
            }
            if publicListPreviews[list.id] == nil {
                Task { await fetchPublicListPreview(listId: list.id) }
            }
        }
        .overlay(
            Rectangle()
                .fill(ColorTheme.separator.opacity(0.6))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func listPreviewStack(_ listId: String) -> some View {
        let covers = publicListPreviews[listId] ?? []
        return HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { idx in
                if idx < covers.count {
                    GameCoverImage(id: covers[idx], preset: .custom(width: 28), cornerRadius: 5)
                        .frame(width: 28, height: 36)
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(ColorTheme.separator.opacity(0.2))
                        .frame(width: 28, height: 36)
                }
            }
        }
    }

    private var floatingCreateButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCreateMenu.toggle()
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.96), radius: 0, x: 1, y: 0)
                .shadow(color: .black.opacity(0.96), radius: 0, x: -1, y: 0)
                .shadow(color: .black.opacity(0.96), radius: 0, x: 0, y: 1)
                .shadow(color: .black.opacity(0.96), radius: 0, x: 0, y: -1)
                .frame(width: 52, height: 52)
                .background(Circle().fill(ColorTheme.accent))
                .overlay(Circle().stroke(.black.opacity(0.88), lineWidth: 1.2))
                .shadow(color: ColorTheme.black.opacity(0.25), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func createMenuOverlay() -> some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCreateMenu = false
                    }
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Quick Actions")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCreateMenu = false
                        }
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }
                createMenuAction(label: "Log a Game", system: "square.and.pencil") {
                    currentTab = .explore
                    showCreateMenu = false
                }
                createMenuAction(label: "Write a Review", system: "text.quote") {
                    currentTab = .explore
                    showCreateMenu = false
                }
                createMenuAction(label: "Add to List", system: "text.badge.plus") {
                    currentTab = .profile
                    showCreateMenu = false
                }
                createMenuAction(label: "Search Games", system: "magnifyingglass") {
                    currentTab = .explore
                    showCreateMenu = false
                }
            }
            .padding(16)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ColorTheme.black.opacity(0.62))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator.opacity(0.7), lineWidth: 1))
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func createMenuAction(label: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: system)
                    .font(.body.weight(.semibold))
                    .frame(width: 22)
                Text(label)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.subtext)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(ColorTheme.text)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func feedHeader(isFollowing: Bool) -> some View {
        Color.clear.frame(height: 0)
    }

    private func toggleWatchlist(gameId: Int, name: String, cover: Game.Cover?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let doc = db.collection("users").document(uid)
        doc.getDocument { snap, _ in
            var list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            if let idx = list.firstIndex(where: { ($0["id"] as? Int) == gameId }) {
                list.remove(at: idx)
                watchlistIds.remove(gameId)
            } else {
                var dict: [String: Any] = ["id": gameId, "name": name, "added_at": Timestamp(date: Date())]
                if let img = cover?.imageId { dict["cover_id"] = img }
                list.append(dict)
                watchlistIds.insert(gameId)
            }
            doc.setData(["watchlist_games": list], merge: true)
        }
    }

    private func showFeedHintTemporarily() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showFeedHint = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showFeedHint = false
            }
        }
    }

    private var feedHintFloating: some View {
        Text(feedHintText(feed: selectedFeed, filter: selectedFeedFilter))
            .font(.caption.weight(.semibold))
            .foregroundColor(ColorTheme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ColorTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
            )
    }

    private func feedHintText(feed: String, filter: FeedFilter) -> String {
        switch (feed, filter) {
        case ("Following", _):
            return "From People You Follow"
        case ("For You", _):
            return "Trending Across GamerLnd"
        default:
            return "Trending Across GamerLnd"
        }
    }

    private func openRatingsOverlay(for item: FeedActivityItem, avg: Double) {
        openRatingsOverlay(
            gameId: item.gameLog.gameId,
            gameName: displayGameName(item),
            cover: item.gameLog.cover,
            avg: avg
        )
    }

    private func openRatingsOverlay(gameId: Int, gameName: String, cover: Game.Cover?, avg: Double?) {
        ratingsOverlayGameId = gameId
        ratingsOverlayName = gameName
        ratingsOverlayCover = cover
        ratingsOverlayAvg = avg
        ratingsOverlayFilter = "All"
        ratingsOverlayList = []
        ratingsOverlayReviewEntry = nil
        ratingsOverlayLoading = true
        withAnimation(.easeInOut(duration: 0.2)) {
            showRatingsOverlay = true
        }
        Task { await loadRatingsOverlayData(gameId: gameId) }
    }

    private func loadRatingsOverlayData(gameId: Int) async {
        do {
            var followingSet = followingIds
            if followingSet.isEmpty, let uid = Auth.auth().currentUser?.uid {
                let fetched = await fetchFollowingIds(for: uid)
                followingSet = Set(fetched)
                await MainActor.run { self.followingIds = followingSet }
            }
            let snap = try await db.collection("game_logs")
                .whereField("game_id", isEqualTo: gameId)
                .getDocuments()

            var entries: [RatingsOverlayEntry] = []
            let currentUserId = Auth.auth().currentUser?.uid

            for d in snap.documents {
                let data = d.data()
                let uid = data["user_id"] as? String ?? ""
                if uid.isEmpty { continue }

                let ratingValue: Double?
                if let r = data["rating"] as? Double, r > 0 {
                    ratingValue = r
                } else if let rI = data["rating"] as? Int, rI > 0 {
                    ratingValue = Double(rI)
                } else if let rN = data["rating"] as? NSNumber, rN.doubleValue > 0 {
                    ratingValue = rN.doubleValue
                } else {
                    ratingValue = nil
                }
                guard let val = ratingValue else { continue }

                let review = (data["review"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(
                    RatingsOverlayEntry(
                        userId: uid,
                        displayName: "User",
                        username: "",
                        rating: val,
                        isTrusted: trustedCache[uid] ?? false,
                        isFollowing: followingSet.contains(uid),
                        review: review?.isEmpty == true ? nil : review,
                        isCurrentUser: uid == currentUserId
                    )
                )
            }

            let userIds = Array(Set(entries.map { $0.userId }))
            await fillUsernameCacheIfNeeded(userIds)
            let mapped = entries.map { entry in
                RatingsOverlayEntry(
                    userId: entry.userId,
                    displayName: displayNameCache[entry.userId] ?? usernameCache[entry.userId] ?? "User",
                    username: usernameCache[entry.userId] ?? "",
                    rating: entry.rating,
                    isTrusted: trustedCache[entry.userId] ?? false,
                    isFollowing: entry.isFollowing,
                    review: entry.review,
                    isCurrentUser: entry.isCurrentUser
                )
            }
            let sorted = mapped.sorted { lhs, rhs in
                if lhs.isCurrentUser != rhs.isCurrentUser { return lhs.isCurrentUser && !rhs.isCurrentUser }
                if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

            await MainActor.run {
                ratingsOverlayList = sorted
                ratingsOverlayLoading = false
            }
        } catch {
            await MainActor.run { ratingsOverlayLoading = false }
        }
    }

    private func loadWatchlistIds() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            db.collection("users").document(uid).getDocument { snap, _ in
                let list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
                let ids = list.compactMap { $0["id"] as? Int }
                self.watchlistIds = Set(ids)
                cont.resume()
            }
        }
    }

    private func loadPublicLists() async {
        do {
            let snap = try await db.collection("lists")
                .whereField("is_public", isEqualTo: true)
                .order(by: "updated_at", descending: true)
                .limit(to: 12)
                .getDocuments()
            let lists: [UserList] = snap.documents.compactMap { UserList(id: $0.documentID, data: $0.data()) }
            var previews: [String: [String]] = [:]
            for d in snap.documents {
                if let arr = d.data()["preview_cover_ids"] as? [String], !arr.isEmpty {
                    previews[d.documentID] = Array(arr.prefix(4))
                }
            }
            await MainActor.run {
                self.publicLists = lists
                for (k, v) in previews { self.publicListPreviews[k] = v }
            }
            let ownerIds = Array(Set(lists.map { $0.ownerId }))
            await fillListOwnerNamesIfNeeded(ownerIds)
            await loadPublicListPreviews(lists)
        } catch {
            await MainActor.run { self.publicLists = [] }
        }
    }

    private func loadPublicListPreviews(_ lists: [UserList]) async {
        let missing = lists.map { $0.id }.filter { publicListPreviews[$0] == nil }
        if missing.isEmpty { return }
        for listId in missing {
            if Task.isCancelled { return }
            await fetchPublicListPreview(listId: listId)
        }
    }

    private func fetchPublicListPreview(listId: String) async {
        let db = self.db
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            db.collection("lists").document(listId).collection("items")
                .limit(to: 4)
                .getDocuments { snap, err in
                    if err != nil {
                        self.publicListPreviews[listId] = []
                        cont.resume()
                        return
                    }
                    let coverIds = (snap?.documents ?? []).compactMap { d -> String? in
                        let data = d.data()
                        if let flat = data["cover_image_id"] as? String, !flat.isEmpty { return flat }
                        if let cover = data["cover"] as? [String: Any],
                           let embedded = cover["image_id"] as? String,
                           !embedded.isEmpty { return embedded }
                        return nil
                    }
                    if !coverIds.isEmpty {
                        self.publicListPreviews[listId] = coverIds
                        cont.resume()
                        return
                    }
                    db.collection("list_items")
                        .whereField("list_id", isEqualTo: listId)
                        .limit(to: 4)
                        .getDocuments { snap2, err2 in
                            if err2 != nil {
                                self.publicListPreviews[listId] = []
                                cont.resume()
                                return
                            }
                            let coverIds2 = (snap2?.documents ?? []).compactMap { d -> String? in
                                let data = d.data()
                                if let flat = data["cover_image_id"] as? String, !flat.isEmpty { return flat }
                                if let cover = data["cover"] as? [String: Any],
                                   let embedded = cover["image_id"] as? String,
                                   !embedded.isEmpty { return embedded }
                                return nil
                            }
                            self.publicListPreviews[listId] = coverIds2
                            cont.resume()
                        }
                }
        }
    }

    private func fillListOwnerNamesIfNeeded(_ ownerIds: [String]) async {
        let missing = ownerIds.filter { listOwnerNames[$0] == nil }
        if missing.isEmpty { return }
        let chunks = stride(from: 0, to: missing.count, by: 10).map { Array(missing[$0..<min($0+10, missing.count)]) }
        await withTaskGroup(of: Void.self) { group in
            for chunk in chunks {
                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        let db = Firestore.firestore()
                        db.collection("users")
                            .whereField("id", in: chunk)
                            .getDocuments { snap, _ in
                                if let docs = snap?.documents {
                                    for d in docs {
                                        let data = d.data()
                                        if let id = data["id"] as? String {
                                            let name = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                                            self.listOwnerNames[id] = name
                                        }
                                    }
                                }
                                cont.resume()
                            }
                    }
                }
            }
            for await _ in group { }
        }
        let stillMissing = ownerIds.filter { listOwnerNames[$0] == nil }
        if stillMissing.isEmpty { return }
        await withTaskGroup(of: Void.self) { group in
            for uid in stillMissing {
                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        let db = Firestore.firestore()
                        db.collection("users").document(uid).getDocument { snap, _ in
                            if let data = snap?.data() {
                                let name = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                                self.listOwnerNames[uid] = name
                            } else {
                                self.listOwnerNames[uid] = "User"
                            }
                            cont.resume()
                        }
                    }
                }
            }
            for await _ in group { }
        }
    }

    private func ratingsOverlayView() -> some View {
        let accent = ColorTheme.ratingBandColor(for: ratingsOverlayAvg ?? 7.5)
        let filteredRows = filteredRatingsOverlayRows()

        return ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRatingsOverlay = false
                    }
                }

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Text("Ratings")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRatingsOverlay = false
                        }
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 32)

                HStack(alignment: .top, spacing: 14) {
                    if let cover = ratingsOverlayCover?.imageId {
                        GameCoverImage(id: cover, preset: .custom(width: 104), cornerRadius: 14)
                            .frame(width: 104, height: 139)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(accent.opacity(0.72), lineWidth: 1.2)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(ColorTheme.surface)
                            .frame(width: 104, height: 139)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(accent.opacity(0.72), lineWidth: 1.2)
                            )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(ratingsOverlayName)
                            .font(.headline.weight(.bold))
                            .foregroundColor(ColorTheme.text)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        if let avg = ratingsOverlayAvg {
                            HStack(spacing: 12) {
                                AverageHeartBadge(value: avg, size: 38)
                                    .padding(.horizontal, 8)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("GamerLnd Average")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(ColorTheme.text)
                                    Text(formatRatingValue(avg))
                                        .font(.title3.weight(.heavy))
                                        .foregroundColor(ColorTheme.ratingBandColor(for: avg))
                                    Text("See ratings from everyone, trusted gamers, or people you follow.")
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.subtext)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        } else {
                            Text("No ratings yet")
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: 150, alignment: .top)

                HStack(spacing: 8) {
                    ratingsOverlayFilterButton("All", accent: accent)
                    ratingsOverlayFilterButton("Trusted", accent: accent)
                    ratingsOverlayFilterButton("Following", accent: accent)
                }
                .frame(maxWidth: .infinity)

                let listWidth: CGFloat = 348
                let rowHeight: CGFloat = 52
                let stickyCurrentUserRow = filteredRows.first(where: { $0.isCurrentUser })
                let scrollRows = filteredRows.filter { !$0.isCurrentUser }
                if ratingsOverlayLoading {
                    ProgressView().tint(ColorTheme.accent)
                        .frame(width: listWidth, height: 360)
                } else {
                    VStack(spacing: 8) {
                        if filteredRows.isEmpty {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(ColorTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.44), lineWidth: 1))
                                .frame(width: listWidth, height: rowHeight)
                                .overlay(
                                    Text(ratingsOverlayFilter == "Trusted" ? "No trusted ratings yet" : ratingsOverlayFilter == "Following" ? "No following ratings yet" : "No ratings yet")
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.subtext)
                                )
                        } else {
                            if let stickyCurrentUserRow {
                                ratingsOverlayRow(stickyCurrentUserRow, accent: accent, listWidth: listWidth, rowHeight: rowHeight)
                            }

                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(scrollRows, id: \.userId) { row in
                                        ratingsOverlayRow(row, accent: accent, listWidth: listWidth, rowHeight: rowHeight)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .frame(width: listWidth, height: stickyCurrentUserRow == nil ? 360 : 300)
                        }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(width: 380, height: 640)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(ColorTheme.black.opacity(0.84))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.6), lineWidth: 1.2))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            if let reviewEntry = ratingsOverlayReviewEntry {
                ratingsReviewOverlay(entry: reviewEntry, accent: accent)
            }
        }
    }

    private func filteredRatingsOverlayRows() -> [RatingsOverlayEntry] {
        switch ratingsOverlayFilter {
        case "Trusted":
            return ratingsOverlayList.filter { $0.isTrusted }
        case "Following":
            return ratingsOverlayList.filter { $0.isFollowing || $0.isCurrentUser }
        default:
            return ratingsOverlayList
        }
    }

    private func ratingsOverlayFilterButton(_ title: String, accent: Color) -> some View {
        let isSelected = ratingsOverlayFilter == title
        return Button {
            Haptics.select()
            ratingsOverlayFilter = title
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? accent : ColorTheme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? ColorTheme.black : ColorTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? accent : ColorTheme.separator, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func ratingsOverlayRow(_ row: RatingsOverlayEntry, accent: Color, listWidth: CGFloat, rowHeight: CGFloat) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(row.displayName)
                    .foregroundColor(row.isCurrentUser ? ColorTheme.accent : ColorTheme.text)
                if row.isTrusted {
                    trustedGamerBadge
                }
            }
            Spacer()
            if let review = row.review, !review.isEmpty {
                Button {
                    ratingsOverlayReviewEntry = row
                } label: {
                    Image(systemName: "text.quote")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(accent.opacity(0.24))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(accent.opacity(0.58), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read review")
            }
            RatingHeartBadge(value: row.rating, size: 26)
        }
        .padding(.horizontal, 12)
        .frame(width: listWidth, height: rowHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.38), lineWidth: 1))
    }

    private func ratingsReviewOverlay(entry: RatingsOverlayEntry, accent: Color) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { ratingsOverlayReviewEntry = nil }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(
                        name: entry.displayName,
                        size: 30,
                        avatarURL: avatarCache[entry.userId]
                    )
                    .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.isCurrentUser ? "Your Review" : entry.displayName)
                                .font(.headline.weight(.bold))
                                .foregroundColor(ColorTheme.text)
                            if entry.isTrusted {
                                trustedGamerBadge
                            }
                        }
                        if !ratingsOverlayName.isEmpty {
                            Text(ratingsOverlayName)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ColorTheme.subtext)
                        }
                    }
                    Spacer()
                }

                HStack {
                    Spacer()
                    ratingHeartText(
                        text: formatRatingValue(entry.rating),
                        color: ColorTheme.ratingBandColor(for: entry.rating),
                        size: 44
                    )
                    Spacer()
                }

                ScrollView {
                    Text(ContentModeration.displayReviewText(entry.review))
                        .font(.body)
                        .foregroundColor(ColorTheme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .frame(width: 336, height: 340)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(ColorTheme.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(accent.opacity(0.62), lineWidth: 1.1)
                    )
            )
            .overlay(alignment: .topTrailing) {
                Button {
                    ratingsOverlayReviewEntry = nil
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    private func openBookmarksOverlay() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showBookmarksOverlay = true
        }
        Task { await loadBookmarksOverlayData() }
    }

    private func loadBookmarksOverlayData() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            let list = snap.data()?["watchlist_games"] as? [[String: Any]] ?? []
            var entries: [BookmarkEntry] = list.compactMap { dict in
                guard let id = dict["id"] as? Int else { return nil }
                let name = dict["name"] as? String ?? "Game #\(id)"
                let coverId = dict["cover_id"] as? String
                var addedAt: Date? = nil
                if let ts = dict["added_at"] as? Timestamp {
                    addedAt = ts.dateValue()
                }
                return BookmarkEntry(id: id, name: name, coverId: coverId, addedAt: addedAt)
            }
            let needsName = entries
                .filter { entry in
                    let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty || trimmed.hasPrefix("Game #") || trimmed == "Unknown Game"
                }
                .map { $0.id }
            if !needsName.isEmpty {
                let fetched = await GameNameCache.shared.fillAndGet(namesFor: Array(Set(needsName)))
                entries = entries.map { entry in
                    if let replacement = fetched[entry.id], !replacement.isEmpty {
                        return BookmarkEntry(id: entry.id, name: replacement, coverId: entry.coverId, addedAt: entry.addedAt)
                    }
                    return entry
                }
                // Persist updated names so "Unknown Game" doesn't linger
                var patched = list
                var changed = false
                for i in 0..<patched.count {
                    if let id = patched[i]["id"] as? Int,
                       let replacement = fetched[id],
                       !replacement.isEmpty {
                        patched[i]["name"] = replacement
                        changed = true
                    }
                }
                if changed {
                    try? await db.collection("users").document(uid).setData(["watchlist_games": patched], merge: true)
                }
            }
            await MainActor.run {
                bookmarksList = entries
                watchlistIds = Set(entries.map { $0.id })
            }
        } catch { }
    }

    private func sortedBookmarks() -> [BookmarkEntry] {
        switch bookmarksSort {
        case .recent:
            return bookmarksList.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .az:
            return bookmarksList.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    private func bookmarksOverlayView() -> some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBookmarksOverlay = false
                        pendingSaveGame = nil
                    }
                }

            VStack(spacing: 12) {
                Text("Saved Games")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let pending = pendingSaveGame {
                    let isSaved = watchlistIds.contains(pending.id)
                    HStack(spacing: 10) {
                        if let cover = pending.cover?.imageId {
                            GameCoverImage(id: cover, preset: .custom(width: 40), cornerRadius: 8)
                                .frame(width: 40, height: 56)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ColorTheme.separator.opacity(0.2))
                                .frame(width: 40, height: 56)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pending.name)
                                .foregroundColor(ColorTheme.text)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            if !isSaved {
                                toggleWatchlist(gameId: pending.id, name: pending.name, cover: pending.cover)
                                let entry = BookmarkEntry(
                                    id: pending.id,
                                    name: pending.name,
                                    coverId: pending.cover?.imageId,
                                    addedAt: Date()
                                )
                                bookmarksList.removeAll { $0.id == pending.id }
                                bookmarksList.insert(entry, at: 0)
                                watchlistIds.insert(pending.id)
                            }
                            // Keep the selected game visible at the top after save.
                        } label: {
                            Text(isSaved ? "Saved" : "Save Game")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(isSaved ? ColorTheme.subtext : ColorTheme.accent)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaved)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                }

                HStack {
                    Spacer(minLength: 0)
                    Picker("", selection: $bookmarksSort) {
                        ForEach(BookmarkSort.allCases, id: \.self) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ColorTheme.accent)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)

                let list = sortedBookmarks()
                ScrollView {
                    VStack(spacing: 6) {
                        if list.isEmpty {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(ColorTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                                .frame(height: 44)
                                .overlay(
                                        Text("No saved games yet")
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.subtext)
                                )

                            Button {
                                currentTab = .explore
                                showBookmarksOverlay = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                    Text("Find a game to save")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ColorTheme.accent)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                            ForEach(list, id: \.id) { row in
                                VStack(spacing: 6) {
                                    HStack(spacing: 10) {
                                        if let cover = row.coverId {
                                            GameCoverImage(id: cover, preset: .custom(width: 36), cornerRadius: 6)
                                                .frame(width: 36, height: 48)
                                        } else {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(ColorTheme.separator.opacity(0.2))
                                                .frame(width: 36, height: 48)
                                        }
                                        Text(row.name)
                                            .foregroundColor(ColorTheme.text)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))

                                    Rectangle()
                                        .fill(ColorTheme.separator.opacity(0.35))
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                }
                .frame(height: 280)
            }
            .padding(16)
            .frame(width: 360, height: 520)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(ColorTheme.black.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(ColorTheme.separator.opacity(0.6), lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBookmarksOverlay = false
                    }
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .padding(.horizontal, 20)
        }
    }

    private func presentExpandedFeedPreview(for item: FeedActivityItem) {
        expandedFeedDetailsVisible = true
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            expandedFeedItem = item
        }
    }

    private func dismissExpandedFeedPreview() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            expandedFeedItem = nil
        }
    }

    private func expandedFeedPreviewOverlay(item: FeedActivityItem) -> some View {
        let targetWidth = min(UIScreen.main.bounds.width - 18, 430)
        let targetHeight = min(UIScreen.main.bounds.height - 88, 770)

        return ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    dismissExpandedFeedPreview()
                }

            ZStack(alignment: .topTrailing) {
                expandedFeedPreviewSurface(item: item, width: targetWidth, height: targetHeight)

                Button {
                    dismissExpandedFeedPreview()
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 6)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private func expandedFeedPreviewSurface(item: FeedActivityItem, width: CGFloat, height: CGFloat) -> some View {
        let rating = item.gameLog.rating ?? 0
        let shellShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        let accent = rating > 0 ? ColorTheme.ratingBandColor(for: rating) : ColorTheme.separator
        let shellGradient = LinearGradient(
            colors: [accent.opacity(0.18), ColorTheme.surface.opacity(0.96), ColorTheme.surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return ZStack {
            shellShape
                .fill(ColorTheme.surface)
                .background(shellGradient.clipShape(shellShape))
                .overlay(shellShape.stroke(Color.white.opacity(0.08), lineWidth: 1))
                .overlay(shellShape.stroke(accent.opacity(0.34), lineWidth: 1))
                .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 14)

            GameLogDetailView(
                gameLog: item.gameLog,
                gameName: displayGameName(item),
                authorUsernameOverride: item.username,
                focusCommentOnAppear: false,
                embeddedOverlay: true,
                hostedInOverlay: true,
                compactFeedExpansion: true
            )
            .frame(width: width, height: height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func logGameOverlay(game: Game) -> some View {
        GameLogOverlayHost(editor: game) {
            withAnimation(.easeInOut(duration: 0.2)) {
                logOverlayGame = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea()
    }

    private func logDetailOverlayView(ctx: LogDetailOverlayContext) -> some View {
        GameLogOverlayHost(
            preview: .init(
                gameLog: ctx.gameLog,
                gameName: ctx.gameName,
                authorUsernameOverride: ctx.username,
                focusCommentOnAppear: ctx.focusComment
            )
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                logDetailOverlay = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea()
    }


    private func displayGameName(_ item: FeedActivityItem) -> String {
        let primary = item.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isUsableGameName(primary) { return primary }

        if let stored = item.gameLog.gameName?.trimmingCharacters(in: .whitespacesAndNewlines),
           isUsableGameName(stored) {
            return stored
        }

        if let cached = gameNameCache[item.gameLog.gameId]?.trimmingCharacters(in: .whitespacesAndNewlines),
           isUsableGameName(cached) {
            return cached
        }

        let gid = item.gameLog.gameId
        requestGameNameFillIfNeeded(for: gid)
        return "Game #\(gid)"
    }

    private func requestGameNameFillIfNeeded(for gameId: Int) {
        guard !requestedNameIds.contains(gameId) else { return }
        DispatchQueue.main.async {
            guard !requestedNameIds.contains(gameId) else { return }
            requestedNameIds.insert(gameId)
            Task { await fillGameNameCacheIfNeeded([gameId]) }
        }
    }

    private func isUsableGameName(_ value: String) -> Bool {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard name != "Loading…" && name != "Loading..." && name != "Unknown Game" else { return false }
        guard !name.hasPrefix("Game #") else { return false }
        let numericOnly = name.allSatisfy { $0.isNumber }
        guard !numericOnly else { return false }
        if name.hasPrefix("#") {
            let rest = name.dropFirst()
            if !rest.isEmpty && rest.allSatisfy({ $0.isNumber }) {
                return false
            }
        }
        return true
    }


    private func resolvedFeedGameName(for log: GameLog) -> String {
        if let cached = gameNameCache[log.gameId]?.trimmingCharacters(in: .whitespacesAndNewlines),
           isUsableGameName(cached) {
            return cached
        }
        if let stored = log.gameName?.trimmingCharacters(in: .whitespacesAndNewlines),
           isUsableGameName(stored) {
            return stored
        }
        return "Game #\(log.gameId)"
    }

    private func fetchLikeCount(for logId: String) {
        db.collection("review_likes").whereField("log_id", isEqualTo: logId).getDocuments { snap, _ in
            likeCounts[logId] = snap?.documents.count ?? 0
        }
    }

    private func handleFeedLikeToggle(for log: GameLog) {
        let logId = log.id
        guard !pendingLikeLogIds.contains(logId) else { return }

        let shouldLike = !likedSet.contains(logId)
        pendingLikeLogIds.insert(logId)

        withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
            _ = likePulseIds.insert(logId)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeOut(duration: 0.18)) {
                _ = likePulseIds.remove(logId)
            }
        }

        // Keep the icon snappy, but leave the count to the server refresh so it can't drift.
        if shouldLike {
            likedSet.insert(logId)
        } else {
            likedSet.remove(logId)
        }

        InteractionService.shared.setLike(log: log, shouldLike: shouldLike) { result in
            pendingLikeLogIds.remove(logId)
            switch result {
            case .success(let isNowLiked):
                if isNowLiked {
                    likedSet.insert(logId)
                } else {
                    likedSet.remove(logId)
                }
                fetchLikeCount(for: logId)
            case .failure:
                if shouldLike {
                    likedSet.remove(logId)
                } else {
                    likedSet.insert(logId)
                }
                fetchLikeCount(for: logId)
            }
        }
    }

    private func fetchCommentCount(for logId: String) {
        db.collection("review_comments").whereField("log_id", isEqualTo: logId).getDocuments { snap, _ in
            let docs = snap?.documents ?? []
            commentCounts[logId] = docs.count
            let uid = Auth.auth().currentUser?.uid ?? ""
            if docs.contains(where: { ($0.data()["user_id"] as? String) == uid }) {
                commentedLogIds.insert(logId)
            } else {
                commentedLogIds.remove(logId)
            }
        }
    }

    private func ensureHasLogged(gameId: Int) {
        guard hasLogged[gameId] == nil else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: uid)
            .whereField("game_id", isEqualTo: gameId)
            .limit(to: 1)
            .getDocuments { snap, _ in
                let exists = (snap?.documents.first != nil)
                hasLogged[gameId] = exists
            }
    }

    private func prefetchAverages(for gameIds: [Int]) {
        let ids = Array(Set(gameIds)).filter { avgCache[$0] == nil && !requestedAverageGameIds.contains($0) }
        guard !ids.isEmpty else { return }
        ids.forEach { requestedAverageGameIds.insert($0) }
        for gameId in ids {
            GamerLndScoreService.shared.fetchAverage(gameId: gameId) { avg, count in
                DispatchQueue.main.async {
                    avgCache[gameId] = (avg: avg, count: count)
                }
            }
        }
    }

    private func prefetchHasLogged(for gameIds: [Int]) {
        let uniqueIds = Array(Set(gameIds)).filter { hasLogged[$0] == nil && !requestedHasLoggedGameIds.contains($0) }
        guard !uniqueIds.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        uniqueIds.forEach { requestedHasLoggedGameIds.insert($0) }

        let chunks = stride(from: 0, to: uniqueIds.count, by: 10).map { Array(uniqueIds[$0..<min($0 + 10, uniqueIds.count)]) }
        for chunk in chunks {
            db.collection("game_logs")
                .whereField("user_id", isEqualTo: uid)
                .whereField("game_id", in: chunk)
                .getDocuments { snap, _ in
                    let found = Set((snap?.documents ?? []).compactMap { $0.data()["game_id"] as? Int })
                    DispatchQueue.main.async {
                        for gameId in chunk {
                            hasLogged[gameId] = found.contains(gameId)
                        }
                    }
                }
        }
    }

    private func initialLoad() async {
        followLastDoc = nil; followingLogs = []; followingIds = []; followingLogIds = []; followingChunkLastDocs = [:]
        forYouLastDoc = nil; forYouLogs = []; forYouIds = []
        if selectedFeed == "Following" {
            await loadMore(isFollowing: true)
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if self.forYouLogs.isEmpty {
                    await self.loadMore(isFollowing: false)
                }
            }
        } else {
            await loadMore(isFollowing: false)
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if self.followingLogs.isEmpty {
                    await self.loadMore(isFollowing: true)
                }
            }
        }
        Task { await loadWatchlistIds() }
        if selectedFeedFilter != .logs {
            Task { await loadPublicLists() }
        }
    }

    private func refreshCurrentFeed() async {
        if isRefreshingFeed { return }
        if let last = lastRefreshAt, Date().timeIntervalSince(last) < 1.0 { return }
        lastRefreshAt = Date()
        isRefreshingFeed = true
        defer { isRefreshingFeed = false }
        feedLoadTask?.cancel()
        feedLoadTask = nil
        isLoadingFollowing = false
        isLoadingForYou = false

        if selectedFeed == "Following" {
            followLastDoc = nil; followingLogs = []; followingIds = []; followingLogIds = []; followingChunkLastDocs = [:]
            await loadMore(isFollowing: true)
        } else {
            forYouLastDoc = nil; forYouLogs = []; forYouIds = []
            await loadMore(isFollowing: false)
        }

        if selectedFeedFilter != .logs || publicLists.isEmpty {
            await loadPublicLists()
        }
    }

    private func ensureLoadedSelectedFeed() async {
        if selectedFeed == "Following" {
            if followingLogs.isEmpty || followingIds.isEmpty {
                await loadMore(isFollowing: true)
            }
        } else if forYouLogs.isEmpty {
            await loadMore(isFollowing: false)
        }

        if selectedFeedFilter != .logs && publicLists.isEmpty {
            await loadPublicLists()
        }
    }

    private func runFeedTask(_ block: @escaping () async -> Void) {
        feedLoadTask?.cancel()
        feedLoadTask = Task { await block() }
    }

    private func loadMore(isFollowing: Bool) async {
        if Task.isCancelled { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            return
        }

        if isFollowing {
            if isLoadingFollowing { return }
            isLoadingFollowing = true

            let followingIdsArr: [String]
            if !followingIds.isEmpty {
                followingIdsArr = Array(followingIds)
            } else {
                followingIdsArr = await fetchFollowingIds(for: uid)
            }
            if followingIdsArr.isEmpty {
                self.followingLogs = []
                self.followingIds = []
                self.followingLogIds = []
                self.isLoadingFollowing = false
                return
            }
            self.followingIds = Set(followingIdsArr)

            let sinceDate = Calendar.current.date(byAdding: .day, value: -DAYS_BACK, to: Date()) ?? .distantPast
            let ts = Timestamp(date: sinceDate)

            let pageLimit = followLastDoc == nil ? INITIAL_PAGE_SIZE : PAGE_SIZE
            let chunks = stride(from: 0, to: followingIdsArr.count, by: 10).map {
                Array(followingIdsArr[$0..<min($0 + 10, followingIdsArr.count)])
            }

            do {
                let existingChunkDocs = followingChunkLastDocs
                let chunkResults = try await withThrowingTaskGroup(of: (String, DocumentSnapshot?, [GameLog]).self) { group in
                    for chunk in chunks {
                        let chunkKey = chunk.joined(separator: ",")
                        let chunkLastDoc = existingChunkDocs[chunkKey]
                        group.addTask {
                            var query: Query = db.collection("game_logs")
                                .whereField("user_id", in: chunk)
                                .whereField("play_date", isGreaterThanOrEqualTo: ts)
                                .order(by: "play_date", descending: true)
                                .limit(to: pageLimit)

                            if let last = chunkLastDoc {
                                query = query.start(afterDocument: last)
                            }

                            let snap = try await query.getDocuments()
                            let parsed = snap.documents.compactMap { d in
                                Self.parseGameLog(docIdFallback: d.documentID, data: d.data())
                            }
                            return (chunkKey, snap.documents.last, parsed)
                        }
                    }

                    var collected: [(String, DocumentSnapshot?, [GameLog])] = []
                    for try await result in group {
                        collected.append(result)
                    }
                    return collected
                }

                var updatedChunkLastDocs: [String: DocumentSnapshot] = existingChunkDocs
                var fetchedLogs: [GameLog] = []
                for (chunkKey, lastDoc, parsed) in chunkResults {
                    if let lastDoc {
                        updatedChunkLastDocs[chunkKey] = lastDoc
                    }
                    fetchedLogs.append(contentsOf: parsed)
                }

                self.followingChunkLastDocs = updatedChunkLastDocs
                let logs = fetchedLogs.sorted { $0.playDate.dateValue() > $1.playDate.dateValue() }
                let enriched = await self.enrichLogs(logs)
                let existingIds = self.followingLogIds
                let uniques = enriched.filter { !existingIds.contains($0.id) }

                let gameIds = uniques.map { $0.gameLog.gameId }
                let logIds = uniques.map(\.id)
                let isInitialPage = self.followingLogs.isEmpty
                let priorityGameIds = Array(gameIds.prefix(isInitialPage ? 6 : gameIds.count))
                let priorityLogIds = Array(logIds.prefix(isInitialPage ? 6 : logIds.count))
                let deferredGameIds = Array(gameIds.dropFirst(priorityGameIds.count))
                let deferredLogIds = Array(logIds.dropFirst(priorityLogIds.count))

                self.prefetchAverages(for: priorityGameIds)
                self.prefetchHasLogged(for: priorityGameIds)
                self.preloadLikeCounts(for: priorityLogIds)
                self.preloadCommentState(for: priorityLogIds)
                self.preloadLikeState(for: priorityLogIds)

                if !deferredGameIds.isEmpty || !deferredLogIds.isEmpty {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        self.prefetchAverages(for: deferredGameIds)
                        self.prefetchHasLogged(for: deferredGameIds)
                        self.preloadLikeCounts(for: deferredLogIds)
                        self.preloadCommentState(for: deferredLogIds)
                        self.preloadLikeState(for: deferredLogIds)
                    }
                }
                self.followingLogs.append(contentsOf: uniques)
                for u in uniques { self.followingLogIds.insert(u.id) }
                self.isLoadingFollowing = false
            } catch {
                os_log("following page err: %@", error.localizedDescription)
                self.isLoadingFollowing = false
            }
        } else {
            if isLoadingForYou { return }
            isLoadingForYou = true

            let sinceDate = Calendar.current.date(byAdding: .day, value: -DAYS_BACK, to: Date()) ?? .distantPast
            let ts = Timestamp(date: sinceDate)

            let pageLimit = forYouLastDoc == nil ? INITIAL_PAGE_SIZE : PAGE_SIZE
            var query: Query = db.collection("game_logs")
                .whereField("play_date", isGreaterThanOrEqualTo: ts)
                .order(by: "play_date", descending: true)
                .limit(to: pageLimit)

            if let last = forYouLastDoc { query = query.start(afterDocument: last) }

            do {
                let snap = try await query.getDocuments()
                self.forYouLastDoc = snap.documents.last

                let logs: [GameLog] = snap.documents.compactMap { d in
                    Self.parseGameLog(docIdFallback: d.documentID, data: d.data())
                }
                let enriched = await self.enrichLogs(logs)
                let existingIds = self.forYouIds
                let uniques = enriched.filter { !existingIds.contains($0.id) }

                let gameIds = uniques.map { $0.gameLog.gameId }
                let logIds = uniques.map(\.id)
                let isInitialPage = self.forYouLastDoc == snap.documents.last && self.forYouLogs.isEmpty
                let priorityGameIds = Array(gameIds.prefix(isInitialPage ? 6 : gameIds.count))
                let priorityLogIds = Array(logIds.prefix(isInitialPage ? 6 : logIds.count))
                let deferredGameIds = Array(gameIds.dropFirst(priorityGameIds.count))
                let deferredLogIds = Array(logIds.dropFirst(priorityLogIds.count))

                self.prefetchAverages(for: priorityGameIds)
                self.prefetchHasLogged(for: priorityGameIds)
                self.preloadLikeCounts(for: priorityLogIds)
                self.preloadCommentState(for: priorityLogIds)
                self.preloadLikeState(for: priorityLogIds)

                if !deferredGameIds.isEmpty || !deferredLogIds.isEmpty {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        self.prefetchAverages(for: deferredGameIds)
                        self.prefetchHasLogged(for: deferredGameIds)
                        self.preloadLikeCounts(for: deferredLogIds)
                        self.preloadCommentState(for: deferredLogIds)
                        self.preloadLikeState(for: deferredLogIds)
                    }
                }
                self.forYouLogs.append(contentsOf: uniques)
                for u in uniques { self.forYouIds.insert(u.id) }
                self.isLoadingForYou = false
            } catch {
                os_log("foryou page err: %@", error.localizedDescription)
                self.isLoadingForYou = false
            }
        }
    }

    private func fetchFollowingIds(for uid: String) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            db.collection("follows")
                .whereField("follower_id", isEqualTo: uid)
                .getDocuments { snap, _ in
                    let ids = snap?.documents.compactMap { $0.data()["followed_id"] as? String } ?? []
                    cont.resume(returning: ids)
                }
        }
    }

    private func enrichLogs(_ logs: [GameLog]) async -> [FeedActivityItem] {
        if logs.isEmpty { return [] }
        let userIds = Array(Set(logs.map { $0.userId }))
        let gameIds = Array(Set(logs.map { $0.gameId }))
        await fillUsernameCacheIfNeeded(userIds)
        await fillGameNameCacheIfNeeded(gameIds)
        await fillGameMetaCacheIfNeeded(gameIds)
        return logs.map { log in
            FeedActivityItem(
                id: log.id,
                gameLog: log,
                gameName: resolvedFeedGameName(for: log),
                username: displayNameCache[log.userId] ?? usernameCache[log.userId] ?? "User",
                avatarUrl: avatarCache[log.userId],
                isTrustedGamer: trustedCache[log.userId] ?? false
            )
        }
    }

    private func fillUsernameCacheIfNeeded(_ userIds: [String]) async {
        let missing = userIds.filter {
            usernameCache[$0] == nil || avatarCache[$0] == nil || displayNameCache[$0] == nil || trustedCache[$0] == nil
        }
        if missing.isEmpty { return }
        let chunks = stride(from: 0, to: missing.count, by: 10).map { Array(missing[$0..<min($0+10, missing.count)]) }
        let db = self.db
        await withTaskGroup(of: Void.self) { group in
            for chunk in chunks {
                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        db.collection("users")
                            .whereField("id", in: chunk)
                            .getDocuments { snap, _ in
                                if let docs = snap?.documents {
                                    for d in docs {
                                        let data = d.data()
                                        if let id = data["id"] as? String {
                                            let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                                            self.usernameCache[id] = uname
                                            if let display = data["display_name"] as? String, !display.isEmpty {
                                                self.displayNameCache[id] = display
                                            } else {
                                                self.displayNameCache[id] = uname
                                            }
                                            if let avatar = data["avatar_url"] as? String, !avatar.isEmpty {
                                                self.avatarCache[id] = avatar
                                            }
                                            self.trustedCache[id] = (data["is_trusted_gamer"] as? Bool) ?? false
                                        }
                                    }
                                }
                                cont.resume()
                            }
                    }
                }
            }
            for await _ in group { }
        }
    }

    private func fillGameNameCacheIfNeeded(_ gameIds: [Int]) async {
        let missing = gameIds.filter {
            guard let existing = gameNameCache[$0] else { return true }
            return !isUsableGameName(existing)
        }
        if missing.isEmpty { return }
        let names = await GameNameCache.shared.fillAndGet(namesFor: missing)
        await MainActor.run {
            for (gid, name) in names where isUsableGameName(name) {
                gameNameCache[gid] = name
            }
        }
    }

    private func fillGameMetaCacheIfNeeded(_ gameIds: [Int]) async {
        let missing = gameIds.filter { gamePublisherCache[$0] == nil || gameYearCache[$0] == nil }
        if missing.isEmpty { return }
        let igdb = self.igdb
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            igdb.fetchGamesByIds(ids: missing) { result in
                if case .success(let games) = result {
                    Task { @MainActor in
                        for g in games {
                            let gid = g.id
                            let pub = Self.bestEffortPublisher(from: g)
                            let year = g.computedReleaseYear
                            if let pub = pub, !pub.isEmpty { self.gamePublisherCache[gid] = pub }
                            if let y = year { self.gameYearCache[gid] = y }
                        }
                        cont.resume()
                    }
                } else {
                    cont.resume()
                }
            }
        }
    }

    nonisolated private static func bestEffortPublisher(from game: Game) -> String? {
        if let companies = game.involvedCompanies {
            if let pub = companies.first(where: { $0.publisher == true })?.company?.name, !pub.isEmpty {
                return pub
            }
            if let dev = companies.first(where: { $0.developer == true })?.company?.name, !dev.isEmpty {
                return dev
            }
            if let any = companies.first?.company?.name, !any.isEmpty {
                return any
            }
        }
        return nil
    }

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
        let gameName = (data["game_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var cover: Game.Cover? = nil
        if let coverDict = data["cover"] as? [String: Any],
           let imageId = coverDict["image_id"] as? String {
            cover = Game.Cover(id: coverDict["id"] as? Int, imageId: imageId)
        }
        return GameLog(
            id: (data["id"] as? String) ?? docIdFallback,
            userId: userId, gameId: gameId,
            gameName: gameName?.isEmpty == true ? nil : gameName,
            status: status, playDate: playDate,
            rating: rating, review: review, containsSpoilers: containsSpoilers, isLiked: isLiked, cover: cover
        )
    }
}

extension Notification.Name {
    static let switchToExplore = Notification.Name("gamerlnd.switchToExplore")
    static let emailVerificationNotDetected = Notification.Name("gamerlnd.emailVerificationNotDetected")
    static let profileOverlayVisibilityChanged = Notification.Name("gamerlnd.profileOverlayVisibilityChanged")
    static let openProfileRewardsPage = Notification.Name("gamerlnd.openProfileRewardsPage")
    static let openGlobalGameLogEditorRequested = Notification.Name("gamerlnd.openGlobalGameLogEditorRequested")
    static let openGlobalGameLogPreviewRequested = Notification.Name("gamerlnd.openGlobalGameLogPreviewRequested")
}

// Local model
struct FeedActivityItem: Identifiable, Equatable {
    let id: String
    let gameLog: GameLog
    let gameName: String
    let username: String
    let avatarUrl: String?
    let isTrustedGamer: Bool
}

private struct FeedRowCard: View, Equatable {
    let item: FeedActivityItem
    let displayName: String
    let gameTitle: String
    let isMine: Bool
    let reviewText: String
    let isFlipped: Bool
    let userRating: Double
    let publisher: String?
    let releaseYear: Int?
    let averageRating: Double?
    let averageCount: Int
    let commentCount: Int
    let isCommented: Bool
    let isSaved: Bool
    let likeCount: Int
    let isLiked: Bool
    let isLikePending: Bool
    let isLikePulsing: Bool
    let feedCardTheme: String
    let timestampRelative: String
    let timestampAbsolute: String
    let onOpenLog: () -> Void
    let onOpenSpoilerReview: () -> Void
    let onToggleReview: () -> Void
    let onCloseReview: () -> Void
    let onOpenRatings: (Double) -> Void
    let onOpenAverageFallback: () -> Void
    let onOpenOwnProfile: () -> Void
    let onAddToList: () -> Void
    let onSaveGame: () -> Void
    let onToggleLike: () -> Void

    private let coverWidth: CGFloat = 130
    private let coverHeight: CGFloat = 175

    static func == (lhs: FeedRowCard, rhs: FeedRowCard) -> Bool {
        lhs.item == rhs.item &&
        lhs.displayName == rhs.displayName &&
        lhs.gameTitle == rhs.gameTitle &&
        lhs.isMine == rhs.isMine &&
        lhs.reviewText == rhs.reviewText &&
        lhs.isFlipped == rhs.isFlipped &&
        lhs.userRating == rhs.userRating &&
        lhs.publisher == rhs.publisher &&
        lhs.releaseYear == rhs.releaseYear &&
        lhs.averageRating == rhs.averageRating &&
        lhs.averageCount == rhs.averageCount &&
        lhs.commentCount == rhs.commentCount &&
        lhs.isCommented == rhs.isCommented &&
        lhs.isSaved == rhs.isSaved &&
        lhs.likeCount == rhs.likeCount &&
        lhs.isLiked == rhs.isLiked &&
        lhs.isLikePending == rhs.isLikePending &&
        lhs.isLikePulsing == rhs.isLikePulsing &&
        lhs.feedCardTheme == rhs.feedCardTheme &&
        lhs.timestampRelative == rhs.timestampRelative &&
        lhs.timestampAbsolute == rhs.timestampAbsolute
    }

    private var hasReview: Bool { !reviewText.isEmpty }
    private var cardAccent: Color {
        userRating > 0 ? ColorTheme.ratingBandColor(for: userRating) : ColorTheme.separator
    }

    var body: some View {
        ZStack {
            cardFront
                .blur(radius: isFlipped ? 3 : 0)

            if isFlipped {
                reviewOverlay
                    .transition(.opacity)
            }
        }
    }

    private var cardFront: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                profileHeader
                Spacer()
                gamerLndBadge
            }

            HStack(alignment: .top, spacing: 12) {
                coverView

                VStack(alignment: .leading, spacing: 6) {
                    Text(gameTitle)
                        .font(feedCardTitleFont(for: gameTitle))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(3)
                        .minimumScaleFactor(0.84)
                        .allowsTightening(true)
                        .lineSpacing(1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    HStack(spacing: 6) {
                        if let publisher, !publisher.isEmpty {
                            Text(publisher)
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                                .lineLimit(1)
                        }
                        if let releaseYear {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                            Text(String(releaseYear))
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                        }
                        Spacer(minLength: 0)
                    }

                    Rectangle()
                        .fill(cardAccent.opacity(0.58))
                        .frame(height: 1)

                    HStack(spacing: 8) {
                        reviewButton
                        Spacer(minLength: 0)
                        if userRating > 0 {
                            FeedHeartValueView(
                                text: formatRatingValue(userRating),
                                color: ColorTheme.ratingBandColor(for: userRating),
                                size: 60
                            )
                        } else {
                            FeedHeartValueView(
                                text: "—",
                                color: ColorTheme.subtext,
                                size: 60,
                                empty: true
                            )
                        }
                    }
                    .frame(height: 56, alignment: .center)
                    .padding(.top, 1)

                    Spacer(minLength: 6)

                    HStack(spacing: 12) {
                        Button(action: onOpenLog) {
                            FeedActionIcon(
                                systemName: "bubble.right",
                                count: commentCount,
                                tint: isCommented ? ColorTheme.accent : .white,
                                countHighlighted: isCommented,
                                size: .large
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: onAddToList) {
                            FeedActionIcon(systemName: "text.badge.plus", count: nil, size: .large)
                        }
                        .buttonStyle(.plain)

                        Rectangle()
                            .fill(ColorTheme.separator.opacity(0.45))
                            .frame(width: 1, height: 22)

                        Button(action: onSaveGame) {
                            FeedActionIcon(
                                systemName: isSaved ? "tray.and.arrow.down.fill" : "tray.and.arrow.down",
                                count: nil,
                                tint: isSaved ? ColorTheme.accent : .white,
                                size: .large
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: onToggleLike) {
                            FeedActionIcon(
                                systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                                count: likeCount,
                                tint: isLiked ? ColorTheme.accent : .white,
                                countHighlighted: isLiked,
                                size: .large
                            )
                        }
                        .scaleEffect(isLikePulsing ? 1.14 : 1.0)
                        .buttonStyle(.plain)
                        .disabled(isLikePending)
                        .opacity(isLikePending ? 0.72 : 1)
                        .transaction { t in t.animation = nil }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 40, alignment: .center)
                    .padding(.top, 2)
                    .padding(.bottom, 0)
                }
                .frame(height: coverHeight, alignment: .top)
            }
        }
        .padding(14)
        .background(feedCardBackground(rating: userRating, theme: feedCardTheme))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ColorTheme.separator, lineWidth: 1)
        )
        .shadow(color: Color(red: 0, green: 0, blue: 0).opacity(0.18), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    private var coverView: some View {
        Group {
            if let imgId = item.gameLog.cover?.imageId {
                GameCoverImage(id: imgId, preset: .custom(width: coverWidth), cornerRadius: 12)
                    .frame(width: coverWidth, height: coverHeight)
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(cardAccent.opacity(0.72), lineWidth: 1.2)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(ColorTheme.separator.opacity(0.2))
                    .frame(width: coverWidth, height: coverHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(cardAccent.opacity(0.72), lineWidth: 1.2)
                    )
            }
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        if isMine {
            Button(action: onOpenOwnProfile) {
                profileHeaderIdentity
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: ProfileView(userId: item.gameLog.userId)) {
                profileHeaderIdentity
            }
            .buttonStyle(.plain)
        }
    }

    private var profileHeaderIdentity: some View {
        HStack(spacing: 8) {
            AvatarView(name: displayName, size: 28, avatarURL: item.avatarUrl)
                .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

            HStack(spacing: 3) {
                Text(displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if item.isTrustedGamer {
                    FeedTrustedGamerBadge()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(timestampRelative)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(ColorTheme.subtext)
                    .lineLimit(1)
                Text(timestampAbsolute)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(ColorTheme.subtext.opacity(0.88))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 36, alignment: .leading)
    }

    @ViewBuilder
    private var gamerLndBadge: some View {
        if let averageRating, averageCount > 0 {
            Button {
                onOpenRatings(averageRating)
            } label: {
                AverageHeartBadge(value: averageRating, size: 26)
                    .padding(.trailing, 6)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onOpenAverageFallback) {
                FeedHeartValueView(
                    text: "-",
                    color: ColorTheme.separator,
                    size: 26,
                    empty: true
                )
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var reviewButton: some View {
        if hasReview {
            Button {
                if item.gameLog.containsSpoilers {
                    onOpenSpoilerReview()
                } else {
                    onToggleReview()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                    ZStack {
                        ForEach(0..<4, id: \.self) { i in
                            let offsets: [CGSize] = [
                                CGSize(width: -0.6, height: 0),
                                CGSize(width: 0.6, height: 0),
                                CGSize(width: 0, height: -0.6),
                                CGSize(width: 0, height: 0.6)
                            ]
                            Text("Read Review")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.black.opacity(0.55))
                                .offset(offsets[i])
                        }
                        Text("Read Review")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.99))
                            .shadow(color: .black.opacity(0.35), radius: 0.8, x: 0, y: 0.6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardAccent.opacity(0.62), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            Text("No Review")
                .font(.subheadline.weight(.medium))
                .foregroundColor(ColorTheme.subtext)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardAccent.opacity(0.62), lineWidth: 1))
                .opacity(0.6)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .highPriorityGesture(TapGesture().onEnded({}))
        }
    }

    private var reviewOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    AvatarView(name: displayName, size: 20, avatarURL: item.avatarUrl)
                        .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                    Text("\(displayName)’s review")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                    if item.isTrustedGamer {
                        FeedTrustedGamerBadge()
                    }
                }
                Spacer()
                Button(action: onCloseReview) {
                    OverlayCloseButton()
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            Text(gameTitle)
                .font(.caption2.weight(.semibold))
                .foregroundColor(ColorTheme.subtext)
                .frame(maxWidth: .infinity, alignment: .center)

            ScrollView {
                Text(reviewText)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                NavigationLink(
                    destination: GameDetailView(
                        game: Game(
                            id: item.gameLog.gameId,
                            name: gameTitle,
                            cover: item.gameLog.cover,
                            firstReleaseDate: nil, genres: nil, platforms: nil,
                            rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                        )
                    )
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                        Text("Review this game")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(ColorTheme.black.opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator.opacity(0.6), lineWidth: 1))
        )
    }
}

private struct FeedTrustedGamerBadge: View {
    var body: some View {
        Image("trusted_flag")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .foregroundStyle(ColorTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(4)
            .background(
                Capsule()
                    .fill(ColorTheme.surface)
                    .overlay(Capsule().stroke(ColorTheme.separator, lineWidth: 1))
            )
    }
}

private struct FeedHeartValueView: View {
    let text: String
    let color: Color
    let size: CGFloat
    var empty: Bool = false

    var body: some View {
        ZStack {
            let numericValue = Double(text) ?? 0
            PixelHeartIcon(
                color: color,
                size: size,
                empty: empty,
                perfectScore: ColorTheme.isPerfectScore(numericValue)
            )
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let offsets: [CGSize] = [
                        CGSize(width: -0.9, height: 0),
                        CGSize(width: 0.9, height: 0),
                        CGSize(width: 0, height: -0.9),
                        CGSize(width: 0, height: 0.9)
                    ]
                    Text(text)
                        .font(.system(size: max(8, size * 0.315), weight: .heavy, design: .rounded))
                        .foregroundColor(.black.opacity(0.8))
                        .offset(offsets[i])
                }
                Text(text)
                    .font(.system(size: max(8, size * 0.315), weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(empty ? 0.82 : 0.99))
                    .shadow(color: .black.opacity(0.45), radius: 1.2, x: 0, y: 0.8)
            }
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .padding(.horizontal, max(2, size * 0.12))
            .offset(y: -max(0.6, size * 0.035))
        }
    }
}

private struct FeedActionIcon: View {
    let systemName: String
    let count: Int?
    var tint: Color = .white
    var countHighlighted: Bool = true
    var size: ContentView.ActionIconSize = .regular

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(size.iconFont)
                .foregroundColor(tint)
                .frame(width: size.container, height: size.container)
                .contentShape(Circle())
            if let count {
                Text("\(min(max(count, 0), 99))")
                    .font(size.countFont)
                    .foregroundColor(countHighlighted ? .white : ColorTheme.subtext)
                    .shadow(color: .black.opacity(0.65), radius: 0.8, x: 0, y: 0.6)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(countHighlighted ? ColorTheme.accent : Color.clear)
                            .overlay(
                                Capsule().stroke(
                                    countHighlighted ? ColorTheme.accent : ColorTheme.separator.opacity(0.9),
                                    lineWidth: 1
                                )
                            )
                    )
                    .offset(x: 8, y: -6)
            }
        }
    }
}

private func feedCardTitleFont(for title: String) -> Font {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let count = trimmed.count

    if count <= 18 {
        return .system(size: 20, weight: .semibold, design: .default)
    } else if count <= 36 {
        return .system(size: 17, weight: .semibold, design: .default)
    } else if count <= 64 {
        return .system(size: 14.5, weight: .semibold, design: .default)
    } else {
        return .system(size: 13, weight: .semibold, design: .default)
    }
}

private func feedCardBackground(rating: Double, theme: String) -> some View {
    let pair: (Color, Color)
    let accentStroke: Color
    let perfectScore = ColorTheme.isPerfectScore(rating)
    switch theme {
    case "glass":
        pair = (ColorTheme.separator, ColorTheme.subtext)
        accentStroke = ColorTheme.separator
    default:
        if rating > 0 {
            if perfectScore {
                pair = (ColorTheme.gold, ColorTheme.xpGreen)
                accentStroke = ColorTheme.gold
            } else {
                let c = ColorTheme.ratingBandColor(for: rating)
                pair = (c, c.opacity(0.65))
                accentStroke = c
            }
        } else {
            pair = (ColorTheme.separator, ColorTheme.subtext)
            accentStroke = ColorTheme.separator
        }
    }
    return ZStack {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(ColorTheme.surface)
        if perfectScore {
            LinearGradient(
                colors: ColorTheme.perfectScoreRainbow.map { $0.opacity(0.16) } + [ColorTheme.surface.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            LinearGradient(
                colors: [pair.0.opacity(0.24), pair.1.opacity(0.14), ColorTheme.surface.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: perfectScore
                        ? ColorTheme.perfectScoreRainbow.map { $0.opacity(0.34) }
                        : [Color.white.opacity(0.12), Color.clear, pair.0.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(accentStroke.opacity(0.56), lineWidth: 1)
    }
}

private struct BookmarkEntry: Identifiable {
    let id: Int
    let name: String
    let coverId: String?
    let addedAt: Date?
}

private enum BookmarkSort: String, CaseIterable {
    case recent = "Recent"
    case az = "A–Z"
}

private struct LogDetailOverlayContext: Identifiable {
    let id: String
    let gameLog: GameLog
    let gameName: String
    let username: String
    let focusComment: Bool
}

private struct RatingsOverlayEntry: Identifiable, Equatable {
    let userId: String
    let displayName: String
    let username: String
    let rating: Double
    let isTrusted: Bool
    let isFollowing: Bool
    let review: String?
    let isCurrentUser: Bool

    var id: String { userId }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}


// Feed skeleton (unchanged)
private struct FeedSkeletonList: View {
    private let rows = 5
    private let coverWidth: CGFloat = 130
    private let coverHeight: CGFloat = 175
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { _ in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(ColorTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ColorTheme.separator.opacity(0.25))
                            .frame(width: coverWidth, height: coverHeight)
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.25)).frame(height: 14)
                            RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.2)).frame(height: 12)
                            RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.18)).frame(height: 12)
                            Spacer(minLength: 0)
                            HStack {
                                RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.22)).frame(width: 70, height: 20)
                                RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.22)).frame(width: 70, height: 20)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                }
                .frame(minHeight: coverHeight + 35)
            }
        }
    }
}
