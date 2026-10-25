-- 🏠 내 집 창 (v4): 위쪽 탭 3개
--   🏡 새 집 (처음 탭): 집 테마 8개 큰 카드 (집 그림, 이름, 크기, +N% 수익, 값 / 보유 / 사는 중, 🛒 사기 · 🚚 이사하기)
--                     + 맨 위 "다음 집" 안내 (지금 살 수 있는 집 / 얼마 더 모으면 되는지)
--   🏗 층·받침대: 층 올리기(10층 + ★v8 2번 집 10층)·받침대 사기, 자동 배치 / 모두 빼기, 층 목록 (🛗 이동)
--   🪑 꾸미기: 가구 꾸미기 시작 (층 고르기), 놓은 가구 수, 🛍 가구 사기
-- HouseWindow.OpenFloorPicker(floor?): 엘리베이터를 누르면 뜨는 작은 "층 이동" 창 (WorldFx → init.client 가 불러요)
-- HouseWindow.ThemeGoal(): 지금 살 수 있는 더 좋은 집 (HUD "집" 버튼의 빨간 "!" 에 써요)
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
	Preview: Frame,
	NameLabel: TextLabel,
	Stats: TextLabel,
	Price: Frame,
	PriceLabel: TextLabel,
	Button: TextButton,
	ButtonLabel: TextLabel,
	Ribbon: Frame,
	RibbonLabel: TextLabel,
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

type TabInfo = { Text: string, Color: Color3, Order: number }

local MAX_FLOORS = Config.House.MaxFloors -- 집 한 채 층 (가구는 1번 집만)
local TOTAL_FLOORS = Config.House.TotalFloors -- ★v8 2번 집까지 (11~20 = 2번 집 1~10층)
local PER_FLOOR = Config.Plot.SlotsPerFloor

-- ★v8 짧은 층 이름 (버튼용): 1번 집 "3층", 2번 집 "🏡3층"
local function shortFloor(f: number): string
	local house, lf = Config.FloorHouse(f)
	return if house == 2 then "🏡" .. lf .. "층" else lf .. "층"
end

-- ★v8 2번 집 층을 보여 줄까 (1번 집을 다 올렸으면)
local function showHouse2(floors: number): boolean
	return floors >= MAX_FLOORS
end
local THEME_ORDER: { string } = Config.House.ThemeOrder

-- 탭 (처음 = 새 집)
local TABS: { [string]: TabInfo } = {
	Themes = { Text = "🏡 새 집", Color = C.Pink, Order = 1 },
	Floors = { Text = "🏗 층·받침대", Color = C.Sky, Order = 2 },
	Decor = { Text = "🪑 꾸미기", Color = C.Lavender, Order = 3 },
}
local TAB_IDS = { "Themes", "Floors", "Decor" }

local window: UiKit.Window
local picker: UiKit.Window
local rootGui: Instance? = nil
local actions: Actions = {}
local currentTab = "Themes"
local tabButtons: { [string]: TextButton } = {}
local tabScrolls: { [string]: ScrollingFrame } = {}
local tabRow: Frame
local themeBadge: Frame? = nil
local coinLabel: TextLabel
-- 새 집 탭
local goalFrame: Frame
local goalLabel: TextLabel
local goalBar: Frame
local goalFill: Frame
local themeSection: Frame
local themeGrid: UIGridLayout
local themeLandscape: boolean? = nil
local themeCards: { [string]: ThemeCard } = {}
-- 층·받침대 탭
local infoLabel: TextLabel
local floorButton: TextButton
local floorLabel: TextLabel
local slotButton: TextButton
local slotLabel: TextLabel
local floorRows: { FloorRow } = {}
-- 꾸미기 탭
local furnLabel: TextLabel
local decorFloorButtons: { PickerButton } = {}
local decorFloorRelayout: () -> () = function() end
local decorFloorsShown = -1
-- 엘리베이터 창
local pickerButtons: { PickerButton } = {}
local pickerInfo: TextLabel
local pickerRelayout: (() -> ())? = nil -- ★v8 보이는 층 버튼 수가 바뀌면 칸 크기 다시
local pickerFloor: number? = nil -- 엘리베이터가 있던 층 (모르면 캐릭터 높이로)
local lastFire = 0
local lastTeleport = -10
local moveConfirm: { [string]: number } = {} -- 더 작은 집으로 이사: 한 번 더 누를 때까지 (os.clock)
local rebuild: () -> () = function() end -- 아래에서 채워요

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
	local short = math.max(0, price - coins())
	Toasts.Show(string.format("코인이 %s 더 필요해요 💰", Config.FormatNumber(if short > 0 then short else price)), "warn")
	UiKit.Shake(button, 6, 6)
end

-- 낮은 화면 (가로 폰): 탭 줄을 얇게
local function isShort(): boolean
	local g = rootGui
	if g and g:IsA("GuiBase2d") then
		local h = (g :: GuiBase2d).AbsoluteSize.Y
		return h > 0 and h < 500
	end
	return false
end

----------------------------------------------------------------------
-- 테마 도우미
----------------------------------------------------------------------

local function ownsTheme(snap: any, themeId: string): boolean
	return themeId == "Basic" or (snap ~= nil and type(snap.Themes) == "table" and snap.Themes[themeId] == true)
end

-- 다음 집: (지금 살 수 있는 가장 좋은 새 집?, 다음에 살 새 집?)
-- "새 집" = 아직 없고, 가진 집 중 가장 좋은 집보다 뒤 순서 (일부러 건너뛴 싼 집은 다시 권하지 않아요)
local function themeGoal(snap: any, have: number): (string?, string?)
	if not snap then
		return nil, nil
	end
	local best = 0
	for i, id in THEME_ORDER do
		if ownsTheme(snap, id) then
			best = i
		end
	end
	local affordable: string? = nil
	local nextId: string? = nil
	for i = best + 1, #THEME_ORDER do
		local id = THEME_ORDER[i]
		local theme = Config.House.Themes[id]
		if theme and not ownsTheme(snap, id) then
			if nextId == nil then
				nextId = id
			end
			if have >= theme.Price then
				affordable = id
			end
		end
	end
	return affordable, nextId
end

-- (공개) 지금 살 수 있는 더 좋은 집 id (없으면 nil), 다음 목표 집 id
function HouseWindow.ThemeGoal(): (string?, string?)
	return themeGoal(State.Snapshot, coins())
end

local function bonusText(theme: any): string
	local bonus = math.floor((theme.IncomeBonus or 0) * 100 + 0.5)
	return if bonus > 0 then string.format("+%d%% 수익", bonus) else "보너스 없음"
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
			Toasts.Show("2번 집까지 다 올렸어요! 🏰", "info")
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
			Toasts.Show(Config.FloorName(floors + 1) .. "을 먼저 올려야 해요! 🏠", "warn")
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
			Toasts.Show(string.format("%s은 🔄 환생 %d회부터 올릴 수 있어요!", Config.FloorName(n), info.MinRebirth), "warn")
		else
			Toasts.Show(string.format("%s은 아직 없어요! 집(H)에서 올려 보세요 🏗", Config.FloorName(n)), "warn")
		end
		return
	end
	if State.CurrentFloor() == n then
		Toasts.Show(string.format("여기가 %s이에요! 😊", Config.FloorName(n)), "info")
		return
	end
	if os.clock() - lastTeleport < 1.6 then
		Toasts.Show("잠깐만요! ⏳", "info")
		return
	end
	lastTeleport = os.clock()
	Remotes.Teleport:FireServer("Floor", n)
	UiKit.PlaySound("Buy")
	Toasts.Show(string.format("🛗 %s으로 가요!", Config.FloorName(n)), "good")
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

-- floor = 꾸밀 층 (nil 이면 지금 있는 층, 집 밖이면 꾸미기 모드가 정해요)
local function decorateFloor(floor: number?)
	if not State.Plot then
		Toasts.Show("집이 아직 없어요! 잠깐만 기다려 주세요 🏠", "warn")
		return
	end
	if floor and floor > MAX_FLOORS then
		Toasts.Show("가구는 1번 집에만 놓을 수 있어요 🪑", "info") -- ★v8
		return
	end
	local decorate = actions.Decorate
	if not decorate then
		Toasts.Show("꾸미기는 곧 열려요! 🛠", "info")
		return
	end
	picker.Close()
	window.Close()
	decorate(floor)
end

local function onDecorate()
	decorateFloor(State.CurrentFloor())
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
-- 🏡 새 집: 테마 카드
----------------------------------------------------------------------
local function onTheme(themeId: string)
	local snap = State.Snapshot
	local theme = Config.House.Themes[themeId]
	if not snap or not theme then
		return
	end
	if snap.Theme == themeId then
		Toasts.Show("지금 살고 있는 집이에요! 🏡", "info")
		return
	end
	local owned = ownsTheme(snap, themeId)
	local card = themeCards[themeId]
	if not owned and coins() < theme.Price then
		needCoins(theme.Price, if card then card.Button else window.Panel)
		return
	end
	-- 더 작은 집으로 가면 안 들어가는 가구는 🎒 가방으로 가요 (ShopService) → 한 번 더 눌러야 이사
	if (theme.Size or 26) < Config.ThemeSize(snap.Theme) and State.CountPlacedFurniture() > 0 then
		if os.clock() > (moveConfirm[themeId] or 0) then
			moveConfirm[themeId] = os.clock() + 2.5
			Toasts.Show("작은 집이라 가구가 🎒 가방으로 갈 수 있어요! 한 번 더 누르면 이사해요", "warn")
			rebuild()
			if card then
				UiKit.Shake(card.Button, 5, 6)
			end
			task.delay(2.6, function()
				if window.IsOpen() then
					rebuild()
				end
			end)
			return
		end
		moveConfirm[themeId] = nil
	end
	fireOnce(function()
		Remotes.SetTheme:FireServer(themeId)
		UiKit.PlaySound("Buy")
		if card then
			UiKit.Bump(card.Frame, 0.08)
		end
	end)
end

-- 작은 집 그림 (땅 · 벽 · 3단 지붕 · 문 · 창문). 테마가 클수록 집도 넓게 그려요
local function drawHouse(holder: Frame, theme: any)
	local t = math.clamp(((theme.Size or 26) - 26) / 26, 0, 1)
	local groundH = 0.2
	local bodyW = 0.4 + 0.3 * t
	local bodyH = 0.34 + 0.08 * t
	local bodyBottom = 1 - groundH + 0.03
	local bodyTop = bodyBottom - bodyH

	local ground: Frame = Make("Frame", {
		Name = "Ground",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, groundH),
		BackgroundColor3 = theme.Floor,
		BorderSizePixel = 0,
		Parent = holder,
	})
	UiKit.Gradient(ground)

	-- 지붕 3단 (아래가 넓고 위로 갈수록 좁게)
	for k, w in { 1.22, 0.86, 0.5 } do
		local roof: Frame = Make("Frame", {
			Name = "Roof" .. k,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, bodyTop + 0.02 - (k - 1) * 0.095),
			Size = UDim2.fromScale(bodyW * w, 0.11),
			BackgroundColor3 = UiKit.Lighten(theme.Roof, (k - 1) * 0.12),
			ZIndex = 3,
			Parent = holder,
		})
		UiKit.Corner(roof, UDim.new(0.45, 0))
		UiKit.Stroke(roof, UiKit.Darken(theme.Roof, 0.3), 1.5, true)
	end
	-- 지붕 꼭대기 장식 (포인트 색 구슬)
	local top: Frame = Make("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, bodyTop + 0.02 - 2 * 0.095 - 0.1),
		Size = UDim2.fromScale(0.09, 0.09),
		BackgroundColor3 = theme.Accent,
		ZIndex = 4,
		Parent = holder,
	})
	Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = top })
	UiKit.Corner(top, UDim.new(0.5, 0))

	local body: Frame = Make("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, bodyBottom),
		Size = UDim2.fromScale(bodyW, bodyH),
		BackgroundColor3 = theme.Wall,
		ZIndex = 2,
		Parent = holder,
	})
	UiKit.Corner(body, UDim.new(0.12, 0))
	UiKit.Gradient(body)
	UiKit.Stroke(body, UiKit.Darken(theme.Wall, 0.3), 1.5, true)
	local door: Frame = Make("Frame", {
		Name = "Door",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.22, 0.56),
		BackgroundColor3 = theme.Accent,
		ZIndex = 3,
		Parent = body,
	})
	UiKit.Corner(door, UDim.new(0.4, 0))
	for i, x in { 0.2, 0.8 } do
		local win: Frame = Make("Frame", {
			Name = "Window" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.36),
			Size = UDim2.fromScale(0.2, 0.3),
			BackgroundColor3 = UiKit.Lighten(theme.Accent, 0.55),
			ZIndex = 3,
			Parent = body,
		})
		Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = win })
		UiKit.Corner(win, UDim.new(0.3, 0))
		UiKit.Stroke(win, C.White, 1.5, true)
	end
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
	UiKit.Corner(frame, UDim.new(0, 18))
	UiKit.Gradient(frame)
	local stroke = UiKit.Stroke(frame, C.Grey, 4, true)

	-- 집 그림 (하늘색 = 포인트 색을 아주 밝게)
	local preview: Frame = Make("Frame", {
		Name = "Preview",
		BackgroundColor3 = UiKit.Lighten(theme.Accent, 0.72),
		ClipsDescendants = true,
		Parent = frame,
	})
	UiKit.Corner(preview, UDim.new(0, 14))
	UiKit.Stroke(preview, C.White, 3, true)
	drawHouse(preview, theme)

	local nameLabel = UiKit.Label({
		Name = "ThemeName",
		Text = theme.Name,
		Parent = frame,
	}, { Stroke = UiKit.Darken(theme.Roof, 0.4), StrokeThickness = 3, MaxText = 28 })

	-- 크기 + 수익 보너스
	local stats = UiKit.Label({
		Name = "Stats",
		Text = string.format("🏠 크기 %d · %s", theme.Size or 26, bonusText(theme)),
		TextColor3 = C.Ink,
		Parent = frame,
	}, { Stroke = C.White, MaxText = 20 })

	local price: Frame = Make("Frame", {
		Name = "Price",
		BackgroundColor3 = C.Lemon,
		Parent = frame,
	})
	UiKit.Corner(price, UDim.new(0.5, 0))
	UiKit.Stroke(price, C.White, 2, true)
	local priceLabel = UiKit.Label({
		Text = "",
		Size = UDim2.fromScale(0.88, 0.78),
		Position = UDim2.fromScale(0.06, 0.11),
		Parent = price,
	}, { Stroke = UiKit.Darken(C.Lemon, 0.5), MaxText = 22 })

	local button, buttonLabel = UiKit.Button({
		Name = "Apply",
		Text = "🛒 사기",
		Color = C.Pink,
		Radius = UDim.new(0.4, 0),
		TextSize = 26,
		Parent = frame,
		OnClick = function()
			onTheme(themeId)
		end,
	})

	-- 왼쪽 위 리본: "⭐ 우리 집" / "✨ 살 수 있어요!" / "🎯 다음 목표"
	local ribbon: Frame = Make("Frame", {
		Name = "Ribbon",
		Rotation = -6,
		BackgroundColor3 = C.Gold,
		Visible = false,
		ZIndex = 5,
		Parent = frame,
	})
	UiKit.Corner(ribbon, UDim.new(0.5, 0))
	UiKit.Gradient(ribbon)
	UiKit.Stroke(ribbon, C.White, 3, true)
	local ribbonLabel = UiKit.Label({
		Text = "",
		Size = UDim2.fromScale(0.88, 0.78),
		Position = UDim2.fromScale(0.06, 0.11),
		ZIndex = 6,
		Parent = ribbon,
	}, { Stroke = UiKit.Darken(C.Gold, 0.5), MaxText = 20 })

	return {
		Frame = frame,
		Stroke = stroke,
		Preview = preview,
		NameLabel = nameLabel,
		Stats = stats,
		Price = price,
		PriceLabel = priceLabel,
		Button = button,
		ButtonLabel = buttonLabel,
		Ribbon = ribbon,
		RibbonLabel = ribbonLabel,
	}
end

-- 카드 안 배치: 세로 카드 (큰 화면) / 가로 카드 (낮은 화면: 그림 왼쪽, 글자·버튼 오른쪽)
local function applyCardLayout(card: ThemeCard, landscape: boolean)
	local function place(obj: GuiObject, anchor: Vector2, pos: UDim2, size: UDim2)
		obj.AnchorPoint = anchor
		obj.Position = pos
		obj.Size = size
	end
	local v0 = Vector2.zero
	if landscape then
		place(card.Preview, v0, UDim2.fromScale(0.03, 0.08), UDim2.fromScale(0.37, 0.84))
		place(card.NameLabel, v0, UDim2.fromScale(0.43, 0.06), UDim2.fromScale(0.54, 0.22))
		place(card.Stats, v0, UDim2.fromScale(0.43, 0.29), UDim2.fromScale(0.54, 0.14))
		place(card.Price, Vector2.new(0.5, 0), UDim2.fromScale(0.7, 0.45), UDim2.fromScale(0.46, 0.17))
		place(card.Button, Vector2.new(0.5, 1), UDim2.fromScale(0.7, 0.95), UDim2.fromScale(0.54, 0.29))
		place(card.Ribbon, v0, UDim2.new(0, -6, 0, -8), UDim2.fromScale(0.4, 0.2))
	else
		place(card.Preview, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.04), UDim2.fromScale(0.9, 0.4))
		place(card.NameLabel, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.92, 0.12))
		place(card.Stats, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.57), UDim2.fromScale(0.92, 0.08))
		place(card.Price, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.665), UDim2.fromScale(0.72, 0.1))
		place(card.Button, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.965), UDim2.fromScale(0.86, 0.17))
		place(card.Ribbon, v0, UDim2.new(0, -6, 0, -8), UDim2.fromScale(0.62, 0.1))
	end
end

-- 테마 격자: 너비와 보이는 높이에 맞게 칸 수 · 칸 크기 · 카드 모양을 골라요
local function relayoutThemes()
	local scroll = tabScrolls.Themes
	if not scroll then
		return
	end
	local w = UiKit.GridWidth(scroll)
	local viewH = scroll.AbsoluteSize.Y / UiKit.ScaleOf(scroll)
	if w <= 0 or viewH <= 0 then
		return
	end
	local landscape = viewH < 360
	local cols, cw, ch
	if landscape then
		cols = math.clamp(math.floor((w + 10) / 330), 1, 3)
		cw = math.floor((w - (cols - 1) * 10) / cols)
		ch = math.clamp(math.floor(cw * 0.42), 136, 170)
	else
		cols, cw, ch = UiKit.GridCell(w, 190, 1.3, 4)
	end
	themeGrid.CellSize = UDim2.fromOffset(cw, ch)
	local n = 0
	for _ in themeCards do
		n += 1
	end
	local rows = math.ceil(n / cols)
	themeSection.Size = UDim2.new(1, 0, 0, if rows > 0 then rows * ch + (rows - 1) * 10 else 0)
	goalFrame.Size = UDim2.new(1, -8, 0, if landscape then 44 else 54)
	if landscape ~= themeLandscape then
		themeLandscape = landscape
		for _, card in themeCards do
			applyCardLayout(card, landscape)
		end
	end
end

----------------------------------------------------------------------
-- 🏗 층 목록 한 줄
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
	local namePill = UiKit.Pill(frame, if f > MAX_FLOORS then shortFloor(f) else string.format("🏠 %d층", f), C.Peach, {
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
local lastAffordable: string? = nil

local function rebuildThemes(snap: State.Snapshot, have: number)
	local currentTheme = snap.Theme
	local affordable, nextId = themeGoal(snap, have)

	-- 다음 집 안내
	local fillTo = 1
	if affordable then
		local theme = Config.House.Themes[affordable]
		goalLabel.Text = string.format("🎉 %s 살 수 있어요! (%s) 아래에서 🛒 사기", UiKit.Josa(theme.Name, "을", "를"), bonusText(theme))
		goalFrame.BackgroundColor3 = UiKit.Lighten(C.Mint, 0.35)
		goalBar.Visible = false
		if lastAffordable ~= affordable then
			UiKit.Bump(goalFrame, 0.06)
		end
	elseif nextId then
		local theme = Config.House.Themes[nextId]
		goalLabel.Text = string.format("💡 다음 집: %s · 💰 %s 더 모으면 돼요!", theme.Name, Config.FormatNumber(math.max(0, theme.Price - have)))
		goalFrame.BackgroundColor3 = UiKit.Lighten(C.Lemon, 0.55)
		goalBar.Visible = true
		fillTo = if theme.Price > 0 then math.clamp(have / theme.Price, 0, 1) else 1
	else
		goalLabel.Text = "👑 가장 좋은 집을 다 가졌어요! 멋져요!"
		goalFrame.BackgroundColor3 = UiKit.Lighten(C.Gold, 0.45)
		goalBar.Visible = false
	end
	goalFill.Size = UDim2.fromScale(math.max(0.03, fillTo), 1)
	lastAffordable = affordable
	UiKit.ShowBadge(themeBadge, affordable ~= nil)

	for themeId, card in themeCards do
		local theme = Config.House.Themes[themeId]
		local isCurrent = themeId == currentTheme
		local has = ownsTheme(snap, themeId)
		local canBuy = not has and have >= theme.Price
		-- 리본
		if isCurrent then
			card.RibbonLabel.Text = "⭐ 우리 집"
			card.Ribbon.BackgroundColor3 = C.Gold
			card.Ribbon.Visible = true
		elseif themeId == affordable then
			card.RibbonLabel.Text = "✨ 살 수 있어요!"
			card.Ribbon.BackgroundColor3 = C.Pink
			card.Ribbon.Visible = true
		elseif themeId == nextId then
			card.RibbonLabel.Text = "🎯 다음 목표"
			card.Ribbon.BackgroundColor3 = C.Sky
			card.Ribbon.Visible = true
		else
			card.Ribbon.Visible = false
		end
		-- 테두리
		if isCurrent then
			card.Stroke.Color = C.Gold
			card.Stroke.Thickness = 6
		elseif themeId == affordable then
			card.Stroke.Color = C.Pink
			card.Stroke.Thickness = 6
		elseif has then
			card.Stroke.Color = C.White
			card.Stroke.Thickness = 4
		else
			card.Stroke.Color = C.Grey
			card.Stroke.Thickness = 4
		end
		-- 값 / 버튼
		if isCurrent then
			card.PriceLabel.Text = "🏡 지금 사는 집"
			card.Price.BackgroundColor3 = C.Gold
			card.ButtonLabel.Text = "⭐ 사는 중"
			card.Button.BackgroundColor3 = C.Grey
		elseif has then
			card.PriceLabel.Text = "✅ 보유"
			card.Price.BackgroundColor3 = C.Mint
			card.ButtonLabel.Text = "🚚 이사하기"
			card.Button.BackgroundColor3 = C.Mint
		else
			card.PriceLabel.Text = "💰 " .. Config.FormatNumber(theme.Price)
			card.Price.BackgroundColor3 = C.Lemon
			card.ButtonLabel.Text = "🛒 사기"
			card.Button.BackgroundColor3 = if canBuy then C.Pink else C.Lavender
		end
		if not isCurrent and os.clock() <= (moveConfirm[themeId] or 0) then
			card.ButtonLabel.Text = "정말 이사할까요?"
			card.Button.BackgroundColor3 = C.Red
		end
		if isCurrent and lastTheme ~= "" and lastTheme ~= themeId then
			UiKit.Pop(card.Ribbon, 0.4)
			UiKit.Bump(card.Frame, 0.08)
		end
	end
	lastTheme = currentTheme
end

local function rebuildFloors(snap: State.Snapshot, have: number)
	local floors = snap.Floors
	local slots = snap.SlotsUnlocked
	local rebirths = snap.Rebirths
	local here = State.CurrentFloor()

	-- 집 정보
	local plotIdx = State.PlotIndex()
	local where = if plotIdx then string.format("🏠 %d번 집", plotIdx) else "🏠 내 집"
	local bonus = math.floor(Config.ThemeIncomeBonus(snap.Theme) * 100 + 0.5)
	local floorText = if floors > MAX_FLOORS
		then string.format("🏢 %d층 + 🏡 %d층", MAX_FLOORS, floors - MAX_FLOORS)
		else string.format("🏢 %d층", floors)
	infoLabel.Text = string.format("%s · %s · 받침대 %d/%d · 🎨 +%d%%", where, floorText, slots, floors * PER_FLOOR, bonus)

	-- 층 올리기 (큰 버튼). ★v8 10층 다음은 2번 집 짓기
	local nextFloor = floors + 1
	local nextInfo = Config.FloorRequirement(nextFloor)
	local nextName = if nextFloor == MAX_FLOORS + 1 then "🏡 2번 집 짓기" else "🏗 " .. Config.FloorName(nextFloor) .. " 올리기"
	if floors >= TOTAL_FLOORS or not nextInfo then
		floorLabel.Text = "🏰 2번 집까지 완성! ✅"
		floorButton.BackgroundColor3 = C.Grey
	else
		local needSlots, needRebirth = floorNeeds(floors, slots, rebirths)
		if needRebirth then
			floorLabel.Text = string.format("%s\n🔒 환생 %d회 필요", nextName, nextInfo.MinRebirth)
			floorButton.BackgroundColor3 = C.Grey
		elseif needSlots then
			floorLabel.Text = string.format("%s\n받침대 먼저 (%d/%d)", nextName, slots, floors * PER_FLOOR)
			floorButton.BackgroundColor3 = C.Grey
		else
			floorLabel.Text = string.format("%s\n💰 %s", nextName, Config.FormatNumber(nextInfo.Price))
			floorButton.BackgroundColor3 = if have >= nextInfo.Price then C.Mint else C.Lavender
		end
	end

	-- 받침대
	local price = Config.NextSlotPrice(slots, floors)
	if price then
		slotLabel.Text = string.format("➕ 받침대 %d번\n💰 %s", slots + 1, Config.FormatNumber(price))
		slotButton.BackgroundColor3 = if have >= price then C.Peach else C.Lavender
	elseif slots < Config.Plot.TotalSlots then
		slotLabel.Text = "➕ 받침대\n" .. Config.FloorName(floors + 1) .. "이 필요해요"
		slotButton.BackgroundColor3 = C.Grey
	else
		slotLabel.Text = "➕ 받침대\n최대 🎉"
		slotButton.BackgroundColor3 = C.Grey
	end

	-- 층 목록
	for f, row in floorRows do
		local info = Config.FloorRequirement(f)
		local built = f <= floors
		row.Frame.Visible = f <= MAX_FLOORS or showHouse2(floors) -- ★v8
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
end

local function rebuildDecor(snap: State.Snapshot)
	local floors = snap.Floors
	local here = State.CurrentFloor()
	furnLabel.Text = string.format(
		"🛋 집에 놓은 가구 %d/%d개 · 🎒 가구 가방 %d개",
		State.CountPlacedFurniture(),
		Config.Decor.MaxPlaced,
		State.CountFurnitureInv()
	)
	for f, pb in decorFloorButtons do
		pb.Button.Visible = f <= floors
		local isHere = here == f
		pb.Label.Text = if isHere then string.format("📍 %d층", f) else string.format("🏠 %d층", f)
		pb.Button.BackgroundColor3 = if isHere then C.Gold else C.Peach
	end
	if decorFloorsShown ~= floors then
		decorFloorsShown = floors
		decorFloorRelayout()
	end
end

rebuild = function()
	local snap = State.Snapshot
	if not snap then
		return
	end
	local have = coins()
	coinLabel.Text = "💰 " .. Config.FormatNumber(have)
	rebuildThemes(snap, have)
	rebuildFloors(snap, have)
	rebuildDecor(snap)
end

----------------------------------------------------------------------
-- 탭
----------------------------------------------------------------------
local function relayoutTabRow()
	local short = isShort()
	local h = if short then 42 else 50
	tabRow.Size = UDim2.new(1, 0, 0, h)
	for _, id in TAB_IDS do
		local scroll = tabScrolls[id]
		if scroll then
			scroll.Position = UDim2.new(0, 0, 0, h + 6)
			scroll.Size = UDim2.new(1, 0, 1, -(h + 6))
		end
	end
end

local function switchTab(tab: string)
	if not TABS[tab] then
		return
	end
	currentTab = tab
	for id, btn in tabButtons do
		btn.BackgroundColor3 = if id == tab then TABS[id].Color else C.Grey
	end
	for id, scroll in tabScrolls do
		scroll.Visible = id == tab
	end
	if tab == "Themes" then
		relayoutThemes()
	elseif tab == "Decor" then
		decorFloorRelayout()
	end
end

-- (검사용) 지금 보이는 탭
function HouseWindow.CurrentTab(): string
	return currentTab
end

----------------------------------------------------------------------
-- 엘리베이터 층 고르기 창
----------------------------------------------------------------------
local function refreshPicker()
	local snap = State.Snapshot
	local floors = if snap then snap.Floors else 1
	local here = pickerFloor or State.CurrentFloor()
	pickerInfo.Text = if here then string.format("📍 지금 %s · 어디로 갈까요?", Config.FloorName(here)) else "어디로 갈까요? 🛗"
	local show2 = floors > MAX_FLOORS -- ★v8 2번 집이 있으면 그 층 버튼도
	for f, pb in pickerButtons do
		pb.Button.Visible = f <= MAX_FLOORS or show2
		if f <= floors then
			local isHere = f == here
			pb.Label.Text = if isHere then shortFloor(f) .. "\n📍 여기" else shortFloor(f)
			pb.Button.BackgroundColor3 = if isHere then C.Gold elseif f > MAX_FLOORS then C.Mint else C.Sky
		else
			pb.Label.Text = shortFloor(f) .. "\n🔒"
			pb.Button.BackgroundColor3 = C.Grey
		end
	end
	if pickerRelayout then
		pickerRelayout()
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
	for f = 1, TOTAL_FLOORS do
		local btn, label = UiKit.Button({
			Name = "Floor" .. f,
			Text = shortFloor(f),
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
		local shown = 0
		for _, pb in pickerButtons do
			if pb.Button.Visible then
				shown += 1
			end
		end
		local rows = math.max(math.ceil(shown / cols), 1)
		local cw = math.floor((w - (cols - 1) * 8) / cols)
		local ch = math.clamp(math.floor((h - (rows - 1) * 8) / rows), 36, 80)
		grid.CellSize = UDim2.fromOffset(cw, ch)
	end
	gridFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutGrid)
	pickerRelayout = relayoutGrid
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
		OnClick = function()
			decorateFloor(pickerFloor or State.CurrentFloor())
		end,
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
			HouseWindow.Open("Floors")
		end,
	})
end

----------------------------------------------------------------------
-- 만들기: 탭별 내용
----------------------------------------------------------------------
local function newTabScroll(content: Instance, id: string): ScrollingFrame
	local scroll = UiKit.ListScroller(content, {
		Name = id,
		ScrollBarImageColor3 = TABS[id].Color,
		Visible = id == currentTab,
	})
	tabScrolls[id] = scroll
	return scroll
end

local function buildThemesTab(content: Instance)
	local scroll = newTabScroll(content, "Themes")

	-- 다음 집 안내 (글자 + 모은 코인 막대)
	goalFrame = Make("Frame", {
		Name = "Goal",
		Size = UDim2.new(1, -8, 0, 54),
		BackgroundColor3 = UiKit.Lighten(C.Lemon, 0.55),
		LayoutOrder = 1,
		Parent = scroll,
	})
	UiKit.Corner(goalFrame, UDim.new(0, 16))
	UiKit.Stroke(goalFrame, C.White, 3, true)
	goalLabel = UiKit.Label({
		Name = "Text",
		Text = "",
		Position = UDim2.new(0, 12, 0, 4),
		Size = UDim2.new(1, -24, 0.62, -4),
		TextColor3 = C.Ink,
		Parent = goalFrame,
	}, { Stroke = C.White, MaxText = 24 })
	goalBar = Make("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -28, 0.24, 0),
		BackgroundColor3 = C.White,
		Parent = goalFrame,
	})
	UiKit.Corner(goalBar, UDim.new(0.5, 0))
	UiKit.Stroke(goalBar, UiKit.Darken(C.Lemon, 0.15), 2, true)
	goalFill = Make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.03, 1),
		BackgroundColor3 = C.White,
		Parent = goalBar,
	})
	UiKit.Corner(goalFill, UDim.new(0.5, 0))
	Make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.Lemon),
			ColorSequenceKeypoint.new(1, C.Mint),
		}),
		Parent = goalFill,
	})

	-- 집 카드 격자
	themeSection = Make("Frame", {
		Name = "Themes",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = scroll,
	})
	themeGrid = Make("UIGridLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = themeSection,
	})
	for i, themeId in THEME_ORDER do
		if Config.House.Themes[themeId] then
			themeCards[themeId] = createThemeCard(themeSection, themeId, i)
		end
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutThemes)
	relayoutThemes()
end

local function buildFloorsTab(content: Instance)
	local scroll = newTabScroll(content, "Floors")

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

	-- 펫 정리 (자동 배치 / 모두 빼기)
	local toolRow: Frame = Make("Frame", {
		Name = "Tools",
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = scroll,
	})
	UiKit.Button({
		Name = "AutoPlace",
		Text = "✨ 좋은 펫 자동 배치",
		Color = C.Gold,
		Size = UDim2.new(0.5, -5, 1, 0),
		Radius = UDim.new(0.35, 0),
		TextSize = 24,
		Parent = toolRow,
		OnClick = onAutoPlace,
	})
	local clearTap: () -> () = function() end
	local clearBtn, clearLabel = UiKit.Button({
		Name = "ClearBase",
		Text = "📦 집 펫 모두 빼기",
		Color = C.Sky,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -5, 1, 0),
		Radius = UDim.new(0.35, 0),
		TextSize = 24,
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

	-- 층 목록
	UiKit.SectionHeader(scroll, "🏢 우리 집 층 · 🛗 가기", C.Sky, 4, 250)
	local floorList: Frame = Make("Frame", {
		Name = "FloorList",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = scroll,
	})
	Make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = floorList,
	})
	for f = 1, TOTAL_FLOORS do -- ★v8 2번 집 층까지
		floorRows[f] = createFloorRow(floorList, f)
	end
end

local function buildDecorTab(content: Instance)
	local scroll = newTabScroll(content, "Decor")

	-- 가구 수
	local _, label = UiKit.Pill(scroll, "", C.Lavender, {
		Name = "Info",
		Size = UDim2.new(1, -8, 0, 40),
		LayoutOrder = 1,
	}, 22)
	furnLabel = label

	-- 큰 꾸미기 버튼 (지금 있는 층)
	UiKit.Button({
		Name = "Decorate",
		Text = "🪑 가구 꾸미기 시작!",
		Color = C.Pink,
		Size = UDim2.new(1, -8, 0, 62),
		LayoutOrder = 2,
		Radius = UDim.new(0.35, 0),
		TextSize = 30,
		Parent = scroll,
		OnClick = onDecorate,
	})

	-- 어느 층을 꾸밀까요? (있는 층만)
	UiKit.SectionHeader(scroll, "🏢 어느 층을 꾸밀까요?", C.Peach, 3, 250)
	local floorsFrame: Frame = Make("Frame", {
		Name = "DecorFloors",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = scroll,
	})
	for f = 1, MAX_FLOORS do
		local btn, btnLabel = UiKit.Button({
			Name = "DecorFloor" .. f,
			Text = string.format("🏠 %d층", f),
			Color = C.Peach,
			LayoutOrder = f,
			Radius = UDim.new(0.35, 0),
			TextSize = 22,
			Parent = floorsFrame,
			OnClick = function()
				decorateFloor(f)
			end,
		})
		decorFloorButtons[f] = { Button = btn, Label = btnLabel }
	end
	decorFloorRelayout = UiKit.SectionGrid(floorsFrame, scroll, 120, 0.36, 5)

	-- 가구 사기
	local shopRow: Frame = Make("Frame", {
		Name = "Shop",
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundColor3 = UiKit.Lighten(C.Mint, 0.8),
		LayoutOrder = 5,
		Parent = scroll,
	})
	UiKit.Corner(shopRow, UDim.new(0.5, 0))
	UiKit.Stroke(shopRow, C.Mint, 3, true)
	UiKit.Label({
		Text = "가구는 상점에서 사서 🎒 가구 가방에 담아요",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.new(0.6, -16, 0.66, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Ink,
		Parent = shopRow,
	}, { Stroke = C.White, MaxText = 20 })
	UiKit.Button({
		Name = "FurnitureShop",
		Text = "🛍 가구 사기",
		Color = C.Mint,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.new(0.38, 0, 1, -6),
		Radius = UDim.new(0.5, 0),
		TextSize = 24,
		Parent = shopRow,
		OnClick = onFurnitureShop,
	})
end

----------------------------------------------------------------------
-- 만들기
----------------------------------------------------------------------
function HouseWindow.Init(gui: Instance, houseActions: Actions?)
	actions = houseActions or {}
	rootGui = gui
	window = UiKit.Window(gui, { Title = "🏠 내 집", Color = C.Peach, Name = "HouseWindow" })
	local content = window.Content

	-- 탭 줄 + 내 코인
	tabRow = Make("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = content,
	})
	for _, id in TAB_IDS do
		local info = TABS[id]
		local i = info.Order - 1
		local btn = UiKit.Button({
			Name = id,
			Text = info.Text,
			Color = if id == currentTab then info.Color else C.Grey,
			Position = UDim2.new(0.245 * i, 0, 0, 0),
			Size = UDim2.new(0.235, 0, 1, -2),
			Radius = UDim.new(0.35, 0),
			TextSize = 24,
			ZIndex = 24,
			Parent = tabRow,
			OnClick = function()
				switchTab(id)
			end,
		})
		tabButtons[id] = btn
	end
	local badge = UiKit.Badge(tabButtons.Themes, "!", 22)
	badge.Position = UDim2.new(1, -4, 0, 4)
	themeBadge = badge
	local _, coinPillLabel = UiKit.Pill(tabRow, "💰 0", C.Lemon, {
		Name = "Coins",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.new(0.25, -4, 0.84, 0),
		ZIndex = 24,
	}, 22)
	coinLabel = coinPillLabel

	buildThemesTab(content)
	buildFloorsTab(content)
	buildDecorTab(content)
	relayoutTabRow()
	if gui:IsA("GuiBase2d") then
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutTabRow)
	end
	switchTab(currentTab)

	window.OnOpen = function()
		picker.Close()
		rebuild()
		switchTab(currentTab)
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

-- tab = "Themes" (🏡 새 집) | "Floors" (🏗 층·받침대) | "Decor" (🪑 꾸미기).
-- 안 주면: 살 수 있는 새 집이 있으면 새 집 탭, 아니면 마지막에 본 탭 (처음엔 새 집)
function HouseWindow.Open(tab: string?)
	if not window then
		return
	end
	if picker then
		picker.Close()
	end
	local want = currentTab
	if type(tab) == "string" and TABS[tab] then
		want = tab
	elseif HouseWindow.ThemeGoal() ~= nil then
		want = "Themes"
	end
	switchTab(want)
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
