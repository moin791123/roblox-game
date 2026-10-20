-- 🛍 상점 서버: 펫 옷 (사기/입히기) + 가구 (사기/놓기/옮기기/치우기) + 집에 놓인 가구 그리기.
-- (설계: docs/DESIGN.md "ShopService", §5 Remotes, §6 Plot<i>.Furniture)
-- 좌표는 모두 플롯 로컬 (origin = 집 땅 가운데, y = 0, 입구 = -Z). 집 모양 규칙은 HouseLayout 이 정해요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local HouseLayout = require(Shared:WaitForChild("HouseLayout"))
local DataService = require(script.Parent.DataService)
local FollowService = require(script.Parent.FollowService)
local PlotService = require(script.Parent.PlotService)

-- 가구 모델은 다른 모듈이라 실패해도 상점은 살아 있도록 pcall (실패하면 네모 상자로 그려요)
local FurnitureModels: any = nil
do
	local mod = Shared:FindFirstChild("FurnitureModels")
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			FurnitureModels = result
		else
			warn("[ShopService] FurnitureModels 불러오기 실패:", result)
		end
	else
		warn("[ShopService] FurnitureModels 모듈이 없어요 (상자로 그려요)")
	end
end

local ShopService = {}

----------------------------------------------------------------------
-- 상수
----------------------------------------------------------------------
local ACTION_THROTTLE = 0.15 -- 같은 사람 연타 무시 (초)
local MAX_STRING = 32
local EPS = 1e-3 -- 딱 붙는 건 괜찮아요 (겹침/벽 판정 여유)
local FOLDER_NAME = "Furniture"
local DECOR = Config.Decor
local VALID_R = { [0] = true, [90] = true, [180] = true, [270] = true }

local REASON_BAD = "여기에는 놓을 수 없어요!"
local REASON_WALL = "벽 밖이에요!"
local REASON_BLOCKED = "받침대/계단 자리예요!"
local REASON_OVERLAP = "다른 가구랑 겹쳐요!"
local REASON_MAX = string.format("가구는 최대 %d개까지예요!", DECOR.MaxPlaced)

type Furniture = DataService.Furniture
type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

----------------------------------------------------------------------
-- 상태
----------------------------------------------------------------------
local lastAction: { [Player]: number } = {}
local refreshQueued: { [Player]: boolean } = {}
local started = false

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------
local function notify(player: Player, text: string, kind: string?)
	if player.Parent then
		Remotes.Notify:FireClient(player, text, kind or "info")
	end
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

local function isShortString(v: any): boolean
	return type(v) == "string" and #v <= MAX_STRING
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- 마지막 글자 받침이 있으면 a, 없으면 b ("고깔모자를" / "왕관을")
local function josa(name: string, a: string, b: string): string
	local last = nil
	for _, cp in utf8.codes(name) do
		last = cp
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 and (last - 0xAC00) % 28 ~= 0 then
		return name .. a
	end
	return name .. b
end

-- Decor.Snap 단위로 맞추기
local function snap(v: number): number
	local s = DECOR.Snap
	return math.floor(v / s + 0.5) * s
end

-- 0/90/180/270 으로 (아니면 nil)
local function normRot(r: any): number?
	if not isFinite(r) then
		return nil
	end
	local rr = (r :: number) % 360
	if VALID_R[rr] then
		return rr
	end
	return nil
end

local function fidNumber(fid: string): number
	return tonumber(string.match(fid, "^f(%d+)$")) or 0
end

local function footprintRect(furnId: string, x: number, z: number, r: number): Rect
	local sx, sz = Config.FurnitureFootprint(furnId, r)
	return { MinX = x - sx / 2, MaxX = x + sx / 2, MinZ = z - sz / 2, MaxZ = z + sz / 2 }
end

local function overlaps(a: Rect, b: any): boolean
	local bMinX, bMaxX = tonumber(b.MinX), tonumber(b.MaxX)
	local bMinZ, bMaxZ = tonumber(b.MinZ), tonumber(b.MaxZ)
	if not (bMinX and bMaxX and bMinZ and bMaxZ) then
		return false
	end
	return a.MinX < bMaxX - EPS and bMinX < a.MaxX - EPS and a.MinZ < bMaxZ - EPS and bMinZ < a.MaxZ - EPS
end

local function isRug(furnId: string): boolean
	local def = Config.Furniture[furnId]
	return def ~= nil and def.Category == "Rug"
end

-- 놓기 규칙 (CanPlace 와 Validate 가 같이 써요). others = 비교할 다른 가구들 (fid → 가구)
-- x, z 는 이미 Snap 된 값, r 은 0/90/180/270
local function checkPlace(themeId: string, floors: number, furnId: string, floor: number, x: number, z: number, r: number, others: { [string]: Furniture }, ignoreFid: string?): (boolean, string?)
	if not Config.Furniture[furnId] then
		return false, REASON_BAD
	end
	if floor ~= math.floor(floor) or floor < 1 or floor > floors or floor > Config.House.MaxFloors then
		return false, REASON_BAD
	end
	local rect = footprintRect(furnId, x, z, r)

	-- 벽 안쪽 (WallMargin 만큼 띄워서)
	local okB, bounds = pcall(HouseLayout.FloorBounds, themeId, floor)
	if not okB or type(bounds) ~= "table" then
		return false, REASON_BAD
	end
	local m = DECOR.WallMargin
	local minX, maxX = (tonumber(bounds.MinX) or 0) + m, (tonumber(bounds.MaxX) or 0) - m
	local minZ, maxZ = (tonumber(bounds.MinZ) or 0) + m, (tonumber(bounds.MaxZ) or 0) - m
	if rect.MinX < minX - EPS or rect.MaxX > maxX + EPS or rect.MinZ < minZ - EPS or rect.MaxZ > maxZ + EPS then
		return false, REASON_WALL
	end

	-- 받침대 / 계단 / 엘리베이터 / 입구 자리
	local okR, blocked = pcall(HouseLayout.BlockedRects, themeId, floor)
	if okR and type(blocked) == "table" then
		for _, b in blocked do
			if type(b) == "table" and overlaps(rect, b) then
				return false, REASON_BLOCKED
			end
		end
	end

	-- 같은 층 다른 가구 (러그는 위에 겹쳐 놓아도 돼요)
	local rug = isRug(furnId)
	for fid, f in others do
		if fid ~= ignoreFid and f.Floor == floor and not rug and not isRug(f.Id) then
			if overlaps(rect, footprintRect(f.Id, f.X, f.Z, f.R)) then
				return false, REASON_OVERLAP
			end
		end
	end
	return true, nil
end

----------------------------------------------------------------------
-- 놓기 검사 (공개)
----------------------------------------------------------------------
-- 이 가구를 (floor, x, z, r) 에 놓을 수 있나? ignoreFid = 옮기는 중인 자기 자신 (개수 제한도 안 셈)
function ShopService.CanPlace(player: Player, furnId: any, floor: any, x: any, z: any, r: any, ignoreFid: string?): (boolean, string?)
	local data = DataService.Get(player)
	if not data then
		return false, REASON_BAD
	end
	if not isShortString(furnId) or not Config.Furniture[furnId] then
		return false, REASON_BAD
	end
	if not (isFinite(floor) and isFinite(x) and isFinite(z)) then
		return false, REASON_BAD
	end
	local rot = normRot(r)
	if rot == nil then
		return false, REASON_BAD
	end
	local half = Config.Layout.PlotSize / 2
	local sx, sz = snap(x :: number), snap(z :: number)
	if math.abs(sx) > half or math.abs(sz) > half then
		return false, REASON_WALL
	end
	if not ignoreFid and DataService.CountPlacedFurniture(player) >= DECOR.MaxPlaced then
		return false, REASON_MAX
	end
	return checkPlace(data.Theme, data.Floors, furnId :: string, floor :: number, sx, sz, rot, data.Furniture, ignoreFid)
end

----------------------------------------------------------------------
-- 그리기 (Plot<i>.Furniture > F_<fid>)
----------------------------------------------------------------------
local function folderOf(plot: any, create: boolean): Folder?
	local model = plot and plot.Model
	if typeof(model) ~= "Instance" then
		return nil
	end
	local f = (model :: Instance):FindFirstChild(FOLDER_NAME)
	if f and f:IsA("Folder") then
		return f
	end
	if f then
		f:Destroy()
	end
	if not create then
		return nil
	end
	local nf = Instance.new("Folder")
	nf.Name = FOLDER_NAME
	nf.Parent = model
	return nf
end

-- FurnitureModels 가 없거나 실패하면 귀여운 파스텔 상자
local function fallbackModel(furnId: string): Model
	local def = Config.Furniture[furnId]
	local size = if def then def.Size else Vector3.new(2, 2, 2)
	local model = Instance.new("Model")
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = size
	base.Color = Color3.fromHSV((#furnId * 0.137) % 1, 0.35, 1)
	base.Material = Enum.Material.SmoothPlastic
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.CanCollide = if def then def.Collide else true
	base.CanTouch = false
	base.CFrame = CFrame.new(0, size.Y / 2, 0)
	base.PivotOffset = CFrame.new(0, -size.Y / 2, 0)
	base.Parent = model
	model.PrimaryPart = base
	return model
end

local function buildModel(furnId: string): Model
	if FurnitureModels and type(FurnitureModels.Build) == "function" then
		local ok, m = pcall(FurnitureModels.Build, furnId)
		if ok and typeof(m) == "Instance" and m:IsA("Model") then
			return m
		end
		warn("[ShopService] 가구 모델 만들기 실패:", furnId, m)
	end
	return fallbackModel(furnId)
end

local function furnitureCFrame(origin: CFrame, f: Furniture): CFrame
	return origin * CFrame.new(f.X, HouseLayout.FloorY(f.Floor), f.Z) * CFrame.Angles(0, math.rad(f.R), 0)
end

local function renderOne(player: Player, plot: any, fid: string, f: Furniture)
	local folder = folderOf(plot, true)
	if not folder then
		return
	end
	local old = folder:FindFirstChild("F_" .. fid)
	if old then
		old:Destroy()
	end
	local m = buildModel(f.Id)
	m.Name = "F_" .. fid
	m:SetAttribute("Fid", fid)
	m:SetAttribute("FurnitureId", f.Id)
	m:SetAttribute("Floor", f.Floor)
	m:SetAttribute("OwnerUserId", player.UserId)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
		end
	end
	m:PivotTo(furnitureCFrame(plot.Origin, f))
	m.Parent = folder
end

local function removeOne(plot: any, fid: string)
	local folder = folderOf(plot, false)
	if folder then
		local old = folder:FindFirstChild("F_" .. fid)
		if old then
			old:Destroy()
		end
	end
end

-- 내 집의 가구를 전부 다시 그려요
function ShopService.RenderFurniture(player: Player)
	local plot = PlotService.GetPlot(player)
	local data = DataService.Get(player)
	if not plot then
		return
	end
	local folder = folderOf(plot, true)
	if not folder then
		return
	end
	folder:ClearAllChildren()
	if not data then
		return
	end
	for fid, f in data.Furniture do
		local ok, err = pcall(renderOne, player, plot, fid, f)
		if not ok then
			warn("[ShopService] 가구 그리기 오류:", fid, err)
		end
	end
end

-- 집에 안 맞는 가구 (작은 테마로 바꾼 뒤 등) 를 가구 가방으로. 옮긴 개수를 돌려줘요
function ShopService.Validate(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local fids = {}
	for fid in data.Furniture do
		table.insert(fids, fid)
	end
	table.sort(fids, function(a, b)
		return fidNumber(a) < fidNumber(b)
	end)
	local kept: { [string]: Furniture } = {}
	local keptCount = 0
	local moved = 0
	for _, fid in fids do
		local f = data.Furniture[fid]
		local rot = normRot(f.R)
		local ok = false
		if rot ~= nil and isFinite(f.X) and isFinite(f.Z) and isFinite(f.Floor) and keptCount < DECOR.MaxPlaced then
			f.X, f.Z, f.R = snap(f.X), snap(f.Z), rot
			ok = checkPlace(data.Theme, data.Floors, f.Id, f.Floor, f.X, f.Z, f.R, kept, nil)
		end
		if ok then
			kept[fid] = f
			keptCount += 1
		else
			data.Furniture[fid] = nil
			if Config.Furniture[f.Id] and not DataService.AddFurnitureInv(player, f.Id) then
				-- 가방이 꽉 찼으면 최대치로 (넘치는 건 사라져요)
				data.FurnitureInv[f.Id] = DECOR.MaxPerItem
			end
			moved += 1
		end
	end
	if moved > 0 then
		notify(player, string.format("🛋 가구 %d개가 집에 안 맞아서 가구 가방에 넣었어요", moved), "info")
	end
	DataService.Sync(player)
	return moved
end

-- 집 배정 / 다시 짓기 뒤에 한 번만 (같은 프레임에 여러 번 불려도 모아서)
local function scheduleRefresh(player: Player)
	if refreshQueued[player] then
		return
	end
	refreshQueued[player] = true
	task.defer(function()
		refreshQueued[player] = nil
		if player.Parent == nil or not PlotService.GetPlot(player) then
			return
		end
		local ok, err = pcall(function()
			ShopService.Validate(player)
			ShopService.RenderFurniture(player)
		end)
		if not ok then
			warn("[ShopService] 가구 새로 그리기 오류:", err)
		end
	end)
end

local function onPlotChanged(player: Player, plot: any, reason: string)
	if reason == "Release" then
		refreshQueued[player] = nil
		local folder = folderOf(plot, false)
		if folder then
			folder:Destroy()
		end
	else
		scheduleRefresh(player)
	end
end

----------------------------------------------------------------------
-- 옷
----------------------------------------------------------------------
local function onBuyAccessory(player: Player, accId: any)
	local data = DataService.Get(player)
	if not data or not isShortString(accId) or not Config.AccessoryValid(accId) then
		return
	end
	local def = Config.Accessories[accId]
	if data.Wardrobe[accId] then
		notify(player, "이미 옷장에 있어요! 👕", "info")
		return
	end
	if not DataService.TrySpend(player, def.Price) then
		notify(player, string.format("코인이 %s 필요해요 💰", Config.FormatNumber(def.Price)), "warn")
		return
	end
	data.Wardrobe[accId] = true
	notify(player, "👕 " .. josa(def.Name, "을", "를") .. " 샀어요!", "good")
	DataService.Sync(player)
end

local function onEquipAccessory(player: Player, uid: any, accId: any)
	local data = DataService.Get(player)
	if not data or not isShortString(uid) or not isShortString(accId) then
		return
	end
	local item = DataService.GetItem(player, uid)
	if not item or item.Kind ~= "Pet" then
		notify(player, "펫만 옷을 입을 수 있어요! 🐾", "warn")
		return
	end
	local petName = Config.PetDisplayName(item.Id, item.Tier)
	if accId == "" then
		if item.Acc == nil then
			notify(player, "옷을 안 입고 있어요 😊", "info")
			return
		end
		item.Acc = nil
		notify(player, "👕 " .. petName .. "의 옷을 벗겼어요", "info")
	else
		if not Config.AccessoryValid(accId) or not DataService.HasAccessory(player, accId) then
			notify(player, "옷장에 없는 옷이에요! 🛍 상점에서 사 보세요", "warn")
			return
		end
		if item.Acc == accId then
			notify(player, "이미 입고 있어요! 👕", "info")
			return
		end
		item.Acc = accId
		local accName = Config.Accessories[accId].Name
		notify(player, "👕 " .. petName .. "에게 " .. josa(accName, "을", "를") .. " 입혔어요!", "good")
	end
	-- 펫이 있는 곳에서 다시 그리기 (받침대 / 따라옴·타기·들기)
	local ok, err = pcall(function()
		if item.Loc == "Slot" then
			PlotService.PlaceItem(player, uid)
		elseif item.Loc == "Follow" or item.Loc == "Ride" or item.Loc == "Hold" then
			FollowService.Refresh(player)
		end
	end)
	if not ok then
		warn("[ShopService] 옷 입은 펫 다시 그리기 오류:", err)
	end
	DataService.Sync(player)
end

----------------------------------------------------------------------
-- 가구
----------------------------------------------------------------------
local function onBuyFurniture(player: Player, furnId: any)
	local data = DataService.Get(player)
	if not data or not isShortString(furnId) or not Config.Furniture[furnId] then
		return
	end
	local def = Config.Furniture[furnId]
	if (data.FurnitureInv[furnId] or 0) >= DECOR.MaxPerItem then
		notify(player, string.format("가구 가방에 %s 최대 %d개까지예요!", josa(def.Name, "은", "는"), DECOR.MaxPerItem), "warn")
		return
	end
	if not DataService.TrySpend(player, def.Price) then
		notify(player, string.format("코인이 %s 필요해요 💰", Config.FormatNumber(def.Price)), "warn")
		return
	end
	if not DataService.AddFurnitureInv(player, furnId) then
		DataService.AddCoins(player, def.Price) -- 혹시 실패하면 돌려줘요
		notify(player, "가구 가방이 가득 찼어요!", "warn")
		return
	end
	notify(player, "🛋 " .. josa(def.Name, "을", "를") .. " 샀어요! 🪑 꾸미기에서 놓아 보세요", "good")
	DataService.Sync(player)
end

local function onPlaceFurniture(player: Player, furnId: any, floor: any, x: any, z: any, r: any)
	local data = DataService.Get(player)
	if not data or not isShortString(furnId) or not Config.Furniture[furnId] then
		return
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		notify(player, "집이 있어야 가구를 놓을 수 있어요 🏠", "warn")
		return
	end
	if (data.FurnitureInv[furnId] or 0) <= 0 then
		notify(player, "가구 가방에 없어요! 🛍 상점에서 사 보세요", "warn")
		return
	end
	local ok, reason = ShopService.CanPlace(player, furnId, floor, x, z, r, nil)
	if not ok then
		notify(player, "🙅 " .. (reason or REASON_BAD), "warn")
		return
	end
	if not DataService.TakeFurnitureInv(player, furnId) then
		return
	end
	local fid = DataService.NewFurnitureId(player)
	if fid == "" then
		return
	end
	local f: Furniture = { Id = furnId, Floor = floor, X = snap(x), Z = snap(z), R = normRot(r) :: number }
	data.Furniture[fid] = f
	local okR, err = pcall(renderOne, player, plot, fid, f)
	if not okR then
		warn("[ShopService] 가구 그리기 오류:", fid, err)
	end
	DataService.Sync(player)
end

local function onMoveFurniture(player: Player, fid: any, floor: any, x: any, z: any, r: any)
	local data = DataService.Get(player)
	if not data or not isShortString(fid) then
		return
	end
	local f = data.Furniture[fid]
	if not f then
		return
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return
	end
	local ok, reason = ShopService.CanPlace(player, f.Id, floor, x, z, r, fid)
	if not ok then
		notify(player, "🙅 " .. (reason or REASON_BAD), "warn")
		-- 클라이언트가 흐리게 해 둔 모델이 있으면 원래대로 보이게 다시 그려요
		pcall(renderOne, player, plot, fid, f)
		return
	end
	f.Floor = floor
	f.X = snap(x)
	f.Z = snap(z)
	f.R = normRot(r) :: number
	local okR, err = pcall(renderOne, player, plot, fid, f)
	if not okR then
		warn("[ShopService] 가구 그리기 오류:", fid, err)
	end
	DataService.Sync(player)
end

local function onPickupFurniture(player: Player, fid: any)
	local data = DataService.Get(player)
	if not data or not isShortString(fid) then
		return
	end
	local f = data.Furniture[fid]
	if not f then
		return
	end
	if not DataService.AddFurnitureInv(player, f.Id) then
		notify(player, "가구 가방이 가득 찼어요!", "warn")
		return
	end
	data.Furniture[fid] = nil
	local plot = PlotService.GetPlot(player)
	if plot then
		removeOne(plot, fid)
	end
	local def = Config.Furniture[f.Id]
	if def then
		notify(player, "📦 " .. josa(def.Name, "을", "를") .. " 가구 가방에 넣었어요", "info")
	end
	DataService.Sync(player)
end

----------------------------------------------------------------------
-- 시작
----------------------------------------------------------------------
-- PlotService.OnPlotChanged 가 없을 때 대신: 집 모델 속성(주인/테마/층)이 바뀌면 다시 그려요
local function watchPlotsFallback()
	task.spawn(function()
		local folder = workspace:WaitForChild("Plots", 30)
		if not folder then
			return
		end
		local function watch(m: Instance)
			if not m:IsA("Model") then
				return
			end
			local function changed()
				local ownerId = tonumber(m:GetAttribute("OwnerUserId")) or 0
				local owner = if ownerId > 0 then Players:GetPlayerByUserId(ownerId) else nil
				if owner then
					scheduleRefresh(owner)
				else
					local f = m:FindFirstChild(FOLDER_NAME)
					if f then
						f:Destroy()
					end
				end
			end
			for _, attr in { "OwnerUserId", "Theme", "Floors" } do
				m:GetAttributeChangedSignal(attr):Connect(changed)
			end
		end
		for _, m in folder:GetChildren() do
			watch(m)
		end
		folder.ChildAdded:Connect(watch)
	end)
end

function ShopService.Start()
	if started then
		return
	end
	started = true

	local hook = (PlotService :: any).OnPlotChanged
	if type(hook) == "function" then
		hook(function(player: Player, plot: any, reason: string)
			local ok, err = pcall(onPlotChanged, player, plot, reason)
			if not ok then
				warn("[ShopService] OnPlotChanged 오류:", err)
			end
		end)
	else
		warn("[ShopService] PlotService.OnPlotChanged 가 없어요 (집 속성을 지켜봐요)")
		watchPlotsFallback()
	end

	local function connect(remote: RemoteEvent, fn: (Player, ...any) -> ())
		remote.OnServerEvent:Connect(function(player: Player, ...)
			if throttled(player) then
				return
			end
			local ok, err = pcall(fn, player, ...)
			if not ok then
				warn("[ShopService] " .. remote.Name .. " 오류:", err)
			end
		end)
	end
	connect(Remotes.BuyAccessory, onBuyAccessory)
	connect(Remotes.EquipAccessory, onEquipAccessory)
	connect(Remotes.BuyFurniture, onBuyFurniture)
	connect(Remotes.PlaceFurniture, onPlaceFurniture)
	connect(Remotes.MoveFurniture, onMoveFurniture)
	connect(Remotes.PickupFurniture, onPickupFurniture)

	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		refreshQueued[player] = nil
	end)

	-- 이미 집이 있는 사람 (Start 가 늦게 불린 경우)
	for _, player in Players:GetPlayers() do
		if PlotService.GetPlot(player) then
			scheduleRefresh(player)
		end
	end
end

return ShopService
