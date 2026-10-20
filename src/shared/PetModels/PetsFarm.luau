-- 농장 친구들 펫 모델 (PetModels/init.luau 가 불러서 등록)
-- 오리 / 양 / 다람쥐 / 고슴도치 / 라쿤 / 원숭이 / 사자 / 앵무새
return function(Kit, PET_BUILDERS, EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, tri, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.tri, Kit.chibi, Kit.SIDES
	local darker, alongY, frameUp, pointyEars, roundEars, muzzle, smallNose, ballArc = Kit.darker, Kit.alongY, Kit.frameUp, Kit.pointyEars, Kit.roundEars, Kit.muzzle, Kit.smallNose, Kit.ballArc
	local WHITE, MOUTH = Kit.WHITE, Kit.MOUTH
	local _ = EGG_BUILDERS -- 이 모듈은 알을 추가하지 않아요

	-- 오리: 노란 크림 몸, 넓적한 주황 부리(위/아래 두 겹 + 콧구멍), 작은 날개, 위로 말린 꼬리, 물갈퀴 발
	PET_BUILDERS.Duck = function(b)
		local Y = RGB(255, 236, 140)
		local Or = RGB(255, 150, 45)
		local c = chibi(b, {
			body = Y,
			belly = RGB(255, 248, 205),
			feet = Or,
			noArms = true,
			noMouth = true,
			eyeY = 0.12,
			blushX = 0.66,
			blushY = -0.22,
		})
		-- 넓적한 부리 (병아리 부리보다 넓고 납작)
		local p, n = front(c.H, c.HS, 0, -0.28)
		local bcf = facing(p + n * 0.14, n)
		ell(b, "Bill", V(0.66, 0.17, 0.5), bcf, Or)
		ell(b, "Bill", V(0.56, 0.12, 0.42), bcf * CFrame.new(0, -0.1, 0.03), darker(Or, 0.15))
		for _, sx in SIDES do
			ell(b, "Nostril", V(0.07, 0.05, 0.05), bcf * CFrame.new(sx * 0.12, 0.07, -0.12), darker(Or, 0.35))
		end
		-- 작은 날개
		for _, sx in SIDES do
			local wp, wn = surf(c.B, c.BS, V(sx, 0.05, 0.1))
			ell(b, "Wing", V(0.26, 0.58, 0.55), CFrame.new(wp + wn * 0.02) * CFrame.Angles(0, 0, sx * 0.3), darker(Y, 0.08))
		end
		-- 위로 말린 꼬리
		local tp, tn = surf(c.B, c.BS, V(0, 0.1, 1))
		ell(b, "Tail", V(0.4, 0.26, 0.44), CFrame.new(tp + tn * 0.1) * CFrame.Angles(-0.55, 0, 0), Y)
		ell(b, "Tail", V(0.24, 0.24, 0.24), CFrame.new(tp + tn * 0.1 + V(0, 0.2, 0.2)), Y)
		-- 물갈퀴: 발 앞으로 펼쳐진 납작한 세모 (바닥에 붙음)
		for _, sx in SIDES do
			local frame = CFrame.fromMatrix(V(sx * c.BS.X * 0.5, 0.05, -c.BS.Z * 0.38 - 0.5), -Vector3.xAxis, Vector3.zAxis)
			tri(b, "Web", frame, 0.84, 0.78, 0.1, Or)
		end
		-- 머리 위 털 한 가닥
		local top = c.H + V(0, c.HS.Y, 0)
		ell(b, "Tuft", V(0.15, 0.36, 0.15), CFrame.new(top + V(0.08, 0.08, 0.05)) * CFrame.Angles(0, 0, -0.5), Y)
	end

	-- 양: 크림 양털(겹친 공들), 연회색 얼굴/다리, 옆으로 늘어진 작은 귀, 동그란 꼬리
	PET_BUILDERS.Sheep = function(b)
		local Cr = RGB(242, 234, 220)
		local Wool = RGB(252, 248, 240)
		local Gy = RGB(205, 205, 215)
		local Dk = RGB(165, 165, 180)
		local c = chibi(b, {
			body = Cr,
			feet = Dk,
			noArms = true,
			face = { color = Gy, semi = V(0.82, 0.72, 0.6), offset = V(0, -0.1, -0.42) },
			eyeX = 0.34,
			eyeY = 0.06,
			blushX = 0.58,
			blushY = -0.2,
			mouthY = -0.3,
		})
		-- 몸통 둘레 양털 고리 + 가슴 + 엉덩이
		local bodyFluff = {}
		for i = 0, 5 do
			local a = math.rad(30 + 60 * i)
			table.insert(bodyFluff, V(math.sin(a), 0.3, -math.cos(a)))
		end
		table.insert(bodyFluff, V(0, 0.55, -1))
		table.insert(bodyFluff, V(0.45, -0.35, 0.9))
		table.insert(bodyFluff, V(-0.45, -0.35, 0.9))
		for i, d in bodyFluff do
			local p, n = surf(c.B, c.BS, d)
			local s = if i % 2 == 0 then 0.66 else 0.6
			ell(b, "Fluff", V(s, s, s), CFrame.new(p - n * 0.12), Wool)
		end
		-- 머리 위/뒤 양털 모자
		local headFluff = { V(0, 1, -0.4), V(0.6, 0.9, -0.2), V(-0.6, 0.9, -0.2), V(0, 1, 0.5), V(0.65, 0.7, 0.6), V(-0.65, 0.7, 0.6) }
		for i, d in headFluff do
			local p, n = surf(c.H, c.HS, d)
			local s = if i % 2 == 0 then 0.62 else 0.68
			ell(b, "Fluff", V(s, s, s), CFrame.new(p - n * 0.1), Wool)
		end
		-- 옆으로 처진 작은 귀
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx, 0.05, -0.1))
			local cf = CFrame.new(p + n * 0.12) * CFrame.Angles(0, 0, -sx * 0.45)
			ell(b, "Ear", V(0.56, 0.28, 0.3), cf, Gy)
			ell(b, "EarInner", V(0.34, 0.14, 0.1), cf * CFrame.new(sx * 0.03, 0, -0.12), RGB(255, 200, 210))
		end
		local tp, tn = surf(c.B, c.BS, V(0, -0.45, 1))
		ell(b, "Tail", V(0.34, 0.34, 0.34), CFrame.new(tp + tn * 0.06), Wool)
	end

	-- 다람쥐: 따뜻한 갈색, 크림 배, 머리 뒤까지 휘어 올라간 복슬 꼬리, 끝털 달린 귀, 두 손으로 든 도토리
	PET_BUILDERS.Squirrel = function(b)
		local Br = RGB(200, 130, 70)
		local Cr = RGB(255, 236, 200)
		local Dk = RGB(130, 80, 45)
		local c = chibi(b, {
			body = Br,
			belly = Cr,
			feet = Dk,
			noArms = true,
			eyeY = 0.06,
			mouthY = -0.42,
			blushX = 0.68,
			blushY = -0.22,
		})
		smallNose(c, -0.24, V(0.18, 0.13, 0.1), Dk, 0.04)
		-- 뾰족 귀 + 끝털 (안쪽 색은 파트 수 때문에 생략)
		pointyEars(c, 0.55, 0.85, 0.42, 0.5, 0.12, 0.25, Br)
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx * 0.55, 0.85, 0))
			local frame = CFrame.new(p - n * 0.14) * CFrame.Angles(0, 0, -sx * 0.25)
			ell(b, "EarTuft", V(0.13, 0.34, 0.13), frame * CFrame.new(0, 0.58, 0), Dk)
		end
		-- 도토리 + 도토리를 감싸 쥔 팔
		local acorn = V(0, c.BeC.Y - 0.02, c.BeC.Z - c.BeS.Z - 0.12)
		ell(b, "Acorn", V(0.4, 0.44, 0.4), CFrame.new(acorn), RGB(215, 160, 95))
		ell(b, "AcornCap", V(0.46, 0.24, 0.46), CFrame.new(acorn + V(0, 0.17, 0)), Dk)
		ell(b, "AcornStem", V(0.07, 0.16, 0.07), CFrame.new(acorn + V(0, 0.33, 0)), Dk)
		for _, sx in SIDES do
			local sp = surf(c.B, c.BS, V(sx, 0.1, -0.5))
			local hand = acorn + V(sx * 0.22, 0.02, 0.02)
			local mid = (sp + hand) * 0.5
			ell(b, "Arm", V(0.3, 0.3, (hand - sp).Magnitude + 0.2), CFrame.lookAt(mid, hand), Br)
		end
		-- 복슬 꼬리: 엉덩이에서 시작해 머리 뒤까지 호를 그리며 올라감
		local tp, tn = surf(c.B, c.BS, V(0, -0.15, 1))
		ell(b, "Tail", V(0.6, 0.6, 0.6), CFrame.new(tp + tn * 0.12), Br)
		local L = V(0, 2.05, 0.95)
		local R = 0.8
		local sizes = { 0.62, 0.78, 0.88, 0.88, 0.78, 0.6 }
		for i, s in sizes do
			local th = math.rad(-70 + 33 * (i - 1))
			local pos = L + V(0, R * math.sin(th), R * math.cos(th))
			ell(b, "Tail", V(s, s, s), CFrame.new(pos), if i >= 5 then RGB(225, 165, 105) else Br)
		end
	end

	-- 고슴도치: 갈색 몸 + 연한 얼굴판, 뾰족 주둥이에 까만 코, 등/머리 뒤를 덮은 두 가지 색 가시
	PET_BUILDERS.Hedgehog = function(b)
		local Br = RGB(150, 110, 80)
		local Tn = RGB(240, 212, 175)
		local Dk = RGB(95, 65, 45)
		local Lt = RGB(215, 175, 120)
		local c = chibi(b, {
			body = Br,
			belly = Tn,
			feet = Dk,
			arms = Dk,
			face = { color = Tn, semi = V(0.92, 0.8, 0.62), offset = V(0, -0.1, -0.42) },
			noMouth = true,
			eyeX = 0.36,
			eyeY = 0.06,
			blushX = 0.62,
			blushY = -0.2,
		})
		-- 뾰족 주둥이 + 까만 코 + 입
		local p, n = front(c.FC, c.FS, 0, -0.3)
		local scf = facing(p + n * 0.08, n)
		ell(b, "Snout", V(0.48, 0.34, 0.44), scf, Tn)
		ell(b, "Nose", V(0.2, 0.16, 0.14), scf * CFrame.new(0, 0.04, -0.2), RGB(35, 28, 28))
		ell(b, "Mouth", V(0.14, 0.06, 0.05), scf * CFrame.new(0, -0.1, -0.19), MOUTH)
		roundEars(c, 0.74, 0.48, 0.3, Lt, nil)
		-- 가시: { 중심, 반지름, 방향, 밝은색? } (머리 뒤/위 + 등. 머리에 가려지는 몸통 윗부분은 피함)
		local spikes = {
			{ c.H, c.HS, V(0, 1, -0.2), false },
			{ c.H, c.HS, V(0.55, 0.95, -0.1), true },
			{ c.H, c.HS, V(-0.55, 0.95, -0.1), true },
			{ c.H, c.HS, V(0, 0.9, 0.55), true },
			{ c.H, c.HS, V(0.7, 0.7, 0.5), false },
			{ c.H, c.HS, V(-0.7, 0.7, 0.5), false },
			{ c.H, c.HS, V(1, 0.3, 0.5), true },
			{ c.H, c.HS, V(-1, 0.3, 0.5), true },
			{ c.H, c.HS, V(0, 0.25, 1), false },
			{ c.B, c.BS, V(0, 0.6, 0.8), true },
			{ c.B, c.BS, V(0.6, 0.35, 0.8), false },
			{ c.B, c.BS, V(-0.6, 0.35, 0.8), false },
			{ c.B, c.BS, V(0.95, 0.4, 0.35), true },
			{ c.B, c.BS, V(-0.95, 0.4, 0.35), true },
		}
		for _, s in spikes do
			local sp, sn = surf(s[1], s[2], s[3])
			ell(b, "Spike", V(0.17, 0.56, 0.17), alongY(sp + sn * 0.14, sn), if s[4] then Lt else Dk)
		end
	end

	-- 라쿤: 회색 몸, 까만 도적 가면(눈은 그 위로), 연한 이마/주둥이, 뾰족 귀, 회색/검정 줄무늬 꼬리
	PET_BUILDERS.Raccoon = function(b)
		local Gy = RGB(140, 140, 150)
		local Cr = RGB(235, 230, 225)
		local Bk = RGB(40, 38, 48)
		local c = chibi(b, {
			body = Gy,
			belly = Cr,
			feet = Bk,
			arms = Bk,
			noMouth = true,
			eyeY = 0.08,
			eyeSize = V(0.34, 0.44, 0.16),
			eyeLift = 0.08,
			blushX = 0.74,
			blushY = -0.3,
		})
		-- 가면: 눈 밑에 깔리는 패치 2개 + 콧대 연결. 눈은 eyeLift 로 가면 앞에 떠 있음
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.42, 0.06)
			ell(b, "Mask", V(0.78, 0.6, 0.16), facing(p - n * 0.04, n) * CFrame.Angles(0, 0, sx * 0.25), Bk)
		end
		local bp, bn = front(c.H, c.HS, 0, 0.04)
		ell(b, "Mask", V(0.4, 0.34, 0.12), facing(bp - bn * 0.03, bn), Bk)
		-- 이마의 밝은 무늬
		local fp, fn = front(c.H, c.HS, 0, 0.5)
		ell(b, "Brow", V(0.72, 0.26, 0.1), facing(fp - fn * 0.02, fn), Cr)
		muzzle(c, V(0.6, 0.4, 0.36), Cr, Bk, -0.38)
		pointyEars(c, 0.55, 0.85, 0.46, 0.5, 0.14, 0.3, Gy, Cr)
		-- 줄무늬 꼬리 (회색/검정 번갈아)
		local tp = surf(c.B, c.BS, V(0, -0.15, 1))
		ballArc(b, "Tail", tp + V(0, 0, 0.1), 0.85, { Gy, Bk, Gy, Bk, Gy }, 0.54, 0.4)
	end

	-- 원숭이: 갈색 몸, 살구색 얼굴판/배, 옆으로 튀어나온 동그란 귀, 고리 모양으로 말린 긴 꼬리, 한 손에 바나나
	PET_BUILDERS.Monkey = function(b)
		local Br = RGB(170, 120, 80)
		local Tn = RGB(245, 210, 170)
		local Yl = RGB(255, 225, 80)
		local c = chibi(b, {
			body = Br,
			belly = Tn,
			feet = darker(Br, 0.2),
			face = { color = Tn, semi = V(0.84, 0.72, 0.62), offset = V(0, -0.14, -0.42) },
			noMouth = true,
			eyeX = 0.34,
			eyeY = 0.1,
			blushX = 0.58,
			blushY = -0.18,
		})
		for _, sx in SIDES do
			local np, nn = front(c.FC, c.FS, sx * 0.1, -0.2)
			ell(b, "Nostril", V(0.08, 0.06, 0.05), facing(np + nn * 0.01, nn), darker(Tn, 0.4))
		end
		local mp, mn = front(c.FC, c.FS, 0, -0.42)
		ell(b, "Mouth", V(0.4, 0.09, 0.06), facing(mp + mn * 0.01, mn), MOUTH)
		roundEars(c, 1, 0.25, 0.6, Br, Tn)
		-- 머리 위 털 두 가닥
		local top = c.H + V(0, c.HS.Y, 0)
		ell(b, "Tuft", V(0.14, 0.38, 0.14), CFrame.new(top + V(-0.1, 0.08, 0.05)) * CFrame.Angles(0, 0, 0.45), Br)
		ell(b, "Tuft", V(0.14, 0.34, 0.14), CFrame.new(top + V(0.12, 0.06, 0.08)) * CFrame.Angles(0, 0, -0.5), Br)
		-- 꼬리: 엉덩이에서 뒤로 올라간 뒤 고리 한 바퀴
		local tp = surf(c.B, c.BS, V(0, -0.2, 1))
		local d1 = V(0, 0.75, 1).Unit
		ell(b, "Tail", V(0.24, 0.24, 0.78), CFrame.lookAt(tp + d1 * 0.32, tp + d1 * 1.32), Br)
		local L = tp + d1 * 0.71 + V(0, 0.42, 0)
		local r = 0.42
		for k = 0, 5 do
			local th = math.rad(30 + 60 * k)
			local pos = L + V(0, -r * math.cos(th), r * math.sin(th))
			local tan = V(0, math.sin(th), math.cos(th))
			ell(b, "Tail", V(0.22, 0.22, 0.52), CFrame.lookAt(pos, pos + tan), Br)
		end
		-- 오른손 바나나 (살짝 휜 두 토막 + 갈색 꼭지)
		local bcf = CFrame.new(0.98, 0.78, -0.5) * CFrame.Angles(0.15, 0.3, -0.25)
		ell(b, "Banana", V(0.17, 0.5, 0.17), bcf * CFrame.new(0.02, 0.18, 0) * CFrame.Angles(0, 0, -0.35), Yl)
		ell(b, "Banana", V(0.17, 0.5, 0.17), bcf * CFrame.new(-0.02, -0.18, 0) * CFrame.Angles(0, 0, 0.35), Yl)
		ell(b, "BananaTip", V(0.1, 0.12, 0.1), bcf * CFrame.new(0.1, 0.44, 0), RGB(110, 80, 50))
	end

	-- 사자: 황금색 몸, 머리를 두르는 주황 갈기 공 고리, 갈기 밖으로 나온 동그란 귀, 끝에 털뭉치 달린 꼬리
	PET_BUILDERS.Lion = function(b)
		local Au = RGB(240, 185, 80)
		local Tn = RGB(255, 228, 175)
		local Mn = RGB(205, 115, 50)
		local Mn2 = RGB(230, 145, 60)
		local c = chibi(b, { body = Au, belly = Tn, feet = darker(Au, 0.12), noMouth = true, eyeY = 0.1, blushX = 0.7, blushY = -0.2 })
		muzzle(c, V(0.62, 0.42, 0.38), Tn, RGB(80, 50, 40), -0.34)
		-- 갈기: 머리 둘레(위에서 36° 간격, 턱 밑은 몸통에 묻히니 생략) 두 톤 공 고리
		for k = -4, 4 do
			local a = math.rad(90 + 36 * k)
			local pos = c.H + V(math.cos(a) * (c.HS.X + 0.02), math.sin(a) * (c.HS.Y + 0.02), 0.4)
			local odd = k % 2 ~= 0
			local s = if odd then 0.78 else 0.86
			ell(b, "Mane", V(s, s, s), CFrame.new(pos), if odd then Mn2 else Mn)
		end
		-- 귀: 갈기 앞으로 살짝 내민 동그란 귀
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx * 0.6, 0.8, 0))
			local ec = p + n * 0.1 + V(0, 0, -0.12)
			ell(b, "Ear", V(0.5, 0.5, 0.3), CFrame.new(ec), Au)
			ell(b, "EarInner", V(0.3, 0.3, 0.08), CFrame.new(ec + V(0, 0, -0.13)), Tn)
		end
		-- 꼬리 + 끝 털뭉치
		local tp = surf(c.B, c.BS, V(0, 0, 1))
		local td = V(0, 0.8, 0.7).Unit
		ell(b, "Tail", V(0.2, 0.2, 0.9), CFrame.lookAt(tp + td * 0.35, tp + td * 1.35), Au)
		ell(b, "TailTuft", V(0.36, 0.36, 0.36), CFrame.new(tp + td * 0.86), Mn)
	end

	-- 앵무새: 초록 몸, 빨간 머리 + 볏, 하얀 눈가, 갈고리 부리, 노랑/파랑 무늬 날개, 빨강/파랑 긴 꼬리깃 3장
	PET_BUILDERS.Parrot = function(b)
		local G = RGB(90, 200, 110)
		local R = RGB(235, 70, 70)
		local Yl = RGB(255, 215, 70)
		local Bl = RGB(70, 140, 255)
		local Or = RGB(255, 160, 60)
		local c = chibi(b, {
			body = G,
			head = R,
			belly = RGB(170, 230, 120),
			feet = RGB(120, 120, 130),
			noArms = true,
			noMouth = true,
			eyeY = 0.1,
			eyeLift = 0.05,
			blushX = 0.78,
			blushY = -0.3,
		})
		-- 눈 둘레 하얀 볼
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.4, 0.08)
			ell(b, "Cheek", V(0.54, 0.66, 0.1), facing(p - n * 0.03, n), WHITE)
		end
		-- 아래로 굽은 부리 (윗부리 + 갈고리 끝 + 아랫부리)
		local p, n = front(c.H, c.HS, 0, -0.26)
		local bcf = facing(p + n * 0.1, n) * CFrame.Angles(-0.35, 0, 0)
		ell(b, "Beak", V(0.36, 0.34, 0.48), bcf, Yl)
		ell(b, "BeakHook", V(0.18, 0.3, 0.18), bcf * CFrame.new(0, -0.14, -0.2), Yl)
		ell(b, "BeakLower", V(0.28, 0.14, 0.3), bcf * CFrame.new(0, -0.2, 0.02), RGB(95, 75, 65))
		-- 볏 3가닥
		local crestDirs = { V(0, 1, 0.15), V(0.4, 0.95, 0.3), V(-0.4, 0.95, 0.3) }
		local crestCols = { Or, Yl, Yl }
		for i, d in crestDirs do
			local cp = surf(c.H, c.HS, d)
			ell(b, "Crest", V(0.2, 0.74, 0.2), alongY(cp + d.Unit * 0.26, d), crestCols[i])
		end
		-- 날개 + 노랑/파랑 무늬
		for _, sx in SIDES do
			local wp, wn = surf(c.B, c.BS, V(sx, 0.1, 0.1))
			local wcf = CFrame.new(wp + wn * 0.02) * CFrame.Angles(0, 0, sx * 0.2)
			ell(b, "Wing", V(0.3, 0.95, 0.72), wcf, darker(G, 0.12))
			ell(b, "WingPatch", V(0.14, 0.46, 0.4), wcf * CFrame.new(sx * 0.12, 0.08, -0.02), Yl)
			ell(b, "WingPatch", V(0.12, 0.3, 0.34), wcf * CFrame.new(sx * 0.14, -0.26, 0.04), Bl)
		end
		-- 긴 꼬리깃 3장 (납작한 세모, 뒤로 펼쳐짐)
		local tp = surf(c.B, c.BS, V(0, -0.1, 1))
		local tailDirs = { V(0, -0.25, 1), V(0.32, -0.2, 1), V(-0.32, -0.2, 1) }
		local tailCols = { R, Bl, Bl }
		for i, d in tailDirs do
			local frame = frameUp(tp + V(0, 0, 0.02), d, Vector3.yAxis)
			tri(b, "TailFeather", frame, 0.36, if i == 1 then 1.4 else 1.2, 0.08, tailCols[i])
		end
	end
end
