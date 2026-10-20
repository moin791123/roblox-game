-- 우주 알 펫 모델 (PetModels/init.luau 가 불러서 등록)
-- 외계인 / 로봇 강아지 / 달토끼 / 우주 냥이 / 별 슬라임
return function(Kit, PET_BUILDERS, EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, addEye, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.addEye, Kit.chibi, Kit.SIDES
	local addPart, darker, alongY, smallNose, pointyEars = Kit.addPart, Kit.darker, Kit.alongY, Kit.smallNose, Kit.pointyEars
	local WHITE, BLUSH, MOUTH = Kit.WHITE, Kit.BLUSH, Kit.MOUTH
	local NEON = Enum.Material.Neon

	-- 기본 몸에서 바꿔 끼울 파트를 빌더 목록에서 빼고 지워요
	local function dropParts(b, name)
		for i = #b.parts, 1, -1 do
			local p = b.parts[i]
			if p.Name == name then
				table.remove(b.parts, i)
				p:Destroy()
			end
		end
	end

	-- 외계인: 민트색 큰 머리, 커다란 까만 눈, 네온 더듬이 2개, 작은 몸, 발밑 UFO 접시
	PET_BUILDERS.Alien = function(b)
		local G = RGB(150, 240, 170)
		local c = chibi(b, {
			body = G,
			belly = RGB(200, 250, 210),
			feet = darker(G, 0.15),
			BS = V(0.7, 0.6, 0.65),
			HS = V(1.2, 1.05, 1.0),
			eyeX = 0.48,
			eyeY = 0,
			eyeSize = V(0.58, 0.76, 0.2),
			eyeLift = 0.02,
			blushX = 0.95,
			blushY = -0.42,
			mouthY = -0.55,
		})
		for _, p in b.parts do
			if p.Name == "Eye" then
				p.Reflectance = 0.2 -- 반들반들한 눈
			end
		end
		-- 더듬이: 비스듬히 올라가는 줄기 + 네온 구슬
		for _, sx in SIDES do
			local d = V(sx * 0.35, 1, 0).Unit
			local p = surf(c.H, c.HS, V(sx * 0.4, 1, 0))
			ell(b, "Antenna", V(0.1, 0.62, 0.1), alongY(p + d * 0.24, d), darker(G, 0.1))
			ell(b, "AntennaTip", V(0.26, 0.26, 0.26), CFrame.new(p + d * 0.6), RGB(255, 120, 220), NEON)
		end
		-- UFO 접시 위에 서 있어요 (발을 접시 위로 올림)
		dropParts(b, "Foot")
		addPart(b, "Saucer", "Cyl", V(0.16, 2.4, 2.4), CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(205, 210, 225), Enum.Material.Metal)
		for i = 1, 4 do
			local a = (i - 0.5) * math.pi / 2
			ell(b, "Light", V(0.22, 0.1, 0.22), CFrame.new(math.cos(a), 0.18, math.sin(a)), RGB(120, 255, 240), NEON)
		end
		for _, sx in SIDES do
			ell(b, "Foot", V(0.5, 0.38, 0.6), CFrame.new(sx * 0.35, 0.35, -0.25), darker(G, 0.15))
		end
	end

	-- 로봇 강아지: 네모난 은색/파랑 금속 몸, 네온 눈 바이저, 안테나, 네모 귀, 패널 줄
	PET_BUILDERS.RobotPuppy = function(b)
		local SILVER = RGB(205, 212, 228)
		local BLUE = RGB(95, 150, 235)
		local DARK = RGB(60, 70, 95)
		local LINE = RGB(150, 160, 185)
		local CYAN = RGB(100, 240, 255)
		local M = Enum.Material.Metal
		local function blk(name, size, cf, col, mat)
			return addPart(b, name, "Block", size, cf, col, mat)
		end
		blk("Body", V(1.7, 1.3, 1.4), CFrame.new(0, 0.85, 0), SILVER, M)
		blk("Head", V(2.0, 1.6, 1.7), CFrame.new(0, 2.25, 0), SILVER, M)
		for _, sx in SIDES do
			blk("Foot", V(0.55, 0.3, 0.75), CFrame.new(sx * 0.5, 0.15, -0.3), DARK, M)
			blk("Arm", V(0.36, 0.62, 0.4), CFrame.new(sx * 0.95, 0.75, -0.35), BLUE, M)
			blk("Ear", V(0.5, 0.62, 0.36), CFrame.new(sx * 0.82, 3.2, 0) * CFrame.Angles(0, 0, -sx * 0.15), BLUE, M)
			addPart(b, "Bolt", "Cyl", V(0.08, 0.24, 0.24), CFrame.new(sx * 1.03, 2.6, 0.3), DARK, M)
		end
		-- 얼굴: 까만 바이저 + 네온 눈 2개 + 파란 주둥이 + 코 + 입 + 볼터치
		blk("Eye", V(1.5, 0.52, 0.12), CFrame.new(0, 2.42, -0.87), RGB(25, 30, 45))
		for _, sx in SIDES do
			blk("Eye", V(0.4, 0.28, 0.08), CFrame.new(sx * 0.42, 2.42, -0.95), CYAN, NEON)
			ell(b, "Blush", V(0.32, 0.17, 0.06), CFrame.new(sx * 0.72, 1.98, -0.87), BLUSH, nil, 0.1)
		end
		blk("Snout", V(0.9, 0.5, 0.5), CFrame.new(0, 1.85, -1.05), BLUE, M)
		blk("Nose", V(0.32, 0.2, 0.1), CFrame.new(0, 2.0, -1.33), DARK)
		blk("Mouth", V(0.42, 0.05, 0.04), CFrame.new(0, 1.72, -1.31), DARK)
		-- 안테나 + 빨간 네온 구슬
		addPart(b, "Antenna", "Cyl", V(0.5, 0.08, 0.08), CFrame.new(0.35, 3.3, 0.2) * CFrame.Angles(0, 0, math.pi / 2), DARK, M)
		ell(b, "AntennaTip", V(0.2, 0.2, 0.2), CFrame.new(0.35, 3.57, 0.2), RGB(255, 90, 120), NEON)
		-- 패널 줄 + 가슴 네온 램프
		blk("Line", V(1.0, 0.04, 0.05), CFrame.new(0, 1.15, -0.71), LINE)
		blk("Line", V(0.04, 0.5, 0.05), CFrame.new(-0.45, 0.6, -0.71), LINE)
		blk("Line", V(1.6, 0.04, 0.05), CFrame.new(0, 2.95, -0.86), LINE)
		blk("Line", V(1.1, 0.04, 0.05), CFrame.new(0, 1.0, 0.71), LINE)
		blk("Light", V(0.34, 0.34, 0.06), CFrame.new(0.15, 0.62, -0.72), CYAN, NEON)
		-- 비스듬히 선 네모 꼬리 + 네온 끝
		blk("Tail", V(0.16, 0.16, 0.65), CFrame.new(0, 1.35, 0.9) * CFrame.Angles(-0.7, 0, 0), BLUE, M)
		ell(b, "TailTip", V(0.22, 0.22, 0.22), CFrame.new(0, 1.6, 1.2), CYAN, NEON)
	end

	-- 달토끼: 연노랑 토끼, 이마에 네온 초승달, 별 반짝이, 작은 모찌를 안고 있어요
	PET_BUILDERS.MoonBunny = function(b)
		local Y = RGB(255, 246, 195)
		local P = RGB(255, 200, 215)
		local GLOW = RGB(255, 240, 150)
		local c = chibi(b, { body = Y, belly = RGB(255, 253, 235), feet = RGB(255, 235, 200), eyeY = 0.02, blushY = -0.3 })
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.38, 1, 0.05))
			local cf = CFrame.new(p) * CFrame.Angles(0, 0, -sx * 0.2) * CFrame.new(0, 0.5, 0)
			ell(b, "Ear", V(0.42, 1.2, 0.24), cf, Y)
			ell(b, "EarInner", V(0.22, 0.9, 0.08), cf * CFrame.new(0, 0.04, -0.09), P)
		end
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 150, 175), 0.02)
		-- 이마 초승달: 네온 원판 위에 머리색 원판을 살짝 비껴 덮어서 초승달 모양
		local mp, mn = front(c.H, c.HS, 0, 0.6)
		local mcf = facing(mp + mn * 0.01, mn)
		ell(b, "Moon", V(0.46, 0.46, 0.06), mcf, GLOW, NEON)
		ell(b, "MoonCut", V(0.4, 0.4, 0.07), mcf * CFrame.new(0.13, 0.07, -0.012), Y)
		-- 별 반짝이 (십자 네온 막대 2개)
		local function sparkle(cc, ss, dir, len, col)
			local p, n = surf(cc, ss, dir)
			local cf = facing(p + n * 0.02, n)
			addPart(b, "Sparkle", "Block", V(len, len * 0.22, 0.05), cf, col, NEON)
			addPart(b, "Sparkle", "Block", V(len * 0.22, len, 0.05), cf, col, NEON)
		end
		sparkle(c.H, c.HS, V(0.8, 0.35, -0.55), 0.34, GLOW)
		sparkle(c.BeC, c.BeS, V(0.5, 0.5, -0.7), 0.26, WHITE)
		-- 배 앞에 안고 있는 모찌 + 양손
		local mc = c.B + V(0, -0.12, -c.BS.Z - 0.18)
		ell(b, "Mochi", V(0.5, 0.36, 0.46), CFrame.new(mc), RGB(255, 252, 250))
		ell(b, "MochiDot", V(0.18, 0.1, 0.12), CFrame.new(mc + V(0, 0.16, -0.06)), RGB(255, 170, 200))
		for _, sx in SIDES do
			ell(b, "Paw", V(0.26, 0.22, 0.26), CFrame.new(mc + V(sx * 0.3, 0.05, -0.02)), Y)
		end
		local tp, tn = surf(c.B, c.BS, V(0, -0.1, 1))
		ell(b, "Tail", V(0.5, 0.5, 0.5), CFrame.new(tp + tn * 0.1), WHITE)
	end

	-- 우주 냥이: 진보라 고양이, 유리 헬멧 돔 + 금속 목 고리, 몸에 네온 별, 등에 제트팩
	PET_BUILDERS.SpaceCat = function(b)
		local PUR = RGB(120, 90, 200)
		local LIL = RGB(185, 165, 240)
		local METAL = RGB(215, 220, 235)
		local c = chibi(b, { body = PUR, belly = LIL, feet = LIL, eyeY = 0.05, noMouth = true, blushY = -0.22 })
		for _, p in b.parts do
			if p.Name == "Blush" then
				p.Transparency = 0 -- 유리 헬멧 뒤에서도 보이게
			end
		end
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.16, -0.33)
			ell(b, "Muzzle", V(0.42, 0.32, 0.28), facing(p - n * 0.06, n), LIL)
		end
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 140, 190), 0.04)
		pointyEars(c, 0.55, 0.85, 0.6, 0.62, 0.16, 0.3, PUR)
		-- 네온 별 점 (머리 옆, 몸 옆)
		local stars = { { c.H, c.HS, V(0.7, 0.5, -0.4) }, { c.H, c.HS, V(-0.6, 0.65, -0.3) }, { c.B, c.BS, V(0.9, 0.3, 0.3) } }
		for i, s in stars do
			local p, n = surf(s[1], s[2], s[3])
			ell(b, "Star", V(0.13, 0.13, 0.05), facing(p + n * 0.01, n), if i % 2 == 0 then WHITE else RGB(255, 240, 150), NEON)
		end
		-- 유리 헬멧 (귀까지 다 들어가는 크기) + 목 고리
		ell(b, "Helmet", V(3.0, 2.6, 2.9), CFrame.new(c.H + V(0, 0.3, 0)), RGB(200, 230, 255), Enum.Material.Glass, 0.5)
		addPart(b, "Collar", "Cyl", V(0.22, 2.0, 2.0), CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2), METAL, Enum.Material.Metal)
		-- 제트팩: 등에 상자 + 분사구 2개 + 네온 불꽃
		local jc = V(0, 1.1, c.BS.Z + 0.1)
		addPart(b, "Jetpack", "Block", V(0.8, 0.85, 0.42), CFrame.new(jc), METAL, Enum.Material.Metal)
		for _, sx in SIDES do
			addPart(b, "Nozzle", "Cyl", V(0.3, 0.3, 0.3), CFrame.new(jc + V(sx * 0.22, -0.55, 0)) * CFrame.Angles(0, 0, math.pi / 2), RGB(110, 115, 135), Enum.Material.Metal)
			ell(b, "Flame", V(0.2, 0.34, 0.2), CFrame.new(jc + V(sx * 0.22, -0.82, 0)), RGB(255, 160, 60), NEON)
		end
		-- 꼬리 (제트팩 옆으로 비켜서 위로)
		local tp = surf(c.B, c.BS, V(0.6, -0.35, 0.9))
		local t1 = tp + V(0.1, 0.05, 0.28)
		ell(b, "Tail", V(0.28, 0.28, 0.7), CFrame.lookAt(t1, t1 + V(0.33, 0.14, 0.93)), PUR)
		ell(b, "Tail", V(0.28, 0.8, 0.28), CFrame.new(tp + V(0.22, 0.42, 0.6)), PUR)
	end

	-- 별 슬라임: 얼음빛 반투명 슬라임 (발 없음), 네온 속, 머리 위 큰 네온 별, 흘러내린 방울
	PET_BUILDERS.StarSlime = function(b)
		local ICE = RGB(150, 225, 255)
		local G = Enum.Material.Glass
		local C = V(0, 0.78, 0)
		local S = V(1.1, 0.78, 1.0)
		ell(b, "Body", S * 2, CFrame.new(C), ICE, G, 0.2)
		ell(b, "Skirt", V(2.5, 0.8, 2.3), CFrame.new(0, 0.4, 0), ICE, G, 0.2)
		ell(b, "Core", V(0.9, 0.9, 0.9), CFrame.new(0, 0.72, 0.1), RGB(130, 200, 255), NEON)
		-- 둘레 방울 + 위 혹 + 옆으로 흐르는 방울 + 팔 뭉치
		local bumps = { V(-0.75, 0.22, -0.8), V(0.85, 0.2, -0.6), V(0.6, 0.25, 0.9), V(-0.95, 0.24, 0.4) }
		for _, p in bumps do
			ell(b, "Bump", V(0.46, 0.4, 0.46), CFrame.new(p), ICE, G, 0.2)
		end
		ell(b, "Bump", V(0.6, 0.5, 0.6), CFrame.new(-0.45, 1.4, 0.2), ICE, G, 0.2)
		ell(b, "Drip", V(0.26, 0.5, 0.26), CFrame.new(0.95, 1.0, -0.35), ICE, G, 0.2)
		for _, sx in SIDES do
			ell(b, "Arm", V(0.4, 0.34, 0.4), CFrame.new(sx * 1.05, 0.72, -0.4), ICE, G, 0.2)
		end
		-- 큰 네온 별 (막대 3개 교차 = 6각 별 + 가운데 구슬)
		local sc = V(0.1, 1.74, 0)
		local STAR = RGB(255, 235, 110)
		for i = 0, 2 do
			addPart(b, "Star", "Block", V(0.85, 0.2, 0.1), CFrame.new(sc) * CFrame.Angles(0, 0, math.pi / 2 + i * math.pi / 3), STAR, NEON)
		end
		ell(b, "StarCore", V(0.32, 0.32, 0.14), CFrame.new(sc), STAR, NEON)
		-- 얼굴: 큰 눈 + 볼터치 + 방긋 입
		for _, sx in SIDES do
			addEye(b, C, S, sx * 0.42, 0.18, V(0.42, 0.58, 0.16), 0)
		end
		for _, sx in SIDES do
			local p, n = front(C, S, sx * 0.78, -0.12)
			ell(b, "Blush", V(0.34, 0.18, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		local mp, mn = front(C, S, 0, -0.2)
		ell(b, "Mouth", V(0.36, 0.16, 0.06), facing(mp + mn * 0.01, mn), MOUTH)
		-- 작은 네온 반짝 점
		for i, xy in { V(-0.55, 0.45, 0), V(0.7, 0.5, 0), V(0.25, -0.5, 0) } do
			local p, n = front(C, S, xy.X, xy.Y)
			ell(b, "Spark", V(0.1, 0.1, 0.05), facing(p + n * 0.01, n), if i == 2 then STAR else WHITE, NEON)
		end
	end
end
