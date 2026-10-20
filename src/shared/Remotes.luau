-- 서버/클라이언트 통신용 RemoteEvent 모음.
-- 서버가 먼저 require 하면 만들어지고, 클라이언트는 만들어질 때까지 기다려요.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- 서버 -> 클라이언트
	"DataSync", -- (snapshot) 내 데이터 전체
	"Notify", -- (text: string, kind: "info" | "good" | "warn" | "alert")
	"HatchFx", -- (petId: string, position: Vector3, isNew: boolean, tier: number?, mode: "Hatch" | "Fuse" | nil)
	"CoinFx", -- (amount: number, position: Vector3)
	"CoinField", -- (op: "Reset" | "Add" | "Remove", payload) 내 들판 코인 (CoinFieldService 참고)
	-- 클라이언트 -> 서버
	"RequestSync", -- ()
	"PetAction", -- (uid: string, action: "Follow" | "Unfollow" | "ToBase" | "ToBag" | "Sell" | "Ride" | "Unride" | "Hold" | "Unhold" | "Fuse")
	"BuySlot", -- ()
	"Rebirth", -- () 환생하기
	"BuyFloor", -- () 2층 올리기
	"SetTheme", -- (themeId: string) 집 테마 사기/적용
	"PickupCoin", -- (coinId: number) 들판 코인 먹기 요청
}

local Remotes: { [string]: RemoteEvent } = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
	end
	for _, name in NAMES do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		Remotes[name] = remote
	end
	folder.Parent = ReplicatedStorage
else
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	for _, name in NAMES do
		Remotes[name] = folder:WaitForChild(name) :: RemoteEvent
	end
end

return Remotes
