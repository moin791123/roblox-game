-- 🏃 훔친 걸 들고 있을 때: 남은 시간 배너 + 내 기지까지 빛줄기
local Players = game:GetService("Players")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer

local CarryHud = {}

local banner: Frame
local label: TextLabel
local running = false
local beam: Beam? = nil
local fromAtt: Attachment? = nil
local toAtt: Attachment? = nil

local function clearBeam()
	if beam then
		beam:Destroy()
		beam = nil
	end
	if fromAtt then
		fromAtt:Destroy()
		fromAtt = nil
	end
	if toAtt then
		toAtt:Destroy()
		toAtt = nil
	end
end

local function ensureBeam(t: number)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local plot = State.Plot
	local spawnPoint = plot and plot:FindFirstChild("SpawnPoint", true)
	if not (hrp and hrp:IsA("BasePart") and spawnPoint and spawnPoint:IsA("BasePart")) then
		clearBeam()
		return
	end
	local a0 = fromAtt
	if not a0 or a0.Parent ~= hrp then
		if a0 then
			a0:Destroy()
		end
		a0 = Make("Attachment", { Name = "CarryBeamFrom", Parent = hrp })
		fromAtt = a0
	end
	local a1 = toAtt
	if not a1 then
		a1 = Make("Attachment", { Name = "CarryBeamTo", Parent = workspace.Terrain })
		toAtt = a1
		-- 목표 표시
		local bb: BillboardGui = Make("BillboardGui", {
			Size = UDim2.fromOffset(170, 60),
			StudsOffset = Vector3.new(0, 3, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			Adornee = a1,
			Parent = a1,
		})
		UiKit.Label({ Text = "🏠 내 기지!", Parent = bb }, { Stroke = UiKit.Darken(C.Orange, 0.4), StrokeThickness = 3, MaxText = 40 })
	end
	assert(a1)
	a1.WorldPosition = spawnPoint.Position + Vector3.new(0, 3, 0)
	local b = beam
	if not b then
		b = Make("Beam", {
			Name = "CarryBeam",
			Color = ColorSequence.new(Color3.fromRGB(255, 240, 90), Color3.fromRGB(255, 110, 200)),
			Transparency = NumberSequence.new(0.15),
			LightEmission = 0.7,
			LightInfluence = 0,
			FaceCamera = true,
			Segments = 24,
			Width0 = 1.2,
			Width1 = 1.2,
			Parent = workspace.Terrain,
		})
		beam = b
	end
	assert(b)
	b.Attachment0 = a0
	b.Attachment1 = a1
	local w = 1.1 + 0.35 * math.sin(t * 7)
	b.Width0 = w
	b.Width1 = w * 1.6
end

local function stop()
	running = false
	clearBeam()
	if banner.Visible then
		UiKit.Tween(UiKit.Scale(banner), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.21, function()
			if not running then
				banner.Visible = false
			end
		end)
	end
end

local function start()
	if running then
		return
	end
	running = true
	banner.Visible = true
	UiKit.Pop(banner, 0.4)
	UiKit.PlaySound("Steal")
	task.spawn(function()
		local lastSec = -1
		local t0 = os.clock()
		while running do
			local deadline = tonumber(player:GetAttribute("CarryDeadline")) or 0
			local left = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
			local name = player:GetAttribute("CarryItemName")
			label.Text = string.format("🏃 %s 들고 기지로! ⏱ %d초", if type(name) == "string" and name ~= "" then name else "보물", left)
			if left ~= lastSec then
				lastSec = left
				local hurry = left <= 10
				banner.BackgroundColor3 = if hurry then C.Red else C.Orange
				UiKit.Bump(banner, if hurry then 0.12 else 0.05)
			end
			ensureBeam(os.clock() - t0)
			task.wait(0.05)
		end
	end)
end

local function refresh()
	if player:GetAttribute("Carrying") == true then
		start()
	else
		stop()
	end
end

function CarryHud.Init(gui: Instance)
	banner = Make("Frame", {
		Name = "CarryBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromScale(0.5, 0.1),
		BackgroundColor3 = C.Orange,
		Visible = false,
		ZIndex = 15,
		Parent = gui,
	})
	Make("UISizeConstraint", { MinSize = Vector2.new(300, 52), MaxSize = Vector2.new(620, 80), Parent = banner })
	UiKit.Corner(banner, UDim.new(0.5, 0))
	UiKit.Gradient(banner)
	UiKit.Stroke(banner, C.White, 4, true)
	label = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.72),
		ZIndex = 16,
		Parent = banner,
	}, { Stroke = UiKit.Darken(C.Orange, 0.5), StrokeThickness = 3, MaxText = 36 })

	player:GetAttributeChangedSignal("Carrying"):Connect(refresh)
	refresh()
end

function CarryHud.IsCarrying(): boolean
	return running
end

return CarryHud
