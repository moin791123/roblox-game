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

local UiKit = {}
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

-- 펫/알 뷰포트. PetModels 가 없거나 실패하면 이모지로 대신
function UiKit.Viewport(kind: string, id: string, parent: GuiObject, silhouette: boolean?): (GuiObject, Model?)
	if PetModels and PetModels.CreateViewport then
		local ok, vp, model = pcall(PetModels.CreateViewport, kind, id, parent, silhouette == true)
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
	local emoji = if kind == "Egg" then "🥚" elseif silhouette then "❓" else "🐾"
	local label = UiKit.Label({ Text = emoji, Parent = parent }, { MaxText = 80 })
	return label, nil
end

export type Window = {
	Panel: Frame,
	Header: Frame,
	Content: Frame,
	Open: () -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	OnOpen: (() -> ())?,
}

-- 가운데 뜨는 창 (반투명 배경 탭하면 닫힘)
function UiKit.Window(gui: Instance, opts: { Title: string, Color: Color3, Name: string }): Window
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
		Size = UDim2.fromScale(0.86, 0.86),
		BackgroundColor3 = C.Cream,
		Visible = false,
		ZIndex = 21,
		Active = true,
		Parent = gui,
	})
	Make("UISizeConstraint", { MaxSize = Vector2.new(900, 660), MinSize = Vector2.new(280, 220), Parent = panel })
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
	UiKit.Label({
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

	local win: any = { Panel = panel, Header = header, Content = content }

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
	end

	backdrop.Activated:Connect(function()
		win.Close()
	end)

	UiKit.Button({
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

	return win :: Window
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
		-- 창이 튀어나오는 애니메이션(UIScale) 중에도 칸 크기가 흔들리지 않게 배율을 나눠요
		local s = 1
		local node: Instance? = scroll
		while node do
			local sc = node:FindFirstChildOfClass("UIScale")
			if sc and sc.Scale > 0.01 then
				s *= sc.Scale
			end
			node = node.Parent
		end
		local w = scroll.AbsoluteSize.X / s - scroll.ScrollBarThickness - 12
		if w <= 0 then
			return
		end
		local cols = math.clamp(math.floor(w / minCell), 2, maxCols or 6)
		local cw = math.floor((w - (cols - 1) * 10) / cols)
		grid.CellSize = UDim2.fromOffset(cw, math.floor(cw * ratio))
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
	return grid
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
