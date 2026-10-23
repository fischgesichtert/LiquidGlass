---------------------------------------------------------------------------
-- ScreenGui
---------------------------------------------------------------------------
do
	local function guiParent()
		local ok, h = pcall(function()
			return gethui and gethui()
		end)
		if ok and h then
			return h
		end
		local core = game:GetService("CoreGui")
		if pcall(function()
			return core:GetChildren()
		end) then
			return core
		end
		return LocalPlayer:WaitForChild("PlayerGui")
	end
	Library.Gui = new("ScreenGui", {
		Name = "LiquidGlass",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10000,
		AutoLocalize = false,
	})
	pcall(function()
		Library.Gui.ScreenInsets = Enum.ScreenInsets.None
	end)
	if syn and syn.protect_gui then
		pcall(syn.protect_gui, Library.Gui)
	end
	Library.Gui.Parent = guiParent()
	Library.ScaleObject = new("UIScale", { Parent = Library.Gui })
end

local zCounter = 10
local function nextZ(n)
	zCounter += n or 1
	return zCounter
end
Library._nextZ = nextZ

-- windows keep their on-screen center and stay reachable when the scale changes
function Library:SetScale(s)
	s = math.clamp(tonumber(s) or 1, 0.4, 2)
	local old = Library.ScaleObject.Scale
	Library.Settings.Scale = s
	Library.ScaleObject.Scale = s
	local vs = camera.ViewportSize / s
	for _, w in ipairs(Library.Windows) do
		local root = w.Root
		local pos = Motion.target(root)
		local size = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
		local center = (pos + size / 2) * old / s
		local fit = Vector2.new(math.clamp(size.X, w.MinSize.X, math.max(vs.X - 20, w.MinSize.X)), math.clamp(size.Y, w.MinSize.Y, math.max(vs.Y - 20, w.MinSize.Y)))
		root.Size = UDim2.fromOffset(fit.X, fit.Y)
		local np = w:_clampPos(center - fit / 2)
		Motion.stop(root)
		root.Position = UDim2.fromOffset(np.X, np.Y)
	end
	if Overlay.layoutNotifications then
		Overlay.layoutNotifications()
	end
	if Overlay.active then
		Overlay.active.Close()
	end
end

local function typing()
	return UserInputService:GetFocusedTextBox() ~= nil
end
Library._typing = typing

---------------------------------------------------------------------------
-- Smooth scrolling: mouse wheel eases the canvas; the topmost scroller under the
-- pointer wins; a thin indicator fades in while scrolling (iOS style).
---------------------------------------------------------------------------
local scrollers = {}
local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

function Glass.scroller(sf, o)
	o = o or {}
	local s = { sf = sf, target = 0, last = 0, prio = o.Priority or function()
		return 0
	end }
	sf.ScrollingEnabled = touchOnly
	sf.ScrollBarThickness = 0
	sf.Active = true
	local indicator = new("Frame", {
		Name = "ScrollIndicator",
		AnchorPoint = Vector2.new(1, 0),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(3, 30),
		ZIndex = 40,
		Parent = o.IndicatorParent or sf.Parent,
	}, { Util.corner(2) })
	Theme.bind(indicator, { BackgroundColor3 = "Text" })
	s.indicator = indicator
	local shownT = 1
	local function maxY()
		return math.max(sf.AbsoluteCanvasSize.Y - sf.AbsoluteWindowSize.Y, 0)
	end
	function s.wheel(z)
		s.target = math.clamp(s.target - z * 90, 0, maxY())
		s.last = os.clock()
	end
	function s.scrollTo(y, instant)
		s.target = math.clamp(y, 0, maxY())
		if instant then
			sf.CanvasPosition = Vector2.new(0, s.target)
		end
	end
	function s.step(dt)
		if not sf.Parent then
			return false
		end
		local m = maxY()
		local cur = sf.CanvasPosition.Y
		if touchOnly then
			s.target = cur
		else
			s.target = math.clamp(s.target, 0, m)
			if math.abs(s.target - cur) > 0.25 then
				sf.CanvasPosition = Vector2.new(0, cur + (s.target - cur) * (1 - math.exp(-dt * 16)))
				s.last = os.clock()
			end
		end
		-- indicator
		local win = sf.AbsoluteWindowSize.Y
		local active = m > 1 and (os.clock() - s.last < 0.9)
		local want = active and 0.55 or 1
		shownT += (want - shownT) * (1 - math.exp(-dt * (active and 18 or 6)))
		indicator.BackgroundTransparency = shownT
		if m > 1 then
			local h = math.max(24, win * win / sf.AbsoluteCanvasSize.Y)
			local y = (sf.CanvasPosition.Y / m) * (win - h - 8) + 4
			local base = screenPos(sf) - screenPos(indicator.Parent)
			indicator.Size = UDim2.fromOffset(3, h)
			indicator.Position = UDim2.fromOffset(base.X + sf.AbsoluteSize.X - 2, base.Y + y)
		end
		return true
	end
	table.insert(scrollers, s)
	return s
end

Util.track(UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	local best, bestPrio
	local p = pointer(input)
	for _, s in ipairs(scrollers) do
		local sf = s.sf
		if sf.Parent and sf.Visible and Motion.inside(sf, p) then
			local visible = true
			local o = sf
			while o and o ~= Library.Gui do
				if o:IsA("GuiObject") and not o.Visible then
					visible = false
					break
				end
				o = o.Parent
			end
			if visible then
				local pr = s.prio()
				if not bestPrio or pr >= bestPrio then
					best, bestPrio = s, pr
				end
			end
		end
	end
	if best then
		best.wheel(input.Position.Z)
	end
end))

Util.track(RunService.RenderStepped:Connect(function(dt)
	for i = #scrollers, 1, -1 do
		if not scrollers[i].step(dt) then
			table.remove(scrollers, i)
		end
	end
end))

---------------------------------------------------------------------------
-- Selector: tap or drag a glass pill across items. While held the pill lifts
-- into a clear glass lens that follows the pointer and magnifies the item under
-- it, then snaps onto the nearest item with a liquid bounce.
---------------------------------------------------------------------------
-- o: Hit (GuiButton receiving input), Ref (frame whose top-left is the pill's
-- coordinate origin), Pill (glass), Count(), Slot(i) -> Vector2, Axis ("X"/"Y"),
-- Items() -> {GuiObject}, Paint(i, held), OnSelect(i), Magnify, LensScale
function Glass.selector(o)
	local pill = o.Pill
	local axis = o.Axis or "X"
	local current = o.Initial or 1
	local held, under = false, nil
	local scales = setmetatable({}, { __mode = "k" })
	local baseFill = pill.Fill.BackgroundTransparency
	local sel = {}
	local rest = pill.Root.Size

	-- the pill's size at rest in px (never the stretched size, or it would grow forever)
	local function pillSize()
		local parent = pill.Root.Parent
		local ps = parent and (parent:IsA("ScrollingFrame") and parent.AbsoluteWindowSize or parent.AbsoluteSize) or Vector2.zero
		ps = ps / Library.ScaleObject.Scale
		return Vector2.new(ps.X * rest.X.Scale + rest.X.Offset, ps.Y * rest.Y.Scale + rest.Y.Offset)
	end
	local function stretch()
		return { Base = pillSize(), Rest = rest, Axis = axis }
	end
	local function scaleOf(item)
		local sc = scales[item]
		if not sc then
			sc = item:FindFirstChild("LensScale") or new("UIScale", { Name = "LensScale", Parent = item })
			scales[item] = sc
		end
		return sc
	end
	local function localPos(p)
		local s = Library.ScaleObject.Scale
		local lp = (p - screenPos(o.Ref)) / s
		if o.Ref:IsA("ScrollingFrame") then
			lp += o.Ref.CanvasPosition
		end
		return lp
	end
	local function nearest(lp)
		local best, bd = 1, math.huge
		local size = pillSize()
		for i = 1, o.Count() do
			local c = o.Slot(i) + size / 2
			local d = axis == "X" and math.abs(lp.X - c.X) or math.abs(lp.Y - c.Y)
			if d < bd then
				best, bd = i, d
			end
		end
		return best
	end
	local function hover(i)
		if i == under then
			return
		end
		under = i
		local items = o.Items and o.Items() or {}
		for j, item in ipairs(items) do
			tween(scaleOf(item), 0.25, { Scale = (held and j == i) and (o.Magnify or 1.1) or 1 })
		end
		if held then
			Sound.play("tick")
		end
		if o.Paint then
			o.Paint(i, held)
		end
	end
	local function lens(on)
		tween(pill.Scale, on and 0.3 or 0.55, { Scale = on and (o.LensScale or 1.1) or 1 }, on and Enum.EasingStyle.Quint or Enum.EasingStyle.Back)
		tween(pill.Fill, 0.3, { BackgroundTransparency = on and math.min(baseFill + 0.06, 0.97) or baseFill })
		if pill.Rim and pill.Rim:IsA("ImageLabel") then
			tween(pill.Rim, 0.3, { ImageTransparency = on and 0 or (pill.Rim:GetAttribute("LGT") or 0) })
		end
	end
	local function clampSlot(v)
		local first, last = o.Slot(1), o.Slot(o.Count())
		if axis == "X" then
			return Vector2.new(Motion.rubber(v.X, first.X, last.X, 10), first.Y)
		end
		return Vector2.new(first.X, Motion.rubber(v.Y, first.Y, last.Y, 10))
	end

	Motion.drag(o.Hit, {
		allow = function()
			return o.Count() > 0 and not (o.Disabled and o.Disabled())
		end,
		began = function(p)
			held = true
			under = nil
			lens(true)
			local lp = localPos(p)
			local size = pillSize()
			local target = clampSlot(lp - size / 2)
			Motion.spring(pill.Root, target, 30, 0.85, stretch())
			hover(nearest(lp))
		end,
		moved = function(p)
			local lp = localPos(p)
			local size = pillSize()
			Motion.spring(pill.Root, clampSlot(lp - size / 2), 38, 1, stretch())
			hover(nearest(lp))
		end,
		ended = function(p)
			held = false
			local i = nearest(localPos(p))
			local changed = i ~= current
			current = i
			Motion.spring(pill.Root, o.Slot(current), 24, 0.55, stretch())
			lens(false)
			for _, item in ipairs(o.Items and o.Items() or {}) do
				tween(scaleOf(item), 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			under = current
			if o.Paint then
				o.Paint(current, false)
			end
			if changed then
				Sound.play(o.Sound or "tab")
			end
			if o.OnSelect then
				o.OnSelect(current, changed)
			end
		end,
	})

	function sel.set(i, instant)
		current = i
		under = i
		if instant then
			Motion.stop(pill.Root)
			pill.Root.Size = rest
			local s = o.Slot(i)
			pill.Root.Position = UDim2.new(pill.Root.Position.X.Scale, s.X, pill.Root.Position.Y.Scale, s.Y)
		else
			Motion.spring(pill.Root, o.Slot(i), 24, 0.6, stretch())
		end
		if o.Paint then
			o.Paint(i, false)
		end
	end
	function sel.get()
		return current
	end
	-- the pill's resting size changed (layout, orientation)
	function sel.setRest(r)
		rest = r
		Motion.stop(pill.Root)
		pill.Root.Size = r
	end
	return sel
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local Window, Tab, Section = {}, {}, {}
Window.__index, Tab.__index, Section.__index = Window, Tab, Section
Library._classes = { Window = Window, Tab = Tab, Section = Section }

local COLLAPSE_BELOW = 600

local function toVector(v, default)
	if typeof(v) == "Vector2" then
		return v
	elseif typeof(v) == "UDim2" then
		return Vector2.new(v.X.Offset, v.Y.Offset)
	elseif type(v) == "table" and v[1] then
		return Vector2.new(v[1], v[2])
	end
	return default
end

function Glass.surfaceFade(g, visible, time)
	for _, inst in ipairs({ g.Dim, g.Fill, g.Rim, g.Shadow }) do
		if inst then
			local prop = inst:IsA("ImageLabel") and "ImageTransparency" or (inst:IsA("UIStroke") and "Transparency") or "BackgroundTransparency"
			local target = 1
			if visible then
				local map = Theme.binds[inst]
				local tok = map and map[prop]
				if tok ~= nil then
					target = Theme.value(tok)
				else
					target = inst:GetAttribute("LGT") or 0
				end
			end
			tween(inst, time, { [prop] = target }, Enum.EasingStyle.Quad)
		end
	end
end

function Library:CreateWindow(o)
	o = o or {}
	if o.Theme then
		Library:SetTheme(o.Theme)
	end
	if o.Accent then
		Library:SetAccent(o.Accent)
	end
	if o.Sounds == false then
		Library.Settings.Sounds = false
	end
	if o.Blur == false then
		Library.Settings.Blur = false
	end
	if o.Scale then
		Library:SetScale(o.Scale)
	end
	local key = Util.toKey(opt(o, nil, "ToggleKey", "MinimizeKey", "Keybind"))
	if key then
		Library.ToggleKey = key
	end

	local self = setmetatable({
		Tabs = {},
		Title = opt(o, "LiquidGlass", "Title", "Name"),
		Subtitle = opt(o, nil, "Subtitle", "SubTitle", "LoadingSubtitle"),
		Visible = true,
		Minimized = false,
		Collapsed = false,
		MinSize = toVector(o.MinSize, Vector2.new(480, 340)),
		NavMode = ((tostring(opt(o, "", "Navigation", "Layout", "Nav")):lower():find("tab") or (o.TabBar ~= nil and opt(o, nil, "Navigation", "Layout", "Nav") == nil)) and "TabBar") or "Sidebar",
		Resizable = o.Resizable ~= false,
		Opts = o,
	}, Window)
	table.insert(Library.Windows, self)
	if o.Density then
		Library:SetDensity(o.Density)
	end
	if o.Metrics then
		Library:SetMetrics(o.Metrics)
	end
	if o.Font then
		Library:SetFont(o.Font)
	end

	local vs = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local scale = Library.ScaleObject.Scale
	local avail = vs / scale - Vector2.new(40, 80)
	local size = toVector(o.Size, Vector2.new(700, 480))
	size = Vector2.new(math.clamp(size.X, self.MinSize.X, math.max(avail.X, self.MinSize.X)), math.clamp(size.Y, self.MinSize.Y, math.max(avail.Y, self.MinSize.Y)))
	local pos = (vs / scale - size) / 2
	if typeof(o.Position) == "UDim2" or typeof(o.Position) == "Vector2" then
		pos = toVector(o.Position, pos)
	else
		-- cascade instead of opening exactly on top of another window
		for _ = 1, 8 do
			local taken = false
			for _, other in ipairs(Library.Windows) do
				if other ~= self and other.Root and (Motion.target(other.Root) - pos).Magnitude < 24 then
					taken = true
				end
			end
			if not taken then
				break
			end
			pos += Vector2.new(36, 36)
		end
	end

	local root = Glass.new({
		Kind = "Surface",
		Name = "Window",
		Parent = Library.Gui,
		Radius = S.WindowRadius,
		Position = UDim2.fromOffset(math.floor(pos.X), math.floor(pos.Y)),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = nextZ(5),
		BlurStart = 0,
	})
	root.Root.Active = true
	self.Glass, self.Root = root, root.Root
	self.Body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = root.Content })

	-- raise to front on press
	root.Root.InputBegan:Connect(function(input)
		if isPress(input) then
			self:Focus()
		end
	end)

	if self.NavMode == "TabBar" then
		self:_buildMain(o)
		self:_buildTabBar(opt(o, {}, "TabBar", "Bar"))
	else
		self:_buildSidebar(o)
		self:_buildMain(o)
	end
	self:_buildResize()
	self:_layout(true)
	Util.track(root.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout(false)
	end))

	-- open animation; the very first window waits for the intro to dissolve
	root.Scale.Scale = 0.9
	Glass.surfaceFade(root, false, 0)
	if self.Bar then
		self.Bar:setShown(false, 0)
	end
	local function open()
		root.Root.Visible = true
		self.Visible = true
		if self.Bar then
			self.Bar:setShown(self.Bar:wantShown())
		end
		Glass.surfaceFade(root, true, 0.35)
		tween(root.Scale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
		Motion.groupFade(self.Body, 1, 0, 0.35)
		root.BlurRegion:SetTarget(1, 10)
		Sound.play("open")
	end
	local intro = Library._intro
	if intro and not intro.Played then
		root.Root.Visible = false
		self.Visible = false
		self.Opening = true
		intro.play({ Title = opt(o, nil, "IntroTitle") or self.Title, OnReveal = function()
			self.Opening = false
			if not self.Destroyed then
				open()
			end
		end })
	else
		task.defer(open)
	end

	if UserInputService.TouchEnabled then
		self:_buildMobileButton(o)
	end
	return self
end

function Window:Focus()
	if self.Root.ZIndex < zCounter then
		self.Root.ZIndex = nextZ(5)
	end
end

function Window:_buildSidebar(o)
	local sb = Glass.new({
		Kind = "Card",
		Name = "Sidebar",
		Parent = self.Body,
		Radius = S.SidebarRadius,
		Position = UDim2.fromOffset(S.WindowInset, S.WindowInset),
		Size = UDim2.new(0, S.Sidebar, 1, -2 * S.WindowInset),
		ZIndex = 2,
	})
	self.Sidebar = sb
	local c = sb.Content
	c.ClipsDescendants = true
	-- sidebar-local axes; the collapsed sidebar is exactly 2 * IconAxis wide so the
	-- icons never move when it collapses
	local iconX = S.IconAxis
	local textX = S.TextAxis

	-- brand: same height as the page header so both rows share one center line
	local brand = new("Frame", { Name = "Brand", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, S.Header), ZIndex = 6, Parent = c })
	local iconSrc = opt(o, "layers", "Icon", "Logo", "Image")
	local appIcon
	local iconProps = { Parent = brand, Radius = S.BadgeRadius, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(iconX, S.Header / 2), Size = UDim2.fromOffset(S.Badge, S.Badge), Shadow = false, ZIndex = 6 }
	if Assets.isIcon(iconSrc) then
		iconProps.Kind = "Tinted"
		appIcon = Glass.new(iconProps)
		Glass.icon({ Parent = appIcon.Content, Icon = iconSrc, Size = S.BadgeIcon, Color = "OnAccent" })
	else
		iconProps.Kind = "Control"
		appIcon = Glass.new(iconProps)
		local img = new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop, ZIndex = 4, Parent = appIcon.Content }, { Util.corner(S.BadgeRadius) })
		Assets.apply(img, iconSrc)
	end
	self.AppIcon = appIcon
	self.TitleLabel = Glass.text({ Parent = brand, Text = self.Title, Weight = Enum.FontWeight.SemiBold, TextSize = S.Body, Truncate = true, Size = UDim2.new(1, -textX - 8, 0, 19) })
	self.SubtitleLabel = Glass.text({ Parent = brand, Text = self.Subtitle or "", Level = 2, TextSize = S.Footnote, Truncate = true, Size = UDim2.new(1, -textX - 8, 0, 15) })
	self:_placeBrandText()
	local brandHit = hitbox(brand, 5)
	self:_dragHandle(brandHit)

	-- search
	local top = S.Header
	if o.Search ~= false then
		local h = S.Control + 2
		local search = Glass.new({ Kind = "Control", Name = "Search", Parent = c, Radius = h / 2, Position = UDim2.fromOffset(S.WindowInset, top), Size = UDim2.new(1, -2 * S.WindowInset, 0, h), Shadow = false, ZIndex = 6 })
		-- the glass icon sits on the sidebar's icon axis
		Glass.icon({ Parent = search.Content, Icon = "search", Size = 14, Level = 3, Position = UDim2.fromOffset(iconX - S.WindowInset, h / 2) })
		local box = new("TextBox", {
			BackgroundTransparency = 1,
			Text = "",
			PlaceholderText = "Search",
			ClearTextOnFocus = false,
			FontFace = Util.font(Enum.FontWeight.Regular),
			TextSize = S.Callout,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(textX - S.WindowInset, 0),
			Size = UDim2.new(1, -(textX - S.WindowInset) - 12, 1, 0),
			ZIndex = 7,
			Parent = search.Content,
		})
		Theme.bind(box, { TextColor3 = "Text", PlaceholderColor3 = "Text", TextTransparency = function()
			return 0
		end })
		box:GetPropertyChangedSignal("Text"):Connect(function()
			Sound.play("type")
			if self.ActiveTab then
				self.ActiveTab:_filter(box.Text)
			end
		end)
		self.SearchBox, self.Search = box, search
		top += h + S.WindowInset
	end
	self.TabTop = top

	-- tab list
	local list = new("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top - S.Header),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 6,
		Parent = c,
	})
	local items = new("Frame", { Name = "Items", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 8, Parent = list }, {
		Util.list(nil, S.TabGap),
		Util.pad(0, S.WindowInset, S.WindowInset, S.WindowInset),
	})
	self.TabList, self.TabItems = list, items
	Glass.scroller(list, { Priority = function()
		return self.Root.ZIndex
	end })
	local pill = Glass.new({ Kind = "Control", Name = "Selection", Parent = list, Radius = S.TabRadius, Size = UDim2.new(1, -2 * S.WindowInset, 0, S.TabRow), Position = UDim2.fromOffset(S.WindowInset, 0), Shadow = false, ZIndex = 7 })
	pill.Root.Visible = false
	self.TabPill = pill
	-- outside Items so the list layout ignores it; scale sizes follow the canvas
	local tabHit = hitbox(list, 30)
	self.TabSelector = Glass.selector({
		Hit = tabHit,
		Ref = list,
		Pill = pill,
		Axis = "Y",
		Count = function()
			return #self.Tabs
		end,
		Slot = function(i)
			return Vector2.new(S.WindowInset, (i - 1) * (S.TabRow + S.TabGap))
		end,
		Items = function()
			local t = {}
			for i, tab in ipairs(self.Tabs) do
				t[i] = tab.Button
			end
			return t
		end,
		Magnify = 1.04,
		LensScale = 1.05,
		Paint = function(i)
			for j, tab in ipairs(self.Tabs) do
				tab:_paint(j == i)
			end
		end,
		OnSelect = function(i)
			self:SelectTab(i)
		end,
	})

	-- profile footer, as tall as the brand row
	if o.Profile ~= false and o.ShowProfile ~= false then
		local foot = new("Frame", { Name = "Profile", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, S.Header), ZIndex = 6, Parent = c })
		local sep = new("Frame", { BorderSizePixel = 0, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 0, 1), ZIndex = 6, Parent = foot })
		Theme.bind(sep, { BackgroundColor3 = "Separator", BackgroundTransparency = "SeparatorT" })
		local av = new("ImageLabel", {
			BackgroundTransparency = 0.85,
			BackgroundColor3 = WHITE,
			Image = Library:Avatar(LocalPlayer.UserId),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(iconX, S.Header / 2),
			Size = UDim2.fromOffset(S.Badge, S.Badge),
			ZIndex = 6,
			Parent = foot,
		}, { Util.corner(S.Badge / 2) })
		local rimId, slice, sc = rimFor(S.Badge / 2)
		if rimId then
			new("ImageLabel", { BackgroundTransparency = 1, Image = rimId, ScaleType = Enum.ScaleType.Slice, SliceCenter = slice, SliceScale = sc, Size = UDim2.fromScale(1, 1), ImageTransparency = 0.3, ZIndex = 7, Parent = av })
		end
		Glass.text({ Parent = foot, Text = LocalPlayer.DisplayName, Weight = Enum.FontWeight.SemiBold, TextSize = S.Subhead, Truncate = true, Position = UDim2.fromOffset(textX, S.Header / 2 - 16), Size = UDim2.new(1, -textX - 8, 0, 16) })
		Glass.text({ Parent = foot, Text = "@" .. LocalPlayer.Name, Level = 2, TextSize = S.Caption, Truncate = true, Position = UDim2.fromOffset(textX, S.Header / 2 + 1), Size = UDim2.new(1, -textX - 8, 0, 14) })
		self.Profile = foot
	else
		list.Size = UDim2.new(1, 0, 1, -top)
	end
end

function Window:_placeBrandText()
	if not self.TitleLabel then
		return
	end
	local textX = S.TextAxis
	local has = self.Subtitle ~= nil and self.Subtitle ~= ""
	self.TitleLabel.Position = UDim2.fromOffset(textX, has and S.Header / 2 - 18 or (S.Header - 19) / 2)
	self.SubtitleLabel.Position = UDim2.fromOffset(textX, S.Header / 2 + 1)
	self.SubtitleLabel.Visible = has and not self.Collapsed
end

function Window:_buildMain(o)
	-- the main column runs from the sidebar to the window edge; its content keeps
	-- the same gutter on both sides and ends where the sidebar ends
	local main = new("Frame", { Name = "Main", BackgroundTransparency = 1, ZIndex = 3, Parent = self.Body })
	self.Main = main
	local header = new("Frame", { Name = "Header", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, S.WindowInset), Size = UDim2.new(1, 0, 0, S.Header), ZIndex = 4, Parent = main })
	self.Header = header
	local g = S.Gutter
	local btn = S.IconButton
	local titleX = g + 4
	if self.NavMode == "TabBar" then
		-- no sidebar: the app badge leads the header
		local iconSrc = opt(o, "layers", "Icon", "Logo", "Image")
		local badgeProps = { Parent = header, Radius = S.BadgeRadius, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, g + 2, 0.5, 0), Size = UDim2.fromOffset(S.Badge, S.Badge), Shadow = false, ZIndex = 6 }
		if Assets.isIcon(iconSrc) then
			badgeProps.Kind = "Tinted"
			self.AppIcon = Glass.new(badgeProps)
			Glass.icon({ Parent = self.AppIcon.Content, Icon = iconSrc, Size = S.BadgeIcon, Color = "OnAccent" })
		else
			badgeProps.Kind = "Control"
			self.AppIcon = Glass.new(badgeProps)
			local img = new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop, ZIndex = 4, Parent = self.AppIcon.Content }, { Util.corner(S.BadgeRadius) })
			Assets.apply(img, iconSrc)
		end
		titleX = g + 2 + S.Badge + S.IconGap
	end
	self.TitleX = titleX
	self.PageTitle = Glass.text({ Parent = header, Text = "", Weight = Enum.FontWeight.Bold, TextSize = S.LargeTitle, Truncate = true, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, titleX, 0.5, 0), Size = UDim2.new(1, -titleX - g - 2 * btn - 16, 0, S.LargeTitle + 6), ZIndex = 6 })
	local dragHit = hitbox(header, 5)
	self:_dragHandle(dragHit)
	if self.NavMode == "TabBar" and o.Search ~= false then
		local h = S.Control + 2
		local search = Glass.new({ Kind = "Control", Name = "Search", Parent = header, Radius = h / 2, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(g + 2 * btn + 16), 0.5, 0), Size = UDim2.fromOffset(170, h), Shadow = false, ZIndex = 7 })
		Glass.icon({ Parent = search.Content, Icon = "search", Size = 14, Level = 3, Position = UDim2.fromOffset(h / 2 + 2, h / 2) })
		local box = new("TextBox", {
			BackgroundTransparency = 1,
			Text = "",
			PlaceholderText = "Search",
			ClearTextOnFocus = false,
			FontFace = Util.font(Enum.FontWeight.Regular),
			TextSize = S.Callout,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(h + 4, 0),
			Size = UDim2.new(1, -(h + 4) - 12, 1, 0),
			ZIndex = 8,
			Parent = search.Content,
		})
		Theme.bind(box, { TextColor3 = "Text", PlaceholderColor3 = "Text", TextTransparency = function()
			return 0
		end })
		box:GetPropertyChangedSignal("Text"):Connect(function()
			Sound.play("type")
			if self.ActiveTab then
				self.ActiveTab:_filter(box.Text)
			end
		end)
		self.SearchBox, self.Search = box, search
		self:_fitHeaderTitle(true)
	end

	self.CloseButton = Glass.iconButton({ Parent = header, Icon = "close", Size = btn, IconSize = 12, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -g, 0.5, 0), ZIndex = 8, Callback = function()
		self:_closePrompt()
	end })
	self.MinimizeButton = Glass.iconButton({ Parent = header, Icon = "minus", Size = btn, IconSize = 12, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -g - btn - 8, 0.5, 0), ZIndex = 8, Callback = function()
		self:Minimize()
	end })

	-- 4 px of breathing room on each side so pressed controls never clip
	local pages = new("Frame", { Name = "Pages", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(g - 4, S.WindowInset + S.Header), Size = UDim2.new(1, -2 * (g - 4), 1, -(S.WindowInset + S.Header) - S.WindowInset), ZIndex = 4, Parent = main })
	self.Pages = pages
end

function Window:_fitHeaderTitle(withSearch)
	local g, btn = S.Gutter, S.IconButton
	local right = g + 2 * btn + 16 + (withSearch and (170 + 8) or 0)
	self.PageTitle.Size = UDim2.new(1, -self.TitleX - right, 0, S.LargeTitle + 6)
end

-- keeps enough of the window on screen to grab it again
function Window:_clampPos(p)
	local vs = camera.ViewportSize / Library.ScaleObject.Scale
	local w = self.Root.Size.X.Offset
	local keep = 90
	return Vector2.new(math.clamp(p.X, keep - w, vs.X - keep), math.clamp(p.Y, 0, vs.Y - 70))
end

function Window:_dragHandle(hit)
	local startPos
	Motion.drag(hit, {
		began = function()
			startPos = Motion.target(self.Root)
		end,
		moved = function(_, delta, moved)
			if moved then
				self.AtBar = false
				local s = Library.ScaleObject.Scale
				Motion.spring(self.Root, self:_clampPos(startPos + delta / s), 26, 1)
			end
		end,
	})
end

function Window:_buildResize()
	local root = self.Root
	local gripId = Assets.get("grip.png")
	local grip
	if gripId then
		grip = new("ImageLabel", {
			Name = "ResizeGrip",
			BackgroundTransparency = 1,
			Image = gripId,
			ImageTransparency = 1,
			Position = UDim2.new(1, -S.WindowRadius, 1, -S.WindowRadius),
			Size = UDim2.fromOffset(S.WindowRadius, S.WindowRadius),
			ZIndex = 60,
			Parent = self.Glass.Content,
		})
		Theme.bind(grip, { ImageColor3 = "Text" })
	end
	local function zone(name, props)
		local b = hitbox(self.Glass.Content, 61, props)
		b.Name = name
		return b
	end
	local corner = zone("ResizeCorner", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(22, 22) })
	local right = zone("ResizeRight", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 3, 0, S.WindowRadius), Size = UDim2.new(0, 8, 1, -2 * S.WindowRadius) })
	local bottom = zone("ResizeBottom", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, S.WindowRadius, 1, 3), Size = UDim2.new(1, -2 * S.WindowRadius, 0, 8) })
	local resizing = false
	local function showGrip(on)
		if grip then
			tween(grip, 0.25, { ImageTransparency = on and 0.35 or 1 })
		end
	end
	for _, z in ipairs({ corner, right, bottom }) do
		z.MouseEnter:Connect(function()
			if self.Resizable then
				showGrip(true)
			end
		end)
		z.MouseLeave:Connect(function()
			if not resizing then
				showGrip(false)
			end
		end)
		local start
		Motion.drag(z, {
			allow = function()
				return self.Resizable
			end,
			began = function()
				resizing = true
				self.Resizing = true
				start = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
				showGrip(true)
			end,
			moved = function(_, delta)
				local s = Library.ScaleObject.Scale
				local d = delta / s
				local vs = camera.ViewportSize / s
				local w = z == bottom and start.X or math.clamp(start.X + d.X, self.MinSize.X, vs.X)
				local h = z == right and start.Y or math.clamp(start.Y + d.Y, self.MinSize.Y, vs.Y)
				root.Size = UDim2.fromOffset(w, h)
			end,
			ended = function()
				resizing = false
				self.Resizing = false
				showGrip(false)
			end,
		})
	end
	self.ResizeZones = { corner, right, bottom }
end

-- responsive layout: the sidebar collapses to icons on narrow windows
function Window:_layout(instant)
	if self.NavMode == "TabBar" then
		self.Main.Position = UDim2.new()
		self.Main.Size = UDim2.fromScale(1, 1)
		self:_layoutTabBar(instant)
		return
	end
	local w = self.Root.Size.X.Offset
	local collapsed = w < COLLAPSE_BELOW
	local sw = collapsed and S.SidebarMini or S.Sidebar
	if collapsed ~= self.Collapsed or instant then
		self.Collapsed = collapsed
		local t = instant and 0 or 0.35
		local function set(inst, props)
			if t == 0 then
				for k, v in pairs(props) do
					inst[k] = v
				end
			else
				tween(inst, t, props)
			end
		end
		set(self.Sidebar.Root, { Size = UDim2.new(0, sw, 1, -2 * S.WindowInset) })
		set(self.Main, { Position = UDim2.fromOffset(S.WindowInset + sw, 0), Size = UDim2.new(1, -(S.WindowInset + sw), 1, 0) })
		self.TitleLabel.Visible = not collapsed
		self:_placeBrandText()
		if self.Search then
			self.Search.Root.Visible = not collapsed
		end
		for _, tab in ipairs(self.Tabs) do
			tab:_setCompact(collapsed, t)
		end
		if self.Profile then
			for _, ch in ipairs(self.Profile:GetChildren()) do
				if ch:IsA("TextLabel") then
					ch.Visible = not collapsed
				end
			end
		end
		local top = (self.Search and not collapsed) and self.TabTop or S.Header
		set(self.TabList, { Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top - (self.Profile and S.Header or 0)) })
	end
end

function Window:_buildMobileButton(o)
	local b = Glass.new({ Kind = "Surface", Name = "MobileToggle", Parent = Library.Gui, Radius = 24, Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(18, 120), ZIndex = nextZ(200) })
	local src = opt(o, "layers", "Icon", "Logo")
	Glass.icon({ Parent = b.Content, Icon = Assets.isIcon(src) and src or "layers", Size = 22 })
	local hit = hitbox(b.Root, 20)
	local start
	Motion.drag(hit, {
		began = function()
			start = Motion.target(b.Root)
			tween(b.Scale, 0.3, { Scale = 1.1 })
		end,
		moved = function(_, d, moved)
			if moved then
				Motion.spring(b.Root, start + d / Library.ScaleObject.Scale, 30, 1)
			end
		end,
		ended = function(_, moved)
			tween(b.Scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			if not moved then
				Sound.play("click")
				self:Toggle()
			end
		end,
	})
	self.MobileButton = b
end

function Window:SetTitle(t)
	self.Title = t
	if self.TitleLabel then
		self.TitleLabel.Text = t
	end
	if self.Pill then
		self.Pill.Title.Text = t
	end
end

function Window:SetSubtitle(t)
	self.Subtitle = t
	if not self.SubtitleLabel then
		return
	end
	self.SubtitleLabel.Text = t or ""
	self:_placeBrandText()
end

function Window:SetSize(size)
	local v = toVector(size, Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset))
	tween(self.Root, 0.4, { Size = UDim2.fromOffset(math.max(v.X, self.MinSize.X), math.max(v.Y, self.MinSize.Y)) })
end

function Window:Center()
	self.AtBar = false
	local s = Library.ScaleObject.Scale
	local vs = camera.ViewportSize / s
	local size = Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset)
	Motion.spring(self.Root, (vs - size) / 2, 22, 0.8)
end

function Window:SetResizable(on)
	self.Resizable = on
end

-- hide/show with the glass dissolving into the backdrop
function Window:SetVisible(on, silent)
	on = on and true or false
	if on == self.Visible and not self.Minimized then
		return
	end
	if on and self.Minimized then
		self:Restore()
		return
	end
	self.Visible = on
	local root, g = self.Root, self.Glass
	if on then
		root.Visible = true
		self:Focus()
		g.Scale.Scale = 0.94
		tween(g.Scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
		Glass.surfaceFade(g, true, 0.3)
		Motion.groupFade(self.Body, 1, 0, 0.3)
		g.BlurRegion:SetTarget(1, 12)
		if not silent then
			Sound.play("open")
		end
	else
		tween(g.Scale, 0.25, { Scale = 0.94 }, Enum.EasingStyle.Quad)
		Glass.surfaceFade(g, false, 0.22)
		g.BlurRegion:SetTarget(0, 14)
		Motion.groupFade(self.Body, 0, 1, 0.22, function()
			if not self.Visible then
				root.Visible = false
			end
		end)
		if not silent then
			Sound.play("close")
		end
	end
end

function Window:Toggle()
	if self.Minimized then
		self:Restore()
	else
		self:SetVisible(not self.Visible)
	end
end

function Window:IsVisible()
	return self.Visible and not self.Minimized
end

-- collapse into a floating glass pill at the top of the screen
function Window:Minimize()
	if self.Minimized then
		return
	end
	self:SetVisible(false, true)
	self.Minimized = true
	Sound.play("close")
	-- a tab bar that stays on screen brings the window back; no pill needed
	if self.Bar and self.Bar:persists() then
		return
	end
	if not self.Pill then
		-- icon and chevron sit on the centers of the capsule's round ends
		local PH = S.ButtonLarge
		local p = Glass.new({ Kind = "Surface", Name = "MinimizedPill", Parent = Library.Gui, Radius = PH / 2, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(220, PH), ZIndex = nextZ(50), BlurStart = 0 })
		local ic = self.AppIcon and self.Opts and opt(self.Opts, "layers", "Icon", "Logo", "Image")
		Glass.icon({ Parent = p.Content, Icon = Assets.isIcon(ic) and ic or "layers", Size = 16, Position = UDim2.fromOffset(PH / 2, PH / 2) })
		local t = Glass.text({ Parent = p.Content, Text = self.Title, Weight = Enum.FontWeight.SemiBold, TextSize = S.Callout, Truncate = true, Position = UDim2.fromOffset(PH / 2 + 16, 0), Size = UDim2.new(1, -(PH + 32), 1, 0) })
		Glass.icon({ Parent = p.Content, Icon = "chevron-down", Size = S.Chevron, Level = 2, Position = UDim2.new(1, -PH / 2, 0, PH / 2) })
		p.Title = t
		-- tap restores, drag moves it out of the way of the game's own UI
		local glow = Glass.glow(p)
		local hit = hitbox(p.Root, 20)
		local start
		hit.MouseEnter:Connect(function()
			glow.follow()
			glow.set(0.5)
		end)
		hit.MouseMoved:Connect(glow.follow)
		hit.MouseLeave:Connect(function()
			glow.set(0, 0.4)
		end)
		Motion.drag(hit, {
			began = function()
				start = Motion.target(p.Root)
				tween(p.Scale, 0.3, { Scale = 1.06 })
			end,
			moved = function(_, d, moved)
				if moved then
					local vs2 = camera.ViewportSize / Library.ScaleObject.Scale
					local target = start + d / Library.ScaleObject.Scale
					Motion.spring(p.Root, Vector2.new(math.clamp(target.X, 110, vs2.X - 110), math.clamp(target.Y, 4, vs2.Y - 46)), 30, 1)
				end
			end,
			ended = function(_, moved)
				tween(p.Scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
				if moved then
					self.PillHome = Motion.target(p.Root)
				else
					Sound.play("click")
					self:Restore()
				end
			end,
		})
		self.Pill = p
	end
	local p = self.Pill
	local vs = camera.ViewportSize / Library.ScaleObject.Scale
	local home = self.PillHome or Vector2.new(vs.X / 2, 14)
	home = Vector2.new(math.clamp(home.X, 110, vs.X - 110), math.clamp(home.Y, 4, vs.Y - 46))
	p.Root.Visible = true
	p.Root.Position = UDim2.fromOffset(home.X, home.Y - 70)
	Motion.spring(p.Root, home, 20, 0.62)
	Glass.surfaceFade(p, true, 0.3)
	p.BlurRegion:SetTarget(1, 10)
end

function Window:Restore()
	if not self.Minimized then
		return
	end
	self.Minimized = false
	local p = self.Pill
	if p then
		local at = Motion.target(p.Root)
		Motion.spring(p.Root, Vector2.new(at.X, at.Y - 70), 22, 1)
		Glass.surfaceFade(p, false, 0.25)
		p.BlurRegion:SetTarget(0, 12)
		task.delay(0.35, function()
			if not self.Minimized then
				p.Root.Visible = false
			end
		end)
	end
	self.Visible = false
	self:SetVisible(true)
end

function Window:_closePrompt()
	if self.Opts.ConfirmClose == false then
		self:Destroy()
		return
	end
	self:Dialog({
		Title = "Close " .. self.Title .. "?",
		Content = "Hide keeps everything running — press " .. Util.keyName(Library.ToggleKey) .. " to bring it back. Unload removes the UI completely.",
		Icon = "power",
		Buttons = {
			{ Title = "Hide", Style = "Primary", Callback = function()
				self:SetVisible(false)
			end },
			{ Title = "Unload", Style = "Destructive", Callback = function()
				Library:Destroy()
			end },
			{ Title = "Cancel", Style = "Cancel" },
		},
	})
end

function Window:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self:SetVisible(false)
	task.delay(0.3, function()
		self.Root:Destroy()
		if self.Pill then
			self.Pill.Root:Destroy()
		end
		if self.MobileButton then
			self.MobileButton.Root:Destroy()
		end
	end)
	local i = table.find(Library.Windows, self)
	if i then
		table.remove(Library.Windows, i)
	end
	Util.fire(self.Opts.OnDestroy)
end

-- Glass can't blur other LiquidGlass UI, so surfaces that sit on top of another
-- window turn denser (and clear again once they no longer overlap)
local stackCheck = 0
Util.track(RunService.Heartbeat:Connect(function(dt)
	stackCheck += dt
	if stackCheck < 0.15 then
		return
	end
	stackCheck = 0
	local wins = {}
	for _, w in ipairs(Library.Windows) do
		if w.Root and w.Root.Visible then
			table.insert(wins, w)
		end
	end
	local surfaces = {}
	for _, w in ipairs(wins) do
		table.insert(surfaces, { g = w.Glass, z = w.Root.ZIndex, self = w.Root })
		if w.Bar and w.Bar.Floating and w.Bar.Glass then
			table.insert(surfaces, { g = w.Bar.Glass, z = w.Bar.Root.ZIndex, self = w.Bar.Root })
		end
	end
	local function overlap(a, b)
		local ap, as = a.AbsolutePosition, a.AbsoluteSize
		local bp, bs = b.AbsolutePosition, b.AbsoluteSize
		return ap.X < bp.X + bs.X - 6 and bp.X < ap.X + as.X - 6 and ap.Y < bp.Y + bs.Y - 6 and bp.Y < ap.Y + as.Y - 6
	end
	for _, sf in ipairs(surfaces) do
		local covering = false
		for _, w in ipairs(wins) do
			if w.Root ~= sf.self and w.Root.ZIndex < sf.z and overlap(sf.self, w.Root) then
				covering = true
				break
			end
		end
		local g = sf.g
		if g.Dim and g.Stacked ~= covering then
			g.Stacked = covering
			local map = Theme.binds[g.Dim]
			if map then
				map.BackgroundTransparency = covering and "StackDimT" or "DimT"
			end
			tween(g.Dim, 0.3, { BackgroundTransparency = Theme.value(covering and "StackDimT" or "DimT") })
		end
	end
end))

-- toggle key for every window
Util.track(UserInputService.InputBegan:Connect(function(input)
	if typing() or Library.Unloaded then
		return
	end
	if Library._intro and Library._intro.Active then
		return
	end
	if Library.ToggleKey and input.KeyCode == Library.ToggleKey and not Library._capturingKey then
		for _, w in ipairs(Library.Windows) do
			w:Toggle()
		end
	end
end))

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
function Window:AddTab(o, icon)
	if type(o) == "string" then
		o = { Title = o, Icon = icon }
	end
	o = o or {}
	local tab = setmetatable({
		Window = self,
		Title = opt(o, "Tab", "Title", "Name"),
		Icon = opt(o, nil, "Icon", "Image"),
		Sections = {},
		Index = #self.Tabs + 1,
		Elements = {},
	}, Tab)
	table.insert(self.Tabs, tab)

	if not self.Bar then
		-- sidebar button
		local b = new("Frame", { Name = "Tab_" .. tab.Title, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, S.TabRow), LayoutOrder = tab.Index, ZIndex = 9, Parent = self.TabItems })
		tab.Button = b
		tab.IconImage = Glass.icon({ Parent = b, Icon = tab.Icon or "circle", Size = 18, Position = UDim2.fromOffset(S.IconAxis - S.WindowInset, S.TabRow / 2) })
		tab.Label = Glass.text({ Parent = b, Text = tab.Title, Weight = Enum.FontWeight.Medium, TextSize = S.Callout, Truncate = true, Position = UDim2.fromOffset(S.TextAxis - S.WindowInset, 0), Size = UDim2.new(1, -(S.TextAxis - S.WindowInset) - 8, 1, 0), ZIndex = 9 })
		tab:_setCompact(self.Collapsed, 0)
	end

	-- page
	local page = new("ScrollingFrame", {
		Name = "Page_" .. tab.Title,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		ZIndex = 4,
		Parent = self.Pages,
	}, {
		Util.list(nil, S.SectionGap),
		Util.pad(4, 4, S.Gutter, 4),
	})
	tab.Page = page
	tab.Scroller = Glass.scroller(page, { IndicatorParent = self.Pages, Priority = function()
		return self.Root.ZIndex
	end })

	if self.Bar then
		self.Bar:addItem(tab)
	else
		self.TabPill.Root.Visible = true
	end
	if not self.ActiveTab then
		self:SelectTab(tab, true)
	end
	return tab
end
Window.CreateTab = Window.AddTab

function Window:SelectTab(t, instant)
	local tab = type(t) == "number" and self.Tabs[t] or t
	if not tab or tab == self.ActiveTab then
		return
	end
	local old = self.ActiveTab
	self.ActiveTab = tab
	if old then
		old.Page.Visible = false
		if self.SearchBox and self.SearchBox.Text ~= "" then
			old:_filter("")
		end
	end
	tab.Page.Visible = true
	self.PageTitle.Text = tab.Title
	self.TabSelector.set(tab.Index, instant)
	if self.SearchBox and self.SearchBox.Text ~= "" then
		tab:_filter(self.SearchBox.Text)
	end
	if not instant then
		tab.Page.Position = UDim2.fromOffset(0, 14)
		tween(tab.Page, 0.45, { Position = UDim2.new() })
		Motion.groupFade(tab.Page, 1, 0, 0.28)
	end
	Util.fire(self.Opts.OnTabChanged, tab)
end

function Tab:_paint(selected)
	self.Selected = selected
	Theme.bind(self.IconImage, { ImageColor3 = selected and "Accent" or "Text", ImageTransparency = function(t)
		return selected and 0 or t.Text2T
	end })
	if self.Window.Bar then
		Theme.bind(self.Label, { TextColor3 = selected and "Accent" or "Text", TextTransparency = function(t)
			return selected and 0 or t.Text2T
		end })
		return
	end
	Theme.bind(self.Label, { TextTransparency = function()
		return 0
	end })
	self.Label.FontFace = Util.font(selected and Enum.FontWeight.SemiBold or Enum.FontWeight.Medium)
end

function Tab:_setCompact(compact)
	-- the icon stays on the sidebar's icon axis in both states
	if self.Window.Bar then
		return
	end
	self.Label.Visible = not compact
end

function Tab:Select()
	self.Window:SelectTab(self)
end

function Tab:SetTitle(t)
	self.Title = t
	self.Label.Text = t
	if self.Window.ActiveTab == self then
		self.Window.PageTitle.Text = t
	end
end

function Tab:SetIcon(src)
	self.Icon = src
	Assets.apply(self.IconImage, src)
end

function Tab:_filter(query)
	query = (query or ""):lower()
	for _, section in ipairs(self.Sections) do
		local any = false
		for _, el in ipairs(section.Elements) do
			local hay = ((el.TitleText or "") .. " " .. (el.DescText or "")):lower()
			local match = query == "" or hay:find(query, 1, true) ~= nil
			el._filtered = not match
			el:_updateVisible()
			any = any or (match and not el._hidden)
		end
		section._filtered = query ~= "" and not any
		section:_refresh()
	end
	self.Window.PageTitle.Text = query == "" and self.Title or ("Results for “" .. query .. "”")
end

---------------------------------------------------------------------------
-- Sections and rows
---------------------------------------------------------------------------
function Tab:AddSection(o)
	if type(o) ~= "table" then
		o = { Title = o }
	end
	local section = setmetatable({
		Tab = self,
		Title = opt(o, nil, "Title", "Name", "Text"),
		Elements = {},
		Order = 0,
	}, Section)
	local frame = new("Frame", { Name = "Section", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = #self.Sections + 1, ZIndex = 4, Parent = self.Page }, {
		Util.list(nil, S.HeaderGap),
	})
	section.Frame = frame
	section.Header = Glass.text({ Parent = frame, Text = section.Title and section.Title:upper() or "", Weight = Enum.FontWeight.SemiBold, TextSize = S.Footnote, Level = 2, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 0 })
	new("UIPadding", { PaddingLeft = UDim.new(0, S.RowInset), PaddingRight = UDim.new(0, S.RowInset), Parent = section.Header })
	section.Header.Visible = section.Title ~= nil
	section.Card = Glass.new({ Kind = "Card", Name = "Card", Parent = frame, Radius = S.CardRadius, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, ZIndex = 4 })
	section.Rows = section.Card.Content
	Util.list(nil, 0).Parent = section.Rows
	table.insert(self.Sections, section)
	self.CurrentSection = section
	return section
end
Tab.CreateSection = Tab.AddSection

function Tab:_section()
	return self.CurrentSection or self:AddSection({})
end

function Section:SetTitle(t)
	self.Title = t
	self.Header.Text = t and t:upper() or ""
	self.Header.Visible = t ~= nil
end
Section.Set = Section.SetTitle

function Section:SetVisible(on)
	self._hidden = not on
	self:_refresh()
end

function Section:Destroy()
	self.Frame:Destroy()
	local i = table.find(self.Tab.Sections, self)
	if i then
		table.remove(self.Tab.Sections, i)
	end
end

function Section:_refresh()
	local last
	for _, el in ipairs(self.Elements) do
		if el.Row and el.Row.Frame.Visible then
			last = el
		end
	end
	for _, el in ipairs(self.Elements) do
		if el.Row and el.Row.Separator then
			el.Row.Separator.Visible = el ~= last and not el.NoSeparator
		end
	end
	self.Frame.Visible = not self._hidden and not self._filtered and last ~= nil
end

function Section:_order()
	self.Order += 1
	return self.Order
end

-- a list row: icon/title/description on the left, a control on the right.
-- The text column and an invisible RowMin strut sit side by side in a centered
-- horizontal list, so short rows are exactly RowMin tall with their text centered.
-- o: Title, Description, Icon, IconColor (draws a colored badge), Right (width),
--    MinHeight, PadY, Inset (left/right override for full-bleed content)
function Section:_row(o)
	local row = { Section = self }
	local minH = o.MinHeight or S.RowMin
	local padY = o.PadY or S.RowPadY
	local frame = new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = self:_order(), ZIndex = 5, Parent = self.Rows })
	row.Frame = frame
	row.Highlight = new("Frame", { Name = "Highlight", BorderSizePixel = 0, BackgroundTransparency = 1, Position = UDim2.fromOffset(S.HighlightInset, 2), Size = UDim2.new(1, -2 * S.HighlightInset, 1, -4), ZIndex = 5, Parent = frame }, { Util.corner(S.HighlightRadius) })
	Theme.bind(row.Highlight, { BackgroundColor3 = "Highlight" })

	local left = S.RowInset
	if o.Icon then
		if o.IconColor then
			local badge = new("Frame", { Name = "Badge", BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, S.RowInset, 0.5, 0), Size = UDim2.fromOffset(S.Badge, S.Badge), ZIndex = 6, Parent = frame }, { Util.corner(S.BadgeRadius) })
			if typeof(o.IconColor) == "Color3" then
				badge.BackgroundColor3 = o.IconColor
			else
				Theme.bind(badge, { BackgroundColor3 = o.IconColor })
			end
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(205, 205, 205)), Parent = badge })
			Glass.icon({ Parent = badge, Icon = o.Icon, Size = S.BadgeIcon, Color = Color3.new(1, 1, 1), ZIndex = 7 })
			row.Badge = badge
		else
			row.IconImage = Glass.icon({ Parent = frame, Icon = o.Icon, Size = S.RowIcon, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, S.RowInset + S.Badge / 2, 0.5, 0), Level = 1, ZIndex = 6 })
		end
		left = S.TextX
	end
	left = o.Inset or left
	local rightInset = o.Inset or S.RowInset
	row.TextX = left
	local rightW = o.Right or 0
	local function lineWidth(w)
		return UDim2.new(1, -(left + rightInset + (w > 0 and w + S.IconGap or 0)), 0, 0)
	end
	row.Line = new("Frame", {
		Name = "Line",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(left, 0),
		Size = lineWidth(rightW),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 6,
		Parent = frame,
	}, { Util.list(Enum.FillDirection.Horizontal, 0, { VerticalAlignment = Enum.VerticalAlignment.Center }) })
	row.Strut = new("Frame", { Name = "Strut", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, minH), LayoutOrder = 0, Parent = row.Line })
	row.Body = new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = row.Line,
	}, { Util.pad(padY, 0, padY, 0), Util.list(nil, S.RowGap) })
	row.Title = Glass.text({ Parent = row.Body, Text = o.Title or "", Weight = Enum.FontWeight.Medium, TextSize = S.Body, Wrap = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 1, ZIndex = 6 })
	row.Title.Visible = (o.Title or "") ~= ""
	row.Desc = Glass.text({ Parent = row.Body, Text = o.Description or "", Level = 2, TextSize = S.Subhead, Wrap = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, ZIndex = 6 })
	row.Desc.Visible = (o.Description or "") ~= ""
	row.Right = new("Frame", { Name = "Right", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -rightInset, 0.5, 0), Size = UDim2.fromOffset(rightW, S.Control), ZIndex = 8, Parent = frame })
	row.Separator = new("Frame", { Name = "Separator", BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, left, 1, 0), Size = UDim2.new(1, -left, 0, 1), ZIndex = 5, Parent = frame })
	Theme.bind(row.Separator, { BackgroundColor3 = "Separator", BackgroundTransparency = "SeparatorT" })

	function row.SetRight(w)
		rightW = w
		row.Right.Size = UDim2.fromOffset(w, row.Right.Size.Y.Offset)
		row.Line.Size = lineWidth(w)
	end

	-- rows with a control stacked under the text (sliders, fields...) keep their
	-- icon level with the title block instead of the middle of the whole row
	function row.TopIcon()
		local icon = row.Badge or row.IconImage
		if not icon then
			return
		end
		local function place()
			local sc = Library.ScaleObject.Scale
			local h = row.Title.Visible and row.Title.AbsoluteSize.Y / sc or 0
			if row.Desc.Visible then
				h += S.RowGap + row.Desc.AbsoluteSize.Y / sc
			end
			local y = padY + math.max(h, S.Badge) / 2
			icon.Position = UDim2.new(icon.Position.X.Scale, icon.Position.X.Offset, 0, y)
		end
		row.Title:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		row.Desc:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		row.Desc:GetPropertyChangedSignal("Visible"):Connect(place)
		place()
	end

	-- whole-row press feedback; returns the hit button
	function row.Interactive(onClick, ro)
		ro = ro or {}
		local hit = hitbox(frame, 7)
		local hovered, pressed = false, false
		local function paint()
			local t = Theme.current
			local target = pressed and t.PressT or hovered and t.HighlightT or 1
			tween(row.Highlight, pressed and 0.08 or 0.25, { BackgroundTransparency = target })
		end
		hit.MouseEnter:Connect(function()
			if row.Locked then
				return
			end
			hovered = true
			paint()
			if ro.HoverSound ~= false then
				Sound.play("hover")
			end
			if ro.OnHover then
				ro.OnHover(true)
			end
		end)
		hit.MouseLeave:Connect(function()
			hovered = false
			paint()
			if ro.OnHover then
				ro.OnHover(false)
			end
		end)
		hit.InputBegan:Connect(function(input)
			if isPress(input) and not row.Locked then
				pressed = true
				paint()
			end
		end)
		Util.track(UserInputService.InputEnded:Connect(function(input)
			if pressed and isPress(input) then
				pressed = false
				paint()
			end
		end))
		hit.Activated:Connect(function()
			if not row.Locked and onClick then
				onClick()
			end
		end)
		row.Hit = hit
		return hit
	end

	-- dims the row and blocks its input
	function row.SetLocked(on)
		if (row.Locked or false) == on then
			return
		end
		row.Locked = on
		if on then
			-- the group sizes itself from the row content, so a row locked before it was
			-- ever laid out keeps its height
			local group = new("CanvasGroup", { Name = "Locked", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, GroupTransparency = 0.55, ZIndex = 6, Parent = frame })
			new("Frame", { Name = "LockStrut", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, minH), Parent = group })
			for _, ch in ipairs(frame:GetChildren()) do
				if ch ~= group and ch:IsA("GuiObject") and ch ~= row.Highlight then
					ch.Parent = group
				end
			end
			hitbox(group, 90).Name = "Blocker"
			row.LockGroup = group
		else
			local group = row.LockGroup
			for _, ch in ipairs(group:GetChildren()) do
				if ch.Name ~= "Blocker" and ch.Name ~= "LockStrut" and ch:IsA("GuiObject") then
					ch.Parent = frame
				end
			end
			group:Destroy()
		end
	end
	return row
end
