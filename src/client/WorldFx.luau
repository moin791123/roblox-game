-- 월드 쪽 클라이언트 효과: 코인 빙글빙글, 프롬프트 숨기기, 내 레이저문 통과, +코인 숫자
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer
local myId = player.UserId

local WorldFx = {}

----------------------------------------------------------------------
-- 프롬프트 필터 (내 것만 보이게 / 내 것은 숨기게)
----------------------------------------------------------------------
local hiddenByMe: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastWrite: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- 로컬에서 Enabled 를 바꿀 때 (내가 쓴 값은 Enabled 신호에서 무시. 신호가 지연(deferred)돼도 안전)
local function setLocal(p: ProximityPrompt, value: boolean)
	lastWrite[p] = value
	p.Enabled = value
end

local function applyPrompt(p: ProximityPrompt)
	local kind = p:GetAttribute("PromptKind")
	if kind == nil then
		return
	end
	local owner = tonumber(p:GetAttribute("OwnerUserId"))
	local want: boolean? = nil
	if kind == "Steal" then
		want = owner ~= myId
	elseif kind == "Owner" or kind == "Reclaim" then
		want = owner == myId
	end
	if want == false then
		-- 서버가 켜 둔 것만 숨겨요 (꺼져 있던 걸 숨김 처리하면 나중에 잘못 켜져요)
		if p.Enabled then
			hiddenByMe[p] = true
			setLocal(p, false)
		end
	elseif want == true and hiddenByMe[p] then
		-- 내가 숨긴 것만 다시 켜요 (서버가 끈 건 그대로)
		hiddenByMe[p] = nil
		setLocal(p, true)
	end
end

local function hookPrompt(p: ProximityPrompt)
	p.AttributeChanged:Connect(function()
		applyPrompt(p)
	end)
	p:GetPropertyChangedSignal("Enabled"):Connect(function()
		local cur = p.Enabled
		if lastWrite[p] == cur then
			return
		end
		lastWrite[p] = nil
		if cur then
			-- 서버가 켰어요: 나한테 안 보여야 하면 다시 숨김
			applyPrompt(p)
		else
			-- 서버가 껐어요: 이제 내가 숨긴 상태가 아님
			hiddenByMe[p] = nil
		end
	end)
	applyPrompt(p)
end

local function setupPrompts()
	for _, d in workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			hookPrompt(d)
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			hookPrompt(d)
		end
	end)
end

----------------------------------------------------------------------
-- 내 기지 레이저문은 나만 통과
----------------------------------------------------------------------
local doorConns: { RBXScriptConnection } = {}

local function setupLaserDoor(plot: Model?)
	for _, c in doorConns do
		c:Disconnect()
	end
	table.clear(doorConns)
	if not plot then
		return
	end
	local function hook(door: Instance)
		if door.Name ~= "LaserDoor" then
			return
		end
		local parts: { BasePart } = {}
		if door:IsA("BasePart") then
			table.insert(parts, door)
		end
		for _, d in door:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		for _, part in parts do
			local function apply()
				if part.CanCollide then
					part.CanCollide = false
				end
			end
			apply()
			table.insert(doorConns, part:GetPropertyChangedSignal("CanCollide"):Connect(apply))
		end
	end
	for _, d in plot:GetDescendants() do
		hook(d)
	end
	table.insert(doorConns, plot.DescendantAdded:Connect(hook))
end

----------------------------------------------------------------------
-- 들판 코인 빙글빙글 (앵커된 파트, 로컬에서만 회전)
----------------------------------------------------------------------
local coinParts: { BasePart } = {}
local coinModels: { Model } = {}
local coinsDirty = true
local cfBuffer: { CFrame } = {}
local moved: { BasePart } = {}

local function setupCoins()
	task.spawn(function()
		local folder = workspace:FindFirstChild("FieldCoins")
		while not folder do
			task.wait(1)
			folder = workspace:FindFirstChild("FieldCoins")
		end
		local function rebuild()
			coinsDirty = false
			table.clear(coinParts)
			table.clear(coinModels)
			for _, child in folder:GetChildren() do
				if child:IsA("BasePart") then
					table.insert(coinParts, child)
				elseif child:IsA("Model") then
					table.insert(coinModels, child)
				end
			end
		end
		folder.ChildAdded:Connect(function()
			coinsDirty = true
		end)
		folder.ChildRemoved:Connect(function()
			coinsDirty = true
		end)
		rebuild()
		RunService.RenderStepped:Connect(function(dt)
			if coinsDirty then
				rebuild()
			end
			local rot = CFrame.Angles(0, math.min(dt, 0.1) * 2.4, 0)
			table.clear(cfBuffer)
			table.clear(moved)
			for _, part in coinParts do
				if part.Parent and part.Anchored then
					local cf = part.CFrame
					table.insert(moved, part)
					table.insert(cfBuffer, CFrame.new(cf.Position) * rot * cf.Rotation)
				end
			end
			if #moved > 0 then
				workspace:BulkMoveTo(moved, cfBuffer, Enum.BulkMoveMode.FireCFrameChanged)
			end
			for _, model in coinModels do
				if model.Parent then
					local cf = model:GetPivot()
					model:PivotTo(CFrame.new(cf.Position) * rot * cf.Rotation)
				end
			end
		end)
	end)
end

----------------------------------------------------------------------
-- +코인 떠오르는 숫자
----------------------------------------------------------------------
local lastCoinSound = 0

function WorldFx.CoinFx(amount: any, position: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	local n = tonumber(amount) or 0
	if n <= 0 then
		return
	end
	local att: Attachment = Make("Attachment", { Name = "CoinFx", Parent = workspace.Terrain })
	att.WorldPosition = position + Vector3.new(0, 2.5, 0)
	local bb: BillboardGui = Make("BillboardGui", {
		Size = UDim2.fromOffset(150, 52),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 150,
		Adornee = att,
		Parent = att,
	})
	local label = UiKit.Label({
		Text = "+" .. Config.FormatNumber(n) .. " 💰",
		TextColor3 = C.Lemon,
		Parent = bb,
	}, { Stroke = Color3.fromRGB(150, 85, 20), StrokeThickness = 3, MaxText = 40 })
	UiKit.Pop(label, 0.25)
	UiKit.Tween(att, 1.1, { Position = att.Position + Vector3.new(0, 4.5, 0) }, Enum.EasingStyle.Quad)
	task.delay(0.5, function()
		UiKit.Tween(label, 0.6, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			UiKit.Tween(stroke, 0.6, { Transparency = 1 })
		end
	end)
	Debris:AddItem(att, 1.3)

	if os.clock() - lastCoinSound > 0.09 then
		lastCoinSound = os.clock()
		UiKit.PlaySound("Coin")
	end
end

function WorldFx.Init()
	setupPrompts()
	setupCoins()
	State.OnPlot(setupLaserDoor)
	setupLaserDoor(State.Plot)
end

return WorldFx
