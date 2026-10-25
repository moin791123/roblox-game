-- 귀여운 파스텔 월드 (v4): 가운데 숲 마을 + 둘레 섬 7개 + 숲 마을 가장자리에서 섬으로 가는 짧은 길(Trail) + 길 입구 문(Gate)
-- + 테마 장식 + 로비 + 바다 + 조명. 모든 자리는 Config.Zones (Center/Size/Trail/Gate/Spawn/Conveyor/Field) 에서 읽어요
-- 집(플롯)/컨베이어/코인/순위표는 다른 서비스가 만들어요. 여기서는 그 자리를 비워 둬요.
-- 모든 파트는 workspace.World 아래. 문은 workspace.World.Gates.Gate<k> (서버에서는 CanCollide 끔, 클라이언트가 잠근 사람만 막아요)
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

local Layout = Config.Layout
local Zones = Config.Zones
local HALF_PLOT = Layout.PlotSize / 2
local LOBBY = Layout.LobbySpawn
local HALF_TRAIL = Layout.TrailWidth / 2
local SEA_Y = Layout.SeaY
local HOME_CENTER = Zones[1].Center

local FENCE_H = 4.6 -- 울타리 기둥 높이 (≥ 4)
local WALL_H = 60 -- 투명 벽 높이 (뛰어서 못 넘게)
local ARCH_BEAM_Y = 20 -- 지역 문 아치 들보 아래 높이 (탄 채로 지나가요, ≥ 18)
local PLAZA_R = 17 -- 로비 광장 반지름
local RAINBOW_X = LOBBY.X + 26 -- 로비에서 마을로 나가는 길 위 무지개
local RAINBOW_R = 24
local WALK_IN = 6 -- 집 컨베이어 옆 산책로 |z| 안쪽
local WALK_OUT = 12 -- 바깥쪽
local ZONE_PART_WARN = 400

local FONT = Enum.Font.FredokaOne
local RGB = Color3.fromRGB

local COLORS = {
	Path = RGB(250, 232, 198),
	PathDark = RGB(238, 212, 172),
	Cream = RGB(255, 250, 240),
	White = RGB(255, 255, 255),
	Pink = RGB(255, 160, 200),
	HotPink = RGB(255, 105, 170),
	Mint = RGB(160, 235, 205),
	Lavender = RGB(205, 180, 255),
	Peach = RGB(255, 200, 165),
	Lemon = RGB(255, 240, 150),
	Sky = RGB(165, 215, 255),
	Trunk = RGB(205, 155, 115),
	Bark = RGB(150, 105, 70),
	Leaf = RGB(95, 190, 95),
	DarkLeaf = RGB(60, 150, 75),
	Rock = RGB(165, 165, 178),
	Text = RGB(110, 70, 120),
	Gold = RGB(255, 205, 70),
	Black = RGB(45, 40, 55),
}

local CROWN_COLORS = {
	RGB(255, 180, 210),
	RGB(160, 235, 200),
	RGB(210, 185, 255),
	RGB(255, 200, 160),
	RGB(255, 240, 150),
	RGB(170, 215, 255),
	RGB(145, 220, 125),
}

local GREEN_CROWNS = {
	RGB(110, 200, 110),
	RGB(130, 215, 135),
	RGB(100, 190, 125),
	RGB(150, 220, 120),
}

local FLOWER_COLORS = {
	RGB(255, 150, 190),
	RGB(255, 230, 110),
	RGB(200, 160, 255),
	RGB(130, 200, 255),
	RGB(255, 255, 255),
	RGB(255, 180, 140),
	RGB(255, 115, 130),
}

local BUSH_COLORS = {
	RGB(110, 200, 110),
	RGB(130, 215, 135),
	RGB(100, 190, 125),
}

local CAP_COLORS = {
	RGB(255, 110, 120),
	RGB(255, 150, 200),
	RGB(190, 140, 255),
	RGB(255, 170, 90),
}

local CANDY_COLORS = {
	RGB(255, 120, 170),
	RGB(130, 220, 255),
	RGB(255, 225, 100),
	RGB(150, 230, 170),
	RGB(200, 150, 255),
	RGB(255, 160, 110),
}

local RAINBOW_COLORS = {
	RGB(255, 140, 150),
	RGB(255, 190, 120),
	RGB(255, 235, 130),
	RGB(150, 225, 150),
	RGB(140, 190, 255),
	RGB(200, 160, 255),
}

-- 지역별 땅 재질 / 절벽 색
local GROUND_MATERIAL: { [string]: Enum.Material } = {
	Village = Enum.Material.Grass,
	Lake = Enum.Material.Grass,
	Jungle = Enum.Material.LeafyGrass,
	Snow = Enum.Material.Snow,
	Ocean = Enum.Material.Sand,
	Candy = Enum.Material.SmoothPlastic,
	Cloud = Enum.Material.SmoothPlastic,
	Space = Enum.Material.Slate,
	Blossom = Enum.Material.Grass, -- ★v8
	Dino = Enum.Material.LeafyGrass,
	Crystal = Enum.Material.Slate,
	Desert = Enum.Material.Sand,
	Toy = Enum.Material.SmoothPlastic,
	Dream = Enum.Material.SmoothPlastic,
	Volcano = Enum.Material.Basalt,
	Gold = Enum.Material.Marble,
}

local CLIFF_COLOR: { [string]: Color3 } = {
	Village = RGB(170, 125, 90),
	Lake = RGB(160, 120, 85),
	Jungle = RGB(125, 90, 60),
	Snow = RGB(185, 210, 235),
	Ocean = RGB(220, 195, 140),
	Candy = RGB(125, 75, 55), -- 초콜릿 케이크
	Cloud = RGB(230, 225, 250),
	Space = RGB(50, 40, 85),
	Blossom = RGB(175, 125, 105), -- ★v8
	Dino = RGB(130, 100, 70),
	Crystal = RGB(70, 60, 95),
	Desert = RGB(215, 170, 110),
	Toy = RGB(90, 160, 255), -- 장난감 블록 받침
	Dream = RGB(95, 90, 160),
	Volcano = RGB(50, 40, 45),
	Gold = RGB(230, 185, 70),
}

local rng = Random.new(20261020)
local partCount = 0

----------------------------------------------------------------------
-- 파트 도우미
----------------------------------------------------------------------

local function newPart(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	shape: Enum.PartType?,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = parent
	partCount += 1
	return p
end

-- 공 모양 (지름 d)
local function ball(parent: Instance, pos: Vector3, d: number, color: Color3, material: Enum.Material?): Part
	return newPart(parent, Vector3.new(d, d, d), CFrame.new(pos), color, Enum.PartType.Ball, material)
end

-- 타원체 (SpecialMesh 구), CFrame 으로
local function blobCF(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = newPart(parent, size, cf, color, nil, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function blob(parent: Instance, pos: Vector3, size: Vector3, color: Color3, material: Enum.Material?): Part
	return blobCF(parent, CFrame.new(pos), size, color, material)
end

-- 세운 원기둥 (bottom = 바닥 중심)
local function column(parent: Instance, bottom: Vector3, height: number, d: number, color: Color3, material: Enum.Material?): Part
	return newPart(
		parent,
		Vector3.new(height, d, d),
		CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		Enum.PartType.Cylinder,
		material
	)
end

-- 눕힌 원판 (center = 원판 가운데, 두께 thickness)
local function disc(parent: Instance, center: Vector3, d: number, thickness: number, color: Color3, material: Enum.Material?): Part
	return newPart(
		parent,
		Vector3.new(thickness, d, d),
		CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		Enum.PartType.Cylinder,
		material
	)
end

-- a 에서 b 까지 이어진 막대 (원기둥)
local function stick(parent: Instance, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?): Part
	local dir = b - a
	local len = dir.Magnitude
	local up = if len > 0 and math.abs(dir.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	return newPart(parent, Vector3.new(len, d, d), cf, color, Enum.PartType.Cylinder, material)
end

-- 바닥에 까는 납작한 사각형 (윗면 높이 top)
local function flatRect(
	parent: Instance,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	top: number,
	color: Color3,
	material: Enum.Material?
): Part
	local minX, maxX = math.min(x0, x1), math.max(x0, x1)
	local minZ, maxZ = math.min(z0, z1), math.max(z0, z1)
	local p = newPart(
		parent,
		Vector3.new(maxX - minX, 1, maxZ - minZ),
		CFrame.new((minX + maxX) / 2, top - 0.5, (minZ + maxZ) / 2),
		color,
		nil,
		material or Enum.Material.Sand
	)
	p.CanCollide = true
	return p
end

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(COLORS.White, a)
end

local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

-- 반짝이 파티클 (하늘 눈/별 등)
local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

----------------------------------------------------------------------
-- 표지판 GUI
----------------------------------------------------------------------

local function signFrame(part: BasePart, face: Enum.NormalId, pixelsPerStud: number, bg: Color3, stroke: Color3): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Parent = part

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.95, 0.9)
	frame.BackgroundColor3 = bg
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = frame

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = stroke
	uiStroke.Thickness = math.max(4, pixelsPerStud * 0.18)
	uiStroke.Parent = frame
	return frame
end

local function textLabel(
	parent: Instance,
	text: string,
	pos: UDim2,
	size: UDim2,
	color: Color3,
	xAlign: Enum.TextXAlignment?
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = FONT
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeColor3 = COLORS.White
	l.TextStrokeTransparency = 0.2
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

-- 기둥 2개 + 판. 판의 앞면(Front)이 lookTarget 쪽을 봐요
local function buildSignBoard(
	parent: Instance,
	pos: Vector3,
	lookTarget: Vector3,
	boardSize: Vector2,
	bottomY: number,
	boardColor: Color3
): Part
	local base = CFrame.lookAt(pos, Vector3.new(lookTarget.X, pos.Y, lookTarget.Z))
	local postH = bottomY + boardSize.Y * 0.6
	for _, sx in { -1, 1 } do
		local postPos = (base * CFrame.new(sx * (boardSize.X / 2 - 0.8), 0, 0.5)).Position
		local post = column(parent, postPos, postH, 0.7, COLORS.White)
		post.CanCollide = true
	end
	local board = newPart(
		parent,
		Vector3.new(boardSize.X, boardSize.Y, 0.6),
		base * CFrame.new(0, bottomY + boardSize.Y / 2, 0),
		boardColor
	)
	board.CanCollide = true
	return board
end

----------------------------------------------------------------------
-- 지역 정보 + 장식 자리 고르기
----------------------------------------------------------------------

type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
type Circle = { X: number, Z: number, R: number }
type Spot = { x: number, z: number, r: number }
type Ctx = {
	Index: number,
	Def: any,
	Pal: any,
	Folder: Model,
	Deco: Folder,
	Rect: Rect, -- 섬 땅
	Field: Rect, -- 코인 들판 (큰 장식 금지)
	South: Rect, -- 컨베이어 뒤쪽 큰 장식 구역 (지역 2~8)
	Blocks: { Rect }, -- 모든 장식 금지 (길, 컨베이어, 집, 순위표 ...)
	Circles: { Circle },
	Placed: { Spot },
	Exits: { Vector3 }, -- ★v8 이 섬에서 바깥 섬으로 나가는 길 시작점 (Zone.Parent == 이 섬)
}

local function rect(minX: number, maxX: number, minZ: number, maxZ: number): Rect
	return { MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ }
end

local function inRect(r: Rect, x: number, z: number, margin: number): boolean
	return x >= r.MinX - margin and x <= r.MaxX + margin and z >= r.MinZ - margin and z <= r.MaxZ + margin
end

local function zoneRect(def: any): Rect
	local c, s = def.Center, def.Size
	return rect(c.X - s.X / 2, c.X + s.X / 2, c.Z - s.Z / 2, c.Z + s.Z / 2)
end

-- 축 방향 띠 a → b (폭 반 = halfW) 를 사각형으로
local function stripRect(a: Vector3, b: Vector3, halfW: number): Rect
	local d = b - a
	if math.abs(d.X) >= math.abs(d.Z) then
		return rect(math.min(a.X, b.X), math.max(a.X, b.X), math.min(a.Z, b.Z) - halfW, math.max(a.Z, b.Z) + halfW)
	end
	return rect(math.min(a.X, b.X) - halfW, math.max(a.X, b.X) + halfW, math.min(a.Z, b.Z), math.max(a.Z, b.Z))
end

-- 지역 2~8 섬 안 좌표 (Config 의 island 와 같아요): u = 섬 입구에서 안쪽(Trail.Dir)으로, v = 길 중심선에서 Trail.Side 쪽으로
local function localPoint(def: any, u: number, v: number): Vector3
	local t = def.Trail
	return t.To + t.Dir * u + t.Side * v
end

local function localRect(def: any, u0: number, u1: number, v0: number, v1: number): Rect
	local a, b = localPoint(def, u0, v0), localPoint(def, u1, v1)
	return rect(math.min(a.X, b.X), math.max(a.X, b.X), math.min(a.Z, b.Z), math.max(a.Z, b.Z))
end

-- 컨베이어의 v, 시작/끝 u (섬 안 좌표)
local function beltLocal(def: any): (number, number, number)
	local t = def.Trail
	local v = (def.ConveyorStart - t.To):Dot(t.Side)
	local u0 = (def.ConveyorStart - t.To):Dot(t.Dir)
	local u1 = (def.ConveyorEnd - t.To):Dot(t.Dir)
	return v, math.min(u0, u1), math.max(u0, u1)
end

local function rectPart(parent: Instance, r: Rect, top: number, color: Color3, material: Enum.Material?): Part
	return flatRect(parent, r.MinX, r.MaxX, r.MinZ, r.MaxZ, top, color, material)
end

-- 바다 위 배경 장식이 겹치면 안 되는 곳 (숲 마을, 섬, 길). Build 가 맨 처음 채워요
local seaBlocks: { Rect } = {}
local seaPlaced: { Spot } = {} -- 이미 놓은 바다 위 장식 (서로 안 겹치게)

local function seaFree(x: number, z: number, r: number): boolean
	for _, b in seaBlocks do
		if inRect(b, x, z, r) then
			return false
		end
	end
	for _, s in seaPlaced do
		local dx, dz = s.x - x, s.z - z
		if dx * dx + dz * dz < (s.r + r) ^ 2 then
			return false
		end
	end
	return true
end

-- 섬 밖 바다 위 자리: 숲 마을 반대쪽(바깥) 반원에서 섬 가장자리로부터 minDist..maxDist.
-- 다른 섬·길·숲 마을과 r + 6 이상, 이미 놓은 바다 장식과도 안 겹치게. 못 찾으면 그만큼 적게 돌려줘요
local function outerSpots(ctx: Ctx, n: number, minDist: number, maxDist: number, r: number): { Vector3 }
	local c = ctx.Def.Center
	local base = math.atan2(c.Z - HOME_CENTER.Z, c.X - HOME_CENTER.X)
	local hx, hz = ctx.Def.Size.X / 2, ctx.Def.Size.Z / 2
	local list: { Vector3 } = {}
	for _ = 1, n * 30 do
		if #list >= n then
			break
		end
		local a = base + rng:NextNumber(-1.45, 1.45)
		local dx, dz = math.cos(a), math.sin(a)
		local edge = math.min(hx / math.max(math.abs(dx), 1e-3), hz / math.max(math.abs(dz), 1e-3))
		local d = edge + rng:NextNumber(minDist, maxDist)
		local x, z = c.X + dx * d, c.Z + dz * d
		if seaFree(x, z, r + 6) then
			table.insert(seaPlaced, { x = x, z = z, r = r })
			table.insert(list, Vector3.new(x, 0, z))
		end
	end
	return list
end

-- small = true 면 코인 들판 안에도 놓을 수 있어요 (납작하거나 작은 장식만)
local function isFree(ctx: Ctx, x: number, z: number, r: number, small: boolean): boolean
	local island = ctx.Rect
	if x < island.MinX + 5 + r or x > island.MaxX - 5 - r or z < island.MinZ + 5 + r or z > island.MaxZ - 5 - r then
		return false
	end
	if not small and inRect(ctx.Field, x, z, 4 + r) then
		return false
	end
	for _, b in ctx.Blocks do
		if inRect(b, x, z, r) then
			return false
		end
	end
	for _, c in ctx.Circles do
		local dx, dz = x - c.X, z - c.Z
		if dx * dx + dz * dz < (c.R + r) ^ 2 then
			return false
		end
	end
	for _, s in ctx.Placed do
		local dx, dz = s.x - x, s.z - z
		if dx * dx + dz * dz < (s.r + r) ^ 2 then
			return false
		end
	end
	return true
end

local function findSpot(ctx: Ctx, r: number, small: boolean, region: Rect?): Vector3?
	local reg = region or ctx.Rect
	for _ = 1, 50 do
		local x = rng:NextNumber(reg.MinX, reg.MaxX)
		local z = rng:NextNumber(reg.MinZ, reg.MaxZ)
		if isFree(ctx, x, z, r, small) then
			table.insert(ctx.Placed, { x = x, z = z, r = r })
			return Vector3.new(x, 0, z)
		end
	end
	return nil
end

-- count 개를 빈 자리에 흩뿌려요
local function scatter(ctx: Ctx, count: number, r: number, small: boolean, region: Rect?, build: (Instance, Vector3) -> ())
	for _ = 1, count do
		local p = findSpot(ctx, r, small, region)
		if p then
			build(ctx.Deco, p)
		end
	end
end

----------------------------------------------------------------------
-- 장식: 숲 마을 (나무, 꽃, 버섯, 덤불, 구름)
----------------------------------------------------------------------

local function buildTree(parent: Instance, pos: Vector3, crowns: { Color3 }?)
	local m = model("Tree", parent)
	local palette = crowns or CROWN_COLORS
	local kind = rng:NextInteger(1, 3)
	local h = rng:NextNumber(6, 9)
	local trunkColor = if rng:NextNumber() < 0.5 then COLORS.Trunk else COLORS.Cream
	local trunk = column(m, pos, h + 1, rng:NextNumber(0.9, 1.3), trunkColor)
	trunk.CanCollide = true
	local top = pos + Vector3.new(0, h, 0)
	local crown = pick(palette)
	if kind == 1 then
		-- 막대사탕 나무: 큰 공 + 하이라이트
		local d = rng:NextNumber(6, 8)
		ball(m, top + Vector3.new(0, d * 0.35, 0), d, crown)
		ball(m, top + Vector3.new(d * 0.22, d * 0.62, -d * 0.18), d * 0.3, lighten(crown, 0.55))
	elseif kind == 2 then
		-- 솜사탕 나무: 뭉게뭉게 3개
		local d = rng:NextNumber(5, 6.5)
		local c2 = pick(palette)
		blob(m, top + Vector3.new(0, d * 0.45, 0), Vector3.new(d * 1.3, d, d * 1.3), crown)
		blob(m, top + Vector3.new(d * 0.45, d * 0.15, d * 0.2), Vector3.new(d * 0.9, d * 0.75, d * 0.9), c2)
		blob(m, top + Vector3.new(-d * 0.4, d * 0.2, -d * 0.25), Vector3.new(d * 0.85, d * 0.7, d * 0.85), crown:Lerp(c2, 0.5))
	else
		-- 열매 나무: 둥근 잎 + 빨간 열매
		local d = rng:NextNumber(6.5, 8.5)
		local center = top + Vector3.new(0, d * 0.3, 0)
		blob(m, center, Vector3.new(d, d * 0.85, d), pick(BUSH_COLORS))
		for _ = 1, 2 do
			local a = rng:NextNumber(0, math.pi * 2)
			local off = Vector3.new(math.cos(a) * d * 0.47, rng:NextNumber(-0.1, 0.25) * d, math.sin(a) * d * 0.47)
			ball(m, center + off, 0.9, RGB(255, 90, 110))
		end
	end
end

local function buildFlowers(parent: Instance, pos: Vector3)
	local m = model("Flowers", parent)
	for _ = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local rr = rng:NextNumber(0, 1.3)
		local base = pos + Vector3.new(math.cos(a) * rr, 0, math.sin(a) * rr)
		local h = rng:NextNumber(0.8, 1.5)
		column(m, base, h, 0.22, RGB(95, 185, 90))
		ball(m, base + Vector3.new(0, h + 0.3, 0), rng:NextNumber(0.7, 0.95), pick(FLOWER_COLORS))
	end
end

local function buildMushroom(parent: Instance, pos: Vector3)
	local m = model("Mushroom", parent)
	local s = rng:NextNumber(0.8, 1.5)
	local h = 1.3 * s
	column(m, pos, h, 0.8 * s, COLORS.Cream)
	local capPos = pos + Vector3.new(0, h + 0.2 * s, 0)
	blob(m, capPos, Vector3.new(2.4 * s, 1.3 * s, 2.4 * s), pick(CAP_COLORS))
	for i = 1, 3 do
		local a = i * 2.1 + rng:NextNumber(0, 0.5)
		local off = Vector3.new(math.cos(a) * 0.75 * s, 0.4 * s, math.sin(a) * 0.75 * s)
		ball(m, capPos + off, 0.38 * s, COLORS.White)
	end
end

local function buildBush(parent: Instance, pos: Vector3)
	local m = model("Bush", parent)
	local s = rng:NextNumber(1.2, 2)
	local c = pick(BUSH_COLORS)
	local main = blob(m, pos + Vector3.new(0, 0.7 * s, 0), Vector3.new(2.4 * s, 1.8 * s, 2.2 * s), c)
	main.CanCollide = true
	blob(m, pos + Vector3.new(0.9 * s, 0.5 * s, 0.3 * s), Vector3.new(1.6 * s, 1.3 * s, 1.6 * s), lighten(c, 0.12))
	if rng:NextNumber() < 0.6 then
		ball(m, pos + Vector3.new(-0.4 * s, 1.5 * s, -0.5 * s), 0.5, pick(FLOWER_COLORS))
	end
end

local function buildCloud(parent: Instance, pos: Vector3, color: Color3?)
	local m = model("Cloud", parent)
	local s = rng:NextNumber(1, 1.8)
	local n = 4
	for i = 1, n do
		local t = (i - (n + 1) / 2)
		local size = Vector3.new(rng:NextNumber(7, 10), rng:NextNumber(4.5, 6.5), rng:NextNumber(6, 8)) * s
		local p = blob(
			m,
			pos + Vector3.new(t * 4.5 * s, rng:NextNumber(-0.5, 1.5) * s, rng:NextNumber(-1.5, 1.5) * s),
			size,
			color or COLORS.White
		)
		p.CastShadow = false
	end
end

local function buildLamp(parent: Instance, pos: Vector3, color: Color3)
	local m = model("CandyLamp", parent)
	local pole = column(m, pos, 5, 0.5, COLORS.White)
	pole.CanCollide = true
	column(m, pos + Vector3.new(0, 2, 0), 0.6, 0.62, COLORS.Pink)
	local top = ball(m, pos + Vector3.new(0, 5.6, 0), 1.6, color, Enum.Material.Neon)
	top.CastShadow = false
end

-- 바위 (capColor 가 있으면 위에 눈/이끼)
local function buildRock(parent: Instance, pos: Vector3, color: Color3, capColor: Color3?)
	local m = model("Rock", parent)
	local s = rng:NextNumber(1.1, 2.2)
	local r = blob(m, pos + Vector3.new(0, 0.5 * s, 0), Vector3.new(2.6 * s, 1.6 * s, 2.2 * s), color, Enum.Material.Slate)
	r.CanCollide = true
	if capColor then
		blob(m, pos + Vector3.new(0, 1.05 * s, 0), Vector3.new(2.0 * s, 0.7 * s, 1.7 * s), capColor)
	else
		blob(m, pos + Vector3.new(1.5 * s, 0.3 * s, 0.6 * s), Vector3.new(1.3 * s, 0.9 * s, 1.2 * s), lighten(color, 0.1), Enum.Material.Slate)
	end
end

-- 바다 위에 반쯤 잠긴 큰 언덕 (울타리 밖 배경)
local function buildHill(parent: Instance, pos: Vector3, size: Vector3, color: Color3, material: Enum.Material?)
	local hill = blob(parent, Vector3.new(pos.X, SEA_Y, pos.Z), size, color, material)
	hill.Name = "Hill"
	return hill
end

----------------------------------------------------------------------
-- 장식: 호수 (연못, 연잎, 갈대, 바위, 나무)
----------------------------------------------------------------------

local function buildLilyPad(parent: Instance, pos: Vector3)
	local m = model("LilyPad", parent)
	local d = rng:NextNumber(2.6, 3.8)
	disc(m, pos + Vector3.new(0, 0.08, 0), d, 0.16, pick({ RGB(95, 190, 90), RGB(120, 205, 100) }))
	if rng:NextNumber() < 0.6 then
		ball(m, pos + Vector3.new(d * 0.15, 0.35, d * 0.1), 0.75, pick({ RGB(255, 170, 210), RGB(255, 255, 255), RGB(255, 210, 120) }))
	end
end

local function buildDuck(parent: Instance, pos: Vector3)
	local m = model("Duck", parent)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	blobCF(m, base * CFrame.new(0, 0.55, 0), Vector3.new(1.4, 1.1, 1.9), RGB(255, 235, 120))
	ball(m, (base * CFrame.new(0, 1.35, -0.7)).Position, 0.95, RGB(255, 240, 140))
	newPart(m, Vector3.new(0.5, 0.2, 0.5), base * CFrame.new(0, 1.3, -1.25), RGB(255, 150, 60))
end

local function buildPond(parent: Instance, pos: Vector3, pal: any)
	local m = model("Pond", parent)
	local d = rng:NextNumber(11, 15)
	disc(m, pos + Vector3.new(0, 0.08, 0), d + 2.6, 0.16, pal.Path)
	local water = disc(m, pos + Vector3.new(0, 0.2, 0), d, 0.2, pal.Water or COLORS.Sky, Enum.Material.Glass)
	water.Transparency = 0.1
	water.Reflectance = 0.15
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local rock = blob(
			m,
			pos + Vector3.new(math.cos(a) * (d / 2 + 0.7), 0.4, math.sin(a) * (d / 2 + 0.7)),
			Vector3.new(2.2, 1.3, 1.8),
			COLORS.Rock,
			Enum.Material.Slate
		)
		rock.CanCollide = true
	end
	for _ = 1, 2 do
		local a = rng:NextNumber(0, math.pi * 2)
		local rr = rng:NextNumber(1, d / 2 - 2)
		buildLilyPad(m, pos + Vector3.new(math.cos(a) * rr, 0.22, math.sin(a) * rr))
	end
	buildDuck(m, pos + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.2, rng:NextNumber(-1.5, 1.5)))
end

local function buildReeds(parent: Instance, pos: Vector3)
	local m = model("Reeds", parent)
	for _ = 1, 3 do
		local off = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		local h = rng:NextNumber(3, 5)
		column(m, pos + off, h, 0.25, RGB(110, 180, 90))
		blob(m, pos + off + Vector3.new(0, h + 0.4, 0), Vector3.new(0.55, 1.4, 0.55), RGB(150, 100, 65))
	end
end

----------------------------------------------------------------------
-- 장식: 정글 / 바다 (야자수, 큰 잎, 덩굴 나무, 열대 꽃, 산호, 파라솔, 불가사리, 조개)
----------------------------------------------------------------------

local function buildPalm(parent: Instance, pos: Vector3, scale: number?)
	local m = model("PalmTree", parent)
	local s = scale or rng:NextNumber(0.9, 1.25)
	local lean = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.cos(lean), 0, math.sin(lean))
	local p = pos
	for i = 1, 4 do
		local q = p + Vector3.new(0, 2.5 * s, 0) + dir * (0.35 * i * s)
		local seg = stick(m, p, q, (1.35 - i * 0.12) * s, if i % 2 == 0 then RGB(190, 140, 90) else RGB(205, 160, 110))
		if i == 1 then
			seg.CanCollide = true
		end
		p = q
	end
	-- 잎 5장 (축 늘어진 타원)
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local tip = p + out * 5 * s + Vector3.new(0, -1.5 * s, 0)
		local mid = (p + tip) / 2 + Vector3.new(0, 0.5 * s, 0)
		blobCF(m, CFrame.lookAt(mid, tip), Vector3.new(1.9 * s, 0.3, (tip - p).Magnitude + 0.6), if i % 2 == 0 then COLORS.Leaf else COLORS.DarkLeaf)
	end
	for i = 1, 2 do
		local a = lean + i * 2.4
		ball(m, p + Vector3.new(math.cos(a) * 0.6 * s, -0.5 * s, math.sin(a) * 0.6 * s), 0.9 * s, RGB(140, 95, 55))
	end
end

local function buildBigLeaf(parent: Instance, pos: Vector3)
	local m = model("BigLeaf", parent)
	local n = 4
	local base = pos + Vector3.new(0, 0.3, 0)
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local len = rng:NextNumber(3.5, 5.5)
		local tip = base + out * len + Vector3.new(0, rng:NextNumber(2, 3.5), 0)
		blobCF(m, CFrame.lookAt((base + tip) / 2, tip), Vector3.new(len * 0.5, 0.25, (tip - base).Magnitude), if i % 2 == 0 then COLORS.Leaf else RGB(80, 175, 85))
	end
	ball(m, pos + Vector3.new(0, 0.6, 0), 1.2, COLORS.DarkLeaf)
end

local function buildVineTree(parent: Instance, pos: Vector3)
	local m = model("VineTree", parent)
	local h = rng:NextNumber(9, 12)
	local trunk = column(m, pos, h, 1.8, COLORS.Bark)
	trunk.CanCollide = true
	local top = pos + Vector3.new(0, h, 0)
	blob(m, top + Vector3.new(0, 1.2, 0), Vector3.new(11, 5, 10), COLORS.DarkLeaf)
	blob(m, top + Vector3.new(1.5, 3, -1), Vector3.new(7, 4, 7), COLORS.Leaf)
	-- 늘어진 덩굴 3개 + 잎 방울
	for i = 1, 3 do
		local a = i * 2.1 + rng:NextNumber(0, 0.6)
		local hang = top + Vector3.new(math.cos(a) * 4, 0, math.sin(a) * 3.6)
		local len = rng:NextNumber(4, 7)
		column(m, hang - Vector3.new(0, len, 0), len, 0.22, RGB(90, 160, 70))
		ball(m, hang - Vector3.new(0, len, 0), 0.7, RGB(255, 120, 150))
	end
end

local function buildTropicalFlower(parent: Instance, pos: Vector3)
	local m = model("TropicalFlower", parent)
	local h = rng:NextNumber(0.9, 1.4)
	column(m, pos, h, 0.25, RGB(90, 170, 80))
	local c = pick({ RGB(255, 110, 140), RGB(255, 170, 60), RGB(255, 90, 200), RGB(255, 220, 80) })
	blob(m, pos + Vector3.new(0, h + 0.15, 0), Vector3.new(2, 0.45, 2), c)
	ball(m, pos + Vector3.new(0, h + 0.4, 0), 0.55, RGB(255, 240, 120))
end

local function buildCoral(parent: Instance, pos: Vector3)
	local m = model("Coral", parent)
	local c = pick({ RGB(255, 120, 150), RGB(255, 170, 90), RGB(190, 120, 255), RGB(255, 95, 125) })
	for _ = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local tilt = rng:NextNumber(0.15, 0.5)
		local h = rng:NextNumber(2, 4)
		local top = pos + Vector3.new(math.cos(a) * math.sin(tilt) * h, math.cos(tilt) * h, math.sin(a) * math.sin(tilt) * h)
		stick(m, pos, top, 0.6, c)
		ball(m, top, 0.85, lighten(c, 0.3))
	end
end

local function buildUmbrella(parent: Instance, pos: Vector3, pal: any)
	local m = model("Umbrella", parent)
	local pole = column(m, pos, 6.5, 0.35, COLORS.White)
	pole.CanCollide = true
	disc(m, pos + Vector3.new(0, 6.3, 0), 8, 0.35, pal.Accent)
	disc(m, pos + Vector3.new(0, 6.65, 0), 5, 0.35, COLORS.White)
	ball(m, pos + Vector3.new(0, 7, 0), 0.6, pal.Trim)
	local yaw = rng:NextNumber(0, math.pi * 2)
	newPart(m, Vector3.new(2.6, 0.1, 5), CFrame.new(pos + Vector3.new(2.6, 0.05, 0)) * CFrame.Angles(0, yaw, 0), pick(FLOWER_COLORS))
end

local function buildStarfish(parent: Instance, pos: Vector3)
	local m = model("Starfish", parent)
	local c = pick({ RGB(255, 140, 110), RGB(255, 180, 80), RGB(255, 120, 170), RGB(255, 215, 90) })
	local yaw = rng:NextNumber(0, math.pi * 2)
	for i = 0, 4 do
		local cf = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, yaw + i * math.pi * 2 / 5, 0) * CFrame.new(0, 0, -0.55)
		blobCF(m, cf, Vector3.new(0.55, 0.3, 1.3), c)
	end
end

local function buildShell(parent: Instance, pos: Vector3)
	local m = model("Shell", parent)
	local c = pick({ RGB(255, 200, 210), RGB(255, 230, 200), RGB(240, 210, 255) })
	blob(m, pos + Vector3.new(0, 0.3, 0), Vector3.new(1.4, 0.7, 1.2), c)
	ball(m, pos + Vector3.new(0.55, 0.15, 0.4), 0.45, lighten(c, 0.4))
end

local function buildLighthouse(parent: Instance, pos: Vector3)
	local m = model("Lighthouse", parent)
	blob(m, Vector3.new(pos.X, SEA_Y, pos.Z), Vector3.new(16, 6, 14), COLORS.Rock, Enum.Material.Slate)
	local y = SEA_Y + 1.5
	for i = 1, 4 do
		column(m, Vector3.new(pos.X, y, pos.Z), 3, 3.6 - i * 0.3, if i % 2 == 1 then RGB(255, 100, 110) else COLORS.White)
		y += 3
	end
	local lamp = ball(m, Vector3.new(pos.X, y + 0.9, pos.Z), 2.2, RGB(255, 240, 150), Enum.Material.Neon)
	lamp.CastShadow = false
	ball(m, Vector3.new(pos.X, y + 2.4, pos.Z), 2.4, RGB(255, 100, 110))
end

----------------------------------------------------------------------
-- 장식: 겨울 산 (뾰족 나무, 눈 더미, 얼음 수정, 눈사람, 큰 산)
----------------------------------------------------------------------

local function buildPine(parent: Instance, pos: Vector3, scale: number?)
	local m = model("PineTree", parent)
	local s = scale or rng:NextNumber(0.9, 1.4)
	local trunk = column(m, pos, 2.2 * s, 0.9 * s, COLORS.Bark)
	trunk.CanCollide = true
	local y = 1.6 * s
	for i = 1, 3 do
		local w = (6.4 - i * 1.5) * s
		local h = 2.6 * s
		blob(m, pos + Vector3.new(0, y + h * 0.4, 0), Vector3.new(w, h, w), RGB(55, 135, 95))
		blob(m, pos + Vector3.new(0, y + h * 0.78, 0), Vector3.new(w * 0.68, h * 0.32, w * 0.68), RGB(250, 252, 255))
		y += h * 0.7
	end
end

local function buildSnowPile(parent: Instance, pos: Vector3)
	local m = model("SnowPile", parent)
	local s = rng:NextNumber(0.8, 1.6)
	blob(m, pos + Vector3.new(0, 0.3 * s, 0), Vector3.new(3 * s, 1.2 * s, 2.6 * s), RGB(250, 252, 255), Enum.Material.Snow)
	blob(m, pos + Vector3.new(0.9 * s, 0.2 * s, 0.5 * s), Vector3.new(1.6 * s, 0.9 * s, 1.5 * s), RGB(240, 247, 255), Enum.Material.Snow)
end

local function buildIceCrystal(parent: Instance, pos: Vector3, scale: number?)
	local m = model("IceCrystal", parent)
	local s = scale or 1
	for i = 1, 3 do
		local h = rng:NextNumber(2.5, 5.5) * s
		local tilt = CFrame.Angles(rng:NextNumber(-0.35, 0.35), i * 1.3, rng:NextNumber(-0.35, 0.35))
		local p = newPart(
			m,
			Vector3.new(0.9 * s, h, 0.9 * s),
			CFrame.new(pos + Vector3.new(rng:NextNumber(-0.6, 0.6), h / 2 - 0.3, rng:NextNumber(-0.6, 0.6))) * tilt,
			pick({ RGB(150, 215, 255), RGB(190, 235, 255), RGB(130, 200, 255) }),
			nil,
			Enum.Material.Glass
		)
		p.Transparency = 0.25
		p.Reflectance = 0.3
	end
end

local function buildSnowman(parent: Instance, pos: Vector3)
	local m = model("Snowman", parent)
	local s = rng:NextNumber(0.9, 1.3)
	local white = RGB(250, 252, 255)
	local body = ball(m, pos + Vector3.new(0, 1.3 * s, 0), 2.8 * s, white, Enum.Material.Snow)
	body.CanCollide = true
	ball(m, pos + Vector3.new(0, 3.3 * s, 0), 2.1 * s, white, Enum.Material.Snow)
	local headPos = pos + Vector3.new(0, 4.85 * s, 0)
	ball(m, headPos, 1.6 * s, white, Enum.Material.Snow)
	local look = CFrame.new(headPos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	for _, sx in { -1, 1 } do
		ball(m, (look * CFrame.new(sx * 0.3 * s, 0.2 * s, -0.72 * s)).Position, 0.22 * s, COLORS.Black)
	end
	-- 당근 코 (원기둥 축을 앞쪽으로)
	newPart(m, Vector3.new(0.75 * s, 0.25 * s, 0.25 * s), look * CFrame.new(0, 0, -1.0 * s) * CFrame.Angles(0, math.pi / 2, 0), RGB(255, 150, 60), Enum.PartType.Cylinder)
	-- 모자 + 목도리
	disc(m, headPos + Vector3.new(0, 0.7 * s, 0), 1.8 * s, 0.2 * s, COLORS.Black)
	column(m, headPos + Vector3.new(0, 0.75 * s, 0), 1.1 * s, 1.1 * s, COLORS.Black)
	disc(m, pos + Vector3.new(0, 4.15 * s, 0), 1.75 * s, 0.4 * s, RGB(255, 90, 110))
end

local function buildMountain(parent: Instance, pos: Vector3, w: number, h: number)
	local m = model("Mountain", parent)
	blob(m, Vector3.new(pos.X, SEA_Y, pos.Z), Vector3.new(w, h * 2, w * 0.85), RGB(195, 212, 235), Enum.Material.Snow)
	blob(m, Vector3.new(pos.X, SEA_Y + h * 0.78, pos.Z), Vector3.new(w * 0.45, h * 0.5, w * 0.4), RGB(250, 252, 255), Enum.Material.Snow)
end

----------------------------------------------------------------------
-- 장식: 캔디 랜드 (막대사탕, 지팡이 사탕, 컵케이크, 젤리, 도넛)
----------------------------------------------------------------------

local function buildLollipop(parent: Instance, pos: Vector3, scale: number?)
	local m = model("Lollipop", parent)
	local s = scale or rng:NextNumber(0.9, 1.3)
	local h = 5 * s
	local stickPart = column(m, pos, h, 0.45 * s, COLORS.White)
	stickPart.CanCollide = true
	local cf = CFrame.new(pos + Vector3.new(0, h + 1.6 * s, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local c1, c2 = pick(CANDY_COLORS), pick(CANDY_COLORS)
	-- 세운 원판 3겹 (원기둥 축 X → 판 면이 옆을 봐요)
	newPart(m, Vector3.new(0.6 * s, 3.6 * s, 3.6 * s), cf, c1, Enum.PartType.Cylinder)
	newPart(m, Vector3.new(0.7 * s, 2.4 * s, 2.4 * s), cf, COLORS.White, Enum.PartType.Cylinder)
	newPart(m, Vector3.new(0.8 * s, 1.2 * s, 1.2 * s), cf, c2, Enum.PartType.Cylinder)
end

local function buildCandyCane(parent: Instance, pos: Vector3)
	local m = model("CandyCane", parent)
	local s = rng:NextNumber(0.9, 1.3)
	local segH = 1.25 * s
	local red = RGB(255, 80, 100)
	for i = 0, 3 do
		local p = column(m, pos + Vector3.new(0, i * segH, 0), segH, 0.8 * s, if i % 2 == 0 then red else COLORS.White)
		if i == 0 then
			p.CanCollide = true
		end
	end
	-- 손잡이 고리: 공 3개로 둥글게
	local top = pos + Vector3.new(0, 4 * segH, 0)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	local hookR = 0.9 * s
	for k = 1, 3 do
		local a = k / 3 * math.pi
		local p = top + dir * (hookR - math.cos(a) * hookR) + Vector3.new(0, math.sin(a) * hookR, 0)
		ball(m, p, 0.85 * s, if k % 2 == 1 then COLORS.White else red)
	end
end

local function buildCupcake(parent: Instance, pos: Vector3, pal: any)
	local m = model("Cupcake", parent)
	local s = rng:NextNumber(0.9, 1.3)
	local cup = column(m, pos, 1.6 * s, 2.6 * s, pal.Trim)
	cup.CanCollide = true
	local frost = pick({ COLORS.White, RGB(255, 200, 225), pal.Accent })
	blob(m, pos + Vector3.new(0, 2.1 * s, 0), Vector3.new(3 * s, 1.6 * s, 3 * s), frost)
	blob(m, pos + Vector3.new(0, 2.9 * s, 0), Vector3.new(1.8 * s, 1.1 * s, 1.8 * s), lighten(frost, 0.3))
	ball(m, pos + Vector3.new(0, 3.6 * s, 0), 0.8 * s, RGB(255, 60, 90))
end

local function buildGumDrop(parent: Instance, pos: Vector3)
	local m = model("GumDrop", parent)
	local p = blob(m, pos + Vector3.new(0, 0.5, 0), Vector3.new(1.7, 1.3, 1.7), pick(CANDY_COLORS))
	p.Reflectance = 0.15
end

local function buildDonut(parent: Instance, pos: Vector3, pal: any)
	local m = model("Donut", parent)
	local s = rng:NextNumber(1, 1.5)
	local dough = disc(m, pos + Vector3.new(0, 0.55 * s, 0), 4.4 * s, 1.1 * s, RGB(220, 165, 100))
	dough.CanCollide = true
	disc(m, pos + Vector3.new(0, 1.2 * s, 0), 3.9 * s, 0.3 * s, pick({ RGB(255, 150, 200), RGB(140, 90, 60), RGB(150, 220, 255) }))
	disc(m, pos + Vector3.new(0, 0.7 * s, 0), 1.4 * s, 1.5 * s, pal.Ground)
	for i = 1, 3 do
		local a = i * 2.1
		newPart(
			m,
			Vector3.new(0.6 * s, 0.15, 0.2 * s),
			CFrame.new(pos + Vector3.new(math.cos(a) * 1.4 * s, 1.4 * s, math.sin(a) * 1.4 * s)) * CFrame.Angles(0, a * 1.7, 0),
			pick(CANDY_COLORS)
		)
	end
end

----------------------------------------------------------------------
-- 장식: 구름 왕국 (구름 덩어리, 무지개, 기둥, 성, 별)
----------------------------------------------------------------------

local function buildCloudPuff(parent: Instance, pos: Vector3, scale: number?)
	local m = model("CloudPuff", parent)
	local s = scale or rng:NextNumber(1, 1.6)
	local main = blob(m, pos + Vector3.new(0, 1.2 * s, 0), Vector3.new(5 * s, 3 * s, 4.5 * s), COLORS.White)
	main.CanCollide = true
	blob(m, pos + Vector3.new(2.2 * s, 0.9 * s, 0.6 * s), Vector3.new(3.5 * s, 2.4 * s, 3.2 * s), RGB(248, 246, 255))
	blob(m, pos + Vector3.new(-2 * s, 0.8 * s, -0.5 * s), Vector3.new(3.2 * s, 2.2 * s, 3 * s), RGB(240, 238, 255))
end

-- 무지개 아치 (center = 땅 가운데, across = 아치가 걸쳐지는 방향)
local function buildRainbowArc(parent: Instance, center: Vector3, radius: number, across: Vector3, bands: number, segs: number)
	local m = model("Rainbow", parent)
	local bandW = 1.25
	local a0, a1 = -0.05, math.pi + 0.05
	local da = (a1 - a0) / segs
	local side = across.Unit
	local normal = side:Cross(Vector3.yAxis)
	for b = 1, bands do
		local color = RAINBOW_COLORS[(b - 1) % #RAINBOW_COLORS + 1]
		local r = radius - (b - 0.5) * bandW
		for k = 0, segs - 1 do
			local am = a0 + (k + 0.5) * da
			local radial = Vector3.yAxis * math.sin(am) + side * math.cos(am)
			local pos = center + radial * r
			local len = 2 * r * math.sin(da / 2) + 0.35
			local p = newPart(m, Vector3.new(1.6, bandW, len), CFrame.fromMatrix(pos, normal, radial), color)
			p.CastShadow = false
		end
	end
	-- 무지개 끝 구름
	for _, sgn in { 1, -1 } do
		local foot = center + side * sgn * (radius - bandW * bands / 2) + Vector3.new(0, 0.8, 0)
		blob(m, foot, Vector3.new(6, 3.4, 7), COLORS.White)
	end
end

local function buildPillar(parent: Instance, pos: Vector3)
	local m = model("Pillar", parent)
	local h = rng:NextNumber(6, 9)
	disc(m, pos + Vector3.new(0, 0.3, 0), 2.8, 0.6, COLORS.Gold)
	local shaft = column(m, pos, h, 1.9, RGB(250, 248, 255), Enum.Material.Marble)
	shaft.CanCollide = true
	ball(m, pos + Vector3.new(0, h + 0.6, 0), 1.6, COLORS.Gold)
end

local function buildCastle(parent: Instance, pos: Vector3, scale: number?)
	local m = model("Castle", parent)
	local s = scale or 1
	local white = RGB(250, 248, 255)
	local roof = RGB(200, 170, 255)
	local base = newPart(m, Vector3.new(10, 6, 8) * s, CFrame.new(pos + Vector3.new(0, 3 * s, 0)), white, nil, Enum.Material.Marble)
	base.CanCollide = true
	newPart(m, Vector3.new(2.6 * s, 3.6 * s, 0.4), CFrame.new(pos + Vector3.new(0, 1.8 * s, -4 * s)), RGB(170, 140, 230))
	for _, off in { Vector3.new(-5, 0, -4), Vector3.new(5, 0, -4), Vector3.new(-5, 0, 4), Vector3.new(5, 0, 4) } do
		local tp = pos + off * s
		local h = (if off.Z < 0 then 9 else 11) * s
		local tower = column(m, tp, h, 2.8 * s, white, Enum.Material.Marble)
		tower.CanCollide = true
		blob(m, tp + Vector3.new(0, h + 1.1 * s, 0), Vector3.new(3.2, 3.4, 3.2) * s, roof)
	end
end

local function buildStar(parent: Instance, pos: Vector3, size: number, color: Color3?)
	local m = model("Star", parent)
	local c = color or COLORS.Gold
	local core = ball(m, pos, size * 0.55, c, Enum.Material.Neon)
	core.CastShadow = false
	local spin = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	local a = newPart(m, Vector3.new(size * 0.18, size, size * 0.18), spin, c, nil, Enum.Material.Neon)
	local b = newPart(m, Vector3.new(size, size * 0.18, size * 0.18), spin, c, nil, Enum.Material.Neon)
	a.CastShadow = false
	b.CastShadow = false
end

----------------------------------------------------------------------
-- 장식: 우주 (크레이터, 행성, 수정, 로켓)
----------------------------------------------------------------------

local function buildCrater(parent: Instance, pos: Vector3, pal: any)
	local m = model("Crater", parent)
	local d = rng:NextNumber(5, 9)
	disc(m, pos + Vector3.new(0, 0.13, 0), d, 0.26, darken(pal.Ground, 0.15), Enum.Material.Slate)
	disc(m, pos + Vector3.new(0, 0.1, 0), d * 0.65, 0.22, darken(pal.Ground, 0.35), Enum.Material.Slate)
end

local function buildPlanet(parent: Instance, pos: Vector3, d: number, ringed: boolean)
	local m = model("Planet", parent)
	local c = pick({ RGB(255, 170, 120), RGB(150, 200, 255), RGB(200, 150, 255), RGB(255, 210, 110), RGB(130, 230, 190) })
	local body = ball(m, pos, d, c)
	body.CastShadow = false
	if ringed then
		local ring = newPart(
			m,
			Vector3.new(0.2, d * 1.8, d * 1.8),
			CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, math.pi / 2 + rng:NextNumber(-0.4, 0.4)),
			lighten(c, 0.4),
			Enum.PartType.Cylinder,
			Enum.Material.Glass
		)
		ring.Transparency = 0.35
		ring.CastShadow = false
	end
end

local function buildSpaceCrystal(parent: Instance, pos: Vector3, pal: any)
	local m = model("SpaceCrystal", parent)
	for i = 1, 3 do
		local h = rng:NextNumber(2, 4.5)
		local p = newPart(
			m,
			Vector3.new(0.8, h, 0.8),
			CFrame.new(pos + Vector3.new(rng:NextNumber(-0.5, 0.5), h / 2 - 0.3, rng:NextNumber(-0.5, 0.5)))
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), i * 1.1, rng:NextNumber(-0.4, 0.4)),
			pick({ pal.Accent, RGB(220, 140, 255), RGB(255, 150, 220) }),
			nil,
			Enum.Material.Neon
		)
		p.CastShadow = false
	end
end

local function buildRocket(parent: Instance, pos: Vector3, scale: number?)
	local m = model("Rocket", parent)
	local s = scale or 1
	local body = column(m, pos + Vector3.new(0, 0.6 * s, 0), 6.5 * s, 2.4 * s, RGB(245, 245, 255))
	body.CanCollide = true
	column(m, pos + Vector3.new(0, 4.2 * s, 0), 0.7 * s, 2.5 * s, RGB(255, 110, 130))
	blob(m, pos + Vector3.new(0, 7.4 * s, 0), Vector3.new(2.4, 3.2, 2.4) * s, RGB(255, 100, 120))
	local yaw = rng:NextNumber(0, math.pi * 2)
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	ball(m, (base * CFrame.new(0, 5.2 * s, -1.1 * s)).Position, 1.1 * s, RGB(120, 220, 255), Enum.Material.Neon)
	for i = 0, 2 do
		local fin = base * CFrame.Angles(0, i * math.pi * 2 / 3, 0) * CFrame.new(0, 1.3 * s, 1.5 * s)
		newPart(m, Vector3.new(0.3 * s, 2.4 * s, 1.6 * s), fin, RGB(255, 110, 130))
	end
end

----------------------------------------------------------------------
-- 섬 / 울타리 / 길 / 다리 / 문
----------------------------------------------------------------------

-- 울타리 한 줄 a → b (기둥 + 난간 2줄 + 투명 벽)
local function fenceLine(parent: Instance, a: Vector3, b: Vector3, postColor: Color3, capColor: Color3, railColor: Color3, postEvery: number)
	local len = (b - a).Magnitude
	if len < 1 then
		return
	end
	local dir = (b - a).Unit
	local n = math.max(1, math.floor(len / postEvery + 0.5))
	for k = 0, n do
		local pos = a + dir * (len * k / n)
		local post = column(parent, pos, FENCE_H, 0.9, postColor)
		post.CanCollide = true
		if k % 2 == 0 then
			ball(parent, pos + Vector3.new(0, FENCE_H + 0.4, 0), 1.3, capColor)
		end
	end
	local mid = (a + b) / 2
	for _, y in { 1.6, 3.9 } do
		local rail = newPart(parent, Vector3.new(0.45, 0.55, len), CFrame.lookAt(mid + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0)), railColor)
		rail.CanCollide = true
	end
	local wall = newPart(
		parent,
		Vector3.new(1, WALL_H, len),
		CFrame.lookAt(mid + Vector3.new(0, WALL_H / 2, 0), b + Vector3.new(0, WALL_H / 2, 0)),
		COLORS.White
	)
	wall.Name = "InvisibleWall"
	wall.Transparency = 1
	wall.CanCollide = true
	wall.CastShadow = false
end

-- 섬 둘레 울타리. gaps = 길이 닿는 점들 (그 점이 있는 변에서 길 폭만큼 비워요)
local function buildIslandFence(ctx: Ctx, gaps: { Vector3 })
	local f = folder("Fence", ctx.Folder)
	local r = ctx.Rect
	local pal = ctx.Pal
	local every = 30
	local rail = lighten(pal.Trim, 0.35)
	local function line(x0: number, z0: number, x1: number, z1: number)
		fenceLine(f, Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z1), pal.Trim, pal.Accent, rail, every)
	end
	-- 변 하나: 고정 좌표(fixed)와 따라가는 축(along: "X" | "Z"), lo..hi
	local function side(along: string, fixed: number, lo: number, hi: number)
		local cuts: { number } = {}
		for _, g in gaps do
			local onSide = if along == "X" then math.abs(g.Z - fixed) < 1 else math.abs(g.X - fixed) < 1
			local t = if along == "X" then g.X else g.Z
			if onSide and t > lo and t < hi then
				table.insert(cuts, t)
			end
		end
		table.sort(cuts)
		local from = lo
		local function seg(a: number, b: number)
			if b - a < 1 then
				return
			end
			if along == "X" then
				line(a, fixed, b, fixed)
			else
				line(fixed, a, fixed, b)
			end
		end
		for _, t in cuts do
			seg(from, t - HALF_TRAIL)
			from = t + HALF_TRAIL
		end
		seg(from, hi)
	end
	side("X", r.MaxZ, r.MinX, r.MaxX)
	side("X", r.MinZ, r.MinX, r.MaxX)
	side("Z", r.MinX, r.MinZ, r.MaxZ)
	side("Z", r.MaxX, r.MinZ, r.MaxZ)
end

-- 섬 땅 + 절벽
local function buildIsland(ctx: Ctx)
	local def, pal = ctx.Def, ctx.Pal
	local size, center = def.Size, def.Center
	local ground = newPart(
		ctx.Folder,
		Vector3.new(size.X, size.Y, size.Z),
		CFrame.new(center.X, -size.Y / 2, center.Z),
		pal.Ground,
		nil,
		GROUND_MATERIAL[def.Id] or Enum.Material.Grass
	)
	ground.Name = "Ground"
	ground.CanCollide = true
	local cliff = newPart(
		ctx.Folder,
		Vector3.new(size.X + 3, 10, size.Z + 3),
		CFrame.new(center.X, -5.8, center.Z), -- 윗면 -0.8: 물 위로 살짝 보이는 섬 테두리
		CLIFF_COLOR[def.Id] or COLORS.Trunk,
		nil,
		if def.Id == "Snow" then Enum.Material.Ice else Enum.Material.Slate
	)
	cliff.Name = "Cliff"
end

-- 다리 (숲 마을 가장자리 Trail.From → 섬 입구 Trail.To)
local function buildTrail(parent: Instance, k: number)
	local def = Zones[k]
	local t = def.Trail
	local pal = def.Palette
	local from, to, dir, side = t.From, t.To, t.Dir, t.Side
	local m = model("Trail" .. k, parent)
	local deck = rectPart(m, stripRect(from - dir, to + dir, HALF_TRAIL), 0.16, lighten(pal.Trim, 0.25), Enum.Material.WoodPlanks)
	deck.Name = "Deck"
	-- 물속 다리 기둥
	local mid = (from + to) / 2
	for _, sz in { -1, 1 } do
		column(m, mid + side * (sz * (HALF_TRAIL - 2)) + Vector3.new(0, SEA_Y - 8, 0), 8, 2.4, darken(pal.Trim, 0.15))
	end
	-- 양옆 난간 (높이 ≥ 4) + 투명 벽. 숲 마을 울타리와 섬 울타리에 딱 붙어요
	for _, sz in { -1, 1 } do
		local off = side * (sz * (HALF_TRAIL + 0.5))
		fenceLine(m, from + off, to + off, pal.Trim, pal.Accent, COLORS.White, 15)
	end
end

-- 지역 문 (숲 마을 쪽 길 입구): 아치 + 큰 간판 + 막는 판 (Gates/Gate<k>)
local function buildGate(arches: Instance, gates: Instance, k: number)
	local def = Zones[k]
	local gateDef = def.Gate
	if not gateDef then
		return
	end
	local pal = def.Palette
	local t = def.Trail
	local dir, side = t.Dir, t.Side
	local base = gateDef.CFrame.Position
	local g0 = Vector3.new(base.X, 0, base.Z)
	local pillarOff = gateDef.Size.X / 2 + 1.6
	local m = model("Arch" .. k, arches)
	local ringH = 4
	local rings = math.ceil(ARCH_BEAM_Y / ringH)
	for _, sz in { -1, 1 } do
		local p = g0 + side * (sz * pillarOff)
		-- 물속까지 내려가는 받침 (기둥이 떠 보이지 않게)
		column(m, p + Vector3.new(0, SEA_Y - 2, 0), 2 - SEA_Y, 3.4, darken(pal.Trim, 0.1))
		for i = 0, rings - 1 do
			local ring = column(m, p + Vector3.new(0, i * ringH, 0), ringH, 2.6, if i % 2 == 0 then pal.Accent else COLORS.White)
			ring.CanCollide = true
		end
		ball(m, p + Vector3.new(0, rings * ringH + 2.6 + 3.2, 0), 2.6, pal.Trim)
	end
	local beamY = rings * ringH
	local beamPos = g0 + Vector3.new(0, beamY + 1, 0)
	local beam = newPart(m, Vector3.new(2.6, 2, pillarOff * 2 + 3), CFrame.lookAt(beamPos, beamPos + side), pal.Trim)
	beam.CanCollide = true
	-- 큰 간판: 앞면은 숲 마을 쪽(집에서 보여요), 뒷면은 섬 쪽
	local signPos = g0 + Vector3.new(0, beamY + 2 + 3.6, 0)
	local sign = newPart(m, Vector3.new(26, 7, 0.8), CFrame.lookAt(signPos, signPos - dir), pal.Accent)
	sign.Name = "ZoneSign"
	local stroke = darken(pal.Accent, 0.25)
	local front = signFrame(sign, Enum.NormalId.Front, 30, COLORS.Cream, stroke)
	textLabel(front, def.Emoji .. " " .. def.Name, UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.92, 0.58), stroke)
	textLabel(front, "🔄 환생 " .. def.MinRebirth .. "회", UDim2.fromScale(0.1, 0.66), UDim2.fromScale(0.8, 0.28), COLORS.Text)
	local home = Zones[def.Parent or 1] -- ★v8 길이 시작하는 땅
	local back = signFrame(sign, Enum.NormalId.Back, 30, COLORS.Cream, stroke)
	textLabel(back, def.Emoji .. " " .. def.Name, UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.92, 0.58), stroke)
	textLabel(back, "← " .. home.Emoji .. " " .. home.Name, UDim2.fromScale(0.1, 0.66), UDim2.fromScale(0.8, 0.28), COLORS.Text)

	-- 막는 판: 서버에서는 안 막아요 (환생 모자란 사람만 ZoneClient 가 로컬로 막아요)
	local gate = Instance.new("Part")
	gate.Name = "Gate" .. k
	gate.Anchored = true
	gate.CanCollide = false
	gate.CanTouch = false
	gate.CanQuery = false
	gate.CastShadow = false
	gate.Transparency = 1
	gate.Material = Enum.Material.ForceField
	gate.Color = RGB(255, 120, 200)
	gate.Size = gateDef.Size
	gate.CFrame = gateDef.CFrame
	gate:SetAttribute("ZoneIndex", k)
	gate:SetAttribute("MinRebirth", def.MinRebirth)
	local bb = Instance.new("BillboardGui")
	bb.Name = "LockInfo"
	bb.Size = UDim2.new(14, 0, 3.2, 0)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
	bb.MaxDistance = 450 -- 숲 마을 어디서든 잠긴 문이 보여요
	bb.LightInfluence = 0
	bb.Parent = gate
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = FONT
	label.TextScaled = true
	label.Text = "🔒 환생 " .. def.MinRebirth .. "회"
	label.TextColor3 = COLORS.White
	label.TextStrokeColor3 = RGB(200, 60, 140)
	label.TextStrokeTransparency = 0
	label.Parent = bb
	gate.Parent = gates
	partCount += 1
end

-- 바다 (CanCollide 끔: 떨어지면 ZoneService 가 스폰으로 돌려보내요). 숲 마을 + 섬 7개를 모두 덮는 물 한 장,
-- 구름 왕국 둘레는 구름 바다, 우주 둘레는 별이 반짝이는 우주 (물보다 살짝 위, 높이가 달라서 겹쳐도 안 깜빡여요)
local function buildSea(world: Instance)
	local f = folder("Sea", world)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, def in Zones do
		local r = zoneRect(def)
		minX, maxX = math.min(minX, r.MinX), math.max(maxX, r.MaxX)
		minZ, maxZ = math.min(minZ, r.MinZ), math.max(maxZ, r.MaxZ)
	end
	local pad = 170
	local function plane(r: Rect, top: number, color: Color3, transparency: number, material: Enum.Material?): Part
		local p = newPart(f, Vector3.new(r.MaxX - r.MinX, 1, r.MaxZ - r.MinZ), CFrame.new((r.MinX + r.MaxX) / 2, top - 0.5, (r.MinZ + r.MaxZ) / 2), color, nil, material)
		p.Transparency = transparency
		p.CastShadow = false
		return p
	end
	local all = rect(minX - pad, maxX + pad, minZ - pad, maxZ + pad)
	local water = plane(all, SEA_Y, Zones[2].Palette.Water or RGB(90, 180, 235), 0.2)
	water.Name = "Water"
	water.Reflectance = 0.12
	plane(all, SEA_Y - 9, RGB(45, 120, 185), 0).Name = "SeaBed"
	local margin = 14
	for _, def in Zones do
		local r = zoneRect(def)
		local around = rect(r.MinX - margin, r.MaxX + margin, r.MinZ - margin, r.MaxZ + margin)
		if def.Id == "Cloud" then
			plane(around, SEA_Y + 0.3, RGB(250, 248, 255), 0.05).Name = "CloudSea"
		elseif def.Id == "Space" then
			local void = plane(around, SEA_Y + 0.6, RGB(18, 14, 45), 0)
			void.Name = "SpaceVoid"
			emitter(void, {
				Rate = 12,
				Lifetime = NumberRange.new(2, 4),
				Speed = NumberRange.new(0, 0),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1.2), NumberSequenceKeypoint.new(1, 0) }),
				Color = ColorSequence.new(RGB(255, 255, 255), RGB(180, 200, 255)),
				LightEmission = 1,
				EmissionDirection = Enum.NormalId.Top,
			})
		end
	end
end

----------------------------------------------------------------------
-- 지역 1: 숲 마을 (집 6채 자리, 컨베이어 옆 산책로, 로비, 무지개, 알 공장 아치)
----------------------------------------------------------------------

local function buildRainbow(parent: Instance)
	buildRainbowArc(parent, Vector3.new(RAINBOW_X, 0, LOBBY.Z), RAINBOW_R, Vector3.zAxis, 6, 9)
end

local function buildFactoryArch(parent: Instance)
	local m = model("EggFactoryArch", parent)
	local x = Zones[1].ConveyorStart.X
	local pillarZ = WALK_OUT + 2
	local ringH = 2.1
	local rings = 8
	for _, side in { 1, -1 } do
		for i = 0, rings - 1 do
			local c = if i % 2 == 0 then COLORS.Pink else COLORS.White
			local p = column(m, Vector3.new(x, i * ringH, side * pillarZ), ringH, 2.4, c)
			p.CanCollide = true
		end
		ball(m, Vector3.new(x, rings * ringH + 2.6, side * (pillarZ + 0.6)), 2.4, if side == 1 then COLORS.Mint else COLORS.Lavender)
	end
	local beamY = rings * ringH
	local beam = newPart(m, Vector3.new(2.6, 1.8, pillarZ * 2 + 3), CFrame.new(x, beamY + 0.9, 0), COLORS.Lavender)
	beam.CanCollide = true
	local signY = beamY + 1.8 + 1.8
	local sign = newPart(m, Vector3.new(14, 3.6, 0.8), CFrame.lookAt(Vector3.new(x, signY, 0), Vector3.new(x - 10, signY, 0)), COLORS.HotPink)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local frame = signFrame(sign, face, 40, COLORS.Cream, COLORS.HotPink)
		textLabel(frame, "🏭 알 공장 🥚", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.84), COLORS.HotPink)
	end
	local eggPos = Vector3.new(x, signY + 1.8 + 2.0, 0)
	blob(m, eggPos, Vector3.new(3.2, 4.2, 3.2), COLORS.Cream)
	ball(m, eggPos + Vector3.new(-1.35, 0.6, 0.5), 0.9, COLORS.Pink)
	ball(m, eggPos + Vector3.new(1.35, 0.2, 0), 0.9, COLORS.Lemon)
end

local function buildLobby(ctx: Ctx)
	local m = model("Lobby", ctx.Folder)
	local up = CFrame.Angles(0, 0, math.pi / 2)
	local ring = newPart(m, Vector3.new(1, PLAZA_R * 2, PLAZA_R * 2), CFrame.new(LOBBY.X, -0.38, LOBBY.Z) * up, COLORS.Pink, Enum.PartType.Cylinder)
	ring.CanCollide = true
	local inner = newPart(m, Vector3.new(1, PLAZA_R * 2 - 3, PLAZA_R * 2 - 3), CFrame.new(LOBBY.X, -0.34, LOBBY.Z) * up, COLORS.Cream, Enum.PartType.Cylinder)
	inner.CanCollide = true
	local star = newPart(m, Vector3.new(1, 12, 12), CFrame.new(LOBBY.X, -0.3, LOBBY.Z) * up, COLORS.Lemon, Enum.PartType.Cylinder)
	star.CanCollide = true

	-- 스폰 (마을 쪽 +X 를 바라봄)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.6, 8)
	spawn.CFrame = CFrame.lookAt(LOBBY + Vector3.new(0, 0.5, 0), LOBBY + Vector3.new(10, 0.5, 0))
	spawn.Color = COLORS.Pink
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.AllowTeamChangeOnTouch = false
	spawn.Enabled = true
	spawn.Parent = m
	partCount += 1

	-- 환영 간판 (북동쪽, 스폰을 바라봄)
	local welcomePos = Vector3.new(LOBBY.X + 12, 0, LOBBY.Z + 24)
	local welcome = buildSignBoard(m, welcomePos, LOBBY, Vector2.new(16, 7), 3, COLORS.HotPink)
	local wf = signFrame(welcome, Enum.NormalId.Front, 40, COLORS.Cream, COLORS.HotPink)
	textLabel(wf, "🥚 펫 월드 🐾", UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.92, 0.5), COLORS.HotPink)
	textLabel(wf, "🌳 숲 마을에 어서 와요! 💖", UDim2.fromScale(0.08, 0.6), UDim2.fromScale(0.84, 0.3), COLORS.Text)
	local wb = signFrame(welcome, Enum.NormalId.Back, 40, COLORS.Cream, COLORS.HotPink)
	textLabel(wb, "🐾 즐겁게 놀아요! 🐾", UDim2.fromScale(0.05, 0.3), UDim2.fromScale(0.9, 0.4), COLORS.HotPink)
	table.insert(ctx.Circles, { X = welcomePos.X, Z = welcomePos.Z, R = 10 })

	-- 놀이 방법 간판 (남동쪽)
	local howPos = Vector3.new(LOBBY.X + 12, 0, LOBBY.Z - 24)
	local howto = buildSignBoard(m, howPos, LOBBY, Vector2.new(15, 12), 2, COLORS.Sky)
	local lines = {
		"1. 컨베이어에서 알 사기 🥚",
		"2. 들판에서 코인 줍기 💰",
		"3. 가방에서 펫 타기 🏇",
		"4. 합성: 같은 펫 3마리 (가방 펫만) ✨",
		"5. 🗺 지도(M)로 지역 이동",
		"6. 🛍 상점(P): 옷 · 가구",
		"7. 🔄 환생하면 새 지역이 열려요!",
	}
	local blue = RGB(110, 170, 255)
	local frame = signFrame(howto, Enum.NormalId.Front, 40, COLORS.Cream, blue)
	textLabel(frame, "📖 놀이 방법", UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.15), RGB(80, 130, 230))
	for i, line in lines do
		textLabel(frame, line, UDim2.fromScale(0.06, 0.2 + (i - 1) * 0.112), UDim2.fromScale(0.88, 0.095), COLORS.Text, Enum.TextXAlignment.Left)
	end
	local back = signFrame(howto, Enum.NormalId.Back, 40, COLORS.Cream, blue)
	textLabel(back, "🐾 펫 월드 🐾", UDim2.fromScale(0.05, 0.3), UDim2.fromScale(0.9, 0.4), COLORS.HotPink)
	table.insert(ctx.Circles, { X = howPos.X, Z = howPos.Z, R = 10 })

	-- 광장 꽃 화분 (서쪽 반원만: 동쪽 출구와 간판 자리는 비워 둠)
	for i = 0, 5 do
		local a = math.pi * 0.62 + i / 5 * math.pi * 0.76
		local p = Vector3.new(LOBBY.X + math.cos(a) * (PLAZA_R - 2.5), 0, LOBBY.Z + math.sin(a) * (PLAZA_R - 2.5))
		local pot = column(m, p, 1.2, 2.2, COLORS.Peach)
		pot.CanCollide = true
		ball(m, p + Vector3.new(0, 1.5, 0), 1.3, pick(FLOWER_COLORS))
	end
end

-- 귀여운 펫 동상 (PetModels 가 있으면)
local function buildStatues(parent: Instance)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("PetModels")
	if not (module and module:IsA("ModuleScript")) then
		return
	end
	local ok, PetModels = pcall(require, module)
	if not ok or type(PetModels) ~= "table" or type((PetModels :: any).BuildPet) ~= "function" then
		return
	end
	local m = model("Statues", parent)
	local spots = {
		{ id = "Chick", pos = Vector3.new(LOBBY.X - 11, 0, LOBBY.Z + 6) },
		{ id = "Bunny", pos = Vector3.new(LOBBY.X - 11, 0, LOBBY.Z - 6) },
	}
	for _, s in spots do
		local built, pet = pcall((PetModels :: any).BuildPet, s.id)
		if built and typeof(pet) == "Instance" and pet:IsA("Model") then
			local pedestal = column(m, s.pos, 1.2, 4.5, COLORS.Lavender)
			pedestal.CanCollide = true
			pcall(function()
				pet:ScaleTo(2.2)
			end)
			for _, d in pet:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanTouch = false
					partCount += 1
				end
			end
			local top = s.pos + Vector3.new(0, 1.2, 0)
			pet:PivotTo(CFrame.lookAt(top, top + Vector3.new(1, 0, 0)))
			pet.Name = "Statue_" .. s.id
			pet.Parent = m
		end
	end
end

local function buildHome(ctx: Ctx)
	local def, pal = ctx.Def, ctx.Pal
	local paths = folder("Paths", ctx.Folder)
	local conv0, conv1 = def.ConveyorStart.X, def.ConveyorEnd.X
	local r = ctx.Rect
	local east = r.MaxX
	local pathColor, sideColor = pal.Path, COLORS.PathDark

	-- 로비 → 알 공장 큰길, 컨베이어 양옆 산책로, 알 통을 돌아서 바다 길(동쪽)까지 큰길
	flatRect(paths, LOBBY.X + 10, conv0 - 6, -HALF_TRAIL, HALF_TRAIL, 0.1, pathColor)
	for _, side in { 1, -1 } do
		flatRect(paths, conv0 - 8, conv1 + 10, side * WALK_IN, side * WALK_OUT, 0.12, pathColor)
	end
	flatRect(paths, conv1 + 8, east + 1, -HALF_TRAIL, HALF_TRAIL, 0.1, pathColor)
	-- 집 입구 → 산책로, 집 줄 앞길
	for _, cf in Layout.Plots do
		local entrance = cf.Position + cf.LookVector * HALF_PLOT
		local sign = if entrance.Z >= 0 then 1 else -1
		flatRect(paths, entrance.X - 5, entrance.X + 5, sign * WALK_OUT, entrance.Z + sign * 0.5, 0.14, sideColor)
	end
	local rowFront = Layout.Plots[1].Position.Z - HALF_PLOT -- 48
	local plotMinX, plotMaxX = math.huge, -math.huge
	for _, cf in Layout.Plots do
		plotMinX = math.min(plotMinX, cf.Position.X - HALF_PLOT)
		plotMaxX = math.max(plotMaxX, cf.Position.X + HALF_PLOT)
	end

	-- 섬 길 입구로 가는 길 (v4): 숲 마을 가장자리 길 입구(Trail.From)마다 숲 마을 안쪽 길과 이어요.
	--   북/남쪽 입구 → 세로 길 (x = 입구 x), 서쪽 입구 → 가로 길 (z = 입구 z) → 가까운 세로 길
	--   세로 길은 집 줄 앞길(|z| ≈ 45)을 지나 로비 광장 / 동쪽 큰길까지
	local LANE = 5 -- 세로 길 폭 반
	local laneXs: { number } = {}
	local function addLane(x: number)
		for _, lx in laneXs do
			if math.abs(lx - x) < 1 then
				return
			end
		end
		table.insert(laneXs, x)
	end
	for k = 2, #Zones do
		local t = Zones[k].Trail
		if t and Zones[k].Parent == 1 and math.abs(t.Dir.Z) > 0.5 then
			addLane(t.From.X)
		end
	end
	table.sort(laneXs)
	local function laneInner(x: number): number
		-- 세로 길 안쪽 끝 |z|: 로비 광장에 닿으면 광장 가장자리, 아니면 큰길 가장자리
		if math.abs(x - LOBBY.X) < PLAZA_R then
			return PLAZA_R - 1
		end
		return HALF_TRAIL - 0.5
	end
	local laneMin, laneMax = plotMinX, plotMaxX
	for _, x in laneXs do
		laneMin, laneMax = math.min(laneMin, x - LANE), math.max(laneMax, x + LANE)
		for _, side in { 1, -1 } do
			local z0, z1 = side * laneInner(x), side * (r.MaxZ + 1)
			flatRect(paths, x - LANE, x + LANE, math.min(z0, z1), math.max(z0, z1), 0.11, pathColor)
		end
	end
	local spurs: { Rect } = {}
	for k = 2, #Zones do
		local t = Zones[k].Trail
		if t and Zones[k].Parent == 1 and math.abs(t.Dir.X) > 0.5 then
			-- 동쪽 입구는 큰길이 이미 닿아요 (z = 0)
			if math.abs(t.From.Z) > HALF_TRAIL then
				local nearest = laneXs[1] or LOBBY.X
				for _, x in laneXs do
					if math.abs(x - t.From.X) < math.abs(nearest - t.From.X) then
						nearest = x
					end
				end
				local x0, x1 = math.min(t.From.X, nearest), math.max(t.From.X, nearest)
				local s = rect(x0 - (if t.Dir.X < 0 then 1 else 0), x1 + LANE, t.From.Z - HALF_TRAIL, t.From.Z + HALF_TRAIL)
				flatRect(paths, s.MinX, s.MaxX, s.MinZ, s.MaxZ, 0.1, pathColor)
				table.insert(spurs, s)
			end
		end
	end
	for _, side in { 1, -1 } do
		flatRect(paths, laneMin, laneMax, side * (rowFront - 5), side * (rowFront - 1), 0.12, pathColor)
	end
	-- ★v8 2번 집 줄 (1번 집 바로 뒤): 1번 집 뒤 ~ 2번 집 앞 사이 뒷골목 길. 양 끝이 세로 길과 이어져요
	local alleyIn = Layout.Plots[1].Position.Z + HALF_PLOT -- 112
	local alleyOut = Layout.Plots2[1].Position.Z - HALF_PLOT -- 128
	for _, side in { 1, -1 } do
		flatRect(paths, laneMin, laneMax, side * (alleyIn + 3), side * (alleyOut - 3), 0.12, pathColor)
	end
	-- 캔디 가로등
	for _, x in { -44, -20, 20, 44 } do
		for _, side in { 1, -1 } do
			buildLamp(paths, Vector3.new(x, 0, side * (WALK_OUT + 1.5)), pick(FLOWER_COLORS))
		end
	end

	-- 장식 금지 구역
	local blocks = ctx.Blocks
	table.insert(blocks, rect(conv0 - 12, conv1 + 14, -WALK_OUT - 3, WALK_OUT + 3)) -- 컨베이어 + 산책로 + 아치
	table.insert(blocks, rect(LOBBY.X, conv0, -HALF_TRAIL - 2, HALF_TRAIL + 2)) -- 서쪽 큰길
	table.insert(blocks, rect(conv1, east, -HALF_TRAIL - 2, HALF_TRAIL + 2)) -- 동쪽 큰길
	for _, cf in Layout.Plots do
		local p = cf.Position
		table.insert(blocks, rect(p.X - HALF_PLOT - 4, p.X + HALF_PLOT + 4, p.Z - HALF_PLOT - 4, p.Z + HALF_PLOT + 4))
		local sign = if p.Z >= 0 then 1 else -1
		table.insert(blocks, rect(p.X - 7, p.X + 7, math.min(sign * WALK_OUT, p.Z), math.max(sign * WALK_OUT, p.Z)))
	end
	for _, side in { 1, -1 } do
		table.insert(blocks, rect(laneMin - 2, laneMax + 2, math.min(side * (rowFront - 7), side * rowFront), math.max(side * (rowFront - 7), side * rowFront)))
		table.insert(blocks, rect(laneMin - 2, laneMax + 2, math.min(side * alleyIn, side * alleyOut), math.max(side * alleyIn, side * alleyOut)))
	end
	for _, cf in Layout.Plots2 do
		local p = cf.Position
		table.insert(blocks, rect(p.X - HALF_PLOT - 4, p.X + HALF_PLOT + 4, p.Z - HALF_PLOT - 4, p.Z + HALF_PLOT + 4))
	end
	for _, x in laneXs do
		table.insert(blocks, rect(x - LANE - 2, x + LANE + 2, r.MinZ, r.MaxZ))
	end
	for _, s in spurs do
		table.insert(blocks, rect(s.MinX, s.MaxX, s.MinZ - 2, s.MaxZ + 2))
	end
	-- 길 입구 앞 (문 아치 앞이 막히지 않게)
	for k = 2, #Zones do
		local t = Zones[k].Trail
		if t and Zones[k].Parent == 1 then
			table.insert(blocks, stripRect(t.From, t.From - t.Dir * 22, HALF_TRAIL + 6))
		end
	end
	-- 순위표 자리 (±10 + 판 너비)
	for _, cf in { Layout.Leaderboards.Income, Layout.Leaderboards.Rebirths } do
		local p = cf.Position
		table.insert(blocks, rect(p.X - 12, p.X + 14, p.Z - 16, p.Z + 16))
	end
	table.insert(blocks, rect(RAINBOW_X - 5, RAINBOW_X + 5, -RAINBOW_R - 4, RAINBOW_R + 4))
	table.insert(ctx.Circles, { X = LOBBY.X, Z = LOBBY.Z, R = PLAZA_R + 3 })

	buildLobby(ctx)
	buildStatues(ctx.Folder)
	buildRainbow(ctx.Folder)
	buildFactoryArch(ctx.Folder)
end

local function decorateVillage(ctx: Ctx)
	scatter(ctx, 22, 4.5, false, nil, function(p, pos)
		buildTree(p, pos)
	end)
	scatter(ctx, 14, 2.2, false, nil, buildBush)
	scatter(ctx, 9, 1.6, false, nil, buildMushroom)
	scatter(ctx, 14, 1.8, true, nil, buildFlowers)
	local r = ctx.Rect
	for _ = 1, 7 do
		buildCloud(ctx.Deco, Vector3.new(rng:NextNumber(r.MinX, r.MaxX), rng:NextNumber(50, 75), rng:NextNumber(r.MinZ, r.MaxZ)))
	end
	-- 섬 사이 바다 위 작은 언덕 (숲 마을·섬·길과 안 겹치는 빈 바다에만)
	local hills = folder("Hills", ctx.Folder)
	local placed = 0
	for _ = 1, 400 do
		if placed >= 6 then
			break
		end
		local x = rng:NextNumber(r.MinX - 120, r.MaxX + 120)
		local z = rng:NextNumber(r.MinZ - 120, r.MaxZ + 120)
		local hr = rng:NextNumber(14, 20)
		if seaFree(x, z, hr + 8) then
			table.insert(seaPlaced, { x = x, z = z, r = hr })
			local c = pick(BUSH_COLORS):Lerp(COLORS.Lemon, rng:NextNumber(0, 0.2))
			buildHill(hills, Vector3.new(x, 0, z), Vector3.new(hr * 2, rng:NextNumber(18, 28), hr * 1.8), c, Enum.Material.Grass)
			placed += 1
		end
	end
end

----------------------------------------------------------------------
-- 지역 2~8 공통: 큰길, 컨베이어 앞 산책로, 스폰 자리 (섬 안 좌표 u/v 로 그려요, Config 의 island 와 같아요)
----------------------------------------------------------------------

local function buildZoneRoads(ctx: Ctx)
	local def, pal = ctx.Def, ctx.Pal
	local f = folder("Paths", ctx.Folder)
	local t = def.Trail
	local bs = t.BeltSide
	local last = ctx.Index >= Config.MaxZone
	local vb, u0, u1 = beltLocal(def)
	local roadEnd = 92 -- 큰길 끝 (동그란 광장)
	local plazaU = roadEnd + 10
	-- 큰길: 섬 입구 → 섬 안쪽 광장
	rectPart(f, localRect(def, -1, roadEnd, -HALF_TRAIL, HALF_TRAIL), 0.1, pal.Path)
	disc(f, localPoint(def, plazaU, 0) + Vector3.new(0, 0.06, 0), 26, 0.3, pal.Path, Enum.Material.Sand).CanCollide = true
	if last then
		-- 마지막 지역: 네온 길 테두리
		for _, sz in { -1, 1 } do
			local a = localPoint(def, 0, sz * (HALF_TRAIL - 0.3))
			local b = localPoint(def, roadEnd, sz * (HALF_TRAIL - 0.3))
			local mid = (a + b) / 2 + Vector3.new(0, 0.15, 0)
			local strip = newPart(f, Vector3.new(0.5, 0.1, (b - a).Magnitude), CFrame.lookAt(mid, mid + t.Dir), pal.Accent, nil, Enum.Material.Neon)
			strip.CastShadow = false
		end
	end
	-- 컨베이어 앞 산책로 + 큰길에서 내려가는 길
	local wv = vb - bs * 8
	rectPart(f, localRect(def, u0 - 10, u1 + 10, wv - 3, wv + 3), 0.12, pal.Path)
	local roadEdge = bs * (HALF_TRAIL - 0.5)
	rectPart(f, localRect(def, u0 - 8, u0, roadEdge, wv), 0.14, darken(pal.Path, 0.05))
	-- 스폰 자리 (납작한 원판 2장)
	local sp = def.Spawn
	disc(f, Vector3.new(sp.X, 0.08, sp.Z), 12, 0.3, pal.Accent).CanCollide = true
	disc(f, Vector3.new(sp.X, 0.12, sp.Z), 6, 0.3, lighten(pal.Path, 0.4)).CanCollide = true

	-- 장식 금지 구역
	local blocks = ctx.Blocks
	table.insert(blocks, localRect(def, 0, roadEnd, -HALF_TRAIL - 2, HALF_TRAIL + 2))
	table.insert(ctx.Circles, { X = localPoint(def, plazaU, 0).X, Z = localPoint(def, plazaU, 0).Z, R = 16 })
	table.insert(blocks, localRect(def, u0 - 12, u1 + 14, vb + bs * 10, wv - bs * 4))
	table.insert(blocks, localRect(def, u0 - 10, u0 + 2, roadEdge, wv))
	table.insert(blocks, localRect(def, 0, 14, -18, 18)) -- 섬 입구 앞
	table.insert(ctx.Circles, { X = sp.X, Z = sp.Z, R = 10 })

	-- ★v8 바깥 섬으로 가는 길: 광장 → 섬 맨 끝 길 시작점 (시작점은 늘 섬 안 좌표 v = 0 쪽 끝이에요)
	for _, exit in ctx.Exits do
		local eu = (exit - t.To):Dot(t.Dir)
		local ev = (exit - t.To):Dot(t.Side)
		rectPart(f, localRect(def, plazaU + 8, eu + 1, ev - HALF_TRAIL, ev + HALF_TRAIL), 0.1, pal.Path)
		table.insert(blocks, localRect(def, plazaU, eu, ev - HALF_TRAIL - 2, ev + HALF_TRAIL + 2))
		table.insert(blocks, stripRect(exit, exit - t.Dir * 22, HALF_TRAIL + 6))
	end
end

----------------------------------------------------------------------
-- 지역별 장식
----------------------------------------------------------------------

local function skyClouds(ctx: Ctx, n: number, color: Color3?)
	local r = ctx.Rect
	for _ = 1, n do
		buildCloud(ctx.Deco, Vector3.new(rng:NextNumber(r.MinX, r.MaxX), rng:NextNumber(55, 75), rng:NextNumber(r.MinZ, r.MaxZ)), color)
	end
end

-- 섬 가운데에서 숲 마을 반대쪽(바깥) 방향
local function outward(ctx: Ctx): Vector3
	local d = ctx.Def.Center - HOME_CENTER
	d = Vector3.new(d.X, 0, d.Z)
	return if d.Magnitude > 1e-3 then d.Unit else Vector3.xAxis
end

local THEMES: { [string]: (Ctx) -> () } = {}

THEMES.Village = decorateVillage

THEMES.Lake = function(ctx)
	local pal = ctx.Pal
	scatter(ctx, 3, 9, false, ctx.South, function(p, pos)
		buildPond(p, pos, pal)
	end)
	scatter(ctx, 8, 4.5, false, ctx.South, function(p, pos)
		buildTree(p, pos, GREEN_CROWNS)
	end)
	scatter(ctx, 6, 1.8, false, ctx.South, buildReeds)
	scatter(ctx, 5, 2.4, false, ctx.South, function(p, pos)
		buildRock(p, pos, COLORS.Rock, nil)
	end)
	scatter(ctx, 8, 1.6, true, ctx.Field, buildFlowers)
	-- 섬 밖 언덕 + 바다 위 연잎
	for _, s in outerSpots(ctx, 5, 30, 60, 30) do
		buildHill(ctx.Deco, s, Vector3.new(rng:NextNumber(50, 64), rng:NextNumber(24, 36), rng:NextNumber(40, 56)), pick(GREEN_CROWNS), Enum.Material.Grass)
	end
	for _, s in outerSpots(ctx, 14, 3, 40, 2.5) do
		buildLilyPad(ctx.Deco, Vector3.new(s.X, SEA_Y, s.Z))
	end
	skyClouds(ctx, 3)
end

THEMES.Jungle = function(ctx)
	scatter(ctx, 9, 5, false, ctx.South, function(p, pos)
		buildPalm(p, pos)
	end)
	scatter(ctx, 4, 6, false, ctx.South, buildVineTree)
	scatter(ctx, 6, 3.5, false, ctx.South, buildBigLeaf)
	scatter(ctx, 4, 2.4, false, ctx.South, function(p, pos)
		buildRock(p, pos, RGB(140, 145, 150), RGB(110, 185, 95))
	end)
	scatter(ctx, 8, 1.4, true, ctx.Field, buildTropicalFlower)
	local hills = outerSpots(ctx, 5, 30, 55, 32)
	for _, s in hills do
		buildHill(ctx.Deco, s, Vector3.new(rng:NextNumber(55, 66), rng:NextNumber(40, 60), rng:NextNumber(45, 60)), pick({ RGB(70, 160, 80), RGB(90, 175, 85) }), Enum.Material.LeafyGrass)
	end
	-- 폭포 (섬을 바라보는 언덕 하나)
	local h = hills[2] or hills[1]
	if h then
		local toward = Vector3.new(ctx.Def.Center.X - h.X, 0, ctx.Def.Center.Z - h.Z).Unit
		local at = h + toward * 20 + Vector3.new(0, SEA_Y + 11, 0)
		local fall = newPart(ctx.Deco, Vector3.new(6, 24, 1), CFrame.lookAt(at, at + toward), RGB(170, 225, 255), nil, Enum.Material.Glass)
		fall.Transparency = 0.3
		fall.Name = "Waterfall"
		blob(ctx.Deco, h + toward * 22 + Vector3.new(0, SEA_Y + 0.5, 0), Vector3.new(10, 3, 10), COLORS.White).Name = "Foam"
	end
	skyClouds(ctx, 2)
end

THEMES.Snow = function(ctx)
	scatter(ctx, 11, 3.6, false, ctx.South, function(p, pos)
		buildPine(p, pos)
	end)
	scatter(ctx, 4, 2.4, false, ctx.South, buildSnowman)
	scatter(ctx, 5, 2, false, ctx.South, function(p, pos)
		buildIceCrystal(p, pos)
	end)
	scatter(ctx, 4, 2.6, false, ctx.South, buildSnowPile)
	scatter(ctx, 3, 2.4, false, ctx.South, function(p, pos)
		buildRock(p, pos, RGB(150, 160, 175), RGB(250, 252, 255))
	end)
	scatter(ctx, 8, 1.6, true, ctx.Field, buildSnowPile)
	-- 큰 눈 덮인 산 (겨울 산!)
	for _, s in outerSpots(ctx, 6, 40, 70, 40) do
		buildMountain(ctx.Deco, s, rng:NextNumber(60, 80), rng:NextNumber(40, 62))
	end
	-- 바다 위 빙산
	for _, s in outerSpots(ctx, 4, 10, 25, 7) do
		blob(ctx.Deco, Vector3.new(s.X, SEA_Y, s.Z), Vector3.new(rng:NextNumber(8, 14), rng:NextNumber(5, 9), rng:NextNumber(8, 12)), RGB(225, 240, 255), Enum.Material.Ice).Name = "Iceberg"
	end
	-- 눈 내리기
	local snow = newPart(ctx.Deco, Vector3.new(ctx.Def.Size.X, 1, ctx.Def.Size.Z), CFrame.new(ctx.Def.Center.X, 70, ctx.Def.Center.Z), COLORS.White)
	snow.Name = "Snowfall"
	snow.Transparency = 1
	snow.CastShadow = false
	emitter(snow, {
		Rate = 40,
		Lifetime = NumberRange.new(16, 20),
		Speed = NumberRange.new(3.5, 4.5),
		SpreadAngle = Vector2.new(12, 12),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new(0.4),
		Color = ColorSequence.new(COLORS.White),
		LightEmission = 0.3,
		RotSpeed = NumberRange.new(-40, 40),
	})
	skyClouds(ctx, 2)
end

THEMES.Ocean = function(ctx)
	local pal = ctx.Pal
	scatter(ctx, 8, 5, false, ctx.South, function(p, pos)
		buildPalm(p, pos)
	end)
	scatter(ctx, 4, 4.2, false, ctx.South, function(p, pos)
		buildUmbrella(p, pos, pal)
	end)
	scatter(ctx, 5, 2.4, false, ctx.South, buildCoral)
	scatter(ctx, 3, 2.4, false, ctx.South, function(p, pos)
		buildRock(p, pos, RGB(160, 150, 140), nil)
	end)
	scatter(ctx, 6, 1.4, true, ctx.Field, buildStarfish)
	scatter(ctx, 6, 1.1, true, ctx.Field, buildShell)
	-- 등대 + 야자수 작은 섬 (섬 바깥 바다)
	local light = outerSpots(ctx, 1, 30, 45, 6)[1]
	if light then
		buildLighthouse(ctx.Deco, light)
	end
	local islet = outerSpots(ctx, 1, 30, 50, 12)[1]
	if islet then
		blob(ctx.Deco, Vector3.new(islet.X, SEA_Y, islet.Z), Vector3.new(22, 5, 18), pal.Ground, Enum.Material.Sand).Name = "Islet"
		buildPalm(ctx.Deco, islet + Vector3.new(0, SEA_Y + 2, 0), 1.3)
	end
	-- 바다 속 산호 (물 위로 살짝)
	for _, s in outerSpots(ctx, 4, 8, 30, 3) do
		buildCoral(ctx.Deco, Vector3.new(s.X, SEA_Y - 2.5, s.Z))
	end
	skyClouds(ctx, 2)
end

THEMES.Candy = function(ctx)
	local pal = ctx.Pal
	-- 케이크처럼 크림 띠 (섬 가장자리)
	local def = ctx.Def
	newPart(ctx.Folder, Vector3.new(def.Size.X + 3.4, 0.8, def.Size.Z + 3.4), CFrame.new(def.Center.X, -1.6, def.Center.Z), COLORS.Cream).Name = "Cream"
	scatter(ctx, 7, 2.6, false, ctx.South, function(p, pos)
		buildLollipop(p, pos)
	end)
	scatter(ctx, 7, 2, false, ctx.South, buildCandyCane)
	scatter(ctx, 5, 2.2, false, ctx.South, function(p, pos)
		buildCupcake(p, pos, pal)
	end)
	scatter(ctx, 4, 3.6, false, ctx.South, function(p, pos)
		buildDonut(p, pos, pal)
	end)
	scatter(ctx, 10, 1.2, true, ctx.Field, buildGumDrop)
	for _, s in outerSpots(ctx, 4, 30, 55, 30) do
		buildHill(ctx.Deco, s, Vector3.new(rng:NextNumber(45, 60), rng:NextNumber(26, 40), rng:NextNumber(40, 56)), pick({ RGB(255, 190, 220), RGB(190, 240, 215), RGB(255, 245, 250) }))
	end
	-- 바다에 꽂힌 큰 막대사탕
	for _, s in outerSpots(ctx, 4, 12, 22, 4) do
		buildLollipop(ctx.Deco, Vector3.new(s.X, SEA_Y, s.Z), rng:NextNumber(2.4, 3.2))
	end
	-- 솜사탕 구름
	local r = ctx.Rect
	for _ = 1, 4 do
		buildCloud(ctx.Deco, Vector3.new(rng:NextNumber(r.MinX, r.MaxX), rng:NextNumber(55, 75), rng:NextNumber(r.MinZ, r.MaxZ)), pick({ RGB(255, 200, 230), RGB(200, 225, 255) }))
	end
end

THEMES.Cloud = function(ctx)
	local def = ctx.Def
	local t = def.Trail
	-- 섬 둘레 몽글몽글 구름 (숲 마을 쪽 입구 변은 비워요)
	local r = ctx.Rect
	local edges = {
		{ A = Vector3.new(r.MinX, 0, r.MaxZ), B = Vector3.new(r.MaxX, 0, r.MaxZ), N = Vector3.zAxis },
		{ A = Vector3.new(r.MinX, 0, r.MinZ), B = Vector3.new(r.MaxX, 0, r.MinZ), N = -Vector3.zAxis },
		{ A = Vector3.new(r.MinX, 0, r.MinZ), B = Vector3.new(r.MinX, 0, r.MaxZ), N = -Vector3.xAxis },
		{ A = Vector3.new(r.MaxX, 0, r.MinZ), B = Vector3.new(r.MaxX, 0, r.MaxZ), N = Vector3.xAxis },
	}
	for _, e in edges do
		if e.N:Dot(t.Dir) > -0.5 then
			local along = (e.B - e.A).Unit
			for i = 0, 3 do
				local p = e.A + (e.B - e.A) * ((i + 0.5) / 4) + e.N * 3 + Vector3.new(0, -1.5, 0)
				local blocked = false
				for _, exit in ctx.Exits do
					if (Vector3.new(p.X, 0, p.Z) - exit).Magnitude < 17 + HALF_TRAIL + 4 then
						blocked = true -- ★v8 바깥 섬 길 앞은 비워요
					end
				end
				if blocked then
					continue
				end
				blobCF(ctx.Folder, CFrame.lookAt(p, p + along), Vector3.new(16, 9, 34), RGB(250, 248, 255)).Name = "EdgeCloud"
			end
		end
	end
	scatter(ctx, 6, 4, false, ctx.South, function(p, pos)
		buildCloudPuff(p, pos)
	end)
	-- 큰길 위 무지개 다리 (파트는 안 막아요)
	local across = Vector3.new(math.abs(t.Side.X), 0, math.abs(t.Side.Z))
	buildRainbowArc(ctx.Deco, localPoint(def, 50, 0), 16, across, 5, 7)
	scatter(ctx, 5, 2, false, ctx.South, buildPillar)
	local castle = findSpot(ctx, 9, false, ctx.South)
	if castle then
		buildCastle(ctx.Deco, castle)
	end
	-- 들판 위에 떠 있는 별 (높이 떠 있고 큰길 위는 비워요)
	local placed = 0
	for _ = 1, 60 do
		if placed >= 9 then
			break
		end
		local x = rng:NextNumber(ctx.Field.MinX + 6, ctx.Field.MaxX - 6)
		local z = rng:NextNumber(ctx.Field.MinZ + 6, ctx.Field.MaxZ - 6)
		local v = (Vector3.new(x, 0, z) - t.To):Dot(t.Side)
		if math.abs(v) > HALF_TRAIL + 6 then
			buildStar(ctx.Deco, Vector3.new(x, rng:NextNumber(9, 16), z), rng:NextNumber(1.6, 2.4))
			placed += 1
		end
	end
	-- 큰 구름 위 성 (바깥 배경)
	local bigCloud = outerSpots(ctx, 1, 40, 60, 32)[1]
	if bigCloud then
		blob(ctx.Deco, bigCloud + Vector3.new(0, 2, 0), Vector3.new(60, 12, 40), COLORS.White).Name = "BigCloud"
		buildCastle(ctx.Deco, bigCloud + Vector3.new(0, 6, 0), 2)
	end
	for _, s in outerSpots(ctx, 5, 25, 60, 10) do
		buildCloud(ctx.Deco, Vector3.new(s.X, rng:NextNumber(0, 8), s.Z))
	end
	skyClouds(ctx, 3, RGB(245, 240, 255))
end

THEMES.Space = function(ctx)
	local pal = ctx.Pal
	local def = ctx.Def
	local t = def.Trail
	scatter(ctx, 6, 4.5, false, ctx.South, function(p, pos)
		buildCrater(p, pos, pal)
	end)
	scatter(ctx, 8, 2, false, ctx.South, function(p, pos)
		buildSpaceCrystal(p, pos, pal)
	end)
	scatter(ctx, 3, 3, false, ctx.South, function(p, pos)
		buildRocket(p, pos)
	end)
	scatter(ctx, 8, 3, true, ctx.Field, function(p, pos)
		buildCrater(p, pos, pal)
	end)
	-- 떠 있는 작은 행성 (컨베이어 뒤 하늘)
	local vb = beltLocal(def)
	local behind = localRect(def, 10, 150, vb + t.BeltSide * 12, vb + t.BeltSide * 32)
	for _ = 1, 4 do
		local x = rng:NextNumber(behind.MinX, behind.MaxX)
		local z = rng:NextNumber(behind.MinZ, behind.MaxZ)
		buildPlanet(ctx.Deco, Vector3.new(x, rng:NextNumber(14, 24), z), rng:NextNumber(3, 6), rng:NextNumber() < 0.5)
	end
	-- 큰 행성 / 달 (배경)
	for i, s in outerSpots(ctx, 6, 40, 90, 20) do
		buildPlanet(ctx.Deco, Vector3.new(s.X, rng:NextNumber(20, 60), s.Z), rng:NextNumber(16, 34), i % 2 == 0)
	end
	local out = outward(ctx)
	local moonAt = def.Center + out * def.Size.X + Vector3.new(0, 95, 0)
	local moon = ball(ctx.Deco, moonAt, 30, RGB(255, 245, 200), Enum.Material.Neon)
	moon.Name = "Moon"
	moon.CastShadow = false
	-- 하늘 별
	for _ = 1, 10 do
		local s = ball(ctx.Deco, Vector3.new(def.Center.X + rng:NextNumber(-140, 140), rng:NextNumber(45, 90), def.Center.Z + rng:NextNumber(-140, 140)), rng:NextNumber(0.6, 1.4), pick({ COLORS.White, RGB(255, 240, 160), RGB(170, 220, 255) }), Enum.Material.Neon)
		s.CastShadow = false
	end
	-- 섬 너머 바다: 발사대 위 큰 로켓 (★v8 맨 끝은 바깥 섬 길이라 빈 바다에서 자리를 찾아요)
	local padPos = outerSpots(ctx, 1, 26, 45, 16)[1] or localPoint(def, def.Size.X / 2, (def.Center - t.To):Dot(t.Side) - def.Size.X / 2 - 34)
	disc(ctx.Deco, padPos + Vector3.new(0, -1.5, 0), 30, 3, RGB(120, 115, 150), Enum.Material.Metal).Name = "LaunchPad"
	disc(ctx.Deco, padPos + Vector3.new(0, 0.05, 0), 18, 0.2, pal.Accent, Enum.Material.Neon).CastShadow = false
	buildRocket(ctx.Deco, padPos, 3)
end

----------------------------------------------------------------------
-- ★v8 바깥 섬 8곳 장식
----------------------------------------------------------------------

local SAKURA_CROWNS = { RGB(255, 190, 215), RGB(255, 170, 205), RGB(255, 215, 230), RGB(250, 160, 195) }
local GEM_COLORS = { RGB(120, 240, 230), RGB(255, 120, 170), RGB(170, 130, 255), RGB(120, 180, 255), RGB(255, 225, 120) }
local TOY_COLORS = { RGB(255, 95, 115), RGB(90, 160, 255), RGB(255, 210, 60), RGB(110, 210, 120), RGB(190, 130, 255), RGB(255, 160, 80) }

-- 섬 위에 꽃잎·불씨처럼 천천히 떨어지는 것 (보이지 않는 판 하나 + 파티클)
local function skyParticles(ctx: Ctx, props: { [string]: any })
	local def = ctx.Def
	local sky = newPart(ctx.Deco, Vector3.new(def.Size.X, 1, def.Size.Z), CFrame.new(def.Center.X, 60, def.Center.Z), COLORS.White)
	sky.Name = "SkyParticles"
	sky.Transparency = 1
	sky.CastShadow = false
	emitter(sky, props)
end

-- 벚꽃 나무: 굵은 줄기 + 분홍 꽃 뭉치 3개
local function buildSakuraTree(parent: Instance, pos: Vector3, scale: number?)
	local m = model("SakuraTree", parent)
	local s = scale or rng:NextNumber(1, 1.4)
	local h = 6 * s
	local trunk = column(m, pos, h + 1, 1.2 * s, RGB(140, 95, 80))
	trunk.CanCollide = true
	local top = pos + Vector3.new(0, h, 0)
	stick(m, top - Vector3.new(0, 2 * s, 0), top + Vector3.new(2.6, 1.2, 0.8) * s, 0.6 * s, RGB(140, 95, 80))
	blob(m, top + Vector3.new(0, 2 * s, 0), Vector3.new(8, 5.5, 8) * s, pick(SAKURA_CROWNS))
	blob(m, top + Vector3.new(2.8, 1.6, 1) * s, Vector3.new(5, 4, 5) * s, pick(SAKURA_CROWNS))
	blob(m, top + Vector3.new(-2.4, 1.2, -1.2) * s, Vector3.new(4.6, 3.6, 4.6) * s, pick(SAKURA_CROWNS))
end

-- 종이 등불 (기둥 + 빛나는 등)
local function buildLantern(parent: Instance, pos: Vector3, color: Color3)
	local m = model("Lantern", parent)
	local pole = column(m, pos, 4.5, 0.5, RGB(120, 85, 70))
	pole.CanCollide = true
	disc(m, pos + Vector3.new(0, 4.6, 0), 2.2, 0.3, RGB(90, 60, 50))
	local lamp = blob(m, pos + Vector3.new(0, 5.7, 0), Vector3.new(1.8, 2.2, 1.8), color, Enum.Material.Neon)
	lamp.CastShadow = false
	disc(m, pos + Vector3.new(0, 6.9, 0), 1.6, 0.3, RGB(90, 60, 50))
end

-- 고사리 (잎 4~5장)
local function buildFern(parent: Instance, pos: Vector3)
	local m = model("Fern", parent)
	local n = rng:NextInteger(4, 5)
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local d = Vector3.new(math.cos(a), 0.8, math.sin(a)).Unit
		blobCF(m, CFrame.lookAt(pos + d * 1.6, pos + d * 3.2), Vector3.new(1.0, 0.25, 3.6), pick({ RGB(70, 160, 80), RGB(90, 180, 90) }))
	end
end

-- 공룡 뼈 (갈비뼈 아치 + 등뼈)
local function buildBones(parent: Instance, pos: Vector3)
	local m = model("Bones", parent)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local bone = RGB(245, 240, 225)
	stick(m, (base * CFrame.new(0, 2.6, -4)).Position, (base * CFrame.new(0, 2.2, 4)).Position, 0.7, bone)
	for i = -1, 1 do
		for _, sx in { -1, 1 } do
			local top = (base * CFrame.new(0, 2.5, i * 2.2)).Position
			local foot = (base * CFrame.new(sx * 2.2, 0, i * 2.2)).Position
			stick(m, top, foot, 0.5, bone).CanCollide = true
		end
	end
	ball(m, (base * CFrame.new(0, 1.2, -5.2)).Position, 2.4, bone)
end

-- 공룡 알 둥지 (나뭇가지 둥지 + 점박이 알 2~3개)
local function buildDinoEgg(parent: Instance, pos: Vector3)
	local m = model("DinoNest", parent)
	disc(m, pos + Vector3.new(0, 0.3, 0), 6, 0.6, RGB(150, 110, 70), Enum.Material.WoodPlanks)
	for i = 1, rng:NextInteger(2, 3) do
		local a = i * 2.2
		local c = pick({ RGB(240, 235, 210), RGB(190, 225, 170), RGB(255, 215, 170) })
		local e = blob(m, pos + Vector3.new(math.cos(a) * 1.2, 1.9, math.sin(a) * 1.2), Vector3.new(2.2, 3, 2.2), c)
		e.CanCollide = true
		ball(m, pos + Vector3.new(math.cos(a) * 1.9, 2.3, math.sin(a) * 1.9), 0.6, darken(c, 0.25))
	end
end

-- 큰 보석 무더기 (빛나는 기둥 3~4개)
local function buildBigCrystal(parent: Instance, pos: Vector3, scale: number?)
	local m = model("BigCrystal", parent)
	local s = scale or rng:NextNumber(1, 1.6)
	local c = pick(GEM_COLORS)
	for i = 1, rng:NextInteger(3, 4) do
		local h = rng:NextNumber(3, 7) * s
		local p = newPart(
			m,
			Vector3.new(1.4 * s, h, 1.4 * s),
			CFrame.new(pos + Vector3.new(rng:NextNumber(-1, 1) * s, h / 2 - 0.4, rng:NextNumber(-1, 1) * s)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), i * 1.2, rng:NextNumber(-0.4, 0.4)),
			if i == 1 then c else lighten(c, 0.3),
			nil,
			if i == 1 then Enum.Material.Neon else Enum.Material.Glass
		)
		p.Transparency = if i == 1 then 0 else 0.2
		p.CastShadow = false
		if i == 1 then
			p.CanCollide = true
		end
	end
end

-- 정동 (반으로 갈라진 돌 + 안쪽 보석)
local function buildGeode(parent: Instance, pos: Vector3)
	local m = model("Geode", parent)
	local shell = blob(m, pos + Vector3.new(0, 1.2, 0), Vector3.new(4.5, 3, 4), RGB(120, 110, 125), Enum.Material.Slate)
	shell.CanCollide = true
	blob(m, pos + Vector3.new(0, 2.4, 0), Vector3.new(3.4, 0.6, 3), pick(GEM_COLORS), Enum.Material.Neon).CastShadow = false
end

-- 선인장 (몸통 + 팔 2개)
local function buildCactus(parent: Instance, pos: Vector3)
	local m = model("Cactus", parent)
	local s = rng:NextNumber(0.9, 1.5)
	local g = pick({ RGB(95, 175, 90), RGB(115, 190, 100) })
	local body = column(m, pos, 6 * s, 1.8 * s, g)
	body.CanCollide = true
	ball(m, pos + Vector3.new(0, 6 * s, 0), 1.8 * s, g)
	for _, sx in { -1, 1 } do
		local y = rng:NextNumber(2.2, 3.6) * s
		stick(m, pos + Vector3.new(0, y, 0), pos + Vector3.new(sx * 1.8 * s, y, 0), 1.1 * s, g)
		column(m, pos + Vector3.new(sx * 1.8 * s, y, 0), 2 * s, 1.1 * s, g)
		ball(m, pos + Vector3.new(sx * 1.8 * s, y + 2 * s, 0), 1.1 * s, g)
	end
	if rng:NextNumber() < 0.5 then
		ball(m, pos + Vector3.new(0, 7 * s, 0), 0.9, RGB(255, 120, 170))
	end
end

-- 계단 피라미드 (블록 5단, 바다 위 큰 배경)
local function buildPyramid(parent: Instance, pos: Vector3, w: number)
	local m = model("Pyramid", parent)
	local c = RGB(235, 200, 135)
	local steps = 5
	local stepH = w * 0.12
	for i = 0, steps - 1 do
		local size = w * (1 - i / steps)
		newPart(m, Vector3.new(size, stepH, size), CFrame.new(pos + Vector3.new(0, SEA_Y + stepH * (i + 0.5), 0)), if i % 2 == 0 then c else darken(c, 0.08), nil, Enum.Material.Sandstone).Name = "Step"
	end
	ball(m, pos + Vector3.new(0, SEA_Y + stepH * steps + 1.5, 0), 3, COLORS.Gold, Enum.Material.Neon).CastShadow = false
end

-- 장난감 블록 탑 (색 블록 2~4개 + 위 동그란 돌기)
local function buildToyBlocks(parent: Instance, pos: Vector3, scale: number?)
	local m = model("ToyBlocks", parent)
	local s = scale or rng:NextNumber(1, 1.5)
	local y = 0
	for i = 1, rng:NextInteger(2, 4) do
		local size = Vector3.new(rng:NextNumber(2.5, 4), 2, rng:NextNumber(2.5, 4)) * s
		local c = pick(TOY_COLORS)
		local b = newPart(m, size, CFrame.new(pos + Vector3.new(rng:NextNumber(-0.6, 0.6), y + size.Y / 2, rng:NextNumber(-0.6, 0.6))) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), c)
		b.CanCollide = true
		y += size.Y
		if i == 1 then
			disc(m, pos + Vector3.new(0, size.Y + 0.25, 0), 1.2 * s, 0.5, c)
		end
	end
end

-- 비치볼 (3색 공)
local function buildToyBall(parent: Instance, pos: Vector3)
	local m = model("ToyBall", parent)
	local d = rng:NextNumber(2.5, 4)
	local b = ball(m, pos + Vector3.new(0, d / 2, 0), d, pick(TOY_COLORS))
	b.CanCollide = true
	disc(m, pos + Vector3.new(0, d / 2, 0), d * 1.02, 0.5, COLORS.White)
end

-- 풍선 다발 (줄 + 공 3개)
local function buildBalloons(parent: Instance, pos: Vector3)
	local m = model("Balloons", parent)
	column(m, pos, 0.6, 1, RGB(200, 200, 210)).CanCollide = true
	for i = 1, 3 do
		local a = i * 2.1
		local top = pos + Vector3.new(math.cos(a) * 1.2, 7 + i * 0.8, math.sin(a) * 1.2)
		stick(m, pos + Vector3.new(0, 0.6, 0), top - Vector3.new(0, 1.2, 0), 0.08, COLORS.White)
		blob(m, top, Vector3.new(2, 2.5, 2), pick(TOY_COLORS))
	end
end

-- 팽이 (원뿔 대신 원판 2장 + 손잡이)
local function buildSpinningTop(parent: Instance, pos: Vector3)
	local m = model("SpinningTop", parent)
	local c = pick(TOY_COLORS)
	blob(m, pos + Vector3.new(0, 1.6, 0), Vector3.new(4.5, 2.6, 4.5), c).CanCollide = true
	disc(m, pos + Vector3.new(0, 1.8, 0), 4.6, 0.4, COLORS.White)
	column(m, pos + Vector3.new(0, 2.6, 0), 1.6, 0.6, darken(c, 0.2))
	ball(m, pos + Vector3.new(0, 0.3, 0), 0.8, darken(c, 0.2))
end

-- 큰 베개 (꿈나라)
local function buildPillow(parent: Instance, pos: Vector3)
	local m = model("Pillow", parent)
	local c = pick({ RGB(255, 225, 240), RGB(220, 225, 255), RGB(255, 245, 210) })
	local yaw = rng:NextNumber(0, math.pi)
	local p = blobCF(m, CFrame.new(pos + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, yaw, 0), Vector3.new(6, 2.4, 4), c)
	p.CanCollide = true
	for _, sx in { -1, 1 } do
		ball(m, (CFrame.new(pos + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new(sx * 2.8, 0, 0)).Position, 1.4, c)
	end
end

-- 초승달 가로등 (꿈나라 길가)
local function buildMoonLamp(parent: Instance, pos: Vector3)
	local m = model("MoonLamp", parent)
	local pole = column(m, pos, 6, 0.5, RGB(200, 195, 240))
	pole.CanCollide = true
	local top = pos + Vector3.new(0, 7, 0)
	ball(m, top, 1.8, RGB(255, 235, 150), Enum.Material.Neon).CastShadow = false
	blob(m, top + Vector3.new(0.5, 0.3, 0), Vector3.new(1.6, 1.7, 1.9), RGB(200, 195, 240))
end

-- 용암 웅덩이 (돌 테두리 + 빛나는 용암)
local function buildLavaPool(parent: Instance, pos: Vector3)
	local m = model("LavaPool", parent)
	local d = rng:NextNumber(7, 11)
	disc(m, pos + Vector3.new(0, 0.1, 0), d + 2.4, 0.2, RGB(60, 50, 55), Enum.Material.Basalt)
	local lava = disc(m, pos + Vector3.new(0, 0.2, 0), d, 0.2, RGB(255, 110, 40), Enum.Material.Neon)
	lava.CastShadow = false
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		blob(m, pos + Vector3.new(math.cos(a) * (d / 2 + 0.8), 0.5, math.sin(a) * (d / 2 + 0.8)), Vector3.new(2.4, 1.4, 2), RGB(50, 42, 48), Enum.Material.Basalt).CanCollide = true
	end
end

-- 흑요석 뾰족 바위
local function buildObsidian(parent: Instance, pos: Vector3)
	local m = model("Obsidian", parent)
	for i = 1, 3 do
		local h = rng:NextNumber(3, 6)
		local p = newPart(m, Vector3.new(1.4, h, 1.4), CFrame.new(pos + Vector3.new(rng:NextNumber(-0.8, 0.8), h / 2 - 0.4, rng:NextNumber(-0.8, 0.8))) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), i, rng:NextNumber(-0.3, 0.3)), RGB(40, 30, 50), nil, Enum.Material.Glass)
		p.Reflectance = 0.25
		if i == 1 then
			p.CanCollide = true
		end
	end
end

-- 바다 위 큰 화산 (산 + 꼭대기 용암 + 연기)
local function buildVolcanoMountain(parent: Instance, pos: Vector3, w: number, h: number)
	local m = model("VolcanoMountain", parent)
	blob(m, Vector3.new(pos.X, SEA_Y, pos.Z), Vector3.new(w, h * 2, w * 0.9), RGB(70, 55, 60), Enum.Material.Basalt)
	local top = Vector3.new(pos.X, SEA_Y + h * 0.92, pos.Z)
	local lava = blob(m, top, Vector3.new(w * 0.3, h * 0.12, w * 0.28), RGB(255, 110, 40), Enum.Material.Neon)
	lava.CastShadow = false
	emitter(lava, {
		Rate = 4,
		Lifetime = NumberRange.new(6, 9),
		Speed = NumberRange.new(4, 7),
		SpreadAngle = Vector2.new(15, 15),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(RGB(120, 110, 115)),
	})
end

-- 동전 더미 (납작한 금 원판들)
local function buildCoinPile(parent: Instance, pos: Vector3)
	local m = model("CoinPile", parent)
	local base = blob(m, pos + Vector3.new(0, 0.6, 0), Vector3.new(5, 2, 5), COLORS.Gold, Enum.Material.Metal)
	base.CanCollide = true
	for _ = 1, 4 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0.5, 2)
		newPart(m, Vector3.new(0.3, 1.4, 1.4), CFrame.new(pos + Vector3.new(math.cos(a) * r, rng:NextNumber(1.2, 2), math.sin(a) * r)) * CFrame.Angles(rng:NextNumber(-1, 1), a, math.pi / 2 + rng:NextNumber(-0.6, 0.6)), RGB(255, 220, 90), Enum.PartType.Cylinder, Enum.Material.Metal)
	end
end

-- 보물 상자 (뚜껑 열린 상자 + 반짝이)
local function buildTreasure(parent: Instance, pos: Vector3)
	local m = model("Treasure", parent)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	newPart(m, Vector3.new(4, 2.4, 2.8), base * CFrame.new(0, 1.2, 0), RGB(170, 105, 55), nil, Enum.Material.WoodPlanks).CanCollide = true
	newPart(m, Vector3.new(4.1, 0.5, 2.9), base * CFrame.new(0, 2.3, 0), COLORS.Gold, nil, Enum.Material.Metal)
	newPart(m, Vector3.new(4, 0.6, 2.8), base * CFrame.new(0, 3.0, 1.6) * CFrame.Angles(-1.1, 0, 0), RGB(170, 105, 55), nil, Enum.Material.WoodPlanks)
	ball(m, (base * CFrame.new(0, 2.6, 0)).Position, 1.4, RGB(255, 230, 120), Enum.Material.Neon).CastShadow = false
end

-- 분수 (둥근 물받이 + 기둥 + 물)
local function buildFountain(parent: Instance, pos: Vector3, pal: any)
	local m = model("Fountain", parent)
	local rim = disc(m, pos + Vector3.new(0, 0.6, 0), 10, 1.2, RGB(250, 245, 230), Enum.Material.Marble)
	rim.CanCollide = true
	local water = disc(m, pos + Vector3.new(0, 1.25, 0), 8.6, 0.2, pal.Water or COLORS.Sky, Enum.Material.Glass)
	water.Transparency = 0.15
	column(m, pos, 4.5, 1.2, RGB(250, 245, 230), Enum.Material.Marble)
	disc(m, pos + Vector3.new(0, 4.5, 0), 3.6, 0.5, COLORS.Gold, Enum.Material.Metal)
	ball(m, pos + Vector3.new(0, 5.3, 0), 1.4, COLORS.Gold, Enum.Material.Metal)
end

THEMES.Blossom = function(ctx)
	local pal = ctx.Pal
	scatter(ctx, 10, 5, false, ctx.South, function(p, pos)
		buildSakuraTree(p, pos)
	end)
	scatter(ctx, 2, 9, false, ctx.South, function(p, pos)
		buildPond(p, pos, pal)
	end)
	scatter(ctx, 5, 1.6, false, ctx.South, function(p, pos)
		buildLantern(p, pos, RGB(255, 170, 190))
	end)
	scatter(ctx, 4, 2.2, false, ctx.South, buildBush)
	scatter(ctx, 12, 1.8, true, ctx.Field, buildFlowers)
	for _, s in outerSpots(ctx, 4, 30, 55, 30) do
		buildHill(ctx.Deco, s, Vector3.new(rng:NextNumber(50, 62), rng:NextNumber(26, 36), rng:NextNumber(40, 54)), pick({ RGB(150, 215, 130), RGB(255, 200, 220) }), Enum.Material.Grass)
	end
	for _, s in outerSpots(ctx, 10, 3, 35, 2.5) do
		buildLilyPad(ctx.Deco, Vector3.new(s.X, SEA_Y, s.Z))
	end
	skyParticles(ctx, {
		Rate = 14,
		Lifetime = NumberRange.new(14, 18),
		Speed = NumberRange.new(3, 4.5),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new(0.5),
		Color = ColorSequence.new(RGB(255, 190, 215), RGB(255, 230, 240)),
		RotSpeed = NumberRange.new(-60, 60),
	})
	skyClouds(ctx, 2)
end

THEMES.Dino = function(ctx)
	scatter(ctx, 7, 5, false, ctx.South, function(p, pos)
		buildPalm(p, pos)
	end)
	scatter(ctx, 7, 3, false, ctx.South, buildFern)
	scatter(ctx, 3, 6, false, ctx.South, buildBones)
	scatter(ctx, 3, 3.6, false, ctx.South, buildDinoEgg)
	scatter(ctx, 4, 2.4, false, ctx.South, function(p, pos)
		buildRock(p, pos, RGB(150, 140, 125), RGB(110, 175, 85))
	end)
	scatter(ctx, 8, 1.6, true, ctx.Field, buildFern)
	local spots = outerSpots(ctx, 5, 30, 60, 32)
	for i, s in spots do
		if i == 1 then
			buildVolcanoMountain(ctx.Deco, s, rng:NextNumber(60, 70), rng:NextNumber(40, 50))
		else
			buildHill(ctx.Deco, s, Vector3.new(rng:NextNumber(50, 64), rng:NextNumber(36, 56), rng:NextNumber(44, 58)), pick({ RGB(70, 150, 75), RGB(95, 165, 80) }), Enum.Material.LeafyGrass)
		end
	end
	skyClouds(ctx, 2)
end

THEMES.Crystal = function(ctx)
	scatter(ctx, 9, 3.4, false, ctx.South, function(p, pos)
		buildBigCrystal(p, pos)
	end)
	scatter(ctx, 4, 2.6, false, ctx.South, buildGeode)
	scatter(ctx, 5, 1.6, false, ctx.South, buildMushroom)
	scatter(ctx, 4, 2.4, false, ctx.South, function(p, pos)
		buildRock(p, pos, RGB(95, 85, 115), nil)
	end)
	scatter(ctx, 10, 1.6, true, ctx.Field, function(p, pos)
		buildSpaceCrystal(p, pos, ctx.Pal)
	end)
	-- 바다 위 큰 동굴 바위 (보석이 박힌 어두운 산)
	for _, s in outerSpots(ctx, 5, 30, 60, 32) do
		local w = rng:NextNumber(50, 66)
		blob(ctx.Deco, Vector3.new(s.X, SEA_Y, s.Z), Vector3.new(w, rng:NextNumber(50, 80), w * 0.85), RGB(80, 70, 100), Enum.Material.Slate).Name = "CaveRock"
		buildBigCrystal(ctx.Deco, Vector3.new(s.X, SEA_Y + 12, s.Z) + (ctx.Def.Center - s).Unit * w * 0.3, 2.6)
	end
	skyParticles(ctx, {
		Rate = 6,
		Lifetime = NumberRange.new(10, 14),
		Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(40, 40),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(RGB(150, 255, 245), RGB(220, 170, 255)),
		LightEmission = 1,
	})
end

THEMES.Desert = function(ctx)
	local pal = ctx.Pal
	scatter(ctx, 9, 2.6, false, ctx.South, buildCactus)
	scatter(ctx, 5, 5, false, ctx.South, function(p, pos)
		buildPalm(p, pos)
	end)
	scatter(ctx, 2, 9, false, ctx.South, function(p, pos)
		buildPond(p, pos, pal) -- 오아시스
	end)
	scatter(ctx, 4, 2.4, false, ctx.South, function(p, pos)
		buildRock(p, pos, RGB(210, 170, 120), nil)
	end)
	scatter(ctx, 8, 1.2, true, ctx.Field, buildShell)
	local spots = outerSpots(ctx, 5, 35, 60, 32)
	for i, s in spots do
		if i <= 2 then
			buildPyramid(ctx.Deco, s, rng:NextNumber(46, 60))
		else
			buildHill(ctx.Deco, s, Vector3.new(rng:NextNumber(55, 70), rng:NextNumber(20, 30), rng:NextNumber(40, 55)), RGB(240, 210, 150), Enum.Material.Sand)
		end
	end
	skyClouds(ctx, 1)
end

THEMES.Toy = function(ctx)
	-- 케이크처럼 장난감 블록 띠 (섬 가장자리)
	local def = ctx.Def
	newPart(ctx.Folder, Vector3.new(def.Size.X + 3.4, 0.8, def.Size.Z + 3.4), CFrame.new(def.Center.X, -1.6, def.Center.Z), RGB(255, 210, 60)).Name = "ToyBand"
	scatter(ctx, 9, 3, false, ctx.South, function(p, pos)
		buildToyBlocks(p, pos)
	end)
	scatter(ctx, 5, 2.4, false, ctx.South, buildBalloons)
	scatter(ctx, 4, 2.6, false, ctx.South, buildSpinningTop)
	scatter(ctx, 5, 2, false, ctx.South, buildToyBall)
	local castle = findSpot(ctx, 9, false, ctx.South)
	if castle then
		buildCastle(ctx.Deco, castle)
	end
	scatter(ctx, 8, 1.2, true, ctx.Field, buildGumDrop)
	for _, s in outerSpots(ctx, 5, 25, 55, 14) do
		buildToyBlocks(ctx.Deco, Vector3.new(s.X, SEA_Y, s.Z), rng:NextNumber(3, 4.5))
	end
	skyClouds(ctx, 3)
end

THEMES.Dream = function(ctx)
	local def = ctx.Def
	scatter(ctx, 6, 4, false, ctx.South, function(p, pos)
		buildCloudPuff(p, pos)
	end)
	scatter(ctx, 6, 3.4, false, ctx.South, buildPillow)
	scatter(ctx, 6, 1.6, false, ctx.South, buildMoonLamp)
	scatter(ctx, 8, 1.2, true, ctx.Field, buildGumDrop)
	-- 들판 위에 떠 있는 별
	local t = def.Trail
	local placed = 0
	for _ = 1, 60 do
		if placed >= 9 then
			break
		end
		local x = rng:NextNumber(ctx.Field.MinX + 6, ctx.Field.MaxX - 6)
		local z = rng:NextNumber(ctx.Field.MinZ + 6, ctx.Field.MaxZ - 6)
		local v = (Vector3.new(x, 0, z) - t.To):Dot(t.Side)
		if math.abs(v) > HALF_TRAIL + 6 then
			buildStar(ctx.Deco, Vector3.new(x, rng:NextNumber(9, 16), z), rng:NextNumber(1.6, 2.4), pick({ COLORS.Gold, RGB(200, 210, 255) }))
			placed += 1
		end
	end
	-- 큰 달 + 구름 + 하늘 별
	local moonAt = def.Center + outward(ctx) * def.Size.X + Vector3.new(0, 80, 0)
	local moon = ball(ctx.Deco, moonAt, 34, RGB(255, 240, 180), Enum.Material.Neon)
	moon.Name = "Moon"
	moon.CastShadow = false
	ball(ctx.Deco, moonAt + Vector3.new(9, 6, -6), 30, RGB(45, 45, 100)).CastShadow = false -- 초승달로 가려요
	for _, s in outerSpots(ctx, 6, 20, 60, 12) do
		buildCloud(ctx.Deco, Vector3.new(s.X, rng:NextNumber(0, 10), s.Z), RGB(200, 200, 245))
	end
	for _ = 1, 12 do
		local s = ball(ctx.Deco, Vector3.new(def.Center.X + rng:NextNumber(-140, 140), rng:NextNumber(45, 90), def.Center.Z + rng:NextNumber(-140, 140)), rng:NextNumber(0.6, 1.4), pick({ COLORS.White, RGB(255, 240, 160), RGB(200, 210, 255) }), Enum.Material.Neon)
		s.CastShadow = false
	end
end

THEMES.Volcano = function(ctx)
	scatter(ctx, 4, 6, false, ctx.South, buildLavaPool)
	scatter(ctx, 7, 2.2, false, ctx.South, buildObsidian)
	scatter(ctx, 6, 2.4, false, ctx.South, function(p, pos)
		buildRock(p, pos, RGB(70, 58, 62), nil)
	end)
	scatter(ctx, 8, 1.4, true, ctx.Field, buildObsidian)
	for i, s in outerSpots(ctx, 4, 35, 65, 34) do
		buildVolcanoMountain(ctx.Deco, s, rng:NextNumber(60, 76), rng:NextNumber(45, 62) * (if i == 1 then 1.3 else 1))
	end
	skyParticles(ctx, {
		Rate = 10,
		Lifetime = NumberRange.new(8, 12),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(RGB(255, 200, 80), RGB(255, 90, 40)),
		LightEmission = 1,
	})
end

THEMES.Gold = function(ctx)
	local pal = ctx.Pal
	scatter(ctx, 5, 2, false, ctx.South, buildPillar)
	scatter(ctx, 5, 3, false, ctx.South, buildCoinPile)
	scatter(ctx, 4, 2.8, false, ctx.South, buildTreasure)
	scatter(ctx, 2, 6, false, ctx.South, function(p, pos)
		buildFountain(p, pos, pal)
	end)
	scatter(ctx, 6, 4.5, false, ctx.South, function(p, pos)
		buildTree(p, pos, { RGB(255, 215, 90), RGB(255, 235, 150), RGB(250, 200, 70) })
	end)
	local castle = findSpot(ctx, 9, false, ctx.South)
	if castle then
		buildCastle(ctx.Deco, castle, 1.2)
	end
	scatter(ctx, 8, 1.4, true, ctx.Field, function(p, pos)
		buildStar(p, pos + Vector3.new(0, 1.4, 0), 1.4)
	end)
	-- 바다 위 큰 황금 성
	local big = outerSpots(ctx, 1, 40, 60, 32)[1]
	if big then
		blob(ctx.Deco, big + Vector3.new(0, SEA_Y, 0), Vector3.new(60, 14, 44), RGB(250, 240, 205), Enum.Material.Sand).Name = "CastleIsland"
		buildCastle(ctx.Deco, big + Vector3.new(0, 3, 0), 2.4)
	end
	for _, s in outerSpots(ctx, 3, 25, 55, 14) do
		buildCoinPile(ctx.Deco, Vector3.new(s.X, SEA_Y, s.Z))
	end
	skyClouds(ctx, 3, RGB(255, 245, 215))
end

----------------------------------------------------------------------
-- 조명
----------------------------------------------------------------------

local function setupLighting()
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 25
	Lighting.Brightness = 2.4
	Lighting.Ambient = RGB(150, 145, 160)
	Lighting.OutdoorAmbient = RGB(185, 175, 195)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.28 -- 반짝 비치는 빛 (금속·유리 펫이 살랑살랑 돌 때 번쩍이지 않게, 0.4 → 0.28)
	Lighting.ExposureCompensation = 0.1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.FogEnd = 100000

	-- 기존 효과 정리 (Sky 는 그대로 둬요)
	for _, c in Lighting:GetChildren() do
		if c:IsA("Atmosphere") or c:IsA("ColorCorrectionEffect") or c:IsA("BloomEffect") or c:IsA("DepthOfFieldEffect") then
			c:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.18
	atmosphere.Offset = 0.2
	atmosphere.Color = RGB(255, 228, 242)
	atmosphere.Decay = RGB(200, 210, 255)
	atmosphere.Glare = 0.05
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "PastelColor" -- ZoneClient 가 지역마다 살짝 물들여요
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.Brightness = 0.02
	cc.TintColor = RGB(255, 250, 252)
	cc.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "SoftBloom"
	-- 네온·반짝이가 번지는 정도. 집 안에 빛나는 게 많이 모이면 번쩍번쩍 눈부셔서 약하게
	-- (0.35 / 24 / 1.6 → 0.28 / 24 / 1.8 → 0.18 / 20 / 2.1)
	bloom.Intensity = 0.18
	bloom.Size = 20
	bloom.Threshold = 2.1
	bloom.Parent = Lighting
end

----------------------------------------------------------------------

-- 지역 k 울타리에서 비울 곳: 자기 길 끝 + 여기서 시작하는 길 (★v8 Zone.Parent == k, 숲 마을은 안쪽 섬 7개)
local function fenceGaps(k: number): { Vector3 }
	local gaps: { Vector3 } = {}
	if Zones[k].Trail then
		table.insert(gaps, Zones[k].Trail.To)
	end
	for j = 2, Config.MaxZone do
		local t = Zones[j].Trail
		if t and Zones[j].Parent == k then
			table.insert(gaps, t.From)
		end
	end
	return gaps
end

local function newCtx(k: number, world: Instance): Ctx
	local def = Zones[k]
	local m = model("Zone" .. k, world)
	m:SetAttribute("ZoneIndex", k)
	local r = zoneRect(def)
	local fieldMin, fieldMax = def.FieldMin, def.FieldMax
	local ctx: Ctx = {
		Index = k,
		Def = def,
		Pal = def.Palette,
		Folder = m,
		Deco = folder("Decorations", m),
		Rect = r,
		Field = rect(fieldMin.X, fieldMax.X, fieldMin.Z, fieldMax.Z),
		South = r, -- 큰 장식 자리: 섬 전체에서 코인 들판·길·컨베이어(Blocks)를 뺀 곳 (컨베이어 뒤 띠, 섬 맨 끝 띠)
		Blocks = {},
		Circles = {},
		Placed = {},
		Exits = {},
	}
	for j = 2, Config.MaxZone do
		local t = Zones[j].Trail
		if t and Zones[j].Parent == k then
			table.insert(ctx.Exits, t.From)
		end
	end
	return ctx
end

function WorldBuilder.Build()
	-- 기본 바닥/스폰 제거, 이전 월드 제거
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") or child.Name == "World" then
			child:Destroy()
		end
	end

	partCount = 0
	local world = Instance.new("Folder")
	world.Name = "World"

	-- 바다 장식이 피해야 하는 곳: 땅 + 길 (+ 문 아치)
	table.clear(seaBlocks)
	table.clear(seaPlaced)
	for k = 1, Config.MaxZone do
		table.insert(seaBlocks, zoneRect(Zones[k]))
		local t = Zones[k].Trail
		if t then
			table.insert(seaBlocks, stripRect(t.From, t.To, HALF_TRAIL + 6))
		end
	end

	local counts: { string } = {}
	for k = 1, Config.MaxZone do
		local before = partCount
		local ctx = newCtx(k, world)
		buildIsland(ctx)
		buildIslandFence(ctx, fenceGaps(k))
		if k == 1 then
			buildHome(ctx)
		else
			buildZoneRoads(ctx)
		end
		local theme = THEMES[ctx.Def.Id]
		if theme then
			theme(ctx)
		end
		local n = partCount - before
		counts[k] = tostring(n)
		if n > ZONE_PART_WARN + (if k == 1 then 200 else 0) then
			warn(("[WorldBuilder] 지역 %d 파트가 많아요: %d"):format(k, n))
		end
	end

	local before = partCount
	local trails = folder("Trails", world)
	local gates = folder("Gates", world)
	for k = 2, Config.MaxZone do
		buildTrail(trails, k)
		buildGate(trails, gates, k)
	end
	buildSea(world)
	local shared = partCount - before

	world.Parent = workspace
	setupLighting()

	print(("[WorldBuilder] 월드 완성! 파트 %d개 (지역별 %s, 다리·문·바다 %d)"):format(partCount, table.concat(counts, "/"), shared))
end

return WorldBuilder
