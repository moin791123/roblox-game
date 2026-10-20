# 알 훔치기 펫 월드: design contract

Kid-friendly "Steal an Egg" + "Pet Simulator" game. Rojo project. Luau. All player-facing text is **Korean**, cute and short.
Code comments: short Korean comments are fine (match existing files). Use `--!strict` only if your code type-checks cleanly; otherwise omit it.

## Core loop
1. Each player (max 6) gets a **plot** (base) with pedestals ("slots"). 6 slots open at the start, up to 12 can be bought.
2. Eggs of random rarity ride a **conveyor** through the middle of the map. A player buys one (ProximityPrompt), and it flies into a free slot in their plot.
3. An egg on a slot **hatches** after `HatchTime` into a random cute **pet** (pets added to the Index, which is the collection book).
4. A pet on a slot generates `Income` coins/sec into the plot's **collector**. The owner steps on the collector pad to claim the coins.
5. **Stealing**: other players can walk into an unlocked plot and hold "훔치기" on an egg or pet. The thief carries it above their head, slowed, and must reach their own plot within `CarryTimeout` seconds. The owner can press "되찾기" on the carried item to get it back. Thief death, timeout, or leaving also returns it.
6. **Lock**: the owner presses the lock button and a laser door closes the plot entrance for `LockDuration` s (then a `LockCooldown`). Stealing from a locked plot is rejected.
7. **Pet-sim part**: coins (bronze, silver, gold) lie in the field around the conveyor. Up to `MaxFollow` pets can follow the player. Followers add a coin `Boost` and magnet radius, plus a little walk speed.
8. Bag / inventory UI: move pets between slot / follow / bag, sell pets, place bag eggs onto slots. Index UI shows discovered pets.

## Coordinates (see `Config.Layout`)
- Ground top surface is **y = 0**. Conveyor runs along X at z = 0 from x = -72 to 72.
- Plots: `Config.Layout.Plots[i]` is a CFrame at the plot floor centre (y = 0). Its **LookVector points toward the entrance** (the conveyor). The plot is a `PlotSize` × `PlotSize` square. In plot-local space the entrance wall is at local z = -PlotSize/2.
- Field coins spawn in `FieldMin..FieldMax`, but not where |z| < `FieldConveyorClearance`.

## Player data (server, DataService)
```lua
data = {
  Coins = number,
  Pending = number,          -- coins waiting in the plot collector
  SlotsUnlocked = number,    -- starts Config.Plot.StartSlots
  Items = { [uid: string] = Item },
  Index = { [petId: string] = true },
  NextUid = number,
  LastOnline = number,       -- os.time() at last save (offline earnings)
  Stats = { Hatched = number, Steals = number },
}
Item = {
  Kind = "Egg" | "Pet",
  Id = string,               -- eggId or petId
  Loc = "Slot" | "Follow" | "Bag",   -- eggs are never "Follow"
  Slot = number?,            -- when Loc == "Slot"
  HatchAt = number?,         -- eggs on a slot: os.time() when it hatches
  HatchLeft = number?,       -- eggs in the bag: seconds remaining (timer paused)
}
```
Uids are strings like `"i17"`, so they work as DataStore dictionary keys.

## Client snapshot (`Remotes.DataSync`)
`{ Coins, Pending, SlotsUnlocked, Items = data.Items, Index = data.Index, PlotIndex = number? }`. The client never mutates it. It re-renders on every sync.

## Remotes (`ReplicatedStorage.Shared.Remotes`, all RemoteEvents)
| name | dir | args |
|---|---|---|
| DataSync | S→C | snapshot |
| Notify | S→C | text, kind ("info", "good", "warn", "alert") |
| HatchFx | S→C | petId, position (Vector3), isNew (bool) |
| CoinFx | S→C | amount, position |
| RequestSync | C→S | (none) |
| PetAction | C→S | uid, action ("Follow", "Unfollow", "ToBase", "ToBag", "Sell") |
| BuySlot | C→S | (none) |
| LockBase | C→S | (none) |

The server **must validate everything** (types, ownership, coin balance, locks). Never trust client values.

## Workspace instance contract (things the client reads)
- `workspace.Plots.Plot<i>`: Model. Attributes: `OwnerUserId` (number, 0 = free), `OwnerName` (string), `LockedUntil` (number, `workspace:GetServerTimeNow()` time; 0 = unlocked), `PlotIndex` (number).
  - Child BasePart `LaserDoor`: the server sets `CanCollide = true` and visible while locked, `CanCollide = false` and mostly transparent while unlocked. The **owner's client locally forces `CanCollide = false`** on its own LaserDoor so the owner can always walk through.
  - Child BasePart `Collector`: the owner touches it to claim `Pending`. Attribute `Pending` (number) for display.
  - Child BasePart `SpawnPoint`: where the owner respawns.
- Slot item models (eggs or pets sitting on pedestals) live under their plot model in a Folder `Items`. Attributes on the model: `ItemUid`, `OwnerUserId`, `Kind`, `Id`, and `HatchAt` for eggs.
- **ProximityPrompts carry attributes** so the client can hide irrelevant ones locally:
  - `PromptKind = "Steal"` with `OwnerUserId`: hidden for the owner.
  - `PromptKind = "Owner"` with `OwnerUserId`: shown only to the owner.
  - `PromptKind = "Reclaim"` with `OwnerUserId` (the victim): shown only to the victim.
  - `PromptKind = "Buy"`: shown to everyone.
  The client sets `prompt.Enabled = false` locally for hidden ones. The server still validates.
- `workspace.Conveyor`: belt and eggs. Each conveyor egg Model has attributes `EggId` and `Price`.
- `workspace.FieldCoins`: coin parts. Attribute `Value`.
- `workspace.FollowPets`: follower pet models.
- Player attributes: `Carrying` (bool), `CarryDeadline` (server time number), `CarryItemName` (string).

## Server modules (src/server, children of the `Server` script). Required APIs
Use these **exact** names. Modules require each other via `script.Parent.<Name>`. Avoid circular requires: use the callback fields listed below.

### DataService (agent B)
- `Start()`: autosave loop (every 90 s).
- `Load(player) -> data?`: yields. Uses DataStore with pcall and up to 3 retries, sanitizes and drops unknown ids, applies offline earnings into `Pending`. If loading errored, it marks the player "no-save" so we never overwrite real data with defaults. It also creates leaderstats (`💰 코인`, `🐾 펫`).
- `Get(player) -> data?`, `Save(player)`, `Release(player)` (save, then forget), `SaveAll()`
- `AddCoins(player, n)`, `TrySpend(player, n) -> boolean`
- `AddItem(player, item) -> uid` (assigns a new uid), `RemoveItem(player, uid) -> Item?`, `GetItem(player, uid) -> Item?`
- `CountItems(player, loc?) -> number`
- `MarkDiscovered(player, petId) -> boolean` (true if it is new)
- `Sync(player)`: deferred and coalesced (at most once per frame). Fires `DataSync` and updates leaderstats.

### PlotService (agent B)
- `Start()`: builds 6 plots under `workspace.Plots` (floor, low fence walls, entrance gap with LaserDoor, 12 pedestals with locked ones shown greyed with a "🔒" price sign, Collector pad with a billboard showing pending coins, lock button pad, owner name sign). It also runs the income tick (1 s), the hatch tick, and connects the PetAction / BuySlot / LockBase remotes.
- `AssignPlot(player) -> plot?`, `ReleasePlot(player)`
- `OnCharacterAdded(player, character)`: teleports the player to their plot `SpawnPoint`.
- `GetPlot(player) -> plot?`, where plot = `{ Index, Model, Owner, Origin: CFrame }`
- `GetPlotAt(position: Vector3) -> plot?`: which plot area contains this point (any height).
- `FreeSlot(player) -> number?`: lowest unlocked slot index with no item.
- `GetSlotCFrame(player, slot) -> CFrame`: top surface of the pedestal, where an item model's pivot goes.
- `PlaceItem(player, uid)`: render the item (it must have `Loc == "Slot"`) on its slot. Adds prompts: for pets, a `"Owner"` prompt ("가방에 넣기") and a `"Steal"` prompt ("훔치기", HoldDuration = Config.Steal.HoldDuration). For eggs, a `"Steal"` prompt plus a billboard countdown. Pets bob gently. Legendary and Mythic pets get sparkles.
- `RemoveItemVisual(player, uid)`, `RefreshPlot(player)`
- `IsLocked(plot) -> boolean`
- `Callbacks = { OnStealPrompt = nil :: ((thief, owner, uid) -> ())? }`: init wires this to `CarryService.StartSteal`.
- Hatching: when an egg slot item reaches `HatchAt`, it becomes `{Kind="Pet", Id=Config.RollPet(eggId), Loc="Slot", Slot=same}` (same uid). Then call `MarkDiscovered`, `Stats.Hatched += 1`, `Remotes.HatchFx:FireClient(owner, petId, pos, isNew)`, re-render, and Sync.
- PetAction handling: Follow (max Config.MaxFollow; then `FollowService.Refresh`), Unfollow (to Bag), ToBase (needs FreeSlot; for eggs, `HatchAt = now + HatchLeft`), ToBag (eggs: store `HatchLeft`), Sell (pets only, `Config.SellPrice`). Call `FollowService.Refresh` and `Sync` as needed.

### ConveyorService (agent C)
- `Start()`: builds the belt (`workspace.Conveyor`, a nice animated-looking belt with side rails; the belt top is at y ≈ 1.2), spawns eggs (`Config.RollEgg`) every `SpawnInterval`, and moves them from start to end over `TravelTime` (smooth server-side CFrame lerp on Heartbeat, or TweenService). Each egg shows a billboard with its name, rarity colour, and price. It has a `"Buy"` prompt ("구매 💰<price>").
- Buying: check that the player has a plot and a `FreeSlot`, then `TrySpend`. `AddItem({Kind="Egg", Id, Loc="Slot", Slot, HatchAt=os.time()+HatchTime})`. Remove the egg from the belt, tween a flying copy into the slot, then `PlotService.PlaceItem`, Notify, and Sync. If there is no free slot, notify "기지에 빈 자리가 없어요!".

### CarryService (agent C)
- `Start()`
- `StartSteal(thief, owner, uid)`: validates (different players, thief not already carrying, owner plot not locked, item exists with Loc == "Slot", thief has a plot with a FreeSlot). Then `RemoveItem` from the owner and `RemoveItemVisual`. Weld the carried model (`PetModels.BuildPet` / `BuildEgg`) above the thief's head. Set the thief attributes `Carrying` / `CarryDeadline` / `CarryItemName`, then `FollowService.UpdateSpeed(thief)`. Add a `"Reclaim"` prompt ("되찾기!") on the carried model. Alert the owner ("🚨 OO님이 내 펫을 훔쳐가요! 쫓아가서 되찾으세요!") and tell the thief ("내 기지로 달려가세요!").
- Heartbeat: when the thief's HumanoidRootPart is inside the thief's own plot (`GetPlotAt`), deliver: `AddItem` to the thief with Slot = FreeSlot (if none, use Bag), `PlaceItem`, `MarkDiscovered` for pets, increment `Stats.Steals`, and notify both.
- Fail (reclaim prompt by the victim, timeout, thief death, thief leaving): return the item to the owner: the original slot if still free, else FreeSlot, else Bag. If the owner left, the item is lost (fine).
- `OnPlayerRemoving(player)`, `ReturnAll()` (used on server shutdown, before SaveAll).

### FollowService (agent D)
- `Start()`
- `Refresh(player)`: (re)spawn follower pet models for items with Loc == "Follow" (at most MaxFollow) in `workspace.FollowPets`. They are physics-free and smooth: either the client animates them, or the server uses AlignPosition / AlignOrientation with the network owner set to the player. Pets float behind the player in a fan and bob gently. Each has a name tag.
- `Clear(player)`
- `GetBoost(player) -> number`: the sum of follower `Boost`s.
- `GetFollowerCount(player) -> number`
- `UpdateSpeed(player)`: WalkSpeed = (BaseWalkSpeed + WalkSpeedPerFollower × followers) × (Carrying and CarrySpeedMultiplier or 1). **The only place that sets WalkSpeed.**

### CoinFieldService (agent D)
- `Start()`: keeps `Config.FieldCoins.Count` coins in `workspace.FieldCoins` (spinning on the client, floating). Collection is on the server: a Heartbeat check every 0.1 s of the distance from each character to the coins within the magnet radius (`MagnetRadius + MagnetPerFollower × followers`). The value is `math.floor(Value × (1 + FollowService.GetBoost(player)))`. Then `AddCoins`, `CoinFx`, `Sync`, and respawn after `RespawnTime`.

### WorldBuilder (agent D)
- `Build()`: called first. Removes the default `Baseplate` if present and builds a cute world: a big grass ground (top at y = 0), paths, trees, flowers, clouds, fences, a lobby spawn area at `LobbySpawn` with a SpawnLocation, a welcome sign "알 훔치기 펫 월드", a decorated arch over the conveyor start ("알 공장"), a bright sky and lighting (Lighting properties, Atmosphere, maybe a ColorCorrection). Keep the part count reasonable (< 1500). Don't build plots, belt, or coins (other modules do).

## Shared modules (src/shared)
- `Config` (done; read it).
- `Remotes` (done).
- `PetModels` (agent A):
  - `BuildPet(petId) -> Model`: cute chibi pet from Parts (round body, big shiny eyes, blush, species features), about 2.5–3.5 studs tall. PrimaryPart = `Body`. All parts are unanchored, CanCollide/CanTouch/CanQuery false, and welded (WeldConstraint) to Body. The Body is not Massless, the others are Massless. Pivot = bottom centre, so `model:PivotTo(slotCFrame)` makes it sit on a surface. Front = -Z.
  - `BuildEgg(eggId) -> Model`: same rules. An egg shape with rarity-themed decorations (spots, crystal, gold, rainbow stripes).
  - `AddRarityEffects(model, rarity)`: sparkles / light for Epic and above (the caller decides whether to use it).
  - `CreateViewport(kind: "Pet"|"Egg", id, parent, silhouette: boolean?) -> (ViewportFrame, Model)`: framed nicely. When silhouette is true it is all black (undiscovered Index entries).

## Client (src/client, agent E)
`init.client.luau` + modules. Everything is built in code (no Studio-made GUIs). Cute, rounded, colourful, readable on phones and tablets (use Scale + UISizeConstraint / UIAspectRatioConstraint, big touch buttons).
- HUD: coins (animated count-up and a bump on change), pet count, and buttons for 가방 (Bag), 도감 (Index), ➕ 받침대 (buy slot, showing the next price or "최대"), and 🔒 잠금 (lock, showing remaining / cooldown time from the plot attributes).
- Bag window: cards with a viewport model, rarity-colour border, name, income/boost, and location tag; context buttons that fire PetAction. Filter tabs (전체 / 펫 / 알).
- Index window: all `Config.PetOrder`. Discovered pets show a viewport. Undiscovered ones show a silhouette and "???". Progress "n / 18". Grouped or coloured by rarity.
- Hatch FX: a fullscreen pop with the egg shaking, then a reveal of the pet viewport spinning, rarity banner, and a "NEW!" badge, plus confetti. Plus a world particle burst at the position.
- Notifications: a toast stack; `alert` = red and shaking with a sound.
- CoinFx: a floating "+N" at the position and a sound.
- Carry HUD: when the local player has `Carrying`, show "🏃 기지로 달려가요! ⏱ n초" and a Beam / arrow pointing to the own plot.
- Prompt filtering (see the attributes above) and the own LaserDoor local `CanCollide = false`.
- Coin spinning for `workspace.FieldCoins` (local CFrame rotation; anchored parts).
- A first-time tips banner cycling short hints.
- Sounds: use `Config.Sounds` via `SoundService:PlayLocalSound`.

## init scripts (done by the integrator)
`src/server/init.server.luau` calls `WorldBuilder.Build()`, then `Start()` on each service, and wires `PlotService.Callbacks.OnStealPrompt = CarryService.StartSteal`. It also handles PlayerAdded (Load, AssignPlot, character handling, FollowService.Refresh, Sync), PlayerRemoving, and BindToClose.
