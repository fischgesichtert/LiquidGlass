-- Screen-edge pinning and locking of the tab bar.
if getgenv().LGDocShot then
	getgenv().LGDocShot.restore()
end
getgenv().LiquidGlassSkipIntro = true
local LiquidGlass = loadstring(readfile("LiquidGlass/LiquidGlass.lua"))()
local Window = LiquidGlass:CreateWindow({
	Title = "Screen Bar",
	Icon = "apps",
	Navigation = "TabBar",
	TabBar = { Position = "Bottom", Screen = true },
	Size = Vector2.new(640, 440),
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
local vs = workspace.CurrentCamera.ViewportSize
local function rect()
	task.wait(0.9)
	local p, s = bar.Root.AbsolutePosition, bar.Root.AbsoluteSize
	return p, s, string.format("pos %d,%d size %d,%d vp %d,%d", p.X, p.Y, s.X, s.Y, vs.X, vs.Y)
end
local inset = game:GetService("GuiService"):GetGuiInset().Y

local p, s, info = rect()
check("bottom: centered", math.abs(p.X + s.X / 2 - vs.X / 2) < 3, info)
-- 14 px from the bottom, or above the backpack hotbar while the player has tools
local me = game:GetService("Players").LocalPlayer
local hotbar = me.Backpack:FindFirstChildOfClass("Tool") or (me.Character and me.Character:FindFirstChildOfClass("Tool"))
local gap = vs.Y - inset - (p.Y + s.Y)
check("bottom: on screen edge", math.abs(gap - (hotbar and 76 or 14)) < 4, info .. " gap " .. gap)
check("screen flag", bar.Screen == true and bar.Floating == true)

Window:PinTabBar("Left")
p, s, info = rect()
check("left: at screen edge", p.X < 30, info)
check("left: vertical", s.Y > s.X, info)

Window:PinTabBar("Top")
p, s, info = rect()
check("top: below topbar", p.Y >= -inset and p.Y < 40, info)

Window:PinTabBar("Right")
p, s, info = rect()
check("right: at screen edge", vs.X - (p.X + s.X) < 30, info)

-- lock: grip goes away, next() does nothing
Window:PinTabBar("Bottom")
rect()
check("grip before lock", bar.GripFrame ~= nil)
Window:LockTabBar(true)
p, s, info = rect()
check("lock hides grip", bar.GripFrame == nil and bar.Locked == true)
check("locked still pinned", bar.Screen == true and bar.Position == "Bottom", info)
bar:next()
task.wait(0.5)
check("locked ignores next()", bar.Position == "Bottom")
Window:LockTabBar(false)
rect()
check("unlock restores grip", bar.GripFrame ~= nil and not bar.Locked)

-- unpin: floats next to the window again
Window:UnpinTabBar()
p, s, info = rect()
local wp, ws = Window.Root.AbsolutePosition, Window.Root.AbsoluteSize
check("unpinned floats by window", bar.Screen == false and bar.Floating == true and p.Y >= wp.Y + ws.Y - 2 and p.Y < wp.Y + ws.Y + 40, info)

-- drop near screen edge pins
bar:drop(Vector2.new(vs.X - 20, vs.Y / 2))
p, s, info = rect()
check("drop at right screen edge pins", bar.Screen == true and bar.Position == "Right", info)
bar:drop(Window.Root.AbsolutePosition + Window.Root.AbsoluteSize / 2)
rect()
check("drop on window docks", bar.Screen == false and bar.Floating == false)

-- attach / detach keep working
Window:PinTabBar("Bottom")
rect()
Window:AttachTabBar()
rect()
check("attach clears screen", bar.Screen == false and bar.Floating == false)
Window:PinTabBar("Bottom")
rect()

local moved = {}
bar.OnMoved = function(...)
	moved = { ... }
end
Window:PinTabBar("Left")
rect()
check("OnMoved has screen flag", moved[1] == "Left" and moved[3] == true, tostring(moved[1]) .. " " .. tostring(moved[3]))
Window:PinTabBar("Bottom")
rect()

table.insert(out, 1, ("screenbar: %d failed"):format(fails))
return table.concat(out, "\n")
