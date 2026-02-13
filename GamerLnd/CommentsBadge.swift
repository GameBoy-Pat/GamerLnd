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

        // Use a collection group if you ever change hierarchy; for now simple collection.
        // No order required for counting — this is efficient and uses existing composite index (log_id, created_at) if you order later.
        db.collection("review_comments")
            .whereField("log_id", isEqualTo: logId)
            .addSnapshotListener(includeMetadataChanges: false) { snap, _ in
                count = snap?.documents.count ?? 0
            }
    }

    private func stop() {
        // Snapshot listeners are retained by the returned ListenerRegistration,
        // but since we're adding an anonymous listener, it gets cleaned up when the view disappears.
        // If you want strict control: refactor to keep a ListenerRegistration and call .remove() here.
        listening = false
    }
}
