-- 집(플롯): 외형(바닥/벽/받침대/층/계단/엘리베이터/간판/수금 패드)은 HouseBuilder 가 짓고, 여기서는 배정·수입/부화 틱·수금·
-- 구매(받침대/층/테마)·환생·펫 행동(PetAction)·자동 배치(AutoPlace)·집 비우기(ClearBase)·★v7 나쁜 알 빼기(StashEgg)를 처리해요.
-- 🏦 자동 수금 버튼(설정 "AutoCollect")이 켜져 있으면 어디에 있든 몇 초마다 집 금고 코인을 조용히 받아요.
-- (설계: docs/DESIGN.md "PlotService", §7)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PetModels = require(ReplicatedStorage.Shared.PetModels)
local DataService = require(script.Parent.DataService)
local FollowService = require(script.Parent.FollowService)
local HouseBuilder = require(script.Parent.HouseBuilder)
local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout)

local PlotService = {}

----------------------------------------------------------------------
-- 상수
----------------------------------------------------------------------
local HALF = Config.Layout.PlotSize / 2 -- 플롯 반 변 (GetPlotAt 의 사각형 판정용)
local SLOTS_PER_FLOOR = Config.Plot.SlotsPerFloor
local TOTAL_SLOTS = Config.Plot.TotalSlots

local CLAIM_DEBOUNCE = 1
local AUTO_COLLECT_EVERY = 3 -- 자동 수금 간격 (초)
local AUTO_FX_RANGE = 120 -- 집 근처에 있을 때만 수금 패드 위에 "+N 💰" (소리 없이)
local ACTION_THROTTLE = 0.15
local EFFECT_MIN_ORDER = 5 -- 받침대/타기 펫 희귀도 효과: 전설 이상 (반짝이가 너무 많아지지 않게)

local rng = Random.new()

----------------------------------------------------------------------
-- 상태
----------------------------------------------------------------------
type Visual = {
	Model: Model,
	Kind: string,
	Slot: number,
	HatchAt: number?,
	Label: TextLabel?,
}

export type Plot = {
	Index: number,
	Model: Model,
	Owner: Player?,
	Origin: CFrame,
	Theme: string, -- 지금 지어진 집 테마 (받침대 위치가 이 테마를 따라요)
	Floors: number, -- 지금 지어진 층 수
	Handles: HouseBuilder.Handles, -- HouseBuilder.Build 결과 (House / 받침대 / Collector / SpawnPoint / 엘리베이터)
	Collector: BasePart, -- = Handles.Collector (플롯 모델 바로 아래. 다시 지어도 재사용돼요)
	CollectorLabel: TextLabel?, -- Collector > BillboardGui > "Amount"
	CollectorConn: RBXScriptConnection?, -- Collector.Touched (bindCollector 가 관리)
	SpawnPoint: BasePart, -- = Handles.SpawnPoint
	SignLabel: TextLabel?, -- House > Sign > BillboardGui > "OwnerLabel"
	ItemsFolder: Folder,
	Visuals: { [string]: Visual },
	LastClaim: number,
	LastAutoClaim: number, -- 마지막 자동 수금 (os.clock)
	ShownPending: number,
	ShownAuto: boolean?, -- 수금 패드 글자가 "자동 수금 중" 인가
}

export type PlotChangeReason = "Assign" | "Rebuild" | "Release"
type PlotListener = (player: Player, plot: Plot, reason: PlotChangeReason) -> ()

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}
local lastAction: { [Player]: number } = {}
local listeners: { PlotListener } = {}
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

local function rarityOrder(rarity: string?): number
	local info = if rarity then Config.Rarities[rarity] else nil
	return if info then info.Order else 0
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

-- 플레이어 머리 위 (합성 이펙트 등). 캐릭터가 없으면 집 수금 패드 / 원점
local function effectPosition(player: Player): Vector3
	local hrp = rootPart(player)
	if hrp then
		return hrp.Position + Vector3.new(0, 3, 0)
	end
	local plot = plotByPlayer[player]
	if plot then
		return plot.Collector.Position + Vector3.new(0, 3, 0)
	end
	return Vector3.zero
end

-- 받침대 윗면 (아이템이 놓이는 곳). 받침대 배치는 테마 크기에 따라 HouseBuilder(HouseLayout) 가 알아요
local function slotCFrameOf(plot: Plot, slot: number): CFrame
	return HouseBuilder.SlotCFrame(plot.Origin, slot, plot.Theme)
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

-- 집이 바뀌었다고 알려요 (ShopService: 가구 검사/다시 그리기). 듣는 쪽 오류는 여기서 멈춰요
local function fireChanged(player: Player, plot: Plot, reason: PlotChangeReason)
	for _, fn in table.clone(listeners) do
		local ok, err = pcall(fn, player, plot, reason)
		if not ok then
			warn("[PlotService] OnPlotChanged 오류 (" .. reason .. "):", err)
		end
	end
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

-- 자동 수금 버튼이 켜져 있나
local function autoOn(player: Player?): boolean
	return player ~= nil and DataService.GetSetting(player, "AutoCollect")
end

local function updateCollector(plot: Plot)
	local owner = plot.Owner
	local data = owner and DataService.Get(owner)
	local pending = if data then math.floor(data.Pending) else 0
	local auto = data ~= nil and autoOn(owner)
	if pending == plot.ShownPending and auto == plot.ShownAuto then
		return
	end
	plot.ShownPending = pending
	plot.ShownAuto = auto
	plot.Collector:SetAttribute("Pending", pending)
	local label = plot.CollectorLabel
	if label then
		label.Text = if auto
			then "🏦 자동 수금 중"
			elseif pending > 0 then "💰 " .. Config.FormatNumber(pending) .. " 받기"
			else "💰 모으기"
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

-- 엘리베이터 프롬프트 주인 확인 (HouseBuilder 가 지을 때 OwnerUserId 를 읽지만, 혹시 몰라 한 번 더 맞춰요).
-- 누르면 서버는 아무것도 안 해요: 클라이언트가 층 고르기 창을 열어요 (§6)
local function syncElevatorOwner(plot: Plot, handles: HouseBuilder.Handles)
	local elevators = (handles :: any).Elevators
	if type(elevators) ~= "table" then
		return
	end
	local ownerId = plot.Model:GetAttribute("OwnerUserId") or 0
	for _, part in elevators do
		if typeof(part) == "Instance" then
			for _, d in part:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					d:SetAttribute("PromptKind", "Owner")
					d:SetAttribute("OwnerUserId", ownerId)
				end
			end
		end
	end
end

-- Build 결과를 플롯에 연결: 핸들, 수금 패드(+Touched), 스폰, 간판 글자, 수금 글자
local function applyHandles(plot: Plot, handles: HouseBuilder.Handles)
	plot.Handles = handles
	plot.Collector = handles.Collector
	plot.CollectorLabel = collectorLabelOf(handles.Collector)
	plot.SpawnPoint = handles.SpawnPoint
	plot.SignLabel = signLabelOf(handles.House)
	syncElevatorOwner(plot, handles)
	bindCollector(plot)
	setSign(plot)
	plot.ShownPending = -1
	plot.ShownAuto = nil
	updateCollector(plot)
end

-- 플롯 모델 속성 (Theme / Floors / ThemeSize). OwnerUserId 는 부르는 쪽이 짓기 전에 맞춰요
local function setHouseAttributes(model: Model, themeId: string, floors: number)
	model:SetAttribute("Theme", themeId)
	model:SetAttribute("Floors", floors)
	model:SetAttribute("ThemeSize", Config.ThemeSize(themeId))
end

-- 집을 (다시) 지어요. 받침대 위 아이템은 안 그려요 (필요하면 RefreshPlot)
local function buildHouse(plot: Plot, themeId: string, floors: number, slotsUnlocked: number)
	local theme = if Config.House.Themes[themeId] then themeId else "Basic"
	local floorCount = math.clamp(math.floor(floors), 1, Config.House.MaxFloors)
	plot.Theme = theme
	plot.Floors = floorCount
	setHouseAttributes(plot.Model, theme, floorCount)
	applyHandles(plot, HouseBuilder.Build(plot.Model, plot.Origin, theme, floorCount, slotsUnlocked))
end

local function buildPlot(index: number, origin: CFrame, parent: Instance): Plot
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	setHouseAttributes(model, "Basic", 1)

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
		Theme = "Basic",
		Floors = 1,
		Handles = handles,
		Collector = handles.Collector,
		CollectorLabel = nil,
		CollectorConn = nil,
		SpawnPoint = handles.SpawnPoint,
		SignLabel = nil,
		ItemsFolder = items,
		Visuals = {},
		LastClaim = 0,
		LastAutoClaim = 0,
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
		local sizeLabel = Config.SizeLabel(Config.SizeOf(item), item.Id)
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

-- ★v7 받침대 펫이 들어가는 가장 큰 모델 배율 (배율 1 모델을 재요). 이웃 받침대와는 가운데 선까지
-- (가로/세로 중 더 먼 쪽으로 나눠서 양쪽 펫이 같은 선을 써요 → 둘 다 커져도 안 겹쳐요), 벽·계단 유리는 안쪽 면까지,
-- 위로는 천장(층 사이 11) - 받침대 - 살랑살랑 흔들림까지. 보통 펫은 Config.PetDisplayScale 이 v6 크기 그대로 둬요
local SLOT_UP = Config.House.FloorHeight - HouseLayout.SLAB_T - HouseLayout.PED_H - 0.5 -- 받침대 윗면 → 천장 (8.9)
local SLOT_TAG_TOP = SLOT_UP - 0.3 -- 이름표 가운데는 받침대 윗면 위 이만큼까지 (천장 속에 안 묻히게)
local function slotFit(plot: Plot, slot: number, m: Model): number?
	local L = HouseLayout.Get(plot.Theme)
	local me = L.Slots[(slot - 1) % #L.Slots + 1]
	if not me then
		return nil
	end
	local lo, hi = PetModels.PivotBounds(m) -- 모델 상자 (피벗 기준, 배율 1)
	-- 자리마다 남은 거리 (왼 -X / 오른 +X / 앞 -Z / 뒤 +Z)
	local inner = L.Inner
	local rightWall = if me.X < L.Stair.GlassX then L.Stair.GlassX else inner.MaxX
	local left, right, front, back = me.X - inner.MinX, rightWall - me.X, me.Z - inner.MinZ, inner.MaxZ - me.Z
	for _, o in L.Slots do
		if o ~= me then
			local dx, dz = o.X - me.X, o.Z - me.Z
			if math.abs(dx) >= math.abs(dz) then
				if dx > 0 then
					right = math.min(right, dx / 2)
				else
					left = math.min(left, -dx / 2)
				end
			elseif dz > 0 then
				back = math.min(back, dz / 2)
			else
				front = math.min(front, -dz / 2)
			end
		end
	end
	local function k(space: number, ext: number): number
		return if ext > 0.05 then math.max(space, 0) / ext else math.huge
	end
	return math.min(k(left, -lo.X), k(right, hi.X), k(front, -lo.Z), k(back, hi.Z), k(SLOT_UP, hi.Y))
end

-- 받침대 위 알/펫 모델을 (다시) 그려요. 펫은 Body 를 받침대에 고정(Anchored)하고 Bob = true:
-- 서버는 절대 움직이지 않고, 살랑살랑은 클라이언트(WorldFx)가 해요
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
	if slot < 1 or slot > TOTAL_SLOTS then
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
	local acc = if isPet then item.Acc else nil
	local ok, model = pcall(function()
		if isPet then
			return PetModels.BuildPet(item.Id, tier, acc)
		end
		return PetModels.BuildEgg(item.Id)
	end)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		warn("[PlotService] 모델 만들기 실패:", item.Kind, item.Id, model)
		return
	end
	local m = model :: Model
	local size = if isPet then Config.SizeOf(item) else 1
	local scale = 1 -- ★v7 보이는 크기 (희귀 펫은 더 크게, 받침대 자리에 맞게)
	if isPet then
		-- 크기 (피벗 = 바닥 중심이라 받침대 위에 그대로 앉아요. 옷도 같이 커져요)
		local okFit, fit = pcall(slotFit, plot, slot, m)
		scale = Config.PetDisplayScale(item, "Slot", if okFit then fit else nil)
		pcall(function()
			m:ScaleTo(scale)
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
		m:SetAttribute("Acc", acc)
		m:SetAttribute("Bob", true)
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
	m.PrimaryPart = bodyPart
	local rarity = if isPet then Config.Pets[item.Id].Rarity else Config.Eggs[item.Id].Rarity
	if isPet and rarityOrder(rarity) >= EFFECT_MIN_ORDER then
		pcall(PetModels.AddRarityEffects, m, rarity)
	end
	-- Body 만 고정, 나머지는 용접된 채로 (클라이언트가 Body 를 움직이면 같이 움직여요)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == bodyPart
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	m:PivotTo(slotCFrameOf(plot, slot))

	-- 이름표 (브론즈 이상은 등급 색). 큰 펫은 조금 더 위에 (★v7 천장 속에는 안 묻히게)
	local tagY = 3.2 * scale
	if isPet then
		tagY = math.min(tagY, math.max(SLOT_TAG_TOP - (bodyPart.Position.Y - m:GetPivot().Position.Y), 1))
	end
	local bb, label = makeBillboard(bodyPart, tagY, 6, if isPet then 1.1 else 1.8, 40)
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

	plot.Visuals[uid] = {
		Model = m,
		Kind = item.Kind,
		Slot = slot,
		HatchAt = item.HatchAt,
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

-- 주인 데이터(Theme/Floors/받침대)대로 집을 짓고 아이템을 다시 그려요 (알림 없음)
local function rebuildOwned(player: Player, plot: Plot)
	local data = DataService.Get(player)
	local floors = if data then data.Floors else 1
	local themeId = if data then data.Theme else "Basic"
	local unlocked = if data then data.SlotsUnlocked else Config.Plot.StartSlots
	buildHouse(plot, themeId, floors, unlocked)
	PlotService.RefreshPlot(player)
end

-- 주인의 Theme/Floors/받침대에 맞게 집을 다시 짓고 (HouseBuilder) 아이템을 다시 그려요 → OnPlotChanged "Rebuild"
function PlotService.RebuildHouse(player: Player)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	rebuildOwned(player, plot)
	fireChanged(player, plot, "Rebuild")
end

-- 집이 바뀔 때 알려 줘요: "Assign" (집 받음, 다 지은 뒤), "Rebuild" (다시 지은 뒤), "Release" (비우기 직전).
-- 돌려주는 함수를 부르면 그만 들어요
function PlotService.OnPlotChanged(fn: PlotListener): () -> ()
	table.insert(listeners, fn)
	return function()
		local i = table.find(listeners, fn)
		if i then
			table.remove(listeners, i)
		end
	end
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
	for slot = 1, math.min(data.SlotsUnlocked, TOTAL_SLOTS) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

-- 받침대 윗면 월드 CFrame (주인 집 테마 기준). 집이 없으면 로비
function PlotService.GetSlotCFrame(player: Player, slot: number): CFrame
	local plot = plotByPlayer[player]
	if not plot then
		return CFrame.new(Config.Layout.LobbySpawn + Vector3.new(0, 3, 0))
	end
	local s = math.clamp(math.floor(tonumber(slot) or 1), 1, TOTAL_SLOTS)
	return slotCFrameOf(plot, s)
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
	-- 주인 속성은 짓기 전에 (HouseBuilder 가 엘리베이터 프롬프트에 OwnerUserId 를 넣어요)
	p.Model:SetAttribute("OwnerUserId", player.UserId)
	p.Model:SetAttribute("OwnerName", player.DisplayName)
	player:SetAttribute("PlotIndex", p.Index)
	rebuildOwned(player, p) -- 테마/층/받침대 반영 (HouseBuilder) + 아이템 그리기 + 간판
	fireChanged(player, p, "Assign")
	return p
end

function PlotService.ReleasePlot(player: Player)
	local plot = plotByPlayer[player]
	lastAction[player] = nil
	if not plot then
		return
	end
	-- 비우기 전에 알려요 (ShopService 가 가구 폴더를 치워요)
	fireChanged(player, plot, "Release")
	plotByPlayer[player] = nil
	for uid, v in plot.Visuals do
		plot.Visuals[uid] = nil
		destroyVisual(v)
	end
	plot.Owner = nil
	plot.Model:SetAttribute("OwnerUserId", 0)
	plot.Model:SetAttribute("OwnerName", "")
	if player.Parent then
		player:SetAttribute("PlotIndex", nil)
	end
	-- 빈 집 모양으로 되돌려요 (기본 테마, 1층, 시작 받침대). 간판 "빈 집" / 수금 패드 글자도 초기화
	buildHouse(plot, "Basic", 1, Config.Plot.StartSlots)

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
-- 수금 / 받침대 구매 / 층 / 테마 / 환생
----------------------------------------------------------------------
claim = function(plot: Plot, player: Player)
	if plot.Owner ~= player or autoOn(player) then
		return -- 자동 수금이 켜져 있으면 틱이 조용히 받아요
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
	DataService.AddCoins(player, amount) -- 코인만 바뀌어서 CoinSync 로 충분해요
	Remotes.CoinFx:FireClient(player, amount, plot.Collector.Position + Vector3.new(0, 3, 0))
	notify(player, "💰 " .. Config.FormatNumber(amount) .. " 코인을 받았어요!", "good")
	updateCollector(plot)
end

-- 🏦 자동 수금: 수금 패드를 밟은 것과 같은 결과 (코인 + 패드 글자), 알림 말풍선·소리 없이 조용히
local function autoCollect(plot: Plot, player: Player)
	if plot.Owner ~= player then
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
	plot.LastAutoClaim = os.clock()
	data.Pending -= amount
	DataService.AddCoins(player, amount)
	local hrp = rootPart(player)
	local pos = plot.Collector.Position + Vector3.new(0, 3, 0)
	if hrp and (hrp.Position - pos).Magnitude < AUTO_FX_RANGE then
		Remotes.CoinFx:FireClient(player, amount, pos, true)
	end
	updateCollector(plot)
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

local function notEnoughCoins(player: Player, price: number)
	notify(player, "코인이 부족해요! 💰" .. Config.FormatNumber(price) .. " 필요해요", "warn")
end

local function tryBuySlot(player: Player)
	local plot = plotByPlayer[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return
	end
	local price = Config.NextSlotPrice(data.SlotsUnlocked, data.Floors)
	if not price then
		if data.SlotsUnlocked >= TOTAL_SLOTS then
			notify(player, "받침대가 최대예요! 🎉", "info")
		elseif data.SlotsUnlocked >= data.Floors * SLOTS_PER_FLOOR then
			notify(player, (data.Floors + 1) .. "층을 먼저 올려야 해요! 🏠", "warn")
		else
			notify(player, "지금은 받침대를 살 수 없어요", "warn")
		end
		return
	end
	if not DataService.TrySpend(player, price) then
		notEnoughCoins(player, price)
		return
	end
	data.SlotsUnlocked = math.min(data.SlotsUnlocked + 1, data.Floors * SLOTS_PER_FLOOR, TOTAL_SLOTS)
	HouseBuilder.UpdatePedestals(plot.Handles, data.SlotsUnlocked, data.Floors)
	notify(player, "새 받침대가 열렸어요! 🎉", "good")
	DataService.Sync(player)
end

-- 다음 층 올리기 (§5 BuyFloor, §7 Floors): 아래층 받침대 전부 + 환생 수 + 가격. 새 층 첫 6개는 무료
local function tryBuyFloor(player: Player)
	local plot = plotByPlayer[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return
	end
	local nextFloor = data.Floors + 1
	local ok, reason = Config.CanBuyFloor(data.Floors, data.SlotsUnlocked, data.Rebirths)
	if not ok then
		if reason == "Max" then
			notify(player, "이미 " .. Config.House.MaxFloors .. "층이에요! 🏰", "info")
		elseif reason == "Slots" then
			notify(player, "받침대 " .. (data.Floors * SLOTS_PER_FLOOR) .. "개를 먼저 다 열어야 해요!", "warn")
		elseif reason == "Rebirth" then
			local req = Config.FloorRequirement(nextFloor)
			local need = if req then req.MinRebirth else 0
			notify(player, "🔄 환생 " .. need .. "회가 필요해요!", "warn")
		else
			notify(player, "지금은 층을 올릴 수 없어요", "warn")
		end
		return
	end
	local req = Config.FloorRequirement(nextFloor)
	if not req then
		return
	end
	local price = tonumber(req.Price) or 0
	if not DataService.TrySpend(player, price) then
		notEnoughCoins(player, price)
		return
	end
	data.Floors = nextFloor
	data.SlotsUnlocked = math.max(data.SlotsUnlocked, Config.FloorStartSlots(nextFloor))
	PlotService.RebuildHouse(player)
	notify(player, "🏠 " .. nextFloor .. "층이 생겼어요!", "good")
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
			notEnoughCoins(player, price)
			return
		end
		data.Themes[themeId] = true
		notify(player, "🎨 " .. theme.Name .. " 테마를 샀어요!", "good")
	elseif data.Theme == themeId then
		notify(player, "이미 " .. theme.Name .. " 테마예요!", "info")
		return
	end
	data.Theme = themeId
	-- 집 크기가 바뀌어요 → OnPlotChanged "Rebuild" 에서 ShopService 가 안 맞는 가구를 가구 가방으로 돌려보내요
	PlotService.RebuildHouse(player)
	notify(player, "🏠 " .. josaRo(theme.Name) .. " 꾸몄어요!", "good")
	DataService.Sync(player)
end

-- 환생: 코인(수금 대기 포함)을 0으로 돌리고 영구 보너스. 펫·집·받침대·테마·옷·가구는 그대로. 새 지역/층이 열리면 알려요
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
	-- 이번 환생으로 새로 열린 지역 / 올릴 수 있게 된 층
	for _, zone in Config.Zones do
		if zone.MinRebirth == r then
			notify(player, "🗺 새 지역 " .. josa(zone.Name, "이", "가") .. " 열렸어요!", "good")
		end
	end
	for f = 2, Config.House.MaxFloors do
		local req = Config.FloorRequirement(f)
		if req and req.MinRebirth == r and f > data.Floors then
			notify(player, "🏗 이제 " .. f .. "층까지 올릴 수 있어요!", "good")
		end
	end
	DataService.Sync(player)
end

----------------------------------------------------------------------
-- 자동 배치 / 집 비우기 (§7)
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

-- 가방 + 받침대 펫 중 가장 좋은 펫들을 받침대에 (알 있는 받침대는 그대로, 따라옴/타기/들기는 안 건드려요)
local function tryAutoPlace(player: Player)
	local plot = plotByPlayer[player]
	local data = DataService.Get(player)
	if not data then
		return
	end
	if not plot then
		notify(player, "집이 없어요 😢", "warn")
		return
	end
	local unlocked = math.min(data.SlotsUnlocked, TOTAL_SLOTS)
	local eggSlots: { [number]: boolean } = {}
	for _, item in data.Items do
		if item.Loc == "Slot" and item.Kind == "Egg" and type(item.Slot) == "number" then
			eggSlots[item.Slot :: number] = true
		end
	end
	local open: { number } = {}
	for s = 1, unlocked do
		if not eggSlots[s] then
			table.insert(open, s)
		end
	end
	if #open == 0 then
		notify(player, "빈 받침대가 없어요! 알이 부화하면 다시 해 보세요 🥚", "warn")
		return
	end
	local cands = DataService.GetItemsSorted(player, function(_, item)
		return item.Kind == "Pet" and (item.Loc == "Bag" or item.Loc == "Slot")
	end)
	if #cands == 0 then
		notify(player, "집에 놓을 펫이 없어요! 🐣", "info")
		return
	end
	local best: { [string]: boolean } = {}
	for i = 1, math.min(#open, #cands) do
		best[cands[i].Uid] = true
	end

	-- 1) best 가 아닌 받침대 펫 → 가방. best 인 받침대 펫은 그 자리에 그대로
	local taken: { [number]: boolean } = {}
	for _, entry in cands do
		local item = entry.Item
		if item.Loc == "Slot" then
			if best[entry.Uid] then
				if type(item.Slot) == "number" then
					taken[item.Slot :: number] = true
				end
			else
				PlotService.RemoveItemVisual(player, entry.Uid)
				item.Loc = "Bag"
				item.Slot = nil
			end
		end
	end

	-- 2) best 인 가방 펫 → 남은 빈 받침대 (번호 작은 순, 좋은 펫부터)
	local placed = 0
	local oi = 1
	for _, entry in cands do
		local item = entry.Item
		if best[entry.Uid] and item.Loc == "Bag" then
			while oi <= #open and taken[open[oi]] do
				oi += 1
			end
			if oi > #open then
				break
			end
			local s = open[oi]
			oi += 1
			taken[s] = true
			item.Loc = "Slot"
			item.Slot = s
			PlotService.PlaceItem(player, entry.Uid)
			placed += 1
		end
	end

	if placed > 0 then
		notify(player, "✨ 가장 좋은 펫 " .. placed .. "마리를 집에 놓았어요!", "good")
	else
		notify(player, "이미 가장 좋은 펫들이 집에 있어요! 😊", "info")
	end
	DataService.Sync(player)
end

-- 받침대 펫(알 제외)을 모두 가방으로. 약한 펫부터, 가방이 차면 멈춰요
local function tryClearBase(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local pets = DataService.GetItemsSorted(player, function(_, item)
		return item.Kind == "Pet" and item.Loc == "Slot"
	end)
	if #pets == 0 then
		notify(player, "집에 펫이 없어요", "info")
		return
	end
	local space = DataService.BagSpace(player)
	local moved = 0
	for i = #pets, 1, -1 do
		if moved >= space then
			break
		end
		local entry = pets[i]
		PlotService.RemoveItemVisual(player, entry.Uid)
		entry.Item.Loc = "Bag"
		entry.Item.Slot = nil
		moved += 1
	end
	if moved == 0 then
		notify(player, "가방이 가득 찼어요! 🎒", "warn")
		return
	end
	if moved < #pets then
		notify(player, "가방이 가득 차서 " .. moved .. "마리만 넣었어요! 🎒", "warn")
	else
		notify(player, "📦 펫 " .. moved .. "마리를 가방에 넣었어요", "good")
	end
	DataService.Sync(player)
end

-- ★v7 "🥚 나쁜 알 빼기" (Remotes.StashEgg): 새 알을 살 자리 만들기. 빈 받침대가 있으면 말만 하고,
-- 없으면 받침대 위 가장 나쁜 알 하나를 가방으로 (부화 시간은 ToBag 처럼 멈춰요: HatchLeft).
-- 나쁜 알 순서: 보통 알 먼저 (희귀 알은 마지막) → 희귀도 낮은 알 → 싼 알 → 부화까지 오래 남은 알.
-- 받침대에 알이 없으면 가장 약한 펫 (Config.ItemIncome 작은 펫, CompareItems 맨 뒤) 을 빼요
local function eggWorse(a: DataService.Item, b: DataService.Item): boolean
	local sa, sb = Config.IsSpecialEgg(a.Id), Config.IsSpecialEgg(b.Id)
	if sa ~= sb then
		return not sa
	end
	local ea, eb = Config.Eggs[a.Id], Config.Eggs[b.Id]
	local oa, ob = rarityOrder(ea and ea.Rarity), rarityOrder(eb and eb.Rarity)
	if oa ~= ob then
		return oa < ob
	end
	local pa, pb = if ea then ea.Price else 0, if eb then eb.Price else 0
	if pa ~= pb then
		return pa < pb
	end
	return (a.HatchAt or 0) > (b.HatchAt or 0)
end

local function tryStashEgg(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	if not plotByPlayer[player] then
		notify(player, "집이 없어요 😢", "warn")
		return
	end
	if PlotService.FreeSlot(player) then
		notify(player, "이미 빈 받침대가 있어요! 알을 살 수 있어요 🥚", "info")
		return
	end
	if DataService.BagSpace(player) <= 0 then
		notify(player, "가방이 가득 찼어요! 🎒 가방을 조금 비워 주세요", "warn")
		return
	end
	local worstUid: string? = nil
	local worst: DataService.Item? = nil
	for uid, item in data.Items do
		if item.Kind == "Egg" and item.Loc == "Slot" then
			if not worst or eggWorse(item, worst) or (not eggWorse(worst, item) and uid < (worstUid :: string)) then
				worstUid, worst = uid, item
			end
		end
	end
	if worstUid and worst then
		local name = itemName(worst)
		PlotService.RemoveItemVisual(player, worstUid)
		worst.HatchLeft = math.max(0, (worst.HatchAt or os.time()) - os.time())
		worst.HatchAt = nil
		worst.Loc = "Bag"
		worst.Slot = nil
		notify(player, "📦 " .. josa(name, "을", "를") .. " 가방에 넣었어요! 이제 새 알을 살 수 있어요", "good")
		DataService.Sync(player)
		return
	end
	local pets = DataService.GetItemsSorted(player, function(_, item)
		return item.Kind == "Pet" and item.Loc == "Slot"
	end)
	local entry = pets[#pets]
	if not entry then
		notify(player, "집 받침대에 뺄 알이 없어요 🥚", "info")
		return
	end
	local name = itemName(entry.Item)
	PlotService.RemoveItemVisual(player, entry.Uid)
	entry.Item.Loc = "Bag"
	entry.Item.Slot = nil
	notify(player, "📦 알이 없어서 가장 약한 " .. josa(name, "을", "를") .. " 가방에 넣었어요! 이제 알을 살 수 있어요", "good")
	DataService.Sync(player)
end

----------------------------------------------------------------------
-- 펫 행동 (PetAction)
----------------------------------------------------------------------

-- loc 에 있는 다른 펫을 가방으로 (타기/들기는 한 마리만). 옮긴 수
local function bagOthersAt(data: DataService.Data, loc: string, exceptUid: string): number
	local n = 0
	for otherUid, other in data.Items do
		if otherUid ~= exceptUid and other.Loc == loc then
			other.Loc = "Bag"
			other.Slot = nil
			n += 1
		end
	end
	return n
end

local function hasOtherAt(data: DataService.Data, loc: string, exceptUid: string): boolean
	for otherUid, other in data.Items do
		if otherUid ~= exceptUid and other.Loc == loc then
			return true
		end
	end
	return false
end

-- 합성 (§7): 누른 펫은 가방/따라옴/타기/들기만. 재료 = DataService.FusableUids (받침대 펫은 절대 안 써요)
local function fuse(player: Player, data: DataService.Data, uid: string, item: DataService.Item): boolean
	if item.Kind ~= "Pet" then
		notify(player, "알은 합성할 수 없어요!", "warn")
		return false
	end
	if not Config.CanFuseLoc(item.Loc) then
		notify(player, "🏠 집에 있는 펫은 합성할 수 없어요! 가방에 넣고 해 보세요 🎒", "warn")
		return false
	end
	local tier = tierOf(item.Tier)
	if tier >= Config.MaxTier then
		notify(player, "이미 최고 등급이에요! 🌌", "info")
		return false
	end
	-- 같은 펫·같은 등급 (가방 → 따라옴 → 들기 → 타기, 오래된 것부터)
	local others: { string } = {}
	for _, cuid in DataService.FusableUids(player, item.Id, tier) do
		if cuid ~= uid then
			table.insert(others, cuid)
		end
	end
	local have = #others + 1
	if have < Config.FuseCount then
		notify(player, "같은 펫 " .. Config.FuseCount .. "마리가 필요해요! (" .. have .. "/" .. Config.FuseCount .. ")", "warn")
		return false
	end
	local consumed = { uid }
	for i = 1, Config.FuseCount - 1 do
		table.insert(consumed, others[i])
	end
	local newTier = tier + 1
	-- 크기: 합친 펫 중 가장 큰 크기 + 0.02 (그 펫의 최대까지, ★v7 희귀 펫은 범위가 넓어요)
	local sizeRange = Config.PetSizeRange(item.Id)
	local maxSize = sizeRange.Min
	for _, cuid in consumed do
		maxSize = math.max(maxSize, Config.SizeOf(data.Items[cuid]))
	end
	local newSize = math.floor(math.min(maxSize + 0.02, sizeRange.Max) * 100 + 0.5) / 100
	-- 새 펫은 누른 펫 자리에 (따라옴 / 타기 / 들기 / 가방), 옷도 그대로
	local wasLoc = item.Loc
	local newItem: DataService.Item = { Kind = "Pet", Id = item.Id, Tier = newTier, Size = newSize, Acc = item.Acc, Loc = wasLoc }
	local needFollow = isMounted(wasLoc)
	for _, cuid in consumed do
		local removed = DataService.RemoveItem(player, cuid)
		if removed and isMounted(removed.Loc) then
			needFollow = true
		end
	end
	DataService.AddItem(player, newItem)
	local isNew = DataService.MarkDiscovered(player, item.Id, newTier)
	data.Stats.Fused += 1
	if needFollow then
		refreshFollow(player)
	end
	Remotes.HatchFx:FireClient(player, item.Id, effectPosition(player), isNew, newTier, "Fuse", newSize)
	local newName = Config.PetDisplayName(item.Id, newTier)
	-- 🆕 = 도감에 처음 (부화 화면을 숨긴 아이도 알 수 있게 말풍선에도 적어요)
	notify(player, (if isNew then "🆕 NEW! " else "") .. "✨ 합성 성공! " .. josa(newName, "이", "가") .. " 되었어요!", "good")
	return true
end

handlePetAction = function(player: Player, uid: any, action: any)
	if type(uid) ~= "string" or type(action) ~= "string" or #uid > 32 or #action > 32 then
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
		if DataService.BagSpace(player) <= 0 then
			notify(player, "가방이 가득 찼어요! 🎒", "warn")
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
		if DataService.BagSpace(player) <= 0 then
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
	elseif action == "Ride" or action == "Hold" then
		local riding = action == "Ride"
		if item.Kind ~= "Pet" then
			notify(player, if riding then "알은 탈 수 없어요!" else "알은 들 수 없어요!", "warn")
			return
		end
		if wasLoc == action then
			return
		end
		-- 타던/들던 펫은 가방으로 (한 마리만). 새 펫이 가방에서 오는 게 아니면 가방 칸이 1 필요해요
		if wasLoc ~= "Bag" and hasOtherAt(data, action, uid) and DataService.BagSpace(player) <= 0 then
			notify(player, "가방이 가득 찼어요! 🎒", "warn")
			return
		end
		bagOthersAt(data, action, uid)
		if wasLoc == "Slot" then
			PlotService.RemoveItemVisual(player, uid)
		end
		item.Loc = action
		item.Slot = nil
		refreshFollow(player)
		if riding then
			notify(player, "🏇 " .. josa(name, "을", "를") .. " 탔어요! 더 빨라져요 💨", "good")
		else
			notify(player, "🙌 " .. josa(name, "을", "를") .. " 머리 위에 올렸어요!", "good")
		end
	elseif action == "Unride" or action == "Unhold" then
		local loc = if action == "Unride" then "Ride" else "Hold"
		if wasLoc ~= loc then
			return
		end
		if DataService.BagSpace(player) <= 0 then
			notify(player, "가방이 가득 찼어요! 🎒", "warn")
			return
		end
		item.Loc = "Bag"
		item.Slot = nil
		refreshFollow(player)
		if loc == "Ride" then
			notify(player, name .. "에서 내렸어요. 가방에 넣었어요 🎒", "info")
		else
			notify(player, josa(name, "을", "를") .. " 내려놓았어요. 가방에 넣었어요 🎒", "info")
		end
	elseif action == "Fuse" then
		if not fuse(player, data, uid, item) then
			return
		end
	else
		return
	end
	DataService.Sync(player)
end

----------------------------------------------------------------------
-- 부화 / 수입 틱
----------------------------------------------------------------------
local function hatch(player: Player, plot: Plot, uid: string, item: DataService.Item)
	local eggId = item.Id
	local petId = Config.RollPet(eggId, rng)
	local slot = item.Slot or 1
	-- 환생 운: 가끔 브론즈~골드로 태어나요. 크기도 여기서 뽑아요
	local tier = Config.RollHatchTier(DataService.GetRebirths(player), rng)
	local size = Config.RollPetSize(rng, petId) -- ★v7 희귀 펫은 더 넓은 범위에서
	item.Kind = "Pet"
	item.Id = petId
	item.Tier = tier
	item.Size = size
	item.Acc = nil
	item.Loc = "Slot"
	item.HatchAt = nil
	item.HatchLeft = nil
	local isNew = DataService.MarkDiscovered(player, petId, tier)
	local data = DataService.Get(player)
	if data then
		data.Stats.Hatched += 1
	end
	local pos = slotCFrameOf(plot, slot).Position + Vector3.new(0, 2, 0)
	Remotes.HatchFx:FireClient(player, petId, pos, isNew, tier, "Hatch", size)
	PlotService.PlaceItem(player, uid)
	local pet = Config.Pets[petId]
	local rarityName = Config.Rarities[pet.Rarity].Name
	local sizeLabel = Config.SizeLabel(size, petId)
	local bornName =(if sizeLabel ~= "" then sizeLabel .. " " else "") .. Config.PetDisplayName(petId, tier)
	notify(player, (if isNew then "🆕 NEW! [" else "🎉 [") .. rarityName .. "] " .. josa(bornName, "이", "가") .. " 태어났어요!", "good")
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

	-- 수입: 받침대 펫 × 환생 × 집 테마 보너스 (DataService.GetIncome 한 곳에서만 계산)
	local income = DataService.GetIncome(owner)
	if income > 0 then
		data.Pending += income
		DataService.SyncCoins(owner)
	end

	-- 부화 + 알 남은 시간 글자
	local nowSec = os.time()
	local toHatch = nil
	for uid, item in data.Items do
		if item.Loc ~= "Slot" or item.Kind ~= "Egg" then
			continue
		end
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
	if toHatch then
		for _, uid in toHatch do
			local item = data.Items[uid]
			if item and item.Kind == "Egg" and item.Loc == "Slot" then
				hatch(owner, plot, uid, item)
			end
		end
	end
	-- 🏦 자동 수금 (어디에 있든 몇 초마다)
	if autoOn(owner) and os.clock() - plot.LastAutoClaim >= AUTO_COLLECT_EVERY - 0.05 then
		autoCollect(plot, owner)
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
-- 인자 없는 리모트: 연타 막고 처리
local function connectSimple(remote: RemoteEvent, fn: (player: Player) -> ())
	remote.OnServerEvent:Connect(function(player)
		if throttled(player) then
			return
		end
		fn(player)
	end)
end

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
	Remotes.SetTheme.OnServerEvent:Connect(function(player, themeId)
		if throttled(player) then
			return
		end
		trySetTheme(player, themeId)
	end)
	connectSimple(Remotes.BuySlot, tryBuySlot)
	connectSimple(Remotes.BuyFloor, tryBuyFloor)
	connectSimple(Remotes.Rebirth, tryRebirth)
	connectSimple(Remotes.AutoPlace, tryAutoPlace)
	connectSimple(Remotes.ClearBase, tryClearBase)
	connectSimple(Remotes.StashEgg, tryStashEgg) -- ★v7

	-- 자동 수금 버튼을 누르면 수금 패드 글자를 바로 바꿔요 (코인은 다음 틱에)
	DataService.OnSettingChanged(function(player, key)
		local plot = plotByPlayer[player]
		if key == "AutoCollect" and plot then
			updateCollector(plot)
		end
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
