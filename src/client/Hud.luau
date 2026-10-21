-- 화면 고정 UI: 코인(CoinSync 로 바로바로), 초당 수익, 집 금고, 펫 수, 왼쪽 큰 버튼 7개
-- (가방 B / 도감 N / 집 H / 상점 P / 지도 M / 순위 L / 환생 R). 화면이 낮으면 2~3열로 접혀요.
-- Hud.SetBadge("집", true): 버튼 오른쪽 위에 빨간 "!" (새 집을 살 수 있을 때 init.client 가 켜요)
-- 켜고 끄는 버튼 3개 (🙈 부화 숨기기 / 🏦 자동 수금 / 🧲 자석): 한 번 누르면 바로 켜짐/꺼짐 (색 + ON/OFF 스위치),
--   서버로 Remotes.SetSetting, 스냅샷 Settings 를 따라가요 (State.GetSetting). PC·태블릿은 이름이 보이는 가로 버튼,
--   폰은 작은 네모. 자리: 큰 버튼 칸 바로 오른쪽 (위 → 아래 맞춤) → 왼쪽 위 가로 줄 → 오른쪽 위 (코인 줄·점프·조이스틱은 피해요).
--   꾸미기 모드 동안은 큰 버튼과 같이 숨어요.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local Hud = {}

local coinPill: Frame
local coinLabel: TextLabel
local pawPill: Frame
local pawLabel: TextLabel
local incomePill: Frame
local incomeLabel: TextLabel
local pendingPill: Frame
local pendingLabel: TextLabel
local rebirthButton: TextButton
local rebirthPill: Frame
local rebirthPillLabel: TextLabel
local sideColumn: Frame? = nil
local sideButtons: { [string]: TextButton } = {} -- 글자(가방, 집 …) → 버튼
local badges: { [string]: Frame } = {}
local wantBadge: { [string]: boolean } = {} -- Init 전에 부르면 기억해 뒀다가 붙여요
local lastPending = -1
local lastIncome = -1
local lastCanRebirth: boolean? = nil

local coinValue = Instance.new("NumberValue")
local targetCoins = -1
local lastPets = -1

-- 켜고 끄는 버튼 (Config.Settings 키)
type ToggleDef = { Key: string, Emoji: string, Caption: string, Color: Color3, OnText: string, OffText: string }
local TOGGLES: { ToggleDef } = {
	{
		Key = "HideHatch",
		Emoji = "🙈",
		Caption = "부화 숨기기",
		Color = C.Lavender,
		OnText = "🙈 부화 화면을 숨겨요! 작은 알림만 떠요",
		OffText = "🐣 부화 화면을 다시 보여 줘요!",
	},
	{
		Key = "AutoCollect",
		Emoji = "🏦",
		Caption = "자동 수금",
		Color = C.Orange,
		OnText = "🏦 자동 수금 켜짐! 집 금고 코인이 저절로 들어와요",
		OffText = "🏦 자동 수금 꺼짐! 집의 금색 판을 밟으면 받아요",
	},
	{
		Key = "Magnet",
		Emoji = "🧲",
		Caption = "자석",
		Color = C.Sky,
		OnText = "🧲 자석 켜짐! 주변 코인이 저절로 끌려와요",
		OffText = "🧲 자석 꺼짐!",
	},
}
local OFF_FACE = Color3.fromRGB(190, 190, 206)
local OFF_TRACK = Color3.fromRGB(125, 125, 145)

type Toggle = {
	Def: ToggleDef,
	Button: TextButton,
	Icon: TextLabel,
	Caption: TextLabel,
	Track: Frame,
	Knob: Frame,
	StateLabel: TextLabel,
	Stroke: UIStroke,
	KnobOff: number, -- 스위치 동그라미 가운데 (트랙 안 비율)
	KnobOn: number,
	Shown: boolean?,
	LastTap: number,
}
local toggleFrame: Frame? = nil
local toggles: { Toggle } = {}
local toggleByKey: { [string]: Toggle } = {}
local topBarFrame: Frame? = nil
local subRowFrame: Frame? = nil

export type Actions = {
	ToggleBag: () -> (),
	ToggleIndex: () -> (),
	ToggleHouse: () -> (),
	ToggleRebirth: () -> (),
	ToggleShop: (() -> ())?,
	ToggleMap: (() -> ())?,
	ToggleLeaderboard: (() -> ())?,
}

-- 키보드가 있는 PC 에서만 버튼 구석에 단축키 글자를 보여 줘요
local showKeys = UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled

-- 큰 네모 버튼 (이모지 + 아래 글자 + 단축키)
local function bigButton(parent: Instance, emoji: string, caption: string, key: string, color: Color3, order: number, onClick: () -> ())
	local btn, emojiLabel = UiKit.Button({
		Name = caption,
		Text = emoji,
		Color = color,
		LayoutOrder = order,
		Radius = UDim.new(0.3, 0),
		TextSize = 60,
		Parent = parent,
		OnClick = onClick,
	})
	emojiLabel.Position = UDim2.fromScale(0.5, 0.38)
	emojiLabel.Size = UDim2.fromScale(0.7, 0.5)
	local cap = UiKit.Label({
		Name = "Caption",
		Text = caption,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.79),
		Size = UDim2.fromScale(0.94, 0.27),
		ZIndex = 2,
		Parent = btn,
	}, { Stroke = UiKit.Darken(color, 0.45), MaxText = 22 })
	if showKeys then
		local keyPill: Frame = Make("Frame", {
			Name = "Key",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.12, 0.12),
			Size = UDim2.fromScale(0.3, 0.3),
			BackgroundColor3 = C.White,
			ZIndex = 3,
			Parent = btn,
		})
		UiKit.Corner(keyPill, UDim.new(0.5, 0))
		UiKit.Stroke(keyPill, UiKit.Darken(color, 0.3), 2, true)
		UiKit.Label({
			Text = key,
			TextColor3 = UiKit.Darken(color, 0.45),
			Size = UDim2.fromScale(0.8, 0.8),
			Position = UDim2.fromScale(0.1, 0.1),
			ZIndex = 4,
			Parent = keyPill,
		}, { Stroke = C.White, StrokeThickness = 1, MaxText = 16 })
	end
	return btn, emojiLabel, cap
end

-- 작은 알약 (코인 아래 줄: 초당 수익 / 금고)
local function smallPill(parent: Instance, name: string, color: Color3, order: number, width: number): (Frame, TextLabel)
	local pill: Frame = Make("Frame", {
		Name = name,
		Size = UDim2.fromScale(width, 1),
		BackgroundColor3 = color,
		LayoutOrder = order,
		Parent = parent,
	})
	UiKit.Corner(pill, UDim.new(0.5, 0))
	UiKit.Gradient(pill)
	UiKit.Stroke(pill, C.White, 2, true)
	local label = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.78),
		Parent = pill,
	}, { Stroke = UiKit.Darken(color, 0.5), MaxText = 22 })
	return pill, label
end

local function updatePending()
	local plot = State.Plot
	local collector = plot and plot:FindFirstChild("Collector")
	local pending = 0
	if collector then
		pending = tonumber(collector:GetAttribute("Pending")) or 0
	elseif State.Snapshot then
		pending = tonumber(State.Snapshot.Pending) or 0
	end
	pending = math.floor(pending)
	if State.GetSetting("AutoCollect") then
		pending = 0 -- 자동 수금 중에는 금고 알약이 깜빡이지 않게 숨겨요
	end
	if pending == lastPending then
		return
	end
	if pending > 0 then
		pendingLabel.Text = "🏦 집 금고 +" .. Config.FormatNumber(pending)
		if not pendingPill.Visible then
			pendingPill.Visible = true
			UiKit.Pop(pendingPill)
		end
	else
		pendingPill.Visible = false
	end
	lastPending = pending
end

-- 환생 비용 알약 (살 수 있으면 민트색으로)
local function refreshRebirth()
	local snap = State.Snapshot
	if not snap or not rebirthPill then
		return
	end
	local rebirths = snap.Rebirths
	local cost = snap.RebirthCost
	local maxed = rebirths >= Config.Rebirth.MaxRebirths
	local can = not maxed and snap.Coins >= cost
	rebirthPillLabel.Text = if maxed then "최대 ✅" else "💰 " .. Config.FormatNumber(cost)
	rebirthPill.BackgroundColor3 = if can then C.Mint else C.Grey
	if can and lastCanRebirth == false then
		UiKit.Pop(rebirthPill, 0.4)
		UiKit.Bump(rebirthButton, 0.15)
	end
	lastCanRebirth = can
end

----------------------------------------------------------------------
-- 켜고 끄는 버튼 (🙈 / 🏦 / 🧲)
----------------------------------------------------------------------
local function strokeOf(label: TextLabel): UIStroke?
	return label:FindFirstChildOfClass("UIStroke")
end

-- 켜짐/꺼짐 모양 (animate = 누른 직후면 통통 + 스위치가 미끄러져요)
local function paintToggle(t: Toggle, on: boolean, animate: boolean)
	local face = if on then t.Def.Color else OFF_FACE
	t.Shown = on
	t.Button.BackgroundColor3 = face
	t.Stroke.Thickness = if on then 3 else 2
	t.Icon.TextTransparency = if on then 0 else 0.35
	t.Caption.TextTransparency = if on then 0 else 0.15
	local capStroke = strokeOf(t.Caption)
	if capStroke then
		capStroke.Color = UiKit.Darken(face, 0.5)
	end
	t.Track.BackgroundColor3 = if on then C.Mint else OFF_TRACK
	t.StateLabel.Text = if on then "ON" else "OFF"
	t.StateLabel.Position = UDim2.fromScale(if on then 0.38 else 0.62, 0.5)
	local stateStroke = strokeOf(t.StateLabel)
	if stateStroke then
		stateStroke.Color = UiKit.Darken(if on then C.Mint else OFF_TRACK, 0.5)
	end
	local goal = UDim2.fromScale(if on then t.KnobOn else t.KnobOff, 0.5)
	if animate then
		UiKit.Tween(t.Knob, 0.18, { Position = goal }, Enum.EasingStyle.Back)
		UiKit.Bump(t.Button, if on then 0.14 else -0.08)
	else
		t.Knob.Position = goal
	end
end

local function onToggleTap(t: Toggle)
	local now = os.clock()
	if now - t.LastTap < 0.2 then
		return -- 아주 빠른 연타는 한 번으로
	end
	t.LastTap = now
	local key = t.Def.Key
	local value = not State.GetSetting(key)
	State.SetSettingLocal(key, value) -- 바로 바꿔 보여 줘요 (OnSetting → paintToggle)
	Remotes.SetSetting:FireServer(key, value)
	UiKit.PlaySound("Click")
	Toasts.Show(if value then t.Def.OnText else t.Def.OffText, if value then "good" else "info")
end

local function makeToggle(parent: Instance, def: ToggleDef, order: number): Toggle
	local btn: TextButton = Make("TextButton", {
		Name = def.Key,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = OFF_FACE,
		LayoutOrder = order,
		Selectable = true,
		Parent = parent,
	})
	UiKit.Corner(btn, UDim.new(0.28, 0))
	UiKit.Gradient(btn)
	local stroke = UiKit.Stroke(btn, C.White, 2, true)
	local icon = UiKit.Label({
		Name = "Icon",
		Text = def.Emoji,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 2,
		Parent = btn,
	}, { MaxText = 40 })
	local caption = UiKit.Label({
		Name = "Caption",
		Text = def.Caption,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 2,
		Parent = btn,
	}, { MaxText = 24, StrokeThickness = 2 })
	local track: Frame = Make("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = OFF_TRACK,
		ZIndex = 2,
		Parent = btn,
	})
	UiKit.Corner(track, UDim.new(0.5, 0))
	UiKit.Stroke(track, C.White, 1.5, true)
	local stateLabel = UiKit.Label({
		Name = "State",
		Text = "OFF",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.86),
		ZIndex = 3,
		Parent = track,
	}, { MaxText = 16, StrokeThickness = 1.5 })
	local knob: Frame = Make("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		BackgroundColor3 = C.White,
		ZIndex = 4,
		Parent = track,
	})
	Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = knob })
	UiKit.Corner(knob, UDim.new(0.5, 0))
	local t: Toggle = {
		Def = def,
		Button = btn,
		Icon = icon,
		Caption = caption,
		Track = track,
		Knob = knob,
		StateLabel = stateLabel,
		Stroke = stroke,
		KnobOff = 0.2,
		KnobOn = 0.8,
		Shown = nil,
		LastTap = 0,
	}
	-- 누르는 느낌 (UiKit.Button 과 같게)
	local scale = UiKit.Scale(btn)
	btn.MouseButton1Down:Connect(function()
		UiKit.Tween(scale, 0.08, { Scale = 0.9 })
	end)
	btn.MouseButton1Up:Connect(function()
		UiKit.Tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	btn.MouseLeave:Connect(function()
		UiKit.Tween(scale, 0.15, { Scale = 1 })
	end)
	btn.Activated:Connect(function()
		onToggleTap(t)
	end)
	return t
end

-- 버튼 안 배치. chip (큰 화면): [이모지 | 이름 / 스위치] 가로로 길게, 아니면 네모 [이모지 / 스위치]
local function styleToggle(t: Toggle, w: number, h: number, chip: boolean)
	t.Button.Size = UDim2.fromOffset(w, h)
	t.Caption.Visible = chip
	local tw, th
	if chip then
		t.Icon.Position = UDim2.fromOffset(math.floor(h * 0.5) + 2, math.floor(h * 0.5))
		t.Icon.Size = UDim2.fromOffset(math.floor(h * 0.74), math.floor(h * 0.74))
		t.Caption.AnchorPoint = Vector2.new(0, 0)
		t.Caption.TextXAlignment = Enum.TextXAlignment.Left
		t.Caption.Position = UDim2.fromOffset(math.floor(h * 0.98), math.floor(h * 0.1))
		t.Caption.Size = UDim2.fromOffset(w - math.floor(h * 0.98) - 8, math.floor(h * 0.42))
		tw, th = math.floor(h * 1.2), math.floor(h * 0.34)
		t.Track.AnchorPoint = Vector2.new(0, 0)
		t.Track.Position = UDim2.fromOffset(math.floor(h * 0.98), math.floor(h * 0.57))
	else
		t.Icon.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.36))
		t.Icon.Size = UDim2.fromOffset(math.floor(w * 0.68), math.floor(h * 0.52))
		tw, th = math.floor(w * 0.84), math.floor(h * 0.3)
		t.Track.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Track.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.8))
	end
	t.Track.Size = UDim2.fromOffset(tw, th)
	-- 동그라미 가운데: 반지름 + 조금 여백 (트랙 너비 비율)
	local edge = math.clamp((th * 0.78 / 2 + th * 0.12) / math.max(tw, 1), 0.1, 0.45)
	t.KnobOff, t.KnobOn = edge, 1 - edge
	paintToggle(t, t.Shown == true, false)
end

-- 버튼 3개 자리: 큰 버튼 칸 오른쪽 위에 세로로 (안 되면 왼쪽 위 가로 → 큰 버튼 칸 오른쪽 아래 → 오른쪽 위)
-- 위 코인 줄(+초당/금고 알약 줄), 큰 버튼 칸(+환생 알약), 폰 점프 버튼·조이스틱 자리는 피해요
local function layoutToggles(gui: ScreenGui, column: Frame, cell: number, gap: number)
	local frame = toggleFrame
	if not frame then
		return
	end
	local size = gui.AbsoluteSize
	local gw, gh = size.X, size.Y
	local n = #toggles
	-- 큰 버튼이 크면 (PC·태블릿) 이름이 보이는 가로 버튼, 아니면 (폰) 작은 네모
	local chip = cell >= 70 and gw >= 700
	local bh = if chip then math.clamp(math.floor(cell * 0.56), 44, 54) else math.clamp(math.floor(cell * 0.62), 42, 58)
	local bw = if chip then math.floor(bh * 3.3) else bh
	local tgap = math.max(5, math.floor(bh * 0.12))
	local long = n * bh + (n - 1) * tgap -- 세로로 세울 때 높이
	local wide = n * bw + (n - 1) * tgap -- 가로로 놓을 때 너비

	local avoid: { UiKit.Rect } = {}
	local top, sub = topBarFrame, subRowFrame
	if top then
		table.insert(avoid, UiKit.RectOf(top, 2))
	end
	if sub then
		table.insert(avoid, UiKit.RectOf(sub, 2)) -- 금고 알약이 보이든 안 보이든 그 줄 전체 (버튼이 왔다 갔다 하지 않게)
	end
	-- 큰 버튼 칸은 방금 정한 Position/Size 로 바로 계산 (AbsolutePosition 은 아직 안 바뀌었을 수도 있어요). 기준점 (0, 0.5)
	local colPos, colSize = column.Position, column.Size
	local sx0, sy0 = colPos.X.Offset, colPos.Y.Offset - colSize.Y.Offset / 2
	local side: UiKit.Rect = { X0 = sx0, Y0 = sy0, X1 = sx0 + colSize.X.Offset, Y1 = sy0 + colSize.Y.Offset }
	table.insert(avoid, { X0 = side.X0 - 4, Y0 = side.Y0 - 4, X1 = side.X1 + 4, Y1 = side.Y1 + 4 })
	if rebirthPill and rebirthButton then
		-- 환생 알약: 환생 버튼(마지막 칸) 오른쪽
		local cols = math.max(1, math.floor((colSize.X.Offset + gap) / (cell + gap) + 0.5))
		local idx = rebirthButton.LayoutOrder - 1
		local cx = side.X0 + (idx % cols) * (cell + gap)
		local cy = side.Y0 + math.floor(idx / cols) * (cell + gap)
		local px = cx + cell + 8
		table.insert(avoid, { X0 = px - 4, Y0 = cy + cell * 0.29 - 4, X1 = px + cell * 1.5 + 4, Y1 = cy + cell * 0.71 + 4 })
	end
	if UserInputService.TouchEnabled then
		if math.min(gw, gh) <= 500 then
			table.insert(avoid, { X0 = gw - 105, Y0 = gh - 100, X1 = gw, Y1 = gh })
		else
			table.insert(avoid, { X0 = gw - 180, Y0 = gh - 220, X1 = gw - 40, Y1 = gh - 80 })
		end
		-- 조이스틱: 왼쪽 아래 (큰 버튼 칸과 같은 아래 여백 120)
		table.insert(avoid, { X0 = 0, Y0 = gh - 120, X1 = gw * 0.4, Y1 = gh })
	end

	type Spot = { X: number, Y: number, Vertical: boolean }
	local spots: { Spot } = {
		{ X = side.X1 + tgap, Y = math.max(8, side.Y0), Vertical = true },
		{ X = 10, Y = 8, Vertical = false },
		{ X = side.X1 + tgap, Y = side.Y1 - long, Vertical = true },
		{ X = gw - 10 - bw, Y = 8, Vertical = true },
	}
	local best: Spot? = nil
	local bestOv = math.huge
	for _, spot in spots do
		local w = if spot.Vertical then bw else wide
		local h = if spot.Vertical then long else bh
		local r: UiKit.Rect = { X0 = spot.X, Y0 = spot.Y, X1 = spot.X + w, Y1 = spot.Y + h }
		local ov = UiKit.OverlapArea(r, avoid)
		if r.X0 < 0 or r.Y0 < 0 or r.X1 > gw or r.Y1 > gh then
			ov += w * h -- 화면 밖
		end
		if ov < bestOv then
			best, bestOv = spot, ov
			if ov == 0 then
				break
			end
		end
	end
	local spot = best :: Spot
	frame.Position = UDim2.fromOffset(math.floor(spot.X), math.floor(spot.Y))
	frame.Size = if spot.Vertical then UDim2.fromOffset(bw, long) else UDim2.fromOffset(wide, bh)
	local list = frame:FindFirstChildOfClass("UIListLayout")
	if list then
		list.FillDirection = if spot.Vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
		list.Padding = UDim.new(0, tgap)
	end
	for _, tg in toggles do
		styleToggle(tg, bw, bh, chip)
	end
end

function Hud.Init(gui: ScreenGui, actions: Actions)
	------------------------------------------------------------------
	-- 위쪽 가운데: 코인 + 펫 수
	------------------------------------------------------------------
	local top: Frame = Make("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromScale(0.42, 0.085),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Make("UISizeConstraint", { MinSize = Vector2.new(250, 48), MaxSize = Vector2.new(440, 70), Parent = top })
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0.03, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = top,
	})

	coinPill = Make("Frame", {
		Name = "Coins",
		Size = UDim2.fromScale(0.64, 1),
		BackgroundColor3 = C.Lemon,
		LayoutOrder = 1,
		Parent = top,
	})
	UiKit.Corner(coinPill, UDim.new(0.5, 0))
	UiKit.Gradient(coinPill)
	UiKit.Stroke(coinPill, C.White, 4, true)
	local coinIcon: Frame = Make("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, 0),
		Size = UDim2.fromScale(0.3, 0.84),
		BackgroundColor3 = C.Gold,
		Parent = coinPill,
	})
	Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = coinIcon })
	UiKit.Corner(coinIcon, UDim.new(0.5, 0))
	UiKit.Stroke(coinIcon, C.White, 3, true)
	UiKit.Label({ Text = "💰", Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Parent = coinIcon }, { MaxText = 40 })
	coinLabel = UiKit.Label({
		Name = "Amount",
		Text = "0",
		Position = UDim2.fromScale(0.3, 0.12),
		Size = UDim2.fromScale(0.64, 0.76),
		Parent = coinPill,
	}, { Stroke = UiKit.Darken(C.Lemon, 0.5), StrokeThickness = 3, MaxText = 44 })

	pawPill = Make("Frame", {
		Name = "Pets",
		Size = UDim2.fromScale(0.3, 0.82),
		BackgroundColor3 = C.Pink,
		LayoutOrder = 2,
		Parent = top,
	})
	UiKit.Corner(pawPill, UDim.new(0.5, 0))
	UiKit.Gradient(pawPill)
	UiKit.Stroke(pawPill, C.White, 3, true)
	pawLabel = UiKit.Label({
		Text = "🐾 0",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.84, 0.72),
		Parent = pawPill,
	}, { Stroke = UiKit.Darken(C.Pink, 0.45), MaxText = 32 })

	-- 코인 줄 아래: 초당 수익(항상) + 집 금고에 쌓인 코인(있을 때만).
	-- 코인 줄(코인 + 펫 수) 전체의 가운데 아래에 둬요 (왼쪽 큰 버튼 옆 켜고 끄는 버튼 자리를 비워요).
	-- 코인 알약 기준 좌표: 줄 왼쪽 여백 0.015 + 코인 알약 0.64 → 줄 가운데 = (0.5 - 0.015) / 0.64
	local subRow: Frame = Make("Frame", {
		Name = "SubRow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new((0.5 - 0.015) / 0.64, 0, 1, 4),
		Size = UDim2.fromScale(1.3, 0.54),
		BackgroundTransparency = 1,
		Parent = coinPill,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = subRow,
	})
	incomePill, incomeLabel = smallPill(subRow, "Income", C.Mint, 1, 0.44)
	incomeLabel.Text = "💰 +0/초"
	pendingPill, pendingLabel = smallPill(subRow, "Pending", C.Orange, 2, 0.5)
	pendingPill.Visible = false
	topBarFrame = top
	subRowFrame = subRow

	coinValue.Changed:Connect(function(v: number)
		coinLabel.Text = Config.FormatNumber(v)
	end)

	------------------------------------------------------------------
	-- 왼쪽: 큰 버튼 7개 (화면 높이에 맞게 1~3열)
	------------------------------------------------------------------
	local column: Frame = Make("Frame", {
		Name = "SideButtons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.46, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	sideColumn = column
	local GAP = 8
	local grid: UIGridLayout = Make("UIGridLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		CellPadding = UDim2.fromOffset(GAP, GAP),
		Parent = column,
	})

	local function noop() end
	local defs: { { Emoji: string, Caption: string, Key: string, Color: Color3, Fn: () -> () } } = {
		{ Emoji = "🎒", Caption = "가방", Key = "B", Color = C.Pink, Fn = actions.ToggleBag },
		{ Emoji = "📖", Caption = "도감", Key = "N", Color = C.Sky, Fn = actions.ToggleIndex },
		{ Emoji = "🏠", Caption = "집", Key = "H", Color = C.Peach, Fn = actions.ToggleHouse },
		{ Emoji = "🛍", Caption = "상점", Key = "P", Color = C.Mint, Fn = actions.ToggleShop or noop },
		{ Emoji = "🗺", Caption = "지도", Key = "M", Color = Color3.fromRGB(110, 195, 120), Fn = actions.ToggleMap or noop },
		{ Emoji = "🏆", Caption = "순위", Key = "L", Color = C.Gold, Fn = actions.ToggleLeaderboard or noop },
		{ Emoji = "🔄", Caption = "환생", Key = "R", Color = C.Lavender, Fn = actions.ToggleRebirth },
	}
	for i, def in defs do
		local btn = bigButton(column, def.Emoji, def.Caption, def.Key, def.Color, i, def.Fn)
		sideButtons[def.Caption] = btn
		if def.Caption == "환생" then
			rebirthButton = btn
		end
	end
	local count = #defs

	-- 켜고 끄는 버튼 3개 (자리는 layout 이 정해요)
	local toggleBox: Frame = Make("Frame", {
		Name = "Toggles",
		BackgroundTransparency = 1,
		Parent = gui,
	})
	toggleFrame = toggleBox
	Make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = toggleBox,
	})
	for i, def in TOGGLES do
		local t = makeToggle(toggleBox, def, i)
		table.insert(toggles, t)
		toggleByKey[def.Key] = t
		paintToggle(t, State.GetSetting(def.Key), false)
	end
	State.OnSetting(function(key: string, value: boolean)
		local t = toggleByKey[key]
		if t and t.Shown ~= value then
			paintToggle(t, value, true)
		end
		if key == "AutoCollect" then
			lastPending = -1
			updatePending()
		end
	end)

	-- 환생 비용 (버튼 오른쪽 작은 알약)
	rebirthPill = Make("Frame", {
		Name = "RebirthCost",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 8, 0.5, 0),
		Size = UDim2.new(1.5, 0, 0.42, 0),
		BackgroundColor3 = C.Grey,
		ZIndex = 3,
		Parent = rebirthButton,
	})
	UiKit.Corner(rebirthPill, UDim.new(0.5, 0))
	UiKit.Stroke(rebirthPill, C.White, 3, true)
	rebirthPillLabel = UiKit.Label({
		Text = "💰 ?",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.7),
		ZIndex = 4,
		Parent = rebirthPill,
	}, { MaxText = 22 })

	-- 화면 크기에 맞게: 한 줄로 세울 수 있으면 1열, 아니면 2열(폰), 그래도 안 되면 3열
	local touch = UserInputService.TouchEnabled
	local function layout()
		local size = gui.AbsoluteSize
		local w, h = size.X, size.Y
		if h <= 0 then
			return
		end
		-- 좁은 화면(세로 폰)에서는 위 코인 줄 아래부터, 폰은 아래 조이스틱 자리를 비워요
		local topMargin = if w < 700 then 110 else 12
		local bottomMargin = if touch then 120 else 24
		local avail = math.max(120, h - topMargin - bottomMargin)
		local cols, cell = 3, 48
		for c = 1, 3 do
			local rows = math.ceil(count / c)
			local fit = math.floor((avail - (rows - 1) * GAP) / rows)
			local need = if c == 1 then 66 elseif c == 2 then 46 else 0
			if fit >= need then
				cols = c
				cell = fit
				break
			end
		end
		cell = math.clamp(cell, 44, if cols == 1 then 92 else 80)
		local rows = math.ceil(count / cols)
		local height = rows * cell + (rows - 1) * GAP
		grid.CellSize = UDim2.fromOffset(cell, cell)
		column.Size = UDim2.fromOffset(cols * cell + (cols - 1) * GAP, height)
		-- 쓸 수 있는 칸의 가운데 (위아래 여백 안)
		local centerY = topMargin + avail / 2
		column.Position = UDim2.new(0, 10, 0, math.floor(math.max(topMargin + height / 2, centerY)))
		layoutToggles(gui, column, cell, GAP)
		-- 코인 줄 크기는 한 프레임 뒤에 바뀔 수 있어서 한 번 더
		task.defer(function()
			layoutToggles(gui, column, cell, GAP)
		end)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	for caption, on in wantBadge do
		Hud.SetBadge(caption, on)
	end

	task.spawn(function()
		while true do
			updatePending()
			task.wait(0.2)
		end
	end)
end

-- 코인 / 금고 / 초당 수익 (CoinSync 와 전체 스냅샷 뒤에 State.OnCoins 로 불려요)
function Hud.SetCoins(coins: number, _pending: number, income: number)
	if not coinLabel then
		return
	end
	if targetCoins < 0 then
		coinValue.Value = coins
		coinLabel.Text = Config.FormatNumber(coins)
	elseif coins ~= targetCoins then
		if coins > targetCoins then
			-- 초당 수익처럼 조금씩 늘 때는 살짝만 통통
			UiKit.Bump(coinPill, if coins - targetCoins > math.max(1, targetCoins * 0.05) then 0.2 else 0.06)
			UiKit.Tween(coinValue, 0.6, { Value = coins })
		else
			UiKit.Bump(coinPill, -0.08)
			UiKit.Tween(coinValue, 0.35, { Value = coins })
		end
	end
	targetCoins = coins

	local shown = math.floor(income * 10 + 0.5) / 10
	incomeLabel.Text = "💰 +" .. UiKit.IncomeText(shown) .. "/초"
	if lastIncome >= 0 and shown > lastIncome then
		UiKit.Bump(incomePill, 0.2)
	end
	lastIncome = shown

	updatePending()
	refreshRebirth()
end

-- 왼쪽 큰 버튼에 빨간 "!" 알림 켜기/끄기 (caption = "가방" | "집" | …)
function Hud.SetBadge(caption: string, on: boolean)
	wantBadge[caption] = on
	local btn = sideButtons[caption]
	if not btn then
		return
	end
	local badge = badges[caption]
	if not badge then
		if not on then
			return
		end
		badge = UiKit.Badge(btn)
		badges[caption] = badge
	end
	if on and not badge.Visible then
		UiKit.Bump(btn, 0.15)
	end
	UiKit.ShowBadge(badge, on)
end

-- 알림이 켜져 있나 (검사용)
function Hud.HasBadge(caption: string): boolean
	local badge = badges[caption]
	return badge ~= nil and badge.Visible
end

-- 왼쪽 큰 버튼들 보이기/숨기기 (꾸미기 모드 동안 숨겨요)
function Hud.SetSideVisible(visible: boolean)
	local box = toggleFrame
	if box then
		box.Visible = visible -- 켜고 끄는 버튼도 같이
	end
	local column = sideColumn
	if not column or column.Visible == visible then
		return
	end
	column.Visible = visible
	if visible then
		UiKit.Pop(column, 0.3)
		if box then
			UiKit.Pop(box, 0.3)
		end
	end
end

-- 켜고 끄는 버튼 (검사용): key → 버튼
function Hud.ToggleButton(key: string): TextButton?
	local t = toggleByKey[key]
	return if t then t.Button else nil
end

-- 전체 스냅샷: 펫 수, 환생 버튼 (코인은 SetCoins 가 해요)
function Hud.Update(snap: State.Snapshot)
	local pets = 0
	for _, item in snap.Items do
		if type(item) == "table" and item.Kind == "Pet" then
			pets += 1
		end
	end
	pawLabel.Text = "🐾 " .. tostring(pets)
	if lastPets >= 0 and pets > lastPets then
		UiKit.Bump(pawPill, 0.25)
	end
	lastPets = pets
	refreshRebirth()
end

return Hud
