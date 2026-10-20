-- 🐣 부화 연출: 화면 어둡게 → 알 흔들흔들 → 번쩍 → 펫 등장 + 빙글빙글 + 색종이
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local HatchFx = {}

type Job = { PetId: string, EggId: string, IsNew: boolean }

local gui: ScreenGui
local queue: { Job } = {}
local running = false
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

-- 어떤 알에서 나왔는지 추측 (부화 직전 스냅샷의 기지 알 중 가장 먼저 부화하는 것)
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

local function confetti(root: GuiObject)
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
				BackgroundColor3 = CONFETTI_COLORS[rng:NextInteger(1, #CONFETTI_COLORS)],
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

local function showOne(job: Job)
	local def = Config.Pets[job.PetId]
	local rarity = (Config.Rarities :: any)[def.Rarity]
	local rc = UiKit.RarityColor(def.Rarity)

	local root: TextButton = Make("TextButton", {
		Name = "Hatch",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 20, 65),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UiKit.Tween(root, 0.3, { BackgroundTransparency = 0.3 })

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
			BackgroundColor3 = UiKit.Lighten(rc, 0.4),
			BackgroundTransparency = 0.55,
			ZIndex = 2,
			Parent = rays,
		})
		UiKit.Corner(ray, UDim.new(0.5, 0))
	end

	local title = UiKit.Label({
		Text = "두근두근...",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.fromScale(1.2, 0.16),
		ZIndex = 8,
		Parent = stage,
	}, { StrokeThickness = 3, MaxText = 44 })

	-- 1) 알 흔들기
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
	local amps = { 5, -5, 7, -7, 10, -10, 13, -13, 16, -16, 20, -20, 24, -24 }
	for i, a in amps do
		local dt = math.max(0.06, 0.13 - i * 0.005)
		UiKit.Tween(eggHolder, dt, { Rotation = a }, Enum.EasingStyle.Sine)
		task.wait(dt)
	end

	-- 2) 번쩍!
	local flash: Frame = Make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		ZIndex = 50,
		Parent = root,
	})
	UiKit.Tween(flash, 0.6, { BackgroundTransparency = 1 })
	Debris:AddItem(flash, 0.7)
	eggHolder:Destroy()
	UiKit.PlaySound("Hatch")

	-- 3) 펫 등장
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
	local _, model = UiKit.Viewport("Pet", job.PetId, petHolder, false)
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

	title.Text = if job.IsNew then "새 친구가 태어났어요!" else "짜잔! 부화했어요!"
	UiKit.Bump(title, 0.3)

	-- 희귀도 배너
	local banner: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.fromScale(1.15, 0.28),
		BackgroundColor3 = rc,
		ZIndex = 9,
		Parent = stage,
	})
	UiKit.Corner(banner, UDim.new(0.3, 0))
	UiKit.Gradient(banner)
	UiKit.Stroke(banner, C.White, 4, true)
	UiKit.Label({
		Text = def.Name,
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.56),
		ZIndex = 10,
		Parent = banner,
	}, { Stroke = UiKit.Darken(rc, 0.5), StrokeThickness = 3, MaxText = 50 })
	UiKit.Label({
		Text = "⭐ " .. (if rarity then rarity.Name else "") .. " ⭐   💰 " .. Config.FormatNumber(def.Income) .. "/초",
		Position = UDim2.fromScale(0.05, 0.6),
		Size = UDim2.fromScale(0.9, 0.32),
		ZIndex = 10,
		Parent = banner,
	}, { Stroke = UiKit.Darken(rc, 0.5), MaxText = 28 })
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

	confetti(root)

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

	-- 4) 탭하거나 3초 뒤 닫기
	local closed = false
	local revealAt = os.clock()
	local conn = root.Activated:Connect(function()
		if os.clock() - revealAt > 0.4 then
			closed = true
		end
	end)
	while not closed and os.clock() - revealAt < 3 do
		task.wait()
	end
	conn:Disconnect()

	UiKit.Tween(UiKit.Scale(stage), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	UiKit.Tween(root, 0.25, { BackgroundTransparency = 1 })
	hint.Visible = false
	task.wait(0.26)
	spin:Disconnect()
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
				for _, child in gui:GetChildren() do
					child:Destroy()
				end
			end
		end
	end
	running = false
end

function HatchFx.Play(petId: any, position: any, isNew: any)
	if type(petId) ~= "string" or not Config.Pets[petId] then
		return
	end
	local rc = UiKit.RarityColor(Config.Pets[petId].Rarity)
	if typeof(position) == "Vector3" then
		worldBurst(position, rc)
	end
	table.insert(queue, { PetId = petId, EggId = guessEgg(petId), IsNew = isNew == true })
	if not running then
		task.spawn(runQueue)
	end
end

return HatchFx
