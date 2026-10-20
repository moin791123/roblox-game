-- 📖 도감 창: 펫 66마리를 지역별로 (지역 머리글에 잠김 표시). 찾은 펫은 최고 등급 모습 + 등급 배지,
-- 못 찾은 펫은 그림자 + ??? (비밀 펫은 "<알 이름>에서 아주 드물게… ✨" 힌트)
local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local IndexWindow = {}

type Entry = {
	Frame: Frame,
	Holder: Frame,
	Name: TextLabel,
	Badge: Frame,
	BadgeLabel: TextLabel,
	Tier: number?, -- nil = 아직 안 그림, 0 = 미발견, 1~ = 발견한 최고 등급
}

type Group = { Zone: number, Header: TextLabel, HeaderPill: Frame, Section: Frame, Pets: { string } }

local window: UiKit.Window
local progressLabel: TextLabel
local barFill: Frame
local entries: { [string]: Entry } = {}
local groups: { Group } = {}
local dirty = true
local lastCount = -1

-- 비밀 펫 힌트: 그 펫이 가장 잘 나오는 알 이름 (알 표에서 찾아요)
local secretHints: { [string]: string } = {}
for _, eggId in Config.EggOrder do
	local egg = Config.Eggs[eggId]
	for petId, weight in egg.Pets do
		local def = Config.Pets[petId]
		if def and def.Rarity == "Secret" then
			local best = secretHints[petId]
			local bestWeight = if best then (Config.Eggs[best].Pets[petId] or 0) else -1
			if weight > bestWeight then
				secretHints[petId] = eggId
			end
		end
	end
end

local function secretHint(petId: string): string
	local eggId = secretHints[petId]
	local egg = if eggId then Config.Eggs[eggId] else nil
	if egg then
		return egg.Name .. "에서\n아주 드물게… ✨"
	end
	return "아주 드문 비밀 펫… ✨"
end

-- 도감 값 → 발견한 최고 등급 (예전 데이터 true = 1, 없으면 0)
local function indexTier(value: any): number
	if value == true then
		return 1
	end
	local n = tonumber(value)
	if n and n >= 1 then
		return math.clamp(math.floor(n), 1, Config.MaxTier)
	end
	return 0
end

local function setTier(petId: string, entry: Entry, tier: number)
	if entry.Tier == tier then
		return
	end
	local before = entry.Tier
	entry.Tier = tier
	for _, child in entry.Holder:GetChildren() do
		if child:IsA("GuiObject") then -- UICorner 같은 꾸밈은 남김
			child:Destroy()
		end
	end
	local discovered = tier >= 1
	UiKit.Viewport("Pet", petId, entry.Holder, not discovered, if discovered then tier else nil)
	local def = Config.Pets[petId]
	local rc = UiKit.RarityColor(def.Rarity)
	if discovered then
		entry.Name.Text = Config.PetDisplayName(petId, tier)
		entry.Frame.BackgroundColor3 = UiKit.Lighten(if tier >= 2 then UiKit.TierColor(tier) else rc, 0.8)
		if before ~= nil then
			UiKit.Pop(entry.Frame, 0.45) -- 새로 찾았거나 등급이 올랐어요
		end
	else
		-- 비밀 펫은 힌트만 살짝
		entry.Name.Text = if def.Rarity == "Secret" then secretHint(petId) else "???"
		entry.Frame.BackgroundColor3 = if def.Rarity == "Secret" then Color3.fromRGB(40, 35, 80) else Color3.fromRGB(225, 222, 235)
	end
	local badge = if tier >= 2 then UiKit.TierEmoji(tier) else nil
	entry.Badge.Visible = badge ~= nil and badge ~= ""
	if badge and badge ~= "" then
		entry.BadgeLabel.Text = badge
		entry.Badge.BackgroundColor3 = UiKit.TierColor(tier)
		if before ~= nil then
			UiKit.Pop(entry.Badge, 0.5)
		end
	end
end

local rebuildGen = 0

local function rebuild()
	dirty = false
	rebuildGen += 1
	local myGen = rebuildGen
	local snap = State.Snapshot
	local index: { [string]: any } = if snap then snap.Index else {}
	local rebirths = State.Rebirths()
	local count = 0
	local built = 0
	for _, group in groups do
		local found = 0
		for _, petId in group.Pets do
			local tier = indexTier(index[petId])
			if tier >= 1 then
				found += 1
				count += 1
			end
			local entry = entries[petId]
			if entry and entry.Tier ~= tier then
				setTier(petId, entry, tier)
				built += 1
				-- 뷰포트(펫 모델) 만들기는 무거워서 6개마다 한 프레임 쉬어요 (처음 열 때 66개)
				if built % 6 == 0 then
					task.wait()
					if rebuildGen ~= myGen then
						return
					end
				end
			end
		end
		local zone = Config.Zones[group.Zone]
		local unlocked = Config.ZoneUnlocked(group.Zone, rebirths)
		group.Header.Text = if unlocked
			then string.format("%s %s  %d / %d", zone.Emoji, zone.Name, found, #group.Pets)
			else string.format("🔒 %s %s · 환생 %d  %d / %d", zone.Emoji, zone.Name, zone.MinRebirth, found, #group.Pets)
		group.HeaderPill.BackgroundColor3 = if unlocked then zone.Palette.Accent else C.Grey
	end
	local total = #Config.PetOrder
	progressLabel.Text = string.format("📖 %d / %d", count, total)
	UiKit.Tween(barFill, 0.5, { Size = UDim2.fromScale(math.max(0.04, count / total), 1) }, Enum.EasingStyle.Back)
	if lastCount >= 0 and count > lastCount then
		UiKit.Bump(progressLabel, 0.25)
	end
	lastCount = count
end

local function createEntry(parent: Instance, petId: string, order: number): Entry
	local def = Config.Pets[petId]
	local rc = UiKit.RarityColor(def.Rarity)
	local frame: Frame = Make("Frame", {
		Name = petId,
		LayoutOrder = order,
		BackgroundColor3 = Color3.fromRGB(225, 222, 235),
		Parent = parent,
	})
	UiKit.Corner(frame, UDim.new(0.12, 0))
	UiKit.Stroke(frame, rc, 4, true)
	local holder: Frame = Make("Frame", {
		Name = "Viewport",
		Position = UDim2.fromScale(0.07, 0.05),
		Size = UDim2.fromScale(0.86, 0.62),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.3,
		ClipsDescendants = true,
		Parent = frame,
	})
	UiKit.Corner(holder, UDim.new(0.2, 0))
	local nameLabel = UiKit.Label({
		Text = "???",
		Position = UDim2.fromScale(0.05, 0.68),
		Size = UDim2.fromScale(0.9, 0.15),
		Parent = frame,
	}, { Stroke = UiKit.Darken(rc, 0.5), MaxText = 24 })
	local rinfo = (Config.Rarities :: any)[def.Rarity]
	local rpill: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.84),
		Size = UDim2.fromScale(0.64, 0.12),
		BackgroundColor3 = rc,
		Parent = frame,
	})
	UiKit.Corner(rpill, UDim.new(0.5, 0))
	UiKit.Label({ Text = rinfo and rinfo.Name or "", Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), Parent = rpill }, { Stroke = UiKit.Darken(rc, 0.45), MaxText = 18 })
	-- 등급 배지 (🥉🥈🥇🌈💎🌌), 오른쪽 위
	local badge: Frame = Make("Frame", {
		Name = "TierBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.03),
		Size = UDim2.fromScale(0.24, 0.18),
		BackgroundColor3 = C.Gold,
		Visible = false,
		ZIndex = 3,
		Parent = frame,
	})
	Make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = badge })
	UiKit.Corner(badge, UDim.new(0.5, 0))
	UiKit.Stroke(badge, C.White, 3, true)
	local badgeLabel = UiKit.Label({ Text = "", Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), ZIndex = 4, Parent = badge }, { MaxText = 30 })
	return { Frame = frame, Holder = holder, Name = nameLabel, Badge = badge, BadgeLabel = badgeLabel, Tier = nil }
end

function IndexWindow.Init(gui: Instance)
	window = UiKit.Window(gui, { Title = "📖 펫 도감", Color = C.Sky, Name = "IndexWindow" })
	local content = window.Content

	-- 진행도
	local head: Frame = Make("Frame", {
		Name = "Progress",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 46),
		Parent = content,
	})
	progressLabel = UiKit.Label({
		Text = "📖 0 / " .. #Config.PetOrder,
		Size = UDim2.new(0.3, 0, 1, -6),
		Position = UDim2.fromOffset(0, 3),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = head,
	}, { Stroke = UiKit.Darken(C.Sky, 0.45), StrokeThickness = 3, MaxText = 32 })
	local bar: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.new(0.68, 0, 0, 26),
		BackgroundColor3 = Color3.fromRGB(230, 225, 240),
		ClipsDescendants = false,
		Parent = head,
	})
	UiKit.Corner(bar, UDim.new(0.5, 0))
	UiKit.Stroke(bar, C.White, 3, true)
	barFill = Make("Frame", {
		Size = UDim2.fromScale(0.04, 1),
		BackgroundColor3 = C.White,
		Parent = bar,
	})
	UiKit.Corner(barFill, UDim.new(0.5, 0))
	Make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.Pink),
			ColorSequenceKeypoint.new(0.5, C.Lemon),
			ColorSequenceKeypoint.new(1, C.Mint),
		}),
		Parent = barFill,
	})

	local scroll = UiKit.ListScroller(content, { Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 1, -52), ScrollBarImageColor3 = C.Sky })

	-- 지역별 묶음 (지역 순서, 지역 안에서는 PetOrder = 희귀도 순)
	for zoneIndex, zone in Config.Zones do
		local header = UiKit.SectionHeader(scroll, "", zone.Palette.Accent, zoneIndex * 2 - 1, 300)
		local pill = header.Parent :: Frame
		local section: Frame = Make("Frame", {
			Name = zone.Id,
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			LayoutOrder = zoneIndex * 2,
			Parent = scroll,
		})
		table.insert(groups, { Zone = zoneIndex, Header = header, HeaderPill = pill, Section = section, Pets = {} })
	end
	for _, petId in Config.PetOrder do
		local def = Config.Pets[petId]
		local group = groups[math.clamp(def.Zone or 1, 1, #groups)]
		table.insert(group.Pets, petId)
	end
	for _, group in groups do
		for i, petId in group.Pets do
			entries[petId] = createEntry(group.Section, petId, i)
		end
		UiKit.SectionGrid(group.Section, scroll, 128, 1.3, 6)
	end

	window.OnOpen = function()
		if dirty then
			rebuild()
		end
	end
	-- 뷰포트는 처음 열 때 만들어요 (시작할 때 66마리를 한꺼번에 만들면 잠깐 멈칫함)
end

function IndexWindow.OnSync()
	if window and window.IsOpen() then
		rebuild()
	else
		dirty = true
	end
end

function IndexWindow.Open()
	window.Open()
end

function IndexWindow.Close()
	window.Close()
end

function IndexWindow.IsOpen(): boolean
	return window ~= nil and window.IsOpen()
end

return IndexWindow
