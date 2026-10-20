-- v3 새 알 4종 (PetModels/init.luau 가 불러서 등록): 호수 알 / 정글 알 / 진주 알 / 구름 알
-- 크기와 중심은 다른 알과 같아요 (가로 2, 세로 2.6, 중심 Kit.EGG_C). 파트는 14개 이하.
return function(Kit, PET_BUILDERS, EGG_BUILDERS)
	local V, RGB, ell, surf, facing, addPart, WHITE = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.facing, Kit.addPart, Kit.WHITE
	local EGG_S, EGG_C, eggBase, eggDot, eggRing = Kit.EGG_S, Kit.EGG_C, Kit.eggBase, Kit.eggDot, Kit.eggRing
	local NEON = Enum.Material.Neon
	local TOP = EGG_C.Y + EGG_S.Y

	-- 알 표면 dir 쪽에 납작 장식을 붙일 CFrame (lift = 표면 밖으로 띄우는 거리, 음수면 살짝 묻힘)
	local function onEgg(dir, lift)
		local p, n = surf(EGG_C, EGG_S, dir)
		return facing(p + n * (lift or 0), n)
	end

	-- 중심 기준 높이 y 에서 알 둘레 반지름
	local function radAt(y)
		return EGG_S.X * math.sqrt(math.max(1 - (y / EGG_S.Y) ^ 2, 0))
	end

	-- 비스듬히 기운 띠 (올라간 쪽이 뜨지 않게 반지름을 그쪽에 맞춰요)
	local function tiltRing(b, y, tilt, t, color, mat)
		local r = radAt(math.abs(y) + radAt(y) * math.sin(math.abs(tilt)) + t / 2) + 0.03
		local D = 2 * r
		return addPart(b, "Ring", "Cyl", V(t, D, D), CFrame.new(EGG_C + V(0, y, 0)) * CFrame.Angles(0, 0, math.pi / 2 + tilt), color, mat)
	end

	-- 호수 알: 연한 물빛 바탕, 파란 물결 띠(지그재그 8조각) + 아래 얇은 띠, 꼭대기 연잎 + 분홍 꽃봉오리, 물방울
	EGG_BUILDERS.Lake = function(b)
		local body = eggBase(b, RGB(185, 235, 240))
		body.Reflectance = 0.05
		local y = -0.15
		local r = radAt(y)
		local n = 8
		for i = 0, n - 1 do
			local a = (i + 0.5) * math.pi * 2 / n
			local dir = V(math.sin(a), 0, -math.cos(a))
			local p = EGG_C + V(0, y, 0) + dir * (r - 0.02)
			local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.42 else -0.42)
			ell(b, "Wave", V(0.86, 0.17, 0.12), cf, RGB(75, 160, 230))
		end
		eggRing(b, -0.62, 0.08, RGB(120, 200, 245))
		ell(b, "LilyPad", V(0.95, 0.32, 0.85), CFrame.new(0.05, TOP - 0.11, 0.02) * CFrame.Angles(0.06, 0.4, -0.05), RGB(95, 185, 85))
		ell(b, "LilyBud", V(0.2, 0.24, 0.2), CFrame.new(0.14, TOP + 0.1, -0.04), RGB(255, 165, 205))
		eggDot(b, V(-0.55, 0.5, -0.7), 0.17, WHITE, nil, "Bubble")
		eggDot(b, V(0.6, 0.62, -0.5), 0.12, WHITE, nil, "Bubble")
	end

	-- 정글 알: 연두 바탕, 진초록 큰 잎 무늬 6장, 노란 덩굴 띠 + 작은 잎 3장
	EGG_BUILDERS.Jungle = function(b)
		eggBase(b, RGB(135, 210, 95))
		local DK = RGB(45, 128, 62)
		local leaves = {
			{ V(0.45, 0.5, -0.75), 0.45 },
			{ V(-0.6, -0.2, -0.75), -0.55 },
			{ V(0.3, -0.7, -0.65), 0.95 },
			{ V(-0.85, 0.6, 0.2), -0.25 },
			{ V(0.85, -0.15, 0.45), 0.3 },
			{ V(-0.2, 0.25, 1), -0.75 },
		}
		for _, L in leaves do
			ell(b, "BigLeaf", V(0.5, 0.76, 0.14), onEgg(L[1], -0.05) * CFrame.Angles(0, 0, L[2]), DK)
		end
		tiltRing(b, 0.05, 0.22, 0.12, RGB(250, 215, 70))
		for i, a in { -0.6, 0.15, 0.9 } do
			local yy = 0.05 + math.sin(a) * 0.25
			ell(b, "VineLeaf", V(0.22, 0.12, 0.06), onEgg(V(math.sin(a), yy, -math.cos(a)), 0.03) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.6 else -0.6), RGB(160, 225, 110))
		end
	end

	-- 진주 알: 진주빛 하양-분홍 (반사), 은은한 하이라이트, 얇은 금 띠 + 작은 진주 3알, 꼭대기 분홍 조개 + 진주
	EGG_BUILDERS.Pearl = function(b)
		local body = eggBase(b, RGB(255, 236, 244))
		body.Reflectance = 0.25
		ell(b, "Sheen", V(0.45, 1.05, 0.05), onEgg(V(-0.5, 0.35, -0.8), 0) * CFrame.Angles(0, 0, -0.35), WHITE, NEON, 0.55)
		local ring = eggRing(b, -0.1, 0.09, RGB(255, 205, 80), Enum.Material.Metal)
		ring.Reflectance = 0.3
		for _, a in { -0.5, 0, 0.5 } do
			local dir = V(math.sin(a), 0, -math.cos(a))
			local pearl = ell(b, "Pearl", V(0.15, 0.15, 0.15), CFrame.new(EGG_C + V(0, -0.1, 0) + dir * (radAt(-0.1) + 0.05)), WHITE)
			pearl.Reflectance = 0.3
		end
		-- 조개: 뒤로 살짝 누워 앞에서 무늬가 보여요 (아래 경첩에서 부채꼴 줄무늬)
		local shellCf = CFrame.new(0, TOP + 0.12, -0.05) * CFrame.Angles(0.5, 0, 0)
		ell(b, "Shell", V(0.62, 0.48, 0.16), shellCf, RGB(255, 180, 195))
		for _, a in { -0.5, 0, 0.5 } do
			addPart(b, "ShellRib", "Block", V(0.04, 0.4, 0.04), shellCf * CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, a) * CFrame.new(0, 0.2, -0.075), RGB(240, 140, 165))
		end
		local sp = ell(b, "ShellPearl", V(0.16, 0.16, 0.16), shellCf * CFrame.new(0, -0.19, -0.09), WHITE)
		sp.Reflectance = 0.3
		eggDot(b, V(0.5, 0.55, -0.65), 0.12, WHITE, NEON, "Sparkle")
		eggDot(b, V(-0.35, -0.6, -0.7), 0.1, WHITE, NEON, "Sparkle")
	end

	-- 구름 알: 하얀 폭신 알, 아래쪽 라벤더 구름 7개, 꼭대기 작은 금빛 별 (가시 5개 + 가운데)
	EGG_BUILDERS.Cloud = function(b)
		local body = eggBase(b, RGB(250, 251, 255))
		body.Reflectance = 0.04
		local n = 7
		for i = 0, n - 1 do
			local a = (i + 0.25) * math.pi * 2 / n
			local y = -0.82 + (i % 2) * 0.12
			local d = if i % 2 == 0 then 0.66 else 0.56
			local dir = V(math.sin(a), 0, -math.cos(a))
			local col = if i % 3 == 0 then RGB(232, 222, 255) else RGB(212, 198, 255)
			ell(b, "Puff", V(d, d * 0.85, d), CFrame.new(EGG_C + V(0, y, 0) + dir * (radAt(y) - d * 0.22)), col)
		end
		local STAR = RGB(255, 210, 70)
		local sc = CFrame.new(0, TOP + 0.24, 0)
		ell(b, "Star", V(0.2, 0.2, 0.11), sc, STAR, NEON)
		for i = 0, 4 do
			local cf = sc * CFrame.Angles(0, 0, i * math.pi * 2 / 5) * CFrame.new(0, 0.15, 0)
			ell(b, "Star", V(0.12, 0.27, 0.07), cf, STAR, NEON)
		end
	end
end
