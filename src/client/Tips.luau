-- 처음 2분 반 동안 아래쪽에 도움말이 바뀌며 나와요 (지도·상점·자동 배치·옷·엘리베이터 소개)
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.UiKit)

local Make, C = UiKit.Make, UiKit.Colors

local Tips = {}

-- PC(키보드)에서만 "(B)" 같은 단축키를 붙여요
local showKeys = UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
local function key(k: string): string
	return if showKeys then "(" .. k .. ")" else ""
end

local TIPS = {
	"🥚 컨베이어에서 알을 사세요" .. (if showKeys then " (E)" else ""),
	"🐣 집 받침대에 둔 알은 시간이 지나면 부화해요",
	"💰 들판의 코인을 주우면 코인이 늘어요",
	"🏦 집의 금색 판을 밟으면 모인 코인을 받아요",
	"⭐ 가방" .. key("B") .. "의 '✨ 좋은 펫 자동 배치'로 집을 가장 센 펫으로 채워요",
	"🎒 가방" .. key("B") .. "에서 펫을 눌러 따라오게 하거나 타 보세요 🏇",
	"✨ 같은 펫 3마리를 모아 합성해 보세요 (집 받침대 펫은 빼고 세요)",
	"🛍 상점" .. key("P") .. "에서 펫 옷 👕 과 가구 🛋 를 살 수 있어요",
	"👕 가방" .. key("B") .. "에서 펫을 누르고 '옷 입히기'를 해 보세요",
	"🗺 지도" .. key("M") .. "로 열린 지역에 바로 갈 수 있어요",
	"🏠 집" .. key("H") .. "에서 테마를 바꾸면 집이 커지고 수익도 늘어요",
	"🛗 집 엘리베이터로 층을 오르내려요",
	"📖 도감" .. key("N") .. "에서 지역마다 숨은 비밀 펫을 찾아보세요",
	"🏆 순위" .. key("L") .. "에서 친구들 기록을 볼 수 있어요",
	"🔄 환생" .. key("R") .. "하면 새 지역이 열리고 영구 보너스를 받아요",
}

local DURATION = 150
local INTERVAL = 6

local banner: Frame? = nil
local suppressed = false -- 꾸미기 모드 중에는 숨겨요 (아래 가구 줄을 가려요)

function Tips.Init(gui: Instance)
	local frame: Frame = Make("Frame", {
		Name = "Tips",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0.46, 0, 0, 48),
		BackgroundColor3 = C.Lavender,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	banner = frame
	Make("UISizeConstraint", { MinSize = Vector2.new(260, 0), MaxSize = Vector2.new(580, 60), Parent = frame })
	UiKit.Corner(frame, UDim.new(0.5, 0))
	UiKit.Gradient(frame)
	UiKit.Stroke(frame, C.White, 3, true)
	local label = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -28, 0.7, 0),
		ZIndex = 11,
		Parent = frame,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.5), MaxText = 26 })

	task.spawn(function()
		task.wait(3)
		local started = os.clock()
		local i = 0
		while os.clock() - started < DURATION do
			i = i % #TIPS + 1
			label.Text = TIPS[i]
			frame.Visible = not suppressed
			if not suppressed then
				UiKit.Pop(frame, 0.35)
			end
			task.wait(INTERVAL)
		end
		UiKit.Tween(UiKit.Scale(frame), 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.3)
		banner = nil
		frame:Destroy()
	end)
end

-- 잠깐 숨기기 (꾸미기 모드 등). false 면 다음 도움말부터 다시 보여요
function Tips.SetSuppressed(on: boolean)
	suppressed = on
	local b = banner
	if b and on then
		b.Visible = false
	end
end

return Tips
