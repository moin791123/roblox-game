local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	print(player.Name .. " 님이 입장했습니다")
end)
