-- 겨울 알 펫 모델 (PetModels/init.luau 가 불러서 등록)
-- 규칙은 init.luau 와 같아요: 앞쪽 = -Z, 바닥 = y 0, 파트 이름 Eye/Shine/Blush 는 얼굴 전용.
return function(Kit, PET_BUILDERS, EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, addEye, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.addEye, Kit.chibi, Kit.SIDES
	local addPart, darker, alongX, muzzle, roundEars, smallNose = Kit.addPart, Kit.darker, Kit.alongX, Kit.muzzle, Kit.roundEars, Kit.smallNose
	local WHITE, BLUSH, MOUTH = Kit.WHITE, Kit.BLUSH, Kit.MOUTH

	-- 목에 두르는 고리 (목도리/목걸이)
	local function neckRing(b, name, c, t, color, mat)
		local ny = c.B.Y + c.BS.Y - 0.2
		addPart(b, name, "Cyl", V(t, 1.62, 1.62), CFrame.new(0, ny, 0) * CFrame.Angles(0, 0, math.pi / 2), color, mat)
		return ny
	end

	-- 바다표범: 통통한 회백색 몸, 가슴과 머리를 든 자세, 물갈퀴, 까만 코, 수염, 큰 까만 눈
	-- (기울인 긴 타원체는 피벗 계산에서 바닥보다 내려가므로 바닥 몸통은 수평, 가슴만 기울임)
	PET_BUILDERS.Seal = function(b)
		local S = RGB(228, 232, 240)
		local Wt = RGB(250, 250, 253)
		local B = V(0, 0.74, 0.3)
		local BS = V(0.95, 0.74, 1.2)
		ell(b, "Body", BS * 2, CFrame.new(B), S)
		local CC = V(0, 1.2, -0.55)
		local CF = CFrame.new(CC) * CFrame.Angles(0.8, 0, 0)
		ell(b, "Chest", V(1.6, 1.24, 1.4), CF, S)
		ell(b, "Belly", V(1.2, 1.0, 1.1), CF * CFrame.new(0, -0.2, -0.25), Wt)
		for _, d in { V(0.5, 0.8, 0.3), V(-0.45, 0.85, 0.6), V(0.1, 0.9, 0.95) } do
			local p, n = surf(B, BS, d)
			ell(b, "Spot", V(0.3, 0.26, 0.06), facing(p, n), RGB(200, 206, 218))
		end

		-- 머리
		local H = V(0, 1.9, -0.8)
		local HS = V(0.84, 0.76, 0.76)
		ell(b, "Head", HS * 2, CFrame.new(H), S)
		for _, sx in SIDES do
			addEye(b, H, HS, sx * 0.3, 0.02, V(0.4, 0.5, 0.16), 0)
			local p, n = front(H, HS, sx * 0.56, -0.26)
			ell(b, "Blush", V(0.3, 0.16, 0.06), facing(p, n), BLUSH, nil, 0.1)
			-- 수염 2가닥씩 (가는 원기둥)
			for _, a in { 0.15, -0.12 } do
				local wp, wn = front(H, HS, sx * 0.4, -0.34 + a * 0.4)
				addPart(b, "Whisker", "Cyl", V(0.5, 0.035, 0.035), facing(wp + wn * 0.03, wn) * CFrame.Angles(0, 0, sx * a), RGB(90, 85, 95))
			end
		end
		local np, nn = front(H, HS, 0, -0.24)
		ell(b, "Nose", V(0.26, 0.18, 0.16), facing(np + nn * 0.04, nn), RGB(35, 32, 40))
		local mp, mn = front(H, HS, 0, -0.44)
		ell(b, "Mouth", V(0.16, 0.07, 0.05), facing(mp, mn), MOUTH)

		-- 앞 물갈퀴 (앞·아래로), 뒷 물갈퀴 (뒤로 벌어짐)
		for _, sx in SIDES do
			local fcf = CFrame.new(sx * 0.95, 0.25, -0.45) * CFrame.Angles(0, sx * 0.5, 0) * CFrame.Angles(0, 0, -sx * 0.35)
			ell(b, "Flipper", V(0.7, 0.26, 0.5), fcf, S)
			ell(b, "Flipper", V(0.55, 0.26, 0.8), CFrame.new(sx * 0.35, 0.13, 1.5) * CFrame.Angles(0, sx * 0.35, 0), S)
		end
	end

	-- 눈토끼: 새하얀 토끼, 얼음색 귀 안쪽, 이마의 작은 눈꽃(막대 3개), 하늘색 목도리
	PET_BUILDERS.SnowBunny = function(b)
		local W = RGB(250, 252, 255)
		local Ice = RGB(165, 215, 255)
		local c = chibi(b, { body = W, belly = WHITE, feet = RGB(235, 242, 252), eyeY = 0.02, blushY = -0.3, mouthY = -0.4 })
		for _, sx in SIDES do
			local p = surf(c.H, c.HS, V(sx * 0.38, 1, 0.05))
			local cf = CFrame.new(p) * CFrame.Angles(0, 0, -sx * 0.2) * CFrame.new(0, 0.5, 0)
			ell(b, "Ear", V(0.42, 1.2, 0.24), cf, W)
			ell(b, "EarInner", V(0.22, 0.9, 0.08), cf * CFrame.new(0, 0.04, -0.09), Ice)
		end
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 170, 195), 0.02)
		-- 이마 눈꽃: 가는 막대 3개가 60도씩 교차
		local fp, fn = surf(c.H, c.HS, V(0, 0.62, -0.85))
		local fcf = facing(fp + fn * 0.03, fn)
		for i = 0, 2 do
			addPart(b, "Snowflake", "Block", V(0.4, 0.05, 0.04), fcf * CFrame.Angles(0, 0, i * math.pi / 3), Ice, Enum.Material.Neon)
		end
		-- 목도리 + 앞으로 늘어진 자락
		local ny = neckRing(b, "Scarf", c, 0.26, Ice)
		addPart(b, "ScarfTail", "Block", V(0.3, 0.6, 0.16), CFrame.new(0.42, ny - 0.38, -0.78) * CFrame.Angles(0, 0, 0.15), Ice)
		local tp, tn = surf(c.B, c.BS, V(0, -0.1, 1))
		ell(b, "Tail", V(0.5, 0.5, 0.5), CFrame.new(tp + tn * 0.1), WHITE)
	end

	-- 눈사람: 눈덩이 3개, 당근 코, 석탄 단추/입, 나뭇가지 팔, 빨간 목도리, 까만 모자
	PET_BUILDERS.Snowman = function(b)
		local Sn = RGB(248, 250, 255)
		local Coal = RGB(40, 40, 48)
		local Twig = RGB(120, 85, 55)
		local Or = RGB(255, 140, 50)
		local Red = RGB(230, 60, 70)
		local BR, MR, HR = 0.75, 0.58, 0.48
		local B = V(0, BR, 0)
		local M = V(0, 1.84, 0)
		local H = V(0, 2.7, 0)
		local MS = V(MR, MR, MR)
		local HS = V(HR, HR, HR)
		ell(b, "Body", V(BR * 2, BR * 2, BR * 2), CFrame.new(B), Sn)
		ell(b, "Middle", MS * 2, CFrame.new(M), Sn)
		ell(b, "Head", HS * 2, CFrame.new(H), Sn)

		-- 얼굴
		for _, sx in SIDES do
			addEye(b, H, HS, sx * 0.2, 0.06, V(0.22, 0.3, 0.12), 0)
			local p, n = front(H, HS, sx * 0.36, -0.16)
			ell(b, "Blush", V(0.2, 0.11, 0.05), facing(p, n), BLUSH, nil, 0.1)
		end
		local np, nn = front(H, HS, 0, -0.06)
		addPart(b, "Nose", "Cyl", V(0.45, 0.15, 0.15), alongX(np + nn * 0.18, nn), Or)
		addPart(b, "NoseTip", "Cyl", V(0.25, 0.09, 0.09), alongX(np + nn * 0.5, nn), Or)
		for _, m in { V(-0.2, -0.24, 0), V(-0.07, -0.3, 0), V(0.07, -0.3, 0), V(0.2, -0.24, 0) } do
			local p, n = front(H, HS, m.X, m.Y)
			ell(b, "Mouth", V(0.07, 0.07, 0.05), facing(p + n * 0.01, n), Coal)
		end

		-- 단추
		for _, y in { 0.2, 0, -0.2 } do
			local p, n = front(M, MS, 0, y)
			ell(b, "Button", V(0.13, 0.13, 0.06), facing(p + n * 0.01, n), Coal)
		end

		-- 나뭇가지 팔 (위로 벌림) + 잔가지
		for _, sx in SIDES do
			local ap = surf(M, MS, V(sx, 0.25, 0))
			local d = V(sx, 0.6, -0.15).Unit
			addPart(b, "Arm", "Cyl", V(1.0, 0.1, 0.1), alongX(ap + d * 0.4, d), Twig)
			local d2 = V(sx * 0.4, 1, -0.1).Unit
			addPart(b, "Arm", "Cyl", V(0.4, 0.08, 0.08), alongX(ap + d * 0.6 + d2 * 0.15, d2), Twig)
		end

		-- 목도리 (머리와 몸통 사이) + 자락
		local ny = M.Y + MR - 0.12
		addPart(b, "Scarf", "Cyl", V(0.26, 0.9, 0.9), CFrame.new(0, ny, 0) * CFrame.Angles(0, 0, math.pi / 2), Red)
		addPart(b, "ScarfTail", "Block", V(0.26, 0.5, 0.12), CFrame.new(0.3, ny - 0.3, -0.52) * CFrame.Angles(0, 0, 0.12), Red)

		-- 모자 (챙 + 몸통 + 띠)
		local hy = H.Y + HR - 0.1
		addPart(b, "HatBrim", "Cyl", V(0.08, 1.2, 1.2), CFrame.new(0, hy, 0) * CFrame.Angles(0, 0, math.pi / 2), Coal)
		addPart(b, "Hat", "Cyl", V(0.42, 0.78, 0.78), CFrame.new(0, hy + 0.25, 0) * CFrame.Angles(0, 0, math.pi / 2), Coal)
		addPart(b, "HatBand", "Cyl", V(0.1, 0.82, 0.82), CFrame.new(0, hy + 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2), Red)
	end

	-- 북극곰: 하얀 동글 곰, 작은 동그란 귀, 까만 코, 하늘색 목도리
	PET_BUILDERS.PolarBear = function(b)
		local W = RGB(248, 248, 252)
		local Cr = RGB(255, 252, 240)
		local Ice = RGB(150, 205, 255)
		local c = chibi(b, { body = W, belly = Cr, feet = RGB(225, 228, 238), eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		muzzle(c, V(0.6, 0.42, 0.38), Cr, RGB(40, 36, 40), -0.32)
		roundEars(c, 0.64, 0.78, 0.46, W, RGB(255, 215, 225))
		local ny = neckRing(b, "Muffler", c, 0.28, Ice)
		addPart(b, "MufflerTail", "Block", V(0.32, 0.62, 0.16), CFrame.new(-0.4, ny - 0.4, -0.78) * CFrame.Angles(0, 0, -0.12), Ice)
		for _, dx in { -0.09, 0.09 } do
			addPart(b, "Fringe", "Block", V(0.08, 0.18, 0.14), CFrame.new(-0.44 + dx, ny - 0.78, -0.78) * CFrame.Angles(0, 0, -0.12), darker(Ice, 0.1))
		end
		local tp, tn = surf(c.B, c.BS, V(0, -0.2, 1))
		ell(b, "Tail", V(0.34, 0.34, 0.34), CFrame.new(tp + tn * 0.05), W)
	end

	-- 순록: 갈색 몸, 크림 주둥이 + 빨간 네온 코, 갈라진 뿔 2개(원기둥), 작은 귀, 방울 목걸이
	PET_BUILDERS.Reindeer = function(b)
		local Br = RGB(175, 125, 85)
		local Cr = RGB(245, 225, 195)
		local Dk = RGB(110, 75, 50)
		local c = chibi(b, { body = Br, belly = Cr, feet = Dk, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		local p, n = front(c.H, c.HS, 0, -0.32)
		local mcf = facing(p - n * 0.05, n)
		ell(b, "Muzzle", V(0.62, 0.44, 0.4), mcf, Cr)
		ell(b, "Nose", V(0.3, 0.26, 0.24), mcf * CFrame.new(0, 0.1, -0.2), RGB(255, 60, 60), Enum.Material.Neon)
		ell(b, "Mouth", V(0.14, 0.06, 0.05), mcf * CFrame.new(0, -0.08, -0.19), MOUTH)

		-- 뿔: 큰 줄기 + 옆가지 + 앞가지
		for _, sx in SIDES do
			local ap = surf(c.H, c.HS, V(sx * 0.4, 1, 0.1))
			local d = V(sx * 0.4, 1, 0.1).Unit
			addPart(b, "Antler", "Cyl", V(0.8, 0.13, 0.13), alongX(ap + d * 0.32, d), Dk)
			local d2 = V(sx, 0.3, -0.35).Unit
			addPart(b, "Antler", "Cyl", V(0.45, 0.11, 0.11), alongX(ap + d * 0.4 + d2 * 0.18, d2), Dk)
			local d3 = V(sx * 0.15, 0.45, -1).Unit
			addPart(b, "Antler", "Cyl", V(0.38, 0.1, 0.1), alongX(ap + d * 0.66 + d3 * 0.15, d3), Dk)
		end
		-- 귀
		for _, sx in SIDES do
			local ep, en = surf(c.H, c.HS, V(sx, 0.35, 0))
			ell(b, "Ear", V(0.5, 0.28, 0.22), CFrame.new(ep + en * 0.12) * CFrame.Angles(0, 0, sx * 0.35), Br)
		end
		-- 방울 목걸이
		local ny = neckRing(b, "Collar", c, 0.16, RGB(220, 60, 70))
		ell(b, "Bell", V(0.3, 0.3, 0.3), CFrame.new(0, ny - 0.18, -0.78), RGB(255, 210, 70), Enum.Material.Metal)
		local tp, tn = surf(c.B, c.BS, V(0, -0.1, 1))
		ell(b, "Tail", V(0.28, 0.32, 0.28), CFrame.new(tp + tn * 0.06), Cr)
	end
end
