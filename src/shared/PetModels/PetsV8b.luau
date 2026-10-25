-- ★v8 11 보석 동굴 / 12 사막 오아시스 펫 (PetModels/init.luau 가 불러서 등록)
-- 규칙은 init.luau 와 같아요: 앞쪽 = -Z, 바닥 = y 0, 몸 = Body, 머리 = Head.
return function(Kit, PET_BUILDERS, _EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.chibi, Kit.SIDES
	local addPart, darker, alongY, tri, frameUp, muzzle, smallNose, pointyEars, roundEars = Kit.addPart, Kit.darker, Kit.alongY, Kit.tri, Kit.frameUp, Kit.muzzle, Kit.smallNose, Kit.pointyEars, Kit.roundEars
	local WHITE, EYE = Kit.WHITE, Kit.EYE
	local NEON = Enum.Material.Neon
	local GLASS = Enum.Material.Glass
	local METAL = Enum.Material.Metal
	local H = require(script.Parent.V8Kit).make(Kit)
	local foxBase = H.foxBase

	-- 보석 기둥 하나 (몸 표면에서 바깥으로 솟은 육각 기둥 느낌: 길쭉한 블록 + 뾰족 끝)
	local function crystal(b, base, dir, w, h, color, mat, transparency)
		local d = dir.Unit
		local cf = alongY(base + d * h * 0.35, d) * CFrame.Angles(0, math.pi / 4, 0)
		addPart(b, "Crystal", "Block", V(w, h * 0.7, w), cf, color, mat or GLASS, transparency or 0.1)
		H.blade(b, "Crystal", base + d * h * 0.7, d, cf.RightVector, w * 1.3, h * 0.45, w * 0.9, color, mat or GLASS, transparency or 0.1)
	end

	-- 복슬 꼬리 (뒤로 나갔다 위로, 끝 색 따로)
	local function bushyTail(b, c, col, tipCol, k)
		local s = k or 1
		local tp = surf(c.B, c.BS, V(0, -0.2, 1))
		local t1 = tp + V(0.2, 0.35, 0.45) * s
		ell(b, "Tail", V(0.62, 0.62, 1.0) * s, CFrame.lookAt(t1, t1 + V(0.3, 0.8, 0.6)), col)
		local t2 = t1 + V(0.15, 0.55, 0.15) * s
		ell(b, "TailTip", V(0.5, 0.62, 0.5) * s, CFrame.new(t2), tipCol)
		return t2
	end

	----------------------------------------------------------------------
	-- 11 보석 동굴
	----------------------------------------------------------------------

	-- 동굴 박쥐: 보라 꼬마 박쥐, 큰 귀, 박쥐 날개, 작은 송곳니
	PET_BUILDERS.CaveBat = function(b)
		local P = RGB(150, 120, 200)
		local c = chibi(b, { body = P, belly = RGB(210, 195, 240), eyeY = 0.04, noArms = true })
		pointyEars(c, 0.6, 0.8, 0.7, 0.95, 0.14, 0.4, P, RGB(255, 190, 215))
		local fp, fn = front(c.H, c.HS, 0, -0.42)
		for _, sx in SIDES do
			ell(b, "Tooth", V(0.07, 0.1, 0.05), facing(fp + fn * 0.01, fn) * CFrame.new(sx * 0.1, -0.05, 0), WHITE)
			local base = c.B + V(sx * 0.6, 0.3, 0.15)
			local fr = frameUp(base, V(sx, 0.35, 0.25), Vector3.zAxis)
			tri(b, "Wing", fr, 1.0, 1.25, 0.07, RGB(120, 95, 170))
			tri(b, "Wing", fr * CFrame.Angles(0, 0, sx * 0.7), 0.8, 1.0, 0.07, RGB(120, 95, 170))
		end
		smallNose(c, -0.24, V(0.14, 0.1, 0.08), RGB(255, 150, 180), 0.02)
	end

	-- 광부 두더지: 갈색 두더지, 분홍 코, 큰 앞발 손톱, 불 켜진 노란 안전모
	PET_BUILDERS.Mole = function(b)
		local BR = RGB(150, 110, 90)
		local c = chibi(b, { body = BR, belly = RGB(210, 175, 150), arms = RGB(255, 190, 180), eyeY = 0.06, eyeSize = V(0.26, 0.32, 0.12), noMouth = true })
		local p, n = front(c.H, c.HS, 0, -0.28)
		ell(b, "Muzzle", V(0.55, 0.38, 0.4), facing(p - n * 0.05, n), RGB(225, 185, 160))
		ell(b, "Nose", V(0.3, 0.24, 0.2), facing(p + n * 0.15, n), RGB(255, 130, 160))
		local mp, mn = front(c.H, c.HS, 0, -0.5)
		ell(b, "Mouth", V(0.14, 0.06, 0.05), facing(mp, mn), Kit.MOUTH)
		for _, sx in SIDES do
			local cp = surf(c.B, c.BS, V(sx * 0.8, -0.1, -0.7))
			for i = -1, 1 do
				ell(b, "Claw", V(0.08, 0.08, 0.26), CFrame.lookAt(cp + V(sx * 0.05 + i * 0.08, -0.05, -0.1), cp + V(i * 0.1, -0.3, -1)), RGB(255, 245, 230))
			end
		end
		-- 안전모 + 앞 램프
		local top = H.top(c, 0.55)
		ell(b, "Helmet", V(2.0, 1.2, 1.95), CFrame.new(top + V(0, 0.15, 0.02)), RGB(255, 205, 60))
		addPart(b, "HelmetBrim", "Cyl", V(0.08, 2.2, 2.2), CFrame.new(top - V(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2), RGB(245, 185, 40))
		local lp, ln = surf(top + V(0, 0.15, 0.02), V(1.0, 0.6, 0.98), V(0, 0.4, -1))
		addPart(b, "Lamp", "Cyl", V(0.16, 0.36, 0.36), H.along(lp + ln * 0.06, ln) * CFrame.Angles(0, -math.pi / 2, 0), RGB(200, 200, 210), METAL)
		ell(b, "LampLight", V(0.28, 0.28, 0.08), facing(lp + ln * 0.15, ln), RGB(255, 250, 200), NEON)
	end

	-- 보석 달팽이: 하늘색 몸, 눈자루, 등껍질 대신 반짝이는 보석 무더기
	PET_BUILDERS.GemSnail = function(b)
		local S = RGB(150, 230, 255)
		local B = V(0, 0.38, 0.25)
		local BS = V(0.62, 0.38, 1.25)
		ell(b, "Body", BS * 2, CFrame.new(B), S)
		local HC = V(0, 1.05, -0.75)
		local HS = V(0.62, 0.62, 0.58)
		H.link(b, "Neck", B + V(0, 0.1, -0.7), HC, 0.85, S)
		ell(b, "Head", HS * 2, CFrame.new(HC), S)
		for _, sx in SIDES do
			Kit.addEye(b, HC, HS, sx * 0.24, 0.0, V(0.24, 0.32, 0.12), 0)
			local p, n = front(HC, HS, sx * 0.36, -0.22)
			ell(b, "Blush", V(0.2, 0.11, 0.05), facing(p, n), Kit.BLUSH, nil, 0.1)
			local s0 = surf(HC, HS, V(sx * 0.4, 1, 0))
			local s1 = s0 + V(sx * 0.15, 0.5, -0.05)
			H.rod(b, "Stalk", s0, s1, 0.1, S)
			ell(b, "StalkTip", V(0.2, 0.2, 0.2), CFrame.new(s1), RGB(110, 200, 240))
		end
		local mp, mn = front(HC, HS, 0, -0.3)
		ell(b, "Mouth", V(0.14, 0.06, 0.05), facing(mp, mn), Kit.MOUTH)
		-- 보석 껍데기: 동그란 돌 + 솟은 보석 5개
		local SC = V(0, 1.15, 0.5)
		ell(b, "Shell", V(1.3, 1.25, 1.3), CFrame.new(SC), RGB(130, 120, 150))
		for i, g in { { V(0, 1, 0), RGB(120, 230, 255) }, { V(0.6, 0.6, 0.2), RGB(255, 130, 200) }, { V(-0.6, 0.6, 0.1), RGB(170, 130, 255) }, { V(0.2, 0.5, 0.8), RGB(140, 255, 190) }, { V(-0.3, 0.5, -0.7), RGB(255, 220, 110) } } do
			local p = surf(SC, V(0.65, 0.62, 0.65), g[1])
			crystal(b, p - g[1].Unit * 0.1, g[1], if i == 1 then 0.3 else 0.22, if i == 1 then 0.8 else 0.55, g[2])
		end
	end

	-- 정동 거북: 회색 돌 껍데기가 반으로 갈라져 안에 보라 수정이 반짝
	PET_BUILDERS.GeodeTurtle = function(b)
		local SK = RGB(150, 200, 150)
		local c = H.quad(b, { body = SK, BS = V(0.85, 0.55, 1.0), legH = 0.35, legW = 0.42, HS = V(0.62, 0.58, 0.6), eyeX = 0.26, eyeSize = V(0.24, 0.34, 0.12) })
		H.snout(b, c, SK, V(0.5, 0.3, 0.3), -0.25)
		local SC = c.B + V(0, 0.3, 0.05)
		local SS = V(1.1, 0.75, 1.2)
		ell(b, "Shell", SS * 2, CFrame.new(SC), RGB(140, 130, 125))
		-- 갈라진 틈 (위쪽) 과 수정들
		ell(b, "Geode", V(1.3, 0.5, 1.5), CFrame.new(SC + V(0, SS.Y - 0.12, 0)), RGB(90, 60, 130))
		for i, d in { V(0, 1, 0), V(0.35, 0.9, 0.3), V(-0.35, 0.9, -0.25), V(0.3, 0.9, -0.4), V(-0.3, 0.9, 0.4) } do
			local p = SC + V(d.X * 0.9, SS.Y - 0.12, d.Z * 0.9)
			crystal(b, p, V(d.X, 1, d.Z), if i == 1 then 0.26 else 0.18, if i == 1 then 0.7 else 0.45, if i % 2 == 0 then RGB(200, 150, 255) else RGB(170, 110, 240))
		end
		for _, d in { V(1, -0.2, 0.3), V(-1, -0.2, -0.3), V(0.4, -0.1, 1) } do
			H.patch(b, "ShellSpot", SC, SS, d, 0.4, 0.3, RGB(115, 105, 100))
		end
		local tp = surf(c.B, c.BS, V(0, -0.2, 1))
		ell(b, "Tail", V(0.24, 0.2, 0.42), CFrame.new(tp + V(0, 0, 0.12)), SK)
	end

	-- 루비 여우: 빨간 여우, 이마와 꼬리 끝에 빨간 보석, 하얀 볼
	PET_BUILDERS.RubyFox = function(b)
		local R = RGB(240, 60, 90)
		local c = foxBase(b, R, RGB(255, 240, 240), { feet = RGB(120, 30, 50), arms = RGB(120, 30, 50) })
		local mp, mn = front(c.H, c.HS, 0, -0.42)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), Kit.MOUTH)
		local gp, gn = front(c.H, c.HS, 0, 0.55)
		ell(b, "Ruby", V(0.34, 0.42, 0.16), facing(gp + gn * 0.04, gn) * CFrame.Angles(0, 0, math.pi / 4), RGB(255, 40, 80), GLASS, 0.05)
		ell(b, "RubyShine", V(0.1, 0.1, 0.05), facing(gp + gn * 0.12, gn) * CFrame.new(0.06, 0.06, 0), WHITE, NEON)
		local t2 = bushyTail(b, c, R, RGB(255, 245, 245))
		crystal(b, t2 + V(0, 0.15, 0), V(0, 1, 0.2), 0.22, 0.5, RGB(255, 50, 90))
	end

	-- 사파이어 늑대: 파란 늑대, 등에 사파이어 수정 3개, 하얀 목털
	PET_BUILDERS.SapphireWolf = function(b)
		local B = RGB(70, 120, 240)
		local c = foxBase(b, B, RGB(225, 235, 255), { earW = 0.6, earH = 0.85, earTilt = 0.18, earIn = RGB(190, 210, 255) })
		muzzle(c, V(0.55, 0.36, 0.36), RGB(225, 235, 255), RGB(30, 35, 60), -0.3)
		-- 목털 (복슬 공 5개)
		for i = -2, 2 do
			local p = surf(c.B, c.BS, V(i * 0.35, 0.75, -0.75))
			ell(b, "Ruff", V(0.42, 0.42, 0.35), CFrame.new(p), RGB(235, 242, 255))
		end
		for i, d in { V(0, 1, 0.6), V(0.3, 0.8, 0.9), V(-0.3, 0.8, 0.9) } do
			local p, n = surf(c.B, c.BS, d)
			crystal(b, p - n * 0.05, n + V(0, 0.4, 0.3), if i == 1 then 0.26 else 0.2, if i == 1 then 0.75 else 0.55, RGB(80, 150, 255))
		end
		bushyTail(b, c, B, RGB(225, 235, 255))
		H.glow(H.part(b, "Crystal"), RGB(120, 170, 255), 0.15, 3)
	end

	-- 자수정 부엉이: 보라 부엉이, 보석 귀깃, 가슴 V 무늬, 날개
	PET_BUILDERS.AmethystOwl = function(b)
		local P = RGB(170, 100, 230)
		local c = chibi(b, {
			body = P,
			belly = RGB(230, 210, 250),
			feet = RGB(255, 200, 90),
			face = { color = RGB(240, 225, 255), semi = V(0.9, 0.7, 0.55), offset = V(0, -0.05, -0.47) },
			eyeX = 0.36,
			eyeSize = V(0.42, 0.52, 0.16),
			noMouth = true,
			noArms = true,
		})
		H.beak(b, c, RGB(255, 200, 90), -0.22, V(0.22, 0.26, 0.22))
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.55, 0.85, 0))
			crystal(b, p, V(sx * 0.5, 1, 0.1), 0.2, 0.62, RGB(190, 120, 255))
			local wp = surf(c.B, c.BS, V(sx, 0.1, 0.1))
			ell(b, "Wing", V(0.3, 0.95, 0.75), CFrame.new(wp) * CFrame.Angles(0, 0, sx * 0.2), darker(P, 0.12))
		end
		for i = -1, 1 do
			local p, n = front(c.BeC, c.BeS, i * 0.22, 0.15 - math.abs(i) * 0.1)
			ell(b, "Feather", V(0.18, 0.12, 0.05), facing(p + n * 0.01, n), RGB(180, 130, 230))
		end
		local gp, gn = front(c.BeC, c.BeS, 0, -0.15)
		ell(b, "Gem", V(0.24, 0.3, 0.1), facing(gp + gn * 0.03, gn) * CFrame.Angles(0, 0, math.pi / 4), RGB(210, 150, 255), NEON)
	end

	-- 보석 골렘 (시크릿): 네모난 돌 몸, 어깨와 머리에서 자라는 청록 수정, 가슴의 빛나는 핵
	PET_BUILDERS.GemGolem = function(b)
		local ST = RGB(140, 145, 160)
		local GEM = RGB(120, 230, 220)
		local B = V(0, 1.1, 0.1)
		addPart(b, "Body", "Block", V(1.7, 1.3, 1.3), CFrame.new(B), ST)
		local HC = V(0, 2.25, 0)
		addPart(b, "Head", "Block", V(1.5, 1.1, 1.2), CFrame.new(HC), ST)
		for _, sx in SIDES do
			Kit.addEye(b, HC, V(0.75, 0.55, 0.6), sx * 0.32, 0.05, V(0.3, 0.38, 0.12), 0)
			ell(b, "Blush", V(0.26, 0.13, 0.05), CFrame.new(HC + V(sx * 0.52, -0.2, -0.61)), Kit.BLUSH, nil, 0.1)
			-- 다리 + 팔 (돌 덩어리)
			addPart(b, "Foot", "Block", V(0.62, 0.5, 0.7), CFrame.new(sx * 0.45, 0.25, 0.05), darker(ST, 0.1))
			addPart(b, "Arm", "Block", V(0.5, 1.0, 0.55), CFrame.new(sx * 1.1, 1.05, 0) * CFrame.Angles(0, 0, sx * 0.15), darker(ST, 0.05))
			addPart(b, "Hand", "Block", V(0.6, 0.45, 0.6), CFrame.new(sx * 1.2, 0.45, -0.05), darker(ST, 0.1))
			crystal(b, V(sx * 0.7, 1.75, 0.2), V(sx * 0.6, 1, 0.2), 0.26, 0.75, GEM)
		end
		ell(b, "Mouth", V(0.2, 0.08, 0.05), CFrame.new(HC + V(0, -0.27, -0.61)), Kit.MOUTH)
		crystal(b, HC + V(0.25, 0.5, 0.1), V(0.3, 1, 0.1), 0.24, 0.65, GEM)
		crystal(b, HC + V(-0.2, 0.5, 0.15), V(-0.2, 1, 0), 0.18, 0.45, RGB(170, 140, 255))
		crystal(b, B + V(0, 0.5, 0.6), V(0, 0.6, 1), 0.22, 0.55, GEM)
		ell(b, "Core", V(0.5, 0.5, 0.16), CFrame.new(B + V(0, 0.05, -0.66)), GEM, NEON)
		for _, o in { V(0.5, 0.35, -0.66), V(-0.55, -0.3, -0.66), V(0.45, -0.4, -0.66) } do
			ell(b, "Crack", V(0.3, 0.06, 0.04), CFrame.new(B + o) * CFrame.Angles(0, 0, 0.5), darker(ST, 0.3))
		end
		H.glow(H.part(b, "Core"), GEM, 0.25, 4)
	end

	-- 오팔 토끼 (시크릿 알): 진주빛 하얀 토끼, 무지개 반짝이, 이마의 오팔
	PET_BUILDERS.OpalBunny = function(b)
		local W = RGB(240, 245, 255)
		local c = chibi(b, { body = W, belly = WHITE, feet = RGB(225, 230, 250), eyeY = 0.02 })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Head" then
				p.Reflectance = 0.15
			end
		end
		H.lashes(b, c.eyes)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.38, 1, 0.05))
			local cf = CFrame.new(p) * CFrame.Angles(0, 0, -sx * 0.2) * CFrame.new(0, 0.5, 0)
			ell(b, "Ear", V(0.42, 1.25, 0.24), cf, W)
			ell(b, "EarInner", V(0.22, 0.95, 0.08), cf * CFrame.new(0, 0.04, -0.09), RGB(200, 230, 255))
		end
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 170, 200), 0.02)
		local gp, gn = front(c.H, c.HS, 0, 0.5)
		ell(b, "Opal", V(0.36, 0.42, 0.14), facing(gp + gn * 0.04, gn), RGB(210, 240, 255), GLASS, 0.05)
		ell(b, "OpalFire", V(0.16, 0.16, 0.06), facing(gp + gn * 0.1, gn) * CFrame.new(-0.05, 0.05, 0), RGB(255, 150, 210), NEON)
		local cols = Kit.RAINBOW
		for i, d in { V(0.7, 0.5, 0.4), V(-0.7, 0.4, 0.5), V(0.4, 0.2, 0.9), V(-0.3, -0.2, 0.95), V(0.8, -0.2, -0.3), V(-0.8, 0.1, -0.2) } do
			local p, n = surf(c.B, c.BS, d)
			ell(b, "Speck", V(0.14, 0.14, 0.05), facing(p + n * 0.01, n), cols[i])
		end
		local tp, tn = surf(c.B, c.BS, V(0, -0.1, 1))
		ell(b, "Tail", V(0.5, 0.5, 0.5), CFrame.new(tp + tn * 0.1), WHITE)
		H.glow(H.part(b, "Body"), RGB(220, 230, 255), 0.2, 4)
	end

	-- 크리스탈 사슴 (천상): 하늘색 아기 사슴, 투명한 수정 뿔, 등에 반짝이는 수정 점
	PET_BUILDERS.CrystalDeer = function(b)
		local F = RGB(170, 230, 255)
		local CR = RGB(200, 245, 255)
		local c = chibi(b, { body = F, belly = WHITE, feet = RGB(120, 170, 220), eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		H.lashes(b, c.eyes)
		muzzle(c, V(0.56, 0.38, 0.36), WHITE, RGB(90, 110, 160), -0.32)
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx, 0.42, 0.05))
			ell(b, "Ear", V(0.66, 0.3, 0.2), CFrame.new(p + n * 0.14) * CFrame.Angles(0, 0, sx * 0.4), F)
			-- 수정 뿔 (줄기 + 가지 2)
			local ap = surf(c.H, c.HS, V(sx * 0.42, 1, 0.12))
			crystal(b, ap, V(sx * 0.35, 1, 0.1), 0.2, 1.1, CR, GLASS, 0.15)
			crystal(b, ap + V(sx * 0.12, 0.35, 0), V(sx, 0.6, -0.1), 0.15, 0.6, CR, GLASS, 0.15)
			crystal(b, ap + V(sx * 0.2, 0.6, 0.05), V(sx * 0.3, 0.8, 0.6), 0.13, 0.45, RGB(220, 200, 255), GLASS, 0.15)
		end
		for i, d in { V(0.5, 0.6, 0.6), V(-0.5, 0.5, 0.7), V(0, 0.8, 0.5) } do
			local p, n = surf(c.B, c.BS, d)
			ell(b, "Spark", V(0.2, 0.2, 0.06), facing(p + n * 0.01, n) * CFrame.Angles(0, 0, math.pi / 4), WHITE, if i == 1 then NEON else nil)
		end
		local tp, tn = surf(c.B, c.BS, V(0, 0.1, 1))
		ell(b, "Tail", V(0.32, 0.36, 0.28), CFrame.new(tp + tn * 0.06), WHITE)
		H.glow(H.part(b, "Body"), RGB(190, 235, 255), 0.3, 4.5)
	end

	-- 다이아몬드 용 (이터널): 하얗게 빛나는 용, 다이아 가시와 뿔, 투명한 유리 날개, 가슴 다이아
	PET_BUILDERS.DiamondDragon = function(b)
		local W = RGB(220, 240, 255)
		local D = RGB(235, 250, 255)
		local c = chibi(b, { body = W, belly = RGB(250, 252, 255), feet = RGB(170, 200, 230), eyeY = 0.04, BS = V(0.95, 0.8, 0.85), HS = V(1.08, 0.98, 0.98) })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Head" then
				p.Reflectance = 0.2
			end
		end
		H.lashes(b, c.eyes)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.45, 1, 0.1))
			crystal(b, p, V(sx * 0.35, 1, 0.45), 0.22, 0.8, D, GLASS, 0.1)
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), RGB(150, 170, 200))
			-- 유리 날개 (큰 + 작은)
			local base = c.B + V(sx * 0.32, 0.5, 0.55)
			tri(b, "Wing", frameUp(base, V(sx, 0.8, 0.5), Vector3.zAxis), 1.05, 1.6, 0.06, RGB(200, 235, 255), GLASS)
			tri(b, "Wing", frameUp(base + V(0, -0.1, 0.1), V(sx, 0.3, 0.7), Vector3.zAxis), 0.8, 1.15, 0.06, RGB(225, 210, 255), GLASS)
			b.parts[#b.parts].Transparency = 0.25
			b.parts[#b.parts - 1].Transparency = 0.25
		end
		for _, sp in { { c.H, c.HS, V(0, 0.55, 1) }, { c.B, c.BS, V(0, 0.7, 1) }, { c.B, c.BS, V(0, 0.2, 1) } } do
			local p, n = surf(sp[1], sp[2], sp[3])
			crystal(b, p - n * 0.05, n, 0.2, 0.5, D, GLASS, 0.1)
		end
		local gp, gn = front(c.BeC, c.BeS, 0, 0.3)
		H.gem(b, "Diamond", gp + gn * 0.12, 0.3, RGB(200, 245, 255))
		local tip, d = H.tail(b, c, W, { w = 0.5 })
		crystal(b, tip, d, 0.24, 0.6, D, GLASS, 0.1)
		H.sparkles(b, c, WHITE, { { "H", V(0.7, 0.5, -0.4) }, { "B", V(-0.85, 0.2, -0.35) }, { "H", V(-0.6, 0.6, 0.3) } })
		H.glow(H.part(b, "Body"), RGB(210, 240, 255), 0.45, 6)
	end

	----------------------------------------------------------------------
	-- 12 사막 오아시스
	----------------------------------------------------------------------

	-- 사막여우: 크림색 작은 여우, 아주 큰 귀
	PET_BUILDERS.Fennec = function(b)
		local F = RGB(245, 205, 150)
		local c = foxBase(b, F, RGB(255, 245, 230), { earX = 0.6, earW = 0.85, earH = 1.25, earTilt = 0.35, earIn = RGB(255, 210, 200) })
		local mp, mn = front(c.H, c.HS, 0, -0.42)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), Kit.MOUTH)
		bushyTail(b, c, F, RGB(150, 110, 80), 0.9)
	end

	-- 아기 낙타: 네 발, 등에 혹 하나, 긴 속눈썹, 알록달록 안장 담요
	PET_BUILDERS.BabyCamel = function(b)
		local C = RGB(215, 170, 110)
		local c = H.quad(b, { body = C, belly = RGB(240, 210, 170), legH = 0.7, legW = 0.36, HS = V(0.68, 0.62, 0.7), headAt = V(0, 2.35, -0.95), eyeX = 0.28, eyeSize = V(0.26, 0.36, 0.13) })
		H.link(b, "Neck", c.B + V(0, 0.3, -0.75), c.H + V(0, -0.25, 0.15), 0.5, C)
		H.lashes(b, c.eyes, 0.8)
		H.snout(b, c, RGB(235, 200, 150), V(0.62, 0.42, 0.42), -0.25)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx, 0.4, 0.2))
			ell(b, "Ear", V(0.2, 0.3, 0.14), CFrame.new(p) * CFrame.Angles(0, 0, -sx * 0.6), C)
		end
		local hp = surf(c.B, c.BS, V(0, 1, 0.1))
		ell(b, "Hump", V(1.0, 0.9, 1.0), CFrame.new(hp), C)
		-- 담요 (혹 앞뒤로 걸친 빨강 + 노랑 테두리)
		ell(b, "Blanket", V(1.85, 0.5, 1.5), CFrame.new(c.B + V(0, c.BS.Y * 0.72, 0.1)), RGB(230, 80, 90))
		addPart(b, "BlanketTrim", "Cyl", V(0.1, 1.95, 1.95), CFrame.new(c.B + V(0, c.BS.Y * 0.62, 0.1)) * CFrame.Angles(0, 0, math.pi / 2), RGB(255, 210, 80))
		H.link(b, "Tail", surf(c.B, c.BS, V(0, 0.1, 1)), surf(c.B, c.BS, V(0, 0.1, 1)) + V(0, -0.35, 0.2), 0.14, C)
	end

	-- 미어캣: 꼿꼿이 선 날씬한 몸, 눈 둘레 까만 무늬, 손을 모은 자세
	PET_BUILDERS.Meerkat = function(b)
		local M = RGB(210, 175, 125)
		local c = chibi(b, { body = M, belly = RGB(245, 225, 190), BS = V(0.68, 1.0, 0.62), HS = V(0.8, 0.78, 0.8), eyeY = 0.06, eyeX = 0.3, eyeSize = V(0.28, 0.36, 0.13), noMouth = true, noArms = true })
		for _, cf in c.eyes do
			ell(b, "EyePatch", V(0.42, 0.5, 0.1), cf * CFrame.new(0, 0, 0.05), RGB(90, 65, 50))
		end
		local p, n = front(c.H, c.HS, 0, -0.25)
		ell(b, "Muzzle", V(0.38, 0.3, 0.42), facing(p - n * 0.02, n), RGB(235, 205, 160))
		ell(b, "Nose", V(0.16, 0.11, 0.1), facing(p + n * 0.18, n), RGB(60, 45, 40))
		for _, sx in SIDES do
			local ep = surf(c.H, c.HS, V(sx, 0.2, 0.1))
			ell(b, "Ear", V(0.14, 0.24, 0.2), CFrame.new(ep), RGB(90, 65, 50))
			local ap = surf(c.B, c.BS, V(sx * 0.6, 0.35, -0.8))
			ell(b, "Arm", V(0.2, 0.5, 0.2), CFrame.new(ap + V(-sx * 0.05, 0, -0.05)) * CFrame.Angles(-0.4, 0, -sx * 0.5), M)
		end
		for _, y in { 0.4, 0.0 } do
			H.patch(b, "Stripe", c.B, c.BS, V(0, y, 1), 0.9, 0.12, RGB(170, 135, 95))
		end
		local tp = surf(c.B, c.BS, V(0, -0.6, 1))
		H.link(b, "Tail", tp, tp + V(0, -0.35, 0.7), 0.2, M)
		ell(b, "TailTip", V(0.18, 0.18, 0.3), CFrame.new(tp + V(0, -0.38, 0.78)), RGB(90, 65, 50))
	end

	-- 선인장 친구: 초록 통 선인장 몸, 양팔, 머리 위 분홍 꽃, 하얀 가시 점, 화분 발
	PET_BUILDERS.CactusPal = function(b)
		local G = RGB(110, 190, 100)
		local POT = RGB(215, 120, 80)
		addPart(b, "Pot", "Cyl", V(0.7, 1.4, 1.4), CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, math.pi / 2), POT)
		addPart(b, "PotRim", "Cyl", V(0.2, 1.6, 1.6), CFrame.new(0, 0.72, 0) * CFrame.Angles(0, 0, math.pi / 2), darker(POT, 0.1))
		local B = V(0, 1.65, 0)
		local BS = V(0.75, 1.0, 0.72)
		ell(b, "Body", BS * 2, CFrame.new(B), G)
		local c = { b = b, B = B, BS = BS, H = B + V(0, 0.2, 0), HS = BS, FC = B + V(0, 0.2, 0), FS = BS }
		for _, sx in SIDES do
			Kit.addEye(b, c.FC, c.FS, sx * 0.28, 0.1, V(0.26, 0.34, 0.13), 0)
			local p, n = front(c.FC, c.FS, sx * 0.48, -0.12)
			ell(b, "Blush", V(0.24, 0.13, 0.05), facing(p, n), Kit.BLUSH, nil, 0.1)
			-- 팔: 옆으로 나갔다 위로
			local a0 = surf(B, BS, V(sx, -0.1, 0))
			local a1 = a0 + V(sx * 0.45, 0, 0)
			H.link(b, "Arm", a0 - V(sx * 0.1, 0, 0), a1, 0.36, G)
			H.link(b, "Arm", a1, a1 + V(0, 0.5, 0), 0.34, G)
		end
		local mp, mn = front(c.FC, c.FS, 0, -0.18)
		ell(b, "Mouth", V(0.16, 0.08, 0.05), facing(mp, mn), Kit.MOUTH)
		for _, d in { V(0.5, 0.5, 0.6), V(-0.5, 0.4, 0.6), V(0.6, -0.3, 0.5), V(-0.55, -0.4, 0.5), V(0, 0.2, 1), V(0.3, -0.6, -0.7), V(-0.3, -0.6, -0.7) } do
			local p, n = surf(B, BS, d)
			ell(b, "Prickle", V(0.08, 0.08, 0.12), CFrame.lookAt(p + n * 0.04, p + n), RGB(255, 250, 230))
		end
		H.flower(b, B + V(0.1, BS.Y + 0.02, 0), V(0, 1, -0.4), 0.55, RGB(255, 120, 170), RGB(255, 225, 100))
	end

	-- 아르마딜로: 띠 무늬 갑옷 등, 작은 귀, 긴 주둥이
	PET_BUILDERS.Armadillo = function(b)
		local SK = RGB(220, 185, 160)
		local AR = RGB(180, 150, 130)
		local c = H.quad(b, { body = SK, BS = V(0.8, 0.6, 1.05), legH = 0.35, HS = V(0.62, 0.58, 0.62), eyeX = 0.26, eyeSize = V(0.24, 0.34, 0.12) })
		H.snout(b, c, SK, V(0.42, 0.36, 0.6), -0.25)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.6, 0.8, 0.2))
			ell(b, "Ear", V(0.18, 0.36, 0.14), CFrame.new(p + V(0, 0.1, 0)) * CFrame.Angles(0, 0, -sx * 0.3), SK)
		end
		local SC = c.B + V(0, 0.18, 0.05)
		for i = -2, 2 do
			addPart(b, "Band", "Cyl", V(0.36, 1.85 - math.abs(i) * 0.18, 1.85 - math.abs(i) * 0.18), CFrame.new(SC + V(0, 0, i * 0.38)) * CFrame.Angles(0, math.pi / 2, 0), if i % 2 == 0 then AR else darker(AR, 0.1))
		end
		ell(b, "Shell", V(1.75, 1.25, 2.1), CFrame.new(SC + V(0, 0.05, 0)), AR, nil, 0)
		for i = -2, 2 do
			local p = SC + V(0, 0.68, i * 0.38)
			addPart(b, "BandLine", "Block", V(1.2, 0.05, 0.06), CFrame.new(p - V(0, 0.08 * math.abs(i), 0)), darker(AR, 0.25))
		end
		local tp = surf(c.B, c.BS, V(0, -0.1, 1))
		H.link(b, "Tail", tp, tp + V(0, -0.2, 0.7), 0.22, AR)
	end

	-- 스핑크스 냥이: 금빛 고양이, 파랑·금 줄무늬 머리 장식, 이마 코브라 장식, 금 목걸이
	PET_BUILDERS.SphinxCat = function(b)
		local GO = RGB(240, 200, 120)
		local BLUE = RGB(50, 90, 200)
		local GOLD = RGB(255, 205, 70)
		local c = chibi(b, { body = GO, belly = RGB(255, 235, 190), eyeY = 0.04 })
		pointyEars(c, 0.55, 0.85, 0.6, 0.75, 0.14, 0.25, GO, RGB(255, 200, 170))
		smallNose(c, -0.2, V(0.14, 0.1, 0.08), RGB(220, 120, 110), 0.02)
		for _, cf in c.eyes do
			addPart(b, "Lash", "Block", V(0.3, 0.05, 0.04), cf * CFrame.new(0.2, -0.04, -0.05), EYE)
		end
		-- 머리 장식 (네메스): 머리 위 덮개 + 양옆으로 늘어진 천, 줄무늬
		ell(b, "Headdress", V(2.2, 1.2, 2.05), CFrame.new(c.H + V(0, 0.4, 0.06)), BLUE)
		for _, y in { 0.15, 0.45 } do
			addPart(b, "HeaddressLine", "Cyl", V(0.1, 2.1, 2.0), CFrame.new(c.H + V(0, y, 0.06)) * CFrame.Angles(0, 0, math.pi / 2), GOLD)
		end
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx, -0.3, 0.1))
			addPart(b, "Lappet", "Block", V(0.3, 1.0, 0.7), CFrame.new(p + V(sx * 0.08, -0.25, 0)), BLUE)
			addPart(b, "Lappet", "Block", V(0.32, 0.1, 0.72), CFrame.new(p + V(sx * 0.08, -0.15, 0)), GOLD)
		end
		local cp, cn = front(c.H, c.HS, 0, 0.62)
		ell(b, "Cobra", V(0.2, 0.36, 0.14), facing(cp + cn * 0.12, cn), GOLD, METAL)
		-- 금 목걸이 (넓은 띠)
		local ny = c.B.Y + c.BS.Y - 0.15
		addPart(b, "Collar", "Cyl", V(0.24, 1.7, 1.7), CFrame.new(0, ny, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
		ell(b, "CollarGem", V(0.2, 0.2, 0.08), CFrame.new(0, ny - 0.05, -0.84), RGB(60, 200, 190))
		H.tail(b, c, GO, { w = 0.28, d1 = V(0.3, 0.6, 1), d2 = V(0.1, 1, 0.2), l2 = 0.8 })
	end

	-- 파라오 강아지: 까만 강아지, 길고 뾰족한 귀, 금 귀걸이·목걸이, 눈가 금빛 화장
	PET_BUILDERS.PharaohPup = function(b)
		local K = RGB(60, 60, 80)
		local GOLD = RGB(255, 205, 70)
		local c = chibi(b, { body = K, belly = RGB(90, 90, 115), feet = RGB(45, 45, 60), eyeY = 0.06, noMouth = true })
		muzzle(c, V(0.55, 0.38, 0.4), RGB(80, 80, 100), RGB(25, 25, 30), -0.3)
		pointyEars(c, 0.5, 0.88, 0.5, 1.1, 0.14, 0.1, K, GOLD)
		for _, cf in c.eyes do
			addPart(b, "Lash", "Block", V(0.36, 0.06, 0.04), cf * CFrame.new(0.2, -0.02, -0.05) * CFrame.Angles(0, 0, -0.15), GOLD)
		end
		local ny = c.B.Y + c.BS.Y - 0.15
		addPart(b, "Collar", "Cyl", V(0.3, 1.75, 1.75), CFrame.new(0, ny, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
		addPart(b, "Collar", "Cyl", V(0.12, 1.85, 1.85), CFrame.new(0, ny - 0.18, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(60, 120, 220))
		ell(b, "CollarGem", V(0.24, 0.26, 0.08), CFrame.new(0, ny - 0.08, -0.88), RGB(255, 80, 80), NEON)
		for _, sx in SIDES do
			ell(b, "Earring", V(0.16, 0.16, 0.16), CFrame.new(surf(c.H, c.HS, V(sx, 0.05, 0)) + V(sx * 0.05, -0.12, 0)), GOLD, METAL)
		end
		H.tail(b, c, K, { w = 0.28, d1 = V(0, 0.6, 1), d2 = V(0, 1, 0.3) })
	end

	-- 모래 용 (시크릿): 모래색 용, 등에 모래 물결 무늬, 머리 두건, 꼬리를 감싼 작은 모래바람
	PET_BUILDERS.SandDragon = function(b)
		local S = RGB(230, 190, 120)
		local DK = RGB(200, 150, 90)
		local c = chibi(b, { body = S, belly = RGB(255, 235, 195), feet = DK, eyeY = 0.04 })
		H.horns(b, c, RGB(255, 245, 220), 0.6, 0.4, 0.6)
		for _, sx in SIDES do
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(S, 0.4))
		end
		for _, y in { 0.6, 0.25, -0.1 } do
			H.patch(b, "Wave", c.B, c.BS, V(0, y, 1), 1.3, 0.12, DK)
		end
		H.patch(b, "Wave", c.H, c.HS, V(0, 0.5, 1), 1.2, 0.12, DK)
		H.batWings(b, c, RGB(240, 170, 90), 0.95, 1.35, RGB(255, 215, 150))
		-- 두건 (머리 뒤로 늘어진 천)
		ell(b, "Hood", V(1.6, 0.5, 1.4), CFrame.new(c.H + V(0, 0.75, 0.3)) * CFrame.Angles(0.3, 0, 0), RGB(90, 160, 200))
		ell(b, "Hood", V(1.0, 0.25, 1.2), CFrame.new(c.H + V(0, 0.35, 1.05)) * CFrame.Angles(1.1, 0, 0), RGB(90, 160, 200))
		local tip, d = H.tail(b, c, S, { w = 0.5 })
		for i = 0, 2 do
			local a = i * 2.1
			addPart(b, "SandSwirl", "Cyl", V(0.06, 0.8 - i * 0.18, 0.8 - i * 0.18), CFrame.new(tip + V(0, i * 0.18, 0)) * CFrame.Angles(0, a, math.pi / 2 + 0.2), RGB(255, 225, 160), nil, 0.35)
		end
		ell(b, "TailGem", V(0.22, 0.22, 0.22), CFrame.new(tip + d * 0.1), RGB(60, 200, 190), NEON)
		H.glow(H.part(b, "Body"), RGB(255, 215, 150), 0.25, 4)
	end

	-- 램프 요정 (시크릿 알): 금 램프에서 솟아오른 파란 요정, 꼬리는 연기처럼 감겨요, 금 팔찌, 상투
	PET_BUILDERS.LampGenie = function(b)
		local BL = RGB(120, 170, 255)
		local GOLD = RGB(255, 205, 70)
		-- 램프 (바닥)
		ell(b, "Lamp", V(1.6, 0.6, 1.0), CFrame.new(0, 0.3, 0.1), GOLD, METAL)
		ell(b, "Lamp", V(0.4, 0.2, 0.9), CFrame.new(0, 0.42, -0.75) * CFrame.Angles(-0.4, 0, 0), GOLD, METAL)
		addPart(b, "Lamp", "Cyl", V(0.12, 0.5, 0.5), CFrame.new(0, 0.62, 0.1) * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
		addPart(b, "LampHandle", "Cyl", V(0.1, 0.55, 0.55), CFrame.new(0, 0.45, 0.68) * CFrame.Angles(0, math.pi / 2, 0), GOLD, METAL)
		-- 연기 꼬리 (아래가 가는 공 3개)
		for i, y in { 0.75, 1.05, 1.35 } do
			local d = 0.4 + i * 0.22
			ell(b, "Smoke", V(d, d * 0.75, d), CFrame.new(0.1 * (i % 2 * 2 - 1), y, 0.1), BL, nil, 0.1)
		end
		local B = V(0, 1.85, 0)
		local BS = V(0.75, 0.6, 0.65)
		ell(b, "Body", BS * 2, CFrame.new(B), BL)
		local HC = V(0, 2.95, 0)
		local HS = V(0.92, 0.85, 0.85)
		ell(b, "Head", HS * 2, CFrame.new(HC), BL)
		local c = { b = b, B = B, BS = BS, H = HC, HS = HS, FC = HC, FS = HS }
		for _, sx in SIDES do
			Kit.addEye(b, HC, HS, sx * 0.34, 0.02, V(0.32, 0.44, 0.15), 0)
			local p, n = front(HC, HS, sx * 0.56, -0.28)
			ell(b, "Blush", V(0.28, 0.15, 0.05), facing(p, n), Kit.BLUSH, nil, 0.1)
			-- 팔짱 낀 팔 + 금 팔찌
			local ap = surf(B, BS, V(sx, 0.1, -0.4))
			H.link(b, "Arm", ap, ap + V(-sx * 0.55, 0.05, -0.35), 0.32, BL)
			addPart(b, "Bracelet", "Cyl", V(0.12, 0.38, 0.38), H.along(ap + V(-sx * 0.15, 0.02, -0.1), V(-sx * 0.55, 0.05, -0.35)) * CFrame.Angles(0, -math.pi / 2, 0), GOLD, METAL)
			ell(b, "Earring", V(0.16, 0.16, 0.16), CFrame.new(surf(HC, HS, V(sx, -0.2, 0)) + V(0, -0.12, 0)), GOLD, METAL)
		end
		local mp, mn = front(HC, HS, 0, -0.35)
		ell(b, "Mouth", V(0.24, 0.08, 0.05), facing(mp, mn), Kit.MOUTH)
		-- 상투 + 금 고리
		local top = H.top(c, 0.9)
		addPart(b, "HairTie", "Cyl", V(0.16, 0.36, 0.36), CFrame.new(top + V(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
		ell(b, "Hair", V(0.4, 0.75, 0.4), CFrame.new(top + V(0, 0.45, 0.1)) * CFrame.Angles(0.4, 0, 0), RGB(40, 40, 70))
		ell(b, "Sparkle", V(0.16, 0.16, 0.16), CFrame.new(0.45, 0.85, -0.85), RGB(200, 230, 255), NEON)
		H.glow(H.part(b, "Body"), RGB(150, 200, 255), 0.25, 4)
	end

	-- 태양 풍뎅이 (천상): 청록 금속 풍뎅이, 앞다리로 굴리는 빛나는 금빛 해 공, 금 날개 무늬
	PET_BUILDERS.SunScarab = function(b)
		local T = RGB(60, 200, 180)
		local GOLD = RGB(255, 210, 80)
		local c = chibi(b, { body = T, head = RGB(80, 215, 195), feet = darker(T, 0.25), arms = darker(T, 0.25), eyeY = 0.04, BS = V(1.0, 0.8, 0.95) })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Head" then
				p.Reflectance = 0.15
			end
		end
		-- 등딱지 두 장 + 금 테두리 줄
		local SC = c.B + V(0, 0.1, 0.12)
		for _, sx in SIDES do
			ell(b, "Shell", V(1.05, 1.7, 1.85), CFrame.new(SC + V(sx * 0.5, 0, 0)) * CFrame.Angles(0, 0, -sx * 0.08), darker(T, 0.2), METAL)
			H.patch(b, "ShellMark", SC + V(sx * 0.5, 0, 0), V(0.52, 0.85, 0.92), V(sx * 0.4, 0.6, 0.6), 0.36, 0.5, GOLD)
		end
		H.rod(b, "ShellLine", SC + V(0, 0.85, -0.15), SC + V(0, -0.1, 0.94), 0.06, GOLD)
		-- 뿔 (앞으로 휘어진)
		local hp = surf(c.H, c.HS, V(0, 1, -0.2))
		H.link(b, "Horn", hp, hp + V(0, 0.4, -0.3), 0.18, GOLD)
		-- 해 공 (머리 위 원반 + 빛살)
		local sc = H.top(c, 0.9) + V(0, 0.85, 0.2)
		ell(b, "Sun", V(0.75, 0.75, 0.75), CFrame.new(sc), RGB(255, 200, 70), NEON)
		for i = 0, 7 do
			local a = i * math.pi / 4
			ell(b, "SunRay", V(0.12, 0.34, 0.08), CFrame.new(sc + V(math.sin(a) * 0.55, math.cos(a) * 0.55, 0)) * CFrame.Angles(0, 0, -a), GOLD)
		end
		H.horns(b, c, darker(T, 0.25), 0.4, 0.6, -0.2)
		H.glow(H.part(b, "Sun"), RGB(255, 210, 120), 0.35, 5)
	end

	-- 신기루 용 (이터널): 주황·분홍 용, 반투명 날개와 꼬리 끝 아지랑이, 금 장신구, 오아시스 물방울 보석
	PET_BUILDERS.MirageDragon = function(b)
		local O = RGB(255, 170, 110)
		local P = RGB(255, 140, 180)
		local GOLD = RGB(255, 210, 90)
		local c = chibi(b, { body = O, head = RGB(255, 185, 130), belly = RGB(255, 225, 190), feet = P, eyeY = 0.04, BS = V(0.95, 0.8, 0.85), HS = V(1.08, 0.98, 0.98) })
		H.lashes(b, c.eyes)
		H.horns(b, c, GOLD, 0.65, 0.35, 0.5)
		for _, sx in SIDES do
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(O, 0.4))
			ell(b, "Earring", V(0.2, 0.2, 0.2), CFrame.new(surf(c.H, c.HS, V(sx, -0.1, 0)) + V(0, -0.16, 0)), GOLD, METAL)
		end
		-- 이마 물방울 보석 (오아시스)
		local gp, gn = front(c.H, c.HS, 0, 0.55)
		ell(b, "Gem", V(0.3, 0.4, 0.14), facing(gp + gn * 0.05, gn), RGB(80, 210, 255), NEON)
		addPart(b, "Circlet", "Cyl", V(0.1, 2.1, 2.0), CFrame.new(c.H + V(0, 0.45, 0)) * CFrame.Angles(0.35, 0, math.pi / 2), GOLD, METAL)
		-- 날개 (주황 → 분홍 깃 날개, 반투명)
		H.wings(b, c, { { 58, 1.45, 0.62, RGB(255, 210, 150) }, { 30, 1.25, 0.56, O }, { 2, 0.95, 0.48, P } }, { transparency = 0.2, thick = 0.07 })
		local tip, d = H.tail(b, c, O, { w = 0.5, color2 = P })
		-- 꼬리 끝 아지랑이 (반투명 물방울 3개가 위로)
		for i = 0, 2 do
			local r = 0.34 - i * 0.08
			ell(b, "HeatWave", V(r, r * 1.3, r), CFrame.new(tip + d * 0.1 + V(0, 0.1 + i * 0.3, 0)), RGB(255, 225, 170), if i == 0 then NEON else GLASS, 0.3)
		end
		H.sparkles(b, c, RGB(255, 240, 180), { { "H", V(0.7, 0.55, -0.4) }, { "B", V(-0.85, 0.2, -0.35) }, { "B", V(0.8, 0.4, 0.4) } })
		H.glow(H.part(b, "Body"), RGB(255, 190, 140), 0.45, 6)
	end
end
