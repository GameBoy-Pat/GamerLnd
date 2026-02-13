// SearchView.swift
// Game search with idle state, magnifying-glass action, LIVE (debounced) results,
// Sort & Filters, GamerLnd badge + review count, and a "Load more" option.
//
// THIS PASS:
// • Sort By: Relevance (default), Popularity (IGDB rating), GamerLnd Rating, Release (newest), Alphabetical.
// • Filters: Year, Genre (queried at search time), Platform (local quick filter).
// • Popularity uses IGDB "rating" internally; the heart display in rows is removed.
// • GamerLnd Rating sort uses GamerLndScoreService averages (fetched lazily and cached).
// • Each result row shows: GamerLnd Rating badge (or “Be the first to rate!”) and review count (or “Be the first to review this game”).
// • Idle/empty state shows ONE randomized italic quote each time SearchView appears.
// • Live search as you type with a 350ms debounce (no need to press return or the icon).
// • "Load more" button to request additional pages from IGDB.
// • ADDED: Analytics for typing + submit, subtle haptics on filter/sort taps.

import SwiftUI
import FirebaseFirestore

struct SearchView: View {
    // MARK: - Query / Results
    @State private var query: String = ""
    @State private var results: [Game] = []
    @State private var isLoading: Bool = false
    @State private var errorText: String = ""

    // Filters bound to UI
    @State private var selectedYear: String? = nil
    @State private var selectedGenre: String? = nil
    @State private var selectedPlatform: String? = nil

    // Sort mode
    enum SortMode: String, CaseIterable, Identifiable {
        case relevance = "Relevance"
        case popularity = "Popularity"
        case gamerlnd = "GamerLnd Rating"
        case releaseDesc = "Release (Newest)"
        case alpha = "Alphabetical"
        var id: String { rawValue }
    }
    @State private var sortMode: SortMode = .relevance

    // Live search debounce
    @State private var debounceTask: DispatchWorkItem?

    // Quotes / idle state
    private let idleQuotes: [String] = [
        "Let's-a go!",
        "Kooloo-Limpah!",
        "No matter what, you keep findin’ somethin’ to fight for.",
        "Scanning... Just dust and echoes.",
        "There's so much more to discover before the world ends."
    ]
    @State private var currentQuote: String = ""
    private var showIdle: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isLoading
        && results.isEmpty
        && errorText.isEmpty
    }

    // Data sources
    private let igdb = IGDBService()
    private let db = Firestore.firestore()

    // Filter data sources (simple demo lists; years & genres are driven by searches anyway)
    @State private var allYears: [String] = []
    @State private var allGenres: [String] = []
    private let commonPlatforms: [String] = [
        "PlayStation 5", "PlayStation 4", "Xbox Series X|S", "Xbox One",
        "Nintendo Switch", "PC (Microsoft Windows)", "iOS", "Android", "Mac"
    ]

    // Cache for GamerLnd averages and review counts
    @State private var gamerLndAvg: [Int: Double] = [:]
    @State private var gamerLndCount: [Int: Int] = [:]   // # of ratings
    @State private var reviewCountCache: [Int: Int] = [:] // # of non-empty reviews

    // Sheets / Menus
    @State private var showingFilters: Bool = false

    // Paging (client-side)
    private let pageSize: Int = 20
    @State private var nextOffset: Int = 0
    @State private var canLoadMore: Bool = false // becomes true if we got a "full page" last load

    var body: some View {
        VStack(spacing: 0) {
            // (Removed app icon per your latest ProfileView preference; keep search clean)

            // Search + Sort & Filters row
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        TextField("Search…", text: $query, onCommit: { performSearch(reset: true) })
                            .textInputAutocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                            .foregroundColor(ColorTheme.text)
                            .overlay(alignment: .trailing) {
                                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Button {
                                        Haptics.tap()
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

                    Button(action: {
                        Haptics.tap()
                        performSearch(reset: true)
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.headline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ColorTheme.accent)
                    .disabled(isLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Sort & Filters controls
                HStack(spacing: 10) {
                    Menu {
                        Picker("Sort By", selection: $sortMode) {
                            ForEach(SortMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortMode.rawValue)
                                .lineLimit(1)
                        }
                        .foregroundColor(ColorTheme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .onTapGesture { Haptics.tap() }

                    Button {
                        Haptics.tap()
                        showingFilters = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("Filters")
                        }
                        .foregroundColor(ColorTheme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    }

                    Spacer()
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
            .padding(.bottom, 8)

            // Active filter chips (appear when a filter is set)
            if selectedYear != nil || selectedGenre != nil || selectedPlatform != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let y = selectedYear {
                            chip("Year: \(y)") { selectedYear = nil; performSearch(reset: true) }
                        }
                        if let g = selectedGenre {
                            chip("Genre: \(g)") { selectedGenre = nil; performSearch(reset: true) }
                        }
                        if let p = selectedPlatform {
                            chip("Platform: \(p)") { selectedPlatform = nil; applyLocalFiltersAndSort() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            }

            // Results area
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if isLoading && results.isEmpty {
                            ProgressView().tint(ColorTheme.accent).padding(.top, 12)
                        }

                        if !errorText.isEmpty {
                            Text(errorText)
                                .foregroundColor(ColorTheme.highlight)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        ForEach(results, id: \.id) { game in
                            NavigationLink(
                                destination: GameDetailView(game: game)
                            ) {
                                resultRow(game)
                                    .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                // When sorting by GamerLnd, pull averages as rows come into view.
                                if gamerLndAvg[game.id] == nil {
                                    fetchGamerLndAverage(for: game.id)
                                }
                                if reviewCountCache[game.id] == nil {
                                    fetchReviewCount(for: game.id)
                                }
                                // Infinite-ish scroll: when last few appear and canLoadMore, load next page
                                if game.id == results.suffix(5).first?.id, canLoadMore, !isLoading {
                                    loadMore()
                                }
                            }
                        }

                        // Manual "Load more" button (always available when canLoadMore)
                        if canLoadMore {
                            Button {
                                Haptics.tap()
                                loadMore()
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

                        Spacer(minLength: 20)
                    }
                }

                // Idle overlay (centered)
                if showIdle {
                    VStack(spacing: 16) {
                        Text("Search for Games")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(ColorTheme.text)

                        if !currentQuote.isEmpty {
                            Text(currentQuote)
                                .italic() // italicized, no quotes
                                .font(.footnote)
                                .foregroundColor(ColorTheme.subtext)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) { EmptyView() }
        }
        .sheet(isPresented: $showingFilters) { FiltersSheet }
        .onAppear {
            currentQuote = idleQuotes.randomElement() ?? ""
            AnalyticsService.shared.screen("search_games")
        }
        .onChange(of: query) { _, newValue in
            debounceTask?.cancel()

            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

            // If cleared, reset state and do nothing
            if trimmed.isEmpty {
                clearSearch()
                return
            }

            // Light analytics for typing (debounced below as well)
            AnalyticsService.shared.trackSearchTyping(query: newValue)

            // Start a new debounced task (350ms)
            let task = DispatchWorkItem { performSearch(reset: true) }
            debounceTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
        }
        .onChange(of: sortMode) { _, _ in
            Haptics.tap()
            applyLocalFiltersAndSort()
        }
        .onChange(of: selectedPlatform) { _, _ in
            applyLocalFiltersAndSort()
        }
    }

    // MARK: - Filters Sheet

    private var FiltersSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Year")) {
                    Picker("Year", selection: Binding(
                        get: { selectedYear ?? "" },
                        set: { selectedYear = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Any").tag("")
                        // If you have allYears populated from IGDBService.fetchFilterOptions, show it:
                        ForEach((allYears.isEmpty ? suggestedYears() : allYears), id: \.self) { y in
                            Text(y).tag(y)
                        }
                    }
                }

                Section(header: Text("Genre")) {
                    Picker("Genre", selection: Binding(
                        get: { selectedGenre ?? "" },
                        set: { selectedGenre = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Any").tag("")
                        ForEach((allGenres.isEmpty ? suggestedGenres() : allGenres), id: \.self) { g in
                            Text(g).tag(g)
                        }
                    }
                }

                Section(header: Text("Platform")) {
                    Picker("Platform", selection: Binding(
                        get: { selectedPlatform ?? "" },
                        set: { selectedPlatform = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Any").tag("")
                        ForEach(commonPlatforms, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }
                }
            }
            .navigationBarTitle("Filters", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        Haptics.tap()
                        selectedYear = nil
                        selectedGenre = nil
                        selectedPlatform = nil
                        applyLocalFiltersAndSort()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Haptics.tap()
                        showingFilters = false
                        performSearch(reset: true) // year/genre affect the server query
                    }
                }
            }
        }
        .preferredColorScheme(ColorTheme.preferredScheme)
    }

    private func suggestedYears() -> [String] {
        let y = Calendar.current.component(.year, from: Date())
        return (2000...y).reversed().map { "\($0)" }
    }

    private func suggestedGenres() -> [String] {
        [
            "Action", "Adventure", "RPG", "Shooter", "Strategy",
            "Puzzle", "Racing", "Platform", "Sports", "Simulation"
        ]
    }

    // MARK: - Row

    private func resultRow(_ game: Game) -> some View {
        let corner: CGFloat = uiCorner
        let reviewCount = reviewCountCache[game.id] ?? 0
        let ratingAvg = gamerLndAvg[game.id]
        let ratingCnt = gamerLndCount[game.id] ?? 0

        return HStack(alignment: .top, spacing: 12) {
            if let imgId = game.cover?.imageId ?? game.screenshots?.first?.imageId {
                GameCoverImage(id: imgId, preset: .custom(width: 120), cornerRadius: corner)
                    .frame(width: 120, height: 160)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: corner)
                    .fill(ColorTheme.separator.opacity(0.2))
                    .frame(width: 120, height: 160)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(game.name)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)

                if let year = game.computedReleaseYear {
                    // ensure no commas (just in case of a bad formatter elsewhere)
                    Text("\(year)")
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

                // Review count line
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

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 8) // spacing from badge at bottom-right
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorTheme.separator, lineWidth: 1)
        )
        // Bottom-right GamerLnd badge
        .overlay(alignment: .bottomTrailing) {
            gamerLndBadge(avg: ratingAvg, count: ratingCnt)
                .padding(10)
        }
        .onAppear {
            if gamerLndAvg[game.id] == nil { fetchGamerLndAverage(for: game.id) }
            if reviewCountCache[game.id] == nil { fetchReviewCount(for: game.id) }
        }
    }

    private func gamerLndBadge(avg: Double?, count: Int) -> some View {
        Group {
            if let avg = avg, count > 0 {
                HStack(spacing: 8) {
                    Text("GamerLnd Rating")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                    Image(systemName: "heart.fill")
                        .foregroundColor(ColorTheme.highlight)
                    Text(String(format: "%.1f", avg))
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(ColorTheme.highlight)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
            } else {
                HStack(spacing: 8) {
                    Text("GamerLnd Rating")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                    Text("Be the first to rate!")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
            }
        }
    }

    // MARK: - Actions

    private func performSearch(reset: Bool) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        // (Optional) require at least 2 characters before searching to cut noise
        guard q.count >= 2 else {
            results = []
            errorText = ""
            isLoading = false
            canLoadMore = false
            nextOffset = 0
            return
        }

        // If a debounced task is still pending, cancel it—this is the actual run
        debounceTask?.cancel()
        debounceTask = nil

        if reset {
            nextOffset = 0
            results = []
            canLoadMore = false
        }

        errorText = ""
        isLoading = true

        igdb.searchGamesPaged(
            query: q,
            year: selectedYear,
            genre: selectedGenre,
            limit: pageSize,
            offset: nextOffset
        ) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let games):
                    // Track submit once per actual fetch (not on every keypress)
                    AnalyticsService.shared.trackSearchSubmitted(query: q, resultsCount: games.count)

                    // Local platform filter
                    var incoming = games
                    if let platform = selectedPlatform, !platform.isEmpty {
                        incoming = games.filter { g in
                            (g.platforms ?? []).contains(where: { $0.name == platform })
                        }
                    }

                    // Merge & de-dup by id
                    var merged = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
                    for g in incoming { merged[g.id] = g }
                    var newList = Array(merged.values)

                    // Sort locally
                    newList = applySort(to: newList)

                    results = newList

                    // Determine if there's likely another page
                    canLoadMore = (games.count >= pageSize)
                    if canLoadMore { nextOffset += pageSize }

                    // Prime caches
                    if sortMode == .gamerlnd { primeGamerLndAverages(for: incoming) }
                    for g in incoming {
                        if reviewCountCache[g.id] == nil { fetchReviewCount(for: g.id) }
                    }
                case .failure(let err):
                    errorText = err.localizedDescription
                }
            }
        }
    }

    private func loadMore() {
        guard !isLoading, canLoadMore else { return }
        performSearch(reset: false)
    }

    private func applyLocalFiltersAndSort() {
        // Re-apply platform-only filtering to the current results, then sort.
        var filtered = results
        if let platform = selectedPlatform, !platform.isEmpty {
            filtered = filtered.filter { g in
                (g.platforms ?? []).contains(where: { $0.name == platform })
            }
        }
        results = applySort(to: filtered)
        if sortMode == .gamerlnd {
            primeGamerLndAverages(for: results)
        }
    }

    private func applySort(to list: [Game]) -> [Game] {
        switch sortMode {
        case .relevance:
            return stableByExistingOrder(list, existing: results)
        case .popularity:
            return list.sorted {
                let a = $0.rating ?? -1
                let b = $1.rating ?? -1
                if a == b {
                    let ac = $0.totalRatingCount ?? $0.ratingCount ?? 0
                    let bc = $1.totalRatingCount ?? $1.ratingCount ?? 0
                    return ac > bc
                }
                return a > b
            }
        case .gamerlnd:
            return list.sorted {
                let a = gamerLndAvg[$0.id]
                let b = gamerLndAvg[$1.id]
                switch (a, b) {
                case let (a?, b?):
                    if a == b {
                        return (gamerLndCount[$0.id] ?? 0) > (gamerLndCount[$1.id] ?? 0)
                    }
                    return a > b
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return ($0.rating ?? -1) > ($1.rating ?? -1)
                }
            }
        case .releaseDesc:
            return list.sorted {
                ($0.computedReleaseYear ?? 0) > ($1.computedReleaseYear ?? 0)
            }
        case .alpha:
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func stableByExistingOrder(_ list: [Game], existing: [Game]) -> [Game] {
        let indexMap: [Int: Int] = Dictionary(uniqueKeysWithValues: existing.enumerated().map { ($0.element.id, $0.offset) })
        return list.sorted {
            let a = indexMap[$0.id] ?? Int.max
            let b = indexMap[$1.id] ?? Int.max
            if a == b { return $0.id < $1.id }
            return a < b
        }
    }

    // MARK: - GamerLnd averages & review counts

    private func primeGamerLndAverages(for games: [Game]) {
        for g in games {
            if gamerLndAvg[g.id] == nil {
                fetchGamerLndAverage(for: g.id)
            }
        }
    }

    private func fetchGamerLndAverage(for gameId: Int) {
        GamerLndScoreService.shared.fetchAverage(gameId: gameId) { avg, count in
            DispatchQueue.main.async {
                gamerLndAvg[gameId] = avg
                gamerLndCount[gameId] = count
                // Re-apply sorting if we're currently sorting by GamerLnd
                if sortMode == .gamerlnd {
                    results = applySort(to: results)
                }
            }
        }
    }

    private func fetchReviewCount(for gameId: Int) {
        db.collection("game_logs")
            .whereField("game_id", isEqualTo: gameId)
            .limit(to: 500) // cap for cost; adjust as needed
            .getDocuments { snap, _ in
                let count = (snap?.documents ?? []).reduce(0) { acc, d in
                    if let t = d.data()["review"] as? String,
                       !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return acc + 1
                    }
                    return acc
                }
                DispatchQueue.main.async {
                    reviewCountCache[gameId] = count
                }
            }
    }

    // MARK: - Helpers

    private func chip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption.weight(.semibold))
            Button(action: {
                Haptics.tap()
                onRemove()
            }) {
                Image(systemName: "xmark.circle.fill").font(.caption)
            }
        }
        .foregroundColor(ColorTheme.accent)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private var uiCorner: CGFloat {
        #if canImport(UIKit)
        return UIStyles.Art.screenshotCorner
        #else
        return 10
        #endif
    }

    private func clearSearch() {
        debounceTask?.cancel()
        query = ""
        results = []
        errorText = ""
        isLoading = false
        canLoadMore = false
        nextOffset = 0
    }
}
