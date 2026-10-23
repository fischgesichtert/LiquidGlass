---------------------------------------------------------------------------
-- Backdrop blur
-- Glass parts just in front of the camera get blurred by a DepthOfField near
-- blur, and the closer a part sits to the camera the stronger its blur. Every
-- surface is a lightly blurred interior with blurrier rings toward its rim, so
-- the backdrop smears and wraps around the edge like a thick lens.
-- Near-field blur bleeds outward, so each layer is pulled in by its own bleed.
-- Glass also shows a sharp sun/moon specular spot wherever the mirrored light
-- lands on screen; when it would, the parts tilt until the spot leaves the view.
-- Fading a blur slides its parts toward the near limit, where blur reaches zero.
---------------------------------------------------------------------------
local camera = workspace.CurrentCamera
local blurFolder, dof

local NEAR_LIMIT = 1.6 -- FocusDistance - InFocusRadius
local INTERIOR_DEPTH = 0.6
-- rim rings: width = radius * frac clamped to [min, max] px. Parts can't be thinner
-- than 0.001 studs, so the shallow ring keeps a min width the clamp can't swallow.
local RINGS = {
	{ frac = 0.45, min = 6, max = 16, depth = 0.3 },
	{ frac = 0.2, min = 4.5, max = 7, depth = 0.15 },
}
local TILT_X, TILT_Y = math.rad(31), math.rad(40)
local SPOT_MARGIN = math.rad(24)
local THIN = 0.001
local INSET = 0.5
local GLASS_T = 0.995
local BLEED_FRAC = 0.014 -- outward bleed of the closest layer, fraction of viewport height
local ROT90 = CFrame.Angles(0, math.rad(90), 0)

Blur.regions = {}
local tiltX, tiltY = 0, 0

function Blur.attach()
	camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if not blurFolder then
		blurFolder = new("Folder", { Name = "LiquidGlassBlur" })
	end
	blurFolder.Parent = camera
	if not dof or not dof.Parent then
		dof = new("DepthOfFieldEffect", {
			Name = "LiquidGlassDOF",
			FarIntensity = 0,
			FocusDistance = 51.6,
			InFocusRadius = 50,
			NearIntensity = 1,
			Enabled = false,
		})
	end
	dof.Parent = camera
end
Blur.attach()
Util.track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(Blur.attach))

local function glassPart(shape)
	return new("Part", {
		Name = "Glass",
		Shape = shape,
		Material = Enum.Material.Glass,
		Transparency = 1,
		Color = WHITE,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Size = Vector3.new(THIN, THIN, THIN),
		Parent = blurFolder,
	})
end

local function shown(o)
	local gui = Library.Gui
	if not gui or not gui.Enabled then
		return false
	end
	while o and o ~= gui do
		if o:IsA("GuiObject") and not o.Visible then
			return false
		end
		o = o.Parent
	end
	return o == gui
end

-- inset of a rounded rect's left edge at row py (0..h) for corner radius r
local function cornerInset(py, h, r)
	local dy = 0
	if py < r then
		dy = r - py
	elseif py > h - r then
		dy = py - (h - r)
	end
	if dy <= 0 then
		return 0
	end
	return r - math.sqrt(math.max(r * r - dy * dy, 0))
end

local function bleed(depth, maxBleed)
	return maxBleed * math.clamp((NEAR_LIMIT - depth) / NEAR_LIMIT, 0, 1)
end

-- screen-space primitives {kind, cx, cy, w, h, rot, depth} of one rounded rect
local function buildPrims(x0, y0, w0, h0, r0, interiorDepth, tilted, maxBleed, amount)
	local prims = {}
	local function rect(ax, ay, bx, by, depth)
		if bx - ax > 0.05 and by - ay > 0.05 then
			table.insert(prims, { "rect", (ax + bx) / 2, (ay + by) / 2, bx - ax, by - ay, 0, depth })
		end
	end
	local function shrink(e)
		e = math.min(e, math.min(w0, h0) / 2 - 1)
		return x0 + e, y0 + e, w0 - 2 * e, h0 - 2 * e, math.max(r0 - e, 0)
	end
	local function depthOf(d)
		return NEAR_LIMIT - (NEAR_LIMIT - d) * amount
	end

	local di = depthOf(interiorDepth)
	local x, y, w, h, r = shrink(bleed(di, maxBleed))
	if not tilted then
		rect(x, y + r, x + w, y + h - r, di)
		rect(x + r, y, x + w - r, y + h, di)
		if r > 0.5 then
			for _, c in ipairs({ { x + r, y + r }, { x + w - r, y + r }, { x + r, y + h - r }, { x + w - r, y + h - r } }) do
				table.insert(prims, { "cyl", c[1], c[2], 2 * r, 2 * r, 0, di })
			end
		end
	else
		-- tilted parts must stay short along the tilt, so the interior becomes strips
		local yy = 0
		while yy < h - 0.01 do
			local step = math.min((yy < r or yy >= h - r) and 3 or 24, h - yy)
			local ins = math.max(cornerInset(yy, h, r), cornerInset(yy + step, h, r))
			-- neighbours overlap slightly so tilted strips never leave hairline cracks
			rect(x + ins, y + yy - 0.6, x + w - ins, y + yy + step + 0.6, di)
			yy += step
		end
	end

	for _, ring in ipairs(RINGS) do
		local d = depthOf(ring.depth)
		x, y, w, h, r = shrink(bleed(d, maxBleed))
		local t = math.min(math.clamp(r0 * ring.frac, ring.min, ring.max), math.min(w, h) / 2)
		rect(x + r, y, x + w - r, y + t, d)
		rect(x + r, y + h - t, x + w - r, y + h, d)
		rect(x, y + r, x + t, y + h - r, d)
		rect(x + w - t, y + r, x + w, y + h - r, d)
		if r > 0.5 then
			-- quarter annuli out of short tangential bricks (inscribed polygon)
			local ro, ri = r, math.max(r - t, 0)
			local n = math.clamp(math.ceil(r / 6), 3, 7)
			local da = (math.pi / 2) / n
			local hd = da / 2
			local outer = ro * (1 + math.cos(hd)) / 2
			local inner = ri * math.cos(hd)
			local radial = outer - inner
			local tangential = 2 * ro * math.sin(hd) + 0.8
			local mid = (outer + inner) / 2
			for _, c in ipairs({
				{ x + r, y + r, math.pi },
				{ x + w - r, y + r, math.pi * 1.5 },
				{ x + w - r, y + h - r, 0 },
				{ x + r, y + h - r, math.pi * 0.5 },
			}) do
				for j = 0, n - 1 do
					local am = c[3] + da * (j + 0.5)
					table.insert(prims, { "rect", c[1] + math.cos(am) * mid, c[2] + math.sin(am) * mid, tangential, radial, am + math.pi / 2, d })
				end
			end
		end
	end
	return prims
end

-- camera-space CFrame and size of a primitive; K = world units per px at depth 1
local function primToLocal(p, K, hx, hy)
	local kind, cx, cy, w, h, rot, depth = p[1], p[2], p[3], p[4], p[5], p[6], p[7]
	local P = Vector3.new((cx - hx) * K * depth, (hy - cy) * K * depth, -depth)
	if kind == "cyl" then
		return CFrame.new(P) * ROT90, Vector3.new(THIN, h * K * depth, h * K * depth)
	end
	local axisX = rot ~= 0 or w >= h
	local angle = axisX and tiltX or tiltY
	if angle == 0 then
		return CFrame.new(P) * CFrame.Angles(0, 0, -rot), Vector3.new(w * K * depth, h * K * depth, THIN)
	end
	local n = axisX and Vector3.new(0, -math.sin(angle), math.cos(angle)) or Vector3.new(math.sin(angle), 0, math.cos(angle))
	local nP = n:Dot(P)
	local c, s = math.cos(rot), math.sin(rot)
	local function onPlane(u, v)
		local sx = cx + u * w * c - v * h * s
		local sy = cy + u * w * s + v * h * c
		local d = Vector3.new((sx - hx) * K, (hy - sy) * K, -1)
		return d * (nP / n:Dot(d))
	end
	local l, rr, t, b = onPlane(-0.5, 0), onPlane(0.5, 0), onPlane(0, -0.5), onPlane(0, 0.5)
	local U, V = rr - l, b - t
	local X = U.Unit
	local Vp = V - X * V:Dot(X)
	return CFrame.fromMatrix((l + rr + t + b) / 4, X, -Vp.Unit), Vector3.new(U.Magnitude, Vp.Magnitude, THIN)
end

-- smallest angle between the view frustum and the view ray whose mirror image
-- (about a plane with camera-space normal n) points at light direction s
local function spotAngle(n, s, tanH, tanV)
	local v = s - n * (2 * s:Dot(n))
	if v.Z > -0.02 then
		return math.pi
	end
	local px, py = v.X / -v.Z, v.Y / -v.Z
	local d = Vector3.new(math.clamp(px, -tanH, tanH), math.clamp(py, -tanV, tanV), -1).Unit
	return math.acos(math.clamp(v.Unit:Dot(d), -1, 1))
end

local function chooseTilt(current, axisX, maxAngle, lights, tanH, tanV)
	local function worst(a)
		local n = axisX and Vector3.new(0, -math.sin(a), math.cos(a)) or Vector3.new(math.sin(a), 0, math.cos(a))
		local m = math.pi
		for _, s in ipairs(lights) do
			m = math.min(m, spotAngle(n, s, tanH, tanV))
		end
		return m
	end
	-- flat whenever safe (with hysteresis), otherwise keep or pick the safer tilt
	if worst(0) > SPOT_MARGIN + (current ~= 0 and math.rad(6) or 0) then
		return 0
	end
	if current ~= 0 and worst(current) > SPOT_MARGIN then
		return current
	end
	return worst(maxAngle) >= worst(-maxAngle) and maxAngle or -maxAngle
end

local function setVisible(rg, on)
	if rg.visible == on then
		return
	end
	rg.visible = on
	for _, part in ipairs(rg.used) do
		part.Transparency = on and GLASS_T or 1
	end
end

local function rebuild(rg, x, y, w, h, r, K, hx, hy, tilted, maxBleed)
	local prims = buildPrims(x + INSET, y + INSET, w - 2 * INSET, h - 2 * INSET, math.max(r - INSET, 0), rg.depth, tilted, maxBleed, rg.amount)
	local nb, nc = 0, 0
	local used, locals = {}, {}
	for i, p in ipairs(prims) do
		local part
		if p[1] == "cyl" then
			nc += 1
			part = rg.cyls[nc] or glassPart(Enum.PartType.Cylinder)
			rg.cyls[nc] = part
		else
			nb += 1
			part = rg.blocks[nb] or glassPart(Enum.PartType.Block)
			rg.blocks[nb] = part
		end
		local lcf, size = primToLocal(p, K, hx, hy)
		part.Size = size
		used[i], locals[i] = part, lcf
	end
	for j = nb + 1, #rg.blocks do
		rg.blocks[j].Transparency = 1
	end
	for j = nc + 1, #rg.cyls do
		rg.cyls[j].Transparency = 1
	end
	for _, part in ipairs(used) do
		part.Transparency = rg.visible and GLASS_T or 1
	end
	rg.used, rg.locals = used, locals
end

local Region = {}
Region.__index = Region

-- fade the blur in (1) or out (0)
function Region:SetTarget(t, speed)
	self.target = t
	self.speed = speed or self.speed
end

function Region:Remove()
	if self.removed then
		return
	end
	self.removed = true
	local i = table.find(Blur.regions, self)
	if i then
		table.remove(Blur.regions, i)
	end
	for _, p in ipairs(self.blocks) do
		p:Destroy()
	end
	for _, p in ipairs(self.cyls) do
		p:Destroy()
	end
end

-- frame: the GuiObject whose rounded shape is blurred; radius: number or function()
function Blur.add(frame, radius, o)
	o = o or {}
	local rg = setmetatable({
		frame = frame,
		radius = radius,
		depth = o.Depth or INTERIOR_DEPTH,
		amount = o.Instant == false and 0 or (o.Start or 1),
		target = 1,
		speed = o.Speed or 12,
		blocks = {},
		cyls = {},
		used = {},
		locals = {},
		visible = false,
	}, Region)
	table.insert(Blur.regions, rg)
	frame.Destroying:Connect(function()
		rg:Remove()
	end)
	return rg
end

local bulkParts, bulkCFrames = {}, {}
Blur.stats = { parts = 0 }
local function updateBlur(dt)
	if not camera or not camera.Parent then
		Blur.attach()
		if not camera then
			return
		end
	end
	local cf = camera.CFrame
	local vs = camera.ViewportSize
	local fov = math.rad(camera.FieldOfView)
	local tanV = math.tan(fov / 2)
	local tanH = tanV * vs.X / vs.Y
	local K = 2 * tanV / vs.Y
	local hx, hy = vs.X / 2, vs.Y / 2

	local lights = {}
	for _, dir in ipairs({ Lighting:GetSunDirection(), Lighting:GetMoonDirection() }) do
		if dir.Y > -0.15 then
			table.insert(lights, cf:VectorToObjectSpace(dir))
		end
	end
	tiltX = chooseTilt(tiltX, true, TILT_X, lights, tanH, tanV)
	tiltY = chooseTilt(tiltY, false, TILT_Y, lights, tanH, tanV)
	local tilted = tiltX ~= 0 or tiltY ~= 0
	local maxBleed = vs.Y * BLEED_FRAC

	table.clear(bulkParts)
	table.clear(bulkCFrames)
	local enabled = Library.Settings.Blur and not Library.Unloaded
	local origin = Library.Gui and Library.Gui.AbsolutePosition or Vector2.zero
	for _, rg in ipairs(Blur.regions) do
		if rg.amount ~= rg.target then
			rg.amount += (rg.target - rg.amount) * (1 - math.exp(-dt * rg.speed))
			if math.abs(rg.target - rg.amount) < 0.01 then
				rg.amount = rg.target
			end
		end
		if not enabled or rg.amount < 0.02 or not shown(rg.frame) then
			setVisible(rg, false)
			continue
		end
		-- AbsolutePosition lives in inset space; make it relative to the (inset-ignoring) ScreenGui
		local pos, size = rg.frame.AbsolutePosition - origin, rg.frame.AbsoluteSize
		if size.X < 2 or size.Y < 2 then
			setVisible(rg, false)
			continue
		end
		local base = rg.frame.Size.Y.Offset
		local scale = base > 0 and size.Y / base or 1
		local radius = type(rg.radius) == "function" and rg.radius() or rg.radius * scale
		local r = math.min(radius, size.X / 2, size.Y / 2)
		local key = string.format("%.2f|%.2f|%.2f|%.2f|%.2f|%.4f|%.4f|%.4f|%d|%d|%.2f", pos.X, pos.Y, size.X, size.Y, r, tiltX, tiltY, fov, vs.X, vs.Y, rg.amount)
		if key ~= rg.key then
			rg.key = key
			rebuild(rg, pos.X, pos.Y, size.X, size.Y, r, K, hx, hy, tilted, maxBleed)
		end
		setVisible(rg, true)
		for i, part in ipairs(rg.used) do
			bulkParts[#bulkParts + 1] = part
			bulkCFrames[#bulkCFrames + 1] = cf * rg.locals[i]
		end
	end
	Blur.stats.parts = #bulkParts
	if dof then
		dof.Enabled = #bulkParts > 0
	end
	if #bulkParts > 0 then
		workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- unique per instance: a reloaded copy unbinding by name must never hit the new one
local BIND_NAME = "LiquidGlassBlur_" .. Util.hash(tostring(os.clock()) .. tostring(math.random()))
local lastBlur = os.clock()
RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
	local now = os.clock()
	local dt = math.min(now - lastBlur, 0.1)
	lastBlur = now
	local ok, err = pcall(updateBlur, dt)
	if not ok then
		warn("[LiquidGlass] blur: " .. tostring(err))
	end
end)

Util.onCleanup(function()
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, rg in ipairs(table.clone(Blur.regions)) do
		rg:Remove()
	end
	if blurFolder then
		blurFolder:Destroy()
	end
	if dof then
		dof:Destroy()
	end
end)

function Library:SetBlur(on)
	Library.Settings.Blur = on and true or false
end
