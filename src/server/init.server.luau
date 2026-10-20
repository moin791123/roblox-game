local CoinService = require(script.CoinService)
local PetService = require(script.PetService)
local EggService = require(script.EggService)

-- 바닥이 없는 맵에서도 놀 수 있도록 잔디 바닥을 깔아 준다
if not workspace:FindFirstChild("Baseplate") then
	local ground = Instance.new("Part")
	ground.Name = "Baseplate"
	ground.Size = Vector3.new(200, 2, 200)
	ground.Position = Vector3.new(0, -1, 0)
	ground.Color = Color3.fromRGB(120, 200, 110)
	ground.Material = Enum.Material.Grass
	ground.Anchored = true
	ground.Parent = workspace
end

CoinService.Start()
PetService.Start()
EggService.Start()
