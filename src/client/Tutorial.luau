-- ★v7.6 📘 튜토리얼 (처음 온 친구용): 화면 카드 한 장 + 버튼을 가리키는 손가락 👈 + 길 안내 빛줄기 (알 벨트 · 금고 판)
-- 단계 (Config.TutorialSteps 와 같은 수): 👋 환영 → 🥚 알 사기 → 🏡 집으로 → 🐣 부화 기다리기 → 🏦 금고 받기
--   → 🎒 가방 열기 → ✨ 도구 줄 소개 → 🔄 환생 소개. 해내면 저절로 다음 단계, 소개 단계는 "다음 ▶" 버튼.
--   해내는 단계에서 오래 (STUCK_TIME) 못 넘어가면 "넘어가기 ▶" 버튼이 나와요.
-- 진행은 Settings.Tutorial (끝낸 단계 수) 로 저장해요 (Remotes.SetSetting, 다시 들어와도 이어서).
--   다 끝내거나 "건너뛰기" (두 번 누르기) 하면 다시 안 나와요.
--   이미 키운 친구 (환생 1번 이상 / 부화 5번 이상 / 펫 5마리 이상) 는 처음부터 끝낸 걸로 쳐요.
-- 자리: PC 는 아래 가운데 (팁 줄 자리, 튜토리얼 동안 팁 줄은 쉬어요), 폰은 코인 줄 아래 가운데 (조이스틱을 피해요).
-- 꾸미기 모드 동안은 카드·손가락·빛줄기가 숨어요 (SetSuppressed).
-- ★v7.6 카드는 다른 HUD (왼쪽 버튼 · 도구 줄 · 펫 타기 버튼 · 점프 · 조이스틱 칸) 를 비켜요. 오른쪽 아래 알림 줄은 카드를 비켜 가다가
--   자리가 모자라면 (작은 폰) 카드 자리를 써요: 그동안 카드만 잠깐 숨어요 (희귀 알 배너·말풍선은 절대 안 잃어요).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer

local Tutorial = {}

export type Hooks = {
	HomeButton: () -> GuiObject?,
	SideButton: (caption: string) -> GuiObject?,
	Tools: () -> GuiObject?,
	OnActive: ((boolean) -> ())?, -- 튜토리얼이 켜지고 꺼질 때 (팁 줄 쉬기)
}

local touch = UserInputService.TouchEnabled
local showKeys = UserInputService.KeyboardEnabled and not touch
local function key(k: string): string
	return if showKeys then " (" .. k .. ")" else ""
end

local TOTAL = Config.TutorialSteps
local STUCK_TIME = 75 -- 해내는 단계에서 이만큼 지나면 "넘어가기 ▶"
local TICK = 0.25

----------------------------------------------------------------------
-- 지금 상태 읽기
----------------------------------------------------------------------
-- (알 수, 펫 수, 부화한 수)
local function counts(): (number, number, number)
	local eggs, pets = 0, 0
	for _, it in State.Items() do
		if type(it) == "table" then
			if it.Kind == "Egg" then
				eggs += 1
			elseif it.Kind == "Pet" then
				pets += 1
			end
		end
	end
	local snap = State.Snapshot
	local stats = if snap and type(snap.Stats) == "table" then snap.Stats else nil
	local hatched = if stats then tonumber(stats.Hatched) or 0 else 0
	return eggs, pets, hatched
end

-- 받침대 위 (알 수, 펫 수, 가장 빨리 깨는 알까지 남은 초)
local function slotCounts(): (number, number, number?)
	local eggs, pets = 0, 0
	local soonest: number? = nil
	local now = workspace:GetServerTimeNow()
	for _, it in State.Items() do
		if type(it) == "table" and it.Loc == "Slot" then
			if it.Kind == "Egg" then
				eggs += 1
				local left = (tonumber(it.HatchAt) or now) - now
				if not soonest or left < soonest then
					soonest = left
				end
			elseif it.Kind == "Pet" then
				pets += 1
			end
		end
	end
	return eggs, pets, soonest
end

-- 집 금고에 쌓인 코인 (Hud 와 같은 셈)
local function pendingNow(): number
	local plot = State.Plot
	local collector = plot and plot:FindFirstChild("Collector")
	if collector then
		return tonumber(collector:GetAttribute("Pending")) or 0
	end
	local snap = State.Snapshot
	return if snap then tonumber(snap.Pending) or 0 else 0
end

-- 이미 키운 친구인가 (처음 들어올 때만 봐요)
local function veteran(): boolean
	local _, pets, hatched = counts()
	return State.Rebirths() > 0 or hatched >= 5 or pets >= 5
end

----------------------------------------------------------------------
-- 단계
----------------------------------------------------------------------
type Step = {
	Emoji: string,
	Title: string,
	Text: string,
	Button: string?, -- 있으면 눌러서 넘어가요 (소개 단계)
	Point: string?, -- 손가락: "Home" | "Bag" | "Tools" | "Rebirth"
	Guide: string?, -- 빛줄기: "Belt" | "Collector"
	Begin: (() -> ())?, -- 단계를 시작할 때 (기준 값 기억)
	Done: (() -> boolean)?, -- 해냈나 (0.25초마다)
	Live: (() -> string?)?, -- 카드 아래 한 줄 (남은 시간 같은 것)
}

local base = 0
local sawPending = false
local noticed: { [string]: boolean } = {}

local STEPS: { Step } = {
	{
		Emoji = "👋",
		Title = "펫 월드에 온 걸 환영해요!",
		Text = "알을 사서 귀여운 펫을 키우고 코인을 모아요. 하나씩 알려 줄게요!",
		Button = "시작! ▶",
	},
	{
		Emoji = "🥚",
		Title = "알을 사 봐요",
		Text = if showKeys
			then "빛줄기를 따라 컨베이어로 가서 알 앞에서 E 를 꾹 눌러요"
			else "빛줄기를 따라 컨베이어로 가서 알 옆 버튼을 꾹 눌러요",
		Guide = "Belt",
		Begin = function()
			local eggs, _, hatched = counts()
			base = eggs + hatched
		end,
		Done = function(): boolean
			local eggs, _, hatched = counts()
			return eggs + hatched > base
		end,
	},
	{
		Emoji = "🏡",
		Title = "집으로 가요",
		Text = "산 알은 내 집 받침대로 날아가요. '집으로' 버튼" .. key("G") .. "을 눌러 봐요!",
		Point = "Home",
		Done = function(): boolean
			return State.CurrentFloor() ~= nil
		end,
	},
	{
		Emoji = "🐣",
		Title = "알이 깨어나길 기다려요",
		Text = "받침대 위 알은 조금 기다리면 펫이 돼요",
		Begin = function()
			local _, _, hatched = counts()
			base = hatched
		end,
		Done = function(): boolean
			local _, _, hatched = counts()
			if hatched > base then
				return true
			end
			local eggs, pets = slotCounts()
			return eggs == 0 and pets > 0
		end,
		Live = function(): string?
			local eggs, _, soonest = slotCounts()
			if eggs == 0 or not soonest then
				return nil
			end
			local left = math.ceil(soonest)
			return if left <= 0 then "🐣 곧 깨어나요!" else string.format("⏱ %d초 남았어요", left)
		end,
	},
	{
		Emoji = "🏦",
		Title = "금고 코인을 받아요",
		Text = "펫이 코인을 만들어 집 금고에 모아요. 빛줄기를 따라 금색 판을 밟아요!",
		Guide = "Collector",
		Begin = function()
			sawPending = false
		end,
		Done = function(): boolean
			if State.GetSetting("AutoCollect") and State.HasPass("AutoCollect") then
				return true -- 자동 수금이면 저절로 들어와요
			end
			if pendingNow() >= 1 then
				sawPending = true
				return false
			end
			return sawPending
		end,
		Live = function(): string?
			local p = math.floor(pendingNow())
			return if p > 0 then "🏦 금고에 " .. Config.FormatNumber(p) .. " 코인!" else "💰 펫이 코인을 모으는 중…"
		end,
	},
	{
		Emoji = "🎒",
		Title = "가방을 열어 봐요",
		Text = "왼쪽 '가방'" .. key("B") .. "에서 펫을 데리고 다니거나 타고, 같은 펫 3마리로 합성해요",
		Point = "Bag",
		Begin = function()
			noticed.Bag = false
		end,
		Done = function(): boolean
			return noticed.Bag == true
		end,
	},
	{
		Emoji = "✨",
		Title = "편한 버튼 줄",
		Text = "🏡 집으로 · 🧲 자석 같은 켜고 끄기 · ✨ 자동 배치 · ⚙️ 옵션이 여기 모여 있어요",
		Point = "Tools",
		Button = "다음 ▶",
	},
	{
		Emoji = "🔄",
		Title = "환생하면 새 지역이 열려요!",
		Text = "코인을 모아 '환생'" .. key("R") .. " 하면 새 지역과 보너스! 🗺 지도로 바로 가요",
		Point = "Rebirth",
		Button = "끝! 🎉",
	},
}

----------------------------------------------------------------------
-- 화면
----------------------------------------------------------------------
local gui: ScreenGui? = nil
local hooks: Hooks? = nil
local card: Frame? = nil
local stepPill: TextLabel
local emojiLabel: TextLabel
local titleLabel: TextLabel
local textLabel: TextLabel
local liveLabel: TextLabel
local nextButton: TextButton
local nextLabel: TextLabel
local skipButton: TextButton
local skipLabel: TextLabel
local skipReset: () -> () = function() end
local ring: Frame? = nil
local finger: TextLabel? = nil

local current = 0 -- 지금 단계 (1..#STEPS), 0 = 안 해요
local stepStarted = 0
local passing = false -- 해낸 뒤 다음 단계로 넘어가는 중
local suppressed = false
local yielding = false -- ★v7.6 알림 줄이 자리가 모자라서 카드 자리를 쓰는 동안 (카드가 잠깐 숨어요)
local started = false

-- 빛줄기 (나만 보여요: 클라이언트에서 만든 건 서버로 안 가요)
local guideFolder: Folder? = nil
local guideTarget: BasePart? = nil
local guideLastFind = 0

local function save(n: number)
	State.SetSettingLocal("Tutorial", n)
	Remotes.SetSetting:FireServer("Tutorial", n)
end

local function setActive(on: boolean)
	local h = hooks
	if h and h.OnActive then
		h.OnActive(on)
	end
end

-- ★v7.6 y0..y1 줄에서 다른 HUD (왼쪽 큰 버튼 칸 · 도구 줄 · 펫 타기 버튼 · 창 ✖ · 폰 조이스틱 칸 · 점프 버튼) 사이의
-- 가장 넓은 빈 칸 (화면 끝 10, 피할 것과 8 띄우기). 카드 자신은 SideSoft 라 UiKit.SideObstacles 에 안 들어가요
local function freeSpan(obs: { UiKit.Rect }, gw: number, y0: number, y1: number): (number, number)
	local cuts: { UiKit.Rect } = {}
	for _, o in obs do
		if o.Y0 < y1 and y0 < o.Y1 then
			table.insert(cuts, o)
		end
	end
	table.sort(cuts, function(a: UiKit.Rect, b: UiKit.Rect): boolean
		return a.X0 < b.X0
	end)
	local bestL, bestR = 10, 10
	local x = 10
	for _, o in cuts do
		local e = math.min(o.X0 - 8, gw - 10)
		if e - x > bestR - bestL then
			bestL, bestR = x, e
		end
		x = math.max(x, o.X1 + 8)
	end
	if gw - 10 - x > bestR - bestL then
		bestL, bestR = x, gw - 10
	end
	return math.floor(bestL), math.floor(bestR)
end

-- 카드 자리와 안 크기 (화면이 바뀔 때 · 0.25초마다).
-- 아래 가운데 (폰은 조이스틱 칸과 점프 버튼 사이) → 너무 좁으면 코인 줄 아래. 다른 HUD 와는 안 겹치고 화면 밖으로도 안 나가요.
-- ★v7.6 오른쪽 알림 줄은 카드를 비켜 가다가, 자리가 모자라면 (작은 폰) 카드 자리를 써요 → 그동안 카드는 잠깐 숨어요 (tick)
local MIN_W = 260
local compact = false
local function layoutCard()
	local f, g = card, gui
	if not f or not g then
		return
	end
	local size = g.AbsoluteSize
	local gw, gh = size.X, size.Y
	if gw <= 0 or gh <= 0 then
		return
	end
	local small = gh < 500
	local H = if small then 84 else 104
	local want = math.clamp(gw * 0.46, 340, 560)
	local obs = UiKit.SideObstacles(g)
	-- 내 캐릭터 (화면 가운데, 머리 ~ 몸통) 도 가리지 않아요 (작은 폰에서 코인 줄 아래로 올라갈 때)
	local cw = math.max(24, math.floor(gh * 0.07))
	table.insert(obs, { X0 = gw / 2 - cw, Y0 = gh * 0.38, X1 = gw / 2 + cw, Y1 = gh * 0.65, Tag = "Character" })
	local off = g.AbsolutePosition
	-- (알약·건너뛰기 버튼이 카드 위로 12px 나와요: 줄은 그 위부터 봐요)
	local y = gh - 12 - H
	local L, R = freeSpan(obs, gw, y - 12, y + H)
	if R - L < MIN_W then
		-- 아래가 좁으면 코인 줄 아래
		-- (코인 줄과 점프 버튼 사이가 빠듯한 작은 폰: 몇 px 씩 내려 보며 가장 넓은 자리)
		local base = 77
		local top = g:FindFirstChild("TopBar")
		local sub = top and top:FindFirstChild("SubRow", true)
		if sub and sub:IsA("GuiObject") then
			base = math.ceil(sub.AbsolutePosition.Y - off.Y + sub.AbsoluteSize.Y)
		end
		for d = 13, 21 do
			local ty = base + d
			local tl, tr = freeSpan(obs, gw, ty - 12, ty + H)
			if tr - tl > R - L then
				y, L, R = ty, tl, tr
			end
		end
	end
	-- 빈 칸이 좀 좁으면 (작은 폰) 카드도 좁게, 아주 좁으면 원래 너비로 (그래도 화면 밖으로는 안 나가요)
	local W = math.floor(math.min(want, R - L))
	if W < 200 then
		W = math.min(MIN_W, gw - 20)
	end
	local x = math.floor(math.clamp(gw / 2 - W / 2, L, math.max(L, R - W)))
	x = math.clamp(x, 10, math.max(10, gw - 10 - W))
	f.AnchorPoint = Vector2.new(0, 0)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(W, H)

	-- 안: [이모지 | 제목 / 설명 / 한 줄 | 버튼]. 좁으면 이모지는 제목 앞으로
	compact = W < 440
	local step = STEPS[current]
	local pad = 10
	local e = H - 2 * pad - 8
	emojiLabel.Visible = not compact
	emojiLabel.Position = UDim2.fromOffset(pad, math.floor((H - e) / 2) + 4)
	emojiLabel.Size = UDim2.fromOffset(e, e)
	if step and not passing then
		titleLabel.Text = if compact then step.Emoji .. " " .. step.Title else step.Title
	end
	local bw = if nextButton.Visible then math.clamp(math.floor(W * 0.22), 80, 120) else 0
	local tx = if compact then pad + 4 else pad + e + 8
	local tw = W - tx - pad - (if bw > 0 then bw + 8 else 0)
	local top = 14
	local titleH = math.floor(H * 0.28)
	titleLabel.Position = UDim2.fromOffset(tx, top)
	titleLabel.Size = UDim2.fromOffset(tw, titleH)
	local live = liveLabel.Text ~= ""
	local rest = H - top - titleH - 6
	local textH = if live then math.floor(rest * 0.66) else rest
	textLabel.Position = UDim2.fromOffset(tx, top + titleH + 2)
	textLabel.Size = UDim2.fromOffset(tw, textH)
	liveLabel.Visible = live
	liveLabel.Position = UDim2.fromOffset(tx, top + titleH + 2 + textH)
	liveLabel.Size = UDim2.fromOffset(tw, rest - textH)
	if bw > 0 then
		local bh = math.max(44, math.floor(H * 0.46)) -- ★v7.6 손가락 크기 44px 이상
		nextButton.Size = UDim2.fromOffset(bw, bh)
		nextButton.Position = UDim2.fromOffset(W - pad - bw, math.floor((H - bh) / 2) + 6)
	end
	skipButton.Size = UDim2.fromOffset(if small then 74 else 86, if small then 24 else 26)
end

-- 손가락이 가리킬 것
local function pointTarget(step: Step): GuiObject?
	local h = hooks
	if not h or not step.Point then
		return nil
	end
	if step.Point == "Home" then
		return h.HomeButton()
	elseif step.Point == "Tools" then
		return h.Tools()
	elseif step.Point == "Bag" then
		return h.SideButton("가방")
	elseif step.Point == "Rebirth" then
		return h.SideButton("환생")
	end
	return nil
end

-- 보이나 (조상까지)
local function shown(g: GuiObject): boolean
	local n: Instance? = g
	while n and n:IsA("GuiObject") do
		if not n.Visible then
			return false
		end
		n = n.Parent
	end
	return true
end

-- 손가락 + 반짝 테두리 (매 프레임 따라가요)
local fingerPhase = 0
local function updatePointer(dt: number)
	local r, f, g = ring, finger, gui
	if not r or not f or not g then
		return
	end
	local step = STEPS[current]
	local target = if step and not suppressed and not passing then pointTarget(step) else nil
	if not target or not shown(target) then
		r.Visible = false
		f.Visible = false
		return
	end
	local off = g.AbsolutePosition
	local p, s = target.AbsolutePosition - off, target.AbsoluteSize
	r.Visible = true
	r.Position = UDim2.fromOffset(math.floor(p.X - 6), math.floor(p.Y - 6))
	r.Size = UDim2.fromOffset(math.floor(s.X + 12), math.floor(s.Y + 12))
	fingerPhase += dt * 6
	local bob = math.sin(fingerPhase) * 8
	local fs = math.clamp(math.floor(math.min(s.X, s.Y) * 0.8), 36, 56)
	f.Visible = true
	f.Size = UDim2.fromOffset(fs, fs)
	f.Position = UDim2.fromOffset(math.floor(p.X + s.X + 12 + bob), math.floor(p.Y + math.min(s.Y, 70) / 2 - fs / 2))
end

----------------------------------------------------------------------
-- 빛줄기 (알 벨트 · 금고 판)
----------------------------------------------------------------------
local function clearGuide()
	local f = guideFolder
	if f then
		f:Destroy()
	end
	guideFolder = nil
	guideTarget = nil
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- 지금 지역 벨트 윗면 중 나와 가장 가까운 조각 (지역을 모르면 1)
local function findBelt(root: BasePart): BasePart?
	local conveyors = workspace:FindFirstChild("Conveyors")
	if not conveyors then
		return nil
	end
	local zone = tonumber(player:GetAttribute("Zone")) or 1
	local folder = conveyors:FindFirstChild("Zone" .. zone) or conveyors:FindFirstChild("Zone1")
	if not folder then
		return nil
	end
	local best: BasePart? = nil
	local bestD = math.huge
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "BeltTop" then
			local dist = (d.Position - root.Position).Magnitude
			if dist < bestD then
				best, bestD = d, dist
			end
		end
	end
	return best
end

local function findGuide(kind: string, root: BasePart): BasePart?
	if kind == "Belt" then
		return findBelt(root)
	elseif kind == "Collector" then
		local plot = State.Plot
		local c = plot and plot:FindFirstChild("Collector")
		return if c and c:IsA("BasePart") then c else nil
	end
	return nil
end

-- 0.25초마다: 빛줄기를 내 몸 ↔ 목표에 이어요 (다시 태어나도, 목표가 바뀌어도)
local function updateGuide(step: Step?)
	local kind = if step and not suppressed and not passing then step.Guide else nil
	local root = rootPart()
	if not kind or not root then
		clearGuide()
		return
	end
	local now = os.clock()
	local target = guideTarget
	if not target or not target.Parent or now - guideLastFind > 2 then
		guideLastFind = now
		target = findGuide(kind, root)
	end
	if not target then
		clearGuide()
		return
	end
	local folder = guideFolder
	if folder and target == guideTarget and folder.Parent == root then
		return -- 그대로
	end
	clearGuide()
	guideTarget = target
	local f: Folder = Make("Folder", { Name = "TutorialGuide" })
	-- 끝점 붙임: 내 몸 (발 쪽) · 목표 윗면
	local a0: Attachment = Make("Attachment", { Name = "TutorialFrom", Position = Vector3.new(0, -1.5, 0), Parent = root })
	local a1: Attachment = Make("Attachment", { Name = "TutorialTo", Position = Vector3.new(0, target.Size.Y / 2 + 0.5, 0), Parent = target })
	Make("Beam", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = ColorSequence.new(C.Lemon, C.Mint),
		Transparency = NumberSequence.new(0.25),
		LightEmission = 0.6,
		Width0 = 1.2,
		Width1 = 1.2,
		FaceCamera = true,
		Segments = 1,
		Parent = f,
	})
	-- 목표 위에 "여기!" 표시
	local board: BillboardGui = Make("BillboardGui", {
		Name = "Here",
		Adornee = target,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(120, 60),
		StudsOffset = Vector3.new(0, target.Size.Y / 2 + 4, 0),
		Parent = f,
	})
	UiKit.Label({ Text = "여기! ⬇", Parent = board }, { Stroke = UiKit.Darken(C.Lemon, 0.5), StrokeThickness = 3, MaxText = 36 })
	-- 빛줄기와 표시는 내 몸 아래 폴더에 (폴더가 없어지면 끝점 붙임도 같이 지워요)
	f.Parent = root
	f.Destroying:Connect(function()
		a0:Destroy()
		a1:Destroy()
	end)
	guideFolder = f
end

----------------------------------------------------------------------
-- 단계 진행
----------------------------------------------------------------------
local finish: (skipped: boolean) -> ()

-- ★v7.6 비켜 주기: 작은 폰에서 희귀 알 배너·말풍선이 카드 자리까지 써야 하면 (Toasts.SoftCovered) 그동안 카드는 숨어요.
-- 알림은 절대 안 잃어요. 숨어 있어도 자리는 그대로 알려 줘서 (SideYield) 알림이 줄면 카드가 다시 나와요
local function setYield(on: boolean)
	if yielding == on then
		return
	end
	yielding = on
	local f = card
	if not f then
		return
	end
	f:SetAttribute("SideYield", on)
	if current > 0 then
		f.Visible = not suppressed and not on
		if f.Visible then
			UiKit.Pop(f, 0.25)
		end
	end
end

local function showStep()
	local f = card
	local step = STEPS[current]
	if not f or not step then
		return
	end
	stepPill.Text = string.format("📘 %d/%d", current, #STEPS)
	emojiLabel.Text = step.Emoji
	titleLabel.Text = step.Title
	textLabel.Text = step.Text
	liveLabel.Text = ""
	nextButton.Visible = step.Button ~= nil
	nextLabel.Text = step.Button or "넘어가기 ▶"
	nextButton.BackgroundColor3 = C.Mint
	f.Visible = not suppressed and not yielding
	layoutCard()
	if f.Visible then
		UiKit.Pop(f, 0.3)
	end
end

local function startStep(n: number)
	if n > #STEPS then
		finish(false)
		return
	end
	current = n
	stepStarted = os.clock()
	passing = false
	local step = STEPS[n]
	if step.Begin then
		step.Begin()
	end
	showStep()
end

-- 지금 단계 끝 → 저장하고 다음 단계
local function complete()
	if passing or current == 0 then
		return
	end
	passing = true
	local n = current
	save(math.min(n, TOTAL))
	UiKit.PlaySound("Buy")
	if card and not suppressed and n < #STEPS then
		emojiLabel.Text = "✅"
		titleLabel.Text = "잘했어요! ✨"
		UiKit.Bump(card, 0.12)
	end
	clearGuide()
	task.delay(if n < #STEPS then 0.9 else 0, function()
		if current == n then
			startStep(n + 1)
		end
	end)
end

finish = function(skipped: boolean)
	local was = current
	current = 0
	passing = false
	setYield(false)
	clearGuide()
	save(TOTAL)
	local f = card
	if f then
		UiKit.Tween(UiKit.Scale(f), 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.3, function()
			if current == 0 then
				f.Visible = false
				UiKit.Scale(f).Scale = 1
			end
		end)
	end
	if ring then
		ring.Visible = false
	end
	if finger then
		finger.Visible = false
	end
	setActive(false)
	if was > 0 then
		if skipped then
			Toasts.Show("📘 튜토리얼을 건너뛰었어요! 아래 도움말을 봐요", "info")
		else
			UiKit.PlaySound("Hatch")
			Toasts.Show("🎉 튜토리얼 끝! 이제 마음껏 펫을 모아 봐요", "good")
		end
	end
end

local function onNext()
	local step = STEPS[current]
	if not step or passing then
		return
	end
	if step.Button or os.clock() - stepStarted >= STUCK_TIME then
		complete()
	end
end

-- 0.25초마다: 해냈나 + 한 줄 + 오래 걸리면 "넘어가기"
local function tick()
	local step = STEPS[current]
	if not step then
		return
	end
	setYield(Toasts.SoftCovered()) -- ★v7.6 알림이 먼저
	layoutCard() -- 펫 타기 버튼처럼 나타났다 사라지는 HUD 도 비켜요
	updateGuide(step)
	if passing then
		return
	end
	if step.Done and step.Done() then
		complete()
		return
	end
	local live = if step.Live then step.Live() or "" else ""
	local stuck = not step.Button and os.clock() - stepStarted >= STUCK_TIME
	local relayout = false
	if liveLabel.Text ~= live then
		liveLabel.Text = live
		relayout = true
	end
	if stuck and not nextButton.Visible then
		nextButton.Visible = true
		nextLabel.Text = "넘어가기 ▶"
		nextButton.BackgroundColor3 = C.Sky
		relayout = true
	end
	if relayout then
		layoutCard()
	end
end

----------------------------------------------------------------------
-- 만들기
----------------------------------------------------------------------
function Tutorial.Init(g: ScreenGui, h: Hooks)
	gui = g
	hooks = h
	local f: Frame = Make("Frame", {
		Name = "Tutorial",
		BackgroundColor3 = C.Lavender,
		Visible = false,
		ZIndex = 12,
		Parent = g,
	})
	-- ★v7.6 알림 줄은 이 카드를 비켜 가지만, 자리가 모자라면 그 위에 놓여요 (카드가 비켜요, UiKit.SoftRects)
	f:SetAttribute("SideSoft", true)
	card = f
	UiKit.Corner(f, UDim.new(0, 18))
	UiKit.Gradient(f)
	UiKit.Stroke(f, C.White, 3, true)
	-- 위 왼쪽 "📘 2/8"
	local pill, pillLabel = UiKit.Pill(f, "📘 1/" .. #STEPS, C.Sky, {
		Name = "Step",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.fromOffset(74, 24),
		ZIndex = 13,
	}, 18)
	pill.ZIndex = 13
	stepPill = pillLabel
	emojiLabel = UiKit.Label({ Name = "Emoji", Text = "👋", ZIndex = 13, Parent = f }, { MaxText = 60 })
	titleLabel = UiKit.Label({
		Name = "Title",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = f,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.5), StrokeThickness = 2.5, MaxText = 28 })
	textLabel = UiKit.Label({
		Name = "Text",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = f,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.5), MaxText = 20 })
	liveLabel = UiKit.Label({
		Name = "Live",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Lemon,
		Visible = false,
		ZIndex = 13,
		Parent = f,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.5), MaxText = 18 })
	nextButton, nextLabel = UiKit.Button({
		Name = "Next",
		Text = "다음 ▶",
		Color = C.Mint,
		Radius = UDim.new(0.35, 0),
		TextSize = 22,
		ZIndex = 13,
		Parent = f,
		OnClick = onNext,
	})
	nextButton.Visible = false
	-- 위 오른쪽 "건너뛰기" (두 번 눌러야 해요)
	local skipClick: () -> ()
	skipButton, skipLabel = UiKit.Button({
		Name = "Skip",
		Text = "건너뛰기",
		Color = C.Grey,
		Radius = UDim.new(0.5, 0),
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0, 0),
		ZIndex = 13,
		Parent = f,
		OnClick = function()
			skipClick()
		end,
	})
	skipClick, skipReset = UiKit.TwoTap(skipButton, skipLabel, "정말요?", function()
		finish(true)
	end, 2.5)

	-- 손가락 + 반짝 테두리 (알림 줄이 비키지 않게 SideIgnore)
	local r: Frame = Make("Frame", {
		Name = "TutorialRing",
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 50,
		Parent = g,
	})
	r:SetAttribute("SideIgnore", true)
	UiKit.Corner(r, UDim.new(0, 16))
	local stroke = UiKit.Stroke(r, C.Lemon, 4, true)
	task.spawn(function()
		-- 테두리 깜빡깜빡
		local on = true
		while r.Parent do
			on = not on
			UiKit.Tween(stroke, 0.5, { Transparency = if on then 0 else 0.55 }, Enum.EasingStyle.Sine)
			task.wait(0.5)
		end
	end)
	ring = r
	local fl = UiKit.Label({
		Name = "TutorialFinger",
		Text = "👈",
		Visible = false,
		ZIndex = 51,
		Parent = g,
	}, { MaxText = 56, StrokeThickness = 0 })
	fl:SetAttribute("SideIgnore", true)
	finger = fl

	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(layoutCard)
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		if current > 0 then
			updatePointer(dt)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			if current > 0 then
				local ok, err = pcall(tick)
				if not ok then
					warn("[Tutorial] " .. tostring(err))
				end
			end
		end
	end)
end

-- 전체 스냅샷마다 (처음 한 번만: 이어서 할지 정해요)
function Tutorial.OnSync()
	if started or not State.Snapshot or not card then
		return
	end
	started = true
	local saved = tonumber(State.GetSetting("Tutorial")) or 0
	if saved >= TOTAL then
		return
	end
	if saved == 0 and veteran() then
		save(TOTAL) -- 이미 키운 친구는 안 보여 줘요
		return
	end
	task.delay(2, function()
		if current == 0 then
			setActive(true)
			skipReset()
			startStep(math.clamp(saved + 1, 1, #STEPS))
		end
	end)
end

-- 일어난 일 알리기 ("Bag" = 가방을 열었어요)
function Tutorial.Notice(what: string)
	noticed[what] = true
end

function Tutorial.IsActive(): boolean
	return current > 0
end

-- 꾸미기 모드 동안 숨기기
function Tutorial.SetSuppressed(on: boolean)
	suppressed = on
	local f = card
	if f and current > 0 then
		f.Visible = not on and not yielding
	end
	if on then
		clearGuide()
	end
end

-- 검사용
function Tutorial.Step(): number
	return current
end

return Tutorial
