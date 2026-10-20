-- 🪑 꾸미기 모드: 내 집에 가구를 놓고 / 옮기고 / 돌리고 / 치워요. (설계: docs/DESIGN.md §10 DecorateMode)
-- 고스트(미리보기)는 서버 ShopService.CanPlace 와 같은 규칙(HouseLayout + Config)으로 초록/빨강을 보여 줘요.
-- 서버가 다시 검사하니까 여기 검사는 "미리 알려 주기" 용이에요.
-- PC: 마우스를 따라오는 고스트, 클릭 = 놓기 / R 회전 / X·Delete 치우기 / Esc·Q 끝내기
-- 폰: 바닥을 누르면 고스트가 그 자리로, 고스트를 한 번 더 누르거나 "✅ 놓기" = 놓기
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = UiKit.Config

-- 집 모양 규칙 (HouseLayout, 서버와 같은 모듈). 혹시 못 불러오면 간단한 대신 규칙으로 (서버가 어차피 다시 검사해요)
local HouseLayout: any = nil
do
	local mod = Shared:WaitForChild("HouseLayout", 10)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			HouseLayout = result
		else
			warn("[DecorateMode] HouseLayout 불러오기 실패:", result)
		end
	else
		warn("[DecorateMode] HouseLayout 모듈이 없어요 (간단한 규칙으로 미리 보여 줘요)")
	end
	if type(HouseLayout) ~= "table" then
		HouseLayout = {
			FloorY = function(floor: number): number
				return 0.2 + (floor - 1) * Config.House.FloorHeight
			end,
			FloorBounds = function(themeId: string, _floor: number): any
				local half = Config.ThemeSize(themeId) / 2 - 0.5
				return { MinX = -half, MaxX = half, MinZ = -half, MaxZ = half }
			end,
			BlockedRects = function(_themeId: string, _floor: number): any
				return {}
			end,
		}
	end
end

-- 가구 모델은 다른 모듈이라 처음 쓸 때 pcall 로 불러요 (실패하면 네모 상자)
local FurnitureModels: any = nil
local furnitureTried = false
local function getFurnitureModels(): any
	if not furnitureTried then
		furnitureTried = true
		local mod = Shared:FindFirstChild("FurnitureModels")
		if mod and mod:IsA("ModuleScript") then
			local ok, result = pcall(require, mod)
			if ok then
				FurnitureModels = result
			else
				warn("[DecorateMode] FurnitureModels 불러오기 실패:", result)
			end
		end
	end
	return FurnitureModels
end

local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer

local DecorateMode = {}

----------------------------------------------------------------------
-- 상수
----------------------------------------------------------------------
local DECOR = Config.Decor
-- 1 스터드 격자 (서버 Decor.Snap 의 배수라서 서버에서도 같은 자리)
local GRID = DECOR.Snap * math.max(1, math.floor(1 / DECOR.Snap + 0.5))
local EPS = 1e-3
local FIRE_GAP = 0.25 -- 서버 요청 간격 (서버는 0.15 초)
local TELEPORT_GAP = 1.6 -- 서버 Teleport 제한 1.5 초
local TELEPORT_GRACE = 3 -- 순간이동 뒤 이만큼은 층/집 밖 검사 안 함
local CHECK_EVERY = 0.5
local LEAVE_TIME = 1.5 -- 집 땅 밖에 이만큼 있으면 끝내요
local GHOST_LIFT = 0.05
local MAX_RAY = 1500

local COLOR_OK = Color3.fromRGB(90, 230, 120)
local COLOR_BAD = Color3.fromRGB(255, 80, 95)

local REASON_BAD = "여기에는 놓을 수 없어요!"
local REASON_WALL = "벽 밖이에요!"
local REASON_BLOCKED = "받침대/계단 자리예요!"
local REASON_OVERLAP = "다른 가구랑 겹쳐요!"
local REASON_MAX = string.format("가구는 최대 %d개까지예요!", DECOR.MaxPlaced)

type Piece = { Id: string, Floor: number, X: number, Z: number, R: number }
type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
type Tile = { Button: TextButton, Stroke: UIStroke, Count: TextLabel }
type Mode = "Idle" | "Place" | "Selected" | "Move"

----------------------------------------------------------------------
-- 상태
----------------------------------------------------------------------
local active = false
local mode: Mode = "Idle"
local editFloor = 1
local placeId: string? = nil -- 가방에서 꺼내 놓을 가구 id (Place)
local selFid: string? = nil -- 고른 놓인 가구 (Selected / Move)
local rot = 0
local gx: number? = nil
local gz: number? = nil
local ghostValid = false
local ghostReason: string? = nil
local ghostKey = ""
local syncVersion = 0

local enteredPlot: Model? = nil
local ghostFolder: Folder? = nil
local ghost: Model? = nil
local ghostId: string? = nil
local ghostHl: Highlight? = nil
local plate: Part? = nil
local selHl: Highlight? = nil
local fadedModel: Model? = nil

local conns: { RBXScriptConnection } = {}
local changedListeners: { (boolean) -> () } = {}
local shopOpener: (() -> ())? = nil

-- 서버 답(DataSync)이 오기 전까지 내가 보낸 것 (다음 Sync 때 비워요)
local pendingTaken: { [string]: number } = {}
local pendingNew: { Piece } = {}
local pendingOverride: { [string]: Piece | false } = {}

local lastFire = 0
local lastTeleport = -100
local teleportGraceUntil = 0
local queuedTeleport: number? = nil
local teleportScheduled = false
local outsideSince: number? = nil
local lastCheck = 0
local lastMouse: Vector2? = nil
local lastCam: CFrame? = nil

-- UI
local hostGui: Instance? = nil
local ownScreen: ScreenGui? = nil
local root: Frame? = nil
local bottomPanel: Frame
local column: Frame
local hintPill: Frame
local hintLabel: TextLabel
local countLabel: TextLabel
local floorLabel: TextLabel
local floorUpButton: TextButton
local floorDownButton: TextButton
local tray: ScrollingFrame
local emptyFrame: Frame
local tiles: { [string]: Tile } = {}
local actionButtons: { [string]: TextButton } = {}
local scales: { UIScale } = {}

----------------------------------------------------------------------
-- 작은 도우미
----------------------------------------------------------------------
local function snapshot(): any
	return State.Snapshot
end

local function snapGrid(v: number): number
	return math.floor(v / GRID + 0.5) * GRID
end

local function themeId(): string
	local snap = snapshot()
	return if snap and type(snap.Theme) == "string" then snap.Theme else "Basic"
end

local function floorsCount(): number
	local snap = snapshot()
	return math.clamp(math.floor(tonumber(snap and snap.Floors) or 1), 1, Config.House.MaxFloors)
end

local function plotOrigin(): CFrame?
	local plot = State.Plot
	local snap = snapshot()
	local idx = (plot and tonumber(plot:GetAttribute("PlotIndex"))) or tonumber(player:GetAttribute("PlotIndex")) or (snap and tonumber(snap.PlotIndex))
	if not idx then
		return nil
	end
	return Config.Layout.Plots[idx]
end

local function invCount(furnId: string): number
	local snap = snapshot()
	local inv = if snap and type(snap.FurnitureInv) == "table" then snap.FurnitureInv else {}
	return math.max(0, (tonumber(inv[furnId]) or 0) - (pendingTaken[furnId] or 0))
end

local function furnitureName(furnId: string?): string
	local def = furnId and Config.Furniture[furnId]
	return if def then def.Name else "가구"
end

local function character(): (BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return if hrp and hrp:IsA("BasePart") then hrp else nil, hum
end

local function canFire(): boolean
	if os.clock() - lastFire < FIRE_GAP then
		return false
	end
	lastFire = os.clock()
	return true
end

-- 놓인 가구 (서버 스냅샷 + 아직 답이 안 온 내 요청)
local function placedMap(): { [string]: Piece }
	local out: { [string]: Piece } = {}
	local snap = snapshot()
	local furn = if snap and type(snap.Furniture) == "table" then snap.Furniture else {}
	for fid, f in furn do
		if type(fid) == "string" and type(f) == "table" and type(f.Id) == "string" and Config.Furniture[f.Id] then
			out[fid] = {
				Id = f.Id,
				Floor = tonumber(f.Floor) or 1,
				X = tonumber(f.X) or 0,
				Z = tonumber(f.Z) or 0,
				R = tonumber(f.R) or 0,
			}
		end
	end
	for fid, p in pendingOverride do
		if p == false then
			out[fid] = nil
		elseif out[fid] then
			out[fid] = p :: Piece
		end
	end
	for i, p in pendingNew do
		out["~" .. tostring(i)] = p
	end
	return out
end

local function countPlaced(): number
	local n = 0
	for _ in placedMap() do
		n += 1
	end
	return n
end

----------------------------------------------------------------------
-- 놓기 규칙 (서버 ShopService.CanPlace 와 똑같이)
----------------------------------------------------------------------
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

local function canPlaceLocal(furnId: string, floor: number, x: number, z: number, r: number, ignoreFid: string?): (boolean, string?)
	if not snapshot() or not Config.Furniture[furnId] then
		return false, REASON_BAD
	end
	if floor ~= math.floor(floor) or floor < 1 or floor > floorsCount() then
		return false, REASON_BAD
	end
	local half = Config.Layout.PlotSize / 2
	if math.abs(x) > half or math.abs(z) > half then
		return false, REASON_WALL
	end
	local placed = placedMap()
	if not ignoreFid then
		local n = 0
		for _ in placed do
			n += 1
		end
		if n >= DECOR.MaxPlaced then
			return false, REASON_MAX
		end
	end
	local theme = themeId()
	local rect = footprintRect(furnId, x, z, r)

	local okB, bounds = pcall(HouseLayout.FloorBounds, theme, floor)
	if not okB or type(bounds) ~= "table" then
		return false, REASON_BAD
	end
	local m = DECOR.WallMargin
	local minX, maxX = (tonumber(bounds.MinX) or 0) + m, (tonumber(bounds.MaxX) or 0) - m
	local minZ, maxZ = (tonumber(bounds.MinZ) or 0) + m, (tonumber(bounds.MaxZ) or 0) - m
	if rect.MinX < minX - EPS or rect.MaxX > maxX + EPS or rect.MinZ < minZ - EPS or rect.MaxZ > maxZ + EPS then
		return false, REASON_WALL
	end

	local okR, blocked = pcall(HouseLayout.BlockedRects, theme, floor)
	if okR and type(blocked) == "table" then
		for _, b in blocked do
			if type(b) == "table" and overlaps(rect, b) then
				return false, REASON_BLOCKED
			end
		end
	end

	local rug = isRug(furnId)
	for fid, f in placed do
		if fid ~= ignoreFid and f.Floor == floor and not rug and not isRug(f.Id) then
			if overlaps(rect, footprintRect(f.Id, f.X, f.Z, f.R)) then
				return false, REASON_OVERLAP
			end
		end
	end
	return true, nil
end

----------------------------------------------------------------------
-- 위치 계산 (화면 → 집 로컬 바닥)
----------------------------------------------------------------------
local function floorWorldY(origin: CFrame): number
	return (origin * CFrame.new(0, HouseLayout.FloorY(editFloor), 0)).Position.Y
end

-- 화면 좌표(뷰포트) → 바닥 평면 위 로컬 (x, z). 못 맞추면 nil
local function rayToLocal(ray: Ray): (number?, number?)
	local origin = plotOrigin()
	if not origin then
		return nil, nil
	end
	local dy = ray.Direction.Y
	if math.abs(dy) < 1e-4 then
		return nil, nil
	end
	local t = (floorWorldY(origin) - ray.Origin.Y) / dy
	if t <= 0 or t > MAX_RAY then
		return nil, nil
	end
	local p = origin:PointToObjectSpace(ray.Origin + ray.Direction * t)
	return p.X, p.Z
end

local function viewportRay(pos: Vector2): Ray?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	return cam:ViewportPointToRay(pos.X, pos.Y)
end

-- 캐릭터가 있는 층, 집 안인지, 집 땅 위인지
local function characterWhere(): (number, boolean, boolean)
	local hrp, hum = character()
	local origin = plotOrigin()
	if not hrp or not origin then
		return 1, false, false
	end
	local p = origin:PointToObjectSpace(hrp.Position)
	local half = Config.Layout.PlotSize / 2
	local onPlot = math.abs(p.X) <= half + 6 and math.abs(p.Z) <= half + 6
	local feet = p.Y - (hrp.Size.Y / 2 + (if hum then hum.HipHeight else 2))
	local fh = Config.House.FloorHeight
	local f = math.clamp(math.floor((feet - HouseLayout.FloorY(1)) / fh + 0.5) + 1, 1, floorsCount())
	local inside = false
	local ok, b = pcall(HouseLayout.FloorBounds, themeId(), f)
	if ok and type(b) == "table" then
		local minX, maxX = tonumber(b.MinX) or 0, tonumber(b.MaxX) or 0
		local minZ, maxZ = tonumber(b.MinZ) or 0, tonumber(b.MaxZ) or 0
		inside = p.X >= minX - 1 and p.X <= maxX + 1 and p.Z >= minZ - 1 and p.Z <= maxZ + 1
	end
	return f, inside, onPlot
end

-- 광선이 고스트 상자(가구 크기 + 여유)에 닿나 (폰: 고스트를 한 번 더 누르면 놓기)
local function slab(o: number, d: number, lo: number, hi: number, tmin: number, tmax: number): (number, number)
	if math.abs(d) < 1e-6 then
		if o < lo or o > hi then
			return 1, 0
		end
		return tmin, tmax
	end
	local t1, t2 = (lo - o) / d, (hi - o) / d
	if t1 > t2 then
		t1, t2 = t2, t1
	end
	return math.max(tmin, t1), math.min(tmax, t2)
end

local function rayHitsGhost(ray: Ray): boolean
	local m, id = ghost, ghostId
	if not m or not id or not m.Parent then
		return false
	end
	local def = Config.Furniture[id]
	if not def then
		return false
	end
	local cf = m:GetPivot()
	local o = cf:PointToObjectSpace(ray.Origin)
	local d = cf:VectorToObjectSpace(ray.Direction)
	local hx, hz = def.Size.X / 2 + 0.6, def.Size.Z / 2 + 0.6
	local tmin, tmax = -math.huge, math.huge
	tmin, tmax = slab(o.X, d.X, -hx, hx, tmin, tmax)
	tmin, tmax = slab(o.Y, d.Y, -0.5, def.Size.Y + 0.6, tmin, tmax)
	tmin, tmax = slab(o.Z, d.Z, -hz, hz, tmin, tmax)
	return tmin <= tmax and tmax >= 0
end

----------------------------------------------------------------------
-- 놓인 가구 모델 찾기 / 고르기
----------------------------------------------------------------------
local function furnitureFolder(): Instance?
	local plot = State.Plot
	return if plot then plot:FindFirstChild("Furniture") else nil
end

local function modelOf(fid: string?): Model?
	local folder = furnitureFolder()
	if not folder or not fid then
		return nil
	end
	local m = folder:FindFirstChild("F_" .. fid)
	return if m and m:IsA("Model") then m else nil
end

-- 누른 곳의 놓인 가구 (이 층만). 광선이 안 맞으면 바닥 발자국으로 찾아요
local function pickFurniture(ray: Ray): string?
	local folder = furnitureFolder()
	local placed = placedMap()
	if folder then
		local list: { Instance } = {}
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and tonumber(m:GetAttribute("Floor")) == editFloor then
				table.insert(list, m)
			end
		end
		if #list > 0 then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = list
			local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_RAY, params)
			if result then
				local node: Instance? = result.Instance
				while node and node ~= folder do
					local fid = node:GetAttribute("Fid")
					if type(fid) == "string" and placed[fid] then
						return fid
					end
					node = node.Parent
				end
			end
		end
	end
	-- 바닥 위치로 (러그가 아닌 가구 먼저)
	local x, z = rayToLocal(ray)
	if not x or not z then
		return nil
	end
	local rugHit: string? = nil
	for fid, f in placed do
		if f.Floor == editFloor and string.sub(fid, 1, 1) ~= "~" then
			local r = footprintRect(f.Id, f.X, f.Z, f.R)
			if x >= r.MinX and x <= r.MaxX and z >= r.MinZ and z <= r.MaxZ then
				if not isRug(f.Id) then
					return fid
				end
				rugHit = fid
			end
		end
	end
	return rugHit
end

local function setFade(m: Model?, on: boolean)
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if on then 0.75 else 0
		end
	end
end

----------------------------------------------------------------------
-- 고스트
----------------------------------------------------------------------
local function buildFurniture(furnId: string): Model
	local fm = getFurnitureModels()
	if fm and type(fm.Build) == "function" then
		local ok, m = pcall(fm.Build, furnId)
		if ok and typeof(m) == "Instance" and m:IsA("Model") then
			return m
		end
	end
	local def = Config.Furniture[furnId]
	local size = if def then def.Size else Vector3.new(2, 2, 2)
	local model = Instance.new("Model")
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = size
	base.CFrame = CFrame.new(0, size.Y / 2, 0)
	base.PivotOffset = CFrame.new(0, -size.Y / 2, 0)
	base.Color = C.Lavender
	base.Parent = model
	model.PrimaryPart = base
	return model
end

local function hideGhost()
	if ghost then
		ghost.Parent = nil
	end
	if plate then
		plate.Parent = nil
	end
end

local function destroyGhost()
	if ghost then
		ghost:Destroy()
	end
	if plate then
		plate:Destroy()
	end
	ghost, ghostId, ghostHl, plate = nil, nil, nil, nil
	gx, gz = nil, nil
	ghostKey = ""
end

local function makeGhost(furnId: string)
	destroyGhost()
	local m = buildFurniture(furnId)
	m.Name = "DecorGhost"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if d.Transparency < 1 then
				d.Transparency = math.max(d.Transparency, 0.3)
			end
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local hl = Instance.new("Highlight")
	hl.FillColor = COLOR_OK
	hl.FillTransparency = 0.5
	hl.OutlineColor = C.White
	hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = m
	hl.Parent = m

	local p = Instance.new("Part")
	p.Name = "DecorFootprint"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 0.55
	p.Color = COLOR_OK
	p.Size = Vector3.new(1, 0.08, 1)

	ghost, ghostId, ghostHl, plate = m, furnId, hl, p
	ghostKey = ""
end

local updateHint: () -> ()

-- 고스트를 (gx, gz, rot) 에 두고 초록/빨강 다시 계산
local function refreshGhost(force: boolean?)
	local m, id, p, hl = ghost, ghostId, plate, ghostHl
	local origin = plotOrigin()
	if not m or not id or not p or not hl or not origin then
		return
	end
	if gx == nil or gz == nil then
		hideGhost()
		updateHint()
		return
	end
	local x, z = gx :: number, gz :: number
	local ignore = if mode == "Move" then selFid else nil
	local key = string.format("%s|%d|%.2f|%.2f|%d|%d|%s", id, editFloor, x, z, rot, syncVersion, tostring(ignore))
	if key == ghostKey and not force and m.Parent then
		return
	end
	ghostKey = key
	ghostValid, ghostReason = canPlaceLocal(id, editFloor, x, z, rot, ignore)
	local y = HouseLayout.FloorY(editFloor)
	m:PivotTo(origin * CFrame.new(x, y + GHOST_LIFT, z) * CFrame.Angles(0, math.rad(rot), 0))
	local sx, sz = Config.FurnitureFootprint(id, rot)
	p.Size = Vector3.new(math.max(sx, 0.2), 0.08, math.max(sz, 0.2))
	p.CFrame = origin * CFrame.new(x, y + 0.06, z)
	local color = if ghostValid then COLOR_OK else COLOR_BAD
	hl.FillColor = color
	p.Color = color
	local folder = ghostFolder
	if folder then
		m.Parent = folder
		p.Parent = folder
	end
	updateHint()
end

local function setGhostAt(x: number, z: number)
	gx, gz = snapGrid(x), snapGrid(z)
	refreshGhost()
end

-- 캐릭터 앞 (없으면 바닥 가운데)
local function defaultSpot(): (number, number)
	local origin = plotOrigin()
	local hrp = character()
	if origin and hrp then
		local p = origin:PointToObjectSpace(hrp.Position + hrp.CFrame.LookVector * 5)
		return p.X, p.Z
	end
	local ok, b = pcall(HouseLayout.FloorBounds, themeId(), editFloor)
	if ok and type(b) == "table" then
		return ((tonumber(b.MinX) or 0) + (tonumber(b.MaxX) or 0)) / 2, ((tonumber(b.MinZ) or 0) + (tonumber(b.MaxZ) or 0)) / 2
	end
	return 0, 0
end

local function isTouchInput(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

----------------------------------------------------------------------
-- 모드 바꾸기
----------------------------------------------------------------------
local refreshTray: () -> ()
local refreshButtons: () -> ()

local function clearSelection()
	if selHl then
		selHl.Adornee = nil
	end
end

local function unfade()
	if fadedModel then
		setFade(fadedModel, false)
		fadedModel = nil
	end
end

local function setMode(newMode: Mode)
	-- 고스트는 놓기/옮기기 때만
	if newMode ~= "Place" and newMode ~= "Move" then
		destroyGhost()
	end
	if mode == "Move" and newMode ~= "Move" then
		unfade()
	end
	if newMode ~= "Place" then
		placeId = nil
	end
	if newMode == "Idle" or newMode == "Place" then
		selFid = nil
		clearSelection()
	end
	mode = newMode
	refreshButtons()
	refreshTray()
	updateHint()
end

local function startPlace(furnId: string)
	if invCount(furnId) <= 0 then
		Toasts.Show("가구 가방에 없어요! 🛍 상점에서 사 보세요", "warn")
		return
	end
	local keepSpot = mode == "Place" and gx ~= nil
	local oldX, oldZ = gx, gz
	setMode("Place")
	placeId = furnId
	rot = 0
	makeGhost(furnId)
	if keepSpot and oldX and oldZ then
		setGhostAt(oldX, oldZ)
	else
		local x, z = defaultSpot()
		setGhostAt(x, z)
	end
	refreshTray()
	UiKit.PlaySound("Click")
end

local function selectPiece(fid: string)
	local piece = placedMap()[fid]
	if not piece then
		return
	end
	setMode("Selected")
	selFid = fid
	if selHl then
		selHl.Adornee = modelOf(fid)
	end
	refreshButtons()
	updateHint()
	UiKit.PlaySound("Click")
end

local function startMove()
	local fid = selFid
	local piece = if fid then placedMap()[fid] else nil
	if not fid or not piece then
		setMode("Idle")
		return
	end
	mode = "Move"
	clearSelection()
	makeGhost(piece.Id)
	rot = piece.R
	unfade()
	fadedModel = modelOf(fid)
	setFade(fadedModel, true)
	gx, gz = piece.X, piece.Z
	refreshGhost(true)
	refreshButtons()
	updateHint()
end

----------------------------------------------------------------------
-- 행동 (놓기 / 회전 / 치우기 / 취소)
----------------------------------------------------------------------
local function confirm()
	local id = ghostId
	if not id or gx == nil or gz == nil then
		Toasts.Show("👆 놓을 곳을 먼저 눌러요!", "info")
		return
	end
	refreshGhost(true)
	if not ghostValid then
		Toasts.Show("🙅 " .. (ghostReason or REASON_BAD), "warn")
		if hintPill then
			UiKit.Shake(hintPill, 5, 6)
		end
		return
	end
	if not canFire() then
		return
	end
	local x, z = gx :: number, gz :: number
	local piece: Piece = { Id = id, Floor = editFloor, X = x, Z = z, R = rot }
	if mode == "Place" and placeId then
		local furnId = placeId :: string
		if invCount(furnId) <= 0 then
			Toasts.Show("가구 가방에 없어요!", "warn")
			setMode("Idle")
			return
		end
		Remotes.PlaceFurniture:FireServer(furnId, editFloor, x, z, rot)
		pendingTaken[furnId] = (pendingTaken[furnId] or 0) + 1
		table.insert(pendingNew, piece)
		UiKit.PlaySound("Buy")
		if invCount(furnId) <= 0 then
			setMode("Idle")
		else
			-- 같은 가구를 또 놓을 수 있게 그대로 (방금 놓은 자리는 이제 빨강)
			refreshGhost(true)
			refreshTray()
		end
	elseif mode == "Move" and selFid then
		local fid = selFid :: string
		Remotes.MoveFurniture:FireServer(fid, editFloor, x, z, rot)
		pendingOverride[fid] = piece
		UiKit.PlaySound("Buy")
		-- 서버가 새 모델을 그리면 흐린 옛 모델은 사라져요. 혹시 안 오면 다시 보이게
		local old = fadedModel
		fadedModel = nil
		task.delay(2.5, function()
			if old and old.Parent then
				setFade(old, false)
			end
		end)
		destroyGhost()
		mode = "Selected"
		selFid = fid
		if selHl then
			selHl.Adornee = nil -- 새 모델이 오면 다시 붙여요 (onRender)
		end
		refreshButtons()
		updateHint()
	end
end

local function rotate()
	if mode == "Place" or mode == "Move" then
		rot = (rot + 90) % 360
		refreshGhost(true)
		UiKit.PlaySound("Click")
	elseif mode == "Selected" and selFid then
		local fid = selFid :: string
		local piece = placedMap()[fid]
		if not piece then
			setMode("Idle")
			return
		end
		local newR = (piece.R + 90) % 360
		local ok, reason = canPlaceLocal(piece.Id, piece.Floor, piece.X, piece.Z, newR, fid)
		if not ok then
			Toasts.Show("🙅 돌리면 " .. (reason or REASON_BAD), "warn")
			return
		end
		if not canFire() then
			return
		end
		Remotes.MoveFurniture:FireServer(fid, piece.Floor, piece.X, piece.Z, newR)
		pendingOverride[fid] = { Id = piece.Id, Floor = piece.Floor, X = piece.X, Z = piece.Z, R = newR }
		UiKit.PlaySound("Click")
	else
		Toasts.Show("돌릴 가구를 먼저 골라요! 🛋", "info")
	end
end

local function pickup()
	if (mode == "Selected" or mode == "Move") and selFid then
		if not canFire() then
			return
		end
		local fid = selFid :: string
		Remotes.PickupFurniture:FireServer(fid)
		pendingOverride[fid] = false
		local m = if mode == "Move" then fadedModel else nil
		fadedModel = nil
		if m then
			task.delay(2.5, function()
				if m.Parent then
					setFade(m, false)
				end
			end)
		end
		UiKit.PlaySound("Click")
		setMode("Idle")
	elseif mode == "Place" then
		setMode("Idle")
	else
		Toasts.Show("치울 가구를 먼저 눌러요! 📦", "info")
	end
end

local function cancel()
	if mode == "Move" then
		destroyGhost()
		unfade()
		local fid = selFid
		mode = "Selected"
		if fid then
			selectPiece(fid)
		else
			setMode("Idle")
		end
	else
		setMode("Idle")
	end
end

----------------------------------------------------------------------
-- 층 바꾸기 / 순간이동
----------------------------------------------------------------------
local function requestTeleport(floor: number)
	queuedTeleport = floor
	teleportGraceUntil = os.clock() + TELEPORT_GRACE
	local function go()
		local target = queuedTeleport
		if not active or target == nil then
			return
		end
		queuedTeleport = nil
		lastTeleport = os.clock()
		teleportGraceUntil = os.clock() + TELEPORT_GRACE
		Remotes.Teleport:FireServer("Floor", target)
	end
	local waitLeft = TELEPORT_GAP - (os.clock() - lastTeleport)
	if waitLeft <= 0 then
		go()
	elseif not teleportScheduled then
		teleportScheduled = true
		task.delay(waitLeft, function()
			teleportScheduled = false
			go()
		end)
	end
end

local function refreshFloorLabel()
	if not root then
		return
	end
	local floors = floorsCount()
	floorLabel.Text = string.format("🏠 %d층", editFloor)
	floorUpButton.BackgroundColor3 = if editFloor < floors then C.Sky else C.Grey
	floorDownButton.BackgroundColor3 = if editFloor > 1 then C.Sky else C.Grey
end

local function setEditFloor(floor: number, teleport: boolean)
	local f = math.clamp(floor, 1, floorsCount())
	if f == editFloor then
		return
	end
	editFloor = f
	if mode == "Selected" or mode == "Move" then
		setMode("Idle")
	elseif mode == "Place" then
		gx, gz = nil, nil
		hideGhost()
	end
	if teleport then
		requestTeleport(f)
	end
	ghostKey = ""
	refreshFloorLabel()
	updateHint()
end

local function changeFloor(delta: number)
	local target = editFloor + delta
	if target < 1 then
		Toasts.Show("여기가 1층이에요! 🏠", "info")
		return
	end
	if target > floorsCount() then
		Toasts.Show("더 높은 층이 없어요! 🏗 집 창에서 층을 올려요", "info")
		return
	end
	setEditFloor(target, true)
	if mode == "Place" and ghost then
		-- 순간이동이 끝나면 캐릭터 앞에 다시 보여 줘요
		task.delay(0.8, function()
			if active and mode == "Place" and gx == nil then
				local x, z = defaultSpot()
				setGhostAt(x, z)
			end
		end)
	end
end

----------------------------------------------------------------------
-- 입력
----------------------------------------------------------------------
-- pos = 뷰포트 좌표. isTouch 면 "두 번 눌러 놓기"
local function onWorldPress(pos: Vector2, isTouch: boolean)
	local ray = viewportRay(pos)
	if not ray then
		return
	end
	if mode == "Place" or mode == "Move" then
		if isTouch then
			if gx ~= nil and ghost and ghost.Parent and rayHitsGhost(ray) then
				confirm()
				return
			end
			local x, z = rayToLocal(ray)
			if x and z then
				setGhostAt(x, z)
			end
		else
			local x, z = rayToLocal(ray)
			if x and z then
				setGhostAt(x, z)
				confirm()
			end
		end
	else
		local fid = pickFurniture(ray)
		if fid then
			if fid == selFid and mode == "Selected" then
				return
			end
			selectPiece(fid)
		elseif mode == "Selected" then
			setMode("Idle")
		end
	end
end

-- 마우스가 꾸미기 UI 위에 있나 (그때는 고스트를 움직이지 않아요)
local function mouseOverUi(mouse: Vector2): boolean
	local inset = GuiService:GetGuiInset()
	local p = mouse - inset
	for _, frame in { bottomPanel, column } do
		if frame and frame.Visible then
			local a, s = frame.AbsolutePosition, frame.AbsoluteSize
			if p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y then
				return true
			end
		end
	end
	return false
end

local function onRender()
	if not active then
		return
	end
	-- PC: 고스트가 마우스를 따라와요
	if (mode == "Place" or mode == "Move") and ghost and UserInputService.MouseEnabled and not isTouchInput() then
		local mouse = UserInputService:GetMouseLocation()
		local cam = workspace.CurrentCamera
		local camCf = if cam then cam.CFrame else nil
		if mouse ~= lastMouse or camCf ~= lastCam or ghostKey == "" then
			lastMouse = mouse
			lastCam = camCf
			if not mouseOverUi(mouse) then
				local ray = viewportRay(mouse)
				if ray then
					local x, z = rayToLocal(ray)
					if x and z then
						setGhostAt(x, z)
					end
				end
			end
		end
	end
	-- 고른 가구 테두리 (서버가 모델을 새로 그리면 다시 붙여요)
	if mode == "Selected" and selHl then
		local hl = selHl :: Highlight
		local adornee = hl.Adornee
		if not adornee or not adornee.Parent then
			hl.Adornee = modelOf(selFid)
		end
	end

	-- 가끔: 층 따라가기 / 집 밖이면 끝내기
	local now = os.clock()
	if now - lastCheck < CHECK_EVERY then
		return
	end
	lastCheck = now
	if now < teleportGraceUntil then
		outsideSince = nil
		return
	end
	local floor, inside, onPlot = characterWhere()
	if not onPlot then
		outsideSince = outsideSince or now
		if now - (outsideSince :: number) > LEAVE_TIME then
			Toasts.Show("🏠 집에서 나가서 꾸미기를 끝냈어요", "info")
			DecorateMode.Exit()
		end
		return
	end
	outsideSince = nil
	if inside and floor ~= editFloor and mode ~= "Move" then
		setEditFloor(floor, false)
		if mode == "Place" and ghost and gx == nil then
			local x, z = defaultSpot()
			setGhostAt(x, z)
		end
	end
end

local function onInput(input: InputObject, processed: boolean)
	if not active then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Escape then
			DecorateMode.Exit()
			return
		end
		if processed then
			return
		end
		if key == Enum.KeyCode.Q then
			DecorateMode.Exit()
		elseif key == Enum.KeyCode.R then
			rotate()
		elseif key == Enum.KeyCode.X or key == Enum.KeyCode.Delete or key == Enum.KeyCode.Backspace then
			pickup()
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
			if mode == "Place" or mode == "Move" then
				confirm()
			end
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		if processed then
			return
		end
		onWorldPress(UserInputService:GetMouseLocation(), false)
	end
end

local function onTouchTap(position: Vector2, processedByUI: boolean)
	-- 마우스 클릭은 onInput 에서 (두 번 처리하지 않게)
	if not active or processedByUI or not isTouchInput() then
		return
	end
	onWorldPress(position, true)
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function updateHint()
	if not root or not active then
		return
	end
	local text: string
	local color = C.Sky
	if mode == "Place" or mode == "Move" then
		if gx == nil then
			text = "👆 놓을 곳을 눌러요"
		elseif ghostValid then
			text = if isTouchInput() then "✅ 좋아요! 한 번 더 누르면 놓아요" else "✅ 여기에 놓을 수 있어요! (클릭)"
			color = C.Mint
		else
			text = "❌ " .. (ghostReason or REASON_BAD)
			color = C.Red
		end
		if mode == "Move" then
			text = "✋ " .. text
		end
	elseif mode == "Selected" then
		local piece = if selFid then placedMap()[selFid] else nil
		text = "🛋 " .. furnitureName(piece and piece.Id) .. " · 옮기기 / 회전 / 치우기"
		color = C.Gold
	else
		local hasInv = false
		for furnId in Config.Furniture do
			if invCount(furnId) > 0 then
				hasInv = true
				break
			end
		end
		text = if hasInv then "👇 가구를 고르거나, 놓인 가구를 눌러요" else "🛋 놓인 가구를 누르거나 🛍 상점에서 사 와요"
	end
	hintLabel.Text = text
	hintPill.BackgroundColor3 = color
	countLabel.Text = string.format("🛋 %d/%d", countPlaced(), DECOR.MaxPlaced)
end

function refreshButtons()
	if not root then
		return
	end
	local show: { [string]: boolean } = {
		Place = mode == "Place" or mode == "Move",
		Rotate = mode ~= "Idle",
		Move = mode == "Selected",
		Pickup = mode == "Selected" or mode == "Move",
		Cancel = mode ~= "Idle",
	}
	local any = false
	for name, btn in actionButtons do
		btn.Visible = show[name] == true
		any = any or btn.Visible
	end
	column.Visible = any
end

local function makeTile(furnId: string): Tile
	local def = Config.Furniture[furnId]
	local btn: TextButton = Make("TextButton", {
		Name = furnId,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.White,
		Size = UDim2.new(0, 86, 1, -10),
		LayoutOrder = def.Order,
		Parent = tray,
	})
	UiKit.Corner(btn, UDim.new(0, 14))
	UiKit.Gradient(btn)
	local stroke = UiKit.Stroke(btn, C.Lavender, 3, true)
	local holder: Frame = Make("Frame", {
		Name = "View",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.08, 0.04),
		Size = UDim2.fromScale(0.84, 0.6),
		Parent = btn,
	})
	UiKit.FurnitureViewport(furnId, holder)
	UiKit.Label({
		Text = def.Name,
		Position = UDim2.fromScale(0.04, 0.66),
		Size = UDim2.fromScale(0.92, 0.28),
		Parent = btn,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.45), MaxText = 15 })
	local pill: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(36, 22),
		BackgroundColor3 = C.Pink,
		Parent = btn,
	})
	UiKit.Corner(pill, UDim.new(0.5, 0))
	UiKit.Stroke(pill, C.White, 2, true)
	local count = UiKit.Label({
		Text = "×1",
		Size = UDim2.fromScale(0.86, 0.8),
		Position = UDim2.fromScale(0.07, 0.1),
		Parent = pill,
	}, { Stroke = UiKit.Darken(C.Pink, 0.45), MaxText = 16 })
	btn.Activated:Connect(function()
		if mode == "Place" and placeId == furnId then
			setMode("Idle")
		else
			startPlace(furnId)
		end
	end)
	return { Button = btn, Stroke = stroke, Count = count }
end

function refreshTray()
	if not root then
		return
	end
	local anyTile = false
	for _, furnId in Config.FurnitureOrder do
		local n = invCount(furnId)
		local tile = tiles[furnId]
		if n > 0 then
			if not tile then
				tile = makeTile(furnId)
				tiles[furnId] = tile
			end
			local t = tile :: Tile
			t.Count.Text = "×" .. tostring(n)
			local selected = mode == "Place" and placeId == furnId
			t.Stroke.Color = if selected then C.Gold else C.Lavender
			t.Stroke.Thickness = if selected then 5 else 3
			anyTile = true
		elseif tile then
			tile.Button:Destroy()
			tiles[furnId] = nil
		end
	end
	emptyFrame.Visible = not anyTile
end

local function actionButton(name: string, text: string, color: Color3, order: number, fn: () -> ())
	local btn = UiKit.Button({
		Name = name,
		Text = text,
		Color = color,
		Size = UDim2.new(1, 0, 0, 50),
		LayoutOrder = order,
		Radius = UDim.new(0.3, 0),
		TextSize = 24,
		ZIndex = 6,
		Parent = column,
		OnClick = fn,
	})
	btn.Visible = false
	actionButtons[name] = btn
end

local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vs = cam.ViewportSize
	local s = math.clamp(math.min(vs.Y / 620, vs.X / 1000), 0.62, 1)
	for _, sc in scales do
		sc.Scale = s
	end
end

local function ensureUi()
	if root then
		return
	end
	local parent: Instance? = hostGui
	if not parent then
		local screen: ScreenGui = Make("ScreenGui", {
			Name = "PetWorldDecorate",
			ResetOnSpawn = false,
			IgnoreGuiInset = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = player:WaitForChild("PlayerGui"),
		})
		ownScreen = screen
		parent = screen
	end
	-- 창(ZIndex 20+) 보다 아래, HUD 보다 위
	local r: Frame = Make("Frame", {
		Name = "DecorateMode",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	})
	root = r

	-- 아래 판: 안내 / 층 버튼 + 끝내기 / 가구 가방 줄
	bottomPanel = Make("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(0.6, 0, 0, 196),
		BackgroundColor3 = C.Cream,
		BackgroundTransparency = 0.05,
		ZIndex = 5,
		Active = true,
		Parent = r,
	})
	Make("UISizeConstraint", { MinSize = Vector2.new(330, 196), MaxSize = Vector2.new(760, 196), Parent = bottomPanel })
	UiKit.Corner(bottomPanel, UDim.new(0, 22))
	UiKit.Stroke(bottomPanel, C.Lavender, 5, true)
	table.insert(scales, Make("UIScale", { Name = "FitScale", Parent = bottomPanel }))

	hintPill = Make("Frame", {
		Name = "Hint",
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(1, -20, 0, 36),
		BackgroundColor3 = C.Sky,
		ZIndex = 6,
		Parent = bottomPanel,
	})
	UiKit.Corner(hintPill, UDim.new(0.5, 0))
	UiKit.Gradient(hintPill)
	UiKit.Stroke(hintPill, C.White, 3, true)
	hintLabel = UiKit.Label({
		Text = "",
		Position = UDim2.new(0, 12, 0.12, 0),
		Size = UDim2.new(1, -92, 0.76, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = hintPill,
	}, { MaxText = 20 })
	countLabel = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0.14, 0),
		Size = UDim2.new(0, 74, 0.72, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 7,
		Parent = hintPill,
	}, { MaxText = 18 })

	local row: Frame = Make("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 50),
		Size = UDim2.new(1, -20, 0, 44),
		ZIndex = 6,
		Parent = bottomPanel,
	})
	floorDownButton = UiKit.Button({
		Name = "FloorDown",
		Text = "▼",
		Color = C.Sky,
		Size = UDim2.fromOffset(48, 44),
		Radius = UDim.new(0.35, 0),
		TextSize = 26,
		ZIndex = 6,
		Parent = row,
		OnClick = function()
			changeFloor(-1)
		end,
	})
	floorLabel = UiKit.Label({
		Text = "🏠 1층",
		Position = UDim2.fromOffset(52, 4),
		Size = UDim2.fromOffset(76, 36),
		ZIndex = 6,
		Parent = row,
	}, { MaxText = 22 })
	floorUpButton = UiKit.Button({
		Name = "FloorUp",
		Text = "▲",
		Color = C.Sky,
		Position = UDim2.fromOffset(132, 0),
		Size = UDim2.fromOffset(48, 44),
		Radius = UDim.new(0.35, 0),
		TextSize = 26,
		ZIndex = 6,
		Parent = row,
		OnClick = function()
			changeFloor(1)
		end,
	})
	UiKit.Button({
		Name = "Exit",
		Text = "🚪 끝내기",
		Color = C.Red,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(120, 44),
		Radius = UDim.new(0.35, 0),
		TextSize = 22,
		ZIndex = 6,
		Parent = row,
		OnClick = function()
			DecorateMode.Exit()
		end,
	})

	tray = UiKit.Scroller(bottomPanel, {
		Name = "Tray",
		Position = UDim2.new(0, 8, 0, 98),
		Size = UDim2.new(1, -16, 0, 94),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Lavender,
		ZIndex = 6,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = tray,
	})
	Make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = tray })

	emptyFrame = Make("Frame", {
		Name = "Empty",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 98),
		Size = UDim2.new(1, -16, 0, 94),
		Visible = false,
		ZIndex = 7,
		Parent = bottomPanel,
	})
	UiKit.Label({
		Text = "가구 가방이 비었어요!\n🛍 상점에서 사 오세요",
		Size = UDim2.new(0.62, 0, 0.8, 0),
		Position = UDim2.fromScale(0.02, 0.1),
		ZIndex = 7,
		Parent = emptyFrame,
	}, { MaxText = 20 })
	UiKit.Button({
		Name = "Shop",
		Text = "🛍 상점",
		Color = C.Pink,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.98, 0.5),
		Size = UDim2.new(0.32, 0, 0, 52),
		Radius = UDim.new(0.35, 0),
		TextSize = 22,
		ZIndex = 7,
		Parent = emptyFrame,
		OnClick = function()
			local opener = shopOpener
			DecorateMode.Exit()
			if opener then
				opener()
			end
		end,
	})

	-- 오른쪽 버튼 줄 (폰에서 누르기 쉽게 크게)
	column = Make("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.42, 0),
		Size = UDim2.fromOffset(124, 5 * 56),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = r,
	})
	table.insert(scales, Make("UIScale", { Name = "FitScale", Parent = column }))
	Make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = column,
	})
	actionButton("Place", "✅ 놓기", C.Mint, 1, confirm)
	actionButton("Rotate", "🔄 회전", C.Sky, 2, rotate)
	actionButton("Move", "✋ 옮기기", C.Peach, 3, startMove)
	actionButton("Pickup", "📦 치우기", C.Orange, 4, pickup)
	actionButton("Cancel", "✖ 취소", C.Lavender, 5, cancel)

	updateScale()
	local function watchCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
end

local function fireChanged()
	for _, fn in changedListeners do
		task.spawn(fn, active)
	end
end

----------------------------------------------------------------------
-- 동기화
----------------------------------------------------------------------
local function onSync()
	-- 서버 답이 왔으니 내 임시 기록은 버려요
	table.clear(pendingTaken)
	table.clear(pendingNew)
	table.clear(pendingOverride)
	syncVersion += 1
	if not active then
		return
	end
	if editFloor > floorsCount() then
		setEditFloor(floorsCount(), true)
	end
	if (mode == "Selected" or mode == "Move") and selFid and not placedMap()[selFid] then
		setMode("Idle")
	elseif mode == "Place" and placeId and invCount(placeId) <= 0 then
		setMode("Idle")
	end
	refreshTray()
	refreshFloorLabel()
	refreshGhost(true)
	updateHint()
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------
-- (선택) 메인 화면 GUI 를 주면 그 안에 만들어요. 안 부르면 따로 ScreenGui 를 만들어요
function DecorateMode.Init(gui: Instance?)
	if gui and not root then
		hostGui = gui
	end
	ensureUi()
end

function DecorateMode.IsActive(): boolean
	return active
end

-- 꾸미기 시작/끝날 때 알림 (HUD 등)
function DecorateMode.OnChanged(fn: (boolean) -> ())
	table.insert(changedListeners, fn)
end

-- 빈 가방에서 "🛍 상점" 을 누르면 부를 함수 (ShopWindow 가 넣어요)
function DecorateMode.SetShopOpener(fn: (() -> ())?)
	shopOpener = fn
end

function DecorateMode.OnSync()
	onSync()
end

-- floor = 꾸밀 층 (없으면 지금 있는 층), furnId = 바로 놓을 가구 (상점 "놓으러 가기")
function DecorateMode.Enter(floor: number?, furnId: string?)
	local snap = snapshot()
	if not snap then
		Toasts.Show("잠깐만요! 아직 불러오는 중이에요 ⏳", "info")
		return
	end
	local plot = State.Plot
	if not plot or not plotOrigin() then
		Toasts.Show("집이 있어야 꾸밀 수 있어요! 🏠", "warn")
		return
	end
	local _, hum = character()
	if not hum or hum.Health <= 0 then
		return
	end
	ensureUi()
	local curFloor, inside = characterWhere()
	local want = tonumber(floor)
	local target = math.clamp(math.floor(want or (if inside then curFloor else 1)), 1, floorsCount())

	if not active then
		active = true
		enteredPlot = plot
		outsideSince = nil
		lastCheck = 0
		lastMouse = nil
		local folder = Instance.new("Folder")
		folder.Name = "DecorateGhost"
		folder.Parent = workspace
		ghostFolder = folder
		-- 고른 가구 테두리 (하나만 써요, Adornee 만 바꿔요)
		local hl = Instance.new("Highlight")
		hl.Name = "DecorSelect"
		hl.FillColor = C.Gold
		hl.FillTransparency = 0.7
		hl.OutlineColor = C.Gold
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = folder
		selHl = hl
		table.insert(conns, RunService.RenderStepped:Connect(onRender))
		table.insert(conns, UserInputService.InputBegan:Connect(onInput))
		table.insert(conns, UserInputService.TouchTapInWorld:Connect(onTouchTap))
		table.insert(conns, hum.Died:Connect(function()
			DecorateMode.Exit()
		end))
		table.insert(conns, player.CharacterRemoving:Connect(function()
			DecorateMode.Exit()
		end))
		if root then
			(root :: Frame).Visible = true
		end
		if ownScreen then
			(ownScreen :: ScreenGui).Enabled = true
		end
		Toasts.Show("🪑 꾸미기 시작! 아래에서 가구를 골라요", "good")
		fireChanged()
	end

	editFloor = target
	if not inside or curFloor ~= target then
		requestTeleport(target)
	end
	setMode("Idle")
	refreshFloorLabel()
	if type(furnId) == "string" and Config.Furniture[furnId] then
		if invCount(furnId) > 0 then
			startPlace(furnId)
			if not inside or curFloor ~= target then
				-- 순간이동이 끝나면 캐릭터 앞에 다시
				gx, gz = nil, nil
				hideGhost()
				task.delay(0.8, function()
					if active and mode == "Place" and gx == nil then
						local x, z = defaultSpot()
						setGhostAt(x, z)
					end
				end)
			end
		else
			Toasts.Show(furnitureName(furnId) .. " 은(는) 가구 가방에 없어요!", "warn")
		end
	end
	refreshTray()
	updateHint()
end

function DecorateMode.Exit()
	if not active then
		return
	end
	setMode("Idle")
	active = false
	unfade()
	destroyGhost()
	clearSelection()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	if ghostFolder then
		ghostFolder:Destroy()
		ghostFolder = nil
	end
	selHl = nil
	queuedTeleport = nil
	enteredPlot = nil
	outsideSince = nil
	if root then
		(root :: Frame).Visible = false
	end
	if ownScreen then
		(ownScreen :: ScreenGui).Enabled = false
	end
	fireChanged()
end

-- 집이 바뀌거나 없어지면 끝내요
State.OnPlot(function(plot)
	if active and plot ~= enteredPlot then
		DecorateMode.Exit()
	end
end)
State.OnSync(function()
	onSync()
end)

return DecorateMode
