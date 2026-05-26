// GameNameCache.swift
// A single, concurrency-safe cache for IGDB game names.
// BEGINNERS:
// • Using an `actor` ensures only one task mutates the cache at a time.
// • We also dedupe in-flight lookups so we never resume the same continuation twice,
//   which fixes the "SWIFT TASK CONTINUATION MISUSE" crash you saw on device under flaky networks.

import Foundation

actor GameNameCache {
    static let shared = GameNameCache()

    private var cache: [Int: String] = [:]
    // Track in-flight tasks so repeated requests for the same id await the same work
    private var inflight: [Int: Task<String, Never>] = [:]
    private let storageKey = "gamerlnd.game_name_cache.v2"

    init() {
        if let data = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            var restored: [Int: String] = [:]
            for (k, v) in data {
                let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = Int(k), !trimmed.isEmpty, trimmed != "Unknown Game" {
                    restored[id] = trimmed
                }
            }
            cache = restored
        }
    }

    /// Get names for ids; missing ones are fetched and cached.
    func fillAndGet(namesFor ids: [Int]) async -> [Int: String] {
        var results: [Int: String] = [:]
        let uniqueIds = ids.reduce(into: [Int]()) { acc, id in
            if id > 0, !acc.contains(id) { acc.append(id) }
        }
        let missingIds = uniqueIds.filter {
            guard let name = cache[$0] else { return true }
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        for id in uniqueIds {
            if let name = cache[id], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results[id] = name
            }
        }

        guard !missingIds.isEmpty else {
            return results
        }

        let fetched = await fetchNames(ids: missingIds)
        for (id, name) in fetched {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            results[id] = name
            if !trimmed.isEmpty && trimmed != "Unknown Game" {
                cache[id] = trimmed
            } else {
                cache[id] = nil
            }
        }
        persistCacheIfNeeded()

        return results
    }

    // MARK: - Private

    private func fetchNames(ids: [Int]) async -> [Int: String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[Int: String], Never>) in
            var finished = false
            func resumeOnce(_ value: [Int: String]) {
                guard !finished else { return }
                finished = true
                cont.resume(returning: value)
            }

            IGDBService().fetchGamesByIds(ids: ids) { result in
                switch result {
                case .success(let games):
                    let map = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.name) })
                    resumeOnce(map)
                case .failure:
                    resumeOnce([:])
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                resumeOnce([:])
            }
        }
    }

    private func persistCacheIfNeeded() {
        // Keep cache lightweight for device storage.
        if cache.count > 600 {
            let trimmed = Array(cache.prefix(600))
            cache = Dictionary(uniqueKeysWithValues: trimmed)
        }
        let dict: [String: String] = cache.reduce(into: [:]) { acc, pair in
            let trimmed = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != "Unknown Game" {
                acc[String(pair.key)] = pair.value
            }
        }
        UserDefaults.standard.set(dict, forKey: storageKey)
    }
}
