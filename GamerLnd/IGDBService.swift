// IGDBService.swift
// Service to interact with the IGDB API for game data and filters.
// THIS PASS:
// • Single source of truth for paged search: searchGamesPaged(query:year:genre:limit:offset:completion:)
// • Convenience searchGames(...) wraps the paged version (limit 20, offset 0).
// • Keeps in-memory cache + OAuth refresh (401) + simple 429 backoff.

import Foundation
import os.log

final class IGDBService {
    private var clientId: String
    private var accessToken: String
    private var clientSecret: String
    private let baseUrl = Config.igdbBaseUrl // e.g. https://api.igdb.com/v4

    // In-memory game cache (session-scoped)
    private var gameCache: [Int: Game] = [:]
    private let cacheQueue = DispatchQueue(label: "igdb.cache.queue", attributes: .concurrent)

    init() {
        self.clientId = Config.igdbClientId
        self.accessToken = Config.igdbAccessToken
        self.clientSecret = Config.igdbClientSecret
        os_log("IGDBService initialized", log: .default, type: .debug)
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
            self.accessToken = token
            completion(.success(token))
        }.resume()
    }

    // MARK: - Search (Convenience)

    /// Legacy convenience that just calls the paged API with a default limit/offset.
    func searchGames(query: String, year: String?, genre: String?, completion: @escaping (Result<[Game], Error>) -> Void) {
        searchGamesPaged(query: query, year: year, genre: genre, limit: 20, offset: 0, completion: completion)
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
        let body = buildGamesSearchBody(query: query, year: year, genre: genre, limit: max(1, min(50, limit)), offset: max(0, offset))
        makeRequest(endpoint: "/games", body: body, retries: 2) { (result: Result<[Game], Error>) in
            switch result {
            case .success(let games):
                self.cacheGames(games)
                completion(.success(games))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    private func buildGamesSearchBody(query: String, year: String?, genre: String?, limit: Int, offset: Int) -> String {
        var body = """
        fields id,name,cover.image_id,first_release_date,genres.name,platforms.name,rating,rating_count,total_rating_count,screenshots.image_id;
        search "\(query.replacingOccurrences(of: "\"", with: ""))*";
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

    // MARK: - Single Game (with cache)

    func fetchGameById(id: Int, completion: @escaping (Result<Game, Error>) -> Void) {
        cacheQueue.sync {
            if let cached = gameCache[id] {
                completion(.success(cached))
                return
            }
        }
        let body = "fields id,name,cover.image_id,first_release_date,genres.name,platforms.name,rating,rating_count,total_rating_count,screenshots.image_id; where id = \(id); limit 1;"
        makeRequest(endpoint: "/games", body: body, retries: 2) { (result: Result<[Game], Error>) in
            switch result {
            case .success(let games):
                if let g = games.first {
                    self.cacheQueue.async(flags: .barrier) { self.gameCache[id] = g }
                    completion(.success(g))
                } else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No game found for ID \(id)"])))
                }
            case .failure(let err):
                completion(.failure(err))
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
        guard let url = URL(string: "\(baseUrl)\(endpoint)") else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(clientId, forHTTPHeaderField: "Client-ID")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }

            // 401 → refresh OAuth and retry
            if http.statusCode == 401 && retries > 0 {
                self.fetchAccessToken { result in
                    switch result {
                    case .success:
                        self.makeRequest(endpoint: endpoint, body: body, retries: retries - 1, completion: completion)
                    case .failure(let tokenError):
                        completion(.failure(tokenError))
                    }
                }
                return
            }

            // 429 → exponential backoff and retry
            if http.statusCode == 429 && retries > 0 {
                let attempt = max(0, 3 - retries) // 0,1,2...
                let delay = pow(1.5, Double(attempt)) // 1.0, 1.5, 2.25 sec
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.makeRequest(endpoint: endpoint, body: body, retries: retries - 1, completion: completion)
                }
                return
            }

            guard http.statusCode == 200 else {
                completion(.failure(NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error \(http.statusCode)"])))
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
        cacheQueue.async(flags: .barrier) {
            for g in games { self.gameCache[g.id] = g }
        }
    }
}

// Temporary struct for release dates.
struct ReleaseDate: Codable {
    let date: Date?
}
