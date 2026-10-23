---------------------------------------------------------------------------
-- Elements
-- Every element accepts LiquidGlass, Rayfield and Fluent style options:
--   Title/Name/Text, Description/Desc/Content, Icon, IconColor, Flag, Callback,
--   Tooltip, Disabled, Visible; plus AddX("Flag", {...}) and AddX("Title", fn).
-- Every element has :SetTitle :SetDescription :SetVisible :SetDisabled
-- :Destroy :OnChanged, value elements also :Set/:SetValue :Get/:GetValue .Value
---------------------------------------------------------------------------
local Element = {}
Element.__index = Element
Library._classes.Element = Element

local function normalize(a, b)
	if type(a) == "string" and type(b) == "table" then
		b.Flag = b.Flag or a
		return b
	elseif type(a) == "string" then
		return { Title = a, Callback = type(b) == "function" and b or nil }
	end
	return a or {}
end

function Section:_element(o, kind, rowOpts)
	local el = setmetatable({
		Section = self,
		Type = kind,
		Opts = o,
		TitleText = opt(o, "", "Title", "Name", "Text"),
		DescText = opt(o, nil, "Description", "Desc", "SubText"),
		Callback = opt(o, nil, "Callback", "Func", "Function"),
		Flag = opt(o, nil, "Flag", "Id", "Idx"),
		Listeners = {},
	}, Element)
	if rowOpts ~= false then
		rowOpts = rowOpts or {}
		rowOpts.Title = rowOpts.Title or el.TitleText
		rowOpts.Description = rowOpts.Description or el.DescText
		rowOpts.Icon = rowOpts.Icon == nil and opt(o, nil, "Icon", "Image") or rowOpts.Icon or nil
		rowOpts.IconColor = rowOpts.IconColor or opt(o, nil, "IconColor", "BadgeColor")
		rowOpts.MinHeight = opt(o, rowOpts.MinHeight, "RowHeight")
		el.Row = self:_row(rowOpts)
		el:_style(o)
	end
	table.insert(self.Elements, el)
	table.insert(self.Tab.Elements, el)
	if el.Flag then
		Library.Options[el.Flag] = el
		Library.Flags[el.Flag] = el
	end
	local tip = opt(o, nil, "Tooltip", "Hint")
	if tip and el.Row then
		Overlay.attachTooltip(el.Row.Frame, function()
			return el.TooltipText or tip
		end)
		el.TooltipText = tip
	end
	if o.Visible == false then
		el._hidden = true
		el:_updateVisible()
	end
	if opt(o, false, "Disabled", "Locked") then
		task.defer(function()
			el:SetDisabled(true)
		end)
	end
	self:_refresh()
	return el
end

-- per-element text styling: TitleSize, DescriptionSize, TitleColor, DescriptionColor,
-- Font (any font), TitleWeight / DescriptionWeight (Enum.FontWeight or its name)
local function weightOf(v, default)
	if typeof(v) == "EnumItem" then
		return v
	end
	if type(v) == "string" then
		local ok, w = pcall(function()
			return Enum.FontWeight[v]
		end)
		if ok and w then
			return w
		end
	end
	return default
end

function Element:_style(o)
	local row = self.Row
	if not row then
		return
	end
	local fam = Util.fontFamily(opt(o, nil, "Font", "FontFace", "FontFamily"))
	local function apply(label, size, color, weight)
		if size then
			label.TextSize = size
		end
		if color then
			Theme.bind(label, { TextColor3 = color })
		end
		if fam or weight then
			label.FontFace = Font.new(fam or label.FontFace.Family, weightOf(weight, label.FontFace.Weight))
		end
	end
	apply(row.Title, opt(o, nil, "TitleSize", "TextSize"), opt(o, nil, "TitleColor"), opt(o, nil, "TitleWeight", "Weight"))
	apply(row.Desc, opt(o, nil, "DescriptionSize", "DescSize"), opt(o, nil, "DescriptionColor", "DescColor"), opt(o, nil, "DescriptionWeight"))
end

-- size variant of a control: "Small" | "Regular" | "Large" or a number factor
local VARIANT = { small = 0.82, regular = 1, large = 1.18 }
local function sizeFactor(o)
	local v = opt(o, nil, "Size", "ControlSize")
	if type(v) == "number" then
		return math.clamp(v, 0.5, 2)
	end
	if type(v) == "string" then
		return VARIANT[v:lower()] or 1
	end
	return 1
end
Library._sizeFactor = sizeFactor

function Element:_updateVisible()
	if self.Row then
		self.Row.Frame.Visible = not self._hidden and not self._filtered
	end
	self.Section:_refresh()
end

function Element:SetVisible(on)
	self._hidden = not on
	self:_updateVisible()
end

function Element:SetTitle(t)
	self.TitleText = t or ""
	if self.Row then
		self.Row.Title.Text = self.TitleText
		self.Row.Title.Visible = self.TitleText ~= ""
	end
end
Element.SetName = Element.SetTitle

function Element:SetDescription(d)
	self.DescText = d
	if self.Row then
		self.Row.Desc.Text = d or ""
		self.Row.Desc.Visible = (d or "") ~= ""
	end
end
Element.SetDesc = Element.SetDescription

function Element:SetTooltip(t)
	self.TooltipText = t
end

function Element:SetDisabled(on)
	self.Disabled = on and true or false
	if self.Row then
		self.Row.SetLocked(self.Disabled)
	end
end
function Element:Lock()
	self:SetDisabled(true)
end
function Element:Unlock()
	self:SetDisabled(false)
end

function Element:OnChanged(fn)
	table.insert(self.Listeners, fn)
	if self.Value ~= nil then
		Util.fire(fn, self.Value)
	end
	return {
		Disconnect = function()
			local i = table.find(self.Listeners, fn)
			if i then
				table.remove(self.Listeners, i)
			end
		end,
	}
end

function Element:_emit(...)
	Util.fire(self.Callback, ...)
	for _, fn in ipairs(self.Listeners) do
		Util.fire(fn, ...)
	end
end

function Element:_store(v)
	self.Value = v
	self.CurrentValue = v
	self.CurrentOption = v
	self.CurrentKeybind = v
	self.Color = v
end

function Element:SetValue(...)
	if self.Set then
		return self:Set(...)
	end
end

function Element:GetValue()
	return self.Value
end
Element.Get = Element.GetValue

function Element:Destroy()
	if self.Row then
		self.Row.Frame:Destroy()
	end
	local list = self.Section.Elements
	local i = table.find(list, self)
	if i then
		table.remove(list, i)
	end
	i = table.find(self.Section.Tab.Elements, self)
	if i then
		table.remove(self.Section.Tab.Elements, i)
	end
	if self.Flag and Library.Options[self.Flag] == self then
		Library.Options[self.Flag] = nil
		Library.Flags[self.Flag] = nil
	end
	if self._cleanup then
		self._cleanup()
	end
	self.Section:_refresh()
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
local CAPSULE_STYLES = {
	primary = { kind = "Tinted", tint = "Accent", text = "OnAccent" },
	destructive = { kind = "Tinted", tint = "Danger", text = "OnAccent" },
	danger = { kind = "Tinted", tint = "Danger", text = "OnAccent" },
	success = { kind = "Tinted", tint = "Success", text = "OnAccent" },
	secondary = { kind = "Control", text = "Text" },
	glass = { kind = "Control", text = "Text" },
}

-- height, text size, icon size and gap of each capsule size
-- height, text size, icon size and gap of each capsule size (read live: density aware)
local function capsuleSize(variant)
	local v = type(variant) == "string" and variant:lower() or "regular"
	if v == "small" then
		return { S.ButtonSmall, S.Subhead, math.floor(S.ButtonSmall * 0.46), 6 }
	elseif v == "large" then
		return { S.ButtonLarge, S.Body, math.floor(S.ButtonLarge * 0.42), 8 }
	end
	return { S.Button, S.Body, math.floor(S.Button * 0.44), 7 }
end

-- o.Width: UDim (default: fill); o.Variant: "Small" | "Regular" | "Large"
local function capsule(parent, o, style, onClick)
	local st = CAPSULE_STYLES[(style or "glass"):lower()] or CAPSULE_STYLES.glass
	local sz = capsuleSize(o.Variant)
	local h = sz[1]
	local width = o.Width or UDim.new(1, 0)
	local g = Glass.new({
		Kind = st.kind,
		Name = "Capsule",
		Parent = parent,
		Radius = h / 2,
		Size = UDim2.new(width.Scale, width.Offset, 0, h),
		Tint = st.tint,
		Shadow = st.kind == "Tinted" and 0.25 or false,
		SmallShadow = true,
		ZIndex = 7,
		LayoutOrder = o.LayoutOrder,
	})
	local holder = new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, h), ZIndex = 8, Parent = g.Content }, {
		Util.list(Enum.FillDirection.Horizontal, sz[4], { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	new("UISizeConstraint", { MaxSize = Vector2.new(math.huge, h), Parent = holder })
	local icon = opt(o, nil, "Icon", "Image")
	if icon then
		Glass.icon({ Parent = holder, Icon = icon, Size = sz[3], Color = st.text, Position = UDim2.new(), AnchorPoint = Vector2.zero, LayoutOrder = 1, ZIndex = 8 })
	end
	local label = Glass.text({ Parent = holder, Text = opt(o, "Button", "Title", "Name", "Text"), Weight = Enum.FontWeight.SemiBold, TextSize = opt(o, sz[2], "TextSize", "TitleSize"), Color = st.text, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h), LayoutOrder = 2, ZIndex = 8 })
	g.Label = label
	if o.Auto then
		-- hug the label: side padding = half the height, like an iOS capsule
		local function fit()
			local sc = Library.ScaleObject.Scale
			g.Root.Size = UDim2.fromOffset(math.ceil(holder.AbsoluteSize.X / sc) + h, h)
		end
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		task.defer(fit)
	end
	g.Hit = Glass.pressable(g, { Grow = 1.04, OnClick = onClick, Disabled = o.IsDisabled })
	return g
end

function Section:AddButton(a, b)
	local o = normalize(a, b)
	local style = opt(o, nil, "Style", "Variant", "Type")
	local variant = opt(o, nil, "Size", "ButtonSize")
	if type(variant) ~= "string" then
		variant = nil
	end
	if not style and (variant or opt(o, nil, "Width", "ButtonWidth")) then
		style = "Glass"
	end
	if style and style:lower() ~= "row" then
		local sz = capsuleSize(variant)
		local rowH = math.max(S.RowMin, sz[1] + 12)
		local pad = (rowH - sz[1]) / 2
		local el = self:_element(o, "Button", { Title = "", Description = "", Icon = false, MinHeight = rowH })
		el.Row.Body.Visible = false
		-- a fixed height: the capsule's drop shadow must not grow the row
		el.Row.Frame.AutomaticSize = Enum.AutomaticSize.None
		el.Row.Frame.Size = UDim2.new(1, 0, 0, rowH)
		-- Width: "Fill" (default), "Auto" (hugs the label) or px; Align for the narrower ones
		local width = opt(o, "Fill", "Width", "ButtonWidth")
		local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH), ZIndex = 7, Parent = el.Row.Frame }, { Util.pad(pad, pad, pad, pad) })
		local co = table.clone(o)
		co.Variant = variant
		if width ~= "Fill" then
			local align = opt(o, "Center", "Align")
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment[align] or Enum.HorizontalAlignment.Center, Parent = holder })
			if type(width) == "number" then
				co.Width = UDim.new(0, width)
			else
				co.Width = UDim.new(0, sz[1] * 3)
				co.Auto = true
			end
		end
		el.Capsule = capsule(holder, co, style, function()
			el:_emit()
		end)
		el.NoSeparator = true
		function el:SetTitle(t)
			self.TitleText = t
			self.Capsule.Label.Text = t
		end
		function el:Fire()
			self:_emit()
		end
		self:_refresh()
		return el
	end

	local accessory = opt(o, nil, "Accessory", "Value")
	local el = self:_element(o, "Button", { Right = accessory and 120 or S.Chevron })
	local row = el.Row
	if accessory then
		el.AccessoryLabel = Glass.text({ Parent = row.Right, Text = tostring(accessory), Level = 2, TextSize = S.Body, XAlign = Enum.TextXAlignment.Right, Truncate = true, Size = UDim2.new(1, -(S.Chevron + 8), 1, 0), ZIndex = 8 })
	end
	Glass.icon({ Parent = row.Right, Icon = "chevron-right", Size = S.Chevron, Level = 3, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 8 })
	local color = opt(o, nil, "Color", "TextColor")
	if opt(o, false, "Destructive", "Danger") then
		color = "Danger"
	end
	if color then
		Theme.bind(row.Title, { TextColor3 = color })
	end
	row.Interactive(function()
		Sound.play("click")
		el:_emit()
	end)
	function el:Fire()
		self:_emit()
	end
	function el:SetAccessory(t)
		if self.AccessoryLabel then
			self.AccessoryLabel.Text = tostring(t)
		end
	end
	return el
end

-- a row of capsule buttons sharing the width
-- o: Size ("Small" | "Regular" | "Large") for every capsule in the row
function Section:AddButtons(list, o)
	o = o or {}
	local el = self:_element({ Title = "" }, "Buttons", { Title = "", Description = "" })
	el.Row.Body.Visible = false
	el.NoSeparator = true
	el.Row.Frame.AutomaticSize = Enum.AutomaticSize.None
	el.Row.Frame.Size = UDim2.new(1, 0, 0, S.RowMin)
	local pad = (S.RowMin - S.Button) / 2
	local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, S.RowMin), ZIndex = 7, Parent = el.Row.Frame }, {
		Util.pad(pad, pad, pad, pad),
		Util.list(Enum.FillDirection.Horizontal, pad, { HorizontalFlex = Enum.UIFlexAlignment.Fill }),
	})
	el.Buttons = {}
	for i, b in ipairs(list or {}) do
		local c = capsule(holder, { Title = b.Title or b.Name, Icon = b.Icon, LayoutOrder = i, Width = UDim.new(0, 40), Variant = b.Size or o.Size }, b.Style or "glass", function()
			Util.fire(b.Callback)
		end)
		el.Buttons[i] = c
	end
	self:_refresh()
	return el
end

---------------------------------------------------------------------------
-- Toggle (iOS switch: tap, or drag the knob; it becomes a glass lens while held)
---------------------------------------------------------------------------
function Glass.switch(parent, on, onChange, factor)
	factor = factor or 1
	local SW, SH = math.floor(S.SwitchW * factor + 0.5), math.floor(S.SwitchH * factor + 0.5)
	local KW, KH = math.floor(S.KnobW * factor + 0.5), math.floor(S.KnobH * factor + 0.5)
	KH = math.min(KH, SH - 4)
	local inset = (SH - KH) / 2
	local OFF_X, ON_X = inset, SW - KW - inset
	local KNOB = { Base = Vector2.new(KW, KH), Rest = UDim2.fromOffset(KW, KH), Axis = "X" }
	local trackFrame = new("Frame", { Name = "Switch", BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(SW, SH), ZIndex = 8, Parent = parent }, { Util.corner(SH / 2) })
	local knob = Glass.new({ Kind = "Solid", Name = "Knob", Parent = trackFrame, Radius = KH / 2, Size = KNOB.Rest, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, on and ON_X or OFF_X, 0.5, 0), ZIndex = 9 })
	local ctl = { State = on, Root = trackFrame, OffX = OFF_X, OnX = ON_X, KnobSize = KNOB.Rest }
	local function paint(f, time)
		f = math.clamp(f, 0, 1)
		local t = Theme.current
		local col = t.Track:Lerp(Theme.value("Switch"), f)
		local tr = t.TrackT * (1 - f)
		if time then
			tween(trackFrame, time, { BackgroundColor3 = col, BackgroundTransparency = tr })
		else
			trackFrame.BackgroundColor3, trackFrame.BackgroundTransparency = col, tr
		end
	end
	paint(on and 1 or 0)
	Theme.onChange(function()
		paint(ctl.State and 1 or 0)
	end)
	local function lens(held)
		tween(knob.Scale, held and 0.3 or 0.5, { Scale = held and 1.32 or 1 }, held and Enum.EasingStyle.Quint or Enum.EasingStyle.Back)
		tween(knob.Fill, 0.3, { BackgroundTransparency = held and 0.82 or 0 })
		if knob.Rim and knob.Rim:IsA("ImageLabel") then
			tween(knob.Rim, 0.3, { ImageTransparency = held and 0 or 1 })
		end
	end
	function ctl.Set(v, silent)
		v = v and true or false
		local changed = v ~= ctl.State
		ctl.State = v
		Motion.spring(knob.Root, Vector2.new(v and ON_X or OFF_X, 0), 26, 0.55, KNOB)
		paint(v and 1 or 0, 0.35)
		if changed and not silent then
			Sound.play(v and "toggle_on" or "toggle_off")
			onChange(v)
		end
	end
	local hit = hitbox(trackFrame, 12, { Size = UDim2.new(1, 16, 1, 16), Position = UDim2.fromOffset(-8, -8) })
	local startX
	Motion.drag(hit, {
		allow = function()
			return not (ctl.Disabled and ctl.Disabled())
		end,
		began = function()
			startX = Motion.target(knob.Root).X
			lens(true)
		end,
		moved = function(_, delta, moved)
			if moved then
				local x = Motion.rubber(startX + delta.X / Library.ScaleObject.Scale, OFF_X, ON_X, 5)
				Motion.spring(knob.Root, Vector2.new(x, 0), 45, 1, KNOB)
				paint((x - OFF_X) / (ON_X - OFF_X))
			end
		end,
		ended = function(_, moved)
			local v
			if moved then
				v = Motion.target(knob.Root).X > (OFF_X + ON_X) / 2
			else
				v = not ctl.State
			end
			lens(false)
			if v == ctl.State then
				Motion.spring(knob.Root, Vector2.new(v and ON_X or OFF_X, 0), 26, 0.55, KNOB)
				paint(v and 1 or 0, 0.3)
			end
			ctl.Set(v)
		end,
	})
	ctl.Hit = hit
	return ctl
end

function Section:AddToggle(a, b)
	local o = normalize(a, b)
	local factor = sizeFactor(o)
	local el = self:_element(o, "Toggle", { Right = math.floor(S.SwitchW * factor + 0.5) })
	local initial = opt(o, false, "Default", "Value", "CurrentValue", "State") and true or false
	el:_store(initial)
	el.Switch = Glass.switch(el.Row.Right, initial, function(v)
		el:_store(v)
		el:_emit(v)
	end, factor)
	el.Switch.Disabled = function()
		return el.Disabled
	end
	el.Row.Interactive(function()
		el.Switch.Set(not el.Switch.State)
	end, { HoverSound = false })
	function el:Set(v, silent)
		v = v and true or false
		self:_store(v)
		self.Switch.Set(v, true)
		if not silent then
			Sound.play(v and "toggle_on" or "toggle_off")
			self:_emit(v)
		end
	end
	function el:Toggle()
		self:Set(not self.Value)
	end
	if initial then
		task.defer(function()
			el:_emit(true)
		end)
	end
	return el
end

---------------------------------------------------------------------------
-- Slider
---------------------------------------------------------------------------
function Section:AddSlider(a, b)
	local o = normalize(a, b)
	local range = opt(o, nil, "Range")
	local min = opt(o, range and range[1] or 0, "Min", "Minimum")
	local max = opt(o, range and range[2] or 100, "Max", "Maximum")
	local step = opt(o, nil, "Step", "Increment", "Interval")
	local rounding = opt(o, nil, "Rounding", "Decimals")
	if not step then
		step = rounding and 10 ^ -rounding or (max - min <= 1 and 0.01 or 1)
	end
	local decimals = rounding or Util.decimals(step)
	local prefix, suffix = opt(o, "", "Prefix"), opt(o, "", "Suffix")
	if suffix ~= "" and not suffix:match("^[%%x]") and not suffix:match("^%s") and not suffix:match("^°") and not suffix:match("^×") then
		suffix = " " .. suffix
	end
	local factor = sizeFactor(o)
	local KW, KH = math.floor(S.KnobW * factor + 0.5), math.floor(S.KnobH * factor + 0.5)
	local TRACK = opt(o, math.max(4, math.floor(6 * factor + 0.5)), "TrackHeight", "TrackThickness")
	local el = self:_element(o, "Slider", { PadY = S.RowPadY + 2 })
	local row = el.Row
	row.TopIcon()
	new("UIPadding", { PaddingRight = UDim.new(0, 80), Parent = row.Title })

	local valueBox = new("TextBox", {
		Name = "Value",
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		TextEditable = true,
		FontFace = Util.font(Enum.FontWeight.Regular),
		TextSize = S.Body,
		TextXAlignment = Enum.TextXAlignment.Right,
		-- top-aligned at the title's top: both use the same font size
		TextYAlignment = Enum.TextYAlignment.Top,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S.RowInset, 0, S.RowPadY + 2),
		Size = UDim2.fromOffset(80, 19),
		ZIndex = 9,
		Parent = row.Frame,
	})
	Theme.bind(valueBox, { TextColor3 = "Text", TextTransparency = "Text2T" })

	-- the knob travels inside the track's ends: half a knob of padding each side
	local holder = new("Frame", { Name = "Slider", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, KH + 8), LayoutOrder = 3, ZIndex = 7, Parent = row.Body })
	local trackFrame = new("Frame", { Name = "Track", BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, TRACK), ZIndex = 7, Parent = holder }, { Util.corner(TRACK / 2) })
	Theme.bind(trackFrame, { BackgroundColor3 = "Track", BackgroundTransparency = "TrackT" })
	local fill = new("Frame", { Name = "Fill", BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 8, Parent = trackFrame }, { Util.corner(TRACK / 2) })
	Theme.bind(fill, { BackgroundColor3 = "Accent" })
	local knob = Glass.new({ Kind = "Solid", Name = "Knob", Parent = holder, Radius = KH / 2, Size = UDim2.fromOffset(KW, KH), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), ZIndex = 9 })

	local value
	local function frac(v)
		return max == min and 0 or (v - min) / (max - min)
	end
	-- the track spans the full width; the knob's center travels between its ends
	-- inset by half a knob, and the fill always reaches the knob's center
	local function show(v)
		local f = frac(v)
		local off = KW * (0.5 - f)
		fill.Size = UDim2.new(f, off, 1, 0)
		knob.Root.Position = UDim2.new(f, off, 0.5, 0)
		if not valueBox:IsFocused() then
			valueBox.Text = prefix .. Util.format(v, decimals) .. suffix
		end
	end
	local function set(v, silent, fromDrag)
		v = math.clamp(Util.snap(v, min, step), min, max)
		v = tonumber(Util.format(v, decimals)) or v
		local changed = v ~= value
		value = v
		el:_store(v)
		show(v)
		if changed then
			if fromDrag then
				Sound.play("tick")
			end
			if not silent then
				el:_emit(v)
			end
		end
	end
	set(opt(o, min, "Default", "Value", "CurrentValue"), true)

	local hit = hitbox(holder, 12, { Size = UDim2.new(1, 12, 1, 12), Position = UDim2.fromOffset(-6, -6) })
	local function fromPointer(p)
		local sc = Library.ScaleObject.Scale
		local half = KW / 2 * sc
		local left = screenPos(trackFrame).X + half
		local w = trackFrame.AbsoluteSize.X - 2 * half
		return min + math.clamp((p.X - left) / math.max(w, 1), 0, 1) * (max - min)
	end
	Motion.drag(hit, {
		allow = function()
			return not el.Disabled
		end,
		began = function(p)
			set(fromPointer(p), false, true)
			tween(knob.Scale, 0.3, { Scale = 1.35 }, Enum.EasingStyle.Quint)
			tween(knob.Fill, 0.25, { BackgroundTransparency = 0.85 })
			if knob.Rim and knob.Rim:IsA("ImageLabel") then
				tween(knob.Rim, 0.25, { ImageTransparency = 0 })
			end
		end,
		moved = function(p)
			set(fromPointer(p), false, true)
		end,
		ended = function()
			tween(knob.Scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			tween(knob.Fill, 0.35, { BackgroundTransparency = 0 })
			if knob.Rim and knob.Rim:IsA("ImageLabel") then
				tween(knob.Rim, 0.35, { ImageTransparency = 1 })
			end
			Util.fire(opt(o, nil, "Released", "ChangedCallback", "OnRelease"), value)
		end,
	})
	valueBox.Focused:Connect(function()
		valueBox.Text = Util.format(value, decimals)
	end)
	valueBox.FocusLost:Connect(function()
		local n = tonumber((valueBox.Text:gsub("[^%d%.%-]", "")))
		valueBox.Text = ""
		if n then
			set(n)
		end
		show(value)
	end)
	function el:Set(v, silent)
		set(tonumber(v) or value, silent)
	end
	function el:SetRange(a2, b2)
		min, max = a2, b2
		set(value, true)
	end
	function el:SetMin(v)
		self:SetRange(v, max)
	end
	function el:SetMax(v)
		self:SetRange(min, v)
	end
	return el
end

---------------------------------------------------------------------------
-- Dropdown
---------------------------------------------------------------------------
function Section:AddDropdown(a, b)
	local o = normalize(a, b)
	local options = table.clone(opt(o, {}, "Options", "Values", "List", "Items"))
	local multi = opt(o, false, "Multi", "MultipleOptions", "Multiple", "MultiSelect")
	local placeholder = opt(o, multi and "None" or "Select", "Placeholder", "PlaceholderText")
	local allowNull = opt(o, multi, "AllowNull", "AllowEmpty")
	local el = self:_element(o, "Dropdown", { Right = opt(o, 160, "Width", "ValueWidth") })
	local row = el.Row
	local valueLabel = Glass.text({ Parent = row.Right, Text = "", Level = 2, TextSize = S.Body, XAlign = Enum.TextXAlignment.Right, Truncate = true, Size = UDim2.new(1, -(S.Chevron + 8), 1, 0), ZIndex = 8 })
	local chevron = Glass.icon({ Parent = row.Right, Icon = "chevron-down", Size = S.Chevron, Level = 3, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 8 })

	local selected = {} -- set
	local order = {}
	local function label(v)
		return tostring(v)
	end
	local function current()
		if multi then
			local out = {}
			for _, v in ipairs(options) do
				if selected[v] then
					table.insert(out, v)
				end
			end
			return out
		end
		return order[1]
	end
	local function refreshText()
		local v = current()
		if multi then
			if #v == 0 then
				valueLabel.Text = placeholder
			elseif #v <= 2 then
				local parts = {}
				for _, x in ipairs(v) do
					table.insert(parts, label(x))
				end
				valueLabel.Text = table.concat(parts, ", ")
			else
				valueLabel.Text = #v .. " selected"
			end
		else
			valueLabel.Text = v ~= nil and label(v) or placeholder
		end
	end
	local function commit(silent)
		local v = current()
		el:_store(v)
		refreshText()
		if el.Menu then
			el.Menu.SetSelected(selected)
		end
		if not silent then
			el:_emit(v)
		end
	end
	local function setValue(v)
		table.clear(selected)
		table.clear(order)
		if type(v) == "number" and options[v] ~= nil and not table.find(options, v) then
			v = options[v] -- Fluent: default given as an index
		end
		if type(v) == "table" then
			local list = v
			if #v == 0 then
				list = {}
				for k, on in pairs(v) do
					if on then
						table.insert(list, k)
					end
				end
			end
			for _, x in ipairs(list) do
				if table.find(options, x) ~= nil then
					selected[x] = true
					table.insert(order, x)
					if not multi then
						break
					end
				end
			end
		elseif v ~= nil and table.find(options, v) then
			selected[v] = true
			table.insert(order, v)
		end
	end
	setValue(opt(o, nil, "Default", "CurrentOption", "Value", "Selected"))
	commit(true)

	local function pick(v)
		if multi then
			selected[v] = not selected[v] or nil
		else
			if selected[v] and allowNull then
				table.clear(selected)
				table.clear(order)
			else
				table.clear(selected)
				table.clear(order)
				selected[v] = true
				order[1] = v
			end
		end
		commit()
	end

	row.Interactive(function()
		if el.Menu then
			el.Menu.Close()
			return
		end
		Sound.play("popup")
		tween(chevron, 0.3, { Rotation = 180 })
		el.Menu = Overlay.menu({
			Anchor = row.Frame,
			Align = "Right",
			Width = math.clamp(row.Frame.AbsoluteSize.X * 0.5, 200, 280),
			Options = options,
			Selected = selected,
			Multi = multi,
			Search = opt(o, #options > 8, "Searchable", "Search"),
			Label = label,
			OnPick = function(v)
				pick(v)
				return multi
			end,
			OnClose = function()
				el.Menu = nil
				tween(chevron, 0.3, { Rotation = 0 })
			end,
		})
	end)

	function el:Set(v, silent)
		setValue(v)
		commit(silent)
	end
	function el:SetOptions(list, keep)
		options = table.clone(list or {})
		if keep then
			for k in pairs(selected) do
				if not table.find(options, k) then
					selected[k] = nil
				end
			end
			for i = #order, 1, -1 do
				if not selected[order[i]] then
					table.remove(order, i)
				end
			end
		else
			table.clear(selected)
			table.clear(order)
		end
		self.Options = options
		self.Values = options
		if self.Menu then
			self.Menu.Close()
		end
		commit(true)
	end
	function el:Refresh(list, keep)
		self:SetOptions(list, keep == nil and true or keep)
	end
	el.SetValues = el.SetOptions
	function el:Add(v)
		table.insert(options, v)
		self:SetOptions(options, true)
	end
	function el:Remove(v)
		local i = table.find(options, v)
		if i then
			table.remove(options, i)
		end
		self:SetOptions(options, true)
	end
	function el:Clear()
		table.clear(selected)
		table.clear(order)
		commit()
	end
	el.Options, el.Values = options, options
	el._cleanup = function()
		if el.Menu then
			el.Menu.Close()
		end
	end
	return el
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
function Glass.field(parent, o)
	local h = o.Height or S.Control
	local radius = o.Multiline and 12 or h / 2
	local g = Glass.new({ Kind = "Control", Name = "Field", Parent = parent, Radius = radius, Size = o.Size or UDim2.new(1, 0, 0, h), Position = o.Position, AnchorPoint = o.AnchorPoint, Shadow = false, ZIndex = 8 })
	local tx = o.Multiline and 12 or math.max(radius - 2, 10)
	local stroke = new("UIStroke", { Thickness = 1.5, Transparency = 1, Parent = g.Fill })
	Theme.bind(stroke, { Color = "Accent" })
	local box = new("TextBox", {
		BackgroundTransparency = 1,
		Text = o.Text or "",
		PlaceholderText = o.Placeholder or "",
		ClearTextOnFocus = o.ClearOnFocus or false,
		MultiLine = o.Multiline or false,
		TextWrapped = o.Multiline or false,
		FontFace = o.Font or Util.font(Enum.FontWeight.Regular),
		TextSize = o.TextSize or S.Callout,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = o.Multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		ClipsDescendants = true,
		Size = UDim2.new(1, -2 * tx, 1, o.Multiline and -16 or 0),
		Position = UDim2.fromOffset(tx, o.Multiline and 8 or 0),
		ZIndex = 9,
		Parent = g.Content,
	})
	Theme.bind(box, { TextColor3 = "Text", PlaceholderColor3 = "Text", TextTransparency = function()
		return 0
	end })
	box.Focused:Connect(function()
		tween(stroke, 0.2, { Transparency = 0.25 })
		tween(g.Scale, 0.3, { Scale = 1.02 })
	end)
	box.FocusLost:Connect(function()
		tween(stroke, 0.3, { Transparency = 1 })
		tween(g.Scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	local last = box.Text
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if box:IsFocused() and #box.Text > #last then
			Sound.play("type")
		end
		last = box.Text
	end)
	g.Box = box
	return g
end

function Section:AddInput(a, b)
	local o = normalize(a, b)
	local multiline = opt(o, false, "Multiline", "MultiLine")
	local numeric = opt(o, false, "Numeric", "Number", "NumbersOnly")
	local maxLength = opt(o, nil, "MaxLength", "CharacterLimit")
	local finished = opt(o, nil, "Finished", "OnEnter")
	local clearAfter = opt(o, false, "RemoveTextAfterFocusLost", "ClearOnLost")
	local fieldW = opt(o, S.Field, "Width", "FieldWidth")
	local el = self:_element(o, "Input", { Right = multiline and 0 or fieldW })
	local row = el.Row
	if multiline then
		row.TopIcon()
	end
	local parent, size = row.Right, UDim2.fromScale(1, 1)
	if multiline then
		local height = opt(o, 84, "Height")
		local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height + 6), LayoutOrder = 3, ZIndex = 7, Parent = row.Body }, { Util.pad(6, 0, 0, 0) })
		parent = holder
		size = UDim2.new(1, 0, 0, height)
	end
	local field = Glass.field(parent, {
		Text = tostring(opt(o, "", "Default", "Text", "Value", "CurrentValue")),
		Placeholder = opt(o, "Type here", "Placeholder", "PlaceholderText"),
		ClearOnFocus = opt(o, false, "ClearOnFocus", "ClearTextOnFocus"),
		Multiline = multiline,
		Size = size,
	})
	el.Field, el.Box = field, field.Box
	local box = field.Box
	el:_store(box.Text)
	local changed = opt(o, nil, "Changed", "OnChanged")
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local t = box.Text
		if numeric then
			local filtered = t:gsub("[^%d%.%-]", "")
			if filtered ~= t then
				box.Text = filtered
				return
			end
		end
		if maxLength and #t > maxLength then
			box.Text = t:sub(1, maxLength)
			return
		end
		el:_store(t)
		Util.fire(changed, t)
		if finished == false then
			el:_emit(t)
		end
	end)
	box.FocusLost:Connect(function(enter)
		local t = box.Text
		if finished == false then
			return
		end
		if finished == true and not enter then
			return
		end
		el:_emit(numeric and (tonumber(t) or t) or t)
		if clearAfter then
			box.Text = ""
		end
	end)
	function el:Set(v, silent)
		box.Text = tostring(v or "")
		self:_store(box.Text)
		if not silent then
			self:_emit(box.Text)
		end
	end
	function el:Focus()
		box:CaptureFocus()
	end
	function el:SetPlaceholder(t)
		box.PlaceholderText = t
	end
	return el
end
Section.AddTextbox = Section.AddInput
Section.AddTextBox = Section.AddInput

---------------------------------------------------------------------------
-- Keybind
---------------------------------------------------------------------------
function Section:AddKeybind(a, b)
	local o = normalize(a, b)
	local mode = opt(o, "Toggle", "Mode")
	if opt(o, false, "HoldToInteract", "Hold") then
		mode = "Hold"
	end
	local el = self:_element(o, "Keybind", { Right = 120 })
	local row = el.Row
	local pill = Glass.new({ Kind = "Control", Name = "Key", Parent = row.Right, Radius = S.Control / 2, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(48, S.Control), Shadow = false, ZIndex = 8 })
	local keyLabel = Glass.text({ Parent = pill.Content, Text = "None", Weight = Enum.FontWeight.SemiBold, TextSize = S.Subhead, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 9 })
	-- the capsule hugs its label: 12 px each side, never narrower than it is tall + 18
	local function fit()
		local w = math.max(math.ceil(keyLabel.TextBounds.X / Library.ScaleObject.Scale) + 24, S.Control + 18)
		tween(pill.Root, 0.25, { Size = UDim2.fromOffset(w, S.Control) })
	end
	keyLabel:GetPropertyChangedSignal("TextBounds"):Connect(fit)
	task.defer(fit)

	local key = Util.toKey(opt(o, nil, "Default", "CurrentKeybind", "Value", "Key"))
	local listening = false
	local state = false
	local onClick, onChange = {}, opt(o, nil, "ChangedCallback", "OnChanged", "Changed")
	local function paint()
		keyLabel.Text = listening and "Press a key…" or Util.keyName(key)
		if listening then
			pill.SetTint(Theme.value("Accent"), 0.55, 0.2)
		else
			pill.BindTint({ BackgroundColor3 = "Control", BackgroundTransparency = "ControlT" })
		end
	end
	el:_store(key and key.Name or "None")
	paint()
	local function setKey(k, silent)
		key = k
		el:_store(k and k.Name or "None")
		paint()
		if not silent then
			Util.fire(onChange, k)
		end
	end
	local listenedAt = 0
	local function listen()
		if el.Disabled or listening then
			return
		end
		listenedAt = os.clock()
		listening = true
		Library._capturingKey = true
		Sound.play("click")
		paint()
	end
	row.Interactive(listen)
	local skipRelease = false
	Util.track(UserInputService.InputBegan:Connect(function(input, processed)
		if Library.Unloaded then
			return
		end
		if listening then
			local k
			if input.UserInputType == Enum.UserInputType.Keyboard then
				k = input.KeyCode
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
				k = input.UserInputType
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				-- the click that started listening is ignored; a later click elsewhere cancels
				if os.clock() - listenedAt > 0.2 then
					listening = false
					task.defer(function()
						Library._capturingKey = false
					end)
					paint()
				end
				return
			end
			if not k then
				return
			end
			listening = false
			task.defer(function()
				Library._capturingKey = false
			end)
			if k == Enum.KeyCode.Escape then
				paint()
			elseif k == Enum.KeyCode.Backspace or k == Enum.KeyCode.Delete then
				setKey(nil)
			else
				setKey(k)
			end
			Sound.play("success")
			skipRelease = true
			return
		end
		if not key or typing() then
			return
		end
		if input.KeyCode == key or input.UserInputType == key then
			if mode == "Hold" then
				state = true
				el:_emit(true)
			elseif mode == "Always" then
				el:_emit(true)
			else
				state = not state
				el:_emit(state)
			end
			for _, fn in ipairs(onClick) do
				Util.fire(fn, state)
			end
		end
	end))
	Util.track(UserInputService.InputEnded:Connect(function(input)
		if skipRelease then
			skipRelease = false
			return
		end
		if mode == "Hold" and key and state and (input.KeyCode == key or input.UserInputType == key) then
			state = false
			el:_emit(false)
		end
	end))
	function el:Set(k, silent)
		setKey(Util.toKey(k), silent)
	end
	function el:GetState()
		if mode == "Hold" and key then
			if key.EnumType == Enum.UserInputType then
				return UserInputService:IsMouseButtonPressed(key)
			end
			return UserInputService:IsKeyDown(key)
		end
		return state
	end
	function el:OnClick(fn)
		table.insert(onClick, fn)
	end
	function el:SetMode(m)
		mode = m
	end
	el.Mode = mode
	return el
end
Section.AddBind = Section.AddKeybind

---------------------------------------------------------------------------
-- Color picker
---------------------------------------------------------------------------
function Section:AddColorPicker(a, b)
	local o = normalize(a, b)
	local color = opt(o, Color3.fromRGB(10, 132, 255), "Default", "Color", "Value")
	if type(color) == "string" then
		color = Util.fromHex(color) or WHITE
	end
	local alpha = opt(o, nil, "Transparency", "Alpha")
	local SW = S.Badge
	local el = self:_element(o, "ColorPicker", { Right = 100 })
	local row = el.Row
	local hex = Glass.text({ Parent = row.Right, Text = Util.toHex(color), Level = 2, TextSize = S.Subhead, Font = MONO, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(1, -(SW + 10), 1, 0), ZIndex = 8 })
	local swatchHolder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(SW, SW), ZIndex = 8, Parent = row.Right }, { Util.corner(SW / 2) })
	local checker = Assets.get("checker.png")
	if checker then
		new("ImageLabel", { BackgroundTransparency = 1, Image = checker, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(12, 12), Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = swatchHolder }, { Util.corner(SW / 2) })
	end
	local swatch = new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = swatchHolder }, { Util.corner(SW / 2) })
	local rimId, slice, sc = rimFor(SW / 2)
	if rimId then
		new("ImageLabel", { BackgroundTransparency = 1, Image = rimId, ScaleType = Enum.ScaleType.Slice, SliceCenter = slice, SliceScale = sc, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = swatchHolder })
	end
	local function show()
		swatch.BackgroundColor3 = color
		swatch.BackgroundTransparency = alpha or 0
		hex.Text = Util.toHex(color)
	end
	show()
	el:_store(color)
	el.Transparency = alpha
	local function set(c, t, silent)
		color = c
		alpha = t
		el:_store(c)
		el.Transparency = t
		show()
		if not silent then
			el:_emit(c, t)
		end
	end
	row.Interactive(function()
		if el.Picker then
			el.Picker.Close()
			return
		end
		Sound.play("popup")
		el.Picker = Overlay.colorPicker({
			Anchor = row.Frame,
			Color = color,
			Transparency = alpha,
			OnChange = function(c, t)
				set(c, t)
			end,
			OnClose = function()
				el.Picker = nil
			end,
		})
	end)
	function el:Set(c, t, silent)
		if type(c) == "string" then
			c = Util.fromHex(c) or color
		end
		set(c or color, t == nil and alpha or t, silent)
	end
	function el:SetValueRGB(c)
		self:Set(c)
	end
	el._cleanup = function()
		if el.Picker then
			el.Picker.Close()
		end
	end
	return el
end
Section.AddColorpicker = Section.AddColorPicker

---------------------------------------------------------------------------
-- Text: Label, Paragraph, Code
---------------------------------------------------------------------------
function Section:AddLabel(a, b, c)
	local o = type(a) == "table" and a or { Title = a, Icon = b, Color = c }
	local el = self:_element(o, "Label")
	-- labels default to regular weight; explicit styling options win
	el.Row.Title.FontFace = Font.new(el.Row.Title.FontFace.Family, Enum.FontWeight.Regular)
	el:_style(o)
	local color = opt(o, nil, "Color", "TextColor")
	if typeof(color) == "Color3" or type(color) == "string" then
		Theme.bind(el.Row.Title, { TextColor3 = color })
	end
	function el:Set(t)
		self:SetTitle(t)
		self:_store(t)
	end
	el:_store(el.TitleText)
	return el
end

function Section:AddParagraph(a, b)
	local o = type(a) == "table" and a or { Title = a, Content = b }
	o.Description = o.Description or o.Content or o.Desc
	local el = self:_element(o, "Paragraph", { PadY = S.RowPadY + 2 })
	el.Row.Title.FontFace = Font.new(el.Row.Title.FontFace.Family, Enum.FontWeight.SemiBold)
	el:_style(o)
	function el:Set(v)
		if type(v) == "table" then
			if v.Title then
				self:SetTitle(v.Title)
			end
			self:SetDescription(v.Content or v.Description)
		else
			self:SetDescription(v)
		end
	end
	function el:SetContent(t)
		self:SetDescription(t)
	end
	return el
end

function Section:AddCode(a, b)
	local o = type(a) == "table" and a or { Title = a, Code = b }
	local code = tostring(opt(o, "", "Code", "Content", "Text"))
	o.Text = nil
	local el = self:_element(o, "Code", { PadY = S.RowPadY + 2 })
	el.Row.TopIcon()
	local block = new("Frame", { Name = "Code", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 7, Parent = el.Row.Body }, { Util.corner(12), Util.pad(12, 12 + S.Control, 12, 12) })
	Theme.bind(block, { BackgroundColor3 = "Field", BackgroundTransparency = "FieldT" })
	local text = Glass.text({ Parent = block, Text = code, Font = MONO, TextSize = S.Subhead, Wrap = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), ZIndex = 8 })
	text.TextYAlignment = Enum.TextYAlignment.Top
	-- the copy button sits in the block's top-right corner, 6 px from both edges
	Glass.iconButton({ Parent = block, Icon = "copy", Size = S.Control - 4, IconSize = 13, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 12 + S.Control - 6, 0, -6), ZIndex = 9, Callback = function()
		local ok = pcall(function()
			(setclipboard or toclipboard or set_clipboard)(code)
		end)
		Library:Notify({ Title = ok and "Copied" or "Copy failed", Content = ok and "Code copied to clipboard." or "This executor has no clipboard access.", Type = ok and "Success" or "Error", Duration = 2.5 })
	end })
	function el:Set(t)
		code = tostring(t)
		text.Text = code
	end
	return el
end

---------------------------------------------------------------------------
-- Image
---------------------------------------------------------------------------
function Section:AddImage(a, b)
	local o = type(a) == "table" and a or { Image = a, Title = b }
	local src = opt(o, nil, "Image", "Source", "Src", "Url", "Id", "Asset")
	local height = opt(o, 170, "Height")
	local caption = opt(o, nil, "Caption", "Title", "Name")
	local IN = 8
	local IR = S.CardRadius - IN
	local el = self:_element({ Title = "", Description = caption, Flag = o.Flag, Callback = o.Callback, Tooltip = o.Tooltip }, "Image", { Icon = false, PadY = IN, MinHeight = 0, Inset = IN })
	local row = el.Row
	row.Title.Visible = false
	row.Separator.Position = UDim2.new(0, 0, 1, 0)
	row.Separator.Size = UDim2.new(1, 0, 0, 1)
	row.Desc.LayoutOrder = 5
	-- the caption lines up with the text of the rows around it
	new("UIPadding", { PaddingLeft = UDim.new(0, S.RowInset - IN), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 2), Parent = row.Desc })
	local frame = new("Frame", { Name = "Image", BorderSizePixel = 0, BackgroundTransparency = 0.9, BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, height), LayoutOrder = 1, ZIndex = 7, Parent = row.Body }, { Util.corner(IR) })
	local img = new("ImageLabel", { BackgroundTransparency = 1, ScaleType = Enum.ScaleType[opt(o, "Crop", "ScaleType", "Fit")] or Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = frame }, { Util.corner(IR) })
	local rimId, slice, sc = rimFor(IR)
	if rimId then
		new("ImageLabel", { BackgroundTransparency = 1, Image = rimId, ScaleType = Enum.ScaleType.Slice, SliceCenter = slice, SliceScale = sc, ImageTransparency = 0.35, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = frame })
	end
	local aspect = opt(o, nil, "AspectRatio", "Aspect")
	if aspect then
		local function fit()
			local w = frame.AbsoluteSize.X / Library.ScaleObject.Scale
			frame.Size = UDim2.new(1, 0, 0, math.floor(w / aspect))
		end
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		task.defer(fit)
	end
	Assets.apply(img, src)
	local function iconMode(on)
		-- glyphs are drawn small and centered in the text color; pictures fill the frame
		if on then
			img.ScaleType = Enum.ScaleType.Fit
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromScale(0.5, 0.5)
			Theme.bind(img, { ImageColor3 = "Text" })
		else
			Theme.unbind(img, "ImageColor3")
			img.ImageColor3 = WHITE
			img.AnchorPoint = Vector2.zero
			img.Position = UDim2.new()
			img.Size = UDim2.fromScale(1, 1)
		end
	end
	iconMode(Assets.isIcon(src))
	el.ImageLabel = img
	if el.Callback then
		row.Interactive(function()
			Sound.play("click")
			el:_emit()
		end)
	end
	function el:Set(s)
		iconMode(Assets.isIcon(s))
		Assets.apply(img, s)
		self:_store(s)
	end
	function el:SetHeight(h)
		frame.Size = UDim2.new(1, 0, 0, h)
	end
	el:_store(src)
	return el
end

---------------------------------------------------------------------------
-- Segmented control (drag the glass lens across the options)
---------------------------------------------------------------------------
function Section:AddSegmented(a, b)
	local o = normalize(a, b)
	local options = opt(o, { "One", "Two" }, "Options", "Values", "Items")
	local titled = (opt(o, "", "Title", "Name", "Text")) ~= ""
	-- untitled: the control alone fills a standard row, aligned with the text inset
	local inset = (S.RowMin - S.Segmented) / 2
	local el = self:_element(o, "Segmented", titled and { PadY = S.RowPadY + 2, MinHeight = 0 } or { PadY = inset, MinHeight = 0, Icon = false })
	local row = el.Row
	if titled then
		row.TopIcon()
	end
	local holder = new("Frame", { Name = "Segmented", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, S.Segmented), LayoutOrder = 3, ZIndex = 7, Parent = row.Body })
	if titled then
		new("UIPadding", { PaddingTop = UDim.new(0, 6), Parent = holder })
		holder.Size = UDim2.new(1, 0, 0, S.Segmented + 6)
	end
	local PILL = 3
	local trackG = Glass.new({ Kind = "Control", Parent = holder, Radius = S.Segmented / 2, Size = UDim2.new(1, 0, 0, S.Segmented), Shadow = false, ZIndex = 7 })
	local count = #options
	local pill = Glass.new({ Kind = "Control", Name = "Selection", Parent = trackG.Content, Radius = S.Segmented / 2 - PILL, Size = UDim2.new(1 / count, -2 * PILL, 1, -2 * PILL), Position = UDim2.fromOffset(PILL, PILL), Shadow = 0.25, SmallShadow = true, ZIndex = 8 })
	pill.SetTint(WHITE, 0.72)
	local labels = {}
	for i, name in ipairs(options) do
		labels[i] = Glass.text({ Parent = trackG.Content, Text = tostring(name), Weight = Enum.FontWeight.SemiBold, TextSize = S.Callout, XAlign = Enum.TextXAlignment.Center, Truncate = true, Position = UDim2.fromScale((i - 1) / count, 0), Size = UDim2.fromScale(1 / count, 1), ZIndex = 10 })
	end
	local initial = opt(o, options[1], "Default", "Value", "CurrentOption")
	local index = table.find(options, initial) or (type(initial) == "number" and initial) or 1
	local function segW()
		return trackG.Root.AbsoluteSize.X / Library.ScaleObject.Scale / count
	end
	local hit = hitbox(trackG.Content, 20)
	local sel = Glass.selector({
		Hit = hit,
		Ref = trackG.Root,
		Pill = pill,
		Axis = "X",
		Initial = index,
		Count = function()
			return count
		end,
		Slot = function(i)
			return Vector2.new((i - 1) * segW() + PILL, PILL)
		end,
		Items = function()
			return labels
		end,
		Magnify = 1.12,
		LensScale = 1.14,
		Disabled = function()
			return el.Disabled
		end,
		Paint = function(i)
			for j, l in ipairs(labels) do
				Theme.bind(l, { TextTransparency = function(t)
					return j == i and 0 or t.Text2T
				end })
			end
		end,
		OnSelect = function(i, changed)
			if changed then
				el:_store(options[i])
				el:_emit(options[i])
			end
		end,
	})
	-- keep the pill on its slot while the control resizes
	trackG.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		pill.Root.Size = UDim2.new(1 / count, -2 * PILL, 1, -2 * PILL)
		sel.set(sel.get(), true)
	end)
	task.defer(function()
		sel.set(index, true)
	end)
	el:_store(options[index])
	function el:Set(v, silent)
		local i = table.find(options, v) or (type(v) == "number" and v)
		if not i then
			return
		end
		sel.set(i)
		self:_store(options[i])
		if not silent then
			self:_emit(options[i])
		end
	end
	return el
end
Section.AddSegment = Section.AddSegmented

---------------------------------------------------------------------------
-- Progress, Stepper
---------------------------------------------------------------------------
function Section:AddProgress(a, b)
	local o = type(a) == "table" and a or { Title = a, Default = b }
	local max = opt(o, 1, "Max", "Maximum")
	local suffix = opt(o, nil, "Suffix")
	local el = self:_element(o, "Progress", { PadY = S.RowPadY + 2 })
	local row = el.Row
	row.TopIcon()
	new("UIPadding", { PaddingRight = UDim.new(0, 80), Parent = row.Title })
	local pct = Glass.text({ Parent = row.Frame, Text = "", Level = 2, TextSize = S.Body, XAlign = Enum.TextXAlignment.Right, YAlign = Enum.TextYAlignment.Top, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -S.RowInset, 0, S.RowPadY + 2), Size = UDim2.fromOffset(80, 19), ZIndex = 8 })
	local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3, ZIndex = 7, Parent = row.Body })
	local bar = new("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 6), ZIndex = 7, Parent = holder }, { Util.corner(3) })
	Theme.bind(bar, { BackgroundColor3 = "Track", BackgroundTransparency = "TrackT" })
	local fill = new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 8, Parent = bar }, { Util.corner(3) })
	Theme.bind(fill, { BackgroundColor3 = "Accent" })
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(215, 235, 255), WHITE), Rotation = 0, Parent = fill })
	local function set(v)
		v = math.clamp(tonumber(v) or 0, 0, max)
		el:_store(v)
		tween(fill, 0.45, { Size = UDim2.fromScale(v / max, 1) })
		pct.Text = suffix and (Util.format(v, Util.decimals(v)) .. suffix) or (math.floor(v / max * 100 + 0.5) .. "%")
	end
	set(opt(o, 0, "Default", "Value"))
	function el:Set(v)
		set(v)
	end
	return el
end
Section.AddProgressBar = Section.AddProgress

function Section:AddStepper(a, b)
	local o = normalize(a, b)
	local min, max = opt(o, 0, "Min"), opt(o, 10, "Max")
	local step = opt(o, 1, "Step", "Increment")
	local decimals = Util.decimals(step)
	local W = 104
	local el = self:_element(o, "Stepper", { Right = W })
	local row = el.Row
	local g = Glass.new({ Kind = "Control", Parent = row.Right, Radius = S.Control / 2, Size = UDim2.fromOffset(W, S.Control), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Shadow = false, ZIndex = 8 })
	local valueLabel = Glass.text({ Parent = g.Content, Text = "", Weight = Enum.FontWeight.SemiBold, TextSize = S.Body, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 9 })
	local value
	local function set(v, silent)
		v = math.clamp(Util.snap(v, min, step), min, max)
		local changed = v ~= value
		value = v
		el:_store(v)
		valueLabel.Text = Util.format(v, decimals)
		if changed and not silent then
			el:_emit(v)
		end
	end
	set(opt(o, min, "Default", "Value"), true)
	for i, d in ipairs({ -1, 1 }) do
		local bt = new("TextButton", { BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Position = i == 1 and UDim2.new() or UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(i == 1 and 0 or 1, 0), Size = UDim2.new(0, S.Control + 4, 1, 0), ZIndex = 10, Parent = g.Content })
		local ic = Glass.icon({ Parent = bt, Icon = d < 0 and "minus" or "plus", Size = 12, ZIndex = 10 })
		bt.Activated:Connect(function()
			if el.Disabled then
				return
			end
			set(value + d * step)
			Sound.play("tick")
			ic.Size = UDim2.fromOffset(9, 9)
			tween(ic, 0.35, { Size = UDim2.fromOffset(12, 12) }, Enum.EasingStyle.Back)
		end)
	end
	function el:Set(v, silent)
		set(tonumber(v) or value, silent)
	end
	return el
end

---------------------------------------------------------------------------
-- Layout helpers and custom content
---------------------------------------------------------------------------
function Section:AddDivider()
	local el = self:_element({ Title = "" }, "Divider", { MinHeight = 16, PadY = 0, Title = "" })
	el.Row.Body.Visible = false
	el.Row.Separator.AnchorPoint = Vector2.new(0, 0.5)
	el.Row.Separator.Position = UDim2.new(0, S.RowInset, 0.5, 0)
	el.Row.Separator.Size = UDim2.new(1, -2 * S.RowInset, 0, 1)
	el.NoSeparator = true
	self:_refresh()
	return el
end

function Section:AddSpacer(h)
	local el = self:_element({ Title = "" }, "Spacer", { MinHeight = h or 12, PadY = 0, Title = "" })
	el.Row.Body.Visible = false
	el.NoSeparator = true
	self:_refresh()
	return el
end

-- anything else: Build(container, element) receives a frame inside the card
function Section:AddCustom(a, b)
	local o = type(a) == "function" and { Build = a } or (a or {})
	local build = b or opt(o, nil, "Build", "Callback", "Create")
	o.Callback = nil
	local el = self:_element(o, "Custom", { PadY = opt(o, S.RowPadY + 2, "Padding"), MinHeight = opt(o, 0, "MinHeight") })
	el.Row.TopIcon()
	local container = new("Frame", { Name = "Custom", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, opt(o, 0, "Height")), AutomaticSize = opt(o, nil, "Height") and Enum.AutomaticSize.None or Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 7, Parent = el.Row.Body })
	if el.TitleText == "" then
		el.Row.Title.Visible = false
	end
	el.Container = container
	if build then
		local ok, err = pcall(build, container, el, Library)
		if not ok then
			warn("[LiquidGlass] custom element: " .. tostring(err))
		end
	end
	return el
end

---------------------------------------------------------------------------
-- Tabs forward every element constructor to their current section
---------------------------------------------------------------------------
local ALIASES = {
	CreateButton = "AddButton", CreateToggle = "AddToggle", CreateSlider = "AddSlider",
	CreateDropdown = "AddDropdown", CreateInput = "AddInput", CreateKeybind = "AddKeybind",
	CreateColorPicker = "AddColorPicker", CreateLabel = "AddLabel", CreateParagraph = "AddParagraph",
	CreateDivider = "AddDivider", CreateImage = "AddImage", AddCheckbox = "AddToggle", AddSwitch = "AddToggle",
	AddList = "AddDropdown", AddSelect = "AddDropdown", AddTextLabel = "AddLabel", AddText = "AddLabel",
	AddSeparator = "AddDivider", AddPicture = "AddImage", AddProgressbar = "AddProgress",
}
for alias, target in pairs(ALIASES) do
	Section[alias] = Section[target]
end
for name, fn in pairs(Section) do
	if type(fn) == "function" and (name:sub(1, 3) == "Add" or name:sub(1, 6) == "Create") and not Tab[name] and name ~= "AddSection" then
		Tab[name] = function(self, ...)
			local s = self:_section()
			return fn(s, ...)
		end
	end
end
