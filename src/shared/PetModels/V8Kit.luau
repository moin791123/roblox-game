-- ★v8 새 섬 8곳 펫 모델이 같이 쓰는 도우미 (PetsV8a~d 가 불러요).
-- 함수가 아니라 표를 돌려주니까 init.luau 의 자동 등록에서는 건너뛰어요.
local V8Kit = {}

function V8Kit.make(Kit)
	local V, ell, surf, facing, addPart, tri, alongX, alongY, frameUp = Kit.V, Kit.ell, Kit.surf, Kit.facing, Kit.addPart, Kit.tri, Kit.alongX, Kit.alongY, Kit.frameUp
	local SIDES, EYE = Kit.SIDES, Kit.EYE
	local H = {}

	-- 은은한 불빛 (희귀 펫 몸통에만, 작고 약하게)
	function H.glow(part, color, brightness, range)
		if not part then
			return
		end
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Brightness = brightness
		light.Range = range
		light.Shadows = false
		light.Parent = part
	end

	function H.part(b, name)
		for _, p in b.parts do
			if p.Name == name then
				return p
			end
		end
		return nil
	end

	-- 곡면에 착 붙는 납작 무늬 (R = 그 자리 반지름)
	function H.stick(b, name, p, n, w, h, R, color, spin, mat)
		local a = math.max(w, h) * 0.5
		local t = math.clamp(a * a / R, 0.05, a)
		return ell(b, name, V(w, h, t * 2), facing(p - n * (t - 0.03), n) * CFrame.Angles(0, 0, spin or 0), color, mat)
	end

	function H.patch(b, name, C, S, dir, w, h, color, spin, mat)
		local p, n = surf(C, S, dir)
		return H.stick(b, name, p, n, w, h, (S.X + S.Y + S.Z) / 3, color, spin, mat)
	end

	-- 두 점을 잇는 길쭉한 타원체
	-- (세로로 곧은 다리도 되게 lookAt 대신 직접 축을 만들어요)
	function H.along(pos, dir)
		local z = dir.Unit
		local ref = if math.abs(z.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
		local x = ref:Cross(z).Unit
		return CFrame.fromMatrix(pos, x, z:Cross(x).Unit)
	end

	function H.link(b, name, p0, p1, w, color, mat)
		return ell(b, name, V(w, w, (p1 - p0).Magnitude + w * 0.5), H.along((p0 + p1) * 0.5, p1 - p0), color, mat)
	end

	-- 두 점을 잇는 원기둥
	function H.rod(b, name, p0, p1, w, color, mat)
		return addPart(b, name, "Cyl", V((p1 - p0).Magnitude, w, w), alongX((p0 + p1) * 0.5, p1 - p0), color, mat)
	end

	function H.lashes(b, eyes, k)
		local s = k or 1
		for i, cf in eyes do
			local sx = if i == 1 then -1 else 1
			addPart(b, "Lash", "Block", V(0.14 * s, 0.04, 0.04), cf * CFrame.new(sx * 0.19 * s, 0.2 * s, -0.03) * CFrame.Angles(0, 0, sx * 0.6), EYE)
		end
	end

	-- 졸린 눈 (감은 눈 곡선): 눈 대신 쓰려면 chibi 에 noEyes = true
	function H.sleepyEyes(b, c, x, y)
		for _, sx in SIDES do
			local p, n = Kit.front(c.FC, c.FS, sx * (x or 0.38), y or 0)
			addPart(b, "Eye", "Block", V(0.3, 0.06, 0.05), facing(p + n * 0.01, n) * CFrame.Angles(0, 0, sx * 0.12), EYE)
		end
	end

	-- 깃털/꽃잎 날개 (PetsRareA 와 같은 방식). f = { 각도(도), 길이, 폭, 색 }
	function H.featherWing(b, root, sx, feathers, sweep, lean, thick, name)
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

	-- 등 양쪽 깃털 날개 한 쌍
	function H.wings(b, c, feathers, opt)
		local o = opt or {}
		for _, sx in SIDES do
			local root = surf(c.B, c.BS, V(sx * (o.x or 0.55), o.y or 0.45, 0.78))
			local parts = H.featherWing(b, root, sx, feathers, o.sweep or 0.35, o.lean or 0.3, o.thick or 0.1, o.name)
			if o.transparency then
				for _, p in parts do
					p.Transparency = o.transparency
				end
			end
		end
	end

	-- 박쥐/용 날개 (삼각 2장씩)
	function H.batWings(b, c, color, w, h, inner)
		for _, sx in SIDES do
			local base = c.B + V(sx * 0.32, c.BS.Y * 0.55, c.BS.Z * 0.6)
			tri(b, "Wing", frameUp(base, V(sx, 0.8, 0.5), Vector3.zAxis), w or 0.85, h or 1.25, 0.08, color)
			if inner then
				tri(b, "Wing", frameUp(base + V(sx * 0.05, 0, 0.05), V(sx, 0.35, 0.6), Vector3.zAxis), (w or 0.85) * 0.8, (h or 1.25) * 0.75, 0.07, inner)
			end
		end
	end

	-- 꽃잎/잎을 cf 로컬 XY 평면에 빙 둘러요
	function H.petals(b, name, cf, n, r, size, color, mat, start)
		for i = 0, n - 1 do
			local a = (start or math.pi / 2) + i * 2 * math.pi / n
			ell(b, name, size, cf * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(0, 0, a - math.pi / 2), color, mat)
		end
	end

	-- 작은 꽃 (꽃잎 5 + 가운데)
	function H.flower(b, pos, dir, r, color, core, mat)
		local cf = CFrame.lookAt(pos, pos + dir)
		H.petals(b, "Petal", cf, 5, r * 0.55, V(r * 0.75, r * 0.95, 0.06), color, mat)
		ell(b, "Petal", V(r * 0.5, r * 0.5, 0.08), cf * CFrame.new(0, 0, -0.02), core, mat)
	end

	-- 뾰족한 칼날 (쐐기 2개): base 에서 dir 쪽으로 뾰족
	function H.blade(b, name, base, dir, side, w, h, t, color, mat, transparency)
		local d = dir.Unit
		local s = (side - d * side:Dot(d)).Unit
		tri(b, name, CFrame.fromMatrix(base, s, d), w, h, t, color, mat)
		if transparency then
			b.parts[#b.parts].Transparency = transparency
			b.parts[#b.parts - 1].Transparency = transparency
		end
	end

	-- 뿔 한 쌍 (머리 위에서 dir 쪽으로)
	function H.horns(b, c, color, len, spread, back, mat)
		for _, sx in SIDES do
			local d = V(sx * (spread or 0.35), 1, back or 0.45)
			local p = surf(c.H, c.HS, V(sx * 0.45, 1, 0.1))
			ell(b, "Horn", V(0.22, len or 0.58, 0.22), alongY(p + d.Unit * (len or 0.58) * 0.3, d), color, mat)
		end
	end

	-- 등 가시 (머리 뒤 → 몸 뒤). size 배율
	function H.spikes(b, c, color, k, mat)
		local s = k or 1
		for _, sp in { { c.H, c.HS, V(0, 0.55, 1) }, { c.H, c.HS, V(0, 0, 1) }, { c.B, c.BS, V(0, 0.6, 1) }, { c.B, c.BS, V(0, 0.1, 1) } } do
			local p, n = surf(sp[1], sp[2], sp[3])
			ell(b, "Spike", V(0.14 * s, 0.34 * s, 0.28 * s), alongY(p + n * 0.08 * s, n), color, mat)
		end
	end

	-- 2마디 꼬리. 끝 위치와 방향을 돌려줘요
	function H.tail(b, c, color, opt)
		local o = opt or {}
		local w = o.w or 0.5
		local tp = surf(c.B, c.BS, V(0, o.from or -0.4, 1))
		local d1 = (o.d1 or V(0, 0.15, 1)).Unit
		local t1 = tp + d1 * (o.l1 or 0.35)
		ell(b, "Tail", V(w, w, (o.l1 or 0.35) * 2.6), CFrame.lookAt(t1, t1 + d1), color)
		local d2 = (o.d2 or V(0, 0.6, 1)).Unit
		local t2 = t1 + d1 * 0.4 + d2 * 0.3
		ell(b, "Tail", V(w * 0.6, w * 0.6, (o.l2 or 0.65)), CFrame.lookAt(t2, t2 + d2), o.color2 or color)
		return t2 + d2 * (o.l2 or 0.65) * 0.45, d2
	end

	-- 머리 둘레 갈기 (뒤쪽 반원 + 위). n 개 공
	function H.mane(b, c, color, n, d, color2)
		local count = n or 9
		for i = 0, count - 1 do
			local a = math.rad(-110 + i * 220 / (count - 1))
			local dir = V(math.sin(a), math.cos(a), 0.55)
			local p = surf(c.H, c.HS, dir)
			local col = if color2 and i % 2 == 1 then color2 else color
			ell(b, "Mane", V(d or 0.62, d or 0.62, d or 0.62), CFrame.new(p + V(0, 0, 0.12)), col)
		end
	end

	-- 왕관 (띠 + 뾰족 5개 + 보석). pos = 띠 아래 가운데
	function H.crown(b, pos, r, color, gem, mat)
		local band = addPart(b, "Crown", "Cyl", V(0.22 * r / 0.4, r * 2, r * 2), CFrame.new(pos + V(0, 0.11 * r / 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, mat)
		for i = 0, 4 do
			local a = i * 2 * math.pi / 5
			local p = pos + V(math.sin(a) * r * 0.92, 0.22 * r / 0.4, -math.cos(a) * r * 0.92)
			ell(b, "Crown", V(0.12, 0.3, 0.12) * (r / 0.4), CFrame.new(p + V(0, 0.1 * r / 0.4, 0)), color, mat)
		end
		local gp = pos + V(0, 0.12 * r / 0.4, -r * 1.0)
		ell(b, "CrownGem", V(0.13, 0.13, 0.06) * (r / 0.4), CFrame.new(gp), gem, Enum.Material.Neon)
		return band
	end

	-- 머리 꼭대기 점 (왕관/모자 자리)
	function H.top(c, k)
		return c.H + V(0, c.HS.Y * (k or 0.88), 0)
	end

	-- 새 부리 (얼굴 앞, 아래로 살짝)
	function H.beak(b, c, color, y, size)
		local p, n = Kit.front(c.FC, c.FS, 0, y or -0.22)
		local s = size or V(0.34, 0.24, 0.36)
		local cf = facing(p + n * 0.06, n)
		ell(b, "Beak", s, cf, color)
		return cf
	end

	-- 얼굴 앞 동그란 주둥이 (공룡/말)
	function H.snout(b, c, color, size, y)
		local p, n = Kit.front(c.H, c.HS, 0, y or -0.28)
		local s = size or V(0.8, 0.5, 0.55)
		local cf = facing(p - n * 0.06, n)
		ell(b, "Muzzle", s, cf, color)
		for _, sx in SIDES do
			ell(b, "Nostril", V(0.07, 0.05, 0.04), cf * CFrame.new(sx * s.X * 0.18, s.Y * 0.12, -(s.Z * 0.5 - 0.02)), Kit.darker(color, 0.4))
		end
		ell(b, "Mouth", V(0.2, 0.06, 0.05), cf * CFrame.new(0, -s.Y * 0.22, -(s.Z * 0.5 - 0.04)), Kit.MOUTH)
		return cf
	end

	-- 땅에 닿는 네 발 짐승 몸 (말/공룡/사자): 몸통 가로 길쭉 + 다리 4 + 머리. Ctx 모양으로 돌려줘요
	function H.quad(b, o)
		local BS = o.BS or V(0.85, 0.7, 1.15)
		local legH = o.legH or 0.55
		local B = V(0, legH + BS.Y * 0.8, 0.2)
		local HS = o.HS or V(0.9, 0.85, 0.85)
		local Hc = o.headAt or V(0, B.Y + BS.Y * 0.95, B.Z - BS.Z * 0.75)
		ell(b, "Body", BS * 2, CFrame.new(B), o.body, o.mat)
		ell(b, "Head", HS * 2, CFrame.new(Hc), o.head or o.body, o.mat)
		local legCol = o.legs or Kit.darker(o.body, 0.1)
		for _, sx in SIDES do
			for _, sz in { -1, 1 } do
				local top = B + V(sx * BS.X * 0.55, -BS.Y * 0.4, sz * BS.Z * 0.55)
				local foot = V(top.X, 0.18, top.Z)
				H.link(b, "Leg", top, foot, o.legW or 0.44, legCol, o.mat)
				ell(b, "Foot", V(0.48, 0.32, 0.56), CFrame.new(foot + V(0, -0.02, -0.04)), o.feet or Kit.darker(legCol, 0.15), o.mat)
			end
		end
		local BeS = V(BS.X * 0.7, BS.Y * 0.6, BS.Z * 0.75)
		local BeC = B + V(0, -BS.Y * 0.38, 0)
		if o.belly then
			ell(b, "Belly", BeS * 2, CFrame.new(BeC), o.belly, o.mat)
		end
		local eyes = {}
		for _, sx in SIDES do
			table.insert(eyes, Kit.addEye(b, Hc, HS, sx * (o.eyeX or 0.36), o.eyeY or 0.08, o.eyeSize or V(0.32, 0.44, 0.15), 0))
			local p, n = Kit.front(Hc, HS, sx * ((o.eyeX or 0.36) + 0.24), (o.eyeY or 0.08) - 0.28)
			ell(b, "Blush", V(0.28, 0.15, 0.06), facing(p, n), Kit.BLUSH, nil, 0.1)
		end
		return { b = b, B = B, BS = BS, H = Hc, HS = HS, FC = Hc, FS = HS, BeC = BeC, BeS = BeS, eyes = eyes }
	end

	-- 여우 꼬마 (흰 볼 + 까만 코 + 뾰족 귀). opt: feet, arms, earX, earW, earH, earTilt, earIn
	function H.foxBase(b, col, belly, opt)
		local o = opt or {}
		local c = Kit.chibi(b, { body = col, belly = belly, feet = o.feet or Kit.darker(col, 0.25), arms = o.arms, eyeY = 0.06, noMouth = true, blushX = 0.7, blushY = -0.2 })
		for _, sx in SIDES do
			local p, n = Kit.front(c.H, c.HS, sx * 0.22, -0.36)
			ell(b, "Cheek", V(0.6, 0.45, 0.35), facing(p - n * 0.08, n), belly)
		end
		Kit.smallNose(c, -0.22, V(0.18, 0.12, 0.1), Kit.RGB(40, 30, 35), 0.05)
		Kit.pointyEars(c, o.earX or 0.55, 0.85, o.earW or 0.62, o.earH or 0.78, 0.15, o.earTilt or 0.28, col, o.earIn or Kit.RGB(255, 225, 215))
		return c
	end

	-- 반짝이 점 몇 개 (몸/머리 표면, 네온은 2개만)
	function H.sparkles(b, c, color, list)
		for i, s in list do
			local C, S = if s[1] == "H" then c.H else c.B, if s[1] == "H" then c.HS else c.BS
			local p, n = surf(C, S, s[2])
			local d = s[3] or 0.12
			ell(b, "Star", V(d, d, 0.05), facing(p + n * 0.01, n), color, if i <= 2 then Enum.Material.Neon else nil)
		end
	end

	-- 보석 (네모 보석: 다이아 모양 블록 2개)
	function H.gem(b, name, pos, size, color, mat, transparency)
		local cf = CFrame.new(pos) * CFrame.Angles(0, math.pi / 4, 0)
		addPart(b, name, "Block", V(size, size * 1.2, size), cf * CFrame.Angles(math.pi / 4, 0, 0) * CFrame.Angles(0, 0, 0), color, mat or Enum.Material.Glass, transparency or 0.1)
		return ell(b, name, V(size * 0.7, size * 0.7, size * 0.7), CFrame.new(pos), color, Enum.Material.Neon, 0.2)
	end

	return H
end

return V8Kit
