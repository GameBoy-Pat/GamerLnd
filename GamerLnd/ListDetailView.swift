// ListDetailView.swift
// Shows a user list (Regular/Ranked/Tiered), supports reordering, tier moves, and adding/removing items.
// Covers in lanes/pool are rendered via AsyncImage with a direct IGDB image URL.
// If an item lacks cover_image_id, we resolve it via IGDB and persist it to Firestore.
//
// Updates:
// • Ranked Grid: drag-and-drop reordering while in grid layout (Edit Order active) + TRASH icon to delete while editing.
// • Save button appears for Ranked Grid edit mode, persists order via ListsService.updateRanks.
// • Tiered: Save button now calls saveTierPositions() to persist lane positions.
// • Keeps: Ranked List mode reorder, Tier lanes+pool with drag/drop, add-games sheet, description card.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UniformTypeIdentifiers

struct ListDetailView: View {
    let list: UserList
    let isOwner: Bool

    @Environment(\.dismiss) private var dismiss

    // Items state
    @State private var items: [UserListItem] = []
    @State private var nameCache: [Int: String] = [:]
    @State private var loading: Bool = false
    @State private var errorText: String = ""

    // UI
    @State private var showAddSheet: Bool = false
    @State private var showConfirmDelete: Bool = false
    @State private var isSavingOrder: Bool = false

    // Tier edit mode
    @State private var editTierMode: Bool = false
    @State private var draggingItemID: String? = nil

    // Ranked edit + layout
    enum RankedLayout { case list, grid }
    @State private var rankedEditMode: Bool = false
    @State private var rankedLayout: RankedLayout = .list
    @State private var rankedGridDirty: Bool = false // track unsaved grid edits

    private let db = Firestore.firestore()

    var body: some View {
        VStack(spacing: 0) {
            header

            // Description (roomier card)
            if !list.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack {
                    Text(list.description)
                        .font(.footnote)
                        .foregroundColor(ColorTheme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ColorTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(ColorTheme.separator, lineWidth: 1)
                                )
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if loading {
                ProgressView().tint(ColorTheme.accent).padding()
            }

            contentList
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Center brand
            ToolbarItem(placement: .principal) { AppIconCentered() }

            // Leading Save button:
            // - Tiered when editing
            // - Ranked Grid when editing and there are changes
            ToolbarItemGroup(placement: .navigationBarLeading) {
                if list.type == .tiered && isOwner && editTierMode {
                    Button {
                        saveTierPositions()
                    } label: {
                        if isSavingOrder { ProgressView().tint(ColorTheme.accent) }
                        else { Text("Save").bold() }
                    }
                    .disabled(isSavingOrder)
                    .foregroundColor(ColorTheme.accent)
                } else if list.type == .ranked && rankedLayout == .grid && isOwner && rankedEditMode {
                    Button {
                        saveRankedOrderFromCurrentItems()
                    } label: {
                        if isSavingOrder { ProgressView().tint(ColorTheme.accent) }
                        else { Text("Save").bold() }
                    }
                    .disabled(isSavingOrder || !rankedGridDirty)
                    .foregroundColor(ColorTheme.accent)
                }
            }

            // Trailing menu
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isOwner {
                    Menu {
                        if list.type == .tiered {
                            Button {
                                withAnimation(.easeInOut) {
                                    editTierMode.toggle()
                                }
                            } label: {
                                Label(editTierMode ? "Done Editing Layout" : "Edit Tier Layout",
                                      systemImage: editTierMode ? "checkmark.circle" : "rectangle.and.hand.point.up.left")
                            }
                        }

                        if list.type == .ranked {
                            Button {
                                withAnimation(.easeInOut) {
                                    rankedEditMode.toggle()
                                    // When switching on edit in GRID, start a clean session
                                    if rankedLayout == .grid && rankedEditMode {
                                        rankedGridDirty = false
                                    }
                                }
                            } label: {
                                Label(rankedEditMode ? "Done Editing" : "Edit Order",
                                      systemImage: rankedEditMode ? "checkmark.circle" : "arrow.up.arrow.down")
                            }

                            Button {
                                withAnimation(.easeInOut) {
                                    // If leaving List while editing, end list edit mode (drag handles)
                                    if rankedLayout == .list && rankedEditMode {
                                        rankedEditMode = false
                                    }
                                    rankedLayout = (rankedLayout == .list) ? .grid : .list
                                    // Reset grid dirty indicator when entering grid
                                    if rankedLayout == .grid {
                                        rankedGridDirty = false
                                    }
                                }
                            } label: {
                                Label(
                                    rankedLayout == .list ? "Show as Grid" : "Show as List",
                                    systemImage: rankedLayout == .list ? "square.grid.2x2" : "list.bullet"
                                )
                            }
                        }

                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add Games", systemImage: "text.badge.plus")
                        }

                        Button(role: .destructive) {
                            showConfirmDelete = true
                        } label: {
                            Label("Delete List", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundColor(ColorTheme.accent)
                    }
                }
            }
        }
        .onAppear { loadItems() }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadItems() }) {
            if let uid = Auth.auth().currentUser?.uid {
                AddGamesToListSheet(listId: list.id, ownerId: uid)
                    .preferredColorScheme(ColorTheme.preferredScheme)
                    .presentationDetents([.fraction(0.85)])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(16)
            }
        }
        .confirmationDialog("Delete this list?", isPresented: $showConfirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteList() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(list.title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                if list.isPublic {
                    Text("Public")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.accent))
                } else {
                    Text("Private")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(ColorTheme.subtext)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ColorTheme.separator, lineWidth: 1))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if let tlabels = list.tierLabels, !tlabels.isEmpty, list.type == .tiered {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(tlabels.enumerated()), id: \.offset) { idx, label in
                            let txt = label.trimmingCharacters(in: .whitespacesAndNewlines)
                            Text(txt.isEmpty ? defaultTierLabel(idx) : txt)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(ColorTheme.text)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(ColorTheme.surface)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentList: some View {
        switch list.type {
        case .regular:
            regularListView
        case .ranked:
            if rankedLayout == .list {
                rankedListView
            } else {
                rankedGridView
            }
        case .tiered:
            tieredWithPool
        }
    }

    // Regular list (no ordering UI)
    private var regularListView: some View {
        List {
            ForEach(items.sorted(by: { ($0.addedAt ?? Date.distantPast) > ($1.addedAt ?? Date.distantPast) }), id: \.id) { it in
                itemRow(it)
                    .listRowBackground(ColorTheme.background)
            }
            .onDelete(perform: isOwner ? delete(at:) : nil)
        }
        .listStyle(.plain)
        .background(ColorTheme.background)
    }

    // Ranked list (List layout) with reordering
    private var rankedListView: some View {
        List {
            ForEach(items.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }), id: \.id) { it in
                itemRow(it, showRank: true)
                    .listRowBackground(ColorTheme.background)
            }
            .onMove(perform: (isOwner && rankedEditMode) ? moveRanked : nil)
            .onDelete(perform: (isOwner && rankedEditMode) ? delete(at:) : nil)
        }
        .environment(\.editMode, .constant((isOwner && rankedEditMode) ? .active : .inactive))
        .listStyle(.plain)
        .background(ColorTheme.background)
    }

    // Ranked list (Grid layout) — editable with drag/drop when rankedEditMode == true
    private var rankedGridView: some View {
        let ordered = items.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        let grid = [GridItem(.adaptive(minimum: 110), spacing: 12)]
        return ScrollView {
            LazyVGrid(columns: grid, spacing: 12) {
                ForEach(ordered, id: \.id) { it in
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            CoverFetchView(item: it, cornerRadius: 12, width: 110, height: 146)
                                .frame(width: 110, height: 146)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke((rankedEditMode && draggingItemID == it.id) ? ColorTheme.accent : Color.white.opacity(0.06), lineWidth: rankedEditMode && draggingItemID == it.id ? 2 : 1)
                                )
                                .onDragIf(rankedEditMode, item: it.id) { draggingItemID = it.id }
                                .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                                    handleRankedGridDrop(onTargetId: it.id, providers: providers)
                                }

                            // Rank badge (persistent order)
                            Text("\((it.order ?? 0) + 1)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.black.opacity(0.65))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .padding(6)

                            // Trash (delete from list) — visible only while editing in GRID
                            if rankedEditMode && isOwner {
                                HStack {
                                    Spacer()
                                    Button {
                                        deleteItems([it.id])
                                        rankedGridDirty = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(6)
                                            .background(Color.black.opacity(0.65))
                                            .clipShape(Circle())
                                            .foregroundColor(.white)
                                            .accessibilityLabel("Remove from List")
                                    }
                                }
                                .padding(6)
                            }
                        }
                        Text(displayName(for: it))
                            .font(.caption)
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(2)
                    }
                }

                // Drop area at the END of grid (allow moving to last)
                Color.clear
                    .frame(height: 10)
                    .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                        handleRankedGridDrop(onTargetId: nil, providers: providers) // nil => append to end
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(ColorTheme.background)
    }

    // MARK: - Tiered (lanes + bottom Pool)

    private var tieredWithPool: some View {
        let labels = normalizedTierLabels()
        let colors = normalizedTierColors()

        let laneHeight: CGFloat = 110
        let coverSize = CGSize(width: 70, height: 93)
        let leftColWidth: CGFloat = 64

        // Lanes
        let lanesSection = VStack(spacing: 10) {
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                let laneItems = items
                    .filter { ($0.tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == label }
                    .sorted { ($0.order ?? 0) < ($1.order ?? 0) }

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorFromHex(colors[idx]))
                        .overlay(
                            Text(label.isEmpty ? defaultTierLabel(idx) : label)
                                .font(.headline.weight(.bold))
                                .foregroundColor(.white)
                        )
                        .frame(width: leftColWidth, height: laneHeight)

                    TierLaneView(
                        tierId: label,
                        items: laneItems,
                        allItems: $items,
                        editMode: $editTierMode,
                        draggingItemID: $draggingItemID,
                        laneHeight: laneHeight,
                        coverSize: coverSize
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ColorTheme.surface.opacity(0.35))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    )
                }
            }
        }

        // Pool
        let poolItems: [UserListItem] = items
            .filter {
                let t = ($0.tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty || !labels.contains(t)
            }
            .sorted { ($0.addedAt ?? Date.distantPast) > ($1.addedAt ?? Date.distantPast) }

        return ScrollView {
            VStack(spacing: 16) {
                lanesSection

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pool")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.subtext)
                        if editTierMode {
                            Text("Drag from here into any tier")
                                .font(.caption)
                                .foregroundColor(ColorTheme.subtext)
                        }
                        Spacer()
                    }
                    TierPoolView(
                        listId: list.id,
                        items: poolItems,
                        allItems: $items,
                        editMode: $editTierMode,
                        draggingItemID: $draggingItemID,
                        coverSize: coverSize,
                        onDelete: { deleteId in
                            // Persisted delete
                            deleteItems([deleteId])
                        }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ColorTheme.surface.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    )
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Row for non-ranked/non-tiered lists

    private func itemRow(_ it: UserListItem, showRank: Bool = false) -> some View {
        HStack(spacing: 10) {
            CoverFetchView(item: it, cornerRadius: 10, width: 70, height: 93)
                .frame(width: 70, height: 93)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(for: it))
                    .foregroundColor(ColorTheme.text)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let y = it.releaseYear {
                        Text(String(y)).font(.caption).foregroundColor(ColorTheme.subtext)
                    }
                    if list.type == .tiered, let t = it.tier {
                        Text(t).font(.caption.weight(.semibold)).foregroundColor(ColorTheme.subtext)
                    }
                }
            }
            Spacer()
            if showRank {
                Text("\( (it.order ?? 0) + 1 )")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundColor(ColorTheme.subtext)
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isOwner && rankedEditMode {
                Button(role: .destructive) { deleteItems([it.id]) } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Loads

    private func loadItems() {
        loading = true
        errorText = ""
        db.collection("lists").document(list.id)
            .collection("items")
            // IMPORTANT: always order by "added_at" so docs without "order" still return.
            .order(by: "added_at", descending: false)
            .getDocuments { snap, err in
                loading = false
                if let err = err {
                    errorText = err.localizedDescription
                    items = []
                    return
                }
                let parsed: [UserListItem] = (snap?.documents ?? []).compactMap { d in
                    var dict = d.data()
                    // Inject list_id so the model can validate
                    dict["list_id"] = list.id
                    return UserListItem(id: d.documentID, data: dict)
                }
                items = parsed
                hydrateItemNamesIfNeeded(parsed)
            }
    }

    private func hydrateItemNamesIfNeeded(_ parsed: [UserListItem]) {
        let ids = Array(Set(parsed.filter {
            let n = $0.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty || n.hasPrefix("Game #") || n == "Unknown Game"
        }.map { $0.gameId }))
        guard !ids.isEmpty else { return }
        Task {
            let fetched = await GameNameCache.shared.fillAndGet(namesFor: ids)
            await MainActor.run {
                var updated = nameCache
                for (gid, name) in fetched where !name.isEmpty {
                    updated[gid] = name
                }
                nameCache = updated
            }
        }
    }

    private func displayName(for item: UserListItem) -> String {
        let name = item.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.hasPrefix("Game #") || name == "Unknown Game" {
            if let cached = nameCache[item.gameId], !cached.isEmpty {
                return cached
            }
            return "Loading…"
        }
        return name
    }

    // MARK: - Actions

    private func deleteList() {
        guard isOwner else { return }
        db.collection("lists").document(list.id).delete { err in
            if let err = err { errorText = err.localizedDescription; return }
            dismiss()
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.compactMap { idx in items[safe: idx]?.id }
        deleteItems(ids)
    }

    private func deleteItems(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        ListsService.shared.removeItems(listId: list.id, itemIds: ids) {
            loadItems()
        }
    }

    // Ranked reordering (LIST layout)
    private func moveRanked(from source: IndexSet, to destination: Int) {
        var arr = items.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) })
        arr.move(fromOffsets: source, toOffset: destination)
        let updates: [(id: String, order: Int)] = arr.enumerated().map { (idx, it) in
            (id: it.id, order: idx)
        }
        isSavingOrder = true
        ListsService.shared.updateRanks(listId: list.id, updates: updates) {
            isSavingOrder = false
            loadItems()
        }
    }

    // Ranked reordering (GRID layout) — perform local reorder and mark dirty
    private func rankedGridMove(droppedId: String, before targetId: String?) {
        // Compute ordered snapshot
        var ordered = items.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        guard let fromIndex = ordered.firstIndex(where: { $0.id == droppedId }) else { return }

        // Remove
        let moving = ordered.remove(at: fromIndex)

        // Compute destination
        if let targetId = targetId, let targetIndex = ordered.firstIndex(where: { $0.id == targetId }) {
            ordered.insert(moving, at: targetIndex)
        } else {
            ordered.append(moving)
        }

        // Reindex -> write back to items (local)
        for (idx, it) in ordered.enumerated() {
            if let globalIdx = items.firstIndex(where: { $0.id == it.id }) {
                items[globalIdx].order = idx
            }
        }
        rankedGridDirty = true
    }

    private func saveRankedOrderFromCurrentItems() {
        let ordered = items.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        let updates: [(id: String, order: Int)] = ordered.enumerated().map { (idx, it) in
            (id: it.id, order: idx)
        }
        isSavingOrder = true
        ListsService.shared.updateRanks(listId: list.id, updates: updates) {
            isSavingOrder = false
            rankedGridDirty = false
            rankedEditMode = false
            loadItems()
        }
    }

    // Tiered: persist current in-memory lane/tier positions to Firestore
    private func saveTierPositions() {
        // Build array of (id, order, tier) from current state
        let updates: [(id: String, order: Int, tier: String?)] = items
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
            .map { it in
                (id: it.id, order: it.order ?? 0, tier: it.tier)
            }

        isSavingOrder = true
        ListsService.shared.updateTierPositions(listId: list.id, items: updates) {
            isSavingOrder = false
            editTierMode = false
            loadItems()
        }
    }

    // MARK: - Helpers

    private func defaultTierLabel(_ idx: Int) -> String {
        let defaults = ["S","A","B","C","D"]
        return defaults.indices.contains(idx) ? defaults[idx] : "T\(idx+1)"
    }

    private func normalizedTierLabels() -> [String] {
        let defaults = ["S","A","B","C","D"]
        guard list.type == .tiered else { return defaults }
        let labels = list.tierLabels ?? defaults
        var result = Array(labels.prefix(5))
        while result.count < 5 { result.append(defaults[result.count]) }
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func normalizedTierColors() -> [String] {
        let defaults = ["#E74C3C","#E67E22","#F1C40F","#2ECC71","#3498DB"]
        guard list.type == .tiered else { return defaults }
        let colors = list.tierColors ?? defaults
        var result = Array(colors.prefix(5))
        while result.count < 5 { result.append(defaults[result.count]) }
        return result
    }

    private func colorFromHex(_ hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var v = trimmed
        if v.hasPrefix("#") { v.removeFirst() }
        guard v.count == 6, let num = Int(v, radix: 16) else {
            return ColorTheme.surface
        }
        let r = Double((num >> 16) & 0xFF) / 255.0
        let g = Double((num >> 8) & 0xFF) / 255.0
        let b = Double(num & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    // Handle a drop onto a ranked GRID cell (targetId may be nil for end)
    private func handleRankedGridDrop(onTargetId targetId: String?, providers: [NSItemProvider]) -> Bool {
        guard rankedEditMode else { return false }
        let idUT = UTType.plainText

        for p in providers {
            if p.hasItemConformingToTypeIdentifier(idUT.identifier) {
                p.loadItem(forTypeIdentifier: idUT.identifier, options: nil) { (data, _) in
                    DispatchQueue.main.async {
                        var droppedId: String?
                        if let strData = data as? Data, let s = String(data: strData, encoding: .utf8) {
                            droppedId = s
                        } else if let s = data as? String {
                            droppedId = s
                        }
                        if let d = droppedId {
                            rankedGridMove(droppedId: d, before: targetId)
                        }
                        draggingItemID = nil
                    }
                }
                return true
            }
        }
        return false
    }
}

// MARK: - Tier Lane

private struct TierLaneView: View {
    let tierId: String?
    var items: [UserListItem]

    @Binding var allItems: [UserListItem]
    @Binding var editMode: Bool
    @Binding var draggingItemID: String?

    let laneHeight: CGFloat
    let coverSize: CGSize

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }), id: \.id) { it in
                    ZStack(alignment: .topLeading) {
                        CoverFetchView(item: it, cornerRadius: 10, width: coverSize.width, height: coverSize.height)
                            .frame(width: coverSize.width, height: coverSize.height)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke((editMode && draggingItemID == it.id) ? ColorTheme.accent : Color.clear, lineWidth: 2)
                            )
                            .onDragIf(editMode, item: it.id) { draggingItemID = it.id }

                        // Move to Pool (X) — visible only in edit mode
                        if editMode {
                            Button {
                                moveItemToPool(withId: it.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(6)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                    .foregroundColor(.white)
                                    .accessibilityLabel("Move to Pool")
                            }
                            .padding(4)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: laneHeight)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard editMode else { return false }
        let idUT = UTType.plainText

        for p in providers {
            if p.hasItemConformingToTypeIdentifier(idUT.identifier) {
                p.loadItem(forTypeIdentifier: idUT.identifier, options: nil) { (data, _) in
                    DispatchQueue.main.async {
                        if let strData = data as? Data, let s = String(data: strData, encoding: .utf8) {
                            moveItem(withId: s, to: tierId)
                        } else if let s = data as? String {
                            moveItem(withId: s, to: tierId)
                        }
                        draggingItemID = nil
                    }
                }
                return true
            }
        }
        return false
    }

    private func moveItem(withId id: String, to targetTier: String?) {
        guard let idx = allItems.firstIndex(where: { $0.id == id }) else { return }
        let laneItems = allItems
            .filter { ($0.tier ?? "") == (targetTier ?? "") && $0.id != id }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        let nextOrder = (laneItems.last?.order ?? -1) + 1
        var it = allItems[idx]
        it.tier = targetTier
        it.order = nextOrder
        allItems[idx] = it
    }

    private func moveItemToPool(withId id: String) {
        guard let idx = allItems.firstIndex(where: { $0.id == id }) else { return }
        // Compute next pool order
        let poolItems = allItems.filter {
            let t = ($0.tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty
        }
        let nextOrder = (poolItems.map { $0.order ?? 0 }.max() ?? -1) + 1
        var it = allItems[idx]
        it.tier = nil
        it.order = nextOrder
        allItems[idx] = it
    }
}

// MARK: - Tier Pool

private struct TierPoolView: View {
    let listId: String
    var items: [UserListItem]

    @Binding var allItems: [UserListItem]
    @Binding var editMode: Bool
    @Binding var draggingItemID: String?

    let coverSize: CGSize
    let onDelete: (String) -> Void

    private var grid: [GridItem] {
        [GridItem(.adaptive(minimum: coverSize.width), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: grid, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.id) { it in
                ZStack(alignment: .topLeading) {
                    CoverFetchView(item: it, cornerRadius: 10, width: coverSize.width, height: coverSize.height)
                        .frame(width: coverSize.width, height: coverSize.height)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke((editMode && draggingItemID == it.id) ? ColorTheme.accent : Color.clear, lineWidth: 2)
                        )
                        .onDragIf(editMode, item: it.id) { draggingItemID = it.id }

                    // Trash (delete from list) — visible only in edit mode
                    if editMode {
                        Button {
                            onDelete(it.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .bold))
                                .padding(6)
                                .background(Color.black.opacity(0.65))
                                .clipShape(Circle())
                                .foregroundColor(.white)
                                .accessibilityLabel("Remove from List")
                        }
                        .padding(4)
                    }
                }
            }
        }
        .padding(8)
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            handleDropToPool(providers)
        }
    }

    private func handleDropToPool(_ providers: [NSItemProvider]) -> Bool {
        guard editMode else { return false }
        let idUT = UTType.plainText

        for p in providers {
            if p.hasItemConformingToTypeIdentifier(idUT.identifier) {
                p.loadItem(forTypeIdentifier: idUT.identifier, options: nil) { (data, _) in
                    DispatchQueue.main.async {
                        var droppedId: String?
                        if let strData = data as? Data, let s = String(data: strData, encoding: .utf8) {
                            droppedId = s
                        } else if let s = data as? String {
                            droppedId = s
                        }
                        if let id = droppedId, let idx = allItems.firstIndex(where: { $0.id == id }) {
                            let poolItems = allItems.filter {
                                let t = ($0.tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                return t.isEmpty
                            }
                            let nextOrder = (poolItems.map { $0.order ?? 0 }.max() ?? -1) + 1
                            var it = allItems[idx]
                            it.tier = nil
                            it.order = nextOrder
                            allItems[idx] = it
                        }
                        draggingItemID = nil
                    }
                }
                return true
            }
        }
        return false
    }
}

// MARK: - CoverFetchView (uses AsyncImage + direct IGDB URL)

private struct CoverFetchView: View {
    let item: UserListItem
    let cornerRadius: CGFloat
    let width: CGFloat
    let height: CGFloat

    @State private var resolvedImageId: String? = nil
    @State private var showDebugId: Bool = false

    private let db = Firestore.firestore()
    private let igdb = IGDBService()

    var body: some View {
        let effectiveImageId = (resolvedImageId ?? item.coverImageId)?.trimmingCharacters(in: .whitespacesAndNewlines)

        Group {
            if let iid = effectiveImageId, !iid.isEmpty, let url = igdbCoverURL(imageId: iid) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: height)
                            .clipped()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .onLongPressGesture {
                    withAnimation { showDebugId.toggle() }
                }
                .overlay(alignment: .bottom) {
                    if showDebugId, let text = effectiveImageId {
                        Text(text)
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .padding(2)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(2)
                    }
                }
            } else {
                placeholder
                    .onAppear(perform: tryResolveAndPersistCover)
            }
        }
        .frame(width: width, height: height)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(ColorTheme.separator.opacity(0.2))
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(ColorTheme.subtext.opacity(0.8))
            )
            .frame(width: width, height: height)
    }

    private func igdbCoverURL(imageId: String, size: String = "t_cover_big") -> URL? {
        URL(string: "https://images.igdb.com/igdb/image/upload/\(size)/\(imageId).jpg")
    }

    private func tryResolveAndPersistCover() {
        igdb.fetchGameById(id: item.gameId) { result in
            if case .success(let g) = result, let imgId = g.cover?.imageId, !imgId.isEmpty {
                DispatchQueue.main.async {
                    self.resolvedImageId = imgId
                }
                // Persist for next loads (requires rules that allow updating cover_image_id)
                let ref = db.collection("lists").document(item.listId)
                    .collection("items").document(item.id)
                ref.setData(["cover_image_id": imgId], merge: true)
            }
        }
    }
}

// MARK: - Safe array indexing

private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}

// MARK: - Conditional onDrag helper

private extension View {
    @ViewBuilder
    func onDragIf(_ condition: Bool, item: String, setDragging: @escaping () -> Void) -> some View {
        if condition {
            self.onDrag {
                setDragging()
                return NSItemProvider(object: item as NSString)
            }
        } else {
            self
        }
    }
}
