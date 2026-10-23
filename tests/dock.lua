-- Tab bar as a dock: screen corners (lying and standing), snap preview, bar
-- staying on screen while the window is away, and tabs opening the window
-- right next to the bar. Drives real input through the harness.
if getgenv().LGDocShot then
	getgenv().LGDocShot.restore()
end
getgenv().LiquidGlassSkipIntro = true
local LiquidGlass = loadstring(readfile("LiquidGlass/LiquidGlass.lua"))()
local T = loadstring(readfile("LiquidGlass/harness.lua"))()
local Window = LiquidGlass:CreateWindow({
	Title = "Dock",
	Icon = "apps",
	Navigation = "TabBar",
	TabBar = { Position = "Bottom", Screen = true },
	Size = Vector2.new(600, 400),
})
for _, t in ipairs({ { "Home", "home" }, { "Search", "search" }, { "Library", "music" }, { "Profile", "user" } }) do
	local tab = Window:AddTab({ Title = t[1], Icon = t[2] })
	tab:AddSection(t[1]):AddToggle({ Title = "Toggle on " .. t[1], Default = true })
end
Window:AddSettingsTab()

local out, fails = {}, 0
local function check(name, ok, info)
	if not ok then
		fails += 1
	end
	table.insert(out, (ok and "PASS " or "FAIL ") .. name .. (info and (" (" .. info .. ")") or ""))
end
local bar = Window:GetTabBar()
local sc = LiquidGlass.ScaleObject.Scale
local inset = game:GetService("GuiService"):GetGuiInset().Y
local vs = workspace.CurrentCamera.ViewportSize
-- rects in screen space (the gui ignores the inset; AbsolutePosition doesn't)
local function rect(gui)
	return gui.AbsolutePosition + Vector2.new(0, inset), gui.AbsoluteSize
end
local function settle(t)
	task.wait(t or 0.9)
end
local function fmt(p, s)
	return string.format("%d,%d %dx%d", p.X, p.Y, s.X, s.Y)
end

for _, name in ipairs({ "monitor", "lock", "eye-off", "external" }) do
	check("icon " .. name, LiquidGlass:GetIcon(name) ~= nil)
end

-- the window opens right above a bar pinned to the bottom
settle(1.2)
local bp, bs = rect(bar.Root)
local wp, ws = rect(Window.Root)
check("window opens above bar", math.abs((wp.Y + ws.Y) - (bp.Y - 12 * sc)) < 4 and math.abs((wp.X + ws.X / 2) - (bp.X + bs.X / 2)) < 4, fmt(wp, ws) .. " / " .. fmt(bp, bs))

-- corners, lying and standing
local cases = {
	{ "Bottom", "Left", false, function(p, s) return p.X < 30 and vs.Y - (p.Y + s.Y) < 30 end },
	{ "Left", "Bottom", true, function(p, s) return p.X < 30 and vs.Y - (p.Y + s.Y) < 30 end },
	{ "Top", "Right", false, function(p, s) return vs.X - (p.X + s.X) < 30 and p.Y < inset + 30 end },
	{ "Right", "Top", true, function(p, s) return vs.X - (p.X + s.X) < 30 and p.Y < inset + 30 end },
	{ "Right", "Bottom", true, function(p, s) return vs.X - (p.X + s.X) < 30 and vs.Y - (p.Y + s.Y) < 30 end },
	{ "Bottom", "Right", false, function(p, s) return vs.X - (p.X + s.X) < 30 and vs.Y - (p.Y + s.Y) < 30 end },
}
for _, c in ipairs(cases) do
	Window:PinTabBar(c[1], c[2])
	settle()
	local p, s = rect(bar.Root)
	local vert = s.Y > s.X
	check(("pin %s-%s"):format(c[1], c[2]), c[4](p, s) and vert == c[3], fmt(p, s))
	-- the window follows, lined up with the bar's corner
	local wp2, ws2 = rect(Window.Root)
	local overlap = wp2.X < p.X + s.X and p.X < wp2.X + ws2.X and wp2.Y < p.Y + s.Y and p.Y < wp2.Y + ws2.Y
	check(("window beside %s-%s"):format(c[1], c[2]), not overlap, fmt(wp2, ws2))
end

-- snap slot picking (pointer + bar position in gui pixels)
Window:PinTabBar("Bottom", "Center")
settle()
local m = bar.M.size
local function slot(pointer, at)
	local s2 = bar:snapSlot(pointer * sc, at)
	return s2 and (s2.Edge .. "-" .. s2.Align) or "none"
end
local v = vs / sc
check("snap bottom-left lying", slot(Vector2.new(m.X, v.Y - 30), Vector2.new(10, v.Y - m.Y - 10)) == "Bottom-Start", slot(Vector2.new(m.X, v.Y - 30), Vector2.new(10, v.Y - m.Y - 10)))
check("snap left-bottom standing", slot(Vector2.new(30, v.Y - 200), Vector2.new(-m.X / 2 + 40, v.Y - 260)) == "Left-End", slot(Vector2.new(30, v.Y - 200), Vector2.new(-m.X / 2 + 40, v.Y - 260)))
check("snap bottom middle", slot(Vector2.new(v.X / 2 + m.X / 2, v.Y - 20), Vector2.new(v.X / 2 - m.X / 2, v.Y - m.Y - 8)) == "Bottom-Center")
check("no snap mid-screen", slot(Vector2.new(v.X * 0.3 + m.X - 28, v.Y * 0.4 + 28), Vector2.new(v.X * 0.3, v.Y * 0.4)) == "none")
check("no snap on window", slot(T.center(Window.Root) / sc, T.center(Window.Root) / sc - m / 2) == "none")

-- real drag: grip to the bottom-left corner -> lies there
local grip = bar.GripFrame
local function dragGripTo(target)
	local a = T.center(bar.GripFrame)
	T.drag(a, target, 24, 0.12)
	settle(1.1)
end
dragGripTo(Vector2.new(bs.X - 30, vs.Y - 20))
check("drag to bottom-left lies", bar.Screen and bar.Position == "Bottom" and bar.Align == "Start", tostring(bar.Position) .. "-" .. tostring(bar.Align))
-- drag up along the left wall -> stands in the corner
dragGripTo(Vector2.new(20, vs.Y - 120))
check("drag up the left wall stands", bar.Screen and bar.Position == "Left" and bar.Align == "End", tostring(bar.Position) .. "-" .. tostring(bar.Align))
check("ghost gone after drop", not bar.GhostKey)
dragGripTo(Vector2.new(vs.X - 20, vs.Y / 2 + 150))
check("drag to right edge middle", bar.Screen and bar.Position == "Right" and bar.Align == "Center", tostring(bar.Position) .. "-" .. tostring(bar.Align))
Window:PinTabBar("Bottom", "Center")
settle()

-- the bar stays while the window is hidden; a tab brings the window back next to it
Window:SetVisible(false)
settle(0.6)
check("bar stays when window hides", bar.Shown and bar.Root.Visible)
Window:Center()
settle(0.8)
local tabs = Window.Tabs
T.click(T.center(tabs[2].Button))
settle(1)
bp, bs = rect(bar.Root)
wp, ws = rect(Window.Root)
check("tab reopens window", Window:IsVisible() and Window.ActiveTab == tabs[2])
check("reopened above bar", math.abs((wp.Y + ws.Y) - (bp.Y - 12 * sc)) < 4, fmt(wp, ws) .. " / " .. fmt(bp, bs))

-- minimize: no pill, the bar brings it back
Window:Minimize()
settle(0.6)
check("minimize keeps bar", bar.Root.Visible and not (Window.Pill and Window.Pill.Root.Visible))
T.click(T.center(tabs[1].Button))
settle(0.9)
check("tab restores minimized window", Window:IsVisible() and not Window.Minimized)

-- opting out: HideWithWindow, SetTabBarVisible
Window:SetTabBar({ HideWithWindow = true })
settle(0.5)
Window:SetVisible(false)
settle(0.6)
check("HideWithWindow hides bar", not bar.Root.Visible)
Window:SetVisible(true)
settle(0.6)
check("bar back with window", bar.Root.Visible)
Window:SetTabBar({ HideWithWindow = false })
settle(0.5)
Window:SetTabBarVisible(false)
settle(0.5)
check("SetTabBarVisible(false)", not bar.Root.Visible)
Window:SetTabBarVisible(true)
settle(0.5)
check("SetTabBarVisible(true)", bar.Root.Visible)

-- docked bars are part of the window
Window:AttachTabBar()
settle()
Window:SetVisible(false)
settle(0.6)
check("docked bar hides with window", not bar.Shown)
Window:SetVisible(true)
settle(0.6)
check("docked bar shows with window", bar.Shown and bar.Root.Visible)
Window:PinTabBar("Bottom", "Center")
settle()

check("no script errors", true)
table.insert(out, 1, ("dock: %d failed"):format(fails))
return table.concat(out, "\n")
