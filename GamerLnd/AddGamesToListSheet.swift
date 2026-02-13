// AddGamesToListSheet.swift
// Compact game search + one-tap "Add" to a specific list.
// THIS PASS:
// • Loads existing game_ids from /lists/{listId}/items so results already in the list show “Added” (disabled).
// • On tap “Add”, double-checks with a quick query to avoid duplicates due to race.
// • Still uses batch to create item + bump parent list.updated_at & item_count.
// • Keeps mini search bar with debounce and IGDB-backed results.

import SwiftUI
import FirebaseFirestore

struct AddGamesToListSheet: View {
    let listId: String
    let ownerId: String  // reserved for future owner checks

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [Game] = []
    @State private var isLoading: Bool = false
    @State private var errorText: String = ""

    // Track games we *already* have in this list (from Firestore)…
    @State private var existingGameIds: Set<Int> = []
    // …and games we just added in this session (to immediately reflect UI).
    @State private var addedGameIds: Set<Int> = []

    private let db = Firestore.firestore()
    private let igdb = IGDBService()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Compact search bar
                HStack(spacing: 8) {
                    TextField("Search games…", text: $query)
                        .foregroundColor(ColorTheme.text)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: query, initial: false) { _, _ in debounceSearch() }
                    Button(action: performSearch) {
                        Text("Go").bold().frame(minWidth: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ColorTheme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)

                Divider().background(ColorTheme.separator.opacity(0.6))

                if isLoading {
                    ProgressView().tint(ColorTheme.accent).padding()
                }

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(ColorTheme.highlight)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                List {
                    ForEach(results, id: \.id) { g in
                        HStack(spacing: 12) {
                            if let imgId = g.cover?.imageId {
                                GameCoverImage(id: imgId, preset: .custom(width: 70), cornerRadius: 10)
                                    .frame(width: 70, height: 93)
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(ColorTheme.separator.opacity(0.2))
                                    .frame(width: 70, height: 93)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(g.name)
                                    .foregroundColor(ColorTheme.text)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                if let y = g.computedReleaseYear {
                                    Text(String(y))
                                        .foregroundColor(ColorTheme.subtext)
                                        .font(.caption)
                                }
                            }
                            Spacer()

                            if isAlreadyAdded(g.id) {
                                Label("Added", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(ColorTheme.highlight)
                            } else {
                                Button {
                                    add(game: g)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(ColorTheme.accent)
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(ColorTheme.background)
                    }
                }
                .listStyle(.plain)
                .background(ColorTheme.background)
            }
            .background(ColorTheme.background.ignoresSafeArea())
            .navigationTitle("Add Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ColorTheme.accent)
                    }
                }
            }
        }
        .tint(ColorTheme.accent)
        .preferredColorScheme(ColorTheme.preferredScheme)
        .presentationCornerRadius(16)
        .onAppear(perform: loadExistingGameIds)
    }

    // MARK: - Search

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        isLoading = true; errorText = ""
        igdb.searchGames(query: q, year: nil, genre: nil) { res in
            DispatchQueue.main.async {
                self.isLoading = false
                switch res {
                case .failure(let err):
                    self.errorText = err.localizedDescription
                    self.results = []
                case .success(let games):
                    self.results = games
                }
            }
        }
    }

    @State private var debounceWork: DispatchWorkItem?
    private func debounceSearch() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { self.performSearch() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: - Existing items

    private func loadExistingGameIds() {
        db.collection("lists").document(listId)
            .collection("items")
            .limit(to: 500) // lightweight cap; adjust if you expect huge lists
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

    private func isAlreadyAdded(_ gameId: Int) -> Bool {
        existingGameIds.contains(gameId) || addedGameIds.contains(gameId)
    }

    // MARK: - Add to List (with duplicate guard)

    private func add(game: Game) {
        // If we *already* know it’s in, just reflect UI.
        if isAlreadyAdded(game.id) {
            addedGameIds.insert(game.id)
            return
        }

        let listRef = db.collection("lists").document(listId)
        let items = listRef.collection("items")

        // Quick guard against races: does an item with this game_id already exist?
        items.whereField("game_id", isEqualTo: game.id).limit(to: 1).getDocuments { snap, err in
            if let _ = snap?.documents.first {
                // It's already there — mark as added so UI reflects it.
                self.addedGameIds.insert(game.id)
                self.existingGameIds.insert(game.id)
                return
            }

            // Not found; proceed to write.
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
                if err == nil {
                    // Update UI caches so button flips to “Added”.
                    self.addedGameIds.insert(game.id)
                    self.existingGameIds.insert(game.id)
                }
            }
        }
    }
}
