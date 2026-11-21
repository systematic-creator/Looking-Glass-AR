# Looking Glass platform: accounts, saves, leaderboards, hub, creator tools

Status: **design (doc only, no code yet).** Branch `platform-accounts`,
from `main` @ 10511db.

All open questions are answered (D1-D8 below).

Direction agreed with the owner, modelled on how Roblox splits things:

1. **An online account backend**: profiles, cloud saves per game, per-game
   leaderboards; later friends and a shared currency.
2. **Looking Glass stays one app**: a profile / progress hub plus the game
   catalog and launcher. Not a second phone app, because handing off
   between apps would restart AR tracking (a new ARCore session, a new
   anchor, calibration again).
3. **Creator tools later, as a separate tool** (like Roblox Studio), not
   inside the phone app.

### Decisions (owner, 20 Nov 2026)

| # | Question | Decision |
| --- | --- | --- |
| D1 | Audience | **13+ only.** No under-13 audience: no Kids mode, COPPA out of scope. A basic age gate and terms note (13+) before sign-in. Global leaderboards and display names are fine, with basic name filtering (section 7). |
| D2 | Shared currency | **Earned and purchasable eventually, earn-only to start.** Purchase sections are visible in the UI behind a "Coming soon" sign; the store UI and the Google Play Billing integration are designed now and built later (section 10). |
| D3 | iOS | **Out of scope** for now (no Apple device for signing / ARKit). Android only; no Sign in with Apple. |
| D4 | Multiplayer | **Shared-board multiplayer is likely within about a year.** The backend recommendation is therefore **Nakama**, behind the `LGBackend` interface, with Supabase as the alternative (section 6; multiplayer in section 9). |
| D5 | Tattoo ink | **Phone only** for now (local blobs, never synced). |
| D6 | Multiplayer modes | **Same-room and remote, per game.** Each manifest declares the modes it supports; remote play shows the other players on a **mirrored board on each player's own table**, with avatars and ghost hands (section 9.4). |
| D7 | Hosting region | **US.** One Nakama server in a central US region (section 6). GDPR basics only matter once EU players join (section 7). |
| D8 | Currency name | **Shards.** Starter earn rates per game and a daily cap in section 10.1. Crystal Defense's in-run **mana** stays a separate, per-run game resource. |

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
├── LGWallet     shared currency (server-authoritative, P5)
├── LGMatch      multiplayer session, same room or remote (section 9)
└── LGBackend    one interface; adapters: Offline (P1), Nakama (P2+),
        │        Supabase as the alternative
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

The launcher grows into **Home**, with four tabs. Same app, same AR
session: going from the hub into a game and back never restarts tracking
(the session is created by GameHost as today).

### 2.1 Tabs

| Tab | Content |
| --- | --- |
| **Play** (default) | The current catalog cards, plus a progress line per card ("Best 4210", "12 / 30 stars", "Run in progress") and a "Continue" badge when a game has a resumable run slot. Tapping a card opens the game sheet. |
| **Profile** | Avatar (colour + glyph), display name, "Playing as guest" / signed-in account, totals (play time, games played, sessions), a per-game progress list, and local leaderboards per game. |
| **Store** | The shared currency balance, ways to earn it, things to spend it on, and the purchase section behind "Coming soon" (section 10). |
| **Settings** | Profile switch (local profiles on this phone), sign in / link (P2), age and terms (13+), sound, haptics, reduced motion, left-handed HUD, AR (forget saved placements, tracking help), data (export, reset a game, delete profile / account), about and privacy policy, debug overlay. |

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
| Navigation | Bottom tab bar (Play / Profile / Store / Settings), thumb reach | Left rail with the four tabs |
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
| Tattoo Studio | per model: scale, yaw, last tools | per model ink atlas as blobs (`ink_<model>.blob`, local) | **Ink stays on the phone (D5)**: never synced; reinstalling or a new phone starts with clean skin |
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
  separate, server-authoritative platform ledger (`LGWallet`, P5, a Nakama
  wallet). The two
  must not be mixed: a game can award shared currency only through a
  platform call that the server checks.
- **Multiplayer later** (section 9): keep the simulation deterministic and
  free of nodes where possible (fixed tick from `SimClock`, seeded RNG,
  inputs as commands such as "build arc at (3, 5)"), so a co-op mode can run
  the same simulation in a Nakama authoritative match.
- **Leaderboards** (manifest `leaderboards`, section 4.2): `best_wave_<level>`
  (higher is better) and `fastest_<level>` (time in ms, lower is better).
- Until `LGSave` lands, Crystal Defense can write the same JSON through a
  thin local adapter with the same `save_slot()` / `commit()` calls, so
  switching later is a one-file change.

---

## 4. Identity and leaderboards

### 4.1 Identity model

```
Device ──has── Local profiles (1..4) ──may link to── Account (P2, a Nakama user)
                                                       └── Identities: device (guest), Google, email
```

- **Guest / local profile first (P1).** A profile is a random UUID v4 with a
  display name and avatar, created on first launch. No network, no
  personal data. Up to 4 local profiles per phone (a family or friends
  sharing one phone), switched in Settings.
- **Account (P2).** Turning on cloud features creates a Nakama user for the
  profile with **device authentication** (`authenticate_device` with a
  per-profile random id stored in `profile.json`, not a hardware id). That
  is a real account with no personal data, so sync and leaderboards work
  for guests too.
- **Upgrading and linking** (Nakama link APIs; the account id never
  changes, so saves and scores stay):
  1. **Google**: Android Credential Manager returns a Google ID token;
     `link_google` attaches it to the guest account (or
     `authenticate_google` on a new phone restores it). The default on
     Android.
  2. **Email + password**: `link_email` / `authenticate_email` (Nakama
     stores a bcrypt hash). Magic links or one-time codes are not built in;
     add them later with a custom auth flow if wanted.
  3. **Google Play Games Services** only if achievements or Play's player
     id are wanted later (it needs a server-side auth-code exchange in a
     custom auth hook).
  4. **Apple: out of scope (D3).**
- **Linking conflicts.** Linking an identity already attached to another
  account asks which account to keep and merges (section 5.3); the other
  account is then deleted.
- **First sign-in with existing guest progress:** if the account is empty,
  the guest's data is uploaded. If both have data, per game: keep this
  phone's, keep the account's, or merge (the game's `_save_merge`, or the
  defaults in 5.3). Nothing is discarded silently: the losing copy is kept
  as a conflict backup for 30 days.
- **Sign-out** keeps the local profile as a guest copy, or removes it from
  this phone if the user asks.
- **Age gate and terms (D1):** before the first sign-in (and before any
  online feature for a guest) the app asks for a birth year and shows the
  terms and privacy note: Looking Glass is for **13 and over**. Under 13:
  online features stay off and the profile stays local; no data is sent.

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
  scopes then read from the backend (cached for offline viewing). On
  Nakama each `LGLeaderboardDef` becomes a server-created leaderboard named
  `<game_id>.<board_id>` with sort order from `order`, operator `best`, an
  optional cron reset (`reset`), and **authoritative** set, so clients
  cannot write records directly: the client calls an RPC
  (`lg_submit_score`) that validates (5.4) and then writes the record.
  Weekly boards can use Nakama tournaments.
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
- **Outbox:** score submissions, stat increments and (P5) currency
  operations are queued as operations with idempotency keys, uploaded in
  order, and retried with backoff. Saves are not queued as operations; the
  latest document wins its slot (5.2).

**On Nakama:** a slot is a **storage object**: collection
`save.<game_id>`, key `<slot>`, owner the user, value the envelope (JSON
object), `permission_read = 1` (owner only), `permission_write = 1`.
Nakama gives every object a **version** (a hash) and supports conditional
writes: writing with the version you last read fails if the object changed
since, which is exactly the `base_rev` check below; `version = "*"` means
"create only if absent". The phone stores the last Nakama version next to
`base_rev`. Conflict backups go to collection `save_conflict.<game_id>`
(server-written, 30-day cleanup job).

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
| **Nakama** (Heroic Labs, Apache 2.0) | Game server: accounts (device, Google, email, custom) with linking, storage objects with versions and permissions, leaderboards and tournaments, friends and groups, wallets with a ledger, in-app purchase validation, matchmaker, **relayed and authoritative realtime matches**, server code in Go, TypeScript or Lua. Official Godot 4 client in GDScript. | The only option that covers every phase including **shared-board multiplayer (D4)** in one service. Costs: a server and database to run, and server code in a second language. | Self-host: Docker image plus Postgres on a small US VPS, roughly **$20-35/month**. Heroic Cloud (managed): priced per Nakama CPU and database CPU through a calculator, no public list price, aimed at studios; support plans from $2,000. |
| **Supabase** (alternative) | Hosted Postgres + Auth (anonymous, Google ID token, email OTP) + row-level security + Edge Functions + storage. Open source, self-hostable. | Excellent for accounts, saves and SQL leaderboards with no server to run. No game realtime: multiplayer would need a second service. | Free: 50k MAU, 500 MB DB, paused after 1 week idle. Pro from **$25/month**. |
| **Firebase** | Firestore, Firebase Auth, Cloud Functions. | Good Google sign-in; leaderboard queries awkward in a document store; read-metered costs; no game realtime. Community Godot addon. | Spark free: 1 GiB, 50k reads / 20k writes per day. Blaze pay as you go, no hard spending cap. |
| **PlayFab** | Managed game backend. | No official Godot SDK (REST only); free Development Mode caps at 1,000 lifetime players per title; Foundation Mode only for Xbox Store games. | Pay-as-you-go meters, Standard $99/month. |
| **Custom** | Own service + Postgres. | Auth, deletion, abuse handling and realtime all on us. | $5-20/month infra, a lot of engineering time. |

### Recommendation (solo developer): Nakama, behind `LGBackend`

**Why.** Shared-board multiplayer within a year (D4) needs a realtime
match server. Nakama has it alongside everything else this doc needs:
device-auth guests that link Google and email later, versioned storage
objects for saves, authoritative leaderboards, friends, a wallet with a
ledger for the shared currency, and Google purchase validation for D2.
One backend, one account system, one place for anti-cheat code.

**What stays the same.** Games still only see `LGSave`, `LGScores`,
`LGWallet` and `LGMatch`. `LGBackend` has an offline adapter (P1, tests)
and a `NakamaBackend` adapter built on the official
[nakama-godot](https://github.com/heroiclabs/nakama-godot) client
(`addons/com.heroiclabs.nakama/`, used only inside `platform/backend/`).
A `FakeBackend` (like `FakeARBridge`) drives the headless tests.

**Hosting, in order:**

1. **Development:** Nakama + Postgres with Docker Compose on the box or a
   laptop (API on port 7350, console on 7351). Free.
2. **Test and launch: self-host on one VPS in a central US region (D7).**
   **Chicago or Dallas** (for example Vultr, Akamai / Linode) or **GCP
   `us-central1` (Iowa)**: a central location keeps round trips to both
   coasts around 30-50 ms, which suits remote matches. 2 vCPU / 4 GB RAM
   (about $20-30/month at those providers; an East-coast-only box such as
   Hetzner Ashburn is cheaper but adds latency for the West coast). Docker
   Compose with
   Nakama, Postgres and Caddy for TLS, nightly `pg_dump` to object storage,
   uptime monitoring. About **$20-35/month** with backups, plus a few hours a month of
   upkeep (OS and Nakama updates). Open-source Nakama runs as a **single
   node** (clustering is an Enterprise feature); one node handles thousands
   of concurrent players for this kind of game. Change the default server
   key, the console password and the `runtime.http_key` before going public.
3. **Heroic Cloud when it pays for itself:** move when uptime, scaling or
   on-call time matter more than the bill (managed database, backups,
   scaling, Enterprise clustering). Quote from the calculator first; it is
   priced for studios, so expect hundreds of dollars a month, not tens.

**Server code.** One module set in **TypeScript** (Nakama's JS runtime:
quick to iterate, no plugin build matching the server version), with Go
reserved for hot authoritative match loops if profiling ever demands it.
Lua is also supported but the TypeScript tooling is better. Modules
register:

- RPCs: `lg_submit_score` (validation, 5.4), `lg_wallet_earn` (server
  rules), `lg_purchase_validate` (D2, later), `lg_delete_account` cleanup,
  `lg_match_create` (board session, section 9);
- leaderboards from a config file generated from the game manifests;
- authoritative match handlers per game mode (section 9.3);
- before / after hooks: name filtering on account updates (section 7),
  rate limits on writes.

**Alternative: Supabase.** If multiplayer is dropped or delayed past
P4, Supabase is the simpler service to run for accounts, saves and
leaderboards (no server to maintain; $25/month Pro). The `LGBackend`
interface keeps that switch possible: the storage-object, leaderboard and
wallet shapes in this doc map onto Postgres tables (`rev` column for the
version check, SQL ranks, an Edge Function per RPC).

## 7. Privacy, data deletion and age

- **Collect the minimum.** P1 collects nothing (all local). P2 stores: the
  Nakama account id, linked identity ids, an email only if email sign-in
  is used, display name, avatar, birth year (for the 13+ gate), saves,
  scores, stats and wallet ledger, and coarse device info for sync
  (`device_id`, app version). No location, no contacts, no advertising id.
  **AR camera frames and room geometry never leave the phone**; placement is
  device-local and Tattoo ink stays on the phone (D5). In multiplayer, only
  board-space game state goes over the network (section 9), never camera
  images or the room.
- **Store disclosures.** A privacy policy and terms (linked in Settings and
  on the store listing) and an accurate Google Play **Data safety** form,
  updated with each phase.
- **Deletion.** Google Play requires apps with account creation to offer
  account deletion **in the app and through a web link**. Settings ->
  Delete account calls Nakama's account delete (which removes the user and
  their data) plus an after-hook that removes anything else keyed by the
  user (leaderboard records, conflict backups); a small web page with the
  same flow covers the web link. Also: delete a local profile, reset one
  game, and **export** my data (a JSON file of all slots, scores and the
  wallet ledger) for access / portability requests (GDPR, CCPA).
- **Retention.** Conflict backups 30 days; deleted accounts purged from
  database backups within the backup rotation (keep it at 7-14 days). Logs
  without personal data.
- **Age (D1): 13+ only.** No under-13 audience, so no Kids mode and COPPA is
  out of scope. A neutral age gate (birth year, no default) and a terms
  note before sign-in or any online feature. Under 13: online features stay
  off. The store listing's target audience is 13+.
- **Region (D7): US first.** Data is stored on the US server; the privacy
  policy follows US norms (CCPA-style access and deletion, both already
  covered above). **Only if EU players join** (the store listing is opened
  to EU countries): add the GDPR basics: a lawful basis per data use (saves
  and scores as contract necessity; no ads or analytics, so no consent
  banners), the age of digital consent (13-16 by country, GDPR Art. 8,
  which may need parental consent for younger EU teens or a higher gate
  there), a note on transfers to the US (standard contractual clauses with
  the host), and a contact for data requests. Until then, limit the Play
  listing to the countries the policy covers.
- **Display names and leaderboards.** Global leaderboards and free-text
  display names are allowed. Names: 3-16 characters, letters, digits,
  spaces and `_-`; a server-side filter (word list with leetspeak
  normalisation, in a Nakama before-hook) rejects slurs and profanity;
  generated names ("Brave Otter") remain the default; a report button on
  leaderboard rows; repeated reports reset the name to a generated one. No
  chat for now.
- **Security basics.** Storage permissions owner-only, authoritative
  leaderboards and wallet (server writes only), validation in RPCs, tokens
  in the platform only (never in game code), TLS only, server key and
  secrets only on the server.

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

## 9. Multiplayer: same room and remote

Goal (D4, within about a year): two or more players on one game, either
**in the same room on one shared board** or **remote, each on their own
table** (D6), depending on what the game supports.

**Manifest (D6).** Each game declares its modes; the hub's game sheet shows
**Play together** (same room) and / or **Play online** (remote) from them:

```gdscript
# LGGameManifest (new optional fields)
@export var multiplayer_modes: PackedStringArray = []   # "same_room", "remote"
@export var multiplayer_kind: StringName = &""          # &"relayed" or &"authoritative" (9.3)
@export var remote_view: StringName = &"mirror"         # how remote players appear (9.4)
@export_range(2, 8) var max_online_players: int = 2
```

| Game | Same room | Remote | Kind | Notes |
| --- | --- | --- | --- | --- |
| Tic-Tac-Toe | Yes | Yes | Relayed | Turn-based; the obvious first test |
| Stack Tower | Yes (take turns on one tower) | Yes (race: each builds a tower, the rival's appears as a ghost tower) | Relayed first, authoritative for ranked | |
| Mage Run | No (one road is too small for two runners on a table) | Yes (race on the same seed; the rival is a ghost wizard on your road) | Authoritative (ranked) | |
| Crystal Defense | Yes (co-op on one map) | Yes (co-op on mirrored maps) | Authoritative | Shared waves and towers; in-run mana per team |
| Tattoo Studio | Yes (draw together on one model) | Yes (mirrored model, ghost needles) | Relayed | No scores; ink still stays on each phone (D5) |
| Competitive Evolution | Later | Later | Authoritative | Placeholder today |

### 9.1 One board for every phone

Everything in Looking Glass already lives in **board space** (games, taps,
rays, the play box), and only the board's anchor is in world space. So
phones only need to agree on the **board's pose**; all game state can be
exchanged in board coordinates and every phone renders it from its own
anchor. Options for agreeing on the pose, simplest first:

| Option | How | Tradeoff |
| --- | --- | --- |
| **Fit the same table** | Each phone runs the normal calibration on the same table; the host's board size and the fitted edges (Fit edges already snaps to a real table) give the same rectangle; a "which corner is mine" tap resolves the rotation, plus a small nudge control | No new services; a few cm of error, fine for board games and Crystal Defense, weaker for precise shared pointing |
| **Printed marker** | ARCore Augmented Images: the board is placed relative to a printed card on the table | Very consistent; needs a printed card |
| **ARCore Cloud Anchors** | The host hosts the anchor; guests resolve it by id (Google Cloud ARCore API, with an API key or OAuth; longer persistence needs OAuth) | Most automatic; sends visual feature data to Google (a privacy note and a Google Cloud project), resolve can fail in plain rooms |

Start with **fit the same table** (it reuses the platform's calibration),
add Cloud Anchors as an option later.

### 9.2 Session flow

1. Same room (**Play together**): the host picks a game; the platform creates a Nakama
   match (`lg_match_create`) and shows a 6-character join code (and a QR
   code).
2. Guests enter the code; everyone calibrates and locks the same table; the
   match starts when all are locked (the AR pause / resume rules apply per
   phone; a phone that loses tracking pauses its view, not the match).
3. Remote (**Play online**): the same join code, or Nakama's matchmaker
   for public games later; each player calibrates their own table; the
   match starts when all boards are locked.
4. Games get an `LGMatch`: `players`, `local_player`, `send(op, data)`,
   `state_received` signal, `is_host()`; payloads are board-space and small
   (ints, packed vectors).

### 9.3 Relayed vs authoritative

| Mode | Nakama feature | Use for | Notes |
| --- | --- | --- | --- |
| **Relayed** | Clients send match data; the server forwards it (no game code on the server) | Turn-based and casual co-op: Tic-Tac-Toe on one board, Stack Tower turns, Tattoo Studio "draw together" (strokes are board-space rays) | Quick to build; a host phone acts as the referee; cheating is possible, so no ranked results |
| **Authoritative** | A match handler on the server (`match_init`, `match_join_attempt`, `match_join`, `match_loop` at a fixed tick, `match_leave`, `match_terminate`) owns the state | Anything competitive or with shared simulation: Crystal Defense co-op (towers, waves, shared mana), Mage Run races, ranked results feeding leaderboards | Server code per game mode (TypeScript first); deterministic, node-free sims (Mage Run's `MageRunSim`, Crystal Defense's `platform/sim` pieces) can be shared by porting the rules or by running the same seeded rules on both sides with the server as referee; start at 10-20 Hz |

Plan: relayed Tic-Tac-Toe on one board first (proves the board-pose
agreement and the session flow), then remote Tic-Tac-Toe with the mirrored
board (9.4), then an authoritative Crystal Defense co-op prototype in both
modes.

### 9.4 Remote play: a mirrored board on every table

In remote play there is no shared physical board. Each player places the
game's board on **their own table** as usual (normal calibration, their own
placement scale), and the match state, which is already in **board space**,
is drawn on every board. So each player sees the **same board**,
mirrored onto their table, with the others shown as presences around it:

- **Seats.** Each player gets a side of the board (2 players: opposite
  sides; up to 4: one per side). Each phone rotates the board so its own
  seat is nearest to it (`remote_view = &"mirror"`, the default). Games
  where sides matter (Tic-Tac-Toe marks, Crystal Defense lanes) convert
  seat-relative positions; board space stays the source of truth.
- **Avatars.** Each remote player is a small floating **avatar marker** at
  their seat: their profile colour and glyph and display name, placed where
  their phone is relative to their own board (their camera pose in board
  space, sent at about 10 Hz, scaled to the local board), so you see where
  they are looking from. It fades when they look away or lose tracking.
- **Ghost hands.** Each remote player's **touch ray** on their board
  (already board-space: `_on_box_ray`, ray strokes) shows as a translucent
  **ghost hand / pointer** where it hits, with a short trail: you see them
  aim at a cell, trace a tattoo line, or point at the tower they will
  build. Picked-up or selected pieces glow in that player's colour.
- **Ghost content per game.** Racing games show the rival as a ghost on
  your own track (Mage Run's ghost wizard, Stack Tower's ghost tower beside
  yours) rather than a shared board, chosen by `remote_view = &"ghost"`.
- **Latency.** Authoritative games get the server's state at 10-20 Hz; each
  phone predicts its own inputs, interpolates remote avatars, hands and
  pieces about 100 ms behind, and snaps to the server state on mismatch.
  Turn-based relayed games just apply moves in order. A "waiting for
  {name}" badge shows when a remote player is paused (rotation, app
  background or lost tracking); the match keeps going for real-time games
  and waits for turn-based ones.
- **Social.** Quick reactions (a few emotes on the ghost hand) and no free
  text chat (section 7); voice is out of scope.
- **Same room vs remote in code.** Games see the same `LGMatch`; same-room
  play just has every seat on one shared board (9.1), remote play adds the
  mirror and presences. `LGMatch.presences()` gives each remote player's
  seat, pose and ray for the platform's avatar and ghost-hand rendering, so
  games do not draw them themselves.

---

## 10. Store and Play Billing (designed now, purchases later)

### 10.1 Shared currency

- **Earn-only at first (D2).** A platform currency, **Shards**
  (D8), in a **Nakama wallet** per account. Only the server changes
  it: `lg_wallet_earn(game_id, reason, evidence)` applies server-side rules
  (daily caps per game, first-win bonuses, verified leaderboard results),
  writes a ledger entry, and returns the new balance. A game cannot mint
  currency by editing a save.
- **Starter earn rates (D8, server rules, tune in playtests).** Earnings
  need a completed session and evidence the server already checks
  (section 5.4); repeats beyond a cap earn nothing that day.

  | Game | Earns | Per-game daily cap |
  | --- | --- | --- |
  | Tic-Tac-Toe | 5 per finished game (local two-player counts once per round, not per mark) | 30 |
  | Stack Tower | 1 per 5 layers; +10 for a new personal best | 60 |
  | Mage Run | 1 per 100 m; +10 for a new personal best | 80 |
  | Crystal Defense | 10 per level won; +5 per star the first time it is earned | 100 |
  | Tattoo Studio | 5 per session with at least 5 minutes of drawing | 20 |
  | Competitive Evolution | none (placeholder) | 0 |
  | Any multiplayer match | +10 per finished match (on top of the game's own rate) | 50 |

  - **Daily cap: 250 Shards per account** across all games (resets at
    midnight US Central time), so a long session in one game cannot farm
    the economy. **Daily first win** in any game: +20 (inside the cap).
  - **One-time:** +25 the first time each game is played, +50 for linking
    an account (outside the cap).
  - **Reference prices:** small cosmetics 150-300, large ones (board skins,
    full outfits) 600-1,200, so a regular player earns a small item in one
    or two days and a large one in about a week.
- **Not the same as Crystal Defense's mana (D8).** Crystal Defense's
  in-run **mana** is the game's own `Wallet`: earned and spent inside a run,
  reset every level, never saved to the account and never exchanged for
  Shards. To avoid confusion with the crystal theme, Shards are only shown
  in platform UI (hub, Store, the result screen's "+20 Shards" line with the
  Shards icon), never in Crystal Defense's in-run HUD, and the two never
  share an icon or colour (mana: Crystal Defense's own crystal colour;
  Shards: the platform's shard icon in a distinct colour).
- Offline: earn requests queue in the outbox and the hub shows them as
  "pending" until the server confirms. Spending needs to be online.
- Spend on cosmetics first (wizard hats and robes, board skins, Tattoo
  Studio ink packs, Stack Tower slab themes), each a platform item id
  granted on the server and readable by games through `LGWallet.owns(item)`.

### 10.2 Store UI (hub **Store** tab)

| Section | Content | Now |
| --- | --- | --- |
| Header | Balance chip (Shards icon and number), "pending" badge when offline earnings wait | Live |
| **Earn** | Today's ways to earn: per-game goals, daily first win, streaks, with progress bars | Live |
| **Spend** | Cosmetic items per game and platform-wide, preview on the board (place a hat on the wizard in the hub preview) | Live with earn-only currency |
| **Get Shards** (purchase packs) | 3-4 pack tiles laid out as they will ship, with no price shown; a diagonal **"Coming soon"** ribbon and a dimmed, disabled button; tapping shows "Purchases are coming soon. Earn Shards by playing for now." | **Blocked** (D2) |
| Purchase history | Empty state "No purchases yet" | Placeholder |

Portrait: sections stacked in one scroll, packs in a 2-column grid.
Landscape: Earn and Spend side by side, packs in one row. The same
layout tests as the hub (inside the screen, no overlaps, both shapes).

### 10.3 Play Billing integration (later)

- **Client:** the Godot Google Play Billing plugin (Play Billing Library)
  behind an `LGStore` platform class; games never touch it. One-time
  consumable products (`glimmer_pack_small` …) defined in Play Console.
- **Flow:** query products (show localized prices from Play), launch the
  purchase flow, receive the purchase token, send it to the server
  (`lg_purchase_validate`), which validates it with Google (Nakama's
  Google purchase validation, using a Play Developer API service account),
  grants the currency in the same transaction with the order id as the
  idempotency key, then the client **consumes** the purchase. Unconsumed
  purchases are retried at the next launch, so a crash never loses a paid
  pack.
- **Refunds and chargebacks:** Play Real-time Developer Notifications (or
  the Voided Purchases API polled daily) mark the order voided; the server
  writes a negative ledger entry (balance may go negative, which blocks
  spending until earned back).
- **Rules:** Google Play's payments policy (digital goods must use Play
  Billing), a clear price and content on each pack, no loot boxes (fixed
  contents only), purchase history and receipts in the hub, and the 13+
  audience (D1). Taxes and payouts are handled by Google; a merchant
  account in Play Console is needed first.
- **Turn-on checklist:** merchant account, products in Play Console,
  service account, the RPC and refund job deployed, then remove the
  "Coming soon" block behind a remote config flag.

---

## 11. Milestones

| Phase | Scope | Done when |
| --- | --- | --- |
| **P1: local profile, save API, hub** | `LGProfile` (guest, up to 4 local), `LGSave` (slots, envelope, migrations, autosave hooks, atomic writes, blobs), `LGScores` local (manifest leaderboards, local top 20, stats), hub (Play / Profile / Store shell / Settings, game sheet, progress summaries) in both orientations; migrate Stack Tower, Mage Run, Tic-Tac-Toe, Tattoo Studio (settings; ink as local blobs) and placement files; Crystal Defense adopts `main` and `run` slots; data export and per-game reset; `save_tests` and hub layout tests | Bests, progress and Tattoo ink survive an app restart; a corrupted or half-written save falls back cleanly; the hub passes the orientation layout checks; everything works in airplane mode |
| **P2: accounts and cloud saves (Nakama)** | Self-hosted Nakama (Docker Compose, VPS), `LGBackend` with `NakamaBackend` and `FakeBackend`; device-auth guest accounts, Google and email linking; storage-object sync of `main` slots with versions, merge hooks and conflict backups; 13+ age gate and terms; name filter hook; in-app and web account deletion; privacy policy and Data safety | Progress moves to a second phone by signing in; conflicts resolve as specified; deleting an account removes all server data |
| **P3: online leaderboards** | Authoritative Nakama leaderboards from the manifests, `lg_submit_score` validation, outbox, global and weekly boards, verified flags, reports; optional replay verification for Mage Run | Global boards show verified scores; forged submissions are rejected in tests |
| **P4: multiplayer (same room and remote)** | Manifest `multiplayer_modes`, join codes, board-pose agreement by fitting the same table, `LGMatch` with presences; relayed Tic-Tac-Toe same room, then remote on mirrored boards with avatars and ghost hands; then an authoritative Crystal Defense co-op prototype in both modes | Two phones play one board in the same room, and two phones in different places see each other's moves, avatars and ghost hands on their own tables; a phone losing tracking rejoins without ending the match |
| **P5: friends and Shards (earn-only)** | Friends (codes and the match history), friends' boards; Nakama wallet with the Shards earn rules and daily cap (10.1), cosmetics to spend on; Store tab live with the purchase section behind "Coming soon" | Balances cannot be changed by editing a save; the store passes the layout checks |
| **P6: purchases** | Play Billing via `LGStore`, server validation, consume, refunds, remote flag to lift "Coming soon" | A test purchase grants currency exactly once, survives a crash, and a refund claws it back |
| **P7: creator tools alpha** | `.lgpkg` for first-party games, sandbox scripting prototype, Studio alpha, automated review checks | A non-bundled game installs from a package and passes the platform tests |

Each phase ships with headless tests like today's suites, and the APK keeps
working fully offline (multiplayer and purchases excepted).

---

## 12. Open questions

None blocking. All design questions are answered (D1-D8). The Shards earn
rates and caps in section 10.1 are starting values to tune in playtests,
not open questions.
