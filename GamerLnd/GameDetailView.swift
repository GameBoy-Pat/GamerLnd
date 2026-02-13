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
    // Selected IGDB game
    let game: Game

    @Environment(\.dismiss) private var dismiss
    // USER INPUT
    @State private var rating: Double = 0.0
    @State private var review: String = ""
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
    @State private var showSavedToast: Bool = false

    // LISTS
    @State private var showAddToList: Bool = false

    // DISPLAY METADATA (can be enriched via IGDB)
    @State private var displayName: String = ""
    @State private var displayYear: Int? = nil
    @State private var displayPlatforms: [String] = []
    @State private var publisherName: String? = nil

    private let db = Firestore.firestore()
    private let igdb = IGDBService()
    private var canEditExistingLog: Bool { !hasExistingLog || isEditingExistingLog }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // 1) HERO HEADER
                headerHero

                // 2) INFO CARD
                infoCard
                    .padding(.horizontal, 16)
                    .offset(y: -28)
                    .zIndex(2)

                // 3) Action row directly under the info card (single source of truth)
                HStack(spacing: 12) {
                    addToListsButton
                    saveButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .offset(y: -22)

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
                VStack(alignment: .leading, spacing: 18) {
                    if hasExistingLog {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Text("Your log")
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
                                    .foregroundColor(ColorTheme.subtext)
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    // Community average
                    if let avg = avgRating, ratingsCount > 0 {
                        HStack(spacing: 8) {
                            Text("GamerLnd Score")
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                            Image(systemName: "heart.fill")
                                .foregroundColor(ColorTheme.highlight)
                            Text(String(format: "%.1f", avg))
                                .font(.headline.weight(.semibold))
                                .foregroundColor(ColorTheme.highlight)
                            if ratingsCount > 0 {
                                Text("(\(ratingsCount))")
                                    .font(.caption2)
                                    .foregroundColor(ColorTheme.subtext)
                            }
                            Spacer()
                        }
                    }

                    // Your rating
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your Rating")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)

                        HStack(alignment: .center, spacing: 12) {
                            GeometryReader { geo in
                                VStack(spacing: 8) {
                                    HeartRatingBarAligned(
                                        value: $rating,
                                        totalWidth: geo.size.width,
                                        spacing: UIStyles.RatingHeart.spacingPrimary
                                    )
                                    Slider(value: $rating, in: 0...10, step: 0.1)
                                        .tint(ColorTheme.highlight)
                                        .frame(width: geo.size.width)
                                        .onChange(of: rating) { _, _ in Haptics.softImpact() }
                                }
                            }
                            .frame(height: 60)

                            Text(String(format: "%.1f", rating))
                                .font(.title2.monospacedDigit().weight(.semibold))
                                .foregroundColor(ColorTheme.highlight)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Review")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)

                        TextEditor(text: $review)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 130)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(ColorTheme.surface)
                            )
                            .foregroundColor(ColorTheme.text)
                            .onChange(of: review) { _, _ in
                                if canEditExistingLog {
                                    hasUnsavedChanges = true
                                }
                            }
                            .disabled(!canEditExistingLog)

                        if reviewsCount == 0 {
                            Text("Be the first to review this game!")
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                        }
                    }

                    // Status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.text)

                        Picker("Status", selection: $status) {
                            Text("In Progress").tag(GameStatus.inProgress)
                            Text("Completed").tag(GameStatus.completed)
                            Text("Not Played").tag(GameStatus.notPlayed)
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
                .padding(.bottom, 24)
            }
        }
        .padding(.bottom, 80)
        .background(ColorTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .principal) { AppIconCentered() }
            ToolbarItem(placement: .navigationBarLeading) {
                if hasUnsavedChanges {
                    Button {
                        Haptics.tap()
                        showDraftPrompt = true
                    } label: {
                        HStack { Image(systemName: "chevron.left"); Text("Back") }
                    }
                    .foregroundColor(ColorTheme.accent)
                }
            }
        }
        .onAppear {
            AnalyticsService.shared.screen("game_detail")
        }
        .confirmationDialog("Save draft before leaving?", isPresented: $showDraftPrompt, titleVisibility: .visible) {
            Button("Save Draft") { Haptics.commit(); saveDraftAndDismiss() }
            Button("Leave Without Saving", role: .destructive) { Haptics.tap(); dismiss() }
            Button("Keep Editing", role: .cancel) { }
        }
        .sheet(isPresented: $showAddToList) {
            if let uid = Auth.auth().currentUser?.uid {
                AddToListSheet(ownerId: uid, game: game)
                    .preferredColorScheme(ColorTheme.preferredScheme)
                    .presentationDetents([.fraction(0.85)])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(16)
            } else {
                VStack(spacing: 12) {
                    Text("Please sign in to add to lists.")
                        .foregroundColor(ColorTheme.text)
                    Button {
                        Haptics.tap()
                        showAddToList = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ColorTheme.accent)
                    }
                }
                .padding()
                .background(ColorTheme.background)
                .preferredColorScheme(ColorTheme.preferredScheme)
                .presentationCornerRadius(16)
            }
        }
        .onAppear {
            // Base display info from incoming Game
            self.displayName = game.name
            self.displayYear = game.computedReleaseYear
            self.displayPlatforms = (game.platforms ?? []).map { $0.name }
            // Enrich metadata (publisher, etc.) safely
            enrichMetaIfNeeded()
            loadExistingLogIfAny()
            loadDraftIfAny()
            loadAverageAndCounts()
            loadScreenshots()
        }
    }

    // MARK: - Header & Info Card

    private var headerHero: some View {
        let ids = screenshots.map { $0.imageId }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return ZStack {
            if !ids.isEmpty {
                let idx = currentScreenshotIndex % max(ids.count, 1)
                GameScreenshotImage(id: ids[idx], size: .hd720, cornerRadius: 0)
                    .frame(height: UIStyles.Art.headerHeight)
                    .clipped()
                    .transition(.opacity)
                    .id(ids[idx])
            } else {
                Rectangle()
                    .fill(ColorTheme.surface)
                    .frame(height: UIStyles.Art.headerHeight)
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
                gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.55)]),
                startPoint: .center, endPoint: .bottom
            )
            .frame(height: UIStyles.Art.headerHeight)
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
        HStack(alignment: .top, spacing: 12) {
            if let imgId = game.cover?.imageId ?? game.screenshots?.first?.imageId {
                GameCoverImage(id: imgId, preset: .custom(width: 84), cornerRadius: 12)
                    .frame(width: 84, height: 112)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(displayName.isEmpty ? game.name : displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 4) {
                    if let y = displayYear {
                        Text("\(y)")
                            .font(.footnote)
                            .foregroundColor(ColorTheme.subtext)
                    }
                    if !displayPlatforms.isEmpty {
                        Text(displayPlatforms.prefix(4).joined(separator: ", "))
                            .font(.footnote)
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(1)
                    }
                    if let pub = publisherName, !pub.isEmpty {
                        Text("Publisher: \(pub)")
                            .font(.footnote)
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Buttons (single row under card)

    private var saveButtonTitle: String {
        if hasExistingLog && !isEditingExistingLog { return "Edit Log" }
        if hasExistingLog { return "Save Changes" }
        return "Save Log"
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
                    if isSaving { ProgressView().tint(.white) }
                    Text(saveButtonTitle).bold()
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
            .frame(maxWidth: 180)
            .padding(.horizontal, 12)
            .background(ColorTheme.accent)
            .foregroundColor(.white)
            .cornerRadius(UIStyles.Buttons.primaryCorner)
            .overlay(
                RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                    .stroke(ColorTheme.separator.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(isSaving)
        .accessibilityLabel("Save your log for this game")
    }

    private var addToListsButton: some View {
        Button {
            Haptics.tap()
            showAddToList = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.badge.plus")
                Text("Add to Lists").bold()
            }
            .frame(height: UIStyles.Buttons.compactHeight)
            .frame(maxWidth: 180)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                    .fill(ColorTheme.surface)
            )
            .foregroundColor(ColorTheme.accent)
            .overlay(
                RoundedRectangle(cornerRadius: UIStyles.Buttons.primaryCorner)
                    .stroke(ColorTheme.separator, lineWidth: 1)
            )
        }
        .accessibilityLabel("Add this game to your custom lists")
    }

    // MARK: - Firestore Loads

    private func loadExistingLogIfAny() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: uid)
            .whereField("game_id", isEqualTo: game.id)
            .limit(to: 1)
            .getDocuments { snap, _ in
                guard let d = snap?.documents.first?.data() else { return }
                hasExistingLog = true
                isEditingExistingLog = false
                if let r = d["rating"] as? Double { rating = r }
                if let rev = d["review"] as? String { review = rev }
                if let s = d["status"] as? String, let gs = GameStatus(rawValue: s) { status = gs }
            }
    }

    private func loadDraftIfAny() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("drafts")
            .whereField("user_id", isEqualTo: uid)
            .whereField("game_id", isEqualTo: game.id)
            .limit(to: 1)
            .getDocuments { snap, _ in
                guard let d = snap?.documents.first?.data() else { return }
                if let r = d["rating"] as? Double { rating = r }
                if let rI = d["rating"] as? Int { rating = Double(rI) }
                if let rev = d["review"] as? String { review = rev }
                if let s = d["status"] as? String, let gs = GameStatus(rawValue: s) { status = gs }
                if let gn = d["game_name"] as? String, !gn.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.displayName = gn
                }
                hasUnsavedChanges = true
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

    private func loadScreenshots() {
        if let shots = game.screenshots, !shots.isEmpty {
            screenshots = shots
            didAttemptScreenshotLoad = true
            return
        }
        igdb.fetchGameById(id: game.id) { result in
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

    // MARK: - Metadata enrichment (SAFE)

    private func enrichMetaIfNeeded() {
        // Fetch once to try to get publisher/platform superset (no KVC).
        igdb.fetchGameById(id: game.id) { result in
            if case .success(let g) = result {
                DispatchQueue.main.async {
                    // Name
                    if self.displayName.isPlaceholderForId(self.game.id) || self.displayName.isEmpty {
                        self.displayName = g.name
                    }
                    // Year
                    if self.displayYear == nil {
                        self.displayYear = g.computedReleaseYear
                    }
                    // Platforms
                    let plats = (g.platforms ?? []).map { $0.name }
                    if !plats.isEmpty { self.displayPlatforms = plats }
                    // Publisher (non-throwing Mirror traversal)
                    if let pub = bestEffortPublisher(from: g) {
                        self.publisherName = pub
                    }
                }
            }
        }
    }

    /// Try to traverse the `Game` object with Mirror to find `involvedCompanies.publisher == true` → `company.name`.
    /// This never throws (unlike KVC); it simply returns nil if the shape isn't present.
    private func bestEffortPublisher(from game: Game) -> String? {
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

    // MARK: - Save / Draft

    private func saveLog() {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        if hasExistingLog && !isEditingExistingLog { return }
        isSaving = true
        errorText = ""

        let docId = "\(uid)_\(game.id)"
        var payload: [String: Any] = [
            "id": docId,
            "user_id": uid,
            "game_id": game.id,
            "status": status.rawValue,
            "play_date": Timestamp(date: Date()),
            "is_liked": false
        ]
        if rating > 0 { payload["rating"] = rating }

        let trimmed = review.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { payload["review"] = trimmed }

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

        db.collection("game_logs").document(docId).setData(payload, merge: true) { err in
            isSaving = false
            if let err = err {
                AnalyticsService.shared.trackError(err, context: "save_log")
                return
            }
            hasUnsavedChanges = false
            hasExistingLog = true
            isEditingExistingLog = false
            showSavedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSavedToast = false
                }
            }
            AnalyticsService.shared.trackLogSaved(
                gameId: game.id,
                rating: payload["rating"] as? Double,
                hasReview: payload["review"] != nil
            )
            Haptics.success()
            ReviewPromptManager.shared.registerUserAction()
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                ReviewPromptManager.shared.maybePrompt(in: scene)
            }
            GamerLndScoreService.shared.invalidate(gameId: game.id)
            NotificationCenter.default.post(name: .gamerLndRatingUpdated, object: nil, userInfo: ["game_id": game.id])
            loadAverageAndCounts()
        }
    }

    private func saveDraftAndDismiss() {
        guard let uid = Auth.auth().currentUser?.uid else { dismiss(); return }
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
            "updated_at": Timestamp(date: Date()),
            "play_date": Timestamp(date: Date()),
            "cover": game.cover != nil
                ? ["id": game.cover?.id as Any, "image_id": game.cover!.imageId]
                : [:]
        ]
        db.collection("drafts").document(draftId).setData(payload, merge: true) { _ in
            Haptics.success()
            dismiss()
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
        ZStack(alignment: .leading) {
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { _ in
                    Image(systemName: "heart")
                        .resizable()
                        .scaledToFit()
                        .frame(width: heartWidth, height: heartWidth)
                        .foregroundColor(ColorTheme.separator)
                }
            }
            .frame(width: totalWidth, alignment: .leading)

            let filledRow = HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { _ in
                    Image(systemName: "heart.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: heartWidth, height: heartWidth)
                        .foregroundColor(ColorTheme.highlight)
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
