---------------------------------------------------------------------------
-- Configs: every element with a Flag can be saved and restored as JSON in the
-- executor workspace (LiquidGlass/configs/<folder>/<name>.json).
---------------------------------------------------------------------------
local configRoot = ROOT .. "/configs/" .. tostring(game.PlaceId)
local SAVED_TYPES = { Toggle = true, Slider = true, Dropdown = true, Input = true, Keybind = true, ColorPicker = true, Segmented = true, Stepper = true }

function Library:SetConfigFolder(name)
	configRoot = ROOT .. "/configs/" .. tostring(name)
end

local function serialize(el)
	local v = el.Value
	if el.Type == "ColorPicker" then
		return { Color = Util.toHex(v), Transparency = el.Transparency }
	end
	if typeof(v) == "EnumItem" then
		return v.Name
	end
	return v
end

function Library:SaveConfig(name)
	if not canFiles then
		return false, "no file access"
	end
	name = tostring(name or "default")
	local data = {}
	for flag, el in pairs(Library.Options) do
		if SAVED_TYPES[el.Type] and not (el.Opts and el.Opts.NoSave) then
			data[flag] = { Type = el.Type, Value = serialize(el) }
		end
	end
	local ok, err = pcall(function()
		Assets.folder(configRoot)
		writefile(configRoot .. "/" .. name .. ".json", HttpService:JSONEncode(data))
	end)
	return ok, err
end

function Library:LoadConfig(name)
	if not canFiles then
		return false, "no file access"
	end
	local path = configRoot .. "/" .. tostring(name or "default") .. ".json"
	if not isfile(path) then
		return false, "not found"
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)
	if not ok or type(data) ~= "table" then
		return false, "invalid config"
	end
	for flag, entry in pairs(data) do
		local el = Library.Options[flag]
		if el and el.Set and type(entry) == "table" then
			pcall(function()
				if el.Type == "ColorPicker" and type(entry.Value) == "table" then
					el:Set(Util.fromHex(entry.Value.Color), entry.Value.Transparency)
				else
					el:Set(entry.Value)
				end
			end)
		end
	end
	return true
end

function Library:DeleteConfig(name)
	local path = configRoot .. "/" .. tostring(name) .. ".json"
	if canFiles and typeof(delfile) == "function" and isfile(path) then
		pcall(delfile, path)
		return true
	end
	return false
end

function Library:ListConfigs()
	local out = {}
	if canFiles and typeof(listfiles) == "function" then
		local ok, files = pcall(listfiles, configRoot)
		if ok then
			for _, f in ipairs(files) do
				local n = tostring(f):match("([^/\\]+)%.json$")
				if n then
					table.insert(out, n)
				end
			end
		end
	end
	table.sort(out)
	return out
end

function Library:SetAutoload(name)
	if canFiles then
		Assets.folder(configRoot)
		pcall(writefile, configRoot .. "/autoload.txt", tostring(name or ""))
	end
end

function Library:LoadAutoload()
	local path = configRoot .. "/autoload.txt"
	if canFiles and isfile(path) then
		local name = readfile(path)
		if name ~= "" then
			return Library:LoadConfig(name)
		end
	end
	return false
end

-- Rayfield: ConfigurationSaving + :LoadConfiguration()
function Library:LoadConfiguration()
	if Library._autoSave then
		Library:LoadConfig(Library._autoSave)
	end
	Library._autoSaveReady = true
end

local saveQueued = false
local baseEmit = Element._emit
function Element:_emit(...)
	baseEmit(self, ...)
	if Library._autoSave and Library._autoSaveReady and self.Flag and not saveQueued then
		saveQueued = true
		task.delay(1, function()
			saveQueued = false
			Library:SaveConfig(Library._autoSave)
		end)
	end
end

local baseCreate = Library.CreateWindow
function Library:CreateWindow(o)
	o = o or {}
	local cs = o.ConfigurationSaving or o.ConfigSaving
	if type(cs) == "table" and cs.Enabled then
		Library:SetConfigFolder(cs.FolderName or game.PlaceId)
		Library._autoSave = cs.FileName or "config"
	end
	if type(o.Theme) == "string" and not THEMES[o.Theme] then
		o.Theme = o.Theme:lower():find("light") and "Light" or "Dark"
	end
	return baseCreate(self, o)
end

---------------------------------------------------------------------------
-- Ready-made settings tab
---------------------------------------------------------------------------
function Window:AddSettingsTab(o)
	o = o or {}
	local tab = self:AddTab({ Title = o.Title or "Settings", Icon = o.Icon or "settings" })
	local ap = tab:AddSection("Appearance")
	local themeSeg = ap:AddSegmented({ Title = "Theme", Options = { "Dark", "Light" }, Default = Library.Settings.Theme, Callback = function(v)
		if Library.Settings.Theme ~= v then
			Library:SetTheme(v)
		end
	end })
	-- settings mirror changes made from code or other controls
	Theme.onChange(function(t)
		if themeSeg.Value ~= t.Name and (t.Name == "Dark" or t.Name == "Light") then
			themeSeg:Set(t.Name, true)
		end
	end)
	ap:AddColorPicker({ Title = "Accent color", Icon = "palette", IconColor = "Accent", Default = Theme.value("Accent"), Callback = function(c)
		Library:SetAccent(c)
	end })
	ap:AddToggle({ Title = "Background blur", Description = "Frosted liquid glass behind every surface", Icon = "layers", IconColor = Color3.fromRGB(94, 92, 230), Default = Library.Settings.Blur, Callback = function(v)
		Library:SetBlur(v)
	end })
	ap:AddSlider({ Title = "Interface scale", Min = 0.6, Max = 1.4, Step = 0.05, Default = Library.Settings.Scale, Suffix = "×", Released = function(v)
		Library:SetScale(v)
	end })

	if self.Bar then
		local nav = tab:AddSection("Tab bar")
		local bar = self.Bar
		local posSeg = nav:AddSegmented({ Title = "Position", Options = { "Bottom", "Left", "Top", "Right" }, Default = bar.Position, Callback = function(v)
			if bar.Position ~= v or bar.Free then
				self:SetTabBarPosition(v)
			end
		end })
		local floatToggle = nav:AddToggle({ Title = "Detached", Description = "Floats next to the window instead of inside it", Icon = "external", IconColor = Color3.fromRGB(94, 92, 230), Default = bar.Floating, Callback = function(v)
			if bar.Floating ~= v then
				bar:setFloating(v)
			end
		end })
		local screenToggle = nav:AddToggle({ Title = "Pin to screen edge", Description = "Sits on the edge of the screen like a dock", Icon = "monitor", IconColor = Color3.fromRGB(10, 132, 255), Default = bar.Screen, Callback = function(v)
			if bar.Screen ~= v then
				bar:setScreen(v)
			end
		end })
		nav:AddToggle({ Title = "Lock position", Description = "Hides the grip so the bar can't be moved", Icon = "lock", IconColor = Color3.fromRGB(142, 142, 147), Default = bar.Locked, Callback = function(v)
			bar:setLocked(v)
		end })
		local alignSeg = nav:AddSegmented({ Title = "Along the edge", Description = "Where a pinned bar sits: Start is left or top, End is right or bottom", Options = { "Start", "Center", "End" }, Default = bar.Align, Callback = function(v)
			if bar.Align ~= v then
				bar:setPosition(bar.Position, { Align = v })
			end
		end })
		nav:AddToggle({ Title = "Hide with window", Description = "Otherwise a detached bar stays on screen to bring the window back", Icon = "eye-off", IconColor = Color3.fromRGB(255, 159, 10), Default = bar.HideWithWindow, Callback = function(v)
			if bar.HideWithWindow ~= v then
				bar.HideWithWindow = v
				bar:setShown(bar:wantShown())
			end
		end })
		nav:AddToggle({ Title = "Labels", Default = bar.Labels, Callback = function(v)
			if bar.Labels ~= v then
				self:SetTabBar({ Labels = v })
			end
		end })
		-- mirror moves made with the grip
		local userMoved = bar.OnMoved
		bar.OnMoved = function(position, floating, screen, align)
			if position ~= "Free" and posSeg.Value ~= position then
				posSeg:Set(position, true)
			end
			if floatToggle.Value ~= floating then
				floatToggle:Set(floating, true)
			end
			if screenToggle.Value ~= (screen == true) then
				screenToggle:Set(screen == true, true)
			end
			if align and alignSeg.Value ~= align then
				alignSeg:Set(align, true)
			end
			Util.fire(userMoved, position, floating, screen, align)
		end
	end

	local snd = tab:AddSection("Sound")
	snd:AddToggle({ Title = "Interface sounds", Icon = "volume", IconColor = Color3.fromRGB(255, 45, 85), Default = Library.Settings.Sounds, Callback = function(v)
		Library.Settings.Sounds = v
	end })
	snd:AddSlider({ Title = "Volume", Min = 0, Max = 100, Step = 1, Default = math.floor(Library.Settings.Volume * 100), Suffix = "%", Callback = function(v)
		Library.Settings.Volume = v / 100
	end, Released = function()
		Sound.play("click")
	end })

	local ctl = tab:AddSection("Controls")
	ctl:AddKeybind({ Title = "Show / hide interface", Icon = "keyboard", IconColor = Color3.fromRGB(142, 142, 147), Default = Library.ToggleKey, ChangedCallback = function(k)
		Library.ToggleKey = k
	end })
	ctl:AddDropdown({ Title = "Notifications", Options = { "TopRight", "TopLeft", "TopCenter", "BottomRight", "BottomLeft" }, Default = Library.NotifyPosition, Callback = function(v)
		Library.NotifyPosition = v
		Library:Notify({ Title = "Notifications moved", Content = "New notifications appear " .. v:gsub("(%l)(%u)", "%1 %2"):lower() .. ".", Duration = 3 })
	end })

	if canFiles then
		local cfg = tab:AddSection("Configuration")
		local nameInput = cfg:AddInput({ Title = "Config name", Placeholder = "default", Icon = "edit", IconColor = Color3.fromRGB(255, 159, 10) })
		local list = cfg:AddDropdown({ Title = "Saved configs", Options = Library:ListConfigs(), Placeholder = "None" })
		local function chosen()
			local n = nameInput.Value
			if n == nil or n == "" then
				n = list.Value
			end
			return (n ~= nil and n ~= "") and n or "default"
		end
		cfg:AddButtons({
			{ Title = "Save", Style = "Primary", Icon = "save", Callback = function()
				local name = chosen()
				local ok = Library:SaveConfig(name)
				list:SetOptions(Library:ListConfigs(), true)
				Library:Notify({ Title = ok and "Config saved" or "Save failed", Content = ok and ("Saved as “" .. name .. "”.") or "Could not write the file.", Type = ok and "Success" or "Error", Duration = 3 })
			end },
			{ Title = "Load", Icon = "download", Callback = function()
				local name = chosen()
				local ok, err = Library:LoadConfig(name)
				Library:Notify({ Title = ok and "Config loaded" or "Load failed", Content = ok and ("Loaded “" .. name .. "”.") or tostring(err), Type = ok and "Success" or "Error", Duration = 3 })
			end },
			{ Title = "Delete", Style = "Destructive", Icon = "trash", Callback = function()
				local name = chosen()
				Library:DeleteConfig(name)
				list:SetOptions(Library:ListConfigs(), false)
			end },
		})
		cfg:AddButton({ Title = "Load this config automatically", Icon = "refresh", IconColor = Color3.fromRGB(48, 209, 88), Callback = function()
			local name = chosen()
			Library:SetAutoload(name)
			Library:Notify({ Title = "Autoload set", Content = "“" .. name .. "” loads whenever the script starts.", Type = "Success", Duration = 3 })
		end })
	end

	local danger = tab:AddSection({})
	danger:AddButton({ Title = "Unload interface", Destructive = true, Icon = "power", Callback = function()
		self:Dialog({
			Title = "Unload " .. self.Title .. "?",
			Content = "This removes the interface. Features that already run keep running.",
			Icon = "power",
			IconColor = "Danger",
			Buttons = {
				{ Title = "Cancel", Style = "Cancel" },
				{ Title = "Unload", Style = "Destructive", Callback = function()
					Library:Destroy()
				end },
			},
		})
	end })
	return tab
end
Window.AddSettings = Window.AddSettingsTab

---------------------------------------------------------------------------
-- Unload
---------------------------------------------------------------------------
function Library:Destroy()
	if Library.Unloaded then
		return
	end
	for _, w in ipairs(table.clone(Library.Windows)) do
		w:Destroy()
	end
	if Overlay.active then
		Overlay.active.Close()
	end
	if Overlay.dialog then
		Overlay.dialog.Close()
	end
	Library.Unloaded = true
	Util.fire(Library.OnUnload)
	task.delay(0.4, function()
		for _, c in ipairs(connections) do
			pcall(function()
				c:Disconnect()
			end)
		end
		for _, fn in ipairs(cleanupTasks) do
			pcall(fn)
		end
		for _, s in pairs(Sound.pool) do
			if s then
				s:Destroy()
			end
		end
		Library.Gui:Destroy()
		if env.LiquidGlass == Library then
			env.LiquidGlass = nil
		end
	end)
end
Library.Unload = Library.Destroy

function Library:IsUnloaded()
	return Library.Unloaded
end

Library.Theme = Theme
Library.Assets = Assets
Library.Glass = Glass
Library.Motion = Motion
Library.Util = Util
Library._blur = Blur
Library._overlay = Overlay

return Library
