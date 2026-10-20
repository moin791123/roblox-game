-- v3 새 펫 모델 (PetModels/init.luau 가 불러서 등록)
-- 캔디: 젤리 용 / 사탕 유니콘 / 쿠키 왕 · 구름: 구름 강아지 / 아기 구름 / 페가수스 / 천사 토끼 · 우주: 우주곰 / 혜성 여우
return function(Kit, PET_BUILDERS, _EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, addEye, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.addEye, Kit.chibi, Kit.SIDES
	local addPart, darker, alongX, alongY, tri, muzzle, smallNose, pointyEars, roundEars = Kit.addPart, Kit.darker, Kit.alongX, Kit.alongY, Kit.tri, Kit.muzzle, Kit.smallNose, Kit.pointyEars, Kit.roundEars
	local WHITE, EYE, BLUSH, MOUTH, RAINBOW = Kit.WHITE, Kit.EYE, Kit.BLUSH, Kit.MOUTH, Kit.RAINBOW
	local NEON = Enum.Material.Neon
	local METAL = Enum.Material.Metal

	-- 속눈썹 (유니콘 스타일)
	local function lashes(b, c)
		for i, cf in c.eyes do
			local sx = if i == 1 then -1 else 1
			addPart(b, "Lash", "Block", V(0.14, 0.04, 0.04), cf * CFrame.new(sx * 0.19, 0.2, -0.03) * CFrame.Angles(0, 0, sx * 0.6), EYE)
		end
	end

	-- 깃털 날개: root 에서 바깥/위로 부채꼴로 펼친 깃털들. f = { 각도(도, 수평 바깥 = 0), 길이, 폭, 색 }
	-- sweep = 바깥 끝이 뒤로 젖혀지는 정도, lean = 위로 갈수록 뒤로 눕는 정도
	local function featherWing(b, root, sx, feathers, sweep, lean, thick)
		local nrm = V(-math.sin(sweep), 0, sx * math.cos(sweep))
		for _, f in feathers do
			local th = math.rad(f[1])
			local d = V(sx * math.cos(th) * math.cos(sweep), math.sin(th), math.cos(th) * math.sin(sweep) + math.sin(th) * lean).Unit
			local xv = d:Cross(nrm).Unit
			ell(b, "Wing", V(f[3], f[2], thick), CFrame.fromMatrix(root + d * (f[2] * 0.42), xv, d), f[4])
		end
	end

	-- Body 에 액세서리 위치 Attachment (AccHead / AccFace / AccNeck / AccBack) 추가
	local function attach(b, name, worldPos)
		for _, p in b.parts do
			if p.Name == "Body" then
				local a = Instance.new("Attachment")
				a.Name = name
				a.Position = p.CFrame:PointToObjectSpace(worldPos)
				a.Parent = p
				return
			end
		end
	end

	-- 원기둥 n 개로 만든 고리 (수평, tilt = X 축 기울기). 바깥 모서리가 딱 맞게 조금씩 길게
	local function ring(b, name, center, R, n, d, col, mat, tilt)
		local tf = CFrame.new(center) * CFrame.Angles(tilt, 0, 0)
		local half = math.pi / n
		local len = 2 * R * math.sin(half) + d * math.tan(half)
		for i = 0, n - 1 do
			local a = (2 * i + 1) * half
			local pos = tf * V(R * math.cos(half) * math.cos(a), 0, R * math.cos(half) * math.sin(a))
			local dir = tf:VectorToWorldSpace(V(-math.sin(a), 0, math.cos(a)))
			addPart(b, name, "Cyl", V(len, d, d), alongX(pos, dir), col, mat)
		end
	end

	----------------------------------------------------------------------
	-- 캔디 랜드
	----------------------------------------------------------------------

	-- 젤리 용: 반투명 빨강-주황 젤리 아기 용, 노란 젤리 뿔/가시, 짧은 날개, 설탕 반짝이
	-- (Glass 는 겹친 반투명 파트를 서로 안 그려서 젤리곰처럼 SmoothPlastic + 투명도 + 반사로 표현)
	PET_BUILDERS.GummyDragon = function(b)
		local R = RGB(255, 100, 60)
		local Or = RGB(255, 165, 70)
		local Yl = RGB(255, 215, 95)
		local c = chibi(b, { body = R, belly = Or, feet = R, arms = R, eyeY = 0.04, blushY = -0.26 })
		for _, sx in SIDES do
			local d = V(sx * 0.35, 1, 0.4)
			local p = surf(c.H, c.HS, V(sx * 0.45, 1, 0.1))
			ell(b, "Horn", V(0.24, 0.46, 0.24), alongY(p + d.Unit * 0.14, d), Yl)
			local np, nn = front(c.H, c.HS, sx * 0.12, -0.18)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(R, 0.35))
		end
		-- 짧고 동그란 날개 (등 위쪽에서 옆/위/뒤로)
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.55, 0.5, 0.7))
			local span = V(sx, 0.8, 0.5).Unit
			local chord = Vector3.zAxis:Cross(span).Unit
			ell(b, "Wing", V(0.85, 0.6, 0.14), CFrame.fromMatrix(root + span * 0.3, span, chord), Or)
		end
		-- 등 가시
		for _, s in { { c.H, c.HS, V(0, 0.4, 1) }, { c.B, c.BS, V(0, 0.55, 1) } } do
			local sp, sn = surf(s[1], s[2], s[3])
			ell(b, "Spike", V(0.16, 0.3, 0.26), alongY(sp + sn * 0.08, sn), Yl)
		end
		-- 꼬리 (두 마디 + 노란 끝)
		local tp = surf(c.B, c.BS, V(0, -0.4, 1))
		local d1 = V(0, 0.15, 1).Unit
		local t1 = tp + d1 * 0.35
		ell(b, "Tail", V(0.5, 0.5, 0.9), CFrame.lookAt(t1, t1 + d1), R)
		local d2 = V(0, 0.6, 1).Unit
		local t2 = t1 + d1 * 0.4 + d2 * 0.3
		ell(b, "Tail", V(0.3, 0.3, 0.65), CFrame.lookAt(t2, t2 + d2), R)
		ell(b, "TailTip", V(0.16, 0.36, 0.3), alongY(t2 + d2 * 0.36, d2), Yl)
		-- 젤리 느낌: 몸 파트만 반투명 + 반사 (눈/볼터치/입은 그대로)
		local gummy = { Body = true, Head = true, Belly = true, Foot = true, Arm = true, Horn = true, Wing = true, Spike = true, Tail = true, TailTip = true }
		for _, p in b.parts do
			if gummy[p.Name] then
				p.Transparency = 0.25
				p.Reflectance = 0.18
			end
		end
		-- 설탕 알갱이 (작은 네온 큐브)
		local sugar = {
			{ c.H, c.HS, V(-0.55, 0.62, -0.55) },
			{ c.H, c.HS, V(0.66, 0.5, -0.56) },
			{ c.H, c.HS, V(-0.12, 0.95, -0.3) },
			{ c.B, c.BS, V(0.62, 0.1, -0.78) },
			{ c.B, c.BS, V(-0.78, -0.25, -0.6) },
		}
		for i, s in sugar do
			local p, n = surf(s[1], s[2], s[3])
			addPart(b, "Sugar", "Block", V(0.11, 0.11, 0.11), facing(p + n * 0.02, n) * CFrame.Angles(0, 0, 0.3 + i * 0.6), WHITE, NEON)
		end
		-- 윤기 하이라이트
		local hp, hn = surf(c.H, c.HS, V(-0.42, 0.45, -0.75))
		ell(b, "Gloss", V(0.18, 0.5, 0.06), facing(hp + hn * 0.02, hn) * CFrame.Angles(0, 0, -0.5), WHITE, nil, 0.3)
		local bp, bn = surf(c.B, c.BS, V(-0.55, 0.45, -0.7))
		ell(b, "Gloss", V(0.12, 0.34, 0.06), facing(bp + bn * 0.02, bn) * CFrame.Angles(0, 0, -0.5), WHITE, nil, 0.3)
	end

	-- 사탕 유니콘: 파스텔 분홍 유니콘, 빨강-하양 사탕 지팡이 줄무늬 뿔, 솜사탕(분홍/하늘) 갈기와 꼬리
	PET_BUILDERS.CandyUnicorn = function(b)
		local PINK = RGB(255, 205, 228)
		local CC_PINK = RGB(255, 150, 205)
		local CC_BLUE = RGB(165, 215, 255)
		local RED = RGB(230, 45, 75)
		local c = chibi(b, { body = PINK, feet = RGB(240, 135, 180), eyeY = 0, blushY = -0.3 })
		lashes(b, c)
		-- 뿔: 하얀 뿔에 비스듬한 빨간 띠 3줄 = 사탕 지팡이 나선
		local hp = surf(c.H, c.HS, V(0, 1, -0.4))
		local hd = V(0, 1, -0.35).Unit
		local hc = hp + hd * 0.36
		local hl = 0.44
		ell(b, "Horn", V(0.3, hl * 2, 0.3), alongY(hc, hd), RGB(255, 252, 250))
		-- 기울어진 원판의 테두리가 뿔 표면 밖으로 0.01~0.04 나오는 지름 (빈틈 없는 띠)
		local tilt = 0.35
		local axis = (hd * math.cos(tilt) + Vector3.xAxis * math.sin(tilt)).Unit
		for _, h in { -0.22, 0, 0.2 } do
			addPart(b, "HornStripe", "Cyl", V(0.07, 0.355, 0.355), alongX(hc + hd * h, axis), RED)
		end
		pointyEars(c, 0.6, 0.8, 0.36, 0.46, 0.12, 0.35, PINK)
		-- 솜사탕 갈기
		local mane = {
			{ V(0.28, 1, -0.28), 0.5, CC_PINK },
			{ V(-0.22, 0.95, 0.25), 0.58, CC_BLUE },
			{ V(0.2, 0.7, 0.75), 0.6, CC_PINK },
			{ V(-0.15, 0.2, 1), 0.6, CC_BLUE },
			{ V(0.1, -0.3, 0.95), 0.52, CC_PINK },
		}
		for _, m in mane do
			local mp, mn = surf(c.H, c.HS, m[1])
			ell(b, "Mane", V(m[2], m[2], m[2]), CFrame.new(mp + mn * 0.06), m[3], nil, 0.08)
		end
		-- 솜사탕 꼬리
		local tp = surf(c.B, c.BS, V(0, 0, 1))
		ell(b, "Tail", V(0.48, 0.48, 0.48), CFrame.new(tp + V(0, 0, 0.12)), CC_PINK, nil, 0.08)
		ell(b, "Tail", V(0.42, 0.42, 0.42), CFrame.new(tp + V(0, -0.2, 0.42)), CC_BLUE, nil, 0.08)
		ell(b, "Tail", V(0.36, 0.36, 0.36), CFrame.new(tp + V(0, -0.42, 0.56)), CC_PINK, nil, 0.08)
	end

	-- 쿠키 왕: 통통한 진저브레드 쿠키맨, 하얀 아이싱 (웃는 입/손목/발목), 젤리 단추 3개, 작은 금관, 막대사탕 홀
	PET_BUILDERS.CookieKing = function(b)
		local CK = RGB(205, 128, 68)
		local ICING = RGB(255, 252, 245)
		local GOLD = RGB(255, 205, 70)
		-- 다리 (바닥 y = 0)
		for _, sx in SIDES do
			ell(b, "Leg", V(0.64, 0.95, 0.68), CFrame.new(sx * 0.38, 0.475, 0), CK)
			-- 발목 아이싱 고리
			addPart(b, "Icing", "Cyl", V(0.07, 0.66, 0.66), CFrame.new(sx * 0.38, 0.275, 0) * CFrame.Angles(0, 0, math.pi / 2), ICING)
		end
		local B, BS = V(0, 1.35, 0), V(0.72, 0.78, 0.37)
		ell(b, "Body", BS * 2, CFrame.new(B), CK)
		-- 팔 (살짝 들어 올림) + 손목 아이싱 고리
		for _, sx in SIDES do
			local acf = CFrame.new(sx * 0.88, 1.68, 0) * CFrame.Angles(0, 0, sx * 0.32)
			ell(b, "Arm", V(0.95, 0.56, 0.6), acf, CK)
			addPart(b, "Icing", "Cyl", V(0.07, 0.55, 0.55), acf * CFrame.new(sx * 0.27, 0, 0), ICING)
		end
		local H, HS = V(0, 2.78, 0), V(0.9, 0.82, 0.4)
		ell(b, "Head", HS * 2, CFrame.new(H), CK)
		-- 얼굴: 눈 + 분홍 볼 + 아이싱 웃는 입 (3 조각 U 자)
		for _, sx in SIDES do
			addEye(b, H, HS, sx * 0.34, 0.1, V(0.28, 0.38, 0.12), 0)
			local p, n = front(H, HS, sx * 0.6, -0.2)
			ell(b, "Blush", V(0.3, 0.16, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		for _, m in { V(-0.15, -0.24, -0.6), V(0, -0.3, 0), V(0.15, -0.24, 0.6) } do
			local p, n = front(H, HS, m.X, m.Y)
			ell(b, "Icing", V(0.18, 0.07, 0.05), facing(p, n) * CFrame.Angles(0, 0, m.Z), ICING)
		end
		-- 젤리 단추 (빨강/초록/노랑)
		for i, col in { RGB(240, 70, 90), RGB(90, 205, 120), RGB(255, 200, 60) } do
			local p, n = front(B, BS, 0, 0.38 - (i - 1) * 0.36)
			local g = ell(b, "Gumdrop", V(0.26, 0.24, 0.2), facing(p, n), col)
			g.Reflectance = 0.15
		end
		-- 작은 금관 (살짝 기울어진 띠 + 뾰족 5개 + 앞 보석)
		local ccf = CFrame.new(0.06, H.Y + HS.Y + 0.02, 0) * CFrame.Angles(0, 0, -0.12)
		addPart(b, "Crown", "Cyl", V(0.24, 0.72, 0.72), ccf * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
		for i = 0, 4 do
			local a = -math.pi / 2 + i * 2 * math.pi / 5 -- 첫 뾰족은 정면(-Z)
			ell(b, "Crown", V(0.16, 0.34, 0.16), ccf * CFrame.new(math.cos(a) * 0.3, 0.22, math.sin(a) * 0.3), GOLD, METAL)
		end
		ell(b, "Gem", V(0.15, 0.15, 0.08), ccf * CFrame.new(0, 0, -0.37), RGB(230, 50, 80))
		-- 오른손 막대사탕 홀
		addPart(b, "Stick", "Cyl", V(1.2, 0.1, 0.1), CFrame.new(1.3, 1.95, -0.12) * CFrame.Angles(0, 0, math.pi / 2), ICING)
		local lcf = CFrame.new(1.3, 2.8, -0.12) * CFrame.Angles(0, math.pi / 2, 0)
		addPart(b, "Candy", "Cyl", V(0.14, 0.62, 0.62), lcf, RGB(255, 120, 180))
		addPart(b, "Candy", "Cyl", V(0.15, 0.32, 0.32), lcf, ICING)
	end

	----------------------------------------------------------------------
	-- 구름 왕국
	----------------------------------------------------------------------

	-- 구름 강아지: 몽실몽실 구름 공으로 된 하얀 강아지, 하늘색 코, 축 처진 구름 귀
	PET_BUILDERS.CloudPuppy = function(b)
		local W = RGB(250, 252, 255)
		local CL = RGB(228, 238, 255)
		local c = chibi(b, { body = W, feet = CL, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		local mcf = muzzle(c, V(0.62, 0.42, 0.4), WHITE, RGB(120, 190, 255), -0.32)
		ell(b, "Tongue", V(0.14, 0.13, 0.06), mcf * CFrame.new(0, -0.17, -0.13), RGB(255, 140, 165))
		-- 축 처진 귀 (구름 공 2개)
		for _, sx in SIDES do
			ell(b, "Ear", V(0.6, 0.6, 0.5), CFrame.new(c.H + V(sx * 1.02, 0.28, 0.1)), CL)
			ell(b, "Ear", V(0.5, 0.5, 0.44), CFrame.new(c.H + V(sx * 1.16, -0.2, 0.08)), CL)
		end
		-- 몸/머리 위 구름 뭉치
		local puffs = {
			{ c.B, c.BS, V(1, 0.25, 0.5), 0.64, WHITE },
			{ c.B, c.BS, V(-1, 0.25, 0.5), 0.64, WHITE },
			{ c.B, c.BS, V(0.6, -0.1, 0.85), 0.58, CL },
			{ c.B, c.BS, V(-0.6, -0.1, 0.85), 0.58, CL },
			{ c.H, c.HS, V(0, 1, 0.15), 0.64, WHITE },
			{ c.H, c.HS, V(0.5, 0.85, 0.3), 0.52, CL },
			{ c.H, c.HS, V(-0.5, 0.85, 0.3), 0.52, CL },
		}
		for _, pf in puffs do
			local p, n = surf(pf[1], pf[2], pf[3])
			local s = pf[4]
			ell(b, "Puff", V(s, s, s), CFrame.new(p + n * (s * 0.15)), pf[5])
		end
		-- 위로 선 구름 꼬리
		local tp = surf(c.B, c.BS, V(0, 0.1, 1))
		ell(b, "Tail", V(0.46, 0.46, 0.46), CFrame.new(tp + V(0, 0.18, 0.2)), WHITE)
		ell(b, "Tail", V(0.5, 0.5, 0.5), CFrame.new(tp + V(0, 0.55, 0.36)), CL)
	end

	-- 아기 구름: 웃는 작은 하얀 구름 (공 뭉치) + 발그레한 볼, 아래에 작은 무지개 아치 (무지개 발이 바닥에 닿아요)
	PET_BUILDERS.BabyCloud = function(b)
		local W = RGB(252, 253, 255)
		local CL = RGB(230, 239, 255)
		-- 무지개: XY 평면 반원 띠 4줄, 띠마다 45° 블록 4개 (바깥 모서리가 딱 맞게)
		local t, depth = 0.18, 0.3
		local half = math.pi / 8
		local c0 = t * math.sin(half) -- 맨 아래 블록의 안쪽 모서리가 y = 0
		local bands = { { 1.02, RAINBOW[1] }, { 0.85, RAINBOW[3] }, { 0.68, RAINBOW[4] }, { 0.51, RAINBOW[5] } }
		for _, band in bands do
			local r = band[1]
			local col = band[2]:Lerp(WHITE, 0.15)
			local len = 2 * (r * math.sin(half) + t * 0.5 * math.tan(half))
			for k = 0, 3 do
				local phi = (2 * k + 1) * half
				local radial = V(math.cos(phi), math.sin(phi), 0)
				local tangent = V(-math.sin(phi), math.cos(phi), 0)
				addPart(b, "Rainbow", "Block", V(len, t, depth), CFrame.fromMatrix(V(0, c0, 0) + radial * (r * math.cos(half)), tangent, radial), col)
			end
		end
		-- 구름 (무지개 꼭대기를 살짝 덮음)
		local C = V(0, 1.8, 0)
		local S = V(1.15, 0.78, 0.92)
		ell(b, "Body", S * 2, CFrame.new(C), W)
		local puffs = {
			{ V(-0.55, 2.42, 0.1), 1.1, CL },
			{ V(0.45, 2.52, 0.0), 1.2, W },
			{ V(0, 2.3, 0.55), 1.25, CL },
			{ V(-1.08, 1.62, 0.1), 0.85, W },
			{ V(1.1, 1.68, 0.1), 0.8, CL },
		}
		for _, pf in puffs do
			ell(b, "Puff", V(pf[2], pf[2], pf[2]), CFrame.new(pf[1]), pf[3])
		end
		-- 얼굴
		for _, sx in SIDES do
			addEye(b, C, S, sx * 0.36, 0.1, V(0.3, 0.4, 0.14), 0)
			local p, n = front(C, S, sx * 0.68, -0.1)
			ell(b, "Blush", V(0.38, 0.21, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		local mp, mn = front(C, S, 0, -0.13)
		ell(b, "Mouth", V(0.24, 0.13, 0.06), facing(mp, mn), MOUTH)
	end

	-- 페가수스: 하얀 조랑말, 크고 하얀 깃털 날개, 하늘색 갈기/꼬리, 금색 발굽
	PET_BUILDERS.Pegasus = function(b)
		local W = RGB(252, 252, 255)
		local M1 = RGB(150, 210, 255)
		local M2 = RGB(120, 190, 250)
		local M3 = RGB(185, 228, 255)
		local c = chibi(b, { body = W, feet = RGB(255, 205, 80), eyeY = 0, blushY = -0.3 })
		for _, p in b.parts do
			if p.Name == "Foot" then
				p.Reflectance = 0.25 -- 반짝이는 금 발굽
			end
		end
		lashes(b, c)
		pointyEars(c, 0.6, 0.8, 0.36, 0.46, 0.12, 0.35, W)
		local mane = { { V(0.3, 1, -0.25), 0.5, M1 }, { V(0, 0.85, 0.55), 0.6, M2 }, { V(0, 0.3, 1), 0.6, M3 }, { V(0, -0.25, 0.95), 0.52, M1 } }
		for _, m in mane do
			local mp, mn = surf(c.H, c.HS, m[1])
			ell(b, "Mane", V(m[2], m[2], m[2]), CFrame.new(mp + mn * 0.05), m[3])
		end
		local tp = surf(c.B, c.BS, V(0, 0, 1))
		ell(b, "Tail", V(0.46, 0.46, 0.46), CFrame.new(tp + V(0, 0, 0.12)), M1)
		ell(b, "Tail", V(0.4, 0.4, 0.4), CFrame.new(tp + V(0, -0.22, 0.42)), M2)
		-- 큰 깃털 날개 (깃털 3장씩, 옆으로 활짝)
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.6, 0.45, 0.75))
			featherWing(b, root, sx, { { 55, 1.8, 0.56, WHITE }, { 30, 1.55, 0.5, RGB(245, 248, 255) }, { 6, 1.2, 0.44, RGB(235, 242, 255) } }, 0.25, 0.3, 0.14)
		end
	end

	-- 천사 토끼: 하얀 토끼, 등에 작은 깃털 날개, 귀 사이 위에 둥둥 뜬 금색 네온 후광
	PET_BUILDERS.AngelBunny = function(b)
		local W = RGB(255, 251, 253)
		local P = RGB(255, 175, 200)
		local c = chibi(b, { body = W, feet = RGB(255, 232, 240) })
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.42, 1, 0.15))
			local cf = CFrame.new(p) * CFrame.Angles(0, 0, -sx * 0.3) * CFrame.new(0, 0.5, 0)
			ell(b, "Ear", V(0.42, 1.2, 0.24), cf, W)
			ell(b, "EarInner", V(0.22, 0.9, 0.08), cf * CFrame.new(0, 0.04, -0.09), P)
		end
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), P, 0.02)
		local tp, tn = surf(c.B, c.BS, V(0, -0.1, 1))
		ell(b, "Tail", V(0.5, 0.5, 0.5), CFrame.new(tp + tn * 0.1), WHITE)
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.55, 0.45, 0.8))
			featherWing(b, root, sx, { { 50, 1.1, 0.42, WHITE }, { 26, 0.92, 0.36, RGB(246, 248, 255) }, { 4, 0.72, 0.3, RGB(236, 241, 255) } }, 0.35, 0.3, 0.12)
		end
		-- 후광: 머리 위로 떠 있고 귀 앞쪽에 걸쳐요 (앞쪽이 살짝 아래로)
		ring(b, "Halo", V(0, c.H.Y + c.HS.Y + 0.5, -0.28), 0.46, 7, 0.13, RGB(255, 215, 80), NEON, -0.15)
	end

	----------------------------------------------------------------------
	-- 우주
	----------------------------------------------------------------------

	-- 우주곰: 하얀 우주복을 입은 갈색 곰돌이, 투명 유리 헬멧 + 금속 목 고리, 작은 안테나, 가슴 패널, 산소통
	PET_BUILDERS.AstroBear = function(b)
		local Br = RGB(170, 112, 72)
		local Tn = RGB(240, 210, 170)
		local SUIT = RGB(242, 245, 252)
		local GREY = RGB(150, 160, 185)
		local c = chibi(b, { body = SUIT, head = Br, arms = SUIT, feet = GREY, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		for _, p in b.parts do
			if p.Name == "Blush" then
				p.Transparency = 0 -- 유리 헬멧 뒤에서도 보이게
			end
		end
		muzzle(c, V(0.6, 0.42, 0.38), Tn, RGB(50, 35, 30), -0.32)
		roundEars(c, 0.62, 0.78, 0.56, Br, Tn)
		-- 유리 헬멧 (귀/주둥이까지 다 들어가는 크기) + 하이라이트 + 목 고리
		local HC = c.H + V(0, 0.25, -0.04)
		local HSz = V(1.47, 1.3, 1.45)
		ell(b, "Helmet", HSz * 2, CFrame.new(HC), RGB(205, 230, 255), Enum.Material.Glass, 0.55)
		local gp, gn = surf(HC, HSz, V(-0.6, 0.55, -0.6))
		ell(b, "Gloss", V(0.26, 0.7, 0.05), facing(gp + gn * 0.01, gn) * CFrame.Angles(0, 0, -0.5), WHITE, nil, 0.35)
		addPart(b, "Collar", "Cyl", V(0.24, 2.0, 2.0), CFrame.new(0, 1.22, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(205, 212, 228), METAL)
		-- 안테나 (헬멧 위 오른쪽) + 빨간 네온 구슬
		local ap = surf(HC, HSz, V(0.35, 1, 0.1))
		local ad = V(0.25, 1, 0.1).Unit
		addPart(b, "Antenna", "Cyl", V(0.42, 0.07, 0.07), alongX(ap + ad * 0.17, ad), GREY, METAL)
		ell(b, "AntennaTip", V(0.2, 0.2, 0.2), CFrame.new(ap + ad * 0.42), RGB(255, 90, 110), NEON)
		-- 가슴 패널 + 네온 버튼 3개
		local pp, pn = front(c.B, c.BS, 0, -0.05)
		local pcf = facing(pp + pn * 0.01, pn)
		addPart(b, "Panel", "Block", V(0.6, 0.36, 0.08), pcf, RGB(200, 210, 230))
		for i, col in { RGB(255, 90, 110), RGB(255, 220, 90), RGB(100, 220, 255) } do
			ell(b, "Button", V(0.1, 0.1, 0.05), pcf * CFrame.new((i - 2) * 0.17, 0, -0.045), col, NEON)
		end
		-- 등 산소통 (목 고리 아래)
		addPart(b, "Backpack", "Block", V(0.9, 0.7, 0.4), CFrame.new(0, 0.75, c.BS.Z + 0.06), RGB(220, 225, 238))
		-- 액세서리 자리: 모자는 헬멧 위, 얼굴 장식은 헬멧 앞 (눈 높이)
		attach(b, "AccHead", HC + V(0, HSz.Y, 0))
		attach(b, "AccFace", (front(HC, HSz, 0, c.H.Y + 0.08 - HC.Y)))
	end

	-- 혜성 여우: 짙은 파랑 여우, 꼬리는 빛나는 혜성 꼬리 (네온 하늘색 → 하양), 이마에 노란 별
	PET_BUILDERS.CometFox = function(b)
		local Bl = RGB(55, 90, 200)
		local Lt = RGB(215, 230, 255)
		local Dk = RGB(30, 45, 115)
		local STAR = RGB(255, 235, 120)
		local c = chibi(b, { body = Bl, belly = Lt, feet = Dk, arms = Dk, eyeY = 0.06, noMouth = true, blushX = 0.7, blushY = -0.2 })
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.22, -0.36)
			ell(b, "Cheek", V(0.6, 0.45, 0.35), facing(p - n * 0.08, n), Lt)
		end
		smallNose(c, -0.22, V(0.18, 0.12, 0.1), RGB(25, 25, 55), 0.05)
		local mp, mn = front(c.H, c.HS, 0, -0.4)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), MOUTH)
		-- 큰 뾰족 귀 (안쪽은 하늘색 타원 한 장)
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx * 0.55, 0.85, 0))
			local frame = CFrame.new(p - n * 0.14) * CFrame.Angles(0, 0, -sx * 0.28)
			tri(b, "Ear", frame, 0.62, 0.75, 0.15, Bl)
			ell(b, "EarInner", V(0.28, 0.42, 0.04), frame * CFrame.new(0, 0.32, -0.085), RGB(130, 200, 255))
		end
		-- 이마의 오각 별 (네온 광선 5개)
		local sp, sn = front(c.H, c.HS, 0, 0.56)
		local scf = facing(sp + sn * 0.01, sn)
		for i = 0, 4 do
			local a = i * 2 * math.pi / 5
			ell(b, "Star", V(0.09, 0.24, 0.05), scf * CFrame.new(-math.sin(a) * 0.085, math.cos(a) * 0.085, 0) * CFrame.Angles(0, 0, a), STAR, NEON)
		end
		-- 혜성 꼬리: 몸 뒤에서 뒤/위/오른쪽으로 휘며 점점 굵고 밝아지다 하얀 혜성 머리로 끝나요
		-- (정면에서도 머리 옆으로 하얀 끝이 살짝 보여요)
		local pts = { surf(c.B, c.BS, V(0, -0.15, 1)), V(0.1, 1.08, 1.22), V(0.32, 1.6, 1.48), V(0.75, 2.1, 1.45) }
		local trail = { { 0.34, RGB(60, 205, 255) }, { 0.44, RGB(120, 228, 255) }, { 0.52, RGB(190, 245, 255) } }
		for i, tr in trail do
			local a, z = pts[i], pts[i + 1]
			local s = tr[1]
			ell(b, "Tail", V(s, s, (z - a).Magnitude * 1.35), CFrame.lookAt((a + z) * 0.5, z), tr[2], NEON)
		end
		local tipC = pts[4] + (pts[4] - pts[3]).Unit * 0.3
		ell(b, "TailTip", V(0.68, 0.68, 0.68), CFrame.new(tipC), WHITE, NEON)
	end
end
