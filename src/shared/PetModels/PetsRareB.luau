-- v6 아주 희귀 펫 (5~8 구역) 모델 (PetModels/init.luau 가 불러서 등록)
-- 바다: 무지개 해파리 / 진주 해마 / 아기 크라켄 · 캔디: 막대사탕 판다 / 마시멜로 곰 / 사탕 여왕 냥이
-- 구름: 번개 강아지 / 해님 그리핀 / 구미호 · 우주: 운석 햄스터 / 은하 유니콘 / 은하 용
-- 시크릿 < 천상 < 이터널 순서로 장식이 많아져요. 규칙은 init.luau 와 같아요: 앞 = -Z, 바닥 = y 0, 몸통 = Body.
-- 부모님 부탁: 덜 번쩍이게. 네온은 조금만, 빛은 작고 은은하게.
return function(Kit, PET_BUILDERS, _EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, addEye, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.addEye, Kit.chibi, Kit.SIDES
	local addPart, darker, alongX, alongY, tri, frameUp = Kit.addPart, Kit.darker, Kit.alongX, Kit.alongY, Kit.tri, Kit.frameUp
	local muzzle, smallNose, pointyEars, roundEars, dropParts, accAnchor = Kit.muzzle, Kit.smallNose, Kit.pointyEars, Kit.roundEars, Kit.dropParts, Kit.accAnchor
	local WHITE, EYE, BLACK, BLUSH, MOUTH = Kit.WHITE, Kit.EYE, Kit.BLACK, Kit.BLUSH, Kit.MOUTH
	local NEON = Enum.Material.Neon
	local METAL = Enum.Material.Metal
	local GLASS = Enum.Material.Glass

	----------------------------------------------------------------------
	-- 도우미
	----------------------------------------------------------------------

	-- 작고 은은한 빛
	local function glow(parent, color, brightness, range)
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Brightness = brightness
		light.Range = range
		light.Shadows = false
		light.Parent = parent
	end

	-- a → z 를 잇는 길쭉한 타원체 (굵기 d)
	local function seg(b, name, a, z, d, col, mat, tr)
		local dir = z - a
		return ell(b, name, V(d, dir.Magnitude, d), alongY((a + z) * 0.5, dir), col, mat, tr)
	end

	-- a → z 를 잇는 납작한 막대 (번개 조각 등). w = 폭, t = 두께
	local function bar(b, name, a, z, w, t, col, mat)
		local dir = z - a
		return addPart(b, name, "Block", V(w, dir.Magnitude, t), alongY((a + z) * 0.5, dir), col, mat)
	end

	-- 원기둥 (축 = dir, 길이 len, 지름 d)
	local function cyl(b, name, c, dir, len, d, col, mat, tr)
		return addPart(b, name, "Cyl", V(len, d, d), alongX(c, dir), col, mat, tr)
	end

	-- 속눈썹 (눈 크기 w × h 에 맞춰요)
	local function lashes(b, eyes, w, h)
		for i, cf in eyes do
			local sx = if i == 1 then -1 else 1
			addPart(b, "Lash", "Block", V(0.14, 0.04, 0.04), cf * CFrame.new(sx * w * 0.53, h * 0.4, -0.03) * CFrame.Angles(0, 0, sx * 0.6), EYE)
		end
	end

	-- 깃털 날개: root 에서 바깥/위로 부채꼴. f = { 각도(도, 수평 바깥 = 0), 길이, 폭, 색 }
	local function featherWing(b, root, sx, feathers, sweep, lean, thick)
		local nrm = V(-math.sin(sweep), 0, sx * math.cos(sweep))
		for _, f in feathers do
			local th = math.rad(f[1])
			local d = V(sx * math.cos(th) * math.cos(sweep), math.sin(th), math.cos(th) * math.sin(sweep) + math.sin(th) * lean).Unit
			local xv = d:Cross(nrm).Unit
			ell(b, "Wing", V(f[3], f[2], thick), CFrame.fromMatrix(root + d * (f[2] * 0.42), xv, d), f[4])
		end
	end

	-- 다섯 갈래 별 (cf 의 -Z 가 앞). r = 반지름
	local function star5(b, name, cf, r, col, mat)
		for i = 0, 4 do
			local a = i * 2 * math.pi / 5
			ell(b, name, V(r * 0.46, r * 1.2, 0.07), cf * CFrame.new(-math.sin(a) * r * 0.45, math.cos(a) * r * 0.45, 0) * CFrame.Angles(0, 0, a), col, mat)
		end
	end

	-- 기본 몸 파트를 dy 만큼 올려요 (from 번째 파트부터). ctx 도 같이 옮긴 새 ctx 를 돌려줘요
	local function liftCtx(b, c, from, dy)
		local off = V(0, dy, 0)
		for i = from, #b.parts do
			local p = b.parts[i]
			p.CFrame = p.CFrame + off
		end
		local eyes = {}
		for i, cf in c.eyes do
			eyes[i] = cf + off
		end
		return { b = b, B = c.B + off, BS = c.BS, H = c.H + off, HS = c.HS, FC = c.FC + off, FS = c.FS, BeC = c.BeC + off, BeS = c.BeS, eyes = eyes }
	end

	-- 무지개 줄무늬 모자: 같은 모양 타원체를 조금씩 작게, 조금씩 위로 겹치면 꼭대기부터 색 띠가 생겨요.
	-- tops[k] = k 번째 띠의 아래 경계 높이 (반지름 S.Y 비율, 위 띠부터). 마지막 띠 아래는 몸 색
	local function stripeCap(b, C, S, cols, tops, step)
		local sNext, dNext = 1, 0
		for k = #cols, 1, -1 do
			local d = step * (#cols - k + 1)
			local c = tops[k]
			local rho2 = 1 - c * c
			local root = math.sqrt(math.max(sNext * sNext - rho2, 0)) - (d - dNext) / S.Y
			local s = math.sqrt(rho2 + math.max(root, 0) ^ 2)
			ell(b, "Stripe", S * 2 * s, CFrame.new(C + V(0, d, 0)), cols[k])
			sNext, dNext = s, d
		end
	end

	----------------------------------------------------------------------
	-- 5. 바다
	----------------------------------------------------------------------

	-- 무지개 해파리 (시크릿): 동그란 하얀 갓 위쪽에 무지개 줄무늬, 왕눈이, 라일락 테두리, 끝이 도르르 말린 무지개 촉수 6개
	PET_BUILDERS.RainbowJelly = function(b)
		local SHELL = RGB(255, 246, 250)
		local C = V(0, 1.95, 0)
		local S = V(1.12, 0.98, 1.08)
		ell(b, "Body", S * 2, CFrame.new(C), SHELL)
		stripeCap(b, C, S, {
			RGB(255, 125, 150),
			RGB(255, 175, 100),
			RGB(255, 225, 110),
			RGB(140, 225, 160),
			RGB(130, 195, 255),
		}, { 0.84, 0.68, 0.52, 0.36, 0.2 }, 0.045)
		ell(b, "Rim", V(2.36, 0.32, 2.28), CFrame.new(C + V(0, -0.7, 0)), RGB(205, 175, 255))

		-- 얼굴: 아주 큰 눈 + 볼터치 + 방긋 입
		for _, sx in SIDES do
			addEye(b, C, S, sx * 0.42, -0.24, V(0.46, 0.6, 0.18), 0)
			local p, n = front(C, S, sx * 0.8, -0.42)
			ell(b, "Blush", V(0.34, 0.18, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		local mp, mn = front(C, S, 0, -0.5)
		ell(b, "Mouth", V(0.26, 0.12, 0.06), facing(mp + mn * 0.01, mn), MOUTH)
		-- 꼭대기 반짝 별
		local tp = C + V(0, S.Y + 0.17, 0)
		ell(b, "Sparkle", V(0.2, 0.2, 0.2), CFrame.new(tp), RGB(255, 250, 220), NEON)

		-- 촉수 6개: 갓 밑에서 바깥 아래로 → 바닥 공 → 바깥 위로 도르르
		local cols = { RGB(255, 140, 165), RGB(255, 190, 120), RGB(255, 228, 125), RGB(150, 225, 165), RGB(140, 195, 255), RGB(195, 160, 255) }
		for i = 1, 6 do
			local a = math.rad((i - 1) * 60 + 30)
			local d = V(math.cos(a), 0, math.sin(a))
			local col = cols[(i + 2) % 6 + 1]
			local p0 = d * 0.5 + V(0, 1.12, 0)
			local p1 = d * 0.86 + V(0, 0.25, 0)
			seg(b, "Tentacle", p0, p1, 0.3, col)
			ell(b, "Tentacle", V(0.3, 0.3, 0.3), CFrame.new(d * 0.92 + V(0, 0.15, 0)), col)
			ell(b, "Tentacle", V(0.2, 0.2, 0.2), CFrame.new(d * 1.1 + V(0, 0.3, 0)), col)
		end
	end

	-- 진주 해마 (천상): 파스텔 분홍 해마, 앞으로 쭉 뻗은 주둥이, 크림 배 주름, 등 가시 + 하늘색 지느러미,
	-- 뒤로 도르르 말린 꼬리, 금 왕관 (뾰족 끝마다 진주, 앞 가운데 큰 진주만 은은하게 빛나요)
	PET_BUILDERS.PearlSeahorse = function(b)
		local P = RGB(255, 190, 220)
		local CR = RGB(255, 236, 205)
		local AQ = RGB(150, 225, 235)
		local GOLD = RGB(255, 210, 120)
		local PEARL = RGB(255, 246, 250)
		local B = V(0, 1.3, 0)
		local BS = V(0.7, 0.8, 0.64)
		ell(b, "Body", BS * 2, CFrame.new(B), P)
		local H = V(0, 2.45, -0.1)
		local HS = V(0.9, 0.8, 0.82)
		ell(b, "Head", HS * 2, CFrame.new(H), P)
		-- 배 (앞으로 볼록) + 주름 3줄
		local BeC, BeS = B + V(0, -0.05, -0.22), V(0.52, 0.64, 0.5)
		ell(b, "Belly", BeS * 2, CFrame.new(BeC), CR)
		for _, y in { 0.3, 0, -0.3 } do
			local p, n = front(BeC, BeS, 0, y)
			ell(b, "Ridge", V(0.6 * math.sqrt(1 - (y / BeS.Y) ^ 2), 0.06, 0.06), facing(p, n), darker(CR, 0.12))
		end
		-- 주둥이 (거의 수평으로 앞) + 동그란 입
		local sp = front(H, HS, 0, -0.28)
		local sd = V(0, -0.08, -1).Unit
		local snc = sp + sd * 0.22 + V(0, 0, 0.04)
		ell(b, "Snout", V(0.34, 0.32, 0.72), CFrame.lookAt(snc, snc + sd), P)
		ell(b, "Mouth", V(0.2, 0.15, 0.06), CFrame.lookAt(snc + sd * 0.36, snc + sd * 2), MOUTH)
		-- 얼굴
		local eyes = {}
		for _, sx in SIDES do
			table.insert(eyes, addEye(b, H, HS, sx * 0.42, 0.1, V(0.38, 0.5, 0.16), 0))
			local p, n = front(H, HS, sx * 0.64, -0.22)
			ell(b, "Blush", V(0.3, 0.16, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		lashes(b, eyes, 0.38, 0.5)
		-- 귀 지느러미 + 등 가시 3개 + 등지느러미
		for _, sx in SIDES do
			local p, n = surf(H, HS, V(sx, 0.05, 0.25))
			ell(b, "Fin", V(0.1, 0.46, 0.36), CFrame.new(p + n * 0.06) * CFrame.Angles(0.25, 0, -sx * 0.35), AQ)
		end
		for _, s in { { H, HS, V(0, 0.45, 1) }, { H, HS, V(0, -0.25, 1) }, { B, BS, V(0, 0.55, 1) } } do
			local kp, kn = surf(s[1], s[2], s[3])
			ell(b, "Spike", V(0.14, 0.3, 0.24), alongY(kp + kn * 0.07, kn), AQ)
		end
		local dp, dn = surf(B, BS, V(0, -0.05, 1))
		ell(b, "Fin", V(0.1, 0.8, 0.5), CFrame.new(dp + dn * 0.12) * CFrame.Angles(-0.25, 0, 0), AQ)
		-- 꼬리: 몸 밑에서 뒤로 내려가 바닥에 닿고, 위로 도르르 말려요
		local tail = {
			{ V(0, 0.55, 0.36), 0.46 },
			{ V(0, 0.2, 0.58), 0.4 },
			{ V(0, 0.22, 0.92), 0.32 },
			{ V(0, 0.46, 1.04), 0.26 },
			{ V(0, 0.62, 0.92), 0.2 },
		}
		for _, t in tail do
			ell(b, "Tail", V(t[2], t[2], t[2]), CFrame.new(t[1]), P)
		end
		-- 왕관: 금 띠 + 뾰족 끝 3개 (끝마다 진주) + 앞 가운데 큰 진주
		local cy = 0.6
		local crc = H + V(0, cy, 0)
		local cr = HS.X * math.sqrt(1 - ((cy - 0.09) / HS.Y) ^ 2)
		addPart(b, "CrownBand", "Cyl", V(0.2, cr * 2 + 0.06, cr * 2 + 0.06), CFrame.new(crc) * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
		for _, a in { -0.75, 0, 0.75 } do
			local dir = V(math.sin(a), 0, -math.cos(a))
			local base = crc + dir * (cr + 0.01) + V(0, 0.02, 0)
			tri(b, "CrownTip", frameUp(base, Vector3.yAxis, dir), 0.32, 0.42, 0.06, GOLD, METAL)
			local pearl = ell(b, "Pearl", V(0.16, 0.16, 0.16), CFrame.new(base + V(0, 0.44, 0)), PEARL)
			pearl.Reflectance = 0.2
		end
		ell(b, "Pearl", V(0.22, 0.22, 0.16), CFrame.new(crc + V(0, -0.01, -(cr + 0.06))), RGB(255, 225, 240), NEON)
		-- 주둥이 끝 물방울 (반투명)
		ell(b, "Bubble", V(0.18, 0.18, 0.18), CFrame.new(snc + sd * 0.42 + V(0.1, 0.16, 0)), RGB(210, 240, 255), GLASS, 0.45)
		local body = b.model:FindFirstChild("Body")
		if body then
			glow(body, RGB(255, 215, 235), 0.35, 5)
		end
	end

	-- 아기 크라켄 (이터널): 통통한 보라 문어 왕눈이, 살짝 비스듬한 선장 모자, 바닥에 말린 다리 6개 +
	-- 앞으로 든 다리 2개 (오른쪽은 금 망원경), 은은한 청록 점 3개
	PET_BUILDERS.BabyKraken = function(b)
		local PU = RGB(160, 110, 225)
		local LT = RGB(205, 175, 250)
		local NAVY = RGB(45, 55, 110)
		local GOLD = RGB(255, 205, 90)
		local C = V(0, 1.62, 0)
		local S = V(1.2, 1.1, 1.12)
		local body = ell(b, "Body", S * 2, CFrame.new(C), PU)
		ell(b, "Skirt", V(2.1, 0.62, 2.0), CFrame.new(0, 0.58, 0.05), PU)
		-- 얼굴
		for _, sx in SIDES do
			addEye(b, C, S, sx * 0.44, -0.02, V(0.5, 0.62, 0.18), 0)
			local p, n = front(C, S, sx * 0.86, -0.36)
			ell(b, "Blush", V(0.36, 0.18, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		local mp, mn = front(C, S, 0, -0.42)
		ell(b, "Mouth", V(0.26, 0.1, 0.06), facing(mp, mn), MOUTH)
		-- 은은한 청록 점 (네온은 작게 3개만)
		for _, d in { V(0.8, 0.45, 0.3), V(-0.75, 0.35, 0.5), V(0.2, 0.55, 0.85) } do
			local p, n = surf(C, S, d)
			ell(b, "Spot", V(0.22, 0.2, 0.06), facing(p, n), RGB(120, 235, 225), NEON)
		end
		-- 선장 모자 (오른쪽으로 살짝 기울어요): 남색 띠 + 하얀 윗판 + 까만 챙 + 금 배지
		local hcf = CFrame.new(0.12, C.Y + S.Y - 0.1, 0.0) * CFrame.Angles(-0.12, 0, -0.16)
		addPart(b, "HatBand", "Cyl", V(0.3, 1.0, 1.0), hcf * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2), NAVY)
		ell(b, "HatTop", V(1.24, 0.34, 1.2), hcf * CFrame.new(0, 0.33, 0.02), RGB(250, 250, 255))
		ell(b, "HatBrim", V(0.8, 0.08, 0.46), hcf * CFrame.new(0, 0.0, -0.5) * CFrame.Angles(0.25, 0, 0), RGB(30, 30, 40))
		ell(b, "HatBadge", V(0.22, 0.2, 0.06), hcf * CFrame.new(0, 0.14, -0.5), GOLD, METAL)
		accAnchor(b, "Head", hcf * CFrame.new(0, 0.48, 0.02))
		-- 바닥 다리 6개 (밖으로 뻗고 끝이 위로 말림)
		for i = 1, 8 do
			local a = math.rad((i - 1) * 45 + 22.5)
			local d = V(math.cos(a), 0, math.sin(a))
			if i == 6 or i == 7 then
				continue -- 앞쪽 둘은 들고 있어요
			end
			local tc = d * 0.78 + V(0, 0.21, 0.05)
			ell(b, "Tentacle", V(0.46, 0.42, 1.0), CFrame.lookAt(tc, tc + d), PU)
			ell(b, "TentacleTip", V(0.34, 0.34, 0.34), CFrame.new(d * 1.28 + V(0, 0.33, 0.05)), LT)
		end
		-- 앞으로 든 다리 2개 + 빨판
		local grip = V(0, 0, 0)
		for _, sx in SIDES do
			local a0 = V(sx * 0.7, 0.62, -0.62)
			local a1 = V(sx * 1.25, 1.25, -0.72)
			seg(b, "Tentacle", a0, a1, 0.38, PU)
			local tip = a1 + (a1 - a0).Unit * 0.04 + V(0, 0.08, 0)
			ell(b, "TentacleTip", V(0.3, 0.3, 0.3), CFrame.new(tip), LT)
			if sx > 0 then
				grip = tip
			end
			for _, f in { 0.3, 0.6 } do
				local sp = a0:Lerp(a1, f) + V(-sx * 0.1, -0.08, -0.14)
				ell(b, "Sucker", V(0.12, 0.12, 0.06), facing(sp, V(-sx * 0.3, -0.3, -1).Unit), LT)
			end
		end
		-- 금 망원경 (오른쪽 다리)
		local gd = V(0.15, 0.25, -1).Unit
		local gc = grip + gd * 0.12 + V(0, 0.04, 0)
		cyl(b, "Spyglass", gc, gd, 0.62, 0.16, GOLD, METAL)
		cyl(b, "Spyglass", gc + gd * 0.36, gd, 0.14, 0.22, darker(GOLD, 0.2), METAL)
		cyl(b, "Lens", gc + gd * 0.43, gd, 0.04, 0.17, RGB(120, 190, 255), GLASS, 0.2)
		glow(body, RGB(170, 140, 255), 0.4, 6)
	end

	----------------------------------------------------------------------
	-- 6. 캔디 랜드
	----------------------------------------------------------------------

	-- 막대사탕 판다 (시크릿): 판다, 사탕 분홍 귀, 머리에 작은 분홍 리본, 오른손에 소용돌이 막대사탕
	PET_BUILDERS.LollipopPanda = function(b)
		local Wt = RGB(252, 250, 252)
		local Bk = RGB(40, 40, 48)
		local PK = RGB(255, 140, 190)
		local c = chibi(b, {
			body = Wt,
			feet = Bk,
			arms = Bk,
			eyeY = 0,
			eyeLift = 0.06,
			eyeSize = V(0.32, 0.44, 0.16),
			mouthY = -0.4,
			blushX = 0.76,
			blushY = -0.3,
		})
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.4, -0.02)
			ell(b, "EyePatch", V(0.52, 0.68, 0.14), facing(p, n) * CFrame.Angles(0, 0, sx * 0.45), Bk)
		end
		smallNose(c, -0.24, V(0.22, 0.14, 0.1), Bk, 0.03)
		roundEars(c, 0.62, 0.78, 0.54, PK, RGB(255, 205, 225))
		-- 왼쪽 귀 옆 리본
		local rp, rn = surf(c.H, c.HS, V(-0.55, 0.85, -0.25))
		local rcf = facing(rp + rn * 0.04, rn)
		for _, sx in SIDES do
			ell(b, "Bow", V(0.3, 0.22, 0.1), rcf * CFrame.new(sx * 0.13, 0, 0) * CFrame.Angles(0, 0, sx * 0.3), PK)
		end
		ell(b, "Bow", V(0.12, 0.12, 0.1), rcf * CFrame.new(0, 0, -0.02), RGB(255, 205, 225))
		-- 막대사탕: 막대 + 겹친 원판 4장 (조금씩 비켜서 소용돌이처럼)
		local ap, an = surf(c.B, c.BS, V(1, -0.05, -0.45))
		local hand = ap + an * 0.12 + V(0, 0, -0.08)
		local top = hand + V(0.28, 1.24, -0.04)
		cyl(b, "Stick", (hand + top) * 0.5, top - hand, (top - hand).Magnitude, 0.12, RGB(255, 250, 245))
		local cc = top + V(0.05, 0.32, -0.02)
		local disks = {
			{ 0.92, V(0, 0, 0), PK },
			{ 0.7, V(0.05, 0.03, -0.012), RGB(255, 250, 250) },
			{ 0.5, V(0.02, 0.07, -0.024), RGB(140, 215, 255) },
			{ 0.3, V(0.06, 0.06, -0.036), RGB(255, 250, 250) },
		}
		for _, dk in disks do
			addPart(b, "Candy", "Cyl", V(0.14, dk[1], dk[1]), CFrame.new(cc + dk[2]) * CFrame.Angles(0, math.pi / 2, 0), dk[3])
		end
		-- 손잡이 리본
		local kp = hand:Lerp(top, 0.62) + V(0, 0, -0.07)
		for _, sx in SIDES do
			ell(b, "Ribbon", V(0.24, 0.16, 0.08), CFrame.new(kp + V(sx * 0.1, 0, 0)) * CFrame.Angles(0, 0, sx * 0.35), RGB(150, 225, 190))
		end
		-- 머리 위 알록달록 스프링클
		local spr = { { V(0.25, 1, -0.35), RGB(255, 120, 170) }, { V(-0.1, 1, 0.1), RGB(120, 200, 255) }, { V(0.45, 0.9, 0.25), RGB(255, 215, 90) } }
		for i, s in spr do
			local p, n = surf(c.H, c.HS, s[1])
			addPart(b, "Sprinkle", "Block", V(0.2, 0.07, 0.07), facing(p + n * 0.02, n) * CFrame.Angles(0, 0, i * 0.9), s[2])
		end
	end

	-- 마시멜로 곰 (천상): 폭신한 원기둥 마시멜로 머리/몸, 윗면 가장자리와 아랫면이 노릇노릇 구운 금빛,
	-- 미니 마시멜로 귀/발, 분홍 리본, 설탕 반짝이
	PET_BUILDERS.MarshmallowBear = function(b)
		local MW = RGB(255, 252, 247)
		local TOAST = RGB(245, 198, 120)
		local TOAST2 = RGB(232, 175, 98)
		local up = Vector3.yAxis
		-- 몸: 작은 마시멜로 (세운 원기둥 + 노릇한 폭신 아랫면)
		local BR = 0.84
		local BH = 1.1
		local BC = V(0, 0.35 + BH * 0.5, 0)
		cyl(b, "Body", BC, up, BH, BR * 2, MW)
		ell(b, "Toast", V(BR * 2, 0.36, BR * 2), CFrame.new(V(0, 0.35, 0)), TOAST2)
		-- 머리: 큰 마시멜로. 윗면은 금빛 판 위에 작은 하얀 판을 겹쳐 가장자리만 노릇하게
		local HC = V(0, 1.98, 0)
		local HR = 1.08
		local HH = 1.1
		cyl(b, "Marsh", HC, up, HH, HR * 2, MW)
		ell(b, "HeadTop", V(HR * 2, 0.7, HR * 2), CFrame.new(HC + V(0, HH * 0.5 - 0.1, 0)), TOAST)
		ell(b, "HeadTop", V(HR * 2 - 0.5, 0.76, HR * 2 - 0.5), CFrame.new(HC + V(0, HH * 0.5 - 0.08, 0)), MW)
		-- 노릇한 아랫면을 "Head" 로: 옷 자리 재기가 목을 머리 아래 몸 위에서 찾아요 (목도리가 턱 밑에 쏙)
		ell(b, "Head", V(HR * 2, 0.48, HR * 2), CFrame.new(HC + V(0, -HH * 0.5, 0)), TOAST)
		-- 원기둥 앞면 위의 점
		local FS = V(HR, 50, HR)
		local function face(x, y)
			return front(HC, FS, x, y)
		end
		local eyes = {}
		for _, sx in SIDES do
			table.insert(eyes, addEye(b, HC, FS, sx * 0.42, 0.12, V(0.36, 0.5, 0.16), 0))
			local p, n = face(sx * 0.72, -0.2)
			ell(b, "Blush", V(0.32, 0.17, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		local mp, mn = face(0, -0.26)
		local mcf = facing(mp - mn * 0.04, mn)
		ell(b, "Muzzle", V(0.6, 0.4, 0.3), mcf, RGB(255, 240, 220))
		ell(b, "Nose", V(0.24, 0.16, 0.12), mcf * CFrame.new(0, 0.09, -0.13), RGB(120, 75, 50))
		ell(b, "Mouth", V(0.14, 0.06, 0.05), mcf * CFrame.new(0, -0.08, -0.15), MOUTH)
		-- 미니 마시멜로 귀 (앞을 보는 작은 원기둥) + 노릇한 안쪽
		for _, sx in SIDES do
			local ec = HC + V(sx * 0.72, HH * 0.5 + 0.2, 0.05)
			cyl(b, "Ear", ec, Vector3.zAxis, 0.3, 0.56, MW)
			cyl(b, "EarInner", ec + V(0, 0, -0.13), Vector3.zAxis, 0.08, 0.34, TOAST)
		end
		-- 팔 + 미니 마시멜로 발 + 꼬리
		for _, sx in SIDES do
			ell(b, "Arm", V(0.42, 0.6, 0.42), CFrame.new(V(sx * 0.88, 0.83, -0.3)) * CFrame.Angles(0, 0, sx * 0.35), MW)
			cyl(b, "Foot", V(sx * 0.44, 0.16, -0.42), up, 0.32, 0.6, MW)
		end
		cyl(b, "Tail", V(0, 0.68, BR + 0.08), Vector3.zAxis, 0.22, 0.4, MW)
		-- 분홍 리본 (오른쪽 귀 아래)
		local rn = V(0.5, 0, -0.866)
		local rcf = CFrame.lookAt(HC + V(0, HH * 0.5 - 0.04, 0) + rn * (HR + 0.03), HC + V(0, HH * 0.5 - 0.04, 0) + rn * 3)
		for _, sx in SIDES do
			ell(b, "Bow", V(0.32, 0.24, 0.1), rcf * CFrame.new(sx * 0.14, 0, 0) * CFrame.Angles(0, 0, sx * 0.3), RGB(255, 160, 200))
		end
		ell(b, "Bow", V(0.13, 0.13, 0.1), rcf * CFrame.new(0, 0, -0.03), RGB(255, 205, 225))
		-- 설탕 반짝이 (작은 네온 2개 + 금빛 1개)
		local sugar = { { V(-0.62, 0.42), WHITE }, { V(0.7, 0.32), RGB(255, 235, 170) }, { V(-0.75, -0.42), WHITE } }
		for i, s in sugar do
			local p, n = face(s[1].X, s[1].Y)
			addPart(b, "Sugar", "Block", V(0.11, 0.11, 0.11), facing(p + n * 0.02, n) * CFrame.Angles(0, 0, 0.4 + i), s[2], if i < 3 then NEON else nil)
		end
		local body = b.model:FindFirstChild("Body")
		if body then
			glow(body, RGB(255, 220, 160), 0.35, 5)
		end
	end

	-- 사탕 여왕 냥이 (이터널): 연분홍 고양이, 젤리 보석 사탕 왕관, 하트 브로치가 달린 보라 망토 + 하얀 털 깃,
	-- 오른손에 별 요술봉 (별 가운데만 은은하게), 사탕 줄무늬 꼬리
	PET_BUILDERS.SweetQueenCat = function(b)
		local PKW = RGB(255, 228, 240)
		local PK = RGB(255, 160, 200)
		local CAPE = RGB(190, 90, 200)
		local GOLD = RGB(255, 210, 110)
		local c = chibi(b, { body = PKW, belly = WHITE, feet = RGB(255, 205, 225), eyeY = 0.05, noMouth = true, blushY = -0.22 })
		lashes(b, c.eyes, 0.36, 0.5)
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.16, -0.33)
			ell(b, "Muzzle", V(0.42, 0.32, 0.28), facing(p - n * 0.06, n), WHITE)
		end
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 120, 165), 0.04)
		pointyEars(c, 0.55, 0.85, 0.6, 0.62, 0.16, 0.3, PKW)
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx * 0.55, 0.85, 0))
			ell(b, "EarInner", V(0.26, 0.34, 0.04), CFrame.new(p - n * 0.14) * CFrame.Angles(0, 0, -sx * 0.3) * CFrame.new(0, 0.22, -0.1), PK)
		end
		-- 사탕 왕관: 귀 사이 앞쪽에 살짝 앞으로 기운 작은 금 띠 + 뾰족한 젤리 보석 3개 + 앞 하트 보석
		local tz = -0.22
		local ty = c.HS.Y * math.sqrt(1 - (tz / c.HS.Z) ^ 2)
		local tcf = CFrame.new(c.H + V(0, ty - 0.14, tz)) * CFrame.Angles(-0.22, 0, 0)
		addPart(b, "CrownBand", "Cyl", V(0.26, 0.92, 0.92), tcf * CFrame.Angles(0, 0, math.pi / 2), GOLD, METAL)
		local gems = { { -0.75, RGB(130, 225, 190) }, { 0, RGB(255, 120, 170) }, { 0.75, RGB(150, 200, 255) } }
		for _, g in gems do
			ell(b, "Gumdrop", V(0.22, 0.36, 0.22), tcf * CFrame.new(math.sin(g[1]) * 0.36, 0.27, -math.cos(g[1]) * 0.36), g[2])
		end
		ell(b, "Jewel", V(0.2, 0.17, 0.08), tcf * CFrame.new(0, 0, -0.48), RGB(255, 80, 130))
		-- 망토: 등 뒤로 늘어진 넓은 판 + 하얀 털 깃 + 하트 브로치
		ell(b, "Cape", V(2.5, 1.95, 0.16), CFrame.new(0, 1.02, 0.84) * CFrame.Angles(-0.16, 0, 0), CAPE)
		ell(b, "Collar", V(1.72, 0.32, 1.58), CFrame.new(0, c.B.Y + c.BS.Y - 0.12, 0.05), WHITE)
		ell(b, "Brooch", V(0.22, 0.22, 0.1), CFrame.new(0, c.B.Y + c.BS.Y - 0.14, -0.82), RGB(255, 90, 140))
		accAnchor(b, "Back", CFrame.new(0, 1.15, 0.98))
		-- 요술봉 (오른손): 막대 + 별 + 가운데 빛
		local ap, an = surf(c.B, c.BS, V(1, -0.05, -0.45))
		local hand = ap + an * 0.12 + V(0, 0, -0.08)
		local tip = hand + V(0.3, 1.12, -0.06)
		cyl(b, "Wand", (hand + tip) * 0.5, tip - hand, (tip - hand).Magnitude, 0.1, RGB(255, 250, 245))
		local scf = CFrame.lookAt(tip + V(0, 0.22, 0), tip + V(0, 0.22, -1))
		star5(b, "WandStar", scf, 0.3, RGB(255, 225, 110))
		local core = ell(b, "WandCore", V(0.18, 0.18, 0.12), scf * CFrame.new(0, 0, -0.03), RGB(255, 245, 190), NEON)
		glow(core, RGB(255, 230, 160), 0.4, 5)
		-- 사탕 줄무늬 꼬리 (분홍 / 하양 번갈아)
		local tp = surf(c.B, c.BS, V(0.25, -0.3, 1))
		local tpts = { tp + V(0, 0, -0.05), tp + V(0.12, 0.3, 0.32), tp + V(0.3, 0.75, 0.42), tp + V(0.42, 1.15, 0.3) }
		local tailCols = { PK, WHITE, PK }
		for i = 1, 3 do
			local a, z = tpts[i], tpts[i + 1]
			local d = (z - a).Unit
			seg(b, "Tail", a - d * 0.06, z + d * 0.06, 0.3 - 0.02 * i, tailCols[i])
		end
	end

	----------------------------------------------------------------------
	-- 7. 구름 왕국
	----------------------------------------------------------------------

	-- 번개 강아지 (시크릿): 회청색 강아지, 머리 위 구름 뭉치, 늘어진 귀, 번개 꼬리, 번개 이름표
	PET_BUILDERS.ThunderPup = function(b)
		local GB = RGB(150, 172, 212)
		local DK = RGB(95, 115, 160)
		local Cr = RGB(235, 240, 252)
		local YL = RGB(255, 222, 80)
		local c = chibi(b, { body = GB, belly = Cr, feet = DK, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		local mcf = muzzle(c, V(0.62, 0.42, 0.4), Cr, RGB(45, 45, 60), -0.32)
		ell(b, "Tongue", V(0.14, 0.13, 0.06), mcf * CFrame.new(0, -0.17, -0.13), RGB(255, 120, 140))
		for _, sx in SIDES do
			ell(b, "Ear", V(0.42, 0.85, 0.26), CFrame.new(c.H + V(sx * 1.08, 0.22, 0.05)) * CFrame.Angles(0, 0, sx * 0.25), DK)
		end
		-- 구름 뭉치 (모자를 쓰면 밑에 깔려요)
		local top = c.H + V(0, c.HS.Y, 0)
		for _, t in { { V(0, 0.06, 0.05), 0.62 }, { V(-0.3, -0.04, 0.12), 0.46 }, { V(0.3, -0.03, 0.08), 0.48 }, { V(0.08, 0.2, 0.28), 0.42 } } do
			ell(b, "Tuft", V(t[2], t[2] * 0.85, t[2]), CFrame.new(top + t[1]), WHITE)
		end
		-- 목걸이 + 번개 이름표
		local ny = c.B.Y + c.BS.Y - 0.2
		addPart(b, "Collar", "Cyl", V(0.18, 1.6, 1.6), CFrame.new(0, ny, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(70, 90, 150))
		local tg = V(0, ny - 0.16, -0.83)
		bar(b, "Tag", tg + V(0.05, 0.1, 0), tg + V(-0.04, -0.02, 0), 0.1, 0.05, YL)
		bar(b, "Tag", tg + V(0.05, 0.0, -0.005), tg + V(-0.04, -0.14, -0.005), 0.1, 0.05, YL)
		-- 번개 꼬리: 엉덩이에서 위로 지그재그 (앞에서도 어깨 너머로 보여요)
		local root = surf(c.B, c.BS, V(0.25, 0.1, 1))
		local pts = { root + V(0, 0, -0.08), V(0.6, 1.55, 1.02), V(0.32, 1.72, 1.06), V(0.95, 2.55, 1.1) }
		bar(b, "Tail", pts[1], pts[2], 0.24, 0.12, YL)
		bar(b, "Tail", pts[2] + V(0.04, -0.06, 0), pts[3] + V(-0.04, 0.04, 0), 0.22, 0.12, YL)
		bar(b, "Tail", pts[3], pts[4], 0.24, 0.12, YL)
		ell(b, "TailTip", V(0.16, 0.16, 0.13), CFrame.new(pts[4]), RGB(255, 245, 170), NEON)
	end

	-- 해님 그리핀 (천상): 금빛 독수리 아기 + 사자 발/꼬리, 머리 뒤로 해님 햇살 깃털 부채, 금빛 깃털 날개, 이마에 작은 해
	PET_BUILDERS.SunGriffin = function(b)
		local G = RGB(255, 200, 85)
		local GH = RGB(255, 222, 125)
		local Cr = RGB(255, 242, 205)
		local OR = RGB(255, 150, 60)
		local PAW = RGB(235, 172, 90)
		local c = chibi(b, { body = G, head = GH, belly = Cr, feet = PAW, arms = PAW, noMouth = true, eyeY = 0.06 })
		-- 갈고리 부리
		local p, n = front(c.H, c.HS, 0, -0.24)
		local bcf = facing(p + n * 0.06, n)
		ell(b, "Beak", V(0.36, 0.26, 0.34), bcf, RGB(255, 165, 55))
		ell(b, "Beak", V(0.16, 0.2, 0.14), bcf * CFrame.new(0, -0.1, -0.12) * CFrame.Angles(0.5, 0, 0), RGB(240, 140, 45))
		-- 해님 햇살 깃털: 머리 뒤에서 위/옆으로 부채꼴 7장 (주황/금 번갈아)
		local fc = c.H + V(0, 0.05, 0.42)
		for i = 0, 6 do
			local a = math.rad(-84 + i * 28)
			local d = V(math.sin(a), math.cos(a), 0)
			local r0 = 0.86
			local len = if i % 2 == 0 then 0.78 else 0.62
			local mid = fc + d * (r0 + len * 0.32) + V(0, 0, 0.12)
			ell(b, "SunRay", V(0.3, len, 0.1), CFrame.fromMatrix(mid, V(d.Y, -d.X, 0), d), if i % 2 == 0 then OR else RGB(255, 205, 70))
		end
		-- 이마 위 작은 해 (은은한 네온)
		local sp, sn = front(c.H, c.HS, 0, 0.52)
		ell(b, "SunMark", V(0.24, 0.24, 0.06), facing(sp + sn * 0.01, sn), RGB(255, 170, 70), NEON)
		-- 금빛 깃털 날개 (3장씩, 끝은 주황)
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * 0.6, 0.45, 0.75))
			featherWing(b, root, sx, { { 52, 1.25, 0.44, RGB(255, 235, 160) }, { 28, 1.05, 0.4, G }, { 4, 0.8, 0.34, OR } }, 0.3, 0.3, 0.12)
		end
		-- 사자 꼬리 + 주황 털 끝
		local tp = surf(c.B, c.BS, V(0, -0.3, 1))
		local t1 = tp + V(0, 0.4, 0.45)
		seg(b, "Tail", tp + V(0, 0, -0.05), t1, 0.2, G)
		ell(b, "TailTuft", V(0.4, 0.46, 0.4), CFrame.new(t1 + V(0, 0.18, 0.06)), OR)
		local body = b.model:FindFirstChild("Body")
		if body then
			glow(body, RGB(255, 210, 130), 0.4, 5)
		end
	end

	-- 구미호 (이터널): 하얀 여우, 연보라 귀 안쪽, 이마에 은은한 분홍 불꽃 무늬, 금방울 빨간 목끈,
	-- 등 뒤로 부채처럼 펼친 복슬 꼬리 9개 (끝은 분홍 → 보라 → 하늘 파스텔)
	PET_BUILDERS.NineTailFox = function(b)
		local W = RGB(255, 252, 250)
		local Cr = RGB(255, 238, 245)
		local IN = RGB(215, 185, 255)
		local c = chibi(b, { body = W, belly = Cr, feet = RGB(240, 228, 245), noArms = true, eyeY = 0.06, noMouth = true, blushX = 0.7, blushY = -0.2 })
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.22, -0.36)
			ell(b, "Cheek", V(0.6, 0.45, 0.35), facing(p - n * 0.08, n), Cr)
		end
		smallNose(c, -0.22, V(0.18, 0.12, 0.1), RGB(70, 50, 70), 0.05)
		local mp, mn = front(c.H, c.HS, 0, -0.4)
		ell(b, "Mouth", V(0.12, 0.06, 0.04), facing(mp + mn * 0.05, mn), MOUTH)
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx * 0.55, 0.85, 0))
			local frame = CFrame.new(p - n * 0.14) * CFrame.Angles(0, 0, -sx * 0.28)
			tri(b, "Ear", frame, 0.62, 0.78, 0.15, W)
			ell(b, "EarInner", V(0.28, 0.44, 0.04), frame * CFrame.new(0, 0.32, -0.085), IN)
		end
		-- 이마 불꽃 무늬 (작은 네온 하나)
		local fp, fn = front(c.H, c.HS, 0, 0.5)
		ell(b, "Mark", V(0.14, 0.3, 0.05), facing(fp + fn * 0.01, fn), RGB(255, 120, 175), NEON)
		-- 빨간 목끈 + 금방울
		local ny = c.B.Y + c.BS.Y - 0.2
		addPart(b, "Collar", "Cyl", V(0.16, 1.6, 1.6), CFrame.new(0, ny, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(230, 70, 90))
		local bell = ell(b, "Bell", V(0.26, 0.26, 0.26), CFrame.new(0, ny - 0.17, -0.84), RGB(255, 210, 90), METAL)
		bell.Reflectance = 0.15
		-- 꼬리 9개: 엉덩이에서 뒤/위로 부채꼴
		local root = V(0, 1.2, 0.64)
		local tipCols = {
			RGB(255, 190, 215), RGB(250, 190, 235), RGB(235, 190, 250), RGB(215, 195, 255), RGB(200, 205, 255),
			RGB(215, 195, 255), RGB(235, 190, 250), RGB(250, 190, 235), RGB(255, 190, 215),
		}
		for i = 1, 9 do
			local a = math.rad(-66 + (i - 1) * 16.5)
			local d = V(math.sin(a) * 1.1, math.cos(a), 0.35).Unit
			local len = 1.7 - math.abs(i - 5) * 0.05
			local tc = root + d * (len * 0.5 + 0.1)
			ell(b, "Tail", V(0.54, 0.54, len), CFrame.lookAt(tc, tc + d), W)
			ell(b, "TailTip", V(0.46, 0.46, 0.5), CFrame.lookAt(tc + d * (len * 0.48), tc + d * 2), tipCols[i])
		end
		local body = b.model:FindFirstChild("Body")
		if body then
			glow(body, RGB(220, 195, 255), 0.45, 6)
		end
	end

	----------------------------------------------------------------------
	-- 8. 우주
	----------------------------------------------------------------------

	-- 운석 햄스터 (시크릿): 유리 우주 헬멧을 쓴 햄스터가 작은 운석을 타고 둥실 (투명 Hover 파트로 바닥 = y 0)
	-- 운석: 울퉁불퉁 바위 + 분화구 3개 + 뒤로 꼬리 불꽃 (가운데만 네온)
	PET_BUILDERS.MeteorHamster = function(b)
		local O = RGB(240, 178, 105)
		local Cr = RGB(255, 240, 215)
		local ROCK = RGB(125, 105, 100)
		local c0 = chibi(b, {
			body = O,
			belly = Cr,
			BS = V(0.74, 0.62, 0.68),
			HS = V(1.0, 0.84, 0.86),
			feet = RGB(255, 200, 185),
			eyeX = 0.38,
			eyeY = 0.04,
			eyeSize = V(0.36, 0.48, 0.16),
			blushX = 0.55,
			blushY = -0.3,
			blushLift = 0.1,
			mouthY = -0.32,
		})
		dropParts(b, "Foot")
		local c = liftCtx(b, c0, 1, 0.72)
		for _, p in b.parts do
			if p.Name == "Blush" then
				p.Transparency = 0 -- 유리 헬멧 뒤에서도 보이게
			end
		end
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.52, -0.34)
			ell(b, "Cheek", V(0.48, 0.38, 0.4), facing(p - n * 0.1, n), Cr)
		end
		smallNose(c, -0.16, V(0.13, 0.09, 0.08), RGB(255, 140, 160), 0.02)
		roundEars(c, 0.6, 0.8, 0.4, darker(O, 0.08), RGB(255, 175, 190))
		-- 운석 가장자리에 걸터앉은 발
		for _, sx in SIDES do
			ell(b, "Foot", V(0.42, 0.34, 0.5), CFrame.new(sx * 0.36, 1.02, -0.72), RGB(255, 200, 185))
		end
		-- 유리 헬멧 + 금속 목 고리
		local HC = c.H + V(0, 0.1, -0.02)
		local HSz = V(1.18, 1.02, 1.08)
		ell(b, "Helmet", HSz * 2, CFrame.new(HC), RGB(205, 230, 255), GLASS, 0.55)
		local gp, gn = surf(HC, HSz, V(-0.6, 0.55, -0.6))
		ell(b, "Gloss", V(0.24, 0.62, 0.05), facing(gp + gn * 0.01, gn) * CFrame.Angles(0, 0, -0.5), WHITE, nil, 0.35)
		addPart(b, "Collar", "Cyl", V(0.2, 1.72, 1.72), CFrame.new(c.B + V(0, c.BS.Y - 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2), RGB(205, 212, 228), METAL)
		accAnchor(b, "Head", CFrame.new(HC + V(0, HSz.Y - 0.09, 0))) -- 둥근 헬멧이라 살짝 내려 앉혀요
		accAnchor(b, "Face", CFrame.new((front(HC, HSz, 0, c.H.Y + 0.04 - HC.Y))))
		-- 운석 (바닥에서 0.28 떠 있어요)
		local MC = V(0, 0.7, 0.12)
		local MS = V(1.0, 0.42, 0.9)
		ell(b, "Meteor", MS * 2, CFrame.new(MC), ROCK)
		ell(b, "Meteor", V(0.9, 0.6, 0.8), CFrame.new(MC + V(-0.62, -0.05, 0.25)), darker(ROCK, 0.06))
		for _, d in { V(0.55, 0.2, -0.8), V(-0.4, -0.1, -0.9), V(0.85, 0.1, 0.4) } do
			local p, n = surf(MC, MS, d)
			ell(b, "Crater", V(0.26, 0.22, 0.06), facing(p, n), darker(ROCK, 0.3))
		end
		-- 뒤로 꼬리 불꽃 (주황 → 노랑, 가운데만 네온)
		local f0 = MC + V(0.15, 0.05, 0.85)
		seg(b, "Flame", f0, f0 + V(0.25, 0.3, 0.75), 0.5, RGB(255, 140, 60))
		seg(b, "Flame", f0 + V(-0.28, 0.12, -0.05), f0 + V(-0.2, 0.42, 0.62), 0.26, RGB(255, 205, 90), NEON)
		addPart(b, "Hover", "Block", V(0.3, 0.1, 0.3), CFrame.new(0, 0.05, 0), BLACK, nil, 1)
	end

	-- 은하 유니콘 (천상): 짙은 파랑 유니콘, 별 점, 은은하게 빛나는 뿔, 은하색 갈기/꼬리, 은빛 발굽
	PET_BUILDERS.GalaxyUnicorn = function(b)
		local NV = RGB(65, 80, 180)
		local PUR = RGB(155, 95, 235)
		local PINK = RGB(255, 130, 205)
		local CY = RGB(100, 205, 255)
		local VI = RGB(110, 75, 205)
		local c = chibi(b, { body = NV, belly = RGB(95, 110, 205), feet = RGB(205, 210, 235), eyeY = 0, blushY = -0.3 })
		for _, p in b.parts do
			if p.Name == "Foot" then
				p.Reflectance = 0.2
			end
		end
		lashes(b, c.eyes, 0.36, 0.5)
		pointyEars(c, 0.6, 0.8, 0.36, 0.46, 0.12, 0.35, NV)
		-- 빛나는 뿔 + 금/분홍 띠
		local hp = surf(c.H, c.HS, V(0, 1, -0.4))
		local hd = V(0, 1, -0.35).Unit
		local hc = hp + hd * 0.34
		local horn = ell(b, "Horn", V(0.28, 0.84, 0.28), alongY(hc, hd), RGB(215, 240, 255), NEON)
		for i, h in { -0.14, 0.1 } do
			local r = 0.14 * math.sqrt(1 - (h / 0.42) ^ 2)
			local D = 2 * r + 0.05
			addPart(b, "HornRing", "Cyl", V(0.05, D, D), alongX(hc + hd * h, hd), if i == 1 then RGB(255, 215, 110) else PINK)
		end
		glow(horn, RGB(170, 220, 255), 0.4, 5)
		-- 은하색 갈기 + 꼬리
		local mane = { { V(0.3, 1, -0.25), 0.5, PUR }, { V(-0.1, 0.9, 0.45), 0.58, PINK }, { V(0.15, 0.4, 0.95), 0.6, CY }, { V(-0.1, -0.2, 0.95), 0.52, VI }, { V(0.35, 0.75, 0.6), 0.42, CY } }
		for _, m in mane do
			local mp, mn = surf(c.H, c.HS, m[1])
			ell(b, "Mane", V(m[2], m[2], m[2]), CFrame.new(mp + mn * 0.05), m[3])
		end
		local tp = surf(c.B, c.BS, V(0, 0, 1))
		ell(b, "Tail", V(0.46, 0.46, 0.46), CFrame.new(tp + V(0, 0, 0.12)), PUR)
		ell(b, "Tail", V(0.4, 0.4, 0.4), CFrame.new(tp + V(0, -0.2, 0.42)), PINK)
		ell(b, "Tail", V(0.34, 0.34, 0.34), CFrame.new(tp + V(0, -0.42, 0.56)), CY)
		-- 별 점 (네온은 둘만)
		local stars = {
			{ c.H, c.HS, V(0.75, 0.45, -0.45), true },
			{ c.H, c.HS, V(-0.7, 0.55, -0.35), false },
			{ c.H, c.HS, V(-0.85, -0.1, 0.4), false },
			{ c.B, c.BS, V(0.85, 0.25, -0.35), false },
			{ c.B, c.BS, V(-0.8, 0.35, 0.4), true },
			{ c.B, c.BS, V(0.6, 0.2, 0.75), false },
		}
		for i, s in stars do
			local p, n = surf(s[1], s[2], s[3])
			local d = if s[4] then 0.17 else 0.14
			ell(b, "Star", V(d, d, 0.05), facing(p + n * 0.01, n), if i % 2 == 0 then RGB(255, 240, 170) else WHITE, if s[4] then NEON else nil)
		end
	end

	-- 은하 용 (이터널): 짙은 남색 아기 용, 밝은 얼굴/배, 금 뿔, 보라 날개, 별 점, 꼬리 끝 별,
	-- 가슴에 작은 은하 보석, 머리 옆을 도는 고리 달린 꼬마 행성
	PET_BUILDERS.CosmoDragon = function(b)
		local NV = RGB(40, 48, 120)
		local FACE = RGB(120, 135, 225)
		local BELLY = RGB(150, 165, 240)
		local WING = RGB(125, 85, 215)
		local GOLD = RGB(255, 210, 110)
		local c = chibi(b, {
			body = NV,
			belly = BELLY,
			feet = darker(NV, 0.15),
			eyeY = 0.04,
			face = { color = FACE, semi = V(0.86, 0.7, 0.62), offset = V(0, -0.14, -0.4) },
			eyeX = 0.36,
			blushX = 0.62,
			blushY = -0.22,
			mouthY = -0.36,
		})
		for _, sx in SIDES do
			local d = V(sx * 0.35, 1, 0.45)
			local p = surf(c.H, c.HS, V(sx * 0.45, 1, 0.1))
			ell(b, "Horn", V(0.22, 0.58, 0.22), alongY(p + d.Unit * 0.18, d), GOLD)
			local np, nn = front(c.FC, c.FS, sx * 0.12, -0.14)
			ell(b, "Nostril", V(0.07, 0.05, 0.04), facing(np, nn), darker(FACE, 0.35))
		end
		-- 보라 날개
		for _, sx in SIDES do
			local base = c.B + V(sx * 0.3, 0.4, 0.5)
			tri(b, "Wing", frameUp(base, V(sx, 0.8, 0.5), Vector3.zAxis), 0.85, 1.25, 0.08, WING)
		end
		-- 등 가시
		for _, s in { { c.H, c.HS, V(0, 0.55, 1) }, { c.H, c.HS, V(0, 0, 1) }, { c.B, c.BS, V(0, 0.6, 1) } } do
			local sp, sn = surf(s[1], s[2], s[3])
			ell(b, "Spike", V(0.14, 0.32, 0.26), alongY(sp + sn * 0.08, sn), RGB(110, 200, 255))
		end
		-- 꼬리 + 별 끝
		local tp = surf(c.B, c.BS, V(0, -0.4, 1))
		local d1 = V(0, 0.15, 1).Unit
		local t1 = tp + d1 * 0.35
		ell(b, "Tail", V(0.5, 0.5, 0.9), CFrame.lookAt(t1, t1 + d1), NV)
		local d2 = V(0, 0.6, 1).Unit
		local t2 = t1 + d1 * 0.4 + d2 * 0.3
		ell(b, "Tail", V(0.3, 0.3, 0.65), CFrame.lookAt(t2, t2 + d2), NV)
		local t3 = t2 + d2 * 0.3
		local scf = CFrame.lookAt(t3, t3 + V(0.5, 0, 1))
		for _, a in { 0, math.pi / 2 } do
			ell(b, "TailStar", V(0.12, 0.42, 0.1), scf * CFrame.Angles(0, 0, a), RGB(255, 235, 140), if a == 0 then NEON else nil)
		end
		-- 별 점 (머리/몸/날개, 네온은 둘만)
		local stars = {
			{ c.H, c.HS, V(0.7, 0.55, -0.4), true },
			{ c.H, c.HS, V(-0.75, 0.5, -0.3), false },
			{ c.B, c.BS, V(0.85, 0.3, -0.3), false },
			{ c.B, c.BS, V(-0.85, 0.2, -0.35), true },
			{ c.H, c.HS, V(0.3, 0.95, 0.2), false },
		}
		for i, s in stars do
			local p, n = surf(s[1], s[2], s[3])
			local d = if s[4] then 0.15 else 0.11
			ell(b, "Star", V(d, d, 0.05), facing(p + n * 0.01, n), if i % 2 == 0 then RGB(255, 240, 170) else WHITE, if s[4] then NEON else nil)
		end
		-- 가슴 은하 보석
		local gp, gn = front(c.BeC, c.BeS, 0, 0.35)
		ell(b, "Gem", V(0.24, 0.3, 0.1), facing(gp + gn * 0.02, gn), RGB(150, 230, 255), NEON)
		-- 고리 달린 꼬마 행성 (머리 오른쪽 위를 둥실)
		local pc = c.H + V(1.32, 0.72, 0.15)
		ell(b, "Planet", V(0.5, 0.5, 0.5), CFrame.new(pc), RGB(255, 175, 120))
		addPart(b, "PlanetRing", "Cyl", V(0.04, 0.95, 0.95), CFrame.new(pc) * CFrame.Angles(0.35, 0, math.pi / 2 - 0.4), RGB(255, 225, 160))
		local body = b.model:FindFirstChild("Body")
		if body then
			glow(body, RGB(160, 140, 255), 0.45, 6)
		end
	end
end
