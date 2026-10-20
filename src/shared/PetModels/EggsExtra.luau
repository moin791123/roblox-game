-- 추가 알 모델 (PetModels/init.luau 가 불러서 등록)
-- 바다 알 / 겨울 알 / 캔디 알 / 우주 알 (가로 2, 세로 2.6, 중심은 기본 알과 같음)
return function(Kit, PET_BUILDERS, EGG_BUILDERS)
	local V, RGB, ell, surf, facing, addPart, WHITE = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.facing, Kit.addPart, Kit.WHITE
	local EGG_S, EGG_C, eggBase, eggDot, eggRing = Kit.EGG_S, Kit.EGG_C, Kit.eggBase, Kit.eggDot, Kit.eggRing
	local NEON = Enum.Material.Neon

	-- 알 표면 dir 쪽에 납작 장식을 붙일 CFrame (lift = 표면 밖으로 띄우는 거리)
	local function onEgg(dir, lift)
		local p, n = surf(EGG_C, EGG_S, dir)
		return facing(p + n * (lift or 0), n)
	end

	-- 비스듬히 기운 띠 (앞에서 보면 사선 줄무늬): Kit.eggTiltBand (기운 단면 타원 가운데에 맞춰서 어디서도 안 묻혀요)
	local function tiltRing(b, y, tilt, t, color, mat)
		return Kit.eggTiltBand(b, "Ring", y, tilt, t, color, mat)
	end

	-- 바다 알: 바다색 바탕, 하양/청록 물결 띠, 진주 구슬, 분홍 조개 점
	EGG_BUILDERS.Ocean = function(b)
		local body = eggBase(b, RGB(85, 170, 235))
		body.Reflectance = 0.05
		eggRing(b, 0.15, 0.14, WHITE)
		eggRing(b, -0.2, 0.12, RGB(95, 225, 215))
		eggRing(b, -0.6, 0.14, WHITE)
		for _, d in { V(0.45, 0.75, -0.6), V(-0.5, 0.6, -0.6), V(0.1, 0.95, 0.4), V(-0.75, 0.5, 0.5) } do
			local p, n = surf(EGG_C, EGG_S, d)
			local pearl = ell(b, "Pearl", V(0.22, 0.22, 0.2), CFrame.new(p + n * 0.02), RGB(255, 250, 245))
			pearl.Reflectance = 0.2
		end
		for _, d in { V(0.6, -0.38, -0.7), V(-0.55, -0.4, -0.75), V(0.2, -0.42, 0.9) } do
			eggDot(b, d, 0.24, RGB(255, 190, 175), nil, "Shell")
		end
	end

	-- 겨울 알: 얼음빛 하양-파랑 바탕, 눈 결정 무늬(가는 막대 교차), 아래쪽 서리 띠, 눈송이 점
	EGG_BUILDERS.Snow = function(b)
		local body = eggBase(b, RGB(225, 240, 255))
		body.Reflectance = 0.08
		local function flake(dir, len, bars)
			local cf = onEgg(dir, 0)
			for i = 0, bars - 1 do
				addPart(b, "Flake", "Block", V(len, 0.06, 0.05), cf * CFrame.Angles(0, 0, i * math.pi / bars), WHITE)
			end
		end
		flake(V(0.1, 0.35, -1), 0.5, 3)
		flake(V(-0.75, -0.3, -0.6), 0.4, 3)
		flake(V(0.8, 0.7, 0.4), 0.4, 2)
		eggRing(b, -0.95, 0.2, WHITE)
		for _, d in { V(0.55, -0.2, -0.8), V(-0.3, 0.9, -0.5), V(0.3, 0.2, 1) } do
			eggDot(b, d, 0.14, WHITE, nil, "Snow")
		end
	end

	-- 캔디 알: 분홍 바탕, 사선 캔디 줄무늬(하양/민트 기운 띠 + 위아래 짧은 줄), 스프링클 점
	EGG_BUILDERS.Candy = function(b)
		local PINK = RGB(255, 185, 215)
		local MINT = RGB(175, 240, 215)
		eggBase(b, PINK)
		tiltRing(b, 0.2, 0.32, 0.16, WHITE)
		tiltRing(b, -0.22, 0.32, 0.16, MINT)
		for i, d in { V(0.15, 0.85, -0.6), V(-0.2, 0.8, 0.65), V(0.1, -0.85, -0.6), V(-0.15, -0.8, 0.65) } do
			ell(b, "Stripe", V(0.2, 0.5, 0.06), onEgg(d, -0.02) * CFrame.Angles(0, 0, 0.55), if i % 2 == 0 then MINT else WHITE)
		end
		local cols = { RGB(255, 235, 120), RGB(170, 200, 255), RGB(255, 120, 160), RGB(200, 150, 255), WHITE }
		local dirs = { V(0.5, 0.8, -0.5), V(-0.6, 0.65, -0.6), V(0.95, 0.29, -0.3), V(-0.95, -0.31, -0.3), V(0.2, -0.6, -0.8) }
		for i, d in dirs do
			addPart(b, "Sprinkle", "Block", V(0.2, 0.07, 0.06), onEgg(d, 0.01) * CFrame.Angles(0, 0, i * 0.8), cols[i])
		end
	end

	-- 우주 알: 진남색 바탕, 네온 별점, 빛나는 보라 띠, 고리 달린 작은 행성
	EGG_BUILDERS.Space = function(b)
		eggBase(b, RGB(40, 45, 110))
		eggRing(b, -0.55, 0.1, RGB(160, 130, 255), NEON)
		local starDirs = { V(0.55, 0.6, -0.6), V(-0.6, 0.35, -0.7), V(0.2, -0.65, -0.75), V(-0.3, 0.95, -0.3), V(0.9, -0.05, 0.4), V(-0.85, -0.85, 0.3), V(0.1, 0.4, 1) }
		for i, d in starDirs do
			eggDot(b, d, if i % 3 == 0 then 0.1 else 0.15, if i % 2 == 0 then RGB(255, 245, 180) else WHITE, NEON, "Star")
		end
		local pcf = onEgg(V(-0.45, -0.25, -0.85), 0)
		ell(b, "Planet", V(0.4, 0.4, 0.2), pcf, RGB(255, 170, 90))
		ell(b, "PlanetRing", V(0.7, 0.14, 0.04), pcf * CFrame.new(0, 0, -0.1) * CFrame.Angles(0, 0, -0.45), RGB(255, 225, 170))
	end
end
