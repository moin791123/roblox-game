-- 🏆 순위표 창: ⚡ 초당 수익 / 🔄 환생 TOP 10 + 내 순위. (설계: docs/DESIGN.md "LeaderboardWindow", v3)
-- 서버 LeaderboardService 가 LeaderboardSync 로 보내 줘요 (들어올 때 + 1분마다 + 이 서버 값이 바뀔 때).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local LeaderboardWindow = {}

export type Row = { Rank: number, UserId: number, Name: string, Value: number }
export type MineEntry = { Rank: number?, Value: number }
export type Board = {
	Income: { Row },
	Rebirths: { Row },
	Global: boolean,
	Studio: boolean,
	UpdatedAt: number,
	Mine: { [string]: MineEntry },
}

type RowCard = {
	Frame: Frame,
	Stroke: UIStroke,
	Badge: Frame,
	RankLabel: TextLabel,
	NameLabel: TextLabel,
	ValuePill: Frame,
	ValueLabel: TextLabel,
}

type TabDef = { Key: string, Text: string, Color: Color3 }

local TABS: { TabDef } = {
	{ Key = "Income", Text = "⚡ 초당 수익", Color = C.Orange },
	{ Key = "Rebirths", Text = "🔄 환생", Color = C.Lavender },
}
local TOP_N = Config.Leaderboard.TopN
local ROW_H = 52
local MEDALS = { "🥇", "🥈", "🥉" }
local MEDAL_COLORS = {
	Color3.fromRGB(255, 214, 80), -- 금
	Color3.fromRGB(205, 215, 232), -- 은
	Color3.fromRGB(232, 162, 102), -- 동
}
local ROW_COLORS = { C.White, Color3.fromRGB(255, 238, 246) }

local player = Players.LocalPlayer
local window: UiKit.Window
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Income"
local board: Board? = nil
local rowCards: { RowCard } = {}
local scopePill: Frame
local scopeLabel: TextLabel
local mineBar: Frame
local mineLabel: TextLabel
local emptyLabel: TextLabel
local scroll: ScrollingFrame
local dirty = true
local renderQueued = false
local lastRank: { [string]: number } = {}

local function formatValue(tab: string, value: number): string
	if tab == "Income" then
		return "⚡ " .. Config.FormatNumber(value) .. "/초"
	end
	return "🔄 " .. Config.FormatNumber(value) .. "회"
end

local function tabColor(tab: string): Color3
	for _, t in TABS do
		if t.Key == tab then
			return t.Color
		end
	end
	return C.Pink
end

----------------------------------------------------------------------
-- 서버 데이터 정리 (이상한 값이 와도 창은 안 깨지게)
----------------------------------------------------------------------
local function cleanRows(v: any): { Row }
	local out: { Row } = {}
	if type(v) ~= "table" then
		return out
	end
	for _, r in v do
		if type(r) == "table" and #out < TOP_N then
			table.insert(out, {
				Rank = tonumber(r.Rank) or (#out + 1),
				UserId = tonumber(r.UserId) or 0,
				Name = if type(r.Name) == "string" then r.Name else "???",
				Value = tonumber(r.Value) or 0,
			})
		end
	end
	table.sort(out, function(a, b)
		return a.Rank < b.Rank
	end)
	return out
end

local function cleanMine(v: any): { [string]: MineEntry }
	local out: { [string]: MineEntry } = {}
	if type(v) ~= "table" then
		return out
	end
	for _, t in TABS do
		local m = v[t.Key]
		if type(m) == "table" then
			local rank = tonumber(m.Rank)
			out[t.Key] = { Rank = if rank and rank >= 1 then math.floor(rank) else nil, Value = tonumber(m.Value) or 0 }
		end
	end
	return out
end

local function rowsOf(tab: string): { Row }
	local b = board
	if not b then
		return {}
	end
	return if tab == "Income" then b.Income else b.Rebirths
end

----------------------------------------------------------------------
-- 내 순위
----------------------------------------------------------------------
local function myValue(tab: string): number?
	local snap = State.Snapshot
	if snap then
		local v = if tab == "Income" then snap.Income else snap.Rebirths
		return math.floor(tonumber(v) or 0)
	end
	local b = board
	local mine = b and b.Mine[tab]
	return if mine then mine.Value else nil
end

-- 서버가 알려 준 내 순위 → 없으면 TOP 10 안에서 찾기
local function myRank(tab: string): number?
	local b = board
	if not b then
		return nil
	end
	local mine = b.Mine[tab]
	if mine and mine.Rank then
		return mine.Rank
	end
	for _, row in rowsOf(tab) do
		if row.UserId == player.UserId then
			return row.Rank
		end
	end
	return nil
end

local function updateMine()
	if not mineLabel then
		return
	end
	local value = myValue(currentTab)
	if value == nil then
		mineBar.Visible = false
		return
	end
	mineBar.Visible = true
	local rank = myRank(currentTab)
	if rank then
		mineLabel.Text = string.format("🙋 내 순위: %d위 · %s", rank, formatValue(currentTab, value))
		mineBar.BackgroundColor3 = if rank <= 3 then MEDAL_COLORS[rank] else C.Lemon
		local before = lastRank[currentTab]
		if before and rank < before then
			UiKit.Bump(mineBar, 0.12) -- 순위가 올랐어요!
		end
		lastRank[currentTab] = rank
	elseif value <= 0 then
		mineLabel.Text = if currentTab == "Income"
			then "🐾 집 받침대에 펫을 놓으면 순위에 올라가요!"
			else "🔄 환생하면 순위에 올라가요!"
		mineBar.BackgroundColor3 = C.Mint
	else
		mineLabel.Text = string.format("🙋 나: %s · 조금만 더 힘내요! 💪", formatValue(currentTab, value))
		mineBar.BackgroundColor3 = C.Lemon
	end
end

----------------------------------------------------------------------
-- 그리기
----------------------------------------------------------------------
local function updateScope()
	if not scopeLabel then
		return
	end
	local b = board
	if not b then
		scopeLabel.Text = "⏳ 불러오는 중"
		scopePill.BackgroundColor3 = C.Grey
	elseif b.Global then
		scopeLabel.Text = "🌍 전체 서버"
		scopePill.BackgroundColor3 = C.Sky
	elseif b.Studio then
		scopeLabel.Text = "🧪 Studio: 이 서버"
		scopePill.BackgroundColor3 = C.Peach
	else
		scopeLabel.Text = "🏠 이 서버"
		scopePill.BackgroundColor3 = C.Mint
	end
end

local function render()
	dirty = false
	if not window then
		return
	end
	local rows = rowsOf(currentTab)
	local color = tabColor(currentTab)
	for i, card in rowCards do
		local row = rows[i]
		card.Frame.Visible = row ~= nil
		if row then
			local rank = math.max(1, math.floor(row.Rank))
			local medal = rank <= #MEDALS
			local isMe = row.UserId == player.UserId
			card.Frame.BackgroundColor3 = if medal then MEDAL_COLORS[rank] else ROW_COLORS[(rank % 2) + 1]
			card.Stroke.Color = if isMe then C.Pink else C.White
			card.Stroke.Thickness = if isMe then 5 else 3
			card.Badge.BackgroundColor3 = if medal then C.White else C.Lavender
			card.RankLabel.Text = if medal then MEDALS[rank] else tostring(rank)
			card.NameLabel.Text = if isMe then row.Name .. " (나)" else row.Name
			card.ValuePill.BackgroundColor3 = color
			card.ValueLabel.Text = formatValue(currentTab, row.Value)
		end
	end
	if not board then
		emptyLabel.Text = "순위를 불러오는 중… ⏳"
	elseif currentTab == "Income" then
		emptyLabel.Text = "아직 순위가 없어요 🐣\n펫을 집에 놓고 다시 와 봐요!"
	else
		emptyLabel.Text = "아직 환생한 친구가 없어요 🔄\n첫 번째가 되어 봐요!"
	end
	emptyLabel.Visible = #rows == 0
	updateScope()
	updateMine()
end

-- 같은 프레임에 여러 번 와도 한 번만 그려요
local function queueRender()
	if renderQueued then
		return
	end
	renderQueued = true
	task.defer(function()
		renderQueued = false
		if window and window.IsOpen() then
			render()
		else
			dirty = true
		end
	end)
end

local function setTab(tab: string)
	currentTab = tab
	for key, btn in tabButtons do
		local selected = key == tab
		btn.BackgroundColor3 = if selected then tabColor(key) else C.Grey
		if selected then
			UiKit.Bump(btn, 0.1)
		end
	end
	if window then
		render()
		scroll.CanvasPosition = Vector2.zero
	end
end

local function createRow(parent: Instance, i: number): RowCard
	local frame: Frame = Make("Frame", {
		Name = "Row" .. i,
		LayoutOrder = i,
		Size = UDim2.new(1, -8, 0, ROW_H),
		BackgroundColor3 = C.White,
		Visible = false,
		ZIndex = 24,
		Parent = parent,
	})
	UiKit.Corner(frame, UDim.new(0.3, 0))
	UiKit.Gradient(frame)
	local stroke = UiKit.Stroke(frame, C.White, 3, true)

	local badge: Frame = Make("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(ROW_H - 12, ROW_H - 12),
		BackgroundColor3 = C.Lavender,
		ZIndex = 25,
		Parent = frame,
	})
	UiKit.Corner(badge, UDim.new(0.5, 0))
	UiKit.Stroke(badge, C.White, 2, true)
	local rankLabel = UiKit.Label({
		Text = tostring(i),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.78),
		ZIndex = 26,
		Parent = badge,
	}, { MaxText = 26 })

	local nameLabel = UiKit.Label({
		Text = "",
		Position = UDim2.new(0, ROW_H + 4, 0.18, 0),
		Size = UDim2.new(0.6, -(ROW_H + 8), 0.64, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 25,
		Parent = frame,
	}, { MaxText = 24 })

	local pill: Frame = Make("Frame", {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.4, -8, 0, ROW_H - 16),
		BackgroundColor3 = C.Orange,
		ZIndex = 25,
		Parent = frame,
	})
	UiKit.Corner(pill, UDim.new(0.5, 0))
	UiKit.Stroke(pill, C.White, 2, true)
	local valueLabel = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.74),
		ZIndex = 26,
		Parent = pill,
	}, { MaxText = 22 })

	return {
		Frame = frame,
		Stroke = stroke,
		Badge = badge,
		RankLabel = rankLabel,
		NameLabel = nameLabel,
		ValuePill = pill,
		ValueLabel = valueLabel,
	}
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------
function LeaderboardWindow.Init(gui: Instance)
	window = UiKit.Window(gui, { Title = "🏆 순위표", Color = C.Gold, Name = "LeaderboardWindow" })
	-- 목록 창이라 조금 좁게
	local limit = window.Panel:FindFirstChildOfClass("UISizeConstraint")
	if limit then
		limit.MaxSize = Vector2.new(640, 660)
	end
	local content = window.Content

	-- 탭 + 어떤 순위인지 (🌍 전체 서버 / 🏠 이 서버)
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
	for i, t in TABS do
		local key = t.Key
		tabButtons[key] = UiKit.Button({
			Name = key,
			Text = t.Text,
			Color = C.Grey,
			Size = UDim2.new(0.33, -6, 1, -4),
			LayoutOrder = i,
			Radius = UDim.new(0.5, 0),
			TextSize = 24,
			Parent = top,
			OnClick = function()
				setTab(key)
			end,
		})
	end
	scopePill = Make("Frame", {
		Name = "Scope",
		Size = UDim2.new(0.34, -6, 1, -10),
		BackgroundColor3 = C.Grey,
		LayoutOrder = 10,
		ZIndex = 23,
		Parent = top,
	})
	UiKit.Corner(scopePill, UDim.new(0.5, 0))
	UiKit.Stroke(scopePill, C.White, 3, true)
	scopeLabel = UiKit.Label({
		Text = "⏳ 불러오는 중",
		Position = UDim2.fromScale(0.06, 0.16),
		Size = UDim2.fromScale(0.88, 0.68),
		ZIndex = 24,
		Parent = scopePill,
	}, { MaxText = 20 })

	-- 순위 목록
	scroll = UiKit.ListScroller(content, {
		Position = UDim2.new(0, 0, 0, 56),
		Size = UDim2.new(1, 0, 1, -56 - 64),
		ScrollBarImageColor3 = C.Gold,
	})
	for i = 1, TOP_N do
		rowCards[i] = createRow(scroll, i)
	end

	emptyLabel = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromScale(0.8, 0.3),
		TextColor3 = C.Ink,
		Visible = false,
		ZIndex = 30,
		Parent = content,
	}, { Stroke = C.White, MaxText = 28 })

	-- 내 순위 줄 (아래에 고정)
	mineBar = Make("Frame", {
		Name = "Mine",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = C.Lemon,
		Visible = false,
		ZIndex = 23,
		Parent = content,
	})
	UiKit.Corner(mineBar, UDim.new(0.4, 0))
	UiKit.Gradient(mineBar)
	UiKit.Stroke(mineBar, C.White, 3, true)
	mineLabel = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.66),
		ZIndex = 24,
		Parent = mineBar,
	}, { Stroke = UiKit.Darken(C.Lemon, 0.5), MaxText = 24 })

	window.OnOpen = function()
		if dirty then
			render()
		else
			updateMine()
		end
	end
	setTab("Income")

	-- init.client 가 연결하지 않아도 받을 수 있게 (같이 연결돼도 한 번만 그려요)
	Remotes.LeaderboardSync.OnClientEvent:Connect(function(data)
		LeaderboardWindow.SetBoard(data)
	end)
end

-- LeaderboardSync 로 받은 표 ({ Income, Rebirths, Global, Studio?, UpdatedAt, Mine? })
function LeaderboardWindow.SetBoard(data: any)
	if type(data) ~= "table" then
		return
	end
	board = {
		Income = cleanRows(data.Income),
		Rebirths = cleanRows(data.Rebirths),
		Global = data.Global == true,
		Studio = data.Studio == true,
		UpdatedAt = tonumber(data.UpdatedAt) or 0,
		Mine = cleanMine(data.Mine),
	}
	if window and window.IsOpen() then
		queueRender()
	else
		dirty = true
	end
end

-- (같은 함수) init.client 에서 OnLeaderboard 라는 이름으로 불러도 돼요
LeaderboardWindow.OnLeaderboard = LeaderboardWindow.SetBoard

-- 내 스냅샷이 바뀌면 "내 순위" 줄의 내 값만 다시
function LeaderboardWindow.OnSync()
	if window and window.IsOpen() then
		updateMine()
	end
end

-- 지금 받은 순위 (없으면 nil)
function LeaderboardWindow.GetBoard(): Board?
	return board
end

function LeaderboardWindow.Open()
	window.Open()
end

function LeaderboardWindow.Close()
	window.Close()
end

function LeaderboardWindow.IsOpen(): boolean
	return window ~= nil and window.IsOpen()
end

return LeaderboardWindow
