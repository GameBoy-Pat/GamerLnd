// NotificationsView.swift
// Lists notifications for the current user.
// THIS PASS:
// • Query uses where user_id == me and order by created_at desc (matches rules & index).
// • Beginner-friendly, read-only list.

import SwiftUI
import FirebaseAuth
@preconcurrency import FirebaseFirestore

struct NotificationsView: View {
    private enum ActivityFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case like = "Likes"
        case comment = "Comments"
        case follow = "Following"
        var id: String { rawValue }
    }

    @State private var items: [ActivityItem] = []
    @State private var loading = false
    @State private var selectedLog: GameLog? = nil
    @State private var selectedGameName: String = ""
    @State private var selectedAuthorName: String? = nil
    @State private var selectedProfileTarget: ProfileTarget? = nil
    @State private var creatorNames: [String: String] = [:]
    @State private var gameNameByLogId: [String: String] = [:]
    @State private var selectedFilter: ActivityFilter = .all
    private let db = Firestore.firestore()

    private var filteredItems: [ActivityItem] {
        switch selectedFilter {
        case .all: return items
        case .like: return items.filter { $0.type == "like" }
        case .comment: return items.filter { $0.type == "comment" }
        case .follow: return items.filter { $0.type == "follow" }
        }
    }

    private var activityFilters: some View {
        HStack(spacing: 8) {
            ForEach(ActivityFilter.allCases) { filter in
                let isSelected = selectedFilter == filter
                Button {
                    Haptics.select()
                    selectedFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(isSelected ? ColorTheme.accent : ColorTheme.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? ColorTheme.black : ColorTheme.background.opacity(0.22))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? ColorTheme.accent : ColorTheme.separator, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        ZStack {
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
                        Text("Activity")
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

                    activityFilters
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        ForEach(filteredItems) { n in
                            Button {
                                openNotification(n)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: n.type == "like" ? "hand.thumbsup.fill" : (n.type == "comment" ? "bubble.right.fill" : "person.crop.circle.badge.plus"))
                                        .foregroundColor(ColorTheme.accent)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 4) {
                                        headlineText(for: n)
                                            .font(.subheadline.weight(.semibold))
                                        subtitleLine(for: n)
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
                }
                .padding(.bottom, 90)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .background(ColorTheme.background.ignoresSafeArea())

            if let log = selectedLog {
                notificationsLogOverlay(log: log)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .onAppear(perform: load)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
        .sheet(item: $selectedProfileTarget) { target in
            ProfileView(userId: target.id)
                .preferredColorScheme(ColorTheme.preferredScheme)
        }
    }

    private func notificationsLogOverlay(log: GameLog) -> some View {
        GameLogOverlayHost(
            preview: .init(
                gameLog: log,
                gameName: selectedGameName.isEmpty ? "Game" : selectedGameName,
                authorUsernameOverride: selectedAuthorName,
                focusCommentOnAppear: false
            )
        ) {
            selectedLog = nil
        }
    }

    private func load() {
        guard let uid = Auth.auth().currentUser?.uid else { items = []; return }
        loading = true
        let group = DispatchGroup()
        var notificationItems: [ActivityItem] = []
        var followItems: [ActivityItem] = []

        group.enter()
        db.collection("notifications")
            .whereField("user_id", isEqualTo: uid)
            .order(by: "created_at", descending: true)
            .limit(to: 50)
            .getDocuments { snap, _ in
                notificationItems = (snap?.documents ?? []).compactMap { d -> ActivityItem? in
                    let data = d.data()
                    guard
                        let type = data["type"] as? String,
                        let logId = data["log_id"] as? String,
                        let created = data["created_at"] as? Timestamp,
                        let creator = data["creator_id"] as? String,
                        let userId = data["user_id"] as? String
                    else { return nil }
                    return ActivityItem(id: (data["id"] as? String) ?? d.documentID, type: type, logId: logId, creatorId: creator, userId: userId, createdAt: created)
                }
                group.leave()
            }

        group.enter()
        db.collection("follows")
            .whereField("followed_id", isEqualTo: uid)
            .order(by: "created_at", descending: true)
            .limit(to: 50)
            .getDocuments { snap, _ in
                followItems = (snap?.documents ?? []).compactMap { d -> ActivityItem? in
                    let data = d.data()
                    guard
                        let creator = data["follower_id"] as? String,
                        let userId = data["followed_id"] as? String,
                        let created = data["created_at"] as? Timestamp
                    else { return nil }
                    return ActivityItem(id: (data["id"] as? String) ?? d.documentID, type: "follow", logId: nil, creatorId: creator, userId: userId, createdAt: created)
                }
                group.leave()
            }

        group.notify(queue: .main) {
            loading = false
            items = (notificationItems + followItems).sorted(by: { (lhs: ActivityItem, rhs: ActivityItem) in
                lhs.createdAt.dateValue() > rhs.createdAt.dateValue()
            })
            let creatorIds = Array(Set(items.map { $0.creatorId }))
            fetchCreatorNames(creatorIds)
            Task { await hydrateGameNames(for: items) }
        }
    }

    private func openNotification(_ n: ActivityItem) {
        if n.type == "follow" {
            selectedProfileTarget = ProfileTarget(id: n.creatorId)
            return
        }
        guard let logId = n.logId else { return }
        db.collection("game_logs").document(logId).getDocument { snap, _ in
            guard let data = snap?.data(),
                  let log = Self.parseGameLog(docIdFallback: logId, data: data) else { return }
            selectedLog = log
            selectedGameName = log.gameName ?? "Loading…"
            fetchLogOwnerName(log.userId)
        }
    }

    private func fetchLogOwnerName(_ userId: String) {
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

    private func titleText(for n: ActivityItem) -> String {
        let name = creatorNames[n.creatorId] ?? "Someone"
        switch n.type {
        case "like":
            let game = n.logId.flatMap { gameNameByLogId[$0] }
            let gameText = (game == nil || game == "Unknown Game" || game == "Loading…") ? "game log" : "\(game!) game log"
            return "\(name) liked your \(gameText)"
        case "comment":
            let game = n.logId.flatMap { gameNameByLogId[$0] }
            let gameText = (game == nil || game == "Unknown Game" || game == "Loading…") ? "game log" : "\(game!) game log"
            return "\(name) commented on your \(gameText)"
        case "follow":
            return "\(name) followed you"
        default: return "New activity"
        }
    }

    private func headlineText(for n: ActivityItem) -> Text {
        let name = creatorNames[n.creatorId] ?? "Someone"
        switch n.type {
        case "like":
            if let game = sanitizedGameTitle(for: n) {
                return Text("\(name) liked your ") +
                Text(game).italic().foregroundColor(ColorTheme.accent) +
                Text(" game log")
            }
            return Text("\(name) liked your game log")
        case "comment":
            if let game = sanitizedGameTitle(for: n) {
                return Text("\(name) commented on your ") +
                Text(game).italic().foregroundColor(ColorTheme.accent) +
                Text(" game log")
            }
            return Text("\(name) commented on your game log")
        case "follow":
            return Text("\(name) followed you")
        default:
            return Text("New activity")
        }
    }

    private func subtitleText(for n: ActivityItem) -> String {
        switch n.type {
        case "like":
            let game = n.logId.flatMap { gameNameByLogId[$0] } ?? "Loading…"
            return "\(game) • Like"
        case "comment":
            let game = n.logId.flatMap { gameNameByLogId[$0] } ?? "Loading…"
            return "\(game) • Comment"
        case "follow":
            return "New follower"
        default:
            return "Activity"
        }
    }

    private func subtitleLine(for n: ActivityItem) -> some View {
        switch n.type {
        case "like":
            if let game = sanitizedGameTitle(for: n) {
                return AnyView(
                    (Text(game).italic().foregroundColor(ColorTheme.accent.opacity(0.92)) +
                     Text(" • Like").foregroundColor(ColorTheme.subtext))
                        .font(.caption)
                )
            }
        case "comment":
            if let game = sanitizedGameTitle(for: n) {
                return AnyView(
                    (Text(game).italic().foregroundColor(ColorTheme.accent.opacity(0.92)) +
                     Text(" • Comment").foregroundColor(ColorTheme.subtext))
                        .font(.caption)
                )
            }
        default:
            break
        }
        return AnyView(
            Text(subtitleText(for: n))
                .foregroundColor(ColorTheme.subtext)
                .font(.caption)
        )
    }

    private func sanitizedGameTitle(for n: ActivityItem) -> String? {
        guard let logId = n.logId else { return nil }
        let title = gameNameByLogId[logId]
        guard let title, title != "Unknown Game", title != "Loading…" else { return nil }
        return title
    }

    private func hydrateGameNames(for items: [ActivityItem]) async {
        let missing = items.compactMap { item -> ActivityItem? in
            guard let logId = item.logId, gameNameByLogId[logId] == nil else { return nil }
            return item
        }
        if missing.isEmpty { return }
        var logToGameId: [String: Int] = [:]
        await withTaskGroup(of: (String, Int?).self) { group in
            for n in missing {
                group.addTask {
                    let gid = await fetchGameId(for: n.logId ?? "")
                    return (n.logId ?? "", gid)
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
        let containsSpoilers = data["review_contains_spoilers"] as? Bool ?? false
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
            containsSpoilers: containsSpoilers,
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
                        Text("“\(ContentModeration.displayReviewText(review))”")
                            .font(.caption)
                            .foregroundColor(ColorTheme.text)
                            .lineLimit(2)
                    }

                    if let r = log.rating, r > 0 {
                        HStack(spacing: 6) {
                            RatingHeartBadge(value: r, size: 22)
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
                AverageHeartBadge(value: avg, size: 16)
            } else {
                Image(systemName: "heart")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.accent)
                    .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(ColorTheme.surface))
            }
        }
    }
}

private struct ProfileTarget: Identifiable {
    let id: String
}

struct ActivityItem: Identifiable, Hashable {
    let id: String
    let type: String   // "like" | "comment" | "follow"
    let logId: String?
    let creatorId: String
    let userId: String
    let createdAt: Timestamp
}
