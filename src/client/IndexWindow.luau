-- 📖 도감 창: 펫을 지역별로 (지역 머리글에 잠김 표시). 찾은 펫은 최고 등급 모습 + 등급 배지,
-- 못 찾은 펫은 그림자 + ??? (비밀 펫은 "<알 이름>에서 아주 드물게… ✨" 힌트)
-- ★v6 지역마다 "🌟 희귀 3종" 줄: 시크릿 / 천상 / 이터널 펫 (★ ~ ★★★ 알약), 못 찾으면 그림자 + "<알 이름>에서만 나와요",
--   지역마다 몇 마리 모았는지. 펫 수는 Config 에서 세요 (66 + 24 = 90). PetOrder 에 없는 펫도 지역 순으로 붙여요.
local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local IndexWindow = {}

type Entry = {
	Frame: Frame,
	Holder: Frame,
	Name: TextLabel,
	Hint: TextLabel?, -- ★v6 희귀 3종 칸: "<알 이름>에서만 나와요"
	Badge: Frame,
	BadgeLabel: TextLabel,
	Tier: number?, -- nil = 아직 안 그림, 0 = 미발견, 1~ = 발견한 최고 등급
}

type Group = {
	Zone: number,
	Header: TextLabel,
	HeaderPill: Frame,
	Section: Frame,
	Pets: { string },
	Rare: { string }, -- ★v6 시크릿 / 천상 / 이터널 (단계 순)
	RareHeader: TextLabel?,
	RarePill: Frame?,
}

local RARE_ROW_COLOR = Color3.fromRGB(125, 100, 205)
local RARE_DARK = Color3.fromRGB(38, 32, 78)

local window: UiKit.Window
local progressLabel: TextLabel
local barFill: Frame
local entries: { [string]: Entry } = {}
local groups: { Group } = {}
local dirty = true
local lastCount = -1

-- 도감에 넣을 펫 순서: PetOrder (있는 것만, 한 번씩) + 빠진 펫 (지역 → 희귀도 → id 순)
local function petList(): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, petId in Config.PetOrder do
		if Config.Pets[petId] and not seen[petId] then
			seen[petId] = true
			table.insert(out, petId)
		end
	end
	local extra: { string } = {}
	for petId in Config.Pets do
		if not seen[petId] then
			table.insert(extra, petId)
		end
	end
	local function order(id: string): number
		local r = (Config.Rarities :: any)[Config.Pets[id].Rarity]
		return if r and r.Order then r.Order else 7 + UiKit.SpecialRank(Config.Pets[id].Rarity)
	end
	table.sort(extra, function(a, b)
		local za, zb = Config.Pets[a].Zone or 1, Config.Pets[b].Zone or 1
		if za ~= zb then
			return za < zb
		end
		local oa, ob = order(a), order(b)
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
	for _, petId in extra do
		table.insert(out, petId)
	end
	return out
end
local allPets: { string } = {}

-- ★v6 희귀 3종 힌트
local function rareHint(petId: string): string
	local eggId = UiKit.SpecialEggOfPet(petId)
	local egg = if eggId then Config.Eggs[eggId] else nil
	if egg then
		return egg.Name .. "에서만 나와요"
	end
	return "아주 희귀한 알에서만 나와요"
end

-- 비밀 펫 힌트: 그 펫이 나올 확률(가중치 ÷ 그 알 가중치 합)이 가장 높은 알 이름.
-- 지역마다 알이 5~6개여도, EggOrder 에 없는 알이 있어도 괜찮게 Config.Eggs 를 다 봐요 (같으면 EggOrder 앞쪽)
local secretHints: { [string]: string } = {}
do
	local order: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, eggId in Config.EggOrder do
		if Config.Eggs[eggId] and not seen[eggId] then
			seen[eggId] = true
			table.insert(order, eggId)
		end
	end
	local extra: { string } = {}
	for eggId in Config.Eggs do
		if not seen[eggId] then
			table.insert(extra, eggId)
		end
	end
	table.sort(extra)
	for _, eggId in extra do
		table.insert(order, eggId)
	end
	local bestChance: { [string]: number } = {}
	for _, eggId in order do
		local egg = Config.Eggs[eggId]
		local total = 0
		for _, weight in egg.Pets do
			total += math.max(0, tonumber(weight) or 0)
		end
		if total > 0 then
			for petId, weight in egg.Pets do
				local def = Config.Pets[petId]
				local chance = math.max(0, tonumber(weight) or 0) / total
				if def and def.Rarity == "Secret" and chance > 0 and chance > (bestChance[petId] or 0) then
					bestChance[petId] = chance
					secretHints[petId] = eggId
				end
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
	local hint = entry.Hint
	if hint then
		-- ★v6 희귀 3종: 찾으면 "🎉 찾았어요!", 못 찾으면 어느 알에서 나오는지
		hint.Text = if discovered then "🎉 찾았어요!" else rareHint(petId)
		hint.TextColor3 = if discovered then C.Ink else C.White
		local hs = hint:FindFirstChildOfClass("UIStroke")
		if hs then
			hs.Color = if discovered then C.White else UiKit.Darken(rc, 0.55)
		end
	end
	if discovered then
		entry.Name.Text = Config.PetDisplayName(petId, tier)
		entry.Frame.BackgroundColor3 = UiKit.Lighten(if tier >= 2 then UiKit.TierColor(tier) else rc, 0.8)
		if before ~= nil then
			UiKit.Pop(entry.Frame, 0.45) -- 새로 찾았거나 등급이 올랐어요
		end
	elseif hint then
		entry.Name.Text = "???"
		entry.Frame.BackgroundColor3 = RARE_DARK
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
	-- 한 묶음 칠하기: 찾은 수 (뷰포트 만들기는 무거워서 6개마다 한 프레임 쉬어요, 처음 열 때 90개)
	local stale = false
	local function paint(list: { string }): number
		local found = 0
		for _, petId in list do
			local tier = indexTier(index[petId])
			if tier >= 1 then
				found += 1
				count += 1
			end
			local entry = entries[petId]
			if entry and entry.Tier ~= tier and not stale then
				setTier(petId, entry, tier)
				built += 1
				if built % 6 == 0 then
					task.wait()
					if rebuildGen ~= myGen then
						stale = true
					end
				end
			end
		end
		return found
	end
	for _, group in groups do
		local found = paint(group.Pets)
		local rareFound = paint(group.Rare)
		if stale then
			return
		end
		local zone = Config.Zones[group.Zone]
		local unlocked = Config.ZoneUnlocked(group.Zone, rebirths)
		group.Header.Text = if unlocked
			then string.format("%s %s  %d / %d", zone.Emoji, zone.Name, found, #group.Pets)
			else string.format("🔒 %s %s · 환생 %d  %d / %d", zone.Emoji, zone.Name, zone.MinRebirth, found, #group.Pets)
		group.HeaderPill.BackgroundColor3 = if unlocked then zone.Palette.Accent else C.Grey
		local rh, rp = group.RareHeader, group.RarePill
		if rh and rp then
			local n = #group.Rare
			rh.Text = if rareFound >= n and n > 0
				then string.format("🌟 희귀 %d종 다 모았어요!  %d / %d", n, rareFound, n)
				elseif unlocked then string.format("🌟 희귀 %d종  %d / %d", n, rareFound, n)
				else string.format("🔒 🌟 희귀 %d종  %d / %d", n, rareFound, n)
			rp.BackgroundColor3 = if rareFound >= n and n > 0 then C.Gold elseif unlocked then RARE_ROW_COLOR else C.Grey
		end
	end
	local total = #allPets
	progressLabel.Text = string.format("📖 %d / %d", count, total)
	UiKit.Tween(barFill, 0.5, { Size = UDim2.fromScale(math.max(0.04, count / total), 1) }, Enum.EasingStyle.Back)
	if lastCount >= 0 and count > lastCount then
		UiKit.Bump(progressLabel, 0.25)
	end
	lastCount = count
end

local function createEntry(parent: Instance, petId: string, order: number, rare: boolean?): Entry
	local def = Config.Pets[petId]
	local rc = UiKit.RarityColor(def.Rarity)
	local special = if rare then UiKit.PetSpecial(petId) else nil
	local frame: Frame = Make("Frame", {
		Name = petId,
		LayoutOrder = order,
		BackgroundColor3 = if rare then RARE_DARK else Color3.fromRGB(225, 222, 235),
		Parent = parent,
	})
	UiKit.Corner(frame, UDim.new(0.12, 0))
	local frameStroke = UiKit.Stroke(frame, rc, 4, true)
	if special then
		frameStroke.Color = C.White
		UiKit.SpecialGradient(frameStroke, special) -- 단계 색 테두리 (돌지 않아요)
	end
	-- 희귀 3종 칸은 조금 더 길어요 (힌트 줄)
	local function Y(v: number): number
		return if rare then v * 1.3 / 1.45 else v
	end
	local holder: Frame = Make("Frame", {
		Name = "Viewport",
		Position = UDim2.fromScale(0.07, Y(0.05)),
		Size = UDim2.fromScale(0.86, Y(0.62)),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.3,
		ClipsDescendants = true,
		Parent = frame,
	})
	UiKit.Corner(holder, UDim.new(0.2, 0))
	local nameLabel = UiKit.Label({
		Text = "???",
		Position = UDim2.fromScale(0.05, Y(0.68)),
		Size = UDim2.fromScale(0.9, Y(0.15)),
		Parent = frame,
	}, { Stroke = UiKit.Darken(rc, 0.5), MaxText = 24 })
	local hint: TextLabel? = nil
	if rare then
		hint = UiKit.Label({
			Name = "Hint",
			Text = rareHint(petId),
			Position = UDim2.fromScale(0.05, Y(0.83)),
			Size = UDim2.fromScale(0.9, Y(0.15)),
			Parent = frame,
		}, { Stroke = UiKit.Darken(rc, 0.55), MaxText = 15 })
	end
	local rinfo = (Config.Rarities :: any)[def.Rarity]
	local rpill: Frame = Make("Frame", {
		Name = "RarityPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, if rare then 1 - 0.13 * 1.3 / 1.45 else 0.84),
		Size = UDim2.fromScale(if rare then 0.78 else 0.64, Y(0.12)),
		BackgroundColor3 = rc,
		Parent = frame,
	})
	UiKit.Corner(rpill, UDim.new(0.5, 0))
	local rname = if rinfo and rinfo.Name then rinfo.Name else UiKit.RarityName(def.Rarity)
	if special then
		-- ★ 시크릿 / ★★ 천상 / ★★★ 이터널
		UiKit.Gradient(rpill)
		UiKit.Stroke(rpill, C.White, 2, true)
		rname = UiKit.SpecialStars(special) .. " " .. rname
	end
	UiKit.Label({ Name = "Rarity", Text = rname, Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), Parent = rpill }, { Stroke = UiKit.Darken(rc, 0.45), MaxText = 18 })
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
	return { Frame = frame, Holder = holder, Name = nameLabel, Hint = hint, Badge = badge, BadgeLabel = badgeLabel, Tier = nil }
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
	allPets = petList()
	progressLabel = UiKit.Label({
		Text = "📖 0 / " .. #allPets,
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

	-- 지역별 묶음 (지역 순서, 지역 안에서는 PetOrder = 희귀도 순). ★v6 그 아래 "🌟 희귀 3종" 줄
	for zoneIndex, zone in Config.Zones do
		local header = UiKit.SectionHeader(scroll, "", zone.Palette.Accent, zoneIndex * 4 - 3, 300)
		local pill = header.Parent :: Frame
		local section: Frame = Make("Frame", {
			Name = zone.Id,
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			LayoutOrder = zoneIndex * 4 - 2,
			Parent = scroll,
		})
		table.insert(groups, { Zone = zoneIndex, Header = header, HeaderPill = pill, Section = section, Pets = {}, Rare = {} })
	end
	for _, petId in allPets do
		local def = Config.Pets[petId]
		local group = groups[math.clamp(def.Zone or 1, 1, #groups)]
		if UiKit.PetSpecial(petId) then
			table.insert(group.Rare, petId)
		else
			table.insert(group.Pets, petId)
		end
	end
	for _, group in groups do
		table.sort(group.Rare, function(a, b)
			return UiKit.SpecialRank(Config.Pets[a].Rarity) < UiKit.SpecialRank(Config.Pets[b].Rarity)
		end)
		for i, petId in group.Pets do
			entries[petId] = createEntry(group.Section, petId, i)
		end
		UiKit.SectionGrid(group.Section, scroll, 128, 1.3, 6)
		if #group.Rare > 0 then
			local rh = UiKit.SectionHeader(scroll, "", RARE_ROW_COLOR, group.Zone * 4 - 1, 260)
			local row = (rh.Parent :: Frame).Parent :: Frame
			row.Name = "RareHeader"
			local rareSection: Frame = Make("Frame", {
				Name = Config.Zones[group.Zone].Id .. "_Rare",
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				LayoutOrder = group.Zone * 4,
				Parent = scroll,
			})
			group.RareHeader = rh
			group.RarePill = rh.Parent :: Frame
			for i, petId in group.Rare do
				entries[petId] = createEntry(rareSection, petId, i, true)
			end
			UiKit.SectionGrid(rareSection, scroll, 128, 1.45, 6) -- 보통 칸과 같은 크기로 가운데에
		end
	end

	window.OnOpen = function()
		if dirty then
			rebuild()
		end
	end
	-- 뷰포트는 처음 열 때 만들어요 (시작할 때 90마리를 한꺼번에 만들면 잠깐 멈칫함)
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
