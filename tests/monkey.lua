getgenv().LiquidGlassSkipIntro = true
-- Monkey test: random presses, drags, scrolls, keys and text on visible
-- LiquidGlass UI only, with invariant checks between bursts.
-- usage: local M = loadstring(readfile("LiquidGlass/monkey.lua"))(); M.setup(seed); M.run(n); M.report()
local T = loadstring(readfile("LiquidGlass/harness.lua"))()
local LogService = game:GetService("LogService")
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")
local M = getgenv().LGM or {}
getgenv().LGM = M

local SAFE_KEYS = { Enum.KeyCode.KeypadOne, Enum.KeyCode.KeypadTwo, Enum.KeyCode.KeypadThree, Enum.KeyCode.KeypadSeven }
local BLOCKED_TEXT = { Unload = true, ["Unload interface"] = true }

function M.setup(seed, winOpts)
	M.seed = seed or os.time()
	M.rng = Random.new(M.seed)
	M.violations, M.errors, M.actions, M.counts = {}, {}, 0, {}
	if M.log then
		M.log:Disconnect()
	end
	M.log = LogService.MessageOut:Connect(function(msg, kind)
		local ours = msg:find("LiquidGlass") or msg:find('%[string "%-%-!nocheck')
		if ours and (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning) then
			table.insert(M.errors, msg:sub(1, 220))
		end
	end)
	local lib = loadstring(readfile("LiquidGlass/LiquidGlass.lua"))()
	lib.ToggleKey = Enum.KeyCode.KeypadZero
	M.lib = lib
	local o = { Title = "Monkey Test", Subtitle = "seed " .. M.seed, Icon = "bug", Size = Vector2.new(700, 480) }
	for k, v in pairs(winOpts or {}) do
		o[k] = v
	end
	local w = lib:CreateWindow(o)
	M.w = w
	local a = w:AddTab({ Title = "Controls", Icon = "sliders" })
	local s1 = a:AddSection("Switches")
	for i = 1, 4 do
		s1:AddToggle({ Title = "Toggle " .. i, Description = i % 2 == 0 and "With a description that is long enough to wrap onto a second line in narrow windows" or nil, Default = i % 2 == 0, Flag = "t" .. i, Icon = i == 1 and "wifi" or nil, IconColor = i == 1 and Color3.fromRGB(10, 132, 255) or nil })
	end
	s1:AddSegmented({ Title = "Mode", Options = { "A", "B", "C" }, Flag = "seg" })
	local s2 = a:AddSection("Values")
	s2:AddSlider({ Title = "Slider int", Min = 0, Max = 10, Step = 1, Default = 5, Flag = "s1" })
	s2:AddSlider({ Title = "Slider float", Min = -1, Max = 1, Step = 0.01, Default = 0, Flag = "s2" })
	s2:AddStepper({ Title = "Stepper", Min = 0, Max = 5, Default = 2, Flag = "st" })
	s2:AddProgress({ Title = "Progress", Default = 0.4 })
	local b = w:AddTab({ Title = "Pickers", Icon = "palette" })
	local s3 = b:AddSection("Choices")
	s3:AddDropdown({ Title = "Single", Options = { "One", "Two", "Three", "Four" }, Default = "One", Flag = "d1" })
	s3:AddDropdown({ Title = "Multi", Options = { "Red", "Green", "Blue", "Gold" }, Multi = true, Flag = "d2" })
	local many = {}
	for i = 1, 30 do
		many[i] = "Item " .. i
	end
	s3:AddDropdown({ Title = "Long list", Options = many, Flag = "d3" })
	s3:AddColorPicker({ Title = "Color", Default = Color3.fromRGB(255, 45, 85), Flag = "c1" })
	s3:AddColorPicker({ Title = "Color alpha", Default = Color3.fromRGB(94, 92, 230), Transparency = 0.5, Flag = "c2" })
	local s4 = b:AddSection("Text")
	s4:AddInput({ Title = "Input", Placeholder = "text", Flag = "i1" })
	s4:AddInput({ Title = "Numeric", Numeric = true, Flag = "i2" })
	s4:AddKeybind({ Title = "Bind", Default = Enum.KeyCode.KeypadFive, Flag = "k1" })
	s4:AddKeybind({ Title = "Hold bind", Default = Enum.KeyCode.KeypadSix, Mode = "Hold", Flag = "k2" })
	local c = w:AddTab({ Title = "Misc", Icon = "grid" })
	local s5 = c:AddSection("Buttons")
	s5:AddButton({ Title = "Notify", Callback = function()
		lib:Notify({ Title = "Monkey", Content = "pressed", Duration = 2 })
	end })
	s5:AddButton({ Title = "Dialog", Callback = function()
		w:Dialog({ Title = "Monkey dialog", Content = "Any button", Buttons = { { Title = "OK", Style = "Primary" }, { Title = "Cancel", Style = "Cancel" } } })
	end })
	s5:AddButtons({ { Title = "A", Style = "Primary" }, { Title = "B" }, { Title = "C", Style = "Destructive" } })
	s5:AddButton({ Title = "Disabled", Disabled = true })
	s5:AddParagraph({ Title = "Paragraph", Content = "Text block" })
	s5:AddImage({ Image = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=150&h=150", Height = 90, Caption = "Image" })
	s5:AddCode({ Title = "Code", Code = "print('hi')" })
	w:AddSettingsTab()
	task.wait(1.2)
	return "setup ok, seed " .. M.seed
end

local function interactive()
	local lib = M.lib
	local list = {}
	for _, d in ipairs(lib.Gui:GetDescendants()) do
		if d:IsA("GuiButton") and d.Visible and d.AbsoluteSize.X > 2 then
			local label = d.Parent and d.Parent:FindFirstChildWhichIsA("TextLabel", true)
			local text = label and label.Text or ""
			local blocked = BLOCKED_TEXT[text]
			for _, l in ipairs(d.Parent and d.Parent:GetDescendants() or {}) do
				if l:IsA("TextLabel") and BLOCKED_TEXT[l.Text] then
					blocked = true
				end
			end
			if not blocked then
				local p = T.center(d)
				if T.onOurGui(p) and T.visibleIn(d, p) then
					local shown = true
					local o = d
					while o and o ~= lib.Gui do
						if o:IsA("GuiObject") and not o.Visible then
							shown = false
							break
						end
						o = o.Parent
					end
					if shown then
						table.insert(list, d)
					end
				end
			end
		end
		if d:IsA("TextBox") and d.Visible then
			local p = T.center(d)
			if T.onOurGui(p) and T.visibleIn(d, p) then
				table.insert(list, d)
			end
		end
	end
	return list
end

local function count(k)
	M.counts[k] = (M.counts[k] or 0) + 1
end

local function randomPointIn(gui)
	local r = M.rng
	return T.at(gui, r:NextNumber(0.05, 0.95), r:NextNumber(0.1, 0.9))
end

local function closeRobloxMenu()
	if GuiService.MenuIsOpen then
		VIM:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
		task.wait(0.03)
		VIM:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
		task.wait(0.4)
	end
end

function M.step()
	local r = M.rng
	local w = M.w
	if not w.Root.Parent then
		return
	end
	if not w.Root.Visible and r:NextNumber() < 0.75 then
		if w.Minimized and w.Pill and w.Pill.Root.Visible then
			T.click(w.Pill.Root)
			count("pillrestore")
		else
			T.key(Enum.KeyCode.KeypadZero)
			count("show")
		end
		task.wait(0.5)
		return
	end
	local roll = r:NextNumber()
	local focused = game:GetService("UserInputService"):GetFocusedTextBox()
	if focused and roll < 0.6 then
		local texts = { "abc", "123", "-4.5", "", "x", ("long "):rep(20), "😀", "#00FF00" }
		T.enter(focused, texts[r:NextInteger(1, #texts)])
		count("text")
		return
	end
	if roll < 0.03 then
		T.key(Enum.KeyCode.KeypadZero) -- toggle UI
		count("togglekey")
		if r:NextNumber() < 0.7 then
			task.wait(r:NextNumber(0.02, 0.4))
			T.key(Enum.KeyCode.KeypadZero)
		end
		return
	elseif roll < 0.08 then
		T.key(SAFE_KEYS[r:NextInteger(1, #SAFE_KEYS)])
		count("key")
		return
	elseif roll < 0.1 then
		T.key(Enum.KeyCode.Escape)
		closeRobloxMenu()
		count("escape")
		return
	elseif roll < 0.16 then
		-- wheel over the active page
		local page = w.ActiveTab and w.ActiveTab.Page
		if page and w.Root.Visible then
			local p = randomPointIn(page)
			if T.onOurGui(p) then
				T.move(p)
				VIM:SendMouseWheelEvent(p.X, p.Y, r:NextNumber() < 0.5, game)
				count("wheel")
			end
		end
		return
	elseif roll < 0.2 and w.Root.Visible then
		-- resize from a random zone
		local z = w.ResizeZones[r:NextInteger(1, 3)]
		local d = Vector2.new(r:NextInteger(-300, 300), r:NextInteger(-200, 200))
		T.drag(T.center(z), T.center(z) + d, r:NextInteger(3, 14))
		count("resize")
		return
	elseif roll < 0.23 and w.Root.Visible then
		local p = T.at(w.Header, r:NextNumber(0.1, 0.6), 0.5)
		T.drag(p, p + Vector2.new(r:NextInteger(-400, 400), r:NextInteger(-300, 300)), r:NextInteger(3, 14))
		count("windowdrag")
		return
	end
	local targets = interactive()
	if #targets == 0 then
		return
	end
	local t = targets[r:NextInteger(1, #targets)]
	local kind = r:NextNumber()
	if kind < 0.62 then
		T.click(t, r:NextNumber() < 0.15 and r:NextNumber(0.2, 0.8) or nil)
		count("click")
	elseif kind < 0.92 then
		local a = T.center(t)
		local b = a + Vector2.new(r:NextInteger(-260, 260), r:NextInteger(-160, 160))
		T.drag(a, b, r:NextInteger(2, 18))
		count("drag")
	else
		-- double/triple rapid clicks
		for _ = 1, r:NextInteger(2, 4) do
			T.click(t, 0.01)
		end
		count("multiclick")
	end
	if r:NextNumber() < 0.15 then
		task.wait(r:NextNumber(0, 0.6))
	end
end

local function violation(msg)
	if #M.violations < 60 then
		table.insert(M.violations, string.format("[action %d] %s", M.actions, msg))
	end
end

function M.check()
	local lib, w = M.lib, M.w
	closeRobloxMenu()
	task.wait(1.4) -- let springs, tweens and fades settle
	if not w.Root.Parent then
		violation("window destroyed")
		return
	end
	if not w.Body:IsDescendantOf(w.Root) then
		violation("window body lost")
	end
	for _, g in ipairs(lib.Gui:GetDescendants()) do
		if g.Name == "LGFade" then
			violation("leftover fade group under " .. g.Parent:GetFullName():sub(-40))
		end
	end
	local ov = lib._overlay
	local catchers = 0
	for _, g in ipairs(lib.Gui:GetChildren()) do
		if g.Name == "PopoverCatcher" then
			catchers += 1
		end
	end
	if catchers ~= (ov.active and 1 or 0) then
		violation("popover catchers " .. catchers .. " with active=" .. tostring(ov.active ~= nil))
	end
	if w.Root.Visible ~= (w.Visible and not w.Minimized) then
		violation("window visible flag mismatch root=" .. tostring(w.Root.Visible) .. " flag=" .. tostring(w.Visible) .. " min=" .. tostring(w.Minimized))
	end
	if w.Root.Size.X.Offset < w.MinSize.X or w.Root.Size.Y.Offset < w.MinSize.Y then
		violation("window below MinSize " .. tostring(w.Root.Size))
	end
	local vs = workspace.CurrentCamera.ViewportSize
	local pos = w.Root.AbsolutePosition - lib.Gui.AbsolutePosition
	if pos.X > vs.X - 40 or pos.Y > vs.Y - 40 or pos.X + w.Root.AbsoluteSize.X < 40 or pos.Y < -5 then
		violation("window off screen " .. tostring(pos))
	end
	if not w.Bar and w.Collapsed ~= (w.Root.Size.X.Offset < 600) then
		violation("sidebar collapse state wrong at width " .. w.Root.Size.X.Offset)
	end
	if w.Root.Visible and w.ActiveTab then
		local pill, btn = w.TabPill.Root, w.ActiveTab.Button
		if (pill.AbsolutePosition - btn.AbsolutePosition).Magnitude > 2 or (pill.AbsoluteSize - btn.AbsoluteSize).Magnitude > 2 then
			violation("tab pill off its tab d=" .. tostring(pill.AbsolutePosition - btn.AbsolutePosition) .. " size=" .. tostring(pill.AbsoluteSize))
		end
		if w.PageTitle.Text ~= w.ActiveTab.Title and not w.PageTitle.Text:find("Results") then
			violation("page title " .. w.PageTitle.Text .. " for tab " .. w.ActiveTab.Title)
		end
		for _, t in ipairs(w.Tabs) do
			if t.Page.Visible ~= (t == w.ActiveTab) then
				violation("page visibility wrong for " .. t.Title)
			end
		end
	end
	for _, tab in ipairs(w.Tabs) do
		for _, el in ipairs(tab.Elements) do
			if el.Type == "Toggle" then
				local knob = el.Switch.Root:FindFirstChild("Knob")
				local want = el.Value and 22 or 2
				if math.abs(knob.Position.X.Offset - want) > 0.6 then
					violation(el.TitleText .. " knob at " .. knob.Position.X.Offset .. " for value " .. tostring(el.Value))
				end
				if knob.Size ~= UDim2.fromOffset(38, 24) then
					violation(el.TitleText .. " knob size " .. tostring(knob.Size))
				end
				if el.Switch.State ~= el.Value then
					violation(el.TitleText .. " switch state " .. tostring(el.Switch.State) .. " vs value " .. tostring(el.Value))
				end
			elseif el.Type == "Slider" then
				local box = el.Row.Frame:FindFirstChild("Value")
				if not box:IsFocused() and tonumber((box.Text:gsub("[^%d%.%-]", ""))) ~= el.Value then
					violation(el.TitleText .. " label '" .. box.Text .. "' value " .. tostring(el.Value))
				end
			elseif el.Type == "Dropdown" and el.Menu and ov.active ~= el.Menu then
				violation(el.TitleText .. " thinks its menu is open")
			elseif el.Type == "ColorPicker" and el.Picker and ov.active ~= el.Picker then
				violation(el.TitleText .. " thinks its picker is open")
			end
			if el.Row and el.Row.Frame.Parent == nil then
				violation(el.TitleText .. " row lost")
			end
		end
	end
	local blur = lib._blur
	local cam = workspace.CurrentCamera
	for _, rg in ipairs(blur.regions) do
		if not rg.frame:IsDescendantOf(game) then
			violation("blur region for destroyed frame")
		end
		if rg.visible and rg.key then
			local x, y = rg.key:match("^([%-%d%.]+)|([%-%d%.]+)")
			local pos = rg.frame.AbsolutePosition - lib.Gui.AbsolutePosition
			if math.abs(tonumber(x) - pos.X) > 1.5 or math.abs(tonumber(y) - pos.Y) > 1.5 then
				violation("blur region stale for " .. rg.frame.Name .. " key " .. x .. "," .. y .. " frame " .. tostring(pos))
			end
			for _, part in ipairs(rg.used) do
				if (part.Position - cam.CFrame.Position).Magnitude > 3 then
					violation("blur glass left behind in the world for " .. rg.frame.Name)
					break
				end
			end
		end
	end
	local bar = w.Bar
	if bar then
		if not bar.Root or not bar.Root.Parent then
			violation("tab bar lost")
		else
			if bar.Dragging then
				violation("tab bar stuck dragging")
			end
			if bar.Floating ~= (bar.Root.Parent == lib.Gui) then
				violation("tab bar parent does not match Floating=" .. tostring(bar.Floating))
			end
			local wantShown = bar:wantShown()
			if bar.Floating and bar.Root.Visible ~= wantShown then
				violation("floating bar visible=" .. tostring(bar.Root.Visible) .. " want=" .. tostring(wantShown) .. " window=" .. tostring(w.Visible and not w.Minimized))
			end
			if bar.GhostKey or (bar.Ghost and bar.Ghost.BackgroundTransparency < 0.99) then
				violation("snap outline left on screen")
			end
			if w.AtBar and (bar.Screen or bar.Free) and w.Visible and not w.Minimized then
				local spot = bar:windowSpot(bar:target(bar.M))
				local wp = Vector2.new(w.Root.Position.X.Offset, w.Root.Position.Y.Offset)
				if (spot - wp).Magnitude > 3 then
					violation("window not at its bar (off by " .. string.format("%.1f", (spot - wp).Magnitude) .. ")")
				end
			end
			local t = bar:target()
			local p = Vector2.new(bar.Root.Position.X.Offset, bar.Root.Position.Y.Offset)
			if (t - p).Magnitude > 2 then
				violation("tab bar off its spot by " .. string.format("%.1f", (t - p).Magnitude) .. " (" .. bar.Position .. (bar.Floating and " floating" or "") .. ")")
			end
			local gripCount = 0
			for _, g in ipairs(lib.Gui:GetChildren()) do
				if g.Name == "TabBar" then
					gripCount += 1
				end
			end
			local docked = 0
			for _, g in ipairs(w.Body:GetChildren()) do
				if g.Name == "TabBar" then
					docked += 1
				end
			end
			if gripCount + docked ~= 1 then
				violation((gripCount + docked) .. " tab bars alive")
			end
		end
	end
	local guis = 0
	for _, g in ipairs(lib.Gui.Parent:GetChildren()) do
		if g.Name == "LiquidGlass" and g:IsA("ScreenGui") then
			guis += 1
		end
	end
	if guis > 1 then
		violation(guis .. " LiquidGlass ScreenGuis alive")
	end
	if lib._capturingKey then
		local listening = false
		for _, tab in ipairs(w.Tabs) do
			for _, el in ipairs(tab.Elements) do
				if el.Type == "Keybind" and el.Row.Frame:FindFirstChild("Key", true) then
					local lbl = el.Row.Frame:FindFirstChild("Key", true):FindFirstChildWhichIsA("TextLabel", true)
					if lbl and lbl.Text:find("Press") then
						listening = true
					end
				end
			end
		end
		if not listening then
			violation("capture flag stuck without a listening keybind")
		end
	end
end

function M.run(n)
	local t0 = os.clock()
	for _ = 1, n do
		M.actions += 1
		local ok, err = pcall(M.step)
		if not ok then
			violation("harness: " .. tostring(err))
		end
		if M.actions % 40 == 0 then
			M.check()
		end
		if os.clock() - t0 > 95 then
			break
		end
	end
	return M.report()
end

function M.report()
	local parts = {}
	for k, v in pairs(M.counts) do
		table.insert(parts, k .. "=" .. v)
	end
	table.sort(parts)
	return string.format("seed %d, %d actions (%s), refused clicks %d\nLiquidGlass errors: %d\n%s\nviolations: %d\n%s", M.seed, M.actions, table.concat(parts, " "), T.refused, #M.errors, table.concat(M.errors, "\n"), #M.violations, table.concat(M.violations, "\n"))
end

return M
