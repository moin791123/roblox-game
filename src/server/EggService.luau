local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CoinService = require(script.Parent.CoinService)
local PetService = require(script.Parent.PetService)

local EggService = {}

local hatchEvent

local function rollPet(egg)
	local total = 0
	for _, pet in egg.Pets do
		total += pet.Chance
	end

	local roll = math.random() * total
	for _, pet in egg.Pets do
		roll -= pet.Chance
		if roll <= 0 then
			return pet
		end
	end
	return egg.Pets[#egg.Pets]
end

local function buildEgg(egg)
	local part = Instance.new("Part")
	part.Name = egg.Name
	part.Size = Vector3.new(4, 5, 4)
	part.Color = egg.Color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.Position = egg.Position

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 50)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.format("%s\n🪙 %d", egg.Name, egg.Price)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "부화하기"
	prompt.ObjectText = egg.Name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		if not CoinService.SpendCoins(player, egg.Price) then
			hatchEvent:FireClient(player, {
				Success = false,
				Message = string.format("코인이 부족해요! (%d개 필요)", egg.Price),
			})
			return
		end

		local pet = rollPet(egg)
		PetService.GivePet(player, pet)
		hatchEvent:FireClient(player, {
			Success = true,
			PetName = pet.Name,
			Rarity = pet.Rarity,
		})
	end)

	part.Parent = workspace
end

function EggService.Start()
	hatchEvent = Instance.new("RemoteEvent")
	hatchEvent.Name = "HatchResult"
	hatchEvent.Parent = ReplicatedStorage

	for _, egg in Config.Eggs do
		buildEgg(egg)
	end
end

return EggService
