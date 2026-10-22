-- ★v7.2 ⚙️ 게임 옵션 창 (Hud 의 ⚙️ 옵션 버튼으로 열어요. 다른 창처럼 한 번에 하나, ✖ / 바깥 / Esc 로 닫혀요, 꾸미기 중엔 닫혀요)
-- 🙈 부화 숨기기 (Settings.HideHatch): 줄 전체가 켜고 끄는 스위치 + 한 줄 설명 (예전 Hud 버튼과 같은 말풍선)
-- 🔔 알 알림 (Settings.AlertLevel, Config.AlertLevels 5단계): 고르면 바로 바꿔 보여 주고 Remotes.SetSetting + 말풍선
--   (예전 Hud 🔔 고르는 창과 같아요: 지금 단계 ✔ + 노란 바탕). 값 검사는 서버 그대로 (DataService · Config.SettingValue).
-- 자리: 넉넉하면 세로 줄 5개 (이모지 · 이름 · 설명 · ✔), 낮은 화면 (가로 폰) 은 한 줄에 큰 카드 5개 (이모지 + 짧은 이름 + ✔)
--   + 고른 단계 설명 한 줄. 어느 쪽이든 누르는 칸은 44 px 넘게, 스크롤 없이 다 보여요.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local OptionsWindow = {}

local HIDE_ON = "🙈 부화 화면을 숨겨요! 작은 알림만 떠요"
local HIDE_OFF = "🐣 부화 화면을 다시 보여 줘요!"
local OFF_TRACK = Color3.fromRGB(125, 125, 145)
local INK_SOFT = Color3.fromRGB(125, 100, 150)
local MIN_ROW = 44 -- 누르는 칸 최소 높이

local window: UiKit.Window? = nil
local content: Frame
local hideRow: TextButton
local hideIcon: TextLabel
local hideTitle: TextLabel
local hideDesc: TextLabel
local hideTrack: Frame
local hideKnob: Frame
local hideState: TextLabel
local alertTitle: TextLabel
local levelDesc: TextLabel
local rows: { TextButton } = {}
local lastHideTap = 0
local cards = false -- 지금 카드 모양인가 (낮은 화면)
local lastW, lastH = -1, -1
local knobOff, knobOn = 0.25, 0.75

-- 글자 크기 상한 (줄마다 같게)
local function setMax(label: Instance?, size: number)
	local c = label and label:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c.MaxTextSize = math.max(8, math.floor(size))
	end
end

local function hideOn(): boolean
	return State.GetSetting("HideHatch") == true
end

local function alertLevelNow(): number
	local v = State.GetSetting("AlertLevel")
	return if type(v) == "number" then v else 0
end

----------------------------------------------------------------------
-- 🙈 부화 숨기기
----------------------------------------------------------------------
local function paintHide(animate: boolean)
	if not hideRow then
		return
	end
	local on = hideOn()
	hideRow.BackgroundColor3 = if on then UiKit.Lighten(C.Lavender, 0.55) else C.White
	local st = hideRow:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = if on then C.Lavender else UiKit.Lighten(C.Ink, 0.65)
		st.Thickness = if on then 3 else 1.5
	end
	hideTrack.BackgroundColor3 = if on then C.Mint else OFF_TRACK
	hideState.Text = if on then "ON" else "OFF"
	hideState.Position = UDim2.fromScale(if on then 0.36 else 0.64, 0.5)
	local ss = hideState:FindFirstChildOfClass("UIStroke")
	if ss then
		ss.Color = UiKit.Darken(if on then C.Mint else OFF_TRACK, 0.5)
	end
	hideIcon.TextTransparency = if on then 0 else 0.25
	local goal = UDim2.fromScale(if on then knobOn else knobOff, 0.5)
	if animate then
		UiKit.Tween(hideKnob, 0.18, { Position = goal }, Enum.EasingStyle.Back)
		UiKit.Bump(hideRow, if on then 0.06 else -0.04)
	else
		hideKnob.Position = goal
	end
end

-- 누르면 바로 바꿔 보여 주고 (낙관적) 서버로 + 말풍선 (예전 Hud 🙈 버튼과 똑같아요)
local function onHideTap()
	local now = os.clock()
	if now - lastHideTap < 0.2 then
		return -- 아주 빠른 연타는 한 번으로
	end
	lastHideTap = now
	local value = not hideOn()
	State.SetSettingLocal("HideHatch", value) -- OnSetting → paintHide
	Remotes.SetSetting:FireServer("HideHatch", value)
	UiKit.PlaySound("Click")
	Toasts.Show(if value then HIDE_ON else HIDE_OFF, if value then "good" else "info")
end

----------------------------------------------------------------------
-- 🔔 알 알림 단계
----------------------------------------------------------------------
-- 지금 단계 줄(카드)에 ✔ + 노란 바탕, 아래 설명 한 줄
local function paintLevels()
	local level = alertLevelNow()
	for i, row in rows do
		local on = i - 1 == level
		row.BackgroundColor3 = if on then UiKit.Lighten(C.Lemon, 0.45) else C.White
		local check = row:FindFirstChild("Check")
		if check and check:IsA("GuiObject") then
			check.Visible = on
		end
		local st = row:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = if on then C.Gold else UiKit.Lighten(C.Ink, 0.65)
			st.Thickness = if on then 3 else 1.5
		end
	end
	local info = Config.AlertLevelInfo(level)
	if levelDesc then
		levelDesc.Text = info.Emoji .. " " .. info.Name .. " · " .. info.Desc
	end
end

-- 단계 고르기 → 바로 바꿔 보여 주고 (낙관적) 서버로 + 말풍선. 지금 단계면 그냥 둬요 (서버로 안 보내요)
local function chooseLevel(n: number)
	local info = Config.AlertLevels[n + 1]
	if not info then
		return
	end
	if n == alertLevelNow() then
		local row = rows[n + 1]
		if row then
			UiKit.Bump(row, 0.06)
		end
		return
	end
	State.SetSettingLocal("AlertLevel", n)
	Remotes.SetSetting:FireServer("AlertLevel", n)
	Toasts.Show(info.Toast, "good")
end

----------------------------------------------------------------------
-- 자리 (창 안 칸 크기에 맞게)
----------------------------------------------------------------------
local function child(parent: Instance, name: string): GuiObject?
	local c = parent:FindFirstChild(name)
	return if c and c:IsA("GuiObject") then c else nil
end

local function layoutHide(W: number, h: number)
	hideRow.Position = UDim2.fromOffset(0, 0)
	hideRow.Size = UDim2.fromOffset(W, h)
	local icon = math.floor(h * 0.68)
	hideIcon.Position = UDim2.fromOffset(8, math.floor((h - icon) / 2))
	hideIcon.Size = UDim2.fromOffset(icon, icon)
	local tw = math.clamp(math.floor(h * 1.3), 58, 80)
	local th = math.clamp(math.floor(h * 0.46), 24, 32)
	hideTrack.Position = UDim2.fromOffset(W - tw - 10, math.floor((h - th) / 2))
	hideTrack.Size = UDim2.fromOffset(tw, th)
	local edge = math.clamp((th * 0.78 / 2 + th * 0.12) / tw, 0.1, 0.45)
	knobOff, knobOn = edge, 1 - edge
	local textX = 8 + icon + 8
	local textW = W - textX - tw - 18
	hideTitle.Position = UDim2.fromOffset(textX, math.floor(h * 0.08))
	hideTitle.Size = UDim2.fromOffset(textW, math.floor(h * 0.48))
	setMax(hideTitle, math.min(22, h * 0.4, textW / 6))
	hideDesc.Position = UDim2.fromOffset(textX, math.floor(h * 0.56))
	hideDesc.Size = UDim2.fromOffset(textW, math.floor(h * 0.36))
	setMax(hideDesc, math.min(15, h * 0.3, textW / 19))
end

-- 세로 줄: [이모지 | 이름 / 설명 | ✔]
local function layoutRow(row: TextButton, x: number, y: number, rw: number, rowH: number)
	row.Position = UDim2.fromOffset(x, y)
	row.Size = UDim2.fromOffset(rw, rowH)
	local icon = math.floor(rowH * 0.66)
	local textX = icon + 12
	local checkW = math.floor(rowH * 0.5)
	local textW = rw - textX - checkW - 8
	local emoji = child(row, "Emoji")
	if emoji then
		emoji.Position = UDim2.fromOffset(6, math.floor((rowH - icon) / 2))
		emoji.Size = UDim2.fromOffset(icon, icon)
	end
	local name = child(row, "LevelName")
	if name then
		name.Visible = true
		name.Position = UDim2.fromOffset(textX, 2)
		name.Size = UDim2.fromOffset(textW, math.floor(rowH * 0.54))
		setMax(name, math.min(20, rowH * 0.46, textW / 13))
	end
	local desc = child(row, "Desc")
	if desc then
		desc.Visible = true
		desc.Position = UDim2.fromOffset(textX, math.floor(rowH * 0.56))
		desc.Size = UDim2.fromOffset(textW, math.floor(rowH * 0.38))
		setMax(desc, math.min(15, rowH * 0.34, textW / 18))
	end
	local short = child(row, "Short")
	if short then
		short.Visible = false
	end
	local check = child(row, "Check")
	if check then
		check.Position = UDim2.fromOffset(rw - checkW - 6, math.floor((rowH - checkW) / 2))
		check.Size = UDim2.fromOffset(checkW, checkW)
	end
end

-- 카드: [이모지 / 짧은 이름], ✔ 는 오른쪽 위 구석
local function layoutCard(row: TextButton, x: number, y: number, cw: number, ch: number)
	row.Position = UDim2.fromOffset(x, y)
	row.Size = UDim2.fromOffset(cw, ch)
	local icon = math.floor(math.min(cw * 0.62, ch * 0.5))
	local emoji = child(row, "Emoji")
	if emoji then
		emoji.Position = UDim2.fromOffset(math.floor((cw - icon) / 2), math.floor(ch * 0.1))
		emoji.Size = UDim2.fromOffset(icon, icon)
	end
	for _, n in { "LevelName", "Desc" } do
		local g = child(row, n)
		if g then
			g.Visible = false
		end
	end
	local short = child(row, "Short")
	if short then
		short.Visible = true
		short.Position = UDim2.fromOffset(3, math.floor(ch * 0.64))
		short.Size = UDim2.fromOffset(cw - 6, math.floor(ch * 0.28))
		setMax(short, math.min(20, ch * 0.24, (cw - 6) / 3.3))
	end
	local check = child(row, "Check")
	if check then
		local s = math.floor(math.min(cw, ch) * 0.3)
		check.Position = UDim2.fromOffset(cw - s - 2, 2)
		check.Size = UDim2.fromOffset(s, s)
	end
end

local function layout(force: boolean?)
	local win = window
	if not win or not content then
		return
	end
	local sc = UiKit.ScaleOf(content)
	local abs = content.AbsoluteSize
	local W, H = math.floor(abs.X / sc + 0.5), math.floor(abs.Y / sc + 0.5)
	if W <= 0 or H <= 0 or (not force and W == lastW and H == lastH) then
		return
	end
	lastW, lastH = W, H
	local gap = if H < 320 then 6 else 8
	local rgap = 6
	local hideH = math.clamp(math.floor(H * 0.17), 52, 68)
	local titleH = 28
	cards = H < hideH + titleH + 2 * gap + 5 * MIN_ROW + 4 * rgap
	if cards then
		hideH = math.clamp(math.floor(H * 0.24), 46, 60)
		titleH = 24
	end
	layoutHide(W, hideH)
	alertTitle.Position = UDim2.fromOffset(4, hideH + gap)
	alertTitle.Size = UDim2.fromOffset(W - 8, titleH)
	local y0 = hideH + gap + titleH + gap
	local n = #rows
	if not cards then
		local rowH = math.clamp(math.floor((H - y0 - (n - 1) * rgap) / n), MIN_ROW, 60)
		for i, row in rows do
			layoutRow(row, 0, y0 + (i - 1) * (rowH + rgap), W, rowH)
		end
		levelDesc.Visible = false
	else
		local cgap = 6
		local descH = 22
		local cw = math.floor((W - (n - 1) * cgap) / n)
		local ch = math.clamp(H - y0 - gap - descH, MIN_ROW, math.floor(cw * 1.4))
		for i, row in rows do
			layoutCard(row, (i - 1) * (cw + cgap), y0, cw, ch)
		end
		levelDesc.Visible = true
		levelDesc.Position = UDim2.fromOffset(4, y0 + ch + gap)
		levelDesc.Size = UDim2.fromOffset(W - 8, descH)
	end
end

----------------------------------------------------------------------
-- 만들기
----------------------------------------------------------------------
local function pressFeel(btn: GuiButton, down: number)
	local scale = UiKit.Scale(btn)
	btn.MouseButton1Down:Connect(function()
		UiKit.Tween(scale, 0.08, { Scale = down })
	end)
	btn.MouseButton1Up:Connect(function()
		UiKit.Tween(scale, 0.15, { Scale = 1 })
	end)
	btn.MouseLeave:Connect(function()
		UiKit.Tween(scale, 0.15, { Scale = 1 })
	end)
end

local function buildHide(parent: Instance)
	hideRow = Make("TextButton", {
		Name = "HideHatch",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.White,
		ZIndex = 23,
		Selectable = true,
		Parent = parent,
	})
	UiKit.Corner(hideRow, UDim.new(0, 12))
	UiKit.Stroke(hideRow, UiKit.Lighten(C.Ink, 0.65), 1.5, true)
	hideIcon = UiKit.Label({ Name = "Emoji", Text = "🙈", ZIndex = 24, Parent = hideRow }, { MaxText = 34 })
	hideTitle = UiKit.Label({
		Name = "Title",
		Text = "부화 숨기기",
		TextColor3 = C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
		Parent = hideRow,
	}, { Stroke = C.White, StrokeThickness = 0, MaxText = 22 })
	hideDesc = UiKit.Label({
		Name = "Desc",
		Text = "켜면 부화 화면 없이 작은 알림만 떠요",
		TextColor3 = INK_SOFT,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
		Parent = hideRow,
	}, { Stroke = C.White, StrokeThickness = 0, MaxText = 15 })
	hideTrack = Make("Frame", {
		Name = "Switch",
		BackgroundColor3 = OFF_TRACK,
		ZIndex = 24,
		Parent = hideRow,
	})
	UiKit.Corner(hideTrack, UDim.new(0.5, 0))
	UiKit.Stroke(hideTrack, C.White, 1.5, true)
	hideState = UiKit.Label({
		Name = "State",
		Text = "OFF",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.8),
		ZIndex = 25,
		Parent = hideTrack,
	}, { MaxText = 16, StrokeThickness = 1.5 })
	hideKnob = Make("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		BackgroundColor3 = C.White,
		ZIndex = 26,
		Parent = hideTrack,
	})
	Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = hideKnob })
	UiKit.Corner(hideKnob, UDim.new(0.5, 0))
	pressFeel(hideRow, 0.97)
	hideRow.Activated:Connect(onHideTap)
end

local function buildLevels(parent: Instance)
	alertTitle = UiKit.Label({
		Name = "AlertTitle",
		Text = "🔔 알 알림 · 어디까지 받을까요?",
		TextColor3 = C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = parent,
	}, { Stroke = C.White, MaxText = 20 })
	for i, info in Config.AlertLevels do
		local n = i - 1
		local row: TextButton = Make("TextButton", {
			Name = "Level" .. n,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.White,
			ZIndex = 23,
			Selectable = true,
			Parent = parent,
		})
		UiKit.Corner(row, UDim.new(0, 10))
		UiKit.Stroke(row, UiKit.Lighten(C.Ink, 0.65), 1.5, true)
		UiKit.Label({ Name = "Emoji", Text = info.Emoji, ZIndex = 24, Parent = row }, { MaxText = 34 })
		UiKit.Label({
			Name = "LevelName",
			Text = info.Name,
			TextColor3 = C.Ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 24,
			Parent = row,
		}, { Stroke = C.White, StrokeThickness = 0, MaxText = 20 })
		UiKit.Label({
			Name = "Desc",
			Text = info.Desc,
			TextColor3 = INK_SOFT,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 24,
			Parent = row,
		}, { Stroke = C.White, StrokeThickness = 0, MaxText = 15 })
		UiKit.Label({
			Name = "Short",
			Text = info.Short,
			TextColor3 = C.Ink,
			Visible = false,
			ZIndex = 24,
			Parent = row,
		}, { Stroke = C.White, StrokeThickness = 0, MaxText = 20 })
		UiKit.Label({ Name = "Check", Text = "✔", TextColor3 = C.Mint, Visible = false, ZIndex = 25, Parent = row }, { Stroke = UiKit.Darken(C.Mint, 0.45), MaxText = 28 })
		pressFeel(row, 0.96)
		row.Activated:Connect(function()
			UiKit.PlaySound("Click")
			chooseLevel(n)
		end)
		table.insert(rows, row)
	end
	levelDesc = UiKit.Label({
		Name = "LevelDesc",
		Text = "",
		TextColor3 = INK_SOFT,
		Visible = false,
		ZIndex = 23,
		Parent = parent,
	}, { Stroke = C.White, StrokeThickness = 0, MaxText = 16 })
end

function OptionsWindow.Init(gui: Instance)
	if window then
		return
	end
	-- 작은 창: PC 는 480 × 470, 가로 폰은 화면 높이의 95 % (UiKit.Window 가 맞춰요)
	local win = UiKit.Window(gui, {
		Title = "⚙️ 게임 옵션",
		Color = C.Sky,
		Name = "OptionsWindow",
		Size = UDim2.new(0.9, 0, 0, 470),
		MaxSize = Vector2.new(480, 470),
	})
	window = win
	content = win.Content
	buildHide(content)
	buildLevels(content)
	paintHide(false)
	paintLevels()
	win.OnOpen = function()
		paintHide(false)
		paintLevels()
		layout(true)
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layout(false)
	end)
	if gui:IsA("GuiBase2d") then
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			task.defer(layout, true)
		end)
	end
	layout(true)
	State.OnSetting(function(key: string)
		if key == "HideHatch" then
			paintHide(win.IsOpen())
		elseif key == "AlertLevel" then
			paintLevels()
		end
	end)
	State.OnSync(function()
		paintHide(false)
		paintLevels()
	end)
	-- Esc 로 닫기 (다른 창은 단축키를 다시 눌러 닫아요)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape and win.IsOpen() then
			win.Close()
		end
	end)
end

function OptionsWindow.Open()
	local win = window
	if win then
		win.Open()
	end
end

function OptionsWindow.Close()
	local win = window
	if win then
		win.Close()
	end
end

function OptionsWindow.IsOpen(): boolean
	local win = window
	return win ~= nil and win.IsOpen()
end

-- 검사용: 창 / 🙈 줄 / 단계 줄(카드) n (0..4) / 카드 모양인가
function OptionsWindow.Panel(): Frame?
	local win = window
	return if win then win.Panel else nil
end

function OptionsWindow.HideButton(): TextButton?
	return hideRow
end

function OptionsWindow.LevelButton(n: number): TextButton?
	return rows[n + 1]
end

function OptionsWindow.IsCards(): boolean
	return cards
end

return OptionsWindow
