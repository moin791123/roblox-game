-- 알림 말풍선 (코인 아래 가운데에 쌓여요, 최대 4개)
local UiKit = require(script.Parent.UiKit)

local Make, C = UiKit.Make, UiKit.Colors

local Toasts = {}

local KIND_COLORS: { [string]: Color3 } = {
	info = C.Sky,
	good = C.Mint,
	warn = C.Orange,
	alert = C.Red,
}

local MAX = 4
local container: Frame? = nil
local live: { Frame } = {}
local counter = 0

function Toasts.Init(gui: Instance)
	local frame: Frame = Make("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 116),
		Size = UDim2.new(0.5, 0, 0, 260),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = gui,
	})
	Make("UISizeConstraint", { MinSize = Vector2.new(290, 0), MaxSize = Vector2.new(560, 400), Parent = frame })
	Make("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	container = frame
end

local function remove(outer: Frame)
	local idx = table.find(live, outer)
	if not idx then
		return
	end
	table.remove(live, idx)
	local bubble = outer:FindFirstChild("Bubble")
	if bubble then
		UiKit.Tween(UiKit.Scale(bubble), 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
	task.delay(0.2, function()
		outer:Destroy()
	end)
end

function Toasts.Show(text: any, kind: any)
	local parent = container
	if not parent then
		return
	end
	local k = if type(kind) == "string" and KIND_COLORS[kind] then kind else "info"
	local color = KIND_COLORS[k]
	local str = tostring(text)
	counter += 1

	local tall = utf8.len(str) ~= nil and (utf8.len(str) :: number) > 22
	local outer: Frame = Make("Frame", {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, if tall then 58 else 46),
		BackgroundTransparency = 1,
		LayoutOrder = counter,
		ZIndex = 40,
		Parent = parent,
	})
	local bubble: Frame = Make("Frame", {
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		ZIndex = 41,
		Parent = outer,
	})
	UiKit.Corner(bubble, UDim.new(0, 20))
	UiKit.Gradient(bubble)
	UiKit.Stroke(bubble, C.White, 3, true)
	UiKit.Label({
		Text = str,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -12),
		ZIndex = 42,
		Parent = bubble,
	}, { Stroke = UiKit.Darken(color, 0.45), MaxText = 26 })

	table.insert(live, outer)
	while #live > MAX do
		local old = table.remove(live, 1)
		if old then
			old:Destroy()
		end
	end

	UiKit.Pop(bubble, 0.4)
	if k == "alert" then
		UiKit.PlaySound("Alert")
		task.delay(0.15, function()
			UiKit.Shake(bubble, 7, 14)
		end)
	end
	task.delay(if k == "alert" then 5 elseif tall then 4 else 3.2, function()
		remove(outer)
	end)
end

return Toasts
