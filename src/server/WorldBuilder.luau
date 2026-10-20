-- 귀여운 파스텔 월드 (v3): 지역 8개 섬 + 섬 사이 다리 + 지역 문(Gate) + 테마 장식 + 로비 + 바다 + 조명
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

-- 섬 둘레 울타리 (서쪽/동쪽 길 입구 |z| ≤ 길 폭/2 는 비워요)
local function buildIslandFence(ctx: Ctx, westGap: boolean, eastGap: boolean)
	local f = folder("Fence", ctx.Folder)
	local r = ctx.Rect
	local pal = ctx.Pal
	local every = 30
	local rail = lighten(pal.Trim, 0.35)
	local function line(x0: number, z0: number, x1: number, z1: number)
		fenceLine(f, Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z1), pal.Trim, pal.Accent, rail, every)
	end
	line(r.MinX, r.MaxZ, r.MaxX, r.MaxZ)
	line(r.MinX, r.MinZ, r.MaxX, r.MinZ)
	for _, side in { { X = r.MinX, Gap = westGap }, { X = r.MaxX, Gap = eastGap } } do
		if side.Gap then
			line(side.X, r.MinZ, side.X, -HALF_TRAIL)
			line(side.X, HALF_TRAIL, side.X, r.MaxZ)
		else
			line(side.X, r.MinZ, side.X, r.MaxZ)
		end
	end
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

-- 다리 (지역 k-1 동쪽 끝 → 지역 k 서쪽 끝)
local function buildTrail(parent: Instance, k: number)
	local prev, def = Zones[k - 1], Zones[k]
	local pal = def.Palette
	local x0 = prev.Center.X + prev.Size.X / 2
	local x1 = def.Center.X - def.Size.X / 2
	local m = model("Trail" .. k, parent)
	local deck = flatRect(m, x0 - 1, x1 + 1, -HALF_TRAIL, HALF_TRAIL, 0.16, lighten(pal.Trim, 0.25), Enum.Material.WoodPlanks)
	deck.Name = "Deck"
	-- 물속 다리 기둥
	for _, sz in { -1, 1 } do
		column(m, Vector3.new((x0 + x1) / 2, SEA_Y - 8, sz * (HALF_TRAIL - 2)), 8, 2.4, darken(pal.Trim, 0.15))
	end
	-- 양옆 난간 (높이 ≥ 4) + 투명 벽
	for _, sz in { -1, 1 } do
		fenceLine(
			m,
			Vector3.new(x0, 0, sz * (HALF_TRAIL + 0.5)),
			Vector3.new(x1, 0, sz * (HALF_TRAIL + 0.5)),
			pal.Trim,
			pal.Accent,
			COLORS.White,
			17
		)
	end
end

-- 지역 문: 아치 + 큰 간판 + 막는 판 (Gates/Gate<k>)
local function buildGate(arches: Instance, gates: Instance, k: number)
	local def = Zones[k]
	local gateDef = def.Gate
	if not gateDef then
		return
	end
	local pal = def.Palette
	local gx = gateDef.CFrame.Position.X
	local pillarZ = gateDef.Size.Z / 2 + 1.6
	local m = model("Arch" .. k, arches)
	local ringH = 4
	local rings = math.ceil(ARCH_BEAM_Y / ringH)
	for _, sz in { -1, 1 } do
		for i = 0, rings - 1 do
			local p = column(m, Vector3.new(gx, i * ringH, sz * pillarZ), ringH, 2.6, if i % 2 == 0 then pal.Accent else COLORS.White)
			p.CanCollide = true
		end
		ball(m, Vector3.new(gx, rings * ringH + 2.6 + 3.2, sz * pillarZ), 2.6, pal.Trim)
	end
	local beamY = rings * ringH
	local beam = newPart(m, Vector3.new(2.6, 2, pillarZ * 2 + 3), CFrame.new(gx, beamY + 1, 0), pal.Trim)
	beam.CanCollide = true
	-- 큰 간판: 앞면은 서쪽(들어오는 사람), 뒷면은 지역 안쪽
	local signY = beamY + 2 + 3.6
	local sign = newPart(m, Vector3.new(26, 7, 0.8), CFrame.lookAt(Vector3.new(gx, signY, 0), Vector3.new(gx - 10, signY, 0)), pal.Accent)
	sign.Name = "ZoneSign"
	local stroke = darken(pal.Accent, 0.25)
	local front = signFrame(sign, Enum.NormalId.Front, 30, COLORS.Cream, stroke)
	textLabel(front, def.Emoji .. " " .. def.Name, UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.92, 0.58), stroke)
	textLabel(front, "🔄 환생 " .. def.MinRebirth .. "회", UDim2.fromScale(0.1, 0.66), UDim2.fromScale(0.8, 0.28), COLORS.Text)
	local prev = Zones[k - 1]
	local back = signFrame(sign, Enum.NormalId.Back, 30, COLORS.Cream, stroke)
	textLabel(back, def.Emoji .. " " .. def.Name, UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.92, 0.58), stroke)
	textLabel(back, "← " .. prev.Emoji .. " " .. prev.Name, UDim2.fromScale(0.1, 0.66), UDim2.fromScale(0.8, 0.28), COLORS.Text)

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
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	bb.Parent = gate
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = FONT
	label.TextScaled = true
	label.Text = "🔒 환생 " .. def.MinRebirth .. "회 필요"
	label.TextColor3 = COLORS.White
	label.TextStrokeColor3 = RGB(200, 60, 140)
	label.TextStrokeTransparency = 0
	label.Parent = bb
	gate.Parent = gates
	partCount += 1
end

-- 바다 / 구름 바다 / 우주 (CanCollide 끔: 떨어지면 ZoneService 가 스폰으로 돌려보내요)
local function buildSea(world: Instance)
	local f = folder("Sea", world)
	local zDepth = 900
	local function plane(x0: number, x1: number, top: number, color: Color3, transparency: number, material: Enum.Material?)
		local p = newPart(f, Vector3.new(x1 - x0, 1, zDepth), CFrame.new((x0 + x1) / 2, top - 0.5, 0), color, nil, material)
		p.Transparency = transparency
		p.CastShadow = false
		return p
	end
	-- 지역 1~6: 물 (길이 2048 을 넘지 않게 나눠요)
	local waterEnd = Zones[6].Center.X + 125
	local water = plane(-460, waterEnd, SEA_Y, Zones[2].Palette.Water or RGB(90, 180, 235), 0.2)
	water.Name = "Water"
	water.Reflectance = 0.12
	plane(-460, waterEnd, SEA_Y - 9, RGB(45, 120, 185), 0).Name = "SeaBed"
	-- 지역 7: 구름 바다
	local cloudEnd = Zones[7].Center.X + 125
	plane(waterEnd, cloudEnd, SEA_Y - 1, RGB(250, 248, 255), 0.1).Name = "CloudSea"
	plane(waterEnd, cloudEnd, SEA_Y - 10, RGB(215, 205, 255), 0).Name = "CloudBed"
	-- 지역 8: 우주
	local spaceEnd = Zones[8].Center.X + 340
	local void = plane(cloudEnd, spaceEnd, SEA_Y - 8, RGB(18, 14, 45), 0)
	void.Name = "SpaceVoid"
	emitter(void, {
		Rate = 25,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(0, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(RGB(255, 255, 255), RGB(180, 200, 255)),
		LightEmission = 1,
		EmissionDirection = Enum.NormalId.Top,
	})
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
	local east = ctx.Rect.MaxX
	local pathColor, sideColor = pal.Path, COLORS.PathDark

	-- 로비 → 알 공장 큰길, 컨베이어 양옆 산책로, 알 통을 돌아서 지역 2 다리까지 큰길
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
	for _, side in { 1, -1 } do
		flatRect(paths, plotMinX, plotMaxX, side * (rowFront - 5), side * (rowFront - 1), 0.12, pathColor)
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
		table.insert(blocks, rect(plotMinX - 2, plotMaxX + 2, math.min(side * (rowFront - 7), side * rowFront), math.max(side * (rowFront - 7), side * rowFront)))
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
	-- 울타리 밖 언덕
	local hills = folder("Hills", ctx.Folder)
	local spots = {
		Vector3.new(-238, 0, -60),
		Vector3.new(-240, 0, 55),
		Vector3.new(-150, 0, 165),
		Vector3.new(-40, 0, 170),
		Vector3.new(80, 0, 165),
		Vector3.new(-120, 0, -168),
		Vector3.new(10, 0, -172),
		Vector3.new(100, 0, -165),
	}
	for _, s in spots do
		local c = pick(BUSH_COLORS):Lerp(COLORS.Lemon, rng:NextNumber(0, 0.2))
		buildHill(hills, s, Vector3.new(rng:NextNumber(50, 80), rng:NextNumber(26, 40), rng:NextNumber(45, 70)), c, Enum.Material.Grass)
	end
end

----------------------------------------------------------------------
-- 지역 2~8 공통: 큰길, 컨베이어 앞 산책로, 스폰 자리
----------------------------------------------------------------------

local function buildZoneRoads(ctx: Ctx)
	local def, pal = ctx.Def, ctx.Pal
	local f = folder("Paths", ctx.Folder)
	local r = ctx.Rect
	local cx = def.Center.X
	local last = ctx.Index >= Config.MaxZone
	local roadEnd = if last then cx + 66 else r.MaxX + 1
	flatRect(f, r.MinX - 1, roadEnd, -HALF_TRAIL, HALF_TRAIL, 0.1, pal.Path)
	if last then
		-- 마지막 지역: 길 끝 동그란 광장
		disc(f, Vector3.new(roadEnd, 0.06, 0), 26, 0.3, pal.Path, Enum.Material.Sand).CanCollide = true
		-- 네온 길 테두리
		for _, sz in { -1, 1 } do
			local strip = newPart(f, Vector3.new(roadEnd - r.MinX, 0.1, 0.5), CFrame.new((r.MinX + roadEnd) / 2, 0.15, sz * (HALF_TRAIL - 0.3)), pal.Accent, nil, Enum.Material.Neon)
			strip.CastShadow = false
		end
	end
	-- 컨베이어 앞 산책로 + 큰길에서 내려가는 길
	local cs, ce = def.ConveyorStart, def.ConveyorEnd
	local wz = cs.Z + 8
	flatRect(f, cs.X - 10, ce.X + 10, wz - 3, wz + 3, 0.12, pal.Path)
	flatRect(f, cs.X - 15, cs.X - 7, wz, -HALF_TRAIL + 0.5, 0.14, darken(pal.Path, 0.05))
	-- 스폰 자리 (납작한 원판 2장)
	local sp = def.Spawn
	disc(f, Vector3.new(sp.X, 0.08, sp.Z), 12, 0.3, pal.Accent).CanCollide = true
	disc(f, Vector3.new(sp.X, 0.12, sp.Z), 6, 0.3, lighten(pal.Path, 0.4)).CanCollide = true

	-- 장식 금지 구역
	local blocks = ctx.Blocks
	table.insert(blocks, rect(r.MinX, roadEnd + 13, -HALF_TRAIL - 2, HALF_TRAIL + 2))
	table.insert(blocks, rect(cs.X - 12, ce.X + 14, cs.Z - 10, wz + 4))
	table.insert(blocks, rect(cs.X - 17, cs.X - 5, wz, -HALF_TRAIL))
	table.insert(blocks, rect(r.MinX, r.MinX + 14, -18, 18)) -- 문 아치 앞
	table.insert(ctx.Circles, { X = sp.X, Z = sp.Z, R = 10 })
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

-- 섬 밖 배경 자리 (북쪽/남쪽 바다 위)
local function backdropSpots(ctx: Ctx, n: number, minDist: number, maxDist: number): { Vector3 }
	local cx = ctx.Def.Center.X
	local list = {}
	for i = 1, n do
		local north = i % 2 == 0
		local x = cx + (i / (n + 1) - 0.5) * 220 + rng:NextNumber(-15, 15)
		local z = (if north then 1 else -1) * (ctx.Rect.MaxZ + rng:NextNumber(minDist, maxDist))
		table.insert(list, Vector3.new(x, 0, z))
	end
	return list
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
	-- 바다 위 연잎
	for i = 1, 14 do
		local north = i % 2 == 0
		local x = ctx.Def.Center.X + rng:NextNumber(-115, 115)
		local z = (if north then 1 else -1) * (ctx.Rect.MaxZ + rng:NextNumber(5, 40))
		buildLilyPad(ctx.Deco, Vector3.new(x, SEA_Y, z))
	end
	for _, s in backdropSpots(ctx, 5, 30, 60) do
		buildHill(ctx.Deco, s, Vector3.new(rng:NextNumber(50, 75), rng:NextNumber(24, 36), rng:NextNumber(40, 60)), pick(GREEN_CROWNS), Enum.Material.Grass)
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
	local hills = backdropSpots(ctx, 5, 30, 55)
	for _, s in hills do
		buildHill(ctx.Deco, s, Vector3.new(rng:NextNumber(55, 80), rng:NextNumber(40, 60), rng:NextNumber(45, 60)), pick({ RGB(70, 160, 80), RGB(90, 175, 85) }), Enum.Material.LeafyGrass)
	end
	-- 폭포 (북쪽 언덕 하나)
	local h = hills[2]
	if h then
		local fall = newPart(ctx.Deco, Vector3.new(6, 24, 1), CFrame.new(h.X, SEA_Y + 11, h.Z - 20), RGB(170, 225, 255), nil, Enum.Material.Glass)
		fall.Transparency = 0.3
		fall.Name = "Waterfall"
		blob(ctx.Deco, Vector3.new(h.X, SEA_Y + 0.5, h.Z - 22), Vector3.new(10, 3, 6), COLORS.White).Name = "Foam"
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
	for _, s in backdropSpots(ctx, 6, 40, 70) do
		buildMountain(ctx.Deco, s, rng:NextNumber(60, 85), rng:NextNumber(40, 62))
	end
	-- 바다 위 빙산
	for i = 1, 4 do
		local z = (if i % 2 == 0 then 1 else -1) * (ctx.Rect.MaxZ + rng:NextNumber(10, 25))
		blob(ctx.Deco, Vector3.new(ctx.Def.Center.X + rng:NextNumber(-90, 90), SEA_Y, z), Vector3.new(rng:NextNumber(8, 14), rng:NextNumber(5, 9), rng:NextNumber(8, 12)), RGB(225, 240, 255), Enum.Material.Ice).Name = "Iceberg"
	end
	-- 눈 내리기
	local snow = newPart(ctx.Deco, Vector3.new(ctx.Def.Size.X, 1, ctx.Def.Size.Z), CFrame.new(ctx.Def.Center.X, 70, 0), COLORS.White)
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
	-- 바다 속 산호 (물 위로 살짝)
	for i = 1, 4 do
		local z = (if i % 2 == 0 then 1 else -1) * (ctx.Rect.MaxZ + rng:NextNumber(8, 30))
		buildCoral(ctx.Deco, Vector3.new(ctx.Def.Center.X + rng:NextNumber(-90, 90), SEA_Y - 2.5, z))
	end
	buildLighthouse(ctx.Deco, Vector3.new(ctx.Def.Center.X + 60, 0, ctx.Rect.MaxZ + 45))
	-- 야자수 작은 섬
	local islet = Vector3.new(ctx.Def.Center.X - 50, 0, ctx.Rect.MinZ - 40)
	blob(ctx.Deco, Vector3.new(islet.X, SEA_Y, islet.Z), Vector3.new(22, 5, 18), pal.Ground, Enum.Material.Sand).Name = "Islet"
	buildPalm(ctx.Deco, islet + Vector3.new(0, SEA_Y + 2, 0), 1.3)
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
	for _, s in backdropSpots(ctx, 4, 30, 55) do
		buildHill(ctx.Deco, s, Vector3.new(rng:NextNumber(45, 70), rng:NextNumber(26, 40), rng:NextNumber(40, 60)), pick({ RGB(255, 190, 220), RGB(190, 240, 215), RGB(255, 245, 250) }))
	end
	-- 바다에 꽂힌 큰 막대사탕
	for _, s in backdropSpots(ctx, 4, 12, 22) do
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
	-- 섬 둘레 몽글몽글 구름
	local r = ctx.Rect
	for i = 0, 9 do
		local t = i / 10
		local x = r.MinX + (r.MaxX - r.MinX) * ((t * 2) % 1)
		local z = if t < 0.5 then r.MaxZ + 3 else r.MinZ - 3
		blob(ctx.Folder, Vector3.new(x + 10, -1.5, z), Vector3.new(34, 9, 16), RGB(250, 248, 255)).Name = "EdgeCloud"
	end
	scatter(ctx, 6, 4, false, ctx.South, function(p, pos)
		buildCloudPuff(p, pos)
	end)
	-- 큰길 위 무지개 다리 (파트는 안 막아요)
	buildRainbowArc(ctx.Deco, Vector3.new(def.Center.X - 30, 0, 0), 16, Vector3.zAxis, 5, 7)
	scatter(ctx, 5, 2, false, ctx.South, buildPillar)
	local castle = findSpot(ctx, 9, false, ctx.South)
	if castle then
		buildCastle(ctx.Deco, castle)
	end
	-- 들판 위에 떠 있는 별 (높이 떠 있어서 코인 자리를 막지 않아요)
	for _ = 1, 9 do
		local x = rng:NextNumber(ctx.Field.MinX + 6, ctx.Field.MaxX - 6)
		local z = rng:NextNumber(HALF_TRAIL + 6, ctx.Field.MaxZ - 6)
		buildStar(ctx.Deco, Vector3.new(x, rng:NextNumber(9, 16), z), rng:NextNumber(1.6, 2.4))
	end
	-- 큰 구름 위 성 (북쪽 배경)
	local bigCloud = Vector3.new(def.Center.X + 30, 0, r.MaxZ + 55)
	blob(ctx.Deco, bigCloud + Vector3.new(0, 2, 0), Vector3.new(60, 12, 40), COLORS.White).Name = "BigCloud"
	buildCastle(ctx.Deco, bigCloud + Vector3.new(0, 6, 0), 2)
	for _, s in backdropSpots(ctx, 5, 25, 60) do
		buildCloud(ctx.Deco, Vector3.new(s.X, rng:NextNumber(0, 8), s.Z))
	end
	skyClouds(ctx, 3, RGB(245, 240, 255))
end

THEMES.Space = function(ctx)
	local pal = ctx.Pal
	local def = ctx.Def
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
	-- 떠 있는 작은 행성
	for _ = 1, 4 do
		local x = def.Center.X + rng:NextNumber(-90, 90)
		local z = rng:NextNumber(-95, -70)
		buildPlanet(ctx.Deco, Vector3.new(x, rng:NextNumber(14, 24), z), rng:NextNumber(3, 6), rng:NextNumber() < 0.5)
	end
	-- 큰 행성 / 달 (배경)
	for i, s in backdropSpots(ctx, 6, 40, 90) do
		buildPlanet(ctx.Deco, Vector3.new(s.X, rng:NextNumber(20, 60), s.Z), rng:NextNumber(16, 34), i % 2 == 0)
	end
	local moon = ball(ctx.Deco, Vector3.new(def.Center.X - 40, 95, -def.Size.Z), 30, RGB(255, 245, 200), Enum.Material.Neon)
	moon.Name = "Moon"
	moon.CastShadow = false
	-- 하늘 별
	for _ = 1, 10 do
		local s = ball(ctx.Deco, Vector3.new(def.Center.X + rng:NextNumber(-140, 140), rng:NextNumber(45, 90), rng:NextNumber(-140, 140)), rng:NextNumber(0.6, 1.4), pick({ COLORS.White, RGB(255, 240, 160), RGB(170, 220, 255) }), Enum.Material.Neon)
		s.CastShadow = false
	end
	-- 동쪽 끝 너머: 발사대 위 큰 로켓
	local padPos = Vector3.new(def.Center.X + def.Size.X / 2 + 34, 0, 0)
	disc(ctx.Deco, padPos + Vector3.new(0, -1.5, 0), 30, 3, RGB(120, 115, 150), Enum.Material.Metal).Name = "LaunchPad"
	disc(ctx.Deco, padPos + Vector3.new(0, 0.05, 0), 18, 0.2, pal.Accent, Enum.Material.Neon).CastShadow = false
	buildRocket(ctx.Deco, padPos, 3)
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
	Lighting.EnvironmentSpecularScale = 0.4
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
	atmosphere.Glare = 0.1
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
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
end

----------------------------------------------------------------------

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
		South = rect(r.MinX, r.MaxX, r.MinZ, math.min(fieldMin.Z, def.ConveyorStart.Z + 12)),
		Blocks = {},
		Circles = {},
		Placed = {},
	}
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

	local counts: { string } = {}
	for k = 1, Config.MaxZone do
		local before = partCount
		local ctx = newCtx(k, world)
		buildIsland(ctx)
		buildIslandFence(ctx, k > 1, k < Config.MaxZone)
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
