-- 들판 코인: 컨베이어 양옆 들판에 코인을 깔아 두고, 가까이 오면 (자석 반경) 자동으로 주워요.
-- 수집 판정은 서버에서 0.1초마다. 코인 회전은 클라이언트가 해요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local FollowService = require(script.Parent.FollowService)

local CoinFieldService = {}

local FC = Config.FieldCoins
local Layout = Config.Layout
local HALF_PLOT = Layout.PlotSize / 2

local COIN_Y = 2 -- 코인 중심 높이
local CHECK_INTERVAL = 0.1
local MIN_SPACING = 4 -- 코인끼리 최소 간격
local MAX_HEIGHT_DIFF = 10

type CoinKind = { Name: string, Value: number, Weight: number, Color: Color3, Size: number }

local rng = Random.new()
local folder: Folder? = nil
local active: { BasePart } = {}
local started = false

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = workspace:FindFirstChild("FieldCoins")
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = "FieldCoins"
		f.Parent = workspace
	end
	folder = f :: Folder
	return f :: Folder
end

local function pickKind(): CoinKind
	local total = 0
	for _, k in FC.Kinds do
		total += k.Weight
	end
	local roll = rng:NextNumber() * total
	for _, k in FC.Kinds do
		roll -= k.Weight
		if roll <= 0 then
			return k
		end
	end
	return FC.Kinds[1]
end

local function insidePlot(pos: Vector3, margin: number): boolean
	for _, cf in Layout.Plots do
		local lp = cf:PointToObjectSpace(Vector3.new(pos.X, cf.Position.Y, pos.Z))
		if math.abs(lp.X) <= HALF_PLOT + margin and math.abs(lp.Z) <= HALF_PLOT + margin then
			return true
		end
	end
	return false
end

local function tooClose(pos: Vector3): boolean
	for _, c in active do
		local d = c.Position - pos
		if d.X * d.X + d.Z * d.Z < MIN_SPACING * MIN_SPACING then
			return true
		end
	end
	return false
end

-- 컨베이어 여유 구역 밖의 z 값 하나 고르기
local function randomZ(): number
	local clear = Layout.FieldConveyorClearance
	local zMin, zMax = Layout.FieldMin.Z, Layout.FieldMax.Z
	-- 구간 [zMin, -clear] 와 [clear, zMax]
	local lowLen = math.max(0, math.min(zMax, -clear) - zMin)
	local highLen = math.max(0, zMax - math.max(zMin, clear))
	if lowLen + highLen <= 0 then
		return rng:NextNumber(zMin, zMax)
	end
	local r = rng:NextNumber(0, lowLen + highLen)
	if r < lowLen then
		return zMin + r
	end
	return math.max(zMin, clear) + (r - lowLen)
end

local function randomPosition(): Vector3
	local fallback: Vector3? = nil
	for _ = 1, 30 do
		local pos = Vector3.new(rng:NextNumber(Layout.FieldMin.X, Layout.FieldMax.X), COIN_Y, randomZ())
		if not insidePlot(pos, 2) then
			if not tooClose(pos) then
				return pos
			end
			fallback = fallback or pos
		end
	end
	return fallback or Vector3.new(0, COIN_Y, Layout.FieldConveyorClearance + 2)
end

local function makeCoin(kind: CoinKind, pos: Vector3): Part
	local coin = Instance.new("Part")
	coin.Name = "Coin" .. kind.Name
	coin.Shape = Enum.PartType.Cylinder
	-- 원기둥 축 = X (옆으로 선 동전)
	coin.Size = Vector3.new(math.max(0.3, kind.Size * 0.18), kind.Size, kind.Size)
	coin.CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	coin.Color = kind.Color
	coin.Material = if kind.Name == "Gold" then Enum.Material.Neon else Enum.Material.Metal
	coin.Reflectance = if kind.Name == "Gold" then 0 else 0.15
	coin.Anchored = true
	coin.CanCollide = false
	coin.CanQuery = false
	coin.CanTouch = false
	coin.CastShadow = false
	coin.TopSurface = Enum.SurfaceType.Smooth
	coin.BottomSurface = Enum.SurfaceType.Smooth
	coin:SetAttribute("Value", kind.Value)
	coin:SetAttribute("Kind", kind.Name)

	-- 양면에 작은 안쪽 원 + 별
	local inner = kind.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	local dark = kind.Color:Lerp(Color3.new(0, 0, 0), 0.3)
	for _, face in { Enum.NormalId.Right, Enum.NormalId.Left } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(100, 100)
		gui.LightInfluence = 0
		gui.MaxDistance = 120
		gui.Parent = coin

		local disc = Instance.new("Frame")
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromScale(0.68, 0.68)
		disc.BackgroundColor3 = inner
		disc.BorderSizePixel = 0
		disc.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc

		local stroke = Instance.new("UIStroke")
		stroke.Color = dark
		stroke.Thickness = 3
		stroke.Transparency = 0.3
		stroke.Parent = disc

		local star = Instance.new("TextLabel")
		star.BackgroundTransparency = 1
		star.Size = UDim2.fromScale(1, 1)
		star.Font = Enum.Font.FredokaOne
		star.Text = "★"
		star.TextScaled = true
		star.TextColor3 = dark
		star.Parent = disc
	end
	return coin
end

local function spawnCoin()
	local coin = makeCoin(pickKind(), randomPosition())
	coin.Parent = getFolder()
	table.insert(active, coin)
end

local function collect(player: Player, coin: BasePart, boost: number)
	local value = coin:GetAttribute("Value")
	local pos = coin.Position
	coin:Destroy()
	task.delay(FC.RespawnTime, spawnCoin)

	if type(value) ~= "number" then
		return
	end
	local amount = math.floor(value * (1 + boost))
	if amount <= 0 then
		return
	end
	DataService.AddCoins(player, amount)
	Remotes.CoinFx:FireClient(player, amount, pos)
	DataService.Sync(player)
end

local function check()
	if #active == 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 and DataService.Get(player) then
			local radius = FC.MagnetRadius + FC.MagnetPerFollower * FollowService.GetFollowerCount(player)
			local r2 = radius * radius
			local p = hrp.Position
			local boost: number? = nil
			local i = 1
			while i <= #active do
				local coin = active[i]
				local cp = coin.Position
				local dx, dz = cp.X - p.X, cp.Z - p.Z
				if dx * dx + dz * dz <= r2 and math.abs(cp.Y - p.Y) <= MAX_HEIGHT_DIFF then
					-- 순서 상관없으니 마지막 것과 바꿔서 제거
					active[i] = active[#active]
					active[#active] = nil
					if boost == nil then
						boost = FollowService.GetBoost(player)
					end
					collect(player, coin, boost :: number)
				else
					i += 1
				end
			end
		end
	end
end

function CoinFieldService.Start()
	if started then
		return
	end
	started = true
	getFolder()
	for _ = 1, FC.Count do
		spawnCoin()
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < CHECK_INTERVAL then
			return
		end
		acc = 0
		check()
	end)
end

return CoinFieldService
