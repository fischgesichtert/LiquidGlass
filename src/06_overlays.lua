---------------------------------------------------------------------------
-- Popovers: one at a time, anchored to a GuiObject, closed by an outside click,
-- Escape, or the anchor moving away. They grow out of their anchor corner.
---------------------------------------------------------------------------
local function anchorRect(anchor)
	local s = Library.ScaleObject.Scale
	return screenPos(anchor) / s, anchor.AbsoluteSize / s
end

function Overlay.popover(o)
	if Overlay.active then
		Overlay.active.Close()
	end
	local s = Library.ScaleObject.Scale
	local vs = camera.ViewportSize / s
	local width, height = o.Width or 240, o.Height or 200
	local aPos, aSize = anchorRect(o.Anchor)
	local below = aPos.Y + aSize.Y + 6 + height < vs.Y - 10
	local x = o.Align == "Left" and aPos.X + 8 or (o.Align == "Center" and aPos.X + aSize.X / 2 or aPos.X + aSize.X - 8)
	local ax = o.Align == "Left" and 0 or (o.Align == "Center" and 0.5 or 1)
	local y = below and (aPos.Y + aSize.Y + 4) or (aPos.Y - 4)
	x = math.clamp(x, width * ax + 8, vs.X - width * (1 - ax) - 8)

	local catcher = new("TextButton", { Name = "PopoverCatcher", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = nextZ(), Parent = Library.Gui })
	local g = Glass.new({
		Kind = "Surface",
		Dense = true,
		Name = o.Name or "Popover",
		Parent = Library.Gui,
		Radius = o.Radius or S.PopoverRadius,
		AnchorPoint = Vector2.new(ax, below and 0 or 1),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, height),
		ZIndex = nextZ(5),
		BlurStart = 0,
	})
	g.Root.Active = true
	local pop = { Glass = g, Root = g.Root, Content = g.Content, Closed = false }
	g.Scale.Scale = 0.82
	Glass.surfaceFade(g, false, 0)
	Glass.surfaceFade(g, true, 0.2)
	tween(g.Scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	g.BlurRegion:SetTarget(1, 16)
	local startPos = screenPos(o.Anchor)
	local follow
	function pop.Close()
		if pop.Closed then
			return
		end
		pop.Closed = true
		if Overlay.active == pop then
			Overlay.active = nil
		end
		catcher:Destroy()
		if follow then
			follow:Disconnect()
		end
		tween(g.Scale, 0.2, { Scale = 0.9 }, Enum.EasingStyle.Quad)
		Glass.surfaceFade(g, false, 0.18)
		g.BlurRegion:SetTarget(0, 18)
		Motion.groupFade(g.Content.Parent and g.Content or g.Root, 0, 1, 0.18)
		task.delay(0.25, function()
			g.Root:Destroy()
		end)
		Util.fire(o.OnClose)
	end
	catcher.Activated:Connect(pop.Close)
	catcher.MouseButton2Click:Connect(pop.Close)
	follow = RunService.RenderStepped:Connect(function()
		if not o.Anchor.Parent or (screenPos(o.Anchor) - startPos).Magnitude > 3 then
			pop.Close()
		end
	end)
	Overlay.active = pop
	return pop
end

-- Escape always reaches Roblox's own menu too (core bindings can't be sunk),
-- so overlays close on Escape and whenever that menu opens.
local function dismissOverlays()
	if Overlay.active then
		Overlay.active.Close()
	elseif Overlay.dialog then
		Overlay.dialog.Cancel()
	end
end
Util.track(UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Escape then
		dismissOverlays()
	end
end))
Util.track(GuiService.MenuOpened:Connect(function()
	if Overlay.active then
		Overlay.active.Close()
	end
end))

---------------------------------------------------------------------------
-- Menu (dropdowns, context menus)
---------------------------------------------------------------------------

-- o: Anchor, Options, Selected (set), Multi, Search, Label(v), OnPick(v) -> keepOpen, Width, OnClose
function Overlay.menu(o)
	local options = o.Options or {}
	local search = o.Search
	local visibleRows = math.clamp(#options, 1, 7)
	local inset = S.MenuInset
	local fieldH = S.Control + 2
	local top = search and (8 + fieldH + 4) or inset
	local height = top + visibleRows * S.MenuItem + inset
	local pop = Overlay.popover({ Anchor = o.Anchor, Width = o.Width or 220, Height = height, Align = o.Align or "Right", OnClose = o.OnClose, Name = "Menu" })
	local c = pop.Content
	local box
	if search then
		local f = Glass.field(c, { Placeholder = "Search", Height = fieldH, Size = UDim2.new(1, -16, 0, fieldH), Position = UDim2.fromOffset(8, 8) })
		box = f.Box
	end
	local list = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top - inset),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 8,
		Parent = c,
	}, { Util.list(nil, 0), Util.pad(0, inset, 0, inset) })
	Glass.scroller(list, { IndicatorParent = c, Priority = function()
		return pop.Root.ZIndex
	end })
	local selected = o.Selected or {}
	local rows = {}
	local function paintRow(r)
		r.Check.Visible = selected[r.Value] and true or false
	end
	for i, v in ipairs(options) do
		local b = new("TextButton", { Name = "Item", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, S.MenuItem), LayoutOrder = i, ZIndex = 9, Parent = list })
		local hl = new("Frame", { BorderSizePixel = 0, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = b }, { Util.corner(S.PopoverRadius - inset) })
		Theme.bind(hl, { BackgroundColor3 = "Highlight" })
		local check = Glass.icon({ Parent = b, Icon = "check", Size = 14, Color = "Accent", Position = UDim2.fromOffset(20, S.MenuItem / 2), ZIndex = 10 })
		local text = Glass.text({ Parent = b, Text = (o.Label or tostring)(v), TextSize = S.Body, Truncate = true, Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -38 - 14, 1, 0), ZIndex = 10 })
		local r = { Button = b, Check = check, Value = v, Text = text, Highlight = hl }
		rows[i] = r
		paintRow(r)
		b.MouseEnter:Connect(function()
			tween(hl, 0.15, { BackgroundTransparency = Theme.current.HighlightT - 0.02 })
			Sound.play("hover")
		end)
		b.MouseLeave:Connect(function()
			tween(hl, 0.25, { BackgroundTransparency = 1 })
		end)
		b.Activated:Connect(function()
			Sound.play("click")
			local keep = o.OnPick and o.OnPick(v)
			for _, rr in ipairs(rows) do
				paintRow(rr)
			end
			if not keep then
				pop.Close()
			end
		end)
	end
	if #options == 0 then
		Glass.text({ Parent = list, Text = "No options", Level = 3, TextSize = S.Body, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, S.MenuItem), ZIndex = 10 })
	end
	if box then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local q = box.Text:lower()
			for _, r in ipairs(rows) do
				r.Button.Visible = q == "" or r.Text.Text:lower():find(q, 1, true) ~= nil
			end
		end)
		task.defer(function()
			if not pop.Closed then
				box:CaptureFocus()
			end
		end)
	end
	function pop.SetSelected(set)
		selected = set
		for _, r in ipairs(rows) do
			paintRow(r)
		end
	end
	return pop
end

-- context menu at the pointer: items = { {Title, Icon, Callback, Destructive}, ... }
function Library:Menu(anchor, items)
	local labels, map = {}, {}
	for i, it in ipairs(items) do
		labels[i] = it.Title or it.Name
		map[labels[i]] = it
	end
	return Overlay.menu({
		Anchor = anchor,
		Options = labels,
		Width = 220,
		OnPick = function(v)
			Util.fire(map[v] and map[v].Callback)
			return false
		end,
	})
end

---------------------------------------------------------------------------
-- Color picker popover
---------------------------------------------------------------------------
local PRESETS = {
	Color3.fromRGB(255, 59, 48), Color3.fromRGB(255, 149, 0), Color3.fromRGB(255, 204, 0), Color3.fromRGB(52, 199, 89),
	Color3.fromRGB(0, 199, 190), Color3.fromRGB(10, 132, 255), Color3.fromRGB(94, 92, 230), Color3.fromRGB(255, 45, 85),
}

function Overlay.colorPicker(o)
	local hasAlpha = o.Transparency ~= nil
	local h, sat, val = (o.Color or WHITE):ToHSV()
	local alpha = o.Transparency or 0
	local M, R = 14, 24
	local IR = R - M
	local BAR, PITCH = 16, 30
	local height = M + 150 + M + PITCH * (hasAlpha and 2 or 1) + S.Control + 12 + 26 + M
	local pop = Overlay.popover({ Anchor = o.Anchor, Width = 270, Height = height, Align = "Right", OnClose = o.OnClose, Name = "ColorPicker", Radius = R })
	local c = pop.Content
	local y = M

	local sv = new("Frame", { Name = "SV", BorderSizePixel = 0, Position = UDim2.fromOffset(M, y), Size = UDim2.new(1, -2 * M, 0, 150), ZIndex = 8, Parent = c }, { Util.corner(IR) })
	local white = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = sv }, { Util.corner(IR) })
	new("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
	local black = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = BLACK, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = sv }, { Util.corner(IR) })
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
	local rimId, slice, sc = rimFor(IR)
	if rimId then
		new("ImageLabel", { BackgroundTransparency = 1, Image = rimId, ScaleType = Enum.ScaleType.Slice, SliceCenter = slice, SliceScale = sc, ImageTransparency = 0.4, Size = UDim2.fromScale(1, 1), ZIndex = 11, Parent = sv })
	end
	local cursor = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20), ZIndex = 12, Parent = sv }, { Util.corner(10) })
	new("UIStroke", { Color = WHITE, Thickness = 2.5, Parent = cursor })
	local cursorDot = new("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), ZIndex = 12, Parent = cursor }, { Util.corner(7) })
	y += 150 + M

	local function bar(name)
		local b = new("Frame", { Name = name, BorderSizePixel = 0, BackgroundColor3 = WHITE, Position = UDim2.fromOffset(M, y), Size = UDim2.new(1, -2 * M, 0, BAR), ZIndex = 8, Parent = c }, { Util.corner(BAR / 2) })
		local knob = Glass.new({ Kind = "Solid", Parent = b, Radius = 11, Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), ZIndex = 10 })
		y += PITCH
		return b, knob
	end
	local hue, hueKnob = bar("Hue")
	local keys = {}
	for i = 0, 6 do
		keys[#keys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1))
	end
	new("UIGradient", { Color = ColorSequence.new(keys), Parent = hue })
	local alphaBar, alphaKnob, alphaGrad
	if hasAlpha then
		alphaBar, alphaKnob = bar("Alpha")
		local checker = Assets.get("checker.png")
		if checker then
			new("ImageLabel", { BackgroundTransparency = 1, Image = checker, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(12, 12), Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = alphaBar }, { Util.corner(8) })
		end
		local overlayBar = new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = alphaBar }, { Util.corner(8) })
		alphaGrad = new("UIGradient", { Transparency = NumberSequence.new(1, 0), Parent = overlayBar })
		alphaBar.BackgroundTransparency = 1
		alphaGrad.Parent = overlayBar
		alphaBar:SetAttribute("Overlay", true)
		pop.AlphaOverlay = overlayBar
	end
	y -= PITCH - BAR - M

	-- hex field and preview share one row, then the presets
	local half = (270 - 2 * M - 10) / 2
	local field = Glass.field(c, { Placeholder = "#RRGGBB", Size = UDim2.fromOffset(half, S.Control), Position = UDim2.fromOffset(M, y), Font = MONO, TextSize = S.Subhead })
	local preview = new("Frame", { BorderSizePixel = 0, Position = UDim2.fromOffset(M + half + 10, y), Size = UDim2.fromOffset(half, S.Control), ZIndex = 8, Parent = c }, { Util.corner(S.Control / 2) })
	if rimId then
		local r2, s2, sc2 = rimFor(S.Control / 2)
		new("ImageLabel", { BackgroundTransparency = 1, Image = r2, ScaleType = Enum.ScaleType.Slice, SliceCenter = s2, SliceScale = sc2, ImageTransparency = 0.3, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = preview })
	end
	y += S.Control + 12
	local presetRow = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(M, y), Size = UDim2.new(1, -2 * M, 0, 26), ZIndex = 8, Parent = c }, {
		Util.list(Enum.FillDirection.Horizontal, 0, { HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween }),
	})

	local function color()
		return Color3.fromHSV(h, sat, val)
	end
	local function render(fromField)
		local col = color()
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		cursor.Position = UDim2.fromScale(sat, 1 - val)
		cursorDot.BackgroundColor3 = col
		hueKnob.Root.Position = UDim2.fromScale(h, 0.5)
		hueKnob.SetTint(Color3.fromHSV(h, 1, 1), 0)
		preview.BackgroundColor3 = col
		preview.BackgroundTransparency = alpha
		if hasAlpha then
			pop.AlphaOverlay.BackgroundColor3 = col
			alphaKnob.Root.Position = UDim2.fromScale(1 - alpha, 0.5)
		end
		if not fromField and not field.Box:IsFocused() then
			field.Box.Text = Util.toHex(col)
		end
	end
	local function changed(fromField)
		render(fromField)
		Util.fire(o.OnChange, color(), hasAlpha and alpha or nil)
	end
	for _, pc in ipairs(PRESETS) do
		local dot = new("TextButton", { BorderSizePixel = 0, BackgroundColor3 = pc, Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(26, 26), ZIndex = 9, Parent = presetRow }, { Util.corner(13) })
		if rimId then
			local r3, s3, sc3 = rimFor(13)
			new("ImageLabel", { BackgroundTransparency = 1, Image = r3, ScaleType = Enum.ScaleType.Slice, SliceCenter = s3, SliceScale = sc3, ImageTransparency = 0.25, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = dot })
		end
		dot.Activated:Connect(function()
			h, sat, val = pc:ToHSV()
			Sound.play("click")
			changed()
		end)
	end

	local function dragArea(frame, onMove)
		local hit = hitbox(frame, 30, { Size = UDim2.new(1, 12, 1, 12), Position = UDim2.fromOffset(-6, -6) })
		Motion.drag(hit, {
			began = function(p)
				onMove(p)
			end,
			moved = function(p)
				onMove(p)
			end,
		})
	end
	local function rel(frame, p)
		local pos, size = screenPos(frame), frame.AbsoluteSize
		return Vector2.new(math.clamp((p.X - pos.X) / size.X, 0, 1), math.clamp((p.Y - pos.Y) / size.Y, 0, 1))
	end
	dragArea(sv, function(p)
		local r = rel(sv, p)
		sat, val = r.X, 1 - r.Y
		changed()
	end)
	dragArea(hue, function(p)
		h = math.min(rel(hue, p).X, 0.9999)
		Sound.play("tick")
		changed()
	end)
	if hasAlpha then
		dragArea(alphaBar, function(p)
			alpha = 1 - rel(alphaBar, p).X
			changed()
		end)
	end
	field.Box.FocusLost:Connect(function()
		local col = Util.fromHex(field.Box.Text)
		if col then
			h, sat, val = col:ToHSV()
			changed(true)
		end
		render()
	end)
	render()
	return pop
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
local tooltipTargets = setmetatable({}, { __mode = "k" })
local tooltip, tipTarget, tipSince

function Overlay.attachTooltip(frame, getText)
	tooltipTargets[frame] = getText
end

local function showTooltip(text)
	if not tooltip then
		local g = Glass.new({ Kind = "Surface", Name = "Tooltip", Parent = Library.Gui, Radius = 12, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Blur = false, Shadow = 0.3, ZIndex = 9000 })
		g.Content.AutomaticSize = Enum.AutomaticSize.XY
		g.Content.Size = UDim2.fromOffset(0, 0)
		Theme.bind(g.Dim, { BackgroundTransparency = function(t)
			return t.Name == "Light" and 0.15 or 0.2
		end })
		g.Label = Glass.text({ Parent = g.Content, Text = "", TextSize = S.Footnote, Weight = Enum.FontWeight.Medium, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Wrap = false, ZIndex = 9001 })
		new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = g.Label })
		new("UISizeConstraint", { MaxSize = Vector2.new(260, 200), Parent = g.Label })
		tooltip = g
	end
	tooltip.Label.Text = text
	tooltip.Label.TextWrapped = #text > 40
	tooltip.Root.Visible = true
	tooltip.Root.ZIndex = nextZ(1000)
	tooltip.Scale.Scale = 0.9
	tween(tooltip.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	Glass.surfaceFade(tooltip, true, 0.15)
end

local function hideTooltip()
	if tooltip and tooltip.Root.Visible then
		tooltip.Root.Visible = false
	end
end

Util.track(RunService.RenderStepped:Connect(function()
	local p = pointer()
	local hovered
	-- no tooltips while something is held or dragged
	local held = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	for frame in pairs(held and {} or tooltipTargets) do
		if frame.Parent and frame.Visible and Motion.inside(frame, p) then
			local o, visible = frame, true
			while o and o ~= Library.Gui do
				if o:IsA("GuiObject") and not o.Visible then
					visible = false
					break
				end
				o = o.Parent
			end
			if visible then
				hovered = frame
				break
			end
		end
	end
	if hovered ~= tipTarget then
		tipTarget, tipSince = hovered, os.clock()
		hideTooltip()
	elseif hovered and (not tooltip or not tooltip.Root.Visible) and os.clock() - tipSince > 0.6 then
		local text = tooltipTargets[hovered]()
		if text and text ~= "" then
			showTooltip(text)
		end
	end
	if tooltip and tooltip.Root.Visible then
		local s = Library.ScaleObject.Scale
		tooltip.Root.Position = UDim2.fromOffset(p.X / s + 14, p.Y / s + 18)
	end
end))

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
local notifications = {}
local notifyHolder = new("Frame", { Name = "Notifications", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = Library.Gui })

local TYPES = {
	info = { icon = "info", color = "Accent", sound = "notify" },
	success = { icon = "check-circle", color = "Success", sound = "success" },
	warning = { icon = "warning", color = "Warning", sound = "notify" },
	error = { icon = "error", color = "Danger", sound = "error" },
}

local function layoutNotifications()
	local s = Library.ScaleObject.Scale
	local vs = camera.ViewportSize / s
	local pos = (Library.NotifyPosition or "TopRight"):lower()
	local right = not pos:find("left")
	local bottom = pos:find("bottom") ~= nil
	local x = right and (vs.X - S.Notify - 16) or 16
	if pos:find("center") then
		x = (vs.X - S.Notify) / 2
	end
	local y = bottom and (vs.Y - 16) or (GuiService:GetGuiInset().Y / s + 12)
	for _, n in ipairs(notifications) do
		local h = n.Glass.Root.AbsoluteSize.Y / s
		if bottom then
			y -= h
		end
		local target = Vector2.new(x + (n.Offset or 0), y)
		if not n.Placed then
			n.Placed = true
			n.Glass.Root.Position = UDim2.fromOffset(target.X + (right and 60 or -60), target.Y)
		end
		if not n.Dragging then
			Motion.spring(n.Glass.Root, target, n.Closing and 18 or 20, n.Closing and 1 or 0.75)
		end
		n.Rest = target
		y = bottom and (y - 10) or (y + h + 10)
	end
end

Overlay.layoutNotifications = function()
	for _, n in ipairs(notifications) do
		n.Placed = false
	end
	layoutNotifications()
end

function Library:Notify(o)
	if type(o) == "string" then
		o = { Title = o }
	end
	o = o or {}
	local kind = TYPES[(opt(o, "info", "Type", "Kind", "Level")):lower()] or TYPES.info
	local duration = opt(o, 5, "Duration", "Time", "Delay")
	local n = {}
	local g = Glass.new({ Kind = "Surface", Name = "Notification", Parent = notifyHolder, Radius = S.NotifyRadius, Size = UDim2.fromOffset(S.Notify, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = nextZ(400), BlurStart = 0 })
	g.Root.Active = true
	n.Glass = g
	local body = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 6, Parent = g.Content }, { Util.pad(S.NotifyPad, S.NotifyPad, S.NotifyPad, S.NotifyPad) })
	local strut = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, S.NotifyBadge), Parent = body })
	local _ = strut
	-- icon or image
	local image = opt(o, nil, "Image", "Icon")
	local iconHolder
	if image and not Assets.isIcon(image) then
		iconHolder = new("ImageLabel", { BackgroundTransparency = 0.9, BackgroundColor3 = WHITE, Size = UDim2.fromOffset(S.NotifyBadge, S.NotifyBadge), ScaleType = Enum.ScaleType.Crop, ZIndex = 7, Parent = body }, { Util.corner(S.NotifyRadius - S.NotifyPad) })
		Assets.apply(iconHolder, image)
	else
		local badge = Glass.new({ Kind = "Tinted", Parent = body, Radius = S.NotifyRadius - S.NotifyPad, Size = UDim2.fromOffset(S.NotifyBadge, S.NotifyBadge), Tint = kind.color, Shadow = false, ZIndex = 7 })
		Glass.icon({ Parent = badge.Content, Icon = image or kind.icon, Size = 18, Color = "OnAccent" })
		iconHolder = badge.Root
	end
	local TX = S.NotifyBadge + 12
	local text = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(TX, 0), Size = UDim2.new(1, -TX, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 7, Parent = body }, { Util.list(nil, S.RowGap) })
	-- with one line of content the text block is as tall as the badge
	new("UISizeConstraint", { MinSize = Vector2.new(0, S.NotifyBadge), Parent = text })
	local titleRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 19), LayoutOrder = 1, ZIndex = 7, Parent = text })
	Glass.text({ Parent = titleRow, Text = opt(o, "Notification", "Title", "Name"), Weight = Enum.FontWeight.SemiBold, TextSize = S.Body, Truncate = true, Size = UDim2.new(1, -40, 1, 0) })
	Glass.text({ Parent = titleRow, Text = "now", TextSize = S.Footnote, Level = 3, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(1, 0, 1, 0) })
	local content = opt(o, nil, "Content", "Description", "Text", "Desc")
	if content then
		Glass.text({ Parent = text, Text = tostring(content), TextSize = S.Subhead, Level = 2, Wrap = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2 })
	end
	local sub = opt(o, nil, "SubContent", "Footer")
	if sub then
		Glass.text({ Parent = text, Text = tostring(sub), TextSize = S.Footnote, Level = 3, Wrap = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 3 })
	end
	-- actions (list or Rayfield-style dictionary)
	local actions = opt(o, nil, "Actions", "Buttons")
	local list = {}
	if type(actions) == "table" then
		for k, v in pairs(actions) do
			if type(v) == "table" then
				table.insert(list, { Title = v.Title or v.Name or tostring(k), Callback = v.Callback, Style = v.Style, Order = type(k) == "number" and k or 99 })
			end
		end
		table.sort(list, function(a2, b2)
			return a2.Order < b2.Order
		end)
	end
	if #list > 0 then
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, S.ButtonSmall + 10), LayoutOrder = 4, ZIndex = 7, Parent = text }, {
			Util.pad(10, 0, 0, 0),
			Util.list(Enum.FillDirection.Horizontal, 8, { HorizontalFlex = Enum.UIFlexAlignment.Fill }),
		})
		for i, a in ipairs(list) do
			capsule(row, { Title = a.Title, LayoutOrder = i, Width = UDim.new(0, 40), Variant = "Small" }, a.Style or (i == 1 and "primary" or "glass"), function()
				Util.fire(a.Callback)
				n.Close()
			end)
		end
	end
	-- remaining-time line
	local line = new("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, S.NotifyRadius, 1, -1), Size = UDim2.new(1, -2 * S.NotifyRadius, 0, 2), BackgroundTransparency = 0.5, ZIndex = 8, Parent = g.Content }, { Util.corner(1) })
	Theme.bind(line, { BackgroundColor3 = kind.color })

	table.insert(notifications, 1, n)
	Glass.surfaceFade(g, false, 0)
	g.Scale.Scale = 0.94
	task.defer(function()
		Glass.surfaceFade(g, true, 0.3)
		tween(g.Scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		g.BlurRegion:SetTarget(1, 10)
		Motion.groupFade(g.Content, 1, 0, 0.3)
		layoutNotifications()
	end)
	if opt(o, true, "Sound") ~= false then
		Sound.play(kind.sound)
	end

	local remaining = duration
	local hovered = false
	function n.Close()
		if n.Closed then
			return
		end
		n.Closed = true
		n.Closing = true
		local i = table.find(notifications, n)
		if i then
			table.remove(notifications, i)
		end
		local s = Library.ScaleObject.Scale
		local vs = camera.ViewportSize / s
		local right = not (Library.NotifyPosition or ""):lower():find("left")
		Motion.spring(g.Root, Vector2.new(right and vs.X + 20 or -S.Notify - 20, g.Root.Position.Y.Offset), 16, 1)
		Glass.surfaceFade(g, false, 0.3)
		g.BlurRegion:SetTarget(0, 10)
		task.delay(0.45, function()
			g.Root:Destroy()
		end)
		layoutNotifications()
		Util.fire(o.OnClose)
	end
	n.Dismiss = n.Close

	local hit = hitbox(g.Root, 4)
	hit.MouseEnter:Connect(function()
		hovered = true
	end)
	hit.MouseLeave:Connect(function()
		hovered = false
	end)
	local startX
	Motion.drag(hit, {
		began = function()
			startX = Motion.target(g.Root).X
			n.Dragging = true
		end,
		moved = function(_, d, moved)
			if moved then
				local rest = n.Rest or Motion.target(g.Root)
				Motion.spring(g.Root, Vector2.new(startX + Motion.rubber(d.X, -6, 400, 20), rest.Y), 40, 1)
			end
		end,
		ended = function(_, moved, input)
			n.Dragging = false
			local _ = input
			local dx = Motion.target(g.Root).X - (n.Rest and n.Rest.X or 0)
			if moved and dx > 70 then
				n.Close()
			elseif not moved and #list == 0 then
				Util.fire(o.OnClick or o.Callback)
				n.Close()
			else
				layoutNotifications()
			end
		end,
	})

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if n.Closed or not g.Root.Parent then
			conn:Disconnect()
			return
		end
		if not hovered and not n.Dragging and duration and duration > 0 then
			remaining -= dt
			local f = math.max(remaining / duration, 0)
			line.Size = UDim2.new(f, -2 * S.NotifyRadius * f, 0, 2)
			if remaining <= 0 then
				n.Close()
			end
		end
	end)
	g.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutNotifications)
	return n
end

---------------------------------------------------------------------------
-- Dialogs (alerts)
---------------------------------------------------------------------------
function Library:Dialog(o, window)
	o = o or {}
	if Overlay.dialog then
		Overlay.dialog.Close()
	end
	local d = {}
	local host = window and window.Glass.Content or Library.Gui
	local shade = new("TextButton", { Name = "DialogShade", Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = window and 80 or nextZ(), Parent = host }, { window and Util.corner(S.WindowRadius) or nil })
	Theme.bind(shade, { BackgroundColor3 = "Overlay" })
	tween(shade, 0.3, { BackgroundTransparency = Theme.current.OverlayT })
	local g = Glass.new({ Kind = "Surface", Dense = window ~= nil, Name = "Dialog", Parent = Library.Gui, Radius = S.DialogRadius, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(o.Width or S.DialogW, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = nextZ(600), BlurStart = 0 })
	g.Root.Active = true
	local function center()
		local s = Library.ScaleObject.Scale
		if window then
			local p, size = screenPos(window.Root) / s, window.Root.AbsoluteSize / s
			g.Root.Position = UDim2.fromOffset(p.X + size.X / 2, p.Y + size.Y / 2)
		else
			local vs = camera.ViewportSize / s
			g.Root.Position = UDim2.fromOffset(vs.X / 2, vs.Y / 2)
		end
	end
	center()
	local follow = RunService.RenderStepped:Connect(center)
	local body = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 6, Parent = g.Content }, {
		Util.pad(S.DialogPad, S.DialogPad, S.DialogPad, S.DialogPad),
		Util.list(nil, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	local icon = opt(o, nil, "Icon", "Image")
	if icon then
		local badge = Glass.new({ Kind = "Tinted", Parent = body, Radius = 12, Size = UDim2.fromOffset(44, 44), Tint = o.IconColor or "Accent", Shadow = 0.25, SmallShadow = true, LayoutOrder = 1, ZIndex = 7 })
		Glass.icon({ Parent = badge.Content, Icon = icon, Size = 22, Color = "OnAccent" })
	end
	Glass.text({ Parent = body, Text = opt(o, "Are you sure?", "Title", "Name"), Weight = Enum.FontWeight.SemiBold, TextSize = S.Title, XAlign = Enum.TextXAlignment.Center, Wrap = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2 })
	local content = opt(o, nil, "Content", "Description", "Text")
	if content then
		Glass.text({ Parent = body, Text = tostring(content), TextSize = S.Subhead, Level = 2, XAlign = Enum.TextXAlignment.Center, Wrap = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 3 })
	end
	local inputOpts = opt(o, nil, "Input", "TextBox")
	local field
	if inputOpts then
		local fh = S.Control + 4
		local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, fh + 4), LayoutOrder = 4, ZIndex = 7, Parent = body }, { Util.pad(4, 0, 0, 0) })
		field = Glass.field(holder, { Placeholder = type(inputOpts) == "table" and inputOpts.Placeholder or "", Text = type(inputOpts) == "table" and inputOpts.Default or "", Height = fh, Size = UDim2.new(1, 0, 0, fh) })
	end
	local buttons = opt(o, { { Title = "OK", Style = "Primary" } }, "Buttons", "Actions")
	local horizontal = #buttons == 2
	local btnHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, ZIndex = 7, Parent = body }, {
		Util.pad(12, 0, 0, 0),
		Util.list(horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical, 8, horizontal and { HorizontalFlex = Enum.UIFlexAlignment.Fill } or nil),
	})
	local cancelButton
	for i, b in ipairs(buttons) do
		local style = (b.Style or (i == 1 and "Primary" or "Glass"))
		if style:lower() == "cancel" then
			style = "Glass"
			cancelButton = b
		end
		capsule(btnHolder, { Title = b.Title or b.Name, Icon = b.Icon, LayoutOrder = i, Width = horizontal and UDim.new(0, 40) or UDim.new(1, 0), Variant = "Large" }, style, function()
			local keep = b.Callback and b.Callback(field and field.Box.Text or nil)
			if keep ~= false then
				d.Close()
			end
		end)
	end
	g.Scale.Scale = 1.12
	Glass.surfaceFade(g, false, 0)
	task.defer(function()
		Glass.surfaceFade(g, true, 0.25)
		tween(g.Scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		g.BlurRegion:SetTarget(1, 14)
		Motion.groupFade(g.Content, 1, 0, 0.25)
	end)
	Sound.play("popup")
	function d.Close()
		if d.Closed then
			return
		end
		d.Closed = true
		if Overlay.dialog == d then
			Overlay.dialog = nil
		end
		follow:Disconnect()
		tween(shade, 0.25, { BackgroundTransparency = 1 })
		tween(g.Scale, 0.2, { Scale = 0.92 }, Enum.EasingStyle.Quad)
		Glass.surfaceFade(g, false, 0.2)
		g.BlurRegion:SetTarget(0, 16)
		Motion.groupFade(g.Content, 0, 1, 0.2)
		task.delay(0.3, function()
			g.Root:Destroy()
			shade:Destroy()
		end)
	end
	function d.Cancel()
		if cancelButton then
			Util.fire(cancelButton.Callback)
		end
		d.Close()
	end
	shade.Activated:Connect(function()
		if o.CloseOnShade ~= false then
			d.Cancel()
		end
	end)
	Overlay.dialog = d
	return d
end

function Window:Dialog(o)
	return Library:Dialog(o, self)
end

function Window:Notify(o)
	return Library:Notify(o)
end
