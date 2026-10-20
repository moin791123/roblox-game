-- v3 신규 펫 모델 (PetModels/init.luau 가 불러서 등록)
-- 정령 사슴 / 달빛 잉어 / 공작새 / 백호 / 눈꽃 여우 / 예티 / 일각고래 / 인어 냥이 / 용왕
-- 규칙은 init.luau 와 같아요: 앞쪽 = -Z, 바닥 = y 0, 머리 파트 이름 = Head,
-- 파트 이름 Eye/Shine/Blush/EyeWhite/Pupil 은 얼굴 전용 (등급 색을 안 입혀요).
return function(Kit, PET_BUILDERS, EGG_BUILDERS)
	local V, RGB, ell, surf, front, facing, addEye, chibi, SIDES = Kit.V, Kit.RGB, Kit.ell, Kit.surf, Kit.front, Kit.facing, Kit.addEye, Kit.chibi, Kit.SIDES
	local addPart, alongX, alongY, muzzle, smallNose, pointyEars, roundEars, ballArc = Kit.addPart, Kit.alongX, Kit.alongY, Kit.muzzle, Kit.smallNose, Kit.pointyEars, Kit.roundEars, Kit.ballArc
	local tri, WHITE, BLUSH, MOUTH = Kit.tri, Kit.WHITE, Kit.BLUSH, Kit.MOUTH
	local NEON = Enum.Material.Neon
	local GLASS = Enum.Material.Glass

	-- 기본 몸에서 바꿔 끼울 파트를 빌더 목록에서 빼고 지워요
	local function dropParts(b, name)
		for i = #b.parts, 1, -1 do
			local p = b.parts[i]
			if p.Name == name then
				table.remove(b.parts, i)
				p:Destroy()
			end
		end
	end

	-- 곡면에 착 붙는 무늬: 표면 점 p(법선 n)에서 poke 만큼만 튀어나온 납작 타원체.
	-- 두께를 곡률(반지름 R)에 맞춰서 가장자리가 붕 뜨지 않아요.
	local function stick(b, name, p, n, w, h, R, color, spin, mat)
		local a = math.max(w, h) * 0.5
		local t = math.clamp(a * a / R, 0.05, a)
		return ell(b, name, V(w, h, t * 2), facing(p - n * (t - 0.03), n) * CFrame.Angles(0, 0, spin or 0), color, mat)
	end

	local function patch(b, name, C, S, dir, w, h, color, spin)
		local p, n = surf(C, S, dir)
		return stick(b, name, p, n, w, h, (S.X + S.Y + S.Z) / 3, color, spin)
	end

	local function glow(part, color, brightness, range)
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Brightness = brightness
		light.Range = range
		light.Shadows = false
		light.Parent = part
	end

	-- 두 점 사이를 잇는 길쭉한 타원체 (팔/꼬리 마디)
	local function link(b, name, p0, p1, w, h, extra, color, mat)
		local mid = (p0 + p1) * 0.5
		return ell(b, name, V(w, h, (p1 - p0).Magnitude + extra), CFrame.lookAt(mid, p1), color, mat)
	end

	----------------------------------------------------------------------
	-- 정령 사슴: 하얀 민트빛 아기 사슴, 작은 잎이 달린 갈래 뿔, 등에 네온 민트 점, 옆에 떠 있는 반딧불 3개
	----------------------------------------------------------------------
	PET_BUILDERS.SpiritDeer = function(b)
		local FUR = RGB(222, 248, 236)
		local CREAM = RGB(255, 252, 240)
		local HOOF = RGB(150, 200, 182)
		local ANTLER = RGB(222, 196, 158)
		local LEAF = RGB(110, 210, 115)
		local GLOW = RGB(120, 255, 200)
		local FIRE = RGB(255, 238, 110)
		local c = chibi(b, { body = FUR, belly = CREAM, feet = HOOF, eyeY = 0.08, noMouth = true, blushX = 0.7, blushY = -0.2 })
		muzzle(c, V(0.56, 0.38, 0.36), CREAM, RGB(120, 85, 95), -0.32)

		-- 옆으로 뻗은 나뭇잎 모양 귀 (바깥 끝이 살짝 위로)
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx, 0.42, 0.05))
			ell(b, "Ear", V(0.66, 0.3, 0.2), CFrame.new(p + n * 0.14) * CFrame.Angles(0, 0, sx * 0.4), FUR)
		end

		-- 갈래 뿔: 줄기 + 바깥 가지, 끝마다 작은 잎
		for _, sx in SIDES do
			local ap = surf(c.H, c.HS, V(sx * 0.42, 1, 0.12))
			local d1 = V(sx * 0.42, 1, 0.12).Unit
			addPart(b, "Antler", "Cyl", V(0.8, 0.13, 0.13), alongX(ap + d1 * 0.3, d1), ANTLER)
			local bp = ap + d1 * 0.42
			local d2 = V(sx, 0.75, -0.2).Unit
			addPart(b, "Antler", "Cyl", V(0.46, 0.1, 0.1), alongX(bp + d2 * 0.2, d2), ANTLER)
			local l1 = V(sx * 0.5, 1, 0).Unit
			ell(b, "Leaf", V(0.24, 0.4, 0.07), alongY(ap + d1 * 0.66 + l1 * 0.16, l1), LEAF)
			local l2 = V(sx, 0.35, 0).Unit
			ell(b, "Leaf", V(0.22, 0.36, 0.07), alongY(bp + d2 * 0.4 + l2 * 0.15, l2), LEAF)
		end

		-- 등과 뒤통수의 빛나는 민트 점
		for _, s in { { c.B, c.BS, V(0.6, 0.25, 0.75) }, { c.B, c.BS, V(-0.55, 0.05, 0.8) }, { c.H, c.HS, V(0.3, 0.25, 1) } } do
			local p, n = surf(s[1], s[2], s[3])
			ell(b, "Spot", V(0.26, 0.24, 0.06), facing(p + n * 0.005, n), GLOW, NEON)
		end

		-- 반딧불 (머리/몸 AABB 귀퉁이에 떠 있어요)
		ell(b, "Firefly", V(0.2, 0.2, 0.2), CFrame.new(1.13, 2.86, -0.35), FIRE, NEON)
		ell(b, "Firefly", V(0.17, 0.17, 0.17), CFrame.new(-1.0, 1.58, 0.5), FIRE, NEON)
		ell(b, "Firefly", V(0.18, 0.18, 0.18), CFrame.new(0.98, 0.52, -0.62), FIRE, NEON)

		local tp, tn = surf(c.B, c.BS, V(0, 0.1, 1))
		ell(b, "Tail", V(0.3, 0.34, 0.26), CFrame.new(tp + tn * 0.06), CREAM)
	end

	----------------------------------------------------------------------
	-- 달빛 잉어: 꼬리지느러미로 서 있는 통통한 은백색 잉어, 주홍 무늬, 큰 꼬리, 이마의 네온 초승달
	----------------------------------------------------------------------
	PET_BUILDERS.MoonKoi = function(b)
		local SILVER = RGB(240, 244, 250)
		local RED = RGB(250, 100, 60)
		local FIN = RGB(255, 228, 215)
		local FINTIP = RGB(255, 150, 110)
		local MOON = RGB(255, 240, 150)

		-- 큰 머리 + 아래로 좁아지는 몸 = 통통한 물방울 모양 (둘레가 매끈하게 이어져요)
		local B = V(0, 1.35, 0.05)
		local BS = V(0.9, 0.85, 0.8)
		local H = V(0, 2.25, -0.05)
		local HS = V(1.0, 0.98, 0.92)
		local body = ell(b, "Body", BS * 2, CFrame.new(B), SILVER)
		local head = ell(b, "Head", HS * 2, CFrame.new(H), SILVER)
		body.Reflectance = 0.08
		head.Reflectance = 0.08

		-- 꼬리자루 + 바닥에 치마처럼 펼친 큰 꼬리지느러미 4장 (끝이 살짝 들리고 주홍빛)
		ell(b, "Tail", V(0.84, 0.9, 0.84), CFrame.new(0, 0.45, 0.12), SILVER)
		local base = V(0, 0.18, 0.15)
		for _, deg in { -85, -30, 30, 85 } do
			local a = math.rad(deg)
			local d = V(math.sin(a), 0, math.cos(a))
			local side = math.abs(deg) > 60
			local lift = if side then 0.3 else 0.55
			local L = if side then 0.9 else 1.5
			-- 안쪽 끝을 축으로 바깥 끝만 들어 올려요 (AABB 가 바닥 아래로 안 내려가게)
			local cf = CFrame.lookAt(base, base + d) * CFrame.Angles(lift, 0, 0) * CFrame.new(0, 0, -L * 0.42)
			ell(b, "TailFin", V(if side then 0.72 else 0.8, 0.16, L), cf, FIN)
			ell(b, "TailFinTip", V(if side then 0.46 else 0.6, 0.13, 0.42), cf * CFrame.new(0, 0.02, -L * 0.37), FINTIP)
		end

		-- 가슴지느러미 (팔처럼) + 등지느러미
		for _, sx in SIDES do
			local p, n = surf(B, BS, V(sx, 0.15, -0.3))
			ell(b, "Fin", V(0.22, 0.55, 0.42), CFrame.new(p + n * 0.08) * CFrame.Angles(0.3, 0, sx * 0.6), FIN)
		end
		ell(b, "DorsalFin", V(0.12, 1.3, 0.55), CFrame.new(0, 2.0, 0.86) * CFrame.Angles(0.35, 0, 0), FIN)

		-- 얼굴: 큰 눈, 볼터치, 동그란 입술, 수염 2가닥
		for _, sx in SIDES do
			addEye(b, H, HS, sx * 0.42, -0.02, V(0.38, 0.5, 0.16), 0)
			local p, n = front(H, HS, sx * 0.68, -0.32)
			ell(b, "Blush", V(0.3, 0.16, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		local mp, mn = front(H, HS, 0, -0.42)
		local mcf = facing(mp + mn * 0.03, mn)
		ell(b, "Lips", V(0.26, 0.18, 0.1), mcf, RGB(255, 196, 190))
		ell(b, "Mouth", V(0.14, 0.09, 0.05), mcf * CFrame.new(0, 0, -0.04), MOUTH)
		for _, sx in SIDES do
			local d = V(sx, -0.9, -0.3).Unit
			ell(b, "Barbel", V(0.045, 0.24, 0.045), alongY(mcf * V(sx * 0.14, -0.02, 0) + d * 0.11, d), FINTIP)
		end

		-- 이마 초승달: 네온 원판 위에 머리색 원판을 비껴 덮음
		local fp, fn = front(H, HS, 0, 0.5)
		local fcf = facing(fp + fn * 0.01, fn)
		ell(b, "Moon", V(0.46, 0.46, 0.06), fcf, MOON, NEON)
		local cut = ell(b, "MoonCut", V(0.4, 0.4, 0.07), fcf * CFrame.new(0.13, 0.07, -0.012), SILVER)
		cut.Reflectance = 0.08

		-- 주홍 무늬 (머리 위가 제일 커요)
		patch(b, "Patch", H, HS, V(0.25, 1, 0.35), 1.0, 0.85, RED)
		patch(b, "Patch", H, HS, V(-0.75, 0.5, -0.4), 0.5, 0.42, RED)
		patch(b, "Patch", B, BS, V(0.95, 0.25, 0.3), 0.7, 0.6, RED)
		patch(b, "Patch", B, BS, V(-0.8, -0.3, 0.55), 0.55, 0.5, RED)
	end

	----------------------------------------------------------------------
	-- 공작새: 동그란 청보라 새, 작은 볏, 등 뒤로 활짝 선 청록/초록 부채 꼬리 + 금색 눈 무늬
	----------------------------------------------------------------------
	PET_BUILDERS.Peacock = function(b)
		local BLUE = RGB(40, 95, 215)
		local BLUE_H = RGB(55, 115, 235)
		local WING = RGB(35, 120, 165)
		local TEAL = RGB(25, 170, 160)
		local GREEN = RGB(80, 195, 105)
		local GOLD = RGB(255, 205, 70)
		local c = chibi(b, { body = BLUE, head = BLUE_H, feet = RGB(170, 160, 170), noArms = true, noMouth = true, eyeY = 0.05, blushY = -0.24 })
		local p, n = front(c.H, c.HS, 0, -0.22)
		ell(b, "Beak", V(0.26, 0.2, 0.3), facing(p + n * 0.06, n), RGB(240, 220, 175))

		-- 볏: 가는 줄기 3개 + 동그란 끝
		for _, dx in { -0.16, 0, 0.16 } do
			local d = V(dx * 1.8, 1, 0.1).Unit
			local cp = surf(c.H, c.HS, V(dx, 1, -0.05))
			ell(b, "Crest", V(0.06, 0.46, 0.06), alongY(cp + d * 0.2, d), BLUE_H)
			ell(b, "CrestTip", V(0.17, 0.17, 0.17), CFrame.new(cp + d * 0.44), TEAL)
		end

		for _, sx in SIDES do
			local wp, wn = surf(c.B, c.BS, V(sx, 0.1, 0.15))
			ell(b, "Wing", V(0.3, 0.9, 0.72), CFrame.new(wp + wn * 0.02) * CFrame.Angles(0, 0, sx * 0.18), WING)
		end

		-- 부채 꼬리: 몸 뒤 한 점에서 퍼지는 깃털 7장 (가운데가 제일 길어요), 살짝 뒤로 젖힘
		local F = V(0, 1.2, 0.9)
		local tilt = 0.25
		local nBack = V(0, -math.sin(tilt), math.cos(tilt))
		local count = 7
		for i = 1, count do
			local f = (i - 1) / (count - 1)
			local a = math.rad(-68 + 136 * f)
			local L = 2.75 - 0.75 * math.abs(a) / math.rad(68)
			local d = V(math.sin(a), math.cos(a) * math.cos(tilt), math.cos(a) * math.sin(tilt))
			ell(b, "Feather", V(0.8, L, 0.12), CFrame.fromMatrix(F + d * (L * 0.5), d:Cross(nBack), d), if i % 2 == 0 then GREEN else TEAL)
			ell(b, "Ocellus", V(0.36, 0.44, 0.06), facing(F + d * (L * 0.8) - nBack * 0.07, -nBack), GOLD)
		end
	end

	----------------------------------------------------------------------
	-- 백호: 통통한 하얀 아기 호랑이, 청회색 줄무늬(이마에 王), 얼음빛 네온 눈, 복슬 꼬리
	----------------------------------------------------------------------
	PET_BUILDERS.WhiteTiger = function(b)
		local W = RGB(242, 245, 252)
		local ST = RGB(100, 118, 158)
		local ICE = RGB(110, 220, 255)
		local c = chibi(b, { body = W, belly = WHITE, feet = WHITE, noEyes = true, noMouth = true, eyeX = 0.4, eyeY = 0.06, blushX = 0.7, blushY = -0.22 })

		-- 얼음빛 네온 눈 + 남색 눈동자 + 반짝이
		local es = V(0.36, 0.46, 0.16)
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.4, 0.06)
			local cf = facing(p, n)
			ell(b, "Eye", es, cf, ICE, NEON)
			ell(b, "Pupil", V(0.16, 0.28, 0.06), cf * CFrame.new(0, -0.03, -0.07), RGB(30, 40, 75))
			ell(b, "Shine", V(0.14, 0.14, 0.04), cf * CFrame.new(es.X * 0.2, es.Y * 0.22, -0.1), WHITE, NEON)
			ell(b, "Shine", V(0.07, 0.07, 0.04), cf * CFrame.new(-es.X * 0.17, -es.Y * 0.2, -0.095), WHITE, NEON)
		end

		roundEars(c, 0.62, 0.8, 0.5, W, RGB(255, 200, 215))
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.17, -0.34)
			ell(b, "Muzzle", V(0.44, 0.33, 0.28), facing(p - n * 0.06, n), WHITE)
		end
		smallNose(c, -0.2, V(0.18, 0.12, 0.08), RGB(255, 150, 170), 0.04)

		-- 이마의 王 무늬 (가로 3줄 + 세로 1줄), 볼 옆 줄무늬, 몸통 옆 줄무늬
		local R = (c.HS.X + c.HS.Y + c.HS.Z) / 3
		for i, w in { 0.44, 0.32, 0.5 } do
			local p, n = front(c.H, c.HS, 0, 0.8 - (i - 1) * 0.15)
			stick(b, "Stripe", p, n, w, 0.1, R, ST)
		end
		local vp, vn = front(c.H, c.HS, 0, 0.65)
		stick(b, "Stripe", vp, vn, 0.1, 0.36, R, ST)
		for _, sx in SIDES do
			patch(b, "Stripe", c.H, c.HS, V(sx, 0.2, 0.3), 0.6, 0.14, ST, sx * 0.25)
			patch(b, "Stripe", c.B, c.BS, V(sx * 0.8, 0.35, 0.6), 0.16, 0.7, ST, -sx * 0.3)
		end

		-- 복슬 꼬리 (하양 - 줄무늬 - 큰 하양 끝)
		local tp = surf(c.B, c.BS, V(0, -0.2, 1))
		ballArc(b, "Tail", tp + V(0, 0, 0.12), 0.7, { W, ST, W }, 0.46, 0.64)
	end

	----------------------------------------------------------------------
	-- 눈꽃 여우: 연한 얼음빛 여우, 이마의 눈꽃, 끝에 유리 얼음 결정이 달린 아주 큰 하얀 꼬리
	----------------------------------------------------------------------
	PET_BUILDERS.FrostFox = function(b)
		local ICE = RGB(192, 226, 255)
		local Wt = RGB(250, 253, 255)
		local DEEP = RGB(125, 170, 228)
		local FLAKE = RGB(110, 185, 255)
		local CRY = RGB(165, 235, 255)
		local c = chibi(b, { body = ICE, belly = Wt, feet = DEEP, arms = DEEP, eyeY = 0.06, noMouth = true, blushX = 0.7, blushY = -0.2 })
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.22, -0.36)
			ell(b, "Cheek", V(0.6, 0.45, 0.35), facing(p - n * 0.08, n), Wt)
		end
		smallNose(c, -0.22, V(0.18, 0.12, 0.1), RGB(60, 70, 115), 0.05)
		pointyEars(c, 0.55, 0.85, 0.62, 0.78, 0.15, 0.28, ICE, Wt)

		-- 이마 눈꽃: 가는 막대 3개가 60도씩 교차
		local fp, fn = front(c.H, c.HS, 0, 0.55)
		local fcf = facing(fp + fn * 0.02, fn)
		for i = 0, 2 do
			addPart(b, "Snowflake", "Block", V(0.42, 0.06, 0.04), fcf * CFrame.Angles(0, 0, math.pi / 2 + i * math.pi / 3), FLAKE, NEON)
		end

		-- 큰 복슬 꼬리: 뒤로 나갔다가 오른쪽 위로 (앞에서도 머리 옆으로 보여요)
		local tails = {
			{ V(0.25, 0.62, 0.95), 0.78, ICE },
			{ V(0.55, 1.12, 1.42), 0.98, Wt },
			{ V(0.82, 1.8, 1.55), 1.0, Wt },
		}
		for _, t in tails do
			ell(b, "Tail", V(t[2], t[2], t[2]), CFrame.new(t[1]), t[3])
		end
		-- 꼬리 끝 얼음 결정: 유리 기둥 + 뾰족한 지붕 (쐐기 2개), 45도 돌려서 보석처럼
		local cb = V(0.9, 2.2, 1.55)
		local cd = V(0.3, 1, -0.05).Unit
		local cw = 0.4
		addPart(b, "Crystal", "Block", V(cw, 0.7, cw), alongY(cb + cd * 0.33, cd) * CFrame.Angles(0, math.pi / 4, 0), CRY, GLASS, 0.25)
		tri(b, "Crystal", alongY(cb + cd * 0.67, cd) * CFrame.Angles(0, math.pi / 4, 0), cw, 0.48, cw, CRY, GLASS)
		for i = #b.parts - 1, #b.parts do
			b.parts[i].Transparency = 0.25
		end
	end

	----------------------------------------------------------------------
	-- 예티: 동글동글 복슬한 하얀 눈 아기 거인, 하늘색 얼굴, 작은 뿔 2개, 큰 발, 작은 눈덩이를 안고 있어요
	----------------------------------------------------------------------
	PET_BUILDERS.Yeti = function(b)
		local FUR = RGB(250, 252, 255)
		local FACE = RGB(160, 205, 245)
		local SKIN = RGB(135, 180, 232)
		local HORN = RGB(235, 225, 200)
		local c = chibi(b, {
			body = FUR,
			BS = V(1.05, 0.85, 0.92),
			HS = V(1.12, 1.0, 1.0),
			noArms = true,
			noMouth = true,
			face = { color = FACE, semi = V(0.84, 0.7, 0.6), offset = V(0, -0.1, -0.47) },
			eyeX = 0.32,
			eyeY = 0.1,
			eyeSize = V(0.34, 0.44, 0.16),
			blushX = 0.56,
			blushY = -0.16,
		})
		dropParts(b, "Foot")

		-- 코 + 벌린 입 + 작은 송곳니 2개
		local np, nn = front(c.FC, c.FS, 0, -0.08)
		ell(b, "Nose", V(0.2, 0.13, 0.08), facing(np + nn * 0.02, nn), RGB(95, 140, 200))
		local mp, mn = front(c.FC, c.FS, 0, -0.3)
		local mcf = facing(mp, mn)
		ell(b, "Mouth", V(0.34, 0.17, 0.07), mcf, MOUTH)
		for _, sx in SIDES do
			ell(b, "Tooth", V(0.08, 0.1, 0.05), mcf * CFrame.new(sx * 0.09, -0.03, -0.03), WHITE)
		end

		-- 큰 발
		for _, sx in SIDES do
			ell(b, "Foot", V(0.82, 0.46, 1.12), CFrame.new(sx * 0.55, 0.23, -0.38), SKIN)
		end

		-- 배 앞에 안은 눈덩이 + 아래로 내려온 두 팔 (손바닥은 하늘색)
		local SB = c.B + V(0, -0.12, -c.BS.Z - 0.3)
		local ball = ell(b, "Snowball", V(0.72, 0.72, 0.72), CFrame.new(SB), RGB(225, 240, 255))
		ball.Reflectance = 0.05
		for _, sx in SIDES do
			local sp = surf(c.B, c.BS, V(sx, 0.45, -0.25))
			local hand = SB + V(sx * 0.36, 0.08, 0.04)
			link(b, "Arm", sp, hand, 0.4, 0.4, 0.12, FUR)
			ell(b, "Paw", V(0.3, 0.32, 0.26), CFrame.new(hand + V(sx * 0.04, 0, -0.02)), SKIN)
		end

		-- 작은 뿔 2개 + 머리 위 복슬 털
		for _, sx in SIDES do
			local d = V(sx * 0.45, 1, 0.05).Unit
			local hp = surf(c.H, c.HS, V(sx * 0.5, 1, 0.05))
			ell(b, "Horn", V(0.2, 0.46, 0.2), alongY(hp + d * 0.16, d), HORN)
		end
		for _, d in { V(-0.18, 1, -0.25), V(0.15, 1, -0.1), V(0, 0.9, 0.35) } do
			local p, n = surf(c.H, c.HS, d)
			ell(b, "Fluff", V(0.45, 0.4, 0.45), CFrame.new(p + n * 0.02), FUR)
		end
		-- 얼굴 옆 복슬 구레나룻 + 엉덩이 쪽 복슬 털
		for _, sx in SIDES do
			local p, n = surf(c.H, c.HS, V(sx, -0.45, -0.3))
			ell(b, "Fluff", V(0.5, 0.5, 0.5), CFrame.new(p + n * 0.02), FUR)
			local q, m = surf(c.B, c.BS, V(sx * 0.8, -0.45, 0.6))
			ell(b, "Fluff", V(0.55, 0.5, 0.55), CFrame.new(q + m * 0.02), FUR)
		end
	end

	----------------------------------------------------------------------
	-- 일각고래: 동그란 하늘색 고래, 하얀 배, 길게 꼬인 크림색 뿔, 작은 지느러미
	----------------------------------------------------------------------
	PET_BUILDERS.Narwhal = function(b)
		local BLUE = RGB(150, 200, 242)
		local DEEP = RGB(105, 160, 220)
		local BELLY = RGB(245, 250, 255)
		local HORN = RGB(252, 240, 205)
		local GROOVE = RGB(215, 192, 145)

		local H = V(0, 1.06, -0.3)
		local HS = V(1.08, 1.06, 1.0)
		local B = V(0, 0.92, 0.55)
		local BS = V(0.88, 0.82, 1.05)
		ell(b, "Body", BS * 2, CFrame.new(B), BLUE)
		ell(b, "Head", HS * 2, CFrame.new(H), BLUE)
		ell(b, "Belly", V(1.6, 1.15, 1.6), CFrame.new(H + V(0, -0.45, -0.2)), BELLY)

		for _, sx in SIDES do
			addEye(b, H, HS, sx * 0.44, 0.18, V(0.36, 0.46, 0.16), 0)
			local p, n = front(H, HS, sx * 0.74, -0.08)
			ell(b, "Blush", V(0.32, 0.17, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end
		local mp, mn = front(H, HS, 0, -0.12)
		ell(b, "Mouth", V(0.4, 0.09, 0.06), facing(mp, mn), MOUTH)

		-- 뿔: 이마에서 앞위로 길게 + 비스듬한 홈 4개 (나선처럼 보여요)
		local hd = V(0, 0.93, -0.37).Unit
		local hp = surf(H, HS, V(0, 0.62, -0.78))
		local hl = 1.75
		local hc = hp + hd * (hl * 0.5 - 0.18)
		ell(b, "Horn", V(0.32, hl, 0.32), alongY(hc, hd), HORN)
		local tiltAxis = (hd + V(0.45, 0, 0)).Unit
		local cosT = tiltAxis:Dot(hd)
		for i = 1, 4 do
			local h = -0.45 + (i - 1) * 0.3
			local r = 0.16 * math.sqrt(math.max(1 - (h / (hl * 0.5)) ^ 2, 0))
			local D = 2 * r / cosT + 0.03
			addPart(b, "HornRing", "Cyl", V(0.05, D, D), alongX(hc + hd * h, tiltAxis), GROOVE)
		end

		-- 작은 옆지느러미
		for _, sx in SIDES do
			local p = surf(H, HS, V(sx, -0.3, 0.05))
			local cf = CFrame.new(p + V(sx * 0.12, -0.08, 0)) * CFrame.Angles(0, -sx * 0.35, 0) * CFrame.Angles(0, 0, -sx * 0.5)
			ell(b, "Flipper", V(0.62, 0.15, 0.4), cf, DEEP)
		end

		-- 위로 들린 꼬리 + 꼬리지느러미
		local tp = surf(B, BS, V(0, 0.25, 1))
		local d1 = V(0, 0.5, 1).Unit
		local t1 = tp + d1 * 0.25
		ell(b, "Tail", V(0.5, 0.42, 1.0), CFrame.lookAt(t1, t1 + d1), BLUE)
		local te = t1 + d1 * 0.45
		for _, sx in SIDES do
			local cf = CFrame.new(te + V(sx * 0.36, 0.04, 0.1)) * CFrame.Angles(0, -sx * 0.45, 0) * CFrame.Angles(0, 0, sx * 0.2)
			ell(b, "Fluke", V(0.8, 0.12, 0.46), cf, DEEP)
		end

		-- 등의 점박이
		for _, s in { { B, BS, V(0.45, 0.85, 0.25) }, { B, BS, V(-0.4, 0.9, 0.55) }, { H, HS, V(-0.35, 0.8, 0.5) } } do
			local p, n = surf(s[1], s[2], s[3])
			ell(b, "Spot", V(0.24, 0.22, 0.06), facing(p + n * 0.005, n), DEEP)
		end
	end

	----------------------------------------------------------------------
	-- 인어 냥이: 크림색 아기 고양이 상반신 + 청록→분홍 비늘 물고기 꼬리, 머리에 분홍 조개
	----------------------------------------------------------------------
	PET_BUILDERS.MermaidCat = function(b)
		local CREAM = RGB(255, 240, 215)
		local WT = RGB(255, 250, 242)
		local EARIN = RGB(255, 185, 200)
		local T1 = RGB(70, 205, 195)
		local T2 = RGB(115, 195, 215)
		local T3 = RGB(180, 175, 225)
		local T4 = RGB(240, 160, 210)
		local FINC = RGB(255, 150, 195)
		local SCALE = RGB(150, 235, 225)
		local SHELL = RGB(255, 170, 190)
		local SHELL2 = RGB(240, 120, 160)
		local c = chibi(b, { body = CREAM, eyeY = 0.05, noMouth = true, blushY = -0.22 })
		dropParts(b, "Foot")
		for _, sx in SIDES do
			local p, n = front(c.H, c.HS, sx * 0.16, -0.33)
			ell(b, "Muzzle", V(0.42, 0.32, 0.28), facing(p - n * 0.06, n), WT)
		end
		smallNose(c, -0.2, V(0.16, 0.11, 0.08), RGB(255, 130, 160), 0.04)
		pointyEars(c, 0.55, 0.85, 0.6, 0.62, 0.16, 0.3, CREAM, EARIN)

		-- 물고기 꼬리: 허리 → 뒤 → 오른쪽으로 감아 앞으로, 끝에 분홍 지느러미 2장
		-- (허리 아래는 몸보다 살짝 좁아서 상반신에서 매끈하게 이어져요)
		local hipC, hipS = V(0, 0.5, 0.08), V(0.85, 0.5, 0.8)
		ell(b, "TailBase", hipS * 2, CFrame.new(hipC), T1)
		ell(b, "Tail", V(0.86, 0.62, 1.0), CFrame.new(0.72, 0.31, 0.5) * CFrame.Angles(0, 0.8, 0), T2)
		ell(b, "Tail", V(0.66, 0.5, 0.9), CFrame.new(1.15, 0.25, -0.05) * CFrame.Angles(0, -0.1, 0), T3)
		ell(b, "Tail", V(0.46, 0.4, 0.66), CFrame.new(1.2, 0.2, -0.58) * CFrame.Angles(0, -0.35, 0), T4)
		local fe = V(1.24, 0.28, -0.86)
		for _, d in { V(0.05, 1, -0.35), V(0.55, 1, -0.25) } do
			local u = d.Unit
			ell(b, "Fin", V(0.55, 1.1, 0.12), alongY(fe + u * 0.5, u), FINC)
		end
		for _, sx in SIDES do
			local p, n = front(hipC, hipS, sx * 0.32, 0.05)
			ell(b, "Scale", V(0.26, 0.18, 0.06), facing(p, n), SCALE)
		end

		-- 머리 위 분홍 가리비 조개 (부채 + 홈 2줄 + 밑동)
		local sp = surf(c.H, c.HS, V(0, 1, -0.3))
		local scf = CFrame.new(sp + V(0, 0.16, -0.02)) * CFrame.Angles(-0.3, 0, 0)
		ell(b, "Shell", V(0.62, 0.52, 0.14), scf, SHELL)
		for _, dx in { -0.13, 0.13 } do
			ell(b, "ShellRidge", V(0.06, 0.4, 0.05), scf * CFrame.new(dx, 0.02, -0.065) * CFrame.Angles(0, 0, -dx * 2), SHELL2)
		end
		ell(b, "ShellBase", V(0.22, 0.14, 0.12), scf * CFrame.new(0, -0.24, -0.02), SHELL2)
	end

	----------------------------------------------------------------------
	-- 용왕: S 자로 감아 올라간 바다색 동양 용, 금 뿔과 금 수염, 빛나는 하얀 네온 여의주를 들고 있어요
	----------------------------------------------------------------------
	PET_BUILDERS.DragonKing = function(b)
		local SEA = RGB(60, 190, 150)
		local BELLY = RGB(250, 238, 185)
		local GOLD = RGB(255, 200, 70)
		local MANE = RGB(130, 225, 235)
		local PEARL = RGB(250, 250, 255)

		-- 몸: 바닥 가운데 동그란 몸통에서 왼쪽은 꼬리, 오른쪽은 S 자로 감아 올라가 목까지.
		-- 이웃 마디를 길쭉한 타원체로 이어서 매끈한 뱀 몸처럼 보여요.
		local BC = V(0, 0.46, 0.3)
		ell(b, "Body", V(0.92, 0.92, 0.92), CFrame.new(BC), SEA)
		local pts = {
			V(-1.3, 0.8, 0.0), -- 꼬리 끝 (살짝 들림)
			V(-1.0, 0.4, 0.15),
			V(-0.4, 0.42, 0.28),
			V(0.5, 0.55, 0.32),
			V(0.86, 1.02, 0.38),
			V(0.55, 1.52, 0.45),
			V(-0.25, 1.74, 0.45),
			V(-0.48, 2.14, 0.3),
			V(-0.1, 2.48, 0.1), -- 목 (머리 아래)
		}
		local widths = { 0.3, 0.52, 0.7, 0.8, 0.82, 0.8, 0.76, 0.72 }
		for i = 1, #pts - 1 do
			local w = widths[i]
			link(b, if i <= 2 then "Tail" else "Coil", pts[i], pts[i + 1], w, w, w * 0.55, SEA)
		end
		-- 앞으로 선 마디의 크림색 배 비늘
		link(b, "BellyPlate", pts[4] + V(0.02, 0.02, -0.33), pts[5] + V(-0.05, 0, -0.33), 0.46, 0.14, 0.15, BELLY)

		-- 등지느러미 (금색 작은 가시)
		for _, i in { 2, 6 } do
			local mid = (pts[i] + pts[i + 1]) * 0.5
			local d = V(0, 1, 0.7).Unit
			ell(b, "Spine", V(0.1, 0.36, 0.26), alongY(mid + d * (widths[i] * 0.5 + 0.06), d), GOLD)
		end
		-- 꼬리 끝 지느러미
		local tl = V(-0.4, 1, 0).Unit
		ell(b, "TailFin", V(0.36, 0.6, 0.12), alongY(pts[1] + tl * 0.3, tl), MANE)

		-- 머리: 둥근 머리 + 앞으로 나온 주둥이
		local H = V(0, 2.9, -0.12)
		local HS = V(0.8, 0.66, 0.74)
		ell(b, "Head", HS * 2, CFrame.new(H), SEA)
		local sp, sn = front(H, HS, 0, -0.3)
		local scf = facing(sp + sn * 0.16, sn)
		ell(b, "Snout", V(0.74, 0.44, 0.6), scf, SEA)
		ell(b, "Mouth", V(0.3, 0.07, 0.05), scf * CFrame.new(0, -0.11, -0.28), MOUTH)
		for _, sx in SIDES do
			addEye(b, H, HS, sx * 0.34, 0.14, V(0.3, 0.4, 0.15), 0)
			local p, n = front(H, HS, sx * 0.6, -0.12)
			ell(b, "Blush", V(0.26, 0.14, 0.06), facing(p, n), BLUSH, nil, 0.1)
		end

		-- 금 뿔 (줄기 + 앞가지), 아래로 늘어진 금 수염, 뒤로 흘러내린 갈기
		for _, sx in SIDES do
			local hp = surf(H, HS, V(sx * 0.45, 0.9, 0.35))
			local d1 = V(sx * 0.35, 1, 0.45).Unit
			addPart(b, "Horn", "Cyl", V(0.75, 0.14, 0.14), alongX(hp + d1 * 0.28, d1), GOLD)
			local kp = hp + d1 * 0.38
			local d2 = V(sx * 0.3, 0.7, -0.6).Unit
			addPart(b, "Horn", "Cyl", V(0.36, 0.11, 0.11), alongX(kp + d2 * 0.16, d2), GOLD)
			local wd = V(sx, -0.75, -0.3).Unit
			ell(b, "Whisker", V(0.06, 0.8, 0.06), alongY(scf * V(sx * 0.33, -0.04, -0.12) + wd * 0.38, wd), GOLD)
			local mp = surf(H, HS, V(sx * 0.4, -0.1, 0.9))
			local md = V(sx * 0.3, -0.6, 1).Unit
			ell(b, "Mane", V(0.34, 0.34, 0.75), CFrame.lookAt(mp + md * 0.2, mp + md), MANE)
		end

		-- 두 팔로 든 빛나는 여의주
		local P = V(-0.02, 1.5, -0.45)
		local pearl = ell(b, "Pearl", V(0.52, 0.52, 0.52), CFrame.new(P), PEARL, NEON)
		glow(pearl, RGB(220, 240, 255), 0.9, 7)
		local cm = (pts[6] + pts[7]) * 0.5
		for _, sx in SIDES do
			link(b, "Arm", cm + V(sx * 0.32, -0.08, -0.25), P + V(sx * 0.28, 0.04, 0.02), 0.2, 0.2, 0.12, SEA)
		end
	end
end
