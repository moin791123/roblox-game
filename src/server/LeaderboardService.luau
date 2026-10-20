--!strict
-- 🏆 순위표 (v3): 전체 서버 TOP 10 — ⚡ 초당 수익 / 🔄 환생. (설계: docs/DESIGN.md "LeaderboardService")
-- 내 점수를 OrderedDataStore 에 쓰고, 1분마다 순위를 읽어서 로비의 순위판 2개와 🏆 창(LeaderboardSync)에 보여 줘요.
-- DataStore 를 못 쓰면 (API 접근이 꺼진 Studio 등) 이 서버에 있는 사람끼리 순위를 보여 줘요 (Global = false).
-- leaderstats (💰 코인 / ⚡ 초당 / 🔄 환생) 는 DataService 가 만들어요. 여기서는 읽기만 해요.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

-- 순위 한 줄 (DESIGN §5 LeaderboardSync)
export type Row = { Rank: number, UserId: number, Name: string, Value: number }
export type Board = {
	Income: { Row },
	Rebirths: { Row },
	Global: boolean, -- true = 전체 서버 순위, false = 이 서버 사람끼리
	Studio: boolean, -- (추가) Studio 테스트라서 이 서버 순위만 보여 주는 중
	UpdatedAt: number, -- os.time()
}
-- (추가) 클라이언트마다 붙여 보내는 "내 순위". Rank = nil 이면 몰라요 (100위 밖 / 아직 점수 없음)
export type MineEntry = { Rank: number?, Value: number }

type Live = { Income: number, Rebirths: number, CanSave: boolean } -- CanSave = false: 불러오기 실패한 판 (점수 안 써요)
type Entry = { UserId: number, Value: number }
type RowGui = { Frame: Frame, Name: TextLabel, Value: TextLabel }
type BoardGui = { Model: Model, Subtitle: TextLabel, Rows: { RowGui } }
type Stat = {
	StoreName: string,
	Store: OrderedDataStore?,
	Entries: { Entry }, -- 마지막으로 읽은 전체 순위 (높은 순, 최대 RANK_PAGE 줄)
	HasGlobal: boolean, -- 읽기에 한 번이라도 성공했나
	Written: { [number]: number }, -- userId → 마지막으로 쓴 값 (같으면 다시 안 써요)
	WrittenAt: { [number]: number }, -- userId → 마지막으로 쓴 시각 (os.clock)
	Pick: (live: Live) -> number,
	Format: (value: number) -> string,
	ModelName: string,
	Title: string,
	Accent: Color3,
	Place: CFrame,
	Gui: BoardGui?,
}

local LeaderboardService = {}

local LB = Config.Leaderboard
local TOP_N: number = LB.TopN
local REFRESH: number = LB.RefreshSeconds
local WRITE_EVERY: number = LB.WriteSeconds
local LOCAL_TICK = math.min(15, REFRESH) -- 이 서버 사람들 값은 15초마다 다시 봐요 (DataStore 안 씀)
local RANK_PAGE = 100 -- 한 번에 100줄 읽어요 (요청 수는 같고, "내 순위" 를 100위까지 알 수 있어요)
local NAME_AHEAD = 8 -- TOP_N 아래 몇 줄도 이름을 미리 찾아 둬요 (이 서버 사람 값이 바뀌면 순위가 밀려요)
local KEY_COOLDOWN = 7 -- 같은 키는 6초에 한 번만 쓸 수 있어요
local WRITE_RESERVE = 2 -- 주기 쓰기는 예산을 조금 남겨 둬요 (나갈 때 쓰기용)
local NAME_RETRY = 600 -- 이름 찾기에 실패하면 10분 뒤 다시
local INT_MAX = 2 ^ 53 -- OrderedDataStore 는 정수만 (double 로 안전한 최대값)
local UNKNOWN_NAME = "익명 친구"

local FONT = Enum.Font.FredokaOne
local PIXELS_PER_STUD = 40
local PANEL_W = 16
local PANEL_H = 18
local PANEL_BOTTOM = 3

local INK = Color3.fromRGB(95, 60, 120)
local CREAM = Color3.fromRGB(255, 248, 240)
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 200, 60)
local STONE = Color3.fromRGB(240, 228, 212)
local MEDALS = { "🥇", "🥈", "🥉" }
local MEDAL_COLORS = {
	Color3.fromRGB(255, 214, 80), -- 금
	Color3.fromRGB(214, 222, 236), -- 은
	Color3.fromRGB(232, 162, 102), -- 동
}
local ROW_COLORS = { WHITE, Color3.fromRGB(255, 238, 246) } -- 4위부터 번갈아

local function newStat(storeName: string, modelName: string, title: string, accent: Color3, place: CFrame, pick: (Live) -> number, format: (number) -> string): Stat
	return {
		StoreName = storeName,
		Store = nil,
		Entries = {},
		HasGlobal = false,
		Written = {},
		WrittenAt = {},
		Pick = pick,
		Format = format,
		ModelName = modelName,
		Title = title,
		Accent = accent,
		Place = place,
		Gui = nil,
	}
end

local INCOME = newStat(
	LB.IncomeStore,
	"IncomeBoard",
	"⚡ 초당 코인 TOP " .. TOP_N,
	Color3.fromRGB(255, 165, 60),
	Config.Layout.Leaderboards.Income,
	function(live: Live): number
		return live.Income
	end,
	function(value: number): string
		return "⚡ " .. Config.FormatNumber(value) .. "/초"
	end
)
local REBIRTHS = newStat(
	LB.RebirthStore,
	"RebirthBoard",
	"🔄 환생 TOP " .. TOP_N,
	Color3.fromRGB(175, 135, 255),
	Config.Layout.Leaderboards.Rebirths,
	function(live: Live): number
		return live.Rebirths
	end,
	function(value: number): string
		return "🔄 " .. Config.FormatNumber(value) .. "회"
	end
)
local STATS: { Stat } = { INCOME, REBIRTHS }

local started = false
local storesOk = true -- false = DataStore 를 못 써요 (이 서버 순위만)
local updatedAt = 0 -- 마지막으로 전체 순위를 읽은 시각 (os.time)
local lastLive: { [number]: Live } = {} -- 이 서버 사람들의 마지막 값 (나갈 때 쓰기용)
local lastSent: { [Player]: string } = {} -- 같은 내용이면 다시 안 보내요
local lastBoardSig = ""
local nameCache: { [number]: string } = {}
local nameTriedAt: { [number]: number } = {}

local function safe(what: string, fn: () -> ())
	local ok, err = pcall(function(): any
		fn()
		return nil
	end)
	if not ok then
		warn(string.format("[LeaderboardService] %s 오류: %s", what, tostring(err)))
	end
end

local function toInt(v: any): number
	local n = tonumber(v) or 0
	if n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, INT_MAX)
end

local function keyFor(userId: number): string
	return "u_" .. tostring(userId)
end

local function isGlobal(): boolean
	return storesOk and INCOME.HasGlobal and REBIRTHS.HasGlobal
end

local function turnOff(reason: any)
	if storesOk then
		storesOk = false
		warn("[LeaderboardService] OrderedDataStore 를 쓸 수 없어서 이 서버 순위만 보여 줘요:", reason)
	end
end

-- Studio 에서는 실패하면 바로 이 서버 순위로 (API 접근이 꺼져 있는 경우가 대부분).
-- 라이브 서버에서는 잠깐 실패할 수도 있어서 계속 다시 해 봐요 (마지막으로 읽은 순위는 그대로 보여 줘요)
local function onStoreError(what: string, err: any)
	if RunService:IsStudio() then
		turnOff(err)
	else
		warn(string.format("[LeaderboardService] %s 실패: %s", what, tostring(err)))
	end
end

local function budget(kind: Enum.DataStoreRequestType): number
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	if ok and type(n) == "number" then
		return n
	end
	return 5 -- 예산을 못 읽으면 조금만 쓴다고 생각해요
end

----------------------------------------------------------------------
-- 이름 (Players:GetNameFromUserIdAsync, 캐시 + pcall)
----------------------------------------------------------------------
local function nameOf(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	if p then
		return p.DisplayName
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	if userId <= 0 then
		return "Player" .. tostring(-userId) -- Studio 테스트 계정
	end
	return UNKNOWN_NAME
end

-- 기다려요 (yield). 캐시에 있거나 최근에 실패했으면 바로 끝
local function resolveName(userId: number)
	if userId <= 0 or nameCache[userId] or Players:GetPlayerByUserId(userId) then
		return
	end
	local tried = nameTriedAt[userId]
	if tried and os.clock() - tried < NAME_RETRY then
		return
	end
	nameTriedAt[userId] = os.clock()
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" and name ~= "" then
		nameCache[userId] = name
	end
end

----------------------------------------------------------------------
-- 이 서버 사람들 값 / 순위 만들기
----------------------------------------------------------------------
-- 데이터를 불러온 사람만 (안 불러온 사람의 0 으로 진짜 점수를 덮어쓰지 않게)
local function collectOnline(): { [number]: Live }
	local map: { [number]: Live } = {}
	for _, p in Players:GetPlayers() do
		if DataService.Get(p) then
			map[p.UserId] = {
				Income = toInt(DataService.GetIncome(p)),
				Rebirths = toInt(DataService.GetRebirths(p)),
				CanSave = DataService.CanSave(p),
			}
			nameCache[p.UserId] = p.DisplayName -- 나간 뒤에도 같은 이름으로
		end
	end
	lastLive = map
	return map
end

local function sortEntries(list: { Entry })
	table.sort(list, function(a: Entry, b: Entry): boolean
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.UserId < b.UserId
	end)
end

-- 전체 순위 + 이 서버 사람들의 지금 값 (DataStore 보다 최신) 을 합친 순위.
-- 전체 순위가 없으면 이 서버 사람끼리 (0 도 보여 줘요: 혼자 테스트할 때 내가 보이게)
local function ranking(stat: Stat, online: { [number]: Live }, global: boolean): { Entry }
	local list: { Entry } = {}
	if global then
		local seen: { [number]: boolean } = {}
		for _, e in stat.Entries do
			seen[e.UserId] = true
			local live = online[e.UserId]
			local value = if live then stat.Pick(live) else e.Value
			if value > 0 then
				table.insert(list, { UserId = e.UserId, Value = value })
			end
		end
		for userId, live in online do
			local value = stat.Pick(live)
			if not seen[userId] and value > 0 then
				table.insert(list, { UserId = userId, Value = value })
			end
		end
	else
		for userId, live in online do
			table.insert(list, { UserId = userId, Value = stat.Pick(live) })
		end
	end
	sortEntries(list)
	return list
end

local function topRows(list: { Entry }): { Row }
	local rows: { Row } = {}
	for i = 1, math.min(TOP_N, #list) do
		local e = list[i]
		rows[i] = { Rank = i, UserId = e.UserId, Name = nameOf(e.UserId), Value = e.Value }
	end
	return rows
end

local function mineOf(stat: Stat, list: { Entry }, userId: number, live: Live?, global: boolean): MineEntry
	local value = if live then stat.Pick(live) else 0
	-- 100줄을 다 읽었으면 그 아래는 진짜 순위를 몰라요
	local full = global and #stat.Entries >= RANK_PAGE
	for i, e in list do
		if e.UserId == userId then
			if full and i > RANK_PAGE then
				break
			end
			return { Rank = i, Value = value }
		end
	end
	return { Rank = nil, Value = value }
end

type Built = {
	Board: Board,
	IncomeList: { Entry },
	RebirthList: { Entry },
	Online: { [number]: Live },
}

local function build(): Built
	local online = collectOnline()
	local global = isGlobal()
	local incomeList = ranking(INCOME, online, global)
	local rebirthList = ranking(REBIRTHS, online, global)
	local board: Board = {
		Income = topRows(incomeList),
		Rebirths = topRows(rebirthList),
		Global = global,
		Studio = not global and RunService:IsStudio(),
		UpdatedAt = if global and updatedAt > 0 then updatedAt else os.time(),
	}
	return { Board = board, IncomeList = incomeList, RebirthList = rebirthList, Online = online }
end

local function boardSig(board: Board): string
	local parts = { if board.Global then "G" else "L", if board.Studio then "S" else "-" }
	for _, row in board.Income do
		table.insert(parts, row.UserId .. ":" .. row.Value .. ":" .. row.Name)
	end
	table.insert(parts, "#")
	for _, row in board.Rebirths do
		table.insert(parts, row.UserId .. ":" .. row.Value .. ":" .. row.Name)
	end
	return table.concat(parts, ",")
end

-- 클라이언트에게 보낼 표 (+ 내 순위) 와 비교용 문자열
local function payloadFor(player: Player, built: Built): ({ [string]: any }, string)
	local board = built.Board
	local live = built.Online[player.UserId]
	local mineIncome = mineOf(INCOME, built.IncomeList, player.UserId, live, board.Global)
	local mineRebirths = mineOf(REBIRTHS, built.RebirthList, player.UserId, live, board.Global)
	local payload = {
		Income = board.Income,
		Rebirths = board.Rebirths,
		Global = board.Global,
		Studio = board.Studio,
		UpdatedAt = board.UpdatedAt,
		Mine = { Income = mineIncome, Rebirths = mineRebirths },
	}
	local sig = string.format(
		"%s/%d|%s/%d",
		tostring(mineIncome.Rank),
		mineIncome.Value,
		tostring(mineRebirths.Rank),
		mineRebirths.Value
	)
	return payload, sig
end

----------------------------------------------------------------------
-- 로비의 순위판 (Part + SurfaceGui)
----------------------------------------------------------------------
local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function newLabel(parent: Instance, text: string, pos: UDim2, size: UDim2, color: Color3, maxText: number, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.TextWrapped = false
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Position = pos
	l.Size = size
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxText
	c.MinTextSize = 10
	c.Parent = l
	l.Parent = parent
	return l
end

local function corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, border: boolean)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = if border then Enum.ApplyStrokeMode.Border else Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
end

local function buildSurface(panel: Part, stat: Stat): (TextLabel, { RowGui })
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Board"
	sg.Face = Enum.NormalId.Front -- 앞면 = LookVector 쪽 (로비)
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = PIXELS_PER_STUD
	sg.LightInfluence = 0
	sg.MaxDistance = 220
	sg.ClipsDescendants = true
	sg.Parent = panel

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = CREAM
	bg.BorderSizePixel = 0
	bg.Parent = sg

	-- 머리: 🏆 제목 🏆
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Position = UDim2.fromScale(0.03, 0.02)
	header.Size = UDim2.fromScale(0.94, 0.13)
	header.BackgroundColor3 = stat.Accent
	header.BorderSizePixel = 0
	header.Parent = bg
	corner(header, 0.3)
	stroke(header, WHITE, 4, true)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(WHITE, Color3.fromRGB(215, 215, 225))
	grad.Rotation = 90
	grad.Parent = header
	newLabel(header, "🏆", UDim2.fromScale(0.02, 0.08), UDim2.fromScale(0.14, 0.84), WHITE, 80)
	newLabel(header, "🏆", UDim2.fromScale(0.84, 0.08), UDim2.fromScale(0.14, 0.84), WHITE, 80)
	local title = newLabel(header, stat.Title, UDim2.fromScale(0.16, 0.12), UDim2.fromScale(0.68, 0.76), WHITE, 56)
	title.Name = "Title"
	stroke(title, stat.Accent:Lerp(Color3.new(0, 0, 0), 0.45), 3, false)

	local subtitle = newLabel(bg, "순위를 불러오는 중… ⏳", UDim2.fromScale(0.05, 0.16), UDim2.fromScale(0.9, 0.055), INK, 30)
	subtitle.Name = "Subtitle"

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0.03, 0.225)
	list.Size = UDim2.fromScale(0.94, 0.715)
	list.Parent = bg
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.01, 0)
	layout.Parent = list

	local rows: { RowGui } = {}
	for i = 1, TOP_N do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. i
		frame.LayoutOrder = i
		frame.Size = UDim2.fromScale(1, 0.9 / TOP_N)
		frame.BackgroundColor3 = if i <= #MEDAL_COLORS then MEDAL_COLORS[i] else ROW_COLORS[(i % 2) + 1]
		frame.BorderSizePixel = 0
		frame.Parent = list
		corner(frame, 0.3)
		stroke(frame, if i <= #MEDAL_COLORS then WHITE else Color3.fromRGB(235, 220, 240), 3, true)
		local rankText = if i <= #MEDALS then MEDALS[i] else tostring(i)
		newLabel(frame, rankText, UDim2.fromScale(0.01, 0.06), UDim2.fromScale(0.12, 0.88), INK, 44)
		local name = newLabel(frame, "-", UDim2.fromScale(0.14, 0.14), UDim2.fromScale(0.48, 0.72), INK, 34, Enum.TextXAlignment.Left)
		name.Name = "PlayerName"
		local value = newLabel(frame, "", UDim2.fromScale(0.62, 0.14), UDim2.fromScale(0.36, 0.72), INK, 34, Enum.TextXAlignment.Right)
		value.Name = "Value"
		rows[i] = { Frame = frame, Name = name, Value = value }
	end

	newLabel(
		bg,
		"⏱ " .. (if REFRESH % 60 == 0 then tostring(REFRESH // 60) .. "분" else tostring(REFRESH) .. "초") .. "마다 새로 고쳐져요",
		UDim2.fromScale(0.05, 0.948),
		UDim2.fromScale(0.9, 0.042),
		Color3.fromRGB(150, 125, 165),
		24
	)
	return subtitle, rows
end

-- 판 하나: 받침 + 기둥 2개 + 판 + 금테 + 공 장식 (9 파츠, 가로 18 이하 = WorldBuilder 가 비워 둔 ±10 안)
local function buildBoard(folder: Instance, stat: Stat)
	local old = folder:FindFirstChild(stat.ModelName)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = stat.ModelName
	local cf = stat.Place
	local postColor = stat.Accent:Lerp(WHITE, 0.25)
	local topY = PANEL_BOTTOM + PANEL_H

	newPart("Base", Vector3.new(PANEL_W + 2, 1, 5), cf * CFrame.new(0, 0.5, 0), STONE, model)
	for _, side in { -1, 1 } do
		local x = side * (PANEL_W / 2 + 0.6)
		newPart("Post", Vector3.new(1.2, topY, 1.2), cf * CFrame.new(x, 1 + (topY - 1) / 2, 0.3), postColor, model)
		local ball = newPart("Finial", Vector3.new(1.8, 1.8, 1.8), cf * CFrame.new(x, topY + 1.6, 0.3), GOLD, model, Enum.PartType.Ball)
		ball.Reflectance = 0.15
	end
	local panel = newPart("Panel", Vector3.new(PANEL_W, PANEL_H, 0.8), cf * CFrame.new(0, PANEL_BOTTOM + PANEL_H / 2, 0), CREAM, model)
	newPart("TopTrim", Vector3.new(PANEL_W + 2.4, 1.2, 1.4), cf * CFrame.new(0, topY + 0.6, 0.1), GOLD, model).Reflectance = 0.15
	newPart("BottomTrim", Vector3.new(PANEL_W + 1.2, 0.8, 1.2), cf * CFrame.new(0, PANEL_BOTTOM - 0.4, 0.1), GOLD, model).Reflectance = 0.15
	local star = newPart("Trophy", Vector3.new(2.8, 2.8, 2.8), cf * CFrame.new(0, topY + 2.4, 0.1), GOLD, model, Enum.PartType.Ball)
	star.Reflectance = 0.2
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 0.6
	light.Range = 10
	light.Parent = star

	model.PrimaryPart = panel
	local subtitle, rows = buildSurface(panel, stat)
	model.Parent = folder
	stat.Gui = { Model = model, Subtitle = subtitle, Rows = rows }
end

local function buildBoards()
	local folder = workspace:FindFirstChild("Leaderboards")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Leaderboards"
		f.Parent = workspace
		folder = f
	end
	for _, stat in STATS do
		buildBoard(folder :: Instance, stat)
	end
end

local function subtitleText(board: Board): string
	if board.Global then
		return "🌍 전체 서버 순위"
	elseif board.Studio then
		return "Studio 테스트 중: 이 서버 순위"
	end
	return "🏠 이 서버 순위 (전체 순위는 잠시 후에!)"
end

local function renderStat(stat: Stat, rows: { Row }, board: Board)
	local gui = stat.Gui
	if not gui or not gui.Model.Parent then
		return
	end
	gui.Subtitle.Text = subtitleText(board)
	for i, rg in gui.Rows do
		local row = rows[i]
		if row then
			rg.Name.Text = row.Name
			rg.Value.Text = stat.Format(row.Value)
			rg.Frame.BackgroundTransparency = 0
		else
			rg.Name.Text = if i == 1 then "아직 아무도 없어요 🐣" else "-"
			rg.Value.Text = ""
			rg.Frame.BackgroundTransparency = 0.5
		end
	end
end

local function renderAll(board: Board)
	renderStat(INCOME, board.Income, board)
	renderStat(REBIRTHS, board.Rebirths, board)
end

----------------------------------------------------------------------
-- OrderedDataStore 쓰기 / 읽기 (모두 pcall, 예산 확인)
----------------------------------------------------------------------
-- 같은 값이면 안 써요. minGap 초 안에 이미 썼으면 안 써요. 예산이 reserve 이하면 다음에.
local function writeStat(stat: Stat, userId: number, value: number, minGap: number, reserve: number): boolean
	local store = stat.Store
	if not storesOk or not store then
		return false
	end
	-- Studio 테스트 계정 (음수 id) 과 0 점은 안 써요 (못 불러온 데이터의 0 으로 진짜 점수를 덮지 않게)
	if userId <= 0 or value <= 0 or stat.Written[userId] == value then
		return false
	end
	local now = os.clock()
	local last = stat.WrittenAt[userId]
	if last and now - last < minGap then
		return false
	end
	if budget(Enum.DataStoreRequestType.SetIncrementSortedAsync) <= reserve then
		return false
	end
	stat.WrittenAt[userId] = now
	local ok, err = pcall(function()
		store:SetAsync(keyFor(userId), value)
	end)
	if ok then
		stat.Written[userId] = value
	else
		onStoreError("점수 쓰기 (" .. stat.StoreName .. ")", err)
	end
	return ok
end

local function readStat(stat: Stat): boolean
	local store = stat.Store
	if not storesOk or not store then
		return false
	end
	if budget(Enum.DataStoreRequestType.GetSortedAsync) < 1 then
		return false
	end
	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(false, RANK_PAGE)
		return pages:GetCurrentPage()
	end)
	if not ok then
		onStoreError("순위 읽기 (" .. stat.StoreName .. ")", result)
		return false
	end
	local entries: { Entry } = {}
	if type(result) == "table" then
		for _, item in result do
			if type(item) == "table" then
				local userId = tonumber(string.match(tostring(item.key), "^u_(%-?%d+)$"))
				local value = toInt(item.value)
				if userId and value > 0 then
					table.insert(entries, { UserId = userId, Value = value })
				end
			end
		end
	end
	sortEntries(entries)
	stat.Entries = entries
	stat.HasGlobal = true
	return true
end

local function openStores()
	for _, stat in STATS do
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(stat.StoreName)
		end)
		if ok then
			stat.Store = result
		else
			turnOff(result)
			return
		end
	end
end

-- 1분마다: 이 서버 사람들 점수 쓰기 → 두 순위 읽기 → 위쪽 이름 찾기
local function refreshGlobal()
	if not storesOk then
		return
	end
	for _, p in Players:GetPlayers() do
		-- 불러오기에 실패한 사람(기본값으로 노는 중)의 점수는 절대 안 써요
		if storesOk and p.Parent and DataService.CanSave(p) then
			local income = toInt(DataService.GetIncome(p))
			local rebirths = toInt(DataService.GetRebirths(p))
			writeStat(INCOME, p.UserId, income, WRITE_EVERY - 5, WRITE_RESERVE)
			writeStat(REBIRTHS, p.UserId, rebirths, WRITE_EVERY - 5, WRITE_RESERVE)
		end
	end
	local anyRead = false
	for _, stat in STATS do
		if readStat(stat) then
			anyRead = true
		end
	end
	if anyRead then
		updatedAt = os.time()
	end
	for _, stat in STATS do
		for i = 1, math.min(#stat.Entries, TOP_N + NAME_AHEAD) do
			resolveName(stat.Entries[i].UserId)
		end
	end
end

-- 순위판을 다시 그리고 (바뀌었으면) 모두에게 LeaderboardSync. force = 같아도 보내기 (전체 순위를 새로 읽은 뒤)
local function publish(force: boolean)
	local built = build()
	local sig = boardSig(built.Board)
	if force or sig ~= lastBoardSig then
		lastBoardSig = sig
		renderAll(built.Board)
	end
	for _, p in Players:GetPlayers() do
		if DataService.Get(p) then
			local payload, mineSig = payloadFor(p, built)
			local full = sig .. "|" .. mineSig
			if force or lastSent[p] ~= full then
				lastSent[p] = full
				Remotes.LeaderboardSync:FireClient(p, payload)
			end
		end
	end
end

-- 나갈 때: 마지막 점수를 한 번 더 써 둬요 (바뀐 경우만, 키 쿨다운만 지키고)
local function onLeave(player: Player)
	lastSent[player] = nil
	local userId = player.UserId
	local live: Live? = lastLive[userId]
	if DataService.Get(player) then
		live = {
			Income = toInt(DataService.GetIncome(player)),
			Rebirths = toInt(DataService.GetRebirths(player)),
			CanSave = DataService.CanSave(player),
		}
	end
	if not live or not live.CanSave or not storesOk then
		return
	end
	local income, rebirths = live.Income, live.Rebirths
	task.spawn(function()
		safe("나갈 때 점수 쓰기", function()
			writeStat(INCOME, userId, income, KEY_COOLDOWN, 0)
			writeStat(REBIRTHS, userId, rebirths, KEY_COOLDOWN, 0)
		end)
	end)
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------
function LeaderboardService.Start()
	if started then
		return
	end
	started = true
	safe("순위판 만들기", buildBoards)
	openStores()
	Players.PlayerRemoving:Connect(onLeave)

	task.spawn(function()
		safe("첫 순위 읽기", refreshGlobal)
		safe("순위 보내기", function()
			publish(true)
		end)
		local lastGlobal = os.clock()
		while true do
			task.wait(LOCAL_TICK)
			if os.clock() - lastGlobal >= REFRESH - 0.5 then
				lastGlobal = os.clock()
				safe("순위 새로 고침", refreshGlobal)
				safe("순위 보내기", function()
					publish(true)
				end)
			else
				-- 이 서버 사람들 값만 다시 보고, 바뀐 게 있을 때만 다시 그리고 보내요
				safe("순위 보내기", function()
					publish(false)
				end)
			end
		end
	end)
end

-- 데이터를 불러온 뒤 init.server 가 불러요: 지금 순위 (+ 내 순위) 를 이 사람에게 보내요
function LeaderboardService.SendTo(player: Player)
	safe("SendTo", function()
		if not player.Parent then
			return
		end
		local built = build()
		local sig = boardSig(built.Board)
		if sig ~= lastBoardSig then
			lastBoardSig = sig
			renderAll(built.Board)
		end
		local payload, mineSig = payloadFor(player, built)
		lastSent[player] = sig .. "|" .. mineSig
		Remotes.LeaderboardSync:FireClient(player, payload)
	end)
end

-- 지금 보여 주는 순위 (내 순위 없이). 기다리지 않아요
function LeaderboardService.GetBoard(): Board
	return build().Board
end

return LeaderboardService
