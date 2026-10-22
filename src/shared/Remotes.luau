-- 서버/클라이언트 통신용 RemoteEvent 모음. (v4, 설계: docs/DESIGN.md "Remotes")
-- 서버가 먼저 require 하면 만들어지고, 클라이언트는 만들어질 때까지 기다려요.
-- 서버는 클라이언트가 보낸 값을 절대 믿지 않아요 (타입·소유·돈·거리·환생 수를 모두 검사).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- 서버 -> 클라이언트
	"DataSync", -- (snapshot) 내 데이터 전체 (DataService.Sync, 최대 초당 5번)
	"CoinSync", -- (coins: number, pending: number, income: number) 코인만 바뀌었을 때 가벼운 갱신 ★
	"Notify", -- (text: string, kind: "info" | "good" | "warn" | "alert")
	"HatchFx", -- (petId: string, position: Vector3, isNew: boolean, tier: number?, mode: "Hatch" | "Fuse" | nil)
	"CoinFx", -- (amount: number, position: Vector3, silent: boolean?) silent 면 소리 없이 숫자만
	"CoinField", -- (op: "Reset" | "Add" | "Remove", payload) 내 들판 코인 (CoinFieldService 참고, 코인마다 Zone 있음)
	"LeaderboardSync", -- (board: { Income: {Row}, Rebirths: {Row}, Global: boolean, UpdatedAt: number }) ★
	"EggAlert", -- (zone: number, eggId: string) 좋은 알(지역 맨 위 2칸)이 벨트에 나왔어요 → 배너 (Config.EggAlert 규칙) ★v4
	-- ★v6 아주 희귀한 알 (Config.EggAlertKind(eggId) == "Rare", egg.Special) 은 규칙 없이 늘 와요
	"EggBelt", -- (op: "Reset" | "Add" | "Remove" | "Bought", payload) 내 벨트 알 (사람마다 따로, ConveyorService 참고) ★v5
	-- Reset: { {Uid, EggId, Zone, Born}, … } 내 모든 벨트 알 / Add: {Uid, EggId, Zone, Born} / Remove: Uid
	-- Bought: {Uid, Target: CFrame (받침대), FlyTime: number, Poof: boolean} 산 알 → 집으로 날아가기 (Poof 면 뿅)
	-- Born = workspace:GetServerTimeNow() 기준 나온 시각, 자리 = Config.BeltEggSpot(Zone, 지금 - Born, EggId)
	-- ★v6 희귀 알은 더 오래 있어요: 지우는 때 = Config.BeltEggLife(EggId)
	-- 클라이언트 -> 서버
	"RequestSync", -- ()
	"PetAction", -- (uid: string, action: "Follow" | "Unfollow" | "ToBase" | "ToBag" | "Sell" | "Ride" | "Unride" | "Hold" | "Unhold" | "Fuse")
	"AutoPlace", -- () 빈 받침대를 가장 좋은 펫으로 채우기 (가방 + 받침대 펫 중 수익 높은 순) ★
	"ClearBase", -- () 집 받침대 펫을 모두 가방으로 (알은 그대로) ★
	"BuySlot", -- () 다음 받침대 사기
	"BuyFloor", -- () 다음 층 올리기 (Config.CanBuyFloor + FloorInfo[floors + 1].Price)
	"SetTheme", -- (themeId: string) 집 테마 사기/적용
	"Rebirth", -- () 환생하기
	"PickupCoin", -- (coinId: number) 들판 코인 먹기 요청
	"BuyEgg", -- (uid: number) 내 벨트 알 사기 (내 목록에 있고, 벨트 위, 계산한 자리 20 안, 지역 열림, 빈 받침대, 코인) ★v5
	"Teleport", -- (kind: "Zone" | "Floor" | "Home", n: number?) 지역/우리 집 층/우리 집으로 이동 ★
	"BuyAccessory", -- (accId: string) 펫 옷 사기 (옷장에 영원히) ★
	"EquipAccessory", -- (uid: string, accId: string) 펫에게 옷 입히기, accId = "" 이면 벗기기 ★
	"BuyFurniture", -- (furnId: string) 가구 1개 사기 → 가구 가방 ★
	"PlaceFurniture", -- (furnId: string, floor: number, x: number, z: number, r: number) 가구 가방에서 꺼내 놓기 ★
	"MoveFurniture", -- (fid: string, floor: number, x: number, z: number, r: number) 놓인 가구 옮기기/돌리기 ★
	"PickupFurniture", -- (fid: string) 놓인 가구를 가구 가방으로 ★
	"SetSetting", -- (key: string, value: boolean | number) 켜고 끄는 버튼 (Config.Settings 의 키만) ★v5, ★v7 AlertLevel 은 0..4 숫자
	"StashEgg", -- () ★v7 "🥚 나쁜 알 빼기": 받침대가 다 찼으면 가장 나쁜 알(없으면 가장 약한 펫) 하나를 가방으로
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
