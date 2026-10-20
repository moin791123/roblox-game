# 펫 월드 (v2): design contract

Kid-friendly **Pet Simulator** game. Rojo project. Luau. All player-facing text is **Korean**, cute and short.
Code comments: short Korean comments (match existing files). Use `--!strict` only if your code type-checks cleanly; otherwise omit it.
Every module must pass `luau-lsp analyze` with 0 errors (the integrator runs it).

> **v2 changes (what this round does)**
> 1. **Stealing is gone.** No CarryService, no lock button, no laser door, no `Steal`/`Reclaim` prompts, no `LockBase` remote, no `Carrying*` attributes, no `Config.Steal`. Plots are now cute **houses**.
> 2. **Field coins are per player** and their value **scales with the player's house income/sec**. Each player sees and collects only their own coins (client-rendered, server-validated).
> 3. **Many more pets and eggs**: 47 pets, 10 eggs (see `Config.Pets`, `Config.Eggs`). New pet models register through `src/shared/PetModels/<File>.luau`.
> 4. **House decorating + 2nd floor**: themes (`Config.House.Themes`) and `BuyFloor` (slots 13–24 live upstairs).
> 5. **Riding a pet**: `Loc = "Ride"` (one pet). The player stands on a bigger copy of the pet and moves faster (`Config.RideSpeedMultiplier`).
> 6. **Fusion**: `Config.FuseCount` (3) identical pets of the same tier → one pet of the next **tier**. Tier 1 normal, 2 황금 (gold), 3 무지개 (rainbow); `PetModels.BuildPet(id, tier)` recolours the model and adds sparkles. Tiers multiply income/boost (`Config.Tiers`).

## Core loop
1. Each player (max 6) gets a **house** (plot) with pedestals ("slots"). 6 slots open at the start; slots 7–12 can be bought (`Config.Plot.SlotPrices`). After all 12 are open, **2층 올리기** (`BuyFloor`, `Config.House.FloorPrice`) adds the second floor and opens slots 13–18 at once; 19–24 are bought one by one.
2. Eggs of random rarity ride a **conveyor** through the middle of the map. A player buys one (ProximityPrompt `PromptKind = "Buy"`), and it flies into a free slot in their house.
3. An egg on a slot **hatches** after `HatchTime` into a random cute **pet** (added to the Index, the collection book, which records the highest tier seen per pet).
4. A pet on a slot generates `Config.ItemIncome(item)` coins/sec into the house **collector**. The owner steps on the collector pad to claim the coins.
5. **Pet-sim part**: coins (bronze, silver, gold) lie in the field around the conveyor, **per player**. Up to `MaxFollow` pets follow the player. Followers (and the ridden pet) add a coin `Boost` and magnet radius, plus a little walk speed.
6. **Ride**: pick a pet in the bag → "타기". It becomes `Loc = "Ride"`: the player stands on it and walks `Config.RideSpeedMultiplier(petId, tier)` × faster. "내리기" puts it back in the bag.
7. **Fusion**: in the bag, a pet whose (Id, Tier) the player owns at least `FuseCount` times shows "합성". `PetAction(uid, "Fuse")` consumes 3 and creates one of Tier+1 (max `Config.MaxTier`). Fusion result keeps the clicked item's location (same slot / Follow / Ride / Bag).
8. **House**: HUD button 🏠 → House window: choose/buy a theme (`SetTheme`), 2층 올리기 (`BuyFloor`), ➕ 받침대 (`BuySlot`). Themes change floor/wall/roof/accent colours and the decoration set (flowers, candy, mushrooms, shells, stars, rainbow).

## Coordinates (see `Config.Layout`)
- Ground top surface is **y = 0**. Conveyor runs along X at z = 0 from x = -72 to 72.
- Plots: `Config.Layout.Plots[i]` is a CFrame at the plot floor centre (y = 0). Its **LookVector points toward the entrance** (the conveyor). The plot is a `PlotSize` × `PlotSize` square. In plot-local space the entrance is at local z = -PlotSize/2.
- Slots 1–12 are on floor 1 (pedestal top ≈ y 1.4 above the floor); slots 13–24 are on floor 2 (floor-2 slab top at local y = `HouseBuilder.FLOOR_HEIGHT` ≈ 11; same 4×3 grid). `Config.SlotFloor(slot)` tells the floor.
- Field coins spawn in `FieldMin..FieldMax`, but not where |z| < `FieldConveyorClearance`, not inside plots, and not inside decorations.

## Player data (server, DataService)
```lua
data = {
  Coins = number,
  Pending = number,          -- coins waiting in the collector
  SlotsUnlocked = number,    -- starts Config.Plot.StartSlots; max Config.Plot.TotalSlots (24)
  Floors = number,           -- 1 or 2
  Theme = string,            -- current theme id ("Basic" default)
  Themes = { [themeId] = true },   -- owned themes; Basic always owned
  Items = { [uid: string] = Item },
  Index = { [petId: string] = number },  -- highest tier discovered (legacy `true` sanitizes to 1)
  NextUid = number,
  LastOnline = number,       -- os.time() at last save (offline earnings)
  Stats = { Hatched = number, Fused = number },
}
Item = {
  Kind = "Egg" | "Pet",
  Id = string,               -- eggId or petId
  Tier = number?,            -- pets only: 1..Config.MaxTier (nil/absent means 1 — always sanitize to a number for pets)
  Loc = "Slot" | "Follow" | "Ride" | "Bag",   -- eggs are only "Slot" | "Bag"; at most ONE item has Loc "Ride"
  Slot = number?,            -- when Loc == "Slot" (1..SlotsUnlocked)
  HatchAt = number?,         -- eggs on a slot: os.time() when it hatches
  HatchLeft = number?,       -- eggs in the bag: seconds remaining (timer paused)
}
```
Uids are strings like `"i17"`, so they work as DataStore dictionary keys. Sanitize must: clamp Tier to 1..MaxTier, drop unknown ids, keep only one "Ride" item (extra → "Bag"), slots > SlotsUnlocked → "Bag", Floors ∈ {1,2}, unknown Theme → "Basic", and SlotsUnlocked ≤ 12 when Floors == 1.

## Client snapshot (`Remotes.DataSync`)
```lua
{ Coins, Pending, SlotsUnlocked, Floors, Theme, Themes, Items = data.Items, Index = data.Index, PlotIndex = number?,
  Income = number }   -- Income = Σ Config.ItemIncome(item) for items with Loc == "Slot" (coins/sec)
```
The client never mutates it. It re-renders on every sync.

## Remotes (`ReplicatedStorage.Shared.Remotes`, all RemoteEvents)
| name | dir | args |
|---|---|---|
| DataSync | S→C | snapshot |
| Notify | S→C | text, kind ("info", "good", "warn", "alert") |
| HatchFx | S→C | petId, position (Vector3), isNew (bool), tier (number), mode ("Hatch" \| "Fuse") |
| CoinFx | S→C | amount, position |
| CoinField | S→C | op, payload — `"Reset", { {Id, Kind, Position}, ... }` (full list of my coins), `"Add", {Id, Kind, Position}`, `"Remove", Id` |
| RequestSync | C→S | (none) |
| PetAction | C→S | uid, action ("Follow", "Unfollow", "ToBase", "ToBag", "Sell", "Ride", "Unride", "Fuse") |
| BuySlot | C→S | (none) |
| BuyFloor | C→S | (none) |
| SetTheme | C→S | themeId (buys it first if not owned and affordable, then applies) |
| PickupCoin | C→S | coinId (number) |

The server **must validate everything** (types, ownership, coin balance, distances). Never trust client values.

## Workspace instance contract (things the client reads)
- `workspace.Plots.Plot<i>`: Model. Attributes: `OwnerUserId` (number, 0 = free), `OwnerName` (string), `PlotIndex` (number), `Theme` (string), `Floors` (number).
  - Child BasePart `Collector`: the owner touches it to claim `Pending`. Attribute `Pending` (number) for display.
  - Child BasePart `SpawnPoint`: where the owner respawns.
  - Child Model `House` (built by HouseBuilder; rebuilt on theme/floor change). Child Folder `Items` holds slot item models.
- Slot item models (eggs or pets sitting on pedestals) live under their plot model in the Folder `Items`. Attributes on the model: `ItemUid`, `OwnerUserId`, `Kind`, `Id`, `Tier` (pets), and `HatchAt` for eggs.
- **ProximityPrompts carry attributes** so the client can hide irrelevant ones locally:
  - `PromptKind = "Owner"` with `OwnerUserId`: shown only to the owner (e.g. "가방에 넣기").
  - `PromptKind = "Buy"`: shown to everyone (conveyor eggs).
  The client sets `prompt.Enabled = false` locally for hidden ones. The server still validates.
- `workspace.Conveyor`: belt and eggs. Each conveyor egg Model has attributes `EggId` and `Price`.
- `workspace.ClientCoins` (**client-only**, created by the client `CoinField` module): this player's coin parts. The server never creates coin parts.
- `workspace.FollowPets`: follower pet models and ride mounts (`RideMount_<userId>` models are welded to the character).
- Player attributes: `RideSpeedMult` (number, 1 when not riding) — informational.

## Server modules (src/server, children of the `Server` script). Required APIs
Use these **exact** names. Modules require each other via `script.Parent.<Name>`. Avoid circular requires.

### DataService
- `Start()`: autosave loop (every 90 s).
- `Load(player) -> data?`: yields. DataStore with pcall and up to 3 retries, sanitize (see above), offline earnings into `Pending`. If loading errored, mark the player "no-save". Creates leaderstats (`💰 코인`, `🐾 펫`).
- `Get(player) -> data?`, `Save(player)`, `Release(player)`, `SaveAll()`
- `AddCoins(player, n)`, `TrySpend(player, n) -> boolean`
- `AddItem(player, item) -> uid`, `RemoveItem(player, uid) -> Item?`, `GetItem(player, uid) -> Item?`
- `CountItems(player, loc?) -> number`
- `CountSame(player, petId, tier) -> number`: how many pets with that Id and Tier (any Loc).
- `MarkDiscovered(player, petId, tier) -> boolean` (true if the pet is new OR the tier is higher than recorded).
- `GetIncome(player) -> number`: Σ `Config.ItemIncome` over Loc == "Slot" items (coins/sec).
- `Sync(player)`: deferred and coalesced. Fires `DataSync` (with `Income`) and updates leaderstats.

### PlotService
- `Start()`: builds 6 plots under `workspace.Plots` (via `HouseBuilder.Build`), runs the income tick (1 s), the hatch tick, and connects the PetAction / BuySlot / BuyFloor / SetTheme remotes.
- `AssignPlot(player) -> plot?`, `ReleasePlot(player)` (re-assigns a freed plot to a waiting player).
- `OnCharacterAdded(player, character)`: teleports the player to their plot `SpawnPoint`.
- `GetPlot(player) -> plot?`, where plot = `{ Index, Model, Owner, Origin: CFrame }`
- `GetPlotAt(position: Vector3) -> plot?`
- `FreeSlot(player) -> number?`: lowest unlocked slot index with no item.
- `GetSlotCFrame(player, slot) -> CFrame`: top surface of the pedestal (floor 2 for slots > 12).
- `PlaceItem(player, uid)`: render the item on its slot with `PetModels.BuildPet(id, item.Tier)` / `BuildEgg(id)`. Pets: an `"Owner"` prompt ("가방에 넣기"). Eggs: a billboard countdown. Pets bob gently. Legendary+ pets get `AddRarityEffects`.
- `RemoveItemVisual(player, uid)`, `RefreshPlot(player)` (re-renders every slot item; used after a house rebuild).
- `RebuildHouse(player)`: `HouseBuilder.Build` again with the player's current Theme/Floors, then `RefreshPlot`.
- Hatching: when an egg slot item reaches `HatchAt`, it becomes `{Kind="Pet", Id=Config.RollPet(eggId), Tier=1, Loc="Slot", Slot=same}` (same uid). Then `MarkDiscovered(petId, 1)`, `Stats.Hatched += 1`, `Remotes.HatchFx:FireClient(owner, petId, pos, isNew, 1, "Hatch")`, re-render, Sync.
- PetAction handling: Follow (max Config.MaxFollow; then `FollowService.Refresh`), Unfollow (to Bag), ToBase (needs FreeSlot; for eggs, `HatchAt = now + HatchLeft`), ToBag (eggs: store `HatchLeft`), Sell (pets only, `Config.SellPrice(id, tier)`), **Ride** (pets only; any previous Ride item → Bag; this item Loc = "Ride"; `FollowService.Refresh`), **Unride** (→ Bag), **Fuse** (see Core loop 7: pick `FuseCount` items with the same Id & Tier including the clicked uid, prefer consuming Bag items first, then Slot, Follow, Ride; remove them (+ visuals), add the new item with Tier+1 at the clicked item's location; `MarkDiscovered(id, tier+1)`; `Stats.Fused += 1`; `HatchFx(petId, pos, isNew, tier+1, "Fuse")` where pos is the slot position or the player's position; Notify "✨ 합성 성공! 황금 병아리가 되었어요!"; Refresh + Sync). Tier at MaxTier cannot fuse.
- BuySlot: next price via `Config.NextSlotPrice(SlotsUnlocked, Floors)`; nil → notify why ("2층을 먼저 올려야 해요!" or "최대예요!").
- BuyFloor: requires Floors == 1, SlotsUnlocked == 12, coins ≥ FloorPrice. Then Floors = 2, SlotsUnlocked = 18, `RebuildHouse`, Notify, Sync.
- SetTheme: validate id; if not owned, TrySpend(theme.Price) and own it; set Theme; `RebuildHouse`; Sync.

### HouseBuilder (server, new)
- `HouseBuilder.FLOOR_HEIGHT: number` (local y of the floor-2 slab top, ≈ 11).
- `HouseBuilder.Build(plotModel: Model, origin: CFrame, themeId: string, floors: number, slotsUnlocked: number) -> Handles`
  where `Handles = { House: Model, Pedestals: { [slot]: BasePart } (1..24; locked ones greyed with a "🔒 price" sign, floor-2 ones only when floors == 2), SpawnPoint: BasePart, Collector: BasePart }`.
  Destroys a previous `House` model and rebuilds. Keeps `Collector` and `SpawnPoint` as direct children of the plot model (the client reads them). Builds: floor slab in theme colour, low walls, corner pillars, a roof (hip roof from wedges) above floor 2 when floors == 2 (above floor 1 otherwise), stairs/ramp to floor 2 with railing, pedestals, owner sign, theme decorations (`Theme.Deco`), lamps, a small pet house, planters. Part budget ≤ 250 per house.
- `HouseBuilder.UpdatePedestals(handles, slotsUnlocked, floors)`: re-colours locked/unlocked pedestals and price signs without a full rebuild.

### ConveyorService
Unchanged except: hatch/egg models via `PetModels.BuildEgg`, all 10 eggs (`Config.EggOrder`), buying checks `FreeSlot`.

### FollowService
- `Start()`
- `Refresh(player)`: (re)spawn follower models for Loc == "Follow" (max MaxFollow) **and the ride mount** for the Loc == "Ride" item: `PetModels.BuildPet(id, tier)` scaled by `Config.Ride.Scale`, parts Massless & welded to the character's HumanoidRootPart, positioned under the character; `Humanoid.HipHeight` raised by `Config.Ride.HipHeightAdd` while riding (restore on unride/respawn). Call `UpdateSpeed`.
- `Clear(player)`
- `GetBoost(player) -> number`: Σ `Config.PetBoost(id, tier)` over Follow + Ride items.
- `GetFollowerCount(player) -> number`
- `UpdateSpeed(player)`: WalkSpeed = (BaseWalkSpeed + WalkSpeedPerFollower × followers) × (riding and `Config.RideSpeedMultiplier(id, tier)` or 1). Sets attribute `RideSpeedMult`. **The only place that sets WalkSpeed / HipHeight.**

### CoinFieldService (per-player coins)
- `Start()`: for each loaded player keep `Config.FieldCoins.Count` **virtual** coins `{ Id, Kind, Position, Alive }` (server memory only, no parts). On load/respawn send `CoinField("Reset", list)`; on respawn of a coin send `"Add"`; on pickup send `"Remove"`.
- `PickupCoin(id)` handler: coin must exist & be alive for this player; the character's HumanoidRootPart must be within `MagnetRadius + MagnetPerFollower × followers + 8` studs of `Position`; then value = `math.floor(Kind.Value × (1 + DataService.GetIncome(player) / Config.FieldCoins.IncomeScale) × (1 + FollowService.GetBoost(player)))`, `AddCoins`, `CoinFx(value, Position)`, `Sync`, mark dead and respawn after `RespawnTime` at a new position (`"Add"`).
- Positions avoid the conveyor strip, plots, and decorations (`workspace:GetPartBoundsInRadius` against `workspace.World`).

### WorldBuilder
Unchanged except the tutorial sign text (no stealing; mention: 알 사기, 코인 줍기, 펫 타기 (가방 → 타기), 합성 (같은 펫 3마리), 집 꾸미기 (H 키)).

## Shared modules (src/shared)
- `Config` (done; read it): `Tiers`, `TierInfo`, `PetDisplayName`, `PetIncome`, `PetBoost`, `ItemIncome`, `RideSpeedMultiplier`, `SellPrice(id, tier)`, `NextSlotPrice(slots, floors)`, `SlotFloor`, `House`, `FieldCoins.IncomeScale`.
- `Remotes` (done).
- `PetModels` (folder module `PetModels/init.luau`):
  - `BuildPet(petId, tier?) -> Model` (tier 2 = gold recolour + sparkles, 3 = rainbow). PrimaryPart = `Body`, pivot = bottom centre, front = -Z, unanchored, non-colliding, welded.
  - `BuildEgg(eggId) -> Model`, `AddRarityEffects(model, rarity)`, `HasPet(id)`, `HasEgg(id)`.
  - `CreateViewport(kind, id, parent, silhouette?, tier?) -> (ViewportFrame, Model)`.
  - **Adding pets**: create `src/shared/PetModels/<Group>.luau` returning `function(Kit, PET_BUILDERS, EGG_BUILDERS)` and register `PET_BUILDERS.<PetId> = function(b) ... end`. `Kit` exposes the helpers used by `init.luau` builders: `V, RGB, EYE, WHITE, BLACK, BLUSH, MOUTH, RAINBOW, SIDES, addPart, ell, darker, surf, front, facing, alongY, alongX, frameUp, tri, addEye, chibi, pointyEars, roundEars, muzzle, smallNose, ballArc, EGG_S, EGG_C, eggBase, eggDot, eggRing`. Read the existing builders in `init.luau` for style; every Config pet/egg id must have a builder.

## Client (src/client)
`init.client.luau` + modules. Everything is built in code. Cute, rounded, colourful, readable on phones (Scale + UISizeConstraint, big touch buttons).
- HUD: coins (animated), income/sec ("💰 +N/초"), pet count, buttons: 🎒 가방 (B), 📖 도감 (N), 🏠 집 (H). No lock button.
- Bag window: cards with a viewport (tier passed), tier label (`Config.TierInfo(tier).Label`) and tier-coloured border, name (`Config.PetDisplayName`), income/boost, location tag (집 / 따라옴 / 타는 중 / 가방). Buttons: 따라가기 / 그만, 집에 놓기 / 가방에, 타기 / 내리기, 합성 ✨ (only when `count of same Id&Tier ≥ FuseCount` and tier < MaxTier), 팔기. Filter tabs (전체 / 펫 / 알).
- House window: theme cards (colour swatches, name, price or "보유", "적용" / "구매"), 2층 올리기 (price / "완료" / "받침대 12개를 먼저 여세요"), ➕ 받침대 (next price / "최대").
- Index window: all `Config.PetOrder` (47). Discovered pets show a viewport at the highest tier seen plus a ✨/🌈 badge. Undiscovered: silhouette + "???". Progress "n / 47".
- Hatch FX: `HatchFx(petId, pos, isNew, tier, mode)`: mode "Fuse" shows the egg stage replaced by three small pet viewports merging, title "✨ 합성 성공!", and the tier label; mode "Hatch" as before. Never block input (Frame root, tap or 3 s to close; 1 s when more are queued).
- CoinField (client): renders `workspace.ClientCoins` from `CoinField` remote ops (spinning, floating, kind colours/sizes), magnet (10 Hz distance check with radius `MagnetRadius + MagnetPerFollower × followers`; follower count = my items with Loc Follow), tweens the coin to the player, fires `PickupCoin(id)` once, removes the part. Sound + "+N" come from `CoinFx`.
- Notifications: toast stack (own ScreenGui, DisplayOrder 30).
- Prompt filtering: only `PromptKind = "Owner"` hiding remains.
- Keys: B bag, N index, H house.

---

## v2.1 addendum: rebirth, pet size/weight, holding a pet, hatch luck, the secret pet

Config already has: `Config.Rarities.Secret` (Order 7), pet `CosmicWhale` (Secret, last in `PetOrder`, 48 pets now), eggs `Twilight` (MinRebirth 1) and `Starlight` (MinRebirth 3, contains CosmicWhale at 3 %), `Config.Rebirth`, `Config.RebirthCost/RebirthIncomeMult/RebirthCoinMult/RebirthSpeedMult/RebirthLuckMult/RebirthHatchTime/RollHatchTier`, `Config.HatchTierChance`, `Config.PetSize`, `Config.RollPetSize/SizeOf/SizeLabel/PetWeight`, `Config.ItemIncome` (now × Size), `Config.ItemBoost`, `Config.Hold`. Remotes has `Rebirth` (C→S) and PetAction actions `Hold` / `Unhold`.

### Data additions
```lua
data.Rebirths = number            -- 0..Config.Rebirth.MaxRebirths
Item.Size = number?               -- pets only, Config.PetSize.Min..Max; rolled at hatch (Config.RollPetSize); sanitize via Config.SizeOf
Item.Loc adds "Hold"              -- at most ONE item (like "Ride"); pets only
data.Stats.Rebirths               -- optional mirror; not required
```
Snapshot adds `Rebirths` and `RebirthCost` (= `Config.RebirthCost(data.Rebirths)`), and `Income` must now be `Σ Config.ItemIncome(item) × Config.RebirthIncomeMult(data.Rebirths)` over Loc == "Slot" items (i.e. the real coins/sec, rebirth included).

### Rules
- **Rebirth** (`Remotes.Rebirth`, C→S, no args): requires `Coins >= Config.RebirthCost(Rebirths)` and `Rebirths < MaxRebirths`. Then `Coins = 0`, `Pending = 0`, `Rebirths += 1`. Pets, bag, house, slots, themes are all kept. `FollowService.UpdateSpeed`, Notify "🔄 환생 N회! 수익 ×a, 코인 ×b, 속도 +c%" and `HatchFx`-style celebration is optional (client may show a toast + confetti). Sync.
- **Multipliers**: income tick and offline earnings use `Config.ItemIncome(item) × Config.RebirthIncomeMult(Rebirths)`; field coin value additionally × `Config.RebirthCoinMult(Rebirths)` (CoinFieldService uses `DataService.GetIncome` which already includes the rebirth income multiplier, and multiplies the final value by RebirthCoinMult); `FollowService.UpdateSpeed` multiplies by `Config.RebirthSpeedMult(Rebirths)`; hatch time of newly bought eggs = `Config.RebirthHatchTime(eggId, Rebirths)` (ConveyorService at purchase; ToBase from bag keeps HatchLeft).
- **Hatch luck**: when an egg hatches, `tier = Config.RollHatchTier(Rebirths)` (1 normally; 2 = 황금, 3 = 무지개) and `size = Config.RollPetSize()`. The new pet item gets `Tier = tier`, `Size = size`. HatchFx shows the tier label; isNew via `MarkDiscovered(petId, tier)`.
- **Size**: model scale = `item.Size` (`model:ScaleTo(size)` after `BuildPet`) on pedestals, followers, ride (× Config.Ride.Scale) and hold (× Config.Hold.Scale). Fusion result: `Size = max(sizes) + 0.02` clamped to Max. Bag card shows "⚖️ 3.2kg" (`Config.PetWeight(id, size)`) and the "거대"/"꼬마" label (`Config.SizeLabel`); income shown via `Config.ItemIncome(item)`.
- **Hold** (`PetAction(uid, "Hold")` / `"Unhold"`): pets only; one at a time (previous Hold → Bag); FollowService renders it on top of the character's head (welded to Head, Massless, scale `Config.Hold.Scale`, bobbing slightly), counts toward `GetBoost` like a follower. Unhold → Bag. Ride and Hold can be used together.
- **Rebirth eggs on the conveyor**: eggs with `MinRebirth` spawn only if at least one online player has `Rebirths >= MinRebirth` (ConveyorService checks before rolling; exclude them from the roll otherwise). Their billboard shows "🔄 환생 N 필요". Buying requires the buyer's `Rebirths >= MinRebirth` (Notify "환생 N회가 필요해요!").
- **Secret pet**: `CosmicWhale` only comes from the Starlight egg. Index shows it last, in Secret colour, with hint text "별빛 알에서… 🌌" when undiscovered.

### Client additions
- HUD: 🔄 환생 button (shows the cost) → Rebirth window: current rebirth count, current bonuses, next bonuses, cost, "환생하기" (two-tap confirm; explains coins reset to 0 but pets/house stay).
- Bag card: size/weight line, 들기/내려놓기 buttons (Hold/Unhold), location tag "들고 있음".
- Index: 48 pets; Secret rarity group last.
