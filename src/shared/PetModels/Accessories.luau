-- 펫 옷(액세서리) 14종 모델 (PetModels/init.luau 가 불러서 등록)
-- 빌더 = function(b, fit): 앵커(원점) 둘레에 파트를 만들어요. 앞 = -Z, 위 = +Y.
--   Head: 원점 = 머리 꼭대기 표면 (모자 밑면), Face: 원점 = 두 눈 바로 앞 (눈 높이),
--   Neck: 원점 = 목 앞면, Back: 원점 = 등 표면 (+Z 가 등 바깥쪽).
-- fit.s = 크기 배율 (펫에 맞춰 0.6~2), 그 밖의 fit 값은 init.luau 의 AccFit 설명을 보세요.
-- 첫 번째로 만든 파트가 상점 미리보기 모델의 PrimaryPart 가 돼요. 이름 "Body"/"Head" 는 쓰지 마세요.
return function(Kit, PET_BUILDERS, EGG_BUILDERS, ACC_BUILDERS)
	if not ACC_BUILDERS then
		return
	end
	local V, RGB, ell, addPart, tri, alongY, surf, facing = Kit.V, Kit.RGB, Kit.ell, Kit.addPart, Kit.tri, Kit.alongY, Kit.surf, Kit.facing
	local WHITE, SIDES = Kit.WHITE, Kit.SIDES
	local NEON = Enum.Material.Neon
	local METAL = Enum.Material.Metal
	local GOLD = RGB(255, 200, 60)

	-- 세로(Y) 축 원판/원기둥 (addPart 의 Cyl 은 X 축이라 90도 돌려요)
	local function disc(b, name, d, h, cf, color, mat)
		return addPart(b, name, "Cyl", V(h, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, mat)
	end
	-- 앞뒤(Z) 축 원판 (메달)
	local function coin(b, name, d, t, cf, color, mat)
		return addPart(b, name, "Cyl", V(t, d, d), cf * CFrame.Angles(0, math.pi / 2, 0), color, mat)
	end
	-- 두 점을 잇는 납작한 막대
	local function bar(b, name, a, c, w, t, color, mat)
		local d = c - a
		return addPart(b, name, "Block", V(w, d.Magnitude, t), alongY((a + c) * 0.5, d), color, mat)
	end
	-- 3막대 6각 별 (cf 의 -Z 가 보는 쪽)
	local function star(b, name, cf, len, w, color)
		for i = 0, 2 do
			addPart(b, name, "Block", V(len, w, w * 0.6), cf * CFrame.Angles(0, 0, math.pi / 2 + i * math.pi / 3), color, NEON)
		end
	end

	------------------------------------------------------------------
	-- 머리 [Head]
	------------------------------------------------------------------

	-- 고깔모자: 분홍 고깔(타원체 4층), 하얀 물방울, 노란 방울
	ACC_BUILDERS.PartyHat = function(b, f)
		local S = f.s
		local PINK = RGB(255, 120, 185)
		local base = CFrame.Angles(0, 0, -0.12) -- 살짝 삐딱하게
		local layers = { { 0.15, 0.94, 0.42 }, { 0.42, 0.72, 0.46 }, { 0.68, 0.5, 0.44 }, { 0.9, 0.28, 0.38 } }
		for _, L in layers do
			ell(b, "HatCone", V(L[2], L[3], L[2]) * S, base * CFrame.new(0, L[1] * S, 0), PINK)
		end
		ell(b, "PomPom", V(0.3, 0.3, 0.3) * S, base * CFrame.new(0, 1.1 * S, 0), RGB(255, 225, 70))
		local dots = { { 1, V(0.25, 0, -1) }, { 1, V(-0.95, 0.1, -0.35) }, { 2, V(0.75, 0.1, -0.7) }, { 2, V(-0.35, 0.15, -0.95) }, { 3, V(0.15, 0.1, -1) }, { 1, V(0.8, 0, 0.6) } }
		for _, dd in dots do
			local L = layers[dd[1]]
			local p, n = surf(V(0, L[1] * S, 0), V(L[2], L[3], L[2]) * (S * 0.5), dd[2])
			ell(b, "HatDot", V(0.14, 0.14, 0.05) * S, base * facing(p + n * 0.005 * S, n), WHITE)
		end
	end

	-- 꽃 화관: 초록 덩굴 고리 + 알록달록 작은 꽃 6송이 + 잎 3장
	ACC_BUILDERS.FlowerCrown = function(b, f)
		local S = f.s
		local R = 0.5 * S
		disc(b, "Vine", 2 * R + 0.06 * S, 0.06 * S, CFrame.new(0, -0.08 * S, 0), RGB(95, 170, 80))
		local cols = { RGB(255, 140, 190), RGB(255, 225, 80), RGB(190, 150, 255), WHITE, RGB(255, 165, 90), RGB(140, 200, 255) }
		for i, col in cols do
			local a = (i - 1) * math.pi * 2 / 6
			local dir = V(math.sin(a), 0, -math.cos(a)) -- 첫 꽃 = 정면
			local p = dir * R + V(0, -0.02 * S, 0)
			local cf = facing(p, (dir + V(0, 0.9, 0)).Unit)
			ell(b, "Flower", V(0.28, 0.28, 0.09) * S, cf, col)
			ell(b, "FlowerMid", V(0.11, 0.11, 0.06) * S, cf * CFrame.new(0, 0, -0.04 * S), if i == 2 then RGB(255, 150, 60) else RGB(255, 225, 80))
			if i % 2 == 0 then
				local la = a + math.pi / 6
				local ld = V(math.sin(la), 0, -math.cos(la))
				ell(b, "Leaf", V(0.26, 0.07, 0.13) * S, CFrame.new(ld * (R + 0.02 * S) + V(0, -0.05 * S, 0)) * CFrame.Angles(0, -la, 0.2), RGB(110, 195, 90))
			end
		end
	end

	-- 신사 모자: 까만 원통 + 넓은 챙 + 빨간 띠
	ACC_BUILDERS.TopHat = function(b, f)
		local S = f.s
		local BLK = RGB(32, 32, 40)
		local base = CFrame.Angles(0, 0, 0.1)
		disc(b, "HatCrown", 0.74 * S, 0.78 * S, base * CFrame.new(0, 0.44 * S, 0), BLK)
		disc(b, "HatBrim", 1.16 * S, 0.07 * S, base * CFrame.new(0, 0.06 * S, 0), BLK)
		disc(b, "HatBand", 0.765 * S, 0.15 * S, base * CFrame.new(0, 0.17 * S, 0), RGB(215, 40, 55))
		local sp = V(-0.2, 0.55, -0.313) * S
		addPart(b, "HatShine", "Block", V(0.06, 0.42, 0.02) * S, base * facing(sp, V(-0.2, 0, -0.311).Unit), RGB(95, 95, 112))
	end

	-- 마법사 모자: 넓은 보라 챙 + 뒤로 축 늘어진 고깔 + 노란 네온 별 3개
	ACC_BUILDERS.WizardHat = function(b, f)
		local S = f.s
		local PUR, PUR2 = RGB(125, 75, 205), RGB(100, 58, 175)
		disc(b, "HatBrim", 1.5 * S, 0.07 * S, CFrame.new(0, 0.05 * S, 0), PUR2)
		local layers = {
			{ V(0, 0.22, 0), 0.86, 0.48 },
			{ V(0, 0.55, 0.03), 0.64, 0.46 },
			{ V(0, 0.84, 0.1), 0.44, 0.42 },
			{ V(0.05, 1.06, 0.24), 0.28, 0.36 },
		}
		for _, L in layers do
			ell(b, "HatCone", V(L[2], L[3], L[2]) * S, CFrame.new(L[1] * S), PUR)
		end
		ell(b, "HatTip", V(0.18, 0.2, 0.18) * S, CFrame.new(V(0.1, 1.18, 0.42) * S), PUR)
		local stars = { { 1, V(0.35, 0.05, -1), 0.24 }, { 2, V(-0.8, 0.2, -0.55), 0.2 }, { 3, V(0.55, 0.1, -0.8), 0.17 } }
		for _, st in stars do
			local L = layers[st[1]]
			local p, n = surf(L[1] * S, V(L[2], L[3], L[2]) * (S * 0.5), st[2])
			star(b, "HatStar", facing(p + n * 0.01 * S, n), st[3] * S, 0.055 * S, RGB(255, 230, 80))
		end
	end

	-- 왕관: 금색 오각 띠 + 뾰족 5개 + 끝마다 빨강/파랑 보석 구슬 + 앞 큰 보석
	ACC_BUILDERS.Crown = function(b, f)
		local S = f.s
		local G = RGB(255, 200, 55)
		local a = 0.46 * S
		local w = 2 * a * math.tan(math.pi / 5) + 0.02 * S
		local gems = { RGB(235, 40, 70), RGB(50, 120, 240) }
		for i = 0, 4 do
			local ang = i * math.pi * 2 / 5
			local dir = V(math.sin(ang), 0, -math.cos(ang))
			local pos = dir * a + V(0, 0.12 * S, 0)
			local cf = CFrame.lookAt(pos, pos + dir)
			local band = addPart(b, "CrownBand", "Block", V(w, 0.26 * S, 0.07 * S), cf, G, METAL)
			band.Reflectance = 0.25
			local pt = addPart(b, "CrownPoint", "Block", V(0.3, 0.3, 0.065) * S, cf * CFrame.new(0, 0.13 * S, 0) * CFrame.Angles(0, 0, math.pi / 4), G, METAL)
			pt.Reflectance = 0.25
			local gem = ell(b, "CrownGem", V(0.14, 0.14, 0.14) * S, cf * CFrame.new(0, 0.35 * S, 0), gems[i % 2 + 1])
			gem.Reflectance = 0.3
			if i == 0 then
				local big = ell(b, "CrownGem", V(0.17, 0.17, 0.1) * S, cf * CFrame.new(0, 0, -0.045 * S), gems[1])
				big.Reflectance = 0.3
			end
		end
	end

	------------------------------------------------------------------
	-- 얼굴 [Face]
	------------------------------------------------------------------

	-- 안경테 다리 + 콧등 (선글라스/하트 안경 공용)
	local function glassesFrame(b, S, lensX, color)
		for _, sx in SIDES do
			addPart(b, "GlassesArm", "Block", V(0.05, 0.06, 0.5) * S, CFrame.new(sx * (lensX + 0.25 * S), 0.06 * S, 0.22 * S) * CFrame.Angles(0, -sx * 0.25, 0), color)
		end
		addPart(b, "GlassesBridge", "Block", V(0.32, 0.06, 0.06) * S, CFrame.new(0, 0.08 * S, -0.03 * S), color)
	end

	-- 선글라스: 까만 동그란 알 + 반짝 하이라이트
	ACC_BUILDERS.Sunglasses = function(b, f)
		local S = f.s
		local BLK = RGB(28, 28, 36)
		local lensX = 0.4 * S
		for _, sx in SIDES do
			local lens = ell(b, "Lens", V(0.52, 0.42, 0.08) * S, CFrame.new(sx * lensX, 0, -0.02 * S) * CFrame.Angles(0, -sx * 0.12, 0), BLK)
			lens.Reflectance = 0.35
		end
		for _, sx in SIDES do
			ell(b, "LensGlint", V(0.13, 0.08, 0.02) * S, CFrame.new(sx * lensX - 0.1 * S, 0.1 * S, -0.065 * S) * CFrame.Angles(0, 0, 0.5), WHITE, NEON)
		end
		glassesFrame(b, S, lensX, BLK)
	end

	-- 하트 안경: 분홍 하트 알 (동그라미 2 + 마름모 1, 반투명 0.2)
	ACC_BUILDERS.HeartGlasses = function(b, f)
		local S = f.s
		local PINK = RGB(255, 120, 175)
		local lensX = 0.4 * S
		for _, sx in SIDES do
			local cf = CFrame.new(sx * lensX, 0, -0.02 * S) * CFrame.Angles(0, -sx * 0.12, 0)
			for _, lx in SIDES do
				ell(b, "HeartLens", V(0.27, 0.27, 0.07) * S, cf * CFrame.new(lx * 0.1 * S, 0.06 * S, 0), PINK, nil, 0.2)
			end
			addPart(b, "HeartLens", "Block", V(0.26, 0.26, 0.065) * S, cf * CFrame.new(0, -0.06 * S, 0) * CFrame.Angles(0, 0, math.pi / 4), PINK, nil, 0.2)
		end
		glassesFrame(b, S, lensX, RGB(235, 70, 140))
	end

	-- 콧수염: 갈색 양 갈래, 끝이 위로 돌돌 (fit.mouth = 코 바로 아래)
	ACC_BUILDERS.Mustache = function(b, f)
		local S = f.s
		local BR = RGB(105, 65, 40)
		local o = CFrame.new(f.mouth)
		ell(b, "MustacheMid", V(0.16, 0.13, 0.11) * S, o, BR)
		for _, sx in SIDES do
			local side = o * CFrame.Angles(0, -sx * 0.3, 0) -- 바깥쪽이 얼굴을 따라 뒤로
			ell(b, "MustacheHalf", V(0.36, 0.14, 0.1) * S, side * CFrame.new(sx * 0.16 * S, -0.02 * S, 0) * CFrame.Angles(0, 0, -sx * 0.25), BR)
			ell(b, "MustacheCurl", V(0.12, 0.17, 0.09) * S, side * CFrame.new(sx * 0.35 * S, 0.0, 0) * CFrame.Angles(0, 0, sx * 0.35), BR)
			ell(b, "MustacheTip", V(0.09, 0.09, 0.08) * S, side * CFrame.new(sx * 0.31 * S, 0.08 * S, 0), BR)
		end
	end

	------------------------------------------------------------------
	-- 목 [Neck]
	------------------------------------------------------------------

	-- 나비넥타이: 빨간 세모 날개 2개 + 가운데 매듭
	ACC_BUILDERS.BowTie = function(b, f)
		local S = f.s
		ell(b, "BowKnot", V(0.2, 0.2, 0.17) * S, CFrame.new(0, 0, -0.06 * S), RGB(200, 30, 45))
		for _, sx in SIDES do
			-- 밑변은 세로, 꼭짓점은 가운데를 향해요
			local frame = CFrame.fromMatrix(V(sx * 0.42 * S, 0, -0.04 * S), V(0, sx, 0), V(-sx, 0, 0))
			tri(b, "BowWing", frame, 0.4 * S, 0.38 * S, 0.1 * S, RGB(230, 45, 60))
		end
	end

	-- 목도리: 빨강 바탕 + 하얀 줄 2개로 목을 감고, 앞 오른쪽에 매듭 + 늘어진 끝
	ACC_BUILDERS.Scarf = function(b, f)
		local S = f.s
		local RED, WT = RGB(225, 50, 60), RGB(255, 245, 240)
		local c = f.ring
		local hy = 0.21 * S
		local w, d = 2 * f.rx + 0.22 * S, 2 * f.rz + 0.22 * S
		ell(b, "ScarfWrap", V(w, hy * 2, d), CFrame.new(c), RED)
		for _, y in { 0.09, -0.09 } do
			local k = math.sqrt(1 - (y * S / hy) ^ 2)
			ell(b, "ScarfStripe", V(w * k + 0.03 * S, 0.07 * S, d * k + 0.03 * S), CFrame.new(c + V(0, y * S, 0)), WT)
		end
		local a = math.rad(35)
		local knot = c + V(math.sin(a) * w * 0.5, -0.06 * S, -math.cos(a) * d * 0.5)
		ell(b, "ScarfKnot", V(0.26, 0.24, 0.2) * S, CFrame.new(knot), RED)
		-- 늘어진 끝: 가슴(fit.chest) 앞으로 지나가게 앞으로 기울여요
		local lean = math.clamp(math.atan2(knot.Z - (f.chest.Z - 0.1 * S), 0.6 * S), 0, 0.8)
		local tf = CFrame.new(knot) * CFrame.Angles(lean, 0, -0.12)
		ell(b, "ScarfEnd", V(0.26, 0.62, 0.1) * S, tf * CFrame.new(0, -0.32 * S, 0), RED)
		ell(b, "ScarfStripe", V(0.27, 0.07, 0.11) * S, tf * CFrame.new(0, -0.44 * S, -0.004 * S), WT)
	end

	-- 금메달: 목에 두른 파란 리본 + 가슴 앞 금 원판
	ACC_BUILDERS.Medal = function(b, f)
		local S = f.s
		local BLUE = RGB(60, 120, 230)
		local c = f.ring
		local dc = f.chest + V(0, 0.02 * S, -0.05 * S)
		local disk = coin(b, "MedalDisc", 0.42 * S, 0.07 * S, CFrame.new(dc), GOLD, METAL)
		disk.Reflectance = 0.3
		coin(b, "MedalStar", 0.24 * S, 0.08 * S, CFrame.new(dc + V(0, 0, -0.01 * S)), RGB(255, 235, 140), METAL)
		ell(b, "MedalRibbon", V(2 * f.rx + 0.06 * S, 0.08 * S, 2 * f.rz + 0.06 * S), CFrame.new(c + V(0, 0.02 * S, 0)), BLUE)
		for _, sx in SIDES do
			local top = c + V(sx * f.rx * 0.5, 0.02 * S, -f.rz * 0.86)
			bar(b, "MedalStrap", top, dc + V(sx * 0.07 * S, 0.14 * S, 0), 0.12 * S, 0.04 * S, BLUE)
		end
	end

	------------------------------------------------------------------
	-- 등 [Back]  (+Z = 등 바깥쪽)
	------------------------------------------------------------------

	-- 꼬마 가방: 노란 가방 + 주머니 + 덮개 + 단추 + 어깨끈 2개
	ACC_BUILDERS.Backpack = function(b, f)
		local S = f.s
		ell(b, "Pack", V(0.86, 0.96, 0.52) * S, CFrame.new(0, 0, 0.2 * S), RGB(255, 205, 60))
		ell(b, "PackPocket", V(0.56, 0.42, 0.22) * S, CFrame.new(0, -0.18 * S, 0.43 * S), RGB(245, 175, 40))
		ell(b, "PackFlap", V(0.74, 0.32, 0.36) * S, CFrame.new(0, 0.3 * S, 0.33 * S), RGB(240, 140, 50))
		ell(b, "PackButton", V(0.09, 0.09, 0.06) * S, CFrame.new(0, -0.12 * S, 0.55 * S), RGB(120, 70, 40))
		for _, sx in SIDES do
			addPart(b, "PackStrap", "Block", V(0.1, 0.62, 0.06) * S, CFrame.new(sx * 0.26 * S, 0.12 * S, 0) * CFrame.Angles(-0.2, 0, 0), RGB(200, 120, 40))
		end
	end

	-- 망토: 목 뒤(fit.neck)에서 바닥 위까지 늘어진 빨간 망토, 아래로 퍼짐, 금색 단 + 깃 + 단추
	ACC_BUILDERS.Cape = function(b, f)
		local S = f.s
		local RED = RGB(210, 35, 50)
		local T = V(0, f.neck.Y, f.neck.Z + 0.05 * S)
		local Bm = V(0, -f.drop + 0.12 * S, math.max(0.22 * S, T.Z + 0.1 * S))
		local L = (Bm - T).Magnitude
		local frame = CFrame.fromMatrix(T, Vector3.xAxis, (T - Bm).Unit)
		local W, F = 0.8 * S, 0.32 * S
		addPart(b, "CapeCloth", "Block", V(W, L, 0.05 * S), frame * CFrame.new(0, -L * 0.5, 0), RED)
		for _, sx in SIDES do
			-- 옆으로 퍼지는 직각 세모 (직각 = 아래 안쪽 모서리)
			addPart(b, "CapeCloth", "Wedge", V(0.05 * S, L, F), frame * CFrame.fromMatrix(V(sx * (W + F) * 0.5, -L * 0.5, 0), V(0, 0, sx), V(0, 1, 0)), RED)
		end
		local trim = addPart(b, "CapeTrim", "Block", V(W + 2 * F + 0.04 * S, 0.09 * S, 0.07 * S), frame * CFrame.new(0, -L + 0.045 * S, 0.005 * S), GOLD, METAL)
		trim.Reflectance = 0.2
		addPart(b, "CapeCollar", "Block", V(W + 0.08 * S, 0.1 * S, 0.08 * S), frame * CFrame.new(0, -0.03 * S, 0), GOLD, METAL)
		for _, sx in SIDES do
			ell(b, "CapeClasp", V(0.13, 0.13, 0.1) * S, frame * CFrame.new(sx * W * 0.45, -0.04 * S, -0.04 * S), GOLD, METAL)
		end
	end

	-- 천사 날개: 등 가운데 뿌리 + 양쪽 하얀 깃털 3장씩 (위로 크게, 아래로 작게 펼침)
	ACC_BUILDERS.AngelWings = function(b, f)
		local S = f.s
		local W1, W2 = WHITE, RGB(232, 240, 255)
		ell(b, "WingRoot", V(0.34, 0.3, 0.22) * S, CFrame.new(0, 0.15 * S, 0.08 * S), W1)
		for _, sx in SIDES do
			local root = V(sx * 0.12, 0.18, 0.12) * S
			local feathers = {
				{ V(sx * 0.75, 0.62, 0.3), 1.05, 0.44, W1 },
				{ V(sx * 0.95, 0.15, 0.3), 0.9, 0.38, W2 },
				{ V(sx * 0.85, -0.25, 0.3), 0.7, 0.32, W2 },
			}
			for _, fe in feathers do
				local d = fe[1].Unit
				local len = fe[2] * S
				ell(b, "WingFeather", V(fe[3] * S, len, 0.1 * S), alongY(root + d * (len * 0.5), d), fe[4])
			end
		end
	end
end
