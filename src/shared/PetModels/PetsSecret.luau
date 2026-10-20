-- 비밀 펫 + 환생 알 모델 (PetModels/init.luau 가 불러서 등록)
return function(Kit, PET_BUILDERS, EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, tri, addEye, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.tri, Kit.addEye, Kit.SIDES
	local addPart, darker, frameUp = Kit.addPart, Kit.darker, Kit.frameUp
	local eggBase, eggDot, eggRing, EGG_S, EGG_C = Kit.eggBase, Kit.eggDot, Kit.eggRing, Kit.EGG_S, Kit.EGG_C
	local WHITE, BLACK, BLUSH, MOUTH = Kit.WHITE, Kit.BLACK, Kit.BLUSH, Kit.MOUTH
	local NEON = Enum.Material.Neon

	local function glow(parent: BasePart, color: Color3, brightness: number, range: number)
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Brightness = brightness
		light.Range = range
		light.Shadows = false
		light.Parent = parent
	end

	----------------------------------------------------------------------
	-- 우주 고래: 남색 통통 고래, 하얀 배, 큰 웃음, 등에 네온 별, 물줄기, 떠 있는 초승달
	-- 발 없이 바닥에서 살짝 떠 있음 (투명 Hover 파트로 피벗 바닥 = y 0)
	----------------------------------------------------------------------
	PET_BUILDERS.CosmicWhale = function(b)
		local INDIGO = RGB(60, 62, 165)
		local DEEP = darker(INDIGO, 0.22)
		local BELLY = RGB(205, 225, 255)
		local CYAN = RGB(130, 240, 255)
		local PINK = RGB(255, 175, 235)
		local MOON = RGB(255, 236, 150)

		-- 몸통 (바닥에서 0.45 떠 있음) + 배
		local BS = V(1.05, 0.8, 1.4)
		local B = V(0, 0.45 + BS.Y, 0)
		local body = ell(b, "Body", BS * 2, CFrame.new(B), INDIGO)
		local BeC, BeS = B + V(0, -0.42, -0.15), V(0.95, 0.5, 1.2)
		ell(b, "Belly", BeS * 2, CFrame.new(BeC), BELLY)
		addPart(b, "Hover", "Block", V(0.3, 0.1, 0.3), CFrame.new(0, 0.05, 0), BLACK, nil, 1)

		-- 앞면에서 (x, y 절대높이) 위치의 표면: 몸통/배 중 더 앞에 나온 쪽
		local function face(x: number, y: number): (Vector3, Vector3)
			local p1, n1 = front(B, BS, x, y - B.Y)
			local p2, n2 = front(BeC, BeS, x, y - BeC.Y)
			if p2.Z < p1.Z then
				return p2, n2
			end
			return p1, n1
		end

		-- 얼굴: 큰 반짝 눈, 볼터치, 몸통/배 경계선을 따라 양끝이 올라간 큰 웃음 + 혀
		for _, sx in SIDES do
			addEye(b, B, BS, sx * 0.52, 0.16, V(0.4, 0.5, 0.18), 0)
		end
		for _, sx in SIDES do
			local p, n = front(B, BS, sx * 0.82, -0.1)
			ell(b, "Blush", V(0.34, 0.18, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		local mp, mn = face(0, 0.95)
		ell(b, "Mouth", V(0.52, 0.1, 0.06), facing(mp, mn), MOUTH)
		for _, sx in SIDES do
			local p, n = face(sx * 0.4, 1.02)
			ell(b, "Mouth", V(0.36, 0.1, 0.06), facing(p, n) * CFrame.Angles(0, 0, sx * 0.55), MOUTH)
		end
		local tgp, tgn = face(0, 0.85)
		ell(b, "Tongue", V(0.22, 0.12, 0.06), facing(tgp, tgn), RGB(255, 130, 150))

		-- 옆 지느러미 (아래/뒤로 비스듬히)
		for _, sx in SIDES do
			local fp = surf(B, BS, V(sx, -0.25, -0.25))
			local cf = CFrame.new(fp + V(sx * 0.32, -0.14, 0.05)) * CFrame.Angles(0, -sx * 0.35, 0) * CFrame.Angles(0, 0, -sx * 0.45)
			ell(b, "Fin", V(0.95, 0.16, 0.5), cf, DEEP)
		end

		-- 꼬리 + 양쪽 꼬리 지느러미
		local tp = surf(B, BS, V(0, 0.05, 1))
		local d1 = V(0, 0.2, 1).Unit
		local t1 = tp + d1 * 0.3
		ell(b, "Tail", V(0.55, 0.45, 1.1), CFrame.lookAt(t1, t1 + d1), INDIGO)
		local te = t1 + d1 * 0.5
		for _, sx in SIDES do
			local cf = CFrame.new(te + V(sx * 0.4, 0.02, 0.12)) * CFrame.Angles(0, -sx * 0.45, 0) * CFrame.Angles(0, 0, sx * 0.15)
			ell(b, "Fluke", V(0.85, 0.12, 0.5), cf, DEEP)
		end

		-- 등지느러미 (작은 세모, 살짝 뒤로 누움)
		local dp, dn = surf(B, BS, V(0, 1, 0.5))
		tri(b, "DorsalFin", frameUp(dp - dn * 0.1, V(0, 1, 0.45), Vector3.xAxis), 0.55, 0.5, 0.1, DEEP)

		-- 숨구멍 + 네온 물줄기 (공 3개가 위로 솟음)
		local sp, sn = surf(B, BS, V(0, 1, -0.3))
		ell(b, "Blowhole", V(0.26, 0.2, 0.08), facing(sp - sn * 0.02, sn), DEEP)
		local spout = { { V(0, 0.16, 0), 0.2 }, { V(0.1, 0.44, -0.03), 0.27 }, { V(-0.07, 0.76, 0.02), 0.34 } }
		for _, s in spout do
			ell(b, "Spout", V(s[2], s[2], s[2]), CFrame.new(sp + s[1]), CYAN, NEON)
		end

		-- 등 위에 떠 있는 네온 초승달 (렌즈 모양 3조각이 호를 그림)
		local mcf = CFrame.new(0.72, 2.45, 0.3) * CFrame.Angles(0, 0, 0.45)
		for _, a in { -math.pi / 2, -math.pi / 2 + 0.95, -math.pi / 2 - 0.95 } do
			local tip = a ~= -math.pi / 2
			local size = if tip then V(0.3, 0.11, 0.1) else V(0.34, 0.17, 0.12)
			ell(b, "Moon", size, mcf * CFrame.new(0.3 * math.cos(a), 0.3 * math.sin(a), 0) * CFrame.Angles(0, 0, a + math.pi / 2), MOON, NEON)
		end

		-- 등/옆구리의 네온 별 가루 10개 (흰/청록/분홍)
		local starDirs = {
			V(0.45, 0.85, 0.1),
			V(-0.55, 0.8, -0.3),
			V(0.35, 0.85, 0.75),
			V(-0.35, 0.8, 0.85),
			V(0.85, 0.55, -0.45),
			V(-0.9, 0.45, 0.35),
			V(0.6, 0.7, -0.75),
			V(-0.65, 0.6, -0.8),
			V(0.9, 0.5, 0.7),
			V(-0.2, 0.95, -0.8),
		}
		local starCols = { WHITE, CYAN, PINK }
		for i, d in starDirs do
			local p, n = surf(B, BS, d)
			local s = 0.11 + 0.04 * (i % 3)
			ell(b, "Star", V(s, s, 0.08), facing(p - n * 0.02, n), starCols[(i - 1) % 3 + 1], NEON)
		end

		glow(body, RGB(140, 205, 255), 0.8, 7)
	end

	----------------------------------------------------------------------
	-- 황혼 알: 보라 → 분홍 → 주황으로 물드는 노을 알, 네온 별, 꼭대기 금색 띠
	----------------------------------------------------------------------
	EGG_BUILDERS.Twilight = function(b)
		eggBase(b, RGB(150, 95, 205))
		-- 아래쪽 주황 노을: 안쪽 타원체가 아랫부분에서 몸 밖으로 살짝 나옴
		ell(b, "Dusk", V(1.98, 2.0, 1.98), CFrame.new(0, 1.01, 0), RGB(255, 168, 95))
		eggRing(b, -0.3, 0.22, RGB(245, 128, 190))
		eggRing(b, -0.52, 0.2, RGB(255, 145, 135))
		eggRing(b, 0.82, 0.1, RGB(255, 215, 110), Enum.Material.Metal)
		local stars = {
			V(0.45, 0.55, -0.7),
			V(-0.5, 0.3, -0.8),
			V(0.12, 0.05, -0.95),
			V(-0.25, 0.85, -0.45),
			V(0.85, 0.3, 0.3),
			V(-0.6, 0.5, 0.6),
		}
		for i, d in stars do
			eggDot(b, d, if i % 2 == 0 then 0.14 else 0.18, if i % 3 == 0 then RGB(255, 220, 160) else WHITE, NEON, "Star")
		end
	end

	----------------------------------------------------------------------
	-- 별빛 알: 짙은 남색, 정면 네온 별빛 폭발, 반짝이 가루, 청록 네온 띠, 은은한 빛
	----------------------------------------------------------------------
	EGG_BUILDERS.Starlight = function(b)
		local CYAN = RGB(120, 235, 255)
		local body = eggBase(b, RGB(28, 36, 96))
		-- 별빛 폭발: 십자 광선 2개 + 대각선 광선 2개 + 가운데 구슬
		local p, n = front(EGG_C, EGG_S, 0, 0.18)
		local scf = facing(p - n * 0.03, n)
		ell(b, "Ray", V(0.95, 0.2, 0.12), scf, WHITE, NEON)
		ell(b, "Ray", V(0.2, 1.0, 0.12), scf, WHITE, NEON)
		for _, r in SIDES do
			ell(b, "Ray", V(0.66, 0.13, 0.1), scf * CFrame.Angles(0, 0, r * math.pi / 4), CYAN, NEON)
		end
		ell(b, "Core", V(0.34, 0.34, 0.2), scf * CFrame.new(0, 0, -0.05), RGB(255, 248, 215), NEON)
		eggRing(b, -0.6, 0.12, CYAN, NEON)
		local specks = {
			V(0.75, 0.65, -0.45),
			V(-0.7, 0.6, -0.5),
			V(0.85, -0.15, -0.5),
			V(-0.85, -0.2, -0.45),
			V(0.3, 0.95, 0.3),
			V(-0.4, 0.85, 0.6),
			V(0.9, 0.35, 0.55),
			V(-0.9, -0.1, 0.6),
		}
		local cols = { WHITE, CYAN, RGB(255, 180, 240) }
		for i, d in specks do
			eggDot(b, d, 0.1 + 0.03 * (i % 3), cols[(i - 1) % 3 + 1], NEON, "Spark")
		end
		glow(body, RGB(140, 215, 255), 0.45, 5)
	end
end
