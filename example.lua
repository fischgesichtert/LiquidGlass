-- LiquidGlass demo: every element, notification, dialog and image source.
local LiquidGlass = loadstring(game:HttpGet("https://raw.githubusercontent.com/fischgesichtert/LiquidGlass/main/dist/LiquidGlass.lua"))()
-- a local build instead (python build.py --install):
-- local LiquidGlass = loadstring(readfile("LiquidGlass/LiquidGlass.lua"))()

local Window = LiquidGlass:CreateWindow({
	Title = "Liquid Glass",
	Subtitle = "UI Library Demo",
	Icon = "layers",
	Size = Vector2.new(720, 500),
	ToggleKey = Enum.KeyCode.RightControl,
})

-- Home -------------------------------------------------------------------
local Home = Window:AddTab({ Title = "Home", Icon = "home" })

local Hero = Home:AddSection("Welcome")
Hero:AddParagraph({
	Title = "Liquid Glass for Roblox",
	Content = "Real frosted glass with lens edges, spring physics and glass sounds. Drag the switches, sliders, segmented controls and the tab selection — everything is a living glass lens.",
})
Hero:AddImage({ Image = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=512&h=512", Height = 150, Caption = "Images from asset ids, thumbnails, web URLs or local files" })
Hero:AddButtons({
	{ Title = "Notify", Style = "Primary", Icon = "bell", Callback = function()
		LiquidGlass:Notify({ Title = "Hello!", Content = "This is a Liquid Glass notification. Hover to pause, swipe right to dismiss.", Duration = 6 })
	end },
	{ Title = "Dialog", Icon = "info", Callback = function()
		Window:Dialog({
			Title = "Liquid Glass",
			Content = "Dialogs float above the window on their own sheet of glass.",
			Icon = "sparkles",
			Buttons = {
				{ Title = "Cancel", Style = "Cancel" },
				{ Title = "Continue", Style = "Primary", Callback = function()
					LiquidGlass:Notify({ Title = "Continued", Type = "Success", Duration = 3 })
				end },
			},
		})
	end },
})

local Quick = Home:AddSection("Quick settings")
Quick:AddToggle({ Title = "Wi-Fi", Icon = "wifi", IconColor = Color3.fromRGB(10, 132, 255), Default = true, Flag = "wifi" })
Quick:AddToggle({ Title = "Bluetooth", Icon = "bluetooth", IconColor = Color3.fromRGB(10, 132, 255), Default = true, Flag = "bt" })
Quick:AddToggle({ Title = "Airplane Mode", Description = "Turns off every wireless connection", Icon = "airplane", IconColor = Color3.fromRGB(255, 159, 10), Flag = "airplane" })
Quick:AddSegmented({ Title = "Appearance", Options = { "Dark", "Light" }, Default = "Dark", Callback = function(v)
	LiquidGlass:SetTheme(v)
end })

-- Controls -----------------------------------------------------------------
local Controls = Window:AddTab({ Title = "Controls", Icon = "sliders" })

local Inputs = Controls:AddSection("Values")
Inputs:AddSlider({ Title = "Walk speed", Description = "Drag the glass knob", Min = 16, Max = 120, Default = 16, Step = 1, Flag = "speed", Callback = function(v)
	local h = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if h then
		h.WalkSpeed = v
	end
end })
Inputs:AddSlider({ Title = "Field of view", Min = 50, Max = 110, Default = 70, Suffix = "°", Flag = "fov", Callback = function(v)
	workspace.CurrentCamera.FieldOfView = v
end })
Inputs:AddStepper({ Title = "Jump count", Min = 0, Max = 10, Default = 2, Flag = "jumps" })
Inputs:AddProgress({ Title = "Download", Default = 0.62 })

local Choices = Controls:AddSection("Choices")
Choices:AddDropdown({ Title = "Weapon", Options = { "Sword", "Bow", "Staff", "Hammer", "Dagger" }, Default = "Sword", Flag = "weapon", Icon = "target", IconColor = Color3.fromRGB(255, 69, 58) })
Choices:AddDropdown({ Title = "Targets", Description = "Multi-select with checkmarks", Options = { "Players", "NPCs", "Bosses", "Chests", "Doors" }, Multi = true, Default = { "Players", "Bosses" }, Flag = "targets" })
local players = {}
for _, p in ipairs(game.Players:GetPlayers()) do
	table.insert(players, p.Name)
end
Choices:AddDropdown({ Title = "Teleport to player", Options = players, Searchable = true, Icon = "user", IconColor = Color3.fromRGB(48, 209, 88) })
Choices:AddSegmented({ Options = { "Low", "Medium", "High", "Ultra" }, Default = "High", Flag = "quality" })

local Text = Controls:AddSection("Text & keys")
Text:AddInput({ Title = "Display name", Placeholder = "Enter a name", Flag = "name", Callback = function(t)
	LiquidGlass:Notify({ Title = "Name set", Content = t, Duration = 2 })
end })
Text:AddInput({ Title = "Notes", Multiline = true, Placeholder = "Multi-line text…" })
Text:AddKeybind({ Title = "Sprint", Default = Enum.KeyCode.LeftShift, Mode = "Hold", Flag = "sprintKey" })
Text:AddKeybind({ Title = "Fly", Default = "F", Flag = "flyKey", Callback = function(on)
	LiquidGlass:Notify({ Title = on and "Fly on" or "Fly off", Type = on and "Success" or "Info", Duration = 1.5 })
end })
Text:AddColorPicker({ Title = "ESP color", Default = Color3.fromRGB(255, 45, 85), Flag = "espColor" })
Text:AddColorPicker({ Title = "Glow", Description = "With transparency", Default = Color3.fromRGB(94, 92, 230), Transparency = 0.3, Flag = "glow" })

local Buttons = Controls:AddSection("Buttons")
Buttons:AddButton({ Title = "Rejoin server", Description = "Row buttons open things", Icon = "refresh", IconColor = Color3.fromRGB(142, 142, 147), Callback = function()
	LiquidGlass:Notify({ Title = "Rejoin", Content = "Pretending to rejoin…", Duration = 2 })
end })
Buttons:AddButton({ Title = "Copy join script", Accessory = "Copy", Icon = "copy", IconColor = Color3.fromRGB(10, 132, 255) })
Buttons:AddButton({ Title = "Primary action", Style = "Primary", Icon = "bolt" })
Buttons:AddButton({ Title = "Reset everything", Destructive = true, Icon = "trash", Tooltip = "Asks before resetting", Callback = function()
	Window:Dialog({ Title = "Reset everything?", Content = "This cannot be undone.", Icon = "warning", IconColor = "Danger", Buttons = { { Title = "Cancel", Style = "Cancel" }, { Title = "Reset", Style = "Destructive" } } })
end })
local locked = Buttons:AddToggle({ Title = "Locked feature", Description = "Disabled elements dim and ignore input", Disabled = true })
local _ = locked

-- Media ----------------------------------------------------------------------
local Media = Window:AddTab({ Title = "Media", Icon = "image" })
local Gallery = Media:AddSection("Images")
Gallery:AddImage({ Image = LiquidGlass:Avatar(game.Players.LocalPlayer.UserId, "AvatarBust"), Height = 180, Caption = "Your avatar (rbxthumb)", ScaleType = "Fit" })
Gallery:AddImage({ Image = "music", Height = 90, Caption = "Built-in icons scale too" })
local Code = Media:AddSection("Code")
Code:AddCode({ Title = "Load this library", Code = 'local LiquidGlass = loadstring(game:HttpGet("https://…/LiquidGlass.lua"))()' })
local Custom = Media:AddSection("Custom")
Custom:AddCustom({ Title = "Anything you want", Height = 60, Build = function(frame, el, lib)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 44)
	bar.BackgroundColor3 = Color3.fromRGB(10, 132, 255)
	bar.BackgroundTransparency = 0.2
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 12)
	local grad = Instance.new("UIGradient", bar)
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 45, 85), Color3.fromRGB(94, 92, 230))
	bar.Parent = frame
end })
Custom:AddLabel("Labels are plain text rows.")

-- Settings ---------------------------------------------------------------------
Window:AddSettingsTab()

LiquidGlass:Notify({ Title = "Liquid Glass loaded", Content = "Press Right Ctrl to hide or show the window.", Type = "Success", Duration = 5 })
