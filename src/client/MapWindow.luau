-- 🗺️ 지도 창: 지역 8개 카드 (이모지, 이름, 지역 색, 🔒 환생 N회 / "이동"), 지금 있는 지역 표시,
-- "🏠 우리 집" 버튼. 이동은 Teleport("Zone", i) / Teleport("Home") (서버가 환생 수를 다시 확인해요)
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
}

local window: UiKit.Window
local infoLabel: TextLabel
local homeButton: TextButton
local cards: { [number]: Card } = {}
local dirty = true
local lastTeleport = 0

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
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.fromScale(0.4, 0.4),
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
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.92, 0.15),
		ZIndex = 25,
		Parent = frame,
	}, { Stroke = UiKit.Darken(pal.Ground, 0.55), MaxText = 26, StrokeThickness = 2.5 })

	local status = UiKit.Label({
		Name = "Status",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.61),
		Size = UDim2.fromScale(0.9, 0.11),
		ZIndex = 25,
		Parent = frame,
	}, { Stroke = UiKit.Darken(pal.Ground, 0.55), MaxText = 18 })

	local button, buttonLabel = UiKit.Button({
		Name = "Go",
		Text = "🚀 이동",
		Color = C.Mint,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.95),
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
	}
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
			card.Status.Text = "💰 코인 ×" .. tostring(def.CoinMult)
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
