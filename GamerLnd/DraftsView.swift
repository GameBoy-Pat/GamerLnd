// DraftsView.swift
// Shows the current user's saved drafts (For You / Following tab helper).
//
// THIS PASS:
// • Each row shows game cover, **game title**, and a "Last edited" timestamp.
// • Enriches missing titles by fetching from IGDB and writes back `game_name` to the draft.
// • Ordered by updated_at desc; tap opens GameDetailView with that game.
// • Keeps local @State array (no Binding conversion error).

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DraftsView: View {
    @State private var drafts: [DraftRow] = []
    @State private var loading = false
    @State private var errorText = ""

    private let db = Firestore.firestore()
    private let igdb = IGDBService()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if loading {
                    ProgressView().tint(ColorTheme.accent).padding()
                }

                List {
                    ForEach(drafts, id: \.id) { d in
                        NavigationLink(destination: GameDetailView(game: d.asGame)) {
                            HStack(spacing: 12) {
                                if let img = d.coverImageId {
                                    GameCoverImage(id: img, preset: .custom(width: 70), cornerRadius: 10)
                                        .frame(width: 70, height: 93)
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(ColorTheme.separator.opacity(0.2))
                                        .frame(width: 70, height: 93)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(d.gameName)
                                        .foregroundColor(ColorTheme.text)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                    Text("Last edited \(relative(d.updatedAt.dateValue()))")
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.subtext)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(ColorTheme.background)
                    }

                    if drafts.isEmpty && !loading {
                        Text("No drafts yet.")
                            .foregroundColor(ColorTheme.subtext)
                            .font(.caption)
                            .listRowBackground(ColorTheme.background)
                    }
                }
                .listStyle(.plain)
                .background(ColorTheme.background)

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(ColorTheme.highlight)
                        .padding(.vertical, 8)
                }
            }
            .background(ColorTheme.background.ignoresSafeArea())
            .navigationTitle("Drafts")
            .toolbar { ToolbarItem(placement: .principal) { AppIconCentered() } }
            .onAppear(perform: loadDrafts)
        }
        .tint(ColorTheme.accent)
        .preferredColorScheme(ColorTheme.preferredScheme)
    }

    // MARK: - Data

    private func loadDrafts() {
        guard let uid = Auth.auth().currentUser?.uid else { drafts = []; return }
        loading = true; errorText = ""
        db.collection("drafts")
            .whereField("user_id", isEqualTo: uid)
            .order(by: "updated_at", descending: true)
            .limit(to: 50)
            .getDocuments { snap, err in
                loading = false
                if let err = err {
                    errorText = err.localizedDescription
                    drafts = []
                    return
                }
                let rows: [DraftRow] = (snap?.documents ?? []).compactMap { d in
                    DraftRow.fromFirestore(id: d.documentID, data: d.data())
                }
                self.drafts = rows
                // Enrich any rows where name is a placeholder (older drafts)
                self.enrichMissingNamesIfNeeded()
            }
    }

    /// For any draft still showing "Game #123", fetch the real name from IGDB and
    /// write it back to Firestore for future loads.
    private func enrichMissingNamesIfNeeded() {
        // Collect unique ids that still have placeholders like "Game #123"
        let missing = drafts
            .filter { $0.gameName.isPlaceholderForId($0.gameId) }
            .map { $0.gameId }

        guard !missing.isEmpty else { return }

        // Avoid duplicate requests
        let uniqueIds = Array(Set(missing))
        for gid in uniqueIds {
            igdb.fetchGameById(id: gid) { result in
                switch result {
                case .success(let game):
                    let realName = game.name
                    // Update local rows
                    DispatchQueue.main.async {
                        for idx in drafts.indices {
                            if drafts[idx].gameId == gid && drafts[idx].gameName.isPlaceholderForId(gid) {
                                drafts[idx] = drafts[idx].withName(realName)
                            }
                        }
                    }
                    // Write back to any drafts in Firestore that are missing `game_name`
                    guard let uid = Auth.auth().currentUser?.uid else { return }
                    db.collection("drafts")
                        .whereField("user_id", isEqualTo: uid)
                        .whereField("game_id", isEqualTo: gid)
                        .getDocuments { snap, _ in
                            for doc in (snap?.documents ?? []) {
                                let data = doc.data()
                                // Only set if not present to avoid clobbering
                                if data["game_name"] as? String == nil {
                                    db.collection("drafts").document(doc.documentID)
                                        .setData(["game_name": realName], merge: true)
                                }
                            }
                        }
                case .failure:
                    break // silently ignore; will still show placeholder until next time
                }
            }
        }
    }

    // MARK: - Helpers

    private func relative(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Draft row model for list

struct DraftRow: Identifiable, Hashable {
    let id: String
    let gameId: Int
    let gameName: String
    let coverImageId: String?
    let updatedAt: Timestamp

    var asGame: Game {
        Game(
            id: gameId,
            name: gameName,
            cover: coverImageId != nil ? Game.Cover(id: nil, imageId: coverImageId!) : nil,
            firstReleaseDate: nil,
            genres: nil,
            platforms: nil,
            rating: nil,
            ratingCount: nil,
            totalRatingCount: nil,
            screenshots: nil
        )
    }

    static func fromFirestore(id: String, data: [String: Any]) -> DraftRow? {
        guard
            let gid = (data["game_id"] as? Int) ?? (data["game_id"] as? NSNumber)?.intValue,
            let updated = data["updated_at"] as? Timestamp
        else { return nil }

        // Prefer explicit title fields
        let name =
            (data["game_name"] as? String) ??
            (data["name"] as? String) ??
            (data["title"] as? String) ??
            "Game #\(gid)" // fallback

        // Cover can be nested map or flat id
        var coverId: String? = nil
        if let coverDict = data["cover"] as? [String: Any],
           let img = coverDict["image_id"] as? String {
            coverId = img
        } else if let flat = data["cover_image_id"] as? String {
            coverId = flat
        }

        return DraftRow(id: id, gameId: gid, gameName: name, coverImageId: coverId, updatedAt: updated)
    }

    func withName(_ newName: String) -> DraftRow {
        DraftRow(id: id, gameId: gameId, gameName: newName, coverImageId: coverImageId, updatedAt: updatedAt)
    }
}

// MARK: - Small helper for placeholder detection
private extension String {
    func isPlaceholderForId(_ id: Int) -> Bool {
        self == "Game #\(id)" || self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
