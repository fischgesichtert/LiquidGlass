--!nocheck
--[[
	LiquidGlass — an iOS 26 "Liquid Glass" UI library for Roblox.

	local LiquidGlass = loadstring(game:HttpGet("<raw url of dist/LiquidGlass.lua>"))()
	local Window = LiquidGlass:CreateWindow({ Title = "My Script", Icon = "sparkle" })
	local Tab = Window:AddTab({ Title = "Main", Icon = "home" })
	Tab:AddToggle({ Title = "Enabled", Default = true, Callback = function(v) end })

	Full API: README.md. Rayfield- and Fluent-style calls are accepted as well.
]]

local VERSION = "1.0.0"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")

local env = (typeof(getgenv) == "function" and getgenv()) or _G
if type(env.LiquidGlass) == "table" and type(env.LiquidGlass.Destroy) == "function" then
	pcall(function()
		env.LiquidGlass:Destroy()
	end)
end

local LocalPlayer = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local Library = {
	Version = VERSION,
	Flags = {},
	Options = {},
	Windows = {},
	Unloaded = false,
	ToggleKey = Enum.KeyCode.RightControl,
	NotifyPosition = "TopRight",
	Settings = { Sounds = true, Volume = 1, Blur = true, Theme = "Dark", Scale = 1 },
}
env.LiquidGlass = Library

local Util, Assets, Theme, Sound, Motion, Blur, Glass, Overlay = {}, {}, {}, {}, {}, {}, {}, {}
local connections, cleanupTasks = {}, {}

---------------------------------------------------------------------------
-- Util
---------------------------------------------------------------------------
function Util.track(c)
	connections[#connections + 1] = c
	return c
end

function Util.onCleanup(fn)
	cleanupTasks[#cleanupTasks + 1] = fn
end

function Util.new(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local new = Util.new

function Util.corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

function Util.pad(t, r, b, l)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, t),
		PaddingRight = UDim.new(0, r or t),
		PaddingBottom = UDim.new(0, b or t),
		PaddingLeft = UDim.new(0, l or r or t),
	})
end

function Util.list(dir, gap, props)
	local l = new("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

function Util.tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local tween = Util.tween

-- user callbacks run on their own thread; an error there never breaks the UI
function Util.fire(cb, ...)
	if type(cb) ~= "function" then
		return
	end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(cb, table.unpack(args, 1, args.n))
		if not ok then
			warn("[LiquidGlass] callback error: " .. tostring(err))
		end
	end)
end

-- first non-nil option among aliases
function Util.opt(o, default, ...)
	if type(o) ~= "table" then
		return default
	end
	for i = 1, select("#", ...) do
		local v = o[select(i, ...)]
		if v ~= nil then
			return v
		end
	end
	return default
end
local opt = Util.opt

function Util.decimals(step)
	local s = tostring(step)
	local dot = s:find("%.")
	return dot and #s - dot or 0
end

function Util.snap(v, min, step)
	if not step or step <= 0 then
		return v
	end
	return min + math.floor((v - min) / step + 0.5) * step
end

function Util.format(v, decimals)
	if decimals <= 0 then
		return tostring(math.floor(v + 0.5))
	end
	return string.format("%." .. decimals .. "f", v)
end

function Util.toHex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

function Util.fromHex(s)
	s = tostring(s):gsub("#", "")
	if #s == 3 then
		s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
	end
	if #s ~= 6 or not s:match("^%x+$") then
		return nil
	end
	return Color3.fromRGB(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16))
end

function Util.hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 4294967296
	end
	return string.format("%08x", h)
end

function Util.keyName(key)
	if key == nil then
		return "None"
	end
	if typeof(key) == "EnumItem" then
		local names = {
			MouseButton1 = "LMB", MouseButton2 = "RMB", MouseButton3 = "MMB",
			LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
			LeftAlt = "LAlt", RightAlt = "RAlt", Return = "Enter", Backspace = "Back",
		}
		return names[key.Name] or key.Name
	end
	return tostring(key)
end

function Util.toKey(v)
	if typeof(v) == "EnumItem" then
		return v
	end
	if type(v) == "string" and v ~= "" and v ~= "None" then
		local short = {
			MB1 = Enum.UserInputType.MouseButton1, MB2 = Enum.UserInputType.MouseButton2, MB3 = Enum.UserInputType.MouseButton3,
			LMB = Enum.UserInputType.MouseButton1, RMB = Enum.UserInputType.MouseButton2, MMB = Enum.UserInputType.MouseButton3,
		}
		if short[v:upper()] then
			return short[v:upper()]
		end
		local ok, k = pcall(function()
			return Enum.KeyCode[v]
		end)
		if ok and k then
			return k
		end
		ok, k = pcall(function()
			return Enum.UserInputType[v]
		end)
		if ok and k then
			return k
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Assets: textures, icons and sounds are embedded in this file and written
-- to the executor workspace once; images can come from anywhere.
---------------------------------------------------------------------------
--@ASSETS@--
PACK = PACK or {}
ASSET_VERSION = ASSET_VERSION or "dev"
ICON_INDEX = ICON_INDEX or {}
ICON_CELL, ICON_COLS = ICON_CELL or 64, ICON_COLS or 16

local ICON_ALIASES = {
	x = "close", ["x-circle"] = "error", ["check-mark"] = "check", gear = "settings", cog = "settings",
	person = "user", people = "users", ["add"] = "plus", remove = "minus", ["delete"] = "trash",
	["alert"] = "warning", ["alert-triangle"] = "warning", question = "help", notification = "bell",
	sparkle = "bolt", sparkles = "bolt", magic = "bolt", emoji = "smile", zap = "bolt", lightning = "bolt", flame = "fire",
	world = "globe", earth = "globe", note = "music", sound = "volume", speaker = "volume",
	["volume-x"] = "mute", picture = "image", photo = "image", controller = "gamepad", game = "gamepad",
	chevron = "chevron-right", ["arrow"] = "arrow-right", dots = "more", ellipsis = "more",
	["more-horizontal"] = "more", hamburger = "menu", cart = "cart", store = "shop", ["shopping-cart"] = "cart",
	crosshair = "target", aim = "target", eye_off = "eye-off", ["eye-closed"] = "eye-off",
	pencil = "edit", clipboard = "paste", ["file-text"] = "page", document = "file", script = "code",
	console = "terminal", settings2 = "cogs", plugin = "puzzle", bot = "robot", ai = "robot",
	run = "run", sprint = "run", fly = "airplane", plane = "airplane", teleport = "move", tp = "move",
	speedometer = "speed", stats = "chart", ["bar-chart"] = "chart", activity = "chart", server = "network",
	wallet = "card", money = "card", coins = "card", key = "key", password = "key", rotate = "rotate",
	reload = "refresh", ["rotate-ccw"] = "undo", ["rotate-cw"] = "redo", home = "home", house = "home",
	sun = "sun", moon = "moon", dark = "moon", light = "sun", info = "info", ["info-circle"] = "info",
	["check-circle-2"] = "check-circle", success = "check-circle", ["log-out"] = "logout", exit = "logout",
}
Library.Icons = {}
for name in pairs(ICON_INDEX) do
	table.insert(Library.Icons, name)
end
table.sort(Library.Icons)

local b64decode
do
	local native = (crypt and (crypt.base64decode or (crypt.base64 and crypt.base64.decode)))
		or base64_decode
		or (base64 and base64.decode)
		or (syn and syn.crypt and syn.crypt.base64 and syn.crypt.base64.decode)
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local lut = {}
	for i = 1, 64 do
		lut[string.byte(alphabet, i)] = i - 1
	end
	local function pure(s)
		s = s:gsub("[^%w%+/=]", "")
		local out = buffer.create(#s // 4 * 3)
		local n = 0
		for i = 1, #s - 3, 4 do
			local a, b, c, d = string.byte(s, i, i + 3)
			local v = lut[a] * 262144 + lut[b] * 4096 + (lut[c] or 0) * 64 + (lut[d] or 0)
			buffer.writeu8(out, n, v // 65536)
			n += 1
			if c ~= 61 then
				buffer.writeu8(out, n, (v // 256) % 256)
				n += 1
			end
			if d ~= 61 then
				buffer.writeu8(out, n, v % 256)
				n += 1
			end
		end
		return buffer.readstring(out, 0, n)
	end
	b64decode = function(s)
		if native then
			local ok, r = pcall(native, s)
			if ok and type(r) == "string" and #r > 0 then
				return r
			end
		end
		return pure(s)
	end
end

local customAsset = getcustomasset or getsynasset
local canFiles = typeof(writefile) == "function" and typeof(isfile) == "function" and typeof(customAsset) == "function"
local ROOT = "LiquidGlass"
Assets.cache = {}

function Assets.folder(path)
	if typeof(makefolder) ~= "function" then
		return
	end
	local acc = ""
	for part in path:gmatch("[^/]+") do
		acc = acc == "" and part or acc .. "/" .. part
		if typeof(isfolder) ~= "function" or not isfolder(acc) then
			pcall(makefolder, acc)
		end
	end
end

function Assets.get(name)
	local c = Assets.cache[name]
	if c ~= nil then
		return c or nil
	end
	local id = false
	if canFiles and PACK[name] then
		local path = ROOT .. "/assets/" .. ASSET_VERSION .. "/" .. name
		local ok, res = pcall(function()
			if not isfile(path) then
				Assets.folder(ROOT .. "/assets/" .. ASSET_VERSION)
				writefile(path, b64decode(PACK[name]))
			end
			return customAsset(path)
		end)
		if ok and res then
			id = res
		end
	end
	Assets.cache[name] = id
	return id or nil
end

function Assets.iconName(name)
	if type(name) ~= "string" then
		return nil
	end
	local n = name:lower():gsub("^lucide[%-:]", ""):gsub("_", "-")
	if ICON_INDEX[n] then
		return n
	end
	local alias = ICON_ALIASES[n]
	if alias and ICON_INDEX[alias] then
		return alias
	end
	return nil
end

-- Resolves any image source into {Image, Offset?, Size?}:
-- icon names, asset ids (number or string), rbxasset/rbxthumb/rbxhttp urls,
-- web urls (downloaded and cached), local workspace files, or a prepared table.
function Assets.resolve(src, onAsync)
	if src == nil or src == "" or src == false then
		return nil
	end
	if type(src) == "table" then
		return src.Image and src or nil
	end
	if type(src) == "number" then
		return { Image = "rbxassetid://" .. math.floor(src) }
	end
	if type(src) ~= "string" then
		return nil
	end
	local icon = Assets.iconName(src)
	if icon then
		local atlas = Assets.get("icons.png")
		local i = ICON_INDEX[icon]
		if atlas then
			return {
				Image = atlas,
				Offset = Vector2.new((i % ICON_COLS) * ICON_CELL, (i // ICON_COLS) * ICON_CELL),
				Size = Vector2.new(ICON_CELL, ICON_CELL),
				Icon = true,
			}
		end
		return nil
	end
	if src:match("^%d+$") then
		return { Image = "rbxassetid://" .. src }
	end
	if src:match("^[%w_%-]+$") then
		-- a bare word can only be an icon name
		Assets.warned = Assets.warned or {}
		if not Assets.warned[src] then
			Assets.warned[src] = true
			warn(("[LiquidGlass] unknown icon %q (see LiquidGlass.Icons)"):format(src))
		end
		return nil
	end
	local lower = src:lower()
	if lower:match("^rbxasset") or lower:match("^rbxthumb") or lower:match("^rbxhttp") or lower:match("roblox%.com/asset") then
		return { Image = src }
	end
	if lower:match("^https?://") then
		return Assets.remote(src, onAsync)
	end
	if canFiles and pcall(isfile, src) and isfile(src) then
		local ok, id = pcall(customAsset, src)
		return ok and { Image = id } or nil
	end
	return { Image = src }
end

local remoteCache = {}
function Assets.remote(url, onAsync)
	local cached = remoteCache[url]
	if type(cached) == "table" then
		return cached
	end
	if not canFiles then
		return nil
	end
	if cached == nil then
		remoteCache[url] = { waiting = { onAsync } }
		task.spawn(function()
			local ext = url:lower():match("%.(%a%a%a%a?)[%?#]?") or "png"
			if ext ~= "png" and ext ~= "jpg" and ext ~= "jpeg" then
				ext = "png"
			end
			local path = ROOT .. "/cache/" .. Util.hash(url) .. "." .. ext
			local ok, res = pcall(function()
				if not isfile(path) then
					local body
					local req = (syn and syn.request) or (http and http.request) or http_request or request
					if req then
						local r = req({ Url = url, Method = "GET" })
						body = r and (r.Body or r.body)
					end
					if not body or #body == 0 then
						body = game:HttpGet(url)
					end
					Assets.folder(ROOT .. "/cache")
					writefile(path, body)
				end
				return customAsset(path)
			end)
			local waiting = remoteCache[url].waiting
			local result = ok and res and { Image = res } or false
			remoteCache[url] = result
			for _, cb in ipairs(waiting) do
				if cb and result then
					task.spawn(cb, result)
				end
			end
		end)
	elseif onAsync then
		table.insert(cached.waiting, onAsync)
	end
	return nil
end

-- applies any image source to an ImageLabel/ImageButton; returns true when it resolved now
function Assets.apply(img, src, tint)
	img:SetAttribute("LGSource", tostring(src))
	local function set(r)
		-- a late download must not overwrite an image that changed meanwhile
		if not r or img:GetAttribute("LGSource") ~= tostring(src) then
			return
		end
		img.Image = r.Image
		img.ImageRectOffset = r.Offset or Vector2.zero
		img.ImageRectSize = r.Size or Vector2.zero
		if tint ~= nil then
			img.ImageColor3 = tint
		end
	end
	local r = Assets.resolve(src, set)
	if r then
		set(r)
		return true, r
	end
	img.Image = ""
	return false
end

function Assets.isIcon(src)
	return Assets.iconName(src) ~= nil
end

function Library:GetIcon(name)
	return Assets.resolve(name)
end

function Library:Avatar(userId, kind)
	return ("rbxthumb://type=%s&id=%d&w=150&h=150"):format(kind or "AvatarHeadShot", tonumber(userId) or LocalPlayer.UserId)
end

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------
local FONT_FAMILY = "rbxasset://fonts/families/BuilderSans.json"
local fontCache = {}
function Util.font(weight)
	weight = weight or Enum.FontWeight.Regular
	local f = fontCache[weight]
	if not f then
		f = Font.new(FONT_FAMILY, weight)
		fontCache[weight] = f
	end
	return f
end

-- any font as a family id: Enum.Font, Font, "Gotham", or a full rbxasset/rbxassetid family
function Util.fontFamily(v)
	if typeof(v) == "EnumItem" then
		return Font.fromEnum(v).Family
	elseif typeof(v) == "Font" then
		return v.Family
	elseif type(v) == "string" then
		if v:find("://") then
			return v
		end
		local ok, e = pcall(function()
			return Enum.Font[v]
		end)
		if ok and e then
			return Font.fromEnum(e).Family
		end
		return "rbxasset://fonts/families/" .. v .. ".json"
	end
	return nil
end

-- the interface font for everything created afterwards
function Library:SetFont(v)
	local fam = Util.fontFamily(v)
	if fam then
		FONT_FAMILY = fam
		table.clear(fontCache)
		Library.Settings.Font = fam
	end
end
local MONO = Font.fromEnum(Enum.Font.RobotoMono)

-- Metrics: every size in the library comes from here. 4 px grid, one type
-- ramp, and nested corners are concentric (inner radius = outer - inset).
local S = {
	-- type ramp
	LargeTitle = 24, Title = 17, Body = 15, Callout = 14, Subhead = 13, Footnote = 12, Caption = 11,
	-- window
	WindowRadius = 26, WindowInset = 8, Gutter = 16, Header = 56,
	-- sidebar (icon axis x = 30 both expanded and collapsed; text axis x = 52)
	Sidebar = 208, SidebarMini = 60, TabRow = 36, TabGap = 2, IconAxis = 30, TextAxis = 52,
	-- lists
	CardRadius = 18, RowInset = 16, RowPadY = 12, RowMin = 48, RowGap = 3,
	Badge = 28, BadgeRadius = 7, BadgeIcon = 16, RowIcon = 20, IconGap = 12,
	HighlightInset = 4, SectionGap = 20, HeaderGap = 6,
	-- controls
	Control = 30, Field = 170, Segmented = 32, Chevron = 12,
	SwitchW = 62, SwitchH = 28, KnobW = 38, KnobH = 24,
	Button = 36, ButtonLarge = 40, ButtonSmall = 30, IconButton = 30,
	-- overlays
	PopoverRadius = 20, MenuInset = 6, MenuItem = 38, Notify = 340, NotifyRadius = 22, NotifyPad = 14, NotifyBadge = 36,
	DialogW = 300, DialogRadius = 26, DialogPad = 20,
	-- floating tab bar
	TabBarItem = 74, TabBarHeight = 56, TabBarInset = 4, TabBarGap = 12,
}
local BASE_METRICS = table.clone(S)

-- values derived from others; recomputed whenever metrics change
local function deriveMetrics()
	S.SidebarRadius = S.WindowRadius - S.WindowInset
	S.TabRadius = math.max(S.SidebarRadius - S.WindowInset, 6)
	S.HighlightRadius = math.max(S.CardRadius - S.HighlightInset, 4)
	S.TextX = S.RowInset + S.Badge + S.IconGap
	S.SidebarMini = S.IconAxis * 2
end
deriveMetrics()
Library.Metrics = S

-- Density presets: complete, balanced metric sets (rows, controls, type, radii)
local DENSITIES = {
	Regular = {},
	Compact = {
		LargeTitle = 21, Title = 16, Body = 14, Callout = 13, Subhead = 12, Footnote = 11, Caption = 10,
		WindowRadius = 22, Gutter = 14, Header = 50, Sidebar = 188, TabRow = 32, IconAxis = 28, TextAxis = 50,
		CardRadius = 16, RowInset = 14, RowPadY = 10, RowMin = 40, Badge = 24, BadgeRadius = 6, BadgeIcon = 14,
		RowIcon = 18, IconGap = 10, SectionGap = 16, Control = 26, Field = 150, Segmented = 28, Chevron = 11,
		SwitchW = 52, SwitchH = 24, KnobW = 32, KnobH = 20, Button = 32, ButtonLarge = 36, ButtonSmall = 26, IconButton = 26,
		PopoverRadius = 18, MenuItem = 34, Notify = 320, NotifyRadius = 20, NotifyPad = 12, NotifyBadge = 32,
		DialogW = 280, DialogRadius = 24, DialogPad = 18, TabBarItem = 64, TabBarHeight = 50,
	},
	Large = {
		LargeTitle = 28, Title = 19, Body = 17, Callout = 16, Subhead = 15, Footnote = 13, Caption = 12,
		WindowRadius = 30, Gutter = 18, Header = 62, Sidebar = 228, TabRow = 40, IconAxis = 32, TextAxis = 58,
		CardRadius = 20, RowInset = 18, RowPadY = 14, RowMin = 56, Badge = 32, BadgeRadius = 8, BadgeIcon = 18,
		RowIcon = 22, IconGap = 14, SectionGap = 24, Control = 34, Field = 190, Segmented = 36, Chevron = 13,
		SwitchW = 68, SwitchH = 32, KnobW = 42, KnobH = 28, Button = 42, ButtonLarge = 48, ButtonSmall = 34, IconButton = 34,
		PopoverRadius = 22, MenuItem = 42, Notify = 370, NotifyRadius = 24, NotifyPad = 16, NotifyBadge = 40,
		DialogW = 330, DialogRadius = 28, DialogPad = 22, TabBarItem = 84, TabBarHeight = 62,
	},
}
Library.Densities = DENSITIES

-- Changes any metric (see README "Metrics"). Affects everything created afterwards,
-- so call it before CreateWindow. Unknown keys are ignored with a warning.
function Library:SetMetrics(overrides)
	for k, v in pairs(overrides or {}) do
		if BASE_METRICS[k] ~= nil and type(v) == "number" then
			S[k] = v
		else
			warn(("[LiquidGlass] unknown metric %q"):format(tostring(k)))
		end
	end
	-- keep the knob inside its switch
	S.KnobH = math.min(S.KnobH, S.SwitchH - 4)
	S.KnobW = math.min(S.KnobW, S.SwitchW - 8)
	deriveMetrics()
end

function Library:SetDensity(name)
	local preset = DENSITIES[name] or (type(name) == "table" and name)
	if not preset then
		warn(("[LiquidGlass] unknown density %q (Compact, Regular, Large)"):format(tostring(name)))
		return
	end
	for k, v in pairs(BASE_METRICS) do
		S[k] = v
	end
	Library.Settings.Density = type(name) == "string" and name or "Custom"
	Library:SetMetrics(preset)
end

function Library:ResetMetrics()
	Library:SetDensity("Regular")
end

local THEMES = {
	Dark = {
		Name = "Dark",
		Text = WHITE, Text2T = 0.4, Text3T = 0.62,
		Glass = WHITE, GlassT = 0.9, Dim = BLACK, DimT = 0.55, DenseDimT = 0.05, StackDimT = 0.16,
		Card = WHITE, CardT = 0.94, CardRim = 0.5,
		Control = WHITE, ControlT = 0.87, ControlRim = 0.85,
		Track = WHITE, TrackT = 0.8, Separator = WHITE, SeparatorT = 0.9,
		Highlight = WHITE, HighlightT = 0.93, PressT = 0.88,
		Knob = WHITE, Shadow = 0.36, Rim = 1,
		Overlay = BLACK, OverlayT = 0.55,
		Field = BLACK, FieldT = 0.82,
		Accent = Color3.fromRGB(10, 132, 255), Switch = Color3.fromRGB(48, 209, 88),
		Danger = Color3.fromRGB(255, 69, 58), Warning = Color3.fromRGB(255, 159, 10),
		Success = Color3.fromRGB(48, 209, 88), OnAccent = WHITE,
	},
	Light = {
		Name = "Light",
		Text = Color3.fromRGB(18, 18, 22), Text2T = 0.45, Text3T = 0.65,
		Glass = WHITE, GlassT = 0.62, Dim = WHITE, DimT = 0.78, DenseDimT = 0.12, StackDimT = 0.18,
		Card = WHITE, CardT = 0.55, CardRim = 0.85,
		Control = WHITE, ControlT = 0.45, ControlRim = 0.9,
		Track = Color3.fromRGB(120, 120, 128), TrackT = 0.78, Separator = BLACK, SeparatorT = 0.9,
		Highlight = BLACK, HighlightT = 0.95, PressT = 0.9,
		Knob = WHITE, Shadow = 0.22, Rim = 1,
		Overlay = BLACK, OverlayT = 0.75,
		Field = BLACK, FieldT = 0.94,
		Accent = Color3.fromRGB(0, 122, 255), Switch = Color3.fromRGB(52, 199, 89),
		Danger = Color3.fromRGB(255, 59, 48), Warning = Color3.fromRGB(255, 149, 0),
		Success = Color3.fromRGB(52, 199, 89), OnAccent = WHITE,
	},
}
Library.Themes = THEMES

Theme.binds = setmetatable({}, { __mode = "k" })
Theme.accent = nil
Theme.current = THEMES.Dark

function Theme.value(token)
	if type(token) == "function" then
		return token(Theme.current)
	end
	if type(token) ~= "string" then
		return token -- a literal value (Color3, number) instead of a theme token
	end
	if token == "Accent" and Theme.accent then
		return Theme.accent
	end
	return Theme.current[token]
end

function Theme.apply(inst, map, time)
	for prop, token in pairs(map) do
		local v = Theme.value(token)
		if v ~= nil then
			if time and time > 0 then
				tween(inst, time, { [prop] = v }, Enum.EasingStyle.Quad)
			else
				inst[prop] = v
			end
		end
	end
end

-- keeps instance properties in sync with theme tokens (or functions of the theme)
function Theme.bind(inst, map)
	local existing = Theme.binds[inst]
	if existing then
		for k, v in pairs(map) do
			existing[k] = v
		end
	else
		Theme.binds[inst] = map
	end
	Theme.apply(inst, map)
	return inst
end

function Theme.unbind(inst, prop)
	local m = Theme.binds[inst]
	if m then
		m[prop] = nil
	end
end

function Theme.refresh(time)
	for inst, map in pairs(Theme.binds) do
		if inst.Parent then
			Theme.apply(inst, map, time)
		end
	end
	for _, fn in ipairs(Theme.listeners or {}) do
		pcall(fn, Theme.current)
	end
end

function Theme.onChange(fn)
	Theme.listeners = Theme.listeners or {}
	table.insert(Theme.listeners, fn)
end

function Library:SetTheme(name)
	local t = THEMES[name] or (type(name) == "table" and name)
	if not t then
		return
	end
	Theme.current = t
	Library.Settings.Theme = t.Name or "Custom"
	Theme.refresh(0.35)
end

function Library:SetAccent(color)
	if typeof(color) == "string" then
		color = Util.fromHex(color)
	end
	Theme.accent = color
	Theme.refresh(0.25)
end

-- change single theme values live, e.g. SetThemeValue("GlassT", 0.8) or ("Text", Color3...)
function Library:SetThemeValue(key, value)
	if type(key) == "table" then
		for k, v in pairs(key) do
			Theme.current[k] = v
		end
	else
		Theme.current[key] = value
	end
	Theme.refresh(0.25)
end

function Library:GetTheme()
	return Theme.current
end

function Library:AddTheme(name, base, overrides)
	local t = table.clone(THEMES[base] or THEMES.Dark)
	for k, v in pairs(overrides or {}) do
		t[k] = v
	end
	t.Name = name
	THEMES[name] = t
	return t
end

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------
local SOUNDS = {
	hover = { files = { "hover_1.ogg", "hover_2.ogg" }, volume = 0.1, gap = 0.05 },
	click = { files = { "click_1.ogg", "click_2.ogg" }, volume = 0.4, gap = 0.03 },
	toggle_on = { files = { "toggle_on.ogg" }, volume = 0.45 },
	toggle_off = { files = { "toggle_off.ogg" }, volume = 0.4 },
	tick = { files = { "slider_tick.ogg" }, volume = 0.16, gap = 0.035, pitch = 0.08 },
	open = { files = { "open.ogg" }, volume = 0.35 },
	close = { files = { "close.ogg" }, volume = 0.3 },
	notify = { files = { "notify.ogg" }, volume = 0.45 },
	success = { files = { "success.ogg" }, volume = 0.45 },
	error = { files = { "error.ogg" }, volume = 0.45 },
	tab = { files = { "tab.ogg" }, volume = 0.28, gap = 0.04 },
	popup = { files = { "popup.ogg" }, volume = 0.35, gap = 0.05 },
	intro = { files = { "intro.ogg" }, volume = 0.6 },
	type = { files = { "type_1.ogg", "type_2.ogg" }, volume = 0.14, gap = 0.025, pitch = 0.1 },
}
Sound.pool = {}

function Sound.play(name)
	if not Library.Settings.Sounds or Library.Unloaded then
		return
	end
	local def = SOUNDS[name]
	if not def then
		return
	end
	local now = os.clock()
	if def.gap and def.last and now - def.last < def.gap then
		return
	end
	def.last = now
	local file = def.files[math.random(1, #def.files)]
	local s = Sound.pool[file]
	if s == nil then
		local id = Assets.get(file)
		if id then
			s = new("Sound", { Name = "LiquidGlass_" .. name, SoundId = id, Parent = SoundService })
		else
			s = false
		end
		Sound.pool[file] = s
	end
	if not s then
		return
	end
	s.Volume = def.volume * Library.Settings.Volume
	s.PlaybackSpeed = 1 + (def.pitch and (math.random() - 0.5) * def.pitch or 0)
	s.TimePosition = 0
	s:Play()
end

function Library:PlaySound(name)
	Sound.play(name)
end

---------------------------------------------------------------------------
-- Motion: one pointer space, drags, springs, rubber banding
---------------------------------------------------------------------------
-- Pointer and GUI positions share one space: window pixels including the topbar.
-- An input's own position is exact for that event; GetMouseLocation can still
-- report the previous frame's position when an event arrives.
local POSITIONAL = {
	[Enum.UserInputType.MouseButton1] = true, [Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true, [Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.Touch] = true, [Enum.UserInputType.MouseWheel] = true,
}
local lastPointer
function Motion.pointer(input)
	if input and POSITIONAL[input.UserInputType] then
		return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	end
	return lastPointer or UserInputService:GetMouseLocation()
end
local function trackPointer(input)
	if POSITIONAL[input.UserInputType] then
		lastPointer = Motion.pointer(input)
	end
end
Util.track(UserInputService.InputChanged:Connect(trackPointer))
Util.track(UserInputService.InputBegan:Connect(trackPointer))
local pointer = Motion.pointer

function Motion.screenPos(obj)
	return obj.AbsolutePosition - Library.Gui.AbsolutePosition
end
local screenPos = Motion.screenPos

function Motion.inside(obj, p)
	p = p or pointer()
	local pos, size = screenPos(obj), obj.AbsoluteSize
	return p.X >= pos.X and p.Y >= pos.Y and p.X <= pos.X + size.X and p.Y <= pos.Y + size.Y
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
Motion.isPress = isPress

-- began(p) / moved(p, delta, moved) / ended(p, moved, input); moved = travelled past 4px.
-- The release position is delivered through moved() first, so it always counts.
function Motion.drag(hit, cb)
	local active, start, moved, touch, last = false, nil, false, nil, nil
	local function finish(input)
		active = false
		local p = input and pointer(input) or last
		if p and last and p ~= last and cb.moved then
			moved = moved or (p - start).Magnitude > 4
			last = p
			cb.moved(p, p - start, moved)
		end
		if cb.ended then
			cb.ended(p or start, moved, input)
		end
	end
	hit.InputBegan:Connect(function(input)
		if isPress(input) then
			if cb.allow and not cb.allow() then
				return
			end
			if active then
				-- a release we never saw (focus loss, another script) must not lock the control
				finish(nil)
			end
			active, moved = true, false
			start = pointer(input)
			last = start
			touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
			if cb.began then
				cb.began(start)
			end
		end
	end)
	Util.track(UserInputService.InputChanged:Connect(function(input)
		if not active then
			return
		end
		local mouseMove = input.UserInputType == Enum.UserInputType.MouseMovement and not touch
		if mouseMove or (touch and input == touch) then
			local p = pointer(input)
			if p == last then
				return
			end
			last = p
			moved = moved or (p - start).Magnitude > 4
			if cb.moved then
				cb.moved(p, p - start, moved)
			end
		end
	end))
	Util.track(UserInputService.InputEnded:Connect(function(input)
		if active and isPress(input) and (not touch or input == touch) then
			finish(input)
		end
	end))
	return function()
		return active
	end
end

-- Springs drive offset positions so drags glide and interrupted motion stays
-- continuous (damping 1 = no overshoot, < 1 = liquid bounce). With a stretch
-- spec {Base = Vector2 px, Rest = UDim2, Axis = "X"/"Y"} the object also stretches
-- along its velocity like a drop, keeping its center, and returns to Rest after.
local springs = {}
function Motion.spring(inst, target, speed, damping, stretch)
	local s = springs[inst]
	if not s then
		s = { pos = Vector2.new(inst.Position.X.Offset, inst.Position.Y.Offset), vel = Vector2.zero }
		springs[inst] = s
	end
	s.target, s.speed, s.damping = target, speed or 30, damping or 1
	s.stretch = stretch or s.stretch
end

function Motion.target(inst)
	local s = springs[inst]
	return s and s.target or Vector2.new(inst.Position.X.Offset, inst.Position.Y.Offset)
end

function Motion.stop(inst)
	springs[inst] = nil
end

Util.track(RunService.RenderStepped:Connect(function(dt)
	local steps = math.clamp(math.ceil(dt * 240), 1, 16)
	local h = dt / steps
	for inst, s in pairs(springs) do
		if not inst.Parent then
			springs[inst] = nil
			continue
		end
		local w, z = s.speed, s.damping
		for _ = 1, steps do
			s.vel += ((s.target - s.pos) * (w * w) - s.vel * (2 * z * w)) * h
			s.pos += s.vel * h
		end
		local done = (s.target - s.pos).Magnitude < 0.02 and s.vel.Magnitude < 0.5
		if done then
			s.pos, s.vel = s.target, Vector2.zero
			springs[inst] = nil
		end
		local x, y = s.pos.X, s.pos.Y
		local st = s.stretch
		if st then
			if done then
				inst.Size = st.Rest
			elseif st.Axis == "Y" then
				local k = math.min(math.abs(s.vel.Y) / 1600, 0.32)
				local extra = st.Base.Y * k
				inst.Size = UDim2.new(st.Rest.X.Scale, st.Rest.X.Offset, st.Rest.Y.Scale, st.Rest.Y.Offset + extra)
				y -= extra * (0.5 - inst.AnchorPoint.Y)
			else
				local k = math.min(math.abs(s.vel.X) / 1600, 0.32)
				local extra = st.Base.X * k
				inst.Size = UDim2.new(st.Rest.X.Scale, st.Rest.X.Offset + extra, st.Rest.Y.Scale, st.Rest.Y.Offset)
				x -= extra * (0.5 - inst.AnchorPoint.X)
			end
		end
		local p = inst.Position
		inst.Position = UDim2.new(p.X.Scale, x, p.Y.Scale, y)
	end
end))

function Motion.rubber(x, lo, hi, give)
	if x < lo then
		return lo - give * (1 - 1 / ((lo - x) / give + 1))
	elseif x > hi then
		return hi + give * (1 - 1 / ((x - hi) / give + 1))
	end
	return x
end

-- Cross-fades a subtree by wrapping it in a CanvasGroup only while animating,
-- so text stays pixel-sharp the rest of the time.
-- A fade that starts while another runs takes over the same group; only the
-- newest fade unwraps it and runs its `done`, so interrupted fades never stack.
local fadeOwners = setmetatable({}, { __mode = "k" })
function Motion.groupFade(frame, from, to, time, done)
	local group = frame.Parent
	if not (group and group:IsA("CanvasGroup") and group.Name == "LGFade") then
		local holder = frame.Parent
		if not holder then
			return
		end
		group = new("CanvasGroup", {
			Name = "LGFade",
			BackgroundTransparency = 1,
			-- mirror the frame's sizing so auto-sized parents keep their height
			Size = frame.Size,
			AutomaticSize = frame.AutomaticSize,
			ZIndex = frame.ZIndex,
			LayoutOrder = frame.LayoutOrder,
			GroupTransparency = from,
			Parent = holder,
		})
		group:SetAttribute("Mirrors", frame.Name)
		frame.Parent = group
	end
	local token = {}
	fadeOwners[group] = token
	local tw = tween(group, time, { GroupTransparency = to }, Enum.EasingStyle.Quad)
	tw.Completed:Once(function()
		if fadeOwners[group] ~= token then
			return
		end
		fadeOwners[group] = nil
		if frame.Parent == group then
			frame.Parent = group.Parent
		end
		group:Destroy()
		if done then
			done()
		end
	end)
	return tw
end
