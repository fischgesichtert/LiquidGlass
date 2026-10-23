getgenv().LiquidGlassSkipIntro = true
-- API robustness: Rayfield- and Fluent-style scripts, hostile input, edge cases.
local report, failures = {}, 0
local function check(name, ok, detail)
	if not ok then
		failures += 1
	end
	table.insert(report, (ok and "PASS " or "FAIL ") .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or ""))
end
local function try(name, fn)
	local ok, err = pcall(fn)
	check(name, ok, not ok and err or nil)
	return ok
end

local LogService = game:GetService("LogService")
local libErrors = {}
local conn = LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError and (msg:find("LiquidGlass") or msg:find('%[string "%-%-!nocheck')) and not msg:find("callback error") then
		table.insert(libErrors, msg:sub(1, 200))
	end
end)

local Lib = loadstring(readfile("LiquidGlass/LiquidGlass.lua"))()

-- Rayfield style ------------------------------------------------------------
local cbValues = {}
try("rayfield window", function()
	local Window = Lib:CreateWindow({
		Name = "Rayfield Script",
		LoadingTitle = "Loading",
		LoadingSubtitle = "by someone",
		ConfigurationSaving = { Enabled = true, FolderName = "LGApiTest", FileName = "cfg" },
		KeySystem = false,
	})
	local Tab = Window:CreateTab("Main", 4483362458)
	local Section = Tab:CreateSection("Section")
	Tab:CreateButton({ Name = "Button", Callback = function() end })
	local t = Tab:CreateToggle({ Name = "Toggle", CurrentValue = false, Flag = "rfToggle", Callback = function(v)
		cbValues.toggle = v
	end })
	local s = Tab:CreateSlider({ Name = "Slider", Range = { 0, 100 }, Increment = 10, Suffix = "Bananas", CurrentValue = 10, Flag = "rfSlider", Callback = function(v)
		cbValues.slider = v
	end })
	local d = Tab:CreateDropdown({ Name = "Dropdown", Options = { "Option 1", "Option 2" }, CurrentOption = { "Option 1" }, MultipleOptions = false, Flag = "rfDropdown", Callback = function(o)
		cbValues.dropdown = o
	end })
	Tab:CreateInput({ Name = "Input", PlaceholderText = "Input Placeholder", RemoveTextAfterFocusLost = false, Callback = function() end })
	local k = Tab:CreateKeybind({ Name = "Keybind", CurrentKeybind = "Q", HoldToInteract = false, Flag = "rfKey", Callback = function() end })
	local c = Tab:CreateColorPicker({ Name = "Color", Color = Color3.fromRGB(255, 255, 255), Flag = "rfColor", Callback = function() end })
	local l = Tab:CreateLabel("Label Example")
	local p = Tab:CreateParagraph({ Title = "Paragraph", Content = "Content" })
	Section:Set("Renamed")
	t:Set(true)
	s:Set(55)
	d:Set({ "Option 2" })
	k:Set("E")
	c:Set(Color3.fromRGB(1, 2, 3))
	l:Set("New label")
	p:Set({ Title = "T", Content = "C" })
	d:Refresh({ "A", "B", "C" })
	Lib:Notify({ Title = "Rayfield", Content = "Notify", Duration = 1, Image = 4483362458, Actions = { Ignore = { Name = "Okay!", Callback = function() end } } })
	Lib:LoadConfiguration()
	task.wait(0.3)
	check("rayfield toggle value", t.CurrentValue == true and cbValues.toggle == true, tostring(t.CurrentValue))
	check("rayfield slider snaps to increment", s.CurrentValue == 60 and cbValues.slider == 60, s.CurrentValue)
	check("rayfield dropdown value", d.CurrentOption == nil, tostring(d.CurrentOption))
	check("rayfield keybind", k.CurrentKeybind == "E", k.CurrentKeybind)
	check("rayfield flags", Lib.Flags.rfToggle == t and Lib.Flags.rfSlider == s)
end)

-- Fluent style ------------------------------------------------------------------
try("fluent window", function()
	local Window = Lib:CreateWindow({ Title = "Fluent " .. Lib.Version, SubTitle = "by someone", TabWidth = 160, Size = UDim2.fromOffset(580, 460), Acrylic = true, Theme = "Dark", MinimizeKey = Enum.KeyCode.KeypadMinus })
	local Tabs = { Main = Window:AddTab({ Title = "Main", Icon = "" }), Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }) }
	local Options = Lib.Options
	Tabs.Main:AddParagraph({ Title = "Paragraph", Content = "This is a paragraph.\nSecond line!" })
	Tabs.Main:AddButton({ Title = "Button", Description = "Very important button", Callback = function() end })
	local Toggle = Tabs.Main:AddToggle("MyToggle", { Title = "Toggle", Default = false })
	Toggle:OnChanged(function()
		cbValues.fluentToggle = Options.MyToggle.Value
	end)
	Options.MyToggle:SetValue(true)
	local Slider = Tabs.Main:AddSlider("Slider", { Title = "Slider", Description = "This is a slider", Default = 2, Min = 0, Max = 5, Rounding = 1, Callback = function(v)
		cbValues.fluentSlider = v
	end })
	Slider:SetValue(3.33)
	local Dropdown = Tabs.Main:AddDropdown("Dropdown", { Title = "Dropdown", Values = { "one", "two", "three" }, Multi = false, Default = 1 })
	Dropdown:SetValue("two")
	local Multi = Tabs.Main:AddDropdown("MultiDropdown", { Title = "Dropdown", Values = { "one", "two", "three" }, Multi = true, Default = { "one", "three" } })
	Multi:SetValue({ two = true, three = true })
	local Color = Tabs.Main:AddColorpicker("Colorpicker", { Title = "Colorpicker", Default = Color3.fromRGB(96, 205, 255) })
	Color:SetValueRGB(Color3.fromRGB(0, 255, 140))
	local Keybind = Tabs.Main:AddKeybind("Keybind", { Title = "KeyBind", Mode = "Toggle", Default = "LeftControl", ChangedCallback = function() end })
	Keybind:OnClick(function() end)
	Keybind:SetValue("MB2", "Toggle")
	local Input = Tabs.Main:AddInput("Input", { Title = "Input", Default = "Default", Placeholder = "Placeholder", Numeric = false, Finished = false, Callback = function() end })
	Input:SetValue("x")
	Window:SelectTab(1)
	Lib:Notify({ Title = "Fluent", Content = "Notification", SubContent = "SubContent", Duration = 1 })
	task.wait(0.3)
	check("fluent OnChanged + SetValue", cbValues.fluentToggle == true)
	check("fluent slider rounding", Slider.Value == 3.3, Slider.Value)
	check("fluent dropdown index default then set", Dropdown.Value == "two", Dropdown.Value)
	local mv = Multi.Value
	check("fluent multi from dictionary", type(mv) == "table" and #mv == 2 and table.find(mv, "two") and table.find(mv, "three"), type(mv) == "table" and table.concat(mv, ",") or tostring(mv))
	check("fluent colorpicker", Color.Value == Color3.fromRGB(0, 255, 140))
	check("fluent keybind mouse button", Keybind.Value == "MouseButton2", Keybind.Value)
	check("fluent input", Input.Value == "x", Input.Value)
end)

-- hostile input -------------------------------------------------------------------
try("hostile values", function()
	local W = Lib:CreateWindow({ Title = ("Very long title "):rep(12), Size = Vector2.new(99999, -5) })
	check("absurd size clamped", W.Root.Size.X.Offset <= workspace.CurrentCamera.ViewportSize.X and W.Root.Size.Y.Offset >= W.MinSize.Y, tostring(W.Root.Size))
	local T = W:AddTab({ Title = "", Icon = "definitely-not-an-icon" })
	local S = T:AddSection()
	local errCb = S:AddButton({ Title = "Throws", Callback = function()
		error("boom")
	end })
	errCb:Fire()
	local sl = S:AddSlider({ Title = "Weird slider", Min = 10, Max = 10, Default = 99 })
	sl:Set("not a number")
	sl:Set(math.huge)
	sl:Set(-math.huge)
	check("degenerate slider stays sane", sl.Value == 10, sl.Value)
	local sl2 = S:AddSlider({ Title = "Reversed", Min = 0, Max = 1, Step = 0.25, Default = 0.6 })
	check("slider snaps to step", sl2.Value == 0.5, sl2.Value)
	local dd = S:AddDropdown({ Title = "Empty", Options = {} })
	dd:Set("nope")
	dd:Set(nil)
	dd:SetOptions({ 1, 2, 3, true, "x" })
	dd:Set(2)
	check("dropdown with non-string options", dd.Value == 2, tostring(dd.Value))
	S:AddImage({ Image = "https://invalid.invalid/nothing.png" })
	S:AddImage({ Image = "rbxassetid://0" })
	S:AddImage({ Image = 0 })
	S:AddImage({})
	S:AddLabel(nil)
	S:AddParagraph({})
	S:AddKeybind({ Title = "Bad key", Default = "NotAKey" })
	S:AddColorPicker({ Title = "Hex", Default = "#12ab34" })
	S:AddColorPicker({ Title = "Bad hex", Default = "zzz" })
	S:AddInput({ Title = "Max", MaxLength = 3, Default = "abcdef" })
	S:AddCustom({ Title = "Throws in build", Build = function()
		error("custom boom")
	end })
	local el = S:AddToggle({ Title = "Destroy me", Flag = "destroyMe" })
	el:Destroy()
	el:Destroy()
	check("destroyed element unregistered", Lib.Options.destroyMe == nil)
	S:Destroy()
	W:Notify({})
	Lib:Notify(nil)
	Lib:Notify("just a string")
	W:Dialog({ Buttons = {} })
	task.wait(0.4)
	W:Destroy()
	W:Destroy()
end)

-- customization -----------------------------------------------------------------------
try("customization", function()
	Lib:SetDensity("Large")
	check("density sets metrics", Lib.Metrics.RowMin == 56 and Lib.Metrics.Button == 42, Lib.Metrics.RowMin)
	Lib:SetMetrics({ Button = 44, NotAMetric = 1 })
	check("SetMetrics overrides", Lib.Metrics.Button == 44)
	Lib:SetDensity("Regular")
	check("density resets", Lib.Metrics.RowMin == 48 and Lib.Metrics.Button == 36, Lib.Metrics.Button)
	Lib:SetFont(Enum.Font.Gotham)
	local W = Lib:CreateWindow({ Title = "Custom", Accent = "#FF2D55" })
	local T = W:AddTab({ Title = "Custom", Icon = "palette" })
	local s = T:AddSection("Styled")
	local big = s:AddToggle({ Title = "Big title", TitleSize = 20, TitleColor = Color3.fromRGB(255, 200, 0), Size = "Large", RowHeight = 64 })
	check("TitleSize applied", big.Row.Title.TextSize == 20)
	check("TitleColor applied", big.Row.Title.TextColor3 == Color3.fromRGB(255, 200, 0))
	check("Font applied", big.Row.Title.FontFace.Family == Font.fromEnum(Enum.Font.Gotham).Family)
	check("large switch", big.Switch.Root.Size.X.Offset > Lib.Metrics.SwitchW)
	task.wait(0.9) -- let the window's open animation finish
	check("RowHeight applied", big.Row.Frame.AbsoluteSize.Y / Lib.ScaleObject.Scale >= 63.5, big.Row.Frame.AbsoluteSize.Y)
	local small = s:AddButton({ Title = "Small", Size = "Small", Width = "Auto" })
	task.wait(0.1)
	check("small auto button", small.Capsule and math.abs(small.Capsule.Root.AbsoluteSize.Y / Lib.ScaleObject.Scale - Lib.Metrics.ButtonSmall) < 1)
	check("auto width hugs label", small.Capsule.Root.AbsoluteSize.X < 200, small.Capsule.Root.AbsoluteSize.X)
	local sl = s:AddSlider({ Title = "Thick", TrackHeight = 10, Size = "Large" })
	check("slider track height", sl.Row.Body:FindFirstChild("Slider"):FindFirstChild("Track").Size.Y.Offset == 10)
	local inp = s:AddInput({ Title = "Wide", Width = 240 })
	check("input width", inp.Row.Right.Size.X.Offset == 240)
	Lib:SetThemeValue("GlassT", 0.8)
	check("SetThemeValue", Lib:GetTheme().GlassT == 0.8)
	Lib:SetThemeValue("GlassT", 0.9)
	Lib:SetFont("BuilderSans")
	task.wait(0.3)
	W:Destroy()
end)

-- tab bar navigation -------------------------------------------------------------------
try("tab bar", function()
	for _, cfg in ipairs({ { Position = "Bottom" }, { Position = "Left" }, { Position = "Top", Labels = false }, { Position = "Right", Floating = true } }) do
		local W = Lib:CreateWindow({ Title = "Bar " .. cfg.Position, Navigation = "TabBar", TabBar = cfg })
		for i = 1, 4 do
			W:AddTab({ Title = "Tab " .. i, Icon = "home" }):AddToggle({ Title = "t" })
		end
		task.wait(0.4)
		local bar = W:GetTabBar()
		check("bar " .. cfg.Position .. " built", bar and bar.Root and bar.Root.Parent ~= nil)
		check("bar " .. cfg.Position .. " orientation", (bar.Root.AbsoluteSize.Y > bar.Root.AbsoluteSize.X) == (cfg.Position == "Left" or cfg.Position == "Right"), tostring(bar.Root.AbsoluteSize))
		W:SelectTab(3)
		task.wait(0.6)
		local pill = bar.Pill.Root
		local item = W.Tabs[3].Button
		check("bar " .. cfg.Position .. " pill on tab 3", (pill.AbsolutePosition - item.AbsolutePosition).Magnitude < 2, tostring(pill.AbsolutePosition - item.AbsolutePosition))
		W:SetTabBarPosition("Top")
		task.wait(0.7)
		check("bar " .. cfg.Position .. " moved to Top", bar.Position == "Top")
		W:DetachTabBar()
		task.wait(0.6)
		check("bar " .. cfg.Position .. " detached", bar.Floating and bar.Root.Parent == Lib.Gui)
		W:AttachTabBar()
		task.wait(0.6)
		check("bar " .. cfg.Position .. " attached", not bar.Floating and bar.Root:IsDescendantOf(W.Root))
		W:SetVisible(false)
		task.wait(0.4)
		W:SetVisible(true)
		task.wait(0.4)
		W:Destroy()
		task.wait(0.4)
		check("bar " .. cfg.Position .. " destroyed with window", bar.Glass == nil or bar.Root.Parent == nil)
	end
end)

-- many elements / performance --------------------------------------------------------
try("bulk build", function()
	local t0 = os.clock()
	local W = Lib:CreateWindow({ Title = "Bulk" })
	for ti = 1, 5 do
		local T = W:AddTab({ Title = "Tab " .. ti, Icon = Lib.Icons[ti * 7] })
		for si = 1, 4 do
			local S = T:AddSection("Section " .. si)
			for i = 1, 10 do
				local k = (i % 5)
				if k == 0 then
					S:AddToggle({ Title = "T" .. i })
				elseif k == 1 then
					S:AddSlider({ Title = "S" .. i })
				elseif k == 2 then
					S:AddDropdown({ Title = "D" .. i, Options = { "a", "b" } })
				elseif k == 3 then
					S:AddButton({ Title = "B" .. i })
				else
					S:AddInput({ Title = "I" .. i })
				end
			end
		end
	end
	local dt = os.clock() - t0
	check("200 elements build fast", dt < 3, string.format("%.2fs", dt))
	task.wait(0.5)
	W:Destroy()
end)

task.wait(1)
Lib:Destroy()
task.wait(0.8)
local alive = 0
for _, g in ipairs(gethui():GetChildren()) do
	if g.Name == "LiquidGlass" then
		alive += 1
	end
end
check("unload removes the GUI", alive == 0, alive)
local cam = workspace.CurrentCamera
check("unload removes blur parts", cam:FindFirstChild("LiquidGlassBlur") == nil and cam:FindFirstChild("LiquidGlassDOF") == nil)
check("unload clears global", getgenv().LiquidGlass == nil)
conn:Disconnect()
check("no internal LiquidGlass errors", #libErrors == 0, table.concat(libErrors, " || "))
pcall(function()
	delfolder("LiquidGlass/configs/LGApiTest")
end)
table.insert(report, 1, string.format("%d checks, %d failures", #report, failures))
return table.concat(report, "\n")
