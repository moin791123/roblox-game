-- 월드 쪽 클라이언트 효과: 내 것 아닌 프롬프트 숨기기, +코인 숫자
-- (들판 코인 그리기는 CoinField 모듈이 해요)
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local UiKit = require(script.Parent.UiKit)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer
local myId = player.UserId

local WorldFx = {}

----------------------------------------------------------------------
-- 프롬프트 필터: PromptKind "Owner" 는 주인한테만 보여요
----------------------------------------------------------------------
local hiddenByMe: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastWrite: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- 로컬에서 Enabled 를 바꿀 때 (내가 쓴 값은 Enabled 신호에서 무시. 신호가 지연(deferred)돼도 안전)
local function setLocal(p: ProximityPrompt, value: boolean)
	lastWrite[p] = value
	p.Enabled = value
end

local function applyPrompt(p: ProximityPrompt)
	if p:GetAttribute("PromptKind") ~= "Owner" then
		return
	end
	local owner = tonumber(p:GetAttribute("OwnerUserId"))
	local want = owner == myId
	if not want then
		-- 서버가 켜 둔 것만 숨겨요 (꺼져 있던 걸 숨김 처리하면 나중에 잘못 켜져요)
		if p.Enabled then
			hiddenByMe[p] = true
			setLocal(p, false)
		end
	elseif hiddenByMe[p] then
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
end

return WorldFx
