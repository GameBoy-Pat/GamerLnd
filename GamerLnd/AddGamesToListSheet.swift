import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct AddGamesToListSheet: View {
    let listId: String
    let ownerId: String
    var onClose: (() -> Void)? = nil
    var onAdded: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private enum SourceTab: String, CaseIterable, Identifiable {
        case search = "Search"
        case saved = "Saved Games"
        var id: String { rawValue }
    }

    private enum GameSort: String, CaseIterable, Identifiable {
        case relevance = "Relevance"
        case popularity = "Popularity"
        case glRating = "GamerLnd Rating"
        case newest = "Release (Newest)"
        case alpha = "Alphabetical"
        var id: String { rawValue }
    }

    @State private var selectedSourceTab: SourceTab = .search
    @State private var query: String = ""
    @State private var rawResults: [Game] = []
    @State private var results: [Game] = []
    @State private var isLoading: Bool = false
    @State private var errorText: String = ""
    @State private var debounceWork: DispatchWorkItem?

    @State private var selectedSort: GameSort = .relevance
    @State private var selectedYear: Int? = nil
    @State private var selectedGenre: String? = nil
    @State private var selectedPlatform: String? = nil

    @State private var existingGameIds: Set<Int> = []
    @State private var addedGameIds: Set<Int> = []
    @State private var addingGameIds: Set<Int> = []
    @State private var savedGames: [SavedGameEntry] = []
    @State private var gamerLndAvg: [Int: Double] = [:]
    @State private var gamerLndCount: [Int: Int] = [:]
    @FocusState private var searchFocused: Bool
    @State private var activeSearchReport: SearchResultReportContext? = nil
    @State private var selectedSearchReportReason: SearchReportReason = .notRelevant
    @State private var searchReportNotes: String = ""
    @State private var isSubmittingSearchReport: Bool = false
    @FocusState private var searchReportNotesFocused: Bool
    @State private var searchReportKeyboardHeight: CGFloat = 0
    @State private var previewGame: Game? = nil
    @State private var previewShowsPlatforms: Bool = false

    private struct SavedGameEntry: Identifiable {
        let id: Int
        let name: String
        let coverId: String?
        let addedAt: Date?
    }

    private let db = Firestore.firestore()
    private let igdb = IGDBService()

    var body: some View {
        VStack(spacing: 0) {
            header
            sourceTabs

            if selectedSourceTab == .search {
                controls

                if isLoading {
                    ProgressView().tint(ColorTheme.accent).padding(.top, 18)
                }
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(ColorTheme.highlight)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    if selectedSourceTab == .search {
                        if !isLoading && results.isEmpty {
                            Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Search for games to add to this list." : "No games found.")
                                .font(.footnote)
                                .foregroundColor(ColorTheme.subtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                        }

                        ForEach(Array(results.enumerated()), id: \.element.id) { entry in
                            resultRow(entry.element, resultIndex: entry.offset)
                        }
                    } else {
                        if savedGames.isEmpty {
                            Text("No saved games yet.")
                                .font(.footnote)
                                .foregroundColor(ColorTheme.subtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                        }

                        ForEach(savedGames) { entry in
                            savedGameRow(entry)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(ColorTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ColorTheme.separator, lineWidth: 1)
        )
        .preferredColorScheme(ColorTheme.preferredScheme)
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
                    searchFocused = false
                    searchReportNotesFocused = false
                }
            }
        }
        .onAppear {
            loadExistingGameIds()
            loadSavedGames()
        }
        .onChange(of: selectedSort) { _, _ in applyGameSortAndFilters() }
        .onChange(of: selectedYear) { _, _ in applyGameSortAndFilters() }
        .onChange(of: selectedGenre) { _, _ in applyGameSortAndFilters() }
        .onChange(of: selectedPlatform) { _, _ in applyGameSortAndFilters() }
        .overlay {
            if let context = activeSearchReport {
                searchReportOverlay(context: context)
            } else if let game = previewGame {
                gamePreviewOverlay(game)
            }
        }
    }

    private var sourceTabs: some View {
        HStack(spacing: 8) {
            ForEach(SourceTab.allCases) { tab in
                let isSelected = selectedSourceTab == tab
                Button {
                    guard selectedSourceTab != tab else { return }
                    Haptics.select()
                    searchFocused = false
                    selectedSourceTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isSelected ? .black : ColorTheme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(isSelected ? ColorTheme.accent : ColorTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(isSelected ? ColorTheme.accent : ColorTheme.separator, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Add Games")
                .font(.headline.weight(.bold))
                .foregroundColor(ColorTheme.text)
            Spacer()
            Button {
                close()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    TextField("Search games…", text: $query, onCommit: { performSearch(userInitiated: true) })
                        .textInputAutocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.webSearch)
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                        .foregroundColor(ColorTheme.text)
                        .overlay(alignment: .trailing) {
                            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    query = ""
                                    rawResults = []
                                    results = []
                                    errorText = ""
                                    searchFocused = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(ColorTheme.subtext)
                                        .font(.system(size: 16, weight: .semibold))
                                        .padding(.trailing, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onChange(of: query, initial: false) { _, _ in debounceSearch() }
                }
                Button {
                    Haptics.tap()
                    performSearch(userInitiated: true)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(ColorTheme.accent))
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
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
        .padding(.bottom, 6)
    }

    private var filtersButton: some View {
        Menu {
            Section("Sort") {
                Picker("Sort games", selection: $selectedSort) {
                    ForEach(GameSort.allCases) { s in Text(s.rawValue).tag(s) }
                }
            }
            Section("Filters") {
                Picker("Year", selection: Binding(
                    get: { selectedYear ?? -1 },
                    set: { selectedYear = ($0 == -1 ? nil : $0) }
                )) {
                    Text("Any year").tag(-1)
                    ForEach((1980...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                        Text("\(year)").tag(year)
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
                    selectedYear = nil
                    selectedGenre = nil
                    selectedPlatform = nil
                    selectedSort = .relevance
                    applyGameSortAndFilters()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
                Text("Filters")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(ColorTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.background))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
        }
    }

    private func resultRow(_ game: Game, resultIndex: Int) -> some View {
        let isAdding = addingGameIds.contains(game.id)
        return HStack(spacing: 12) {
            if let imgId = game.cover?.imageId {
                GameCoverImage(id: imgId, preset: .custom(width: 70), cornerRadius: 10)
                    .frame(width: 70, height: 93)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(ColorTheme.separator.opacity(0.2))
                    .frame(width: 70, height: 93)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .foregroundColor(ColorTheme.text)
                    .font(searchResultTitleFont(for: game.name))
                    .lineLimit(3)
                    .minimumScaleFactor(0.84)
                    .allowsTightening(true)

                HStack(spacing: 8) {
                    if let year = game.computedReleaseYear {
                        Text(String(year))
                            .foregroundColor(ColorTheme.subtext)
                            .font(.caption)
                    }
                    if let avg = gamerLndAvg[game.id], (gamerLndCount[game.id] ?? 0) > 0 {
                        HStack(spacing: 0) {
                            AverageHeartBadge(value: avg, size: 18)
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    openSearchReport(for: game, resultIndex: resultIndex)
                } label: {
                    Image(systemName: "flag")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(ColorTheme.surface.opacity(0.92)))
                        .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)

                if isAlreadyAdded(game.id) {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.highlight)
                } else if isAdding {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.black)
                        Text("Adding")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.accent))
                } else {
                    Button {
                        add(game: game)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            previewShowsPlatforms = false
            previewGame = game
        }
    }

    private func savedGameRow(_ entry: SavedGameEntry) -> some View {
        let isAdding = addingGameIds.contains(entry.id)
        return HStack(spacing: 12) {
            if let coverId = entry.coverId, !coverId.isEmpty {
                GameCoverImage(id: coverId, preset: .custom(width: 70), cornerRadius: 10)
                    .frame(width: 70, height: 93)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(ColorTheme.separator.opacity(0.2))
                    .frame(width: 70, height: 93)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name)
                    .foregroundColor(ColorTheme.text)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let addedAt = entry.addedAt {
                    Text("Saved " + savedDateFormatter.string(from: addedAt))
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                }
            }

            Spacer()

            if isAlreadyAdded(entry.id) {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.highlight)
            } else if isAdding {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.black)
                    Text("Adding")
                }
                .font(.caption.weight(.bold))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.accent))
            } else {
                Button {
                    addSavedGame(entry)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private var savedDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }

    private func addSavedGame(_ entry: SavedGameEntry) {
        guard !addingGameIds.contains(entry.id) else { return }
        addingGameIds.insert(entry.id)
        let item = UserListItem(
            id: UUID().uuidString,
            listId: listId,
            gameId: entry.id,
            gameName: entry.name,
            coverImageId: entry.coverId,
            addedAt: Date()
        )
        ListsService.shared.addItems(listId: listId, items: [item]) {
            DispatchQueue.main.async {
                self.addingGameIds.remove(entry.id)
                self.addedGameIds.insert(entry.id)
                self.existingGameIds.insert(entry.id)
                self.onAdded?()
            }
        }
    }

    private func performSearch(userInitiated: Bool = false) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            rawResults = []
            results = []
            return
        }
        if userInitiated {
            RewardService.shared.recordSearch(query: q)
        }
        isLoading = true
        errorText = ""
        igdb.searchGames(query: q, year: selectedYear.map(String.init), genre: selectedGenre) { res in
            DispatchQueue.main.async {
                self.isLoading = false
                switch res {
                case .failure(let err):
                    self.errorText = err.localizedDescription
                    self.rawResults = []
                    self.results = []
                case .success(let games):
                    self.rawResults = games
                    self.primeMetrics(for: games)
                    self.applyGameSortAndFilters()
                }
            }
        }
    }

    private func debounceSearch() {
        debounceWork?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            rawResults = []
            results = []
            return
        }
        let work = DispatchWorkItem { self.performSearch(userInitiated: false) }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func applyGameSortAndFilters() {
        var list = rawResults

        if let year = selectedYear {
            list = list.filter { $0.computedReleaseYear == year }
        }
        if let genre = selectedGenre?.lowercased(), !genre.isEmpty {
            list = list.filter { game in
                (game.genres ?? []).contains { $0.name.lowercased().contains(genre) }
            }
        }
        if let platform = selectedPlatform?.lowercased(), !platform.isEmpty {
            list = list.filter { game in
                (game.platforms ?? []).contains { $0.name.lowercased().contains(platform) }
            }
        }

        switch selectedSort {
        case .relevance:
            break
        case .popularity:
            list.sort { lhs, rhs in
                let l = max(lhs.totalRatingCount ?? 0, lhs.ratingCount ?? 0)
                let r = max(rhs.totalRatingCount ?? 0, rhs.ratingCount ?? 0)
                if l == r { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return l > r
            }
        case .glRating:
            list.sort { lhs, rhs in
                let l = gamerLndAvg[lhs.id] ?? -1
                let r = gamerLndAvg[rhs.id] ?? -1
                if l == r { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return l > r
            }
        case .newest:
            list.sort { ($0.computedReleaseYear ?? 0) > ($1.computedReleaseYear ?? 0) }
        case .alpha:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        results = list
    }

    private func primeMetrics(for games: [Game]) {
        for game in games {
            if gamerLndCount[game.id] == nil {
                GamerLndScoreService.shared.fetchAverage(gameId: game.id) { avg, count in
                    DispatchQueue.main.async {
                        self.gamerLndAvg[game.id] = avg
                        self.gamerLndCount[game.id] = count
                        if self.selectedSort == .glRating {
                            self.applyGameSortAndFilters()
                        }
                    }
                }
            }
        }
    }

    private func loadSavedGames() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).getDocument { snap, _ in
            let list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
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
                self.savedGames = entries.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            }
        }
    }

    private func loadExistingGameIds() {
        db.collection("lists").document(listId)
            .collection("items")
            .limit(to: 500)
            .getDocuments { snap, _ in
                var ids: Set<Int> = []
                for d in (snap?.documents ?? []) {
                    let data = d.data()
                    if let gid = (data["game_id"] as? Int) ?? (data["game_id"] as? NSNumber)?.intValue {
                        ids.insert(gid)
                    }
                }
                existingGameIds = ids
            }
    }

    private func searchResultTitleFont(for title: String) -> Font {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.count {
        case ...24:
            return .subheadline.weight(.semibold)
        case ...48:
            return .subheadline.weight(.medium)
        default:
            return .caption.weight(.semibold)
        }
    }

    private func isAlreadyAdded(_ gameId: Int) -> Bool {
        existingGameIds.contains(gameId) || addedGameIds.contains(gameId)
    }

    private func add(game: Game) {
        guard !addingGameIds.contains(game.id) else { return }
        if isAlreadyAdded(game.id) {
            addedGameIds.insert(game.id)
            return
        }
        addingGameIds.insert(game.id)

        let listRef = db.collection("lists").document(listId)
        let items = listRef.collection("items")

        items.whereField("game_id", isEqualTo: game.id).limit(to: 1).getDocuments { snap, _ in
            if let _ = snap?.documents.first {
                self.addingGameIds.remove(game.id)
                self.addedGameIds.insert(game.id)
                self.existingGameIds.insert(game.id)
                return
            }

            let itemId = UUID().uuidString
            let batch = db.batch()

            var item: [String: Any] = [
                "id": itemId,
                "game_id": game.id,
                "game_name": game.name,
                "added_at": Timestamp(date: Date())
            ]
            if let coverId = game.cover?.imageId {
                item["cover_image_id"] = coverId
            } else {
                item["cover_image_id"] = NSNull()
            }

            batch.setData(item, forDocument: items.document(itemId), merge: false)
            batch.updateData([
                "updated_at": Timestamp(date: Date()),
                "item_count": FieldValue.increment(Int64(1))
            ], forDocument: listRef)

            batch.commit { err in
                DispatchQueue.main.async {
                    if let err {
                        self.addingGameIds.remove(game.id)
                        self.errorText = err.localizedDescription
                        return
                    }
                    self.addingGameIds.remove(game.id)
                    self.addedGameIds.insert(game.id)
                    self.existingGameIds.insert(game.id)
                    self.onAdded?()
                }
            }
        }
    }

    private func openSearchReport(for game: Game, resultIndex: Int) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        selectedSearchReportReason = .notRelevant
        searchReportNotes = ""
        activeSearchReport = SearchResultReportContext(
            query: trimmedQuery,
            gameId: game.id,
            gameName: game.name,
            resultIndex: resultIndex,
            surface: "list_add_games"
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
        SearchReportService.submit(context: context, reason: selectedSearchReportReason, notes: searchReportNotes) { result in
            DispatchQueue.main.async {
                self.isSubmittingSearchReport = false
                switch result {
                case .success:
                    self.dismissSearchReportOverlay()
                case .failure(let error):
                    self.errorText = "Could not send report: \(error.localizedDescription)"
                }
            }
        }
    }

    private func searchReportOverlay(context: SearchResultReportContext) -> some View {
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
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Report Search Result")
                            .font(.headline.weight(.bold))
                            .foregroundColor(ColorTheme.text)
                        Text(context.gameName)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(2)
                    }
                    Spacer()
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
                }

                Text("Search: \"\(context.query)\"")
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
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedSearchReportReason == reason ? ColorTheme.accent : ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextEditor(text: $searchReportNotes)
                    .focused($searchReportNotesFocused)
                    .scrollContentBackground(.hidden)
                    .frame(height: 82)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                    .foregroundColor(ColorTheme.text)

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

                    Button {
                        submitSearchReport(context)
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmittingSearchReport {
                                ProgressView().tint(.black)
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

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func gamePreviewOverlay(_ game: Game) -> some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    previewGame = nil
                    previewShowsPlatforms = false
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    if let imgId = game.cover?.imageId ?? game.screenshots?.first?.imageId {
                        GameCoverImage(id: imgId, preset: .custom(width: 96), cornerRadius: 12)
                            .frame(width: 96, height: 128)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ColorTheme.separator.opacity(0.2))
                            .frame(width: 96, height: 128)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(game.name)
                            .font(.headline.weight(.bold))
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(3)

                        if let avg = gamerLndAvg[game.id], (gamerLndCount[game.id] ?? 0) > 0 {
                            HStack(spacing: 6) {
                                AverageHeartBadge(value: avg, size: 18)
                                Text(formatRatingValue(avg))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                            }
                        }

                        if let year = game.computedReleaseYear {
                            Text(String(year))
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                        }

                        let platformNames = game.prioritizedPlatformNames(prefix: 99)
                        if !platformNames.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    previewShowsPlatforms.toggle()
                                }
                            } label: {
                                Text("\(platformNames.count) Platforms")
                                    .font(.caption.italic())
                                    .foregroundColor(ColorTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 0)
                    }
                }

                if previewShowsPlatforms {
                    let platformNames = game.prioritizedPlatformNames(prefix: 99)
                    Text(platformNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Close") {
                        previewGame = nil
                        previewShowsPlatforms = false
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .frame(width: min(UIScreen.main.bounds.width - 28, 380))
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ColorTheme.background)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
            )
            .padding(.horizontal, 14)
        }
    }
}
