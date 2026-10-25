--!strict
-- 집 배치 계산 (순수 수학). 서버(HouseBuilder / ShopService / ZoneService)와 클라이언트(DecorateMode)가 같이 써요.
-- 인스턴스를 만들지 않고 기다리지도 않아요. Config 만 읽어요. (설계: docs/DESIGN.md "HouseLayout")
-- 좌표는 전부 플롯 로컬: origin = 플롯 땅 가운데 (y = 0), 입구 = 로컬 -Z (z = -32), 집 뒤 = +Z.
-- 집은 한 변 Config.ThemeSize(테마) 인 정사각형, X 가운데 정렬, 뒤쪽(z = BACK_Z)에 붙어 있어요.
-- ★ 가구 자리: 1층 = 울타리 안 전체 (마당 + 집 안), 위층 = 집 안. 놓기 규칙은 CheckPlace 하나 (서버·클라이언트 공용)
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

-- 마당 (울타리 안). HouseBuilder 가 이 숫자 그대로 지어요
local FENCE = PLOT / 2 - 0.4 -- 울타리 가운데 선 (±31.6)
local FENCE_T = 0.6 -- 울타리 두께
local YARD_IN = FENCE - FENCE_T / 2 -- 울타리 안쪽 면 (±31.3) = 1층 가구 자리 끝
local YARD_Y = 0.06 -- 마당 바닥 윗면 (집 1층 바닥 0.2 보다 살짝 낮아요)
local GATE_HALF = 6 -- 마당 문 반 폭 (기둥 안쪽 면 사이 12)
local GATE_POST = 1.2 -- 마당 문 기둥 두께
local PILLAR = 1.6 -- 집 모서리 기둥
local TRIM = 0.7 -- 집 둘레 바닥 띠 (벽 바깥으로)
local WALL_MARGIN = Config.Decor.WallMargin -- 가구 ↔ 벽/울타리 틈
local EPS = 1e-3 -- 딱 붙는 건 괜찮아요 (겹침/벽 판정 여유)

-- 테마 장식이 마당에서 차지하는 자리 (HouseBuilder DECO.* 와 같이 맞춰요).
-- Spot = 앞마당 자리 번호 (Yard.Spots), Side = 옆마당 자리 번호 (Yard.Side), DX = 자리에서 x 로 비킨 만큼, HX/HZ = 반 크기
type DecoUse = { Spot: number?, Side: number?, DX: number?, HX: number, HZ: number }
local DECO_YARD: { [string]: { DecoUse } } = {
	flowers = { { Spot = 1, DX = 2, HX = 3, HZ = 1.3 } }, -- 꽃밭
	candy = { -- 막대사탕 3개 + 옆마당 1개 (지팡이 사탕은 화분 자리)
		{ Spot = 1, HX = 1.2, HZ = 1.2 },
		{ Spot = 2, HX = 1.2, HZ = 1.2 },
		{ Spot = 3, HX = 1.2, HZ = 1.2 },
		{ Side = 2, HX = 1.2, HZ = 1.2 },
	},
	mushrooms = { { Spot = 1, HX = 1.65, HZ = 1.65 }, { Spot = 2, HX = 1.65, HZ = 1.65 }, { Spot = 3, HX = 1.65, HZ = 1.65 } }, -- 버섯 램프
	shells = { { Spot = 1, DX = 1.5, HX = 2.8, HZ = 2.8 }, { Spot = 3, HX = 0.9, HZ = 0.8 }, { Spot = 4, HX = 0.9, HZ = 0.8 } }, -- 물웅덩이 + 조개
	stars = { { Spot = 1, HX = 2.1, HZ = 2.1 } }, -- 로켓
	rainbow = { { Spot = 1, DX = 2.2, HX = 6, HZ = 1.5 } }, -- 무지개 아치 + 구름
	royal = { { Spot = 1, HX = 1.6, HZ = 1.6 }, { Spot = 3, HX = 1.6, HZ = 1.6 } }, -- 둥근 정원수
	galaxy = { { Spot = 1, HX = 2.6, HZ = 2.6 }, { Spot = 3, HX = 1.8, HZ = 1.8 } }, -- 고리 행성
}

----------------------------------------------------------------------
-- 타입
----------------------------------------------------------------------
-- Kind (막힌 자리 종류, 알림 글): "Stand" 받침대·계단·엘리베이터·수금·스폰 | "Path" 다니는 길 | "Wall" 집 벽 | "Deco" 마당 장식 | "Hole" 뚫린 바닥
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number, Name: string?, Kind: string? }
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
-- 마당 (울타리 안, 집 밖). 자리는 전부 플롯 로컬, y = 0
export type Yard = {
	Bounds: Rect, -- 울타리 안쪽 면 (1층 가구를 놓을 수 있는 땅 끝)
	Y: number, -- 마당 바닥 윗면
	Fence: number, -- 울타리 가운데 선 (±)
	FenceT: number,
	GateHalf: number,
	GatePost: number,
	Sign: { X: number, Z: number }, -- 이름 간판 기둥 (마당 문 왼쪽)
	Mail: { X: number, Z: number }, -- 우편함 (마당 문 오른쪽)
	PetHouse: { X: number, Z: number }, -- 펫 집 (앞마당 왼쪽)
	PlanterX: number, -- 현관 양옆 화분 ±x
	PlanterZ: number,
	LampX: number, -- 길가 가로등 ±x
	LampZs: { number },
	Spots: { Vector3 }, -- 앞마당 장식 자리 (울타리 근처, 길 밖)
	Side: { Vector3 }, -- 집 양옆 마당 가운데
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
	Grid: string, -- "4x3" | "3x4" | "hex" | "squeezed" (어떤 모양으로 놓였는지)
	MinSpacing: number,
	Yard: Yard,
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
	local gridName = bestGrid
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
		gridName = "hex"
		if #spots < SLOTS then
			spots = squeezedGrid(reg0)
			gridName = "squeezed"
		end
	end
	sortSpots(spots)
	local slots: { { X: number, Z: number } } = {}
	for i = 1, SLOTS do
		local s = spots[i]
		slots[i] = { X = s.X, Z = s.Z }
	end

	-- 마당: 울타리 안 (집 밖). 앞마당 장식은 앞 울타리 근처에 모아서 옆·앞마당을 가구 자리로 남겨요
	local gateOuter = GATE_HALF + GATE_POST -- 마당 문 기둥 바깥 끝 (7.2)
	local lampZs = { -FENCE + 2.4 }
	if zf + FENCE > 18 then -- 앞마당이 길면 길 중간에 한 쌍 더
		table.insert(lampZs, (zf - FENCE) / 2 + 1)
	end
	local sideX = (half + YARD_IN) / 2
	local yard: Yard = {
		Bounds = { MinX = -YARD_IN, MaxX = YARD_IN, MinZ = -YARD_IN, MaxZ = YARD_IN, Name = "Yard" },
		Y = YARD_Y,
		Fence = FENCE,
		FenceT = FENCE_T,
		GateHalf = GATE_HALF,
		GatePost = GATE_POST,
		Sign = { X = -(gateOuter + 3.2), Z = -FENCE + 0.95 },
		Mail = { X = gateOuter + 3.3, Z = -FENCE + 1.2 },
		PetHouse = { X = -19, Z = -28.2 },
		PlanterX = DOOR_W / 2 + 3.6,
		PlanterZ = zf - 1.8,
		LampX = DOOR_W / 2 + 2,
		LampZs = lampZs,
		Spots = {
			Vector3.new(15.5, 0, -28.6),
			Vector3.new(20.5, 0, -28.6),
			Vector3.new(-13.6, 0, -27.6),
			Vector3.new(25.2, 0, -28.6),
			Vector3.new(-25, 0, -28.6),
		},
		Side = { Vector3.new(-sideX, 0, (zf + zb) / 2), Vector3.new(sideX, 0, (zf + zb) / 2) },
	}

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
		Grid = gridName,
		MinSpacing = minDist(spots),
		Yard = yard,
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
HouseLayout.YARD_Y = YARD_Y -- 마당 땅 윗면 (1층 집 밖 가구 바닥)
HouseLayout.FENCE = FENCE -- 울타리 가운데 선 (±)
HouseLayout.FENCE_T = FENCE_T
HouseLayout.GATE_HALF = GATE_HALF
HouseLayout.PILLAR = PILLAR
HouseLayout.TRIM = TRIM

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
	local _, s = Config.SlotHouse(slot) -- ★v8 2번 집 받침대(121~)도 그 집 안 번호로 (원점은 부르는 쪽이 2번 집 자리로)
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

-- 가구를 놓을 수 있는 땅 끝 (플롯 로컬 XZ). 1층 = 울타리 안쪽 면까지 (마당 + 집 안), 위층 = 집 벽 안쪽.
-- 가구는 여기서 Decor.WallMargin 만큼 더 안쪽에. 그 안에서 막힌 곳은 BlockedRects (1층은 집 벽도 막혀요)
function HouseLayout.PlaceBounds(themeId: any, floor: number): Bounds
	local f = math.max(math.floor(tonumber(floor) or 1), 1)
	if f == 1 then
		local b = HouseLayout.Get(themeId).Yard.Bounds
		return { MinX = b.MinX, MaxX = b.MaxX, MinZ = b.MinZ, MaxZ = b.MaxZ, Y = YARD_Y }
	end
	return HouseLayout.FloorBounds(themeId, f)
end

-- (x, z) 가 집 정사각형(벽 바깥면) 안인가
function HouseLayout.InHouse(themeId: any, x: number, z: number): boolean
	local l = HouseLayout.Get(themeId)
	local px, pz = tonumber(x) or 0, tonumber(z) or 0
	return math.abs(px) <= l.Half and pz >= l.FrontZ and pz <= l.BackZ
end

-- 가구 바닥 높이 (플롯 로컬 y): 위층 = 그 층 바닥, 1층 = 집 안이면 집 바닥 (0.2), 마당이면 마당 땅 (0.06).
-- 1층 벽은 막혀 있어서 가구가 벽에 걸칠 일은 없어요 (가운데 점으로 정해요)
function HouseLayout.PlaceY(themeId: any, floor: number, x: number, z: number): number
	local f = math.max(math.floor(tonumber(floor) or 1), 1)
	if f >= 2 or HouseLayout.InHouse(themeId, x, z) then
		return HouseLayout.FloorY(f)
	end
	return YARD_Y
end

-- 막힌 자리 목록 만들기 (테마·층마다 한 번)
local function buildBlocked(l: Layout, f: number): { Rect }
	local rects: { Rect } = {}
	local function add(name: string, kind: string, x0: number, x1: number, z0: number, z1: number)
		table.insert(rects, { MinX = math.min(x0, x1), MaxX = math.max(x0, x1), MinZ = math.min(z0, z1), MaxZ = math.max(z0, z1), Name = name, Kind = kind })
	end
	local r = l.PedD / 2 + BLOCK_PAD
	for i, s in l.Slots do
		add("Pedestal" .. ((f - 1) * SLOTS + i), "Stand", s.X - r, s.X + r, s.Z - r, s.Z + r)
	end
	local st = l.Stair
	add("Stairs", "Stand", st.GlassX, st.MaxX, st.MinZ, st.MaxZ)
	add("StairLanding", "Stand", st.GlassX, st.MaxX, st.LandingMinZ, st.MinZ)
	local e = l.Elevator
	add("Elevator", "Stand", e.X - e.W / 2 - 0.3, e.X + e.W / 2 + 0.3, e.PanelMinZ, e.ApproachMaxZ)
	if f == 1 then
		local en = l.Entrance
		add("Entrance", "Path", en.MinX, en.MaxX, en.MinZ, en.MaxZ)
		local c = l.Collector
		local cr = c.D / 2 + 0.4
		add("Collector", "Stand", c.X - cr, c.X + cr, c.Z - cr, c.Z + cr)
		local sp = l.Spawn
		local sr = sp.Size / 2
		add("SpawnPoint", "Stand", sp.X - sr, sp.X + sr, sp.Z - sr, sp.Z + sr)

		-- 집 벽: 바깥 바닥 띠(TRIM)부터 벽 안쪽 면 + WallMargin 까지 (집 안 가구는 예전처럼 벽에서 띄워요).
		-- 앞벽은 문 구멍(현관 문 기둥 안쪽 면 사이)만 비워요 → 그 자리는 길(Path)
		local h, zf, zb = l.Half, l.FrontZ, l.BackZ
		local wIn = WALL_T + WALL_MARGIN
		add("Wall", "Wall", -h - TRIM, l.Door.MinX, zf - TRIM, zf + wIn)
		add("Wall", "Wall", l.Door.MaxX, h + TRIM, zf - TRIM, zf + wIn)
		add("Wall", "Wall", -h - TRIM, -h + wIn, zf - TRIM, zb + TRIM)
		add("Wall", "Wall", h - wIn, h + TRIM, zf - TRIM, zb + TRIM)
		add("Wall", "Wall", -h - TRIM, h + TRIM, zb - wIn, zb + TRIM)
		local pIn = PILLAR + WALL_MARGIN
		for _, sx in { -1, 1 } do
			add("Pillar", "Wall", sx * (h - pIn), sx * h, zf, zf + pIn)
			add("Pillar", "Wall", sx * (h - pIn), sx * h, zb - pIn, zb)
			-- 앞 기둥 램프 (+ 숲 덩굴, 우주 별)
			local px = sx * (h - PILLAR / 2)
			add("PillarLamp", "Deco", px - 1, px + 1, zf - 1.2, zf)
		end

		-- 마당: 길 (마당 문 → 현관 문 구멍), 마당 문, 간판, 우편함, 펫 집, 화분, 가로등, 테마 장식
		local y = l.Yard
		local edge = PLOT / 2
		add("Path", "Path", l.Door.MinX, l.Door.MaxX, -edge, l.Inner.MinZ)
		local gateOuter = y.GateHalf + y.GatePost
		add("Gate", "Path", -gateOuter, gateOuter, -edge, -y.Fence + 2.6)
		add("Sign", "Deco", y.Sign.X - 3, y.Sign.X + 3, -edge, y.Sign.Z + 0.45)
		add("Mailbox", "Deco", y.Mail.X - 1, y.Mail.X + 1.1, -edge, y.Mail.Z + 0.7)
		add("PetHouse", "Deco", y.PetHouse.X - 2.1, y.PetHouse.X + 2.1, -edge, y.PetHouse.Z + 1.9)
		for _, sx in { -1, 1 } do
			-- 화분 (+ 캔디 지팡이 사탕): 길 옆부터 화분 바깥까지
			add("Planter", "Deco", sx * l.Door.MaxX, sx * (y.PlanterX + 1.5), y.PlanterZ - 1.5, zf)
			for _, lz in y.LampZs do
				add("Lamp", "Deco", sx * (y.LampX - 0.8), sx * (y.LampX + 0.8), lz - 0.8, lz + 0.8)
			end
		end
		local theme = Config.House.Themes[l.Theme]
		local uses = DECO_YARD[if theme then theme.Deco else "flowers"] or DECO_YARD.flowers
		for _, u in uses do
			local spot = if u.Side then y.Side[u.Side] else y.Spots[u.Spot or 1]
			if spot then
				local cx = spot.X + (u.DX or 0)
				add("YardDeco", "Deco", cx - u.HX, cx + u.HX, spot.Z - u.HZ, spot.Z + u.HZ)
			end
		end
	elseif f == 2 then
		local p = l.Porch
		add("Porch", "Hole", p.MinX - 0.4, p.MaxX + 0.4, l.Inner.MinZ, p.MaxZ + 0.4)
	end
	return rects
end

local blockedCache: { [string]: { Rect } } = {}
local function blockedOf(themeId: any, floor: number): { Rect }
	local l = HouseLayout.Get(themeId)
	local f = math.clamp(math.floor(tonumber(floor) or 1), 1, Config.House.MaxFloors)
	local key = l.Theme .. "|" .. f
	local list = blockedCache[key]
	if not list then
		list = buildBlocked(l, f)
		blockedCache[key] = list
	end
	return list
end

-- 가구를 놓으면 안 되는 사각형들 (플롯 로컬 XZ, 새 표라서 고쳐도 돼요). 모든 층: 받침대(+0.5), 계단 탑 + 계단 앞 자리,
-- 엘리베이터 + 앞자리 (계단 자리는 1층짜리 집에서도 비워 둬요). 1층: 입구 길 / 수금 패드 / 스폰 + ★ 집 벽·기둥 (문 구멍만 열림),
-- 마당 길(마당 문 → 현관), 마당 문, 간판, 우편함, 펫 집, 화분, 가로등, 테마 마당 장식. 2층: 현관 구멍. Kind 는 Rect 설명
function HouseLayout.BlockedRects(themeId: any, floor: number): { Rect }
	local out: { Rect } = {}
	for i, b in blockedOf(themeId, floor) do
		out[i] = { MinX = b.MinX, MaxX = b.MaxX, MinZ = b.MinZ, MaxZ = b.MaxZ, Name = b.Name, Kind = b.Kind }
	end
	return out
end

----------------------------------------------------------------------
-- 가구 놓기 규칙 (하나뿐): 서버 ShopService (CanPlace / Validate / 살 수 있나) 와 클라이언트 DecorateMode (고스트 / 상점 표시)
-- 가 이 함수를 그대로 써요. 그래서 초록 고스트 = 서버 OK 예요.
----------------------------------------------------------------------
HouseLayout.Reasons = {
	Bad = "여기에는 놓을 수 없어요!",
	Wall = "벽 밖이에요!", -- 위층: 집 벽 밖
	Fence = "울타리 밖이에요!", -- 1층: 울타리 밖
	Stand = "받침대/계단 자리예요!",
	Path = "다니는 길은 비워 둬요!",
	HouseWall = "집 벽 자리예요!",
	Deco = "마당 장식이 있는 자리예요!",
	Hole = "바닥이 뚫린 곳이에요!",
	Overlap = "다른 가구랑 겹쳐요!",
}
local REASON_BY_KIND: { [string]: string } = {
	Stand = HouseLayout.Reasons.Stand,
	Path = HouseLayout.Reasons.Path,
	Wall = HouseLayout.Reasons.HouseWall,
	Deco = HouseLayout.Reasons.Deco,
	Hole = HouseLayout.Reasons.Hole,
}

local function footRect(furnId: string, x: number, z: number, r: number): Rect
	local sx, sz = Config.FurnitureFootprint(furnId, r)
	return { MinX = x - sx / 2, MaxX = x + sx / 2, MinZ = z - sz / 2, MaxZ = z + sz / 2 }
end

local function overlapEps(a: Rect, b: Rect): boolean
	return a.MinX < b.MaxX - EPS and b.MinX < a.MaxX - EPS and a.MinZ < b.MaxZ - EPS and b.MinZ < a.MaxZ - EPS
end

local function isRug(furnId: any): boolean
	local def = if type(furnId) == "string" then Config.Furniture[furnId] else nil
	return def ~= nil and def.Category == "Rug"
end

-- 이 가구를 (floor, x, z, r) 에 놓을 수 있나? x, z 는 이미 Decor.Snap 된 값, r 은 0/90/180/270.
-- floors = 집 층 수, others = 다른 놓인 가구 { [fid] = { Id, Floor, X, Z, R } } (nil 이면 빈 집), ignoreFid = 옮기는 자기 자신.
-- 개수 제한(MaxPlaced)·가방 확인은 부르는 쪽에서 해요
function HouseLayout.CheckPlace(themeId: any, floors: number, furnId: string, floor: number, x: number, z: number, r: number, others: { [string]: any }?, ignoreFid: string?): (boolean, string?)
	local R = HouseLayout.Reasons
	if type(furnId) ~= "string" or not Config.Furniture[furnId] then
		return false, R.Bad
	end
	if type(floor) ~= "number" or floor ~= math.floor(floor) or floor < 1 or floor > (tonumber(floors) or 1) or floor > Config.House.MaxFloors then
		return false, R.Bad
	end
	local rect = footRect(furnId, x, z, r)

	-- 땅 끝 (1층 = 울타리, 위층 = 벽) 에서 WallMargin 만큼 안쪽
	local b = HouseLayout.PlaceBounds(themeId, floor)
	local m = WALL_MARGIN
	if rect.MinX < b.MinX + m - EPS or rect.MaxX > b.MaxX - m + EPS or rect.MinZ < b.MinZ + m - EPS or rect.MaxZ > b.MaxZ - m + EPS then
		return false, if floor == 1 then R.Fence else R.Wall
	end

	-- 받침대 / 계단 / 엘리베이터 / 길 / 집 벽 / 마당 장식
	for _, blk in blockedOf(themeId, floor) do
		if overlapEps(rect, blk) then
			return false, REASON_BY_KIND[blk.Kind or "Stand"] or R.Stand
		end
	end

	-- 같은 층 다른 가구 (러그는 위에 겹쳐 놓아도 돼요)
	if others and not isRug(furnId) then
		for fid, f in others do
			if fid ~= ignoreFid and type(f) == "table" and f.Floor == floor and type(f.Id) == "string" and Config.Furniture[f.Id] and not isRug(f.Id) then
				local fx, fz, fr = tonumber(f.X), tonumber(f.Z), tonumber(f.R)
				if fx and fz and overlapEps(rect, footRect(f.Id, fx, fz, fr or 0)) then
					return false, R.Overlap
				end
			end
		end
	end
	return true, nil
end

local function snapHalf(v: number): number
	local s = Config.Decor.Snap
	return math.floor(v / s + 0.5) * s
end

-- 빈 집에 이 가구가 들어갈 자리가 하나라도 있나? (1~2층, 0/90도, Snap 한 땅 끝에서 max(Snap, 1) 씩, 다른 가구 없이)
-- 서버는 안 들어가는 가구는 팔지 않고, 상점은 "🏠 더 큰 집 필요" 를 보여 줘요. 마당이 있어서 거의 다 들어가요. 결과는 기억해요
local fitCache: { [string]: boolean } = {}
function HouseLayout.FitsInHouse(themeId: any, floors: number, furnId: string): boolean
	if type(furnId) ~= "string" or not Config.Furniture[furnId] then
		return false
	end
	local theme = HouseLayout.Get(themeId).Theme
	local floorCount = math.clamp(math.floor(tonumber(floors) or 1), 1, Config.House.MaxFloors)
	local maxFloor = math.min(floorCount, 2) -- 2층부터는 모양이 같아요
	local key = theme .. "|" .. maxFloor .. "|" .. furnId
	local cached = fitCache[key]
	if cached ~= nil then
		return cached
	end
	local step = math.max(Config.Decor.Snap, 1)
	local found = false
	for floor = 1, maxFloor do
		local b = HouseLayout.PlaceBounds(theme, floor)
		local x0, x1 = snapHalf(b.MinX), snapHalf(b.MaxX)
		local z0, z1 = snapHalf(b.MinZ), snapHalf(b.MaxZ)
		for _, r in { 0, 90 } do
			local px = x0
			while px <= x1 and not found do
				local pz = z0
				while pz <= z1 do
					if HouseLayout.CheckPlace(theme, floorCount, furnId, floor, px, pz, r, nil, nil) then
						found = true
						break
					end
					pz += step
				end
				px += step
			end
			if found then
				break
			end
		end
		if found then
			break
		end
	end
	fitCache[key] = found
	return found
end

-- 이 가구가 들어가는 가장 작은 집 테마 id (없으면 nil)
function HouseLayout.SmallestThemeFor(furnId: string, floors: number): string?
	for _, id in Config.House.ThemeOrder do
		if HouseLayout.FitsInHouse(id, floors, furnId) then
			return id
		end
	end
	return nil
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
