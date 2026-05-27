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

private enum CurrentUserLogPresenceStore {
    private static var cache: [String: Set<Int>] = [:]

    static func contains(userId: String, gameId: Int) -> Bool? {
        guard let set = cache[userId] else { return nil }
        return set.contains(gameId)
    }

    static func set(_ hasLog: Bool, userId: String, gameId: Int) {
        var set = cache[userId] ?? []
        if hasLog {
            set.insert(gameId)
        } else {
            set.remove(gameId)
        }
        cache[userId] = set
    }
}

struct GameLogDetailView: View {
    private struct BookmarkEntry: Identifiable {
        let id: Int
        let name: String
        let coverId: String?
        let addedAt: Date?
    }

    private enum BookmarkSort: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case az = "A–Z"

        var id: String { rawValue }
    }

    let gameLog: GameLog
    let gameName: String
    let authorUsernameOverride: String?
    let focusCommentOnAppear: Bool
    var suppressHostChrome: Binding<Bool> = .constant(false)
    var onOpenCurrentUserLog: ((Game) -> Void)? = nil
    var embeddedOverlay: Bool = false
    var hostedInOverlay: Bool = false
    var compactFeedExpansion: Bool = false
    var onRequestClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var authorName: String = ""
    @State private var authorAvatarUrl: String? = nil
    @State private var commentAuthorNames: [String: String] = [:]
    @State private var commentAuthorAvatars: [String: String] = [:]
    @State private var isFollowingAuthor: Bool = false

    @State private var comments: [ReviewComment] = []
    @State private var commentsError: String = ""
    @State private var errorText: String = ""
    @State private var isLoadingComments: Bool = false
    @State private var likeCount: Int = 0
    @State private var isLikedByCurrentUser: Bool = false
    @State private var isLikeMutationInFlight: Bool = false
    @State private var likers: [LogLiker] = []
    @State private var isLoadingLikers: Bool = false
    @State private var isReferenceSaved: Bool = false
    @State private var isSavingReference: Bool = false
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
    @State private var hasCurrentUserLogForGame: Bool = false
    @State private var currentUserLogGameOverlay: Game? = nil
    @State private var showReviewOverlay: Bool = false
    @State private var showSpoilerWarning: Bool = false
    @State private var showCommentsOverlay: Bool = false
    @State private var showCommentsReviewOverlay: Bool = false
    @State private var showLikesOverlay: Bool = false
    @State private var spoilerReviewRequestFromComments: Bool = false
    @State private var showAddToList: Bool = false
    @State private var isSavedGame: Bool = false
    @State private var isSavingGame: Bool = false
    @State private var showSavedGameToast: Bool = false
    @State private var commentsKeyboardHeight: CGFloat = 0
    @State private var showBookmarksOverlay: Bool = false
    @State private var bookmarksList: [BookmarkEntry] = []
    @State private var watchlistIds: Set<Int> = []
    @State private var bookmarksSort: BookmarkSort = .recent
    @State private var isPreparingShareCard: Bool = false
    @State private var activeShareSheet: ShareSheetPayload? = nil

    // Display metadata for the info card (enriched via IGDB using gameLog.gameId)
    @State private var displayName: String = ""
    @State private var displayYear: Int? = nil
    @State private var displayPlatforms: [String] = []
    @State private var showPlatformsOverlay: Bool = false
    @State private var primaryStudioName: String? = nil
    @State private var fullGameMetadata: Game? = nil
    @State private var isFetchingFullGameMetadata: Bool = false

    private let db = Firestore.firestore()
    private let igdb = IGDBService()
    
    private var userRatingAccent: Color {
        if let rating = gameLog.rating, rating > 0 {
            return ColorTheme.ratingBandColor(for: rating)
        }
        return ColorTheme.separator
    }

    private func shareReviewCard() {
        guard !isPreparingShareCard else { return }
        isPreparingShareCard = true

        Task { @MainActor in
            let fallbackName = authorName.isEmpty ? (authorUsernameOverride ?? "Gamer") : authorName
            let identity = await GamerLndShareCardRenderer.fetchUserIdentity(
                userId: gameLog.userId,
                fallbackName: fallbackName
            )
            let avatarImage = await GamerLndShareCardRenderer.loadAvatarImage(urlString: identity.avatarURL)
            let fallbackHandle = authorUsernameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedHandle = fallbackHandle.isEmpty
                ? (identity.handle ?? identity.displayName.replacingOccurrences(of: " ", with: "").lowercased())
                : fallbackHandle.replacingOccurrences(of: "@", with: "")

            let request = ReviewShareCardRequest(
                gameTitle: displayName.isEmpty ? gameName : displayName,
                releaseYear: displayYear,
                primaryStudio: primaryStudioName,
                username: resolvedHandle,
                displayName: identity.displayName,
                userRating: gameLog.rating,
                averageRating: avgRating,
                reviewText: gameLog.review,
                coverImageId: gameLog.cover?.imageId,
                avatarImage: avatarImage
            )

            let payload = await GamerLndShareCardRenderer.makeReviewSharePayload(request: request)
            isPreparingShareCard = false
            if let payload {
                activeShareSheet = payload
            } else {
                errorText = "Could not generate share card right now."
            }
        }
    }

    var body: some View {
        ZStack {
            if let game = currentUserLogGameOverlay {
                GameDetailView(
                    game: game,
                    compactOverlay: embeddedOverlay,
                    onRequestClose: {
                        currentUserLogGameOverlay = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                detailScrollView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func detailScrollView() -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if compactFeedExpansion {
                    detailContent
                        .padding(.top, 12)
                } else {
                    headerHero
                    infoCard
                        .padding(.horizontal, 16)
                        .offset(y: -28)
                        .zIndex(2)

                    detailContent
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background((hostedInOverlay ? Color.clear : ColorTheme.background).ignoresSafeArea())
        .clipShape(RoundedRectangle(cornerRadius: hostedInOverlay ? 0 : 18, style: .continuous))
        .overlay(
            Group {
                if !hostedInOverlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(userRatingAccent.opacity(0.78), lineWidth: 1.2)
                }
            }
        )
        .overlay(alignment: .topTrailing) {
            if let onRequestClose, !showCommentsOverlay, !hostedInOverlay {
                Button {
                    onRequestClose()
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.top, embeddedOverlay ? 12 : -34)
            }
        }
        .navigationTitle(embeddedOverlay ? "" : " ")
        .toolbar {
            if !embeddedOverlay {
                ToolbarItem(placement: .principal) { AppIconCentered() }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        shareReviewCard()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(ColorTheme.text)
                    }

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
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                KeyboardDismissAccessoryButton {
                    commentFocused = false
                }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let target = reportTarget {
                ReportSheet(target: target, resultText: $reportResultText)
            }
        }
        .sheet(item: $activeShareSheet) { payload in
            SharePreviewSheet(payload: payload)
        }
        .overlay {
            if showReviewOverlay {
                reviewOverlay
            } else if showLikesOverlay {
                likesOverlay
            } else if showCommentsOverlay {
                commentsOverlay
            } else if showPlatformsOverlay {
                platformsOverlay
            } else if showAddToList, let uid = Auth.auth().currentUser?.uid {
                ZStack {
                    OverlayBackdrop()
                        .ignoresSafeArea()
                        .onTapGesture { showAddToList = false }

                    AddToListSheet(
                        ownerId: uid,
                        game: Game(
                            id: gameLog.gameId,
                            name: displayName.isEmpty ? gameName : displayName,
                            cover: gameLog.cover,
                            firstReleaseDate: nil,
                            genres: nil,
                            platforms: nil,
                            rating: nil,
                            ratingCount: nil,
                            totalRatingCount: nil,
                            screenshots: nil
                        )
                    ) {
                        showAddToList = false
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
            } else if showBookmarksOverlay {
                bookmarksOverlay
            } else if isPreparingShareCard {
                ZStack {
                    OverlayBackdrop()
                        .ignoresSafeArea()

                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(ColorTheme.accent)
                        Text("Preparing share card...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(ColorTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(ColorTheme.separator, lineWidth: 1)
                            )
                    )
                }
            }
        }
        .alert("Spoiler Warning", isPresented: $showSpoilerWarning) {
            Button("Cancel", role: .cancel) {
                spoilerReviewRequestFromComments = false
            }
            Button("Read Review") {
                if spoilerReviewRequestFromComments {
                    showCommentsReviewOverlay = true
                    spoilerReviewRequestFromComments = false
                } else {
                    showReviewOverlay = true
                }
            }
        } message: {
            Text("This review was marked as containing spoilers. Do you still want to read it?")
        }
        .onAppear {
            hydrateAuthorIfNeeded()
            loadComments()
            loadLikeState()
            loadReferenceState()
            loadAvgRating()
            loadSupplementalGameMetadataIfNeeded()
            loadCurrentUserLogState()
            loadSavedGameState()
            if focusCommentOnAppear {
                showCommentsOverlay = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    commentFocused = true
                }
            }
            syncHostChromeSuppression()
        }
        .onChange(of: showCommentsOverlay) { _, _ in syncHostChromeSuppression() }
        .onChange(of: showCommentsReviewOverlay) { _, _ in syncHostChromeSuppression() }
        .onChange(of: showAddToList) { _, _ in syncHostChromeSuppression() }
        .onChange(of: showBookmarksOverlay) { _, _ in syncHostChromeSuppression() }
        .onChange(of: showPlatformsOverlay) { _, _ in syncHostChromeSuppression() }
        .onReceive(NotificationCenter.default.publisher(for: .gameLogChanged)) { note in
            guard let currentUserId = Auth.auth().currentUser?.uid,
                  let changedUserId = note.userInfo?["user_id"] as? String,
                  let changedGameId = note.userInfo?["game_id"] as? Int,
                  changedUserId == currentUserId,
                  changedGameId == gameLog.gameId else { return }
            let deleted = note.userInfo?["deleted"] as? Bool ?? false
            CurrentUserLogPresenceStore.set(!deleted, userId: currentUserId, gameId: gameLog.gameId)
            hasCurrentUserLogForGame = !deleted
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard showCommentsOverlay,
                  let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            let screenHeight = UIScreen.main.bounds.height
            commentsKeyboardHeight = max(0, screenHeight - frame.origin.y)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            commentsKeyboardHeight = 0
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    if hasCurrentUserLogForGame {
                        previewTextActionButton(title: "Open Log") {
                            openCurrentUserLogAction()
                        }
                    } else {
                        previewTextActionButton(title: "Log Game", systemName: "plus") {
                            Haptics.tap()
                            openCurrentUserLogAction()
                        }
                    }

                    if hasCurrentUserLogForGame {
                        solidPreviewActionButton(systemName: "text.badge.plus") {
                            Haptics.tap()
                            showAddToList = true
                        }
                    }

                    solidPreviewActionButton(systemName: isSavedGame ? "tray.and.arrow.down.fill" : "tray.and.arrow.down",
                                             tint: isSavedGame ? ColorTheme.accent : .white,
                                             fill: isSavedGame ? ColorTheme.accent.opacity(0.14) : ColorTheme.surface,
                                             disabled: isSavingGame) {
                        Haptics.tap()
                        openBookmarksOverlay()
                    }

                    if gameLog.userId != (Auth.auth().currentUser?.uid ?? "") {
                        solidPreviewActionButton(systemName: referenceButtonSystemName,
                                                 tint: isReferenceSaved ? ColorTheme.accent : .white,
                                                 fill: isReferenceSaved ? ColorTheme.accent.opacity(0.14) : ColorTheme.surface,
                                                 disabled: isSavingReference) {
                            toggleReferenceSaved()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, compactFeedExpansion ? 0 : -18)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.highlight)
                    .padding(.horizontal, 16)
            }

            // Author row with clearer hierarchy
            HStack(alignment: .center, spacing: 12) {
                AvatarView(name: authorName.isEmpty ? "U" : authorName, size: 32, avatarURL: authorAvatarUrl)

                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName.isEmpty ? "User" : authorName)
                        .foregroundColor(ColorTheme.text)
                        .font(.headline.weight(.semibold))
                    Text(logEditedSubtitle)
                        .foregroundColor(ColorTheme.subtext)
                        .font(.caption.weight(.medium))
                }

                Spacer()

                if let avg = avgRating, ratingsCount > 0 {
                    Button {
                        NotificationCenter.default.post(
                            name: .openRatingsOverlayRequested,
                            object: nil,
                            userInfo: [
                                "game_id": gameLog.gameId,
                                "game_name": gameName,
                                "avg": avg,
                                "cover_image_id": gameLog.cover?.imageId as Any
                            ]
                        )
                    } label: {
                        AverageHeartBadge(value: avg, size: 24)
                    }
                    .buttonStyle(.plain)
                }

                if gameLog.userId != (Auth.auth().currentUser?.uid ?? "") {
                    FollowButtonCompact(
                        targetUserId: gameLog.userId,
                        isFollowing: $isFollowingAuthor
                    )
                }
            }
            .padding(.horizontal, 16)

            // Rating / Review
            VStack(alignment: .leading, spacing: 8) {
                if let r = gameLog.rating, let t = gameLog.review, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let isOwnLog = gameLog.userId == (Auth.auth().currentUser?.uid ?? "")
                    HStack(alignment: .center, spacing: 12) {
                        RatingHeartBadge(value: r, size: 60)
                            .fixedSize()

                        Button {
                            if gameLog.containsSpoilers {
                                showSpoilerWarning = true
                            } else {
                                showReviewOverlay = true
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Read Review")
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(ColorTheme.text)
                                    Text(gameLog.containsSpoilers && !isOwnLog ? "This review is marked for spoilers." : ContentModeration.displayReviewText(t))
                                        .font(gameLog.containsSpoilers && !isOwnLog ? .caption.italic() : .caption)
                                        .foregroundColor(gameLog.containsSpoilers && !isOwnLog ? ColorTheme.accent : ColorTheme.subtext)
                                        .lineLimit(3)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "text.quote")
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(ColorTheme.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(userRatingAccent.opacity(0.58), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    if let r = gameLog.rating {
                        RatingHeartBadge(value: r, size: 60)
                    }
                    if let t = gameLog.review, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let isOwnLog = gameLog.userId == (Auth.auth().currentUser?.uid ?? "")
                        Button {
                            if gameLog.containsSpoilers {
                                showSpoilerWarning = true
                            } else {
                                showReviewOverlay = true
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Read Review")
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(ColorTheme.text)
                                    Text(gameLog.containsSpoilers && !isOwnLog ? "This review is marked for spoilers." : ContentModeration.displayReviewText(t))
                                        .font(gameLog.containsSpoilers && !isOwnLog ? .caption.italic() : .caption)
                                        .foregroundColor(gameLog.containsSpoilers && !isOwnLog ? ColorTheme.accent : ColorTheme.subtext)
                                        .lineLimit(3)
                                }
                                Spacer()
                                Image(systemName: "text.quote")
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(ColorTheme.accent)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(userRatingAccent.opacity(0.58), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        guard !isLikeMutationInFlight else { return }
                        let shouldLike = !isLikedByCurrentUser
                        isLikeMutationInFlight = true
                        isLikedByCurrentUser = shouldLike
                        let previousCount = likeCount
                        likeCount = max(0, likeCount + (shouldLike ? 1 : -1))
                        InteractionService.shared.setLikeState(
                            log: gameLog,
                            shouldLike: shouldLike
                        ) { result in
                            isLikeMutationInFlight = false
                            switch result {
                            case .success(let state):
                                isLikedByCurrentUser = state.isLiked
                                likeCount = state.count
                            case .failure(let error):
                                errorText = error.localizedDescription
                                isLikedByCurrentUser = !shouldLike
                                likeCount = previousCount
                            }
                        }
                    } label: {
                        Image(systemName: isLikedByCurrentUser ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(isLikedByCurrentUser ? ColorTheme.accent : ColorTheme.text)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLikeMutationInFlight)

                    Button {
                        openLikesOverlay()
                    } label: {
                        Text(likePillTitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Color.white.opacity(0.96))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(userRatingAccent.opacity(0.58), lineWidth: 1))

                Button {
                    showCommentsOverlay = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .font(.footnote.weight(.semibold))
                        Text(commentPillTitle)
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ColorTheme.subtext)
                    }
                    .foregroundColor(ColorTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(userRatingAccent.opacity(0.58), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Comments (\(comments.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)

                    VStack(alignment: .leading, spacing: 6) {
                        let previewComments = Array(comments.suffix(3).reversed())
                        ForEach(Array(previewComments.enumerated()), id: \.element.id) { entry in
                            let comment = entry.element
                            VStack(alignment: .leading, spacing: 2) {
                                Text(commentPreviewAuthorName(for: comment))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                                    .lineLimit(1)
                                Text(ContentModeration.displayCommentText(comment.text))
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.subtext)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if entry.offset < previewComments.count - 1 {
                                Rectangle()
                                    .fill(ColorTheme.separator.opacity(0.28))
                                    .frame(height: 0.5)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(userRatingAccent.opacity(0.58), lineWidth: 1))
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 24)
        .padding(.bottom, 12)
    }

    private var likesOverlay: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { showLikesOverlay = false }

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Likes")
                            .font(.headline.weight(.bold))
                            .foregroundColor(ColorTheme.text)
                        Text(likePillTitle)
                            .font(.caption)
                            .foregroundColor(ColorTheme.subtext)
                    }
                    Spacer()
                    Button {
                        showLikesOverlay = false
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider().opacity(0.3)

                Group {
                    if isLoadingLikers {
                        ProgressView()
                            .tint(ColorTheme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if likers.isEmpty {
                        Text("No likes yet.")
                            .font(.footnote)
                            .foregroundColor(ColorTheme.subtext)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(likers) { liker in
                                    LikerRow(liker: liker)
                                        .padding(.horizontal, 16)
                                }
                            }
                            .padding(.vertical, 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: min(UIScreen.main.bounds.width - 24, 390), height: min(UIScreen.main.bounds.height - 120, 520))
            .background(RoundedRectangle(cornerRadius: 18).fill(ColorTheme.background))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
            .padding(.horizontal, 12)
        }
    }

    private var reviewOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { showReviewOverlay = false }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    AvatarView(name: authorName.isEmpty ? "User" : authorName, size: 22, avatarURL: authorAvatarUrl)
                    Text("\((authorName.isEmpty ? "User" : authorName))’s review")
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Button {
                        showReviewOverlay = false
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }

                Text(ContentModeration.displayReviewText(gameLog.review))
                    .font(.body)
                    .foregroundColor(ColorTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: min(UIScreen.main.bounds.width - 24, 390))
            .background(RoundedRectangle(cornerRadius: 18).fill(ColorTheme.background))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
            .padding(.horizontal, 12)
        }
    }

    private var commentsOverlay: some View {
        GeometryReader { geo in
            let keyboardInset = max(0, commentsKeyboardHeight - geo.safeAreaInsets.bottom)
            let topInset: CGFloat = 64
            let sideInset: CGFloat = 14
            let panelWidth = min(geo.size.width - (sideInset * 2), 396)
            let availableHeight = max(360, geo.size.height - topInset - max(18, keyboardInset + 12))
            let panelHeight = min(availableHeight, 610.0)

            ZStack(alignment: .top) {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture { showCommentsOverlay = false }

                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Comments")
                                    .font(.headline.weight(.bold))
                                    .foregroundColor(ColorTheme.text)
                                Text(commentPillSubtitle)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.subtext)
                            }
                            Spacer()
                            Button {
                                showCommentsOverlay = false
                            } label: {
                                OverlayCloseButton()
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 10)

                        if let review = gameLog.review, !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                if gameLog.containsSpoilers {
                                    spoilerReviewRequestFromComments = true
                                    showSpoilerWarning = true
                                } else {
                                    showCommentsReviewOverlay = true
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "text.quote")
                                        .font(.footnote.weight(.semibold))
                                    Text("Show Review")
                                        .font(.footnote.weight(.semibold))
                                    Spacer()
                                }
                                .foregroundColor(ColorTheme.accent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }

                        Divider().opacity(0.3)

                        Group {
                            if isLoadingComments && comments.isEmpty {
                                ProgressView()
                                    .tint(ColorTheme.accent)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if comments.isEmpty {
                                Text("No comments yet.")
                                    .font(.footnote)
                                    .foregroundColor(ColorTheme.subtext)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollViewReader { proxy in
                                    ScrollView {
                                        VStack(spacing: 10) {
                                            ForEach(comments, id: \.id) { c in
                                                CommentRow(
                                                    comment: c,
                                                    cachedUsername: commentPreviewAuthorName(for: c),
                                                    cachedAvatarUrl: c.authorAvatarUrl ?? commentAuthorAvatars[c.userId],
                                                    onReport: {
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

                                            Color.clear
                                                .frame(height: 1)
                                                .id("commentListBottom")
                                        }
                                        .padding(.vertical, 12)
                                    }
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
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !commentsError.isEmpty {
                            Text(commentsError)
                                .font(.caption)
                                .foregroundColor(ColorTheme.highlight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                        }

                        commentComposer
                            .background(ColorTheme.background)
                    }
                    .frame(
                        width: panelWidth,
                        height: panelHeight
                    )
                    .background(RoundedRectangle(cornerRadius: 18).fill(ColorTheme.background))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .padding(.horizontal, sideInset)
                .padding(.top, topInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if showCommentsReviewOverlay {
                    ZStack {
                        Color.black.opacity(0.62)
                            .ignoresSafeArea()
                            .onTapGesture { showCommentsReviewOverlay = false }

                        reviewCard {
                            showCommentsReviewOverlay = false
                        }
                        .frame(width: min(geo.size.width - 32, 340))
                    }
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func syncHostChromeSuppression() {
        suppressHostChrome.wrappedValue =
            showCommentsOverlay ||
            showCommentsReviewOverlay ||
            showAddToList ||
            showBookmarksOverlay ||
            showPlatformsOverlay
    }

    private func reviewCard(onClose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AvatarView(name: authorName.isEmpty ? "User" : authorName, size: 22, avatarURL: authorAvatarUrl)
                Text("\((authorName.isEmpty ? "User" : authorName))’s review")
                    .font(.headline.weight(.bold))
                    .foregroundColor(ColorTheme.text)
                Spacer()
                Button {
                    onClose()
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
            }

            Text(ContentModeration.displayReviewText(gameLog.review))
                .font(.body)
                .foregroundColor(ColorTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(ColorTheme.background))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
        .padding(.horizontal, 12)
    }
    private var headerHero: some View {
        let ids = screenshots.map { $0.imageId }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return ZStack {
            if !ids.isEmpty {
                let idx = currentScreenshotIndex % max(ids.count, 1)
                GameScreenshotImage(id: ids[idx], size: .big, cornerRadius: 0)
                    .frame(height: 198)
                    .clipped()
                    .transition(.opacity)
                    .id(ids[idx])
            } else if didAttemptScreenshotLoad {
                if let coverId = gameLog.cover?.imageId {
                    GameCoverImage(id: coverId, preset: .custom(width: 240), cornerRadius: 0)
                        .frame(height: 198)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(ColorTheme.surface)
                        .frame(height: 198)
                        .overlay(
                            Text("No screenshots available")
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                        )
                }
            } else {
                Rectangle()
                    .fill(ColorTheme.surface)
                    .frame(height: 198)
                    .overlay(ProgressView().tint(ColorTheme.accent))
            }

            LinearGradient(
                gradient: Gradient(colors: [.black.opacity(0.12), .black.opacity(0.35), .black.opacity(0.82)]),
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 198)
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

    private func formattedStatus(_ status: GameStatus) -> String {
        switch status {
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .notPlayed: return "Not Started"
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
        Button {
            let game = Game(
                id: gameLog.gameId,
                name: displayName.isEmpty ? gameName : displayName,
                cover: gameLog.cover,
                firstReleaseDate: nil,
                genres: nil,
                platforms: nil,
                rating: nil,
                ratingCount: nil,
                totalRatingCount: nil,
                screenshots: nil
            )
            onOpenCurrentUserLog?(game)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                if let coverId = gameLog.cover?.imageId {
                    GameCoverImage(id: coverId, preset: .custom(width: 78), cornerRadius: 12)
                        .frame(width: 78, height: 104)
                        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(displayName.isEmpty ? gameName : displayName)
                        .font(.title3.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if !yearString(displayYear).isEmpty {
                            previewMetaPill(yearString(displayYear), tint: .white.opacity(0.12))
                        }
                        if let studio = primaryStudioName, !studio.isEmpty {
                            previewMetaPill(studio, tint: .white.opacity(0.12))
                        }
                    }

                    Text("Open this game to edit your own log or save it for later.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer(minLength: 0)
                        platformCountText
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(userRatingAccent.opacity(0.18))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(userRatingAccent.opacity(0.72), lineWidth: 1.1))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
    }

    private var platformCountText: some View {
        Group {
            if !displayPlatforms.isEmpty {
                let countText = displayPlatforms.count == 1 ? "1 Platform" : "\(displayPlatforms.count) Platforms"
                Button {
                    showPlatformsOverlay = true
                } label: {
                    Text(countText)
                        .font(.caption2)
                        .italic()
                        .foregroundColor(ColorTheme.subtext)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bookmarksOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { showBookmarksOverlay = false }

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    Text("Saved Games")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    Button {
                        showBookmarksOverlay = false
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }

                let currentName = displayName.isEmpty ? gameName : displayName
                let isAlreadySaved = watchlistIds.contains(gameLog.gameId)
                HStack(spacing: 10) {
                    if let cover = gameLog.cover?.imageId {
                        GameCoverImage(id: cover, preset: .custom(width: 40), cornerRadius: 8)
                            .frame(width: 40, height: 56)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ColorTheme.separator.opacity(0.2))
                            .frame(width: 40, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentName)
                            .foregroundColor(ColorTheme.text)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        if !isAlreadySaved {
                            saveCurrentGameToWatchlist()
                        }
                    } label: {
                        Text(isAlreadySaved ? "Saved" : "Save Game")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(isAlreadySaved ? ColorTheme.subtext : ColorTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAlreadySaved || isSavingGame)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))

                HStack {
                    Spacer(minLength: 0)
                    Picker("", selection: $bookmarksSort) {
                        ForEach(BookmarkSort.allCases) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(sortedBookmarks()) { entry in
                            HStack(spacing: 10) {
                                if let coverId = entry.coverId {
                                    GameCoverImage(id: coverId, preset: .custom(width: 34), cornerRadius: 8)
                                        .frame(width: 34, height: 48)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(ColorTheme.separator.opacity(0.2))
                                        .frame(width: 34, height: 48)
                                }
                                Text(entry.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                                    .lineLimit(2)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            .padding(16)
            .frame(width: min(UIScreen.main.bounds.width - 20, 404), height: min(UIScreen.main.bounds.height - 80, 720))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ColorTheme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(ColorTheme.separator, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
        }
    }

    private var platformsOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { showPlatformsOverlay = false }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("All Platforms")
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Button {
                        showPlatformsOverlay = false
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(displayPlatforms, id: \.self) { platform in
                            Text(platform)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            .padding(16)
            .frame(width: min(UIScreen.main.bounds.width - 40, 340))
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ColorTheme.background)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
            )
        }
    }

    private func previewMetaPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundColor(ColorTheme.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var commentComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add a comment…")
                        .font(.body)
                        .foregroundColor(ColorTheme.subtext)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $newComment)
                    .foregroundColor(ColorTheme.text)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 52, maxHeight: 112)
                    .background(Color.clear)
                    .focused($commentFocused)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(ColorTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator.opacity(0.7), lineWidth: 1))

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

    private var commentPillTitle: String {
        let count = comments.count
        return count == 1 ? "1 Comment" : "\(count) Comments"
    }

    private var likePillTitle: String {
        likeCount == 1 ? "1 Like" : "\(likeCount) Likes"
    }

    private var referenceButtonSystemName: String {
        isReferenceSaved ? "doc.badge.checkmark" : "doc.badge.plus"
    }

    private var commentPillSubtitle: String {
        comments.isEmpty ? "Leave the first comment" : "Read and leave a comment"
    }

    private func commentPreviewAuthorName(for comment: ReviewComment) -> String {
        comment.authorName
            ?? commentAuthorNames[comment.userId]
            ?? (comment.userId == gameLog.userId ? authorName : nil)
            ?? "User"
    }

    @ViewBuilder
    private func solidPreviewActionButton(systemName: String, tint: Color = .white, fill: Color = ColorTheme.surface, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(userRatingAccent.opacity(0.58), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private func previewTextActionButton(title: String, systemName: String? = nil, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.footnote.weight(.bold))
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(.black)
            .frame(height: UIStyles.Buttons.compactHeight)
            .frame(minWidth: 102)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                    .fill(ColorTheme.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                    .stroke(userRatingAccent.opacity(0.58), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var logEditedSubtitle: String {
        let sourceDate = gameLog.playDate.dateValue()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: sourceDate))"
    }

    private func openCurrentUserLogAction() {
        let game = Game(
            id: gameLog.gameId,
            name: displayName.isEmpty ? gameName : displayName,
            cover: gameLog.cover,
            firstReleaseDate: nil,
            genres: nil,
            platforms: nil,
            rating: nil,
            ratingCount: nil,
            totalRatingCount: nil,
            screenshots: nil
        )
        if let onOpenCurrentUserLog {
            onOpenCurrentUserLog(game)
        } else {
            currentUserLogGameOverlay = game
        }
    }

    private func authorNameForCurrentUser() -> String {
        if let existing = commentAuthorNames[Auth.auth().currentUser?.uid ?? ""], !existing.isEmpty {
            return existing
        }
        if let authName = Auth.auth().currentUser?.displayName, !authName.isEmpty {
            return authName
        }
        if !authorName.isEmpty, gameLog.userId == Auth.auth().currentUser?.uid {
            return authorName
        }
        return "User"
    }

    private func readableStatus(_ s: GameStatus) -> String {
        switch s {
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .notPlayed: return "Not Started"
        }
    }

    private func loadSavedGameState() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isSavedGame = false
            return
        }
        let ref = db.collection("users").document(uid)
        ref.getDocument(source: .cache) { doc, _ in
            let list = doc?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            DispatchQueue.main.async {
                let ids = Set(list.compactMap { ($0["id"] as? Int) ?? ($0["id"] as? NSNumber)?.intValue })
                self.watchlistIds = ids
                self.isSavedGame = ids.contains(self.gameLog.gameId)
            }
            ref.getDocument { liveDoc, _ in
                let liveList = liveDoc?.data()?["watchlist_games"] as? [[String: Any]] ?? []
                DispatchQueue.main.async {
                    let ids = Set(liveList.compactMap { ($0["id"] as? Int) ?? ($0["id"] as? NSNumber)?.intValue })
                    self.watchlistIds = ids
                    self.isSavedGame = ids.contains(self.gameLog.gameId)
                }
            }
        }
    }

    private func bestEffortPrimaryStudio(from game: Game) -> String? {
        let involvedCompanies = game.involvedCompanies ?? []
        if let publisher = involvedCompanies.first(where: { $0.publisher == true })?.company?.name,
           !publisher.isEmpty {
            return publisher
        }
        if let developer = involvedCompanies.first(where: { $0.developer == true })?.company?.name,
           !developer.isEmpty {
            return developer
        }
        return nil
    }

    private func toggleSavedGame() {
        guard let uid = Auth.auth().currentUser?.uid, !isSavingGame else { return }
        isSavingGame = true
        let userRef = db.collection("users").document(uid)
        userRef.getDocument { doc, error in
            if let error {
                DispatchQueue.main.async {
                    self.errorText = error.localizedDescription
                    self.isSavingGame = false
                }
                return
            }
            var list = doc?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            if let index = list.firstIndex(where: {
                (($0["id"] as? Int) ?? (($0["id"] as? NSNumber)?.intValue ?? -1)) == self.gameLog.gameId
            }) {
                list.remove(at: index)
            } else {
                var payload: [String: Any] = [
                    "id": self.gameLog.gameId,
                    "name": self.displayName.isEmpty ? self.gameName : self.displayName,
                    "added_at": Timestamp(date: Date())
                ]
                if let cover = self.gameLog.cover?.imageId {
                    payload["cover"] = [
                        "id": self.gameLog.cover?.id as Any,
                        "image_id": cover
                    ]
                }
                list.insert(payload, at: 0)
            }
            userRef.setData(["watchlist_games": list], merge: true) { writeError in
                DispatchQueue.main.async {
                    self.isSavingGame = false
                    if let writeError {
                        self.errorText = writeError.localizedDescription
                    } else {
                        self.isSavedGame = list.contains {
                            (($0["id"] as? Int) ?? (($0["id"] as? NSNumber)?.intValue ?? -1)) == self.gameLog.gameId
                        }
                        self.showSavedGameToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.showSavedGameToast = false
                        }
                        Haptics.success()
                    }
                }
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
            let entries: [BookmarkEntry] = list.compactMap { dict in
                guard let id = dict["id"] as? Int ?? (dict["id"] as? NSNumber)?.intValue else { return nil }
                let name = dict["name"] as? String ?? "Game #\(id)"
                let coverId = (dict["cover"] as? [String: Any])?["image_id"] as? String ?? dict["cover_id"] as? String
                let addedAt = (dict["added_at"] as? Timestamp)?.dateValue()
                return BookmarkEntry(id: id, name: name, coverId: coverId, addedAt: addedAt)
            }
            await MainActor.run {
                bookmarksList = entries
                watchlistIds = Set(entries.map(\.id))
                isSavedGame = watchlistIds.contains(gameLog.gameId)
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }

    private func sortedBookmarks() -> [BookmarkEntry] {
        switch bookmarksSort {
        case .recent:
            return bookmarksList.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .az:
            return bookmarksList.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func saveCurrentGameToWatchlist() {
        guard let uid = Auth.auth().currentUser?.uid, !isSavingGame else { return }
        isSavingGame = true
        let userRef = db.collection("users").document(uid)
        userRef.getDocument { doc, error in
            if let error {
                DispatchQueue.main.async {
                    errorText = error.localizedDescription
                    isSavingGame = false
                }
                return
            }
            var list = doc?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            guard !list.contains(where: { (($0["id"] as? Int) ?? (($0["id"] as? NSNumber)?.intValue ?? -1)) == gameLog.gameId }) else {
                DispatchQueue.main.async { isSavingGame = false }
                return
            }
            var payload: [String: Any] = [
                "id": gameLog.gameId,
                "name": displayName.isEmpty ? gameName : displayName,
                "added_at": Timestamp(date: Date())
            ]
            if let cover = gameLog.cover?.imageId {
                payload["cover"] = [
                    "id": gameLog.cover?.id as Any,
                    "image_id": cover
                ]
            }
            list.insert(payload, at: 0)
            userRef.setData(["watchlist_games": list], merge: true) { writeError in
                DispatchQueue.main.async {
                    isSavingGame = false
                    if let writeError {
                        errorText = writeError.localizedDescription
                    } else {
                        isSavedGame = true
                        let newEntry = BookmarkEntry(id: gameLog.gameId, name: displayName.isEmpty ? gameName : displayName, coverId: gameLog.cover?.imageId, addedAt: Date())
                        bookmarksList.removeAll { $0.id == gameLog.gameId }
                        bookmarksList.insert(newEntry, at: 0)
                        watchlistIds.insert(gameLog.gameId)
                        Haptics.success()
                    }
                }
            }
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
        if let metadata = fullGameMetadata {
            applySupplementalMetadata(metadata)
            return
        }
        loadSupplementalGameMetadataIfNeeded()
    }

    private func loadScreenshots() {
        if let metadata = fullGameMetadata {
            screenshots = metadata.screenshots ?? []
            didAttemptScreenshotLoad = true
            return
        }
        loadSupplementalGameMetadataIfNeeded()
    }

    private func loadSupplementalGameMetadataIfNeeded() {
        guard fullGameMetadata == nil, !isFetchingFullGameMetadata else {
            if let metadata = fullGameMetadata {
                applySupplementalMetadata(metadata)
            }
            return
        }
        isFetchingFullGameMetadata = true
        igdb.fetchGameById(id: gameLog.gameId) { result in
            DispatchQueue.main.async {
                self.isFetchingFullGameMetadata = false
                switch result {
                case .success(let g):
                    self.fullGameMetadata = g
                    self.applySupplementalMetadata(g)
                case .failure:
                    self.screenshots = []
                    self.didAttemptScreenshotLoad = true
                }
            }
        }
    }

    private func applySupplementalMetadata(_ g: Game) {
        if displayName.gl_isPlaceholderForId(gameLog.gameId) || displayName.isEmpty {
            displayName = g.name
        }
        if displayYear == nil {
            displayYear = g.computedReleaseYear
        }
        if displayPlatforms.isEmpty {
            displayPlatforms = g.prioritizedPlatformNames(prefix: 8)
        }
        if primaryStudioName == nil {
            primaryStudioName = bestEffortPrimaryStudio(from: g)
        }
        screenshots = g.screenshots ?? []
        didAttemptScreenshotLoad = true
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

    private func loadLikeState() {
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        guard !currentUserId.isEmpty else {
            likeCount = 0
            isLikedByCurrentUser = false
            return
        }
        InteractionService.shared.fetchLikeState(logId: gameLog.id, currentUserId: currentUserId) { result in
            switch result {
            case .success(let state):
                likeCount = state.count
                isLikedByCurrentUser = state.isLiked
            case .failure:
                break
            }
        }
    }

    private func loadReferenceState() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let refId = "\(uid)_\(gameLog.id)"
        db.collection("users").document(uid).getDocument { snap, error in
            DispatchQueue.main.async {
                guard !isSavingReference else { return }
                if let error {
                    errorText = error.localizedDescription
                }
                let refs = snap?.data()?["log_references"] as? [[String: Any]] ?? []
                isReferenceSaved = refs.contains { ($0["id"] as? String) == refId }
            }
        }
    }

    private func toggleReferenceSaved() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        errorText = ""
        let refId = "\(uid)_\(gameLog.id)"
        let userRef = db.collection("users").document(uid)
        if isReferenceSaved {
            isSavingReference = true
            isReferenceSaved = false
            userRef.getDocument { snap, error in
                if let error {
                    DispatchQueue.main.async {
                        isSavingReference = false
                        isReferenceSaved = true
                        errorText = error.localizedDescription
                    }
                    return
                }
                var refs = snap?.data()?["log_references"] as? [[String: Any]] ?? []
                refs.removeAll { ($0["id"] as? String) == refId }
                userRef.setData(["log_references": refs], merge: true) { error in
                    DispatchQueue.main.async {
                        isSavingReference = false
                        if let error {
                            isReferenceSaved = true
                            errorText = error.localizedDescription
                            return
                        }
                        UserDefaults.standard.set(glSerializeReferencePayloadsForCache(refs), forKey: glReferenceCacheKey(for: uid))
                        NotificationCenter.default.post(name: .referencesUpdated, object: nil, userInfo: ["user_id": uid])
                    }
                }
            }
            return
        }

        let preview = (gameLog.review ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = [
            "id": refId,
            "user_id": uid,
            "log_id": gameLog.id,
            "log_owner_id": gameLog.userId,
            "game_id": gameLog.gameId,
            "game_name": gameName,
            "added_at": Timestamp(date: Date())
        ]
        if let coverId = gameLog.cover?.imageId, !coverId.isEmpty {
            payload["cover_id"] = coverId
        }
        if !authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["author_name"] = authorName
        }
        if let authorAvatarUrl, !authorAvatarUrl.isEmpty {
            payload["author_avatar_url"] = authorAvatarUrl
        }
        if let rating = gameLog.rating {
            payload["rating"] = rating
        }
        if !preview.isEmpty {
            payload["review_preview"] = String(preview.prefix(140))
        }

        isSavingReference = true
        isReferenceSaved = true
        userRef.getDocument { snap, error in
            if let error {
                DispatchQueue.main.async {
                    isSavingReference = false
                    isReferenceSaved = false
                    errorText = error.localizedDescription
                }
                return
            }
            var refs = snap?.data()?["log_references"] as? [[String: Any]] ?? []
            refs.removeAll { ($0["id"] as? String) == refId }
            refs.insert(payload, at: 0)
            userRef.setData(["log_references": refs], merge: true) { error in
                DispatchQueue.main.async {
                    isSavingReference = false
                    if let error {
                        isReferenceSaved = false
                        errorText = error.localizedDescription
                        return
                    }
                    UserDefaults.standard.set(glSerializeReferencePayloadsForCache(refs), forKey: glReferenceCacheKey(for: uid))
                    NotificationCenter.default.post(name: .referencesUpdated, object: nil, userInfo: ["user_id": uid])
                }
            }
        }
    }

    private func openLikesOverlay() {
        showLikesOverlay = true
        loadLikers()
    }

    private func loadLikers() {
        isLoadingLikers = true
        db.collection("review_likes")
            .whereField("log_id", isEqualTo: gameLog.id)
            .order(by: "created_at", descending: true)
            .getDocuments { snap, _ in
                let docs = snap?.documents ?? []
                let likeDocs: [(userId: String, createdAt: Timestamp, inlineName: String?, inlineAvatar: String?)] = docs.compactMap { doc in
                    guard let userId = doc.data()["user_id"] as? String,
                          let createdAt = doc.data()["created_at"] as? Timestamp else { return nil }
                    return (
                        userId,
                        createdAt,
                        doc.data()["author_name"] as? String,
                        doc.data()["author_avatar_url"] as? String
                    )
                }
                if likeDocs.isEmpty {
                    DispatchQueue.main.async {
                        likers = []
                        isLoadingLikers = false
                    }
                    return
                }

                let uniqueIds = Array(Set(likeDocs.map(\.userId)))
                let group = DispatchGroup()
                var fetchedUsers: [String: (name: String, avatar: String?)] = [:]
                let resultQueue = DispatchQueue(label: "gamerlnd.likers.fetch")

                for chunkStart in stride(from: 0, to: uniqueIds.count, by: 10) {
                    let chunk = Array(uniqueIds[chunkStart..<min(chunkStart + 10, uniqueIds.count)])
                    group.enter()
                    db.collection("users")
                        .whereField("id", in: chunk)
                        .getDocuments { snap, _ in
                            for doc in snap?.documents ?? [] {
                                let data = doc.data()
                                let uid = (data["id"] as? String) ?? doc.documentID
                                let name = (data["display_name"] as? String)
                                    ?? (data["username"] as? String)
                                    ?? (data["email"] as? String)
                                    ?? "User"
                                resultQueue.sync {
                                    fetchedUsers[uid] = (name, UserRecordAvatarResolver.url(from: data))
                                }
                            }
                            group.leave()
                        }
                }

                group.notify(queue: .main) {
                    let fetched: [LogLiker] = likeDocs.map { entry in
                        let name = fetchedUsers[entry.userId]?.name
                            ?? entry.inlineName
                            ?? "User"
                        let avatar = fetchedUsers[entry.userId]?.avatar
                            ?? entry.inlineAvatar
                        return LogLiker(userId: entry.userId, displayName: name, avatarUrl: avatar, createdAt: entry.createdAt)
                    }
                    likers = fetched.sorted { $0.createdAt.dateValue() > $1.createdAt.dateValue() }
                    isLoadingLikers = false
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
                    return ReviewComment(
                        id: id,
                        logId: logId,
                        userId: uid,
                        text: text,
                        createdAt: ts,
                        authorName: data["author_name"] as? String,
                        authorAvatarUrl: data["author_avatar_url"] as? String
                    )
                }
                self.comments = list
                hydrateCommentAuthors(for: list)
            }
    }

    private func hydrateCommentAuthors(for list: [ReviewComment]) {
        for comment in list {
            if let authorName = comment.authorName, !authorName.isEmpty {
                commentAuthorNames[comment.userId] = authorName
            }
            if let avatar = comment.authorAvatarUrl, !avatar.isEmpty {
                commentAuthorAvatars[comment.userId] = avatar
            }
        }

        let missingIds = Array(Set(list.map(\.userId))).filter {
            let hasName = !(commentAuthorNames[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return !hasName
        }
        guard !missingIds.isEmpty else { return }

        let chunks = stride(from: 0, to: missingIds.count, by: 10).map {
            Array(missingIds[$0..<min($0 + 10, missingIds.count)])
        }

        for chunk in chunks {
            db.collection("users")
                .whereField("id", in: chunk)
                .getDocuments { snap, _ in
                    for doc in snap?.documents ?? [] {
                        let data = doc.data()
                        guard let uid = data["id"] as? String else { continue }
                        let name = (data["display_name"] as? String)
                            ?? (data["username"] as? String)
                            ?? (data["email"] as? String)
                            ?? "User"
                        commentAuthorNames[uid] = name
                        if let avatar = UserRecordAvatarResolver.url(from: data), !avatar.isEmpty {
                            commentAuthorAvatars[uid] = avatar
                        }
                    }
                }
        }
    }

    private func loadCurrentUserLogState() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        if gameLog.userId == uid {
            hasCurrentUserLogForGame = true
            CurrentUserLogPresenceStore.set(true, userId: uid, gameId: gameLog.gameId)
            return
        }

        if let cached = CurrentUserLogPresenceStore.contains(userId: uid, gameId: gameLog.gameId) {
            hasCurrentUserLogForGame = cached
        }

        let query = db.collection("game_logs")
            .whereField("user_id", isEqualTo: uid)
            .whereField("game_id", isEqualTo: gameLog.gameId)
            .limit(to: 1)

        query.getDocuments(source: .cache) { snap, _ in
            let hasLog = !(snap?.documents.isEmpty ?? true)
            if hasLog {
                DispatchQueue.main.async {
                    CurrentUserLogPresenceStore.set(true, userId: uid, gameId: gameLog.gameId)
                    hasCurrentUserLogForGame = true
                }
            }
        }

        query.getDocuments { snap, _ in
            let hasLog = !(snap?.documents.isEmpty ?? true)
            DispatchQueue.main.async {
                CurrentUserLogPresenceStore.set(hasLog, userId: uid, gameId: gameLog.gameId)
                hasCurrentUserLogForGame = hasLog
            }
        }
    }

    private func sendComment() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        let cid = UUID().uuidString
        let currentUser = Auth.auth().currentUser
        var payload: [String: Any] = [
            "id": cid,
            "log_id": gameLog.id,
            "user_id": uid,
            "text": trimmed,
            "created_at": Timestamp(date: Date())
        ]
        let authorName = currentUser?.displayName ?? authorNameForCurrentUser()
        if !authorName.isEmpty {
            payload["author_name"] = authorName
        }
        if let avatarURL = currentUser?.photoURL?.absoluteString, !avatarURL.isEmpty {
            payload["author_avatar_url"] = avatarURL
        }
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
            RewardService.shared.recordGamificationEvent(
                RewardService.GamificationEvent(
                    userId: uid,
                    kind: .commentLog,
                    gameId: self.gameLog.gameId,
                    releaseYear: nil,
                    reviewLength: nil,
                    ratingValue: nil,
                    searchQuery: nil,
                    sessionId: RewardService.activeSessionId,
                    occurredAt: Date()
                )
            )
            NotificationCenter.default.post(
                name: .logCommentsUpdated,
                object: nil,
                userInfo: ["log_id": self.gameLog.id]
            )
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
    let cachedUsername: String?
    let cachedAvatarUrl: String?
    var onReport: (() -> Void)? = nil

    @State private var username: String
    @State private var avatarUrl: String?
    private let db = Firestore.firestore()

    init(comment: ReviewComment, cachedUsername: String? = nil, cachedAvatarUrl: String? = nil, onReport: (() -> Void)? = nil) {
        self.comment = comment
        self.cachedUsername = cachedUsername
        self.cachedAvatarUrl = cachedAvatarUrl
        self.onReport = onReport
        _username = State(initialValue: cachedUsername ?? comment.authorName ?? "User")
        _avatarUrl = State(initialValue: cachedAvatarUrl ?? comment.authorAvatarUrl)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    Text(ContentModeration.displayCommentText(comment.text))
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
            Rectangle()
                .fill(ColorTheme.separator.opacity(0.24))
                .frame(height: 0.5)
        }
        .padding(.vertical, 4)
        .onAppear(perform: fetchUsername)
    }

    private func fetchUsername() {
        if let cachedUsername, !cachedUsername.isEmpty {
            username = cachedUsername
        }
        if let cachedAvatarUrl, !cachedAvatarUrl.isEmpty {
            avatarUrl = cachedAvatarUrl
        }
        if (cachedUsername?.isEmpty == false || comment.authorName?.isEmpty == false),
           (cachedAvatarUrl?.isEmpty == false || comment.authorAvatarUrl?.isEmpty == false) {
            return
        }
        db.collection("users").document(comment.userId).getDocument { doc, _ in
            let data = doc?.data() ?? [:]
            let name = (data["display_name"] as? String)
                ?? (data["username"] as? String)
                ?? (data["email"] as? String)
                ?? "User"
            self.username = name
            if let avatar = UserRecordAvatarResolver.url(from: data), !avatar.isEmpty {
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

private struct LogLiker: Identifiable {
    let userId: String
    let displayName: String
    let avatarUrl: String?
    let createdAt: Timestamp

    var id: String { userId }
}

private struct LikerRow: View {
    let liker: LogLiker

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(name: liker.displayName, size: 24, avatarURL: liker.avatarUrl)
            VStack(alignment: .leading, spacing: 2) {
                Text(liker.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                Text(fullDate(liker.createdAt.dateValue()))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(ColorTheme.subtext)
            }
            Spacer()
            Image(systemName: "hand.thumbsup.fill")
                .font(.footnote.weight(.semibold))
                .foregroundColor(ColorTheme.accent)
        }
        .padding(.vertical, 6)
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
