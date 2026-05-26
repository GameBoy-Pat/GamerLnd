# Backend / Data Sanity Pass

Date: 2026-04-02
Project: GamerLnd beta prep

## What we checked
- Firebase auth / profile bootstrap behavior
- Firestore-heavy feed loading paths
- IGDB auth + metadata fetch behavior
- Daily / weekly objective generation paths
- Listener lifetime / background update behavior
- Beta data assumptions for quests / secrets / founder state

## Current good state

### 1. IGDB auth is healthier
- The old `401 -> refresh -> retry` pattern was removed.
- IGDB token preflight now happens before requests.
- Batched IGDB metadata fetches are in place for several heavy surfaces.

### 2. Debug profiling noise is reduced
- Firebase Analytics and Crashlytics collection are disabled in `DEBUG` only.
- This gives cleaner performance profiling without changing release behavior.

### 3. Feed query fan-out is much better
- Like counts, comment counts, like state, average rating data, and `has logged` state were reduced from many per-row requests to batched/prefetched work.
- First-page feed hydration is now prioritized and partially deferred for better startup behavior.

### 4. Daily / weekly objective fallback is safer
- There is a local fallback path so the app should not sit on `Refreshing challenges...` forever if the persistence path stalls.
- Objective pools are seeded in code and GL-gated.

### 5. Secret quests are effectively off for beta
- `secretsEnabled = false`
- This is the right beta choice because it avoids partial/unreliable unlock behavior.

## Residual beta risks to be aware of

### 1. Following feed now queries all followed users in chunks
- File: `/Users/patrickflood/Desktop/GamerLnd/GamerLnd/ContentView.swift`
- Firestore `in` query limits are now handled by chunking followed user IDs into groups of 10.
- The `Following` feed merges results across those chunks instead of silently dropping followed users beyond the first 10.
- This removes the biggest feed correctness risk that existed earlier in beta prep.

### 2. Objective reset timing still depends on client execution
- The app has ET-based keying and fallback generation logic.
- That is good for beta.
- But it is still client-driven, not server-scheduled. So the exact refresh moment depends on the user opening/using the app around the boundary.

### 3. One deprecated navigation API remains
- File: `/Users/patrickflood/Desktop/GamerLnd/GamerLnd/ProfileView.swift:327`
- This is not a beta blocker, just cleanup.

### 4. Performance is improved but not fully "done"
- Startup and Home idle behavior are materially better than before.
- But Home still has enough moving pieces that a deeper post-beta feed refactor would still be worthwhile.

## Suggested go/no-go read

### Safe enough for beta
- IGDB/network waste is meaningfully improved.
- Feed fan-out and offscreen churn are materially reduced.
- Secret quests are disabled instead of half-working.
- Objective generation has a fallback path.
- Overlay and profile-state work is much more stable than before.

### Notable limitation to remember during beta
- The `Following` feed fix is correctness-first, so users with very large follow graphs may cause a somewhat heavier `Following` feed load than users with smaller graphs.

## Recommended post-beta work
1. Move more Home/feed state out of `ContentView` if we still want lower steady-state CPU.
2. Replace the deprecated `NavigationLink(isActive:)` path in Profile.
