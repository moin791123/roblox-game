-- 클라이언트 상태: 서버 스냅샷 + 내 집(플롯) 모델 찾기
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

export type Item = {
	Kind: string,
	Id: string,
	Tier: number?,
	Size: number?, -- 펫 크기 (수익 × 크기)
	Loc: string,
	Slot: number?,
	HatchAt: number?,
	HatchLeft: number?,
}

export type Snapshot = {
	Coins: number,
	Pending: number,
	SlotsUnlocked: number,
	Floors: number,
	Theme: string,
	Themes: { [string]: boolean },
	Items: { [string]: Item },
	Index: { [string]: any }, -- 펫별 최고 등급 (예전 데이터는 true)
	PlotIndex: number?,
	Income: number,
	Rebirths: number,
	RebirthCost: number,
}

local State = {}
State.Snapshot = nil :: Snapshot?
State.Plot = nil :: Model?

local syncListeners: { (Snapshot, Snapshot?) -> () } = {}
local plotListeners: { (Model?) -> () } = {}
local plotsFolder: Instance? = nil

function State.OnSync(fn: (Snapshot, Snapshot?) -> ())
	table.insert(syncListeners, fn)
end

function State.OnPlot(fn: (Model?) -> ())
	table.insert(plotListeners, fn)
end

function State.Items(): { [string]: Item }
	local snap = State.Snapshot
	if snap and type(snap.Items) == "table" then
		return snap.Items
	end
	return {}
end

-- 펫 등급 (없으면 1)
function State.ItemTier(item: Item?): number
	if not item then
		return 1
	end
	return math.max(1, math.floor(tonumber(item.Tier) or 1))
end

-- 같은 펫·같은 등급이 몇 마리인지 (합성 버튼용)
function State.CountSame(petId: string, tier: number?): number
	local want = math.max(1, math.floor(tonumber(tier) or 1))
	local n = 0
	for _, item in State.Items() do
		if type(item) == "table" and item.Kind == "Pet" and item.Id == petId and State.ItemTier(item) == want then
			n += 1
		end
	end
	return n
end

-- 타고 있는 펫의 uid (없으면 nil)
function State.RideItem(): string?
	for uid, item in State.Items() do
		if type(item) == "table" and item.Loc == "Ride" then
			return uid
		end
	end
	return nil
end

-- 머리 위에 들고 있는 펫의 uid (없으면 nil)
function State.HoldItem(): string?
	for uid, item in State.Items() do
		if type(item) == "table" and item.Loc == "Hold" then
			return uid
		end
	end
	return nil
end

-- 따라오는 펫 수
function State.FollowCount(): number
	local n = 0
	for _, item in State.Items() do
		if type(item) == "table" and item.Loc == "Follow" then
			n += 1
		end
	end
	return n
end

function State.RescanPlot()
	local folder = plotsFolder
	if not folder then
		return
	end
	local found: Model? = nil
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == player.UserId then
			found = m
			break
		end
	end
	if not found then
		-- 속성이 아직 안 왔으면 스냅샷의 PlotIndex 로
		local snap = State.Snapshot
		local idx = player:GetAttribute("PlotIndex") or (snap and snap.PlotIndex)
		if idx then
			local m = folder:FindFirstChild("Plot" .. tostring(idx))
			local owner = if m then m:GetAttribute("OwnerUserId") else nil
			if m and m:IsA("Model") and (owner == nil or owner == 0 or owner == player.UserId) then
				found = m
			end
		end
	end
	if found ~= State.Plot then
		State.Plot = found
		for _, fn in plotListeners do
			task.spawn(fn, found)
		end
	end
end

function State.SetSnapshot(snap: any)
	if type(snap) ~= "table" then
		return
	end
	if type(snap.Items) ~= "table" then
		snap.Items = {}
	end
	if type(snap.Index) ~= "table" then
		snap.Index = {}
	end
	if type(snap.Themes) ~= "table" then
		snap.Themes = { Basic = true }
	end
	if type(snap.Theme) ~= "string" then
		snap.Theme = "Basic"
	end
	snap.Floors = math.clamp(math.floor(tonumber(snap.Floors) or 1), 1, 2)
	snap.Income = tonumber(snap.Income) or 0
	snap.Rebirths = math.max(0, math.floor(tonumber(snap.Rebirths) or 0))
	snap.RebirthCost = tonumber(snap.RebirthCost) or Config.RebirthCost(snap.Rebirths)
	local prev = State.Snapshot
	State.Snapshot = snap
	for _, fn in syncListeners do
		task.spawn(fn, snap, prev)
	end
	State.RescanPlot()
end

local function watchPlot(m: Instance)
	m:GetAttributeChangedSignal("OwnerUserId"):Connect(State.RescanPlot)
end

player:GetAttributeChangedSignal("PlotIndex"):Connect(State.RescanPlot)

task.spawn(function()
	local folder = workspace:FindFirstChild("Plots")
	while not folder do
		task.wait(0.5)
		folder = workspace:FindFirstChild("Plots")
	end
	plotsFolder = folder
	for _, m in folder:GetChildren() do
		watchPlot(m)
	end
	folder.ChildAdded:Connect(function(m)
		watchPlot(m)
		State.RescanPlot()
	end)
	folder.ChildRemoved:Connect(function()
		State.RescanPlot()
	end)
	State.RescanPlot()
end)

return State
