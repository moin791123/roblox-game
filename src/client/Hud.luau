-- 화면 고정 UI: 코인, 펫 수, 왼쪽 큰 버튼들 (가방/도감/받침대/잠금)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local Hud = {}

local coinPill: Frame
local coinLabel: TextLabel
local pawPill: Frame
local pawLabel: TextLabel
local slotCaption: TextLabel
local lockButton: TextButton
local lockEmoji: TextLabel
local lockCaption: TextLabel
local lockStatus: Frame
local lockStatusLabel: TextLabel
local pendingPill: Frame
local pendingLabel: TextLabel
local lastPending = -1

local coinValue = Instance.new("NumberValue")
local targetCoins = -1
local lastPets = -1
local nextSlotPrice: number? = nil

export type Actions = { ToggleBag: () -> (), ToggleIndex: () -> () }

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

local function lockState(): (string, number)
	local plot = State.Plot
	if not plot then
		return "none", 0
	end
	local now = workspace:GetServerTimeNow()
	local lu = tonumber(plot:GetAttribute("LockedUntil")) or 0
	if lu > now then
		return "locked", lu - now
	end
	local cd = tonumber(plot:GetAttribute("LockCooldownUntil"))
	if not cd then
		cd = if lu > 0 then lu + Config.Plot.LockCooldown else 0
	end
	if now < cd then
		return "cooldown", cd - now
	end
	return "ready", 0
end

local lastLockState = ""
local function updateLock()
	local st, left = lockState()
	local secs = math.max(0, math.ceil(left))
	if st == "locked" then
		lockStatusLabel.Text = string.format("잠김 %d초", secs)
	elseif st == "cooldown" then
		lockStatusLabel.Text = string.format("다시 잠금까지 %d초", secs)
	end
	if st == lastLockState then
		return
	end
	lastLockState = st
	if st == "locked" then
		lockEmoji.Text = "🔒"
		lockCaption.Text = "잠김"
		lockButton.BackgroundColor3 = C.Mint
		lockStatus.BackgroundColor3 = C.Mint
		lockStatus.Visible = true
		UiKit.Pop(lockStatus)
	elseif st == "cooldown" then
		lockEmoji.Text = "⏳"
		lockCaption.Text = "잠금"
		lockButton.BackgroundColor3 = C.Grey
		lockStatus.BackgroundColor3 = C.Grey
		lockStatus.Visible = true
	else
		lockEmoji.Text = "🔒"
		lockCaption.Text = "잠금"
		lockButton.BackgroundColor3 = C.Lavender
		lockStatus.Visible = false
		if st == "ready" then
			UiKit.Bump(lockButton, 0.12)
		end
	end
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
		pendingLabel.Text = "🏦 기지 금고 +" .. Config.FormatNumber(pending)
		if not pendingPill.Visible then
			pendingPill.Visible = true
			UiKit.Pop(pendingPill)
		end
	else
		pendingPill.Visible = false
	end
	lastPending = pending
end

local function onLockPressed()
	local st, left = lockState()
	if st == "locked" then
		Toasts.Show(string.format("벌써 잠겨 있어요! 🔒 (%d초)", math.ceil(left)), "info")
		UiKit.Shake(lockButton, 6, 6)
	elseif st == "cooldown" then
		Toasts.Show(string.format("조금만 기다려요 ⏳ %d초", math.ceil(left)), "warn")
		UiKit.Shake(lockButton, 6, 6)
	else
		Remotes.LockBase:FireServer()
	end
end

local function onBuySlot()
	local snap = State.Snapshot
	if snap and not nextSlotPrice then
		Toasts.Show("받침대를 모두 열었어요! 🎉", "info")
		return
	end
	if snap and nextSlotPrice and (tonumber(snap.Coins) or 0) < nextSlotPrice then
		Toasts.Show(string.format("코인이 %s 필요해요 💰", Config.FormatNumber(nextSlotPrice)), "warn")
		return
	end
	Remotes.BuySlot:FireServer()
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

	-- 기지 금고에 쌓인 코인 (Collector 속성 Pending 을 실시간으로)
	pendingPill = Make("Frame", {
		Name = "Pending",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromScale(0.86, 0.52),
		BackgroundColor3 = C.Mint,
		Visible = false,
		Parent = coinPill,
	})
	UiKit.Corner(pendingPill, UDim.new(0.5, 0))
	UiKit.Gradient(pendingPill)
	UiKit.Stroke(pendingPill, C.White, 2, true)
	pendingLabel = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.78),
		Parent = pendingPill,
	}, { Stroke = UiKit.Darken(C.Mint, 0.5), MaxText = 22 })

	coinValue.Changed:Connect(function(v: number)
		coinLabel.Text = Config.FormatNumber(v)
	end)

	------------------------------------------------------------------
	-- 왼쪽: 큰 버튼들 (화면이 낮으면 2x2)
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
	local _slotBtn, _slotEmoji, slotCap = bigButton(column, "➕", "받침대", C.Peach, 3, onBuySlot)
	slotCaption = slotCap
	local lb, le, lc = bigButton(column, "🔒", "잠금", C.Lavender, 4, onLockPressed)
	lockButton, lockEmoji, lockCaption = lb, le, lc

	lockStatus = Make("Frame", {
		Name = "LockStatus",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 8, 0.5, 0),
		Size = UDim2.new(1.9, 0, 0.42, 0),
		BackgroundColor3 = C.Mint,
		Visible = false,
		ZIndex = 3,
		Parent = lockButton,
	})
	UiKit.Corner(lockStatus, UDim.new(0.5, 0))
	UiKit.Stroke(lockStatus, C.White, 3, true)
	lockStatusLabel = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.7),
		ZIndex = 4,
		Parent = lockStatus,
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
		local rows = math.ceil(4 / cols)
		grid.CellSize = UDim2.fromOffset(cell, cell)
		column.Size = UDim2.fromOffset(cols * cell + (cols - 1) * 10, rows * cell + (rows - 1) * 10)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	task.spawn(function()
		while true do
			updateLock()
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

	nextSlotPrice = Config.NextSlotPrice(tonumber(snap.SlotsUnlocked) or Config.Plot.StartSlots)
	slotCaption.Text = if nextSlotPrice then "💰" .. Config.FormatNumber(nextSlotPrice) else "최대"
end

return Hud
