---------------------------------------------------------------------------
-- Glass surfaces
--   Surface  floating glass over the world: blur + dim + tint + rim + shadow
--   Card     grouped glass on glass (sections, sidebars)
--   Control  small glass controls (fields, glass buttons, pills)
--   Tinted   colored glass (primary buttons, active toggles)
--   Solid    opaque white glass (switch and slider knobs)
---------------------------------------------------------------------------
local RIM_MIN, RIM_MAX = 4, 40
local SHADOW_STEP, SHADOW_MAX, SHADOW_SM_MAX = 4, 40, 24
local SHADOW_PAD, SHADOW_SM_PAD = 48, 12

-- keep in sync with RIM_SIZES in build.py
local RIM_SIZES = { 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 26, 28, 30, 33, 36, 40 }
local function rimFor(r)
	local want = math.clamp(r, RIM_MIN, RIM_MAX)
	local rt = RIM_SIZES[1]
	for _, size in ipairs(RIM_SIZES) do
		if math.abs(size - want) < math.abs(rt - want) then
			rt = size
		end
	end
	local id = Assets.get(("rim_%d.png"):format(rt))
	return id, Rect.new(2 * rt, 2 * rt, 2 * rt + 8, 2 * rt + 8), 0.5 * math.max(r, 1) / rt
end

local function shadowFor(r, small)
	local maxR = small and SHADOW_SM_MAX or SHADOW_MAX
	local rt = math.clamp(math.floor(r / SHADOW_STEP + 0.5) * SHADOW_STEP, SHADOW_STEP, maxR)
	local pad = small and SHADOW_SM_PAD or SHADOW_PAD
	local id = Assets.get(((small and "shadowsm_%d.png") or "shadow_%d.png"):format(rt))
	local scale = math.max(r, 1) / rt
	return id, Rect.new(pad + rt, pad + rt, pad + rt + 4, pad + rt + 4), scale, pad * scale
end
Glass.rimFor = rimFor

local KIND = {
	Surface = { fill = "Glass", fillT = "GlassT", rim = "Rim", gradient = true, dim = true, shadow = 0.36 },
	Card = { fill = "Card", fillT = "CardT", rim = "CardRim" },
	Control = { fill = "Control", fillT = "ControlT", rim = "ControlRim" },
	Tinted = { fill = "Accent", fillT = function()
		return 0.06
	end, rim = function()
		return 0.65
	end, gradient = true },
	Solid = { fill = "Knob", fillT = function()
		return 0
	end, rim = function()
		return 0
	end, shadow = 0.28, small = true },
}

-- o: Kind, Parent, Name, Position, Size, AnchorPoint, ZIndex, Radius, Tint (Color3 or
-- theme token), TintTransparency, Blur (Surface default true), BlurDepth, Shadow
-- (strength or false), SmallShadow, Rim (strength 0..1), AutomaticSize
function Glass.new(o)
	local kind = KIND[o.Kind or "Card"]
	local r = o.Radius or 16
	local root = new("Frame", {
		Name = o.Name or (o.Kind or "Glass"),
		BackgroundTransparency = 1,
		Position = o.Position or UDim2.new(),
		Size = o.Size or UDim2.fromScale(1, 1),
		AnchorPoint = o.AnchorPoint or Vector2.zero,
		ZIndex = o.ZIndex or 1,
		LayoutOrder = o.LayoutOrder or 0,
		Parent = o.Parent,
	})
	local g = { Root = root, Radius = r, Kind = o.Kind or "Card" }
	g.Scale = new("UIScale", { Parent = root })

	local shadowStrength = o.Shadow
	if shadowStrength == nil then
		shadowStrength = kind.shadow
	end
	if shadowStrength then
		local small = o.SmallShadow or kind.small
		local id, slice, scale, pad = shadowFor(r, small)
		if id then
			local holder = new("Frame", { Name = "ShadowHolder", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0, Parent = root })
			g.Shadow = new("ImageLabel", {
				Name = "Shadow",
				BackgroundTransparency = 1,
				Image = id,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = slice,
				SliceScale = scale,
				Position = UDim2.fromOffset(-pad, -pad),
				Size = UDim2.new(1, pad * 2, 1, pad * 2),
				ZIndex = 0,
				Parent = holder,
			})
			if o.Kind == "Surface" then
				Theme.bind(g.Shadow, { ImageTransparency = function(t)
					return 1 - (t.Shadow or 0.3)
				end })
			else
				g.Shadow.ImageTransparency = 1 - shadowStrength
			end
		end
	end

	if kind.dim then
		g.Dim = new("Frame", {
			Name = "Dim",
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = root,
		}, { Util.corner(r) })
		-- overlays sit above other LiquidGlass UI, which the world blur can't soften,
		-- so their glass is much denser
		Theme.bind(g.Dim, { BackgroundColor3 = "Dim", BackgroundTransparency = o.Dense and "DenseDimT" or "DimT" })
	end

	g.Fill = new("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = root,
	}, { Util.corner(r) })
	local tint = o.Tint or kind.fill
	local tintT = o.TintTransparency or kind.fillT
	if typeof(tint) == "Color3" then
		g.Fill.BackgroundColor3 = tint
		Theme.bind(g.Fill, { BackgroundTransparency = tintT })
	else
		Theme.bind(g.Fill, { BackgroundColor3 = tint, BackgroundTransparency = tintT })
	end
	if typeof(o.TintTransparency) == "number" then
		Theme.unbind(g.Fill, "BackgroundTransparency")
		g.Fill.BackgroundTransparency = o.TintTransparency
	end
	if kind.gradient and o.Gradient ~= false then
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.45, 0.35),
				NumberSequenceKeypoint.new(1, 0.15),
			}),
			Parent = g.Fill,
		})
	end

	local rimId, slice, sliceScale = rimFor(r)
	if rimId then
		g.Rim = new("ImageLabel", {
			Name = "Rim",
			BackgroundTransparency = 1,
			Image = rimId,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = slice,
			SliceScale = sliceScale,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = root,
		})
		if o.Rim then
			g.Rim.ImageTransparency = 1 - o.Rim
		else
			local rimToken = kind.rim
			Theme.bind(g.Rim, { ImageTransparency = function(t)
				local v = type(rimToken) == "function" and rimToken(t) or t[rimToken] or 1
				return 1 - v
			end })
		end
	else
		-- no texture support: a plain hairline keeps the shape readable
		g.Rim = new("UIStroke", { Color = WHITE, Transparency = 0.75, Thickness = 1, Parent = g.Fill })
	end

	local auto = o.AutomaticSize
	if auto == Enum.AutomaticSize.None then
		auto = nil
	end
	g.Content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = (auto == Enum.AutomaticSize.XY and UDim2.new()) or (auto == Enum.AutomaticSize.X and UDim2.fromScale(0, 1)) or (auto and UDim2.fromScale(1, 0)) or UDim2.fromScale(1, 1),
		AutomaticSize = auto or Enum.AutomaticSize.None,
		ZIndex = 5,
		Parent = root,
	})
	if auto then
		-- Roblox AutomaticSize misbehaves with scale-sized layers (fill, rim, shadow),
		-- so the root follows its content's measured size instead
		local function sync()
			local sc = g.Scale.Scale * (Library.ScaleObject and Library.ScaleObject.Scale or 1)
			if sc <= 0.01 then
				return
			end
			local cs = g.Content.AbsoluteSize / sc
			local size = root.Size
			if auto == Enum.AutomaticSize.XY then
				root.Size = UDim2.fromOffset(math.ceil(cs.X), math.ceil(cs.Y))
			elseif auto == Enum.AutomaticSize.X then
				root.Size = UDim2.new(0, math.ceil(cs.X), size.Y.Scale, size.Y.Offset)
			else
				root.Size = UDim2.new(size.X.Scale, size.X.Offset, 0, math.ceil(cs.Y))
			end
		end
		g.Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
		g.Scale:GetPropertyChangedSignal("Scale"):Connect(sync)
		task.defer(sync)
		g.SyncSize = sync
	end

	local blur = o.Blur
	if blur == nil then
		blur = o.Kind == "Surface"
	end
	if blur then
		g.BlurRegion = Blur.add(g.Fill, function()
			return r * g.Scale.Scale * (Library.ScaleObject and Library.ScaleObject.Scale or 1)
		end, { Depth = o.BlurDepth, Start = o.BlurStart })
	end

	function g.SetTint(color, transparency, time)
		Theme.unbind(g.Fill, "BackgroundColor3")
		if transparency then
			Theme.unbind(g.Fill, "BackgroundTransparency")
		end
		local props = { BackgroundColor3 = color }
		if transparency then
			props.BackgroundTransparency = transparency
		end
		if time then
			tween(g.Fill, time, props)
		else
			for k, v in pairs(props) do
				g.Fill[k] = v
			end
		end
	end

	function g.BindTint(map)
		Theme.bind(g.Fill, map)
	end
	return g
end

---------------------------------------------------------------------------
-- Interaction helpers
---------------------------------------------------------------------------
function Glass.hitbox(parent, z, props)
	local b = new("TextButton", {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z or 20,
		Parent = parent,
	})
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	return b
end
local hitbox = Glass.hitbox

-- light that follows the pointer inside a glass shape, clipped to its corners
function Glass.glow(g, strength)
	local clip = new("CanvasGroup", {
		Name = "PointerLight",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1,
		ZIndex = 4,
		Parent = g.Root,
	}, { Util.corner(g.Radius) })
	local light = new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Assets.get("radial.png") or "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(1.5, 1.5),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ImageTransparency = 1 - (strength or 0.45),
		Parent = clip,
	})
	local ctl = {}
	function ctl.follow()
		local rel = (pointer() - screenPos(g.Root)) / math.max(g.Scale.Scale, 0.01)
		light.Position = UDim2.fromOffset(rel.X, rel.Y)
	end
	function ctl.set(level, time)
		tween(clip, time or 0.3, { GroupTransparency = 1 - level })
	end
	return ctl
end

-- glass that swells on press, glows under the pointer and clicks
-- opts: Grow, OnClick, Sound ("click" default, false = silent), Disabled() -> bool, Glow
function Glass.pressable(g, opts)
	opts = opts or {}
	local hit = hitbox(g.Root, opts.Z or 20)
	local grow = opts.Grow or 1.05
	local glow = opts.Glow ~= false and Glass.glow(g, opts.GlowStrength) or nil
	local hovered, pressed = false, false
	local function disabled()
		return opts.Disabled and opts.Disabled()
	end
	hit.MouseEnter:Connect(function()
		if disabled() then
			return
		end
		hovered = true
		if glow then
			glow.follow()
			glow.set(0.5)
		end
		Sound.play("hover")
	end)
	hit.MouseMoved:Connect(function()
		if glow and hovered then
			glow.follow()
		end
	end)
	hit.MouseLeave:Connect(function()
		hovered = false
		if glow and not pressed then
			glow.set(0, 0.4)
		end
	end)
	hit.InputBegan:Connect(function(input)
		if not isPress(input) or disabled() then
			return
		end
		pressed = true
		tween(g.Scale, 0.35, { Scale = grow }, Enum.EasingStyle.Quint)
		if glow then
			glow.follow()
			glow.set(1, 0.15)
		end
	end)
	Util.track(UserInputService.InputEnded:Connect(function(input)
		if pressed and isPress(input) then
			pressed = false
			tween(g.Scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
			if glow then
				glow.set(hovered and 0.5 or 0, 0.5)
			end
		end
	end))
	hit.Activated:Connect(function()
		if disabled() then
			return
		end
		if opts.Sound ~= false then
			Sound.play(opts.Sound or "click")
		end
		Util.fire(opts.OnClick)
	end)
	return hit
end

-- small round glass icon button (window controls, field accessories)
function Glass.iconButton(o)
	local size = o.Size or 30
	local g = Glass.new({
		Kind = o.Kind or "Control",
		Parent = o.Parent,
		Name = o.Name,
		Radius = size / 2,
		Size = UDim2.fromOffset(size, size),
		Position = o.Position,
		AnchorPoint = o.AnchorPoint,
		ZIndex = o.ZIndex,
		Shadow = false,
		Tint = o.Tint,
	})
	local img = new("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(o.IconSize or math.floor(size * 0.46), o.IconSize or math.floor(size * 0.46)),
		ZIndex = 6,
		Parent = g.Content,
	})
	Assets.apply(img, o.Icon)
	Theme.bind(img, { ImageColor3 = o.IconColor or "Text" })
	g.Icon = img
	g.Hit = Glass.pressable(g, { Grow = o.Grow or 1.12, OnClick = o.Callback, Sound = o.Sound })
	return g
end

-- themed text
function Glass.text(o)
	local l = new(o.Class or "TextLabel", {
		Name = o.Name or "Text",
		BackgroundTransparency = 1,
		Text = o.Text or "",
		FontFace = o.Font or Util.font(o.Weight),
		TextSize = o.TextSize or 15,
		TextXAlignment = o.XAlign or Enum.TextXAlignment.Left,
		TextYAlignment = o.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = o.Wrap or false,
		TextTruncate = o.Truncate and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
		RichText = o.Rich or false,
		Position = o.Position or UDim2.new(),
		Size = o.Size or UDim2.new(1, 0, 0, o.TextSize and o.TextSize + 4 or 19),
		AnchorPoint = o.AnchorPoint or Vector2.zero,
		AutomaticSize = o.AutomaticSize or Enum.AutomaticSize.None,
		ZIndex = o.ZIndex or 6,
		LayoutOrder = o.LayoutOrder or 0,
		Parent = o.Parent,
	})
	if l:IsA("TextButton") then
		l.AutoButtonColor = false
	end
	local level = o.Level or 1
	Theme.bind(l, {
		TextColor3 = o.Color or "Text",
		TextTransparency = function(t)
			return level == 1 and 0 or level == 2 and t.Text2T or t.Text3T
		end,
	})
	return l
end

function Glass.icon(o)
	local img = new("ImageLabel", {
		Name = o.Name or "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(o.Size or 18, o.Size or 18),
		Position = o.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = o.AnchorPoint or Vector2.new(0.5, 0.5),
		ScaleType = o.ScaleType or Enum.ScaleType.Fit,
		ZIndex = o.ZIndex or 6,
		LayoutOrder = o.LayoutOrder or 0,
		Parent = o.Parent,
	})
	local level = o.Level or 1
	local _, r = Assets.apply(img, o.Icon)
	-- only glyphs follow the text color; pictures keep their own colors
	if o.Color ~= false and ((r and r.Icon) or o.Color) then
		Theme.bind(img, {
			ImageColor3 = o.Color or "Text",
			ImageTransparency = function(t)
				return level == 1 and 0 or level == 2 and t.Text2T or t.Text3T
			end,
		})
	end
	return img
end
