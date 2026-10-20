local Config = {
	GameName = "귀여운 펫 모으기",

	-- 코인
	CoinValue = 1,
	CoinCount = 40,
	CoinSpawnRange = 50,
	CoinRespawnTime = 5,

	-- 펫
	MaxFollowingPets = 3,

	Rarities = {
		["일반"] = Color3.fromRGB(230, 230, 230),
		["희귀"] = Color3.fromRGB(90, 170, 255),
		["전설"] = Color3.fromRGB(255, 200, 40),
	},

	Eggs = {
		{
			Name = "기본 알",
			Price = 10,
			Color = Color3.fromRGB(255, 245, 210),
			Position = Vector3.new(-8, 3, -15),
			Pets = {
				{ Name = "병아리", Rarity = "일반", Chance = 40, Color = Color3.fromRGB(255, 230, 90) },
				{ Name = "강아지", Rarity = "일반", Chance = 30, Color = Color3.fromRGB(210, 170, 120) },
				{ Name = "고양이", Rarity = "희귀", Chance = 20, Color = Color3.fromRGB(255, 160, 80) },
				{ Name = "토끼", Rarity = "희귀", Chance = 10, Color = Color3.fromRGB(255, 180, 210) },
			},
		},
		{
			Name = "반짝 알",
			Price = 50,
			Color = Color3.fromRGB(200, 170, 255),
			Position = Vector3.new(8, 3, -15),
			Pets = {
				{ Name = "판다", Rarity = "희귀", Chance = 50, Color = Color3.fromRGB(250, 250, 250) },
				{ Name = "여우", Rarity = "희귀", Chance = 30, Color = Color3.fromRGB(240, 110, 50) },
				{ Name = "유니콘", Rarity = "전설", Chance = 15, Color = Color3.fromRGB(220, 190, 255) },
				{ Name = "아기 용", Rarity = "전설", Chance = 5, Color = Color3.fromRGB(120, 230, 180) },
			},
		},
	},
}

return Config
