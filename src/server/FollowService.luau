-- 따라다니는 펫 + 타는 펫 + 들고 있는 펫: 서버가 모델을 만들고 AlignPosition/AlignOrientation 으로 플레이어 뒤를 따라가게 해요.
-- 타는 펫은 캐릭터 HumanoidRootPart 에 용접해서 플레이어가 펫 등 위에 올라탄 것처럼 보여요.
-- 들고 있는 펫은 머리(Head)에 용접해서 머리 위에 둥실둥실 떠 있어요.
-- 물리는 플레이어 클라이언트가 계산 (SetNetworkOwner) 해서 부드러워요.
-- 펫은 입은 옷(Item.Acc)까지 같이 만들어요. WalkSpeed / HipHeight 를 정하는 곳은 여기뿐이에요. (설계: docs/DESIGN.md "FollowService")
-- 펫 타고 날기: 타는 펫이 붙어 있는 동안 플레이어 속성 Riding = true (= 날 수 있어요), FlySpeed = 나는 속도.
-- 나는 물리는 클라이언트(RideFly)가 해요. 내리면(Unride) Riding = false → 클라이언트가 살살 내려와 착지해요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local PetModels = require(ReplicatedStorage.Shared.PetModels)
local DataService = require(script.Parent.DataService)

local FollowService = {}

type PetEntry = { uid: string, id: string, tier: number, size: number, boost: number, acc: string? }
type State = {
	models: { Model },
	targets: { Attachment },
	tweens: { Tween },
	offsets: { CFrame },
	ride: Model?,
	hold: Model?, -- 머리 위에 든 펫
	rideHumanoid: Humanoid?, -- HipHeight 를 올린 휴머노이드 (내릴 때 되돌리기용)
	hipAdded: number,
	hipBase: number?, -- 올리기 전 HipHeight (내릴 때 이 값으로 되돌려요)
}

local states: { [Player]: State } = {}
local hooked: { [Player]: { RBXScriptConnection } } = {}
local folder: Folder? = nil

local SPACING = 3.6 -- 펫 사이 간격
local BACK = 5 -- 플레이어 뒤로 떨어진 거리
local HOVER = 0.4 -- 땅 위로 살짝 뜸
local BOB = 0.7 -- 위아래 흔들림
local HOLD_BOB = 0.25 -- 머리 위 펫 위아래 흔들림
local SNAP_DISTANCE = 60 -- 이보다 멀어지면 순간이동
local EFFECT_MIN_ORDER = 5 -- 타기/들기 펫 희귀도 효과: 전설 이상
local FLY_SPEED_MULT = 1.2 -- 날 때 속도 = 탈 때 속도 × 이만큼
local FLY_MAX_SPEED = 72 -- 나는 속도 최대

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = workspace:FindFirstChild("FollowPets")
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = "FollowPets"
		f.Parent = workspace
	end
	folder = f :: Folder
	return f :: Folder
end

local function uidNumber(uid: string): number
	return tonumber(string.sub(uid, 2)) or 0
end

local function tierOf(v: any): number
	return math.clamp(math.floor(tonumber(v) or 1), 1, Config.MaxTier)
end

-- 입은 옷 (진짜 있는 옷만. 옷장 검사는 DataService 가 해요)
local function accOf(v: any): string?
	if Config.AccessoryValid(v) then
		return v
	end
	return nil
end

local function entryOf(uid: string, item: any): PetEntry
	return {
		uid = uid,
		id = item.Id,
		tier = tierOf(item.Tier),
		size = Config.SizeOf(item),
		boost = Config.ItemBoost(item),
		acc = accOf(item.Acc),
	}
end

-- 희귀도 효과 (전설 이상)
local function addRarityEffects(model: Model, petId: string)
	local pet = Config.Pets[petId]
	local rarity = if pet then pet.Rarity else nil
	local info = if rarity then Config.Rarities[rarity] else nil
	if rarity and info and info.Order >= EFFECT_MIN_ORDER then
		pcall(PetModels.AddRarityEffects, model, rarity)
	end
end

-- 모델 속성 (주인 / uid / 펫 / 등급 / 크기 / 옷)
local function tagModel(m: Model, player: Player, entry: PetEntry)
	m:SetAttribute("OwnerUserId", player.UserId)
	m:SetAttribute("ItemUid", entry.uid)
	m:SetAttribute("PetId", entry.id)
	m:SetAttribute("Tier", entry.tier)
	m:SetAttribute("Size", entry.size)
	m:SetAttribute("Acc", entry.acc)
end

-- 데이터에서 따라다니는 펫 목록 (최대 MaxFollow)
local function getFollowItems(player: Player): { PetEntry }
	local list: { PetEntry } = {}
	local data = DataService.Get(player)
	if not data then
		return list
	end
	for uid, item in data.Items do
		if item.Kind == "Pet" and item.Loc == "Follow" and Config.Pets[item.Id] then
			table.insert(list, entryOf(uid, item))
		end
	end
	table.sort(list, function(a, b)
		return uidNumber(a.uid) < uidNumber(b.uid)
	end)
	while #list > Config.MaxFollow do
		table.remove(list)
	end
	return list
end

-- Loc 이 loc 인 펫 하나 (딱 한 마리. 여러 개면 uid 가 가장 작은 것)
local function getSingleItem(player: Player, loc: string): PetEntry?
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local best: PetEntry? = nil
	for uid, item in data.Items do
		if item.Kind == "Pet" and item.Loc == loc and Config.Pets[item.Id] then
			if not best or uidNumber(uid) < uidNumber(best.uid) then
				best = entryOf(uid, item)
			end
		end
	end
	return best
end

-- 타고 있는 펫
local function getRideItem(player: Player): PetEntry?
	return getSingleItem(player, "Ride")
end

-- 머리 위에 들고 있는 펫
local function getHoldItem(player: Player): PetEntry?
	return getSingleItem(player, "Hold")
end

local function getHead(player: Player): BasePart?
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function getHRP(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		return hum
	end
	return nil
end

-- HumanoidRootPart 중심에서 땅까지 거리 (타고 있으면 올라간 HipHeight 가 반영돼요)
local function groundDepth(player: Player, hrp: BasePart): number
	local hum = getHumanoid(player)
	if hum and hum.RigType == Enum.HumanoidRigType.R15 then
		return hum.HipHeight + hrp.Size.Y / 2
	end
	if hum then
		return 2 + hum.HipHeight + hrp.Size.Y / 2 -- R6 다리 2 + HipHeight
	end
	return 3
end

-- 올렸던 HipHeight 되돌리기
local function restoreHip(st: State)
	local hum = st.rideHumanoid
	if hum and st.hipAdded ~= 0 and hum.Parent then
		-- 빼기가 아니라 원래 값으로 (아바타 로드 등으로 HipHeight 가 바뀌어 있어도 안전)
		hum.HipHeight = if st.hipBase ~= nil then st.hipBase else math.max(0, hum.HipHeight - st.hipAdded)
	end
	st.rideHumanoid = nil
	st.hipAdded = 0
	st.hipBase = nil
end

-- 날기 허락 (타는 펫이 진짜 붙어 있을 때만 true). 같은 값이면 안 써요 (Refresh 중에 false 로 깜빡이지 않게)
local function syncRideFlag(player: Player)
	if player.Parent == nil then
		return
	end
	local st = states[player]
	local on = st ~= nil and st.ride ~= nil and st.ride.Parent ~= nil
	if player:GetAttribute("Riding") ~= on then
		player:SetAttribute("Riding", on)
	end
end

local function destroyModels(player: Player)
	local st = states[player]
	if not st then
		return
	end
	for _, t in st.tweens do
		t:Cancel()
	end
	for _, m in st.models do
		m:Destroy()
	end
	for _, a in st.targets do
		a:Destroy()
	end
	if st.ride then
		st.ride:Destroy()
		st.ride = nil
	end
	if st.hold then
		st.hold:Destroy()
		st.hold = nil
	end
	restoreHip(st)
	states[player] = nil
end

local function makeNameTag(body: BasePart, model: Model, petId: string, tier: number)
	local pet = Config.Pets[petId]
	local rarity = Config.Rarities[pet.Rarity]
	local info = Config.TierInfo(tier)
	local color = if tier >= 2 then info.Color else (if rarity then rarity.Color else Color3.new(1, 1, 1))

	local top = model:GetPivot().Position.Y + model:GetExtentsSize().Y + 0.9
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Adornee = body
	gui.Size = UDim2.fromOffset(150, 28)
	gui.StudsOffsetWorldSpace = Vector3.new(0, top - body.Position.Y, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = body

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.FredokaOne
	label.Text = Config.PetDisplayName(petId, tier)
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(60, 45, 80)
	label.TextStrokeTransparency = 0.35
	label.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = label
end

local function buildPetModel(entry: PetEntry): (Model?, BasePart?)
	local ok, built = pcall(function()
		return PetModels.BuildPet(entry.id, entry.tier, entry.acc)
	end)
	if not ok or typeof(built) ~= "Instance" or not built:IsA("Model") then
		warn("[FollowService] 펫 모델을 만들 수 없어요:", entry.id, built)
		return nil, nil
	end
	local model = built :: Model
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		model:Destroy()
		return nil, nil
	end
	model.PrimaryPart = body
	return model, body
end

local function setPhysicsFlags(model: Model, body: BasePart, allMassless: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = allMassless or d ~= body
		end
	end
end

-- 타는 펫: 캐릭터 발밑에 크게 만든 펫을 용접하고 HipHeight 를 올려요
local function mountRide(player: Player, st: State, hrp: BasePart, hum: Humanoid)
	local entry = getRideItem(player)
	if not entry then
		return
	end
	local model, body = buildPetModel(entry)
	if not model or not body then
		return
	end
	local m = model :: Model
	local b = body :: BasePart
	pcall(function()
		m:ScaleTo(entry.size * Config.Ride.Scale)
	end)
	setPhysicsFlags(m, b, true)
	addRarityEffects(m, entry.id)

	-- 캐릭터를 펫 등 높이만큼 올리기
	local hipBase = hum.HipHeight
	st.rideHumanoid = hum
	st.hipBase = hipBase
	st.hipAdded = Config.Ride.HipHeightAdd
	hum.HipHeight = hipBase + st.hipAdded

	-- 펫 바닥(피벗)이 땅에 닿게: HRP 아래 (올라간 HipHeight + HRP 절반)
	local depth = groundDepth(player, hrp)
	local offset = CFrame.new(0, -depth, 0)
	m:PivotTo(hrp.CFrame * offset)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "RideWeld"
	weld.Part0 = hrp
	weld.Part1 = b
	weld.Parent = b

	m.Name = "RideMount_" .. tostring(player.UserId)
	tagModel(m, player, entry)
	m:SetAttribute("Ride", true)
	m.Parent = getFolder()
	st.ride = m
end

-- 들고 있는 펫: 작게 만들어 머리 위에 용접하고 살짝 둥실둥실 (Weld C0 트윈 1개)
local function mountHold(player: Player, st: State, head: BasePart)
	local entry = getHoldItem(player)
	if not entry then
		return
	end
	local model, body = buildPetModel(entry)
	if not model or not body then
		return
	end
	local m = model :: Model
	local b = body :: BasePart
	pcall(function()
		m:ScaleTo(entry.size * Config.Hold.Scale)
	end)
	setPhysicsFlags(m, b, true)
	addRarityEffects(m, entry.id)

	-- 펫 바닥(피벗)이 머리 꼭대기에서 HeadOffset 만큼 위에 오게
	local lift = head.Size.Y / 2 + Config.Hold.HeadOffset
	m:PivotTo(head.CFrame * CFrame.new(0, lift, 0))

	local weld = Instance.new("Weld")
	weld.Name = "HoldWeld"
	weld.Part0 = head
	weld.Part1 = b
	weld.C0 = head.CFrame:ToObjectSpace(b.CFrame)
	weld.Parent = b

	m.Name = "HoldPet_" .. tostring(player.UserId)
	tagModel(m, player, entry)
	m:SetAttribute("Hold", true)
	m.Parent = getFolder()
	st.hold = m

	local tween = TweenService:Create(
		weld,
		TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ C0 = weld.C0 * CFrame.new(0, HOLD_BOB, 0) }
	)
	tween:Play()
	table.insert(st.tweens, tween)
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 따라오는 펫 수 (+ 타는 펫 1). 자석 반경·이동 속도 계산에 써요
function FollowService.GetFollowerCount(player: Player): number
	return #getFollowItems(player) + (if getRideItem(player) then 1 else 0)
end

-- 따라오는 펫 + 타는 펫 + 들고 있는 펫의 코인 보너스 합
function FollowService.GetBoost(player: Player): number
	local boost = 0
	for _, entry in getFollowItems(player) do
		boost += entry.boost
	end
	local ride = getRideItem(player)
	if ride then
		boost += ride.boost
	end
	local hold = getHoldItem(player)
	if hold then
		boost += hold.boost
	end
	return boost
end

-- 이동 속도(WalkSpeed)와 HipHeight 를 정하는 유일한 곳 (타기 배율 × 환생 배율, 최대 Config.MaxWalkSpeed)
function FollowService.UpdateSpeed(player: Player)
	local ride = getRideItem(player)
	local mult = if ride then Config.RideSpeedMultiplier(ride.id, ride.tier) else 1
	if player.Parent then
		player:SetAttribute("RideSpeedMult", mult)
	end
	local hum = getHumanoid(player)
	if not hum then
		return
	end
	local count = FollowService.GetFollowerCount(player)
	local rebirthMult = Config.RebirthSpeedMult(DataService.GetRebirths(player))
	local speed = (Config.BaseWalkSpeed + Config.WalkSpeedPerFollower * count) * mult * rebirthMult
	hum.WalkSpeed = math.min(speed, Config.MaxWalkSpeed)
	-- 날 때 속도 (탈 때보다 조금 빠르게)
	local fly = if ride then math.floor(math.min(hum.WalkSpeed * FLY_SPEED_MULT, FLY_MAX_SPEED) * 10 + 0.5) / 10 else 0
	if player.Parent and player:GetAttribute("FlySpeed") ~= fly then
		player:SetAttribute("FlySpeed", fly)
	end
end

function FollowService.Clear(player: Player)
	destroyModels(player)
	syncRideFlag(player)
	if player.Parent then
		player:SetAttribute("RideSpeedMult", 1)
	end
end

-- 타는 펫이 지금 붙어 있나 (= 날 수 있나)
function FollowService.IsRiding(player: Player): boolean
	local st = states[player]
	return st ~= nil and st.ride ~= nil and st.ride.Parent ~= nil
end

local refreshInner: (Player) -> ()

function FollowService.Refresh(player: Player)
	refreshInner(player)
	syncRideFlag(player)
end

refreshInner = function(player: Player)
	destroyModels(player)
	FollowService.UpdateSpeed(player)
	if player.Parent == nil then
		return
	end

	local items = getFollowItems(player)
	local rideEntry = getRideItem(player)
	local holdEntry = getHoldItem(player)
	local hrp = getHRP(player)
	local hum = getHumanoid(player)
	if (#items == 0 and not rideEntry and not holdEntry) or not hrp or not hum then
		return
	end
	if hum.Health <= 0 then
		return
	end

	local st: State = { models = {}, targets = {}, tweens = {}, offsets = {}, ride = nil, hold = nil, rideHumanoid = nil, hipAdded = 0, hipBase = nil }
	states[player] = st

	-- 타는 펫 먼저 (HipHeight 가 바뀌어야 따라오는 펫의 땅 높이가 맞아요)
	if rideEntry then
		local ok, err = pcall(mountRide, player, st, hrp, hum)
		if not ok then
			warn("[FollowService] 타기 오류:", err)
		end
	end

	-- 머리 위에 든 펫
	if holdEntry then
		local head = getHead(player)
		if head then
			local ok, err = pcall(mountHold, player, st, head)
			if not ok then
				warn("[FollowService] 들기 오류:", err)
			end
		end
	end

	local parentFolder = getFolder()
	local depth = groundDepth(player, hrp)
	local n = #items

	for i, entry in items do
		local model, body = buildPetModel(entry)
		if not model or not body then
			continue
		end
		local m = model :: Model
		local b = body :: BasePart
		pcall(function()
			m:ScaleTo(entry.size)
		end)
		setPhysicsFlags(m, b, false)

		-- 부채꼴: 가운데 펫이 가장 뒤, 양옆 펫은 조금 앞
		local sideX = (i - (n + 1) / 2) * SPACING
		local offset = CFrame.new(sideX, -depth + HOVER, BACK - math.abs(sideX) * 0.3)

		local target = Instance.new("Attachment")
		target.Name = "FollowTarget_" .. entry.uid
		target.CFrame = offset
		target.Parent = hrp

		-- 펫 쪽 부착점 = 모델 피벗 (바닥 중심)
		local petAtt = Instance.new("Attachment")
		petAtt.Name = "FollowAttachment"
		petAtt.CFrame = b.CFrame:ToObjectSpace(m:GetPivot())
		petAtt.Parent = b

		local alignPos = Instance.new("AlignPosition")
		alignPos.Mode = Enum.PositionAlignmentMode.TwoAttachment
		alignPos.Attachment0 = petAtt
		alignPos.Attachment1 = target
		alignPos.MaxForce = 1e6
		alignPos.Responsiveness = 25
		alignPos.Parent = b

		local alignOri = Instance.new("AlignOrientation")
		alignOri.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		alignOri.Attachment0 = petAtt
		alignOri.Attachment1 = target
		alignOri.MaxTorque = 1e6
		alignOri.Responsiveness = 18
		alignOri.Parent = b

		makeNameTag(b, m, entry.id, entry.tier)

		m.Name = player.Name .. "_" .. entry.id
		tagModel(m, player, entry)
		m:PivotTo(hrp.CFrame * offset)
		m.Parent = parentFolder

		pcall(function()
			b:SetNetworkOwner(player)
		end)

		-- 둥실둥실
		local tween = TweenService:Create(
			target,
			TweenInfo.new(0.8 + i * 0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, i * 0.2),
			{ CFrame = offset * CFrame.new(0, BOB, 0) }
		)
		tween:Play()

		table.insert(st.models, m)
		table.insert(st.targets, target)
		table.insert(st.tweens, tween)
		table.insert(st.offsets, offset)
	end
end

local function hookPlayer(player: Player)
	if hooked[player] then
		return
	end
	hooked[player] = {
		player.CharacterRemoving:Connect(function()
			destroyModels(player)
			syncRideFlag(player)
		end),
		-- 리스폰하면 타던 펫 / 들고 있던 펫을 다시 올려요 (기지로 옮겨진 뒤에)
		player.CharacterAdded:Connect(function(character)
			task.delay(0.6, function()
				if player.Parent and player.Character == character and DataService.Get(player) and (getRideItem(player) or getHoldItem(player)) then
					local st = states[player]
					if not (st and (st.ride or st.hold)) then
						FollowService.Refresh(player)
					end
				end
			end)
		end),
		-- 아바타(몸 크기)가 늦게 적용되면 HipHeight 가 다시 써질 수 있어요 → 타던/들던 펫을 한 번 더 올려요
		player.CharacterAppearanceLoaded:Connect(function()
			if player.Parent and DataService.Get(player) and (getRideItem(player) or getHoldItem(player)) then
				FollowService.Refresh(player)
			end
		end),
	}
end

function FollowService.Start()
	getFolder()
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		destroyModels(player)
		local conns = hooked[player]
		if conns then
			for _, c in conns do
				c:Disconnect()
			end
			hooked[player] = nil
		end
	end)

	-- 너무 멀어진(순간이동 등) 펫은 바로 옆으로 옮겨요
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, st in states do
				local hrp = getHRP(player)
				if hrp then
					for i, m in st.models do
						local body = m.PrimaryPart
						local offset = st.offsets[i]
						if body and offset and (body.Position - hrp.Position).Magnitude > SNAP_DISTANCE then
							m:PivotTo(hrp.CFrame * offset)
							body.AssemblyLinearVelocity = Vector3.zero
						end
					end
				end
			end
		end
	end)
end

return FollowService
