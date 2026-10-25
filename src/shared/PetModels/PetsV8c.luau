-- ★v8 13 장난감 나라 / 14 꿈나라 펫 (PetModels/init.luau 가 불러서 등록)
-- 규칙은 init.luau 와 같아요: 앞쪽 = -Z, 바닥 = y 0, 몸 = Body, 머리 = Head.
return function(Kit, PET_BUILDERS, _EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.chibi, Kit.SIDES
	local addPart, darker, alongY, tri, frameUp, muzzle, smallNose, pointyEars, roundEars = Kit.addPart, Kit.darker, Kit.alongY, Kit.tri, Kit.frameUp, Kit.muzzle, Kit.smallNose, Kit.pointyEars, Kit.roundEars
	local WHITE, EYE, MOUTH = Kit.WHITE, Kit.EYE, Kit.MOUTH
	local NEON = Enum.Material.Neon
	local GLASS = Enum.Material.Glass
	local METAL = Enum.Material.Metal
	local WOOD = Enum.Material.Wood
	local H = require(script.Parent.V8Kit).make(Kit)
	local foxBase = H.foxBase

	-- 등의 태엽 열쇠 (손잡이 고리 2개)
	local function windKey(b, c, color)
		local p, n = surf(c.B, c.BS, V(0, 0.2, 1))
		local q = p + n * 0.35
		H.rod(b, "Key", p - n * 0.05, q, 0.12, color, METAL)
		for _, sx in SIDES do
			addPart(b, "KeyLoop", "Cyl", V(0.1, 0.42, 0.42), CFrame.new(q + V(sx * 0.2, 0.05, 0)) * CFrame.Angles(0, math.pi / 2, 0), color, METAL)
		end
	end

	-- 톱니바퀴 (원판 + 이 8개)
	local function gear(b, pos, normal, r, color)
		local cf = H.along(pos, normal) * CFrame.Angles(0, -math.pi / 2, 0)
		addPart(b, "Gear", "Cyl", V(0.1, r * 2, r * 2), cf, color, METAL)
		for i = 0, 5 do
			local a = i * math.pi / 3
			addPart(b, "GearTooth", "Block", V(0.1, r * 0.35, r * 0.35), cf * CFrame.new(0, math.cos(a) * r, math.sin(a) * r), color, METAL)
		end
		addPart(b, "Gear", "Cyl", V(0.14, r * 0.6, r * 0.6), cf, darker(color, 0.25), METAL)
	end

	-- 수면 모자 (원뿔 대신 휘어진 긴 공 2개 + 끝 방울)
	local function nightcap(b, c, color, pom)
		local top = H.top(c, 0.62)
		ell(b, "Cap", V(c.HS.X * 1.85, 0.75, c.HS.Z * 1.85), CFrame.new(top + V(0, 0.1, 0.05)), color)
		addPart(b, "CapBand", "Cyl", V(0.2, c.HS.X * 1.9, c.HS.Z * 1.9), CFrame.new(top - V(0, 0.1, -0.05)) * CFrame.Angles(0, 0, math.pi / 2), WHITE)
		local p1 = top + V(0.1, 0.6, 0.15)
		local p2 = p1 + V(0.45, 0.2, 0.25)
		H.link(b, "Cap", top + V(0, 0.3, 0), p1, 0.62, color)
		H.link(b, "Cap", p1, p2, 0.38, color)
		ell(b, "CapPom", V(0.36, 0.36, 0.36), CFrame.new(p2 + V(0.15, -0.12, 0.05)), pom or WHITE)
	end

	-- 머리 위 쿨쿨 (Z 블록 2개)
	local function zzz(b, c)
		for i, o in { V(1.0, 0.8, -0.1), V(1.4, 1.4, 0.1) } do
			local s = 0.18 + i * 0.06
			local cf = CFrame.new(c.H + o)
			addPart(b, "Zzz", "Block", V(s * 2, s * 0.35, 0.06), cf * CFrame.new(0, s, 0), RGB(200, 210, 255))
			addPart(b, "Zzz", "Block", V(s * 2, s * 0.35, 0.06), cf * CFrame.new(0, -s, 0), RGB(200, 210, 255))
			addPart(b, "Zzz", "Block", V(s * 2.6, s * 0.35, 0.06), cf * CFrame.Angles(0, 0, 0.75), RGB(200, 210, 255))
		end
	end

	-- 별 (납작 공 5개 + 가운데). small = 반짝이 십자 2개만 (파트 아끼기)
	local function star(b, name, pos, normal, r, color, mat, small)
		local cf = CFrame.lookAt(pos, pos + normal)
		if small then
			ell(b, name, V(r * 0.3, r * 1.2, 0.08), cf, color, mat)
			ell(b, name, V(r * 1.2, r * 0.3, 0.08), cf, color, mat)
			return
		end
		H.petals(b, name, cf, 5, r * 0.5, V(r * 0.5, r * 0.75, 0.08), color, mat)
		ell(b, name, V(r * 0.7, r * 0.7, 0.1), cf, color, mat)
	end

	----------------------------------------------------------------------
	-- 13 장난감 나라
	----------------------------------------------------------------------

	-- 곰인형: 갈색 곰, 꿰맨 배 조각, 빨간 나비넥타이
	PET_BUILDERS.TeddyBear = function(b)
		local BR = RGB(200, 140, 90)
		local c = chibi(b, { body = BR, belly = RGB(245, 215, 175), feet = RGB(245, 215, 175), eyeY = 0.06, noMouth = true })
		roundEars(c, 0.62, 0.72, 0.45, BR, RGB(245, 215, 175))
		muzzle(c, V(0.6, 0.42, 0.4), RGB(245, 215, 175), RGB(70, 45, 35), -0.28)
		-- 바느질 자국 (배 위 짧은 막대)
		for i = -2, 2 do
			local p, n = front(c.BeC, c.BeS, i * 0.13, 0.05)
			addPart(b, "Stitch", "Block", V(0.04, 0.16, 0.04), facing(p + n * 0.02, n), RGB(140, 90, 60))
		end
		H.patch(b, "Patch", c.H, c.HS, V(0.7, 0.6, -0.3), 0.3, 0.3, RGB(140, 190, 230))
		local ny = c.B.Y + c.BS.Y - 0.05
		for _, sx in SIDES do
			ell(b, "Bow", V(0.4, 0.3, 0.14), CFrame.new(sx * 0.2, ny, -0.8) * CFrame.Angles(0, 0, sx * 0.3), RGB(230, 60, 80))
		end
		ell(b, "Bow", V(0.16, 0.16, 0.16), CFrame.new(0, ny, -0.84), RGB(200, 40, 60))
	end

	-- 고무 오리: 반짝이는 노란 오리, 주황 부리, 작은 날개, 머리 위 비누 거품
	PET_BUILDERS.RubberDuck = function(b)
		local Y = RGB(255, 220, 60)
		local B = V(0, 0.75, 0.15)
		local BS = V(0.95, 0.72, 1.15)
		ell(b, "Body", BS * 2, CFrame.new(B), Y)
		local HC = V(0, 1.85, -0.45)
		local HS = V(0.78, 0.74, 0.74)
		ell(b, "Head", HS * 2, CFrame.new(HC), Y)
		for _, p in b.parts do
			p.Reflectance = 0.1
		end
		local c = { b = b, B = B, BS = BS, H = HC, HS = HS, FC = HC, FS = HS }
		for _, sx in SIDES do
			Kit.addEye(b, HC, HS, sx * 0.3, 0.1, V(0.28, 0.38, 0.14), 0)
			local p, n = front(HC, HS, sx * 0.48, -0.16)
			ell(b, "Blush", V(0.24, 0.13, 0.05), facing(p, n), Kit.BLUSH, nil, 0.1)
			local wp = surf(B, BS, V(sx, 0.3, 0.2))
			ell(b, "Wing", V(0.25, 0.6, 0.9), CFrame.new(wp) * CFrame.Angles(0.3, 0, sx * 0.2), RGB(250, 205, 50))
		end
		local bc = H.beak(b, c, RGB(255, 140, 50), -0.18, V(0.6, 0.24, 0.55))
		ell(b, "Beak", V(0.5, 0.16, 0.45), bc * CFrame.new(0, -0.12, 0), RGB(240, 120, 40))
		local tp = surf(B, BS, V(0, 0.5, 1))
		ell(b, "Tail", V(0.4, 0.5, 0.4), CFrame.new(tp + V(0, 0.1, 0)) * CFrame.Angles(-0.6, 0, 0), Y)
		for i, o in { V(0.3, 2.75, -0.2), V(-0.15, 2.85, 0.05), V(0.05, 3.15, -0.05) } do
			local r = if i == 3 then 0.32 else 0.42
			ell(b, "Bubble", V(r, r, r), CFrame.new(o), RGB(220, 240, 255), GLASS, 0.35)
		end
	end

	-- 태엽 생쥐: 은색 쇠 생쥐, 큰 동그란 귀, 바퀴 발, 등에 금 태엽
	PET_BUILDERS.WindUpMouse = function(b)
		local S = RGB(190, 195, 210)
		local c = chibi(b, { body = S, belly = RGB(225, 228, 238), feet = RGB(90, 90, 100), eyeY = 0.04, BS = V(0.85, 0.7, 0.9) })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Head" then
				p.Material = METAL
			end
		end
		roundEars(c, 0.7, 0.75, 0.75, S, RGB(255, 190, 200))
		smallNose(c, -0.25, V(0.16, 0.12, 0.1), RGB(255, 140, 170), 0.04)
		for _, sx in SIDES do
			for _, a in { 0.12, -0.12 } do
				local wp, wn = front(c.H, c.HS, sx * 0.42, -0.3 + a)
				addPart(b, "Whisker", "Cyl", V(0.5, 0.03, 0.03), facing(wp + wn * 0.03, wn) * CFrame.Angles(0, 0, sx * a), RGB(90, 90, 100))
			end
		end
		windKey(b, c, RGB(255, 205, 80))
		local tp = surf(c.B, c.BS, V(0, -0.5, 1))
		H.link(b, "Tail", tp, tp + V(0.3, 0.3, 0.7), 0.1, RGB(255, 180, 190))
		H.link(b, "Tail", tp + V(0.3, 0.3, 0.7), tp + V(0.1, 0.7, 1.0), 0.09, RGB(255, 180, 190))
	end

	-- 블록 강아지: 장난감 블록으로 만든 파란 강아지 (네모 몸·머리, 위에 동그란 돌기)
	PET_BUILDERS.BlockPuppy = function(b)
		local BL = RGB(90, 170, 255)
		local YE = RGB(255, 210, 60)
		local B = V(0, 0.95, 0.2)
		addPart(b, "Body", "Block", V(1.4, 1.0, 1.7), CFrame.new(B), BL)
		local HC = V(0, 1.95, -0.45)
		addPart(b, "Head", "Block", V(1.5, 1.2, 1.2), CFrame.new(HC), BL)
		local HS = V(0.75, 0.6, 0.6)
		for _, sx in SIDES do
			Kit.addEye(b, HC, HS, sx * 0.34, 0.1, V(0.3, 0.38, 0.12), 0)
			ell(b, "Blush", V(0.26, 0.13, 0.05), CFrame.new(HC + V(sx * 0.52, -0.18, -0.61)), Kit.BLUSH, nil, 0.1)
			addPart(b, "Ear", "Block", V(0.3, 0.7, 0.5), CFrame.new(HC + V(sx * 0.85, 0.05, 0.1)), YE)
			for _, sz in { -1, 1 } do
				addPart(b, "Leg", "Block", V(0.45, 0.5, 0.45), CFrame.new(sx * 0.42, 0.25, B.Z + sz * 0.55), YE)
			end
			for _, sz in { -1, 1 } do
				addPart(b, "Stud", "Cyl", V(0.16, 0.36, 0.36), CFrame.new(HC + V(sx * 0.35, 0.68, sz * 0.3)) * CFrame.Angles(0, 0, math.pi / 2), BL)
				addPart(b, "Stud", "Cyl", V(0.16, 0.36, 0.36), CFrame.new(B + V(sx * 0.35, 0.58, sz * 0.45 + 0.2)) * CFrame.Angles(0, 0, math.pi / 2), BL)
			end
		end
		addPart(b, "Muzzle", "Block", V(0.7, 0.4, 0.3), CFrame.new(HC + V(0, -0.3, -0.7)), RGB(240, 245, 255))
		addPart(b, "Nose", "Block", V(0.26, 0.18, 0.12), CFrame.new(HC + V(0, -0.2, -0.88)), RGB(40, 40, 50))
		ell(b, "Mouth", V(0.16, 0.06, 0.05), CFrame.new(HC + V(0, -0.38, -0.86)), MOUTH)
		addPart(b, "Tail", "Block", V(0.3, 0.7, 0.3), CFrame.new(B + V(0, 0.6, 0.9)) * CFrame.Angles(-0.4, 0, 0), RGB(255, 90, 90))
	end

	-- 풍선 강아지: 분홍 풍선을 꼬아 만든 강아지 (긴 풍선 마디들), 반짝 광택
	PET_BUILDERS.BalloonDog = function(b)
		local P = RGB(255, 110, 160)
		local function seg(name, p0, p1, w)
			local part = H.link(b, name, p0, p1, w, P)
			part.Reflectance = 0.2
			return part
		end
		local body = seg("Body", V(0, 1.3, -0.45), V(0, 1.3, 0.75), 0.75)
		body.Name = "Body"
		local HC = V(0, 2.3, -0.7)
		local head = ell(b, "Head", V(1.2, 1.1, 1.1), CFrame.new(HC), P)
		head.Reflectance = 0.2
		seg("Neck", V(0, 1.45, -0.55), HC + V(0, -0.35, 0.05), 0.5)
		seg("Muzzle", HC + V(0, -0.1, -0.35), HC + V(0, -0.15, -1.0), 0.5)
		for _, sx in SIDES do
			seg("Leg", V(sx * 0.3, 1.2, -0.4), V(sx * 0.45, 0.2, -0.45), 0.42)
			seg("Leg", V(sx * 0.3, 1.2, 0.7), V(sx * 0.45, 0.2, 0.75), 0.42)
			seg("Ear", HC + V(sx * 0.25, 0.35, 0.1), HC + V(sx * 0.5, 0.95, 0.25), 0.36)
			Kit.addEye(b, HC, V(0.6, 0.55, 0.55), sx * 0.24, 0.12, V(0.24, 0.32, 0.12), 0)
			local p, n = front(HC, V(0.6, 0.55, 0.55), sx * 0.4, -0.12)
			ell(b, "Blush", V(0.2, 0.11, 0.05), facing(p, n), RGB(255, 200, 220), nil, 0.1)
		end
		ell(b, "Nose", V(0.2, 0.16, 0.12), CFrame.new(HC + V(0, -0.12, -1.2)), RGB(230, 70, 120))
		seg("Tail", V(0, 1.45, 0.95), V(0, 2.05, 1.25), 0.36)
		ell(b, "Shine", V(0.18, 0.4, 0.06), CFrame.new(V(0.25, 1.62, -0.1)) * CFrame.Angles(0, 0.5, 0.3), WHITE, NEON, 0.3)
		ell(b, "Knot", V(0.2, 0.2, 0.2), CFrame.new(0, 2.32, 1.3), darker(P, 0.2))
	end

	-- 흔들 목마: 나무 말 + 바닥의 휜 흔들 받침, 털실 갈기, 빨간 안장
	PET_BUILDERS.RockingHorse = function(b)
		local RD = RGB(240, 120, 90)
		local WD = RGB(200, 150, 100)
		-- 흔들 받침 (얇고 긴 휜 판 2개)
		for _, sx in SIDES do
			ell(b, "Rocker", V(0.16, 0.5, 2.9), CFrame.new(sx * 0.5, 0.25, 0.2), WD, WOOD)
		end
		local c = H.quad(b, { body = RD, legs = WD, feet = WD, legH = 0.7, legW = 0.3, BS = V(0.7, 0.55, 1.05), HS = V(0.6, 0.6, 0.72), headAt = V(0, 2.5, -1.0), eyeX = 0.28, eyeSize = V(0.24, 0.34, 0.12) })
		H.link(b, "Neck", c.B + V(0, 0.25, -0.7), c.H + V(0, -0.25, 0.25), 0.55, RD)
		H.snout(b, c, RGB(255, 200, 170), V(0.55, 0.45, 0.6), -0.3)
		for _, sx in SIDES do
			local ep = surf(c.H, c.HS, V(sx * 0.5, 1, 0.2))
			ell(b, "Ear", V(0.18, 0.4, 0.14), CFrame.new(ep + V(0, 0.12, 0)) * CFrame.Angles(0, 0, -sx * 0.2), RD)
			addPart(b, "Handle", "Cyl", V(0.5, 0.1, 0.1), CFrame.new(c.H + V(sx * 0.6, -0.1, 0.1)), WD, WOOD)
		end
		-- 털실 갈기 (목 뒤 공 줄)
		for i = 0, 4 do
			local p = c.H + V(0, 0.45 - i * 0.3, 0.45 + i * 0.12)
			ell(b, "Mane", V(0.3, 0.3, 0.3), CFrame.new(p), RGB(255, 225, 100))
		end
		ell(b, "Saddle", V(1.5, 0.3, 0.95), CFrame.new(c.B + V(0, c.BS.Y * 0.88, 0)), RGB(60, 120, 220))
		local tp = surf(c.B, c.BS, V(0, 0.2, 1))
		H.link(b, "Tail", tp, tp + V(0, -0.5, 0.45), 0.28, RGB(255, 225, 100))
	end

	-- 오르골 냥이: 분홍 고양이가 금 테두리 오르골 위에 앉아요, 태엽 열쇠, 반짝이는 음표
	PET_BUILDERS.MusicBoxCat = function(b)
		local P = RGB(255, 200, 230)
		local GOLD = RGB(255, 210, 90)
		-- 오르골 상자
		addPart(b, "Box", "Block", V(1.9, 0.6, 1.6), CFrame.new(0, 0.3, 0.1), RGB(140, 200, 240))
		addPart(b, "BoxTrim", "Block", V(2.0, 0.12, 1.7), CFrame.new(0, 0.62, 0.1), GOLD, METAL)
		addPart(b, "BoxKey", "Cyl", V(0.4, 0.1, 0.1), CFrame.new(1.15, 0.3, 0.1), GOLD, METAL)
		addPart(b, "BoxKey", "Block", V(0.06, 0.36, 0.2), CFrame.new(1.35, 0.3, 0.1), GOLD, METAL)
		-- 고양이 (상자 위)
		local c = chibi(b, { body = P, belly = WHITE, eyeY = 0.04, BS = V(0.75, 0.62, 0.68), HS = V(0.92, 0.86, 0.86) })
		for _, p in b.parts do
			if p.Name ~= "Box" and p.Name ~= "BoxTrim" and p.Name ~= "BoxKey" then
				p.CFrame = p.CFrame + V(0, 0.62, 0)
			end
		end
		c.B += V(0, 0.62, 0)
		c.H += V(0, 0.62, 0)
		c.FC = c.H
		pointyEars(c, 0.55, 0.85, 0.55, 0.65, 0.14, 0.25, P, RGB(255, 160, 200))
		H.lashes(b, c.eyes)
		smallNose(c, -0.2, V(0.14, 0.1, 0.08), RGB(255, 120, 160), 0.02)
		ell(b, "Bow", V(0.4, 0.3, 0.14), CFrame.new(surf(c.H, c.HS, V(0.6, 0.75, -0.1)) + V(0, 0.05, 0)) * CFrame.Angles(0, 0, -0.3), RGB(255, 120, 170))
		H.tail(b, c, P, { w = 0.26, d1 = V(0.6, 0.3, 1), d2 = V(0.5, 1, 0.2) })
		-- 음표 2개
		for i, o in { V(1.3, 2.6, -0.1), V(-1.25, 2.95, 0.1) } do
			ell(b, "Note", V(0.24, 0.2, 0.08), CFrame.new(o) * CFrame.Angles(0, 0, 0.4), RGB(150, 120, 255), if i == 1 then NEON else nil)
			addPart(b, "Note", "Block", V(0.05, 0.42, 0.05), CFrame.new(o + V(0.1, 0.22, 0)), RGB(150, 120, 255))
		end
	end

	-- 장난감 왕 (시크릿): 빨간 제복 장난감 병정 왕, 금 단추, 망토, 큰 왕관, 홀
	PET_BUILDERS.ToyKing = function(b)
		local RD = RGB(230, 60, 70)
		local GOLD = RGB(255, 205, 70)
		local SKIN = RGB(255, 225, 200)
		local c = chibi(b, { body = RD, head = SKIN, belly = nil, feet = RGB(40, 40, 50), arms = RD, eyeY = 0.0, BS = V(0.85, 0.85, 0.75) })
		for i, y in { 0.35, 0.0, -0.35 } do
			local p, n = front(c.B, c.BS, 0, y)
			ell(b, "Button", V(0.16, 0.16, 0.08), facing(p + n * 0.02, n), GOLD, METAL)
			if i == 1 then
				for _, sx in SIDES do
					local sp = surf(c.B, c.BS, V(sx, 0.7, 0))
					addPart(b, "Epaulet", "Cyl", V(0.14, 0.55, 0.55), CFrame.new(sp + V(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
				end
			end
		end
		addPart(b, "Belt", "Cyl", V(0.18, 1.72, 1.52), CFrame.new(c.B + V(0, -0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), WHITE)
		-- 콧수염
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.17, -0.3)
			ell(b, "Mustache", V(0.36, 0.14, 0.1), facing(p + n * 0.03, n) * CFrame.Angles(0, 0, sx * 0.25), RGB(110, 70, 45))
		end
		-- 망토 (뒤)
		ell(b, "Cape", V(1.9, 1.9, 0.3), CFrame.new(c.B + V(0, 0.2, c.BS.Z + 0.05)) * CFrame.Angles(0.15, 0, 0), RGB(120, 60, 200))
		addPart(b, "CapeTrim", "Cyl", V(0.24, 1.75, 0.6), CFrame.new(c.B + V(0, c.BS.Y * 0.95, 0.35)) * CFrame.Angles(0, 0, math.pi / 2), WHITE)
		H.crown(b, H.top(c, 0.82), 0.52, GOLD, RGB(80, 160, 255), METAL)
		-- 홀 (오른손)
		local hp = surf(c.B, c.BS, V(1, -0.05, -0.45))
		H.rod(b, "Scepter", hp + V(0.15, -0.5, -0.1), hp + V(0.2, 0.9, -0.25), 0.1, GOLD, METAL)
		ell(b, "ScepterGem", V(0.3, 0.3, 0.3), CFrame.new(hp + V(0.21, 1.0, -0.26)), RGB(255, 80, 120), NEON)
		H.glow(H.part(b, "Body"), RGB(255, 200, 120), 0.2, 4)
	end

	-- 태엽 여우 (시크릿 알): 구리빛 기계 여우, 옆구리의 돌아가는 톱니바퀴, 등 태엽, 은은한 눈빛
	PET_BUILDERS.ClockworkFox = function(b)
		local CU = RGB(230, 170, 80)
		local BR = RGB(180, 110, 60)
		local c = foxBase(b, CU, RGB(255, 230, 190), { feet = BR, arms = BR, earIn = RGB(255, 210, 150) })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Head" or p.Name == "Ear" then
				p.Material = METAL
			end
		end
		local mp, mn = front(c.H, c.HS, 0, -0.42)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), MOUTH)
		for _, sx in SIDES do
			local p, n = surf(c.B, c.BS, V(sx, 0.15, 0.2))
			gear(b, p + n * 0.02, n, 0.32, if sx > 0 then RGB(255, 205, 90) else RGB(210, 150, 70))
		end
		windKey(b, c, RGB(255, 215, 110))
		-- 기계 꼬리 (마디 3개 + 끝 톱니)
		local tp = surf(c.B, c.BS, V(0, -0.3, 1))
		local p1 = tp + V(0.15, 0.35, 0.45)
		local p2 = p1 + V(0.1, 0.5, 0.15)
		H.link(b, "Tail", tp, p1, 0.45, CU)
		H.link(b, "Tail", p1, p2, 0.4, BR)
		gear(b, p2 + V(0, 0.15, 0), V(0, 0, 1), 0.28, RGB(255, 205, 90))
		local fp, fn = front(c.H, c.HS, 0, 0.55)
		ell(b, "Gem", V(0.22, 0.22, 0.08), facing(fp + fn * 0.02, fn), RGB(120, 230, 255), NEON)
		H.glow(H.part(b, "Body"), RGB(255, 200, 120), 0.2, 4)
	end

	-- 회전목마 유니콘 (천상): 하얀 유니콘, 몸을 꿰뚫는 금 기둥, 파스텔 갈기, 금 안장, 반짝 뿔
	PET_BUILDERS.CarouselUnicorn = function(b)
		local W = RGB(255, 245, 250)
		local GOLD = RGB(255, 210, 90)
		local MANE = { RGB(255, 180, 210), RGB(190, 180, 255), RGB(170, 230, 255), RGB(255, 235, 160) }
		local c = H.quad(b, { body = W, legs = W, feet = GOLD, legH = 0.7, legW = 0.32, BS = V(0.7, 0.58, 1.05), HS = V(0.62, 0.6, 0.7), headAt = V(0, 2.55, -1.0), eyeX = 0.28, eyeSize = V(0.26, 0.36, 0.13) })
		H.link(b, "Neck", c.B + V(0, 0.25, -0.7), c.H + V(0, -0.25, 0.25), 0.55, W)
		H.lashes(b, c.eyes, 0.8)
		H.snout(b, c, RGB(255, 225, 235), V(0.55, 0.45, 0.6), -0.3)
		local hp = surf(c.H, c.HS, V(0, 1, -0.4))
		ell(b, "Horn", V(0.18, 0.8, 0.18), alongY(hp + V(0, 0.3, -0.12), V(0, 1, -0.35)), GOLD, NEON)
		for _, sx in SIDES do
			local ep = surf(c.H, c.HS, V(sx * 0.5, 1, 0.2))
			ell(b, "Ear", V(0.18, 0.4, 0.14), CFrame.new(ep + V(0, 0.12, 0)) * CFrame.Angles(0, 0, -sx * 0.2), W)
		end
		for i = 0, 5 do
			local p = c.H + V(0, 0.5 - i * 0.3, 0.42 + i * 0.12)
			ell(b, "Mane", V(0.36, 0.36, 0.36), CFrame.new(p), MANE[i % 4 + 1])
		end
		ell(b, "Saddle", V(1.5, 0.3, 0.95), CFrame.new(c.B + V(0, c.BS.Y * 0.88, 0)), RGB(255, 150, 190))
		addPart(b, "SaddleTrim", "Cyl", V(0.1, 1.55, 1.0), CFrame.new(c.B + V(0, c.BS.Y * 0.8, 0)) * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
		-- 금 기둥 (위로만, 몸 등 위에서 솟아요) + 꼭대기 공
		H.rod(b, "Pole", c.B + V(0, 0.2, 0), c.B + V(0, 2.4, 0), 0.14, GOLD, METAL)
		ell(b, "PoleTop", V(0.3, 0.3, 0.3), CFrame.new(c.B + V(0, 2.45, 0)), RGB(255, 180, 220), NEON)
		local tp = surf(c.B, c.BS, V(0, 0.2, 1))
		for i, col in MANE do
			H.link(b, "Tail", tp + V((i - 2.5) * 0.08, 0, 0), tp + V((i - 2.5) * 0.15, -0.55, 0.45), 0.18, col)
		end
		H.glow(H.part(b, "Body"), RGB(255, 220, 240), 0.3, 4.5)
	end

	-- 메카 용 (이터널): 파란 금속 로봇 용, 노란 줄무늬 갑판, 가슴 반응로, 등 제트 엔진, 금속 날개
	PET_BUILDERS.MechaDragon = function(b)
		local BL = RGB(120, 160, 220)
		local DK = RGB(70, 85, 120)
		local YE = RGB(255, 210, 60)
		local c = chibi(b, { body = BL, belly = RGB(200, 215, 235), feet = DK, arms = DK, eyeY = 0.04, BS = V(0.95, 0.8, 0.85), HS = V(1.08, 0.98, 0.98) })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Head" or p.Name == "Foot" or p.Name == "Arm" then
				p.Material = METAL
			end
		end
		-- 머리 볏 판 + 뿔 안테나
		addPart(b, "Plate", "Block", V(0.2, 0.4, 1.4), CFrame.new(H.top(c, 0.92) + V(0, 0.05, 0.1)), YE, METAL)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.5, 0.9, 0.15))
			H.rod(b, "Horn", p, p + V(sx * 0.25, 0.55, 0.3), 0.14, DK, METAL)
			ell(b, "HornTip", V(0.14, 0.14, 0.14), CFrame.new(p + V(sx * 0.28, 0.6, 0.33)), RGB(120, 230, 255), NEON)
			-- 금속 날개 (각진 판 2장)
			local base = c.B + V(sx * 0.32, 0.5, 0.55)
			tri(b, "Wing", frameUp(base, V(sx, 0.8, 0.5), Vector3.zAxis), 0.95, 1.4, 0.1, RGB(170, 190, 220), METAL)
			tri(b, "Wing", frameUp(base + V(0, -0.1, 0.1), V(sx, 0.25, 0.65), Vector3.zAxis), 0.7, 1.0, 0.1, YE, METAL)
			-- 얼굴 옆 볼트
			local bp, bn = surf(c.H, c.HS, V(sx, 0, 0))
			addPart(b, "Bolt", "Cyl", V(0.12, 0.26, 0.26), H.along(bp + bn * 0.03, bn) * CFrame.Angles(0, -math.pi / 2, 0), DK, METAL)
		end
		-- 가슴 반응로
		local gp, gn = front(c.BeC, c.BeS, 0, 0.2)
		addPart(b, "Reactor", "Cyl", V(0.1, 0.55, 0.55), H.along(gp + gn * 0.03, gn) * CFrame.Angles(0, -math.pi / 2, 0), DK, METAL)
		ell(b, "Core", V(0.36, 0.36, 0.1), facing(gp + gn * 0.1, gn), RGB(120, 230, 255), NEON)
		-- 등 제트 2개 (아래로 불꽃)
		for _, sx in SIDES do
			local jp = c.B + V(sx * 0.35, 0.3, c.BS.Z + 0.1)
			addPart(b, "Jet", "Cyl", V(0.7, 0.36, 0.36), CFrame.new(jp) * CFrame.Angles(0, 0, math.pi / 2), DK, METAL)
			ell(b, "JetFire", V(0.26, 0.4, 0.26), CFrame.new(jp + V(0, -0.5, 0)), RGB(120, 230, 255), NEON, 0.2)
		end
		for _, y in { 0.45, 0.0 } do
			H.patch(b, "Stripe", c.B, c.BS, V(0.75, y, -0.4), 0.18, 0.5, YE)
			H.patch(b, "Stripe", c.B, c.BS, V(-0.75, y, -0.4), 0.18, 0.5, YE)
		end
		local tip, d = H.tail(b, c, BL)
		tri(b, "TailFin", CFrame.fromMatrix(tip, Vector3.xAxis, d), 0.5, 0.5, 0.1, YE, METAL)
		H.glow(H.part(b, "Body"), RGB(140, 220, 255), 0.45, 6)
	end

	----------------------------------------------------------------------
	-- 14 꿈나라
	----------------------------------------------------------------------

	-- 졸린 양: 몽글몽글 하얀 털, 졸린 눈, 하늘색 수면 모자
	PET_BUILDERS.SleepySheep = function(b)
		local W = RGB(240, 235, 255)
		local FACE = RGB(255, 225, 215)
		local c = chibi(b, { body = W, head = W, feet = RGB(120, 110, 140), arms = W, noEyes = true, face = { color = FACE, semi = V(0.72, 0.62, 0.55), offset = V(0, -0.15, -0.45) }, blushX = 0.45, blushY = -0.2, mouthY = -0.32 })
		H.sleepyEyes(b, c, 0.28, 0.02)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx, 0.2, 0))
			ell(b, "Ear", V(0.5, 0.24, 0.3), CFrame.new(p + V(sx * 0.1, -0.05, 0)) * CFrame.Angles(0, 0, sx * 0.4), FACE)
		end
		-- 털 뭉치 (몸 둘레)
		for _, d in { V(0.8, 0.4, 0.3), V(-0.8, 0.4, 0.3), V(0.6, -0.2, 0.7), V(-0.6, -0.2, 0.7), V(0, 0.6, 0.8), V(0, 0.1, 1), V(0.85, 0, -0.3), V(-0.85, 0, -0.3) } do
			local p = surf(c.B, c.BS, d)
			ell(b, "Wool", V(0.62, 0.62, 0.62), CFrame.new(p), W)
		end
		nightcap(b, c, RGB(160, 190, 255))
	end

	-- 잠꾸러기 햄스터: 동그랗게 웅크린 햄스터, 감은 눈, 코에서 부푼 콧방울
	PET_BUILDERS.SnoozeHamster = function(b)
		local F = RGB(230, 200, 170)
		local c = chibi(b, { body = F, belly = RGB(255, 245, 230), noEyes = true, BS = V(0.95, 0.75, 0.85), noMouth = true })
		H.sleepyEyes(b, c, 0.36, 0.0)
		roundEars(c, 0.6, 0.72, 0.4, F, RGB(255, 190, 190))
		smallNose(c, -0.2, V(0.14, 0.1, 0.08), RGB(255, 150, 160), 0.02)
		local np, nn = front(c.H, c.HS, 0.15, -0.22)
		ell(b, "Bubble", V(0.45, 0.45, 0.45), CFrame.new(np + nn * 0.25 + V(0.15, 0, 0)), RGB(210, 235, 255), GLASS, 0.4)
		ell(b, "Blanket", V(1.95, 0.7, 1.7), CFrame.new(c.B + V(0, -0.15, 0.1)), RGB(160, 150, 240))
		H.patch(b, "Blanket", c.B + V(0, -0.15, 0.1), V(0.98, 0.35, 0.85), V(0.4, 0.8, -0.4), 0.3, 0.3, RGB(255, 230, 120))
		zzz(b, c)
	end

	-- 베개 냥이: 푹신한 베개에 엎드린 하늘색 고양이, 졸린 눈
	PET_BUILDERS.PillowCat = function(b)
		local C = RGB(200, 205, 255)
		addPart(b, "Pillow", "Block", V(2.2, 0.45, 1.8), CFrame.new(0, 0.22, 0.05), WHITE)
		for _, sx in SIDES do
			for _, sz in { -1, 1 } do
				ell(b, "Pillow", V(0.45, 0.45, 0.45), CFrame.new(sx * 1.05, 0.22, 0.05 + sz * 0.85), WHITE)
			end
		end
		ell(b, "PillowDot", V(0.9, 0.08, 0.6), CFrame.new(0, 0.46, 0.3), RGB(255, 225, 240))
		local c = chibi(b, { body = C, belly = WHITE, eyeY = 0.04, noEyes = true, BS = V(0.85, 0.6, 0.85), HS = V(0.95, 0.88, 0.88) })
		for _, p in b.parts do
			if p.Name ~= "Pillow" and p.Name ~= "PillowDot" then
				p.CFrame = p.CFrame + V(0, 0.42, 0)
			end
		end
		c.B += V(0, 0.42, 0)
		c.H += V(0, 0.42, 0)
		c.FC = c.H
		H.sleepyEyes(b, c, 0.34, 0.0)
		pointyEars(c, 0.55, 0.85, 0.55, 0.62, 0.14, 0.3, C, RGB(255, 190, 220))
		smallNose(c, -0.18, V(0.14, 0.1, 0.08), RGB(255, 150, 180), 0.02)
		H.tail(b, c, C, { w = 0.26, from = -0.3, d1 = V(0.6, -0.2, 1), d2 = V(1, 0.1, 0.2) })
	end

	-- 반딧불이: 둥근 꼬마 벌레, 엉덩이에 노랗게 빛나는 등불, 반투명 날개
	PET_BUILDERS.Firefly = function(b)
		local BK = RGB(70, 75, 110)
		local c = chibi(b, { body = BK, head = RGB(95, 100, 140), belly = RGB(120, 125, 160), eyeY = 0.04, BS = V(0.75, 0.7, 0.75) })
		local lp = surf(c.B, c.BS, V(0, -0.3, 1))
		local lamp = ell(b, "Lantern", V(1.0, 0.95, 1.05), CFrame.new(lp + V(0, 0.05, 0.25)), RGB(220, 255, 120), NEON)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.35, 1, -0.1))
			local q = p + V(sx * 0.3, 0.55, -0.1)
			H.rod(b, "Antenna", p, q, 0.06, BK)
			ell(b, "AntennaTip", V(0.16, 0.16, 0.16), CFrame.new(q), RGB(220, 255, 120))
			local root = surf(c.B, c.BS, V(sx * 0.4, 0.6, 0.8))
			for _, w in H.featherWing(b, root, sx, { { 40, 1.0, 0.5, RGB(220, 235, 255) } }, 0.45, 0.2, 0.05) do
				w.Transparency = 0.35
			end
		end
		H.glow(lamp, RGB(220, 255, 120), 0.3, 5)
	end

	-- 달곰: 남색 곰, 가슴의 하얀 초승달 무늬, 별 볼터치
	PET_BUILDERS.MoonBear = function(b)
		local N = RGB(90, 90, 140)
		local c = chibi(b, { body = N, feet = darker(N, 0.15), eyeY = 0.06, noMouth = true })
		roundEars(c, 0.62, 0.72, 0.46, N, RGB(150, 150, 200))
		muzzle(c, V(0.6, 0.42, 0.4), RGB(200, 200, 230), RGB(40, 40, 60), -0.28)
		-- 초승달 (큰 하얀 원 + 남색 원으로 가려서)
		local p, n = front(c.B, c.BS, 0, 0.3)
		ell(b, "Moon", V(0.7, 0.7, 0.08), facing(p + n * 0.02, n), RGB(255, 250, 220))
		ell(b, "MoonCut", V(0.62, 0.62, 0.09), facing(p + n * 0.035, n) * CFrame.new(0.18, 0.1, 0), N)
		for _, sx in SIDES do
			local sp, sn = front(c.H, c.HS, sx * 0.7, -0.22)
			star(b, "Star", sp + sn * 0.03, sn, 0.22, RGB(255, 230, 130))
		end
	end

	-- 꿈먹는 맥: 앞은 보라 뒤는 하얀 맥, 짧은 코, 몸에 별 무늬
	PET_BUILDERS.Baku = function(b)
		local P = RGB(180, 160, 230)
		local c = H.quad(b, { body = P, belly = RGB(235, 230, 255), legs = darker(P, 0.2), BS = V(0.8, 0.65, 1.1), HS = V(0.75, 0.7, 0.72), eyeX = 0.3, eyeSize = V(0.28, 0.38, 0.13) })
		ell(b, "Saddle", V(1.75, 1.42, 1.3), CFrame.new(c.B + V(0, 0.03, 0.45)), RGB(250, 248, 255))
		-- 짧은 코 (앞으로 처진)
		local np, nn = front(c.H, c.HS, 0, -0.25)
		H.link(b, "Trunk", np - nn * 0.1, np + nn * 0.35 + V(0, -0.2, 0), 0.38, P)
		for _, sx in SIDES do
			local ep = surf(c.H, c.HS, V(sx * 0.7, 0.8, 0.1))
			ell(b, "Ear", V(0.32, 0.36, 0.14), CFrame.new(ep), P)
		end
		local mp, mn = front(c.H, c.HS, 0, -0.5)
		ell(b, "Mouth", V(0.14, 0.06, 0.05), facing(mp, mn), MOUTH)
		for _, d in { V(0.5, 0.8, -0.3), V(-0.6, 0.6, -0.5) } do
			local p, n = surf(c.B, c.BS, d)
			star(b, "Star", p + n * 0.03, n, 0.26, RGB(255, 230, 130))
		end
		local tp = surf(c.B, c.BS, V(0, 0.2, 1))
		ell(b, "Tail", V(0.2, 0.2, 0.36), CFrame.new(tp + V(0, 0, 0.1)), RGB(250, 248, 255))
	end

	-- 꿈 요정 강아지: 하늘색 강아지, 별 무늬 수면 모자, 별 지팡이, 반짝 모래 주머니
	PET_BUILDERS.SandmanPup = function(b)
		local B = RGB(150, 170, 255)
		local c = chibi(b, { body = B, belly = WHITE, feet = darker(B, 0.2), eyeY = 0.06, noMouth = true })
		muzzle(c, V(0.55, 0.4, 0.4), RGB(230, 235, 255), RGB(50, 50, 80), -0.3)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx, 0.35, 0))
			ell(b, "Ear", V(0.32, 0.75, 0.22), CFrame.new(p + V(sx * 0.06, -0.25, 0)) * CFrame.Angles(0, 0, sx * 0.2), darker(B, 0.15))
		end
		nightcap(b, c, RGB(90, 80, 180), RGB(255, 225, 120))
		-- 별 지팡이
		local hp = surf(c.B, c.BS, V(1, -0.05, -0.45))
		H.rod(b, "Wand", hp + V(0.1, -0.2, -0.05), hp + V(0.25, 0.9, -0.3), 0.08, RGB(255, 245, 230))
		star(b, "WandStar", hp + V(0.27, 1.05, -0.33), V(0, 0, -1), 0.4, RGB(255, 225, 100), NEON)
		-- 모래 주머니 (옆구리)
		local sp = surf(c.B, c.BS, V(-1, -0.3, 0))
		ell(b, "Pouch", V(0.5, 0.55, 0.45), CFrame.new(sp + V(-0.15, 0, 0)), RGB(255, 225, 160))
		ell(b, "Sparkle", V(0.12, 0.12, 0.12), CFrame.new(sp + V(-0.15, 0.35, 0)), RGB(255, 245, 200), NEON)
		H.tail(b, c, B, { w = 0.3, d1 = V(0, 0.6, 1), d2 = V(0, 1, 0.3) })
	end

	-- 별빛 사자 (시크릿): 크림 사자, 밤하늘 갈기에 박힌 별, 꼬리 끝 별
	PET_BUILDERS.StarlightLion = function(b)
		local Y = RGB(255, 230, 150)
		local NAVY = RGB(70, 70, 150)
		local c = chibi(b, { body = Y, belly = RGB(255, 245, 215), eyeY = 0.04, noMouth = true })
		H.mane(b, c, NAVY, 11, 0.7, RGB(110, 100, 190))
		roundEars(c, 0.6, 0.75, 0.42, Y, RGB(255, 200, 170))
		muzzle(c, V(0.6, 0.42, 0.4), RGB(255, 245, 220), RGB(120, 70, 60), -0.3)
		for i, d in { V(0.75, 0.55, 0.4), V(-0.7, 0.7, 0.45), V(0, 1, 0.5), V(0.95, -0.1, 0.4), V(-0.95, 0, 0.35) } do
			local p, n = surf(c.H, c.HS * 1.2, d)
			star(b, "ManeStar", p + n * 0.05, n, 0.3, RGB(255, 240, 150), if i <= 2 then NEON else nil, true)
		end
		local tip, d = H.tail(b, c, Y, { w = 0.28, d1 = V(0, 0.4, 1), d2 = V(0, 1, 0.3), l2 = 0.8 })
		star(b, "TailStar", tip + d * 0.1, V(0, 0, 1), 0.36, RGB(255, 230, 120), NEON)
		H.glow(H.part(b, "Body"), RGB(200, 200, 255), 0.25, 4)
	end

	-- 낮잠 판다 (시크릿 알): 눈가리개를 쓴 판다, 대나무 베개를 꼭 안고, 쿨쿨
	PET_BUILDERS.SnoozePanda = function(b)
		local W = RGB(245, 245, 255)
		local K = RGB(45, 45, 55)
		local c = chibi(b, { body = W, feet = K, arms = K, noEyes = true, noMouth = true })
		roundEars(c, 0.62, 0.72, 0.46, K)
		muzzle(c, V(0.56, 0.38, 0.36), WHITE, K, -0.3)
		-- 수면 안대 (분홍 띠 + 눈 모양 그림)
		addPart(b, "Mask", "Cyl", V(0.38, 2.12, 2.0), CFrame.new(c.H + V(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2), RGB(255, 160, 200))
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.36, 0.05)
			addPart(b, "MaskEye", "Block", V(0.28, 0.05, 0.04), facing(p + n * 0.08, n) * CFrame.Angles(0, 0, sx * 0.12), K)
		end
		-- 대나무 베개 (가로로 안은 초록 원기둥 + 마디)
		local pc = c.BeC + V(0, 0.05, -0.55)
		addPart(b, "Bamboo", "Cyl", V(1.9, 0.5, 0.5), CFrame.new(pc), RGB(120, 200, 110))
		for _, x in { -0.5, 0.2 } do
			addPart(b, "BambooRing", "Cyl", V(0.08, 0.55, 0.55), CFrame.new(pc + V(x, 0, 0)), RGB(90, 160, 85))
		end
		ell(b, "Leaf", V(0.18, 0.5, 0.06), CFrame.new(pc + V(0.75, 0.35, 0)) * CFrame.Angles(0, 0, -0.5), RGB(120, 200, 110))
		zzz(b, c)
		H.glow(H.part(b, "Body"), RGB(220, 220, 255), 0.2, 4)
	end

	-- 초승달 여우 (천상): 크림빛 여우, 이마 초승달, 꼬리 3개 끝에 별, 머리 위에 떠 있는 작은 달
	PET_BUILDERS.CrescentFox = function(b)
		local C = RGB(255, 240, 180)
		local c = foxBase(b, C, WHITE, { feet = RGB(200, 180, 255), arms = RGB(200, 180, 255), earIn = RGB(200, 180, 255) })
		H.lashes(b, c.eyes)
		local mp, mn = front(c.H, c.HS, 0, -0.42)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), MOUTH)
		local fp, fn = front(c.H, c.HS, 0, 0.55)
		ell(b, "Moon", V(0.34, 0.34, 0.06), facing(fp + fn * 0.02, fn), RGB(200, 170, 255), NEON)
		ell(b, "MoonCut", V(0.3, 0.3, 0.07), facing(fp + fn * 0.035, fn) * CFrame.new(0.1, 0.06, 0), C)
		for i, a in { -0.5, 0, 0.5 } do
			local tp = surf(c.B, c.BS, V(0, -0.2, 1))
			local t1 = tp + V(a * 0.9, 0.55, 0.55)
			ell(b, "Tail", V(0.48, 0.48, 0.95), CFrame.lookAt((tp + t1) * 0.5 + V(0, 0.1, 0), t1), C)
			star(b, "TailStar", t1 + V(0, 0.15, 0), V(a, 0.3, 1), 0.3, RGB(200, 180, 255), if i == 2 then NEON else nil)
		end
		-- 떠 있는 달 (초승달 모양)
		local mc = c.H + V(1.2, 0.95, 0.1)
		ell(b, "FloatMoon", V(0.6, 0.6, 0.2), CFrame.new(mc), RGB(255, 245, 190), NEON)
		ell(b, "FloatMoonCut", V(0.52, 0.52, 0.22), CFrame.new(mc + V(0.17, 0.1, 0)), C, nil, 0.85)
		H.glow(H.part(b, "Body"), RGB(230, 210, 255), 0.3, 4.5)
	end

	-- 꿈의 용 (이터널): 라벤더 용, 구름 날개, 별 뿔, 꼬리 끝 초승달, 몸 주위를 도는 별
	PET_BUILDERS.DreamDragon = function(b)
		local L = RGB(160, 140, 255)
		local CL = RGB(245, 245, 255)
		local c = chibi(b, { body = L, belly = RGB(225, 215, 255), feet = darker(L, 0.15), eyeY = 0.04, BS = V(0.95, 0.8, 0.85), HS = V(1.08, 0.98, 0.98) })
		H.lashes(b, c.eyes)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.45, 1, 0.1))
			local q = p + V(sx * 0.2, 0.45, 0.2)
			H.rod(b, "Horn", p, q, 0.14, RGB(255, 240, 200))
			star(b, "HornStar", q + V(0, 0.1, 0), V(0, 0, -1), 0.3, RGB(255, 225, 120), NEON)
			-- 구름 날개 (뭉게구름 공 4개)
			local root = c.B + V(sx * 0.55, 0.55, 0.6)
			for i, o in { V(0.3, 0.2, 0), V(0.75, 0.55, 0.1), V(1.0, 0.1, 0.15), V(0.55, 0.85, 0.2) } do
				local r = if i == 2 then 0.75 else 0.58
				ell(b, "Wing", V(r, r * 0.85, r * 0.8), CFrame.new(root + V(sx * o.X, o.Y, o.Z)), CL)
			end
		end
		H.spikes(b, c, RGB(255, 210, 240), 0.9)
		local tip, d = H.tail(b, c, L)
		local mc = tip + d * 0.15
		ell(b, "TailMoon", V(0.5, 0.5, 0.14), CFrame.lookAt(mc, mc + V(1, 0, 0)), RGB(255, 245, 190), NEON)
		ell(b, "TailMoonCut", V(0.44, 0.44, 0.15), CFrame.lookAt(mc + V(0, 0.08, 0.12), mc + V(0, 0.08, 0.12) + V(1, 0, 0)), L)
		for i, o in { V(1.4, 2.7, -0.3), V(-1.5, 2.2, 0.2), V(0.5, 3.5, 0.6) } do
			star(b, "FloatStar", o, V(0, 0, -1), 0.4, RGB(255, 240, 160), if i == 1 then NEON else nil, true)
		end
		H.glow(H.part(b, "Body"), RGB(190, 170, 255), 0.45, 6)
	end
end
