-- 알림 말풍선 (코인 아래 가운데에 쌓여요, 최대 4개)
-- + 큰 배너 하나 (Toasts.Banner): "✨ 정글에 점박이 알이 나타났어요!" 처럼 그림 + 버튼이 있는 알림.
--   ★ 화면 가운데(눈높이)를 가리지 않게 오른쪽 옆 칸 위쪽에 작게 미끄러져 들어와요 (UiKit.SideSpot).
--   같은 Key 가 또 오면 합치고 (×2), 다른 건 줄을 서서 차례로 보여요.
--   부화 연출이 옆 칸을 쓰고 있어서 자리가 없으면 잠깐 숨었다가 (시간은 멈춰요) 끝나면 다시 나와요.
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
local TOAST_GAP = 6
local container: Frame? = nil
local live: { Frame } = {}
local counter = 0
local toastX: number? = nil -- nil = 가운데 (배너를 비켜 왼쪽으로 가면 픽셀)
local toastY = TOP

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

type BannerEntry = { Spec: BannerSpec, Count: number, Shown: number, Until: number, Closed: boolean, Played: boolean? }

local BANNER_TIME = 6
local BANNER_MIN = 3 -- 기다리는 배너가 있으면 이만큼만 보여 주고 다음으로
local BANNER_QUEUE_MAX = 3
local BANNER_MAX_WAIT = 20 -- 부화 연출이 길게 이어져서 이만큼 못 나오면 버려요 (알이 벌써 없을 거예요)
local TICK = 0.25

local rootGui: Instance? = nil
local guard: GuiObject? = nil -- 왼쪽 큰 버튼 칸 (그 부모 = 메인 GUI 에서 피할 것들을 찾아요)
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
local bannerWidth = 320
local bannerX, bannerY = 0, TOP
local bannerOut = false -- 보이는 중 (미끄러져 나가는 중이면 false)
local bannerQueue: { BannerEntry } = {}
local bannerCurrent: BannerEntry? = nil
local bannerRunning = false
local bannerSuppressed = false
local bannerToken = 0

local function bannerRect(): UiKit.Rect?
	local outer = bannerOuter
	if not outer or not outer.Visible or not bannerOut then
		return nil
	end
	return { X0 = bannerX, Y0 = bannerY, X1 = bannerX + bannerWidth, Y1 = bannerY + bannerHeight, Tag = "Banner" }
end

local function toastsHeight(): number
	local h = 0
	for i, t in live do
		h += t.Size.Y.Offset + (if i > 1 then TOAST_GAP else 0)
	end
	return h
end

-- 말풍선 줄 자리: 보통 코인 아래 가운데. 옆 칸 배너와 겹치면 (좁은 화면) 왼쪽으로 비키고 (290px 까지 좁게),
-- 그래도 안 되면 배너 아래로
local TOAST_MIN_W = 290
local toastW: number? = nil -- nil = 보통 너비 (화면 50%, 290~560)
local function moveToasts()
	local frame = container
	local gui = rootGui
	if not frame or not gui or not gui:IsA("GuiBase2d") then
		return
	end
	local gw = (gui :: GuiBase2d).AbsoluteSize.X
	local cw = math.clamp(math.floor(gw * 0.5), TOAST_MIN_W, 560)
	local x: number? = nil
	local y = TOP
	local width: number? = nil
	local b = bannerRect()
	if b then
		local colH = math.max(toastsHeight(), 58)
		local col = { X0 = gw / 2 - cw / 2, Y0 = TOP, X1 = gw / 2 + cw / 2, Y1 = TOP + colH }
		if UiKit.RectsHit(col, b) then
			local left = 12
			local g = guard
			if g and g.Parent and g.Visible then
				local side = UiKit.RectOf(g, 0)
				if side.Y0 < col.Y1 and col.Y0 < side.Y1 then
					left = math.max(left, side.X1 + 8)
				end
			end
			local right = b.X0 - 8
			if right - left >= TOAST_MIN_W then
				width = math.floor(math.min(cw, right - left))
				x = math.floor(math.min(gw / 2, right - (width :: number) / 2))
			else
				y = math.floor(b.Y1 + 8)
			end
		end
	end
	if x == toastX and y == toastY and width == toastW then
		return
	end
	toastX, toastY, toastW = x, y, width
	frame.Size = if width then UDim2.fromOffset(width, 260) else UDim2.new(0.5, 0, 0, 260)
	UiKit.Tween(frame, 0.2, { Position = if x then UDim2.fromOffset(x, y) else UDim2.new(0.5, 0, 0, y) })
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
		Padding = UDim.new(0, TOAST_GAP),
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
	moveToasts()
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
	moveToasts()

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
-- 큰 배너 (오른쪽 옆 칸)
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

local function mainGui(): Instance?
	local g = guard
	return if g then g.Parent else nil
end

local function setMaxText(label: TextLabel, size: number, stroke: number?)
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c.MaxTextSize = size
	end
	local s = label:FindFirstChildOfClass("UIStroke")
	if s and stroke then
		s.Thickness = stroke
	end
end

-- 크기·안쪽 배치: [그림] [제목 두 줄 / 작은 글 / 🗺 버튼]
-- 큰 화면 300~360 × 139 (버튼 없으면 110), 낮은 화면(폰, 높이 < 500) 230~270 × 114 (버튼 없으면 86)
local function sizeBanner(gw: number, gh: number, showButton: boolean): (number, number)
	local small = gh < 500
	local pad = if small then 6 else 9
	local icon = if small then 58 else 80
	local titleH = if small then 34 else 44
	local subH = if small then 26 else 30
	local buttonH = if small then 36 else 40
	local gap = if small then 4 else 5
	local width = if small
		then math.clamp(math.floor(gw * 0.31), 230, 270)
		else math.clamp(math.floor(gw * 0.19), 300, 360)
	if not showButton then
		subH += if small then 12 else 16 -- 버튼 자리에 HiddenSub 를 두 줄로
	end
	local height = math.max(pad + titleH + 2 + subH + (if showButton then gap + buttonH else 0) + pad, icon + 2 * pad)

	bannerIcon.Size = UDim2.fromOffset(icon, icon)
	bannerIcon.Position = UDim2.new(0, pad, 0.5, 0)
	bannerCount.Size = if small then UDim2.fromOffset(34, 22) else UDim2.fromOffset(38, 24)
	bannerCount.Position = UDim2.new(0, pad + icon - 6, 0.5, math.floor(icon / 2) - 6)
	local textLeft = pad + icon + 8
	local textW = width - textLeft - pad
	bannerTitle.Position = UDim2.fromOffset(textLeft, pad)
	bannerTitle.Size = UDim2.fromOffset(textW, titleH)
	bannerSub.Position = UDim2.fromOffset(textLeft, pad + titleH + 2)
	bannerSub.Size = UDim2.fromOffset(textW, subH)
	bannerButton.Visible = showButton
	bannerButton.AnchorPoint = Vector2.zero
	bannerButton.Position = UDim2.fromOffset(textLeft, pad + titleH + 2 + subH + gap)
	bannerButton.Size = UDim2.fromOffset(textW, buttonH)
	setMaxText(bannerTitle, if small then 16 else 22, if small then 2 else 3)
	setMaxText(bannerSub, if small then 13 else 16)
	setMaxText(bannerButtonLabel, if small then 18 else 22)
	bannerStroke.Thickness = if small then 4 else 5
	return width, height
end

-- 자리: 오른쪽 옆 칸 위쪽 (코인 줄 · 열린 창 ✖ · 점프 버튼 · 꾸미기 버튼 · 부화 연출을 피해요).
-- 0.25초마다 다시 재서, 창이 열리거나 닫히면 부드럽게 옮겨 가요.
-- 돌려주는 값: 지금 보여도 되나 (부화 연출 때문에 빈자리가 없으면 false → 잠깐 숨어요)
local function layoutBanner(): boolean
	local outer = bannerOuter
	local gui = rootGui
	if not outer or not gui or not gui:IsA("GuiBase2d") then
		return false
	end
	local size = (gui :: GuiBase2d).AbsoluteSize
	local gw, gh = size.X, size.Y
	if gw <= 0 or gh <= 0 then
		return false
	end
	local current = bannerCurrent
	local w, h = sizeBanner(gw, gh, current ~= nil and buttonShown(current))
	local avoid = UiKit.SideObstacles(mainGui())
	local hatch = UiKit.SideRect("Hatch")
	if hatch then
		table.insert(avoid, hatch)
	end
	local small = gh < 500
	-- 늘 오른쪽 끝에 붙어요 (자리가 없으면 왼쪽 아래로 헤매지 않고 잠깐 숨어요)
	local x, y, ov = UiKit.SideSpot(gw, gh, w, h, math.floor(gh * (if small then 0.2 else 0.18)), avoid, if small then 10 else 16, true)
	local moved = x ~= bannerX or y ~= bannerY
	bannerX, bannerY, bannerWidth, bannerHeight = x, y, w, h
	local pos = UDim2.fromOffset(x, y)
	if moved and outer.Visible and bannerOut then
		UiKit.Tween(outer, 0.25, { Position = pos })
	else
		outer.Position = pos
	end
	outer.Size = UDim2.fromOffset(w, h)
	if bannerOut then
		UiKit.SetSideRect("Banner", bannerRect())
	end
	-- 부화 연출 중인데 빈자리가 없으면 숨어요 (연출이 끝나면 자리가 나요)
	return hatch == nil or ov == 0
end

-- 화면 크기가 바뀌면 배너 자리 + 말풍선 자리 다시
local function relayoutAll()
	if bannerOuter then
		layoutBanner()
	end
	moveToasts()
end

-- 오른쪽 화면 밖까지 거리 (미끄러져 들어오고 나가요)
local function slideDistance(): number
	local gui = rootGui
	local gw = if gui and gui:IsA("GuiBase2d") then (gui :: GuiBase2d).AbsoluteSize.X else 1000
	return math.max(60, gw - bannerX + 12)
end

local function slideIn()
	local outer = bannerOuter
	if not outer then
		return
	end
	bannerToken += 1
	outer.Visible = true
	bannerOut = true
	UiKit.Scale(bannerBubble).Scale = 1
	bannerBubble.Position = UDim2.new(0.5, slideDistance(), 0.5, 0)
	UiKit.Tween(bannerBubble, 0.35, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
	UiKit.SetSideRect("Banner", bannerRect())
	moveToasts()
end

local function slideOut()
	local outer = bannerOuter
	bannerOut = false
	UiKit.SetSideRect("Banner", nil)
	if not outer or not outer.Visible then
		return
	end
	bannerToken += 1
	local my = bannerToken
	UiKit.Tween(bannerBubble, 0.22, { Position = UDim2.new(0.5, slideDistance(), 0.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.24, function()
		if bannerToken == my then
			outer.Visible = false
		end
	end)
	moveToasts()
end

local function hideBanner()
	bannerCurrent = nil
	slideOut()
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
	UiKit.Corner(bubble, UDim.new(0, 20))
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
	}, { MaxText = 21, StrokeThickness = 3 })
	local sub = UiKit.Label({
		Name = "Sub",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Ink,
		ZIndex = 46,
		Parent = bubble,
	}, { Stroke = C.White, MaxText = 15 })
	local button, buttonLabel = UiKit.Button({
		Name = "Go",
		Text = "🗺 바로 가기",
		Color = C.Mint,
		Radius = UDim.new(0.4, 0),
		TextSize = 22,
		ZIndex = 47,
		Parent = bubble,
		OnClick = function()
			local entry = bannerCurrent
			if not entry or entry.Closed or not bannerOut then
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

-- 글자·×N 다시 (0.25초마다)
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

-- 새 배너 그림·색 채우기 (아직 숨은 채로)
local function fillBanner(entry: BannerEntry)
	local spec = entry.Spec
	local color = spec.Color or C.Gold
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
	refreshBanner(entry)
end

-- 미끄러져 들어오기 (처음 나올 때만 소리 + 그림 흔들기)
local function showBanner(entry: BannerEntry)
	slideIn()
	if not entry.Played then
		entry.Played = true
		UiKit.PlaySound(entry.Spec.Sound or "Alert")
		task.delay(0.45, function()
			if bannerCurrent == entry and not entry.Closed and bannerOut then
				UiKit.Shake(bannerIcon, 8, 8)
			end
		end)
	end
end

local function runBanners()
	if bannerRunning then
		return
	end
	bannerRunning = true
	task.spawn(function()
		while #bannerQueue > 0 and not bannerSuppressed do
			local entry = table.remove(bannerQueue, 1) :: BannerEntry
			ensureBanner()
			if not bannerOuter then
				break
			end
			local last = os.clock()
			entry.Shown = last
			entry.Until = last + (entry.Spec.Duration or BANNER_TIME)
			bannerCurrent = entry
			fillBanner(entry)
			local waited = 0
			while not entry.Closed and not bannerSuppressed do
				local free = layoutBanner()
				if free and not bannerOut then
					showBanner(entry)
				elseif not free and bannerOut then
					slideOut() -- 부화 연출에게 자리 비켜 주기
				end
				if bannerOut then
					refreshBanner(entry)
				end
				task.wait(TICK)
				local now = os.clock()
				local dt = now - last
				last = now
				if not bannerOut then
					-- 숨어 있는 동안은 시간이 멈춰요
					entry.Shown += dt
					entry.Until += dt
					waited += dt
					if waited >= BANNER_MAX_WAIT then
						break
					end
				elseif now >= entry.Until or (#bannerQueue > 0 and now >= entry.Shown + BANNER_MIN) then
					break
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
		if bannerOut then
			UiKit.Bump(bannerBubble, 0.1)
			UiKit.PlaySound(spec.Sound or "Alert")
		end
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

-- 메인 화면의 왼쪽 큰 버튼 칸 (말풍선이 비킬 때 쓰고, 그 부모 GUI 에서 배너가 피할 것들을 찾아요)
function Toasts.SetBannerGuard(obj: GuiObject?)
	guard = obj
	if obj then
		obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutAll)
		obj:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayoutAll)
	end
	relayoutAll()
end

-- 위쪽에 떠 있는 알림 상자들 (좋은 알 배너 + 말풍선 줄, 화면 픽셀). 아무것도 없으면 빈 표
-- ZoneClient 의 "○○에 왔어요!" 배너가 이것들과 겹치지 않게 비킬 때 써요
function Toasts.TopRects(): { UiKit.Rect }
	local out: { UiKit.Rect } = {}
	local b = bannerRect()
	if b then
		table.insert(out, b)
	end
	local frame = container
	local gui = rootGui
	if #live > 0 and frame and gui and gui:IsA("GuiBase2d") then
		local gw = (gui :: GuiBase2d).AbsoluteSize.X
		local cw = toastW or math.clamp(math.floor(gw * 0.5), TOAST_MIN_W, 560)
		local cx = toastX or gw / 2
		table.insert(out, { X0 = cx - cw / 2, Y0 = toastY, X1 = cx + cw / 2, Y1 = toastY + toastsHeight(), Tag = "Toasts" })
	end
	return out
end

-- (검사용) 지금 보이는 배너: (Frame?, 제목, 버튼 보임?)
function Toasts.BannerState(): (Frame?, string?, boolean)
	local outer = bannerOuter
	if not outer or not outer.Visible or not bannerOut or not bannerCurrent then
		return nil, nil, false
	end
	return outer, bannerTitle.Text, bannerButton.Visible
end

return Toasts
