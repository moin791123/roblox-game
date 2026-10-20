-- 🏠 내 집 창: 테마 고르기/사기, 2층 올리기, 받침대 사기
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local HouseWindow = {}

type ThemeCard = {
	Frame: Frame,
	Stroke: UIStroke,
	Price: Frame,
	PriceLabel: TextLabel,
	Button: TextButton,
	ButtonLabel: TextLabel,
	Current: Frame,
}

local window: UiKit.Window
local infoLabel: TextLabel
local floorButton: TextButton
local floorLabel: TextLabel
local slotButton: TextButton
local slotLabel: TextLabel
local themeCards: { [string]: ThemeCard } = {}
local dirty = true
local lastFire = 0

local function fireOnce(fn: () -> ())
	if os.clock() - lastFire < 0.3 then
		return
	end
	lastFire = os.clock()
	fn()
end

local function coins(): number
	local snap = State.Snapshot
	return if snap then tonumber(snap.Coins) or 0 else 0
end

local function needCoins(price: number, button: GuiObject)
	Toasts.Show(string.format("코인이 %s 필요해요 💰", Config.FormatNumber(price)), "warn")
	UiKit.Shake(button, 6, 6)
end

----------------------------------------------------------------------
-- 2층 / 받침대 버튼
----------------------------------------------------------------------
local function onBuyFloor()
	local snap = State.Snapshot
	if not snap then
		return
	end
	local floors = tonumber(snap.Floors) or 1
	local slots = tonumber(snap.SlotsUnlocked) or Config.Plot.StartSlots
	if floors >= Config.House.MaxFloors then
		Toasts.Show("벌써 2층이 있어요! 🏠", "info")
		return
	end
	if slots < Config.Plot.SlotsPerFloor then
		Toasts.Show(string.format("받침대 %d개를 먼저 여세요!", Config.Plot.SlotsPerFloor), "warn")
		UiKit.Shake(floorButton, 6, 6)
		return
	end
	if coins() < Config.House.FloorPrice then
		needCoins(Config.House.FloorPrice, floorButton)
		return
	end
	fireOnce(function()
		Remotes.BuyFloor:FireServer()
	end)
end

local function onBuySlot()
	local snap = State.Snapshot
	if not snap then
		return
	end
	local floors = tonumber(snap.Floors) or 1
	local slots = tonumber(snap.SlotsUnlocked) or Config.Plot.StartSlots
	local price = Config.NextSlotPrice(slots, floors)
	if not price then
		if floors < Config.House.MaxFloors and slots >= Config.Plot.SlotsPerFloor then
			Toasts.Show("2층을 먼저 올려야 해요! 🏗", "warn")
		else
			Toasts.Show("받침대를 모두 열었어요! 🎉", "info")
		end
		UiKit.Shake(slotButton, 6, 6)
		return
	end
	if coins() < price then
		needCoins(price, slotButton)
		return
	end
	fireOnce(function()
		Remotes.BuySlot:FireServer()
	end)
end

----------------------------------------------------------------------
-- 테마
----------------------------------------------------------------------
local function onTheme(themeId: string)
	local snap = State.Snapshot
	local theme = Config.House.Themes[themeId]
	if not snap or not theme then
		return
	end
	if snap.Theme == themeId then
		Toasts.Show("지금 쓰는 테마예요! 🏠", "info")
		return
	end
	local owned = themeId == "Basic" or (type(snap.Themes) == "table" and snap.Themes[themeId] == true)
	local card = themeCards[themeId]
	if not owned and coins() < theme.Price then
		needCoins(theme.Price, if card then card.Button else window.Panel)
		return
	end
	fireOnce(function()
		Remotes.SetTheme:FireServer(themeId)
		UiKit.PlaySound("Buy")
	end)
end

local function createThemeCard(parent: Instance, themeId: string, order: number): ThemeCard
	local theme = Config.House.Themes[themeId]
	local frame: Frame = Make("Frame", {
		Name = themeId,
		LayoutOrder = order,
		BackgroundColor3 = UiKit.Lighten(theme.Wall, 0.3),
		ZIndex = 24,
		Parent = parent,
	})
	UiKit.Corner(frame, UDim.new(0.1, 0))
	local stroke = UiKit.Stroke(frame, C.Grey, 4, true)

	-- 색 견본 4칸 (바닥 / 벽 / 지붕 / 포인트)
	local swatches: Frame = Make("Frame", {
		Name = "Swatches",
		Position = UDim2.fromScale(0.06, 0.05),
		Size = UDim2.fromScale(0.88, 0.26),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0.04, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = swatches,
	})
	local colors = { theme.Floor, theme.Wall, theme.Roof, theme.Accent }
	for i, color in colors do
		local sw: Frame = Make("Frame", {
			Size = UDim2.fromScale(0.22, 1),
			BackgroundColor3 = color,
			LayoutOrder = i,
			Parent = swatches,
		})
		Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width, Parent = sw })
		UiKit.Corner(sw, UDim.new(0.3, 0))
		UiKit.Gradient(sw)
		UiKit.Stroke(sw, C.White, 3, true)
	end

	-- 지붕 모양 포인트 (작은 집 아이콘 느낌)
	local roof: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(0.5, 0.04),
		BackgroundColor3 = theme.Roof,
		Parent = frame,
	})
	UiKit.Corner(roof, UDim.new(0.5, 0))

	UiKit.Label({
		Name = "ThemeName",
		Text = theme.Name,
		Position = UDim2.fromScale(0.04, 0.4),
		Size = UDim2.fromScale(0.92, 0.14),
		Parent = frame,
	}, { Stroke = UiKit.Darken(theme.Roof, 0.4), StrokeThickness = 3, MaxText = 26 })

	local price: Frame = Make("Frame", {
		Name = "Price",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.7, 0.11),
		BackgroundColor3 = C.Lemon,
		Parent = frame,
	})
	UiKit.Corner(price, UDim.new(0.5, 0))
	UiKit.Stroke(price, C.White, 2, true)
	local priceLabel = UiKit.Label({
		Text = "",
		Size = UDim2.fromScale(0.86, 0.78),
		Position = UDim2.fromScale(0.07, 0.11),
		Parent = price,
	}, { Stroke = UiKit.Darken(C.Lemon, 0.5), MaxText = 20 })

	local button, buttonLabel = UiKit.Button({
		Name = "Apply",
		Text = "적용",
		Color = C.Mint,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.86, 0.22),
		Radius = UDim.new(0.4, 0),
		TextSize = 24,
		Parent = frame,
		OnClick = function()
			onTheme(themeId)
		end,
	})

	-- 지금 쓰는 테마 표시 (왼쪽 위 리본)
	local current: Frame = Make("Frame", {
		Name = "Current",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(-0.03, -0.04),
		Size = UDim2.fromScale(0.5, 0.12),
		Rotation = -8,
		BackgroundColor3 = C.Gold,
		Visible = false,
		ZIndex = 5,
		Parent = frame,
	})
	UiKit.Corner(current, UDim.new(0.5, 0))
	UiKit.Gradient(current)
	UiKit.Stroke(current, C.White, 3, true)
	UiKit.Label({ Text = "⭐ 사용 중", Size = UDim2.fromScale(0.86, 0.78), Position = UDim2.fromScale(0.07, 0.11), ZIndex = 6, Parent = current }, { Stroke = UiKit.Darken(C.Gold, 0.5), MaxText = 18 })

	return {
		Frame = frame,
		Stroke = stroke,
		Price = price,
		PriceLabel = priceLabel,
		Button = button,
		ButtonLabel = buttonLabel,
		Current = current,
	}
end

----------------------------------------------------------------------
-- 다시 그리기
----------------------------------------------------------------------
local lastTheme = ""

local function rebuild()
	dirty = false
	local snap = State.Snapshot
	if not snap then
		return
	end
	local floors = math.clamp(tonumber(snap.Floors) or 1, 1, Config.House.MaxFloors)
	local slots = tonumber(snap.SlotsUnlocked) or Config.Plot.StartSlots
	local owned: { [string]: boolean } = if type(snap.Themes) == "table" then snap.Themes else {}
	local currentTheme = if type(snap.Theme) == "string" then snap.Theme else "Basic"

	-- 집 정보
	local plot = State.Plot
	local plotIdx = (plot and tonumber(plot:GetAttribute("PlotIndex"))) or snap.PlotIndex
	local where = if plotIdx then string.format("🏠 %d번 집", plotIdx) else "🏠 내 집"
	infoLabel.Text = string.format("%s  ·  받침대 %d / %d  ·  %d층", where, slots, Config.Plot.TotalSlots, floors)

	-- 2층 올리기
	if floors >= Config.House.MaxFloors then
		floorLabel.Text = "🏗 2층 완료 ✅"
		floorButton.BackgroundColor3 = C.Grey
	elseif slots < Config.Plot.SlotsPerFloor then
		floorLabel.Text = string.format("🏗 2층 올리기\n받침대 %d개를 먼저 여세요", Config.Plot.SlotsPerFloor)
		floorButton.BackgroundColor3 = C.Grey
	else
		floorLabel.Text = "🏗 2층 올리기\n💰 " .. Config.FormatNumber(Config.House.FloorPrice)
		floorButton.BackgroundColor3 = if coins() >= Config.House.FloorPrice then C.Mint else C.Lavender
	end

	-- 받침대
	local price = Config.NextSlotPrice(slots, floors)
	if price then
		slotLabel.Text = "➕ 받침대\n💰 " .. Config.FormatNumber(price)
		slotButton.BackgroundColor3 = if coins() >= price then C.Peach else C.Lavender
	elseif floors < Config.House.MaxFloors and slots >= Config.Plot.SlotsPerFloor then
		slotLabel.Text = "➕ 받침대\n2층 필요"
		slotButton.BackgroundColor3 = C.Grey
	else
		slotLabel.Text = "➕ 받침대\n최대 🎉"
		slotButton.BackgroundColor3 = C.Grey
	end

	-- 테마 카드
	for themeId, card in themeCards do
		local theme = Config.House.Themes[themeId]
		local isCurrent = themeId == currentTheme
		local has = themeId == "Basic" or owned[themeId] == true
		card.Current.Visible = isCurrent
		if isCurrent then
			card.Stroke.Color = C.Gold
			card.Stroke.Thickness = 6
		elseif has then
			card.Stroke.Color = C.White
			card.Stroke.Thickness = 4
		else
			card.Stroke.Color = C.Grey
			card.Stroke.Thickness = 4
		end
		if has then
			card.PriceLabel.Text = "보유"
			card.Price.BackgroundColor3 = C.Mint
			card.ButtonLabel.Text = if isCurrent then "사용 중" else "적용"
			card.Button.BackgroundColor3 = if isCurrent then C.Grey else C.Mint
		else
			card.PriceLabel.Text = "💰 " .. Config.FormatNumber(theme.Price)
			card.Price.BackgroundColor3 = C.Lemon
			card.ButtonLabel.Text = "구매"
			card.Button.BackgroundColor3 = if coins() >= theme.Price then C.Pink else C.Lavender
		end
		if isCurrent and lastTheme ~= "" and lastTheme ~= themeId then
			UiKit.Pop(card.Current, 0.4)
			UiKit.Bump(card.Frame, 0.08)
		end
	end
	lastTheme = currentTheme
end

function HouseWindow.Init(gui: Instance)
	window = UiKit.Window(gui, { Title = "🏠 내 집", Color = C.Peach, Name = "HouseWindow" })
	local content = window.Content

	local scroll = UiKit.ListScroller(content, { ScrollBarImageColor3 = C.Peach })

	-- 집 정보 알약
	local info: Frame = Make("Frame", {
		Name = "Info",
		Size = UDim2.new(1, -8, 0, 40),
		BackgroundColor3 = C.Lavender,
		LayoutOrder = 1,
		Parent = scroll,
	})
	UiKit.Corner(info, UDim.new(0.5, 0))
	UiKit.Gradient(info)
	UiKit.Stroke(info, C.White, 3, true)
	infoLabel = UiKit.Label({
		Text = "🏠 내 집",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.74),
		Parent = info,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.5), MaxText = 24 })

	-- 2층 올리기 / 받침대 (큰 버튼 둘)
	local actions: Frame = Make("Frame", {
		Name = "Actions",
		Size = UDim2.new(1, -8, 0, 78),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = scroll,
	})
	floorButton, floorLabel = UiKit.Button({
		Name = "BuyFloor",
		Text = "🏗 2층 올리기",
		Color = C.Mint,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(0.5, -5, 1, 0),
		Radius = UDim.new(0.25, 0),
		TextSize = 26,
		Parent = actions,
		OnClick = onBuyFloor,
	})
	slotButton, slotLabel = UiKit.Button({
		Name = "BuySlot",
		Text = "➕ 받침대",
		Color = C.Peach,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -5, 1, 0),
		Radius = UDim.new(0.25, 0),
		TextSize = 26,
		Parent = actions,
		OnClick = onBuySlot,
	})

	-- 테마 머리글 + 격자
	UiKit.SectionHeader(scroll, "🎨 집 테마", C.Pink, 3)
	local section: Frame = Make("Frame", {
		Name = "Themes",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = scroll,
	})
	for i, themeId in Config.House.ThemeOrder do
		if Config.House.Themes[themeId] then
			themeCards[themeId] = createThemeCard(section, themeId, i)
		end
	end
	UiKit.SectionGrid(section, scroll, 150, 1.45, 4) -- 버튼이 44px 이상 되게 세로로 넉넉히

	window.OnOpen = function()
		if dirty then
			rebuild()
		end
	end
	State.OnPlot(function()
		if window.IsOpen() then
			rebuild()
		else
			dirty = true
		end
	end)
end

function HouseWindow.OnSync()
	if window and window.IsOpen() then
		rebuild()
	else
		dirty = true
	end
end

function HouseWindow.Open()
	window.Open()
end

function HouseWindow.Close()
	window.Close()
end

function HouseWindow.IsOpen(): boolean
	return window ~= nil and window.IsOpen()
end

return HouseWindow
