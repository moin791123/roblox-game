-- 내 들판 코인: 서버가 보내는 CoinField 이벤트대로 로컬 파트를 그리고, 가까이 가면 빨려 들어와요.
-- 파트는 workspace.ClientCoins 아래에 (나한테만 보임). 먹기는 PickupCoin 으로 서버에 요청해요.
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
local FLY_TIME = 0.25 -- 플레이어에게 날아가는 시간
local CONFIRM_TIMEOUT = 3 -- 서버가 Remove 를 안 보내면 코인을 되살리는 시간
local SPIN_SPEED = 2.4
local BOB_HEIGHT = 0.25
local BOB_SPEED = 2.2
local SOUND_GAP = 0.08

type CoinKind = { Name: string, Value: number, Weight: number, Color: Color3, Size: number }
type Entry = {
	id: number,
	kind: CoinKind,
	base: Vector3, -- 떠 있는 기준 위치 (코인 중심)
	phase: number,
	part: BasePart?,
	state: string, -- "Live" | "Pending" | "Gone"
	flyStart: number,
	flyFrom: CFrame,
	flySize: Vector3,
	goneAt: number,
	confirmed: boolean, -- 서버가 Remove 를 보냈는지
}

local entries: { [number]: Entry } = {}
local folder: Folder? = nil
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local lastSound = 0
local initialized = false

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
	if part then
		part:Destroy()
	end
end

local function spawnPart(entry: Entry)
	destroyPart(entry)
	local part = makePart(entry.kind)
	part.CFrame = CFrame.new(entry.base) * CFrame.Angles(0, entry.phase, 0)
	part.Parent = getFolder()
	entry.part = part
	entry.state = "Live"
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
	removeEntry(id)
	-- 큰 코인은 바닥에 안 묻히게 조금 더 띄워요
	local lift = 1.2 + kind.Size * 0.35
	local entry: Entry = {
		id = id,
		kind = kind,
		base = pos + Vector3.new(0, lift, 0),
		phase = (id * 0.73) % (math.pi * 2),
		part = nil,
		state = "Live",
		flyStart = 0,
		flyFrom = CFrame.identity,
		flySize = Vector3.one,
		goneAt = 0,
		confirmed = false,
	}
	entries[id] = entry
	spawnPart(entry)
end

local function resetCoins(list: any)
	for id in entries do
		removeEntry(id)
	end
	table.clear(entries)
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
-- 자석: 반경 안 코인을 빨아들여요
----------------------------------------------------------------------

local function startFly(entry: Entry)
	local part = entry.part
	if not part then
		return
	end
	entry.state = "Pending"
	entry.confirmed = false
	entry.flyStart = os.clock()
	entry.flyFrom = part.CFrame
	entry.flySize = part.Size
	Remotes.PickupCoin:FireServer(entry.id)
	if os.clock() - lastSound > SOUND_GAP and type(UiKit.PlaySound) == "function" then
		lastSound = os.clock()
		UiKit.PlaySound("Coin")
	end
end

local function magnetCheck()
	local now = os.clock()
	local hrp = getHRP()
	local radius = FC.MagnetRadius + FC.MagnetPerFollower * followerCount()
	local r2 = radius * radius
	for _, entry in entries do
		if entry.state == "Live" and hrp then
			local d = entry.base - hrp.Position
			if d:Dot(d) <= r2 then
				startFly(entry)
			end
		elseif entry.state == "Gone" and not entry.confirmed and now - entry.goneAt > CONFIRM_TIMEOUT then
			-- 서버가 안 받아줬어요 (너무 멀었거나 지연): 제자리에 다시 놓아요
			spawnPart(entry)
		end
	end
end

----------------------------------------------------------------------
-- 매 프레임: 빙글빙글 + 둥실둥실 + 날아가기
----------------------------------------------------------------------

local function render()
	local t = os.clock()
	local hrp = getHRP()
	table.clear(moveParts)
	table.clear(moveCFrames)
	for _, entry in entries do
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
			local a = math.clamp((t - entry.flyStart) / FLY_TIME, 0, 1)
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

function CoinField.Init()
	if initialized then
		return
	end
	initialized = true
	getFolder()

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
		while true do
			task.wait(MAGNET_INTERVAL)
			magnetCheck()
		end
	end)
end

return CoinField
