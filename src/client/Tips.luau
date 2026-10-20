-- 처음 2분 동안 아래쪽에 도움말이 바뀌며 나와요
local Players = game:GetService("Players")

local UiKit = require(script.Parent.UiKit)

local Make, C = UiKit.Make, UiKit.Colors
local player = Players.LocalPlayer

local Tips = {}

local TIPS = {
	"🥚 가운데 컨베이어에서 알을 사세요",
	"🐣 기지 받침대에 둔 알은 시간이 지나면 부화해요",
	"💰 기지의 금색 판을 밟으면 코인을 받아요",
	"🐾 펫이 따라오면 들판 코인을 더 많이 모아요",
	"😈 다른 기지의 펫을 훔칠 수 있어요!",
	"🔒 잠금 버튼으로 기지를 지켜요",
	"🎒 가방에서 펫을 옮기거나 팔 수 있어요",
}

local DURATION = 120
local INTERVAL = 6

function Tips.Init(gui: Instance)
	local banner: Frame = Make("Frame", {
		Name = "Tips",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0.46, 0, 0, 48),
		BackgroundColor3 = C.Lavender,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	Make("UISizeConstraint", { MinSize = Vector2.new(260, 0), MaxSize = Vector2.new(580, 60), Parent = banner })
	UiKit.Corner(banner, UDim.new(0.5, 0))
	UiKit.Gradient(banner)
	UiKit.Stroke(banner, C.White, 3, true)
	local label = UiKit.Label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -28, 0.7, 0),
		ZIndex = 11,
		Parent = banner,
	}, { Stroke = UiKit.Darken(C.Lavender, 0.5), MaxText = 26 })

	task.spawn(function()
		task.wait(3)
		local started = os.clock()
		local i = 0
		while os.clock() - started < DURATION do
			if player:GetAttribute("Carrying") == true then
				banner.Visible = false
				task.wait(1)
			else
				i = i % #TIPS + 1
				label.Text = TIPS[i]
				banner.Visible = true
				UiKit.Pop(banner, 0.35)
				task.wait(INTERVAL)
			end
		end
		UiKit.Tween(UiKit.Scale(banner), 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.3)
		banner:Destroy()
	end)
end

return Tips
