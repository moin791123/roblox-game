-- 컨베이어(알 공장 벨트): 지역마다 벨트 1개 (workspace.Conveyors.Zone<k>), 그 지역 알 2종만 나와요.
-- 그 지역이 열린 사람이 접속해 있을 때만 알이 나오고 (숲 마을은 항상), 지역이 잠긴 사람은 못 사요.
-- 산 알은 집 받침대로 날아가요. 집이 아주 멀면 "뿅" 하고 사라졌다가 받침대에 바로 나타나요.
-- 벨트 줄무늬 애니메이션은 클라이언트(ZoneClient)가 해요 (서버 복제 줄이기).
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
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
local FLY_TIME = 0.9 -- 산 알이 집으로 날아가는 시간 (가까울 때)
local FLY_TIME_MAX = 1.8
local STRIPE_SPACING = 8
local BUY_DISTANCE = 20
local WATCH_DISTANCE = 260 -- 이 안에 사람이 있는 벨트만 알을 매 프레임 움직여요
local ANNOUNCE_GAP = 45 -- 좋은 알 등장 알림 간격 (벨트마다)

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

type Belt = {
	Zone: number,
	Folder: Folder,
	Start: Vector3,
	Dir: Vector3,
	Length: number,
	Base: CFrame,
	Speed: number,
	Center: Vector3,
	Eggs: { EggEntry },
	Active: boolean, -- 알이 나오는지 (지역이 열린 사람이 접속 중)
	Watched: boolean, -- 근처에 사람이 있는지
	NextSpawn: number,
	LastAnnounce: number,
}

local rng = Random.new()
local belts: { Belt } = {}
local buyDebounce: { [Player]: number } = {}
local started = false

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
local function beltCFrame(belt: Belt, s: number, y: number): CFrame
	return belt.Base * CFrame.new(0, y, -s)
end

----------------------------------------------------------------------
-- 벨트 만들기
----------------------------------------------------------------------
local function buildBelt(belt: Belt)
	local beltFolder = Instance.new("Folder")
	beltFolder.Name = "Belt"
	-- ZoneClient 가 줄무늬를 움직일 때 쓰는 값
	beltFolder:SetAttribute("Start", belt.Start)
	beltFolder:SetAttribute("Dir", belt.Dir)
	beltFolder:SetAttribute("Length", belt.Length)
	beltFolder:SetAttribute("Speed", belt.Speed)
	beltFolder:SetAttribute("StripeSpacing", STRIPE_SPACING)
	beltFolder:SetAttribute("StripeY", BELT_TOP + 0.02)
	beltFolder.Parent = belt.Folder

	local W = Config.Layout.ConveyorWidth
	local L = belt.Length

	-- 받침 프레임
	makePart({
		Name = "Frame",
		Size = Vector3.new(W + 1.2, 0.9, L + 1),
		CFrame = beltCFrame(belt, L / 2, 0.45),
		Color = Color3.fromRGB(150, 170, 210),
		Parent = beltFolder,
	})
	-- 벨트 (진짜로 위에 선 사람을 실어 날라요!)
	local top = makePart({
		Name = "BeltTop",
		Size = Vector3.new(W, 0.3, L),
		CFrame = beltCFrame(belt, L / 2, BELT_TOP - 0.15),
		Color = Color3.fromRGB(55, 58, 75),
		Material = Enum.Material.Fabric,
		Parent = beltFolder,
	})
	top.AssemblyLinearVelocity = belt.Dir * belt.Speed

	-- 옆 난간 (보기용, 통과 가능)
	local railColors = { Color3.fromRGB(255, 140, 190), Color3.fromRGB(110, 210, 230) }
	for i, side in { -1, 1 } do
		makePart({
			Name = "Rail",
			Size = Vector3.new(0.5, 0.5, L),
			CFrame = beltCFrame(belt, L / 2, BELT_TOP + 0.35) * CFrame.new(side * (W / 2 + 0.3), 0, 0),
			Color = railColors[i],
			CanCollide = false,
			Parent = beltFolder,
		})
		local posts = math.floor(L / 20)
		for k = 0, posts do
			makePart({
				Name = "Post",
				Size = Vector3.new(0.4, 0.9, 0.4),
				CFrame = beltCFrame(belt, k * (L / posts), BELT_TOP - 0.1) * CFrame.new(side * (W / 2 + 0.3), 0, 0),
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
			CFrame = beltCFrame(belt, s, BELT_TOP - 0.6),
			Color = Color3.fromRGB(255, 210, 80),
			CanCollide = false,
			Parent = beltFolder,
		})
	end

	-- 줄무늬 (네온). 움직이는 건 클라이언트가 해요
	local stripeColors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(140, 230, 255), Color3.fromRGB(255, 160, 210) }
	local count = math.floor(L / STRIPE_SPACING)
	for i = 1, count do
		local stripe = makePart({
			Name = "Stripe",
			Size = Vector3.new(W - 1.2, 0.06, 0.8),
			CFrame = beltCFrame(belt, (i - 1) * STRIPE_SPACING, BELT_TOP + 0.02),
			Color = stripeColors[(i - 1) % #stripeColors + 1],
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Parent = beltFolder,
		})
		stripe:SetAttribute("StripeIndex", i)
	end

	-- 시작점 알 슈트
	local chute = Instance.new("Model")
	chute.Name = "Chute"
	chute.Parent = beltFolder
	local cw = 5
	local chuteBottom = BELT_TOP + 3.6
	local chuteTop = DROP_HEIGHT + 3
	local chuteH = chuteTop - chuteBottom
	local chuteCenter = beltCFrame(belt, 0, chuteBottom + chuteH / 2)
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
			Parent = chute,
		})
	end
	makePart({
		Name = "ChuteCap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(cw + 1.5, cw + 1.5, cw + 1.5),
		CFrame = beltCFrame(belt, 0, chuteTop + 0.6),
		Color = Color3.fromRGB(255, 120, 170),
		CanCollide = false,
		Parent = chute,
	})
	for _, off in { Vector3.new(cw / 2, 0, cw / 2), Vector3.new(-cw / 2, 0, cw / 2), Vector3.new(cw / 2, 0, -cw / 2), Vector3.new(-cw / 2, 0, -cw / 2) } do
		makePart({
			Name = "ChuteLeg",
			Size = Vector3.new(0.4, chuteBottom - BELT_TOP + 0.2, 0.4),
			CFrame = beltCFrame(belt, 0, (BELT_TOP + chuteBottom) / 2) * CFrame.new(off),
			Color = Color3.fromRGB(255, 255, 255),
			CanCollide = false,
			Parent = chute,
		})
	end

	-- 끝 알 통
	local bin = Instance.new("Model")
	bin.Name = "Bin"
	bin.Parent = beltFolder
	local binLen = 5.5
	local binW = W + 1
	local binH = 1.1
	local binCenter = beltCFrame(belt, L + binLen / 2 + 0.3, 0)
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

----------------------------------------------------------------------
-- 알
----------------------------------------------------------------------
local function buildEggModel(eggId: string): Model
	local ok, model = pcall(PetModels.BuildEgg, eggId)
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		return model
	end
	warn("[ConveyorService] BuildEgg 실패:", model)
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
	local premium = egg.Premium == true
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggInfo"
	gui.Adornee = adornee
	-- 비싼 알은 간판도 커요
	gui.Size = if premium then UDim2.new(9, 0, 4, 0) else UDim2.new(7, 0, 3, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if premium then 3.8 else 3.2, 0)
	gui.MaxDistance = if premium then 120 else 90
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
	label(if premium then "✨ " .. egg.Name .. " ✨" else egg.Name, rarity.Color, 0, 0.4)
	label("💰 " .. Config.FormatNumber(price), Color3.fromRGB(255, 225, 90), 0.4, 0.33)
	label(rarity.Name, rarity.Color, 0.73, 0.27)
	gui.Parent = adornee
end

-- 비싼 알 반짝임 (빛 + 반짝이)
local function addPremiumGlow(main: BasePart, egg: any)
	local color = Config.Rarities[egg.Rarity].Color
	local light = Instance.new("PointLight")
	light.Name = "PremiumGlow"
	light.Color = color
	light.Brightness = 1.6
	light.Range = 9
	light.Parent = main
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "PremiumSparkle"
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparkle.LightEmission = 0.8
	sparkle.Size = NumberSequence.new(0.5, 0)
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Speed = NumberRange.new(1, 2.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 6
	sparkle.Parent = main
end

local function removeEntry(belt: Belt, entry: EggEntry)
	local i = table.find(belt.Eggs, entry)
	if i then
		table.remove(belt.Eggs, i)
	end
end

-- 잠깐 반짝 터지는 효과 (보이지 않는 파트 + 파티클 한 번)
local function poofAt(pos: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Name = "EggPoof"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.LightEmission = 0.7
	e.Size = NumberSequence.new(0.9, 0)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(6, 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(24)
	Debris:AddItem(p, 1.5)
end

local function placeIfStillThere(player: Player, uid: string)
	if player.Parent == nil then
		return
	end
	local item = DataService.GetItem(player, uid)
	if item and item.Loc == "Slot" then
		PlotService.PlaceItem(player, uid)
	end
end

local function flyToSlot(model: Model, player: Player, uid: string, target: CFrame)
	task.spawn(function()
		local from = model:GetPivot()
		local p0 = from.Position
		local p2 = target.Position
		local dist = (p2 - p0).Magnitude
		local p1 = (p0 + p2) / 2 + Vector3.new(0, math.max(10, dist * 0.35), 0)
		local flyTime = math.clamp(FLY_TIME + dist / 500, FLY_TIME, FLY_TIME_MAX)
		local t0 = os.clock()
		while true do
			local a = math.clamp((os.clock() - t0) / flyTime, 0, 1)
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
		placeIfStillThere(player, uid)
	end)
end

-- 너무 먼 집: 그 자리에서 뿅! 하고 받침대에 바로 나타나요
local function poofToSlot(model: Model, player: Player, uid: string, target: CFrame, color: Color3)
	poofAt(model:GetPivot().Position + Vector3.new(0, 1.5, 0), color)
	model:Destroy()
	placeIfStillThere(player, uid)
	poofAt(target.Position + Vector3.new(0, 1.5, 0), color)
end

local function onBuy(belt: Belt, entry: EggEntry, player: Player)
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
		notify(player, "아직 내 집이 없어요! 🏠", "warn")
		return
	end
	local egg = Config.Eggs[entry.EggId]
	local rebirths = DataService.GetRebirths(player)
	local zone = Config.EggZone(entry.EggId)
	if not Config.ZoneUnlocked(zone, rebirths) then
		notify(player, "🔒 환생 " .. Config.Zones[zone].MinRebirth .. "회가 필요해요!", "warn")
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

	-- 빈 받침대 먼저 확인하고 돈을 빼요 (반대 순서면 돈만 빠질 수 있어요)
	local slot = PlotService.FreeSlot(player)
	if not slot then
		notify(player, "집에 빈 받침대가 없어요! 🏠", "warn")
		return
	end
	if not DataService.TrySpend(player, entry.Price) then
		notify(player, "코인이 부족해요! 💰 " .. Config.FormatNumber(entry.Price) .. " 필요", "warn")
		return
	end

	-- 여기부터는 이 알은 이 플레이어 것 (중간에 yield 없음)
	entry.Claimed = true
	entry.Done = true
	removeEntry(belt, entry)

	local uid = DataService.AddItem(player, {
		Kind = "Egg",
		Id = entry.EggId,
		Loc = "Slot",
		Slot = slot,
		HatchAt = os.time() + Config.RebirthHatchTime(entry.EggId, rebirths), -- 환생할수록 빨리 부화
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
	if (target.Position - main.Position).Magnitude <= Config.Conveyor.FlyMaxDistance then
		flyToSlot(model, player, uid, target)
		notify(player, "알을 샀어요! 집에서 부화를 기다려요 🥚", "good")
	else
		poofToSlot(model, player, uid, target, Config.Rarities[egg.Rarity].Color)
		notify(player, "✨ 뿅! 알이 집 받침대로 갔어요 🥚", "good")
	end
	DataService.Sync(player)
end

local function spawnEgg(belt: Belt)
	if #belt.Eggs >= Config.Conveyor.MaxEggs then
		return
	end
	local eggId = Config.RollEgg(rng, belt.Zone)
	local egg = Config.Eggs[eggId]
	if not egg then
		return
	end
	local rarity = Config.Rarities[egg.Rarity]
	local price = egg.Price

	local model = buildEggModel(eggId)
	model.Name = "ConveyorEgg_" .. eggId
	model:SetAttribute("EggId", eggId)
	model:SetAttribute("Price", price)
	model:SetAttribute("Zone", belt.Zone)

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
	if egg.Premium then
		addPremiumGlow(main, egg)
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
		onBuy(belt, entry, player)
	end)

	model:PivotTo(beltCFrame(belt, 0, DROP_HEIGHT))
	model.Parent = belt.Folder
	table.insert(belt.Eggs, entry)

	-- 좋은 알 등장 알림: 그 지역에 있는 사람한테만, 가끔
	local now = os.clock()
	if egg.Premium and rarity.Order >= 5 and now - belt.LastAnnounce >= ANNOUNCE_GAP then
		belt.LastAnnounce = now
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Zone") == belt.Zone then
				notify(player, "✨ " .. egg.Name .. "이 나타났어요!", "info")
			end
		end
	end
end

-- 벨트 하나의 알을 한 번에 움직여요 (근처에 아무도 없으면 시간만 세고 움직이진 않아요)
local function updateEggs(belt: Belt, now: number)
	local travel = Config.Conveyor.TravelTime
	local eggs = belt.Eggs
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
			s = (t - DROP_TIME) * belt.Speed
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
			s = belt.Length + ft * belt.Speed
			y = BELT_TOP - 1.4 * (ft / FALL_TIME) ^ 2
		else
			e.Done = true
			table.remove(eggs, i)
			e.Model:Destroy()
			continue
		end
		if belt.Watched then
			local phase = e.Wobble
			local wobble = CFrame.Angles(0, now * 0.8 + phase, 0)
				* CFrame.Angles(math.sin(now * 5 + phase) * 0.07, 0, math.sin(now * 4 + phase) * 0.1)
			e.Model:PivotTo(beltCFrame(belt, s, y) * wobble)
		end
	end
end

-- 벨트마다: 알이 나와도 되는지 / 근처에 사람이 있는지
local function refreshBeltStates()
	local players = Players:GetPlayers()
	for _, belt in belts do
		local active = belt.Zone == 1
		local watched = false
		local minRebirth = Config.Zones[belt.Zone].MinRebirth
		for _, player in players do
			if not active and DataService.Get(player) and DataService.GetRebirths(player) >= minRebirth then
				active = true
			end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local d = hrp.Position - belt.Center
				if d.X * d.X + d.Z * d.Z <= WATCH_DISTANCE * WATCH_DISTANCE then
					watched = true
				end
			end
		end
		if active and not belt.Active then
			belt.NextSpawn = os.clock() + rng:NextNumber(0, Config.Conveyor.SpawnInterval)
		end
		belt.Active = active
		belt.Watched = watched
	end
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 지역 k 의 벨트 폴더 (workspace.Conveyors.Zone<k>)
function ConveyorService.GetZoneFolder(zone: number): Folder?
	for _, belt in belts do
		if belt.Zone == zone then
			return belt.Folder
		end
	end
	return nil
end

function ConveyorService.Start()
	if started then
		return
	end
	started = true
	for _, name in { "Conveyor", "Conveyors" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local root = Instance.new("Folder")
	root.Name = "Conveyors"

	for k, def in Config.Zones do
		local startPos, endPos = def.ConveyorStart, def.ConveyorEnd
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = "Zone" .. k
		zoneFolder:SetAttribute("ZoneIndex", k)
		zoneFolder.Parent = root
		local length = (endPos - startPos).Magnitude
		local dir = (endPos - startPos).Unit
		local belt: Belt = {
			Zone = k,
			Folder = zoneFolder,
			Start = startPos,
			Dir = dir,
			Length = length,
			Base = CFrame.lookAt(startPos, startPos + dir),
			Speed = length / Config.Conveyor.TravelTime,
			Center = (startPos + endPos) / 2,
			Eggs = {},
			Active = k == 1,
			Watched = false,
			NextSpawn = os.clock() + (k - 1) * 0.3,
			LastAnnounce = -math.huge,
		}
		buildBelt(belt)
		table.insert(belts, belt)
	end
	root.Parent = workspace

	Players.PlayerRemoving:Connect(function(player)
		buyDebounce[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, belt in belts do
			if #belt.Eggs > 0 then
				updateEggs(belt, now)
			end
		end
	end)

	task.spawn(function()
		local nextRefresh = 0
		while true do
			local now = os.clock()
			if now >= nextRefresh then
				nextRefresh = now + 0.5
				local ok, err = pcall(refreshBeltStates)
				if not ok then
					warn("[ConveyorService] 벨트 상태 오류:", err)
				end
			end
			for _, belt in belts do
				if belt.Active and now >= belt.NextSpawn then
					belt.NextSpawn = now + Config.Conveyor.SpawnInterval
					local ok, err = pcall(spawnEgg, belt)
					if not ok then
						warn("[ConveyorService] 알 생성 오류:", err)
					end
				end
			end
			task.wait(0.25)
		end
	end)
end

return ConveyorService
