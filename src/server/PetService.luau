local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local PetService = {}

local petFolder
local petsByPlayer = {}

local function makeNameTag(petInfo)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 30)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = petInfo.Name
	label.TextColor3 = Config.Rarities[petInfo.Rarity] or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	return billboard
end

local function buildPet(petInfo)
	local body = Instance.new("Part")
	body.Name = petInfo.Name
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2, 2, 2)
	body.Color = petInfo.Color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false

	-- 눈 두 개 (앞쪽이 -Z 방향)
	for _, side in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.35, 0.35, 0.35)
		eye.Color = Color3.fromRGB(30, 30, 30)
		eye.CanCollide = false
		eye.CanTouch = false
		eye.CanQuery = false
		eye.Massless = true
		eye.CFrame = body.CFrame * CFrame.new(side * 0.4, 0.25, -0.9)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = eye
		weld.Parent = eye

		eye.Parent = body
	end

	makeNameTag(petInfo).Parent = body
	return body
end

function PetService.GivePet(player, petInfo)
	local list = petsByPlayer[player]
	if not list then
		list = {}
		petsByPlayer[player] = list
	end

	-- 따라다니는 펫이 가득 차면 가장 오래된 펫과 교체
	if #list >= Config.MaxFollowingPets then
		table.remove(list, 1):Destroy()
	end

	local pet = buildPet(petInfo)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		pet.CFrame = root.CFrame * CFrame.new(0, 0, 5)
	end
	pet.Parent = petFolder
	table.insert(list, pet)

	local petCount = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("펫")
	if petCount then
		petCount.Value += 1
	end
end

function PetService.Start()
	petFolder = Instance.new("Folder")
	petFolder.Name = "Pets"
	petFolder.Parent = workspace

	Players.PlayerRemoving:Connect(function(player)
		local list = petsByPlayer[player]
		if list then
			for _, pet in list do
				pet:Destroy()
			end
		end
		petsByPlayer[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for player, list in petsByPlayer do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				for i, pet in list do
					local offsetX = (i - (#list + 1) / 2) * 3
					local bob = math.sin(t * 4 + i) * 0.3
					local target = root.CFrame * CFrame.new(offsetX, bob - 1, 5)
					pet.CFrame = pet.CFrame:Lerp(target, 0.15)
				end
			end
		end
	end)
end

return PetService
