-- 알림 말풍선 (코인 아래 가운데에 쌓여요, 최대 4개)
-- + 큰 배너 하나 (Toasts.Banner): "✨ 정글에 점박이 알이 나타났어요!" 처럼 그림 + 버튼이 있는 알림.
--   같은 Key 가 또 오면 합치고 (×2), 다른 건 줄을 서서 차례로 보여요. 보이는 동안 말풍선은 배너 아래로 내려가요.
local UiKit = require(script.Parent.UiKit)

local Make, C = UiKit.Make, UiKit.Colors

local Toasts = {}

local KIND_COLORS: { [string]: Color3 } = {
	info = C.Sky,
	good = C.Mint,
	warn = C.Orange,
	alert = C.Red,
}

local MAX = 4
local TOP = 124 -- 코인 줄 + 초당 수익 줄 아래
local container: Frame? = nil
local live: { Frame } = {}
local counter = 0

----------------------------------------------------------------------
-- 배너 상태
----------------------------------------------------------------------
export type BannerSpec = {
	Key: string?, -- 같은 Key 가 또 오면 하나로 합쳐요 (×2, 시간 연장)
	Title: string,
	Sub: string?,
	Color: Color3?, -- 테두리·강조색
	IconKind: string?, -- "Egg" | "Pet" → UiKit.Viewport
	IconId: string?,
	IconText: string?, -- 뷰포트 대신 이모지
	Sound: string?, -- Config.Sounds 키 (기본 "Alert")
	Duration: number?, -- 기본 6초
	ButtonText: string?, -- 없으면 버튼 없음
	ButtonColor: Color3?,
	OnButton: (() -> boolean?)?, -- true 를 돌려주면 배너를 닫아요
	ButtonVisible: (() -> boolean)?, -- false 면 버튼을 숨기고 HiddenSub 를 보여 줘요 (0.25초마다 확인)
	HiddenSub: string?,
}

type BannerEntry = { Spec: BannerSpec, Count: number, Shown: number, Until: number, Closed: boolean }

local BANNER_TIME = 6
local BANNER_MIN = 3 -- 기다리는 배너가 있으면 이만큼만 보여 주고 다음으로
local BANNER_QUEUE_MAX = 3

local rootGui: Instance? = nil
local guard: GuiObject? = nil -- 배너가 가리면 안 되는 것 (왼쪽 큰 버튼들)
local bannerOuter: Frame? = nil
local bannerBubble: Frame
local bannerStroke: UIStroke
local bannerIcon: Frame
local bannerCount: Frame
local bannerCountLabel: TextLabel
local bannerTitle: TextLabel
local bannerSub: TextLabel
local bannerButton: TextButton
local bannerButtonLabel: TextLabel
local bannerHeight = 100
local bannerWidth = 560
local bannerQueue: { BannerEntry } = {}
local bannerCurrent: BannerEntry? = nil
local bannerRunning = false
local bannerSuppressed = false
local bannerToken = 0

local function toastTop(): number
	local outer = bannerOuter
	if outer and outer.Visible then
		return TOP + bannerHeight + 8
	end
	return TOP
end

local function moveToasts()
	local frame = container
	if frame then
		UiKit.Tween(frame, 0.2, { Position = UDim2.new(0.5, 0, 0, toastTop()) })
	end
end

function Toasts.Init(gui: Instance)
	rootGui = gui
	local frame: Frame = Make("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP),
		Size = UDim2.new(0.5, 0, 0, 260),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = gui,
	})
	Make("UISizeConstraint", { MinSize = Vector2.new(290, 0), MaxSize = Vector2.new(560, 400), Parent = frame })
	Make("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	container = frame
end

local function remove(outer: Frame)
	local idx = table.find(live, outer)
	if not idx then
		return
	end
	table.remove(live, idx)
	local bubble = outer:FindFirstChild("Bubble")
	if bubble then
		UiKit.Tween(UiKit.Scale(bubble), 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
	task.delay(0.2, function()
		outer:Destroy()
	end)
end

function Toasts.Show(text: any, kind: any)
	local parent = container
	if not parent then
		return
	end
	local k = if type(kind) == "string" and KIND_COLORS[kind] then kind else "info"
	local color = KIND_COLORS[k]
	local str = tostring(text)
	counter += 1

	local tall = utf8.len(str) ~= nil and (utf8.len(str) :: number) > 22
	local outer: Frame = Make("Frame", {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, if tall then 58 else 46),
		BackgroundTransparency = 1,
		LayoutOrder = counter,
		ZIndex = 40,
		Parent = parent,
	})
	local bubble: Frame = Make("Frame", {
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		ZIndex = 41,
		Parent = outer,
	})
	UiKit.Corner(bubble, UDim.new(0, 20))
	UiKit.Gradient(bubble)
	UiKit.Stroke(bubble, C.White, 3, true)
	UiKit.Label({
		Text = str,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -12),
		ZIndex = 42,
		Parent = bubble,
	}, { Stroke = UiKit.Darken(color, 0.45), MaxText = 26 })

	table.insert(live, outer)
	while #live > MAX do
		local old = table.remove(live, 1)
		if old then
			old:Destroy()
		end
	end

	UiKit.Pop(bubble, 0.4)
	if k == "alert" then
		UiKit.PlaySound("Alert")
		task.delay(0.15, function()
			UiKit.Shake(bubble, 7, 14)
		end)
	end
	task.delay(if k == "alert" then 5 elseif tall then 4 else 3.2, function()
		remove(outer)
	end)
end

----------------------------------------------------------------------
-- 큰 배너
----------------------------------------------------------------------

-- 배너 버튼이 지금 보여야 하나
local function buttonShown(entry: BannerEntry): boolean
	local spec = entry.Spec
	if not spec.ButtonText or not spec.OnButton then
		return false
	end
	local check = spec.ButtonVisible
	if check then
		local ok, result = pcall(check)
		return ok and result == true
	end
	return true
end

-- 크기·자리: 화면 위쪽 가운데, 왼쪽 큰 버튼과 겹치면 그 오른쪽으로 비켜요
local function layoutBanner()
	local outer = bannerOuter
	local gui = rootGui
	if not outer or not gui or not gui:IsA("GuiBase2d") then
		return
	end
	local size = (gui :: GuiBase2d).AbsoluteSize
	local w, h = size.X, size.Y
	if w <= 0 or h <= 0 then
		return
	end
	bannerHeight = if h < 500 then 80 else 100
	local left, right = 16, w - 16
	local g = guard
	if g and g.Parent and g.Visible then
		local gp, gs = g.AbsolutePosition, g.AbsoluteSize
		if gp.Y < TOP + bannerHeight and gp.Y + gs.Y > TOP and gp.X < w / 2 then
			left = math.max(left, gp.X + gs.X + 10)
		end
	end
	if right - left < 300 then
		left = 16 -- 너무 좁으면 (세로 폰) 그냥 가운데
	end
	local width = math.min(math.clamp(math.floor(w * 0.6), 320, 620), right - left)
	local x = math.clamp(math.floor(w / 2 - width / 2), left, math.max(left, right - width))
	bannerWidth = width
	outer.Position = UDim2.fromOffset(x, TOP)
	outer.Size = UDim2.fromOffset(width, bannerHeight)

	-- 안쪽: [그림] [글자 두 줄] [버튼]
	local pad = 8
	local icon = bannerHeight - 2 * pad
	bannerIcon.Size = UDim2.fromOffset(icon, icon)
	bannerIcon.Position = UDim2.new(0, pad + 2, 0.5, 0)
	bannerCount.Position = UDim2.new(0, pad + 2 + icon - 6, 0.5, math.floor(icon / 2) - 6)
	local current = bannerCurrent
	local showButton = current ~= nil and buttonShown(current)
	local buttonW = math.clamp(math.floor(width * 0.27), 112, 160)
	bannerButton.Size = UDim2.fromOffset(buttonW, math.max(44, bannerHeight - 30))
	bannerButton.Visible = showButton
	local textLeft = pad + 2 + icon + 10
	local textRight = if showButton then buttonW + 2 * pad + 6 else 2 * pad
	bannerTitle.Position = UDim2.new(0, textLeft, 0, 6)
	bannerTitle.Size = UDim2.new(1, -(textLeft + textRight), 0.58, -6)
	bannerSub.Position = UDim2.new(0, textLeft, 0.6, 0)
	bannerSub.Size = UDim2.new(1, -(textLeft + textRight), 0.32, -2)
end

-- 화면 크기가 바뀌면 배너 자리 + 말풍선 높이 다시
local function relayoutAll()
	layoutBanner()
	moveToasts()
end

local function hideBanner()
	local outer = bannerOuter
	bannerCurrent = nil
	if not outer or not outer.Visible then
		return
	end
	bannerToken += 1
	local my = bannerToken
	UiKit.Tween(UiKit.Scale(bannerBubble), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.delay(0.22, function()
		if bannerToken == my then
			outer.Visible = false
			moveToasts()
		end
	end)
end

local function ensureBanner()
	if bannerOuter then
		return
	end
	local gui = rootGui
	if not gui then
		return
	end
	local outer: Frame = Make("Frame", {
		Name = "Banner",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(bannerWidth, bannerHeight),
		Visible = false,
		ZIndex = 44,
		Parent = gui,
	})
	local bubble: Frame = Make("Frame", {
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Cream,
		ZIndex = 45,
		Parent = outer,
	})
	UiKit.Corner(bubble, UDim.new(0, 24))
	UiKit.Gradient(bubble)
	local stroke = UiKit.Stroke(bubble, C.Gold, 5, true)
	local icon: Frame = Make("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UiKit.Lighten(C.Gold, 0.6),
		ClipsDescendants = true,
		ZIndex = 46,
		Parent = bubble,
	})
	UiKit.Corner(icon, UDim.new(0.3, 0))
	UiKit.Stroke(icon, C.White, 3, true)
	-- ×2 (같은 알림이 또 왔어요). 그림 칸은 잘라내니까 bubble 에 두고 그림 오른쪽 아래에 맞춰요
	local count: Frame = Make("Frame", {
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(38, 24),
		BackgroundColor3 = C.Red,
		Visible = false,
		ZIndex = 49,
		Parent = bubble,
	})
	UiKit.Corner(count, UDim.new(0.5, 0))
	UiKit.Stroke(count, C.White, 2, true)
	local countLabel = UiKit.Label({
		Text = "×2",
		Size = UDim2.fromScale(0.84, 0.8),
		Position = UDim2.fromScale(0.08, 0.1),
		ZIndex = 50,
		Parent = count,
	}, { Stroke = UiKit.Darken(C.Red, 0.4), MaxText = 18 })
	local title = UiKit.Label({
		Name = "Title",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 46,
		Parent = bubble,
	}, { MaxText = 30, StrokeThickness = 3 })
	local sub = UiKit.Label({
		Name = "Sub",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Ink,
		ZIndex = 46,
		Parent = bubble,
	}, { Stroke = C.White, MaxText = 20 })
	local button, buttonLabel = UiKit.Button({
		Name = "Go",
		Text = "🗺 바로 가기",
		Color = C.Mint,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Radius = UDim.new(0.4, 0),
		TextSize = 24,
		ZIndex = 47,
		Parent = bubble,
		OnClick = function()
			local entry = bannerCurrent
			if not entry or entry.Closed then
				return
			end
			local fn = entry.Spec.OnButton
			if not fn then
				return
			end
			local ok, close = pcall(fn)
			if not ok then
				warn("[Toasts] 배너 버튼 오류:", close)
			elseif close == true then
				entry.Closed = true
				hideBanner()
			end
		end,
	})

	bannerOuter = outer
	bannerBubble = bubble
	bannerStroke = stroke
	bannerIcon = icon
	bannerCount = count
	bannerCountLabel = countLabel
	bannerTitle = title
	bannerSub = sub
	bannerButton = button
	bannerButtonLabel = buttonLabel

	if gui:IsA("GuiBase2d") then
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutAll)
	end
end

-- 글자·버튼·×N 다시 (보이는 동안 0.25초마다)
local function refreshBanner(entry: BannerEntry)
	local spec = entry.Spec
	local showButton = buttonShown(entry)
	bannerTitle.Text = spec.Title
	local sub = if not showButton and spec.HiddenSub then spec.HiddenSub else (spec.Sub or "")
	bannerSub.Text = sub
	bannerSub.Visible = sub ~= ""
	bannerCount.Visible = entry.Count >= 2
	bannerCountLabel.Text = "×" .. tostring(entry.Count)
	if bannerButton.Visible ~= showButton then
		layoutBanner()
	end
end

local function showBanner(entry: BannerEntry)
	ensureBanner()
	local outer = bannerOuter
	if not outer then
		return
	end
	local spec = entry.Spec
	local color = spec.Color or C.Gold
	bannerToken += 1
	bannerStroke.Color = color
	bannerIcon.BackgroundColor3 = UiKit.Lighten(color, 0.65)
	local titleStroke = bannerTitle:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = UiKit.Darken(color, 0.4)
	end
	for _, child in bannerIcon:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if spec.IconKind and spec.IconId then
		UiKit.Viewport(spec.IconKind, spec.IconId, bannerIcon)
	else
		UiKit.Label({ Text = spec.IconText or "✨", ZIndex = 47, Parent = bannerIcon }, { MaxText = 60 })
	end
	local buttonColor = spec.ButtonColor or C.Mint
	bannerButton.BackgroundColor3 = buttonColor
	bannerButtonLabel.Text = spec.ButtonText or ""
	local labelStroke = bannerButtonLabel:FindFirstChildOfClass("UIStroke")
	if labelStroke then
		labelStroke.Color = UiKit.Darken(buttonColor, 0.45)
	end
	bannerCurrent = entry
	outer.Visible = true
	layoutBanner()
	refreshBanner(entry)
	UiKit.Pop(bannerBubble, 0.45)
	UiKit.PlaySound(spec.Sound or "Alert")
	task.delay(0.45, function()
		if bannerCurrent == entry and not entry.Closed then
			UiKit.Shake(bannerIcon, 8, 8)
		end
	end)
	moveToasts()
end

local function runBanners()
	if bannerRunning then
		return
	end
	bannerRunning = true
	task.spawn(function()
		while #bannerQueue > 0 and not bannerSuppressed do
			local entry = table.remove(bannerQueue, 1) :: BannerEntry
			entry.Shown = os.clock()
			entry.Until = entry.Shown + (entry.Spec.Duration or BANNER_TIME)
			showBanner(entry)
			while not entry.Closed and not bannerSuppressed do
				task.wait(0.25)
				local now = os.clock()
				if now >= entry.Until or (#bannerQueue > 0 and now >= entry.Shown + BANNER_MIN) then
					break
				end
				if bannerCurrent == entry then
					refreshBanner(entry)
				end
			end
			entry.Closed = true
			hideBanner()
			task.wait(0.35)
		end
		bannerRunning = false
	end)
end

-- 큰 배너 띄우기 (줄 서기 · 같은 Key 는 합치기)
function Toasts.Banner(spec: BannerSpec)
	if bannerSuppressed or not rootGui or type(spec) ~= "table" or type(spec.Title) ~= "string" then
		return
	end
	local key = spec.Key
	local current = bannerCurrent
	if key and current and not current.Closed and current.Spec.Key == key then
		current.Count += 1
		current.Until = math.max(current.Until, os.clock() + (spec.Duration or BANNER_TIME))
		refreshBanner(current)
		UiKit.Bump(bannerBubble, 0.1)
		UiKit.PlaySound(spec.Sound or "Alert")
		return
	end
	if key then
		for _, waiting in bannerQueue do
			if waiting.Spec.Key == key then
				waiting.Count += 1
				return
			end
		end
	end
	table.insert(bannerQueue, { Spec = spec, Count = 1, Shown = 0, Until = 0, Closed = false })
	while #bannerQueue > BANNER_QUEUE_MAX do
		table.remove(bannerQueue, 1) -- 너무 많이 밀리면 오래된 것부터 버려요
	end
	runBanners()
end

-- 배너 쉬기 (꾸미기 모드 동안): 켜면 지금 배너를 닫고 기다리던 것도 버려요
function Toasts.SetBannerSuppressed(on: boolean)
	bannerSuppressed = on
	if on then
		table.clear(bannerQueue)
		local current = bannerCurrent
		if current then
			current.Closed = true
		end
		hideBanner()
	end
end

-- 배너가 비켜야 하는 화면 요소 (왼쪽 큰 버튼 칸)
function Toasts.SetBannerGuard(obj: GuiObject?)
	guard = obj
	if obj then
		obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutAll)
		obj:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayoutAll)
	end
	relayoutAll()
end

-- (검사용) 지금 보이는 배너: (Frame?, 제목, 버튼 보임?)
function Toasts.BannerState(): (Frame?, string?, boolean)
	local outer = bannerOuter
	if not outer or not outer.Visible or not bannerCurrent then
		return nil, nil, false
	end
	return outer, bannerTitle.Text, bannerButton.Visible
end

return Toasts
