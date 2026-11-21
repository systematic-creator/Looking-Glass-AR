# Looking Glass platform: accounts, saves, leaderboards, hub, creator tools

Status: **design (doc only, no code yet).** Branch `platform-accounts`,
from `main` @ 10511db.

Direction agreed with the owner, modelled on how Roblox splits things:

1. **An online account backend**: profiles, cloud saves per game, per-game
   leaderboards; later friends and a shared currency.
2. **Looking Glass stays one app**: a profile / progress hub plus the game
   catalog and launcher. Not a second phone app, because handing off
   between apps would restart AR tracking (a new ARCore session, a new
   anchor, calibration again).
3. **Creator tools later, as a separate tool** (like Roblox Studio), not
   inside the phone app.

This doc fixes the shapes that games code against first (`LGProfile`,
`LGSave`, `LGScores`), so that the games, including **Crystal Defense**
(being built on `crystal-defense`), can adopt them before any backend
exists. See [section 3.8](#38-crystal-defense-coordination).

---

## 0. Where we are today

| Thing | Today | Problem |
| --- | --- | --- |
| Placement (board pose, box height) | `user://lg_placement_<id>.cfg` (`ConfigFile`), per game | Fine; becomes a per-profile, device-local slot |
| Mage Run settings | `user://mage_run.cfg` | Ad hoc path, no versioning |
| Bests and scores | `static var session_best` (Stack Tower, Mage Run), `session_score` (Tic-Tac-Toe) | Lost when the app closes |
| Tattoo Studio ink | `static var session_layers` (ink atlases in memory) | Lost when the app closes |
| Crystal Defense | `Wallet` (per-run mana), no saves yet | Needs a save system now |

The manifest already says the game `id` "also names the per-game save
files"; this design keeps that promise.

---

## 1. Architecture at a glance

```
Looking Glass app (one Godot app, one AR session)
├── Hub (Home): Play (catalog) · Profile · Settings          platform/hub/
├── GameHost + LGGame (unchanged contract, plus save / score helpers)
├── LGProfile    who is playing (local guest first, account later)
├── LGSave       per-profile, per-game, namespaced slots on user://
├── LGScores     per-game leaderboards and stats (local first)
└── LGBackend    one interface; adapters: Offline (P1), Supabase (P2+)
        └── Sync engine: outbox, revisions, conflict resolution
```

Rules:

- **Offline-first.** Every read and write goes to `user://` first. The
  backend only syncs. A game never waits on the network to start, save or
  submit a score.
- **Games never talk to the backend.** They use `LGSave` / `LGScores`;
  the platform owns identity, sync and validation. This keeps creator
  games (later) away from network and credentials.
- **One backend interface.** `LGBackend` hides the vendor, so the
  recommendation in section 6 can be swapped without touching games.

---

## 2. The hub (in Looking Glass)

The launcher grows into **Home**, with three tabs. Same app, same AR
session: going from the hub into a game and back never restarts tracking
(the session is created by GameHost as today).

### 2.1 Tabs

| Tab | Content |
| --- | --- |
| **Play** (default) | The current catalog cards, plus a progress line per card ("Best 4210", "12 / 30 stars", "Run in progress") and a "Continue" badge when a game has a resumable run slot. Tapping a card opens the game sheet. |
| **Profile** | Avatar (colour + glyph), display name, "Playing as guest" / signed-in account, totals (play time, games played, sessions), a per-game progress list, and local leaderboards per game. |
| **Settings** | Profile switch (local profiles on this phone), sign in / link (P2), sound, haptics, reduced motion, left-handed HUD, AR (forget saved placements, tracking help), data (export, reset a game, delete profile / account), about and privacy policy, debug overlay. |

**Game sheet** (from a card): art, description, board size and orientation
hint, your progress, the game's leaderboards (local top 10 in P1; friends /
global later), **Play** (and **Continue** if a run slot exists), and "Reset
progress for this game" behind a confirm.

### 2.2 Progress without loading game code

The hub lists games from manifests without loading game scripts (as the
launcher does today). To show progress it reads a **summary** that each
game writes into its save envelope (`save.set_summary(...)`, section 3.4):
`{"line": "Best 4210", "progress": 0.4, "badge": "continue"}`. The hub never
interprets game data.

### 2.3 Layout in both orientations

Same rules as the launcher today (`LGOrientation`, base canvas 1280 x 720
/ 720 x 1280, anchored Controls, everything inside the screen, no overlaps;
`orientation_tests` style checks for each tab).

| | Portrait (720 x 1280+) | Landscape (1280+ x 720) |
| --- | --- | --- |
| Navigation | Bottom tab bar (Play / Profile / Settings), thumb reach | Left rail with the three tabs |
| Play | One wide list row per game (as the launcher is now) | One row of cards (as now), or two rows past 6 games |
| Profile | Header (avatar, name, account chip) on top; stats grid 2 columns; per-game list below | Header + stats on the left half, per-game list and leaderboards on the right |
| Game sheet | Bottom sheet, 85% height, Play pinned at the bottom | Right-side panel, 45% width, Play pinned at the bottom |
| Settings | Grouped list | Grouped list, two columns |

The AR HUD is not shown in the hub. Games keep using `ui_bottom_inset()`
for the AR row once a board is locked.

### 2.4 First launch

1. Hub opens on **Play** with a guest profile already created (no forced
   sign-up; see section 4).
2. A one-line card on Profile offers a name and avatar ("Brave Otter",
   picked from word lists; editable).
3. Sign-in is offered later, at moments with a reason: "Back up your
   progress", "See friends' scores" (P2+). Never before the first game.

---

## 3. Save API for games: `LGSave`

### 3.1 Goals

- Namespaced: **profile → game → slot**. A game can only reach its own
  slots.
- **Versioned schemas with migrations** declared by the game.
- **Autosave hooks** at the moments the platform knows about (pause, app
  background, exit, timer).
- **Atomic writes** to `user://` with a backup and a checksum; a crash or a
  dead battery never leaves a half-written save.
- **JSON-safe data** so the same document syncs to any backend.
- Small and boring: games get a `Dictionary`, not an ORM.

### 3.2 Files on disk

```
user://lg/
  device.json                       device id, schema of this tree
  profiles.json                     local profiles, last active
  profiles/<profile_id>/
    profile.json                    name, avatar, settings, account link
    scores.json                     local leaderboards and stats
    outbox.json                     pending sync operations (P2+)
    games/<game_id>/
      main.json   main.json.bak     the default slot
      run.json    run.json.bak      e.g. a resumable run
      <slot>.blob                   optional binary payloads (e.g. ink)
    device/<game_id>/
      placement.cfg                 device-local only (board pose)
```

Placement stays **device-local** (a board pose means nothing on another
phone). It moves under the profile so two family members keep their own
table setups. The existing `user://lg_placement_<id>.cfg` files are
migrated once at first launch (section 3.7).

### 3.3 Envelope

Each slot file is one JSON object:

```json
{
  "lg": 1,
  "game": "crystal_defense",
  "slot": "main",
  "schema": 3,
  "rev": 17,
  "base_rev": 16,
  "device": "7f2c…",
  "saved_at": 1795212345,
  "game_version": "0.3.0",
  "summary": {"line": "12 / 30 stars", "progress": 0.4},
  "data": { "...": "the game's own data" },
  "sha256": "…of the canonical JSON of data"
}
```

- `schema`: the game's data version (section 3.5).
- `rev` / `base_rev`: local revision counter and the revision last synced;
  used by cloud sync (section 5).
- `sha256`: detects truncation and corruption on load (not a tamper
  defence; see 5.4).

### 3.4 Game-facing API (GDScript shape)

Games reach saves through `LGGame` helpers, so they cannot name another
game's id:

```gdscript
# Manifest (new optional fields)
@export var save_schema: int = 1            # current data version
@export var save_slots: PackedStringArray = ["main"]
@export var autosave_seconds: float = 30.0  # 0 = only on pause / exit

# In a game (extends LGGame)
func _on_board_ready() -> void:
	var s: LGSaveSlot = save_slot()           # "main" by default
	best = int(s.get_value("best", 0))
	var run: LGSaveSlot = save_slot(&"run")
	if run.exists():
		_offer_continue(run.data)

func _on_game_over() -> void:
	var s := save_slot()
	s.set_value("best", maxi(best, score))
	s.set_summary({"line": "Best %d" % maxi(best, score)})
	s.commit()                                # atomic write now
	save_slot(&"run").erase()

# Hooks (all optional)
func _save_defaults(slot: StringName) -> Dictionary        # first run
func _save_migrate(slot: StringName, from: int, data: Dictionary) -> Dictionary
func _on_save_requested(reason: StringName) -> void        # write your state into the slots
func _save_merge(slot: StringName, local: Dictionary, remote: Dictionary, base: Dictionary) -> Dictionary  # P2, optional
```

`LGSaveSlot`:

| Member | Meaning |
| --- | --- |
| `data: Dictionary` | The game's data (after defaults / migration). Mutate it directly or through `set_value`. |
| `get_value(key, default)` / `set_value(key, value)` | Dotted keys allowed (`"levels.meadow_1.stars"`); `set_value` marks the slot dirty. |
| `mark_dirty()` | After mutating `data` directly. |
| `commit() -> Error` | Write now if dirty (atomic). Cheap when clean. |
| `exists() -> bool`, `erase()` | Slot present / delete it (and its backup and blobs). |
| `set_summary(d)` | What the hub shows (section 2.2). |
| `write_blob(name, bytes)` / `read_blob(name)` | Binary payloads stored beside the slot (compressed). Local-only unless the slot's sync policy says otherwise. |
| `sync_policy` | `&"cloud"` (default for `main`) or `&"local"` (default for `run` and blobs). |

Value rules (checked on `set_value` in debug builds and on commit):
`null`, `bool`, `int`, `float`, `String`, `Array`, `Dictionary` with
String keys. Vectors and colours go through `LGSave.pack(v)` /
`LGSave.unpack(v)` (`{"v2": [x, y]}` etc.). Ints above 2^53 are rejected
(JSON numbers). Size caps: 256 KB of JSON per slot, 8 MB of blobs per game
(warnings in debug, hard error at 4x).

### 3.5 Versioned schemas and migrations

- The manifest's `save_schema` is the version the code expects.
- On load, if `envelope.schema < save_schema`, the platform calls
  `_save_migrate(slot, from, data)` once per step (`from` = 1, 2, … up to
  `save_schema - 1`), each returning the next version's data. The result is
  committed with the new `schema` and the pre-migration file is kept as
  `<slot>.v<from>.bak` until the next successful load.
- A save **newer** than the code (`schema > save_schema`, e.g. after a
  downgrade or from a newer phone via sync) is **not touched**: the slot
  opens read-only, the game gets defaults in memory, and the hub shows "This
  progress needs a newer version". Nothing is ever lost by downgrading.
- `mage_run_tests`-style tests per game: load every historical fixture
  (`tests/fixtures/saves/<game>/v1.json …`) and check the migrated result.

### 3.6 Autosave and atomic writes

The platform calls `_on_save_requested(reason)` and then commits every
dirty slot of the running game at:

| Reason | When |
| --- | --- |
| `&"pause"` | `_on_paused` (board unlocked, app paused) |
| `&"background"` | `NOTIFICATION_APPLICATION_PAUSED` / focus out (Android may kill us next) |
| `&"exit"` | Before `_on_exit` (back to the hub) |
| `&"timer"` | Every `autosave_seconds` while dirty and playing |
| `&"rotate"` | Orientation pause (cheap; it is a natural checkpoint) |

Games commit themselves at meaningful moments (wave cleared, game over,
level won). Commits are synchronous and small (JSON under 256 KB writes in
well under a frame on a phone); blobs are written on a worker thread.

**Atomic write**, per slot:

1. Serialize `data` canonically (sorted keys), compute `sha256`, build the
   envelope, `rev += 1`.
2. Write `<slot>.json.tmp` with `FileAccess`, `flush()`, close.
3. Copy the current `<slot>.json` to `<slot>.json.bak` (if present).
4. `DirAccess.rename_absolute(tmp, final)`. On Android and Linux this is a
   single `rename(2)`, atomic on the same filesystem. (On Windows desktop
   builds, verify Godot replaces an existing target; if not, remove then
   rename. That is a dev-only gap.)
5. On load: parse `<slot>.json`; on parse error or checksum mismatch fall
   back to `.bak`, then to defaults, and log a warning for the debug
   overlay. Never crash on a bad save.

Tests (new `save_tests`): kill-mid-write simulation (leave a `.tmp` or a
truncated file and check the fallback), migrations, read-only newer schema,
value validation, autosave triggers through GameHost, namespacing (a game
cannot open another game's slot), profile isolation.

### 3.7 Migrating today's games

| Game | Slot `main` (cloud) | Slot `run` (local) | Notes |
| --- | --- | --- | --- |
| Stack Tower | best height, style | none | Style is a game setting |
| Mage Run | best score, total coins, settings (from `user://mage_run.cfg`) | optional: none for now (runs are short) | Leaderboard `best_score` |
| Tic-Tac-Toe | board size, score history per size | none | |
| Tattoo Studio | per model: scale, yaw, last tools | per model ink atlas as blobs (`ink_<model>.blob`, local) | Ink is large: local first; cloud later as an opt-in |
| Competitive Evolution | none | none | Placeholder |
| Placement (platform) | device-local | | Moved from `user://lg_placement_<id>.cfg` |

`static var session_*` stay as in-memory caches, filled from the slot at
`_on_board_ready`.

### 3.8 Crystal Defense coordination

Crystal Defense (worktree `/workspace/lg-crystal-defense`, branch
`crystal-defense`) is the first game to need real saves. Proposed shape, to
agree with that worker before either side codes it:

- **Slot `main`** (`sync_policy` cloud, `save_schema` 1):

  ```json
  {
    "campaign": {
      "unlocked": ["meadow_1", "meadow_2"],
      "levels": {
        "meadow_1": {"stars": 3, "best_wave": 20, "best_time_ms": 412000, "wins": 2}
      }
    },
    "totals": {"waves_cleared": 140, "towers_built": 610, "play_ms": 7200000},
    "settings": {"autostart": true, "speed": 2}
  }
  ```

  Summary: `{"line": "12 / 30 stars", "progress": stars / max_stars}`.
- **Slot `run`** (`sync_policy` local): a resumable snapshot, committed at
  the **end of each wave** (the phase machine's build phase is a clean
  checkpoint; mid-wave state is not saved), erased on win / loss:

  ```json
  {
    "level": "meadow_2", "wave": 7, "seed": 91823, "rng_state": "…",
    "crystal_hp": 14,
    "wallet": {"balance": 230, "total_earned": 1210, "total_spent": 980},
    "towers": [{"kind": "arc", "cell": [3, 5], "level": 2, "target": "first"}],
    "autostart_streak": 2
  }
  ```

- **`Wallet`** gets `to_save() -> Dictionary` / `static from_save(d)`
  (balance and totals; the transaction log is not saved). This mana wallet
  is **per run** and stays in the game. The later **shared currency** is a
  separate, server-authoritative platform ledger (`LGWallet`, P4). The two
  must not be mixed: a game can award shared currency only through a
  platform call that the server checks.
- **Leaderboards** (manifest `leaderboards`, section 4.2): `best_wave_<level>`
  (higher is better) and `fastest_<level>` (time in ms, lower is better).
- Until `LGSave` lands, Crystal Defense can write the same JSON through a
  thin local adapter with the same `save_slot()` / `commit()` calls, so
  switching later is a one-file change.

---

## 4. Identity and leaderboards

### 4.1 Identity model

```
Device ──has── Local profiles (1..4) ──may link to── Account (P2)
                                                       └── Identities: guest (anonymous), Google, email, (Apple, iOS)
```

- **Guest / local profile first (P1).** A profile is a random UUID v4 with a
  display name and avatar, created on first launch. No network, no
  personal data. Up to 4 local profiles per phone (a family sharing one
  phone), switched in Settings.
- **Account (P2).** Turning on cloud features creates a backend user for
  the profile: first an **anonymous** backend user (no personal data; lets
  sync start), later **upgraded** by linking a real identity.
- **Sign-in providers**, in order:
  1. **Google** (Android Credential Manager, an OpenID ID token; the
     backend verifies it). The natural default on Android.
  2. **Email** one-time code or magic link (no passwords to store).
  3. **Sign in with Apple** if and when there is an iOS build (Apple requires
     it when other social logins are offered).
  4. **Google Play Games Services** later, only if achievements or Play's
     player ID are wanted; it is not an OpenID login, so it needs a
     server-side auth-code exchange.
- **Linking.** One account can hold several identities. Signing in on a new
  phone with the same Google account restores the account's profile.
  Linking an identity already attached to another account asks which
  account to keep and merges (section 5.3).
- **First sign-in with existing guest progress:** if the account is empty,
  the guest's data is uploaded. If both have data, per game: keep this
  phone's, keep the account's, or merge (the game's `_save_merge`, or the
  defaults in 5.3). Nothing is discarded silently: the losing copy is kept
  as a conflict backup for 30 days.
- **Sign-out** keeps the local profile as a guest copy, or removes it from
  this phone if the user asks.

`LGProfile` (platform, read-only to games): `id`, `display_name`,
`avatar`, `is_guest()`, `account_id` (empty offline). Games get
`profile()` on `LGGame`; they never see emails or tokens.

### 4.2 Leaderboards and score submission

Declared in the manifest so the hub can show them without loading the game:

```gdscript
# LGLeaderboardDef (Resource), in manifest.leaderboards: Array[LGLeaderboardDef]
id: StringName            # "best_score", "fastest_meadow_1"
display_name: String
order: int                # DESCENDING (higher is better) or ASCENDING (times)
format: StringName        # &"int", &"time_ms", &"distance_cm", &"height_cm"
reset: StringName         # &"never" (P1); &"weekly" / &"daily" later
max_value: int            # plausibility ceiling (server check, 5.4)
```

Game-facing calls (on `LGGame`, always against the current game's id):

```gdscript
var receipt: LGScoreReceipt = submit_score(&"best_score", score, {
	"seed": seed, "duration_ms": run_ms, "game_version": manifest.version,
})
# receipt.personal_best (bool), receipt.local_rank (int), receipt.id (idempotency key)

var top: Array[LGScoreEntry] = await top_scores(&"best_score", LGScores.Scope.LOCAL, 10)
var best: LGScoreEntry = personal_best(&"best_score")
record_stat(&"waves_cleared", 1)        # summed per profile (and globally, later)
```

- **Values are ints** (milliseconds, centimetres, points): no float
  ordering surprises across devices.
- **Local (P1):** `scores.json` per profile keeps the top 20 per board, the
  personal best, and every local profile's best (a "this phone" board for
  families). `LGScores.Scope.LOCAL` reads it synchronously (the `await` is
  for API parity).
- **Cloud (P3):** every submission also goes into the **outbox** with an
  idempotency key and is uploaded when online; `FRIENDS` and `GLOBAL`
  scopes then read from the backend (cached for offline viewing).
- `LGScoreEntry`: `rank`, `value`, `display_name`, `avatar`, `is_self`,
  `submitted_at`, `verified` (server checked).

---

## 5. Cloud sync

### 5.1 Model

- Each `(account, game, slot)` with `sync_policy = cloud` is one server
  document: `data` (JSON), `schema`, `rev`, `updated_at`, `device_id`,
  `summary`.
- The phone keeps the local file as the working copy plus `base_rev`, the
  server revision it last agreed with.
- **Sync points:** app start, back in the hub, 10 s after a commit
  (debounced), app background (best effort), and a manual "Sync now" in
  Settings. Never while a game is mid-frame-critical (uploads run on a
  thread; the HTTP client is async).
- **Outbox:** score submissions, stat increments and (P4) currency
  operations are queued as operations with idempotency keys, uploaded in
  order, and retried with backoff. Saves are not queued as operations; the
  latest document wins its slot (5.2).

### 5.2 Upload and download

- **Upload:** `PUT slot (base_rev = N, data, schema)`. The server accepts if
  its `rev == N` and stores `rev = N + 1`. Otherwise it answers **conflict**
  with its copy.
- **Download:** on start the phone fetches the revisions of all its slots
  (one request). A slot newer on the server and clean locally is replaced
  (after migration if its schema is older; kept read-only if newer).
- A save from a newer schema on the server never overwrites an older app's
  local copy (3.5); the app asks to update.

### 5.3 Conflict resolution

Conflicts happen when two phones (or a phone and a reinstall) both changed
the same slot since the last sync. In order:

1. **Game merge.** If the game implements `_save_merge(slot, local, remote,
   base)`, its result is uploaded as the new revision. Best for real
   progress (Crystal Defense: union of unlocked levels, max stars and best
   wave per level, summed totals since `base`).
2. **Declared field rules** (no code): the manifest can list merge rules
   per key path, e.g. `{"campaign.levels.*.stars": "max",
   "campaign.unlocked": "union", "totals.*": "sum_since_base",
   "settings": "newest"}`. Unlisted keys fall to 3.
3. **Default: newest wins** (by `saved_at`, ties by `rev`), and the other
   copy is kept server-side as a **conflict backup** for 30 days, restorable
   from Settings. If the losing copy had more play time (`play_ms`), the hub
   asks instead of deciding.

`run` slots are local-only by default, so mid-run snapshots never conflict.

### 5.4 Anti-tamper basics for leaderboards

Assume the client is fully readable and modifiable (any key shipped in the
APK can be extracted). So:

- **No secrets in the client.** Submissions are authenticated by the
  signed-in user's session token only; validation happens on the server.
- **Server checks per submission:** the value is within `max_value` and
  plausible for the evidence (for example Mage Run: score <= f(duration_ms,
  speed curve); Stack Tower: height <= layers x max slab height; times above
  a floor); the `game_version` is known; rate limits per user and board;
  idempotency keys stop replays.
- **Mark, don't trust.** Entries that pass get `verified = true`.
  Suspicious ones are kept but hidden from global boards pending review;
  users with repeated rejects get shadow-limited (visible only to
  themselves).
- **Replays later (P3+).** Games with a seeded, node-free simulation (Mage
  Run's `MageRunSim`, Stack Tower's placement math) can upload a compact
  input log; a server job re-simulates top-N entries headlessly and
  confirms the score. This is the strong defence and it falls out of the
  existing test-friendly architecture.
- **Device integrity (optional, P3+):** Google Play Integrity verdicts on
  submissions for global boards.
- **Cloud saves** are protected only by account auth (a player may edit
  their own save; that only affects them). Anything that affects others
  (scores, shared currency) is validated server-side.

---

## 6. Backend options

| Option | What it is | Fit for Looking Glass | Cost notes (checked Nov 2026; verify before buying) |
| --- | --- | --- | --- |
| **Supabase** | Hosted Postgres + Auth (anonymous, Google ID token, email OTP, Apple) + row-level security + Edge Functions (TypeScript) + storage. Open source, self-hostable. | Saves as JSONB rows, leaderboards as SQL (indexes, window functions), score validation in Edge Functions, account deletion as one transaction. Community Godot clients, or plain HTTPS (`HTTPRequest`) against its REST API. | Free: 50k MAU, 500 MB DB, 1 GB files, 2 projects, but **paused after 1 week of inactivity**. Pro from **$25/month** (100k MAU, 8 GB disk, daily backups, never paused). |
| **Firebase** | Firestore (documents), Firebase Auth, Cloud Functions, Google-native. | Great Android and Google sign-in story. Leaderboard queries (rank of a player, top N per period) are awkward in a document store; costs scale with reads (every leaderboard view). Godot support via a community addon. | Spark (free): Firestore 1 GiB, 50k reads / 20k writes per day. Blaze: pay as you go (about $0.03 / 100k reads, $0.09 / 100k writes), Functions need Blaze, **no hard spending cap**. |
| **Nakama** (Heroic Labs) | Open-source game server: accounts, device / Google / Apple auth, storage objects, leaderboards and tournaments, friends, groups, chat, realtime multiplayer, server code in Go / TS / Lua. Official Godot client. | The most "game-shaped" option: leaderboards, friends, wallets and realtime are built in, which fits the later **shared-anchor multiplayer** goal. But self-hosting means running and patching a server plus its database. | Self-host: a small VPS + Postgres (roughly $10-30/month) plus ops time. Heroic Cloud (managed) is quoted by CPU through a calculator, priced for studios. |
| **PlayFab** (Microsoft) | Managed game backend: player accounts, player data, statistics / leaderboards, economy, CloudScript. | Feature-complete, but no official Godot SDK (REST only), metered pricing, and the free Development Mode caps at **1,000 lifetime players per title**. Foundation Mode (free core services) applies to games shipping on the Xbox Store, not this Android app. | Pay-as-you-go meters (for example about $7 per million profile writes), Standard **$99/month**, Premium $1,999/month. |
| **Custom** (for example a small Go / Node service + Postgres on a VPS or Cloud Run) | Exactly what we need. | Most control and cheapest at tiny scale, but auth, token verification, deletion, backups, abuse handling and security are all on us. The wrong use of a solo developer's time now. | $5-20/month infra, plus a lot of engineering time and on-call. |

### Recommendation (solo developer)

**Supabase, behind the `LGBackend` interface, plain HTTPS from Godot.**

- It covers P2-P3 with managed pieces: anonymous users that upgrade to
  Google / email accounts (exactly the guest-first model), JSONB documents
  with a `rev` column for optimistic concurrency, SQL leaderboards, Edge
  Functions for score validation and account deletion, and row-level
  security so a user can only read and write their own saves.
- Postgres keeps an exit path: it is self-hostable and the data is
  portable; nothing in the game code depends on Supabase.
- Cost: develop on the **free** tier (fine for testing; it pauses after a
  week idle, so keep a keep-alive or accept the resume), move to **Pro
  ($25/month)** before any public test so the project never pauses and has
  backups. Expect $25-40/month until tens of thousands of monthly players.
- Talk to it with Godot's `HTTPRequest` and a small `SupabaseBackend`
  adapter (auth endpoints, REST for tables, Edge Function calls) rather than
  a third-party addon, to keep the dependency surface small and testable
  with a fake backend (like `FakeARBridge` today).
- **Revisit at P4 / multiplayer:** if realtime shared-anchor play becomes
  real, Nakama is the better home for matchmaking and realtime state. The
  `LGBackend` split lets the multiplayer service be Nakama while accounts and
  saves stay where they are, or move everything with a migration.

---

## 7. Privacy, data deletion and age

- **Collect the minimum.** P1 collects nothing (all local). P2 stores: an
  account id, linked identity ids and the email the provider returns (only
  if email sign-in is used), display name, avatar, saves, scores and stats,
  coarse device info for sync (`device_id`, app version). No location, no
  contacts, no advertising id. **AR camera frames and room geometry never
  leave the phone**, and saves must not contain them (placement is
  device-local and does not sync).
- **Store disclosures.** A privacy policy (linked in Settings and on the
  store listing) and an accurate Google Play **Data safety** form, updated
  with each phase.
- **Deletion.** Google Play requires apps with account creation to offer
  account deletion **in the app and through a web link**. Settings ->
  Delete account removes the account, identities, saves, scores and conflict
  backups server-side (one Edge Function, one transaction) and local copies
  on this phone; leaderboard rows are removed, not anonymised. Also: delete
  a local profile, reset one game, and **export** my data (a JSON file of
  all slots and scores) for access / portability requests (GDPR, CCPA).
- **Retention.** Conflict backups 30 days; deleted accounts purged from
  backups within the backup window (7 days on Supabase Pro). Logs without
  personal data.
- **Age.** Decide the audience first (open question 1):
  - If the app is **directed at children under 13** (or we learn a player is
    under 13), US **COPPA** applies: verifiable parental consent before
    collecting personal information (which includes persistent identifiers
    used beyond internal operations, and free-text names or photos), a
    children's privacy notice, and data minimisation. The FTC's amended
    COPPA rule (2025) adds written data-retention and security
    requirements. On Google Play this also means the **Families policy**
    (Designed for Families requirements, limits on SDKs).
  - In the EU and UK the age of digital consent is 13-16 depending on the
    country (GDPR Art. 8), and the UK Age Appropriate Design Code expects
    high-privacy defaults for under-18s.
  - **Practical design:** a neutral age prompt (birth year, no default)
    before sign-in or any social feature. Under 13 (or local threshold):
    **Kids mode**, local profiles only, no account, no global leaderboards
    (this-phone boards only), names chosen from word lists only, no friends
    or chat; cloud backup only through a parent's account flow if we ever
    build one. 13+: the normal flow, still with no free-text chat at first.
  - Display names: word-list generated by default; free-text names (P2+)
    go through a profanity filter and a report button.
- **Security basics.** Row-level security on every table, server-side
  validation for anything shared, tokens in the platform only (never in
  game code), HTTPS only, secrets only in Edge Function config.

---

## 8. Creator tools roadmap (later, a separate tool)

The Roblox split: **Studio** (desktop authoring) is separate from the
**player app** (Looking Glass), and the **platform** (accounts, catalog,
review) sits between them.

### 8.1 What exists already

Games are **manifest-driven** (`LGGameManifest`: id, board size, box,
orientation, entry scene; `GameCatalog.register()` already notes "downloaded
creator games can register the same way from user://"), with a small
contract (`LGGame` hooks) and strong headless tests (containment in the box,
HUD layout in both orientations, budgets). That is the base of a creator
platform.

### 8.2 The hard constraint: no downloaded GDScript

Running downloaded GDScript would give creator code the whole engine (file
system, network, other games' saves), and Google Play's policy forbids apps
from downloading executable code outside Play, with an exception for code
running in a sandboxed interpreter or VM without direct access to Android
APIs. So creator games must be:

1. **Data first:** packages of scenes, models, textures, sounds and
   manifest data built from **platform-provided building blocks** (board
   grids, phase machines, wallets, placement, flow fields: the
   `platform/game` and `platform/sim` pieces Crystal Defense is building now
   are exactly these blocks).
2. **Scripted in a sandbox:** a small interpreted language with only the
   Looking Glass API exposed (no file or network access, CPU and memory
   budgets per frame). Options to evaluate: an embedded Luau or Lua
   interpreter as a GDExtension (Roblox's model), or a node-graph / event
   rules system compiled to data (simplest to secure, less expressive).
3. **Saves and scores** only through `LGSave` / `LGScores`, namespaced by the
   package id, with the same caps.

### 8.3 Pieces

| Piece | Shape |
| --- | --- |
| **Package format** `.lgpkg` | A zip: `manifest.json` (the manifest as data), assets, sandbox scripts, a content hash, the creator's signature. Versioned; the app verifies the platform's signature before loading. |
| **Looking Glass Studio** | A desktop app built on the Godot editor (or a Godot app) with a board and box editor, the building blocks, a script editor for the sandbox language, and **play-in-box preview** (the "Play without AR" camera, plus a phone link over USB / Wi-Fi to preview in real AR). Publish uploads a package. |
| **Review pipeline** | Automated: manifest validation, size and asset limits, headless run of the platform tests (inside the box, HUD inside the screen in both orientations, triangle and draw-call budgets, no crashes over a scripted session). Then human review and an age rating questionnaire. Then staged rollout. Reporting and takedown in the app; creators can unpublish. |
| **Catalog service** | The backend lists approved packages; the hub's Play tab shows bundled plus downloaded games; packages download to `user://packages/`. |

Order: (a) the package format for **first-party** games (proves loading
from `user://`), (b) building blocks plus the sandbox language, (c) Studio
alpha for invited creators, (d) review pipeline, (e) public publishing.
Revenue sharing and creator payouts are out of scope until there is an
audience.

---

## 9. Milestones

| Phase | Scope | Done when |
| --- | --- | --- |
| **P1: local profile, save API, hub** | `LGProfile` (guest, up to 4 local), `LGSave` (slots, envelope, migrations, autosave hooks, atomic writes, blobs), `LGScores` local (manifest leaderboards, local top 20, stats), hub (Play / Profile / Settings, game sheet, progress summaries) in both orientations; migrate Stack Tower, Mage Run, Tic-Tac-Toe, Tattoo Studio (settings and local ink blobs) and placement files; Crystal Defense adopts `main` and `run` slots; data export and per-game reset; `save_tests` and hub layout tests | Bests, progress and Tattoo ink survive an app restart; a corrupted or half-written save falls back cleanly; hub passes the orientation layout checks; everything works in airplane mode |
| **P2: accounts and cloud saves** | `LGBackend` interface, fake backend for tests, Supabase adapter; anonymous account per profile, Google and email sign-in, linking; cloud sync of `main` slots with revisions, merge hooks and conflict backups; in-app and web account deletion; privacy policy and Data safety update; age prompt and Kids mode | Progress moves to a second phone by signing in; conflicts resolve as specified; deleting an account removes all server data |
| **P3: online leaderboards** | Outbox submissions, server validation (bounds, rates, evidence), friends-less global and "this week" boards, verified flags, review queue; optional replay verification for Mage Run | Global boards show verified scores; obviously forged submissions are rejected in tests |
| **P4: friends and shared currency** | Friends (invite codes, no search for minors), friends' boards; a server-authoritative shared currency ledger (`LGWallet`, earn rules on the server, idempotent operations); no purchases until the IAP questions are answered | Friends see each other's scores; currency balances cannot be changed by editing a save |
| **P5: creator tools alpha** | `.lgpkg` for first-party games, sandbox scripting prototype, Studio alpha, automated review checks | A non-bundled game installs from a package and passes the platform tests |

Each phase ships with headless tests like today's suites, and the APK keeps
working fully offline.

---

## 10. Open questions

1. **Audience:** is Looking Glass aimed at (or likely to have) children
   under 13? This decides Kids mode, COPPA and the Families policy, and
   whether global leaderboards and free-text names exist at all.
2. **Shared currency:** earn-only, or also bought with real money? Buying
   adds Google Play Billing (fees, refunds, receipts), stricter rules for
   minors and an economy design pass.
3. **iOS:** is an iPhone build planned? It adds Sign in with Apple and an
   ARKit bridge, and affects the choice of sign-in providers now.
4. **Multiplayer timing:** if shared-anchor multiplayer (two phones, one
   board) is within about a year, should P2 start on Nakama instead of
   Supabase to avoid running two backends?
5. **Tattoo ink in the cloud:** ink atlases are megabytes per model. Keep
   them local-only, or offer opt-in cloud backup (storage cost and upload
   size)?
