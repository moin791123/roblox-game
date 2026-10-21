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

type RarityInfo = { Name: string, Color: Color3, Order: number, Special: boolean?, Rainbow: boolean? }

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

-- 비스듬한 띠 (사선 줄무늬): 중심 기준 높이 y 에서 Z 축으로 tilt 만큼 기운 고리.
-- 기운 면이 알을 자른 단면(타원)의 가운데로 고리 중심을 옮기고, 고리 판 3장(윗면/가운데/아랫면)에서
-- 껍데기까지 가장 먼 거리 + 0.025 를 반지름으로 써요 → 어디서도 안 묻히고 턱도 작아요.
local function eggTiltBand(b: Builder, name: string, y: number, tilt: number, t: number, color: Color3, mat: Enum.Material?): BasePart
	local AX, AY = EGG_S.X, EGG_S.Y
	local axis = V(-math.sin(tilt), math.cos(tilt), 0)
	local u = V(math.cos(tilt), math.sin(tilt), 0)
	local K = u.X * u.X / (AX * AX) + u.Y * u.Y / (AY * AY)
	local oc = V(0, y, 0) + u * (-(y * u.Y) / (AY * AY) / K) -- 단면 타원의 가운데 (알 중심 기준)
	local far = 0
	for _, s in { -t / 2, 0, t / 2 } do
		local o = oc + axis * s
		for i = 0, 23 do
			local a = i * math.pi / 12
			local dv = u * math.cos(a) + Vector3.zAxis * math.sin(a)
			-- o + k·dv 가 껍데기 위에 오는 k (양수 근)
			local A = (dv.X * dv.X + dv.Z * dv.Z) / (AX * AX) + dv.Y * dv.Y / (AY * AY)
			local B = 2 * ((o.X * dv.X + o.Z * dv.Z) / (AX * AX) + o.Y * dv.Y / (AY * AY))
			local C = (o.X * o.X + o.Z * o.Z) / (AX * AX) + o.Y * o.Y / (AY * AY) - 1
			local disc = B * B - 4 * A * C
			if disc > 0 then
				far = math.max(far, (-B + math.sqrt(disc)) / (2 * A))
			end
		end
	end
	local D = 2 * (far + 0.025)
	return addPart(b, name, "Cyl", V(t, D, D), CFrame.new(EGG_C + oc) * CFrame.Angles(0, 0, math.pi / 2 + tilt), color, mat)
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
-- 펫 옷(액세서리) 빌더 표 + 맞춤 정보
----------------------------------------------------------------------

-- 옷 빌더가 받는 맞춤 정보. 위치는 모두 "앵커 기준 로컬 좌표" (앞 = -Z, 위 = +Y, 원점 = 앵커),
-- 펫 크기 1 기준 스터드이고 s 가 이미 들어 있어요. 빌더는 원점 둘레에 파트를 만들면 돼요.
export type AccFit = {
	slot: string, -- "Head" | "Face" | "Neck" | "Back"
	s: number, -- 크기 배율 (0.6 ~ 2, 펫 크기에 맞춤)
	mouth: Vector3, -- Face: 콧수염 자리 (코 바로 아래)
	rx: number, -- Neck: 목 둘레 가로 반지름
	rz: number, -- Neck: 목 둘레 앞뒤 반지름
	ring: Vector3, -- Neck: 목 고리 중심
	chest: Vector3, -- Neck: 가슴 앞면 (메달 원판 자리)
	neck: Vector3, -- Back: 목 뒤 (망토 윗변)
	drop: number, -- Back/Neck: 앵커에서 아래로 늘어뜨릴 수 있는 길이 (바닥/펫 맨 아래까지)
	opaque: boolean, -- 유리 헬멧 안이면 true (반투명 파트를 불투명하게 바꿔요)
}

local ACC_BUILDERS: { [string]: (Builder, AccFit) -> () } = {}

-- 펫 없이 만들 때 (상점 미리보기) 쓰는 기본 맞춤 정보 = 기본 꼬마 몸 기준
local function defaultFit(slot: string): AccFit
	return {
		slot = slot,
		s = 1,
		mouth = Vector3.zero,
		rx = 0.74,
		rz = 0.68,
		ring = V(0, 0, 0.68),
		chest = V(0, -0.42, -0.2),
		neck = V(0, 0.32, -0.15),
		drop = 0.9,
		opaque = false,
	}
end

-- 눈/반짝이/볼터치/입은 등급 색을 입히지 않음. 펫 빌더는 파트에 KeepColor = true 속성을 달아도 돼요.
local KEEP_COLOR = {
	Eye = true,
	EyeWhite = true,
	Pupil = true,
	Shine = true,
	Blush = true,
	Lash = true,
	Mouth = true,
	Tongue = true,
}

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

-- 빌더 목록과 모델에서 이름이 name 인 파트를 빼고 지워요 (기본 몸 파트 바꿔 끼우기)
local function dropParts(b: Builder, name: string)
	for i = #b.parts, 1, -1 do
		local p = b.parts[i]
		if p.Name == name then
			table.remove(b.parts, i)
			p:Destroy()
		end
	end
end

-- 펫 빌더용: 옷 자리를 직접 정하고 싶을 때 Body 에 Attachment "Acc<slot>" 를 붙여요.
-- slot = "Head" | "Face" | "Neck" | "Back", cf = 빌드 공간(월드) CFrame, 앞 = -Z, 위 = +Y
local function accAnchor(b: Builder, slot: string, cf: CFrame)
	local body = b.model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		local att = Instance.new("Attachment")
		att.Name = "Acc" .. slot
		att.CFrame = body.CFrame:ToObjectSpace(cf)
		att.Parent = body
	end
end

----------------------------------------------------------------------
-- 추가 펫/알/옷 모듈: 이 폴더(PetModels) 안의 다른 ModuleScript 는
-- function(Kit, PET_BUILDERS, EGG_BUILDERS, ACC_BUILDERS) 를 돌려주고, 거기서 빌더를 등록해요.
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
	-- v3 추가
	NEON = Enum.Material.Neon,
	KEEP_COLOR = KEEP_COLOR,
	bounds = bounds,
	dropParts = dropParts,
	accAnchor = accAnchor,
	-- v4: 무늬 알 (EggsPattern.luau 가 채워요). Config.Eggs[id].Look 표로 알을 만들어요
	eggTiltBand = eggTiltBand, -- (b, name, y, tilt, t, color, mat?) 껍데기에 딱 붙는 사선 띠
	eggFromLook = nil :: ((Builder, any) -> ())?,
	EGG_PATTERNS = {} :: { string },
}

for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, err = pcall(function()
			local register = (require :: any)(child)
			if type(register) == "function" then
				register(Kit, PET_BUILDERS, EGG_BUILDERS, ACC_BUILDERS)
			end
		end)
		if not ok then
			warn("[PetModels] 추가 모듈 오류 (" .. child.Name .. "): " .. tostring(err))
		end
	end
end

----------------------------------------------------------------------
-- 마무리: 용접 + 피벗
----------------------------------------------------------------------

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
-- 모양 재기 도우미 (옷 자리 찾기 / 갤럭시 별 점)
----------------------------------------------------------------------

-- 파트의 보이는 모양: kind = "Ball"(타원체) | "Cyl"(X축 원기둥) | "Box", half = 반지름, lo/hi = AABB
type Shape = { part: BasePart, kind: string, cf: CFrame, half: Vector3, lo: Vector3, hi: Vector3 }

-- toLocal/k 를 주면 펫 피벗 기준 "크기 1" 공간으로 바꿔서 재요
local function shapeOf(p: BasePart, toLocal: CFrame?, k: number?): Shape
	local kind = "Box"
	local half = p.Size * 0.5
	local cf = p.CFrame
	local mesh = p:FindFirstChildWhichIsA("SpecialMesh")
	if mesh then
		if mesh.MeshType == Enum.MeshType.Sphere then
			kind = "Ball"
		end
		half = half * mesh.Scale
		cf = cf * CFrame.new(mesh.Offset)
	elseif p:IsA("Part") then
		if p.Shape == Enum.PartType.Ball then
			local r = math.min(half.X, half.Y, half.Z)
			kind, half = "Ball", V(r, r, r)
		elseif p.Shape == Enum.PartType.Cylinder then
			local r = math.min(half.Y, half.Z)
			kind, half = "Cyl", V(half.X, r, r)
		end
	end
	if toLocal then
		local rel = toLocal * cf
		local kk = k or 1
		cf = rel.Rotation + rel.Position / kk
		half = half / kk
	end
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ext = V(
		math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z,
		math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z,
		math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
	)
	return { part = p, kind = kind, cf = cf, half = half, lo = cf.Position - ext, hi = cf.Position + ext }
end

-- (가장 얇은 지름, 가장 긴 지름)
local function dims(s: Shape): (number, number)
	local h = s.half
	return 2 * math.min(h.X, h.Y, h.Z), 2 * math.max(h.X, h.Y, h.Z)
end

local function centerOf(s: Shape): Vector3
	return (s.lo + s.hi) * 0.5
end

-- 광선 o + d·t 가 모양에 처음 닿는 t (안 닿으면 nil)
local function rayShape(s: Shape, o: Vector3, d: Vector3): number?
	local lo = s.cf:PointToObjectSpace(o)
	local ld = s.cf:VectorToObjectSpace(d)
	local h = s.half
	if s.kind == "Ball" then
		local a, bb = lo / h, ld / h
		local A = bb:Dot(bb)
		if A < 1e-12 then
			return nil
		end
		local B = 2 * a:Dot(bb)
		local C = a:Dot(a) - 1
		local disc = B * B - 4 * A * C
		if disc < 0 then
			return nil
		end
		local sq = math.sqrt(disc)
		if (-B + sq) / (2 * A) < 0 then
			return nil
		end
		return math.max((-B - sq) / (2 * A), 0)
	elseif s.kind == "Cyl" then
		local r = h.Y
		local best: number? = nil
		local A = ld.Y * ld.Y + ld.Z * ld.Z
		if A > 1e-12 then
			local B = 2 * (lo.Y * ld.Y + lo.Z * ld.Z)
			local C = lo.Y * lo.Y + lo.Z * lo.Z - r * r
			local disc = B * B - 4 * A * C
			if disc >= 0 then
				local t = (-B - math.sqrt(disc)) / (2 * A)
				if t >= 0 and math.abs(lo.X + ld.X * t) <= h.X then
					best = t
				end
			end
		end
		if math.abs(ld.X) > 1e-12 then
			for _, sx in SIDES do
				local t = (sx * h.X - lo.X) / ld.X
				local y, z = lo.Y + ld.Y * t, lo.Z + ld.Z * t
				if t >= 0 and y * y + z * z <= r * r and (best == nil or t < best) then
					best = t
				end
			end
		end
		return best
	end
	local tmin, tmax = -math.huge, math.huge
	local function slab(oo: number, dd: number, hh: number): boolean
		if math.abs(dd) < 1e-12 then
			return math.abs(oo) <= hh
		end
		local t1, t2 = (-hh - oo) / dd, (hh - oo) / dd
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tmin = math.max(tmin, t1)
		tmax = math.min(tmax, t2)
		return tmin <= tmax
	end
	if not (slab(lo.X, ld.X, h.X) and slab(lo.Y, ld.Y, h.Y) and slab(lo.Z, ld.Z, h.Z)) or tmax < 0 then
		return nil
	end
	return math.max(tmin, 0)
end

-- 목록 중 처음 닿는 점과 모양
local function hitAt(list: { Shape }, o: Vector3, d: Vector3): (Vector3?, Shape?)
	local bestT: number? = nil
	local bestS: Shape? = nil
	for _, s in list do
		local t = rayShape(s, o, d)
		if t and (bestT == nil or t < bestT) then
			bestT, bestS = t, s
		end
	end
	if bestT then
		return o + d * bestT, bestS
	end
	return nil, nil
end

local function insideShape(s: Shape, pt: Vector3): boolean
	local l = s.cf:PointToObjectSpace(pt)
	local h = s.half
	if s.kind == "Ball" then
		local q = l / h
		return q:Dot(q) < 1
	elseif s.kind == "Cyl" then
		return math.abs(l.X) < h.X and l.Y * l.Y + l.Z * l.Z < h.Y * h.Y
	end
	return math.abs(l.X) < h.X and math.abs(l.Y) < h.Y and math.abs(l.Z) < h.Z
end

local function overlapVol(alo: Vector3, ahi: Vector3, blo: Vector3, bhi: Vector3): number
	local x = math.min(ahi.X, bhi.X) - math.max(alo.X, blo.X)
	local y = math.min(ahi.Y, bhi.Y) - math.max(alo.Y, blo.Y)
	local z = math.min(ahi.Z, bhi.Z) - math.max(alo.Z, blo.Z)
	if x <= 0 or y <= 0 or z <= 0 then
		return 0
	end
	return x * y * z
end

local function hasName(name: string, list: { string }): boolean
	for _, w in list do
		if string.find(name, w, 1, true) then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- 합성 등급 모양 (§12, Config.Tiers[t].Visual)
----------------------------------------------------------------------

local GALAXY_LO = RGB(45, 30, 110)
local GALAXY_HI = RGB(110, 60, 200)
local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"

-- 등급이 건드리지 않는 파트: 얼굴, KeepColor 속성, 옷, 많이 투명한 파트 (유리 헬멧/거품 = 0.4 이상)
-- (젤리 용/별 슬라임처럼 살짝 투명한 몸은 색이 바뀌고, 유리 재질과 투명도는 그대로예요)
local function tierSkip(p: BasePart): boolean
	return KEEP_COLOR[p.Name] == true
		or p:GetAttribute("KeepColor") == true
		or p:GetAttribute("AccId") ~= nil
		or p.Transparency >= 0.4
end

local function colorSeq(cols: { Color3 }?, fallback: Color3): ColorSequence
	if not cols or #cols == 0 then
		return ColorSequence.new(fallback)
	end
	if #cols == 1 then
		return ColorSequence.new(cols[1])
	end
	local kps = {}
	for i, c in cols do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#cols - 1), c))
	end
	return ColorSequence.new(kps)
end

-- 같은 펫은 어디서 봐도 같은 자리에 별이 생기게 (이름으로 정한 씨앗)
local function seedOf(str: string): number
	local h = 7
	for i = 1, #str do
		h = (h * 31 + string.byte(str, i)) % 2147483647
	end
	return h + 1
end

-- 갤럭시: 몸 표면 여기저기에 작은 네온 별 (하양/노랑) 을 용접해요
local function addSpecks(model: Model, count: number)
	local body = model.PrimaryPart
	if not body then
		return
	end
	local all: { Shape } = {}
	local cands: { Shape } = {}
	local weights: { number } = {}
	local total = 0
	local avoid: { Vector3 } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			local s = shapeOf(d)
			table.insert(all, s)
			if KEEP_COLOR[d.Name] or hasName(d.Name, { "Nose", "Beak", "Mouth", "Muzzle" }) then
				table.insert(avoid, d.Position)
			elseif not tierSkip(d) and d.Transparency < 0.5 and d.Material ~= Enum.Material.Neon then
				local h = s.half
				if math.min(h.X, h.Y, h.Z) >= 0.18 then
					local area = h.X * h.Y + h.Y * h.Z + h.X * h.Z
					table.insert(cands, s)
					table.insert(weights, area)
					total += area
				end
			end
		end
	end
	if total <= 0 then
		return
	end
	local seed = seedOf(model.Name)
	local function rnd(): number
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	local b: Builder = { model = model, parts = {} }
	local placed, tries = 0, 0
	while placed < count and tries < count * 15 do
		tries += 1
		local pick = rnd() * total
		local s = cands[#cands]
		for i, w in weights do
			pick -= w
			if pick <= 0 then
				s = cands[i]
				break
			end
		end
		-- 구 위의 무작위 방향 → 모양 표면의 점
		local zz = rnd() * 2 - 1
		local a = rnd() * math.pi * 2
		local rr = math.sqrt(1 - zz * zz)
		local u = V(rr * math.cos(a), zz, rr * math.sin(a))
		local h = s.half
		local lp: Vector3
		if s.kind == "Ball" then
			lp = u / math.sqrt((u.X / h.X) ^ 2 + (u.Y / h.Y) ^ 2 + (u.Z / h.Z) ^ 2)
		elseif s.kind == "Cyl" then
			lp = u / math.max(math.abs(u.X) / h.X, math.sqrt(u.Y * u.Y + u.Z * u.Z) / h.Y, 1e-6)
		else
			lp = u / math.max(math.abs(u.X) / h.X, math.abs(u.Y) / h.Y, math.abs(u.Z) / h.Z, 1e-6)
		end
		local wp = s.cf * lp
		local n = (wp - s.cf.Position).Unit
		local ok = n.Y > -0.35
		if ok then
			for _, o in all do
				if o ~= s and o.part.Transparency < 0.5 and insideShape(o, wp + n * 0.04) then
					ok = false
					break
				end
			end
		end
		if ok then
			for _, ap in avoid do
				if (ap - wp).Magnitude < 0.42 then
					ok = false
					break
				end
			end
		end
		if ok then
			local dd = 0.15 + rnd() * 0.1
			local col = if placed % 3 == 1 then RGB(255, 235, 150) else WHITE
			local sp = ell(b, "Speck", V(dd, dd, dd), CFrame.new(wp + n * dd * 0.12), col, Enum.Material.Neon)
			sp.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = sp
			w.Parent = sp
			table.insert(avoid, wp)
			placed += 1
		end
	end
end

-- 합성 등급 색/재질/반짝이 (1 기본 ~ 7 갤럭시). 레인보우는 파트마다 TierHue 속성을 남겨요.
-- 반짝이 LightEmission: 1 이면 겹칠수록 하얗게 번쩍여요 (받침대에 여러 마리 모이면 눈부셔서 낮춰요, 0.8 → 0.6.
-- 받침대 펫은 클라이언트 WorldFx 가 0.35 까지 더 낮춰요)
local TIER_SPARKLE_EMISSION = 0.6
local function applyTier(model: Model, tier: number)
	local t = math.clamp(math.floor(tier), 1, Config.MaxTier)
	model:SetAttribute("Tier", t)
	if t <= 1 then
		return
	end
	local vis = Config.TierVisual(t)
	if not vis then
		return
	end
	local minV, maxV = bounds(model)
	local span = math.max(maxV.Y - minV.Y, 0.01)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not tierSkip(d) then
			local h = math.clamp((d.Position.Y - minV.Y) / span, 0, 1)
			if vis.Gradient == "Rainbow" then
				local hue = (0.98 - h * 0.78) % 1 -- 위쪽은 빨강/주황, 아래쪽은 파랑/보라
				d.Color = Color3.fromHSV(hue, 0.72, 1)
				d:SetAttribute("TierHue", hue)
			elseif vis.Gradient == "Galaxy" then
				d.Color = d.Color:Lerp(GALAXY_LO:Lerp(GALAXY_HI, h), vis.TintAlpha or 0.85)
			elseif vis.Tint then
				d.Color = d.Color:Lerp(vis.Tint, vis.TintAlpha or 0.7)
			end
			-- 네온(빛나는 장식), 유리, 이미 반투명한 파트(젤리 몸 등)는 재질/투명도를 그대로 둬요
			-- (겹친 반투명 파트를 유리로 바꾸면 서로 안 보이게 돼요)
			local keepLook = d.Material == Enum.Material.Neon or d.Material == Enum.Material.Glass or d.Transparency > 0.05
			if vis.Material and not keepLook then
				d.Material = vis.Material
			end
			if vis.Reflectance then
				d.Reflectance = math.max(d.Reflectance, vis.Reflectance)
			end
			if vis.Transparency and not keepLook then
				d.Transparency = vis.Transparency
			end
		end
	end
	if (vis.Specks or 0) > 0 then
		addSpecks(model, vis.Specks)
	end
	if vis.Cycle then
		model:SetAttribute("TierCycle", true)
	end
	local body = model.PrimaryPart
	if not body then
		return
	end
	local glow: Color3 = if vis.Tint and not vis.Gradient then vis.Tint else Config.TierInfo(t).Color
	if (vis.Light or 0) > 0 then
		local light = Instance.new("PointLight")
		light.Name = "TierFx"
		light.Color = glow
		light.Brightness = vis.Light
		light.Range = 4 + t * 1.2
		light.Shadows = false
		light.Parent = body
	end
	if (vis.Particles or 0) > 0 then
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "TierFx"
		pe.Texture = SPARKLE_TEX
		pe.Color = colorSeq(vis.ParticleColors, glow)
		pe.LightEmission = TIER_SPARKLE_EMISSION
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.12 + 0.03 * t),
			NumberSequenceKeypoint.new(1, 0),
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Lifetime = NumberRange.new(0.8, 1.1 + 0.08 * t)
		pe.Rate = vis.Particles
		pe.Shape = Enum.ParticleEmitterShape.Sphere
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		pe.Speed = NumberRange.new(0.8, 1.4 + 0.2 * t)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Rotation = NumberRange.new(0, 360)
		pe.RotSpeed = NumberRange.new(-60 - 15 * t, 60 + 15 * t)
		pe.Drag = 1
		pe.Parent = body
	end
end

----------------------------------------------------------------------
-- 옷 자리 재기 (§8): 펫 피벗 기준 "크기 1" 공간에서 재고, 붙일 때 실제 크기로 바꿔요
----------------------------------------------------------------------

type Probe = {
	model: Model,
	pivot: CFrame,
	k: number, -- 펫 model:GetScale()
	shapes: { Shape },
	head: Shape?,
	body: Shape?,
	lo: Vector3,
	hi: Vector3,
	refW: number, -- 머리(없으면 몸) 가로 폭
}

-- 몸에서 삐죽 나온 부분: 옷 자리를 잴 때 무시해요
local APPENDAGE = {
	"Ear", "Horn", "Antenna", "Tail", "Wing", "Fin", "Fluke", "Feather", "Arm", "Foot", "Leg", "Flipper",
	"Gill", "Spike", "Crest", "Halo", "Tuft", "Mane", "Whisker", "Paw", "Hoof", "Tentacle", "Speck",
}
-- 모자 밑에 깔려도 괜찮은 머리 위 장식 (귀/털)
local SOFT_TOP = { "Ear", "Tuft", "Mane", "Hair", "Fluff", "Bang", "Speck" }
local NOSES = { "Nose", "Snout", "Beak", "Muzzle" }
-- 모자 자리 후보 { 앞(-)/뒤(+) = 머리 깊이 비율, 옆 = 머리 폭 비율 }. 처음 것이 가려지면 다음 자리
-- (마지막 넷은 옆으로 살짝 비스듬히 쓴 모자: 꼭대기에 지느러미/물줄기가 있는 펫)
local HEAD_TRIES = {
	{ -0.12, 0 }, { -0.28, 0 }, { 0.1, 0 }, { -0.42, 0 }, { 0.24, 0 },
	{ -0.12, 0.27 }, { -0.12, -0.27 }, { 0.1, 0.3 }, { 0.1, -0.3 },
}
-- 머리 옷 밑면 반지름 (크기 1 기준). 앞으로 비켜 앉을 때 눈을 덮는지 볼 때 써요
local HEAD_FOOT = { PartyHat = 0.47, FlowerCrown = 0.64, TopHat = 0.58, WizardHat = 0.75, Crown = 0.56 }

local function makeProbe(model: Model): Probe?
	local pivot = model:GetPivot()
	local k = 1
	local okScale, sc = pcall(function()
		return model:GetScale()
	end)
	if okScale and type(sc) == "number" and sc > 0 then
		k = sc
	end
	local inv = pivot:Inverse()
	local shapes: { Shape } = {}
	local head: Shape? = nil
	local body: Shape? = nil
	local lo = V(math.huge, math.huge, math.huge)
	local hi = -lo
	local primary = model.PrimaryPart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and d:GetAttribute("AccId") == nil then
			local s = shapeOf(d, inv, k)
			table.insert(shapes, s)
			lo = lo:Min(s.lo)
			hi = hi:Max(s.hi)
			if d.Name == "Head" then
				local cur = head
				if cur == nil or s.half.X * s.half.Y * s.half.Z > cur.half.X * cur.half.Y * cur.half.Z then
					head = s
				end
			end
			if d == primary then
				body = s
			end
		end
	end
	if #shapes == 0 then
		return nil
	end
	if body == nil then
		for _, s in shapes do
			if s.part.Name == "Body" then
				body = s
				break
			end
		end
	end
	local ref = head or body
	local refW = if ref then ref.hi.X - ref.lo.X else hi.X - lo.X
	return {
		model = model,
		pivot = pivot,
		k = k,
		shapes = shapes,
		head = head,
		body = body,
		lo = lo,
		hi = hi,
		refW = math.max(refW, 0.2),
	}
end

-- 옷 자리 재기에 쓰는 단단한 몸 파트 (눈/입, 삐죽 나온 부분, 작은 장식, 많이 투명한 파트 빼고)
local function solidShapes(pr: Probe, maxTransparency: number, minThin: number?): { Shape }
	local out = {}
	for _, s in pr.shapes do
		local p = s.part
		local mn, mx = dims(s)
		if
			not KEEP_COLOR[p.Name]
			and p.Transparency < maxTransparency
			and not hasName(p.Name, APPENDAGE)
			and mx >= 0.12 * pr.refW
			and mn >= (minThin or 0) * pr.refW
		then
			table.insert(out, s)
		end
	end
	return out
end

-- 머리가 몸 위에 얹힌 펫인지 (보통 꼬마 몸)
local function isStacked(pr: Probe): boolean
	local h, b = pr.head, pr.body
	if not h or not b or h == b then
		return false
	end
	return centerOf(h).Y > centerOf(b).Y + 0.15 * (b.hi.Y - b.lo.Y)
end

-- 머리와 몸이 만나는 높이 (앞에서 봤을 때 가장 쏙 들어간 곳)
local function neckHeight(pr: Probe): number?
	local h, b = pr.head, pr.body
	if not h or not b or not isStacked(pr) then
		return nil
	end
	local hc = centerOf(h)
	local lo = math.max(h.lo.Y, b.lo.Y + 0.35 * (b.hi.Y - b.lo.Y))
	local hi = math.min(b.hi.Y, hc.Y)
	if hi < lo then
		lo, hi = hi, lo
	end
	local pair = { h, b }
	local bestY, bestZ = (lo + hi) * 0.5, -math.huge
	for i = 0, 10 do
		local y = lo + (hi - lo) * i / 10
		local p = hitAt(pair, V(hc.X, y, pr.lo.Z - 5), Vector3.zAxis)
		if p and p.Z > bestZ then
			bestY, bestZ = y, p.Z
		end
	end
	return bestY
end

local function frontZ(list: { Shape }, pr: Probe, x: number, y: number): number?
	local p = hitAt(list, V(x, y, pr.lo.Z - 5), Vector3.zAxis)
	return if p then p.Z else nil
end

local function backZ(list: { Shape }, pr: Probe, x: number, y: number): number?
	local p = hitAt(list, V(x, y, pr.hi.Z + 5), -Vector3.zAxis)
	return if p then p.Z else nil
end

-- 위에서 아래로 쏜 광선이 닿는 높이와 모양
local function topY(list: { Shape }, pr: Probe, x: number, z: number): (number?, Shape?)
	local p, s = hitAt(list, V(x, pr.hi.Y + 5, z), -Vector3.yAxis)
	return if p then p.Y else nil, s
end

-- 머리 위: 가장 위의 큰 몸 파트 (헬멧이면 헬멧 위). 뿔/별 같은 장식에 가리면 앞/뒤로 비켜요
local function headAnchor(pr: Probe, fit: AccFit, foot: number): (CFrame, BasePart)
	local ref = pr.head or pr.body
	local cands = solidShapes(pr, 0.6, 0.3)
	local eyes: { Shape } = {}
	for _, o in pr.shapes do
		if o.part.Name == "Eye" or o.part.Name == "Shine" then
			table.insert(eyes, o)
		end
	end
	if #cands == 0 then
		cands = pr.shapes
	end
	local c = if ref then centerOf(ref) else (pr.lo + pr.hi) * 0.5
	local depth = if ref then ref.hi.Z - ref.lo.Z else pr.hi.Z - pr.lo.Z
	local cx = c.X
	if not pr.head then
		-- 머리 파트가 없는 펫 (구름/슬라임): 가운데 근처에서 가장 높은 곳 (꼭대기 뭉치 위)
		local bestY = -math.huge
		for _, dx in { 0, -0.12, 0.12, -0.24, 0.24 } do
			local yy = topY(cands, pr, c.X + dx * pr.refW, c.Z - 0.12 * depth)
			if yy and yy > bestY + 0.05 then
				bestY, cx = yy, c.X + dx * pr.refW
			end
		end
	end
	local bestCf: CFrame? = nil
	local bestPart: BasePart? = nil
	local bestS, bestScore = 1, math.huge
	for i, try in HEAD_TRIES do
		local f = try[1]
		local x, z = cx + try[2] * pr.refW, c.Z + f * depth
		local y, hit = topY(cands, pr, x, z)
		if y and hit then
			-- 크기: 앉은 파트 폭 (헬멧이면 헬멧), 머리 없는 펫은 몸 폭보다 작아지지 않게
			local w = hit.hi.X - hit.lo.X
			if not pr.head then
				w = math.max(w, pr.refW)
			end
			local s = math.clamp(w / 2.1, 0.6, 2)
			local r = 0.45 * s
			local function rim(dx: number, dz: number): number
				local yy = topY(cands, pr, x + dx, z + dz)
				return if yy then math.min(yy, y) else y - r
			end
			local yF, yB, yL, yR = rim(0, -r), rim(0, r), rim(-r, 0), rim(r, 0)
			local drop = y - (yF + yB + yL + yR) / 4
			local sink = math.clamp(drop * 0.6, 0, 0.25 * s)
			local pitch = math.clamp(math.atan2(yF - yB, 2 * r) * 0.6, -0.4, 0.4)
			local roll = math.clamp(math.atan2(yR - yL, 2 * r) * 0.6, -0.3, 0.3)
			local cf = CFrame.new(x, y - sink, z) * CFrame.Angles(pitch, 0, roll)
			-- 모자 가운데 기둥 자리에 걸리는 장식이 있으면 점수 (부피)
			local core = 0.27 * s
			local zlo, zhi = V(x - core, y + 0.1 * s, z - core), V(x + core, y + 0.95 * s, z + core)
			local score = 0
			for _, o in pr.shapes do
				local _, mx = dims(o)
				if o ~= hit and not KEEP_COLOR[o.part.Name] and not hasName(o.part.Name, SOFT_TOP) and mx >= 0.1 * pr.refW then
					score += overlapVol(o.lo, o.hi, zlo, zhi)
				end
			end
			-- 밑면 테두리 점들이 눈(조금 넓힌 타원체)에 들어가면 큰 벌점
			local R = foot * s
			local pad = V(0.04, 0.04, 0.04)
			for _, e in eyes do
				local hit2 = false
				for k = 0, 11 do
					local a = k * math.pi / 6
					for _, rr in { R, R * 0.6 } do
						for _, hy in { -0.12 * s, 0.1 * s, 0.3 * s, 0.5 * s } do
							local wp = cf * V(math.sin(a) * rr, hy, -math.cos(a) * rr)
							local q = e.cf:PointToObjectSpace(wp) / (e.half + pad)
							if q:Dot(q) < 1 then
								hit2 = true
							end
						end
					end
				end
				if hit2 then
					score += 0.05
				end
			end
			if score < 1e-4 then
				fit.s = s
				return cf, hit.part
			end
			score += (i - 1) * 0.004 * s ^ 3
			if score < bestScore then
				bestCf, bestPart, bestS, bestScore = cf, hit.part, s, score
			end
		end
	end
	if bestCf and bestPart then
		fit.s = bestS
		return bestCf, bestPart
	end
	fit.s = math.clamp(pr.refW / 2.1, 0.6, 2)
	local any = if ref then ref.part else pr.shapes[1].part
	return CFrame.new(c.X, pr.hi.Y, c.Z), any
end

-- 얼굴: 두 눈 앞 (눈 사이 간격으로 크기), 콧수염 자리는 코/부리/주둥이 바로 아래
local function faceAnchor(pr: Probe, fit: AccFit): (CFrame, BasePart)
	local ref = pr.head or pr.body
	local onPart = if ref then ref.part else pr.shapes[1].part
	local solid = solidShapes(pr, 0.4)
	local eyes: { Shape } = {}
	for _, s in pr.shapes do
		if s.part.Name == "Eye" then
			table.insert(eyes, s)
		end
	end
	local cx, ey, fz, s
	if #eyes > 0 then
		local L, R = eyes[1], eyes[1]
		for _, e in eyes do
			if e.cf.Position.X < L.cf.Position.X then
				L = e
			end
			if e.cf.Position.X > R.cf.Position.X then
				R = e
			end
		end
		local pl, pq = L.cf.Position, R.cf.Position
		cx, ey = (pl.X + pq.X) * 0.5, (pl.Y + pq.Y) * 0.5
		local spacing = math.abs(pq.X - pl.X)
		local eh = math.max(L.hi.Y - L.lo.Y, R.hi.Y - R.lo.Y)
		s = math.clamp(math.max(spacing / 0.8, eh / 0.5), 0.6, 2)
		fz = math.min(L.lo.Z, R.lo.Z)
	else
		local c = if ref then centerOf(ref) else (pr.lo + pr.hi) * 0.5
		cx = c.X
		ey = if ref then ref.lo.Y + 0.55 * (ref.hi.Y - ref.lo.Y) else pr.lo.Y + 0.65 * (pr.hi.Y - pr.lo.Y)
		s = math.clamp(pr.refW / 2.1, 0.6, 2)
		fz = math.huge
	end
	local hz = frontZ(solid, pr, cx, ey)
	if hz then
		fz = math.min(fz, hz)
	end
	if fz == math.huge then
		fz = pr.lo.Z
	end
	local pos = V(cx, ey, fz - 0.03 * s)
	-- 콧수염 자리
	local nose: Shape? = nil
	for _, nm in NOSES do
		for _, sh in pr.shapes do
			local p = sh.cf.Position
			if sh.part.Name == nm and p.Y < ey and math.abs(p.X - cx) < 0.3 * s then
				local cur = nose
				if cur == nil or p.Z < cur.cf.Position.Z then
					nose = sh
				end
			end
		end
		if nose then
			break
		end
	end
	local my = if nose then nose.lo.Y - 0.06 * s else ey - 0.32 * s
	if ref then
		my = math.max(my, ref.lo.Y + 0.12 * (ref.hi.Y - ref.lo.Y))
	end
	local mz = frontZ(solid, pr, cx, my) or fz
	fit.mouth = V(0, my - ey, mz - 0.02 * s - pos.Z)
	fit.s = s
	return CFrame.new(pos), onPart
end

-- 목: 머리와 몸 사이 앞 (머리 없는 펫은 입 아래). 목 둘레도 재요 (목도리/메달)
local function neckAnchor(pr: Probe, fit: AccFit): (CFrame, BasePart)
	local ref = pr.head or pr.body
	local onPart = if pr.body then pr.body.part elseif ref then ref.part else pr.shapes[1].part
	local solid = solidShapes(pr, 0.4)
	local c = if ref then centerOf(ref) else (pr.lo + pr.hi) * 0.5
	local cx = c.X
	local u = math.clamp(pr.refW / 2.1, 0.6, 2)
	local H = pr.hi.Y - pr.lo.Y
	local y = neckHeight(pr)
	local headless = y == nil
	local mouthLo = math.huge
	if not y then
		-- 머리가 따로 없는 펫: 입 아래 → 눈 아래 → 40 % 높이 (나비넥타이 윗변이 입에 안 닿게)
		local eyeSum, eyeN = 0, 0
		for _, sh in pr.shapes do
			if (sh.part.Name == "Mouth" or sh.part.Name == "Tongue") and math.abs(sh.cf.Position.X - cx) < 0.5 * pr.refW then
				mouthLo = math.min(mouthLo, sh.lo.Y)
			elseif sh.part.Name == "Eye" then
				eyeSum += sh.cf.Position.Y
				eyeN += 1
			end
		end
		if mouthLo < math.huge then
			y = mouthLo - (0.06 + 0.2 * u)
		elseif eyeN > 0 then
			y = eyeSum / eyeN - 0.55 * u
		else
			y = pr.lo.Y + 0.4 * H
		end
	end
	local ny: number = math.max(y or 0, pr.lo.Y + 0.1 * H)
	-- 그 높이 앞쪽에 몸이 없으면 (해파리 갓 바로 아래 등) 위로 훑어서 가장 앞으로 나온 높이에 걸어요
	-- (입이 있으면 넥타이 윗변이 입 아래에 머무는 데까지만)
	local zF0 = frontZ(solid, pr, cx, ny)
	if not zF0 then
		local capY = if mouthLo < math.huge then mouthLo - 0.02 - 0.2 * 0.6 else ny + 0.35 * u
		local bestY, bestZ = ny, math.huge
		local yy = ny + 0.03 * u
		while yy <= capY and yy < pr.hi.Y do
			local z = frontZ(solid, pr, cx, yy)
			if z and z < bestZ - 0.02 then
				bestY, bestZ = yy, z
			end
			yy += 0.03 * u
		end
		if bestZ < math.huge then
			ny, zF0 = bestY, bestZ
		end
	end
	local zF = zF0 or pr.lo.Z
	local zB = backZ(solid, pr, cx, ny) or pr.hi.Z
	local zc = (zF + zB) * 0.5
	local pL = hitAt(solid, V(pr.lo.X - 5, ny, zc), Vector3.xAxis)
	local pR = hitAt(solid, V(pr.hi.X + 5, ny, zc), -Vector3.xAxis)
	local xL = if pL then pL.X else pr.lo.X
	local xR = if pR then pR.X else pr.hi.X
	local rx, rz = (xR - xL) * 0.5, (zB - zF) * 0.5
	-- 크기: 목 둘레 기준 (꼬마 몸 목 = 0.72). 머리 없는 펫은 둘레가 몸 전체라 몸 폭 기준을 넘지 않게
	local s = math.clamp(rx / 0.72, 0.6, 2)
	if headless then
		s = math.min(s, u)
		if mouthLo < math.huge then
			-- 넥타이 윗변 (0.2 s) 이 입을 덮지 않게
			s = math.clamp(math.min(s, (mouthLo - 0.02 - ny) / 0.2), 0.6, 2)
		end
	end
	local pos = V(cx, ny, zF - 0.02 * s)
	fit.s = s
	fit.rx = rx + 0.03 * s
	fit.rz = rz + 0.03 * s
	fit.ring = V((xL + xR) * 0.5 - cx, 0, zc - pos.Z)
	-- 가슴 (메달 원판): 몸 위에 머물고, 몸이 뒤로 쑥 들어가면 목 앞 바로 아래에 매달려요
	local cy = ny - (if headless then 0.32 else 0.42) * s
	local b = pr.body
	if b then
		cy = math.max(cy, b.lo.Y + 0.2 * (b.hi.Y - b.lo.Y))
	end
	local cz = frontZ(solid, pr, cx, cy) or zF
	cz = math.min(cz, zF + 0.12 * s)
	fit.chest = V(0, cy - ny, cz - pos.Z)
	fit.drop = math.max(ny - pr.lo.Y, 0.1)
	return CFrame.new(pos), onPart
end

-- 등: 몸 뒷면 60 % 높이. 길쭉하게 누운 펫(고래 등)은 등 위쪽으로 기울여요
local function backAnchor(pr: Probe, fit: AccFit): (CFrame, BasePart)
	local body = pr.body
	local onPart = if body then body.part else pr.shapes[1].part
	local blo = if body then body.lo else pr.lo
	local bhi = if body then body.hi else pr.hi
	local bh, bd = bhi.Y - blo.Y, bhi.Z - blo.Z
	local c = (blo + bhi) * 0.5
	local solid = solidShapes(pr, 0.6)
	local stacked = isStacked(pr)
	local e = 0
	if not stacked and bd > 1.25 * bh then
		e = math.clamp((bd / bh - 1.1) * 1.4, 0, 0.95)
	end
	local y = blo.Y + 0.6 * bh
	local dir = V(0, -math.sin(e), -math.cos(e))
	local far = 5 + (pr.hi - pr.lo).Magnitude
	local aim = V(c.X, y, c.Z)
	local P = hitAt(solid, aim - dir * far, dir) or V(c.X, y, bhi.Z)
	local cf = CFrame.new(P) * CFrame.Angles(-e, 0, 0)
	local s = math.clamp((bhi.X - blo.X) / 1.8, 0.6, 2)
	fit.s = s
	if e > 0 then
		fit.neck = V(0, 0.45 * s, -0.08 * s)
		fit.drop = math.clamp(bd * 0.45, 0.4, 2.2 * s)
	else
		local ny = neckHeight(pr) or math.min(pr.hi.Y - 0.1 * s, P.Y + 0.45 * s)
		local nz = backZ(solid, pr, c.X, ny) or P.Z
		local nl = cf:PointToObjectSpace(V(c.X, ny, nz))
		fit.neck = V(0, nl.Y, nl.Z)
		fit.drop = math.clamp(P.Y - 0.15, 0.3, 2.4 * s)
	end
	return cf, onPart
end

-- 펫 빌더가 Body 에 붙인 Attachment "Acc<slot>" (있으면 그 자리 그대로)
local function findAccAttachment(model: Model, slot: string): Attachment?
	local att = model:FindFirstChild("Acc" .. slot, true)
	if att and att:IsA("Attachment") and att.Parent and att.Parent:IsA("BasePart") then
		return att
	end
	return nil
end

local function accDef(accId: string): any
	return (Config.Accessories :: any)[accId]
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 붙어 있는 옷 파트 (AccId 속성) 를 모두 떼요
function PetModels.RemoveAccessory(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("AccId") ~= nil then
			d:Destroy()
		end
	end
	model:SetAttribute("AccId", nil)
end

-- 펫 모델에 옷을 입혀요. 옷 파트는 펫 모델의 바로 아래 자식 (그래서 model:ScaleTo 가 같이 키워요),
-- 앉은 파트(머리/헬멧/몸)에 WeldConstraint, Massless, 충돌/터치/쿼리 끔, 속성 AccId.
-- 이미 키운(ScaleTo) 모델이나 옮긴 모델에도 맞게 붙어요. 성공하면 true.
function PetModels.AttachAccessory(model: Model, accId: string): boolean
	local def = accDef(accId)
	local fn = ACC_BUILDERS[accId]
	if not def or not fn then
		warn("[PetModels] 알 수 없는 옷: " .. tostring(accId))
		return false
	end
	PetModels.RemoveAccessory(model)
	local pr = makeProbe(model)
	if not pr then
		return false
	end
	local slot: string = def.Slot
	local fit = defaultFit(slot)
	local anchor: CFrame, sitOn: BasePart
	if slot == "Head" then
		anchor, sitOn = headAnchor(pr, fit, HEAD_FOOT[accId] or 0.55)
	elseif slot == "Face" then
		anchor, sitOn = faceAnchor(pr, fit)
	elseif slot == "Neck" then
		anchor, sitOn = neckAnchor(pr, fit)
	else
		anchor, sitOn = backAnchor(pr, fit)
	end
	local att = findAccAttachment(model, slot)
	if att then
		local rel = pr.pivot:Inverse() * att.WorldCFrame
		anchor = rel.Rotation + rel.Position / pr.k
		sitOn = att.Parent :: BasePart
	end
	-- 유리 헬멧 안이면 반투명 파트도 보이게
	for _, sh in pr.shapes do
		if sh.part.Material == Enum.Material.Glass and sh.part.Transparency > 0.05 and insideShape(sh, anchor.Position) then
			fit.opaque = true
		end
	end
	local b = newBuilder(accId)
	fn(b, fit)
	for _, p in b.parts do
		local u = anchor * p.CFrame
		p.Size = p.Size * pr.k
		p.CFrame = pr.pivot * (u.Rotation + u.Position * pr.k)
		if p.Name == "Body" or p.Name == "Head" then
			p.Name = "Acc" .. p.Name
		end
		if fit.opaque and p.Transparency < 0.95 then
			p.Transparency = 0
		end
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p:SetAttribute("AccId", accId)
		local w = Instance.new("WeldConstraint")
		w.Part0 = sitOn
		w.Part1 = p
		w.Parent = p
		p.Parent = model
	end
	b.model:Destroy()
	model:SetAttribute("AccId", accId)
	return true
end

-- tier: 1 기본 ~ 7 갤럭시 (생략하면 1). accId: 입힐 옷 (생략 가능)
function PetModels.BuildPet(petId: string, tier: number?, accId: string?): Model
	local fn = PET_BUILDERS[petId]
	if not fn then
		warn("[PetModels] 알 수 없는 펫: " .. tostring(petId))
		fn = PET_BUILDERS.Chick
	end
	local b = newBuilder(petId)
	fn(b)
	local model = finish(b)
	applyTier(model, tier or 1)
	if accId and accId ~= "" then
		local ok, err = pcall(PetModels.AttachAccessory, model, accId)
		if not ok then
			warn("[PetModels] 옷 입히기 실패 (" .. tostring(accId) .. "): " .. tostring(err))
		end
	end
	return model
end

function PetModels.HasPet(petId: string): boolean
	return PET_BUILDERS[petId] ~= nil
end

-- 알 빌더 찾기: 손으로 만든 빌더(EGG_BUILDERS) → Config.Eggs[id].Look 무늬 알 → 없으면 nil
local function eggBuilder(eggId: string): ((Builder) -> ())?
	local fn = EGG_BUILDERS[eggId]
	if fn then
		return fn
	end
	local def = (Config.Eggs :: any)[eggId]
	local look = if type(def) == "table" then def.Look else nil
	local fromLook = Kit.eggFromLook
	if type(look) == "table" and fromLook then
		return function(b: Builder)
			fromLook(b, look)
		end
	end
	return nil
end

function PetModels.HasEgg(eggId: string): boolean
	return eggBuilder(eggId) ~= nil
end

function PetModels.HasAccessory(accId: string): boolean
	return ACC_BUILDERS[accId] ~= nil
end

function PetModels.BuildEgg(eggId: string): Model
	local fn: (Builder) -> () = EGG_BUILDERS.Basic
	local found = eggBuilder(eggId)
	if found then
		fn = found
	else
		warn("[PetModels] 알 수 없는 알: " .. tostring(eggId))
	end
	local b = newBuilder(eggId)
	local ok, err = pcall(function(): any
		fn(b)
		return nil
	end)
	if not ok then
		-- 빌더 오류(잘못된 Look 등)면 기본 알로 대신 보여줘요
		warn("[PetModels] 알 만들기 오류 (" .. tostring(eggId) .. "): " .. tostring(err))
		b.model:Destroy()
		b = newBuilder(eggId)
		EGG_BUILDERS.Basic(b)
	end
	return finish(b)
end

-- Look 표 하나로 바로 알 만들기 (Config 없이 미리보기/시험용). Look 형식은 EggsPattern.luau 맨 위 참고
function PetModels.BuildEggLook(look: any, name: string?): Model
	local b = newBuilder(name or "LookEgg")
	local fromLook = Kit.eggFromLook
	if fromLook then
		fromLook(b, look)
	else
		EGG_BUILDERS.Basic(b)
	end
	return finish(b)
end

-- 무늬 알이 쓸 수 있는 Pattern 이름 목록
function PetModels.EggPatterns(): { string }
	return table.clone(Kit.EGG_PATTERNS)
end

-- 옷 하나만 (상점 미리보기용). PrimaryPart = 첫 파트, 피벗 = 바닥 가운데, 앞 = -Z (펫이 입었을 때와 같은 방향)
function PetModels.BuildAccessory(accId: string): Model
	local def = accDef(accId)
	local fn = ACC_BUILDERS[accId]
	local b = newBuilder(accId)
	if not fn then
		warn("[PetModels] 알 수 없는 옷: " .. tostring(accId))
		local p = ell(b, "Unknown", V(0.6, 0.6, 0.6), CFrame.new(0, 0.3, 0), RGB(200, 200, 210))
		b.model.PrimaryPart = p
		return b.model
	end
	local slot: string = if def then def.Slot else "Head"
	fn(b, defaultFit(slot))
	local main = b.parts[1]
	b.model.PrimaryPart = main
	for _, p in b.parts do
		p:SetAttribute("AccId", accId)
		p.Massless = p ~= main
		if p ~= main then
			local w = Instance.new("WeldConstraint")
			w.Part0 = main
			w.Part1 = p
			w.Parent = p
		end
	end
	local minV, maxV = bounds(b.model)
	b.model.WorldPivot = CFrame.new((minV.X + maxV.X) * 0.5, minV.Y, (minV.Z + maxV.Z) * 0.5)
	b.model:SetAttribute("AccId", accId)
	b.model:SetAttribute("Slot", slot)
	return b.model
end

-- 레인보우 색 돌리기 (클라이언트용, 서버 루프 없음): TierHue 속성이 있는 파트만 색상환을 phase 만큼 돌려요.
-- 예) 가까운 TierCycle 펫마다 0.1초에 한 번 CycleTierColors(model, os.clock() * 0.08)
function PetModels.CycleTierColors(model: Model, phase: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local h = d:GetAttribute("TierHue")
			if type(h) == "number" then
				d.Color = Color3.fromHSV((h + phase) % 1, 0.72, 1)
			end
		end
	end
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
	local level = math.clamp(info.Order - 3, 1, 3) -- Epic 1, Legendary 2, Mythic 3 (비밀도 3)
	-- ★v6 시크릿/천상/이터널 (Special): 비밀보다 밝지 않게. 빛은 한 단계 낮게, 반짝이는 단계 색으로 크고 느리게 떠올라요 (이터널만 무지개)
	local special = info.Special == true

	local light = Instance.new("PointLight")
	light.Name = "RarityFx"
	light.Color = col
	light.Brightness = if special then 1.3 else 0.3 + 0.5 * level
	light.Range = if special then 10 else 4 + 3 * level
	light.Shadows = false
	light.Parent = body

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "RarityFx"
	pe.Texture = SPARKLE_TEX
	if special then
		pe.Color = if info.Rainbow then colorSeq(RAINBOW, col) else ColorSequence.new(col, WHITE)
	elseif level >= 3 then
		pe.Color = colorSeq(RAINBOW, col)
	else
		pe.Color = ColorSequence.new(col, WHITE)
	end
	pe.LightEmission = if special then 0.7 else 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if special then 0.42 else 0.12 + 0.08 * level),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = if special then NumberRange.new(1.4, 2.2) else NumberRange.new(0.8, 1.5)
	pe.Rate = if special then 6 elseif level == 1 then 3 elseif level == 2 then 7 else 12
	-- 몸 표면에서 바깥쪽으로 뿌려야 몸속에 가려지지 않음
	pe.Shape = Enum.ParticleEmitterShape.Sphere
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	pe.Speed = if special then NumberRange.new(0.5, 1.2) else NumberRange.new(1, 2.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Drag = 1
	pe.Parent = body
end

-- UI 용 3D 미리보기. kind = "Pet" | "Egg" | "Accessory". silhouette = true 면 새까만 그림자 (도감 미발견)
-- 펫은 tier (등급 색) 와 accId (입은 옷) 도 보여줘요. 등 옷은 바깥쪽이 보이게 돌려요.
function PetModels.CreateViewport(
	kind: string,
	id: string,
	parent: Instance,
	silhouette: boolean?,
	tier: number?,
	accId: string?
): (ViewportFrame, Model)
	local vf = Instance.new("ViewportFrame")
	vf.Name = "PetViewport"
	vf.Size = UDim2.fromScale(1, 1)
	vf.AnchorPoint = Vector2.new(0.5, 0.5)
	vf.Position = UDim2.fromScale(0.5, 0.5)
	vf.BackgroundTransparency = 1
	vf.Ambient = RGB(175, 175, 185)
	vf.LightColor = RGB(255, 250, 245)
	vf.LightDirection = V(-0.4, -1, 0.8)

	local model: Model
	if kind == "Egg" then
		model = PetModels.BuildEgg(id)
	elseif kind == "Accessory" then
		model = PetModels.BuildAccessory(id)
		local def = accDef(id)
		if def and def.Slot == "Back" then
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.pi, 0))
		end
	else
		model = PetModels.BuildPet(id, tier, accId)
	end

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
