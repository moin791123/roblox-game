-- 월드 쪽 클라이언트 효과
--  · 내 것 아닌 프롬프트 숨기기 (PromptKind "Owner")
--  · 엘리베이터 프롬프트 (PromptAction "Elevator") → init.client 가 넣은 함수 (층 고르기 창)
--  · 집 받침대 펫 살랑살랑 (Bob = true 모델, 가까운 것만, 루프 하나로 Body CFrame 만 움직여요)
--  · 받침대 펫 빛·반짝이 살짝 줄이기 (한 방에 많이 모여 눈부시지 않게) + 멀리 있는 펫의 반짝이/빛 끄기 (LOD)
--  · 레인보우 등급(TierCycle) 색 돌리기: 가까운 받침대 펫 + 내가 데리고 다니는/탄/든 펫
--  · +코인 떠오르는 숫자
-- (들판 코인 그리기는 CoinField 모듈이 해요)
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local UiKit = require(script.Parent.UiKit)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer
local myId = player.UserId

local WorldFx = {}

local BOB_DISTANCE = 90 -- 이 거리 안의 펫만 살랑살랑
local LOD_DISTANCE = 70 -- 이보다 먼 펫은 반짝이·빛을 꺼요
local BOB_STEP = 1 / 30 -- 살랑살랑 갱신 간격 (초당 30번)
local SCAN_STEP = 0.25 -- 거리 다시 재는 간격
local CYCLE_STEP = 0.1 -- 레인보우 등급 색 돌리는 간격 (초당 10번)
local CYCLE_SPEED = 0.1 -- 레인보우 색이 한 바퀴 도는 속도 (바퀴/초 → 10초에 한 바퀴. 빠르면 정신없어요)
-- 받침대 펫은 한 층에 12마리씩 모여 있어서 빛·반짝이가 겹쳐 눈부셔요 → 조금만 줄여요 (등급·희귀도 효과 모두).
-- 데리고 다니는/탄/든 펫 (FollowPets) 과 부화 화면은 그대로라서 그쪽이 조금 더 반짝여요
local PED_LIGHT_MULT = 0.6 -- PointLight 밝기 배율
local PED_SPARKLE_MULT = 0.6 -- 반짝이 초당 개수 배율

----------------------------------------------------------------------
-- 프롬프트 필터: PromptKind "Owner" 는 주인한테만 보여요
----------------------------------------------------------------------
local hiddenByMe: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastWrite: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- 로컬에서 Enabled 를 바꿀 때 (내가 쓴 값은 Enabled 신호에서 무시. 신호가 지연(deferred)돼도 안전)
local function setLocal(p: ProximityPrompt, value: boolean)
	lastWrite[p] = value
	p.Enabled = value
end

local function applyPrompt(p: ProximityPrompt)
	if p:GetAttribute("PromptKind") ~= "Owner" then
		return
	end
	local owner = tonumber(p:GetAttribute("OwnerUserId"))
	local want = owner == myId
	if not want then
		-- 서버가 켜 둔 것만 숨겨요 (꺼져 있던 걸 숨김 처리하면 나중에 잘못 켜져요)
		if p.Enabled then
			hiddenByMe[p] = true
			setLocal(p, false)
		end
	elseif hiddenByMe[p] then
		-- 내가 숨긴 것만 다시 켜요 (서버가 끈 건 그대로)
		hiddenByMe[p] = nil
		setLocal(p, true)
	end
end

local function hookPrompt(p: ProximityPrompt)
	p.AttributeChanged:Connect(function()
		applyPrompt(p)
	end)
	p:GetPropertyChangedSignal("Enabled"):Connect(function()
		local cur = p.Enabled
		if lastWrite[p] == cur then
			return
		end
		lastWrite[p] = nil
		if cur then
			-- 서버가 켰어요: 나한테 안 보여야 하면 다시 숨김
			applyPrompt(p)
		else
			-- 서버가 껐어요: 이제 내가 숨긴 상태가 아님
			hiddenByMe[p] = nil
		end
	end)
	applyPrompt(p)
end

local function setupPrompts()
	for _, d in workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			hookPrompt(d)
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			hookPrompt(d)
		end
	end)
end

----------------------------------------------------------------------
-- 엘리베이터: 서버는 아무것도 안 하고, 내가 누르면 층 고르기 창을 열어요
----------------------------------------------------------------------
local elevatorHandler: ((floor: number?) -> ())? = nil

-- init.client 가 넣어요: fn(누른 엘리베이터의 층 또는 nil)
function WorldFx.OnElevator(fn: (floor: number?) -> ())
	elevatorHandler = fn
end

local function attr(inst: Instance?, name: string): any
	return if inst then inst:GetAttribute(name) else nil
end

local function setupElevator()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player then
			return
		end
		local part = prompt.Parent
		local action = attr(prompt, "PromptAction") or attr(part, "PromptAction")
		if action ~= "Elevator" then
			return
		end
		local owner = tonumber(attr(prompt, "OwnerUserId"))
		if owner ~= nil and owner ~= myId then
			return
		end
		local floor = tonumber(attr(prompt, "Floor")) or tonumber(attr(part, "Floor"))
		local fn = elevatorHandler
		if fn then
			fn(floor)
		end
	end)
end

----------------------------------------------------------------------
-- 받침대 펫 살랑살랑 + 멀리 있는 펫 효과 끄기
-- 서버는 Body 를 받침대 CFrame 에 고정(Anchored)만 하고 움직이지 않아요. 클라이언트에서만 Body 를
-- 위아래로 움직이고(나머지 파트는 용접돼 같이 움직여요), 서버가 CFrame 을 바꾸면 그 값을 새 기준으로 삼아요.
----------------------------------------------------------------------
type BobInfo = {
	Model: Model,
	Body: BasePart?,
	Base: CFrame?, -- 서버가 놓은 CFrame
	Last: CFrame?, -- 내가 마지막으로 쓴 CFrame (다르면 서버가 바꾼 것)
	Phase: number,
	Amp: number,
	Speed: number,
	Active: boolean,
	Effects: { Instance }?, -- 반짝이/빛 (처음 필요할 때 모아요)
	LodOff: { [Instance]: boolean }, -- 내가 끈 효과
	Far: boolean,
	CalmConn: RBXScriptConnection?, -- 나중에 붙는 효과도 줄이기
}

local tracked: { [Model]: BobInfo } = {}
local active: { BobInfo } = {}
local rng = Random.new()

-- 받침대 펫 빛·반짝이 한 번만 줄이기 (다시 track 돼도 두 번 줄지 않게)
local calmed: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function calmFx(d: Instance)
	if calmed[d] then
		return
	end
	if d:IsA("Light") then
		calmed[d] = true
		local l = d :: Light
		l.Brightness *= PED_LIGHT_MULT
	elseif d:IsA("ParticleEmitter") then
		calmed[d] = true
		local pe = d :: ParticleEmitter
		pe.Rate *= PED_SPARKLE_MULT
	end
end

local function findBody(model: Model): BasePart?
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		return body
	end
	return nil
end

local function stopBob(info: BobInfo)
	if not info.Active then
		return
	end
	info.Active = false
	local body = info.Body
	-- 내가 움직인 상태 그대로면 원래 자리로 (서버가 바꿨으면 손대지 않아요)
	if body and body.Parent and info.Base and info.Last and body.CFrame == info.Last then
		body.CFrame = info.Base
	end
	info.Last = nil
end

local function setFar(info: BobInfo, far: boolean)
	if info.Far == far then
		return
	end
	info.Far = far
	if far then
		local effects = info.Effects
		if not effects then
			effects = {}
			for _, d in info.Model:GetDescendants() do
				if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Sparkles") then
					table.insert(effects, d)
				end
			end
			info.Effects = effects
		end
		for _, e in effects do
			local fx = e :: any
			if e.Parent and fx.Enabled then
				fx.Enabled = false
				info.LodOff[e] = true
			end
		end
	else
		for e in info.LodOff do
			if e.Parent then
				(e :: any).Enabled = true
			end
		end
		table.clear(info.LodOff)
	end
end

local function untrack(model: Instance)
	local info = tracked[model :: Model]
	if not info then
		return
	end
	tracked[model :: Model] = nil
	if info.CalmConn then
		info.CalmConn:Disconnect()
		info.CalmConn = nil
	end
	stopBob(info)
	setFar(info, false)
end

local function track(model: Model)
	if tracked[model] then
		return
	end
	local uid = tostring(model:GetAttribute("ItemUid") or model.Name)
	local seed = 0
	for i = 1, #uid do
		seed = (seed * 31 + string.byte(uid, i)) % 100000
	end
	tracked[model] = {
		Model = model,
		Body = nil,
		Base = nil,
		Last = nil,
		Phase = (seed % 628) / 100, -- 펫마다 다른 박자
		Amp = 0,
		Speed = 2.1 + rng:NextNumber(0, 0.6),
		Active = false,
		Effects = nil,
		LodOff = {},
		Far = false,
		CalmConn = model.DescendantAdded:Connect(calmFx),
	}
	for _, d in model:GetDescendants() do
		calmFx(d)
	end
end

local function consider(child: Instance)
	if not child:IsA("Model") then
		return
	end
	local model = child :: Model
	if model:GetAttribute("Bob") == true then
		track(model)
	end
	-- 속성이 나중에 붙거나 빠져도
	model:GetAttributeChangedSignal("Bob"):Connect(function()
		if model:GetAttribute("Bob") == true and model.Parent then
			track(model)
		else
			untrack(model)
		end
	end)
end

local function watchItems(folder: Instance)
	for _, child in folder:GetChildren() do
		consider(child)
	end
	folder.ChildAdded:Connect(consider)
	folder.ChildRemoved:Connect(untrack)
end

local function watchPlot(plot: Instance)
	local items = plot:FindFirstChild("Items")
	if items then
		watchItems(items)
	end
	plot.ChildAdded:Connect(function(child)
		if child.Name == "Items" then
			watchItems(child)
		end
	end)
end

-- 거리 재기: 가까운 펫은 살랑살랑 목록에, 먼 펫은 효과 끄기
local function scan()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	table.clear(active)
	for model, info in tracked do
		if not model.Parent then
			untrack(model)
			continue
		end
		local body = info.Body
		if not body or not body.Parent then
			body = findBody(model)
			info.Body = body
			info.Active = false
			info.Last = nil
			if body then
				-- 큰 펫은 조금 더 크게 (최대 0.45 스터드)
				info.Amp = math.clamp(body.Size.Y * 0.12, 0.15, 0.45)
			end
		end
		if body then
			local pos = if info.Active and info.Base then info.Base.Position else body.Position
			local dist = (pos - eye).Magnitude
			local near = dist <= BOB_DISTANCE and body.Anchored
			if near then
				if not info.Active then
					info.Active = true
					info.Base = body.CFrame
					info.Last = nil
				end
				table.insert(active, info)
			else
				stopBob(info)
			end
			setFar(info, dist > LOD_DISTANCE)
		end
	end
end

local function step()
	local t = os.clock()
	for _, info in active do
		local body = info.Body
		if info.Active and body and body.Parent then
			local cur = body.CFrame
			if info.Last == nil or cur ~= info.Last then
				info.Base = cur -- 서버가 새로 놓았어요 (또는 처음)
			end
			local base = info.Base
			if base then
				local s = math.sin(t * info.Speed + info.Phase)
				local lift = info.Amp * (0.5 + 0.5 * s) -- 받침대 아래로는 안 내려가요
				local sway = math.sin(t * info.Speed * 0.5 + info.Phase) * 0.06
				body.CFrame = base * CFrame.new(0, lift, 0) * CFrame.Angles(0, sway, 0)
				info.Last = body.CFrame
			end
		end
	end
end

-- 내가 데리고 다니는/탄/든 펫 (workspace.FollowPets, OwnerUserId = 나) 중 레인보우 등급(TierCycle)
local ownCycle: { [Model]: boolean } = {}

local function considerOwn(child: Instance)
	if child:IsA("Model") and child:GetAttribute("TierCycle") == true and tonumber(child:GetAttribute("OwnerUserId")) == myId then
		ownCycle[child :: Model] = true
	end
end

local function watchFollowFolder(folder: Instance)
	for _, child in folder:GetChildren() do
		considerOwn(child)
	end
	folder.ChildAdded:Connect(considerOwn)
	folder.ChildRemoved:Connect(function(child)
		ownCycle[child :: Model] = nil
	end)
end

local function setupOwnCycle()
	local folder = workspace:FindFirstChild("FollowPets")
	if folder then
		watchFollowFolder(folder)
		return
	end
	-- 서버가 처음 펫을 데리고 다닐 때 폴더를 만들어요
	local conn: RBXScriptConnection? = nil
	conn = workspace.ChildAdded:Connect(function(child)
		if child.Name == "FollowPets" and child:IsA("Folder") then
			if conn then
				conn:Disconnect()
				conn = nil
			end
			watchFollowFolder(child)
		end
	end)
end

local function setupBob()
	setupOwnCycle()
	task.spawn(function()
		local plots = workspace:WaitForChild("Plots")
		for _, plot in plots:GetChildren() do
			watchPlot(plot)
		end
		plots.ChildAdded:Connect(watchPlot)
	end)
	local bobAcc, scanAcc, cycleAcc = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		-- 레인보우 등급(TierCycle) 펫은 가까운 것만 색이 천천히 돌아요
		cycleAcc += dt
		if cycleAcc >= CYCLE_STEP then
			cycleAcc = 0
			local pm = UiKit.PetModels
			if pm and pm.CycleTierColors then
				local phase = (os.clock() * CYCLE_SPEED) % 1
				for _, info in active do
					if info.Active and not info.Far and info.Model:GetAttribute("TierCycle") == true then
						pcall(pm.CycleTierColors, info.Model, phase)
					end
				end
				for model in ownCycle do
					if model.Parent then
						pcall(pm.CycleTierColors, model, phase)
					else
						ownCycle[model] = nil
					end
				end
			end
		end
		scanAcc += dt
		if scanAcc >= SCAN_STEP then
			scanAcc = 0
			scan()
		end
		bobAcc += dt
		if bobAcc >= BOB_STEP then
			bobAcc = 0
			step()
		end
	end)
end

----------------------------------------------------------------------
-- +코인 떠오르는 숫자
----------------------------------------------------------------------
local lastCoinSound = 0

function WorldFx.CoinFx(amount: any, position: any, silent: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	local n = tonumber(amount) or 0
	if n <= 0 then
		return
	end
	local att: Attachment = Make("Attachment", { Name = "CoinFx", Parent = workspace.Terrain })
	att.WorldPosition = position + Vector3.new(0, 2.5, 0)
	local bb: BillboardGui = Make("BillboardGui", {
		Size = UDim2.fromOffset(150, 52),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 150,
		Adornee = att,
		Parent = att,
	})
	local label = UiKit.Label({
		Text = "+" .. Config.FormatNumber(n) .. " 💰",
		TextColor3 = C.Lemon,
		Parent = bb,
	}, { Stroke = Color3.fromRGB(150, 85, 20), StrokeThickness = 3, MaxText = 40 })
	UiKit.Pop(label, 0.25)
	UiKit.Tween(att, 1.1, { Position = att.Position + Vector3.new(0, 4.5, 0) }, Enum.EasingStyle.Quad)
	task.delay(0.5, function()
		UiKit.Tween(label, 0.6, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			UiKit.Tween(stroke, 0.6, { Transparency = 1 })
		end
	end)
	Debris:AddItem(att, 1.3)

	-- 들판 코인은 자석에 끌릴 때 이미 소리를 냈으니(CoinField) 서버 확인 때는 숫자만
	if silent ~= true and os.clock() - lastCoinSound > 0.09 then
		lastCoinSound = os.clock()
		UiKit.PlaySound("Coin")
	end
end

function WorldFx.Init()
	setupPrompts()
	setupElevator()
	setupBob()
end

return WorldFx
