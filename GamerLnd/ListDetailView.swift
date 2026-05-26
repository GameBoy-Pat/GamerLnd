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
    @State private var currentListTitle: String = ""
    @State private var currentListIsPublic: Bool = true
    @State private var currentListUpdatedAt: Timestamp
    @State private var draftListTitle: String = ""
    @State private var draftListIsPublic: Bool = true
    @State private var showEditMetaSheet: Bool = false

    // UI
    @State private var showAddSheet: Bool = false
    @State private var showConfirmDelete: Bool = false
    @State private var isSavingOrder: Bool = false

    // Tier edit mode
    @State private var editTierMode: Bool = false
    @State private var draggingItemID: String? = nil
    @State private var editableTierLabels: [String] = []
    @State private var editableTierColors: [String] = []
    @State private var editableTierTextColors: [String] = []
    @State private var editingTierIndex: Int? = nil
    @State private var liftedPoolItemId: String? = nil

    // Ranked edit + layout
    enum RankedLayout { case list, grid }
    @State private var rankedEditMode: Bool = false
    @State private var rankedLayout: RankedLayout = .list
    @State private var rankedGridDirty: Bool = false // track unsaved grid edits

    private let db = Firestore.firestore()

    init(list: UserList, isOwner: Bool) {
        self.list = list
        self.isOwner = isOwner
        _currentListTitle = State(initialValue: list.title)
        _currentListIsPublic = State(initialValue: list.isPublic)
        _currentListUpdatedAt = State(initialValue: list.updatedAt)
        _draftListTitle = State(initialValue: list.title)
        _draftListIsPublic = State(initialValue: list.isPublic)
    }

    var body: some View {
        VStack(spacing: 0) {
            if list.type != .tiered {
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
            }

            if loading {
                ProgressView().tint(ColorTheme.accent).padding()
            }

            contentList
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
        .onAppear {
            seedTierEditorStateIfNeeded()
            loadItems()
        }
        .overlay {
            if showAddSheet, let uid = Auth.auth().currentUser?.uid {
                ZStack {
                    OverlayBackdrop()
                        .ignoresSafeArea()
                        .onTapGesture {
                            showAddSheet = false
                            loadItems()
                        }

                    AddGamesToListSheet(
                        listId: list.id,
                        ownerId: uid,
                        onClose: {
                            showAddSheet = false
                            loadItems()
                        },
                        onAdded: {
                            loadItems()
                        }
                    )
                    .frame(width: min(UIScreen.main.bounds.width - 24, 390),
                           height: min(UIScreen.main.bounds.height - 180, 640))
                    .padding(.horizontal, 12)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .overlay {
            if let idx = editingTierIndex {
                tierHeaderEditorOverlay(index: idx)
            }
        }
        .confirmationDialog("Delete this list?", isPresented: $showConfirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteList() }
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if showEditMetaSheet {
                listMetaEditorOverlay
            }
        }
    }

    // MARK: - Header

    private var tieredHeroHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentListTitle)
                        .font(.title3.weight(.heavy))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    if !list.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(list.description)
                            .font(.caption)
                            .foregroundColor(ColorTheme.subtext)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Image(systemName: currentListIsPublic ? "globe" : "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(currentListIsPublic ? ColorTheme.accent : ColorTheme.subtext)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(ColorTheme.separator, lineWidth: 1))

                    if isOwner && editTierMode {
                        Image(systemName: "pencil")
                            .font(.footnote.weight(.bold))
                            .foregroundColor(ColorTheme.accent)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9).fill(ColorTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(ColorTheme.separator, lineWidth: 1))
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(Array(normalizedTierColors().prefix(5).enumerated()), id: \.offset) { idx, hex in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorFromHex(hex))
                        .frame(width: 20, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ColorTheme.separator.opacity(0.35), lineWidth: 0.75)
                        )
                        .onTapGesture {
                            guard isOwner && editTierMode else { return }
                            editingTierIndex = idx
                        }
                }

                Spacer()

                if editTierMode {
                    Text("Tap a color chip or lane label to edit")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.subtext)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [ColorTheme.surface.opacity(0.92), ColorTheme.surface.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(ColorTheme.separator, lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 0)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    guard isOwner && (editTierMode || rankedEditMode) else { return }
                    draftListTitle = currentListTitle
                    draftListIsPublic = currentListIsPublic
                    showEditMetaSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Text(currentListTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(ColorTheme.text)
                        if isOwner && (editTierMode || rankedEditMode) {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.bold))
                                .foregroundColor(ColorTheme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
                if list.type == .tiered {
                    HStack(spacing: 4) {
                        ForEach(Array(normalizedTierColors().prefix(5).enumerated()), id: \.offset) { idx, hex in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colorFromHex(hex))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(ColorTheme.separator.opacity(0.35), lineWidth: 0.5)
                                )
                                .onTapGesture {
                                    guard isOwner && editTierMode else { return }
                                    editingTierIndex = idx
                                }
                        }
                    }
                }
                Button {
                    guard isOwner && (editTierMode || rankedEditMode) else { return }
                    draftListTitle = currentListTitle
                    draftListIsPublic = currentListIsPublic
                    showEditMetaSheet = true
                } label: {
                    Image(systemName: currentListIsPublic ? "globe" : "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(currentListIsPublic ? ColorTheme.accent : ColorTheme.subtext)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ColorTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ColorTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .padding(.bottom, 4)
    }

    private var listMetaEditorOverlay: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    showEditMetaSheet = false
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Edit List")
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Button {
                        showEditMetaSheet = false
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                }

                TextField("List title", text: $draftListTitle)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ColorTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))
                    .foregroundColor(ColorTheme.text)

                Toggle(isOn: $draftListIsPublic) {
                    HStack(spacing: 8) {
                        Image(systemName: draftListIsPublic ? "globe" : "lock.fill")
                            .foregroundColor(draftListIsPublic ? ColorTheme.accent : ColorTheme.subtext)
                        Text(draftListIsPublic ? "Public list" : "Private list")
                            .foregroundColor(ColorTheme.text)
                    }
                }
                .tint(ColorTheme.accent)

                Button {
                    saveListMeta()
                } label: {
                    Text("Save")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(ColorTheme.accent))
                }
                .buttonStyle(.plain)
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

                            if rankedBadgeShouldShow(for: it) {
                                HStack(spacing: 6) {
                                    if let decoration = rankedDecorationChoice(for: it) {
                                        rankedDecorationIcon(decoration)
                                            .frame(width: 12, height: 12)
                                    }
                                    if list.rankedShowNumbers {
                                        Text("\((it.order ?? 0) + 1)")
                                    }
                                }
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.black.opacity(0.65))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .padding(6)
                            }

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
        let textColors = normalizedTierTextColors()

        let poolItems: [UserListItem] = items
            .filter {
                let t = ($0.tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty || !labels.contains(t)
            }
            .sorted { ($0.addedAt ?? Date.distantPast) > ($1.addedAt ?? Date.distantPast) }

        return GeometryReader { proxy in
            let availableHeight = proxy.size.height
            let laneHeight = max(78.0, min(94.0, (availableHeight - 170.0) / 6.0))
            let coverHeight = max(68.0, min(80.0, laneHeight - 16.0))
            let coverWidth = coverHeight * 0.76
            let coverSize = CGSize(width: coverWidth, height: coverHeight)
            let leftColWidth = max(58.0, min(68.0, laneHeight * 0.68))
            let laneSpacing = max(6.0, min(9.0, (availableHeight - 520.0) / 18.0 + 7.0))

            VStack(spacing: 8) {
                tieredHeroHeader

                VStack(spacing: laneSpacing) {
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
                                        .foregroundColor(colorFromHex(textColors[idx]))
                                )
                                .frame(width: leftColWidth, height: laneHeight)
                                .onTapGesture {
                                    guard isOwner && editTierMode else { return }
                                    editingTierIndex = idx
                                }

                            TierLaneView(
                                tierId: label,
                                items: laneItems,
                                allItems: $items,
                                editMode: $editTierMode,
                                draggingItemID: $draggingItemID,
                                laneHeight: laneHeight,
                                coverSize: coverSize,
                                onMoveWithinTier: { itemId, direction in
                                    moveTierItem(itemId, within: label, direction: direction)
                                }
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(ColorTheme.surface.opacity(0.35))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pool")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.subtext)
                        if editTierMode {
                            Text(liftedPoolItemId == nil ? "Tap or drag a game into any tier" : "Lifted for quick dragging")
                                .font(.caption2)
                                .foregroundColor(ColorTheme.subtext)
                        }
                        Spacer()
                    }
                    TierPoolView(
                        items: poolItems,
                        allItems: $items,
                        editMode: $editTierMode,
                        draggingItemID: $draggingItemID,
                        liftedItemID: $liftedPoolItemId,
                        coverSize: coverSize,
                        onDelete: { deleteId in
                            deleteItems([deleteId], reloadAfter: false)
                        }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ColorTheme.surface.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ColorTheme.separator, lineWidth: 1))
                    )
                }
                .padding(.top, 2)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 12)
            .padding(.top, 0)
            .padding(.bottom, 6)
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
            if showRank, rankedBadgeShouldShow(for: it) {
                HStack(spacing: 6) {
                    if let decoration = rankedDecorationChoice(for: it) {
                        rankedDecorationIcon(decoration)
                            .frame(width: 14, height: 14)
                    }
                    if list.rankedShowNumbers {
                        Text("\( (it.order ?? 0) + 1 )")
                    }
                }
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

    private func deleteItems(_ ids: [String], reloadAfter: Bool = true) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        ListsService.shared.removeItems(listId: list.id, itemIds: ids) {
            currentListUpdatedAt = Timestamp(date: Date())
            if reloadAfter {
                loadItems()
            }
        }
    }

    private func saveListMeta() {
        let trimmed = draftListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentListTitle = trimmed
        currentListIsPublic = draftListIsPublic
        currentListUpdatedAt = Timestamp(date: Date())
        ListsService.shared.updateListMeta(
            listId: list.id,
            title: trimmed,
            description: list.description,
            isPublic: draftListIsPublic,
            type: list.type,
            tierLabels: list.tierLabels,
            tierColors: list.tierColors,
            tierTextColors: list.tierTextColors,
            rankedShowNumbers: list.rankedShowNumbers,
            rankedTopDecoration: list.rankedTopDecoration
        )
        showEditMetaSheet = false
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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
            currentListUpdatedAt = Timestamp(date: Date())
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
            currentListUpdatedAt = Timestamp(date: Date())
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
            ListsService.shared.updateListMeta(
                listId: list.id,
                title: currentListTitle,
                description: list.description,
                isPublic: currentListIsPublic,
                type: list.type,
                tierLabels: editableTierLabels,
                tierColors: editableTierColors,
                tierTextColors: editableTierTextColors
            ) {
                isSavingOrder = false
                editTierMode = false
                currentListUpdatedAt = Timestamp(date: Date())
                SecretUnlockService.shared.evaluateTierListSecrets(
                    userId: list.ownerId,
                    isPublic: currentListIsPublic,
                    tierLabels: editableTierLabels,
                    tierColors: editableTierColors,
                    itemTierLabels: items.compactMap(\.tier)
                )
                SecretUnlockService.shared.evaluateTierListSecretsForList(userId: list.ownerId, listId: list.id)
                SecretUnlockService.shared.reevaluateListSecrets(userId: list.ownerId)
                loadItems()
            }
        }
    }

    // MARK: - Helpers

    private func rankedDecorationChoice(for item: UserListItem) -> String? {
        guard list.type == .ranked, (item.order ?? 0) == 0 else { return nil }
        return list.rankedTopDecoration ?? "medal"
    }

    private func rankedBadgeShouldShow(for item: UserListItem) -> Bool {
        guard list.type == .ranked else { return false }
        return list.rankedShowNumbers || rankedDecorationChoice(for: item) != nil
    }

    @ViewBuilder
    private func rankedDecorationIcon(_ choice: String) -> some View {
        #if canImport(UIKit)
        if UIImage(named: rankedDecorationAssetName(choice)) != nil {
            Image(rankedDecorationAssetName(choice))
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: rankedDecorationSystemName(choice))
                .resizable()
                .scaledToFit()
        }
        #else
        Image(systemName: rankedDecorationSystemName(choice))
            .resizable()
            .scaledToFit()
        #endif
    }

    private func rankedDecorationAssetName(_ choice: String) -> String {
        switch choice {
        case "trophy": return "trophy-solid-full"
        case "award": return "award-solid-full"
        default: return "medal-solid-full"
        }
    }

    private func rankedDecorationSystemName(_ choice: String) -> String {
        switch choice {
        case "trophy": return "trophy.fill"
        case "award": return "rosette"
        default: return "medal.fill"
        }
    }

    private func defaultTierLabel(_ idx: Int) -> String {
        let defaults = ["S","A","B","C","D"]
        return defaults.indices.contains(idx) ? defaults[idx] : "T\(idx+1)"
    }

    private func normalizedTierLabels() -> [String] {
        let defaults = ["S","A","B","C","D"]
        guard list.type == .tiered else { return defaults }
        let labels = editableTierLabels.isEmpty ? (list.tierLabels ?? defaults) : editableTierLabels
        var result = Array(labels.prefix(5))
        while result.count < 5 { result.append(defaults[result.count]) }
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func normalizedTierColors() -> [String] {
        let defaults = ["#E74C3C","#E67E22","#F1C40F","#2ECC71","#3498DB"]
        guard list.type == .tiered else { return defaults }
        let colors = editableTierColors.isEmpty ? (list.tierColors ?? defaults) : editableTierColors
        var result = Array(colors.prefix(5))
        while result.count < 5 { result.append(defaults[result.count]) }
        return result
    }

    private func normalizedTierTextColors() -> [String] {
        let defaults = ["#FFFFFF","#FFFFFF","#FFFFFF","#FFFFFF","#FFFFFF"]
        guard list.type == .tiered else { return defaults }
        let colors = editableTierTextColors.isEmpty ? (list.tierTextColors ?? defaults) : editableTierTextColors
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

    private func hexString(from color: Color) -> String {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#FFFFFF"
        }
        return String(format: "#%02X%02X%02X",
                      Int(red * 255),
                      Int(green * 255),
                      Int(blue * 255))
        #else
        return "#FFFFFF"
        #endif
    }

    private func seedTierEditorStateIfNeeded() {
        if editableTierLabels.isEmpty { editableTierLabels = normalizedTierLabels() }
        if editableTierColors.isEmpty { editableTierColors = normalizedTierColors() }
        if editableTierTextColors.isEmpty { editableTierTextColors = normalizedTierTextColors() }
    }

    private func moveTierItem(_ itemId: String, within tierLabel: String, direction: Int) {
        let laneItems = items
            .filter { ($0.tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == tierLabel }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        guard let currentIndex = laneItems.firstIndex(where: { $0.id == itemId }) else { return }
        let destination = currentIndex + direction
        guard laneItems.indices.contains(destination) else { return }

        let movingId = laneItems[currentIndex].id
        let targetId = laneItems[destination].id
        guard
            let movingIndex = items.firstIndex(where: { $0.id == movingId }),
            let targetIndex = items.firstIndex(where: { $0.id == targetId })
        else { return }

        let movingOrder = items[movingIndex].order ?? currentIndex
        let targetOrder = items[targetIndex].order ?? destination
        items[movingIndex].order = targetOrder
        items[targetIndex].order = movingOrder
    }

    @ViewBuilder
    private func tierHeaderEditorOverlay(index: Int) -> some View {
        let title = editableTierLabels[safe: index] ?? defaultTierLabel(index)
        let fillColor = colorFromHex(editableTierColors[safe: index] ?? "#3A3A3A")
        let textColor = colorFromHex(editableTierTextColors[safe: index] ?? "#FFFFFF")
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture { editingTierIndex = nil }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Edit Tier Header")
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                    Button("Done") { editingTierIndex = nil }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }

                TextField("Tier label", text: Binding(
                    get: { editableTierLabels[safe: index] ?? defaultTierLabel(index) },
                    set: { value in
                        seedTierEditorStateIfNeeded()
                        editableTierLabels[index] = String(value.prefix(6))
                    }
                ))
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(ColorTheme.surface))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Block Color")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                    ColorPicker("", selection: Binding(
                        get: { fillColor },
                        set: { newColor in
                            seedTierEditorStateIfNeeded()
                            editableTierColors[index] = hexString(from: newColor)
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Text Color")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                    ColorPicker("", selection: Binding(
                        get: { textColor },
                        set: { newColor in
                            seedTierEditorStateIfNeeded()
                            editableTierTextColors[index] = hexString(from: newColor)
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }

                RoundedRectangle(cornerRadius: 12)
                    .fill(fillColor)
                    .frame(height: 64)
                    .overlay(
                        Text(title.isEmpty ? defaultTierLabel(index) : title)
                            .font(.title3.weight(.bold))
                            .foregroundColor(textColor)
                    )
            }
            .padding(16)
            .frame(width: min(UIScreen.main.bounds.width - 32, 360))
            .background(RoundedRectangle(cornerRadius: 18).fill(ColorTheme.background))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ColorTheme.separator, lineWidth: 1))
        }
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
    enum TierMoveDirection {
        case left
        case right
    }

    let tierId: String?
    var items: [UserListItem]

    @Binding var allItems: [UserListItem]
    @Binding var editMode: Bool
    @Binding var draggingItemID: String?

    let laneHeight: CGFloat
    let coverSize: CGSize
    let onMoveWithinTier: (String, Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }), id: \.id) { it in
                    VStack(spacing: 4) {
                        ZStack(alignment: .topLeading) {
                            CoverFetchView(item: it, cornerRadius: 10, width: coverSize.width, height: coverSize.height)
                                .frame(width: coverSize.width, height: coverSize.height)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke((editMode && draggingItemID == it.id) ? ColorTheme.accent : Color.clear, lineWidth: 2)
                                )
                                .onDragIf(editMode, item: it.id) { draggingItemID = it.id }

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

                        if editMode {
                            HStack(spacing: 6) {
                                Button {
                                    onMoveWithinTier(it.id, -1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(ColorTheme.text)
                                        .frame(width: 22, height: 18)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.surface))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    onMoveWithinTier(it.id, 1)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(ColorTheme.text)
                                        .frame(width: 22, height: 18)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.surface))
                                }
                                .buttonStyle(.plain)
                            }
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
    var items: [UserListItem]

    @Binding var allItems: [UserListItem]
    @Binding var editMode: Bool
    @Binding var draggingItemID: String?
    @Binding var liftedItemID: String?

    let coverSize: CGSize
    let onDelete: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.id) { it in
                    ZStack(alignment: .topLeading) {
                        CoverFetchView(item: it, cornerRadius: 10, width: coverSize.width, height: coverSize.height)
                            .frame(width: coverSize.width, height: coverSize.height)
                            .scaleEffect(liftedItemID == it.id ? 1.16 : 1.0)
                            .shadow(color: liftedItemID == it.id ? ColorTheme.accent.opacity(0.28) : .clear, radius: 10, x: 0, y: 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke((editMode && (draggingItemID == it.id || liftedItemID == it.id)) ? ColorTheme.accent : Color.clear, lineWidth: 2)
                            )
                            .onDragIf(editMode, item: it.id) {
                                draggingItemID = it.id
                                liftedItemID = it.id
                            }
                            .onTapGesture {
                                guard editMode else { return }
                                liftedItemID = (liftedItemID == it.id) ? nil : it.id
                            }

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
        }
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
                        liftedItemID = nil
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
