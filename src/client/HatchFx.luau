-- 🐣 부화 연출: 화면 어둡게 → 알 흔들흔들 → 번쩍 → 펫 등장 + 빙글빙글 + 색종이
-- ✨ 합성 연출(mode "Fuse"): 알 대신 작은 펫 3마리가 가운데로 모여 합쳐진 뒤 다음 등급 펫 등장
-- 등급 7단계 (기본 / 🥉 브론즈 / 🥈 실버 / 🥇 골드 / 🌈 레인보우 / 💎 다이아 / 🌌 갤럭시): 색·글자는 Config.Tiers
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local HatchFx = {}

type Job = { PetId: string, EggId: string, IsNew: boolean, Tier: number, Mode: string }

local gui: ScreenGui
local queue: { Job } = {}
local running = false
local activeSpin: RBXScriptConnection? = nil -- 연출 중 오류가 나도 끊을 수 있게 보관
local usedEggUids: { [string]: boolean } = {}

local CONFETTI_COLORS = { C.Pink, C.Lemon, C.Mint, C.Sky, C.Lavender, C.Peach, C.White }

function HatchFx.Init(playerGui: Instance)
	gui = Make("ScreenGui", {
		Name = "HatchFxGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
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

local function confetti(root: GuiObject, colors: { Color3 }?)
	local palette = if colors and #colors > 0 then colors else CONFETTI_COLORS
	local rng = Random.new()
	for _ = 1, 22 do
		task.delay(rng:NextNumber(0, 0.5), function()
			if not root.Parent then
				return
			end
			local x = rng:NextNumber(0.03, 0.97)
			local piece: Frame = Make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, -0.05),
				Size = UDim2.fromOffset(rng:NextInteger(10, 16), rng:NextInteger(14, 24)),
				Rotation = rng:NextNumber(0, 360),
				BackgroundColor3 = palette[rng:NextInteger(1, #palette)],
				ZIndex = 30,
				Parent = root,
			})
			UiKit.Corner(piece, UDim.new(0, 4))
			local t = rng:NextNumber(1.6, 2.8)
			UiKit.Tween(piece, t, {
				Position = UDim2.fromScale(x + rng:NextNumber(-0.15, 0.15), 1.08),
				Rotation = piece.Rotation + rng:NextNumber(360, 900) * (if rng:NextNumber() < 0.5 then -1 else 1),
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

local function showOne(job: Job)
	local def = Config.Pets[job.PetId]
	local rarity = (Config.Rarities :: any)[def.Rarity]
	local rc = UiKit.RarityColor(def.Rarity)
	local tier = job.Tier
	local tinfo = Config.TierInfo(tier)
	local isFuse = job.Mode == "Fuse"
	local tc = if tier >= 2 then UiKit.TierColor(tier) else rc -- 브론즈 이상이면 등급색으로 꾸며요
	local displayName = Config.PetDisplayName(job.PetId, tier)

	-- 입력을 막지 않는 Frame (모바일 조이스틱·점프가 계속 동작해야 함)
	local root: Frame = Make("Frame", {
		Name = if isFuse then "Fuse" else "Hatch",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 20, 65),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local manyQueued = #queue > 0 -- 뒤에 기다리는 연출이 있으면 짧게
	UiKit.Tween(root, 0.3, { BackgroundTransparency = 0.45 })

	-- 무대 (정사각형)
	local stage: Frame = Make("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.43),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = root,
	})
	Make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = stage })
	Make("UISizeConstraint", { MaxSize = Vector2.new(440, 440), Parent = stage })

	-- 빛줄기 (펫 나오면 보임)
	local rays: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.7, 1.7),
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
			BackgroundTransparency = 0.55,
			ZIndex = 2,
			Parent = rays,
		})
		UiKit.Corner(ray, UDim.new(0.5, 0))
	end

	local title = UiKit.Label({
		Text = if isFuse then "✨ 합성 중..." else "두근두근...",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.fromScale(1.2, 0.16),
		ZIndex = 8,
		Parent = stage,
	}, { StrokeThickness = 3, MaxText = 44 })

	-- 1) 알 흔들기 / 펫 모으기
	if isFuse then
		fuseStage(stage, job, manyQueued, tc)
	else
		eggStage(stage, job, manyQueued)
	end

	-- 2) 번쩍!
	local flash: Frame = Make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = if isFuse then UiKit.Lighten(tc, 0.6) else Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		ZIndex = 50,
		Parent = root,
	})
	UiKit.Tween(flash, 0.6, { BackgroundTransparency = 1 })
	Debris:AddItem(flash, 0.7)
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

	-- 이름/등급/희귀도 배너
	local banner: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.fromScale(1.15, 0.28),
		BackgroundColor3 = tc,
		ZIndex = 9,
		Parent = stage,
	})
	UiKit.Corner(banner, UDim.new(0.3, 0))
	UiKit.Gradient(banner)
	UiKit.Stroke(banner, C.White, 4, true)
	UiKit.Label({
		Text = displayName,
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.56),
		ZIndex = 10,
		Parent = banner,
	}, { Stroke = UiKit.Darken(tc, 0.5), StrokeThickness = 3, MaxText = 50 })
	local tierText = if tinfo.Label ~= "" then tinfo.Label .. " · " else ""
	UiKit.Label({
		Text = tierText .. "⭐ " .. (if rarity then rarity.Name else "") .. "   💰 " .. Config.FormatNumber(Config.PetIncome(job.PetId, tier)) .. "/초",
		Position = UDim2.fromScale(0.05, 0.6),
		Size = UDim2.fromScale(0.9, 0.32),
		ZIndex = 10,
		Parent = banner,
	}, { Stroke = UiKit.Darken(tc, 0.5), MaxText = 28 })
	UiKit.Pop(banner, 0.5)

	if job.IsNew then
		local badge: Frame = Make("Frame", {
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
		UiKit.Stroke(badge, C.White, 4, true)
		UiKit.Label({ Text = "NEW!", Size = UDim2.fromScale(0.86, 0.76), Position = UDim2.fromScale(0.07, 0.12), ZIndex = 13, Parent = badge }, { Stroke = UiKit.Darken(C.Red, 0.5), StrokeThickness = 3, MaxText = 40 })
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
	confetti(root, confettiColors)

	local hint = UiKit.Label({
		Text = "화면을 누르면 닫혀요",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0.6, 0, 0, 30),
		TextTransparency = 0.2,
		ZIndex = 8,
		Parent = root,
	}, { MaxText = 24 })
	hint.Visible = true

	-- 4) 탭/클릭하거나 시간이 지나면 닫기 (뒤에 기다리는 연출이 있으면 1초)
	local closed = false
	local revealAt = os.clock()
	local conn = UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) and os.clock() - revealAt > 0.4 then
			closed = true
		end
	end)
	local hold = if #queue > 0 then 1.0 else 3
	while not closed and os.clock() - revealAt < hold do
		task.wait()
	end
	conn:Disconnect()

	UiKit.Tween(UiKit.Scale(stage), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	UiKit.Tween(root, 0.25, { BackgroundTransparency = 1 })
	hint.Visible = false
	task.wait(0.26)
	spin:Disconnect()
	activeSpin = nil
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
