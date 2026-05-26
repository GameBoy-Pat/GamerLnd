// CommentsBadge.swift
// Tiny badge that shows live count of comments for a given game_log (log_id).

import SwiftUI
import FirebaseFirestore

struct CommentsBadge: View {
    let logId: String
    var tint: Color = ColorTheme.subtext          // adjust to match your feed UI
    var font: Font = .footnote.monospacedDigit()

    @State private var count: Int = 0
    @State private var listening: Bool = false
    @State private var listener: ListenerRegistration? = nil

    private let db = Firestore.firestore()

    var body: some View {
        Text("\(count)")
            .font(font)
            .foregroundColor(tint)
            .onAppear(perform: start)
            .onDisappear(perform: stop)
    }

    // MARK: - Live listener
    private var listenerKey: String { "comments_\(logId)" }

    private func start() {
        guard !listening else { return }
        listening = true
        listener = db.collection("review_comments")
            .whereField("log_id", isEqualTo: logId)
            .addSnapshotListener(includeMetadataChanges: false) { snap, _ in
                count = snap?.documents.count ?? 0
            }
    }

    private func stop() {
        listener?.remove()
        listener = nil
        listening = false
    }
}
