-- v4 무늬 알 (PetModels/init.luau 가 불러서 등록)
-- 손으로 만든 알 빌더(EGG_BUILDERS)가 없는 알은 Config.Eggs[id].Look 표 하나로 만들어요.
-- init.luau 의 BuildEgg / HasEgg 가 여기서 등록한 Kit.eggFromLook(b, look) 을 불러요.
--
-- Look 읽는 법
--   Base    (Color3)  알 껍데기 색
--   Accent  (Color3)  무늬 주인공 색 (없으면 Base 를 30% 어둡게)
--   Accent2 (Color3?) 둘째 색. 없으면 무늬마다 기본값 (A2_DEFAULT): 보통 Accent 와 하양 반반,
--                     Gems = 금색 띠, Crown = 루비색 보석, Flames = 노랑, Leaves = 진한 덩굴색, Bubbles/Snow/Candy = 하양
--   Pattern (string)  PATTERN_ORDER 의 16 가지 중 하나 (모르는 이름이면 경고 + Spots)
--   Shine   (bool?)   반짝 코팅: 껍데기 Reflectance 0.18 + 왼쪽 위 하얀 광택 줄/점 (파트 2)
--   Glow    (bool?)   네온 띠 1줄 + 껍데기에 은은한 PointLight("Glow") + 별/보석/불꽃 같은 조각이 네온
-- 크기/중심/피벗은 다른 알과 같아요 (가로 2, 세로 2.6, 중심 Kit.EGG_C, 피벗 = 바닥 가운데). 파트는 30개 이하.
-- 무늬 조각은 껍데기 곡면에 맞춰 붙여요: 그 자리 곡률로 납작 타원체의 너비/두께/깊이를 계산해서
-- 가장자리는 껍데기 속으로 살짝 들어가고, 겉에서 보이는 테두리는 주문한 크기 그대로 (뜨지도 묻히지도 않음).
return function(Kit, _PET_BUILDERS, _EGG_BUILDERS)
	local V, RGB, ell, addPart, surf, tri, frameUp = Kit.V, Kit.RGB, Kit.ell, Kit.addPart, Kit.surf, Kit.tri, Kit.frameUp
	local WHITE, BLACK, RAINBOW = Kit.WHITE, Kit.BLACK, Kit.RAINBOW
	local EGG_S, EGG_C, eggBase = Kit.EGG_S, Kit.EGG_C, Kit.eggBase
	local NEON, GLASS, METAL = Enum.Material.Neon, Enum.Material.Glass, Enum.Material.Metal
	local AX, AY = EGG_S.X, EGG_S.Y -- 가로 반지름 1, 세로 반지름 1.3
	local TOP = EGG_C.Y + AY -- 알 꼭대기 (월드 y 2.6)
	local TAU = math.pi * 2
	local GOLDEN = 2.39996323 -- 황금각: 점을 알 전체에 고르게 뿌릴 때
	local POP = 0.035 -- 납작 무늬가 껍데기 밖으로 튀어나오는 높이
	local GOLD = RGB(255, 205, 70)
	local HERO = 0.28 -- 주인공 무늬 자리 (정면에서 +X 로 살짝 = 미리보기 카메라 쪽)

	----------------------------------------------------------------------
	-- 껍데기 기하 도우미
	----------------------------------------------------------------------

	-- 중심 기준 높이 y 에서 알 둘레 반지름
	local function radAt(y)
		return AX * math.sqrt(math.max(1 - (y / AY) ^ 2, 0))
	end

	-- 표면 점 p 의 바깥 법선
	local function normalAt(p)
		local q = p - EGG_C
		return V(q.X / (AX * AX), q.Y / (AY * AY), q.Z / (AX * AX)).Unit
	end

	-- 표면 점 p 에서 접선 방향 u 쪽 곡률 반지름 (작을수록 그쪽으로 둥글게 휘어요)
	local function bendR(p, u)
		local q = p - EGG_C
		local g = V(q.X / (AX * AX), q.Y / (AY * AY), q.Z / (AX * AX)).Magnitude
		local k = (u.X * u.X + u.Z * u.Z) / (AX * AX) + u.Y * u.Y / (AY * AY)
		return g / k
	end

	local function rot(a)
		return CFrame.Angles(0, 0, a)
	end

	-- 표면 틀: az = 0 이 정면(-Z), +X 쪽으로 돌아요. y = 중심 기준 높이.
	-- 틀의 -Z(LookVector) = 바깥 법선, Y ≈ 위 (자오선 방향), X = 옆
	local function at(az, y)
		local r = radAt(y)
		local p = EGG_C + V(math.sin(az) * r, y, -math.cos(az) * r)
		local n = normalAt(p)
		return CFrame.lookAt(p, p + n, if math.abs(n.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis)
	end

	-- 틀 cf 의 접평면에서 (ox, oy) 옮긴 곳을 다시 껍데기에 붙인 틀 (방향은 cf 를 따라가요)
	local function slide(cf, ox, oy)
		local w = cf * V(ox, oy, 0)
		local p, n = surf(EGG_C, EGG_S, w - EGG_C)
		return CFrame.lookAt(p, p + n, cf.UpVector)
	end

	-- 곡면에 착 붙는 납작 타원체 무늬. cf = 표면 틀 (-Z = 바깥), w × h = 겉에서 보이는 크기,
	-- pop = 가운데가 튀어나오는 높이. 접선 X/Y 방향 곡률로 타원체 반지름과 깊이를 따로 맞춰서
	-- 보이는 테두리가 w × h 가 되고 타원체 가장자리는 껍데기 속에 들어가요.
	local function stick(b, name, cf, w, h, color, mat, tr, pop)
		local pp = pop or POP
		local p = cf.Position
		local rx, ry = bendR(p, cf.RightVector), bendR(p, cf.UpVector)
		local sx, sy = w * 0.5, h * 0.5
		local gx, gy = sx * sx / (2 * rx), sy * sy / (2 * ry) -- 보일 테두리 자리의 처짐
		local g = math.max(gx, gy)
		local e = 0.008 + 0.15 * g
		local d, t, SX, SY = g + e, g + e + pp, sx, sy
		for _ = 1, 16 do
			d = g + e
			t = d + pp
			SX = sx / math.sqrt(math.max(1 - ((d - gx) / t) ^ 2, 0.1))
			SY = sy / math.sqrt(math.max(1 - ((d - gy) / t) ^ 2, 0.1))
			if d >= SX * SX / (2 * rx) and d >= SY * SY / (2 * ry) then
				break
			end
			e *= 1.5
		end
		return ell(b, name, V(SX * 2, SY * 2, t * 2), cf * CFrame.new(0, 0, d), color, mat, tr)
	end

	-- 곡면에 붙는 얇은 네모 판 (하트 아래 뾰족이, 작은 다이아 보석). 모서리도 껍데기에 닿아요.
	local function plate(b, name, cf, w, h, color, mat, pop)
		local pp = pop or POP
		local rr = math.min(bendR(cf.Position, cf.RightVector), bendR(cf.Position, cf.UpVector))
		local c = math.sqrt(w * w + h * h) * 0.5
		local hz = (pp + c * c / (2 * rr)) * 0.5 + 0.012
		return addPart(b, name, "Block", V(w, h, hz * 2), cf * CFrame.new(0, 0, hz - pp), color, mat)
	end

	-- 껍데기 위 두 점을 잇는 길쭉한 조각 (선/덩굴/소용돌이). extra = 이음매가 안 끊기게 더 늘이는 길이
	local function seg(b, name, p0, p1, w, color, mat, extra, pop)
		local p, n = surf(EGG_C, EGG_S, (p0 + p1) * 0.5 - EGG_C)
		local cf = CFrame.lookAt(p, p + n, p1 - p0)
		return stick(b, name, cf, w, (p1 - p0).Magnitude + (extra or 0), color, mat, nil, pop)
	end

	-- 가로 띠 (원기둥 고리). 넓은 쪽 가장자리에서 0.03 튀어나와요.
	-- steps 로 나누면 얇은 고리 여러 개가 계단처럼 껍데기 곡면을 따라가서, 위/아래쪽 띠의 턱이 작아져요
	local function band(b, name, y, t, color, mat, steps)
		local n = steps or 1
		local tt = t / n
		local first
		for i = 1, n do
			local yy = y - t / 2 + tt * (i - 0.5)
			local r = radAt(math.max(math.abs(yy) - tt / 2, 0)) + 0.03
			local part = addPart(b, name, "Cyl", V(tt, 2 * r, 2 * r), CFrame.new(EGG_C + V(0, yy, 0)) * rot(math.pi / 2), color, mat)
			first = first or part
		end
		return first
	end

	-- 비스듬한 띠 (캔디 줄무늬): init.luau 의 Kit.eggTiltBand (단면 타원 가운데에 맞춘 고리)
	local tiltBand = Kit.eggTiltBand

	-- 아래쪽이 다른 색으로 물든 알: 껍데기보다 살짝 홀쭉한 타원체가 월드 높이 H 아래에서만 껍데기 밖으로 나와요.
	-- 바닥은 껍데기 바닥(y = 0)과 맞닿아서 피벗이 그대로예요. H 는 0.4 ~ 1.3.
	local function dip(b, name, H, color, mat)
		local m = 0.5 + 0.5 * H -- 낮게 물들수록 홀쭉하게 (밖으로 0.03 ~ 0.05 나와요)
		local shell = AX * AX * (2 * AY * H - H * H) / (AY * AY) -- 껍데기의 x² (높이 H)
		local q = math.sqrt(shell * m * m / (2 * m * H - H * H))
		return ell(b, name, V(2 * q, 2 * m, 2 * q), CFrame.new(EGG_C.X, m + 0.003, EGG_C.Z), color, mat)
	end

	-- 알 전체에 고르게 n 자리 (황금각 나선): { {az, y}, ... } 위에서 아래로
	local function spread(n, lo, hi, az0)
		local out = {}
		for i = 0, n - 1 do
			table.insert(out, { az0 + i * GOLDEN, hi - (hi - lo) * (i + 0.5) / n })
		end
		return out
	end

	local function lum(c)
		return 0.3 * c.R + 0.59 * c.G + 0.11 * c.B
	end

	----------------------------------------------------------------------
	-- 작은 모양들
	----------------------------------------------------------------------

	-- 통통한 별: 팔 5개 (+ 가운데). r = 가운데에서 끝까지
	local function star(b, cf, r, color, mat, core)
		for i = 0, 4 do
			local a = i * TAU / 5
			stick(b, "Star", slide(cf, -math.sin(a) * r * 0.42, math.cos(a) * r * 0.42) * rot(a), r * 0.54, r * 1.16, color, mat)
		end
		if core then
			stick(b, "Star", cf, r * 0.8, r * 0.8, color, mat, nil, POP + 0.008)
		end
	end

	-- 하트: 동그라미 2개 + 45도 돌린 네모 (아래 뾰족). s = 가로 너비
	local function heart(b, cf, s, color, mat)
		local a = s / 1.707
		local dy = -0.073 * a
		local lob = a * 0.3536
		plate(b, "Heart", slide(cf, 0, dy) * rot(math.pi / 4), a, a, color, mat, POP - 0.004)
		for _, sx in { -1, 1 } do
			stick(b, "Heart", slide(cf, sx * lob, lob + dy), a, a, color, mat, nil, POP + 0.004)
		end
	end

	-- 반짝 별 (✦ 가는 십자 2개)
	local function twinkle(b, cf, s, color, mat)
		stick(b, "Twinkle", cf, s * 0.22, s, color, mat)
		stick(b, "Twinkle", cf * rot(math.pi / 2), s * 0.22, s * 0.78, color, mat, nil, POP + 0.006)
	end

	-- 눈 결정: 막대 3개가 60도씩 (+ 가운데 점)
	local function flake(b, cf, len, color, mat, core)
		for i = 0, 2 do
			stick(b, "Flake", cf * rot(i * math.pi / 3), 0.075, len, color, mat, nil, POP + i * 0.004)
		end
		if core then
			stick(b, "Flake", cf, 0.14, 0.14, color, mat, nil, POP + 0.02)
		end
	end

	-- 접평면 소용돌이 (아르키메데스 나선) n 조각. R = 바깥 반지름, 안쪽은 촘촘하게 나눠요
	local function swirl(b, cf, R, turns, n, w0, w1, color, mat)
		local th1 = turns * TAU
		local N = 240
		local qs, acc = {}, {}
		local total = 0
		for i = 0, N do
			local th = th1 * i / N
			local r = R * (0.18 + 0.82 * th / th1)
			qs[i] = { r * math.cos(th), r * math.sin(th) }
			if i > 0 then
				total += math.sqrt(r) * th1 / N
			end
			acc[i] = total
		end
		local pts = {}
		local j = 0
		for s = 0, n do
			local goal = total * s / n
			while j < N and acc[j] < goal do
				j += 1
			end
			pts[s] = slide(cf, qs[j][1], qs[j][2]).Position
		end
		for s = 1, n do
			seg(b, "Swirl", pts[s - 1], pts[s], w0 + (w1 - w0) * s / n, color, mat, 0.07, POP + (s % 2) * 0.004)
		end
	end

	----------------------------------------------------------------------
	-- 무늬 16 가지. k = { b, base, a1, a2, glow, neon(Glow 면 Neon 재질, 아니면 nil) }
	----------------------------------------------------------------------

	local P = {}

	-- 민무늬: 아래 1/3 이 Accent 로 물들고, 경계에 Accent2 리본 + 정면 리본 매듭
	P.Plain = function(k)
		local b = k.b
		local H = 0.95
		local y = H - AY
		dip(b, "Dip", H, k.a1)
		band(b, "Ribbon", y, 0.1, k.a2)
		local cf = at(HERO, y)
		for _, sx in { -1, 1 } do
			stick(b, "Bow", slide(cf, sx * 0.17, 0.03) * rot(sx * 0.32), 0.34, 0.21, k.a2, nil, nil, 0.08)
		end
		stick(b, "Bow", cf, 0.14, 0.14, k.a2:Lerp(BLACK, 0.12), nil, nil, 0.1)
	end

	-- 점박이: 크고 작은 동그란 점 15개 (셋에 하나는 Accent2)
	P.Spots = function(k)
		local sizes = { 0.56, 0.36, 0.48, 0.3, 0.52, 0.4 }
		for i, s in spread(15, -0.92, 1.02, HERO + 0.35) do
			local d = sizes[(i - 1) % #sizes + 1]
			stick(k.b, "Spot", at(s[1], s[2]) * rot(i * 0.7), d, d * 0.9, if i % 3 == 0 then k.a2 else k.a1)
		end
	end

	-- 줄무늬: 가로 띠 4줄 (Accent / Accent2 번갈아). 띠마다 얇은 고리 3개로 곡면을 따라가요
	P.Stripes = function(k)
		for i, y in { 0.62, 0.21, -0.2, -0.61 } do
			band(k.b, "Stripe", y, 0.2, if i % 2 == 1 then k.a1 else k.a2, nil, 3)
		end
	end

	-- 지그재그: 허리에 뾰족뾰족 띠 (12 조각) + 위아래 가는 Accent2 줄
	P.Zigzag = function(k)
		local n, y0, amp = 12, -0.02, 0.2
		local pts = {}
		for j = 0, n do
			pts[j] = at(HERO + j * TAU / n, y0 + (if j % 2 == 0 then amp else -amp)).Position
		end
		for j = 1, n do
			seg(k.b, "Zig", pts[j - 1], pts[j], 0.17, k.a1, nil, 0.16, POP + (j % 2) * 0.005)
		end
		band(k.b, "ZigLine", 0.45, 0.07, k.a2, k.neon)
		band(k.b, "ZigLine", -0.49, 0.07, k.a2, k.neon)
	end

	-- 별: 정면 큰 별 + 둘레 별 3개 + 반짝 별 2개 (Glow 면 네온)
	P.Stars = function(k)
		local b = k.b
		star(b, at(HERO, 0.02), 0.38, k.a1, k.neon, true)
		star(b, at(HERO + 0.7, 0.6) * rot(0.3), 0.22, k.a2, k.neon)
		star(b, at(HERO - 0.68, 0.55) * rot(-0.25), 0.22, k.a2, k.neon)
		star(b, at(HERO + 3.1, 0.05) * rot(0.2), 0.32, k.a1, k.neon)
		twinkle(b, at(HERO + 0.68, -0.55), 0.26, k.a2, k.neon)
		twinkle(b, at(HERO - 0.62, -0.5), 0.22, k.a1, k.neon)
	end

	-- 하트: 정면 큰 하트 + 둘레 하트 6개 (Accent / Accent2)
	P.Hearts = function(k)
		local list = {
			{ 0, 0.02, 0.64, -0.12, k.a1 },
			{ 0.7, 0.6, 0.36, 0.3, k.a2 },
			{ -0.68, 0.55, 0.36, -0.3, k.a2 },
			{ 0.66, -0.58, 0.32, -0.25, k.a2 },
			{ -0.62, -0.55, 0.3, 0.25, k.a1 },
			{ 3.1, 0.15, 0.54, 0.15, k.a1 },
			{ 2.15, -0.35, 0.34, -0.2, k.a2 },
		}
		for _, h in list do
			heart(k.b, at(HERO + h[1], h[2]) * rot(h[4]), h[3], h[5])
		end
	end

	-- 땡땡이: 작은 점 24개
	P.Dots = function(k)
		for i, s in spread(24, -0.95, 1.05, HERO) do
			local d = if i % 2 == 0 then 0.15 else 0.2
			stick(k.b, "Dot", at(s[1], s[2]), d, d, if i % 3 == 0 then k.a2 else k.a1)
		end
	end

	-- 소용돌이: 정면 큰 소용돌이 (Accent) + 뒤쪽 작은 소용돌이 (Accent2)
	P.Swirl = function(k)
		swirl(k.b, at(HERO, 0.05), 0.56, 1.9, 14, 0.08, 0.15, k.a1)
		swirl(k.b, at(HERO + math.pi, 0.15) * rot(1.2), 0.42, 1.6, 9, 0.08, 0.13, k.a2)
	end

	-- 보석: 허리 금속 띠(Accent2) 에 큰 보석 5개 (유리, Glow 면 네온) + 위아래 작은 다이아 8개
	P.Gems = function(k)
		local b = k.b
		local y, t = -0.05, 0.2
		local ring = band(b, "GemBand", y, t, k.a2, METAL)
		ring.Reflectance = 0.25
		local R = radAt(math.max(math.abs(y) - t / 2, 0)) + 0.03
		local mat = if k.glow then NEON else GLASS
		for i = 0, 4 do
			local az = i * TAU / 5 -- 첫 보석은 정면 (옆구리 ±X 에 안 걸려서 너비가 안 늘어요)
			local dir = V(math.sin(az), 0, -math.cos(az))
			local p = EGG_C + V(0, y, 0) + dir * R
			local cf = CFrame.lookAt(p, p + dir)
			ell(b, "Gem", V(0.3, 0.34, 0.17), cf, if i % 2 == 0 then k.a1 else k.a1:Lerp(WHITE, 0.35), mat, 0.05)
			ell(b, "Glint", V(0.08, 0.1, 0.05), cf * CFrame.new(0.055, 0.075, -0.07), WHITE, NEON)
		end
		for i = 0, 7 do
			local up = i % 2 == 0
			local az = HERO + (i + 0.5) * TAU / 8
			local col = if i % 4 < 2 then k.a1:Lerp(WHITE, 0.2) else k.a1:Lerp(BLACK, 0.15)
			plate(b, "Gem", at(az, if up then 0.5 else -0.55) * rot(math.pi / 4), 0.17, 0.17, col, mat, 0.05)
		end
	end

	-- 왕관: 꼭대기 금속 왕관 (Accent → 금색 왕관이면 Accent 를 금색으로) + 뾰족 5개 + 보석/껍데기 점 8개 (Accent2)
	P.Crown = function(k)
		local b = k.b
		local rc, hc = 0.47, 0.2
		local yb = AY * math.sqrt(1 - ((rc - 0.03) / AX) ^ 2) -- 띠 아랫면 (껍데기 속)
		local cy = EGG_C.Y + yb + hc / 2
		local base = addPart(b, "Crown", "Cyl", V(hc, rc * 2, rc * 2), CFrame.new(EGG_C.X, cy, EGG_C.Z) * rot(math.pi / 2), k.a1, METAL)
		base.Reflectance = 0.25
		for i = 0, 4 do
			local az = HERO + i * TAU / 5
			local dir = V(math.sin(az), 0, -math.cos(az))
			local foot = V(EGG_C.X, cy + hc / 2 - 0.03, EGG_C.Z) + dir * (rc - 0.04)
			local fr = frameUp(foot, (Vector3.yAxis + dir * 0.18).Unit, dir)
			tri(b, "Crown", fr, 0.3, 0.3, 0.07, k.a1, METAL)
			ell(b, "CrownJewel", V(0.11, 0.11, 0.11), fr * CFrame.new(0, 0.3, 0), k.a2, k.neon)
		end
		local dir = V(math.sin(HERO), 0, -math.cos(HERO))
		local jp = V(EGG_C.X, cy, EGG_C.Z) + dir * (rc + 0.005)
		ell(b, "CrownJewel", V(0.15, 0.15, 0.08), CFrame.lookAt(jp, jp + dir), k.a2, k.neon)
		for i, s in spread(8, -0.85, 0.7, HERO + 0.4) do
			local d = if i % 2 == 0 then 0.2 else 0.26
			stick(b, "Dot", at(s[1], s[2]), d, d, if i % 2 == 0 then k.a2:Lerp(WHITE, 0.3) else k.a2)
		end
	end

	-- 불꽃: 아래가 Accent 로 물들고, 거기서 올라오는 불꽃 혀 8개 (큰/작은 번갈아, 끝이 뾰족) + 안쪽 Accent2 불꽃 (Glow 면 네온)
	P.Flames = function(k)
		local b = k.b
		local H = 0.62
		local yb = H - AY
		dip(b, "Fire", H, k.a1)
		for i = 0, 7 do
			local tall = i % 2 == 0
			local len = if tall then 1.0 else 0.72
			local w = if tall then 0.44 else 0.36
			local sway = if i % 4 < 2 then 0.16 else -0.16
			-- 불꽃 혀 = 통통한 아래 + 뾰족한 끝 (살짝 휘어요) + 안쪽 노란 불꽃
			local cf = at(HERO + i * TAU / 8, yb + 0.85 * len * 0.3)
			stick(b, "Flame", cf, w, len * 0.62, k.a1)
			stick(b, "Flame", slide(cf, 0, len * 0.36) * rot(sway), w * 0.5, len * 0.55, k.a1, nil, nil, POP + 0.004)
			stick(b, "Flame", slide(cf, 0, len * 0.02) * rot(sway * 0.5), w * 0.46, len * 0.5, k.a2, k.neon, nil, POP + 0.012)
		end
	end

	-- 나뭇잎: 허리를 물결치며 도는 덩굴 (Accent2) + 잎 8장 (Accent) + 꼭대기 새싹
	P.Leaves = function(k)
		local b = k.b
		local function vy(az)
			return 0.02 + 0.2 * math.sin(3 * (az - HERO))
		end
		local n = 12
		local pts = {}
		for j = 0, n do
			local az = HERO + j * TAU / n
			pts[j] = at(az, vy(az)).Position
		end
		for j = 1, n do
			seg(b, "Vine", pts[j - 1], pts[j], 0.075, k.a2, nil, 0.06)
		end
		local light = k.a1:Lerp(WHITE, 0.25)
		for i = 0, 7 do
			local az = HERO + 0.2 + i * TAU / 8
			local a = if i % 2 == 0 then 0.75 else math.pi + 0.75
			local cf = at(az, vy(az))
			stick(b, "Leaf", slide(cf, -math.sin(a) * 0.22, math.cos(a) * 0.22) * rot(a), 0.24, 0.44, if i % 3 == 1 then light else k.a1, nil, nil, POP + 0.006)
		end
		addPart(b, "Stem", "Cyl", V(0.32, 0.1, 0.1), CFrame.new(EGG_C.X, TOP + 0.09, EGG_C.Z) * rot(math.pi / 2), k.a2)
		for _, sx in { -1, 1 } do
			ell(b, "Sprout", V(0.4, 0.11, 0.22), CFrame.new(EGG_C.X + sx * 0.17, TOP + 0.25, EGG_C.Z) * CFrame.Angles(0, 0, sx * 0.45), k.a1)
		end
	end

	-- 비눗방울: 반투명 방울 8개 (Accent 와 하양 반반) + 방울마다 반짝 점 (Accent2, 네온) + 작은 점 4개
	P.Bubbles = function(k)
		local b = k.b
		local list = {
			{ 0, -0.08, 0.42 },
			{ -0.85, 0.45, 0.3 },
			{ 0.7, 0.55, 0.26 },
			{ 0.5, -0.65, 0.3 },
			{ -0.6, -0.6, 0.22 },
			{ 2.3, 0.2, 0.38 },
			{ -2.8, -0.2, 0.34 },
			{ 3.0, 0.72, 0.24 },
		}
		for _, s in list do
			local cf = at(HERO + s[1], s[2])
			local d = s[3]
			local c = cf.Position + cf.LookVector * (d * 0.1) -- 40% 는 껍데기에 묻혀요
			local bub = ell(b, "Bubble", V(d, d, d), CFrame.new(c), k.a1:Lerp(WHITE, 0.5), nil, 0.3)
			bub.Reflectance = 0.25
			local g = (cf.LookVector + cf.UpVector * 0.65 + cf.RightVector * 0.45).Unit
			local gp = c + g * (d * 0.5 - 0.015)
			ell(b, "Glint", V(d * 0.26, d * 0.4, 0.05), CFrame.lookAt(gp, gp + g, cf.UpVector) * rot(-0.6), k.a2, NEON, 0.05)
		end
		local soft = k.a1:Lerp(WHITE, 0.4)
		for _, s in { { 1.2, 0.0 }, { -1.4, 0.0 }, { 0.35, 0.9 }, { -0.35, 0.95 } } do
			stick(b, "Dot", at(HERO + s[1], s[2]), 0.11, 0.11, soft)
		end
	end

	-- 눈송이: 아래 서리(Accent2) + 경계에 눈 뭉치 6개 + 눈 결정 4개 (Accent, Glow 면 네온) + 눈 점 4개
	P.Snow = function(k)
		local b = k.b
		local H = 0.55
		local yb = H - AY
		dip(b, "Frost", H, k.a2)
		for i = 0, 5 do
			stick(b, "Frost", at(HERO + i * TAU / 6, yb + 0.03) * rot(i * 0.4), 0.36, 0.3, k.a2)
		end
		flake(b, at(HERO, 0.18), 0.62, k.a1, k.neon, true)
		flake(b, at(HERO + 1.45, 0.48) * rot(0.2), 0.42, k.a1, k.neon)
		flake(b, at(HERO - 1.55, 0.4) * rot(-0.15), 0.42, k.a1, k.neon)
		flake(b, at(HERO + 3.0, 0.15) * rot(0.3), 0.5, k.a1, k.neon)
		for _, s in { { 0.85, -0.2 }, { -0.6, -0.15 }, { 0.5, 0.78 }, { -0.9, 0.85 } } do
			stick(b, "Snow", at(HERO + s[1], s[2]), 0.12, 0.12, k.a2)
		end
	end

	-- 캔디: 비스듬한 캔디 줄무늬 3줄 (Accent / Accent2 / Accent) + 무지개 스프링클 14개 (줄 사이 바탕에)
	P.Candy = function(k)
		local b = k.b
		local tilt = 0.28
		for i, y in { 0.42, 0, -0.42 } do
			tiltBand(b, "CandyStripe", y, tilt, 0.17, if i % 2 == 1 then k.a1 else k.a2)
		end
		local tn = math.tan(tilt)
		local rows = {
			{ 0.69, { 0.3, 2.4, 4.3 } },
			{ 0.21, { -0.35, 0.85, 2.0, 3.3, 4.6 } },
			{ -0.21, { 0.25, 1.45, 2.7, 3.9 } },
			{ -0.66, { -0.2, 2.2 } },
		}
		local i = 0
		for _, row in rows do
			for _, az in row[2] do
				i += 1
				local a = HERO + az
				local y = row[1]
				for _ = 1, 3 do -- 기운 줄 사이 높이: y = 줄 높이 + x·tan(tilt)
					y = row[1] + radAt(y) * math.sin(a) * tn
				end
				stick(b, "Sprinkle", at(a, y) * rot(i * 1.13), 0.075, 0.21, RAINBOW[(i - 1) % #RAINBOW + 1], k.neon)
			end
		end
	end

	-- 행성: 정면에 고리 달린 행성 (Accent, 고리 Accent2) + 달 + 뒤쪽 작은 행성 (Accent2) + 반짝 별 6개 + 별 점 4개
	-- 별 색: 바탕이 어두우면 연노랑, 밝으면 Accent (Glow 면 네온)
	P.Planets = function(k)
		local b = k.b
		local starCol = if lum(k.base) < 0.55 then RGB(255, 240, 170) else k.a1
		local function planet(cf, d, col, ringCol, stripeCol)
			local c = cf.Position + cf.LookVector * (d * 0.1) -- 40% 묻힘
			local pc = CFrame.lookAt(c, c + cf.LookVector, cf.UpVector)
			ell(b, "Planet", V(d, d, d), pc, col)
			ell(b, "Planet", V(d * 1.02, d * 0.2, d * 1.02), pc * rot(-0.35) * CFrame.new(0, d * 0.14, 0), stripeCol)
			if ringCol then
				-- 토성 고리: 비스듬히 누운 얇은 원판 (뒤쪽 반은 껍데기 속)
				ell(b, "PlanetRing", V(d * 1.62, 0.05, d * 1.62), pc * rot(-0.35) * CFrame.Angles(-0.62, 0, 0), ringCol)
			end
		end
		planet(at(HERO, 0.02), 0.52, k.a1, k.a2, k.a1:Lerp(BLACK, 0.18))
		planet(at(HERO + math.pi + 0.3, 0.25), 0.38, k.a2, nil, k.a2:Lerp(BLACK, 0.15))
		local mcf = at(HERO + 0.85, 0.6)
		ell(b, "Moon", V(0.2, 0.2, 0.2), CFrame.new(mcf.Position + mcf.LookVector * 0.03), k.a2)
		local tw = { { -0.75, 0.5, 0.36 }, { 0.75, -0.5, 0.3 }, { -0.55, -0.55, 0.26 }, { 1.65, 0.1, 0.3 }, { -1.7, 0.0, 0.3 }, { 2.4, -0.45, 0.28 } }
		for _, s in tw do
			twinkle(b, at(HERO + s[1], s[2]), s[3], starCol, k.neon)
		end
		for _, s in { { 0.3, 0.75 }, { -0.25, -0.85 }, { 1.2, 0.6 }, { -1.2, 0.75 } } do
			stick(b, "Star", at(HERO + s[1], s[2]), 0.09, 0.09, starCol, k.neon)
		end
	end

	local PATTERN_ORDER = {
		"Plain", "Spots", "Stripes", "Zigzag", "Stars", "Hearts", "Dots", "Swirl",
		"Gems", "Crown", "Flames", "Leaves", "Bubbles", "Snow", "Candy", "Planets",
	}

	-- Accent2 가 없을 때 무늬별 기본값
	local A2_DEFAULT = {
		Gems = function(_)
			return GOLD
		end,
		Crown = function(_)
			return RGB(255, 85, 130) -- 루비 보석
		end,
		Flames = function(_)
			return RGB(255, 228, 95)
		end,
		Leaves = function(a1)
			return a1:Lerp(BLACK, 0.35)
		end,
		Bubbles = function(_)
			return WHITE
		end,
		Snow = function(_)
			return WHITE
		end,
		Candy = function(_)
			return WHITE
		end,
	}

	-- Glow 네온 띠 높이 (중심 기준). 아래쪽을 무늬가 쓰는 알은 위쪽에
	local TRIM_Y = { Flames = 0.78, Snow = 0.85, Candy = -1.0 }

	local function color3(v, default)
		return if typeof(v) == "Color3" then v else default
	end

	-- Look 표로 알 하나 만들기 (b = init.luau 의 빌더). 몸통 이름은 Body (다른 알과 같음)
	local function eggFromLook(b, look)
		local lk = if type(look) == "table" then look else {}
		local name = lk.Pattern
		local fn = P[name]
		if not fn then
			warn("[PetModels] 모르는 알 무늬: " .. tostring(name) .. " → Spots")
			name = "Spots"
			fn = P.Spots
		end
		local base = color3(lk.Base, RGB(255, 246, 228))
		local a1 = color3(lk.Accent, base:Lerp(BLACK, 0.3))
		local a2def = A2_DEFAULT[name]
		local a2 = color3(lk.Accent2, if a2def then a2def(a1) else a1:Lerp(WHITE, 0.5))
		local glow = lk.Glow == true
		local body = eggBase(b, base)
		b.model:SetAttribute("EggPattern", name)
		fn({ b = b, base = base, a1 = a1, a2 = a2, glow = glow, neon = if glow then NEON else nil })
		if lk.Shine == true then
			body.Reflectance = 0.18
			stick(b, "Gloss", at(HERO + 0.3, 0.55) * rot(0.45), 0.2, 0.5, WHITE, NEON, 0.3, 0.06)
			stick(b, "Gloss", at(HERO + 0.45, 0.12), 0.12, 0.12, WHITE, NEON, 0.3, 0.06)
		end
		if glow then
			band(b, "GlowTrim", TRIM_Y[name] or -0.9, 0.07, a1:Lerp(WHITE, 0.35), NEON)
			local light = Instance.new("PointLight")
			light.Name = "Glow"
			light.Color = a1:Lerp(WHITE, 0.3)
			light.Brightness = 0.6
			light.Range = 6
			light.Shadows = false
			light.Parent = body
		end
	end

	Kit.eggFromLook = eggFromLook
	Kit.EGG_PATTERNS = PATTERN_ORDER
end
