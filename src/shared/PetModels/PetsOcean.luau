-- 바다 알 펫 모델 (PetModels/init.luau 가 불러서 등록)
-- 규칙은 init.luau 와 같아요: 앞쪽 = -Z, 바닥 = y 0, 파트 이름 Eye/Shine/Blush 는 얼굴 전용.
return function(Kit, PET_BUILDERS, EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, tri, addEye, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.tri, Kit.addEye, Kit.SIDES
	local addPart, darker, alongY, frameUp = Kit.addPart, Kit.darker, Kit.alongY, Kit.frameUp
	local WHITE, BLUSH, MOUTH = Kit.WHITE, Kit.BLUSH, Kit.MOUTH

	-- 납작 볼터치 (표면 점 + 법선)
	local function blushAt(b, p, n, w)
		ell(b, "Blush", V(w, w * 0.5, 0.06), facing(p, n), BLUSH, nil, 0.1)
	end

	-- 거북이: 초록 몸, 등에 볼록한 갈색 등딱지(판 무늬 + 크림 테두리), 짤막한 물갈퀴 4개, 작은 꼬리
	PET_BUILDERS.Turtle = function(b)
		local G = RGB(120, 200, 120)
		local SH = RGB(135, 115, 70)
		local PL = RGB(95, 125, 60)
		local RIM = RGB(228, 205, 140)

		-- 아래쪽 초록 몸 (배)
		local B = V(0, 0.62, 0)
		ell(b, "Body", V(2.0, 1.0, 1.9), CFrame.new(B), G)

		-- 등딱지
		local SC = V(0, 1.12, 0.05)
		local SS = V(1.15, 0.85, 1.05)
		ell(b, "Shell", SS * 2, CFrame.new(SC), SH)
		ell(b, "ShellRim", V(SS.X * 2 + 0.14, 0.32, SS.Z * 2 + 0.14), CFrame.new(SC + V(0, -0.5, 0)), RIM)
		local plateDirs = {
			V(0, 1, 0.05),
			V(0.7, 0.55, -0.55),
			V(-0.7, 0.55, -0.55),
			V(0.9, 0.5, 0.3),
			V(-0.9, 0.5, 0.3),
			V(0.45, 0.55, 0.9),
			V(-0.45, 0.55, 0.9),
			V(0, 0.3, 1),
		}
		for i, d in plateDirs do
			local p, n = surf(SC, SS, d)
			local s = if i == 1 then 0.62 else 0.5
			ell(b, "Plate", V(s, s * 0.85, 0.08), facing(p + n * 0.01, n), PL)
		end

		-- 머리 (등딱지 앞에서 살짝 위로)
		local H = V(0, 1.62, -1.2)
		local HS = V(0.74, 0.68, 0.64)
		ell(b, "Head", HS * 2, CFrame.new(H), G)
		for _, sx in SIDES do
			addEye(b, H, HS, sx * 0.3, 0.06, V(0.32, 0.42, 0.14), 0)
			local p, n = front(H, HS, sx * 0.5, -0.22)
			blushAt(b, p, n, 0.28)
		end
		local mp, mn = front(H, HS, 0, -0.3)
		ell(b, "Mouth", V(0.3, 0.08, 0.06), facing(mp, mn), MOUTH)

		-- 물갈퀴 4개 (앞/뒤), 바깥으로 벌어지게
		for _, sx in SIDES do
			for _, z in { -0.6, 0.6 } do
				local fwd = if z < 0 then 0.5 else -0.5
				local cf = CFrame.new(sx * 0.98, 0.22, z) * CFrame.Angles(0, sx * fwd, 0)
				ell(b, "Flipper", V(0.78, 0.42, 0.56), cf, G)
			end
		end
		-- 꼬리
		ell(b, "Tail", V(0.3, 0.24, 0.5), CFrame.new(0, 0.5, 1.05), G)
	end

	-- 게: 주황빨강 동글 몸, 앞으로 치켜든 큰 집게 2개, 양옆 다리 4개씩, 자루 위의 눈
	PET_BUILDERS.Crab = function(b)
		local R = RGB(255, 110, 80)
		local Dk = darker(R, 0.2)
		local B = V(0, 0.95, 0)
		local BS = V(1.15, 0.62, 0.9)
		ell(b, "Body", BS * 2, CFrame.new(B), R)

		-- 눈자루 + 눈
		for _, sx in SIDES do
			local base = surf(B, BS, V(sx * 0.45, 1, -0.45))
			local top = base + V(0, 0.42, 0)
			ell(b, "Stalk", V(0.2, 0.6, 0.2), CFrame.new(base + V(0, 0.18, 0)), R)
			ell(b, "StalkTop", V(0.4, 0.4, 0.4), CFrame.new(top), R)
			addEye(b, top, V(0.2, 0.2, 0.2), 0, 0, V(0.28, 0.32, 0.12), 0)
		end

		-- 입 + 볼터치 (몸 앞면)
		local mp, mn = front(B, BS, 0, -0.08)
		ell(b, "Mouth", V(0.3, 0.08, 0.06), facing(mp, mn), MOUTH)
		for _, sx in SIDES do
			local p, n = front(B, BS, sx * 0.62, -0.12)
			blushAt(b, p, n, 0.3)
		end

		-- 집게팔 2개: 팔 → 큰 집게 → 위아래 쐐기 집게발
		for _, sx in SIDES do
			local ap = surf(B, BS, V(sx, 0.15, -0.55))
			local CC = B + V(sx * 1.25, 0.5, -1.05)
			local mid = (ap + CC) * 0.5
			ell(b, "Arm", V(0.32, 0.32, (CC - ap).Magnitude + 0.15), CFrame.lookAt(mid, CC), R)
			local ccf = CFrame.new(CC) * CFrame.Angles(0, -sx * 0.3, 0)
			ell(b, "Claw", V(0.8, 0.64, 0.72), ccf, R)
			for _, sy in SIDES do
				local flip = if sy > 0 then CFrame.new() else CFrame.Angles(0, 0, math.pi)
				local pcf = ccf * CFrame.new(0, sy * 0.1, -0.28) * CFrame.Angles(sy * 0.3, 0, 0) * CFrame.new(0, 0, -0.24) * flip
				addPart(b, "Pincer", "Wedge", V(0.3, 0.22, 0.5), pcf, R)
			end
		end

		-- 다리 4개씩
		local legZ = { -0.55, -0.2, 0.2, 0.55 }
		for _, sx in SIDES do
			for _, zf in legZ do
				local p = surf(B, BS, V(sx, -0.25, zf * 0.8))
				local d = V(sx * 0.8, -1, zf * 0.35).Unit
				ell(b, "Leg", V(0.2, 0.9, 0.2), alongY(p + d * 0.35, d), Dk)
			end
		end
	end

	-- 해파리: 반투명 라벤더 갓(속에 네온 심지 + 빛나는 테두리), 갓 위 얼굴, 흐느적 촉수 6개 (바닥까지)
	PET_BUILDERS.Jellyfish = function(b)
		local L = RGB(190, 160, 255)
		local P = RGB(255, 170, 230)
		local DC = V(0, 2.15, 0)
		local DS = V(1.2, 0.85, 1.2)
		ell(b, "Body", DS * 2, CFrame.new(DC), L, nil, 0.25)
		ell(b, "Core", V(1.1, 0.8, 1.1), CFrame.new(DC + V(0, 0.05, 0)), P, Enum.Material.Neon)
		ell(b, "Rim", V(DS.X * 2 + 0.1, 0.3, DS.Z * 2 + 0.1), CFrame.new(DC + V(0, -0.6, 0)), RGB(225, 205, 255), Enum.Material.Neon, 0.2)

		-- 얼굴 (갓 앞면, 살짝 띄워서 반투명 속에 안 묻히게)
		for _, sx in SIDES do
			addEye(b, DC, DS, sx * 0.42, -0.15, V(0.36, 0.48, 0.16), 0.03)
			local p, n = front(DC, DS, sx * 0.78, -0.42)
			blushAt(b, p + n * 0.03, n, 0.3)
		end
		local mp, mn = front(DC, DS, 0, -0.5)
		ell(b, "Mouth", V(0.2, 0.09, 0.06), facing(mp + mn * 0.03, mn), MOUTH)
		for _, d in { V(0.5, 0.7, -0.5), V(-0.6, 0.55, 0.3) } do
			local p, n = surf(DC, DS, d)
			ell(b, "Sparkle", V(0.14, 0.14, 0.05), facing(p + n * 0.02, n), WHITE, Enum.Material.Neon)
		end

		-- 촉수 6개: 작은 타원체 3개씩, 좌우로 살짝 흔들리게. 맨 아래가 y 0 에 닿아요
		local ys = { 1.2, 0.74, 0.28 }
		for i = 1, 6 do
			local a = (i - 1) * math.pi / 3
			local rx, rz = math.cos(a), math.sin(a)
			local col = if i % 2 == 0 then P else L
			for k, y in ys do
				local wob = math.sin(k * 1.9 + i) * 0.1
				local rad = 0.68 + wob + (k - 1) * 0.08
				local s = 0.3 - (k - 1) * 0.05
				local mat = if k == 3 then Enum.Material.Neon else nil
				ell(b, "Tentacle", V(s, 0.52, s), CFrame.new(rx * rad, y, rz * rad), col, mat)
			end
		end
	end

	-- 문어: 분홍 동글 머리몸, 바닥 둘레로 말린 다리 8개, 왕눈이, 볼터치, 머리 점 3개
	PET_BUILDERS.Octopus = function(b)
		local P = RGB(255, 135, 165)
		local Lt = RGB(255, 190, 210)
		local B = V(0, 1.45, 0)
		local BS = V(1.15, 1.05, 1.1)
		ell(b, "Body", BS * 2, CFrame.new(B), P)
		ell(b, "Skirt", V(1.7, 0.55, 1.7), CFrame.new(0, 0.45, 0), P)

		-- 다리 8개: 바닥에서 바깥으로 뻗고 끝이 위로 말림
		for i = 1, 8 do
			local a = (i - 0.5) * math.pi / 4
			local d = V(math.cos(a), 0, math.sin(a))
			local base = V(d.X * 0.55, 0.22, d.Z * 0.55)
			local tc = base + d * 0.5
			ell(b, "Tentacle", V(0.42, 0.44, 1.05), CFrame.lookAt(tc, tc + d), P)
			ell(b, "TentacleTip", V(0.36, 0.36, 0.36), CFrame.new(base + d * 1.05 + V(0, 0.2, 0)), Lt)
		end

		-- 얼굴
		for _, sx in SIDES do
			addEye(b, B, BS, sx * 0.45, 0.05, V(0.5, 0.62, 0.18), 0)
			local p, n = front(B, BS, sx * 0.9, -0.3)
			blushAt(b, p, n, 0.4)
		end
		local mp, mn = front(B, BS, 0, -0.42)
		ell(b, "Mouth", V(0.2, 0.1, 0.06), facing(mp, mn), MOUTH)
		for _, d in { V(0.45, 0.85, -0.2), V(-0.5, 0.8, 0.1), V(0.1, 0.95, 0.5) } do
			local p, n = surf(B, BS, d)
			ell(b, "Spot", V(0.32, 0.28, 0.06), facing(p, n), Lt)
		end
	end

	-- 아기 상어: 하늘색 몸 + 흰 배, 등지느러미/옆지느러미/꼬리지느러미, 하얀 이빨이 보이는 웃는 입, 앞옆의 눈
	PET_BUILDERS.BabyShark = function(b)
		local Bl = RGB(120, 175, 235)
		local Wt = RGB(240, 248, 255)
		local Dk = darker(Bl, 0.3)
		local B = V(0, 0.9, 0)
		local BS = V(0.85, 0.75, 1.3)
		ell(b, "Body", BS * 2, CFrame.new(B), Bl)
		ell(b, "Belly", V(1.44, 1.12, 2.1), CFrame.new(B + V(0, -0.3, -0.05)), Wt)

		-- 꼬리 + 꼬리지느러미 (위/아래)
		local tc = B + V(0, 0.1, 1.45)
		ell(b, "Tail", V(0.5, 0.5, 0.8), CFrame.new(tc), Bl)
		local tf = tc + V(0, 0, 0.3)
		tri(b, "TailFin", frameUp(tf, V(0, 1, 0.55).Unit, Vector3.xAxis), 0.45, 0.85, 0.14, Bl)
		tri(b, "TailFin", frameUp(tf, V(0, -1, 0.5).Unit, Vector3.xAxis), 0.4, 0.6, 0.14, Bl)

		-- 등지느러미
		local dp, dn = surf(B, BS, V(0, 1, 0.25))
		tri(b, "DorsalFin", frameUp(dp - dn * 0.05, V(0, 1, 0.5).Unit, Vector3.xAxis), 0.8, 0.75, 0.14, Bl)

		-- 옆지느러미
		for _, sx in SIDES do
			local p, n = surf(B, BS, V(sx, -0.3, -0.3))
			tri(b, "Fin", frameUp(p - n * 0.08, V(sx, -0.5, 0.4).Unit, Vector3.yAxis), 0.75, 0.7, 0.12, Bl)
		end

		-- 입 (벌린 입 + 작은 이빨 3개)
		local mp, mn = front(B, BS, 0, -0.25)
		local mcf = facing(mp + mn * 0.02, mn)
		ell(b, "Mouth", V(0.8, 0.3, 0.16), mcf, MOUTH)
		for _, dx in { -0.22, 0, 0.22 } do
			local flipX = if dx < 0 then 1 else -1
			local tcf = mcf * CFrame.new(dx, 0.09, -0.07) * CFrame.fromMatrix(Vector3.zero, V(0, 0, flipX), V(flipX, 0, 0))
			addPart(b, "Tooth", "Wedge", V(0.06, 0.12, 0.14), tcf, WHITE)
		end

		-- 눈 (앞옆), 볼터치, 아가미 줄
		for _, sx in SIDES do
			addEye(b, B, BS, sx * 0.5, 0.15, V(0.34, 0.44, 0.16), 0)
			local p, n = front(B, BS, sx * 0.72, -0.1)
			blushAt(b, p, n, 0.3)
			for _, gz in { -0.35, -0.15 } do
				local gp, gn = surf(B, BS, V(sx, 0.1, gz))
				ell(b, "Gill", V(0.06, 0.4, 0.07), facing(gp, gn), Dk)
			end
		end
	end

	-- 돌고래: 매끈한 청회색 몸, 주둥이, 등/옆지느러미, 꼬리지느러미, 흰 배, 웃는 입.
	-- 몸은 바닥에 눕고 가슴·머리가 위로 들린 자세 (기울인 긴 타원체는 피벗 계산에서 바닥보다 내려가므로 바닥 몸통은 수평)
	PET_BUILDERS.Dolphin = function(b)
		local Gr = RGB(120, 160, 215)
		local Wt = RGB(240, 246, 255)
		local B = V(0, 0.72, 0.35)
		local BS = V(0.72, 0.72, 1.05)
		ell(b, "Body", BS * 2, CFrame.new(B), Gr)
		-- 들린 가슴 (기울어진 타원체, 바닥 위에 떠 있음)
		local CC = V(0, 1.3, -0.5)
		local CF = CFrame.new(CC) * CFrame.Angles(0.9, 0, 0)
		ell(b, "Chest", V(1.36, 1.24, 1.44), CF, Gr)
		ell(b, "Belly", V(1.1, 1.0, 1.1), CF * CFrame.new(0, -0.18, -0.22), Wt)
		-- 머리
		local H = V(0, 2.0, -0.85)
		local HS = V(0.72, 0.66, 0.66)
		ell(b, "Head", HS * 2, CFrame.new(H), Gr)

		-- 주둥이 + 웃는 입
		local rp, rn = front(H, HS, 0, -0.2)
		local rcf = facing(rp + rn * 0.12, rn)
		ell(b, "Rostrum", V(0.5, 0.34, 0.64), rcf, Gr)
		ell(b, "Mouth", V(0.4, 0.07, 0.06), rcf * CFrame.new(0, -0.12, -0.27), MOUTH)

		-- 눈, 볼터치, 숨구멍
		for _, sx in SIDES do
			addEye(b, H, HS, sx * 0.4, 0.12, V(0.32, 0.42, 0.16), 0)
			local bp, bn = front(H, HS, sx * 0.58, -0.14)
			blushAt(b, bp, bn, 0.28)
		end
		local hp, hn = surf(H, HS, V(0, 1, -0.15))
		ell(b, "Blowhole", V(0.12, 0.08, 0.05), facing(hp, hn), darker(Gr, 0.4))

		-- 등지느러미 (몸 위, 뒤로 휘어짐)
		local dp, dn = surf(B, BS, V(0, 1, 0.1))
		tri(b, "DorsalFin", frameUp(dp - dn * 0.05, V(0, 1, 0.55).Unit, Vector3.xAxis), 0.7, 0.65, 0.12, Gr)

		-- 옆지느러미 (가슴 양옆, 앞아래로)
		for _, sx in SIDES do
			local p = CF:PointToWorldSpace(V(sx * 0.6, -0.15, 0))
			tri(b, "Fin", frameUp(p, V(sx, -0.45, -0.3).Unit, Vector3.yAxis), 0.55, 0.6, 0.1, Gr)
		end

		-- 꼬리 + 바닥에 납작하게 놓인 꼬리지느러미
		local t0 = B + V(0, -0.2, 1.0)
		local t1 = V(0, 0.32, 1.65)
		ell(b, "Tail", V(0.42, 0.42, (t1 - t0).Magnitude + 0.3), CFrame.lookAt((t0 + t1) * 0.5, t1), Gr)
		local fe = t1 + V(0, -0.04, 0.12)
		for _, sx in SIDES do
			tri(b, "Fluke", frameUp(fe, V(sx, 0, 0.35).Unit, Vector3.yAxis), 0.5, 0.62, 0.1, Gr)
		end
	end
end
