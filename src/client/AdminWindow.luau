-- ★v7.4 🛠 관리자 페이지 (클라이언트)
-- 서버(AdminService)가 관리자에게만 플레이어 속성 IsAdmin = true 를 줘요 → 그때만 🛠 버튼이 보여요.
-- 속성은 버튼을 보여 주기만 해요: 누를 때마다 서버가 UserId 로 다시 보고, 관리자가 아니면 아무것도 안 해요.
-- 🛠 버튼: Hud 빠른 버튼과 같은 크기·모양 (PC 는 이름 버튼, 폰은 네모), 빠른 버튼·켜고 끄는 버튼 옆 빈 곳
--   (코인 줄·큰 버튼·환생 알약·팁·알림 줄·점프·조이스틱은 피해요). 꾸미기 중엔 숨어요.
-- 창 (UiKit.Window, 한 번에 하나, ✖ / 바깥 / Esc 로 닫혀요): 👤 누구에게 (나 먼저) + 탭 7개
--   💰 코인 (+1K … +1Qa, ×10) · 🐾 펫 (지역·희귀도 순 목록, 등급 ◀ ▶, 크기 4개) · 🥚 알 (희귀 알도)
--   · 🌟 희귀 알 소환 (지역 + 시크릿/천상/이터널) · 🎟 유료 기능 (🧲 ⚡ 🏦 ★v7.5 ♾ 공짜 선물 켜기/끄기, 낮은 화면은 2열)
--   · 🔄 환생 +1 (두 번 눌러요) · 📢 공지 (60자, 서버가 글자 검사)
-- 모두 Remotes.Admin(op, payload) 로 보내요 (payload.Target = 고른 사람 UserId). 서버가 "State" 로 사람 목록을 줘요.
-- 누르는 칸은 모두 44 px 넘게, 568×320 화면에서도 스크롤 목록 말고는 다 보여요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiKit = require(script.Parent.UiKit)
local Toasts = require(script.Parent.Toasts)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local AdminWindow = {}

local player = Players.LocalPlayer
local ATTR = "IsAdmin"
local MIN = 44 -- 누르는 칸 최소 크기
local GAP = 6
local TAP_GAP = 0.25 -- 아주 빠른 연타는 한 번으로 (서버도 0.2초에 한 번)
local REFRESH_EVERY = 3 -- 창이 열려 있으면 몇 초마다 사람 목록 새로 받기
local INK_SOFT = Color3.fromRGB(125, 100, 150)
local OFF_TRACK = Color3.fromRGB(125, 125, 145)
local ADMIN: any = (Config :: any).Admin or {}
local COIN_ADDS: { number } = ADMIN.CoinAdds or { 1e3, 1e6, 1e9, 1e12, 1e15 }
local COIN_CAP: number = ADMIN.CoinCap or 1e17
local ANNOUNCE_MAX: number = ADMIN.AnnounceMax or 60
local MAX_REBIRTHS: number = (Config.Rebirth :: any).MaxRebirths or 25
local SPECIAL_TIERS = { "Hidden", "Celestial", "Eternal" }
local SPECIAL_EMOJI: { [string]: string } = { Hidden = "✨", Celestial = "🌟", Eternal = "🌈" }
local REB_CONFIRM = "한 번 더 누르면 환생 +1!"

type TabDef = { Id: string, Emoji: string, Name: string, Color: Color3 }
local TABS: { TabDef } = {
	{ Id = "Coins", Emoji = "💰", Name = "코인", Color = C.Lemon },
	{ Id = "Pet", Emoji = "🐾", Name = "펫", Color = C.Pink },
	{ Id = "Egg", Emoji = "🥚", Name = "알", Color = C.Peach },
	{ Id = "Rare", Emoji = "🌟", Name = "희귀", Color = C.Gold },
	{ Id = "Paid", Emoji = "🎟", Name = "유료", Color = C.Sky },
	{ Id = "Rebirth", Emoji = "🔄", Name = "환생", Color = C.Lavender },
	{ Id = "Announce", Emoji = "📢", Name = "공지", Color = C.Mint },
}

type SizeDef = { Id: string, Name: string }
local SIZES: { SizeDef } = {
	{ Id = "Small", Name = "작게" },
	{ Id = "Normal", Name = "보통" },
	{ Id = "Huge", Name = "거대" },
	{ Id = "Max", Name = "최대" },
}

type Row = {
	UserId: number,
	Name: string,
	Coins: number,
	Rebirths: number,
	Bag: number,
	BagCap: number,
	Admin: boolean,
	Grants: { [string]: boolean },
	Bought: { [string]: boolean },
	Known: boolean,
}
type Tab = { Def: TabDef, Button: TextButton, Icon: TextLabel, Caption: TextLabel }
type Cell = { Id: string, Button: TextButton, Title: TextLabel, Sub: TextLabel, Color: Color3 }
type List = { Scroll: ScrollingFrame, Headers: { [number]: Frame }, Zones: { [number]: { Cell } }, ById: { [string]: Cell } }
type Chip = { Id: string, Button: TextButton, Label: TextLabel, Color: Color3 }
type GrantRow = {
	Key: string,
	Button: TextButton,
	Icon: TextLabel,
	Title: TextLabel,
	Desc: TextLabel,
	Track: Frame,
	Knob: Frame,
	State: TextLabel,
}

local gui: ScreenGui? = nil
local onToggle: (() -> ())? = nil
local hudVisible = true
local hudButton: TextButton? = nil
local hudIcon: TextLabel? = nil
local hudCaption: TextLabel? = nil
local lastButtonTap = 0

local window: UiKit.Window? = nil
local content: Frame
local targetButton: TextButton
local targetLabel: TextLabel
local tabs: { Tab } = {}
local tabById: { [string]: Tab } = {}
local pages: { [string]: Frame } = {}
local pageArea: Frame
local current = "Coins"
local lastW, lastH = -1, -1
local pageW, pageH = 0, 0

-- 사람 목록 (서버 "State"). 아직 못 받았으면 Players 로 이름만
local rows: { Row } = {}
local rowById: { [number]: Row } = {}
local gotState = false
local targetId = player.UserId
local lastSend = -math.huge
local refreshToken = 0

-- 💰
local coinInfo: TextLabel
local coinHint: TextLabel
local coinButtons: { TextButton } = {}
-- 🐾
local petList: List
local petSel = ""
local petTier = 1
local petSize = "Normal"
local petInfo: TextLabel
local tierPrev: TextButton
local tierNext: TextButton
local tierBox: Frame
local tierLabel: TextLabel
local sizeChips: { Chip } = {}
local petGive: TextButton
local petGiveLabel: TextLabel
-- 🥚
local eggList: List
local eggSel = ""
local eggInfo: TextLabel
local eggGive: TextButton
local eggGiveLabel: TextLabel
local eggHint: TextLabel
-- 🌟
local zoneChips: { Chip } = {}
local rareChips: { Chip } = {}
local rareZone = 1
local rareTier = "Hidden"
local spawnButton: TextButton
local spawnLabel: TextLabel
local rareHint: TextLabel
-- 🎟
local grantRows: { GrantRow } = {}
local paidHint: TextLabel
-- 🔄
local rebInfo: TextLabel
local rebButton: TextButton
local rebLabel: TextLabel
local rebHint: TextLabel
local rebClick: () -> () = function() end
local rebReset: () -> () = function() end
-- 📢
local announceBox: TextBox
local announceCount: TextLabel
local announceSend: TextButton
local announceHint: TextLabel
local fixingText = false
-- 👤 고르기
local picker: Frame
local pickerTitle: TextLabel
local pickerScroll: ScrollingFrame
local pickerRows: { [number]: TextButton } = {}
local pickerOpen = false

----------------------------------------------------------------------
-- 작은 도우미
----------------------------------------------------------------------
local function isAdmin(): boolean
	return player:GetAttribute(ATTR) == true
end

local function setMax(label: Instance?, size: number)
	local c = label and label:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c.MaxTextSize = math.max(8, math.floor(size))
	end
end

local function place(g: GuiObject, x: number, y: number, w: number, h: number)
	g.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	g.Size = UDim2.fromOffset(math.max(0, math.floor(w)), math.max(0, math.floor(h)))
end

-- 보라 글씨 (흰·크림 바탕용, 테두리 없이)
local function inkLabel(props: { [string]: any }, maxText: number?): TextLabel
	if props.TextColor3 == nil then
		props.TextColor3 = C.Ink
	end
	if props.ZIndex == nil then
		props.ZIndex = 24
	end
	return UiKit.Label(props, { Stroke = C.White, StrokeThickness = 0, MaxText = maxText or 20 })
end

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

local function strokeOf(g: Instance): UIStroke?
	return g:FindFirstChildOfClass("UIStroke")
end

local function num(v: any): number
	return if type(v) == "number" and v == v then v else 0
end

local function flags(t: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, key in Config.PassOrder do
		out[key] = type(t) == "table" and t[key] == true
	end
	return out
end

local function displayName(p: Player): string
	local n = p.DisplayName
	if type(n) ~= "string" or n == "" then
		n = p.Name
	end
	return n
end

-- 지금 목록: 서버가 준 것 (나 먼저), 아직이면 이 서버 사람들 이름만
local function currentRows(): { Row }
	if gotState then
		return rows
	end
	local out: { Row } = {}
	local function add(p: Player)
		table.insert(out, {
			UserId = p.UserId,
			Name = displayName(p),
			Coins = 0,
			Rebirths = 0,
			Bag = 0,
			BagCap = 0,
			Admin = false,
			Grants = flags(nil),
			Bought = flags(nil),
			Known = false,
		})
	end
	add(player)
	for _, p in Players:GetPlayers() do
		if p ~= player then
			add(p)
		end
	end
	return out
end

-- 고른 사람 정보 (서버가 준 것만, 모르면 nil)
local function targetRow(): Row?
	return if gotState then rowById[targetId] else nil
end

local function targetName(): string
	if targetId == player.UserId then
		return "나"
	end
	for _, r in currentRows() do
		if r.UserId == targetId then
			return r.Name
		end
	end
	return "친구"
end

-- 서버로 (관리자 아니면 안 보내요. 연타는 한 번으로). Announce 말고는 고른 사람을 같이 보내요
local function send(op: string, payload: { [string]: any }, noTarget: boolean?): boolean
	if not isAdmin() then
		return false
	end
	local now = os.clock()
	if now - lastSend < TAP_GAP then
		return false
	end
	lastSend = now
	if not noTarget then
		payload.Target = targetId
	end
	Remotes.Admin:FireServer(op, payload)
	return true
end

local function refresh()
	if isAdmin() then
		Remotes.Admin:FireServer("Refresh", {})
	end
end

local function sizeOf(mode: string, petId: string): number
	local r = Config.PetSizeRange(petId)
	local v = if mode == "Small" then r.Min elseif mode == "Huge" then r.HugeFrom elseif mode == "Max" then r.Max else 1
	v = math.clamp(v, r.Min, r.Max)
	return math.floor(v * 100 + 0.5) / 100
end

local function sizeText(v: number): string
	local s = string.format("%.2f", v)
	s = (string.gsub(s, "0+$", ""))
	s = (string.gsub(s, "%.$", ""))
	return "×" .. s
end

local function tierText(t: number): string
	local label = UiKit.TierLabel(t)
	return if label == "" then "🐾 기본" else label
end

local function zoneLocked(z: number): boolean
	local r = targetRow()
	if not r then
		return false -- 모르면 서버가 알려 줘요
	end
	return not Config.ZoneUnlocked(z, r.Rebirths)
end

----------------------------------------------------------------------
-- 🛠 HUD 버튼 (빠른 버튼과 같은 모양)
----------------------------------------------------------------------
local function styleButton(w: number, h: number, chip: boolean)
	local btn, icon, cap = hudButton, hudIcon, hudCaption
	if not btn or not icon or not cap then
		return
	end
	btn.Size = UDim2.fromOffset(w, h)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	if chip then
		local left = math.floor(h * 0.98)
		icon.Position = UDim2.fromOffset(math.floor(h * 0.5) + 2, math.floor(h * 0.5))
		icon.Size = UDim2.fromOffset(math.floor(h * 0.72), math.floor(h * 0.72))
		cap.Text = "관리자 페이지"
		cap.TextXAlignment = Enum.TextXAlignment.Left
		cap.AnchorPoint = Vector2.new(0, 0.5)
		cap.Position = UDim2.fromOffset(left, math.floor(h * 0.5))
		cap.Size = UDim2.fromOffset(w - left - 8, math.floor(h * 0.5))
	else
		icon.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.36))
		icon.Size = UDim2.fromOffset(math.floor(w * 0.62), math.floor(h * 0.5))
		cap.Text = "관리자"
		cap.TextXAlignment = Enum.TextXAlignment.Center
		cap.AnchorPoint = Vector2.new(0.5, 0.5)
		cap.Position = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.8))
		cap.Size = UDim2.fromOffset(math.floor(w * 0.96), math.floor(h * 0.3))
	end
end

-- Hud 가 Position/Size 를 오프셋으로 정한 틀 (Toggles · Quick). 튀어나오는 애니메이션 중에도 같은 값
local function offsetRect(name: string): UiKit.Rect?
	local g = gui and gui:FindFirstChild(name)
	if not g or not g:IsA("GuiObject") or not g.Visible then
		return nil
	end
	local p, s = g.Position, g.Size
	if s.X.Offset <= 0 or s.Y.Offset <= 0 then
		return nil
	end
	return { X0 = p.X.Offset, Y0 = p.Y.Offset, X1 = p.X.Offset + s.X.Offset, Y1 = p.Y.Offset + s.Y.Offset }
end

-- root 까지 조상이 모두 보이나
local function shownUnder(d: GuiObject, root: Instance): boolean
	local n: Instance? = d
	while n and n ~= root do
		if n:IsA("GuiObject") and not n.Visible then
			return false
		end
		n = n.Parent
	end
	return true
end

-- 상자 + 안의 보이는 조각 (밖으로 삐져나온 알약까지)
local function addTree(out: { UiKit.Rect }, root: GuiObject, pad: number)
	table.insert(out, UiKit.RectOf(root, pad))
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.AbsoluteSize.X > 0 and shownUnder(d, root) then
			local hasText = (d:IsA("TextLabel") or d:IsA("TextButton")) and (d :: any).Text ~= ""
			if d.BackgroundTransparency < 1 or hasText then
				table.insert(out, UiKit.RectOf(d, pad))
			end
		end
	end
end

-- 피할 것: (꼭) 코인 줄·큰 버튼·켜고 끄는 버튼·빠른 버튼·팁 줄 자리·점프·조이스틱, (되도록) 팁 · 오른쪽 알림 줄 띠
local function obstacles(g: ScreenGui): ({ UiKit.Rect }, { UiKit.Rect })
	local size = g.AbsoluteSize
	local gw, gh = size.X, size.Y
	local hard: { UiKit.Rect } = {}
	local top = g:FindFirstChild("TopBar")
	for _, name in { "TopBar", "SideButtons" } do
		local root = g:FindFirstChild(name)
		if root and root:IsA("GuiObject") and root.Visible then
			addTree(hard, root, 2)
		end
	end
	local sub = top and top:FindFirstChild("SubRow", true)
	if sub and sub:IsA("GuiObject") then
		table.insert(hard, UiKit.RectOf(sub, 2)) -- 금고 알약이 숨어도 그 줄 전체 (버튼이 왔다 갔다 하지 않게)
	end
	local r = offsetRect("Tools") -- ★v7.6 도구 줄 (켜고 끄는 버튼 · 빠른 버튼 · ⚙️ · 🏡)
	if r then
		table.insert(hard, { X0 = r.X0 - 3, Y0 = r.Y0 - 3, X1 = r.X1 + 3, Y1 = r.Y1 + 3 })
	end
	local tipW = math.clamp(gw * 0.46, 260, 580)
	table.insert(hard, { X0 = (gw - tipW) / 2 - 4, Y0 = gh - 64, X1 = (gw + tipW) / 2 + 4, Y1 = gh })
	if UserInputService.TouchEnabled then
		if math.min(gw, gh) <= 500 then
			table.insert(hard, { X0 = gw - 105, Y0 = gh - 100, X1 = gw, Y1 = gh })
		else
			table.insert(hard, { X0 = gw - 180, Y0 = gh - 220, X1 = gw - 40, Y1 = gh - 80 })
		end
		table.insert(hard, { X0 = 0, Y0 = gh - 120, X1 = gw * 0.4, Y1 = gh })
	end
	local all = table.clone(hard)
	local tips = g:FindFirstChild("Tips")
	if tips and tips:IsA("GuiObject") and tips.Visible then
		table.insert(all, UiKit.RectOf(tips, 4))
	end
	-- 오른쪽 알림 줄 띠 (Hud 빠른 버튼과 같은 셈: 코인 줄에 막히면 그 아래부터)
	local small = gh < 500
	local stripW = if small then math.clamp(math.floor(gw * 0.31), 224, 270) else math.clamp(math.floor(gw * 0.19), 300, 360)
	local m = if small then 10 else 16
	local stripX0 = gw - m - stripW - 8
	local stripTop = 0
	if top and top:IsA("GuiObject") then
		local tr = UiKit.RectOf(top, 4)
		if tr.X1 > stripX0 then
			stripTop = tr.Y1
		end
	end
	table.insert(all, { X0 = stripX0, Y0 = stripTop, X1 = gw, Y1 = gh })
	return all, hard
end

-- 자리 찾기 (★v7.6): 도구 줄 아래 → 도구 줄 오른쪽 (위 / 아래 맞춤) → 왼쪽 위 → 오른쪽 위
-- 아무것도 안 가리는 첫 자리 → (세로 화면처럼 모자라면) 꼭 피할 것만 안 가리는 첫 자리 → 가장 덜 가리는 자리
local function placeButton()
	local btn, g = hudButton, gui
	if not btn or not g then
		return
	end
	local want = isAdmin() and hudVisible
	btn.Visible = want
	if not want then
		return
	end
	local size = g.AbsoluteSize
	local gw, gh = size.X, size.Y
	if gw <= 0 or gh <= 0 then
		return
	end
	local w, h = 48, 48
	local toolBox = g:FindFirstChild("Tools")
	if toolBox then
		for _, c in toolBox:GetChildren() do
			if c:IsA("GuiButton") and c.Size.X.Offset >= MIN and c.Size.Y.Offset >= MIN then
				w, h = c.Size.X.Offset, c.Size.Y.Offset
				break
			end
		end
	end
	local chip = w > h * 1.5
	local T = offsetRect("Tools")
	local cands: { { number } } = {}
	local function add(x: number, y: number)
		table.insert(cands, { math.floor(x), math.floor(y) })
	end
	if T then
		-- ★v7.6 도구 줄 아래 (같은 줄처럼) → 오른쪽 위 → 오른쪽 아래
		add(T.X0, T.Y1 + GAP)
		add(T.X1 + GAP, T.Y0)
		add(T.X1 + GAP, T.Y1 - h)
	end
	add(10, 8)
	add(gw - 10 - w, 8)
	local all, hard = obstacles(g)
	local function cost(c: { number }, against: { UiKit.Rect }): number
		local r: UiKit.Rect = { X0 = c[1], Y0 = c[2], X1 = c[1] + w, Y1 = c[2] + h }
		local ov = UiKit.OverlapArea(r, against)
		if r.X0 < 0 or r.Y0 < 0 or r.X1 > gw or r.Y1 > gh then
			ov += w * h -- 화면 밖
		end
		return ov
	end
	local pick: { number }? = nil
	for _, c in cands do
		if cost(c, all) == 0 then
			pick = c
			break
		end
	end
	if not pick then
		for _, c in cands do
			if cost(c, hard) == 0 then
				pick = c
				break
			end
		end
	end
	if not pick then
		local best = math.huge
		for _, c in cands do
			local ov = cost(c, all)
			if ov < best then
				best, pick = ov, c
			end
		end
	end
	local spot = pick or cands[1]
	btn.Position = UDim2.fromOffset(spot[1], spot[2])
	styleButton(w, h, chip)
end

local function makeHudButton(parent: Instance)
	local btn, icon = UiKit.Button({
		Name = "AdminButton",
		Text = "🛠",
		Color = C.Lavender,
		Radius = UDim.new(0.28, 0),
		TextSize = 40,
		Parent = parent,
		OnClick = function()
			local now = os.clock()
			if now - lastButtonTap < 0.25 then
				return
			end
			lastButtonTap = now
			local fn = onToggle
			if fn then
				fn()
			elseif AdminWindow.IsOpen() then
				AdminWindow.Close()
			else
				AdminWindow.Open()
			end
		end,
	})
	icon.Name = "Icon"
	hudCaption = UiKit.Label({
		Name = "Caption",
		Text = "관리자",
		ZIndex = 2,
		Parent = btn,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.5), MaxText = 22, StrokeThickness = 2 })
	btn.Size = UDim2.fromOffset(48, 48)
	btn.Visible = false
	hudButton = btn
	hudIcon = icon
end

----------------------------------------------------------------------
-- 칠하기 (고른 사람 · 고른 것 · 서버 정보에 맞게)
----------------------------------------------------------------------
local function paintTabs()
	for _, t in tabs do
		local on = t.Def.Id == current
		t.Button.BackgroundColor3 = if on then t.Def.Color else UiKit.Lighten(t.Def.Color, 0.62)
		local st = strokeOf(t.Button)
		if st then
			st.Color = if on then C.White else UiKit.Lighten(t.Def.Color, 0.15)
			st.Thickness = if on then 3 else 1.5
		end
		t.Icon.TextTransparency = if on then 0 else 0.2
	end
	for id, page in pages do
		page.Visible = id == current and not pickerOpen
	end
end

local function paintTarget()
	if not targetLabel then
		return
	end
	local name = targetName()
	targetLabel.Text = "👤 " .. name .. (if pickerOpen then " ▴" else " ▾")
end

local function paintCoins()
	if not coinInfo then
		return
	end
	local r = targetRow()
	coinInfo.Text = "💰 " .. targetName() .. (if r then ": " .. Config.FormatNumber(r.Coins) .. " 코인" else "")
end

local function paintCell(cell: Cell, on: boolean)
	cell.Button.BackgroundColor3 = if on then UiKit.Lighten(C.Lemon, 0.3) else UiKit.Lighten(cell.Color, 0.74)
	local st = strokeOf(cell.Button)
	if st then
		st.Color = if on then C.Gold else cell.Color
		st.Thickness = if on then 3 else 2
	end
end

local function paintPet()
	if not petList then
		return
	end
	for id, cell in petList.ById do
		paintCell(cell, id == petSel)
	end
	local def = Config.Pets[petSel]
	if not def then
		return
	end
	tierLabel.Text = tierText(petTier)
	local tc = UiKit.TierColor(petTier)
	tierBox.BackgroundColor3 = UiKit.Lighten(tc, 0.55)
	tierPrev.BackgroundColor3 = if petTier > 1 then C.Sky else C.Grey
	tierNext.BackgroundColor3 = if petTier < Config.MaxTier then C.Sky else C.Grey
	for _, chip in sizeChips do
		local on = chip.Id == petSize
		local v = sizeOf(chip.Id, petSel)
		local name = ""
		for _, s in SIZES do
			if s.Id == chip.Id then
				name = s.Name
			end
		end
		chip.Label.Text = name .. "\n" .. sizeText(v)
		chip.Button.BackgroundColor3 = if on then UiKit.Lighten(C.Lemon, 0.3) else C.White
		local st = strokeOf(chip.Button)
		if st then
			st.Color = if on then C.Gold else UiKit.Lighten(C.Ink, 0.65)
			st.Thickness = if on then 3 else 1.5
		end
	end
	local v = sizeOf(petSize, petSel)
	local label = Config.SizeLabel(v, petSel)
	petInfo.Text = "🐾 "
		.. Config.PetDisplayName(petSel, petTier)
		.. " · "
		.. UiKit.RarityName(def.Rarity)
		.. " · "
		.. sizeText(v)
		.. (if label ~= "" then " " .. label else "")
	petGiveLabel.Text = "🎁 " .. Config.PetDisplayName(petSel, petTier) .. " 주기"
end

local function paintEgg()
	if not eggList then
		return
	end
	for id, cell in eggList.ById do
		paintCell(cell, id == eggSel)
	end
	local egg = Config.Eggs[eggSel]
	if not egg then
		return
	end
	local kind = if egg.Special then "🌟 " .. UiKit.RarityName(egg.Special) else UiKit.RarityName(egg.Rarity)
	eggInfo.Text = "🥚 " .. egg.Name .. "\n" .. kind .. " · ⏳ " .. tostring(egg.HatchTime or 0) .. "초"
	eggGiveLabel.Text = "🎁 " .. egg.Name .. " 주기"
end

local function paintRare()
	if #zoneChips == 0 then
		return
	end
	local wide = zoneChips[1].Button.Size.X.Offset >= 112
	for i, chip in zoneChips do
		local zone = Config.Zones[i]
		local locked = zoneLocked(i)
		local on = i == rareZone
		chip.Label.Text = (if locked then "🔒" else zone.Emoji) .. " " .. (if wide then zone.Name else tostring(i))
		chip.Button.BackgroundColor3 = if on then UiKit.Lighten(C.Lemon, 0.3) elseif locked then UiKit.Lighten(C.Grey, 0.4) else C.White
		local st = strokeOf(chip.Button)
		if st then
			st.Color = if on then C.Gold else UiKit.Lighten(C.Ink, 0.65)
			st.Thickness = if on then 3 else 1.5
		end
	end
	for _, chip in rareChips do
		local on = chip.Id == rareTier
		chip.Button.BackgroundColor3 = if on then chip.Color else UiKit.Lighten(chip.Color, 0.65)
		local st = strokeOf(chip.Button)
		if st then
			st.Color = if on then C.White else chip.Color
			st.Thickness = if on then 3 else 1.5
		end
	end
	local eggId = Config.SpecialEggOf(rareZone, rareTier)
	local egg = if eggId then Config.Eggs[eggId] else nil
	spawnLabel.Text = "🌟 " .. (if egg then egg.Name else "희귀 알") .. " 소환!"
	local locked = zoneLocked(rareZone)
	spawnButton.BackgroundColor3 = if locked then C.Grey else C.Gold
	if locked then
		rareHint.Text = "🔒 " .. targetName() .. "는 아직 " .. Config.Zones[rareZone].Name .. "에 못 가요"
	else
		rareHint.Text = "고른 사람 벨트에 바로 나와요! 알림도 떠요 ✨"
	end
end

local function paintGrantRow(gr: GrantRow, animate: boolean)
	local r = targetRow()
	local on = r ~= nil and r.Grants[gr.Key] == true
	gr.Button.BackgroundColor3 = if on then UiKit.Lighten(C.Sky, 0.6) else C.White
	local st = strokeOf(gr.Button)
	if st then
		st.Color = if on then C.Sky else UiKit.Lighten(C.Ink, 0.65)
		st.Thickness = if on then 3 else 1.5
	end
	gr.Track.BackgroundColor3 = if on then C.Mint else OFF_TRACK
	gr.State.Text = if on then "ON" else "OFF"
	gr.State.Position = UDim2.fromScale(if on then 0.36 else 0.64, 0.5)
	local ss = strokeOf(gr.State)
	if ss then
		ss.Color = UiKit.Darken(if on then C.Mint else OFF_TRACK, 0.5)
	end
	local desc
	if r and r.Admin then
		desc = "관리자는 늘 써요 ✨"
	elseif r and r.Bought[gr.Key] then
		desc = "산 패스 ✅ 선물 없이도 써요"
	elseif on then
		desc = "공짜 선물 중 🎁"
	else
		desc = "켜면 공짜로 써요"
	end
	gr.Desc.Text = desc
	local edge = gr.Knob:GetAttribute("Edge")
	local e = if type(edge) == "number" then edge else 0.25
	local goal = UDim2.fromScale(if on then 1 - e else e, 0.5)
	if animate then
		UiKit.Tween(gr.Knob, 0.18, { Position = goal }, Enum.EasingStyle.Back)
	else
		gr.Knob.Position = goal
	end
end

local function paintPaid(animate: boolean)
	for _, gr in grantRows do
		paintGrantRow(gr, animate)
	end
end

local function paintRebirth()
	if not rebInfo then
		return
	end
	local r = targetRow()
	local name = targetName()
	local max = r ~= nil and r.Rebirths >= MAX_REBIRTHS
	if max and r then
		rebInfo.Text = "🔄 " .. name .. ": " .. r.Rebirths .. "회 (최대예요!)"
	else
		rebInfo.Text = "🔄 " .. name .. (if r then ": " .. r.Rebirths .. "회 → " .. (r.Rebirths + 1) .. "회" else "")
	end
	if rebLabel.Text == REB_CONFIRM then
		return -- 한 번 누른 채 기다리는 중 (3초마다 오는 State 가 풀지 않게)
	end
	rebLabel.Text = if max then "🔄 최대 환생이에요" else "🔄 환생 +1 (공짜)"
	rebButton.BackgroundColor3 = if max then C.Grey else C.Lavender
end

local function paintPicker()
	if not pickerScroll then
		return
	end
	for _, r in currentRows() do
		local btn = pickerRows[r.UserId]
		if btn then
			local on = r.UserId == targetId
			btn.BackgroundColor3 = if on then UiKit.Lighten(C.Lemon, 0.4) else C.White
			local st = strokeOf(btn)
			if st then
				st.Color = if on then C.Gold else UiKit.Lighten(C.Ink, 0.65)
				st.Thickness = if on then 3 else 1.5
			end
			local check = btn:FindFirstChild("Check")
			if check and check:IsA("GuiObject") then
				check.Visible = on
			end
		end
	end
end

local function paintAll()
	paintTabs()
	paintTarget()
	paintCoins()
	paintPet()
	paintEgg()
	paintRare()
	paintPaid(false)
	paintRebirth()
	paintPicker()
end

----------------------------------------------------------------------
-- 👤 누구에게 (목록 위에 덮는 판)
----------------------------------------------------------------------
local layoutPicker: () -> ()

local function rebuildPicker()
	if not pickerScroll then
		return
	end
	for _, b in pickerRows do
		b:Destroy()
	end
	table.clear(pickerRows)
	for i, r in currentRows() do
		local me = r.UserId == player.UserId
		local btn: TextButton = Make("TextButton", {
			Name = "Player" .. r.UserId,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.White,
			LayoutOrder = i,
			ZIndex = 32,
			Selectable = true,
			Parent = pickerScroll,
		})
		UiKit.Corner(btn, UDim.new(0, 12))
		UiKit.Stroke(btn, UiKit.Lighten(C.Ink, 0.65), 1.5, true)
		inkLabel({
			Name = "PlayerName",
			Text = (if me then "⭐ 나 · " else "👤 ") .. r.Name .. (if r.Admin and not me then " 🛠" else ""),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 33,
			Parent = btn,
		}, 20)
		inkLabel({
			Name = "Stats",
			Text = if r.Known
				then string.format("💰 %s · 🔄 %d · 🎒 %d/%d", Config.FormatNumber(r.Coins), r.Rebirths, r.Bag, r.BagCap)
				else "정보를 받는 중… ⏳",
			TextColor3 = INK_SOFT,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 33,
			Parent = btn,
		}, 15)
		UiKit.Label({ Name = "Check", Text = "✔", TextColor3 = C.Mint, Visible = false, ZIndex = 34, Parent = btn }, { Stroke = UiKit.Darken(C.Mint, 0.45), MaxText = 28 })
		local id = r.UserId
		btn.Activated:Connect(function()
			UiKit.PlaySound("Click")
			AdminWindow.ChooseTarget(id)
		end)
		pickerRows[id] = btn
	end
	layoutPicker()
	paintPicker()
end

local function setPicker(open: boolean)
	if not picker then
		return
	end
	pickerOpen = open
	picker.Visible = open
	if open then
		rebuildPicker()
		UiKit.Pop(picker, 0.25)
	end
	paintTabs()
	paintTarget()
end

----------------------------------------------------------------------
-- 자리 (창 안 칸 크기에 맞게)
----------------------------------------------------------------------
local function layoutList(list: List, x: number, y: number, w: number, h: number, minCell: number)
	local scroll = list.Scroll
	place(scroll, x, y, w, h)
	local inner = w - scroll.ScrollBarThickness - 8
	local cols = math.max(1, math.floor((inner + GAP) / (minCell + GAP)))
	local cw = math.floor((inner - (cols - 1) * GAP) / cols)
	local ch = if h >= 300 then 52 else MIN
	local cy = 4
	for z = 1, Config.MaxZone do
		local cells = list.Zones[z]
		local header = list.Headers[z]
		if cells and #cells > 0 and header then
			place(header, 4, cy, math.min(inner, 220), 26)
			cy += 26 + 4
			for i, cell in cells do
				local col = (i - 1) % cols
				local row = math.floor((i - 1) / cols)
				place(cell.Button, 4 + col * (cw + GAP), cy + row * (ch + GAP), cw, ch)
				place(cell.Title, 4, 2, cw - 8, math.floor(ch * 0.56))
				place(cell.Sub, 4, math.floor(ch * 0.58), cw - 8, math.floor(ch * 0.36))
				setMax(cell.Title, math.min(18, ch * 0.4))
				setMax(cell.Sub, math.min(14, ch * 0.3))
			end
			local n = math.ceil(#cells / cols)
			cy += n * ch + (n - 1) * GAP + 10
		end
	end
	scroll.CanvasSize = UDim2.fromOffset(0, cy + 4)
end

-- 목록 + 오른쪽 (좁으면 아래) 조절 칸. 조절 칸 자리 (x, y, w, h) 를 돌려줘요
local function splitList(list: List, PW: number, PH: number, ctrlH: number): (number, number, number, number)
	if PW >= 420 then
		local cw = math.clamp(math.floor(PW * 0.38), 200, 300)
		local lw = PW - cw - GAP
		layoutList(list, 0, 0, lw, PH, if lw >= 480 then 104 else 88)
		return lw + GAP, 0, cw, PH
	end
	local lh = math.max(60, PH - ctrlH - GAP) -- (아주 좁고 낮으면 목록이 작아져도 조절 칸은 다 보여요)
	layoutList(list, 0, 0, PW, lh, 88)
	return 0, lh + GAP, PW, PH - lh - GAP
end

local function layoutCoins(PW: number, PH: number)
	local infoH = math.clamp(math.floor(PH * 0.16), 24, 34)
	place(coinInfo, 4, 0, PW - 8, infoH)
	local n = #coinButtons
	local cols = if (PW - 5 * GAP) / 6 >= 80 then 6 elseif (PW - 2 * GAP) / 3 >= 80 then 3 else 2
	local nRows = math.ceil(n / cols)
	local y0 = infoH + GAP
	local avail = PH - y0 - 22 - GAP
	local bh = math.clamp(math.floor((avail - (nRows - 1) * GAP) / nRows), MIN, 64)
	local bw = math.floor((PW - (cols - 1) * GAP) / cols)
	for i, b in coinButtons do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		place(b, col * (bw + GAP), y0 + row * (bh + GAP), bw, bh)
	end
	local yEnd = y0 + nRows * bh + (nRows - 1) * GAP
	local left = PH - yEnd - GAP
	coinHint.Visible = left >= 16
	place(coinHint, 4, yEnd + GAP, PW - 8, math.min(26, left))
end

local function layoutPet(PW: number, PH: number)
	local rowH0 = if PH >= 300 then 48 else MIN -- (낮으면 조절 칸을 얇게 → 목록 한 줄은 꼭 보여요)
	local cx, cy, cw, ch = splitList(petList, PW, PH, 3 * rowH0 + 2 * GAP)
	local rowH = math.clamp(math.floor((ch - 2 * GAP) / 3), MIN, 60)
	local y = cy
	local spare = ch - (3 * rowH + 2 * GAP)
	if spare >= 30 + GAP then
		local infoH = math.min(52, spare - GAP)
		petInfo.Visible = true
		place(petInfo, cx + 2, y, cw - 4, infoH)
		y += infoH + GAP
	else
		petInfo.Visible = false
	end
	place(tierPrev, cx, y, rowH, rowH)
	place(tierBox, cx + rowH + GAP, y, cw - 2 * (rowH + GAP), rowH)
	place(tierNext, cx + cw - rowH, y, rowH, rowH)
	y += rowH + GAP
	local sw = math.floor((cw - 3 * GAP) / 4)
	for i, chip in sizeChips do
		place(chip.Button, cx + (i - 1) * (sw + GAP), y, sw, rowH)
		place(chip.Label, 2, 2, sw - 4, rowH - 4)
		setMax(chip.Label, math.min(16, rowH * 0.34))
	end
	y += rowH + GAP
	place(petGive, cx, y, cw, rowH)
end

local function layoutEgg(PW: number, PH: number)
	local hintH = 24
	local cx, cy, cw, ch = splitList(eggList, PW, PH, 48 + GAP + hintH)
	local rowH = math.clamp(math.floor(ch * 0.32), MIN, 60)
	local y = cy
	local spare = ch - rowH - GAP - hintH
	if spare >= 36 + GAP then
		local infoH = math.min(64, spare - GAP)
		eggInfo.Visible = true
		place(eggInfo, cx + 2, y, cw - 4, infoH)
		y += infoH + GAP
	else
		eggInfo.Visible = false
	end
	place(eggGive, cx, y, cw, rowH)
	y += rowH + GAP
	local left = cy + ch - y
	eggHint.Visible = left >= 16
	place(eggHint, cx + 2, y, cw - 4, math.min(34, left))
end

local function layoutRare(PW: number, PH: number)
	local nz = #zoneChips
	-- ★v8 지역 16개: 지역 칸 (넓이 minW 이상) 몇 줄 + 등급 칩 줄 + 소환 버튼 줄. 높이가 모자라면 등급 칩과 소환을 한 줄에,
	-- 그래도 모자라면 (세운 작은 폰) 칸 사이를 좁게. 모든 칸은 MIN (44) 이상
	local gap, zc, zr, nRows, sw, together = GAP, nz, 1, 3, PW, false
	for _, try in { { GAP, 56, false }, { GAP, 56, true }, { GAP, MIN, true }, { 3, MIN, true } } do
		local g, minW, tog = try[1], try[2], try[3]
		local c = nz
		while c > 1 and (PW - (c - 1) * g) / c < minW do
			c -= 1
		end
		local r = math.ceil(nz / c)
		c = math.ceil(nz / r)
		local rows = r + (if tog then 1 else 2)
		local w = if tog then math.min(math.max(math.floor(PW * 0.34), 120), PW - 3 * (MIN + g)) else PW
		gap, zc, zr, nRows, sw, together = g, c, r, rows, w, tog
		if rows * MIN + (rows - 1) * g <= PH and w >= 100 then
			break
		end
	end
	local rowH = math.clamp(math.floor((PH - (nRows - 1) * gap) / nRows), MIN, 64)
	local zw = math.floor((PW - (zc - 1) * gap) / zc)
	for i, chip in zoneChips do
		local col = (i - 1) % zc
		local row = math.floor((i - 1) / zc)
		place(chip.Button, col * (zw + gap), row * (rowH + gap), zw, rowH)
		place(chip.Label, 2, 2, zw - 4, rowH - 4)
		setMax(chip.Label, math.min(20, rowH * 0.42))
	end
	local y = zr * (rowH + gap)
	local tw = if together then math.floor((PW - sw - 3 * gap) / 3) else math.floor((PW - 2 * gap) / 3)
	for i, chip in rareChips do
		place(chip.Button, (i - 1) * (tw + gap), y, tw, rowH)
		place(chip.Label, 2, 2, tw - 4, rowH - 4)
		setMax(chip.Label, math.min(20, rowH * 0.42))
	end
	if together then
		place(spawnButton, PW - sw, y, sw, rowH)
	else
		y += rowH + gap
		place(spawnButton, 0, y, PW, rowH)
	end
	y += rowH + gap
	local left = PH - y
	rareHint.Visible = left >= 16
	place(rareHint, 4, y, PW - 8, math.min(28, left))
end

local function layoutGrantRow(gr: GrantRow, x: number, y: number, W: number, h: number)
	place(gr.Button, x, y, W, h)
	local icon = math.floor(h * 0.66)
	place(gr.Icon, 8, (h - icon) / 2, icon, icon)
	local tw = math.clamp(math.min(math.floor(h * 1.3), math.floor(W * 0.22)), 52, 80) -- ★v7.5 2열이면 스위치를 조금 좁게
	local th = math.clamp(math.floor(h * 0.46), 24, 32)
	place(gr.Track, W - tw - 10, (h - th) / 2, tw, th)
	gr.Knob:SetAttribute("Edge", math.clamp((th * 0.78 / 2 + th * 0.12) / tw, 0.1, 0.45))
	local textX = 8 + icon + 8
	local textW = W - textX - tw - 18
	place(gr.Title, textX, h * 0.08, textW, h * 0.48)
	setMax(gr.Title, math.min(22, h * 0.4, textW / 6))
	place(gr.Desc, textX, h * 0.56, textW, h * 0.36)
	setMax(gr.Desc, math.min(15, h * 0.3, textW / 12))
end

-- ★v7.5 패스가 4개 (🧲 ⚡ 🏦 ♾): 한 줄씩 44 px 가 안 들어가는 낮은 화면 (568×320, 667×375) 은 2열 (2×2)
local function layoutPaid(PW: number, PH: number)
	local n = #grantRows
	local cols = if n > 1 and (PH - (n - 1) * GAP) / n < MIN then 2 else 1
	local rows = math.ceil(n / cols)
	local colW = (PW - (cols - 1) * GAP) / cols
	local rowH = math.clamp(math.floor((PH - (rows - 1) * GAP) / rows), MIN, if cols > 1 then 60 else 72)
	for i, gr in grantRows do
		local c = (i - 1) % cols
		local r = (i - 1) // cols
		layoutGrantRow(gr, c * (colW + GAP), r * (rowH + GAP), colW, rowH)
	end
	local y = rows * (rowH + GAP)
	local left = PH - y
	paidHint.Visible = left >= 16
	place(paidHint, 4, y, PW - 8, math.min(28, left))
end

local function layoutRebirth(PW: number, PH: number)
	local infoH = math.clamp(math.floor(PH * 0.26), 26, 56)
	local bh = math.clamp(math.floor(PH * 0.34), MIN, 72)
	local bw = math.min(PW, 460)
	place(rebInfo, 4, 0, PW - 8, infoH)
	place(rebButton, (PW - bw) / 2, infoH + GAP, bw, bh)
	local y = infoH + GAP + bh + GAP
	local left = PH - y
	rebHint.Visible = left >= 16
	place(rebHint, 4, y, PW - 8, math.min(30, left))
end

local function layoutAnnounce(PW: number, PH: number)
	local boxH = math.clamp(math.floor(PH * 0.34), MIN, 72)
	place(announceBox, 0, 0, PW, boxH)
	local sendW = math.clamp(math.floor(PW * 0.34), 130, 240)
	local bh = math.clamp(math.floor(PH * 0.3), MIN, 60)
	place(announceSend, PW - sendW, boxH + GAP, sendW, bh)
	place(announceCount, 4, boxH + GAP, PW - sendW - GAP - 8, bh)
	local y = boxH + GAP + bh + GAP
	local left = PH - y
	announceHint.Visible = left >= 16
	place(announceHint, 4, y, PW - 8, math.min(30, left))
end

layoutPicker = function()
	if not picker then
		return
	end
	local W, H = pageW, pageH
	if W <= 0 or H <= 0 then
		return
	end
	local titleH = 26
	place(pickerTitle, 10, 4, W - 20, titleH)
	local sy = titleH + 8
	place(pickerScroll, 6, sy, W - 12, H - sy - 6)
	local inner = W - 12 - pickerScroll.ScrollBarThickness - 8
	local rh = if H >= 300 then 56 else 48
	local y = 4
	for _, r in currentRows() do
		local btn = pickerRows[r.UserId]
		if btn then
			place(btn, 4, y, inner, rh)
			local checkW = math.floor(rh * 0.5)
			local textW = inner - 12 - checkW - 8
			local nameL = btn:FindFirstChild("PlayerName")
			local stats = btn:FindFirstChild("Stats")
			local check = btn:FindFirstChild("Check")
			if nameL and nameL:IsA("GuiObject") then
				place(nameL, 12, 2, textW, rh * 0.54)
				setMax(nameL, math.min(20, rh * 0.42))
			end
			if stats and stats:IsA("GuiObject") then
				place(stats, 12, rh * 0.56, textW, rh * 0.38)
				setMax(stats, math.min(15, rh * 0.32))
			end
			if check and check:IsA("GuiObject") then
				place(check, inner - checkW - 8, (rh - checkW) / 2, checkW, checkW)
			end
			y += rh + GAP
		end
	end
	pickerScroll.CanvasSize = UDim2.fromOffset(0, y + 4)
end

local function layout(force: boolean?)
	if not window or not content then
		return
	end
	local sc = UiKit.ScaleOf(content)
	local abs = content.AbsoluteSize
	local W, H = math.floor(abs.X / sc + 0.5), math.floor(abs.Y / sc + 0.5)
	if W <= 0 or H <= 0 or (not force and W == lastW and H == lastH) then
		return
	end
	lastW, lastH = W, H
	-- 맨 위 줄: [👤 누구에게 ▾] [탭 7개] (좁으면 👤 한 줄 + 탭 줄들)
	local rowH = math.clamp(math.floor(H * 0.09), MIN, 54)
	local targetW = math.clamp(math.floor(W * 0.24), 110, 220)
	local n = #tabs
	local tabMin, tabGap = 50, 4
	local pageY
	local tw, tabH = 0, rowH
	if W - targetW - GAP >= n * tabMin + (n - 1) * tabGap then
		place(targetButton, 0, 0, targetW, rowH)
		local x0 = targetW + GAP
		tw = math.floor((W - x0 - (n - 1) * tabGap) / n)
		for i, t in tabs do
			place(t.Button, x0 + (i - 1) * (tw + tabGap), 0, tw, tabH)
		end
		pageY = rowH + GAP
	else
		place(targetButton, 0, 0, W, rowH)
		local per = math.max(1, math.floor((W + tabGap) / (tabMin + tabGap)))
		local lines = math.ceil(n / per)
		per = math.ceil(n / lines)
		tw = math.floor((W - (per - 1) * tabGap) / per)
		for i, t in tabs do
			local col = (i - 1) % per
			local line = math.floor((i - 1) / per)
			place(t.Button, col * (tw + tabGap), rowH + GAP + line * (tabH + tabGap), tw, tabH)
		end
		pageY = rowH + GAP + lines * tabH + (lines - 1) * tabGap + GAP
	end
	-- 탭 안: 좁으면 [이모지 / 이름], 넓으면 [이모지 이름]
	for _, t in tabs do
		if tw >= 92 then
			local icon = math.floor(tabH * 0.64)
			place(t.Icon, 8, (tabH - icon) / 2, icon, icon)
			place(t.Caption, 8 + icon + 4, tabH * 0.2, tw - icon - 20, tabH * 0.6)
			t.Caption.TextXAlignment = Enum.TextXAlignment.Left
			setMax(t.Caption, math.min(22, tabH * 0.42))
		else
			place(t.Icon, 2, tabH * 0.04, tw - 4, tabH * 0.5)
			place(t.Caption, 2, tabH * 0.56, tw - 4, tabH * 0.38)
			t.Caption.TextXAlignment = Enum.TextXAlignment.Center
			setMax(t.Caption, math.min(16, tabH * 0.32))
		end
	end
	setMax(targetLabel, math.min(22, rowH * 0.46))
	local PW, PH = W, math.max(MIN, H - pageY)
	pageW, pageH = PW, PH
	place(pageArea, 0, pageY, PW, PH)
	place(picker, 0, pageY, PW, PH)
	for _, page in pages do
		place(page, 0, 0, PW, PH)
	end
	layoutCoins(PW, PH)
	layoutPet(PW, PH)
	layoutEgg(PW, PH)
	layoutRare(PW, PH)
	layoutPaid(PW, PH)
	layoutRebirth(PW, PH)
	layoutAnnounce(PW, PH)
	layoutPicker()
	paintRare() -- 지역 칸이 넓으면 이름까지
end

----------------------------------------------------------------------
-- 만들기
----------------------------------------------------------------------
local function newPage(id: string): Frame
	local page: Frame = Make("Frame", {
		Name = "Page" .. id,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 23,
		Parent = pageArea,
	})
	pages[id] = page
	return page
end

local function hint(parent: Instance, name: string, text: string): TextLabel
	return inkLabel({
		Name = name,
		Text = text,
		TextColor3 = INK_SOFT,
		Parent = parent,
	}, 16)
end

local function chipButton(parent: Instance, name: string, text: string, color: Color3, onTap: () -> ()): Chip
	local btn: TextButton = Make("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.White,
		ZIndex = 24,
		Selectable = true,
		Parent = parent,
	})
	UiKit.Corner(btn, UDim.new(0, 12))
	UiKit.Stroke(btn, UiKit.Lighten(C.Ink, 0.65), 1.5, true)
	local label = inkLabel({ Name = "Label", Text = text, ZIndex = 25, Parent = btn }, 20)
	pressFeel(btn, 0.94)
	btn.Activated:Connect(function()
		UiKit.PlaySound("Click")
		onTap()
	end)
	return { Id = name, Button = btn, Label = label, Color = color }
end

local function bigButton(parent: Instance, name: string, text: string, color: Color3, onTap: () -> ()): (TextButton, TextLabel)
	return UiKit.Button({
		Name = name,
		Text = text,
		Color = color,
		Radius = UDim.new(0, 14),
		TextSize = 24,
		ZIndex = 24,
		Parent = parent,
		OnClick = onTap,
	})
end

local function makeList(parent: Instance, name: string, color: Color3): List
	local scroll = UiKit.Scroller(parent, {
		Name = name,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollBarImageColor3 = color,
		ZIndex = 24,
	})
	local headers: { [number]: Frame } = {}
	for z, zone in Config.Zones do
		local pill = UiKit.Pill(scroll, zone.Emoji .. " " .. zone.Name, color, { Name = "Zone" .. z, ZIndex = 25 }, 16)
		headers[z] = pill
	end
	return { Scroll = scroll, Headers = headers, Zones = {}, ById = {} }
end

local function addCell(list: List, zone: number, id: string, title: string, sub: string, color: Color3, onPick: (string) -> ())
	local btn: TextButton = Make("TextButton", {
		Name = id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = UiKit.Lighten(color, 0.74),
		ZIndex = 25,
		Selectable = true,
		Parent = list.Scroll,
	})
	UiKit.Corner(btn, UDim.new(0, 10))
	UiKit.Stroke(btn, color, 2, true)
	local t = inkLabel({ Name = "Title", Text = title, ZIndex = 26, Parent = btn }, 18)
	local s = inkLabel({ Name = "Sub", Text = sub, TextColor3 = UiKit.Darken(color, 0.35), ZIndex = 26, Parent = btn }, 14)
	btn.Activated:Connect(function()
		UiKit.PlaySound("Click")
		onPick(id)
	end)
	local cell: Cell = { Id = id, Button = btn, Title = t, Sub = s, Color = color }
	local z = if Config.Zones[zone] then zone else 1
	local bucket = list.Zones[z]
	if not bucket then
		bucket = {}
		list.Zones[z] = bucket
	end
	table.insert(bucket, cell)
	list.ById[id] = cell
end

local function buildTop(parent: Instance)
	local btn, label = UiKit.Button({
		Name = "Target",
		Text = "👤 나 ▾",
		Color = C.Sky,
		Radius = UDim.new(0, 14),
		TextSize = 22,
		ZIndex = 23,
		Parent = parent,
		OnClick = function()
			setPicker(not pickerOpen)
		end,
	})
	targetButton, targetLabel = btn, label
	for _, def in TABS do
		local tb: TextButton = Make("TextButton", {
			Name = "Tab" .. def.Id,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = def.Color,
			ZIndex = 23,
			Selectable = true,
			Parent = parent,
		})
		UiKit.Corner(tb, UDim.new(0, 12))
		UiKit.Gradient(tb)
		UiKit.Stroke(tb, C.White, 2, true)
		local icon = UiKit.Label({ Name = "Icon", Text = def.Emoji, ZIndex = 24, Parent = tb }, { MaxText = 26 })
		local cap = UiKit.Label({ Name = "Caption", Text = def.Name, ZIndex = 24, Parent = tb }, { Stroke = UiKit.Darken(def.Color, 0.45), MaxText = 18 })
		pressFeel(tb, 0.94)
		local id = def.Id
		tb.Activated:Connect(function()
			UiKit.PlaySound("Click")
			AdminWindow.SwitchTab(id)
		end)
		local t: Tab = { Def = def, Button = tb, Icon = icon, Caption = cap }
		table.insert(tabs, t)
		tabById[def.Id] = t
	end
end

local function buildCoins()
	local page = newPage("Coins")
	coinInfo = inkLabel({ Name = "Info", Text = "💰", TextXAlignment = Enum.TextXAlignment.Left, Parent = page }, 22)
	for i, n in COIN_ADDS do
		local amount = n
		local b = bigButton(page, "Coin" .. i, "💰 +" .. Config.FormatNumber(amount), C.Lemon, function()
			send("Coins", { Add = amount })
		end)
		table.insert(coinButtons, b)
	end
	local times = bigButton(page, "CoinTimes", "💰 ×10", C.Orange, function()
		send("Coins", { Times = 10 })
	end)
	table.insert(coinButtons, times)
	coinHint = hint(page, "Hint", "×10 = 지금 코인의 10배 (최대 " .. Config.FormatNumber(COIN_CAP) .. ")")
end

local function buildPet()
	local page = newPage("Pet")
	petList = makeList(page, "PetList", C.Pink)
	local seen: { [string]: boolean } = {}
	local order: { string } = {}
	for _, id in Config.PetOrder do
		if Config.Pets[id] and not seen[id] then
			seen[id] = true
			table.insert(order, id)
		end
	end
	local extra: { string } = {}
	for id in Config.Pets do
		if not seen[id] then
			table.insert(extra, id)
		end
	end
	table.sort(extra)
	for _, id in extra do
		table.insert(order, id)
	end
	for _, id in order do
		local def = Config.Pets[id]
		local rarity = (Config.Rarities :: any)[def.Rarity]
		local special = rarity and rarity.Special
		local sub = (if special then "🌟 " else "") .. UiKit.RarityName(def.Rarity)
		addCell(petList, def.Zone or 1, id, def.Name, sub, UiKit.RarityColor(def.Rarity), function(pick: string)
			petSel = pick
			paintPet()
		end)
	end
	petSel = order[1] or ""
	petInfo = inkLabel({ Name = "Info", Text = "", Parent = page }, 18)
	tierPrev = bigButton(page, "TierPrev", "◀", C.Sky, function()
		if petTier > 1 then
			petTier -= 1
			paintPet()
		end
	end)
	tierNext = bigButton(page, "TierNext", "▶", C.Sky, function()
		if petTier < Config.MaxTier then
			petTier += 1
			paintPet()
		end
	end)
	tierBox = Make("Frame", { Name = "Tier", BackgroundColor3 = C.White, ZIndex = 24, Parent = page })
	UiKit.Corner(tierBox, UDim.new(0, 12))
	UiKit.Stroke(tierBox, C.White, 2, true)
	tierLabel = inkLabel({
		Name = "Label",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.7),
		ZIndex = 25,
		Parent = tierBox,
	}, 20)
	for _, s in SIZES do
		local id = s.Id
		local chip = chipButton(page, "Size" .. id, s.Name, C.Lemon, function()
			petSize = id
			paintPet()
		end)
		chip.Id = id
		table.insert(sizeChips, chip)
	end
	petGive, petGiveLabel = bigButton(page, "Give", "🎁 주기", C.Mint, function()
		if Config.Pets[petSel] then
			send("Pet", { PetId = petSel, Tier = petTier, Size = sizeOf(petSize, petSel) })
		end
	end)
end

local function buildEgg()
	local page = newPage("Egg")
	eggList = makeList(page, "EggList", C.Peach)
	local seen: { [string]: boolean } = {}
	local first = ""
	local function addEgg(id: string)
		local egg = Config.Eggs[id]
		if not egg or seen[id] then
			return
		end
		seen[id] = true
		if first == "" then
			first = id
		end
		local color = UiKit.RarityColor(egg.Special or egg.Rarity)
		local sub = if egg.Special
			then "🌟 " .. UiKit.RarityName(egg.Special)
			else UiKit.RarityName(egg.Rarity)
		addCell(eggList, egg.Zone or 1, id, egg.Name, sub, color, function(pick: string)
			eggSel = pick
			paintEgg()
		end)
	end
	for z = 1, Config.MaxZone do
		for _, id in Config.ZoneEggOrder[z] or {} do
			addEgg(id)
		end
		for _, id in Config.ZoneSpecialEggOrder[z] or {} do
			addEgg(id)
		end
	end
	local extra: { string } = {}
	for id in Config.Eggs do
		if not seen[id] then
			table.insert(extra, id)
		end
	end
	table.sort(extra)
	for _, id in extra do
		addEgg(id)
	end
	eggSel = first
	eggInfo = inkLabel({ Name = "Info", Text = "", Parent = page }, 18)
	eggGive, eggGiveLabel = bigButton(page, "Give", "🎁 주기", C.Mint, function()
		if Config.Eggs[eggSel] then
			send("Egg", { EggId = eggSel })
		end
	end)
	eggHint = hint(page, "Hint", "가방이 차면 빈 받침대로 가요 🏠")
end

local function buildRare()
	local page = newPage("Rare")
	for z = 1, Config.MaxZone do
		local zone = z
		local chip = chipButton(page, "Zone" .. z, Config.Zones[z].Emoji .. " " .. z, C.Lemon, function()
			rareZone = zone
			paintRare()
		end)
		table.insert(zoneChips, chip)
	end
	for _, tier in SPECIAL_TIERS do
		local id = tier
		local color = UiKit.RarityColor(tier)
		local chip = chipButton(page, "Tier" .. tier, (SPECIAL_EMOJI[tier] or "🌟") .. " " .. UiKit.RarityName(tier), color, function()
			rareTier = id
			paintRare()
		end)
		chip.Id = tier
		table.insert(rareChips, chip)
	end
	spawnButton, spawnLabel = bigButton(page, "Spawn", "🌟 소환!", C.Gold, function()
		send("RareEgg", { Zone = rareZone, Tier = rareTier })
	end)
	rareHint = hint(page, "Hint", "")
end

local function buildPaid()
	local page = newPage("Paid")
	for _, key in Config.PassOrder do
		local pass = (Config.Passes :: any)[key]
		if pass then
			local row: TextButton = Make("TextButton", {
				Name = "Grant" .. key,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = C.White,
				ZIndex = 24,
				Selectable = true,
				Parent = page,
			})
			UiKit.Corner(row, UDim.new(0, 12))
			UiKit.Stroke(row, UiKit.Lighten(C.Ink, 0.65), 1.5, true)
			local icon = UiKit.Label({ Name = "Emoji", Text = pass.Emoji, ZIndex = 25, Parent = row }, { MaxText = 34 })
			local title = inkLabel({
				Name = "Title",
				Text = pass.Name,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 25,
				Parent = row,
			}, 22)
			local desc = inkLabel({
				Name = "Desc",
				Text = "",
				TextColor3 = INK_SOFT,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 25,
				Parent = row,
			}, 15)
			local track: Frame = Make("Frame", { Name = "Switch", BackgroundColor3 = OFF_TRACK, ZIndex = 25, Parent = row })
			UiKit.Corner(track, UDim.new(0.5, 0))
			UiKit.Stroke(track, C.White, 1.5, true)
			local state = UiKit.Label({
				Name = "State",
				Text = "OFF",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromScale(0.5, 0.8),
				ZIndex = 26,
				Parent = track,
			}, { MaxText = 16, StrokeThickness = 1.5 })
			local knob: Frame = Make("Frame", {
				Name = "Knob",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromScale(0.78, 0.78),
				BackgroundColor3 = C.White,
				ZIndex = 27,
				Parent = track,
			})
			Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = knob })
			UiKit.Corner(knob, UDim.new(0.5, 0))
			pressFeel(row, 0.97)
			local gr: GrantRow = { Key = key, Button = row, Icon = icon, Title = title, Desc = desc, Track = track, Knob = knob, State = state }
			row.Activated:Connect(function()
				local r = targetRow()
				local on = not (r ~= nil and r.Grants[key] == true)
				if send("Grant", { Key = key, On = on }) then
					UiKit.PlaySound("Click")
					if r then
						r.Grants[key] = on -- 바로 바꿔 보여 줘요 (서버 State 가 곧 맞춰 줘요)
					end
					paintGrantRow(gr, true)
					UiKit.Bump(row, if on then 0.06 else -0.04)
				end
			end)
			table.insert(grantRows, gr)
		end
	end
	paidHint = hint(page, "Hint", "켜면 그 친구가 공짜로 써요 · 끄면 원래대로 🎁")
end

local function buildRebirth()
	local page = newPage("Rebirth")
	rebInfo = inkLabel({ Name = "Info", Text = "", Parent = page }, 24)
	rebButton, rebLabel = bigButton(page, "Rebirth", "🔄 환생 +1 (공짜)", C.Lavender, function()
		rebClick()
	end)
	rebClick, rebReset = UiKit.TwoTap(rebButton, rebLabel, REB_CONFIRM, function()
		local r = targetRow()
		if r and r.Rebirths >= MAX_REBIRTHS then
			Toasts.Show("🔄 이미 최대 환생이에요!", "info")
			return
		end
		send("Rebirth", {})
	end)
	rebHint = hint(page, "Hint", "코인은 그대로예요 💰 (두 번 눌러요)")
end

-- 60자 넘으면 잘라요 (줄바꿈은 빈칸으로)
local function cleanAnnounce(text: string): (string, number)
	local s = string.gsub(text, "[\r\n\t]", " ")
	local n, bad = utf8.len(s)
	if not n then
		s = string.sub(s, 1, (bad or 1) - 1)
		n = utf8.len(s) or 0
	end
	local count: number = n :: number
	if count > ANNOUNCE_MAX then
		local cut = utf8.offset(s, ANNOUNCE_MAX + 1)
		if cut then
			s = string.sub(s, 1, cut - 1)
		end
		count = ANNOUNCE_MAX
	end
	return s, count
end

local function sendAnnounce()
	local text = string.match(announceBox.Text, "^%s*(.-)%s*$") or ""
	if text == "" then
		Toasts.Show("📢 보낼 말을 먼저 써 주세요!", "info")
		return
	end
	if send("Announce", { Text = text }, true) then
		announceBox.Text = ""
	end
end

local function buildAnnounce()
	local page = newPage("Announce")
	announceBox = Make("TextBox", {
		Name = "Box",
		Text = "",
		PlaceholderText = "📢 모두에게 보낼 말 (" .. ANNOUNCE_MAX .. "자까지)",
		PlaceholderColor3 = INK_SOFT,
		ClearTextOnFocus = false,
		Font = UiKit.Font,
		TextColor3 = C.Ink,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = C.White,
		ZIndex = 24,
		Parent = page,
	})
	UiKit.Corner(announceBox, UDim.new(0, 12))
	UiKit.Stroke(announceBox, C.Mint, 2, true)
	Make("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 10, Parent = announceBox })
	Make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = announceBox })
	announceCount = inkLabel({
		Name = "Count",
		Text = "0/" .. ANNOUNCE_MAX,
		TextColor3 = INK_SOFT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = page,
	}, 18)
	announceBox:GetPropertyChangedSignal("Text"):Connect(function()
		if fixingText then
			return
		end
		local s, n = cleanAnnounce(announceBox.Text)
		if s ~= announceBox.Text then
			fixingText = true
			announceBox.Text = s
			fixingText = false
		end
		announceCount.Text = n .. "/" .. ANNOUNCE_MAX
	end)
	announceBox.FocusLost:Connect(function(enter: boolean)
		if enter then
			sendAnnounce()
		end
	end)
	announceSend = bigButton(page, "Send", "📢 보내기", C.Mint, sendAnnounce)
	announceHint = hint(page, "Hint", "글자 검사를 하고 모두에게 보여요 📢")
end

local function buildPicker(parent: Instance)
	picker = Make("Frame", {
		Name = "Picker",
		BackgroundColor3 = UiKit.Lighten(C.Sky, 0.82),
		Visible = false,
		Active = true,
		ZIndex = 30,
		Parent = parent,
	})
	UiKit.Corner(picker, UDim.new(0, 16))
	UiKit.Stroke(picker, C.Sky, 3, true)
	pickerTitle = inkLabel({
		Name = "Title",
		Text = "👤 누구에게 줄까요?",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
		Parent = picker,
	}, 20)
	pickerScroll = UiKit.Scroller(picker, {
		Name = "List",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollBarImageColor3 = C.Sky,
		ZIndex = 31,
	})
end

-- 서버가 보낸 사람 목록 (관리자에게만): 값은 모두 다시 정리해요, 나 먼저
local function onState(payload: any)
	if type(payload) ~= "table" or type(payload.Players) ~= "table" then
		return
	end
	local mine: { Row } = {}
	local others: { Row } = {}
	for _, r in payload.Players do
		if type(r) == "table" and type(r.UserId) == "number" then
			local name = if type(r.Name) == "string" and r.Name ~= "" then r.Name elseif type(r.User) == "string" then r.User else "친구"
			local row: Row = {
				UserId = r.UserId,
				Name = name,
				Coins = num(r.Coins),
				Rebirths = math.floor(num(r.Rebirths)),
				Bag = math.floor(num(r.Bag)),
				BagCap = math.floor(num(r.BagCap)),
				Admin = r.Admin == true,
				Grants = flags(r.Grants),
				Bought = flags(r.Bought),
				Known = true,
			}
			table.insert(if row.UserId == player.UserId then mine else others, row)
		end
	end
	for _, r in others do
		table.insert(mine, r)
	end
	rows = mine
	rowById = {}
	for _, r in rows do
		rowById[r.UserId] = r
	end
	gotState = true
	if targetId ~= player.UserId and not rowById[targetId] then
		targetId = player.UserId
		Toasts.Show("👋 그 친구가 나갔어요! 이제 나에게 줘요", "info")
	end
	if pickerOpen then
		rebuildPicker()
	end
	paintAll()
end

local function startRefresh()
	refreshToken += 1
	local my = refreshToken
	refresh()
	task.spawn(function()
		while refreshToken == my do
			task.wait(REFRESH_EVERY)
			local win = window
			if refreshToken ~= my or not win or not win.IsOpen() then
				return
			end
			refresh()
		end
	end)
end

function AdminWindow.Init(mainGui: ScreenGui, toggleFn: (() -> ())?)
	if window then
		return
	end
	gui = mainGui
	onToggle = toggleFn
	makeHudButton(mainGui)
	local win = UiKit.Window(mainGui, {
		Title = "🛠 관리자 페이지",
		Color = C.Lavender,
		Name = "AdminWindow",
	})
	window = win
	content = win.Content
	buildTop(content)
	pageArea = Make("Frame", { Name = "Pages", BackgroundTransparency = 1, ZIndex = 23, Parent = content })
	buildCoins()
	buildPet()
	buildEgg()
	buildRare()
	buildPaid()
	buildRebirth()
	buildAnnounce()
	buildPicker(content)
	layout(true)
	paintAll()
	win.OnOpen = function()
		pickerOpen = false
		picker.Visible = false
		layout(true)
		paintAll()
		startRefresh()
	end
	win.OnClose = function()
		refreshToken += 1
		rebReset()
		if pickerOpen then
			setPicker(false)
		end
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layout(false)
	end)
	mainGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(layout, true)
		-- Hud 가 버튼 줄을 다시 놓은 뒤에 (Hud 도 한 번 더 미뤄서 놓아요)
		task.defer(function()
			task.defer(placeButton)
		end)
	end)
	player:GetAttributeChangedSignal(ATTR):Connect(function()
		placeButton()
		if not isAdmin() and win.IsOpen() then
			win.Close()
		end
	end)
	Remotes.Admin.OnClientEvent:Connect(function(op: any, payload: any)
		if op == "State" then
			onState(payload)
		end
	end)
	-- Esc 로 닫기
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape and win.IsOpen() then
			win.Close()
		end
	end)
	task.defer(placeButton)
	-- 코인 줄이 커지거나 HUD 가 움직이면 따라가요 (관리자에게만, 1초에 한 번)
	task.spawn(function()
		while true do
			task.wait(1)
			if hudVisible and isAdmin() then
				placeButton()
			end
		end
	end)
end

function AdminWindow.Open()
	local win = window
	if not win then
		return
	end
	if not isAdmin() then
		Toasts.Show("🛠 관리자만 열 수 있어요!", "warn")
		return
	end
	win.Open()
end

function AdminWindow.Close()
	local win = window
	if win then
		win.Close()
	end
end

function AdminWindow.IsOpen(): boolean
	local win = window
	return win ~= nil and win.IsOpen()
end

-- 꾸미기 중엔 🛠 버튼도 숨겨요 (창은 init.client 가 다른 창처럼 닫아요)
function AdminWindow.SetHudVisible(visible: boolean)
	hudVisible = visible
	placeButton()
	if not visible and AdminWindow.IsOpen() then
		AdminWindow.Close()
	end
end

function AdminWindow.SwitchTab(id: string)
	if not pages[id] then
		return
	end
	current = id
	if pickerOpen then
		setPicker(false)
	end
	rebReset()
	paintTabs()
end

-- 👤 대상 고르기 (목록에 있는 사람만)
function AdminWindow.ChooseTarget(userId: number)
	local found = false
	for _, r in currentRows() do
		if r.UserId == userId then
			found = true
		end
	end
	if not found then
		return
	end
	local changed = userId ~= targetId
	targetId = userId
	setPicker(false)
	paintAll()
	if changed then
		refresh()
		Toasts.Show("👤 이제 " .. targetName() .. "에게 줘요!", "info")
	end
end

-- 검사용
function AdminWindow.Panel(): Frame?
	local win = window
	return if win then win.Panel else nil
end
function AdminWindow.Button(): TextButton?
	return hudButton
end
function AdminWindow.TargetButton(): TextButton?
	return targetButton
end
function AdminWindow.TabButton(id: string): TextButton?
	local t = tabById[id]
	return if t then t.Button else nil
end
function AdminWindow.Page(id: string): Frame?
	return pages[id]
end
function AdminWindow.CoinButton(i: number): TextButton?
	return coinButtons[i]
end
function AdminWindow.PetCell(id: string): TextButton?
	local c = petList and petList.ById[id]
	return if c then c.Button else nil
end
function AdminWindow.EggCell(id: string): TextButton?
	local c = eggList and eggList.ById[id]
	return if c then c.Button else nil
end
function AdminWindow.TierPrev(): TextButton?
	return tierPrev
end
function AdminWindow.TierNext(): TextButton?
	return tierNext
end
function AdminWindow.SizeChip(mode: string): TextButton?
	for _, c in sizeChips do
		if c.Id == mode then
			return c.Button
		end
	end
	return nil
end
function AdminWindow.PetGive(): TextButton?
	return petGive
end
function AdminWindow.EggGive(): TextButton?
	return eggGive
end
function AdminWindow.ZoneChip(z: number): TextButton?
	local c = zoneChips[z]
	return if c then c.Button else nil
end
function AdminWindow.RareTierChip(tier: string): TextButton?
	for _, c in rareChips do
		if c.Id == tier then
			return c.Button
		end
	end
	return nil
end
function AdminWindow.SpawnButton(): TextButton?
	return spawnButton
end
function AdminWindow.GrantRow(key: string): TextButton?
	for _, g in grantRows do
		if g.Key == key then
			return g.Button
		end
	end
	return nil
end
function AdminWindow.RebirthButton(): TextButton?
	return rebButton
end
function AdminWindow.AnnounceBox(): TextBox?
	return announceBox
end
function AdminWindow.AnnounceSend(): TextButton?
	return announceSend
end
function AdminWindow.PickerRow(userId: number): TextButton?
	return pickerRows[userId]
end
function AdminWindow.IsPickerOpen(): boolean
	return pickerOpen
end
function AdminWindow.Target(): number
	return targetId
end
function AdminWindow.Current(): string
	return current
end

return AdminWindow
