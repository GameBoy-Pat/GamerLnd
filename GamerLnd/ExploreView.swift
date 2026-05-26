// ExploreView.swift
// Combined Game & User search with filters/sorts, skeleton loaders, last searches,
// debounced live search, pull-to-refresh, standardized toasts, and gentle haptics.
//
// Updates:
// • Title "Explore" and the Games/Users segmented picker are now on the SAME top row.
//   The title stays perfectly centered using an overlay, while the picker sits at top-left.
// • Search bar + Filters button remain together on the next row underneath.
// • Removed the Games/Users mode choice from the Filters menu (now only in the top-left picker).

import SwiftUI
import UIKit
@preconcurrency import FirebaseFirestore
import FirebaseAuth

struct ExploreView: View {
    // MARK: - Mode
    enum Mode: String, CaseIterable, Identifiable { case games = "Games", users = "Users"; var id: String { rawValue } }
    private enum TrustedGamerOverlayMode { case info, apply }
    private struct CreatorSpotlight: Identifiable, Hashable {
        let id: String
        let user: GamerLnd.UserLite
        let youtubeURL: String?
        let twitchURL: String?
        let tiktokURL: String?
    }
    private struct CreatorLinks: Hashable {
        let youtubeURL: String?
        let twitchURL: String?
        let tiktokURL: String?

        var hasAny: Bool {
            [youtubeURL, twitchURL, tiktokURL].contains { url in
                guard let url else { return false }
                return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
    private enum CreatorPlatform: String, Hashable {
        case youtube
        case tiktok
        case twitch
    }
    private struct CreatorLinkButtonData: Identifiable, Hashable {
        let platform: CreatorPlatform
        let url: String

        var id: String { "\(platform.rawValue)-\(url)" }
    }
    private struct SearchReportDraft: Identifiable {
        let id = UUID()
        let context: SearchResultReportContext
    }

    // MARK: - UI
    @State private var mode: Mode = .games
    @State private var query: String = ""
    @State private var toast: Toast? = nil
    @State private var selectedGameOverlay: Game? = nil
    @State private var selectedRecentLogOverlay: GameLog? = nil
    @State private var suppressNextRecentLogSelection: Bool = false

    // MARK: - Games state
    @State private var gameResults: [Game] = []
    @State private var gameLoading: Bool = false
    @State private var gameError: String = ""
    @State private var gamerLndAvg: [Int: Double] = [:]
    @State private var gamerLndCount: [Int: Int] = [:]
    @State private var reviewCountCache: [Int: Int] = [:]
    @State private var appActivityByGame: [Int: Double] = [:]
    @State private var nextGameOffset: Int = 0
    @State private var canLoadMoreGames: Bool = false
    @State private var visibleGameCount: Int = 20

    // Filters / Sort (Games)
    enum GameSort: String, CaseIterable, Identifiable {
        case relevance = "Relevance"              // IGDB default order
        case popularity = "Popularity"            // local: rating_count/total_rating_count desc
        case glRating = "GamerLnd Rating"         // local: avg desc
        case newest = "Release (Newest)"          // local: year desc
        case alpha = "Alphabetical"
        var id: String { rawValue }
    }
    @State private var selectedGameSort: GameSort = .relevance
    @State private var selectedYear: Int? = nil
    @State private var selectedGenre: String? = nil
    @State private var selectedPlatform: String? = nil

    // MARK: - Users state
    @State private var userResults: [GamerLnd.UserLite] = []
    @State private var userLoading: Bool = false
    @State private var userError: String = ""
    @State private var followersCount: [String: Int] = [:]
    @State private var logsCount: [String: Int] = [:]
    @State private var reviewsCount: [String: Int] = [:]
    @State private var lastActivity: [String: Date] = [:]
    @State private var followingState: [String: Bool] = [:]
    @State private var lastUserDoc: DocumentSnapshot?
    @State private var canLoadMoreUsers: Bool = false
    @State private var savedGameIds: Set<Int> = []
    @State private var pendingSaveGame: Game? = nil
    @State private var showSaveOverlay: Bool = false
    @State private var savedGamesList: [SavedGameEntry] = []
    @State private var savedGamesSort: SavedGamesSort = .recent
    @State private var trendingGames: [TrendingGameCard] = []
    @State private var recentSelfLogs: [GameLog] = []
    @State private var trustedUsersRow: [GamerLnd.UserLite] = []
    @State private var creatorSpotlights: [CreatorSpotlight] = []
    @State private var creatorLinksByUserId: [String: CreatorLinks] = [:]
    @State private var visitedUserHistory: [GamerLnd.UserLite] = []
    @State private var isLoadingDiscoverRows: Bool = false
    @State private var showingGameSubmissionSheet: Bool = false
    @State private var showingFeedbackSheet: Bool = false
    @State private var showTrustedGamerOverlay: Bool = false
    @State private var trustedGamerOverlayMode: TrustedGamerOverlayMode = .info
    @State private var trustedGamerApplicationWhy: String = ""
    @State private var trustedGamerApplicationLinks: String = ""
    @State private var trustedGamerApplicationNotes: String = ""
    @State private var userAverageRatings: [String: Double] = [:]
    @State private var activeSearchReport: SearchReportDraft? = nil
    @State private var selectedSearchReportReason: SearchReportReason = .notRelevant
    @State private var searchReportNotes: String = ""
    @State private var isSubmittingSearchReport: Bool = false
    @FocusState private var searchReportNotesFocused: Bool
    @FocusState private var searchFieldFocused: Bool
    @State private var searchReportKeyboardHeight: CGFloat = 0

    // Filters / Sort (Users)
    enum UserSort: String, CaseIterable, Identifiable {
        case relevance = "Relevance"      // preserve Firestore prefix order
        case followers = "Followers"
        case recent = "Recent Activity"
        case alpha = "Alphabetical"
        var id: String { rawValue }
    }
    @State private var selectedUserSort: UserSort = .relevance
    @State private var filterHasReviews: Bool = false
    @State private var filterHasAvatar: Bool = false
    @State private var filterTrustedGamer: Bool = false

    private enum SavedGamesSort: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case az = "A–Z"
        var id: String { rawValue }
    }

    private struct SavedGameEntry: Identifiable {
        let id: Int
        let name: String
        let coverId: String?
        let addedAt: Date?
    }

    // MARK: - Shared
    @State private var debounceTask: DispatchWorkItem?
    private let igdb = IGDBService()
    private let db = Firestore.firestore()
    private let pageSize = 20
    private let gameFetchSize = 60

    // Last searches (scoped per signed-in user)
    @State private var lastSearches: [String] = []
    private var currentExploreStorageUserId: String? {
        Auth.auth().currentUser?.uid
    }
    private var lastSearchesKey: String? {
        guard let uid = currentExploreStorageUserId else { return nil }
        return "explore.lastSearches.\(uid)"
    }
    private var visitedUsersKey: String? {
        guard let uid = currentExploreStorageUserId else { return nil }
        return "explore.visitedUsers.\(uid)"
    }

    var body: some View {
        exploreBody
    }

    private var exploreBody: AnyView {
        AnyView(exploreInteractiveView)
    }

    private var exploreBaseView: AnyView {
        AnyView(
            ZStack {
                exploreRootContent
                exploreOverlayLayer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ColorTheme.background.ignoresSafeArea())
        )
    }

    private var exploreSheetView: AnyView {
        AnyView(
            exploreBaseView
                .sheet(isPresented: $showingGameSubmissionSheet) {
                    GameSubmissionSheet { payload in
                        submitGameSuggestion(payload: payload)
                    }
                    .preferredColorScheme(ColorTheme.preferredScheme)
                }
                .sheet(isPresented: $showingFeedbackSheet) {
                    FeedbackSubmissionSheet { payload in
                        submitFeedback(payload: payload)
                    }
                    .preferredColorScheme(ColorTheme.preferredScheme)
                }
        )
    }

    private var exploreInteractiveView: AnyView {
        let navigationWrapped = AnyView(
            exploreSheetView
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .principal) { EmptyView() }
                }
                .toast($toast)
                .onAppear(perform: handleAppear)
        )

        let searchWrapped = AnyView(
            navigationWrapped
                .onChange(of: mode) { _, _ in
                    Haptics.select()
                    if !query.isEmpty { performSearch(reset: true, userInitiated: false) }
                }
                .onChange(of: query) { _, newValue in
                    debounceTask?.cancel()
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        clearSearch()
                        return
                    }
                    let task = DispatchWorkItem { performSearch(reset: true, userInitiated: false) }
                    debounceTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
                }
        )

        let filtersWrapped = AnyView(
            searchWrapped
                .onChange(of: selectedGameSort) { _, _ in applyGameSortAndFilters() }
                .onChange(of: selectedYear) { _, _ in applyGameSortAndFilters() }
                .onChange(of: selectedGenre) { _, _ in applyGameSortAndFilters() }
                .onChange(of: selectedPlatform) { _, _ in applyGameSortAndFilters() }
                .onChange(of: selectedUserSort) { _, _ in applyUserFiltersAndSort() }
                .onChange(of: filterHasReviews) { _, _ in applyUserFiltersAndSort() }
                .onChange(of: filterHasAvatar) { _, _ in applyUserFiltersAndSort() }
                .onChange(of: filterTrustedGamer) { _, _ in applyUserFiltersAndSort() }
        )

        let overlayWrapped = AnyView(
            filtersWrapped
                .onChange(of: selectedGameOverlay) { _, newValue in
                    postNestedOverlayVisibility(newValue != nil)
                }
                .onChange(of: selectedRecentLogOverlay) { _, newValue in
                    postNestedOverlayVisibility(newValue != nil)
                }
                .onChange(of: hasPresentedOverlay) { _, visible in
                    postNestedOverlayVisibility(visible)
                }
        )

        return AnyView(
            overlayWrapped
                .onReceive(NotificationCenter.default.publisher(for: .gamerLndRatingUpdated)) { note in
                    guard let gid = note.userInfo?["game_id"] as? Int else { return }
                    GamerLndScoreService.shared.fetchAverage(gameId: gid) { avg, count in
                        DispatchQueue.main.async {
                            self.gamerLndAvg[gid] = avg
                            self.gamerLndCount[gid] = count
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    guard activeSearchReport != nil,
                          let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
                    let screenHeight = UIScreen.main.bounds.height
                    searchReportKeyboardHeight = max(0, screenHeight - frame.origin.y)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    searchReportKeyboardHeight = 0
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        KeyboardDismissAccessoryButton {
                            searchFieldFocused = false
                            searchReportNotesFocused = false
                            dismissKeyboard()
                        }
                    }
                }
                .ignoresSafeArea(.keyboard, edges: .all)
        )
    }

    private var exploreRootContent: some View {
        VStack(spacing: 0) {
            exploreHeader
            filtersRow
            if showRecentSearches {
                recentSearchesSection
            }
            mainExploreContent
        }
    }

    private func postRatingsOverlayRequest(game: Game, avg: Double) {
        postRatingsOverlayRequest(gameId: game.id, gameName: game.name, coverImageId: game.cover?.imageId, avg: avg)
    }

    private func postRatingsOverlayRequest(gameId: Int, gameName: String, coverImageId: String?, avg: Double) {
        NotificationCenter.default.post(
            name: .openRatingsOverlayRequested,
            object: nil,
            userInfo: [
                "game_id": gameId,
                "game_name": gameName,
                "avg": avg,
                "cover_image_id": coverImageId as Any
            ]
        )
    }

    @ViewBuilder
    private var exploreOverlayLayer: some View {
        if showSaveOverlay {
            saveConfirmOverlay
        }
        if showTrustedGamerOverlay {
            trustedGamerOverlay
        }
        if let draft = activeSearchReport {
            searchReportOverlay(draft: draft)
        }
        if let game = selectedGameOverlay {
            gameDetailOverlay(game: game)
        }
        if let log = selectedRecentLogOverlay {
            recentLogOverlay(log: log)
        }
    }

    private var hasPresentedOverlay: Bool {
        selectedGameOverlay != nil
            || selectedRecentLogOverlay != nil
            || showSaveOverlay
            || showTrustedGamerOverlay
            || activeSearchReport != nil
            || showingGameSubmissionSheet
            || showingFeedbackSheet
    }

    private var exploreHeader: some View {
        VStack(spacing: 0) {
            AppIconCentered()
                .padding(.top, 8)
                .padding(.bottom, 4)
            HStack {
                Picker("", selection: $mode) {
                    Image(systemName: "gamecontroller.fill").tag(Mode.games)
                    Image(systemName: "person.2.fill").tag(Mode.users)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .tint(ColorTheme.accent)
                .frame(width: 112, height: 32)
                .accessibilityLabel("Explore Picker")
                Spacer(minLength: 0)
            }
            .overlay(
                Text("Explore")
                    .font(.headline.weight(.bold))
                    .foregroundColor(ColorTheme.text)
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    private var filtersRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    TextField("Search \(mode.rawValue.lowercased())…", text: $query, onCommit: { performSearch(reset: true, userInitiated: true) })
                        .textInputAutocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.webSearch)
                        .submitLabel(.search)
                        .focused($searchFieldFocused)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .foregroundColor(ColorTheme.text)
                        .overlay(alignment: .trailing) {
                            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    clearSearch()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(ColorTheme.subtext)
                                        .font(.system(size: 16, weight: .semibold))
                                        .padding(.trailing, 8)
                                }
                                .accessibilityLabel("Clear search")
                            }
                        }
                }
                Button {
                    Haptics.tap()
                    performSearch(reset: true, userInitiated: true)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(ColorTheme.accent))
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gameLoading || userLoading)
                filtersButton
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var filtersButton: some View {
        Menu {
            if mode == .games {
                Section("Sort") {
                    Picker("Sort games", selection: $selectedGameSort) {
                        ForEach(GameSort.allCases) { s in Text(s.rawValue).tag(s) }
                    }
                }
                Section("Filters") {
                    Picker("Year", selection: Binding(
                        get: { selectedYear ?? -1 },
                        set: { selectedYear = ($0 == -1 ? nil : $0) }
                    )) {
                        Text("Any year").tag(-1)
                        ForEach((1980...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    TextField("Genre (e.g. RPG)", text: Binding(
                        get: { selectedGenre ?? "" },
                        set: { selectedGenre = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Platform (e.g. Switch)", text: Binding(
                        get: { selectedPlatform ?? "" },
                        set: { selectedPlatform = $0.isEmpty ? nil : $0 }
                    ))
                    Button("Reset filters") {
                        selectedYear = nil; selectedGenre = nil; selectedPlatform = nil
                        selectedGameSort = .relevance
                        applyGameSortAndFilters()
                    }
                }
            } else {
                Section("Sort") {
                    Picker("Sort users", selection: $selectedUserSort) {
                        ForEach(UserSort.allCases) { s in Text(s.rawValue).tag(s) }
                    }
                }
                Section("Filters") {
                    Toggle("Has Reviews", isOn: $filterHasReviews)
                    Toggle("Has Avatar", isOn: $filterHasAvatar)
                    Toggle("Trusted Gamers", isOn: $filterTrustedGamer)
                    Button("Reset filters") {
                        filterHasReviews = false
                        filterHasAvatar = false
                        filterTrustedGamer = false
                        applyUserFiltersAndSort()
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text("Filters")
            }
            .foregroundColor(ColorTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
        }
    }

    private var showRecentSearches: Bool {
        mode == .games && !lastSearches.isEmpty && query.isEmpty
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent searches")
                .font(.caption)
                .foregroundColor(ColorTheme.subtext)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    lastSearches = []
                    if let key = lastSearchesKey {
                        UserDefaults.standard.set([], forKey: key)
                    }
                    Haptics.select()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Clear recent")
                    }
                    .font(.caption)
                    .foregroundColor(ColorTheme.highlight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .fixedSize()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(lastSearches, id: \.self) { s in
                            Button {
                                query = s
                                performSearch(reset: true, userInitiated: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                    Text(s)
                                }
                                .font(.caption)
                                .foregroundColor(ColorTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 16)
                }
            }
            .padding(.leading, 16)
            .padding(.bottom, 6)
        }
    }

    private var mainExploreContent: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    discoverRowsSection
                        .padding(.top, 4)
                        .padding(.bottom, 92)
                }
                .scrollDismissesKeyboard(.immediately)
            } else {
                ZStack {
                    if mode == .games { gamesList } else { usersList }
                }
            }
        }
    }

    private func handleAppear() {
        AnalyticsService.shared.screen("Explore")
        UserDefaults.standard.removeObject(forKey: "explore.lastSearches")
        guard let key = lastSearchesKey else {
            lastSearches = []
            return
        }
        lastSearches = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        loadSavedGames()
        loadDiscoverRows()
        loadVisitedUserHistory()
    }

    private func postNestedOverlayVisibility(_ visible: Bool) {
        NotificationCenter.default.post(
            name: .nestedOverlayVisibilityChanged,
            object: nil,
            userInfo: ["visible": visible]
        )
    }

    // MARK: - UI Pieces

    private var discoverRowsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .games {
                gameDiscoverSection
            } else {
                userDiscoverSection
            }
        }
    }

    private var gameDiscoverSection: some View {
        Group {
            HStack {
                Text("Trending Games")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                if isLoadingDiscoverRows {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 16)

            if trendingGames.isEmpty {
                Text("No recent game activity yet.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(trendingGames) { trend in
                            Button {
                                dismissKeyboard()
                                selectedGameOverlay = trend.game
                            } label: {
                                trendingGameCard(trend)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
            }

            HStack {
                Text("Recently Logged (You)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
            }
            .padding(.horizontal, 16)

            if recentSelfLogs.isEmpty {
                Text("You haven’t logged any games yet.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentSelfLogs, id: \.id) { log in
                            let title = (log.gameName?.isEmpty == false ? log.gameName! : "Game #\(log.gameId)")
                            ExploreRecentLogRowCard(
                                log: log,
                                title: title,
                                avg: gamerLndAvg[log.gameId],
                                count: gamerLndCount[log.gameId] ?? 0,
                                onAverageTap: {
                                    suppressNextRecentLogSelection = true
                                    if let avg = gamerLndAvg[log.gameId], (gamerLndCount[log.gameId] ?? 0) > 0 {
                                        postRatingsOverlayRequest(gameId: log.gameId, gameName: title, coverImageId: log.cover?.imageId, avg: avg)
                                    }
                                }
                            )
                            .onTapGesture {
                                dismissKeyboard()
                                if suppressNextRecentLogSelection {
                                    suppressNextRecentLogSelection = false
                                    return
                                }
                                selectedRecentLogOverlay = log
                            }
                            .onAppear {
                                if gamerLndCount[log.gameId] == nil {
                                    GamerLndScoreService.shared.fetchAverage(gameId: log.gameId) { avg, count in
                                        DispatchQueue.main.async {
                                            gamerLndAvg[log.gameId] = avg
                                            gamerLndCount[log.gameId] = count
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
            }

            discoverActionButtons(isGamesMode: true)
        }
    }

    private var userDiscoverSection: some View {
        Group {
            HStack(spacing: 6) {
                Text("Trusted Gamers")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Image("trusted_flag")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(ColorTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                Spacer()
                Button {
                    trustedGamerOverlayMode = .info
                    showTrustedGamerOverlay = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if trustedUsersRow.isEmpty {
                Text("No trusted gamers yet.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(trustedUsersRow, id: \.id) { user in
                            NavigationLink(destination: ProfileView(userId: user.id)) {
                                featuredUserCard(user, showTrustedBadge: false)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                recordVisitedUser(user)
                            })
                            .onAppear {
                                hydrateUserCardStats(for: user.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
            }

            HStack {
                Text("Content Creators")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
            }
            .padding(.horizontal, 16)

            if creatorSpotlights.isEmpty {
                Text("Creators with linked channels will appear here.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(creatorSpotlights) { creator in
                            NavigationLink(destination: ProfileView(userId: creator.user.id)) {
                                creatorSpotlightCard(creator)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                recordVisitedUser(creator.user)
                            })
                                .onAppear {
                                    hydrateUserCardStats(for: creator.user.id)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
            }

            HStack {
                Text("Search History")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
            }
            .padding(.horizontal, 16)

            if visitedUserHistory.isEmpty {
                Text("Profiles you open from search will appear here.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(visitedUserHistory, id: \.id) { user in
                            NavigationLink(destination: ProfileView(userId: user.id)) {
                                featuredUserCard(user, showTrustedBadge: user.isTrustedGamer)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                recordVisitedUser(user)
                            })
                            .onAppear {
                                hydrateUserCardStats(for: user.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
            }

            discoverActionButtons(isGamesMode: false)
        }
    }

    private func discoverActionButtons(isGamesMode: Bool) -> some View {
        HStack(spacing: 10) {
            if isGamesMode {
                Button {
                    showingGameSubmissionSheet = true
                } label: {
                    discoverButtonLabel("Can't find a game?", tint: ColorTheme.accent)
                }
                .buttonStyle(.plain)
            }

            Button {
                showingFeedbackSheet = true
            } label: {
                discoverButtonLabel("Send feedback", tint: ColorTheme.subtext)
            }
            .buttonStyle(.plain)

            if !isGamesMode {
                Button {
                    trustedGamerOverlayMode = .info
                    showTrustedGamerOverlay = true
                } label: {
                    discoverButtonLabel("What is a Trusted Gamer", tint: ColorTheme.gold)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func discoverButtonLabel(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private func trendingGameCard(_ trend: TrendingGameCard) -> some View {
        let publisher = trendingPublisher(for: trend.game)
        return VStack(alignment: .leading, spacing: 8) {
            if let img = trend.game.cover?.imageId ?? trend.game.screenshots?.first?.imageId {
                GameCoverImage(id: img, preset: .custom(width: 100), cornerRadius: 10)
                    .frame(width: 100, height: 132)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(ColorTheme.separator.opacity(0.2))
                    .frame(width: 100, height: 132)
            }

            Text(trend.game.name)
                .font(.caption.weight(.bold))
                .foregroundColor(ColorTheme.text)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 100, alignment: .leading)

            Button {
                postRatingsOverlayRequest(game: trend.game, avg: trend.avgRating)
            } label: {
                HStack(spacing: 6) {
                    AverageHeartBadge(value: trend.avgRating, size: 16)
                    Text(formatRatingValue(trend.avgRating))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                if let year = trend.game.computedReleaseYear {
                    Text(String(year))
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                }
                if let publisher, !publisher.isEmpty {
                    if trend.game.computedReleaseYear != nil {
                        Text("•").font(.caption2).foregroundColor(ColorTheme.subtext)
                    }
                    Text(publisher)
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: 100, alignment: .leading)
        }
        .padding(8)
        .frame(width: 116, height: 220, alignment: .topLeading)
        .background(exploreCardBackground(corner: 14))
    }

    private func featuredUserCard(_ user: GamerLnd.UserLite, showTrustedBadge: Bool) -> some View {
        let followers = followersCount[user.id] ?? 0
        let reviews = reviewsCount[user.id] ?? 0
        let avg = userAverageRatings[user.id] ?? 0
        let creatorButtons = creatorButtons(for: user.id)

        return ZStack {
            exploreCardBackground(corner: 16)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AvatarView(name: user.displayName ?? user.username, size: 56, avatarURL: user.avatarUrl)
                        .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(user.displayName ?? user.username)
                                .font(.headline.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if showTrustedBadge || user.isTrustedGamer {
                                Image("trusted_flag")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(ColorTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }
                        }

                        Text("@\(user.username)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    statMiniBlock(value: "\(followers)", label: "Followers")
                    statMiniBlock(value: "\(reviews)", label: "Reviews")
                    statMiniRatingBlock(value: avg)
                }
            }
            .padding(14)
            .padding(.trailing, creatorButtons.isEmpty ? 14 : 52)
        }
        .frame(width: 308, height: 150, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            creatorIconOverlay(for: creatorButtons)
        }
    }

    private func creatorSpotlightCard(_ creator: CreatorSpotlight) -> some View {
        let user = creator.user
        let followers = followersCount[user.id] ?? 0
        let reviews = reviewsCount[user.id] ?? 0
        let avg = userAverageRatings[user.id] ?? 0
        let creatorButtons = creatorButtons(for: CreatorLinks(
            youtubeURL: creator.youtubeURL,
            twitchURL: creator.twitchURL,
            tiktokURL: creator.tiktokURL
        ))

        return ZStack {
            exploreCardBackground(corner: 16)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    AvatarView(name: user.displayName ?? user.username, size: 56, avatarURL: user.avatarUrl)
                        .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(user.displayName ?? user.username)
                                .font(.headline.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            if user.isTrustedGamer {
                                Image("trusted_flag")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(ColorTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }
                        }
                        Text("@\(user.username)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 0)
                }

                HStack(alignment: .center, spacing: 8) {
                    statMiniBlock(value: "\(followers)", label: "Followers")
                    statMiniBlock(value: "\(reviews)", label: "Reviews")
                    statMiniRatingBlock(value: avg)
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .padding(.trailing, creatorButtons.isEmpty ? 14 : 52)
        }
        .frame(width: 308, height: 150, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            creatorIconOverlay(for: creatorButtons)
        }
    }

    private func creatorButtons(for userId: String) -> [CreatorLinkButtonData] {
        guard let links = creatorLinksByUserId[userId] else { return [] }
        return creatorButtons(for: links)
    }

    private func creatorButtons(for links: CreatorLinks) -> [CreatorLinkButtonData] {
        var buttons: [CreatorLinkButtonData] = []
        if let youtube = normalizedCreatorURL(links.youtubeURL) {
            buttons.append(CreatorLinkButtonData(platform: .youtube, url: youtube))
        }
        if let tiktok = normalizedCreatorURL(links.tiktokURL) {
            buttons.append(CreatorLinkButtonData(platform: .tiktok, url: tiktok))
        }
        if let twitch = normalizedCreatorURL(links.twitchURL) {
            buttons.append(CreatorLinkButtonData(platform: .twitch, url: twitch))
        }
        return buttons
    }

    private func normalizedCreatorURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private func creatorIconOverlay(for buttons: [CreatorLinkButtonData]) -> some View {
        if !buttons.isEmpty {
            VStack(spacing: 8) {
                ForEach(buttons) { button in
                    Button {
                        if let url = URL(string: button.url) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        creatorPlatformIcon(platform: button.platform)
                            .frame(width: 24, height: 24)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(ColorTheme.surface))
                            .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 14)
        }
    }

    @ViewBuilder
    private func creatorPlatformIcon(platform: CreatorPlatform) -> some View {
        SocialBrandIconView(platform: platform.rawValue)
    }

    private func statMiniBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundColor(ColorTheme.text)
            Text(label)
                .font(.caption2)
                .foregroundColor(ColorTheme.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statMiniRatingBlock(value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                AverageHeartBadge(value: value, size: 12)
                Text(formatRatingValue(value))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.ratingBandColor(for: value))
            }
            Text("Average Rating")
                .font(.caption2)
                .foregroundColor(ColorTheme.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendingPublisher(for game: Game) -> String? {
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

    private func sortedSavedGames() -> [SavedGameEntry] {
        switch savedGamesSort {
        case .recent:
            return savedGamesList.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .az:
            return savedGamesList.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var saveConfirmOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    showSaveOverlay = false
                    pendingSaveGame = nil
                }

            VStack(spacing: 12) {
                Text("Saved Games")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let pending = pendingSaveGame {
                    let isSaved = savedGameIds.contains(pending.id)
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
                                toggleSavedGame(pending)
                            }
                        } label: {
                            Text(isSaved ? "Saved" : "Save Game")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(isSaved ? ColorTheme.subtext : ColorTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaved)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                }

                HStack {
                    Spacer(minLength: 0)
                    Picker("", selection: $savedGamesSort) {
                        ForEach(SavedGamesSort.allCases) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ColorTheme.accent)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)

                let list = sortedSavedGames()
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
                        } else {
                            ForEach(list) { row in
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
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
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
                    showSaveOverlay = false
                    pendingSaveGame = nil
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .padding(.horizontal, 20)
        }
    }

    private var trustedGamerOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    showTrustedGamerOverlay = false
                    trustedGamerOverlayMode = .info
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if trustedGamerOverlayMode == .apply {
                        Button {
                            trustedGamerOverlayMode = .info
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(ColorTheme.text)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(ColorTheme.surface))
                                .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button {
                        showTrustedGamerOverlay = false
                        trustedGamerOverlayMode = .info
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if trustedGamerOverlayMode == .info {
                            Text("Trusted Gamer")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(ColorTheme.text)

                            HStack(spacing: 12) {
                                Image("trusted_flag")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(ColorTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("This flag marks a Trusted Gamer.")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(ColorTheme.text)
                                    Text("You will see it on user rows and game logs when someone has earned trusted status.")
                                        .font(.footnote)
                                        .foregroundColor(ColorTheme.subtext)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ColorTheme.surface))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(ColorTheme.accent.opacity(0.55), lineWidth: 1)
                            )

                            Text("Trusted Gamers are community members who consistently contribute thoughtful ratings, useful reviews, and strong overall participation.")
                                .font(.body)
                                .foregroundColor(ColorTheme.text)

                            Text("This is not a critic score, paid placement, or permanent badge. Trusted status should be reviewed regularly, held accountable by GamerLnd, and shaped by community feedback over time.")
                                .font(.footnote)
                                .foregroundColor(ColorTheme.subtext)

                            Button {
                                trustedGamerOverlayMode = .apply
                            } label: {
                                Text("Become a Trusted Gamer")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(ColorTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Trusted Gamer Application")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(ColorTheme.text)

                            Text("Tell GamerLnd why you should be considered and include any relevant links or creator/community background.")
                                .font(.footnote)
                                .foregroundColor(ColorTheme.subtext)

                            Group {
                                Text("Why should you be considered?")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                                TextEditor(text: $trustedGamerApplicationWhy)
                                    .frame(height: 110)
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))

                                Text("Links")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                                TextField("YouTube, Twitch, website, social links", text: $trustedGamerApplicationLinks)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))

                                Text("Anything else?")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                                TextEditor(text: $trustedGamerApplicationNotes)
                                    .frame(height: 80)
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                            }

                            Button {
                                submitTrustedGamerApplication()
                            } label: {
                                Text("Send Application")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(ColorTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(trustedGamerApplicationWhy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .frame(width: min(UIScreen.main.bounds.width - 32, 360),
                   height: min(UIScreen.main.bounds.height - 120, trustedGamerOverlayMode == .info ? 420 : 560))
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ColorTheme.background)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator.opacity(0.75), lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
        }
    }

    private var showIdle: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return (mode == .games ? gameResults.isEmpty && !gameLoading : userResults.isEmpty && !userLoading)
        && (mode == .games ? gameError.isEmpty : userError.isEmpty)
    }

    // MARK: - Games List

    private var gamesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if gameLoading && gameResults.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in GameRowSkeleton().padding(.horizontal, 16) }
                }

                if !gameError.isEmpty {
                    Text(gameError)
                        .foregroundColor(ColorTheme.highlight)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                let visibleResults = Array(gameResults.prefix(max(20, visibleGameCount)).enumerated())
                ForEach(visibleResults, id: \.element.id) { entry in
                    let resultIndex = entry.offset
                    let game = entry.element
                    gameRow(game, resultIndex: resultIndex)
                        .padding(.horizontal, 16)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture {
                            dismissKeyboard()
                            selectedGameOverlay = game
                        }
                        .onAppear {
                            if gamerLndAvg[game.id] == nil { fetchGamerLndAverage(for: game.id) }
                            if reviewCountCache[game.id] == nil { fetchReviewCount(for: game.id) }
                        }
                }

                if visibleResults.count < gameResults.count || canLoadMoreGames {
                    Button {
                        loadMoreGameResults()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                            Text("Load more results")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .foregroundColor(ColorTheme.accent)
                    .padding(.top, 6)
                }

                Spacer(minLength: 16)
            }
        }
        .refreshable {
            if !query.isEmpty { performSearch(reset: true, userInitiated: false) }
        }
        .padding(.bottom, 68)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
    }

    private func gameDetailOverlay(game: Game) -> some View {
        GameLogOverlayHost(editor: game) {
            selectedGameOverlay = nil
        }
    }

    private func searchReportOverlay(draft: SearchReportDraft) -> some View {
        GeometryReader { geo in
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    searchReportNotesFocused = false
                }

            VStack {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Report Search Result")
                            .font(.headline.weight(.bold))
                            .foregroundColor(ColorTheme.text)
                        Text(draft.context.gameName)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        dismissSearchReportOverlay()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(ColorTheme.subtext)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(ColorTheme.surface))
                            .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmittingSearchReport)
                }

                Text("Search: \"\(draft.context.query)\"")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)

                VStack(spacing: 8) {
                    ForEach(SearchReportReason.allCases) { reason in
                        Button {
                            selectedSearchReportReason = reason
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedSearchReportReason == reason ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(selectedSearchReportReason == reason ? ColorTheme.accent : ColorTheme.subtext)
                                Text(reason.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedSearchReportReason == reason ? ColorTheme.accent : ColorTheme.separator, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Optional note")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                    TextEditor(text: $searchReportNotes)
                        .focused($searchReportNotesFocused)
                        .scrollContentBackground(.hidden)
                        .frame(height: 82)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                        .foregroundColor(ColorTheme.text)
                }

                HStack(spacing: 10) {
                    Button("Cancel") {
                        dismissSearchReportOverlay()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.subtext)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                    .buttonStyle(.plain)
                    .disabled(isSubmittingSearchReport)

                    Button {
                        submitSearchReport(draft.context)
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmittingSearchReport {
                                ProgressView()
                                    .tint(.black)
                            }
                            Text(isSubmittingSearchReport ? "Sending..." : "Send Report")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmittingSearchReport)
                }
            }
            .padding(18)
            .frame(width: min(geo.size.width - 28, 380))
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ColorTheme.background)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 14)
            .padding(.bottom, max(20, min(searchReportKeyboardHeight * 0.72, 220)))
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        }
    }

    private func recentLogOverlay(log: GameLog) -> some View {
        GameLogOverlayHost(
            preview: .init(
                gameLog: log,
                gameName: resolvedLogGameName(for: log),
                authorUsernameOverride: nil,
                focusCommentOnAppear: false
            )
        ) {
            selectedRecentLogOverlay = nil
        }
    }

    private func resolvedLogGameName(for log: GameLog) -> String {
        if let gameName = log.gameName, !gameName.isEmpty {
            return gameName
        }
        if let overlayGame = selectedGameOverlay, overlayGame.id == log.gameId {
            return overlayGame.name
        }
        if let existing = recentSelfLogs.first(where: { $0.id == log.id })?.gameName, !existing.isEmpty {
            return existing
        }
        return "Game"
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func searchResultTitleFont(for title: String) -> Font {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.count {
        case ...24:
            return .headline.weight(.semibold)
        case ...48:
            return .subheadline.weight(.semibold)
        default:
            return .subheadline.weight(.medium)
        }
    }

    private func gameRow(_ game: Game, resultIndex: Int) -> some View {
        let avg = gamerLndAvg[game.id]
        let count = gamerLndCount[game.id] ?? 0
        let reviewCount = reviewCountCache[game.id] ?? 0
        let isSaved = savedGameIds.contains(game.id)

        return ZStack {
            exploreCardBackground(corner: 14)

            HStack(spacing: 12) {
                if let imgId = game.cover?.imageId ?? game.screenshots?.first?.imageId {
                    GameCoverImage(id: imgId, preset: .custom(width: 120), cornerRadius: 10)
                        .frame(width: 120, height: 160)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ColorTheme.separator.opacity(0.25))
                        .frame(width: 120, height: 160)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name)
                        .font(searchResultTitleFont(for: game.name))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(3)
                        .minimumScaleFactor(0.84)

                    if let y = game.computedReleaseYear {
                        Text(verbatim: String(y))
                            .font(.caption)
                            .foregroundColor(ColorTheme.subtext)
                    }

                    if let gens = game.genres?.map({ $0.name }).prefix(3), !gens.isEmpty {
                        Text(gens.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(1)
                    }

                    if reviewCount > 0 {
                        Text("\(reviewCount) \(reviewCount == 1 ? "review" : "reviews")")
                            .font(.caption2)
                            .foregroundColor(ColorTheme.subtext)
                            .padding(.top, 2)
                    } else {
                        Text("Be the first to review this game")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(ColorTheme.accent)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 2)

                    // Badge
                    CompactGamerLndBadge(avg: avg, count: count) {
                        if let avg, count > 0 {
                            postRatingsOverlayRequest(game: game, avg: avg)
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button {
                        openSearchReport(for: game, resultIndex: resultIndex)
                    } label: {
                        Image(systemName: "flag")
                            .foregroundColor(ColorTheme.subtext)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismissKeyboard()
                        selectedGameOverlay = game
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add")
                        }
                        .foregroundColor(.black)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.accent))
                    }
                    .buttonStyle(.plain)

                    Button {
                        pendingSaveGame = game
                        showSaveOverlay = true
                    } label: {
                        Image(systemName: isSaved ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .foregroundColor(isSaved ? ColorTheme.accent : ColorTheme.subtext)
                            .font(.title3.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded({}))
                }
            }
            .padding(10)
        }
        .frame(height: 180)
    }

    // MARK: - Users List

    private var usersList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if userLoading && userResults.isEmpty {
                    ForEach(0..<8, id: \.self) { _ in UserRowSkeleton().padding(.horizontal, 16) }
                }

                if !userError.isEmpty {
                    Text(userError)
                        .foregroundColor(ColorTheme.highlight)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                ForEach(userResults, id: \.id) { user in
                    NavigationLink(destination: ProfileView(userId: user.id)) {
                        userRow(user)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        recordVisitedUser(user)
                    })
                    .onAppear {
                        if followersCount[user.id] == nil { fetchFollowersCount(for: user.id) }
                        if logsCount[user.id] == nil || reviewsCount[user.id] == nil { fetchLogAndReviewCounts(for: user.id) }
                        if userAverageRatings[user.id] == nil { fetchUserAverageRating(for: user.id) }
                        if lastActivity[user.id] == nil { fetchLastActivity(for: user.id) }
                        if followingState[user.id] == nil { fetchFollowingState(for: user.id) }

                        if user.id == userResults.suffix(5).first?.id, canLoadMoreUsers, !userLoading {
                            loadMoreUsers()
                        }
                    }
                }

                if canLoadMoreUsers {
                    Button {
                        loadMoreUsers()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                            Text("Load more results")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .foregroundColor(ColorTheme.accent)
                    .padding(.top, 6)
                }

                Spacer(minLength: 16)
            }
        }
        .refreshable {
            if !query.isEmpty { performSearch(reset: true, userInitiated: false) }
        }
    }

    private func userRow(_ user: GamerLnd.UserLite) -> some View {
        let fCount = followersCount[user.id] ?? 0
        let rCount = reviewsCount[user.id] ?? 0
        let avgRating = userAverageRatings[user.id] ?? 0
        let last = lastActivity[user.id]
        let isFollowing = followingState[user.id] ?? false
        let isMe = (user.id == Auth.auth().currentUser?.uid)
        let socialButtons = creatorButtons(for: user.id)

        return ZStack {
            exploreCardBackground(corner: 14)

            HStack(spacing: 12) {
                AvatarView(name: user.displayName ?? user.username, size: 54, avatarURL: user.avatarUrl)
                    .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(user.displayName ?? user.username)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        if user.isTrustedGamer {
                            Image("trusted_flag")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(ColorTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 8) {
                        HStack(spacing: 4) { Image(systemName: "person.2"); Text("\(fCount)") }
                        HStack(spacing: 4) { Image(systemName: "text.bubble"); Text("\(rCount)") }
                        HStack(spacing: 4) {
                            PixelHeartIcon(color: ColorTheme.ratingBandColor(for: avgRating), size: 10)
                            Text(formatRatingValue(avgRating))
                        }
                    }
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)

                    if let last = last {
                        Text("Active \(relativeDate(last))")
                            .font(.caption2)
                            .foregroundColor(ColorTheme.subtext)
                    }
                }
                .padding(.trailing, socialButtons.isEmpty ? 0 : 4)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    if !socialButtons.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(socialButtons) { button in
                                Button {
                                    if let url = URL(string: button.url) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    creatorPlatformIcon(platform: button.platform)
                                        .frame(width: 18, height: 18)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(ColorTheme.surface))
                                        .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !isMe {
                        Button {
                            InteractionService.shared.toggleFollow(u: user.id, isFollowing: isFollowing) { newState in
                                followingState[user.id] = newState
                                followersCount[user.id] = max(0, (followersCount[user.id] ?? 0) + (newState ? 1 : -1))
                                Haptics.success()
                                AnalyticsService.shared.trackFollow(targetUserId: user.id, nowFollowing: newState)
                            }
                        } label: {
                            Text(isFollowing ? "Followed" : "Follow")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(
                                    Group {
                                        if isFollowing {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(ColorTheme.separator.opacity(0.25))
                                        } else {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(ColorTheme.surface)
                                        }
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(isFollowing ? ColorTheme.highlight : ColorTheme.accent)
                        .simultaneousGesture(TapGesture().onEnded({}))
                    }
                }
            }
            .padding(10)
        }
        .frame(height: socialButtons.isEmpty ? 90 : 102)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func exploreCardBackground(corner: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(ColorTheme.surface)
            LinearGradient(
                colors: [ColorTheme.accent.opacity(0.13), ColorTheme.gold.opacity(0.08), ColorTheme.surface.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(ColorTheme.separator.opacity(0.85), lineWidth: 1)
        }
    }

    // MARK: - Saved Games (Search)

    private func loadSavedGames() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).getDocument { snap, _ in
            let list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            let ids = list.compactMap { $0["id"] as? Int }
            let entries: [SavedGameEntry] = list.compactMap { item in
                guard let id = item["id"] as? Int else { return nil }
                let addedAt: Date?
                if let ts = item["added_at"] as? Timestamp {
                    addedAt = ts.dateValue()
                } else {
                    addedAt = nil
                }
                return SavedGameEntry(
                    id: id,
                    name: (item["name"] as? String) ?? "Game #\(id)",
                    coverId: item["cover_id"] as? String,
                    addedAt: addedAt
                )
            }
            DispatchQueue.main.async {
                savedGameIds = Set(ids)
                savedGamesList = entries
            }
        }
    }

    private func toggleSavedGame(_ game: Game) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let doc = db.collection("users").document(uid)
        doc.getDocument { snap, _ in
            var list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            if let idx = list.firstIndex(where: { ($0["id"] as? Int) == game.id }) {
                list.remove(at: idx)
            } else {
                var dict: [String: Any] = [
                    "id": game.id,
                    "name": game.name,
                    "added_at": Timestamp(date: Date())
                ]
                if let coverId = game.cover?.imageId {
                    dict["cover_id"] = coverId
                }
                list.append(dict)
                RewardService.shared.awardForSaveGame(gameId: game.id)
            }
            doc.setData(["watchlist_games": list], merge: true) { _ in
                loadSavedGames()
            }
        }
    }

    // MARK: - Skeletons

    private struct GameRowSkeleton: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10).fill(ColorTheme.separator.opacity(0.25))
                        .frame(width: 120, height: 160)
                        .redactedShimmer()
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.25)).frame(height: 14)
                        RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.18)).frame(height: 12)
                        RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.18)).frame(height: 12)
                        Spacer()
                        RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.22)).frame(width: 160, height: 20)
                    }
                    Spacer()
                }
                .padding(10)
            }
            .frame(height: 180)
        }
    }

private struct UserRowSkeleton: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                HStack(spacing: 12) {
                    Circle().fill(ColorTheme.separator.opacity(0.25)).frame(width: 54, height: 54).redactedShimmer()
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.25)).frame(height: 14)
                        RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.18)).frame(height: 12)
                        RoundedRectangle(cornerRadius: 6).fill(ColorTheme.separator.opacity(0.18)).frame(height: 10)
                    }
                    Spacer()
                }
                .padding(10)
            }
            .frame(height: 90)
        }
    }

    // MARK: - Actions

    private func loadDiscoverRows() {
        isLoadingDiscoverRows = true
        loadTrendingGames()
        loadRecentSelfLogs()
        loadTrustedUsersRow()
        loadCreatorSpotlights()
    }

    private func loadRecentSelfLogs() {
        guard let uid = Auth.auth().currentUser?.uid else {
            recentSelfLogs = []
            return
        }
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: uid)
            .order(by: "play_date", descending: true)
            .limit(to: 12)
            .getDocuments { snap, _ in
                DispatchQueue.main.async {
                    self.recentSelfLogs = (snap?.documents ?? []).compactMap {
                        ProfileView.parseGameLog(docIdFallback: $0.documentID, data: $0.data())
                    }
                }
            }
    }

    private func loadTrendingGames() {
        let fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(timeIntervalSinceNow: -2_592_000)
        let currentUid = Auth.auth().currentUser?.uid

        let fetchLogs: (Set<String>) -> Void = { followedIds in
            self.db.collection("game_logs")
                .whereField("play_date", isGreaterThan: Timestamp(date: fromDate))
                .order(by: "play_date", descending: true)
                .limit(to: 350)
                .getDocuments { snap, _ in
                    let docs = snap?.documents ?? []
                    var weighted: [Int: Double] = [:]
                    let now = Date()

                    for d in docs {
                        let data = d.data()
                        let gid = data["game_id"] as? Int ?? 0
                        guard gid > 0 else { continue }
                        let logUserId = data["user_id"] as? String ?? ""
                        if logUserId == currentUid { continue }
                        let rating = ((data["rating"] as? Double) ?? (data["rating"] as? NSNumber)?.doubleValue ?? 0)
                        let review = (data["review"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let playDate = (data["play_date"] as? Timestamp)?.dateValue() ?? now
                        let ageDays = max(0, Calendar.current.dateComponents([.day], from: playDate, to: now).day ?? 0)
                        let recency = max(0.35, 1.0 - (Double(ageDays) / 28.0))
                        let followBoost = followedIds.contains(logUserId) ? 1.7 : 1.0
                        let actionWeight = (1.0 + (rating > 0 ? 0.55 : 0.0) + (!review.isEmpty ? 0.9 : 0.0)) * followBoost
                        weighted[gid, default: 0] += actionWeight * recency
                    }

                    let topIds = weighted.sorted { lhs, rhs in
                        lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
                    }.prefix(12).map(\.key)

                    if topIds.isEmpty {
                        DispatchQueue.main.async {
                            self.trendingGames = []
                            self.isLoadingDiscoverRows = false
                        }
                        return
                    }

                    self.igdb.fetchGamesByIds(ids: topIds) { result in
                        switch result {
                        case .success(let games):
                            var cards: [TrendingGameCard] = []
                            let group = DispatchGroup()
                            for game in games {
                                let gid = game.id
                                group.enter()
                                GamerLndScoreService.shared.fetchAverage(gameId: gid) { avg, _ in
                                    DispatchQueue.main.async {
                                        cards.append(TrendingGameCard(game: game, avgRating: avg ?? 0, activity: Int((weighted[gid] ?? 0).rounded())))
                                        group.leave()
                                    }
                                }
                            }
                            group.notify(queue: .main) {
                                self.trendingGames = cards.sorted {
                                    if $0.activity == $1.activity {
                                        return $0.avgRating == $1.avgRating ? $0.game.name < $1.game.name : $0.avgRating > $1.avgRating
                                    }
                                    return $0.activity > $1.activity
                                }
                                self.isLoadingDiscoverRows = false
                            }
                        case .failure:
                            DispatchQueue.main.async {
                                self.trendingGames = []
                                self.isLoadingDiscoverRows = false
                            }
                        }
                    }
                }
        }

        guard let currentUid else {
            fetchLogs([])
            return
        }

        db.collection("follows")
            .whereField("follower_id", isEqualTo: currentUid)
            .getDocuments { snap, _ in
                let followedIds = Set((snap?.documents ?? []).compactMap { $0.data()["followed_id"] as? String })
                fetchLogs(followedIds)
            }
    }

    private func loadTrustedUsersRow() {
        db.collection("users")
            .whereField("is_trusted_gamer", isEqualTo: true)
            .limit(to: 20)
            .getDocuments { snap, _ in
                DispatchQueue.main.async {
                    self.trustedUsersRow = (snap?.documents ?? []).compactMap { d in
                        let data = d.data()
                        let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                        let displayName = data["display_name"] as? String
                        return GamerLnd.UserLite(
                            id: d.documentID,
                            username: uname,
                            displayName: displayName,
                            avatarUrl: data["avatar_url"] as? String,
                            isTrustedGamer: true
                        )
                    }
                    .sorted { ($0.displayName ?? $0.username).localizedCaseInsensitiveCompare($1.displayName ?? $1.username) == .orderedAscending }
                    self.trustedUsersRow.forEach { self.hydrateUserCardStats(for: $0.id) }
                }
            }
    }

    private func loadCreatorSpotlights() {
        db.collection("users")
            .limit(to: 100)
            .getDocuments { snap, _ in
                let creators: [CreatorSpotlight] = (snap?.documents ?? []).compactMap { doc in
                    let data = doc.data()
                    let youtube = (data["youtube_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let twitch = (data["twitch_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let tiktok = (data["tiktok_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !youtube.isEmpty || !twitch.isEmpty || !tiktok.isEmpty else { return nil }

                    let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                    let displayName = data["display_name"] as? String
                    let user = GamerLnd.UserLite(
                        id: doc.documentID,
                        username: uname,
                        displayName: displayName,
                        avatarUrl: data["avatar_url"] as? String,
                        isTrustedGamer: (data["is_trusted_gamer"] as? Bool) ?? false
                    )

                    return CreatorSpotlight(
                        id: doc.documentID,
                        user: user,
                        youtubeURL: youtube.isEmpty ? nil : youtube,
                        twitchURL: twitch.isEmpty ? nil : twitch,
                        tiktokURL: tiktok.isEmpty ? nil : tiktok
                    )
                }

                DispatchQueue.main.async {
                    self.creatorSpotlights = creators.sorted {
                        ($0.user.displayName ?? $0.user.username).localizedCaseInsensitiveCompare($1.user.displayName ?? $1.user.username) == .orderedAscending
                    }
                    creators.forEach { creator in
                        self.creatorLinksByUserId[creator.user.id] = CreatorLinks(
                            youtubeURL: creator.youtubeURL,
                            twitchURL: creator.twitchURL,
                            tiktokURL: creator.tiktokURL
                        )
                        self.hydrateUserCardStats(for: creator.user.id)
                    }
                }
            }
    }

    private func loadVisitedUserHistory() {
        guard let key = visitedUsersKey else {
            visitedUserHistory = []
            return
        }
        let ids = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        guard !ids.isEmpty else {
            visitedUserHistory = []
            return
        }
        fetchUsers(byIDs: ids) { users in
            DispatchQueue.main.async {
                self.visitedUserHistory = users
                users.forEach { self.hydrateUserCardStats(for: $0.id) }
            }
        }
    }

    private func recordVisitedUser(_ user: GamerLnd.UserLite) {
        guard let key = visitedUsersKey else { return }
        var ids = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        ids.removeAll { $0 == user.id }
        ids.insert(user.id, at: 0)
        if ids.count > 12 { ids.removeLast(ids.count - 12) }
        UserDefaults.standard.set(ids, forKey: key)

        var updated = visitedUserHistory.filter { $0.id != user.id }
        updated.insert(user, at: 0)
        if updated.count > 12 { updated.removeLast(updated.count - 12) }
        visitedUserHistory = updated
        hydrateUserCardStats(for: user.id)
    }

    private func fetchUsers(byIDs ids: [String], completion: @escaping ([GamerLnd.UserLite]) -> Void) {
        let chunks = stride(from: 0, to: ids.count, by: 10).map { Array(ids[$0..<min($0 + 10, ids.count)]) }
        guard !chunks.isEmpty else {
            completion([])
            return
        }

        var collected: [GamerLnd.UserLite] = []
        let group = DispatchGroup()
        for chunk in chunks {
            group.enter()
            db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { snap, _ in
                    let users = (snap?.documents ?? []).compactMap { d -> GamerLnd.UserLite? in
                        let data = d.data()
                        let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                        return GamerLnd.UserLite(
                            id: d.documentID,
                            username: uname,
                            displayName: data["display_name"] as? String,
                            avatarUrl: data["avatar_url"] as? String,
                            isTrustedGamer: data["is_trusted_gamer"] as? Bool ?? false
                        )
                    }
                    collected.append(contentsOf: users)
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            let byId = Dictionary(uniqueKeysWithValues: collected.map { ($0.id, $0) })
            completion(ids.compactMap { byId[$0] })
        }
    }

    private func hydrateUserCardStats(for userId: String) {
        if followersCount[userId] == nil { fetchFollowersCount(for: userId) }
        if logsCount[userId] == nil || reviewsCount[userId] == nil { fetchLogAndReviewCounts(for: userId) }
        if userAverageRatings[userId] == nil { fetchUserAverageRating(for: userId) }
        if creatorLinksByUserId[userId] == nil { fetchCreatorLinks(for: userId) }
    }

    private func fetchCreatorLinks(for userId: String) {
        db.collection("users")
            .document(userId)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }
                let links = CreatorLinks(
                    youtubeURL: (data["youtube_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    twitchURL: (data["twitch_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    tiktokURL: (data["tiktok_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                guard links.hasAny else {
                    DispatchQueue.main.async {
                        self.creatorLinksByUserId[userId] = CreatorLinks(youtubeURL: nil, twitchURL: nil, tiktokURL: nil)
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.creatorLinksByUserId[userId] = links
                }
            }
    }

    private func fetchUserAverageRating(for userId: String) {
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: userId)
            .getDocuments { snap, _ in
                let ratings = (snap?.documents ?? []).compactMap { doc -> Double? in
                    let value = doc.data()["rating"] as? Double
                    guard let value, value > 0 else { return nil }
                    return value
                }
                DispatchQueue.main.async {
                    self.userAverageRatings[userId] = ratings.isEmpty ? 0 : (ratings.reduce(0, +) / Double(ratings.count))
                }
            }
    }

    private func submitGameSuggestion(payload: GameSubmissionPayload) {
        let uid = Auth.auth().currentUser?.uid ?? "anon"
        let data: [String: Any] = [
            "user_id": uid,
            "game_name": payload.gameName,
            "platform": payload.platform,
            "release_year": payload.releaseYear,
            "publisher": payload.publisher,
            "notes": payload.notes,
            "status": "pending",
            "created_at": Timestamp(date: Date()),
            "review_email": "programming.pf@gmail.com"
        ]
        db.collection("game_submissions").addDocument(data: data) { err in
            DispatchQueue.main.async {
                if let err {
                    toast = Toast(kind: .error, message: "Submission failed: \(err.localizedDescription)")
                } else {
                    toast = Toast(kind: .success, message: "Game submission sent")
                    self.openSupportEmailDraft(subject: "GamerLnd Game Submission", body: self.gameSubmissionEmailBody(payload: payload))
                }
            }
        }
    }

    private func submitFeedback(payload: FeedbackPayload) {
        let uid = Auth.auth().currentUser?.uid ?? "anon"
        let data: [String: Any] = [
            "user_id": uid,
            "category": payload.category,
            "message": payload.message,
            "related_game": payload.relatedGame,
            "status": "open",
            "created_at": Timestamp(date: Date()),
            "review_email": "programming.pf@gmail.com"
        ]
        db.collection("user_feedback").addDocument(data: data) { err in
            DispatchQueue.main.async {
                if let err {
                    toast = Toast(kind: .error, message: "Feedback failed: \(err.localizedDescription)")
                } else {
                    toast = Toast(kind: .success, message: "Feedback sent")
                    self.openSupportEmailDraft(subject: "GamerLnd Feedback", body: self.feedbackEmailBody(payload: payload))
                }
            }
        }
    }

    private func submitTrustedGamerApplication() {
        let why = trustedGamerApplicationWhy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !why.isEmpty else { return }

        let uid = Auth.auth().currentUser?.uid ?? "anon"
        let data: [String: Any] = [
            "user_id": uid,
            "why": why,
            "links": trustedGamerApplicationLinks.trimmingCharacters(in: .whitespacesAndNewlines),
            "notes": trustedGamerApplicationNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            "status": "pending",
            "created_at": Timestamp(date: Date()),
            "review_email": "programming.pf@gmail.com"
        ]

        db.collection("trusted_gamer_applications").addDocument(data: data) { err in
            DispatchQueue.main.async {
                if let err {
                    toast = Toast(kind: .error, message: "Application failed: \(err.localizedDescription)")
                } else {
                    trustedGamerApplicationWhy = ""
                    trustedGamerApplicationLinks = ""
                    trustedGamerApplicationNotes = ""
                    trustedGamerOverlayMode = .info
                    showTrustedGamerOverlay = false
                    toast = Toast(kind: .success, message: "Application sent")
                    self.openSupportEmailDraft(subject: "GamerLnd Trusted Gamer Application", body: self.trustedGamerEmailBody())
                }
            }
        }
    }

    private func openSupportEmailDraft(subject: String, body: String) {
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        guard let url = URL(string: "mailto:programming.pf@gmail.com?subject=\(subjectEncoded)&body=\(bodyEncoded)") else { return }
        UIApplication.shared.open(url)
    }

    private func gameSubmissionEmailBody(payload: GameSubmissionPayload) -> String {
        [
            "Game Submission",
            "",
            "Game: \(payload.gameName)",
            "Platform: \(payload.platform)",
            "Release Year: \(payload.releaseYear)",
            "Publisher: \(payload.publisher)",
            "Notes: \(payload.notes)",
            "User ID: \(Auth.auth().currentUser?.uid ?? "anon")"
        ].joined(separator: "\n")
    }

    private func feedbackEmailBody(payload: FeedbackPayload) -> String {
        [
            "Feedback",
            "",
            "Category: \(payload.category)",
            "Related Game: \(payload.relatedGame)",
            "Message: \(payload.message)",
            "User ID: \(Auth.auth().currentUser?.uid ?? "anon")"
        ].joined(separator: "\n")
    }

    private func trustedGamerEmailBody() -> String {
        [
            "Trusted Gamer Application",
            "",
            "Why: \(trustedGamerApplicationWhy)",
            "Links: \(trustedGamerApplicationLinks)",
            "Notes: \(trustedGamerApplicationNotes)",
            "User ID: \(Auth.auth().currentUser?.uid ?? "anon")"
        ].joined(separator: "\n")
    }

    private func performSearch(reset: Bool, userInitiated: Bool = false) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = q.hasPrefix("@") ? String(q.dropFirst()) : q
        guard !q.isEmpty else { return }
        debounceTask?.cancel(); debounceTask = nil
        let normalizedGameInput = normalizedGameSearchInput(q)

        if userInitiated, let key = lastSearchesKey {
            var recents = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
            if let idx = recents.firstIndex(of: q) { recents.remove(at: idx) }
            recents.insert(q, at: 0)
            if recents.count > 10 { recents.removeLast(recents.count - 10) }
            lastSearches = recents
            UserDefaults.standard.set(recents, forKey: key)
            AnalyticsService.shared.trackSearchSubmitted(query: q, resultsCount: 0)
        }

        switch mode {
        case .games:
            if reset {
                gameResults = []; canLoadMoreGames = false; nextGameOffset = 0; visibleGameCount = 20
                if userInitiated {
                    RewardService.shared.recordSearch(query: normalizedGameInput)
                }
            }
            gameError = ""; gameLoading = true

            // Use your existing IGDBService signature (no order args). Sort/filter locally below.
            igdb.searchGamesPaged(query: normalizedGameInput, year: nil, genre: nil, limit: gameFetchSize, offset: nextGameOffset) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let games):
                        // If results are weak, run one broader fallback query to improve typo/partial matching.
                        if reset, games.count < 8, let fallback = self.fallbackGameQuery(from: normalizedGameInput) {
                            self.igdb.searchGamesPaged(query: fallback, year: nil, genre: nil, limit: self.gameFetchSize, offset: 0) { fallbackResult in
                                DispatchQueue.main.async {
                                    self.gameLoading = false
                                    let fallbackGames: [Game]
                                    if case .success(let fg) = fallbackResult { fallbackGames = fg } else { fallbackGames = [] }
                                    self.handleGameSearchSuccess(primary: games, fallback: fallbackGames, query: normalizedGameInput)
                                }
                            }
                        } else {
                            self.gameLoading = false
                            self.handleGameSearchSuccess(primary: games, fallback: [], query: normalizedGameInput)
                        }
                    case .failure(let err):
                        self.gameLoading = false
                        self.gameError = err.localizedDescription
                        self.toast = Toast(kind: .error, message: "Search failed: \(err.localizedDescription)")
                        AnalyticsService.shared.trackError(err, context: "game_search_failed")
                    }
                }
            }

        case .users:
            if reset {
                userResults = []; canLoadMoreUsers = false; lastUserDoc = nil
            }
            userError = ""; userLoading = true
            queryUsers(prefix: normalized, reset: reset)
        }
    }

    private func handleGameSearchSuccess(primary: [Game], fallback: [Game], query: String) {
        var merged = Dictionary(uniqueKeysWithValues: gameResults.map { ($0.id, $0) })
        for g in primary { merged[g.id] = g }
        for g in fallback { merged[g.id] = g }
        gameResults = Array(merged.values)
        canLoadMoreGames = (primary.count >= gameFetchSize)
        if canLoadMoreGames { nextGameOffset += gameFetchSize }

        for g in primary {
            if gamerLndAvg[g.id] == nil { fetchGamerLndAverage(for: g.id) }
            if reviewCountCache[g.id] == nil { fetchReviewCount(for: g.id) }
        }
        for g in fallback {
            if gamerLndAvg[g.id] == nil { fetchGamerLndAverage(for: g.id) }
            if reviewCountCache[g.id] == nil { fetchReviewCount(for: g.id) }
        }
        fetchInAppActivity(for: Array(merged.keys))

        applyGameSortAndFilters()
        AnalyticsService.shared.trackSearchSubmitted(query: query, resultsCount: gameResults.count)
    }

    private func fallbackGameQuery(from query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 3 else { return nil }
        let firstToken = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        if let canonical = canonicalFranchiseToken(for: firstToken), canonical != firstToken {
            return canonical
        }
        if firstToken.count <= 3 { return firstToken }
        return String(firstToken.prefix(3))
    }

    private func fetchInAppActivity(for ids: [Int]) {
        let unique = Array(Set(ids)).filter { $0 > 0 }
        guard !unique.isEmpty else { return }
        let fromDate = Calendar.current.date(byAdding: .day, value: -180, to: Date()) ?? Date(timeIntervalSinceNow: -15_552_000)
        let chunks = stride(from: 0, to: unique.count, by: 10).map { Array(unique[$0..<min($0 + 10, unique.count)]) }
        let group = DispatchGroup()
        var totals: [Int: Double] = [:]
        let now = Date()

        for chunk in chunks {
            group.enter()
            db.collection("game_logs")
                .whereField("game_id", in: chunk)
                .whereField("play_date", isGreaterThan: Timestamp(date: fromDate))
                .getDocuments { snap, _ in
                    for d in snap?.documents ?? [] {
                        let data = d.data()
                        let gid = data["game_id"] as? Int ?? 0
                        guard gid > 0 else { continue }
                        let rating = ((data["rating"] as? Double) ?? (data["rating"] as? NSNumber)?.doubleValue ?? 0)
                        let review = (data["review"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let playDate = (data["play_date"] as? Timestamp)?.dateValue() ?? now
                        let ageDays = max(0, Calendar.current.dateComponents([.day], from: playDate, to: now).day ?? 0)
                        let recency = max(0.3, 1.0 - (Double(ageDays) / 180.0))
                        let weight = 1.0 + (rating > 0 ? 0.45 : 0.0) + (!review.isEmpty ? 0.8 : 0.0)
                        totals[gid, default: 0] += (weight * recency)
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            for (k, v) in totals { appActivityByGame[k] = v }
            applyGameSortAndFilters()
        }
    }

    private func normalizedGameSearchInput(_ query: String) -> String {
        let lowered = query.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let firstToken = compact.split(separator: " ").first.map(String.init) ?? compact
        if let canonical = canonicalFranchiseToken(for: firstToken) {
            return compact.replacingOccurrences(of: firstToken, with: canonical)
        }
        return compact
    }

    private func canonicalFranchiseToken(for token: String) -> String? {
        let seed = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !seed.isEmpty else { return nil }
        let canonical = ["mario", "zelda", "pokemon", "metroid", "sonic", "final fantasy", "dragon quest", "resident evil", "call of duty"]
        for key in canonical {
            let d = levenshteinDistance(seed, key)
            if d <= 2 || key.hasPrefix(seed) || seed.hasPrefix(key) {
                return key
            }
        }
        return nil
    }

    private func loadMoreGames() {
        guard !gameLoading, canLoadMoreGames else { return }
        performSearch(reset: false, userInitiated: false)
    }

    private func loadMoreGameResults() {
        // Page through local ranked results in 20-item chunks.
        if visibleGameCount < gameResults.count {
            visibleGameCount = min(gameResults.count, visibleGameCount + 20)
            return
        }
        // If local buffer is exhausted, fetch the next chunk from IGDB.
        visibleGameCount += 20
        loadMoreGames()
    }

    // Local filter + sort for games
    private func applyGameSortAndFilters() {
        var list = gameResults
        let queryLower = normalizedGameSearchInput(query.trimmingCharacters(in: .whitespacesAndNewlines))

        // Step 2: remove categories/noise that are poor primary search results.
        list = list.filter { passesGameSearchFilters($0, queryLower: queryLower) }

        // Filters
        if let y = selectedYear {
            list = list.filter { $0.computedReleaseYear == y }
        }
        if let g = selectedGenre?.lowercased(), !g.isEmpty {
            list = list.filter { game in
                (game.genres ?? []).contains { $0.name.lowercased().contains(g) }
            }
        }
        if let p = selectedPlatform?.lowercased(), !p.isEmpty {
            list = list.filter { game in
                (game.platforms ?? []).contains { $0.name.lowercased().contains(p) }
            }
        }

        // Sorts
        switch selectedGameSort {
        case .relevance:
            list.sort {
                let sa = relevanceScore(for: $0, queryLower: queryLower)
                let sb = relevanceScore(for: $1, queryLower: queryLower)
                if sa == sb {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return sa > sb
            }
        case .popularity:
            list.sort {
                let a = $0.popularity ?? Double($0.totalRatingCount ?? $0.ratingCount ?? 0)
                let b = $1.popularity ?? Double($1.totalRatingCount ?? $1.ratingCount ?? 0)
                return a > b
            }
        case .glRating:
            list.sort {
                let a = gamerLndAvg[$0.id] ?? 0
                let b = gamerLndAvg[$1.id] ?? 0
                return a > b
            }
        case .newest:
            list.sort {
                let a = $0.computedReleaseYear ?? 0
                let b = $1.computedReleaseYear ?? 0
                return a > b
            }
        case .alpha:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        gameResults = list
    }

    private func passesGameSearchFilters(_ game: Game, queryLower: String) -> Bool {
        // Hard-filter categories we never want near the top for discovery searches.
        if let cat = game.category, [3, 5, 12, 13, 14].contains(cat) {
            return false
        }

        let name = game.name.lowercased()
        let normalizedName = name
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let strongTextMatch =
            (!queryLower.isEmpty && normalizedName == queryLower)
            || normalizedName.hasPrefix(queryLower)
            || normalizedName.contains(queryLower)

        // Deprioritize/trim obvious fan-mod noise if it is not a strong text match.
        if !strongTextMatch {
            let noisyTokens = ["fan", "fangame", "mod", "hack", "randomizer", "romhack", "prototype", "beta", "demo"]
            if noisyTokens.contains(where: { name.contains($0) }) {
                return false
            }
        }

        // Ignore very low-signal entries unless they strongly match the query.
        if !strongTextMatch {
            let rc = game.totalRatingCount ?? game.ratingCount ?? 0
            let h = game.hypes ?? 0
            let p = game.popularity ?? 0
            if rc < 3 && h < 2 && p < 5 {
                return false
            }
        }
        return true
    }

    private func relevanceScore(for game: Game, queryLower: String) -> Double {
        let name = game.name.lowercased()
        let normalizedName = name
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let wordSet = Set(words)
        let queryWords = Set(queryLower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        var score = 0.0

        if !queryLower.isEmpty {
            // STEP 3: weighted scoring model
            if normalizedName == queryLower { score += 1000 }        // exact match boost
            if normalizedName.hasPrefix(queryLower) { score += 600 } // prefix boost
            if normalizedName.contains(queryLower) { score += 260 }  // partial match

            let overlap = Double(wordSet.intersection(queryWords).count)
            score += overlap * 90

            if let firstWord = words.first, !queryLower.isEmpty {
                let d = levenshteinDistance(firstWord, queryLower)
                if d <= 2 { score += Double((3 - d) * 120) }
            }

            let queryTokens = queryLower.split(separator: " ").map(String.init)
            var typoBonus = 0.0
            for token in queryTokens where token.count >= 3 {
                let bestDistance = words.map { levenshteinDistance($0, token) }.min() ?? 99
                if bestDistance <= 2 {
                    typoBonus += Double((3 - bestDistance) * 95)
                }
            }
            score += typoBonus
        }

        let popularity = game.popularity ?? Double(game.totalRatingCount ?? game.ratingCount ?? 0)
        let ratingCount = Double(game.totalRatingCount ?? game.ratingCount ?? 0)
        let hypes = Double(game.hypes ?? 0)
        let appActivity = appActivityByGame[game.id] ?? 0

        if let rating = game.rating {
            score += min(140, rating * 1.6)
        }
        score += min(160, log10(max(1, popularity)) * 75)
        score += min(180, log10(max(1, ratingCount)) * 85)
        score += min(110, log10(max(1, hypes)) * 70)
        score += min(220, appActivity * 45)

        if let year = game.computedReleaseYear {
            score += max(0, 35 - Double(max(0, 2010 - year)) * 0.35)
        }

        // Prefer official, major-release categories.
        if let category = game.category {
            switch category {
            case 0: score += 190   // main_game
            case 8: score += 120   // remake
            case 9: score += 105   // remaster
            case 11: score += 70   // port
            case 2, 4: score += 35 // expansion / standalone expansion
            case 1: score -= 20    // dlc/addon
            default: score -= 40
            }
        }

        // De-prioritize fan builds/mod forks and non-mainline variants.
        let penalties = ["hack", "fan", "mod", "randomizer", "prototype", "beta", "demo", "satellaview", "master quest", "romhack", "retexture", "olympic", "tour", "maker", "party", "pinball", "tribute", "remix", "fangame"]
        for p in penalties where name.contains(p) {
            score -= 140
        }
        if name.contains("dx") || name.contains("edition") || name.contains("collection") {
            score -= 28
        }

        if queryLower == "mario" || queryLower == "super mario" {
            if name.contains("mario kart") || name.contains("mario party") || name.contains("olympic") || name.contains("tour") {
                score -= 110
            }
            if name.hasPrefix("super mario") || name.contains(" mario bros") {
                score += 90
            }
        }
        if queryLower == "zelda" || queryLower == "the legend of zelda" {
            if name.hasPrefix("the legend of zelda") { score += 110 }
            if name.contains("satellaview") || name.contains("bs zelda") || name.contains("master quest") { score -= 120 }
        }
        if queryLower == "pokemon" && (name.contains("pinball") || name.contains("stadium") || name.contains("shuffle")) {
            score -= 90
        }

        return score
    }

    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var prev = Array(0...bChars.count)
        var curr = Array(repeating: 0, count: bChars.count + 1)

        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[bChars.count]
    }

    private func queryUsers(prefix: String, reset: Bool) {
        let lower = prefix.lowercased()
        let firstToken = lower.split(separator: " ").first.map(String.init) ?? lower
        var ref: Query = db.collection("users")
            .order(by: "username_lower")
            .start(at: [lower])
            .end(at: [lower + "\u{f8ff}"])
            .limit(to: pageSize)

        if let last = lastUserDoc { ref = ref.start(afterDocument: last) }

        ref.getDocuments { snap, err in
            if let ns = err as NSError?, ns.code == 9 || ns.code == 7 {
                // Fallback
                self.queryUsersFallback(prefix: prefix, reset: reset)
                return
            }
            self.userLoading = false
            if let err = err {
                self.userError = err.localizedDescription
                self.toast = Toast(kind: .error, message: "Search failed: \(err.localizedDescription)")
                return
            }
            self.lastUserDoc = snap?.documents.last
            let newUsers: [GamerLnd.UserLite] = (snap?.documents ?? []).compactMap { d in
                let data = d.data()
                let id = (data["id"] as? String) ?? d.documentID
                let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                let displayName = data["display_name"] as? String
                return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String, isTrustedGamer: (data["is_trusted_gamer"] as? Bool) ?? false)
            }
            mergeUsersAndApply(newUsers)
            // Also try matching by display name for broader results.
            self.queryUsersByDisplayName(prefix: prefix, token: firstToken)
            // And a broad prefix array search for display names (legacy users)
            self.queryUsersByPrefixArray(prefix: prefix)
        }
    }

    private func queryUsersByDisplayName(prefix: String, token: String) {
        let lower = prefix.lowercased()
        let tokenLower = token.lowercased()
        let ref: Query = db.collection("users")
            .order(by: "display_name_lower")
            .start(at: [tokenLower])
            .end(at: [tokenLower + "\u{f8ff}"])
            .limit(to: pageSize)

        ref.getDocuments { snap, err in
            if err != nil {
                // Fallback to legacy display_name field if index missing
                self.queryUsersByDisplayNameLegacy(prefix: prefix, token: token)
                return
            }
            let newUsers: [GamerLnd.UserLite] = (snap?.documents ?? []).compactMap { d in
                let data = d.data()
                let id = (data["id"] as? String) ?? d.documentID
                let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                let displayName = data["display_name"] as? String
                return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String, isTrustedGamer: (data["is_trusted_gamer"] as? Bool) ?? false)
            }
            self.mergeUsersAndApply(newUsers)
            // If no results, fallback: broaden by first 2 letters and filter locally
            if self.userResults.isEmpty && lower.count >= 2 {
                let two = String(lower.prefix(2))
                let broad: Query = self.db.collection("users")
                    .order(by: "display_name_lower")
                    .start(at: [two])
                    .end(at: [two + "\u{f8ff}"])
                    .limit(to: 50)
                broad.getDocuments { snap2, _ in
                    let fallbackUsers: [GamerLnd.UserLite] = (snap2?.documents ?? []).compactMap { d in
                        let data = d.data()
                        let id = (data["id"] as? String) ?? d.documentID
                        let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                        let displayName = data["display_name"] as? String
                        return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String, isTrustedGamer: (data["is_trusted_gamer"] as? Bool) ?? false)
                    }
                    let filtered = fallbackUsers.filter { u in
                        let hay = ((u.displayName ?? u.username)).lowercased()
                        return hay.contains(lower)
                    }
                    self.mergeUsersAndApply(filtered)
                }
            }
        }
    }

    private func queryUsersByPrefixArray(prefix: String) {
        let lower = prefix.lowercased()
        guard let first = lower.first else { return }
        let firstStr = String(first)
        db.collection("users")
            .whereField("search_prefix", arrayContains: firstStr)
            .limit(to: 50)
            .getDocuments { snap, _ in
                let fallbackUsers: [GamerLnd.UserLite] = (snap?.documents ?? []).compactMap { d in
                    let data = d.data()
                    let id = (data["id"] as? String) ?? d.documentID
                    let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                    let displayName = data["display_name"] as? String
                    return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String, isTrustedGamer: (data["is_trusted_gamer"] as? Bool) ?? false)
                }
                let filtered = fallbackUsers.filter { u in
                    let hay = ((u.displayName ?? u.username)).lowercased()
                    let handle = u.username.lowercased()
                    return hay.contains(lower) || handle.contains(lower)
                }
                self.mergeUsersAndApply(filtered)
            }
    }

    private func queryUsersByDisplayNameLegacy(prefix: String, token: String) {
        let lower = prefix.lowercased()
        let tokenLower = token.lowercased()
        let ref: Query = db.collection("users")
            .order(by: "display_name")
            .start(at: [tokenLower])
            .end(at: [tokenLower + "\u{f8ff}"])
            .limit(to: pageSize)

        ref.getDocuments { snap, _ in
            let newUsers: [GamerLnd.UserLite] = (snap?.documents ?? []).compactMap { d in
                let data = d.data()
                let id = (data["id"] as? String) ?? d.documentID
                let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                let displayName = data["display_name"] as? String
                return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String, isTrustedGamer: (data["is_trusted_gamer"] as? Bool) ?? false)
            }
            self.mergeUsersAndApply(newUsers)
            if self.userResults.isEmpty && lower.count >= 2 {
                let two = String(lower.prefix(2))
                let broad: Query = self.db.collection("users")
                    .order(by: "display_name")
                    .start(at: [two])
                    .end(at: [two + "\u{f8ff}"])
                    .limit(to: 50)
                broad.getDocuments { snap2, _ in
                    let fallbackUsers: [GamerLnd.UserLite] = (snap2?.documents ?? []).compactMap { d in
                        let data = d.data()
                        let id = (data["id"] as? String) ?? d.documentID
                        let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                        let displayName = data["display_name"] as? String
                        return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String, isTrustedGamer: (data["is_trusted_gamer"] as? Bool) ?? false)
                    }
                    let filtered = fallbackUsers.filter { u in
                        let hay = ((u.displayName ?? u.username)).lowercased()
                        return hay.contains(lower)
                    }
                    self.mergeUsersAndApply(filtered)
                }
            }
        }
    }

    private func queryUsersFallback(prefix: String, reset: Bool) {
        var ref: Query = db.collection("users")
            .order(by: "username")
            .start(at: [prefix])
            .end(at: [prefix + "\u{f8ff}"])
            .limit(to: pageSize)

        if let last = lastUserDoc { ref = ref.start(afterDocument: last) }

        ref.getDocuments { snap, err in
            self.userLoading = false
            if let err = err {
                self.userError = err.localizedDescription
                self.toast = Toast(kind: .error, message: "Search failed: \(err.localizedDescription)")
                return
            }
            self.lastUserDoc = snap?.documents.last
            let newUsers: [GamerLnd.UserLite] = (snap?.documents ?? []).compactMap { d in
                let data = d.data()
                let id = (data["id"] as? String) ?? d.documentID
                let uname = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
                let displayName = data["display_name"] as? String
                return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String, isTrustedGamer: (data["is_trusted_gamer"] as? Bool) ?? false)
            }
            mergeUsersAndApply(newUsers)
        }
    }

    private func mergeUsersAndApply(_ newUsers: [GamerLnd.UserLite]) {
        var merged = self.userResults
        for u in newUsers {
            if let idx = merged.firstIndex(where: { $0.id == u.id }) {
                merged[idx] = u
            } else {
                merged.append(u)
            }
        }
        self.userResults = merged
        self.canLoadMoreUsers = (newUsers.count >= self.pageSize)

        for u in newUsers {
            if self.followersCount[u.id] == nil { self.fetchFollowersCount(for: u.id) }
            if self.logsCount[u.id] == nil || self.reviewsCount[u.id] == nil { self.fetchLogAndReviewCounts(for: u.id) }
            if self.lastActivity[u.id] == nil { self.fetchLastActivity(for: u.id) }
            if self.followingState[u.id] == nil { self.fetchFollowingState(for: u.id) }
            if self.creatorLinksByUserId[u.id] == nil { self.fetchCreatorLinks(for: u.id) }
        }
        self.applyUserFiltersAndSort()
    }

    private func loadMoreUsers() { guard !userLoading, canLoadMoreUsers else { return }; performSearch(reset: false, userInitiated: false) }

    private func clearSearch() {
        debounceTask?.cancel()
        query = ""
        if mode == .games {
            gameResults = []; gameError = ""; gameLoading = false
            canLoadMoreGames = false; nextGameOffset = 0; visibleGameCount = 20
        } else {
            userResults = []; userError = ""; userLoading = false
            canLoadMoreUsers = false; lastUserDoc = nil
        }
    }

    private func openSearchReport(for game: Game, resultIndex: Int) {
        dismissKeyboard()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        selectedSearchReportReason = .notRelevant
        searchReportNotes = ""
        activeSearchReport = SearchReportDraft(
            context: SearchResultReportContext(
                query: trimmedQuery,
                gameId: game.id,
                gameName: game.name,
                resultIndex: resultIndex,
                surface: "explore_games"
            )
        )
    }

    private func dismissSearchReportOverlay() {
        searchReportNotesFocused = false
        activeSearchReport = nil
        selectedSearchReportReason = .notRelevant
        searchReportNotes = ""
        isSubmittingSearchReport = false
        searchReportKeyboardHeight = 0
    }

    private func submitSearchReport(_ context: SearchResultReportContext) {
        guard !isSubmittingSearchReport else { return }
        isSubmittingSearchReport = true
        SearchReportService.submit(
            context: context,
            reason: selectedSearchReportReason,
            notes: searchReportNotes
        ) { result in
            DispatchQueue.main.async {
                self.isSubmittingSearchReport = false
                switch result {
                case .success:
                    self.dismissSearchReportOverlay()
                    self.toast = Toast(kind: .success, message: "Thanks — this helps improve search.")
                case .failure(let error):
                    self.toast = Toast(kind: .error, message: "Could not send report: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Game metrics

    private func fetchGamerLndAverage(for gameId: Int) {
        GamerLndScoreService.shared.fetchAverage(gameId: gameId) { avg, count in
            DispatchQueue.main.async {
                self.gamerLndAvg[gameId] = avg
                self.gamerLndCount[gameId] = count
            }
        }
    }

    private func fetchReviewCount(for gameId: Int) {
        db.collection("game_logs")
            .whereField("game_id", isEqualTo: gameId)
            .limit(to: 500)
            .getDocuments { snap, _ in
                let count = (snap?.documents ?? []).reduce(0) { acc, d in
                    if let t = d.data()["review"] as? String,
                       !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return acc + 1
                    }
                    return acc
                }
                DispatchQueue.main.async {
                    self.reviewCountCache[gameId] = count
                }
            }
    }

    // MARK: - User metrics

    private func fetchFollowersCount(for userId: String) {
        db.collection("follows")
            .whereField("followed_id", isEqualTo: userId)
            .getDocuments { snap, _ in
                DispatchQueue.main.async {
                    self.followersCount[userId] = snap?.documents.count ?? 0
                }
            }
    }

    private func fetchLogAndReviewCounts(for userId: String) {
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: userId)
            .limit(to: 1000)
            .getDocuments { snap, _ in
                let docs = snap?.documents ?? []
                let logs = docs.count
                let reviews = docs.reduce(0) { acc, d in
                    if let t = d.data()["review"] as? String,
                       !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return acc + 1 }
                    return acc
                }
                DispatchQueue.main.async {
                    self.logsCount[userId] = logs
                    self.reviewsCount[userId] = reviews
                }
            }
    }

    private func fetchLastActivity(for userId: String) {
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: userId)
            .order(by: "play_date", descending: true)
            .limit(to: 1)
            .getDocuments { snap, _ in
                let last = (snap?.documents.first?["play_date"] as? Timestamp)?.dateValue()
                DispatchQueue.main.async {
                    self.lastActivity[userId] = last
                }
            }
    }

    private func fetchFollowingState(for userId: String) {
        InteractionService.shared.isFollowing(targetUserId: userId) { state in
            DispatchQueue.main.async {
                self.followingState[userId] = state
            }
        }
    }

    // MARK: - Users filter/sort

    private func applyUserFiltersAndSort() {
        var list = userResults
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = raw.hasPrefix("@") ? String(raw.dropFirst()).lowercased() : raw.lowercased()

        if !q.isEmpty {
            list = list.filter { u in
                let uname = u.username.lowercased()
                let dname = (u.displayName ?? "").lowercased()
                return uname.contains(q) || dname.contains(q)
            }
        }

        if filterHasAvatar {
            list = list.filter { ($0.avatarUrl ?? "").isEmpty == false }
        }
        if filterHasReviews {
            list = list.filter { (reviewsCount[$0.id] ?? 0) > 0 }
        }
        if filterTrustedGamer {
            list = list.filter { $0.isTrustedGamer }
        }

        switch selectedUserSort {
        case .relevance:
            if !q.isEmpty {
                list.sort { a, b in
                    let sa = relevanceScore(for: a, query: q)
                    let sb = relevanceScore(for: b, query: q)
                    if sa == sb {
                        return (followersCount[a.id] ?? 0) > (followersCount[b.id] ?? 0)
                    }
                    return sa > sb
                }
            }
        case .followers:
            list.sort { (followersCount[$0.id] ?? 0) > (followersCount[$1.id] ?? 0) }
        case .recent:
            list.sort { (lastActivity[$0.id] ?? .distantPast) > (lastActivity[$1.id] ?? .distantPast) }
        case .alpha:
            list.sort { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        }

        userResults = list
    }

    private func relevanceScore(for user: GamerLnd.UserLite, query q: String) -> Int {
        let handle = user.username.lowercased()
        let display = (user.displayName ?? "").lowercased()
        var score = 0

        if !display.isEmpty {
            if display == q { score = max(score, 120) }
            else if display.hasPrefix(q) { score = max(score, 95) }
            else if display.contains(q) { score = max(score, 70) }
        }
        if handle == q { score = max(score, 110) }
        else if handle.hasPrefix(q) { score = max(score, 90) }
        else if handle.contains(q) { score = max(score, 60) }

        score += min(20, (followersCount[user.id] ?? 0) / 50)
        return score
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func randomQuote() -> String {
        let games = [
            "Let's-a go!",
            "Kooloo-Limpah!",
            "No matter what, you keep findin’ somethin’ to fight for.",
            "Scanning... Just dust and echoes.",
            "There's so much more to discover before the world ends."
        ]
        let users = [
            "People linked by destiny will always find each other.",
            "It's dangerous to go alone...",
            "I see 'em up ahead! Let's rock and roll!",
            "My friends… with all of your strength… stand with me",
            "Poyo poyo!"
        ]
        return (mode == .games ? games : users).randomElement() ?? ""
    }
}

private struct TrendingGameCard: Identifiable {
    var id: Int { game.id }
    let game: Game
    let avgRating: Double
    let activity: Int
}

private struct GameSubmissionPayload {
    let gameName: String
    let platform: String
    let releaseYear: String
    let publisher: String
    let notes: String
}

private struct FeedbackPayload {
    let category: String
    let message: String
    let relatedGame: String
}

private struct GameSubmissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var gameName: String = ""
    @State private var platform: String = ""
    @State private var releaseYear: String = ""
    @State private var publisher: String = ""
    @State private var notes: String = ""
    let onSubmit: (GameSubmissionPayload) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Game") {
                    TextField("Game name", text: $gameName)
                    TextField("Platform", text: $platform)
                    TextField("Release year", text: $releaseYear)
                        .keyboardType(.numberPad)
                    TextField("Publisher", text: $publisher)
                }
                Section("Notes") {
                    TextField("Why should this game be added?", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle("Submit Game")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        onSubmit(GameSubmissionPayload(
                            gameName: gameName.trimmingCharacters(in: .whitespacesAndNewlines),
                            platform: platform.trimmingCharacters(in: .whitespacesAndNewlines),
                            releaseYear: releaseYear.trimmingCharacters(in: .whitespacesAndNewlines),
                            publisher: publisher.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        dismiss()
                    }
                    .disabled(gameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct FeedbackSubmissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category: String = "General"
    @State private var relatedGame: String = ""
    @State private var message: String = ""
    let onSubmit: (FeedbackPayload) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Type") {
                    Picker("Category", selection: $category) {
                        Text("General").tag("General")
                        Text("Bug").tag("Bug")
                        Text("Game Data").tag("Game Data")
                        Text("Feature Request").tag("Feature Request")
                    }
                    .pickerStyle(.menu)
                    TextField("Related game (optional)", text: $relatedGame)
                }
                Section("Message") {
                    TextField("Tell us what happened or what you'd like changed", text: $message, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("Send Feedback")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        onSubmit(FeedbackPayload(
                            category: category,
                            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                            relatedGame: relatedGame.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        dismiss()
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ExploreRecentLogRowCard: View {
    let log: GameLog
    let title: String
    let avg: Double?
    let count: Int
    var onAverageTap: (() -> Void)? = nil

    var body: some View {
        let userAccent = ColorTheme.ratingBandColor(for: log.rating ?? 0)
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke((log.rating ?? 0) > 0 ? userAccent.opacity(0.72) : ColorTheme.separator, lineWidth: 1))

            HStack(spacing: 10) {
                if let imgId = log.cover?.imageId {
                    GameCoverImage(id: imgId, preset: .custom(width: 96), cornerRadius: 10)
                        .frame(width: 96, height: 128)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ColorTheme.separator.opacity(0.25))
                        .frame(width: 96, height: 128)
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

                    if let rating = log.rating, rating > 0 {
                        ExploreRatingHeartText(
                            text: formatRatingValue(rating),
                            color: userAccent,
                            size: 40
                        )
                    }

                    Spacer(minLength: 2)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .overlay(alignment: .topTrailing) {
                if avg != nil, count > 0 {
                    Button {
                        onAverageTap?()
                    } label: {
                        AverageHeartBadge(value: avg ?? 0, size: 24)
                            .padding(.top, 10)
                            .padding(.leading, 10)
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 324, height: 150)
    }
}

private struct ExploreRatingHeartText: View {
    let text: String
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            PixelHeartIcon(
                color: color,
                size: size,
                perfectScore: ColorTheme.isPerfectScore(Double(text) ?? 0)
            )
            HeartValueText(text: text, size: size)
        }
    }
}

// MARK: - Compact GamerLnd Badge (local copy)

private struct CompactGamerLndBadge: View {
    let avg: Double?
    let count: Int
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            Group {
                if let avg = avg, count > 0 {
                    AverageHeartBadge(value: avg, size: 16)
                } else {
                    PixelHeartIcon(
                        color: ColorTheme.separator,
                        size: 16,
                        empty: true
                    )
                }
            }
            .padding(6)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil || (avg == nil || count == 0))
    }
}

// MARK: - Redacted shimmer

fileprivate extension View {
    func redactedShimmer() -> some View {
        modifier(ExploreShimmerModifier())
    }
}

private struct ExploreShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -200

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.22), .clear]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(20))
                .blendMode(.plusLighter)
                .mask(content)
                .offset(x: phase)
            )
            .onAppear {
                if phase <= -200 {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 200
                    }
                }
            }
    }
}
