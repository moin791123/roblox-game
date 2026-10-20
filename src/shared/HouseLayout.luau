-- 집 배치 계산 (순수 수학). 서버(HouseBuilder / ShopService / ZoneService)와 클라이언트(DecorateMode)가 같이 써요.
-- 인스턴스를 만들지 않고 기다리지도 않아요. Config 만 읽어요. (설계: docs/DESIGN.md "HouseLayout")
-- 좌표는 전부 플롯 로컬: origin = 플롯 땅 가운데 (y = 0), 입구 = 로컬 -Z (z = -32), 집 뒤 = +Z.
-- 집은 한 변 Config.ThemeSize(테마) 인 정사각형, X 가운데 정렬, 뒤쪽(z = BACK_Z)에 붙어 있어요.
--
--   +Z (뒤)  ┌──────────────────┬─────────┐
--            │  받침대 12개       │ 계단 탑  │  ← 유리 계단 탑 (반층씩 꺾이는 계단, 층마다 같은 자리)
--            │  (격자)            ├─────────┤
--            │                    │ 계단 앞  │
--            │                    │ (빈 길)  │
--            │ [수금] [입구 길]    │ 엘리베이터│
--   -Z (앞)  └────────[ 문 ]─────┴─────────┘
local Config = require(script.Parent.Config)

local HouseLayout = {}

----------------------------------------------------------------------
-- 상수 (스터드)
----------------------------------------------------------------------
local FH = Config.House.FloorHeight -- 12: 층 사이 높이
local FLOOR1_TOP = 0.2 -- 1층 바닥 윗면 (땅 y = 0 보다 살짝 위)
local PLOT = Config.Layout.PlotSize -- 64
local BACK_Z = PLOT / 2 - 4 -- 집 뒷벽 바깥면 z (뒤 울타리와 4 띄움)
local WALL_T = 1 -- 벽/난간 두께
local RAIL_H = 3 -- 벽/난간 높이 (모든 층)
local SLAB_T = 1 -- 위층 바닥 두께 (천장 아래 11)
local TOP_H = 14.6 -- 꼭대기 층 바닥 → 처마 (1층 집도 문 높이 14 이상)

local DOOR_W = 10 -- 문 너비 (≥ 9, 위는 뻥 뚫림)
local ENTRANCE_D = 6 -- 문 안쪽 입구 길 깊이 (가구 금지)
local PORCH_W = 11 -- 2층 바닥에 뚫린 현관 구멍 (문 위 14 이상 비우기)
local PORCH_D = 5 -- 집 앞면에서 안쪽으로

local STAIR_W = 4.2 -- 계단 한 줄 폭 (≥ 4)
local DIVIDER_T = 0.3 -- 계단 두 줄 사이 칸막이
local GLASS_T = 0.3 -- 계단 탑 안쪽 유리벽 두께
local STEP_RUN = 1.2 -- 한 칸 깊이 (45°)
local MAX_RISE = 1.2 -- 한 칸 높이 최대
local MID_LANDING_D = 4 -- 반층 참 깊이
local FLOOR_LANDING_D = 3 -- 층마다 계단 앞 빈 자리
local TREAD_T = 0.9 -- 계단 판 두께 (위 계단과 11.1 띄움)

local ELEV_W = 5.2 -- 엘리베이터 문틀 너비
local ELEV_D = 0.75 -- 문틀 + 문 두께 (앞벽 안쪽에 붙어요)
local ELEV_APPROACH = 3 -- 엘리베이터 앞 빈 자리

local COLLECTOR_D = 4.4
local SPAWN_SIZE = 4

local PED_MIN_D = 4.2 -- 받침대 아래판 지름 (작은 집)
local PED_MAX_D = 5.4 -- (큰 집)
local PED_TOP_INSET = 0.8 -- 윗판 지름 = 아래판 - 0.8
local PED_BASE_H = 0.6
local PED_TOP_H = 1.0
local PED_H = PED_BASE_H + PED_TOP_H -- 받침대 윗면 = 바닥 + 1.6
local MIN_SP = 5 -- 받침대 사이 최소 간격 (가운데 ↔ 가운데)
local MAX_SP = 9 -- 큰 집에서도 이보다 넓게는 안 벌려요 (가구 놓을 자리)
local PED_MARGIN = 0.4 -- 받침대 ↔ 벽/유리/입구 틈
local BLOCK_PAD = 0.5 -- BlockedRects 받침대 여유

local SLOTS = Config.Plot.SlotsPerFloor -- 12

----------------------------------------------------------------------
-- 타입
----------------------------------------------------------------------
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number, Name: string? }
export type Bounds = { MinX: number, MaxX: number, MinZ: number, MaxZ: number, Y: number }
export type Stair = {
	MinX: number, -- 계단 탑 안쪽 (유리벽 제외)
	MaxX: number,
	MinZ: number, -- 계단 시작 z (= 층 계단 앞 자리 끝)
	MaxZ: number, -- 반층 참 뒤 끝
	GlassX: number, -- 안쪽 유리벽 바깥면 x (= MinX - GLASS_T)
	UpMinX: number, -- 첫 반층 계단 줄 (바깥쪽, +Z 로 올라가요)
	UpMaxX: number,
	DownMinX: number, -- 둘째 반층 계단 줄 (안쪽, -Z 로 올라가서 위층에 도착)
	DownMaxX: number,
	RunEndZ: number, -- 반층 참 시작 z
	LandingMinZ: number, -- 층 계단 앞 빈 자리 시작 z
	Rise: number, -- 한 칸 높이 (≤ 1.2)
	Run: number, -- 한 칸 깊이
	Treads: number, -- 반층 계단 판 수 (마지막 칸은 참/바닥)
	HalfRise: number, -- 반층 높이 (= FloorHeight / 2)
	TreadT: number,
	MidLandingD: number,
}
export type Layout = {
	Theme: string,
	Size: number,
	Half: number,
	FrontZ: number, -- 집 앞면 바깥 z
	BackZ: number,
	CenterZ: number,
	Inner: Rect, -- 벽 안쪽 (걸을 수 있는 바닥)
	Door: Rect, -- 문 (앞벽 구멍)
	Entrance: Rect, -- 문 안쪽 입구 길 (1층)
	Porch: Rect, -- 2층 바닥 구멍 (현관 위)
	Collector: { X: number, Z: number, D: number },
	Spawn: { X: number, Z: number, Size: number },
	Elevator: { X: number, Z: number, W: number, D: number, PanelMinZ: number, PanelMaxZ: number, ApproachMaxZ: number },
	Stair: Stair,
	Slots: { { X: number, Z: number } }, -- 한 층의 받침대 12개 (모든 층 같은 자리)
	PedD: number, -- 받침대 아래판 지름
	PedTopD: number,
	Grid: string, -- "4x3" | "3x4" | "hex" (어떤 모양으로 놓였는지)
	MinSpacing: number,
}

----------------------------------------------------------------------
-- 받침대 자리 찾기
----------------------------------------------------------------------
type Spot = { X: number, Z: number }

local function minDist(spots: { Spot }): number
	local best = math.huge
	for i = 1, #spots do
		for j = i + 1, #spots do
			local dx, dz = spots[i].X - spots[j].X, spots[i].Z - spots[j].Z
			best = math.min(best, math.sqrt(dx * dx + dz * dz))
		end
	end
	return best
end

-- 앞 줄부터, 줄 안에서는 x 작은 쪽부터 (슬롯 1 = 입구 쪽)
local function sortSpots(spots: { Spot })
	table.sort(spots, function(a, b)
		if math.abs(a.Z - b.Z) > 0.01 then
			return a.Z < b.Z
		end
		return a.X < b.X
	end)
end

type Region = { X0: number, X1: number, Z0: number, Z1: number }

-- 받침대 가운데가 들어갈 수 있는 사각형 (반지름 r 만큼 안쪽)
local function centerRegion(inner: Rect, glassX: number, entranceMaxZ: number, r: number): Region
	return {
		X0 = inner.MinX + PED_MARGIN + r,
		X1 = glassX - PED_MARGIN - r,
		Z0 = entranceMaxZ + PED_MARGIN + r,
		Z1 = inner.MaxZ - PED_MARGIN - r,
	}
end

-- 반듯한 격자 cols × rows 를 영역 가운데에 (간격 MIN_SP..MAX_SP). 안 들어가면 nil
local function regularGrid(reg: Region, cols: number, rows: number): ({ Spot }?, number)
	local sx = math.min((reg.X1 - reg.X0) / (cols - 1), MAX_SP)
	local sz = math.min((reg.Z1 - reg.Z0) / (rows - 1), MAX_SP)
	local sp = math.min(sx, sz)
	if sp < MIN_SP - 1e-6 then
		return nil, sp
	end
	local cx, cz = (reg.X0 + reg.X1) / 2, (reg.Z0 + reg.Z1) / 2
	local spots: { Spot } = {}
	for row = 1, rows do
		for col = 1, cols do
			table.insert(spots, {
				X = cx + (col - (cols + 1) / 2) * sx,
				Z = cz + (row - (rows + 1) / 2) * sz,
			})
		end
	end
	return spots, sp
end

-- 작은 집: 엇갈린(벌집) 줄 + 앞쪽 빈 구석 2곳. 간격은 모두 MIN_SP 이상
local function hexSpots(reg: Region, extras: { Spot }): { Spot }
	local rowGap = MIN_SP * math.sqrt(3) / 2
	local rows = math.floor((reg.Z1 - reg.Z0) / rowGap + 1e-6) + 1
	local dz = if rows > 1 then (reg.Z1 - reg.Z0) / (rows - 1) else 0
	local cands: { Spot } = {}
	for _, e in extras do
		table.insert(cands, e)
	end
	for row = 0, rows - 1 do
		local z = reg.Z0 + row * dz
		local x = reg.X0 + (if row % 2 == 1 then MIN_SP / 2 else 0)
		while x <= reg.X1 + 1e-6 do
			table.insert(cands, { X = x, Z = z })
			x += MIN_SP
		end
	end
	sortSpots(cands)
	local picked: { Spot } = {}
	for _, c in cands do
		local ok = true
		for _, p in picked do
			local ddx, ddz = c.X - p.X, c.Z - p.Z
			if ddx * ddx + ddz * ddz < (MIN_SP - 1e-3) ^ 2 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(picked, c)
			if #picked >= SLOTS then
				break
			end
		end
	end
	return picked
end

-- 마지막 수단: 자리가 정말 모자라면 4×3 을 좁게라도 (설정이 바뀌어 집이 아주 작아졌을 때)
local function squeezedGrid(reg: Region): { Spot }
	local spots: { Spot } = {}
	for row = 1, 3 do
		for col = 1, 4 do
			table.insert(spots, {
				X = reg.X0 + (col - 1) * (reg.X1 - reg.X0) / 3,
				Z = reg.Z0 + (row - 1) * (reg.Z1 - reg.Z0) / 2,
			})
		end
	end
	return spots
end

----------------------------------------------------------------------
-- 테마별 배치 (한 번 계산해서 저장)
----------------------------------------------------------------------
local cache: { [string]: Layout } = {}

local function themeKey(themeId: any): string
	if type(themeId) == "string" and Config.House.Themes[themeId] then
		return themeId
	end
	return "Basic"
end

local function compute(id: string): Layout
	local S = Config.ThemeSize(id)
	local half = S / 2
	local zb = BACK_Z
	local zf = zb - S
	local h = half - WALL_T
	local inner: Rect = { MinX = -h, MaxX = h, MinZ = zf + WALL_T, MaxZ = zb - WALL_T }

	-- 계단 탑 (뒤 오른쪽). 반층 = FH/2, 칸 높이 ≤ 1.2
	local halfRise = FH / 2
	local risers = math.ceil(halfRise / MAX_RISE - 1e-6)
	local rise = halfRise / risers
	local treads = risers - 1 -- 마지막 칸은 참 / 위층 바닥
	local run = treads * STEP_RUN
	local tx1 = inner.MaxX
	local tx0 = tx1 - (2 * STAIR_W + DIVIDER_T)
	local tz1 = inner.MaxZ
	local tz0 = tz1 - (run + MID_LANDING_D)
	local stair: Stair = {
		MinX = tx0,
		MaxX = tx1,
		MinZ = tz0,
		MaxZ = tz1,
		GlassX = tx0 - GLASS_T,
		UpMinX = tx0 + STAIR_W + DIVIDER_T,
		UpMaxX = tx1,
		DownMinX = tx0,
		DownMaxX = tx0 + STAIR_W,
		RunEndZ = tz0 + run,
		LandingMinZ = tz0 - FLOOR_LANDING_D,
		Rise = rise,
		Run = STEP_RUN,
		Treads = treads,
		HalfRise = halfRise,
		TreadT = TREAD_T,
		MidLandingD = MID_LANDING_D,
	}

	local entrance: Rect = { MinX = -DOOR_W / 2, MaxX = DOOR_W / 2, MinZ = inner.MinZ, MaxZ = inner.MinZ + ENTRANCE_D, Name = "Entrance" }

	-- 엘리베이터: 앞벽 안쪽 오른쪽 (문 옆), 집 안을 바라봐요
	local ex = inner.MaxX - 0.6 - ELEV_W / 2
	local elevator = {
		X = ex,
		Z = inner.MinZ + ELEV_D / 2,
		W = ELEV_W,
		D = ELEV_D,
		PanelMinZ = inner.MinZ,
		PanelMaxZ = inner.MinZ + ELEV_D,
		ApproachMaxZ = inner.MinZ + ELEV_D + ELEV_APPROACH,
	}

	-- 받침대: 반듯한 격자 (4×3 / 3×4 중 간격이 넓은 쪽). 안 되면 벌집 + 앞 구석
	local r0 = PED_MIN_D / 2
	local reg0 = centerRegion(inner, stair.GlassX, entrance.MaxZ, r0)
	local best: { Spot }? = nil
	local bestSp = -1
	local bestGrid = "hex"
	for _, shape in { { 4, 3 }, { 3, 4 } } do
		local spots, sp = regularGrid(reg0, shape[1], shape[2])
		if spots and sp > bestSp + 1e-6 then
			best, bestSp, bestGrid = spots, sp, shape[1] .. "x" .. shape[2]
		end
	end
	local pedD = PED_MIN_D
	local spots: { Spot }
	if best then
		-- 간격이 넓으면 받침대도 조금 크게 (그래도 들어가는지 다시 확인)
		local d = math.clamp(bestSp - 1, PED_MIN_D, PED_MAX_D)
		local cols = if bestGrid == "4x3" then 4 else 3
		local rows = SLOTS // cols
		local again, sp2 = regularGrid(centerRegion(inner, stair.GlassX, entrance.MaxZ, d / 2), cols, rows)
		if again and sp2 >= MIN_SP then
			spots, pedD = again, d
		else
			spots = best
		end
	else
		-- 앞 왼쪽 구석 + 엘리베이터와 계단 앞 사이 오른쪽 자리 (오른쪽 길은 남겨요)
		local extras: { Spot } = {
			{ X = inner.MinX + PED_MARGIN + r0, Z = inner.MinZ + 0.5 + r0 },
			{
				X = inner.MaxX - PED_MARGIN - r0,
				Z = ((elevator.ApproachMaxZ + PED_MARGIN + r0) + (stair.LandingMinZ - PED_MARGIN - r0)) / 2,
			},
		}
		spots = hexSpots(reg0, extras)
		if #spots < SLOTS then
			spots = squeezedGrid(reg0)
			bestGrid = "squeezed"
		end
	end
	sortSpots(spots)
	local slots: { { X: number, Z: number } } = {}
	for i = 1, SLOTS do
		local s = spots[i]
		slots[i] = { X = s.X, Z = s.Z }
	end

	return {
		Theme = id,
		Size = S,
		Half = half,
		FrontZ = zf,
		BackZ = zb,
		CenterZ = (zf + zb) / 2,
		Inner = inner,
		Door = { MinX = -DOOR_W / 2, MaxX = DOOR_W / 2, MinZ = zf, MaxZ = zf + WALL_T, Name = "Door" },
		Entrance = entrance,
		Porch = { MinX = -PORCH_W / 2, MaxX = PORCH_W / 2, MinZ = zf, MaxZ = zf + PORCH_D, Name = "Porch" },
		Collector = { X = -2.6, Z = entrance.MinZ + 3, D = COLLECTOR_D },
		Spawn = { X = 2.6, Z = entrance.MinZ + 3, Size = SPAWN_SIZE },
		Elevator = elevator,
		Stair = stair,
		Slots = slots,
		PedD = pedD,
		PedTopD = pedD - PED_TOP_INSET,
		Grid = if best then bestGrid else (if bestGrid == "squeezed" then "squeezed" else "hex"),
		MinSpacing = minDist(spots),
	}
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------
HouseLayout.FLOOR_HEIGHT = FH
HouseLayout.FLOOR1_TOP = FLOOR1_TOP
HouseLayout.WALL_T = WALL_T
HouseLayout.RAIL_H = RAIL_H
HouseLayout.SLAB_T = SLAB_T
HouseLayout.TOP_H = TOP_H
HouseLayout.PED_BASE_H = PED_BASE_H
HouseLayout.PED_TOP_H = PED_TOP_H
HouseLayout.PED_H = PED_H

-- 테마 배치 전체 (읽기만 하세요). 모르는 테마는 Basic
function HouseLayout.Get(themeId: any): Layout
	local id = themeKey(themeId)
	local l = cache[id]
	if not l then
		l = compute(id)
		cache[id] = l
	end
	return l
end

-- floor 층 바닥 윗면 (플롯 로컬 y) = 0.2 + (floor - 1) × FloorHeight
function HouseLayout.FloorY(floor: number): number
	return FLOOR1_TOP + (math.max(math.floor(tonumber(floor) or 1), 1) - 1) * FH
end

-- 플롯 로컬 y 가 몇 층인지 (계단 중간이면 아래층). 1..MaxFloors
function HouseLayout.FloorAtY(localY: number): number
	local f = math.floor(((tonumber(localY) or 0) - FLOOR1_TOP + 1) / FH) + 1
	return math.clamp(f, 1, Config.House.MaxFloors)
end

-- 꼭대기 층이 floors 일 때 처마(지붕 밑) 높이 (플롯 로컬 y)
function HouseLayout.RoofY(floors: number): number
	return HouseLayout.FloorY(floors) + TOP_H
end

-- 집 정사각형 (벽 바깥면, 플롯 로컬 XZ)
function HouseLayout.Footprint(themeId: any): Rect
	local l = HouseLayout.Get(themeId)
	return { MinX = -l.Half, MaxX = l.Half, MinZ = l.FrontZ, MaxZ = l.BackZ, Name = "House" }
end

-- 받침대 윗면 (아이템 모델 바닥 피벗) 플롯 로컬 CFrame. 받침대 s 는 ceil(s / 12) 층. 앞(-Z, 입구)을 바라봐요
function HouseLayout.SlotLocal(slot: number, themeId: any): CFrame
	local l = HouseLayout.Get(themeId)
	local s = math.max(math.floor(tonumber(slot) or 1), 1)
	local spot = l.Slots[(s - 1) % SLOTS + 1]
	return CFrame.new(spot.X, HouseLayout.FloorY(Config.SlotFloor(s)) + PED_H, spot.Z)
end

-- 받침대 윗면 월드 CFrame = origin * SlotLocal
function HouseLayout.SlotCFrame(origin: CFrame, slot: number, themeId: any): CFrame
	return origin * HouseLayout.SlotLocal(slot, themeId)
end

-- 그 층에서 걸을 수 있는 바닥 (벽 안쪽). 가구는 여기서 Decor.WallMargin 만큼 더 안쪽에
function HouseLayout.FloorBounds(themeId: any, floor: number): Bounds
	local inner = HouseLayout.Get(themeId).Inner
	return { MinX = inner.MinX, MaxX = inner.MaxX, MinZ = inner.MinZ, MaxZ = inner.MaxZ, Y = HouseLayout.FloorY(floor) }
end

-- 가구를 놓으면 안 되는 사각형들 (플롯 로컬 XZ). 받침대(+0.5), 계단 탑 + 계단 앞 자리, 엘리베이터 + 앞자리,
-- 1층: 입구 길 / 수금 패드 / 스폰, 2층: 현관 구멍. 계단 자리는 1층짜리 집에서도 비워 둬요 (층을 올려도 가구가 안 걸려요)
function HouseLayout.BlockedRects(themeId: any, floor: number): { Rect }
	local l = HouseLayout.Get(themeId)
	local f = math.max(math.floor(tonumber(floor) or 1), 1)
	local rects: { Rect } = {}
	local r = l.PedD / 2 + BLOCK_PAD
	for i, s in l.Slots do
		table.insert(rects, { MinX = s.X - r, MaxX = s.X + r, MinZ = s.Z - r, MaxZ = s.Z + r, Name = "Pedestal" .. ((f - 1) * SLOTS + i) })
	end
	local st = l.Stair
	table.insert(rects, { MinX = st.GlassX, MaxX = st.MaxX, MinZ = st.MinZ, MaxZ = st.MaxZ, Name = "Stairs" })
	table.insert(rects, { MinX = st.GlassX, MaxX = st.MaxX, MinZ = st.LandingMinZ, MaxZ = st.MinZ, Name = "StairLanding" })
	local e = l.Elevator
	table.insert(rects, { MinX = e.X - e.W / 2 - 0.3, MaxX = e.X + e.W / 2 + 0.3, MinZ = e.PanelMinZ, MaxZ = e.ApproachMaxZ, Name = "Elevator" })
	if f == 1 then
		local en = l.Entrance
		table.insert(rects, { MinX = en.MinX, MaxX = en.MaxX, MinZ = en.MinZ, MaxZ = en.MaxZ, Name = "Entrance" })
		local c = l.Collector
		local cr = c.D / 2 + 0.4
		table.insert(rects, { MinX = c.X - cr, MaxX = c.X + cr, MinZ = c.Z - cr, MaxZ = c.Z + cr, Name = "Collector" })
		local sp = l.Spawn
		local sr = sp.Size / 2
		table.insert(rects, { MinX = sp.X - sr, MaxX = sp.X + sr, MinZ = sp.Z - sr, MaxZ = sp.Z + sr, Name = "SpawnPoint" })
	elseif f == 2 then
		local p = l.Porch
		table.insert(rects, { MinX = p.MinX - 0.4, MaxX = p.MaxX + 0.4, MinZ = l.Inner.MinZ, MaxZ = p.MaxZ + 0.4, Name = "Porch" })
	end
	return rects
end

-- 엘리베이터 문틀 가운데 (그 층 바닥 높이), 집 안(+Z)을 바라봐요. 플롯 로컬
function HouseLayout.ElevatorLocal(themeId: any, floor: number): CFrame
	local e = HouseLayout.Get(themeId).Elevator
	return CFrame.new(e.X, HouseLayout.FloorY(floor), e.Z) * CFrame.Angles(0, math.pi, 0)
end

-- 그 층으로 순간이동할 자리 (월드): 엘리베이터 바로 앞, 집 안을 바라보고, 이미 3 스터드 위
function HouseLayout.FloorSpawn(origin: CFrame, themeId: any, floor: number): CFrame
	local e = HouseLayout.Get(themeId).Elevator
	local z = (e.PanelMaxZ + e.ApproachMaxZ) / 2
	return origin * CFrame.new(e.X, HouseLayout.FloorY(floor) + 3, z) * CFrame.Angles(0, math.pi, 0)
end

-- 두 사각형이 겹치나 (모서리만 닿으면 안 겹침). DecorateMode 미리보기용
function HouseLayout.RectsOverlap(a: Rect, b: Rect): boolean
	local eps = 1e-4
	return a.MinX < b.MaxX - eps and b.MinX < a.MaxX - eps and a.MinZ < b.MaxZ - eps and b.MinZ < a.MaxZ - eps
end

return HouseLayout
