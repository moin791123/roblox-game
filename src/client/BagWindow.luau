-- 🎒 가방 창: 내 펫·알 카드 (수익 높은 순, 알은 맨 뒤) + 고른 카드의 자세한 정보와 행동 버튼
-- (따라가기 / 집에 놓기 / 타기 / 들기 / 옷 입히기 / 합성 / 팔기). 위쪽엔 자동 배치·집 펫 모두 빼기·★v7.1 💰 한꺼번에 팔기.
-- ★v7.1 창 머리줄 오른쪽: "가방 n/150" 알약 + ♾ 가방 무한 스위치. 💰 한꺼번에 팔기 창: 테마·등급 고르기 (설정으로 저장),
-- 미리 보기 "n마리 · 💰 X", 팔기 (많으면 두 번), 🤖 자동 판매 스위치 (같은 조건, 서버 PlotService 가 부화 때 팔아요).
-- 카드의 3D 뷰포트는 화면 근처에 보이는 카드에만 만들고 재활용해요 (가방 150 (♾ 500) + 집 120 칸이라 다 만들면 무거워요).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local BagWindow = {}

export type Actions = {
	OpenShop: ((tab: string?) -> ())?, -- 옷이 없을 때 "옷 사러 가기" (init.client 가 상점 창을 열어요)
}

local R = 1.22 -- 카드 높이 / 너비
local MIN_CELL = 112 -- 카드 최소 너비 (px)
local MAX_VIEWPORTS = 30 -- 카드에 붙어 있는 뷰포트 최대 수
local POOL_MAX = 10 -- 재활용 대기 뷰포트 최대 수
local BUILD_PER_STEP = 5 -- 한 번에 새로 만드는 뷰포트 수 (나머지는 다음 프레임)
local WIDE_FROM = 560 -- 창 안쪽 너비가 이 이상이면 오른쪽에 정보 칸을 붙여요

local function Y(u: number): number
	return u / R
end

local LOC_INFO: { [string]: { Text: string, Short: string, Color: Color3 } } = {
	Ride = { Text = "🏇 타는 중", Short = "타는 중", Color = C.Lavender },
	Hold = { Text = "🙌 들고 있음", Short = "들기", Color = C.Orange },
	Follow = { Text = "💕 따라옴", Short = "따라옴", Color = C.Pink },
	Slot = { Text = "🏠 집 받침대", Short = "집", Color = C.Mint },
	Bag = { Text = "🎒 가방", Short = "가방", Color = C.Sky },
}

local WEAR_COLOR = Color3.fromRGB(150, 165, 255)

type Card = {
	Uid: string,
	Item: State.Item,
	Frame: TextButton,
	Stroke: UIStroke,
	Holder: Frame,
	Placeholder: TextLabel,
	NameLabel: TextLabel,
	InfoLabel: TextLabel,
	Tag: Frame?,
	TagLabel: TextLabel?,
	AccBadge: Frame?,
	FuseBadge: Frame?,
	LookKey: string, -- 뷰포트 모습 (종류|id|등급|옷)
	Viewport: GuiObject?,
	ViewKey: string?,
}

type ActionDef = { Text: string, Action: string, Color: Color3 }

local window: UiKit.Window
local actions: Actions = {}
local content: Frame
local tabsRow: Frame
local toolsRow: Frame
local body: Frame
local gridArea: Frame
local scroll: ScrollingFrame
local emptyLabel: TextLabel
local countLabel: TextLabel
local countPill: Frame
local tabButtons: { [string]: TextButton } = {}
local cards: { [string]: Card } = {} -- uid → 카드
local currentTab = "All"
local dirty = true
local lastFire = 0
local wide = true

-- 오른쪽(또는 덮는) 정보 칸
local panel: Frame
local panelScroll: ScrollingFrame
local panelBack: TextButton
local panelEmpty: TextLabel
local panelHolder: Frame
local panelName: TextLabel
local panelPills: Frame
local panelLines: { TextLabel } = {}
local panelButtons: Frame
local panelVp: GuiObject? = nil
local panelModel: Model? = nil
local panelBase: CFrame? = nil
local panelLook = ""
local panelButtonsKey = ""
local selectedUid: string? = nil
local pendingFuse: { Id: string, Tier: number, At: number }? = nil

-- 옷 고르기 창 (가방 창 안에 덮어요)
local wardrobe: TextButton? = nil

-- 합성 재료 수 (rebuild 마다 한 번 세요): "펫id|등급" → 수
local fuseCounts: { [string]: number } = {}

----------------------------------------------------------------------
-- 작은 도우미
----------------------------------------------------------------------

local function fire(uid: string, action: string)
	if os.clock() - lastFire < 0.25 then
		return
	end
	lastFire = os.clock()
	Remotes.PetAction:FireServer(uid, action)
end

local function tierOf(item: State.Item): number
	return if item.Kind == "Pet" then State.ItemTier(item) else 1
end

local function accOf(item: State.Item): string?
	if item.Kind == "Pet" and Config.AccessoryValid(item.Acc) then
		return tostring(item.Acc)
	end
	return nil
end

local function lookKey(item: State.Item): string
	if item.Kind == "Pet" then
		return "Pet|" .. item.Id .. "|" .. tostring(tierOf(item)) .. "|" .. (accOf(item) or "")
	end
	return "Egg|" .. item.Id
end

local function uidNumber(uid: string): number
	return tonumber(string.match(uid, "%d+")) or 0
end

local function countFuse(items: { [string]: State.Item })
	table.clear(fuseCounts)
	for _, item in items do
		if type(item) == "table" and item.Kind == "Pet" and Config.CanFuseLoc(item.Loc) then
			local key = item.Id .. "|" .. tostring(State.ItemTier(item))
			fuseCounts[key] = (fuseCounts[key] or 0) + 1
		end
	end
end

-- 합성 재료로 쓸 수 있는 같은 펫 수 (집 받침대 펫 제외)
local function fusableCount(item: State.Item): number
	return fuseCounts[item.Id .. "|" .. tostring(tierOf(item))] or 0
end

-- 합성 버튼을 보여 줄까? (집 받침대 펫이 아니고, 최고 등급이 아니고, 같은 펫이 3마리 이상)
local function canFuse(item: State.Item): boolean
	return item.Kind == "Pet"
		and Config.CanFuseLoc(item.Loc)
		and tierOf(item) < Config.MaxTier
		and fusableCount(item) >= Config.FuseCount
end

local function cardColors(item: State.Item): (Color3, Color3)
	local _, rarity = UiKit.ItemInfo(item.Kind, item.Id)
	local rc = UiKit.RarityColor(rarity)
	local tier = tierOf(item)
	local border = if tier >= 2 then UiKit.TierColor(tier) else rc
	return UiKit.Lighten(border, 0.82), border
end

-- "⚖️ 3.2kg · 거대 🐘" 같은 크기 줄
local function sizeLine(item: State.Item): string
	local size = Config.SizeOf(item)
	local tag = Config.SizeLabel(size, item.Id) -- ★v7 희귀 펫은 그 펫 범위 기준
	local text = string.format("⚖️ %.1fkg", Config.PetWeight(item.Id, size))
	if tag == "거대" then
		return text .. " · 거대 🐘"
	elseif tag == "꼬마" then
		return text .. " · 꼬마 🐭"
	end
	return text
end

-- 알 부화 남은 시간
local function eggLine(item: State.Item, short: boolean): string
	if item.Loc == "Slot" then
		local left = math.ceil((tonumber(item.HatchAt) or 0) - workspace:GetServerTimeNow())
		if left <= 0 then
			return if short then "🐣 곧 부화!" else "🐣 곧 부화해요!"
		end
		return if short then string.format("⏱ %d초", left) else string.format("⏱ 부화까지 %d초", left)
	end
	local left = math.max(0, math.ceil(tonumber(item.HatchLeft) or 0))
	return if short then string.format("⏸ %d초", left) else string.format("⏸ %d초 (집 받침대에 놓으면 부화)", left)
end

local function cardInfo(item: State.Item): string
	if item.Kind == "Pet" then
		return "💰 " .. UiKit.IncomeText(State.RealIncome(item)) .. "/초"
	end
	return eggLine(item, true)
end

local function displayName(item: State.Item): string
	if item.Kind == "Egg" then
		local name = UiKit.ItemInfo(item.Kind, item.Id)
		return "🥚 " .. (name or item.Id)
	end
	return Config.PetDisplayName(item.Id, tierOf(item))
end

----------------------------------------------------------------------
-- 뷰포트 재활용 (같은 모습이면 다시 써요)
----------------------------------------------------------------------
local pool: { { Key: string, Gui: GuiObject } } = {}
local vpQueued = false
local refreshViewports: () -> ()

local function poolTake(key: string): GuiObject?
	for i = #pool, 1, -1 do
		if pool[i].Key == key then
			local g = pool[i].Gui
			table.remove(pool, i)
			return g
		end
	end
	return nil
end

local function poolPut(key: string, g: GuiObject)
	g.Parent = nil
	table.insert(pool, { Key = key, Gui = g })
	while #pool > POOL_MAX do
		local old = table.remove(pool, 1)
		if old then
			old.Gui:Destroy()
		end
	end
end

local function attachViewport(card: Card)
	local key = card.LookKey
	local g = poolTake(key)
	if g then
		g.Parent = card.Holder
	else
		local item = card.Item
		g = UiKit.Viewport(item.Kind, item.Id, card.Holder, false, tierOf(item), accOf(item))
	end
	card.Viewport = g
	card.ViewKey = key
	card.Placeholder.Visible = false
end

local function detachViewport(card: Card)
	local g = card.Viewport
	if g then
		card.Viewport = nil
		poolPut(card.ViewKey or "", g)
		card.ViewKey = nil
	end
	card.Placeholder.Visible = true
end

local function queueViewports()
	if vpQueued then
		return
	end
	vpQueued = true
	task.delay(0.05, function()
		vpQueued = false
		refreshViewports()
	end)
end

-- 스크롤 영역(+ 위아래 반 화면) 안의 카드에만 뷰포트. 가운데에 가까운 카드부터 MAX_VIEWPORTS 개까지
refreshViewports = function()
	if not window or not window.IsOpen() then
		return
	end
	local top = scroll.AbsolutePosition.Y
	local height = scroll.AbsoluteSize.Y
	if height <= 0 then
		return
	end
	local margin = height * 0.5
	local mid = top + height / 2
	local want: { { Card: Card, D: number } } = {}
	for _, card in cards do
		local f = card.Frame
		if f.Visible then
			local y = f.AbsolutePosition.Y
			local h = f.AbsoluteSize.Y
			if y + h >= top - margin and y <= top + height + margin then
				table.insert(want, { Card = card, D = math.abs(y + h / 2 - mid) })
			end
		end
	end
	table.sort(want, function(a, b)
		return a.D < b.D
	end)
	local keep: { [Card]: boolean } = {}
	for i = 1, math.min(#want, MAX_VIEWPORTS) do
		keep[want[i].Card] = true
	end
	for _, card in cards do
		if card.Viewport and (not keep[card] or card.ViewKey ~= card.LookKey) then
			detachViewport(card)
		end
	end
	local made = 0
	for i = 1, math.min(#want, MAX_VIEWPORTS) do
		local card = want[i].Card
		if not card.Viewport then
			if made >= BUILD_PER_STEP then
				queueViewports() -- 나머지는 조금 뒤에
				return
			end
			attachViewport(card)
			made += 1
		end
	end
end

----------------------------------------------------------------------
-- 카드
----------------------------------------------------------------------
local selectItem: (uid: string) -> ()

local function smallBadge(parent: Instance, text: string, color: Color3, anchor: Vector2, pos: UDim2, size: number): Frame
	local badge: Frame = Make("Frame", {
		AnchorPoint = anchor,
		Position = pos,
		Size = UDim2.fromScale(size, Y(size)),
		BackgroundColor3 = color,
		ZIndex = 27,
		Parent = parent,
	})
	UiKit.Corner(badge, UDim.new(0.5, 0))
	UiKit.Stroke(badge, C.White, 2, true)
	UiKit.Label({ Text = text, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), ZIndex = 28, Parent = badge }, { MaxText = 26 })
	return badge
end

local function createCard(uid: string, item: State.Item): Card?
	local name = UiKit.ItemInfo(item.Kind, item.Id)
	if not name then
		return nil
	end
	local bg, border = cardColors(item)
	local tier = tierOf(item)
	local frame: TextButton = Make("TextButton", {
		Name = uid,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = bg,
		ZIndex = 24,
		Parent = scroll,
	})
	UiKit.Corner(frame, UDim.new(0.12, 0))
	local stroke = UiKit.Stroke(frame, border, if tier >= 2 then 5 else 4, true)

	local holder: Frame = Make("Frame", {
		Name = "Viewport",
		Position = UDim2.fromScale(0.07, Y(0.05)),
		Size = UDim2.fromScale(0.86, Y(0.76)),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.25,
		ClipsDescendants = true,
		ZIndex = 25,
		Parent = frame,
	})
	UiKit.Corner(holder, UDim.new(0.18, 0))
	local placeholder = UiKit.Label({
		Text = if item.Kind == "Egg" then "🥚" else "🐾",
		TextTransparency = 0.6,
		Size = UDim2.fromScale(0.5, 0.5),
		Position = UDim2.fromScale(0.25, 0.25),
		ZIndex = 26,
		Parent = holder,
	}, { MaxText = 40 })

	-- ★v6 아주 희귀한 펫·알 (시크릿 / 천상 / 이터널): 왼쪽 위 🌟 배지 (단계 색)
	local special = if item.Kind == "Pet" then UiKit.PetSpecial(item.Id) else UiKit.EggSpecial(item.Id)
	if special then
		smallBadge(frame, "🌟", UiKit.RarityColor(special), Vector2.new(0, 0), UDim2.fromScale(0.03, Y(0.02)), 0.27)
	end

	-- 등급 배지 (브론즈 이상, 오른쪽 위). 등급은 같은 uid 에서 안 바뀌어요 (합성하면 새 펫)
	if item.Kind == "Pet" and tier >= 2 then
		smallBadge(frame, UiKit.TierEmoji(tier), UiKit.TierColor(tier), Vector2.new(1, 0), UDim2.fromScale(0.97, Y(0.02)), 0.27)
	end

	local nameLabel = UiKit.Label({
		Name = "ItemName",
		Text = displayName(item),
		Position = UDim2.fromScale(0.04, Y(0.83)),
		Size = UDim2.fromScale(0.92, Y(0.16)),
		ZIndex = 25,
		Parent = frame,
	}, { Stroke = UiKit.Darken(border, 0.5), MaxText = 22 })
	local infoLabel = UiKit.Label({
		Name = "Info",
		Position = UDim2.fromScale(0.05, Y(1.0)),
		Size = UDim2.fromScale(0.9, Y(0.15)),
		TextColor3 = C.Ink,
		ZIndex = 25,
		Parent = frame,
	}, { Stroke = C.White, MaxText = 20 })

	local card: Card = {
		Uid = uid,
		Item = item,
		Frame = frame,
		Stroke = stroke,
		Holder = holder,
		Placeholder = placeholder,
		NameLabel = nameLabel,
		InfoLabel = infoLabel,
		LookKey = lookKey(item),
	}
	frame.Activated:Connect(function()
		UiKit.PlaySound("Click")
		selectItem(uid)
	end)
	return card
end

local function setSelectedLook(card: Card, selected: boolean)
	local _, border = cardColors(card.Item)
	card.Stroke.Color = if selected then C.Gold else border
	card.Stroke.Thickness = if selected then 7 elseif tierOf(card.Item) >= 2 then 5 else 4
end

local function updateCard(card: Card, item: State.Item)
	card.Item = item
	-- 위치 표시 (가방이 아니면 왼쪽 위)
	if item.Loc ~= "Bag" then
		local info = LOC_INFO[item.Loc] or LOC_INFO.Bag
		local tag = card.Tag
		local tagLabel = card.TagLabel
		if not tag or not tagLabel then
			tag = Make("Frame", {
				Name = "Loc",
				Position = UDim2.fromScale(0.03, Y(0.03)),
				Size = UDim2.fromScale(0.5, Y(0.17)),
				ZIndex = 27,
				Parent = card.Frame,
			})
			UiKit.Corner(tag, UDim.new(0.5, 0))
			UiKit.Stroke(tag, C.White, 2, true)
			tagLabel = UiKit.Label({ Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), ZIndex = 28, Parent = tag }, { MaxText = 18 })
			card.Tag = tag
			card.TagLabel = tagLabel
		end
		if tag and tagLabel then
			tag.Visible = true
			tag.BackgroundColor3 = info.Color
			tagLabel.Text = info.Short
			local stroke = tagLabel:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = UiKit.Darken(info.Color, 0.45)
			end
		end
	elseif card.Tag then
		card.Tag.Visible = false
	end
	-- 옷 배지 (왼쪽 아래)
	if accOf(item) then
		if not card.AccBadge then
			card.AccBadge = smallBadge(card.Frame, "👕", WEAR_COLOR, Vector2.new(0, 1), UDim2.fromScale(0.04, Y(0.8)), 0.24)
		end
		local badge = card.AccBadge
		if badge then
			badge.Visible = true
		end
	elseif card.AccBadge then
		card.AccBadge.Visible = false
	end
	-- 합성 가능 배지 (오른쪽 아래)
	if canFuse(item) then
		if not card.FuseBadge then
			card.FuseBadge = smallBadge(card.Frame, "✨", C.Gold, Vector2.new(1, 1), UDim2.fromScale(0.96, Y(0.8)), 0.24)
		end
		local badge = card.FuseBadge
		if badge then
			badge.Visible = true
		end
	elseif card.FuseBadge then
		card.FuseBadge.Visible = false
	end
	card.InfoLabel.Text = cardInfo(item)
	local key = lookKey(item)
	if key ~= card.LookKey then
		card.LookKey = key -- 옷을 바꿨어요: 다음 refreshViewports 가 새로 그려요
	end
	setSelectedLook(card, card.Uid == selectedUid)
end

local function destroyCard(card: Card)
	detachViewport(card)
	card.Frame:Destroy()
end

local function matchesTab(item: State.Item): boolean
	if currentTab == "All" then
		return true
	elseif currentTab == "Home" then
		return item.Loc == "Slot"
	end
	return item.Kind == currentTab
end

----------------------------------------------------------------------
-- 옷 입히기 (옷장에서 고르기)
----------------------------------------------------------------------
local function closeWardrobe()
	local w = wardrobe
	if w then
		wardrobe = nil
		w:Destroy()
	end
end

local function goShop()
	closeWardrobe()
	local open = actions.OpenShop
	if open then
		open("Clothes")
	else
		Toasts.Show("🛍 상점(P)에서 옷을 살 수 있어요!", "info")
	end
end

local function equip(uid: string, accId: string)
	if os.clock() - lastFire < 0.25 then
		return
	end
	lastFire = os.clock()
	-- 알림(입혔어요/벗겼어요)은 서버 ShopService 가 보내요 (여기서 또 띄우면 두 번 나와요)
	Remotes.EquipAccessory:FireServer(uid, accId)
	closeWardrobe()
end

local function openWardrobe(uid: string)
	closeWardrobe()
	local item = State.Items()[uid]
	if not item or item.Kind ~= "Pet" then
		return
	end
	local current = accOf(item)
	local owned = State.OwnedAccessories()

	local overlay: TextButton = Make("TextButton", {
		Name = "Wardrobe",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(45, 25, 70),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
		Parent = content,
	})
	overlay.Activated:Connect(closeWardrobe)
	wardrobe = overlay
	-- 안쪽을 눌러도 닫히지 않게 버튼으로 (아무 일도 안 해요)
	local sheet: TextButton = Make("TextButton", {
		Name = "Sheet",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.96, 0.96),
		BackgroundColor3 = C.Cream,
		ZIndex = 41,
		Parent = overlay,
	})
	Make("UISizeConstraint", { MaxSize = Vector2.new(640, 470), Parent = sheet })
	UiKit.Corner(sheet, UDim.new(0, 20))
	UiKit.Stroke(sheet, WEAR_COLOR, 5, true)
	UiKit.Pop(sheet, 0.3)

	UiKit.Label({
		Text = "👕 옷 입히기 · " .. Config.PetDisplayName(item.Id, tierOf(item)),
		Position = UDim2.new(0, 14, 0, 8),
		Size = UDim2.new(1, -28, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 42,
		Parent = sheet,
	}, { Stroke = UiKit.Darken(WEAR_COLOR, 0.45), StrokeThickness = 3, MaxText = 28 })

	local bottom: Frame = Make("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -8),
		Size = UDim2.new(1, -20, 0, 46),
		BackgroundTransparency = 1,
		ZIndex = 42,
		Parent = sheet,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bottom,
	})

	if #owned == 0 then
		UiKit.Label({
			Text = "아직 옷이 없어요! 👕\n상점에서 귀여운 옷을 사 보세요",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.new(0.86, 0, 0.4, 0),
			TextColor3 = C.Ink,
			ZIndex = 42,
			Parent = sheet,
		}, { Stroke = C.White, MaxText = 30 })
		UiKit.Button({
			Text = "🛍 옷 사러 가기",
			Color = C.Mint,
			Size = UDim2.new(0.6, 0, 1, 0),
			LayoutOrder = 1,
			ZIndex = 43,
			TextSize = 26,
			Parent = bottom,
			OnClick = goShop,
		})
		UiKit.Button({
			Text = "닫기",
			Color = C.Grey,
			Size = UDim2.new(0.3, 0, 1, 0),
			LayoutOrder = 2,
			ZIndex = 43,
			TextSize = 24,
			Parent = bottom,
			OnClick = closeWardrobe,
		})
		return
	end

	local list = UiKit.Scroller(sheet, {
		Position = UDim2.new(0, 8, 0, 46),
		Size = UDim2.new(1, -16, 1, -104),
		ScrollBarImageColor3 = WEAR_COLOR,
		ZIndex = 42,
	})
	UiKit.AutoGrid(list, 96, 1.22, 6)
	for i, accId in owned do
		local def = Config.Accessories[accId]
		local wearing = accId == current
		local cell: TextButton = Make("TextButton", {
			Name = accId,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
			BackgroundColor3 = if wearing then UiKit.Lighten(C.Gold, 0.6) else UiKit.Lighten(WEAR_COLOR, 0.75),
			ZIndex = 43,
			Parent = list,
		})
		UiKit.Corner(cell, UDim.new(0.14, 0))
		UiKit.Stroke(cell, if wearing then C.Gold else WEAR_COLOR, if wearing then 5 else 3, true)
		local holder: Frame = Make("Frame", {
			Position = UDim2.fromScale(0.08, 0.05),
			Size = UDim2.fromScale(0.84, 0.62),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.3,
			ClipsDescendants = true,
			ZIndex = 44,
			Parent = cell,
		})
		UiKit.Corner(holder, UDim.new(0.2, 0))
		UiKit.Viewport("Accessory", accId, holder, false)
		UiKit.Label({
			Text = UiKit.AccessoryIcon(accId) .. " " .. def.Name,
			Position = UDim2.fromScale(0.05, 0.69),
			Size = UDim2.fromScale(0.9, 0.16),
			ZIndex = 44,
			Parent = cell,
		}, { Stroke = UiKit.Darken(WEAR_COLOR, 0.5), MaxText = 20 })
		UiKit.Label({
			Text = if wearing then "✓ 입는 중" else "입히기",
			Position = UDim2.fromScale(0.05, 0.85),
			Size = UDim2.fromScale(0.9, 0.12),
			TextColor3 = C.Ink,
			ZIndex = 44,
			Parent = cell,
		}, { Stroke = C.White, MaxText = 16 })
		cell.Activated:Connect(function()
			UiKit.PlaySound("Click")
			if wearing then
				Toasts.Show("이미 입고 있어요! 😊", "info")
				return
			end
			equip(uid, accId)
		end)
	end
	if current then
		UiKit.Button({
			Text = "🚫 벗기기",
			Color = C.Peach,
			Size = UDim2.new(0.3, 0, 1, 0),
			LayoutOrder = 1,
			ZIndex = 43,
			TextSize = 24,
			Parent = bottom,
			OnClick = function()
				equip(uid, "")
			end,
		})
	end
	UiKit.Button({
		Text = "🛍 옷 더 사기",
		Color = C.Mint,
		Size = UDim2.new(0.34, 0, 1, 0),
		LayoutOrder = 2,
		ZIndex = 43,
		TextSize = 24,
		Parent = bottom,
		OnClick = goShop,
	})
	UiKit.Button({
		Text = "닫기",
		Color = C.Grey,
		Size = UDim2.new(0.24, 0, 1, 0),
		LayoutOrder = 3,
		ZIndex = 43,
		TextSize = 24,
		Parent = bottom,
		OnClick = closeWardrobe,
	})
end

----------------------------------------------------------------------
-- 정보 칸 (고른 펫/알)
----------------------------------------------------------------------
local function actionsFor(item: State.Item): { ActionDef }
	local defs: { ActionDef } = {}
	if item.Kind == "Pet" then
		local tier = tierOf(item)
		if item.Loc == "Follow" then
			table.insert(defs, { Text = "💤 그만 따라오기", Action = "Unfollow", Color = C.Lavender })
		elseif item.Loc ~= "Ride" then
			table.insert(defs, { Text = "💕 따라가기", Action = "Follow", Color = C.Pink })
		end
		if item.Loc == "Slot" then
			table.insert(defs, { Text = "🎒 가방에", Action = "ToBag", Color = C.Sky })
		else
			table.insert(defs, { Text = "🏠 집에 놓기", Action = "ToBase", Color = C.Mint })
		end
		if item.Loc == "Ride" then
			table.insert(defs, { Text = "🛑 내리기", Action = "Unride", Color = C.Peach })
		else
			table.insert(defs, { Text = "🏇 타기", Action = "Ride", Color = C.Peach })
		end
		if item.Loc == "Hold" then
			table.insert(defs, { Text = "👇 내려놓기", Action = "Unhold", Color = C.Orange })
		else
			table.insert(defs, { Text = "🙌 들기", Action = "Hold", Color = C.Orange })
		end
		table.insert(defs, { Text = "👕 옷 입히기", Action = "Wear", Color = WEAR_COLOR })
		if canFuse(item) then
			table.insert(defs, { Text = "✨ 합성", Action = "Fuse", Color = C.Gold })
		end
		table.insert(defs, { Text = "💰 팔기 " .. Config.FormatNumber(Config.SellPrice(item.Id, tier)), Action = "Sell", Color = C.Orange })
	else
		if item.Loc == "Bag" then
			table.insert(defs, { Text = "🏠 집에 놓기", Action = "ToBase", Color = C.Mint })
		else
			table.insert(defs, { Text = "🎒 가방에", Action = "ToBag", Color = C.Sky })
		end
	end
	return defs
end

local function onAction(def: ActionDef, uid: string)
	local item = State.Items()[uid]
	if not item then
		return
	end
	if def.Action == "Wear" then
		openWardrobe(uid)
		return
	elseif def.Action == "Fuse" then
		if item.Loc == "Slot" then
			Toasts.Show("🏠 집에 있는 펫은 합성할 수 없어요! 가방에 넣고 해 보세요 🎒", "warn")
			return
		end
		local n = fusableCount(item)
		if n < Config.FuseCount then
			Toasts.Show(string.format("같은 펫 %d마리가 필요해요! (%d/%d)", Config.FuseCount, n, Config.FuseCount), "warn")
			return
		end
		pendingFuse = { Id = item.Id, Tier = tierOf(item) + 1, At = os.clock() }
	end
	-- 타기/들기 알림은 서버가 보내요 (가방이 가득 차서 안 될 때도 서버가 알려 줘요)
	fire(uid, def.Action)
end

local function buildPanelButtons(uid: string, item: State.Item)
	for _, child in panelButtons:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, def in actionsFor(item) do
		local tap: () -> () = function() end
		local btn, label = UiKit.Button({
			Name = def.Action,
			Text = def.Text,
			Color = def.Color,
			LayoutOrder = i,
			Radius = UDim.new(0.35, 0),
			TextSize = 22,
			ZIndex = 26,
			Parent = panelButtons,
			OnClick = function()
				tap()
			end,
		})
		if def.Action == "Sell" then
			-- 2초 안에 두 번 눌러야 팔려요
			tap = UiKit.TwoTap(btn, label, "정말 팔까요? 💰", function()
				fire(uid, "Sell")
			end)
		else
			tap = function()
				onAction(def, uid)
			end
		end
	end
end

local function pill(parent: Instance, text: string, color: Color3, order: number)
	UiKit.Pill(parent, text, color, { Size = UDim2.new(0.32, -4, 1, 0), LayoutOrder = order, ZIndex = 26 }, 18)
end

local function setPanelViewport(item: State.Item?)
	local key = if item then lookKey(item) else ""
	if key == panelLook then
		return
	end
	panelLook = key
	if panelVp then
		panelVp:Destroy()
		panelVp = nil
	end
	panelModel = nil
	panelBase = nil
	if item then
		local vp, model = UiKit.Viewport(item.Kind, item.Id, panelHolder, false, tierOf(item), accOf(item))
		panelVp = vp
		panelModel = model
		panelBase = if model then model:GetPivot() else nil
	end
end

local function renderPanel()
	if not panel then
		return
	end
	local item = if selectedUid then State.Items()[selectedUid] else nil
	if not item or not UiKit.ItemInfo(item.Kind, item.Id) then
		selectedUid = nil
		panelEmpty.Visible = true
		panelScroll.Visible = false
		setPanelViewport(nil)
		panelButtonsKey = ""
		if not wide then
			panel.Visible = false
		end
		return
	end
	local uid = selectedUid :: string
	panelEmpty.Visible = false
	panelScroll.Visible = true
	setPanelViewport(item)
	local _, border = cardColors(item)
	panelName.Text = displayName(item)
	local nameStroke = panelName:FindFirstChildOfClass("UIStroke")
	if nameStroke then
		nameStroke.Color = UiKit.Darken(border, 0.5)
	end

	-- 알약 줄: 희귀도 / 등급 / 위치
	for _, child in panelPills:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local _, rarity, rinfo = UiKit.ItemInfo(item.Kind, item.Id)
	local rname = if rinfo then rinfo.Name else UiKit.RarityName(rarity)
	local special = if item.Kind == "Pet" then UiKit.PetSpecial(item.Id) else UiKit.EggSpecial(item.Id)
	if special then
		rname = "🌟 " .. UiKit.SpecialStars(special) .. " " .. UiKit.RarityName(special) -- ★v6
	end
	pill(panelPills, if rname ~= "" then rname else "?", UiKit.RarityColor(special or rarity), 1)
	local tier = tierOf(item)
	if item.Kind == "Pet" and tier >= 2 then
		pill(panelPills, UiKit.TierLabel(tier), UiKit.TierColor(tier), 2)
	end
	local loc = LOC_INFO[item.Loc] or LOC_INFO.Bag
	pill(panelPills, loc.Text, loc.Color, 3)

	-- 정보 줄
	local lines: { string } = {}
	if item.Kind == "Pet" then
		table.insert(lines, "💰 집에서 +" .. UiKit.IncomeText(State.RealIncome(item)) .. "/초")
		local boost = math.floor(Config.PetBoost(item.Id, tier) * 100 + 0.5)
		table.insert(lines, string.format("🍀 코인 +%d%% · 🏇 ×%.2f", boost, Config.RideSpeedMultiplier(item.Id, tier, Config.SizeOf(item))))
		table.insert(lines, sizeLine(item))
		local acc = accOf(item)
		table.insert(lines, if acc then "👕 " .. (UiKit.AccessoryName(acc) or acc) else "👕 옷 없음")
		if tier >= Config.MaxTier then
			table.insert(lines, "🌌 최고 등급이에요!")
		elseif item.Loc == "Slot" then
			table.insert(lines, "🏠 집 펫은 합성 재료가 안 돼요")
		else
			local n = fusableCount(item)
			table.insert(lines, if n >= Config.FuseCount
				then string.format("✨ 합성할 수 있어요! (%d/%d)", n, Config.FuseCount)
				else string.format("✨ 같은 펫 %d/%d마리", n, Config.FuseCount))
		end
	else
		table.insert(lines, eggLine(item, false))
		local egg = Config.Eggs[item.Id]
		local zone = if egg then Config.Zones[egg.Zone] else nil
		if zone then
			table.insert(lines, "🗺 " .. zone.Emoji .. " " .. zone.Name .. " 알")
		end
		-- ★v6 희귀 알: 꼭 나오는 펫
		local petId = if special then UiKit.SpecialPet(item.Id) else nil
		local pet = if petId then Config.Pets[petId] else nil
		if pet then
			table.insert(lines, "🎁 " .. pet.Name .. " 확정!")
		end
	end
	for i, label in panelLines do
		local text = lines[i]
		label.Visible = text ~= nil
		label.Text = text or ""
	end

	local key = uid .. ":" .. item.Kind .. ":" .. item.Loc .. ":" .. tostring(canFuse(item)) .. ":" .. tostring(tier)
	if key ~= panelButtonsKey then
		panelButtonsKey = key
		buildPanelButtons(uid, item)
	end
	if not wide then
		panel.Visible = true
	end
end

selectItem = function(uid: string)
	local prev = selectedUid
	selectedUid = uid
	if prev and cards[prev] then
		setSelectedLook(cards[prev], false)
	end
	local card = cards[uid]
	if card then
		setSelectedLook(card, true)
		UiKit.Bump(card.Frame, 0.06)
	end
	renderPanel()
	if not wide then
		UiKit.Pop(panel, 0.25)
	elseif prev ~= uid then
		UiKit.Bump(panelHolder, 0.08)
	end
end

local function clearSelection()
	local prev = selectedUid
	selectedUid = nil
	if prev and cards[prev] then
		setSelectedLook(cards[prev], false)
	end
	renderPanel()
end

-- 합성하면 고른 펫이 없어져요: 방금 생긴 한 단계 위 펫을 대신 골라요
local function findFuseResult(items: { [string]: State.Item }): string?
	local pf = pendingFuse
	if not pf or os.clock() - pf.At > 6 then
		return nil
	end
	local best: string? = nil
	for uid, item in items do
		if type(item) == "table" and item.Kind == "Pet" and item.Id == pf.Id and State.ItemTier(item) == pf.Tier then
			if not best or uidNumber(uid) > uidNumber(best) then
				best = uid
			end
		end
	end
	if best then
		pendingFuse = nil
	end
	return best
end

----------------------------------------------------------------------
-- ★v7.1 ♾ 가방 무한 스위치 / 💰 한꺼번에 팔기 창 (+ 🤖 자동 판매 스위치)
-- 고른 테마·등급은 설정으로 저장해요 (SellZoneMax / SellRarityMax) → 서버의 자동 판매도 같은 조건을 써요.
-- 팔리는 펫은 서버와 같은 Config.SellMatch: 가방 펫만, 옷 입은 펫·🥇 골드 이상·시크릿/천상/이터널은 절대 안 팔아요
----------------------------------------------------------------------
local OFF_FACE = Color3.fromRGB(190, 190, 206) -- Hud 켜고 끄는 버튼과 같은 회색
local OFF_TRACK = Color3.fromRGB(125, 125, 145)
local INFINITE_COLOR = Color3.fromRGB(110, 190, 255)
local AUTO_COLOR = Color3.fromRGB(95, 200, 160)
local SEND_DELAY = 0.4 -- 테마·등급을 연달아 누르면 마지막 값만 서버로
local SELL_HINT = "🎒 가방 펫만 · 🛡 옷·골드 이상·희귀는 지켜요"
local AUTO_NOTE = "새로 태어난 펫이 이 조건이면 바로 팔아요 · 처음 본 펫과 브론즈 이상은 지켜요"

type Switch = {
	Button: TextButton, -- 누르는 칸 (≥ 44 px, 투명)
	Face: Frame, -- 보이는 알약
	Caption: TextLabel,
	Track: Frame,
	Knob: Frame,
	StateLabel: TextLabel,
	Color: Color3,
	Shown: boolean?,
}

type Stepper = { Frame: Frame, Down: TextButton, Up: TextButton, Face: Frame, Caption: TextLabel, Value: TextLabel }
type ToolButton = { Button: TextButton, Label: TextLabel, Long: string, Short: string }

local headerBox: Frame -- 창 머리줄 오른쪽 (가방 칸 알약 + ♾ 스위치)
local bagSwitch: Switch
local toolButtons: { ToolButton } = {}
local sellOverlay: TextButton
local sellSheet: TextButton
local sellTitle: TextLabel
local sellHint: TextLabel
local sellClose: TextButton
local zoneStep: Stepper
local rarityStep: Stepper
local previewFace: Frame
local previewLabel: TextLabel
local sellButton: TextButton
local sellLabel: TextLabel
local autoSwitch: Switch
local autoNote: TextLabel
local sellArmed: { Count: number, Until: number }? = nil -- 두 번 눌러야 할 때 첫 번째 누름
local lastSell = 0
local pendingSend: { [string]: any } = {}
local sendToken = 0

local function strokeOf(label: TextLabel): UIStroke?
	return label:FindFirstChildOfClass("UIStroke")
end

local function settingNumber(key: string): number
	local v = State.GetSetting(key)
	if type(v) == "number" then
		return v
	end
	local d = (Config.Settings :: any)[key]
	return if type(d) == "number" then d else 1
end

local function sellZone(): number
	return settingNumber("SellZoneMax")
end

local function sellRarity(): number
	return settingNumber("SellRarityMax")
end

-- 고를 수 있는 가장 먼 테마: 열린 지역 (+ 지금 저장된 값)
local function zoneLimit(): number
	return math.clamp(math.max(State.MaxZone(), sellZone()), 1, Config.MaxZone)
end

local function zoneText(z: number): string
	local zone = Config.Zones[z]
	return if zone then zone.Emoji .. " " .. zone.Name .. " 이하" else "?"
end

local function zoneColor(z: number): Color3
	local zone = Config.Zones[z]
	local pal = if zone then zone.Palette else nil
	return if pal and typeof(pal.Ground) == "Color3" then UiKit.Lighten(pal.Ground, 0.1) else C.Mint
end

local function rarityKey(r: number): string?
	return Config.RarityOrder[r]
end

local function rarityText(r: number): string
	local key = rarityKey(r)
	local info = if key then Config.Rarities[key] else nil
	return if info then info.Name .. " 이하" else "?"
end

-- 가방 칸 알약: "가방 n/150" (♾ 켜면 "가방 n/∞"), 꽉 차면 빨강
local function updateCount()
	if not countLabel then
		return
	end
	local bag = State.BagCount()
	local infinite = State.GetSetting("InfiniteBag") == true
	countLabel.Text = string.format("가방 %d/%s", bag, if infinite then "∞" else tostring(Config.MaxBagItems))
	countPill.BackgroundColor3 = if bag >= State.BagCapacity() then C.Red else C.Lemon
end

local function paintSwitch(sw: Switch, on: boolean, animate: boolean)
	sw.Shown = on
	local face = if on then sw.Color else OFF_FACE
	sw.Face.BackgroundColor3 = face
	local cs = strokeOf(sw.Caption)
	if cs then
		cs.Color = UiKit.Darken(face, 0.5)
	end
	sw.Track.BackgroundColor3 = if on then C.Mint else OFF_TRACK
	sw.StateLabel.Text = if on then "ON" else "OFF"
	sw.StateLabel.Position = UDim2.fromScale(if on then 0.36 else 0.64, 0.5)
	local ss = strokeOf(sw.StateLabel)
	if ss then
		ss.Color = UiKit.Darken(if on then C.Mint else OFF_TRACK, 0.5)
	end
	local goal = UDim2.fromScale(if on then 0.76 else 0.24, 0.5)
	if animate then
		UiKit.Tween(sw.Knob, 0.18, { Position = goal }, Enum.EasingStyle.Back)
		UiKit.Bump(sw.Face, if on then 0.12 else -0.06)
	else
		sw.Knob.Position = goal
	end
end

-- ON/OFF 스위치 (Hud 켜고 끄는 버튼과 같은 모양: ON = 제 색 + 민트 스위치, OFF = 회색). 누르는 칸은 투명 버튼
local function makeSwitch(parent: Instance, name: string, text: string, color: Color3, z: number, onTap: () -> ()): Switch
	local btn: TextButton = Make("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = true,
		ZIndex = z,
		Parent = parent,
	})
	local face: Frame = Make("Frame", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = OFF_FACE,
		ZIndex = z,
		Parent = btn,
	})
	UiKit.Corner(face, UDim.new(0.5, 0))
	UiKit.Gradient(face)
	UiKit.Stroke(face, C.White, 2, true)
	local caption = UiKit.Label({
		Name = "Caption",
		Text = text,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.07, 0.5),
		Size = UDim2.fromScale(0.53, 0.8),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = z + 1,
		Parent = face,
	}, { MaxText = 22 })
	local track: Frame = Make("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.94, 0.5),
		Size = UDim2.fromScale(0.34, 0.58),
		BackgroundColor3 = OFF_TRACK,
		ZIndex = z + 1,
		Parent = face,
	})
	UiKit.Corner(track, UDim.new(0.5, 0))
	UiKit.Stroke(track, C.White, 1.5, true)
	local state = UiKit.Label({
		Name = "State",
		Text = "OFF",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.64, 0.5),
		Size = UDim2.fromScale(0.5, 0.8),
		ZIndex = z + 2,
		Parent = track,
	}, { MaxText = 14, StrokeThickness = 1.5 })
	local knob: Frame = Make("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.24, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		BackgroundColor3 = C.White,
		ZIndex = z + 3,
		Parent = track,
	})
	Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = knob })
	UiKit.Corner(knob, UDim.new(0.5, 0))
	-- 누르는 느낌 (UiKit.Button 과 같게)
	local scale = UiKit.Scale(face)
	btn.MouseButton1Down:Connect(function()
		UiKit.Tween(scale, 0.08, { Scale = 0.92 })
	end)
	btn.MouseButton1Up:Connect(function()
		UiKit.Tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	btn.MouseLeave:Connect(function()
		UiKit.Tween(scale, 0.15, { Scale = 1 })
	end)
	local lastTap = 0
	btn.Activated:Connect(function()
		if os.clock() - lastTap < 0.25 then
			return -- 아주 빠른 연타는 한 번으로
		end
		lastTap = os.clock()
		UiKit.PlaySound("Click")
		onTap()
	end)
	return {
		Button = btn,
		Face = face,
		Caption = caption,
		Track = track,
		Knob = knob,
		StateLabel = state,
		Color = color,
		Shown = nil,
	}
end

-- 기다리던 테마·등급 설정을 지금 서버로
local function flushSettings()
	sendToken += 1
	for key, value in pendingSend do
		Remotes.SetSetting:FireServer(key, value)
	end
	table.clear(pendingSend)
end

-- 바로 바꿔 보여 주고 (State.SetSettingLocal) 조금 뒤에 서버로 (연달아 누르면 마지막 값만)
local function queueSetting(key: string, value: number)
	State.SetSettingLocal(key, value)
	pendingSend[key] = value
	sendToken += 1
	local my = sendToken
	task.delay(SEND_DELAY, function()
		if my == sendToken then
			flushSettings()
		end
	end)
end

local function onInfiniteTap()
	local on = State.GetSetting("InfiniteBag") ~= true
	State.SetSettingLocal("InfiniteBag", on) -- 바로 바꿔 보여 줘요 (OnSetting → 스위치 + 알약)
	Remotes.SetSetting:FireServer("InfiniteBag", on)
	if on then
		Toasts.Show("♾ 가방 무한 켜짐! 펫을 " .. Config.InfiniteBagItems .. "마리까지 넣을 수 있어요 🎒", "good")
	elseif State.BagCount() > Config.MaxBagItems then
		Toasts.Show("♾ 가방 무한 꺼짐 · 펫은 그대로예요! " .. Config.MaxBagItems .. "마리보다 적어지면 다시 넣을 수 있어요", "info")
	else
		Toasts.Show("♾ 가방 무한 꺼짐 · 가방은 " .. Config.MaxBagItems .. "칸이에요", "info")
	end
end

-- 지금 조건으로 팔릴 가방 펫 수와 합계 (서버 PlotService 와 같은 Config.SellMatch + Config.SellPrice)
local function sellPreview(zone: number, rarity: number): (number, number)
	local n, total = 0, 0
	for _, item in State.Items() do
		if type(item) == "table" and item.Loc == "Bag" and Config.SellMatch(item, zone, rarity) then
			n += 1
			total += Config.SellPrice(item.Id, tonumber(item.Tier) or 1)
		end
	end
	return n, total
end

local function needConfirm(n: number, total: number): boolean
	return n >= Config.BulkSell.ConfirmCount or total >= Config.BulkSell.ConfirmCoins
end

local function paintStepper(st: Stepper, text: string, color: Color3, canDown: boolean, canUp: boolean)
	st.Value.Text = text
	st.Face.BackgroundColor3 = color
	for _, label in { st.Value, st.Caption } do
		local stroke = strokeOf(label)
		if stroke then
			stroke.Color = UiKit.Darken(color, 0.55)
		end
	end
	st.Down.BackgroundColor3 = if canDown then C.Sky else C.Grey
	st.Up.BackgroundColor3 = if canUp then C.Sky else C.Grey
end

-- 💰 창 글자/색 다시 칠하기 (열려 있을 때만)
local function refreshSell()
	if not sellOverlay or not sellOverlay.Visible then
		return
	end
	local z, r = sellZone(), sellRarity()
	paintStepper(zoneStep, zoneText(z), zoneColor(z), z > 1, z < zoneLimit())
	paintStepper(rarityStep, rarityText(r), UiKit.RarityColor(rarityKey(r)), r > 1, r < Config.SellRarityTop)
	local n, total = sellPreview(z, r)
	previewLabel.Text = string.format("%d마리 · 💰 %s", n, Config.FormatNumber(total))
	previewFace.BackgroundColor3 = if n > 0 then C.Lemon else C.Grey
	local armed = sellArmed
	if armed and (armed.Count ~= n or os.clock() > armed.Until) then
		sellArmed = nil
		armed = nil
	end
	if armed then
		sellLabel.Text = "정말 팔까요? 💰"
		sellButton.BackgroundColor3 = C.Red
	else
		sellLabel.Text = "💰 팔기"
		sellButton.BackgroundColor3 = if n > 0 then C.Orange else C.Grey
	end
	local auto = State.GetSetting("AutoSell") == true
	if autoSwitch.Shown ~= auto then
		paintSwitch(autoSwitch, auto, false)
	end
end

local function stepZone(d: number)
	local z = sellZone() + d
	if z < 1 or z > zoneLimit() then
		UiKit.Shake(if d < 0 then zoneStep.Down else zoneStep.Up, 5, 6)
		if z > zoneLimit() and z <= Config.MaxZone then
			Toasts.Show("🔒 더 먼 테마는 환생하면 열려요!", "info")
		end
		return
	end
	sellArmed = nil
	queueSetting("SellZoneMax", z)
	UiKit.Bump(zoneStep.Face, 0.08)
	refreshSell()
end

local function stepRarity(d: number)
	local r = sellRarity() + d
	if r < 1 or r > Config.SellRarityTop then
		UiKit.Shake(if d < 0 then rarityStep.Down else rarityStep.Up, 5, 6)
		if r > Config.SellRarityTop then
			Toasts.Show("🌟 시크릿·천상·이터널 펫은 안 팔아요!", "info")
		end
		return
	end
	sellArmed = nil
	queueSetting("SellRarityMax", r)
	UiKit.Bump(rarityStep.Face, 0.08)
	refreshSell()
end

local function onSellTap()
	if os.clock() - lastSell < Config.BulkSell.Gap then
		return
	end
	local z, r = sellZone(), sellRarity()
	local n, total = sellPreview(z, r)
	if n == 0 then
		sellArmed = nil
		UiKit.Shake(sellButton, 5, 6)
		Toasts.Show("가방에 이 조건 펫이 없어요 🐾", "info")
		return
	end
	if needConfirm(n, total) then
		local armed = sellArmed
		if not armed or armed.Count ~= n or os.clock() > armed.Until then
			-- 많이 팔 때는 한 번 더 눌러야 해요
			sellArmed = { Count = n, Until = os.clock() + 2.5 }
			UiKit.Shake(sellButton, 5, 6)
			refreshSell()
			task.delay(2.6, refreshSell)
			return
		end
	end
	sellArmed = nil
	lastSell = os.clock()
	flushSettings() -- 고른 조건도 저장 (자동 판매가 같은 조건)
	Remotes.SellBulk:FireServer(z, r)
	refreshSell()
end

local function onAutoTap()
	local on = State.GetSetting("AutoSell") ~= true
	flushSettings() -- 조건을 먼저 보내요
	State.SetSettingLocal("AutoSell", on)
	Remotes.SetSetting:FireServer("AutoSell", on)
	if on then
		Toasts.Show("🤖 자동 판매 켜짐! " .. zoneText(sellZone()) .. " · " .. rarityText(sellRarity()) .. " 새 펫은 바로 팔아요", "good")
	else
		Toasts.Show("🤖 자동 판매 꺼짐", "info")
	end
	refreshSell()
end

local function placeStepper(st: Stepper, x: number, y: number, w: number, h: number)
	local bw = 44
	st.Frame.Position = UDim2.fromOffset(x, y)
	st.Frame.Size = UDim2.fromOffset(w, h)
	st.Down.Position = UDim2.fromOffset(0, 0)
	st.Down.Size = UDim2.fromOffset(bw, h)
	st.Up.Position = UDim2.fromOffset(w - bw, 0)
	st.Up.Size = UDim2.fromOffset(bw, h)
	st.Face.Position = UDim2.fromOffset(bw + 4, 0)
	st.Face.Size = UDim2.fromOffset(math.max(40, w - 2 * bw - 8), h)
end

-- 💰 창 배치: 제목줄 / [테마 | 미리 보기] / [등급 | 팔기] / [🤖 자동 판매 | 설명]. 높이 222 라 568×320 에도 들어가요
local function layoutSell()
	if not sellOverlay or not sellOverlay.Visible then
		return
	end
	local s = UiKit.ScaleOf(sellOverlay)
	local W = sellOverlay.AbsoluteSize.X / s
	if W <= 0 then
		return
	end
	local pad, gap, titleH, rowH, autoH = 10, 6, 44, 46, 48
	local sw = math.floor(math.min(W - 16, 640))
	local sh = pad * 2 + titleH + rowH * 2 + autoH + gap * 3
	sellSheet.Size = UDim2.fromOffset(sw, sh)
	local inner = sw - pad * 2
	local titleW = math.floor(inner * 0.4)
	sellTitle.Position = UDim2.fromOffset(pad, pad)
	sellTitle.Size = UDim2.fromOffset(titleW, titleH)
	sellClose.Position = UDim2.fromOffset(sw - pad - 44, pad)
	sellClose.Size = UDim2.fromOffset(44, 44)
	sellHint.Position = UDim2.fromOffset(pad + titleW + 6, pad + 4)
	sellHint.Size = UDim2.fromOffset(math.max(40, inner - titleW - 6 - 44 - 6), titleH - 8)
	local left = math.floor(inner * 0.58) - 3
	local right = inner - left - 6
	local y2 = pad + titleH + gap
	local y3 = y2 + rowH + gap
	local y4 = y3 + rowH + gap
	placeStepper(zoneStep, pad, y2, left, rowH)
	placeStepper(rarityStep, pad, y3, left, rowH)
	previewFace.Position = UDim2.fromOffset(pad + left + 6, y2)
	previewFace.Size = UDim2.fromOffset(right, rowH)
	sellButton.Position = UDim2.fromOffset(pad + left + 6, y3)
	sellButton.Size = UDim2.fromOffset(right, rowH)
	local swW = math.clamp(math.floor(inner * 0.36), 150, 220)
	autoSwitch.Button.Position = UDim2.fromOffset(pad, y4)
	autoSwitch.Button.Size = UDim2.fromOffset(swW, autoH)
	autoNote.Position = UDim2.fromOffset(pad + swW + 8, y4)
	autoNote.Size = UDim2.fromOffset(inner - swW - 8, autoH)
end

local function closeSell()
	if sellOverlay and sellOverlay.Visible then
		sellOverlay.Visible = false
		sellArmed = nil
		flushSettings()
	end
end

-- 💰 한꺼번에 팔기 버튼: 열기 / 닫기
local function toggleSell()
	if sellOverlay.Visible then
		closeSell()
		return
	end
	closeWardrobe()
	sellArmed = nil
	sellOverlay.Visible = true
	layoutSell()
	refreshSell()
	UiKit.Pop(sellSheet, 0.25)
end

-- 창 머리줄: 제목 | (가방 칸 알약 + ♾ 스위치) | ✖. 낮은 화면은 머리줄이 44 라 스위치 누르는 칸 = 44
local function layoutHeader()
	if not headerBox then
		return
	end
	local header = window.Header
	local s = UiKit.ScaleOf(header)
	local hw = header.AbsoluteSize.X / s
	local hh = header.AbsoluteSize.Y / s
	if hw <= 0 or hh <= 0 then
		return
	end
	local compact = hh < 50
	local closeW = if compact then 38 else 46
	local btnH = math.min(hh, math.max(44, hh - 12))
	local faceH = if compact then 34 else 40
	local swW = math.clamp(math.floor(hw * 0.26), 140, 180)
	local pillW = math.clamp(math.floor(hw * 0.18), 104, 140)
	local boxW = pillW + 6 + swW
	headerBox.Position = UDim2.new(1, -(8 + closeW + 10), 0.5, 0)
	headerBox.Size = UDim2.fromOffset(boxW, btnH)
	countPill.Position = UDim2.new(0, 0, 0.5, 0)
	countPill.Size = UDim2.fromOffset(pillW, faceH - 4)
	bagSwitch.Button.Position = UDim2.fromOffset(pillW + 6, 0)
	bagSwitch.Button.Size = UDim2.fromOffset(swW, btnH)
	bagSwitch.Face.Size = UDim2.new(1, 0, 0, faceH)
	window.Title.Size = UDim2.new(1, -(18 + 8 + closeW + 10 + boxW + 10), 1, -12)
end

local function buildSell()
	sellOverlay = Make("TextButton", {
		Name = "SellPanel",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(45, 25, 70),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 46,
		Parent = window.Panel,
	})
	UiKit.Corner(sellOverlay, UDim.new(0, 26))
	sellOverlay.Activated:Connect(closeSell)
	-- 안쪽을 눌러도 닫히지 않게 버튼으로 (아무 일도 안 해요)
	sellSheet = Make("TextButton", {
		Name = "Sheet",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 222),
		BackgroundColor3 = C.Cream,
		ZIndex = 47,
		Parent = sellOverlay,
	})
	UiKit.Corner(sellSheet, UDim.new(0, 20))
	UiKit.Stroke(sellSheet, C.Orange, 5, true)
	sellTitle = UiKit.Label({
		Name = "Title",
		Text = "💰 한꺼번에 팔기",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 48,
		Parent = sellSheet,
	}, { Stroke = UiKit.Darken(C.Orange, 0.45), StrokeThickness = 3, MaxText = 28 })
	sellHint = UiKit.Label({
		Name = "Hint",
		Text = SELL_HINT,
		TextColor3 = C.Ink,
		ZIndex = 48,
		Parent = sellSheet,
	}, { Stroke = C.White, MaxText = 18 })
	sellClose = UiKit.Button({
		Name = "Close",
		Text = "✖",
		Color = C.Red,
		Radius = UDim.new(0.5, 0),
		ZIndex = 49,
		TextSize = 24,
		Parent = sellSheet,
		OnClick = closeSell,
	})
	local function stepper(name: string, caption: string, onStep: (number) -> ()): Stepper
		local frame: Frame = Make("Frame", { Name = name, BackgroundTransparency = 1, ZIndex = 48, Parent = sellSheet })
		local down = UiKit.Button({
			Name = "Down",
			Text = "◀",
			Color = C.Sky,
			Radius = UDim.new(0.35, 0),
			ZIndex = 49,
			TextSize = 24,
			Parent = frame,
			OnClick = function()
				onStep(-1)
			end,
		})
		local up = UiKit.Button({
			Name = "Up",
			Text = "▶",
			Color = C.Sky,
			Radius = UDim.new(0.35, 0),
			ZIndex = 49,
			TextSize = 24,
			Parent = frame,
			OnClick = function()
				onStep(1)
			end,
		})
		local face: Frame = Make("Frame", { Name = "Value", BackgroundColor3 = C.Mint, ZIndex = 49, Parent = frame })
		UiKit.Corner(face, UDim.new(0.3, 0))
		UiKit.Gradient(face)
		UiKit.Stroke(face, C.White, 2, true)
		local cap = UiKit.Label({
			Name = "Caption",
			Text = caption,
			Position = UDim2.fromScale(0.05, 0.04),
			Size = UDim2.fromScale(0.9, 0.34),
			ZIndex = 50,
			Parent = face,
		}, { MaxText = 14, StrokeThickness = 1.5 })
		local value = UiKit.Label({
			Name = "Text",
			Text = "",
			Position = UDim2.fromScale(0.05, 0.36),
			Size = UDim2.fromScale(0.9, 0.58),
			ZIndex = 50,
			Parent = face,
		}, { MaxText = 22 })
		return { Frame = frame, Down = down, Up = up, Face = face, Caption = cap, Value = value }
	end
	zoneStep = stepper("Zone", "🗺 테마", stepZone)
	rarityStep = stepper("Rarity", "⭐ 등급", stepRarity)
	previewFace = Make("Frame", { Name = "Preview", BackgroundColor3 = C.Lemon, ZIndex = 48, Parent = sellSheet })
	UiKit.Corner(previewFace, UDim.new(0.3, 0))
	UiKit.Gradient(previewFace)
	UiKit.Stroke(previewFace, C.White, 2, true)
	previewLabel = UiKit.Label({
		Name = "Text",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.7),
		ZIndex = 49,
		Parent = previewFace,
	}, { Stroke = UiKit.Darken(C.Orange, 0.5), MaxText = 24 })
	sellButton, sellLabel = UiKit.Button({
		Name = "Sell",
		Text = "💰 팔기",
		Color = C.Orange,
		Radius = UDim.new(0.35, 0),
		ZIndex = 48,
		TextSize = 26,
		Parent = sellSheet,
		OnClick = onSellTap,
	})
	autoSwitch = makeSwitch(sellSheet, "AutoSell", "🤖 자동 판매", AUTO_COLOR, 48, onAutoTap)
	autoNote = UiKit.Label({
		Name = "AutoNote",
		Text = AUTO_NOTE,
		TextColor3 = C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 48,
		Parent = sellSheet,
	}, { Stroke = C.White, MaxText = 18 })
	paintSwitch(autoSwitch, State.GetSetting("AutoSell") == true, false)
	sellOverlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutSell)
end

----------------------------------------------------------------------
-- 다시 그리기
----------------------------------------------------------------------
local function rebuild()
	dirty = false
	local items = State.Items()
	countFuse(items)

	-- 사라진/바뀐 카드 정리 (팔거나 합성하면 없어져요)
	for uid, card in cards do
		local item = items[uid]
		if not item or item.Kind ~= card.Item.Kind or item.Id ~= card.Item.Id or tierOf(item) ~= tierOf(card.Item) then
			destroyCard(card)
			cards[uid] = nil
		end
	end

	local sorted = State.SortedItems(function(_, item)
		return (UiKit.ItemInfo(item.Kind, item.Id)) ~= nil
	end)
	local shown = 0
	for i, entry in sorted do
		local card = cards[entry.Uid]
		if not card then
			card = createCard(entry.Uid, entry.Item)
			if card then
				cards[entry.Uid] = card
			end
		end
		if card then
			updateCard(card, entry.Item)
			card.Frame.LayoutOrder = i
			local visible = matchesTab(entry.Item)
			card.Frame.Visible = visible
			if visible then
				shown += 1
			end
		end
	end

	updateCount() -- ★v7.1 ♾ 켜면 "가방 n/∞"
	emptyLabel.Visible = shown == 0
	if shown == 0 then
		emptyLabel.Text = if currentTab == "Egg"
			then "알이 없어요 🥚\n컨베이어에서 사 보세요!"
			elseif currentTab == "Pet" then "펫이 아직 없어요 🐣\n알을 집 받침대에 두면 부화해요!"
			elseif currentTab == "Home" then "집 받침대가 비어 있어요 🏠\n'✨ 좋은 펫 자동 배치'를 눌러 보세요!"
			else "가방이 비어 있어요 🎒\n컨베이어에서 알을 사 보세요!"
	end

	if selectedUid and not items[selectedUid] then
		local nextUid = findFuseResult(items)
		selectedUid = nil
		if nextUid then
			selectItem(nextUid)
		end
	end
	renderPanel()
	refreshSell() -- ★v7.1 💰 창 미리 보기
	queueViewports()
end

local function setTab(tab: string)
	currentTab = tab
	for key, btn in tabButtons do
		local selected = key == tab
		btn.BackgroundColor3 = if selected then C.Pink else C.Grey
		if selected then
			UiKit.Bump(btn, 0.1)
		end
	end
	rebuild()
	scroll.CanvasPosition = Vector2.zero
end

----------------------------------------------------------------------
-- 자동 배치 / 집 펫 모두 빼기
----------------------------------------------------------------------
local function onAutoPlace()
	if os.clock() - lastFire < 0.6 then
		return
	end
	if not State.Plot then
		Toasts.Show("집이 아직 없어요! 잠깐만 기다려 주세요 🏠", "warn")
		return
	end
	local pets = 0
	for _, item in State.Items() do
		if type(item) == "table" and item.Kind == "Pet" and (item.Loc == "Bag" or item.Loc == "Slot") then
			pets += 1
		end
	end
	if pets == 0 then
		Toasts.Show("가방에 펫이 없어요 🐣", "info")
		return
	end
	lastFire = os.clock()
	Remotes.AutoPlace:FireServer()
end

local function onClearBase()
	if os.clock() - lastFire < 0.6 then
		return
	end
	lastFire = os.clock()
	Remotes.ClearBase:FireServer()
end

----------------------------------------------------------------------
-- 화면 크기에 맞추기 (넓으면 오른쪽 정보 칸, 좁으면 정보 칸이 목록을 덮어요)
----------------------------------------------------------------------
local function relayout()
	local w = content.AbsoluteSize.X / UiKit.ScaleOf(content)
	if w <= 0 then
		return
	end
	wide = w >= WIDE_FROM
	local topH: number
	if wide then
		-- ★v7.1 가방 칸 알약은 창 머리줄로 갔어요: 탭 4개 44 % | 도구 3개 56 %
		tabsRow.Position = UDim2.fromOffset(0, 0)
		tabsRow.Size = UDim2.new(0.44, -4, 0, 46)
		toolsRow.Position = UDim2.new(0.44, 4, 0, 0)
		toolsRow.Size = UDim2.new(0.56, -4, 0, 46)
		topH = 54
	else
		tabsRow.Position = UDim2.fromOffset(0, 0)
		tabsRow.Size = UDim2.new(1, 0, 0, 44)
		toolsRow.Position = UDim2.fromOffset(0, 50)
		toolsRow.Size = UDim2.new(1, 0, 0, 44)
		topH = 102
	end
	body.Position = UDim2.fromOffset(0, topH)
	body.Size = UDim2.new(1, 0, 1, -topH)
	if wide then
		local pw = math.clamp(math.floor(w * 0.36), 210, 320)
		gridArea.Size = UDim2.new(1, -(pw + 8), 1, 0)
		panel.Position = UDim2.new(1, -pw, 0, 0)
		panel.Size = UDim2.new(0, pw, 1, 0)
		panel.BackgroundTransparency = 0
		panel.Visible = true
		panelBack.Visible = false
		panelHolder.Size = UDim2.new(1, -8, 0, math.clamp(math.floor(pw * 0.62), 110, 190))
	else
		gridArea.Size = UDim2.fromScale(1, 1)
		panel.Position = UDim2.fromOffset(0, 0)
		panel.Size = UDim2.fromScale(1, 1)
		panel.Visible = selectedUid ~= nil
		panelBack.Visible = true
		panelHolder.Size = UDim2.new(1, -8, 0, math.clamp(math.floor(w * 0.4), 100, 170))
	end
	-- ★v7.1 도구 버튼이 좁으면 짧은 글자 (두 번 누르기 확인 글자는 그대로)
	local toolW = (if wide then w * 0.56 else w) / math.max(1, #toolButtons)
	for _, t in toolButtons do
		if t.Label.Text == t.Long or t.Label.Text == t.Short then
			t.Label.Text = if toolW >= 150 then t.Long else t.Short
		end
	end
	layoutHeader()
	layoutSell()
	queueViewports()
end

----------------------------------------------------------------------
-- 만들기
----------------------------------------------------------------------
local function buildPanel(parent: Instance)
	panel = Make("Frame", {
		Name = "Detail",
		BackgroundColor3 = Color3.fromRGB(255, 244, 250),
		ZIndex = 25,
		Parent = parent,
	})
	UiKit.Corner(panel, UDim.new(0, 18))
	UiKit.Stroke(panel, C.Pink, 4, true)

	panelEmpty = UiKit.Label({
		Text = "펫이나 알을\n눌러 보세요 👆",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.3),
		TextColor3 = C.Ink,
		ZIndex = 26,
		Parent = panel,
	}, { Stroke = C.White, MaxText = 26 })

	panelScroll = UiKit.ListScroller(panel, {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		ScrollBarThickness = 6,
		ZIndex = 26,
		Visible = false,
	})
	local list = panelScroll:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, 6)
	end

	-- 좁은 화면: 목록으로 돌아가기
	panelBack = UiKit.Button({
		Name = "Back",
		Text = "◀ 목록으로",
		Color = C.Sky,
		Size = UDim2.new(0.5, 0, 0, 38),
		LayoutOrder = 0,
		ZIndex = 27,
		TextSize = 22,
		Parent = panelScroll,
		OnClick = clearSelection,
	})

	panelHolder = Make("Frame", {
		Name = "Viewport",
		Size = UDim2.new(1, -8, 0, 140),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.2,
		ClipsDescendants = true,
		LayoutOrder = 1,
		ZIndex = 27,
		Parent = panelScroll,
	})
	UiKit.Corner(panelHolder, UDim.new(0, 16))

	panelName = UiKit.Label({
		Name = "PetName",
		Text = "",
		Size = UDim2.new(1, -8, 0, 32),
		LayoutOrder = 2,
		ZIndex = 27,
		Parent = panelScroll,
	}, { StrokeThickness = 3, MaxText = 28 })

	panelPills = Make("Frame", {
		Name = "Pills",
		Size = UDim2.new(1, -8, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		ZIndex = 27,
		Parent = panelScroll,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panelPills,
	})

	for i = 1, 5 do
		panelLines[i] = UiKit.Label({
			Name = "Line" .. i,
			Text = "",
			Size = UDim2.new(1, -8, 0, 22),
			TextColor3 = C.Ink,
			LayoutOrder = 3 + i,
			ZIndex = 27,
			Parent = panelScroll,
		}, { Stroke = C.White, MaxText = 20 })
	end

	panelButtons = Make("Frame", {
		Name = "Actions",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 20,
		ZIndex = 27,
		Parent = panelScroll,
	})
	Make("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, 44),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = panelButtons,
	})
end

function BagWindow.Init(gui: Instance, bagActions: Actions?)
	actions = bagActions or {}
	window = UiKit.Window(gui, { Title = "🎒 가방", Color = C.Pink, Name = "BagWindow" })
	content = window.Content

	-- 탭 줄: 전체 / 펫 / 알 / 집 + 가방 칸 수
	tabsRow = Make("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = content,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 5),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabsRow,
	})
	local tabs = { { "All", "전체" }, { "Pet", "🐾 펫" }, { "Egg", "🥚 알" }, { "Home", "🏠 집" } }
	for i, t in tabs do
		local key = t[1]
		tabButtons[key] = UiKit.Button({
			Name = key,
			Text = t[2],
			Color = C.Grey,
			Size = UDim2.new(0.25, -4, 1, -4),
			LayoutOrder = i,
			Radius = UDim.new(0.5, 0),
			TextSize = 22,
			Parent = tabsRow,
			OnClick = function()
				setTab(key)
			end,
		})
	end
	-- ★v7.1 창 머리줄 오른쪽: 가방 칸 알약 + ♾ 가방 무한 스위치 (자리는 layoutHeader)
	headerBox = Make("Frame", {
		Name = "BagBox",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 24,
		Parent = window.Header,
	})
	countPill, countLabel = UiKit.Pill(headerBox, "가방 0/" .. Config.MaxBagItems, C.Lemon, {
		Name = "Count",
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 25,
	}, 20)
	bagSwitch = makeSwitch(headerBox, "InfiniteBag", "♾ 가방 무한", INFINITE_COLOR, 25, onInfiniteTap)
	paintSwitch(bagSwitch, State.GetSetting("InfiniteBag") == true, false)

	-- 도구 줄: 자동 배치 / 집 펫 모두 빼기 (두 번 눌러야 해요) / ★v7.1 💰 한꺼번에 팔기
	toolsRow = Make("Frame", {
		Name = "Tools",
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = content,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toolsRow,
	})
	local autoBtn, autoLabel = UiKit.Button({
		Name = "AutoPlace",
		Text = "✨ 좋은 펫 자동 배치",
		Color = C.Gold,
		Size = UDim2.new(1 / 3, -4, 1, 0),
		LayoutOrder = 1,
		Radius = UDim.new(0.4, 0),
		TextSize = 22,
		Parent = toolsRow,
		OnClick = onAutoPlace,
	})
	local clearTap: () -> () = function() end
	local clearBtn, clearLabel = UiKit.Button({
		Name = "ClearBase",
		Text = "📦 집 펫 모두 빼기",
		Color = C.Sky,
		Size = UDim2.new(1 / 3, -4, 1, 0),
		LayoutOrder = 2,
		Radius = UDim.new(0.4, 0),
		TextSize = 22,
		Parent = toolsRow,
		OnClick = function()
			if State.SlotPetCount() == 0 then
				Toasts.Show("집에 펫이 없어요 🏠", "info")
				return
			end
			clearTap()
		end,
	})
	clearTap = UiKit.TwoTap(clearBtn, clearLabel, "정말 다 뺄까요? 📦", onClearBase)
	local sellBtn, sellBtnLabel = UiKit.Button({
		Name = "SellBulk",
		Text = "💰 한꺼번에 팔기",
		Color = C.Orange,
		Size = UDim2.new(1 / 3, -4, 1, 0),
		LayoutOrder = 3,
		Radius = UDim.new(0.4, 0),
		TextSize = 22,
		Parent = toolsRow,
		OnClick = function()
			toggleSell()
		end,
	})
	toolButtons = {
		{ Button = autoBtn, Label = autoLabel, Long = "✨ 좋은 펫 자동 배치", Short = "✨ 자동 배치" },
		{ Button = clearBtn, Label = clearLabel, Long = "📦 집 펫 모두 빼기", Short = "📦 모두 빼기" },
		{ Button = sellBtn, Label = sellBtnLabel, Long = "💰 한꺼번에 팔기", Short = "💰 한꺼번에 팔기" },
	}

	-- 아래: 카드 목록 + 정보 칸
	body = Make("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = content,
	})
	gridArea = Make("Frame", {
		Name = "GridArea",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 23,
		Parent = body,
	})
	scroll = UiKit.Scroller(gridArea)
	UiKit.AutoGrid(scroll, MIN_CELL, R, 6)
	emptyLabel = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.86, 0.36),
		TextColor3 = C.Ink,
		Visible = false,
		ZIndex = 30,
		Parent = gridArea,
	}, { Stroke = C.White, MaxText = 30 })
	buildPanel(body)
	buildSell() -- ★v7.1 💰 한꺼번에 팔기 창 (창 전체를 덮어요, 처음엔 숨김)

	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	window.Header:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHeader)
	-- ★v7.1 설정이 바뀌면 (방금 누른 값 포함) 스위치·알약·💰 창을 다시 칠해요
	State.OnSetting(function(key: string, value: any)
		if key == "InfiniteBag" then
			if bagSwitch.Shown ~= (value == true) then
				paintSwitch(bagSwitch, value == true, true)
			end
			updateCount()
		elseif key == "AutoSell" then
			if autoSwitch.Shown ~= (value == true) then
				paintSwitch(autoSwitch, value == true, true)
			end
		elseif key == "SellZoneMax" or key == "SellRarityMax" then
			refreshSell()
		end
	end)
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(queueViewports)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueViewports)
	relayout()

	window.OnOpen = function()
		relayout()
		if dirty then
			rebuild()
		else
			renderPanel()
			queueViewports()
		end
	end
	window.OnClose = function()
		closeWardrobe()
		closeSell()
		-- 좁은 화면에서는 다시 열면 목록부터 보이게
		if not wide and selectedUid then
			clearSelection()
		end
	end
	setTab("All")

	-- 알 카운트다운 (열려 있을 때만)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if window.IsOpen() then
				for _, card in cards do
					if card.Item.Kind == "Egg" and card.Frame.Visible then
						card.InfoLabel.Text = eggLine(card.Item, true)
					end
				end
				local uid = selectedUid
				local item = if uid then State.Items()[uid] else nil
				if item and item.Kind == "Egg" and panelLines[1] then
					panelLines[1].Text = eggLine(item, false)
				end
			end
		end
	end)

	-- 정보 칸 펫이 살랑살랑 좌우로 (창이 열려 있을 때만)
	RunService.RenderStepped:Connect(function()
		local model = panelModel
		local base = panelBase
		if model and base and model.Parent and window.IsOpen() then
			model:PivotTo(base * CFrame.Angles(0, math.sin(os.clock() * 0.9) * 0.5, 0))
		end
	end)
end

function BagWindow.OnSync()
	if window and window.IsOpen() then
		rebuild()
	else
		dirty = true
	end
end

function BagWindow.Open()
	window.Open()
end

function BagWindow.Close()
	window.Close()
end

function BagWindow.IsOpen(): boolean
	return window ~= nil and window.IsOpen()
end

return BagWindow
