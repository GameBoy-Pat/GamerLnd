// ListEditorSheet.swift
// Create / edit a List (Regular, Ranked, Tiered).
//
// THIS PASS (full file; no features removed):
// • Type selection uses a segmented control (slider-style) like your Status bars.
// • NEW: In EDIT mode, a "Manage Games" section with "Add Games" button opens a compact
//   search sheet for quick-adding games to this list.
// • Everything else preserved: public toggle, description, tier label/color editors,
//   create/update/delete flows, validation, Firestore payloads that match your rules.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ListEditorSheet: View {
    // Owner of the list (uid). Callers pass the profile's userId. Rules check this.
    let ownerId: String
    var onCreated: ((UserList) -> Void)? = nil

    // When present, we're editing an existing list; otherwise we're creating a new one.
    var existing: UserList? = nil

    @Environment(\.dismiss) private var dismiss

    // MARK: - Form state

    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var type: ListType = .regular
    @State private var isPublic: Bool = true

    // Tiered-only fields (5 default rows; matches our Tier grid S/A/B/C/D)
    @State private var tierLabels: [String] = ["S", "A", "B", "C", "D"]
    @State private var tierColors: [String] = ["", "", "", "", ""] // hex (#RRGGBB) or "" for none

    // UI state
    @State private var isSaving: Bool = false
    @State private var isDeleting: Bool = false
    @State private var errorText: String = ""
    @State private var showAddGames: Bool = false

    // MARK: - Init (pre-fill when editing)
    init(ownerId: String, existing: UserList? = nil, onCreated: ((UserList) -> Void)? = nil) {
        self.ownerId = ownerId
        self.existing = existing
        self.onCreated = onCreated

        // NOTE: We can't assign to @State in init directly, but we can set the _State wrappers.
        if let e = existing {
            _title = State(initialValue: e.title)
            _descriptionText = State(initialValue: e.description)
            _type = State(initialValue: e.type)
            _isPublic = State(initialValue: e.isPublic)
            // If the list already has tier metadata, prefill those (safe defaults otherwise)
            _tierLabels = State(initialValue: e.tierLabels ?? ["S", "A", "B", "C", "D"])
            _tierColors = State(initialValue: e.tierColors ?? ["", "", "", "", ""])
        }
    }

    var body: some View {
        NavigationView {
            Form {
                // DETAILS
                Section(header: Text("Details").foregroundColor(ColorTheme.subtext)) {
                    TextField("Title", text: $title)
                        .foregroundColor(ColorTheme.text)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .onChange(of: title) { _, _ in errorText = "" }

                    TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                        .foregroundColor(ColorTheme.text)

                    // Slider-style type picker (segmented control)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Type")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ColorTheme.subtext)
                        Picker("", selection: $type) {
                            Text("Regular").tag(ListType.regular)
                            Text("Ranked").tag(ListType.ranked)
                            Text("Tiered").tag(ListType.tiered)
                        }
                        .pickerStyle(.segmented)
                        .tint(ColorTheme.accent)
                    }

                    Toggle("Public", isOn: $isPublic)
                        .tint(ColorTheme.accent)
                        .accessibilityHint(Text("If on, others can view this list"))
                }
                .listRowBackground(ColorTheme.surface)

                // TIERED OPTIONS (only shows when Type == .tiered)
                if type == .tiered {
                    Section(header: Text("Tier Settings").foregroundColor(ColorTheme.subtext),
                            footer: Text("Leave color blank for no background. Use hex like #FFAA00.")
                                .font(.caption).foregroundColor(ColorTheme.subtext)) {

                        // We provide 5 rows by default. If a future version needs more, this can be dynamic.
                        ForEach(0..<min(tierLabels.count, tierColors.count), id: \.self) { idx in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Tier \(idxLabel(idx))")
                                        .foregroundColor(ColorTheme.text)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                }

                                // Label
                                TextField("Label (e.g. S, A, B…)", text: Binding(
                                    get: { safeIndex(tierLabels, idx) ?? "" },
                                    set: { val in setArray(&tierLabels, idx, val) }
                                ))
                                .foregroundColor(ColorTheme.text)

                                // Hex color (kept simple per your request—no live color picker)
                                TextField("Hex Color (e.g. #FFAA00) or leave blank", text: Binding(
                                    get: { safeIndex(tierColors, idx) ?? "" },
                                    set: { val in setArray(&tierColors, idx, val) }
                                ))
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .foregroundColor(ColorTheme.text)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowBackground(ColorTheme.surface)
                }

                // MANAGE GAMES (edit-only)
                if let e = existing {
                    Section(header: Text("Manage Games").foregroundColor(ColorTheme.subtext)) {
                        Button {
                            showAddGames = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "text.badge.plus")
                                Text("Add Games")
                            }
                            .foregroundColor(ColorTheme.accent)
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                    .listRowBackground(ColorTheme.surface)
                    .sheet(isPresented: $showAddGames) {
                        AddGamesToListSheet(listId: e.id, ownerId: ownerId)
                            .preferredColorScheme(ColorTheme.preferredScheme)
                            .presentationDetents([.fraction(0.85)])
                            .presentationDragIndicator(.hidden)
                            .presentationCornerRadius(16)
                    }
                }

                // ERROR
                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .font(.caption)
                            .foregroundColor(ColorTheme.highlight)
                    }
                    .listRowBackground(ColorTheme.surface)
                }

                // DANGER (Edit-only)
                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text(isDeleting ? "Deleting…" : "Delete List")
                            }
                        }
                        .disabled(isDeleting)
                    }
                    .listRowBackground(ColorTheme.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ColorTheme.background.ignoresSafeArea())

            .navigationTitle(existing == nil ? "New List" : "Edit List")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ColorTheme.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(existing == nil ? "Create" : "Save") { save() }
                        .bold()
                        .disabled(isSaving || titleTrimmed.isEmpty)
                }
            }
        }
        .tint(ColorTheme.accent)
        .preferredColorScheme(ColorTheme.preferredScheme)
    }

    // MARK: - Actions

    private var titleTrimmed: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validate fields and call service to create/update.
    private func save() {
        guard !ownerId.isEmpty else { return }
        errorText = ""

        // Basic validation
        guard !titleTrimmed.isEmpty else {
            errorText = "Please enter a title."
            return
        }

        // Sanitize hex values: allow "" or "#RRGGBB" (7 chars) or "RRGGBB" (6 chars).
        let cleanedColors = sanitizeHexArray(tierColors)

        isSaving = true

        if let e = existing {
            // EDIT MODE: Update meta + optional tier arrays (only for tiered)
            ListsService.shared.updateListMeta(
                listId: e.id,
                title: titleTrimmed,
                description: descriptionText,
                isPublic: isPublic,
                type: type,
                tierLabels: (type == .tiered) ? tierLabels : nil,
                tierColors: (type == .tiered) ? cleanedColors : nil
            ) {
                isSaving = false
                dismiss()
            }
            return
        }

        // CREATE MODE
        ListsService.shared.createList(
            ownerId: ownerId,
            title: titleTrimmed,
            description: descriptionText,
            type: type,
            isPublic: isPublic
        ) { result in
            isSaving = false
            switch result {
            case .success(let newList):
                onCreated?(newList)
                // If tiered, immediately patch tier arrays (optional but nice to have)
                if type == .tiered {
                    ListsService.shared.updateListMeta(
                        listId: newList.id,
                        title: newList.title,
                        description: newList.description,
                        isPublic: newList.isPublic,
                        type: newList.type,
                        tierLabels: tierLabels,
                        tierColors: cleanedColors
                    ) {
                        dismiss()
                    }
                } else {
                    dismiss()
                }
            case .failure(let err):
                errorText = err.localizedDescription
            }
        }
    }

    /// Confirm and delete (edit-only). Here we do a shallow delete: delete list doc.
    private func confirmDelete() {
        guard let e = existing else { return }
        isDeleting = true
        let db = Firestore.firestore()
        db.collection("lists").document(e.id).delete { err in
            isDeleting = false
            if let err = err {
                errorText = err.localizedDescription
            } else {
                dismiss()
            }
        }
    }

    // MARK: - Helpers (arrays, labels, hex)

    /// Safe index get for arrays to avoid out-of-bounds crashes.
    private func safeIndex<T>(_ arr: [T], _ idx: Int) -> T? {
        guard idx >= 0 && idx < arr.count else { return nil }
        return arr[idx]
    }

    /// Mutate array element at index (grow if needed to keep 5 entries).
    private func setArray(_ arr: inout [String], _ idx: Int, _ value: String) {
        if idx >= arr.count {
            while arr.count <= idx { arr.append("") }
        }
        arr[idx] = value
    }

    /// Human label for default rows (S/A/B/C/D). If user changes label, this is only used as section heading.
    private func idxLabel(_ idx: Int) -> String {
        let defaults = ["S", "A", "B", "C", "D"]
        return safeIndex(tierLabels, idx)?.isEmpty == false ? (safeIndex(tierLabels, idx) ?? defaults[idx]) : defaults[idx]
    }

    /// Normalize user hex inputs:
    /// - Accept "", "#RRGGBB", or "RRGGBB"
    /// - Return "" (no color) or "#RRGGBB" uniform style
    private func sanitizeHexArray(_ raw: [String]) -> [String] {
        raw.enumerated().map { (_, val) in
            let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            var v = trimmed.uppercased()
            if v.hasPrefix("#") { v.removeFirst() }
            let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
            if v.count == 6 && CharacterSet(charactersIn: v).isSubset(of: allowed) {
                return "#\(v)"
            }
            return ""
        }
    }
}

// PREVIEW
#if DEBUG
struct ListEditorSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ListEditorSheet(ownerId: "demo_owner")
                .preferredColorScheme(ColorTheme.preferredScheme)

            ListEditorSheet(
                ownerId: "demo_owner",
                existing: UserList(
                    id: "list_demo",
                    ownerId: "demo_owner",
                    title: "Top JRPGs",
                    description: "Favorites across gens",
                    type: .tiered,
                    isPublic: true,
                    createdAt: Timestamp(date: Date()),
                    updatedAt: Timestamp(date: Date()),
                    itemCount: 3,
                    tierLabels: ["S","A","B","C","D"],
                    tierColors: ["#FFAA00","","","",""]
                )
            )
            .preferredColorScheme(ColorTheme.preferredScheme)
        }
    }
}
#endif
