// GameDetailView.swift
// Game detail + logging UI (full file)
//
// THIS PASS:
// • Single action row (Add to Lists + Save Log) is fixed just under the info card (no bottom inset / no duplicates).
// • Info card shows Title + Release Year + Platforms + Publisher (safe Mirror traversal, no KVC).
// • Hearts fill left→right and align to the slider.
// • Draft flow stores game_name so DraftsView & edits show the title.
// • ADDED: Haptics on key actions, ReviewPromptManager call after successful save, analytics screen + save events.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GameDetailView: View {
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

    // Selected IGDB game
    let game: Game
    var compactOverlay: Bool = false
    var hostedInOverlay: Bool = false
    var suppressHostChrome: Binding<Bool> = .constant(false)
    var onRequestClose: (() -> Void)? = nil
    var externalDismissRequestID: Int = 0
    var startWithExistingLog: Bool = false

    @Environment(\.dismiss) private var dismiss
    // USER INPUT
    @State private var rating: Double = 0.0
    @State private var review: String = ""
    @State private var reviewContainsSpoilers: Bool = false
    @State private var status: GameStatus = .inProgress

    // AGGREGATES
    @State private var avgRating: Double? = nil
    @State private var ratingsCount: Int = 0
    @State private var reviewsCount: Int = 0

    // MEDIA
    @State private var screenshots: [Game.Screenshot] = []
    @State private var didAttemptScreenshotLoad: Bool = false
    // @State private var showScreens: Bool = false
    @State private var currentScreenshotIndex: Int = 0

    // SAVE/DRAFT
    @State private var hasUnsavedChanges: Bool = false
    @State private var showDraftPrompt: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorText: String = ""
    @State private var hasExistingLog: Bool = false
    @State private var isEditingExistingLog: Bool = false
    @State private var hadExistingRatingBeforeEdit: Bool = false
    @State private var hadExistingReviewBeforeEdit: Bool = false
    @State private var showSavedToast: Bool = false
    @State private var showReviewComposer: Bool = false
    @State private var showReviewDraftPrompt: Bool = false
    @State private var showDeleteLogConfirm: Bool = false
    @State private var reviewComposerSnapshot: String = ""
    @State private var reviewComposerSpoilerSnapshot: Bool = false
    @FocusState private var reviewEditorFocused: Bool
    @State private var isSavedGame: Bool = false
    @State private var isSavingSavedGame: Bool = false
    @State private var reviewComposerKeyboardHeight: CGFloat = 0
    @State private var showBookmarksOverlay: Bool = false
    @State private var bookmarksList: [BookmarkEntry] = []
    @State private var watchlistIds: Set<Int> = []
    @State private var bookmarksSort: BookmarkSort = .recent
    @State private var isLoadingLogState: Bool = false

    // LISTS
    @State private var showAddToList: Bool = false

    // DISPLAY METADATA (can be enriched via IGDB)
    @State private var displayName: String = ""
    @State private var displayYear: Int? = nil
    @State private var displayPlatforms: [String] = []
    @State private var showPlatformsOverlay: Bool = false
    @State private var publisherName: String? = nil
    @State private var primaryStudioName: String? = nil
    @State private var fullGameMetadata: Game? = nil
    @State private var isFetchingFullGameMetadata: Bool = false
    @State private var didTrackGamificationView: Bool = false

    private let db = Firestore.firestore()
    private let igdb = IGDBService()
    private var canEditExistingLog: Bool { !hasExistingLog || isEditingExistingLog }
    private var shouldSuppressHostChrome: Bool {
        showReviewComposer || showPlatformsOverlay || showAddToList || showBookmarksOverlay
    }

    var body: some View {
        VStack(spacing: 0) {

            // 1) HERO HEADER
            headerHero

            // 2) INFO CARD
            infoCard
                .padding(.horizontal, 16)
                .offset(y: compactOverlay ? -24 : -28)
                .zIndex(2)

            // 3) Action row directly under the info card (single source of truth)
            HStack(spacing: 12) {
                saveButton
                addToListsButton
                saveGameButton
                if hasExistingLog {
                    logMoreMenu
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, compactOverlay ? 2 : 6)
            .offset(y: compactOverlay ? -18 : -22)

            if !errorText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(ColorTheme.highlight)
                    if let user = Auth.auth().currentUser, !user.isEmailVerified {
                        Button {
                            user.sendEmailVerification(completion: nil)
                            errorText = "Verification email sent. Check your inbox."
                        } label: {
                            Text("Resend verification email")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ColorTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .offset(y: -18)
            }

            // 4) BODY
            if isLoadingLogState {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(ColorTheme.accent)
                    Text("Loading your log…")
                        .font(.caption)
                        .foregroundColor(ColorTheme.subtext)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .padding(.bottom, compactOverlay ? 16 : 24)
            } else {
                VStack(alignment: .leading, spacing: compactOverlay ? 14 : 18) {
                    if hasExistingLog {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Text("Your game log")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(ColorTheme.text)
                                Spacer()
                                if isEditingExistingLog {
                                    Text("Editing")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(ColorTheme.subtext)
                                }
                            }

                            if !isEditingExistingLog {
                                Text("Read-only. Tap Edit Log to update.")
                                    .font(.caption)
                                    .foregroundColor(Color("SecondaryHighlightColor"))
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    // Community average
                    if let avg = avgRating, ratingsCount > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                openRatingsOverlay(avg: avg)
                            } label: {
                                HStack(spacing: 10) {
                                    AverageHeartBadge(value: avg, size: 28)
                                    Text("\(ratingsCount) ratings")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(ColorTheme.subtext)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Your rating
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your Rating")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)

                        HStack(alignment: .center, spacing: 12) {
                            GeometryReader { geo in
                                VStack(spacing: compactOverlay ? 6 : 8) {
                                    HeartRatingBarAligned(
                                        value: $rating,
                                        totalWidth: geo.size.width,
                                        spacing: UIStyles.RatingHeart.spacingPrimary
                                    )
                                    Slider(value: $rating, in: 0...10, step: 0.1)
                                        .tint(ColorTheme.ratingBandColor(for: rating))
                                        .frame(width: geo.size.width)
                                        .onChange(of: rating) { _, _ in Haptics.softImpact() }
                                }
                            }
                            .frame(height: 60)

                            Text(formatRatingValue(rating))
                                .font(.title2.monospacedDigit().weight(.semibold))
                                .foregroundColor(ColorTheme.ratingBandColor(for: rating))
                                .frame(minWidth: 56, alignment: .trailing)
                        }
                        .onChange(of: rating) { _, _ in
                            if canEditExistingLog {
                                hasUnsavedChanges = true
                            }
                        }
                        .disabled(!canEditExistingLog)

                        if ratingsCount == 0 {
                            Text("Be the first to rate this game!")
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                        }
                    }

                    // Your review
                    VStack(alignment: .leading, spacing: compactOverlay ? 6 : 8) {
                        Text("Your Review")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)

                        Button {
                            guard canEditExistingLog else { return }
                            openReviewComposer()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Write Review" : "Edit Review")
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(ColorTheme.text)
                                    Text(reviewPreviewText)
                                        .font(.caption)
                                        .foregroundColor(reviewContainsSpoilers && !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ColorTheme.accent : ColorTheme.subtext)
                                        .lineLimit(3)
                                }
                                Spacer()
                                Image(systemName: "square.and.pencil")
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(ColorTheme.accent)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEditExistingLog)

                        if reviewsCount == 0 {
                            Text("Be the first to review this game!")
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                        }
                    }

                    // Status
                    VStack(alignment: .leading, spacing: compactOverlay ? 6 : 8) {
                        Text("Status")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)

                        Picker("Status", selection: $status) {
                            Text("In Progress").tag(GameStatus.inProgress)
                            Text("Completed").tag(GameStatus.completed)
                            Text("Not Started").tag(GameStatus.notPlayed)
                        }
                        .pickerStyle(.segmented)
                        .tint(ColorTheme.accent)
                        .onChange(of: status) { _, _ in
                            if canEditExistingLog {
                                hasUnsavedChanges = true
                                Haptics.tap()
                            }
                        }
                        .disabled(!canEditExistingLog)
                    }

                    // Screenshots now handled in header
                }
                .padding(.horizontal, 16)
                .padding(.bottom, compactOverlay ? 28 : 30)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, hostedInOverlay ? 0 : (compactOverlay ? 0 : 80))
        .background((hostedInOverlay ? Color.clear : ColorTheme.background).ignoresSafeArea())
        .overlay {
            if showReviewComposer {
                reviewComposerOverlay
            } else if showPlatformsOverlay {
                platformsOverlay
            } else if showAddToList, let uid = Auth.auth().currentUser?.uid {
                ZStack {
                    OverlayBackdrop()
                        .ignoresSafeArea()
                        .onTapGesture { showAddToList = false }

                    AddToListSheet(ownerId: uid, game: game) {
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
            }
        }
        .overlay(alignment: .topTrailing) {
            if compactOverlay && !hostedInOverlay && !showReviewComposer {
                Button {
                    handleDismissAttempt()
                } label: {
                    OverlayCloseButton()
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .navigationBarBackButtonHidden(hostedInOverlay ? false : hasUnsavedChanges)
        .toolbar {
            if !hostedInOverlay {
                ToolbarItem(placement: .principal) { AppIconCentered() }
                ToolbarItem(placement: .navigationBarLeading) {
                    if hasUnsavedChanges {
                        Button {
                            Haptics.tap()
                            handleDismissAttempt()
                        } label: {
                            HStack { Image(systemName: "chevron.left"); Text("Back") }
                        }
                        .foregroundColor(ColorTheme.accent)
                    }
                }
            }
        }
        .onAppear {
            AnalyticsService.shared.screen("game_detail")
            if !didTrackGamificationView {
                didTrackGamificationView = true
                RewardService.shared.recordViewedGame(gameId: game.id, releaseYear: game.computedReleaseYear)
            }
        }
        .confirmationDialog("Save draft before leaving?", isPresented: $showDraftPrompt, titleVisibility: .visible) {
            Button("Save Draft") { Haptics.commit(); saveDraftAndDismiss() }
            Button("Leave Without Saving", role: .destructive) { Haptics.tap(); closeView() }
            Button("Keep Editing", role: .cancel) { }
        }
        .confirmationDialog("Save review draft?", isPresented: $showReviewDraftPrompt, titleVisibility: .visible) {
            Button("Save Draft") { saveReviewDraftOnly() }
            Button("Leave Without Saving", role: .destructive) {
                review = reviewComposerSnapshot
                reviewContainsSpoilers = reviewComposerSpoilerSnapshot
                reviewEditorFocused = false
                showReviewComposer = false
            }
            Button("Keep Editing", role: .cancel) { }
        }
        .alert("Delete Log?", isPresented: $showDeleteLogConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteLog()
            }
        } message: {
            Text("This will delete your rating, review, and log for this game.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                KeyboardDismissAccessoryButton {
                    reviewEditorFocused = false
                }
            }
        }
        .onChange(of: externalDismissRequestID) { _, _ in
            handleDismissAttempt()
        }
        .onAppear {
            hasExistingLog = startWithExistingLog
            isEditingExistingLog = false
            isLoadingLogState = startWithExistingLog
            // Base display info from incoming Game
            self.displayName = game.name
            self.displayYear = game.computedReleaseYear
            self.displayPlatforms = game.prioritizedPlatformNames
            self.primaryStudioName = bestEffortPrimaryStudio(from: game)
            // Fetch once and reuse for screenshots + metadata.
            loadSupplementalGameMetadataIfNeeded()
            loadExistingLogIfAny()
            loadDraftIfAny()
            loadAverageAndCounts()
            loadSavedGameState()
        }
        .onChange(of: shouldSuppressHostChrome) { _, newValue in
            suppressHostChrome.wrappedValue = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard showReviewComposer,
                  let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            let screenHeight = UIScreen.main.bounds.height
            let overlap = max(0, screenHeight - frame.origin.y)
            reviewComposerKeyboardHeight = overlap
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            reviewComposerKeyboardHeight = 0
        }
        .onDisappear {
            suppressHostChrome.wrappedValue = false
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Header & Info Card

    private var headerHero: some View {
        let ids = screenshots.map { $0.imageId }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let headerHeight = compactOverlay ? CGFloat(184) : UIStyles.Art.headerHeight
        return ZStack {
            if !ids.isEmpty {
                let idx = currentScreenshotIndex % max(ids.count, 1)
                GameScreenshotImage(id: ids[idx], size: .big, cornerRadius: 0)
                    .frame(height: headerHeight)
                    .clipped()
                    .transition(.opacity)
                    .id(ids[idx])
            } else {
                Rectangle()
                    .fill(ColorTheme.surface)
                    .frame(height: headerHeight)
                    .overlay(
                        Group {
                            if didAttemptScreenshotLoad {
                                Text("No screenshots available")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.subtext)
                            } else {
                                ProgressView().tint(ColorTheme.accent)
                            }
                        }
                    )
            }

            LinearGradient(
                gradient: Gradient(colors: [.black.opacity(0.12), .black.opacity(0.34), .black.opacity(0.82)]),
                startPoint: .center, endPoint: .bottom
            )
            .frame(height: headerHeight)
        }
        .overlay(alignment: .center) {
            screenshotHeaderControls(idsCount: ids.count)
        }
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
        withAnimation(.easeInOut(duration: 0.35)) {
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
                    .background(Circle().fill(Color.black.opacity(0.4)))
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
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .opacity(idsCount > 1 ? 1 : 0.35)
        }
        .padding(.horizontal, 16)
    }


    private var infoCard: some View {
        HStack(alignment: .top, spacing: 14) {
            if let imgId = game.cover?.imageId ?? game.screenshots?.first?.imageId {
                GameCoverImage(id: imgId, preset: .custom(width: 88), cornerRadius: 12)
                    .frame(width: 88, height: 118)
                    .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 6)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(displayName.isEmpty ? game.name : displayName)
                    .font(.headline.weight(.bold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let y = displayYear {
                        editorMetaPill(String(y), tint: .white.opacity(0.08), foreground: ColorTheme.text)
                    }
                    if let studio = primaryStudioName, !studio.isEmpty {
                        editorMetaPill(studio, tint: .white.opacity(0.08), foreground: ColorTheme.text)
                    }
                }

                Text("Shape your rating, review, and status here — this becomes your card across GamerLnd.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer(minLength: 0)
                    editorPlatformCountText
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 6)
    }

    private var editorPlatformCountText: some View {
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

                let isAlreadySaved = watchlistIds.contains(game.id)
                HStack(spacing: 10) {
                    if let cover = game.cover?.imageId {
                        GameCoverImage(id: cover, preset: .custom(width: 40), cornerRadius: 8)
                            .frame(width: 40, height: 56)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ColorTheme.separator.opacity(0.2))
                            .frame(width: 40, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName.isEmpty ? game.name : displayName)
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
                    .disabled(isAlreadySaved || isSavingSavedGame)
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

    private func editorMetaPill(_ text: String, tint: Color, foreground: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundColor(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Buttons (single row under card)

    private var saveButtonTitle: String {
        if hasExistingLog && !isEditingExistingLog { return "Edit" }
        return "Save"
    }

    private var saveButton: some View {
        Button {
            if hasExistingLog && !isEditingExistingLog {
                isEditingExistingLog = true
                Haptics.tap()
                return
            }
            Haptics.commit()
            saveLog()
        } label: {
            ZStack {
                HStack(spacing: 8) {
                    if isSaving { ProgressView().tint(saveButtonTextColor) }
                    Text(saveButtonTitle)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .foregroundColor(saveButtonTextColor)
                }
                .opacity(showSavedToast ? 0 : 1)

                if showSavedToast {
                    Text("Saved")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.9))
                        .transition(.opacity)
                }
            }
            .frame(height: UIStyles.Buttons.compactHeight)
            .frame(width: hasExistingLog ? 114 : 106)
            .padding(.horizontal, 12)
            .background(saveButtonBackgroundColor)
            .foregroundColor(saveButtonTextColor)
            .cornerRadius(UIStyles.Buttons.primaryCorner)
            .overlay(
                RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                    .stroke(ColorTheme.separator.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(isSaving)
        .accessibilityLabel("Save your log for this game")
    }

    private var saveGameButton: some View {
        Button {
            Haptics.tap()
            openBookmarksOverlay()
        } label: {
            Image(systemName: isSavedGame ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.headline.weight(.semibold))
                .foregroundColor(isSavedGame ? ColorTheme.accent : .white)
                .frame(width: UIStyles.Buttons.compactHeight, height: UIStyles.Buttons.compactHeight)
                .background(
                    RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                        .fill(isSavedGame ? ColorTheme.accent.opacity(0.14) : ColorTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                        .stroke(ColorTheme.separator, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isSavingSavedGame)
        .accessibilityLabel(isSavedGame ? "Saved game options" : "Save game")
    }

    private var saveButtonBackgroundColor: Color {
        if hasExistingLog && !isEditingExistingLog {
            return ColorTheme.surface
        }
        return ColorTheme.xpGreen
    }

    private var saveButtonTextColor: Color {
        if hasExistingLog && !isEditingExistingLog {
            return ColorTheme.text
        }
        return .white
    }

    private var addToListsButton: some View {
        Button {
            Haptics.tap()
            showAddToList = true
        } label: {
            Image(systemName: "text.badge.plus")
                .font(.headline.weight(.semibold))
                .frame(width: UIStyles.Buttons.compactHeight, height: UIStyles.Buttons.compactHeight)
                .background(
                    RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                        .fill(ColorTheme.surface)
                )
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                        .stroke(ColorTheme.separator, lineWidth: 1)
                )
        }
        .accessibilityLabel("Add this game to your custom lists")
    }

    private var logMoreMenu: some View {
        Menu {
            Button(role: .destructive) {
                showDeleteLogConfirm = true
            } label: {
                Label("Delete Log", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.weight(.bold))
                .foregroundColor(ColorTheme.subtext)
                .frame(width: UIStyles.Buttons.compactHeight, height: UIStyles.Buttons.compactHeight)
                .background(
                    RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                        .fill(ColorTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                        .stroke(ColorTheme.separator, lineWidth: 1)
                )
        }
    }

    // MARK: - Firestore Loads

    private func loadExistingLogIfAny() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoadingLogState = false
            return
        }
        let docId = "\(uid)_\(game.id)"
        let ref = db.collection("game_logs").document(docId)

        func apply(_ d: [String: Any]) {
            hasExistingLog = true
            isEditingExistingLog = false
            if let r = d["rating"] as? Double {
                rating = r
                hadExistingRatingBeforeEdit = r > 0
            } else if let r = d["rating"] as? Int {
                rating = Double(r)
                hadExistingRatingBeforeEdit = r > 0
            } else {
                hadExistingRatingBeforeEdit = false
            }
            if let rev = d["review"] as? String {
                review = rev
                hadExistingReviewBeforeEdit = !rev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } else {
                hadExistingReviewBeforeEdit = false
            }
            reviewContainsSpoilers = d["review_contains_spoilers"] as? Bool ?? false
            if let s = d["status"] as? String, let gs = GameStatus(rawValue: s) { status = gs }
        }

        ref.getDocument(source: .cache) { snap, _ in
            if let d = snap?.data() {
                DispatchQueue.main.async {
                    apply(d)
                    isLoadingLogState = false
                }
            }
            ref.getDocument { liveSnap, _ in
                DispatchQueue.main.async {
                    if let d = liveSnap?.data() {
                        apply(d)
                    }
                    isLoadingLogState = false
                }
            }
        }
    }

    private func loadDraftIfAny() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let draftId = "draft_\(uid)_\(game.id)"
        let ref = db.collection("drafts").document(draftId)

        func apply(_ d: [String: Any]) {
            if let r = d["rating"] as? Double { rating = r }
            if let rI = d["rating"] as? Int { rating = Double(rI) }
            if let rev = d["review"] as? String { review = rev }
            reviewContainsSpoilers = d["review_contains_spoilers"] as? Bool ?? false
            if let s = d["status"] as? String, let gs = GameStatus(rawValue: s) { status = gs }
            if let gn = d["game_name"] as? String, !gn.trimmingCharacters(in: .whitespaces).isEmpty {
                self.displayName = gn
            }
            hasUnsavedChanges = true
        }

        ref.getDocument(source: .cache) { snap, _ in
            if let d = snap?.data() {
                DispatchQueue.main.async { apply(d) }
            }
            ref.getDocument { liveSnap, _ in
                if let d = liveSnap?.data() {
                    DispatchQueue.main.async { apply(d) }
                }
            }
        }
    }

    private func loadAverageAndCounts() {
        db.collection("game_logs")
            .whereField("game_id", isEqualTo: game.id)
            .whereField("rating", isGreaterThan: 0)
            .getDocuments { snap, _ in
                let ratings = (snap?.documents ?? []).compactMap { $0.data()["rating"] as? Double }
                ratingsCount = ratings.count
                avgRating = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
            }

        db.collection("game_logs")
            .whereField("game_id", isEqualTo: game.id)
            .limit(to: 200)
            .getDocuments { snap, _ in
                let count = (snap?.documents ?? []).reduce(0) { acc, d in
                    if let t = d.data()["review"] as? String,
                       !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return acc + 1
                    }
                    return acc
                }
                reviewsCount = count
            }
    }

    private func loadSavedGameState() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(uid)
        ref.getDocument(source: .cache) { snap, _ in
            let list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            DispatchQueue.main.async {
                self.isSavedGame = list.contains {
                    (($0["id"] as? Int) ?? (($0["id"] as? NSNumber)?.intValue ?? -1)) == self.game.id
                }
            }
            ref.getDocument { liveSnap, _ in
                let liveList = liveSnap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
                DispatchQueue.main.async {
                    self.isSavedGame = liveList.contains {
                        (($0["id"] as? Int) ?? (($0["id"] as? NSNumber)?.intValue ?? -1)) == self.game.id
                    }
                }
            }
        }
    }

    private func toggleSavedGame() {
        guard let uid = Auth.auth().currentUser?.uid, !isSavingSavedGame else { return }
        isSavingSavedGame = true
        let doc = db.collection("users").document(uid)
        doc.getDocument { snap, err in
            if let err {
                DispatchQueue.main.async {
                    self.errorText = err.localizedDescription
                    self.isSavingSavedGame = false
                }
                return
            }
            var list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            if let idx = list.firstIndex(where: { (($0["id"] as? Int) ?? (($0["id"] as? NSNumber)?.intValue ?? -1)) == self.game.id }) {
                list.remove(at: idx)
            } else {
                var payload: [String: Any] = [
                    "id": self.game.id,
                    "name": self.displayName.isEmpty ? self.game.name : self.displayName,
                    "added_at": Timestamp(date: Date())
                ]
                if let cover = self.game.cover?.imageId {
                    payload["cover"] = [
                        "id": self.game.cover?.id as Any,
                        "image_id": cover
                    ]
                }
                list.insert(payload, at: 0)
            }
            doc.setData(["watchlist_games": list], merge: true) { writeErr in
                DispatchQueue.main.async {
                    self.isSavingSavedGame = false
                    if let writeErr {
                        self.errorText = writeErr.localizedDescription
                    } else {
                        self.isSavedGame = list.contains {
                            (($0["id"] as? Int) ?? (($0["id"] as? NSNumber)?.intValue ?? -1)) == self.game.id
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
                isSavedGame = watchlistIds.contains(game.id)
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
        guard let uid = Auth.auth().currentUser?.uid, !isSavingSavedGame else { return }
        isSavingSavedGame = true
        let doc = db.collection("users").document(uid)
        doc.getDocument { snap, err in
            if let err {
                DispatchQueue.main.async {
                    errorText = err.localizedDescription
                    isSavingSavedGame = false
                }
                return
            }
            var list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            guard !list.contains(where: { (($0["id"] as? Int) ?? (($0["id"] as? NSNumber)?.intValue ?? -1)) == game.id }) else {
                DispatchQueue.main.async { isSavingSavedGame = false }
                return
            }
            var payload: [String: Any] = [
                "id": game.id,
                "name": displayName.isEmpty ? game.name : displayName,
                "added_at": Timestamp(date: Date())
            ]
            if let cover = game.cover?.imageId {
                payload["cover"] = [
                    "id": game.cover?.id as Any,
                    "image_id": cover
                ]
            }
            list.insert(payload, at: 0)
            doc.setData(["watchlist_games": list], merge: true) { writeErr in
                DispatchQueue.main.async {
                    isSavingSavedGame = false
                    if let writeErr {
                        errorText = writeErr.localizedDescription
                    } else {
                        isSavedGame = true
                        let newEntry = BookmarkEntry(id: game.id, name: displayName.isEmpty ? game.name : displayName, coverId: game.cover?.imageId, addedAt: Date())
                        bookmarksList.removeAll { $0.id == game.id }
                        bookmarksList.insert(newEntry, at: 0)
                        watchlistIds.insert(game.id)
                        Haptics.success()
                    }
                }
            }
        }
    }

    private func loadScreenshots() {
        if let shots = game.screenshots, !shots.isEmpty {
            screenshots = shots
            didAttemptScreenshotLoad = true
            return
        }
        if let metadata = fullGameMetadata {
            screenshots = metadata.screenshots ?? []
            didAttemptScreenshotLoad = true
            return
        }
        loadSupplementalGameMetadataIfNeeded()
    }

    // MARK: - Metadata enrichment (SAFE)

    private func enrichMetaIfNeeded() {
        if let metadata = fullGameMetadata {
            applySupplementalMetadata(metadata)
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
        igdb.fetchGameById(id: game.id) { result in
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
        if displayName.isPlaceholderForId(game.id) || displayName.isEmpty {
            displayName = g.name
        }
        if displayYear == nil {
            displayYear = g.computedReleaseYear
        }
        let plats = g.prioritizedPlatformNames(prefix: 8)
        if !plats.isEmpty { displayPlatforms = plats }
        if let studio = bestEffortPrimaryStudio(from: g) {
            primaryStudioName = studio
            publisherName = studio
        }
        screenshots = g.screenshots ?? []
        didAttemptScreenshotLoad = true
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

    // MARK: - Save / Draft

    private func saveLog() {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        if hasExistingLog && !isEditingExistingLog { return }
        let hadLogBeforeSave = hasExistingLog
        let hadRatingBeforeSave = hadExistingRatingBeforeEdit
        let hadReviewBeforeSave = hadExistingReviewBeforeEdit
        isSaving = true
        errorText = ""

        let docId = "\(uid)_\(game.id)"
        var payload: [String: Any] = [
            "id": docId,
            "user_id": uid,
            "game_id": game.id,
            "status": status.rawValue,
            "play_date": Timestamp(date: Date()),
            "updated_at": Timestamp(date: Date()),
            "is_liked": false
        ]
        payload["rating"] = rating > 0 ? rating : FieldValue.delete()

        let trimmed = review.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            payload["review"] = trimmed
            payload["review_contains_spoilers"] = reviewContainsSpoilers
        } else {
            payload["review"] = FieldValue.delete()
            payload["review_contains_spoilers"] = false
        }

        let isPostingReviewOrRating = rating > 0 || !trimmed.isEmpty
        if isPostingReviewOrRating && !user.isEmailVerified {
            isSaving = false
            errorText = "Verify your email to post ratings or reviews."
            return
        }

        if let cover = game.cover?.imageId {
            payload["cover"] = [
                "id": game.cover?.id as Any,
                "image_id": cover
            ]
        }
        let nameToStore = (displayName.isEmpty ? game.name : displayName)
        payload["game_name"] = nameToStore

        let savedRating = rating
        let savedReview = review
        let savedHasReview = payload["review"] != nil
        let savedReleaseYear = game.computedReleaseYear

        hasUnsavedChanges = false
        hasExistingLog = true
        isEditingExistingLog = false
        hadExistingRatingBeforeEdit = rating > 0
        hadExistingReviewBeforeEdit = !trimmed.isEmpty
        showSavedToast = true
        isSaving = false
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSavedToast = false
            }
        }

        NotificationCenter.default.post(name: .gamerLndRatingUpdated, object: nil, userInfo: ["game_id": game.id])
        NotificationCenter.default.post(
            name: .gameLogChanged,
            object: nil,
            userInfo: [
                "log_id": docId,
                "user_id": uid,
                "game_id": game.id,
                "deleted": false
            ]
        )

        db.collection("game_logs").document(docId).setData(payload, merge: true) { err in
            if let err = err {
                hasUnsavedChanges = true
                AnalyticsService.shared.trackError(err, context: "save_log")
                errorText = "We couldn't save your game log. Try again."
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                AnalyticsService.shared.trackLogSaved(
                    gameId: game.id,
                    rating: savedRating > 0 ? savedRating : nil,
                    hasReview: savedHasReview
                )
                RewardService.shared.awardForLogSave(
                    gameId: game.id,
                    hadLogBefore: hadLogBeforeSave,
                    hadRatingBefore: hadRatingBeforeSave,
                    hadReviewBefore: hadReviewBeforeSave,
                    rating: savedRating,
                    review: savedReview,
                    releaseYear: savedReleaseYear
                )
                ReviewPromptManager.shared.registerUserAction()
                DispatchQueue.main.async {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        ReviewPromptManager.shared.maybePrompt(in: scene)
                    }
                    GamerLndScoreService.shared.invalidate(gameId: game.id)
                    loadAverageAndCounts()
                }
            }
        }
    }

    private func saveDraftAndDismiss() {
        guard let uid = Auth.auth().currentUser?.uid else { closeView(); return }
        let draftId = "draft_\(uid)_\(game.id)"
        let nameToStore = (displayName.isEmpty ? game.name : displayName)
        let payload: [String: Any] = [
            "id": draftId,
            "user_id": uid,
            "game_id": game.id,
            "game_name": nameToStore,
            "status": status.rawValue,
            "rating": rating,
            "review": review,
            "review_contains_spoilers": reviewContainsSpoilers,
            "updated_at": Timestamp(date: Date()),
            "play_date": Timestamp(date: Date()),
            "cover": game.cover != nil
                ? ["id": game.cover?.id as Any, "image_id": game.cover!.imageId]
                : [:]
        ]
        db.collection("drafts").document(draftId).setData(payload, merge: true) { _ in
            Haptics.success()
            closeView()
        }
    }

    private func deleteLog() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let logId = "\(uid)_\(game.id)"
        isSaving = true
        errorText = ""

        let group = DispatchGroup()

        func deleteDocs(in collection: String, where field: String, equals value: String) {
            group.enter()
            db.collection(collection)
                .whereField(field, isEqualTo: value)
                .getDocuments { snap, _ in
                    let docs = snap?.documents ?? []
                    guard !docs.isEmpty else {
                        group.leave()
                        return
                    }
                    let batch = db.batch()
                    docs.forEach { batch.deleteDocument($0.reference) }
                    batch.commit { _ in
                        group.leave()
                    }
                }
        }

        group.enter()
        db.collection("game_logs").document(logId).delete { _ in
            group.leave()
        }

        group.enter()
        db.collection("drafts").document("draft_\(uid)_\(game.id)").delete { _ in
            group.leave()
        }

        deleteDocs(in: "review_likes", where: "log_id", equals: logId)
        deleteDocs(in: "review_comments", where: "log_id", equals: logId)
        deleteDocs(in: "notifications", where: "log_id", equals: logId)

        group.notify(queue: .main) {
            isSaving = false
            hasExistingLog = false
            isEditingExistingLog = false
            hadExistingRatingBeforeEdit = false
            hadExistingReviewBeforeEdit = false
            hasUnsavedChanges = false
            rating = 0
            review = ""
            reviewContainsSpoilers = false
            status = .inProgress
            GamerLndScoreService.shared.invalidate(gameId: game.id)
            NotificationCenter.default.post(name: .gamerLndRatingUpdated, object: nil, userInfo: ["game_id": game.id])
            NotificationCenter.default.post(
                name: .gameLogChanged,
                object: nil,
                userInfo: [
                    "log_id": logId,
                    "user_id": uid,
                    "game_id": game.id,
                    "deleted": true
                ]
            )
            loadAverageAndCounts()
            Haptics.success()
            closeView()
        }
    }

    private func saveReviewDraftOnly() {
        guard let uid = Auth.auth().currentUser?.uid else {
            reviewEditorFocused = false
            showReviewComposer = false
            return
        }
        let draftId = "draft_\(uid)_\(game.id)"
        let nameToStore = (displayName.isEmpty ? game.name : displayName)
        let payload: [String: Any] = [
            "id": draftId,
            "user_id": uid,
            "game_id": game.id,
            "game_name": nameToStore,
            "status": status.rawValue,
            "rating": rating,
            "review": review,
            "review_contains_spoilers": reviewContainsSpoilers,
            "updated_at": Timestamp(date: Date()),
            "play_date": Timestamp(date: Date()),
            "cover": game.cover != nil
                ? ["id": game.cover?.id as Any, "image_id": game.cover!.imageId]
                : [:]
        ]
        db.collection("drafts").document(draftId).setData(payload, merge: true) { _ in
            Haptics.success()
            reviewComposerSnapshot = review
            reviewComposerSpoilerSnapshot = reviewContainsSpoilers
            hasUnsavedChanges = false
            reviewEditorFocused = false
            showReviewComposer = false
        }
    }
}

private extension GameDetailView {
    var reviewPreviewText: String {
        let trimmed = review.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Open the review editor to write your thoughts and mark spoilers if needed."
        }
        return ContentModeration.displayReviewText(trimmed)
    }

    var hasReviewComposerChanges: Bool {
        review != reviewComposerSnapshot || reviewContainsSpoilers != reviewComposerSpoilerSnapshot
    }

    func openReviewComposer() {
        reviewComposerSnapshot = review
        reviewComposerSpoilerSnapshot = reviewContainsSpoilers
        showReviewComposer = true
    }

    func openRatingsOverlay(avg: Double) {
        NotificationCenter.default.post(
            name: .openRatingsOverlayRequested,
            object: nil,
            userInfo: [
                "game_id": game.id,
                "game_name": displayName.isEmpty ? game.name : displayName,
                "avg": avg,
                "cover_image_id": game.cover?.imageId as Any
            ]
        )
    }

    func closeView() {
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }

    func handleDismissAttempt() {
        if showReviewComposer {
            reviewEditorFocused = false
            closeReviewComposerTapped()
        } else if hasUnsavedChanges {
            showDraftPrompt = true
        } else {
            closeView()
        }
    }

    func closeReviewComposerTapped() {
        if hasReviewComposerChanges {
            showReviewDraftPrompt = true
        } else {
            reviewEditorFocused = false
            showReviewComposer = false
        }
    }

    var reviewComposerOverlay: some View {
        let screenBounds = UIScreen.main.bounds
        let topInset: CGFloat = compactOverlay ? 54 : 66
        let sideInset: CGFloat = 14
        let maxPanelWidth = min(screenBounds.width - (sideInset * 2), 392)
        let availableHeight = max(360, screenBounds.height - topInset - 26)
        let panelHeight = min(availableHeight, compactOverlay ? 520 : 600)

        return ZStack(alignment: .top) {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    reviewEditorFocused = false
                    closeReviewComposerTapped()
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Write Review")
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Button {
                        closeReviewComposerTapped()
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }

                Toggle("Contains spoilers", isOn: $reviewContainsSpoilers)
                    .tint(ColorTheme.accent)
                    .foregroundColor(ColorTheme.text)

                TextEditor(text: $review)
                    .focused($reviewEditorFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: compactOverlay ? 132 : 160, maxHeight: .infinity, alignment: .top)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                    .foregroundColor(ColorTheme.text)
                    .onChange(of: review) { _, _ in
                        if canEditExistingLog {
                            hasUnsavedChanges = true
                        }
                    }
                    .onChange(of: reviewContainsSpoilers) { _, _ in
                        if canEditExistingLog {
                            hasUnsavedChanges = true
                        }
                    }

                Text("Reviews with at least 50 characters count toward GamerLnd Level progress.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    reviewEditorFocused = false
                    hasUnsavedChanges = true
                    showReviewComposer = false
                } label: {
                    Text("Save Review")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(ColorTheme.accent)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(width: maxPanelWidth, height: panelHeight, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 18).fill(ColorTheme.background))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
            .padding(.horizontal, sideInset)
            .padding(.top, topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            reviewEditorFocused = true
        }
    }
}

// MARK: - HeartRatingBarAligned (LEFT→RIGHT fill aligned to slider width)
struct HeartRatingBarAligned: View {
    @Binding var value: Double        // 0…10 (step 0.1)
    let totalWidth: CGFloat           // exact width hearts should occupy (matches slider)
    let spacing: CGFloat              // spacing between hearts

    private let count = 10

    private var heartWidth: CGFloat {
        (totalWidth - CGFloat(count - 1) * spacing) / CGFloat(count)
    }

    private var fillWidth: CGFloat {
        max(0, min(totalWidth, totalWidth * CGFloat(value / 10.0)))
    }

    var body: some View {
        let activeColor = ColorTheme.ratingBandColor(for: value)
        ZStack(alignment: .leading) {
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { _ in
                    PixelHeartIcon(color: ColorTheme.separator, size: heartWidth * 1.12, empty: true)
                        .frame(width: heartWidth, height: heartWidth)
                }
            }
            .frame(width: totalWidth, alignment: .leading)

            let filledRow = HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { _ in
                    PixelHeartIcon(color: activeColor, size: heartWidth * 1.12)
                        .frame(width: heartWidth, height: heartWidth)
                }
            }
            .frame(width: totalWidth, alignment: .leading)

            filledRow
                .mask(
                    HStack(spacing: 0) {
                        Rectangle().frame(width: fillWidth, height: heartWidth)
                        Spacer(minLength: 0)
                    }
                    .frame(width: totalWidth, height: heartWidth)
                )
        }
        .frame(width: totalWidth, height: heartWidth, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let x = max(0, min(gesture.location.x, totalWidth))
                    let proportion = x / totalWidth
                    let raw = Double(proportion) * 10.0
                    let stepped = (raw * 10.0).rounded() / 10.0
                    value = min(10.0, max(0.0, stepped))
                }
        )
    }
}

// MARK: - Small helper for placeholder detection
private extension String {
    func isPlaceholderForId(_ id: Int) -> Bool {
        self == "Game #\(id)" || self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
