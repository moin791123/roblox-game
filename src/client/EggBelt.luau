-- 내 컨베이어 알 (★v5 사람마다 따로): 서버가 보내는 EggBelt 이벤트대로 알을 내 화면에만 그려요. 남의 알은 안 보여요.
-- 알 자리는 나온 시각으로 계산해요 (Config.BeltEggSpot + workspace:GetServerTimeNow()) → 서버가 검사하는 자리와 같아요.
-- 가까운 알(Conveyor.RenderDistance)만 모델로 그리고, 좋은 알 빛기둥 + "✨ <알 이름>!" 간판은 멀리서도 보여요.
-- 사기: 알의 ProximityPrompt (PromptKind "Buy") → Remotes.BuyEgg(uid). 서버가 검증하고 "Bought" 를 보내면 집으로 날아가요.
-- 파트는 workspace.ClientEggs 아래에 (나한테만 보임). 벨트·슈트·통·줄무늬는 서버(ConveyorService) + ZoneClient 몫이에요.
-- ★v6 아주 희귀한 알 (시크릿 / 천상 / 이터널, egg.Special): 좋은 알보다 더 높은 단계 색 빛기둥 + 은은한 빛 테두리,
--   바닥의 빛 고리, "🌟 <알 이름>!" 간판 (⏳ 남은 시간), 가격 간판에 꼭 나오는 펫 이름. 벨트에 더 오래 있어요
--   (Config 의 알별 시간 도우미를 써요). 알림 배너(Toasts)·지도(MapWindow)가 EggBelt.Find / Specials 로 물어봐요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PetModels = require(Shared:WaitForChild("PetModels"))
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local CV = Config.Conveyor

local EggBelt = {}

local CULL_INTERVAL = 0.3 -- 모델 만들기/지우기 다시 계산
local BUILDS_PER_CULL = 6 -- 한 번에 만드는 모델 수 (지역에 막 왔을 때 끊기지 않게)
local BEACON_WIDTH = 0.8
local PROMPT_COOLDOWN = 0.6 -- 사기 누른 뒤 서버 답을 기다리는 시간
local FLY_ARC_MIN = 10
-- ★v6 희귀 알 빛기둥: 좋은 알 기둥보다 단계마다 더 높게 (시크릿 ×1.4 / 천상 ×1.6 / 이터널 ×1.8)
local SPECIAL_BEACON_MULT: { [string]: number } = { Hidden = 1.4, Celestial = 1.6, Eternal = 1.8 }
local SPECIAL_BEACON_WIDTH = 1.1
local SPECIAL_HALO_WIDTH = 3.4 -- 기둥 둘레 은은한 빛 (아주 옅게)
local SPECIAL_RING_SIZE = 5.6 -- 알 아래 빛 고리 지름
local SPECIAL_CYCLE = 9 -- 색이 한 바퀴 도는 초 (천천히)
local SPECIAL_COLOR_STEP = 0.1 -- 색 바꾸기 간격 (초)

type Entry = {
	uid: number,
	eggId: string,
	zone: number,
	born: number,
	wobble: number,
	model: Model?,
	main: BasePart?,
	offset: CFrame, -- 피벗 → 몸통
	prompt: ProximityPrompt?,
	beacon: BasePart?,
	special: string?, -- ★v6 "Hidden" | "Celestial" | "Eternal"
	life: number, -- 벨트에 머무는 전체 시간 (희귀 알은 더 길어요)
	halo: BasePart?, -- 희귀 알: 기둥 둘레 옅은 빛
	ring: BasePart?, -- 희귀 알: 알 아래 빛 고리
	signInfo: TextLabel?, -- 빛기둥 간판의 "★★ 천상 · ⏳ 58초"
	infoTimer: TextLabel?, -- 가격 간판의 남은 시간
	highlight: Highlight?,
	promptAt: number, -- 마지막으로 사기를 누른 시각
	-- 산 알: 집으로 날아가는 중
	flying: boolean,
	flyFrom: Vector3,
	flyTo: CFrame,
	flyStart: number,
	flyTime: number,
}

local entries: { [number]: Entry } = {}
local folder: Folder? = nil
local beltRot: { [number]: CFrame } = {} -- 지역마다 벨트 방향 회전
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local initialized = false
local specialListeners: { () -> () } = {}
local lastColorAt = 0

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = workspace:FindFirstChild("ClientEggs")
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = "ClientEggs"
		f.Parent = workspace
	end
	folder = f :: Folder
	return f :: Folder
end

local function clockNow(): number
	return workspace:GetServerTimeNow()
end

local function rotOf(zone: number): CFrame
	local r = beltRot[zone]
	if r then
		return r
	end
	local def = Config.Zones[zone] or Config.Zones[1]
	local dir = (def.ConveyorEnd - def.ConveyorStart).Unit
	r = CFrame.lookAt(Vector3.zero, dir)
	beltRot[zone] = r
	return r
end

-- 보는 기준 위치 (캐릭터가 없으면 카메라)
local function viewPosition(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position else nil
end

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- ★v6 알이 벨트에 머무는 시간 / 자리: Config 가 알 id 를 받아요 (희귀 알은 끝 앞에서 옆으로 비켜 오래 기다려요).
-- 서버(ConveyorService)도 같은 공식이라 자리·시간이 꼭 맞아요
local function eggLife(eggId: string): number
	return Config.BeltEggLife(eggId)
end

local function eggSpot(entry: { zone: number, eggId: string }, age: number): (Vector3, number)
	return Config.BeltEggSpot(entry.zone, age, entry.eggId)
end

-- 아직 살 수 있는 남은 초 (통으로 떨어지기 시작하면 0)
local function timeLeft(entry: Entry, now: number): number
	local cfg: any = Config
	local buyEnd = if type(cfg.BeltEggBuyEnd) == "function" then cfg.BeltEggBuyEnd(entry.eggId) else entry.life - CV.FallTime
	return math.max(0, buyEnd - (now - entry.born))
end

local function leftText(sec: number): string
	local s = math.max(0, math.floor(sec + 0.5))
	if s >= 60 then
		return string.format("⏳ %d분 %02d초", s // 60, s % 60)
	end
	return "⏳ " .. s .. "초"
end

-- 단계 색 (천천히 무지개처럼 돌아요). phase = 0~1
local function cycleColor(tier: string, phase: number): Color3
	local list = UiKit.SpecialPalette(tier)
	local n = #list
	if n <= 1 then
		return list[1] or Color3.new(1, 1, 1)
	end
	local x = (phase % 1) * n
	local i = math.floor(x)
	local a = list[i + 1]
	local b = list[(i + 1) % n + 1]
	return a:Lerp(b, x - i)
end

local function notifySpecial()
	for _, fn in table.clone(specialListeners) do
		local ok, err = pcall(fn)
		if not ok then
			warn("[EggBelt] 희귀 알 알림 오류:", err)
		end
	end
end

local function buildEggModel(eggId: string): Model
	local ok, model = pcall(PetModels.BuildEgg, eggId)
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		return model
	end
	warn("[EggBelt] BuildEgg 실패:", model)
	local m = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2.4, 2.4, 2.4)
	body.Color = Config.Rarities[Config.Eggs[eggId].Rarity].Color
	body.Parent = m
	m.PrimaryPart = body
	m.WorldPivot = body.CFrame * CFrame.new(0, -1.2, 0)
	return m
end

local function makeBillboard(adornee: BasePart, egg: any, entry: Entry?)
	local rarity = Config.Rarities[egg.Rarity]
	local special = if entry then entry.special else nil
	if special then
		-- ★v6 희귀 알 간판: 이름 / 🎁 꼭 나오는 펫 / 💰 가격 / ★★ 천상 · ⏳ 남은 시간
		local color = UiKit.RarityColor(special)
		local petId = UiKit.SpecialPet(entry and entry.eggId)
		local pet = if petId then Config.Pets[petId] else nil
		local sgui = Instance.new("BillboardGui")
		sgui.Name = "EggInfo"
		sgui.Adornee = adornee
		sgui.Size = UDim2.new(11, 0, 5.4, 0)
		sgui.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
		sgui.MaxDistance = 160
		sgui.LightInfluence = 0
		sgui.ResetOnSpawn = false
		local function row(name: string, text: string, textColor: Color3, y: number, h: number): TextLabel
			local l = Instance.new("TextLabel")
			l.Name = name
			l.BackgroundTransparency = 1
			l.Size = UDim2.new(1, 0, h, 0)
			l.Position = UDim2.new(0, 0, y, 0)
			l.Font = Enum.Font.FredokaOne
			l.TextScaled = true
			l.Text = text
			l.TextColor3 = textColor
			l.TextStrokeTransparency = 0.15
			l.TextStrokeColor3 = Color3.fromRGB(40, 30, 60)
			l.Parent = sgui
			return l
		end
		row("EggName", "🌟 " .. egg.Name .. " 🌟", color, 0, 0.3)
		row("Pet", if pet then "🎁 " .. pet.Name .. " 확정!" else "🎁 아주 희귀한 펫 확정!", Color3.fromRGB(255, 250, 240), 0.3, 0.24)
		row("Price", "💰 " .. Config.FormatNumber(egg.Price), Color3.fromRGB(255, 225, 90), 0.54, 0.24)
		local info = row("Tier", UiKit.SpecialStars(special) .. " " .. UiKit.RarityName(special), color, 0.78, 0.22)
		if entry then
			entry.infoTimer = info
		end
		sgui.Parent = adornee
		return
	end
	local premium = egg.Premium == true
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggInfo"
	gui.Adornee = adornee
	-- 비싼 알은 간판도 커요
	gui.Size = if premium then UDim2.new(9, 0, 4, 0) else UDim2.new(7, 0, 3, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if premium then 3.8 else 3.2, 0)
	gui.MaxDistance = if premium then 120 else 90
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local function label(text: string, color: Color3, y: number, h: number)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, h, 0)
		l.Position = UDim2.new(0, 0, y, 0)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.2
		l.TextStrokeColor3 = Color3.fromRGB(40, 30, 60)
		l.Parent = gui
	end
	label(if premium then "✨ " .. egg.Name .. " ✨" else egg.Name, rarity.Color, 0, 0.4)
	label("💰 " .. Config.FormatNumber(egg.Price), Color3.fromRGB(255, 225, 90), 0.4, 0.33)
	label(rarity.Name, rarity.Color, 0.73, 0.27)
	gui.Parent = adornee
end

-- 비싼 알 반짝임 (빛 + 반짝이)
local function addPremiumGlow(main: BasePart, egg: any)
	local color = Config.Rarities[egg.Rarity].Color
	local light = Instance.new("PointLight")
	light.Name = "PremiumGlow"
	light.Color = color
	light.Brightness = 1.6
	light.Range = 9
	light.Parent = main
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "PremiumSparkle"
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparkle.LightEmission = 0.8
	sparkle.Size = NumberSequence.new(0.5, 0)
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Speed = NumberRange.new(1, 2.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 6
	sparkle.Parent = main
end

-- 좋은 알 빛기둥: 앵커된 네온 기둥 + 멀리서도 보이는 간판. 알 모델 밖에 있어서 흔들리지 않아요
local function beaconCFrame(pos: Vector3): CFrame
	local h = CV.BeaconHeight
	return CFrame.new(pos + Vector3.new(0, h / 2 + 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
end

-- ★v6 희귀 알 빛기둥: 더 높고, 둘레에 옅은 빛, 알 아래 빛 고리. 색은 단계 색이 천천히 돌아요
local function specialHeight(tier: string): number
	return CV.BeaconHeight * (SPECIAL_BEACON_MULT[tier] or 1.5)
end

local function specialBeaconCFrame(pos: Vector3, tier: string): CFrame
	local h = specialHeight(tier)
	return CFrame.new(pos + Vector3.new(0, h / 2 + 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
end

local function ringCFrame(pos: Vector3): CFrame
	return CFrame.new(pos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
end

local function makeSpecialBeacon(entry: Entry, egg: any, pos: Vector3): BasePart
	local tier = entry.special :: string
	local h = specialHeight(tier)
	local color = UiKit.RarityColor(tier)
	local beam = makePart({
		Name = "EggBeacon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, SPECIAL_BEACON_WIDTH, SPECIAL_BEACON_WIDTH),
		CFrame = specialBeaconCFrame(pos, tier),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	})
	beam:SetAttribute("Special", tier)
	local halo = makePart({
		Name = "BeaconHalo",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, SPECIAL_HALO_WIDTH, SPECIAL_HALO_WIDTH),
		CFrame = specialBeaconCFrame(pos, tier),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.86,
	})
	halo.Parent = beam
	local ring = makePart({
		Name = "EggRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, SPECIAL_RING_SIZE, SPECIAL_RING_SIZE),
		CFrame = ringCFrame(pos),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.7,
	})
	ring.Parent = beam
	-- 멀리서도 보이는 간판 (픽셀 크기)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BeaconSign"
	gui.Size = UDim2.fromOffset(270, 72)
	gui.StudsOffsetWorldSpace = Vector3.new(0, h / 2 + 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 900
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.62)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "🌟 " .. egg.Name .. "!"
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(40, 30, 60)
	label.Parent = gui
	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromScale(0.1, 0.62)
	info.Size = UDim2.fromScale(0.8, 0.38)
	info.Font = Enum.Font.FredokaOne
	info.TextScaled = true
	info.Text = UiKit.SpecialStars(tier) .. " " .. UiKit.RarityName(tier) .. " · " .. leftText(timeLeft(entry, clockNow()))
	info.TextColor3 = Color3.fromRGB(255, 250, 240)
	info.TextStrokeTransparency = 0.1
	info.TextStrokeColor3 = Color3.fromRGB(40, 30, 60)
	info.Parent = gui
	gui.Parent = beam
	beam.Parent = getFolder()
	entry.halo = halo
	entry.ring = ring
	entry.signInfo = info
	return beam
end

local function makeBeacon(egg: any, pos: Vector3): BasePart
	local h = CV.BeaconHeight
	local color = Config.Rarities[egg.Rarity].Color
	local beam = makePart({
		Name = "EggBeacon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, BEACON_WIDTH, BEACON_WIDTH),
		CFrame = beaconCFrame(pos),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "BeaconSign"
	gui.Size = UDim2.fromOffset(230, 56) -- 픽셀 크기: 멀리서도 똑같이 크게
	gui.StudsOffsetWorldSpace = Vector3.new(0, h / 2 + 3, 0) -- 기둥 꼭대기 (월드 좌표 위쪽)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 700
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "✨ " .. egg.Name .. "!"
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(40, 30, 60)
	label.Parent = gui
	gui.Parent = beam
	beam.Parent = getFolder()
	return beam
end

-- 잠깐 반짝 터지는 효과 (보이지 않는 파트 + 파티클 한 번)
local function poofAt(pos: Vector3, color: Color3)
	local p = makePart({
		Name = "EggPoof",
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(pos),
	})
	p.Parent = getFolder()
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.LightEmission = 0.7
	e.Size = NumberSequence.new(0.9, 0)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(6, 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(24)
	task.delay(1.5, function()
		p:Destroy()
	end)
end

----------------------------------------------------------------------
-- 알 모델
----------------------------------------------------------------------

local function dropModel(entry: Entry)
	local model = entry.model
	entry.model = nil
	entry.main = nil
	entry.prompt = nil
	entry.infoTimer = nil
	entry.highlight = nil
	if model then
		model:Destroy()
	end
end

local function dropBeacon(entry: Entry)
	local beacon = entry.beacon
	entry.beacon = nil
	entry.halo = nil
	entry.ring = nil
	entry.signInfo = nil
	if beacon then
		beacon:Destroy() -- 둘레 빛·빛 고리·간판은 기둥 안에 있어서 같이 없어져요
	end
end

local function removeEntry(uid: number)
	local entry = entries[uid]
	if not entry then
		return
	end
	entries[uid] = nil
	dropModel(entry)
	dropBeacon(entry)
	if entry.special then
		notifySpecial()
	end
end

local function tryBuy(entry: Entry)
	if entry.flying or entries[entry.uid] ~= entry then
		return
	end
	local now = os.clock()
	if now - entry.promptAt < PROMPT_COOLDOWN then
		return
	end
	entry.promptAt = now
	local prompt = entry.prompt
	if prompt then
		-- 서버 답을 기다리는 동안 잠깐 꺼요 (못 사면 다시 켜져요)
		prompt.Enabled = false
		task.delay(PROMPT_COOLDOWN, function()
			if entry.prompt == prompt and not entry.flying then
				local _, phase = eggSpot(entry, clockNow() - entry.born)
				prompt.Enabled = phase <= 2
			end
		end)
	end
	Remotes.BuyEgg:FireServer(entry.uid)
end

local function buildModel(entry: Entry)
	if entry.model then
		return
	end
	local egg = Config.Eggs[entry.eggId]
	local model = buildEggModel(entry.eggId)
	model.Name = "BeltEgg_" .. entry.eggId
	model:SetAttribute("EggId", entry.eggId)
	model:SetAttribute("EggUid", entry.uid)
	model:SetAttribute("Price", egg.Price)
	model:SetAttribute("Zone", entry.zone)
	local main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not main then
		model:Destroy()
		return
	end
	-- 몸통만 앵커 (나머지는 용접으로 따라와요). 매 프레임 몸통 CFrame 하나만 움직여요
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == main
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	if Config.Rarities[egg.Rarity].Order >= 4 then
		pcall(PetModels.AddRarityEffects, model, egg.Rarity)
	end
	if egg.Premium or entry.special then
		addPremiumGlow(main, egg)
	end
	if entry.special then
		-- ★v6 은은한 단계 색 테두리 (벽 뒤에서는 안 보여요)
		local hl = Instance.new("Highlight")
		hl.Name = "SpecialOutline"
		hl.Adornee = model
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillTransparency = 0.85
		hl.FillColor = UiKit.RarityColor(entry.special)
		hl.OutlineColor = UiKit.RarityColor(entry.special)
		hl.OutlineTransparency = 0.25
		hl.Parent = model
		entry.highlight = hl
	end
	makeBillboard(main, egg, entry)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "구매 💰" .. Config.FormatNumber(egg.Price)
	prompt.ObjectText = egg.Name
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("PromptKind", "Buy")
	prompt:SetAttribute("EggUid", entry.uid)
	prompt.Triggered:Connect(function()
		tryBuy(entry)
	end)
	prompt.Parent = main

	entry.offset = model:GetPivot():ToObjectSpace(main.CFrame)
	entry.model = model
	entry.main = main
	entry.prompt = prompt
	local pos, phase = eggSpot(entry, clockNow() - entry.born)
	prompt.Enabled = phase <= 2
	model:PivotTo(CFrame.new(pos) * rotOf(entry.zone))
	model.Parent = getFolder()
end

-- 산 알: 모델만 남기고 (간판·프롬프트·빛기둥 없이) 집으로 날아가요
local function onBought(raw: any)
	if type(raw) ~= "table" or type(raw.Uid) ~= "number" then
		return
	end
	local entry = entries[raw.Uid]
	if not entry or entry.flying then
		return
	end
	local egg = Config.Eggs[entry.eggId]
	local color = Config.Rarities[egg.Rarity].Color
	local target: CFrame? = if typeof(raw.Target) == "CFrame" then raw.Target else nil
	local flyTime = tonumber(raw.FlyTime) or 0
	dropBeacon(entry)
	local model = entry.model
	if not model or not target or raw.Poof == true or flyTime <= 0 or flyTime ~= flyTime then
		-- 뿅! (멀리 있는 집이거나 모델이 없을 때)
		local pos = eggSpot(entry, clockNow() - entry.born)
		if model then
			pos = model:GetPivot().Position
		end
		poofAt(pos + Vector3.new(0, 1.5, 0), color)
		if target then
			poofAt(target.Position + Vector3.new(0, 1.5, 0), color)
		end
		removeEntry(entry.uid)
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	entry.prompt = nil
	entry.infoTimer = nil
	entry.flying = true
	entry.flyFrom = model:GetPivot().Position
	entry.flyTo = target
	entry.flyStart = os.clock()
	entry.flyTime = math.max(0.1, flyTime)
	if entry.special then
		poofAt(entry.flyFrom + Vector3.new(0, 1.5, 0), color)
		notifySpecial() -- 산 희귀 알은 이제 벨트에 없어요 (지도 🌟 표시 끄기)
	end
end

----------------------------------------------------------------------
-- 서버 이벤트
----------------------------------------------------------------------

local function addEgg(raw: any)
	if type(raw) ~= "table" then
		return
	end
	local uid, eggId, zone, born = raw.Uid, raw.EggId, raw.Zone, raw.Born
	if type(uid) ~= "number" or type(eggId) ~= "string" or type(zone) ~= "number" or type(born) ~= "number" then
		return
	end
	local egg = Config.Eggs[eggId]
	if not egg or not Config.Zones[zone] or born ~= born then
		return
	end
	local life = eggLife(eggId)
	if clockNow() - born > life then
		return -- 이미 다 지나갔어요
	end
	removeEntry(uid)
	local entry: Entry = {
		uid = uid,
		eggId = eggId,
		zone = zone,
		born = born,
		wobble = (uid * 1.37) % 10,
		model = nil,
		main = nil,
		offset = CFrame.identity,
		prompt = nil,
		beacon = nil,
		special = UiKit.EggSpecial(eggId),
		life = life,
		halo = nil,
		ring = nil,
		signInfo = nil,
		infoTimer = nil,
		highlight = nil,
		promptAt = -math.huge,
		flying = false,
		flyFrom = Vector3.zero,
		flyTo = CFrame.identity,
		flyStart = 0,
		flyTime = 1,
	}
	entries[uid] = entry
	if entry.special then
		local pos = eggSpot(entry, clockNow() - born)
		entry.beacon = makeSpecialBeacon(entry, egg, pos)
		notifySpecial()
	elseif egg.Premium then
		local pos = eggSpot(entry, clockNow() - born)
		entry.beacon = makeBeacon(egg, pos)
	end
end

local function resetEggs(list: any)
	for uid in entries do
		removeEntry(uid)
	end
	table.clear(entries)
	if type(list) ~= "table" then
		return
	end
	for _, raw in list do
		addEgg(raw)
	end
end

-- 희귀 알 남은 시간 글자 (0.3초마다)
local function refreshSpecialText(entry: Entry, now: number)
	local left = leftText(timeLeft(entry, now))
	local sign = entry.signInfo
	if sign then
		local text = UiKit.SpecialStars(entry.special) .. " " .. UiKit.RarityName(entry.special) .. " · " .. left
		if sign.Text ~= text then
			sign.Text = text
		end
	end
	local info = entry.infoTimer
	if info then
		local text = UiKit.SpecialStars(entry.special) .. " " .. UiKit.RarityName(entry.special) .. " · " .. left
		if info.Text ~= text then
			info.Text = text
		end
	end
end

----------------------------------------------------------------------
-- 보이기/숨기기 + 매 프레임 움직이기
----------------------------------------------------------------------

local function cullCheck()
	local view = viewPosition()
	local now = clockNow()
	local r2 = CV.RenderDistance * CV.RenderDistance
	local builds = 0
	for uid, entry in entries do
		if entry.flying then
			continue
		end
		local pos, phase = eggSpot(entry, now - entry.born)
		if phase >= 4 then
			removeEntry(uid)
			continue
		end
		if entry.special then
			refreshSpecialText(entry, now)
		end
		local want = false
		if view then
			local dx, dz = pos.X - view.X, pos.Z - view.Z
			want = dx * dx + dz * dz <= r2
		end
		if want and not entry.model and builds < BUILDS_PER_CULL then
			builds += 1
			buildModel(entry)
		elseif not want and entry.model then
			dropModel(entry)
		end
	end
end

local function render()
	local now = clockNow()
	local t = os.clock()
	table.clear(moveParts)
	table.clear(moveCFrames)
	local recolor = t - lastColorAt >= SPECIAL_COLOR_STEP
	if recolor then
		lastColorAt = t
	end
	for uid, entry in entries do
		local main = entry.main
		if entry.flying then
			local model = entry.model
			local a = math.clamp((t - entry.flyStart) / entry.flyTime, 0, 1)
			if not model or not main or a >= 1 then
				removeEntry(uid)
				continue
			end
			-- 포물선으로 집 받침대까지 (빙글빙글)
			local p0, p2 = entry.flyFrom, entry.flyTo.Position
			local dist = (p2 - p0).Magnitude
			local p1 = (p0 + p2) / 2 + Vector3.new(0, math.max(FLY_ARC_MIN, dist * 0.35), 0)
			local u = 1 - a
			local pos = p0 * (u * u) + p1 * (2 * u * a) + p2 * (a * a)
			local rot = entry.flyTo.Rotation * CFrame.Angles(0, (1 - a) * math.pi * 4, 0)
			table.insert(moveParts, main)
			table.insert(moveCFrames, CFrame.new(pos) * rot * entry.offset)
			continue
		end
		local pos, phase = eggSpot(entry, now - entry.born)
		if phase >= 4 then
			removeEntry(uid)
			continue
		end
		if main then
			if phase >= 3 and entry.prompt and entry.prompt.Enabled then
				entry.prompt.Enabled = false -- 통으로 떨어지는 중에는 못 사요
			end
			local w = entry.wobble
			local wobble = CFrame.Angles(0, t * 0.8 + w, 0) * CFrame.Angles(math.sin(t * 5 + w) * 0.07, 0, math.sin(t * 4 + w) * 0.1)
			table.insert(moveParts, main)
			table.insert(moveCFrames, CFrame.new(pos) * rotOf(entry.zone) * wobble * entry.offset)
		end
		local beacon = entry.beacon
		local tier = entry.special
		if beacon and tier then
			local bcf = specialBeaconCFrame(pos, tier)
			table.insert(moveParts, beacon)
			table.insert(moveCFrames, bcf)
			local halo, ring = entry.halo, entry.ring
			if halo then
				table.insert(moveParts, halo)
				table.insert(moveCFrames, bcf)
			end
			if ring then
				table.insert(moveParts, ring)
				table.insert(moveCFrames, ringCFrame(pos))
			end
			if recolor then
				-- 단계 색이 천천히 돌아요 (기둥·둘레·고리·테두리가 조금씩 다른 자리)
				local base = (t / SPECIAL_CYCLE) + entry.wobble * 0.1
				beacon.Color = cycleColor(tier, base)
				if halo then
					halo.Color = cycleColor(tier, base + 0.15)
				end
				if ring then
					ring.Color = cycleColor(tier, base + 0.3)
				end
				local hl = entry.highlight
				if hl then
					hl.OutlineColor = cycleColor(tier, base + 0.3)
				end
			end
		elseif beacon then
			table.insert(moveParts, beacon)
			table.insert(moveCFrames, beaconCFrame(pos))
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

-- 내 벨트 알 수 / 모델로 그린 수 / 빛기둥 수 (디버그·테스트용)
function EggBelt.Counts(): (number, number, number)
	local n, models, beacons = 0, 0, 0
	for _, entry in entries do
		n += 1
		if entry.model then
			models += 1
		end
		if entry.beacon then
			beacons += 1
		end
	end
	return n, models, beacons
end

-- 지금 벨트 위 내 알 (uid → { EggId, Zone, Born, Model })
function EggBelt.Eggs(): { [number]: { EggId: string, Zone: number, Born: number, Model: Model? } }
	local out = {}
	for uid, entry in entries do
		out[uid] = { EggId = entry.eggId, Zone = entry.zone, Born = entry.born, Model = entry.model }
	end
	return out
end

-- ★v6 지금 벨트 위 내 희귀 알 (남은 시간 = 아직 살 수 있는 초)
function EggBelt.Specials(): { { Uid: number, EggId: string, Zone: number, Tier: string, Left: number } }
	local out = {}
	local now = clockNow()
	for uid, entry in entries do
		if entry.special and not entry.flying then
			table.insert(out, { Uid = uid, EggId = entry.eggId, Zone = entry.zone, Tier = entry.special, Left = timeLeft(entry, now) })
		end
	end
	table.sort(out, function(a, b)
		return a.Uid < b.Uid
	end)
	return out
end

-- ★v6 지역마다 내 희귀 알 가장 높은 단계 ({ [지역] = "Eternal" ... })
function EggBelt.SpecialZones(): { [number]: string }
	local out: { [number]: string } = {}
	for _, s in EggBelt.Specials() do
		local cur = out[s.Zone]
		if not cur or UiKit.SpecialRank(s.Tier) > UiKit.SpecialRank(cur) then
			out[s.Zone] = s.Tier
		end
	end
	return out
end

-- ★v6 그 지역 벨트에 이 알이 있나: (uid, 남은 초). 여러 개면 가장 늦게 나온 것
function EggBelt.Find(zone: number, eggId: string): (number?, number?)
	local best: Entry? = nil
	for _, entry in entries do
		if entry.zone == zone and entry.eggId == eggId and not entry.flying then
			if not best or entry.born > best.born then
				best = entry
			end
		end
	end
	if best then
		return best.uid, timeLeft(best, clockNow())
	end
	return nil, nil
end

-- ★v6 그 알을 아직 살 수 있으면 남은 초, 없어졌거나 샀으면 nil
function EggBelt.TimeLeft(uid: number): number?
	local entry = entries[uid]
	if not entry or entry.flying then
		return nil
	end
	local now = clockNow()
	local _, phase = eggSpot(entry, now - entry.born)
	if phase >= 3 then
		return nil
	end
	return timeLeft(entry, now)
end

-- ★v6 희귀 알이 생기거나 없어질 때 부르기. 돌려주는 함수를 부르면 그만 받아요
function EggBelt.OnSpecialChanged(fn: () -> ()): () -> ()
	table.insert(specialListeners, fn)
	return function()
		local i = table.find(specialListeners, fn)
		if i then
			table.remove(specialListeners, i)
		end
	end
end

function EggBelt.Init()
	if initialized then
		return
	end
	initialized = true
	getFolder()

	Remotes.EggBelt.OnClientEvent:Connect(function(op: any, arg: any)
		if op == "Reset" then
			resetEggs(arg)
		elseif op == "Add" then
			addEgg(arg)
		elseif op == "Remove" then
			if type(arg) == "number" then
				removeEntry(arg)
			end
		elseif op == "Bought" then
			onBought(arg)
		end
		cullCheck()
	end)

	RunService.RenderStepped:Connect(render)

	task.spawn(function()
		while true do
			task.wait(CULL_INTERVAL)
			local ok, err = pcall(cullCheck)
			if not ok then
				warn("[EggBelt] 알 그리기 오류:", err)
			end
		end
	end)
end

return EggBelt
