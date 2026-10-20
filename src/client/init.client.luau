-- 알 훔치기 펫 월드: 클라이언트 시작점
-- 화면(UI)과 효과를 만들고 서버 이벤트를 연결해요.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local UiKit = require(script.UiKit)
local State = require(script.State)
local Toasts = require(script.Toasts)
local Hud = require(script.Hud)
local BagWindow = require(script.BagWindow)
local IndexWindow = require(script.IndexWindow)
local HatchFx = require(script.HatchFx)
local CarryHud = require(script.CarryHud)
local WorldFx = require(script.WorldFx)
local Tips = require(script.Tips)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 예전 GUI 가 남아 있으면 정리
for _, name in { "PetWorldGui", "PetWorldToasts" } do
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local gui: ScreenGui = UiKit.Make("ScreenGui", {
	Name = "PetWorldGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

local function toggleBag()
	if BagWindow.IsOpen() then
		BagWindow.Close()
	else
		IndexWindow.Close()
		BagWindow.Open()
	end
end

local function toggleIndex()
	if IndexWindow.IsOpen() then
		IndexWindow.Close()
	else
		BagWindow.Close()
		IndexWindow.Open()
	end
end

-- 알림은 부화 연출(DisplayOrder 20)보다 위에 보이도록 따로
local toastGui: ScreenGui = UiKit.Make("ScreenGui", {
	Name = "PetWorldToasts",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 30,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
Toasts.Init(toastGui)
Hud.Init(gui, { ToggleBag = toggleBag, ToggleIndex = toggleIndex })
BagWindow.Init(gui)
IndexWindow.Init(gui)
CarryHud.Init(gui)
Tips.Init(gui)
HatchFx.Init(playerGui)
WorldFx.Init()

-- 서버 이벤트
State.OnSync(function(snap)
	Hud.Update(snap)
	BagWindow.OnSync()
	IndexWindow.OnSync()
end)

Remotes.DataSync.OnClientEvent:Connect(function(snap)
	State.SetSnapshot(snap)
end)

Remotes.Notify.OnClientEvent:Connect(function(text, kind)
	Toasts.Show(text, kind)
end)

Remotes.HatchFx.OnClientEvent:Connect(function(petId, position, isNew)
	HatchFx.Play(petId, position, isNew)
end)

Remotes.CoinFx.OnClientEvent:Connect(function(amount, position)
	WorldFx.CoinFx(amount, position)
end)

-- 키보드 단축키 (PC): B = 가방, N = 도감
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		toggleBag()
	elseif input.KeyCode == Enum.KeyCode.N then
		toggleIndex()
	end
end)

Remotes.RequestSync:FireServer()
