-- 컨베이어(알 공장 벨트): 알이 나와서 굴러가고, 프롬프트로 사요.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local PetModels = require(Shared.PetModels)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local ConveyorService = {}

local BELT_TOP = 1.2
local DROP_TIME = 0.7 -- 슈트에서 벨트로 떨어지는 시간
local DROP_HEIGHT = 9 -- 슈트 안에서 알이 나오는 높이
local FALL_TIME = 0.7 -- 끝에서 통 안으로 떨어지는 시간
local FLY_TIME = 0.9 -- 산 알이 기지로 날아가는 시간
local STRIPE_SPACING = 8
local BUY_DISTANCE = 20

type EggEntry = {
	Model: Model,
	EggId: string,
	Price: number,
	Born: number,
	Phase: number,
	Claimed: boolean,
	Done: boolean,
	Wobble: number,
}

local rng = Random.new()
local folder: Folder? = nil
local eggs: { EggEntry } = {}
local buyDebounce: { [Player]: number } = {}

-- 벨트 좌표계 (시작점 기준, -Z 가 진행 방향)
local startPos = Config.Layout.ConveyorStart
local endPos = Config.Layout.ConveyorEnd
local beltLength = (endPos - startPos).Magnitude
local beltDir = (endPos - startPos).Unit
local beltBase = CFrame.lookAt(startPos, startPos + beltDir)
local speed = beltLength / Config.Conveyor.TravelTime

local function notify(player: Player, text: string, kind: string)
	Remotes.Notify:FireClient(player, text, kind)
end

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- 벨트 위 거리 s, 높이 y 의 CFrame
local function beltCFrame(s: number, y: number): CFrame
	return beltBase * CFrame.new(0, y, -s)
end

----------------------------------------------------------------------
-- 벨트 만들기
----------------------------------------------------------------------
local stripes: { BasePart } = {}

local function buildBelt(root: Folder)
	local beltFolder = Instance.new("Folder")
	beltFolder.Name = "Belt"
	beltFolder.Parent = root

	local W = Config.Layout.ConveyorWidth
	local L = beltLength

	-- 받침 프레임
	makePart({
		Name = "Frame",
		Size = Vector3.new(W + 1.2, 0.9, L + 1),
		CFrame = beltCFrame(L / 2, 0.45),
		Color = Color3.fromRGB(150, 170, 210),
		Parent = beltFolder,
	})
	-- 벨트 (진짜로 위에 선 사람을 실어 날라요!)
	local top = makePart({
		Name = "BeltTop",
		Size = Vector3.new(W, 0.3, L),
		CFrame = beltCFrame(L / 2, BELT_TOP - 0.15),
		Color = Color3.fromRGB(55, 58, 75),
		Material = Enum.Material.Fabric,
		Parent = beltFolder,
	})
	top.AssemblyLinearVelocity = beltDir * speed

	-- 옆 난간 (보기용, 통과 가능)
	local railColors = { Color3.fromRGB(255, 140, 190), Color3.fromRGB(110, 210, 230) }
	for i, side in { -1, 1 } do
		makePart({
			Name = "Rail",
			Size = Vector3.new(0.5, 0.5, L),
			CFrame = beltCFrame(L / 2, BELT_TOP + 0.35) * CFrame.new(side * (W / 2 + 0.3), 0, 0),
			Color = railColors[i],
			CanCollide = false,
			Parent = beltFolder,
		})
		-- 난간 기둥
		local posts = math.floor(L / 12)
		for k = 0, posts do
			makePart({
				Name = "Post",
				Size = Vector3.new(0.4, 0.9, 0.4),
				CFrame = beltCFrame(k * (L / posts), BELT_TOP - 0.1) * CFrame.new(side * (W / 2 + 0.3), 0, 0),
				Color = Color3.fromRGB(255, 255, 255),
				CanCollide = false,
				Parent = beltFolder,
			})
		end
	end

	-- 양 끝 롤러
	for _, s in { 0, L } do
		makePart({
			Name = "Roller",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(W + 0.4, 1.3, 1.3),
			CFrame = beltCFrame(s, BELT_TOP - 0.6),
			Color = Color3.fromRGB(255, 210, 80),
			CanCollide = false,
			Parent = beltFolder,
		})
	end

	-- 움직이는 줄무늬 (네온)
	local stripeColors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(140, 230, 255), Color3.fromRGB(255, 160, 210) }
	local count = math.floor(L / STRIPE_SPACING)
	for i = 1, count do
		local stripe = makePart({
			Name = "Stripe",
			Size = Vector3.new(W - 1.2, 0.06, 0.8),
			CFrame = beltCFrame((i - 1) * STRIPE_SPACING, BELT_TOP + 0.02),
			Color = stripeColors[(i - 1) % #stripeColors + 1],
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Parent = beltFolder,
		})
		table.insert(stripes, stripe)
	end

	-- 시작점 알 슈트
	local chuteFolder = Instance.new("Model")
	chuteFolder.Name = "Chute"
	chuteFolder.Parent = beltFolder
	local cw = 5
	local chuteBottom = BELT_TOP + 3.6
	local chuteTop = DROP_HEIGHT + 3
	local chuteH = chuteTop - chuteBottom
	local chuteCenter = beltCFrame(0, chuteBottom + chuteH / 2)
	local chuteColor = Color3.fromRGB(255, 190, 220)
	for _, off in { Vector3.new(cw / 2, 0, 0), Vector3.new(-cw / 2, 0, 0), Vector3.new(0, 0, cw / 2), Vector3.new(0, 0, -cw / 2) } do
		local isX = off.X ~= 0
		makePart({
			Name = "ChuteWall",
			Size = if isX then Vector3.new(0.4, chuteH, cw) else Vector3.new(cw, chuteH, 0.4),
			CFrame = chuteCenter * CFrame.new(off),
			Color = chuteColor,
			Material = Enum.Material.Glass,
			Transparency = 0.45,
			CanCollide = false,
			Parent = chuteFolder,
		})
	end
	makePart({
		Name = "ChuteCap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(cw + 1.5, cw + 1.5, cw + 1.5),
		CFrame = beltCFrame(0, chuteTop + 0.6),
		Color = Color3.fromRGB(255, 120, 170),
		CanCollide = false,
		Parent = chuteFolder,
	})
	-- 슈트 다리
	for _, off in { Vector3.new(cw / 2, 0, cw / 2), Vector3.new(-cw / 2, 0, cw / 2), Vector3.new(cw / 2, 0, -cw / 2), Vector3.new(-cw / 2, 0, -cw / 2) } do
		makePart({
			Name = "ChuteLeg",
			Size = Vector3.new(0.4, chuteBottom - BELT_TOP + 0.2, 0.4),
			CFrame = beltCFrame(0, (BELT_TOP + chuteBottom) / 2) * CFrame.new(off),
			Color = Color3.fromRGB(255, 255, 255),
			CanCollide = false,
			Parent = chuteFolder,
		})
	end

	-- 끝 알 통
	local bin = Instance.new("Model")
	bin.Name = "Bin"
	bin.Parent = beltFolder
	local binLen = 5.5
	local binW = W + 1
	local binH = 1.1
	local binCenter = beltCFrame(L + binLen / 2 + 0.3, 0)
	makePart({
		Name = "BinFloor",
		Size = Vector3.new(binW, 0.2, binLen),
		CFrame = binCenter * CFrame.new(0, 0.1, 0),
		Color = Color3.fromRGB(120, 200, 255),
		Parent = bin,
	})
	for _, data in {
		{ Vector3.new(binW / 2, binH / 2, 0), Vector3.new(0.4, binH, binLen) },
		{ Vector3.new(-binW / 2, binH / 2, 0), Vector3.new(0.4, binH, binLen) },
		{ Vector3.new(0, binH / 2, -binLen / 2), Vector3.new(binW, binH, 0.4) },
	} do
		makePart({
			Name = "BinWall",
			Size = data[2],
			CFrame = binCenter * CFrame.new(data[1]),
			Color = Color3.fromRGB(90, 170, 240),
			Parent = bin,
		})
	end
end

local function animateStripes(now: number)
	if #stripes == 0 then
		return
	end
	local span = #stripes * STRIPE_SPACING
	local offset = (now * speed * span / beltLength) % span
	local cfs = table.create(#stripes)
	for i = 1, #stripes do
		local s = ((i - 1) * STRIPE_SPACING + offset) % span
		cfs[i] = beltCFrame(s * (beltLength / span), BELT_TOP + 0.02)
	end
	workspace:BulkMoveTo(stripes, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

----------------------------------------------------------------------
-- 알
----------------------------------------------------------------------
local function buildEggModel(eggId: string): Model
	local ok, model = pcall(PetModels.BuildEgg, eggId)
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		return model
	end
	warn("[ConveyorService] BuildEgg 실패:", model)
	-- 대체 모델
	local m = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2.4, 2.4, 2.4)
	body.Color = Config.Rarities[Config.Eggs[eggId].Rarity].Color
	body.CanCollide = false
	body.Parent = m
	m.PrimaryPart = body
	m.WorldPivot = body.CFrame * CFrame.new(0, -1.2, 0)
	return m
end

local function getMainPart(model: Model): BasePart?
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function makeBillboard(adornee: BasePart, egg: any, price: number)
	local rarity = Config.Rarities[egg.Rarity]
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggInfo"
	gui.Adornee = adornee
	gui.Size = UDim2.new(7, 0, 3, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local function label(text: string, color: Color3, y: number, h: number)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, h, 0)
		l.Position = UDim2.new(0, 0, y, 0)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.2
		l.TextStrokeColor3 = Color3.fromRGB(40, 30, 60)
		l.Parent = gui
		return l
	end
	label(egg.Name, rarity.Color, 0, 0.4)
	label("💰 " .. Config.FormatNumber(price), Color3.fromRGB(255, 225, 90), 0.4, 0.33)
	label(rarity.Name, rarity.Color, 0.73, 0.27)
	gui.Parent = adornee
end

local function removeEntry(entry: EggEntry)
	local i = table.find(eggs, entry)
	if i then
		table.remove(eggs, i)
	end
end

local function flyToSlot(model: Model, player: Player, uid: string, target: CFrame)
	task.spawn(function()
		local from = model:GetPivot()
		local p0 = from.Position
		local p2 = target.Position
		local p1 = (p0 + p2) / 2 + Vector3.new(0, math.max(10, (p2 - p0).Magnitude * 0.35), 0)
		local t0 = os.clock()
		while true do
			local a = math.clamp((os.clock() - t0) / FLY_TIME, 0, 1)
			if model.Parent == nil then
				break
			end
			local u = 1 - a
			local pos = p0 * (u * u) + p1 * (2 * u * a) + p2 * (a * a)
			local rot = target.Rotation * CFrame.Angles(0, (1 - a) * math.pi * 4, 0)
			model:PivotTo(CFrame.new(pos) * rot)
			if a >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		model:Destroy()
		-- 날아가는 동안 상황이 바뀌었을 수 있으니 다시 확인
		if player.Parent == nil then
			return
		end
		local item = DataService.GetItem(player, uid)
		if item and item.Loc == "Slot" then
			PlotService.PlaceItem(player, uid)
		end
	end)
end

local function onBuy(entry: EggEntry, player: Player)
	if entry.Claimed or entry.Done or entry.Phase >= 3 then
		return
	end
	local now = os.clock()
	if (buyDebounce[player] or 0) > now then
		return
	end
	buyDebounce[player] = now + 0.3

	if not DataService.Get(player) then
		return
	end
	if not PlotService.GetPlot(player) then
		notify(player, "아직 내 기지가 없어요!", "warn")
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local main = getMainPart(entry.Model)
	if not (hrp and hrp:IsA("BasePart") and main) then
		return
	end
	if (hrp.Position - main.Position).Magnitude > BUY_DISTANCE then
		return
	end

	local egg = Config.Eggs[entry.EggId]
	local slot = PlotService.FreeSlot(player)
	if not slot then
		notify(player, "기지에 빈 자리가 없어요!", "warn")
		return
	end
	if not DataService.TrySpend(player, entry.Price) then
		notify(player, "코인이 부족해요! 💰 " .. Config.FormatNumber(entry.Price) .. " 필요", "warn")
		return
	end

	-- 여기부터는 이 알은 이 플레이어 것 (중간에 yield 없음)
	entry.Claimed = true
	entry.Done = true
	removeEntry(entry)

	local uid = DataService.AddItem(player, {
		Kind = "Egg",
		Id = entry.EggId,
		Loc = "Slot",
		Slot = slot,
		HatchAt = os.time() + egg.HatchTime,
	})
	if not uid or uid == "" then
		-- 혹시 실패하면 환불
		DataService.AddCoins(player, entry.Price)
		entry.Model:Destroy()
		DataService.Sync(player)
		return
	end

	local model = entry.Model
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	local target = PlotService.GetSlotCFrame(player, slot)
	flyToSlot(model, player, uid, target)

	notify(player, "알을 샀어요! 기지에서 부화를 기다려요 🥚", "good")
	DataService.Sync(player)
end

local function spawnEgg()
	if not folder or #eggs >= Config.Conveyor.MaxEggs then
		return
	end
	local eggId = Config.RollEgg(rng)
	local egg = Config.Eggs[eggId]
	local rarity = Config.Rarities[egg.Rarity]
	local price = egg.Price

	local model = buildEggModel(eggId)
	model.Name = "ConveyorEgg_" .. eggId
	model:SetAttribute("EggId", eggId)
	model:SetAttribute("Price", price)

	local main = getMainPart(model)
	if not main then
		model:Destroy()
		return
	end
	-- 몸통만 앵커 (나머지는 WeldConstraint 로 따라와요). 매 프레임 움직일 때 몸통 CFrame 하나만 복제돼서 가벼워요.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == main
			d.CanCollide = false
			d.CanTouch = false
		end
	end

	if rarity.Order >= 4 then
		pcall(PetModels.AddRarityEffects, model, egg.Rarity)
	end

	makeBillboard(main, egg, price)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "구매 💰" .. Config.FormatNumber(price)
	prompt.ObjectText = egg.Name
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("PromptKind", "Buy")
	prompt.Parent = main

	local entry: EggEntry = {
		Model = model,
		EggId = eggId,
		Price = price,
		Born = os.clock(),
		Phase = 1,
		Claimed = false,
		Done = false,
		Wobble = rng:NextNumber() * 10,
	}
	prompt.Triggered:Connect(function(player)
		onBuy(entry, player)
	end)

	model:PivotTo(beltCFrame(0, DROP_HEIGHT))
	model.Parent = folder
	table.insert(eggs, entry)

	if egg.Rarity == "Legendary" or egg.Rarity == "Mythic" then
		Remotes.Notify:FireAllClients("✨ " .. egg.Name .. "이 나타났어요!", "info")
	end
end

-- 모든 알을 한 번에 움직여요
local function updateEggs(now: number)
	local travel = Config.Conveyor.TravelTime
	for i = #eggs, 1, -1 do
		local e = eggs[i]
		local t = now - e.Born
		local s, y
		if t < DROP_TIME then
			-- 슈트에서 톡 떨어지기
			local a = t / DROP_TIME
			s = 0
			y = DROP_HEIGHT + (BELT_TOP - DROP_HEIGHT) * (a * a)
		elseif t < DROP_TIME + travel then
			e.Phase = 2
			s = (t - DROP_TIME) * speed
			y = BELT_TOP
		elseif t < DROP_TIME + travel + FALL_TIME then
			if e.Phase < 3 then
				e.Phase = 3
				local prompt = e.Model:FindFirstChildWhichIsA("ProximityPrompt", true)
				if prompt then
					prompt.Enabled = false
				end
			end
			local ft = t - DROP_TIME - travel
			s = beltLength + ft * speed
			y = BELT_TOP - 1.4 * (ft / FALL_TIME) ^ 2
		else
			e.Done = true
			table.remove(eggs, i)
			e.Model:Destroy()
			continue
		end
		local phase = e.Wobble
		local wobble = CFrame.Angles(0, now * 0.8 + phase, 0) * CFrame.Angles(math.sin(now * 5 + phase) * 0.07, 0, math.sin(now * 4 + phase) * 0.1)
		e.Model:PivotTo(beltCFrame(s, y) * wobble)
	end
end

function ConveyorService.Start()
	local old = workspace:FindFirstChild("Conveyor")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Conveyor"
	folder = root
	buildBelt(root)
	root.Parent = workspace

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		buyDebounce[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		animateStripes(now)
		updateEggs(now)
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(spawnEgg)
			if not ok then
				warn("[ConveyorService] 알 생성 오류:", err)
			end
			task.wait(Config.Conveyor.SpawnInterval)
		end
	end)
end

return ConveyorService
