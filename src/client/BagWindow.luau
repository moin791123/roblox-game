-- 🎒 가방 창: 내 펫과 알 카드 + 행동 버튼
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local BagWindow = {}

local R = 1.82 -- 카드 높이 / 너비
local function Y(u: number): number
	return u / R
end

local LOC_INFO: { [string]: { Text: string, Color: Color3, Order: number } } = {
	Follow = { Text = "함께", Color = C.Pink, Order = 1 },
	Slot = { Text = "기지", Color = C.Mint, Order = 2 },
	Bag = { Text = "가방", Color = C.Sky, Order = 3 },
}

type Card = {
	Frame: Frame,
	Kind: string,
	Id: string,
	ActionsKey: string,
	Info1: TextLabel,
	Info2: TextLabel,
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
local cards: { [string]: Card } = {}
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

local function eggLine(item: State.Item): string
	if item.Loc == "Slot" then
		local left = math.ceil((tonumber(item.HatchAt) or 0) - workspace:GetServerTimeNow())
		if left <= 0 then
			return "🐣 곧 부화!"
		end
		return string.format("⏱ %d초 남음", left)
	end
	local left = math.ceil(tonumber(item.HatchLeft) or 0)
	return string.format("⏸ %d초 (기지에서 부화)", math.max(0, left))
end

type ActionDef = { Text: string, Action: string, Color: Color3 }

local function actionsFor(item: State.Item): { ActionDef }
	if item.Kind == "Pet" then
		if item.Loc == "Slot" then
			return {
				{ Text = "따라오기", Action = "Follow", Color = C.Pink },
				{ Text = "가방에", Action = "ToBag", Color = C.Sky },
			}
		elseif item.Loc == "Follow" then
			return { { Text = "쉬기", Action = "Unfollow", Color = C.Lavender } }
		else
			return {
				{ Text = "따라오기", Action = "Follow", Color = C.Pink },
				{ Text = "기지에", Action = "ToBase", Color = C.Mint },
				{ Text = "팔기 💰" .. Config.FormatNumber(Config.SellPrice(item.Id)), Action = "Sell", Color = C.Orange },
			}
		end
	else
		if item.Loc == "Bag" then
			return { { Text = "기지에", Action = "ToBase", Color = C.Mint } }
		else
			return { { Text = "가방에", Action = "ToBag", Color = C.Sky } }
		end
	end
end

local function buildButtons(card: Card, uid: string, item: State.Item)
	for _, child in card.Buttons:GetChildren() do
		child:Destroy()
	end
	local defs = actionsFor(item)
	local n = #defs
	local rowH = 0.46
	for i, def in defs do
		local pos, size
		if n == 1 then
			pos, size = UDim2.fromScale(0, 0.25), UDim2.fromScale(1, rowH)
		elseif n == 2 then
			pos, size = UDim2.fromScale((i - 1) * 0.52, 0.25), UDim2.fromScale(0.48, rowH)
		elseif i <= 2 then
			pos, size = UDim2.fromScale((i - 1) * 0.52, 0), UDim2.fromScale(0.48, rowH)
		else
			pos, size = UDim2.fromScale(0, 0.53), UDim2.fromScale(1, rowH)
		end
		local confirmToken = 0
		local btn: TextButton, label: TextLabel
		btn, label = UiKit.Button({
			Name = def.Action,
			Text = def.Text,
			Color = def.Color,
			Position = pos,
			Size = size,
			Radius = UDim.new(0.35, 0),
			TextSize = 24,
			Parent = card.Buttons,
			OnClick = function()
				if def.Action == "Sell" then
					-- 두 번 눌러야 팔려요
					if confirmToken == 0 then
						confirmToken += 1
						local my = confirmToken
						label.Text = "정말? 한 번 더!"
						btn.BackgroundColor3 = C.Red
						UiKit.Shake(btn, 5, 6)
						task.delay(3, function()
							if confirmToken == my and btn.Parent then
								confirmToken = 0
								label.Text = def.Text
								btn.BackgroundColor3 = def.Color
							end
						end)
						return
					end
					confirmToken = 0
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
	local rc = UiKit.RarityColor(rarity)
	local frame: Frame = Make("Frame", {
		Name = uid,
		BackgroundColor3 = UiKit.Lighten(rc, 0.82),
		ZIndex = 24,
		Parent = scroll,
	})
	UiKit.Corner(frame, UDim.new(0.1, 0))
	UiKit.Stroke(frame, rc, 4, true)

	local vpHolder: Frame = Make("Frame", {
		Name = "Viewport",
		Position = UDim2.fromScale(0.06, Y(0.05)),
		Size = UDim2.fromScale(0.88, Y(0.78)),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.25,
		ClipsDescendants = true,
		Parent = frame,
	})
	UiKit.Corner(vpHolder, UDim.new(0.18, 0))
	UiKit.Viewport(item.Kind, item.Id, vpHolder, false)

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
		Size = UDim2.fromScale(0.38, Y(0.15)),
		BackgroundColor3 = C.Mint,
		ZIndex = 3,
		Parent = frame,
	})
	UiKit.Corner(tag, UDim.new(0.5, 0))
	UiKit.Stroke(tag, C.White, 2, true)
	local tagLabel = UiKit.Label({ Text = "", Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), ZIndex = 4, Parent = tag }, { MaxText = 18 })

	UiKit.Label({
		Name = "ItemName",
		Text = (if item.Kind == "Egg" then "🥚 " else "") .. name,
		Position = UDim2.fromScale(0.04, Y(0.85)),
		Size = UDim2.fromScale(0.92, Y(0.16)),
		Parent = frame,
	}, { Stroke = UiKit.Darken(rc, 0.5), MaxText = 26 })
	local info1 = UiKit.Label({
		Position = UDim2.fromScale(0.05, Y(1.01)),
		Size = UDim2.fromScale(0.9, Y(0.11)),
		TextColor3 = C.Ink,
		Parent = frame,
	}, { Stroke = C.White, MaxText = 20 })
	local info2 = UiKit.Label({
		Position = UDim2.fromScale(0.05, Y(1.12)),
		Size = UDim2.fromScale(0.9, Y(0.1)),
		TextColor3 = C.Ink,
		Parent = frame,
	}, { Stroke = C.White, MaxText = 18 })

	local buttons: Frame = Make("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.05, Y(1.25)),
		Size = UDim2.fromScale(0.9, Y(0.53)),
		Parent = frame,
	})

	local card: Card = {
		Frame = frame,
		Kind = item.Kind,
		Id = item.Id,
		ActionsKey = "",
		Info1 = info1,
		Info2 = info2,
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
	if item.Kind == "Pet" then
		local def = Config.Pets[item.Id]
		card.Info1.Text = "💰 " .. Config.FormatNumber(def.Income) .. "/초"
		card.Info2.Text = "+" .. tostring(math.floor(def.Boost * 100 + 0.5)) .. "% 코인"
	else
		card.Info1.Text = "⏳ 부화 대기"
		card.Info2.Text = eggLine(item)
	end
	local key = item.Kind .. ":" .. item.Loc
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

local function rebuild()
	dirty = false
	local items = State.Items()

	-- 사라진/바뀐 카드 정리 (훔쳐지면 uid 가 바뀌어요)
	for uid, card in cards do
		local item = items[uid]
		if not item or item.Kind ~= card.Kind or item.Id ~= card.Id then
			card.Frame:Destroy()
			cards[uid] = nil
		end
	end

	local list = {}
	for uid, item in items do
		if type(item) == "table" and UiKit.ItemInfo(item.Kind, item.Id) then
			table.insert(list, { Uid = uid, Item = item, Loc = (LOC_INFO[item.Loc] or LOC_INFO.Bag).Order, Rarity = rarityOrder(item) })
		end
	end
	table.sort(list, function(a, b)
		if a.Loc ~= b.Loc then
			return a.Loc < b.Loc
		end
		if a.Rarity ~= b.Rarity then
			return a.Rarity > b.Rarity
		end
		if a.Item.Kind ~= b.Item.Kind then
			return a.Item.Kind == "Pet"
		end
		if a.Item.Id ~= b.Item.Id then
			return a.Item.Id < b.Item.Id
		end
		return a.Uid < b.Uid
	end)

	local shown, inBag = 0, 0
	for i, entry in list do
		local card = cards[entry.Uid]
		if not card then
			card = createCard(entry.Uid, entry.Item)
			if card then
				cards[entry.Uid] = card
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
			elseif currentTab == "Pet" then "펫이 아직 없어요 🐣\n알을 기지에 두면 부화해요!"
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
	UiKit.AutoGrid(scroll, 158, R, 6)

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
