-- 🐣 부화 연출: 알 흔들흔들 → 반짝 → 펫 등장 + 빙글빙글 + 색종이
-- ✨ 합성 연출(mode "Fuse"): 알 대신 작은 펫 3마리가 가운데로 모여 합쳐진 뒤 다음 등급 펫 등장
-- 등급 7단계 (기본 / 🥉 브론즈 / 🥈 실버 / 🥇 골드 / 🌈 레인보우 / 💎 다이아 / 🌌 갤럭시): 색·글자는 Config.Tiers
-- ★ 화면 가운데(캐릭터·눈높이)를 가리지 않게 오른쪽 옆 칸에 작게 떠요 (UiKit.SideSpot):
--   화면을 어둡게 하지 않고, 번쩍임·색종이도 그 칸 안에서만. 코인 줄·창 ✖·점프 버튼·꾸미기 버튼은 피해요.
--   좋은 알 배너(Toasts)가 있으면 그 아래로 비키고, 자리가 모자라면 배너가 잠깐 숨어요.
--   연출 칸을 누르면 바로 닫혀요 (화면의 다른 곳을 눌러도 안 닫혀요: 움직이면서 볼 수 있어요)
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local HatchFx = {}

type Job = { PetId: string, EggId: string, IsNew: boolean, Tier: number, Mode: string }
type Layout = { S: number, W: number, H: number, TitleH: number, CardH: number, HintH: number, X: number, Y: number, Small: boolean }

local gui: ScreenGui
local hostGui: Instance? = nil -- PlayerGui (메인 화면 PetWorldGui 에서 피할 것들을 찾아요)
local queue: { Job } = {}
local running = false
local activeSpin: RBXScriptConnection? = nil -- 연출 중 오류가 나도 끊을 수 있게 보관
local usedEggUids: { [string]: boolean } = {}

local CONFETTI_COLORS = { C.Pink, C.Lemon, C.Mint, C.Sky, C.Lavender, C.Peach, C.White }
local CARD_GAP = 6

function HatchFx.Init(playerGui: Instance)
	hostGui = playerGui
	gui = Make("ScreenGui", {
		Name = "HatchFxGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = false, -- 메인 화면과 같은 좌표 (옆 칸 자리 맞추기)
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	-- 새 스냅샷이 오면 "이미 쓴 알" 기록 초기화
	State.OnSync(function()
		table.clear(usedEggUids)
	end)
end

-- 어떤 알에서 나왔는지 추측 (부화 직전 스냅샷의 집 알 중 가장 먼저 부화하는 것)
local function guessEgg(petId: string): string
	local bestUid, bestId, bestAt = nil, nil, math.huge
	for uid, item in State.Items() do
		if item.Kind == "Egg" and item.Loc == "Slot" and not usedEggUids[uid] then
			local egg = Config.Eggs[item.Id]
			if egg and egg.Pets[petId] then
				local at = tonumber(item.HatchAt) or (math.huge - 1)
				if at < bestAt then
					bestUid, bestId, bestAt = uid, item.Id, at
				end
			end
		end
	end
	if bestUid and bestId then
		usedEggUids[bestUid] = true
		return bestId
	end
	local rarity = Config.Pets[petId].Rarity
	local fallback = nil
	for _, eggId in Config.EggOrder do
		local egg = Config.Eggs[eggId]
		if egg.Pets[petId] then
			if egg.Rarity == rarity then
				return eggId
			end
			fallback = fallback or eggId
		end
	end
	return fallback or "Basic"
end

local function worldBurst(position: Vector3, color: Color3)
	local att = Instance.new("Attachment")
	att.Name = "HatchBurst"
	att.Parent = workspace.Terrain
	att.WorldPosition = position + Vector3.new(0, 1.5, 0)
	local pe: ParticleEmitter = Make("ParticleEmitter", {
		Rate = 0,
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(12, 24),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -14, 0),
		Drag = 2,
		LightEmission = 0.7,
		LightInfluence = 0,
		Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.8, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-180, 180),
		Parent = att,
	})
	pe:Emit(30)
	Debris:AddItem(att, 3)
end

-- 색종이 (연출 칸 위에서 아래로만 떨어져요)
local function confetti(panel: GuiObject, stageSize: number, colors: { Color3 }?)
	local palette = if colors and #colors > 0 then colors else CONFETTI_COLORS
	local rng = Random.new()
	local unit = math.max(6, stageSize * 0.045)
	for _ = 1, 18 do
		task.delay(rng:NextNumber(0, 0.5), function()
			if not panel.Parent then
				return
			end
			local x = rng:NextNumber(0.02, 0.98)
			local piece: Frame = Make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, 0.02),
				Size = UDim2.fromOffset(math.floor(unit * rng:NextNumber(0.8, 1.2)), math.floor(unit * rng:NextNumber(1.2, 1.8))),
				Rotation = rng:NextNumber(0, 360),
				BackgroundColor3 = palette[rng:NextInteger(1, #palette)],
				ZIndex = 30,
				Parent = panel,
			})
			UiKit.Corner(piece, UDim.new(0, 3))
			local t = rng:NextNumber(1.3, 2.2)
			UiKit.Tween(piece, t, {
				Position = UDim2.fromScale(math.clamp(x + rng:NextNumber(-0.12, 0.12), 0, 1), 1),
				Rotation = piece.Rotation + rng:NextNumber(360, 900) * (if rng:NextNumber() < 0.5 then -1 else 1),
				BackgroundTransparency = 0.6,
			}, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
			Debris:AddItem(piece, t + 0.1)
		end)
	end
end

-- 가운데에서 사방으로 튀는 반짝이 (합성 순간)
local function sparkleBurst(stage: GuiObject, color: Color3)
	local rng = Random.new()
	for i = 1, 14 do
		local ang = (i / 14) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dist = rng:NextNumber(0.35, 0.6)
		local piece: Frame = Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.07, 0.07),
			Rotation = 45,
			BackgroundColor3 = if i % 2 == 0 then color else C.White,
			ZIndex = 7,
			Parent = stage,
		})
		UiKit.Corner(piece, UDim.new(0.3, 0))
		UiKit.Tween(piece, 0.55, {
			Position = UDim2.fromScale(0.5 + math.cos(ang) * dist, 0.5 + math.sin(ang) * dist),
			Size = UDim2.fromScale(0.015, 0.015),
			BackgroundTransparency = 1,
			Rotation = 45 + 180,
		}, Enum.EasingStyle.Quad)
		Debris:AddItem(piece, 0.6)
	end
end

-- 1) 알 흔들기 (부화)
local function eggStage(stage: GuiObject, job: Job, manyQueued: boolean)
	local eggHolder: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = stage,
	})
	UiKit.Viewport("Egg", job.EggId, eggHolder, false)
	UiKit.Pop(eggHolder, 0.35)
	task.wait(0.4)
	local eggScale = UiKit.Scale(eggHolder)
	UiKit.Tween(eggScale, 1.6, { Scale = 1.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local amps = if manyQueued
		then { 8, -8, 14, -14, 20, -20 }
		else { 5, -5, 7, -7, 10, -10, 13, -13, 16, -16, 20, -20, 24, -24 }
	for i, a in amps do
		local dt = math.max(0.06, 0.13 - i * 0.005)
		UiKit.Tween(eggHolder, dt, { Rotation = a }, Enum.EasingStyle.Sine)
		task.wait(dt)
	end
	eggHolder:Destroy()
end

-- 1') 펫 3마리가 가운데로 모여 합쳐지기 (합성)
local function fuseStage(stage: GuiObject, job: Job, manyQueued: boolean, color: Color3)
	local oldTier = math.max(1, job.Tier - 1)
	local holders: { Frame } = {}
	local xs = { 0.15, 0.5, 0.85 }
	for i = 1, Config.FuseCount do
		local x = xs[math.clamp(i, 1, #xs)]
		local holder: Frame = Make("Frame", {
			Name = "FusePet" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.fromScale(0.34, 0.34),
			BackgroundTransparency = 1,
			ZIndex = 6,
			Parent = stage,
		})
		UiKit.Viewport("Pet", job.PetId, holder, false, oldTier)
		table.insert(holders, holder)
		task.delay((i - 1) * 0.12, function()
			if holder.Parent then
				UiKit.Pop(holder, 0.35)
			end
		end)
	end
	-- 둥실둥실
	task.wait(if manyQueued then 0.45 else 0.8)
	for i, holder in holders do
		UiKit.Tween(holder, 0.25, { Position = UDim2.fromScale(xs[math.clamp(i, 1, #xs)], 0.44) }, Enum.EasingStyle.Sine)
	end
	task.wait(0.25)
	-- 가운데로 모이기
	local t = if manyQueued then 0.45 else 0.75
	for i, holder in holders do
		UiKit.Tween(holder, t, {
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.18, 0.18),
			Rotation = if i % 2 == 0 then 360 else -360,
		}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
	-- 모이는 동안 빛 고리
	local ring: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.1, 0.1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = stage,
	})
	UiKit.Corner(ring, UDim.new(0.5, 0))
	local ringStroke = UiKit.Stroke(ring, color, 6, true)
	UiKit.Tween(ring, t, { Size = UDim2.fromScale(0.9, 0.9) }, Enum.EasingStyle.Quad)
	UiKit.Tween(ringStroke, t, { Transparency = 1 }, Enum.EasingStyle.Quad)
	Debris:AddItem(ring, t + 0.1)
	task.wait(t)
	for _, holder in holders do
		holder:Destroy()
	end
	sparkleBurst(stage, color)
end

-- 연출 칸 크기: 무대(정사각형) S + 위 제목 + 아래 이름표 (+ 큰 화면은 "누르면 닫혀요")
-- narrow = 아주 작은 화면에서 코인 줄 오른쪽 빈칸에 맞추려고 좁게 (글자가 조금 작아져요)
local function measure(s: number, small: boolean, narrow: boolean?): (number, number, number, number, number)
	local titleH = math.max(if small then 22 else 28, math.floor(s * 0.17))
	local cardH = math.max(if small then 40 else 50, math.floor(s * 0.3))
	local hintH = if small then 0 else 22
	local w = if narrow
		then math.max(math.floor(s * 1.15), 120)
		else math.max(math.floor(s * 1.3), if small then 170 else 230)
	local h = titleH + s + CARD_GAP + cardH + (if hintH > 0 then hintH + 4 else 0)
	return w, h, titleH, cardH, hintH
end

local function mainGui(): Instance?
	local host = hostGui
	return if host then host:FindFirstChild("PetWorldGui") else nil
end

local function margin(small: boolean): number
	return if small then 10 else 16
end

local function prefY(gh: number, h: number): number
	return gh * 0.56 - h / 2 -- 가운데보다 조금 아래 (위쪽은 좋은 알 배너 자리)
end

-- 자리 찾기 (오른쪽 옆 칸), 먼저 되는 것:
-- 1) 오른쪽 끝, 좋은 알 배너도 비켜서  2) 오른쪽 끝 (배너는 잠깐 숨어요)  3) 오른쪽 끝에 좁게 (아주 작은 화면)
-- 4) 막은 것 왼쪽 (화면 오른쪽 1/3 안)  5) 4 + 좁게. 각각 무대를 조금씩 줄여 봐요 (폰 화면 높이 < 500 이면 무대 ~110px).
-- 다 안 되면 가장 덜 가리는 자리
local function findLayout(): Layout
	local size = gui.AbsoluteSize
	local gw, gh = math.max(size.X, 1), math.max(size.Y, 1)
	local small = gh < 500
	local s0 = math.clamp(math.floor(math.min(gw * 0.2, gh * 0.42)), 96, 300)
	local sizes: { number } = {}
	local s = s0
	while s >= 90 do
		table.insert(sizes, s)
		s = math.floor(s * 0.9)
	end
	local static = UiKit.SideObstacles(mainGui())
	local banner = UiKit.SideRect("Banner")
	type Mode = { Avoid: { UiKit.Rect }, Edge: boolean, Narrow: boolean }
	local modes: { Mode } = {}
	if banner then
		local withBanner = table.clone(static)
		table.insert(withBanner, banner)
		table.insert(modes, { Avoid = withBanner, Edge = true, Narrow = false })
	end
	table.insert(modes, { Avoid = static, Edge = true, Narrow = false })
	table.insert(modes, { Avoid = static, Edge = true, Narrow = true })
	table.insert(modes, { Avoid = static, Edge = false, Narrow = false })
	table.insert(modes, { Avoid = static, Edge = false, Narrow = true })
	local best: Layout? = nil
	local bestOv = math.huge
	for _, mode in modes do
		for _, size_ in sizes do
			local w, h, titleH, cardH, hintH = measure(size_, small, mode.Narrow)
			local x, y, ov = UiKit.SideSpot(gw, gh, w, h, prefY(gh, h), mode.Avoid, margin(small), mode.Edge)
			local layout: Layout = { S = size_, W = w, H = h, TitleH = titleH, CardH = cardH, HintH = hintH, X = x, Y = y, Small = small }
			if ov == 0 then
				return layout
			end
			if mode.Avoid == static and ov < bestOv then
				best, bestOv = layout, ov
			end
		end
	end
	return best :: Layout
end

local function showOne(job: Job)
	local def = Config.Pets[job.PetId]
	local rarity = (Config.Rarities :: any)[def.Rarity]
	local rc = UiKit.RarityColor(def.Rarity)
	local tier = job.Tier
	local tinfo = Config.TierInfo(tier)
	local isFuse = job.Mode == "Fuse"
	local tc = if tier >= 2 then UiKit.TierColor(tier) else rc -- 브론즈 이상이면 등급색으로 꾸며요
	local displayName = Config.PetDisplayName(job.PetId, tier)
	local manyQueued = #queue > 0 -- 뒤에 기다리는 연출이 있으면 짧게

	local L = findLayout()
	local S = L.S
	-- 입력을 막지 않는 Frame (모바일 조이스틱·점프가 계속 동작해야 함). 화면은 어둡게 하지 않아요
	local root: Frame = Make("Frame", {
		Name = if isFuse then "Fuse" else "Hatch",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	-- 옆 칸 (오른쪽에서 미끄러져 들어와요)
	local px, py = L.X, L.Y
	local panel: Frame = Make("Frame", {
		Name = "Panel",
		Active = false,
		Position = UDim2.fromOffset(gui.AbsoluteSize.X + 12, py),
		Size = UDim2.fromOffset(L.W, L.H),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = root,
	})
	local fit = 1 -- 나중에 창이 열려서 자리가 모자라면 칸을 통째로 작게 (UIScale)
	local fitScale: UIScale = Make("UIScale", { Name = "FitScale", Parent = panel })
	local function rectAt(x: number, y: number, k: number): UiKit.Rect
		return { X0 = x, Y0 = y, X1 = x + L.W * k, Y1 = y + L.H * k, Tag = "Hatch" }
	end
	local function panelRect(): UiKit.Rect
		return rectAt(px, py, fit)
	end
	UiKit.SetSideRect("Hatch", panelRect())
	UiKit.Tween(panel, 0.3, { Position = UDim2.fromOffset(px, py) }, Enum.EasingStyle.Back)

	-- 창이 열리거나 화면 크기가 바뀌어서 지금 자리가 무언가를 가리면 옮겨요 (필요하면 조금 작게)
	local watching = true
	task.spawn(function()
		while watching and panel.Parent do
			task.wait(0.3)
			if not watching or not panel.Parent then
				break
			end
			local size = gui.AbsoluteSize
			local avoid = UiKit.SideObstacles(mainGui())
			local here = panelRect()
			local curOv = UiKit.OverlapArea(here, avoid)
			if here.X0 < 0 or here.Y0 < 0 or here.X1 > size.X or here.Y1 > size.Y then
				curOv = math.huge
			end
			if curOv > 0 then
				local bx, by, bk, bov = px, py, fit, curOv
				for _, k in { 1, 0.9, 0.8, 0.7 } do
					for _, edgeOnly in { true, false } do
						local w, h = L.W * k, L.H * k
						local x, y, ov = UiKit.SideSpot(size.X, size.Y, w, h, prefY(size.Y, h), avoid, margin(L.Small), edgeOnly)
						if ov < bov then
							bx, by, bk, bov = x, y, k, ov
						end
					end
					if bov == 0 then
						break
					end
				end
				if bx ~= px or by ~= py or bk ~= fit then
					px, py, fit = bx, by, bk
					UiKit.SetSideRect("Hatch", panelRect())
					UiKit.Tween(panel, 0.25, { Position = UDim2.fromOffset(px, py) })
					UiKit.Tween(fitScale, 0.25, { Scale = fit })
				end
			end
		end
	end)

	-- 무대 (정사각형)
	local stage: Frame = Make("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, L.TitleH),
		Size = UDim2.fromOffset(S, S),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = panel,
	})
	-- 뒤에 부드러운 빛 동그라미 (화면을 어둡게 하는 대신: 알·펫이 바깥 풍경 위에서도 잘 보여요)
	local glow: Frame = Make("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.04, 1.04),
		BackgroundColor3 = UiKit.Lighten(tc, 0.7),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = stage,
	})
	UiKit.Corner(glow, UDim.new(0.5, 0))
	local glowStroke = UiKit.Stroke(glow, C.White, if L.Small then 3 else 4, true)
	glowStroke.Transparency = 1
	UiKit.Tween(glow, 0.3, { BackgroundTransparency = 0.35 })
	UiKit.Tween(glowStroke, 0.3, { Transparency = 0.3 })

	-- 빛줄기 (펫 나오면 보임)
	local rays: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.5, 1.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
		Parent = stage,
	})
	for i = 1, 8 do
		local ray: Frame = Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.09, 1),
			Rotation = i * 22.5,
			BackgroundColor3 = UiKit.Lighten(tc, 0.4),
			BackgroundTransparency = 0.6,
			ZIndex = 2,
			Parent = rays,
		})
		UiKit.Corner(ray, UDim.new(0.5, 0))
	end

	local title = UiKit.Label({
		Name = "Title",
		Text = if isFuse then "✨ 합성 중..." else "두근두근...",
		Size = UDim2.new(1, 0, 0, L.TitleH - 2),
		ZIndex = 8,
		Parent = panel,
	}, { StrokeThickness = if L.Small then 2 else 3, MaxText = 40 })

	-- 1) 알 흔들기 / 펫 모으기
	if isFuse then
		fuseStage(stage, job, manyQueued, tc)
	else
		eggStage(stage, job, manyQueued)
	end

	-- 2) 번쩍! (무대 안에서만: 화면 가운데는 그대로 보여요)
	local flash: Frame = Make("Frame", {
		Name = "Flash",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.25, 1.25),
		BackgroundColor3 = if isFuse then UiKit.Lighten(tc, 0.6) else Color3.new(1, 1, 1),
		BackgroundTransparency = 0.15,
		ZIndex = 50,
		Parent = stage,
	})
	UiKit.Corner(flash, UDim.new(0.5, 0))
	local flashScale = UiKit.Scale(flash)
	flashScale.Scale = 0.6
	UiKit.Tween(flashScale, 0.5, { Scale = 1.2 }, Enum.EasingStyle.Quad)
	UiKit.Tween(flash, 0.5, { BackgroundTransparency = 1 })
	Debris:AddItem(flash, 0.6)
	UiKit.PlaySound(if isFuse then "Buy" else "Hatch")

	-- 3) 펫 등장 (등급 반영)
	rays.Visible = true
	UiKit.Pop(rays, 0.5)
	local petHolder: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.92),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = stage,
	})
	local _, model = UiKit.Viewport("Pet", job.PetId, petHolder, false, tier)
	UiKit.Pop(petHolder, 0.55)
	local baseCf = if model then model:GetPivot() else nil
	local t0 = os.clock()
	local spin = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		rays.Rotation = t * 25
		if model and baseCf and model.Parent then
			model:PivotTo(baseCf * CFrame.Angles(0, t * 1.6, 0))
		end
	end)
	activeSpin = spin

	title.Text = if isFuse
		then (if tinfo.Label ~= "" then "✨ 합성 성공! " .. tinfo.Label else "✨ 합성 성공!")
		elseif tier >= 2 then tinfo.Label .. " 펫이 태어났어요!" -- 운 좋게 상위 등급으로 부화
		elseif job.IsNew then "새 친구가 태어났어요!"
		else "짜잔! 부화했어요!"
	UiKit.Bump(title, 0.3)

	-- 이름/등급/희귀도 이름표
	local card: Frame = Make("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, L.TitleH + S + CARD_GAP),
		Size = UDim2.fromOffset(L.W, L.CardH),
		BackgroundColor3 = tc,
		ZIndex = 9,
		Parent = panel,
	})
	UiKit.Corner(card, UDim.new(0.3, 0))
	UiKit.Gradient(card)
	UiKit.Stroke(card, C.White, if L.Small then 3 else 4, true)
	UiKit.Label({
		Name = "PetName",
		Text = displayName,
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.56),
		ZIndex = 10,
		Parent = card,
	}, { Stroke = UiKit.Darken(tc, 0.5), StrokeThickness = if L.Small then 2 else 3, MaxText = 44 })
	local tierText = if tinfo.Label ~= "" then tinfo.Label .. " · " else ""
	UiKit.Label({
		Name = "Info",
		Text = tierText .. "⭐ " .. (if rarity then rarity.Name else "") .. "   💰 " .. Config.FormatNumber(Config.PetIncome(job.PetId, tier)) .. "/초",
		Position = UDim2.fromScale(0.05, 0.6),
		Size = UDim2.fromScale(0.9, 0.32),
		ZIndex = 10,
		Parent = card,
	}, { Stroke = UiKit.Darken(tc, 0.5), MaxText = 24 })
	UiKit.Pop(card, 0.5)

	if job.IsNew then
		local badge: Frame = Make("Frame", {
			Name = "New",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.9, 0.12),
			Size = UDim2.fromScale(0.36, 0.16),
			Rotation = -14,
			BackgroundColor3 = C.Red,
			ZIndex = 12,
			Parent = stage,
		})
		UiKit.Corner(badge, UDim.new(0.4, 0))
		UiKit.Gradient(badge)
		UiKit.Stroke(badge, C.White, if L.Small then 3 else 4, true)
		UiKit.Label({ Text = "NEW!", Size = UDim2.fromScale(0.86, 0.76), Position = UDim2.fromScale(0.07, 0.12), ZIndex = 13, Parent = badge }, { Stroke = UiKit.Darken(C.Red, 0.5), StrokeThickness = if L.Small then 2 else 3, MaxText = 40 })
		task.delay(0.25, function()
			UiKit.Pop(badge, 0.45)
			task.wait(0.5)
			-- 통통 튀기
			local s = UiKit.Scale(badge)
			while badge.Parent do
				UiKit.Tween(s, 0.35, { Scale = 1.12 }, Enum.EasingStyle.Sine)
				task.wait(0.35)
				UiKit.Tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Sine)
				task.wait(0.35)
			end
		end)
	end

	-- 레인보우 이상은 등급 반짝이 색으로 색종이 (흰색 섞어서)
	local confettiColors: { Color3 }? = nil
	local visual = Config.TierVisual(tier)
	if tier >= 5 and visual and type(visual.ParticleColors) == "table" then
		local list: { Color3 } = { C.White }
		for _, color in visual.ParticleColors do
			if typeof(color) == "Color3" then
				table.insert(list, color)
			end
		end
		confettiColors = list
	end
	confetti(panel, S, confettiColors)

	if L.HintH > 0 then
		UiKit.Label({
			Name = "Hint",
			Text = "누르면 닫혀요",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 0, L.HintH),
			TextTransparency = 0.2,
			ZIndex = 8,
			Parent = panel,
		}, { MaxText = 18 })
	end

	-- 4) 연출 칸을 누르거나 시간이 지나면 닫기 (뒤에 기다리는 연출이 있으면 1초).
	--    누르는 칸은 연출 칸 안에만 있어요: 조이스틱·점프·화면 돌리기는 그대로
	local closed = false
	local revealAt = os.clock()
	Make("TextButton", {
		Name = "Tap",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
		Parent = panel,
	}).Activated:Connect(function()
		if os.clock() - revealAt > 0.3 then
			closed = true
		end
	end)
	local hold = if #queue > 0 then 1.0 else 3
	while not closed and os.clock() - revealAt < hold do
		task.wait()
	end

	watching = false
	UiKit.Tween(panel, 0.22, { Position = UDim2.fromOffset(gui.AbsoluteSize.X + 12, py) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UiKit.Tween(glow, 0.2, { BackgroundTransparency = 1 })
	task.wait(0.24)
	spin:Disconnect()
	activeSpin = nil
	UiKit.SetSideRect("Hatch", nil)
	root:Destroy()
end

local function runQueue()
	running = true
	while #queue > 0 do
		local job = table.remove(queue, 1)
		if job then
			local ok, err = pcall(showOne, job)
			if not ok then
				warn("[HatchFx]", err)
				if activeSpin then
					activeSpin:Disconnect()
					activeSpin = nil
				end
				UiKit.SetSideRect("Hatch", nil)
				for _, child in gui:GetChildren() do
					child:Destroy()
				end
			end
		end
	end
	running = false
end

-- mode: "Hatch"(기본) 또는 "Fuse". tier: 새 펫의 등급 1..7 (없으면 1)
function HatchFx.Play(petId: any, position: any, isNew: any, tier: any, mode: any)
	if type(petId) ~= "string" or not Config.Pets[petId] then
		return
	end
	local t = UiKit.TierOf(tier)
	local m = if mode == "Fuse" then "Fuse" else "Hatch"
	local color = if t >= 2 then UiKit.TierColor(t) else UiKit.RarityColor(Config.Pets[petId].Rarity)
	if typeof(position) == "Vector3" then
		worldBurst(position, color)
	end
	table.insert(queue, {
		PetId = petId,
		EggId = if m == "Hatch" then guessEgg(petId) else "",
		IsNew = isNew == true,
		Tier = t,
		Mode = m,
	})
	if not running then
		task.spawn(runQueue)
	end
end

return HatchFx
