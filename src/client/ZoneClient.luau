-- 지역 클라이언트: 환생이 모자란 지역 문은 나한테만 막혀요 (분홍 보호막, 스냅샷마다 다시 확인).
-- 지역에 들어가면 "🦆 호수에 왔어요!" 배너, 새 지역이 열리면 축하 배너, 지역마다 하늘 색을 살짝 바꿔요 (우주 = 밤).
-- 컨베이어 줄무늬도 여기서 움직여요 (서버는 줄무늬를 안 움직여요).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer

local ZoneClient = {}

local ZONE_CHECK = 0.25
local BANNER_TIME = 2.6
local STRIPE_DISTANCE = 240 -- 이 안의 컨베이어만 줄무늬를 움직여요
local LOCKED_COLOR = Color3.fromRGB(255, 120, 200)
local NIGHT_CLOCK = 22 -- 우주는 밤

type StripeBelt = {
	Folder: Instance,
	Parts: { BasePart },
	Base: CFrame,
	Length: number,
	Speed: number,
	Spacing: number,
	Y: number,
	Center: Vector3,
}

local gates: { [number]: BasePart } = {}
local stripeBelts: { StripeBelt } = {}
local currentZone: number? = nil
local initialized = false

local bannerFrame: Frame? = nil
local bannerTitle: TextLabel? = nil
local bannerSub: TextLabel? = nil
local bannerToken = 0

-- 조명 원래 값 (처음 바꿀 때 기억)
local baseLight: { ClockTime: number, Tint: Color3, Ambient: Color3 }? = nil

----------------------------------------------------------------------
-- 환생 수 / 열린 지역 (스냅샷 기준)
----------------------------------------------------------------------

local function rebirths(): number
	local snap: any = State.Snapshot
	return if snap then math.max(0, math.floor(tonumber(snap.Rebirths) or 0)) else 0
end

local function maxZoneOf(snap: any): number
	if not snap then
		return 1
	end
	local z = tonumber(snap.MaxZone)
	if z then
		return math.clamp(math.floor(z), 1, Config.MaxZone)
	end
	return Config.MaxZoneFor(tonumber(snap.Rebirths) or 0)
end

----------------------------------------------------------------------
-- 문 (나한테만 막기)
----------------------------------------------------------------------

local function applyGate(gate: BasePart)
	local minRebirth = tonumber(gate:GetAttribute("MinRebirth")) or 0
	local locked = rebirths() < minRebirth
	gate.CanCollide = locked
	gate.Transparency = if locked then 0.35 else 1
	gate.Material = Enum.Material.ForceField
	gate.Color = LOCKED_COLOR
	local info = gate:FindFirstChild("LockInfo")
	if info and info:IsA("BillboardGui") then
		info.Enabled = locked
	end
end

local function applyGates()
	for _, gate in gates do
		if gate.Parent then
			applyGate(gate)
		end
	end
end

local function addGate(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local k = tonumber(inst:GetAttribute("ZoneIndex")) or tonumber(string.match(inst.Name, "^Gate(%d+)$"))
	if not k then
		return
	end
	gates[k] = inst
	applyGate(inst)
end

local function watchGates()
	local world = workspace:WaitForChild("World", 60)
	local folder = world and world:WaitForChild("Gates", 60)
	if not folder then
		warn("[ZoneClient] workspace.World.Gates 를 찾지 못했어요")
		return
	end
	for _, g in folder:GetChildren() do
		addGate(g)
	end
	folder.ChildAdded:Connect(addGate)
end

----------------------------------------------------------------------
-- 배너
----------------------------------------------------------------------

local function ensureBanner(gui: Instance?)
	if bannerFrame then
		return
	end
	local parent: Instance? = gui
	if not parent then
		parent = Make("ScreenGui", {
			Name = "PetWorldZoneBanner",
			ResetOnSpawn = false,
			DisplayOrder = 25,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = player:WaitForChild("PlayerGui"),
		})
	end
	local frame: Frame = Make("Frame", {
		Name = "ZoneBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromScale(0.5, 0.11),
		BackgroundColor3 = C.Cream,
		Visible = false,
		ZIndex = 35,
		Parent = parent,
	})
	Make("UISizeConstraint", { MinSize = Vector2.new(260, 64), MaxSize = Vector2.new(560, 110), Parent = frame })
	UiKit.Corner(frame, UDim.new(0.35, 0))
	local stroke = UiKit.Stroke(frame, C.Pink, 5, true)
	stroke.Name = "BannerStroke"
	bannerTitle = UiKit.Label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.92, 0.56),
		ZIndex = 36,
		Parent = frame,
	}, { MaxText = 40, StrokeThickness = 3 })
	bannerSub = UiKit.Label({
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromScale(0.9, 0.3),
		TextColor3 = C.Ink,
		ZIndex = 36,
		Parent = frame,
	}, { Stroke = C.White, MaxText = 22 })
	bannerFrame = frame
end

local function showBanner(title: string, sub: string, color: Color3, sound: string?)
	ensureBanner(nil)
	local frame, titleLabel, subLabel = bannerFrame, bannerTitle, bannerSub
	if not frame or not titleLabel or not subLabel then
		return
	end
	bannerToken += 1
	local my = bannerToken
	titleLabel.Text = title
	subLabel.Text = sub
	subLabel.Visible = sub ~= ""
	local stroke = frame:FindFirstChild("BannerStroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = color
	end
	local titleStroke = titleLabel:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = UiKit.Darken(color, 0.35)
	end
	frame.Visible = true
	UiKit.Pop(frame, 0.4)
	if sound then
		UiKit.PlaySound(sound)
	end
	task.delay(BANNER_TIME, function()
		if bannerToken ~= my then
			return
		end
		local s = UiKit.Scale(frame)
		UiKit.Tween(s, 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.22, function()
			if bannerToken == my then
				frame.Visible = false
			end
		end)
	end)
end

----------------------------------------------------------------------
-- 지역 들어감 + 하늘 색
----------------------------------------------------------------------

local function applyLighting(zone: number)
	local def = Config.Zones[zone]
	if not def then
		return
	end
	local cc = Lighting:FindFirstChild("PastelColor")
	if not baseLight then
		baseLight = {
			ClockTime = Lighting.ClockTime,
			Tint = if cc and cc:IsA("ColorCorrectionEffect") then cc.TintColor else Color3.new(1, 1, 1),
			Ambient = Lighting.OutdoorAmbient,
		}
	end
	local base = baseLight :: { ClockTime: number, Tint: Color3, Ambient: Color3 }
	local isSpace = def.Id == "Space"
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, info, {
		ClockTime = if isSpace then NIGHT_CLOCK else base.ClockTime,
		OutdoorAmbient = if isSpace then Color3.fromRGB(150, 140, 200) else base.Ambient,
	}):Play()
	if cc and cc:IsA("ColorCorrectionEffect") then
		local sky: Color3 = def.Palette.Sky or Color3.new(1, 1, 1)
		local tint = if zone == 1 then base.Tint else base.Tint:Lerp(sky:Lerp(Color3.new(1, 1, 1), 0.55), 0.6)
		TweenService:Create(cc, info, { TintColor = tint }):Play()
	end
end

local function onZoneChanged(zone: number, first: boolean)
	applyLighting(zone)
	if first then
		return
	end
	local def = Config.Zones[zone]
	if def then
		showBanner(def.Emoji .. " " .. def.Name .. "에 왔어요!", "💰 코인 ×" .. tostring(def.CoinMult), def.Palette.Accent or C.Pink, nil)
	end
end

local function zoneCheck()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	local z = Config.ZoneAt(hrp.Position)
	if z and z ~= currentZone then
		local first = currentZone == nil
		currentZone = z
		onZoneChanged(z, first)
	end
end

----------------------------------------------------------------------
-- 컨베이어 줄무늬 (가까운 벨트만)
----------------------------------------------------------------------

local function addBelt(beltFolder: Instance)
	local start = beltFolder:GetAttribute("Start")
	local dir = beltFolder:GetAttribute("Dir")
	local length = tonumber(beltFolder:GetAttribute("Length"))
	local speed = tonumber(beltFolder:GetAttribute("Speed"))
	if typeof(start) ~= "Vector3" or typeof(dir) ~= "Vector3" or not length or not speed or length <= 0 then
		return
	end
	local parts: { BasePart } = {}
	for _, c in beltFolder:GetChildren() do
		if c:IsA("BasePart") and c.Name == "Stripe" then
			table.insert(parts, c)
		end
	end
	if #parts == 0 then
		return
	end
	table.sort(parts, function(a, b)
		return (tonumber(a:GetAttribute("StripeIndex")) or 0) < (tonumber(b:GetAttribute("StripeIndex")) or 0)
	end)
	table.insert(stripeBelts, {
		Folder = beltFolder,
		Parts = parts,
		Base = CFrame.lookAt(start, start + dir),
		Length = length,
		Speed = speed,
		Spacing = tonumber(beltFolder:GetAttribute("StripeSpacing")) or 8,
		Y = tonumber(beltFolder:GetAttribute("StripeY")) or 1.22,
		Center = start + dir * (length / 2),
	})
end

local function watchConveyors()
	local root = workspace:WaitForChild("Conveyors", 60)
	if not root then
		return
	end
	local function onZoneFolder(zf: Instance)
		task.spawn(function()
			local belt = zf:WaitForChild("Belt", 30)
			if belt then
				task.wait(0.5) -- 줄무늬가 다 복제될 때까지 잠깐
				addBelt(belt)
			end
		end)
	end
	for _, zf in root:GetChildren() do
		onZoneFolder(zf)
	end
	root.ChildAdded:Connect(onZoneFolder)
end

local stripeCFs: { CFrame } = {}
local function animateStripes()
	if #stripeBelts == 0 then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local view = cam.CFrame.Position
	local now = workspace:GetServerTimeNow()
	for _, belt in stripeBelts do
		local d = belt.Center - view
		if belt.Folder.Parent and d.X * d.X + d.Z * d.Z <= STRIPE_DISTANCE * STRIPE_DISTANCE then
			local n = #belt.Parts
			local span = n * belt.Spacing
			local offset = (now * belt.Speed * span / belt.Length) % span
			table.clear(stripeCFs)
			for i = 1, n do
				local s = ((i - 1) * belt.Spacing + offset) % span
				stripeCFs[i] = belt.Base * CFrame.new(0, belt.Y, -s * (belt.Length / span))
			end
			workspace:BulkMoveTo(belt.Parts, stripeCFs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 내가 지금 있는 지역 (길 위에서는 마지막 지역)
function ZoneClient.CurrentZone(): number
	return currentZone or tonumber(player:GetAttribute("Zone")) or 1
end

-- 스냅샷이 바뀌면 문을 다시 확인해요 (Init 이 State.OnSync 에도 연결해 둬요)
function ZoneClient.OnSync()
	applyGates()
end

function ZoneClient.Init(gui: Instance?)
	if initialized then
		return
	end
	initialized = true
	ensureBanner(gui)

	task.spawn(watchGates)
	task.spawn(watchConveyors)

	State.OnSync(function(snap: any, prev: any)
		applyGates()
		-- 환생으로 새 지역이 열렸어요
		if prev then
			local before, after = maxZoneOf(prev), maxZoneOf(snap)
			if after > before then
				local def = Config.Zones[after]
				if def then
					showBanner("🎉 " .. def.Emoji .. " " .. def.Name .. " 문이 열렸어요!", "🗺 지도(M)로 가 봐요!", C.Gold, "Hatch")
				end
			end
		end
	end)
	applyGates()

	RunService.RenderStepped:Connect(animateStripes)

	task.spawn(function()
		while true do
			task.wait(ZONE_CHECK)
			local ok, err = pcall(zoneCheck)
			if not ok then
				warn("[ZoneClient] 지역 확인 오류:", err)
			end
		end
	end)
end

return ZoneClient
