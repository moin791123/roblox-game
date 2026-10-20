-- 🛍 상점 창: 👕 펫 옷 / 🛋️ 가구 사기. (설계: docs/DESIGN.md §10 ShopWindow)
-- 옷은 한 번 사면 영원히 (가방 창의 👕 버튼으로 입혀요), 가구는 가구 가방에 들어가고 "놓으러 가기" 로 꾸미기 모드를 열어요.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

-- 꾸미기 모드는 없거나 오류가 나도 상점은 살아 있게 pcall 로 불러요
local DecorateMode: any = nil
do
	local ok, result = pcall(require, script.Parent.DecorateMode)
	if ok and type(result) == "table" then
		DecorateMode = result
	else
		warn("[ShopWindow] DecorateMode 불러오기 실패:", result)
	end
end

local ShopWindow = {}

----------------------------------------------------------------------
-- 상수
----------------------------------------------------------------------
local SAMPLE_PET = "Cat" -- 옷 미리보기에 입혀 보는 펫
local DECOR = Config.Decor

type TabInfo = { Text: string, Color: Color3, Order: number }
local TABS: { [string]: TabInfo } = {
	Clothes = { Text = "👕 펫 옷", Color = C.Pink, Order = 1 },
	Furniture = { Text = "🛋️ 가구", Color = C.Mint, Order = 2 },
}
local SLOT_NAME: { [string]: string } = { Head = "머리", Face = "얼굴", Neck = "목", Back = "등" }
local SLOT_COLOR: { [string]: Color3 } = { Head = C.Pink, Face = C.Sky, Neck = C.Peach, Back = C.Lavender }
local CATEGORY_COLORS = { C.Pink, C.Sky, C.Mint, C.Peach, C.Lavender, C.Orange, C.Lemon, C.Gold }

type AccCard = {
	Frame: Frame,
	Stroke: UIStroke,
	Holder: Frame,
	Made: boolean,
	Price: Frame,
	PriceLabel: TextLabel,
	Button: TextButton,
	ButtonLabel: TextLabel,
}

type FurnCard = {
	Frame: Frame,
	Stroke: UIStroke,
	Holder: Frame,
	Made: boolean,
	Fits: boolean, -- 지금 집에 놓을 자리가 있나 (없으면 서버가 안 팔아요)
	Price: Frame,
	PriceLabel: TextLabel,
	CountLabel: TextLabel,
	BuyButton: TextButton,
	BuyLabel: TextLabel,
	PlaceButton: TextButton,
}

----------------------------------------------------------------------
-- 상태
----------------------------------------------------------------------
local window: UiKit.Window
local currentTab = "Clothes"
local tabButtons: { [string]: TextButton } = {}
local scrolls: { [string]: ScrollingFrame } = {}
local relayouts: { [string]: { () -> () } } = { Clothes = {}, Furniture = {} }
local accCards: { [string]: AccCard } = {}
local furnCards: { [string]: FurnCard } = {}
local coinLabel: TextLabel
local decorLabel: TextLabel
local dirty = true
local lastFire = 0
local lastOwned: { [string]: boolean } = {}
local lastInv: { [string]: number } = {}
local firstBuild = true

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------
local function fireOnce(fn: () -> ())
	if os.clock() - lastFire < 0.3 then
		return
	end
	lastFire = os.clock()
	fn()
end

local function snapshot(): any
	return State.Snapshot
end

local function coins(): number
	local snap = snapshot()
	return if snap then tonumber(snap.Coins) or 0 else 0
end

local function tableOf(v: any): { [string]: any }
	return if type(v) == "table" then v else {}
end

local function invOf(furnId: string): number
	local snap = snapshot()
	return math.max(0, math.floor(tonumber(tableOf(snap and snap.FurnitureInv)[furnId]) or 0))
end

-- 집에 놓인 개수 (가구 id 별) 와 전체
local function placedCounts(): ({ [string]: number }, number)
	local snap = snapshot()
	local out: { [string]: number } = {}
	local total = 0
	for _, f in tableOf(snap and snap.Furniture) do
		if type(f) == "table" and type(f.Id) == "string" then
			out[f.Id] = (out[f.Id] or 0) + 1
			total += 1
		end
	end
	return out, total
end

local function needCoins(price: number, button: GuiObject)
	Toasts.Show(string.format("코인이 %s 필요해요 💰", Config.FormatNumber(price)), "warn")
	UiKit.Shake(button, 6, 6)
end

-- 지금 집(테마·층 수)에 이 가구를 놓을 자리가 있나? 1층은 울타리 안 마당도 자리라서 거의 다 들어가요.
-- 규칙은 서버와 같은 HouseLayout.FitsInHouse (DecorateMode 를 거쳐요), 결과는 테마·층별로 기억해요. 모르면 true (서버가 다시 검사해요)
local function fitsHouse(furnId: string): boolean
	local snap = snapshot()
	if not snap or not DecorateMode or type(DecorateMode.FitsInHouse) ~= "function" then
		return true
	end
	local theme = if type(snap.Theme) == "string" then snap.Theme else "Basic"
	local ok, fits = pcall(DecorateMode.FitsInHouse, theme, tonumber(snap.Floors) or 1, furnId)
	return not ok or fits ~= false
end

local function samplePet(): string
	if Config.Pets[SAMPLE_PET] then
		return SAMPLE_PET
	end
	return Config.PetOrder[1]
end

----------------------------------------------------------------------
-- 버튼 동작
----------------------------------------------------------------------
local function onBuyAccessory(accId: string)
	local snap = snapshot()
	local def = Config.Accessories[accId]
	local card = accCards[accId]
	if not snap or not def or not card then
		return
	end
	if tableOf(snap.Wardrobe)[accId] == true then
		Toasts.Show("🎒 가방에서 펫을 골라 👕 옷 버튼으로 입혀요!", "info")
		UiKit.Bump(card.Frame, 0.06)
		return
	end
	if coins() < def.Price then
		needCoins(def.Price, card.Button)
		return
	end
	fireOnce(function()
		Remotes.BuyAccessory:FireServer(accId)
		UiKit.PlaySound("Buy")
	end)
end

local function goDecorate(furnId: string?)
	if not State.Plot then
		Toasts.Show("집이 있어야 꾸밀 수 있어요! 🏠", "warn")
		return
	end
	if not DecorateMode then
		Toasts.Show("🛋️ 꾸미기는 곧 열려요!", "info")
		return
	end
	ShopWindow.Close()
	DecorateMode.Enter(nil, furnId)
end

local function onBuyFurniture(furnId: string)
	local def = Config.Furniture[furnId]
	local card = furnCards[furnId]
	local snap = snapshot()
	if not snap or not def or not card then
		return
	end
	-- 지금 집에 자리가 없으면 서버가 안 팔아요 (서버 알림과 같은 말)
	if not fitsHouse(furnId) then
		local okT, better = pcall(DecorateMode.SmallestThemeFor, furnId, tonumber(snap.Floors) or 1)
		if okT and type(better) == "string" then
			Toasts.Show(string.format("🏠 지금 집에는 %s 안 들어가요! '%s' 이상으로 집을 바꾸면 놓을 수 있어요", UiKit.Josa(def.Name, "이", "가"), better), "warn")
		else
			Toasts.Show("🏠 이 가구는 아직 놓을 수 있는 집이 없어요", "warn")
		end
		UiKit.Shake(card.BuyButton, 6, 6)
		return
	end
	if invOf(furnId) >= DECOR.MaxPerItem then
		Toasts.Show(string.format("가구 가방에 %s 최대 %d개까지예요!", UiKit.Josa(def.Name, "은", "는"), DECOR.MaxPerItem), "warn")
		UiKit.Shake(card.BuyButton, 6, 6)
		return
	end
	if coins() < def.Price then
		needCoins(def.Price, card.BuyButton)
		return
	end
	fireOnce(function()
		Remotes.BuyFurniture:FireServer(furnId)
		UiKit.PlaySound("Buy")
	end)
end

local function onPlaceFurniture(furnId: string)
	local card = furnCards[furnId]
	if invOf(furnId) <= 0 then
		Toasts.Show("먼저 사야 해요! 💰 구매를 눌러요", "info")
		if card then
			UiKit.Shake(card.PlaceButton, 5, 6)
		end
		return
	end
	goDecorate(furnId)
end

----------------------------------------------------------------------
-- 카드
----------------------------------------------------------------------
local function createAccCard(parent: Instance, accId: string, order: number): AccCard
	local def = Config.Accessories[accId]
	local frame: Frame = Make("Frame", {
		Name = accId,
		LayoutOrder = order,
		BackgroundColor3 = C.White,
		ZIndex = 24,
		Parent = parent,
	})
	UiKit.Corner(frame, UDim.new(0.1, 0))
	UiKit.Gradient(frame)
	local stroke = UiKit.Stroke(frame, C.Grey, 4, true)

	-- 어디에 입는지 배지
	local slotColor = SLOT_COLOR[def.Slot] or C.Sky
	UiKit.Pill(frame, UiKit.AccessoryIcon(accId) .. " " .. (SLOT_NAME[def.Slot] or ""), slotColor, {
		Name = "Slot",
		Position = UDim2.fromScale(0.05, 0.03),
		Size = UDim2.fromScale(0.5, 0.09),
		ZIndex = 27,
	}, 16)

	local holder: Frame = Make("Frame", {
		Name = "View",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.08, 0.1),
		Size = UDim2.fromScale(0.84, 0.42),
		ZIndex = 25,
		Parent = frame,
	})
	UiKit.Label({
		Name = "AccName",
		Text = def.Name,
		Position = UDim2.fromScale(0.04, 0.53),
		Size = UDim2.fromScale(0.92, 0.1),
		ZIndex = 25,
		Parent = frame,
	}, { Stroke = UiKit.Darken(slotColor, 0.45), MaxText = 22 })

	local price, priceLabel = UiKit.Pill(frame, "", C.Lemon, {
		Name = "Price",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.65),
		Size = UDim2.fromScale(0.74, 0.1),
		ZIndex = 25,
	}, 20)

	local button, buttonLabel = UiKit.Button({
		Name = "Buy",
		Text = "구매",
		Color = C.Pink,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.86, 0.18),
		Radius = UDim.new(0.4, 0),
		TextSize = 22,
		ZIndex = 25,
		Parent = frame,
		OnClick = function()
			onBuyAccessory(accId)
		end,
	})

	return {
		Frame = frame,
		Stroke = stroke,
		Holder = holder,
		Made = false,
		Price = price,
		PriceLabel = priceLabel,
		Button = button,
		ButtonLabel = buttonLabel,
	}
end

local function createFurnCard(parent: Instance, furnId: string, order: number, color: Color3): FurnCard
	local def = Config.Furniture[furnId]
	local frame: Frame = Make("Frame", {
		Name = furnId,
		LayoutOrder = order,
		BackgroundColor3 = C.White,
		ZIndex = 24,
		Parent = parent,
	})
	UiKit.Corner(frame, UDim.new(0.1, 0))
	UiKit.Gradient(frame)
	local stroke = UiKit.Stroke(frame, C.Grey, 4, true)

	local holder: Frame = Make("Frame", {
		Name = "View",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.08, 0.03),
		Size = UDim2.fromScale(0.84, 0.4),
		ZIndex = 25,
		Parent = frame,
	})
	UiKit.Label({
		Name = "FurnName",
		Text = def.Name,
		Position = UDim2.fromScale(0.04, 0.44),
		Size = UDim2.fromScale(0.92, 0.1),
		ZIndex = 25,
		Parent = frame,
	}, { Stroke = UiKit.Darken(color, 0.45), MaxText = 22 })

	local price, priceLabel = UiKit.Pill(frame, "💰 " .. Config.FormatNumber(def.Price), C.Lemon, {
		Name = "Price",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.74, 0.09),
		ZIndex = 25,
	}, 20)

	local countLabel = UiKit.Label({
		Name = "Count",
		Text = "",
		Position = UDim2.fromScale(0.04, 0.655),
		Size = UDim2.fromScale(0.92, 0.085),
		ZIndex = 25,
		Parent = frame,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.45), MaxText = 16 })

	local buyButton, buyLabel = UiKit.Button({
		Name = "Buy",
		Text = "구매",
		Color = C.Pink,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.05, 0.97),
		Size = UDim2.fromScale(0.44, 0.19),
		Radius = UDim.new(0.4, 0),
		TextSize = 20,
		ZIndex = 25,
		Parent = frame,
		OnClick = function()
			onBuyFurniture(furnId)
		end,
	})
	local placeButton = UiKit.Button({
		Name = "Place",
		Text = "놓으러 가기",
		Color = C.Grey,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.95, 0.97),
		Size = UDim2.fromScale(0.44, 0.19),
		Radius = UDim.new(0.4, 0),
		TextSize = 20,
		ZIndex = 25,
		Parent = frame,
		OnClick = function()
			onPlaceFurniture(furnId)
		end,
	})

	return {
		Frame = frame,
		Stroke = stroke,
		Holder = holder,
		Made = false,
		Fits = true,
		Price = price,
		PriceLabel = priceLabel,
		CountLabel = countLabel,
		BuyButton = buyButton,
		BuyLabel = buyLabel,
		PlaceButton = placeButton,
	}
end

-- 뷰포트는 그 탭을 처음 볼 때 만들어요 (창을 안 열면 안 만들어요)
local function ensureViewports(tab: string)
	if tab == "Clothes" then
		local pet = samplePet()
		for accId, card in accCards do
			if not card.Made then
				card.Made = true
				UiKit.Viewport("Pet", pet, card.Holder, false, 1, accId)
			end
		end
	else
		for furnId, card in furnCards do
			if not card.Made then
				card.Made = true
				UiKit.FurnitureViewport(furnId, card.Holder)
			end
		end
	end
end

----------------------------------------------------------------------
-- 다시 그리기
----------------------------------------------------------------------
-- 코인만 바뀌었을 때: 코인 알약 + 살 수 있는지 색
local function refreshCoins()
	if not coinLabel then
		return
	end
	local snap = snapshot()
	local money = coins()
	coinLabel.Text = "💰 " .. Config.FormatNumber(money)
	local wardrobe = tableOf(snap and snap.Wardrobe)
	for accId, card in accCards do
		if wardrobe[accId] ~= true then
			card.Button.BackgroundColor3 = if money >= Config.Accessories[accId].Price then C.Pink else C.Lavender
		end
	end
	for furnId, card in furnCards do
		if card.Fits and invOf(furnId) < DECOR.MaxPerItem then
			card.BuyButton.BackgroundColor3 = if money >= Config.Furniture[furnId].Price then C.Pink else C.Lavender
		end
	end
end

local function rebuild()
	dirty = false
	local snap = snapshot()
	if not snap then
		return
	end
	local wardrobe = tableOf(snap.Wardrobe)
	local placed, totalPlaced = placedCounts()
	local totalInv = 0

	for accId, card in accCards do
		local def = Config.Accessories[accId]
		local owned = wardrobe[accId] == true
		if owned then
			card.PriceLabel.Text = "보유 ✓"
			card.Price.BackgroundColor3 = C.Mint
			card.ButtonLabel.Text = "입히기 👕"
			card.Button.BackgroundColor3 = C.Sky
			card.Stroke.Color = C.Mint
		else
			card.PriceLabel.Text = "💰 " .. Config.FormatNumber(def.Price)
			card.Price.BackgroundColor3 = C.Lemon
			card.ButtonLabel.Text = "구매"
			card.Stroke.Color = C.Grey
		end
		if owned and not firstBuild and not lastOwned[accId] then
			UiKit.Bump(card.Frame, 0.1)
		end
		lastOwned[accId] = owned
	end

	for furnId, card in furnCards do
		local have = invOf(furnId)
		local here = placed[furnId] or 0
		totalInv += have
		card.CountLabel.Text = if here > 0 then string.format("🎒 가방에 %d개 · 🏠 %d", have, here) else string.format("🎒 가방에 %d개", have)
		local fits = fitsHouse(furnId)
		card.Fits = fits
		card.PriceLabel.Text = if fits then "💰 " .. Config.FormatNumber(Config.Furniture[furnId].Price) else "🏠 더 큰 집 필요"
		card.Price.BackgroundColor3 = if fits then C.Lemon else C.Peach
		if not fits then
			card.BuyLabel.Text = "구매"
			card.BuyButton.BackgroundColor3 = C.Grey
		elseif have >= DECOR.MaxPerItem then
			card.BuyLabel.Text = "가득 🎒"
			card.BuyButton.BackgroundColor3 = C.Grey
		else
			card.BuyLabel.Text = "구매"
		end
		card.PlaceButton.BackgroundColor3 = if have > 0 then C.Mint else C.Grey
		card.Stroke.Color = if have > 0 then C.Mint elseif here > 0 then C.Sky else C.Grey
		if not firstBuild and have > (lastInv[furnId] or 0) then
			UiKit.Bump(card.Frame, 0.1)
		end
		lastInv[furnId] = have
	end
	decorLabel.Text = string.format("🏠 집에 %d/%d · 🎒 가방 %d개", totalPlaced, DECOR.MaxPlaced, totalInv)
	firstBuild = false
	refreshCoins()
end

local function switchTab(tab: string)
	if not TABS[tab] then
		return
	end
	currentTab = tab
	for name, btn in tabButtons do
		btn.BackgroundColor3 = if name == tab then TABS[name].Color else C.Grey
	end
	for name, scroll in scrolls do
		scroll.Visible = name == tab
	end
	if window and window.IsOpen() then
		ensureViewports(tab)
	end
	for _, fn in relayouts[tab] do
		fn()
	end
end

----------------------------------------------------------------------
-- 만들기
----------------------------------------------------------------------
local function buildClothesTab(content: Instance)
	local scroll = UiKit.ListScroller(content, {
		Name = "Clothes",
		Position = UDim2.new(0, 0, 0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		ScrollBarImageColor3 = C.Pink,
	})
	scrolls.Clothes = scroll

	UiKit.Pill(scroll, "👕 한 번 사면 영원히 내 옷! 🎒 가방에서 펫에게 입혀요", C.Lavender, {
		Name = "Hint",
		Size = UDim2.new(1, -8, 0, 38),
		LayoutOrder = 1,
	}, 22)

	local section: Frame = Make("Frame", {
		Name = "Accessories",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = scroll,
	})
	for i, accId in Config.AccessoryOrder do
		if Config.Accessories[accId] then
			accCards[accId] = createAccCard(section, accId, i)
		end
	end
	table.insert(relayouts.Clothes, UiKit.SectionGrid(section, scroll, 140, 1.45, 5))
end

local function buildFurnitureTab(content: Instance)
	local scroll = UiKit.ListScroller(content, {
		Name = "Furniture",
		Position = UDim2.new(0, 0, 0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		ScrollBarImageColor3 = C.Mint,
		Visible = false,
	})
	scrolls.Furniture = scroll

	-- 꾸미러 가기 + 내 가구 수
	local top: Frame = Make("Frame", {
		Name = "DecorRow",
		Size = UDim2.new(1, -8, 0, 54),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = scroll,
	})
	UiKit.Button({
		Name = "Decorate",
		Text = "🪑 꾸미러 가기",
		Color = C.Peach,
		Size = UDim2.new(0.42, -5, 1, 0),
		Radius = UDim.new(0.3, 0),
		TextSize = 26,
		Parent = top,
		OnClick = function()
			goDecorate(nil)
		end,
	})
	local _, label = UiKit.Pill(top, "", C.Sky, {
		Name = "Info",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.58, -5, 0, 42),
	}, 22)
	decorLabel = label

	-- 종류별 구역 (Config.FurnitureCategories 순서)
	local byCategory: { [string]: { string } } = {}
	for _, furnId in Config.FurnitureOrder do
		local def = Config.Furniture[furnId]
		if def then
			local list = byCategory[def.Category]
			if not list then
				list = {}
				byCategory[def.Category] = list
			end
			table.insert(list, furnId)
		end
	end
	for i, cat in Config.FurnitureCategories do
		local list = byCategory[cat.Id]
		if list and #list > 0 then
			local color = CATEGORY_COLORS[(i - 1) % #CATEGORY_COLORS + 1]
			UiKit.SectionHeader(scroll, cat.Name, color, 10 + i * 2)
			local section: Frame = Make("Frame", {
				Name = "Cat_" .. cat.Id,
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				LayoutOrder = 11 + i * 2,
				Parent = scroll,
			})
			for j, furnId in list do
				furnCards[furnId] = createFurnCard(section, furnId, j, color)
			end
			table.insert(relayouts.Furniture, UiKit.SectionGrid(section, scroll, 140, 1.6, 5))
		end
	end
end

function ShopWindow.Init(gui: Instance)
	window = UiKit.Window(gui, { Title = "🛍 상점", Color = C.Pink, Name = "ShopWindow" })
	local content = window.Content

	-- 탭 + 내 코인
	local top: Frame = Make("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = content,
	})
	for name, info in TABS do
		local i = info.Order - 1
		local btn = UiKit.Button({
			Name = name,
			Text = info.Text,
			Color = if name == currentTab then info.Color else C.Grey,
			Position = UDim2.new(0.34 * i, 0, 0, 0),
			Size = UDim2.new(0.32, 0, 1, -2),
			Radius = UDim.new(0.35, 0),
			TextSize = 24,
			ZIndex = 24,
			Parent = top,
			OnClick = function()
				switchTab(name)
			end,
		})
		tabButtons[name] = btn
	end
	local _, coinPillLabel = UiKit.Pill(top, "💰 0", C.Lemon, {
		Name = "Coins",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.new(0.3, 0, 0, 40),
		ZIndex = 24,
	}, 22)
	coinLabel = coinPillLabel

	buildClothesTab(content)
	buildFurnitureTab(content)
	switchTab(currentTab)

	window.OnOpen = function()
		ensureViewports(currentTab)
		if dirty then
			rebuild()
		end
		for _, fn in relayouts[currentTab] do
			fn()
		end
	end

	-- 꾸미기 모드의 빈 가방 "🛍 상점" → 가구 탭 (init.client 가 창 닫기까지 하는 함수로 다시 넣어요)
	if DecorateMode and type(DecorateMode.SetShopOpener) == "function" then
		DecorateMode.SetShopOpener(function()
			ShopWindow.Open("Furniture")
		end)
	end

	-- 스냅샷/코인이 바뀌면 (init.client 가 OnSync 를 또 불러도 괜찮아요)
	State.OnSync(function()
		ShopWindow.OnSync()
	end)
	local onCoins = (State :: any).OnCoins
	if type(onCoins) == "function" then
		onCoins(function()
			if window.IsOpen() then
				refreshCoins()
			end
		end)
	end
end

function ShopWindow.OnSync()
	if window and window.IsOpen() then
		rebuild()
	else
		dirty = true
	end
end

-- tab = "Clothes" | "Furniture" (없으면 마지막에 본 탭)
function ShopWindow.Open(tab: string?)
	if not window then
		return
	end
	if tab and TABS[tab] then
		switchTab(tab)
	end
	window.Open()
end

function ShopWindow.Close()
	if window then
		window.Close()
	end
end

function ShopWindow.IsOpen(): boolean
	return window ~= nil and window.IsOpen()
end

return ShopWindow
