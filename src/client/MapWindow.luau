-- 🗺️ 지도 창: 지역 카드 (이모지, 이름, 그 지역 알들 작은 그림, 지역 색, 🔒 환생 N회 / "이동"), 지금 있는 지역 표시,
-- "🏠 우리 집" 버튼. 이동은 Teleport("Zone", i) / Teleport("Home") (서버가 환생 수를 다시 확인해요)
-- 지역 수·알 수·위치는 모두 Config.Zones / Config.Eggs 에서 읽어요 (알 그림은 창을 처음 열 때 만들어요)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer

local MapWindow = {}

local TELEPORT_GAP = 1.6 -- 서버 쿨다운(1.5초)보다 살짝 길게
local MAX_EGG_ICONS = 6 -- 카드 한 장에 보여 줄 알 그림 수 (더 많으면 앞의 6개)

type EggIcon = { Holder: Frame, EggId: string, Made: string? } -- Made: nil 아직 / "lit" 그림 / "dark" 그림자

type Card = {
	Frame: Frame,
	Stroke: UIStroke,
	Badge: Frame,
	Status: TextLabel,
	Button: TextButton,
	ButtonLabel: TextLabel,
	Here: Frame,
	Ground: Color3,
	Unlocked: boolean?,
	EggCount: number,
	Eggs: { EggIcon },
}

local window: UiKit.Window
local infoLabel: TextLabel
local homeButton: TextButton
local cards: { [number]: Card } = {}
local dirty = true
local lastTeleport = 0
local eggGen = 0

-- 그 지역 알 목록: Zone.Eggs 순서 + (빠진 것이 있으면) EggOrder 에서 Zone 이 같은 알
local function zoneEggs(i: number): { string }
	local def: any = Config.Zones[i]
	local list: { string } = {}
	local seen: { [string]: boolean } = {}
	if def and type(def.Eggs) == "table" then
		for _, id in def.Eggs do
			if type(id) == "string" and Config.Eggs[id] and not seen[id] then
				seen[id] = true
				table.insert(list, id)
			end
		end
	end
	for _, id in Config.EggOrder do
		local egg = Config.Eggs[id]
		if egg and egg.Zone == i and not seen[id] then
			seen[id] = true
			table.insert(list, id)
		end
	end
	return list
end

local function rebirths(): number
	local snap: any = State.Snapshot
	return if snap then math.max(0, math.floor(tonumber(snap.Rebirths) or 0)) else 0
end

local function currentZone(): number
	local z = tonumber(player:GetAttribute("Zone"))
	return if z and Config.Zones[z] then z else 1
end

local function tooSoon(button: GuiObject): boolean
	if os.clock() - lastTeleport < TELEPORT_GAP then
		Toasts.Show("잠깐만요! 조금 뒤에 다시 해 봐요 ⏳", "info")
		UiKit.Shake(button, 4, 4)
		return true
	end
	return false
end

local function onZone(i: number)
	local def = Config.Zones[i]
	local card = cards[i]
	if not def or not card then
		return
	end
	if not Config.ZoneUnlocked(i, rebirths()) then
		Toasts.Show("🔒 환생 " .. def.MinRebirth .. "회가 필요해요!", "warn")
		UiKit.Shake(card.Button, 6, 6)
		return
	end
	if tooSoon(card.Button) then
		return
	end
	lastTeleport = os.clock()
	Remotes.Teleport:FireServer("Zone", i)
	window.Close()
end

local function onHome()
	if tooSoon(homeButton) then
		return
	end
	lastTeleport = os.clock()
	Remotes.Teleport:FireServer("Home")
	window.Close()
end

----------------------------------------------------------------------
-- 카드
----------------------------------------------------------------------

local function createCard(parent: Instance, i: number): Card
	local def = Config.Zones[i]
	local pal = def.Palette
	local ground: Color3 = UiKit.Lighten(pal.Ground, 0.2)
	local frame: Frame = Make("Frame", {
		Name = "Zone" .. i,
		LayoutOrder = i,
		BackgroundColor3 = ground,
		ZIndex = 24,
		Parent = parent,
	})
	UiKit.Corner(frame, UDim.new(0.1, 0))
	UiKit.Gradient(frame)
	local stroke = UiKit.Stroke(frame, C.White, 4, true)

	-- 이모지 동그라미
	local badge: Frame = Make("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.32, 0.32),
		BackgroundColor3 = pal.Accent,
		ZIndex = 25,
		Parent = frame,
	})
	Make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = badge })
	UiKit.Corner(badge, UDim.new(0.5, 0))
	UiKit.Stroke(badge, C.White, 3, true)
	UiKit.Label({
		Name = "Emoji",
		Text = def.Emoji,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.8, 0.8),
		ZIndex = 26,
		Parent = badge,
	}, { MaxText = 60 })

	UiKit.Label({
		Name = "ZoneName",
		Text = i .. ". " .. def.Name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.37),
		Size = UDim2.fromScale(0.92, 0.13),
		ZIndex = 25,
		Parent = frame,
	}, { Stroke = UiKit.Darken(pal.Ground, 0.55), MaxText = 26, StrokeThickness = 2.5 })

	-- 그 지역 알들 (작은 그림 한 줄, 칸에 맞게 줄어들어요)
	local eggRow: Frame = Make("Frame", {
		Name = "Eggs",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.505),
		Size = UDim2.fromScale(0.94, 0.135),
		BackgroundTransparency = 1,
		ZIndex = 25,
		Parent = frame,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = eggRow,
	})
	local allEggs = zoneEggs(i)
	local shown = math.min(#allEggs, MAX_EGG_ICONS)
	local eggs: { EggIcon } = {}
	for k = 1, shown do
		local eggId = allEggs[k]
		local egg = Config.Eggs[eggId]
		local holder: Frame = Make("Frame", {
			Name = eggId,
			LayoutOrder = k,
			Size = UDim2.new(1 / math.max(shown, 4), -3, 1, 0),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.35,
			ZIndex = 26,
			Parent = eggRow,
		})
		Make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = holder })
		UiKit.Corner(holder, UDim.new(0.5, 0))
		UiKit.Stroke(holder, UiKit.RarityColor(egg.Rarity), 2, true)
		table.insert(eggs, { Holder = holder, EggId = eggId, Made = nil })
	end

	local status = UiKit.Label({
		Name = "Status",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.645),
		Size = UDim2.fromScale(0.9, 0.1),
		ZIndex = 25,
		Parent = frame,
	}, { Stroke = UiKit.Darken(pal.Ground, 0.55), MaxText = 18 })

	local button, buttonLabel = UiKit.Button({
		Name = "Go",
		Text = "🚀 이동",
		Color = C.Mint,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.955),
		Size = UDim2.fromScale(0.82, 0.19),
		Radius = UDim.new(0.35, 0),
		TextSize = 24,
		ZIndex = 26,
		Parent = frame,
		OnClick = function()
			onZone(i)
		end,
	})

	-- "📍 여기" 표시 (지금 있는 지역)
	local here: Frame = Make("Frame", {
		Name = "Here",
		Position = UDim2.fromScale(0.04, 0.04),
		Size = UDim2.fromScale(0.42, 0.13),
		BackgroundColor3 = C.Gold,
		Visible = false,
		ZIndex = 27,
		Parent = frame,
	})
	UiKit.Corner(here, UDim.new(0.5, 0))
	UiKit.Stroke(here, C.White, 2, true)
	UiKit.Label({
		Text = "📍 여기",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.76),
		ZIndex = 28,
		Parent = here,
	}, { Stroke = UiKit.Darken(C.Gold, 0.45), MaxText = 16 })

	return {
		Frame = frame,
		Stroke = stroke,
		Badge = badge,
		Status = status,
		Button = button,
		ButtonLabel = buttonLabel,
		Here = here,
		Ground = ground,
		Unlocked = nil,
		EggCount = #allEggs,
		Eggs = eggs,
	}
end

-- 알 그림 만들기 (창이 열려 있을 때만, 몇 개마다 한 프레임 쉬면서). 잠긴 지역은 그림자
local function ensureEggIcons()
	eggGen += 1
	local my = eggGen
	task.spawn(function()
		local made = 0
		local r = rebirths()
		for i = 1, #cards do
			local card = cards[i]
			local want = if Config.ZoneUnlocked(i, r) then "lit" else "dark"
			for _, icon in card.Eggs do
				if icon.Made ~= want then
					for _, child in icon.Holder:GetChildren() do
						if child:IsA("GuiObject") then
							child:Destroy()
						end
					end
					UiKit.Viewport("Egg", icon.EggId, icon.Holder, want == "dark")
					icon.Made = want
					made += 1
					if made % 8 == 0 then
						task.wait()
						if eggGen ~= my or not window.IsOpen() then
							return
						end
					end
				end
			end
		end
	end)
end

local function refresh()
	dirty = false
	local r = rebirths()
	local here = currentZone()
	local opened = 0
	for i, def in Config.Zones do
		local card = cards[i]
		if not card then
			continue
		end
		local unlocked = Config.ZoneUnlocked(i, r)
		if unlocked then
			opened += 1
		end
		local isHere = i == here
		card.Here.Visible = isHere
		if unlocked then
			card.Frame.BackgroundColor3 = card.Ground
			card.Badge.BackgroundColor3 = def.Palette.Accent
			card.Status.Text = "💰 코인 ×" .. tostring(def.CoinMult) .. (if card.EggCount > 0 then " · 🥚 " .. card.EggCount .. "종" else "")
			card.ButtonLabel.Text = if isHere then "📍 스폰으로" else "🚀 이동"
			card.Button.BackgroundColor3 = if isHere then C.Lemon else C.Mint
		else
			card.Frame.BackgroundColor3 = card.Ground:Lerp(C.Grey, 0.55)
			card.Badge.BackgroundColor3 = C.Grey
			card.Status.Text = "🔒 환생 " .. def.MinRebirth .. "회 필요"
			card.ButtonLabel.Text = "🔒 잠김"
			card.Button.BackgroundColor3 = C.Grey
		end
		card.Stroke.Color = if isHere then C.Gold elseif unlocked then C.White else C.Grey
		card.Stroke.Thickness = if isHere then 6 else 4
		-- 방금 열린 지역은 통통
		if card.Unlocked == false and unlocked then
			UiKit.Bump(card.Frame, 0.12)
		end
		card.Unlocked = unlocked
	end
	if infoLabel then
		infoLabel.Text = string.format("🔄 환생 %d회 · 열린 지역 %d/%d", r, opened, Config.MaxZone)
	end
	if window and window.IsOpen() then
		ensureEggIcons()
	end
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

function MapWindow.Init(gui: Instance)
	window = UiKit.Window(gui, { Title = "🗺️ 지도", Color = C.Sky, Name = "MapWindow" })
	local content = window.Content

	-- 위쪽 줄: 정보 알약 + 우리 집 버튼
	local top: Frame = Make("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = content,
	})
	local info: Frame = Make("Frame", {
		Name = "Info",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0.6, -6, 0, 42),
		BackgroundColor3 = C.Lavender,
		ZIndex = 24,
		Parent = top,
	})
	UiKit.Corner(info, UDim.new(0.5, 0))
	UiKit.Gradient(info)
	UiKit.Stroke(info, C.White, 3, true)
	infoLabel = UiKit.Label({
		Text = "🔄 환생 0회",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.72),
		ZIndex = 25,
		Parent = info,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.5), MaxText = 22 })
	homeButton = UiKit.Button({
		Name = "Home",
		Text = "🏠 우리 집",
		Color = C.Peach,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.4, -6, 0, 48),
		Radius = UDim.new(0.35, 0),
		TextSize = 26,
		ZIndex = 24,
		Parent = top,
		OnClick = onHome,
	})

	-- 지역 카드 격자
	local scroll = UiKit.Scroller(content, {
		Name = "Zones",
		Position = UDim2.new(0, 0, 0, 60),
		Size = UDim2.new(1, 0, 1, -60),
		ScrollBarImageColor3 = C.Sky,
	})
	UiKit.AutoGrid(scroll, 150, 1.2, 4)
	for i = 1, Config.MaxZone do
		cards[i] = createCard(scroll, i)
	end

	window.OnOpen = refresh
	player:GetAttributeChangedSignal("Zone"):Connect(function()
		if window.IsOpen() then
			refresh()
		else
			dirty = true
		end
	end)
	refresh()
end

function MapWindow.OnSync()
	if window and window.IsOpen() then
		refresh()
	else
		dirty = true
	end
end

function MapWindow.Open()
	if dirty then
		refresh()
	end
	window.Open()
end

function MapWindow.Close()
	if window then
		window.Close()
	end
end

function MapWindow.IsOpen(): boolean
	return window ~= nil and window.IsOpen()
end

return MapWindow
