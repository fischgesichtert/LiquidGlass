-- Quick tab bar playground used while developing; see demo.lua for the full demo.
local LiquidGlass = loadstring(readfile("LiquidGlass/LiquidGlass.lua"))()
LiquidGlass._intro.Played = (getgenv().LGSkipIntro == true)
local cfg = getgenv().LGBarCfg or { Position = "Bottom" }
local Window = LiquidGlass:CreateWindow({
	Title = "Tab Bar",
	Icon = "apps",
	Navigation = "TabBar",
	TabBar = cfg,
	Size = Vector2.new(680, 480),
	Density = getgenv().LGDensity,
})
local tabs = {
	{ "Home", "home" }, { "Search", "search" }, { "Library", "music" }, { "Profile", "user" }, { "Settings", "settings" },
}
for _, t in ipairs(tabs) do
	local tab = Window:AddTab({ Title = t[1], Icon = t[2] })
	local s = tab:AddSection(t[1])
	s:AddToggle({ Title = "A toggle on " .. t[1], Default = true, Icon = t[2], IconColor = Color3.fromRGB(10, 132, 255) })
	s:AddSlider({ Title = "Slider", Default = 40 })
	s:AddDropdown({ Title = "Dropdown", Options = { "One", "Two", "Three" }, Default = "Two" })
	s:AddButton({ Title = "Button", Style = "Primary" })
end
return Window
