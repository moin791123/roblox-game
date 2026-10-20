--!strict
-- 귀여운 펫/알 모델을 파트로만 만들어요 (서버/클라이언트 공용, 에셋 ID 없음).
-- 규칙: PrimaryPart = Body, 모든 파트 Unanchored + CanCollide/CanTouch/CanQuery 끔,
-- WeldConstraint 로 Body 에 붙임, Body 만 질량 있음, 피벗 = 바닥 중앙, 앞쪽 = -Z.
local Config = require(script.Parent.Config)

local PetModels = {}

local V = Vector3.new
local RGB = Color3.fromRGB

local EYE = RGB(38, 30, 48)
local WHITE = RGB(255, 255, 255)
local BLACK = RGB(0, 0, 0)
local BLUSH = RGB(255, 140, 170)
local MOUTH = RGB(130, 55, 70)
local RAINBOW = {
	RGB(255, 95, 110),
	RGB(255, 165, 70),
	RGB(255, 225, 80),
	RGB(110, 215, 120),
	RGB(90, 170, 255),
	RGB(175, 120, 255),
}

type RarityInfo = { Name: string, Color: Color3, Order: number }

----------------------------------------------------------------------
-- 파트 만들기 도우미
----------------------------------------------------------------------

type Builder = { model: Model, parts: { BasePart } }

local function newBuilder(name: string): Builder
	local model = Instance.new("Model")
	model.Name = name
	return { model = model, parts = {} }
end

-- kind: "Ell"(타원체) | "Block" | "Cyl"(X축 원기둥) | "Wedge"
local function addPart(
	b: Builder,
	name: string,
	kind: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	transparency: number?
): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if kind == "Cyl" then
			part.Shape = Enum.PartType.Cylinder
		else
			part.Shape = Enum.PartType.Block
		end
		p = part
	end
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "Ell" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = b.model
	table.insert(b.parts, p)
	return p
end

local function ell(
	b: Builder,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	transparency: number?
): BasePart
	return addPart(b, name, "Ell", size, cf, color, mat, transparency)
end

local function darker(c: Color3, k: number?): Color3
	return c:Lerp(BLACK, k or 0.18)
end

-- 타원체(중심 c, 반지름 s) 표면에서 dir 방향의 점과 바깥 법선
local function surf(c: Vector3, s: Vector3, dir: Vector3): (Vector3, Vector3)
	local d = dir.Unit
	local k = (d.X / s.X) ^ 2 + (d.Y / s.Y) ^ 2 + (d.Z / s.Z) ^ 2
	local p = d / math.sqrt(k)
	local n = V(p.X / (s.X * s.X), p.Y / (s.Y * s.Y), p.Z / (s.Z * s.Z)).Unit
	return c + p, n
end

-- 타원체 앞면(-Z)에서 (x, y) 위치의 점과 법선
local function front(c: Vector3, s: Vector3, x: number, y: number): (Vector3, Vector3)
	local k = 1 - (x / s.X) ^ 2 - (y / s.Y) ^ 2
	local z = -s.Z * math.sqrt(math.max(k, 0.02))
	local p = V(x, y, z)
	local n = V(p.X / (s.X * s.X), p.Y / (s.Y * s.Y), p.Z / (s.Z * s.Z)).Unit
	return c + p, n
end

-- -Z(LookVector) 가 법선 n 을 향하는 CFrame (납작한 장식을 표면에 붙일 때)
local function facing(p: Vector3, n: Vector3): CFrame
	local up = if math.abs(n.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt(p, p + n, up)
end

-- 로컬 Y 축이 dir 을 향하는 CFrame
local function alongY(c: Vector3, dir: Vector3): CFrame
	local up = dir.Unit
	local ref = if math.abs(up.Z) < 0.9 then Vector3.zAxis else Vector3.xAxis
	local right = up:Cross(ref).Unit
	return CFrame.fromMatrix(c, right, up)
end

-- 로컬 X 축이 dir 을 향하는 CFrame (원기둥 축 맞추기)
local function alongX(c: Vector3, dir: Vector3): CFrame
	local x = dir.Unit
	local ref = if math.abs(x.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(ref).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(c, x, y)
end

-- Y = up, Z ≈ zHint 인 프레임 (날개 등)
local function frameUp(pos: Vector3, up: Vector3, zHint: Vector3): CFrame
	local u = up.Unit
	local x = u:Cross(zHint).Unit
	return CFrame.fromMatrix(pos, x, u)
end

-- 이등변 삼각형 (쐐기 2개). frame: 원점 = 밑변 중앙, Y = 꼭짓점 방향, Z = 두께 방향
local function tri(b: Builder, name: string, frame: CFrame, w: number, h: number, t: number, color: Color3, mat: Enum.Material?)
	local size = V(t, h, w / 2)
	addPart(b, name, "Wedge", size, frame * CFrame.fromMatrix(V(w / 4, h / 2, 0), Vector3.zAxis, Vector3.yAxis), color, mat)
	addPart(b, name, "Wedge", size, frame * CFrame.fromMatrix(V(-w / 4, h / 2, 0), -Vector3.zAxis, Vector3.yAxis), color, mat)
end

-- 반짝이는 큰 눈 (검은 눈 + 하얀 반짝이 2개). 눈의 CFrame 을 돌려줘요.
local function addEye(b: Builder, c: Vector3, s: Vector3, x: number, y: number, size: Vector3, lift: number): CFrame
	local p, n = front(c, s, x, y)
	local cf = facing(p + n * lift, n)
	ell(b, "Eye", size, cf, EYE)
	local d = size.Z * 0.5
	local s1 = size.X * 0.4
	local s2 = size.X * 0.2
	ell(b, "Shine", V(s1, s1, 0.05), cf * CFrame.new(size.X * 0.2, size.Y * 0.22, -d * 0.8), WHITE, Enum.Material.Neon)
	ell(b, "Shine", V(s2, s2, 0.04), cf * CFrame.new(-size.X * 0.17, -size.Y * 0.2, -d * 0.75), WHITE, Enum.Material.Neon)
	return cf
end

----------------------------------------------------------------------
-- 기본 꼬마 몸 (몸통 + 큰 머리 + 발 + 팔 + 얼굴)
----------------------------------------------------------------------

type FaceOpt = { color: Color3, semi: Vector3, offset: Vector3 }

type Opt = {
	body: Color3,
	head: Color3?,
	feet: Color3?,
	arms: Color3?,
	belly: Color3?,
	mat: Enum.Material?,
	BS: Vector3?,
	HS: Vector3?,
	face: FaceOpt?,
	noArms: boolean?,
	noMouth: boolean?,
	noEyes: boolean?,
	eyeX: number?,
	eyeY: number?,
	eyeSize: Vector3?,
	eyeLift: number?,
	blushX: number?,
	blushY: number?,
	blushLift: number?,
	mouthY: number?,
}

type Ctx = {
	b: Builder,
	B: Vector3, -- 몸통 중심
	BS: Vector3, -- 몸통 반지름
	H: Vector3, -- 머리 중심
	HS: Vector3, -- 머리 반지름
	FC: Vector3, -- 얼굴 면 중심 (보통 머리)
	FS: Vector3,
	BeC: Vector3, -- 배 중심
	BeS: Vector3,
	eyes: { CFrame }, -- [1] = 왼쪽(-X), [2] = 오른쪽(+X)
}

local SIDES = { -1, 1 }

local function chibi(b: Builder, o: Opt): Ctx
	local BS = o.BS or V(0.9, 0.75, 0.8)
	local B = V(0, 0.15 + BS.Y, 0)
	local HS = o.HS or V(1.05, 0.98, 0.98)
	local H = V(0, B.Y + BS.Y + HS.Y * 0.5, 0)
	local mat = o.mat
	local bodyCol = o.body

	ell(b, "Body", BS * 2, CFrame.new(B), bodyCol, mat)
	ell(b, "Head", HS * 2, CFrame.new(H), o.head or bodyCol, mat)

	-- 배: 안쪽 타원체를 앞으로 살짝 내밀어서 표면 위로 볼록
	local BeS = V(BS.X * 0.72, BS.Y * 0.78, BS.Z * 0.7)
	local BeC = B + V(0, -BS.Y * 0.08, -(BS.Z - BeS.Z) - 0.06)
	if o.belly then
		ell(b, "Belly", BeS * 2, CFrame.new(BeC), o.belly, mat)
	end

	-- 발 (바닥 y = 0 에 닿음)
	local feetCol = o.feet or darker(bodyCol, 0.12)
	for _, sx in SIDES do
		ell(b, "Foot", V(0.56, 0.4, 0.72), CFrame.new(sx * BS.X * 0.5, 0.2, -BS.Z * 0.38), feetCol, mat)
	end

	-- 짧은 팔
	if not o.noArms then
		for _, sx in SIDES do
			local p, n = surf(B, BS, V(sx, -0.05, -0.45))
			ell(b, "Arm", V(0.36, 0.52, 0.36), CFrame.new(p - n * 0.04) * CFrame.Angles(0, 0, sx * 0.35), o.arms or bodyCol, mat)
		end
	end

	-- 얼굴 면 (펭귄/부엉이처럼 다른 색 얼굴)
	local FC, FS = H, HS
	local face = o.face
	if face then
		FS = face.semi
		FC = H + face.offset
		ell(b, "Face", FS * 2, CFrame.new(FC), face.color, mat)
	end

	local ex = o.eyeX or 0.4
	local ey = o.eyeY or -0.02
	local eyes = {}
	if not o.noEyes then
		for _, sx in SIDES do
			table.insert(eyes, addEye(b, FC, FS, sx * ex, ey, o.eyeSize or V(0.36, 0.5, 0.16), o.eyeLift or 0))
		end
	end

	-- 볼터치
	for _, sx in SIDES do
		local p, n = front(FC, FS, sx * (o.blushX or ex + 0.28), o.blushY or ey - 0.3)
		ell(b, "Blush", V(0.32, 0.17, 0.06), facing(p + n * (o.blushLift or 0), n), BLUSH, nil, 0.1)
	end

	if not o.noMouth then
		local p, n = front(FC, FS, 0, o.mouthY or ey - 0.34)
		ell(b, "Mouth", V(0.18, 0.09, 0.06), facing(p, n), MOUTH)
	end

	return { b = b, B = B, BS = BS, H = H, HS = HS, FC = FC, FS = FS, BeC = BeC, BeS = BeS, eyes = eyes }
end

-- 뾰족 귀 (고양이/여우/돼지 등). x, y = 머리 위 방향, tilt = 바깥 기울기, fwd = 앞으로 숙임
local function pointyEars(
	c: Ctx,
	x: number,
	y: number,
	w: number,
	h: number,
	t: number,
	tilt: number,
	color: Color3,
	inner: Color3?,
	fwd: number?
)
	for _, sx in SIDES do
		local p, n = surf(c.H, c.HS, V(sx * x, y, 0))
		local frame = CFrame.new(p - n * 0.14) * CFrame.Angles(fwd or 0, 0, -sx * tilt)
		tri(c.b, "Ear", frame, w, h, t, color)
		if inner then
			tri(c.b, "EarInner", frame * CFrame.new(0, 0.1, -(t * 0.5 + 0.015)), w * 0.58, h * 0.62, 0.03, inner)
		end
	end
end

-- 동그란 귀 (곰/판다/햄스터)
local function roundEars(c: Ctx, x: number, y: number, d: number, color: Color3, inner: Color3?)
	for _, sx in SIDES do
		local p, n = surf(c.H, c.HS, V(sx * x, y, 0))
		local ec = p + n * 0.07
		ell(c.b, "Ear", V(d, d, 0.3), CFrame.new(ec), color)
		if inner then
			ell(c.b, "EarInner", V(d * 0.58, d * 0.58, 0.08), CFrame.new(ec + V(0, 0, -0.13)), inner)
		end
	end
end

-- 주둥이 + 코 + 입 (강아지/곰)
local function muzzle(c: Ctx, size: Vector3, color: Color3, noseColor: Color3, y: number): CFrame
	local p, n = front(c.H, c.HS, 0, y)
	local mcf = facing(p - n * 0.05, n)
	ell(c.b, "Muzzle", size, mcf, color)
	local hz = size.Z * 0.5
	ell(c.b, "Nose", V(0.26, 0.18, 0.14), mcf * CFrame.new(0, size.Y * 0.24, -(hz - 0.03)), noseColor)
	ell(c.b, "Mouth", V(0.14, 0.06, 0.05), mcf * CFrame.new(0, -size.Y * 0.17, -(hz - 0.01)), MOUTH)
	return mcf
end

local function smallNose(c: Ctx, y: number, size: Vector3, color: Color3, lift: number)
	local p, n = front(c.FC, c.FS, 0, y)
	ell(c.b, "Nose", size, facing(p + n * lift, n), color)
end

-- 공 여러 개로 된 휘어진 꼬리 (뒤로 나갔다가 위로)
local function ballArc(b: Builder, name: string, start: Vector3, R: number, colors: { Color3 }, d0: number, d1: number, mat: Enum.Material?)
	local count = #colors
	local denom = math.max(count - 1, 1)
	for i, col in colors do
		local f = (i - 1) / denom
		local a = f * math.pi * 0.5
		local pos = start + V(0, R * (1 - math.cos(a)), R * math.sin(a))
		local d = d0 + (d1 - d0) * f
		ell(b, name, V(d, d, d), CFrame.new(pos), col, mat)
	end
end

----------------------------------------------------------------------
-- 펫 18 종
----------------------------------------------------------------------

local PET_BUILDERS: { [string]: (Builder) -> () } = {}

-- 병아리: 노란 동글이, 주황 부리/발, 머리 위 깃털 3가닥, 작은 날개
PET_BUILDERS.Chick = function(b: Builder)
	local Y = RGB(255, 222, 80)
	local c = chibi(b, { body = Y, feet = RGB(255, 150, 50), noArms = true, noMouth = true, eyeY = 0.04 })
	for _, sx in SIDES do
		local p, n = surf(c.B, c.BS, V(sx, 0.05, 0.1))
		ell(b, "Wing", V(0.26, 0.6, 0.55), CFrame.new(p + n * 0.02) * CFrame.Angles(0, 0, sx * 0.3), RGB(250, 200, 60))
	end
	local p, n = front(c.H, c.HS, 0, -0.26)
	ell(b, "Beak", V(0.34, 0.2, 0.3), facing(p + n * 0.04, n), RGB(255, 150, 40))
	local top = c.H + V(0, c.HS.Y, 0)
	for _, dx in { -0.13, 0, 0.13 } do
		ell(b, "Tuft", V(0.16, 0.42, 0.16), CFrame.new(top + V(dx, 0.1, 0.05)) * CFrame.Angles(0, 0, -dx * 3), Y)
	end
	local tp, tn = surf(c.B, c.BS, V(0, 0.15, 1))
	ell(b, "Tail", V(0.45, 0.3, 0.35), CFrame.new(tp + tn * 0.05) * CFrame.Angles(-0.4, 0, 0), Y)
end

-- 토끼: 하얀 분홍빛, 긴 귀(안쪽 분홍), 분홍 코, 동그란 꼬리
PET_BUILDERS.Bunny = function(b: Builder)
	local W = RGB(255, 242, 246)
	local P = RGB(255, 170, 195)
	local c = chibi(b, { body = W, belly = WHITE, feet = RGB(255, 228, 236) })
	for _, sx in SIDES do
		local p = surf(c.H, c.HS, V(sx * 0.38, 1, 0.05))
		local cf = CFrame.new(p) * CFrame.Angles(0, 0, -sx * 0.2) * CFrame.new(0, 0.5, 0)
		ell(b, "Ear", V(0.42, 1.2, 0.24), cf, W)
		ell(b, "EarInner", V(0.22, 0.9, 0.08), cf * CFrame.new(0, 0.04, -0.09), P)
	end
	smallNose(c, -0.2, V(0.16, 0.11, 0.08), P, 0.02)
	local tp, tn = surf(c.B, c.BS, V(0, -0.1, 1))
	ell(b, "Tail", V(0.5, 0.5, 0.5), CFrame.new(tp + tn * 0.1), WHITE)
end

-- 햄스터: 갈색+크림, 빵빵한 볼주머니, 작은 동그란 귀
PET_BUILDERS.Hamster = function(b: Builder)
	local O = RGB(240, 178, 105)
	local Cr = RGB(255, 240, 215)
	local c = chibi(b, {
		body = O,
		belly = Cr,
		HS = V(1.15, 0.95, 0.98),
		feet = RGB(255, 200, 185),
		eyeX = 0.42,
		eyeY = 0.04,
		blushX = 0.6,
		blushY = -0.36,
		blushLift = 0.12,
		mouthY = -0.36,
	})
	for _, sx in SIDES do
		local p, n = front(c.H, c.HS, sx * 0.6, -0.38)
		ell(b, "Cheek", V(0.55, 0.45, 0.45), facing(p - n * 0.1, n), Cr)
	end
	smallNose(c, -0.18, V(0.14, 0.1, 0.08), RGB(255, 140, 160), 0.02)
	roundEars(c, 0.62, 0.8, 0.44, darker(O, 0.08), RGB(255, 175, 190))
	-- 이마 줄무늬
	local p, n = surf(c.H, c.HS, V(0, 0.85, -0.5))
	ell(b, "Stripe", V(0.22, 0.5, 0.06), facing(p, n), darker(O, 0.15))
end

-- 아기돼지: 분홍, 큰 코(콧구멍 2개), 앞으로 접힌 세모 귀, 꼬불 꼬리
PET_BUILDERS.Piglet = function(b: Builder)
	local P = RGB(255, 182, 198)
	local c = chibi(b, {
		body = P,
		belly = RGB(255, 205, 215),
		feet = RGB(235, 130, 160),
		eyeY = 0.1,
		mouthY = -0.56,
		blushY = -0.22,
	})
	local p, n = front(c.H, c.HS, 0, -0.26)
	local scf = facing(p + n * 0.06, n)
	ell(b, "Snout", V(0.6, 0.42, 0.3), scf, RGB(255, 150, 178))
	for _, sx in SIDES do
		ell(b, "Nostril", V(0.09, 0.13, 0.05), scf * CFrame.new(sx * 0.12, 0, -0.13), RGB(200, 90, 120))
	end
	pointyEars(c, 0.55, 0.8, 0.5, 0.5, 0.1, 0.5, P, nil, -0.6)
	local tp, tn = surf(c.B, c.BS, V(0, 0.1, 1))
	ell(b, "Tail", V(0.22, 0.22, 0.22), CFrame.new(tp + tn * 0.08), P)
	ell(b, "Tail", V(0.2, 0.2, 0.2), CFrame.new(tp + tn * 0.18 + V(0, 0.14, 0)), P)
end

-- 고양이: 주황 + 흰 배/발, 뾰족 귀(분홍 안쪽), 볼록 입가, 수염, 위로 선 꼬리
PET_BUILDERS.Cat = function(b: Builder)
	local O = RGB(255, 168, 85)
	local Wt = RGB(255, 248, 238)
	local c = chibi(b, { body = O, belly = Wt, feet = Wt, eyeY = 0.05, noMouth = true, blushY = -0.22 })
	for _, sx in SIDES do
		local p, n = front(c.H, c.HS, sx * 0.16, -0.33)
		ell(b, "Muzzle", V(0.42, 0.32, 0.28), facing(p - n * 0.06, n), Wt)
	end
	smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 130, 160), 0.04)
	pointyEars(c, 0.55, 0.85, 0.6, 0.62, 0.16, 0.3, O, RGB(255, 180, 195))
	for _, sx in SIDES do
		for _, a in { 0.14, -0.14 } do
			local p, n = front(c.H, c.HS, sx * 0.62, -0.4 + a * 0.3)
			addPart(b, "Whisker", "Block", V(0.42, 0.035, 0.035), facing(p + n * 0.03, n) * CFrame.Angles(0, 0, sx * a), RGB(120, 80, 60))
		end
	end
	local tp = surf(c.B, c.BS, V(0, -0.3, 1))
	ell(b, "Tail", V(0.28, 0.28, 0.7), CFrame.new(tp + V(0, 0.08, 0.28)), O)
	ell(b, "Tail", V(0.28, 0.8, 0.28), CFrame.new(tp + V(0, 0.42, 0.58)), O)
end

-- 강아지: 베이지, 크림 주둥이 + 까만 코 + 혀, 늘어진 갈색 귀, 빨간 목걸이, 흔드는 꼬리
PET_BUILDERS.Puppy = function(b: Builder)
	local T = RGB(215, 170, 120)
	local Cr = RGB(255, 240, 220)
	local Br = RGB(150, 100, 65)
	local c = chibi(b, { body = T, belly = Cr, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
	local mcf = muzzle(c, V(0.62, 0.42, 0.4), Cr, RGB(45, 35, 35), -0.32)
	ell(b, "Tongue", V(0.14, 0.13, 0.06), mcf * CFrame.new(0, -0.17, -0.13), RGB(255, 120, 140))
	for _, sx in SIDES do
		ell(b, "Ear", V(0.42, 0.85, 0.26), CFrame.new(c.H + V(sx * 1.08, 0.22, 0.05)) * CFrame.Angles(0, 0, sx * 0.25), Br)
	end
	local ny = c.B.Y + c.BS.Y - 0.2
	addPart(b, "Collar", "Cyl", V(0.18, 1.6, 1.6), CFrame.new(0, ny, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(240, 80, 100))
	ell(b, "Tag", V(0.2, 0.2, 0.08), CFrame.new(0, ny - 0.12, -0.81), RGB(255, 210, 60), Enum.Material.Metal)
	local tp = surf(c.B, c.BS, V(0, 0.1, 1))
	local dir = V(0, 0.65, 0.75).Unit
	ell(b, "Tail", V(0.24, 0.24, 0.6), CFrame.lookAt(tp + dir * 0.22, tp + dir * 1.22), T)
end

-- 개구리: 초록, 머리 위로 튀어나온 눈, 넓은 웃는 입, 등 점박이
PET_BUILDERS.Frog = function(b: Builder)
	local G = RGB(120, 210, 90)
	local c = chibi(b, {
		body = G,
		belly = RGB(220, 245, 170),
		HS = V(1.15, 0.85, 0.95),
		feet = RGB(95, 185, 75),
		noEyes = true,
		noMouth = true,
		blushX = 0.72,
		blushY = -0.15,
	})
	for _, sx in SIDES do
		local bc = c.H + V(sx * 0.5, 0.74, -0.45) -- 머리 밖으로 살짝 나오게 (눈이 안 묻히도록)
		ell(b, "EyeBulb", V(0.62, 0.6, 0.6), CFrame.new(bc), G)
		table.insert(c.eyes, addEye(b, bc, V(0.31, 0.3, 0.3), 0, 0.02, V(0.34, 0.38, 0.14), 0))
	end
	local p, n = front(c.H, c.HS, 0, -0.28)
	ell(b, "Mouth", V(0.5, 0.08, 0.06), facing(p - n * 0.01, n), MOUTH)
	for _, sx in SIDES do
		local np, nn = front(c.H, c.HS, sx * 0.12, -0.06)
		ell(b, "Nostril", V(0.06, 0.05, 0.04), facing(np, nn), darker(G, 0.4))
	end
	for _, d in { V(0.45, 0.55, 0.7), V(-0.5, 0.4, 0.75), V(0.05, 0.8, 0.6) } do
		local sp, sn = surf(c.H, c.HS, d)
		ell(b, "Spot", V(0.3, 0.26, 0.06), facing(sp, sn), RGB(90, 170, 70))
	end
end

-- 펭귄: 남색, 흰 얼굴/배, 주황 부리와 발, 납작 날개
PET_BUILDERS.Penguin = function(b: Builder)
	local N = RGB(55, 72, 110)
	local c = chibi(b, {
		body = N,
		belly = RGB(250, 250, 252),
		feet = RGB(255, 160, 50),
		noArms = true,
		noMouth = true,
		face = { color = RGB(255, 255, 255), semi = V(0.82, 0.72, 0.6), offset = V(0, -0.12, -0.42) },
		eyeX = 0.34,
		eyeY = 0.1,
		blushX = 0.58,
		blushY = -0.18,
	})
	local p, n = front(c.FC, c.FS, 0, -0.18)
	ell(b, "Beak", V(0.3, 0.18, 0.28), facing(p + n * 0.06, n), RGB(255, 160, 50))
	for _, sx in SIDES do
		local fp, fn = surf(c.B, c.BS, V(sx, 0.15, 0))
		ell(b, "Flipper", V(0.22, 0.85, 0.5), CFrame.new(fp + fn * 0.04) * CFrame.Angles(0, 0, sx * 0.3), N)
	end
	-- 머리 위 깃털 한 가닥
	local top = c.H + V(0, c.HS.Y, 0)
	ell(b, "Tuft", V(0.14, 0.36, 0.14), CFrame.new(top + V(0.05, 0.08, 0)) * CFrame.Angles(0, 0, -0.4), N)
end

-- 곰돌이: 갈색, 동그란 귀(안쪽 베이지), 베이지 주둥이 + 까만 코, 동그란 꼬리
PET_BUILDERS.Bear = function(b: Builder)
	local Br = RGB(170, 112, 72)
	local Tn = RGB(240, 210, 170)
	local c = chibi(b, { body = Br, belly = Tn, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
	muzzle(c, V(0.6, 0.42, 0.38), Tn, RGB(50, 35, 30), -0.32)
	roundEars(c, 0.62, 0.78, 0.56, Br, Tn)
	local tp, tn = surf(c.B, c.BS, V(0, -0.2, 1))
	ell(b, "Tail", V(0.35, 0.35, 0.35), CFrame.new(tp + tn * 0.05), Br)
	-- 빨간 리본 (머리 옆)
	local rp, rn = surf(c.H, c.HS, V(0.75, 0.6, -0.45))
	local rcf = facing(rp + rn * 0.04, rn)
	for _, sx in SIDES do
		ell(b, "Bow", V(0.3, 0.22, 0.1), rcf * CFrame.new(sx * 0.13, 0, 0) * CFrame.Angles(0, 0, sx * 0.3), RGB(255, 90, 110))
	end
end

-- 여우: 주황, 흰 볼/배, 큰 뾰족 귀, 갈색 발, 흰 끝 복슬 꼬리
PET_BUILDERS.Fox = function(b: Builder)
	local O = RGB(245, 125, 50)
	local Wt = RGB(255, 250, 240)
	local Dk = RGB(95, 60, 45)
	local c = chibi(b, { body = O, belly = Wt, feet = Dk, arms = Dk, eyeY = 0.06, noMouth = true, blushX = 0.7, blushY = -0.2 })
	for _, sx in SIDES do
		local p, n = front(c.H, c.HS, sx * 0.22, -0.36)
		ell(b, "Cheek", V(0.6, 0.45, 0.35), facing(p - n * 0.08, n), Wt)
	end
	smallNose(c, -0.22, V(0.18, 0.12, 0.1), RGB(40, 30, 30), 0.05)
	local mp, mn = front(c.H, c.HS, 0, -0.4)
	ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), MOUTH)
	pointyEars(c, 0.55, 0.85, 0.62, 0.75, 0.15, 0.28, O, RGB(255, 235, 215))
	local tp = surf(c.B, c.BS, V(0, -0.2, 1))
	local dir = V(0, 0.55, 1).Unit
	local tc = tp + dir * 0.5
	ell(b, "Tail", V(0.62, 0.62, 1.2), CFrame.lookAt(tc, tc + dir), O)
	ell(b, "TailTip", V(0.5, 0.5, 0.5), CFrame.new(tc + dir * 0.55), Wt)
end

-- 코알라: 회색, 크고 복슬한 귀(흰 안쪽), 큰 까만 코, 유칼립투스 잎
PET_BUILDERS.Koala = function(b: Builder)
	local G = RGB(160, 165, 178)
	local c = chibi(b, {
		body = G,
		belly = RGB(230, 230, 236),
		HS = V(1.12, 0.95, 0.98),
		eyeX = 0.46,
		eyeY = 0.1,
		mouthY = -0.5,
		blushX = 0.78,
		blushY = -0.2,
	})
	smallNose(c, -0.15, V(0.36, 0.46, 0.22), RGB(60, 55, 70), 0.04)
	for _, sx in SIDES do
		local ec = c.H + V(sx * 1.0, 0.55, 0.05)
		ell(b, "Ear", V(0.85, 0.8, 0.32), CFrame.new(ec), G)
		ell(b, "EarFluff", V(0.55, 0.5, 0.1), CFrame.new(ec + V(sx * 0.05, 0, -0.13)), RGB(245, 245, 250))
	end
	local ap = surf(c.B, c.BS, V(1, -0.05, -0.45))
	ell(b, "Leaf", V(0.24, 0.5, 0.06), CFrame.new(ap + V(0.05, 0.3, -0.14)) * CFrame.Angles(0, 0, -0.4), RGB(110, 190, 100))
end

-- 판다: 흰 몸, 까만 귀/팔/발, 기울어진 눈 패치, 대나무
PET_BUILDERS.Panda = function(b: Builder)
	local Wt = RGB(250, 250, 250)
	local Bk = RGB(40, 40, 48)
	local c = chibi(b, {
		body = Wt,
		feet = Bk,
		arms = Bk,
		eyeY = 0,
		eyeLift = 0.06,
		eyeSize = V(0.32, 0.44, 0.16),
		mouthY = -0.4,
		blushX = 0.76,
		blushY = -0.3,
	})
	for _, sx in SIDES do
		local p, n = front(c.H, c.HS, sx * 0.4, -0.02)
		ell(b, "EyePatch", V(0.52, 0.68, 0.14), facing(p, n) * CFrame.Angles(0, 0, sx * 0.45), Bk)
	end
	smallNose(c, -0.24, V(0.22, 0.14, 0.1), Bk, 0.03)
	roundEars(c, 0.62, 0.78, 0.52, Bk, nil)
	addPart(b, "Bamboo", "Cyl", V(1.1, 0.18, 0.18), CFrame.new(0.95, 1.05, -0.55) * CFrame.Angles(0, 0, math.pi / 2 - 0.25), RGB(130, 200, 90))
	ell(b, "BambooLeaf", V(0.12, 0.4, 0.06), CFrame.new(1.17, 1.66, -0.55) * CFrame.Angles(0, 0, -0.6), RGB(90, 170, 70))
end

-- 부엉이: 갈색, 크림 얼굴/배, 귀깃(뿔깃), 노란 부리, 날개, 배 무늬
PET_BUILDERS.Owl = function(b: Builder)
	local Br = RGB(150, 108, 78)
	local Cr = RGB(245, 228, 200)
	local Dk = RGB(115, 80, 55)
	local c = chibi(b, {
		body = Br,
		belly = Cr,
		feet = RGB(250, 190, 70),
		noArms = true,
		noMouth = true,
		face = { color = Cr, semi = V(0.9, 0.72, 0.6), offset = V(0, -0.08, -0.42) },
		eyeX = 0.36,
		eyeY = 0.08,
		eyeSize = V(0.42, 0.52, 0.16),
		blushX = 0.64,
		blushY = -0.2,
	})
	local p, n = front(c.FC, c.FS, 0, -0.1)
	ell(b, "Beak", V(0.18, 0.28, 0.16), facing(p + n * 0.05, n), RGB(250, 170, 60))
	pointyEars(c, 0.6, 0.8, 0.42, 0.55, 0.14, 0.45, Dk)
	for _, sx in SIDES do
		local wp, wn = surf(c.B, c.BS, V(sx, 0.1, 0.15))
		ell(b, "Wing", V(0.3, 0.95, 0.75), CFrame.new(wp + wn * 0.02) * CFrame.Angles(0, 0, sx * 0.18), Dk)
	end
	for _, m in { V(-0.2, 0.15, 0.4), V(0.2, 0.15, -0.4), V(0, -0.12, 0.4) } do
		local bp, bn = front(c.BeC, c.BeS, m.X, m.Y)
		ell(b, "Mark", V(0.2, 0.08, 0.05), facing(bp, bn) * CFrame.Angles(0, 0, m.Z), Br)
	end
end

-- 우파루파: 분홍, 넓은 얼굴, 양옆 아가미 6개, 웃는 입, 꼬리 지느러미
PET_BUILDERS.Axolotl = function(b: Builder)
	local P = RGB(255, 178, 208)
	local M = RGB(240, 95, 160)
	local c = chibi(b, {
		body = P,
		belly = RGB(255, 225, 235),
		HS = V(1.2, 0.9, 0.95),
		feet = RGB(255, 150, 190),
		noMouth = true,
		eyeX = 0.52,
		eyeY = 0.02,
		eyeSize = V(0.3, 0.42, 0.16),
		blushX = 0.82,
		blushY = -0.22,
	})
	local p, n = front(c.H, c.HS, 0, -0.3)
	ell(b, "Mouth", V(0.42, 0.07, 0.06), facing(p, n), MOUTH)
	local attach = { V(1, 0.6, 0), V(1, 0.15, 0), V(1, -0.3, 0) }
	local dirs = { V(0.45, 1, 0.25), V(1, 0.45, 0.25), V(1, -0.05, 0.25) }
	for _, sx in SIDES do
		for i, a in attach do
			local gp = surf(c.H, c.HS, V(sx * a.X, a.Y, a.Z))
			local dv = dirs[i]
			local d = V(sx * dv.X, dv.Y, dv.Z).Unit
			ell(b, "Gill", V(0.16, 0.62, 0.16), alongY(gp + d * 0.24, d), M)
		end
	end
	local tp = surf(c.B, c.BS, V(0, -0.25, 1))
	ell(b, "Tail", V(0.4, 0.42, 0.9), CFrame.new(tp + V(0, 0.05, 0.3)), P)
	ell(b, "TailFin", V(0.1, 0.7, 1.1), CFrame.new(tp + V(0, 0.1, 0.45)), RGB(255, 205, 225))
end

-- 유니콘: 하얀 몸, 금색 뿔(줄무늬 링), 파스텔 갈기/꼬리, 속눈썹, 라벤더 발굽
PET_BUILDERS.Unicorn = function(b: Builder)
	local W = RGB(252, 246, 255)
	local PINK = RGB(255, 170, 210)
	local PURPLE = RGB(200, 160, 255)
	local BLUE = RGB(150, 200, 255)
	local MINT = RGB(160, 235, 200)
	local c = chibi(b, { body = W, feet = RGB(205, 175, 245), eyeY = 0, blushY = -0.3 })
	for i, cf in c.eyes do
		local sx = if i == 1 then -1 else 1
		addPart(b, "Lash", "Block", V(0.14, 0.04, 0.04), cf * CFrame.new(sx * 0.19, 0.2, -0.03) * CFrame.Angles(0, 0, sx * 0.6), EYE)
	end
	-- 뿔
	local hp = surf(c.H, c.HS, V(0, 1, -0.4))
	local hd = V(0, 1, -0.35).Unit
	local hc = hp + hd * 0.32
	ell(b, "Horn", V(0.26, 0.8, 0.26), alongY(hc, hd), RGB(255, 215, 100))
	for i, h in { -0.12, 0.12 } do
		local r = 0.13 * math.sqrt(1 - (h / 0.4) ^ 2)
		local D = 2 * r + 0.05
		addPart(b, "HornRing", "Cyl", V(0.05, D, D), alongX(hc + hd * h, hd), if i == 1 then PINK else BLUE)
	end
	-- 갈기
	local maneDirs = { V(0.3, 1, -0.25), V(0, 0.85, 0.55), V(0, 0.3, 1), V(0, -0.25, 0.95) }
	local maneCols = { PINK, PURPLE, BLUE, MINT }
	local maneSizes = { 0.48, 0.58, 0.58, 0.52 }
	for i, d in maneDirs do
		local mp, mn = surf(c.H, c.HS, d)
		local s = maneSizes[i]
		ell(b, "Mane", V(s, s, s), CFrame.new(mp + mn * 0.05), maneCols[i])
	end
	pointyEars(c, 0.6, 0.8, 0.36, 0.46, 0.12, 0.35, W)
	-- 꼬리
	local tp = surf(c.B, c.BS, V(0, 0, 1))
	ell(b, "Tail", V(0.45, 0.45, 0.45), CFrame.new(tp + V(0, 0, 0.12)), PINK)
	ell(b, "Tail", V(0.4, 0.4, 0.4), CFrame.new(tp + V(0, -0.18, 0.4)), PURPLE)
	ell(b, "Tail", V(0.36, 0.36, 0.36), CFrame.new(tp + V(0, -0.4, 0.55)), BLUE)
end

-- 아기 용: 초록, 크림 배, 작은 뿔, 복숭아색 날개, 등 가시, 끝이 뾰족한 꼬리
PET_BUILDERS.Dragon = function(b: Builder)
	local G = RGB(110, 215, 140)
	local Or = RGB(255, 175, 90)
	local c = chibi(b, { body = G, belly = RGB(250, 240, 190), feet = darker(G, 0.15), eyeY = 0.04 })
	for _, sx in SIDES do
		local d = V(sx * 0.35, 1, 0.45)
		local p = surf(c.H, c.HS, V(sx * 0.45, 1, 0.1))
		ell(b, "Horn", V(0.2, 0.55, 0.2), alongY(p + d.Unit * 0.18, d), RGB(255, 245, 215))
	end
	for _, sx in SIDES do
		local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
		ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(G, 0.35))
	end
	for _, sx in SIDES do
		local base = c.B + V(sx * 0.3, 0.4, 0.5)
		local frame = frameUp(base, V(sx, 0.8, 0.5), Vector3.zAxis)
		tri(b, "Wing", frame, 0.8, 1.2, 0.08, Or)
	end
	local spikes = {
		{ c.H, c.HS, V(0, 0.55, 1) },
		{ c.H, c.HS, V(0, 0, 1) },
		{ c.B, c.BS, V(0, 0.6, 1) },
	}
	for _, s in spikes do
		local sp, sn = surf(s[1], s[2], s[3])
		ell(b, "Spike", V(0.14, 0.32, 0.26), alongY(sp + sn * 0.08, sn), Or)
	end
	local tp = surf(c.B, c.BS, V(0, -0.4, 1))
	local d1 = V(0, 0.15, 1).Unit
	local t1 = tp + d1 * 0.35
	ell(b, "Tail", V(0.5, 0.5, 0.9), CFrame.lookAt(t1, t1 + d1), G)
	local d2 = V(0, 0.6, 1).Unit
	local t2 = t1 + d1 * 0.4 + d2 * 0.3
	ell(b, "Tail", V(0.3, 0.3, 0.65), CFrame.lookAt(t2, t2 + d2), G)
	local t3 = t2 + d2 * 0.36
	ell(b, "TailTip", V(0.12, 0.38, 0.3), alongY(t3, d2), Or)
end

-- 불사조: 불꽃색 몸, 금 부리, 네온 볏 3개, 불꽃 날개, 긴 네온 꼬리깃
PET_BUILDERS.Phoenix = function(b: Builder)
	local R = RGB(255, 105, 50)
	local Yl = RGB(255, 215, 90)
	local c = chibi(b, {
		body = R,
		head = RGB(255, 140, 60),
		belly = Yl,
		feet = RGB(255, 190, 60),
		noArms = true,
		noMouth = true,
		eyeY = 0.02,
	})
	local p, n = front(c.H, c.HS, 0, -0.24)
	ell(b, "Beak", V(0.28, 0.2, 0.28), facing(p + n * 0.06, n), RGB(255, 210, 80))
	local crestDirs = { V(0, 1, 0.3), V(0.38, 0.9, 0.4), V(-0.38, 0.9, 0.4) }
	local crestCols = { RGB(255, 230, 90), RGB(255, 160, 40), RGB(255, 160, 40) }
	for i, d in crestDirs do
		local cp = surf(c.H, c.HS, d)
		ell(b, "Crest", V(0.18, 0.72, 0.18), alongY(cp + d.Unit * 0.28, d), crestCols[i], Enum.Material.Neon)
	end
	for _, sx in SIDES do
		local cf = CFrame.new(c.B + V(sx * 0.95, 0.2, 0.15)) * CFrame.Angles(0, 0, -sx * 0.55)
		ell(b, "Wing", V(0.28, 1.0, 0.75), cf, R)
		ell(b, "WingTip", V(0.2, 0.55, 0.5), cf * CFrame.new(0, 0.5, 0.05), Yl, Enum.Material.Neon)
	end
	local tp = surf(c.B, c.BS, V(0, -0.1, 1))
	local tailDirs = { V(0, 0.5, 1), V(0.45, 0.35, 1), V(-0.45, 0.35, 1) }
	local tailCols = { RGB(255, 200, 60), RGB(255, 120, 40), RGB(255, 120, 40) }
	for i, d in tailDirs do
		local u = d.Unit
		ell(b, "TailFeather", V(0.22, 0.22, 1.1), CFrame.lookAt(tp + u * 0.5, tp + u * 1.5), tailCols[i], Enum.Material.Neon)
	end
end

-- 무지개 냥이: 하얀 고양이, 분홍 귀, 이마 무지개 줄무늬, 무지개 공 꼬리
PET_BUILDERS.RainbowCat = function(b: Builder)
	local W = RGB(255, 246, 252)
	local c = chibi(b, { body = W, feet = RGB(255, 220, 240), eyeY = 0.05, blushY = -0.22, mouthY = -0.38 })
	pointyEars(c, 0.55, 0.85, 0.6, 0.62, 0.16, 0.3, RGB(255, 190, 225))
	smallNose(c, -0.22, V(0.16, 0.11, 0.08), RGB(255, 130, 170), 0.03)
	for i, x in { -0.32, 0, 0.32 } do
		local sp, sn = surf(c.H, c.HS, V(x, 0.95, -0.42))
		ell(b, "Stripe", V(0.16, 0.46, 0.07), facing(sp, sn), RAINBOW[i * 2 - 1])
	end
	local tp = surf(c.B, c.BS, V(0, -0.2, 1))
	ballArc(b, "Tail", tp + V(0, 0, 0.1), 0.75, RAINBOW, 0.38, 0.3)
end

----------------------------------------------------------------------
-- 알 6 종 (가로 2, 세로 2.6)
----------------------------------------------------------------------

local EGG_S = V(1, 1.3, 1)
local EGG_C = V(0, 1.3, 0)

local function eggBase(b: Builder, color: Color3, mat: Enum.Material?, transparency: number?): BasePart
	return ell(b, "Body", EGG_S * 2, CFrame.new(EGG_C), color, mat, transparency)
end

local function eggDot(b: Builder, dir: Vector3, d: number, color: Color3, mat: Enum.Material?, name: string?)
	local p, n = surf(EGG_C, EGG_S, dir)
	ell(b, name or "Spot", V(d, d * 0.9, 0.12), facing(p - n * 0.02, n), color, mat)
end

-- 알을 두르는 띠 (가로 원기둥 고리)
local function eggRing(b: Builder, y: number, t: number, color: Color3, mat: Enum.Material?): BasePart
	local yy = math.max(math.abs(y) - t / 2, 0)
	local r = EGG_S.X * math.sqrt(math.max(1 - (yy / EGG_S.Y) ^ 2, 0))
	local D = 2 * r + 0.07
	return addPart(b, "Ring", "Cyl", V(t, D, D), CFrame.new(EGG_C + V(0, y, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, mat)
end

local EGG_BUILDERS: { [string]: (Builder) -> () } = {}

-- 기본 알: 크림색에 파스텔 물방울
EGG_BUILDERS.Basic = function(b: Builder)
	eggBase(b, RGB(255, 246, 228))
	local cols = { RGB(170, 215, 255), RGB(255, 190, 215), RGB(255, 230, 140) }
	local dirs = {
		V(0.5, 0.35, -0.8),
		V(-0.55, -0.1, -0.8),
		V(0.15, -0.55, -0.8),
		V(-0.2, 0.6, -0.75),
		V(0.9, -0.3, 0.3),
		V(-0.85, 0.25, 0.4),
		V(0.1, 0.2, 1),
	}
	for i, d in dirs do
		eggDot(b, d, if i % 2 == 0 then 0.38 else 0.46, cols[(i - 1) % 3 + 1])
	end
end

-- 점박이 알: 하얀 바탕에 초록 점
EGG_BUILDERS.Spotted = function(b: Builder)
	eggBase(b, RGB(252, 252, 246))
	local dirs = {
		V(0.45, 0.4, -0.8),
		V(-0.5, 0.05, -0.85),
		V(0.2, -0.45, -0.85),
		V(-0.15, 0.75, -0.6),
		V(0.9, 0, -0.2),
		V(-0.9, -0.4, 0.1),
		V(0.6, 0.5, 0.6),
		V(-0.4, 0.2, 0.9),
		V(0.3, -0.5, 0.8),
		V(0, 1, 0.1),
	}
	for i, d in dirs do
		local big = i % 3 ~= 0
		eggDot(b, d, if big then 0.55 else 0.32, if big then RGB(100, 200, 115) else RGB(170, 230, 150))
	end
end

-- 숲속 알: 연두 바탕, 둘레 나뭇잎, 머리에 새싹, 작은 꽃
EGG_BUILDERS.Forest = function(b: Builder)
	eggBase(b, RGB(175, 215, 130))
	for i = 1, 5 do
		local a = i * math.pi * 2 / 5 + 0.3
		local p, n = surf(EGG_C, EGG_S, V(math.cos(a), -0.35, math.sin(a)))
		ell(b, "Leaf", V(0.4, 0.75, 0.1), facing(p - n * 0.02, n) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.4 else -0.4), RGB(70, 155, 75))
	end
	local topY = EGG_C.Y + EGG_S.Y
	addPart(b, "Stem", "Cyl", V(0.4, 0.1, 0.1), CFrame.new(0, topY + 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(110, 170, 60))
	for _, sx in SIDES do
		ell(b, "Sprout", V(0.45, 0.12, 0.24), CFrame.new(sx * 0.2, topY + 0.3, 0) * CFrame.Angles(0, 0, sx * 0.4), RGB(120, 200, 80))
	end
	local flowers = { V(0.4, 0.35, -0.8), V(-0.45, 0.5, -0.7), V(0.7, 0.6, 0.3) }
	local fcols = { WHITE, RGB(255, 190, 215), RGB(255, 235, 120) }
	for i, d in flowers do
		eggDot(b, d, 0.26, fcols[i], nil, "Flower")
	end
end

-- 크리스탈 알: 보라 유리 + 빛나는 속, 삐죽 크리스탈 조각
EGG_BUILDERS.Crystal = function(b: Builder)
	eggBase(b, RGB(185, 140, 255), Enum.Material.Glass, 0.2)
	-- 유리 뒤의 반투명 파트는 고화질에서 안 보여서 속은 불투명 네온으로
	ell(b, "Core", V(1.3, 1.8, 1.3), CFrame.new(EGG_C), RGB(235, 200, 255), Enum.Material.Neon, 0)
	local dirs = {
		V(0.7, 0.4, -0.6),
		V(-0.6, -0.1, -0.8),
		V(0.2, -0.5, -0.85),
		V(-0.8, 0.5, 0.3),
		V(0.85, -0.2, 0.5),
		V(0, 0.3, 1),
		V(-0.3, 0.85, -0.4),
	}
	for i, d in dirs do
		local p, n = surf(EGG_C, EGG_S, d)
		local col = if i % 2 == 0 then RGB(255, 170, 240) else RGB(150, 230, 255)
		addPart(b, "Crystal", "Block", V(0.28, 0.5, 0.28), alongY(p + n * 0.08, n) * CFrame.Angles(0, math.pi / 4, 0), col, Enum.Material.Glass, 0.1)
	end
	for _, d in { V(0.35, 0.7, -0.6), V(-0.5, -0.5, -0.7), V(0.6, -0.1, -0.75) } do
		eggDot(b, d, 0.12, WHITE, Enum.Material.Neon, "Sparkle")
	end
end

-- 황금 알: 금속 금색 + 보석 띠 + 반짝 하이라이트
EGG_BUILDERS.Golden = function(b: Builder)
	local body = eggBase(b, RGB(255, 198, 45), Enum.Material.Metal)
	body.Reflectance = 0.2
	eggRing(b, 0, 0.24, RGB(255, 235, 140), Enum.Material.Metal)
	local gems = { RGB(255, 70, 90), RGB(70, 150, 255), RGB(70, 220, 120), RGB(255, 120, 220) }
	for i, col in gems do
		local a = (i - 1) * math.pi / 2 - math.pi / 2 -- 첫 보석은 정면(-Z)
		local d = V(math.cos(a), 0, math.sin(a))
		local p = EGG_C + d * 1.06
		ell(b, "Gem", V(0.28, 0.28, 0.16), facing(p, d), col)
	end
	local sp, sn = surf(EGG_C, EGG_S, V(-0.55, 0.45, -0.7))
	ell(b, "Shine", V(0.2, 0.7, 0.06), facing(sp, sn) * CFrame.Angles(0, 0, -0.5), WHITE, Enum.Material.Neon, 0.25)
	eggDot(b, V(-0.3, 0.75, -0.55), 0.14, WHITE, Enum.Material.Neon, "Sparkle")
	eggDot(b, V(0.5, -0.5, -0.7), 0.12, WHITE, Enum.Material.Neon, "Sparkle")
	-- 꼭대기 작은 왕관 구슬
	ell(b, "Crown", V(0.3, 0.3, 0.3), CFrame.new(0, EGG_C.Y + EGG_S.Y + 0.05, 0), RGB(255, 235, 140), Enum.Material.Metal)
end

-- 무지개 알: 하얀 진주빛 + 무지개 띠 6줄 + 반짝이
EGG_BUILDERS.Rainbow = function(b: Builder)
	local body = eggBase(b, RGB(255, 252, 255))
	body.Reflectance = 0.1
	local ys = { 0.75, 0.45, 0.15, -0.15, -0.45, -0.75 }
	for i, y in ys do
		eggRing(b, y, 0.18, RAINBOW[i])
	end
	for _, d in { V(0.2, 1, -0.3), V(-0.5, 0.8, -0.4), V(0.6, -0.95, -0.5) } do
		eggDot(b, d, 0.16, WHITE, Enum.Material.Neon, "Sparkle")
	end
end

----------------------------------------------------------------------
-- 마무리: 용접 + 피벗
----------------------------------------------------------------------

----------------------------------------------------------------------
-- 추가 펫/알 모듈: 이 폴더(PetModels) 안의 다른 ModuleScript 는
-- function(Kit, PET_BUILDERS, EGG_BUILDERS) 를 돌려주고, 거기서 빌더를 등록해요.
----------------------------------------------------------------------

local Kit = {
	V = V,
	RGB = RGB,
	EYE = EYE,
	WHITE = WHITE,
	BLACK = BLACK,
	BLUSH = BLUSH,
	MOUTH = MOUTH,
	RAINBOW = RAINBOW,
	SIDES = SIDES,
	addPart = addPart,
	ell = ell,
	darker = darker,
	surf = surf,
	front = front,
	facing = facing,
	alongY = alongY,
	alongX = alongX,
	frameUp = frameUp,
	tri = tri,
	addEye = addEye,
	chibi = chibi,
	pointyEars = pointyEars,
	roundEars = roundEars,
	muzzle = muzzle,
	smallNose = smallNose,
	ballArc = ballArc,
	EGG_S = EGG_S,
	EGG_C = EGG_C,
	eggBase = eggBase,
	eggDot = eggDot,
	eggRing = eggRing,
}

for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, err = pcall(function()
			local register = (require :: any)(child)
			if type(register) == "function" then
				register(Kit, PET_BUILDERS, EGG_BUILDERS)
			end
		end)
		if not ok then
			warn("[PetModels] 추가 모듈 오류 (" .. child.Name .. "): " .. tostring(err))
		end
	end
end

-- 모델 안 모든 파트의 월드 AABB
local function bounds(model: Model): (Vector3, Vector3)
	local minV = V(math.huge, math.huge, math.huge)
	local maxV = V(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			local s = d.Size * 0.5
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ext = V(
				math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
				math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
				math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
			)
			minV = minV:Min(cf.Position - ext)
			maxV = maxV:Max(cf.Position + ext)
		end
	end
	if minV.X == math.huge then
		return Vector3.zero, Vector3.zero
	end
	return minV, maxV
end

local function finish(b: Builder): Model
	local model = b.model
	local body = model:FindFirstChild("Body") :: BasePart
	model.PrimaryPart = body
	for _, p in b.parts do
		if p == body then
			p.Massless = false
		else
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
		end
	end
	local minV = bounds(model)
	model.WorldPivot = CFrame.new(body.Position.X, minV.Y, body.Position.Z)
	return model
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 눈/반짝이/볼터치는 등급 색을 입히지 않음
local KEEP_COLOR = { Eye = true, Shine = true, Blush = true, EyeWhite = true, Pupil = true }

local GOLD = RGB(255, 200, 60)

-- 합성 등급 색 입히기. 2 = 황금, 3 = 무지개 (아래→위로 색이 바뀜)
local function applyTier(model: Model, tier: number)
	if tier < 2 then
		return
	end
	local minV, maxV = bounds(model)
	local span = math.max(maxV.Y - minV.Y, 0.01)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not KEEP_COLOR[d.Name] and d.Transparency < 0.95 then
			if tier == 2 then
				d.Color = d.Color:Lerp(GOLD, 0.7)
				d.Reflectance = 0.12
			else
				local t = (d.Position.Y - minV.Y) / span
				local hue = (0.98 - t * 0.78) % 1 -- 위쪽은 빨강/주황, 아래쪽은 파랑/보라
				d.Color = Color3.fromHSV(hue, 0.72, 1)
				d.Reflectance = 0.08
			end
		end
	end
	local body = model.PrimaryPart
	if not body then
		return
	end
	local light = Instance.new("PointLight")
	light.Name = "TierFx"
	light.Color = if tier == 2 then GOLD else RGB(255, 170, 230)
	light.Brightness = if tier == 2 then 0.6 else 1
	light.Range = if tier == 2 then 6 else 8
	light.Shadows = false
	light.Parent = body

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "TierFx"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	if tier == 2 then
		pe.Color = ColorSequence.new(GOLD, WHITE)
	else
		local kps = {}
		for i, c in RAINBOW do
			table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#RAINBOW - 1), c))
		end
		pe.Color = ColorSequence.new(kps)
	end
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if tier == 2 then 0.22 else 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(0.8, 1.4)
	pe.Rate = if tier == 2 then 6 else 12
	pe.Shape = Enum.ParticleEmitterShape.Sphere
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	pe.Speed = NumberRange.new(1, 2.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Drag = 1
	pe.Parent = body
end

-- tier: 1(기본) / 2(황금) / 3(무지개). 생략하면 1
function PetModels.BuildPet(petId: string, tier: number?): Model
	local fn = PET_BUILDERS[petId]
	if not fn then
		warn("[PetModels] 알 수 없는 펫: " .. tostring(petId))
		fn = PET_BUILDERS.Chick
	end
	local b = newBuilder(petId)
	fn(b)
	local model = finish(b)
	applyTier(model, math.clamp(tier or 1, 1, 3))
	return model
end

function PetModels.HasPet(petId: string): boolean
	return PET_BUILDERS[petId] ~= nil
end

function PetModels.HasEgg(eggId: string): boolean
	return EGG_BUILDERS[eggId] ~= nil
end

function PetModels.BuildEgg(eggId: string): Model
	local fn = EGG_BUILDERS[eggId]
	if not fn then
		warn("[PetModels] 알 수 없는 알: " .. tostring(eggId))
		fn = EGG_BUILDERS.Basic
	end
	local b = newBuilder(eggId)
	fn(b)
	return finish(b)
end

-- Epic 이상: 반짝이 파티클 + 은은한 빛 (희귀도 색)
function PetModels.AddRarityEffects(model: Model, rarity: string)
	local rarities = Config.Rarities :: { [string]: RarityInfo }
	local info = rarities[rarity]
	if not info or info.Order < 4 then
		return
	end
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not body then
		return
	end
	for _, child in body:GetChildren() do
		if child.Name == "RarityFx" then
			child:Destroy()
		end
	end
	local col = info.Color
	local level = math.clamp(info.Order - 3, 1, 3) -- Epic 1, Legendary 2, Mythic 3

	local light = Instance.new("PointLight")
	light.Name = "RarityFx"
	light.Color = col
	light.Brightness = 0.3 + 0.5 * level
	light.Range = 4 + 3 * level
	light.Shadows = false
	light.Parent = body

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "RarityFx"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	if level >= 3 then
		local kps = {}
		for i, c in RAINBOW do
			table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#RAINBOW - 1), c))
		end
		pe.Color = ColorSequence.new(kps)
	else
		pe.Color = ColorSequence.new(col, WHITE)
	end
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12 + 0.08 * level),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(0.8, 1.5)
	pe.Rate = if level == 1 then 3 elseif level == 2 then 7 else 12
	-- 몸 표면에서 바깥쪽으로 뿌려야 몸속에 가려지지 않음
	pe.Shape = Enum.ParticleEmitterShape.Sphere
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	pe.Speed = NumberRange.new(1, 2.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Drag = 1
	pe.Parent = body
end

-- UI 용 3D 미리보기. silhouette = true 면 새까만 그림자 (도감 미발견)
function PetModels.CreateViewport(kind: string, id: string, parent: Instance, silhouette: boolean?, tier: number?): (ViewportFrame, Model)
	local vf = Instance.new("ViewportFrame")
	vf.Name = "PetViewport"
	vf.Size = UDim2.fromScale(1, 1)
	vf.AnchorPoint = Vector2.new(0.5, 0.5)
	vf.Position = UDim2.fromScale(0.5, 0.5)
	vf.BackgroundTransparency = 1
	vf.Ambient = RGB(175, 175, 185)
	vf.LightColor = RGB(255, 250, 245)
	vf.LightDirection = V(-0.4, -1, 0.8)

	local model = if kind == "Egg" then PetModels.BuildEgg(id) else PetModels.BuildPet(id, tier)

	if silhouette then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = BLACK
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0
				if d.Transparency < 0.95 then
					d.Transparency = 0
				end
			elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Sparkles") or d:IsA("Fire") or d:IsA("Decal") then
				d:Destroy()
			end
		end
		vf.Ambient = BLACK
		vf.LightColor = BLACK
	end

	model.Parent = vf

	local cam = Instance.new("Camera")
	cam.FieldOfView = 32
	cam.Parent = vf
	vf.CurrentCamera = cam

	local minV, maxV = bounds(model)
	local center = (minV + maxV) * 0.5
	local radius = math.max((maxV - minV).Magnitude * 0.5, 0.5)
	local dist = radius / math.sin(math.rad(cam.FieldOfView * 0.5)) * 0.85
	local dir = V(0.45, 0.32, -1).Unit -- 앞(-Z) 오른쪽 위에서
	cam.CFrame = CFrame.lookAt(center + dir * dist, center)

	vf.Parent = parent
	return vf, model
end

return PetModels
