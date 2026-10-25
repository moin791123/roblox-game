-- 🔄 환생 창: 코인을 0으로 돌리고 영구 보너스를 받아요 (펫·집·받침대·옷·가구는 그대로)
-- 다음 환생 선물(새 지역 🗺 / 새 층 🏗)과 앞으로 열릴 것도 보여 줘요
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local RebirthWindow = {}

type Row = { Now: TextLabel, Next: TextLabel }

local window: UiKit.Window
local countLabel: TextLabel
local costLabel: TextLabel
local costPill: Frame
local haveLabel: TextLabel
local confirmButton: TextButton
local confirmLabel: TextLabel
local rows: { [string]: Row } = {}
local giftLabel: TextLabel
local futureLabel: TextLabel
local giftCard: Frame
local dirty = true
local confirmToken = 0
local lastFire = 0

-- ×1.25 → "×1.25", ×2 → "×2", ×1.5 → "×1.5"
local function mult(x: number): string
	local s = string.format("%.2f", x)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return "×" .. s
end

-- 보너스 표 (이름, 지금/다음 값 만드는 함수)
local BONUS: { { Key: string, Icon: string, Name: string, Fn: (number) -> string } } = {
	{ Key = "Income", Icon = "🏠", Name = "집 수익", Fn = function(n)
		return mult(Config.RebirthIncomeMult(n))
	end },
	{ Key = "Coin", Icon = "💰", Name = "들판 코인", Fn = function(n)
		return mult(Config.RebirthCoinMult(n))
	end },
	{ Key = "Speed", Icon = "🏃", Name = "이동 속도", Fn = function(n)
		return string.format("+%d%%", math.floor((Config.RebirthSpeedMult(n) - 1) * 100 + 0.5))
	end },
	{ Key = "Luck", Icon = "🍀", Name = "높은 등급 운", Fn = function(n)
		return mult(Config.RebirthLuckMult(n))
	end },
	{ Key = "Hatch", Icon = "🐣", Name = "부화 속도", Fn = function(n)
		return mult(1 + Config.Rebirth.HatchSpeedPerRebirth * n)
	end },
}

-- 환생 r 번째에 새로 열리는 것들 (지역 / 층)
local function unlocksAt(r: number): { string }
	local list: { string } = {}
	for _, zone in Config.Zones do
		if zone.MinRebirth == r and r > 0 then
			table.insert(list, string.format("🗺 %s %s 열림", zone.Emoji, zone.Name))
		end
	end
	for f, info in Config.FloorInfo do
		if f >= 2 and info.MinRebirth == r and r > 0 then
			table.insert(list, if f == Config.House.MaxFloors + 1 then "🏡 2번 집 가능" else "🏗 " .. Config.FloorName(f) .. " 가능") -- ★v8
		end
	end
	return list
end

-- r 보다 뒤에 처음 열리는 지역 / 층: (글자) 또는 nil
local function nextUnlockAfter(r: number): string?
	local parts: { string } = {}
	for _, zone in Config.Zones do
		if zone.MinRebirth > r then
			table.insert(parts, string.format("%s %s (환생 %d)", zone.Emoji, zone.Name, zone.MinRebirth))
			break
		end
	end
	for f, info in Config.FloorInfo do
		if f >= 2 and info.MinRebirth > r then
			table.insert(parts, string.format("%s (환생 %d)", if f == Config.House.MaxFloors + 1 then "🏡 2번 집" else "🏗 " .. Config.FloorName(f), info.MinRebirth)) -- ★v8
			break
		end
	end
	if #parts == 0 then
		return nil
	end
	return "🎯 그다음: " .. table.concat(parts, " · ")
end

local function coins(): number
	local snap = State.Snapshot
	return if snap then tonumber(snap.Coins) or 0 else 0
end

local function resetConfirm()
	confirmToken = 0
	if confirmLabel and confirmButton.Parent then
		confirmLabel.Text = "🔄 환생하기"
		confirmButton.BackgroundColor3 = C.Lavender
	end
end

local function onConfirm()
	local snap = State.Snapshot
	if not snap then
		return
	end
	local rebirths = tonumber(snap.Rebirths) or 0
	local cost = tonumber(snap.RebirthCost) or Config.RebirthCost(rebirths)
	if rebirths >= Config.Rebirth.MaxRebirths then
		Toasts.Show("환생을 모두 했어요! 최고예요 🏆", "info")
		return
	end
	if coins() < cost then
		Toasts.Show(string.format("코인이 %s 필요해요 💰", Config.FormatNumber(cost)), "warn")
		UiKit.Shake(confirmButton, 6, 6)
		resetConfirm()
		return
	end
	-- 2초 안에 두 번 눌러야 환생해요
	if confirmToken == 0 then
		confirmToken += 1
		local my = confirmToken
		confirmLabel.Text = "정말 환생? (코인 0!)"
		confirmButton.BackgroundColor3 = C.Red
		UiKit.Shake(confirmButton, 5, 6)
		task.delay(2, function()
			if confirmToken == my then
				resetConfirm()
			end
		end)
		return
	end
	resetConfirm()
	if os.clock() - lastFire < 0.5 then
		return
	end
	lastFire = os.clock()
	Remotes.Rebirth:FireServer()
	UiKit.PlaySound("Buy")
end

local function rebuild()
	dirty = false
	local snap = State.Snapshot
	if not snap then
		return
	end
	local rebirths = tonumber(snap.Rebirths) or 0
	local cost = tonumber(snap.RebirthCost) or Config.RebirthCost(rebirths)
	local maxed = rebirths >= Config.Rebirth.MaxRebirths
	local have = coins()

	countLabel.Text = string.format("🔄 환생 %d회  (최대 %d회)", rebirths, Config.Rebirth.MaxRebirths)

	-- 다음 환생 선물
	if maxed then
		giftLabel.Text = "🏆 모든 지역과 층이 열렸어요!"
		futureLabel.Text = ""
	else
		local gifts = unlocksAt(rebirths + 1)
		giftLabel.Text = if #gifts > 0
			then "🎁 다음 환생 선물: " .. table.concat(gifts, " / ")
			else "🎁 다음 환생 선물: 보너스가 더 커져요! ✨"
		futureLabel.Text = nextUnlockAfter(rebirths + 1) or "🌟 이제 보너스만 더 커져요!"
		giftCard.BackgroundColor3 = UiKit.Lighten(if #gifts > 0 then C.Gold else C.Lemon, 0.7)
	end
	for _, def in BONUS do
		local row = rows[def.Key]
		if row then
			row.Now.Text = def.Fn(rebirths)
			row.Next.Text = if maxed then "—" else def.Fn(rebirths + 1)
		end
	end
	if maxed then
		costLabel.Text = "최대 환생 ✅"
		costPill.BackgroundColor3 = C.Mint
		haveLabel.Text = "모든 환생을 마쳤어요!"
		confirmLabel.Text = "완료 ✅"
		confirmButton.BackgroundColor3 = C.Grey
	else
		costLabel.Text = "💰 비용 " .. Config.FormatNumber(cost)
		local can = have >= cost
		costPill.BackgroundColor3 = if can then C.Mint else C.Lemon
		haveLabel.Text = if can
			then "지금 환생할 수 있어요! ✨"
			else string.format("내 코인 %s  ·  %s 더 필요", Config.FormatNumber(have), Config.FormatNumber(cost - have))
		if confirmToken == 0 then
			confirmLabel.Text = "🔄 환생하기"
			confirmButton.BackgroundColor3 = if can then C.Lavender else C.Grey
		end
	end
end

local function infoCard(parent: Instance, color: Color3, order: number, height: number): Frame
	local card: Frame = Make("Frame", {
		Size = UDim2.new(1, -8, 0, height),
		BackgroundColor3 = UiKit.Lighten(color, 0.75),
		LayoutOrder = order,
		Parent = parent,
	})
	UiKit.Corner(card, UDim.new(0, 18))
	UiKit.Stroke(card, color, 4, true)
	return card
end

function RebirthWindow.Init(gui: Instance)
	window = UiKit.Window(gui, { Title = "🔄 환생", Color = C.Lavender, Name = "RebirthWindow" })
	local content = window.Content
	local scroll = UiKit.ListScroller(content, { ScrollBarImageColor3 = C.Lavender })

	-- 환생 횟수
	local head: Frame = Make("Frame", {
		Size = UDim2.new(1, -8, 0, 40),
		BackgroundColor3 = C.Lavender,
		LayoutOrder = 1,
		Parent = scroll,
	})
	UiKit.Corner(head, UDim.new(0.5, 0))
	UiKit.Gradient(head)
	UiKit.Stroke(head, C.White, 3, true)
	countLabel = UiKit.Label({
		Text = "🔄 환생 0회",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.74),
		Parent = head,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.5), MaxText = 24 })

	-- 설명
	local explain = infoCard(scroll, C.Sky, 2, 66)
	UiKit.Label({
		Text = "코인이 0이 되지만 펫·집·받침대·테마·옷·가구는 그대로!\n대신 영구 보너스와 새 지역이 열려요 ✨",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.8),
		TextColor3 = C.Ink,
		Parent = explain,
	}, { Stroke = C.White, MaxText = 22 })

	-- 다음 환생 선물 (새 지역 / 새 층)
	giftCard = infoCard(scroll, C.Gold, 3, 74)
	giftLabel = UiKit.Label({
		Text = "",
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -24, 0, 34),
		TextColor3 = C.Ink,
		Parent = giftCard,
	}, { Stroke = C.White, MaxText = 24 })
	futureLabel = UiKit.Label({
		Text = "",
		Position = UDim2.new(0, 12, 0, 42),
		Size = UDim2.new(1, -24, 0, 26),
		TextColor3 = UiKit.Darken(C.Lavender, 0.35),
		Parent = giftCard,
	}, { Stroke = C.White, MaxText = 20 })

	-- 보너스 표
	local rowH = 36
	local table_ = infoCard(scroll, C.Mint, 4, 34 + rowH * #BONUS + 10)
	local function cell(parent: Instance, text: string, x: number, w: number, color: Color3, stroke: Color3?, maxText: number?): TextLabel
		return UiKit.Label({
			Text = text,
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromScale(w, 1),
			TextColor3 = color,
			Parent = parent,
		}, { Stroke = stroke or C.White, MaxText = maxText or 22 })
	end
	local header: Frame = Make("Frame", {
		Position = UDim2.new(0, 0, 0, 6),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = table_,
	})
	cell(header, "보너스", 0.04, 0.4, C.White, UiKit.Darken(C.Mint, 0.5))
	cell(header, "지금", 0.46, 0.24, C.White, UiKit.Darken(C.Mint, 0.5))
	cell(header, "다음 ➜", 0.72, 0.24, C.White, UiKit.Darken(C.Lavender, 0.4))
	for i, def in BONUS do
		local row: Frame = Make("Frame", {
			Position = UDim2.new(0, 0, 0, 34 + (i - 1) * rowH),
			Size = UDim2.new(1, 0, 0, rowH),
			BackgroundColor3 = C.White,
			BackgroundTransparency = if i % 2 == 0 then 0.6 else 1,
			Parent = table_,
		})
		cell(row, def.Icon .. " " .. def.Name, 0.04, 0.4, C.Ink)
		local now = cell(row, "×1", 0.46, 0.24, C.Ink)
		local nxt = cell(row, "×1", 0.72, 0.24, C.White, UiKit.Darken(C.Lavender, 0.4), 24)
		rows[def.Key] = { Now = now, Next = nxt }
	end

	-- 비용 + 내 코인
	costPill = Make("Frame", {
		Size = UDim2.new(1, -8, 0, 40),
		BackgroundColor3 = C.Lemon,
		LayoutOrder = 5,
		Parent = scroll,
	})
	UiKit.Corner(costPill, UDim.new(0.5, 0))
	UiKit.Gradient(costPill)
	UiKit.Stroke(costPill, C.White, 3, true)
	costLabel = UiKit.Label({
		Text = "💰 비용",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.74),
		Parent = costPill,
	}, { Stroke = UiKit.Darken(C.Lemon, 0.5), MaxText = 26 })
	haveLabel = UiKit.Label({
		Text = "",
		Size = UDim2.new(1, -8, 0, 26),
		TextColor3 = C.Ink,
		LayoutOrder = 6,
		Parent = scroll,
	}, { Stroke = C.White, MaxText = 20 })

	-- 환생 버튼 (두 번 눌러야 해요)
	local btnRow: Frame = Make("Frame", {
		Size = UDim2.new(1, -8, 0, 64),
		BackgroundTransparency = 1,
		LayoutOrder = 7,
		Parent = scroll,
	})
	confirmButton, confirmLabel = UiKit.Button({
		Name = "Rebirth",
		Text = "🔄 환생하기",
		Color = C.Lavender,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.7, 0, 1, 0),
		Radius = UDim.new(0.4, 0),
		TextSize = 30,
		Sound = "Click",
		Parent = btnRow,
		OnClick = onConfirm,
	})
	Make("UISizeConstraint", { MinSize = Vector2.new(220, 56), Parent = confirmButton })

	window.OnOpen = function()
		resetConfirm()
		if dirty then
			rebuild()
		end
	end
	-- 코인이 바뀌면 "살 수 있어요" 표시 다시 (열려 있을 때만)
	State.OnCoins(function()
		if window.IsOpen() then
			rebuild()
		else
			dirty = true
		end
	end)
end

function RebirthWindow.OnSync()
	if window and window.IsOpen() then
		rebuild()
	else
		dirty = true
	end
end

function RebirthWindow.Open()
	window.Open()
end

function RebirthWindow.Close()
	window.Close()
end

function RebirthWindow.IsOpen(): boolean
	return window ~= nil and window.IsOpen()
end

return RebirthWindow
