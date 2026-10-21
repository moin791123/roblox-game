-- v6 아주 희귀한 펫 (숲 마을 / 호수 / 정글 / 겨울 산): 테마마다 시크릿 → 천상 → 이터널 (PetModels/init.luau 가 불러서 등록)
-- 규칙은 init.luau 와 같아요: 앞쪽 = -Z, 바닥 = y 0, 몸 = Body, 머리 = Head.
-- 파트 이름 Eye/Shine/Blush/Mouth/Lash 는 얼굴 전용 (등급 색을 안 입혀요).
-- 집이 번쩍이지 않게: 네온은 작은 장식 몇 개만, 불빛은 천상(0.3)/이터널(0.4)에만 아주 약하게.
return function(Kit, PET_BUILDERS, _EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, addEye, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.addEye, Kit.chibi, Kit.SIDES
	local addPart, darker, alongX, alongY, tri, muzzle, smallNose, pointyEars, roundEars = Kit.addPart, Kit.darker, Kit.alongX, Kit.alongY, Kit.tri, Kit.muzzle, Kit.smallNose, Kit.pointyEars, Kit.roundEars
	local WHITE, EYE, BLUSH, MOUTH, RAINBOW = Kit.WHITE, Kit.EYE, Kit.BLUSH, Kit.MOUTH, Kit.RAINBOW
	local NEON = Enum.Material.Neon
	local GLASS = Enum.Material.Glass
	local METAL = Enum.Material.Metal

	----------------------------------------------------------------------
	-- 도우미
	----------------------------------------------------------------------

	-- 은은한 불빛 (작고 약하게)
	local function glow(part, color, brightness, range)
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Brightness = brightness
		light.Range = range
		light.Shadows = false
		light.Parent = part
	end

	local function partNamed(b, name)
		for _, p in b.parts do
			if p.Name == name then
				return p
			end
		end
		return nil
	end

	-- 곡면에 착 붙는 납작 무늬: 두께를 곡률(반지름 R)에 맞춰 가장자리가 뜨지 않게
	local function stick(b, name, p, n, w, h, R, color, spin, mat)
		local a = math.max(w, h) * 0.5
		local t = math.clamp(a * a / R, 0.05, a)
		return ell(b, name, V(w, h, t * 2), facing(p - n * (t - 0.03), n) * CFrame.Angles(0, 0, spin or 0), color, mat)
	end

	local function patch(b, name, C, S, dir, w, h, color, spin, mat)
		local p, n = surf(C, S, dir)
		return stick(b, name, p, n, w, h, (S.X + S.Y + S.Z) / 3, color, spin, mat)
	end

	-- 두 점 사이를 잇는 길쭉한 타원체 (팔/목/꼬리 마디)
	local function link(b, name, p0, p1, w, h, extra, color, mat)
		local mid = (p0 + p1) * 0.5
		return ell(b, name, V(w, h, (p1 - p0).Magnitude + extra), CFrame.lookAt(mid, p1), color, mat)
	end

	-- 속눈썹 (k = 눈 크기 비율, 기본 눈 폭 0.36 = 1)
	local function lashes(b, eyes, k)
		local s = k or 1
		for i, cf in eyes do
			local sx = if i == 1 then -1 else 1
			addPart(b, "Lash", "Block", V(0.14 * s, 0.04, 0.04), cf * CFrame.new(sx * 0.19 * s, 0.2 * s, -0.03) * CFrame.Angles(0, 0, sx * 0.6), EYE)
		end
	end

	-- 깃털/꽃잎 날개: root 에서 바깥/위로 부채꼴. f = { 각도(도, 수평 바깥 = 0), 길이, 폭, 색 }
	-- sweep = 바깥 끝이 뒤로 젖혀지는 정도, lean = 위로 갈수록 뒤로 눕는 정도. 만든 파트들을 돌려줘요
	local function featherWing(b, root, sx, feathers, sweep, lean, thick, name)
		local out = {}
		local nrm = V(-math.sin(sweep), 0, sx * math.cos(sweep))
		for _, f in feathers do
			local th = math.rad(f[1])
			local d = V(sx * math.cos(th) * math.cos(sweep), math.sin(th), math.cos(th) * math.sin(sweep) + math.sin(th) * lean).Unit
			local xv = d:Cross(nrm).Unit
			table.insert(out, ell(b, name or "Wing", V(f[3], f[2], thick), CFrame.fromMatrix(root + d * (f[2] * 0.42), xv, d), f[4]))
		end
		return out
	end

	-- 납작한 꽃잎/잎 n 장을 cf 의 로컬 XY 평면에 빙 둘러요 (cf 의 앞(-Z)을 봐요, 첫 장 각도 = start)
	local function petals(b, name, cf, n, r, size, color, mat, start)
		for i = 0, n - 1 do
			local a = (start or math.pi / 2) + i * 2 * math.pi / n
			ell(b, name, size, cf * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(0, 0, a - math.pi / 2), color, mat)
		end
	end

	-- 뾰족한 수정/보석 칼날 (쐐기 2개): base 에서 dir 쪽으로 뾰족, 폭은 side 방향, 두께는 그 둘에 수직
	local function blade(b, name, base, dir, side, w, h, t, color, mat, transparency)
		local d = dir.Unit
		local s = (side - d * side:Dot(d)).Unit
		tri(b, name, CFrame.fromMatrix(base, s, d), w, h, t, color, mat)
		if transparency then
			b.parts[#b.parts].Transparency = transparency
			b.parts[#b.parts - 1].Transparency = transparency
		end
	end

	----------------------------------------------------------------------
	-- 1 숲 마을
	----------------------------------------------------------------------

	-- 네잎클로버 여우 (시크릿): 주황 꼬마 여우, 이마에 은은한 민트 네잎클로버, 크게 말린 꼬리 끝에도 클로버
	PET_BUILDERS.CloverFox = function(b)
		local O = RGB(245, 135, 55)
		local Wt = RGB(255, 250, 240)
		local Dk = RGB(110, 65, 45)
		local MINT = RGB(70, 200, 130)
		local LEAF = RGB(95, 195, 105)
		local STEM = RGB(70, 150, 80)
		local c = chibi(b, { body = O, belly = Wt, feet = Dk, arms = Dk, eyeY = 0.06, noMouth = true, blushX = 0.7, blushY = -0.2 })
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.22, -0.36)
			ell(b, "Cheek", V(0.6, 0.45, 0.35), facing(p - n * 0.08, n), Wt)
		end
		smallNose(c, -0.22, V(0.18, 0.12, 0.1), RGB(40, 30, 30), 0.05)
		local mp, mn = front(c.H, c.HS, 0, -0.4)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), MOUTH)
		pointyEars(c, 0.55, 0.85, 0.62, 0.75, 0.15, 0.28, O, RGB(255, 235, 215))

		-- 이마 네잎클로버: X 자로 놓인 작은 네온 잎 4장 + 짧은 줄기
		local cy = 0.6
		for i = 0, 3 do
			local a = math.pi / 4 + i * math.pi / 2
			local p, n = front(c.H, c.HS, math.cos(a) * 0.11, cy + math.sin(a) * 0.11)
			ell(b, "Clover", V(0.19, 0.23, 0.06), facing(p + n * 0.004, n) * CFrame.Angles(0, 0, a - math.pi / 2), MINT, NEON)
		end
		local sp, sn = front(c.H, c.HS, 0.02, cy - 0.15)
		ell(b, "CloverStem", V(0.05, 0.17, 0.05), facing(sp + sn * 0.004, sn) * CFrame.Angles(0, 0, 0.3), STEM)

		-- 크게 말린 복슬 꼬리 (뒤로 나갔다가 오른쪽 위로, 앞에서도 머리 옆으로 보여요) + 끝의 초록 클로버
		local tails = {
			{ V(0.25, 0.62, 0.95), 0.78, O },
			{ V(0.55, 1.12, 1.4), 0.9, O },
			{ V(0.86, 1.72, 1.48), 0.8, Wt },
		}
		for _, t in tails do
			ell(b, "Tail", V(t[2], t[2], t[2]), CFrame.new(t[1]), t[3])
		end
		local tipC, tipR = tails[3][1], tails[3][2] * 0.5
		local d = V(0.35, 1, -0.45).Unit
		local base = tipC + d * (tipR - 0.03)
		petals(b, "TailClover", CFrame.lookAt(base, base + d), 4, 0.13, V(0.22, 0.26, 0.07), LEAF, nil, math.pi / 4)
	end

	-- 꽃사슴 요정 (천상): 하얀 점박이 연분홍 아기 사슴, 벚꽃이 핀 뿔, 등에 작은 반투명 꽃잎 날개
	PET_BUILDERS.BlossomFawn = function(b)
		local FUR = RGB(255, 212, 222)
		local CREAM = RGB(255, 246, 238)
		local HOOF = RGB(225, 145, 165)
		local SPOT = RGB(255, 253, 253)
		local WOOD = RGB(185, 130, 115)
		local PETAL = RGB(255, 168, 198)
		local BUD = RGB(255, 205, 222)
		local CORE = RGB(255, 220, 120)
		local WING = RGB(255, 230, 244)
		local c = chibi(b, { body = FUR, belly = CREAM, feet = HOOF, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		lashes(b, c.eyes)
		muzzle(c, V(0.56, 0.38, 0.36), CREAM, RGB(150, 90, 105), -0.32)
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx, 0.42, 0.05))
			ell(b, "Ear", V(0.66, 0.3, 0.2), CFrame.new(p + n * 0.14) * CFrame.Angles(0, 0, sx * 0.4), FUR)
		end

		-- 벚꽃 뿔: 줄기 + 바깥 가지, 줄기 끝에 다섯 꽃잎 벚꽃 (가운데 작은 네온), 가지 끝에 꽃봉오리
		for _, sx in SIDES do
			local ap = surf(c.H, c.HS, V(sx * 0.42, 1, 0.12))
			local d1 = V(sx * 0.42, 1, 0.12).Unit
			addPart(b, "Antler", "Cyl", V(0.74, 0.12, 0.12), alongX(ap + d1 * 0.28, d1), WOOD)
			local bp = ap + d1 * 0.38
			local d2 = V(sx, 0.7, -0.2).Unit
			addPart(b, "Antler", "Cyl", V(0.42, 0.1, 0.1), alongX(bp + d2 * 0.18, d2), WOOD)
			local tip = ap + d1 * 0.64
			local fcf = CFrame.lookAt(tip, tip + V(sx * 0.3, 0.45, -1).Unit)
			petals(b, "Blossom", fcf, 5, 0.14, V(0.19, 0.24, 0.05), PETAL)
			ell(b, "Blossom", V(0.12, 0.12, 0.07), fcf * CFrame.new(0, 0, -0.02), CORE, NEON)
			ell(b, "Bud", V(0.19, 0.19, 0.19), CFrame.new(bp + d2 * 0.38), BUD)
		end

		-- 하얀 점박이 (등/엉덩이/뒤통수)
		for _, s in { { c.B, c.BS, V(0.6, 0.2, 0.8), 0.26 }, { c.B, c.BS, V(-0.55, -0.05, 0.85), 0.24 }, { c.H, c.HS, V(-0.4, 0.25, 0.95), 0.22 } } do
			patch(b, "Spot", s[1], s[2], s[3], s[4], s[4] * 0.85, SPOT)
		end

		-- 반투명 꽃잎 날개 (큰 잎 + 작은 잎)
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.5, 0.45, 0.8))
			for _, p in featherWing(b, root, sx, { { 50, 1.05, 0.6, WING }, { 10, 0.76, 0.48, PETAL } }, 0.55, 0.25, 0.06) do
				p.Transparency = 0.25
			end
		end
		local tp, tn = surf(c.B, c.BS, V(0, 0.1, 1))
		ell(b, "Tail", V(0.32, 0.36, 0.28), CFrame.new(tp + tn * 0.06), CREAM)
		glow(partNamed(b, "Body"), RGB(255, 200, 220), 0.3, 4.5)
	end

	-- 세계수 용 (이터널): 통통한 잎새 초록 아기 용, 금빛 배, 등에서 자라는 작은 세계수 (금빛 열매가 은은하게 빛나요)
	PET_BUILDERS.WorldTreeDragon = function(b)
		local G = RGB(120, 205, 95)
		local GD = RGB(90, 170, 75)
		local GOLD = RGB(255, 200, 75)
		local GOLD2 = RGB(255, 228, 140)
		local LINE = RGB(225, 165, 55)
		local BARK = RGB(145, 98, 62)
		local CAN = { RGB(105, 205, 115), RGB(135, 225, 130), RGB(95, 190, 110), RGB(150, 232, 140) }
		local FRUIT = RGB(255, 220, 110)
		local c = chibi(b, { body = G, belly = GOLD, feet = GD, eyeY = 0.04, BS = V(0.95, 0.8, 0.85), HS = V(1.08, 0.98, 0.98) })
		local belly = partNamed(b, "Belly")
		if belly then
			belly.Reflectance = 0.08
		end
		-- 배 줄무늬 (용 배 비늘)
		for _, y in { 0.22, -0.04, -0.3 } do
			local p, n = front(c.BeC, c.BeS, 0, y)
			stick(b, "BellyLine", p, n, 0.5, 0.07, 0.62, LINE)
		end
		-- 금빛 뿔 + 콧구멍 + 작은 송곳니
		for _, sx in SIDES do
			local d = V(sx * 0.35, 1, 0.45)
			local p = surf(c.H, c.HS, V(sx * 0.45, 1, 0.1))
			ell(b, "Horn", V(0.2, 0.55, 0.2), alongY(p + d.Unit * 0.18, d), GOLD2)
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(G, 0.35))
		end
		local fp, fn = front(c.H, c.HS, 0.08, -0.37)
		ell(b, "Tooth", V(0.07, 0.09, 0.05), facing(fp + fn * 0.01, fn), WHITE)
		-- 머리 옆 잎사귀 귀
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx, 0.3, 0.1))
			local d = V(sx, 0.45, 0.25).Unit
			ell(b, "Ear", V(0.4, 0.62, 0.08), alongY(p + d * 0.22, d), CAN[2])
		end
		-- 꼬리 + 끝 잎사귀
		local tp = surf(c.B, c.BS, V(0, -0.45, 1))
		local d1 = V(0.25, 0.1, 1).Unit
		local t1 = tp + d1 * 0.35
		ell(b, "Tail", V(0.52, 0.52, 0.95), CFrame.lookAt(t1, t1 + d1), G)
		local d2 = V(0.45, 0.45, 0.8).Unit
		local t2 = t1 + d1 * 0.4 + d2 * 0.3
		ell(b, "Tail", V(0.32, 0.32, 0.65), CFrame.lookAt(t2, t2 + d2), G)
		local t3 = t2 + d2 * 0.42
		ell(b, "TailLeaf", V(0.34, 0.5, 0.08), alongY(t3 + d2 * 0.1, d2), CAN[1])

		-- 등에서 자라는 세계수: 뿌리 2 + 줄기 2 마디 + 가지 2 + 동글 잎뭉치 4 + 금빛 열매 3
		local T0 = V(0, 1.38, 0.74)
		local T1 = V(0, 2.3, 1.28)
		local T2 = V(0, 2.95, 1.42)
		addPart(b, "Trunk", "Cyl", V((T1 - T0).Magnitude + 0.12, 0.28, 0.28), alongX((T0 + T1) * 0.5, T1 - T0), BARK)
		addPart(b, "Trunk", "Cyl", V((T2 - T1).Magnitude + 0.12, 0.2, 0.2), alongX((T1 + T2) * 0.5, T2 - T1), BARK)
		for _, sx in SIDES do
			local r0 = T0 + V(sx * 0.12, 0.02, 0.02)
			ell(b, "Root", V(0.16, 0.14, 0.46), CFrame.lookAt(r0, r0 + V(sx * 0.8, -0.45, -0.1)) * CFrame.new(0, 0, -0.12), BARK)
			local bd = V(sx, 0.8, 0.1).Unit
			local bp = T1 + (T2 - T1) * 0.2
			addPart(b, "Branch", "Cyl", V(0.5, 0.1, 0.1), alongX(bp + bd * 0.22, bd), BARK)
		end
		local canopy = {
			{ V(0, 3.25, 1.42), 1.0 },
			{ V(-0.5, 3.0, 1.36), 0.72 },
			{ V(0.5, 3.03, 1.46), 0.72 },
			{ V(0.05, 3.65, 1.34), 0.62 },
		}
		local main = nil
		for i, cn in canopy do
			local p = ell(b, "Leaves", V(cn[2], cn[2], cn[2]), CFrame.new(cn[1]), CAN[i])
			if i == 1 then
				main = p
			end
		end
		for _, f in { { 2, V(-0.3, 0.2, -1) }, { 1, V(0.35, 0.45, -1) }, { 3, V(0.5, -0.2, -0.85) } } do
			local cn = canopy[f[1]]
			local r = cn[2] * 0.5
			local p, n = surf(cn[1], V(r, r, r), f[2])
			ell(b, "Fruit", V(0.16, 0.16, 0.16), CFrame.new(p + n * 0.03), FRUIT, NEON)
		end
		glow(main, RGB(220, 255, 170), 0.4, 5)
	end

	----------------------------------------------------------------------
	-- 2 호수
	----------------------------------------------------------------------

	-- 진주 수달 (시크릿): 뒤로 기대 누워서 커다란 반짝 진주를 꼭 안은 갈색 수달, 발바닥이 앞으로
	PET_BUILDERS.PearlOtter = function(b)
		local BR = RGB(165, 115, 80)
		local BRD = RGB(120, 82, 58)
		local CR = RGB(245, 224, 192)
		local PAD = RGB(95, 65, 50)
		local PEARL = RGB(250, 246, 255)
		local B = V(0, 0.82, 0.12)
		local BS = V(0.86, 0.82, 0.8)
		ell(b, "Body", BS * 2, CFrame.new(B), BR)
		local BeS = V(0.64, 0.62, 0.55)
		ell(b, "Belly", BeS * 2, CFrame.new(B + V(0, -0.04, -(BS.Z - BeS.Z) - 0.05)), CR)
		local H = V(0, 2.1, 0.2)
		local HS = V(0.92, 0.8, 0.82)
		ell(b, "Head", HS * 2, CFrame.new(H), BR)

		-- 얼굴: 큰 눈, 볼터치, 크림색 볼 + 까만 코 + 입, 하얀 수염, 작은 동그란 귀
		for _, sx in SIDES do
			addEye(b, H, HS, sx * 0.38, 0.12, V(0.34, 0.44, 0.16), 0)
			local p, n = front(H, HS, sx * 0.66, -0.12)
			ell(b, "Blush", V(0.3, 0.16, 0.06), facing(p, n), BLUSH, nil, 0.1)
			local cp, cn = front(H, HS, sx * 0.2, -0.36)
			ell(b, "Cheek", V(0.56, 0.42, 0.34), facing(cp - cn * 0.08, cn), CR)
			for _, a in { 0.12, -0.12 } do
				local wp, wn = front(H, HS, sx * 0.52, -0.36 + a * 0.3)
				addPart(b, "Whisker", "Block", V(0.4, 0.03, 0.03), facing(wp + wn * 0.04, wn) * CFrame.Angles(0, 0, sx * a), RGB(250, 242, 228))
			end
			local ep, en = surf(H, HS, V(sx * 0.85, 0.5, 0.1))
			ell(b, "Ear", V(0.34, 0.32, 0.22), CFrame.new(ep + en * 0.06), BRD)
		end
		local np, nn = front(H, HS, 0, -0.2)
		ell(b, "Nose", V(0.22, 0.15, 0.11), facing(np + nn * 0.05, nn), RGB(55, 38, 34))
		local mp, mn = front(H, HS, 0, -0.4)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), MOUTH)

		-- 커다란 진주 (살짝 반짝 + 작은 하이라이트 하나)
		local P = V(0, 1.12, -0.8)
		local PR = 0.5
		local pearl = ell(b, "Pearl", V(PR, PR, PR) * 2, CFrame.new(P), PEARL)
		pearl.Reflectance = 0.2
		local gp, gn = surf(P, V(PR, PR, PR), V(-0.45, 0.55, -0.7))
		ell(b, "Gleam", V(0.15, 0.23, 0.05), facing(gp + gn * 0.005, gn) * CFrame.Angles(0, 0, -0.6), WHITE, NEON)
		-- 진주를 꼭 안은 팔
		for _, sx in SIDES do
			local sp = surf(B, BS, V(sx, 0.5, -0.4))
			local hand = P + V(sx * 0.4, 0.14, -0.24)
			link(b, "Arm", sp, hand, 0.3, 0.3, 0.12, BR)
			ell(b, "Paw", V(0.26, 0.24, 0.22), CFrame.new(hand), BRD)
		end
		-- 앞으로 들어 올린 뒷발 (발바닥이 보여요)
		for _, sx in SIDES do
			local fcf = CFrame.new(sx * 0.5, 0.34, -0.5) * CFrame.Angles(-0.25, 0, -sx * 0.2)
			ell(b, "Foot", V(0.42, 0.52, 0.34), fcf, BR)
			ell(b, "Pad", V(0.24, 0.28, 0.06), fcf * CFrame.new(0, 0.04, -0.155), PAD)
		end
		-- 납작한 수달 꼬리: 엉덩이에서 오른쪽 앞으로 바닥을 따라 감겨요
		link(b, "Tail", V(0.25, 0.22, 0.5), V(0.92, 0.22, 0.42), 0.44, 0.3, 0.3, BR)
		link(b, "Tail", V(0.92, 0.22, 0.42), V(1.12, 0.22, -0.1), 0.32, 0.22, 0.2, BRD)
		-- 머리의 분홍 조개 핀
		local hp, hn = surf(H, HS, V(0.55, 0.8, -0.35))
		local scf = facing(hp + hn * 0.06, hn) * CFrame.Angles(0, 0, -0.5)
		ell(b, "Shell", V(0.42, 0.36, 0.12), scf, RGB(255, 175, 195))
		ell(b, "ShellBase", V(0.16, 0.12, 0.1), scf * CFrame.new(0, -0.16, 0.02), RGB(240, 125, 160))
	end

	-- 달빛 백조 (천상): 하얀 백조, 머리에 은빛 초승달 왕관, 은은한 은빛 불빛, 살짝 들린 날개
	PET_BUILDERS.MoonSwan = function(b)
		local W = RGB(250, 251, 255)
		local W2 = RGB(234, 238, 250)
		local W3 = RGB(212, 222, 244)
		local BEAK = RGB(255, 165, 75)
		local FEET = RGB(240, 140, 70)
		local SILVER = RGB(190, 202, 228)
		local MOON = RGB(250, 222, 135)
		local B = V(0, 0.76, 0.25)
		local BS = V(0.98, 0.76, 1.1)
		ell(b, "Body", BS * 2, CFrame.new(B), W)
		-- S 자 목 + 둥근 머리
		local N0, N1, N2 = V(0, 1.15, -0.42), V(0, 1.62, -0.7), V(0, 2.02, -0.52)
		link(b, "Neck", N0, N1, 0.54, 0.54, 0.3, W)
		link(b, "Neck", N1, N2, 0.5, 0.5, 0.3, W)
		local H = V(0, 2.42, -0.48)
		local HS = V(0.78, 0.72, 0.72)
		local head = ell(b, "Head", HS * 2, CFrame.new(H), W)

		-- 얼굴
		local eyes = {}
		for _, sx in SIDES do
			table.insert(eyes, addEye(b, H, HS, sx * 0.3, 0.08, V(0.3, 0.4, 0.15), 0))
			local p, n = front(H, HS, sx * 0.52, -0.18)
			ell(b, "Blush", V(0.26, 0.14, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		lashes(b, eyes, 0.3 / 0.36)
		local bp, bn = front(H, HS, 0, -0.2)
		ell(b, "Beak", V(0.34, 0.22, 0.36), facing(bp + bn * 0.1, bn), BEAK)

		-- 살짝 들린 깃털 날개 + 뾰족 꼬리깃 + 작은 물갈퀴 발
		for _, sx in SIDES do
			local root = surf(B, BS, V(sx * 0.85, 0.5, 0.25))
			featherWing(b, root, sx, { { 68, 1.3, 0.48, W }, { 44, 1.25, 0.48, W2 }, { 20, 1.05, 0.44, W2 }, { -2, 0.82, 0.4, W3 } }, 0.75, 0.35, 0.14)
			ell(b, "Foot", V(0.44, 0.14, 0.52), CFrame.new(sx * 0.42, 0.07, 0), FEET)
		end
		local tp = surf(B, BS, V(0, 0.35, 1))
		for _, d in { V(0, 1, 0.55), V(0.4, 0.85, 0.6), V(-0.4, 0.85, 0.6) } do
			local u = d.Unit
			ell(b, "TailFeather", V(0.22, 0.55, 0.14), alongY(tp + u * 0.2, u), W2)
		end

		-- 초승달 왕관: 은 띠 + 세운 초승달 (작은 네온 조각 3개) + 은 뿔 3개
		local bandY = H.Y + HS.Y - 0.1
		local bz = H.Z + 0.02
		addPart(b, "CrownBand", "Cyl", V(0.18, 0.8, 0.8), CFrame.new(0, bandY, bz) * CFrame.Angles(0, 0, math.pi / 2), SILVER, METAL)
		local mcf = CFrame.new(0, bandY + 0.4, bz - 0.26) * CFrame.Angles(-0.15, 0, 0)
		for _, a in { -math.pi / 2, -math.pi / 2 + 0.95, -math.pi / 2 - 0.95 } do
			local tip = a ~= -math.pi / 2
			local size = if tip then V(0.34, 0.13, 0.1) else V(0.4, 0.2, 0.12)
			ell(b, "Moon", size, mcf * CFrame.new(0.32 * math.cos(a), 0.32 * math.sin(a), 0) * CFrame.Angles(0, 0, a + math.pi / 2), MOON, NEON)
		end
		for _, a in { 0, math.pi * 0.5, math.pi } do
			ell(b, "CrownTip", V(0.1, 0.26, 0.1), CFrame.new(math.cos(a) * 0.3, bandY + 0.17, bz + math.sin(a) * 0.3), SILVER, METAL)
		end
		glow(head, RGB(205, 220, 255), 0.3, 4.5)
	end

	-- 무지개 잉어 용 (이터널): 하얀 잉어 용, 주홍 무늬, 금 뿔과 긴 금 수염, 이마의 진주, 무지개 지느러미
	PET_BUILDERS.RainbowKoiDragon = function(b)
		local W = RGB(252, 250, 245)
		local RED = RGB(250, 110, 75)
		local GOLD = RGB(255, 205, 85)
		local BELLY = RGB(255, 240, 220)
		local PEARL = RGB(255, 236, 246)
		local RB = RAINBOW
		local c = chibi(b, { body = W, belly = BELLY, feet = RGB(240, 232, 225), HS = V(1.05, 0.95, 0.95), noMouth = true, eyeY = 0.1, blushX = 0.7, blushY = -0.18 })
		-- 잉어 입술 + 입
		local mp, mn = front(c.H, c.HS, 0, -0.38)
		local mcf = facing(mp + mn * 0.03, mn)
		ell(b, "Lips", V(0.3, 0.2, 0.12), mcf, RGB(255, 190, 185))
		ell(b, "Mouth", V(0.15, 0.09, 0.05), mcf * CFrame.new(0, 0, -0.05), MOUTH)
		-- 긴 금빛 수염: 입가에서 옆 아래로 늘어졌다가 끝이 살짝 위로
		for _, sx in SIDES do
			local p0 = mcf * V(sx * 0.13, 0.02, 0)
			local p1 = p0 + V(sx * 0.3, -0.34, -0.06)
			local p2 = p1 + V(sx * 0.3, -0.06, 0.24)
			link(b, "Whisker", p0, p1, 0.07, 0.07, 0.06, GOLD)
			link(b, "Whisker", p1, p2, 0.06, 0.06, 0.06, GOLD)
		end
		-- 금 뿔 (줄기 + 앞가지)
		for _, sx in SIDES do
			local hp = surf(c.H, c.HS, V(sx * 0.45, 0.9, 0.3))
			local d1 = V(sx * 0.35, 1, 0.4).Unit
			addPart(b, "Horn", "Cyl", V(0.62, 0.13, 0.13), alongX(hp + d1 * 0.22, d1), GOLD)
			local kp = hp + d1 * 0.32
			local d2 = V(sx * 0.3, 0.7, -0.6).Unit
			addPart(b, "Horn", "Cyl", V(0.32, 0.1, 0.1), alongX(kp + d2 * 0.13, d2), GOLD)
		end
		-- 이마의 진주 (작은 네온 + 약한 불빛)
		local fp, fn = front(c.H, c.HS, 0, 0.56)
		local pearl = ell(b, "Pearl", V(0.26, 0.26, 0.18), facing(fp + fn * 0.04, fn), PEARL, NEON)
		glow(pearl, RGB(255, 225, 240), 0.4, 5)
		-- 주홍 잉어 무늬
		patch(b, "Patch", c.H, c.HS, V(0, 1, -0.05), 0.8, 0.7, RED)
		patch(b, "Patch", c.H, c.HS, V(-0.85, 0.3, 0.45), 0.45, 0.38, RED)
		patch(b, "Patch", c.B, c.BS, V(0.85, 0.3, 0.45), 0.55, 0.48, RED)

		-- 무지개 지느러미: 볼(보라) · 가슴(파랑) · 등 줄(주황 노랑 초록) · 꼬리 부채(빨주노초파)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx, -0.1, 0.15))
			local d = V(sx, 0.5, 0.35).Unit
			ell(b, "Fin", V(0.36, 0.55, 0.1), alongY(p + d * 0.22, d), RB[6])
			local q = surf(c.B, c.BS, V(sx, 0.35, 0.35))
			local e = V(sx, 0.35, 0.55).Unit
			ell(b, "Fin", V(0.5, 0.75, 0.1), alongY(q + e * 0.3, e), RB[5])
		end
		for _, dd in { { c.H, c.HS, V(0, 0.75, 0.8), 0.55, RB[2] }, { c.H, c.HS, V(0, 0.05, 1), 0.5, RB[3] }, { c.B, c.BS, V(0, 0.35, 1), 0.45, RB[4] } } do
			local p, n = surf(dd[1], dd[2], dd[3])
			ell(b, "Fin", V(0.1, dd[4], 0.4), alongY(p + n * (dd[4] * 0.3), n), dd[5])
		end
		local tp = surf(c.B, c.BS, V(0, -0.3, 1))
		local t1 = tp + V(0, 0.3, 0.42)
		link(b, "Tail", tp - V(0, 0, 0.1), t1, 0.5, 0.5, 0.25, W)
		local t2 = t1 + V(0, 0.62, 0.2)
		link(b, "Tail", t1, t2, 0.36, 0.36, 0.2, W)
		local nBack = V(0, -0.35, 1).Unit
		for i = 1, 5 do
			local f = (i - 1) / 4
			local a = math.rad(-72 + 144 * f)
			local L = 1.25 - 0.3 * math.abs(a) / math.rad(72)
			local d = V(math.sin(a), math.cos(a), math.cos(a) * 0.35).Unit
			ell(b, "TailFin", V(0.42, L, 0.1), CFrame.fromMatrix(t2 + d * (L * 0.45), d:Cross(nBack).Unit, d), RB[i])
		end
	end

	----------------------------------------------------------------------
	-- 3 정글
	----------------------------------------------------------------------

	-- 무지개 카멜레온 (시크릿): 동글 카멜레온, 몸에 무지개 줄무늬, 튀어나온 큰 눈, 보라 볏, 무지개 돌돌 꼬리
	PET_BUILDERS.RainbowChameleon = function(b)
		local SKIN = RGB(150, 225, 150)
		local SKIN_D = RGB(115, 195, 125)
		local RB = RAINBOW
		local BS = V(0.88, 0.78, 0.88)
		local c = chibi(b, { body = SKIN, BS = BS, HS = V(1.05, 0.95, 0.98), feet = SKIN_D, arms = SKIN_D, noEyes = true, noMouth = true, blushX = 0.66, blushY = -0.42 })
		-- 툭 튀어나온 동그란 눈두덩 + 큰 반짝 눈
		for _, sx in SIDES do
			local bc = c.H + V(sx * 0.55, 0.12, -0.6)
			local bs = V(0.38, 0.38, 0.38)
			ell(b, "EyeBulb", bs * 2, CFrame.new(bc), SKIN)
			table.insert(c.eyes, addEye(b, bc, bs, 0, 0.02, V(0.36, 0.44, 0.14), 0))
		end
		local mp, mn = front(c.H, c.HS, 0, -0.42)
		ell(b, "Mouth", V(0.42, 0.07, 0.06), facing(mp, mn), MOUTH)
		for _, sx in SIDES do
			local np, nn = front(c.H, c.HS, sx * 0.1, -0.22)
			ell(b, "Nostril", V(0.06, 0.05, 0.04), facing(np, nn), darker(SKIN, 0.4))
		end
		-- 머리 위 뒤로 누운 보라 볏
		local cp, cn = surf(c.H, c.HS, V(0, 1, 0.55))
		ell(b, "Crest", V(0.18, 0.8, 1.1), CFrame.new(cp + cn * 0.1) * CFrame.Angles(0.55, 0, 0), RB[6])
		-- 몸 둘레 무지개 줄 (빨주노초파): 몸 단면에 딱 맞는 납작한 원기둥 고리
		for i, dy in { 0.42, 0.18, -0.06, -0.3, -0.54 } do
			local r = BS.X * math.sqrt(1 - (dy / BS.Y) ^ 2) + 0.025
			addPart(b, "Stripe", "Cyl", V(0.15, r * 2, r * 2), CFrame.new(c.B.X, c.B.Y + dy, c.B.Z) * CFrame.Angles(0, 0, math.pi / 2), RB[i])
		end
		-- 돌돌 말린 무지개 꼬리: 오른쪽 뒤에서 앞을 보고 말려요 (마디 6개, 빨강 → 보라)
		local C = V(0.62, 0.78, 0.92)
		local U = V(0.87, 0, 0.42).Unit
		local pts = {}
		local n = 7
		for i = 0, n - 1 do
			local f = i / (n - 1)
			local phi = math.rad(200 + 400 * f)
			local r = 0.5 - 0.36 * f
			table.insert(pts, C + U * (r * math.cos(phi)) + Vector3.yAxis * (r * math.sin(phi)))
		end
		for i = 1, n - 1 do
			local w = 0.4 - 0.22 * (i - 1) / (n - 2)
			link(b, "Tail", pts[i], pts[i + 1], w, w, w * 0.7, RB[i])
		end
	end

	-- 황금 재규어 (천상): 금빛 아기 재규어, 짙은 갈색 꽃무늬 점, 보석 목걸이 (가운데 보석만 살짝 빛나요)
	PET_BUILDERS.GoldenJaguar = function(b)
		local GOLDF = RGB(250, 195, 70)
		local CR = RGB(255, 242, 210)
		local ROS = RGB(105, 65, 35)
		local ROSIN = RGB(225, 145, 45)
		local COLLAR = RGB(120, 60, 170)
		local GEM = RGB(70, 225, 185)
		local RUBY = RGB(255, 80, 120)
		local GOLDM = RGB(255, 210, 90)
		local c = chibi(b, { body = GOLDF, belly = CR, feet = CR, eyeY = 0.06, noMouth = true, blushY = -0.22 })
		for _, nm in { "Body", "Head" } do
			local p = partNamed(b, nm)
			if p then
				p.Reflectance = 0.06
			end
		end
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.16, -0.33)
			ell(b, "Muzzle", V(0.42, 0.32, 0.28), facing(p - n * 0.06, n), CR)
			local wp, wn = front(c.H, c.HS, sx * 0.6, -0.36)
			addPart(b, "Whisker", "Block", V(0.42, 0.035, 0.035), facing(wp + wn * 0.03, wn) * CFrame.Angles(0, 0, sx * 0.1), ROS)
		end
		smallNose(c, -0.2, V(0.18, 0.12, 0.08), RGB(205, 110, 110), 0.04)
		local mp, mn = front(c.H, c.HS, 0, -0.43)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.025, mn), MOUTH)
		roundEars(c, 0.62, 0.8, 0.46, GOLDF, ROS)

		-- 재규어 꽃무늬 (진한 고리 + 주황 속)
		local function rosette(C, S, dir, s)
			local p, n = surf(C, S, dir)
			local R = (S.X + S.Y + S.Z) / 3
			stick(b, "Rosette", p, n, 0.3 * s, 0.26 * s, R, ROS)
			stick(b, "Rosette", p + n * 0.012, n, 0.15 * s, 0.12 * s, R, ROSIN)
		end
		rosette(c.H, c.HS, V(0.5, 0.7, -0.5), 0.9)
		rosette(c.H, c.HS, V(-0.5, 0.7, -0.5), 0.9)
		rosette(c.H, c.HS, V(0, 0.7, 0.8), 1.1)
		rosette(c.B, c.BS, V(0.85, 0.25, 0.4), 1.15)
		rosette(c.B, c.BS, V(-0.8, 0.1, 0.5), 1.15)

		-- 보석 목걸이: 보라 띠 + 금 받침 + 마름모 보석 (작은 네온) + 양옆 루비
		local ny = c.B.Y + c.BS.Y - 0.2
		addPart(b, "Collar", "Cyl", V(0.2, 1.62, 1.62), CFrame.new(0, ny, 0) * CFrame.Angles(0, 0, math.pi / 2), COLLAR)
		ell(b, "GemSetting", V(0.34, 0.34, 0.08), CFrame.new(0, ny - 0.08, -0.83), GOLDM, METAL)
		addPart(b, "Gem", "Block", V(0.2, 0.2, 0.1), CFrame.new(0, ny - 0.08, -0.88) * CFrame.Angles(0, 0, math.pi / 4), GEM, NEON)
		for _, sx in SIDES do
			local a = sx * 0.55
			local dir = V(math.sin(a), 0, -math.cos(a))
			local ruby = ell(b, "Gem", V(0.14, 0.14, 0.08), facing(V(0, ny, 0) + dir * 0.81, dir), RUBY)
			ruby.Reflectance = 0.15
		end

		-- 긴 꼬리 (위로 휘어요) + 진한 끝
		local tp = surf(c.B, c.BS, V(0, -0.3, 1))
		local t1 = tp + V(0.1, 0.2, 0.5)
		local t2 = t1 + V(0.2, 0.65, 0.2)
		link(b, "Tail", tp, t1, 0.3, 0.3, 0.2, GOLDF)
		link(b, "Tail", t1, t2, 0.27, 0.27, 0.2, GOLDF)
		ell(b, "TailTip", V(0.3, 0.36, 0.3), CFrame.new(t2 + (t2 - t1).Unit * 0.1), ROS)
		glow(partNamed(b, "Body"), RGB(255, 215, 120), 0.3, 4)
	end

	-- 에메랄드 용 (이터널): 에메랄드빛 아기 용, 잎사귀 날개, 가슴에 은은하게 빛나는 보석, 등에 수정 가시
	PET_BUILDERS.EmeraldDragon = function(b)
		local EM = RGB(45, 190, 115)
		local EMD = RGB(32, 150, 92)
		local BELLY = RGB(205, 245, 205)
		local LINE = RGB(150, 215, 160)
		local LEAF1 = RGB(115, 210, 95)
		local LEAF2 = RGB(80, 180, 85)
		local VEIN = RGB(215, 245, 165)
		local GOLD = RGB(255, 205, 80)
		local GEM = RGB(60, 225, 140)
		local CRY = RGB(170, 245, 200)
		local c = chibi(b, { body = EM, belly = BELLY, feet = EMD, arms = EM, eyeY = 0.04 })
		for _, nm in { "Body", "Head" } do
			local p = partNamed(b, nm)
			if p then
				p.Reflectance = 0.05
			end
		end
		-- 금 뿔 + 콧구멍 + 송곳니
		for _, sx in SIDES do
			local d = V(sx * 0.35, 1, 0.45)
			local p = surf(c.H, c.HS, V(sx * 0.45, 1, 0.1))
			ell(b, "Horn", V(0.2, 0.58, 0.2), alongY(p + d.Unit * 0.18, d), GOLD)
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.2)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(EM, 0.35))
		end
		local tp0, tn0 = front(c.H, c.HS, 0.08, -0.37)
		ell(b, "Tooth", V(0.07, 0.09, 0.05), facing(tp0 + tn0 * 0.01, tn0), WHITE)
		-- 머리 옆 뾰족 지느러미 귀 (진한 에메랄드)
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx, 0.3, 0.15))
			blade(b, "Ear", p - n * 0.1, V(sx, 0.55, 0.25), Vector3.yAxis, 0.36, 0.58, 0.08, EMD)
		end
		-- 배 비늘 줄
		for _, y in { -0.06, -0.3 } do
			local p, n = front(c.BeC, c.BeS, 0, y)
			stick(b, "BellyLine", p, n, 0.46, 0.07, 0.6, LINE)
		end
		-- 가슴 보석: 금 받침 + 마름모 유리 보석 + 속의 작은 네온 (약한 초록 불빛)
		local gp, gn = front(c.BeC, c.BeS, 0, 0.2)
		local gcf = facing(gp + gn * 0.02, gn)
		ell(b, "GemSetting", V(0.44, 0.44, 0.08), gcf, GOLD, METAL)
		addPart(b, "Gem", "Block", V(0.26, 0.26, 0.14), gcf * CFrame.new(0, 0, -0.05) * CFrame.Angles(0, 0, math.pi / 4), GEM, GLASS, 0.3)
		local core = ell(b, "GemCore", V(0.13, 0.13, 0.1), gcf * CFrame.new(0, 0, -0.06), RGB(150, 255, 200), NEON)
		glow(core, RGB(120, 255, 170), 0.4, 5)
		-- 잎사귀 날개: 큰 잎 + 작은 잎, 가운데 잎맥
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.55, 0.6, 0.7))
			local sweep = 0.45
			local nrm = V(-math.sin(sweep), 0, sx * math.cos(sweep))
			for _, L in { { 40, 1.5, 0.62, LEAF1 }, { 5, 1.1, 0.5, LEAF2 } } do
				local th = math.rad(L[1])
				local d = V(sx * math.cos(th) * math.cos(sweep), math.sin(th), math.cos(th) * math.sin(sweep) + math.sin(th) * 0.3).Unit
				local cf = CFrame.fromMatrix(root + d * (L[2] * 0.45), d:Cross(nrm).Unit, d)
				ell(b, "Wing", V(L[3], L[2], 0.07), cf, L[4])
				ell(b, "WingVein", V(0.05, L[2] * 0.85, 0.09), cf, VEIN)
			end
		end
		-- 등의 수정 가시 3개 (유리, 살짝 투명)
		for _, s in { { c.H, c.HS, V(0, 0.45, 1), 0.36 }, { c.B, c.BS, V(0, 0.55, 1), 0.32 }, { c.B, c.BS, V(0, 0.05, 1), 0.28 } } do
			local p, n = surf(s[1], s[2], s[3])
			blade(b, "Spike", p - n * 0.05, n, V(0, -n.Z, n.Y), 0.26, s[4], 0.12, CRY, GLASS, 0.15)
		end
		-- 꼬리 + 끝 잎사귀
		local tp = surf(c.B, c.BS, V(0, -0.4, 1))
		local d1 = V(0, 0.15, 1).Unit
		local t1 = tp + d1 * 0.35
		ell(b, "Tail", V(0.5, 0.5, 0.9), CFrame.lookAt(t1, t1 + d1), EM)
		local d2 = V(0, 0.6, 1).Unit
		local t2 = t1 + d1 * 0.4 + d2 * 0.3
		ell(b, "Tail", V(0.3, 0.3, 0.65), CFrame.lookAt(t2, t2 + d2), EM)
		local t3 = t2 + d2 * 0.4
		ell(b, "TailLeaf", V(0.36, 0.52, 0.08), alongY(t3 + d2 * 0.12, d2), LEAF1)
	end

	----------------------------------------------------------------------
	-- 4 겨울 산
	----------------------------------------------------------------------

	-- 수정 펭귄 (시크릿): 남색 펭귄, 머리에 얼음 수정 왕관, 서리 낀 볼 (작은 하얀 반짝이)
	PET_BUILDERS.CrystalPenguin = function(b)
		local N = RGB(60, 82, 135)
		local ICE = RGB(175, 228, 255)
		local ORANGE = RGB(255, 160, 50)
		local FROST = RGB(150, 200, 245)
		local c = chibi(b, {
			body = N,
			belly = RGB(250, 252, 255),
			feet = ORANGE,
			noArms = true,
			noMouth = true,
			face = { color = RGB(255, 255, 255), semi = V(0.82, 0.72, 0.6), offset = V(0, -0.12, -0.42) },
			eyeX = 0.34,
			eyeY = 0.1,
			blushX = 0.58,
			blushY = -0.18,
		})
		-- 서리 볼: 얼음빛 분홍 볼터치 + 작은 하얀 서리 반짝이
		for _, p in b.parts do
			if p.Name == "Blush" then
				p.Color = RGB(205, 205, 255)
			end
		end
		for _, sx in SIDES do
			local p, n = front(c.FC, c.FS, sx * 0.66, -0.1)
			ell(b, "Frost", V(0.09, 0.09, 0.05), facing(p + n * 0.02, n), WHITE, NEON)
		end
		local p, n = front(c.FC, c.FS, 0, -0.18)
		ell(b, "Beak", V(0.3, 0.18, 0.28), facing(p + n * 0.06, n), ORANGE)
		-- 끝이 얼음빛인 날개
		for _, sx in SIDES do
			local fp, fn = surf(c.B, c.BS, V(sx, 0.15, 0))
			local fcf = CFrame.new(fp + fn * 0.04) * CFrame.Angles(0, 0, sx * 0.3)
			ell(b, "Flipper", V(0.22, 0.85, 0.5), fcf, N)
			ell(b, "FlipperTip", V(0.2, 0.34, 0.42), fcf * CFrame.new(0, -0.3, 0), ICE)
		end
		-- 배의 눈꽃 (막대 3개)
		local sp, sn = front(c.BeC, c.BeS, 0, 0.05)
		local scf = facing(sp + sn * 0.02, sn)
		for i = 0, 2 do
			addPart(b, "Snowflake", "Block", V(0.36, 0.05, 0.04), scf * CFrame.Angles(0, 0, math.pi / 2 + i * math.pi / 3), FROST)
		end
		-- 얼음 수정 왕관: 정수리를 빙 둘러 선 수정 5개 (앞이 제일 커요) + 앞 수정 밑의 작은 네온 보석
		local crown = { { 0, 0.64, 0.3 }, { 0.75, 0.48, 0.26 }, { -0.75, 0.48, 0.26 }, { 1.9, 0.38, 0.24 }, { -1.9, 0.38, 0.24 } }
		for _, k in crown do
			local a = k[1]
			local dir = V(math.sin(a) * 0.55, 0.83, -math.cos(a) * 0.55)
			local cp, cn = surf(c.H, c.HS, dir)
			local up = (cn + V(0, 1.2, 0)).Unit
			blade(b, "Crystal", cp - cn * 0.06, up, V(math.cos(a), 0, math.sin(a)), k[3], k[2], 0.18, ICE, GLASS, 0.1)
		end
		local gp, gn = surf(c.H, c.HS, V(0, 0.83, -0.55))
		ell(b, "CrownGem", V(0.13, 0.13, 0.08), facing(gp + gn * 0.03, gn), RGB(140, 215, 255), NEON)
		local top = c.H + V(0, c.HS.Y, 0)
		ell(b, "Tuft", V(0.14, 0.34, 0.14), CFrame.new(top + V(0.05, 0.07, 0.05)) * CFrame.Angles(0, 0, -0.4), N)
	end

	-- 오로라 늑대 (천상): 하얀 아기 늑대, 목과 뒤통수를 감싼 오로라 갈기 (민트 → 청록 → 파랑 → 보라)
	PET_BUILDERS.AuroraWolf = function(b)
		local W = RGB(248, 250, 255)
		local GR = RGB(205, 212, 232)
		local NOSE = RGB(55, 55, 78)
		local AUR = { RGB(120, 240, 200), RGB(95, 215, 228), RGB(120, 170, 255), RGB(165, 135, 255), RGB(205, 130, 240) }
		local c = chibi(b, { body = W, belly = WHITE, feet = GR, arms = W, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		muzzle(c, V(0.6, 0.4, 0.42), WHITE, NOSE, -0.32)
		pointyEars(c, 0.5, 0.86, 0.56, 0.86, 0.15, 0.22, W, AUR[1])
		-- 오로라 갈기: 목둘레 복슬 깃 (앞 민트 → 옆 청록 → 뒤 파랑) + 뒤통수를 타고 올라가는 털 (파랑 → 보라 → 분홍 보라)
		-- 가슴 복슬 털: 아래로 늘어진 털 뭉치 3개 (가운데가 제일 길어요)
		ell(b, "Mane", V(0.5, 0.72, 0.42), CFrame.new(0, 1.28, -0.72) * CFrame.Angles(-0.25, 0, 0), AUR[1])
		for _, sx in SIDES do
			ell(b, "Mane", V(0.48, 0.6, 0.42), CFrame.new(sx * 0.36, 1.36, -0.66) * CFrame.Angles(-0.2, 0, sx * 0.35), AUR[1]:Lerp(AUR[2], 0.4))
		end
		for _, sx in SIDES do
			ell(b, "Mane", V(0.5, 0.56, 1.1), CFrame.new(sx * 0.72, 1.45, -0.05) * CFrame.Angles(0, 0, sx * 0.15), AUR[2])
		end
		ell(b, "Mane", V(1.2, 0.56, 0.52), CFrame.new(0, 1.5, 0.62), AUR[3])
		for _, m in { { V(0, -0.15, 1), AUR[3] }, { V(0, 0.4, 0.92), AUR[4] }, { V(0, 0.85, 0.55), AUR[5] } } do
			local p, n = surf(c.H, c.HS, m[1])
			local t = V(0, n.Z, -n.Y)
			ell(b, "Mane", V(0.56, 0.42, 0.78), CFrame.lookAt(p + n * 0.06, p + n * 0.06 + t), m[2])
		end
		-- 큰 복슬 꼬리 (하양 → 청록 → 보라 끝)
		local tp = surf(c.B, c.BS, V(0, -0.2, 1))
		local td = V(0, 0.6, 1).Unit
		local tc = tp + td * 0.5
		ell(b, "Tail", V(0.62, 0.62, 1.2), CFrame.lookAt(tc, tc + td), W)
		ell(b, "TailTip", V(0.5, 0.5, 0.5), CFrame.new(tc + td * 0.52), AUR[2])
		ell(b, "TailTip", V(0.32, 0.32, 0.32), CFrame.new(tc + td * 0.78), AUR[4])
		-- 이마의 작은 마름모 별 (네온 민트)
		local fp, fn = front(c.H, c.HS, 0, 0.56)
		addPart(b, "Mark", "Block", V(0.16, 0.16, 0.05), facing(fp + fn * 0.01, fn) * CFrame.Angles(0, 0, math.pi / 4), AUR[1], NEON)
		glow(partNamed(b, "Body"), RGB(150, 240, 220), 0.3, 4.5)
	end

	-- 얼음 불사조 (이터널): 얼음빛 불사조, 머리에 수정 볏, 큰 깃털 날개, 뒤로 펼친 수정 꼬리깃
	PET_BUILDERS.IcePhoenix = function(b)
		local ICE = RGB(140, 200, 250)
		local ICE2 = RGB(180, 222, 255)
		local PALE = RGB(228, 244, 255)
		local CRY = RGB(175, 235, 255)
		local CRY2 = RGB(205, 245, 255)
		local c = chibi(b, { body = ICE, head = ICE2, belly = PALE, feet = RGB(195, 210, 235), noArms = true, noMouth = true, eyeY = 0.02 })
		lashes(b, c.eyes)
		local p, n = front(c.H, c.HS, 0, -0.24)
		ell(b, "Beak", V(0.28, 0.2, 0.28), facing(p + n * 0.06, n), RGB(240, 228, 190))
		-- 머리 위 수정 볏 3개 (유리, 살짝 투명)
		for i, d in { V(0, 1, 0.3), V(0.4, 0.9, 0.4), V(-0.4, 0.9, 0.4) } do
			local cp, cn = surf(c.H, c.HS, d)
			blade(b, "Crest", cp - cn * 0.06, d, Vector3.xAxis, 0.26, if i == 1 then 0.75 else 0.55, 0.12, CRY, GLASS, 0.15)
		end
		-- 이마 보석 (작은 네온 마름모)
		local gp, gn = front(c.H, c.HS, 0, 0.5)
		addPart(b, "Gem", "Block", V(0.15, 0.15, 0.06), facing(gp + gn * 0.01, gn) * CFrame.Angles(0, 0, math.pi / 4), RGB(150, 230, 255), NEON)
		-- 볼 옆 작은 깃털
		for _, sx in SIDES do
			local fp = surf(c.H, c.HS, V(sx, 0.1, 0.2))
			local d = V(sx, 0.6, 0.4).Unit
			ell(b, "Feather", V(0.2, 0.44, 0.14), alongY(fp + d * 0.14, d), PALE)
		end
		-- 큰 깃털 날개
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.7, 0.4, 0.55))
			featherWing(b, root, sx, { { 70, 1.3, 0.46, ICE }, { 45, 1.25, 0.46, ICE2 }, { 20, 1.05, 0.42, ICE2 }, { -4, 0.8, 0.38, PALE } }, 0.35, 0.3, 0.13)
		end
		-- 수정 꼬리깃 5개 (유리 칼날, 가운데가 제일 길어요)
		local tp = surf(c.B, c.BS, V(0, -0.1, 1))
		ell(b, "TailBase", V(0.5, 0.42, 0.4), CFrame.new(tp + V(0, 0.02, 0.05)), ICE)
		for i, t in { { V(0, 1.1, 1), 1.6 }, { V(0.5, 0.85, 1), 1.4 }, { V(-0.5, 0.85, 1), 1.4 }, { V(1, 0.5, 0.85), 1.15 }, { V(-1, 0.5, 0.85), 1.15 } } do
			local d = t[1].Unit
			blade(b, "TailFeather", tp + d * 0.1, d, d:Cross(Vector3.yAxis), 0.36, t[2], 0.1, if i == 1 then CRY2 else CRY, GLASS, 0.2)
		end
		glow(partNamed(b, "Body"), RGB(160, 220, 255), 0.4, 5)
	end
end
