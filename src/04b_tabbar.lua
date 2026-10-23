---------------------------------------------------------------------------
-- Tab bar navigation (CreateWindow({ Navigation = "TabBar", TabBar = {...} })):
-- an iOS 26 style glass tab bar instead of the sidebar. It docks inside the
-- window on any edge, or floats next to it (trailing the window like liquid).
-- Its grip moves it: tap to go to the next edge, drag to throw it to any edge
-- (or anywhere on screen when floating); it snaps with a soft bounce.
-- A floating bar stays on screen while the window is hidden, and its tabs
-- bring the window back; one pinned to the screen edge keeps the window
-- right next to it, like a dock.
---------------------------------------------------------------------------
local Bar = {}
Bar.__index = Bar
Library._classes.TabBar = Bar

local EDGES = { Bottom = true, Top = true, Left = true, Right = true }
local CYCLE = { "Bottom", "Left", "Top", "Right" }

local function isVertical(pos)
	return pos == "Left" or pos == "Right"
end

local function edgeName(v)
	if type(v) == "string" then
		local n = v:sub(1, 1):upper() .. v:sub(2):lower()
		if EDGES[n] then
			return n
		end
	end
	return nil
end

-- where a pinned bar sits along its screen edge: "Start" (left / top), "Center"
-- or "End" (right / bottom), so a corner works lying down or standing up
local function alignName(v)
	v = type(v) == "string" and v:lower() or nil
	if v == "start" or v == "left" or v == "top" then
		return "Start"
	elseif v == "end" or v == "right" or v == "bottom" then
		return "End"
	elseif v == "center" or v == "middle" then
		return "Center"
	end
	return nil
end

-- Roblox's backpack hotbar sits at the bottom middle of the screen while the
-- player has tools; a bar pinned to the bottom edge moves up above it
local StarterGui = game:GetService("StarterGui")
local hotbarAt, hotbarOn = 0, false
local function hotbarVisible()
	local now = os.clock()
	if now - hotbarAt > 0.25 then
		hotbarAt = now
		local ok, on = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
		local lp = Players.LocalPlayer
		local bp = lp and lp:FindFirstChildOfClass("Backpack")
		local tool = (bp and bp:FindFirstChildOfClass("Tool")) or (lp and lp.Character and lp.Character:FindFirstChildOfClass("Tool"))
		hotbarOn = ok and on and tool ~= nil
	end
	return hotbarOn
end

-- top-left of a bar of this size pinned to a screen edge; the top edge stays
-- clear of Roblox's top bar, the bottom middle of the backpack hotbar
local function screenSpot(edge, align, size)
	local sc = Library.ScaleObject.Scale
	local vs = camera.ViewportSize / sc
	local margin = 14
	local top = GuiService:GetGuiInset().Y / sc + 8
	local function along(lo, hi, len)
		if align == "Start" then
			return lo
		elseif align == "End" then
			return hi - len
		end
		return lo + (hi - lo - len) / 2
	end
	if edge == "Bottom" or edge == "Top" then
		local x = along(margin, vs.X - margin, size.X)
		if edge == "Top" then
			return Vector2.new(x, top)
		end
		local lift = (align == "Center" and hotbarVisible()) and 62 or 0
		return Vector2.new(x, vs.Y - size.Y - margin - lift)
	end
	local y = along(top, vs.Y - margin, size.Y)
	return Vector2.new(edge == "Left" and margin or vs.X - size.X - margin, y)
end

function Window:_buildTabBar(cfg)
	cfg = type(cfg) == "table" and cfg or {}
	local bar = setmetatable({
		Window = self,
		Position = edgeName(cfg.Position) or "Bottom",
		Floating = cfg.Floating == true or cfg.Screen == true,
		Screen = cfg.Screen == true, -- pinned to the screen edge instead of the window
		Locked = cfg.Locked == true, -- no grip, can't be moved by the user
		HideWithWindow = cfg.HideWithWindow == true, -- floating bars stay on screen otherwise
		Align = alignName(cfg.Align) or "Center",
		Labels = cfg.Labels ~= false,
		Draggable = cfg.Draggable ~= false,
		Grip = cfg.Grip,
		Cycle = cfg.Cycle or CYCLE,
		Gap = cfg.Gap or S.TabBarGap,
		OnMoved = cfg.OnMoved or cfg.Callback,
		Items = {},
		Shown = false,
	}, Bar)
	if bar.Grip == nil then
		bar.Grip = bar.Draggable
	end
	self.Bar = bar
	bar:build()
	-- a window with a pinned bar opens right next to it
	if bar.Screen and not (typeof(self.Opts.Position) == "UDim2" or typeof(self.Opts.Position) == "Vector2") then
		self.AtBar = true
		local spot = bar:windowSpot(bar:target(bar.M))
		bar.LastSpot = spot
		self.Root.Position = UDim2.fromOffset(math.floor(spot.X), math.floor(spot.Y))
	end
	Util.track(RunService.RenderStepped:Connect(function()
		bar:follow()
	end))
	return bar
end

-- sizes for the current orientation and the space available (or for another
-- edge / floating state, to preview a snap)
function Bar:metrics(pos, floating)
	local w = self.Window
	if floating == nil then
		floating = self.Floating
	end
	local vert = isVertical(pos or self.Position)
	local inset = S.TabBarInset
	local thick = vert and (S.TabBarHeight + 8) or S.TabBarHeight
	local short = thick - 2 * inset
	local labels = self.Labels
	local itemLen = vert and (S.TabBarHeight - 2 * inset) or (labels and S.TabBarItem or short)
	local n = math.max(#w.Tabs, 1)
	local grip = (self.Grip and not self.Locked) and short or 0
	local avail
	local sc = Library.ScaleObject.Scale
	if floating then
		local vs = camera.ViewportSize / sc
		avail = (vert and vs.Y or vs.X) - 40
	else
		local ws = Vector2.new(w.Root.Size.X.Offset, w.Root.Size.Y.Offset)
		avail = vert and (ws.Y - S.Header - 3 * S.WindowInset) or (ws.X - 4 * S.WindowInset)
	end
	local need = n * itemLen + grip + 2 * inset
	if need > avail then
		itemLen = math.max(36, math.floor((avail - grip - 2 * inset) / n))
		if not vert and itemLen < 58 then
			labels = false
		end
	end
	local len = n * itemLen + grip + 2 * inset
	return {
		vert = vert,
		inset = inset,
		thick = thick,
		short = short,
		itemLen = itemLen,
		labels = labels and (not vert or self.Labels),
		grip = grip,
		len = len,
		size = vert and Vector2.new(thick, len) or Vector2.new(len, thick),
		item = vert and Vector2.new(short, itemLen) or Vector2.new(itemLen, short),
	}
end

-- where the bar rests: window-local when docked, screen when floating
function Bar:target(m)
	m = m or self:metrics()
	local w = self.Window
	local size = m.size
	if self.Floating then
		local vs = camera.ViewportSize / Library.ScaleObject.Scale
		if self.Free then
			return Vector2.new(math.clamp(self.Free.X, 4, vs.X - size.X - 4), math.clamp(self.Free.Y, 4, vs.Y - size.Y - 4))
		end
		if self.Screen then
			return screenSpot(self.Position, self.Align, size)
		end
		local p = Motion.target(w.Root)
		local ws = Vector2.new(w.Root.Size.X.Offset, w.Root.Size.Y.Offset)
		local g = self.Gap
		local t
		if self.Position == "Bottom" then
			t = Vector2.new(p.X + (ws.X - size.X) / 2, p.Y + ws.Y + g)
		elseif self.Position == "Top" then
			t = Vector2.new(p.X + (ws.X - size.X) / 2, p.Y - g - size.Y)
		elseif self.Position == "Left" then
			t = Vector2.new(p.X - g - size.X, p.Y + (ws.Y - size.Y) / 2)
		else
			t = Vector2.new(p.X + ws.X + g, p.Y + (ws.Y - size.Y) / 2)
		end
		return Vector2.new(math.clamp(t.X, 4, vs.X - size.X - 4), math.clamp(t.Y, 4, vs.Y - size.Y - 4))
	end
	local ws = Vector2.new(w.Root.Size.X.Offset, w.Root.Size.Y.Offset)
	local inset = S.WindowInset
	local contentTop = inset + S.Header
	if self.Position == "Bottom" then
		return Vector2.new((ws.X - size.X) / 2, ws.Y - inset - size.Y)
	elseif self.Position == "Top" then
		return Vector2.new((ws.X - size.X) / 2, contentTop)
	elseif self.Position == "Left" then
		return Vector2.new(inset, contentTop + (ws.Y - contentTop - inset - size.Y) / 2)
	end
	return Vector2.new(ws.X - inset - size.X, contentTop + (ws.Y - contentTop - inset - size.Y) / 2)
end

function Bar:makeItem(tab)
	local item = new("Frame", { Name = "Tab_" .. tab.Title, BackgroundTransparency = 1, ZIndex = 9, Parent = self.Glass.Content })
	tab.Button = item
	tab.IconImage = Glass.icon({ Parent = item, Icon = tab.Icon or "circle", Size = 20, ZIndex = 10 })
	tab.Label = Glass.text({ Parent = item, Text = tab.Title, Weight = Enum.FontWeight.SemiBold, TextSize = S.Caption, XAlign = Enum.TextXAlignment.Center, Truncate = true, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(1, -6, 0, 13), ZIndex = 10 })
	tab:_paint(self.Window.ActiveTab == tab)
	self.Items[tab] = item
	return item
end

function Bar:build()
	local w = self.Window
	local m = self:metrics()
	self.M = m
	local floating = self.Floating
	local g = Glass.new({
		Kind = floating and "Surface" or "Card",
		Name = "TabBar",
		Parent = floating and Library.Gui or w.Body,
		Radius = m.thick / 2,
		Size = UDim2.fromOffset(m.size.X, m.size.Y),
		ZIndex = floating and nextZ(5) or 20,
		Shadow = floating and nil or 0.22,
		SmallShadow = not floating,
		BlurStart = 0,
	})
	g.Root.Active = true
	self.Glass, self.Root = g, g.Root
	table.clear(self.Items)

	-- selection pill + selector over the items
	local pill = Glass.new({ Kind = "Control", Name = "Selection", Parent = g.Content, Radius = m.short / 2, Size = UDim2.fromOffset(m.item.X, m.item.Y), Position = UDim2.fromOffset(m.inset, m.inset), Shadow = false, ZIndex = 8 })
	pill.SetTint(WHITE, Theme.current.Name == "Light" and 0.35 or 0.88)
	self.Pill = pill
	local area = new("Frame", { Name = "Items", BackgroundTransparency = 1, Position = UDim2.fromOffset(m.inset, m.inset), ZIndex = 9, Parent = g.Content })
	self.Area = area
	local hit = hitbox(area, 30)
	for _, tab in ipairs(w.Tabs) do
		self:makeItem(tab)
	end
	local bar = self
	self.Selector = Glass.selector({
		Hit = hit,
		Ref = g.Content,
		Pill = pill,
		Axis = m.vert and "Y" or "X",
		Count = function()
			return #w.Tabs
		end,
		Slot = function(i)
			local mm = bar.M
			if mm.vert then
				return Vector2.new(mm.inset, mm.inset + (i - 1) * mm.itemLen)
			end
			return Vector2.new(mm.inset + (i - 1) * mm.itemLen, mm.inset)
		end,
		Items = function()
			local t = {}
			for i, tab in ipairs(w.Tabs) do
				t[i] = tab.Button
			end
			return t
		end,
		Magnify = 1.12,
		LensScale = 1.12,
		Paint = function(i)
			for j, tab in ipairs(w.Tabs) do
				tab:_paint(j == i)
			end
		end,
		OnSelect = function(i)
			w:SelectTab(i)
			bar:summon()
		end,
	})
	w.TabSelector, w.TabPill = self.Selector, pill

	-- grip: tap -> next edge, drag -> move
	self.GripFrame = nil
	if self.Grip and not self.Locked then
		local gripFrame = new("Frame", { Name = "Grip", BackgroundTransparency = 1, ZIndex = 9, Parent = g.Content })
		self.GripFrame = gripFrame
		local gi = Glass.icon({ Parent = gripFrame, Icon = "move", Size = 16, Level = 2, ZIndex = 10 })
		self.GripIcon = gi
		local ghit = hitbox(gripFrame, 31)
		local startPos, startPointer
		Motion.drag(ghit, {
			allow = function()
				return bar.Draggable and not bar.Locked
			end,
			began = function(p)
				startPos = Motion.target(g.Root)
				startPointer = p
				tween(g.Scale, 0.3, { Scale = 1.06 })
				tween(gi, 0.2, { ImageTransparency = 0 })
			end,
			moved = function(p, d, moved)
				if moved then
					bar.Dragging = true
					local sc = Library.ScaleObject.Scale
					-- a docked bar moves in window space; snapping works in screen space
					local off = bar.Floating and Vector2.zero or screenPos(w.Root) / sc
					local at = startPos + d / sc + off
					-- the screen edges push back softly instead of swallowing the bar
					local vs = camera.ViewportSize / sc
					local size = bar.M.size
					at = Vector2.new(Motion.rubber(at.X, 0, vs.X - size.X, 40), Motion.rubber(at.Y, 0, vs.Y - size.Y, 40))
					local slot = bar:snapSlot(p, at)
					bar.DragAt = at
					bar:showGhost(slot)
					local turning = slot ~= nil and isVertical(slot.Edge) ~= bar.M.vert
					if slot and not turning then
						-- magnetic: the bar leans into the slot it is about to snap to
						at = at:Lerp(slot.Pos, 0.3)
					end
					if turning ~= bar.Turning then
						-- about to stand up or lie down: it shrinks a little toward the outline
						bar.Turning = turning
						tween(g.Scale, 0.25, { Scale = turning and 0.9 or 1.06 })
					end
					Motion.spring(g.Root, at - off, 34, 1)
				end
			end,
			ended = function(p, moved)
				bar.Turning = nil
				tween(g.Scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
				Theme.apply(gi, Theme.binds[gi] or {})
				if not moved then
					Sound.play("click")
					bar:next()
					return
				end
				bar.Dragging = false
				bar:drop(p, bar.DragAt)
			end,
		})
		Overlay.attachTooltip(gripFrame, function()
			return "Tap to move · drag to place"
		end)
	end

	self:relayout(true)
	g.Root.Visible = self:wantShown()
	self.Shown = g.Root.Visible
end

-- positions items, pill and grip for the current metrics (no rebuild)
function Bar:relayout(instant)
	local w = self.Window
	local m = self:metrics()
	self.M = m
	local g = self.Glass
	g.Root.Size = UDim2.fromOffset(m.size.X, m.size.Y)
	local n = #w.Tabs
	self.Area.Size = m.vert and UDim2.fromOffset(m.short, n * m.itemLen) or UDim2.fromOffset(n * m.itemLen, m.short)
	for i, tab in ipairs(w.Tabs) do
		local item = self.Items[tab]
		if item then
			item.Position = m.vert and UDim2.fromOffset(m.inset, m.inset + (i - 1) * m.itemLen) or UDim2.fromOffset(m.inset + (i - 1) * m.itemLen, m.inset)
			item.Size = UDim2.fromOffset(m.item.X, m.item.Y)
			tab.Label.Visible = m.labels
			local iconY = m.labels and (m.item.Y / 2 - 7) or m.item.Y / 2
			tab.IconImage.Position = UDim2.fromOffset(m.item.X / 2, iconY)
			tab.IconImage.Size = UDim2.fromOffset(m.labels and 20 or 22, m.labels and 20 or 22)
			tab.Label.Position = UDim2.new(0.5, 0, 0, iconY + 11)
		end
	end
	if self.GripFrame then
		local at = n * m.itemLen + m.inset
		self.GripFrame.Position = m.vert and UDim2.fromOffset(m.inset, at) or UDim2.fromOffset(at, m.inset)
		self.GripFrame.Size = UDim2.fromOffset(m.short, m.short)
	end
	self.Pill.Root.Visible = n > 0
	self.Selector.setRest(UDim2.fromOffset(m.item.X, m.item.Y))
	if w.ActiveTab then
		self.Selector.set(w.ActiveTab.Index, true)
	end
	self:place(instant)
end

function Bar:place(instant)
	if self.Dragging then
		return
	end
	local t = self:target(self.M)
	if instant then
		Motion.stop(self.Root)
		self.Root.Position = UDim2.fromOffset(t.X, t.Y)
	else
		Motion.spring(self.Root, t, 24, 0.62)
	end
	self.LastTarget = t
end

-- floating bars trail their window; a window opened from a pinned or loose
-- bar stays with the bar instead (until the user drags the window away)
function Bar:follow()
	if not self.Floating or self.Dragging or not self.Root or not self.Root.Parent then
		return
	end
	local t = self:target(self.M)
	if not self.LastTarget or (t - self.LastTarget).Magnitude > 0.05 then
		self.LastTarget = t
		Motion.spring(self.Root, t, 30, 0.85)
	end
	local w = self.Window
	if w.AtBar and (self.Screen or self.Free) and not w.Resizing then
		local spot = self:windowSpot(t)
		if not self.LastSpot or (spot - self.LastSpot).Magnitude > 0.05 then
			self.LastSpot = spot
			Motion.spring(w.Root, spot, 24, 0.8)
		end
	end
end

-- where the window goes next to the bar at t: above a bar at the bottom, beside
-- one on the left or right, below one at the top; a loose bar picks the side
-- with more room
function Bar:windowSpot(t)
	local w = self.Window
	local sc = Library.ScaleObject.Scale
	local vs = camera.ViewportSize / sc
	local top = GuiService:GetGuiInset().Y / sc + 8
	local ws = Vector2.new(w.Root.Size.X.Offset, w.Root.Size.Y.Offset)
	local bs, gap = self.M.size, self.Gap
	local side = ({ Bottom = "Above", Top = "Below", Left = "Right", Right = "Left" })[self.Position]
	-- lined up with the bar: a bar in a corner keeps the window in that corner too
	local align = self.Free and "Center" or self.Align
	local function along(lo, len, wlen)
		if align == "Start" then
			return lo
		elseif align == "End" then
			return lo + len - wlen
		end
		return lo + (len - wlen) / 2
	end
	if self.Free then
		if isVertical(self.Position) then
			side = t.X + bs.X / 2 < vs.X / 2 and "Right" or "Left"
		else
			side = t.Y + bs.Y / 2 < vs.Y / 2 and "Below" or "Above"
		end
	end
	local p
	if side == "Above" then
		p = Vector2.new(along(t.X, bs.X, ws.X), t.Y - gap - ws.Y)
	elseif side == "Below" then
		p = Vector2.new(along(t.X, bs.X, ws.X), t.Y + bs.Y + gap)
	elseif side == "Right" then
		p = Vector2.new(t.X + bs.X + gap, along(t.Y, bs.Y, ws.Y))
	else
		p = Vector2.new(t.X - gap - ws.X, along(t.Y, bs.Y, ws.Y))
	end
	return Vector2.new(math.clamp(p.X, 4, math.max(4, vs.X - ws.X - 4)), math.clamp(p.Y, top, math.max(top, vs.Y - ws.Y - 4)))
end

-- a tab was tapped: show the window if it's away, and bring it to a pinned
-- or loose bar
function Bar:summon()
	local w = self.Window
	local away = not w.Visible or w.Minimized
	if self.Floating and (self.Screen or self.Free) then
		local spot = self:windowSpot(self:target(self.M))
		w.AtBar = true
		self.LastSpot = spot
		if away then
			Motion.stop(w.Root)
			w.Root.Position = UDim2.fromOffset(math.floor(spot.X), math.floor(spot.Y))
		else
			Motion.spring(w.Root, spot, 24, 0.8)
		end
	end
	if w.Minimized then
		w:Restore()
	elseif not w.Visible then
		w:SetVisible(true)
	end
end

function Bar:addItem(tab)
	self:makeItem(tab)
	self:relayout(true)
end

-- rebuild in a new place with a liquid morph: the old bar shrinks away while
-- the new one swells in at its target
function Bar:morph(from)
	local old = self.Glass
	local w = self.Window
	if old then
		tween(old.Scale, 0.22, { Scale = 0.86 }, Enum.EasingStyle.Quad)
		Glass.surfaceFade(old, false, 0.2)
		if old.BlurRegion then
			old.BlurRegion:SetTarget(0, 18)
		end
		Motion.groupFade(old.Content, 0, 1, 0.18)
		task.delay(0.3, function()
			old.Root:Destroy()
		end)
	end
	self:build()
	local g = self.Glass
	if from then
		-- start where the drag ended, then spring home
		local pos = from
		if not self.Floating then
			pos = from - screenPos(w.Root) / Library.ScaleObject.Scale
		end
		g.Root.Position = UDim2.fromOffset(pos.X - g.Root.Size.X.Offset / 2, pos.Y - g.Root.Size.Y.Offset / 2)
		self:place(false)
	end
	if g.Root.Visible then
		g.Scale.Scale = 0.86
		tween(g.Scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
		Glass.surfaceFade(g, false, 0)
		Glass.surfaceFade(g, true, 0.3)
		if g.BlurRegion then
			g.BlurRegion:SetTarget(1, 12)
		end
		Motion.groupFade(g.Content, 1, 0, 0.3)
	end
	w:_layout(false)
	Sound.play("tab")
	Util.fire(self.OnMoved, self.Free and "Free" or self.Position, self.Floating, self.Screen, self.Align)
end

-- opts: Floating (bool), Screen (bool, pinned to the screen edge), Align
-- (Start / Center / End along that edge), Free (Vector2 screen position,
-- floating only), From (screen point a drag ended at), Force (always rebuild)
function Bar:setPosition(pos, opts)
	opts = opts or {}
	local newPos = edgeName(pos) or self.Position
	local floating = opts.Floating
	if floating == nil then
		floating = self.Floating
	end
	local screen = opts.Screen
	if screen == nil then
		screen = self.Screen and opts.Floating ~= false
	end
	if screen then
		floating = true
	end
	local free = floating and opts.Free or nil
	if free then
		screen = false
	end
	local rebuild = opts.Force or floating ~= self.Floating or isVertical(newPos) ~= isVertical(self.Position)
	local align = alignName(opts.Align) or self.Align
	local changed = rebuild or newPos ~= self.Position or (self.Free ~= nil) ~= (free ~= nil) or screen ~= self.Screen or (screen and align ~= self.Align)
	self.Align = align
	if screen ~= self.Screen then
		-- pinning brings the window along; unpinning lets the bar trail it again
		self.Window.AtBar = screen
		self.LastSpot = nil
	end
	self.Position, self.Floating, self.Free, self.Screen = newPos, floating, free, screen
	if rebuild then
		self:morph(opts.From)
		return
	end
	if changed then
		-- same orientation: glide over; docked pages make room as it moves
		self.Window:_layout(false)
		self:place(false)
		Sound.play("tab")
		Util.fire(self.OnMoved, free and "Free" or self.Position, self.Floating, self.Screen, self.Align)
	else
		self:place(false)
	end
end

function Bar:next()
	if self.Locked then
		return
	end
	if self.Free then
		self:setPosition("Bottom", { Floating = true })
		return
	end
	local cur = table.find(self.Cycle, self.Position) or 0
	self:setPosition(self.Cycle[cur % #self.Cycle + 1])
end

-- the screen slot a drag would snap to (pointer p, the bar's top-left at `at`
-- in screen space): three per edge (start, center, end), so a corner takes the
-- bar lying along one edge or standing along the other, whichever is nearer.
-- nil when the bar isn't near an edge of the screen or the pointer is on the
-- window
function Bar:snapSlot(p, at)
	local w = self.Window
	local sc = Library.ScaleObject.Scale
	local q = p / sc
	local vs = camera.ViewportSize / sc
	local top = GuiService:GetGuiInset().Y / sc
	local reach = 64
	-- the window takes a bar dropped on it, unless the pointer is right at the
	-- edge of the screen (a window opened from the bar often reaches it)
	local atEdge = q.X < reach or q.X > vs.X - reach or q.Y < top + reach or q.Y > vs.Y - reach
	if w.Visible and not w.Minimized and not atEdge then
		local wp, ws = screenPos(w.Root) / sc, w.Root.AbsoluteSize / sc
		local beyond = math.max(wp.X - q.X, q.X - (wp.X + ws.X), wp.Y - q.Y, q.Y - (wp.Y + ws.Y))
		if beyond <= 24 then
			return nil
		end
	end
	local size = self.M.size
	at = at or q - size / 2
	local near = {
		Left = math.min(q.X, at.X) < reach,
		Right = math.max(q.X, at.X + size.X) > vs.X - reach,
		Top = math.min(q.Y, at.Y) < top + reach,
		Bottom = math.max(q.Y, at.Y + size.Y) > vs.Y - reach,
	}
	local c = at + size / 2
	local best, bestD
	for _, edge in ipairs(CYCLE) do
		if near[edge] then
			local es = self:metrics(edge, true).size
			for _, align in ipairs({ "Start", "Center", "End" }) do
				local pos = screenSpot(edge, align, es)
				local d = (pos + es / 2 - c).Magnitude
				if not bestD or d < bestD then
					best, bestD = { Edge = edge, Align = align, Pos = pos, Size = es }, d
				end
			end
		end
	end
	return best
end

-- a soft glass outline where (and which way round) the bar is about to snap
function Bar:showGhost(slot)
	local gh = self.Ghost
	if not slot then
		if gh and self.GhostKey then
			self.GhostKey = nil
			tween(gh, 0.2, { BackgroundTransparency = 1 })
			tween(self.GhostStroke, 0.2, { Transparency = 1 })
		end
		return
	end
	if not gh then
		gh = new("Frame", { Name = "TabBarGhost", BackgroundTransparency = 1, BorderSizePixel = 0, Parent = Library.Gui })
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = gh })
		self.GhostStroke = new("UIStroke", { Thickness = 1.5, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = gh })
		self.Ghost = gh
	end
	local key = slot.Edge .. slot.Align
	if key == self.GhostKey then
		return
	end
	local first = self.GhostKey == nil
	self.GhostKey = key
	local accent = Theme.value("Accent")
	gh.BackgroundColor3, self.GhostStroke.Color = accent, accent
	gh.ZIndex = self.Floating and math.max(self.Root.ZIndex - 1, 1) or nextZ(5)
	local pos, size = UDim2.fromOffset(slot.Pos.X, slot.Pos.Y), UDim2.fromOffset(slot.Size.X, slot.Size.Y)
	if first then
		gh.Position, gh.Size = pos, size
		tween(gh, 0.2, { BackgroundTransparency = 0.84 })
		tween(self.GhostStroke, 0.2, { Transparency = 0.3 })
	else
		tween(gh, 0.3, { Position = pos, Size = size }, Enum.EasingStyle.Quint)
	end
	Sound.play("tick")
end

-- a drag ended at screen point p, with the bar's top-left at `at`:
--  near a screen edge: pins to the nearest slot on it (corners included)
--  docked:   inside the window -> nearest inner edge; pulled out -> detaches and floats
--  floating: dropped on the window -> docks inside; near it -> nearest outer edge;
--            far away -> stays exactly where it was dropped
function Bar:drop(p, at)
	local w = self.Window
	local sc = Library.ScaleObject.Scale
	local q = p / sc
	local from = q * sc
	local size = self.M.size
	self:showGhost(nil)
	local slot = self:snapSlot(p, at)
	if slot then
		self:setPosition(slot.Edge, { Floating = true, Screen = true, Align = slot.Align, From = from })
		return
	end
	if not (w.Visible and not w.Minimized) then
		-- the window is away: the bar stays loose where it was dropped
		self:setPosition(self.Position, { Free = Motion.target(self.Root) })
		return
	end
	local wp = screenPos(w.Root) / sc
	local ws = w.Root.AbsoluteSize / sc
	local dl, dr = math.abs(q.X - wp.X), math.abs(q.X - (wp.X + ws.X))
	local dt, db = math.abs(q.Y - wp.Y), math.abs(q.Y - (wp.Y + ws.Y))
	local beyond = math.max(wp.X - q.X, q.X - (wp.X + ws.X), wp.Y - q.Y, q.Y - (wp.Y + ws.Y))
	local nearest, nd = "Bottom", db
	for name, d in pairs({ Left = dl, Right = dr, Top = dt }) do
		if d < nd then
			nearest, nd = name, d
		end
	end
	if not self.Floating then
		if beyond > 24 then
			if beyond > 160 then
				self:setPosition(self.Position, { Floating = true, Free = q - size / 2, From = from })
			else
				self:setPosition(nearest, { Floating = true, From = from })
			end
		else
			self:setPosition(nearest, { From = from })
		end
		return
	end
	if beyond < -40 then
		self:setPosition(nearest, { Floating = false, Screen = false, From = from })
	elseif beyond > 160 then
		self:setPosition(self.Position, { Free = Motion.target(self.Root) })
	else
		self:setPosition(nearest, { Screen = false, From = from })
	end
end

-- detach from / attach to the window programmatically
function Bar:setFloating(on)
	self:setPosition(self.Position, { Floating = on and true or false, Screen = on and self.Screen or false })
end

-- pin to (or release from) the edge of the screen
function Bar:setScreen(on)
	self:setPosition(self.Position, { Screen = on and true or false, Floating = on and true or self.Floating })
end

-- a locked bar has no grip and stays where it is
function Bar:setLocked(on)
	on = on and true or false
	if self.Locked == on then
		return
	end
	self.Locked = on
	self:setPosition(self.Position, { Force = true, Screen = self.Screen, Floating = self.Floating, Free = self.Free })
end

-- floating bars stay on screen while the window is hidden or minimized, so
-- their tabs can bring it back, unless HideWithWindow is set or the script hid
-- the bar; docked bars are part of the window
function Bar:persists()
	return self.Floating and not self.HideWithWindow and not self.Hidden
end

function Bar:wantShown()
	local w = self.Window
	if w.Opening or w.Destroyed or self.Hidden then
		return false
	end
	return self:persists() or (w.Visible and not w.Minimized)
end

function Bar:setShown(on, time)
	if self.Shown == on or not self.Glass then
		return
	end
	self.Shown = on
	local g = self.Glass
	if not self.Floating then
		-- docked bars live in the window body and fade with it
		g.Root.Visible = on
		return
	end
	time = time or 0.25
	if on then
		g.Root.Visible = true
		g.Root.ZIndex = nextZ(5)
		g.Scale.Scale = 0.9
		tween(g.Scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		Glass.surfaceFade(g, true, time)
		g.BlurRegion:SetTarget(1, 12)
		Motion.groupFade(g.Content, 1, 0, time)
	else
		tween(g.Scale, time, { Scale = 0.9 }, Enum.EasingStyle.Quad)
		Glass.surfaceFade(g, false, time)
		g.BlurRegion:SetTarget(0, 14)
		Motion.groupFade(g.Content, 0, 1, time, function()
			if not self.Shown then
				g.Root.Visible = false
			end
		end)
	end
end

function Bar:destroy()
	if self.Ghost then
		self.Ghost:Destroy()
		self.Ghost = nil
	end
	if self.Glass then
		self.Glass.Root:Destroy()
		self.Glass = nil
	end
end

-- Window API ---------------------------------------------------------------------
-- cfg: Position, Floating, Screen, Align, Locked, HideWithWindow, Labels,
-- Draggable, Grip, Cycle, Gap, OnMoved
function Window:SetTabBar(cfg)
	local bar = self.Bar
	if not bar then
		warn("[LiquidGlass] SetTabBar needs CreateWindow({ Navigation = \"TabBar\" })")
		return
	end
	cfg = cfg or {}
	for _, k in ipairs({ "Labels", "Draggable", "Grip", "Cycle", "Gap", "OnMoved", "Locked", "HideWithWindow" }) do
		if cfg[k] ~= nil then
			bar[k] = cfg[k]
		end
	end
	bar:setPosition(cfg.Position or bar.Position, { Floating = cfg.Floating, Screen = cfg.Screen, Align = cfg.Align, Force = true })
end

function Window:SetTabBarPosition(pos, floating)
	if self.Bar then
		self.Bar:setPosition(pos, { Floating = floating })
	end
end

function Window:GetTabBar()
	return self.Bar
end

-- pin the bar to an edge of the screen (Bottom, Left, Top, Right), like a dock;
-- align puts it at the start, center or end of that edge: PinTabBar("Bottom",
-- "Left") lies in the bottom-left corner, PinTabBar("Left", "Bottom") stands there
function Window:PinTabBar(edge, align)
	if self.Bar then
		self.Bar:setPosition(edge or self.Bar.Position, { Screen = true, Align = align })
	end
end

function Window:UnpinTabBar()
	if self.Bar then
		self.Bar:setScreen(false)
	end
end

function Window:LockTabBar(on)
	if self.Bar then
		self.Bar:setLocked(on ~= false)
	end
end

-- hide or show the bar itself; a hidden bar stays hidden with the window open
function Window:SetTabBarVisible(on)
	local bar = self.Bar
	if bar then
		bar.Hidden = on == false
		bar:setShown(bar:wantShown())
	end
end

function Window:DetachTabBar()
	if self.Bar then
		self.Bar:setFloating(true)
	end
end

function Window:AttachTabBar()
	if self.Bar then
		self.Bar:setFloating(false)
	end
end

-- pages make room for a docked bar
function Window:_layoutTabBar(instant)
	local bar = self.Bar
	local g = S.Gutter
	local top = S.WindowInset + S.Header
	local l, r, t, b = g - 4, g - 4, top, S.WindowInset
	if bar and not bar.Floating then
		local m = bar:metrics()
		local room = S.WindowInset
		if bar.Position == "Bottom" then
			b = S.WindowInset + m.size.Y + room
		elseif bar.Position == "Top" then
			t = top + m.size.Y + room
		elseif bar.Position == "Left" then
			l = S.WindowInset + m.size.X + room
		else
			r = S.WindowInset + m.size.X + room
		end
	end
	local pos, size = UDim2.fromOffset(l, t), UDim2.new(1, -(l + r), 1, -(t + b))
	if instant then
		self.Pages.Position, self.Pages.Size = pos, size
	else
		tween(self.Pages, 0.4, { Position = pos, Size = size })
	end
	if self.Search then
		local wide = self.Root.Size.X.Offset >= 560
		self.Search.Root.Visible = wide
		self:_fitHeaderTitle(wide)
	end
	if bar and bar.Glass then
		bar:relayout(instant)
	end
end

-- bars show and hide with their window (see Bar:wantShown), stay in front of
-- it, and unload with it
do
	local baseSetVisible = Window.SetVisible
	function Window:SetVisible(on, silent)
		baseSetVisible(self, on, silent)
		if self.Bar then
			self.Bar:setShown(self.Bar:wantShown())
		end
	end
	local baseFocus = Window.Focus
	function Window:Focus()
		baseFocus(self)
		local bar = self.Bar
		if bar and bar.Floating and bar.Root and bar.Root.ZIndex <= self.Root.ZIndex then
			bar.Root.ZIndex = nextZ(5)
		end
	end
	local baseDestroy = Window.Destroy
	function Window:Destroy()
		if self.Bar and not self.Destroyed then
			self.Bar:setShown(false)
			local bar = self.Bar
			task.delay(0.3, function()
				bar:destroy()
			end)
		end
		baseDestroy(self)
	end
end
