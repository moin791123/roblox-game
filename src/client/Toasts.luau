-- 알림은 모두 오른쪽 아래 구석에 한 줄로 쌓여요 (화면 가운데·눈높이·다른 창을 가리지 않게).
--  · 말풍선 Toasts.Show(text, kind). "🆕 NEW!" 말풍선(새 친구)은 금색 + 조금 더 오래, 많이 밀려와도 먼저 버리지 않아요
--  · 좋은 알 배너 Toasts.Banner(spec): "✨ 정글에 점박이 알이 나타났어요!" 처럼 그림 + "🗺 바로 가기" 버튼.
--    같은 Key 가 또 오면 합치고 (×2), 다른 건 줄을 서서 차례로 (6초씩) 보여요. 꾸미기 중에는 쉬어요.
--  · 다른 모듈의 알림 상자 Toasts.Dock(key, frame, ...) (ZoneClient 의 "🦆 호수에 왔어요!")
-- 쌓는 순서 (아래 → 위): 좋은 알 배너, 그다음 먼저 온 것부터 (새 알림은 맨 위에 붙어요). 모두 오른쪽 끝에 맞춰요.
-- 폰 점프 버튼·조이스틱 칸·팁 줄·열린 창 ✖·꾸미기 버튼·코인 줄은 피해요 (UiKit.SideObstacles).
-- 부화 연출(UiKit.SideRect "Hatch")이 오른쪽 끝을 쓰면 그 왼쪽 아래로 비키고 (화면 가운데는 빼고),
-- 그래도 자리가 없으면 잠깐 숨었다가 (시간은 멈춰요) 자리가 나면 다시 나와요.
-- 쌓인 알림 상자 전체는 UiKit.SetSideRect("Banner") 로 알려서 부화 연출이 비켜 가요.
-- ★v6 아주 희귀한 알 배너 (시크릿 / 천상 / 이터널 알, egg.Special): "🌟 호수에 천상 알이 나타났어요!"
--   단계 색 테두리(천천히 도는 옅은 무지개) + 그림 아래 단계 알약 + "🎁 <펫> 확정!" + 💰·⏳ 남은 시간 + 🗺 바로 가기.
--   단계마다 다른 짧은 소리. 보통 배너보다 오래 (20초, 알이 벨트에 남아 있고 기다리는 배너가 없으면 40초까지),
--   알이 없어지면 (샀거나 지나갔으면) 일찍 닫혀요. 줄 맨 앞에 서고, 보통 배너·말풍선 때문에 버려지거나 숨지 않아요
--   (자리가 모자라면 보통 말풍선이 기다려요. "🆕 NEW!" 같은 중요한 말풍선만 잠깐 먼저).
--   희귀 펫이 태어났다는 말풍선 ("[천상] … 태어났어요!") 은 단계 색으로 조금 더 오래 보여요 (부화 숨기기 중 유일한 알림).
local UiKit = require(script.Parent.UiKit)

local Make, C = UiKit.Make, UiKit.Colors
local Config = UiKit.Config

local Toasts = {}

local KIND_COLORS: { [string]: Color3 } = {
	info = C.Sky,
	good = C.Mint,
	warn = C.Orange,
	alert = C.Red,
}

local MAX = 4 -- 말풍선 최대 (기다리는 것 포함)
local RARE_TOAST_TIME = 6 -- 희귀 펫 말풍선은 조금 더 오래
local TOAST_WAIT_MAX = 8 -- 자리가 없어서 이만큼 못 나온 말풍선은 버려요
local TALL_CHARS = 15 -- 이보다 긴 글은 두 줄 높이
local TICK = 0.25

----------------------------------------------------------------------
-- 상태
----------------------------------------------------------------------
type Toast = {
	Outer: Frame,
	Bubble: Frame,
	Label: TextLabel,
	Kind: string,
	Tall: boolean,
	Important: boolean, -- "alert" 이나 "🆕 NEW!" (부화 숨기기 중에는 이게 유일한 새 친구 알림): 넘치거나 줄이 밀려도 먼저 버리지 않아요
	Rare: string?, -- ★v6 희귀 펫 말풍선 (단계 키)
	Seq: number,
	Left: number, -- 보이는 동안 줄어드는 남은 시간
	Waited: number, -- 자리가 없어서 숨어 있던 시간
	Placed: boolean,
	Played: boolean,
	X: number,
	Y: number,
	W: number,
	H: number,
}

type Dock = {
	Key: string,
	Frame: GuiObject,
	PcH: number,
	SmallH: number,
	Seq: number,
	Placed: boolean,
	Rect: UiKit.Rect?,
}

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
	Rare: string?, -- ★v6 희귀 알 배너 단계 ("Hidden" | "Celestial" | "Eternal"). 알 그림(IconKind "Egg")이면 저절로 알아내요
	ShortTitle: string?, -- 희귀 배너가 한 줄로 줄었을 때 ("🌟 호수 천상 알!")
	Zone: number?, -- 희귀 알 배너: 그 알이 있는 지역 (없으면 알의 Zone)
	EggId: string?,
}

type BannerEntry = {
	Spec: BannerSpec,
	Count: number,
	Shown: number,
	Until: number,
	Closed: boolean,
	Played: boolean?,
	Rare: string?, -- ★v6 희귀 알 배너
	Uid: number?, -- 따라가는 내 벨트 알 (EggBelt)
	Start: number?, -- 처음 보인 시각 (os.clock)
	Seen: number?, -- 보인 시간 합 (숨어 있던 시간 빼고)
	Shrink: number?, -- 희귀 배너가 자리가 안 나면 1 = 작게, 2 = 한 줄 (제목 + 버튼)
}

local BANNER_TIME = 6
local BANNER_MIN = 3 -- 기다리는 배너가 있으면 이만큼만 보여 주고 다음으로
local BANNER_QUEUE_MAX = 3
local BANNER_MAX_WAIT = 20 -- 자리가 없어서 이만큼 못 나오면 버려요 (알이 벌써 없을 거예요)
local RARE_TIME = 20 -- ★v6 희귀 알 배너 기본 시간
local RARE_MAX = 40 -- 알이 아직 있고 기다리는 배너가 없으면 이만큼까지
local RARE_MIN = 2.5 -- 알이 없어져도 이만큼은 보여 줘요 (번쩍 사라지지 않게)
local RARE_MAX_WAIT = 60 -- 자리가 없어서 기다리는 희귀 배너 (알이 없어지면 그 전에 버려요)
local RARE_YIELD = 1.2 -- 희귀 배너가 기다리면 보통 배너는 이만큼만 보이고 비켜요
local RARE_SHARE = 8 -- 희귀 배너가 또 기다리면 지금 희귀 배너는 이만큼 보이고 다음으로

local rootGui: Instance? = nil
local guard: GuiObject? = nil -- 왼쪽 큰 버튼 칸 (그 부모 = 메인 GUI 에서 피할 것들을 찾아요)
local container: Frame? = nil
local toasts: { Toast } = {} -- 온 순서 (오래된 것 먼저)
local docks: { [string]: Dock } = {}
local seq = 0
local placedRects: { UiKit.Rect } = {}

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
local bannerIconStroke: UIStroke
local bannerChip: Frame -- ★v6 희귀 배너: 그림 아래 단계 알약 ("천상")
local bannerChipLabel: TextLabel
local bannerInfo: TextLabel -- ★v6 희귀 배너: "💰 1.2억 · ⏳ 58초"
local bannerHint: TextLabel -- ★v6 희귀 배너: 버튼 대신 (그 지역에 있을 때)
local bannerHeight = 100
local bannerWidth = 320
local bannerX, bannerY = 0, 0
local bannerFits = false -- 이번 자리 계산에서 자리를 받았나
local bannerOut = false -- 보이는 중 (미끄러져 나가는 중이면 false)
local bannerQueue: { BannerEntry } = {}
local bannerCurrent: BannerEntry? = nil
local bannerRunning = false
local bannerSuppressed = false
local bannerToken = 0

local ticking = false

local function mainGui(): Instance?
	local g = guard
	return if g then g.Parent else nil
end

local function guiSize(): (number, number)
	local gui = rootGui
	if gui and gui:IsA("GuiBase2d") then
		local s = (gui :: GuiBase2d).AbsoluteSize
		return s.X, s.Y
	end
	return 0, 0
end

-- 낮은 화면 (폰 가로, GUI 높이 < 500)
local function isSmall(gh: number): boolean
	return gh < 500
end

-- 줄 너비 (배너·말풍선·지역 배너 모두 같은 너비라 깔끔해요)
local function stackWidth(gw: number, gh: number): number
	if isSmall(gh) then
		return math.clamp(math.floor(gw * 0.31), 224, 270)
	end
	return math.clamp(math.floor(gw * 0.19), 300, 360)
end

local function toastHeight(t: Toast, small: boolean): number
	if small then
		return if t.Tall then 50 else 40
	end
	return if t.Tall then 58 else 46
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

----------------------------------------------------------------------
-- 배너 크기
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

-- 크기·안쪽 배치: [그림] [제목 두 줄 / 작은 글 / 🗺 버튼]
-- 큰 화면 300~360 × 139 (버튼 없으면 110), 낮은 화면(폰, 높이 < 500) 224~270 × 114 (버튼 없으면 86)
-- ★v6 희귀 배너: [그림 + 단계 알약] [제목 두 줄 / 🎁 펫 / 💰·⏳ / 🗺 버튼(또는 안내)]
-- 큰 화면 300~360 × 159, 폰 224~270 × 124 (버튼이 숨어도 높이는 그대로: 안내 글이 그 자리에).
-- 아주 낮은 화면(GUI 높이 < 320)이나 자리가 안 나면 작게 (shrink 1: × 109, 보통 배너보다 낮게),
-- 그래도 안 나면 (shrink 2) 그림 + 짧은 제목 한 줄 + 버튼만 (× 66)
local function sizeMiniRareBanner(gw: number, gh: number, showButton: boolean): (number, number)
	local small = isSmall(gh)
	local pad = if small then 6 else 8
	local icon = if small then 52 else 60
	local titleH = if small then 24 else 28
	local buttonH = if small then 28 else 32
	local width = stackWidth(gw, gh)
	local height = math.max(pad + titleH + 3 + buttonH + pad, icon + 2 * pad)
	bannerIcon.AnchorPoint = Vector2.zero
	bannerIcon.Size = UDim2.fromOffset(icon, icon)
	bannerIcon.Position = UDim2.fromOffset(pad, math.floor((height - icon) / 2))
	bannerChip.Visible = false
	bannerInfo.Visible = false
	bannerSub.Visible = false
	bannerCount.Size = UDim2.fromOffset(28, 18)
	bannerCount.Position = UDim2.fromOffset(pad + icon - 6, pad + 4)
	local textLeft = pad + icon + 8
	local textW = width - textLeft - pad
	bannerTitle.Position = UDim2.fromOffset(textLeft, pad)
	bannerTitle.Size = UDim2.fromOffset(textW, titleH)
	local y = pad + titleH + 3
	bannerButton.Visible = showButton
	bannerButton.AnchorPoint = Vector2.zero
	bannerButton.Position = UDim2.fromOffset(textLeft, y)
	bannerButton.Size = UDim2.fromOffset(textW, buttonH)
	bannerHint.Visible = not showButton
	bannerHint.Position = UDim2.fromOffset(textLeft, y)
	bannerHint.Size = UDim2.fromOffset(textW, buttonH)
	setMaxText(bannerTitle, if small then 16 else 20, 2)
	setMaxText(bannerButtonLabel, if small then 16 else 20)
	setMaxText(bannerHint, if small then 12 else 15)
	bannerStroke.Thickness = if small then 3 else 4
	return width, height
end

local function sizeRareBanner(gw: number, gh: number, showButton: boolean, shrink: number?): (number, number)
	if (shrink or 0) >= 2 then
		return sizeMiniRareBanner(gw, gh, showButton)
	end
	local small = isSmall(gh)
	local tight = small and ((shrink or 0) >= 1 or gh < 320)
	local pad = if tight then 6 elseif small then 7 else 10
	local icon = if tight then 54 elseif small then 60 else 86
	local chipH = if tight then 16 elseif small then 18 else 24
	local titleH = if tight then 32 elseif small then 36 else 50
	local subH = if tight then 16 elseif small then 18 else 24
	local infoH = if tight then 14 elseif small then 16 else 20
	local buttonH = if tight then 30 elseif small then 34 else 40
	local gap = if tight then 3 elseif small then 4 else 5
	local width = stackWidth(gw, gh)
	local height = math.max(pad + titleH + 2 + subH + infoH + gap + buttonH + pad, pad + icon + 4 + chipH + pad)
	local colH = icon + 4 + chipH
	local top = math.floor((height - colH) / 2)
	bannerIcon.AnchorPoint = Vector2.zero
	bannerIcon.Size = UDim2.fromOffset(icon, icon)
	bannerIcon.Position = UDim2.fromOffset(pad, top)
	bannerChip.Visible = true
	bannerChip.Size = UDim2.fromOffset(icon + 6, chipH)
	bannerChip.Position = UDim2.fromOffset(pad - 3, top + icon + 4)
	bannerCount.Size = if small then UDim2.fromOffset(30, 20) else UDim2.fromOffset(36, 22)
	bannerCount.Position = UDim2.fromOffset(pad + icon - 6, top + 6)
	local textLeft = pad + icon + 10
	local textW = width - textLeft - pad
	local y = pad
	bannerTitle.Position = UDim2.fromOffset(textLeft, y)
	bannerTitle.Size = UDim2.fromOffset(textW, titleH)
	y += titleH + 2
	bannerSub.Position = UDim2.fromOffset(textLeft, y)
	bannerSub.Size = UDim2.fromOffset(textW, subH)
	y += subH
	bannerInfo.Visible = true
	bannerInfo.Position = UDim2.fromOffset(textLeft, y)
	bannerInfo.Size = UDim2.fromOffset(textW, infoH)
	y += infoH + gap
	bannerButton.Visible = showButton
	bannerButton.AnchorPoint = Vector2.zero
	bannerButton.Position = UDim2.fromOffset(textLeft, y)
	bannerButton.Size = UDim2.fromOffset(textW, buttonH)
	bannerHint.Visible = not showButton
	bannerHint.Position = UDim2.fromOffset(textLeft, y)
	bannerHint.Size = UDim2.fromOffset(textW, buttonH)
	setMaxText(bannerTitle, if small then 17 else 24, if small then 2 else 3)
	setMaxText(bannerSub, if small then 14 else 18)
	setMaxText(bannerInfo, if small then 12 else 16)
	setMaxText(bannerChipLabel, if small then 13 else 17)
	setMaxText(bannerButtonLabel, if small then 18 else 22)
	setMaxText(bannerHint, if small then 13 else 16)
	bannerStroke.Thickness = if small then 4 else 5
	return width, height
end

local function sizeBanner(gw: number, gh: number, showButton: boolean, rare: boolean?, shrink: number?): (number, number)
	if rare then
		return sizeRareBanner(gw, gh, showButton, shrink)
	end
	bannerChip.Visible = false
	bannerInfo.Visible = false
	bannerHint.Visible = false
	bannerIcon.AnchorPoint = Vector2.new(0, 0.5)
	local small = isSmall(gh)
	local pad = if small then 6 else 9
	local icon = if small then 58 else 80
	local titleH = if small then 34 else 44
	local subH = if small then 26 else 30
	local buttonH = if small then 36 else 40
	local gap = if small then 4 else 5
	local width = stackWidth(gw, gh)
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

----------------------------------------------------------------------
-- 자리 계산 (오른쪽 아래 한 줄)
----------------------------------------------------------------------
type Item = { Kind: string, W: number, H: number, Toast: Toast?, Dock: Dock?, X: number?, Y: number? }
type Column = { X1: number, Cursor: number, Closed: boolean, Centre: boolean }

local CENTRE_MAX = 0.25 -- 오른쪽 끝이 아닌 줄의 상자는 화면 가운데 1/3 칸을 이보다 많이 (넓이 비율) 가리면 안 돼요

local function overlap(a: UiKit.Rect, b: UiKit.Rect): number
	local w = math.min(a.X1, b.X1) - math.max(a.X0, b.X0)
	local h = math.min(a.Y1, b.Y1) - math.max(a.Y0, b.Y0)
	return if w > 0 and h > 0 then w * h else 0
end

-- 줄 col 의 지금 높이(Cursor) 위에 w×h 상자 놓을 자리 (위쪽 y). 못 놓으면 nil
-- 코인 줄·점프 버튼 같은 것에 걸리면 그 위로 건너가요. 부화 연출이나 화면 가운데에 걸리면 이 줄은 여기서 끝
local function fitIn(col: Column, w: number, h: number, avoid: { UiKit.Rect }, centre: UiKit.Rect, gap: number): number?
	if col.Closed then
		return nil
	end
	local x0 = col.X1 - w
	if x0 < 8 then
		return nil
	end
	local y = math.floor(col.Cursor - h)
	for _ = 1, 12 do
		if y < 8 then
			return nil
		end
		local r: UiKit.Rect = { X0 = x0, Y0 = y, X1 = col.X1, Y1 = y + h }
		local hit: UiKit.Rect? = nil
		for _, o in avoid do
			if UiKit.RectsHit(r, o) then
				hit = o
				break
			end
		end
		if not hit and col.Centre and overlap(r, centre) > w * h * CENTRE_MAX then
			hit = centre
		end
		if not hit then
			return y
		end
		if hit.Tag == "Hatch" or hit == centre then
			return nil
		end
		y = math.floor(hit.Y0 - gap - h)
	end
	return nil
end

-- 한 상자를 자리에 (보이는 중이면 부드럽게 옮겨요)
local function moveTo(g: GuiObject, x: number, y: number, w: number, h: number, smooth: boolean)
	local ap = g.AnchorPoint
	local pos = UDim2.fromOffset(math.floor(x + w * ap.X), math.floor(y + h * ap.Y))
	if smooth and g.Visible and g.Position ~= pos then
		UiKit.Tween(g, 0.2, { Position = pos })
	else
		g.Position = pos
	end
	g.Size = UDim2.fromOffset(w, h)
end

local function popToast(t: Toast)
	UiKit.Pop(t.Bubble, 0.35)
	if not t.Played then
		t.Played = true
		if t.Kind == "alert" then
			UiKit.PlaySound("Alert")
			task.delay(0.15, function()
				UiKit.Shake(t.Bubble, 7, 14)
			end)
		end
	end
end

-- 전부 다시 놓기. 배너가 자리를 받았는지는 bannerFits 에 남겨요
local function layoutStack()
	local gw, gh = guiSize()
	if gw <= 0 or gh <= 0 then
		return
	end
	local small = isSmall(gh)
	local W = stackWidth(gw, gh)
	local m = if small then 10 else 16
	local gap = if small then 6 else 8

	-- 아래 → 위 순서
	local items: { Item } = {}
	local current = bannerCurrent
	if current and not current.Closed and bannerOuter then
		local w, h = sizeBanner(gw, gh, buttonShown(current), current.Rare ~= nil, current.Shrink)
		table.insert(items, { Kind = "Banner", W = w, H = h })
	end
	local rest: { Item } = {}
	for _, d in docks do
		table.insert(rest, { Kind = "Dock", W = W, H = if small then d.SmallH else d.PcH, Dock = d })
	end
	for _, t in toasts do
		table.insert(rest, { Kind = "Toast", W = W, H = toastHeight(t, small), Toast = t })
	end
	table.sort(rest, function(a, b)
		local sa = if a.Toast then a.Toast.Seq elseif a.Dock then a.Dock.Seq else 0
		local sb = if b.Toast then b.Toast.Seq elseif b.Dock then b.Dock.Seq else 0
		return sa < sb
	end)
	for _, it in rest do
		table.insert(items, it)
	end

	local avoid = UiKit.SideObstacles(mainGui())
	local hatch = UiKit.SideRect("Hatch")
	if hatch then
		table.insert(avoid, { X0 = hatch.X0, Y0 = hatch.Y0, X1 = hatch.X1, Y1 = hatch.Y1, Tag = "Hatch" })
	end
	local centre: UiKit.Rect = { X0 = gw / 3, Y0 = gh / 3, X1 = gw * 2 / 3, Y1 = gh * 2 / 3, Tag = "Centre" }

	-- 줄 (오른쪽 끝이 먼저): 오른쪽 끝, 그다음 오른쪽 끝을 막는 것 (부화 연출 · 점프 버튼 · 오른쪽 HUD 버튼)
	-- 바로 왼쪽에 맞춘 줄들. 오른쪽 끝이 아닌 줄은 화면 가운데를 (조금만) 피해요
	local xs: { number } = { gw - m }
	for _, o in avoid do
		if o.Tag ~= "Stick" and o.X1 > gw - m - W / 2 and o.X0 > gw / 2 and o.X0 - gap < gw - m then
			table.insert(xs, math.floor(o.X0 - gap))
		end
	end
	table.sort(xs, function(a, b)
		return a > b
	end)
	local colXs: { number } = {}
	for _, x in xs do
		local prev = colXs[#colXs]
		if #colXs < 4 and (not prev or prev - x > 4) and x - W >= 8 then
			table.insert(colXs, x)
		end
	end

	-- 차례로 놓아 보기 (skipDocks / skipBanner 면 그건 빼고). 돌려주는 값: 못 놓인 말풍선 수
	local function place(skipDocks: boolean, skipBanner: boolean): number
		local cols: { Column } = {}
		for i, x in colXs do
			table.insert(cols, { X1 = x, Cursor = gh - m, Closed = false, Centre = i > 1 })
		end
		local blocked = table.clone(avoid)
		local left = 0
		for _, it in items do
			it.X, it.Y = nil, nil
			if (skipBanner and it.Kind == "Banner") or (skipDocks and it.Kind == "Dock") then
				continue
			end
			for i, col in cols do
				local y = fitIn(col, it.W, it.H, blocked, centre, gap)
				if y then
					it.X, it.Y = col.X1 - it.W, y
					col.Cursor = y - gap
					-- 다른 줄의 상자도 이걸 비켜요
					table.insert(blocked, { X0 = col.X1 - it.W - gap, Y0 = y - gap, X1 = col.X1 + gap, Y1 = y + it.H + gap, Tag = "Placed" })
					-- 앞 줄은 더 안 써요 (위아래 순서가 뒤섞이지 않게). 아무 데도 못 놓인 상자는 줄을 안 막아요
					for j = 1, i - 1 do
						cols[j].Closed = true
					end
					break
				end
			end
			if it.Kind == "Toast" and it.X == nil then
				left += 1
			end
		end
		return left
	end
	-- 말풍선(누른 것에 대한 대답)이 먼저예요: 자리가 모자라면 (폰) 지역 배너가 먼저, 그래도 안 되면 좋은 알 배너가
	-- 잠깐 쉬어요 (좋은 알 배너는 시간이 멈춰요). 빼도 나아지지 않으면 그대로
	local best = place(false, false)
	if best > 0 then
		local pick = { false, false }
		local options = { { true, false }, { false, true }, { true, true } }
		-- ★v6 희귀 알 배너는 보통 말풍선 때문에 숨지 않아요 (못 놓인 말풍선 중 중요한 것이 있을 때만 잠깐)
		if current and current.Rare and not current.Closed then
			local importantWaiting = false
			for _, it in items do
				if it.Toast and it.X == nil and it.Toast.Important then
					importantWaiting = true
					break
				end
			end
			if not importantWaiting then
				options = { { true, false } }
			end
		end
		for _, opt in options do
			local n = place(opt[1], opt[2])
			if n < best then
				best, pick = n, opt
			end
			if best == 0 then
				break
			end
		end
		place(pick[1], pick[2])
	end

	-- 놓기
	table.clear(placedRects)
	local union: UiKit.Rect? = nil
	local waiting = false
	for _, it in items do
		local x, y = it.X, it.Y
		local placed = x ~= nil and y ~= nil
		if placed then
			local r: UiKit.Rect = { X0 = x :: number, Y0 = y :: number, X1 = (x :: number) + it.W, Y1 = (y :: number) + it.H, Tag = it.Kind }
			table.insert(placedRects, r)
			if union then
				union.X0, union.Y0 = math.min(union.X0, r.X0), math.min(union.Y0, r.Y0)
				union.X1, union.Y1 = math.max(union.X1, r.X1), math.max(union.Y1, r.Y1)
			else
				union = { X0 = r.X0, Y0 = r.Y0, X1 = r.X1, Y1 = r.Y1, Tag = "Banner" }
			end
		end
		if it.Kind == "Banner" then
			bannerFits = placed
			if placed then
				local moved = x ~= bannerX or y ~= bannerY
				bannerX, bannerY, bannerWidth, bannerHeight = x :: number, y :: number, it.W, it.H
				local outer = bannerOuter :: Frame
				if moved and outer.Visible and bannerOut then
					UiKit.Tween(outer, 0.25, { Position = UDim2.fromOffset(bannerX, bannerY) })
				elseif not (outer.Visible and bannerOut) then
					outer.Position = UDim2.fromOffset(bannerX, bannerY)
				end
				outer.Size = UDim2.fromOffset(it.W, it.H)
			end
		elseif it.Toast then
			local t = it.Toast
			t.W, t.H = it.W, it.H
			if placed then
				local fresh = not t.Placed
				t.X, t.Y = x :: number, y :: number
				moveTo(t.Outer, t.X, t.Y, it.W, it.H, not fresh)
				t.Placed = true
				if fresh then
					t.Outer.Visible = true
					popToast(t)
				end
			else
				waiting = true
				if t.Placed then
					t.Placed = false
					t.Outer.Visible = false
				end
			end
		elseif it.Dock then
			local d = it.Dock
			if placed then
				local fresh = not d.Placed
				d.Rect = { X0 = x :: number, Y0 = y :: number, X1 = (x :: number) + it.W, Y1 = (y :: number) + it.H }
				moveTo(d.Frame, x :: number, y :: number, it.W, it.H, not fresh)
				d.Placed = true
				d.Frame.Visible = true
			else
				d.Placed = false
				d.Rect = nil
				d.Frame.Visible = false
			end
		end
	end
	if not current or current.Closed then
		bannerFits = false
	end
	-- 기다리는 말풍선이 있으면 가장 오래된 말풍선을 조금 일찍 보내요 (줄이 빨리 흘러요). 중요한 건 (NEW! 같은) 될 수 있으면 그대로
	if waiting then
		local cut: Toast? = nil
		for _, t in toasts do
			if t.Placed and not t.Important then
				cut = t
				break
			end
		end
		if not cut then
			for _, t in toasts do
				if t.Placed then
					cut = t
					break
				end
			end
		end
		if cut then
			cut.Left = math.min(cut.Left, 0.6)
		end
	end
	UiKit.SetSideRect("Banner", union)
end

----------------------------------------------------------------------
-- 말풍선
----------------------------------------------------------------------
function Toasts.Init(gui: Instance)
	rootGui = gui
	local frame: Frame = Make("Frame", {
		Name = "Toasts",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = gui,
	})
	container = frame
	if gui:IsA("GuiBase2d") then
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutStack)
	end
end

local function removeToast(t: Toast)
	local idx = table.find(toasts, t)
	if not idx then
		return
	end
	table.remove(toasts, idx)
	local outer = t.Outer
	if t.Placed and outer.Visible then
		UiKit.Tween(UiKit.Scale(t.Bubble), 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.2, function()
			outer:Destroy()
		end)
	else
		outer:Destroy()
	end
	layoutStack()
end

local function anyAlive(): boolean
	return #toasts > 0 or next(docks) ~= nil
end

-- 말풍선 시간 + 창·부화 연출이 생기고 없어질 때 다시 놓기 (알림이 있는 동안만 돌아요)
local function ensureTicker()
	if ticking then
		return
	end
	ticking = true
	task.spawn(function()
		local last = os.clock()
		while anyAlive() do
			task.wait(TICK)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, t in table.clone(toasts) do
				if t.Placed then
					t.Left -= dt
					if t.Left <= 0 then
						removeToast(t)
					end
				else
					t.Waited += dt
					if t.Waited >= TOAST_WAIT_MAX then
						removeToast(t)
					end
				end
			end
			layoutStack()
		end
		ticking = false
	end)
end

----------------------------------------------------------------------
-- ★v6 희귀 펫 말풍선: 서버의 "[천상] 달빛 백조가 태어났어요!" 같은 글 (부화 숨기기여도 와요)
----------------------------------------------------------------------
local expectRare: { Name: string, Tier: string, At: number, Used: boolean }? = nil
local EXPECT_TIME = 1.6 -- 부화 연출이 알려 준 뒤 서버 말풍선을 기다리는 시간

local function rareOfText(str: string): string?
	local e = expectRare
	if e and not e.Used and os.clock() - e.At <= EXPECT_TIME + 1 and string.find(str, e.Name, 1, true) then
		e.Used = true
		return e.Tier
	end
	for _, key in UiKit.SpecialOrder do
		local name = UiKit.RarityName(key)
		if name ~= "" and string.find(str, "[" .. name .. "]", 1, true) then
			return key
		end
	end
	-- 이름만 있는 말풍선 (합성 등): 새 친구·부화·합성 글일 때만
	if string.find(str, "NEW!", 1, true) or string.find(str, "태어났", 1, true) or string.find(str, "합성", 1, true) then
		for petId, def in Config.Pets do
			local tier = UiKit.PetSpecial(petId)
			if tier and string.find(str, def.Name, 1, true) then
				return tier
			end
		end
	end
	-- 희귀 알을 샀어요 (서버 "🌟 <알 이름>을 샀어요!")
	if string.find(str, "샀어요", 1, true) then
		for eggId, egg in Config.Eggs do
			local tier = UiKit.EggSpecial(eggId)
			if tier and type(egg.Name) == "string" and string.find(str, egg.Name, 1, true) then
				return tier
			end
		end
	end
	return nil
end

function Toasts.Show(text: any, kind: any)
	local parent = container
	if not parent then
		return
	end
	local k = if type(kind) == "string" and KIND_COLORS[kind] then kind else "info"
	local str = tostring(text)
	-- 🆕 새 친구 (서버 말풍선 "🆕 NEW! ..."): 금색으로 눈에 띄게
	local isNew = string.find(str, "NEW!", 1, true) ~= nil
	-- ★v6 희귀 펫: 단계 색 + 🌟 + 조금 더 오래 (중요한 말풍선)
	local rare = if k == "good" or isNew then rareOfText(str) else nil
	if rare and not string.find(str, "🌟", 1, true) then
		str = "🌟 " .. str
	end
	local color = if rare then UiKit.RarityColor(rare) elseif isNew then C.Gold else KIND_COLORS[k]
	seq += 1
	local len = utf8.len(str)
	local tall = rare ~= nil or (len ~= nil and (len :: number) > TALL_CHARS)
	local _, gh = guiSize()
	local small = isSmall(gh)

	local outer: Frame = Make("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(300, 46),
		BackgroundTransparency = 1,
		Visible = false,
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
	UiKit.Corner(bubble, UDim.new(0, if small then 16 else 20))
	UiKit.Gradient(bubble)
	local bubbleStroke = UiKit.Stroke(bubble, C.White, 3, true)
	if rare then
		bubbleStroke.Thickness = 4
		UiKit.SpecialGradient(bubbleStroke, rare, 7)
	end
	local label = UiKit.Label({
		Text = str,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -20, 1, -10),
		ZIndex = 42,
		Parent = bubble,
	}, { Stroke = UiKit.Darken(color, 0.45), MaxText = if small then 18 else 22 })

	local t: Toast = {
		Outer = outer,
		Bubble = bubble,
		Label = label,
		Kind = k,
		Tall = tall,
		Important = k == "alert" or isNew or rare ~= nil,
		Rare = rare,
		Seq = seq,
		Left = if rare then RARE_TOAST_TIME elseif k == "alert" or isNew then 5 elseif tall then 4 else 3.2,
		Waited = 0,
		Placed = false,
		Played = false,
		X = 0,
		Y = 0,
		W = 0,
		H = 0,
	}
	table.insert(toasts, t)
	while #toasts > MAX do
		-- 너무 많으면 가장 오래된 보통 말풍선부터 버려요 (모두 중요하면 가장 오래된 것)
		local drop = 1
		for i, old in toasts do
			if not old.Important then
				drop = i
				break
			end
		end
		local old = table.remove(toasts, drop)
		if old then
			old.Outer:Destroy()
		end
	end
	layoutStack()
	ensureTicker()
end

----------------------------------------------------------------------
-- 다른 모듈의 알림 상자 (ZoneClient 지역 배너): 자리·보이기는 여기서 정해요
----------------------------------------------------------------------

-- frame 을 줄에 넣어요 (새로 넣으면 맨 위). pcH / smallH = 큰 화면 / 폰 높이 (너비는 줄 너비)
-- 자리가 없으면 frame.Visible 을 잠깐 끄고, 자리가 나면 다시 켜요
function Toasts.Dock(key: string, frame: GuiObject, pcH: number?, smallH: number?)
	seq += 1
	local old = docks[key]
	docks[key] = {
		Key = key,
		Frame = frame,
		PcH = pcH or 84,
		SmallH = smallH or 58,
		Seq = seq,
		Placed = if old and old.Frame == frame then old.Placed else false,
		Rect = nil,
	}
	layoutStack()
	ensureTicker()
end

-- 줄에서 빼기 (frame 은 부른 쪽이 숨겨요)
function Toasts.Undock(key: string)
	if docks[key] then
		docks[key] = nil
		layoutStack()
	end
end

-- 줄에 들어 있는 상자가 지금 자리를 받았나
function Toasts.DockPlaced(key: string): boolean
	local d = docks[key]
	return d ~= nil and d.Placed
end

----------------------------------------------------------------------
-- 큰 배너 (줄 맨 아래)
----------------------------------------------------------------------

-- 오른쪽 화면 밖까지 거리 (미끄러져 들어오고 나가요)
local function slideDistance(): number
	local gw = guiSize()
	if gw <= 0 then
		gw = 1000
	end
	return math.max(60, gw - bannerX + 12)
end

local function slideIn()
	local outer = bannerOuter
	if not outer then
		return
	end
	bannerToken += 1
	outer.Position = UDim2.fromOffset(bannerX, bannerY)
	outer.Visible = true
	bannerOut = true
	UiKit.Scale(bannerBubble).Scale = 1
	bannerBubble.Position = UDim2.new(0.5, slideDistance(), 0.5, 0)
	UiKit.Tween(bannerBubble, 0.35, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
end

local function slideOut()
	local outer = bannerOuter
	bannerOut = false
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
end

local function hideBanner()
	bannerCurrent = nil
	slideOut()
	layoutStack()
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
	local iconStroke = UiKit.Stroke(icon, C.White, 3, true)
	-- ★v6 희귀 배너: 그림 아래 단계 알약
	local chip: Frame = Make("Frame", {
		Name = "TierChip",
		BackgroundColor3 = C.Gold,
		Visible = false,
		ZIndex = 48,
		Parent = bubble,
	})
	UiKit.Corner(chip, UDim.new(0.5, 0))
	UiKit.Gradient(chip)
	UiKit.Stroke(chip, C.White, 2, true)
	local chipLabel = UiKit.Label({
		Name = "Label",
		Text = "",
		Size = UDim2.fromScale(0.9, 0.84),
		Position = UDim2.fromScale(0.05, 0.08),
		ZIndex = 49,
		Parent = chip,
	}, { MaxText = 17 })
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
	local info = UiKit.Label({
		Name = "Info",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Ink,
		Visible = false,
		ZIndex = 46,
		Parent = bubble,
	}, { Stroke = C.White, MaxText = 16 })
	local hint = UiKit.Label({
		Name = "Hint",
		Text = "",
		Visible = false,
		ZIndex = 46,
		Parent = bubble,
	}, { MaxText = 16, StrokeThickness = 2 })
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
	bannerIconStroke = iconStroke
	bannerChip = chip
	bannerChipLabel = chipLabel
	bannerInfo = info
	bannerHint = hint
end

----------------------------------------------------------------------
-- ★v6 희귀 알 배너 도우미
----------------------------------------------------------------------

-- 내 벨트 알 (EggBelt) 은 없어도 돼요: 없으면 시간만으로 닫아요
local eggBeltMod: any = nil
local eggBeltTried = false
local function eggBelt(): any
	if not eggBeltTried then
		eggBeltTried = true
		local mod = script.Parent:FindFirstChild("EggBelt")
		if mod and mod:IsA("ModuleScript") then
			local ok, result = pcall(require, mod)
			if ok and type(result) == "table" then
				eggBeltMod = result
			end
		end
	end
	return eggBeltMod
end

-- 알이 아직 내 벨트에 있으면 남은 초 (모르면 nil, 없어졌으면 0)
local function rareLeft(entry: BannerEntry): number?
	local belt = eggBelt()
	if not belt then
		return nil
	end
	local spec = entry.Spec
	if not entry.Uid and spec.Zone and spec.EggId and type(belt.Find) == "function" then
		local ok, uid = pcall(belt.Find, spec.Zone, spec.EggId)
		if ok and type(uid) == "number" then
			entry.Uid = uid
		end
	end
	local uid = entry.Uid
	if not uid or type(belt.TimeLeft) ~= "function" then
		return nil
	end
	local ok, left = pcall(belt.TimeLeft, uid)
	if not ok then
		return nil
	end
	return if type(left) == "number" then left else 0
end

local function leftText(sec: number): string
	local s = math.max(0, math.floor(sec + 0.5))
	if s >= 60 then
		return string.format("⏳ %d분 %02d초", s // 60, s % 60)
	end
	return "⏳ " .. s .. "초"
end

-- 보통 배너 모양(알 그림)을 희귀 배너 글로 바꿔요 (init.client 의 EggAlert 배너를 그대로 받아요)
local function rareSpec(spec: BannerSpec): (BannerSpec, string?)
	local tier = spec.Rare
	local eggId = spec.EggId or (if spec.IconKind == "Egg" then spec.IconId else nil)
	if not tier and eggId then
		tier = UiKit.EggSpecial(eggId)
	end
	if not tier then
		return spec, nil
	end
	local out: BannerSpec = table.clone(spec)
	local egg: any = if eggId then Config.Eggs[eggId] else nil
	local zone = spec.Zone or (if egg then tonumber(egg.Zone) else nil)
	out.Rare = tier
	out.EggId = eggId
	out.Zone = zone
	local zoneDef: any = if zone then Config.Zones[zone] else nil
	local rname = UiKit.RarityName(tier)
	if not spec.Rare then
		-- 호출한 쪽이 보통 글을 줬으면 희귀 글로
		local where = if zoneDef then zoneDef.Name .. "에 " else ""
		out.Title = "🌟 " .. where .. UiKit.Josa(rname .. " 알", "이", "가") .. " 나타났어요!"
		out.ShortTitle = "🌟 " .. (if zoneDef then zoneDef.Name .. " " else "") .. rname .. " 알!"
		local petId = UiKit.SpecialPet(eggId)
		local pet: any = if petId then Config.Pets[petId] else nil
		out.Sub = if pet then "🎁 " .. pet.Name .. " 확정!" else "🎁 아주 희귀한 펫 확정!"
		out.HiddenSub = "🌟 빛기둥을 따라가요! 👀"
		out.Key = spec.Key or ("Rare:" .. tostring(zone) .. ":" .. tostring(eggId))
	end
	out.Color = UiKit.RarityColor(tier)
	return out, tier
end

-- 희귀 배너 "💰 1.2억 · ⏳ 58초"
local function rareInfoText(entry: BannerEntry, left: number?): string
	local spec = entry.Spec
	local egg: any = if spec.EggId then Config.Eggs[spec.EggId] else nil
	local parts: { string } = {}
	if egg and egg.Price then
		table.insert(parts, "💰 " .. Config.FormatNumber(egg.Price))
	end
	if left and left > 0 then
		table.insert(parts, leftText(left))
	else
		table.insert(parts, UiKit.SpecialStars(entry.Rare) .. " 아주 희귀!")
	end
	return table.concat(parts, " · ")
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
	if entry.Rare then
		-- 희귀 배너: 버튼이 숨으면 그 자리에 안내 글 (높이는 그대로). 한 줄 모양이면 짧은 제목
		local mini = (entry.Shrink or 0) >= 2
		bannerTitle.Text = if mini and spec.ShortTitle then spec.ShortTitle else spec.Title
		bannerSub.Text = spec.Sub or ""
		bannerSub.Visible = bannerSub.Text ~= "" and not mini
		bannerInfo.Text = rareInfoText(entry, rareLeft(entry))
		bannerHint.Text = spec.HiddenSub or ""
		if bannerButton.Visible ~= showButton or bannerHint.Visible == showButton then
			layoutStack()
		end
		return
	end
	if bannerButton.Visible ~= showButton then
		layoutStack()
	end
end

-- 새 배너 그림·색 채우기 (아직 숨은 채로)
local function clearSpecial(parent: Instance)
	for _, child in parent:GetChildren() do
		if child.Name == "SpecialGradient" then
			child:Destroy()
		end
	end
end

local function fillBanner(entry: BannerEntry)
	local spec = entry.Spec
	local color = spec.Color or C.Gold
	local rare = entry.Rare
	bannerStroke.Color = if rare then C.White else color
	clearSpecial(bannerStroke)
	clearSpecial(bannerIconStroke)
	bannerBubble.BackgroundColor3 = if rare then UiKit.Lighten(color, 0.86) else C.Cream
	bannerIconStroke.Color = C.White
	bannerIconStroke.Thickness = 3
	if rare then
		-- 천천히 도는 옅은 단계 무지개 테두리 (번쩍이지 않게)
		UiKit.SpecialGradient(bannerStroke, rare, 6)
		UiKit.SpecialGradient(bannerIconStroke, rare)
		bannerIconStroke.Thickness = 4
		bannerChip.BackgroundColor3 = color
		bannerChipLabel.Text = UiKit.SpecialStars(rare) .. " " .. UiKit.RarityName(rare)
		local chipStroke = bannerChipLabel:FindFirstChildOfClass("UIStroke")
		if chipStroke then
			chipStroke.Color = UiKit.Darken(color, 0.5)
		end
		bannerHint.TextColor3 = C.White
		local hintStroke = bannerHint:FindFirstChildOfClass("UIStroke")
		if hintStroke then
			hintStroke.Color = UiKit.Darken(color, 0.45)
		end
	end
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
		if entry.Rare then
			UiKit.PlayRareSound(entry.Rare)
		else
			UiKit.PlaySound(entry.Spec.Sound or "Alert")
		end
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
			entry.Start = last
			entry.Seen = 0
			entry.Until = last + (entry.Spec.Duration or (if entry.Rare then RARE_TIME else BANNER_TIME))
			-- 희귀 알이 벌써 없어졌으면 (기다리는 동안 샀거나 지나갔어요) 건너뛰어요
			if entry.Rare and entry.Uid and rareLeft(entry) == 0 then
				entry.Closed = true
				continue
			end
			bannerCurrent = entry
			fillBanner(entry)
			local waited = 0
			while not entry.Closed and not bannerSuppressed do
				layoutStack()
				if bannerFits and not bannerOut then
					showBanner(entry)
				elseif not bannerFits and bannerOut then
					slideOut() -- 부화 연출·창에게 자리 비켜 주기
				end
				if bannerOut then
					refreshBanner(entry)
				end
				task.wait(TICK)
				local now = os.clock()
				local dt = now - last
				last = now
				local rare = entry.Rare
				local left: number? = nil
				if rare then
					left = rareLeft(entry)
				end
				local gone = left == 0
				local rareWaiting = false
				for _, q in bannerQueue do
					if q.Rare then
						rareWaiting = true
						break
					end
				end
				if not bannerOut then
					-- 숨어 있는 동안은 시간이 멈춰요
					entry.Shown += dt
					entry.Until += dt
					waited += dt
					if waited >= (if rare then RARE_MAX_WAIT else BANNER_MAX_WAIT) or gone then
						break
					end
					if rareWaiting and not rare then
						break -- 자리를 기다리던 보통 배너는 희귀 배너에게 바로 비켜요
					end
					-- 희귀 배너는 자리가 안 나면 1초 뒤 작게, 2초 뒤 한 줄로 (다음 자리 계산부터)
					if rare and waited >= 1 and (entry.Shrink or 0) < math.min(2, math.floor(waited)) then
						entry.Shrink = math.min(2, math.floor(waited))
						refreshBanner(entry)
					end
				elseif rare then
					entry.Seen = (entry.Seen or 0) + dt
					local seen = entry.Seen or 0
					if gone and seen >= RARE_MIN then
						break -- 알을 샀거나 지나갔어요
					end
					if rareWaiting and seen >= RARE_SHARE then
						break
					end
					if now >= entry.Until then
						-- 알이 아직 있고 기다리는 배너가 없으면 조금 더 (RARE_MAX 까지)
						local more = left ~= nil and left > 0 and #bannerQueue == 0 and seen < RARE_MAX
						if not more then
							break
						end
					end
				elseif now >= entry.Until then
					break
				elseif rareWaiting and now >= entry.Shown + RARE_YIELD then
					break -- 희귀 배너에게 바로 비켜요
				elseif #bannerQueue > 0 and now >= entry.Shown + BANNER_MIN then
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
function Toasts.Banner(rawSpec: BannerSpec)
	if not rootGui or type(rawSpec) ~= "table" or type(rawSpec.Title) ~= "string" then
		return
	end
	local spec, rare = rareSpec(rawSpec)
	if bannerSuppressed and not rare then
		return -- 꾸미기 중: 보통 배너는 버려요 (희귀 배너는 줄에 두었다가 끝나면 보여 줘요)
	end
	local key = spec.Key
	local current = bannerCurrent
	if key and current and not current.Closed and current.Spec.Key == key then
		current.Count += 1
		current.Until = math.max(current.Until, os.clock() + (spec.Duration or (if rare then RARE_TIME else BANNER_TIME)))
		refreshBanner(current)
		if bannerOut then
			UiKit.Bump(bannerBubble, 0.1)
			if rare then
				UiKit.PlayRareSound(rare)
			else
				UiKit.PlaySound(spec.Sound or "Alert")
			end
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
	local entry: BannerEntry = { Spec = spec, Count = 1, Shown = 0, Until = 0, Closed = false, Rare = rare }
	if rare then
		-- ★v6 희귀 알은 줄 맨 앞 (먼저 온 희귀 알 뒤)
		local at = #bannerQueue + 1
		for i, q in bannerQueue do
			if not q.Rare then
				at = i
				break
			end
		end
		table.insert(bannerQueue, at, entry)
		-- 알림이 벨트 알보다 먼저 올 수도 있어요: 바로 한 번 찾아봐요
		rareLeft(entry)
	else
		table.insert(bannerQueue, entry)
	end
	while #bannerQueue > BANNER_QUEUE_MAX do
		-- 너무 많이 밀리면 오래된 보통 배너부터 버려요 (희귀 배너는 끝까지)
		local drop = nil
		for i, q in bannerQueue do
			if not q.Rare then
				drop = i
				break
			end
		end
		table.remove(bannerQueue, drop or 1)
	end
	runBanners()
end

-- ★v6 부화 연출이 알려 줘요: 곧 올 서버 말풍선 (그 펫 이름이 든 것) 을 희귀 색으로.
-- 말풍선이 EXPECT_TIME 안에 안 오면 (서버 글이 바뀌었어도) 작은 희귀 말풍선을 대신 띄워요
function Toasts.ExpectRare(petId: string, isNew: boolean?)
	local def: any = Config.Pets[petId]
	local tier = UiKit.PetSpecial(petId)
	if not def or not tier then
		return
	end
	local e = { Name = def.Name, Tier = tier, At = os.clock(), Used = false }
	expectRare = e
	task.delay(EXPECT_TIME, function()
		if expectRare == e and not e.Used then
			e.Used = true
			local rname = UiKit.RarityName(tier)
			Toasts.Show((if isNew then "🆕 NEW! " else "🎉 ") .. "[" .. rname .. "] " .. UiKit.Josa(def.Name, "이", "가") .. " 태어났어요!", "good")
		end
	end)
end

-- 배너 쉬기 (꾸미기 모드 동안): 켜면 지금 배너를 닫고 기다리던 보통 배너는 버려요.
-- ★v6 희귀 알 배너는 줄에 남겨 두었다가 (알이 ~60초 기다려요) 끄면 보여 줘요 (그 사이 알이 없어졌으면 건너뛰어요)
function Toasts.SetBannerSuppressed(on: boolean)
	bannerSuppressed = on
	if on then
		for i = #bannerQueue, 1, -1 do
			if not bannerQueue[i].Rare then
				table.remove(bannerQueue, i)
			end
		end
		local current = bannerCurrent
		if current and not current.Closed and current.Rare then
			-- 보이던 희귀 배너는 줄 맨 앞에 다시
			table.insert(bannerQueue, 1, { Spec = current.Spec, Count = current.Count, Shown = 0, Until = 0, Closed = false, Rare = current.Rare, Uid = current.Uid })
		end
		if current then
			current.Closed = true
		end
		hideBanner()
	elseif #bannerQueue > 0 then
		runBanners()
	end
end

-- 메인 화면의 왼쪽 큰 버튼 칸 (그 부모 GUI 에서 알림이 피할 것들을 찾아요)
function Toasts.SetBannerGuard(obj: GuiObject?)
	guard = obj
	if obj then
		obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutStack)
		obj:GetPropertyChangedSignal("AbsolutePosition"):Connect(layoutStack)
	end
	layoutStack()
end

-- 지금 화면에 놓인 알림 상자들 (배너 · 지역 배너 · 말풍선, 화면 픽셀). 아무것도 없으면 빈 표
function Toasts.AlertRects(): { UiKit.Rect }
	local out: { UiKit.Rect } = {}
	for _, r in placedRects do
		local keep = true
		if r.Tag == "Banner" then
			keep = bannerOut
		end
		if keep then
			table.insert(out, { X0 = r.X0, Y0 = r.Y0, X1 = r.X1, Y1 = r.Y1, Tag = r.Tag })
		end
	end
	return out
end
Toasts.TopRects = Toasts.AlertRects -- 예전 이름

-- (검사용) ★v6 지금 배너의 희귀 정보: { Rare, Title, Sub, Info, Hint, Chip, Seen, Uid } (희귀 배너가 아니면 nil)
function Toasts.RareBannerInfo(): { [string]: any }?
	local entry = bannerCurrent
	if not entry or entry.Closed or not entry.Rare or not bannerOuter then
		return nil
	end
	return {
		Rare = entry.Rare,
		Title = bannerTitle.Text,
		Sub = bannerSub.Text,
		Info = bannerInfo.Text,
		Hint = if bannerHint.Visible then bannerHint.Text else nil,
		Chip = bannerChipLabel.Text,
		Seen = entry.Seen,
		Uid = entry.Uid,
		Out = bannerOut,
		Queue = #bannerQueue,
	}
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
