getgenv().LiquidGlassSkipIntro = true
-- Functional test: reloads the demo, drives every element with real input events
-- (only ever on visible LiquidGlass UI, only keys no game uses) and returns a report.
local T = loadstring(readfile("LiquidGlass/harness.lua"))()
local LogService = game:GetService("LogService")
local GuiService = game:GetService("GuiService")

local report, failures = {}, 0
local function check(name, ok, detail)
	if not ok then
		failures += 1
	end
	table.insert(report, (ok and "PASS " or "FAIL ") .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or ""))
end

-- only errors from LiquidGlass count; the game's own errors are listed separately
local errors, gameErrors = {}, {}
local logConn = LogService.MessageOut:Connect(function(msg, kind)
	local ours = msg:find("LiquidGlass") or msg:find('%[string "%-%-!nocheck') or msg:find("harness") or msg:find("functional")
	if kind == Enum.MessageType.MessageError or (kind == Enum.MessageType.MessageWarning and ours) then
		table.insert(ours and errors or gameErrors, msg:sub(1, 200))
	end
end)

local function escape()
	T.key(Enum.KeyCode.Escape)
	task.wait(0.35)
	local opened = GuiService.MenuIsOpen
	if opened then
		T.key(Enum.KeyCode.Escape)
		task.wait(0.4)
	end
	return not opened
end

-- fresh start
-- the example loads the published library; test the local build instead
loadstring((readfile("LiquidGlass/example.lua"):gsub('loadstring%(game:HttpGet%(".-"%)%)%(%)', 'loadstring(readfile("LiquidGlass/LiquidGlass.lua"))()', 1)))()
task.wait(1.2)
local lib = T.lib()
local w = lib.Windows[1]
lib.ToggleKey = Enum.KeyCode.KeypadZero -- never a key the game listens to
T.refused = 0

local function outside()
	-- a point on the window glass that is not a control: the sidebar's empty middle
	return T.at(w.TabList, 0.5, 0.92)
end

-- Tabs ---------------------------------------------------------------------
for i = #w.Tabs, 1, -1 do
	T.click(w.Tabs[i].Button)
	task.wait(0.5)
	check("tab click " .. w.Tabs[i].Title, w.ActiveTab == w.Tabs[i])
end
local UIS = game:GetService("UserInputService")
local dragLog = {}
local lc1 = UIS.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		table.insert(dragLog, "B" .. math.floor(i.Position.Y + 58))
	end
end)
local lc2 = UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		table.insert(dragLog, "E" .. math.floor(i.Position.Y + 58))
	end
end)
local moves = 0
local lc3 = UIS.InputChanged:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseMovement then
		moves += 1
	end
end)
local a0, b0 = T.center(w.Tabs[1].Button), T.center(w.Tabs[3].Button)
T.drag(w.Tabs[1].Button, w.Tabs[3].Button, 16)
task.wait(0.6)
lc1:Disconnect()
lc2:Disconnect()
lc3:Disconnect()
check("tab drag lens Home->Media", w.ActiveTab == w.Tabs[3], w.ActiveTab.Title .. " " .. math.floor(a0.Y) .. ">" .. math.floor(b0.Y) .. " " .. table.concat(dragLog, ",") .. " moves=" .. moves .. " focus=" .. tostring(UIS:GetFocusedTextBox()) .. " fps=" .. math.floor(workspace:GetRealPhysicsFPS()))
check("tab pill rests on active tab", math.abs(w.TabPill.Root.AbsolutePosition.Y - w.Tabs[3].Button.AbsolutePosition.Y) < 2)
check("tab pill keeps its size", math.abs(w.TabPill.Root.AbsoluteSize.Y - w.Tabs[3].Button.AbsoluteSize.Y) < 2, w.TabPill.Root.AbsoluteSize.Y)
T.drag(w.Tabs[3].Button, T.center(w.Tabs[1].Button) - Vector2.new(0, 80), 16)
task.wait(0.6)
check("tab drag past the first tab selects it", w.ActiveTab == w.Tabs[1], w.ActiveTab.Title)

-- Toggles --------------------------------------------------------------------
local wifi = T.el("Wi-Fi")
T.reveal(wifi)
local cb
wifi:OnChanged(function(v)
	cb = v
end)
task.wait(0.1)
local before = wifi.Value
cb = nil
T.click(wifi.Switch.Root)
task.wait(0.5)
check("toggle click flips + callback", wifi.Value == not before and cb == wifi.Value)
T.click(T.at(wifi.Row.Frame, 0.3, 0.5))
task.wait(0.5)
check("toggle row click flips back", wifi.Value == before)
local air = T.el("Airplane Mode")
T.reveal(air)
air:Set(false)
task.wait(0.4)
local sw = air.Switch.Root
T.drag(T.at(sw, 0.3, 0.5), T.at(sw, 0.3, 0.5) + Vector2.new(30, 0), 10)
task.wait(0.6)
check("toggle drag on", air.Value == true)
T.drag(T.at(sw, 0.7, 0.5), T.at(sw, 0.7, 0.5) - Vector2.new(30, 0), 10)
task.wait(0.6)
check("toggle drag off", air.Value == false)
local knob = sw:FindFirstChild("Knob")
check("knob rests at off", math.abs(knob.Position.X.Offset - 2) < 0.5, knob.Position.X.Offset)
check("knob keeps its size", knob.Size == UDim2.fromOffset(38, 24), tostring(knob.Size))
T.drag(T.at(sw, 0.3, 0.5), T.at(sw, 0.3, 0.5) + Vector2.new(3, 0), 3)
task.wait(0.6)
check("tiny drag acts as tap", air.Value == true)
T.drag(T.at(sw, 0.7, 0.5), T.at(sw, 0.7, 0.5) - Vector2.new(6, 0), 4)
task.wait(0.6)
check("short drag snaps back to on", air.Value == true and math.abs(knob.Position.X.Offset - 22) < 0.5, knob.Position.X.Offset)
air:Set(false)
task.wait(0.5)

-- Segmented ------------------------------------------------------------------
local seg = T.el("Appearance")
T.reveal(seg)
local segFrame = seg.Row.Body:FindFirstChild("Segmented")
T.click(T.at(segFrame, 0.75, 0.5))
task.wait(0.7)
check("segmented click Light", seg.Value == "Light" and lib.Settings.Theme == "Light", seg.Value)
T.drag(T.at(segFrame, 0.75, 0.5), T.at(segFrame, 0.25, 0.5), 12)
task.wait(0.7)
check("segmented drag back to Dark", seg.Value == "Dark" and lib.Settings.Theme == "Dark", seg.Value)

-- Sliders ----------------------------------------------------------------------
local sp = T.el("Walk speed")
T.reveal(sp)
local track = sp.Row.Body:FindFirstChild("Slider"):FindFirstChild("Track")
-- the knob's center travels between the track ends inset by half a knob
local function along(f)
	local half = lib.Metrics.KnobW / 2 * lib.ScaleObject.Scale
	local p = T.at(track, 0, 0.5)
	return p + Vector2.new(half + f * (track.AbsoluteSize.X - 2 * half), 0)
end
T.drag(along(0), along(0.75), 14)
task.wait(0.3)
check("slider drag to 75%", math.abs(sp.Value - (16 + 0.75 * 104)) <= 1, sp.Value)
T.click(along(0.25))
task.wait(0.3)
check("slider click 25%", math.abs(sp.Value - (16 + 0.25 * 104)) <= 1, sp.Value)
T.drag(along(0.5), along(1.6), 10)
task.wait(0.3)
check("slider clamps at max", sp.Value == 120, sp.Value)
T.drag(along(0.5), along(-0.8), 10)
task.wait(0.3)
check("slider clamps at min", sp.Value == 16, sp.Value)
local box = sp.Row.Frame:FindFirstChild("Value")
T.click(box)
task.wait(0.2)
check("slider value box focuses", box:IsFocused())
T.enter(box, "50")
task.wait(0.3)
check("slider typed value", sp.Value == 50 and box.Text == "50", tostring(sp.Value) .. " '" .. box.Text .. "'")
T.enter(box, "999")
task.wait(0.3)
check("slider typed value clamps", sp.Value == 120 and box.Text == "120", tostring(sp.Value) .. " '" .. box.Text .. "'")
T.enter(box, "abc")
task.wait(0.2)
check("slider ignores garbage", sp.Value == 120 and box.Text == "120", box.Text)
local fov = T.el("Field of view")
check("slider suffix label", fov.Row.Frame:FindFirstChild("Value").Text:find("°") ~= nil, fov.Row.Frame:FindFirstChild("Value").Text)
fov:Set(70)

-- Stepper ----------------------------------------------------------------------
local st = T.el("Jump count")
T.reveal(st)
local plus, minus
for _, d in ipairs(st.Row.Right:GetDescendants()) do
	if d:IsA("TextButton") then
		if d.Position.X.Scale == 1 then
			plus = d
		else
			minus = d
		end
	end
end
local s0 = st.Value
T.click(plus)
T.click(plus)
task.wait(0.2)
check("stepper +2", st.Value == s0 + 2, st.Value)
for _ = 1, 20 do
	T.click(minus, 0.01)
end
task.wait(0.2)
check("stepper clamps at min", st.Value == 0, st.Value)

-- Dropdowns --------------------------------------------------------------------
local function menuItems(menu)
	local items = {}
	if menu then
		for _, d in ipairs(menu.Root:GetDescendants()) do
			if d:IsA("TextButton") and d.Name == "Item" then
				table.insert(items, d)
			end
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return items
end
local dd = T.el("Weapon")
T.reveal(dd)
T.click(T.at(dd.Row.Frame, 0.5, 0.5))
task.wait(0.5)
check("dropdown opens menu", dd.Menu ~= nil)
local items = menuItems(dd.Menu)
check("dropdown lists all options", #items == 5, #items)
if items[3] then
	T.click(items[3])
	task.wait(0.5)
end
check("dropdown pick sets value", dd.Value == "Staff", dd.Value)
check("dropdown closes after pick", dd.Menu == nil)
T.click(T.at(dd.Row.Frame, 0.5, 0.5))
task.wait(0.4)
T.click(outside())
task.wait(0.5)
check("dropdown closes on outside click", dd.Menu == nil)
T.click(T.at(dd.Row.Frame, 0.5, 0.5))
task.wait(0.4)
local esc = escape()
check("dropdown closes on Escape", dd.Menu == nil)
check("Roblox menu closed again after Escape", not GuiService.MenuIsOpen)
T.click(T.at(dd.Row.Frame, 0.5, 0.5))
task.wait(0.4)
T.click(T.at(dd.Row.Frame, 0.5, 0.5))
task.wait(0.4)
check("dropdown reopen/close by clicking the row twice", dd.Menu == nil)

local md = T.el("Targets")
T.reveal(md)
T.click(T.at(md.Row.Frame, 0.5, 0.5))
task.wait(0.5)
local mitems = menuItems(md.Menu)
if mitems[2] then
	T.click(mitems[2])
	task.wait(0.3)
	T.click(mitems[3])
	task.wait(0.3)
end
check("multi dropdown stays open", md.Menu ~= nil)
local v = md.Value or {}
check("multi dropdown toggles", #v == 2 and table.find(v, "NPCs") ~= nil and table.find(v, "Players") ~= nil, table.concat(v, ","))
T.click(outside())
task.wait(0.4)
check("multi dropdown closes on outside click", md.Menu == nil)

local search = T.el("Teleport to player")
T.reveal(search)
T.click(T.at(search.Row.Frame, 0.5, 0.5))
task.wait(0.5)
local sbox = search.Menu and search.Menu.Root:FindFirstChildWhichIsA("TextBox", true)
check("searchable dropdown has a search field", sbox ~= nil)
if sbox then
	T.enter(sbox, "zzzz_nobody")
	task.wait(0.2)
	local shown = 0
	for _, it in ipairs(menuItems(search.Menu)) do
		if it.Visible then
			shown += 1
		end
	end
	check("dropdown search filters", shown == 0, shown)
end
T.click(outside())
task.wait(0.4)

-- Inputs ---------------------------------------------------------------------
local inp = T.el("Display name")
T.reveal(inp)
local got
inp.Callback = function(t)
	got = t
end
T.click(inp.Box)
task.wait(0.2)
check("input focuses", inp.Box:IsFocused())
T.enter(inp.Box, "hello")
task.wait(0.3)
check("input callback on enter", got == "hello", got)
check("input value stored", inp.Value == "hello", inp.Value)

-- Keybinds -------------------------------------------------------------------
local kb = T.el("Fly")
T.reveal(kb)
local state
kb.Callback = function(s)
	state = s
end
T.click(T.at(kb.Row.Frame, 0.5, 0.5))
task.wait(0.2)
T.key(Enum.KeyCode.KeypadNine)
task.wait(0.3)
check("keybind captures key", kb.Value == "KeypadNine", kb.Value)
state = nil
T.key(Enum.KeyCode.KeypadNine)
task.wait(0.2)
check("keybind fires toggle", state == true, state)
T.key(Enum.KeyCode.KeypadNine)
task.wait(0.2)
check("keybind toggles off", state == false, state)
T.click(T.at(kb.Row.Frame, 0.5, 0.5))
task.wait(0.2)
esc = escape()
check("keybind escape keeps key", kb.Value == "KeypadNine", kb.Value)
check("Roblox menu closed again after Escape (capture)", not GuiService.MenuIsOpen)
local hold = T.el("Sprint")
hold:Set(Enum.KeyCode.KeypadEight)
local hs = {}
hold.Callback = function(s)
	table.insert(hs, tostring(s))
end
T.key(Enum.KeyCode.KeypadEight, 0.2)
task.wait(0.2)
check("hold keybind press+release", table.concat(hs, ",") == "true,false", table.concat(hs, ","))

-- Color picker -----------------------------------------------------------------
local cp = T.el("ESP color")
T.reveal(cp)
T.click(T.at(cp.Row.Frame, 0.5, 0.5))
task.wait(0.5)
check("color picker opens", cp.Picker ~= nil)
if cp.Picker then
	local sv = cp.Picker.Root:FindFirstChild("SV", true)
	T.drag(T.at(sv, 0.5, 0.5), T.at(sv, 0.95, 0.05), 8)
	task.wait(0.3)
	local _, s, val = cp.Value:ToHSV()
	check("color picker SV drag", s > 0.85 and val > 0.85, string.format("%.2f %.2f", s, val))
	local hue = cp.Picker.Root:FindFirstChild("Hue", true)
	T.click(T.at(hue, 0.33, 0.5))
	task.wait(0.3)
	local h = cp.Value:ToHSV()
	check("color picker hue click", math.abs(h - 0.33) < 0.04, string.format("%.2f", h))
	local field = cp.Picker.Root:FindFirstChildWhichIsA("TextBox", true)
	T.enter(field, "#FF0000")
	task.wait(0.2)
	check("color picker hex entry", cp.Value == Color3.fromRGB(255, 0, 0), tostring(cp.Value))
	T.click(outside())
	task.wait(0.4)
end
check("color picker closes", cp.Picker == nil)

-- Buttons ----------------------------------------------------------------------
local fired = 0
local rb = T.el("Rejoin server")
T.reveal(rb)
rb.Callback = function()
	fired += 1
end
T.click(T.at(rb.Row.Frame, 0.4, 0.5))
task.wait(0.3)
check("row button fires once", fired == 1, fired)
local locked = T.el("Locked feature")
T.reveal(locked)
local lv = locked.Value
T.click(T.at(locked.Row.Frame, 0.5, 0.5))
task.wait(0.4)
check("disabled element ignores clicks", locked.Value == lv)
locked:SetDisabled(false)
task.wait(0.1)
T.click(T.at(locked.Row.Frame, 0.5, 0.5))
task.wait(0.4)
check("re-enabled element works", locked.Value ~= lv)
check("re-enabled row keeps its layout", locked.Row.Frame:FindFirstChild("Line") ~= nil and locked.Row.Frame:FindFirstChild("Locked") == nil and math.abs(locked.Row.Frame.AbsoluteSize.Y / lib.ScaleObject.Scale - 58) < 8, locked.Row.Frame.AbsoluteSize.Y)

-- Search -----------------------------------------------------------------------
T.enter(w.SearchBox, "walk")
task.wait(0.4)
local visibleRows = 0
for _, el in ipairs(w.ActiveTab.Elements) do
	if el.Row and el.Row.Frame.Visible then
		visibleRows += 1
	end
end
check("search filters rows", visibleRows == 1, visibleRows)
T.enter(w.SearchBox, "")
task.wait(0.4)
local all = 0
for _, el in ipairs(w.ActiveTab.Elements) do
	if el.Row and el.Row.Frame.Visible and not el._hidden then
		all += 1
	end
end
check("search clear restores rows", all == #w.ActiveTab.Elements, all .. "/" .. #w.ActiveTab.Elements)
check("search clear restores title", w.PageTitle.Text == w.ActiveTab.Title, w.PageTitle.Text)

-- Notifications and dialog ------------------------------------------------------
T.click(w.Tabs[1].Button)
task.wait(0.5)
local n = lib:Notify({ Title = "Test", Content = "Swipe me", Duration = 30 })
task.wait(0.8)
local nroot = n.Glass.Root
T.drag(T.at(nroot, 0.5, 0.5), T.at(nroot, 0.5, 0.5) + Vector2.new(160, 0), 10)
task.wait(0.8)
check("notification swipe dismisses", n.Closed == true)
local burst = {}
for i = 1, 6 do
	burst[i] = lib:Notify({ Title = "Burst " .. i, Duration = 1 })
end
task.wait(2.5)
local open = 0
for _, b in ipairs(burst) do
	if not b.Closed then
		open += 1
	end
end
check("notification burst expires", open == 0, open)
local d = w:Dialog({ Title = "Q", Buttons = { { Title = "A", Style = "Primary" }, { Title = "B", Style = "Cancel" } } })
task.wait(0.6)
esc = escape()
check("dialog closes on Escape", d.Closed == true)
check("Roblox menu closed again after Escape (dialog)", not GuiService.MenuIsOpen)

-- Window drag, resize, collapse, minimize, toggle key ---------------------------------
local p0 = w.Root.AbsolutePosition
T.drag(T.at(w.Header, 0.3, 0.5), T.at(w.Header, 0.3, 0.5) + Vector2.new(-60, 40), 12)
task.wait(0.8)
local p1 = w.Root.AbsolutePosition
check("window drag moves", (p1 - p0 - Vector2.new(-60, 40)).Magnitude < 3, tostring(p1 - p0))
local size0 = w.Root.AbsoluteSize
local cornerZone = w.ResizeZones[1]
T.drag(cornerZone, T.center(cornerZone) - Vector2.new(200, 100), 14)
task.wait(0.6)
local size1 = w.Root.AbsoluteSize
check("resize shrinks", size1.X < size0.X - 150 and size1.Y < size0.Y - 60, tostring(size1))
check("sidebar collapses when narrow", w.Collapsed == true, w.Root.Size.X.Offset)
T.click(w.Tabs[2].Button)
task.wait(0.5)
check("tab click works when collapsed", w.ActiveTab == w.Tabs[2])
check("pill fits collapsed sidebar", w.TabPill.Root.AbsoluteSize.X < 60 and math.abs(w.TabPill.Root.AbsoluteSize.Y - 36) < 2, tostring(w.TabPill.Root.AbsoluteSize))
T.drag(cornerZone, T.center(cornerZone) - Vector2.new(800, 800), 14)
task.wait(0.5)
check("resize respects MinSize", w.Root.Size.X.Offset >= 480 and w.Root.Size.Y.Offset >= 340, tostring(w.Root.Size))
T.drag(cornerZone, T.center(cornerZone) + Vector2.new(320, 200), 14)
task.wait(0.6)
check("sidebar expands when wide", w.Collapsed == false, w.Root.Size.X.Offset)
check("pill fits expanded sidebar", w.TabPill.Root.AbsoluteSize.X > 150, tostring(w.TabPill.Root.AbsoluteSize))
T.click(w.MinimizeButton.Root)
task.wait(0.8)
check("minimize hides window", w.Minimized == true and w.Root.Visible == false and w.Pill and w.Pill.Root.Visible)
T.click(w.Pill.Root)
task.wait(0.9)
check("pill restores window", w.Minimized == false and w.Root.Visible == true)
T.key(Enum.KeyCode.KeypadZero)
task.wait(0.6)
check("toggle key hides", w.Root.Visible == false)
T.key(Enum.KeyCode.KeypadZero)
task.wait(0.8)
check("toggle key shows", w.Root.Visible == true)
T.key(Enum.KeyCode.KeypadZero)
T.key(Enum.KeyCode.KeypadZero)
T.key(Enum.KeyCode.KeypadZero)
task.wait(0.9)
check("rapid toggling ends in a consistent state", w.Root.Visible == w.Visible, tostring(w.Root.Visible) .. "/" .. tostring(w.Visible))
if not w.Visible then
	T.key(Enum.KeyCode.KeypadZero)
	task.wait(0.8)
end
local fades = 0
for _, dsc in ipairs(lib.Gui:GetDescendants()) do
	if dsc.Name == "LGFade" then
		fades += 1
	end
end
check("no leftover fade groups", fades == 0, fades)

-- Close prompt ------------------------------------------------------------------
T.click(w.CloseButton.Root)
task.wait(0.6)
check("close shows dialog", lib.Gui:FindFirstChild("Dialog") ~= nil)
local shade = w.Glass.Content:FindFirstChild("DialogShade")
if shade then
	T.click(T.at(shade, 0.03, 0.97))
	task.wait(0.5)
end
check("dialog closes on shade click", lib.Gui:FindFirstChild("Dialog") == nil and w.Root.Visible)

-- Theme + config ---------------------------------------------------------------
lib:SetTheme("Light")
task.wait(0.5)
lib:SetTheme("Dark")
local okSave = lib:SaveConfig("test_cfg")
local wv = wifi.Value
wifi:Set(not wv)
local okLoad = lib:LoadConfig("test_cfg")
task.wait(0.3)
check("config save/load roundtrip", okSave and okLoad and wifi.Value == wv, tostring(okSave) .. " " .. tostring(okLoad))
lib:DeleteConfig("test_cfg")

task.wait(0.5)
logConn:Disconnect()
check("never clicked outside LiquidGlass", T.refused == 0, T.refused)
check("Roblox menu closed", not GuiService.MenuIsOpen)
check("no LiquidGlass errors", #errors == 0, table.concat(errors, " || "))
table.insert(report, "INFO game errors during run: " .. #gameErrors)
table.insert(report, 1, string.format("%d checks, %d failures", #report, failures))
return table.concat(report, "\n")
