// IGDBService.swift
// Service to interact with the IGDB API for game data and filters.
// THIS PASS:
// • Single source of truth for paged search: searchGamesPaged(query:year:genre:limit:offset:completion:)
// • Convenience searchGames(...) wraps the paged version (limit 20, offset 0).
// • Keeps in-memory cache + OAuth refresh (401) + simple 429 backoff.

import Foundation
import os.log

final class IGDBService {
    private static let authQueue = DispatchQueue(label: "igdb.auth.queue")
    private static let storedTokenKey = "igdb.oauth.token"
    private static let storedTokenExpiryKey = "igdb.oauth.expiry"
    private static var sharedAccessToken: String = UserDefaults.standard.string(forKey: IGDBService.storedTokenKey) ?? Config.igdbAccessToken
    private static var sharedTokenExpiry: Date? = {
        let ts = UserDefaults.standard.double(forKey: IGDBService.storedTokenExpiryKey)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }()
    private static var refreshInFlight = false
    private static var refreshWaiters: [(Result<String, Error>) -> Void] = []

    private var clientId: String
    private var clientSecret: String
    private let baseUrl = Config.igdbBaseUrl // e.g. https://api.igdb.com/v4

    // In-memory game cache (shared app-wide so repeated IGDBService() instances still reuse data)
    private static var sharedGameCache: [Int: Game] = [:]
    private static let cacheQueue = DispatchQueue(label: "igdb.cache.queue", attributes: .concurrent)

    init() {
        self.clientId = Config.igdbClientId
        self.clientSecret = Config.igdbClientSecret
    }

    // MARK: - OAuth

    private func fetchAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://id.twitch.tv/oauth2/token?client_id=\(clientId)&client_secret=\(clientSecret)&grant_type=client_credentials") else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid access token response"])))
                return
            }

            let expiresIn = (json["expires_in"] as? Double) ?? Double((json["expires_in"] as? Int) ?? 0)
            let expiryDate = expiresIn > 0 ? Date().addingTimeInterval(expiresIn - 300) : Date().addingTimeInterval(55 * 60)
            IGDBService.storeAccessToken(token, expiry: expiryDate)
            completion(.success(token))
        }.resume()
    }

    private func ensureValidAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        IGDBService.authQueue.async {
            if let expiry = IGDBService.sharedTokenExpiry,
               expiry > Date(),
               !IGDBService.sharedAccessToken.isEmpty {
                completion(.success(IGDBService.sharedAccessToken))
                return
            }

            if IGDBService.refreshInFlight {
                IGDBService.refreshWaiters.append(completion)
                return
            }

            IGDBService.refreshInFlight = true
            IGDBService.refreshWaiters.append(completion)

            self.fetchAccessToken { result in
                IGDBService.authQueue.async {
                    let waiters = IGDBService.refreshWaiters
                    IGDBService.refreshWaiters.removeAll()
                    IGDBService.refreshInFlight = false
                    if case .failure = result {
                        IGDBService.clearStoredAccessToken()
                    }
                    waiters.forEach { $0(result) }
                }
            }
        }
    }

    private static func storeAccessToken(_ token: String, expiry: Date) {
        authQueue.async {
            sharedAccessToken = token
            sharedTokenExpiry = expiry
            UserDefaults.standard.set(token, forKey: storedTokenKey)
            UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: storedTokenExpiryKey)
        }
    }

    private static func clearStoredAccessToken() {
        authQueue.async {
            sharedAccessToken = ""
            sharedTokenExpiry = nil
            UserDefaults.standard.removeObject(forKey: storedTokenKey)
            UserDefaults.standard.removeObject(forKey: storedTokenExpiryKey)
        }
    }

    // MARK: - Search (Convenience)

    /// Legacy convenience that just calls the paged API with a default limit/offset.
    func searchGames(query: String, year: String?, genre: String?, completion: @escaping (Result<[Game], Error>) -> Void) {
        searchGamesPaged(query: query, year: year, genre: genre, limit: 20, offset: 0, completion: completion)
    }

    // MARK: - Discover

    /// Fetches recent official releases for Explore "New Releases".
    func fetchNewReleases(limit: Int = 16, completion: @escaping (Result<[Game], Error>) -> Void) {
        let now = Int(Date().timeIntervalSince1970)
        let safeLimit = max(1, min(40, limit))
        let sixtyDays = 60 * 24 * 60 * 60
        let oneEightyDays = 180 * 24 * 60 * 60
        fetchNewReleasesFromReleaseDates(
            since: now - sixtyDays,
            now: now,
            limit: safeLimit
        ) { result in
            switch result {
            case .success(let games):
                if games.isEmpty {
                    self.fetchNewReleasesFromReleaseDates(
                        since: now - oneEightyDays,
                        now: now,
                        limit: safeLimit
                    ) { fallback in
                        switch fallback {
                        case .success(let fallbackGames):
                            if fallbackGames.isEmpty {
                                self.fetchNewReleasesFromGames(since: now - oneEightyDays, now: now, limit: safeLimit, completion: completion)
                            } else {
                                completion(.success(fallbackGames))
                            }
                        case .failure:
                            self.fetchNewReleasesFromGames(since: now - oneEightyDays, now: now, limit: safeLimit, completion: completion)
                        }
                    }
                } else {
                    completion(.success(games))
                }
            case .failure:
                self.fetchNewReleasesFromGames(since: now - oneEightyDays, now: now, limit: safeLimit, completion: completion)
            }
        }
    }

    private func fetchNewReleasesFromReleaseDates(since: Int, now: Int, limit: Int, completion: @escaping (Result<[Game], Error>) -> Void) {
        let releaseDateBody = """
        fields game,date,platform,human;
        where game != null
          & date != null
          & date >= \(since)
          & date <= \(now);
        sort date desc;
        limit \(max(120, limit * 6));
        """

        makeRequest(endpoint: "/release_dates", body: releaseDateBody, retries: 2) { (result: Result<[ReleaseDate], Error>) in
            switch result {
            case .success(let releaseDates):
                let sorted = releaseDates.sorted { ($0.dateUnix ?? 0) > ($1.dateUnix ?? 0) }
                var seen = Set<Int>()
                var orderedGameIds: [Int] = []
                var releasePlatformIdsByGame: [Int: Set<Int>] = [:]
                for item in sorted {
                    guard let gid = item.game, gid > 0 else { continue }
                    if let pid = item.platform, pid > 0 {
                        releasePlatformIdsByGame[gid, default: []].insert(pid)
                    }
                    if seen.insert(gid).inserted {
                        orderedGameIds.append(gid)
                    }
                    if orderedGameIds.count >= max(24, limit * 2) { break }
                }

                guard !orderedGameIds.isEmpty else {
                    completion(.success([]))
                    return
                }

                let releasePlatformIds = Array(Set(releasePlatformIdsByGame.values.flatMap { $0 }))
                self.fetchPlatformNamesById(ids: releasePlatformIds) { platformResult in
                    let platformNamesById = (try? platformResult.get()) ?? [:]
                    self.fetchGamesByIds(ids: orderedGameIds) { fetchResult in
                        switch fetchResult {
                        case .success(let games):
                            let gameMap = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
                            let filtered = orderedGameIds
                                .compactMap { gameMap[$0] }
                                .filter { game in
                                    if let c = game.category, [3,5,12,13,14].contains(c) { return false }
                                    let releaseNames = (releasePlatformIdsByGame[game.id] ?? []).compactMap { platformNamesById[$0]?.lowercased() }
                                    guard self.isAllowedNewReleasePlatform(releaseNames) else { return false }
                                    return true
                                }

                            self.fetchPopularityPrimitives(gameIds: filtered.map(\.id)) { popularityResult in
                                switch popularityResult {
                                case .success(let popularityScores):
                                    let ranked = filtered.sorted { lhs, rhs in
                                        let l = self.newReleaseRankScore(
                                            game: lhs,
                                            popularityScores: popularityScores,
                                            releasePlatformIds: releasePlatformIdsByGame[lhs.id] ?? [],
                                            platformNamesById: platformNamesById
                                        )
                                        let r = self.newReleaseRankScore(
                                            game: rhs,
                                            popularityScores: popularityScores,
                                            releasePlatformIds: releasePlatformIdsByGame[rhs.id] ?? [],
                                            platformNamesById: platformNamesById
                                        )
                                        if l == r {
                                            return (lhs.firstReleaseDate ?? 0) > (rhs.firstReleaseDate ?? 0)
                                        }
                                        return l > r
                                    }
                                    completion(.success(Array(ranked.prefix(limit))))
                                case .failure:
                                    completion(.success(Array(filtered.prefix(limit))))
                                }
                            }
                        case .failure(let err):
                            completion(.failure(err))
                        }
                    }
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    private func fetchNewReleasesFromGames(since: Int, now: Int, limit: Int, completion: @escaping (Result<[Game], Error>) -> Void) {
        let body = """
        fields id,name,slug,cover.image_id,first_release_date,genres.name,platforms.name,rating,rating_count,aggregated_rating,aggregated_rating_count,total_rating,total_rating_count,hypes,category,screenshots.image_id,involved_companies.publisher,involved_companies.developer,involved_companies.company.name,franchises.name,collections.name;
        where first_release_date != null
          & first_release_date >= \(since)
          & first_release_date <= \(now)
          & category != (3,5,12,13,14);
        sort first_release_date desc;
        limit \(max(24, limit * 2));
        """
        makeRequest(endpoint: "/games", body: body, retries: 2) { (result: Result<[Game], Error>) in
            switch result {
            case .success(let games):
                let filtered = games.filter { game in
                    self.isAllowedNewReleasePlatform((game.platforms ?? []).map { $0.name.lowercased() })
                }
                self.cacheGames(filtered)
                self.fetchPopularityPrimitives(gameIds: filtered.map(\.id)) { popularityResult in
                    switch popularityResult {
                    case .success(let popularityScores):
                        let ranked = filtered.sorted { lhs, rhs in
                            let l = self.newReleaseRankScore(game: lhs, popularityScores: popularityScores, releasePlatformIds: [], platformNamesById: [:])
                            let r = self.newReleaseRankScore(game: rhs, popularityScores: popularityScores, releasePlatformIds: [], platformNamesById: [:])
                            if l == r {
                                return (lhs.firstReleaseDate ?? 0) > (rhs.firstReleaseDate ?? 0)
                            }
                            return l > r
                        }
                        completion(.success(Array(ranked.prefix(limit))))
                    case .failure:
                        completion(.success(Array(games.prefix(limit))))
                    }
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    private func fetchPopularityPrimitives(gameIds: [Int], completion: @escaping (Result<[Int: Double], Error>) -> Void) {
        let ids = Array(Set(gameIds)).filter { $0 > 0 }
        guard !ids.isEmpty else {
            completion(.success([:]))
            return
        }
        let joined = ids.sorted().map(String.init).joined(separator: ",")
        let body = """
        fields game_id,popularity_type,value,updated_at;
        where game_id = (\(joined));
        limit \(max(200, ids.count * 6));
        """
        makeRequest(endpoint: "/popularity_primitives", body: body, retries: 2) { (result: Result<[PopularityPrimitive], Error>) in
            switch result {
            case .success(let primitives):
                var totals: [Int: Double] = [:]
                for primitive in primitives {
                    guard let gid = primitive.gameId else { continue }
                    totals[gid, default: 0] += primitive.value ?? 0
                }
                completion(.success(totals))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    private func fetchPlatformNamesById(ids: [Int], completion: @escaping (Result<[Int: String], Error>) -> Void) {
        let uniqueIds = Array(Set(ids)).filter { $0 > 0 }
        guard !uniqueIds.isEmpty else {
            completion(.success([:]))
            return
        }
        let joined = uniqueIds.sorted().map(String.init).joined(separator: ",")
        let body = """
        fields id,name;
        where id = (\(joined));
        limit \(min(200, uniqueIds.count));
        """
        makeRequest(endpoint: "/platforms", body: body, retries: 2) { (result: Result<[PlatformLite], Error>) in
            switch result {
            case .success(let platforms):
                completion(.success(Dictionary(uniqueKeysWithValues: platforms.map { ($0.id, $0.name) })))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    private func newReleaseRankScore(game: Game, popularityScores: [Int: Double], releasePlatformIds: Set<Int>, platformNamesById: [Int: String]) -> Double {
        let popularity = popularityScores[game.id] ?? 0
        let aggregatedRating = game.aggregatedRating ?? 0
        let aggregatedRatingCount = Double(game.aggregatedRatingCount ?? 0)
        let totalRating = game.totalRating ?? game.rating ?? 0
        let totalRatingCount = Double(game.totalRatingCount ?? game.ratingCount ?? 0)
        let hypes = Double(game.hypes ?? 0)
        let releasePlatformNames = releasePlatformIds.compactMap { platformNamesById[$0]?.lowercased() }
        let platformBoost = prioritizedPlatformBoost(releasePlatformNames: releasePlatformNames, popularity: popularity)
        let criticScore = (aggregatedRating * 0.45)
            + (log10(max(1, aggregatedRatingCount)) * 18.0)
        let overallScore = (totalRating * 0.20)
            + (log10(max(1, totalRatingCount)) * 12.0)
        let popularityScore = (popularity * 0.15)
            + min(28, hypes * 0.18)
        return criticScore
            + overallScore
            + popularityScore
            + platformBoost
    }

    private func prioritizedPlatformBoost(releasePlatformNames names: [String], popularity: Double) -> Double {
        guard !names.isEmpty else { return 0 }

        let hasPriorityPlatform = names.contains { name in
            name.contains("nintendo switch 2")
                || name == "nintendo switch"
                || name.contains("playstation 5")
                || name.contains("ps5")
                || name.contains("xbox series")
        }

        if hasPriorityPlatform {
            if names.contains(where: { $0.contains("nintendo switch 2") }) { return 95 }
            if names.contains(where: { $0 == "nintendo switch" || $0.contains("nintendo switch") }) { return 82 }
            if names.contains(where: { $0 == "playstation 5" || $0.contains("ps5") }) { return 78 }
            if names.contains(where: { $0.contains("xbox series") }) { return 74 }
        }

        // PC and other platforms need a meaningfully stronger popularity signal
        // before competing with priority-console releases.
        if popularity >= 85 { return 30 }
        if popularity >= 55 { return 8 }
        if popularity >= 25 { return -28 }
        return -55
    }

    private func isAllowedNewReleasePlatform(_ names: [String]) -> Bool {
        names.contains { name in
            name.contains("nintendo switch 2")
                || name == "nintendo switch"
                || name.contains("nintendo switch")
                || name == "playstation 5"
                || name.contains("ps5")
                || name.contains("xbox series")
        }
    }

    // MARK: - Search (Paged)

    /// Primary entry used by SearchView for "Load more" pagination.
    func searchGamesPaged(
        query: String,
        year: String?,
        genre: String?,
        limit: Int,
        offset: Int,
        completion: @escaping (Result<[Game], Error>) -> Void
    ) {
        let clampedLimit = max(1, min(50, limit))
        let clampedOffset = max(0, offset)
        let body = buildGamesSearchBody(query: query, year: year, genre: genre, limit: clampedLimit, offset: clampedOffset)
        makeRequest(endpoint: "/games", body: body, retries: 2) { (result: Result<[Game], Error>) in
            switch result {
            case .success(let games):
                self.cacheGames(games)
                completion(.success(games))
            case .failure(let err):
                // Fallback for stricter IGDB schemas that reject newer fields.
                let nsErr = err as NSError
                guard nsErr.code == 400 else {
                    completion(.failure(err))
                    return
                }
                let fallbackBody = self.buildGamesSearchBodyLegacy(query: query, year: year, genre: genre, limit: clampedLimit, offset: clampedOffset)
                self.makeRequest(endpoint: "/games", body: fallbackBody, retries: 2) { (fallbackResult: Result<[Game], Error>) in
                    switch fallbackResult {
                    case .success(let games):
                        self.cacheGames(games)
                        completion(.success(games))
                    case .failure(let fallbackErr):
                        completion(.failure(fallbackErr))
                    }
                }
            }
        }
    }

    private func buildGamesSearchBody(query: String, year: String?, genre: String?, limit: Int, offset: Int) -> String {
        let safeQuery = sanitizedApicalypseSearchQuery(query)
        var body = """
        fields id,name,slug,cover.image_id,first_release_date,genres.name,platforms.name,rating,rating_count,aggregated_rating,aggregated_rating_count,total_rating,total_rating_count,hypes,category,screenshots.image_id,involved_companies.publisher,involved_companies.developer,involved_companies.company.name,franchises.name,collections.name;
        search "\(safeQuery)";
        limit \(limit);
        offset \(offset);
        """

        var whereClauses: [String] = []
        if let year = year, let yearInt = Int(year) {
            let cal = Calendar(identifier: .gregorian)
            var comps = DateComponents()
            comps.year = yearInt; comps.month = 1; comps.day = 1; comps.timeZone = TimeZone(secondsFromGMT: 0)
            let start = cal.date(from: comps)?.timeIntervalSince1970 ?? Double(yearInt * 31_536_000)
            comps.year = yearInt + 1
            let end = cal.date(from: comps)?.timeIntervalSince1970 ?? Double((yearInt + 1) * 31_536_000)
            whereClauses.append("first_release_date >= \(Int(start)) & first_release_date < \(Int(end))")
        }
        if let genre = genre, !genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let safe = genre.replacingOccurrences(of: "\"", with: "")
            whereClauses.append("genres.name = \"\(safe)\"")
        }
        if !whereClauses.isEmpty {
            body += "\nwhere \(whereClauses.joined(separator: " & "));"
        }
        return body
    }

    // Known-good field set fallback for environments where newer fields are rejected.
    private func buildGamesSearchBodyLegacy(query: String, year: String?, genre: String?, limit: Int, offset: Int) -> String {
        let safeQuery = sanitizedApicalypseSearchQuery(query)
        var body = """
        fields id,name,cover.image_id,first_release_date,genres.name,platforms.name,rating,rating_count,aggregated_rating,aggregated_rating_count,total_rating,total_rating_count,screenshots.image_id,involved_companies.publisher,involved_companies.developer,involved_companies.company.name,franchises.name,collections.name;
        search "\(safeQuery)";
        limit \(limit);
        offset \(offset);
        """

        var whereClauses: [String] = []
        if let year = year, let yearInt = Int(year) {
            let cal = Calendar(identifier: .gregorian)
            var comps = DateComponents()
            comps.year = yearInt; comps.month = 1; comps.day = 1; comps.timeZone = TimeZone(secondsFromGMT: 0)
            let start = cal.date(from: comps)?.timeIntervalSince1970 ?? Double(yearInt * 31_536_000)
            comps.year = yearInt + 1
            let end = cal.date(from: comps)?.timeIntervalSince1970 ?? Double((yearInt + 1) * 31_536_000)
            whereClauses.append("first_release_date >= \(Int(start)) & first_release_date < \(Int(end))")
        }
        if let genre = genre, !genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let safe = genre.replacingOccurrences(of: "\"", with: "")
            whereClauses.append("genres.name = \"\(safe)\"")
        }
        if !whereClauses.isEmpty {
            body += "\nwhere \(whereClauses.joined(separator: " & "));"
        }
        return body
    }

    private func sanitizedApicalypseSearchQuery(_ query: String) -> String {
        query
            .replacingOccurrences(of: "\\", with: " ")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: ";", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Single Game (with cache)

    func fetchGameById(id: Int, completion: @escaping (Result<Game, Error>) -> Void) {
        let cachedGame: Game? = IGDBService.cacheQueue.sync {
            IGDBService.sharedGameCache[id]
        }
        if let cached = cachedGame {
            completion(.success(cached))
            return
        }
        let body = "fields id,name,slug,cover.image_id,first_release_date,genres.name,platforms.name,rating,rating_count,aggregated_rating,aggregated_rating_count,total_rating,total_rating_count,hypes,category,screenshots.image_id,involved_companies.publisher,involved_companies.developer,involved_companies.company.name,franchises.name,collections.name; where id = \(id); limit 1;"
        makeRequest(endpoint: "/games", body: body, retries: 2) { (result: Result<[Game], Error>) in
            switch result {
            case .success(let games):
                if let g = games.first {
                    IGDBService.cacheQueue.async(flags: .barrier) { IGDBService.sharedGameCache[id] = g }
                    completion(.success(g))
                } else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No game found for ID \(id)"])))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    func fetchGameNameById(id: Int, completion: @escaping (Result<String, Error>) -> Void) {
        struct NameOnlyGame: Decodable {
            let id: Int
            let name: String
        }

        let body = "fields id,name; where id = \(id); limit 1;"
        makeRequest(endpoint: "/games", body: body, retries: 2) { (result: Result<[NameOnlyGame], Error>) in
            switch result {
            case .success(let games):
                if let g = games.first {
                    completion(.success(g.name))
                } else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No game name found for ID \(id)"])))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    func fetchGamesByIds(ids: [Int], completion: @escaping (Result<[Game], Error>) -> Void) {
        let requestedIds = ids.filter { $0 > 0 }
        let orderedUniqueIds = requestedIds.reduce(into: [Int]()) { acc, id in
            if !acc.contains(id) { acc.append(id) }
        }
        guard !orderedUniqueIds.isEmpty else {
            completion(.success([]))
            return
        }

        let cachedGames: [Int: Game] = IGDBService.cacheQueue.sync {
            var out: [Int: Game] = [:]
            for id in orderedUniqueIds {
                if let game = IGDBService.sharedGameCache[id] { out[id] = game }
            }
            return out
        }
        let missingIds = orderedUniqueIds.filter { cachedGames[$0] == nil }

        func finish(with fetchedGames: [Game]) {
            let fetchedMap = Dictionary(uniqueKeysWithValues: fetchedGames.map { ($0.id, $0) })
            let merged = orderedUniqueIds.compactMap { cachedGames[$0] ?? fetchedMap[$0] }
            completion(.success(merged))
        }

        guard !missingIds.isEmpty else {
            finish(with: [])
            return
        }

        let joined = missingIds.map(String.init).joined(separator: ",")
        let body = """
        fields id,name,slug,cover.image_id,first_release_date,genres.name,platforms.name,rating,rating_count,aggregated_rating,aggregated_rating_count,total_rating,total_rating_count,hypes,category,screenshots.image_id,involved_companies.publisher,involved_companies.developer,involved_companies.company.name,franchises.name,collections.name;
        where id = (\(joined));
        limit \(min(200, missingIds.count));
        """
        makeRequest(endpoint: "/games", body: body, retries: 2) { (result: Result<[Game], Error>) in
            switch result {
            case .success(let games):
                self.cacheGames(games)
                finish(with: games)
            case .failure(let err):
                if !cachedGames.isEmpty {
                    finish(with: [])
                } else {
                    completion(.failure(err))
                }
            }
        }
    }

    // MARK: - Filters

    func fetchFilterOptions(completion: @escaping (Result<([String], [String]), Error>) -> Void) {
        let group = DispatchGroup()
        var years: [String] = []
        var genres: [String] = []
        var fetchError: Error?

        // Years
        group.enter()
        let yearBody = "fields date; limit 500; sort date desc;"
        makeRequest(endpoint: "/release_dates", body: yearBody, retries: 2) { (result: Result<[ReleaseDate], Error>) in
            switch result {
            case .success(let releaseDates):
                let uniqueYears: Set<String> = Set(releaseDates.compactMap {
                    guard let d = $0.date else { return nil }
                    return String(Calendar.current.component(.year, from: d))
                })
                years = Array(uniqueYears).sorted()
            case .failure(let e):
                fetchError = e
            }
            group.leave()
        }

        // Genres
        group.enter()
        let genreBody = "fields name; limit 50;"
        makeRequest(endpoint: "/genres", body: genreBody, retries: 2) { (result: Result<[Game.Genre], Error>) in
            switch result {
            case .success(let genreData):
                genres = genreData.compactMap { $0.name }
            case .failure(let e):
                fetchError = e
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if let e = fetchError { completion(.failure(e)) }
            else { completion(.success((years, genres))) }
        }
    }

    // MARK: - Request core (401 refresh + 429 backoff)

    private func makeRequest<T: Decodable>(endpoint: String, body: String, retries: Int = 1, completion: @escaping (Result<T, Error>) -> Void) {
        ensureValidAccessToken { tokenResult in
            switch tokenResult {
            case .success(let token):
                self.performRequest(endpoint: endpoint, body: body, token: token, retries: retries, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func performRequest<T: Decodable>(endpoint: String, body: String, token: String, retries: Int, completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = URL(string: "\(baseUrl)\(endpoint)") else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(clientId, forHTTPHeaderField: "Client-ID")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }

            if http.statusCode == 401 && retries > 0 {
                IGDBService.clearStoredAccessToken()
                self.ensureValidAccessToken { refreshResult in
                    switch refreshResult {
                    case .success(let freshToken):
                        self.performRequest(endpoint: endpoint, body: body, token: freshToken, retries: retries - 1, completion: completion)
                    case .failure(let tokenError):
                        completion(.failure(tokenError))
                    }
                }
                return
            }

            if http.statusCode == 429 && retries > 0 {
                let attempt = max(0, 3 - retries)
                let delay = pow(1.5, Double(attempt))
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.makeRequest(endpoint: endpoint, body: body, retries: retries - 1, completion: completion)
                }
                return
            }

            guard http.statusCode == 200 else {
                let serverText: String
                if let data = data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    serverText = text
                } else {
                    serverText = "No server message"
                }
                completion(.failure(NSError(
                    domain: "IGDBService",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP error \(http.statusCode): \(serverText)"]
                )))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let decoded = try decoder.decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Cache

    private func cacheGames(_ games: [Game]) {
        IGDBService.cacheQueue.async(flags: .barrier) {
            for g in games { IGDBService.sharedGameCache[g.id] = g }
        }
    }
}

// Temporary struct for release dates.
struct ReleaseDate: Codable {
    let game: Int?
    let platform: Int?
    let human: String?
    let dateUnix: Int?

    enum CodingKeys: String, CodingKey {
        case game, platform, human
        case dateUnix = "date"
    }

    var date: Date? {
        guard let dateUnix else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(dateUnix))
    }
}

struct PopularityPrimitive: Codable {
    let gameId: Int?
    let value: Double?

    enum CodingKeys: String, CodingKey {
        case value
        case gameId = "game_id"
    }
}

struct PlatformLite: Codable {
    let id: Int
    let name: String
}
