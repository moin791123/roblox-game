-- 클라이언트 상태: 서버 스냅샷 + 내 기지 모델 찾기
local Players = game:GetService("Players")

local player = Players.LocalPlayer

export type Item = {
	Kind: string,
	Id: string,
	Loc: string,
	Slot: number?,
	HatchAt: number?,
	HatchLeft: number?,
}

export type Snapshot = {
	Coins: number,
	Pending: number,
	SlotsUnlocked: number,
	Items: { [string]: Item },
	Index: { [string]: boolean },
	PlotIndex: number?,
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
			if m and m:IsA("Model") and m:GetAttribute("OwnerUserId") == nil then
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
