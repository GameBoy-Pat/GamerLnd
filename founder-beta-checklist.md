# Founder Beta Checklist

## 1. Account + Profile
- Sign in as `@gbpatgaming`.
- Confirm profile loads without stale data from prior test users.
- Confirm `Drafts` and `Settings` buttons both appear in the top-right.
- Confirm saved/logged/list overlays open full-screen and are not clipped at the bottom.
- Confirm profile search history and recent search data do not leak between accounts on the same device.

## 2. Home Feed
- Cold-launch into Home and confirm the feed appears quickly.
- Tap a game card and confirm `Game Log Preview` opens with blurred background and full overlay height.
- Open review flip cards and confirm they animate/close correctly.
- Tap like, comments, add-to-list, and save-game actions on feed cards.
- Confirm GamerLnd average heart spacing and sizing look correct on `Your Feed` and `Trending`.

## 3. Explore
- Search for a game and confirm search only counts after explicit submit/search action.
- Confirm no joke/placeholder search helper messages appear.
- Confirm recent searches are only your own.
- Use report/flag on a bad result and confirm the overlay sits above the keyboard and can submit cleanly.
- Check `Recently Logged (You)` row for spacing around the GamerLnd average heart.

## 4. Game Log Preview
- Open from feed, Profile `Logged`, and Profile `Saved`.
- Confirm status pill appears once and no duplicate status text appears lower in the card.
- Confirm `View` only appears if you have actually logged that game.
- Confirm `View`, add-to-list, and save-game actions all work.
- Open comments and confirm:
  - only one `X`
  - no preview/status pills leaking into the comments overlay
  - keyboard shifts the bottom of the comments overlay only
- Confirm recent comments preview box appears under likes/comments.

## 5. Game Log Editor
- Open from search, saved tab, and `View` in preview.
- Confirm it opens in read-only `Edit` mode first for existing logs.
- Tap `Edit`, then confirm button becomes green `Save`.
- Make changes, save, and confirm it returns to `Edit` state with a success toast.
- Tap outside with unsaved changes and confirm save / leave / keep editing prompt appears.
- Open review editor and confirm keyboard-down button appears above keyboard.
- Confirm add-to-list and save-game actions behave like feed cards and do not create double `X` overlays.

## 6. Lists
- Create a Standard list from `Profile > Lists`.
- Create a Ranked list and confirm:
  - `Show numbers` toggle works
  - top-item icon choice preview works
- Create a Tiered list and confirm:
  - tier rows appear below `Public`
  - tier labels, block colors, and text colors can be edited before create
- Confirm `Create` opens directly into the new list detail screen.
- In list detail, use `Add Games` and confirm both tabs work:
  - `Search`
  - `Saved Games`
- Confirm tab haptics fire on `Search` / `Saved Games`.
- Pin and unpin a list in Profile `Lists`.

## 7. G Tab / Progression
- Open mini XP bar history and full XP History overlay.
- Confirm header and close button stay pinned at the top.
- Confirm quest/challenge shortcut icons route to the correct G-tab page.
- Open Quest Board and verify all tiles fit in the overlay without bottom clipping.
- Confirm `Hints Available` and `Quests Completed` labels are present.
- Confirm quest hint rarity stays `?` until first completion of that rarity.
- Reset gamification and confirm:
  - XP totals reset
  - mini XP bar resets too
  - quest/challenge surfaces reload correctly

## 8. Daily / Weekly Challenges
- Confirm Daily and Weekly challenges appear quickly and do not stay on `Refreshing challenges...`.
- Confirm daily challenges rotate at the next ET day boundary.
- Confirm weekly challenges are not rotating daily and are keyed to the weekly window.
- Complete at least one logging action and verify the visible challenge progress increments.

## 9. Notifications / Activity
- Open Activity and tap:
  - `All`
  - `Likes`
  - `Comments`
  - `Following`
- Confirm haptics fire and filters switch correctly.
- Confirm no clipped overlays or double-close buttons appear when opening log previews from notifications.

## 10. Settings + Moderation
- Open Settings and confirm there is no Progress Theme picker.
- Confirm toggles exist for:
  - censor profanity in reviews
  - censor profanity in comments
- Confirm profile image rules mention consequences for violations.
- Confirm signup/profile editing still blocks profane usernames/display names.

## 11. Performance / Polish Smoke Test
- Cold launch the app and watch for obvious hangs.
- Let Home idle for 20–30 seconds and confirm it settles.
- Navigate through Home, Explore, Notifications, and Profile for one minute.
- Confirm there are no repeating stutters, overlay clipping issues, or flashing controls.

## 12. Beta Release Go / No-Go
- No blocker crashes during the sweep.
- No overlay clipping on key surfaces.
- No `Refreshing challenges...` stuck state.
- No missing save/add-to-list actions on game logs.
- No cross-account recent-search leakage.
