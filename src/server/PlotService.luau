-- 기지(플롯): 바닥/울타리/레이저 문/받침대/수금 패드/잠금 버튼, 수입·부화 틱, 펫 행동 처리.
-- (설계: docs/DESIGN.md "PlotService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PetModels = require(ReplicatedStorage.Shared.PetModels)
local DataService = require(script.Parent.DataService)
local FollowService = require(script.Parent.FollowService)

local PlotService = {}

PlotService.Callbacks = {
	OnStealPrompt = nil :: ((thief: Player, owner: Player, uid: string) -> ())?,
}

----------------------------------------------------------------------
-- 배치 상수 (기지 로컬 좌표. 입구 = 로컬 -Z)
----------------------------------------------------------------------
local SIZE = Config.Layout.PlotSize
local HALF = SIZE / 2
local FLOOR_TOP = 0.2 -- 땅(y=0)보다 살짝 위 (z-fighting 방지)
local WALL_H = 3
local BARRIER_H = 14 -- 점프로 못 넘는 투명 벽 높이
local GAP = 12 -- 입구 너비
local PED_BASE_H = 0.6
local PED_TOP_H = 1.0
local PED_SURFACE = FLOOR_TOP + PED_BASE_H + PED_TOP_H
local SLOT_COLS = { -13.5, -4.5, 4.5, 13.5 }
local SLOT_ROWS = { -4, 4.5, 13 } -- 입구에 가까운 줄부터
local COLLECTOR_POS = Vector3.new(-12, 0, -13)
local LOCK_POS = Vector3.new(12, 0, -13)
local SPAWN_POS = Vector3.new(0, FLOOR_TOP + 0.5, -9)

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

local CLAIM_DEBOUNCE = 1
local ACTION_THROTTLE = 0.15

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
	LaserDoor: BasePart,
	Collector: BasePart,
	CollectorLabel: TextLabel,
	SpawnPoint: BasePart,
	SignLabels: { TextLabel },
	LockLabel: TextLabel,
	LockPrompt: ProximityPrompt,
	Pedestals: { Pedestal },
	ItemsFolder: Folder,
	Visuals: { [string]: Visual },
	LockedUntil: number,
	CooldownUntil: number,
	DoorLocked: boolean?,
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

-- 받침 있는 글자면 a, 없으면 b ("곰돌이가" / "아기 용이")
local function josa(name: string, a: string, b: string): string
	local last = nil
	for _, cp in utf8.codes(name) do
		last = cp
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 then
		if (last - 0xAC00) % 28 ~= 0 then
			return name .. a
		end
		return name .. b
	end
	return name .. b
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

local function now(): number
	return workspace:GetServerTimeNow()
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

local function slotLocalPos(slot: number): Vector3
	local row = math.floor((slot - 1) / #SLOT_COLS) + 1
	local col = (slot - 1) % #SLOT_COLS + 1
	return Vector3.new(SLOT_COLS[col], 0, SLOT_ROWS[row])
end

local function slotCFrameOf(plot: Plot, slot: number): CFrame
	local p = slotLocalPos(slot)
	return plot.Origin * CFrame.new(p.X, PED_SURFACE, p.Z)
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
	model:SetAttribute("LockedUntil", 0)

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
		-- 보이지 않는 높은 벽: 낮은 울타리를 점프로 넘으면 잠금이 소용없어서 입구로만 드나들게
		newPart({
			Name = "WallBarrier" .. i,
			Size = Vector3.new(size.X, BARRIER_H, size.Z),
			CFrame = origin * CFrame.new(pos.X, FLOOR_TOP + BARRIER_H / 2, pos.Z),
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
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
		label.Text = "빈 기지"
		label.Parent = sg
		sg.Parent = sign
		table.insert(signLabels, label)
	end

	-- 레이저 문
	local door = newPart({
		Name = "LaserDoor",
		Size = Vector3.new(GAP, 6.4, 0.4),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + 3.2, -HALF + 0.5),
		Color = Color3.fromRGB(255, 50, 70),
		Material = Enum.Material.Neon,
		Transparency = 0.92,
		CanCollide = false,
		CastShadow = false,
		Parent = model,
	})

	-- 받침대 12개
	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = model
	local pedestals: { Pedestal } = {}
	for slot = 1, Config.Plot.TotalSlots do
		local p = slotLocalPos(slot)
		local cf1, s1 = cylinder(origin, p.X, p.Z, FLOOR_TOP, PED_BASE_H, 5.4)
		local base = newPart({ Name = "PedestalBase" .. slot, CFrame = cf1, Size = s1, Shape = Enum.PartType.Cylinder, Parent = model })
		local cf2, s2 = cylinder(origin, p.X, p.Z, FLOOR_TOP + PED_BASE_H, PED_TOP_H, 4.6)
		local top = newPart({ Name = "Pedestal" .. slot, CFrame = cf2, Size = s2, Shape = Enum.PartType.Cylinder, Parent = model })
		top:SetAttribute("Slot", slot)
		local bb, label = makeBillboard(top, 2.2, 5, 1.6, 50)
		bb.Enabled = false
		local buy = makePrompt(top, "Owner", 0, "받침대 열기", "", 0.3, Enum.KeyCode.E)
		buy.Enabled = false
		pedestals[slot] = { Top = top, Base = base, Billboard = bb, Label = label, BuyPrompt = buy }
	end

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
	collectorLabel.TextColor3 = Color3.fromRGB(255, 235, 120)
	collectorLabel.Text = "💰 0 받기"

	-- 잠금 버튼
	local cfL, sL = cylinder(origin, LOCK_POS.X, LOCK_POS.Z, FLOOR_TOP, 0.8, 4.4)
	newPart({ Name = "LockButtonBase", CFrame = cfL, Size = sL, Shape = Enum.PartType.Cylinder, Color = WHITE, Parent = model })
	local cfB, sB = cylinder(origin, LOCK_POS.X, LOCK_POS.Z, FLOOR_TOP + 0.8, 0.6, 2.8)
	local button = newPart({
		Name = "LockButton",
		CFrame = cfB,
		Size = sB,
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(255, 80, 100),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local _, lockLabel = makeBillboard(button, 3, 6, 1.5, 50)
	lockLabel.Text = "🔒 잠그기"
	local lockPrompt = makePrompt(button, "Owner", 0, "기지 잠그기", "🔒", 0.3, Enum.KeyCode.E)
	lockPrompt.Enabled = false

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
		LaserDoor = door,
		Collector = collector,
		CollectorLabel = collectorLabel,
		SpawnPoint = spawn,
		SignLabels = signLabels,
		LockLabel = lockLabel,
		LockPrompt = lockPrompt,
		Pedestals = pedestals,
		ItemsFolder = items,
		Visuals = {},
		LockedUntil = 0,
		CooldownUntil = 0,
		DoorLocked = nil,
		LastClaim = 0,
		ShownPending = -1,
	}
	return plot
end

----------------------------------------------------------------------
-- 화면 갱신
----------------------------------------------------------------------
local function setSign(plot: Plot)
	local owner = plot.Owner
	local text = if owner then owner.DisplayName .. "의 기지" else "빈 기지"
	for _, label in plot.SignLabels do
		label.Text = text
	end
end

local function updatePedestals(plot: Plot)
	local owner = plot.Owner
	local data = owner and DataService.Get(owner)
	local unlocked = if data then data.SlotsUnlocked else Config.Plot.StartSlots
	local nextPrice = if data then Config.NextSlotPrice(unlocked) else nil
	local ownerId = if owner then owner.UserId else 0
	for slot, ped in plot.Pedestals do
		local state
		if slot <= unlocked then
			state = "open"
		elseif data and slot == unlocked + 1 and nextPrice then
			state = "next:" .. nextPrice .. ":" .. ownerId
		else
			state = "locked"
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
			if state ~= "locked" and nextPrice then
				ped.Label.Text = "🔒 💰" .. Config.FormatNumber(nextPrice)
				ped.Label.TextColor3 = Color3.fromRGB(255, 235, 120)
				ped.BuyPrompt.ObjectText = "💰" .. Config.FormatNumber(nextPrice)
				ped.BuyPrompt.Enabled = true
			else
				ped.Label.Text = "🔒"
				ped.Label.TextColor3 = Color3.new(1, 1, 1)
				ped.BuyPrompt.Enabled = false
			end
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

local function setDoor(plot: Plot, locked: boolean)
	if plot.DoorLocked == locked then
		return
	end
	plot.DoorLocked = locked
	plot.LaserDoor.CanCollide = locked
	plot.LaserDoor.Transparency = if locked then 0.35 else 0.92
end

local function updateLockLabel(plot: Plot)
	local t = now()
	if not plot.Owner then
		plot.LockLabel.Text = ""
	elseif t < plot.LockedUntil then
		plot.LockLabel.Text = "🔒 잠김 " .. math.ceil(plot.LockedUntil - t) .. "초"
	elseif t < plot.CooldownUntil then
		plot.LockLabel.Text = "⏳ " .. math.ceil(plot.CooldownUntil - t) .. "초 뒤 다시"
	else
		plot.LockLabel.Text = "🔒 잠그기"
	end
end

----------------------------------------------------------------------
-- 아이템 모델
----------------------------------------------------------------------
local function itemLabelText(item: any): string
	if item.Kind == "Pet" then
		local pet = Config.Pets[item.Id]
		return pet.Name .. "  💰" .. Config.FormatNumber(pet.Income) .. "/초"
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

local function onStealTriggered(plot: Plot, ownerAtBuild: Player, uid: string, thief: Player)
	if thief == ownerAtBuild or plot.Owner ~= ownerAtBuild then
		return
	end
	if PlotService.IsLocked(plot) then
		notify(thief, "기지가 잠겨 있어요! 🔒 조금 뒤에 다시 와요", "warn")
		return
	end
	local item = DataService.GetItem(ownerAtBuild, uid)
	if not item or item.Loc ~= "Slot" then
		return
	end
	local cb = PlotService.Callbacks.OnStealPrompt
	if cb then
		local ok, err = pcall(cb, thief, ownerAtBuild, uid)
		if not ok then
			warn("[PlotService] OnStealPrompt 오류:", err)
		end
	end
end

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
	local ok, model = pcall(function()
		if isPet then
			return PetModels.BuildPet(item.Id)
		end
		return PetModels.BuildEgg(item.Id)
	end)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		warn("[PlotService] 모델 만들기 실패:", item.Kind, item.Id, model)
		return
	end
	local m = model :: Model
	m.Name = (if isPet then "Pet_" else "Egg_") .. uid
	m:SetAttribute("ItemUid", uid)
	m:SetAttribute("OwnerUserId", player.UserId)
	m:SetAttribute("Kind", item.Kind)
	m:SetAttribute("Id", item.Id)
	if not isPet then
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

	-- 이름표
	local bb, label = makeBillboard(bodyPart, 3.2, 6, if isPet then 1.1 else 1.8, 40)
	bb.Name = "ItemTag"
	label.TextColor3 = Config.Rarities[rarity].Color
	label.Text = itemLabelText(item)

	-- 프롬프트
	local name = if isPet then Config.Pets[item.Id].Name else Config.Eggs[item.Id].Name
	local steal = makePrompt(bodyPart, "Steal", player.UserId, "훔치기", name, Config.Steal.HoldDuration, Enum.KeyCode.E)
	steal.Triggered:Connect(function(thief)
		onStealTriggered(plot, player, uid, thief)
	end)
	local own = makePrompt(bodyPart, "Owner", player.UserId, "가방에 넣기", name, 0.4, Enum.KeyCode.F)
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

function PlotService.IsLocked(plot: Plot): boolean
	return plot ~= nil and now() < plot.LockedUntil
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
	plot.LockPrompt:SetAttribute("OwnerUserId", ownerId)
	plot.LockPrompt.Enabled = ownerId ~= 0
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
		notify(player, "빈 기지가 없어요 😢", "warn")
		return nil
	end
	local p = plot :: Plot
	p.Owner = player
	plotByPlayer[player] = p
	p.LockedUntil = 0
	p.CooldownUntil = 0
	p.LastClaim = 0
	p.Model:SetAttribute("OwnerUserId", player.UserId)
	p.Model:SetAttribute("OwnerName", player.DisplayName)
	p.Model:SetAttribute("LockedUntil", 0)
	p.Model:SetAttribute("LockCooldownUntil", 0)
	player:SetAttribute("PlotIndex", p.Index)
	setPromptOwners(p, player.UserId)
	setDoor(p, false)
	for _, ped in p.Pedestals do
		ped.State = nil
	end
	PlotService.RefreshPlot(player)
	updateLockLabel(p)
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
	plot.LockedUntil = 0
	plot.CooldownUntil = 0
	plot.Model:SetAttribute("OwnerUserId", 0)
	plot.Model:SetAttribute("OwnerName", "")
	plot.Model:SetAttribute("LockedUntil", 0)
	plot.Model:SetAttribute("LockCooldownUntil", 0)
	if player.Parent then
		player:SetAttribute("PlotIndex", nil)
	end
	setPromptOwners(plot, 0)
	setDoor(plot, false)
	updatePedestals(plot)
	plot.ShownPending = -1
	updateCollector(plot)
	updateLockLabel(plot)
	setSign(plot)

	-- 빈 기지가 생겼으니 기지 없이 기다리던 사람에게 바로 배정
	for _, other in Players:GetPlayers() do
		if other ~= player and not plotByPlayer[other] and DataService.Get(other) then
			local assigned = PlotService.AssignPlot(other)
			if assigned then
				notify(other, "기지가 생겼어요! 🏠", "good")
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
-- 수금 / 잠금 / 받침대 구매
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

local function tryLock(player: Player)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	local t = now()
	if t < plot.LockedUntil then
		notify(player, "이미 잠겨 있어요! 🔒", "info")
		return
	end
	if t < plot.CooldownUntil then
		notify(player, math.ceil(plot.CooldownUntil - t) .. "초 뒤에 다시 잠글 수 있어요", "warn")
		return
	end
	plot.LockedUntil = t + Config.Plot.LockDuration
	plot.CooldownUntil = plot.LockedUntil + Config.Plot.LockCooldown
	plot.Model:SetAttribute("LockedUntil", plot.LockedUntil)
	plot.Model:SetAttribute("LockCooldownUntil", plot.CooldownUntil)
	setDoor(plot, true)
	updateLockLabel(plot)
	-- 잠글 때 안에 있던 다른 사람은 입구 밖으로 내보내기 (갇히지 않게)
	for _, other in game:GetService("Players"):GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if other ~= player and character and root and PlotService.GetPlotAt((root :: BasePart).Position) == plot then
			character:PivotTo(plot.Origin * CFrame.new(math.random(-4, 4), 3, -(HALF + 6)))
			notify(other, "기지가 잠겨서 밖으로 나왔어요! 🔒", "info")
		end
	end
	notify(player, "기지를 잠갔어요! 🔒 " .. Config.Plot.LockDuration .. "초 동안 안전해요", "good")
end

local function tryBuySlot(player: Player)
	local plot = plotByPlayer[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return
	end
	if data.SlotsUnlocked >= Config.Plot.TotalSlots then
		notify(player, "받침대를 모두 열었어요! 🎉", "info")
		return
	end
	local price = Config.NextSlotPrice(data.SlotsUnlocked)
	if not price then
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

local function itemName(item: any): string
	if item.Kind == "Pet" then
		return Config.Pets[item.Id].Name
	end
	return Config.Eggs[item.Id].Name
end

handlePetAction = function(player: Player, uid: any, action: any)
	if type(uid) ~= "string" or type(action) ~= "string" or #uid > 32 then
		return
	end
	local t = os.clock()
	if t - (lastAction[player] or 0) < ACTION_THROTTLE then
		return
	end
	lastAction[player] = t

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
			notify(player, "기지가 없어요 😢", "warn")
			return
		end
		local slot = PlotService.FreeSlot(player)
		if not slot then
			notify(player, "기지에 빈 자리가 없어요!", "warn")
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
		if wasLoc == "Follow" then
			refreshFollow(player)
		end
		notify(player, josa(name, "을", "를") .. " 기지에 놓았어요 🏠", "good")
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
		if wasLoc == "Follow" then
			refreshFollow(player)
		end
		notify(player, josa(name, "을", "를") .. " 가방에 넣었어요 🎒", "info")
	elseif action == "Sell" then
		if item.Kind ~= "Pet" then
			notify(player, "알은 팔 수 없어요!", "warn")
			return
		end
		local price = Config.SellPrice(item.Id)
		DataService.RemoveItem(player, uid)
		if wasLoc == "Slot" then
			PlotService.RemoveItemVisual(player, uid)
		elseif wasLoc == "Follow" then
			refreshFollow(player)
		end
		DataService.AddCoins(player, price)
		local hrp = rootPart(player)
		if hrp then
			Remotes.CoinFx:FireClient(player, price, hrp.Position + Vector3.new(0, 3, 0))
		end
		notify(player, josa(name, "을", "를") .. " 팔았어요! +💰" .. Config.FormatNumber(price), "good")
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
	local petId = Config.RollPet(eggId)
	local slot = item.Slot
	item.Kind = "Pet"
	item.Id = petId
	item.Loc = "Slot"
	item.HatchAt = nil
	item.HatchLeft = nil
	local isNew = DataService.MarkDiscovered(player, petId)
	local data = DataService.Get(player)
	if data then
		data.Stats.Hatched += 1
	end
	local pos = slotCFrameOf(plot, slot).Position + Vector3.new(0, 2, 0)
	Remotes.HatchFx:FireClient(player, petId, pos, isNew)
	PlotService.PlaceItem(player, uid)
	local pet = Config.Pets[petId]
	local rarityName = Config.Rarities[pet.Rarity].Name
	notify(player, "🎉 [" .. rarityName .. "] " .. josa(pet.Name, "이", "가") .. " 태어났어요!", "good")
	DataService.Sync(player)
end

local function tickPlot(plot: Plot)
	-- 잠금 상태 / 문
	local locked = PlotService.IsLocked(plot)
	local wasLocked = plot.DoorLocked
	setDoor(plot, locked)
	updateLockLabel(plot)

	local owner = plot.Owner
	if not owner then
		return
	end
	if wasLocked and not locked then
		notify(owner, "잠금이 풀렸어요 🔓", "info")
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
			income += Config.Pets[item.Id].Income
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
		data.Pending += income
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
			and math.abs(rel.Y) < 5
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
		updateLockLabel(plot)

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

		plot.LockPrompt.Triggered:Connect(function(player)
			if player == plot.Owner then
				tryLock(player)
			end
		end)

		for _, ped in plot.Pedestals do
			ped.BuyPrompt.Triggered:Connect(function(player)
				if player == plot.Owner then
					tryBuySlot(player)
				end
			end)
		end
	end

	Remotes.PetAction.OnServerEvent:Connect(function(player, uid, action)
		handlePetAction(player, uid, action)
	end)
	Remotes.BuySlot.OnServerEvent:Connect(function(player)
		local t = os.clock()
		if t - (lastAction[player] or 0) < ACTION_THROTTLE then
			return
		end
		lastAction[player] = t
		tryBuySlot(player)
	end)
	Remotes.LockBase.OnServerEvent:Connect(function(player)
		tryLock(player)
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
