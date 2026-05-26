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
    @State private var tierTextColors: [String] = ["#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF"]
    @State private var rankedShowNumbers: Bool = true
    @State private var rankedTopDecoration: String = "medal"

    // UI state
    @State private var isSaving: Bool = false
    @State private var isDeleting: Bool = false
    @State private var errorText: String = ""
    @State private var showAddGames: Bool = false
    @FocusState private var focusedField: EditorField?

    private enum EditorField: Hashable {
        case title
        case description
        case tierLabel(Int)
    }

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
            _tierTextColors = State(initialValue: e.tierTextColors ?? ["#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF"])
            _rankedShowNumbers = State(initialValue: e.rankedShowNumbers)
            _rankedTopDecoration = State(initialValue: e.rankedTopDecoration ?? "medal")
        }
    }

    var body: some View {
        NavigationView {
            GeometryReader { _ in
                VStack(spacing: 10) {
                    detailsCard

                    if let e = existing {
                        manageGamesCard(for: e)
                    }

                    if !errorText.isEmpty {
                        compactCard {
                            Text(errorText)
                                .font(.caption)
                                .foregroundColor(ColorTheme.highlight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if existing != nil {
                        compactCard {
                            Button(role: .destructive) {
                                confirmDelete()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash")
                                    Text(isDeleting ? "Deleting…" : "Delete List")
                                    Spacer()
                                }
                            }
                            .disabled(isDeleting)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(ColorTheme.background.ignoresSafeArea())
            .sheet(isPresented: $showAddGames) {
                if let e = existing {
                    AddGamesToListSheet(listId: e.id, ownerId: ownerId)
                        .preferredColorScheme(ColorTheme.preferredScheme)
                        .presentationDetents([.fraction(0.85)])
                        .presentationDragIndicator(.hidden)
                        .presentationCornerRadius(16)
                }
            }
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissAccessoryButton {
                        focusedField = nil
                    }
                }
            }
        }
        .tint(ColorTheme.accent)
        .preferredColorScheme(ColorTheme.preferredScheme)
    }

    private var detailsCard: some View {
        compactCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Details")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.subtext)

                TextField("Title", text: $title)
                    .focused($focusedField, equals: .title)
                    .foregroundColor(ColorTheme.text)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .onChange(of: title) { _, _ in errorText = "" }
                    .textFieldStyle(.roundedBorder)

                TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                    .focused($focusedField, equals: .description)
                    .lineLimit(2...3)
                    .foregroundColor(ColorTheme.text)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Type")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                    Picker("", selection: $type) {
                        Text("Standard").tag(ListType.regular)
                        Text("Ranked").tag(ListType.ranked)
                        Text("Tiered").tag(ListType.tiered)
                    }
                    .pickerStyle(.segmented)
                    .tint(ColorTheme.accent)
                }

                Toggle("Public", isOn: $isPublic)
                    .tint(ColorTheme.accent)
                    .accessibilityHint(Text("If on, others can view this list"))

                if type == .ranked {
                    rankedOptionsSection
                }

                if type == .tiered {
                    compactTierSection
                }
            }
        }
    }

    private var rankedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ranked Style")
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.subtext)

            Toggle("Show numbers", isOn: $rankedShowNumbers)
                .tint(ColorTheme.accent)

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                    rankedStylePreview
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Top spot")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.subtext)
                    VStack(spacing: 8) {
                        rankedDecorationButton("medal", title: "Medal")
                        rankedDecorationButton("trophy", title: "Trophy")
                        rankedDecorationButton("award", title: "Award")
                    }
                }
                .frame(width: 112)
            }
        }
    }

    private var compactTierSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tiers")
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.subtext)

            ForEach(0..<min(tierLabels.count, tierColors.count), id: \.self) { idx in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorFromHex(safeIndex(tierColors, idx) ?? "") ?? defaultTierColor(for: idx))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Text((safeIndex(tierLabels, idx) ?? idxLabel(idx)).prefix(1))
                                .font(.caption.weight(.bold))
                                .foregroundColor(colorFromHex(safeIndex(tierTextColors, idx) ?? "#FFFFFF") ?? .white)
                        )

                    TextField("Tier", text: Binding(
                        get: { safeIndex(tierLabels, idx) ?? "" },
                        set: { val in setArray(&tierLabels, idx, String(val.prefix(12))) }
                    ))
                    .focused($focusedField, equals: .tierLabel(idx))
                    .foregroundColor(ColorTheme.text)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                    ColorPicker("", selection: Binding(
                        get: { colorFromHex(safeIndex(tierColors, idx) ?? "") ?? defaultTierColor(for: idx) },
                        set: { newColor in setArray(&tierColors, idx, hexString(from: newColor)) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 26)

                    ColorPicker("", selection: Binding(
                        get: { colorFromHex(safeIndex(tierTextColors, idx) ?? "#FFFFFF") ?? .white },
                        set: { newColor in setArray(&tierTextColors, idx, hexString(from: newColor)) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 26)
                }
            }
        }
    }

    private func manageGamesCard(for _: UserList) -> some View {
        compactCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Manage Games")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.subtext)

                Button {
                    showAddGames = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.badge.plus")
                        Text("Add Games")
                        Spacer()
                    }
                    .foregroundColor(ColorTheme.accent)
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func compactCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(ColorTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(ColorTheme.separator, lineWidth: 1)
                )
        )
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
                tierColors: (type == .tiered) ? cleanedColors : nil,
                tierTextColors: (type == .tiered) ? tierTextColors : nil,
                rankedShowNumbers: (type == .ranked) ? rankedShowNumbers : nil,
                rankedTopDecoration: (type == .ranked) ? rankedTopDecoration : nil
            ) {
                isSaving = false
                dismiss()
                if type == .tiered {
                    DispatchQueue.main.async {
                        SecretUnlockService.shared.evaluateTierListSecrets(
                            userId: ownerId,
                            isPublic: isPublic,
                            tierLabels: tierLabels,
                            tierColors: cleanedColors
                        )
                        SecretUnlockService.shared.evaluateTierListSecretsForList(userId: ownerId, listId: e.id)
                        SecretUnlockService.shared.reevaluateListSecrets(userId: ownerId)
                    }
                }
            }
            return
        }

        // CREATE MODE
        ListsService.shared.createList(
            ownerId: ownerId,
            title: titleTrimmed,
            description: descriptionText,
            type: type,
            isPublic: isPublic,
            tierLabels: (type == .tiered) ? tierLabels : nil,
            tierColors: (type == .tiered) ? cleanedColors : nil,
            tierTextColors: (type == .tiered) ? tierTextColors : nil,
            rankedShowNumbers: (type == .ranked) ? rankedShowNumbers : true,
            rankedTopDecoration: (type == .ranked) ? rankedTopDecoration : nil
        ) { result in
            isSaving = false
            switch result {
            case .success(let newList):
                onCreated?(newList)
                dismiss()
                if type == .tiered {
                    DispatchQueue.main.async {
                        SecretUnlockService.shared.evaluateTierListSecrets(
                            userId: ownerId,
                            isPublic: isPublic,
                            tierLabels: tierLabels,
                            tierColors: cleanedColors
                        )
                        SecretUnlockService.shared.evaluateTierListSecretsForList(userId: ownerId, listId: newList.id)
                        SecretUnlockService.shared.reevaluateListSecrets(userId: ownerId)
                    }
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


    private func defaultTierColor(for idx: Int) -> Color {
        let defaults = ["#E74C3C", "#E67E22", "#F1C40F", "#2ECC71", "#3498DB"]
        return colorFromHex(defaults.indices.contains(idx) ? defaults[idx] : defaults[0]) ?? ColorTheme.surface
    }

    private func colorFromHex(_ hex: String) -> Color? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.isEmpty { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let raw = Int(value, radix: 16) else { return nil }
        return Color(
            red: Double((raw >> 16) & 0xFF) / 255.0,
            green: Double((raw >> 8) & 0xFF) / 255.0,
            blue: Double(raw & 0xFF) / 255.0
        )
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
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        #else
        return "#FFFFFF"
        #endif
    }

    /// Human label for default rows (S/A/B/C/D). If user changes label, this is only used as section heading.
    private func idxLabel(_ idx: Int) -> String {
        let defaults = ["S", "A", "B", "C", "D"]
        return safeIndex(tierLabels, idx)?.isEmpty == false ? (safeIndex(tierLabels, idx) ?? defaults[idx]) : defaults[idx]
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
                .foregroundColor(ColorTheme.accent)
        }
        #else
        Image(systemName: rankedDecorationSystemName(choice))
            .resizable()
            .scaledToFit()
            .foregroundColor(ColorTheme.accent)
        #endif
    }

    private func rankedDecorationButton(_ choice: String, title: String) -> some View {
        Button {
            rankedTopDecoration = choice
        } label: {
            VStack(spacing: 8) {
                rankedDecorationIcon(choice)
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(rankedTopDecoration == choice ? ColorTheme.accent.opacity(0.18) : ColorTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(rankedTopDecoration == choice ? ColorTheme.accent : ColorTheme.separator, lineWidth: rankedTopDecoration == choice ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var rankedStylePreview: some View {
        VStack(spacing: 8) {
            rankedPreviewRow(rank: 1, title: "Top Pick", isTop: true)
            rankedPreviewRow(rank: 2, title: "Second Place")
            rankedPreviewRow(rank: 3, title: "Third Place")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(ColorTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(ColorTheme.separator, lineWidth: 1)
                )
        )
    }

    private func rankedPreviewRow(rank: Int, title: String, isTop: Bool = false) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .frame(width: 36, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(ColorTheme.text)

            Spacer()

            if rankedShowNumbers || isTop {
                HStack(spacing: 6) {
                    if isTop {
                        rankedDecorationIcon(rankedTopDecoration)
                            .frame(width: 16, height: 16)
                    }
                    if rankedShowNumbers {
                        Text("\(rank)")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundColor(ColorTheme.subtext)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.035))
        )
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
