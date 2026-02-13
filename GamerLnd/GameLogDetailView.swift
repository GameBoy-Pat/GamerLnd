// GameLogDetailView.swift
// Single log detail screen.
//
// THIS PASS:
// • Info card shows Title + Release Year + Platforms (publisher removed as requested).
// • Follow button is hidden if viewing your own log.
// • CommentRow shows username + avatar + timestamp.
// • Average rating, status, comments composer.
// • FIXED: removed KVC that crashed on `involvedCompanies`.
// • Year display forced to plain integer (no commas).
// • Analytics: follow events go through AnalyticsService.shared.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GameLogDetailView: View {
    let gameLog: GameLog
    let gameName: String
    let authorUsernameOverride: String?
    let focusCommentOnAppear: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var authorName: String = ""
    @State private var authorAvatarUrl: String? = nil
    @State private var isFollowingAuthor: Bool = false

    @State private var comments: [ReviewComment] = []
    @State private var commentsError: String = ""
    @State private var isLoadingComments: Bool = false
    @State private var newComment: String = ""
    @State private var isSending: Bool = false
    @FocusState private var commentFocused: Bool
    @State private var scrollToBottomToken: Int = 0
    @State private var screenshots: [Game.Screenshot] = []
    @State private var didAttemptScreenshotLoad: Bool = false
    @State private var currentScreenshotIndex: Int = 0

    // Reporting
    @State private var showReportSheet: Bool = false
    @State private var reportTarget: ReportTarget? = nil
    @State private var reportResultText: String = ""

    @State private var avgRating: Double? = nil
    @State private var ratingsCount: Int = 0

    // Display metadata for the info card (enriched via IGDB using gameLog.gameId)
    @State private var displayName: String = ""
    @State private var displayYear: Int? = nil
    @State private var displayPlatforms: [String] = []

    private let db = Firestore.firestore()
    private let igdb = IGDBService()

    var body: some View {
        ScrollViewReader { proxy in
            detailScrollView(proxy: proxy)
        }
    }

    @ViewBuilder
    private func detailScrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                headerHero
                infoCard
                    .padding(.horizontal, 16)
                    .offset(y: -28)
                    .zIndex(2)

                detailContent

                Color.clear
                    .frame(height: 1)
                    .id("commentListBottom")
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: comments.count) { _, _ in
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("commentListBottom", anchor: .bottom)
            }
        }
        .onChange(of: scrollToBottomToken) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("commentListBottom", anchor: .bottom)
                }
            }
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            commentComposer
                .background(ColorTheme.background)
        }
        .navigationTitle(" ")
        .toolbar {
            ToolbarItem(placement: .principal) { AppIconCentered() }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    Menu {
                        Button {
                            reportTarget = ReportTarget(
                                type: .log,
                                targetId: gameLog.id,
                                targetUserId: gameLog.userId,
                                title: "Report Log"
                            )
                            showReportSheet = true
                        } label: {
                            Label("Report Log", systemImage: "exclamationmark.bubble")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(ColorTheme.text)
                    }

                    NavigationLink(
                        destination: GameDetailView(game: Game(
                            id: gameLog.gameId,
                            name: displayName.isEmpty ? gameName : displayName,
                            cover: gameLog.cover,
                            firstReleaseDate: nil, genres: nil, platforms: nil,
                            rating: nil, ratingCount: nil, totalRatingCount: nil, screenshots: nil
                        ))
                    ) {
                        Text("Log this Game").bold()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ColorTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let target = reportTarget {
                ReportSheet(target: target, resultText: $reportResultText)
            }
        }
        .onAppear {
            hydrateAuthorIfNeeded()
            loadComments()
            loadAvgRating()
            enrichMeta()
            loadScreenshots()
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Author row with compact follow
            HStack(spacing: 10) {
                AvatarView(name: authorName.isEmpty ? "U" : authorName, size: 22, avatarURL: authorAvatarUrl)
                Text(authorName.isEmpty ? "User" : authorName)
                    .foregroundColor(ColorTheme.text)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if gameLog.userId != (Auth.auth().currentUser?.uid ?? "") {
                    FollowButtonCompact(
                        targetUserId: gameLog.userId,
                        isFollowing: $isFollowingAuthor
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, -24)

            // Rating / Review / Status
            VStack(alignment: .leading, spacing: 8) {
                if let r = gameLog.rating {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill").foregroundColor(ColorTheme.highlight)
                        Text(String(format: "%.1f", r))
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundColor(ColorTheme.highlight)
                    }
                }
                if let t = gameLog.review, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("“\(t)”")
                        .foregroundColor(ColorTheme.text)
                        .font(.body)
                }
                HStack(spacing: 6) {
                    Text("Status:")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                    Text(readableStatus(gameLog.status))
                        .font(.footnote)
                        .foregroundColor(ColorTheme.text)
                }
            }
            .padding(.horizontal, 16)

            // Average (GamerLnd score)
            if let avg = avgRating, ratingsCount > 0 {
                HStack(spacing: 8) {
                    Text("GamerLnd Score")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                    Image(systemName: "heart.fill").foregroundColor(ColorTheme.highlight)
                    Text(String(format: "%.1f", avg))
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ColorTheme.highlight)
                    Text("(\(ratingsCount))")
                        .font(.caption2).foregroundColor(ColorTheme.subtext)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            // Comments
            VStack(alignment: .leading, spacing: 10) {
                Text("Comments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .padding(.horizontal, 16)

                if isLoadingComments && comments.isEmpty {
                    ProgressView()
                        .padding(.horizontal, 16)
                } else if comments.isEmpty {
                    Text("No comments yet.")
                        .font(.footnote)
                        .foregroundColor(ColorTheme.subtext)
                        .padding(.horizontal, 16)
                } else {
                    ForEach(comments, id: \.id) { c in
                        CommentRow(comment: c, onReport: {
                            reportTarget = ReportTarget(
                                type: .comment,
                                targetId: c.id,
                                targetUserId: c.userId,
                                title: "Report Comment"
                            )
                            showReportSheet = true
                        })
                        .padding(.horizontal, 16)
                    }
                }

                if !commentsError.isEmpty {
                    Text(commentsError)
                        .font(.caption)
                        .foregroundColor(ColorTheme.highlight)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.bottom, 12)
    }
    private var headerHero: some View {
        let ids = screenshots.map { $0.imageId }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return ZStack {
            if !ids.isEmpty {
                let idx = currentScreenshotIndex % max(ids.count, 1)
                GameScreenshotImage(id: ids[idx], size: .hd720, cornerRadius: 0)
                    .frame(height: 180)
                    .clipped()
                    .transition(.opacity)
                    .id(ids[idx])
            } else if didAttemptScreenshotLoad {
                if let coverId = gameLog.cover?.imageId {
                    GameCoverImage(id: coverId, preset: .custom(width: 240), cornerRadius: 0)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(ColorTheme.surface)
                        .frame(height: 180)
                        .overlay(
                            Text("No screenshots available")
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                        )
                }
            } else {
                Rectangle()
                    .fill(ColorTheme.surface)
                    .frame(height: 180)
                    .overlay(ProgressView().tint(ColorTheme.accent))
            }

            LinearGradient(
                gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.55)]),
                startPoint: .center, endPoint: .bottom
            )
            .frame(height: 180)
        }
        .overlay(alignment: .center) {
            screenshotHeaderControls(idsCount: ids.count)
                .zIndex(8)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture().onEnded { value in
                guard !ids.isEmpty else { return }
                if value.translation.width < -20 { advanceScreenshot(idsCount: ids.count, forward: true) }
                if value.translation.width > 20 { advanceScreenshot(idsCount: ids.count, forward: false) }
            }
        )
    }

    private func advanceScreenshot(idsCount: Int, forward: Bool) {
        guard idsCount > 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            if forward {
                currentScreenshotIndex = (currentScreenshotIndex + 1) % idsCount
            } else {
                currentScreenshotIndex = (currentScreenshotIndex - 1 + idsCount) % idsCount
            }
        }
    }

    private func screenshotHeaderControls(idsCount: Int) -> some View {
        HStack {
            Button {
                advanceScreenshot(idsCount: idsCount, forward: false)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .opacity(idsCount > 1 ? 1 : 0.35)

            Spacer()

            Button {
                advanceScreenshot(idsCount: idsCount, forward: true)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .opacity(idsCount > 1 ? 1 : 0.35)
        }
        .padding(.horizontal, 16)
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            if let coverId = gameLog.cover?.imageId {
                GameCoverImage(id: coverId, preset: .custom(width: 66), cornerRadius: 10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(displayName.isEmpty ? gameName : displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)

                if !yearString(displayYear).isEmpty {
                    Text(yearString(displayYear))
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                }

                if !displayPlatforms.isEmpty {
                    Text(displayPlatforms.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(ColorTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
    }

    private var commentComposer: some View {
        HStack(spacing: 8) {
            TextField("Add a comment…", text: $newComment)
                .foregroundColor(ColorTheme.text)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                .focused($commentFocused)
            Button {
                sendComment()
            } label: {
                Text("Send").bold()
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorTheme.accent)
            .disabled(isSending || newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        
        .overlay(
            Rectangle()
                .fill(ColorTheme.separator.opacity(0.6))
                .frame(height: 1),
            alignment: .top
        )
    }

    private func readableStatus(_ s: GameStatus) -> String {
        switch s {
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .notPlayed: return "Not Played"
        }
    }

    private func hydrateAuthorIfNeeded() {
        // Always fetch avatar; only override name if provided.
        db.collection("users").document(gameLog.userId).getDocument { doc, _ in
            if let d = doc?.data() {
                if authorUsernameOverride == nil {
                    let name = (d["display_name"] as? String)
                        ?? (d["username"] as? String)
                        ?? (d["email"] as? String)
                        ?? "User"
                    self.authorName = name
                }
                if let avatar = d["avatar_url"] as? String, !avatar.isEmpty {
                    self.authorAvatarUrl = avatar
                }
            }
        }
        if let override = authorUsernameOverride, !override.isEmpty {
            self.authorName = override
        }
        InteractionService.shared.isFollowing(targetUserId: gameLog.userId) { following in
            self.isFollowingAuthor = following
        }
    }

    private func enrichMeta() {
        igdb.fetchGameById(id: gameLog.gameId) { result in
            if case .success(let g) = result {
                DispatchQueue.main.async {
                    if self.displayName.gl_isPlaceholderForId(self.gameLog.gameId) || self.displayName.isEmpty {
                        self.displayName = g.name
                    }
                    if self.displayYear == nil {
                        self.displayYear = g.computedReleaseYear
                    }
                    if self.displayPlatforms.isEmpty {
                        self.displayPlatforms = (g.platforms ?? []).map { $0.name }.prefix(4).map { $0 }
                    }
                }
            }
        }
    }

    private func loadScreenshots() {
        igdb.fetchGameById(id: gameLog.gameId) { result in
            DispatchQueue.main.async {
                if case .success(let g) = result {
                    self.screenshots = g.screenshots ?? []
                } else {
                    self.screenshots = []
                }
                self.didAttemptScreenshotLoad = true
            }
        }
    }

    private func loadAvgRating() {
        db.collection("game_logs")
            .whereField("game_id", isEqualTo: gameLog.gameId)
            .limit(to: 500)
            .getDocuments { snap, _ in
                let ratings: [Double] = (snap?.documents ?? []).compactMap { d in
                    if let dd = d.data()["rating"] as? Double { return dd }
                    if let num = d.data()["rating"] as? NSNumber { return num.doubleValue }
                    return nil
                }.filter { $0 > 0 }
                DispatchQueue.main.async {
                    if ratings.isEmpty {
                        self.avgRating = nil
                        self.ratingsCount = 0
                    } else {
                        self.ratingsCount = ratings.count
                        self.avgRating = ratings.reduce(0, +) / Double(ratings.count)
                    }
                }
            }
    }

    private func loadComments() {
        isLoadingComments = true
        db.collection("review_comments")
            .whereField("log_id", isEqualTo: gameLog.id)
            .order(by: "created_at", descending: false)
            .limit(to: 500)
            .getDocuments { snap, err in
                self.isLoadingComments = false
                if let err = err {
                    self.commentsError = "Failed to load comments: \(err.localizedDescription)"
                    return
                }
                let list: [ReviewComment] = (snap?.documents ?? []).compactMap { d in
                    let data = d.data()
                    guard
                        let id = data["id"] as? String ?? d.documentID as String?,
                        let uid = data["user_id"] as? String,
                        let text = data["text"] as? String,
                        let ts = data["created_at"] as? Timestamp,
                        let logId = data["log_id"] as? String
                    else { return nil }
                    return ReviewComment(id: id, logId: logId, userId: uid, text: text, createdAt: ts)
                }
                self.comments = list
            }
    }

    private func sendComment() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        let cid = UUID().uuidString
        let payload: [String: Any] = [
            "id": cid,
            "log_id": gameLog.id,
            "user_id": uid,
            "text": trimmed,
            "created_at": Timestamp(date: Date())
        ]
        db.collection("review_comments").document(cid).setData(payload) { err in
            self.isSending = false
            if let err = err {
                self.commentsError = err.localizedDescription
                return
            }
            if uid != self.gameLog.userId {
                NotificationService.shared.create(toUserId: self.gameLog.userId, relatedLogId: self.gameLog.id, type: .comment)
            }
            self.newComment = ""
            self.commentFocused = false
            self.loadComments()
            self.scrollToBottomToken += 1
        }
    }

}

// MARK: - Compact Follow Button

struct FollowButtonCompact: View {
    let targetUserId: String
    @Binding var isFollowing: Bool

    var body: some View {
        Button {
            InteractionService.shared.toggleFollow(u: targetUserId, isFollowing: isFollowing) { newState in
                self.isFollowing = newState
                AnalyticsService.shared.trackFollow(targetUserId: targetUserId, nowFollowing: newState)
            }
        } label: {
            Text(isFollowing ? "Followed" : "Follow")
                .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(isFollowing ? ColorTheme.separator : ColorTheme.accent)
        .foregroundColor(.white)
    }
}

// MARK: - Comment Row

struct CommentRow: View {
    let comment: ReviewComment
    var onReport: (() -> Void)? = nil

    @State private var username: String = "User"
    @State private var avatarUrl: String? = nil
    private let db = Firestore.firestore()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(name: username, size: 20, avatarURL: avatarUrl)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(username)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                    Text("•")
                        .font(.footnote).foregroundColor(ColorTheme.subtext)
                    Text(fullDate(comment.createdAt.dateValue()))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(ColorTheme.subtext)
                }
                Text(comment.text)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let onReport = onReport {
                Button {
                    onReport()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote)
                        .foregroundColor(ColorTheme.subtext)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .onAppear(perform: fetchUsername)
    }

    private func fetchUsername() {
        db.collection("users").document(comment.userId).getDocument { doc, _ in
            let data = doc?.data() ?? [:]
            let name = (data["display_name"] as? String)
                ?? (data["username"] as? String)
                ?? (data["email"] as? String)
                ?? "User"
            self.username = name
            if let avatar = data["avatar_url"] as? String, !avatar.isEmpty {
                self.avatarUrl = avatar
            }
        }
    }

    private func fullDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - Reporting

struct ReportTarget {
    let type: ReportTargetType
    let targetId: String
    let targetUserId: String?
    let title: String
}

struct ReportSheet: View {
    let target: ReportTarget
    @Binding var resultText: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: ReportReason = .spam
    @State private var notes: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text(target.title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(ColorTheme.text)

                Text("Tell us what’s going on. Reports are reviewed by moderators.")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.subtext)

                Picker("Reason", selection: $selectedReason) {
                    ForEach(ReportReason.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.menu)

                TextField("Optional details", text: $notes, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(ColorTheme.highlight)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("Report")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSubmitting ? "Sending..." : "Send") {
                        submit()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .preferredColorScheme(ColorTheme.preferredScheme)
    }

    private func submit() {
        isSubmitting = true
        errorText = ""
        ReportService.shared.submit(
            targetType: target.type,
            targetId: target.targetId,
            targetUserId: target.targetUserId,
            reason: selectedReason,
            notes: notes
        ) { result in
            isSubmitting = false
            switch result {
            case .success:
                resultText = "Thanks for the report."
                dismiss()
            case .failure(let err):
                errorText = err.localizedDescription
            }
        }
    }
}

// MARK: - Local helper

private extension String {
    func gl_isPlaceholderForId(_ id: Int) -> Bool {
        self == "Game #\(id)" || self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@inline(__always)
private func yearString(_ y: Int?) -> String {
    guard let y = y else { return "" }
    return String(y) // never adds grouping separators
}
