-- 처음 2분 동안 아래쪽에 도움말이 바뀌며 나와요
local UiKit = require(script.Parent.UiKit)

local Make, C = UiKit.Make, UiKit.Colors

local Tips = {}

local TIPS = {
	"🥚 가운데 컨베이어에서 알을 사세요 (E)",
	"🐣 집 받침대에 둔 알은 시간이 지나면 부화해요",
	"💰 들판의 코인을 주우면 코인이 늘어요",
	"🏦 집의 금색 판을 밟으면 모인 코인을 받아요",
	"🎒 가방(B)에서 펫을 따라오게 할 수 있어요",
	"🏇 가방(B)에서 '타기'를 누르면 펫을 타고 더 빨라져요",
	"✨ 같은 펫 3마리를 모아 가방(B)에서 합성해 보세요",
	"🙌 가방(B)에서 '들기'를 누르면 펫을 머리 위에 올려요",
	"📖 도감(N)에서 찾은 펫을 모아 보세요",
	"🏠 집(H)에서 테마를 바꾸고 2층도 올릴 수 있어요",
	"🔄 환생하면 코인은 0이 되지만 영구 보너스를 받아요",
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
			i = i % #TIPS + 1
			label.Text = TIPS[i]
			banner.Visible = true
			UiKit.Pop(banner, 0.35)
			task.wait(INTERVAL)
		end
		UiKit.Tween(UiKit.Scale(banner), 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.3)
		banner:Destroy()
	end)
end

return Tips
