-- 캔디 알 펫 모델 (PetModels/init.luau 가 불러서 등록)
-- 솜사탕 양 / 도넛 강아지 / 젤리곰 / 컵케이크 냥이 / 마카롱 토끼
return function(Kit, PET_BUILDERS, EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.chibi, Kit.SIDES
	local addPart, darker, alongX, muzzle, smallNose, pointyEars, roundEars = Kit.addPart, Kit.darker, Kit.alongX, Kit.muzzle, Kit.smallNose, Kit.pointyEars, Kit.roundEars
	local WHITE = Kit.WHITE

	-- 기본 몸에서 안 보이게 되는 파트(컵 속 발 등)를 빌더 목록에서 빼고 지워요
	local function dropParts(b, name)
		for i = #b.parts, 1, -1 do
			local p = b.parts[i]
			if p.Name == name then
				table.remove(b.parts, i)
				p:Destroy()
			end
		end
	end

	-- 솜사탕 양: 크림색 몸에 분홍/하늘 솜사탕 털, 종이 콘 막대 꼬리
	PET_BUILDERS.CottonSheep = function(b)
		local Cr = RGB(255, 246, 232)
		local PINK = RGB(255, 185, 225)
		local BLUE = RGB(180, 215, 255)
		local c = chibi(b, { body = Cr, feet = RGB(205, 175, 195), eyeY = 0, blushY = -0.3, mouthY = -0.4 })
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 150, 185), 0.03)
		-- 옆으로 늘어진 작은 귀
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx, 0.05, 0))
			ell(b, "Ear", V(0.5, 0.28, 0.32), CFrame.new(p + n * 0.02 + V(0, -0.08, 0)) * CFrame.Angles(0, 0, sx * 0.5), Cr)
		end
		-- 솜사탕 털: 머리 위 모자처럼 + 등에 복슬복슬
		local headFluff = { V(0, 1, -0.3), V(0.55, 0.85, 0.1), V(-0.55, 0.85, 0.1), V(0.3, 0.9, 0.55), V(-0.3, 0.9, 0.55), V(0, 0.55, 1) }
		local headSz = { 0.72, 0.62, 0.62, 0.6, 0.6, 0.62 }
		for i, d in headFluff do
			local p, n = surf(c.H, c.HS, d)
			local s = headSz[i]
			ell(b, "Fluff", V(s, s, s), CFrame.new(p + n * 0.1), if i % 2 == 0 then BLUE else PINK, nil, 0.1)
		end
		local bodyFluff = { V(0, 0.75, 0.65), V(0.7, 0.45, 0.6), V(-0.7, 0.45, 0.6), V(0.55, -0.1, 0.85), V(-0.55, -0.1, 0.85), V(0, 0.1, 1) }
		for i, d in bodyFluff do
			local p, n = surf(c.B, c.BS, d)
			ell(b, "Fluff", V(0.62, 0.62, 0.62), CFrame.new(p + n * 0.1), if i % 2 == 0 then PINK else BLUE, nil, 0.1)
		end
		-- 꼬리: 솜사탕 뭉치에서 종이 콘 막대가 삐죽
		local tp, tn = surf(c.B, c.BS, V(0, -0.2, 1))
		local dir = V(0, -0.35, 1).Unit
		addPart(b, "Stick", "Cyl", V(0.7, 0.13, 0.13), alongX(tp + dir * 0.3, dir), RGB(255, 250, 240))
		ell(b, "Tail", V(0.4, 0.4, 0.4), CFrame.new(tp + tn * 0.05), PINK, nil, 0.1)
	end

	-- 도넛 강아지: 늘어진 귀 강아지가 분홍 프로스팅 도넛을 허리에 끼고 있어요
	PET_BUILDERS.DonutPuppy = function(b)
		local T = RGB(235, 200, 150)
		local Cr = RGB(255, 242, 222)
		local Br = RGB(145, 95, 60)
		local FROST = RGB(255, 150, 190)
		local c = chibi(b, { body = T, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		local mcf = muzzle(c, V(0.62, 0.42, 0.4), Cr, RGB(45, 35, 35), -0.32)
		ell(b, "Tongue", V(0.14, 0.13, 0.06), mcf * CFrame.new(0, -0.17, -0.13), RGB(255, 120, 140))
		for _, sx in SIDES do
			ell(b, "Ear", V(0.42, 0.85, 0.26), CFrame.new(c.H + V(sx * 1.08, 0.22, 0.05)) * CFrame.Angles(0, 0, sx * 0.25), Br)
		end
		-- 도넛: 반죽 띠 + 위에 프로스팅 원판 + 흘러내린 방울 + 스프링클
		local dy = c.B.Y + 0.4
		addPart(b, "Donut", "Cyl", V(0.36, 2.3, 2.3), CFrame.new(0, dy, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(230, 180, 110))
		addPart(b, "Frosting", "Cyl", V(0.12, 2.36, 2.36), CFrame.new(0, dy + 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2), FROST)
		for i = 1, 3 do
			local a = -math.pi / 2 + (i - 1) * math.pi * 2 / 3 -- 첫 방울은 정면
			local radial = V(math.cos(a), 0, math.sin(a))
			ell(b, "Drip", V(0.24, 0.34, 0.16), facing(V(0, dy + 0.02, 0) + radial * 1.1, radial), FROST)
		end
		local sprinkleCols = { RGB(255, 235, 120), RGB(150, 230, 200), RGB(170, 200, 255), RGB(255, 120, 150), WHITE, RGB(200, 150, 255) }
		for i, col in sprinkleCols do
			local a = (i - 1) * math.pi / 3 + 0.25
			addPart(b, "Sprinkle", "Block", V(0.2, 0.06, 0.07), CFrame.new(math.cos(a), dy + 0.29, math.sin(a)) * CFrame.Angles(0, a + i * 0.9, 0), col)
		end
		local tp = surf(c.B, c.BS, V(0, 0.1, 1))
		local dir = V(0, 0.65, 0.75).Unit
		ell(b, "Tail", V(0.24, 0.24, 0.6), CFrame.lookAt(tp + dir * 0.22, tp + dir * 1.22), T)
	end

	-- 젤리곰: 빨간 반투명 젤리 곰돌이, 윤기 하이라이트
	PET_BUILDERS.JellyBear = function(b)
		local R = RGB(255, 70, 95)
		local c = chibi(b, { body = R, feet = R, arms = R, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2, eyeSize = V(0.3, 0.42, 0.16) })
		muzzle(c, V(0.6, 0.42, 0.38), RGB(255, 120, 135), RGB(140, 25, 50), -0.32)
		roundEars(c, 0.62, 0.78, 0.56, R, nil)
		local tp, tn = surf(c.B, c.BS, V(0, -0.2, 1))
		ell(b, "Tail", V(0.35, 0.35, 0.35), CFrame.new(tp + tn * 0.05), R)
		-- 젤리 느낌: 몸 파트만 반투명 + 반사 (눈/볼터치는 그대로)
		local gummy = { Body = true, Head = true, Foot = true, Arm = true, Ear = true, Tail = true, Muzzle = true }
		for _, p in b.parts do
			if gummy[p.Name] then
				p.Transparency = 0.2
				p.Reflectance = 0.15
			end
		end
		-- 윤기 하이라이트 (머리 왼쪽 위 긴 것 + 점, 몸에 하나)
		local hp, hn = surf(c.H, c.HS, V(-0.45, 0.7, -0.6))
		ell(b, "Gloss", V(0.22, 0.6, 0.06), facing(hp + hn * 0.02, hn) * CFrame.Angles(0, 0, -0.55), WHITE, nil, 0.3)
		local dp, dn = surf(c.H, c.HS, V(-0.8, 0.5, -0.4))
		ell(b, "Gloss", V(0.14, 0.14, 0.06), facing(dp + dn * 0.02, dn), WHITE, nil, 0.3)
		local bp, bn = surf(c.B, c.BS, V(-0.6, 0.4, -0.7))
		ell(b, "Gloss", V(0.14, 0.4, 0.06), facing(bp + bn * 0.02, bn) * CFrame.Angles(0, 0, -0.5), WHITE, nil, 0.3)
	end

	-- 컵케이크 냥이: 민트 주름 컵 안에 앉은 크림색 고양이, 머리 위 분홍 프로스팅 + 체리
	PET_BUILDERS.CupcakeCat = function(b)
		local Cr = RGB(255, 236, 210)
		local MINT = RGB(185, 235, 215)
		local FROST = RGB(255, 200, 225)
		local c = chibi(b, { body = Cr, feet = Cr, eyeY = 0.05, noMouth = true, blushY = -0.22 })
		dropParts(b, "Foot") -- 컵 안에 숨어서 안 보여요
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.16, -0.33)
			ell(b, "Muzzle", V(0.42, 0.32, 0.28), facing(p - n * 0.06, n), WHITE)
		end
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 130, 160), 0.04)
		pointyEars(c, 0.55, 0.85, 0.6, 0.62, 0.16, 0.3, Cr)
		-- 주름 컵: 원기둥 + 둘레 세로 주름 8개
		local cupH, cupR = 0.85, 1.0
		addPart(b, "Cup", "Cyl", V(cupH, cupR * 2, cupR * 2), CFrame.new(0, cupH / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), MINT)
		for i = 1, 8 do
			local a = (i - 0.5) * math.pi / 4
			local pos = V(math.cos(a) * cupR, cupH / 2, math.sin(a) * cupR)
			addPart(b, "Pleat", "Cyl", V(cupH - 0.04, 0.3, 0.3), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), darker(MINT, 0.06))
		end
		-- 프로스팅 소용돌이 (납작 공 3단) + 체리 + 꼭지
		local top = c.H.Y + c.HS.Y
		ell(b, "Frosting", V(1.15, 0.5, 1.15), CFrame.new(0, top - 0.05, 0), FROST)
		ell(b, "Frosting", V(0.85, 0.44, 0.85), CFrame.new(0, top + 0.22, 0), FROST)
		ell(b, "Frosting", V(0.55, 0.38, 0.55), CFrame.new(0, top + 0.46, 0), FROST)
		ell(b, "Cherry", V(0.32, 0.32, 0.32), CFrame.new(0, top + 0.72, 0), RGB(225, 40, 70))
		addPart(b, "Stem", "Cyl", V(0.3, 0.06, 0.06), CFrame.new(0.05, top + 0.98, 0) * CFrame.Angles(0, 0, math.pi / 2 - 0.3), RGB(110, 70, 40))
	end

	-- 마카롱 토끼: 몸이 민트 마카롱(껍질 2장 + 크림), 파스텔 귀, 스프링클
	PET_BUILDERS.MacaronBunny = function(b)
		local MINT = RGB(175, 235, 205)
		local MINT2 = RGB(150, 220, 190)
		local CREAM = RGB(255, 245, 225)
		local PINK = RGB(255, 190, 215)
		local c = chibi(b, { body = MINT, BS = V(0.85, 0.62, 0.7), noArms = true, eyeY = 0, blushY = -0.3, mouthY = -0.4 })
		dropParts(b, "Foot") -- 마카롱 아래로 발을 따로 내밀어요
		-- 마카롱 몸: 아래 껍질 + 크림 + 위 껍질 (기본 몸통은 그 안에 숨음)
		local R = 1.1
		addPart(b, "Shell", "Cyl", V(0.5, R * 2, R * 2), CFrame.new(0, 0.33, 0) * CFrame.Angles(0, 0, math.pi / 2), MINT)
		addPart(b, "Filling", "Cyl", V(0.28, R * 2 - 0.2, R * 2 - 0.2), CFrame.new(0, 0.71, 0) * CFrame.Angles(0, 0, math.pi / 2), CREAM)
		addPart(b, "Shell", "Cyl", V(0.5, R * 2, R * 2), CFrame.new(0, 1.09, 0) * CFrame.Angles(0, 0, math.pi / 2), MINT)
		-- 앞으로 내민 발 + 위 껍질에 올린 앞발
		for _, sx in SIDES do
			ell(b, "Foot", V(0.5, 0.3, 0.55), CFrame.new(sx * 0.42, 0.15, -0.95), MINT2)
			ell(b, "Arm", V(0.36, 0.26, 0.4), CFrame.new(sx * 0.6, 1.42, -0.8), MINT)
		end
		-- 긴 귀 (안쪽 분홍)
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.38, 1, 0.05))
			local cf = CFrame.new(p) * CFrame.Angles(0, 0, -sx * 0.2) * CFrame.new(0, 0.5, 0)
			ell(b, "Ear", V(0.42, 1.2, 0.24), cf, MINT)
			ell(b, "EarInner", V(0.22, 0.9, 0.08), cf * CFrame.new(0, 0.04, -0.09), PINK)
		end
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 140, 175), 0.02)
		ell(b, "Tail", V(0.42, 0.42, 0.42), CFrame.new(0, 1.15, 1.05), WHITE)
		-- 껍질 옆면 스프링클
		local sprCols = { RGB(255, 235, 120), RGB(255, 150, 180), RGB(170, 200, 255), WHITE, RGB(200, 150, 255) }
		local sprY = { 1.12, 0.3, 1.2, 0.38, 1.0 }
		for i, col in sprCols do
			local a = -math.pi / 2 + (i - 3) * 0.55
			local radial = V(math.cos(a), 0, math.sin(a))
			local pos = V(0, sprY[i], 0) + radial * (R + 0.02)
			addPart(b, "Sprinkle", "Block", V(0.18, 0.06, 0.06), facing(pos, radial) * CFrame.Angles(0, 0, i * 0.7), col)
		end
	end
end
