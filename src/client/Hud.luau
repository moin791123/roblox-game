-- 화면 고정 UI: 코인, 초당 수익, 펫 수, 왼쪽 큰 버튼들 (가방/도감/집/환생)
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

local BUTTON_COUNT = 4

export type Actions = { ToggleBag: () -> (), ToggleIndex: () -> (), ToggleHouse: () -> (), ToggleRebirth: () -> () }

-- 큰 네모 버튼 (이모지 + 아래 글자)
local function bigButton(parent: Instance, emoji: string, caption: string, color: Color3, order: number, onClick: () -> ())
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
	-- 왼쪽: 큰 버튼들 (화면이 낮으면 2열)
	------------------------------------------------------------------
	local column: Frame = Make("Frame", {
		Name = "SideButtons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.46, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local grid: UIGridLayout = Make("UIGridLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		CellPadding = UDim2.fromOffset(10, 10),
		Parent = column,
	})

	bigButton(column, "🎒", "가방", C.Pink, 1, actions.ToggleBag)
	bigButton(column, "📖", "도감", C.Sky, 2, actions.ToggleIndex)
	bigButton(column, "🏠", "집", C.Peach, 3, actions.ToggleHouse)
	rebirthButton = bigButton(column, "🔄", "환생", C.Lavender, 4, actions.ToggleRebirth)

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

	local function layout()
		local h = gui.AbsoluteSize.Y
		local cols, cell
		if h >= 520 then
			cols = 1
			cell = math.clamp(math.floor(h * 0.12), 66, 100)
		else
			cols = 2
			cell = math.clamp(math.floor(h * 0.19), 60, 76)
		end
		local rows = math.ceil(BUTTON_COUNT / cols)
		grid.CellSize = UDim2.fromOffset(cell, cell)
		column.Size = UDim2.fromOffset(cols * cell + (cols - 1) * 10, rows * cell + (rows - 1) * 10)
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

function Hud.Update(snap: State.Snapshot)
	local coins = tonumber(snap.Coins) or 0
	if targetCoins < 0 then
		coinValue.Value = coins
		coinLabel.Text = Config.FormatNumber(coins)
	elseif coins ~= targetCoins then
		if coins > targetCoins then
			UiKit.Bump(coinPill, 0.2)
			UiKit.Tween(coinValue, 0.6, { Value = coins })
		else
			UiKit.Bump(coinPill, -0.08)
			UiKit.Tween(coinValue, 0.35, { Value = coins })
		end
	end
	targetCoins = coins

	local pets = 0
	for _, item in snap.Items do
		if item.Kind == "Pet" then
			pets += 1
		end
	end
	pawLabel.Text = "🐾 " .. tostring(pets)
	if lastPets >= 0 and pets > lastPets then
		UiKit.Bump(pawPill, 0.25)
	end
	lastPets = pets

	-- 초당 수익
	local income = math.floor(tonumber(snap.Income) or 0)
	incomeLabel.Text = "💰 +" .. Config.FormatNumber(income) .. "/초"
	if lastIncome >= 0 and income > lastIncome then
		UiKit.Bump(incomePill, 0.2)
	end
	lastIncome = income

	-- 환생 비용 (살 수 있으면 민트색으로)
	local rebirths = tonumber(snap.Rebirths) or 0
	local cost = tonumber(snap.RebirthCost) or Config.RebirthCost(rebirths)
	local maxed = rebirths >= Config.Rebirth.MaxRebirths
	local can = not maxed and coins >= cost
	rebirthPillLabel.Text = if maxed then "최대 ✅" else "💰 " .. Config.FormatNumber(cost)
	rebirthPill.BackgroundColor3 = if can then C.Mint else C.Grey
	if can and lastCanRebirth == false then
		UiKit.Pop(rebirthPill, 0.4)
		UiKit.Bump(rebirthButton, 0.15)
	end
	lastCanRebirth = can
end

return Hud
