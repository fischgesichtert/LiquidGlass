-- Screenshot helper for the dock: opens a window with a pinned tab bar and
-- exposes getgenv().DockHold(edge, align, target) to hold a grip drag mid-way
-- (getgenv().DockRelease() lets go).
getgenv().LiquidGlassSkipIntro = true
local LiquidGlass = loadstring(readfile("LiquidGlass/LiquidGlass.lua"))()
local Window = LiquidGlass:CreateWindow({
	Title = "Dock",
	Icon = "apps",
	Navigation = "TabBar",
	TabBar = { Position = "Bottom", Screen = true },
	Size = Vector2.new(600, 400),
})
for _, t in ipairs({ { "Home", "home" }, { "Search", "search" }, { "Library", "music" }, { "Profile", "user" } }) do
	local tab = Window:AddTab({ Title = t[1], Icon = t[2] })
	local s = tab:AddSection(t[1])
	s:AddToggle({ Title = "Toggle on " .. t[1], Default = true, Icon = t[2], IconColor = Color3.fromRGB(10, 132, 255) })
	s:AddSlider({ Title = "Slider", Default = 40 })
end
Window:AddSettingsTab()

local VIM = game:GetService("VirtualInputManager")
local T = loadstring(readfile("LiquidGlass/harness.lua"))()
local bar = Window:GetTabBar()
local last
getgenv().DockHold = function(edge, align, target)
	Window:PinTabBar(edge, align)
	task.wait(1.2)
	local a = T.center(bar.GripFrame)
	VIM:SendMouseMoveEvent(a.X, a.Y, game)
	task.wait(0.05)
	VIM:SendMouseButtonEvent(a.X, a.Y, 0, true, game, 1)
	task.wait(0.12)
	for i = 1, 30 do
		local p = a:Lerp(target, i / 30)
		VIM:SendMouseMoveEvent(p.X, p.Y, game)
		task.wait(1 / 60)
	end
	last = target
end
getgenv().DockRelease = function()
	if last then
		VIM:SendMouseButtonEvent(last.X, last.Y, 0, false, game, 1)
		last = nil
	end
end
getgenv().DockWindow = Window
return "ready"
