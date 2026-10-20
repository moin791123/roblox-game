local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CoinService = {}

local coinFolder

local function getCoinValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("코인")
end

local function randomPosition()
	local range = Config.CoinSpawnRange
	return Vector3.new(math.random(-range, range), 2, math.random(-range, range))
end

local function spawnCoin()
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.4, 2, 2)
	coin.Color = Color3.fromRGB(255, 205, 50)
	coin.Material = Enum.Material.Neon
	coin.Anchored = true
	coin.CanCollide = false
	coin.CFrame = CFrame.new(randomPosition())

	local collected = false
	coin.Touched:Connect(function(hit)
		if collected then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then
			return
		end
		collected = true
		CoinService.AddCoins(player, Config.CoinValue)
		coin:Destroy()
		task.delay(Config.CoinRespawnTime, spawnCoin)
	end)

	coin.Parent = coinFolder
end

local function setupPlayer(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = "코인"
	coins.Parent = leaderstats

	local pets = Instance.new("IntValue")
	pets.Name = "펫"
	pets.Parent = leaderstats

	leaderstats.Parent = player
end

function CoinService.AddCoins(player, amount)
	local coins = getCoinValue(player)
	if coins then
		coins.Value += amount
	end
end

function CoinService.SpendCoins(player, amount)
	local coins = getCoinValue(player)
	if not coins or coins.Value < amount then
		return false
	end
	coins.Value -= amount
	return true
end

function CoinService.Start()
	coinFolder = Instance.new("Folder")
	coinFolder.Name = "Coins"
	coinFolder.Parent = workspace

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	for _ = 1, Config.CoinCount do
		spawnCoin()
	end
end

return CoinService
