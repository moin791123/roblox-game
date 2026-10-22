-- 🎒 가방 창: 내 펫·알 카드 (수익 높은 순, 알은 맨 뒤) + 고른 카드의 자세한 정보와 행동 버튼
-- (따라가기 / 집에 놓기 / 타기 / 들기 / 옷 입히기 / 합성 / 팔기). 위쪽엔 자동 배치·집 펫 모두 빼기.
-- 카드의 3D 뷰포트는 화면 근처에 보이는 카드에만 만들고 재활용해요 (가방 150 + 집 120 칸이라 다 만들면 무거워요).
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

	local bag = State.BagCount()
	countLabel.Text = string.format("가방 %d/%d", bag, Config.MaxBagItems)
	countPill.BackgroundColor3 = if bag >= Config.MaxBagItems then C.Red else C.Lemon
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
		tabsRow.Position = UDim2.fromOffset(0, 0)
		tabsRow.Size = UDim2.new(0.56, -4, 0, 46)
		toolsRow.Position = UDim2.new(0.56, 4, 0, 0)
		toolsRow.Size = UDim2.new(0.44, -4, 0, 46)
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
			Size = UDim2.new(0.18, -4, 1, -4),
			LayoutOrder = i,
			Radius = UDim.new(0.5, 0),
			TextSize = 22,
			Parent = tabsRow,
			OnClick = function()
				setTab(key)
			end,
		})
	end
	countPill, countLabel = UiKit.Pill(tabsRow, "가방 0/" .. Config.MaxBagItems, C.Lemon, {
		Name = "Count",
		Size = UDim2.new(0.28, -5, 1, -10),
		LayoutOrder = 10,
	}, 20)

	-- 도구 줄: 자동 배치 / 집 펫 모두 빼기 (두 번 눌러야 해요)
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
	UiKit.Button({
		Name = "AutoPlace",
		Text = "✨ 좋은 펫 자동 배치",
		Color = C.Gold,
		Size = UDim2.new(0.5, -3, 1, -2),
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
		Size = UDim2.new(0.5, -3, 1, -2),
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

	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
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
