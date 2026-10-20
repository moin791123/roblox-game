-- 집(플롯) 외형 빌더: 바닥·벽·기둥·지붕·받침대·2층(계단/난간)·앞마당·테마 장식을 지어요.
-- (설계: docs/DESIGN.md "HouseBuilder"). 순수 빌드만 해요: 이벤트/루프/yield 없음. PlotService 가 불러서 써요.
-- 좌표는 전부 플롯 로컬 (origin = 바닥 중심 y=0, 입구 = 로컬 -Z). 받침대 1~12 위치는 예전 PlotService 와 똑같아요.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HouseBuilder = {}

export type Handles = {
	House: Model,
	Pedestals: { [number]: BasePart }, -- 슬롯 번호 → 받침대 윗판. 13~24 는 floors == 2 일 때만 있어요
	SpawnPoint: BasePart,
	Collector: BasePart,
	Bounds: { MinY: number, MaxY: number }, -- 월드 y 범위 (바닥 밑 ~ 지붕 꼭대기)
}

----------------------------------------------------------------------
-- 배치 상수 (플롯 로컬 좌표)
----------------------------------------------------------------------
local SIZE = Config.Layout.PlotSize -- 40
local HALF = SIZE / 2
local FLOOR_TOP = 0.2 -- 1층 바닥 윗면 (땅 y=0 보다 살짝 위, z-fighting 방지)
local WALL_H = 3
local WALL_T = 1
local GAP = 12 -- 입구 너비 (문 없음, 막는 것 없음)
local CAP_TOP = FLOOR_TOP + WALL_H + 0.5 -- 벽 위 장식띠 윗면 (작은 장식을 올려 두는 자리)
local PILLAR = 2 -- 모서리 기둥 두께
local POST_H = 9.6 -- 입구 기둥 높이
local PED_BASE_H = 0.6
local PED_TOP_H = 1.0
local PED_H = PED_BASE_H + PED_TOP_H -- 받침대 윗면 = 바닥 + 1.6 (1층: 1.8, 2층: 12.6)
local PED_BASE_D = 5.4
local PED_TOP_D = 4.6
local SLOT_COLS = { -13.5, -4.5, 4.5, 13.5 } -- x (PlotService 와 동일)
local SLOT_ROWS = { -4, 4.5, 13 } -- z, 입구에 가까운 줄부터
local SLOTS_PER_FLOOR = #SLOT_COLS * #SLOT_ROWS -- 12
local COLLECTOR_POS = Vector3.new(-12, 0, -13) -- 수금 패드 (예전과 동일)
local SPAWN_POS = Vector3.new(0, FLOOR_TOP + 0.5, -9) -- 스폰 (예전과 동일)
local FLOOR_HEIGHT = 11 -- 2층 슬래브 윗면 (두께 1: y 10 ~ 11)
local ROOF_Y1 = 10 -- 1층 집 처마 높이
local ROOF_Y2 = 21 -- 2층 집 처마 높이
local ROOF_H = 6 -- 지붕 높이 (처마 → 용마루)
local ROOF_S = SIZE + 2 -- 지붕 한 변 (처마가 1씩 튀어나옴)
local ROOF_DX = 14 -- 양 끝 경사면 깊이 (용마루 길이 = ROOF_S - 2 × ROOF_DX = 14, X 방향)
local ROOF_DZ = ROOF_S / 2 -- 앞뒤 경사면 깊이
local STAIR_X0 = 7.5 -- 계단 시작 x (앞벽 오른쪽, 입구 기둥 옆에서 +X 로 올라감)
local STAIR_Z = -16.9 -- 계단 중심 z (폭 4: -18.9 ~ -14.9)
local STAIR_W = 4
local STEP_RISE = 1.2 -- 한 칸 높이 (≤ 1.2: 캐릭터가 걸어 올라갈 수 있어요)
local STEP_RUN = 1.27 -- 한 칸 깊이
local STEP_COUNT = 9 -- 9 × 1.2 = 10.8 = FLOOR_HEIGHT - FLOOR_TOP
local RAIL_H = 1.3
local RAIL_SPACING = 6
local YARD_Z = -HALF - 1.8 -- 앞마당 장식 줄 (앞벽 바깥, 입구 길 |x| ≤ 5.5 은 비워 둠)

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
local SKY = Color3.fromRGB(150, 210, 255)

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

type Theme = { Name: string, Price: number, Floor: Color3, Wall: Color3, Roof: Color3, Accent: Color3, Deco: string }
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
}

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end

local function darker(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end

----------------------------------------------------------------------
-- 파트 도우미 (모두 Anchored. Local = 플롯 로컬 CFrame, 부모 기본값 = House)
----------------------------------------------------------------------
type Ctx = { origin: CFrame, house: Model, theme: Theme, mats: Mats, floors: number, count: number }

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

-- 장식: 안 부딪히고 안 밟혀요 (받침대 주변은 걸어 다닐 수 있게)
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

local function cornerWedge(ctx: Ctx, props: { [string]: any }): CornerWedgePart
	local p = Instance.new("CornerWedgePart")
	finish(ctx, p, props)
	return p
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

----------------------------------------------------------------------
-- 받침대 좌표 (순수 함수)
----------------------------------------------------------------------
local function slotXZ(slot: number): (number, number)
	local i = (slot - 1) % SLOTS_PER_FLOOR -- 0..11, 2층도 같은 격자
	local row = math.floor(i / #SLOT_COLS) + 1
	local col = i % #SLOT_COLS + 1
	return SLOT_COLS[col], SLOT_ROWS[row]
end

-- 받침대가 놓이는 바닥 윗면 높이 (1층 0.2 / 2층 11)
local function floorTopOf(slot: number): number
	return if Config.SlotFloor(slot) == 2 then FLOOR_HEIGHT else FLOOR_TOP
end

-- 지붕 윗면이 처마에서 얼마나 솟았는지 (장식을 지붕 위에 얹을 때)
local function roofRise(x: number, z: number): number
	local fz = 1 - math.abs(z) / ROOF_DZ
	local ex = math.abs(x) - (ROOF_S / 2 - ROOF_DX)
	local fx = if ex > 0 then 1 - ex / ROOF_DX else 1
	return ROOF_H * math.clamp(math.min(fz, fx), 0, 1)
end

----------------------------------------------------------------------
-- 구조물
----------------------------------------------------------------------
local function buildFloor(ctx: Ctx)
	local theme = ctx.theme
	local floor = part(ctx, {
		Name = "Floor",
		Size = Vector3.new(SIZE, 1, SIZE),
		Local = CFrame.new(0, FLOOR_TOP - 0.5, 0),
		Color = theme.Floor,
		Material = ctx.mats.Floor,
	})
	part(ctx, {
		Name = "FloorTrim",
		Size = Vector3.new(SIZE + 2, 1, SIZE + 2),
		Local = CFrame.new(0, FLOOR_TOP / 2 - 0.5, 0),
		Color = theme.Accent,
	})
	ctx.house.PrimaryPart = floor
end

-- 낮은 벽 3면 + 입구 양옆 (입구는 넓게 뚫려 있어요)
local function buildWalls(ctx: Ctx)
	local theme = ctx.theme
	local segLen = HALF - GAP / 2
	local walls = {
		{ Vector3.new(0, 0, HALF - WALL_T / 2), Vector3.new(SIZE, WALL_H, WALL_T) }, -- 뒤
		{ Vector3.new(-HALF + WALL_T / 2, 0, 0), Vector3.new(WALL_T, WALL_H, SIZE) }, -- 왼쪽
		{ Vector3.new(HALF - WALL_T / 2, 0, 0), Vector3.new(WALL_T, WALL_H, SIZE) }, -- 오른쪽
		{ Vector3.new(-(GAP / 2 + segLen / 2), 0, -HALF + WALL_T / 2), Vector3.new(segLen, WALL_H, WALL_T) }, -- 입구 왼쪽
		{ Vector3.new(GAP / 2 + segLen / 2, 0, -HALF + WALL_T / 2), Vector3.new(segLen, WALL_H, WALL_T) }, -- 입구 오른쪽
	}
	for i, w in walls do
		local pos, size = w[1], w[2]
		part(ctx, {
			Name = "Wall" .. i,
			Size = size,
			Local = CFrame.new(pos.X, FLOOR_TOP + WALL_H / 2, pos.Z),
			Color = theme.Wall,
			Material = ctx.mats.Wall,
		})
		local capColor = if theme.Deco == "rainbow" then RAINBOW_COLORS[(i - 1) % #RAINBOW_COLORS + 1] else theme.Accent
		part(ctx, {
			Name = "WallCap" .. i,
			Size = Vector3.new(size.X + 0.4, 0.5, size.Z + 0.4),
			Local = CFrame.new(pos.X, FLOOR_TOP + WALL_H + 0.25, pos.Z),
			Color = capColor,
		})
	end
end

-- 기둥 램프 (따뜻한 PointLight)
local function buildLamp(ctx: Ctx, sx: number, sz: number, y: number)
	local pillar = Vector3.new(sx * (HALF - PILLAR / 2), y, sz * (HALF - PILLAR / 2))
	local inward = Vector3.new(-sx, 0, -sz).Unit
	local armC = pillar + inward * 1.7
	deco(ctx, {
		Name = "LampArm",
		Size = Vector3.new(0.3, 0.3, 1.4),
		Local = CFrame.lookAt(armC, armC + inward),
		Color = DARK,
	})
	local bulb = ball(ctx, pillar + inward * 2.6, 1.1, { Name = "Lamp", Color = LAMP, Material = Enum.Material.Neon, CastShadow = false })
	addLight(bulb, LAMP, 16, 1)
end

-- 모서리 기둥 4개 (지붕까지) + 램프
local function buildPillars(ctx: Ctx, roofY: number)
	local h = roofY - FLOOR_TOP
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local sx, sz = c[1], c[2]
		part(ctx, {
			Name = "Pillar",
			Size = Vector3.new(PILLAR, h, PILLAR),
			Local = CFrame.new(sx * (HALF - PILLAR / 2), FLOOR_TOP + h / 2, sz * (HALF - PILLAR / 2)),
			Color = lighter(ctx.theme.Wall, 0.15),
			Material = ctx.mats.Wall,
		})
		buildLamp(ctx, sx, sz, 6.4)
		if ctx.floors >= 2 then
			buildLamp(ctx, sx, sz, FLOOR_HEIGHT + 5.4)
		end
	end
end

-- 입구 기둥 + 이름 간판 (BillboardGui > TextLabel "OwnerLabel": PlotService 가 글자를 넣어요)
local function buildGate(ctx: Ctx)
	local theme = ctx.theme
	for _, sx in { -1, 1 } do
		local x = sx * (GAP / 2 + 0.6)
		part(ctx, {
			Name = "GatePost",
			Size = Vector3.new(1.2, POST_H, 1.2),
			Local = CFrame.new(x, FLOOR_TOP + POST_H / 2, -HALF + WALL_T / 2),
			Color = lighter(theme.Wall, 0.15),
			Material = ctx.mats.Wall,
		})
		ball(ctx, Vector3.new(x, FLOOR_TOP + POST_H + 0.6, -HALF + WALL_T / 2), 1.6, { Name = "GateBall", Color = theme.Accent })
	end
	local sign = part(ctx, {
		Name = "Sign",
		Size = Vector3.new(GAP + 3.6, 2.8, 0.5),
		Local = CFrame.new(0, FLOOR_TOP + POST_H - 1.4, -HALF + WALL_T / 2),
		Color = theme.Accent,
	})
	local bb, label = makeBillboard(sign, 0, 13, 2.4, 70, "OwnerLabel")
	bb.AlwaysOnTop = true
	label.TextStrokeTransparency = 0.1
	label.Text = "빈 집"
end

-- 모임지붕: 가운데 쐐기 2개(앞/뒤) + 모서리 쐐기 4개. 처마 밑면 = eaveY
local function buildRoof(ctx: Ctx, eaveY: number)
	local theme = ctx.theme
	local roofColor = theme.Roof
	local cornerColor = if theme.Deco == "candy" then lighter(theme.Roof, 0.55) else roofColor
	for _, sz in { -1, 1 } do
		wedge(ctx, {
			Name = "RoofSlope",
			Size = Vector3.new(ROOF_S - 2 * ROOF_DX, ROOF_H, ROOF_DZ),
			Local = CFrame.new(0, eaveY + ROOF_H / 2, sz * ROOF_DZ / 2) * CFrame.Angles(0, if sz < 0 then 0 else math.pi, 0),
			Color = roofColor,
			Material = ctx.mats.Roof,
		})
	end
	-- CornerWedgePart 의 꼭짓점(수직 모서리)은 로컬 +X,+Z 에 있어요 → 집 안쪽을 향하게 돌려요
	-- (스튜디오에서 꼭짓점이 바깥을 보면 CORNER_ROT_OFFSET 만 ±math.pi/2 로 바꾸면 돼요. 크기는 자동으로 따라가요)
	local CORNER_ROT_OFFSET = 0
	local corners = { { -1, -1, 0 }, { 1, 1, math.pi }, { -1, 1, math.pi / 2 }, { 1, -1, -math.pi / 2 } }
	for _, c in corners do
		local sx, sz = c[1], c[2]
		local rot = c[3] + CORNER_ROT_OFFSET
		local axisAligned = math.abs(math.sin(rot)) < 1e-6
		cornerWedge(ctx, {
			Name = "RoofCorner",
			Size = if axisAligned then Vector3.new(ROOF_DX, ROOF_H, ROOF_DZ) else Vector3.new(ROOF_DZ, ROOF_H, ROOF_DX),
			Local = CFrame.new(sx * (ROOF_S / 2 - ROOF_DX / 2), eaveY + ROOF_H / 2, sz * ROOF_DZ / 2) * CFrame.Angles(0, rot, 0),
			Color = cornerColor,
			Material = ctx.mats.Roof,
		})
	end
	-- 용마루
	part(ctx, {
		Name = "Ridge",
		Size = Vector3.new(ROOF_S - 2 * ROOF_DX + 1.2, 0.8, 1.4),
		Local = CFrame.new(0, eaveY + ROOF_H + 0.25, 0),
		Color = theme.Accent,
	})
	-- 굴뚝 (우주 기지는 대신 접시 안테나)
	if theme.Deco ~= "stars" then
		local cx, cz = 10, 6
		local top = eaveY + roofRise(cx, cz) + 3
		part(ctx, {
			Name = "Chimney",
			Size = Vector3.new(2.2, 5, 2.2),
			Local = CFrame.new(cx, top - 2.5, cz),
			Color = lighter(theme.Wall, 0.1),
			Material = ctx.mats.Wall,
		})
		part(ctx, {
			Name = "ChimneyCap",
			Size = Vector3.new(2.8, 0.6, 2.8),
			Local = CFrame.new(cx, top + 0.3, cz),
			Color = darker(theme.Roof, 0.15),
		})
	end
end

-- 지붕 경사면 위 줄무늬 (캔디/무지개)
local function roofStripes(ctx: Ctx, eaveY: number, colors: { Color3 })
	local a = math.atan2(ROOF_H, ROOF_DZ)
	local len = math.sqrt(ROOF_DZ * ROOF_DZ + ROOF_H * ROOF_H) - 1
	local normal = Vector3.new(0, math.cos(a), -math.sin(a))
	local i = 0
	for _, sz in { -1, 1 } do
		for _, x in { -4, 0, 4 } do
			i += 1
			local mid = Vector3.new(x, eaveY + ROOF_H / 2, sz * ROOF_DZ / 2)
			local n = Vector3.new(0, normal.Y, sz * normal.Z)
			local rot = if sz < 0 then CFrame.Angles(-a, 0, 0) else CFrame.Angles(0, math.pi, 0) * CFrame.Angles(-a, 0, 0)
			deco(ctx, {
				Name = "RoofStripe",
				Size = Vector3.new(1.3, 0.2, len),
				Local = CFrame.new(mid + n * 0.12) * rot,
				Color = colors[(i - 1) % #colors + 1],
			})
		end
	end
end

----------------------------------------------------------------------
-- 앞마당·소품 (모든 테마 공통): 환영 매트, 우편함, 펫 집, 화분
----------------------------------------------------------------------
local function buildYard(ctx: Ctx)
	local theme = ctx.theme
	-- 환영 매트 (입구 안쪽, 바닥에 붙어서 걷는 데 방해 없음)
	local mat = deco(ctx, {
		Name = "WelcomeMat",
		Size = Vector3.new(6, 0.16, 3.6),
		Local = CFrame.new(0, FLOOR_TOP + 0.08, -HALF + 2.6),
		Color = lighter(theme.Accent, 0.1),
		Material = Enum.Material.Fabric,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	local matLabel = Instance.new("TextLabel")
	matLabel.Size = UDim2.fromScale(0.9, 0.7)
	matLabel.Position = UDim2.fromScale(0.05, 0.15)
	matLabel.BackgroundTransparency = 1
	matLabel.TextScaled = true
	matLabel.Font = Enum.Font.FredokaOne
	matLabel.TextColor3 = Color3.new(1, 1, 1)
	matLabel.TextStrokeTransparency = 0.4
	matLabel.Text = "🐾 어서 와요 🐾"
	matLabel.Parent = sg
	sg.Parent = mat

	-- 우편함 (앞마당 오른쪽)
	local mx = 12
	part(ctx, { Name = "MailPost", Size = Vector3.new(0.4, 2.6, 0.4), Local = CFrame.new(mx, 1.3, YARD_Z + 0.3), Color = WOOD, Material = Enum.Material.Wood })
	part(ctx, { Name = "Mailbox", Size = Vector3.new(1.5, 1.1, 1.0), Local = CFrame.new(mx, 3.15, YARD_Z + 0.3), Color = theme.Accent })
	deco(ctx, { Name = "MailFlag", Size = Vector3.new(0.12, 0.9, 0.35), Local = CFrame.new(mx + 0.8, 3.5, YARD_Z + 0.3), Color = RED })

	-- 펫 집 (앞마당 왼쪽, 입구는 컨베이어 쪽)
	local px, pz = -15, YARD_Z
	part(ctx, { Name = "PetHouse", Size = Vector3.new(3.4, 2.6, 3.0), Local = CFrame.new(px, 1.3, pz), Color = theme.Wall, Material = ctx.mats.Wall })
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
	vcyl(ctx, px, pz - 2.4, 0, 0.12, 1.6, { Name = "PetMat", Color = lighter(theme.Accent, 0.2), CanCollide = false, CanTouch = false })

	-- 화분 2개 (입구 양옆 바깥)
	for i, sx in { -1, 1 } do
		local x, z = sx * 8, YARD_Z + 0.2
		part(ctx, { Name = "Planter", Size = Vector3.new(2.6, 1.2, 2.6), Local = CFrame.new(x, 0.6, z), Color = darker(theme.Accent, 0.15) })
		blob(ctx, Vector3.new(x, 1.45, z), Vector3.new(2.4, 1.1, 2.4), { Name = "PlanterLeaves", Color = LEAF })
		local offsets = { Vector3.new(-0.6, 0, 0.3), Vector3.new(0.55, 0.1, 0.45), Vector3.new(0.05, 0.25, -0.55) }
		for k, off in offsets do
			ball(ctx, Vector3.new(x, 2.0, z) + off, 0.85, { Name = "PlanterFlower", Color = FLOWER_COLORS[(i * 3 + k - 1) % #FLOWER_COLORS + 1] })
		end
	end
end

----------------------------------------------------------------------
-- 2층: 슬래브 + 계단 + 난간
----------------------------------------------------------------------
-- 슬래브 가장자리 난간 (기둥 + 가로대 2줄). a, b = 로컬 x,z
local function railEdge(ctx: Ctx, a: Vector3, b: Vector3)
	local theme = ctx.theme
	local y = FLOOR_HEIGHT
	local len = (b - a).Magnitude
	local n = math.max(1, math.ceil(len / RAIL_SPACING))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		part(ctx, {
			Name = "RailPost",
			Size = Vector3.new(0.4, RAIL_H, 0.4),
			Local = CFrame.new(p.X, y + RAIL_H / 2, p.Z),
			Color = lighter(theme.Wall, 0.1),
		})
	end
	local mid = (a + b) / 2
	for _, h in { RAIL_H - 0.15, RAIL_H * 0.5 } do
		part(ctx, {
			Name = "Rail",
			Size = Vector3.new(0.3, 0.3, len + 0.4),
			Local = CFrame.lookAt(Vector3.new(mid.X, y + h, mid.Z), Vector3.new(b.X, y + h, b.Z)),
			Color = theme.Accent,
		})
	end
end

local function buildFloor2(ctx: Ctx)
	local theme = ctx.theme
	local slabColor = lighter(theme.Floor, 0.15)
	local slabY = FLOOR_HEIGHT - 0.5
	-- 슬래브: 받침대 구역 전체 + 앞쪽 양 날개. 입구 위(|x| < 7.6, z < -8)는 뚫려 있어요 (아트리움). 계단 자리(오른쪽 앞)도 비움
	part(ctx, { Name = "Floor2", Size = Vector3.new(SIZE - 2, 1, 27), Local = CFrame.new(0, slabY, 5.5), Color = slabColor, Material = ctx.mats.Floor })
	part(ctx, { Name = "Floor2Left", Size = Vector3.new(11.4, 1, 11), Local = CFrame.new(-13.3, slabY, -13.5), Color = slabColor, Material = ctx.mats.Floor })
	part(ctx, { Name = "Floor2Right", Size = Vector3.new(11.4, 1, 7), Local = CFrame.new(13.3, slabY, -11.5), Color = slabColor, Material = ctx.mats.Floor })

	-- 계단 (앞벽 오른쪽을 따라 +X 로 올라감). 블록 계단 + 보이지 않는 경사면(부드럽게 걷기)
	for i = 1, STEP_COUNT do
		local top = FLOOR_TOP + STEP_RISE * i
		part(ctx, {
			Name = "Step" .. i,
			Size = Vector3.new(STEP_RUN, top - FLOOR_TOP, STAIR_W),
			Local = CFrame.new(STAIR_X0 + STEP_RUN * (i - 0.5), (FLOOR_TOP + top) / 2, STAIR_Z),
			Color = if i % 2 == 0 then lighter(theme.Accent, 0.35) else lighter(theme.Wall, 0.1),
			Material = ctx.mats.Wall,
		})
	end
	local run = STEP_RUN * STEP_COUNT
	local rise = STEP_RISE * STEP_COUNT
	wedge(ctx, {
		Name = "StairRamp",
		Size = Vector3.new(STAIR_W, rise, run),
		Local = CFrame.new(STAIR_X0 + run / 2, FLOOR_TOP + rise / 2, STAIR_Z) * CFrame.Angles(0, math.pi / 2, 0),
		Transparency = 1,
		CastShadow = false,
	})
	-- 계단 안쪽 손잡이 (1~7칸, 꼭대기 쪽은 비워서 날개로 걸어 나갈 수 있게)
	local railSteps = 7
	local rx0, ry0 = STAIR_X0, FLOOR_TOP + 1.7
	local rx1, ry1 = STAIR_X0 + STEP_RUN * railSteps, FLOOR_TOP + STEP_RISE * railSteps + 1.7
	local rz = STAIR_Z + STAIR_W / 2 + 0.15
	local railLen = math.sqrt((rx1 - rx0) ^ 2 + (ry1 - ry0) ^ 2)
	part(ctx, {
		Name = "StairRail",
		Size = Vector3.new(railLen + 0.3, 0.3, 0.3),
		Local = CFrame.new((rx0 + rx1) / 2, (ry0 + ry1) / 2, rz) * CFrame.Angles(0, 0, math.atan2(ry1 - ry0, rx1 - rx0)),
		Color = theme.Accent,
	})
	for _, i in { 1, 4, 7 } do
		local top = FLOOR_TOP + STEP_RISE * i
		part(ctx, {
			Name = "StairRailPost",
			Size = Vector3.new(0.3, 1.2, 0.3),
			Local = CFrame.new(STAIR_X0 + STEP_RUN * (i - 0.5), top + 0.6, rz),
			Color = lighter(theme.Wall, 0.1),
		})
	end

	-- 난간: 바깥 둘레 + 아트리움 가장자리 (계단 도착 구간 x > 14.5, z < -14.7 은 비움)
	local e = HALF - 1.3 -- 18.7
	local edges = {
		{ Vector3.new(-e, 0, e), Vector3.new(e, 0, e) }, -- 뒤
		{ Vector3.new(-e, 0, -e), Vector3.new(-e, 0, e) }, -- 왼쪽
		{ Vector3.new(e, 0, -14.7), Vector3.new(e, 0, e) }, -- 오른쪽
		{ Vector3.new(-e, 0, -e), Vector3.new(-7.9, 0, -e) }, -- 왼쪽 날개 앞
		{ Vector3.new(-7.9, 0, -e), Vector3.new(-7.9, 0, -8.3) }, -- 아트리움 왼쪽
		{ Vector3.new(-7.9, 0, -8.3), Vector3.new(7.9, 0, -8.3) }, -- 아트리움 앞
		{ Vector3.new(7.9, 0, -8.3), Vector3.new(7.9, 0, -14.7) }, -- 아트리움 오른쪽
		{ Vector3.new(7.9, 0, -14.7), Vector3.new(14.5, 0, -14.7) }, -- 오른쪽 날개 앞 (계단 위)
	}
	for _, edge in edges do
		railEdge(ctx, edge[1], edge[2])
	end
end

----------------------------------------------------------------------
-- 받침대
----------------------------------------------------------------------
-- 잠긴 받침대 글자: 가격 / 2층 혜택 / 자물쇠만
local function lockText(slot: number): string
	local price = Config.Plot.SlotPrices[slot]
	if price then
		return "🔒 💰" .. Config.FormatNumber(price)
	end
	if slot > SLOTS_PER_FLOOR then
		return "🔒 2층 혜택"
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
	local pedestals: { [number]: BasePart } = {}
	local count = if ctx.floors >= 2 then Config.Plot.TotalSlots else SLOTS_PER_FLOOR
	for slot = 1, count do
		local x, z = slotXZ(slot)
		local bottom = floorTopOf(slot)
		local m = Instance.new("Model")
		m.Name = "Pedestal" .. slot
		local base = vcyl(ctx, x, z, bottom, PED_BASE_H, PED_BASE_D, { Name = "Base", Color = WHITE, Parent = m })
		local top = vcyl(ctx, x, z, bottom + PED_BASE_H, PED_TOP_H, PED_TOP_D, { Name = "Top", Color = ctx.theme.Accent, Parent = m })
		top:SetAttribute("Slot", slot)
		local bb, label = makeBillboard(top, 2.2, 5, 1.6, 50, "Label")
		bb.Enabled = false
		m.Parent = ctx.house
		applyPedestal(top, base, bb, label, slot, slotsUnlocked, ctx.theme, true)
		pedestals[slot] = top
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
	-- 흰 테두리 링은 House 안 (매번 새로)
	vcyl(ctx, COLLECTOR_POS.X, COLLECTOR_POS.Z, FLOOR_TOP, 0.3, 7.2, { Name = "CollectorRing", Color = WHITE })
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
	c.Size = Vector3.new(0.6, 6, 6)
	c.CFrame = ctx.origin * CFrame.new(COLLECTOR_POS.X, FLOOR_TOP + 0.3, COLLECTOR_POS.Z) * CFrame.Angles(0, 0, math.pi / 2)
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
	local spawn = findPart(plotModel, "SpawnPoint")
	if not spawn then
		local p = Instance.new("Part")
		p.Name = "SpawnPoint"
		spawn = p
	end
	local s = spawn :: BasePart
	s.Anchored = true
	s.Size = Vector3.new(4, 1, 4)
	s.CFrame = ctx.origin * CFrame.new(SPAWN_POS) -- 입구(컨베이어) 쪽을 바라봄
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
-- 테마 장식
----------------------------------------------------------------------
-- 작은 장식을 올려 두는 자리: 앞마당 (y=0) 과 벽 위 띠 (y=CAP_TOP)
local YARD_SPOTS = { Vector3.new(15.3, 0, YARD_Z), Vector3.new(18.2, 0, YARD_Z), Vector3.new(-11.2, 0, YARD_Z) }
local CAP_SPOTS = {
	Vector3.new(-HALF + 0.5, CAP_TOP, -11),
	Vector3.new(-HALF + 0.5, CAP_TOP, -1),
	Vector3.new(-HALF + 0.5, CAP_TOP, 9),
	Vector3.new(HALF - 0.5, CAP_TOP, -11),
	Vector3.new(HALF - 0.5, CAP_TOP, -1),
	Vector3.new(HALF - 0.5, CAP_TOP, 9),
	Vector3.new(-12, CAP_TOP, HALF - 0.5),
	Vector3.new(0, CAP_TOP, HALF - 0.5),
	Vector3.new(12, CAP_TOP, HALF - 0.5),
}

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

local DECO: { [string]: (Ctx, number) -> () } = {}

-- 기본 집: 꽃밭 + 벽 위 꽃 상자
DECO.flowers = function(ctx: Ctx)
	local theme = ctx.theme
	-- 앞마당 꽃밭 (우편함 오른쪽)
	part(ctx, { Name = "FlowerBed", Size = Vector3.new(5.6, 0.6, 2.2), Local = CFrame.new(15.8, 0.3, YARD_Z), Color = darker(theme.Floor, 0.2), Material = Enum.Material.Grass })
	for k = 0, 4 do
		local x = 13.9 + k * 0.95
		local z = YARD_Z + (if k % 2 == 0 then -0.45 else 0.45)
		flower(ctx, Vector3.new(x, 0.6, z), 0.9 + (k % 3) * 0.2, FLOWER_COLORS[k % #FLOWER_COLORS + 1])
	end
	-- 벽 위 꽃 상자 4개 (양옆 벽)
	for i, spot in { CAP_SPOTS[1], CAP_SPOTS[3], CAP_SPOTS[4], CAP_SPOTS[6] } do
		part(ctx, { Name = "FlowerBox", Size = Vector3.new(1.2, 0.6, 5), Local = CFrame.new(spot + Vector3.new(0, 0.3, 0)), Color = darker(theme.Accent, 0.15) })
		for k = -1, 1 do
			ball(ctx, spot + Vector3.new(0, 1.0, k * 1.5), 0.9, { Name = "BoxFlower", Color = FLOWER_COLORS[(i + k + 3) % #FLOWER_COLORS + 1] })
		end
	end
end

-- 캔디 하우스: 막대사탕, 지팡이 사탕, 줄무늬 지붕, 지붕 위 큰 사탕
DECO.candy = function(ctx: Ctx, eaveY: number)
	local theme = ctx.theme
	local pastel = { Color3.fromRGB(255, 150, 200), Color3.fromRGB(160, 235, 205), Color3.fromRGB(255, 240, 150), Color3.fromRGB(205, 180, 255) }
	for i, spot in { YARD_SPOTS[1], YARD_SPOTS[2], YARD_SPOTS[3], CAP_SPOTS[8] } do
		lollipop(ctx, spot, pastel[(i - 1) % #pastel + 1])
	end
	-- 지팡이 사탕 (입구 양옆 바깥)
	for _, sx in { -1, 1 } do
		local x, z = sx * 5.9, YARD_Z + 0.5
		vcyl(ctx, x, z, 0, 4.2, 0.55, { Name = "CandyCane", Color = RED, CanCollide = false, CanTouch = false })
		hcyl(ctx, CFrame.new(x + sx * 0.65, 4.2, z), 1.3, 0.55, { Name = "CandyCaneHook", Color = WHITE })
		vcyl(ctx, x + sx * 1.3, z, 3.2, 1.0, 0.55, { Name = "CandyCaneTip", Color = RED, CanCollide = false, CanTouch = false })
	end
	roofStripes(ctx, eaveY, { theme.Accent, WHITE })
	local top = Vector3.new(0, eaveY + ROOF_H + 2.0, 0)
	ball(ctx, top, 3, { Name = "RoofCandy", Color = theme.Accent })
	ball(ctx, top + Vector3.new(0.7, 0.8, -0.6), 1.0, { Name = "RoofCandyShine", Color = WHITE })
end

-- 숲속 오두막: 버섯 램프, 통나무, 기둥 덩굴
DECO.mushrooms = function(ctx: Ctx)
	local caps = { Color3.fromRGB(255, 110, 120), Color3.fromRGB(255, 170, 90), Color3.fromRGB(255, 150, 200) }
	for i, spot in YARD_SPOTS do
		mushroomLamp(ctx, spot, caps[i])
	end
	for i, spot in { CAP_SPOTS[7], CAP_SPOTS[9], CAP_SPOTS[2] } do
		local along = if i <= 2 then CFrame.new(spot + Vector3.new(0, 0.55, 0)) else CFrame.new(spot + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, math.pi / 2, 0)
		hcyl(ctx, along, 3.2, 1.1, { Name = "Log", Color = WOOD, Material = Enum.Material.Wood })
	end
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local sx, sz = c[1], c[2]
		local inward = Vector3.new(-sx, 0, -sz).Unit
		local foot = Vector3.new(sx * (HALF - PILLAR / 2), 0, sz * (HALF - PILLAR / 2)) + inward * 1.5
		deco(ctx, { Name = "Vine", Size = Vector3.new(0.3, 7.5, 0.3), Local = CFrame.new(foot + Vector3.new(0, FLOOR_TOP + 3.75, 0)), Color = LEAF })
		ball(ctx, foot + Vector3.new(sx * 0.3, 2.6, 0), 0.8, { Name = "VineLeaf", Color = lighter(LEAF, 0.2) })
		ball(ctx, foot + Vector3.new(0, 5.2, sz * 0.3), 0.7, { Name = "VineLeaf", Color = LEAF })
	end
end

-- 바다 집: 조개, 불가사리, 작은 물웅덩이(오리 포함)
DECO.shells = function(ctx: Ctx)
	local theme = ctx.theme
	-- 물웅덩이 (앞마당 오른쪽)
	local poolX, poolZ = 15.6, YARD_Z - 0.3
	vcyl(ctx, poolX, poolZ, 0, 0.7, 5.2, { Name = "PoolRim", Color = lighter(theme.Floor, 0.3) })
	vcyl(ctx, poolX, poolZ, 0.3, 0.5, 4.6, { Name = "PoolWater", Color = SKY, Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false, CanTouch = false })
	ball(ctx, Vector3.new(poolX - 0.8, 1.15, poolZ + 0.4), 0.9, { Name = "Duck", Color = Color3.fromRGB(255, 225, 80) })
	ball(ctx, Vector3.new(poolX - 0.8, 1.1, poolZ - 0.15), 0.35, { Name = "DuckBeak", Color = Color3.fromRGB(255, 150, 70) })
	-- 조개 4개
	local shellColors = { Color3.fromRGB(255, 200, 215), Color3.fromRGB(255, 240, 220), Color3.fromRGB(230, 200, 255), Color3.fromRGB(255, 215, 180) }
	for i, spot in { YARD_SPOTS[3], Vector3.new(18.8, 0, YARD_Z + 0.6), CAP_SPOTS[2], CAP_SPOTS[5] } do
		blob(ctx, spot + Vector3.new(0, 0.35, 0), Vector3.new(1.3, 0.7, 1.1), { Name = "Shell", Color = shellColors[i] })
	end
	starfish(ctx, CAP_SPOTS[3] + Vector3.new(0, 0.11, 0), Color3.fromRGB(255, 150, 110))
	starfish(ctx, CAP_SPOTS[8] + Vector3.new(0, 0.11, 0), Color3.fromRGB(255, 180, 200))
end

-- 우주 기지: 네온 별, 로켓, 지붕 위 접시 안테나
DECO.stars = function(ctx: Ctx, eaveY: number)
	local theme = ctx.theme
	local starPos = {
		Vector3.new(-(HALF - PILLAR / 2), 8.3, -HALF - 0.35),
		Vector3.new(HALF - PILLAR / 2, 8.3, -HALF - 0.35),
		Vector3.new(0, FLOOR_TOP + POST_H + 1.6, -HALF + WALL_T / 2),
		Vector3.new(-8, eaveY + ROOF_H + 1.4, 0),
		Vector3.new(8, eaveY + ROOF_H + 1.4, 0),
	}
	for _, p in starPos do
		neonStar(ctx, p, theme.Accent)
	end
	-- 로켓 (앞마당 오른쪽)
	local rx, rz = 15.5, YARD_Z - 0.2
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
	-- 접시 안테나 (지붕 왼쪽)
	local dx, dz = -10, 5
	local base = eaveY + roofRise(dx, dz)
	part(ctx, { Name = "DishBase", Size = Vector3.new(1.2, 1.2, 1.2), Local = CFrame.new(dx, base + 0.3, dz), Color = lighter(theme.Wall, 0.1), Material = Enum.Material.Metal })
	deco(ctx, { Name = "DishPole", Size = Vector3.new(0.3, 1.8, 0.3), Local = CFrame.new(dx, base + 1.7, dz), Color = DARK })
	deco(ctx, {
		Name = "Dish",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, 2.8, 2.8),
		Local = CFrame.new(dx, base + 2.8, dz) * CFrame.Angles(0, 0, math.rad(-55)),
		Color = WHITE,
		Material = Enum.Material.Metal,
	})
end

-- 무지개 궁전: 입구 위 무지개 아치 + 파스텔 지붕 줄무늬
DECO.rainbow = function(ctx: Ctx, eaveY: number)
	local bandW = 0.95
	local thick = 1.4
	local segs = 7
	local outerR = 11.2
	local archZ = YARD_Z - 1.2
	local da = math.pi / segs
	for b = 1, 5 do
		local r = outerR - (b - 0.5) * bandW
		local len = 2 * r * math.sin(da / 2) + 0.3
		for k = 0, segs - 1 do
			local am = (k + 0.5) * da
			local radial = Vector3.new(math.cos(am), math.sin(am), 0)
			local tangent = Vector3.new(-math.sin(am), math.cos(am), 0)
			local pos = Vector3.new(0, 0, archZ) + radial * r
			deco(ctx, {
				Name = "RainbowBand",
				Size = Vector3.new(len, bandW, thick),
				Local = CFrame.fromMatrix(pos, tangent, radial),
				Color = RAINBOW_COLORS[b],
				CastShadow = false,
			})
		end
	end
	-- 아치 발밑 구름
	for _, sx in { -1, 1 } do
		blob(ctx, Vector3.new(sx * (outerR - 2.4), 1.0, archZ), Vector3.new(5.5, 2.4, 3.6), { Name = "Cloud", Color = Color3.new(1, 1, 1), CastShadow = false })
	end
	roofStripes(ctx, eaveY, RAINBOW_COLORS)
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------
HouseBuilder.FLOOR_HEIGHT = FLOOR_HEIGHT

-- 받침대 윗면 (아이템 모델의 바닥 피벗 자리), 월드 CFrame. 인스턴스 없이 계산만 해요
function HouseBuilder.SlotCFrame(origin: CFrame, slot: number): CFrame
	local x, z = slotXZ(slot)
	return origin * CFrame.new(x, floorTopOf(slot) + PED_H, z)
end

-- 집 전체를 (다시) 지어요. 기존 House 는 지우고, Collector / SpawnPoint 는 재사용
function HouseBuilder.Build(plotModel: Model, origin: CFrame, themeId: string, floors: number, slotsUnlocked: number): Handles
	local theme, id = themeOf(themeId)
	local floorCount = math.clamp(math.floor(tonumber(floors) or 1), 1, Config.House.MaxFloors)
	local unlocked = math.clamp(math.floor(tonumber(slotsUnlocked) or Config.Plot.StartSlots), 0, Config.Plot.TotalSlots)

	local old = plotModel:FindFirstChild("House")
	if old then
		old:Destroy()
	end
	local house = Instance.new("Model")
	house.Name = "House"
	house.ModelStreamingMode = Enum.ModelStreamingMode.Default
	house:SetAttribute("Theme", id)
	house:SetAttribute("Floors", floorCount)

	local ctx: Ctx = {
		origin = origin,
		house = house,
		theme = theme,
		mats = MATERIALS[theme.Deco] or MATERIALS.flowers,
		floors = floorCount,
		count = 0,
	}
	local roofY = if floorCount >= 2 then ROOF_Y2 else ROOF_Y1

	buildFloor(ctx)
	buildWalls(ctx)
	buildPillars(ctx, roofY)
	buildGate(ctx)
	buildRoof(ctx, roofY)
	buildYard(ctx)
	if floorCount >= 2 then
		buildFloor2(ctx)
	end
	local pedestals = buildPedestals(ctx, unlocked)
	local collector = buildCollector(ctx, plotModel)
	local spawn = buildSpawn(ctx, plotModel)
	local decorate = DECO[theme.Deco] or DECO.flowers
	decorate(ctx, roofY)

	house:SetAttribute("PartCount", ctx.count)
	house.Parent = plotModel

	return {
		House = house,
		Pedestals = pedestals,
		SpawnPoint = spawn,
		Collector = collector,
		Bounds = { MinY = origin.Position.Y - 1, MaxY = origin.Position.Y + roofY + ROOF_H + 3.5 },
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
