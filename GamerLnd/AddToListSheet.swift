// AddToListSheet.swift
// Select one or more lists and add the current game to them.
//
// THIS PASS (full file):
// • Uses ListsService.fetchLists(forUserId:) to load your lists.
// • Checks per-list whether the game is already present (queries /lists/{id}/items where game_id == current).
// • Adds to multiple lists at once via ListsService.addItems(listId:items:).
// • “New List” opens ListEditorSheet(ownerId:) and reloads lists on close.
// • Dark-themed, beginner-friendly comments, complies with Firestore rules for item creation:
//
//   Required on /lists/{listId}/items create by your rules:
//     - game_id: int
//     - game_name: string
//     - cover_image_id: string | null
//     - added_at: timestamp
//
//   (We also store id, list_id for convenience; rules allow extra fields.)

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AddToListSheet: View {
    let ownerId: String
    let game: Game
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    // Lists owned by the user
    @State private var lists: [UserList] = []
    // Which lists are selected for adding the game
    @State private var selected: Set<String> = []
    // Whether each list already contains the game (to show a check and to disable selection)
    @State private var alreadyInList: Set<String> = []

    @State private var loading: Bool = false
    @State private var adding: Bool = false
    @State private var errorText: String = ""
    @State private var successText: String = ""
    @State private var showingNewList: Bool = false
    @State private var previewCovers: [String: [String]] = [:]

    private let db = Firestore.firestore()

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            gameSummarySection

            Group {
                if loading {
                    VStack(spacing: 14) {
                        Spacer(minLength: 0)
                        ProgressView()
                            .tint(ColorTheme.accent)
                        Text("Loading your lists…")
                            .font(.footnote)
                            .foregroundColor(ColorTheme.subtext)
                        Spacer(minLength: 0)
                    }
                } else if lists.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("No lists yet. Create one to get started.")
                            .foregroundColor(ColorTheme.subtext)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(lists, id: \.id) { list in
                                row(for: list)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            statusSection
            actionSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ColorTheme.background.ignoresSafeArea())
        .tint(ColorTheme.accent)
        .preferredColorScheme(ColorTheme.preferredScheme)
        .presentationCornerRadius(16)
        .sheet(isPresented: $showingNewList, onDismiss: { loadLists() }) {
            ListEditorSheet(ownerId: ownerId, onCreated: { newList in
                addGameToList(newList) {
                    loadLists()
                    showingNewList = false
                    closeSheet()
                }
            })
                .preferredColorScheme(ColorTheme.preferredScheme)
        }
        .onAppear { loadLists() }
    }

    private var headerSection: some View {
        HStack {
            Text("Add to Lists")
                .font(.title3.weight(.bold))
                .foregroundColor(ColorTheme.text)
            Spacer()
            Button {
                closeSheet()
            } label: {
                OverlayCloseButton()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(ColorTheme.background)
    }

    private var gameSummarySection: some View {
        HStack(spacing: 12) {
            if let imgId = game.cover?.imageId ?? game.screenshots?.first?.imageId {
                GameCoverImage(id: imgId, preset: .custom(width: 58), cornerRadius: 8)
                    .frame(width: 58, height: 78)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ColorTheme.separator.opacity(0.25))
                    .frame(width: 58, height: 78)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(game.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(2)
                Text("Choose one or more lists for this game.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.subtext)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ColorTheme.separator, lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(ColorTheme.highlight)
            }
            if !successText.isEmpty {
                Text(successText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, (errorText.isEmpty && successText.isEmpty) ? 0 : 8)
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            Button {
                showingNewList = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("New List")
                }
                .font(.subheadline.weight(.semibold))
                .frame(height: 48)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundColor(ColorTheme.accent)

            Spacer(minLength: 0)

            Button {
                addToSelectedLists()
            } label: {
                HStack(spacing: 8) {
                    if adding { ProgressView().tint(.white) }
                    Text(selected.isEmpty ? "Add" : "Add to \(selected.count) \(selected.count == 1 ? "List" : "Lists")")
                        .bold()
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(selected.isEmpty || adding ? ColorTheme.separator : ColorTheme.accent)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(selected.isEmpty || adding)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(ColorTheme.background)
    }

    // MARK: - Rows

    private func row(for list: UserList) -> some View {
        let isIn = alreadyInList.contains(list.id)
        let isSelected = selected.contains(list.id)
        return Button {
            guard !isIn else { return } // don't toggle if already in list
            if isSelected { selected.remove(list.id) } else { selected.insert(list.id) }
        } label: {
            listCard(for: list, isIn: isIn, isSelected: isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isIn)
    }

    // MARK: - Data

    private func loadLists() {
        errorText = ""
        successText = ""
        loading = true
        ListsService.shared.fetchLists(forUserId: ownerId) { lists in
            DispatchQueue.main.async {
                self.lists = lists
                self.selected = []
                self.alreadyInList = []
                self.loading = false
            }
            self.loadPreviews(for: lists)
            // After lists are loaded, check which already contain this game.
            self.checkMembership(for: lists)
        }
    }

    /// For each list, check if the game is already present.
    private func checkMembership(for lists: [UserList]) {
        let group = DispatchGroup()
        var found: Set<String> = []

        for list in lists {
            group.enter()
            db.collection("lists").document(list.id)
                .collection("items")
                .whereField("game_id", isEqualTo: game.id)
                .limit(to: 1)
                .getDocuments { snap, _ in
                    if let has = snap?.documents.first, has.exists {
                        found.insert(list.id)
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            self.alreadyInList = found
        }
    }

    private func loadPreviews(for lists: [UserList]) {
        let group = DispatchGroup()
        var next: [String: [String]] = [:]

        for list in lists {
            group.enter()
            db.collection("lists").document(list.id)
                .collection("items")
                .order(by: "added_at", descending: true)
                .limit(to: 4)
                .getDocuments { snap, _ in
                    let docs = snap?.documents ?? []
                    let ids = extractCoverIds(from: docs)
                    if !ids.isEmpty {
                        next[list.id] = ids
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            self.previewCovers = next
        }
    }

    private func extractCoverIds(from docs: [QueryDocumentSnapshot]) -> [String] {
        var coverIds: [String] = []
        for doc in docs {
            let data = doc.data()
            if let flat = data["cover_image_id"] as? String, !flat.isEmpty {
                coverIds.append(flat); continue
            }
            if let cover = data["cover"] as? [String: Any],
               let embedded = cover["image_id"] as? String,
               !embedded.isEmpty {
                coverIds.append(embedded); continue
            }
        }
        return Array(coverIds.prefix(4))
    }

    // MARK: - Actions

    private func addToSelectedLists() {
        guard !selected.isEmpty else { return }
        adding = true
        errorText = ""
        successText = ""

        let group = DispatchGroup()
        let listById = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })

        for listId in selected {
            guard let list = listById[listId] else { continue }
            group.enter()
            buildItem(for: list) { item in
                ListsService.shared.addItems(listId: listId, items: [item]) {
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.adding = false
            self.successText = "Game added."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.closeSheet()
            }
        }
    }

    private func closeSheet() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func addGameToList(_ list: UserList, completion: @escaping () -> Void) {
        buildItem(for: list) { item in
            ListsService.shared.addItems(listId: list.id, items: [item]) {
                completion()
            }
        }
    }

    private func buildItem(for list: UserList, completion: @escaping (UserListItem) -> Void) {
        let base = UserListItem(
            id: UUID().uuidString,
            listId: list.id,
            gameId: game.id,
            gameName: game.name,
            coverImageId: game.cover?.imageId,
            releaseYear: game.computedReleaseYear,
            order: nil,
            tier: nil,
            addedAt: Date()
        )

        switch list.type {
        case .regular:
            completion(base)
        case .ranked, .tiered:
            fetchNextOrder(for: list.id) { next in
                var item = base
                item.order = next
                completion(item)
            }
        }
    }

    private func fetchNextOrder(for listId: String, completion: @escaping (Int) -> Void) {
        db.collection("lists").document(listId)
            .collection("items")
            .order(by: "order", descending: true)
            .limit(to: 1)
            .getDocuments { snap, _ in
                let maxOrder: Int
                if let data = snap?.documents.first?.data(),
                   let val = data["order"] as? Int {
                    maxOrder = val
                } else if let data = snap?.documents.first?.data(),
                          let val = data["order"] as? NSNumber {
                    maxOrder = val.intValue
                } else {
                    maxOrder = -1
                }
                completion(maxOrder + 1)
            }
    }

    // MARK: - Preview UI

    private func listCard(for list: UserList, isIn: Bool, isSelected: Bool) -> some View {
        let ids = previewCovers[list.id] ?? []
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    privacyBadge(isPublic: list.isPublic)
                        .padding(8)
                }

            HStack(spacing: 12) {
                // Left: preview
                VStack(spacing: 6) {
                    HStack(spacing: 6) { previewCell(0, ids: ids, list: list); previewCell(1, ids: ids, list: list) }
                    HStack(spacing: 6) { previewCell(2, ids: ids, list: list); previewCell(3, ids: ids, list: list) }
                }
                .frame(width: 72, height: 72)

                // Middle: details
                VStack(alignment: .leading, spacing: 6) {
                    Text(list.title)
                        .foregroundColor(ColorTheme.text)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text(list.type.titleText)
                        .foregroundColor(ColorTheme.subtext)
                        .font(.caption)
                }

                Spacer(minLength: 0)

                // Right: state
                if isIn {
                    Label {
                        Text("Added")
                            .foregroundColor(ColorTheme.gold)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(ColorTheme.accent)
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.semibold))
                } else if isSelected {
                    Image(systemName: "checkmark.square.fill")
                        .foregroundColor(ColorTheme.accent)
                } else {
                    Image(systemName: "square")
                        .foregroundColor(ColorTheme.subtext)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func previewCell(_ idx: Int, ids: [String], list: UserList) -> some View {
        let w: CGFloat = 28
        let h: CGFloat = 38
        if idx < ids.count {
            GameCoverImage(id: ids[idx], preset: .custom(width: w), cornerRadius: 4)
                .frame(width: w, height: h)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(ColorTheme.separator.opacity(0.2))
                .frame(width: w, height: h)
                .overlay(
                    Group {
                        if list.type == .tiered {
                            tierPreviewBadge(for: list)
                        } else {
                            Image(systemName: symbolForType(list.type))
                                .foregroundColor(ColorTheme.subtext)
                                .font(.caption2)
                        }
                    }
                )
        }
    }

    private func symbolForType(_ type: ListType) -> String {
        switch type {
        case .tiered: return "square.grid.2x2"
        case .ranked: return "list.number"
        case .regular: return "list.bullet"
        }
    }

    private func tierPreviewBadge(for list: UserList) -> some View {
        let labels = (list.tierLabels ?? ["S", "A", "B"]).prefix(3)
        let colors = (list.tierColors ?? ["#E74C3C","#E67E22","#F1C40F"]).prefix(3)
        return VStack(spacing: 1) {
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(colorFromHex(Array(colors)[min(idx, colors.count - 1)]))
                        .frame(width: 6, height: 6)
                    Text(label.isEmpty ? "T\(idx+1)" : label)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(ColorTheme.subtext)
                }
            }
        }
    }

    private func privacyBadge(isPublic: Bool) -> some View {
        let icon = isPublic ? "globe" : "lock.fill"
        return Image(systemName: icon)
            .font(.caption2.weight(.semibold))
            .foregroundColor(isPublic ? ColorTheme.subtext : ColorTheme.highlight)
            .padding(4)
            .background(Circle().fill(ColorTheme.surface))
            .overlay(Circle().stroke(ColorTheme.separator, lineWidth: 1))
    }

    private func colorFromHex(_ hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var v = trimmed
        if v.hasPrefix("#") { v.removeFirst() }
        guard v.count == 6, let num = Int(v, radix: 16) else {
            return ColorTheme.separator
        }
        let r = Double((num >> 16) & 0xFF) / 255.0
        let g = Double((num >> 8) & 0xFF) / 255.0
        let b = Double(num & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

// PREVIEW
#if DEBUG
struct AddToListSheet_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AddToListSheet(
                ownerId: "demo_owner",
                game: Game(
                    id: 1234,
                    name: "Sample Game",
                    cover: Game.Cover(id: 1, imageId: "abc123"),
                    firstReleaseDate: nil,
                    genres: nil,
                    platforms: nil,
                    rating: nil,
                    ratingCount: nil,
                    totalRatingCount: nil,
                    screenshots: nil
                )
            )
        }
        .preferredColorScheme(ColorTheme.preferredScheme)
    }
}
#endif
