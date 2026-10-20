-- 📖 도감 창: 모든 펫, 찾은 펫은 모습이 보이고 못 찾은 펫은 그림자 + ???
local UiKit = require(script.Parent.UiKit)
local State = require(script.Parent.State)

local Config = UiKit.Config
local Make, C = UiKit.Make, UiKit.Colors

local IndexWindow = {}

type Entry = {
	Frame: Frame,
	Holder: Frame,
	Name: TextLabel,
	Discovered: boolean?,
}

local window: UiKit.Window
local progressLabel: TextLabel
local barFill: Frame
local entries: { [string]: Entry } = {}
local dirty = true
local lastCount = -1

local function setDiscovered(petId: string, entry: Entry, discovered: boolean)
	if entry.Discovered == discovered then
		return
	end
	local wasKnown = entry.Discovered
	entry.Discovered = discovered
	for _, child in entry.Holder:GetChildren() do
		child:Destroy()
	end
	UiKit.Viewport("Pet", petId, entry.Holder, not discovered)
	local def = Config.Pets[petId]
	local rc = UiKit.RarityColor(def.Rarity)
	if discovered then
		entry.Name.Text = def.Name
		entry.Frame.BackgroundColor3 = UiKit.Lighten(rc, 0.8)
		if wasKnown == false then
			UiKit.Pop(entry.Frame, 0.45)
		end
	else
		entry.Name.Text = "???"
		entry.Frame.BackgroundColor3 = Color3.fromRGB(225, 222, 235)
	end
end

local function rebuild()
	dirty = false
	local snap = State.Snapshot
	local index = if snap then snap.Index else {}
	local count = 0
	for _, petId in Config.PetOrder do
		local entry = entries[petId]
		local found = index[petId] == true
		if found then
			count += 1
		end
		if entry then
			setDiscovered(petId, entry, found)
		end
	end
	local total = #Config.PetOrder
	progressLabel.Text = string.format("📖 %d / %d", count, total)
	UiKit.Tween(barFill, 0.5, { Size = UDim2.fromScale(math.max(0.04, count / total), 1) }, Enum.EasingStyle.Back)
	if lastCount >= 0 and count > lastCount then
		UiKit.Bump(progressLabel, 0.25)
	end
	lastCount = count
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

	local scroll = UiKit.Scroller(content, { Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 1, -52), ScrollBarImageColor3 = C.Sky })
	UiKit.AutoGrid(scroll, 128, 1.3, 6)

	for i, petId in Config.PetOrder do
		local def = Config.Pets[petId]
		local rarity = (Config.Rarities :: any)[def.Rarity]
		local rc = UiKit.RarityColor(def.Rarity)
		local frame: Frame = Make("Frame", {
			Name = petId,
			LayoutOrder = i,
			BackgroundColor3 = Color3.fromRGB(225, 222, 235),
			Parent = scroll,
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
		local rpill: Frame = Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.84),
			Size = UDim2.fromScale(0.64, 0.12),
			BackgroundColor3 = rc,
			Parent = frame,
		})
		UiKit.Corner(rpill, UDim.new(0.5, 0))
		UiKit.Label({ Text = rarity and rarity.Name or "", Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1), Parent = rpill }, { Stroke = UiKit.Darken(rc, 0.45), MaxText = 18 })
		entries[petId] = { Frame = frame, Holder = holder, Name = nameLabel, Discovered = nil }
	end

	window.OnOpen = function()
		if dirty then
			rebuild()
		end
	end
	rebuild()
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
