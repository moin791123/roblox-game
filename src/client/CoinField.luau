-- 내 들판 코인: 서버가 보내는 CoinField 이벤트대로 로컬 파트를 그리고, 가까이 가면 빨려 들어와요.
-- 코인은 지역마다 있어요 (payload.Zone). 가벼우려고 내가 있는 지역 코인 + 가까운(RenderDistance) 코인만 파트로 그려요.
-- 파트는 workspace.ClientCoins 아래에 (나한테만 보임). 먹기는 PickupCoin 으로 서버에 요청해요.
-- ★v5 자석 버튼 (State.OnSetting → 누르자마자, 스냅샷 Settings.Magnet, 또는 CoinField.SetMagnet): 기본 자석 밖 BigMagnetRadius 안 코인을
-- 가까운 것부터 초당 BigMagnetRate 개씩 빨아들여요 (서버도 같은 규칙으로 검사해요).
-- ★v6 ⚡ 슈퍼 자석 (State.OnSetting "SuperMagnet", 환생 SuperMagnetMinRebirth 번부터): 지금 서 있는 지역 코인만
-- SuperMagnetRadius 안에서 초당 SuperMagnetRate 개씩, 꼬리 달고 포물선으로 날아와요. 둘 다 켜면 슈퍼가 이겨요
-- (길 위처럼 지역 밖이면 🧲 자석만). 멀리서 날아오는 코인은 MAX_FAR_FLYING 개까지만 한꺼번에 그려요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Config = UiKit.Config
local FC = Config.FieldCoins
local player = Players.LocalPlayer

local CoinField = {}

local MAGNET_INTERVAL = 0.1
local CULL_INTERVAL = 0.3 -- 보이기/숨기기 다시 계산
local FLY_TIME = 0.25 -- 플레이어에게 날아가는 시간
local FAR_FLY_PER_STUD = 1 / 100 -- 큰 자석으로 멀리서 올 때 1 스터드마다 더 걸리는 시간
local FAR_MAX_HEIGHT = 10 -- 큰 자석은 높이 차이가 이보다 크면 안 끌어와요 (서버는 14)
local SUPER_FLY_PER_STUD = 1 / 80 -- ★v6 슈퍼 자석: 멀리서 줄지어 날아오는 게 보이게 조금 천천히
local SUPER_MAX_HEIGHT = 24 -- ★v6 슈퍼 자석 높이 차 허용치 (서버는 30)
local MAX_FAR_FLYING = 14 -- ★v6 멀리서 날아오는 코인 그림은 이만큼까지만 (성능)
local ARC_PER_STUD = 0.08 -- 멀리서 오면 포물선 높이 = 거리 × 이 값 (최대 ARC_MAX)
local ARC_MAX = 12
local MAGNET_HOLD = 2 -- SetMagnet 뒤 이 초 동안은 예전 스냅샷 값이 덮어쓰지 않아요
local CONFIRM_TIMEOUT = 3 -- 서버가 Remove 를 안 보내면 코인을 되살리는 시간
local SPIN_SPEED = 2.4
local BOB_HEIGHT = 0.25
local BOB_SPEED = 2.2
local SOUND_GAP = 0.08
local RENDER_DISTANCE = math.min(FC.RenderDistance or 150, 160)

type CoinKind = { Name: string, Value: number, Weight: number, Color: Color3, Size: number }
type Entry = {
	id: number,
	kind: CoinKind,
	zone: number,
	base: Vector3, -- 떠 있는 기준 위치 (코인 중심)
	phase: number,
	part: BasePart?,
	visible: boolean, -- 지금 그려야 하는지 (내 지역이거나 가까움)
	state: string, -- "Live" | "Pending" | "Gone"
	flyStart: number,
	flyTime: number,
	flyFrom: CFrame,
	flySize: Vector3,
	flyArc: number, -- 멀리서 올 때 포물선 높이 (0 = 바로)
	far: boolean, -- 큰 자석/슈퍼 자석으로 멀리서 날아오는 중
	goneAt: number,
	confirmed: boolean, -- 서버가 Remove 를 보냈는지
}

local entries: { [number]: Entry } = {}
local shown: { [number]: Entry } = {} -- 파트가 있는 코인만
local folder: Folder? = nil
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local lastSound = 0
local myZone = 1 -- 지금 있는 지역 (길 위에서는 마지막 지역)
local initialized = false
local magnetOn = Config.Settings.Magnet == true -- ★v5 자석 버튼
local magnetHoldUntil = 0
local magnetTokens = FC.BigMagnetBurst
local magnetAt = os.clock()
local superOn = Config.Settings.SuperMagnet == true -- ★v6 슈퍼 자석 버튼 (환생 조건은 따로)
local superHoldUntil = 0
local superTokens = FC.SuperMagnetBurst
local farList: { Entry } = {}
local farDist: { [Entry]: number } = {}

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = workspace:FindFirstChild("ClientCoins")
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = "ClientCoins"
		f.Parent = workspace
	end
	folder = f :: Folder
	return f :: Folder
end

local function kindByName(name: any): CoinKind?
	if type(name) ~= "string" then
		return nil
	end
	for _, k in FC.Kinds do
		if k.Name == name then
			return k
		end
	end
	return nil
end

local function getHRP(): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
		return hrp
	end
	return nil
end

-- 보는 기준 위치 (캐릭터가 없으면 카메라)
local function viewPosition(): Vector3?
	local hrp = getHRP()
	if hrp then
		return hrp.Position
	end
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position else nil
end

-- 따라오는 펫 수 + 타는 펫 (스냅샷 기준, 서버 FollowService.GetFollowerCount 와 같아야 해요)
local function followerCount(): number
	local n = 0
	for _, item in State.Items() do
		if item.Loc == "Follow" or item.Loc == "Ride" then
			n += 1
		end
	end
	return n
end

-- 코인 한 면에 안쪽 고리 그리기 (글자 없이 반짝이는 동전 느낌)
local function addRing(part: BasePart, face: Enum.NormalId, kind: CoinKind)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = Vector2.new(100, 100)
	gui.LightInfluence = 0
	gui.MaxDistance = 110
	gui.Parent = part

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.7, 0.7)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = kind.Color:Lerp(Color3.new(0, 0, 0), 0.35)
	stroke.Thickness = 4
	stroke.Transparency = 0.25
	stroke.Parent = ring

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromScale(0.3, 0.3)
	dot.BackgroundColor3 = kind.Color:Lerp(Color3.new(1, 1, 1), 0.45)
	dot.BackgroundTransparency = 0.2
	dot.BorderSizePixel = 0
	dot.Parent = ring

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(0.5, 0)
	dotCorner.Parent = dot
end

local function makePart(kind: CoinKind): BasePart
	local coin = Instance.new("Part")
	coin.Name = "Coin" .. kind.Name
	coin.Shape = Enum.PartType.Cylinder
	-- 원기둥 축 = X (옆으로 세운 동전)
	coin.Size = Vector3.new(math.max(0.3, kind.Size * 0.18), kind.Size, kind.Size)
	coin.Color = kind.Color
	coin.Material = if kind.Name == "Gold" then Enum.Material.Neon else Enum.Material.Metal
	coin.Reflectance = if kind.Name == "Gold" then 0 else 0.2
	coin.Anchored = true
	coin.CanCollide = false
	coin.CanQuery = false
	coin.CanTouch = false
	coin.CastShadow = false
	coin.TopSurface = Enum.SurfaceType.Smooth
	coin.BottomSurface = Enum.SurfaceType.Smooth
	addRing(coin, Enum.NormalId.Right, kind)
	addRing(coin, Enum.NormalId.Left, kind)
	return coin
end

local function destroyPart(entry: Entry)
	local part = entry.part
	entry.part = nil
	shown[entry.id] = nil
	if part then
		part:Destroy()
	end
end

local function ensurePart(entry: Entry)
	if entry.part then
		return
	end
	local part = makePart(entry.kind)
	part.CFrame = CFrame.new(entry.base) * CFrame.Angles(0, entry.phase, 0)
	part.Parent = getFolder()
	entry.part = part
	shown[entry.id] = entry
end

-- 보여야 하는지: 내 지역 코인이거나 가까운 코인
local function wantVisible(entry: Entry, view: Vector3?): boolean
	if entry.zone == myZone then
		return true
	end
	if not view then
		return false
	end
	local dx, dz = entry.base.X - view.X, entry.base.Z - view.Z
	return dx * dx + dz * dz <= RENDER_DISTANCE * RENDER_DISTANCE
end

-- 다시 살아 있는 코인으로 (보일 때만 파트를 만들어요)
local function setLive(entry: Entry)
	entry.state = "Live"
	entry.confirmed = false
	if entry.visible then
		ensurePart(entry)
	else
		destroyPart(entry)
	end
end

local function removeEntry(id: number)
	local entry = entries[id]
	if not entry then
		return
	end
	destroyPart(entry)
	entries[id] = nil
end

local function addCoin(raw: any)
	if type(raw) ~= "table" then
		return
	end
	local id = raw.Id
	local kind = kindByName(raw.Kind)
	local pos = raw.Position
	if type(id) ~= "number" or not kind or typeof(pos) ~= "Vector3" then
		return
	end
	local zone = if type(raw.Zone) == "number" then raw.Zone else (Config.ZoneAt(pos) or 1)
	removeEntry(id)
	-- 큰 코인은 바닥에 안 묻히게 조금 더 띄워요
	local lift = 1.2 + kind.Size * 0.35
	local entry: Entry = {
		id = id,
		kind = kind,
		zone = zone,
		base = pos + Vector3.new(0, lift, 0),
		phase = (id * 0.73) % (math.pi * 2),
		part = nil,
		visible = false,
		state = "Live",
		flyStart = 0,
		flyTime = FLY_TIME,
		flyFrom = CFrame.identity,
		flySize = Vector3.one,
		flyArc = 0,
		far = false,
		goneAt = 0,
		confirmed = false,
	}
	entry.visible = wantVisible(entry, viewPosition())
	entries[id] = entry
	setLive(entry)
end

local function resetCoins(list: any)
	for id in entries do
		removeEntry(id)
	end
	table.clear(entries)
	table.clear(shown)
	if type(list) ~= "table" then
		return
	end
	for _, raw in list do
		addCoin(raw)
	end
end

local function onRemove(id: any)
	if type(id) ~= "number" then
		return
	end
	local entry = entries[id]
	if not entry then
		return
	end
	if entry.state == "Pending" then
		-- 날아가는 중: 다 날아간 뒤에 지워요
		entry.confirmed = true
	else
		removeEntry(id)
	end
end

----------------------------------------------------------------------
-- 보이기/숨기기 (지역 + 거리)
----------------------------------------------------------------------

local function updateZone(view: Vector3?)
	if not view then
		return
	end
	local z = Config.ZoneAt(view)
	if z then
		myZone = z
	end
end

local function cullCheck()
	local view = viewPosition()
	updateZone(view)
	for _, entry in entries do
		local want = wantVisible(entry, view)
		entry.visible = want
		if entry.state == "Live" then
			if want then
				ensurePart(entry)
			elseif entry.part then
				destroyPart(entry)
			end
		end
	end
end

----------------------------------------------------------------------
-- 자석: 반경 안 코인을 빨아들여요
----------------------------------------------------------------------

-- 슈퍼 자석 코인 꼬리 (반짝이는 줄)
local function addTrail(part: BasePart, kind: CoinKind)
	local half = kind.Size * 0.35
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, half, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -half, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.3
	trail.MinLength = 0.2
	trail.FaceCamera = true
	trail.LightEmission = 0.3
	trail.Color = ColorSequence.new(kind.Color, Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.WidthScale = NumberSequence.new(1, 0.1)
	trail.Parent = part
end

-- flyTime 이 있으면 멀리서 (큰 자석/슈퍼 자석): 포물선으로, super 면 꼬리도
local function startFly(entry: Entry, flyTime: number?, super: boolean?)
	ensurePart(entry)
	local part = entry.part
	if not part then
		return
	end
	entry.state = "Pending"
	entry.confirmed = false
	entry.flyStart = os.clock()
	entry.flyTime = flyTime or FLY_TIME
	entry.flyFrom = part.CFrame
	entry.flySize = part.Size
	entry.far = flyTime ~= nil
	entry.flyArc = 0
	if flyTime then
		local hrp = getHRP()
		local dist = if hrp then (hrp.Position - part.Position).Magnitude else 0
		entry.flyArc = math.min(ARC_MAX, dist * ARC_PER_STUD)
		if super then
			addTrail(part, entry.kind)
		end
	end
	Remotes.PickupCoin:FireServer(entry.id)
	if os.clock() - lastSound > SOUND_GAP and type(UiKit.PlaySound) == "function" then
		lastSound = os.clock()
		UiKit.PlaySound("Coin")
	end
end

-- ★v6 슈퍼 자석이 정말 켜져 있나 (버튼 + 환생 조건, 서버도 똑같이 봐요)
local function superActive(): boolean
	return superOn and State.Rebirths() >= (FC.SuperMagnetMinRebirth or 1)
end

local function magnetCheck()
	local now = os.clock()
	local hrp = getHRP()
	local radius = FC.MagnetRadius + FC.MagnetPerFollower * followerCount()
	local r2 = radius * radius
	-- 표: 큰 자석 초당 BigMagnetRate 개, 슈퍼 자석 초당 SuperMagnetRate 개 (켜자마자는 Burst 개)
	local dt = now - magnetAt
	magnetAt = now
	magnetTokens = math.min(FC.BigMagnetBurst, magnetTokens + dt * FC.BigMagnetRate)
	superTokens = math.min(FC.SuperMagnetBurst, superTokens + dt * FC.SuperMagnetRate)
	-- 어떤 자석? 지역 안 + 슈퍼 → 슈퍼 (내 지역 코인만), 아니면 🧲 자석
	local here = if hrp then Config.ZoneAt(hrp.Position) else nil
	local super = here ~= nil and superActive()
	local pull = super or magnetOn
	local far = if super then FC.SuperMagnetRadius else FC.BigMagnetRadius
	local far2 = far * far
	local maxH = if super then SUPER_MAX_HEIGHT else FAR_MAX_HEIGHT
	local flying = 0
	table.clear(farList)
	for _, entry in entries do
		if entry.state == "Live" then
			if hrp then
				local d = entry.base - hrp.Position
				local d2 = d:Dot(d)
				local flat2 = d.X * d.X + d.Z * d.Z
				if d2 <= r2 then
					startFly(entry)
				elseif pull and flat2 <= far2 and math.abs(d.Y) <= maxH and (not super or entry.zone == here) then
					table.insert(farList, entry)
					farDist[entry] = flat2
				end
			end
		elseif entry.state == "Pending" then
			if entry.far then
				flying += 1
			end
		elseif entry.state == "Gone" and not entry.confirmed and now - entry.goneAt > CONFIRM_TIMEOUT then
			-- 서버가 안 받아줬어요 (너무 멀었거나 지연): 제자리에 다시 놓아요
			setLive(entry)
		end
	end
	if #farList > 0 then
		-- 가까운 코인부터
		table.sort(farList, function(a, b)
			return (farDist[a] or 0) < (farDist[b] or 0)
		end)
		local perStud = if super then SUPER_FLY_PER_STUD else FAR_FLY_PER_STUD
		for _, entry in farList do
			local tokens = if super then superTokens else magnetTokens
			if tokens < 1 or flying >= MAX_FAR_FLYING then
				break
			end
			if super then
				superTokens -= 1
			else
				magnetTokens -= 1
			end
			flying += 1
			startFly(entry, FLY_TIME + math.sqrt(farDist[entry] or 0) * perStud, super)
		end
		table.clear(farDist)
	end
end

-- 스냅샷의 버튼 값 (없으면 Config.Settings 기본값)
local function snapshotSetting(snap: any, key: string): boolean
	local settings = if type(snap) == "table" then snap.Settings else nil
	local v = if type(settings) == "table" then settings[key] else nil
	if type(v) ~= "boolean" then
		v = (Config.Settings :: any)[key] == true
	end
	return v == true
end

----------------------------------------------------------------------
-- 매 프레임: 빙글빙글 + 둥실둥실 + 날아가기 (파트가 있는 코인만)
----------------------------------------------------------------------

local function render()
	local t = os.clock()
	local hrp = getHRP()
	table.clear(moveParts)
	table.clear(moveCFrames)
	for _, entry in shown do
		local part = entry.part
		if not part then
			continue
		end
		if entry.state == "Live" then
			local bob = math.sin(t * BOB_SPEED + entry.phase) * BOB_HEIGHT
			table.insert(moveParts, part)
			table.insert(
				moveCFrames,
				CFrame.new(entry.base + Vector3.new(0, bob, 0)) * CFrame.Angles(0, t * SPIN_SPEED + entry.phase, 0)
			)
		elseif entry.state == "Pending" then
			local a = math.clamp((t - entry.flyStart) / entry.flyTime, 0, 1)
			if a >= 1 then
				-- 다 날아갔어요: 파트는 지우고, 서버 확인이 없으면 잠시 뒤 되살릴 수 있게 Gone 으로
				destroyPart(entry)
				if entry.confirmed then
					entries[entry.id] = nil
				else
					entry.state = "Gone"
					entry.goneAt = t
				end
				continue
			end
			local target = if hrp then hrp.Position else entry.flyFrom.Position + Vector3.new(0, 3, 0)
			local eased = a * a
			local pos = entry.flyFrom.Position:Lerp(target, eased)
			if entry.flyArc > 0 then
				pos += Vector3.new(0, math.sin(eased * math.pi) * entry.flyArc, 0)
			end
			part.Size = entry.flySize * (1 - eased * 0.8)
			table.insert(moveParts, part)
			table.insert(moveCFrames, CFrame.new(pos) * CFrame.Angles(0, t * SPIN_SPEED * 3 + entry.phase, 0))
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 지금 그리고 있는 코인 수 / 전체 코인 수 (디버그용)
function CoinField.Counts(): (number, number)
	local a, b = 0, 0
	for _ in shown do
		a += 1
	end
	for _ in entries do
		b += 1
	end
	return a, b
end

-- ★v5 자석 버튼: 버튼이 바로 불러도 되고 (서버 저장 전에 바로 반응), 안 불러도 스냅샷 Settings.Magnet 을 따라가요
function CoinField.SetMagnet(on: boolean)
	magnetOn = on == true -- (꺼져 있는 동안 표가 BigMagnetBurst 개까지 차 있어서 켜자마자 몇 개 쏙!)
	magnetHoldUntil = os.clock() + MAGNET_HOLD
end

function CoinField.IsMagnetOn(): boolean
	return magnetOn
end

-- ★v6 슈퍼 자석 버튼 (켜도 환생 SuperMagnetMinRebirth 번 전에는 안 끌어와요)
function CoinField.SetSuperMagnet(on: boolean)
	superOn = on == true
	superHoldUntil = os.clock() + MAGNET_HOLD
end

-- 버튼이 켜져 있나 / 정말 끌어오는 중인가 (환생 조건까지)
function CoinField.IsSuperMagnetOn(): boolean
	return superOn
end

function CoinField.IsSuperMagnetActive(): boolean
	return superActive()
end

-- 지금 멀리서 날아오는 코인 수 (검사용)
function CoinField.FlyingCount(): number
	local n = 0
	for _, entry in entries do
		if entry.state == "Pending" and entry.far then
			n += 1
		end
	end
	return n
end

function CoinField.Init()
	if initialized then
		return
	end
	initialized = true
	getFolder()

	State.OnSync(function()
		-- 방금 누른 값(서버 답 전)이 있으면 그 값, 아니면 스냅샷 값 (State.GetSetting)
		local now = os.clock()
		local v = State.GetSetting("Magnet")
		if v ~= magnetOn and now >= magnetHoldUntil then
			magnetOn = v
		end
		local sv = State.GetSetting("SuperMagnet")
		if sv ~= superOn and now >= superHoldUntil then
			superOn = sv
		end
	end)
	if State.Snapshot then
		magnetOn = snapshotSetting(State.Snapshot, "Magnet")
		superOn = snapshotSetting(State.Snapshot, "SuperMagnet")
	end
	-- 🧲 / ⚡ 버튼을 누르면 (State.SetSettingLocal) 서버 답을 기다리지 않고 바로 켜고 꺼요.
	-- Remotes.SetSetting 이 다음 PickupCoin 보다 먼저 가서 서버도 같은 자석으로 받아 줘요
	State.OnSetting(function(key: string, value: boolean)
		if key == "Magnet" then
			CoinField.SetMagnet(value)
		elseif key == "SuperMagnet" then
			CoinField.SetSuperMagnet(value)
		end
	end)

	Remotes.CoinField.OnClientEvent:Connect(function(op: any, arg: any)
		if op == "Reset" then
			resetCoins(arg)
		elseif op == "Add" then
			addCoin(arg)
		elseif op == "Remove" then
			onRemove(arg)
		end
	end)

	RunService.RenderStepped:Connect(render)

	task.spawn(function()
		local nextCull = 0
		while true do
			task.wait(MAGNET_INTERVAL)
			local now = os.clock()
			if now >= nextCull then
				nextCull = now + CULL_INTERVAL
				cullCheck()
			end
			magnetCheck()
		end
	end)
end

return CoinField
