// NotificationsView.swift
// Lists notifications for the current user.
// THIS PASS:
// • Query uses where user_id == me and order by created_at desc (matches rules & index).
// • Beginner-friendly, read-only list.

import SwiftUI
import FirebaseAuth
@preconcurrency import FirebaseFirestore

struct NotificationsView: View {
    @State private var items: [AppNotification] = []
    @State private var loading = false
    @State private var selectedLog: GameLog? = nil
    @State private var selectedGameName: String = ""
    @State private var selectedAuthorName: String? = nil
    @State private var creatorNames: [String: String] = [:]
    @State private var gameNameByLogId: [String: String] = [:]
    @State private var recentLogs: [GameLog] = []
    @State private var recentNames: [Int: String] = [:]
    @State private var avgCache: [Int: (avg: Double?, count: Int)] = [:]
    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    AppIconCentered()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 2)

                HStack {
                    Spacer()
                    Text("Notifications")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 2)

                if loading {
                    HStack { Spacer(); ProgressView().tint(ColorTheme.accent); Spacer() }
                        .padding(.vertical, 8)
                }

                VStack(spacing: 0) {
                    ForEach(items) { n in
                        Button {
                            openNotification(n)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: n.type == "like" ? "hand.thumbsup.fill" : "bubble.right.fill")
                                    .foregroundColor(n.type == "like" ? ColorTheme.highlight : ColorTheme.accent)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(titleText(for: n))
                                        .foregroundColor(ColorTheme.text)
                                        .font(.subheadline.weight(.semibold))
                                    Text(subtitleText(for: n))
                                        .foregroundColor(ColorTheme.subtext)
                                        .font(.caption)
                                }
                                Spacer()
                                Text(shortDate(n.createdAt.dateValue()))
                                    .foregroundColor(ColorTheme.subtext)
                                    .font(.caption2)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.3).padding(.leading, 16)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recently Logged")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .padding(.horizontal, 16)

                    if recentLogs.isEmpty {
                        Text("No logs yet.")
                            .font(.footnote)
                            .foregroundColor(ColorTheme.subtext)
                            .padding(.horizontal, 16)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(recentLogs, id: \.id) { log in
                                    let cached = recentNames[log.gameId]
                                    let title = (cached == "Unknown Game" || cached == nil || cached?.hasPrefix("Game #") == true)
                                        ? (log.gameName ?? "Loading…")
                                        : (cached ?? "Loading…")
                                    let avg = avgCache[log.gameId]?.avg
                                    let count = avgCache[log.gameId]?.count ?? 0
                                    NavigationLink(
                                        destination: GameLogDetailView(
                                            gameLog: log,
                                            gameName: title,
                                            authorUsernameOverride: nil,
                                            focusCommentOnAppear: false
                                        )
                                    ) {
                                        RecentLogRowCard(log: log, title: title, avg: avg, count: count)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .frame(height: 160)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.bottom, 90)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .background(ColorTheme.background.ignoresSafeArea())
        .onAppear(perform: load)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
        .sheet(item: $selectedLog) { log in
            GameLogDetailView(
                gameLog: log,
                gameName: selectedGameName.isEmpty ? "Game #\(log.gameId)" : selectedGameName,
                authorUsernameOverride: selectedAuthorName,
                focusCommentOnAppear: false
            )
            .preferredColorScheme(ColorTheme.preferredScheme)
            .presentationCornerRadius(16)
        }
    }

    private func load() {
        guard let uid = Auth.auth().currentUser?.uid else { items = []; return }
        loading = true
        loadRecentLogs(uid: uid)
        db.collection("notifications")
            .whereField("user_id", isEqualTo: uid)
            .order(by: "created_at", descending: true) // ← requires composite index
            .limit(to: 50)
            .getDocuments { snap, _ in
                loading = false
                let nextItems: [AppNotification] = (snap?.documents ?? []).compactMap { d in
                    let data = d.data()
                    guard
                        let id = data["id"] as? String ?? d.documentID as String?,
                        let type = data["type"] as? String,
                        let logId = data["log_id"] as? String,
                        let created = data["created_at"] as? Timestamp,
                        let creator = data["creator_id"] as? String,
                        let userId = data["user_id"] as? String
                    else { return nil }
                    return AppNotification(id: id, type: type, logId: logId, creatorId: creator, userId: userId, createdAt: created)
                }
                items = nextItems
                let creatorIds = Array(Set(nextItems.map { $0.creatorId }))
                fetchCreatorNames(creatorIds)
                Task { await hydrateGameNames(for: nextItems) }
            }
    }

    private func loadRecentLogs(uid: String) {
        db.collection("game_logs")
            .whereField("user_id", isEqualTo: uid)
            .order(by: "play_date", descending: true)
            .limit(to: 20)
            .getDocuments { snap, _ in
                let logs: [GameLog] = (snap?.documents ?? []).compactMap { d in
                    Self.parseGameLog(docIdFallback: d.documentID, data: d.data())
                }
                self.recentLogs = logs
                let gameIds = Array(Set(logs.map { $0.gameId }))
                Task {
                    let names = await GameNameCache.shared.fillAndGet(namesFor: gameIds)
                    await MainActor.run { for (gid, n) in names { self.recentNames[gid] = n } }
                }
                for gid in gameIds {
                    if self.avgCache[gid] == nil {
                        GamerLndScoreService.shared.fetchAverage(gameId: gid) { avg, count in
                            DispatchQueue.main.async {
                                self.avgCache[gid] = (avg, count)
                            }
                        }
                    }
                }
            }
    }

    private func openNotification(_ n: AppNotification) {
        db.collection("game_logs").document(n.logId).getDocument { snap, _ in
            guard let data = snap?.data(),
                  let log = Self.parseGameLog(docIdFallback: n.logId, data: data) else { return }
            selectedLog = log
            selectedGameName = log.gameName ?? "Loading…"
            fetchCreatorName(n.creatorId)
        }
    }

    private func fetchCreatorName(_ userId: String) {
        db.collection("users").document(userId).getDocument { snap, _ in
            let data = snap?.data() ?? [:]
            let name = (data["display_name"] as? String)
                ?? (data["username"] as? String)
                ?? (data["email"] as? String)
            selectedAuthorName = name
        }
    }

    private func fetchCreatorNames(_ userIds: [String]) {
        let missing = userIds.filter { creatorNames[$0] == nil }
        if missing.isEmpty { return }
        let chunks = stride(from: 0, to: missing.count, by: 10).map { Array(missing[$0..<min($0+10, missing.count)]) }
        for chunk in chunks {
            db.collection("users").whereField("id", in: chunk).getDocuments { snap, _ in
                for d in snap?.documents ?? [] {
                    let data = d.data()
                    if let id = data["id"] as? String {
                        let name = (data["display_name"] as? String)
                            ?? (data["username"] as? String)
                            ?? (data["email"] as? String)
                            ?? "User"
                        creatorNames[id] = name
                    }
                }
            }
        }
    }

    private func titleText(for n: AppNotification) -> String {
        let name = creatorNames[n.creatorId] ?? "Someone"
        let game = gameNameByLogId[n.logId]
        let gameText = (game == nil || game == "Unknown Game" || game == "Loading…") ? "game log" : "\(game!) log"
        switch n.type {
        case "like": return "\(name) liked your \(gameText)"
        case "comment": return "\(name) commented on your \(gameText)"
        default: return "New activity"
        }
    }

    private func subtitleText(for n: AppNotification) -> String {
        let game = gameNameByLogId[n.logId] ?? "Loading…"
        let label = (n.type == "comment") ? "Comment" : "Like"
        return "\(game) • \(label)"
    }

    private func hydrateGameNames(for items: [AppNotification]) async {
        let missing = items.filter { gameNameByLogId[$0.logId] == nil }
        if missing.isEmpty { return }
        var logToGameId: [String: Int] = [:]
        await withTaskGroup(of: (String, Int?).self) { group in
            for n in missing {
                group.addTask {
                    let gid = await fetchGameId(for: n.logId)
                    return (n.logId, gid)
                }
            }
            for await (logId, gid) in group {
                if let gid = gid { logToGameId[logId] = gid }
            }
        }
        let ids = Array(Set(logToGameId.values))
        if ids.isEmpty { return }
        let names = await GameNameCache.shared.fillAndGet(namesFor: ids)
        await MainActor.run {
            for (logId, gid) in logToGameId {
                if let name = names[gid], !name.isEmpty {
                    gameNameByLogId[logId] = name
                }
            }
        }
    }

    private func fetchGameId(for logId: String) async -> Int? {
        await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            let db = Firestore.firestore()
            db.collection("game_logs").document(logId).getDocument { snap, _ in
                let data = snap?.data() ?? [:]
                let gid = data["game_id"] as? Int ?? (data["game_id"] as? NSNumber)?.intValue
                cont.resume(returning: gid)
            }
        }
    }

    private static func parseGameLog(docIdFallback: String, data: [String: Any]) -> GameLog? {
        guard
            let userId = data["user_id"] as? String,
            let gameId = data["game_id"] as? Int ?? (data["game_id"] as? NSNumber)?.intValue,
            let statusRaw = data["status"] as? String,
            let status = GameStatus(rawValue: statusRaw),
            let playDate = data["play_date"] as? Timestamp
        else { return nil }

        let rating = data["rating"] as? Double ?? (data["rating"] as? NSNumber)?.doubleValue
        let review = data["review"] as? String
        let isLiked = data["is_liked"] as? Bool ?? false

        var cover: Game.Cover? = nil
        if let coverDict = data["cover"] as? [String: Any],
           let imageId = coverDict["image_id"] as? String {
            let id = coverDict["id"] as? Int ?? (coverDict["id"] as? NSNumber)?.intValue
            cover = Game.Cover(id: id, imageId: imageId)
        }

        let gameName = (data["game_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GameLog(
            id: (data["id"] as? String) ?? docIdFallback,
            userId: userId,
            gameId: gameId,
            gameName: gameName?.isEmpty == true ? nil : gameName,
            status: status,
            playDate: playDate,
            rating: rating,
            review: review,
            isLiked: isLiked,
            cover: cover
        )
    }

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - Recent Log Row Card (local copy for notifications)

private struct RecentLogRowCard: View {
    let log: GameLog
    let title: String
    let avg: Double?
    let count: Int

    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 140
    private let coverCorner: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColorTheme.separator, lineWidth: 1))

            HStack(spacing: 10) {
                if let imgId = log.cover?.imageId {
                    GameCoverImage(id: imgId, preset: .medium, cornerRadius: coverCorner)
                        .frame(width: 84, height: 104)
                } else {
                    RoundedRectangle(cornerRadius: coverCorner)
                        .fill(ColorTheme.separator.opacity(0.25))
                        .frame(width: 84, height: 104)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.text)
                        .lineLimit(2)

                    if let review = log.review, !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("“\(review)”")
                            .font(.caption)
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(2)
                    }

                    if let r = log.rating, r > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(ColorTheme.highlight)
                                .font(.caption)
                            Text(String(format: "%.1f", r))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundColor(ColorTheme.highlight)
                            Text("your rating")
                                .font(.caption2)
                                .foregroundColor(ColorTheme.subtext)
                        }
                    }

                    Spacer(minLength: 2)

                    CompactGamerLndBadge(avg: avg, count: count)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

// MARK: - Compact GamerLnd Badge (local copy)

private struct CompactGamerLndBadge: View {
    let avg: Double?
    let count: Int
    var body: some View {
        Group {
            if let avg = avg, count > 0 {
                HStack(spacing: 6) {
                    Image("icon")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    Image(systemName: "heart.fill").foregroundColor(ColorTheme.highlight)
                    Text(String(format: "%.1f", avg))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.highlight)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ColorTheme.separator, lineWidth: 1))
            } else {
                HStack(spacing: 6) {
                    Image("icon")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    Text("Be the first to rate!")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.accent)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ColorTheme.separator, lineWidth: 1))
            }
        }
    }
}

struct AppNotification: Identifiable, Hashable {
    let id: String
    let type: String   // "like" | "comment"
    let logId: String
    let creatorId: String
    let userId: String
    let createdAt: Timestamp

    // title/subtitle provided by view (needs username cache)
}
