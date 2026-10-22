-- ★v7.2 게임 패스 (Config.Passes: 🧲 자석 · ⚡ 슈퍼 자석 · 🏦 자동 수금). Id = 0 (아직 안 만듦) 이면 모두에게 공짜예요.
-- Id > 0 이면 서버가 확인해요: 들어올 때 MarketplaceService:UserOwnsGamePassAsync (pcall, 안 되면 조금 쉬고 2번 더).
-- 그래도 안 되면 "없음" 으로 두고, 다음 구매 끝 이벤트 때나 다시 들어올 때 또 확인해요.
-- 클라이언트(Hud·CoinField)에는 플레이어 속성 Pass_<키> (true = 쓸 수 있음) 로 알려요.
-- 사면 (PromptGamePassPurchaseFinished, 정말 산 경우만) 바로 켜고 말풍선 "🧲 자석을 샀어요! 이제 켜고 끌 수 있어요".
-- PassService.Has(player, key) 를 CoinFieldService (🧲 / ⚡) 와 PlotService (🏦) 가 써요. 켜 둔 설정 값은 그대로 저장돼요.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PassService = {}

local CHECK_TRIES = 3 -- 확인 시도 (처음 1번 + 다시 2번)
local RETRY_WAIT = 2 -- 다시 해 보기 전에 쉬는 초 (시도마다 조금 더 길게)

type Info = {
	Owned: { [string]: boolean }, -- 가진 패스 (한 번 가지면 안 없어져요)
	Failed: { [string]: boolean }, -- 확인이 끝내 안 된 패스 (다음에 다시)
	Checking: { [string]: boolean },
}
local infos: { [Player]: Info } = {}
local listeners: { (Player, string, boolean) -> () } = {}
local started = false

-- 마지막 글자 받침이 있으면 a ("자석을"), 없으면 b
local function josa(name: string, a: string, b: string): string
	local last: number? = nil
	for _, cp in utf8.codes(name) do
		last = cp
	end
	if last and last >= 0xAC00 and last <= 0xD7A3 and (last - 0xAC00) % 28 ~= 0 then
		return name .. a
	end
	return name .. b
end

local function notify(player: Player, text: string, kind: string)
	if player.Parent then
		Remotes.Notify:FireClient(player, text, kind)
	end
end

-- 이 사람이 이 기능을 쓸 수 있나 (패스가 없는 기능 / Id = 0 이면 언제나 true)
function PassService.Has(player: Player, key: string): boolean
	if Config.PassId(key) <= 0 then
		return true
	end
	local info = infos[player]
	return info ~= nil and info.Owned[key] == true
end

-- 쓸 수 있게 되거나 못 쓰게 되면 (player, key, has). PlotService 가 수금 패드 글자를 바꿔요
function PassService.OnChanged(fn: (Player, string, boolean) -> ())
	table.insert(listeners, fn)
end

-- 속성 Pass_<키> 맞추기 (바뀌었으면 알려요)
local function publish(player: Player, key: string)
	if infos[player] == nil then
		return
	end
	local has = PassService.Has(player, key)
	local attr = Config.PassAttribute(key)
	if player:GetAttribute(attr) == has then
		return
	end
	player:SetAttribute(attr, has)
	for _, fn in listeners do
		task.spawn(fn, player, key, has)
	end
end

-- Roblox 에 물어보기 (실패하면 조금 쉬고 다시). 끝내 안 되면 Failed (다음 구매 끝 이벤트 / 다시 들어오면 또)
local function checkKey(player: Player, key: string)
	local info = infos[player]
	local id = Config.PassId(key)
	if not info or id <= 0 or info.Checking[key] or info.Owned[key] then
		return
	end
	info.Checking[key] = true
	local owned: boolean? = nil
	for try = 1, CHECK_TRIES do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		if infos[player] ~= info then
			return -- 그새 나갔어요
		end
		if ok then
			owned = result == true
			break
		end
		warn("[PassService] 게임 패스 확인 실패:", key, id, result)
		if try < CHECK_TRIES then
			task.wait(RETRY_WAIT * try)
			if infos[player] ~= info then
				return
			end
		end
	end
	info.Checking[key] = nil
	if owned == nil then
		info.Failed[key] = true
	else
		info.Failed[key] = nil
		if owned then
			info.Owned[key] = true -- (그새 사서 켜졌으면 false 로 끄지 않아요)
		end
	end
	publish(player, key)
end

local function onPlayerAdded(player: Player)
	if infos[player] then
		return
	end
	infos[player] = { Owned = {}, Failed = {}, Checking = {} }
	for _, key in Config.PassOrder do
		publish(player, key) -- 공짜는 바로 true, 패스는 확인 전까지 false
		if Config.PassId(key) > 0 then
			task.spawn(checkKey, player, key)
		end
	end
end

-- 구매 창이 닫혔어요: 정말 샀으면 바로 켜고 말풍선. 확인이 안 됐던 패스는 이참에 다시 확인
local function onPurchaseFinished(player: any, passId: any, purchased: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local info = infos[player]
	if not info or player.Parent == nil then
		return -- 나간 사람
	end
	local key = Config.PassKeyOf(passId)
	if key and purchased == true and not info.Owned[key] then
		info.Owned[key] = true
		info.Failed[key] = nil
		publish(player, key)
		local pass = (Config.Passes :: any)[key]
		notify(player, pass.Emoji .. " " .. josa(pass.Name, "을", "를") .. " 샀어요! 이제 켜고 끌 수 있어요", "good")
	end
	local again: { string } = {}
	for k, failed in info.Failed do
		if failed and not info.Owned[k] then
			table.insert(again, k)
		end
	end
	for _, k in again do
		task.spawn(checkKey, player, k)
	end
end

function PassService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		infos[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	local ok, err = pcall(function()
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPurchaseFinished)
	end)
	if not ok then
		warn("[PassService] 구매 이벤트 연결 실패:", err)
	end
end

return PassService
