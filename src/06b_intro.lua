---------------------------------------------------------------------------
-- Intro: "made by Entity" in real 3D liquid glass, played once before the
-- first window opens. The word is a glass mesh (exact font outlines with a
-- rounded bevel) rebuilt at runtime with EditableMesh: clear glass faces, glossy
-- bevels, a slow light glint, all over a softly moving colour backdrop that the
-- glass refracts. Without EditableMesh access it falls back to a 2D version.
---------------------------------------------------------------------------
-- the intro always plays before the first window; automated tests may set
-- getgenv().LiquidGlassSkipIntro = true before loading the library
local Intro = { Played = env.LiquidGlassSkipIntro == true, Active = false }
Library._intro = Intro

local AssetService = game:GetService("AssetService")
local INTRO_CREDIT = "Entity"

local BACKDROP = {
	{ 0.1, 0.15, Color3.fromRGB(46, 32, 190), 0.5 },
	{ 0.9, 0.15, Color3.fromRGB(196, 36, 140), 0.5 },
	{ 0.85, 0.9, Color3.fromRGB(238, 112, 40), 0.42 },
	{ 0.12, 0.9, Color3.fromRGB(10, 150, 190), 0.42 },
	{ 0.5, 0.5, Color3.fromRGB(92, 58, 210), 0.42 },
}

local function backdropColor(u, v)
	local r, g, b, ws = 0, 0, 0, 0
	for _, bl in ipairs(BACKDROP) do
		local w = math.exp(-((u - bl[1]) ^ 2 + (v - bl[2]) ^ 2) / (bl[4] ^ 2 * 0.3))
		r += bl[3].R * w
		g += bl[3].G * w
		b += bl[3].B * w
		ws += w
	end
	local vig = 1 - 0.4 * math.clamp(((u - 0.5) ^ 2 + (v - 0.5) ^ 2) * 2.2, 0, 1)
	return Color3.new(r / ws * vig, g / ws * vig, b / ws * vig)
end

local function solid(mesh)
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CastShadow = false
	return mesh
end

-- opaque geometry with vertex colours: unlike decals, glass refracts it
local function buildBackdrop()
	local em = AssetService:CreateEditableMesh()
	local GX, GY = 14, 8
	local vid, cid = {}, {}
	for j = 0, GY do
		for i = 0, GX do
			local k = j * (GX + 1) + i
			vid[k] = em:AddVertex(Vector3.new(i / GX - 0.5, 0.5 - j / GY, 0))
			cid[k] = em:AddColor(backdropColor(i / GX, j / GY), 1)
		end
	end
	local nid = em:AddNormal(Vector3.new(0, 0, 1))
	for j = 0, GY - 1 do
		for i = 0, GX - 1 do
			local a, b = j * (GX + 1) + i, j * (GX + 1) + i + 1
			local c, d = a + GX + 1, b + GX + 1
			for _, t in ipairs({ { a, c, b }, { b, c, d } }) do
				local f = em:AddTriangle(vid[t[1]], vid[t[2]], vid[t[3]])
				em:SetFaceColors(f, { cid[t[1]], cid[t[2]], cid[t[3]] })
				em:SetFaceNormals(f, { nid, nid, nid })
			end
		end
	end
	local part = solid(AssetService:CreateMeshPartAsync(Content.fromObject(em)))
	part.Material = Enum.Material.SmoothPlastic
	part.Color = WHITE
	return part, em
end

-- the word: returns faces mesh, bevel mesh, and the word's aspect (width / height)
local function buildWord()
	local raw = PACK["logo.mesh"]
	if not raw then
		return nil
	end
	local b = buffer.fromstring(b64decode(raw))
	local nv, nt, nf = buffer.readu16(b, 0), buffer.readu16(b, 2), buffer.readu16(b, 4)
	local o = 6
	local posOff = o
	o += nv * 6
	local nOff = o
	o += nv * 6
	local tOff = o
	o += nt * 6
	local hx, hy, hz = buffer.readf32(b, o), buffer.readf32(b, o + 4), buffer.readf32(b, o + 8)
	local function mesh(first, last)
		local em = AssetService:CreateEditableMesh()
		local vmap, nmap = {}, {}
		local function vert(i)
			local v = vmap[i]
			if not v then
				v = em:AddVertex(Vector3.new(buffer.readi16(b, posOff + i * 6) / 32767 * hx, buffer.readi16(b, posOff + i * 6 + 2) / 32767 * hy, buffer.readi16(b, posOff + i * 6 + 4) / 32767 * hz))
				nmap[i] = em:AddNormal(Vector3.new(buffer.readi16(b, nOff + i * 6), buffer.readi16(b, nOff + i * 6 + 2), buffer.readi16(b, nOff + i * 6 + 4)).Unit)
				vmap[i] = v
			end
			return v
		end
		for t = first, last do
			local a = buffer.readu16(b, tOff + t * 6)
			local c = buffer.readu16(b, tOff + t * 6 + 2)
			local d = buffer.readu16(b, tOff + t * 6 + 4)
			local f = em:AddTriangle(vert(a), vert(c), vert(d))
			em:SetFaceNormals(f, { nmap[a], nmap[c], nmap[d] })
		end
		return solid(AssetService:CreateMeshPartAsync(Content.fromObject(em))), em
	end
	-- one part: Roblox sorts overlapping transparent parts unreliably
	local word, em = mesh(0, nt - 1)
	return word, word.Size, em
end

-- 2D overlay labels shared by both versions
local function labels(holder, title)
	local made = Glass.text({ Parent = holder, Text = "M A D E   B Y", Weight = Enum.FontWeight.SemiBold, TextSize = 15, XAlign = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(300, 18), ZIndex = 3 })
	Theme.unbind(made, "TextColor3")
	made.TextColor3 = WHITE
	made.TextTransparency = 1
	local sub
	if title and title ~= "" then
		sub = Glass.text({ Parent = holder, Text = title, Weight = Enum.FontWeight.SemiBold, TextSize = 18, XAlign = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(500, 22), ZIndex = 3 })
		Theme.unbind(sub, "TextColor3")
		sub.TextColor3 = WHITE
		sub.TextTransparency = 1
	end
	local hint = Glass.text({ Parent = holder, Text = "Click or press Space to skip", TextSize = 12, XAlign = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(200, 16), ZIndex = 3 })
	Theme.unbind(hint, "TextColor3")
	hint.TextColor3 = WHITE
	hint.TextTransparency = 1
	return made, sub, hint
end

-- o: Title (shown under the word), OnReveal() called as the intro dissolves
function Intro.play(o)
	o = o or {}
	Intro.Played = true
	Intro.Active = true
	local done = false
	local cleanup = {}
	local function finish()
		if done then
			return
		end
		done = true
		Intro.Active = false
		for _, fn in ipairs(cleanup) do
			pcall(fn)
		end
		for _, fn in ipairs(Intro.waiting or {}) do
			task.spawn(fn)
		end
		Intro.waiting = nil
	end

	local holder = new("Frame", { Name = "Intro", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = nextZ(2000), Parent = Library.Gui })
	table.insert(cleanup, function()
		holder:Destroy()
	end)
	local catch = new("TextButton", { BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = holder })
	local made, sub, hint = labels(holder, o.Title)

	local cam = workspace.CurrentCamera
	local ok3d, word3d, wordSize, emWord = pcall(buildWord)
	local backdrop, emBack
	if ok3d and word3d then
		local okB, p, e = pcall(buildBackdrop)
		if okB then
			backdrop, emBack = p, e
		end
	end
	local is3d = ok3d and word3d ~= nil and backdrop ~= nil
	local lights = {}
	local fallback

	local D, WALL = 2.5, 6
	local function viewHeight(d)
		return 2 * d * math.tan(math.rad(cam.FieldOfView) / 2)
	end

	if is3d then
		for _, p in ipairs({ word3d, backdrop }) do
			p.Transparency = 1
			p.Parent = cam
			table.insert(cleanup, function()
				p:Destroy()
			end)
		end
		table.insert(cleanup, function()
			emWord:Destroy()
			emBack:Destroy()
		end)
		word3d.Material = Enum.Material.Glass
		word3d.Color = WHITE
		word3d.Reflectance = 0.12
		for i = 1, 2 do
			local anchor = solid(new("Part", { Name = "IntroLight", Transparency = 1, Size = Vector3.one * 0.1, Parent = cam }))
			local light = new("PointLight", { Brightness = 0, Range = 2.6, Shadows = false, Color = WHITE, Parent = anchor })
			lights[i] = { anchor = anchor, light = light }
			table.insert(cleanup, function()
				anchor:Destroy()
			end)
		end
	else
		-- 2D fallback: a colour wash and a big word with a moving sheen
		fallback = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = holder })
		new("UIGradient", { Rotation = 35, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 32, 190)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(92, 58, 210)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(196, 36, 140)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(238, 112, 40)),
		}), Parent = fallback })
		local word = new("TextLabel", { BackgroundTransparency = 1, Text = INTRO_CREDIT, FontFace = Util.font(Enum.FontWeight.Bold), TextScaled = true, TextColor3 = WHITE, TextTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.24), ZIndex = 2, Parent = holder })
		new("UIGradient", { Name = "Sheen", Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.45, 0.25), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.55, 0.25), NumberSequenceKeypoint.new(1, 0.25) }), Rotation = 20, Offset = Vector2.new(-1, 0), Parent = word })
		fallback:SetAttribute("Word", true)
		Intro.word2d = word
	end

	local start = os.clock()
	local skipAt
	local revealed = false
	local function reveal()
		if not revealed then
			revealed = true
			Util.fire(o.OnReveal)
		end
	end
	local function skip()
		if not skipAt then
			skipAt = os.clock() - start
		end
	end
	catch.Activated:Connect(skip)
	local keyConn = UserInputService.InputBegan:Connect(function(input)
		-- only deliberate keys skip; walking (WASD) or the camera must not
		local k = input.KeyCode
		if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.Escape then
			skip()
		end
	end)
	table.insert(cleanup, function()
		keyConn:Disconnect()
	end)

	local function ease(t)
		t = math.clamp(t, 0, 1)
		return 1 - (1 - t) ^ 3
	end
	-- damped spring step response: 0 -> 1 with a soft liquid overshoot
	local function spring(t, freq, damp)
		if t <= 0 then
			return 0
		end
		local w = freq * 2 * math.pi
		local wd = w * math.sqrt(1 - damp * damp)
		return 1 - math.exp(-damp * w * t) * (math.cos(wd * t) + damp * w / wd * math.sin(wd * t))
	end

	local EXIT, LENGTH = 2.55, 3.35
	Sound.play("intro")
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock() - start
		-- a skip jumps the timeline straight into the exit; fade-ins keep real time
		local t = skipAt and math.max(now, EXIT + (now - skipAt)) or now
		local exitT = math.clamp((t - EXIT) / (LENGTH - EXIT), 0, 1)
		local inT = ease((now - 0.25) / 0.6)
		local out = ease(exitT)
		local s = Library.ScaleObject.Scale
		local vs = cam.ViewportSize
		-- word height: 30% of the screen, never wider than 82% of it
		local frac = 0.3
		local aspect = is3d and (wordSize.X / wordSize.Y) or 2.8
		frac = math.min(frac, 0.82 * vs.X / vs.Y / aspect)
		local wordPx = vs.Y * frac
		local centerY = vs.Y * 0.47

		if is3d then
			cam = workspace.CurrentCamera
			local cf = cam.CFrame
			local bdT = 1 - ease(now / 0.45) + out
			backdrop.Transparency = math.clamp(bdT, 0, 1)
			local hW = viewHeight(WALL)
			backdrop.Size = Vector3.new(hW * vs.X / vs.Y * 1.3, hW * 1.3, 0.05)
			backdrop.CFrame = cf * CFrame.new(math.sin(t * 0.6) * 0.25, math.cos(t * 0.45) * 0.15, -WALL)
			local sp = spring(t - 0.25, 0.9, 0.55)
			local scale = (0.86 + 0.14 * sp) * (1 + 0.12 * out)
			local unit = viewHeight(D) * frac / wordSize.Y * scale
			word3d.Size = wordSize * unit
			local yOff = (vs.Y / 2 - centerY) / vs.Y * viewHeight(D)
			local rotY = -0.42 * (1 - sp) + math.sin(t * 0.9) * 0.05 - 0.04
			local rotX = math.sin(t * 0.7) * 0.03 + 0.08 * (1 - sp)
			local wcf = cf * CFrame.new(0, yOff + 0.05 * (1 - sp), -D + 0.25 * out) * CFrame.Angles(rotX, rotY, 0)
			word3d.CFrame = wcf
			word3d.Transparency = 1 - (1 - 0.2) * inT * (1 - out)
			-- key light top-left; glint light sweeps across the bevels
			local sweep = math.clamp((t - 0.6) / 1.7, 0, 1)
			lights[1].anchor.CFrame = cf * CFrame.new(-0.9, 0.7, -1.4)
			lights[1].light.Brightness = 4.5 * inT * (1 - out)
			lights[2].anchor.CFrame = cf * CFrame.new(-1.8 + 3.6 * sweep, 0.25, -1.9)
			lights[2].light.Brightness = 4 * math.sin(math.pi * sweep) * (1 - out)
		else
			fallback.BackgroundTransparency = math.clamp(1 - ease(now / 0.45) + out, 0, 1)
			local word = Intro.word2d
			word.Size = UDim2.fromOffset(wordPx * 2.8 / s, wordPx / s)
			word.Position = UDim2.fromOffset(vs.X / 2 / s, centerY / s)
			word.TextTransparency = 1 - inT * (1 - out)
			local sheen = word:FindFirstChild("Sheen")
			sheen.Offset = Vector2.new(-1 + 2 * math.clamp((t - 0.6) / 1.7, 0, 1), 0)
		end

		-- labels: "MADE BY" above the word, the script's title below it
		local topY = centerY - wordPx / 2
		made.Position = UDim2.fromOffset(vs.X / 2 / s, (topY - 14 + 6 * (1 - ease((t - 0.55) / 0.5))) / s)
		made.TextTransparency = 1 - 0.85 * ease((t - 0.55) / 0.5) * (1 - out)
		if sub then
			sub.Position = UDim2.fromOffset(vs.X / 2 / s, (centerY + wordPx / 2 + 18 - 6 * (1 - ease((t - 1.05) / 0.5))) / s)
			sub.TextTransparency = 1 - 0.9 * ease((t - 1.05) / 0.5) * (1 - out)
		end
		hint.Position = UDim2.fromOffset(vs.X / 2 / s, (centerY + wordPx / 2 + 76) / s)
		hint.TextTransparency = 1 - 0.55 * ease((t - 1.2) / 0.6) * (1 - out)

		if t >= EXIT + 0.15 then
			reveal()
		end
		if t >= LENGTH then
			conn:Disconnect()
			reveal()
			finish()
		end
	end)
	table.insert(cleanup, function()
		conn:Disconnect()
	end)
	return {
		Skip = skip,
		Finish = function()
			reveal()
			finish()
		end,
	}
end

-- runs fn now, or as soon as the intro is over
function Intro.after(fn)
	if Intro.Active then
		Intro.waiting = Intro.waiting or {}
		table.insert(Intro.waiting, fn)
	else
		fn()
	end
end

-- notifications sent while the intro plays appear right after it
do
	local baseNotify = Library.Notify
	function Library:Notify(o)
		if not Intro.Active then
			return baseNotify(self, o)
		end
		local proxy = { Pending = true }
		function proxy.Close()
			proxy.Cancelled = true
		end
		proxy.Dismiss = proxy.Close
		Intro.after(function()
			if proxy.Cancelled then
				return
			end
			local n = baseNotify(Library, o)
			proxy.Pending = false
			setmetatable(proxy, { __index = n })
			proxy.Close = n.Close
			proxy.Dismiss = n.Close
		end)
		return proxy
	end
end
