-- 따라다니는 펫: 서버가 모델을 만들고 AlignPosition/AlignOrientation 으로 플레이어 뒤를 따라가게 해요.
-- 물리는 플레이어 클라이언트가 계산 (SetNetworkOwner) 해서 부드러워요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local PetModels = require(ReplicatedStorage.Shared.PetModels)
local DataService = require(script.Parent.DataService)

local FollowService = {}

type FollowEntry = { uid: string, id: string }
type State = {
	models: { Model },
	targets: { Attachment },
	tweens: { Tween },
	offsets: { CFrame },
}

local states: { [Player]: State } = {}
local hooked: { [Player]: { RBXScriptConnection } } = {}
local folder: Folder? = nil

local SPACING = 3.6 -- 펫 사이 간격
local BACK = 5 -- 플레이어 뒤로 떨어진 거리
local HOVER = 0.4 -- 땅 위로 살짝 뜸
local BOB = 0.7 -- 위아래 흔들림
local SNAP_DISTANCE = 60 -- 이보다 멀어지면 순간이동

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

-- 데이터에서 따라다니는 펫 목록 (최대 MaxFollow)
local function getFollowItems(player: Player): { FollowEntry }
	local list: { FollowEntry } = {}
	local data = DataService.Get(player)
	if not data then
		return list
	end
	for uid, item in data.Items do
		if item.Kind == "Pet" and item.Loc == "Follow" and Config.Pets[item.Id] then
			table.insert(list, { uid = uid, id = item.Id })
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

local function getHRP(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

-- HumanoidRootPart 중심에서 땅까지 거리
local function groundDepth(player: Player, hrp: BasePart): number
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.RigType == Enum.HumanoidRigType.R15 then
		return hum.HipHeight + hrp.Size.Y / 2
	end
	return 3
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
	states[player] = nil
end

local function makeNameTag(body: BasePart, model: Model, petId: string)
	local pet = Config.Pets[petId]
	local rarity = Config.Rarities[pet.Rarity]
	local rarityColor = if rarity then rarity.Color else Color3.new(1, 1, 1)

	local top = model:GetPivot().Position.Y + model:GetExtentsSize().Y + 0.9
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Adornee = body
	gui.Size = UDim2.fromOffset(130, 28)
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
	label.Text = pet.Name
	label.TextScaled = true
	label.TextColor3 = rarityColor
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
	stroke.Color = rarityColor
	stroke.Thickness = 2
	stroke.Parent = label
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

function FollowService.GetFollowerCount(player: Player): number
	return #getFollowItems(player)
end

function FollowService.GetBoost(player: Player): number
	local boost = 0
	for _, entry in getFollowItems(player) do
		boost += Config.Pets[entry.id].Boost
	end
	return boost
end

-- 이동 속도를 정하는 유일한 곳
function FollowService.UpdateSpeed(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local count = FollowService.GetFollowerCount(player)
	local mult = if player:GetAttribute("Carrying") == true then Config.Steal.CarrySpeedMultiplier else 1
	hum.WalkSpeed = (Config.BaseWalkSpeed + Config.WalkSpeedPerFollower * count) * mult
end

function FollowService.Clear(player: Player)
	destroyModels(player)
end

function FollowService.Refresh(player: Player)
	destroyModels(player)
	FollowService.UpdateSpeed(player)
	if player.Parent == nil then
		return
	end

	local items = getFollowItems(player)
	local hrp = getHRP(player)
	if #items == 0 or not hrp then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return
	end

	local st: State = { models = {}, targets = {}, tweens = {}, offsets = {} }
	states[player] = st

	local parentFolder = getFolder()
	local depth = groundDepth(player, hrp)
	local n = #items

	for i, entry in items do
		local ok, built = pcall(PetModels.BuildPet, entry.id)
		if not ok or typeof(built) ~= "Instance" or not built:IsA("Model") then
			warn("[FollowService] 펫 모델을 만들 수 없어요:", entry.id, built)
			continue
		end
		local model = built :: Model
		local body = model.PrimaryPart or model:FindFirstChild("Body")
		if not (body and body:IsA("BasePart")) then
			model:Destroy()
			continue
		end
		model.PrimaryPart = body

		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Massless = d ~= body
			end
		end

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
		petAtt.CFrame = body.CFrame:ToObjectSpace(model:GetPivot())
		petAtt.Parent = body

		local alignPos = Instance.new("AlignPosition")
		alignPos.Mode = Enum.PositionAlignmentMode.TwoAttachment
		alignPos.Attachment0 = petAtt
		alignPos.Attachment1 = target
		alignPos.MaxForce = 1e6
		alignPos.Responsiveness = 25
		alignPos.Parent = body

		local alignOri = Instance.new("AlignOrientation")
		alignOri.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		alignOri.Attachment0 = petAtt
		alignOri.Attachment1 = target
		alignOri.MaxTorque = 1e6
		alignOri.Responsiveness = 18
		alignOri.Parent = body

		makeNameTag(body, model, entry.id)

		model.Name = player.Name .. "_" .. entry.id
		model:SetAttribute("OwnerUserId", player.UserId)
		model:SetAttribute("ItemUid", entry.uid)
		model:SetAttribute("PetId", entry.id)
		model:PivotTo(hrp.CFrame * offset)
		model.Parent = parentFolder

		pcall(function()
			body:SetNetworkOwner(player)
		end)

		-- 둥실둥실
		local tween = TweenService:Create(
			target,
			TweenInfo.new(0.8 + i * 0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, i * 0.2),
			{ CFrame = offset * CFrame.new(0, BOB, 0) }
		)
		tween:Play()

		table.insert(st.models, model)
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
		end),
		player:GetAttributeChangedSignal("Carrying"):Connect(function()
			FollowService.UpdateSpeed(player)
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
