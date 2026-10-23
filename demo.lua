-- Glass Hub: a LiquidGlass demo laid out like a real script hub.
-- Everything here only changes your own view (camera, lighting, UI).
local LiquidGlass = loadstring(game:HttpGet("https://raw.githubusercontent.com/fischgesichtert/LiquidGlass/main/dist/LiquidGlass.lua"))()
-- a local build instead (python build.py --install):
-- local LiquidGlass = loadstring(readfile("LiquidGlass/LiquidGlass.lua"))()

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local gameName = "this experience"
pcall(function()
	gameName = MarketplaceService:GetProductInfo(game.PlaceId).Name
end)

local Window = LiquidGlass:CreateWindow({
	Title = "Glass Hub",
	Subtitle = "LiquidGlass " .. LiquidGlass.Version,
	Icon = "sparkle",
	Size = Vector2.new(760, 520),
	ToggleKey = Enum.KeyCode.RightControl,
})

-- Dashboard ------------------------------------------------------------------------
local Dash = Window:AddTab({ Title = "Dashboard", Icon = "home" })

local Welcome = Dash:AddSection("Welcome back")
Welcome:AddImage({ Image = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=512&h=512", Height = 140, Caption = gameName })
Welcome:AddParagraph({ Title = "Hi, " .. LocalPlayer.DisplayName .. " 👋", Content = "Everything in Glass Hub is real liquid glass. Drag the switches, sliders and segmented controls — the glass follows your finger and snaps back like a drop." })
Welcome:AddButtons({
	{ Title = "What's new", Style = "Primary", Icon = "bell", Callback = function()
		LiquidGlass:Notify({
			Title = "Glass Hub updated",
			Content = "Every size now follows one grid: rows, controls and buttons line up everywhere.",
			Type = "Success",
			Duration = 8,
			Actions = { { Title = "Nice" }, { Title = "Details", Callback = function()
				Window:SelectTab(4)
			end } },
		})
	end },
	{ Title = "About", Icon = "info", Callback = function()
		Window:Dialog({
			Title = "Glass Hub",
			Content = "A demo of the LiquidGlass UI library. Press Right Ctrl to hide or show the window.",
			Icon = "sparkle",
			Buttons = { { Title = "Close", Style = "Primary" } },
		})
	end },
})

local Stats = Dash:AddSection("Session")
local playersLabel = Stats:AddButton({ Title = "Players in server", Icon = "users", IconColor = Color3.fromRGB(10, 132, 255), Accessory = tostring(#Players:GetPlayers()) })
local timeLabel = Stats:AddButton({ Title = "Time in server", Icon = "clock", IconColor = Color3.fromRGB(255, 159, 10), Accessory = "0:00" })
local fpsBar = Stats:AddProgress({ Title = "Frame rate", Max = 120, Suffix = " fps", Default = 60 })
task.spawn(function()
	local started = os.clock()
	local frames, last = 0, os.clock()
	local conn = game:GetService("RunService").RenderStepped:Connect(function()
		frames += 1
	end)
	while not LiquidGlass:IsUnloaded() do
		task.wait(1)
		local now = os.clock()
		fpsBar:Set(math.floor(frames / (now - last) + 0.5))
		frames, last = 0, now
		local t = math.floor(now - started)
		timeLabel:SetAccessory(string.format("%d:%02d", t // 60, t % 60))
		playersLabel:SetAccessory(tostring(#Players:GetPlayers()))
	end
	conn:Disconnect()
end)

-- Visuals -----------------------------------------------------------------------------
local Visuals = Window:AddTab({ Title = "Visuals", Icon = "eye" })

local Cam = Visuals:AddSection("Camera")
local defaultFov = Camera.FieldOfView
Cam:AddSlider({ Title = "Field of view", Min = 40, Max = 120, Default = math.floor(defaultFov), Suffix = "°", Flag = "fov", Callback = function(v)
	Camera.FieldOfView = v
end })
Cam:AddSegmented({ Options = { "Narrow", "Normal", "Wide" }, Default = "Normal", Callback = function(v)
	LiquidGlass.Options.fov:Set(({ Narrow = 55, Normal = 70, Wide = 100 })[v])
end })

local Light = Visuals:AddSection("Lighting")
local original = { ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd }
Light:AddSlider({ Title = "Time of day", Description = "Only on your screen", Min = 0, Max = 24, Step = 0.25, Default = math.floor(Lighting.ClockTime * 4) / 4, Suffix = " h", Icon = "sun", IconColor = Color3.fromRGB(255, 159, 10), Flag = "clock", Callback = function(v)
	Lighting.ClockTime = v
end })
Light:AddToggle({ Title = "Fullbright", Icon = "lightbulb", IconColor = Color3.fromRGB(255, 204, 0), Flag = "fullbright", Callback = function(on)
	Lighting.Brightness = on and 2 or original.Brightness
	Lighting.Ambient = on and Color3.new(1, 1, 1) or original.Ambient
	Lighting.OutdoorAmbient = on and Color3.new(1, 1, 1) or original.OutdoorAmbient
end })
Light:AddToggle({ Title = "No fog", Icon = "cloud", IconColor = Color3.fromRGB(142, 142, 147), Flag = "nofog", Callback = function(on)
	Lighting.FogEnd = on and 1e6 or original.FogEnd
end })
Light:AddButton({ Title = "Reset lighting", Icon = "refresh", Callback = function()
	for k, v in pairs(original) do
		Lighting[k] = v
	end
	LiquidGlass.Options.fullbright:Set(false, true)
	LiquidGlass.Options.nofog:Set(false, true)
	LiquidGlass.Options.clock:Set(original.ClockTime, true)
	LiquidGlass:Notify({ Title = "Lighting reset", Type = "Success", Duration = 2.5 })
end })

local Look = Visuals:AddSection("Highlights")
Look:AddDropdown({ Title = "Highlight", Description = "Who gets an outline", Options = { "Friends", "Team", "Everyone else" }, Multi = true, Default = { "Friends" }, Icon = "users", IconColor = Color3.fromRGB(48, 209, 88), Flag = "hlTargets" })
Look:AddColorPicker({ Title = "Outline color", Default = Color3.fromRGB(10, 132, 255), Flag = "hlColor" })
Look:AddColorPicker({ Title = "Fill color", Default = Color3.fromRGB(255, 45, 85), Transparency = 0.6, Flag = "hlFill" })

-- Players -------------------------------------------------------------------------------
local People = Window:AddTab({ Title = "Players", Icon = "users" })
local Server = People:AddSection("In this server")
local function playerNames()
	local t = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			table.insert(t, p.DisplayName .. " (@" .. p.Name .. ")")
		end
	end
	table.sort(t)
	return t
end
local picker = Server:AddDropdown({ Title = "Player", Options = playerNames(), Searchable = true, Placeholder = "Choose", Icon = "user", IconColor = Color3.fromRGB(94, 92, 230), Flag = "player" })
Players.PlayerAdded:Connect(function()
	picker:SetOptions(playerNames(), true)
end)
Players.PlayerRemoving:Connect(function()
	task.defer(function()
		picker:SetOptions(playerNames(), true)
	end)
end)
Server:AddButton({ Title = "Spectate", Description = "Moves your camera to them", Icon = "eye", IconColor = Color3.fromRGB(10, 132, 255), Callback = function()
	local name = picker.Value and picker.Value:match("@(.-)%)")
	local target = name and Players:FindFirstChild(name)
	local hum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		Camera.CameraSubject = hum
		LiquidGlass:Notify({ Title = "Spectating", Content = target.DisplayName, Duration = 3 })
	else
		LiquidGlass:Notify({ Title = "Pick a player first", Type = "Warning", Duration = 3 })
	end
end })
Server:AddButton({ Title = "Stop spectating", Icon = "close", Callback = function()
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		Camera.CameraSubject = hum
	end
end })

local Me = People:AddSection("You")
Me:AddImage({ Image = LiquidGlass:Avatar(LocalPlayer.UserId, "AvatarBust"), Height = 150, ScaleType = "Fit", Caption = LocalPlayer.DisplayName .. "  ·  @" .. LocalPlayer.Name })
Me:AddKeybind({ Title = "Quick hide", Description = "Hides every LiquidGlass window", Default = Enum.KeyCode.RightControl, ChangedCallback = function(k)
	LiquidGlass.ToggleKey = k
end })

-- Showcase -----------------------------------------------------------------------------
local Show = Window:AddTab({ Title = "Showcase", Icon = "grid" })
local Inputs = Show:AddSection("Inputs")
Inputs:AddInput({ Title = "Nickname", Placeholder = "Type anything", Flag = "nick", Callback = function(t)
	if t ~= "" then
		LiquidGlass:Notify({ Title = "Saved nickname", Content = t, Duration = 2.5 })
	end
end })
Inputs:AddInput({ Title = "Amount", Numeric = true, Placeholder = "0", Flag = "amount" })
Inputs:AddStepper({ Title = "Quantity", Min = 1, Max = 10, Default = 3, Flag = "qty" })
Inputs:AddDropdown({ Title = "Size", Options = { "Small", "Medium", "Large" }, Default = "Medium", Flag = "size" })

local Buttons = Show:AddSection("Buttons")
Buttons:AddButton({ Title = "Primary", Style = "Primary", Icon = "bolt" })
Buttons:AddButtons({ { Title = "Glass" }, { Title = "Success", Style = "Success", Icon = "check" }, { Title = "Delete", Style = "Destructive", Icon = "trash", Callback = function()
	Window:Dialog({ Title = "Delete everything?", Content = "This is just a demo, nothing is deleted.", Icon = "trash", IconColor = "Danger", Buttons = { { Title = "Cancel", Style = "Cancel" }, { Title = "Delete", Style = "Destructive" } } })
end } })
Buttons:AddButton({ Title = "Open link", Accessory = "Copy", Icon = "link", IconColor = Color3.fromRGB(10, 132, 255), Tooltip = "Copies a link to your clipboard" })
Buttons:AddButton({ Title = "Coming soon", Description = "Disabled elements dim and ignore input", Icon = "lock", Disabled = true })

local Notes = Show:AddSection("Text")
Notes:AddLabel("A label is a plain line of text.")
Notes:AddParagraph({ Title = "Paragraph", Content = "Paragraphs wrap over as many lines as they need and keep the same insets as every other row." })
Notes:AddCode({ Title = "Load LiquidGlass", Code = 'local LiquidGlass = loadstring(game:HttpGet("https://…/LiquidGlass.lua"))()' })

local Alerts = Show:AddSection("Notifications")
Alerts:AddButtons({
	{ Title = "Info", Callback = function()
		LiquidGlass:Notify({ Title = "Heads up", Content = "Hover to pause me, swipe right to dismiss.", Duration = 6 })
	end },
	{ Title = "Success", Callback = function()
		LiquidGlass:Notify({ Title = "Done", Content = "Everything worked.", Type = "Success", Duration = 4 })
	end },
	{ Title = "Error", Callback = function()
		LiquidGlass:Notify({ Title = "Something failed", Content = "Just a demo error.", Type = "Error", Duration = 4 })
	end },
})

-- Customize: sizes, text styles and a second window with a tab bar -----------------
local Custom = Window:AddTab({ Title = "Customize", Icon = "brush" })

local Sizes = Custom:AddSection("Sizes")
Sizes:AddToggle({ Title = "Small switch", Size = "Small", Default = true })
Sizes:AddToggle({ Title = "Regular switch", Default = true })
Sizes:AddToggle({ Title = "Large switch", Size = "Large", Default = true })
Sizes:AddSlider({ Title = "Large slider with a thick track", Size = "Large", TrackHeight = 10, Default = 60 })
Sizes:AddButton({ Title = "Small", Size = "Small", Width = "Auto", Style = "Primary" })
Sizes:AddButton({ Title = "Large button", Size = "Large", Style = "Success", Icon = "check" })
Sizes:AddButtons({ { Title = "Small" }, { Title = "Row", Style = "Primary" }, { Title = "Of three" } }, { Size = "Small" })

local Styles = Custom:AddSection("Text styles")
Styles:AddLabel({ Title = "Bigger title", TitleSize = 19, TitleWeight = "Bold" })
Styles:AddLabel({ Title = "Accent colored", TitleColor = "Accent" })
Styles:AddLabel({ Title = "Any color", TitleColor = Color3.fromRGB(255, 159, 10) })
Styles:AddToggle({ Title = "Monospace font", Font = Enum.Font.RobotoMono, Description = "Font works on every element" })
Styles:AddButton({ Title = "Taller row", RowHeight = 64, Icon = "ruler", IconColor = Color3.fromRGB(48, 209, 88) })

local Layout = Custom:AddSection("Layouts")
Layout:AddParagraph({ Title = "Tab bar windows", Content = "Windows can use an iOS-style tab bar instead of the sidebar. This one is a dock on the edge of the screen: drag its grip to any edge or corner (an outline shows where it snaps), and its tabs open the window right next to it. Hide the window and the bar stays, so a tap on a tab brings it back. Drop the bar on the window to dock it inside." })
local barWindow
Layout:AddButton({ Title = "Open tab bar window", Style = "Primary", Icon = "dock", Callback = function()
	if barWindow and not barWindow.Destroyed then
		barWindow:SetVisible(true)
		return
	end
	barWindow = LiquidGlass:CreateWindow({
		Title = "Music",
		Icon = "music",
		Navigation = "TabBar",
		TabBar = { Position = "Bottom", Screen = true },
		Size = Vector2.new(560, 400),
	})
	for _, t in ipairs({ { "Listen Now", "play" }, { "Browse", "grid" }, { "Radio", "wifi" }, { "Library", "music" } }) do
		local tab = barWindow:AddTab({ Title = t[1], Icon = t[2] })
		local s = tab:AddSection(t[1])
		s:AddImage({ Image = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=512&h=512", Height = 120 })
		s:AddToggle({ Title = "Shuffle", Icon = "shuffle", IconColor = Color3.fromRGB(255, 45, 85) })
		s:AddSlider({ Title = "Volume", Default = 60, Suffix = "%" })
	end
	barWindow:AddSettingsTab()
end })
Layout:AddSegmented({ Title = "Move its tab bar", Options = { "Bottom", "Left", "Top", "Right" }, Callback = function(v)
	if barWindow and not barWindow.Destroyed then
		barWindow:SetTabBarPosition(v)
	end
end })
Layout:AddSegmented({ Title = "Along the edge", Options = { "Start", "Center", "End" }, Default = "Center", Callback = function(v)
	if barWindow and not barWindow.Destroyed then
		barWindow:PinTabBar(nil, v)
	end
end })
Layout:AddToggle({ Title = "Lock the bar", Icon = "lock", IconColor = Color3.fromRGB(142, 142, 147), Callback = function(on)
	if barWindow and not barWindow.Destroyed then
		barWindow:LockTabBar(on)
	end
end })

-- Settings -----------------------------------------------------------------------------
Window:AddSettingsTab()

LiquidGlass.OnUnload = function()
	Camera.FieldOfView = defaultFov
	for k, v in pairs(original) do
		Lighting[k] = v
	end
end

LiquidGlass:Notify({ Title = "Glass Hub loaded", Content = "Press Right Ctrl to hide or show the window.", Type = "Success", Duration = 5 })
