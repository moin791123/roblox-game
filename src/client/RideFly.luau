-- 펫 타고 날기 ✈ (클라이언트). 타는 펫에 올라탄 동안 (플레이어 속성 Riding = true, FollowService 가 정해요) 하늘을 날아요.
-- PC: 스페이스 꾹 = 날아오르기 / 올라가기, Q (또는 Ctrl) = 내려가기, F = 날기 ↔ 착륙, WASD = 이동. 아래 구석에 작은 안내 버튼 (왼쪽, 막히면 오른쪽).
-- 폰: 점프 버튼 왼쪽에 ✈ 버튼 (점프를 꾹 눌러도 날아요). 나는 동안 ⬆ / ⬇ 와 🛬 착륙 버튼. 타고 있을 때만 보여요.
-- 물리: HumanoidRootPart 에 LinearVelocity(속도) + AlignOrientation(똑바로 서서 좌우로만 돌기) + Humanoid.PlatformStand.
-- 땅까지 내려가면 / 펫에서 내리면(살살 내려와요) / 죽으면 / 순간이동하면 / 의자에 앉으면 원래대로. 카메라는 안 건드려요.
-- 한계: 높이 MAX_Y, 맵 밖(섬 둘레 + 여백), 바다 아래, 잠긴 지역 섬과 잠긴 길(문 너머)은 못 가요 (서버 ZoneService 도 XZ 로 다시 봐요).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer

local RideFly = {}

-- 움직임 (스터드 / 초)
local RISE_SPEED = 20 -- 올라가기
local DESCEND_SPEED = 24 -- 내려가기 / 착륙
local GLIDE_SPEED = 26 -- 펫에서 내린 뒤 살살 내려오기
local FLY_SPEED_FALLBACK = 1.2 -- 서버 FlySpeed 가 없으면 WalkSpeed × 이만큼
local H_ACCEL = 5 -- 앞뒤옆 부드럽게 (클수록 빨리 따라가요)
local V_ACCEL = 5 -- 위아래 부드럽게
local TURN_RESPONSIVENESS = 14 -- 몸 돌리기 (좌우로만)
local FORCE_G = 6 -- 미는 힘 최대 = 몸무게 × 중력 × 이만큼
local BOB_AMP = 0.35 -- 가만히 떠 있을 때 둥실둥실 (스터드)
local BOB_FREQ = 1.8
local TAKEOFF_HOLD = 0.35 -- 점프를 이만큼 꾹 누르면 날아올라요
local TAKEOFF_TIME = 0.5 -- 날기 시작하면 이만큼 저절로 올라가요
-- 한계
local MAX_Y = 150 -- 가장 높이 (땅 = 0, 10층 집 지붕 ≈ 135)
local SEA_FLOOR_Y = Config.Layout.SeaY + 1 -- 바다 위에서는 발이 이보다 아래로 안 내려가요
local WORLD_MARGIN = 40 -- 섬 바깥 바다 여백
local LOOKAHEAD = 2.5 -- 잠긴 곳/맵 끝 앞에서 멈추는 거리
local TRAIL_HALF = 12 -- 잠긴 길 폭 절반 (문 폭 20 / 2 + 2)
local TRAIL_BEFORE = 0.5 -- 잠긴 길은 문보다 살짝 앞에서부터
local SOFT_FLOOR = 3 -- 땅이 이만큼 가까워지면 천천히
local LAND_GAP = 0.6 -- 이만큼 가까우면 착지
local RAY_LENGTH = 400
local TELEPORT_JUMP = 30 -- 한 번에 이보다 멀리 옮겨지면 순간이동 → 날기 끝
local GLIDE_MAX_TIME = 10 -- 살살 내려오기 최대 시간
local LOCK_NOTIFY_GAP = 3
local UI_TICK = 0.2

type Fly = {
	char: Model,
	hrp: BasePart,
	hum: Humanoid,
	att: Attachment,
	lv: LinearVelocity,
	ao: AlignOrientation,
	vel: Vector3,
	yaw: number,
	mode: string, -- "fly" | "land" (착륙 중) | "glide" (펫에서 내려서 내려오는 중)
	takeoffUntil: number,
	glideUntil: number,
	lastPos: Vector3,
	track: AnimationTrack?,
}
type Box = { MinX: number, MaxX: number, MinZ: number, MaxZ: number, Zone: number }

local fly: Fly? = nil
local initialized = false
local stepConn: RBXScriptConnection? = nil
local charConns: { RBXScriptConnection } = {}
local holdTime = 0
local uiClock = 0
local lastLockNotify = -100
local toldOnce = false
local decorateMod: any = nil
local decorateTried = false

-- 잠긴 곳 상자 (섬 + 길) 와 맵 끝
local lockBoxes: { Box } = {}
local world = { MinX = -math.huge, MaxX = math.huge, MinZ = -math.huge, MaxZ = math.huge }

-- 화면
local gui: Instance? = nil
local root: Frame? = nil
local flyBtn: TextButton? = nil -- 폰: ✈ 날기
local upBtn: TextButton? = nil -- 폰: ⬆
local downBtn: TextButton? = nil -- 폰: ⬇
local landBtn: TextButton? = nil -- 폰: 🛬
local pcBtn: TextButton? = nil -- PC: ✈ 날기 (F) / 🛬 착륙 (F)
local pcMain: TextLabel? = nil
local pcSub: TextLabel? = nil
local holds: { [string]: InputObject? } = {}
local shownRect: UiKit.Rect? = nil

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------

local function aliveChar(): (Model?, BasePart?, Humanoid?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char and hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
		return char, hrp, hum
	end
	return nil, nil, nil
end

-- 타는 펫이 붙어 있나 (서버 속성 Riding. 예전 서버면 타는 펫 모델로)
local function canFly(): boolean
	local v = player:GetAttribute("Riding")
	if v ~= nil then
		return v == true
	end
	local pets = workspace:FindFirstChild("FollowPets")
	return pets ~= nil and pets:FindFirstChild("RideMount_" .. tostring(player.UserId)) ~= nil
end

local function decorating(): boolean
	if not decorateTried then
		decorateTried = true
		local mod = script.Parent:FindFirstChild("DecorateMode")
		if mod and mod:IsA("ModuleScript") then
			local ok, result = pcall(require, mod)
			if ok then
				decorateMod = result
			end
		end
	end
	local m = decorateMod
	if type(m) == "table" and type(m.IsActive) == "function" then
		local ok, on = pcall(m.IsActive)
		return ok and on == true
	end
	return false
end

local function touchLayout(): boolean
	return UserInputService.TouchEnabled
end

local function rebirths(): number
	local ok, n = pcall(State.Rebirths)
	return if ok and type(n) == "number" then n else 0
end

local function keyHeld(a: Enum.KeyCode, b: Enum.KeyCode?): boolean
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	return UserInputService:IsKeyDown(a) or (b ~= nil and UserInputService:IsKeyDown(b))
end

local function held(key: string): boolean
	local io = holds[key]
	if not io then
		return false
	end
	local st = io.UserInputState
	if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
		holds[key] = nil
		return false
	end
	if io.UserInputType == Enum.UserInputType.MouseButton1 and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		holds[key] = nil
		return false
	end
	return true
end

-- 올라가기: 스페이스 / 점프 버튼 (Humanoid.Jump) / ⬆ 버튼
local function upHeld(hum: Humanoid): boolean
	return hum.Jump or held("up") or keyHeld(Enum.KeyCode.Space)
end

-- 내려가기: Q / Ctrl / ⬇ 버튼
local function downHeld(): boolean
	return held("down") or keyHeld(Enum.KeyCode.Q, Enum.KeyCode.LeftControl)
end

-- HumanoidRootPart 가운데에서 서 있는 땅까지 (FollowService.groundDepth 와 같은 식)
local function standDepth(hum: Humanoid, hrp: BasePart): number
	if hum.RigType == Enum.HumanoidRigType.R15 then
		return hum.HipHeight + hrp.Size.Y / 2
	end
	return 2 + hum.HipHeight + hrp.Size.Y / 2
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true
local rayFilter: { Instance } = {}

-- 발밑 땅 높이 (바다/허공이면 nil). 사람·펫·코인은 빼요
local function groundY(hrp: BasePart): number?
	table.clear(rayFilter)
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(rayFilter, p.Character)
		end
	end
	for _, name in { "FollowPets", "ClientCoins" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(rayFilter, f)
		end
	end
	rayParams.FilterDescendantsInstances = rayFilter
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -RAY_LENGTH, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

local function flySpeed(hum: Humanoid): number
	local s = tonumber(player:GetAttribute("FlySpeed"))
	if s and s > 0 then
		return s
	end
	return math.max(hum.WalkSpeed, 16) * FLY_SPEED_FALLBACK
end

----------------------------------------------------------------------
-- 잠긴 곳 / 맵 끝
----------------------------------------------------------------------

local function boxOf(points: { Vector3 }, zone: number): Box
	local b: Box = { MinX = math.huge, MaxX = -math.huge, MinZ = math.huge, MaxZ = -math.huge, Zone = zone }
	for _, p in points do
		b.MinX, b.MaxX = math.min(b.MinX, p.X), math.max(b.MaxX, p.X)
		b.MinZ, b.MaxZ = math.min(b.MinZ, p.Z), math.max(b.MaxZ, p.Z)
	end
	return b
end

local function buildBoxes()
	table.clear(lockBoxes)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i, z in Config.Zones do
		local h = z.Size / 2
		local island = boxOf({ z.Center - h, z.Center + h }, i)
		minX, maxX = math.min(minX, island.MinX), math.max(maxX, island.MaxX)
		minZ, maxZ = math.min(minZ, island.MinZ), math.max(maxZ, island.MaxZ)
		if (z.MinRebirth or 0) > 0 then
			table.insert(lockBoxes, island)
			local t = z.Trail
			if t then
				local a = t.From - t.Dir * TRAIL_BEFORE
				local s = t.Side * TRAIL_HALF
				table.insert(lockBoxes, boxOf({ a + s, a - s, t.To + s, t.To - s }, i))
			end
		end
	end
	if minX < maxX then
		world = { MinX = minX - WORLD_MARGIN, MaxX = maxX + WORLD_MARGIN, MinZ = minZ - WORLD_MARGIN, MaxZ = maxZ + WORLD_MARGIN }
	end
end

-- (x, z) 가 아직 못 가는 지역 섬/길 위면 그 지역 번호
local function lockedAt(x: number, z: number, reb: number): number?
	for _, b in lockBoxes do
		if x >= b.MinX and x <= b.MaxX and z >= b.MinZ and z <= b.MaxZ then
			local def = Config.Zones[b.Zone]
			if def and reb < (def.MinRebirth or 0) then
				return b.Zone
			end
		end
	end
	return nil
end

-- 앞뒤옆 속도를 막기: 맵 밖으로 / 잠긴 곳으로 가는 쪽만 0 (벽을 따라 미끄러져요)
local function guardMove(pos: Vector3, v: Vector3, dt: number): (Vector3, number?)
	local vx, vz = v.X, v.Z
	if vx == 0 and vz == 0 then
		return v, nil
	end
	local function ahead(c: number, vc: number): number
		if vc > 0 then
			return c + vc * dt * 2 + LOOKAHEAD
		elseif vc < 0 then
			return c + vc * dt * 2 - LOOKAHEAD
		end
		return c
	end
	local nx, nz = ahead(pos.X, vx), ahead(pos.Z, vz)
	if (nx < world.MinX and vx < 0) or (nx > world.MaxX and vx > 0) then
		vx = 0
	end
	if (nz < world.MinZ and vz < 0) or (nz > world.MaxZ and vz > 0) then
		vz = 0
	end
	local hit: number? = nil
	local reb = rebirths()
	-- 이미 잠긴 곳 안이면 안 막아요 (나가는 길. 서버가 곧 돌려보내요)
	if (vx ~= 0 or vz ~= 0) and lockedAt(pos.X, pos.Z, reb) == nil then
		nx, nz = ahead(pos.X, vx), ahead(pos.Z, vz)
		local both = lockedAt(nx, nz, reb)
		if both then
			local kx = if vx ~= 0 then lockedAt(nx, pos.Z, reb) else nil
			local kz = if vz ~= 0 then lockedAt(pos.X, nz, reb) else nil
			if kx then
				vx = 0
			end
			if kz then
				vz = 0
			end
			if not kx and not kz then
				vx, vz = 0, 0 -- 모서리
			end
			hit = kx or kz or both
		end
	end
	return Vector3.new(vx, v.Y, vz), hit
end

local function notifyLocked(zone: number)
	local now = os.clock()
	if now - lastLockNotify < LOCK_NOTIFY_GAP then
		return
	end
	lastLockNotify = now
	local def = Config.Zones[zone]
	Toasts.Show("🔒 환생 " .. tostring(if def then def.MinRebirth else 0) .. "회가 필요해요!", "warn")
end

----------------------------------------------------------------------
-- 날기 시작 / 끝
----------------------------------------------------------------------

local refreshUi: () -> ()
local updateStepConn: () -> ()

local function playIdle(f: Fly)
	pcall(function()
		local animate = f.char:FindFirstChild("Animate")
		local idle = animate and animate:FindFirstChild("idle")
		local anim = idle and idle:FindFirstChildWhichIsA("Animation", true)
		local animator = f.hum:FindFirstChildOfClass("Animator")
		if anim and animator then
			local track = animator:LoadAnimation(anim :: Animation)
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Idle
			track:Play(0.3)
			f.track = track
		end
	end)
end

local function stopFlight(reason: string)
	local f = fly
	if not f then
		return
	end
	fly = nil
	holdTime = 0
	local track = f.track
	if track then
		pcall(function()
			track:Stop(0.2)
			track:Destroy()
		end)
	end
	f.lv:Destroy()
	f.ao:Destroy()
	f.att:Destroy()
	local hum = f.hum
	if hum.Parent and hum.Health > 0 then
		hum.PlatformStand = false
		if reason ~= "sit" then
			-- 살짝 떨어지며 착지 (높아도 안 다쳐요)
			pcall(function()
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
			end)
		end
	end
	if f.hrp.Parent then
		local v = f.hrp.AssemblyLinearVelocity
		f.hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, 0), v.Z)
	end
	updateStepConn()
	refreshUi()
end

local function startFlight(): boolean
	if fly or not canFly() or decorating() then
		return false
	end
	local char, hrp, hum = aliveChar()
	if not char or not hrp or not hum or hum.Sit then
		return false
	end
	local mass = 20
	pcall(function()
		mass = math.max(hrp.AssemblyMass, 5)
	end)
	local look = hrp.CFrame.LookVector
	local yaw = if Vector3.new(look.X, 0, look.Z).Magnitude > 0.1 then math.atan2(-look.X, -look.Z) else 0
	local att: Attachment = Make("Attachment", { Name = "RideFlyAttachment", Parent = hrp })
	local lv: LinearVelocity = Make("LinearVelocity", {
		Name = "RideFlyVelocity",
		Attachment0 = att,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		MaxForce = mass * workspace.Gravity * FORCE_G,
		VectorVelocity = Vector3.zero,
		Parent = hrp,
	})
	local ao: AlignOrientation = Make("AlignOrientation", {
		Name = "RideFlyAlign",
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		Attachment0 = att,
		MaxTorque = math.huge,
		Responsiveness = TURN_RESPONSIVENESS,
		CFrame = CFrame.Angles(0, yaw, 0),
		Parent = hrp,
	})
	local v0 = hrp.AssemblyLinearVelocity
	hum.PlatformStand = true
	local now = os.clock()
	local f: Fly = {
		char = char,
		hrp = hrp,
		hum = hum,
		att = att,
		lv = lv,
		ao = ao,
		vel = Vector3.new(v0.X, math.clamp(v0.Y, -8, RISE_SPEED), v0.Z),
		yaw = yaw,
		mode = "fly",
		takeoffUntil = now + TAKEOFF_TIME,
		glideUntil = 0,
		lastPos = hrp.Position,
		track = nil,
	}
	fly = f
	playIdle(f)
	updateStepConn()
	refreshUi()
	return true
end

-- F / 버튼: 날기 ↔ 착륙
local function toggleFly()
	local f = fly
	if not f then
		startFlight()
	elseif f.mode == "fly" then
		f.mode = "land"
		refreshUi()
	elseif f.mode == "land" then
		f.mode = "fly"
		refreshUi()
	end
end

----------------------------------------------------------------------
-- 매 프레임
----------------------------------------------------------------------

local function flyStep(f: Fly, dt: number)
	local char, hrp, hum = f.char, f.hrp, f.hum
	if player.Character ~= char or not hrp.Parent or not hum.Parent or hum.Health <= 0 then
		stopFlight("dead")
		return
	end
	if hum.Sit then
		stopFlight("sit")
		return
	end
	local now = os.clock()
	local pos = hrp.Position
	local speed = if f.mode == "glide" then math.max(hum.WalkSpeed, 8) else flySpeed(hum)
	if (pos - f.lastPos).Magnitude > TELEPORT_JUMP + speed * dt * 3 then
		stopFlight("teleport") -- 지도 / 집 / 엘리베이터 / 잠긴 곳에서 돌려보내기
		return
	end
	f.lastPos = pos
	if f.mode == "fly" and decorating() then
		f.mode = "land"
		refreshUi()
	end
	if f.mode == "glide" and now > f.glideUntil then
		stopFlight("glide")
		return
	end

	local up = upHeld(hum)
	local down = downHeld()
	if f.mode == "land" and up and not down then
		f.mode = "fly" -- 착륙 중에 올라가면 계속 날아요
		refreshUi()
	end
	local mode = f.mode

	-- 위아래
	local ground = groundY(hrp)
	local depth = standDepth(hum, hrp)
	local floorY = (if ground then ground else SEA_FLOOR_Y) + depth
	local gap = pos.Y - floorY
	local vy: number
	if mode == "fly" then
		if up and not down then
			vy = RISE_SPEED
		elseif down and not up then
			vy = -DESCEND_SPEED
		else
			vy = BOB_AMP * BOB_FREQ * math.cos(now * BOB_FREQ) -- 둥실둥실
		end
		if now < f.takeoffUntil and not down then
			vy = math.max(vy, RISE_SPEED)
		end
	else
		vy = -(if mode == "glide" then GLIDE_SPEED else DESCEND_SPEED)
	end
	if gap < SOFT_FLOOR and vy < 0 then
		vy = math.max(vy, -(math.max(gap, 0) * 4 + 1.5)) -- 땅/바다 가까이에서는 천천히
	end
	if gap < 0 then
		vy = math.max(vy, math.min(-gap * 6, RISE_SPEED)) -- 땅 밑으로는 안 들어가요
	end
	local top = MAX_Y - pos.Y
	if top < 6 and vy > 0 then
		vy = math.min(vy, math.max(top, 0) * 3) -- 천장 가까이에서는 천천히
	end
	if top < 0 then
		vy = math.min(vy, -4)
	end

	-- 착지: 땅 위에서 내려가다 닿으면 (바다 위에서는 펫에서 내렸을 때만 그냥 내려요)
	local gliding = mode == "glide"
	local landing = mode ~= "fly"
	if gap <= LAND_GAP and ((ground ~= nil and (down or landing)) or gliding) then
		stopFlight("land")
		return
	end

	-- 앞뒤옆 (카메라 기준 이동 방향 = Humanoid.MoveDirection)
	local md = hum.MoveDirection
	local flat = Vector3.new(md.X, 0, md.Z)
	if flat.Magnitude > 1 then
		flat = flat.Unit
	end
	local target = flat * speed
	local ah = 1 - math.exp(-H_ACCEL * dt)
	local av = 1 - math.exp(-V_ACCEL * dt)
	local vel = f.vel
	local nvy = vel.Y + (vy - vel.Y) * av
	if (top <= 0 and nvy > 0) or (gap < 0 and nvy < 0) then
		nvy = 0
	end
	local nv = Vector3.new(vel.X + (target.X - vel.X) * ah, nvy, vel.Z + (target.Z - vel.Z) * ah)
	local guarded, hitZone = guardMove(pos, nv, dt)
	f.vel = guarded
	f.lv.VectorVelocity = guarded
	if hitZone then
		notifyLocked(hitZone)
	end

	-- 몸 방향: 좌우로만 (기울지 않아요). 시프트 잠금/1인칭이면 카메라 쪽
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		local cam = workspace.CurrentCamera
		local lookV = if cam then cam.CFrame.LookVector else Vector3.zero
		if Vector3.new(lookV.X, 0, lookV.Z).Magnitude > 0.1 then
			f.yaw = math.atan2(-lookV.X, -lookV.Z)
		end
	elseif flat.Magnitude > 0.1 then
		f.yaw = math.atan2(-flat.X, -flat.Z)
	end
	f.ao.CFrame = CFrame.Angles(0, f.yaw, 0)
end

local function step(dt: number)
	local f = fly
	if f then
		local ok, err = pcall(flyStep, f, dt)
		if not ok then
			warn("[RideFly] 날기 오류:", err)
			pcall(stopFlight, "error") -- 매 프레임 오류가 나지 않게 날기를 끝내요
		end
	elseif canFly() and not decorating() then
		-- 타고 있을 때 점프를 꾹 → 날아올라요
		local _, _, hum = aliveChar()
		if hum and not hum.Sit and upHeld(hum) then
			holdTime += dt
			if holdTime >= TAKEOFF_HOLD then
				holdTime = 0
				startFlight()
			end
		else
			holdTime = 0
		end
	else
		holdTime = 0
	end
	uiClock += dt
	if uiClock >= UI_TICK then
		uiClock = 0
		refreshUi()
	end
end

updateStepConn = function()
	local need = fly ~= nil or canFly()
	if need and not stepConn then
		uiClock = 0
		stepConn = RunService.PreSimulation:Connect(step)
	elseif not need and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

----------------------------------------------------------------------
-- 화면 (폰: 점프 버튼 왼쪽 / PC: 아래 구석)
----------------------------------------------------------------------

local function windowOpen(): boolean
	local g = gui
	if not g then
		return false
	end
	for _, child in g:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and child:FindFirstChild("Header") then
			return true
		end
	end
	return false
end

-- 점프 버튼 자리 (메인 GUI 기준). 진짜 버튼이 있으면 그 자리, 없으면 Roblox 기본 자리
local function jumpRect(gw: number, gh: number): (number, number, number, number)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	local frame = tg and tg:FindFirstChild("TouchControlFrame")
	local jb = frame and frame:FindFirstChild("JumpButton")
	local g = gui
	if jb and jb:IsA("GuiObject") and jb.Visible and jb.AbsoluteSize.X > 0 and g and g:IsA("GuiBase2d") then
		local p = jb.AbsolutePosition - g.AbsolutePosition
		local s = jb.AbsoluteSize
		if p.X > gw * 0.5 and p.X + s.X <= gw + 1 and p.Y + s.Y <= gh + 1 then
			return p.X, p.Y, p.X + s.X, p.Y + s.Y
		end
	end
	if math.min(gw, gh) <= 500 then
		return gw - 95, gh - 90, gw - 25, gh - 20
	end
	return gw - 170, gh - 210, gw - 50, gh - 90
end

local function hitsAny(r: UiKit.Rect, list: { UiKit.Rect }): boolean
	for _, o in list do
		if UiKit.RectsHit(r, o) then
			return true
		end
	end
	return false
end

local function rectAt(x: number, y: number, w: number, h: number): UiKit.Rect
	return { X0 = x, Y0 = y, X1 = x + w, Y1 = y + h }
end

-- 화면 상자들 (메인 GUI 기준). 보이는 버튼만
local function computeRects(gw: number, gh: number, flyingNow: boolean): { [GuiObject]: UiKit.Rect }
	local out: { [GuiObject]: UiKit.Rect } = {}
	local avoid: { UiKit.Rect } = {}
	for _, o in UiKit.SideObstacles(gui) do
		if o.Tag ~= "Jump" and o.Tag ~= "RideFly" then -- 점프 버튼은 따로 재고, 내 버튼 틀은 빼요 (알림 줄은 이 틀을 비켜요)
			table.insert(avoid, o)
		end
	end
	if touchLayout() then
		local jx0, jy0, _, jy1 = jumpRect(gw, gh)
		local gap = 10
		local b = math.clamp(math.floor((jy1 - jy0) * 0.86 + 0.5), 56, 92)
		local topMin = 8
		local top = gui and (gui :: Instance):FindFirstChild("TopBar")
		if top and top:IsA("GuiObject") and top.Visible then
			topMin = top.AbsolutePosition.Y + top.AbsoluteSize.Y + 8
		end
		-- 위아래 두 칸이 안 들어가면 조금 작게
		if jy1 - 2 * b - gap < topMin then
			b = math.max(44, math.floor((jy1 - topMin - gap) / 2))
		end
		local colX = jx0 - gap - b
		local downY = jy1 - b
		local upY = downY - gap - b
		if not flyingNow then
			if flyBtn then
				out[flyBtn] = rectAt(colX, downY, b, b)
			end
		else
			if downBtn then
				out[downBtn] = rectAt(colX, downY, b, b)
			end
			-- ★v6 작은 폰: ⬆ 을 ⬇ 위에 쌓으면 그 위로 알림 줄(좋은 알 배너 ~114px)이 안 들어가요 → ⬇ 왼쪽에 한 줄로 (안 겹치면)
			local up = rectAt(colX, upY, b, b)
			local row = false
			if upY - topMin < 120 then
				local r = rectAt(colX - gap - b, downY, b, b)
				if r.X0 >= 8 and not hitsAny(r, avoid) then
					up, row = r, true
				end
			end
			if upBtn then
				out[upBtn] = up
			end
			if landBtn then
				local l = math.floor(b * 0.8)
				-- ⬇ (한 줄이면 ⬆) 왼쪽 (조이스틱·도움말과 안 겹치면) → 아니면 ⬆ 위
				local left = rectAt(up.X0 - gap - l, downY + math.floor((b - l) / 2), l, l)
				local above = rectAt(up.X0 + math.floor((b - l) / 2), (if row then downY else upY) - gap - l, l, l)
				out[landBtn] = if left.X0 >= 8 and not hitsAny(left, avoid) then left else above
			end
		end
	elseif pcBtn then
		local w, h = 200, 56
		-- 왼쪽 아래 → 왼쪽 큰 버튼 오른쪽 → 오른쪽 아래 중에 아무것도 안 가리는 첫 자리
		local tries = { rectAt(12, gh - 12 - h, w, h) }
		local sideX = 0
		for _, o in avoid do
			if o.Tag == "SideButtons" then
				sideX = math.max(sideX, o.X1)
			end
		end
		if sideX > 0 then
			table.insert(tries, rectAt(math.ceil(sideX + 8), gh - 12 - h, w, h))
		end
		table.insert(tries, rectAt(gw - 12 - w, gh - 12 - h, w, h))
		local pick = tries[1]
		for _, r in tries do
			if r.X0 >= 0 and r.X1 <= gw and not hitsAny(r, avoid) then
				pick = r
				break
			end
		end
		out[pcBtn] = pick
	end
	return out
end

local function layout(show: boolean, flyingNow: boolean)
	local r, g = root, gui
	if not r or not g or not g:IsA("GuiBase2d") then
		return
	end
	local gw, gh = g.AbsoluteSize.X, g.AbsoluteSize.Y
	local rects = if show and gw > 0 and gh > 0 then computeRects(gw, gh, flyingNow) else {}
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, q in rects do
		x0, y0 = math.min(x0, q.X0), math.min(y0, q.Y0)
		x1, y1 = math.max(x1, q.X1), math.max(y1, q.Y1)
	end
	for _, btn in { flyBtn, upBtn, downBtn, landBtn, pcBtn } do
		if btn then
			local q = rects[btn]
			btn.Visible = q ~= nil
			if q then
				local pos = UDim2.fromOffset(math.floor(q.X0 - x0), math.floor(q.Y0 - y0))
				local size = UDim2.fromOffset(math.floor(q.X1 - q.X0), math.floor(q.Y1 - q.Y0))
				if btn.Position ~= pos then
					btn.Position = pos
				end
				if btn.Size ~= size then
					btn.Size = size
				end
			end
		end
	end
	if x0 < x1 then
		local pos = UDim2.fromOffset(math.floor(x0), math.floor(y0))
		local size = UDim2.fromOffset(math.floor(x1 - x0), math.floor(y1 - y0))
		if r.Position ~= pos then
			r.Position = pos
		end
		if r.Size ~= size then
			r.Size = size
		end
		r.Visible = true
		shownRect = { X0 = x0, Y0 = y0, X1 = x1, Y1 = y1, Tag = "Fly" }
	else
		r.Visible = false
		shownRect = nil
	end
	-- 다른 화면(알림·배너)이 비킬 수 있게 알려 줘요
	UiKit.SetSideRect("Fly", shownRect)
end

refreshUi = function()
	local f = fly
	local flyingNow = f ~= nil and f.mode ~= "glide"
	local show = (canFly() or flyingNow) and not decorating() and not windowOpen() and aliveChar() ~= nil
	if not show then
		holds.up = nil
		holds.down = nil
	end
	local main, sub = pcMain, pcSub
	if main and sub then
		if not f then
			main.Text = "✈ 날기 (F)"
			sub.Text = "스페이스 꾹 눌러도 날아요"
		elseif f.mode == "land" then
			main.Text = "✈ 계속 날기 (F)"
			sub.Text = "🛬 내려가는 중..."
		else
			main.Text = "🛬 착륙 (F)"
			sub.Text = "⬆ 스페이스  ⬇ Q"
		end
	end
	local land = landBtn
	if land then
		local label = land:FindFirstChild("Glyph")
		if label and label:IsA("TextLabel") then
			label.Text = if f and f.mode == "land" then "✈" else "🛬"
		end
	end
	layout(show, flyingNow)
end

-- 꾹 누르는 동그란 버튼 (⬆ / ⬇)
local function holdButton(parent: Instance, name: string, glyph: string, color: Color3, key: string): TextButton
	local btn: TextButton = Make("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(60, 60),
		Visible = false,
		Active = true,
		Selectable = false,
		ZIndex = 3,
		Parent = parent,
	})
	UiKit.Corner(btn, UDim.new(0.5, 0))
	UiKit.Gradient(btn)
	UiKit.Stroke(btn, C.White, 3, true)
	UiKit.Label({
		Name = "Glyph",
		Text = glyph,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 4,
		Parent = btn,
	}, { Stroke = UiKit.Darken(color, 0.45), MaxText = 44 })
	local scale = UiKit.Scale(btn)
	btn.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			holds[key] = input
			scale.Scale = 0.9
		end
	end)
	btn.InputEnded:Connect(function(input: InputObject)
		if holds[key] == input then
			holds[key] = nil
		end
		scale.Scale = 1
	end)
	return btn
end

-- 누르는 동그란 버튼 (✈ 날기 / 🛬 착륙): 큰 그림 + 작은 글자
local function tapButton(parent: Instance, name: string, glyph: string, caption: string, color: Color3, onClick: () -> ()): TextButton
	local btn, label = UiKit.Button({ Name = name, Text = glyph, Color = color, Radius = UDim.new(0.5, 0), ZIndex = 3, Parent = parent, OnClick = onClick, TextSize = 40 })
	btn.Visible = false
	btn.Size = UDim2.fromOffset(60, 60)
	label.Name = "Glyph"
	if caption ~= "" then
		label.Position = UDim2.fromScale(0.5, 0.4)
		label.Size = UDim2.fromScale(0.6, 0.5)
		UiKit.Label({
			Name = "Caption",
			Text = caption,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.76),
			Size = UDim2.fromScale(0.86, 0.26),
			ZIndex = 4,
			Parent = btn,
		}, { Stroke = UiKit.Darken(color, 0.45), MaxText = 18 })
	end
	return btn
end

local function buildUi(parent: Instance)
	local frame: Frame = Make("Frame", {
		Name = "RideFly",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	})
	root = frame
	flyBtn = tapButton(frame, "Fly", "✈", "날기", C.Sky, function()
		startFlight()
	end)
	upBtn = holdButton(frame, "Up", "⬆", C.Mint, "up")
	downBtn = holdButton(frame, "Down", "⬇", C.Peach, "down")
	landBtn = tapButton(frame, "Land", "🛬", "", C.Lavender, toggleFly)
	-- PC: 글자 두 줄 알약
	local btn, label = UiKit.Button({ Name = "PcFly", Text = "✈ 날기 (F)", Color = C.Sky, Radius = UDim.new(0.5, 0), ZIndex = 3, Parent = frame, OnClick = toggleFly, TextSize = 26 })
	btn.Visible = false
	btn.Size = UDim2.fromOffset(200, 56)
	label.Name = "Main"
	label.Position = UDim2.fromScale(0.5, 0.36)
	label.Size = UDim2.fromScale(0.86, 0.46)
	pcMain = label
	pcSub = UiKit.Label({
		Name = "Sub",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.75),
		Size = UDim2.fromScale(0.86, 0.3),
		ZIndex = 4,
		Parent = btn,
	}, { Stroke = UiKit.Darken(C.Sky, 0.45), MaxText = 16 })
	pcBtn = btn
	if parent:IsA("GuiBase2d") then
		parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			refreshUi()
		end)
	end
end

----------------------------------------------------------------------
-- 캐릭터 / 속성
----------------------------------------------------------------------

local function clearCharConns()
	for _, c in charConns do
		c:Disconnect()
	end
	table.clear(charConns)
end

local function bindCharacter(char: Model)
	clearCharConns()
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if player.Character ~= char or not (hum and hum:IsA("Humanoid")) then
		return
	end
	table.insert(charConns, hum.Died:Connect(function()
		stopFlight("dead")
		refreshUi()
	end))
	refreshUi()
end

local function onRidingChanged()
	local riding = canFly()
	local f = fly
	if f then
		if not riding and f.mode ~= "glide" then
			-- 펫에서 내렸어요: 살살 내려와서 착지
			f.mode = "glide"
			f.glideUntil = os.clock() + GLIDE_MAX_TIME
		elseif riding and f.mode == "glide" then
			f.mode = "fly"
		end
	end
	if riding and not toldOnce then
		toldOnce = true
		Toasts.Show(if touchLayout() then "✈ 버튼을 누르면 하늘을 날아요!" else "✈ 스페이스 꾹 (또는 F) 로 날 수 있어요!", "info")
	end
	updateStepConn()
	refreshUi()
end

----------------------------------------------------------------------
-- 공개 API
----------------------------------------------------------------------

function RideFly.IsFlying(): boolean
	return fly ~= nil
end

-- 지금 나는 중인 모드 ("fly" | "land" | "glide"), 안 날면 nil
function RideFly.Mode(): string?
	local f = fly
	return if f then f.mode else nil
end

-- 지금 보이는 날기 버튼 상자 (메인 GUI 기준, 안 보이면 nil). UiKit.SideRect("Fly") 와 같아요
function RideFly.Rect(): UiKit.Rect?
	return shownRect
end

function RideFly.Init(mainGui: Instance?)
	if initialized then
		return
	end
	initialized = true
	buildBoxes()
	local parent: Instance? = mainGui
	if not parent then
		parent = Make("ScreenGui", {
			Name = "PetWorldFly",
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = player:WaitForChild("PlayerGui"),
		})
	end
	gui = parent
	buildUi(parent :: Instance)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.F and (fly or canFly()) and not decorating() then
			toggleFly()
		end
	end)
	player:GetAttributeChangedSignal("Riding"):Connect(onRidingChanged)
	player.CharacterAdded:Connect(function(char: Model)
		task.spawn(bindCharacter, char)
	end)
	player.CharacterRemoving:Connect(function()
		stopFlight("dead")
		clearCharConns()
		refreshUi()
	end)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	onRidingChanged()
end

return RideFly
