// SearchUsersView.swift
// User search with idle state, magnifying-glass action, LIVE (debounced) results,
// Sort & Filters, follower/log/review counts, follow/unfollow, and "Load more" pagination.
// THIS PASS: uses canonical UserLite from DataModels.swift (remove local duplicate).

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import os.log

struct SearchUsersView: View {
    // MARK: - Query / Results
    @State private var query: String = ""
    @State private var results: [UserLite] = []
    @State private var isLoading: Bool = false
    @State private var errorText: String = ""

    // Sort mode
    enum SortMode: String, CaseIterable, Identifiable {
        case relevance = "Relevance"
        case followers = "Followers"
        case recent = "Recent Activity"
        case alpha = "Alphabetical"
        var id: String { rawValue }
    }
    @State private var sortMode: SortMode = .relevance

    // Filters (simple demo)
    @State private var filterHasReviews: Bool = false
    @State private var filterHasAvatar: Bool = false
    @State private var showingFilters: Bool = false

    // Live search debounce
    @State private var debounceTask: DispatchWorkItem?

    // Quotes / idle state
    private let idleQuotes: [String] = [
        "People linked by destiny will always find each other.",
        "I see 'em up ahead! Let's rock and roll!",
        "It's dangerous to go alone...",
        "Your friends... what kind of people are they? I wonder, do those people think of you as a friend?",
        "It's-a me!",
        "My friends… with all of your strength… stand with me",
        "Poyo poyo!"
    ]
    @State private var currentQuote: String = ""
    private var showIdle: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isLoading
        && results.isEmpty
        && errorText.isEmpty
    }

    // Paging
    private let pageSize: Int = 20
    @State private var lastDoc: DocumentSnapshot?
    @State private var canLoadMore: Bool = false

    // Caches & state per user
    @State private var followersCount: [String: Int] = [:]
    @State private var logsCount: [String: Int] = [:]
    @State private var reviewsCount: [String: Int] = [:]
    @State private var lastActivity: [String: Date] = [:]
    @State private var followingState: [String: Bool] = [:]

    // Services
    private let db = Firestore.firestore()

    var body: some View {
        VStack(spacing: 0) {

            // Search + Sort & Filters row
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        TextField("Search users…", text: $query, onCommit: { performSearch(reset: true) })
                            .textInputAutocapitalization(.none)
                            .disableAutocorrection(true)
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

                    Button(action: { performSearch(reset: true) }) {
                        Image(systemName: "magnifyingglass")
                            .font(.headline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ColorTheme.accent)
                    .disabled(isLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Sort & Filters
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

                    Button {
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

            // Active filter chips
            if filterHasReviews || filterHasAvatar {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if filterHasReviews {
                            chip("Has Reviews") { filterHasReviews = false; applyLocalFiltersAndSort() }
                        }
                        if filterHasAvatar {
                            chip("Has Avatar") { filterHasAvatar = false; applyLocalFiltersAndSort() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            }

            // Results
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

                        ForEach(results, id: \.id) { user in
                            NavigationLink(
                                destination: ProfileView(userId: user.id)
                            ) {
                                userRow(user)
                                    .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if followersCount[user.id] == nil { fetchFollowersCount(for: user.id) }
                                if logsCount[user.id] == nil || (filterHasReviews && reviewsCount[user.id] == nil) {
                                    fetchLogAndReviewCounts(for: user.id)
                                }
                                if lastActivity[user.id] == nil { fetchLastActivity(for: user.id) }
                                if followingState[user.id] == nil { fetchFollowingState(for: user.id) }

                                if user.id == results.suffix(5).first?.id, canLoadMore, !isLoading {
                                    loadMore()
                                }
                            }
                        }

                        if canLoadMore {
                            Button {
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

                // Idle overlay
                if showIdle {
                    VStack(spacing: 16) {
                        Text("Search for Users")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(ColorTheme.text)

                        if !currentQuote.isEmpty {
                            Text(currentQuote)
                                .italic()
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: task)
        }
        .onChange(of: sortMode) { _, _ in
            applyLocalFiltersAndSort()
        }
        .onChange(of: filterHasReviews) { _, _ in
            applyLocalFiltersAndSort()
        }
        .onChange(of: filterHasAvatar) { _, _ in
            applyLocalFiltersAndSort()
        }
    }

    // MARK: - Filters Sheet

    private var FiltersSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Users")) {
                    Toggle("Has Reviews", isOn: $filterHasReviews)
                    Toggle("Has Avatar", isOn: $filterHasAvatar)
                }

                Section(footer: Text("You can add more filters later (e.g., platform preferences, bio keywords).")) {
                    EmptyView()
                }
            }
            .navigationBarTitle("Filters", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        filterHasReviews = false
                        filterHasAvatar = false
                        applyLocalFiltersAndSort()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingFilters = false; applyLocalFiltersAndSort() }
                }
            }
        }
        .preferredColorScheme(ColorTheme.preferredScheme)
    }

    // MARK: - Row

    private func userRow(_ user: UserLite) -> some View {
        let fCount = followersCount[user.id] ?? 0
        let lCount = logsCount[user.id] ?? 0
        let rCount = reviewsCount[user.id] ?? 0
        let last = lastActivity[user.id]
        let isFollowing = followingState[user.id] ?? false
        let isMe = (user.id == Auth.auth().currentUser?.uid)

        return HStack(alignment: .center, spacing: 12) {
            // Avatar
            AvatarView(name: user.username, size: 54)
                .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.username)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                        Text("\(fCount)")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                        Text("\(lCount)")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble")
                        Text("\(rCount)")
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

            Spacer(minLength: 0)

            // Follow / Followed
            if !isMe {
                Button {
                    InteractionService.shared.toggleFollow(u: user.id, isFollowing: isFollowing) { newState in
                        followingState[user.id] = newState
                        followersCount[user.id] = max(0, (followersCount[user.id] ?? 0) + (newState ? 1 : -1))
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
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1)
        )
    }

    // MARK: - Actions / Search

    private func performSearch(reset: Bool) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = q.hasPrefix("@") ? String(q.dropFirst()) : q
        guard !q.isEmpty else { return }

        // Minimum 2 chars to reduce noise
        guard q.count >= 2 else {
            clearSearch()
            return
        }

        debounceTask?.cancel()
        debounceTask = nil

        if reset {
            results = []
            lastDoc = nil
            canLoadMore = false
        }

        errorText = ""
        isLoading = true

        // Try username_lower first
        let collection = db.collection("users")
        let lower = normalized.lowercased()
        var queryRef: Query = collection
            .order(by: "username_lower")
            .start(at: [lower])
            .end(at: [lower + "\u{f8ff}"])
            .limit(to: pageSize)

        if let last = lastDoc {
            queryRef = queryRef.start(afterDocument: last)
        }

        queryRef.getDocuments { snap, err in
            // If missing index/field, fallback to "username"
            if let err = err as NSError?, err.code == 9 || err.code == 7 {
                self.queryWithUsernameField(prefix: q, reset: reset)
                return
            }
            guard err == nil else {
                self.isLoading = false
                self.errorText = err?.localizedDescription ?? "Failed to search."
                return
            }

            self.lastDoc = snap?.documents.last

            let newUsers: [UserLite] = (snap?.documents ?? []).compactMap { d in
                Self.parseUser(docId: d.documentID, data: d.data())
            }

            var merged = Dictionary(uniqueKeysWithValues: self.results.map { ($0.id, $0) })
            for u in newUsers { merged[u.id] = u }
            var newList = Array(merged.values)

            newList = self.applyFilters(to: newList)
            newList = self.applySort(to: newList, baseOrder: self.results)

            self.results = newList
            self.canLoadMore = (newUsers.count >= self.pageSize)
            self.isLoading = false

            // Prime counters/states
            for u in newUsers {
                if self.followersCount[u.id] == nil { self.fetchFollowersCount(for: u.id) }
                if self.logsCount[u.id] == nil || (self.filterHasReviews && self.reviewsCount[u.id] == nil) {
                    self.fetchLogAndReviewCounts(for: u.id)
                }
                if self.lastActivity[u.id] == nil { self.fetchLastActivity(for: u.id) }
                if self.followingState[u.id] == nil { self.fetchFollowingState(for: u.id) }
            }
        }
    }

    private func queryWithUsernameField(prefix: String, reset: Bool) {
        let collection = db.collection("users")
        var queryRef: Query = collection
            .order(by: "username")
            .start(at: [prefix])
            .end(at: [prefix + "\u{f8ff}"])
            .limit(to: pageSize)

        if let last = lastDoc { queryRef = queryRef.start(afterDocument: last) }

        queryRef.getDocuments { snap, err in
            self.isLoading = false
            if let err = err {
                self.errorText = err.localizedDescription
                return
            }
            self.lastDoc = snap?.documents.last

            let newUsers: [UserLite] = (snap?.documents ?? []).compactMap { d in
                Self.parseUser(docId: d.documentID, data: d.data())
            }

            var merged = Dictionary(uniqueKeysWithValues: self.results.map { ($0.id, $0) })
            for u in newUsers { merged[u.id] = u }
            var newList = Array(merged.values)

            newList = self.applyFilters(to: newList)
            newList = self.applySort(to: newList, baseOrder: self.results)

            self.results = newList
            self.canLoadMore = (newUsers.count >= self.pageSize)
        }
    }

    private func loadMore() {
        guard !isLoading, canLoadMore else { return }
        performSearch(reset: false)
    }

    private func clearSearch() {
        debounceTask?.cancel()
        query = ""
        results = []
        errorText = ""
        isLoading = false
        canLoadMore = false
        lastDoc = nil
    }

    // MARK: - Sorting / Filtering (local)

    private func applyLocalFiltersAndSort() {
        results = applyFilters(to: results)
        results = applySort(to: results, baseOrder: results)
    }

    private func applyFilters(to list: [UserLite]) -> [UserLite] {
        var filtered = list
        if filterHasAvatar {
            filtered = filtered.filter { ($0.avatarUrl ?? "").isEmpty == false }
        }
        if filterHasReviews {
            filtered = filtered.filter { (reviewsCount[$0.id] ?? 0) > 0 }
        }
        return filtered
    }

    private func applySort(to list: [UserLite], baseOrder: [UserLite]) -> [UserLite] {
        switch sortMode {
        case .relevance:
            return stableByExistingOrder(list, existing: baseOrder)
        case .followers:
            return list.sorted {
                (followersCount[$0.id] ?? 0) > (followersCount[$1.id] ?? 0)
            }
        case .recent:
            return list.sorted {
                (lastActivity[$0.id] ?? .distantPast) > (lastActivity[$1.id] ?? .distantPast)
            }
        case .alpha:
            return list.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        }
    }

    private func stableByExistingOrder(_ list: [UserLite], existing: [UserLite]) -> [UserLite] {
        let indexMap: [String: Int] = Dictionary(uniqueKeysWithValues: existing.enumerated().map { ($0.element.id, $0.offset) })
        return list.sorted {
            let a = indexMap[$0.id] ?? Int.max
            let b = indexMap[$1.id] ?? Int.max
            if a == b { return $0.id < $1.id }
            return a < b
        }
    }

    // MARK: - Fetch per-user stats

    private func fetchFollowersCount(for userId: String) {
        db.collection("follows")
            .whereField("followed_id", isEqualTo: userId)
            .getDocuments { snap, _ in
                DispatchQueue.main.async {
                    followersCount[userId] = snap?.documents.count ?? 0
                    if sortMode == .followers { applyLocalFiltersAndSort() }
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
                    logsCount[userId] = logs
                    reviewsCount[userId] = reviews
                    if filterHasReviews { applyLocalFiltersAndSort() }
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
                    lastActivity[userId] = last
                    if sortMode == .recent { applyLocalFiltersAndSort() }
                }
            }
    }

    private func fetchFollowingState(for userId: String) {
        InteractionService.shared.isFollowing(targetUserId: userId) { state in
            DispatchQueue.main.async {
                followingState[userId] = state
            }
        }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func chip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption.weight(.semibold))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").font(.caption)
            }
        }
        .foregroundColor(ColorTheme.accent)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
    }

    // MARK: - Parser

    static func parseUser(docId: String, data: [String: Any]) -> UserLite? {
        let id = (data["id"] as? String) ?? docId
        let username = (data["username"] as? String) ?? (data["email"] as? String) ?? "User"
        let displayName = data["display_name"] as? String
        let avatar = UserRecordAvatarResolver.url(from: data)
        return UserLite(id: id, username: username, displayName: displayName, avatarUrl: avatar)
    }
}
