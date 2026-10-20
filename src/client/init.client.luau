local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local hatchEvent = ReplicatedStorage:WaitForChild("HatchResult")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "PetGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 0, 10)
hint.Size = UDim2.fromOffset(420, 36)
hint.BackgroundTransparency = 1
hint.Text = "🪙 코인을 모아서 알을 부화시켜 보세요!"
hint.TextColor3 = Color3.new(1, 1, 1)
hint.TextStrokeTransparency = 0.3
hint.TextScaled = true
hint.Font = Enum.Font.FredokaOne
hint.Parent = gui

local popup = Instance.new("TextLabel")
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.4)
popup.Size = UDim2.fromOffset(0, 0)
popup.BackgroundTransparency = 1
popup.TextColor3 = Color3.new(1, 1, 1)
popup.TextStrokeTransparency = 0
popup.TextScaled = true
popup.Font = Enum.Font.FredokaOne
popup.Visible = false
popup.Parent = gui

local showToken = 0

hatchEvent.OnClientEvent:Connect(function(result)
	showToken += 1
	local token = showToken

	if result.Success then
		popup.Text = string.format("🎉 %s 펫을 얻었어요! (%s)", result.PetName, result.Rarity)
		popup.TextColor3 = Config.Rarities[result.Rarity] or Color3.new(1, 1, 1)
	else
		popup.Text = result.Message
		popup.TextColor3 = Color3.fromRGB(255, 120, 120)
	end

	popup.Size = UDim2.fromOffset(0, 0)
	popup.Visible = true
	TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = UDim2.fromOffset(520, 60),
	}):Play()

	task.delay(2.5, function()
		if token == showToken then
			popup.Visible = false
		end
	end)
end)
