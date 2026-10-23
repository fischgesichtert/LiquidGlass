-- Test helpers driven through VirtualInputManager (real engine input events).
local VIM = game:GetService("VirtualInputManager")
local T = {}

function T.lib()
	return getgenv().LiquidGlass
end

function T.center(gui)
	local lib = T.lib()
	return gui.AbsolutePosition - lib.Gui.AbsolutePosition + gui.AbsoluteSize / 2
end

function T.at(gui, fx, fy)
	local lib = T.lib()
	return gui.AbsolutePosition - lib.Gui.AbsolutePosition + gui.AbsoluteSize * Vector2.new(fx, fy)
end

function T.move(p)
	VIM:SendMouseMoveEvent(p.X, p.Y, game)
	task.wait()
end

function T.click(target, hold)
	local p = typeof(target) == "Vector2" and target or T.center(target)
	T.move(p)
	task.wait(0.03)
	VIM:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 1)
	task.wait(hold or 0.05)
	VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 1)
	task.wait(0.08)
end

function T.drag(a, b, steps, hold)
	a = typeof(a) == "Vector2" and a or T.center(a)
	b = typeof(b) == "Vector2" and b or T.center(b)
	-- the real mouse can't leave the game window either
	local vs = workspace.CurrentCamera.ViewportSize
	b = Vector2.new(math.clamp(b.X, 1, vs.X - 1), math.clamp(b.Y, 1, vs.Y + 57))
	T.move(a)
	VIM:SendMouseButtonEvent(a.X, a.Y, 0, true, game, 1)
	task.wait(hold or 0.08)
	steps = steps or 12
	for i = 1, steps do
		local p = a:Lerp(b, i / steps)
		VIM:SendMouseMoveEvent(p.X, p.Y, game)
		task.wait(1 / 60)
	end
	task.wait(0.05)
	VIM:SendMouseButtonEvent(b.X, b.Y, 0, false, game, 1)
	task.wait(0.1)
end

function T.key(code, hold)
	VIM:SendKeyEvent(true, code, false, game)
	task.wait(hold or 0.04)
	VIM:SendKeyEvent(false, code, false, game)
	task.wait(0.05)
end

function T.type(text)
	local digits = { [0] = Enum.KeyCode.Zero, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }
	for c in text:gmatch(".") do
		local code
		local digit = tonumber(c)
		if digit then
			code = digits[digit]
		elseif c == " " then
			code = Enum.KeyCode.Space
		elseif c == "." then
			code = Enum.KeyCode.Period
		elseif c == "-" then
			code = Enum.KeyCode.Minus
		else
			local ok, k = pcall(function()
				return Enum.KeyCode[c:upper()]
			end)
			code = ok and k or nil
		end
		if code then
			T.key(code, 0.02)
		end
	end
end

-- true when p lies on a visible part of LiquidGlass (never on game/Roblox UI):
-- inside a window, popover, dialog, notification or pill, and inside every
-- clipping ancestor of the topmost LiquidGlass object there
function T.onOurGui(p)
	local lib = T.lib()
	local function inside(gui)
		local pos = gui.AbsolutePosition - lib.Gui.AbsolutePosition
		local s = gui.AbsoluteSize
		return p.X >= pos.X and p.Y >= pos.Y and p.X <= pos.X + s.X and p.Y <= pos.Y + s.Y
	end
	for _, root in ipairs(lib.Gui:GetChildren()) do
		if root:IsA("GuiObject") and root.Visible and root.Name ~= "Notifications" and inside(root) then
			return true
		end
	end
	for _, n in ipairs(lib.Gui.Notifications:GetChildren()) do
		if n:IsA("GuiObject") and n.Visible and inside(n) then
			return true
		end
	end
	return false
end

local function visibleIn(gui, p)
	local o = gui.Parent
	local lib = T.lib()
	while o and o ~= lib.Gui do
		if o:IsA("GuiObject") and (o.ClipsDescendants or o:IsA("ScrollingFrame")) then
			local pos = o.AbsolutePosition - lib.Gui.AbsolutePosition
			local s = o.AbsoluteSize
			if not (p.X >= pos.X and p.Y >= pos.Y and p.X <= pos.X + s.X and p.Y <= pos.Y + s.Y) then
				return false
			end
		end
		o = o.Parent
	end
	return true
end
T.visibleIn = visibleIn

T.refused = 0
local rawClick, rawDrag = T.click, T.drag
function T.click(target, hold)
	local p = typeof(target) == "Vector2" and target or T.center(target)
	if not T.onOurGui(p) or (typeof(target) ~= "Vector2" and not visibleIn(target, p)) then
		T.refused += 1
		return false
	end
	rawClick(p, hold)
	return true
end
function T.drag(a, b, steps, hold)
	local pa = typeof(a) == "Vector2" and a or T.center(a)
	if not T.onOurGui(pa) or (typeof(a) ~= "Vector2" and not visibleIn(a, pa)) then
		T.refused += 1
		return false
	end
	rawDrag(pa, typeof(b) == "Vector2" and b or T.center(b), steps, hold)
	return true
end

-- scrolls an element's page so the element is fully visible
function T.reveal(el)
	local tab = el.Section.Tab
	if tab.Window.ActiveTab ~= tab then
		rawClick(T.center(tab.Button))
		task.wait(0.5)
	end
	local page = tab.Page
	local rowTop = el.Row.Frame.AbsolutePosition.Y - page.AbsolutePosition.Y + page.CanvasPosition.Y
	tab.Scroller.scrollTo(rowTop - 30, true)
	task.wait(0.15)
end

-- text entry: VirtualInputManager can't type into TextBoxes, so set the text the
-- way a user would leave it and submit with Enter
function T.enter(box, text)
	box:CaptureFocus()
	task.wait(0.05)
	box.Text = text
	task.wait(0.05)
	box:ReleaseFocus(true)
	task.wait(0.1)
end

-- finds an element by title in the active window
function T.el(title)
	for _, tab in ipairs(T.lib().Windows[1].Tabs) do
		for _, e in ipairs(tab.Elements) do
			if e.TitleText == title then
				return e, tab
			end
		end
	end
end

getgenv().LGT = T
return T
