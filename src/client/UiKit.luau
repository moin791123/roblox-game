-- 귀여운 UI 도우미 모음 (색, 버튼, 창, 트윈, 소리, 뷰포트)
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

-- PetModels 는 다른 모듈이라 실패해도 UI 는 살아 있도록 pcall
local PetModels: any = nil
do
	local mod = Shared:WaitForChild("PetModels", 8)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			PetModels = result
		else
			warn("[UiKit] PetModels 불러오기 실패:", result)
		end
	else
		warn("[UiKit] PetModels 모듈을 찾지 못했어요 (이모지로 대신 보여줘요)")
	end
end

-- FurnitureModels 도 다른 모듈이라 처음 쓸 때 pcall 로 불러요 (없으면 이모지)
local FurnitureModels: any = nil
local furnitureTried = false
local function getFurnitureModels(): any
	if not furnitureTried then
		furnitureTried = true
		local mod = Shared:FindFirstChild("FurnitureModels")
		if mod and mod:IsA("ModuleScript") then
			local ok, result = pcall(require, mod)
			if ok then
				FurnitureModels = result
			else
				warn("[UiKit] FurnitureModels 불러오기 실패:", result)
			end
		end
	end
	return FurnitureModels
end

local UiKit = {}
UiKit.PetModels = PetModels -- 없으면 nil (WorldFx 무지개 색 돌리기 등)
UiKit.Config = Config
UiKit.Font = Enum.Font.FredokaOne

UiKit.Colors = {
	White = Color3.fromRGB(255, 255, 255),
	Cream = Color3.fromRGB(255, 248, 240),
	Ink = Color3.fromRGB(95, 60, 120), -- 글자 테두리용 보라
	Pink = Color3.fromRGB(255, 140, 190),
	Lemon = Color3.fromRGB(255, 210, 70),
	Mint = Color3.fromRGB(100, 210, 150),
	Sky = Color3.fromRGB(100, 175, 255),
	Lavender = Color3.fromRGB(175, 135, 255),
	Peach = Color3.fromRGB(255, 165, 115),
	Orange = Color3.fromRGB(255, 160, 60),
	Red = Color3.fromRGB(255, 90, 105),
	Grey = Color3.fromRGB(170, 170, 188),
	Gold = Color3.fromRGB(255, 195, 40),
}
local C = UiKit.Colors

function UiKit.Lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

function UiKit.Darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

-- Instance.new + 속성 한 번에
function UiKit.Make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst: any = Instance.new(className :: any)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local Make = UiKit.Make

function UiKit.Tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

function UiKit.Corner(parent: Instance, radius: UDim?): UICorner
	return Make("UICorner", { CornerRadius = radius or UDim.new(0, 16), Parent = parent })
end

-- border = true 면 테두리, 아니면 글자 외곽선
function UiKit.Stroke(parent: Instance, color: Color3, thickness: number?, border: boolean?): UIStroke
	return Make("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		ApplyStrokeMode = if border then Enum.ApplyStrokeMode.Border else Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

-- 배경색에 곱해지는 위->아래 그라데이션 (배경색을 바꿔도 그대로 예뻐요)
function UiKit.Gradient(parent: Instance, rotation: number?): UIGradient
	return Make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(212, 212, 222)),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

-- GuiObject 하나에 UIScale 하나만 (여러 효과가 같이 써요)
function UiKit.Scale(gui: Instance): UIScale
	local s = gui:FindFirstChild("FxScale")
	if s and s:IsA("UIScale") then
		return s
	end
	return Make("UIScale", { Name = "FxScale", Parent = gui })
end

function UiKit.Pop(gui: Instance, time: number?)
	local s = UiKit.Scale(gui)
	s.Scale = 0
	UiKit.Tween(s, time or 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

function UiKit.Bump(gui: Instance, amount: number?)
	local s = UiKit.Scale(gui)
	s.Scale = 1 + (amount or 0.15)
	UiKit.Tween(s, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- 좌우로 흔들기 (Rotation)
function UiKit.Shake(gui: GuiObject, strength: number?, times: number?)
	local st = strength or 8
	local n = times or 8
	task.spawn(function()
		for i = 1, n do
			if not gui.Parent then
				return
			end
			local a = (if i % 2 == 0 then 1 else -1) * st * (1 - (i - 1) / n)
			UiKit.Tween(gui, 0.05, { Rotation = a }, Enum.EasingStyle.Sine)
			task.wait(0.05)
		end
		if gui.Parent then
			UiKit.Tween(gui, 0.06, { Rotation = 0 })
		end
	end)
end

type LabelOpts = { Stroke: Color3?, StrokeThickness: number?, MaxText: number?, MinText: number? }

-- 흰 글씨 + 보라 외곽선 라벨 (TextScaled)
function UiKit.Label(props: { [string]: any }, opts: LabelOpts?): TextLabel
	local o: LabelOpts = opts or {}
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = UiKit.Font,
		TextColor3 = C.White,
		TextScaled = true,
		TextWrapped = true,
		Text = "",
		Size = UDim2.fromScale(1, 1),
	}
	for k, v in props do
		base[k] = v
	end
	local label = Make("TextLabel", base)
	UiKit.Stroke(label, o.Stroke or C.Ink, o.StrokeThickness or 2)
	Make("UITextSizeConstraint", { MaxTextSize = o.MaxText or 40, MinTextSize = o.MinText or 8, Parent = label })
	return label
end

local hoverEnabled = UserInputService.MouseEnabled

export type ButtonOpts = {
	Text: string?,
	Color: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	OnClick: (() -> ())?,
	TextSize: number?,
	Name: string?,
	LayoutOrder: number?,
	Radius: UDim?,
	ZIndex: number?,
	Sound: string?,
}

-- 통통 튀는 버튼. (버튼, 글자라벨) 반환
function UiKit.Button(opts: ButtonOpts): (TextButton, TextLabel)
	local color = opts.Color or C.Pink
	local btn: TextButton = Make("TextButton", {
		Name = opts.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Size = opts.Size or UDim2.fromScale(1, 1),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = opts.ZIndex or 1,
		Selectable = true,
	})
	UiKit.Corner(btn, opts.Radius or UDim.new(0.3, 0))
	UiKit.Gradient(btn)
	UiKit.Stroke(btn, C.White, 3, true)
	local label = UiKit.Label({
		Text = opts.Text or "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.88, 0.74),
		ZIndex = (opts.ZIndex or 1) + 1,
		Parent = btn,
	}, { Stroke = UiKit.Darken(color, 0.45), MaxText = opts.TextSize or 30 })

	local scale = UiKit.Scale(btn)
	local hovering = false
	btn.MouseEnter:Connect(function()
		if hoverEnabled then
			hovering = true
			UiKit.Tween(scale, 0.12, { Scale = 1.07 })
		end
	end)
	btn.MouseLeave:Connect(function()
		hovering = false
		UiKit.Tween(scale, 0.15, { Scale = 1 })
	end)
	btn.MouseButton1Down:Connect(function()
		UiKit.Tween(scale, 0.08, { Scale = 0.88 })
	end)
	btn.MouseButton1Up:Connect(function()
		UiKit.Tween(scale, 0.25, { Scale = if hovering then 1.07 else 1 }, Enum.EasingStyle.Back)
	end)
	btn.Activated:Connect(function()
		UiKit.PlaySound(opts.Sound or "Click")
		if not hovering then
			-- 터치: 살짝 튕기고 원래대로
			scale.Scale = 1.12
			UiKit.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		if opts.OnClick then
			opts.OnClick()
		end
	end)
	if opts.Parent then
		btn.Parent = opts.Parent
	end
	return btn, label
end

-- 소리
local soundCache: { [string]: Sound } = {}
function UiKit.PlaySound(key: string)
	local id = (Config.Sounds :: any)[key]
	if type(id) ~= "string" then
		return
	end
	local sound = soundCache[key]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "Ui_" .. key
		sound.SoundId = id
		sound.Volume = 0.6
		sound.Parent = SoundService
		soundCache[key] = sound
	end
	pcall(function()
		SoundService:PlayLocalSound(sound)
	end)
end

-- 아이템 정보: (이름, 희귀도 키, 희귀도 표)
function UiKit.ItemInfo(kind: string, id: string): (string?, string?, any)
	local def: any = if kind == "Egg" then Config.Eggs[id] else Config.Pets[id]
	if not def then
		return nil, nil, nil
	end
	return def.Name, def.Rarity, Config.Rarities[def.Rarity]
end

function UiKit.RarityColor(rarity: string?): Color3
	local r = rarity and (Config.Rarities :: any)[rarity]
	return if r then r.Color else C.Grey
end

-- 등급(1 기본 / 2 브론즈 / 3 실버 / 4 골드 / 5 레인보우 / 6 다이아 / 7 갤럭시) 강조색
function UiKit.TierColor(tier: number?): Color3
	local info = Config.TierInfo(tier)
	return if info and info.Color then info.Color else C.White
end

-- 등급 숫자 정리 (nil/이상한 값 → 1)
function UiKit.TierOf(tier: any): number
	return math.clamp(math.floor(tonumber(tier) or 1), 1, Config.MaxTier)
end

-- 등급 배지 이모지 ("🥉" "🥈" "🥇" "🌈" "💎" "🌌", 기본은 "")
function UiKit.TierEmoji(tier: any): string
	local label = Config.TierInfo(UiKit.TierOf(tier)).Label
	if type(label) ~= "string" or label == "" then
		return ""
	end
	return string.match(label, "^(%S+)") or ""
end

-- 등급 표시 글자 ("🥇 골드", 기본은 "")
function UiKit.TierLabel(tier: any): string
	local label = Config.TierInfo(UiKit.TierOf(tier)).Label
	return if type(label) == "string" then label else ""
end

-- 옷이 붙는 자리 아이콘 (Head 🎩 / Face 👓 / Neck 🎀 / Back 🎒)
local ACC_SLOT_ICON: { [string]: string } = { Head = "🎩", Face = "👓", Neck = "🎀", Back = "🎒" }
function UiKit.AccessoryIcon(slotOrAccId: string?): string
	if type(slotOrAccId) ~= "string" then
		return "👕"
	end
	local def = (Config.Accessories :: any)[slotOrAccId]
	local slot = if def then def.Slot else slotOrAccId
	return ACC_SLOT_ICON[slot] or "👕"
end

-- 옷 이름 (모르면 nil)
function UiKit.AccessoryName(accId: any): string?
	local def = if type(accId) == "string" then (Config.Accessories :: any)[accId] else nil
	return if def then def.Name else nil
end

-- 초당 수익 글자 (10 미만은 소수 1자리: 2.5, 그 위는 12K 같은 짧은 표기)
function UiKit.IncomeText(n: number): string
	local v = tonumber(n) or 0
	if v < 10 then
		local s = string.format("%.1f", math.floor(v * 10 + 0.5) / 10)
		return (s:gsub("%.0$", ""))
	end
	return Config.FormatNumber(v)
end

-- 한국어 조사 고르기: 받침이 있으면 withBatchim ("을", "이", "은"), 없으면 noBatchim ("를", "가", "는")
-- 예) UiKit.Josa("고양이", "을", "를") → "고양이를"
function UiKit.Josa(word: string, withBatchim: string, noBatchim: string): string
	local last: number? = nil
	for _, code in utf8.codes(word) do
		last = code
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 then
		return word .. (if (last - 0xAC00) % 28 ~= 0 then withBatchim else noBatchim)
	end
	return word .. withBatchim .. "(" .. noBatchim .. ")"
end

-- 두 번 눌러야 실행되는 버튼 (팔기·모두 빼기처럼 되돌리기 힘든 일).
-- 처음 누르면 confirmText + 빨간색으로 바뀌고, timeout(기본 2초) 안에 한 번 더 누르면 action 실행.
-- 돌려주는 click 을 버튼 OnClick 에서 부르세요. reset 은 원래대로 돌리기
function UiKit.TwoTap(button: GuiObject, label: TextLabel, confirmText: string, action: () -> (), timeout: number?): (() -> (), () -> ())
	local token = 0
	local armed = false
	local savedText = ""
	local savedColor = button.BackgroundColor3
	local function reset()
		if armed then
			armed = false
			token += 1
			if button.Parent then
				label.Text = savedText
				button.BackgroundColor3 = savedColor
			end
		end
	end
	local function click()
		if not armed then
			armed = true
			token += 1
			local my = token
			savedText = label.Text
			savedColor = button.BackgroundColor3
			label.Text = confirmText
			button.BackgroundColor3 = C.Red
			UiKit.Shake(button, 5, 6)
			task.delay(timeout or 2, function()
				if token == my then
					reset()
				end
			end)
			return
		end
		reset()
		action()
	end
	return click, reset
end

-- 둥근 알약 라벨 (배경색 + 흰 테두리 + 글자). (알약, 글자) 반환
function UiKit.Pill(parent: Instance?, text: string, color: Color3, props: { [string]: any }?, maxText: number?): (Frame, TextLabel)
	local base: { [string]: any } = {
		Name = "Pill",
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(120, 30),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local pill: Frame = Make("Frame", base)
	UiKit.Corner(pill, UDim.new(0.5, 0))
	UiKit.Gradient(pill)
	UiKit.Stroke(pill, C.White, 2, true)
	local label = UiKit.Label({
		Text = text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.88, 0.76),
		ZIndex = (base.ZIndex or 1) + 1,
		Parent = pill,
	}, { Stroke = UiKit.Darken(color, 0.45), MaxText = maxText or 20 })
	if parent then
		pill.Parent = parent
	end
	return pill, label
end

-- 펫/알/옷 뷰포트. kind = "Pet" | "Egg" | "Accessory". PetModels 가 없거나 실패하면 이모지로 대신.
-- tier 는 펫만 (등급 모습), accId 는 펫이 입은 옷 (없으면 nil)
function UiKit.Viewport(kind: string, id: string, parent: GuiObject, silhouette: boolean?, tier: number?, accId: string?): (GuiObject, Model?)
	if PetModels and PetModels.CreateViewport then
		local t: number? = if kind == "Pet" then UiKit.TierOf(tier) else nil
		local acc: string? = if kind == "Pet" and not silhouette and Config.AccessoryValid(accId) then accId else nil
		local ok, vp, model = pcall(PetModels.CreateViewport, kind, id, parent, silhouette == true, t, acc)
		if ok and typeof(vp) == "Instance" and vp:IsA("GuiObject") then
			vp.AnchorPoint = Vector2.new(0.5, 0.5)
			vp.Position = UDim2.fromScale(0.5, 0.5)
			vp.Size = UDim2.fromScale(1, 1)
			vp.BackgroundTransparency = 1
			if vp.Parent ~= parent then
				vp.Parent = parent
			end
			local m: Model? = nil
			if typeof(model) == "Instance" and model:IsA("Model") then
				m = model
			end
			return vp, m
		elseif not ok then
			warn("[UiKit] CreateViewport 실패:", vp)
		end
	end
	local emoji = if kind == "Egg" then "🥚" elseif kind == "Accessory" then UiKit.AccessoryIcon(id) elseif silhouette then "❓" else "🐾"
	local label = UiKit.Label({ Text = emoji, Parent = parent }, { MaxText = 80 })
	return label, nil
end

-- 모델 하나를 ViewportFrame 에 담아 비스듬히 앞에서 보여 줘요 (모델은 그 안으로 옮겨요)
function UiKit.ModelViewport(model: Model, parent: GuiObject): ViewportFrame
	local vf: ViewportFrame = Make("ViewportFrame", {
		Name = "ModelViewport",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(175, 175, 185),
		LightColor = Color3.fromRGB(255, 250, 245),
		LightDirection = Vector3.new(-0.4, -1, 0.8),
	})
	model.Parent = vf
	local cam: Camera = Make("Camera", { FieldOfView = 32, Parent = vf })
	vf.CurrentCamera = cam
	local cf, size = model:GetBoundingBox()
	local radius = math.max(size.Magnitude * 0.5, 0.5)
	local dist = radius / math.sin(math.rad(cam.FieldOfView * 0.5)) * 0.85
	local dir = Vector3.new(0.45, 0.32, -1).Unit -- 앞(-Z) 오른쪽 위에서
	local center = cf.Position
	cam.CFrame = CFrame.lookAt(center + dir * dist, center)
	vf.Parent = parent
	return vf
end

-- 가구 뷰포트 (상점·꾸미기 칸). FurnitureModels.CreateViewport → 없으면 Build 로 직접 → 그것도 안 되면 이모지
function UiKit.FurnitureViewport(furnId: string, parent: GuiObject): (GuiObject, Model?)
	local fm = getFurnitureModels()
	if fm and fm.CreateViewport then
		local ok, vp, model = pcall(fm.CreateViewport, furnId, parent)
		if ok and typeof(vp) == "Instance" and vp:IsA("GuiObject") then
			vp.AnchorPoint = Vector2.new(0.5, 0.5)
			vp.Position = UDim2.fromScale(0.5, 0.5)
			vp.Size = UDim2.fromScale(1, 1)
			vp.BackgroundTransparency = 1
			if vp.Parent ~= parent then
				vp.Parent = parent
			end
			local m: Model? = nil
			if typeof(model) == "Instance" and model:IsA("Model") then
				m = model
			end
			return vp, m
		elseif not ok then
			warn("[UiKit] 가구 CreateViewport 실패:", vp)
		end
	end
	if fm and fm.Build then
		local ok, model = pcall(fm.Build, furnId)
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			return UiKit.ModelViewport(model, parent), model
		elseif not ok then
			warn("[UiKit] 가구 Build 실패:", model)
		end
	end
	local label = UiKit.Label({ Text = "🛋", Parent = parent }, { MaxText = 80 })
	return label, nil
end

export type Window = {
	Panel: Frame,
	Header: Frame,
	Content: Frame,
	Title: TextLabel,
	Open: () -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	OnOpen: (() -> ())?,
	OnClose: (() -> ())?,
}

export type WindowOpts = {
	Title: string,
	Color: Color3,
	Name: string,
	Size: UDim2?, -- 기본 화면의 86%
	MaxSize: Vector2?, -- 기본 900 × 660
}

-- 가운데 뜨는 창 (반투명 배경 탭하면 닫힘). Size/MaxSize 로 작은 창도 만들 수 있어요
function UiKit.Window(gui: Instance, opts: WindowOpts): Window
	local open = false
	local token = 0

	local backdrop: TextButton = Make("TextButton", {
		Name = opts.Name .. "Backdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(45, 25, 70),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	local panel: Frame = Make("Frame", {
		Name = opts.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = opts.Size or UDim2.fromScale(0.86, 0.86),
		BackgroundColor3 = C.Cream,
		Visible = false,
		ZIndex = 21,
		Active = true,
		Parent = gui,
	})
	Make("UISizeConstraint", { MaxSize = opts.MaxSize or Vector2.new(900, 660), MinSize = Vector2.new(280, 220), Parent = panel })
	UiKit.Corner(panel, UDim.new(0, 26))
	UiKit.Stroke(panel, opts.Color, 6, true)
	local scale = UiKit.Scale(panel)

	local header: Frame = Make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = opts.Color,
		ZIndex = 22,
		Parent = panel,
	})
	UiKit.Corner(header, UDim.new(0, 22))
	UiKit.Gradient(header)
	-- 헤더 아래쪽 모서리는 각지게
	Make("Frame", {
		Name = "Filler",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = UiKit.Darken(opts.Color, 0.12),
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = header,
	})
	local titleLabel = UiKit.Label({
		Name = "Title",
		Text = opts.Title,
		Position = UDim2.new(0, 18, 0, 6),
		Size = UDim2.new(1, -90, 1, -12),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
		Parent = header,
	}, { Stroke = UiKit.Darken(opts.Color, 0.45), MaxText = 34, StrokeThickness = 3 })

	local content: Frame = Make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 66),
		Size = UDim2.new(1, -24, 1, -78),
		ZIndex = 22,
		Parent = panel,
	})

	local win: any = { Panel = panel, Header = header, Content = content, Title = titleLabel }

	function win.IsOpen(): boolean
		return open
	end

	function win.Open()
		if open then
			return
		end
		open = true
		token += 1
		backdrop.Visible = true
		panel.Visible = true
		UiKit.Tween(backdrop, 0.25, { BackgroundTransparency = 0.55 })
		scale.Scale = 0.55
		UiKit.Tween(scale, 0.38, { Scale = 1 }, Enum.EasingStyle.Back)
		UiKit.PlaySound("Click")
		if win.OnOpen then
			win.OnOpen()
		end
	end

	function win.Close()
		if not open then
			return
		end
		open = false
		token += 1
		local my = token
		UiKit.Tween(backdrop, 0.18, { BackgroundTransparency = 1 })
		UiKit.Tween(scale, 0.16, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.17, function()
			if token == my then
				backdrop.Visible = false
				panel.Visible = false
			end
		end)
		if win.OnClose then
			win.OnClose()
		end
	end

	backdrop.Activated:Connect(function()
		win.Close()
	end)

	local closeButton = UiKit.Button({
		Name = "Close",
		Text = "✖",
		Color = C.Red,
		Size = UDim2.new(0, 46, 0, 46),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Radius = UDim.new(0.5, 0),
		ZIndex = 25,
		Parent = header,
		OnClick = function()
			win.Close()
		end,
	})

	-- 낮은 화면 (가로 폰, 화면 높이 < 500): 창을 거의 화면만큼 키우고 머리줄을 얇게 해서 내용 칸을 넓혀요
	local compact: boolean? = nil
	local function applyCompact()
		local h = if gui:IsA("GuiBase2d") then (gui :: GuiBase2d).AbsoluteSize.Y else 0
		local want = h > 0 and h < 500
		if want == compact then
			return
		end
		compact = want
		local headerH = if want then 44 else 58
		local pad = if want then 8 else 12
		header.Size = UDim2.new(1, 0, 0, headerH)
		content.Position = UDim2.new(0, pad, 0, headerH + pad - 4)
		content.Size = UDim2.new(1, -2 * pad, 1, -(headerH + 2 * pad - 4))
		closeButton.Size = if want then UDim2.fromOffset(38, 38) else UDim2.fromOffset(46, 46)
		panel.Position = UDim2.fromScale(0.5, if want then 0.5 else 0.52)
		local base = opts.Size or UDim2.fromScale(0.86, 0.86)
		panel.Size = if want then UDim2.new(if opts.Size then base.X.Scale else 0.94, base.X.Offset, 0.95, 0) else base
	end
	if gui:IsA("GuiBase2d") then
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyCompact)
	end
	applyCompact()

	return win :: Window
end

-- 부모들의 UIScale 을 모두 곱한 값 (창이 튀어나오는 애니메이션 중에도 칸 크기가 흔들리지 않게)
function UiKit.ScaleOf(start: Instance?): number
	local s = 1
	local node: Instance? = start
	while node do
		local sc = node:FindFirstChildOfClass("UIScale")
		if sc and sc.Scale > 0.01 then
			s *= sc.Scale
		end
		node = node.Parent
	end
	return s
end

-- 스크롤 안에서 격자에 쓸 수 있는 너비 (0 이하면 아직 모름)
function UiKit.GridWidth(scroll: ScrollingFrame): number
	return scroll.AbsoluteSize.X / UiKit.ScaleOf(scroll) - scroll.ScrollBarThickness - 12
end

-- 너비에 맞는 칸 수와 칸 크기: (cols, cellW, cellH)
function UiKit.GridCell(width: number, minCell: number, ratio: number, maxCols: number?): (number, number, number)
	local cols = math.clamp(math.floor(width / minCell), 2, maxCols or 6)
	local cw = math.floor((width - (cols - 1) * 10) / cols)
	return cols, cw, math.floor(cw * ratio)
end

-- 스크롤 격자: 너비에 맞게 칸 수/크기 자동 조절
function UiKit.AutoGrid(scroll: ScrollingFrame, minCell: number, ratio: number, maxCols: number?)
	local grid: UIGridLayout = Make("UIGridLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = scroll,
	})
	Make("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		Parent = scroll,
	})
	local function update()
		local w = UiKit.GridWidth(scroll)
		if w <= 0 then
			return
		end
		local _, cw, ch = UiKit.GridCell(w, minCell, ratio, maxCols)
		grid.CellSize = UDim2.fromOffset(cw, ch)
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
	return grid
end

-- 세로 목록(UIListLayout) 스크롤. 머리글 + 격자 구역을 번갈아 넣을 때 써요
function UiKit.ListScroller(parent: Instance, props: { [string]: any }?): ScrollingFrame
	local scroll = UiKit.Scroller(parent, props)
	Make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = scroll,
	})
	Make("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		Parent = scroll,
	})
	return scroll
end

-- 목록 스크롤 안의 격자 구역. 칸 크기와 구역 높이를 너비에 맞게 맞춰요.
-- 돌려주는 함수를 부르면 다시 계산해요 (칸을 숨기거나 더한 뒤에)
function UiKit.SectionGrid(section: GuiObject, scroll: ScrollingFrame, minCell: number, ratio: number, maxCols: number?): () -> ()
	local grid: UIGridLayout = Make("UIGridLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = section,
	})
	local function relayout()
		local w = UiKit.GridWidth(scroll)
		if w <= 0 then
			return
		end
		local cols, cw, ch = UiKit.GridCell(w, minCell, ratio, maxCols)
		grid.CellSize = UDim2.fromOffset(cw, ch)
		local n = 0
		for _, child in section:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				n += 1
			end
		end
		local rows = math.ceil(n / cols)
		section.Size = UDim2.new(1, 0, 0, if rows > 0 then rows * ch + (rows - 1) * 10 else 0)
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	relayout()
	return relayout
end

-- 목록 스크롤에 넣는 머리글 알약 (희귀도 구역 제목 등)
function UiKit.SectionHeader(scroll: Instance, text: string, color: Color3, order: number, width: number?): TextLabel
	local row: Frame = Make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = scroll,
	})
	local pill: Frame = Make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.new(0, width or 190, 0, 30),
		BackgroundColor3 = color,
		Parent = row,
	})
	UiKit.Corner(pill, UDim.new(0.5, 0))
	UiKit.Gradient(pill)
	UiKit.Stroke(pill, C.White, 3, true)
	return UiKit.Label({
		Text = text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.78),
		Parent = pill,
	}, { Stroke = UiKit.Darken(color, 0.45), MaxText = 22 })
end

function UiKit.Scroller(parent: Instance, props: { [string]: any }?): ScrollingFrame
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.Pink,
		ElasticBehavior = Enum.ElasticBehavior.Always,
		ZIndex = 23,
		Parent = parent,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return Make("ScrollingFrame", base)
end

return UiKit
