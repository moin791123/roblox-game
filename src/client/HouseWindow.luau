-- 🏠 내 집 창: 층 올리기(최대 10층)·받침대 사기·층 목록(🛗 이동), 자동 배치/모두 빼기/🛋️ 꾸미기, 테마 8개
-- HouseWindow.OpenFloorPicker(floor?): 엘리베이터를 누르면 뜨는 작은 "층 이동" 창 (WorldFx → init.client 가 불러요)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local HouseWindow = {}

export type Actions = {
	Decorate: ((floor: number?) -> ())?, -- 🛋️ 꾸미기 (init.client 가 다른 창을 닫고 DecorateMode.Enter(floor))
	OpenShop: ((tab: string?) -> ())?, -- 🛍 가구 사기
}

type ThemeCard = {
	Frame: Frame,
	Stroke: UIStroke,
	Price: Frame,
	PriceLabel: TextLabel,
	Button: TextButton,
	ButtonLabel: TextLabel,
	Current: Frame,
}

type FloorRow = {
	Frame: Frame,
	Stroke: UIStroke,
	NamePill: Frame,
	Status: TextLabel,
	Go: TextButton,
	GoLabel: TextLabel,
}

type PickerButton = { Button: TextButton, Label: TextLabel }

local MAX_FLOORS = Config.House.MaxFloors
local PER_FLOOR = Config.Plot.SlotsPerFloor

local window: UiKit.Window
local picker: UiKit.Window
local actions: Actions = {}
local infoLabel: TextLabel
local floorButton: TextButton
local floorLabel: TextLabel
local slotButton: TextButton
local slotLabel: TextLabel
local furnLabel: TextLabel
local themeCards: { [string]: ThemeCard } = {}
local floorRows: { FloorRow } = {}
local pickerButtons: { PickerButton } = {}
local pickerInfo: TextLabel
local pickerFloor: number? = nil -- 엘리베이터가 있던 층 (모르면 캐릭터 높이로)
local lastFire = 0
local lastTeleport = -10

local function fireOnce(fn: () -> ())
	if os.clock() - lastFire < 0.3 then
		return
	end
	lastFire = os.clock()
	fn()
end

local function coins(): number
	return State.Coins()
end

local function needCoins(price: number, button: GuiObject)
	Toasts.Show(string.format("코인이 %s 필요해요 💰", Config.FormatNumber(price)), "warn")
	UiKit.Shake(button, 6, 6)
end

----------------------------------------------------------------------
-- 층 / 받침대
----------------------------------------------------------------------

-- 다음 층을 올리려면 무엇이 모자라나: (받침대 모자람?, 환생 모자람?)
local function floorNeeds(floors: number, slots: number, rebirths: number): (boolean, boolean)
	local info = Config.FloorRequirement(floors + 1)
	if not info then
		return false, false
	end
	return slots < floors * PER_FLOOR, rebirths < info.MinRebirth
end

local function onBuyFloor()
	local snap = State.Snapshot
	if not snap then
		return
	end
	local floors, slots, rebirths = snap.Floors, snap.SlotsUnlocked, snap.Rebirths
	local ok, reason = Config.CanBuyFloor(floors, slots, rebirths)
	if not ok then
		if reason == "Max" then
			Toasts.Show("이미 10층이에요! 🏰", "info")
		elseif reason == "Slots" then
			Toasts.Show(string.format("받침대 %d개를 먼저 다 열어야 해요!", floors * PER_FLOOR), "warn")
		elseif reason == "Rebirth" then
			local info = Config.FloorRequirement(floors + 1)
			Toasts.Show(string.format("🔄 환생 %d회가 필요해요!", if info then info.MinRebirth else 0), "warn")
		end
		UiKit.Shake(floorButton, 6, 6)
		return
	end
	local price = Config.FloorRequirement(floors + 1).Price
	if coins() < price then
		needCoins(price, floorButton)
		return
	end
	fireOnce(function()
		Remotes.BuyFloor:FireServer()
		UiKit.PlaySound("Buy")
	end)
end

local function onBuySlot()
	local snap = State.Snapshot
	if not snap then
		return
	end
	local floors, slots = snap.Floors, snap.SlotsUnlocked
	local price = Config.NextSlotPrice(slots, floors)
	if not price then
		if slots >= Config.Plot.TotalSlots then
			Toasts.Show("받침대가 최대예요! 🎉", "info")
		else
			Toasts.Show(string.format("%d층을 먼저 올려야 해요! 🏠", floors + 1), "warn")
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
		UiKit.PlaySound("Buy")
	end)
end

-- 우리 집 n층으로 순간이동 (서버가 1.5초에 한 번만 받아 줘요)
local function teleportFloor(n: number)
	local snap = State.Snapshot
	if not snap then
		return
	end
	if not State.Plot then
		Toasts.Show("집이 아직 없어요! 잠깐만 기다려 주세요 🏠", "warn")
		return
	end
	if n > snap.Floors then
		local info = Config.FloorRequirement(n)
		if info and snap.Rebirths < info.MinRebirth then
			Toasts.Show(string.format("%d층은 🔄 환생 %d회부터 올릴 수 있어요!", n, info.MinRebirth), "warn")
		else
			Toasts.Show(string.format("%d층은 아직 없어요! 집(H)에서 올려 보세요 🏗", n), "warn")
		end
		return
	end
	if State.CurrentFloor() == n then
		Toasts.Show(string.format("여기가 %d층이에요! 😊", n), "info")
		return
	end
	if os.clock() - lastTeleport < 1.6 then
		Toasts.Show("잠깐만요! ⏳", "info")
		return
	end
	lastTeleport = os.clock()
	Remotes.Teleport:FireServer("Floor", n)
	UiKit.PlaySound("Buy")
	Toasts.Show(string.format("🛗 %d층으로 가요!", n), "good")
	picker.Close()
	window.Close()
end

local function teleportHome()
	if os.clock() - lastTeleport < 1.6 then
		Toasts.Show("잠깐만요! ⏳", "info")
		return
	end
	lastTeleport = os.clock()
	Remotes.Teleport:FireServer("Home", 1)
	UiKit.PlaySound("Buy")
	picker.Close()
	window.Close()
end

----------------------------------------------------------------------
-- 자동 배치 / 모두 빼기 / 꾸미기
----------------------------------------------------------------------
local function onAutoPlace()
	if not State.Plot then
		Toasts.Show("집이 아직 없어요! 잠깐만 기다려 주세요 🏠", "warn")
		return
	end
	fireOnce(function()
		Remotes.AutoPlace:FireServer()
	end)
end

local function onClearBase()
	fireOnce(function()
		Remotes.ClearBase:FireServer()
	end)
end

local function onDecorate()
	if not State.Plot then
		Toasts.Show("집이 아직 없어요! 잠깐만 기다려 주세요 🏠", "warn")
		return
	end
	local decorate = actions.Decorate
	if not decorate then
		Toasts.Show("꾸미기는 곧 열려요! 🛠", "info")
		return
	end
	local floor = State.CurrentFloor()
	picker.Close()
	window.Close()
	decorate(floor)
end

local function onFurnitureShop()
	local open = actions.OpenShop
	if open then
		window.Close()
		open("Furniture")
	else
		Toasts.Show("🛍 상점(P)에서 가구를 살 수 있어요!", "info")
	end
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
	local owned = themeId == "Basic" or snap.Themes[themeId] == true
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
		Position = UDim2.fromScale(0.06, 0.04),
		Size = UDim2.fromScale(0.88, 0.2),
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
	for i, color in { theme.Floor, theme.Wall, theme.Roof, theme.Accent } do
		local sw: Frame = Make("Frame", {
			Size = UDim2.fromScale(0.22, 1),
			BackgroundColor3 = color,
			LayoutOrder = i,
			Parent = swatches,
		})
		Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = sw })
		UiKit.Corner(sw, UDim.new(0.3, 0))
		UiKit.Gradient(sw)
		UiKit.Stroke(sw, C.White, 3, true)
	end

	-- 지붕 모양 포인트
	local roof: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromScale(0.5, 0.03),
		BackgroundColor3 = theme.Roof,
		Parent = frame,
	})
	UiKit.Corner(roof, UDim.new(0.5, 0))

	UiKit.Label({
		Name = "ThemeName",
		Text = theme.Name,
		Position = UDim2.fromScale(0.04, 0.3),
		Size = UDim2.fromScale(0.92, 0.13),
		Parent = frame,
	}, { Stroke = UiKit.Darken(theme.Roof, 0.4), StrokeThickness = 3, MaxText = 26 })

	-- 크기 + 수익 보너스
	local bonus = math.floor((theme.IncomeBonus or 0) * 100 + 0.5)
	UiKit.Label({
		Name = "Stats",
		Text = string.format("🏠 크기 %d · %s", theme.Size or 26, if bonus > 0 then string.format("+%d%% 수익", bonus) else "보너스 없음"),
		Position = UDim2.fromScale(0.04, 0.44),
		Size = UDim2.fromScale(0.92, 0.1),
		TextColor3 = C.Ink,
		Parent = frame,
	}, { Stroke = C.White, MaxText = 18 })

	local price: Frame = Make("Frame", {
		Name = "Price",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.57),
		Size = UDim2.fromScale(0.72, 0.11),
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
		Position = UDim2.fromScale(-0.03, -0.04),
		Size = UDim2.fromScale(0.5, 0.11),
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
-- 층 목록 한 줄
----------------------------------------------------------------------
local function createFloorRow(parent: Instance, f: number): FloorRow
	local frame: Frame = Make("Frame", {
		Name = "Floor" .. f,
		Size = UDim2.new(1, -8, 0, 46),
		BackgroundColor3 = C.White,
		LayoutOrder = f,
		Parent = parent,
	})
	UiKit.Corner(frame, UDim.new(0.3, 0))
	local stroke = UiKit.Stroke(frame, C.Grey, 3, true)
	local namePill = UiKit.Pill(frame, string.format("🏠 %d층", f), C.Peach, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.new(0.2, 0, 0, 32),
	}, 22)
	local status = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.2, 14, 0.5, 0),
		Size = UDim2.new(0.56, -20, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Ink,
		Parent = frame,
	}, { Stroke = C.White, MaxText = 20 })
	local go, goLabel = UiKit.Button({
		Name = "Go",
		Text = "🛗 가기",
		Color = C.Sky,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.new(0.22, 0, 0, 36),
		Radius = UDim.new(0.4, 0),
		TextSize = 20,
		Parent = frame,
		OnClick = function()
			teleportFloor(f)
		end,
	})
	return { Frame = frame, Stroke = stroke, NamePill = namePill, Status = status, Go = go, GoLabel = goLabel }
end

----------------------------------------------------------------------
-- 다시 그리기
----------------------------------------------------------------------
local lastTheme = ""

local function rebuild()
	local snap = State.Snapshot
	if not snap then
		return
	end
	local floors = snap.Floors
	local slots = snap.SlotsUnlocked
	local rebirths = snap.Rebirths
	local currentTheme = snap.Theme
	local have = coins()
	local here = State.CurrentFloor()

	-- 집 정보
	local plotIdx = State.PlotIndex()
	local where = if plotIdx then string.format("🏠 %d번 집", plotIdx) else "🏠 내 집"
	local bonus = math.floor(Config.ThemeIncomeBonus(currentTheme) * 100 + 0.5)
	infoLabel.Text = string.format("%s · 🏢 %d층 · 받침대 %d/%d · 🎨 +%d%%", where, floors, slots, floors * PER_FLOOR, bonus)

	-- 층 올리기 (큰 버튼)
	local nextFloor = floors + 1
	local nextInfo = Config.FloorRequirement(nextFloor)
	if floors >= MAX_FLOORS or not nextInfo then
		floorLabel.Text = string.format("🏰 %d층 완성! ✅", floors)
		floorButton.BackgroundColor3 = C.Grey
	else
		local needSlots, needRebirth = floorNeeds(floors, slots, rebirths)
		if needRebirth then
			floorLabel.Text = string.format("🏗 %d층 올리기\n🔒 환생 %d회 필요", nextFloor, nextInfo.MinRebirth)
			floorButton.BackgroundColor3 = C.Grey
		elseif needSlots then
			floorLabel.Text = string.format("🏗 %d층 올리기\n받침대 먼저 (%d/%d)", nextFloor, slots, floors * PER_FLOOR)
			floorButton.BackgroundColor3 = C.Grey
		else
			floorLabel.Text = string.format("🏗 %d층 올리기\n💰 %s", nextFloor, Config.FormatNumber(nextInfo.Price))
			floorButton.BackgroundColor3 = if have >= nextInfo.Price then C.Mint else C.Lavender
		end
	end

	-- 받침대
	local price = Config.NextSlotPrice(slots, floors)
	if price then
		slotLabel.Text = string.format("➕ 받침대 %d번\n💰 %s", slots + 1, Config.FormatNumber(price))
		slotButton.BackgroundColor3 = if have >= price then C.Peach else C.Lavender
	elseif slots < Config.Plot.TotalSlots then
		slotLabel.Text = string.format("➕ 받침대\n%d층이 필요해요", floors + 1)
		slotButton.BackgroundColor3 = C.Grey
	else
		slotLabel.Text = "➕ 받침대\n최대 🎉"
		slotButton.BackgroundColor3 = C.Grey
	end

	-- 가구
	furnLabel.Text = string.format("🛋 놓은 가구 %d개 · 가구 가방 %d개", State.CountPlacedFurniture(), State.CountFurnitureInv())

	-- 층 목록
	for f, row in floorRows do
		local info = Config.FloorRequirement(f)
		local built = f <= floors
		if built then
			local isHere = here == f
			row.Status.Text = if isHere then "✅ 지금 여기 📍" else string.format("✅ 받침대 %d개", math.clamp(slots - (f - 1) * PER_FLOOR, 0, PER_FLOOR))
			row.Frame.BackgroundColor3 = UiKit.Lighten(C.Mint, if isHere then 0.55 else 0.78)
			row.Stroke.Color = if isHere then C.Gold else C.Mint
			row.NamePill.BackgroundColor3 = C.Peach
			row.Go.Visible = true
			row.Go.BackgroundColor3 = if isHere then C.Grey else C.Sky
		elseif f == nextFloor and info then
			local needSlots, needRebirth = floorNeeds(floors, slots, rebirths)
			if needSlots and needRebirth then
				row.Status.Text = string.format("🔒 환생 %d회 · 받침대 %d/%d", info.MinRebirth, slots, floors * PER_FLOOR)
			elseif needSlots then
				row.Status.Text = string.format("받침대를 먼저 다 열어요 (%d/%d)", slots, floors * PER_FLOOR)
			elseif needRebirth then
				row.Status.Text = string.format("🔒 환생 %d회가 필요해요", info.MinRebirth)
			else
				row.Status.Text = "💰 " .. Config.FormatNumber(info.Price) .. (if have >= info.Price then " · 올릴 수 있어요! ✨" else "")
			end
			row.Frame.BackgroundColor3 = UiKit.Lighten(C.Lemon, 0.75)
			row.Stroke.Color = C.Lemon
			row.NamePill.BackgroundColor3 = C.Lemon
			row.Go.Visible = false
		elseif info then
			row.Status.Text = if info.MinRebirth > 0
				then string.format("🔒 환생 %d · 💰 %s", info.MinRebirth, Config.FormatNumber(info.Price))
				else "💰 " .. Config.FormatNumber(info.Price)
			row.Frame.BackgroundColor3 = Color3.fromRGB(235, 232, 242)
			row.Stroke.Color = C.Grey
			row.NamePill.BackgroundColor3 = C.Grey
			row.Go.Visible = false
		end
	end

	-- 테마 카드
	for themeId, card in themeCards do
		local theme = Config.House.Themes[themeId]
		local isCurrent = themeId == currentTheme
		local has = themeId == "Basic" or snap.Themes[themeId] == true
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
			card.PriceLabel.Text = "보유 ✓"
			card.Price.BackgroundColor3 = C.Mint
			card.ButtonLabel.Text = if isCurrent then "사용 중" else "적용"
			card.Button.BackgroundColor3 = if isCurrent then C.Grey else C.Mint
		else
			card.PriceLabel.Text = "💰 " .. Config.FormatNumber(theme.Price)
			card.Price.BackgroundColor3 = C.Lemon
			card.ButtonLabel.Text = "구매"
			card.Button.BackgroundColor3 = if have >= theme.Price then C.Pink else C.Lavender
		end
		if isCurrent and lastTheme ~= "" and lastTheme ~= themeId then
			UiKit.Pop(card.Current, 0.4)
			UiKit.Bump(card.Frame, 0.08)
		end
	end
	lastTheme = currentTheme
end

----------------------------------------------------------------------
-- 엘리베이터 층 고르기 창
----------------------------------------------------------------------
local function refreshPicker()
	local snap = State.Snapshot
	local floors = if snap then snap.Floors else 1
	local here = pickerFloor or State.CurrentFloor()
	pickerInfo.Text = if here then string.format("📍 지금 %d층 · 어디로 갈까요?", here) else "어디로 갈까요? 🛗"
	for f, pb in pickerButtons do
		if f <= floors then
			local isHere = f == here
			pb.Label.Text = if isHere then string.format("%d층\n📍 여기", f) else string.format("%d층", f)
			pb.Button.BackgroundColor3 = if isHere then C.Gold else C.Sky
		else
			pb.Label.Text = string.format("%d층\n🔒", f)
			pb.Button.BackgroundColor3 = C.Grey
		end
	end
end

local function buildPicker(gui: Instance)
	picker = UiKit.Window(gui, {
		Title = "🛗 엘리베이터",
		Color = C.Sky,
		Name = "FloorPicker",
		Size = UDim2.fromScale(0.62, 0.7),
		MaxSize = Vector2.new(560, 400),
	})
	local content = picker.Content
	pickerInfo = UiKit.Label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = C.Ink,
		Parent = content,
	}, { Stroke = C.White, MaxText = 22 })

	local gridFrame: Frame = Make("Frame", {
		Name = "Floors",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -86),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local grid: UIGridLayout = Make("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = gridFrame,
	})
	for f = 1, MAX_FLOORS do
		local btn, label = UiKit.Button({
			Name = "Floor" .. f,
			Text = string.format("%d층", f),
			Color = C.Sky,
			LayoutOrder = f,
			Radius = UDim.new(0.3, 0),
			TextSize = 26,
			Parent = gridFrame,
			OnClick = function()
				teleportFloor(f)
			end,
		})
		pickerButtons[f] = { Button = btn, Label = label }
	end
	local function relayoutGrid()
		local scale = UiKit.ScaleOf(gridFrame)
		local w = gridFrame.AbsoluteSize.X / scale
		local h = gridFrame.AbsoluteSize.Y / scale
		if w <= 0 or h <= 0 then
			return
		end
		local cols = 5
		local rows = math.ceil(MAX_FLOORS / cols)
		local cw = math.floor((w - (cols - 1) * 8) / cols)
		local ch = math.clamp(math.floor((h - (rows - 1) * 8) / rows), 36, 80)
		grid.CellSize = UDim2.fromOffset(cw, ch)
	end
	gridFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutGrid)
	relayoutGrid()

	local bottom: Frame = Make("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		Parent = content,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bottom,
	})
	UiKit.Button({
		Text = "🚪 입구로",
		Color = C.Mint,
		Size = UDim2.new(0.31, 0, 1, 0),
		LayoutOrder = 1,
		TextSize = 22,
		Parent = bottom,
		OnClick = teleportHome,
	})
	UiKit.Button({
		Text = "🪑 가구 꾸미기",
		Color = C.Pink,
		Size = UDim2.new(0.31, 0, 1, 0),
		LayoutOrder = 2,
		TextSize = 22,
		Parent = bottom,
		OnClick = onDecorate,
	})
	UiKit.Button({
		Text = "🏠 집 관리",
		Color = C.Peach,
		Size = UDim2.new(0.31, 0, 1, 0),
		LayoutOrder = 3,
		TextSize = 22,
		Parent = bottom,
		OnClick = function()
			picker.Close()
			HouseWindow.Open()
		end,
	})
end

----------------------------------------------------------------------
-- 만들기
----------------------------------------------------------------------
function HouseWindow.Init(gui: Instance, houseActions: Actions?)
	actions = houseActions or {}
	window = UiKit.Window(gui, { Title = "🏠 내 집", Color = C.Peach, Name = "HouseWindow" })
	local content = window.Content
	local scroll = UiKit.ListScroller(content, { ScrollBarImageColor3 = C.Peach })

	-- 집 정보 알약
	local _, label = UiKit.Pill(scroll, "🏠 내 집", C.Lavender, {
		Name = "Info",
		Size = UDim2.new(1, -8, 0, 40),
		LayoutOrder = 1,
	}, 24)
	infoLabel = label

	-- 층 올리기 / 받침대 (큰 버튼 둘)
	local buyRow: Frame = Make("Frame", {
		Name = "Buy",
		Size = UDim2.new(1, -8, 0, 76),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = scroll,
	})
	floorButton, floorLabel = UiKit.Button({
		Name = "BuyFloor",
		Text = "🏗 층 올리기",
		Color = C.Mint,
		Size = UDim2.new(0.5, -5, 1, 0),
		Radius = UDim.new(0.25, 0),
		TextSize = 26,
		Parent = buyRow,
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
		Parent = buyRow,
		OnClick = onBuySlot,
	})

	-- 펫 정리 + 꾸미기
	local toolRow: Frame = Make("Frame", {
		Name = "Tools",
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = scroll,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toolRow,
	})
	UiKit.Button({
		Name = "AutoPlace",
		Text = "✨ 좋은 펫 자동 배치",
		Color = C.Gold,
		Size = UDim2.new(0.34, -6, 1, 0),
		LayoutOrder = 1,
		Radius = UDim.new(0.35, 0),
		TextSize = 22,
		Parent = toolRow,
		OnClick = onAutoPlace,
	})
	local clearTap: () -> () = function() end
	local clearBtn, clearLabel = UiKit.Button({
		Name = "ClearBase",
		Text = "📦 집 펫 모두 빼기",
		Color = C.Sky,
		Size = UDim2.new(0.34, -6, 1, 0),
		LayoutOrder = 2,
		Radius = UDim.new(0.35, 0),
		TextSize = 22,
		Parent = toolRow,
		OnClick = function()
			if State.SlotPetCount() == 0 then
				Toasts.Show("집에 펫이 없어요 🏠", "info")
				return
			end
			clearTap()
		end,
	})
	clearTap = UiKit.TwoTap(clearBtn, clearLabel, "정말 다 뺄까요? 📦", onClearBase)
	UiKit.Button({
		Name = "Decorate",
		Text = "🪑 가구 꾸미기",
		Color = C.Pink,
		Size = UDim2.new(0.32, -6, 1, 0),
		LayoutOrder = 3,
		Radius = UDim.new(0.35, 0),
		TextSize = 24,
		Parent = toolRow,
		OnClick = onDecorate,
	})

	-- 가구 정보 + 가구 사기
	local furnRow: Frame = Make("Frame", {
		Name = "Furniture",
		Size = UDim2.new(1, -8, 0, 40),
		BackgroundColor3 = UiKit.Lighten(C.Pink, 0.8),
		LayoutOrder = 4,
		Parent = scroll,
	})
	UiKit.Corner(furnRow, UDim.new(0.5, 0))
	UiKit.Stroke(furnRow, C.Pink, 3, true)
	furnLabel = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.new(0.66, -14, 0.7, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Ink,
		Parent = furnRow,
	}, { Stroke = C.White, MaxText = 20 })
	UiKit.Button({
		Name = "FurnitureShop",
		Text = "🛍 가구 사기",
		Color = C.Mint,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.new(0.32, 0, 1, -6),
		Radius = UDim.new(0.5, 0),
		TextSize = 20,
		Parent = furnRow,
		OnClick = onFurnitureShop,
	})

	-- 층 목록
	UiKit.SectionHeader(scroll, "🏢 우리 집 층", C.Sky, 5, 220)
	local floorList: Frame = Make("Frame", {
		Name = "FloorList",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 6,
		Parent = scroll,
	})
	Make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = floorList,
	})
	for f = 1, MAX_FLOORS do
		floorRows[f] = createFloorRow(floorList, f)
	end

	-- 테마 머리글 + 격자
	UiKit.SectionHeader(scroll, "🎨 집 테마 (클수록 수익 UP)", C.Pink, 7, 260)
	local section: Frame = Make("Frame", {
		Name = "Themes",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 8,
		Parent = scroll,
	})
	for i, themeId in Config.House.ThemeOrder do
		if Config.House.Themes[themeId] then
			themeCards[themeId] = createThemeCard(section, themeId, i)
		end
	end
	UiKit.SectionGrid(section, scroll, 150, 1.5, 4) -- 버튼이 44px 이상 되게 세로로 넉넉히

	window.OnOpen = function()
		picker.Close()
		rebuild()
	end
	State.OnPlot(function()
		if window.IsOpen() then
			rebuild()
		end
	end)
	-- 코인이 바뀌면 살 수 있는지 색 다시 (열려 있을 때만, 닫혀 있으면 열 때 다시 그려요)
	State.OnCoins(function()
		if window.IsOpen() then
			rebuild()
		end
	end)

	buildPicker(gui)
	picker.OnOpen = refreshPicker
end

function HouseWindow.OnSync()
	if window and window.IsOpen() then
		rebuild()
	end
	if picker and picker.IsOpen() then
		refreshPicker()
	end
end

function HouseWindow.Open()
	if picker then
		picker.Close()
	end
	window.Open()
end

-- 엘리베이터 층 고르기 (floor = 누른 엘리베이터가 있는 층, 모르면 nil)
function HouseWindow.OpenFloorPicker(floor: number?)
	if not picker then
		return
	end
	pickerFloor = if type(floor) == "number" then floor else nil
	window.Close()
	if picker.IsOpen() then
		refreshPicker()
		return
	end
	picker.Open()
end

function HouseWindow.Close()
	if window then
		window.Close()
	end
	if picker then
		picker.Close()
	end
end

-- 집 창이나 층 고르기 창 중 하나라도 열려 있으면 true
function HouseWindow.IsOpen(): boolean
	return (window ~= nil and window.IsOpen()) or (picker ~= nil and picker.IsOpen())
end

return HouseWindow
