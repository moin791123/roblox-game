-- ★v8 9 벚꽃 정원 / 10 공룡 섬 펫 (PetModels/init.luau 가 불러서 등록)
-- 규칙은 init.luau 와 같아요: 앞쪽 = -Z, 바닥 = y 0, 몸 = Body, 머리 = Head.
-- 파트 이름 Eye/Shine/Blush/Mouth/Lash 는 얼굴 전용. 네온은 작은 장식만, 불빛은 희귀 펫에만 약하게.
return function(Kit, PET_BUILDERS, _EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.chibi, Kit.SIDES
	local addPart, darker, alongY, tri, frameUp, muzzle, smallNose, pointyEars, roundEars = Kit.addPart, Kit.darker, Kit.alongY, Kit.tri, Kit.frameUp, Kit.muzzle, Kit.smallNose, Kit.pointyEars, Kit.roundEars
	local WHITE = Kit.WHITE
	local NEON = Enum.Material.Neon
	local GLASS = Enum.Material.Glass
	local H = require(script.Parent.V8Kit).make(Kit)

	-- 더듬이 한 쌍 (머리 위, 끝에 동그란 공)
	local function antennae(b, c, color, tip, len, tipMat)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.35, 1, -0.1))
			local q = p + V(sx * 0.3, len or 0.6, -0.1)
			H.rod(b, "Antenna", p, q, 0.06, color)
			ell(b, "AntennaTip", V(0.18, 0.18, 0.18), CFrame.new(q), tip, tipMat)
		end
	end

	-- 얇은 반투명 날개 (곤충): 위 큰 날개 + 아래 작은 날개
	local function bugWings(b, c, color, big, small, transparency, mat)
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.4, 0.55, 0.8))
			local parts = H.featherWing(b, root, sx, { { 48, big, big * 0.62, color }, { 0, small, small * 0.6, color } }, 0.45, 0.2, 0.05)
			for _, p in parts do
				p.Transparency = transparency or 0.3
				if mat then
					p.Material = mat
				end
			end
		end
	end

	----------------------------------------------------------------------
	-- 9 벚꽃 정원
	----------------------------------------------------------------------

	-- 무당벌레: 까만 머리에 크림색 얼굴, 빨간 등딱지(가운데 줄 + 까만 점 6개), 더듬이
	PET_BUILDERS.Ladybug = function(b)
		local RED = RGB(235, 70, 70)
		local DK = RGB(55, 50, 62)
		local c = chibi(b, {
			body = DK,
			head = DK,
			feet = DK,
			arms = DK,
			face = { color = RGB(255, 236, 226), semi = V(0.82, 0.66, 0.55), offset = V(0, -0.1, -0.46) },
			eyeX = 0.32,
			blushX = 0.56,
			blushY = -0.24,
			mouthY = -0.36,
		})
		-- 등딱지: 몸보다 조금 큰 빨간 반구 두 장 (가운데가 살짝 벌어짐)
		local SC = c.B + V(0, 0.12, 0.12)
		local SS = V(1.0, 0.82, 0.86)
		for _, sx in SIDES do
			ell(b, "Shell", V(SS.X, SS.Y * 2, SS.Z * 2), CFrame.new(SC + V(sx * 0.5, 0, 0)) * CFrame.Angles(0, 0, -sx * 0.08), RED)
		end
		H.rod(b, "ShellLine", SC + V(0, SS.Y, -0.2), SC + V(0, -0.1, SS.Z + 0.02), 0.06, DK)
		for _, d in { V(0.5, 0.7, 0.4), V(-0.5, 0.7, 0.4), V(0.75, 0.15, 0.6), V(-0.75, 0.15, 0.6), V(0.35, 0.2, 0.95), V(-0.35, 0.2, 0.95) } do
			H.patch(b, "Spot", SC + V(if d.X > 0 then 0.5 else -0.5, 0, 0), V(SS.X * 0.5, SS.Y, SS.Z), d, 0.3, 0.3, DK)
		end
		antennae(b, c, DK, DK, 0.5)
	end

	-- 꿀벌: 노란 몸에 까만 줄 3개, 반투명 날개, 더듬이, 작은 침
	PET_BUILDERS.HoneyBee = function(b)
		local Y = RGB(255, 210, 60)
		local DK = RGB(60, 50, 50)
		local c = chibi(b, { body = Y, feet = DK, arms = DK, eyeY = 0.04 })
		for i, y in { 0.45, 0.0, -0.45 } do
			H.patch(b, "Stripe", c.B, c.BS, V(0, y, 1), 1.5 - i * 0.12, 0.26, DK)
		end
		H.patch(b, "Stripe", c.H, c.HS, V(0, 0.6, 1), 1.2, 0.24, DK)
		bugWings(b, c, RGB(225, 245, 255), 1.0, 0.7, 0.35)
		antennae(b, c, DK, DK, 0.55)
		local tp, tn = surf(c.B, c.BS, V(0, -0.2, 1))
		ell(b, "Stinger", V(0.12, 0.12, 0.34), CFrame.lookAt(tp + tn * 0.12, tp + tn), DK)
	end

	-- 나비: 작은 보라 몸, 커다란 분홍 날개 4장 (하얀 점), 더듬이
	PET_BUILDERS.Butterfly = function(b)
		local PINK = RGB(255, 170, 220)
		local BODY = RGB(150, 110, 200)
		local c = chibi(b, { body = BODY, head = RGB(185, 150, 230), BS = V(0.62, 0.72, 0.6), HS = V(0.92, 0.86, 0.86), eyeY = 0.04 })
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.3, 0.4, 0.9))
			local wings = H.featherWing(b, root, sx, { { 40, 1.5, 1.05, PINK }, { -20, 1.05, 0.8, RGB(255, 205, 235) } }, 0.6, 0.15, 0.06)
			for _, w in wings do
				w.Transparency = 0.05
			end
			local dot = root + V(sx * 0.75, 0.7, 0.45)
			ell(b, "WingDot", V(0.28, 0.28, 0.08), CFrame.lookAt(dot, dot + V(-0.45, 0, sx * 0.9)), WHITE)
		end
		antennae(b, c, BODY, RGB(255, 210, 90), 0.6)
	end

	-- 꽃잎 햄스터: 크림·분홍 햄스터, 머리 위 벚꽃 한 송이, 꽃잎 하나를 안고 있어요
	PET_BUILDERS.PetalHamster = function(b)
		local FUR = RGB(255, 222, 205)
		local c = chibi(b, { body = FUR, belly = WHITE, feet = RGB(255, 185, 195), eyeY = 0.02 })
		roundEars(c, 0.6, 0.75, 0.4, FUR, RGB(255, 170, 190))
		smallNose(c, -0.2, V(0.14, 0.1, 0.08), RGB(255, 140, 160), 0.02)
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.5, -0.32)
			ell(b, "Cheek", V(0.5, 0.4, 0.3), facing(p - n * 0.06, n), RGB(255, 236, 228))
		end
		H.flower(b, H.top(c, 0.95) + V(0.25, 0.05, 0), V(0.3, 1, -0.4), 0.5, RGB(255, 180, 205), RGB(255, 225, 110))
		local pp, pn = front(c.BeC, c.BeS, 0, 0.1)
		ell(b, "HeldPetal", V(0.55, 0.7, 0.12), facing(pp + pn * 0.12, pn) * CFrame.Angles(0, 0, 0.3), RGB(255, 175, 200))
	end

	-- 벚꽃 냥이: 연분홍 고양이, 귀 옆 벚꽃, 꼬리 끝 벚꽃, 이마 꽃잎 무늬
	PET_BUILDERS.SakuraCat = function(b)
		local FUR = RGB(255, 200, 220)
		local c = chibi(b, { body = FUR, belly = RGB(255, 245, 248), eyeY = 0.04 })
		pointyEars(c, 0.55, 0.85, 0.6, 0.72, 0.14, 0.25, FUR, RGB(255, 160, 190))
		smallNose(c, -0.2, V(0.14, 0.1, 0.08), RGB(255, 120, 150), 0.02)
		H.lashes(b, c.eyes)
		H.flower(b, surf(c.H, c.HS, V(0.75, 0.75, -0.2)), V(0.6, 0.5, -0.6), 0.55, RGB(255, 150, 190), RGB(255, 225, 110))
		H.patch(b, "Mark", c.H, c.HS, V(0, 0.75, -0.6), 0.22, 0.32, RGB(255, 140, 180))
		local tip = H.tail(b, c, FUR, { w = 0.32, l1 = 0.45, d1 = V(0.3, 0.6, 1), d2 = V(0.2, 1, 0.3), l2 = 0.8 })
		H.flower(b, tip, V(0, 0.4, 1), 0.45, RGB(255, 150, 190), RGB(255, 225, 110))
	end

	-- 꽃 요정: 연두 꼬마 요정, 꽃잎 치마, 꽃봉오리 모자, 반투명 날개
	PET_BUILDERS.FlowerFairy = function(b)
		local SKIN = RGB(255, 230, 215)
		local LEAF = RGB(140, 215, 120)
		local PETAL = RGB(255, 190, 220)
		local c = chibi(b, { body = LEAF, head = SKIN, feet = RGB(110, 180, 95), arms = SKIN, eyeY = -0.02 })
		H.lashes(b, c.eyes)
		-- 꽃잎 치마 (허리 둘레 6장)
		for i = 0, 5 do
			local a = i * math.pi / 3
			local d = V(math.sin(a), -0.15, math.cos(a))
			local p = surf(c.B, c.BS, d)
			ell(b, "Skirt", V(0.5, 0.65, 0.16), CFrame.lookAt(p, p + V(d.X, 0, d.Z)) * CFrame.Angles(-0.5, 0, 0), if i % 2 == 0 then PETAL else RGB(255, 225, 240))
		end
		-- 꽃봉오리 모자 (잎 3장이 감싼 분홍 봉오리)
		local top = H.top(c, 0.8)
		ell(b, "Hat", V(0.9, 0.8, 0.9), CFrame.new(top + V(0, 0.25, 0)), PETAL)
		for i = 0, 2 do
			local a = i * 2 * math.pi / 3
			local d = V(math.sin(a), 0.4, math.cos(a))
			ell(b, "HatLeaf", V(0.42, 0.7, 0.12), CFrame.lookAt(top + d * 0.3, top + d * 0.3 + V(d.X, 0, d.Z)) * CFrame.Angles(-0.35, 0, 0), LEAF)
		end
		ell(b, "HatTip", V(0.18, 0.3, 0.18), CFrame.new(top + V(0, 0.72, 0)), RGB(255, 150, 200))
		H.wings(b, c, { { 45, 1.15, 0.6, RGB(230, 255, 230) }, { 5, 0.85, 0.48, RGB(255, 235, 245) } }, { transparency = 0.3, thick = 0.05 })
	end

	-- 벚꽃 정령: 둥실 떠 있는 반투명 연분홍 정령, 꽃잎 왕관, 주위를 도는 꽃잎 3장
	PET_BUILDERS.SakuraSpirit = function(b)
		local S = RGB(255, 215, 235)
		local c = chibi(b, { body = S, feet = S, eyeY = 0.04, HS = V(1.08, 1.0, 1.0) })
		for _, p in b.parts do
			if p.Name == "Body" or p.Name == "Head" or p.Name == "Foot" or p.Name == "Arm" then
				p.Material = GLASS
				p.Transparency = 0.15
			end
		end
		H.lashes(b, c.eyes)
		-- 꽃잎 왕관 (머리 둘레 7장)
		local cy = c.H.Y + c.HS.Y * 0.62
		for i = 0, 6 do
			local a = i * 2 * math.pi / 7
			local d = V(math.sin(a), 0, -math.cos(a))
			local p = V(0, cy, 0) + d * c.HS.X * 0.78
			ell(b, "CrownPetal", V(0.3, 0.46, 0.08), CFrame.lookAt(p, p + d) * CFrame.Angles(-0.4, 0, 0), RGB(255, 150, 195))
		end
		-- 둥실 꽃잎 3장 (작은 네온 하나)
		for i, o in { V(1.3, 1.6, -0.2), V(-1.25, 2.3, 0.2), V(0.9, 2.9, 0.4) } do
			ell(b, "FloatPetal", V(0.3, 0.42, 0.06), CFrame.new(o) * CFrame.Angles(0.4 * i, 0.6, 0.7 * i), RGB(255, 170, 205), if i == 1 then NEON else nil)
		end
		H.patch(b, "Mark", c.H, c.HS, V(0, 0.6, -0.8), 0.24, 0.24, RGB(255, 160, 200), 0, NEON)
	end

	-- 나비 여왕 (시크릿): 보라 나비, 금 왕관, 보석 박힌 커다란 날개 (가장자리 은은한 네온)
	PET_BUILDERS.ButterflyQueen = function(b)
		local BODY = RGB(140, 100, 210)
		local W1 = RGB(200, 150, 255)
		local W2 = RGB(255, 180, 235)
		local GOLD = RGB(255, 210, 90)
		local c = chibi(b, { body = BODY, head = RGB(185, 150, 240), belly = RGB(225, 205, 255), BS = V(0.66, 0.74, 0.62), eyeY = 0.04 })
		H.lashes(b, c.eyes)
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.3, 0.45, 0.9))
			H.featherWing(b, root, sx, { { 48, 1.85, 1.2, W1 }, { -18, 1.3, 0.95, W2 } }, 0.6, 0.15, 0.06)
			H.featherWing(b, root + V(0, 0, 0.03), sx, { { 48, 1.45, 0.75, RGB(240, 215, 255) } }, 0.6, 0.15, 0.07, "WingInner")
			local g = root + V(sx * 1.05, 1.05, 0.65)
			ell(b, "WingGem", V(0.26, 0.26, 0.1), CFrame.lookAt(g, g + V(-0.4, 0, sx)), RGB(120, 230, 255), NEON)
			local g2 = root + V(sx * 0.65, -0.35, 0.45)
			ell(b, "WingGem", V(0.2, 0.2, 0.1), CFrame.lookAt(g2, g2 + V(-0.4, 0, sx)), GOLD)
		end
		H.crown(b, H.top(c, 0.86), 0.4, GOLD, RGB(255, 90, 160))
		antennae(b, c, BODY, GOLD, 0.7, NEON)
		H.glow(H.part(b, "Body"), RGB(220, 170, 255), 0.25, 4)
	end

	-- 꿀단지 곰 (시크릿 알): 꿀단지를 꼭 안은 곰, 머리 위로 흐르는 꿀, 작은 꿀벌 친구
	PET_BUILDERS.HoneyBear = function(b)
		local FUR = RGB(240, 170, 70)
		local HONEY = RGB(255, 190, 40)
		local POT = RGB(200, 120, 70)
		local c = chibi(b, { body = FUR, belly = RGB(255, 225, 160), feet = RGB(205, 135, 55), eyeY = 0.06, noMouth = true })
		roundEars(c, 0.62, 0.72, 0.46, FUR, RGB(255, 210, 150))
		muzzle(c, V(0.62, 0.44, 0.4), RGB(255, 228, 175), RGB(90, 55, 40), -0.28)
		-- 꿀단지 (배 앞) + 뚜껑 띠 + 꿀이 넘쳐요
		local pc = c.BeC + V(0, 0.0, -0.55)
		ell(b, "Pot", V(1.0, 0.95, 0.85), CFrame.new(pc), POT)
		addPart(b, "PotRim", "Cyl", V(0.16, 0.78, 0.78), CFrame.new(pc + V(0, 0.42, 0)) * CFrame.Angles(0, 0, math.pi / 2), darker(POT, 0.15))
		ell(b, "Honey", V(0.7, 0.24, 0.7), CFrame.new(pc + V(0, 0.5, 0)), HONEY, GLASS)
		ell(b, "Drip", V(0.2, 0.42, 0.14), CFrame.new(pc + V(0.25, 0.25, -0.38)), HONEY, GLASS)
		H.patch(b, "PotLabel", pc, V(0.5, 0.48, 0.43), V(0, 0, -1), 0.46, 0.32, RGB(255, 240, 200))
		-- 머리 위 꿀 (흘러내림)
		local top = H.top(c, 0.9)
		ell(b, "Honey", V(0.9, 0.3, 0.8), CFrame.new(top), HONEY, GLASS)
		ell(b, "Drip", V(0.18, 0.4, 0.14), CFrame.new(surf(c.H, c.HS, V(0.45, 0.7, -0.45))), HONEY, GLASS)
		-- 작은 꿀벌 친구
		local bp = c.H + V(1.25, 0.65, -0.2)
		ell(b, "Bee", V(0.36, 0.3, 0.42), CFrame.new(bp), RGB(255, 215, 60))
		ell(b, "BeeStripe", V(0.38, 0.32, 0.1), CFrame.new(bp + V(0, 0, 0.06)), RGB(60, 50, 50))
		for _, sx in SIDES do
			ell(b, "BeeWing", V(0.24, 0.3, 0.04), CFrame.new(bp + V(sx * 0.12, 0.2, 0.05)) * CFrame.Angles(0, 0, -sx * 0.4), WHITE, nil, 0.3)
		end
		H.glow(H.part(b, "Body"), RGB(255, 200, 100), 0.2, 4)
	end

	-- 벚꽃 두루미 (천상): 하얀 두루미, 빨간 정수리, 까만 목, 분홍 끝 날개를 펼치고 벚꽃잎이 흩날려요
	PET_BUILDERS.SakuraCrane = function(b)
		local W = RGB(255, 250, 252)
		local BLK = RGB(50, 50, 60)
		local PINK = RGB(255, 170, 205)
		-- 몸 (앞으로 둥근 물방울)
		local B = V(0, 1.3, 0.25)
		local BS = V(0.8, 0.72, 1.0)
		ell(b, "Body", BS * 2, CFrame.new(B), W)
		-- 긴 다리 2 (빨간 무릎 없이 가는 회색)
		for _, sx in SIDES do
			H.rod(b, "Leg", B + V(sx * 0.3, -0.5, 0.1), V(sx * 0.32, 0.12, 0.05), 0.12, RGB(120, 120, 130))
			ell(b, "Foot", V(0.36, 0.12, 0.48), CFrame.new(sx * 0.32, 0.06, -0.08), RGB(120, 120, 130))
		end
		-- 목 (까만 S자) + 머리
		local n0 = B + V(0, 0.5, -0.6)
		local n1 = n0 + V(0, 0.75, -0.15)
		H.link(b, "Neck", n0, n1, 0.42, BLK)
		local HC = n1 + V(0, 0.45, -0.1)
		local HS = V(0.6, 0.55, 0.58)
		ell(b, "Head", HS * 2, CFrame.new(HC), W)
		local c = { b = b, B = B, BS = BS, H = HC, HS = HS, FC = HC, FS = HS }
		for _, sx in SIDES do
			Kit.addEye(b, HC, HS, sx * 0.22, 0.04, V(0.24, 0.32, 0.12), 0)
			local p, n = front(HC, HS, sx * 0.36, -0.18)
			ell(b, "Blush", V(0.2, 0.11, 0.05), facing(p, n), Kit.BLUSH, nil, 0.1)
		end
		local bp, bn = front(HC, HS, 0, -0.12)
		ell(b, "Beak", V(0.16, 0.16, 0.6), CFrame.lookAt(bp + bn * 0.22, bp + bn), RGB(255, 210, 120))
		ell(b, "CrownSpot", V(0.36, 0.14, 0.32), CFrame.new(HC + V(0, HS.Y - 0.04, 0.02)), RGB(240, 60, 70), NEON)
		-- 날개 (하얀 깃털, 끝 분홍) + 꼬리깃 까망
		H.wings(b, c, { { 60, 1.5, 0.46, W }, { 35, 1.35, 0.44, W }, { 10, 1.1, 0.4, PINK } }, { x = 0.6, y = 0.35, sweep = 0.3, lean = 0.35 })
		for _, sx in SIDES do
			local tp = B + V(sx * 0.18, 0.1, BS.Z - 0.1)
			ell(b, "TailFeather", V(0.24, 0.16, 0.8), CFrame.lookAt(tp, tp + V(sx * 0.2, 0.25, 1)) * CFrame.new(0, 0, -0.25), BLK)
		end
		for i, o in { V(1.4, 2.8, -0.4), V(-1.5, 2.2, 0.3), V(0.3, 3.4, 0.9) } do
			ell(b, "FloatPetal", V(0.26, 0.36, 0.06), CFrame.new(o) * CFrame.Angles(0.5 * i, 0.4, 0.8 * i), PINK, if i == 1 then NEON else nil)
		end
		H.glow(H.part(b, "Body"), RGB(255, 210, 230), 0.3, 4.5)
	end

	-- 벚꽃 용 (이터널): 분홍 아기 용, 벚꽃 핀 나뭇가지 뿔, 꽃잎 날개, 등에 꽃 가시, 꼬리 끝 벚꽃
	PET_BUILDERS.BlossomDragon = function(b)
		local P = RGB(255, 150, 200)
		local CR = RGB(255, 235, 240)
		local WOOD = RGB(150, 100, 85)
		local BLOOM = RGB(255, 200, 225)
		local CORE = RGB(255, 225, 110)
		local c = chibi(b, { body = P, belly = CR, feet = darker(P, 0.12), eyeY = 0.04, BS = V(0.95, 0.8, 0.85), HS = V(1.08, 0.98, 0.98) })
		H.lashes(b, c.eyes)
		for _, y in { 0.22, -0.04, -0.3 } do
			local p, n = front(c.BeC, c.BeS, 0, y)
			H.stick(b, "BellyLine", p, n, 0.5, 0.07, 0.62, RGB(240, 190, 205))
		end
		-- 나뭇가지 뿔 + 가지 끝 벚꽃
		for _, sx in SIDES do
			local ap = surf(c.H, c.HS, V(sx * 0.42, 1, 0.12))
			local d1 = V(sx * 0.45, 1, 0.2).Unit
			H.rod(b, "Antler", ap - d1 * 0.05, ap + d1 * 0.62, 0.13, WOOD)
			local bp = ap + d1 * 0.35
			local d2 = V(sx, 0.55, -0.2).Unit
			H.rod(b, "Antler", bp, bp + d2 * 0.4, 0.1, WOOD)
			H.flower(b, ap + d1 * 0.7, V(sx * 0.3, 0.5, -1), 0.4, BLOOM, CORE)
			ell(b, "Bud", V(0.18, 0.18, 0.18), CFrame.new(bp + d2 * 0.45), RGB(255, 170, 205))
		end
		-- 꽃잎 날개 (반투명, 끝 진분홍)
		H.wings(b, c, { { 55, 1.4, 0.75, RGB(255, 225, 240) }, { 25, 1.2, 0.65, BLOOM }, { -5, 0.9, 0.5, P } }, { transparency = 0.15, thick = 0.06 })
		-- 등 꽃 가시
		for _, sp in { { c.H, c.HS, V(0, 0.5, 1) }, { c.B, c.BS, V(0, 0.7, 1) }, { c.B, c.BS, V(0, 0.15, 1) } } do
			local p, n = surf(sp[1], sp[2], sp[3])
			ell(b, "Spike", V(0.2, 0.3, 0.2), CFrame.new(p + n * 0.08), RGB(255, 120, 175))
		end
		local tip, d = H.tail(b, c, P, { w = 0.5, color2 = P })
		H.flower(b, tip, d, 0.55, BLOOM, CORE, nil)
		ell(b, "TailGlow", V(0.16, 0.16, 0.1), CFrame.new(tip + d * 0.05), CORE, NEON)
		for i, o in { V(1.45, 2.9, -0.2), V(-1.5, 2.5, 0.3), V(-0.6, 3.6, 0.8) } do
			ell(b, "FloatPetal", V(0.26, 0.36, 0.06), CFrame.new(o) * CFrame.Angles(0.5 * i, 0.4, 0.8 * i), BLOOM, if i == 1 then NEON else nil)
		end
		H.glow(H.part(b, "Body"), RGB(255, 190, 220), 0.4, 5.5)
	end

	----------------------------------------------------------------------
	-- 10 공룡 섬
	----------------------------------------------------------------------

	-- 공룡 꼬마 공통: chibi + 주둥이 + 꼬리
	local function dino(b, col, belly, opt)
		local o = opt or {}
		local c = chibi(b, { body = col, belly = belly, feet = darker(col, 0.12), eyeY = o.eyeY or 0.12, noMouth = true, BS = o.BS, HS = o.HS })
		H.snout(b, c, o.snout or darker(col, 0.05), o.snoutSize or V(0.9, 0.55, 0.6), -0.26)
		local tip, d = H.tail(b, c, col, { w = o.tailW or 0.6, l1 = 0.45, d1 = V(0, 0.05, 1), d2 = V(0, 0.35, 1), l2 = 0.8 })
		return c, tip, d
	end

	-- 아기 공룡: 연두 꼬마 공룡, 머리 위에 깨진 알 껍데기 모자, 등 가시
	PET_BUILDERS.BabyDino = function(b)
		local G = RGB(130, 210, 110)
		local c = dino(b, G, RGB(240, 245, 200))
		H.spikes(b, c, RGB(255, 200, 80), 0.9)
		-- 알 껍데기 모자 (위로 볼록한 하얀 반쪽 + 지그재그 가장자리)
		local top = H.top(c, 0.72)
		ell(b, "EggHat", V(1.1, 0.8, 1.05), CFrame.new(top + V(0, 0.22, 0.05)), RGB(255, 252, 240))
		for i = 0, 7 do
			local a = i * math.pi / 4
			local p = top + V(math.sin(a) * 0.52, -0.05, math.cos(a) * 0.5)
			ell(b, "EggHat", V(0.2, 0.26, 0.1), CFrame.lookAt(p, p + V(math.sin(a), 0, math.cos(a))) * CFrame.Angles(0, 0, math.pi / 4), RGB(255, 252, 240))
		end
		H.patch(b, "EggSpot", top + V(0, 0.22, 0.05), V(0.55, 0.4, 0.52), V(0.4, 0.8, -0.4), 0.2, 0.2, RGB(150, 220, 130))
	end

	-- 아기 익룡: 주황 몸, 뒤로 뻗은 볏, 긴 부리, 박쥐 같은 날개
	PET_BUILDERS.Ptero = function(b)
		local O = RGB(240, 160, 110)
		local c = chibi(b, { body = O, belly = RGB(255, 225, 195), eyeY = 0.08, noMouth = true })
		local cf = H.beak(b, c, RGB(255, 215, 130), -0.2, V(0.36, 0.3, 0.9))
		ell(b, "Beak", V(0.3, 0.12, 0.7), cf * CFrame.new(0, -0.1, -0.1), RGB(240, 190, 110))
		local cp = surf(c.H, c.HS, V(0, 0.8, 0.6))
		ell(b, "Crest", V(0.18, 0.5, 1.3), CFrame.new(cp + V(0, 0.02, 0.35)) * CFrame.Angles(-0.35, 0, 0), RGB(230, 100, 80))
		H.batWings(b, c, RGB(250, 190, 150), 1.1, 1.5, RGB(255, 215, 180))
	end

	-- 스테고: 파란 네 발 공룡, 등에 주황 판 5장, 꼬리 끝 가시
	PET_BUILDERS.Stego = function(b)
		local BL = RGB(130, 190, 230)
		local c = H.quad(b, { body = BL, belly = RGB(220, 240, 250), HS = V(0.7, 0.62, 0.68), eyeY = 0.06, eyeX = 0.3, eyeSize = V(0.26, 0.36, 0.13) })
		H.snout(b, c, BL, V(0.7, 0.42, 0.45), -0.22)
		for i, z in { -0.75, -0.35, 0.05, 0.45, 0.85 } do
			local h = if i == 2 or i == 3 or i == 4 then 0.75 else 0.55
			local p = surf(c.B, c.BS, V(0, 1, z))
			tri(b, "Plate", CFrame.new(p - V(0, 0.12, 0)) * CFrame.Angles(0, math.pi / 2, 0), 0.6, h, 0.12, RGB(255, 160, 80))
		end
		local tp = surf(c.B, c.BS, V(0, 0, 1))
		local t1 = tp + V(0, 0.2, 0.6)
		H.link(b, "Tail", tp, t1, 0.4, BL)
		for _, sx in SIDES do
			ell(b, "TailSpike", V(0.1, 0.1, 0.42), CFrame.lookAt(t1, t1 + V(sx, 0.6, 0.3)) * CFrame.new(0, 0, -0.2), RGB(255, 245, 225))
		end
	end

	-- 트리케라: 노란 네 발 공룡, 큰 주름 목깃(분홍 테두리), 뿔 3개
	PET_BUILDERS.Tricera = function(b)
		local Y = RGB(250, 190, 90)
		local c = H.quad(b, { body = Y, belly = RGB(255, 235, 190), eyeY = 0.04 })
		local cf = H.snout(b, c, Y, V(0.75, 0.5, 0.55), -0.28)
		ell(b, "Horn", V(0.14, 0.32, 0.14), cf * CFrame.new(0, 0.3, -0.18) * CFrame.Angles(-0.4, 0, 0), RGB(255, 250, 235))
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.4, 0.85, -0.3))
			ell(b, "Horn", V(0.16, 0.65, 0.16), alongY(p + V(sx * 0.05, 0.25, -0.1), V(sx * 0.2, 1, -0.6)), RGB(255, 250, 235))
		end
		local fc = c.H + V(0, 0.45, 0.45)
		addPart(b, "Frill", "Cyl", V(0.16, 2.2, 2.2), CFrame.new(fc) * CFrame.Angles(-0.35, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), RGB(255, 150, 120))
		addPart(b, "Frill", "Cyl", V(0.18, 1.8, 1.8), CFrame.new(fc + V(0, 0, -0.03)) * CFrame.Angles(-0.35, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), Y)
		H.tail(b, c, Y, { w = 0.42, from = -0.2, d1 = V(0, -0.1, 1), d2 = V(0, 0.2, 1) })
	end

	-- 브론토: 긴 목 공룡, 동그란 연두 몸, 등 점박이
	PET_BUILDERS.Bronto = function(b)
		local G = RGB(170, 200, 140)
		local c = H.quad(b, { body = G, belly = RGB(235, 240, 200), BS = V(0.95, 0.8, 1.2), HS = V(0.62, 0.55, 0.62), headAt = V(0, 3.0, -1.1), eyeY = 0.04, eyeX = 0.28, eyeSize = V(0.24, 0.34, 0.12) })
		H.link(b, "Neck", c.B + V(0, 0.4, -0.7), c.H + V(0, -0.2, 0.2), 0.62, G)
		H.snout(b, c, G, V(0.6, 0.38, 0.4), -0.2)
		for _, d in { V(0.5, 0.8, 0.2), V(-0.4, 0.85, -0.2), V(0.1, 0.9, 0.6), V(-0.6, 0.5, 0.5) } do
			H.patch(b, "Spot", c.B, c.BS, d, 0.4, 0.34, RGB(130, 170, 110))
		end
		H.tail(b, c, G, { w = 0.5, from = -0.1, d1 = V(0, -0.15, 1), d2 = V(0.3, 0.1, 1), l1 = 0.5, l2 = 0.9 })
	end

	-- 안킬로: 갑옷 등에 동그란 돌기, 옆 가시, 꼬리 끝 곤봉
	PET_BUILDERS.Ankylo = function(b)
		local BR = RGB(190, 150, 110)
		local AR = RGB(150, 115, 85)
		local c = H.quad(b, { body = BR, belly = RGB(240, 220, 190), BS = V(1.0, 0.65, 1.15), legH = 0.4, HS = V(0.72, 0.6, 0.68), eyeX = 0.3, eyeSize = V(0.26, 0.36, 0.13) })
		H.snout(b, c, BR, V(0.75, 0.42, 0.42), -0.22)
		ell(b, "Shell", V(2.15, 1.05, 2.3), CFrame.new(c.B + V(0, 0.32, 0)), AR)
		for _, d in { V(0, 1, 0), V(0.5, 0.8, -0.5), V(-0.5, 0.8, -0.5), V(0.5, 0.8, 0.5), V(-0.5, 0.8, 0.5), V(0, 0.85, -0.85), V(0, 0.85, 0.85) } do
			local p, n = surf(c.B + V(0, 0.32, 0), V(1.075, 0.525, 1.15), d)
			ell(b, "Stud", V(0.3, 0.2, 0.3), CFrame.new(p) * CFrame.lookAt(Vector3.zero, n) * CFrame.Angles(-math.pi / 2, 0, 0), RGB(240, 215, 175))
		end
		for _, sx in SIDES do
			for _, z in { -0.4, 0.4 } do
				local p, n = surf(c.B + V(0, 0.32, 0), V(1.075, 0.525, 1.15), V(sx, 0, z))
				ell(b, "Spike", V(0.14, 0.14, 0.4), CFrame.lookAt(p + n * 0.12, p + n), RGB(240, 215, 175))
			end
		end
		local tp = surf(c.B, c.BS, V(0, 0, 1))
		local t1 = tp + V(0, 0.05, 0.75)
		H.link(b, "Tail", tp, t1, 0.36, BR)
		ell(b, "TailClub", V(0.75, 0.5, 0.6), CFrame.new(t1 + V(0, 0, 0.2)), AR)
	end

	-- 꼬마 티렉스: 큰 머리, 작은 팔, 하얀 이빨, 등 가시
	PET_BUILDERS.TRex = function(b)
		local G = RGB(110, 180, 90)
		local c = chibi(b, { body = G, belly = RGB(225, 240, 175), feet = darker(G, 0.15), eyeY = 0.2, noMouth = true, HS = V(1.12, 0.95, 1.05), noArms = true })
		local cf = H.snout(b, c, G, V(1.2, 0.62, 0.75), -0.26)
		for _, x in { -0.4, -0.2, 0.2, 0.4 } do
			ell(b, "Tooth", V(0.09, 0.12, 0.06), cf * CFrame.new(x, -0.22, -0.3), WHITE)
		end
		for _, sx in SIDES do
			local p = surf(c.B, c.BS, V(sx * 0.7, 0.25, -0.7))
			ell(b, "Arm", V(0.2, 0.36, 0.2), CFrame.new(p) * CFrame.Angles(-0.8, 0, sx * 0.3), G)
			local bp = surf(c.H, c.HS, V(sx * 0.55, 0.75, -0.35))
			ell(b, "Brow", V(0.36, 0.12, 0.16), CFrame.new(bp) * CFrame.Angles(0, 0, -sx * 0.2), darker(G, 0.2))
		end
		H.spikes(b, c, RGB(255, 140, 80), 1)
		H.tail(b, c, G, { w = 0.65, l1 = 0.5, d1 = V(0, 0, 1), d2 = V(0, 0.3, 1), l2 = 0.9 })
	end

	-- 호박 랩터 (시크릿): 호박색 랩터, 머리·팔의 깃털, 이마의 빛나는 호박 보석 (안에 모기)
	PET_BUILDERS.AmberRaptor = function(b)
		local A = RGB(255, 180, 60)
		local FEATHER = RGB(230, 110, 60)
		local c, tip, d = dino(b, A, RGB(255, 235, 190), { snoutSize = V(0.85, 0.5, 0.7), eyeY = 0.14 })
		H.lashes(b, c.eyes)
		-- 머리 깃털 (뒤로 3장)
		for i, a in { -0.35, 0, 0.35 } do
			local p = surf(c.H, c.HS, V(a, 0.8, 0.5))
			ell(b, "Feather", V(0.22, 0.75, 0.12), alongY(p + V(0, 0.25, 0.2), V(a, 0.8, 0.8)), if i == 2 then FEATHER else RGB(255, 140, 70))
		end
		-- 팔 깃털
		for _, sx in SIDES do
			local p = surf(c.B, c.BS, V(sx, 0.1, -0.2))
			ell(b, "Feather", V(0.14, 0.6, 0.36), alongY(p + V(sx * 0.2, 0, 0.15), V(sx, -0.3, 0.6)), FEATHER)
		end
		-- 등 줄무늬
		for _, y in { 0.5, 0.05 } do
			H.patch(b, "Stripe", c.B, c.BS, V(0, y, 1), 1.2, 0.18, RGB(200, 110, 40))
		end
		ell(b, "TailFeather", V(0.4, 0.14, 0.7), CFrame.lookAt(tip, tip + d), FEATHER)
		-- 이마 호박 보석
		local gp, gn = front(c.H, c.HS, 0, 0.55)
		ell(b, "Amber", V(0.42, 0.42, 0.24), facing(gp + gn * 0.06, gn), RGB(255, 160, 30), GLASS, 0.15)
		ell(b, "Amber", V(0.16, 0.12, 0.08), facing(gp + gn * 0.14, gn), RGB(110, 70, 40))
		ell(b, "AmberGlow", V(0.12, 0.12, 0.06), facing(gp + gn * 0.17, gn) * CFrame.new(0.08, 0.08, 0), RGB(255, 230, 150), NEON)
		H.glow(H.part(b, "Body"), RGB(255, 190, 90), 0.25, 4)
	end

	-- 공룡 옷 강아지 (시크릿 알): 공룡 후드를 쓴 갈색 강아지 (후드 가시·꼬리)
	PET_BUILDERS.DinoPuppy = function(b)
		local SUIT = RGB(120, 210, 120)
		local DOG = RGB(225, 175, 120)
		local c = chibi(b, {
			body = SUIT,
			head = SUIT,
			belly = RGB(235, 245, 200),
			feet = darker(SUIT, 0.15),
			face = { color = DOG, semi = V(0.82, 0.72, 0.6), offset = V(0, -0.12, -0.42) },
			eyeX = 0.32,
			eyeY = 0.06,
			blushX = 0.55,
			blushY = -0.22,
			noMouth = true,
		})
		muzzle({ b = b, H = c.FC, HS = c.FS }, V(0.5, 0.36, 0.32), RGB(255, 235, 210), RGB(60, 40, 35), -0.24)
		-- 후드에 붙은 강아지 귀 (늘어진)
		for _, sx in SIDES do
			local p = surf(c.FC, c.FS, V(sx, 0.4, -0.2))
			ell(b, "Ear", V(0.3, 0.62, 0.2), CFrame.new(p + V(sx * 0.08, -0.15, 0)) * CFrame.Angles(0, 0, sx * 0.25), darker(DOG, 0.25))
		end
		-- 후드 이빨 (얼굴 둘레 위쪽)
		for i = -2, 2 do
			local p = surf(c.H, c.HS, V(i * 0.32, 0.55, -0.85))
			ell(b, "HoodTooth", V(0.14, 0.2, 0.1), CFrame.new(p) * CFrame.Angles(0, 0, math.pi), WHITE)
		end
		H.spikes(b, c, RGB(255, 210, 90), 1)
		H.tail(b, c, SUIT, { w = 0.55, l1 = 0.4, d1 = V(0, 0, 1), d2 = V(0, 0.35, 1) })
		H.glow(H.part(b, "Body"), RGB(170, 255, 170), 0.2, 4)
	end

	-- 하늘 익룡 (천상): 금빛 익룡, 하얀 깃털 날개, 이마 해님 볏, 발밑 구름
	PET_BUILDERS.SkyPtera = function(b)
		local GO = RGB(255, 210, 120)
		local c = chibi(b, { body = GO, belly = RGB(255, 245, 215), eyeY = 0.08, noMouth = true })
		H.lashes(b, c.eyes)
		H.beak(b, c, RGB(255, 175, 80), -0.2, V(0.36, 0.3, 0.95))
		local cp = surf(c.H, c.HS, V(0, 0.8, 0.6))
		ell(b, "Crest", V(0.18, 0.55, 1.35), CFrame.new(cp + V(0, 0.04, 0.35)) * CFrame.Angles(-0.35, 0, 0), RGB(255, 140, 90))
		ell(b, "CrestGlow", V(0.2, 0.2, 0.2), CFrame.new(cp + V(0, 0.42, 0.85)), RGB(255, 240, 160), NEON)
		H.wings(b, c, { { 62, 1.6, 0.48, WHITE }, { 38, 1.5, 0.46, RGB(255, 245, 220) }, { 14, 1.25, 0.42, RGB(255, 225, 160) }, { -8, 0.95, 0.38, GO } }, { sweep = 0.25, lean = 0.25 })
		-- 발밑 구름 (작은 공 4개)
		for _, o in { V(-0.6, 0.12, 0.2), V(0.6, 0.12, 0.25), V(0, 0.1, 0.55), V(0, 0.12, -0.35) } do
			ell(b, "Cloud", V(0.7, 0.36, 0.6), CFrame.new(o), WHITE, nil, 0.1)
		end
		H.glow(H.part(b, "Body"), RGB(255, 230, 170), 0.3, 4.5)
	end

	-- 고대 용 (이터널): 짙은 초록 돌비늘 용, 이끼 낀 돌 뿔, 몸의 빛나는 룬 무늬, 고대 문양 날개
	PET_BUILDERS.AncientDragon = function(b)
		local G = RGB(90, 150, 110)
		local STONE = RGB(160, 155, 140)
		local MOSS = RGB(120, 190, 90)
		local RUNE = RGB(120, 255, 210)
		local c = chibi(b, { body = G, belly = RGB(200, 215, 170), feet = darker(G, 0.2), eyeY = 0.06, BS = V(0.98, 0.82, 0.88), HS = V(1.1, 0.98, 1.0) })
		for _, sx in SIDES do
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(G, 0.4))
			-- 돌 뿔 (뒤로 휜 두 마디) + 이끼
			local p = surf(c.H, c.HS, V(sx * 0.5, 0.9, 0.2))
			local p1 = p + V(sx * 0.25, 0.45, 0.25)
			local p2 = p1 + V(sx * 0.1, 0.25, 0.4)
			H.link(b, "Horn", p, p1, 0.26, STONE)
			H.link(b, "Horn", p1, p2, 0.18, STONE)
			ell(b, "Moss", V(0.26, 0.14, 0.26), CFrame.new(p1 + V(0, 0.08, 0)), MOSS)
			-- 고대 날개: 돌색 뼈대 + 초록 막
			local base = c.B + V(sx * 0.32, 0.5, 0.55)
			tri(b, "Wing", frameUp(base, V(sx, 0.8, 0.5), Vector3.zAxis), 1.0, 1.45, 0.08, RGB(110, 170, 130))
			H.rod(b, "WingBone", base, base + V(sx, 0.8, 0.5).Unit * 1.45, 0.1, STONE)
			ell(b, "WingRune", V(0.18, 0.18, 0.06), frameUp(base + V(sx, 0.8, 0.5).Unit * 0.6, V(sx, 0.8, 0.5), Vector3.zAxis), RUNE, NEON)
		end
		-- 돌 등판 3장
		for _, sp in { { c.H, c.HS, V(0, 0.4, 1), 0.36 }, { c.B, c.BS, V(0, 0.65, 1), 0.44 }, { c.B, c.BS, V(0, 0.05, 1), 0.36 } } do
			local p, n = surf(sp[1], sp[2], sp[3])
			ell(b, "Spike", V(sp[4], sp[4] * 1.1, sp[4] * 0.8), CFrame.new(p + n * 0.08), STONE)
		end
		-- 빛나는 룬 (가슴 원 + 이마 줄)
		local gp, gn = front(c.BeC, c.BeS, 0, 0.3)
		addPart(b, "Rune", "Cyl", V(0.05, 0.4, 0.4), facing(gp + gn * 0.03, gn) * CFrame.Angles(0, math.pi / 2, 0), RUNE, NEON)
		local fp, fn = front(c.H, c.HS, 0, 0.55)
		H.stick(b, "Rune", fp, fn, 0.12, 0.3, 1, RUNE, 0, NEON)
		local tip, d = H.tail(b, c, G, { w = 0.55 })
		ell(b, "TailStone", V(0.42, 0.42, 0.42), CFrame.new(tip + d * 0.1), STONE)
		ell(b, "Moss", V(0.3, 0.14, 0.3), CFrame.new(tip + d * 0.1 + V(0, 0.18, 0)), MOSS)
		H.glow(H.part(b, "Body"), RGB(140, 255, 210), 0.4, 5.5)
	end
end
