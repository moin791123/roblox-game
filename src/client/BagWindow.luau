-- 🎒 가방 창: 내 펫과 알 카드 + 행동 버튼 (따라가기 / 집에 놓기 / 타기 / 들기 / 합성 / 팔기)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local BagWindow = {}

local R = 2.3 -- 카드 높이 / 너비
local function Y(u: number): number
	return u / R
end

local LOC_INFO: { [string]: { Text: string, Color: Color3, Order: number } } = {
	Ride = { Text = "타는 중", Color = C.Lavender, Order = 1 },
	Hold = { Text = "들고 있음", Color = C.Orange, Order = 2 },
	Follow = { Text = "따라옴", Color = C.Pink, Order = 3 },
	Slot = { Text = "집", Color = C.Mint, Order = 4 },
	Bag = { Text = "가방", Color = C.Sky, Order = 5 },
}

type Card = {
	Frame: Frame,
	Uid: string,
	Kind: string,
	Id: string,
	Tier: number,
	ActionsKey: string,
	Info1: TextLabel,
	Info2: TextLabel,
	Info3: TextLabel,
	Tag: Frame,
	TagLabel: TextLabel,
	Buttons: Frame,
	Item: State.Item,
}

local window: UiKit.Window
local scroll: ScrollingFrame
local emptyLabel: TextLabel
local countLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local cards: { [string]: Card } = {} -- key = uid@tier (합성되면 등급이 바뀌어 새 카드)
local currentTab = "All"
local dirty = true
local lastFire = 0

local function fire(uid: string, action: string)
	if os.clock() - lastFire < 0.25 then
		return
	end
	lastFire = os.clock()
	Remotes.PetAction:FireServer(uid, action)
end

local function tierOf(item: State.Item): number
	return if item.Kind == "Pet" then UiKit.TierOf(item.Tier) else 1
end

local function cacheKey(uid: string, item: State.Item): string
	return uid .. "@" .. tostring(tierOf(item))
end

-- 초당 수익 표시 (크기 때문에 소수가 나오면 한 자리까지)
local function incomeText(n: number): string
	if n < 10 then
		local s = string.format("%.1f", n)
		return (s:gsub("%.0$", ""))
	end
	return Config.FormatNumber(n)
end

-- "⚖️ 3.2kg · 거대 🐘" 같은 크기 줄
local function sizeLine(item: State.Item): string
	local size = Config.SizeOf(item)
	local tag = Config.SizeLabel(size)
	local text = string.format("⚖️ %.1fkg", Config.PetWeight(item.Id, size))
	if tag == "거대" then
		return text .. " · 거대 🐘"
	elseif tag == "꼬마" then
		return text .. " · 꼬마 🐭"
	end
	return text
end

local function eggLine(item: State.Item): string
	if item.Loc == "Slot" then
		local left = math.ceil((tonumber(item.HatchAt) or 0) - workspace:GetServerTimeNow())
		if left <= 0 then
			return "🐣 곧 부화!"
		end
		return string.format("⏱ %d초 남음", left)
	end
	local left = math.ceil(tonumber(item.HatchLeft) or 0)
	return string.format("⏸ %d초 (집에서 부화)", math.max(0, left))
end

-- 합성할 수 있나? (같은 펫·같은 등급 FuseCount 마리, 최고 등급이 아닐 때)
local function canFuse(item: State.Item): boolean
	if item.Kind ~= "Pet" then
		return false
	end
	local tier = tierOf(item)
	return tier < Config.MaxTier and State.CountSame(item.Id, tier) >= Config.FuseCount
end

type ActionDef = { Text: string, Action: string, Color: Color3 }

local function actionsFor(item: State.Item): { ActionDef }
	local defs: { ActionDef } = {}
	if item.Kind == "Pet" then
		local tier = tierOf(item)
		if item.Loc == "Follow" then
			table.insert(defs, { Text = "그만", Action = "Unfollow", Color = C.Lavender })
		elseif item.Loc ~= "Ride" then
			table.insert(defs, { Text = "따라가기", Action = "Follow", Color = C.Pink })
		end
		if item.Loc == "Slot" then
			table.insert(defs, { Text = "가방에", Action = "ToBag", Color = C.Sky })
		else
			table.insert(defs, { Text = "집에 놓기", Action = "ToBase", Color = C.Mint })
		end
		if item.Loc == "Ride" then
			table.insert(defs, { Text = "내리기", Action = "Unride", Color = C.Peach })
		else
			table.insert(defs, { Text = "타기 🏇", Action = "Ride", Color = C.Peach })
		end
		if item.Loc == "Hold" then
			table.insert(defs, { Text = "내려놓기", Action = "Unhold", Color = C.Orange })
		else
			table.insert(defs, { Text = "들기 🙌", Action = "Hold", Color = C.Orange })
		end
		if canFuse(item) then
			table.insert(defs, { Text = "합성 ✨", Action = "Fuse", Color = C.Gold })
		end
		table.insert(defs, { Text = "팔기 💰" .. Config.FormatNumber(Config.SellPrice(item.Id, tier)), Action = "Sell", Color = C.Orange })
	else
		if item.Loc == "Bag" then
			table.insert(defs, { Text = "집에 놓기", Action = "ToBase", Color = C.Mint })
		else
			table.insert(defs, { Text = "가방에", Action = "ToBag", Color = C.Sky })
		end
	end
	return defs
end

local function buildButtons(card: Card, uid: string, item: State.Item)
	for _, child in card.Buttons:GetChildren() do
		child:Destroy()
	end
	local defs = actionsFor(item)
	local n = #defs
	local rowH = 0.3 -- 최대 3줄 (줄 사이 0.05)
	for i, def in defs do
		local row = math.floor((i - 1) / 2)
		local col = (i - 1) % 2
		local lastAlone = i == n and col == 0 -- 마지막이 혼자 남으면 한 줄 가득
		local pos = UDim2.fromScale(if lastAlone then 0 else col * 0.52, row * (rowH + 0.05))
		local size = UDim2.fromScale(if lastAlone then 1 else 0.48, rowH)
		local confirmToken = 0
		local btn: TextButton, label: TextLabel
		btn, label = UiKit.Button({
			Name = def.Action,
			Text = def.Text,
			Color = def.Color,
			Position = pos,
			Size = size,
			Radius = UDim.new(0.35, 0),
			TextSize = 22,
			Parent = card.Buttons,
			OnClick = function()
				if def.Action == "Sell" then
					-- 2초 안에 두 번 눌러야 팔려요
					if confirmToken == 0 then
						confirmToken += 1
						local my = confirmToken
						label.Text = "정말 팔기?"
						btn.BackgroundColor3 = C.Red
						UiKit.Shake(btn, 5, 6)
						task.delay(2, function()
							if confirmToken == my and btn.Parent then
								confirmToken = 0
								label.Text = def.Text
								btn.BackgroundColor3 = def.Color
							end
						end)
						return
					end
					confirmToken = 0
				elseif def.Action == "Fuse" then
					if not canFuse(item) then
						Toasts.Show(string.format("같은 펫이 %d마리 있어야 해요!", Config.FuseCount), "warn")
						return
					end
				elseif def.Action == "Ride" then
					Toasts.Show("🏇 " .. Config.PetDisplayName(item.Id, tierOf(item)) .. "을(를) 타요!", "good")
				elseif def.Action == "Hold" then
					Toasts.Show("🙌 " .. Config.PetDisplayName(item.Id, tierOf(item)) .. "을(를) 머리 위에 올려요!", "good")
				end
				fire(uid, def.Action)
			end,
		})
	end
end

local function createCard(uid: string, item: State.Item): Card?
	local name, rarity, rinfo = UiKit.ItemInfo(item.Kind, item.Id)
	if not name then
		return nil
	end
	local tier = tierOf(item)
	local tinfo = Config.TierInfo(tier)
	local rc = UiKit.RarityColor(rarity)
	local borderColor = if item.Kind == "Pet" and tier >= 2 then UiKit.TierColor(tier) else rc
	local frame: Frame = Make("Frame", {
		Name = uid,
		BackgroundColor3 = UiKit.Lighten(if tier >= 2 then borderColor else rc, 0.82),
		ZIndex = 24,
		Parent = scroll,
	})
	UiKit.Corner(frame, UDim.new(0.1, 0))
	UiKit.Stroke(frame, borderColor, if tier >= 2 then 5 else 4, true)

	local vpHolder: Frame = Make("Frame", {
		Name = "Viewport",
		Position = UDim2.fromScale(0.06, Y(0.05)),
		Size = UDim2.fromScale(0.88, Y(0.72)),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.25,
		ClipsDescendants = true,
		Parent = frame,
	})
	UiKit.Corner(vpHolder, UDim.new(0.18, 0))
	UiKit.Viewport(item.Kind, item.Id, vpHolder, false, tier)

	-- 희귀도 (오른쪽 위)
	local rpill: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, Y(0.03)),
		Size = UDim2.fromScale(0.42, Y(0.15)),
		BackgroundColor3 = rc,
		ZIndex = 3,
		Parent = frame,
	})
	UiKit.Corner(rpill, UDim.new(0.5, 0))
	UiKit.Stroke(rpill, C.White, 2, true)
	UiKit.Label({ Text = rinfo and rinfo.Name or "?", Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), ZIndex = 4, Parent = rpill }, { Stroke = UiKit.Darken(rc, 0.45), MaxText = 18 })

	-- 위치 표시 (왼쪽 위)
	local tag: Frame = Make("Frame", {
		Position = UDim2.fromScale(0.03, Y(0.03)),
		Size = UDim2.fromScale(0.42, Y(0.15)),
		BackgroundColor3 = C.Mint,
		ZIndex = 3,
		Parent = frame,
	})
	UiKit.Corner(tag, UDim.new(0.5, 0))
	UiKit.Stroke(tag, C.White, 2, true)
	local tagLabel = UiKit.Label({ Text = "", Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), ZIndex = 4, Parent = tag }, { MaxText = 18 })

	-- 등급 (황금/무지개, 뷰포트 아래쪽 가운데)
	if item.Kind == "Pet" and tier >= 2 then
		local tc = UiKit.TierColor(tier)
		local tpill: Frame = Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, Y(0.76)),
			Size = UDim2.fromScale(0.6, Y(0.14)),
			BackgroundColor3 = tc,
			ZIndex = 3,
			Parent = frame,
		})
		UiKit.Corner(tpill, UDim.new(0.5, 0))
		UiKit.Gradient(tpill)
		UiKit.Stroke(tpill, C.White, 2, true)
		UiKit.Label({ Text = tinfo.Label, Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), ZIndex = 4, Parent = tpill }, { Stroke = UiKit.Darken(tc, 0.5), MaxText = 18 })
	end

	local displayName = if item.Kind == "Egg" then "🥚 " .. name else Config.PetDisplayName(item.Id, tier)
	UiKit.Label({
		Name = "ItemName",
		Text = displayName,
		Position = UDim2.fromScale(0.04, Y(0.8)),
		Size = UDim2.fromScale(0.92, Y(0.15)),
		Parent = frame,
	}, { Stroke = UiKit.Darken(borderColor, 0.5), MaxText = 26 })
	local info1 = UiKit.Label({
		Position = UDim2.fromScale(0.05, Y(0.95)),
		Size = UDim2.fromScale(0.9, Y(0.1)),
		TextColor3 = C.Ink,
		Parent = frame,
	}, { Stroke = C.White, MaxText = 20 })
	local info2 = UiKit.Label({
		Position = UDim2.fromScale(0.05, Y(1.05)),
		Size = UDim2.fromScale(0.9, Y(0.1)),
		TextColor3 = C.Ink,
		Parent = frame,
	}, { Stroke = C.White, MaxText = 18 })
	local info3 = UiKit.Label({
		Position = UDim2.fromScale(0.05, Y(1.15)),
		Size = UDim2.fromScale(0.9, Y(0.1)),
		TextColor3 = C.Ink,
		Visible = item.Kind == "Pet",
		Parent = frame,
	}, { Stroke = C.White, MaxText = 18 })

	local buttons: Frame = Make("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.05, Y(1.28)),
		Size = UDim2.fromScale(0.9, Y(0.98)),
		Parent = frame,
	})

	local card: Card = {
		Frame = frame,
		Uid = uid,
		Kind = item.Kind,
		Id = item.Id,
		Tier = tier,
		ActionsKey = "",
		Info1 = info1,
		Info2 = info2,
		Info3 = info3,
		Tag = tag,
		TagLabel = tagLabel,
		Buttons = buttons,
		Item = item,
	}
	UiKit.Pop(frame, 0.3)
	return card
end

local function updateCard(card: Card, uid: string, item: State.Item)
	card.Item = item
	local loc = LOC_INFO[item.Loc] or LOC_INFO.Bag
	card.TagLabel.Text = loc.Text
	card.Tag.BackgroundColor3 = loc.Color
	local fusable = canFuse(item)
	if item.Kind == "Pet" then
		local tier = tierOf(item)
		card.Info1.Text = "💰 " .. incomeText(Config.ItemIncome(item)) .. "/초" -- 등급 × 크기
		local boost = math.floor(Config.PetBoost(item.Id, tier) * 100 + 0.5)
		card.Info2.Text = if fusable
			then string.format("+%d%% 코인 · ✨ 합성 가능!", boost)
			else string.format("+%d%% 코인 · 🏇 x%.2f", boost, Config.RideSpeedMultiplier(item.Id, tier))
		card.Info3.Text = sizeLine(item)
	else
		card.Info1.Text = "⏳ 부화 대기"
		card.Info2.Text = eggLine(item)
	end
	local key = item.Kind .. ":" .. item.Loc .. ":" .. tostring(fusable)
	if key ~= card.ActionsKey then
		card.ActionsKey = key
		buildButtons(card, uid, item)
	end
end

local function matchesTab(item: State.Item): boolean
	return currentTab == "All" or item.Kind == currentTab
end

local function rarityOrder(item: State.Item): number
	local _, rarity = UiKit.ItemInfo(item.Kind, item.Id)
	local r = rarity and (Config.Rarities :: any)[rarity]
	return if r then r.Order else 0
end

local function sortName(item: State.Item): string
	if item.Kind == "Pet" then
		return Config.PetDisplayName(item.Id, tierOf(item))
	end
	local name = UiKit.ItemInfo(item.Kind, item.Id)
	return name or item.Id
end

local function rebuild()
	dirty = false
	local items = State.Items()

	-- 사라진/바뀐 카드 정리 (팔거나 합성하면 없어지거나 등급이 바뀌어요)
	for key, card in cards do
		local item = items[card.Uid]
		if not item or item.Kind ~= card.Kind or item.Id ~= card.Id or cacheKey(card.Uid, item) ~= key then
			card.Frame:Destroy()
			cards[key] = nil
		end
	end

	local list = {}
	for uid, item in items do
		if type(item) == "table" and UiKit.ItemInfo(item.Kind, item.Id) then
			table.insert(list, {
				Uid = uid,
				Item = item,
				Tier = if item.Kind == "Pet" then tierOf(item) else 0, -- 알은 펫 뒤로
				Rarity = rarityOrder(item),
				Name = sortName(item),
			})
		end
	end
	-- 등급 높은 순 → 희귀도 높은 순 → 이름
	table.sort(list, function(a, b)
		if a.Tier ~= b.Tier then
			return a.Tier > b.Tier
		end
		if a.Rarity ~= b.Rarity then
			return a.Rarity > b.Rarity
		end
		if a.Name ~= b.Name then
			return a.Name < b.Name
		end
		return a.Uid < b.Uid
	end)

	local shown, inBag = 0, 0
	for i, entry in list do
		local key = cacheKey(entry.Uid, entry.Item)
		local card = cards[key]
		if not card then
			card = createCard(entry.Uid, entry.Item)
			if card then
				cards[key] = card
			end
		end
		if card then
			updateCard(card, entry.Uid, entry.Item)
			card.Frame.LayoutOrder = i
			local visible = matchesTab(entry.Item)
			card.Frame.Visible = visible
			if visible then
				shown += 1
			end
		end
		if entry.Item.Loc == "Bag" then
			inBag += 1
		end
	end

	countLabel.Text = string.format("가방 %d/%d", inBag, Config.MaxBagItems)
	emptyLabel.Visible = shown == 0
	if shown == 0 then
		emptyLabel.Text = if currentTab == "Egg"
			then "알이 없어요 🥚\n가운데 컨베이어에서 사 보세요!"
			elseif currentTab == "Pet" then "펫이 아직 없어요 🐣\n알을 집 받침대에 두면 부화해요!"
			else "가방이 비어 있어요 🎒\n컨베이어에서 알을 사 보세요!"
	end
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

function BagWindow.Init(gui: Instance)
	window = UiKit.Window(gui, { Title = "🎒 가방", Color = C.Pink, Name = "BagWindow" })
	local content = window.Content

	local top: Frame = Make("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		ZIndex = 23,
		Parent = content,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = top,
	})
	local tabs = { { "All", "전체" }, { "Pet", "🐾 펫" }, { "Egg", "🥚 알" } }
	for i, t in tabs do
		local key = t[1]
		tabButtons[key] = UiKit.Button({
			Name = key,
			Text = t[2],
			Color = C.Grey,
			Size = UDim2.new(0.22, 0, 1, -4),
			LayoutOrder = i,
			Radius = UDim.new(0.5, 0),
			TextSize = 24,
			Parent = top,
			OnClick = function()
				setTab(key)
			end,
		})
	end
	local countPill: Frame = Make("Frame", {
		Size = UDim2.new(0.26, 0, 1, -8),
		BackgroundColor3 = C.Lemon,
		LayoutOrder = 10,
		Parent = top,
	})
	UiKit.Corner(countPill, UDim.new(0.5, 0))
	UiKit.Stroke(countPill, C.White, 3, true)
	countLabel = UiKit.Label({ Text = "가방 0/" .. Config.MaxBagItems, Size = UDim2.fromScale(0.86, 0.72), Position = UDim2.fromScale(0.07, 0.14), Parent = countPill }, { Stroke = UiKit.Darken(C.Lemon, 0.5), MaxText = 22 })

	scroll = UiKit.Scroller(content, { Position = UDim2.new(0, 0, 0, 56), Size = UDim2.new(1, 0, 1, -56) })
	UiKit.AutoGrid(scroll, 160, R, 6)

	emptyLabel = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 28),
		Size = UDim2.fromScale(0.8, 0.3),
		TextColor3 = C.Ink,
		Visible = false,
		ZIndex = 30,
		Parent = content,
	}, { Stroke = C.White, MaxText = 30 })

	window.OnOpen = function()
		if dirty then
			rebuild()
		end
	end
	setTab("All")

	-- 열려 있을 때 알 카운트다운 갱신
	task.spawn(function()
		while true do
			task.wait(0.5)
			if window.IsOpen() then
				for _, card in cards do
					if card.Kind == "Egg" then
						card.Info2.Text = eggLine(card.Item)
					end
				end
			end
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
