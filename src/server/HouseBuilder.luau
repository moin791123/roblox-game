-- 집(플롯) 외형 빌더 v3: 테마 크기(26~52)에 맞는 집, 1~10층, 유리 계단 탑, 층마다 엘리베이터, 받침대, 지붕,
-- 울타리 마당(문·간판·우편함·펫 집), 테마 장식을 지어요. (설계: docs/DESIGN.md "HouseBuilder")
-- 순수 빌드만 해요: 이벤트/루프/yield 없음. PlotService 가 불러서 써요. 모든 파트는 Anchored.
-- 배치 숫자(받침대 자리, 계단, 엘리베이터, 입구 …)는 전부 HouseLayout 이 정해요 (서버·클라이언트 공용).
-- 좌표는 플롯 로컬 (origin = 땅 가운데 y = 0, 입구 = 로컬 -Z, z = -32).
--
-- 펫 타고 지나가기 규칙: 마당 문·현관 문 폭 ≥ 10, 길 위는 y 14 까지 아무것도 없음 (간판은 옆 기둥에),
-- 2층 바닥은 현관 위가 뚫려 있고, 1층짜리 집은 처마가 14.5 위. 층 사이 천장 11, 계단은 칸 높이 1.2 + 투명 경사로,
-- 계단 위 머리 공간 ≥ 11 (반층씩 꺾이는 계단이라 위층 계단이 정확히 12 위에 있어요).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout)

local HouseBuilder = {}

export type Handles = {
	House: Model,
	Pedestals: { [number]: BasePart }, -- 슬롯 번호 → 받침대 윗판 (지어진 층만)
	SpawnPoint: BasePart,
	Collector: BasePart,
	Elevators: { [number]: BasePart }, -- 층 → 엘리베이터 문 (이름 "Elevator", 속성 Floor, 프롬프트 있음)
	Bounds: { MinY: number, MaxY: number }, -- 월드 y 범위 (바닥 밑 ~ 지붕 꼭대기)
}

----------------------------------------------------------------------
-- 상수
----------------------------------------------------------------------
local FLOOR1_TOP = HouseLayout.FLOOR1_TOP -- 0.2
local RAIL_H = HouseLayout.RAIL_H -- 3
local SLAB_T = HouseLayout.SLAB_T -- 1
local PED_BASE_H = HouseLayout.PED_BASE_H
local PED_TOP_H = HouseLayout.PED_TOP_H
local SLOTS_PER_FLOOR = Config.Plot.SlotsPerFloor
local FENCE = HouseLayout.FENCE -- 울타리 가운데 선 (±31.6). 마당 숫자는 HouseLayout 이 정해요 (가구 자리와 같이)
local FENCE_T = HouseLayout.FENCE_T
local FENCE_H = 2.2
local GATE_HALF = HouseLayout.GATE_HALF -- 마당 문 반 폭 (기둥 안쪽 면 사이 12)
local PILLAR = HouseLayout.PILLAR -- 모서리 기둥
local YARD_Y = HouseLayout.YARD_Y -- 마당 바닥 윗면 (마당 가구가 여기 서요)
local CAP_TOP = FLOOR1_TOP + RAIL_H + 0.5 -- 1층 벽 위 장식띠 윗면 (작은 장식을 올려 두는 자리)
local DOOR_POST_TOP = 10.2 -- 현관 기둥 (2층 바닥 아래에서 끝나요)
local ELEV_FRAME_H = 9
local ELEV_DOOR_W = 4
local ELEV_DOOR_H = 7.4
local RAMP_T = 0.4 -- 투명 경사로 두께

----------------------------------------------------------------------
-- 색/재질
----------------------------------------------------------------------
local WHITE = Color3.fromRGB(255, 252, 248)
local LOCKED_GREY = Color3.fromRGB(165, 165, 172)
local LOCKED_GREY_DARK = Color3.fromRGB(130, 130, 138)
local GOLD = Color3.fromRGB(255, 205, 60)
local GOLD_TEXT = Color3.fromRGB(255, 235, 120)
local LEAF = Color3.fromRGB(95, 185, 90)
local WOOD = Color3.fromRGB(150, 105, 70)
local DARK = Color3.fromRGB(70, 50, 75)
local LAMP = Color3.fromRGB(255, 222, 160)
local RED = Color3.fromRGB(255, 90, 100)
local ROYAL_RED = Color3.fromRGB(200, 35, 60)
local SKY = Color3.fromRGB(150, 210, 255)
local GLASS = Color3.fromRGB(205, 235, 255)

local FLOWER_COLORS = {
	Color3.fromRGB(255, 150, 190),
	Color3.fromRGB(255, 230, 110),
	Color3.fromRGB(200, 160, 255),
	Color3.fromRGB(130, 200, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 180, 140),
}
local RAINBOW_COLORS = {
	Color3.fromRGB(255, 140, 150),
	Color3.fromRGB(255, 190, 120),
	Color3.fromRGB(255, 235, 130),
	Color3.fromRGB(150, 225, 150),
	Color3.fromRGB(140, 190, 255),
	Color3.fromRGB(200, 160, 255),
}
local NEBULA_COLORS = {
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 120, 210),
	Color3.fromRGB(110, 220, 255),
}

type Theme = { Name: string, Price: number, Size: number, Floor: Color3, Wall: Color3, Roof: Color3, Accent: Color3, Deco: string }
local THEMES = (Config.House.Themes :: any) :: { [string]: Theme }

-- 모르는 테마는 Basic
local function themeOf(themeId: any): (Theme, string)
	if type(themeId) == "string" and THEMES[themeId] then
		return THEMES[themeId], themeId
	end
	return THEMES.Basic, "Basic"
end

type Mats = { Floor: Enum.Material, Wall: Enum.Material, Roof: Enum.Material }
local MATERIALS: { [string]: Mats } = {
	flowers = { Floor = Enum.Material.Grass, Wall = Enum.Material.SmoothPlastic, Roof = Enum.Material.SmoothPlastic },
	candy = { Floor = Enum.Material.SmoothPlastic, Wall = Enum.Material.SmoothPlastic, Roof = Enum.Material.SmoothPlastic },
	mushrooms = { Floor = Enum.Material.Grass, Wall = Enum.Material.Wood, Roof = Enum.Material.WoodPlanks },
	shells = { Floor = Enum.Material.Sand, Wall = Enum.Material.SmoothPlastic, Roof = Enum.Material.SmoothPlastic },
	stars = { Floor = Enum.Material.Metal, Wall = Enum.Material.Metal, Roof = Enum.Material.SmoothPlastic },
	rainbow = { Floor = Enum.Material.SmoothPlastic, Wall = Enum.Material.SmoothPlastic, Roof = Enum.Material.SmoothPlastic },
	royal = { Floor = Enum.Material.Marble, Wall = Enum.Material.SmoothPlastic, Roof = Enum.Material.SmoothPlastic },
	galaxy = { Floor = Enum.Material.SmoothPlastic, Wall = Enum.Material.SmoothPlastic, Roof = Enum.Material.SmoothPlastic },
}

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end

local function darker(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end

-- 마당 바닥/길 모양 (테마 장식 종류별)
type YardLook = { Ground: Color3?, GroundMat: Enum.Material, Path: Color3? }
local YARD_LOOK: { [string]: YardLook } = {
	flowers = { Ground = Color3.fromRGB(140, 210, 115), GroundMat = Enum.Material.Grass, Path = Color3.fromRGB(250, 235, 200) },
	candy = { Ground = Color3.fromRGB(255, 220, 235), GroundMat = Enum.Material.SmoothPlastic, Path = Color3.fromRGB(255, 255, 255) },
	mushrooms = { Ground = Color3.fromRGB(115, 180, 95), GroundMat = Enum.Material.Grass, Path = Color3.fromRGB(205, 165, 120) },
	shells = { Ground = Color3.fromRGB(245, 228, 175), GroundMat = Enum.Material.Sand, Path = Color3.fromRGB(255, 245, 225) },
	stars = { Ground = Color3.fromRGB(60, 52, 95), GroundMat = Enum.Material.SmoothPlastic, Path = Color3.fromRGB(140, 130, 190) },
	rainbow = { Ground = Color3.fromRGB(235, 245, 255), GroundMat = Enum.Material.SmoothPlastic, Path = Color3.fromRGB(255, 240, 200) },
	royal = { Ground = Color3.fromRGB(120, 195, 105), GroundMat = Enum.Material.Grass, Path = ROYAL_RED },
	galaxy = { Ground = Color3.fromRGB(35, 28, 70), GroundMat = Enum.Material.SmoothPlastic, Path = Color3.fromRGB(90, 70, 170) },
}

----------------------------------------------------------------------
-- 파트 도우미 (모두 Anchored. Local = 플롯 로컬 CFrame, 부모 기본값 = House)
----------------------------------------------------------------------
type Ctx = {
	origin: CFrame,
	house: Model,
	theme: Theme,
	deco: string,
	mats: Mats,
	floors: number,
	count: number,
	L: HouseLayout.Layout,
	ownerId: number,
	eaveY: number, -- 처마 (지붕 밑) 높이
	roofBase: number, -- 지붕 쐐기 밑면
	roofH: number, -- 지붕 높이
	roofD: number, -- 지붕 앞뒤 경사 깊이 (용마루 → 처마)
	yardSpots: { Vector3 }, -- 앞마당 빈 자리 (y = 0)
	sideSpots: { Vector3 }, -- 집 양옆 마당
	capSpots: { { pos: Vector3, alongX: boolean } }, -- 1층 벽 위 (y = CAP_TOP)
}

local function finish(ctx: Ctx, p: BasePart, props: { [string]: any }): BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "Local" and k ~= "Shape" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	if props.Local then
		p.CFrame = ctx.origin * props.Local
	end
	p.Parent = props.Parent or ctx.house
	ctx.count += 1
	return p
end

local function part(ctx: Ctx, props: { [string]: any }): Part
	local p = Instance.new("Part")
	if props.Shape then
		p.Shape = props.Shape -- 크기보다 먼저 (Ball 은 Size 를 바꿔요)
	end
	finish(ctx, p, props)
	return p
end

-- 장식: 안 부딪히고 안 밟혀요
local function deco(ctx: Ctx, props: { [string]: any }): Part
	props.CanCollide = false
	props.CanTouch = false
	return part(ctx, props)
end

local function wedge(ctx: Ctx, props: { [string]: any }): WedgePart
	local p = Instance.new("WedgePart")
	finish(ctx, p, props)
	return p
end

-- 축 정렬 상자 (플롯 로컬 최소/최대 좌표로)
local function box(ctx: Ctx, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, props: { [string]: any }?): Part
	local pr: { [string]: any } = props or {}
	pr.Name = name
	pr.Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	pr.Local = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	return part(ctx, pr)
end

-- 세로 원기둥 (바닥 중심 x,z / 바닥 높이 bottomY / 높이 h / 지름 d)
local function vcyl(ctx: Ctx, x: number, z: number, bottomY: number, h: number, d: number, props: { [string]: any }): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(h, d, d)
	props.Local = CFrame.new(x, bottomY + h / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
	return part(ctx, props)
end

-- 가로 원기둥 (cf 의 X 축 방향으로 길이 len)
local function hcyl(ctx: Ctx, cf: CFrame, len: number, d: number, props: { [string]: any }): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(len, d, d)
	props.Local = cf
	return deco(ctx, props)
end

-- 공 (지름 d)
local function ball(ctx: Ctx, pos: Vector3, d: number, props: { [string]: any }): Part
	props.Shape = Enum.PartType.Ball
	props.Size = Vector3.new(d, d, d)
	props.Local = CFrame.new(pos)
	return deco(ctx, props)
end

-- 타원체 (SpecialMesh 구)
local function blob(ctx: Ctx, pos: Vector3, size: Vector3, props: { [string]: any }): Part
	props.Size = size
	props.Local = CFrame.new(pos)
	local p = deco(ctx, props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function addLight(p: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = p
end

local function makeBillboard(adornee: BasePart, offsetY: number, w: number, h: number, maxDist: number, labelName: string): (BillboardGui, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(w, h)
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = maxDist
	bb.LightInfluence = 0
	bb.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Name = labelName
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(60, 40, 70)
	label.Text = ""
	label.Parent = bb
	bb.Parent = adornee
	return bb, label
end

-- 파트 한 면에 글자 (SurfaceGui)
local function surfaceText(p: BasePart, face: Enum.NormalId, text: string, pos: UDim2, size: UDim2): TextLabel
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = pos
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = Color3.fromRGB(60, 40, 70)
	label.Text = text
	label.Parent = sg
	sg.Parent = p
	return label
end

-- 지붕 윗면 높이 (박공지붕: 용마루는 X 방향, 집 가운데 z)
local function roofY(ctx: Ctx, z: number): number
	local f = 1 - math.abs(z - ctx.L.CenterZ) / ctx.roofD
	return ctx.roofBase + ctx.roofH * math.clamp(f, 0, 1)
end

----------------------------------------------------------------------
-- 1층 바닥 / 벽 / 기둥 / 현관
----------------------------------------------------------------------
local function buildGroundFloor(ctx: Ctx)
	local L, theme = ctx.L, ctx.theme
	local floor = box(ctx, "Floor", -L.Half, L.Half, FLOOR1_TOP - SLAB_T, FLOOR1_TOP, L.FrontZ, L.BackZ, {
		Color = theme.Floor,
		Material = ctx.mats.Floor,
	})
	box(ctx, "FloorTrim", -L.Half - 0.7, L.Half + 0.7, -0.9, 0.14, L.FrontZ - 0.7, L.BackZ + 0.7, { Color = theme.Accent })
	ctx.house.PrimaryPart = floor
end

-- 벽 위 장식띠 색 (무지개: 칸마다 다른 색, 은하: 네온 성운 색)
local function capLook(ctx: Ctx, i: number): (Color3, Enum.Material)
	if ctx.deco == "rainbow" then
		return RAINBOW_COLORS[(i - 1) % #RAINBOW_COLORS + 1], Enum.Material.SmoothPlastic
	elseif ctx.deco == "galaxy" then
		return NEBULA_COLORS[(i - 1) % #NEBULA_COLORS + 1], Enum.Material.Neon
	end
	return ctx.theme.Accent, Enum.Material.SmoothPlastic
end

-- 한 층의 바깥 벽(1층) / 난간(위층). 모서리는 기둥이 덮어요. 계단 탑 자리(뒤 오른쪽)는 유리벽이 대신해요
local function buildPerimeter(ctx: Ctx, f: number)
	local L, theme = ctx.L, ctx.theme
	local st = L.Stair
	local y = HouseLayout.FloorY(f)
	local x0, x1 = -L.Half + PILLAR, L.Half - PILLAR
	local z0, z1 = L.FrontZ + PILLAR, L.BackZ - PILLAR
	local hasTower = ctx.floors >= 2
	local backEnd = if hasTower then st.GlassX else x1
	local rightEnd = if hasTower then st.MinZ else z1
	local gap = if f == 1 then L.Door.MaxX elseif f == 2 then L.Porch.MaxX else 0

	-- { x0, x1, z0, z1, 장식띠가 X 방향인지 }
	local segs: { { number | boolean } } = {}
	local zfA, zfB = L.FrontZ, L.FrontZ + 1
	if gap > 0 then
		table.insert(segs, { x0, -gap, zfA, zfB, true })
		table.insert(segs, { gap, x1, zfA, zfB, true })
	else
		table.insert(segs, { x0, x1, zfA, zfB, true })
	end
	table.insert(segs, { -L.Half, -L.Half + 1, z0, z1, false }) -- 왼쪽
	table.insert(segs, { x0, backEnd, L.BackZ - 1, L.BackZ, true }) -- 뒤
	table.insert(segs, { L.Half - 1, L.Half, z0, rightEnd, false }) -- 오른쪽

	for i, s in segs do
		local sx0, sx1, sz0, sz1 = s[1] :: number, s[2] :: number, s[3] :: number, s[4] :: number
		if sx1 - sx0 > 0.05 and sz1 - sz0 > 0.05 then
			box(ctx, if f == 1 then "Wall" else "Rail", sx0, sx1, y, y + RAIL_H, sz0, sz1, {
				Color = if f == 1 then theme.Wall else lighter(theme.Wall, 0.08),
				Material = ctx.mats.Wall,
			})
			local capColor, capMat = capLook(ctx, i + f)
			local ax = s[5] == true
			box(ctx, "WallCap", if ax then sx0 else sx0 - 0.2, if ax then sx1 else sx1 + 0.2, y + RAIL_H, y + RAIL_H + 0.5, if ax then sz0 - 0.2 else sz0, if ax then sz1 + 0.2 else sz1, {
				Color = capColor,
				Material = capMat,
			})
		end
	end

	-- 2층: 현관 구멍 둘레 난간 (왼쪽 / 오른쪽 / 안쪽)
	if f == 2 then
		local p = L.Porch
		local railColor = lighter(theme.Accent, 0.15)
		box(ctx, "PorchRail", p.MinX - 0.4, p.MinX, y, y + RAIL_H, p.MinZ, p.MaxZ + 0.4, { Color = railColor })
		box(ctx, "PorchRail", p.MaxX, p.MaxX + 0.4, y, y + RAIL_H, p.MinZ, p.MaxZ + 0.4, { Color = railColor })
		box(ctx, "PorchRail", p.MinX, p.MaxX, y, y + RAIL_H, p.MaxZ, p.MaxZ + 0.4, { Color = railColor })
	end
end

-- 위층 바닥 (계단 탑 자리는 비워요. 2층은 현관 위도 비워요)
local function buildSlab(ctx: Ctx, f: number)
	local L = ctx.L
	local st = L.Stair
	local y = HouseLayout.FloorY(f)
	local props = function(): { [string]: any }
		return { Color = lighter(ctx.theme.Floor, 0.1), Material = ctx.mats.Floor }
	end
	if f == 2 then
		local p = L.Porch
		box(ctx, "Slab", -L.Half, L.Half, y - SLAB_T, y, p.MaxZ, st.MinZ, props())
		box(ctx, "Slab", -L.Half, p.MinX, y - SLAB_T, y, L.FrontZ, p.MaxZ, props())
		box(ctx, "Slab", p.MaxX, L.Half, y - SLAB_T, y, L.FrontZ, p.MaxZ, props())
	else
		box(ctx, "Slab", -L.Half, L.Half, y - SLAB_T, y, L.FrontZ, st.MinZ, props())
	end
	box(ctx, "Slab", -L.Half, st.GlassX, y - SLAB_T, y, st.MinZ, L.BackZ, props())
end

-- 모서리 기둥 4개 (1층 바닥 → 처마) + 앞 기둥 램프 2개
local function buildPillars(ctx: Ctx)
	local L, theme = ctx.L, ctx.theme
	local top = ctx.eaveY - 0.3
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local sx, sz = c[1], c[2]
		local px = sx * (L.Half - PILLAR / 2)
		local pz = if sz < 0 then L.FrontZ + PILLAR / 2 else L.BackZ - PILLAR / 2
		box(ctx, "Pillar", px - PILLAR / 2, px + PILLAR / 2, FLOOR1_TOP, top, pz - PILLAR / 2, pz + PILLAR / 2, {
			Color = lighter(theme.Wall, 0.15),
			Material = ctx.mats.Wall,
		})
		if sz < 0 then
			local bulb = ball(ctx, Vector3.new(px, 6.6, L.FrontZ - 0.55), 1.1, {
				Name = "Lamp",
				Color = if ctx.deco == "galaxy" or ctx.deco == "stars" then theme.Accent else LAMP,
				Material = Enum.Material.Neon,
				CastShadow = false,
			})
			addLight(bulb, LAMP, 16, 0.9)
		end
	end
end

-- 현관 문 기둥 (문 양옆, 위는 비워요: 가로 들보 없음)
local function buildDoor(ctx: Ctx)
	local L, theme = ctx.L, ctx.theme
	local d = L.Door
	for _, sx in { -1, 1 } do
		local inner = if sx < 0 then d.MinX else d.MaxX
		local outer = inner + sx * 0.5
		box(ctx, "DoorPost", math.min(inner, outer), math.max(inner, outer), FLOOR1_TOP, DOOR_POST_TOP, L.FrontZ - 0.15, L.FrontZ + 1.15, {
			Color = theme.Accent,
		})
		ball(ctx, Vector3.new((inner + outer) / 2, DOOR_POST_TOP + 0.4, L.FrontZ + 0.5), 0.9, { Name = "DoorPostBall", Color = lighter(theme.Accent, 0.3) })
	end
end

----------------------------------------------------------------------
-- 계단 탑 (뒤 오른쪽 유리 탑, 반층씩 꺾이는 계단)
----------------------------------------------------------------------
-- 보이지 않는 경사로: 계단 코(앞 모서리)를 잇는 선이 윗면. (za, ya) → (zb, yb), 폭 x0..x1
local function ramp(ctx: Ctx, x0: number, x1: number, za: number, ya: number, zb: number, yb: number)
	local cx = (x0 + x1) / 2
	local pa = Vector3.new(cx, ya, za)
	local pb = Vector3.new(cx, yb, zb)
	local d = pb - pa
	local dir = d.Unit
	local n = Vector3.xAxis:Cross(dir)
	if n.Y < 0 then
		n = -n
	end
	local center = (pa + pb) / 2 - n * (RAMP_T / 2)
	part(ctx, {
		Name = "StairRamp",
		Size = Vector3.new(x1 - x0, RAMP_T, d.Magnitude),
		Local = CFrame.fromMatrix(center, Vector3.xAxis, n),
		Transparency = 1,
		CastShadow = false,
		CanTouch = false,
	})
end

-- f 층 → f+1 층 계단 한 벌: 바깥 줄 반층(+Z) → 반층 참 → 안쪽 줄 반층(-Z) → 위층 계단 앞 자리
local function buildFlight(ctx: Ctx, f: number)
	local st = ctx.L.Stair
	local theme = ctx.theme
	local y = HouseLayout.FloorY(f)
	local t = st.TreadT
	local colA, colB = lighter(theme.Wall, 0.1), lighter(theme.Accent, 0.35)
	for k = 1, st.Treads do
		local top = y + st.Rise * k
		box(ctx, "Step", st.UpMinX, st.UpMaxX, top - t, top, st.MinZ + st.Run * (k - 1), st.MinZ + st.Run * k, {
			Color = if k % 2 == 0 then colB else colA,
			Material = ctx.mats.Wall,
		})
	end
	local mid = y + st.HalfRise
	box(ctx, "StairLanding", st.MinX, st.MaxX, mid - t, mid, st.RunEndZ, st.MaxZ, {
		Color = lighter(theme.Floor, 0.1),
		Material = ctx.mats.Floor,
	})
	for k = 1, st.Treads do
		local top = mid + st.Rise * k
		box(ctx, "Step", st.DownMinX, st.DownMaxX, top - t, top, st.RunEndZ - st.Run * k, st.RunEndZ - st.Run * (k - 1), {
			Color = if k % 2 == 0 then colA else colB,
			Material = ctx.mats.Wall,
		})
	end
	-- 부드럽게 걸어 올라가는 투명 경사로 2개 (계단 코를 지나요)
	ramp(ctx, st.UpMinX, st.UpMaxX, st.MinZ - st.Run, y, st.RunEndZ, mid)
	ramp(ctx, st.DownMinX, st.DownMaxX, st.RunEndZ + st.Run, mid, st.MinZ, mid + st.HalfRise)
end

local function buildTower(ctx: Ctx)
	local L, theme = ctx.L, ctx.theme
	local st = L.Stair
	if ctx.floors < 2 then
		-- 1층짜리 집: 계단 자리 표시만 (가구도 못 놓는 자리라서 알려 줘요)
		local mat = box(ctx, "StairSpot", st.GlassX, st.MaxX, FLOOR1_TOP, FLOOR1_TOP + 0.06, st.LandingMinZ, st.MaxZ, {
			Color = lighter(theme.Accent, 0.55),
			CanCollide = false,
			CanTouch = false,
			CastShadow = false,
		})
		surfaceText(mat, Enum.NormalId.Top, "🪜 계단 자리\n2층을 올리면 생겨요", UDim2.fromScale(0.05, 0.3), UDim2.fromScale(0.9, 0.4))
		return
	end
	local topF = HouseLayout.FloorY(ctx.floors)
	local glassTop = topF + RAIL_H + 0.5
	local glassProps = function(): { [string]: any }
		return { Color = lighter(theme.Accent, 0.65), Material = Enum.Material.Glass, Transparency = 0.6, CastShadow = false }
	end
	-- 유리벽: 집 안쪽 / 바깥 오른쪽 / 뒤 (모든 층을 한 장으로)
	box(ctx, "StairGlass", st.GlassX, st.MinX, FLOOR1_TOP, glassTop, st.MinZ, L.BackZ - 0.7, glassProps())
	box(ctx, "StairGlass", L.Half - 0.7, L.Half - 0.3, FLOOR1_TOP, glassTop, st.MinZ, L.BackZ - PILLAR, glassProps())
	box(ctx, "StairGlass", st.GlassX, L.Half - PILLAR, FLOOR1_TOP, glassTop, L.BackZ - 0.7, L.BackZ - 0.3, glassProps())
	-- 올라가는 줄 / 내려오는 줄 사이 칸막이
	box(ctx, "StairDivider", st.DownMaxX, st.UpMinX, FLOOR1_TOP, glassTop, st.MinZ, st.RunEndZ, {
		Color = lighter(theme.Wall, 0.1),
		Material = ctx.mats.Wall,
	})
	-- 1층: 안쪽 줄 아래(머리 닿는 곳)는 막아요 / 꼭대기 층: 바깥 줄은 아래로 뚫려 있어서 막아요
	local railColor = lighter(theme.Accent, 0.15)
	box(ctx, "StairGuard", st.DownMinX, st.DownMaxX, FLOOR1_TOP, FLOOR1_TOP + RAIL_H, st.MinZ - 0.4, st.MinZ, { Color = railColor })
	box(ctx, "StairGuard", st.UpMinX, st.UpMaxX, topF, topF + RAIL_H, st.MinZ - 0.4, st.MinZ, { Color = railColor })
	for f = 1, ctx.floors - 1 do
		buildFlight(ctx, f)
	end
end

----------------------------------------------------------------------
-- 엘리베이터 (층마다: 문틀 + 문 "Elevator" + 프롬프트)
----------------------------------------------------------------------
local function buildElevator(ctx: Ctx, f: number): BasePart
	local L, theme = ctx.L, ctx.theme
	local e = L.Elevator
	local y = HouseLayout.FloorY(f)
	local frameBack = e.PanelMinZ
	local frameFront = e.PanelMaxZ - 0.3
	local frame = box(ctx, "ElevatorFrame", e.X - e.W / 2, e.X + e.W / 2, y, y + ELEV_FRAME_H, frameBack, frameFront, {
		Color = theme.Accent,
	})
	surfaceText(frame, Enum.NormalId.Back, "🛗 " .. f .. "층", UDim2.fromScale(0.05, 0.84), UDim2.fromScale(0.9, 0.15))
	local door = box(ctx, "Elevator", e.X - ELEV_DOOR_W / 2, e.X + ELEV_DOOR_W / 2, y + 0.05, y + ELEV_DOOR_H, frameFront, e.PanelMaxZ, {
		Color = if ctx.deco == "galaxy" then Color3.fromRGB(150, 120, 255) else GLASS,
		Material = Enum.Material.Glass,
		Transparency = 0.1,
		Reflectance = 0.15,
	})
	door:SetAttribute("Floor", f)
	door:SetAttribute("PromptAction", "Elevator")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "🛗 층 이동"
	prompt.ObjectText = f .. "층 엘리베이터"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("PromptKind", "Owner")
	prompt:SetAttribute("OwnerUserId", ctx.ownerId)
	prompt:SetAttribute("PromptAction", "Elevator")
	prompt:SetAttribute("Floor", f)
	prompt.Parent = door
	return door
end

----------------------------------------------------------------------
-- 지붕 (박공: 앞뒤 쐐기 2개 + 처마띠 + 용마루 + 굴뚝)
----------------------------------------------------------------------
local function buildRoof(ctx: Ctx)
	local L, theme = ctx.L, ctx.theme
	local w = L.Size + 2
	box(ctx, "Eave", -L.Half - 1.2, L.Half + 1.2, ctx.eaveY - 0.3, ctx.eaveY + 0.3, L.FrontZ - 1.2, L.BackZ + 1.2, {
		Color = if ctx.deco == "galaxy" then theme.Wall else theme.Accent,
	})
	for _, sz in { -1, 1 } do
		wedge(ctx, {
			Name = "Roof",
			Size = Vector3.new(w, ctx.roofH, ctx.roofD),
			Local = CFrame.new(0, ctx.roofBase + ctx.roofH / 2, L.CenterZ + sz * ctx.roofD / 2) * CFrame.Angles(0, if sz < 0 then 0 else math.pi, 0),
			Color = theme.Roof,
			Material = ctx.mats.Roof,
		})
	end
	local ridgeY = ctx.roofBase + ctx.roofH
	box(ctx, "Ridge", -w / 2 - 0.3, w / 2 + 0.3, ridgeY - 0.35, ridgeY + 0.45, L.CenterZ - 0.8, L.CenterZ + 0.8, { Color = theme.Accent })
	if ctx.deco ~= "stars" and ctx.deco ~= "galaxy" then
		local cx, cz = L.Size * 0.22, L.CenterZ + ctx.roofD * 0.45
		local top = roofY(ctx, cz) + 3
		box(ctx, "Chimney", cx - 1.1, cx + 1.1, top - 5, top, cz - 1.1, cz + 1.1, { Color = lighter(theme.Wall, 0.1), Material = ctx.mats.Wall })
		box(ctx, "ChimneyCap", cx - 1.4, cx + 1.4, top, top + 0.6, cz - 1.4, cz + 1.4, { Color = darker(theme.Roof, 0.15) })
	end
end

-- 지붕 경사면 위 줄무늬 (캔디/무지개). 앞뒤 경사면에 3줄씩
local function roofStripes(ctx: Ctx, colors: { Color3 })
	local L = ctx.L
	local len = math.sqrt(ctx.roofD ^ 2 + ctx.roofH ^ 2)
	local i = 0
	local xs = { -L.Size * 0.28, 0, L.Size * 0.28 }
	for _, sz in { -1, 1 } do
		local n = Vector3.new(0, ctx.roofD, sz * ctx.roofH) / len -- 경사면 바깥 법선
		for _, x in xs do
			i += 1
			local mid = Vector3.new(x, ctx.roofBase + ctx.roofH / 2, L.CenterZ + sz * ctx.roofD / 2)
			deco(ctx, {
				Name = "RoofStripe",
				Size = Vector3.new(1.4, 0.2, len - 1),
				Local = CFrame.fromMatrix(mid + n * 0.12, Vector3.xAxis, n),
				Color = colors[(i - 1) % #colors + 1],
				CastShadow = false,
			})
		end
	end
end

----------------------------------------------------------------------
-- 마당: 바닥, 길, 울타리 + 마당 문, 이름 간판(옆 기둥), 우편함, 펫 집, 화분, 가로등, 환영 매트
----------------------------------------------------------------------
local function lampPost(ctx: Ctx, x: number, z: number)
	vcyl(ctx, x, z, 0, 5, 0.45, { Name = "LampPost", Color = DARK, CanCollide = true })
	local bulb = ball(ctx, Vector3.new(x, 5.5, z), 1.2, { Name = "Lamp", Color = LAMP, Material = Enum.Material.Neon, CastShadow = false })
	addLight(bulb, LAMP, 18, 0.9)
end

-- 왕관 (금 띠 + 뾰족 공 3개)
local function crown(ctx: Ctx, pos: Vector3, s: number)
	vcyl(ctx, pos.X, pos.Z, pos.Y, 0.6 * s, 1.5 * s, { Name = "Crown", Color = GOLD, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanTouch = false, Reflectance = 0.2 })
	for k = 0, 2 do
		local a = k * (math.pi * 2 / 3)
		ball(ctx, pos + Vector3.new(math.cos(a) * 0.5 * s, 0.85 * s, math.sin(a) * 0.5 * s), 0.45 * s, {
			Name = "CrownGem",
			Color = if k == 0 then RED elseif k == 1 then SKY else GOLD,
		})
	end
end

local function buildYard(ctx: Ctx)
	local L, theme = ctx.L, ctx.theme
	local look = YARD_LOOK[ctx.deco] or YARD_LOOK.flowers
	local edge = FENCE + FENCE_T / 2

	-- 마당 바닥 + 길 (마당 문 → 현관)
	box(ctx, "Yard", -edge, edge, YARD_Y - 0.2, YARD_Y, -edge, edge, {
		Color = look.Ground or darker(theme.Floor, 0.1),
		Material = look.GroundMat,
	})
	box(ctx, "Path", L.Door.MinX, L.Door.MaxX, -0.1, 0.1, -edge, L.FrontZ, {
		Color = look.Path or WHITE,
		Material = if ctx.deco == "royal" then Enum.Material.Fabric else Enum.Material.SmoothPlastic,
	})

	-- 울타리 (낮아서 밟고 넘을 수도 있어요). 앞은 가운데 마당 문
	local fenceColor = if ctx.deco == "galaxy" or ctx.deco == "stars" then lighter(theme.Wall, 0.1) else WHITE
	local capColor = capLook(ctx, 1)
	local fi = FENCE - FENCE_T / 2
	local fo = FENCE + FENCE_T / 2
	local Y = L.Yard
	local gx = GATE_HALF + Y.GatePost
	local segs = {
		{ -fo, -fi, -fo, fo, false }, -- 왼쪽
		{ fi, fo, -fo, fo, false }, -- 오른쪽
		{ -fi, fi, fi, fo, true }, -- 뒤
		{ -fi, -gx, -fo, -fi, true }, -- 앞 왼쪽
		{ gx, fi, -fo, -fi, true }, -- 앞 오른쪽
	}
	for _, s in segs do
		local sx0, sx1, sz0, sz1 = s[1] :: number, s[2] :: number, s[3] :: number, s[4] :: number
		box(ctx, "Fence", sx0, sx1, 0, FENCE_H, sz0, sz1, { Color = fenceColor })
		-- 장식띠: 옆 울타리 띠가 모서리를 덮고, 앞뒤 띠는 그 안쪽에서 끝나요 (겹치면 깜빡여요)
		if s[5] == true then
			local cx0 = math.max(sx0, -fi + 0.15)
			local cx1 = math.min(sx1, fi - 0.15)
			box(ctx, "FenceCap", cx0, cx1, FENCE_H, FENCE_H + 0.3, sz0 - 0.15, sz1 + 0.15, { Color = capColor })
		else
			box(ctx, "FenceCap", sx0 - 0.15, sx1 + 0.15, FENCE_H, FENCE_H + 0.3, sz0, sz1, { Color = capColor })
		end
	end
	-- 마당 문 기둥 (위에 가로대 없음)
	for _, sx in { -1, 1 } do
		local cx = sx * (GATE_HALF + 0.6)
		box(ctx, "GatePost", cx - 0.6, cx + 0.6, 0, 5, -fo - 0.1, -fi + 0.1, { Color = lighter(theme.Wall, 0.15), Material = ctx.mats.Wall })
		if ctx.deco == "royal" then
			crown(ctx, Vector3.new(cx, 5, -FENCE), 1)
		else
			ball(ctx, Vector3.new(cx, 5.6, -FENCE), 1.4, { Name = "GateBall", Color = theme.Accent })
		end
	end

	-- 이름 간판: 마당 문 왼쪽 옆 기둥 (길 위가 아니에요). BillboardGui > TextLabel "OwnerLabel" 은 PlotService 가 채워요
	local signX, signZ = Y.Sign.X, Y.Sign.Z
	box(ctx, "SignPost", signX - 0.25, signX + 0.25, 0, 3.4, signZ - 0.25, signZ + 0.25, { Color = WOOD, Material = Enum.Material.Wood })
	local sign = box(ctx, "Sign", signX - 2.8, signX + 2.8, 3.2, 6.6, signZ - 0.35, signZ + 0.15, { Color = theme.Accent })
	local bb, label = makeBillboard(sign, 0.6, 13, 2.4, 70, "OwnerLabel")
	bb.AlwaysOnTop = true
	label.TextStrokeTransparency = 0.1
	label.Text = "빈 집"

	-- 우편함 (마당 문 오른쪽)
	local mx, mz = Y.Mail.X, Y.Mail.Z
	box(ctx, "MailPost", mx - 0.2, mx + 0.2, 0, 2.6, mz - 0.2, mz + 0.2, { Color = WOOD, Material = Enum.Material.Wood })
	box(ctx, "Mailbox", mx - 0.75, mx + 0.75, 2.6, 3.7, mz - 0.5, mz + 0.5, { Color = theme.Accent })
	deco(ctx, { Name = "MailFlag", Size = Vector3.new(0.12, 0.9, 0.35), Local = CFrame.new(mx + 0.8, 3.5, mz), Color = RED })

	-- 펫 집 (앞마당 왼쪽)
	local px, pz = Y.PetHouse.X, Y.PetHouse.Z
	box(ctx, "PetHouse", px - 1.7, px + 1.7, 0, 2.6, pz - 1.5, pz + 1.5, { Color = theme.Wall, Material = ctx.mats.Wall })
	deco(ctx, { Name = "PetHouseDoor", Size = Vector3.new(1.3, 1.6, 0.2), Local = CFrame.new(px, 0.8, pz - 1.55), Color = DARK })
	for _, sz in { -1, 1 } do
		wedge(ctx, {
			Name = "PetHouseRoof",
			Size = Vector3.new(3.8, 1.5, 1.7),
			Local = CFrame.new(px, 2.6 + 0.75, pz + sz * 0.85) * CFrame.Angles(0, if sz < 0 then 0 else math.pi, 0),
			Color = theme.Roof,
			Material = ctx.mats.Roof,
		})
	end

	-- 화분 2개 (현관 양옆 바깥)
	for i, sx in { -1, 1 } do
		local x, z = sx * Y.PlanterX, Y.PlanterZ
		box(ctx, "Planter", x - 1.3, x + 1.3, 0, 1.2, z - 1.3, z + 1.3, { Color = darker(theme.Accent, 0.15) })
		blob(ctx, Vector3.new(x, 1.45, z), Vector3.new(2.4, 1.1, 2.4), { Name = "PlanterLeaves", Color = LEAF })
		local offsets = { Vector3.new(-0.6, 0, 0.3), Vector3.new(0.55, 0.1, 0.45), Vector3.new(0.05, 0.25, -0.55) }
		for k, off in offsets do
			ball(ctx, Vector3.new(x, 2.0, z) + off, 0.85, { Name = "PlanterFlower", Color = FLOWER_COLORS[(i * 3 + k - 1) % #FLOWER_COLORS + 1] })
		end
	end

	-- 가로등: 마당 문 안쪽 양옆 (+ 마당이 길면 중간에 한 쌍 더)
	for _, lz in Y.LampZs do
		for _, sx in { -1, 1 } do
			lampPost(ctx, sx * Y.LampX, lz)
		end
	end

	-- 환영 매트 (현관 바로 앞 길 위, 바닥에 붙어 있어요)
	local mat = box(ctx, "WelcomeMat", -3, 3, 0.1, 0.22, L.FrontZ - 3.4, L.FrontZ - 0.6, {
		Color = lighter(theme.Accent, 0.1),
		Material = Enum.Material.Fabric,
		CanCollide = false,
		CanTouch = false,
	})
	surfaceText(mat, Enum.NormalId.Top, "🐾 어서 와요 🐾", UDim2.fromScale(0.05, 0.15), UDim2.fromScale(0.9, 0.7))
end

----------------------------------------------------------------------
-- 받침대
----------------------------------------------------------------------
-- 잠긴 받침대 글자: 가격 / N층 혜택 / 자물쇠만
local function lockText(slot: number): string
	local price = Config.Plot.SlotPrices[slot]
	if price then
		return "🔒 💰" .. Config.FormatNumber(price)
	end
	local f = Config.SlotFloor(slot)
	if f >= 2 then
		return "🔒 " .. f .. "층 혜택"
	end
	return "🔒"
end

-- 받침대 색/글자 적용 (상태가 같으면 건너뜀)
local function applyPedestal(top: BasePart, base: BasePart?, bb: BillboardGui?, label: TextLabel?, slot: number, slotsUnlocked: number, theme: Theme, visible: boolean)
	local state = if not visible then "hidden" elseif slot <= slotsUnlocked then "open" elseif slot == slotsUnlocked + 1 then "next" else "locked"
	if top:GetAttribute("State") == state then
		return
	end
	top:SetAttribute("State", state)
	if state == "hidden" then
		top.Transparency = 1
		top.CanCollide = false
		if base then
			base.Transparency = 1
			base.CanCollide = false
		end
		if bb then
			bb.Enabled = false
		end
		return
	end
	top.CanCollide = true
	if base then
		base.CanCollide = true
	end
	if state == "open" then
		top.Color = theme.Accent
		top.Transparency = 0
		if base then
			base.Color = WHITE
			base.Transparency = 0
		end
		if bb then
			bb.Enabled = false
		end
	else
		top.Color = LOCKED_GREY
		top.Transparency = 0.15
		if base then
			base.Color = LOCKED_GREY_DARK
			base.Transparency = 0
		end
		if bb then
			bb.Enabled = true
		end
		if label then
			label.Text = lockText(slot)
			label.TextColor3 = if state == "next" then GOLD_TEXT else Color3.new(1, 1, 1)
		end
	end
end

local function buildPedestals(ctx: Ctx, slotsUnlocked: number): { [number]: BasePart }
	local L = ctx.L
	local pedestals: { [number]: BasePart } = {}
	for f = 1, ctx.floors do
		local y = HouseLayout.FloorY(f)
		for i, s in L.Slots do
			local slot = (f - 1) * SLOTS_PER_FLOOR + i
			local m = Instance.new("Model")
			m.Name = "Pedestal" .. slot
			local base = vcyl(ctx, s.X, s.Z, y, PED_BASE_H, L.PedD, { Name = "Base", Color = WHITE, Parent = m })
			local top = vcyl(ctx, s.X, s.Z, y + PED_BASE_H, PED_TOP_H, L.PedTopD, { Name = "Top", Color = ctx.theme.Accent, Parent = m })
			top:SetAttribute("Slot", slot)
			top:SetAttribute("Floor", f)
			local bb, label = makeBillboard(top, 2.2, 5, 1.6, 50, "Label")
			bb.Enabled = false
			m.Parent = ctx.house
			applyPedestal(top, base, bb, label, slot, slotsUnlocked, ctx.theme, true)
			pedestals[slot] = top
		end
	end
	return pedestals
end

----------------------------------------------------------------------
-- 수금 패드 / 스폰 (플롯 모델 바로 아래. 있으면 재사용)
----------------------------------------------------------------------
local function findPart(plotModel: Model, name: string): BasePart?
	local inst = plotModel:FindFirstChild(name)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function buildCollector(ctx: Ctx, plotModel: Model): BasePart
	local cl = ctx.L.Collector
	-- 흰 테두리 링은 House 안 (매번 새로)
	vcyl(ctx, cl.X, cl.Z, FLOOR1_TOP, 0.25, cl.D + 0.8, { Name = "CollectorRing", Color = WHITE, CanCollide = false, CanTouch = false })
	local collector = findPart(plotModel, "Collector")
	if not collector then
		local p = Instance.new("Part")
		p.Name = "Collector"
		p.Shape = Enum.PartType.Cylinder
		collector = p
	end
	local c = collector :: BasePart
	c.Anchored = true
	c.CanCollide = true
	c.CanTouch = true
	c.TopSurface = Enum.SurfaceType.Smooth
	c.BottomSurface = Enum.SurfaceType.Smooth
	c.Size = Vector3.new(0.6, cl.D, cl.D)
	c.CFrame = ctx.origin * CFrame.new(cl.X, FLOOR1_TOP + 0.3, cl.Z) * CFrame.Angles(0, 0, math.pi / 2)
	c.Color = GOLD
	c.Material = Enum.Material.Neon
	c.Transparency = 0
	if c:GetAttribute("Pending") == nil then
		c:SetAttribute("Pending", 0)
	end
	if not c:FindFirstChildOfClass("BillboardGui") then
		local _, label = makeBillboard(c, 3.5, 7, 1.8, 60, "Amount")
		label.TextColor3 = GOLD_TEXT
		label.Text = "💰 모으기"
	end
	c.Parent = plotModel
	ctx.count += 1
	return c
end

local function buildSpawn(ctx: Ctx, plotModel: Model): BasePart
	local sp = ctx.L.Spawn
	local spawn = findPart(plotModel, "SpawnPoint")
	if not spawn then
		local p = Instance.new("Part")
		p.Name = "SpawnPoint"
		spawn = p
	end
	local s = spawn :: BasePart
	s.Anchored = true
	s.Size = Vector3.new(sp.Size, 1, sp.Size)
	s.CFrame = ctx.origin * CFrame.new(sp.X, FLOOR1_TOP + 0.5, sp.Z) -- 입구(컨베이어) 쪽을 바라봄
	s.Material = Enum.Material.SmoothPlastic
	s.Transparency = 1
	s.CanCollide = false
	s.CanTouch = false
	s.CanQuery = false
	s.CastShadow = false
	s.Parent = plotModel
	ctx.count += 1
	return s
end

----------------------------------------------------------------------
-- 테마 장식 (마당 빈 자리 / 1층 벽 위 / 지붕)
----------------------------------------------------------------------
local function flower(ctx: Ctx, base: Vector3, h: number, color: Color3)
	vcyl(ctx, base.X, base.Z, base.Y, h, 0.22, { Name = "Stem", Color = LEAF, CanCollide = false, CanTouch = false })
	ball(ctx, base + Vector3.new(0, h + 0.3, 0), 0.8, { Name = "Flower", Color = color })
end

local function lollipop(ctx: Ctx, base: Vector3, color: Color3)
	vcyl(ctx, base.X, base.Z, base.Y, 3.2, 0.35, { Name = "LollipopStick", Color = WHITE, CanCollide = false, CanTouch = false })
	ball(ctx, base + Vector3.new(0, 3.9, 0), 1.9, { Name = "Lollipop", Color = color })
end

local function mushroomLamp(ctx: Ctx, base: Vector3, capColor: Color3)
	local s = 1.1
	vcyl(ctx, base.X, base.Z, base.Y, 1.5 * s, 0.9 * s, { Name = "MushroomStem", Color = WHITE, CanCollide = false, CanTouch = false })
	local capPos = base + Vector3.new(0, 1.5 * s + 0.25 * s, 0)
	local cap = blob(ctx, capPos, Vector3.new(2.6 * s, 1.5 * s, 2.6 * s), { Name = "MushroomCap", Color = capColor })
	addLight(cap, lighter(capColor, 0.3), 12, 0.9)
	ball(ctx, capPos + Vector3.new(0.7 * s, 0.45 * s, 0.3 * s), 0.45, { Name = "MushroomDot", Color = WHITE })
	ball(ctx, capPos + Vector3.new(-0.6 * s, 0.4 * s, -0.5 * s), 0.4, { Name = "MushroomDot", Color = WHITE })
end

local function starfish(ctx: Ctx, pos: Vector3, color: Color3)
	for k = 0, 4 do
		local a = k * (math.pi * 2 / 5)
		deco(ctx, {
			Name = "StarfishArm",
			Size = Vector3.new(0.45, 0.22, 1.3),
			Local = CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.55),
			Color = color,
		})
	end
	ball(ctx, pos + Vector3.new(0, 0.05, 0), 0.5, { Name = "StarfishCenter", Color = lighter(color, 0.3) })
end

-- 반짝이는 네온 별 (십자 2개)
local function neonStar(ctx: Ctx, pos: Vector3, color: Color3)
	for _, size in { Vector3.new(0.3, 1.6, 0.3), Vector3.new(1.6, 0.3, 0.3) } do
		deco(ctx, {
			Name = "Star",
			Size = size,
			Local = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 4),
			Color = color,
			Material = Enum.Material.Neon,
			CastShadow = false,
		})
	end
end

-- 고리 달린 행성 (공 + 납작한 원판)
local function planet(ctx: Ctx, pos: Vector3, d: number, color: Color3, ringColor: Color3)
	ball(ctx, pos, d, { Name = "Planet", Color = color, Material = Enum.Material.SmoothPlastic, CastShadow = false })
	hcyl(ctx, CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2 + 0.35), 0.15, d * 1.7, {
		Name = "PlanetRing",
		Color = ringColor,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CastShadow = false,
	})
end

local DECO: { [string]: (Ctx) -> () } = {}

-- 기본 집: 꽃밭 + 벽 위 꽃 상자
DECO.flowers = function(ctx: Ctx)
	local theme = ctx.theme
	local bed = ctx.yardSpots[1] + Vector3.new(2, 0, 0)
	box(ctx, "FlowerBed", bed.X - 2.8, bed.X + 2.8, 0, 0.6, bed.Z - 1.1, bed.Z + 1.1, { Color = darker(theme.Floor, 0.2), Material = Enum.Material.Grass })
	for k = 0, 4 do
		local x = bed.X - 1.9 + k * 0.95
		local z = bed.Z + (if k % 2 == 0 then -0.45 else 0.45)
		flower(ctx, Vector3.new(x, 0.6, z), 0.9 + (k % 3) * 0.2, FLOWER_COLORS[k % #FLOWER_COLORS + 1])
	end
	for i, idx in { 1, 3, 4 } do
		local c = ctx.capSpots[idx]
		if c then
			local spot = c.pos
			local sz = if c.alongX then Vector3.new(5, 0.6, 1.2) else Vector3.new(1.2, 0.6, 5)
			part(ctx, { Name = "FlowerBox", Size = sz, Local = CFrame.new(spot + Vector3.new(0, 0.3, 0)), Color = darker(theme.Accent, 0.15) })
			for k = -1, 1 do
				local off = if c.alongX then Vector3.new(k * 1.5, 1.0, 0) else Vector3.new(0, 1.0, k * 1.5)
				ball(ctx, spot + off, 0.9, { Name = "BoxFlower", Color = FLOWER_COLORS[(i + k + 3) % #FLOWER_COLORS + 1] })
			end
		end
	end
end

-- 캔디 하우스: 막대사탕, 지팡이 사탕, 줄무늬 지붕, 지붕 위 큰 사탕
DECO.candy = function(ctx: Ctx)
	local theme = ctx.theme
	local L = ctx.L
	local pastel = { Color3.fromRGB(255, 150, 200), Color3.fromRGB(160, 235, 205), Color3.fromRGB(255, 240, 150), Color3.fromRGB(205, 180, 255) }
	for i, spot in { ctx.yardSpots[1], ctx.yardSpots[2], ctx.yardSpots[3], ctx.sideSpots[2] } do
		lollipop(ctx, spot, pastel[(i - 1) % #pastel + 1])
	end
	-- 지팡이 사탕 (현관 양옆 바깥, 갈고리는 바깥쪽으로)
	for _, sx in { -1, 1 } do
		local x, z = sx * (L.Door.MaxX + 1.3), L.FrontZ - 0.9
		vcyl(ctx, x, z, 0, 4.2, 0.55, { Name = "CandyCane", Color = RED, CanCollide = false, CanTouch = false })
		hcyl(ctx, CFrame.new(x + sx * 0.65, 4.2, z), 1.3, 0.55, { Name = "CandyCaneHook", Color = WHITE })
		vcyl(ctx, x + sx * 1.3, z, 3.2, 1.0, 0.55, { Name = "CandyCaneTip", Color = RED, CanCollide = false, CanTouch = false })
	end
	roofStripes(ctx, { theme.Accent, WHITE })
	local top = Vector3.new(0, ctx.roofBase + ctx.roofH + 2.0, L.CenterZ)
	ball(ctx, top, 3, { Name = "RoofCandy", Color = theme.Accent })
	ball(ctx, top + Vector3.new(0.7, 0.8, -0.6), 1.0, { Name = "RoofCandyShine", Color = WHITE })
end

-- 숲속 오두막: 버섯 램프, 통나무, 앞 기둥 덩굴
DECO.mushrooms = function(ctx: Ctx)
	local L = ctx.L
	local caps = { Color3.fromRGB(255, 110, 120), Color3.fromRGB(255, 170, 90), Color3.fromRGB(255, 150, 200) }
	for i = 1, 3 do
		mushroomLamp(ctx, ctx.yardSpots[i], caps[i])
	end
	for _, idx in { 6, 7, 2 } do
		local c = ctx.capSpots[idx]
		if c then
			local along = if c.alongX then CFrame.new(c.pos + Vector3.new(0, 0.55, 0)) else CFrame.new(c.pos + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, math.pi / 2, 0)
			hcyl(ctx, along, 3.2, 1.1, { Name = "Log", Color = WOOD, Material = Enum.Material.Wood })
		end
	end
	for _, sx in { -1, 1 } do
		local foot = Vector3.new(sx * (L.Half - PILLAR / 2), 0, L.FrontZ - 0.25)
		deco(ctx, { Name = "Vine", Size = Vector3.new(0.3, 9, 0.3), Local = CFrame.new(foot + Vector3.new(-sx * 0.5, FLOOR1_TOP + 4.5, 0)), Color = LEAF })
		ball(ctx, foot + Vector3.new(-sx * 0.5, 3, -0.2), 0.8, { Name = "VineLeaf", Color = lighter(LEAF, 0.2) })
		ball(ctx, foot + Vector3.new(-sx * 0.5, 6.4, -0.2), 0.7, { Name = "VineLeaf", Color = LEAF })
	end
end

-- 바다 집: 조개, 불가사리, 작은 물웅덩이(오리 포함)
DECO.shells = function(ctx: Ctx)
	local theme = ctx.theme
	local pool = ctx.yardSpots[1] + Vector3.new(1.5, 0, 0)
	vcyl(ctx, pool.X, pool.Z, 0, 0.7, 5.2, { Name = "PoolRim", Color = lighter(theme.Floor, 0.3) })
	vcyl(ctx, pool.X, pool.Z, 0.3, 0.5, 4.6, { Name = "PoolWater", Color = SKY, Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false, CanTouch = false })
	ball(ctx, Vector3.new(pool.X - 0.8, 1.15, pool.Z + 0.4), 0.9, { Name = "Duck", Color = Color3.fromRGB(255, 225, 80) })
	ball(ctx, Vector3.new(pool.X - 0.8, 1.1, pool.Z - 0.15), 0.35, { Name = "DuckBeak", Color = Color3.fromRGB(255, 150, 70) })
	local shellColors = { Color3.fromRGB(255, 200, 215), Color3.fromRGB(255, 240, 220), Color3.fromRGB(230, 200, 255), Color3.fromRGB(255, 215, 180) }
	local spots = { ctx.yardSpots[3], ctx.yardSpots[4] }
	for _, idx in { 2, 4 } do
		local c = ctx.capSpots[idx]
		if c then
			table.insert(spots, c.pos)
		end
	end
	for i, spot in spots do
		blob(ctx, spot + Vector3.new(0, 0.35, 0), Vector3.new(1.3, 0.7, 1.1), { Name = "Shell", Color = shellColors[(i - 1) % #shellColors + 1] })
	end
	for i, idx in { 3, 6 } do
		local c = ctx.capSpots[idx]
		if c then
			starfish(ctx, c.pos + Vector3.new(0, 0.11, 0), if i == 1 then Color3.fromRGB(255, 150, 110) else Color3.fromRGB(255, 180, 200))
		end
	end
end

-- 우주 기지: 네온 별, 로켓, 지붕 위 접시 안테나
DECO.stars = function(ctx: Ctx)
	local theme = ctx.theme
	local L = ctx.L
	local ridgeY = ctx.roofBase + ctx.roofH
	local starPos = {
		Vector3.new(-(L.Half - PILLAR / 2), 9.5, L.FrontZ - 0.35),
		Vector3.new(L.Half - PILLAR / 2, 9.5, L.FrontZ - 0.35),
		Vector3.new(-L.Size * 0.3, ridgeY + 1.6, L.CenterZ),
		Vector3.new(L.Size * 0.3, ridgeY + 1.6, L.CenterZ),
		Vector3.new(-(GATE_HALF + 4.4), 8, -FENCE + 0.85),
	}
	for _, p in starPos do
		neonStar(ctx, p, theme.Accent)
	end
	-- 로켓 (앞마당 오른쪽)
	local r = ctx.yardSpots[1]
	local rx, rz = r.X, r.Z
	vcyl(ctx, rx, rz, 0.6, 4.2, 1.9, { Name = "RocketBody", Color = WHITE, Material = Enum.Material.Metal })
	ball(ctx, Vector3.new(rx, 4.8, rz), 1.9, { Name = "RocketNose", Color = RED })
	ball(ctx, Vector3.new(rx, 3.2, rz - 0.85), 0.7, { Name = "RocketWindow", Color = SKY, Material = Enum.Material.Neon })
	ball(ctx, Vector3.new(rx, 0.35, rz), 1.0, { Name = "RocketFlame", Color = Color3.fromRGB(255, 160, 60), Material = Enum.Material.Neon, CastShadow = false })
	for k = 0, 2 do
		local a = k * (math.pi * 2 / 3) + math.pi / 6
		deco(ctx, {
			Name = "RocketFin",
			Size = Vector3.new(0.25, 1.5, 1.2),
			Local = CFrame.new(rx, 1.2, rz) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -1.3),
			Color = RED,
		})
	end
	-- 접시 안테나 (지붕 앞쪽 경사 왼편)
	local dx, dz = -L.Size * 0.25, L.CenterZ - ctx.roofD * 0.35
	local base = roofY(ctx, dz)
	part(ctx, { Name = "DishBase", Size = Vector3.new(1.2, 1.2, 1.2), Local = CFrame.new(dx, base + 0.3, dz), Color = lighter(theme.Wall, 0.1), Material = Enum.Material.Metal })
	deco(ctx, { Name = "DishPole", Size = Vector3.new(0.3, 1.8, 0.3), Local = CFrame.new(dx, base + 1.7, dz), Color = DARK })
	deco(ctx, {
		Name = "Dish",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, 2.8, 2.8),
		Local = CFrame.new(dx, base + 2.8, dz) * CFrame.Angles(0, math.pi / 2, math.rad(-55)),
		Color = WHITE,
		Material = Enum.Material.Metal,
	})
end

-- 무지개 궁전: 앞마당 오른쪽 작은 무지개 아치 (길 위가 아니에요) + 구름 + 파스텔 지붕 줄무늬
DECO.rainbow = function(ctx: Ctx)
	local bandW = 0.9
	local thick = 1.2
	local segs = 4
	local bands = 4
	local outerR = 5.6
	local c = ctx.yardSpots[1] + Vector3.new(2.2, 0, 0)
	local da = math.pi / segs
	for b = 1, bands do
		local r = outerR - (b - 0.5) * bandW
		local len = 2 * r * math.sin(da / 2) + 0.3
		for k = 0, segs - 1 do
			local am = (k + 0.5) * da
			local radial = Vector3.new(math.cos(am), math.sin(am), 0)
			local tangent = Vector3.new(-math.sin(am), math.cos(am), 0)
			deco(ctx, {
				Name = "RainbowBand",
				Size = Vector3.new(len, bandW, thick),
				Local = CFrame.fromMatrix(c + radial * r, tangent, radial),
				Color = RAINBOW_COLORS[b],
				CastShadow = false,
			})
		end
	end
	for _, sx in { -1, 1 } do
		blob(ctx, c + Vector3.new(sx * (outerR - 1.6), 0.8, 0), Vector3.new(3.6, 1.8, 2.6), { Name = "Cloud", Color = Color3.new(1, 1, 1), CastShadow = false })
	end
	roofStripes(ctx, RAINBOW_COLORS)
end

-- 왕궁: 빨간 카펫 길 + 금 테두리, 마당 문 왕관(buildYard), 현관 양옆 깃발, 지붕 위 큰 왕관, 둥근 정원수
DECO.royal = function(ctx: Ctx)
	local L = ctx.L
	local edge = FENCE + FENCE_T / 2
	for _, sx in { -1, 1 } do
		local x = sx * (L.Door.MaxX - 0.2)
		box(ctx, "CarpetTrim", x - 0.2, x + 0.2, 0.1, 0.14, -edge, L.FrontZ, { Color = GOLD, CanCollide = false, CanTouch = false })
	end
	-- 깃발: 2층 바닥 밑(1층짜리면 처마 밑)에 매달려요. 길(|x| ≤ 5) 밖이에요
	local hangY = if ctx.floors >= 2 then HouseLayout.FloorY(2) - SLAB_T - 0.1 else ctx.eaveY - 0.4
	for _, sx in { -1, 1 } do
		local x = sx * (L.Door.MaxX + 2.6)
		box(ctx, "Banner", x - 0.8, x + 0.8, hangY - 6, hangY, L.FrontZ - 0.35, L.FrontZ - 0.2, { Color = ROYAL_RED, CanCollide = false, CanTouch = false, Material = Enum.Material.Fabric })
		box(ctx, "BannerTrim", x - 0.85, x + 0.85, hangY - 6.4, hangY - 6, L.FrontZ - 0.4, L.FrontZ - 0.15, { Color = GOLD, CanCollide = false, CanTouch = false })
	end
	crown(ctx, Vector3.new(0, ctx.roofBase + ctx.roofH + 0.4, L.CenterZ), 2.4)
	for _, i in { 1, 3 } do
		local s = ctx.yardSpots[i]
		box(ctx, "TopiaryPot", s.X - 0.9, s.X + 0.9, 0, 1.2, s.Z - 0.9, s.Z + 0.9, { Color = WHITE, Material = Enum.Material.Marble })
		ball(ctx, s + Vector3.new(0, 2.6, 0), 2.8, { Name = "Topiary", Color = Color3.fromRGB(70, 160, 80), Material = Enum.Material.Grass })
		ball(ctx, s + Vector3.new(0, 4.2, 0), 0.6, { Name = "TopiaryGold", Color = GOLD })
	end
end

-- 은하 궁전: 고리 행성, 네온 별 반짝이, 성운 띠 (1층 벽 위 띠는 capLook 이 네온으로)
DECO.galaxy = function(ctx: Ctx)
	local theme = ctx.theme
	local L = ctx.L
	local y1 = ctx.yardSpots[1]
	local y3 = ctx.yardSpots[3]
	planet(ctx, y1 + Vector3.new(0, 3.2, 0), 2.8, Color3.fromRGB(255, 150, 120), NEBULA_COLORS[3])
	planet(ctx, y3 + Vector3.new(0, 2.6, 0), 1.9, Color3.fromRGB(130, 200, 255), NEBULA_COLORS[2])
	planet(ctx, Vector3.new(L.Size * 0.18, ctx.roofBase + ctx.roofH + 4, L.CenterZ), 4, Color3.fromRGB(190, 140, 255), theme.Accent)
	-- 별 반짝이: 1층 벽 바깥, 울타리 위
	local wallW = L.Half - PILLAR - L.Door.MaxX -- 현관 옆 앞벽 길이 (문 구멍 밖에만 붙여요)
	local specks = {
		Vector3.new(-(L.Door.MaxX + wallW * 0.7), 1.6, L.FrontZ - 0.15),
		Vector3.new(-(L.Door.MaxX + wallW * 0.3), 2.6, L.FrontZ - 0.15),
		Vector3.new(L.Door.MaxX + wallW * 0.35, 2.1, L.FrontZ - 0.15),
		Vector3.new(L.Door.MaxX + wallW * 0.75, 1.3, L.FrontZ - 0.15),
		Vector3.new(-L.Half - 0.15, 2.4, L.CenterZ - 4),
		Vector3.new(L.Half + 0.15, 1.8, L.CenterZ + 3),
		Vector3.new(-20, FENCE_H + 0.6, -FENCE),
		Vector3.new(16, FENCE_H + 0.6, -FENCE),
		Vector3.new(-28, FENCE_H + 0.6, -FENCE),
		Vector3.new(26, FENCE_H + 0.6, -FENCE),
	}
	for i, p in specks do
		ball(ctx, p, if i % 3 == 0 then 0.55 else 0.4, {
			Name = "StarSpeck",
			Color = if i % 2 == 0 then Color3.fromRGB(255, 245, 170) else Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
			CastShadow = false,
		})
	end
	-- 성운 띠: 처마 앞뒤
	for i, sz in { -1, 1 } do
		local z = if sz < 0 then L.FrontZ - 1.3 else L.BackZ + 1.3
		box(ctx, "Nebula", -L.Half - 1.2, L.Half + 1.2, ctx.eaveY - 0.15, ctx.eaveY + 0.15, z - 0.12, z + 0.12, {
			Color = NEBULA_COLORS[i],
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = false,
			CastShadow = false,
		})
	end
end

----------------------------------------------------------------------
-- 장식 자리 계산
----------------------------------------------------------------------
local function decoSpots(ctx: Ctx)
	local L = ctx.L
	local st = L.Stair
	local S = L.Size
	-- 앞마당 (울타리 근처, 길 |x| ≤ 5 밖) / 집 양옆. 자리는 HouseLayout 이 정해요: 가구 막힌 자리(BlockedRects)도 같은 자리
	-- 라서, 테마 장식을 옮기면 HouseLayout 의 DECO_YARD 도 같이 고쳐요
	ctx.yardSpots = table.clone(L.Yard.Spots)
	ctx.sideSpots = table.clone(L.Yard.Side)
	-- 1층 벽 위: 왼쪽 3, 오른쪽 2, 뒤 2
	local rightEnd = if ctx.floors >= 2 then st.MinZ else L.BackZ - PILLAR
	local backEnd = if ctx.floors >= 2 then st.GlassX else L.Half - PILLAR
	local caps: { { pos: Vector3, alongX: boolean } } = {}
	for _, k in { 0.3, 0.55, 0.8 } do
		table.insert(caps, { pos = Vector3.new(-L.Half + 0.5, CAP_TOP, L.FrontZ + S * k), alongX = false })
	end
	for _, k in { 0.3, 0.5 } do
		local z = L.FrontZ + S * k
		if z < rightEnd - 3 then
			table.insert(caps, { pos = Vector3.new(L.Half - 0.5, CAP_TOP, z), alongX = false })
		end
	end
	for _, k in { -0.3, -0.05 } do
		local x = S * k
		if x < backEnd - 3 then
			table.insert(caps, { pos = Vector3.new(x, CAP_TOP, L.BackZ - 0.5), alongX = true })
		end
	end
	ctx.capSpots = caps
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------
HouseBuilder.FLOOR_HEIGHT = HouseLayout.FLOOR_HEIGHT
HouseBuilder.Layout = HouseLayout

function HouseBuilder.FloorY(floor: number): number
	return HouseLayout.FloorY(floor)
end

-- 받침대 윗면 (아이템 모델의 바닥 피벗 자리), 월드 CFrame. 인스턴스 없이 계산만 해요
function HouseBuilder.SlotCFrame(origin: CFrame, slot: number, themeId: string?): CFrame
	return HouseLayout.SlotCFrame(origin, slot, themeId)
end

function HouseBuilder.SlotLocal(slot: number, themeId: string?): CFrame
	return HouseLayout.SlotLocal(slot, themeId)
end

function HouseBuilder.FloorBounds(themeId: string?, floor: number): HouseLayout.Bounds
	return HouseLayout.FloorBounds(themeId, floor)
end

function HouseBuilder.BlockedRects(themeId: string?, floor: number): { HouseLayout.Rect }
	return HouseLayout.BlockedRects(themeId, floor)
end

function HouseBuilder.FloorSpawn(origin: CFrame, themeId: string?, floor: number): CFrame
	return HouseLayout.FloorSpawn(origin, themeId, floor)
end

function HouseBuilder.ElevatorLocal(themeId: string?, floor: number): CFrame
	return HouseLayout.ElevatorLocal(themeId, floor)
end

-- 집 전체를 (다시) 지어요. 기존 House 는 지우고, Collector / SpawnPoint 는 재사용.
-- 엘리베이터 프롬프트 주인은 plotModel 의 OwnerUserId 속성 (부르는 쪽이 짓기 전에 맞춰요)
function HouseBuilder.Build(plotModel: Model, origin: CFrame, themeId: string, floors: number, slotsUnlocked: number): Handles
	local theme, id = themeOf(themeId)
	local floorCount = math.clamp(math.floor(tonumber(floors) or 1), 1, Config.House.MaxFloors)
	local unlocked = math.clamp(math.floor(tonumber(slotsUnlocked) or Config.Plot.StartSlots), 0, Config.Plot.TotalSlots)
	local L = HouseLayout.Get(id)

	local old = plotModel:FindFirstChild("House")
	if old then
		old:Destroy()
	end
	local house = Instance.new("Model")
	house.Name = "House"
	house.ModelStreamingMode = Enum.ModelStreamingMode.Default
	house:SetAttribute("Theme", id)
	house:SetAttribute("Floors", floorCount)
	house:SetAttribute("Size", L.Size)

	local eaveY = HouseLayout.RoofY(floorCount)
	local roofD = (L.Size + 2) / 2
	local ctx: Ctx = {
		origin = origin,
		house = house,
		theme = theme,
		deco = theme.Deco,
		mats = MATERIALS[theme.Deco] or MATERIALS.flowers,
		floors = floorCount,
		count = 0,
		L = L,
		ownerId = tonumber(plotModel:GetAttribute("OwnerUserId")) or 0,
		eaveY = eaveY,
		roofBase = eaveY + 0.3,
		roofH = 4 + L.Size * 0.2,
		roofD = roofD,
		yardSpots = {},
		sideSpots = {},
		capSpots = {},
	}
	decoSpots(ctx)

	buildYard(ctx)
	buildGroundFloor(ctx)
	buildPillars(ctx)
	buildDoor(ctx)
	for f = 1, floorCount do
		if f >= 2 then
			buildSlab(ctx, f)
		end
		buildPerimeter(ctx, f)
	end
	buildTower(ctx)
	local elevators: { [number]: BasePart } = {}
	for f = 1, floorCount do
		elevators[f] = buildElevator(ctx, f)
	end
	buildRoof(ctx)
	local pedestals = buildPedestals(ctx, unlocked)
	local collector = buildCollector(ctx, plotModel)
	local spawn = buildSpawn(ctx, plotModel)
	local decorate = DECO[theme.Deco] or DECO.flowers
	decorate(ctx)

	house:SetAttribute("PartCount", ctx.count)
	house.Parent = plotModel

	local baseY = origin.Position.Y
	return {
		House = house,
		Pedestals = pedestals,
		SpawnPoint = spawn,
		Collector = collector,
		Elevators = elevators,
		Bounds = { MinY = baseY - 1, MaxY = baseY + ctx.roofBase + ctx.roofH + 6 },
	}
end

-- 받침대 잠김/열림 색과 가격표만 갱신 (다시 짓지 않음). 층이 바뀌면 Build 를 다시 불러야 해요
function HouseBuilder.UpdatePedestals(handles: Handles, slotsUnlocked: number, floors: number)
	local theme = themeOf(handles.House:GetAttribute("Theme"))
	local floorCount = math.clamp(math.floor(tonumber(floors) or 1), 1, Config.House.MaxFloors)
	local unlocked = math.clamp(math.floor(tonumber(slotsUnlocked) or 0), 0, Config.Plot.TotalSlots)
	for slot, top in handles.Pedestals do
		local m = top.Parent
		local baseInst = if m then m:FindFirstChild("Base") else nil
		local base: BasePart? = if baseInst and baseInst:IsA("BasePart") then baseInst else nil
		local bb = top:FindFirstChildOfClass("BillboardGui")
		local labelInst = if bb then bb:FindFirstChild("Label") else nil
		local label: TextLabel? = if labelInst and labelInst:IsA("TextLabel") then labelInst else nil
		applyPedestal(top, base, bb, label, slot, unlocked, theme, Config.SlotFloor(slot) <= floorCount)
	end
end

-- 이 모듈이 만든 것들을 지워요 (House, Collector, SpawnPoint)
function HouseBuilder.Destroy(plotModel: Model)
	for _, name in { "House", "Collector", "SpawnPoint" } do
		local inst = plotModel:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end
end

return HouseBuilder
