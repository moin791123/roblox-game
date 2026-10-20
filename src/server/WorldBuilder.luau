-- 귀여운 파스텔 월드: 잔디 땅, 길, 막대사탕 나무, 꽃, 버섯, 덤불, 구름, 무지개, 로비, 표지판, 울타리, 조명
-- 기지/컨베이어/코인은 다른 서비스가 만들어요. 여기서는 그 자리를 비워 둬요.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

local Layout = Config.Layout
local HALF_PLOT = Layout.PlotSize / 2
local LOBBY = Layout.LobbySpawn

-- 울타리(맵 경계)
local BOUND_X_MIN = -132
local BOUND_X_MAX = 100
local BOUND_Z = 98

-- 길
local WALK_IN = 6 -- 컨베이어 옆 산책로 안쪽 |z|
local WALK_OUT = 11 -- 산책로 바깥쪽 |z|
local PATH_W = 9 -- 기지 입구 길 폭
local PLAZA_R = 17 -- 로비 광장 반지름
local RAINBOW_X = LOBBY.X + 6 -- 무지개 아치 위치 (x 평면)
local RAINBOW_R = 24
local FACTORY_X = Layout.ConveyorStart.X -- "알 공장" 아치 (알 슈트를 감싸는 높은 문)

local FONT = Enum.Font.FredokaOne

local COLORS = {
	Grass = Color3.fromRGB(125, 210, 105),
	Path = Color3.fromRGB(250, 232, 198),
	PathDark = Color3.fromRGB(238, 212, 172),
	Cream = Color3.fromRGB(255, 250, 240),
	White = Color3.fromRGB(255, 255, 255),
	Pink = Color3.fromRGB(255, 160, 200),
	HotPink = Color3.fromRGB(255, 105, 170),
	Mint = Color3.fromRGB(160, 235, 205),
	Lavender = Color3.fromRGB(205, 180, 255),
	Peach = Color3.fromRGB(255, 200, 165),
	Lemon = Color3.fromRGB(255, 240, 150),
	Sky = Color3.fromRGB(165, 215, 255),
	Trunk = Color3.fromRGB(205, 155, 115),
	Text = Color3.fromRGB(110, 70, 120),
}

local CROWN_COLORS = {
	Color3.fromRGB(255, 180, 210),
	Color3.fromRGB(160, 235, 200),
	Color3.fromRGB(210, 185, 255),
	Color3.fromRGB(255, 200, 160),
	Color3.fromRGB(255, 240, 150),
	Color3.fromRGB(170, 215, 255),
	Color3.fromRGB(145, 220, 125),
}

local FLOWER_COLORS = {
	Color3.fromRGB(255, 150, 190),
	Color3.fromRGB(255, 230, 110),
	Color3.fromRGB(200, 160, 255),
	Color3.fromRGB(130, 200, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 180, 140),
	Color3.fromRGB(255, 115, 130),
}

local BUSH_COLORS = {
	Color3.fromRGB(110, 200, 110),
	Color3.fromRGB(130, 215, 135),
	Color3.fromRGB(100, 190, 125),
}

local CAP_COLORS = {
	Color3.fromRGB(255, 110, 120),
	Color3.fromRGB(255, 150, 200),
	Color3.fromRGB(190, 140, 255),
	Color3.fromRGB(255, 170, 90),
}

local RAINBOW_COLORS = {
	Color3.fromRGB(255, 140, 150),
	Color3.fromRGB(255, 190, 120),
	Color3.fromRGB(255, 235, 130),
	Color3.fromRGB(150, 225, 150),
	Color3.fromRGB(140, 190, 255),
	Color3.fromRGB(200, 160, 255),
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

-- 타원체 (SpecialMesh 구)
local function blob(parent: Instance, pos: Vector3, size: Vector3, color: Color3): Part
	local p = newPart(parent, size, CFrame.new(pos), color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- 세운 원기둥 (bottom = 바닥 중심)
local function column(parent: Instance, bottom: Vector3, height: number, d: number, color: Color3): Part
	return newPart(
		parent,
		Vector3.new(height, d, d),
		CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		Enum.PartType.Cylinder
	)
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

----------------------------------------------------------------------
-- 장식 위치 고르기 (기지, 컨베이어, 길, 광장은 비워 둠)
----------------------------------------------------------------------

type Spot = { x: number, z: number, r: number }
local placed: { Spot } = {}

-- 기지 입구 길 선분 (a -> b)
local entrancePaths: { { a: Vector3, b: Vector3 } } = {}
for _, cf in Layout.Plots do
	local entrance = cf.Position + cf.LookVector * HALF_PLOT
	local sign = if entrance.Z >= 0 then 1 else -1
	table.insert(entrancePaths, {
		a = Vector3.new(entrance.X, 0, entrance.Z),
		b = Vector3.new(entrance.X, 0, sign * WALK_OUT),
	})
end

local function distToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (p - (a + ab * t)).Magnitude
end

local function insidePlot(x: number, z: number, margin: number): boolean
	for _, cf in Layout.Plots do
		local lp = cf:PointToObjectSpace(Vector3.new(x, cf.Position.Y, z))
		if math.abs(lp.X) <= HALF_PLOT + margin and math.abs(lp.Z) <= HALF_PLOT + margin then
			return true
		end
	end
	return false
end

-- allowField = true 면 코인 들판 안에도 놓을 수 있음 (작은 꽃만)
local function isFree(x: number, z: number, r: number, allowField: boolean): boolean
	-- 경계 안쪽
	if x < BOUND_X_MIN + 3 + r or x > BOUND_X_MAX - 3 - r or math.abs(z) > BOUND_Z - 3 - r then
		return false
	end
	-- 컨베이어 + 산책로
	if math.abs(z) <= WALK_OUT + 1 + r and x >= Layout.ConveyorStart.X - 10 - r and x <= Layout.ConveyorEnd.X + 10 + r then
		return false
	end
	-- 코인 들판 (큰 장식 금지)
	if
		not allowField
		and x >= Layout.FieldMin.X - 4 - r
		and x <= Layout.FieldMax.X + 4 + r
		and z >= Layout.FieldMin.Z - 4 - r
		and z <= Layout.FieldMax.Z + 4 + r
	then
		return false
	end
	-- 기지
	if insidePlot(x, z, (if allowField then 1.5 else 3) + r) then
		return false
	end
	-- 기지 입구 길
	local p = Vector3.new(x, 0, z)
	for _, seg in entrancePaths do
		if distToSegment(p, seg.a, seg.b) <= PATH_W / 2 + 1 + r then
			return false
		end
	end
	-- 로비 광장
	local dx, dz = x - LOBBY.X, z - LOBBY.Z
	if dx * dx + dz * dz <= (PLAZA_R + 2 + r) ^ 2 then
		return false
	end
	-- 무지개 / 공장 아치 / 연결길
	if x >= RAINBOW_X - 4 - r and x <= FACTORY_X + 8 + r and math.abs(z) <= RAINBOW_R + 4 + r then
		return false
	end
	-- 이미 놓은 장식
	for _, s in placed do
		local sx, sz = s.x - x, s.z - z
		if sx * sx + sz * sz < (s.r + r) ^ 2 then
			return false
		end
	end
	return true
end

local function findSpot(r: number, allowField: boolean, tries: number): Vector3?
	for _ = 1, tries do
		local x = rng:NextNumber(BOUND_X_MIN, BOUND_X_MAX)
		local z = rng:NextNumber(-BOUND_Z, BOUND_Z)
		if isFree(x, z, r, allowField) then
			table.insert(placed, { x = x, z = z, r = r })
			return Vector3.new(x, 0, z)
		end
	end
	return nil
end

----------------------------------------------------------------------
-- 장식들
----------------------------------------------------------------------

local function buildTree(parent: Instance, pos: Vector3)
	local m = model("Tree", parent)
	local kind = rng:NextInteger(1, 3)
	local h = rng:NextNumber(6, 9)
	local trunkColor = if rng:NextNumber() < 0.5 then COLORS.Trunk else COLORS.Cream
	local trunk = column(m, pos, h + 1, rng:NextNumber(0.9, 1.3), trunkColor)
	trunk.CanCollide = true
	local top = pos + Vector3.new(0, h, 0)
	local crown = pick(CROWN_COLORS)
	if kind == 1 then
		-- 막대사탕 나무: 큰 공 + 하이라이트
		local d = rng:NextNumber(6, 8)
		ball(m, top + Vector3.new(0, d * 0.35, 0), d, crown)
		ball(m, top + Vector3.new(d * 0.22, d * 0.62, -d * 0.18), d * 0.3, crown:Lerp(COLORS.White, 0.55))
	elseif kind == 2 then
		-- 솜사탕 나무: 뭉게뭉게 3개
		local d = rng:NextNumber(5, 6.5)
		local c2 = pick(CROWN_COLORS)
		blob(m, top + Vector3.new(0, d * 0.45, 0), Vector3.new(d * 1.3, d, d * 1.3), crown)
		blob(m, top + Vector3.new(d * 0.45, d * 0.15, d * 0.2), Vector3.new(d * 0.9, d * 0.75, d * 0.9), c2)
		blob(m, top + Vector3.new(-d * 0.4, d * 0.2, -d * 0.25), Vector3.new(d * 0.85, d * 0.7, d * 0.85), crown:Lerp(c2, 0.5))
	else
		-- 열매 나무: 둥근 잎 + 빨간 열매
		local d = rng:NextNumber(6.5, 8.5)
		local center = top + Vector3.new(0, d * 0.3, 0)
		blob(m, center, Vector3.new(d, d * 0.85, d), BUSH_COLORS[rng:NextInteger(1, #BUSH_COLORS)])
		for _ = 1, 3 do
			local a = rng:NextNumber(0, math.pi * 2)
			local off = Vector3.new(math.cos(a) * d * 0.47, rng:NextNumber(-0.1, 0.25) * d, math.sin(a) * d * 0.47)
			ball(m, center + off, 0.9, Color3.fromRGB(255, 90, 110))
		end
	end
end

local function buildFlowers(parent: Instance, pos: Vector3)
	local m = model("Flowers", parent)
	local n = rng:NextInteger(3, 5)
	for _ = 1, n do
		local a = rng:NextNumber(0, math.pi * 2)
		local rr = rng:NextNumber(0, 1.5)
		local base = pos + Vector3.new(math.cos(a) * rr, 0, math.sin(a) * rr)
		local h = rng:NextNumber(0.8, 1.5)
		column(m, base, h, 0.22, Color3.fromRGB(95, 185, 90))
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
	local c = BUSH_COLORS[rng:NextInteger(1, #BUSH_COLORS)]
	blob(m, pos + Vector3.new(0, 0.7 * s, 0), Vector3.new(2.4 * s, 1.8 * s, 2.2 * s), c)
	blob(m, pos + Vector3.new(0.9 * s, 0.5 * s, 0.3 * s), Vector3.new(1.6 * s, 1.3 * s, 1.6 * s), c:Lerp(COLORS.White, 0.12))
	if rng:NextNumber() < 0.6 then
		ball(m, pos + Vector3.new(-0.4 * s, 1.5 * s, -0.5 * s), 0.5, pick(FLOWER_COLORS))
	end
end

local function buildCloud(parent: Instance, pos: Vector3)
	local m = model("Cloud", parent)
	local s = rng:NextNumber(1, 1.8)
	local n = rng:NextInteger(4, 5)
	for i = 1, n do
		local t = (i - (n + 1) / 2)
		local size = Vector3.new(rng:NextNumber(7, 10), rng:NextNumber(4.5, 6.5), rng:NextNumber(6, 8)) * s
		local p = blob(m, pos + Vector3.new(t * 4.5 * s, rng:NextNumber(-0.5, 1.5) * s, rng:NextNumber(-1.5, 1.5) * s), size, COLORS.White)
		p.CastShadow = false
	end
end

local function buildLamp(parent: Instance, pos: Vector3, color: Color3)
	local m = model("CandyLamp", parent)
	column(m, pos, 5, 0.5, COLORS.White)
	column(m, pos + Vector3.new(0, 2, 0), 0.6, 0.62, COLORS.Pink)
	local top = ball(m, pos + Vector3.new(0, 5.6, 0), 1.6, color, Enum.Material.Neon)
	top.CastShadow = false
end

----------------------------------------------------------------------
-- 큰 구조물
----------------------------------------------------------------------

local function buildGround(world: Instance)
	local size = Layout.GroundSize
	local ground = newPart(world, Vector3.new(size, 4, size), CFrame.new(0, -2, 0), COLORS.Grass, nil, Enum.Material.Grass)
	ground.Name = "Ground"
	ground.CanCollide = true
end

local function pathPart(parent: Instance, a: Vector3, b: Vector3, width: number, color: Color3): Part
	local mid = (a + b) / 2
	local len = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
	local p = newPart(
		parent,
		Vector3.new(width, 1, len),
		CFrame.lookAt(Vector3.new(mid.X, -0.4, mid.Z), Vector3.new(b.X, -0.4, b.Z)),
		color,
		nil,
		Enum.Material.Sand
	)
	p.CanCollide = true
	return p
end

local function buildPaths(world: Instance)
	local f = Instance.new("Folder")
	f.Name = "Paths"
	f.Parent = world
	-- 공장 아치 아래 연결 바닥 (광장 -> 산책로)
	local cx0 = RAINBOW_X + 2
	local cx1 = FACTORY_X + 8
	local conn = newPart(
		f,
		Vector3.new(cx1 - cx0, 1, WALK_OUT * 2),
		CFrame.new((cx0 + cx1) / 2, -0.4, 0),
		COLORS.Path,
		nil,
		Enum.Material.Sand
	)
	conn.CanCollide = true
	-- 컨베이어 양옆 산책로
	local x0 = cx1
	local x1 = Layout.ConveyorEnd.X + 8
	for _, side in { 1, -1 } do
		local zc = side * (WALK_IN + WALK_OUT) / 2
		pathPart(f, Vector3.new(x0, 0, zc), Vector3.new(x1, 0, zc), WALK_OUT - WALK_IN, COLORS.Path)
	end
	-- 기지 입구 -> 산책로
	for _, seg in entrancePaths do
		pathPart(f, seg.a, seg.b, PATH_W, COLORS.PathDark)
	end
	-- 캔디 가로등
	for _, x in { -60, -36, -14, 14, 36, 60 } do
		for _, side in { 1, -1 } do
			local pos = Vector3.new(x, 0, side * (WALK_OUT + 1.5))
			buildLamp(f, pos, pick(FLOWER_COLORS))
			table.insert(placed, { x = pos.X, z = pos.Z, r = 1.5 })
		end
	end
end

local function buildRainbow(world: Instance)
	local m = model("Rainbow", world)
	local bandW = 1.25
	local segs = 14
	local a0, a1 = -0.05, math.pi + 0.05
	local da = (a1 - a0) / segs
	for b, color in RAINBOW_COLORS do
		local r = RAINBOW_R - (b - 0.5) * bandW
		for k = 0, segs - 1 do
			local am = a0 + (k + 0.5) * da
			local radial = Vector3.new(0, math.sin(am), math.cos(am))
			local pos = Vector3.new(RAINBOW_X, 0, LOBBY.Z) + radial * r
			local len = 2 * r * math.sin(da / 2) + 0.35
			local p = newPart(m, Vector3.new(1.6, bandW, len), CFrame.fromMatrix(pos, Vector3.xAxis, radial), color)
			p.CastShadow = false
		end
	end
	-- 무지개 끝 구름
	for _, side in { 1, -1 } do
		local foot = Vector3.new(RAINBOW_X, 0.8, LOBBY.Z + side * (RAINBOW_R - bandW * 3))
		blob(m, foot, Vector3.new(6, 3.4, 7), COLORS.White)
		blob(m, foot + Vector3.new(1.5, 0.6, side * 2.2), Vector3.new(4.5, 3, 4.5), COLORS.White)
	end
end

local function buildFactoryArch(world: Instance)
	local m = model("EggFactoryArch", world)
	local x = FACTORY_X
	local pillarZ = 10.5
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
	-- 간판 (-X 쪽에서 오는 사람에게 보이도록)
	local signY = beamY + 1.8 + 1.8
	local sign = newPart(
		m,
		Vector3.new(14, 3.6, 0.8),
		CFrame.lookAt(Vector3.new(x, signY, 0), Vector3.new(x - 10, signY, 0)),
		COLORS.HotPink
	)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local frame = signFrame(sign, face, 40, COLORS.Cream, COLORS.HotPink)
		textLabel(frame, "🏭 알 공장 🥚", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.84), COLORS.HotPink)
	end
	-- 지붕 위 큰 알
	local eggPos = Vector3.new(x, signY + 1.8 + 2.0, 0)
	blob(m, eggPos, Vector3.new(3.2, 4.2, 3.2), COLORS.Cream)
	ball(m, eggPos + Vector3.new(-1.35, 0.6, 0.5), 0.9, COLORS.Pink)
	ball(m, eggPos + Vector3.new(-1.3, -0.7, -0.6), 1.0, COLORS.Sky)
	ball(m, eggPos + Vector3.new(1.35, 0.2, 0), 0.9, COLORS.Lemon)
end

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

local function buildLobby(world: Instance)
	local m = model("Lobby", world)
	-- 광장 (분홍 테두리 + 크림 바닥)
	local up = CFrame.Angles(0, 0, math.pi / 2)
	local ring = newPart(m, Vector3.new(1, PLAZA_R * 2, PLAZA_R * 2), CFrame.new(LOBBY.X, -0.38, LOBBY.Z) * up, COLORS.Pink, Enum.PartType.Cylinder)
	ring.CanCollide = true
	local inner = newPart(
		m,
		Vector3.new(1, PLAZA_R * 2 - 3, PLAZA_R * 2 - 3),
		CFrame.new(LOBBY.X, -0.34, LOBBY.Z) * up,
		COLORS.Cream,
		Enum.PartType.Cylinder
	)
	inner.CanCollide = true
	local star = newPart(m, Vector3.new(1, 12, 12), CFrame.new(LOBBY.X, -0.3, LOBBY.Z) * up, COLORS.Lemon, Enum.PartType.Cylinder)
	star.CanCollide = true

	-- 스폰 (컨베이어 쪽 +X 를 바라봄)
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

	local lookAt = Vector3.new(LOBBY.X - 12, 0, LOBBY.Z)

	-- 환영 간판 (북쪽)
	local welcome = buildSignBoard(m, Vector3.new(LOBBY.X - 2, 0, LOBBY.Z + 12), lookAt, Vector2.new(16, 7), 3, COLORS.HotPink)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local frame = signFrame(welcome, face, 40, COLORS.Cream, COLORS.HotPink)
		textLabel(frame, "🥚 알 훔치기 펫 월드 🐾", UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.55), COLORS.HotPink)
		textLabel(frame, "어서 와요! 귀여운 펫을 모아 봐요 💖", UDim2.fromScale(0.08, 0.65), UDim2.fromScale(0.84, 0.25), COLORS.Text)
	end
	ball(m, (welcome.CFrame * CFrame.new(-8, 3.5, 0)).Position, 1.6, COLORS.Lemon)
	ball(m, (welcome.CFrame * CFrame.new(8, 3.5, 0)).Position, 1.6, COLORS.Mint)

	-- 놀이 방법 간판 (남쪽)
	local howto = buildSignBoard(m, Vector3.new(LOBBY.X - 2, 0, LOBBY.Z - 12), lookAt, Vector2.new(13, 10), 2, COLORS.Sky)
	local lines = {
		"1. 컨베이어에서 알 사기 🥚",
		"2. 기지에서 부화 🐣",
		"3. 펫이 코인을 벌어요 💰",
		"4. 다른 기지의 알/펫을 훔쳐요! 🏃",
		"5. 🔒 잠금으로 지키기",
	}
	local frame = signFrame(howto, Enum.NormalId.Front, 40, COLORS.Cream, Color3.fromRGB(110, 170, 255))
	textLabel(frame, "📖 놀이 방법", UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.2), Color3.fromRGB(80, 130, 230))
	for i, line in lines do
		textLabel(
			frame,
			line,
			UDim2.fromScale(0.07, 0.26 + (i - 1) * 0.142),
			UDim2.fromScale(0.86, 0.12),
			COLORS.Text,
			Enum.TextXAlignment.Left
		)
	end
	local back = signFrame(howto, Enum.NormalId.Back, 40, COLORS.Cream, Color3.fromRGB(110, 170, 255))
	textLabel(back, "🐾 즐겁게 놀아요! 🐾", UDim2.fromScale(0.05, 0.3), UDim2.fromScale(0.9, 0.4), COLORS.HotPink)

	-- 광장 꽃 화분
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local p = Vector3.new(LOBBY.X + math.cos(a) * (PLAZA_R - 2.5), 0, LOBBY.Z + math.sin(a) * (PLAZA_R - 2.5))
		-- 동쪽(컨베이어 쪽) 출구와 간판 자리는 비워 둠
		if math.cos(a) < 0.5 and math.abs(math.sin(a)) < 0.8 then
			column(m, p, 1.2, 2.2, COLORS.Peach)
			ball(m, p + Vector3.new(0, 1.5, 0), 1.3, pick(FLOWER_COLORS))
			ball(m, p + Vector3.new(0.6, 1.3, 0.4), 1.0, pick(FLOWER_COLORS))
		end
	end
end

-- 귀여운 펫 동상 (PetModels 가 있으면)
local function buildStatues(world: Instance)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("PetModels")
	if not (module and module:IsA("ModuleScript")) then
		return
	end
	local ok, PetModels = pcall(require, module)
	if not ok or type(PetModels) ~= "table" or type((PetModels :: any).BuildPet) ~= "function" then
		return
	end
	local m = model("Statues", world)
	local spots = {
		{ id = "Chick", pos = Vector3.new(LOBBY.X - 10, 0, LOBBY.Z + 7) },
		{ id = "Bunny", pos = Vector3.new(LOBBY.X - 10, 0, LOBBY.Z - 7) },
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

local function buildFence(world: Instance)
	local m = model("Fence", world)
	local corners = {
		Vector3.new(BOUND_X_MIN, 0, -BOUND_Z),
		Vector3.new(BOUND_X_MAX, 0, -BOUND_Z),
		Vector3.new(BOUND_X_MAX, 0, BOUND_Z),
		Vector3.new(BOUND_X_MIN, 0, BOUND_Z),
	}
	local picketColors = { COLORS.White, COLORS.Pink, COLORS.Mint, COLORS.Lavender }
	local idx = 0
	for i = 1, 4 do
		local a = corners[i]
		local b = corners[i % 4 + 1]
		local dir = (b - a).Unit
		local len = (b - a).Magnitude
		local n = math.floor(len / 4)
		for k = 0, n - 1 do
			local pos = a + dir * (k * len / n)
			idx += 1
			newPart(
				m,
				Vector3.new(0.9, 3.4, 0.5),
				CFrame.lookAt(pos + Vector3.new(0, 1.7, 0), pos + Vector3.new(0, 1.7, 0) + dir:Cross(Vector3.yAxis)),
				picketColors[idx % #picketColors + 1]
			)
		end
		local mid = (a + b) / 2
		for _, y in { 1.1, 2.5 } do
			local rail = newPart(
				m,
				Vector3.new(0.35, 0.4, len),
				CFrame.lookAt(mid + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0)),
				COLORS.White
			)
			rail.CanCollide = true
		end
		-- 투명 벽 (밖으로 못 나가게)
		local wall = newPart(m, Vector3.new(2, 60, len + 4), CFrame.lookAt(mid + Vector3.new(0, 30, 0), b + Vector3.new(0, 30, 0)), COLORS.White)
		wall.Name = "InvisibleWall"
		wall.Transparency = 1
		wall.CanCollide = true
		wall.CastShadow = false
	end
end

local function buildHills(world: Instance)
	local m = model("Hills", world)
	local half = Layout.GroundSize / 2
	local count = 0
	for _ = 1, 200 do
		if count >= 18 then
			break
		end
		local sx = rng:NextNumber(40, 75)
		local sz = rng:NextNumber(40, 75)
		local sy = rng:NextNumber(20, 38)
		local x = rng:NextNumber(-half + 10, half - 10)
		local z = rng:NextNumber(-half + 10, half - 10)
		-- 울타리 밖에만
		local outside = x + sx / 2 < BOUND_X_MIN - 4
			or x - sx / 2 > BOUND_X_MAX + 4
			or z + sz / 2 < -BOUND_Z - 4
			or z - sz / 2 > BOUND_Z + 4
		if outside then
			count += 1
			local c = BUSH_COLORS[rng:NextInteger(1, #BUSH_COLORS)]:Lerp(COLORS.Lemon, rng:NextNumber(0, 0.2))
			local hill = blob(m, Vector3.new(x, 0, z), Vector3.new(sx, sy, sz), c)
			hill.Material = Enum.Material.Grass
		end
	end
end

local function buildDecorations(world: Instance)
	local deco = Instance.new("Folder")
	deco.Name = "Decorations"
	deco.Parent = world

	for _ = 1, 46 do
		local p = findSpot(4.5, false, 40)
		if p then
			buildTree(deco, p)
		end
	end
	for _ = 1, 34 do
		local p = findSpot(2.2, false, 40)
		if p then
			buildBush(deco, p)
		end
	end
	for _ = 1, 22 do
		local p = findSpot(1.6, false, 40)
		if p then
			buildMushroom(deco, p)
		end
	end
	for _ = 1, 42 do
		local p = findSpot(1.8, true, 40)
		if p then
			buildFlowers(deco, p)
		end
	end
	-- 하늘 구름
	for _ = 1, 14 do
		local pos = Vector3.new(
			rng:NextNumber(BOUND_X_MIN - 30, BOUND_X_MAX + 30),
			rng:NextNumber(50, 75),
			rng:NextNumber(-BOUND_Z - 30, BOUND_Z + 30)
		)
		buildCloud(deco, pos)
	end
end

local function setupLighting()
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 25
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(150, 145, 160)
	Lighting.OutdoorAmbient = Color3.fromRGB(185, 175, 195)
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
	atmosphere.Color = Color3.fromRGB(255, 228, 242)
	atmosphere.Decay = Color3.fromRGB(200, 210, 255)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "PastelColor"
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.Brightness = 0.02
	cc.TintColor = Color3.fromRGB(255, 250, 252)
	cc.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "SoftBloom"
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
end

----------------------------------------------------------------------

function WorldBuilder.Build()
	-- 기본 바닥/스폰 제거, 이전 월드 제거
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") or child.Name == "World" then
			child:Destroy()
		end
	end

	partCount = 0
	table.clear(placed)

	local world = Instance.new("Folder")
	world.Name = "World"

	buildGround(world)
	buildPaths(world)
	buildLobby(world)
	buildRainbow(world)
	buildFactoryArch(world)
	buildStatues(world)
	buildFence(world)
	buildHills(world)
	buildDecorations(world)

	world.Parent = workspace
	setupLighting()

	if partCount > 1500 then
		warn(("[WorldBuilder] 파트가 많아요: %d"):format(partCount))
	end
	print(("[WorldBuilder] 월드 완성! 파트 %d개"):format(partCount))
end

return WorldBuilder
