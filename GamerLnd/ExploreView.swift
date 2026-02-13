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
@preconcurrency import FirebaseFirestore
import FirebaseAuth

struct ExploreView: View {
    // MARK: - Mode
    enum Mode: String, CaseIterable, Identifiable { case games = "Games", users = "Users"; var id: String { rawValue } }

    // MARK: - UI
    @State private var mode: Mode = .games
    @State private var query: String = ""
    @State private var toast: Toast? = nil

    // MARK: - Games state
    @State private var gameResults: [Game] = []
    @State private var gameLoading: Bool = false
    @State private var gameError: String = ""
    @State private var gamerLndAvg: [Int: Double] = [:]
    @State private var gamerLndCount: [Int: Int] = [:]
    @State private var reviewCountCache: [Int: Int] = [:]
    @State private var nextGameOffset: Int = 0
    @State private var canLoadMoreGames: Bool = false

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

    // MARK: - Shared
    @State private var debounceTask: DispatchWorkItem?
    private let igdb = IGDBService()
    private let db = Firestore.firestore()
    private let pageSize = 20

    // Last searches (scoped per signed-in user)
    @State private var lastSearches: [String] = []
    private var lastSearchesKey: String {
        let uid = Auth.auth().currentUser?.uid ?? "anon"
        return "explore.lastSearches.\(uid)"
    }

    var body: some View {
        VStack(spacing: 0) {
            AppIconCentered()
                .padding(.top, 8)
                .padding(.bottom, 4)
            // HEADER ROW: Segmented picker at left; "Explore" perfectly centered.
            HStack {
                Picker("", selection: $mode) {
                    Image(systemName: "gamecontroller.fill").tag(Mode.games)
                    Image(systemName: "person.2.fill").tag(Mode.users)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140) // a touch wider for easier taps
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

            // SEARCH + FILTERS ROW (stays underneath header row)
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        TextField("Search \(mode.rawValue.lowercased())…", text: $query, onCommit: { performSearch(reset: true) })
                            .textInputAutocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.webSearch)
                            .submitLabel(.search)
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

                    // Filters Menu (NO mode picker here)
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
                                        Text("\(y)").tag(y)
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
                                Button("Reset filters") {
                                    filterHasReviews = false
                                    filterHasAvatar = false
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
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
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

            // Last searches row (tap to reuse)
            if lastSearches.isEmpty == false && query.isEmpty {
                Text("Recent searches")
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(lastSearches, id: \.self) { s in
                            Button {
                                query = s
                                performSearch(reset: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                    Text(s)
                                }
                                .font(.caption)
                                .foregroundColor(ColorTheme.accent)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                            }
                        }
                        Button(role: .destructive) {
                            lastSearches = []
                            UserDefaults.standard.set([], forKey: lastSearchesKey)
                            Haptics.select()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Clear recent")
                            }
                            .font(.caption)
                            .foregroundColor(ColorTheme.highlight)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            }

            // Results
            ZStack {
                if mode == .games { gamesList } else { usersList }
                if showIdle { idleOverlay }
            }
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .overlay {
            if showSaveOverlay { saveConfirmOverlay }
        }
        .navigationTitle("")
        .toolbar {
            // Keep nav bar clear; header/picker handled in content.
            ToolbarItem(placement: .principal) { EmptyView() }
        }
        .toast($toast)
        .onAppear {
            AnalyticsService.shared.screen("Explore")
            // Privacy hardening: old shared key should not be used across accounts.
            UserDefaults.standard.removeObject(forKey: "explore.lastSearches")
            lastSearches = (UserDefaults.standard.array(forKey: lastSearchesKey) as? [String]) ?? []
            loadSavedGames()
        }
        .onChange(of: mode) { _, _ in
            Haptics.select()
            if !query.isEmpty { performSearch(reset: true) }
        }
        .onChange(of: query) { _, newValue in
            debounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                clearSearch()
                return
            }
            let task = DispatchWorkItem { performSearch(reset: true) }
            debounceTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
        }
        .onChange(of: selectedGameSort) { _, _ in applyGameSortAndFilters() }
        .onChange(of: selectedYear) { _, _ in applyGameSortAndFilters() }
        .onChange(of: selectedGenre) { _, _ in applyGameSortAndFilters() }
        .onChange(of: selectedPlatform) { _, _ in applyGameSortAndFilters() }
        .onChange(of: selectedUserSort) { _, _ in applyUserFiltersAndSort() }
        .onChange(of: filterHasReviews) { _, _ in applyUserFiltersAndSort() }
        .onChange(of: filterHasAvatar) { _, _ in applyUserFiltersAndSort() }
        .onReceive(NotificationCenter.default.publisher(for: .gamerLndRatingUpdated)) { note in
            guard let gid = note.userInfo?["game_id"] as? Int else { return }
            GamerLndScoreService.shared.fetchAverage(gameId: gid) { avg, count in
                DispatchQueue.main.async {
                    self.gamerLndAvg[gid] = avg
                    self.gamerLndCount[gid] = count
                }
            }
        }
    }

    // MARK: - UI Pieces

    private var idleOverlay: some View {
        VStack(spacing: 16) {
            Text("Search for \(mode.rawValue)")
                .font(.title3.weight(.semibold))
                .foregroundColor(ColorTheme.text)
            Text(randomQuote())
                .italic()
                .font(.footnote)
                .foregroundColor(ColorTheme.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var saveConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    showSaveOverlay = false
                    pendingSaveGame = nil
                }

            if let game = pendingSaveGame {
                let isSaved = savedGameIds.contains(game.id)
                VStack(spacing: 12) {
                    Text("Save Game")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(ColorTheme.text)

                    if let cover = game.cover?.imageId {
                        GameCoverImage(id: cover, preset: .custom(width: 90), cornerRadius: 10)
                            .frame(width: 90, height: 120)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ColorTheme.separator.opacity(0.2))
                            .frame(width: 90, height: 120)
                    }

                    Text(game.name)
                        .foregroundColor(ColorTheme.text)
                        .font(.headline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Button {
                            showSaveOverlay = false
                            pendingSaveGame = nil
                        } label: {
                            Text("Cancel")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ColorTheme.subtext)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            if !isSaved { toggleSavedGame(game) }
                            // Keep context visible; button flips to disabled "Saved".
                        } label: {
                            Text(isSaved ? "Saved" : "Save Game")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(isSaved ? ColorTheme.subtext : ColorTheme.accent)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaved)
                    }
                }
                .padding(16)
                .frame(width: 320)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(ColorTheme.black.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ColorTheme.separator.opacity(0.6), lineWidth: 1))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var showIdle: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (mode == .games ? gameResults.isEmpty && !gameLoading : userResults.isEmpty && !userLoading)
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

                ForEach(gameResults, id: \.id) { game in
                    NavigationLink(destination: GameDetailView(game: game)) {
                        gameRow(game)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if gamerLndAvg[game.id] == nil { fetchGamerLndAverage(for: game.id) }
                        if reviewCountCache[game.id] == nil { fetchReviewCount(for: game.id) }
                        // Infinite-ish scroll
                        if game.id == gameResults.suffix(5).first?.id, canLoadMoreGames, !gameLoading {
                            loadMoreGames()
                        }
                    }
                }

                if canLoadMoreGames {
                    Button {
                        loadMoreGames()
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
            if !query.isEmpty { performSearch(reset: true) }
        }
        .padding(.bottom, 80)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
    }

    private func gameRow(_ game: Game) -> some View {
        let avg = gamerLndAvg[game.id]
        let count = gamerLndCount[game.id] ?? 0
        let reviewCount = reviewCountCache[game.id] ?? 0
        let isSaved = savedGameIds.contains(game.id)

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))

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
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)

                    if let y = game.computedReleaseYear {
                        Text(String(y))
                            .font(.caption)
                            .foregroundColor(ColorTheme.subtext)
                    }

                    if let plats = game.platforms?.map({ $0.name }).prefix(4), !plats.isEmpty {
                        Text(plats.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(1)
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
                    CompactGamerLndBadge(avg: avg, count: count)
                }

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    NavigationLink(destination: GameDetailView(game: game)) {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .font(.title3.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.accent))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
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
                    .onAppear {
                        if followersCount[user.id] == nil { fetchFollowersCount(for: user.id) }
                        if logsCount[user.id] == nil || reviewsCount[user.id] == nil { fetchLogAndReviewCounts(for: user.id) }
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
            if !query.isEmpty { performSearch(reset: true) }
        }
    }

    private func userRow(_ user: GamerLnd.UserLite) -> some View {
        let fCount = followersCount[user.id] ?? 0
        let lCount = logsCount[user.id] ?? 0
        let rCount = reviewsCount[user.id] ?? 0
        let last = lastActivity[user.id]
        let isFollowing = followingState[user.id] ?? false
        let isMe = (user.id == Auth.auth().currentUser?.uid)

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))

            HStack(spacing: 12) {
                AvatarView(name: user.displayName ?? user.username, size: 54, avatarURL: user.avatarUrl)
                    .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName ?? user.username)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(1)
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)

                    HStack(spacing: 10) {
                        HStack(spacing: 4) { Image(systemName: "person.2"); Text("\(fCount)") }
                        HStack(spacing: 4) { Image(systemName: "square.and.pencil"); Text("\(lCount)") }
                        HStack(spacing: 4) { Image(systemName: "text.bubble"); Text("\(rCount)") }
                    }
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)

                    if let last = last {
                        Text("Active \(relativeDate(last))")
                            .font(.caption2)
                            .foregroundColor(ColorTheme.subtext)
                    }
                }

                Spacer(minLength: 0)

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
            .padding(10)
        }
        .frame(height: 90)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(
            NavigationLink(destination: ProfileView(userId: user.id)) { EmptyView() }
                .opacity(0)
        )
    }

    // MARK: - Saved Games (Search)

    private func loadSavedGames() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).getDocument { snap, _ in
            let list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            let ids = list.compactMap { $0["id"] as? Int }
            savedGameIds = Set(ids)
        }
    }

    private func toggleSavedGame(_ game: Game) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let doc = db.collection("users").document(uid)
        doc.getDocument { snap, _ in
            var list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            if let idx = list.firstIndex(where: { ($0["id"] as? Int) == game.id }) {
                list.remove(at: idx)
                savedGameIds.remove(game.id)
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
                savedGameIds.insert(game.id)
            }
            doc.setData(["watchlist_games": list], merge: true)
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

    private func performSearch(reset: Bool) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = q.hasPrefix("@") ? String(q.dropFirst()) : q
        guard !q.isEmpty else { return }
        debounceTask?.cancel(); debounceTask = nil

        // Save to last searches
        var recents = (UserDefaults.standard.array(forKey: lastSearchesKey) as? [String]) ?? []
        if let idx = recents.firstIndex(of: q) { recents.remove(at: idx) }
        recents.insert(q, at: 0)
        if recents.count > 10 { recents.removeLast(recents.count - 10) }
        lastSearches = recents
        UserDefaults.standard.set(recents, forKey: lastSearchesKey)

        AnalyticsService.shared.trackSearchSubmitted(query: q, resultsCount: 0) // count updated after fetch

        switch mode {
        case .games:
            if reset {
                gameResults = []; canLoadMoreGames = false; nextGameOffset = 0
            }
            gameError = ""; gameLoading = true

            // Use your existing IGDBService signature (no order args). Sort/filter locally below.
            igdb.searchGamesPaged(query: q, year: nil, genre: nil, limit: pageSize, offset: nextGameOffset) { result in
                DispatchQueue.main.async {
                    self.gameLoading = false
                    switch result {
                    case .success(let games):
                        var merged = Dictionary(uniqueKeysWithValues: self.gameResults.map { ($0.id, $0) })
                        for g in games { merged[g.id] = g }
                        self.gameResults = Array(merged.values)
                        self.canLoadMoreGames = (games.count >= self.pageSize)
                        if self.canLoadMoreGames { self.nextGameOffset += self.pageSize }

                        // Prime caches
                        for g in games {
                            if self.gamerLndAvg[g.id] == nil { self.fetchGamerLndAverage(for: g.id) }
                            if self.reviewCountCache[g.id] == nil { self.fetchReviewCount(for: g.id) }
                        }

                        // Apply local filters/sort now
                        self.applyGameSortAndFilters()

                        // Update analytics with actual count
                        AnalyticsService.shared.trackSearchSubmitted(query: q, resultsCount: self.gameResults.count)
                    case .failure(let err):
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

    private func loadMoreGames() {
        guard !gameLoading, canLoadMoreGames else { return }
        performSearch(reset: false)
    }

    // Local filter + sort for games
    private func applyGameSortAndFilters() {
        var list = gameResults

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
            // keep IGDB returned order
            break
        case .popularity:
            list.sort {
                let a = $0.totalRatingCount ?? $0.ratingCount ?? 0
                let b = $1.totalRatingCount ?? $1.ratingCount ?? 0
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
                return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String)
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
        var ref: Query = db.collection("users")
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
                return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String)
            }
            self.mergeUsersAndApply(newUsers)
            // If no results, fallback: broaden by first 2 letters and filter locally
            if self.userResults.isEmpty && lower.count >= 2 {
                let two = String(lower.prefix(2))
                var broad: Query = self.db.collection("users")
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
                        return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String)
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
                    return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String)
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
        var ref: Query = db.collection("users")
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
                return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String)
            }
            self.mergeUsersAndApply(newUsers)
            if self.userResults.isEmpty && lower.count >= 2 {
                let two = String(lower.prefix(2))
                var broad: Query = self.db.collection("users")
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
                        return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String)
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
                return GamerLnd.UserLite(id: id, username: uname, displayName: displayName, avatarUrl: data["avatar_url"] as? String)
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
        }
        self.applyUserFiltersAndSort()
    }

    private func loadMoreUsers() { guard !userLoading, canLoadMoreUsers else { return }; performSearch(reset: false) }

    private func clearSearch() {
        debounceTask?.cancel()
        query = ""
        if mode == .games {
            gameResults = []; gameError = ""; gameLoading = false
            canLoadMoreGames = false; nextGameOffset = 0
        } else {
            userResults = []; userError = ""; userLoading = false
            canLoadMoreUsers = false; lastUserDoc = nil
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

// MARK: - Compact GamerLnd Badge (local copy)

private struct CompactGamerLndBadge: View {
    let avg: Double?
    let count: Int
    var body: some View {
        Group {
            if let avg = avg, count > 0 {
                HStack(spacing: 6) {
                    Text("GamerLnd Rating")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
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
                    Text("GamerLnd Rating")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
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

// MARK: - Redacted shimmer

fileprivate extension View {
    func redactedShimmer() -> some View {
        self
            .redacted(reason: .placeholder)
            .overlay(
                LinearGradient(gradient: Gradient(colors: [
                    .clear, .white.opacity(0.22), .clear
                ]), startPoint: .leading, endPoint: .trailing)
                .rotationEffect(.degrees(20))
                .blendMode(.plusLighter)
                .mask(self)
                .offset(x: -200)
                .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: UUID())
            )
    }
}
