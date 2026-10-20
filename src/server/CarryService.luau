-- 훔치기: 다른 기지의 알/펫을 머리 위에 들고 내 기지까지 달려가요.
-- 상태는 도둑(Player) 하나당 하나. 끝내기(finish)는 딱 한 번만 실행돼서 복제/분실이 없어요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local PetModels = require(Shared.PetModels)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local FollowService = require(script.Parent.FollowService)

local CarryService = {}

local STEAL_DISTANCE = 25 -- 훔치는 사람과 받침대 사이 최대 거리
local RECLAIM_DISTANCE = 16

type CarryState = {
	Thief: Player,
	Owner: Player,
	OwnerUserId: number,
	Item: { [string]: any }, -- 원래 아이템 데이터(복사본)
	OrigSlot: number?,
	Name: string,
	Model: Model?,
	Deadline: number,
	Conns: { RBXScriptConnection },
	Ended: boolean,
}

local carries: { [Player]: CarryState } = {}
local carriedFolder: Folder? = nil

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------
local function notify(player: Player?, text: string, kind: string)
	if player and player.Parent ~= nil then
		Remotes.Notify:FireClient(player, text, kind)
	end
end

-- 받침이 있으면 a, 없으면 b (예: 을/를)
local function josa(word: string, withFinal: string, withoutFinal: string): string
	local last: number? = nil
	for _, cp in utf8.codes(word) do
		last = cp
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 then
		if (last - 0xAC00) % 28 ~= 0 then
			return word .. withFinal
		end
		return word .. withoutFinal
	end
	return word .. withFinal .. "(" .. withoutFinal .. ")"
end

local function itemName(kind: string, id: string): string
	if kind == "Pet" then
		local pet = Config.Pets[id]
		return if pet then pet.Name else id
	end
	local egg = Config.Eggs[id]
	return if egg then egg.Name else id
end

local function itemRarity(kind: string, id: string): string?
	if kind == "Pet" then
		local pet = Config.Pets[id]
		return pet and pet.Rarity
	end
	local egg = Config.Eggs[id]
	return egg and egg.Rarity
end

local function getHRP(player: Player): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function updateSpeed(player: Player)
	if player.Parent == nil or player.Character == nil then
		return
	end
	local ok, err = pcall(FollowService.UpdateSpeed, player)
	if not ok then
		warn("[CarryService] UpdateSpeed 오류:", err)
	end
end

local function clearAttributes(player: Player)
	player:SetAttribute("Carrying", false)
	player:SetAttribute("CarryDeadline", 0)
	player:SetAttribute("CarryItemName", "")
end

local function sync(player: Player?)
	if player and player.Parent ~= nil and DataService.Get(player) then
		DataService.Sync(player)
	end
end

-- 해당 슬롯이 열려 있고 비어 있는지
local function isSlotFree(player: Player, slot: number?): boolean
	if type(slot) ~= "number" then
		return false
	end
	local data = DataService.Get(player)
	if not data or slot < 1 or slot > (data.SlotsUnlocked or 0) then
		return false
	end
	for _, item in data.Items do
		if item.Loc == "Slot" and item.Slot == slot then
			return false
		end
	end
	return true
end

-- 아이템 복사본을 slot(있으면) 또는 가방 위치로 만들어요
local function makeItem(src: { [string]: any }, slot: number?): { [string]: any }
	local item: { [string]: any } = { Kind = src.Kind, Id = src.Id }
	if slot then
		item.Loc = "Slot"
		item.Slot = slot
		if src.Kind == "Egg" then
			item.HatchAt = src.HatchAt or (os.time() + (src.HatchLeft or 0))
		end
	else
		item.Loc = "Bag"
		if src.Kind == "Egg" then
			local left = if src.HatchAt then src.HatchAt - os.time() else (src.HatchLeft or 0)
			item.HatchLeft = math.max(0, left)
		end
	end
	return item
end

----------------------------------------------------------------------
-- 들고 다니는 모델
----------------------------------------------------------------------
local function buildModel(kind: string, id: string): Model
	local ok, model = pcall(function()
		if kind == "Pet" then
			return PetModels.BuildPet(id)
		end
		return PetModels.BuildEgg(id)
	end)
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		return model
	end
	warn("[CarryService] 모델 생성 실패:", model)
	local m = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2.4, 2.4, 2.4)
	body.Color = Color3.fromRGB(255, 200, 230)
	body.Parent = m
	m.PrimaryPart = body
	m.WorldPivot = body.CFrame * CFrame.new(0, -1.2, 0)
	return m
end

local function makeCarryBillboard(adornee: BasePart, name: string, rarity: string?)
	local info = rarity and Config.Rarities[rarity]
	local gui = Instance.new("BillboardGui")
	gui.Name = "CarryInfo"
	gui.Adornee = adornee
	gui.Size = UDim2.new(6, 0, 1.2, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = "🏃 " .. name
	l.TextColor3 = if info then info.Color else Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	l.Parent = gui
	gui.Parent = adornee
end

----------------------------------------------------------------------
-- 끝내기 (한 번만)
----------------------------------------------------------------------

-- 원래 주인에게 돌려주기. 돌려줬으면 true, 주인이 없어서 사라졌으면 false.
-- placeVisual = false 면 데이터만 바꿔요(주인이 나가는 중일 때).
local function giveBack(state: CarryState, placeVisual: boolean): (boolean, boolean)
	local owner = state.Owner
	-- 이미 나간 주인이면 사라져요 (나가는 중이면 placeVisual = false 로 데이터에만 넣어요)
	if owner.Parent == nil and placeVisual then
		return false, false
	end
	if not DataService.Get(owner) then
		return false, false
	end
	local slot: number? = nil
	if isSlotFree(owner, state.OrigSlot) then
		slot = state.OrigSlot
	else
		slot = PlotService.FreeSlot(owner)
	end
	local item = makeItem(state.Item, slot)
	local uid = DataService.AddItem(owner, item)
	if not uid or uid == "" then
		return false, false
	end
	if slot and placeVisual then
		PlotService.PlaceItem(owner, uid)
	end
	return true, slot == nil
end

-- 도둑의 기지에 넣기. 성공하면 true.
local function deliver(state: CarryState): boolean
	local thief = state.Thief
	if thief.Parent == nil then
		return false
	end
	local data = DataService.Get(thief)
	if not data then
		return false
	end
	local slot = PlotService.FreeSlot(thief)
	local item = makeItem(state.Item, slot)
	local uid = DataService.AddItem(thief, item)
	if not uid or uid == "" then
		return false
	end
	if slot then
		PlotService.PlaceItem(thief, uid)
	end
	local isNew = false
	if item.Kind == "Pet" then
		isNew = DataService.MarkDiscovered(thief, item.Id)
	end
	if type(data.Stats) == "table" then
		data.Stats.Steals = (data.Stats.Steals or 0) + 1
	end

	local text = "🎉 훔치기 성공! " .. josa(state.Name, "을", "를") .. " 데려왔어요"
	if not slot then
		text ..= " (가방에 넣었어요)"
	end
	notify(thief, text, "good")
	if isNew then
		notify(thief, "📖 도감에 새 친구가 생겼어요!", "good")
	end
	notify(state.Owner, "😢 " .. josa(state.Name, "을", "를") .. " 도둑맞았어요… 기지를 잠그면 안전해요!", "alert")
	return true
end

-- reason: "Deliver" | "Reclaim" | "Timeout" | "Died" | "Left" | "OwnerLeft" | "Lost" | "Shutdown"
local function finish(state: CarryState, reason: string)
	if state.Ended then
		return
	end
	state.Ended = true
	if carries[state.Thief] == state then
		carries[state.Thief] = nil
	end
	for _, c in state.Conns do
		c:Disconnect()
	end
	table.clear(state.Conns)
	local model = state.Model
	state.Model = nil
	if model then
		model:Destroy()
	end

	local thief = state.Thief
	local owner = state.Owner
	clearAttributes(thief)
	updateSpeed(thief)

	local ok, err = pcall(function()
		if reason == "Deliver" and deliver(state) then
			return
		end
		-- 실패: 주인에게 돌려주기
		local placeVisual = reason ~= "OwnerLeft" and reason ~= "Shutdown"
		local returned, toBag = giveBack(state, placeVisual)
		local name = state.Name
		local bagNote = if toBag then " (가방으로 갔어요)" else ""
		if reason == "Reclaim" then
			notify(owner, "💪 되찾았어요! " .. josa(name, "이", "가") .. " 돌아왔어요" .. bagNote, "good")
			notify(thief, "앗! " .. owner.DisplayName .. "님이 " .. josa(name, "을", "를") .. " 되찾아 갔어요 😅", "warn")
		elseif reason == "Timeout" then
			notify(thief, "⏰ 시간이 다 됐어요! " .. josa(name, "이", "가") .. " 집으로 돌아갔어요", "warn")
			if returned then
				notify(owner, "😌 " .. josa(name, "이", "가") .. " 무사히 돌아왔어요!" .. bagNote, "good")
			end
		elseif reason == "Died" or reason == "Lost" then
			notify(thief, "💫 앗, 놓쳤어요! " .. josa(name, "이", "가") .. " 집으로 돌아갔어요", "warn")
			if returned then
				notify(owner, "😌 " .. josa(name, "이", "가") .. " 무사히 돌아왔어요!" .. bagNote, "good")
			end
		elseif reason == "Left" then
			if returned then
				notify(owner, "😌 " .. josa(name, "이", "가") .. " 무사히 돌아왔어요!" .. bagNote, "good")
			end
		elseif reason == "OwnerLeft" then
			notify(thief, "👋 " .. owner.DisplayName .. "님이 나가서 " .. josa(name, "이", "가") .. " 집으로 돌아갔어요", "info")
		end
	end)
	if not ok then
		warn("[CarryService] 끝내기 오류:", err)
	end

	sync(thief)
	sync(owner)
end

----------------------------------------------------------------------
-- 훔치기 시작
----------------------------------------------------------------------
function CarryService.StartSteal(thief: Player, owner: Player, uid: string)
	if typeof(thief) ~= "Instance" or not thief:IsA("Player") then
		return
	end
	if typeof(owner) ~= "Instance" or not owner:IsA("Player") or type(uid) ~= "string" then
		return
	end
	if thief == owner or thief.Parent == nil or owner.Parent == nil then
		return
	end
	if carries[thief] then
		notify(thief, "이미 하나 들고 있어요! 먼저 기지로 가져가요 🏃", "warn")
		return
	end
	if not DataService.Get(thief) or not DataService.Get(owner) then
		return
	end

	local ownerPlot = PlotService.GetPlot(owner)
	if not ownerPlot then
		return
	end
	if PlotService.IsLocked(ownerPlot) then
		notify(thief, "🔒 잠긴 기지예요! 잠금이 풀릴 때까지 기다려요", "warn")
		return
	end
	local item = DataService.GetItem(owner, uid)
	if not item or item.Loc ~= "Slot" then
		return
	end
	if not PlotService.GetPlot(thief) then
		notify(thief, "아직 내 기지가 없어요!", "warn")
		return
	end
	if not PlotService.FreeSlot(thief) then
		notify(thief, "내 기지에 빈 자리가 없어요! 자리를 먼저 비워요", "warn")
		return
	end

	-- 캐릭터 확인
	local character = thief.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = getHRP(thief)
	if not (character and humanoid and hrp) or humanoid.Health <= 0 then
		return
	end
	local headInst = character:FindFirstChild("Head")
	local anchorPart: BasePart = if headInst and headInst:IsA("BasePart") then headInst else hrp
	if type(item.Slot) == "number" then
		local ok, slotCF = pcall(PlotService.GetSlotCFrame, owner, item.Slot)
		if ok and typeof(slotCF) == "CFrame" and (slotCF.Position - hrp.Position).Magnitude > STEAL_DISTANCE then
			return
		end
	end

	-- 주인에게서 빼기 (여기부터 아이템은 이 상태 테이블이 책임져요)
	local removed = DataService.RemoveItem(owner, uid)
	if not removed then
		return
	end
	pcall(PlotService.RemoveItemVisual, owner, uid)

	local name = itemName(removed.Kind, removed.Id)
	local state: CarryState = {
		Thief = thief,
		Owner = owner,
		OwnerUserId = owner.UserId,
		Item = table.clone(removed),
		OrigSlot = removed.Slot,
		Name = name,
		Model = nil,
		Deadline = workspace:GetServerTimeNow() + Config.Steal.CarryTimeout,
		Conns = {},
		Ended = false,
	}
	carries[thief] = state

	-- 모델 만들기 (실패해도 상태는 유지되고 나중에 정상 처리돼요)
	local ok, err = pcall(function()
		local model = buildModel(removed.Kind, removed.Id)
		model.Name = "Carried_" .. thief.Name
		local main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		assert(main, "모델에 파트가 없어요")
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.Massless = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			end
		end
		local rarity = itemRarity(removed.Kind, removed.Id)
		if rarity and Config.Rarities[rarity] and Config.Rarities[rarity].Order >= 4 then
			pcall(PetModels.AddRarityEffects, model, rarity)
		end
		-- 머리 위에 올리기 (도둑과 같은 방향)
		local yaw = hrp.CFrame.Rotation
		local topY = anchorPart.Position.Y + anchorPart.Size.Y / 2 + 0.4
		model:PivotTo(CFrame.new(anchorPart.Position.X, topY, anchorPart.Position.Z) * yaw)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchorPart
		weld.Part1 = main
		weld.Parent = main

		makeCarryBillboard(main, name, rarity)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ReclaimPrompt"
		prompt.ActionText = "되찾기!"
		prompt.ObjectText = name
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("PromptKind", "Reclaim")
		prompt:SetAttribute("OwnerUserId", owner.UserId)
		prompt.Parent = main

		table.insert(
			state.Conns,
			prompt.Triggered:Connect(function(player)
				if state.Ended or player.UserId ~= state.OwnerUserId or player ~= state.Owner then
					return
				end
				local ownerHrp = getHRP(player)
				local mainPart = state.Model and (state.Model.PrimaryPart or state.Model:FindFirstChildWhichIsA("BasePart", true))
				if not (ownerHrp and mainPart) then
					return
				end
				if (ownerHrp.Position - mainPart.Position).Magnitude > RECLAIM_DISTANCE then
					return
				end
				finish(state, "Reclaim")
			end)
		)

		model.Parent = carriedFolder
		state.Model = model

		-- 모델이 없어지면(낙사 등) 돌려주기
		table.insert(
			state.Conns,
			model.AncestryChanged:Connect(function()
				if not state.Ended and not model:IsDescendantOf(workspace) then
					task.defer(finish, state, "Lost")
				end
			end)
		)
	end)
	if not ok then
		warn("[CarryService] 들고 가기 모델 오류:", err)
	end

	-- 실패 조건 연결
	table.insert(
		state.Conns,
		humanoid.Died:Connect(function()
			finish(state, "Died")
		end)
	)
	table.insert(
		state.Conns,
		thief.CharacterRemoving:Connect(function()
			finish(state, "Died")
		end)
	)

	thief:SetAttribute("Carrying", true)
	thief:SetAttribute("CarryDeadline", state.Deadline)
	thief:SetAttribute("CarryItemName", name)
	updateSpeed(thief)

	notify(owner, "🚨 " .. thief.DisplayName .. "님이 내 " .. josa(name, "을", "를") .. " 훔쳐가요! 쫓아가서 되찾으세요!", "alert")
	notify(thief, "🏃 내 기지로 달려가세요! ⏱ " .. Config.Steal.CarryTimeout .. "초", "good")
	sync(owner)
	sync(thief)
end

----------------------------------------------------------------------
-- 루프 / 종료 처리
----------------------------------------------------------------------
local accum = 0
local function onHeartbeat(dt: number)
	accum += dt
	if accum < 0.1 then
		return
	end
	accum = 0
	if next(carries) == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	-- 순회 중 테이블이 바뀌지 않게 목록을 먼저 복사
	local list = {}
	for _, state in carries do
		table.insert(list, state)
	end
	for _, state in list do
		if state.Ended then
			continue
		end
		local thief = state.Thief
		if thief.Parent == nil then
			finish(state, "Left")
			continue
		end
		if now > state.Deadline then
			finish(state, "Timeout")
			continue
		end
		local hrp = getHRP(thief)
		if not hrp then
			continue
		end
		local myPlot = PlotService.GetPlot(thief)
		if myPlot then
			local here = PlotService.GetPlotAt(hrp.Position)
			if here and (here == myPlot or here.Index == myPlot.Index) then
				finish(state, "Deliver")
			end
		end
	end
end

function CarryService.Start()
	local old = workspace:FindFirstChild("CarriedItems")
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "CarriedItems"
	f.Parent = workspace
	carriedFolder = f

	RunService.Heartbeat:Connect(onHeartbeat)

	Players.PlayerAdded:Connect(clearAttributes)
	for _, p in Players:GetPlayers() do
		clearAttributes(p)
	end
end

-- PlayerRemoving 에서 (DataService.Release 전에) 불려요
function CarryService.OnPlayerRemoving(player: Player)
	local own = carries[player]
	if own then
		finish(own, "Left")
	end
	-- 이 사람 물건을 누가 들고 있으면, 저장되기 전에 데이터로 돌려줘요
	local list = {}
	for _, state in carries do
		if state.Owner == player then
			table.insert(list, state)
		end
	end
	for _, state in list do
		finish(state, "OwnerLeft")
	end
end

-- 서버 종료 시 SaveAll 전에 모두 돌려주기
function CarryService.ReturnAll()
	local list = {}
	for _, state in carries do
		table.insert(list, state)
	end
	for _, state in list do
		finish(state, "Shutdown")
	end
end

return CarryService
