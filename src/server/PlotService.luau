-- 집(플롯): 바닥/울타리/받침대(1층 12개 + 2층 12개)/수금 패드, 수입·부화 틱, 펫 행동(PetAction) 처리.
-- (설계: docs/DESIGN.md "PlotService") ※ 집 외형은 나중에 HouseBuilder 가 대신 지어요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PetModels = require(ReplicatedStorage.Shared.PetModels)
local DataService = require(script.Parent.DataService)
local FollowService = require(script.Parent.FollowService)

local PlotService = {}

----------------------------------------------------------------------
-- 배치 상수 (기지 로컬 좌표. 입구 = 로컬 -Z)
----------------------------------------------------------------------
local SIZE = Config.Layout.PlotSize
local HALF = SIZE / 2
local FLOOR_TOP = 0.2 -- 땅(y=0)보다 살짝 위 (z-fighting 방지)
local WALL_H = 3
local GAP = 12 -- 입구 너비
local PED_BASE_H = 0.6
local PED_TOP_H = 1.0
local PED_H = PED_BASE_H + PED_TOP_H -- 받침대 전체 높이 (바닥 → 윗면)
local SLOT_COLS = { -13.5, -4.5, 4.5, 13.5 }
local SLOT_ROWS = { -4, 4.5, 13 } -- 입구에 가까운 줄부터
local SLOTS_PER_FLOOR = Config.Plot.SlotsPerFloor
local COLLECTOR_POS = Vector3.new(-12, 0, -13)
local SPAWN_POS = Vector3.new(0, FLOOR_TOP + 0.5, -9)

-- 2층 (받침대 13~24). 슬래브 윗면 = 로컬 y FLOOR2_Y
local FLOOR2_Y = 11
local FLOOR2_THICK = 1
local FLOOR2_SIZE = Vector3.new(36, FLOOR2_THICK, 26)
local FLOOR2_CENTER_Z = 4.5 -- 슬래브 z 범위: -8.5 ~ 17.5 (받침대 3줄을 덮음)
local RAMP_Z = -12 -- 경사로 중심 z (슬래브 앞, 입구 쪽)
local RAMP_W = 4
local RAMP_X0 = -2 -- 경사로 낮은 끝 (땅)
local RAMP_X1 = 14 -- 경사로 높은 끝 (2층 높이) → 오른쪽 착지 발판 → 슬래브

local PASTELS = {
	Color3.fromRGB(255, 196, 222), -- 분홍
	Color3.fromRGB(190, 236, 210), -- 민트
	Color3.fromRGB(190, 220, 255), -- 하늘
	Color3.fromRGB(222, 205, 255), -- 라벤더
	Color3.fromRGB(255, 218, 190), -- 복숭아
	Color3.fromRGB(255, 240, 175), -- 레몬
}
local ACCENTS = {
	Color3.fromRGB(255, 120, 175),
	Color3.fromRGB(80, 200, 150),
	Color3.fromRGB(90, 160, 255),
	Color3.fromRGB(165, 125, 255),
	Color3.fromRGB(255, 150, 95),
	Color3.fromRGB(245, 195, 50),
}
local WHITE = Color3.fromRGB(255, 252, 248)
local LOCKED_GREY = Color3.fromRGB(165, 165, 172)
local LOCKED_GREY_DARK = Color3.fromRGB(130, 130, 138)
local PRICE_YELLOW = Color3.fromRGB(255, 235, 120)

local CLAIM_DEBOUNCE = 1
local ACTION_THROTTLE = 0.15

-- 합성 때 먼저 쓰는 순서: 가방 → 집 → 따라옴 → 타기 → 들기
local LOC_RANK = { Bag = 1, Slot = 2, Follow = 3, Ride = 4, Hold = 5 }

local rng = Random.new()

----------------------------------------------------------------------
-- 상태
----------------------------------------------------------------------
type Visual = {
	Model: Model,
	Kind: string,
	Slot: number,
	HatchAt: number?,
	Tween: Tween?,
	Label: TextLabel?,
}

type Pedestal = {
	Slot: number,
	Top: BasePart,
	Base: BasePart,
	Billboard: BillboardGui,
	Label: TextLabel,
	BuyPrompt: ProximityPrompt,
	State: string?,
}

export type Plot = {
	Index: number,
	Model: Model,
	Owner: Player?,
	Origin: CFrame,
	Color: Color3,
	Accent: Color3,
	Floor: BasePart,
	Collector: BasePart,
	CollectorLabel: TextLabel,
	SpawnPoint: BasePart,
	SignLabels: { TextLabel },
	Pedestals: { [number]: Pedestal }, -- 1..24 (13~24 는 2층이 지어졌을 때만 있음)
	Floor2Parts: { BasePart }, -- 2층 슬래브/경사로/발판 (없으면 빈 표)
	Floors: number, -- 지금 지어져 있는 층 수 (1 또는 2)
	ItemsFolder: Folder,
	Visuals: { [string]: Visual },
	LastClaim: number,
	ShownPending: number,
}

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}
local lastAction: { [Player]: number } = {}
local started = false

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------
local function notify(player: Player?, text: string, kind: string?)
	if player and player.Parent then
		Remotes.Notify:FireClient(player, text, kind or "info")
	end
end

-- 마지막 글자의 받침 (없으면 0, ㄹ = 8). 한글이 아니면 nil
local function finalJamo(name: string): number?
	local last = nil
	for _, cp in utf8.codes(name) do
		last = cp
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 then
		return (last - 0xAC00) % 28
	end
	return nil
end

-- 받침 있는 글자면 a, 없으면 b ("곰돌이가" / "아기 용이")
local function josa(name: string, a: string, b: string): string
	local jong = finalJamo(name)
	if jong and jong ~= 0 then
		return name .. a
	end
	return name .. b
end

-- "으로" / "로"
local function josaRo(name: string): string
	local jong = finalJamo(name)
	if jong and jong ~= 0 and jong ~= 8 then
		return name .. "으로"
	end
	return name .. "로"
end

local function tierOf(v: any): number
	return math.clamp(math.floor(tonumber(v) or 1), 1, Config.MaxTier)
end

-- 캐릭터에 붙어 있는 위치인지 (따라옴 / 타기 / 들기) → 바뀌면 FollowService.Refresh 필요
local function isMounted(loc: any): boolean
	return loc == "Follow" or loc == "Ride" or loc == "Hold"
end

local function uidNumber(uid: string): number
	return tonumber(string.match(uid, "^i(%d+)$")) or 0
end

-- 2층을 올리면 바로 열리는 받침대 번호까지 (가격표에 없는 13~18 → 18)
local function floor2StartSlots(): number
	local n = SLOTS_PER_FLOOR
	while n < Config.Plot.TotalSlots and Config.Plot.SlotPrices[n + 1] == nil do
		n += 1
	end
	return n
end

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if props.Shape then
		p.Shape = props.Shape -- 크기보다 먼저
	end
	for k, v in props do
		if k ~= "Shape" then
			(p :: any)[k] = v
		end
	end
	return p
end

-- 세로로 선 원기둥 (높이 h, 지름 d), 바닥이 bottomY
local function cylinder(origin: CFrame, x: number, z: number, bottomY: number, h: number, d: number): (CFrame, Vector3)
	return origin * CFrame.new(x, bottomY + h / 2, z) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(h, d, d)
end

local function makeBillboard(adornee: BasePart, offsetY: number, w: number, h: number, maxDist: number): (BillboardGui, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(w, h)
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = maxDist
	bb.LightInfluence = 0
	bb.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(60, 40, 70)
	label.Text = ""
	label.Parent = bb
	bb.Parent = adornee
	return bb, label
end

local function makePrompt(parent: Instance, kind: string, ownerId: number, action: string, object: string, hold: number, key: Enum.KeyCode): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.KeyboardKeyCode = key
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("PromptKind", kind)
	prompt:SetAttribute("OwnerUserId", ownerId)
	prompt.Parent = parent
	return prompt
end

local function rootPart(player: Player): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

-- 받침대가 서는 바닥 위치 (로컬). Y = 그 층의 바닥 윗면
local function slotLocalPos(slot: number): Vector3
	local idx = (slot - 1) % SLOTS_PER_FLOOR
	local row = math.floor(idx / #SLOT_COLS) + 1
	local col = idx % #SLOT_COLS + 1
	local y = if Config.SlotFloor(slot) == 2 then FLOOR2_Y else FLOOR_TOP
	return Vector3.new(SLOT_COLS[col], y, SLOT_ROWS[row])
end

-- 받침대 윗면 (아이템이 놓이는 곳)
local function slotCFrameOf(plot: Plot, slot: number): CFrame
	local p = slotLocalPos(slot)
	return plot.Origin * CFrame.new(p.X, p.Y + PED_H, p.Z)
end

local function themeOf(plot: Plot): any
	local owner = plot.Owner
	local data = owner and DataService.Get(owner)
	if data and Config.House.Themes[data.Theme] then
		return Config.House.Themes[data.Theme]
	end
	return nil
end

-- 바닥 색: 주인이 있으면 테마 바닥색, 없으면 기지 기본 파스텔
local function floorColorOf(plot: Plot): Color3
	local theme = themeOf(plot)
	return if theme then theme.Floor else plot.Color
end

----------------------------------------------------------------------
-- 받침대 / 2층
----------------------------------------------------------------------
local tryBuySlot: (player: Player) -> ()

local function makePedestal(plot: Plot, slot: number): Pedestal
	local origin = plot.Origin
	local p = slotLocalPos(slot)
	local cf1, s1 = cylinder(origin, p.X, p.Z, p.Y, PED_BASE_H, 5.4)
	local base = newPart({ Name = "PedestalBase" .. slot, CFrame = cf1, Size = s1, Shape = Enum.PartType.Cylinder, Parent = plot.Model })
	local cf2, s2 = cylinder(origin, p.X, p.Z, p.Y + PED_BASE_H, PED_TOP_H, 4.6)
	local top = newPart({ Name = "Pedestal" .. slot, CFrame = cf2, Size = s2, Shape = Enum.PartType.Cylinder, Parent = plot.Model })
	top:SetAttribute("Slot", slot)
	local bb, label = makeBillboard(top, 2.2, 5, 1.6, 50)
	bb.Enabled = false
	local ownerId = if plot.Owner then plot.Owner.UserId else 0
	local buy = makePrompt(top, "Owner", ownerId, "받침대 열기", "", 0.3, Enum.KeyCode.E)
	buy.Enabled = false
	buy.Triggered:Connect(function(player)
		if player == plot.Owner then
			tryBuySlot(player)
		end
	end)
	local ped: Pedestal = { Slot = slot, Top = top, Base = base, Billboard = bb, Label = label, BuyPrompt = buy, State = nil }
	plot.Pedestals[slot] = ped
	return ped
end

-- 2층 부수기 (받침대 13~24 포함)
local function destroyFloor2(plot: Plot)
	for slot = SLOTS_PER_FLOOR + 1, Config.Plot.TotalSlots do
		local ped = plot.Pedestals[slot]
		if ped then
			plot.Pedestals[slot] = nil
			ped.Top:Destroy()
			ped.Base:Destroy()
		end
	end
	for _, part in plot.Floor2Parts do
		part:Destroy()
	end
	plot.Floor2Parts = {}
	plot.Floors = 1
end

-- 2층 짓기: 슬래브 + 경사로 + 착지 발판 + 받침대 13~24
local function buildFloor2(plot: Plot)
	destroyFloor2(plot)
	local origin = plot.Origin
	local parts = plot.Floor2Parts
	local floorColor = floorColorOf(plot)

	table.insert(
		parts,
		newPart({
			Name = "Floor2",
			Size = FLOOR2_SIZE,
			CFrame = origin * CFrame.new(0, FLOOR2_Y - FLOOR2_THICK / 2, FLOOR2_CENTER_Z),
			Color = floorColor,
			Parent = plot.Model,
		})
	)

	-- 경사로 (쐐기). 로컬 -Z 쪽이 낮아서, 90도 돌려 낮은 끝이 기지 -X 를 보게
	local rise = FLOOR2_Y - FLOOR_TOP
	local len = RAMP_X1 - RAMP_X0
	local ramp = Instance.new("WedgePart")
	ramp.Name = "Ramp"
	ramp.Anchored = true
	ramp.TopSurface = Enum.SurfaceType.Smooth
	ramp.BottomSurface = Enum.SurfaceType.Smooth
	ramp.Material = Enum.Material.SmoothPlastic
	ramp.Size = Vector3.new(RAMP_W, rise, len)
	ramp.CFrame = origin * CFrame.new((RAMP_X0 + RAMP_X1) / 2, FLOOR_TOP + rise / 2, RAMP_Z) * CFrame.Angles(0, math.pi / 2, 0)
	ramp.Color = plot.Accent
	ramp.Parent = plot.Model
	table.insert(parts, ramp)

	-- 경사로 꼭대기와 슬래브를 잇는 발판
	local landZ0 = RAMP_Z - RAMP_W / 2
	local landZ1 = FLOOR2_CENTER_Z - FLOOR2_SIZE.Z / 2
	table.insert(
		parts,
		newPart({
			Name = "Landing",
			Size = Vector3.new(RAMP_W, FLOOR2_THICK, landZ1 - landZ0),
			CFrame = origin * CFrame.new(RAMP_X1 + RAMP_W / 2, FLOOR2_Y - FLOOR2_THICK / 2, (landZ0 + landZ1) / 2),
			Color = floorColor,
			Parent = plot.Model,
		})
	)

	for slot = SLOTS_PER_FLOOR + 1, Config.Plot.TotalSlots do
		makePedestal(plot, slot)
	end
	plot.Floors = 2
end

----------------------------------------------------------------------
-- 기지 짓기
----------------------------------------------------------------------
local function buildPlot(index: number, origin: CFrame, parent: Instance): Plot
	local color = PASTELS[(index - 1) % #PASTELS + 1]
	local accent = ACCENTS[(index - 1) % #ACCENTS + 1]

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("Theme", "Basic")
	model:SetAttribute("Floors", 1)

	-- 바닥 + 테두리
	local floor = newPart({
		Name = "Floor",
		Size = Vector3.new(SIZE, 1, SIZE),
		CFrame = origin * CFrame.new(0, FLOOR_TOP - 0.5, 0),
		Color = color,
		Parent = model,
	})
	newPart({
		Name = "FloorTrim",
		Size = Vector3.new(SIZE + 2, 1, SIZE + 2),
		CFrame = origin * CFrame.new(0, FLOOR_TOP / 2 - 0.5, 0),
		Color = accent,
		Parent = model,
	})
	model.PrimaryPart = floor

	-- 낮은 울타리 (뒤, 왼쪽, 오른쪽, 입구 양옆)
	local walls = {
		{ Vector3.new(0, 0, HALF - 0.5), Vector3.new(SIZE, WALL_H, 1) },
		{ Vector3.new(-HALF + 0.5, 0, 0), Vector3.new(1, WALL_H, SIZE) },
		{ Vector3.new(HALF - 0.5, 0, 0), Vector3.new(1, WALL_H, SIZE) },
	}
	local segLen = HALF - GAP / 2
	table.insert(walls, { Vector3.new(-(GAP / 2 + segLen / 2), 0, -HALF + 0.5), Vector3.new(segLen, WALL_H, 1) })
	table.insert(walls, { Vector3.new(GAP / 2 + segLen / 2, 0, -HALF + 0.5), Vector3.new(segLen, WALL_H, 1) })
	for i, w in walls do
		local pos, size = w[1], w[2]
		newPart({
			Name = "Wall" .. i,
			Size = size,
			CFrame = origin * CFrame.new(pos.X, FLOOR_TOP + WALL_H / 2, pos.Z),
			Color = WHITE,
			Parent = model,
		})
		newPart({
			Name = "WallCap" .. i,
			Size = Vector3.new(size.X + 0.4, 0.5, size.Z + 0.4),
			CFrame = origin * CFrame.new(pos.X, FLOOR_TOP + WALL_H + 0.25, pos.Z),
			Color = accent,
			Parent = model,
		})
	end
	-- 모서리 동글 장식
	for _, c in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		newPart({
			Name = "CornerBall",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2, 2, 2),
			CFrame = origin * CFrame.new(c.X * (HALF - 0.5), FLOOR_TOP + WALL_H + 1, c.Z * (HALF - 0.5)),
			Color = accent,
			Parent = model,
		})
	end

	-- 입구 기둥 + 이름 간판
	local POST_H = 9.6
	for _, sx in { -1, 1 } do
		newPart({
			Name = "GatePost",
			Size = Vector3.new(1.2, POST_H, 1.2),
			CFrame = origin * CFrame.new(sx * (GAP / 2 + 0.6), FLOOR_TOP + POST_H / 2, -HALF + 0.5),
			Color = WHITE,
			Parent = model,
		})
	end
	local sign = newPart({
		Name = "Sign",
		Size = Vector3.new(GAP + 3.6, 2.8, 0.5),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + POST_H - 1.4, -HALF + 0.5),
		Color = accent,
		Parent = model,
	})
	local signLabels = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.94, 0.86)
		label.Position = UDim2.fromScale(0.03, 0.07)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Text = "빈 집"
		label.Parent = sg
		sg.Parent = sign
		table.insert(signLabels, label)
	end

	-- 아이템 폴더 (받침대 위 알/펫 모델)
	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = model

	-- 코인 받는 패드
	local cfR, sR = cylinder(origin, COLLECTOR_POS.X, COLLECTOR_POS.Z, FLOOR_TOP, 0.3, 7.2)
	newPart({ Name = "CollectorRing", CFrame = cfR, Size = sR, Shape = Enum.PartType.Cylinder, Color = WHITE, Parent = model })
	local cfC, sC = cylinder(origin, COLLECTOR_POS.X, COLLECTOR_POS.Z, FLOOR_TOP, 0.6, 6)
	local collector = newPart({
		Name = "Collector",
		CFrame = cfC,
		Size = sC,
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(255, 205, 60),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	collector:SetAttribute("Pending", 0)
	local _, collectorLabel = makeBillboard(collector, 3.5, 7, 1.8, 60)
	collectorLabel.TextColor3 = PRICE_YELLOW
	collectorLabel.Text = "💰 0 받기"

	-- 스폰 위치 (보이지 않음)
	local spawn = newPart({
		Name = "SpawnPoint",
		Size = Vector3.new(4, 1, 4),
		CFrame = origin * CFrame.new(SPAWN_POS),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Parent = model,
	})

	model.Parent = parent

	local plot: Plot = {
		Index = index,
		Model = model,
		Owner = nil,
		Origin = origin,
		Color = color,
		Accent = accent,
		Floor = floor,
		Collector = collector,
		CollectorLabel = collectorLabel,
		SpawnPoint = spawn,
		SignLabels = signLabels,
		Pedestals = {},
		Floor2Parts = {},
		Floors = 1,
		ItemsFolder = items,
		Visuals = {},
		LastClaim = 0,
		ShownPending = -1,
	}

	-- 1층 받침대 1~12 (2층은 주인의 Floors 가 2일 때 RebuildHouse 가 지어요)
	for slot = 1, SLOTS_PER_FLOOR do
		makePedestal(plot, slot)
	end
	return plot
end

----------------------------------------------------------------------
-- 화면 갱신
----------------------------------------------------------------------
local function setSign(plot: Plot)
	local owner = plot.Owner
	local text = if owner then owner.DisplayName .. "의 집" else "빈 집"
	for _, label in plot.SignLabels do
		label.Text = text
	end
end

-- 잠긴 받침대: "🔒 💰가격" (13~18번은 2층이 없으면 "🔒 2층"). 다음 받침대만 구매 프롬프트
local function updatePedestals(plot: Plot)
	local owner = plot.Owner
	local data = owner and DataService.Get(owner)
	local unlocked = if data then data.SlotsUnlocked else Config.Plot.StartSlots
	local floors = if data then data.Floors else 1
	local nextPrice = if data then Config.NextSlotPrice(unlocked, floors) else nil
	local ownerId = if owner then owner.UserId else 0
	for slot, ped in plot.Pedestals do
		local state: string
		local labelText = ""
		local canBuy = false
		if slot <= unlocked then
			state = "open"
		else
			if floors < 2 and Config.SlotFloor(slot) == 2 then
				labelText = "🔒 2층"
			else
				local price = Config.Plot.SlotPrices[slot]
				labelText = if price then "🔒 💰" .. Config.FormatNumber(price) else "🔒"
			end
			canBuy = data ~= nil and slot == unlocked + 1 and nextPrice ~= nil
			state = "locked:" .. labelText .. ":" .. (if canBuy then "buy" else "no") .. ":" .. ownerId
		end
		ped.BuyPrompt:SetAttribute("OwnerUserId", ownerId)
		if ped.State == state then
			continue
		end
		ped.State = state
		if state == "open" then
			ped.Top.Color = plot.Accent
			ped.Top.Transparency = 0
			ped.Base.Color = WHITE
			ped.Billboard.Enabled = false
			ped.BuyPrompt.Enabled = false
		else
			ped.Top.Color = LOCKED_GREY
			ped.Top.Transparency = 0.15
			ped.Base.Color = LOCKED_GREY_DARK
			ped.Billboard.Enabled = true
			ped.Label.Text = labelText
			ped.Label.TextColor3 = if canBuy then PRICE_YELLOW else Color3.new(1, 1, 1)
			if canBuy and nextPrice then
				ped.BuyPrompt.ObjectText = "💰" .. Config.FormatNumber(nextPrice)
			end
			ped.BuyPrompt.Enabled = canBuy
		end
	end
end

local function updateCollector(plot: Plot)
	local owner = plot.Owner
	local data = owner and DataService.Get(owner)
	local pending = if data then math.floor(data.Pending) else 0
	if pending == plot.ShownPending then
		return
	end
	plot.ShownPending = pending
	plot.Collector:SetAttribute("Pending", pending)
	plot.CollectorLabel.Text = "💰 " .. Config.FormatNumber(pending) .. " 받기"
end

----------------------------------------------------------------------
-- 아이템 모델
----------------------------------------------------------------------
local function itemName(item: any): string
	if item.Kind == "Pet" then
		return Config.PetDisplayName(item.Id, item.Tier)
	end
	local egg = Config.Eggs[item.Id]
	return if egg then egg.Name else tostring(item.Id)
end

local function itemLabelText(item: any): string
	if item.Kind == "Pet" then
		local sizeLabel = Config.SizeLabel(Config.SizeOf(item))
		local prefix = if sizeLabel ~= "" then sizeLabel .. " " else ""
		return prefix .. itemName(item) .. "  💰" .. Config.FormatNumber(Config.ItemIncome(item)) .. "/초"
	end
	local egg = Config.Eggs[item.Id]
	local left = math.max(0, math.ceil((item.HatchAt or 0) - os.time()))
	if left <= 0 then
		return egg.Name .. "\n곧 부화!"
	end
	return egg.Name .. "\n⏳ " .. left .. "초"
end

local function destroyVisual(v: Visual)
	if v.Tween then
		v.Tween:Cancel()
	end
	v.Model:Destroy()
end

function PlotService.RemoveItemVisual(player: Player, uid: string)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	local v = plot.Visuals[uid]
	if v then
		plot.Visuals[uid] = nil
		destroyVisual(v)
	end
end

local handlePetAction: (player: Player, uid: any, action: any) -> ()

function PlotService.PlaceItem(player: Player, uid: string)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	local item = DataService.GetItem(player, uid)
	if not item or item.Loc ~= "Slot" or type(item.Slot) ~= "number" then
		return
	end
	local slot = item.Slot :: number
	if slot < 1 or slot > Config.Plot.TotalSlots then
		return
	end
	-- 이미 있던 모델 / 같은 자리에 남은 모델 정리
	PlotService.RemoveItemVisual(player, uid)
	for otherUid, v in plot.Visuals do
		if v.Slot == slot then
			plot.Visuals[otherUid] = nil
			destroyVisual(v)
		end
	end

	local isPet = item.Kind == "Pet"
	local tier = if isPet then tierOf(item.Tier) else 1
	local ok, model = pcall(function()
		if isPet then
			return PetModels.BuildPet(item.Id, tier)
		end
		return PetModels.BuildEgg(item.Id)
	end)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		warn("[PlotService] 모델 만들기 실패:", item.Kind, item.Id, model)
		return
	end
	local m = model :: Model
	local size = if isPet then Config.SizeOf(item) else 1
	if isPet then
		-- 크기 (피벗 = 바닥 중심이라 받침대 위에 그대로 앉아요)
		pcall(function()
			m:ScaleTo(size)
		end)
	end
	m.Name = (if isPet then "Pet_" else "Egg_") .. uid
	m:SetAttribute("ItemUid", uid)
	m:SetAttribute("OwnerUserId", player.UserId)
	m:SetAttribute("Kind", item.Kind)
	m:SetAttribute("Id", item.Id)
	if isPet then
		m:SetAttribute("Tier", tier)
		m:SetAttribute("Size", size)
	else
		m:SetAttribute("HatchAt", item.HatchAt)
	end

	local body = m.PrimaryPart or m:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		body = m:FindFirstChildWhichIsA("BasePart", true)
	end
	if not body then
		m:Destroy()
		return
	end
	local bodyPart = body :: BasePart
	local rarity = if isPet then Config.Pets[item.Id].Rarity else Config.Eggs[item.Id].Rarity
	if isPet and (rarity == "Legendary" or rarity == "Mythic") then
		pcall(PetModels.AddRarityEffects, m, rarity)
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == bodyPart
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	m:PivotTo(slotCFrameOf(plot, slot))

	-- 이름표 (황금/무지개 등급은 등급 색). 큰 펫은 조금 더 위에
	local bb, label = makeBillboard(bodyPart, 3.2 * size, 6, if isPet then 1.1 else 1.8, 40)
	bb.Name = "ItemTag"
	label.TextColor3 = if isPet and tier >= 2 then Config.TierInfo(tier).Color else Config.Rarities[rarity].Color
	label.Text = itemLabelText(item)

	-- 주인 프롬프트: 가방에 넣기
	local own = makePrompt(bodyPart, "Owner", player.UserId, "가방에 넣기", itemName(item), 0.4, Enum.KeyCode.F)
	own.Triggered:Connect(function(who)
		if who == player and plot.Owner == player then
			handlePetAction(player, uid, "ToBag")
		end
	end)

	m.Parent = plot.ItemsFolder

	-- 펫은 살랑살랑 (서버 트윈 1개, 반복)
	local tween: Tween? = nil
	if isPet then
		local start = bodyPart.CFrame
		local info = TweenInfo.new(1.1 + math.random() * 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local tw = TweenService:Create(bodyPart, info, { CFrame = start * CFrame.new(0, 0.35, 0) })
		tw:Play()
		tween = tw
	end

	plot.Visuals[uid] = {
		Model = m,
		Kind = item.Kind,
		Slot = slot,
		HatchAt = item.HatchAt,
		Tween = tween,
		Label = label,
	}
end

-- 받침대 위 아이템을 전부 다시 그려요 (집을 다시 지은 뒤 등)
function PlotService.RefreshPlot(player: Player)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	for uid, v in plot.Visuals do
		plot.Visuals[uid] = nil
		destroyVisual(v)
	end
	local data = DataService.Get(player)
	if data then
		for uid, item in data.Items do
			if item.Loc == "Slot" then
				PlotService.PlaceItem(player, uid)
			end
		end
	end
	updatePedestals(plot)
	plot.ShownPending = -1
	updateCollector(plot)
	setSign(plot)
end

-- 주인의 Theme/Floors 에 맞게 집을 다시 짓고 (2층 + 받침대 13~24) 아이템을 다시 그려요
function PlotService.RebuildHouse(player: Player)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	local data = DataService.Get(player)
	local floors = if data then data.Floors else 1
	local themeId = if data then data.Theme else "Basic"
	plot.Model:SetAttribute("Theme", themeId)
	plot.Model:SetAttribute("Floors", floors)
	plot.Floor.Color = floorColorOf(plot)
	if floors >= 2 then
		buildFloor2(plot)
	else
		destroyFloor2(plot)
	end
	for _, ped in plot.Pedestals do
		ped.State = nil
	end
	PlotService.RefreshPlot(player)
end

----------------------------------------------------------------------
-- 기지 배정 / 조회
----------------------------------------------------------------------
function PlotService.GetPlot(player: Player): Plot?
	return plotByPlayer[player]
end

function PlotService.GetPlotAt(position: Vector3): Plot?
	for _, plot in plots do
		local p = plot.Origin:PointToObjectSpace(position)
		if math.abs(p.X) <= HALF and math.abs(p.Z) <= HALF then
			return plot
		end
	end
	return nil
end

function PlotService.FreeSlot(player: Player): number?
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local used = {}
	for _, item in data.Items do
		if item.Loc == "Slot" and item.Slot then
			used[item.Slot] = true
		end
	end
	for slot = 1, math.min(data.SlotsUnlocked, Config.Plot.TotalSlots) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

function PlotService.GetSlotCFrame(player: Player, slot: number): CFrame
	local plot = plotByPlayer[player]
	if not plot then
		return CFrame.new(Config.Layout.LobbySpawn + Vector3.new(0, 3, 0))
	end
	return slotCFrameOf(plot, math.clamp(slot, 1, Config.Plot.TotalSlots))
end

local function setPromptOwners(plot: Plot, ownerId: number)
	for _, ped in plot.Pedestals do
		ped.BuyPrompt:SetAttribute("OwnerUserId", ownerId)
	end
end

function PlotService.AssignPlot(player: Player): Plot?
	local existing = plotByPlayer[player]
	if existing then
		return existing
	end
	local plot: Plot? = nil
	for _, p in plots do
		if p.Owner == nil then
			plot = p
			break
		end
	end
	if not plot then
		notify(player, "빈 집이 없어요 😢", "warn")
		return nil
	end
	local p = plot :: Plot
	p.Owner = player
	plotByPlayer[player] = p
	p.LastClaim = 0
	p.Model:SetAttribute("OwnerUserId", player.UserId)
	p.Model:SetAttribute("OwnerName", player.DisplayName)
	player:SetAttribute("PlotIndex", p.Index)
	setPromptOwners(p, player.UserId)
	PlotService.RebuildHouse(player) -- 테마/층 반영 + 아이템 그리기
	return p
end

function PlotService.ReleasePlot(player: Player)
	local plot = plotByPlayer[player]
	lastAction[player] = nil
	if not plot then
		return
	end
	plotByPlayer[player] = nil
	for uid, v in plot.Visuals do
		plot.Visuals[uid] = nil
		destroyVisual(v)
	end
	plot.Owner = nil
	plot.Model:SetAttribute("OwnerUserId", 0)
	plot.Model:SetAttribute("OwnerName", "")
	plot.Model:SetAttribute("Theme", "Basic")
	plot.Model:SetAttribute("Floors", 1)
	if player.Parent then
		player:SetAttribute("PlotIndex", nil)
	end
	setPromptOwners(plot, 0)
	destroyFloor2(plot)
	plot.Floor.Color = plot.Color
	for _, ped in plot.Pedestals do
		ped.State = nil
	end
	updatePedestals(plot)
	plot.ShownPending = -1
	updateCollector(plot)
	setSign(plot)

	-- 빈 집이 생겼으니 집 없이 기다리던 사람에게 바로 배정
	for _, other in Players:GetPlayers() do
		if other ~= player and not plotByPlayer[other] and DataService.Get(other) then
			local assigned = PlotService.AssignPlot(other)
			if assigned then
				notify(other, "집이 생겼어요! 🏠", "good")
				if other.Character then
					PlotService.OnCharacterAdded(other, other.Character)
				end
				DataService.Sync(other)
				break
			end
		end
	end
end

function PlotService.OnCharacterAdded(player: Player, character: Model)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	task.spawn(function()
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		if not hrp then
			return
		end
		-- 기본 스폰 배치가 끝난 다음에 옮겨요
		local t = 0
		while not character:IsDescendantOf(workspace) and t < 5 do
			t += task.wait(0.05)
		end
		task.wait(0.1)
		if plotByPlayer[player] ~= plot or character.Parent == nil or player.Character ~= character then
			return
		end
		character:PivotTo(plot.SpawnPoint.CFrame * CFrame.new(0, 3, 0))
	end)
end

----------------------------------------------------------------------
-- 수금 / 받침대 구매 / 2층 / 테마
----------------------------------------------------------------------
local function claim(plot: Plot, player: Player)
	if plot.Owner ~= player then
		return
	end
	local t = os.clock()
	if t - plot.LastClaim < CLAIM_DEBOUNCE then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	local amount = math.floor(data.Pending)
	if amount <= 0 then
		return
	end
	plot.LastClaim = t
	data.Pending -= amount
	DataService.AddCoins(player, amount)
	Remotes.CoinFx:FireClient(player, amount, plot.Collector.Position + Vector3.new(0, 3, 0))
	notify(player, "💰 " .. Config.FormatNumber(amount) .. " 코인을 받았어요!", "good")
	updateCollector(plot)
	DataService.Sync(player)
end

-- 같은 사람이 너무 빨리 연타하면 무시
local function throttled(player: Player): boolean
	local t = os.clock()
	if t - (lastAction[player] or 0) < ACTION_THROTTLE then
		return true
	end
	lastAction[player] = t
	return false
end

tryBuySlot = function(player: Player)
	local plot = plotByPlayer[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return
	end
	local price = Config.NextSlotPrice(data.SlotsUnlocked, data.Floors)
	if not price then
		if data.SlotsUnlocked >= Config.Plot.TotalSlots then
			notify(player, "받침대가 최대예요! 🎉", "info")
		elseif data.Floors < 2 and data.SlotsUnlocked >= SLOTS_PER_FLOOR then
			notify(player, "2층을 먼저 올려야 해요! 🏠", "warn")
		else
			notify(player, "지금은 받침대를 살 수 없어요", "warn")
		end
		return
	end
	if not DataService.TrySpend(player, price) then
		notify(player, "코인이 부족해요! 💰" .. Config.FormatNumber(price) .. " 필요해요", "warn")
		return
	end
	data.SlotsUnlocked += 1
	updatePedestals(plot)
	notify(player, "새 받침대가 열렸어요! 🎉", "good")
	DataService.Sync(player)
end

local function tryBuyFloor(player: Player)
	local plot = plotByPlayer[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return
	end
	if data.Floors >= Config.House.MaxFloors then
		notify(player, "이미 2층이 있어요! 🏠", "info")
		return
	end
	if data.SlotsUnlocked < SLOTS_PER_FLOOR then
		notify(player, "1층 받침대 " .. SLOTS_PER_FLOOR .. "개를 먼저 다 열어야 해요!", "warn")
		return
	end
	local price = Config.House.FloorPrice
	if not DataService.TrySpend(player, price) then
		notify(player, "코인이 부족해요! 💰" .. Config.FormatNumber(price) .. " 필요해요", "warn")
		return
	end
	data.Floors = 2
	data.SlotsUnlocked = math.max(data.SlotsUnlocked, floor2StartSlots())
	PlotService.RebuildHouse(player)
	notify(player, "🏠 2층이 생겼어요!", "good")
	DataService.Sync(player)
end

local function trySetTheme(player: Player, themeId: any)
	if type(themeId) ~= "string" or #themeId > 32 then
		return
	end
	local theme = Config.House.Themes[themeId]
	if not theme then
		return
	end
	local plot = plotByPlayer[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return
	end
	if not data.Themes[themeId] then
		local price = tonumber(theme.Price) or 0
		if not DataService.TrySpend(player, price) then
			notify(player, "코인이 부족해요! 💰" .. Config.FormatNumber(price) .. " 필요해요", "warn")
			return
		end
		data.Themes[themeId] = true
		notify(player, "🎨 " .. theme.Name .. " 테마를 샀어요!", "good")
	elseif data.Theme == themeId then
		notify(player, "이미 " .. theme.Name .. " 테마예요!", "info")
		return
	end
	data.Theme = themeId
	PlotService.RebuildHouse(player)
	notify(player, "🏠 " .. josaRo(theme.Name) .. " 꾸몄어요!", "good")
	DataService.Sync(player)
end

-- 환생: 코인(수금 대기 포함)을 0으로 돌리고 영구 보너스. 펫·집·받침대·테마는 그대로
local function tryRebirth(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local n = data.Rebirths
	local cost = Config.RebirthCost(n)
	if n >= Config.Rebirth.MaxRebirths then
		notify(player, "환생은 최대 " .. Config.Rebirth.MaxRebirths .. "회까지예요! 🌟", "info")
		return
	end
	if data.Coins < cost then
		notify(
			player,
			"환생하려면 💰" .. Config.FormatNumber(cost) .. " 코인이 필요해요! (지금 💰" .. Config.FormatNumber(data.Coins) .. ")",
			"warn"
		)
		return
	end
	data.Coins = 0
	data.Pending = 0
	data.Rebirths = n + 1
	local plot = plotByPlayer[player]
	if plot then
		updateCollector(plot)
	end
	local ok, err = pcall(FollowService.UpdateSpeed, player)
	if not ok then
		warn("[PlotService] UpdateSpeed 오류:", err)
	end
	local r = data.Rebirths
	notify(
		player,
		string.format(
			"🔄 환생 %d회! 수익 ×%.1f, 코인 ×%.1f, 속도 +%.0f%%",
			r,
			Config.RebirthIncomeMult(r),
			Config.RebirthCoinMult(r),
			(Config.RebirthSpeedMult(r) - 1) * 100
		),
		"good"
	)
	DataService.Sync(player)
end

----------------------------------------------------------------------
-- 펫 행동 (PetAction)
----------------------------------------------------------------------
local function refreshFollow(player: Player)
	local ok, err = pcall(function()
		FollowService.Refresh(player)
		FollowService.UpdateSpeed(player)
	end)
	if not ok then
		warn("[PlotService] FollowService 오류:", err)
	end
end

handlePetAction = function(player: Player, uid: any, action: any)
	if type(uid) ~= "string" or type(action) ~= "string" or #uid > 32 then
		return
	end
	if throttled(player) then
		return
	end

	local data = DataService.Get(player)
	if not data then
		return
	end
	local item = data.Items[uid]
	if not item then
		notify(player, "그 펫을 찾을 수 없어요", "warn")
		return
	end
	local wasLoc = item.Loc
	local name = itemName(item)

	if action == "Follow" then
		if item.Kind ~= "Pet" then
			notify(player, "알은 데리고 다닐 수 없어요!", "warn")
			return
		end
		if wasLoc == "Follow" then
			return
		end
		if DataService.CountItems(player, "Follow") >= Config.MaxFollow then
			notify(player, "따라다니는 펫은 최대 " .. Config.MaxFollow .. "마리예요!", "warn")
			return
		end
		if wasLoc == "Slot" then
			PlotService.RemoveItemVisual(player, uid)
		end
		item.Loc = "Follow"
		item.Slot = nil
		refreshFollow(player)
		notify(player, josa(name, "이", "가") .. " 따라와요! 🐾", "good")
	elseif action == "Unfollow" then
		if wasLoc ~= "Follow" then
			return
		end
		item.Loc = "Bag"
		item.Slot = nil
		refreshFollow(player)
		notify(player, josa(name, "을", "를") .. " 가방에 넣었어요 🎒", "info")
	elseif action == "ToBase" then
		if wasLoc == "Slot" then
			return
		end
		if not plotByPlayer[player] then
			notify(player, "집이 없어요 😢", "warn")
			return
		end
		local slot = PlotService.FreeSlot(player)
		if not slot then
			notify(player, "집에 빈 받침대가 없어요!", "warn")
			return
		end
		item.Loc = "Slot"
		item.Slot = slot
		if item.Kind == "Egg" then
			local left = item.HatchLeft or Config.Eggs[item.Id].HatchTime
			item.HatchAt = os.time() + math.max(0, left)
			item.HatchLeft = nil
		end
		PlotService.PlaceItem(player, uid)
		if isMounted(wasLoc) then
			refreshFollow(player)
		end
		notify(player, josa(name, "을", "를") .. " 집에 놓았어요 🏠", "good")
	elseif action == "ToBag" then
		if wasLoc == "Bag" then
			return
		end
		if DataService.CountItems(player, "Bag") >= Config.MaxBagItems then
			notify(player, "가방이 가득 찼어요! 🎒", "warn")
			return
		end
		if wasLoc == "Slot" then
			PlotService.RemoveItemVisual(player, uid)
		end
		if item.Kind == "Egg" then
			item.HatchLeft = math.max(0, (item.HatchAt or os.time()) - os.time())
			item.HatchAt = nil
		end
		item.Loc = "Bag"
		item.Slot = nil
		if isMounted(wasLoc) then
			refreshFollow(player)
		end
		notify(player, josa(name, "을", "를") .. " 가방에 넣었어요 🎒", "info")
	elseif action == "Sell" then
		if item.Kind ~= "Pet" then
			notify(player, "알은 팔 수 없어요!", "warn")
			return
		end
		local price = Config.SellPrice(item.Id, item.Tier)
		DataService.RemoveItem(player, uid)
		if wasLoc == "Slot" then
			PlotService.RemoveItemVisual(player, uid)
		elseif isMounted(wasLoc) then
			refreshFollow(player)
		end
		DataService.AddCoins(player, price)
		local hrp = rootPart(player)
		if hrp then
			Remotes.CoinFx:FireClient(player, price, hrp.Position + Vector3.new(0, 3, 0))
		end
		notify(player, josa(name, "을", "를") .. " 팔았어요! +💰" .. Config.FormatNumber(price), "good")
	elseif action == "Ride" then
		if item.Kind ~= "Pet" then
			notify(player, "알은 탈 수 없어요!", "warn")
			return
		end
		if wasLoc == "Ride" then
			return
		end
		-- 타던 펫은 가방으로 (타는 펫은 한 마리만)
		for otherUid, other in data.Items do
			if otherUid ~= uid and other.Loc == "Ride" then
				other.Loc = "Bag"
				other.Slot = nil
			end
		end
		if wasLoc == "Slot" then
			PlotService.RemoveItemVisual(player, uid)
		end
		item.Loc = "Ride"
		item.Slot = nil
		refreshFollow(player)
		notify(player, "🏇 " .. josa(name, "을", "를") .. " 탔어요! 더 빨라져요 💨", "good")
	elseif action == "Unride" then
		if wasLoc ~= "Ride" then
			return
		end
		item.Loc = "Bag"
		item.Slot = nil
		refreshFollow(player)
		notify(player, name .. "에서 내렸어요. 가방에 넣었어요 🎒", "info")
	elseif action == "Hold" then
		if item.Kind ~= "Pet" then
			notify(player, "알은 들 수 없어요!", "warn")
			return
		end
		if wasLoc == "Hold" then
			return
		end
		-- 들고 있던 펫은 가방으로 (드는 펫은 한 마리만)
		for otherUid, other in data.Items do
			if otherUid ~= uid and other.Loc == "Hold" then
				other.Loc = "Bag"
				other.Slot = nil
			end
		end
		if wasLoc == "Slot" then
			PlotService.RemoveItemVisual(player, uid)
		end
		item.Loc = "Hold"
		item.Slot = nil
		refreshFollow(player)
		notify(player, "🙌 " .. josa(name, "을", "를") .. " 머리 위에 올렸어요!", "good")
	elseif action == "Unhold" then
		if wasLoc ~= "Hold" then
			return
		end
		item.Loc = "Bag"
		item.Slot = nil
		refreshFollow(player)
		notify(player, josa(name, "을", "를") .. " 내려놓았어요. 가방에 넣었어요 🎒", "info")
	elseif action == "Fuse" then
		if item.Kind ~= "Pet" then
			notify(player, "알은 합성할 수 없어요!", "warn")
			return
		end
		local tier = tierOf(item.Tier)
		if tier >= Config.MaxTier then
			notify(player, "이미 최고 등급이에요! 🌈", "info")
			return
		end
		-- 같은 펫·같은 등급 모으기
		local others: { string } = {}
		for otherUid, other in data.Items do
			if otherUid ~= uid and other.Kind == "Pet" and other.Id == item.Id and tierOf(other.Tier) == tier then
				table.insert(others, otherUid)
			end
		end
		local have = #others + 1
		if have < Config.FuseCount then
			notify(player, "같은 펫 " .. Config.FuseCount .. "마리가 필요해요! (" .. have .. "/" .. Config.FuseCount .. ")", "warn")
			return
		end
		-- 가방 → 집 → 따라옴 → 타기 순으로 먼저 써요 (같은 곳이면 오래된 것부터)
		table.sort(others, function(a, b)
			local ra = LOC_RANK[data.Items[a].Loc] or 9
			local rb = LOC_RANK[data.Items[b].Loc] or 9
			if ra ~= rb then
				return ra < rb
			end
			return uidNumber(a) < uidNumber(b)
		end)
		local consumed = { uid }
		for i = 1, Config.FuseCount - 1 do
			table.insert(consumed, others[i])
		end
		local newTier = tier + 1
		-- 크기: 합친 펫 중 가장 큰 크기 + 0.02 (최대까지)
		local maxSize = Config.PetSize.Min
		for _, cuid in consumed do
			maxSize = math.max(maxSize, Config.SizeOf(data.Items[cuid]))
		end
		local newSize = math.floor(math.min(maxSize + 0.02, Config.PetSize.Max) * 100 + 0.5) / 100
		-- 새 펫은 누른 펫 자리에 (같은 받침대 / 따라옴 / 타기 / 들기 / 가방)
		local newItem: DataService.Item = { Kind = "Pet", Id = item.Id, Tier = newTier, Size = newSize, Loc = wasLoc, Slot = item.Slot }
		local needFollow = false
		for _, cuid in consumed do
			local removed = DataService.RemoveItem(player, cuid)
			if removed then
				if removed.Loc == "Slot" then
					PlotService.RemoveItemVisual(player, cuid)
				elseif isMounted(removed.Loc) then
					needFollow = true
				end
			end
		end
		local newUid = DataService.AddItem(player, newItem)
		local isNew = DataService.MarkDiscovered(player, item.Id, newTier)
		data.Stats.Fused += 1
		local pos: Vector3
		local plot = plotByPlayer[player]
		if newItem.Loc == "Slot" and plot and type(newItem.Slot) == "number" then
			PlotService.PlaceItem(player, newUid)
			pos = slotCFrameOf(plot, newItem.Slot :: number).Position + Vector3.new(0, 2, 0)
		else
			local hrp = rootPart(player)
			pos = if hrp then hrp.Position + Vector3.new(0, 3, 0) else Vector3.zero
		end
		if isMounted(newItem.Loc) or needFollow then
			refreshFollow(player)
		end
		Remotes.HatchFx:FireClient(player, item.Id, pos, isNew, newTier, "Fuse")
		local newName = Config.PetDisplayName(item.Id, newTier)
		notify(player, "✨ 합성 성공! " .. josa(newName, "이", "가") .. " 되었어요!", "good")
	else
		return
	end
	DataService.Sync(player)
end

----------------------------------------------------------------------
-- 부화 / 수입 틱
----------------------------------------------------------------------
local function hatch(player: Player, plot: Plot, uid: string, item: any)
	local eggId = item.Id
	local petId = Config.RollPet(eggId, rng)
	local slot = item.Slot
	-- 환생 운: 가끔 황금/무지개로 태어나요. 크기도 여기서 뽑아요
	local tier = Config.RollHatchTier(DataService.GetRebirths(player), rng)
	local size = Config.RollPetSize(rng)
	item.Kind = "Pet"
	item.Id = petId
	item.Tier = tier
	item.Size = size
	item.Loc = "Slot"
	item.HatchAt = nil
	item.HatchLeft = nil
	local isNew = DataService.MarkDiscovered(player, petId, tier)
	local data = DataService.Get(player)
	if data then
		data.Stats.Hatched += 1
	end
	local pos = slotCFrameOf(plot, slot).Position + Vector3.new(0, 2, 0)
	Remotes.HatchFx:FireClient(player, petId, pos, isNew, tier, "Hatch")
	PlotService.PlaceItem(player, uid)
	local pet = Config.Pets[petId]
	local rarityName = Config.Rarities[pet.Rarity].Name
	local sizeLabel = Config.SizeLabel(size)
	local bornName = (if sizeLabel ~= "" then sizeLabel .. " " else "") .. Config.PetDisplayName(petId, tier)
	notify(player, "🎉 [" .. rarityName .. "] " .. josa(bornName, "이", "가") .. " 태어났어요!", "good")
	DataService.Sync(player)
end

local function tickPlot(plot: Plot)
	local owner = plot.Owner
	if not owner then
		return
	end
	local data = DataService.Get(owner)
	if not data then
		return
	end

	-- 수입 + 부화
	local income = 0
	local nowSec = os.time()
	local toHatch = nil
	for uid, item in data.Items do
		if item.Loc ~= "Slot" then
			continue
		end
		if item.Kind == "Pet" then
			income += Config.ItemIncome(item)
		elseif item.Kind == "Egg" then
			if item.HatchAt and nowSec >= item.HatchAt and item.Slot then
				toHatch = toHatch or {}
				table.insert(toHatch, uid)
			else
				local v = plot.Visuals[uid]
				if v and v.Label then
					v.Label.Text = itemLabelText(item)
				end
			end
		end
	end
	if income > 0 then
		data.Pending += income * Config.RebirthIncomeMult(data.Rebirths)
	end
	if toHatch then
		for _, uid in toHatch do
			local item = data.Items[uid]
			if item and item.Kind == "Egg" and item.Loc == "Slot" then
				hatch(owner, plot, uid, item)
			end
		end
	end
	updateCollector(plot)

	-- 수금 패드 위에 서 있으면 자동으로 받기
	local hrp = rootPart(owner)
	if hrp then
		local rel = plot.Collector.Position - hrp.Position
		if
			Vector2.new(rel.X, rel.Z).Magnitude < 3.6
			and math.abs(rel.Y) < 6
			and os.clock() - plot.LastClaim >= 3
		then
			claim(plot, owner)
		end
	end
end

----------------------------------------------------------------------
-- 시작
----------------------------------------------------------------------
function PlotService.Start()
	if started then
		return
	end
	started = true

	local folder = workspace:FindFirstChild("Plots")
	if folder then
		folder:Destroy()
	end
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace

	for i, origin in Config.Layout.Plots do
		local plot = buildPlot(i, origin, plotsFolder)
		plots[i] = plot
		updatePedestals(plot)

		plot.Collector.Touched:Connect(function(hit)
			local owner = plot.Owner
			if not owner then
				return
			end
			local char = hit:FindFirstAncestorOfClass("Model")
			if not char or char ~= owner.Character then
				return
			end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then
				return
			end
			claim(plot, owner)
		end)
	end

	Remotes.PetAction.OnServerEvent:Connect(function(player, uid, action)
		handlePetAction(player, uid, action)
	end)
	Remotes.BuySlot.OnServerEvent:Connect(function(player)
		if throttled(player) then
			return
		end
		tryBuySlot(player)
	end)
	Remotes.BuyFloor.OnServerEvent:Connect(function(player)
		if throttled(player) then
			return
		end
		tryBuyFloor(player)
	end)
	Remotes.SetTheme.OnServerEvent:Connect(function(player, themeId)
		if throttled(player) then
			return
		end
		trySetTheme(player, themeId)
	end)
	Remotes.Rebirth.OnServerEvent:Connect(function(player)
		if throttled(player) then
			return
		end
		tryRebirth(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			for _, plot in plots do
				local ok, err = pcall(tickPlot, plot)
				if not ok then
					warn("[PlotService] tick 오류:", err)
				end
			end
		end
	end)
end

return PlotService
