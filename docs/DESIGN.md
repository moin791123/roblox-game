# 펫 월드 (v7): design contract

Kid-friendly **pet-collecting simulator**. Rojo project, Luau. All player-facing text is **Korean**, cute and short.
Code comments: short Korean comments (match existing files). Tabs, `task.*` (never `wait`/`spawn`/`delay`).
Use `--!strict` only if your file type-checks cleanly; otherwise omit it. Every module must pass `luau-lsp analyze`
with 0 errors (the integrator runs `check.sh`).

This file is the **contract** between the phase-2 builder agents. Use the exact names below. When something you
need is missing here, do the simplest thing that fits the contract and write it in your report — never edit a
file you do not own (see **File ownership**). `src/shared/Config.luau`, `src/shared/Remotes.luau` and
`src/server/DataService.luau` are **done** (read them; they are the source of truth for numbers and helpers).

> **v7 changes (this round)** — six asks from the parent. ★v7 marks v7 below.
> 1. **Alert level** (`Config.Settings.AlertLevel`, a NUMBER 0–4, default 0; every other setting stays boolean). It is a ladder, each
>    step turns off more ("어디까지 받을지"): `Config.AlertLevels[n+1] = { Name, Short }`
>    0 "모두 받기" (v6 rules) · 1 "최종 테마 좋은 알만 받기" (normal good-egg alerts only from my top unlocked zone
>    `Config.MaxZoneFor(rebirths)`, no "here"/ZoneWindow rule) · 2 "최종 테마도 안 받기" (no normal good-egg alerts) · 3 "시크릿 안 받기"
>    (no normal, no 시크릿) · 4 "천상 안 받기" (only 이터널). 이터널 alerts are always sent. Server-side filter in
>    `ConveyorService.sendEggAlert`; DataService validates AlertLevel as an integer 0..#AlertLevels-1. Hud: a 🔔 button with the
>    current step that opens a small picker (5 rows, tap = choose + toast). The rare egg itself still spawns and shows its beacon/map pill.
> 2. **Rare pets stronger** (fusion-tier reading of "2~3단계 위 신화"): base Income = zone Mythic × **25** (시크릿, beats a 🥇 골드 Mythic ×20),
>    × **60** (천상, beats 🌈 레인보우 ×50), × **150** (이터널, beats 💎 다이아 ×120): zone 1 350 / 840 / 2.1K … zone 8 26.25M / 63M / 157.5M.
>    Rare egg prices (sim `v7/sim7.py`): zone 1 5K / 100K / 400K … zone 8 7.5T / 60T / 200T (시크릿 ×1.5 except zone 1, 천상 ×1.5, 이터널 ×1.2);
>    affordable when the alert pops in the top zone 93 / 71 / 45 %; zone-8 time 19.6 → 15.6 h (no magnet), 10.1 → 8.3 h (🧲 + ⚡).
>    Size ranges `Config.PetSize.Special` (+ `Config.PetSizeRange(petId)`): 시크릿 0.8–1.5 (거대 ≥ 1.31), 천상 0.8–1.7 (≥ 1.46),
>    이터널 0.8–2.0 (≥ 1.67). Rare ride speed = v6 multiplier × (Size / 0.8)^0.5; rare rides use `Config.SoftSpeedCap` (unchanged under
>    64 walk / 72 fly, then easing toward 80 / 96); normal rides keep the hard 64 / 72.
> 3. **Bigger + sparklier, size/speed follow income**: rare pets roll Size from a wider range (`Config.PetSize.Special[rarity] = { Min, Max,
>    HugeFrom }`, e.g. 시크릿 0.8–1.5, 천상 0.8–1.7, 이터널 0.8–2.0; income × Size as before, so a bigger one earns more). World model scale
>    = Size × `Config.Rarities[r].ModelScale` (시크릿 1.2, 천상 1.4, 이터널 1.6; others 1) via `Config.PetDisplayScale(item)` (follow, ride,
>    hold, pedestal; pedestal and ride capped so pets fit slots/doors/floors). Ride/fly speed of rare pets grows with Size (and tier):
>    `Config.RideSpeedMultiplier(petId, tier, size)`; caps may rise for rare rides. Sparkle rises 시크릿 < 천상 < 이터널 (more/bigger
>    sparkles than v6, light never brighter than Secret's); WorldFx pedestal dimming still applies.
>    Built (LOOK): `Config.PetDisplayScale(item, where, fit?)` never shrinks below v6 and eases toward caps (Slot 2.2 + measured fit:
>    neighbour midline, walls/stair glass, 8.9 studs of headroom; Follow 2.2, top ≤ 9.8, big followers spaced by measured width; Ride 2.4,
>    top ≤ 10.6, `Config.RideHipAdd(item, rideScale?)` = 2.2 × max(1, scale / 1.45), stand height ≤ 9.94 < floor gap 11; Hold 1.2, head
>    offset ≤ 1.97). Tier adds +4 %/tier for rare pets. `PetModels.PivotBounds` measures models. Effects 시크릿/천상/이터널: sparkles 8/12/16 /s
>    (size 0.48/0.56/0.64), twinkle stars 1.5/2.5/3.5 /s, soft aura 0.5/0.8/1.1 /s, light 1.3/1.45/1.6 (range 10/11/12) < Secret 1.8/13,
>    rainbow only 이터널; rare followers get the effects too.
> 4. **"🥚 나쁜 알 빼기" button outside the bag** (`Remotes.StashEgg()`): if a pedestal is already free → info toast only; else the worst egg
>    on a pedestal (normal before rare, lower rarity, then lower price, then most hatch time left) goes to the bag (hatch paused like
>    ToBag); with no egg on pedestals the weakest pedestal pet goes instead. Bag full → warn. BuyEgg's "빈 받침대가 없어요" toast hints at it.
> 5. **"✨ 자동 배치" button outside the bag** (existing `Remotes.AutoPlace`). Both quick buttons live on the Hud, hidden while decorating.
>    Built (ALERT): `Config.SettingValue` validates settings (AlertLevel integer, others boolean) on load, remote and State; short labels
>    모두 / 최종만 / 희귀만 / 천상+ / 이터널; a filtered alert returns before the Gap clock. 🔔 "알 알림" is the last toggle cell (picker: 5 rows,
>    ✖ / outside / Esc / bell closes). Quick buttons: PC/tablet continue the toggle column (≥ 44 px); phones use a 3×2 toggle grid and
>    48 px squares in the top-right corner beside the coin bar (on 800×302 the hatch panel shifts ~100 px left during a hatch).
> 6. **Different alert sounds** for 시크릿 / 천상 / 이터널 (`UiKit.PlayRareSound`): Config.Sounds RareHidden 9116395089 (magic chime),
>    RareCelestial 1848271884 (APM harp waltz tag), RareEternal 1842335078 (APM cartoon fanfare) — Roblox's free libraries, public domain.
>    `UiKit.PreloadRareSounds` (init.client) preloads them; a tier plays its asset only after a successful preload, else the v6 tune.
> 7. **Hatch card shows the real income** (× Size) and, for rare pets, "📏 ×n": `Remotes.HatchFx` gains a 6th arg `size` (hatch + fuse).
>
> **v6 changes (this round)** — "조금 진행하니까 루즈해지네": a reason to rush to every map, plus a stronger magnet. ★v6 marks v6 below.
> 1. **Three ultra-rare eggs per zone** (24 eggs): 시크릿 알 → 천상 알 → 이터널 알, each rarer than the last. They are NOT in the normal
>    spawn ladder: every normal belt spawn also rolls for them (rough target per belt: 시크릿 ~1 / 250 spawns, 천상 ~1 / 1000,
>    이터널 ~1 / 4000; the CONFIG agent tunes). They stay on the belt longer (wait at the end, ~60 s) so kids can get there, always fire
>    a special EggAlert ("Rare" kind) with a distinct banner, and get a taller rainbow beacon. Each hatches ONE guaranteed pet.
> 2. **Three new rarities above 비밀 (Secret)**: `Hidden` "시크릿" (Order 8), `Celestial` "천상" (Order 9), `Eternal` "이터널" (Order 10);
>    one pet of each per zone (24 pets, table below). Income ≈ 2.5× / 6× / 15× the zone's Secret pet (tuned by sim).
> 3. **Magnet**: 🧲 `BigMagnetRadius` 45 → 80, `BigMagnetRate` 1.6/s, burst 8 (server: 80 + 8 studs, 2.4/s bucket of 12). New ⚡ 슈퍼 자석
>    (Config.Settings.SuperMagnet; FieldCoins `SuperMagnetMinRebirth` 1, `SuperMagnetRadius` 150, `SuperMagnetRate` 2/s,
>    `SuperMagnetBurst` 12): pulls only coins of the zone you stand in (server: same zone with 10-stud edge slack, 150 + 8 studs,
>    30 studs of height, own 2.5/s bucket of 16); super wins when both are on (other-zone coins refused inside a zone; 🧲 still works on
>    trails). The toggle always saves, the pull needs ≥ 1 rebirth; Hud's 4th toggle is grey "🔒 환생 1회" until then (toast on the
>    unlocking rebirth). Toggles are positioned directly (no UIListLayout). Sim: zone 8 at 17.2 h (none) / 12.2 h (🧲) / 10.2 h (🧲 + ⚡).
> 4. **Integration notes**: rare ("Rare" kind) alerts are queued while decorating (normal ones are still dropped) and shown when decorating
>    ends unless that egg is gone. `PetModels.AddRarityEffects` gives Hidden/Celestial/Eternal a softer light than Secret (1.3 / range 10,
>    tier colour) and 6 slower sparkles/s, rainbow only for Eternal; WorldFx pedestal dimming applies to them too. RideFly: on small
>    screens (< 120 px above the stacked ⬆) ⬆ sits left of ⬇ in one row so egg banners still fit while flying.
>
> | zone | 시크릿 (Hidden) egg → pet | 천상 (Celestial) egg → pet | 이터널 (Eternal) egg → pet |
> |---|---|---|---|
> | 1 숲 마을 | ForestHidden "숲 시크릿 알" → CloverFox 네잎클로버 여우: orange chibi fox, glowing mint four-leaf clover on the forehead, clover-tipped tail | ForestCelestial "숲 천상 알" → BlossomFawn 꽃사슴 요정: pale-pink fawn with white spots, cherry-blossom antlers, tiny translucent petal wings | ForestEternal "숲 이터널 알" → WorldTreeDragon 세계수 용: chubby leaf-green baby dragon, a tiny glowing tree growing on its back, golden belly |
> | 2 호수 | LakeHidden "호수 시크릿 알" → PearlOtter 진주 수달: brown otter on its back hugging a big shiny pearl | LakeCelestial "호수 천상 알" → MoonSwan 달빛 백조: white swan, crescent-moon crown, soft silver glow | LakeEternal "호수 이터널 알" → RainbowKoiDragon 무지개 잉어 용: koi-dragon with long whiskers and rainbow fins |
> | 3 정글 | JungleHidden "정글 시크릿 알" → RainbowChameleon 무지개 카멜레온: round chameleon with rainbow stripes and curly tail | JungleCelestial "정글 천상 알" → GoldenJaguar 황금 재규어: golden jaguar cub with dark rosettes, gem collar | JungleEternal "정글 이터널 알" → EmeraldDragon 에메랄드 용: emerald baby dragon with leafy wings and a gem on the chest |
> | 4 겨울 산 | SnowHidden "겨울 시크릿 알" → CrystalPenguin 수정 펭귄: penguin with an ice-crystal crown and frosty cheeks | SnowCelestial "겨울 천상 알" → AuroraWolf 오로라 늑대: white wolf pup with an aurora-coloured (mint→violet) mane | SnowEternal "겨울 이터널 알" → IcePhoenix 얼음 불사조: ice-blue phoenix with crystal tail feathers |
> | 5 바다 | OceanHidden "바다 시크릿 알" → RainbowJelly 무지개 해파리: round rainbow jellyfish with curly tentacles and big eyes | OceanCelestial "바다 천상 알" → PearlSeahorse 진주 해마: pastel seahorse with a pearl crown | OceanEternal "바다 이터널 알" → BabyKraken 아기 크라켄: chubby purple baby kraken with a tiny captain hat |
> | 6 캔디 랜드 | CandyHidden "캔디 시크릿 알" → LollipopPanda 막대사탕 판다: panda holding a swirl lollipop, candy-pink ears | CandyCelestial "캔디 천상 알" → MarshmallowBear 마시멜로 곰: puffy white marshmallow bear with toasted-gold edges | CandyEternal "캔디 이터널 알" → SweetQueenCat 사탕 여왕 냥이: cat with a candy crown, cape and a wand |
> | 7 구름 왕국 | CloudHidden "구름 시크릿 알" → ThunderPup 번개 강아지: grey-blue puppy with a cloud tuft and a lightning-bolt tail | CloudCelestial "구름 천상 알" → SunGriffin 해님 그리핀: golden griffin chick with sun-ray feathers | CloudEternal "구름 이터널 알" → NineTailFox 구미호: white fox with nine fluffy glowing tails |
> | 8 우주 | SpaceHidden "우주 시크릿 알" → MeteorHamster 운석 햄스터: hamster in a bubble space helmet riding a small meteor | SpaceCelestial "우주 천상 알" → GalaxyUnicorn 은하 유니콘: dark-blue unicorn with star speckles and a glowing horn | SpaceEternal "우주 이터널 알" → CosmoDragon 은하 용: deep-navy dragon with star speckles and a tiny ringed planet orbiting it |
>
> **v6 numbers (CONFIG, scratchpad `v6/sim6.py`)** — egg `Price` / `HatchTime` → pet `Income` (base, per s), per zone 시크릿 · 천상 · 이터널:
>
> | zone | 시크릿 (Hidden) | 천상 (Celestial) | 이터널 (Eternal) |
> |---|---|---|---|
> | 1 | 5K / 45 s → 62 | 60K / 60 s → 150 | 300K / 80 s → 375 |
> | 2 | 150K / 45 s → 300 | 1.5M / 60 s → 720 | 5M / 80 s → 1.8K |
> | 3 | 2.5M / 55 s → 1.5K | 25M / 70 s → 3.6K | 100M / 100 s → 9K |
> | 4 | 40M / 70 s → 7.2K | 400M / 85 s → 17.5K | 1.5B / 120 s → 43.5K |
> | 5 | 750M / 80 s → 36K | 7.5B / 105 s → 87K | 30B / 145 s → 218K |
> | 6 | 15B / 100 s → 180K | 150B / 125 s → 432K | 600B / 170 s → 1.08M |
> | 7 | 300B / 110 s → 900K | 3T / 145 s → 2.16M | 12T / 200 s → 5.4M |
> | 8 | 5T / 130 s → 5M | 40T / 170 s → 12M | 150T / 230 s → 30M |
>
> Rarities: Hidden 시크릿 (60,230,170) Boost 0.5 · Celestial 천상 (255,214,60) 0.6 · Eternal 이터널 (215,105,255) 0.8 (`Special = true`, Eternal `Rainbow = true`).
> Eggs: `Special` = tier key, `Pet` = the guaranteed pet, `Pets = { Pet = 100 }`, `SpawnWeight 0`, `Rung 0`, `Premium false`, Look Gems / Crown / Flames
> (all Shine + Glow). Lists: `Config.SpecialEggOrder` (24), `Config.ZoneSpecialEggOrder[zone]`, `zone.SpecialEggs`; `EggOrder` / `ZoneEggs` / `zone.Eggs` stay the 41-egg ladder.
> Odds: every normal belt spawn rolls each tier once with `Config.SpecialEggChance(tier, belts)` = `SpecialEggs.Chance` (1/300, 1/1200, 1/5000) ÷ √(open belts)
> (rarest hit wins, own `Random`, so the ladder sequence is unchanged); the egg comes half a spawn gap later; ≤ 3 per belt (`MaxPerBelt`); never in a pre-filled belt.
> Per hour, 1 belt: 4.6 / 1.15 / 0.28 · all 8 belts: 13 / 3.3 / 0.8. Life: rides like a normal egg to 3 studs before the end, slides 2.5 studs toward the
> coin field (0.8 s), waits `Conveyor.SpecialWait` 60 s (still phase 2 = buyable), then falls → `Config.BeltEggSpot(zone, age, eggId)`, `BeltEggLife(eggId)`
> (88.2 s vs 27.4), `BeltEggBuyEnd(eggId)`, `BeltEggWait(eggId)`. Alert: `EggAlertKind` "Rare" → always sent to the owner (zone unlocked), no Gap / ZoneWindow,
> does not touch the Gap clock. Sim (10 seeds, active kid): zone 8 19.3 h → 19.6 h (magnet-ish FIELD_PICK 0.7: 15.2 → 15.3 h); in the top zone a 시크릿 is
> affordable at the alert 94 %, 천상 70 %, 이터널 41 %; lower-zone ones ~100 %.
>
> **v5 changes (this round)** — parent's feedback after playing with the kids. ★v5 marks v5 below.
> 1. **Settings toggles** (saved per player): `Config.Settings` { HideHatch, AutoCollect, Magnet } (defaults false), client→server
>    `Remotes.SetSetting(key, value: boolean)` (unknown keys / non-booleans ignored), `DataService.GetSetting(player, key)`,
>    `SetSetting`, `OnSettingChanged(fn(player, key, value))`, snapshot `Settings`; client `State.GetSetting/SetSettingLocal/OnSetting`.
>    Hud shows three one-tap toggles 🙈 부화 숨기기 / 💰 자동 수금 / 🧲 자석 (ON = own colour + mint switch, OFF = grey; optimistic,
>    falls back to the server value after 4 s; hidden while decorating; phones get 42 px squares).
> 2. **HideHatch**: HatchFx skips the big show; the server's hatch/fuse toast is the notice (starts with "🆕 NEW!" for discoveries).
> 3. **AutoCollect**: PlotService moves home `Pending` into coins about every 3 s from anywhere (collector label "🏦 자동 수금 중",
>    silent "+N" only within 120 studs, Hud vault pill hidden).
> 4. **Per-player eggs**: conveyor eggs are no longer shared server Models. ConveyorService keeps each player's own egg list per unlocked
>    belt (same ladder/weights; a new or just-unlocked belt starts full without alerts; EggAlert rules per player). Server→client
>    `EggBelt(op, payload)` ("Reset" {{Uid, EggId, Zone, Born}}, "Add", "Remove" uid, "Bought" {Uid, Target, FlyTime, Poof}),
>    client→server `BuyEgg(uid)` validated in order: own uid, still on belt, has a house, zone unlocked, within 20 studs of
>    `Config.BeltEggSpot(zone, age)`, free slot, coins (0.3 s debounce). `Born` uses `workspace:GetServerTimeNow()`. Client
>    `EggBelt.luau` renders eggs, beacons + "✨ <알 이름>!" signs, price billboards and buy prompts under `workspace.ClientEggs`
>    (models within 200 studs). `workspace.Conveyors.Zone<k>` now holds only the belt parts.
> 5. **Map coins**: still per player (verified with 2 players); `FieldCoins.CountPerZone` 30 → 40, `RespawnTime` 5 → 3. **Magnet**
>    (Settings.Magnet): client pulls coins within `BigMagnetRadius` 45 at `BigMagnetRate` 1.2/s (burst 6); server accepts only with the
>    setting on, within 45 + 8 studs, through a 1.8/s, 10-coin token bucket. Sim: zone 8 at 17.6 h without magnet, 13.8 h with it.
> 6. **Alerts bottom-right**: toasts, the good-egg banner and the zone banner stack bottom-right, newest on top (`Toasts.Dock/Undock`
>    for ZoneClient); phones stay above the jump button; priority toasts > egg banner > zone banner (a waiting banner pauses its clock).
> 7. **Calmer house**: pedestal pets don't hue-cycle, their lights/sparkles/reflectance roughly halved again (WorldFx knobs), lamps ×0.65,
>    furniture lamps lower, GalaxyPalace neon darker, bloom 0.18 / 20 / 2.1, the 집 "!" badge beats 3 times then stays still (§12).
> 8. **Fly while riding**: `src/client/RideFly.luau` (LinearVelocity + AlignOrientation, PlatformStand, soft bob, no camera roll).
>    PC: hold Space 0.35 s or F to take off, Space up, Q / LeftCtrl down, F lands; phone: ✈ beside the jump button, ⬆ / ⬇ and 🛬 while
>    flying. Height cap world Y 150, not below sea + 1, 40 studs past the outer islands. FollowService sets player attributes `Riding`
>    and `FlySpeed` (WalkSpeed × 1.2, max 72); unride glides down. Locked islands and trails are blocked client-side (slide along) and
>    server-side (ZoneService `trailAt` + `checkPlayer`: anyone > 3 studs past a locked gate at any height is sent back).
>
> **v4 changes (this round)** — v3 was less fun than v2 (few eggs, no "good egg!" moment, far-away maps). ★v4 marks v4 below.
> 1. **Many eggs per map again**: **41 eggs** (all 16 old ids + 25 ★v4) — 6 in 숲 마을, 5 in every other zone (§11).
>    Belt spawn-weight ladder 40 / 24 / 11 / 5 / 2 (zone 1: 40 / 24 / 12 / 6 / 3 / 1.5), price ×1 / 3 / 8 / 20 / 50.
>    Each egg's pet weights are a **sliding rarity window**; every pet hatches in its own zone; secrets only from the top 1–2
>    eggs; CosmicWhale only from 별빛 알 (0.25 %). New eggs carry `Egg.Look` (PetModels builds them from it).
> 2. **Good-egg alarm**: an egg from a zone's **top two rungs** (`egg.Premium`) gets a 70-stud Neon **beacon** with a
>    "✨ <egg name>!" sign (visible from the hub) and the server fires `Remotes.EggAlert(zone, eggId)` (§5, §9 ConveyorService);
>    the client shows a banner with "🗺 바로 가기". The old "✨ …이 나타났어요!" Notify toast is gone.
> 3. **Hub-and-spoke map** (§2): 숲 마을 stays in the centre (plots, home belt, lobby, leaderboards unchanged); zones 2–8 are
>    160 × 160 islands around it, clockwise from the lobby, each reached by a **30-stud trail from the home edge** with its gate
>    at the hub end (locked gates are visible from home). Lobby → any belt ≈ 10–21 s at walk speed 18.
> 4. New Config: `Zone.Trail`, `Zone.SpawnLook`, `Egg.Rung` / `Rungs` / `Look`, `ZoneEggOrder`, `EggAlert`, `Conveyor.BeaconHeight`,
>    helpers `ZoneEggs`, `EggRung`, `EggAlertKind` (§8). Pet ids/tiers, house/floor/furniture/accessory tables unchanged.
> 5. **Buying a new house is easy to find again**: HouseWindow has tabs 🏡 새 집 / 🏗 층·받침대 / 🪑 꾸미기 (§10); it opens on
>    🏡 새 집 when a bigger house is affordable, and the 🏠 집 HUD button shows a "!" badge then.
> 6. **Furniture anywhere inside the fence**: v3 only allowed the house interior, where pedestals/stairs/elevator/entrance left
>    almost no room ("벽 밖이에요!" everywhere). Floor 1 is now the whole yard inside the fence; walls, the gate→door path and
>    yard decorations are blocked. One shared rule `HouseLayout.CheckPlace` is used by ShopService and DecorateMode (§8, §9, §10).
>
> **v3 changes** — ★ marks v3 throughout this file
> 1. **7 tiers**: 기본 / 🥉 브론즈 / 🥈 실버 / 🥇 골드 / 🌈 레인보우 / 💎 다이아 / 🌌 갤럭시. Old saves remap 2→4, 3→5.
> 2. **8 zones** in a chain, gated by rebirths (0,1,2,3,5,7,10,14): 숲 마을 (home, 6 houses) → 호수 → 정글 → 겨울 산 → 바다 → 캔디 랜드 → 구름 왕국 → 우주. Each has its own conveyor (2 eggs), field coins, spawn and a gate. (★v4: hub-and-spoke, 5–6 eggs per zone.)
> 3. **66 pets** (48 old ids kept + 18 new), 8 per zone (zone 1 has 10), one **secret** per zone. **16 eggs** (12 old + 4 new).
> 4. **Houses grow with the theme** (8 themes, side 26 → 52, income bonus 0 → +40 %), **up to 10 floors** (12 pedestals each, 120 total), rebirth-gated floors, an **elevator**, and an entrance you can **ride** through.
> 5. **Bag/base**: sorted by income, `AutoPlace` (best pets on pedestals), `ClearBase` (all house pets → bag), bag 150.
> 6. **Fusion never uses pets on pedestals.**
> 7. **Leaderboards**: leaderstats (💰 코인, ⚡ 초당, 🔄 환생) + 2 global top-10 boards + 🏆 window.
> 8. **Pet clothes** (14 accessories, bought once, `Item.Acc`) and **furniture** (22 pieces, placed in your house).
> 9. Pedestal pets no longer bob on the server; the **client animates** them.
> 10. Light `CoinSync` remote for coin-only updates; full `DataSync` is throttled (≤ 5/s).

---

## 1. Core loop

1. Each player (max 6) gets a **house** in 숲 마을. 6 pedestals ("slots") are open at the start; slots 7–12 cost coins (`Config.Plot.SlotPrices`).
2. Eggs ride the **conveyor of each zone**. A player buys one (ProximityPrompt `PromptKind = "Buy"`); it flies (or "poofs" when far) onto a free pedestal in their house.
3. An egg on a pedestal **hatches** after its hatch time into a random pet of that egg (`Config.RollPet`), with a size (`Config.RollPetSize`) and sometimes a higher tier (`Config.RollHatchTier`, never above 골드 from hatching). The Index records the highest tier seen per pet.
4. A pet on a pedestal earns `Config.ItemIncome(item) × Config.IncomeMultiplier(rebirths, theme)` coins/sec into the house **collector**; the owner steps on it to claim. `DataService.GetIncome(player)` already returns that final number.
5. **Field coins** (per player, per zone) lie around each conveyor. Value grows with house income, the zone's `CoinMult`, the follow-pet boost (capped) and rebirths.
6. Up to 3 pets **follow**, one is **ridden** (faster walking), one is **held** over the head. They add coin boost & magnet radius.
7. **Fusion**: 3 pets with the same Id & Tier (from Bag/Follow/Ride/Hold only) → one pet of Tier+1 (max 7).
8. **Rebirth**: costs coins (`Config.RebirthCost`), resets coins to 0, keeps everything else, gives permanent bonuses and **opens zones and floors**.
9. **House**: buy themes (bigger house + income bonus), floors 2–10 (`BuyFloor`), pedestals (`BuySlot`), clothes and furniture (Shop), place furniture (Decorate mode).

### Key numbers (all in Config; see the balance curve in §16)
| | |
|---|---|
| Zone gates (MinRebirth) | 1 숲 마을 0 · 2 호수 1 · 3 정글 2 · 4 겨울 산 3 · 5 바다 5 · 6 캔디 랜드 7 · 7 구름 왕국 10 · 8 우주 14 |
| Zone CoinMult | 1, 1.15, 1.3, 1.45, 1.6, 1.75, 1.9, 2 |
| Pet income per zone | ≈ ×5 per zone: commons 2 / 10 / 50 / 240 / 1.2K / 6K / 30K / 150K; a zone's common always beats the previous zone's legendary |
| Rarity ratio inside a zone | Common 1 · Uncommon 1.5 · Rare 2.2 · Epic 3.2 · Legendary 4.5 · Mythic 7 · Secret 12 (CosmicWhale 2M/s) |
| Tiers IncomeMult | 1, 3, 8, 20, 50, 120, 300 |
| Tiers BoostMult | 1, 1.5, 2.2, 3, 4, 5.5, 7.5 (boost only affects field coins and is capped by `FieldCoins.MaxBoost` = 3) |
| Hatch tier chance | 브론즈 5 %, 실버 1 %, 골드 0.2 % × `RebirthLuckMult` (1 + 0.25 × rebirths), total ≤ 90 %, never above 골드 |
| Rebirth | 25 max; costs 800K, 12M, 240M, 2B, 8B, 40B, 120B, 500B, 1.2T, 3T, … 16Qa (`Config.Rebirth.Costs`); income ×(1 + 0.5 r), field coins ×(1 + 0.1 r), speed ×(1 + 0.03 r), hatch time ÷(1 + 0.1 r) |
| Floors (MinRebirth, price) | 1 free · 2 (0, 300K) · 3 (1, 5M) · 4 (2, 100M) · 5 (3, 800M) · 6 (5, 15B) · 7 (7, 200B) · 8 (10, 2.4T) · 9 (13, 24T) · 10 (16, 200T) |
| Themes (Size, bonus, price) | Basic 26/0/free · Candy 30/+5 %/10K · Forest 32/+10 %/100K · Ocean 36/+15 %/1.2M · Space 40/+20 %/16M · Rainbow 44/+25 %/300M · ★Palace 왕궁 48/+32 %/40B · ★GalaxyPalace 은하 궁전 52/+40 %/4T |
| Bag | `Config.MaxBagItems` = 150 (Loc "Bag" only) |

---

## 2. World layout (all Vector3s are in `Config.Zones` / `Config.Layout`) ★v4 hub-and-spoke

Ground top surface is **y = 0 everywhere**. `Zone.Size.Y` is the ground slab thickness (slab top at y = 0).
숲 마을 (zone 1) is the **hub** in the middle; zones 2–8 are 160 × 160 islands around it. Each island is joined to the hub by one
walkable **trail** (bridge) that starts on the home edge (`Zone.Trail.From`) and ends on the island edge (`Zone.Trail.To`):
`Layout.TrailLength` = 30, `TrailWidth` = 16, side rails ≥ 4 high + invisible walls. Between the land is decorative water
(`Layout.SeaY` = −3, CanCollide **false**; `FallResetY` = −30). Every land edge is fenced (≥ 4 high + invisible wall) except the
trail mouths (home: 7 gaps, island: 1 gap), so the only way into zone k is its trail and gate.
Order is **clockwise from the lobby** (standing at the lobby looking +X, starting behind-left).

| # | Id | Name | Center | Size (X, Z) | Conveyor (start → end) | Field box (min…max) | Spawn | Trail From → To (Dir) | Gate pos |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Village | 🌳 숲 마을 | (−22.5, 0) | 315 × 250 | (−56, 0) → (56, 0) | (−110, −42)…(110, 42) | (−140, 0) | — | — |
| 2 | Lake | 🦆 호수 | (−290, −90) | 160 × 160 | (−236, −132) → (−336, −132) | (−340, −120)…(−222, −20) | (−226, −80) | (−180, −80) → (−210, −80) (−X) | (−181.5, 8, −80) |
| 3 | Jungle | 🌴 정글 | (−105, −235) | 〃 | (−63, −181) → (−63, −281) | (−175, −285)…(−75, −167) | (−150, −171) | (−150, −125) → (−150, −155) (−Z) | (−150, 8, −126.5) |
| 4 | Snow | 🏔 겨울 산 | (125, −235) | 〃 | (167, −181) → (167, −281) | (55, −285)…(155, −167) | (120, −171) | (120, −125) → (120, −155) (−Z) | (120, 8, −126.5) |
| 5 | Ocean | 🌊 바다 | (245, 0) | 〃 | (191, 42) → (291, 42) | (177, −70)…(295, 30) | (181, 0) | (135, 0) → (165, 0) (+X) | (136.5, 8, 0) |
| 6 | Candy | 🍭 캔디 랜드 | (125, 235) | 〃 | (167, 181) → (167, 281) | (55, 167)…(155, 285) | (120, 171) | (120, 125) → (120, 155) (+Z) | (120, 8, 126.5) |
| 7 | Cloud | ☁️ 구름 왕국 | (−105, 235) | 〃 | (−63, 181) → (−63, 281) | (−175, 167)…(−75, 285) | (−150, 171) | (−150, 125) → (−150, 155) (+Z) | (−150, 8, 126.5) |
| 8 | Space | 🚀 우주 | (−290, 90) | 〃 | (−236, 132) → (−336, 132) | (−340, 20)…(−222, 120) | (−226, 80) | (−180, 80) → (−210, 80) (−X) | (−181.5, 8, 80) |

All values are computed in Config by `island(def, { Mouth, Dir, Center })` in the island's local frame: u along `Trail.Dir` from
the island entry, v along `Trail.Side` = (−Dir.Z, 0, Dir.X). Spawn u = 16 on the road (`SpawnLook` = Dir, into the island); the
**main road** runs u −1…92 on v = 0 and ends in a round plaza (u ≈ 102); the conveyor runs parallel to the road at u 26…126 on the
roomier side (`Trail.BeltSide`), 38 from that island edge, with its chute at the entry end; the field box spans from 12 in front of
the belt to 10 from the opposite edge, u 12…130 (the road crosses it; fine). Behind the belt and beyond u 130 are the big-decoration
strips. Zone rects are ≥ 25 apart; trails touch only their two edges. Lobby → belt start (straight-line walk): 1 ≈ 5 s, 2/8 ≈ 10 s,
3/7 ≈ 14 s, 5 ≈ 20 s, 4/6 ≈ 21 s at walk speed 18 (faster with rebirth speed / followers / riding; kids usually start at their house).
`Zone.Palette` = { Ground, Path, Accent, Trim, Sky, Water?, Deco = { kind strings } } for WorldBuilder/ZoneClient.

**Home zone (숲 마을)**: 6 plots, `Layout.PlotSize` = 64, centres x ∈ {−72, 0, 72}, z = ±80 (north row 1–3, south
row 4–6), each `Layout.Plots[i]` CFrame looks at (x, 0, 0) (toward the conveyor). Plot squares: x ±32 around the
centre, z 48…112 (north) / −112…−48 (south). Conveyor along z = 0, x −56…56 (width 8, the old belt). Field coins in
x −110…110, |z| ≤ 42, not within `FieldConveyorClearance` (7) of any conveyor segment, not inside plots (+2 margin).
Lobby / spawn plaza at (−140, 0, 0) (`Layout.LobbySpawn` = `Zones[1].Spawn`). Leaderboards: `Layout.Leaderboards.Income`
at (−165, 0, −28) and `.Rebirths` at (−165, 0, 28), both facing +X (the lobby). ★v4 exits on the home edge: west z = ±80
(호수 / 우주), south and north at x = −150 (정글 / 구름 왕국) and x = 120 (겨울 산 / 캔디 랜드), east z = 0 (바다, the old
east road past the conveyor bin). WorldBuilder adds walkways: lanes x = −150 / 120 (|z| from the plaza / road to the edge), west
spurs at z = ±80, and the plot-row front paths extended to x −155…125.

**Gates** (zones 2–8): ★v4 at the **hub end** of each trail (`Gate.CFrame` = 1.5 into the trail, LookVector = Trail.Dir,
`Size` = (20, 16, 2)). WorldBuilder builds an arch over it (arch beam ≥ 18 high so riders fit), a sign facing home
"🦆 호수 · 🔄 환생 1회" (back: "← 🌳 숲 마을"), a "🔒 환생 N회" billboard (MaxDistance 450, so locked gates show from home) and the **barrier part** `workspace.World.Gates.Gate<k>` with `CFrame = Zone.Gate.CFrame`,
`Size = Zone.Gate.Size`, attributes `ZoneIndex` (k) and `MinRebirth`, `Anchored = true`, **`CanCollide = false`**,
`Transparency = 1` on the server. The client (`ZoneClient`) sets `CanCollide = true` and a visible pink force-field
look **locally** on gates whose `MinRebirth > my Rebirths` (character physics is client-owned, so this blocks the
local player only). The server never trusts that: every zone action (egg buy, coin pickup, teleport) is validated
with `Config.ZoneUnlocked(zone, rebirths)`, and `ZoneService` sends a player standing inside a locked zone back.

---

## 3. Player data (server, DataService) ★

```lua
data = {
  Version = 3,               -- Config.DataVersion
  Coins = number, Pending = number,
  SlotsUnlocked = number,    -- StartSlots (6) .. Floors × 12
  Floors = number,           -- 1..Config.House.MaxFloors (10)
  Theme = string, Themes = { [themeId] = true },   -- Basic always owned
  Items = { [uid] = Item },
  Index = { [petId] = number },                   -- highest tier seen (1..7)
  NextUid = number, LastOnline = number,
  Stats = { Hatched = number, Fused = number },
  Rebirths = number,         -- 0..25
  Wardrobe = { [accId] = true },                  -- ★ clothes owned forever
  Furniture = { [fid] = { Id = furnId, Floor = n, X = number, Z = number, R = 0|90|180|270 } },  -- ★ placed
  FurnitureInv = { [furnId] = count },            -- ★ bought, not placed (key absent when 0)
  NextFid = number,                                -- ★ fids are "f1", "f2", …
}
Item = {
  Kind = "Egg" | "Pet", Id = string,
  Tier = number?,            -- pets: 1..7
  Size = number?,            -- pets: 0.8..1.3
  Acc = string?,             -- ★ pets: worn accessory id (must be in Config.Accessories AND data.Wardrobe)
  Loc = "Slot" | "Follow" | "Ride" | "Hold" | "Bag",   -- eggs only Slot | Bag; ONE Ride, ONE Hold, ≤ 3 Follow
  Slot = number?,            -- Loc == "Slot": 1..SlotsUnlocked; slot s is on floor ceil(s / 12)
  HatchAt = number?, HatchLeft = number?,          -- eggs on a slot / in the bag
}
```
**Sanitize** (done in DataService): unknown ids dropped; Tier clamped 1..7; **migration**: if `raw.Version` is nil
or < 3, Tier 2 → 4 and 3 → 5 for Items **and** Index, then `Version = 3`; Floors 1..10; SlotsUnlocked clamped to
`[StartSlots, Floors × 12]` and raised to `Config.FloorStartSlots(Floors)` (the free first 6 of the top floor);
slot conflicts / slots > SlotsUnlocked → Bag; one Ride, one Hold, ≤ MaxFollow Follow; `Acc` dropped unless known and
owned; Wardrobe known ids only; FurnitureInv known ids, integer 1..`Decor.MaxPerItem`; Furniture: known Id, integer
Floor ≤ Floors, |X|,|Z| ≤ PlotSize/2, R snapped to 0/90/180/270, at most `Decor.MaxPlaced` — anything else goes back
to FurnitureInv. **Theme-size bounds and overlap are not checked at load** (needs the house layout): `ShopService.Validate`
does that when the player gets a plot and after every theme change. `DataStoreName` is unchanged (`EggThiefPets_v1`).

---

## 4. Client snapshot

`Remotes.DataSync` (full; throttled to ≤ 5/s by `DataService.Sync`):
```lua
{ Version, Coins, Pending, SlotsUnlocked, Floors, Theme, Themes, Items, Index, PlotIndex = number?,
  Income,          -- Σ ItemIncome(Slot items) × Config.IncomeMultiplier(Rebirths, Theme)  (real coins/sec)
  Rebirths, RebirthCost = Config.RebirthCost(Rebirths),
  MaxZone,         -- ★ Config.MaxZoneFor(Rebirths) (convenience; the client may also compute it)
  BagCount,        -- ★ items with Loc "Bag"
  Wardrobe, Furniture, FurnitureInv, Stats }   -- ★
```
★ `Remotes.CoinSync(coins, pending, income)`: sent by `DataService.SyncCoins` (from `AddCoins`/`TrySpend` and the
income tick) when only money changed. The client merges these three values into `State.Snapshot` and fires coin
listeners (HUD, affordability). **A full DataSync always follows any item/house/wardrobe/furniture change** because
the server calls `DataService.Sync` explicitly after those. The client never mutates the snapshot otherwise.

---

## 5. Remotes (`ReplicatedStorage.Remotes`, all RemoteEvents; see `src/shared/Remotes.luau`)

The server **validates everything**: argument types (and `#string ≤ 32`), NaN/inf, ownership, coins, distances,
rebirth gates, and throttles each player (≈ 0.15 s per action, 1.5 s for Teleport). Failures → Korean `Notify`.

| name | dir | args | owner (handler) | validation / effect |
|---|---|---|---|---|
| DataSync | S→C | snapshot | DataService | §4 |
| CoinSync ★ | S→C | coins, pending, income | DataService | §4 |
| Notify | S→C | text, kind ("info" \| "good" \| "warn" \| "alert") | any | |
| HatchFx | S→C | petId, position, isNew, tier, mode ("Hatch" \| "Fuse") | PlotService | |
| CoinFx | S→C | amount, position, silent? | any | |
| CoinField | S→C | op, payload: `"Reset", { {Id, Kind, Position, Zone}, … }` / `"Add", {Id, Kind, Position, Zone}` / `"Remove", Id` | CoinFieldService | Ids unique per player across zones |
| LeaderboardSync ★ | S→C | `{ Income = {Row}, Rebirths = {Row}, Global = bool, UpdatedAt = os.time() }`, Row = `{ Rank, UserId, Name, Value }` | LeaderboardService | |
| EggAlert ★v4 | S→C | zone: number, eggId: string | ConveyorService | a top-two-rung egg spawned on zone's belt (rules §9 ConveyorService). Client banner: `Zones[zone].Name`, `Eggs[eggId].Name`, button → `Teleport("Zone", zone)` |
| RequestSync | C→S | — | init.server | full Sync |
| PetAction | C→S | uid, action ("Follow","Unfollow","ToBase","ToBag","Sell","Ride","Unride","Hold","Unhold","Fuse") | PlotService | v2 rules + §7 fusion rule |
| AutoPlace ★ | C→S | — | PlotService | §7 |
| ClearBase ★ | C→S | — | PlotService | §7 |
| BuySlot | C→S | — | PlotService | `Config.NextSlotPrice(SlotsUnlocked, Floors)`; nil → "받침대가 최대예요! 🎉" or "N층을 먼저 올려야 해요! 🏠" |
| BuyFloor | C→S | — | PlotService | `Config.CanBuyFloor(Floors, SlotsUnlocked, Rebirths)` → "Max" "이미 10층이에요! 🏰" / "Slots" "받침대 N개를 먼저 다 열어야 해요!" / "Rebirth" "🔄 환생 N회가 필요해요!"; then `TrySpend(FloorInfo[f].Price)`, `Floors = f`, `SlotsUnlocked = max(SlotsUnlocked, Config.FloorStartSlots(f))`, RebuildHouse, Notify "🏠 f층이 생겼어요!", Sync |
| SetTheme | C→S | themeId | PlotService | buy if not owned (TrySpend), set, RebuildHouse (fires OnPlotChanged "Rebuild" → ShopService.Validate), Sync |
| Rebirth | C→S | — | PlotService | v2 rules; also Notify newly opened zone ("🗺 새 지역 호수가 열렸어요!") / floor |
| PickupCoin | C→S | coinId | CoinFieldService | §9 CoinFieldService |
| Teleport ★ | C→S | kind ("Zone" \| "Floor" \| "Home"), n (number; ignored for Home) | ZoneService | §9 ZoneService |
| BuyAccessory ★ | C→S | accId | ShopService | known, not owned, TrySpend(Price) → `Wardrobe[acc] = true`, Notify "👕 고깔모자를 샀어요!", Sync |
| EquipAccessory ★ | C→S | uid, accId (`""` = take off) | ShopService | item is my Pet; acc owned; set/clear `Item.Acc`; re-render (Slot → `PlotService.PlaceItem`, Follow/Ride/Hold → `FollowService.Refresh`); Sync |
| BuyFurniture ★ | C→S | furnId | ShopService | known; `FurnitureInv[id] < Decor.MaxPerItem`; TrySpend; `DataService.AddFurnitureInv`; Sync |
| PlaceFurniture ★ | C→S | furnId, floor, x, z, r | ShopService | §9 ShopService.CanPlace; `TakeFurnitureInv`, `NewFurnitureId`, store, render, Sync |
| MoveFurniture ★ | C→S | fid, floor, x, z, r | ShopService | fid is mine; CanPlace ignoring itself; update, re-render, Sync |
| PickupFurniture ★ | C→S | fid | ShopService | fid is mine; `AddFurnitureInv` (false → "가구 가방이 가득 찼어요!"); remove + model, Sync |

---

## 6. Workspace instance contract (things other modules / the client read)

- `workspace.Plots.Plot<i>` Model. Attributes: `OwnerUserId` (0 = free), `OwnerName`, `PlotIndex`, `Theme`, `Floors`, ★`ThemeSize`.
  - BasePart `Collector` (attribute `Pending`), BasePart `SpawnPoint` (floor 1, inside the entrance).
  - Model `House` (HouseBuilder; rebuilt on theme/floor change; attributes `Theme`, `Floors`, `Size`, `PartCount`).
    `House > Sign > BillboardGui > TextLabel "OwnerLabel"` (the owner sign is on a **side post**, not overhead).
    ★ Each floor f has a BasePart named `Elevator` (attribute `Floor` = f) with a ProximityPrompt: `PromptKind = "Owner"`,
    `OwnerUserId` = plot owner (HouseBuilder reads `plotModel:GetAttribute("OwnerUserId")` at build time; PlotService
    sets that attribute **before** building and rebuilds on assign/release), attribute `PromptAction = "Elevator"`,
    ActionText "🛗 층 이동", HoldDuration 0. The server does nothing on trigger; the client opens the floor picker.
  - Folder `Items`: slot item models. Attributes: `ItemUid`, `OwnerUserId`, `Kind`, `Id`, `Tier`, `Size`, ★`Acc`, `HatchAt` (eggs).
    ★ Pets carry `Bob = true`: the server anchors the Body at the slot CFrame and **never tweens it**; the client bobs it.
  - ★ Folder `Furniture` (ShopService): models `F_<fid>`, attributes `Fid`, `FurnitureId`, `Floor`, `OwnerUserId`. All parts anchored.
- ProximityPrompts: `PromptKind = "Owner"` (+ `OwnerUserId`) → shown only to the owner (client hides others locally);
  `PromptKind = "Buy"` → everyone (conveyor eggs). The server still validates.
- ★ `workspace.Conveyors.Zone<k>` (Folder per zone): belt parts and egg models; egg Models have attributes `EggId`, `Price`, `Zone`.
  ★v4 premium eggs also have an anchored Neon cylinder `EggBeacon` (child of the zone folder, follows the egg, BillboardGui `BeaconSign`).
- ★ `workspace.World.Gates.Gate<k>` (see §2). `workspace.World` holds all WorldBuilder parts.
- ★ `workspace.Leaderboards` (LeaderboardService): Models `IncomeBoard`, `RebirthBoard`.
- `workspace.ClientCoins` (client-only, CoinField). `workspace.FollowPets` (followers, `RideMount_<userId>`, hold pets).
- Player attributes: `PlotIndex`, `RideSpeedMult`, ★`Zone` (number, the zone the character is in; set by ZoneService ~2×/s).

---

## 7. Gameplay rules ★

**Fusion** (`PetAction(uid, "Fuse")`): the clicked item must be a Pet with `Config.CanFuseLoc(item.Loc)` (Bag/Follow/Ride/Hold)
— a Slot pet is refused with "🏠 집에 있는 펫은 합성할 수 없어요! 가방에 넣고 해 보세요 🎒". Tier < MaxTier. Candidates =
`DataService.FusableUids(player, id, tier)` (never Slot; ordered Bag → Follow → Hold → Ride, oldest first). Need
`Config.FuseCount` including the clicked one ("같은 펫 3마리가 필요해요! (2/3)" counts fusable ones only). Consume the
clicked uid + the first others; new item `{ Kind="Pet", Id, Tier = tier + 1, Size = min(max(sizes) + 0.02, Max), Acc = clicked.Acc,
Loc = clicked.Loc }`; MarkDiscovered; Stats.Fused += 1; HatchFx(mode "Fuse") at the player; Notify "✨ 합성 성공! 실버 병아리가 되었어요!";
FollowService.Refresh if mounts changed; Sync. Bag UI shows "합성 ✨" only on non-Slot pets with ≥ 3 fusable copies.

**AutoPlace** (`Remotes.AutoPlace`): needs a plot. `open` = slots 1..SlotsUnlocked not holding an egg (eggs stay put).
`cands` = pets with Loc "Bag" or "Slot", sorted with `Config.CompareItems`. `best` = first `#open` of `cands`.
Slot pets not in `best` → Bag (remove visual); Bag pets in `best` → the free `open` slots in ascending order (PlaceItem).
Slot pets in `best` stay where they are. Follow/Ride/Hold pets are never touched. The bag never grows (every pet moved
out is replaced by one moved in). Notify "✨ 가장 좋은 펫 N마리를 집에 놓았어요!" or "이미 가장 좋은 펫들이 집에 있어요! 😊". Sync.

**ClearBase** (`Remotes.ClearBase`): every Slot **pet** (not eggs) → Bag, weakest first, until `DataService.BagSpace` is 0;
Notify "📦 펫 N마리를 가방에 넣었어요" or, when the bag fills, "가방이 가득 차서 N마리만 넣었어요! 🎒" (0 pets: "집에 펫이 없어요").

**Floors**: floor f ≥ 2 requires all `(f − 1) × 12` slots of the floors below open, `Rebirths ≥ FloorInfo[f].MinRebirth`, and
`FloorInfo[f].Price`. Buying opens the first 6 slots of the new floor for free; the other 6 are bought with BuySlot
(`Config.Plot.SlotPrices[slot]` exists for exactly the purchasable slots: 7–12 and, on each floor f ≥ 2, the last 6).

**House income**: `income/sec = Σ ItemIncome(slot pets) × Config.IncomeMultiplier(Rebirths, Theme)` where
`IncomeMultiplier = RebirthIncomeMult × (1 + ThemeIncomeBonus)`. Applied in exactly one place: `DataService.GetIncome`
(used by the income tick, offline earnings, field coins, snapshot `Income`, leaderstats, leaderboard). PlotService's tick
must add `DataService.GetIncome(owner)` to `Pending` each second (not its own sum).

**Zones**: an egg, field coin or teleport of zone z is only allowed when `Config.ZoneUnlocked(z, Rebirths)`.
Locked text: "🔒 환생 N회가 필요해요!".

---

## 8. Shared modules (src/shared)

### Config (done) — helpers
Existing names keep working: `WeightedPick`, `RollPet(eggId)`, `RollEgg(rng?, zoneIndex?)` (★ zone filter), `RebirthCost`,
`RebirthIncomeMult/CoinMult/SpeedMult/LuckMult`, `RebirthHatchTime`, `RollHatchTier` (★ up to `MaxHatchTier` 4), `RollPetSize`,
`SizeOf`, `SizeLabel`, `PetWeight`, `TierInfo`, `PetDisplayName` ("골드 병아리"), `PetIncome`, `PetBoost`, `ItemIncome`, `ItemBoost`,
`RideSpeedMultiplier`, `SellPrice`, `NextSlotPrice(slots, floors)`, `SlotFloor(slot)` (★ = ceil(slot/12)), `FormatNumber` (★ K M B T Qa Qi).
★ New: `ZoneOf(petId)`, `EggZone(eggId)`, `ZoneUnlocked(zone, rebirths)`, `MaxZoneFor(rebirths)`, `EggMinRebirth(eggId)`,
`ZoneAt(position) -> zone?` (XZ box; trails/water → nil), `TierVisual(tier)`, `CompareItems(aUid, a, bUid, b)` (bag/auto order),
`CanFuseLoc(loc)`, `ThemeOf(id)`, `ThemeIncomeBonus(id)`, `ThemeSize(id)`, `IncomeMultiplier(rebirths, themeId)`,
`FloorStartSlots(floor)`, `FloorRequirement(floor) -> {Price, MinRebirth}`, `CanBuyFloor(floors, slots, rebirths) -> (ok, "Max"|"Slots"|"Rebirth")`,
`AccessoryValid(id)`, `FurnitureFootprint(furnId, r) -> (sx, sz)`.
★v4: `ZoneEggs(zone) -> {eggId}` (ladder order, cheap → dear), `EggRung(eggId) -> (rung, rungs)`, `EggAlertKind(eggId) -> "Top" | "Second" | nil`;
`RollEgg(rng, zone)` walks `ZoneEggOrder[zone]` by `SpawnWeight`.
Data tables: `Rarities` (+`Boost`), `RarityOrder`, `Zones`, `MaxZone`, `Pets` (+`Zone`, `Boost` auto-filled), `PetOrder` (zone then rarity),
`Eggs` (+`Zone`, `Premium` = top 2 rungs, `MinRebirth` auto = zone's, ★v4 `Rung`, `Rungs`, `Look` on new eggs), `EggOrder`, ★v4 `ZoneEggOrder`, `EggAlert`, `Rebirth.Costs`, `HatchTierChance`, `MaxHatchTier`, `Tiers` (+`Visual`),
`FuseLocs`, `Ride` (+`MaxStandHeight` 8.5), `Conveyor` (per belt; `FlyMaxDistance`, ★v4 `BeaconHeight`), `Plot`, `FloorInfo`, `House` (`MaxFloors` 10,
`FloorHeight` 12, `Themes` with `Size`/`IncomeBonus`), `Accessories`, `AccessoryOrder`, `Furniture`, `FurnitureOrder`,
`FurnitureCategories`, `Decor`, `Leaderboard`, `FieldCoins` (`CountPerZone`, `IncomeScale` 30, `MaxBoost` 3, `RenderDistance`), `Layout`, `Sounds`, `MaxWalkSpeed`.

### Remotes (done) — §5.

### ★ HouseLayout (new, `src/shared/HouseLayout.luau`, owner HOUSE-VISUAL) — pure math shared by server and client
No instances, no yields; requires only Config. All coordinates are **plot-local** (origin = plot floor centre, y = 0,
entrance = local −Z at z = −32). The house is a square of side `Config.ThemeSize(themeId)`, centred in X; its placement
in Z (back-aligned recommended) is HouseLayout's choice but must leave the entrance path clear.
- `HouseLayout.FloorY(floor) -> number`: local y of a floor's top surface = 0.2 + (floor − 1) × `Config.House.FloorHeight`.
- `HouseLayout.SlotLocal(slot, themeId) -> CFrame`: pedestal top (item pivot) in plot space; slot s on floor ceil(s/12).
- `HouseLayout.SlotCFrame(origin, slot, themeId) -> CFrame` = `origin * SlotLocal(...)`.
- `HouseLayout.FloorBounds(themeId, floor) -> { MinX, MaxX, MinZ, MaxZ, Y }`: inner walkable floor area (inside walls).
- `HouseLayout.BlockedRects(themeId, floor) -> { { MinX, MaxX, MinZ, MaxZ, Name, Kind } }`: where furniture may not go: every
  pedestal footprint (+0.5), stairs going up from this floor and the stair landing/opening arriving from below, the elevator
  booth, and on floor 1 also the entrance corridor (doorway → inside 6 studs), Collector and SpawnPoint. ★v4 floor 1 also blocks
  the house walls + corner pillars (doorway open), the gate→door path and gate, and every yard item (sign, mailbox, pet house,
  planters, lamps, theme `DECO_YARD`). `Kind` ∈ Stand / Path / HouseWall / Deco / Hole picks the refusal text.
- ★v4 `HouseLayout.PlaceBounds(themeId, floor)`: where furniture may go — floor 1 = inside the fence (inner face ±31.3) minus
  `Decor.WallMargin`; upper floors = `FloorBounds` minus WallMargin. `FloorBounds` itself is unchanged (house interior).
- ★v4 `HouseLayout.InHouse(themeId, x, z)`, `HouseLayout.PlaceY(themeId, floor, x, z)` (yard ground `YARD_Y` 0.06 outside the
  house, `FloorY(floor)` inside; used by the server render, the ghost and the ray plane).
- ★v4 `HouseLayout.CheckPlace(themeId, floors, furnId, floor, x, z, r, others?, ignoreFid?) -> (ok, reason?)`: the single placement
  rule (see ShopService.CanPlace); `HouseLayout.FitsInHouse(themeId, floors, furnId)`, `HouseLayout.SmallestThemeFor(furnId, floors)`,
  `HouseLayout.Reasons` (refusal texts), `HouseLayout.Layout.Yard` (fence, gate, sign, mailbox, pet house, planters, lamps, deco
  spots — HouseBuilder builds from it so built and blocked never drift), constants `YARD_Y`, `FENCE`, `FENCE_T`, `GATE_HALF`,
  `PILLAR`, `TRIM`. Assumes `Layout.PlotSize` = 64.
- `HouseLayout.FloorSpawn(origin, themeId, floor) -> CFrame`: world CFrame to put a character on that floor (free spot by the
  elevator, facing into the house, already + 3 studs up).
- `HouseLayout.ElevatorLocal(themeId, floor) -> CFrame` (booth centre on the floor).

### PetModels (folder module, owner MODELS)
- `BuildPet(petId, tier?, accId?) -> Model` ★: PrimaryPart `Body`, pivot = bottom centre, front = −Z, unanchored, non-colliding,
  welded (Body has mass, others Massless). Applies `Config.TierVisual(tier)` (§12) and, if `accId`, the accessory.
  Sets model attributes `Tier` and (rainbow) `TierCycle = true`.
- `BuildEgg(eggId) -> Model`, `AddRarityEffects(model, rarity)` (Epic+; Secret strongest), `HasPet`, `HasEgg`, ★`HasAccessory(accId)`.
- ★ `BuildAccessory(accId) -> Model` (standalone, for the shop viewport) and `AttachAccessory(petModel, accId)` (used by BuildPet):
  pet builders may add Attachments `AccHead`, `AccFace`, `AccNeck`, `AccBack` on Body; otherwise the anchor is computed from
  the model bounds (Head = top, 20 % toward the front; Face = front surface at 65 % height; Neck = front at 40 % height;
  Back = back surface at 60 % height). Accessory scale ∝ pet width (clamp 0.6–2). Parts welded to Body, Massless,
  CanCollide/CanTouch/CanQuery false. `model:ScaleTo(size)` by callers scales the accessory too.
- `CreateViewport(kind, id, parent, silhouette?, tier?, accId?) -> (ViewportFrame, Model)` ★ (`kind = "Pet" | "Egg" | "Accessory"`).
- Every `Config.Pets` / `Config.Eggs` / `Config.Accessories` id must have a builder (§13 LOOK lines). New groups go in
  `src/shared/PetModels/<Group>.luau` returning `function(Kit, PET_BUILDERS, EGG_BUILDERS, ACC_BUILDERS)` (4th arg ★).

### ★ FurnitureModels (new folder module `src/shared/FurnitureModels/init.luau`, owner MODELS)
- `FurnitureModels.Build(furnId) -> Model`: PrimaryPart `Base`, pivot = bottom centre at the floor, front = −Z at R = 0,
  bounding box ≈ `Config.Furniture[id].Size` (± 5 %), ≤ 14 parts, parts **unanchored and welded** to Base (like pets;
  ShopService anchors on placement), solid parts `CanCollide = def.Collide`, tiny decorative parts CanCollide false,
  CanTouch false. Lights (StarLamp, FloorLamp, Fireplace) may add a PointLight.
- `FurnitureModels.Has(furnId) -> boolean`, `FurnitureModels.CreateViewport(furnId, parent) -> (ViewportFrame, Model)`.

---

## 9. Server modules (src/server, children of `Server`). Modules require each other via `script.Parent.<Name>`.

Dependency graph (no cycles): DataService ← FollowService ← PlotService ← {ConveyorService, ZoneService, ShopService};
CoinFieldService ← {DataService, FollowService}; LeaderboardService ← DataService; HouseBuilder ← HouseLayout.

### DataService (done)
`Start`, `Load`, `Get`, `Save`, `Release`, `SaveAll`, `AddCoins` (★ → SyncCoins), `TrySpend` (★ → SyncCoins), `AddItem` (validates Acc),
`RemoveItem`, `GetItem`, `CountItems(player, loc?)`, `CountSame`, `MarkDiscovered`, `GetIncome` (★ incl. theme bonus), `GetRebirths`,
`Sync` (★ full, throttled), ★`SyncCoins`, ★`CountByLoc -> {Bag, Slot, Follow, Ride, Hold}`, ★`BagCount`, ★`BagSpace`, ★`GetSlotMap -> {[slot]: uid}`,
★`GetItemsSorted(player, filter?) -> { {Uid, Item} }` (Config.CompareItems), ★`FusableUids(player, petId, tier)`, ★`GetMaxZone`,
★`HasAccessory`, ★`CountPlacedFurniture`, ★`NewFurnitureId`, ★`AddFurnitureInv(player, id, n?) -> bool`, ★`TakeFurnitureInv(player, id) -> bool`.
Leaderstats ★: `💰 코인`, `⚡ 초당` (GetIncome), `🔄 환생` (IntValues, updated on every Sync/SyncCoins).
Callers mutate `data.Items[...]` / `data.Furniture` tables directly (as in v2) and then call `DataService.Sync`.

### PlotService (owner PLOT-LOGIC)
v2 API stays: `Start`, `AssignPlot`, `ReleasePlot`, `OnCharacterAdded`, `GetPlot -> {Index, Model, Owner, Origin, …}`, `GetPlotAt`,
`FreeSlot`, `GetSlotCFrame(player, slot)` (★ uses the owner's theme), `PlaceItem`, `RemoveItemVisual`, `RefreshPlot`, `RebuildHouse`.
★ Changes: slot CFrames via `HouseBuilder.SlotCFrame(origin, slot, themeId)`; `PlaceItem` uses `PetModels.BuildPet(id, tier, item.Acc)`,
sets `Bob`/`Acc` attributes, anchors the Body, **no server tween**; generalised `BuyFloor`/`BuySlot` (§5, §7); fusion rule (§7);
`AutoPlace`, `ClearBase` handlers; income tick uses `DataService.GetIncome` and calls `DataService.SyncCoins(owner)`; Rebirth
notifies new zones/floors. ★ `PlotService.OnPlotChanged(fn: (player: Player, plot: Plot, reason: "Assign" | "Rebuild" | "Release") -> ())`
— called after AssignPlot (house built for the owner), after every RebuildHouse, and before ReleasePlot clears the plot
(ShopService uses it). Set the plot model attributes (`OwnerUserId`, `Theme`, `Floors`, `ThemeSize`) before building.

### HouseBuilder (owner HOUSE-VISUAL)
- `HouseBuilder.FLOOR_HEIGHT` (= Config.House.FloorHeight), `HouseBuilder.FloorY(floor)`.
- `HouseBuilder.Build(plotModel, origin, themeId, floors, slotsUnlocked) -> Handles` where
  `Handles = { House, Pedestals: {[slot]: BasePart} (slots on built floors only; locked ones grey with "🔒 price"), SpawnPoint, Collector,
  Elevators: {[floor]: BasePart}, Bounds: {MinY, MaxY} }`. Keeps `Collector` and `SpawnPoint` as direct plot children (reused).
- `HouseBuilder.UpdatePedestals(handles, slotsUnlocked, floors)`, `HouseBuilder.Destroy(plotModel)`.
- `HouseBuilder.SlotCFrame(origin, slot, themeId)`, `FloorBounds(themeId, floor)`, `BlockedRects(themeId, floor)`,
  `FloorSpawn(origin, themeId, floor)` — thin re-exports of HouseLayout (so server code can use either).
- **Size**: house footprint = `Config.ThemeSize(themeId)` (26…52) inside the 64 × 64 plot; yard/planters/lamps in the rest.
- **Floors 1..10** stacked, floor f top at `FloorY(f)`, slab ≤ 1 thick → clear height ≥ 11 on every floor; walls or railings
  (≥ 3) around every upper floor edge except openings; roof over the top floor.
- **Entrance rule (riding)**: doorway and yard gate clear opening **≥ 9 wide × ≥ 14 tall**; **nothing overhead below y = 14 on the
  walking path** from the plot edge to the doorway (no sign beam, no arch; upper floors start behind the doorway line or the
  doorway sits in a porch with no slab above). A rider stands ≈ `Config.Ride.MaxStandHeight` (8.5) tall.
- **Stairs** between every pair of floors (rise ≤ 1.2 per step, width ≥ 4, **headroom ≥ 11** measured from every step), plus an
  **elevator** booth on every floor (§6). 12 pedestals per floor in a grid that fits the theme size (spacing ≥ 5).
- Part budget: ≤ 260 parts for 1 floor, ≤ 60 more per extra floor (≤ 800 at 10 floors). Theme deco for 2 new themes:
  `"royal"` (red carpet path, gold trims, banners, crown finials) and `"galaxy"` (planet balls, neon star specks, nebula colour strips).

### FollowService (owner PLOT-LOGIC)
v2 API (`Start`, `Refresh`, `Clear`, `GetBoost`, `GetFollowerCount`, `UpdateSpeed`). ★ Models via `BuildPet(id, tier, item.Acc)`;
`UpdateSpeed` clamps WalkSpeed to `Config.MaxWalkSpeed`. `GetBoost` = Σ `Config.ItemBoost` over Follow+Ride+Hold (uncapped; the cap
is applied by CoinFieldService). The only place that sets WalkSpeed / HipHeight.

### ConveyorService (owner WORLD)
★ One belt per zone at `Zones[k].ConveyorStart → ConveyorEnd` under `workspace.Conveyors.Zone<k>`, eggs rolled with
`Config.RollEgg(rng, k)`, `Config.Conveyor` values per belt. A zone's belt only spawns eggs while some online player has
`Config.ZoneUnlocked(k, rebirths)` (zone 1 always). Buy: prompt `PromptKind = "Buy"`, ActionText "구매 💰" .. price; server checks
zone unlocked ("🔒 환생 N회가 필요해요!"), HRP within 20 studs of the egg, `PlotService.FreeSlot`, `TrySpend`; HatchAt =
`now + Config.RebirthHatchTime(eggId, rebirths)`; egg flies to the slot when the plot is within `Conveyor.FlyMaxDistance`,
otherwise sparkles away and appears on the pedestal. Premium eggs (top 2 rungs) get a glow + bigger billboard.
★v4 **beacon + alert**: a premium egg also gets `EggBeacon` (anchored Neon cylinder 0.8 × `Conveyor.BeaconHeight` 70, not
wobbling, moved with the egg; `BeaconSign` BillboardGui 230 × 56 px, AlwaysOnTop, MaxDistance 700, "✨ <egg name>!"); destroyed
when bought or when the egg falls into the bin. On spawn, `Config.EggAlertKind(eggId)`: **"Top"** → always alert; **"Second"** →
only if this belt's last alert was ≥ `EggAlert.Gap` (15) s ago (any alert resets the timer). Recipients: data loaded,
`ZoneUnlocked(zone)`, and (standing in that zone (`Zone` attribute; never counts for zone 1, where every house is) **or** zone > `MaxZoneFor(rebirths) − EggAlert.ZoneWindow` (2))
so big kids are not spammed by low zones. `Remotes.EggAlert:FireClient(player, zone, eggId)`; **no Notify** for it.

### CoinFieldService (owner WORLD)
★ For each loaded player keep `FieldCoins.CountPerZone` virtual coins **per unlocked zone** (positions in that zone's field box,
away from its conveyor segment by `FieldConveyorClearance`, plots, and decorations). Poll `DataService.GetMaxZone` every ~5 s and
send `"Add"` for coins of newly opened zones. `PickupCoin(id)`: coin exists & alive, its zone unlocked, HRP within
`MagnetRadius + MagnetPerFollower × followers + 8` (flat) and 14 (height). Value =
`floor(Kind.Value × Zone.CoinMult × (1 + GetIncome / FieldCoins.IncomeScale) × (1 + min(GetBoost, FieldCoins.MaxBoost)) × RebirthCoinMult)`, ≥ 1.
`AddCoins` (already sends CoinSync — **do not call DataService.Sync here**), `CoinFx(value, pos, true)`, `"Remove"`, respawn after `RespawnTime`.

### ★ ZoneService (new, owner WORLD)
- `ZoneService.Start()`: connects `Remotes.Teleport`; a 0.5 s loop per character: sets player attribute `Zone` (`Config.ZoneAt`, keep the
  last value on trails), sends a character standing inside a **locked** zone back to its `MaxZone` spawn (Notify), and resets falls
  (`HRP.Y < Layout.FallResetY`) to the last zone's spawn.
- `ZoneService.GetPlayerZone(player) -> number` (default 1), `ZoneService.CanEnter(player, zone) -> boolean`.
- `ZoneService.TeleportToZone(player, zone) -> boolean`, `TeleportToFloor(player, floor) -> boolean`, `TeleportHome(player) -> boolean`.
- Teleport validation: kind ∈ {"Zone","Floor","Home"}; n integer; throttle 1.5 s; alive character. Zone: 1..MaxZone and unlocked →
  `Zones[n].Spawn + (0, 3, 0)`. Floor: has a plot, 1 ≤ n ≤ data.Floors → `HouseBuilder.FloorSpawn(plot.Origin, data.Theme, n)`.
  Home: plot `SpawnPoint` (+3) or lobby. Move with `character:PivotTo(cf)` (the ride mount is welded and comes along; followers snap).

### ★ ShopService (new, owner UI-NEW) — clothes + furniture server side
- `ShopService.Start()`: connects BuyAccessory, EquipAccessory, BuyFurniture, PlaceFurniture, MoveFurniture, PickupFurniture (§5) and
  `PlotService.OnPlotChanged` → on "Assign"/"Rebuild": `Validate(player)` then `RenderFurniture(player)`; on "Release": destroy the folder.
- `ShopService.CanPlace(player, furnId, floor, x, z, r, ignoreFid?) -> (boolean, string?)`: furnId known; floor integer 1..Floors;
  r ∈ {0, 90, 180, 270}; x, z finite, snapped to `Decor.Snap`; footprint `Config.FurnitureFootprint(furnId, r)` centred at (x, z) lies
  inside ★v4 `HouseLayout.PlaceBounds(theme, floor)` (floor 1 = the whole yard inside the fence); no overlap with
  `HouseLayout.BlockedRects(theme, floor)`; no overlap with other furniture on that floor unless either is Category "Rug"; placed
  count < `Decor.MaxPlaced` for new pieces. ★v4 the geometry is `HouseLayout.CheckPlace` (the client calls the same function).
  Reasons: "여기에는 놓을 수 없어요!", "벽 밖이에요!" (upper floors), ★"울타리 밖이에요!", ★"다니는 길은 비워 둬요!", ★"집 벽 자리예요!",
  ★"마당 장식이 있는 자리예요!", ★"바닥이 뚫린 곳이에요!", "받침대/계단 자리예요!", "다른 가구랑 겹쳐요!", "가구는 최대 80개까지예요!".
  ★v4 every piece fits the Basic yard, so buying is never refused for space.
- `ShopService.Validate(player)`: puts every piece that fails CanPlace (e.g. after a smaller theme) back into FurnitureInv; Notify
  "🛋 가구 N개가 집에 안 맞아서 가구 가방에 넣었어요" if any; Sync.
- `ShopService.RenderFurniture(player)`: (re)builds `Plot<i>.Furniture`: `FurnitureModels.Build(id)`, anchor all parts,
  `PivotTo(origin * CFrame.new(x, HouseLayout.PlaceY(theme, floor, x, z), z) * CFrame.Angles(0, math.rad(r), 0))` (★v4 PlaceY).

### ★ LeaderboardService (new, owner BOARD)
- `LeaderboardService.Start()`: builds the two boards at `Layout.Leaderboards.Income/Rebirths` (SurfaceGui, title "⚡ 초당 코인 TOP 10" /
  "🔄 환생 TOP 10", 10 rows with rank medal, name, `Config.FormatNumber(value)`), then every `Leaderboard.RefreshSeconds`: writes each
  online player's `floor(DataService.GetIncome)` and `Rebirths` (key `"u_<userId>"`, at most every `WriteSeconds` per player) to the
  OrderedDataStores `Leaderboard.IncomeStore` / `RebirthStore`, reads `GetSortedAsync(false, TopN)`, resolves names
  (`Players:GetNameFromUserIdAsync`, cached, pcall), updates the boards and fires `LeaderboardSync` to everyone. Everything in pcall;
  if the stores fail (Studio without API access), use a **same-server** list built from online players and `Global = false`.
- `LeaderboardService.SendTo(player)` (call after the player's data loads), `LeaderboardService.GetBoard() -> board`.

### WorldBuilder (owner WORLD)
`WorldBuilder.Build()`: ★v4 hub + 7 islands (ground top y = 0, palette colours, fences open only at `Trail.From` / `Trail.To`),
trails From → To with rails + invisible walls, gates at the hub end (§2), island roads/plaza/belt walkway in island-local u/v,
sea decorations only in the outward half around each island and never on other land or trails, per-zone decorations from
`Palette.Deco` (keep conveyors, field boxes, plots + 4, spawn, leaderboard spots ±10 clear), the lobby with the tutorial sign
(알 사기, 코인 줍기, 펫 타기, 합성 (같은 펫 3마리, 가방 펫만), 🗺 지도로 이동, 🛍 상점 옷·가구, 환생하면 새 지역!), zone name signs,
the sea plane, lighting. Part budget ≈ 2500 total. All parts under `workspace.World`.

### init.server.luau (owner PLOT-LOGIC)
Order: `WorldBuilder.Build()`, `DataService.Start()`, `PlotService.Start()`, `FollowService.Start()`, `ConveyorService.Start()`,
`CoinFieldService.Start()`, `ZoneService.Start()`, `ShopService.Start()`, `LeaderboardService.Start()`. After a player's data loads:
`AssignPlot`, character handling as v2, `DataService.Sync`, `LeaderboardService.SendTo(player)`.

---

## 10. Client (src/client)

Everything built in code; cute, rounded, colourful, phone-friendly (Scale + UISizeConstraint, big buttons). One window open at a time
(init.client's `toggle`). Every window module exports `Init(gui)`, `Open()`, `Close()`, `IsOpen() -> boolean`, and `OnSync()` when it
shows snapshot data.

| module | owner | contents |
|---|---|---|
| State | UI-CORE | snapshot (+ ★ CoinSync merge, `State.OnCoins(fn)`), plot lookup, ★`State.SortedItems(filter?)` (Config.CompareItems), ★`State.CountFusable(petId, tier)` (Config.CanFuseLoc), ★`State.MaxZone()`, Floors clamp to 1..MaxFloors |
| Hud | UI-CORE | coins (animated; listens to OnCoins), "💰 +N/초", pet count, buttons: 🎒 가방 (B), 📖 도감 (N), 🏠 집 (H), 🛍 상점 (P), 🗺 지도 (M), 🏆 순위 (L), 🔄 환생 (R, shows cost) |
| BagWindow | UI-CORE | cards sorted by `Config.CompareItems` (pets by income desc, eggs last); tabs 전체/펫/알/집; header buttons **"✨ 좋은 펫 자동 배치"** (AutoPlace) and **"📦 집 펫 모두 빼기"** (ClearBase); count "가방 n/150"; tier label + 7 tier colours; "합성 ✨" only for non-Slot pets with ≥ 3 fusable; **"👕 옷"** button → picker of owned accessories (+ "벗기기") → EquipAccessory; viewports created **lazily** (only for cards in/near the visible scroll area, ≤ ~30 alive, recycled); ★v6 rare pets/eggs (Hidden/Celestial/Eternal) get a 🌟 corner badge, detail pill "🌟 ★★ 천상" in the tier colour, rare egg info "🎁 <펫> 확정!" |
| HouseWindow | UI-CORE | ★v4 `Open(tab?)` with tabs **🏡 새 집** (themes; default when an upgrade is affordable, via `ThemeGoal()`) / **🏗 층·받침대** / **🪑 꾸미기**, `CurrentTab()`; moving to a smaller house with furniture placed needs a two-tap confirm; `Hud.SetBadge("집", on)` "!" badge. Contents: 8 theme cards (swatches, "🏠 크기 N", "+N% 수익", price/보유/적용); floor list 1..10 (✅ / 🔒 환생 N / 💰 price / "받침대를 먼저 다 열어요") + "🏗 N층 올리기"; ➕ 받침대 (next price / 최대); 🛗 floor buttons (Teleport "Floor"); AutoPlace / ClearBase; "🪑 가구 꾸미기" → `DecorateMode.Enter(floor)`; `HouseWindow.OpenFloorPicker()` (used by the elevator prompt) |
| IndexWindow | UI-CORE | 66 pets grouped by zone (header "🌳 숲 마을", locked zones "🔒 환생 N"), viewport at the highest tier seen + tier badge (🥉🥈🥇🌈💎🌌), silhouette "???" for undiscovered, secret hint "<알 이름>에서 아주 드물게… ✨" (derived from the eggs containing it); progress "n / 66". ★v6 **90 pets**: under each zone a "🌟 희귀 3종 n / 3" row (tier-coloured header) with 3 cards (rarity pill ★/★★/★★★ + tier colour, "???" silhouette, hint "<알 이름>에서만 나와요", "🎉 찾았어요!" when found); progress "n / 90" |
| RebirthWindow | UI-CORE | as v2 + "다음 환생 선물: 🗺 호수 열림 / 🏗 3층 가능" (zones/floors whose MinRebirth == Rebirths + 1) |
| HatchFx, Toasts, Tips | UI-CORE | 7-tier labels/colours; Tips mention 지도/상점/자동 배치; ★v4 `Toasts.Banner(spec)` = good-egg banner on `Remotes.EggAlert(zone, eggId)` (zone + egg name, viewport, sound, "🗺 바로 가기" → Teleport("Zone", z); repeats merge ×N, queue ≤ 3, hides after 6 s, suppressed while decorating). ★v5 **Bottom-right alert stack** (never the screen centre / eye level): every notice — toast bubbles (`Toasts.Show`, ≤ 4, newest on top), the good-egg banner (`Toasts.Banner`, compact card, bottom of the stack) and ZoneClient's zone/gate banner (docked via `Toasts.Dock(key, frame, pcH?, smallH?)` / `Toasts.Undock(key)`) — is laid out by `Toasts` as one right-aligned stack, width clamp(19 % gw, 300, 360) on PC / clamp(31 % gw, 224, 270) when GUI height < 500, margin 16/10 px, gap 8/6 px, growing upward. It avoids `UiKit.SideObstacles` (coin bar + income pill, left buttons, top-right toggles, Tips, decorate buttons/tray, open windows' ✖, touch jump button + thumbstick zone; a ScreenGui child with attribute `SideIgnore = true` is skipped): on phones it sits above the jump button; when the right column is full it opens one column further left (≤ 25 % into the centre third). The hatch/fuse show (`UiKit.SideSpot`, no full-screen dim; tap to close) is avoided too; the stack publishes its union as `UiKit.SetSideRect("Banner")`. Space priority: toasts > egg banner > zone banner; a banner that does not fit waits (6 s clock paused, dropped after 20 s), a toast waits ≤ 8 s and speeds the oldest one away. `Toasts.AlertRects()` (alias `TopRects`) returns the placed rects. ★v6 **rare banner** (`Config.EggAlertKind(id) == "Rare"`): tier-coloured card with a soft spinning gradient stroke, title "🌟 <지역>에 <알 이름>이 나타났어요!", chip "★★ 천상", "🎁 <펫> 확정!", "💰 price · ⏳ time left" (from `EggBelt.TimeLeft`), its own short tune per tier (`UiKit.PlayRareSound`), "🗺 바로 가기"; jumps ahead of normal banners (normal ones yield after 1.2 s), never merged with them, stays ≥ 20 s (≤ 40 s) while the egg is still on my belt, closes 2.5 s after it is bought/gone; if there is no room it shrinks (compact, then a one-line mini) and waits ≤ 60 s. Rare hatch/buy toasts (server "[천상] …" / "🌟 <알>을 샀어요!") get the tier colour, 🌟 and 5 s. HatchFx rare reveal (right side, no full-screen flash): gradient ring, "🌟 천상 친구를 찾았어요!", RareBadge, calm tier confetti, 4.5 s hold; with HideHatch only the tune + rare toast |
| WorldFx | UI-CORE | Owner-prompt filter; elevator prompts (`PromptAction = "Elevator"`, via `ProximityPromptService.PromptTriggered` on the client) → callback set by init.client → `HouseWindow.OpenFloorPicker()`; **pet bob**: animates Body CFrame of `Items` models with `Bob = true` within 80 studs (local only, ~30 Hz, small sine; remember the server CFrame per model); particle LOD (disable ParticleEmitters of pedestal pets beyond 70 studs); optional hue cycle for `TierCycle` models nearby; CoinFx numbers |
| init.client | UI-CORE | requires every window below, hotkeys **B N H P M L R**, closes others on open, suppresses hotkeys while `DecorateMode.IsActive()`, wires CoinSync/LeaderboardSync to State/LeaderboardWindow |
| CoinField | WORLD | per-zone coins (payload `Zone`), renders only within `FieldCoins.RenderDistance`, magnet as v2 |
| ★ MapWindow | WORLD | 8 zone cards (emoji, name, palette colour, ★v4 the zone's egg icons, 🔒 환생 N / "이동" → Teleport("Zone", i)), "🏠 우리 집" → Teleport("Home"), current zone highlighted (player attribute `Zone`); ★v6 a "🌟 <단계> 알!" pill (e.g. "🌟 시크릿 알!") on a zone card while one of my rare eggs is on that zone's belt (`EggBelt.OnSpecialChanged`); rare eggs are not in the egg icon row |
| EggBelt | UI-CORE | per-player belt eggs (Reset/Add/Remove/Bought), positions/life via `Config.BeltEggSpot(zone, age, eggId)` / `BeltEggLife(eggId)` / `BeltEggBuyEnd(eggId)`. ★v6 rare eggs: taller tier-coloured beacon (×1.4/1.6/1.8 of Premium) with halo, soft colour-cycling ground ring + Highlight, sign "🌟 <알 이름>!" + "⏳ time left", billboard name / "🎁 <펫> 확정!" / price / tier; API `Specials()`, `SpecialZones()`, `Find(zone, eggId)`, `TimeLeft(uid)`, `OnSpecialChanged(fn)` |
| ★ ZoneClient | WORLD | `ZoneClient.Init()`: local gate collision/visuals for locked zones (re-applied on every sync), entering-zone banner ("🦆 호수에 왔어요!"), optional local Lighting tint from `Palette.Sky` (space = night) |
| ★ ShopWindow | UI-NEW | `Open(tab?: "Clothes" \| "Furniture")`; 👕 옷 tab: 14 accessories (viewport, name, slot icon, price / "보유 ✓", 구매); 🛋 가구 tab: categories (`Config.FurnitureCategories`), cards with viewport, price, "가방에 N개", 구매, and "🪑 꾸미러 가기" → `DecorateMode.Enter()` |
| ★ DecorateMode | UI-NEW | `Enter(floor?)`, `Exit()`, `IsActive()`: only in my own house or ★v4 yard (standing anywhere on my plot ground counts as floor 1, no teleport; otherwise teleports via Teleport "Floor"); hint "🌳 울타리 안 아무 데나 놓을 수 있어요!"; bottom tray of FurnitureInv items; ghost model follows mouse/touch ray on the plane y = origin.Y + ★v4 `HouseLayout.PlaceY(...)`, snapped to `Decor.Snap`, green/red tint from ★v4 `HouseLayout.CheckPlace` (same function as the server); tap/click places (PlaceFurniture), tapping a placed piece selects it → 🔄 회전 (MoveFurniture with r + 90), ✋ 옮기기, 📦 넣기 (PickupFurniture); keys: R rotate, X/Delete pick up, Esc/Q exit; floor ▲▼ buttons |
| ★ LeaderboardWindow | BOARD | `Init(gui)`, `Open/Close/IsOpen`, `SetBoard(board)` (from LeaderboardSync); tabs ⚡ 초당 / 🔄 환생, top 10 with 🥇🥈🥉, my row highlighted, "🌍 전체 서버" or "🏠 이 서버" |

Prompt filtering: only `PromptKind = "Owner"` hiding. Keys: B bag, N index, H house, P shop, M map, L leaderboard, R rebirth.

---

## 11. Zone / pet / egg tables (★ = new id). In-zone rarity: C×2 (zone 1: ×4), U, R, E, L, M, S

| zone | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| 1 숲 마을 | Chick 2, Bunny 2, Hamster 3, Piglet 3 | Puppy 4 | Cat 5 | Owl 7 | Fox 9 | RainbowCat 14 | ★SpiritDeer 25 |
| 2 호수 | Duck 10, Frog 12 | Hedgehog 15 | Squirrel 22 | Raccoon 32 | Turtle 45 | Axolotl 70 | ★MoonKoi 120 |
| 3 정글 | Monkey 50, Parrot 60 | Koala 75 | Bear 110 | Lion 160 | Panda 225 | ★Peacock 350 | ★WhiteTiger 600 |
| 4 겨울 산 | Penguin 240, Seal 290 | SnowBunny 360 | Snowman 530 | PolarBear 770 | Reindeer 1.08K | ★FrostFox 1.7K | ★Yeti 2.9K |
| 5 바다 | Crab 1.2K, Jellyfish 1.45K | Octopus 1.8K | BabyShark 2.65K | Dolphin 3.85K | ★Narwhal 5.4K | ★MermaidCat 8.4K | ★DragonKing 14.5K |
| 6 캔디 랜드 | CottonSheep 6K, DonutPuppy 7.2K | JellyBear 9K | CupcakeCat 13K | MacaronBunny 19K | ★GummyDragon 27K | ★CandyUnicorn 42K | ★CookieKing 72K |
| 7 구름 왕국 | Sheep 30K, ★CloudPuppy 36K | ★BabyCloud 45K | Dragon 66K | Unicorn 96K | ★Pegasus 135K | Phoenix 210K | ★AngelBunny 360K |
| 8 우주 | Alien 150K, RobotPuppy 180K | MoonBunny 225K | SpaceCat 330K | ★AstroBear 480K | ★CometFox 675K | StarSlime 1.05M | CosmicWhale 2M |

★v4 eggs: **41** (`Config.ZoneEggOrder[zone]` = ladder order). Cell = id name (price, hatch s, belt SpawnWeight). **Premium** =
top two rungs (zones 2–8: rungs 4–5, zone 1: 5–6) → glow, beacon, EggAlert ("Top" = last rung, "Second" = the one before).
| zone | rung 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| 1 숲 마을 | Basic 기본 알 (50, 8s, w 40) | ★Flower 꽃 알 (150, 10s, w 24) | ★Mushroom 버섯 알 (500, 14s, w 12) | Forest 숲속 알 (1.5K, 20s, w 6) | ★Fairy 요정 알 (5K, 28s, w 3) | ★Spirit 정령 알 (15K, 36s, w 1.5) |
| 2 호수 | Lake 호수 알 (2K, 12s, w 40) | ★Lily 연꽃 알 (6K, 16s, w 24) | ★Bubble 물방울 알 (20K, 22s, w 11) | ★Moonlight 달빛 알 (40K, 29s, w 5) | Crystal 크리스탈 알 (100K, 36s, w 2) | — |
| 3 정글 | Jungle 정글 알 (24K, 15s, w 40) | ★Leaf 나뭇잎 알 (75K, 20s, w 24) | Spotted 점박이 알 (200K, 27s, w 11) | ★Tropical 열대 알 (500K, 36s, w 5) | ★Tiger 호랑이 알 (1.2M, 45s, w 2) | — |
| 4 겨울 산 | Snow 겨울 알 (300K, 18s, w 40) | ★Ice 얼음 알 (1M, 24s, w 24) | ★Snowflake 눈꽃 알 (2.5M, 32s, w 11) | ★Aurora 오로라 알 (6M, 43s, w 5) | Twilight 황혼 알 (15M, 54s, w 2) | — |
| 5 바다 | Ocean 바다 알 (3M, 22s, w 40) | ★Shell 조개 알 (10M, 30s, w 24) | ★Coral 산호 알 (25M, 40s, w 11) | Pearl 진주 알 (60M, 53s, w 5) | ★DragonPalace 용궁 알 (150M, 66s, w 2) | — |
| 6 캔디 랜드 | Candy 캔디 알 (30M, 26s, w 40) | ★Jelly 젤리 알 (100M, 35s, w 24) | ★Lollipop 막대사탕 알 (250M, 47s, w 11) | ★Cake 케이크 알 (600M, 62s, w 5) | Rainbow 무지개 알 (1.5B, 78s, w 2) | — |
| 7 구름 왕국 | Cloud 구름 알 (300M, 30s, w 40) | ★Breeze 바람 알 (1B, 40s, w 24) | ★Feather 깃털 알 (2.5B, 54s, w 11) | ★Angel 천사 알 (6B, 72s, w 5) | Golden 황금 알 (15B, 90s, w 2) | — |
| 8 우주 | Space 우주 알 (3B, 35s, w 40) | ★Moon 달 알 (10B, 47s, w 24) | ★Planet 행성 알 (25B, 63s, w 11) | ★Comet 혜성 알 (60B, 84s, w 5) | Starlight 별빛 알 (150B, 105s, w 2) | — |

Rarity labels (`Egg.Rarity`): zone 1 Common / Uncommon / Rare / Epic / Legendary / Mythic; zones 2–8 Common / Rare / Epic / Legendary / Mythic.
Hatch = zone base × 1 / 1.35 / 1.8 / 2.4 / 3.0 (bases 12, 15, 18, 22, 26, 30, 35 s); price = base × 1 / 3 / 8 / 20 / 50 (rounded nicely).
**Pet weights = sliding rarity window** (% per egg; C1/C2 = the zone's two commons):
| rung | zones 2–8 |
|---|---|
| 1 | C1 35, C2 31, U 28, R 6 |
| 2 | C1 12, C2 12, U 32, R 28, E 13, L 3 |
| 3 | U 16, R 34, E 32, L 15, M 3 |
| 4 | R 16, E 36, L 32, M 15.7, **S 0.3** |
| 5 | E 24, L 42, M 33, **S 1** |
Zone 8: 혜성 알 has no secret (M 16); 별빛 알 = E 24, L 42, M 33.75, **CosmicWhale 0.25** (the only source).
Zone 1: 기본 Chick 17, Bunny 17, Hamster 16, Piglet 16, Puppy 27, Cat 7 · 꽃 Chick 7, Bunny 7, Hamster 9, Piglet 9, Puppy 32, Cat 26,
Owl 8, Fox 2 · 버섯 Hamster 4, Piglet 4, Puppy 22, Cat 34, Owl 26, Fox 9, RainbowCat 1 · 숲속 Puppy 10, Cat 28, Owl 34, Fox 22,
RainbowCat 6 · 요정 Cat 14, Owl 34, Fox 34, RainbowCat 17.5, **SpiritDeer 0.5** · 정령 Owl 23, Fox 42, RainbowCat 33, **SpiritDeer 2**.

---

## 12. Tier visuals (`Config.Tiers[t].Visual`, implemented in `PetModels.applyTier`)

Parts named `Eye`, `EyeWhite`, `Pupil`, `Shine`, `Blush` keep their colour. Particle rate and light grow with the tier.
Sparkles use LightEmission 0.6 (`TIER_SPARKLE_EMISSION`). ★v5 calm pass (house glare): the client (`WorldFx`) calms pedestal pets (`Bob` models, tier + rarity effects) once each — PointLight brightness × 0.3 and range × 0.75, sparkle rate × 0.3 with LightEmission ≤ 0.35, Reflectance × 0.5 (`PED_LIGHT_MULT`, `PED_LIGHT_RANGE_MULT`, `PED_SPARKLE_MULT`, `PED_SPARKLE_EMISSION`, `PED_REFLECT_MULT`), pedestal pets never hue-cycle (`PED_CYCLE = false`) and bob-sway 0.03; followed/ridden/held pets keep the full values below and rainbow pets you own cycle at 0.07 turns/s (`CYCLE_SPEED`). House: lamps × 0.65 (`HOUSE_LIGHT_MULT`, furniture `FURNITURE_LIGHT_MULT`), galaxy wall caps 75 % / eave bands 35 % toward deep navy, warm-gold collector pad (Transparency 0.3), planet ring Transparency 0.45; lighting: bloom 0.18 / size 20 / threshold 2.1, EnvironmentSpecularScale 0.28, atmosphere glare 0.05; the "!" badge pulses 3 slow beats (scale 1.1) then stays still.
| tier | look |
|---|---|
| 1 기본 | unchanged |
| 2 🥉 브론즈 | lerp colours 60 % toward copper (205,127,50), Reflectance 0.06, 2 copper sparkles/s, faint warm light |
| 3 🥈 실버 | lerp 70 % toward (200,205,215), Material Metal, Reflectance 0.15, 3 white sparkles/s |
| 4 🥇 골드 | lerp 70 % toward gold (255,200,60), Reflectance 0.1, 6 gold sparkles/s, gold PointLight 0.6 |
| 5 🌈 레인보우 | vertical hue gradient bottom→top (v2 rainbow), 9 rainbow sparkles/s, light 1, model attribute `TierCycle = true` (client may slowly cycle the hue of nearby models) |
| 6 💎 다이아 | lerp 80 % toward light blue (170,230,255), Material Glass, Transparency 0.2 (body parts only, never eyes), Reflectance 0.2, 12 white-cyan sparkles/s, light 1.2 |
| 7 🌌 갤럭시 | deep navy → purple gradient (45,30,110 → 110,60,200) bottom→top, ~10 tiny **Neon** star specks (white/yellow balls 0.15–0.25) welded on the surface, 16 purple/blue/white star particles/s, light 1.5 |

---

## 13. LOOK lines for the model agent (cute chibi style like the existing builders, front = −Z)

### New pets
| id | name | look |
|---|---|---|
| SpiritDeer | 정령 사슴 | white-mint fawn, branching antlers with tiny green leaves, glowing mint Neon spots on its back, 2–3 tiny yellow Neon firefly balls floating beside it |
| MoonKoi | 달빛 잉어 | chubby silver-white koi standing on its tail fin, orange-red patches, big flowing tail, pale-yellow Neon crescent moon on the forehead |
| Peacock | 공작새 | round royal-blue bird, small crest, big upright fan tail of teal/green feathers with gold "eye" dots |
| WhiteTiger | 백호 | chubby white tiger cub with blue-grey stripes, ice-blue Neon eyes, fluffy tail (Korean guardian 백호) |
| FrostFox | 눈꽃 여우 | pale icy-blue fox, huge fluffy white tail ending in a Glass ice crystal, snowflake mark on the forehead |
| Yeti | 예티 | round fluffy white snow-baby giant, light-blue face, two tiny horns, big feet, holding a small snowball |
| Narwhal | 일각고래 | round light-blue whale, white belly, long spiral cream horn, tiny flippers |
| MermaidCat | 인어 냥이 | cream kitten upper body with a teal-to-pink scaly fish tail, pink seashell on its head |
| DragonKing | 용왕 | sea-green eastern long dragon curled in an S, gold horns and whiskers, holding a glowing white Neon pearl |
| GummyDragon | 젤리 용 | translucent (Glass, Transparency ≈ 0.3) red-orange gummy baby dragon, stubby wings, sugar-sparkle dots |
| CandyUnicorn | 사탕 유니콘 | pastel-pink unicorn, red-white candy-cane spiral horn, cotton-candy mane and tail (pink/blue blobs) |
| CookieKing | 쿠키 왕 | gingerbread-man cookie (brown) with white icing lines, gumdrop buttons, tiny gold crown |
| CloudPuppy | 구름 강아지 | white puppy made of puffy cloud balls, light-blue nose, floppy ears |
| BabyCloud | 아기 구름 | small smiling white cloud (cluster of spheres) with rosy cheeks and a mini rainbow arc underneath |
| Pegasus | 페가수스 | white pony with big white feathered wings, light-blue mane, golden hooves |
| AngelBunny | 천사 토끼 | white bunny with small feathery wings and a floating gold Neon halo above the head |
| AstroBear | 우주곰 | brown teddy bear in a white space suit, clear Glass bubble helmet, small antenna |
| CometFox | 혜성 여우 | deep-blue fox whose tail is a glowing comet trail (Neon cyan → white pieces), star mark on the forehead |

### New eggs
v3 eggs keep their hand-made builders. ★v4: the 25 new eggs carry `Config.Eggs[id].Look = { Base, Accent, Accent2?, Pattern, Shine?, Glow? }`
(Pattern ∈ the 16 names PetModels' pattern builder knows); `PetModels.BuildEgg` builds them from it (hand-made builders win).

### Accessories (`Config.Accessories`, Slot in brackets)
PartyHat 고깔모자 [Head] pink cone, white polka dots, yellow pom-pom · Sunglasses 선글라스 [Face] black rounded shades ·
BowTie 나비넥타이 [Neck] red bow tie · FlowerCrown 꽃 화관 [Head] ring of 6 tiny multicolour flowers with leaves ·
Scarf 목도리 [Neck] red-white striped wrap with a hanging end · HeartGlasses 하트 안경 [Face] pink heart lenses (Transparency 0.2) ·
Mustache 콧수염 [Face] curly brown mustache · TopHat 신사 모자 [Head] black top hat with a red band ·
Backpack 꼬마 가방 [Back] small yellow backpack with straps · Medal 금메달 [Neck] blue ribbon with a gold disc ·
WizardHat 마법사 모자 [Head] floppy purple cone with yellow Neon stars and a wide brim · Cape 망토 [Back] red cape with gold trim ·
AngelWings 천사 날개 [Back] pair of white feathered wings · Crown 왕관 [Head] gold 5-point crown with red/blue gem balls.

### Furniture (`Config.Furniture`, Size X × Y × Z)
PottedPlant 화분 2×3.5×2 terracotta pot, round green bush · WoodChair 나무 의자 2.5×3.5×2.5 light wood, heart cut-out back ·
PetBed 펫 쿠션 4×1.2×4 round pink cushion with a raised rim · Rug 동그란 러그 8×0.2×8 round pastel rug with a ring pattern (no collide) ·
RoundTable 둥근 탁자 4×3×4 white round top, one thick leg · BeanBag 빈백 3.5×2.5×3.5 squishy lime blob · ToyBlocks 장난감 블록 3×2×3 stacked
primary-colour cubes with letters · Cactus 선인장 2×4×2 cute cactus with a pink flower in a pot · FloorLamp 스탠드 조명 1.6×6×1.6 thin pole,
cream shade, warm light · Sofa 폭신 소파 7×3.5×3 puffy sky-blue sofa with cushions · Bookshelf 책장 6×7×2 wooden shelf with colourful books ·
CatTower 캣타워 3×7×3 beige posts with round platforms and a dangling ball · Bed 침대 6×3×8 white frame, pink blanket, two pillows ·
StarLamp 별 조명 2×2.5×2 yellow Neon star on a small stand · RainbowRug 무지개 러그 10×0.2×6 rainbow-striped rug (no collide) ·
BallPit 볼풀 8×2.5×8 low round pool filled with colourful balls · Aquarium 어항 5×4×2.5 glass tank on a cabinet, tiny fish, blue water ·
Slide 미끄럼틀 4×6×10 kid slide with ladder, red slide, yellow rails · Fireplace 벽난로 6×6×2.5 brick fireplace with Neon orange fire ·
Piano 피아노 6×4.5×3 glossy black upright piano with white keys · GoldStatue 황금 펫 동상 3×6×3 shiny gold cat statue on a marble base ·
Throne 왕좌 4×7×4 red-velvet gold throne with a tall back and gem.

---

## 14. FILE OWNERSHIP (phase 2) — edit only your own files

| group | files (★ = create) |
|---|---|
| LEAD (done) | `docs/DESIGN.md`, `src/shared/Config.luau`, `src/shared/Remotes.luau`, `src/server/DataService.luau` |
| WORLD | `src/server/WorldBuilder.luau`, `src/server/ConveyorService.luau`, `src/server/CoinFieldService.luau`, ★`src/server/ZoneService.luau`, `src/client/CoinField.luau`, ★`src/client/MapWindow.luau`, ★`src/client/ZoneClient.luau` |
| HOUSE-VISUAL | `src/server/HouseBuilder.luau`, ★`src/shared/HouseLayout.luau` |
| PLOT-LOGIC | `src/server/PlotService.luau`, `src/server/FollowService.luau`, `src/server/init.server.luau` |
| MODELS | `src/shared/PetModels/init.luau` + all files in `src/shared/PetModels/` (★ new pet/egg/accessory files), ★`src/shared/FurnitureModels/` (folder module) |
| UI-CORE | `src/client/Hud.luau`, `BagWindow.luau`, `HouseWindow.luau`, `IndexWindow.luau`, `RebirthWindow.luau`, `State.luau`, `UiKit.luau`, `WorldFx.luau`, `HatchFx.luau`, `Toasts.luau`, `Tips.luau`, `init.client.luau` |
| UI-NEW | ★`src/client/ShopWindow.luau`, ★`src/client/DecorateMode.luau`, ★`src/server/ShopService.luau` |
| BOARD | ★`src/server/LeaderboardService.luau`, ★`src/client/LeaderboardWindow.luau` |

Rules: code against this contract even when the other side is not written yet (a missing-module error from `check.sh` for a
file another group is creating is expected until integration — nothing else is). Need a Config/Remotes/DataService change?
Put it in your report; do not edit those files. Keep player text Korean.

---

## 15. Known breakages in the v2 code against the new data (the owners fix these)

- `PlotService.luau:117-123,712-736` floor logic is 2-floor only (BuyFloor would set Floors = 2 forever; uses `House.FloorPrice`); `:174` SlotCFrame without theme; `:389` BuildPet without Acc; `:455-462` server bob tween; `:26,1009-1030` fusion collects/ranks Slot pets (LOC_RANK has Slot); `:1144` income ignores the theme bonus (use `DataService.GetIncome`).
- `HouseBuilder.luau:21-55` all constants derive from `Layout.PlotSize` (now 64) and assume 2 floors/size 40; `:246` `floorTopOf` only knows floor 2; `:343-363` overhead sign beam blocks riders; `:984` SlotCFrame has no themeId.
- `ConveyorService.luau:42-47,325-339` single belt at the home conveyor rolls **all 16 eggs** (later zones' eggs appear at home); `:441,455` fine; billboard uses `egg.MinRebirth` (still filled).
- `CoinFieldService.luau:15-17,111-138,197,300-309` only the home field box; `FC.Count`; old value formula (no CoinMult/MaxBoost, IncomeScale now 30); `:309` extra `DataService.Sync` per pickup (remove).
- `WorldBuilder.luau:11-26,222-264,411` v2 one-map bounds/paths; plots are now 64 wide at z ±80.
- `FollowService.luau:241` BuildPet without Acc; `:408` no MaxWalkSpeed clamp.
- `PetModels/init.luau:1058-1121,1124-1133` tiers clamp to 1..3 (2/3 visuals only); 18 pet + 4 egg builders missing (fallback Chick/Basic with a warning); no accessories.
- `client/State.luau:158` clamps Floors to 2; no CoinSync handling — **coins in the HUD stop updating** until the next full DataSync.
- `client/HouseWindow.luau:60-95,262-295` 2-floor logic and `House.FloorPrice`.
- `client/BagWindow.luau:104-110` fuse button counts Slot pets (State.CountSame); `:407` own sort (use Config.CompareItems), viewports for every card (make lazy).
- `client/IndexWindow.luau:66` every secret shows "별빛 알에서… 🌌"; tier badges assume tiers 2/3.
- `init.server.luau` / `init.client.luau:103` do not start the new modules / handle CoinSync and LeaderboardSync yet.

---

## 16. Balance curve ★v4 (scratchpad `v4/sim4.py`: real Config units, Poisson belt spawns, buys from the belt only, active player)

| milestone | v4 | (v3 same sim) |
|---|---|---|
| first egg (기본 알 50, hatch 8 s) | right away (start 200 coins) | |
| first Rare+ pet | ≈ 23 s | 15 s |
| zone 2 호수 (rebirth 1) | ≈ 37 min | 33 min |
| zone 3 정글 (R2) | ≈ 1.3 h | 1.2 h |
| zone 4 겨울 산 (R3) | ≈ 2.3 h | 2.0 h |
| zone 5 바다 (R5) | ≈ 4.5 h | 4.1 h |
| zone 6 캔디 랜드 (R7) | ≈ 6.9 h | 6.5 h |
| zone 7 구름 왕국 (R10) | ≈ 11.6 h | 11.3 h |
| zone 8 우주 (R14) | ≈ 19.2 h | 19.2 h |
| R15 / R20 / R24 | 21 h / 36 h / 58 h | 32 h / 49 h / — |
| CosmicWhale | ≈ 21–31 h (별빛 알 150B, 0.25 %) | |
| first secret per zone 2…8 | 0.9, 1.6, 3.3, 5.8, 10.3, 13.6, 30 h | |
Floors: 2 ≈ 0.7 h, 3 ≈ 1.5 h, 4 ≈ 2.7 h, 5 ≈ 4.6 h, 6 ≈ 8.4 h, 7 ≈ 13 h, 8 ≈ 22 h, 9 ≈ 36 h, 10 ≈ 52 h. Offline earnings come on top.
Belt buys spread over the ladder (e.g. zone 4: 41 / 36 / 13 / 7 / 3 %). If you change pet incomes or prices, re-run `sim4.py v4 60`.
