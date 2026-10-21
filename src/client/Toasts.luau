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
local bannerPlaced = false
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

-- 말풍선 줄 자리: 보통 코인 아래 가운데. 배너와 겹치면 (좁은 화면) 왼쪽으로 비키고, 그래도 안 되면 배너 아래로
local function moveToasts()
	local frame = container
	local gui = rootGui
	if not frame or not gui or not gui:IsA("GuiBase2d") then
		return
	end
	local gw = (gui :: GuiBase2d).AbsoluteSize.X
	local cw = frame.AbsoluteSize.X
	local x: number? = nil
	local y = TOP
	local b = bannerRect()
	if b and cw > 0 then
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
			if right - left >= cw then
				x = math.floor(math.min(gw / 2, right - cw / 2))
			else
				y = math.floor(b.Y1 + 8)
			end
		end
	end
	if x == toastX and y == toastY then
		return
	end
	toastX, toastY = x, y
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

