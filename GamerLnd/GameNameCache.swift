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
    private let storageKey = "gamerlnd.game_name_cache.v1"

    init() {
        if let data = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            var restored: [Int: String] = [:]
            for (k, v) in data {
                if let id = Int(k) { restored[id] = v }
            }
            cache = restored
        }
    }

    /// Get names for ids; missing ones are fetched and cached.
    func fillAndGet(namesFor ids: [Int]) async -> [Int: String] {
        var results: [Int: String] = [:]
        var tasks: [(Int, Task<String, Never>)] = []

        for id in ids {
            if let name = cache[id] {
                results[id] = name
                continue
            }
            if let t = inflight[id] {
                tasks.append((id, t))
                continue
            }
            let t = Task<String, Never> {
                await fetchName(id: id)
            }
            inflight[id] = t
            tasks.append((id, t))
        }

        for (id, task) in tasks {
            let name = await task.value
            results[id] = name
            if name != "Unknown Game" {
                cache[id] = name
            }
            inflight[id] = nil
        }
        persistCacheIfNeeded()

        return results
    }

    // MARK: - Private

    private func fetchName(id: Int) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            var finished = false
            func resumeOnce(_ value: String) {
                guard !finished else { return }
                finished = true
                cont.resume(returning: value)
            }

            IGDBService().fetchGameById(id: id) { result in
                switch result {
                case .success(let game):
                    resumeOnce(game.name)
                case .failure:
                    resumeOnce("")
                }
            }

            // Optional safety timeout (2.5s) to avoid hanging on no-callback scenarios
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                resumeOnce("")
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
            if pair.value != "Unknown Game" {
                acc[String(pair.key)] = pair.value
            }
        }
        UserDefaults.standard.set(dict, forKey: storageKey)
    }
}
