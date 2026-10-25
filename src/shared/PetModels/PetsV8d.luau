-- ★v8 15 불꽃 화산 / 16 황금 왕국 펫 (PetModels/init.luau 가 불러서 등록)
-- 규칙은 init.luau 와 같아요: 앞쪽 = -Z, 바닥 = y 0, 몸 = Body, 머리 = Head.
return function(Kit, PET_BUILDERS, _EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.chibi, Kit.SIDES
	local addPart, darker, alongY, tri, frameUp, muzzle, smallNose, pointyEars, roundEars = Kit.addPart, Kit.darker, Kit.alongY, Kit.tri, Kit.frameUp, Kit.muzzle, Kit.smallNose, Kit.pointyEars, Kit.roundEars
	local WHITE, MOUTH = Kit.WHITE, Kit.MOUTH
	local NEON = Enum.Material.Neon
	local GLASS = Enum.Material.Glass
	local METAL = Enum.Material.Metal
	local H = require(script.Parent.V8Kit).make(Kit)
	local foxBase = H.foxBase

	local GOLD = RGB(255, 205, 70)
	local FIRE1 = RGB(255, 200, 60)
	local FIRE2 = RGB(255, 110, 40)

	-- 불꽃 (위로 뾰족한 공 3겹: 바깥 주황, 안 노랑 네온). pos = 불꽃 바닥
	local function flame(b, pos, k, neon)
		local s = k or 1
		ell(b, "Flame", V(0.5, 0.9, 0.5) * s, CFrame.new(pos + V(0, 0.4 * s, 0)), FIRE2, if neon then NEON else nil)
		ell(b, "Flame", V(0.32, 0.6, 0.32) * s, CFrame.new(pos + V(0, 0.36 * s, -0.08 * s)), FIRE1, NEON)
		ell(b, "Flame", V(0.22, 0.4, 0.22) * s, CFrame.new(pos + V(0.12 * s, 0.75 * s, 0.05 * s)), FIRE2)
	end

	-- 용암 금 (몸 표면의 빛나는 갈라진 줄)
	local function cracks(b, C, S, list, color)
		for i, d in list do
			H.patch(b, "LavaCrack", C, S, d[1], d[2], 0.07, color or FIRE2, d[3] or 0, if i <= 3 then NEON else nil)
		end
	end

	-- 동전 (금 원판 + 가운데 홈)
	local function coin(b, pos, normal, r)
		local cf = H.along(pos, normal) * CFrame.Angles(0, -math.pi / 2, 0)
		addPart(b, "Coin", "Cyl", V(0.1, r * 2, r * 2), cf, GOLD, METAL)
		addPart(b, "Coin", "Cyl", V(0.12, r * 1.2, r * 1.2), cf, RGB(255, 225, 120), METAL)
	end

	----------------------------------------------------------------------
	-- 15 불꽃 화산
	----------------------------------------------------------------------

	-- 용암 슬라임: 주황 젤리 몸, 머리 위 작은 불꽃, 바닥에 퍼진 용암 웅덩이
	PET_BUILDERS.MagmaSlime = function(b)
		local O = RGB(255, 120, 50)
		local B = V(0, 0.85, 0)
		local BS = V(1.05, 0.85, 1.0)
		ell(b, "Body", BS * 2, CFrame.new(B), O, GLASS, 0.05)
		ell(b, "Puddle", V(2.6, 0.2, 2.4), CFrame.new(0, 0.1, 0.05), RGB(255, 90, 40))
		ell(b, "Core", V(0.9, 0.7, 0.9), CFrame.new(B + V(0, -0.1, 0.1)), FIRE1, NEON, 0.3)
		local c = { b = b, B = B, BS = BS, H = B, HS = BS, FC = B, FS = BS }
		for _, sx in SIDES do
			Kit.addEye(b, B, BS, sx * 0.34, 0.15, V(0.3, 0.42, 0.14), 0.02)
			local p, n = front(B, BS, sx * 0.62, -0.15)
			ell(b, "Blush", V(0.28, 0.15, 0.05), facing(p + n * 0.02, n), Kit.BLUSH, nil, 0.1)
		end
		local mp, mn = front(B, BS, 0, -0.2)
		ell(b, "Mouth", V(0.2, 0.1, 0.06), facing(mp + mn * 0.02, mn), MOUTH)
		flame(b, H.top(c, 0.92), 0.8)
		for _, o in { V(0.75, 0.15, 0.7), V(-0.85, 0.15, -0.4) } do
			ell(b, "Bubble", V(0.24, 0.24, 0.24), CFrame.new(o), FIRE1)
		end
	end

	-- 불도롱뇽: 빨간 도롱뇽, 노란 점, 등을 따라 작은 불꽃, 긴 꼬리
	PET_BUILDERS.Salamander = function(b)
		local R = RGB(255, 90, 70)
		local c = H.quad(b, { body = R, belly = RGB(255, 200, 150), BS = V(0.7, 0.5, 1.15), legH = 0.25, legW = 0.34, HS = V(0.78, 0.6, 0.72), eyeX = 0.36, eyeY = 0.18, eyeSize = V(0.3, 0.4, 0.14) })
		local mp, mn = front(c.H, c.HS, 0, -0.22)
		ell(b, "Mouth", V(0.34, 0.07, 0.05), facing(mp, mn), MOUTH)
		for _, d in { V(0.5, 0.8, -0.3), V(-0.55, 0.75, 0.2), V(0.4, 0.8, 0.6), V(-0.3, 0.6, -0.7) } do
			H.patch(b, "Spot", c.B, c.BS, d, 0.26, 0.26, FIRE1)
		end
		for i, z in { -0.4, 0.2, 0.8 } do
			local p = surf(c.B, c.BS, V(0, 1, z))
			ell(b, "Flame", V(0.22, 0.42, 0.22), CFrame.new(p + V(0, 0.14, 0)), if i == 2 then FIRE1 else FIRE2, if i == 2 then NEON else nil)
		end
		local tp = surf(c.B, c.BS, V(0, 0, 1))
		local p1 = tp + V(0.3, 0, 0.6)
		local p2 = p1 + V(0.35, 0.1, 0.45)
		H.link(b, "Tail", tp, p1, 0.4, R)
		H.link(b, "Tail", p1, p2, 0.28, R)
		flame(b, p2 + V(0.05, -0.05, 0.1), 0.55, true)
	end

	-- 불씨 강아지: 숯빛 강아지, 귀 끝과 꼬리 끝이 불씨처럼 빛나요
	PET_BUILDERS.EmberPup = function(b)
		local K = RGB(90, 80, 85)
		local c = chibi(b, { body = K, belly = RGB(140, 125, 125), feet = RGB(60, 55, 60), eyeY = 0.06, noMouth = true })
		muzzle(c, V(0.55, 0.38, 0.4), RGB(150, 135, 135), RGB(40, 30, 30), -0.3)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx, 0.35, 0))
			ell(b, "Ear", V(0.32, 0.75, 0.22), CFrame.new(p + V(sx * 0.06, -0.25, 0)) * CFrame.Angles(0, 0, sx * 0.2), K)
			ell(b, "EarEmber", V(0.26, 0.26, 0.2), CFrame.new(p + V(sx * 0.12, -0.6, 0)), FIRE2, NEON)
		end
		cracks(b, c.B, c.BS, { { V(0.6, 0.3, 0.6), 0.4, 0.5 }, { V(-0.6, 0.1, 0.6), 0.36, -0.4 } })
		local tip = H.tail(b, c, K, { w = 0.3, d1 = V(0, 0.6, 1), d2 = V(0, 1, 0.3) })
		flame(b, tip - V(0, 0.15, 0), 0.6)
	end

	-- 불꽃 여우: 주황 여우, 꼬리가 불꽃, 이마 불꽃 무늬
	PET_BUILDERS.FlameFox = function(b)
		local O = RGB(255, 110, 40)
		local c = foxBase(b, O, RGB(255, 235, 200), { feet = RGB(120, 50, 30), arms = RGB(120, 50, 30), earIn = FIRE1 })
		local mp, mn = front(c.H, c.HS, 0, -0.42)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), MOUTH)
		local fp, fn = front(c.H, c.HS, 0, 0.55)
		H.stick(b, "Mark", fp, fn, 0.22, 0.36, 1, FIRE1, 0, NEON)
		local tp = surf(c.B, c.BS, V(0, -0.2, 1))
		local t1 = tp + V(0.2, 0.35, 0.45)
		ell(b, "Tail", V(0.6, 0.6, 1.0), CFrame.lookAt(t1, t1 + V(0.3, 0.8, 0.6)), O)
		flame(b, t1 + V(0.1, 0.2, 0.15), 1.1, true)
	end

	-- 용암 거북: 짙은 바위 등껍질에 빛나는 용암 줄, 등 꼭대기 작은 화산
	PET_BUILDERS.LavaTurtle = function(b)
		local SK = RGB(150, 110, 100)
		local c = H.quad(b, { body = SK, BS = V(0.85, 0.55, 1.0), legH = 0.35, legW = 0.42, HS = V(0.62, 0.58, 0.6), eyeX = 0.26, eyeSize = V(0.24, 0.34, 0.12) })
		H.snout(b, c, SK, V(0.5, 0.3, 0.3), -0.25)
		local SC = c.B + V(0, 0.3, 0.05)
		local SS = V(1.1, 0.75, 1.2)
		ell(b, "Shell", SS * 2, CFrame.new(SC), RGB(80, 65, 70))
		cracks(b, SC, SS, { { V(0.6, 0.6, 0.3), 0.8, 0.8 }, { V(-0.6, 0.6, -0.3), 0.8, -0.6 }, { V(0, 0.5, 0.9), 0.7, 0.2 }, { V(0.3, 0.5, -0.8), 0.6, -0.3 } })
		-- 꼭대기 화산 (원뿔 대신 쐐기 4장 + 분화구 불)
		local top = SC + V(0, SS.Y - 0.05, 0)
		for i = 0, 3 do
			tri(b, "Volcano", CFrame.new(top) * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, -0.18) * CFrame.Angles(-0.35, 0, 0), 0.75, 0.6, 0.14, RGB(110, 90, 90))
		end
		ell(b, "Lava", V(0.3, 0.2, 0.3), CFrame.new(top + V(0, 0.55, 0)), FIRE2, NEON)
		local tp = surf(c.B, c.BS, V(0, -0.2, 1))
		ell(b, "Tail", V(0.24, 0.2, 0.42), CFrame.new(tp + V(0, 0, 0.12)), SK)
	end

	-- 마그마 코뿔소: 회색 바위 코뿔소, 큰 코뿔 끝이 빛나요, 몸의 용암 금
	PET_BUILDERS.MagmaRhino = function(b)
		local G = RGB(120, 100, 105)
		local c = H.quad(b, { body = G, belly = RGB(160, 140, 140), BS = V(0.95, 0.75, 1.2), HS = V(0.8, 0.72, 0.8), eyeX = 0.38, eyeY = 0.15, eyeSize = V(0.26, 0.36, 0.13) })
		local cf = H.snout(b, c, G, V(0.8, 0.55, 0.55), -0.25)
		ell(b, "Horn", V(0.32, 0.8, 0.32), cf * CFrame.new(0, 0.42, -0.1) * CFrame.Angles(-0.4, 0, 0), RGB(80, 70, 75))
		ell(b, "HornTip", V(0.2, 0.32, 0.2), cf * CFrame.new(0, 0.82, -0.26) * CFrame.Angles(-0.4, 0, 0), FIRE2, NEON)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.6, 0.8, 0.2))
			ell(b, "Ear", V(0.2, 0.4, 0.16), CFrame.new(p + V(0, 0.1, 0)) * CFrame.Angles(0, 0, -sx * 0.4), G)
		end
		cracks(b, c.B, c.BS, { { V(0.7, 0.6, 0.2), 0.9, 0.6 }, { V(-0.7, 0.5, -0.2), 0.8, -0.5 }, { V(0, 0.9, 0.5), 0.7, 1.4 }, { V(0.5, 0.7, -0.6), 0.5, 0.2 } })
		local p = surf(c.B, c.BS, V(0, 1, -0.2))
		flame(b, p - V(0, 0.1, 0), 0.6)
		local tp = surf(c.B, c.BS, V(0, 0.2, 1))
		H.link(b, "Tail", tp, tp + V(0, -0.35, 0.3), 0.16, G)
	end

	-- 불꽃 사자: 주황 사자, 불꽃 갈기 (노랑·주황 번갈아), 꼬리 끝 불
	PET_BUILDERS.FlameLion = function(b)
		local O = RGB(255, 170, 80)
		local c = chibi(b, { body = O, belly = RGB(255, 230, 190), eyeY = 0.04, noMouth = true })
		for i = 0, 8 do
			local a = math.rad(-110 + i * 220 / 8)
			local dir = V(math.sin(a), math.cos(a), 0.55)
			local p, n = surf(c.H, c.HS, dir)
			ell(b, "Mane", V(0.5, 0.85, 0.5), alongY(p + n * 0.25 + V(0, 0, 0.1), n + V(0, 0.6, 0)), if i % 2 == 0 then FIRE2 else FIRE1, if i == 4 then NEON else nil)
		end
		roundEars(c, 0.6, 0.75, 0.42, O, RGB(255, 210, 170))
		muzzle(c, V(0.6, 0.42, 0.4), RGB(255, 240, 210), RGB(120, 60, 40), -0.3)
		local tip = H.tail(b, c, O, { w = 0.28, d1 = V(0, 0.4, 1), d2 = V(0, 1, 0.3), l2 = 0.8 })
		flame(b, tip - V(0, 0.1, 0), 0.7, true)
		H.glow(H.part(b, "Body"), RGB(255, 170, 90), 0.2, 4)
	end

	-- 불꽃 해태 (시크릿): 금빛 해태, 초록 곱슬 갈기, 이마의 외뿔, 방울 목걸이, 발밑 불꽃 구름
	PET_BUILDERS.Haetae = function(b)
		local Y = RGB(255, 200, 90)
		local GR = RGB(80, 170, 130)
		local c = chibi(b, { body = Y, belly = RGB(255, 240, 200), feet = darker(Y, 0.2), eyeY = 0.06, noMouth = true })
		H.mane(b, c, GR, 9, 0.62, RGB(110, 200, 150))
		roundEars(c, 0.62, 0.72, 0.38, Y, RGB(255, 170, 120))
		muzzle(c, V(0.7, 0.45, 0.42), RGB(255, 235, 190), RGB(120, 60, 40), -0.3)
		for _, sx in SIDES do
			local bp = surf(c.H, c.HS, V(sx * 0.5, 0.65, -0.55))
			ell(b, "Brow", V(0.36, 0.16, 0.16), CFrame.new(bp) * CFrame.Angles(0, 0, -sx * 0.25), GR)
			-- 발밑 불꽃 구름
			ell(b, "FireCloud", V(0.8, 0.3, 0.8), CFrame.new(sx * 0.55, 0.08, 0), FIRE2, NEON, 0.15)
		end
		local hp = surf(c.H, c.HS, V(0, 1, -0.3))
		ell(b, "Horn", V(0.2, 0.55, 0.2), alongY(hp + V(0, 0.2, -0.05), V(0, 1, -0.2)), RGB(255, 245, 220))
		local ny = c.B.Y + c.BS.Y - 0.1
		addPart(b, "Collar", "Cyl", V(0.18, 1.7, 1.7), CFrame.new(0, ny, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(220, 60, 60))
		ell(b, "Bell", V(0.32, 0.32, 0.32), CFrame.new(0, ny - 0.2, -0.86), GOLD, METAL)
		-- 곱슬 꼬리 (초록 공 3개)
		local tp = surf(c.B, c.BS, V(0, -0.1, 1))
		Kit.ballArc(b, "Tail", tp + V(0, 0, 0.15), 0.5, { Y, GR, GR }, 0.42, 0.55)
		flame(b, tp + V(0, 0.65, 0.6), 0.55, true)
		H.glow(H.part(b, "Body"), RGB(255, 190, 110), 0.25, 4)
	end

	-- 불씨 냥이 (시크릿 알): 숯 같은 까만 고양이, 몸의 용암 금, 불꽃 귀 끝, 눈 같은 불씨 꼬리
	PET_BUILDERS.CinderCat = function(b)
		local K = RGB(70, 60, 70)
		local c = chibi(b, { body = K, belly = RGB(105, 90, 100), eyeY = 0.04 })
		pointyEars(c, 0.55, 0.85, 0.6, 0.72, 0.14, 0.25, K, FIRE2)
		smallNose(c, -0.2, V(0.14, 0.1, 0.08), FIRE2, 0.02)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.55, 0.85, 0))
			flame(b, p + V(sx * 0.2, 0.5, 0), 0.45)
		end
		cracks(b, c.B, c.BS, { { V(0.6, 0.3, 0.6), 0.5, 0.6 }, { V(-0.6, 0.1, 0.6), 0.45, -0.5 }, { V(0, 0.6, 1), 0.5, 0.1 } })
		cracks(b, c.H, c.HS, { { V(0.6, 0.6, 0.3), 0.4, 0.8 } })
		local tip = H.tail(b, c, K, { w = 0.26, d1 = V(0.4, 0.5, 1), d2 = V(0.2, 1, 0.2), l2 = 0.8 })
		flame(b, tip - V(0, 0.15, 0), 0.7, true)
		H.glow(H.part(b, "Body"), RGB(255, 120, 60), 0.25, 4)
	end

	-- 마그마 와이번 (천상): 붉은 와이번, 큰 막 날개 (주황 막 + 노랑 테두리), 등 용암 가시, 꼬리 끝 불
	PET_BUILDERS.MagmaWyvern = function(b)
		local R = RGB(230, 80, 50)
		local c = chibi(b, { body = R, belly = RGB(255, 190, 120), feet = darker(R, 0.25), eyeY = 0.04, noArms = true, BS = V(0.95, 0.8, 0.85) })
		H.horns(b, c, RGB(60, 50, 55), 0.7, 0.5, 0.6)
		for _, sx in SIDES do
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(R, 0.4))
			-- 큰 막 날개 (팔 겸용)
			local base = c.B + V(sx * 0.6, 0.35, 0.2)
			local fr = frameUp(base, V(sx, 0.75, 0.35), Vector3.zAxis)
			tri(b, "Wing", fr, 1.3, 1.9, 0.08, RGB(255, 130, 60))
			tri(b, "Wing", fr * CFrame.Angles(0, 0, sx * 0.75), 1.0, 1.4, 0.08, RGB(255, 160, 80))
			H.rod(b, "WingBone", base, base + V(sx, 0.75, 0.35).Unit * 1.9, 0.12, FIRE1, NEON)
		end
		H.spikes(b, c, RGB(60, 50, 55), 1.1)
		cracks(b, c.B, c.BS, { { V(0.7, 0.4, 0.4), 0.5, 0.6 }, { V(-0.7, 0.3, 0.4), 0.5, -0.6 }, { V(0, 0.2, 1), 0.6, 0 } })
		local tip, d = H.tail(b, c, R, { w = 0.55 })
		flame(b, tip + d * 0.05 - V(0, 0.1, 0), 0.8, true)
		H.glow(H.part(b, "Body"), RGB(255, 140, 80), 0.3, 4.5)
	end

	-- 불꽃 용 (이터널): 주황 용, 머리 위 불꽃 왕관, 불꽃 날개, 가슴의 태양 보석, 꼬리 큰 불
	PET_BUILDERS.InfernoDragon = function(b)
		local O = RGB(255, 90, 40)
		local c = chibi(b, { body = O, belly = RGB(255, 210, 120), feet = RGB(150, 40, 30), eyeY = 0.04, BS = V(0.95, 0.8, 0.85), HS = V(1.08, 0.98, 0.98) })
		H.horns(b, c, RGB(60, 45, 50), 0.62)
		for _, sx in SIDES do
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(O, 0.4))
		end
		-- 불꽃 날개 (깃 4장, 끝으로 갈수록 노랑)
		H.wings(b, c, { { 62, 1.55, 0.5, FIRE1 }, { 38, 1.45, 0.48, RGB(255, 160, 50) }, { 14, 1.2, 0.44, FIRE2 }, { -10, 0.9, 0.4, RGB(220, 60, 40) } }, { sweep = 0.3, lean = 0.3 })
		-- 불꽃 왕관 (머리 위 작은 불꽃 3개)
		local top = H.top(c, 0.9)
		flame(b, top + V(0, -0.05, 0.1), 0.7, true)
		flame(b, top + V(0.4, -0.15, 0.2), 0.45)
		flame(b, top + V(-0.4, -0.15, 0.2), 0.45)
		H.spikes(b, c, RGB(255, 210, 90), 1)
		local gp, gn = front(c.BeC, c.BeS, 0, 0.3)
		ell(b, "SunGem", V(0.34, 0.34, 0.12), facing(gp + gn * 0.03, gn), FIRE1, NEON)
		for i = 0, 5 do
			local a = i * math.pi / 3
			ell(b, "SunRay", V(0.08, 0.2, 0.06), facing(gp + gn * 0.02, gn) * CFrame.new(math.sin(a) * 0.28, math.cos(a) * 0.28, 0) * CFrame.Angles(0, 0, -a), GOLD)
		end
		local tip, d = H.tail(b, c, O, { w = 0.55 })
		flame(b, tip + d * 0.05 - V(0, 0.15, 0), 1.2, true)
		H.glow(H.part(b, "Body"), RGB(255, 140, 70), 0.45, 6)
	end

	----------------------------------------------------------------------
	-- 16 황금 왕국
	----------------------------------------------------------------------

	-- 동전 돼지: 분홍 저금통 돼지, 등의 동전 구멍에 꽂힌 금화
	PET_BUILDERS.CoinPig = function(b)
		local P = RGB(255, 190, 200)
		local c = chibi(b, { body = P, eyeY = 0.1, noMouth = true })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Head" then
				p.Reflectance = 0.1
			end
		end
		pointyEars(c, 0.55, 0.8, 0.5, 0.5, 0.12, 0.45, P, RGB(255, 160, 175), 0.5)
		local p, n = front(c.H, c.HS, 0, -0.2)
		local scf = facing(p + n * 0.05, n)
		addPart(b, "Snout", "Cyl", V(0.28, 0.55, 0.55), scf * CFrame.Angles(0, math.pi / 2, 0), RGB(255, 160, 180))
		for _, sx in SIDES do
			ell(b, "Nostril", V(0.1, 0.14, 0.05), scf * CFrame.new(sx * 0.1, 0, -0.15), RGB(200, 100, 120))
		end
		local mp, mn = front(c.H, c.HS, 0, -0.5)
		ell(b, "Mouth", V(0.14, 0.06, 0.05), facing(mp, mn), MOUTH)
		local top = H.top(c, 0.95)
		addPart(b, "Slot", "Block", V(0.5, 0.06, 0.14), CFrame.new(top), RGB(120, 60, 80))
		coin(b, top + V(0, 0.28, 0), V(1, 0, 0), 0.32)
		local tp = surf(c.B, c.BS, V(0, 0, 1))
		Kit.ballArc(b, "Tail", tp + V(0, 0, 0.1), 0.2, { P, P, P }, 0.2, 0.16)
	end

	-- 금빛 햄스터: 노란 햄스터, 볼이 빵빵 (금화 물고), 작은 금화 하나 안고
	PET_BUILDERS.GoldHamster = function(b)
		local Y = RGB(255, 215, 110)
		local c = chibi(b, { body = Y, belly = RGB(255, 245, 215), feet = RGB(255, 190, 170), eyeY = 0.04 })
		roundEars(c, 0.6, 0.75, 0.4, Y, RGB(255, 190, 170))
		smallNose(c, -0.2, V(0.14, 0.1, 0.08), RGB(255, 140, 150), 0.02)
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.55, -0.3)
			ell(b, "Cheek", V(0.6, 0.5, 0.36), facing(p - n * 0.06, n), RGB(255, 235, 180))
		end
		local cp, cn = front(c.BeC, c.BeS, 0, 0.05)
		coin(b, cp + cn * 0.15, cn, 0.38)
		ell(b, "Sparkle", V(0.12, 0.12, 0.12), CFrame.new(cp + cn * 0.25 + V(0.25, 0.3, 0)), WHITE, NEON)
	end

	-- 왕실 코기: 주황·하양 코기, 짧은 다리, 빨간 망토, 작은 금 왕관
	PET_BUILDERS.RoyalCorgi = function(b)
		local O = RGB(245, 175, 95)
		local c = H.quad(b, { body = O, belly = WHITE, legs = O, feet = WHITE, legH = 0.3, BS = V(0.8, 0.62, 1.1), HS = V(0.82, 0.76, 0.76), eyeX = 0.32, eyeY = 0.12 })
		local p, n = front(c.H, c.HS, 0, -0.25)
		ell(b, "Face", V(0.9, 0.7, 0.4), facing(p - n * 0.1, n), WHITE)
		ell(b, "Nose", V(0.22, 0.16, 0.14), facing(p + n * 0.12, n), RGB(40, 30, 30))
		local mp, mn = front(c.H, c.HS, 0, -0.42)
		ell(b, "Mouth", V(0.14, 0.06, 0.05), facing(mp + mn * 0.05, mn), MOUTH)
		pointyEars(c, 0.55, 0.85, 0.55, 0.8, 0.14, 0.3, O, RGB(255, 220, 200))
		ell(b, "Cape", V(1.8, 0.35, 2.0), CFrame.new(c.B + V(0, c.BS.Y * 0.8, 0.15)), RGB(210, 40, 60))
		addPart(b, "CapeTrim", "Cyl", V(0.2, 1.4, 0.7), CFrame.new(c.B + V(0, c.BS.Y * 0.9, -0.75)) * CFrame.Angles(0, 0, math.pi / 2), WHITE)
		H.crown(b, H.top(c, 0.88), 0.3, GOLD, RGB(255, 80, 120), METAL)
		local tp = surf(c.B, c.BS, V(0, 0.2, 1))
		ell(b, "Tail", V(0.3, 0.3, 0.3), CFrame.new(tp + V(0, 0, 0.08)), WHITE)
	end

	-- 왕관 개구리: 초록 개구리, 툭 튀어나온 눈, 큰 금 왕관
	PET_BUILDERS.CrownFrog = function(b)
		local G = RGB(120, 210, 110)
		local B = V(0, 0.7, 0.1)
		local BS = V(1.05, 0.7, 0.95)
		ell(b, "Body", BS * 2, CFrame.new(B), G)
		local HC = V(0, 1.45, -0.2)
		local HS = V(0.95, 0.65, 0.8)
		ell(b, "Head", HS * 2, CFrame.new(HC), G)
		ell(b, "Belly", V(1.4, 1.0, 1.0), CFrame.new(B + V(0, -0.1, -0.45)), RGB(240, 250, 200))
		for _, sx in SIDES do
			local ec = HC + V(sx * 0.48, 0.5, -0.15)
			ell(b, "EyeBump", V(0.6, 0.55, 0.55), CFrame.new(ec), G)
			Kit.addEye(b, ec, V(0.3, 0.28, 0.28), 0, 0, V(0.3, 0.34, 0.12), 0.01)
			local p, n = front(HC, HS, sx * 0.6, -0.15)
			ell(b, "Blush", V(0.26, 0.13, 0.05), facing(p, n), Kit.BLUSH, nil, 0.1)
			ell(b, "Foot", V(0.6, 0.25, 0.8), CFrame.new(sx * 0.75, 0.12, -0.2) * CFrame.Angles(0, sx * 0.3, 0), darker(G, 0.1))
			ell(b, "Leg", V(0.5, 0.6, 0.8), CFrame.new(sx * 0.8, 0.45, 0.4), darker(G, 0.05))
		end
		local mp, mn = front(HC, HS, 0, -0.25)
		ell(b, "Mouth", V(0.6, 0.06, 0.05), facing(mp, mn), MOUTH)
		H.crown(b, HC + V(0, HS.Y * 0.8, 0.05), 0.42, GOLD, RGB(80, 170, 255), METAL)
	end

	-- 기사 냥이: 은빛 갑옷 고양이, 투구 깃털, 작은 방패와 나무 칼
	PET_BUILDERS.KnightCat = function(b)
		local S = RGB(200, 205, 220)
		local FUR = RGB(255, 220, 180)
		local c = chibi(b, { body = S, head = FUR, feet = RGB(150, 155, 170), arms = S, eyeY = 0.0 })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Arm" or p.Name == "Foot" then
				p.Material = METAL
			end
		end
		pointyEars(c, 0.6, 0.8, 0.55, 0.62, 0.14, 0.35, FUR, RGB(255, 180, 190))
		smallNose(c, -0.2, V(0.14, 0.1, 0.08), RGB(255, 140, 160), 0.02)
		-- 투구 (머리 윗부분 + 빨간 깃털)
		ell(b, "Helmet", V(2.15, 1.25, 2.05), CFrame.new(c.H + V(0, 0.42, 0.05)), S, METAL)
		addPart(b, "HelmetBrim", "Cyl", V(0.14, 2.15, 2.05), CFrame.new(c.H + V(0, 0.15, 0.05)) * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
		local pp = H.top(c, 0.95)
		ell(b, "Plume", V(0.3, 0.8, 0.9), CFrame.new(pp + V(0, 0.45, 0.2)) * CFrame.Angles(0.4, 0, 0), RGB(230, 50, 70))
		-- 방패 (왼손) + 칼 (오른손)
		local lp = surf(c.B, c.BS, V(-1, 0, -0.4))
		addPart(b, "Shield", "Cyl", V(0.12, 0.95, 0.95), CFrame.new(lp + V(-0.15, 0, -0.1)) * CFrame.Angles(0, math.pi / 2 + 0.6, 0), RGB(60, 110, 220))
		ell(b, "ShieldMark", V(0.3, 0.3, 0.08), CFrame.new(lp + V(-0.15, 0, -0.1)) * CFrame.Angles(0, 0.6 + math.pi, 0) * CFrame.new(0, 0, -0.08), GOLD)
		local rp = surf(c.B, c.BS, V(1, 0, -0.4))
		H.rod(b, "Sword", rp + V(0.15, -0.1, -0.05), rp + V(0.25, 1.1, -0.3), 0.14, RGB(220, 225, 235), METAL)
		addPart(b, "SwordGuard", "Block", V(0.5, 0.1, 0.12), CFrame.new(rp + V(0.17, 0.12, -0.1)), GOLD, METAL)
		H.tail(b, c, FUR, { w = 0.26, d1 = V(0.3, 0.6, 1), d2 = V(0.1, 1, 0.2), l2 = 0.8 })
	end

	-- 왕실 사자: 금빛 사자, 붉은 갈기, 금 왕관, 빨간 망토
	PET_BUILDERS.RoyalLion = function(b)
		local Y = RGB(250, 200, 100)
		local c = chibi(b, { body = Y, belly = RGB(255, 240, 200), eyeY = 0.04, noMouth = true })
		H.mane(b, c, RGB(200, 100, 50), 11, 0.68, RGB(230, 130, 60))
		roundEars(c, 0.6, 0.75, 0.42, Y, RGB(255, 200, 160))
		muzzle(c, V(0.6, 0.42, 0.4), RGB(255, 245, 220), RGB(120, 60, 40), -0.3)
		H.crown(b, H.top(c, 0.88), 0.42, GOLD, RGB(255, 80, 120), METAL)
		ell(b, "Cape", V(1.9, 1.7, 0.3), CFrame.new(c.B + V(0, 0.2, c.BS.Z + 0.05)) * CFrame.Angles(0.15, 0, 0), RGB(200, 40, 60))
		addPart(b, "CapeTrim", "Cyl", V(0.24, 1.75, 0.6), CFrame.new(c.B + V(0, c.BS.Y * 0.95, 0.35)) * CFrame.Angles(0, 0, math.pi / 2), WHITE)
		local tip = H.tail(b, c, Y, { w = 0.28, d1 = V(0, 0.4, 1), d2 = V(0, 1, 0.3), l2 = 0.8 })
		ell(b, "TailTuft", V(0.4, 0.46, 0.4), CFrame.new(tip), RGB(200, 100, 50))
	end

	-- 황금 페가수스: 금빛 말, 하얀·금 날개, 금 갈기와 발굽
	PET_BUILDERS.GoldenPegasus = function(b)
		local Y = RGB(255, 220, 120)
		local c = H.quad(b, { body = Y, legs = Y, feet = GOLD, legH = 0.7, legW = 0.32, BS = V(0.7, 0.58, 1.05), HS = V(0.62, 0.6, 0.7), headAt = V(0, 2.55, -1.0), eyeX = 0.28, eyeSize = V(0.26, 0.36, 0.13) })
		H.link(b, "Neck", c.B + V(0, 0.25, -0.7), c.H + V(0, -0.25, 0.25), 0.55, Y)
		H.lashes(b, c.eyes, 0.8)
		H.snout(b, c, RGB(255, 240, 200), V(0.55, 0.45, 0.6), -0.3)
		for _, sx in SIDES do
			local ep = surf(c.H, c.HS, V(sx * 0.5, 1, 0.2))
			ell(b, "Ear", V(0.18, 0.4, 0.14), CFrame.new(ep + V(0, 0.12, 0)) * CFrame.Angles(0, 0, -sx * 0.2), Y)
		end
		for i = 0, 5 do
			ell(b, "Mane", V(0.34, 0.34, 0.34), CFrame.new(c.H + V(0, 0.5 - i * 0.3, 0.42 + i * 0.12)), if i % 2 == 0 then GOLD else RGB(255, 240, 170), METAL)
		end
		H.wings(b, c, { { 60, 1.4, 0.44, WHITE }, { 35, 1.25, 0.42, RGB(255, 245, 210) }, { 10, 1.0, 0.38, GOLD } }, { x = 0.6, y = 0.6, sweep = 0.3, lean = 0.35 })
		local tp = surf(c.B, c.BS, V(0, 0.2, 1))
		H.link(b, "Tail", tp, tp + V(0, -0.5, 0.5), 0.3, GOLD, METAL)
		H.glow(H.part(b, "Body"), RGB(255, 225, 140), 0.2, 4)
	end

	-- 임금 펭귄 (시크릿): 남색 펭귄, 목의 금빛 무늬, 빨간 망토, 큰 왕관, 홀
	PET_BUILDERS.KingPenguin = function(b)
		local N = RGB(60, 70, 110)
		local c = chibi(b, {
			body = N,
			belly = WHITE,
			feet = RGB(255, 170, 60),
			arms = N,
			face = { color = WHITE, semi = V(0.82, 0.68, 0.55), offset = V(0, -0.12, -0.45) },
			eyeX = 0.32,
			blushX = 0.55,
			blushY = -0.22,
			noMouth = true,
		})
		H.beak(b, c, RGB(255, 170, 60), -0.2, V(0.3, 0.2, 0.36))
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx, -0.1, -0.2))
			H.stick(b, "GoldPatch", p, n, 0.3, 0.42, 1, RGB(255, 190, 60))
		end
		ell(b, "Cape", V(1.9, 1.8, 0.3), CFrame.new(c.B + V(0, 0.2, c.BS.Z + 0.05)) * CFrame.Angles(0.15, 0, 0), RGB(200, 40, 60))
		addPart(b, "CapeTrim", "Cyl", V(0.24, 1.75, 0.6), CFrame.new(c.B + V(0, c.BS.Y * 0.95, 0.35)) * CFrame.Angles(0, 0, math.pi / 2), WHITE)
		H.crown(b, H.top(c, 0.84), 0.5, GOLD, RGB(80, 170, 255), METAL)
		local hp = surf(c.B, c.BS, V(1, -0.05, -0.45))
		H.rod(b, "Scepter", hp + V(0.15, -0.5, -0.1), hp + V(0.2, 0.9, -0.25), 0.1, GOLD, METAL)
		ell(b, "ScepterGem", V(0.3, 0.3, 0.3), CFrame.new(hp + V(0.21, 1.0, -0.26)), RGB(80, 170, 255), NEON)
		H.glow(H.part(b, "Body"), RGB(200, 210, 255), 0.25, 4)
	end

	-- 보물상자 친구 (시크릿 알): 나무 보물상자 몸, 뚜껑 사이로 보이는 눈과 혀, 넘치는 금화와 보석
	PET_BUILDERS.TreasureMimic = function(b)
		local WD = RGB(190, 120, 60)
		local B = V(0, 0.6, 0)
		addPart(b, "Body", "Block", V(2.0, 1.2, 1.5), CFrame.new(B), WD, Enum.Material.Wood)
		-- 뚜껑 (뒤쪽 경첩으로 살짝 열림)
		local lid = CFrame.new(0, 1.2, 0.75) * CFrame.Angles(0.45, 0, 0) * CFrame.new(0, 0.25, -0.75)
		addPart(b, "Head", "Block", V(2.0, 0.5, 1.5), lid, darker(WD, 0.05), Enum.Material.Wood)
		addPart(b, "Lid", "Cyl", V(2.0, 0.9, 1.5), lid * CFrame.new(0, 0.2, 0), darker(WD, 0.05), Enum.Material.Wood)
		for _, x in { -0.8, 0.8 } do
			addPart(b, "Band", "Block", V(0.18, 1.24, 1.54), CFrame.new(B + V(x, 0, 0)), GOLD, METAL)
			addPart(b, "Band", "Block", V(0.18, 0.54, 1.54), lid * CFrame.new(x, 0, 0), GOLD, METAL)
		end
		addPart(b, "Lock", "Block", V(0.36, 0.42, 0.12), CFrame.new(0, 1.0, -0.78), GOLD, METAL)
		-- 앞면 눈 (상자 몸에)
		for _, sx in SIDES do
			-- (아주 납작한 타원 = 상자 앞면에 딱 붙어요)
			Kit.addEye(b, B + V(0, 0.15, 0), V(5, 5, 0.78), sx * 0.5, 0, V(0.32, 0.4, 0.12), 0)
			ell(b, "Blush", V(0.28, 0.14, 0.05), CFrame.new(B + V(sx * 0.75, -0.05, -0.77)), Kit.BLUSH, nil, 0.1)
		end
		ell(b, "Tongue", V(0.5, 0.12, 0.7), CFrame.new(0, 1.18, -0.75) * CFrame.Angles(0.35, 0, 0), RGB(255, 120, 150))
		-- 넘치는 금화 + 보석
		for i, o in { V(-0.5, 1.3, -0.2), V(0.4, 1.32, -0.1), V(0, 1.38, 0.1), V(0.7, 1.25, 0.25) } do
			coin(b, o, V(0.2 * i - 0.4, 1, -0.3), 0.22)
		end
		ell(b, "Gem", V(0.26, 0.3, 0.26), CFrame.new(-0.2, 1.45, 0.05), RGB(80, 220, 255), NEON)
		ell(b, "Gem", V(0.22, 0.26, 0.22), CFrame.new(0.35, 1.45, 0.25), RGB(255, 80, 130), GLASS)
		for _, sx in SIDES do
			ell(b, "Foot", V(0.4, 0.2, 0.4), CFrame.new(sx * 0.7, 0.05, -0.4), darker(WD, 0.25))
		end
		H.glow(H.part(b, "Gem"), RGB(255, 220, 120), 0.25, 4)
	end

	-- 왕관 그리핀 (천상): 금빛 독수리 머리 + 사자 몸, 하얀·금 날개, 왕관, 꼬리 술
	PET_BUILDERS.CrownGriffin = function(b)
		local Y = RGB(255, 215, 90)
		local W = RGB(255, 250, 240)
		local c = chibi(b, { body = Y, head = W, belly = RGB(255, 240, 200), feet = RGB(230, 175, 80), arms = RGB(255, 180, 60), eyeY = 0.06, noMouth = true })
		local bc = H.beak(b, c, RGB(255, 170, 50), -0.24, V(0.38, 0.28, 0.36))
		ell(b, "Beak", V(0.18, 0.2, 0.14), bc * CFrame.new(0, -0.1, -0.12) * CFrame.Angles(0.5, 0, 0), RGB(240, 140, 45))
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.7, 0.6, 0.4))
			ell(b, "EarFeather", V(0.2, 0.55, 0.14), alongY(p + V(sx * 0.1, 0.15, 0.1), V(sx * 0.5, 1, 0.5)), W)
		end
		H.wings(b, c, { { 60, 1.55, 0.48, W }, { 35, 1.4, 0.46, RGB(255, 240, 200) }, { 10, 1.15, 0.42, Y }, { -12, 0.85, 0.38, GOLD } }, { sweep = 0.3, lean = 0.3 })
		H.crown(b, H.top(c, 0.88), 0.42, GOLD, RGB(255, 80, 120), METAL)
		local tip = H.tail(b, c, Y, { w = 0.26, d1 = V(0, 0.4, 1), d2 = V(0, 1, 0.3), l2 = 0.8 })
		ell(b, "TailTuft", V(0.4, 0.46, 0.4), CFrame.new(tip), W)
		H.sparkles(b, c, WHITE, { { "H", V(0.7, 0.5, -0.4) }, { "B", V(-0.85, 0.2, -0.35) } })
		H.glow(H.part(b, "Body"), RGB(255, 225, 150), 0.3, 4.5)
	end

	-- 황제 용 (이터널): 금빛 용, 큰 황제 왕관, 빨간 망토, 금 날개, 가슴 루비, 꼬리 끝 여의주
	PET_BUILDERS.EmperorDragon = function(b)
		local Y = RGB(255, 200, 60)
		local RED = RGB(200, 40, 60)
		local c = chibi(b, { body = Y, belly = RGB(255, 240, 190), feet = RGB(230, 150, 40), eyeY = 0.04, BS = V(0.95, 0.8, 0.85), HS = V(1.08, 0.98, 0.98) })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Head" then
				p.Reflectance = 0.12
			end
		end
		for _, y in { 0.22, -0.04, -0.3 } do
			local p, n = front(c.BeC, c.BeS, 0, y)
			H.stick(b, "BellyLine", p, n, 0.5, 0.07, 0.62, RGB(230, 170, 60))
		end
		for _, sx in SIDES do
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(Y, 0.4))
			-- 용 수염 (긴 가는 선)
			local wp, wn = front(c.H, c.HS, sx * 0.3, -0.25)
			H.link(b, "Whisker", wp + wn * 0.05, wp + V(sx * 0.8, -0.35, -0.2), 0.07, RED)
			-- 금 날개
			local base = c.B + V(sx * 0.32, 0.5, 0.55)
			tri(b, "Wing", frameUp(base, V(sx, 0.8, 0.5), Vector3.zAxis), 1.05, 1.55, 0.08, GOLD, METAL)
			tri(b, "Wing", frameUp(base + V(0, -0.1, 0.1), V(sx, 0.3, 0.7), Vector3.zAxis), 0.8, 1.1, 0.08, RGB(255, 235, 150))
		end
		H.horns(b, c, RGB(255, 245, 220), 0.55, 0.55, 0.5)
		H.crown(b, H.top(c, 0.86), 0.5, GOLD, RGB(255, 60, 90), METAL)
		ell(b, "Cape", V(1.9, 1.6, 0.3), CFrame.new(c.B + V(0, 0.1, c.BS.Z + 0.08)) * CFrame.Angles(0.15, 0, 0), RED)
		local gp, gn = front(c.BeC, c.BeS, 0, 0.35)
		ell(b, "Ruby", V(0.3, 0.36, 0.12), facing(gp + gn * 0.04, gn) * CFrame.Angles(0, 0, math.pi / 4), RGB(255, 50, 80), NEON)
		local tip, d = H.tail(b, c, Y, { w = 0.55 })
		ell(b, "Pearl", V(0.5, 0.5, 0.5), CFrame.new(tip + d * 0.2), RGB(255, 250, 230), NEON)
		H.sparkles(b, c, WHITE, { { "H", V(0.7, 0.55, -0.4) }, { "B", V(-0.85, 0.2, -0.35) }, { "B", V(0.8, 0.3, 0.4) } })
		H.glow(H.part(b, "Body"), RGB(255, 220, 120), 0.45, 6)
	end
end
