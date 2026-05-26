// DataModels.swift
// Central app models used across views/services.
// THIS PASS:
// • Canonical UserLite lives here (remove any duplicate definitions in other files).
// • Keeps Game, GameLog, ReviewComment, UserProfile, UserProfileBrief as before.

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Game (IGDB)

struct Game: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    var slug: String? = nil
    var cover: Cover?
    var firstReleaseDate: Int?
    var genres: [Genre]?
    var platforms: [Platform]?
    var rating: Double?
    var ratingCount: Int?
    var aggregatedRating: Double? = nil
    var aggregatedRatingCount: Int? = nil
    var totalRating: Double? = nil
    var totalRatingCount: Int?
    var popularity: Double? = nil
    var hypes: Int? = nil
    var category: Int? = nil
    var screenshots: [Screenshot]?
    var involvedCompanies: [InvolvedCompany]? = nil
    var franchises: [Franchise]? = nil
    var collections: [CollectionGroup]? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, slug, cover, genres, platforms, rating, popularity, hypes, category, screenshots, franchises, collections
        case aggregatedRating = "aggregated_rating"
        case aggregatedRatingCount = "aggregated_rating_count"
        case totalRating = "total_rating"
        case firstReleaseDate = "first_release_date"
        case ratingCount = "rating_count"
        case totalRatingCount = "total_rating_count"
        case involvedCompanies = "involved_companies"
    }

    struct Cover: Codable, Hashable {
        var id: Int?
        var imageId: String
        enum CodingKeys: String, CodingKey { case id; case imageId = "image_id" }
    }

    struct Genre: Codable, Hashable { let id: Int; let name: String }
    struct Platform: Codable, Hashable { let id: Int; let name: String }
    struct Franchise: Codable, Hashable { let id: Int; let name: String }
    struct CollectionGroup: Codable, Hashable { let id: Int; let name: String }
    struct InvolvedCompany: Codable, Hashable {
        var publisher: Bool?
        var developer: Bool?
        var company: Company?
    }
    struct Company: Codable, Hashable {
        var id: Int?
        var name: String
    }
    struct Screenshot: Codable, Hashable {
        var id: Int?
        var imageId: String
        enum CodingKeys: String, CodingKey { case id; case imageId = "image_id" }
    }

    var computedReleaseYear: Int? {
        guard let unix = firstReleaseDate else { return nil }
        let d = Date(timeIntervalSince1970: TimeInterval(unix))
        return Calendar.current.dateComponents([.year], from: d).year
    }

    var prioritizedPlatformNames: [String] {
        let names = (platforms ?? []).map(\.name)
        guard !names.isEmpty else { return [] }

        func priority(for name: String) -> Int {
            let lowered = name.lowercased()
            if lowered.contains("nintendo switch 2") { return 0 }
            if lowered == "nintendo switch" || lowered.contains("nintendo switch") { return 1 }
            if lowered == "playstation 5" || lowered.contains("ps5") { return 2 }
            if lowered.contains("xbox series") { return 3 }
            return 10
        }

        return names.sorted { lhs, rhs in
            let lp = priority(for: lhs)
            let rp = priority(for: rhs)
            if lp == rp {
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            return lp < rp
        }
    }

    func prioritizedPlatformNames(prefix limit: Int) -> [String] {
        Array(prioritizedPlatformNames.prefix(max(0, limit)))
    }

    var prioritizedPrimaryPlatformName: String? {
        prioritizedPlatformNames.first
    }
}

// MARK: - Logging

enum GameStatus: String, Codable, CaseIterable {
    case inProgress = "in_progress"
    case completed = "completed"
    case notPlayed = "not_played"
}

struct GameLog: Identifiable, Hashable {
    let id: String
    let userId: String
    let gameId: Int
    let gameName: String?
    let status: GameStatus
    let playDate: Timestamp
    let rating: Double?
    let review: String?
    let containsSpoilers: Bool
    let isLiked: Bool
    let cover: Game.Cover?
}

// MARK: - Comments

struct ReviewComment: Identifiable, Hashable {
    let id: String
    let logId: String
    let userId: String
    let text: String
    let createdAt: Timestamp
    let authorName: String?
    let authorAvatarUrl: String?
}

// MARK: - Users

/// Firestore `/users/{uid}` profile document
struct UserProfile: Identifiable, Hashable {
    let id: String                    // == Firestore doc id (uid)
    var username: String              // display name (not unique)
    var handle: String                // unique, lowercase (no leading "@")
    var bio: String                   // up to 160 chars
    var avatarURL: String?            // optional
    var createdAt: Timestamp?
    var updatedAt: Timestamp?

    init(id: String,
         username: String,
         handle: String,
         bio: String = "",
         avatarURL: String? = nil,
         createdAt: Timestamp? = nil,
         updatedAt: Timestamp? = nil) {
        self.id = id
        self.username = username
        self.handle = handle
        self.bio = bio
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init?(docId: String, data: [String: Any]) {
        let uname = (data["username"] as? String) ?? ""
        let h = (data["handle"] as? String) ?? ""
        guard !uname.isEmpty, !h.isEmpty else { return nil }
        self.id = docId
        self.username = uname
        self.handle = h
        self.bio = (data["bio"] as? String) ?? ""
        self.avatarURL = (data["avatar_url"] as? String)
        self.createdAt = (data["created_at"] as? Timestamp)
        self.updatedAt = (data["updated_at"] as? Timestamp)
    }

    static func searchPrefixes(username: String, handle: String) -> [String] {
        let a = String(username.lowercased().prefix(1))
        let b = String(handle.lowercased().prefix(1))
        return Array(Set([a, b])).filter { !$0.isEmpty }
    }
}

/// Brief user used in lists/search
struct UserProfileBrief: Identifiable, Hashable {
    let id: String
    let username: String
    let handle: String?
    let displayName: String?
    let avatarUrl: String?
}

/// Canonical lightweight user for search screens
struct UserLite: Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let isTrustedGamer: Bool

    init(id: String, username: String, displayName: String?, avatarUrl: String?, isTrustedGamer: Bool = false) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isTrustedGamer = isTrustedGamer
    }
}

// MARK: - Rewards

final class RewardService {
    static let shared = RewardService()
    private let db = Firestore.firestore()
    private init() {}
    private static let dailyNormalXPCap = 150
    private static let minimumReviewLength = 50
    static let activeSessionId = UUID().uuidString
    private static let levelThresholds: [Int] = [
        0, 100, 250, 450, 700, 1000, 1350, 1750, 2200, 3000,
        3700, 4500, 5400, 6400, 7500, 8700, 10000, 11400, 12900, 14500
    ]

    enum Theme: String, CaseIterable {
        case xp
        case cartridges
        case discs
        case bits

        var displayUnit: String {
            switch self {
            case .xp: return "XP"
            case .cartridges: return "Cartridges"
            case .discs: return "Discs"
            case .bits: return "Bits"
            }
        }

        var settingsTitle: String {
            switch self {
            case .xp: return "XP"
            case .cartridges: return "Cartridges"
            case .discs: return "Discs"
            case .bits: return "Bits"
            }
        }
    }

    struct LevelInfo {
        let level: Int
        let totalXP: Int
        let currentLevelStartXP: Int
        let nextLevelXP: Int
        let xpToNext: Int
        let progress: Double
    }

    struct RewardStateSnapshot {
        let totalXP: Int
        let level: Int
        let normalXPEarnedToday: Int
        let normalXPDayKey: String
        let firstActionBonusDayKey: String?
    }

    enum XPKind: String {
        case normal = "NORMAL_XP"
        case bonus = "BONUS_XP"
    }

    private struct XPGrant {
        let transactionId: String
        let amount: Int
        let kind: XPKind
        let reason: String
        let sourceType: String
        let sourceId: String
        let gameId: Int?
        let metadata: [String: Any]
    }

    struct GamificationEvent {
        enum Kind {
            case rateGame
            case writeReview
            case saveGame
            case addToList
            case createList
            case likeLog
            case commentLog
            case followUser
            case searchGame
            case viewGame
            case flagGame
        }

        let userId: String
        let kind: Kind
        let gameId: Int?
        let releaseYear: Int?
        let reviewLength: Int?
        let ratingValue: Double?
        let searchQuery: String?
        let sessionId: String?
        let occurredAt: Date
    }

    static func levelTitle(for level: Int) -> String {
        switch level {
        case 1...4: return "Rookie"
        case 5...9: return "Arcade Regular"
        case 10...19: return "Backlog Breaker"
        case 20...34: return "Quest Runner"
        case 35...49: return "Legend in Training"
        case 50...74: return "Guild Veteran"
        case 75...99: return "Hall of Gamers"
        default: return "Mythic Gamer"
        }
    }

    static func levelInfo(for xp: Int) -> LevelInfo {
        let clamped = max(0, xp)
        var level = 1
        while clamped >= xpRequiredForLevel(level + 1) {
            level += 1
            if level >= 200 { break }
        }
        let start = xpRequiredForLevel(level)
        let next = xpRequiredForLevel(level + 1)
        let toNext = max(0, next - clamped)
        let span = max(1, next - start)
        let pct = min(1.0, max(0.0, Double(clamped - start) / Double(span)))
        return LevelInfo(
            level: level,
            totalXP: clamped,
            currentLevelStartXP: start,
            nextLevelXP: next,
            xpToNext: toNext,
            progress: pct
        )
    }

    private static func xpRequiredForLevel(_ level: Int) -> Int {
        if level <= 1 { return 0 }
        if level - 1 < levelThresholds.count {
            return levelThresholds[level - 1]
        }
        var total = levelThresholds.last ?? 0
        var increment = 1700
        if levelThresholds.count >= 2 {
            increment = (levelThresholds[levelThresholds.count - 1] - levelThresholds[levelThresholds.count - 2]) + 150
        }
        if levelThresholds.count + 1 >= level { return total }
        for _ in (levelThresholds.count + 1)...level {
            total += increment
            increment += 150
        }
        return total
    }

    func currentTheme(for userId: String?) -> Theme {
        .xp
    }

    func setTheme(_ theme: Theme, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else { completion?(nil); return }
        UserDefaults.standard.set(Theme.xp.rawValue, forKey: "reward.theme.\(uid)")
        db.collection("users").document(uid).setData([
            "reward_theme": Theme.xp.rawValue
        ], merge: true) { err in
            completion?(err)
        }
    }

    func syncThemeFromServer(for userId: String, completion: ((Theme) -> Void)? = nil) {
        UserDefaults.standard.set(Theme.xp.rawValue, forKey: "reward.theme.\(userId)")
        completion?(.xp)
    }

    func awardForLogSave(
        gameId: Int,
        hadLogBefore: Bool,
        hadRatingBefore: Bool,
        hadReviewBefore: Bool,
        rating: Double,
        review: String,
        releaseYear: Int? = nil,
        completion: ((Int) -> Void)? = nil
    ) {
        let trimmedReview = review.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRatingNow = rating > 0
        let hasReviewNow = trimmedReview.count >= Self.minimumReviewLength
        var grants: [XPGrant] = []
        guard let uid = Auth.auth().currentUser?.uid else { completion?(0); return }

        if hasRatingNow && !hadRatingBefore {
            grants.append(
                XPGrant(
                    transactionId: makeTransactionId(["rate", String(gameId)]),
                    amount: 10,
                    kind: .normal,
                    reason: "base_rating",
                    sourceType: "game_log",
                    sourceId: "game_\(gameId)",
                    gameId: gameId,
                    metadata: ["had_log_before": hadLogBefore, "rating": rating]
                )
            )
        }

        if hasReviewNow && !hadReviewBefore {
            grants.append(
                XPGrant(
                    transactionId: makeTransactionId(["review", String(gameId)]),
                    amount: 25,
                    kind: .normal,
                    reason: "base_review",
                    sourceType: "game_log",
                    sourceId: "game_\(gameId)",
                    gameId: gameId,
                    metadata: ["review_length": trimmedReview.count]
                )
            )
        }

        applyGrants(grants) { awarded in
            if hasRatingNow && !hadRatingBefore {
                let event = GamificationEvent(
                    userId: uid,
                    kind: .rateGame,
                    gameId: gameId,
                    releaseYear: releaseYear,
                    reviewLength: nil,
                    ratingValue: rating,
                    searchQuery: nil,
                    sessionId: Self.activeSessionId,
                    occurredAt: Date()
                )
                ObjectiveService.shared.handleEvent(event)
                AchievementService.shared.handleEvent(event)
            }
            if hasReviewNow && !hadReviewBefore {
                let event = GamificationEvent(
                    userId: uid,
                    kind: .writeReview,
                    gameId: gameId,
                    releaseYear: releaseYear,
                    reviewLength: trimmedReview.count,
                    ratingValue: nil,
                    searchQuery: nil,
                    sessionId: Self.activeSessionId,
                    occurredAt: Date()
                )
                ObjectiveService.shared.handleEvent(event)
                AchievementService.shared.handleEvent(event)
            }
            completion?(awarded)
        }
    }

    func awardForListAdd(listId: String, items: [UserListItem], completion: ((Int) -> Void)? = nil) {
        let grants = items.map {
            XPGrant(
                transactionId: makeTransactionId(["list_add", listId, $0.id]),
                amount: 5,
                kind: .normal,
                reason: "list_add",
                sourceType: "list_item",
                sourceId: $0.id,
                gameId: $0.gameId,
                metadata: ["list_id": listId]
            )
        }
        guard let uid = Auth.auth().currentUser?.uid else { completion?(0); return }
        applyGrants(grants) { awarded in
            items.forEach { item in
                let event = GamificationEvent(
                    userId: uid,
                    kind: .addToList,
                    gameId: item.gameId,
                    releaseYear: nil,
                    reviewLength: nil,
                    ratingValue: nil,
                    searchQuery: nil,
                    sessionId: Self.activeSessionId,
                    occurredAt: Date()
                )
                ObjectiveService.shared.handleEvent(event)
                AchievementService.shared.handleEvent(event)
            }
            completion?(awarded)
        }
    }

    func awardForListCreate(listId: String, completion: ((Int) -> Void)? = nil) {
        let grant = XPGrant(
            transactionId: makeTransactionId(["list_create", listId]),
            amount: 5,
            kind: .normal,
            reason: "list_create",
            sourceType: "list",
            sourceId: listId,
            gameId: nil,
            metadata: [:]
        )
        guard let uid = Auth.auth().currentUser?.uid else { completion?(0); return }
        applyGrants([grant]) { awarded in
            let event = GamificationEvent(
                userId: uid,
                kind: .createList,
                gameId: nil,
                releaseYear: nil,
                reviewLength: nil,
                ratingValue: nil,
                searchQuery: nil,
                sessionId: Self.activeSessionId,
                occurredAt: Date()
            )
            ObjectiveService.shared.handleEvent(event)
            AchievementService.shared.handleEvent(event)
            completion?(awarded)
        }
    }

    func awardForSaveGame(gameId: Int, completion: ((Int) -> Void)? = nil) {
        let grant = XPGrant(
            transactionId: makeTransactionId(["save_game", String(gameId)]),
            amount: 5,
            kind: .normal,
            reason: "save_game",
            sourceType: "saved_game",
            sourceId: "game_\(gameId)",
            gameId: gameId,
            metadata: [:]
        )
        guard let uid = Auth.auth().currentUser?.uid else { completion?(0); return }
        applyGrants([grant]) { awarded in
            let event = GamificationEvent(
                userId: uid,
                kind: .saveGame,
                gameId: gameId,
                releaseYear: nil,
                reviewLength: nil,
                ratingValue: nil,
                searchQuery: nil,
                sessionId: Self.activeSessionId,
                occurredAt: Date()
            )
            ObjectiveService.shared.handleEvent(event)
            AchievementService.shared.handleEvent(event)
            completion?(awarded)
        }
    }

    func recordGamificationEvent(_ event: GamificationEvent) {
        ObjectiveService.shared.handleEvent(event)
        AchievementService.shared.handleEvent(event)
    }

    func recordSearch(query: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordGamificationEvent(
            GamificationEvent(
                userId: uid,
                kind: .searchGame,
                gameId: nil,
                releaseYear: nil,
                reviewLength: nil,
                ratingValue: nil,
                searchQuery: trimmed,
                sessionId: Self.activeSessionId,
                occurredAt: Date()
            )
        )
    }

    func recordViewedGame(gameId: Int, releaseYear: Int? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        recordGamificationEvent(
            GamificationEvent(
                userId: uid,
                kind: .viewGame,
                gameId: gameId,
                releaseYear: releaseYear,
                reviewLength: nil,
                ratingValue: nil,
                searchQuery: nil,
                sessionId: Self.activeSessionId,
                occurredAt: Date()
            )
        )
    }

    func recordFlaggedGame(gameId: Int?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        recordGamificationEvent(
            GamificationEvent(
                userId: uid,
                kind: .flagGame,
                gameId: gameId,
                releaseYear: nil,
                reviewLength: nil,
                ratingValue: nil,
                searchQuery: nil,
                sessionId: Self.activeSessionId,
                occurredAt: Date()
            )
        )
    }

    private func applyGrants(_ baseGrants: [XPGrant], completion: ((Int) -> Void)? = nil) {
        guard !baseGrants.isEmpty else { completion?(0); return }
        guard let uid = Auth.auth().currentUser?.uid else { completion?(0); return }
        let dayKey = Self.dayKey(for: Date())
        var grants = baseGrants
        if baseGrants.contains(where: { $0.kind == .normal }) {
            grants.insert(
                XPGrant(
                    transactionId: makeTransactionId(["daily_bonus", dayKey]),
                    amount: 10,
                    kind: .normal,
                    reason: "first_action_bonus",
                    sourceType: "daily_login",
                    sourceId: dayKey,
                    gameId: nil,
                    metadata: ["day_key": dayKey]
                ),
                at: 0
            )
        }

        let ref = db.collection("user_stats").document(uid)
        db.runTransaction({ transaction, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            let data = snap.data() ?? [:]
            let current = (data["reward_xp_total"] as? Int)
                ?? (data["reward_xp_total"] as? NSNumber)?.intValue
                ?? 0
            var existingEvents = data["reward_events"] as? [[String: Any]] ?? []
            let rewardState = data["reward_state"] as? [String: Any] ?? [:]
            let resetVersion = (data["reward_reset_version"] as? Int)
                ?? (data["reward_reset_version"] as? NSNumber)?.intValue
                ?? 0
            var processedTransactions = rewardState["processed_transactions"] as? [String] ?? []
            if processedTransactions.count > 250 {
                processedTransactions = Array(processedTransactions.suffix(250))
            }
            let storedDayKey = rewardState["normal_xp_day_key"] as? String
            var normalXPEarnedToday: Int
            if storedDayKey == dayKey {
                normalXPEarnedToday = (rewardState["normal_xp_earned_today"] as? Int)
                    ?? (rewardState["normal_xp_earned_today"] as? NSNumber)?.intValue
                    ?? 0
            } else {
                normalXPEarnedToday = 0
            }
            let firstActionBonusDayKey = rewardState["first_action_bonus_day_key"] as? String

            var awardedTotal = 0
            for grant in grants {
                if grant.reason == "first_action_bonus", firstActionBonusDayKey == dayKey {
                    continue
                }
                let effectiveTransactionId = "r\(resetVersion)_\(grant.transactionId)"
                if processedTransactions.contains(effectiveTransactionId) { continue }

                var awardedXP = grant.amount
                if grant.kind == .normal {
                    let remaining = max(0, Self.dailyNormalXPCap - normalXPEarnedToday)
                    awardedXP = min(awardedXP, remaining)
                }
                processedTransactions.append(effectiveTransactionId)

                guard awardedXP > 0 else { continue }
                awardedTotal += awardedXP
                if grant.kind == .normal {
                    normalXPEarnedToday += awardedXP
                }
                existingEvents.append([
                    "id": effectiveTransactionId,
                    "type": grant.reason,
                    "delta": awardedXP,
                    "at": Timestamp(date: Date())
                ])
            }

            if existingEvents.count > 80 {
                existingEvents = Array(existingEvents.suffix(80))
            }

            let newTotal = max(0, current + awardedTotal)
            let level = RewardService.levelInfo(for: newTotal).level
            var rewardStatePatch: [String: Any] = [
                "total_xp": newTotal,
                "level": level,
                "normal_xp_earned_today": normalXPEarnedToday,
                "normal_xp_day_key": dayKey,
                "processed_transactions": Array(processedTransactions.suffix(250))
            ]
            if firstActionBonusDayKey == dayKey || grants.contains(where: { $0.reason == "first_action_bonus" }) {
                rewardStatePatch["first_action_bonus_day_key"] = dayKey
            } else if let firstActionBonusDayKey {
                rewardStatePatch["first_action_bonus_day_key"] = firstActionBonusDayKey
            }
            transaction.setData([
                "reward_xp_total": newTotal,
                "reward_level": level,
                "reward_events": existingEvents,
                "reward_state": rewardStatePatch,
                "reward_updated_at": FieldValue.serverTimestamp()
            ], forDocument: ref, merge: true)
            return ["total": newTotal, "delta": awardedTotal] as NSDictionary
        }) { result, _ in
            let payload = result as? NSDictionary
            let newTotal = payload?["total"] as? Int ?? 0
            let awardedDelta = payload?["delta"] as? Int ?? 0
            guard awardedDelta > 0 else {
                completion?(0)
                return
            }
            let theme = self.currentTheme(for: uid)
            let reasonSummary = baseGrants.map(\.reason).joined(separator: ",")
            NotificationCenter.default.post(
                name: .rewardXPAwarded,
                object: nil,
                userInfo: [
                    "delta": awardedDelta,
                    "total": newTotal,
                    "theme": theme.rawValue,
                    "reason": reasonSummary
                ]
            )
            completion?(awardedDelta)
        }
    }

    private func applyDirectClaimBonusXP(
        userId: String,
        amount: Int,
        reason: String,
        sourceType: String,
        sourceId: String,
        completion: ((Int) -> Void)? = nil
    ) {
        guard amount > 0 else { completion?(0); return }
        guard let uid = Auth.auth().currentUser?.uid, uid == userId else {
            completion?(0)
            return
        }

        let ref = db.collection("user_stats").document(uid)
        db.runTransaction({ transaction, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            let data = snap.data() ?? [:]
            let current = (data["reward_xp_total"] as? Int)
                ?? (data["reward_xp_total"] as? NSNumber)?.intValue
                ?? 0
            var existingEvents = data["reward_events"] as? [[String: Any]] ?? []
            if existingEvents.count > 80 {
                existingEvents = Array(existingEvents.suffix(80))
            }

            let newTotal = max(0, current + amount)
            let level = RewardService.levelInfo(for: newTotal).level
            let rewardState = data["reward_state"] as? [String: Any] ?? [:]
            var rewardStatePatch = rewardState
            rewardStatePatch["total_xp"] = newTotal
            rewardStatePatch["level"] = level

            existingEvents.append([
                "id": UUID().uuidString,
                "type": reason,
                "delta": amount,
                "at": Timestamp(date: Date())
            ])
            if existingEvents.count > 80 {
                existingEvents = Array(existingEvents.suffix(80))
            }

            transaction.setData([
                "reward_xp_total": newTotal,
                "reward_level": level,
                "reward_events": existingEvents,
                "reward_state": rewardStatePatch,
                "reward_updated_at": FieldValue.serverTimestamp(),
                "reward_last_source_type": sourceType,
                "reward_last_source_id": sourceId
            ], forDocument: ref, merge: true)

            return ["total": newTotal, "delta": amount] as NSDictionary
        }) { result, _ in
            let payload = result as? NSDictionary
            let newTotal = payload?["total"] as? Int ?? 0
            let awardedDelta = payload?["delta"] as? Int ?? 0
            guard awardedDelta > 0 else {
                completion?(0)
                return
            }
            let theme = self.currentTheme(for: uid)
            NotificationCenter.default.post(
                name: .rewardXPAwarded,
                object: nil,
                userInfo: [
                    "delta": awardedDelta,
                    "total": newTotal,
                    "theme": theme.rawValue,
                    "reason": reason
                ]
            )
            completion?(awardedDelta)
        }
    }

    private func makeTransactionId(_ parts: [String]) -> String {
        let joined = parts.joined(separator: "_")
        return joined.replacingOccurrences(of: "/", with: "_")
    }

    func grantObjectiveXP(
        userId: String,
        amount: Int,
        reason: String,
        sourceId: String,
        completion: ((Int) -> Void)? = nil
    ) {
        applyDirectClaimBonusXP(
            userId: userId,
            amount: amount,
            reason: reason,
            sourceType: "objective",
            sourceId: sourceId,
            completion: completion
        )
    }

    fileprivate func grantAchievementXP(
        userId: String,
        amount: Int,
        reason: String,
        sourceId: String,
        completion: ((Int) -> Void)? = nil
    ) {
        applyDirectClaimBonusXP(
            userId: userId,
            amount: amount,
            reason: reason,
            sourceType: "achievement",
            sourceId: sourceId,
            completion: completion
        )
    }

    fileprivate func grantSecretUnlockXP(
        userId: String,
        amount: Int,
        reason: String,
        sourceId: String,
        completion: ((Int) -> Void)? = nil
    ) {
        applyDirectClaimBonusXP(
            userId: userId,
            amount: amount,
            reason: reason,
            sourceType: "secret_unlock",
            sourceId: sourceId,
            completion: completion
        )
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

extension Notification.Name {
    static let rewardXPAwarded = Notification.Name("gamerlnd.rewardXPAwarded")
    static let gamificationUpdated = Notification.Name("gamerlnd.gamificationUpdated")
    static let questCompleted = Notification.Name("gamerlnd.questCompleted")
    static let secretQuestFound = Notification.Name("gamerlnd.secretQuestFound")
    static let challengesUpdated = Notification.Name("gamerlnd.challengesUpdated")
    static let logCommentsUpdated = Notification.Name("gamerlnd.logCommentsUpdated")
    static let gameLogChanged = Notification.Name("gamerlnd.gameLogChanged")
    static let openRatingsOverlayRequested = Notification.Name("gamerlnd.openRatingsOverlayRequested")
    static let nestedOverlayVisibilityChanged = Notification.Name("gamerlnd.nestedOverlayVisibilityChanged")
    static let referencesUpdated = Notification.Name("gamerlnd.referencesUpdated")
}

func glReferenceCacheKey(for userId: String) -> String {
    "gamerlnd.logReferences.\(userId)"
}

func glSerializeReferencePayloadsForCache(_ payloads: [[String: Any]]) -> [[String: Any]] {
    payloads.map { payload in
        var cached = payload
        if let timestamp = payload["added_at"] as? Timestamp {
            cached["added_at_seconds"] = timestamp.dateValue().timeIntervalSince1970
            cached.removeValue(forKey: "added_at")
        }
        return cached
    }
}

func glDeserializeReferencePayloadsFromCache(_ payloads: [[String: Any]]) -> [[String: Any]] {
    payloads.map { payload in
        var restored = payload
        if let seconds = payload["added_at_seconds"] as? Double {
            restored["added_at"] = Timestamp(date: Date(timeIntervalSince1970: seconds))
            restored.removeValue(forKey: "added_at_seconds")
        } else if let secondsInt = payload["added_at_seconds"] as? Int {
            restored["added_at"] = Timestamp(date: Date(timeIntervalSince1970: TimeInterval(secondsInt)))
            restored.removeValue(forKey: "added_at_seconds")
        }
        return restored
    }
}

// MARK: - Gamification Catalog Models

enum AchievementTileState: String, Codable {
    case hidden
    case hinted
    case completed
}

enum RewardRarity: String, Codable, CaseIterable {
    case common
    case rare
    case epic
    case legendary
}

enum ObjectiveWindow: String, Codable {
    case daily
    case weekly
}

struct AchievementDefinition: Identifiable, Hashable {
    let id: String
    let code: String
    let title: String
    let detail: String
    let hintTitle: String
    let hintText: String
    let category: String
    let xpReward: Int
    let rarity: RewardRarity
    let unlockableRewardIds: [String]
    let isSecret: Bool
    let isRepeatable: Bool
    let tileRow: Int?
    let tileColumn: Int?
    let revealsNeighbors: Bool
    let progressMetric: String
    let progressTarget: Int
    let active: Bool

    init(id: String, data: [String: Any]) {
        self.id = id
        self.code = (data["code"] as? String) ?? id
        self.title = (data["title"] as? String) ?? "Quest"
        self.detail = (data["description"] as? String) ?? ""
        self.hintTitle = (data["hint_title"] as? String) ?? "?????"
        self.hintText = (data["hint_text"] as? String) ?? self.detail
        self.category = (data["category"] as? String) ?? "general"
        self.xpReward = (data["xp_reward"] as? Int) ?? (data["xp_reward"] as? NSNumber)?.intValue ?? 0
        self.rarity = RewardRarity(rawValue: (data["rarity"] as? String) ?? "") ?? .common
        self.unlockableRewardIds = data["unlockable_reward_ids"] as? [String] ?? []
        self.isSecret = data["is_secret"] as? Bool ?? false
        self.isRepeatable = data["is_repeatable"] as? Bool ?? false
        if let tile = data["tile_position"] as? [String: Any] {
            self.tileRow = (tile["row"] as? Int) ?? (tile["row"] as? NSNumber)?.intValue
            self.tileColumn = (tile["col"] as? Int) ?? (tile["col"] as? NSNumber)?.intValue
        } else {
            self.tileRow = nil
            self.tileColumn = nil
        }
        self.revealsNeighbors = data["reveals_neighbors"] as? Bool ?? false
        let condition = data["unlock_condition"] as? [String: Any] ?? [:]
        self.progressMetric = (condition["metric"] as? String) ?? "unknown"
        self.progressTarget = (condition["threshold"] as? Int) ?? (condition["threshold"] as? NSNumber)?.intValue ?? 1
        self.active = data["active"] as? Bool ?? true
    }
}

struct UserAchievementState: Identifiable, Hashable {
    let id: String
    let userId: String
    let achievementId: String
    let state: AchievementTileState
    let progressCurrent: Int
    let progressTarget: Int
    let revealedAt: Timestamp?
    let completedAt: Timestamp?
    let claimed: Bool
    let xpGranted: Int
    let unlockablesGranted: [String]

    init(id: String, data: [String: Any]) {
        self.id = id
        self.userId = (data["user_id"] as? String) ?? ""
        self.achievementId = (data["achievement_id"] as? String) ?? ""
        let storedState = (data["state"] as? String) ?? ""
        switch storedState {
        case "completed":
            self.state = .completed
        case "visible", "hinted":
            self.state = .hinted
        default:
            self.state = .hidden
        }
        self.progressCurrent = (data["progress_current"] as? Int) ?? (data["progress_current"] as? NSNumber)?.intValue ?? 0
        self.progressTarget = (data["progress_target"] as? Int) ?? (data["progress_target"] as? NSNumber)?.intValue ?? 0
        self.revealedAt = data["revealed_at"] as? Timestamp
        self.completedAt = data["completed_at"] as? Timestamp
        self.xpGranted = (data["xp_granted"] as? Int) ?? (data["xp_granted"] as? NSNumber)?.intValue ?? 0
        self.claimed = (data["claimed"] as? Bool) ?? (self.xpGranted > 0)
        self.unlockablesGranted = data["unlockables_granted"] as? [String] ?? []
    }
}

struct ObjectiveTemplate: Identifiable, Hashable {
    let id: String
    let code: String
    let window: ObjectiveWindow
    let title: String
    let detail: String
    let objectiveKind: String
    let targetValue: Int
    let xpReward: Int
    let constraints: [String: AnyHashable]
    let difficultyWeight: Int
    let active: Bool

    init(id: String, data: [String: Any]) {
        self.id = id
        self.code = (data["code"] as? String) ?? id
        self.window = ObjectiveWindow(rawValue: (data["type"] as? String) ?? "") ?? .daily
        self.title = (data["title"] as? String) ?? "Objective"
        self.detail = (data["description"] as? String) ?? ""
        self.objectiveKind = (data["objective_kind"] as? String) ?? "general"
        self.targetValue = (data["target_value"] as? Int) ?? (data["target_value"] as? NSNumber)?.intValue ?? 1
        self.xpReward = (data["xp_reward"] as? Int) ?? (data["xp_reward"] as? NSNumber)?.intValue ?? 0
        self.constraints = (data["constraints"] as? [String: AnyHashable]) ?? [:]
        self.difficultyWeight = (data["difficulty_weight"] as? Int) ?? (data["difficulty_weight"] as? NSNumber)?.intValue ?? 1
        self.active = data["active"] as? Bool ?? true
    }
}

struct ObjectiveProgressEntry: Identifiable, Hashable {
    let id: String
    let templateId: String
    let code: String
    let title: String
    let progress: Int
    let target: Int
    let completed: Bool
    let claimed: Bool
    let xpReward: Int

    init(id: String, data: [String: Any]) {
        self.id = id
        self.templateId = (data["template_id"] as? String) ?? id
        self.code = (data["code"] as? String) ?? id
        self.title = (data["title"] as? String) ?? "Objective"
        self.progress = (data["progress"] as? Int) ?? (data["progress"] as? NSNumber)?.intValue ?? 0
        self.target = (data["target"] as? Int) ?? (data["target"] as? NSNumber)?.intValue ?? 1
        self.completed = data["completed"] as? Bool ?? false
        self.claimed = data["claimed"] as? Bool ?? false
        self.xpReward = (data["xp_reward"] as? Int) ?? (data["xp_reward"] as? NSNumber)?.intValue ?? 0
    }
}

struct ObjectiveAssignment: Identifiable, Hashable {
    let id: String
    let userId: String
    let window: ObjectiveWindow
    let periodKey: String
    let objectives: [ObjectiveProgressEntry]
    let allCompletedBonusXP: Int
    let allCompletedBonusGranted: Bool
    let createdAt: Timestamp?
    let expiresAt: Timestamp?

    init(id: String, window: ObjectiveWindow, periodKey: String, data: [String: Any]) {
        self.id = id
        self.userId = (data["user_id"] as? String) ?? ""
        self.window = window
        self.periodKey = periodKey
        let rawObjectives = data["objectives"] as? [[String: Any]] ?? []
        self.objectives = rawObjectives.enumerated().map { idx, item in
            ObjectiveProgressEntry(id: "\(id)_\(idx)", data: item)
        }
        self.allCompletedBonusXP = (data["all_completed_bonus_xp"] as? Int) ?? (data["all_completed_bonus_xp"] as? NSNumber)?.intValue ?? 0
        self.allCompletedBonusGranted = data["all_completed_bonus_granted"] as? Bool ?? false
        self.createdAt = data["created_at"] as? Timestamp
        self.expiresAt = data["expires_at"] as? Timestamp
    }
}

struct SecretUnlockDefinition: Identifiable, Hashable {
    let id: String
    let code: String
    let title: String
    let detail: String
    let hintTitle: String
    let hintText: String
    let rarity: RewardRarity
    let masterSequenceOrder: Int
    let xpReward: Int
    let unlockableRewardIds: [String]
    let isRepeatable: Bool
    let triggerMetric: String
    let triggerThreshold: Int
    let active: Bool

    init(id: String, data: [String: Any]) {
        self.id = id
        self.code = (data["code"] as? String) ?? id
        self.title = (data["title"] as? String) ?? "Secret Unlock"
        self.detail = (data["description"] as? String) ?? ""
        self.hintTitle = (data["hint_title"] as? String) ?? "?????"
        self.hintText = (data["hint_text"] as? String) ?? ""
        self.rarity = RewardRarity(rawValue: (data["rarity"] as? String) ?? "") ?? .rare
        self.masterSequenceOrder = (data["master_sequence_order"] as? Int) ?? (data["master_sequence_order"] as? NSNumber)?.intValue ?? 0
        self.xpReward = (data["xp_reward"] as? Int) ?? (data["xp_reward"] as? NSNumber)?.intValue ?? 0
        self.unlockableRewardIds = data["unlockable_reward_ids"] as? [String] ?? []
        self.isRepeatable = data["is_repeatable"] as? Bool ?? false
        let trigger = data["trigger_condition"] as? [String: Any] ?? [:]
        self.triggerMetric = (trigger["metric"] as? String) ?? "unknown"
        self.triggerThreshold = (trigger["threshold"] as? Int) ?? (trigger["threshold"] as? NSNumber)?.intValue ?? 1
        self.active = data["active"] as? Bool ?? true
    }
}

struct UserSecretUnlockState: Identifiable, Hashable {
    let id: String
    let userId: String
    let secretId: String
    let discoveredAt: Timestamp?
    let discoveryOrder: Int
    let claimed: Bool
    let xpGranted: Int
    let unlockablesGranted: [String]

    init(id: String, data: [String: Any]) {
        self.id = id
        self.userId = (data["user_id"] as? String) ?? ""
        self.secretId = (data["secret_id"] as? String) ?? ""
        self.discoveredAt = data["discovered_at"] as? Timestamp
        self.discoveryOrder = (data["discovery_order"] as? Int) ?? (data["discovery_order"] as? NSNumber)?.intValue ?? 0
        self.xpGranted = (data["xp_granted"] as? Int) ?? (data["xp_granted"] as? NSNumber)?.intValue ?? 0
        self.claimed = (data["claimed"] as? Bool) ?? (self.xpGranted > 0)
        self.unlockablesGranted = data["unlockables_granted"] as? [String] ?? []
    }
}

struct UserGamificationMetrics: Hashable {
    let userId: String
    let ratedGamesCount: Int
    let reviewedGamesCount: Int
    let logActionsCount: Int
    let searchActionsCount: Int
    let savedGamesCount: Int
    let listItemsAddedCount: Int
    let listsCreatedCount: Int
    let likesGivenCount: Int
    let commentsWrittenCount: Int
    let followsCount: Int
    let flaggedGamesCount: Int
    let viewActionsCount: Int
    let perfectTenRatingsCount: Int
    let doubleTakeRatingsCount: Int
    let lowHPRatingsCount: Int
    let completedQuestsCount: Int
    let rabidRaterBestCount: Int
    let retroSavedGamesCount: Int
    let ratingsByDay: [String: Int]
    let retroReviewsCount: Int
    let retroGamesLoggedCount: Int
    let reviewsByDay: [String: Int]
    let savesByDay: [String: Int]
    let listAddsByDay: [String: Int]
    let listCreationsByDay: [String: Int]
    let loggingActionsByDay: [String: Int]
    let actionCategoriesByDay: [String: [String]]
    let objectiveCompletionsByDay: [String: Int]
    let dailyObjectiveCompletionsByDay: [String: Int]
    let questCompletionsByDay: [String: Int]
    let collectionHabitCompletedSessionsCount: Int
    let lastActiveDayKey: String?

    init(userId: String, data: [String: Any]) {
        self.userId = userId
        self.ratedGamesCount = (data["rated_games_count"] as? Int) ?? (data["rated_games_count"] as? NSNumber)?.intValue ?? 0
        self.reviewedGamesCount = (data["reviewed_games_count"] as? Int) ?? (data["reviewed_games_count"] as? NSNumber)?.intValue ?? 0
        self.logActionsCount = (data["log_actions_count"] as? Int) ?? (data["log_actions_count"] as? NSNumber)?.intValue ?? 0
        self.searchActionsCount = (data["search_actions_count"] as? Int) ?? (data["search_actions_count"] as? NSNumber)?.intValue ?? 0
        self.savedGamesCount = (data["saved_games_count"] as? Int) ?? (data["saved_games_count"] as? NSNumber)?.intValue ?? 0
        self.listItemsAddedCount = (data["list_items_added_count"] as? Int) ?? (data["list_items_added_count"] as? NSNumber)?.intValue ?? 0
        self.listsCreatedCount = (data["lists_created_count"] as? Int) ?? (data["lists_created_count"] as? NSNumber)?.intValue ?? 0
        self.likesGivenCount = (data["likes_given_count"] as? Int) ?? (data["likes_given_count"] as? NSNumber)?.intValue ?? 0
        self.commentsWrittenCount = (data["comments_written_count"] as? Int) ?? (data["comments_written_count"] as? NSNumber)?.intValue ?? 0
        self.followsCount = (data["follows_count"] as? Int) ?? (data["follows_count"] as? NSNumber)?.intValue ?? 0
        self.flaggedGamesCount = (data["flagged_games_count"] as? Int) ?? (data["flagged_games_count"] as? NSNumber)?.intValue ?? 0
        self.viewActionsCount = (data["view_actions_count"] as? Int) ?? (data["view_actions_count"] as? NSNumber)?.intValue ?? 0
        self.perfectTenRatingsCount = (data["perfect_ten_ratings_count"] as? Int) ?? (data["perfect_ten_ratings_count"] as? NSNumber)?.intValue ?? 0
        self.doubleTakeRatingsCount = (data["double_take_ratings_count"] as? Int) ?? (data["double_take_ratings_count"] as? NSNumber)?.intValue ?? 0
        self.lowHPRatingsCount = (data["low_hp_ratings_count"] as? Int) ?? (data["low_hp_ratings_count"] as? NSNumber)?.intValue ?? 0
        self.completedQuestsCount = (data["completed_quests_count"] as? Int) ?? (data["completed_quests_count"] as? NSNumber)?.intValue ?? 0
        self.rabidRaterBestCount = (data["rabid_rater_best_count"] as? Int) ?? (data["rabid_rater_best_count"] as? NSNumber)?.intValue ?? 0
        self.retroSavedGamesCount = (data["retro_saved_games_count"] as? Int) ?? (data["retro_saved_games_count"] as? NSNumber)?.intValue ?? 0
        self.ratingsByDay = (data["ratings_by_day"] as? [String: Int]) ?? [:]
        self.retroReviewsCount = (data["retro_reviews_count"] as? Int) ?? (data["retro_reviews_count"] as? NSNumber)?.intValue ?? 0
        self.retroGamesLoggedCount = (data["retro_games_logged_count"] as? Int) ?? (data["retro_games_logged_count"] as? NSNumber)?.intValue ?? 0
        self.reviewsByDay = (data["reviews_by_day"] as? [String: Int]) ?? [:]
        self.savesByDay = (data["saves_by_day"] as? [String: Int]) ?? [:]
        self.listAddsByDay = (data["list_adds_by_day"] as? [String: Int]) ?? [:]
        self.listCreationsByDay = (data["list_creations_by_day"] as? [String: Int]) ?? [:]
        self.loggingActionsByDay = (data["logging_actions_by_day"] as? [String: Int]) ?? [:]
        self.actionCategoriesByDay = (data["action_categories_by_day"] as? [String: [String]]) ?? [:]
        self.objectiveCompletionsByDay = (data["objective_completions_by_day"] as? [String: Int]) ?? [:]
        self.dailyObjectiveCompletionsByDay = (data["daily_objective_completions_by_day"] as? [String: Int]) ?? [:]
        self.questCompletionsByDay = (data["quest_completions_by_day"] as? [String: Int]) ?? [:]
        self.collectionHabitCompletedSessionsCount = (data["collection_habit_sessions_completed"] as? Int) ?? (data["collection_habit_sessions_completed"] as? NSNumber)?.intValue ?? 0
        self.lastActiveDayKey = data["last_active_day_key"] as? String
    }
}

private enum GamificationSeedCatalog {
    static let achievements: [[String: Any]] = makeAchievementSeeds()

    private static func makeAchievementSeeds() -> [[String: Any]] {
        let quests: [(id: String, code: String, title: String, description: String, hint: String, category: String, rarity: String, xp: Int, metric: String, threshold: Int)] = [
            ("first_rating", "first_rating", "First Rating", "Rate your first game", "A number thrown into the void.", "rating", "common", 25, "rated_games_count", 1),
            ("rabid_rater", "rabid_rater", "Rabid Rater", "Rate 10 games within the same 24-hour period", "A pattern starts with repetition.", "rating", "common", 40, "placeholder_unimplemented_metric", 999999),
            ("century_scorer", "century_scorer", "Century Scorer", "Rate 100 games", "The centennial shape of a critic.", "rating", "epic", 150, "rated_games_count", 100),
            ("loyal_gamer", "loyal_gamer", "Loyal Gamer", "Rate 10 games from the same developer or publisher", "Some creators keep calling you back.", "rating", "rare", 75, "placeholder_unimplemented_metric", 999999),
            ("platform_expert", "platform_expert", "Platform Expert", "Rate 50 games on the same platform", "One machine many memories.", "rating", "rare", 75, "placeholder_unimplemented_metric", 999999),
            ("genre_pulse", "genre_pulse", "Genre Pulse", "Rate 10 games in the same genre", "A taste begins to reveal itself.", "rating", "rare", 75, "placeholder_unimplemented_metric", 999999),
            ("the_big_n_approves", "the_big_n_approves", "The Big 'N' Approves", "Rate 50 games developed or published by Nintendo", "One universe earns devotion.", "rating", "rare", 85, "placeholder_unimplemented_metric", 999999),
            ("era_sampler", "era_sampler", "Era Sampler", "Rate games from 5 different release decades", "Time leaves fingerprints on play.", "rating", "rare", 90, "placeholder_unimplemented_metric", 999999),
            ("rgb_maniac", "rgb_maniac", "RGB Maniac", "Use at least 8 different rating bands across your ratings", "A wide scale tells a richer story.", "rating", "epic", 140, "placeholder_unimplemented_metric", 999999),
            ("gotta_rate_em_all", "gotta_rate_em_all", "Gotta Rate 'em All!", "Rate 151 games", "Judgment becomes identity.", "rating", "legendary", 300, "rated_games_count", 151),
            ("baby_critic", "baby_critic", "Baby Critic", "Review your first game", "A score becomes a statement.", "reviewing", "common", 30, "reviewed_games_count", 1),
            ("now_you_re_talkin", "now_you_re_talkin", "Now You're Talkin'", "Review 50 games", "Thoughts become a body of work.", "reviewing", "rare", 70, "reviewed_games_count", 50),
            ("review_archive", "review_archive", "Archive of Your Mind", "Review 100 games", "Your library starts talking back.", "reviewing", "legendary", 300, "reviewed_games_count", 100),
            ("no_limits", "no_limits", "No Limits", "Review games across PlayStation 1, 2, 3, 4, and 5", "One platform tells a full story.", "reviewing", "epic", 150, "placeholder_unimplemented_metric", 999999),
            ("platform_professional", "platform_professional", "Platform Professional", "Review 25 games on the same platform", "One platform teaches its own language.", "reviewing", "epic", 150, "placeholder_unimplemented_metric", 999999),
            ("genre_genius", "genre_genius", "Genre Genius", "Review 25 games in the same genre", "Taste sharpens through comparison.", "reviewing", "rare", 90, "placeholder_unimplemented_metric", 999999),
            ("mature_mind", "mature_mind", "Mature Mind", "Review 10 retro games", "Older worlds still deserve new words.", "reviewing", "epic", 140, "retro_reviews_count", 10),
            ("rhythm_writer", "rhythm_writer", "Rhythm Writer", "Write a review every day for 7 straight days", "Consistency leaves a signature.", "reviewing", "rare", 85, "placeholder_unimplemented_metric", 999999),
            ("long_winded", "long_winded", "Long-winded", "Write 20 reviews longer than 650 characters", "Some thoughts need room to breathe.", "reviewing", "epic", 160, "placeholder_unimplemented_metric", 999999),
            ("canon_fodder", "canon_fodder", "Canon Fodder", "Review 5 games from the same franchise", "A series becomes a conversation.", "reviewing", "rare", 95, "placeholder_unimplemented_metric", 999999),
            ("save_continue", "save_continue", "Save & Continue", "Save your first game", "Curiosity makes a bookmark.", "saving_games", "common", 25, "saved_games_count", 1),
            ("wishlist_wizard", "wishlist_wizard", "Wishlist Wizard", "Save 20 games", "The future starts filling up.", "saving_games", "common", 40, "saved_games_count", 20),
            ("the_collector", "the_collector", "The Collector", "Save 100 games", "A library begins before the first play.", "saving_games", "epic", 140, "saved_games_count", 100),
            ("studio_watchlist", "studio_watchlist", "Studio Watchlist", "Save 10 games from the same developer or publisher", "One studio holds your attention.", "saving_games", "rare", 70, "placeholder_unimplemented_metric", 999999),
            ("platform_peruser", "platform_peruser", "Platform Peruser", "Save 15 games on the same platform", "One platform becomes a destination.", "saving_games", "rare", 70, "placeholder_unimplemented_metric", 999999),
            ("genre_geek", "genre_geek", "Genre Geek", "Save 15 games in the same genre", "Taste reveals itself before play begins.", "saving_games", "rare", 70, "placeholder_unimplemented_metric", 999999),
            ("alpha_zeta", "alpha_zeta", "Alpha Zeta", "Save games that start with every letter of the alphabet", "From A to Z, nothing escapes you.", "saving_games", "epic", 135, "placeholder_unimplemented_metric", 999999),
            ("pre_order_bonus", "pre_order_bonus", "Pre-Order Bonus", "Save 5 upcoming releases", "Anticipation is its own hobby.", "saving_games", "rare", 90, "placeholder_unimplemented_metric", 999999),
            ("preserve_the_classics", "preserve_the_classics", "Preserve the Classics", "Save 15 retro games", "The past still has room on your shelf.", "saving_games", "rare", 90, "retro_saved_games_count", 15),
            ("procrastination", "procrastination", "Procrastination", "Create a list titled \"Backlog\" or \"Back Log\" and add a game to it", "Some lists define what matters.", "lists", "rare", 80, "placeholder_unimplemented_metric", 999999),
            ("the_first_of_many", "the_first_of_many", "The First of Many", "Create your first list", "Curation begins with naming something.", "lists", "common", 30, "lists_created_count", 1),
            ("list_habit", "list_habit", "List Habit", "Add 10 games to lists", "A collection starts with placement.", "lists", "common", 25, "list_items_added_count", 10),
            ("show_off", "show_off", "Show Off", "Create 10 public ranked lists", "Your shelves start taking shape.", "lists", "rare", 80, "placeholder_unimplemented_metric", 999999),
            ("psn", "psn", "PSN", "Create 5 lists with 5 Sony-developed or Sony-published games in each", "One shelf becomes many.", "lists", "legendary", 280, "placeholder_unimplemented_metric", 999999),
            ("the_curator", "the_curator", "The Curator", "Add 50 games to the same list", "A theme becomes intentional.", "lists", "rare", 85, "placeholder_unimplemented_metric", 999999),
            ("public_opinion", "public_opinion", "Public Opinion", "Create 5 public ranked, tiered, and standard lists", "Order reveals conviction.", "lists", "epic", 125, "placeholder_unimplemented_metric", 999999),
            ("tier_architect", "tier_architect", "Tier Architect", "Create 10 public tier lists", "Not every favorite fits a line.", "lists", "rare", 70, "placeholder_unimplemented_metric", 999999),
            ("keepsake", "keepsake", "Keepsake", "Create 1 private standard, ranked, and tiered list", "Taste becomes a performance.", "lists", "common", 30, "placeholder_unimplemented_metric", 999999),
            ("a_bit_much", "a_bit_much", "A Bit Much", "Add 100 games to a single ranked list", "Curation scales with commitment.", "lists", "epic", 100, "placeholder_unimplemented_metric", 999999),
            ("the_connoisseur", "the_connoisseur", "The Connoisseur", "Add 1000 games to lists", "Curation becomes architecture.", "lists", "legendary", 275, "placeholder_unimplemented_metric", 999999),
            ("first_search", "first_search", "First Search", "Search for your first game", "Every journey starts with a search.", "exploration_misc", "common", 25, "search_actions_count", 1),
            ("participation_trophy", "participation_trophy", "Participation Trophy", "Like 1000 different game logs from other users", "Curiosity rewards momentum.", "exploration_misc", "epic", 130, "likes_given_count", 1000),
            ("housemaid", "housemaid", "Housemaid", "Flag 20 games", "Care keeps the library clean.", "exploration_misc", "legendary", 200, "placeholder_unimplemented_metric", 999999),
            ("set_in_your_ways", "set_in_your_ways", "Set In Your Ways", "Save 20 games from the same platform", "One console can become a country.", "exploration_misc", "epic", 130, "placeholder_unimplemented_metric", 999999),
            ("superfan", "superfan", "Superfan", "View 40 games from the same developer or publisher", "A creator's fingerprints become visible.", "exploration_misc", "epic", 125, "placeholder_unimplemented_metric", 999999),
            ("whats_your_kd", "whats_your_kd", "What's Your K/D?", "Rate 10 first-person shooter games", "Patterns emerge in what you choose.", "exploration_misc", "common", 1, "placeholder_unimplemented_metric", 999999),
            ("8_bit_tourist", "8_bit_tourist", "8-bit Tourist", "Save 10 games from the 1980s", "Browsing becomes instinct.", "exploration_misc", "epic", 130, "retro_saved_games_count", 10),
            ("collection_habit", "collection_habit", "Collection Habit", "Search for a game, save a game, and add a game to a list in the same session", "Discovery is best when it leads somewhere.", "exploration_misc", "rare", 90, "placeholder_unimplemented_metric", 999999),
            ("library_rhythm", "library_rhythm", "Library Rhythm", "Save a game on 7 straight days", "A profile becomes a habit.", "exploration_misc", "epic", 150, "placeholder_unimplemented_metric", 999999),
            ("gamerlnd_citizen", "gamerlnd_citizen", "GamerLnd Citizen", "Complete 25 different quests", "A full identity takes balance.", "exploration_misc", "legendary", 280, "completed_quests_count", 25),
        ]

        let positions: [(row: Int, col: Int)] = [
            (7, 4),
            (2, 0),
            (4, 1),
            (2, 4),
            (4, 0),
            (1, 4),
            (3, 3),
            (6, 4),
            (0, 3),
            (4, 2),
            (8, 0),
            (8, 2),
            (7, 0),
            (7, 3),
            (8, 1),
            (0, 2),
            (1, 1),
            (1, 3),
            (9, 0),
            (1, 0),
            (4, 3),
            (8, 3),
            (3, 0),
            (5, 1),
            (9, 4),
            (8, 4),
            (9, 1),
            (0, 0),
            (5, 2),
            (4, 4),
            (2, 3),
            (3, 1),
            (0, 1),
            (9, 3),
            (5, 3),
            (2, 2),
            (9, 2),
            (6, 3),
            (5, 0),
            (6, 1),
            (0, 4),
            (7, 2),
            (3, 4),
            (5, 4),
            (2, 1),
            (7, 1),
            (6, 0),
            (6, 2),
            (1, 2),
            (3, 2),
        ]

        return quests.enumerated().map { index, quest in
            let position = positions[index]
            return [
                "id": quest.id,
                "code": quest.code,
                "title": quest.title,
                "description": quest.description,
                "hint_title": quest.title,
                "hint_text": quest.hint,
                "category": quest.category,
                "xp_reward": quest.xp,
                "rarity": quest.rarity,
                "unlockable_reward_ids": [],
                "is_secret": false,
                "is_repeatable": false,
                "tile_position": ["row": position.row, "col": position.col],
                "reveals_neighbors": true,
                "unlock_condition": ["metric": quest.metric, "threshold": quest.threshold],
                "active": true
            ]
        }
    }

    static let dailyTemplates: [[String: Any]] = [
        objectiveTemplateSeed(id: "daily_rate_one", type: "daily", title: "Rate One", description: "Rate 1 game", objectiveKind: "rate_games", target: 1, xp: 10, glMin: 1, glMax: 4, weight: 1),
        objectiveTemplateSeed(id: "daily_save_one", type: "daily", title: "Save One", description: "Save 1 game", objectiveKind: "save_games", target: 1, xp: 10, glMin: 1, glMax: 4, weight: 1),
        objectiveTemplateSeed(id: "daily_list_one", type: "daily", title: "List One", description: "Add 1 game to a list", objectiveKind: "list_adds", target: 1, xp: 10, glMin: 1, glMax: 4, weight: 1),
        objectiveTemplateSeed(id: "daily_review_one", type: "daily", title: "Review One", description: "Review 1 game", objectiveKind: "write_reviews", target: 1, xp: 10, glMin: 1, glMax: 4, weight: 1),

        objectiveTemplateSeed(id: "daily_rate_three", type: "daily", title: "Rate Three", description: "Rate 3 games", objectiveKind: "rate_games", target: 3, xp: 15, glMin: 5, glMax: 14, weight: 2),
        objectiveTemplateSeed(id: "daily_save_three", type: "daily", title: "Save Three", description: "Save 3 games", objectiveKind: "save_games", target: 3, xp: 15, glMin: 5, glMax: 14, weight: 2),
        objectiveTemplateSeed(id: "daily_list_three", type: "daily", title: "List Three", description: "Add 3 games to lists", objectiveKind: "list_adds", target: 3, xp: 15, glMin: 5, glMax: 14, weight: 2),
        objectiveTemplateSeed(id: "daily_double_log", type: "daily", title: "Double Log", description: "Complete 2 logging actions", objectiveKind: "logging_actions", target: 2, xp: 20, glMin: 5, glMax: 14, weight: 2),

        objectiveTemplateSeed(id: "daily_rate_five", type: "daily", title: "Rate Five", description: "Rate 5 games", objectiveKind: "rate_games", target: 5, xp: 20, glMin: 15, glMax: 999, weight: 3),
        objectiveTemplateSeed(id: "daily_review_two", type: "daily", title: "Review Two", description: "Review 2 games", objectiveKind: "write_reviews", target: 2, xp: 25, glMin: 15, glMax: 999, weight: 3),
        objectiveTemplateSeed(id: "daily_list_five", type: "daily", title: "List Five", description: "Add 5 games to lists", objectiveKind: "list_adds", target: 5, xp: 20, glMin: 15, glMax: 999, weight: 3),
        objectiveTemplateSeed(id: "daily_save_five", type: "daily", title: "Save Five", description: "Save 5 games", objectiveKind: "save_games", target: 5, xp: 20, glMin: 15, glMax: 999, weight: 3),
        objectiveTemplateSeed(id: "daily_quest_chain", type: "daily", title: "Quest Chain", description: "Complete 1 quest and 1 objective in the same day", objectiveKind: "quest_chain", target: 1, xp: 30, glMin: 15, glMax: 999, weight: 4)
    ]

    static let weeklyTemplates: [[String: Any]] = [
        objectiveTemplateSeed(id: "weekly_rate_ten", type: "weekly", title: "Rate Ten", description: "Rate 10 games", objectiveKind: "rate_games", target: 10, xp: 50, glMin: 1, glMax: 4, weight: 1),
        objectiveTemplateSeed(id: "weekly_save_five_beginner", type: "weekly", title: "Save Five", description: "Save 5 games", objectiveKind: "save_games", target: 5, xp: 45, glMin: 1, glMax: 4, weight: 1),
        objectiveTemplateSeed(id: "weekly_list_five", type: "weekly", title: "List Five", description: "Add 5 games to lists", objectiveKind: "list_adds", target: 5, xp: 45, glMin: 1, glMax: 4, weight: 1),
        objectiveTemplateSeed(id: "weekly_create_one_list", type: "weekly", title: "Create One List", description: "Create 1 list", objectiveKind: "create_lists", target: 1, xp: 50, glMin: 1, glMax: 4, weight: 1),

        objectiveTemplateSeed(id: "weekly_review_three", type: "weekly", title: "Review Three", description: "Review 3 games", objectiveKind: "write_reviews", target: 3, xp: 60, glMin: 5, glMax: 14, weight: 2),
        objectiveTemplateSeed(id: "weekly_rate_fifteen", type: "weekly", title: "Rate Fifteen", description: "Rate 15 games", objectiveKind: "rate_games", target: 15, xp: 55, glMin: 5, glMax: 14, weight: 2),
        objectiveTemplateSeed(id: "weekly_save_ten", type: "weekly", title: "Save Ten", description: "Save 10 games", objectiveKind: "save_games", target: 10, xp: 55, glMin: 5, glMax: 14, weight: 2),
        objectiveTemplateSeed(id: "weekly_list_ten", type: "weekly", title: "List Ten", description: "Add 10 games to lists", objectiveKind: "list_adds", target: 10, xp: 55, glMin: 5, glMax: 14, weight: 2),
        objectiveTemplateSeed(id: "weekly_daily_streak", type: "weekly", title: "Daily Streak", description: "Complete 3 daily objectives", objectiveKind: "daily_objectives_completed", target: 3, xp: 60, glMin: 5, glMax: 14, weight: 3),

        objectiveTemplateSeed(id: "weekly_review_five", type: "weekly", title: "Review Five", description: "Review 5 games", objectiveKind: "write_reviews", target: 5, xp: 75, glMin: 15, glMax: 999, weight: 3),
        objectiveTemplateSeed(id: "weekly_rate_twenty_five", type: "weekly", title: "Rate Twenty-Five", description: "Rate 25 games", objectiveKind: "rate_games", target: 25, xp: 75, glMin: 15, glMax: 999, weight: 3),
        objectiveTemplateSeed(id: "weekly_create_two_lists", type: "weekly", title: "Create Two Lists", description: "Create 2 lists", objectiveKind: "create_lists", target: 2, xp: 80, glMin: 15, glMax: 999, weight: 3),
        objectiveTemplateSeed(id: "weekly_four_day_presence", type: "weekly", title: "Four-Day Presence", description: "Complete objectives on 4 different days", objectiveKind: "objective_presence_days", target: 4, xp: 80, glMin: 15, glMax: 999, weight: 4),
        objectiveTemplateSeed(id: "weekly_category_spread", type: "weekly", title: "Category Spread", description: "Complete actions across 3 quest categories", objectiveKind: "category_spread", target: 3, xp: 85, glMin: 15, glMax: 999, weight: 4)
    ]

    private static func objectiveTemplateSeed(
        id: String,
        type: String,
        title: String,
        description: String,
        objectiveKind: String,
        target: Int,
        xp: Int,
        glMin: Int,
        glMax: Int,
        weight: Int
    ) -> [String: Any] {
        [
            "id": id,
            "code": id,
            "type": type,
            "title": title,
            "description": description,
            "objective_kind": objectiveKind,
            "target_value": target,
            "xp_reward": xp,
            "constraints": [
                "gl_min": glMin,
                "gl_max": glMax
            ],
            "difficulty_weight": weight,
            "active": true
        ]
    }

    static let secretUnlocks: [[String: Any]] = [
        [
            "id": "monochromatic",
            "code": "monochromatic",
            "title": "Monochromatic",
            "description": "Use One color for all Tiers in a Tier list",
            "hint_title": "?????",
            "hint_text": "A single shade defines your order.",
            "master_sequence_order": 0,
            "rarity": "epic",
            "xp_reward": 300,
            "unlockable_reward_ids": [],
            "is_repeatable": false,
            "trigger_condition": ["metric": "placeholder_unimplemented_metric", "threshold": 999999],
            "active": true
        ],
        [
            "id": "perfect_ten",
            "code": "perfect_ten",
            "title": "Perfect Ten",
            "description": "Rate a game 10.0",
            "hint_title": "?????",
            "hint_text": "Perfection leaves no room above.",
            "master_sequence_order": 1,
            "rarity": "epic",
            "xp_reward": 300,
            "unlockable_reward_ids": [],
            "is_repeatable": false,
            "trigger_condition": ["metric": "perfect_ten_ratings_count", "threshold": 1],
            "active": true
        ],
        [
            "id": "double_take",
            "code": "double_take",
            "title": "Double Take",
            "description": "Rate two games the same score back-to-back",
            "hint_title": "?????",
            "hint_text": "The same feeling strikes twice.",
            "master_sequence_order": 2,
            "rarity": "epic",
            "xp_reward": 300,
            "unlockable_reward_ids": [],
            "is_repeatable": false,
            "trigger_condition": ["metric": "double_take_ratings_count", "threshold": 1],
            "active": true
        ],
        [
            "id": "silent_shelf",
            "code": "silent_shelf",
            "title": "Silent Shelf",
            "description": "Save 20 games without rating any of them first",
            "hint_title": "?????",
            "hint_text": "A shelf built without judgment.",
            "master_sequence_order": 3,
            "rarity": "epic",
            "xp_reward": 300,
            "unlockable_reward_ids": [],
            "is_repeatable": false,
            "trigger_condition": ["metric": "saved_games_count", "threshold": 20],
            "active": true
        ],
        [
            "id": "negative_nancy",
            "code": "negative_nancy",
            "title": "Negative Nancy",
            "description": "Add 5 games to a tier labeled \"F\" in a public Tier List",
            "hint_title": "?????",
            "hint_text": "Some games fall to the bottom.",
            "master_sequence_order": 4,
            "rarity": "epic",
            "xp_reward": 300,
            "unlockable_reward_ids": [],
            "is_repeatable": false,
            "trigger_condition": ["metric": "placeholder_unimplemented_metric", "threshold": 999999],
            "active": true
        ],
        [
            "id": "completionist",
            "code": "completionist",
            "title": "Completionist",
            "description": "Complete all quests in the GamerLnd Quest Board",
            "hint_title": "?????",
            "hint_text": "100%",
            "master_sequence_order": 5,
            "rarity": "legendary",
            "xp_reward": 300,
            "unlockable_reward_ids": [],
            "is_repeatable": false,
            "trigger_condition": ["metric": "completed_quests_count", "threshold": 50],
            "active": true
        ],
        [
            "id": "low_hp",
            "code": "low_hp",
            "title": "Low HP",
            "description": "Rate 10 games between 1.0 and 1.9 out of 10",
            "hint_title": "?????",
            "hint_text": "Living on the edge of failure.",
            "master_sequence_order": 6,
            "rarity": "epic",
            "xp_reward": 300,
            "unlockable_reward_ids": [],
            "is_repeatable": false,
            "trigger_condition": ["metric": "low_hp_ratings_count", "threshold": 10],
            "active": true
        ]
    ]
}

// MARK: - Gamification Services

final class LevelService {
    static let shared = LevelService()
    private init() {}

    func levelInfo(totalXP: Int) -> RewardService.LevelInfo {
        RewardService.levelInfo(for: totalXP)
    }
}

final class AchievementService {
    static let shared = AchievementService()
    private let db = Firestore.firestore()
    private let igdb = IGDBService()
    let boardRows = 10
    let boardColumns = 5
    private init() {}

    func fetchAchievementCatalog(completion: @escaping ([AchievementDefinition]) -> Void) {
        db.collection("achievements")
            .whereField("active", isEqualTo: true)
            .getDocuments { snap, _ in
                let seedById = Dictionary(uniqueKeysWithValues: GamificationSeedCatalog.achievements.compactMap { seed -> (String, [String: Any])? in
                    guard let id = seed["id"] as? String else { return nil }
                    return (id, seed)
                })
                let seedByCode = Dictionary(uniqueKeysWithValues: GamificationSeedCatalog.achievements.compactMap { seed -> (String, [String: Any])? in
                    guard let code = seed["code"] as? String else { return nil }
                    return (code, seed)
                })
                let remoteDocs = snap?.documents ?? []
                if remoteDocs.isEmpty {
                    completion(GamificationSeedCatalog.achievements.map {
                        AchievementDefinition(id: ($0["id"] as? String) ?? UUID().uuidString, data: $0)
                    }.sorted(by: self.boardSort))
                } else {
                    let merged = remoteDocs.map { doc -> AchievementDefinition in
                        var data = doc.data()
                        let remoteId = doc.documentID
                        let remoteCode = data["code"] as? String
                        if let seed = seedById[remoteId] ?? (remoteCode.flatMap { seedByCode[$0] }) {
                            data.merge(seed) { _, seedValue in seedValue }
                        }
                        return AchievementDefinition(id: remoteId, data: data)
                    }
                    completion(merged.sorted(by: self.boardSort))
                }
            }
    }

    func fetchUserAchievements(userId: String, completion: @escaping ([UserAchievementState]) -> Void) {
        db.collection("user_achievements")
            .whereField("user_id", isEqualTo: userId)
            .getDocuments { snap, _ in
                completion((snap?.documents ?? []).map { UserAchievementState(id: $0.documentID, data: $0.data()) })
            }
    }

    func handleEvent(_ event: RewardService.GamificationEvent) {
        persistAuxiliaryEventState(for: event)
        updateMetrics(for: event) { metrics in
            guard let metrics else { return }
            self.fetchAchievementCatalog { definitions in
                self.fetchUserAchievements(userId: event.userId) { states in
                    self.evaluate(definitions: definitions, existingStates: states, metrics: metrics, userId: event.userId)
                    SecretUnlockService.shared.handleEvent(event, metrics: metrics)
                }
            }
        }
    }

    private func persistAuxiliaryEventState(for event: RewardService.GamificationEvent) {
        switch event.kind {
        case .viewGame:
            guard let gameId = event.gameId else { return }
            db.collection("user_game_views").document("\(event.userId)_\(gameId)").setData([
                "user_id": event.userId,
                "game_id": gameId,
                "last_viewed_at": Timestamp(date: event.occurredAt),
                "first_viewed_at": FieldValue.serverTimestamp()
            ], merge: true)
        default:
            break
        }
    }

    private func updateMetrics(
        for event: RewardService.GamificationEvent,
        completion: @escaping (UserGamificationMetrics?) -> Void
    ) {
        let ref = db.collection("user_metrics").document(event.userId)
        let dayKey = ObjectiveService.dayKey(for: event.occurredAt)

        db.runTransaction({ transaction, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            var data = snap.data() ?? [:]
            data["user_id"] = event.userId
            data["last_active_day_key"] = dayKey
            data["updated_at"] = Timestamp(date: event.occurredAt)

            switch event.kind {
            case .rateGame:
                self.incrementDailyMetric("logging_actions_by_day", dayKey: dayKey, in: &data)
                self.insertDailyCategory("rating", dayKey: dayKey, in: &data)
                let current = (data["rated_games_count"] as? Int) ?? (data["rated_games_count"] as? NSNumber)?.intValue ?? 0
                data["rated_games_count"] = current + 1
                var ratingsByDay = (data["ratings_by_day"] as? [String: Int]) ?? [:]
                ratingsByDay[dayKey] = (ratingsByDay[dayKey] ?? 0) + 1
                data["ratings_by_day"] = ratingsByDay
                var recentRatings = ((data["rating_event_timestamps"] as? [Double]) ?? []).filter { $0 >= event.occurredAt.timeIntervalSince1970 - 86_400 }
                recentRatings.append(event.occurredAt.timeIntervalSince1970)
                data["rating_event_timestamps"] = recentRatings
                let bestWindowCount = max(
                    (data["rabid_rater_best_count"] as? Int) ?? (data["rabid_rater_best_count"] as? NSNumber)?.intValue ?? 0,
                    recentRatings.count
                )
                data["rabid_rater_best_count"] = bestWindowCount
                if let ratingValue = event.ratingValue, ratingValue >= 10.0 {
                    let perfects = (data["perfect_ten_ratings_count"] as? Int) ?? (data["perfect_ten_ratings_count"] as? NSNumber)?.intValue ?? 0
                    data["perfect_ten_ratings_count"] = perfects + 1
                }
                if let ratingValue = event.ratingValue, ratingValue >= 1.0, ratingValue < 2.0 {
                    let lowHP = (data["low_hp_ratings_count"] as? Int) ?? (data["low_hp_ratings_count"] as? NSNumber)?.intValue ?? 0
                    data["low_hp_ratings_count"] = lowHP + 1
                }
                if let ratingValue = event.ratingValue {
                    let lastRating = (data["last_rating_value"] as? Double) ?? (data["last_rating_value"] as? NSNumber)?.doubleValue
                    if let lastRating, abs(lastRating - ratingValue) < 0.001 {
                        let doubles = (data["double_take_ratings_count"] as? Int) ?? (data["double_take_ratings_count"] as? NSNumber)?.intValue ?? 0
                        data["double_take_ratings_count"] = doubles + 1
                    }
                    data["last_rating_value"] = ratingValue
                }
            case .writeReview:
                self.incrementDailyMetric("logging_actions_by_day", dayKey: dayKey, in: &data)
                self.insertDailyCategory("reviewing", dayKey: dayKey, in: &data)
                let current = (data["reviewed_games_count"] as? Int) ?? (data["reviewed_games_count"] as? NSNumber)?.intValue ?? 0
                data["reviewed_games_count"] = current + 1
                var reviewsByDay = (data["reviews_by_day"] as? [String: Int]) ?? [:]
                reviewsByDay[dayKey] = (reviewsByDay[dayKey] ?? 0) + 1
                data["reviews_by_day"] = reviewsByDay
                if let releaseYear = event.releaseYear, releaseYear < 2000 {
                    let retro = (data["retro_reviews_count"] as? Int) ?? (data["retro_reviews_count"] as? NSNumber)?.intValue ?? 0
                    data["retro_reviews_count"] = retro + 1
                }
            case .saveGame:
                self.incrementDailyMetric("logging_actions_by_day", dayKey: dayKey, in: &data)
                self.insertDailyCategory("saving_games", dayKey: dayKey, in: &data)
                let current = (data["log_actions_count"] as? Int) ?? (data["log_actions_count"] as? NSNumber)?.intValue ?? 0
                data["log_actions_count"] = current + 1
                let saved = (data["saved_games_count"] as? Int) ?? (data["saved_games_count"] as? NSNumber)?.intValue ?? 0
                data["saved_games_count"] = saved + 1
                var savesByDay = (data["saves_by_day"] as? [String: Int]) ?? [:]
                savesByDay[dayKey] = (savesByDay[dayKey] ?? 0) + 1
                data["saves_by_day"] = savesByDay
                self.updateCollectionHabitSession(data: &data, event: event)
                if let releaseYear = event.releaseYear, releaseYear < 2000 {
                    let retro = (data["retro_games_logged_count"] as? Int) ?? (data["retro_games_logged_count"] as? NSNumber)?.intValue ?? 0
                    data["retro_games_logged_count"] = retro + 1
                    let retroSaved = (data["retro_saved_games_count"] as? Int) ?? (data["retro_saved_games_count"] as? NSNumber)?.intValue ?? 0
                    data["retro_saved_games_count"] = retroSaved + 1
                }
            case .addToList:
                self.incrementDailyMetric("logging_actions_by_day", dayKey: dayKey, in: &data)
                self.incrementDailyMetric("list_adds_by_day", dayKey: dayKey, in: &data)
                self.insertDailyCategory("lists", dayKey: dayKey, in: &data)
                let current = (data["log_actions_count"] as? Int) ?? (data["log_actions_count"] as? NSNumber)?.intValue ?? 0
                data["log_actions_count"] = current + 1
                let listAdds = (data["list_items_added_count"] as? Int) ?? (data["list_items_added_count"] as? NSNumber)?.intValue ?? 0
                data["list_items_added_count"] = listAdds + 1
                self.updateCollectionHabitSession(data: &data, event: event)
            case .createList:
                self.incrementDailyMetric("list_creations_by_day", dayKey: dayKey, in: &data)
                self.insertDailyCategory("lists", dayKey: dayKey, in: &data)
                let current = (data["log_actions_count"] as? Int) ?? (data["log_actions_count"] as? NSNumber)?.intValue ?? 0
                data["log_actions_count"] = current + 1
                let listsCreated = (data["lists_created_count"] as? Int) ?? (data["lists_created_count"] as? NSNumber)?.intValue ?? 0
                data["lists_created_count"] = listsCreated + 1
            case .likeLog:
                let likes = (data["likes_given_count"] as? Int) ?? (data["likes_given_count"] as? NSNumber)?.intValue ?? 0
                data["likes_given_count"] = likes + 1
            case .commentLog:
                let comments = (data["comments_written_count"] as? Int) ?? (data["comments_written_count"] as? NSNumber)?.intValue ?? 0
                data["comments_written_count"] = comments + 1
            case .followUser:
                let follows = (data["follows_count"] as? Int) ?? (data["follows_count"] as? NSNumber)?.intValue ?? 0
                data["follows_count"] = follows + 1
            case .searchGame:
                let current = (data["search_actions_count"] as? Int) ?? (data["search_actions_count"] as? NSNumber)?.intValue ?? 0
                data["search_actions_count"] = current + 1
                self.updateCollectionHabitSession(data: &data, event: event)
            case .viewGame:
                let current = (data["view_actions_count"] as? Int) ?? (data["view_actions_count"] as? NSNumber)?.intValue ?? 0
                data["view_actions_count"] = current + 1
            case .flagGame:
                let current = (data["flagged_games_count"] as? Int) ?? (data["flagged_games_count"] as? NSNumber)?.intValue ?? 0
                data["flagged_games_count"] = current + 1
            }

            transaction.setData(data, forDocument: ref, merge: true)
            return data as NSDictionary
        }) { result, _ in
            guard let data = result as? NSDictionary as? [String: Any] else {
                completion(nil)
                return
            }
            let metrics = UserGamificationMetrics(userId: event.userId, data: data)
            ObjectiveService.shared.refreshAssignmentsFromMetrics(userId: event.userId, date: event.occurredAt, metrics: metrics)
            completion(metrics)
        }
    }

    private func incrementDailyMetric(_ field: String, dayKey: String, in data: inout [String: Any]) {
        var map = (data[field] as? [String: Int]) ?? [:]
        map[dayKey] = (map[dayKey] ?? 0) + 1
        data[field] = map
    }

    private func insertDailyCategory(_ category: String, dayKey: String, in data: inout [String: Any]) {
        var map = (data["action_categories_by_day"] as? [String: [String]]) ?? [:]
        var categories = Set(map[dayKey] ?? [])
        categories.insert(category)
        map[dayKey] = Array(categories).sorted()
        data["action_categories_by_day"] = map
    }

    private func updateCollectionHabitSession(data: inout [String: Any], event: RewardService.GamificationEvent) {
        guard let sessionId = event.sessionId, !sessionId.isEmpty else { return }
        let previousSessionId = data["collection_habit_session_id"] as? String
        var actions = (data["collection_habit_actions"] as? [String: Bool]) ?? [:]
        let alreadyCompleted = data["collection_habit_session_completed"] as? Bool ?? false

        if previousSessionId != sessionId {
            data["collection_habit_session_id"] = sessionId
            actions = [:]
            data["collection_habit_session_completed"] = false
        }

        switch event.kind {
        case .searchGame:
            actions["searched"] = true
        case .saveGame:
            actions["saved"] = true
        case .addToList:
            actions["listed"] = true
        default:
            break
        }

        data["collection_habit_actions"] = actions
        let nowCompleted = (actions["searched"] == true) && (actions["saved"] == true) && (actions["listed"] == true)
        if nowCompleted && !alreadyCompleted {
            let current = (data["collection_habit_sessions_completed"] as? Int) ?? (data["collection_habit_sessions_completed"] as? NSNumber)?.intValue ?? 0
            data["collection_habit_sessions_completed"] = current + 1
            data["collection_habit_session_completed"] = true
        }
    }

    private struct QuestLogSnapshot {
        let gameId: Int
        let rating: Double?
        let review: String?
        let updatedAt: Date
    }

    private struct QuestSavedSnapshot {
        let gameId: Int
        let name: String
        let addedAt: Date?
    }

    private struct QuestListSnapshot {
        let list: UserList
        let items: [UserListItem]
    }

    private struct QuestGameMetadata {
        let gameId: Int
        let name: String
        let releaseYear: Int?
        let genres: Set<String>
        let platforms: Set<String>
        let developers: Set<String>
        let publishers: Set<String>
        let companies: Set<String>
        let franchiseKeys: Set<String>

        init(game: Game) {
            gameId = game.id
            name = game.name
            releaseYear = game.computedReleaseYear
            genres = Set((game.genres ?? []).map { $0.name.lowercased() })
            platforms = Set((game.platforms ?? []).map { $0.name.lowercased() })
            let devs = (game.involvedCompanies ?? []).filter { $0.developer == true }.compactMap { $0.company?.name.lowercased() }
            let pubs = (game.involvedCompanies ?? []).filter { $0.publisher == true }.compactMap { $0.company?.name.lowercased() }
            developers = Set(devs)
            publishers = Set(pubs)
            companies = Set(devs + pubs)
            let franchiseNames = (game.franchises ?? []).map { $0.name.lowercased() }
            let collectionNames = (game.collections ?? []).map { $0.name.lowercased() }
            franchiseKeys = Set(franchiseNames + collectionNames)
        }

        var decadeBucket: Int? {
            guard let releaseYear else { return nil }
            return (releaseYear / 10) * 10
        }

        var isRetro: Bool {
            guard let releaseYear else { return false }
            let currentYear = Calendar.current.component(.year, from: Date())
            return releaseYear <= currentYear - 20
        }

        var isUpcoming: Bool {
            guard let releaseYear else { return false }
            return releaseYear > Calendar.current.component(.year, from: Date())
        }

        var isNintendo: Bool {
            companies.contains { $0.contains("nintendo") }
        }

        var isSony: Bool {
            companies.contains { $0.contains("sony") || $0.contains("playstation") }
        }

        var isFPS: Bool {
            genres.contains(where: { $0.contains("first-person shooter") || $0 == "fps" || $0.contains("shooter") })
        }

        var firstLetter: String? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first else { return nil }
            let upper = String(first).uppercased()
            return upper.range(of: "^[A-Z]$", options: .regularExpression) != nil ? upper : nil
        }

        func playStationGenerations() -> Set<String> {
            var results = Set<String>()
            for platform in platforms {
                if platform.contains("playstation 1") || platform == "ps1" { results.insert("ps1") }
                if platform.contains("playstation 2") || platform == "ps2" { results.insert("ps2") }
                if platform.contains("playstation 3") || platform == "ps3" { results.insert("ps3") }
                if platform.contains("playstation 4") || platform == "ps4" { results.insert("ps4") }
                if platform.contains("playstation 5") || platform == "ps5" { results.insert("ps5") }
            }
            return results
        }
    }

    private struct QuestContext {
        let logs: [QuestLogSnapshot]
        let savedGames: [QuestSavedSnapshot]
        let lists: [QuestListSnapshot]
        let likedLogIds: Set<String>
        let flaggedCount: Int
        let viewedGameIds: Set<Int>
        let gameMetadata: [Int: QuestGameMetadata]
        let metrics: UserGamificationMetrics
    }

    private func evaluate(
        definitions: [AchievementDefinition],
        existingStates: [UserAchievementState],
        metrics: UserGamificationMetrics,
        userId: String
    ) {
        let existingByAchievement = existingStates.reduce(into: [String: UserAchievementState]()) { partial, state in
            let existing = partial[state.achievementId]
            let existingDate = existing?.completedAt?.dateValue() ?? existing?.revealedAt?.dateValue() ?? .distantPast
            let newDate = state.completedAt?.dateValue() ?? state.revealedAt?.dateValue() ?? .distantPast
            if existing == nil || newDate >= existingDate {
                partial[state.achievementId] = state
            }
        }

        buildQuestContext(userId: userId, metrics: metrics) { context in
            var completedCoords = Set<String>()
            for definition in definitions {
                guard let row = definition.tileRow, let col = definition.tileColumn else { continue }
                if existingByAchievement[definition.id]?.state == .completed || existingByAchievement[definition.id]?.completedAt != nil {
                    completedCoords.insert("\(row):\(col)")
                }
            }

            var progressByAchievementId: [String: Int] = [:]
            var completedAchievementIds = Set(existingByAchievement.values.compactMap { state in
                state.completedAt != nil ? state.achievementId : nil
            })

            for definition in definitions where definition.active && !definition.isSecret && definition.code != "gamerlnd_citizen" {
                let progress = self.progressValue(for: definition, context: context, completedQuestCount: completedAchievementIds.count)
                progressByAchievementId[definition.id] = progress
                if progress >= definition.progressTarget {
                    completedAchievementIds.insert(definition.id)
                }
            }

            if let citizen = definitions.first(where: { $0.code == "gamerlnd_citizen" }) {
                progressByAchievementId[citizen.id] = completedAchievementIds.filter { $0 != citizen.id }.count
            }

            for definition in definitions where definition.active && !definition.isSecret {
                let progress = progressByAchievementId[definition.id] ?? self.progressValue(for: definition, context: context, completedQuestCount: completedAchievementIds.count)
                let isComplete = progress >= definition.progressTarget
                let stateRef = self.db.collection("user_achievements").document("\(userId)_\(definition.id)")
                let existingState = existingByAchievement[definition.id]?.state ?? self.defaultTileState(for: definition)
                let nextState: AchievementTileState = isComplete ? .completed : existingState

                var payload: [String: Any] = [
                    "user_id": userId,
                    "achievement_id": definition.id,
                    "state": nextState.rawValue,
                    "progress_current": progress,
                    "progress_target": definition.progressTarget,
                    "claimed": existingByAchievement[definition.id]?.claimed ?? false,
                    "xp_granted": existingByAchievement[definition.id]?.xpGranted ?? 0,
                    "unlockables_granted": existingByAchievement[definition.id]?.unlockablesGranted ?? []
                ]

                if nextState == .hinted && existingByAchievement[definition.id]?.revealedAt == nil {
                    payload["revealed_at"] = Timestamp(date: Date())
                }

                let shouldComplete = isComplete && existingByAchievement[definition.id]?.completedAt == nil
                if shouldComplete {
                    payload["completed_at"] = Timestamp(date: Date())
                    payload["claimed"] = false
                    payload["xp_granted"] = 0
                    payload["unlockables_granted"] = existingByAchievement[definition.id]?.unlockablesGranted ?? []
                    if let row = definition.tileRow, let col = definition.tileColumn {
                        completedCoords.insert("\(row):\(col)")
                    }
                }

                stateRef.setData(payload, merge: true)
                if shouldComplete {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .questCompleted,
                            object: nil,
                            userInfo: [
                                "user_id": userId,
                                "title": definition.title
                            ]
                        )
                    }
                }
            }

            self.revealAdjacentHints(
                definitions: definitions,
                existingStates: existingByAchievement,
                completedCoords: completedCoords,
                userId: userId
            )

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .gamificationUpdated,
                    object: nil,
                    userInfo: ["user_id": userId]
                )
            }
        }
    }

    private func buildQuestContext(userId: String, metrics: UserGamificationMetrics, completion: @escaping (QuestContext) -> Void) {
        let group = DispatchGroup()
        var logs: [QuestLogSnapshot] = []
        var savedGames: [QuestSavedSnapshot] = []
        var lists: [QuestListSnapshot] = []
        var likedLogIds = Set<String>()
        var flaggedCount = 0
        var viewedGameIds = Set<Int>()

        group.enter()
        db.collection("game_logs").whereField("user_id", isEqualTo: userId).getDocuments { snap, _ in
            logs = (snap?.documents ?? []).compactMap { doc in
                let data = doc.data()
                guard let gameId = (data["game_id"] as? NSNumber)?.intValue ?? data["game_id"] as? Int else { return nil }
                let rating = (data["rating"] as? NSNumber)?.doubleValue ?? data["rating"] as? Double
                let review = (data["review"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let updatedAt = (data["updated_at"] as? Timestamp)?.dateValue() ?? (data["play_date"] as? Timestamp)?.dateValue() ?? Date.distantPast
                return QuestLogSnapshot(gameId: gameId, rating: rating, review: (review?.isEmpty == false ? review : nil), updatedAt: updatedAt)
            }
            group.leave()
        }

        group.enter()
        db.collection("users").document(userId).getDocument { snap, _ in
            let list = snap?.data()?["watchlist_games"] as? [[String: Any]] ?? []
            savedGames = list.compactMap { item in
                guard let gameId = (item["id"] as? NSNumber)?.intValue ?? item["id"] as? Int else { return nil }
                let name = (item["name"] as? String) ?? "Game #\(gameId)"
                let addedAt = (item["added_at"] as? Timestamp)?.dateValue()
                return QuestSavedSnapshot(gameId: gameId, name: name, addedAt: addedAt)
            }
            group.leave()
        }

        group.enter()
        db.collection("review_likes").whereField("user_id", isEqualTo: userId).getDocuments { snap, _ in
            likedLogIds = Set((snap?.documents ?? []).compactMap { $0.data()["log_id"] as? String })
            group.leave()
        }

        group.enter()
        db.collection("search_result_reports").whereField("reported_by", isEqualTo: userId).getDocuments { snap, _ in
            flaggedCount = snap?.documents.count ?? 0
            group.leave()
        }

        group.enter()
        db.collection("user_game_views").whereField("user_id", isEqualTo: userId).getDocuments { snap, _ in
            viewedGameIds = Set((snap?.documents ?? []).compactMap { ($0.data()["game_id"] as? NSNumber)?.intValue ?? $0.data()["game_id"] as? Int })
            group.leave()
        }

        group.enter()
        db.collection("lists").whereField("owner_id", isEqualTo: userId).getDocuments { snap, _ in
            let fetchedLists = (snap?.documents ?? []).compactMap { UserList(id: $0.documentID, data: $0.data()) }
            if fetchedLists.isEmpty {
                lists = []
                group.leave()
                return
            }
            let inner = DispatchGroup()
            var built: [QuestListSnapshot] = []
            for list in fetchedLists {
                inner.enter()
                self.db.collection("lists").document(list.id).collection("items").getDocuments { itemSnap, _ in
                    let items = (itemSnap?.documents ?? []).compactMap { doc -> UserListItem? in
                        var data = doc.data()
                        data["list_id"] = list.id
                        return UserListItem(id: doc.documentID, data: data)
                    }
                    built.append(QuestListSnapshot(list: list, items: items))
                    inner.leave()
                }
            }
            inner.notify(queue: .global()) {
                lists = built
                group.leave()
            }
        }

        group.notify(queue: .global()) {
            let allGameIds = Set(logs.map(\.gameId) + savedGames.map(\.gameId) + lists.flatMap { $0.items.map(\.gameId) } + Array(viewedGameIds))
            self.fetchQuestMetadata(gameIds: Array(allGameIds)) { metadata in
                completion(QuestContext(
                    logs: logs,
                    savedGames: savedGames,
                    lists: lists,
                    likedLogIds: likedLogIds,
                    flaggedCount: flaggedCount,
                    viewedGameIds: viewedGameIds,
                    gameMetadata: metadata,
                    metrics: metrics
                ))
            }
        }
    }

    private func fetchQuestMetadata(gameIds: [Int], completion: @escaping ([Int: QuestGameMetadata]) -> Void) {
        guard !gameIds.isEmpty else {
            completion([:])
            return
        }
        igdb.fetchGamesByIds(ids: Array(Set(gameIds))) { result in
            switch result {
            case .success(let games):
                let metadata = Dictionary(uniqueKeysWithValues: games.map { ($0.id, QuestGameMetadata(game: $0)) })
                completion(metadata)
            case .failure:
                completion([:])
            }
        }
    }

    private func progressValue(for definition: AchievementDefinition, context: QuestContext, completedQuestCount: Int) -> Int {
        switch definition.code {
        case "first_rating":
            return context.logs.filter { $0.rating != nil }.count
        case "rabid_rater":
            return context.metrics.rabidRaterBestCount
        case "century_scorer":
            return context.logs.filter { $0.rating != nil }.count
        case "loyal_gamer":
            return maxLabelFrequency(gameIds: context.logs.compactMap { $0.rating != nil ? $0.gameId : nil }, metadata: context.gameMetadata) { $0.companies }
        case "platform_expert":
            return maxLabelFrequency(gameIds: context.logs.compactMap { $0.rating != nil ? $0.gameId : nil }, metadata: context.gameMetadata) { $0.platforms }
        case "genre_pulse":
            return maxLabelFrequency(gameIds: context.logs.compactMap { $0.rating != nil ? $0.gameId : nil }, metadata: context.gameMetadata) { $0.genres }
        case "the_big_n_approves":
            return context.logs.compactMap { $0.rating != nil ? context.gameMetadata[$0.gameId] : nil }.filter { $0.isNintendo }.count
        case "era_sampler":
            return Set(context.logs.compactMap { $0.rating != nil ? context.gameMetadata[$0.gameId]?.decadeBucket : nil }).count
        case "rgb_maniac":
            return Set(context.logs.compactMap { log -> Int? in
                guard let rating = log.rating else { return nil }
                return min(10, max(0, Int(floor(rating))))
            }).count
        case "gotta_rate_em_all":
            return context.logs.filter { $0.rating != nil }.count
        case "baby_critic":
            return context.logs.filter { ($0.review?.isEmpty == false) }.count
        case "now_you_re_talkin":
            return context.logs.filter { ($0.review?.isEmpty == false) }.count
        case "review_archive":
            return context.logs.filter { ($0.review?.isEmpty == false) }.count
        case "no_limits":
            return Set(context.logs.compactMap { ($0.review?.isEmpty == false) ? context.gameMetadata[$0.gameId] : nil }.flatMap { $0.playStationGenerations() }).count
        case "platform_professional":
            return maxLabelFrequency(gameIds: context.logs.compactMap { ($0.review?.isEmpty == false) ? $0.gameId : nil }, metadata: context.gameMetadata) { $0.platforms }
        case "genre_genius":
            return maxLabelFrequency(gameIds: context.logs.compactMap { ($0.review?.isEmpty == false) ? $0.gameId : nil }, metadata: context.gameMetadata) { $0.genres }
        case "mature_mind":
            return context.logs.compactMap { ($0.review?.isEmpty == false) ? context.gameMetadata[$0.gameId] : nil }.filter { $0.isRetro }.count
        case "rhythm_writer":
            return longestStreak(dayKeys: context.logs.compactMap { ($0.review?.isEmpty == false) ? dayKey(for: $0.updatedAt) : nil })
        case "long_winded":
            return context.logs.filter { ($0.review?.count ?? 0) > 650 }.count
        case "canon_fodder":
            return maxLabelFrequency(gameIds: context.logs.compactMap { ($0.review?.isEmpty == false) ? $0.gameId : nil }, metadata: context.gameMetadata) { $0.franchiseKeys }
        case "save_continue", "wishlist_wizard", "the_collector":
            return context.savedGames.count
        case "studio_watchlist":
            return maxLabelFrequency(gameIds: context.savedGames.map { $0.gameId }, metadata: context.gameMetadata) { $0.companies }
        case "platform_peruser":
            return maxLabelFrequency(gameIds: context.savedGames.map { $0.gameId }, metadata: context.gameMetadata) { $0.platforms }
        case "genre_geek":
            return maxLabelFrequency(gameIds: context.savedGames.map { $0.gameId }, metadata: context.gameMetadata) { $0.genres }
        case "alpha_zeta":
            return Set(context.savedGames.compactMap { context.gameMetadata[$0.gameId]?.firstLetter ?? firstAlphaCharacter(in: $0.name) }).count
        case "pre_order_bonus":
            return context.savedGames.compactMap { context.gameMetadata[$0.gameId] }.filter { $0.isUpcoming }.count
        case "preserve_the_classics":
            return context.savedGames.compactMap { context.gameMetadata[$0.gameId] }.filter { $0.isRetro }.count
        case "procrastination":
            return context.lists.contains(where: { snapshot in
                let title = snapshot.list.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return (title == "backlog" || title == "back log") && !snapshot.items.isEmpty
            }) ? 1 : 0
        case "the_first_of_many":
            return context.lists.count
        case "list_habit", "the_connoisseur":
            return context.lists.reduce(0) { $0 + $1.items.count }
        case "show_off":
            return context.lists.filter { $0.list.isPublic && $0.list.type == .ranked }.count
        case "psn":
            return context.lists.filter { snapshot in
                snapshot.items.compactMap { context.gameMetadata[$0.gameId] }.filter { $0.isSony }.count >= 5
            }.count
        case "the_curator":
            return context.lists.map { $0.items.count }.max() ?? 0
        case "public_opinion":
            let publicRegular = context.lists.filter { $0.list.isPublic && $0.list.type == .regular }.count
            let publicRanked = context.lists.filter { $0.list.isPublic && $0.list.type == .ranked }.count
            let publicTiered = context.lists.filter { $0.list.isPublic && $0.list.type == .tiered }.count
            return min(publicRegular, publicRanked, publicTiered)
        case "tier_architect":
            return context.lists.filter { $0.list.isPublic && $0.list.type == .tiered }.count
        case "keepsake":
            let privateRegular = context.lists.filter { !$0.list.isPublic && $0.list.type == .regular }.count
            let privateRanked = context.lists.filter { !$0.list.isPublic && $0.list.type == .ranked }.count
            let privateTiered = context.lists.filter { !$0.list.isPublic && $0.list.type == .tiered }.count
            return min(privateRegular, privateRanked, privateTiered)
        case "a_bit_much":
            return context.lists.filter { $0.list.type == .ranked }.map { $0.items.count }.max() ?? 0
        case "first_search":
            return context.metrics.searchActionsCount
        case "participation_trophy":
            return context.likedLogIds.count
        case "housemaid":
            return context.flaggedCount
        case "set_in_your_ways":
            return maxLabelFrequency(gameIds: context.savedGames.map { $0.gameId }, metadata: context.gameMetadata) { $0.platforms }
        case "superfan":
            return maxLabelFrequency(gameIds: Array(context.viewedGameIds), metadata: context.gameMetadata) { $0.companies }
        case "whats_your_kd":
            return context.logs.compactMap { $0.rating != nil ? context.gameMetadata[$0.gameId] : nil }.filter { $0.isFPS }.count
        case "8_bit_tourist":
            return context.savedGames.compactMap { context.gameMetadata[$0.gameId] }.filter { $0.releaseYear.map { (1980...1989).contains($0) } ?? false }.count
        case "collection_habit":
            return context.metrics.collectionHabitCompletedSessionsCount
        case "library_rhythm":
            return longestStreak(dayKeys: context.savedGames.compactMap { $0.addedAt.map(dayKey(for:)) })
        case "gamerlnd_citizen":
            return completedQuestCount
        default:
            return metricValue(for: definition.progressMetric, metrics: context.metrics)
        }
    }

    private func metricValue(for metric: String, metrics: UserGamificationMetrics) -> Int {
        switch metric {
        case "rated_games_count":
            return metrics.ratedGamesCount
        case "ratings_in_day":
            return metrics.ratingsByDay.values.max() ?? 0
        case "reviewed_games_count":
            return metrics.reviewedGamesCount
        case "log_actions_count":
            return metrics.logActionsCount
        case "search_actions_count":
            return metrics.searchActionsCount
        case "saved_games_count":
            return metrics.savedGamesCount
        case "list_items_added_count":
            return metrics.listItemsAddedCount
        case "lists_created_count":
            return metrics.listsCreatedCount
        case "likes_given_count":
            return metrics.likesGivenCount
        case "comments_written_count":
            return metrics.commentsWrittenCount
        case "follows_count":
            return metrics.followsCount
        case "flagged_games_count":
            return metrics.flaggedGamesCount
        case "view_actions_count":
            return metrics.viewActionsCount
        case "perfect_ten_ratings_count":
            return metrics.perfectTenRatingsCount
        case "double_take_ratings_count":
            return metrics.doubleTakeRatingsCount
        case "low_hp_ratings_count":
            return metrics.lowHPRatingsCount
        case "rabid_rater_best_count":
            return metrics.rabidRaterBestCount
        case "retro_reviews_count":
            return metrics.retroReviewsCount
        case "retro_saved_games_count":
            return metrics.retroSavedGamesCount
        case "completed_quests_count":
            return metrics.completedQuestsCount
        default:
            return 0
        }
    }

    private func maxLabelFrequency(gameIds: [Int], metadata: [Int: QuestGameMetadata], labels: (QuestGameMetadata) -> Set<String>) -> Int {
        var counts: [String: Int] = [:]
        for gameId in gameIds {
            guard let meta = metadata[gameId] else { continue }
            for label in labels(meta) {
                counts[label, default: 0] += 1
            }
        }
        return counts.values.max() ?? 0
    }

    private func longestStreak(dayKeys: [String]) -> Int {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = Set(dayKeys.compactMap { formatter.date(from: $0) }).sorted()
        guard !dates.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for pair in zip(dates, dates.dropFirst()) {
            let days = Calendar(identifier: .gregorian).dateComponents([.day], from: pair.0, to: pair.1).day ?? 0
            if days == 1 {
                current += 1
                best = max(best, current)
            } else if days > 1 {
                current = 1
            }
        }
        return best
    }

    private func firstAlphaCharacter(in value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        let upper = String(first).uppercased()
        return upper.range(of: "^[A-Z]$", options: .regularExpression) != nil ? upper : nil
    }

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func revealAdjacentHints(
        definitions: [AchievementDefinition],
        existingStates: [String: UserAchievementState],
        completedCoords: Set<String>,
        userId: String
    ) {
        let refs = definitions.compactMap { definition -> (DocumentReference, [String: Any])? in
            guard let row = definition.tileRow, let col = definition.tileColumn else { return nil }
            let currentState = existingStates[definition.id]?.state ?? defaultTileState(for: definition)
            guard currentState != .completed else { return nil }
            let neighbors = ["\(row-1):\(col)", "\(row+1):\(col)", "\(row):\(col-1)", "\(row):\(col+1)"]
            guard neighbors.contains(where: { completedCoords.contains($0) }) else { return nil }
            let ref = db.collection("user_achievements").document("\(userId)_\(definition.id)")
            let payload: [String: Any] = [
                "user_id": userId,
                "achievement_id": definition.id,
                "state": AchievementTileState.hinted.rawValue,
                "progress_current": existingStates[definition.id]?.progressCurrent ?? 0,
                "progress_target": definition.progressTarget,
                "revealed_at": Timestamp(date: Date()),
                "claimed": existingStates[definition.id]?.claimed ?? false,
                "xp_granted": existingStates[definition.id]?.xpGranted ?? 0,
                "unlockables_granted": existingStates[definition.id]?.unlockablesGranted ?? []
            ]
            return (ref, payload)
        }

        refs.forEach { ref, payload in
            ref.setData(payload, merge: true)
        }
    }

    private func defaultTileState(for definition: AchievementDefinition) -> AchievementTileState {
        _ = definition
        return .hidden
    }

    private func boardSort(lhs: AchievementDefinition, rhs: AchievementDefinition) -> Bool {
        let l = (lhs.tileRow ?? Int.max, lhs.tileColumn ?? Int.max, lhs.code)
        let r = (rhs.tileRow ?? Int.max, rhs.tileColumn ?? Int.max, rhs.code)
        return l < r
    }

    func claimQuestXP(
        userId: String,
        achievementId: String,
        completion: ((Int) -> Void)? = nil
    ) {
        let stateRef = db.collection("user_achievements").document("\(userId)_\(achievementId)")
        fetchAchievementCatalog { definitions in
            guard let definition = definitions.first(where: { $0.id == achievementId }) else {
                DispatchQueue.main.async { completion?(0) }
                return
            }

            stateRef.getDocument { snapshot, _ in
                guard
                    let data = snapshot?.data(),
                    let completedAt = data["completed_at"] as? Timestamp,
                    completedAt.dateValue() <= Date()
                else {
                    DispatchQueue.main.async { completion?(0) }
                    return
                }

                let alreadyClaimed = data["claimed"] as? Bool ?? false
                guard !alreadyClaimed, definition.xpReward > 0 else {
                    DispatchQueue.main.async { completion?(0) }
                    return
                }

                stateRef.setData([
                    "claimed": true,
                    "xp_granted": definition.xpReward,
                    "unlockables_granted": definition.unlockableRewardIds
                ], merge: true)

                RewardService.shared.grantAchievementXP(
                    userId: userId,
                    amount: definition.xpReward,
                    reason: "achievement_complete",
                    sourceId: definition.id
                ) { granted in
                    NotificationCenter.default.post(
                        name: .gamificationUpdated,
                        object: nil,
                        userInfo: ["user_id": userId]
                    )

                    DispatchQueue.main.async {
                        completion?(granted)
                    }
                }
            }
        }
    }
}

final class ObjectiveService {
    static let shared = ObjectiveService()
    private let db = Firestore.firestore()
    private var observers: [NSObjectProtocol] = []
    private init() {
        installMetricObservers()
    }

    private static let easternTimeZone = TimeZone(identifier: "America/New_York") ?? .current

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func fetchObjectiveTemplates(window: ObjectiveWindow, completion: @escaping ([ObjectiveTemplate]) -> Void) {
        let seeds = window == .daily ? GamificationSeedCatalog.dailyTemplates : GamificationSeedCatalog.weeklyTemplates
        completion(seeds.map { ObjectiveTemplate(id: ($0["id"] as? String) ?? UUID().uuidString, data: $0) })
    }

    func fetchDailyObjectives(userId: String, dateKey: String, completion: @escaping (ObjectiveAssignment?) -> Void) {
        let docId = "\(userId)_\(dateKey)"
        let ref = db.collection("daily_objectives").document(docId)
        ref.getDocument(source: .cache) { snap, _ in
            if let data = snap?.data() {
                completion(ObjectiveAssignment(id: docId, window: .daily, periodKey: dateKey, data: data))
                return
            }
            ref.getDocument { liveSnap, _ in
                guard let data = liveSnap?.data() else {
                    completion(nil)
                    return
                }
                completion(ObjectiveAssignment(id: docId, window: .daily, periodKey: dateKey, data: data))
            }
        }
    }

    func fetchWeeklyObjectives(userId: String, weekKey: String, completion: @escaping (ObjectiveAssignment?) -> Void) {
        let docId = "\(userId)_\(weekKey)"
        let ref = db.collection("weekly_objectives").document(docId)
        ref.getDocument(source: .cache) { snap, _ in
            if let data = snap?.data() {
                completion(ObjectiveAssignment(id: docId, window: .weekly, periodKey: weekKey, data: data))
                return
            }
            ref.getDocument { liveSnap, _ in
                guard let data = liveSnap?.data() else {
                    completion(nil)
                    return
                }
                completion(ObjectiveAssignment(id: docId, window: .weekly, periodKey: weekKey, data: data))
            }
        }
    }

    func quickAssignment(
        userId: String,
        window: ObjectiveWindow,
        date: Date = Date(),
        userLevel: Int
    ) -> ObjectiveAssignment {
        let periodKey = window == .daily ? Self.dayKey(for: date) : Self.weekKey(for: date)
        let templates = (window == .daily ? GamificationSeedCatalog.dailyTemplates : GamificationSeedCatalog.weeklyTemplates)
            .map { ObjectiveTemplate(id: ($0["id"] as? String) ?? UUID().uuidString, data: $0) }
        let selected = selectTemplates(from: templates, count: 1, userLevel: max(1, userLevel), userId: userId, periodKey: periodKey)
        let payload = assignmentPayload(userId: userId, periodKey: periodKey, window: window, templates: selected, now: date)
        return ObjectiveAssignment(id: "\(userId)_\(periodKey)", window: window, periodKey: periodKey, data: payload)
    }

    func ensureDailyObjectives(userId: String, date: Date = Date(), completion: @escaping (Result<ObjectiveAssignment, Error>) -> Void) {
        let dateKey = Self.dayKey(for: date)
        let docId = "\(userId)_\(dateKey)"
        let ref = db.collection("daily_objectives").document(docId)
        ref.getDocument { snap, err in
            if err != nil {
                self.buildFallbackAssignment(userId: userId, window: .daily, periodKey: dateKey, now: date) { assignment in
                    completion(.success(assignment))
                }
                return
            }
            if let data = snap?.data(), self.isAssignmentCurrent(data: data, window: .daily, expectedPeriodKey: dateKey, now: date) {
                completion(.success(ObjectiveAssignment(id: docId, window: .daily, periodKey: dateKey, data: data)))
                return
            }

            self.fetchUserLevel(userId: userId) { level in
                self.fetchObjectiveTemplates(window: .daily) { templates in
                    let selected = self.selectTemplates(from: templates, count: 1, userLevel: level, userId: userId, periodKey: dateKey)
                    let payload = self.assignmentPayload(userId: userId, periodKey: dateKey, window: .daily, templates: selected, now: date)
                    ref.setData(payload, merge: false) { writeErr in
                        if writeErr != nil {
                            let assignment = ObjectiveAssignment(id: docId, window: .daily, periodKey: dateKey, data: payload)
                            completion(.success(assignment))
                        } else {
                            let assignment = ObjectiveAssignment(id: docId, window: .daily, periodKey: dateKey, data: payload)
                            self.refreshAssignmentsFromMetrics(userId: userId, date: date)
                            completion(.success(assignment))
                        }
                    }
                }
            }
        }
    }

    func resetDailyObjectives(userId: String, date: Date = Date(), completion: @escaping (Result<ObjectiveAssignment, Error>) -> Void) {
        let dateKey = Self.dayKey(for: date)
        let docId = "\(userId)_\(dateKey)"
        let ref = db.collection("daily_objectives").document(docId)
        fetchUserLevel(userId: userId) { level in
            self.fetchObjectiveTemplates(window: .daily) { templates in
                let selected = self.selectTemplates(from: templates, count: 1, userLevel: level, userId: userId, periodKey: dateKey)
                let payload = self.assignmentPayload(userId: userId, periodKey: dateKey, window: .daily, templates: selected, now: date)
                ref.setData(payload, merge: false) { writeErr in
                    if let writeErr {
                        completion(.failure(writeErr))
                    } else {
                        let assignment = ObjectiveAssignment(id: docId, window: .daily, periodKey: dateKey, data: payload)
                        self.refreshAssignmentsFromMetrics(userId: userId, date: date)
                        completion(.success(assignment))
                    }
                }
            }
        }
    }

    func ensureWeeklyObjectives(userId: String, date: Date = Date(), completion: @escaping (Result<ObjectiveAssignment, Error>) -> Void) {
        let weekKey = Self.weekKey(for: date)
        let docId = "\(userId)_\(weekKey)"
        let ref = db.collection("weekly_objectives").document(docId)
        ref.getDocument { snap, err in
            if err != nil {
                self.buildFallbackAssignment(userId: userId, window: .weekly, periodKey: weekKey, now: date) { assignment in
                    completion(.success(assignment))
                }
                return
            }
            if let data = snap?.data(), self.isAssignmentCurrent(data: data, window: .weekly, expectedPeriodKey: weekKey, now: date) {
                completion(.success(ObjectiveAssignment(id: docId, window: .weekly, periodKey: weekKey, data: data)))
                return
            }

            self.fetchUserLevel(userId: userId) { level in
                self.fetchObjectiveTemplates(window: .weekly) { templates in
                    let selected = self.selectTemplates(from: templates, count: 1, userLevel: level, userId: userId, periodKey: weekKey)
                    let payload = self.assignmentPayload(userId: userId, periodKey: weekKey, window: .weekly, templates: selected, now: date)
                    ref.setData(payload, merge: false) { writeErr in
                        if writeErr != nil {
                            let assignment = ObjectiveAssignment(id: docId, window: .weekly, periodKey: weekKey, data: payload)
                            completion(.success(assignment))
                        } else {
                            let assignment = ObjectiveAssignment(id: docId, window: .weekly, periodKey: weekKey, data: payload)
                            self.refreshAssignmentsFromMetrics(userId: userId, date: date)
                            completion(.success(assignment))
                        }
                    }
                }
            }
        }
    }

    func resetWeeklyObjectives(userId: String, date: Date = Date(), completion: @escaping (Result<ObjectiveAssignment, Error>) -> Void) {
        let weekKey = Self.weekKey(for: date)
        let docId = "\(userId)_\(weekKey)"
        let ref = db.collection("weekly_objectives").document(docId)
        fetchUserLevel(userId: userId) { level in
            self.fetchObjectiveTemplates(window: .weekly) { templates in
                let selected = self.selectTemplates(from: templates, count: 1, userLevel: level, userId: userId, periodKey: weekKey)
                let payload = self.assignmentPayload(userId: userId, periodKey: weekKey, window: .weekly, templates: selected, now: date)
                ref.setData(payload, merge: false) { writeErr in
                    if let writeErr {
                        completion(.failure(writeErr))
                    } else {
                        let assignment = ObjectiveAssignment(id: docId, window: .weekly, periodKey: weekKey, data: payload)
                        self.refreshAssignmentsFromMetrics(userId: userId, date: date)
                        completion(.success(assignment))
                    }
                }
            }
        }
    }

    private func buildFallbackAssignment(
        userId: String,
        window: ObjectiveWindow,
        periodKey: String,
        now: Date,
        completion: @escaping (ObjectiveAssignment) -> Void
    ) {
        fetchUserLevel(userId: userId) { level in
            self.fetchObjectiveTemplates(window: window) { templates in
                let selected = self.selectTemplates(from: templates, count: 1, userLevel: level, userId: userId, periodKey: periodKey)
                let payload = self.assignmentPayload(userId: userId, periodKey: periodKey, window: window, templates: selected, now: now)
                let assignment = ObjectiveAssignment(id: "\(userId)_\(periodKey)", window: window, periodKey: periodKey, data: payload)
                completion(assignment)
            }
        }
    }

    private func selectTemplates(
        from templates: [ObjectiveTemplate],
        count: Int,
        userLevel: Int,
        userId: String,
        periodKey: String
    ) -> [ObjectiveTemplate] {
        let sorted = templates
            .filter { template in
                let glMin = (template.constraints["gl_min"] as? Int) ?? 1
                let glMax = (template.constraints["gl_max"] as? Int) ?? 999
                return userLevel >= glMin && userLevel <= glMax
            }
            .sorted { $0.code < $1.code }
        guard !sorted.isEmpty else { return [] }

        let targetCount = min(count, sorted.count)
        guard targetCount > 0 else { return [] }

        let seedSource = "\(userId)|\(periodKey)"
        let seed = seedSource.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31) &+ Int(scalar.value)
        }
        let start = abs(seed) % sorted.count
        var selected: [ObjectiveTemplate] = []
        var seen = Set<String>()
        var cursor = start
        var attempts = 0
        let maxAttempts = sorted.count * 2

        while selected.count < targetCount && attempts < maxAttempts {
            guard sorted.indices.contains(cursor) else { break }
            let candidate = sorted[cursor]
            if !seen.contains(candidate.id) {
                selected.append(candidate)
                seen.insert(candidate.id)
            }
            cursor = (cursor + 1) % sorted.count
            attempts += 1
        }

        return selected
    }

    func handleEvent(_ event: RewardService.GamificationEvent) {
        ensureDailyObjectives(userId: event.userId, date: event.occurredAt) { result in
            if case .success(let assignment) = result {
                self.progressAssignment(assignment, for: event)
            }
        }
        ensureWeeklyObjectives(userId: event.userId, date: event.occurredAt) { result in
            if case .success(let assignment) = result {
                self.progressAssignment(assignment, for: event)
            }
        }
    }

    private func assignmentPayload(
        userId: String,
        periodKey: String,
        window: ObjectiveWindow,
        templates: [ObjectiveTemplate],
        now: Date
    ) -> [String: Any] {
        let nowTimestamp = Timestamp(date: now)
        let expiresAt = Timestamp(date: nextResetDate(for: window, after: now))
        let objectivePayloads: [[String: Any]] = templates.map {
            [
                "template_id": $0.id,
                "code": $0.code,
                "title": $0.title,
                "progress": 0,
                "target": $0.targetValue,
                "completed": false,
                "claimed": false,
                "xp_reward": $0.xpReward
            ]
        }
        return [
            "user_id": userId,
            window == .daily ? "date_key" : "week_key": periodKey,
            "objectives": objectivePayloads,
            "all_completed_bonus_xp": window == .daily ? 50 : 200,
            "all_completed_bonus_granted": false,
            "created_at": nowTimestamp,
            "expires_at": expiresAt
        ]
    }

    private func isAssignmentCurrent(
        data: [String: Any],
        window: ObjectiveWindow,
        expectedPeriodKey: String,
        now: Date
    ) -> Bool {
        let storedKey = (data[window == .daily ? "date_key" : "week_key"] as? String) ?? ""
        guard storedKey == expectedPeriodKey else { return false }

        let objectives = data["objectives"] as? [[String: Any]] ?? []
        guard !objectives.isEmpty else { return false }

        if let expiresAt = data["expires_at"] as? Timestamp, expiresAt.dateValue() <= now {
            return false
        }

        return true
    }

    private func progressAssignment(_ assignment: ObjectiveAssignment, for event: RewardService.GamificationEvent) {
        let collection = assignment.window == .daily ? "daily_objectives" : "weekly_objectives"
        let ref = db.collection(collection).document(assignment.id)

        db.runTransaction({ transaction, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard var data = snap.data() else { return nil }
            var objectives = data["objectives"] as? [[String: Any]] ?? []
            var completedCodes: [String] = []

            for idx in objectives.indices {
                var item = objectives[idx]
                let code = (item["code"] as? String) ?? ""
                let target = (item["target"] as? Int) ?? (item["target"] as? NSNumber)?.intValue ?? 1
                var progress = (item["progress"] as? Int) ?? (item["progress"] as? NSNumber)?.intValue ?? 0
                let completed = item["completed"] as? Bool ?? false
                if completed { continue }

                let increment = self.objectiveIncrement(code: code, event: event)
                guard increment > 0 else { continue }

                progress = min(target, progress + increment)
                item["progress"] = progress
                if progress >= target {
                    item["completed"] = true
                    completedCodes.append(code)
                }
                objectives[idx] = item
            }

            data["objectives"] = objectives
            transaction.setData(data, forDocument: ref, merge: false)
            return completedCodes as NSArray
        }) { result, _ in
            guard
                let completedCodes = result as? [String],
                !completedCodes.isEmpty
            else { return }
            let resolvedUserId = assignment.userId.isEmpty ? (Auth.auth().currentUser?.uid ?? "") : assignment.userId

            NotificationCenter.default.post(
                name: .challengesUpdated,
                object: nil,
                userInfo: [
                    "user_id": resolvedUserId,
                    "window": assignment.window.rawValue,
                    "count": completedCodes.count
                ]
            )
        }
    }

    func refreshAssignmentsFromMetrics(userId: String, date: Date = Date(), metrics: UserGamificationMetrics? = nil) {
        if let metrics {
            applyDerivedProgress(userId: userId, window: .daily, periodKey: Self.dayKey(for: date), metrics: metrics, date: date)
            applyDerivedProgress(userId: userId, window: .weekly, periodKey: Self.weekKey(for: date), metrics: metrics, date: date)
            return
        }
        fetchMetrics(userId: userId) { metrics in
            guard let metrics else { return }
            self.applyDerivedProgress(userId: userId, window: .daily, periodKey: Self.dayKey(for: date), metrics: metrics, date: date)
            self.applyDerivedProgress(userId: userId, window: .weekly, periodKey: Self.weekKey(for: date), metrics: metrics, date: date)
        }
    }

    func claimObjectiveXP(assignment: ObjectiveAssignment, objectiveId: String, completion: ((Int) -> Void)? = nil) {
        let collection = assignment.window == .daily ? "daily_objectives" : "weekly_objectives"
        let ref = db.collection(collection).document(assignment.id)

        db.runTransaction({ transaction, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard var data = snap.data() else { return nil }
            var objectives = data["objectives"] as? [[String: Any]] ?? []
            guard let idx = objectives.indices.first(where: {
                let item = objectives[$0]
                let code = (item["code"] as? String) ?? ""
                return "\(assignment.id)_\($0)" == objectiveId || code == objectiveId
            }) else { return nil }

            var item = objectives[idx]
            let completed = item["completed"] as? Bool ?? false
            let claimed = item["claimed"] as? Bool ?? false
            let code = (item["code"] as? String) ?? ""
            let xp = (item["xp_reward"] as? Int) ?? (item["xp_reward"] as? NSNumber)?.intValue ?? 0
            guard completed, !claimed, xp > 0 else { return nil }

            item["claimed"] = true
            objectives[idx] = item
            data["objectives"] = objectives
            transaction.setData(data, forDocument: ref, merge: false)
            return ["xp": xp, "code": code] as NSDictionary
        }) { result, _ in
            guard
                let payload = result as? NSDictionary,
                let xp = payload["xp"] as? Int,
                let code = payload["code"] as? String
            else {
                completion?(0)
                return
            }
            let resolvedUserId = assignment.userId.isEmpty ? (Auth.auth().currentUser?.uid ?? "") : assignment.userId
            RewardService.shared.grantObjectiveXP(
                userId: resolvedUserId,
                amount: xp,
                reason: "\(assignment.window.rawValue)_objective_complete",
                sourceId: "\(assignment.id)_\(code)",
                completion: completion
            )
        }
    }

    private func objectiveIncrement(code: String, event: RewardService.GamificationEvent) -> Int {
        switch code {
        case "daily_rate_one", "daily_rate_three", "daily_rate_five",
             "weekly_rate_ten", "weekly_rate_fifteen", "weekly_rate_twenty_five":
            return event.kind == .rateGame ? 1 : 0
        case "daily_review_one", "daily_review_two",
             "weekly_review_three", "weekly_review_five":
            if event.kind == .writeReview { return 1 }
            return 0
        case "daily_save_one", "daily_save_three", "daily_save_five",
             "weekly_save_five_beginner", "weekly_save_ten":
            return event.kind == .saveGame ? 1 : 0
        case "daily_list_one", "daily_list_three", "daily_list_five",
             "weekly_list_five", "weekly_list_ten":
            return event.kind == .addToList ? 1 : 0
        case "daily_double_log":
            switch event.kind {
            case .rateGame, .writeReview, .saveGame, .addToList:
                return 1
            default:
                return 0
            }
        case "weekly_create_one_list", "weekly_create_two_lists":
            return event.kind == .createList ? 1 : 0
        case "daily_quest_chain", "weekly_daily_streak", "weekly_four_day_presence", "weekly_category_spread":
            return 0
        default:
            return 0
        }
    }

    private func fetchUserLevel(userId: String, completion: @escaping (Int) -> Void) {
        db.collection("user_stats").document(userId).getDocument { snap, _ in
            let level = (snap?.data()?["reward_level"] as? Int)
                ?? (snap?.data()?["reward_level"] as? NSNumber)?.intValue
                ?? 1
            completion(max(1, level))
        }
    }

    private func fetchMetrics(userId: String, completion: @escaping (UserGamificationMetrics?) -> Void) {
        db.collection("user_metrics").document(userId).getDocument { snap, _ in
            guard let data = snap?.data() else {
                completion(UserGamificationMetrics(userId: userId, data: [:]))
                return
            }
            completion(UserGamificationMetrics(userId: userId, data: data))
        }
    }

    private func applyDerivedProgress(
        userId: String,
        window: ObjectiveWindow,
        periodKey: String,
        metrics: UserGamificationMetrics,
        date: Date
    ) {
        let ref = db.collection(window == .daily ? "daily_objectives" : "weekly_objectives").document("\(userId)_\(periodKey)")
        db.runTransaction { transaction, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard var data = snap.data() else { return nil }
            var objectives = data["objectives"] as? [[String: Any]] ?? []
            var didChange = false
            for idx in objectives.indices {
                var item = objectives[idx]
                let code = (item["code"] as? String) ?? ""
                let target = (item["target"] as? Int) ?? (item["target"] as? NSNumber)?.intValue ?? 1
                let derived = min(target, self.derivedProgress(for: code, metrics: metrics, date: date))
                let existing = (item["progress"] as? Int) ?? (item["progress"] as? NSNumber)?.intValue ?? 0
                if derived != existing {
                    item["progress"] = derived
                    didChange = true
                }
                let shouldComplete = derived >= target
                let completed = item["completed"] as? Bool ?? false
                if shouldComplete != completed {
                    item["completed"] = shouldComplete
                    didChange = true
                }
                objectives[idx] = item
            }
            guard didChange else { return nil }
            data["objectives"] = objectives
            transaction.setData(data, forDocument: ref, merge: false)
            return true as NSNumber
        } completion: { _, _ in }
    }

    private func derivedProgress(for code: String, metrics: UserGamificationMetrics, date: Date) -> Int {
        let dayKey = Self.dayKey(for: date)
        let weekKey = Self.weekKey(for: date)
        switch code {
        case "daily_rate_one", "daily_rate_three", "daily_rate_five":
            return metrics.ratingsByDay[dayKey] ?? 0
        case "daily_save_one", "daily_save_three", "daily_save_five":
            return metrics.savesByDay[dayKey] ?? 0
        case "daily_list_one", "daily_list_three", "daily_list_five":
            return metrics.listAddsByDay[dayKey] ?? 0
        case "daily_review_one", "daily_review_two":
            return metrics.reviewsByDay[dayKey] ?? 0
        case "daily_double_log":
            return metrics.loggingActionsByDay[dayKey] ?? 0
        case "daily_quest_chain":
            let quests = metrics.questCompletionsByDay[dayKey] ?? 0
            let objectives = metrics.objectiveCompletionsByDay[dayKey] ?? 0
            return (quests > 0 && objectives > 0) ? 1 : 0

        case "weekly_rate_ten", "weekly_rate_fifteen", "weekly_rate_twenty_five":
            return sumValues(in: metrics.ratingsByDay, matchingWeekKey: weekKey)
        case "weekly_save_five_beginner", "weekly_save_ten":
            return sumValues(in: metrics.savesByDay, matchingWeekKey: weekKey)
        case "weekly_list_five", "weekly_list_ten":
            return sumValues(in: metrics.listAddsByDay, matchingWeekKey: weekKey)
        case "weekly_review_three", "weekly_review_five":
            return sumValues(in: metrics.reviewsByDay, matchingWeekKey: weekKey)
        case "weekly_create_one_list", "weekly_create_two_lists":
            return sumValues(in: metrics.listCreationsByDay, matchingWeekKey: weekKey)
        case "weekly_daily_streak":
            return sumValues(in: metrics.dailyObjectiveCompletionsByDay, matchingWeekKey: weekKey)
        case "weekly_four_day_presence":
            return distinctCompletedDays(in: metrics.objectiveCompletionsByDay, matchingWeekKey: weekKey)
        case "weekly_category_spread":
            return distinctCategories(in: metrics.actionCategoriesByDay, matchingWeekKey: weekKey)
        default:
            return 0
        }
    }

    private func sumValues(in values: [String: Int], matchingWeekKey weekKey: String) -> Int {
        values.reduce(0) { partial, entry in
            guard let date = Self.date(fromDayKey: entry.key), Self.weekKey(for: date) == weekKey else { return partial }
            return partial + entry.value
        }
    }

    private func distinctCompletedDays(in values: [String: Int], matchingWeekKey weekKey: String) -> Int {
        values.keys.filter { key in
            guard let date = Self.date(fromDayKey: key), Self.weekKey(for: date) == weekKey else { return false }
            return (values[key] ?? 0) > 0
        }.count
    }

    private func distinctCategories(in values: [String: [String]], matchingWeekKey weekKey: String) -> Int {
        var categories = Set<String>()
        for (key, dayCategories) in values {
            guard let date = Self.date(fromDayKey: key), Self.weekKey(for: date) == weekKey else { continue }
            dayCategories.forEach { categories.insert($0) }
        }
        return categories.count
    }

    private func installMetricObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .questCompleted, object: nil, queue: .main) { note in
                guard let userId = note.userInfo?["user_id"] as? String else { return }
                self.recordCompletionMetric(userId: userId, field: "quest_completions_by_day", count: 1)
                self.incrementScalarMetric(userId: userId, field: "completed_quests_count", amount: 1)
            }
        )
        observers.append(
            center.addObserver(forName: .challengesUpdated, object: nil, queue: .main) { note in
                guard let userId = note.userInfo?["user_id"] as? String else { return }
                let count = note.userInfo?["count"] as? Int ?? 1
                let window = note.userInfo?["window"] as? String ?? ObjectiveWindow.daily.rawValue
                self.recordCompletionMetric(userId: userId, field: "objective_completions_by_day", count: count)
                if window == ObjectiveWindow.daily.rawValue {
                    self.recordCompletionMetric(userId: userId, field: "daily_objective_completions_by_day", count: count)
                }
            }
        )
    }

    private func recordCompletionMetric(userId: String, field: String, count: Int) {
        let dayKey = Self.dayKey(for: Date())
        let ref = db.collection("user_metrics").document(userId)
        db.runTransaction { transaction, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            var data = snap.data() ?? [:]
            var map = (data[field] as? [String: Int]) ?? [:]
            map[dayKey] = (map[dayKey] ?? 0) + count
            data[field] = map
            transaction.setData(data, forDocument: ref, merge: true)
            return true as NSNumber
        } completion: { _, _ in
            self.refreshAssignmentsFromMetrics(userId: userId, date: Date())
        }
    }

    private func incrementScalarMetric(userId: String, field: String, amount: Int) {
        guard amount != 0 else { return }
        let ref = db.collection("user_metrics").document(userId)
        db.runTransaction { transaction, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            var data = snap.data() ?? [:]
            let current = (data[field] as? Int) ?? (data[field] as? NSNumber)?.intValue ?? 0
            data[field] = max(0, current + amount)
            transaction.setData(data, forDocument: ref, merge: true)
            return true as NSNumber
        } completion: { _, _ in }
    }

    private static func date(fromDayKey key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func weekKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = easternTimeZone
        // Weekly challenges roll over at the end of Sunday night, so the
        // effective new week starts on Monday at 12:00 AM ET.
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 1
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    private func nextResetDate(for window: ObjectiveWindow, after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.easternTimeZone
        switch window {
        case .daily:
            let startOfDay = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        case .weekly:
            let startOfDay = calendar.startOfDay(for: date)
            // Reset at the start of Monday ET, which is equivalent to Sunday
            // night at 11:59 PM ET ending.
            let weekday = calendar.component(.weekday, from: startOfDay) // 1 = Sun, 2 = Mon
            let daysUntilMonday = (9 - weekday) % 7
            if daysUntilMonday == 0 {
                return calendar.date(byAdding: .day, value: 7, to: startOfDay) ?? date
            }
            return calendar.date(byAdding: .day, value: daysUntilMonday, to: startOfDay) ?? date
        }
    }

    static func nextDailyResetText() -> String {
        "Resets daily at 12:00 AM ET"
    }

    static func nextWeeklyResetText() -> String {
        "Resets Sunday nights at 11:59 PM ET"
    }
}

final class SecretUnlockService {
    static let shared = SecretUnlockService()
    private let db = Firestore.firestore()
    private let secretsEnabled = false
    private init() {}

    private struct SecretTierListSnapshot {
        let list: UserList
        let items: [UserListItem]
    }

    private struct TierListSecretInput {
        let isPublic: Bool
        let tierLabels: [String]
        let tierColors: [String]
        let itemTierLabels: [String]
    }

    private let defaultTierPalette = ["#e74c3c", "#e67e22", "#f1c40f", "#2ecc71", "#3498db"]

    private func seededDefinition(code: String) -> SecretUnlockDefinition? {
        guard let seed = GamificationSeedCatalog.secretUnlocks.first(where: {
            (($0["code"] as? String) ?? "").lowercased() == code.lowercased()
        }) else { return nil }
        let id = (seed["id"] as? String) ?? code
        return SecretUnlockDefinition(id: id, data: seed)
    }

    func triggerNextTestSecret(userId: String) {
        guard secretsEnabled else { return }
        fetchSecretCatalog { definitions in
            self.fetchUserSecrets(userId: userId) { states in
                let found = Set(states.map(\.secretId))
                guard let next = definitions.first(where: { !found.contains($0.id) }) else { return }
                self.unlockSecretIfNeeded(next, userId: userId)
            }
        }
    }

    func fetchSecretCatalog(completion: @escaping ([SecretUnlockDefinition]) -> Void) {
        guard secretsEnabled else {
            completion([])
            return
        }
        db.collection("secret_unlocks")
            .whereField("active", isEqualTo: true)
            .getDocuments { snap, _ in
                let seedById = Dictionary(uniqueKeysWithValues: GamificationSeedCatalog.secretUnlocks.compactMap { seed -> (String, [String: Any])? in
                    guard let id = seed["id"] as? String else { return nil }
                    return (id, seed)
                })
                let seedByCode = Dictionary(uniqueKeysWithValues: GamificationSeedCatalog.secretUnlocks.compactMap { seed -> (String, [String: Any])? in
                    guard let code = seed["code"] as? String else { return nil }
                    return (code, seed)
                })
                let remoteDocs = snap?.documents ?? []
                if remoteDocs.isEmpty {
                    completion(GamificationSeedCatalog.secretUnlocks.map {
                        SecretUnlockDefinition(id: ($0["id"] as? String) ?? UUID().uuidString, data: $0)
                    }.sorted { $0.masterSequenceOrder < $1.masterSequenceOrder })
                } else {
                    var merged = remoteDocs.map { doc -> SecretUnlockDefinition in
                        var data = doc.data()
                        let remoteId = doc.documentID
                        let remoteCode = data["code"] as? String
                        if let seed = seedById[remoteId] ?? (remoteCode.flatMap { seedByCode[$0] }) {
                            data.merge(seed) { _, seedValue in seedValue }
                        }
                        return SecretUnlockDefinition(id: remoteId, data: data)
                    }
                    let presentIds = Set(merged.map(\.id))
                    let presentCodes = Set(merged.map(\.code))
                    let missingSeedDefs = GamificationSeedCatalog.secretUnlocks.compactMap { seed -> SecretUnlockDefinition? in
                        let id = (seed["id"] as? String) ?? UUID().uuidString
                        let code = (seed["code"] as? String) ?? id
                        guard !presentIds.contains(id), !presentCodes.contains(code) else { return nil }
                        return SecretUnlockDefinition(id: id, data: seed)
                    }
                    merged.append(contentsOf: missingSeedDefs)
                    completion(merged.sorted { $0.masterSequenceOrder < $1.masterSequenceOrder })
                }
            }
    }

    func fetchUserSecrets(userId: String, completion: @escaping ([UserSecretUnlockState]) -> Void) {
        guard secretsEnabled else {
            completion([])
            return
        }
        db.collection("user_secret_unlocks")
            .whereField("user_id", isEqualTo: userId)
            .getDocuments { snap, _ in
                let states = (snap?.documents ?? [])
                    .compactMap { doc -> UserSecretUnlockState? in
                        let data = doc.data()
                        guard data["discovered_at"] != nil else { return nil }
                        return UserSecretUnlockState(id: doc.documentID, data: data)
                    }
                    .sorted { lhs, rhs in
                        if lhs.discoveryOrder != rhs.discoveryOrder { return lhs.discoveryOrder < rhs.discoveryOrder }
                        return (lhs.discoveredAt?.dateValue() ?? .distantPast) < (rhs.discoveredAt?.dateValue() ?? .distantPast)
                    }
                completion(states)
            }
    }

    func fetchNextHintSecret(userId: String, completion: @escaping (SecretUnlockDefinition?) -> Void) {
        fetchSecretCatalog { definitions in
            self.fetchUserSecrets(userId: userId) { states in
                let found = Set(states.map(\.secretId))
                completion(definitions.first(where: { !found.contains($0.id) }))
            }
        }
    }

    func reevaluateListSecrets(userId: String) {
        guard secretsEnabled else { return }
        fetchSecretCatalog { definitions in
            let relevant = definitions.filter { ["monochromatic", "negative_nancy"].contains($0.code) && $0.active }
            guard !relevant.isEmpty else { return }
            self.fetchTieredLists(userId: userId) { lists in
                for definition in relevant {
                    switch definition.code {
                    case "monochromatic":
                        let hasMatch = lists.contains { self.matchesMonochromatic(input: self.secretInput(from: $0)) }
                        if hasMatch { self.unlockSecretIfNeeded(definition, userId: userId) }
                    case "negative_nancy":
                        let hasMatch = lists.contains { self.matchesNegativeNancy(input: self.secretInput(from: $0)) }
                        if hasMatch { self.unlockSecretIfNeeded(definition, userId: userId) }
                    default:
                        break
                    }
                }
            }
        }
    }

    func evaluateTierListSecrets(
        userId: String,
        isPublic: Bool,
        tierLabels: [String],
        tierColors: [String],
        itemTierLabels: [String] = []
    ) {
        guard secretsEnabled else { return }
        let input = TierListSecretInput(
            isPublic: isPublic,
            tierLabels: tierLabels,
            tierColors: tierColors,
            itemTierLabels: itemTierLabels
        )
        evaluateTierListSecrets(userId: userId, input: input)
    }

    func evaluateTierListSecretsForList(userId: String, listId: String) {
        guard secretsEnabled else { return }
        fetchTierListSnapshot(listId: listId) { snapshot in
            guard let snapshot else { return }
            self.evaluateTierListSecrets(userId: userId, input: self.secretInput(from: snapshot))
        }
    }

    private func evaluateTierListSecrets(userId: String, input: TierListSecretInput) {
        if matchesMonochromatic(input: input), let definition = seededDefinition(code: "monochromatic"), definition.active {
            unlockSecretIfNeeded(definition, userId: userId)
        }
        if matchesNegativeNancy(input: input), let definition = seededDefinition(code: "negative_nancy"), definition.active {
            unlockSecretIfNeeded(definition, userId: userId)
        }
    }

    private func secretInput(from snapshot: SecretTierListSnapshot) -> TierListSecretInput {
        TierListSecretInput(
            isPublic: snapshot.list.isPublic,
            tierLabels: snapshot.list.tierLabels ?? [],
            tierColors: snapshot.list.tierColors ?? [],
            itemTierLabels: snapshot.items.compactMap { $0.tier }
        )
    }

    private func matchesMonochromatic(input: TierListSecretInput) -> Bool {
        let normalizedColors = input.tierColors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        // This secret should only unlock when the user intentionally assigns the same
        // explicit color to every tier. Blank/default rows should not count.
        guard normalizedColors.count >= 5 else { return false }
        guard normalizedColors.allSatisfy({ !$0.isEmpty }) else { return false }
        guard normalizedColors != defaultTierPalette else { return false }
        return Set(normalizedColors).count == 1
    }

    private func matchesNegativeNancy(input: TierListSecretInput) -> Bool {
        guard input.isPublic else { return false }
        let normalizedLabels = input.tierLabels.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard normalizedLabels.contains("f") else { return false }
        let fCount = input.itemTierLabels.filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "f"
        }.count
        return fCount >= 5
    }

    func handleEvent(_ event: RewardService.GamificationEvent, metrics: UserGamificationMetrics) {
        guard secretsEnabled else { return }
        fetchSecretCatalog { definitions in
            for definition in definitions where definition.active {
                if self.handleSpecialSecretIfNeeded(definition, event: event, userId: event.userId) {
                    continue
                }
                let progress = self.metricValue(for: definition.triggerMetric, metrics: metrics, eventDayKey: ObjectiveService.dayKey(for: event.occurredAt))
                guard progress >= definition.triggerThreshold else { continue }
                self.unlockSecretIfNeeded(definition, userId: event.userId)
            }
        }
    }

    private func handleSpecialSecretIfNeeded(_ definition: SecretUnlockDefinition, event: RewardService.GamificationEvent, userId: String) -> Bool {
        switch definition.code {
        case "monochromatic":
            guard event.kind == .createList || event.kind == .addToList else { return true }
            fetchTieredLists(userId: userId) { lists in
                let hasMatch = lists.contains { snapshot in
                    let colors = (snapshot.list.tierColors ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        .filter { !$0.isEmpty }
                    guard colors.count >= 2 else { return false }
                    return Set(colors).count == 1
                }
                if hasMatch {
                    self.unlockSecretIfNeeded(definition, userId: userId)
                }
            }
            return true
        case "negative_nancy":
            guard event.kind == .createList || event.kind == .addToList else { return true }
            fetchTieredLists(userId: userId) { lists in
                let hasMatch = lists.contains { snapshot in
                    guard snapshot.list.isPublic else { return false }
                    let normalizedLabels = (snapshot.list.tierLabels ?? []).map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }
                    let hasFTier = normalizedLabels.contains("f")
                    guard hasFTier else { return false }
                    let fCount = snapshot.items.filter {
                        ($0.tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "f"
                    }.count
                    return fCount >= 5
                }
                if hasMatch {
                    self.unlockSecretIfNeeded(definition, userId: userId)
                }
            }
            return true
        default:
            return false
        }
    }

    private func fetchTieredLists(userId: String, completion: @escaping ([SecretTierListSnapshot]) -> Void) {
        db.collection("lists")
            .whereField("owner_id", isEqualTo: userId)
            .whereField("type", isEqualTo: ListType.tiered.rawValue)
            .getDocuments { snap, _ in
                let lists = (snap?.documents ?? []).compactMap { UserList(id: $0.documentID, data: $0.data()) }
                guard !lists.isEmpty else {
                    completion([])
                    return
                }

                let group = DispatchGroup()
                let lock = NSLock()
                var snapshots: [SecretTierListSnapshot] = []

                for list in lists {
                    group.enter()
                    self.db.collection("lists").document(list.id).collection("items").getDocuments { itemSnap, _ in
                        let items = (itemSnap?.documents ?? []).compactMap { doc -> UserListItem? in
                            var data = doc.data()
                            data["list_id"] = list.id
                            return UserListItem(id: doc.documentID, data: data)
                        }
                        lock.lock()
                        snapshots.append(SecretTierListSnapshot(list: list, items: items))
                        lock.unlock()
                        group.leave()
                    }
                }

                group.notify(queue: .global()) {
                    completion(snapshots)
                }
            }
    }

    private func fetchTierListSnapshot(listId: String, completion: @escaping (SecretTierListSnapshot?) -> Void) {
        let listRef = db.collection("lists").document(listId)
        listRef.getDocument { listSnap, _ in
            guard let listData = listSnap?.data(), let listSnap,
                  let list = UserList(id: listSnap.documentID, data: listData) else {
                completion(nil)
                return
            }
            listRef.collection("items").getDocuments { itemSnap, _ in
                let items = (itemSnap?.documents ?? []).compactMap { doc -> UserListItem? in
                    var data = doc.data()
                    data["list_id"] = list.id
                    return UserListItem(id: doc.documentID, data: data)
                }
                completion(SecretTierListSnapshot(list: list, items: items))
            }
        }
    }

    private func unlockSecretIfNeeded(_ definition: SecretUnlockDefinition, userId: String) {
        let docId = "\(userId)_\(definition.id)"
        let ref = db.collection("user_secret_unlocks").document(docId)
        ref.getDocument { snap, err in
            if err != nil { return }
            if snap?.exists == true && !definition.isRepeatable { return }

            self.fetchUserSecrets(userId: userId) { states in
                let nextDiscoveryOrder = (states.map(\.discoveryOrder).max() ?? 0) + 1
                let payload: [String: Any] = [
                    "user_id": userId,
                    "secret_id": definition.id,
                    "discovered_at": Timestamp(date: Date()),
                    "discovery_order": nextDiscoveryOrder,
                    "claimed": false,
                    "xp_granted": 0,
                    "unlockables_granted": []
                ]
                ref.setData(payload, merge: definition.isRepeatable) { writeErr in
                    if writeErr != nil { return }
                    NotificationCenter.default.post(
                        name: .gamificationUpdated,
                        object: nil,
                        userInfo: ["user_id": userId]
                    )
                    NotificationCenter.default.post(
                        name: .secretQuestFound,
                        object: nil,
                        userInfo: [
                            "user_id": userId,
                            "title": definition.title
                        ]
                    )
                }
            }
        }
    }

    func claimSecretXP(
        userId: String,
        secretId: String,
        completion: ((Int) -> Void)? = nil
    ) {
        guard secretsEnabled else {
            DispatchQueue.main.async { completion?(0) }
            return
        }
        let ref = db.collection("user_secret_unlocks").document("\(userId)_\(secretId)")
        fetchSecretCatalog { definitions in
            guard let definition = definitions.first(where: { $0.id == secretId }) else {
                DispatchQueue.main.async { completion?(0) }
                return
            }

            ref.getDocument { snapshot, _ in
                guard
                    let data = snapshot?.data(),
                    let discoveredAt = data["discovered_at"] as? Timestamp,
                    discoveredAt.dateValue() <= Date()
                else {
                    DispatchQueue.main.async { completion?(0) }
                    return
                }

                let alreadyClaimed = data["claimed"] as? Bool ?? false
                guard !alreadyClaimed, definition.xpReward > 0 else {
                    DispatchQueue.main.async { completion?(0) }
                    return
                }

                ref.setData([
                    "claimed": true,
                    "xp_granted": definition.xpReward,
                    "unlockables_granted": definition.unlockableRewardIds
                ], merge: true)

                RewardService.shared.grantSecretUnlockXP(
                    userId: userId,
                    amount: definition.xpReward,
                    reason: "secret_unlock",
                    sourceId: definition.id
                ) { granted in
                    NotificationCenter.default.post(
                        name: .gamificationUpdated,
                        object: nil,
                        userInfo: ["user_id": userId]
                    )

                    DispatchQueue.main.async {
                        completion?(granted)
                    }
                }
            }
        }
    }

    private func metricValue(for metric: String, metrics: UserGamificationMetrics, eventDayKey: String) -> Int {
        switch metric {
        case "perfect_ten_ratings_count":
            return metrics.perfectTenRatingsCount
        case "double_take_ratings_count":
            return metrics.doubleTakeRatingsCount
        case "low_hp_ratings_count":
            return metrics.lowHPRatingsCount
        case "reviews_in_day":
            return metrics.reviewsByDay[eventDayKey] ?? 0
        case "retro_games_logged":
            return metrics.retroGamesLoggedCount
        case "log_actions_count":
            return metrics.logActionsCount
        case "saved_games_count":
            return metrics.savedGamesCount
        case "completed_quests_count":
            return metrics.completedQuestsCount
        default:
            return 0
        }
    }
}
