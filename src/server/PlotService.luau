-- 집(플롯): 외형(바닥/벽/받침대/2층/간판/수금 패드)은 HouseBuilder 가 짓고, 여기서는 배정·수입/부화 틱·수금·구매(받침대/2층/테마)·펫 행동(PetAction)을 처리해요.
-- (설계: docs/DESIGN.md "PlotService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PetModels = require(ReplicatedStorage.Shared.PetModels)
local DataService = require(script.Parent.DataService)
local FollowService = require(script.Parent.FollowService)
local HouseBuilder = require(script.Parent.HouseBuilder)

local PlotService = {}

----------------------------------------------------------------------
-- 상수
----------------------------------------------------------------------
local HALF = Config.Layout.PlotSize / 2 -- 플롯 반 변 (GetPlotAt 의 사각형 판정용)
local SLOTS_PER_FLOOR = Config.Plot.SlotsPerFloor

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

export type Plot = {
	Index: number,
	Model: Model,
	Owner: Player?,
	Origin: CFrame,
	Handles: HouseBuilder.Handles, -- HouseBuilder.Build 결과 (House / 받침대 / Collector / SpawnPoint)
	Collector: BasePart, -- = Handles.Collector (플롯 모델 바로 아래. 다시 지어도 재사용돼요)
	CollectorLabel: TextLabel?, -- Collector > BillboardGui > "Amount"
	CollectorConn: RBXScriptConnection?, -- Collector.Touched (bindCollector 가 관리)
	SpawnPoint: BasePart, -- = Handles.SpawnPoint
	SignLabel: TextLabel?, -- House > Sign > BillboardGui > "OwnerLabel"
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

-- 받침대 윗면 (아이템이 놓이는 곳). 받침대 배치는 HouseBuilder 가 알아요
local function slotCFrameOf(plot: Plot, slot: number): CFrame
	return HouseBuilder.SlotCFrame(plot.Origin, slot)
end

-- Collector > BillboardGui > TextLabel "Amount" (HouseBuilder 가 만들어요)
local function collectorLabelOf(collector: BasePart): TextLabel?
	local bb = collector:FindFirstChildOfClass("BillboardGui")
	local label = if bb then bb:FindFirstChild("Amount") else nil
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

-- House > Sign > BillboardGui > TextLabel "OwnerLabel" (HouseBuilder 가 만들어요)
local function signLabelOf(house: Model): TextLabel?
	local sign = house:FindFirstChild("Sign", true)
	local bb = if sign then sign:FindFirstChildOfClass("BillboardGui") else nil
	local label = if bb then bb:FindFirstChild("OwnerLabel") else nil
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

----------------------------------------------------------------------
-- 화면 갱신 (간판 / 받침대 / 수금 패드 글자)
----------------------------------------------------------------------
local function setSign(plot: Plot)
	local label = plot.SignLabel
	if not label then
		return
	end
	local owner = plot.Owner
	label.Text = if owner then owner.DisplayName .. " 님의 집" else "빈 집"
end

-- 잠긴/열린 받침대 색과 가격표 (HouseBuilder 가 그려요). 빈 집은 시작 받침대 / 1층
local function updatePedestals(plot: Plot)
	local owner = plot.Owner
	local data = owner and DataService.Get(owner)
	local unlocked = if data then data.SlotsUnlocked else Config.Plot.StartSlots
	local floors = if data then data.Floors else 1
	HouseBuilder.UpdatePedestals(plot.Handles, unlocked, floors)
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
	local label = plot.CollectorLabel
	if label then
		label.Text = if pending > 0 then "💰 " .. Config.FormatNumber(pending) .. " 받기" else "💰 모으기"
	end
end

----------------------------------------------------------------------
-- 집 짓기 (외형은 HouseBuilder)
----------------------------------------------------------------------
local claim: (plot: Plot, player: Player) -> ()

-- 수금 패드 밟기 → 수금. 집을 지을 때마다 다시 연결해요 (HouseBuilder 는 Collector 를 재사용하지만, 바뀌어도 안전하게)
local function bindCollector(plot: Plot)
	if plot.CollectorConn then
		plot.CollectorConn:Disconnect()
		plot.CollectorConn = nil
	end
	plot.CollectorConn = plot.Collector.Touched:Connect(function(hit)
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

-- Build 결과를 플롯에 연결: 핸들, 수금 패드(+Touched), 스폰, 간판 글자, 수금 글자
local function applyHandles(plot: Plot, handles: HouseBuilder.Handles)
	plot.Handles = handles
	plot.Collector = handles.Collector
	plot.CollectorLabel = collectorLabelOf(handles.Collector)
	plot.SpawnPoint = handles.SpawnPoint
	plot.SignLabel = signLabelOf(handles.House)
	bindCollector(plot)
	setSign(plot)
	plot.ShownPending = -1
	updateCollector(plot)
end

-- 집을 (다시) 지어요. 받침대 위 아이템은 안 그려요 (필요하면 RefreshPlot)
local function rebuildHouse(plot: Plot, themeId: string, floors: number, slotsUnlocked: number)
	applyHandles(plot, HouseBuilder.Build(plot.Model, plot.Origin, themeId, floors, slotsUnlocked))
end

local function buildPlot(index: number, origin: CFrame, parent: Instance): Plot
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("Theme", "Basic")
	model:SetAttribute("Floors", 1)

	-- 아이템 폴더 (받침대 위 알/펫 모델). House 와 달리 집을 다시 지어도 남아요
	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = model

	-- 빈 집: 기본 테마, 1층, 시작 받침대만 열림
	local handles = HouseBuilder.Build(model, origin, "Basic", 1, Config.Plot.StartSlots)
	local plot: Plot = {
		Index = index,
		Model = model,
		Owner = nil,
		Origin = origin,
		Handles = handles,
		Collector = handles.Collector,
		CollectorLabel = nil,
		CollectorConn = nil,
		SpawnPoint = handles.SpawnPoint,
		SignLabel = nil,
		ItemsFolder = items,
		Visuals = {},
		LastClaim = 0,
		ShownPending = -1,
	}
	applyHandles(plot, handles)
	model.Parent = parent
	return plot
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

-- 주인의 Theme/Floors/받침대에 맞게 집을 다시 짓고 (HouseBuilder) 아이템을 다시 그려요
function PlotService.RebuildHouse(player: Player)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	local data = DataService.Get(player)
	local floors = if data then data.Floors else 1
	local themeId = if data then data.Theme else "Basic"
	local unlocked = if data then data.SlotsUnlocked else Config.Plot.StartSlots
	plot.Model:SetAttribute("Theme", themeId)
	plot.Model:SetAttribute("Floors", floors)
	rebuildHouse(plot, themeId, floors, unlocked)
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
	PlotService.RebuildHouse(player) -- 테마/층/받침대 반영 (HouseBuilder) + 아이템 그리기 + 간판
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
	-- 빈 집 모양으로 되돌려요 (기본 테마, 1층, 시작 받침대). 간판 "빈 집" / 수금 패드 글자도 초기화
	rebuildHouse(plot, "Basic", 1, Config.Plot.StartSlots)

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
claim = function(plot: Plot, player: Player)
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

local function tryBuySlot(player: Player)
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
	HouseBuilder.UpdatePedestals(plot.Handles, data.SlotsUnlocked, data.Floors)
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
		plots[i] = buildPlot(i, origin, plotsFolder)
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
