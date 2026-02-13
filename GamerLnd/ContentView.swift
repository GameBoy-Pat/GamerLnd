// ContentView.swift
// Home (feed), Explore, Notifications, Profile.

import SwiftUI
import UIKit
import FirebaseAuth
@preconcurrency import FirebaseFirestore
import os.log

struct ContentView: View {
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
    @State private var showVerificationLoginOverlay: Bool = false
    @State private var verificationOverlayText: String = ""
    @State private var isProcessingVerificationLogin: Bool = false

    // Feeds
    @State private var followingLogs: [FeedActivityItem] = []
    @State private var forYouLogs: [FeedActivityItem] = []
    @State private var followingIds: Set<String> = [] // user ids you follow
    @State private var followingLogIds: Set<String> = [] // log ids for de-dupe
    @State private var forYouIds: Set<String> = []
    @State private var isLoadingFollowing: Bool = false
    @State private var isLoadingForYou: Bool = false
    @State private var selectedFeed: String = "Following"

    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showDrafts: Bool = false
    @State private var addToListGame: Game? = nil
    @State private var revealedReviews: Set<String> = []

    @State private var usernameCache: [String: String] = [:]
    @State private var displayNameCache: [String: String] = [:]
    @State private var avatarCache: [String: String] = [:]
    @State private var gameNameCache: [Int: String] = [:]
    @State private var likedSet: Set<String> = []
    @State private var likeCounts: [String: Int] = [:]
    @State private var commentCounts: [String: Int] = [:]
    @State private var avgCache: [Int: (avg: Double?, count: Int)] = [:]
    @State private var hasLogged: [Int: Bool] = [:]
    @State private var gamePublisherCache: [Int: String] = [:]
    @State private var gameYearCache: [Int: Int] = [:]
    @State private var showRatingsOverlay: Bool = false
    @State private var ratingsOverlayGameId: Int? = nil
    @State private var ratingsOverlayName: String = ""
    @State private var ratingsOverlayCover: Game.Cover? = nil
    @State private var ratingsOverlayAvg: Double? = nil
    @State private var ratingsOverlayList: [(userId: String, displayName: String, rating: Double)] = []
    @State private var ratingsOverlayLoading: Bool = false
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
    @State private var flippedCards: Set<String> = []
    @State private var feedLoadTask: Task<Void, Never>? = nil
    @State private var isRefreshingFeed: Bool = false
    @State private var requestedNameIds: Set<Int> = []
    @State private var lastRefreshAt: Date? = nil
    @State private var showFeedHint: Bool = true

    @State private var followLastDoc: DocumentSnapshot?
    @State private var forYouLastDoc: DocumentSnapshot?

    private let db = Firestore.firestore()
    private let igdb = IGDBService()

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @AppStorage("themeMode") private var themeMode: String = "dark"
    @AppStorage("pendingEmailVerification") private var pendingEmailVerification: Bool = false

    private let PAGE_SIZE = 20
    private let DAYS_BACK: Int = 365

    private let coverWidth: CGFloat = 130
    private let coverHeight: CGFloat = 175
    private let badgeReservedBottomPadding: CGFloat = 36

    private let bottomIconPointSize: CGFloat = 20
    private let headerPickerIconSize: CGFloat = 20

    private var headerTitle: String { selectedFeed == "Following" ? "Your Feed" : "Trending" }

    var body: some View {
        ZStack(alignment: .bottom) {
            if !isLoggedIn {
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
            } else {
                Group {
                    switch currentTab {
                    case .home: homeView
                    case .explore: exploreView
                    case .notifications: notificationsView
                    case .profile: profileView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ColorTheme.background)
                .ignoresSafeArea(.keyboard)
                .blur(radius: (showRatingsOverlay || showBookmarksOverlay || showCreateMenu || logOverlayGame != nil || logDetailOverlay != nil) ? 6 : 0)
            }

            if isLoggedIn {
                bottomSegmentedTabBar
                    .padding(.bottom, 8)
                    .ignoresSafeArea(edges: .bottom)
                    .blur(radius: (showRatingsOverlay || showBookmarksOverlay || showCreateMenu || logOverlayGame != nil || logDetailOverlay != nil) ? 6 : 0)
            }
            if isLoggedIn {
                floatingCreateButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 20)
                    .padding(.bottom, 96)
            }

            if showRatingsOverlay {
                ratingsOverlayView()
                    .transition(.opacity)
            }
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
            }
            if let ctx = logDetailOverlay {
                logDetailOverlayView(ctx: ctx)
                    .transition(.opacity)
            }
            if showVerificationLoginOverlay {
                verificationLoginOverlay
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(preferredScheme)
        .onAppear {
            refreshAuthVerificationState()
            authListener = Auth.auth().addStateDidChangeListener { _, user in
                let wasLoggedIn = isLoggedIn
                if user == nil {
                    isLoggedIn = false
                } else {
                    refreshAuthVerificationState()
                }
                if !isLoggedIn && wasLoggedIn {
                    followingLogs = []; forYouLogs = []
                    followingIds = []; followingLogIds = []; forYouIds = []
                    followLastDoc = nil; forYouLastDoc = nil
                    hasLogged = [:]
                }
            }
            if currentTab == .home { runFeedTask { await initialLoad() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshAuthVerificationState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshAuthVerificationState()
        }
        .onChange(of: currentTab) { _, newValue in
            if newValue == .home {
                runFeedTask { await ensureLoadedSelectedFeed() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gamerLndRatingUpdated)) { note in
            guard let gid = note.userInfo?["game_id"] as? Int else { return }
            GamerLndScoreService.shared.fetchAverage(gameId: gid) { avg, count in
                avgCache[gid] = (avg: avg, count: count)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToExplore)) { _ in
            currentTab = .explore
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .sheet(item: $addToListGame) { game in
            AddToListSheet(ownerId: Auth.auth().currentUser?.uid ?? "", game: game)
                .preferredColorScheme(ColorTheme.preferredScheme)
                .presentationDetents([.fraction(0.85)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(16)
        }
    }

    private var preferredScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var verificationLoginOverlay: some View {
        ZStack {
            Color.black.opacity(0.38)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(ColorTheme.surface)
            )
            .frame(height: 54)
            .onChange(of: currentTab) { _, _ in Haptics.select() }
            .animation(.default, value: currentTab)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(Color.clear)
    }

    // MARK: - Tab Content

    private var homeView: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {

                // HEADER ROW
                HStack {
                    Picker("", selection: Binding(
                        get: { selectedFeed },
                        set: { newVal in selectedFeed = newVal; Haptics.select() }
                    )) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: headerPickerIconSize, weight: .semibold))
                            .tag("Following")
                        Image(systemName: "sparkles")
                            .font(.system(size: headerPickerIconSize, weight: .semibold))
                            .tag("For You")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                    .accessibilityLabel("Feed Picker")

                    Spacer(minLength: 0)

                    Button { showDrafts = true } label: {
                        Image(systemName: "doc.text")
                            .foregroundColor(ColorTheme.accent)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("Drafts")
                }
                .overlay(
                    Text(headerTitle)
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                        .accessibilityAddTraits(.isHeader)
                )
                .padding(.horizontal, 16)
                .padding(.top, 0)
                .padding(.bottom, 6)
                .animation(.none, value: selectedFeed)
                .overlay(alignment: .topTrailing) {
                    if showFeedHint {
                        Text(selectedFeed == "Following" ? "From people you follow" : "Top activity this week")
                            .font(.caption)
                            .foregroundColor(ColorTheme.subtext)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                            .padding(.trailing, 12)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                TabView(selection: $selectedFeed) {
                    feedPage(isFollowing: true)
                        .tag("Following")
                    feedPage(isFollowing: false)
                        .tag("For You")
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .simultaneousGesture(
                    DragGesture().onEnded { value in
                        handleFeedSwipe(value)
                    }
                )
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { AppIconCentered() } }
            .sheet(isPresented: $showDrafts) { DraftsView().preferredColorScheme(ColorTheme.preferredScheme) }
            .background(ColorTheme.background)
            .onAppear {
                if followingLogs.isEmpty && forYouLogs.isEmpty {
                    Task { await initialLoad() }
                }
                showFeedHintTemporarily()
            }
            .onChange(of: selectedFeed) { _, _ in Task { await ensureLoadedSelectedFeed() } }
            .onChange(of: selectedFeed) { _, _ in showFeedHintTemporarily() }
        }
        .navigationViewStyle(.stack)
    }

    private var exploreView: some View {
        NavigationView { ExploreView() }
            .navigationViewStyle(.stack)
            .padding(.bottom, 80)
    }

    private var notificationsView: some View {
        NavigationView { NotificationsView() }
            .navigationViewStyle(.stack)
            .padding(.bottom, 80)
    }

    private var profileView: some View {
        NavigationView { ProfileView(userId: Auth.auth().currentUser?.uid ?? "") }
            .navigationViewStyle(.stack)
            .padding(.bottom, 80)
    }

    // MARK: - Reward HUD

    // MARK: - Feed list / rows (unchanged from your version)

    private func feedBody(isLoading: Bool, logs: [FeedActivityItem], isFollowing: Bool) -> some View {
        Group {
            if isLoading && logs.isEmpty {
                FeedSkeletonList()
            } else if logs.isEmpty {
                Text("No recent activity. (Showing last \(DAYS_BACK) days.)")
                    .foregroundColor(ColorTheme.subtext)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            } else {
                LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                    Section(header: feedHeader(isFollowing: isFollowing)) {
                        ForEach(logs, id: \.id) { item in
                            Button {
                                logDetailOverlay = LogDetailOverlayContext(
                                    id: item.id,
                                    gameLog: item.gameLog,
                                    gameName: displayGameName(item),
                                    username: item.username,
                                    focusComment: false
                                )
                            } label: {
                                feedRow(item: item)
                                    .contentShape(Rectangle())
                                    .onAppear {
                                        if let idx = logs.firstIndex(where: { $0.id == item.id }),
                                           idx >= logs.count - 5 {
                                            Task { await loadMore(isFollowing: isFollowing) }
                                        }
                                        if avgCache[item.gameLog.gameId] == nil {
                                            GamerLndScoreService.shared.fetchAverage(gameId: item.gameLog.gameId) { avg, count in
                                                avgCache[item.gameLog.gameId] = (avg: avg, count: count)
                                            }
                                        }
                                        ensureHasLogged(gameId: item.gameLog.gameId)
                                    }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 0)
                            .padding(.vertical, 0)
                        }

                        if (isFollowing ? isLoadingFollowing : isLoadingForYou) {
                            ProgressView().tint(ColorTheme.accent).padding(.vertical, 8)
                        }
                        
                        if !publicLists.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Public Lists")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(ColorTheme.subtext)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 6)

                                ForEach(publicLists, id: \.id) { list in
                                    NavigationLink(
                                        destination: ListDetailView(list: list, isOwner: list.ownerId == Auth.auth().currentUser?.uid)
                                    ) {
                                        publicListRow(list: list)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .transaction { t in t.animation = nil }
            }
        }
    }

    private func handleFeedSwipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height
        guard abs(horizontal) > abs(vertical) else { return }
        guard abs(horizontal) > 40 else { return }
        if horizontal < 0 {
            if selectedFeed != "For You" {
                selectedFeed = "For You"
                Haptics.select()
            }
        } else {
            if selectedFeed != "Following" {
                selectedFeed = "Following"
                Haptics.select()
            }
        }
    }

    private func feedPage(isFollowing: Bool) -> some View {
        let isLoading = isFollowing ? isLoadingFollowing : isLoadingForYou
        let logs = isFollowing ? followingLogs : forYouLogs

        if isLoading && logs.isEmpty {
            return AnyView(
                FeedSkeletonList()
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 80)
            )
        }

        return AnyView(
            ScrollView {
                feedBody(isLoading: isLoading, logs: logs, isFollowing: isFollowing)
            }
            .refreshable { await refreshCurrentFeed() }
            .padding(.bottom, 80)
            .transaction { t in t.animation = nil }
        )
    }

    private func feedRow(item: FeedActivityItem) -> some View {
        let me = Auth.auth().currentUser?.uid ?? ""
        let isMine = (item.gameLog.userId == me)
        let displayName = isMine ? "You" : item.username
        let gameId = item.gameLog.gameId

        let reviewText = (item.gameLog.review ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasReview = !reviewText.isEmpty
        let isFlipped = flippedCards.contains(item.gameLog.id)
        let userRating = item.gameLog.rating ?? 0
        let reviewAreaHeight: CGFloat = 56
        let publisher = gamePublisherCache[item.gameLog.gameId]
        let releaseYear = gameYearCache[item.gameLog.gameId]
        return ZStack {
            feedCardFront(
                item: item,
                displayName: displayName,
                isMine: isMine,
                userRating: userRating,
                hasReview: hasReview,
                reviewAreaHeight: reviewAreaHeight,
                gameId: gameId,
                publisher: publisher,
                releaseYear: releaseYear
            )
            .blur(radius: isFlipped ? 3 : 0)

            if isFlipped {
                reviewOverlay(item: item, reviewText: reviewText, displayName: displayName)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFlipped)
    }

    private func feedCardFront(
        item: FeedActivityItem,
        displayName: String,
        isMine: Bool,
        userRating: Double,
        hasReview: Bool,
        reviewAreaHeight: CGFloat,
        gameId: Int,
        publisher: String?,
        releaseYear: Int?
    ) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NavigationLink(destination: ProfileView(userId: item.gameLog.userId)) {
                    AvatarView(name: displayName, size: 28, avatarURL: item.avatarUrl)
                        .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                        if !isMine && followingIds.contains(item.gameLog.userId) {
                            Image(systemName: "person.fill.checkmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(ColorTheme.subtext)
                        }
                        if isMine {
                            Circle()
                                .fill(ColorTheme.highlight)
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text(formattedTimestamp(item.gameLog.playDate.dateValue()))
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                }
                if hasLogged[gameId] == true {
                    Button {
                        logOverlayGame = Game(
                            id: gameId,
                            name: displayGameName(item),
                            cover: item.gameLog.cover,
                            firstReleaseDate: nil, genres: nil, platforms: nil,
                            rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal")
                                .foregroundColor(ColorTheme.gold)
                            Text("Logged")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ColorTheme.gold)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                gamerLndBadge(for: item)
            }

            ZStack(alignment: Alignment(horizontal: .trailing, vertical: .center)) {
                HStack(alignment: .top, spacing: 12) {
                    let thumbWidth: CGFloat = coverWidth
                    let thumbHeight: CGFloat = coverHeight
                    ZStack(alignment: .topTrailing) {
                        if let imgId = item.gameLog.cover?.imageId {
                            GameCoverImage(id: imgId, preset: .custom(width: thumbWidth), cornerRadius: 12)
                                .frame(width: thumbWidth, height: thumbHeight)
                                .clipped()
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ColorTheme.separator.opacity(0.2))
                                .frame(width: thumbWidth, height: thumbHeight)
                        }

                        LinearGradient(
                            colors: [Color.black.opacity(0.28), Color.black.opacity(0.0)],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                        .frame(width: 70, height: 70)
                        .mask(
                            Triangle()
                                .frame(width: 70, height: 70)
                        )

                        Button {
                            logOverlayGame = Game(
                                id: gameId,
                                name: displayGameName(item),
                                cover: item.gameLog.cover,
                                firstReleaseDate: nil, genres: nil, platforms: nil,
                                rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                            )
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(ColorTheme.accent))
                                .overlay(Circle().stroke(ColorTheme.separator.opacity(0.6), lineWidth: 1))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayGameName(item))
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.3)
                            .allowsTightening(true)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 2) {
                            if let publisher = publisher, !publisher.isEmpty {
                                Text(publisher)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.subtext)
                            }
                            if let year = releaseYear {
                                Text(String(year))
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.subtext)
                            }
                        }

                        HStack(spacing: 10) {
                            Spacer(minLength: 0)
                            if hasReview {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        _ = flippedCards.insert(item.gameLog.id)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        AvatarView(name: displayName, size: 20, avatarURL: item.avatarUrl)
                                            .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                                        Text("Review")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(ColorTheme.accent)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("No Review")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(ColorTheme.subtext)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                                    .opacity(0.6)
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                                    .highPriorityGesture(TapGesture().onEnded({}))
                            }
                            if userRating > 0 {
                                HStack(spacing: 8) {
                                    Image(systemName: "heart.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(ColorTheme.highlight)
                                    Text(String(format: "%.1f", userRating))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(ColorTheme.highlight)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: reviewAreaHeight, alignment: .top)

                        Rectangle()
                            .fill(ColorTheme.separator.opacity(0.6))
                            .frame(height: 1)

                        Spacer(minLength: 0)

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
                                actionIcon("bubble.right", count: commentCounts[item.gameLog.id], size: .large)
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
                                           tint: isSaved ? ColorTheme.accent : ColorTheme.text,
                                           size: .large)
                            }
                            .buttonStyle(.plain)

                            let isLiked = likedSet.contains(item.gameLog.id)
                            Button {
                                InteractionService.shared.toggleLike(
                                    log: item.gameLog,
                                    currentlyLiked: isLiked
                                ) {
                                    if isLiked {
                                        likedSet.remove(item.gameLog.id)
                                        likeCounts[item.gameLog.id] = max(0, (likeCounts[item.gameLog.id] ?? 1) - 1)
                                    } else {
                                        likedSet.insert(item.gameLog.id)
                                        likeCounts[item.gameLog.id] = (likeCounts[item.gameLog.id] ?? 0) + 1
                                    }
                                }
                            } label: {
                                actionIcon(isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                                           count: likeCounts[item.gameLog.id],
                                           tint: isLiked ? ColorTheme.accent : ColorTheme.text,
                                           size: .large)
                            }
                            .buttonStyle(.plain)
                            .transaction { t in t.animation = nil }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                    }
                    .frame(minHeight: coverHeight, alignment: .top)
                }

            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(ColorTheme.background)
        .overlay(
            Rectangle()
                .fill(ColorTheme.separator.opacity(0.6))
                .frame(height: 1),
            alignment: .bottom
        )
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
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        _ = flippedCards.remove(item.gameLog.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            Text(displayGameName(item))
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
                    HStack(spacing: 8) {
                        Image("icon")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        ZStack {
                            Image(systemName: "heart")
                                .foregroundColor(ColorTheme.highlight)
                            Image(systemName: "heart.fill")
                                .foregroundColor(ColorTheme.subtext)
                        }
                        Text(String(format: "%.1f", avg))
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(ColorTheme.subtext)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.accent, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(
                    destination: GameDetailView(
                        game: Game(
                            id: item.gameLog.gameId,
                            name: item.gameName,
                            cover: item.gameLog.cover,
                            firstReleaseDate: nil, genres: nil, platforms: nil,
                            rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                        )
                    )
                ) {
                    HStack(spacing: 8) {
                        Image("icon")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        Text("Be the first to rate!").font(.caption2.weight(.semibold)).foregroundColor(ColorTheme.accent)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }


    private enum ActionIconSize {
        case regular
        case large

        var paddingH: CGFloat { self == .large ? 14 : 10 }
        var paddingV: CGFloat { self == .large ? 11 : 8 }
        var iconFont: Font { self == .large ? .headline.weight(.semibold) : .footnote.weight(.semibold) }
        var countFont: Font { self == .large ? .caption.weight(.semibold) : .caption2.weight(.semibold) }
    }

    private func actionIcon(_ systemName: String, count: Int?, tint: Color = ColorTheme.subtext, size: ActionIconSize = .regular) -> some View {
        HStack(spacing: 4) {
            if let count = count, count > 0 {
                Text("\(count)")
                    .font(size.countFont)
                    .foregroundColor(tint)
            }
            Image(systemName: systemName)
                .font(size.iconFont)
                .foregroundColor(tint)
        }
        .padding(.horizontal, size.paddingH).padding(.vertical, size.paddingV)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ColorTheme.surface)
        )
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        let relative = rel.localizedString(for: date, relativeTo: Date())
        let abs = DateFormatter()
        abs.dateStyle = .short
        abs.timeStyle = .none
        return "\(relative) • \(abs.string(from: date))"
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
                .frame(width: 52, height: 52)
                .background(Circle().fill(ColorTheme.accent))
                .overlay(Circle().stroke(ColorTheme.separator.opacity(0.6), lineWidth: 1))
                .shadow(color: ColorTheme.black.opacity(0.25), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func createMenuOverlay() -> some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCreateMenu = false
                    }
                }

            VStack(alignment: .leading, spacing: 10) {
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
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(ColorTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
            )
            .padding(.trailing, 20)
            .padding(.bottom, 96)
        }
    }

    private func createMenuAction(label: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: system)
                Text(label)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(ColorTheme.accent)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
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

    private func openRatingsOverlay(for item: FeedActivityItem, avg: Double) {
        ratingsOverlayGameId = item.gameLog.gameId
        ratingsOverlayName = displayGameName(item)
        ratingsOverlayCover = item.gameLog.cover
        ratingsOverlayAvg = avg
        ratingsOverlayList = []
        ratingsOverlayLoading = true
        withAnimation(.easeInOut(duration: 0.2)) {
            showRatingsOverlay = true
        }
        Task { await loadRatingsOverlayData(gameId: item.gameLog.gameId) }
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
            var entries: [(userId: String, rating: Double)] = []
            var myEntry: (userId: String, rating: Double)?
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
                if uid == Auth.auth().currentUser?.uid {
                    myEntry = (userId: uid, rating: val)
                    continue
                }
                if !followingSet.contains(uid) { continue }
                entries.append((userId: uid, rating: val))
            }
            let userIds = Array(Set(entries.map { $0.userId }))
            await fillUsernameCacheIfNeeded(userIds + (myEntry != nil ? [myEntry!.userId] : []))
            let mapped: [(userId: String, displayName: String, rating: Double)] = entries.map {
                ($0.userId, displayNameCache[$0.userId] ?? usernameCache[$0.userId] ?? "User", $0.rating)
            }
            let sorted = mapped.sorted { $0.rating < $1.rating }
            await MainActor.run {
                var final = sorted
                if let me = myEntry {
                    let myName = displayNameCache[me.userId] ?? usernameCache[me.userId] ?? "You"
                    final.insert((userId: me.userId, displayName: myName, rating: me.rating), at: 0)
                }
                ratingsOverlayList = final
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
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRatingsOverlay = false
                    }
                }

            VStack(spacing: 12) {
                Text("Ratings")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer().frame(height: 12)
                if let cover = ratingsOverlayCover?.imageId {
                    GameCoverImage(id: cover, preset: .custom(width: 120), cornerRadius: 12)
                        .frame(width: 120, height: 160)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(ColorTheme.surface)
                        .frame(width: 120, height: 160)
                }

                Text(ratingsOverlayName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .multilineTextAlignment(.center)

                if let avg = ratingsOverlayAvg {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(ColorTheme.highlight)
                        Text(String(format: "%.1f", avg))
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ColorTheme.highlight)
                    }
                    Text("Ratings from people you follow")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                } else {
                    Text("No ratings yet")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                }

                let listWidth: CGFloat = 320
                let rowHeight: CGFloat = 44
                if ratingsOverlayLoading {
                    ProgressView().tint(ColorTheme.accent)
                        .frame(width: listWidth, height: 280)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            if ratingsOverlayList.isEmpty {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(ColorTheme.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                                    .frame(width: listWidth, height: rowHeight)
                                    .overlay(
                                        Text("No ratings yet")
                                            .font(.caption)
                                            .foregroundColor(ColorTheme.subtext)
                                    )
                            } else {
                                ForEach(Array(ratingsOverlayList.enumerated()), id: \.element.userId) { idx, row in
                                    VStack(spacing: 6) {
                                        HStack {
                                            Text((Auth.auth().currentUser?.uid == row.userId) ? "You" : row.displayName)
                                                .foregroundColor(ColorTheme.text)
                                            Spacer()
                                            HStack(spacing: 6) {
                                                Image(systemName: "heart.fill")
                                                    .foregroundColor(ColorTheme.highlight)
                                                Text(String(format: "%.1f", row.rating))
                                                    .foregroundColor(ColorTheme.highlight)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(width: listWidth, height: rowHeight)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))

                                        if idx == 0 && Auth.auth().currentUser?.uid == row.userId {
                                            Rectangle()
                                                .fill(ColorTheme.separator.opacity(0.6))
                                                .frame(width: listWidth, height: 1)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(width: listWidth, height: 280)
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
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
                        showRatingsOverlay = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .padding(.horizontal, 20)
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
            Color.black.opacity(0.35)
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
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .padding(.horizontal, 20)
        }
    }

    private func logGameOverlay(game: Game) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        logOverlayGame = nil
                    }
                }

            VStack(spacing: 0) {
                ZStack {
                    Text("Log Game")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                }
                .padding(16)
                .background(ColorTheme.black.opacity(0.6))

                ScrollView {
                    GameDetailView(game: game)
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 640, maxHeight: UIScreen.main.bounds.height * 0.76)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(ColorTheme.black.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(ColorTheme.separator.opacity(0.6), lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        logOverlayGame = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .padding(.horizontal, 20)
        }
    }

    private func logDetailOverlayView(ctx: LogDetailOverlayContext) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        logDetailOverlay = nil
                    }
                }

            VStack(spacing: 0) {
                ZStack {
                    Text("Log Detail")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                }
                .padding(16)
                .background(ColorTheme.black.opacity(0.6))

                GameLogDetailView(
                    gameLog: ctx.gameLog,
                    gameName: ctx.gameName,
                    authorUsernameOverride: ctx.username,
                    focusCommentOnAppear: ctx.focusComment
                )
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 640, maxHeight: UIScreen.main.bounds.height * 0.76)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(ColorTheme.black.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(ColorTheme.separator.opacity(0.6), lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        logDetailOverlay = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(ColorTheme.accent)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .padding(.horizontal, 20)
        }
    }


    private func displayGameName(_ item: FeedActivityItem) -> String {
        let name = item.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        let numericOnly = name.allSatisfy { $0.isNumber }
        let hashNumeric: Bool = {
            guard name.hasPrefix("#") else { return false }
            let rest = name.dropFirst()
            return !rest.isEmpty && rest.allSatisfy { $0.isNumber }
        }()

        if name.isEmpty || numericOnly || name.hasPrefix("Game #") || hashNumeric || name == "Unknown Game" {
            if let fallback = gameNameCache[item.gameLog.gameId], !fallback.isEmpty,
               !fallback.hasPrefix("Game #") {
                return fallback
            }
            if let stored = item.gameLog.gameName, !stored.isEmpty { return stored }
            let gid = item.gameLog.gameId
            if !requestedNameIds.contains(gid) {
                requestedNameIds.insert(gid)
                Task { await fillGameNameCacheIfNeeded([gid]) }
            }
            return "Loading…"
        }
        return name
    }


    private func fetchLikeCount(for logId: String) {
        db.collection("review_likes").whereField("log_id", isEqualTo: logId).getDocuments { snap, _ in
            likeCounts[logId] = snap?.documents.count ?? 0
        }
    }

    private func fetchCommentCount(for logId: String) {
        db.collection("review_comments").whereField("log_id", isEqualTo: logId).getDocuments { snap, _ in
            commentCounts[logId] = snap?.documents.count ?? 0
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

    private func initialLoad() async {
        followLastDoc = nil; followingLogs = []; followingIds = []; followingLogIds = []
        forYouLastDoc = nil; forYouLogs = []; forYouIds = []
        await loadMore(isFollowing: true)
        await loadMore(isFollowing: false)
        await loadWatchlistIds()
        await loadPublicLists()
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
            followLastDoc = nil; followingLogs = []; followingIds = []; followingLogIds = []
            await loadMore(isFollowing: true)
        } else {
            forYouLastDoc = nil; forYouLogs = []; forYouIds = []
            await loadMore(isFollowing: false)
        }
        await loadPublicLists()
    }

    private func ensureLoadedSelectedFeed() async {
        if selectedFeed == "Following" {
            if followingLogs.isEmpty { await loadMore(isFollowing: true) }
        } else {
            if forYouLogs.isEmpty { await loadMore(isFollowing: false) }
        }
    }

    private func runFeedTask(_ block: @escaping () async -> Void) {
        feedLoadTask?.cancel()
        feedLoadTask = Task { await block() }
    }

    private func loadMore(isFollowing: Bool) async {
        if Task.isCancelled { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            alertMessage = "Please sign in to view your feeds."
            showAlert = true; return
        }

        if isFollowing {
            if isLoadingFollowing { return }
            isLoadingFollowing = true

            let followingIdsArr = await fetchFollowingIds(for: uid)
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

            var query: Query = db.collection("game_logs")
                .whereField("user_id", in: Array(followingIdsArr.prefix(10)))
                .whereField("play_date", isGreaterThanOrEqualTo: ts)
                .order(by: "play_date", descending: true)
                .limit(to: PAGE_SIZE)

            if let last = followLastDoc { query = query.start(afterDocument: last) }

            Task {
                do {
                    let snap = try await query.getDocuments()
                    self.followLastDoc = snap.documents.last

                    let logs: [GameLog] = snap.documents.compactMap { d in
                        Self.parseGameLog(docIdFallback: d.documentID, data: d.data())
                    }
                    let enriched = await self.enrichLogs(logs)
                    let existingIds = await MainActor.run { self.followingLogIds }
                    let uniques = enriched.filter { !existingIds.contains($0.id) }
                    await MainActor.run {
                        self.followingLogs.append(contentsOf: uniques)
                        for u in uniques { self.followingLogIds.insert(u.id) }
                        self.isLoadingFollowing = false
                    }
                } catch {
                    os_log("following page err: %@", error.localizedDescription)
                    self.isLoadingFollowing = false
                }
            }
        } else {
            if isLoadingForYou { return }
            isLoadingForYou = true

            let sinceDate = Calendar.current.date(byAdding: .day, value: -DAYS_BACK, to: Date()) ?? .distantPast
            let ts = Timestamp(date: sinceDate)

            var query: Query = db.collection("game_logs")
                .whereField("play_date", isGreaterThanOrEqualTo: ts)
                .order(by: "play_date", descending: true)
                .limit(to: PAGE_SIZE)

            if let last = forYouLastDoc { query = query.start(afterDocument: last) }

            Task {
                do {
                    let snap = try await query.getDocuments()
                    self.forYouLastDoc = snap.documents.last

                    let logs: [GameLog] = snap.documents.compactMap { d in
                        Self.parseGameLog(docIdFallback: d.documentID, data: d.data())
                    }
                    let enriched = await self.enrichLogs(logs)
                    let existingIds = await MainActor.run { self.forYouIds }
                    let uniques = enriched.filter { !existingIds.contains($0.id) }
                    await MainActor.run {
                        self.forYouLogs.append(contentsOf: uniques)
                        for u in uniques { self.forYouIds.insert(u.id) }
                        self.isLoadingForYou = false
                    }
                } catch {
                    os_log("foryou page err: %@", error.localizedDescription)
                    self.isLoadingForYou = false
                }
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
                gameName: (gameNameCache[log.gameId] ?? log.gameName) ?? "Loading…",
                username: displayNameCache[log.userId] ?? usernameCache[log.userId] ?? "User",
                avatarUrl: avatarCache[log.userId]
            )
        }
    }

    private func fillUsernameCacheIfNeeded(_ userIds: [String]) async {
        let missing = userIds.filter {
            usernameCache[$0] == nil || avatarCache[$0] == nil || displayNameCache[$0] == nil
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
        let missing = gameIds.filter { gameNameCache[$0] == nil }
        if missing.isEmpty { return }
        let names = await GameNameCache.shared.fillAndGet(namesFor: missing)
        await MainActor.run { for (gid, name) in names { gameNameCache[gid] = name } }
    }

    private func fillGameMetaCacheIfNeeded(_ gameIds: [Int]) async {
        let missing = gameIds.filter { gamePublisherCache[$0] == nil || gameYearCache[$0] == nil }
        if missing.isEmpty { return }
        let igdb = self.igdb
        await withTaskGroup(of: Void.self) { group in
            for gid in missing {
                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        let lock = NSLock()
                        var didResume = false
                        igdb.fetchGameById(id: gid) { result in
                            lock.lock()
                            if didResume {
                                lock.unlock()
                                return
                            }
                            didResume = true
                            lock.unlock()

                            if case .success(let g) = result {
                                let pub = Self.bestEffortPublisher(from: g)
                                let year = g.computedReleaseYear
                                Task { @MainActor in
                                    if let pub = pub, !pub.isEmpty { self.gamePublisherCache[gid] = pub }
                                    if let y = year { self.gameYearCache[gid] = y }
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

    nonisolated private static func bestEffortPublisher(from game: Game) -> String? {
        let m = Mirror(reflecting: game)
        for child in m.children {
            guard child.label == "involvedCompanies" else { continue }
            if let array = child.value as? [Any] {
                for entry in array {
                    var isPublisher = false
                    var companyName: String?
                    let em = Mirror(reflecting: entry)
                    for c in em.children {
                        if c.label == "publisher", let b = c.value as? Bool { isPublisher = b }
                        if c.label == "company" {
                            let cm = Mirror(reflecting: c.value)
                            for cc in cm.children {
                                if cc.label == "name", let n = cc.value as? String {
                                    companyName = n
                                }
                            }
                        }
                    }
                    if isPublisher, let name = companyName, !name.isEmpty {
                        return name
                    }
                }
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
            rating: rating, review: review, isLiked: isLiked, cover: cover
        )
    }
}

extension Notification.Name {
    static let switchToExplore = Notification.Name("gamerlnd.switchToExplore")
    static let emailVerificationNotDetected = Notification.Name("gamerlnd.emailVerificationNotDetected")
}

// Local model
struct FeedActivityItem: Identifiable {
    let id: String
    let gameLog: GameLog
    let gameName: String
    let username: String
    let avatarUrl: String?
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
