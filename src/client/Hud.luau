-- 화면 고정 UI: 코인(CoinSync 로 바로바로), 초당 수익, 집 금고, 펫 수, 왼쪽 큰 버튼 7개
-- (가방 B / 도감 N / 집 H / 상점 P / 지도 M / 순위 L / 환생 R). 화면이 낮으면 2~3열로 접혀요.
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

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
local lastPending = -1
local lastIncome = -1
local lastCanRebirth: boolean? = nil

local coinValue = Instance.new("NumberValue")
local targetCoins = -1
local lastPets = -1

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

	-- 코인 아래 줄: 초당 수익(항상) + 집 금고에 쌓인 코인(있을 때만)
	local subRow: Frame = Make("Frame", {
		Name = "SubRow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
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
		if def.Caption == "환생" then
			rebirthButton = btn
		end
	end
	local count = #defs

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
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

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
