-- 화면 고정 UI: 코인(CoinSync 로 바로바로), 초당 수익, 집 금고, 펫 수, 왼쪽 큰 버튼 7개
-- (가방 B / 도감 N / 집 H / 상점 P / 지도 M / 순위 L / 환생 R). 화면이 낮으면 2~3열로 접혀요.
-- Hud.SetBadge("집", true): 버튼 오른쪽 위에 빨간 "!" (새 집을 살 수 있을 때 init.client 가 켜요)
-- 켜고 끄는 버튼 3개 (🏦 자동 수금 / 🧲 자석 / ⚡ 슈퍼 자석): 한 번 누르면 바로 켜짐/꺼짐
--   (색 + ON/OFF 스위치), 서버로 Remotes.SetSetting, 스냅샷 Settings 를 따라가요 (State.GetSetting). PC·태블릿은 이름이 보이는
--   가로 버튼, 폰은 작은 네모. 자리: 큰 버튼 칸 바로 오른쪽 세로 (위 → 아래 맞춤) → 왼쪽 위 가로 줄 → 왼쪽 위 2×2
--   → 큰 버튼 칸 오른쪽 2×2 → 오른쪽 위 (세로 / 2×2). 코인 줄·점프·조이스틱은 피해요. 꾸미기 모드 동안은 큰 버튼과 같이 숨어요.
--   ★v7.2 셋 다 게임 패스 (Config.Passes: 🧲 R$50 · ⚡ R$100 · 🏦 R$150, Id = 0 이면 공짜라 보통 버튼).
--   패스가 없으면 회색 "🔒 R$50", 누르면 MarketplaceService:PromptGamePassPurchase (서버가 사면 속성 Pass_<키> 를 켜요
--   → 바로 보통 버튼으로 바뀌고 통통). 켜 둔 값은 그대로 저장돼요 (패스가 생기면 바로 작동). 환생 잠금은 없어요.
-- ★v7.2 ⚙️ 옵션 버튼 (켜고 끄는 버튼 줄 마지막 칸): 누르면 ⚙️ 게임 옵션 창 (OptionsWindow: 🙈 부화 숨기기 · 🔔 알 알림).
-- ★v7 빠른 버튼 2개 (가방 밖): "🐾 하위 펫 한 개 가방으로" (★v7.2 이름, Remotes.StashEgg) · "✨ 자동 배치" (Remotes.AutoPlace).
--   폰은 작은 네모 (이모지 + 두 줄 글씨) 를 코인 줄 오른쪽 위 구석에 (알림 줄은 코인 줄 때문에 원래 거기까지 못 올라가요),
--   PC·태블릿은 이름 버튼을 켜고 끄는 버튼 아래에. 알림 줄 띠·팁 줄·점프·조이스틱은 피하고, 꾸미기 동안은 숨어요.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
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

-- 켜고 끄는 버튼 (Config.Settings 키 = ★v7.2 Config.Passes 키)
type ToggleDef = {
	Key: string,
	Emoji: string,
	Caption: string,
	Color: Color3,
	OnText: string,
	OffText: string,
	What: string, -- ★v7.2 패스가 없을 때 누르면 나오는 한 줄 설명
}
local TOGGLES: { ToggleDef } = {
	{
		Key = "AutoCollect",
		Emoji = "🏦",
		Caption = "자동 수금",
		Color = C.Orange,
		OnText = "🏦 자동 수금 켜짐! 집 금고 코인이 저절로 들어와요",
		OffText = "🏦 자동 수금 꺼짐! 집의 금색 판을 밟으면 받아요",
		What = "집 금고 코인이 저절로 들어와요",
	},
	{
		Key = "Magnet",
		Emoji = "🧲",
		Caption = "자석",
		Color = C.Sky,
		OnText = "🧲 자석 켜짐! 주변 코인이 저절로 끌려와요",
		OffText = "🧲 자석 꺼짐!",
		What = "주변 코인을 저절로 끌어와요",
	},
	{
		Key = "SuperMagnet",
		Emoji = "⚡",
		Caption = "슈퍼 자석",
		Color = C.Pink,
		OnText = "⚡ 슈퍼 자석 켜짐! 이 지역 코인이 몽땅 날아와요",
		OffText = "⚡ 슈퍼 자석 꺼짐!",
		What = "지금 있는 지역 코인을 몽땅 모아 줘요",
	},
}

-- ★v7.2 게임 패스 가격 글자 "R$50" (Config.Passes, 보여 주기만)
local function priceText(key: string): string
	local pass = (Config.Passes :: any)[key]
	return "R$" .. tostring(if pass then pass.Price else "?")
end
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
	Lock: TextLabel, -- ★v7.2 패스가 없을 때 스위치 자리에 "🔒 R$50" (네모 버튼은 "R$50")
	LockIcon: TextLabel, -- 네모 버튼 오른쪽 위 🔒
	Locked: boolean,
	Chip: boolean,
}
local toggleFrame: Frame? = nil
local toggles: { Toggle } = {}
local toggleByKey: { [string]: Toggle } = {}
local topBarFrame: Frame? = nil
local subRowFrame: Frame? = nil

-- ★v7.2 ⚙️ 옵션 버튼 (켜고 끄는 버튼 줄 마지막 칸) → OptionsWindow
type OptionsButton = {
	Button: TextButton,
	Icon: TextLabel,
	Caption: TextLabel,
	Pill: Frame,
	PillLabel: TextLabel,
	LastTap: number,
}
local optionsButton: OptionsButton? = nil
local OPTIONS_FACE = C.Lemon

-- ★v7 가방 밖 빠른 버튼 2개
type QuickDef = { Name: string, Emoji: string, Caption: string, Short: string, Color: Color3 }
-- ★v7.2 "하위 펫 한 개 가방으로": 이름 버튼은 두 줄로 (한 줄이면 글씨가 너무 작아요), 폰 네모도 두 줄 ("하위 펫 / 1개 가방")
local QUICK: { QuickDef } = {
	{ Name = "StashEgg", Emoji = "🐾", Caption = "하위 펫 한 개\n가방으로", Short = "하위 펫\n1개 가방", Color = C.Peach },
	{ Name = "AutoPlace", Emoji = "✨", Caption = "자동 배치", Short = "자동 배치", Color = C.Mint },
}
type Quick = { Def: QuickDef, Button: TextButton, Icon: TextLabel, Caption: TextLabel, LastTap: number }
local quickFrame: Frame? = nil
local quicks: { Quick } = {}

export type Actions = {
	ToggleBag: () -> (),
	ToggleIndex: () -> (),
	ToggleHouse: () -> (),
	ToggleRebirth: () -> (),
	ToggleShop: (() -> ())?,
	ToggleMap: (() -> ())?,
	ToggleLeaderboard: (() -> ())?,
	ToggleOptions: (() -> ())?, -- ★v7.2 ⚙️ 게임 옵션 창
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
	if State.GetSetting("AutoCollect") and State.HasPass("AutoCollect") then
		pending = 0 -- 자동 수금 중에는 금고 알약이 깜빡이지 않게 숨겨요 (★v7.2 패스가 있을 때만 진짜 자동 수금)
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
-- 켜고 끄는 버튼 (🏦 / 🧲 / ⚡)
----------------------------------------------------------------------
local function strokeOf(label: TextLabel): UIStroke?
	return label:FindFirstChildOfClass("UIStroke")
end

-- ★v7.2 잠긴 버튼인가 (게임 패스가 아직 없어요. Id = 0 이면 공짜라 안 잠겨요)
local function lockedNow(def: ToggleDef): boolean
	return not State.HasPass(def.Key)
end

-- 켜짐/꺼짐 모양 (animate = 누른 직후면 통통 + 스위치가 미끄러져요). 잠겼으면 회색 + 🔒 (켜져 있어도)
local function paintToggle(t: Toggle, on: boolean, animate: boolean)
	t.Shown = on
	local locked = t.Locked
	t.Track.Visible = not locked
	t.Lock.Visible = locked
	t.LockIcon.Visible = locked and not t.Chip
	if locked then
		on = false
	end
	local face = if on then t.Def.Color else OFF_FACE
	t.Button.BackgroundColor3 = face
	t.Stroke.Thickness = if on then 3 else 2
	t.Icon.TextTransparency = if on then 0 elseif locked then 0.5 else 0.35
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
	if t.Locked then
		-- ★v7.2 패스가 없어요: 설명 + 사기 창 (설정은 서버로 안 보내요. 사면 서버가 Pass_<키> 를 켜요)
		UiKit.PlaySound("Click")
		local def = t.Def
		Toasts.Show("🛒 " .. def.Emoji .. " " .. def.Caption .. " (" .. priceText(def.Key) .. "): " .. def.What, "info")
		local ok = pcall(function()
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, Config.PassId(def.Key))
		end)
		if not ok then
			UiKit.Shake(t.Button, 6, 6)
			Toasts.Show("지금은 살 수 없어요 😢 잠시 뒤에 다시 해 봐요", "warn")
		end
		return
	end
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
	-- ★v7.2 잠금 글씨 "🔒 R$50" (스위치 자리) + 네모 버튼용 작은 자물쇠
	local lock = UiKit.Label({
		Name = "Lock",
		Text = "🔒 " .. priceText(def.Key),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 3,
		Parent = btn,
	}, { Stroke = UiKit.Darken(OFF_FACE, 0.55), MaxText = 18, StrokeThickness = 1.5 })
	local lockIcon = UiKit.Label({
		Name = "LockIcon",
		Text = "🔒",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.84, 0.16),
		Size = UDim2.fromScale(0.36, 0.36),
		Visible = false,
		ZIndex = 4,
		Parent = btn,
	}, { MaxText = 20 })
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
		Lock = lock,
		LockIcon = lockIcon,
		Locked = lockedNow(def),
		Chip = false,
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
	t.Chip = chip
	if chip then
		-- 스위치 자리 (이름 아래) 에 "🔒 R$50"
		t.Lock.Text = "🔒 " .. priceText(t.Def.Key)
		t.Lock.TextXAlignment = Enum.TextXAlignment.Left
		t.Lock.AnchorPoint = Vector2.new(0, 0)
		t.Lock.Position = UDim2.fromOffset(math.floor(h * 0.98), math.floor(h * 0.52))
		t.Lock.Size = UDim2.fromOffset(w - math.floor(h * 0.98) - 8, math.floor(h * 0.4))
	else
		-- 네모: 아래 줄에 "R$50", 자물쇠는 오른쪽 위
		t.Lock.Text = priceText(t.Def.Key)
		t.Lock.TextXAlignment = Enum.TextXAlignment.Center
		t.Lock.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Lock.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.8))
		t.Lock.Size = UDim2.fromOffset(math.floor(w * 0.94), math.floor(h * 0.32))
	end
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

----------------------------------------------------------------------
-- ★v7.2 ⚙️ 옵션 버튼 (켜고 끄는 버튼 줄 마지막 칸, 누르면 ⚙️ 게임 옵션 창)
----------------------------------------------------------------------
local function makeOptionsButton(parent: Instance, onTap: () -> ()): OptionsButton
	local btn, icon = UiKit.Button({
		Name = "Options",
		Text = "⚙️",
		Color = OPTIONS_FACE,
		Radius = UDim.new(0.28, 0),
		TextSize = 40,
		Parent = parent,
		OnClick = onTap,
	})
	icon.Name = "Icon"
	local caption = UiKit.Label({
		Name = "Caption",
		Text = "게임 옵션",
		ZIndex = 2,
		Parent = btn,
	}, { Stroke = UiKit.Darken(OPTIONS_FACE, 0.5), MaxText = 24, StrokeThickness = 2 })
	-- 안에 뭐가 있는지 작은 알약으로 (🙈 부화 숨기기 · 🔔 알 알림)
	local pill: Frame = Make("Frame", {
		Name = "Inside",
		BackgroundColor3 = C.White,
		ZIndex = 2,
		Parent = btn,
	})
	UiKit.Corner(pill, UDim.new(0.5, 0))
	UiKit.Stroke(pill, UiKit.Darken(OPTIONS_FACE, 0.25), 1.5, true)
	local pillLabel = UiKit.Label({
		Name = "Emojis",
		Text = "🙈 🔔",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.86),
		ZIndex = 3,
		Parent = pill,
	}, { MaxText = 16, StrokeThickness = 0 })
	return { Button = btn, Icon = icon, Caption = caption, Pill = pill, PillLabel = pillLabel, LastTap = 0 }
end

-- 켜고 끄는 버튼과 같은 모양: chip = [⚙️ | 게임 옵션 / 🙈 🔔], 네모 = [⚙️ / 옵션]
local function styleOptions(o: OptionsButton, w: number, h: number, chip: boolean)
	o.Button.Size = UDim2.fromOffset(w, h)
	o.Icon.AnchorPoint = Vector2.new(0.5, 0.5)
	o.Pill.Visible = chip
	local cap = o.Caption
	if chip then
		local left = math.floor(h * 0.98)
		o.Icon.Position = UDim2.fromOffset(math.floor(h * 0.5) + 2, math.floor(h * 0.5))
		o.Icon.Size = UDim2.fromOffset(math.floor(h * 0.74), math.floor(h * 0.74))
		cap.Text = "게임 옵션"
		cap.TextXAlignment = Enum.TextXAlignment.Left
		cap.AnchorPoint = Vector2.new(0, 0)
		cap.Position = UDim2.fromOffset(left, math.floor(h * 0.1))
		cap.Size = UDim2.fromOffset(w - left - 8, math.floor(h * 0.42))
		o.Pill.AnchorPoint = Vector2.new(0, 0)
		o.Pill.Position = UDim2.fromOffset(left, math.floor(h * 0.57))
		o.Pill.Size = UDim2.fromOffset(math.min(w - left - 8, math.floor(h * 1.2)), math.floor(h * 0.34))
	else
		o.Icon.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.36))
		o.Icon.Size = UDim2.fromOffset(math.floor(w * 0.68), math.floor(h * 0.52))
		cap.Text = "옵션"
		cap.TextXAlignment = Enum.TextXAlignment.Center
		cap.AnchorPoint = Vector2.new(0.5, 0.5)
		cap.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.8))
		cap.Size = UDim2.fromOffset(math.floor(w * 0.92), math.floor(h * 0.3))
	end
end

----------------------------------------------------------------------
-- ★v7 가방 밖 빠른 버튼 (🐾 하위 펫 한 개 가방으로 / ✨ 자동 배치)
----------------------------------------------------------------------
local function onQuickTap(q: Quick)
	local now = os.clock()
	if now - q.LastTap < 0.6 then
		return -- 연타는 한 번으로 (서버도 막아요)
	end
	q.LastTap = now
	if q.Def.Name == "StashEgg" then
		Remotes.StashEgg:FireServer()
	else
		Remotes.AutoPlace:FireServer()
	end
end

local function makeQuick(parent: Instance, def: QuickDef): Quick
	local q: Quick
	local btn, icon = UiKit.Button({
		Name = def.Name,
		Text = def.Emoji,
		Color = def.Color,
		Radius = UDim.new(0.28, 0),
		TextSize = 40,
		Parent = parent,
		OnClick = function()
			onQuickTap(q)
		end,
	})
	icon.Name = "Icon"
	local caption = UiKit.Label({
		Name = "Caption",
		Text = def.Caption,
		ZIndex = 2,
		Parent = btn,
	}, { Stroke = UiKit.Darken(def.Color, 0.5), MaxText = 22, StrokeThickness = 2 })
	q = { Def = def, Button = btn, Icon = icon, Caption = caption, LastTap = 0 }
	return q
end

-- chip (PC·태블릿) = [이모지 | 하위 펫 한 개 / 가방으로], 네모 (폰) = [이모지 / 하위 펫 / 1개 가방].
-- ★v7.2 글씨에 줄바꿈이 있으면 두 줄 자리 (네모는 이모지를 조금 작게 위로)
local function styleQuick(q: Quick, w: number, h: number, chip: boolean)
	q.Button.Size = UDim2.fromOffset(w, h)
	local icon, cap = q.Icon, q.Caption
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	local text = if chip then q.Def.Caption else q.Def.Short
	local twoLines = string.find(text, "\n", 1, true) ~= nil
	cap.Text = text
	if chip then
		local left = math.floor(h * 0.98)
		icon.Position = UDim2.fromOffset(math.floor(h * 0.5) + 2, math.floor(h * 0.5))
		icon.Size = UDim2.fromOffset(math.floor(h * 0.72), math.floor(h * 0.72))
		cap.TextXAlignment = Enum.TextXAlignment.Left
		cap.AnchorPoint = Vector2.new(0, 0.5)
		cap.Position = UDim2.fromOffset(left, math.floor(h * 0.5))
		cap.Size = UDim2.fromOffset(w - left - 8, math.floor(h * (if twoLines then 0.84 else 0.5)))
	elseif twoLines then
		icon.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.25))
		icon.Size = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.38))
		cap.TextXAlignment = Enum.TextXAlignment.Center
		cap.AnchorPoint = Vector2.new(0.5, 0.5)
		cap.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.71))
		cap.Size = UDim2.fromOffset(math.floor(w * 0.96), math.floor(h * 0.52))
	else
		icon.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.36))
		icon.Size = UDim2.fromOffset(math.floor(w * 0.62), math.floor(h * 0.5))
		cap.TextXAlignment = Enum.TextXAlignment.Center
		cap.AnchorPoint = Vector2.new(0.5, 0.5)
		cap.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.8))
		cap.Size = UDim2.fromOffset(math.floor(w * 0.96), math.floor(h * 0.3))
	end
end

-- 빠른 버튼 2개 자리. 폰 (네모): 코인 줄 오른쪽 위 구석 (알림 줄은 코인 줄에 막혀 원래 거기까지 못 올라가요.
-- 아주 낮은 폰 화면에선 부화 칸이 구석 대신 조금 왼쪽에 떠요) → 켜고 끄는 버튼 아래 → 그 오른쪽 → 코인 줄 아래 가운데.
-- (켜고 끄는 버튼 옆·코인 줄 아래는 캐릭터를 가려서 나중에). PC·태블릿 (이름 버튼): 켜고 끄는 버튼 아래 세로 → 오른쪽 위 → 코인 줄 아래.
-- 켜고 끄는 버튼 자리에서 피한 것 + 그 버튼 줄 + 오른쪽 알림 줄 띠 (Toasts 와 같은 너비) + 아래 팁 줄 자리를 피해요
local function layoutQuick(gui: ScreenGui, avoid: { UiKit.Rect }, box: UiKit.Rect, chip: boolean, bw: number, bh: number, tgap: number)
	local frame = quickFrame
	local n = #quicks
	if not frame or n == 0 then
		return
	end
	local size = gui.AbsoluteSize
	local gw, gh = size.X, size.Y
	local w = if chip then bw else math.clamp(bh + 6, 46, 56)
	local h = if chip then bh else w
	local gap = tgap + 1
	local hud = table.clone(avoid)
	table.insert(hud, { X0 = box.X0 - 4, Y0 = box.Y0 - 4, X1 = box.X1 + 4, Y1 = box.Y1 + 4 })
	local list = table.clone(hud)
	local small = gh < 500
	local stripW = if small then math.clamp(math.floor(gw * 0.31), 224, 270) else math.clamp(math.floor(gw * 0.19), 300, 360)
	local m = if small then 10 else 16
	local stripX0 = gw - m - stripW - 8
	local stripTop = 0 -- 알림 줄이 올라갈 수 있는 맨 위 (코인 줄에 막히면 그 아래)
	local top = topBarFrame
	local topY = 6
	if top then
		local tr = UiKit.RectOf(top, 4)
		topY = tr.Y0 + 4
		if tr.X1 > stripX0 then
			stripTop = tr.Y1
		end
	end
	table.insert(list, { X0 = stripX0, Y0 = stripTop, X1 = gw, Y1 = gh })
	local tipW = math.clamp(gw * 0.46, 260, 580)
	table.insert(list, { X0 = (gw - tipW) / 2 - 4, Y0 = gh - 64, X1 = (gw + tipW) / 2 + 4, Y1 = gh })

	local function shape(cols: number): (number, number)
		local rows = math.ceil(n / cols)
		return cols * w + (cols - 1) * gap, rows * h + (rows - 1) * gap
	end
	local rowW = shape(n)
	local subY = topY + 60
	local sub = subRowFrame
	if sub then
		subY = sub.AbsolutePosition.Y + sub.AbsoluteSize.Y
	end
	type Spot = { X: number, Y: number, Cols: number }
	local below: Spot = { X = box.X0, Y = box.Y1 + gap + 3, Cols = if chip then 1 else n }
	local corner: Spot = { X = gw - m - rowW, Y = topY, Cols = n }
	local under: Spot = { X = math.floor((gw - rowW) / 2), Y = subY + 8, Cols = n }
	local beside: Spot = { X = box.X1 + gap + 3, Y = box.Y0, Cols = 1 }
	local belowCol: Spot = { X = box.X1 - w, Y = box.Y1 + gap + 3, Cols = 1 }
	local leftCol: Spot = { X = box.X0 - gap - 3 - w, Y = box.Y0, Cols = 1 }
	local spots: { Spot } = if chip
		then { below, corner, under, beside, belowCol, leftCol }
		else { corner, below, beside, under, belowCol, leftCol }
	-- 아무것도 안 가리는 첫 자리 → (세로 화면처럼 자리가 모자라면) HUD 만 안 가리는 첫 자리 → 가장 덜 가리는 자리
	local function pick(against: { UiKit.Rect }): (Spot, number)
		local best: Spot = spots[1]
		local bestOv = math.huge
		for _, spot in spots do
			local sw, sh = shape(spot.Cols)
			local r: UiKit.Rect = { X0 = spot.X, Y0 = spot.Y, X1 = spot.X + sw, Y1 = spot.Y + sh }
			local ov = UiKit.OverlapArea(r, against)
			if r.X0 < 0 or r.Y0 < 0 or r.X1 > gw or r.Y1 > gh then
				ov += sw * sh -- 화면 밖
			end
			if ov < bestOv then
				best, bestOv = spot, ov
				if ov == 0 then
					break
				end
			end
		end
		return best, bestOv
	end
	local best, ov = pick(list)
	if ov > 0 then
		local hudBest, hudOv = pick(hud)
		if hudOv == 0 then
			best = hudBest
		end
	end
	local fw, fh = shape(best.Cols)
	frame.Position = UDim2.fromOffset(math.floor(best.X), math.floor(best.Y))
	frame.Size = UDim2.fromOffset(fw, fh)
	for i, q in quicks do
		local col = (i - 1) % best.Cols
		local row = math.floor((i - 1) / best.Cols)
		q.Button.Position = UDim2.fromOffset(col * (w + gap), row * (h + gap))
		styleQuick(q, w, h, chip)
	end
end

-- 버튼 4개 (켜고 끄는 버튼 3 + ★v7.2 ⚙️) 자리: 큰 버튼 칸 오른쪽 위에 세로로 (안 되면 왼쪽 위 가로 → 큰 버튼 칸 오른쪽 아래 → 왼쪽 위 2×2
-- → 큰 버튼 칸 오른쪽 2×2 (위 / 아래 맞춤) → 오른쪽 위 세로 → 오른쪽 위 2×2). 아무것도 안 가리는 첫 자리,
-- 없으면 가장 덜 가리는 자리. (오른쪽은 되도록 아래 알림 줄 자리로 비워 둬요)
-- 위 코인 줄(+초당/금고 알약 줄), 큰 버튼 칸(+환생 알약), 폰 점프 버튼·조이스틱 자리는 피해요
local function layoutToggles(gui: ScreenGui, column: Frame, cell: number, gap: number)
	local frame = toggleFrame
	if not frame then
		return
	end
	local size = gui.AbsoluteSize
	local gw, gh = size.X, size.Y
	local n = #toggles + (if optionsButton then 1 else 0) -- ★v7.2 ⚙️ 옵션 버튼이 마지막 칸
	-- 큰 버튼이 크면 (PC·태블릿) 이름이 보이는 가로 버튼, 아니면 (폰) 작은 네모
	local chip = cell >= 70 and gw >= 700
	local bh = if chip then math.clamp(math.floor(cell * 0.56), 44, 54) else math.clamp(math.floor(cell * 0.62), 42, 58)
	local bw = if chip then math.floor(bh * 3.3) else bh
	local tgap = math.max(5, math.floor(bh * 0.12))

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

	-- 모양: cols 열 (1 = 세로, n = 가로, 2 = 2×2)
	local function shape(cols: number): (number, number)
		local rows = math.ceil(n / cols)
		return cols * bw + (cols - 1) * tgap, rows * bh + (rows - 1) * tgap
	end
	local _, long = shape(1) -- 세로로 세울 때 높이
	local gridW, gridH = shape(math.min(2, n))
	local _, grid3H = shape(math.min(3, n)) -- ★v7 5칸이면 3×2
	type Spot = { X: number, Y: number, Cols: number }
	-- 큰 버튼 오른쪽 위 빨간 "!" 알림(칸의 8 % 밖으로 나와요)과 안 닿게 조금 띄워요
	local sx = side.X1 + math.max(tgap, math.ceil(cell * 0.09) + 3)
	local spots: { Spot } = {
		{ X = sx, Y = math.max(8, side.Y0), Cols = 1 },
		{ X = 10, Y = 8, Cols = n },
		{ X = sx, Y = side.Y1 - long, Cols = 1 },
		{ X = 10, Y = 8, Cols = 2 },
		{ X = sx, Y = math.max(8, side.Y0), Cols = 2 },
		{ X = sx, Y = side.Y1 - gridH, Cols = 2 },
		{ X = 10, Y = 8, Cols = 3 }, -- ★v7 왼쪽 위 3×2 → 큰 버튼 칸 오른쪽 3×2 (위 / 아래 맞춤)
		{ X = sx, Y = math.max(8, side.Y0), Cols = 3 },
		{ X = sx, Y = side.Y1 - grid3H, Cols = 3 },
		{ X = gw - 10 - bw, Y = 8, Cols = 1 },
		{ X = gw - 10 - gridW, Y = 8, Cols = 2 },
	}
	local best: Spot? = nil
	local bestOv = math.huge
	for _, spot in spots do
		local w, h = shape(spot.Cols)
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
	local fw, fh = shape(spot.Cols)
	frame.Position = UDim2.fromOffset(math.floor(spot.X), math.floor(spot.Y))
	frame.Size = UDim2.fromOffset(fw, fh)
	-- 버튼은 줄 순서대로 (왼쪽 → 오른쪽, 위 → 아래)
	for i, tg in toggles do
		local col = (i - 1) % spot.Cols
		local row = math.floor((i - 1) / spot.Cols)
		tg.Button.Position = UDim2.fromOffset(col * (bw + tgap), row * (bh + tgap))
		styleToggle(tg, bw, bh, chip)
	end
	-- ★v7.2 ⚙️ (마지막 칸) → 빠른 버튼 2개
	local bx, by = math.floor(spot.X), math.floor(spot.Y)
	local o = optionsButton
	if o then
		local i = #toggles + 1
		local col = (i - 1) % spot.Cols
		local row = math.floor((i - 1) / spot.Cols)
		o.Button.Position = UDim2.fromOffset(col * (bw + tgap), row * (bh + tgap))
		styleOptions(o, bw, bh, chip)
	end
	layoutQuick(gui, avoid, { X0 = bx, Y0 = by, X1 = bx + fw, Y1 = by + fh }, chip, bw, bh, tgap)
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

	-- 켜고 끄는 버튼 3개 + ⚙️ (자리는 layout 이 정해요, 버튼 하나하나 Position 으로)
	local toggleBox: Frame = Make("Frame", {
		Name = "Toggles",
		BackgroundTransparency = 1,
		Parent = gui,
	})
	toggleFrame = toggleBox
	for i, def in TOGGLES do
		local t = makeToggle(toggleBox, def, i)
		table.insert(toggles, t)
		toggleByKey[def.Key] = t
		paintToggle(t, State.GetSetting(def.Key), false)
	end
	-- ★v7.2 ⚙️ 옵션 (마지막 칸, 🙈 부화 숨기기 · 🔔 알 알림은 OptionsWindow 안에), 빠른 버튼 2개 (가방 밖)
	local gear = makeOptionsButton(toggleBox, function()
		local o = optionsButton
		local now = os.clock()
		if not o or now - o.LastTap < 0.25 then
			return
		end
		o.LastTap = now
		local open = actions.ToggleOptions
		if open then
			open()
		else
			Toasts.Show("⚙️ 옵션은 곧 열려요!", "info")
		end
	end)
	gear.Button.LayoutOrder = #TOGGLES + 1
	optionsButton = gear
	local quickBox: Frame = Make("Frame", {
		Name = "Quick",
		BackgroundTransparency = 1,
		Parent = gui,
	})
	quickFrame = quickBox
	for _, def in QUICK do
		table.insert(quicks, makeQuick(quickBox, def))
	end
	State.OnSetting(function(key: string, value: any)
		local t = toggleByKey[key]
		if t and t.Shown ~= value then
			paintToggle(t, value, true)
		end
		if key == "AutoCollect" then
			lastPending = -1
			updatePending()
		end
	end)
	-- ★v7.2 게임 패스가 생기면 (서버가 Pass_<키> 를 켜요) 바로 보통 버튼으로 + 통통 (산 말풍선은 서버가 보내요)
	State.OnPass(function(key: string, has: boolean)
		local t = toggleByKey[key]
		if t and t.Locked ~= not has then
			t.Locked = not has
			paintToggle(t, State.GetSetting(key), false)
			if has then
				UiKit.Pop(t.Button, 0.35)
			end
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
	-- ★v7 빠른 버튼도 같이 숨어요 (⚙️ 옵션 창은 꾸미기를 시작할 때 init.client 가 다른 창처럼 닫아요)
	local quick = quickFrame
	if quick then
		quick.Visible = visible
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
		if quick then
			UiKit.Pop(quick, 0.3)
		end
	end
end

-- 켜고 끄는 버튼 (검사용): key → 버튼
function Hud.ToggleButton(key: string): TextButton?
	local t = toggleByKey[key]
	return if t then t.Button else nil
end

-- ★v7.2 검사용: ⚙️ 옵션 버튼, 빠른 버튼 ("StashEgg" | "AutoPlace")
function Hud.OptionsButton(): TextButton?
	local o = optionsButton
	return if o then o.Button else nil
end

function Hud.QuickButton(name: string): TextButton?
	for _, q in quicks do
		if q.Def.Name == name then
			return q.Button
		end
	end
	return nil
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
