--!strict
-- 귀여운 가구 모델을 파트로만 만들어요 (서버/클라이언트 공용, 에셋 ID 없음).
-- 규칙: PrimaryPart = Base (Config Size 의 X × Z 크기, 높이 0.1 의 투명한 판, CanCollide 끔),
-- 피벗 = 바닥 중앙 (y = 0), 앞쪽 = -Z (R = 0), 모든 파트가 Config Size 상자 안에 들어가요.
-- 모든 파트 Anchored + WeldConstraint 로 Base 에 붙임. CanTouch 는 끔 (Seat 만 켜요: 앉으려면 필요해요).
-- 단단한 파트 CanCollide = Config.Furniture[id].Collide (러그는 전부 끔), 작은 장식 파트는 CanCollide 끔.
local Config = require(script.Parent.Config)

local FurnitureModels = {}

type FurnDef = { Size: Vector3, Collide: boolean? }
local FURN: { [string]: FurnDef } = Config.Furniture :: any

local V = Vector3.new
local RGB = Color3.fromRGB
local CF = CFrame.new
local ANG = CFrame.Angles
local PI = math.pi
local SIDES = { -1, 1 }
local BASE_H = 0.1

local NEON = Enum.Material.Neon
local WOODM = Enum.Material.Wood
local FABRIC = Enum.Material.Fabric
local GLASS = Enum.Material.Glass

-- 색 (파스텔)
local WHITE = RGB(255, 255, 255)
local CREAM = RGB(255, 246, 228)
local EYE = RGB(38, 30, 48)
local BLUSH = RGB(255, 140, 170)
local PINK = RGB(255, 175, 205)
local PINK_LT = RGB(255, 215, 228)
local PINK_DK = RGB(240, 140, 175)
local HOTPINK = RGB(255, 105, 160)
local SKY = RGB(135, 200, 255)
local SKY_LT = RGB(190, 228, 255)
local MINT = RGB(150, 230, 200)
local MINT_LT = RGB(195, 245, 225)
local LEMON = RGB(255, 228, 110)
local LILAC = RGB(200, 170, 255)
local ORANGE = RGB(255, 160, 70)
local WOOD = RGB(232, 195, 145)
local WOOD_DK = RGB(170, 120, 80)
local LEAF = RGB(110, 200, 110)
local LEAF_LT = RGB(145, 220, 125)
local LEAF_DK = RGB(80, 170, 95)
local GOLD = RGB(255, 200, 60)
local GOLD_DK = RGB(205, 145, 35)
local RED = RGB(235, 75, 85)
local BLUE = RGB(70, 140, 240)
local GREEN = RGB(80, 195, 100)
local PURPLE = RGB(165, 110, 235)
local YELLOW = RGB(255, 210, 60)
local RAINBOW = {
	RGB(255, 95, 110),
	RGB(255, 165, 70),
	RGB(255, 225, 80),
	RGB(110, 215, 120),
	RGB(90, 170, 255),
	RGB(175, 120, 255),
}

----------------------------------------------------------------------
-- 파트 만들기 도우미
----------------------------------------------------------------------

type Builder = { model: Model, parts: { BasePart }, solid: boolean }

-- cls: "Part" | "Seat" | "Wedge". deco = true 면 작은 장식 (CanCollide 끔)
local function newPart(
	b: Builder,
	cls: string,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	deco: boolean?
): BasePart
	local p: BasePart
	if cls == "Wedge" then
		p = Instance.new("WedgePart")
	elseif cls == "Seat" then
		p = Instance.new("Seat")
	else
		p = Instance.new("Part")
	end
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = b.solid and not deco
	p.CanTouch = cls == "Seat"
	p.CanQuery = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = b.model
	table.insert(b.parts, p)
	return p
end

local function setShape(p: BasePart, shape: Enum.PartType)
	if p:IsA("Part") then
		p.Shape = shape
	end
end

local function sphereMesh(p: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

local function block(b: Builder, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, deco: boolean?): BasePart
	return newPart(b, "Part", name, size, cf, color, mat, deco)
end

local function wedge(b: Builder, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, deco: boolean?): BasePart
	return newPart(b, "Wedge", name, size, cf, color, mat, deco)
end

-- 타원체 (Size = 지름)
local function ell(b: Builder, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, deco: boolean?): BasePart
	local p = newPart(b, "Part", name, size, cf, color, mat, deco)
	sphereMesh(p)
	return p
end

local function ball(b: Builder, name: string, d: number, cf: CFrame, color: Color3, mat: Enum.Material?, deco: boolean?): BasePart
	local p = newPart(b, "Part", name, V(d, d, d), cf, color, mat, deco)
	setShape(p, Enum.PartType.Ball)
	return p
end

-- X 축 원기둥 (길이 len, 지름 d)
local function xcyl(b: Builder, name: string, len: number, d: number, cf: CFrame, color: Color3, mat: Enum.Material?, deco: boolean?): BasePart
	local p = newPart(b, "Part", name, V(len, d, d), cf, color, mat, deco)
	setShape(p, Enum.PartType.Cylinder)
	return p
end

-- Z 축 원기둥
local function zcyl(b: Builder, name: string, len: number, d: number, cf: CFrame, color: Color3, mat: Enum.Material?, deco: boolean?): BasePart
	return xcyl(b, name, len, d, cf * ANG(0, PI / 2, 0), color, mat, deco)
end

-- 세운 원기둥: (x, z) 에서 y0 부터 높이 h
local function vcyl(
	b: Builder,
	name: string,
	h: number,
	d: number,
	x: number,
	y0: number,
	z: number,
	color: Color3,
	mat: Enum.Material?,
	deco: boolean?
): BasePart
	return xcyl(b, name, h, d, CF(x, y0 + h / 2, z) * ANG(0, 0, PI / 2), color, mat, deco)
end

-- 앉을 수 있는 자리 (앉으면 -Z 쪽을 봐요). round = true 면 타원체 모양
local function seat(b: Builder, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, round: boolean?): BasePart
	local p = newPart(b, "Seat", name, size, cf, color, mat)
	if round then
		sphereMesh(p)
	end
	return p
end

-- 이등변 삼각형 (쐐기 2개). frame: 원점 = 밑변 중앙, Y = 꼭짓점 방향, Z = 두께 방향
local function tri(
	b: Builder,
	name: string,
	frame: CFrame,
	w: number,
	h: number,
	t: number,
	color: Color3,
	mat: Enum.Material?,
	deco: boolean?
)
	local size = V(t, h, w / 2)
	wedge(b, name, size, frame * CFrame.fromMatrix(V(w / 4, h / 2, 0), Vector3.zAxis, Vector3.yAxis), color, mat, deco)
	wedge(b, name, size, frame * CFrame.fromMatrix(V(-w / 4, h / 2, 0), -Vector3.zAxis, Vector3.yAxis), color, mat, deco)
end

-- 하트 (frame 의 XY 평면, 두께 t 는 frame Z). s = 마름모 한 변
local function heart(b: Builder, name: string, frame: CFrame, s: number, t: number, color: Color3, deco: boolean?)
	local q = s / (2 * math.sqrt(2))
	block(b, name, V(s, s, t), frame * ANG(0, 0, PI / 4), color, nil, deco)
	zcyl(b, name, t, s, frame * CF(-q, q, 0), color, nil, deco)
	zcyl(b, name, t, s, frame * CF(q, q, 0), color, nil, deco)
end

-- 타원체(중심 c, 반지름 s) 앞면(-Z)에서 (x, y) 위치의 점과 바깥 법선
local function onFront(c: Vector3, s: Vector3, x: number, y: number): (Vector3, Vector3)
	local k = 1 - (x / s.X) ^ 2 - (y / s.Y) ^ 2
	local z = -s.Z * math.sqrt(math.max(k, 0.02))
	local p = V(x, y, z)
	local n = V(p.X / (s.X * s.X), p.Y / (s.Y * s.Y), p.Z / (s.Z * s.Z)).Unit
	return c + p, n
end

-- -Z(LookVector) 가 법선 n 을 향하는 CFrame
local function facing(p: Vector3, n: Vector3): CFrame
	local up = if math.abs(n.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt(p, p + n, up)
end

-- 귀여운 얼굴 (눈 + 반짝이 + 볼터치) 을 타원체 앞면에
local function face(b: Builder, c: Vector3, s: Vector3, ex: number, ey: number, eye: Vector3, bx: number, by: number)
	for _, sx in SIDES do
		local p, n = onFront(c, s, sx * ex, ey)
		local cf = facing(p + n * (eye.Z * 0.1), n)
		ell(b, "Eye", eye, cf, EYE, nil, true)
		local sh = eye.X * 0.4
		ell(b, "Shine", V(sh, sh, 0.04), cf * CF(eye.X * 0.18, eye.Y * 0.2, -eye.Z * 0.42), WHITE, NEON, true)
		local q, m = onFront(c, s, sx * bx, by)
		ell(b, "Blush", V(eye.X * 1.4, eye.Y * 0.5, eye.Z * 0.5), facing(q + m * 0.01, m), BLUSH, nil, true)
	end
end

local function light(p: BasePart, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = p
end

-- 블록 앞면(-Z)에 큰 글자
local function letter(p: BasePart, text: string)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Letter"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 60
	sg.LightInfluence = 0.3
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(0.8, 0.8)
	t.Position = UDim2.fromScale(0.1, 0.1)
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = WHITE
	t.TextStrokeTransparency = 0.6
	t.Parent = sg
end

-- first 번째 파트부터 지금까지 만든 파트를 반짝이게
local function shineFrom(b: Builder, first: number, refl: number)
	for i = first, #b.parts do
		b.parts[i].Reflectance = refl
	end
end

----------------------------------------------------------------------
-- 가구 22개 (§13). 좌표는 바닥 중앙 (0, 0, 0) 기준, 앞 = -Z
----------------------------------------------------------------------

local BUILD: { [string]: (Builder) -> () } = {}

-- 화분 2 × 3.5 × 2: 테라코타 화분 + 동그란 초록 덤불 + 분홍 꽃
BUILD.PottedPlant = function(b)
	vcyl(b, "Pot", 1.3, 1.5, 0, 0, 0, RGB(215, 125, 85))
	vcyl(b, "Rim", 0.3, 1.8, 0, 1.15, 0, RGB(230, 150, 110))
	local c, s = V(0, 2.25, 0), V(0.975, 0.8, 0.975)
	ell(b, "Bush", s * 2, CF(c), LEAF)
	ell(b, "Bush", V(1.2, 1.0, 1.2), CF(0.1, 3.0, 0.05), LEAF_LT, nil, true)
	ell(b, "Bush", V(1.0, 0.85, 1.0), CF(-0.45, 2.2, -0.45), LEAF_LT, nil, true)
	ell(b, "Bush", V(1.0, 0.85, 1.0), CF(0.45, 2.15, 0.45), LEAF_DK, nil, true)
	for _, f in { { -0.35, 0.35 }, { 0.45, -0.05 } } do
		local p, n = onFront(c, s, f[1], f[2])
		ball(b, "Flower", 0.32, CF(p - n * 0.07), PINK, nil, true)
	end
end

-- 나무 의자 2.5 × 3.5 × 2.5: 밝은 나무, 등받이에 분홍 하트, 분홍 방석 (Seat)
BUILD.WoodChair = function(b)
	for _, sx in SIDES do
		block(b, "Leg", V(0.3, 1.4, 0.3), CF(sx * 1.05, 0.7, -1.05), WOOD, WOODM)
		block(b, "BackLeg", V(0.3, 3.5, 0.3), CF(sx * 1.05, 1.75, 1.05), WOOD, WOODM)
	end
	block(b, "SeatBoard", V(2.4, 0.3, 2.4), CF(0, 1.55, 0), WOOD, WOODM)
	seat(b, "Seat", V(2.0, 0.25, 1.9), CF(0, 1.825, -0.15), PINK, FABRIC)
	block(b, "BackTop", V(1.8, 0.4, 0.2), CF(0, 3.3, 1.05), WOOD, WOODM)
	block(b, "BackLow", V(1.8, 0.25, 0.2), CF(0, 1.825, 1.05), WOOD, WOODM)
	block(b, "BackPanel", V(1.8, 1.15, 0.12), CF(0, 2.525, 1.05), RGB(245, 220, 185), WOODM)
	heart(b, "Heart", CF(0, 2.5, 1.05), 0.7, 0.18, HOTPINK, true)
end

-- 펫 쿠션 4 × 1.2 × 4: 동그란 분홍 쿠션 + 볼록한 테두리 + 하얀 발바닥 무늬
BUILD.PetBed = function(b)
	vcyl(b, "Bottom", 0.35, 3.8, 0, 0, 0, PINK_DK, FABRIC)
	ell(b, "Cushion", V(3.0, 0.6, 3.0), CF(0, 0.45, 0), PINK_LT, FABRIC)
	for i = 0, 7 do
		local a = i * PI / 4
		ell(b, "Rim", V(1.5, 0.9, 0.9), CF(1.5 * math.cos(a), 0.75, 1.5 * math.sin(a)) * ANG(0, PI / 2 - a, 0), PINK, FABRIC)
	end
	ell(b, "Paw", V(0.55, 0.1, 0.45), CF(0, 0.76, 0.12), WHITE, nil, true)
	for _, t in { { -0.3, -0.22 }, { 0, -0.34 }, { 0.3, -0.22 } } do
		ell(b, "Toe", V(0.2, 0.1, 0.2), CF(t[1], 0.75, t[2]), WHITE, nil, true)
	end
end

-- 동그란 러그 8 × 0.2 × 8: 파스텔 동심원 + 하얀 점 (안 부딪혀요)
BUILD.Rug = function(b)
	local cols = { LILAC, CREAM, PINK, MINT, LEMON }
	for i, col in cols do
		vcyl(b, "Ring", 0.12 + (i - 1) * 0.02, 8 - (i - 1) * 1.6, 0, 0, 0, col, FABRIC)
	end
	for i = 0, 7 do
		local a = i * PI / 4 + PI / 8
		vcyl(b, "Dot", 0.13, 0.4, 3.6 * math.cos(a), 0, 3.6 * math.sin(a), WHITE, FABRIC)
	end
end

-- 둥근 탁자 4 × 3 × 4: 하얀 동그란 상판, 굵은 다리 하나
BUILD.RoundTable = function(b)
	vcyl(b, "Foot", 0.3, 2.4, 0, 0, 0, PINK)
	vcyl(b, "Leg", 2.4, 0.8, 0, 0.3, 0, PINK)
	vcyl(b, "Ring", 0.2, 1.1, 0, 0.3, 0, WHITE, nil, true)
	vcyl(b, "Ring", 0.2, 1.1, 0, 2.4, 0, WHITE, nil, true)
	vcyl(b, "Skirt", 0.12, 3.85, 0, 2.6, 0, LILAC, nil, true)
	vcyl(b, "Top", 0.3, 4.0, 0, 2.7, 0, WHITE)
end

-- 빈백 3.5 × 2.5 × 3.5: 말랑한 연두 덩어리 + 귀여운 얼굴 (Seat)
BUILD.BeanBag = function(b)
	local LIME = RGB(185, 235, 95)
	vcyl(b, "Bottom", 0.5, 3.2, 0, 0, 0, RGB(160, 215, 80), FABRIC)
	local c, s = V(0, 0.85, 0), V(1.75, 0.85, 1.64)
	ell(b, "Blob", s * 2, CF(c), LIME, FABRIC)
	ell(b, "BackHump", V(3.1, 1.9, 1.5), CF(0, 1.55, 0.95), LIME, FABRIC)
	seat(b, "Seat", V(2.2, 0.4, 1.9), CF(0, 1.6, -0.35), RGB(210, 245, 140), FABRIC, true)
	face(b, c, s, 0.45, 0.1, V(0.25, 0.32, 0.12), 0.8, -0.1)
end

-- 장난감 블록 3 × 2 × 3: 알록달록 블록 쌓기 + 글자
BUILD.ToyBlocks = function(b)
	letter(block(b, "Block", V(1.1, 1.1, 1.1), CF(-0.9, 0.55, -0.75), RED), "A")
	letter(block(b, "Block", V(1.1, 1.1, 1.1), CF(0.35, 0.55, -0.8) * ANG(0, 0.26, 0), BLUE), "B")
	letter(block(b, "Block", V(1.1, 1.1, 1.1), CF(0.85, 0.55, 0.6) * ANG(0, -0.2, 0), YELLOW), "C")
	letter(block(b, "Block", V(1.0, 1.0, 1.0), CF(-0.7, 0.5, 0.9), GREEN), "D")
	letter(block(b, "Block", V(0.9, 0.9, 0.9), CF(-0.3, 1.55, -0.7) * ANG(0, -0.15, 0), PURPLE), "1")
	wedge(b, "Roof", V(0.9, 0.8, 0.9), CF(0.85, 1.5, 0.6) * ANG(0, -0.2, 0), ORANGE)
end

-- 선인장 2 × 4 × 2: 하늘색 화분 + 웃는 선인장 + 분홍 꽃
BUILD.Cactus = function(b)
	local GREENC = RGB(120, 205, 120)
	vcyl(b, "Pot", 1.0, 1.55, 0, 0, 0, RGB(140, 200, 240))
	vcyl(b, "Rim", 0.25, 1.94, 0, 0.9, 0, RGB(185, 225, 250))
	local c, s = V(0, 2.35, 0), V(0.575, 1.25, 0.575)
	ell(b, "Body", s * 2, CF(c), GREENC)
	ell(b, "Arm", V(0.6, 0.4, 0.4), CF(-0.5, 2.2, 0), GREENC)
	ell(b, "Arm", V(0.42, 0.85, 0.42), CF(-0.77, 2.55, 0), GREENC)
	ell(b, "Arm", V(0.6, 0.4, 0.4), CF(0.5, 2.6, 0), GREENC)
	ell(b, "Arm", V(0.42, 0.85, 0.42), CF(0.77, 2.95, 0), GREENC)
	for _, o in { V(0.17, 0, 0), V(-0.17, 0, 0), V(0, 0, 0.17), V(0, 0, -0.17) } do
		ell(b, "Petal", V(0.4, 0.22, 0.4), CF(V(0, 3.62, 0) + o), HOTPINK, nil, true)
	end
	ball(b, "FlowerMid", 0.26, CF(0, 3.74, 0), LEMON, nil, true)
	face(b, c, s, 0.2, 0.4, V(0.14, 0.2, 0.1), 0.33, 0.2)
end

-- 스탠드 조명 1.6 × 6 × 1.6: 가는 기둥 + 크림색 갓 + 따뜻한 빛
BUILD.FloorLamp = function(b)
	local WARM = RGB(255, 220, 150)
	vcyl(b, "Foot", 0.25, 1.3, 0, 0, 0, MINT)
	vcyl(b, "Pole", 4.6, 0.2, 0, 0.25, 0, WHITE)
	local bulb = ball(b, "Bulb", 0.55, CF(0, 4.55, 0), WARM, NEON, true)
	light(bulb, WARM, 0.8, 12)
	vcyl(b, "ShadeBand", 0.12, 1.6, 0, 4.6, 0, PINK)
	vcyl(b, "Shade", 0.6, 1.56, 0, 4.72, 0, CREAM)
	vcyl(b, "Shade", 0.55, 1.25, 0, 5.32, 0, CREAM)
	ball(b, "Knob", 0.2, CF(0, 5.9, 0), PINK, nil, true)
end

-- 폭신 소파 7 × 3.5 × 3: 하늘색 소파 + 방석 3개 (Seat 3개) + 쿠션
BUILD.Sofa = function(b)
	for _, sx in SIDES do
		for _, sz in SIDES do
			vcyl(b, "Foot", 0.25, 0.4, sx * 2.9, 0, sz * 1.1, WOOD_DK, nil, true)
		end
	end
	block(b, "Frame", V(6.6, 0.9, 2.8), CF(0, 0.7, 0), SKY, FABRIC)
	for _, sx in SIDES do
		block(b, "Arm", V(0.8, 1.6, 2.9), CF(sx * 3.1, 1.05, 0), SKY, FABRIC)
		zcyl(b, "ArmRoll", 2.9, 0.8, CF(sx * 3.1, 1.85, 0), SKY, FABRIC)
	end
	block(b, "Back", V(5.4, 1.7, 0.9), CF(0, 2.0, 1.05), SKY, FABRIC)
	xcyl(b, "BackRoll", 6.2, 0.9, CF(0, 3.05, 1.05), SKY, FABRIC)
	for i = -1, 1 do
		seat(b, "Seat", V(1.75, 0.45, 2.0), CF(i * 1.8, 1.375, -0.4), SKY_LT, FABRIC)
		ell(b, "Cushion", V(1.65, 1.3, 0.55), CF(i * 1.8, 2.25, 0.4), SKY_LT, FABRIC)
	end
	ell(b, "Pillow", V(0.9, 0.9, 0.35), CF(-2.15, 2.05, 0.05) * ANG(0, 0, 0.25), PINK, FABRIC, true)
	ell(b, "Pillow", V(0.9, 0.9, 0.35), CF(2.15, 2.05, 0.05) * ANG(0, 0, -0.25), LEMON, FABRIC, true)
end

-- 책장 6 × 7 × 2: 나무 책장 + 알록달록 책
BUILD.Bookshelf = function(b)
	for _, sx in SIDES do
		block(b, "Side", V(0.3, 7, 2), CF(sx * 2.85, 3.5, 0), WOOD, WOODM)
	end
	block(b, "BackPanel", V(5.4, 6.3, 0.2), CF(0, 3.55, 0.9), PINK_LT)
	block(b, "Top", V(5.4, 0.3, 2), CF(0, 6.85, 0), WOOD, WOODM)
	block(b, "Bottom", V(5.4, 0.4, 2), CF(0, 0.2, 0), WOOD, WOODM)
	for _, y in { 1.875, 3.475, 5.075 } do
		block(b, "Shelf", V(5.4, 0.25, 1.8), CF(0, y, -0.1), WOOD, WOODM)
	end
	-- { x, 두께, 높이, 칸 바닥 y, 색 }
	local books: { { any } } = {
		{ -2.45, 0.42, 1.1, 0.4, RED },
		{ -2.0, 0.42, 1.2, 0.4, SKY },
		{ -1.56, 0.42, 1.0, 0.4, LEMON },
		{ -1.12, 0.4, 1.15, 0.4, MINT },
		{ 0.9, 0.42, 1.15, 2.0, LILAC },
		{ 1.34, 0.4, 1.05, 2.0, PINK },
		{ 1.78, 0.44, 1.2, 2.0, ORANGE },
		{ -0.6, 0.42, 1.15, 3.6, GREEN },
		{ -0.16, 0.4, 1.05, 3.6, RED },
		{ 0.28, 0.44, 1.2, 3.6, SKY },
		{ 0.72, 0.4, 1.0, 3.6, LEMON },
		{ -2.4, 0.44, 1.25, 5.2, HOTPINK },
		{ -1.95, 0.42, 1.15, 5.2, PURPLE },
	}
	for _, bk in books do
		local h = bk[3] :: number
		block(b, "Book", V(bk[2] :: number, h, 1.4), CF(bk[1] :: number, (bk[4] :: number) + h / 2, -0.2), bk[5] :: Color3, nil, true)
	end
	-- 기대 놓은 책 하나 + 눕혀 쌓은 책 두 권
	block(b, "Book", V(0.4, 1.1, 1.4), CF(2.3, 2.584, -0.2) * ANG(0, 0, 0.3), BLUE, nil, true)
	block(b, "Book", V(1.4, 0.3, 1.2), CF(1.5, 5.35, -0.2), MINT, nil, true)
	block(b, "Book", V(1.2, 0.3, 1.1), CF(1.45, 5.65, -0.2), ORANGE, nil, true)
end

-- 캣타워 3 × 7 × 3: 베이지 기둥 + 동그란 발판 + 고양이 귀 쿠션 + 매달린 공
BUILD.CatTower = function(b)
	local SISAL = RGB(230, 205, 160)
	vcyl(b, "Floor", 0.4, 3.0, 0, 0, 0, PINK, FABRIC)
	vcyl(b, "Post", 5.4, 0.7, 0, 0.4, 0.2, SISAL, FABRIC)
	vcyl(b, "Post", 1.8, 0.5, 0.3, 0.4, -0.8, SISAL, FABRIC)
	vcyl(b, "Step", 0.3, 1.8, 0.6, 2.2, -0.4, MINT, FABRIC)
	vcyl(b, "Step", 0.3, 1.8, -0.6, 4.0, 0.1, LEMON, FABRIC)
	vcyl(b, "Top", 0.3, 2.2, 0, 5.8, 0.3, PINK, FABRIC)
	ell(b, "Cushion", V(2.1, 0.7, 2.1), CF(0, 6.35, 0.3), LILAC, FABRIC)
	for _, sx in SIDES do
		tri(b, "Ear", CF(sx * 0.55, 6.5, 0.3) * ANG(0, 0, -sx * 0.15), 0.65, 0.45, 0.25, LILAC, FABRIC, true)
	end
	vcyl(b, "String", 0.75, 0.06, 1.25, 1.45, -0.5, WHITE, nil, true)
	ball(b, "ToyBall", 0.45, CF(1.25, 1.25, -0.5), HOTPINK, nil, true)
end

-- 침대 6 × 3 × 8: 하얀 틀 + 분홍 이불 + 베개 2개 (머리 쪽 = +Z)
BUILD.Bed = function(b)
	for _, sx in SIDES do
		for _, sz in SIDES do
			vcyl(b, "Leg", 0.25, 0.5, sx * 2.6, 0, sz * 3.3 - 0.15, WOOD_DK)
		end
	end
	block(b, "Frame", V(6.0, 0.85, 7.5), CF(0, 0.675, -0.15), WHITE)
	block(b, "Headboard", V(6.0, 2.5, 0.4), CF(0, 1.5, 3.8), WHITE)
	xcyl(b, "HeadRoll", 6.0, 0.5, CF(0, 2.75, 3.75), PINK)
	block(b, "Footboard", V(6.0, 1.5, 0.3), CF(0, 1.0, -3.75), WHITE)
	heart(b, "Heart", CF(0, 1.05, -3.95), 0.6, 0.1, PINK, true)
	block(b, "Mattress", V(5.6, 0.6, 7.2), CF(0, 1.4, 0), CREAM)
	block(b, "Blanket", V(5.8, 0.3, 5.0), CF(0, 1.75, -1.1), PINK, FABRIC)
	for _, sx in SIDES do
		block(b, "Drape", V(0.1, 0.65, 5.0), CF(sx * 2.85, 1.35, -1.1), PINK, FABRIC, true)
		ell(b, "Pillow", V(2.3, 0.6, 1.3), CF(sx * 1.3, 2.0, 2.65), WHITE, FABRIC)
	end
	block(b, "Fold", V(5.8, 0.32, 0.6), CF(0, 1.76, 1.4), PINK_LT, FABRIC)
	for _, p in { { -1.6, -2.6 }, { 0.3, -1.9 }, { 1.8, -2.9 }, { -0.7, -0.5 }, { 1.5, -0.3 } } do
		vcyl(b, "Dot", 0.04, 0.55, p[1], 1.9, p[2], WHITE, nil, true)
	end
end

-- 별 조명 2 × 2.5 × 2: 받침 위의 노란 네온 별 (웃는 얼굴)
BUILD.StarLamp = function(b)
	local STAR = RGB(255, 222, 80)
	vcyl(b, "Stand", 0.3, 1.94, 0, 0, 0, LILAC)
	ell(b, "Dome", V(1.3, 0.5, 1.3), CF(0, 0.3, 0), PINK, nil, true)
	vcyl(b, "Stem", 1.0, 0.25, 0, 0.3, 0, WHITE)
	local c = V(0, 1.65, 0)
	local R, r = 0.85, 0.425
	local core = zcyl(b, "Star", 0.45, 2 * r, CF(c), STAR, NEON)
	light(core, RGB(255, 230, 150), 0.8, 10)
	local cos36, sin36 = math.cos(math.rad(36)), math.sin(math.rad(36))
	for k = 0, 4 do
		local th = math.rad(90 + 72 * k)
		local dir = V(math.cos(th), math.sin(th), 0)
		local frame = CFrame.fromMatrix(c + dir * (r * cos36), V(math.sin(th), -math.cos(th), 0), dir)
		tri(b, "Star", frame, 2 * r * sin36, R - r * cos36, 0.35, STAR, NEON, true)
	end
	for _, sx in SIDES do
		ell(b, "Eye", V(0.12, 0.17, 0.06), CF(sx * 0.16, 1.72, -0.24), EYE, nil, true)
		ell(b, "Blush", V(0.14, 0.08, 0.04), CF(sx * 0.3, 1.58, -0.235), BLUSH, nil, true)
	end
end

-- 무지개 러그 10 × 0.2 × 6: 무지개 줄무늬 + 양 끝 구름 (안 부딪혀요)
BUILD.RainbowRug = function(b)
	block(b, "Border", V(10, 0.12, 6), CF(0, 0.06, 0), WHITE, FABRIC)
	for i, col in RAINBOW do
		block(b, "Stripe", V(9.2, 0.15, 0.9), CF(0, 0.075, (i - 3.5) * 0.95), col, FABRIC)
	end
	for _, sx in SIDES do
		vcyl(b, "Cloud", 0.2, 1.8, sx * 4.0, 0, 0.6, WHITE, FABRIC)
		vcyl(b, "Cloud", 0.2, 1.5, sx * 4.1, 0, -0.7, WHITE, FABRIC)
	end
end

-- 볼풀 8 × 2.5 × 8: 낮은 팔각 풀 + 알록달록 공 (공은 안 부딪혀서 들어가 놀 수 있어요)
BUILD.BallPit = function(b)
	vcyl(b, "Floor", 0.2, 7.2, 0, 0, 0, SKY)
	vcyl(b, "BallFloor", 0.9, 6.8, 0, 0.2, 0, LILAC)
	local wallCols = { PINK, SKY, LEMON, MINT }
	for i = 0, 7 do
		local a = i * PI / 4
		local at = CF(3.55 * math.cos(a), 0, 3.55 * math.sin(a)) * ANG(0, PI / 2 - a, 0)
		block(b, "Wall", V(3.2, 1.9, 0.6), at * CF(0, 0.95, 0), wallCols[i % 4 + 1])
		xcyl(b, "Roll", 3.2, 0.8, at * CF(0, 2.1, 0), WHITE)
	end
	local cols = { RAINBOW[1], RAINBOW[2], RAINBOW[3], RAINBOW[4], RAINBOW[5], RAINBOW[6], WHITE, HOTPINK }
	local n = 0
	local function pitBall(x: number, y: number, z: number)
		n += 1
		ball(b, "Ball", 0.85, CF(x, y, z), cols[(n - 1) % #cols + 1], nil, true)
	end
	pitBall(0, 1.3, 0)
	for k = 0, 4 do
		local a = k * 2 * PI / 5
		pitBall(1.25 * math.cos(a), if k % 2 == 0 then 1.3 else 1.45, 1.25 * math.sin(a))
	end
	for k = 0, 7 do
		local a = PI / 8 + k * PI / 4
		pitBall(2.45 * math.cos(a), 1.3, 2.45 * math.sin(a))
	end
	pitBall(0.6, 1.95, 0.4)
	pitBall(-0.7, 1.9, -0.6)
end

-- 물고기 (dir = +1 이면 +X 쪽을 봐요)
local function fish(b: Builder, pos: Vector3, dir: number, color: Color3)
	ell(b, "Fish", V(0.55, 0.38, 0.2), CF(pos), color, nil, true)
	ell(b, "FishTail", V(0.22, 0.34, 0.08), CF(pos - V(dir * 0.33, 0, 0)), color, nil, true)
end

-- 어항 5 × 4 × 2.5: 장 위의 유리 수조, 파란 물, 작은 물고기
BUILD.Aquarium = function(b)
	block(b, "Cabinet", V(4.8, 1.6, 2.3), CF(0, 0.8, 0), MINT)
	for _, sx in SIDES do
		block(b, "Door", V(2.1, 1.15, 0.05), CF(sx * 1.15, 0.8, -1.175), MINT_LT, nil, true)
		ball(b, "Knob", 0.14, CF(sx * 0.3, 0.8, -1.18), GOLD, nil, true)
	end
	block(b, "TankBottom", V(5.0, 0.15, 2.5), CF(0, 1.675, 0), WHITE)
	block(b, "TankTop", V(5.0, 0.15, 2.5), CF(0, 3.925, 0), WHITE)
	for _, sx in SIDES do
		for _, sz in SIDES do
			block(b, "Post", V(0.15, 2.1, 0.15), CF(sx * 2.425, 2.8, sz * 1.175), WHITE)
		end
	end
	local water = block(b, "Water", V(4.7, 2.1, 2.2), CF(0, 2.8, 0), RGB(110, 190, 255), GLASS)
	water.Transparency = 0.45
	block(b, "Sand", V(4.6, 0.25, 2.1), CF(0, 1.875, 0), RGB(255, 230, 170), nil, true)
	ell(b, "Seaweed", V(0.3, 1.2, 0.3), CF(-1.6, 2.5, 0.4), LEAF, nil, true)
	ell(b, "Seaweed", V(0.3, 1.0, 0.3), CF(1.8, 2.4, 0.5), LEAF_DK, nil, true)
	fish(b, V(-0.6, 3.0, -0.2), -1, ORANGE)
	fish(b, V(0.9, 2.6, 0.1), 1, LEMON)
	fish(b, V(0.2, 3.4, 0.3), -1, HOTPINK)
	ball(b, "Bubble", 0.18, CF(-1.05, 3.4, -0.2), WHITE, nil, true)
	ball(b, "Bubble", 0.14, CF(-1.0, 3.65, -0.25), WHITE, nil, true)
end

-- 미끄럼틀 4 × 6 × 10: 뒤(+Z) 계단 사다리 → 꼭대기 → 앞(-Z)으로 빨간 미끄럼판 + 노란 난간
BUILD.Slide = function(b)
	local stepCols = { PINK, SKY, MINT, LEMON }
	for i = 1, 4 do
		local z0 = 2.2 + 0.7 * (4 - i)
		block(b, "Step", V(3.4, 0.3, 0.7), CF(0, i - 0.15, z0 + 0.35), stepCols[i])
	end
	for _, sx in SIDES do
		wedge(b, "LadderRail", V(0.3, 5.0, 2.8), CF(sx * 1.85, 2.5, 3.6) * ANG(0, PI, 0), YELLOW)
		block(b, "Tower", V(0.3, 6.0, 1.6), CF(sx * 1.85, 3.0, 1.4), SKY)
	end
	block(b, "Deck", V(3.4, 0.4, 1.6), CF(0, 4.8, 1.4), LILAC)
	-- 미끄럼판: 꼭대기 (z 0.6, y 5) → 아래 (z -4.2, y 0.5)
	local top, bot = V(0, 5.0, 0.6), V(0, 0.5, -4.2)
	local d = top - bot
	local L = d.Magnitude
	local n = V(0, d.Z, -d.Y).Unit -- 미끄럼판 윗면 법선 (위 + 앞)
	local mid = (top + bot) * 0.5
	block(b, "SlideBed", V(2.8, 0.3, L), CFrame.fromMatrix(mid - n * 0.15, Vector3.xAxis, n), RED)
	for _, sx in SIDES do
		block(b, "SlideRail", V(0.3, 0.5, L), CFrame.fromMatrix(mid + n * 0.1 + V(sx * 1.55, 0, 0), Vector3.xAxis, n), YELLOW)
	end
	block(b, "Exit", V(2.8, 0.5, 1.0), CF(0, 0.25, -4.5), RED)
	block(b, "Support", V(0.4, 2.3, 0.4), CF(0, 1.15, -2.0), YELLOW)
end

-- 벽난로 6 × 6 × 2.5: 벽돌 벽난로 + 네온 주황 불 + 작은 초
BUILD.Fireplace = function(b)
	local BRICK = RGB(225, 130, 110)
	local BRICKM = Enum.Material.Brick
	block(b, "Hearth", V(6.0, 0.4, 2.5), CF(0, 0.2, 0), RGB(235, 225, 215))
	for _, sx in SIDES do
		block(b, "Pillar", V(1.4, 4.2, 2.1), CF(sx * 2.2, 2.5, 0.15), BRICK, BRICKM)
	end
	block(b, "Lintel", V(3.0, 1.0, 2.1), CF(0, 4.1, 0.15), BRICK, BRICKM)
	block(b, "Inside", V(3.0, 3.2, 0.4), CF(0, 2.0, 1.0), RGB(70, 45, 45))
	block(b, "Mantel", V(6.0, 0.35, 2.5), CF(0, 4.775, 0), CREAM)
	block(b, "Chimney", V(3.6, 1.05, 1.3), CF(0, 5.475, 0.55), BRICK, BRICKM)
	for _, s in SIDES do
		xcyl(b, "Log", 2.0, 0.35, CF(0, 0.58, 0.35) * ANG(0, s * 0.3, 0), WOOD_DK, nil, true)
	end
	local flame = ell(b, "Fire", V(1.3, 1.7, 0.6), CF(0, 1.55, 0.4), RGB(255, 140, 50), NEON, true)
	light(flame, RGB(255, 150, 70), 0.9, 14)
	for _, sx in SIDES do
		ell(b, "Fire", V(0.8, 1.15, 0.5), CF(sx * 0.55, 1.2, 0.45), RGB(255, 95, 50), NEON, true)
	end
	ell(b, "Fire", V(0.6, 0.9, 0.3), CF(0, 1.25, 0.12), RGB(255, 225, 90), NEON, true)
	for _, sx in SIDES do
		vcyl(b, "Candle", 0.5, 0.25, sx * 2.45, 4.95, 0, if sx < 0 then PINK else SKY, nil, true)
		ell(b, "CandleFlame", V(0.14, 0.22, 0.14), CF(sx * 2.45, 5.55, 0), RGB(255, 200, 80), NEON, true)
	end
end

-- 피아노 6 × 4.5 × 3: 반짝이는 검은 업라이트 피아노 + 하얀 건반 (건반 = -Z)
BUILD.Piano = function(b)
	local BLACKP = RGB(30, 28, 36)
	local body = block(b, "Body", V(6.0, 4.5, 1.5), CF(0, 2.25, 0.75), BLACKP)
	body.Reflectance = 0.2
	block(b, "KeyBed", V(5.8, 0.45, 1.4), CF(0, 2.325, -0.7), BLACKP)
	block(b, "Keys", V(5.2, 0.15, 1.15), CF(0, 2.625, -0.725), WHITE)
	local kw = 5.2 / 14
	for _, k in { 1, 2, 4, 5, 6, 8, 9, 11, 12, 13 } do
		block(b, "BlackKey", V(0.18, 0.12, 0.6), CF(-2.6 + k * kw, 2.76, -0.45), BLACKP, nil, true)
	end
	for _, sx in SIDES do
		block(b, "Cheek", V(0.3, 0.35, 1.4), CF(sx * 2.75, 2.725, -0.7), BLACKP)
		block(b, "Leg", V(0.35, 2.1, 0.35), CF(sx * 2.55, 1.05, -1.15), BLACKP)
		block(b, "Pedal", V(0.22, 0.08, 0.5), CF(sx * 0.3, 0.3, -0.2), GOLD, nil, true)
	end
	local standCF = CF(0, 3.3, -0.1) * ANG(0.2, 0, 0)
	block(b, "MusicStand", V(2.6, 0.9, 0.1), standCF, BLACKP, nil, true)
	block(b, "Sheet", V(1.2, 0.7, 0.04), standCF * CF(0, 0.02, -0.07), WHITE, nil, true)
	block(b, "Trim", V(6.0, 0.12, 0.05), CF(0, 4.2, -0.025), GOLD, nil, true)
end

-- 황금 펫 동상 3 × 6 × 3: 대리석 받침 위의 반짝이는 황금 고양이
BUILD.GoldStatue = function(b)
	local MARBLE = RGB(245, 240, 250)
	local MARBLEM = Enum.Material.Marble
	block(b, "Plinth", V(3.0, 0.4, 3.0), CF(0, 0.2, 0), MARBLE, MARBLEM)
	block(b, "Plinth", V(2.5, 1.1, 2.5), CF(0, 0.95, 0), MARBLE, MARBLEM)
	block(b, "Plinth", V(2.8, 0.3, 2.8), CF(0, 1.65, 0), MARBLE, MARBLEM)
	local first = #b.parts + 1
	block(b, "Plaque", V(1.2, 0.4, 0.05), CF(0, 0.95, -1.275), GOLD, nil, true)
	local bc, bs = V(0, 2.75, 0.15), V(0.85, 1.0, 0.75)
	ell(b, "Body", bs * 2, CF(bc), GOLD)
	local hc, hs = V(0, 4.35, -0.05), V(0.95, 0.8, 0.8)
	ell(b, "Head", hs * 2, CF(hc), GOLD)
	for _, sx in SIDES do
		tri(b, "Ear", CF(sx * 0.5, 4.95, -0.05) * ANG(0, 0, -sx * 0.25), 0.7, 0.85, 0.3, GOLD)
		ell(b, "Paw", V(0.55, 0.4, 0.7), CF(sx * 0.4, 1.95, -0.6), GOLD, nil, true)
		local p, n = onFront(hc, hs, sx * 0.38, 0.1)
		ell(b, "Eye", V(0.22, 0.3, 0.1), facing(p, n), GOLD_DK, nil, true)
	end
	local mp, mn = onFront(hc, hs, 0, -0.25)
	ell(b, "Muzzle", V(0.6, 0.4, 0.3), facing(mp, mn), GOLD, nil, true)
	ell(b, "Tail", V(0.45, 1.6, 0.45), CF(0.95, 2.6, 0.45) * ANG(0, 0, -0.35), GOLD, nil, true)
	shineFrom(b, first, 0.3)
	local gp, gn = onFront(bc, bs, 0, 0.6)
	ball(b, "Gem", 0.35, facing(gp, gn), RGB(255, 80, 130), NEON, true)
end

-- 왕좌 4 × 7 × 4: 빨간 벨벳 + 황금 틀, 높은 등받이 꼭대기에 보석 (Seat)
BUILD.Throne = function(b)
	local VELVET = RGB(200, 35, 60)
	local first = #b.parts + 1
	block(b, "Step", V(4.0, 0.4, 4.0), CF(0, 0.2, 0), GOLD)
	block(b, "SeatBase", V(3.4, 1.4, 3.1), CF(0, 1.1, -0.25), GOLD)
	block(b, "Back", V(3.6, 6.0, 0.6), CF(0, 3.4, 1.6), GOLD)
	for _, sx in SIDES do
		block(b, "Arm", V(0.45, 1.1, 2.8), CF(sx * 1.7, 2.35, -0.3), GOLD)
		ball(b, "ArmKnob", 0.5, CF(sx * 1.7, 3.0, -1.55), GOLD, nil, true)
		ball(b, "TopKnob", 0.5, CF(sx * 1.55, 6.65, 1.6), GOLD, nil, true)
	end
	zcyl(b, "Crest", 0.6, 1.2, CF(0, 6.4, 1.6), GOLD)
	for _, p in { V(-0.6, 4.7, 1.03), V(0.6, 4.7, 1.03), V(0, 3.6, 1.03) } do
		ball(b, "Button", 0.2, CF(p), GOLD, nil, true)
	end
	shineFrom(b, first, 0.25)
	seat(b, "Seat", V(2.8, 0.4, 2.6), CF(0, 2.0, -0.4), VELVET, FABRIC)
	block(b, "BackPad", V(2.8, 3.9, 0.3), CF(0, 4.15, 1.2), VELVET, FABRIC)
	ball(b, "Gem", 0.55, CF(0, 6.4, 1.2), RGB(90, 200, 255), NEON, true)
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

local function newBuilder(furnId: string, size: Vector3, solid: boolean): Builder
	local model = Instance.new("Model")
	model.Name = furnId
	local b: Builder = { model = model, parts = {}, solid = solid }
	-- Base: 바닥 크기 판 (투명, 안 부딪힘). 꾸미기 모드의 놓기 상자/선택용
	local base = block(b, "Base", V(size.X, BASE_H, size.Z), CF(0, BASE_H / 2, 0), WHITE, nil, true)
	base.Transparency = 1
	base.CanCollide = false
	base.PivotOffset = CF(0, -BASE_H / 2, 0)
	return b
end

local function finish(b: Builder): Model
	local model = b.model
	local base = b.parts[1]
	model.PrimaryPart = base
	for i = 2, #b.parts do
		local w = Instance.new("WeldConstraint")
		w.Part0 = base
		w.Part1 = b.parts[i]
		w.Parent = b.parts[i]
	end
	return model
end

local function sizeOf(furnId: string): Vector3
	local def = FURN[furnId]
	return if def then def.Size else V(2, 2, 2)
end

-- 가구 모델 (피벗 = 바닥 중앙, 앞 = -Z). 부르는 쪽이 model:PivotTo(...) 하고 Parent 를 정해요
function FurnitureModels.Build(furnId: string): Model
	local def = FURN[furnId]
	local size = sizeOf(furnId)
	local b = newBuilder(furnId, size, if def then def.Collide ~= false else true)
	local fn = BUILD[furnId]
	if fn and def then
		fn(b)
	else
		-- 모르는 가구: 파스텔 상자
		block(b, "Box", size, CF(0, size.Y / 2, 0), LILAC)
	end
	return finish(b)
end

function FurnitureModels.Has(furnId: string): boolean
	return BUILD[furnId] ~= nil and FURN[furnId] ~= nil
end

-- 상점/꾸미기 칸용 3D 미리보기
function FurnitureModels.CreateViewport(furnId: string, parent: Instance): (ViewportFrame, Model)
	local vf = Instance.new("ViewportFrame")
	vf.Name = "FurnitureViewport"
	vf.Size = UDim2.fromScale(1, 1)
	vf.AnchorPoint = Vector2.new(0.5, 0.5)
	vf.Position = UDim2.fromScale(0.5, 0.5)
	vf.BackgroundTransparency = 1
	vf.Ambient = RGB(180, 180, 190)
	vf.LightColor = RGB(255, 250, 245)
	vf.LightDirection = V(-0.4, -1, 0.7)

	local model = FurnitureModels.Build(furnId)
	model.Parent = vf

	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vf
	vf.CurrentCamera = cam

	local size = sizeOf(furnId)
	local center = V(0, size.Y / 2, 0)
	-- 러그처럼 납작하면 위에서, 아니면 앞(-Z) 오른쪽 위에서
	local dir = if size.Y < 0.5 then V(0.3, 1.2, -0.8).Unit else V(0.5, 0.38, -1).Unit
	-- Size 상자의 꼭짓점 8개가 화면에 다 들어오는 거리
	local look = -dir
	local right = look:Cross(Vector3.yAxis).Unit
	local up = right:Cross(look).Unit
	local t = math.tan(math.rad(cam.FieldOfView * 0.5))
	local dist = 1
	for _, sx in SIDES do
		for _, sy in { 0, 1 } do
			for _, sz in SIDES do
				local p = V(sx * size.X / 2, sy * size.Y, sz * size.Z / 2) - center
				dist = math.max(dist, math.max(math.abs(p:Dot(right)), math.abs(p:Dot(up))) / t + p:Dot(dir))
			end
		end
	end
	cam.CFrame = CFrame.lookAt(center + dir * dist * 1.06, center)

	vf.Parent = parent
	return vf, model
end

return FurnitureModels
