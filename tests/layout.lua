-- Layout audit: measures every row, control and the window chrome against the
-- metrics table and reports anything more than half a pixel off.
local lib = getgenv().LiquidGlass
local S = lib.Metrics
local w = lib.Windows[1]
local issues, checked = {}, 0
local function near(a, b, tol)
	return math.abs(a - b) <= (tol or 0.6)
end
local function check(ok, msg)
	checked += 1
	if not ok then
		table.insert(issues, msg)
	end
end
local sc = lib.ScaleObject.Scale
local function pos(g)
	return g.AbsolutePosition / sc
end
local function size(g)
	return g.AbsoluteSize / sc
end
local function midY(g)
	return pos(g).Y + size(g).Y / 2
end
local function right(g)
	return pos(g).X + size(g).X
end

-- window chrome
local root = w.Root
local sb = w.Sidebar.Root
check(near(pos(sb).X - pos(root).X, S.WindowInset) and near(pos(sb).Y - pos(root).Y, S.WindowInset), "sidebar inset")
check(near(pos(root).Y + size(root).Y - (pos(sb).Y + size(sb).Y), S.WindowInset), "sidebar bottom inset")
local brandMid = pos(sb).Y + S.Header / 2
check(near(midY(w.PageTitle), brandMid, 1), string.format("page title center %.1f vs brand %.1f", midY(w.PageTitle), brandMid))
check(near(midY(w.CloseButton.Root), brandMid), "close button center")
check(near(midY(w.MinimizeButton.Root), brandMid), "minimize button center")
check(near(midY(w.AppIcon.Root), brandMid), "app icon center")
local axis = pos(sb).X + S.IconAxis
check(near(pos(w.AppIcon.Root).X + size(w.AppIcon.Root).X / 2, axis), "app icon on icon axis")
for _, t in ipairs(w.Tabs) do
	check(near(pos(t.IconImage).X + size(t.IconImage).X / 2, axis), "tab icon axis " .. t.Title)
	if t.Label.Visible then
		check(near(pos(t.Label).X, pos(sb).X + S.TextAxis), "tab label axis " .. t.Title)
	end
end
if w.TitleLabel.Visible then
	check(near(pos(w.TitleLabel).X, pos(sb).X + S.TextAxis), "brand title on text axis")
end

-- content gutters (left of cards = sidebar edge + gutter, right = window edge - gutter)
local tab = w.ActiveTab
local leftEdge = right(sb) + S.Gutter
local rightEdge = right(root) - S.Gutter
for _, section in ipairs(tab.Sections) do
	if section.Frame.Visible then
		local card = section.Card.Root
		check(near(pos(card).X, leftEdge), string.format("card left %.1f vs %.1f (%s)", pos(card).X, leftEdge, tostring(section.Title)))
		check(near(right(card), rightEdge), string.format("card right %.1f vs %.1f (%s)", right(card), rightEdge, tostring(section.Title)))
		if section.Header.Visible then
			-- header text starts at the row text inset
			local pad = section.Header:FindFirstChildOfClass("UIPadding")
			check(near(pos(section.Header).X + pad.PaddingLeft.Offset, pos(card).X + S.RowInset), "section header inset " .. tostring(section.Title))
		end
		for _, el in ipairs(section.Elements) do
			local row = el.Row
			if row and row.Frame.Visible and el.Type ~= "Divider" and el.Type ~= "Spacer" then
				local f = row.Frame
				local name = el.Type .. " '" .. tostring(el.TitleText) .. "'"
				check(size(f).Y >= S.RowMin - 0.5 or el.Type == "Image" or el.Type == "Segmented", name .. " shorter than RowMin: " .. size(f).Y)
				-- a plain single-line row: the body holds nothing but its title
				local extra = 0
				for _, c in ipairs(row.Body:GetChildren()) do
					if c:IsA("GuiObject") and c ~= row.Title and c ~= row.Desc then
						extra += 1
					end
				end
				local singleLine = row.Title.Visible and not row.Desc.Visible and extra == 0 and el.Type ~= "Paragraph"
				if singleLine and size(row.Title).Y < 20 then
					check(near(size(f).Y, S.RowMin), name .. " single-line height " .. size(f).Y)
					check(near(midY(row.Title), midY(f), 1), string.format("%s title off-center %.1f", name, midY(row.Title) - midY(f)))
				end
				if row.Title.Visible then
					local expectX = pos(f).X + ((row.Badge or row.IconImage) and S.TextX or S.RowInset)
					if el.Type ~= "Image" then
						check(near(pos(row.Title).X, expectX), string.format("%s text x %.1f vs %.1f", name, pos(row.Title).X - pos(f).X, expectX - pos(f).X))
					end
				end
				if row.Badge then
					if extra == 0 then
						check(near(midY(row.Badge), midY(f)), name .. " badge off-center")
					else
						-- stacked rows: level with the title block
						local top = pos(row.Title).Y
						local bottom = row.Desc.Visible and (pos(row.Desc).Y + size(row.Desc).Y) or (top + size(row.Title).Y)
						local blockMid = math.max(bottom - top, S.Badge) / 2 + top
						check(near(midY(row.Badge), blockMid, 1), name .. string.format(" badge %.1f vs title block %.1f", midY(row.Badge), blockMid))
					end
					check(near(pos(row.Badge).X - pos(f).X, S.RowInset), name .. " badge inset")
				end
				-- right accessory: right edge on the inset, vertically centered
				local visibleRight = false
				for _, c in ipairs(row.Right:GetChildren()) do
					if c:IsA("GuiObject") and c.Visible then
						visibleRight = true
					end
				end
				if visibleRight and size(row.Right).X > 0 then
					check(near(right(row.Right), right(f) - S.RowInset), name .. " right inset " .. (right(f) - right(row.Right)))
					check(near(midY(row.Right), midY(f)), name .. " right control off-center")
					for _, c in ipairs(row.Right:GetChildren()) do
						if c:IsA("Frame") and (c.Name == "Field" or c.Name == "Key" or c.Name == "Control") then
							check(near(size(c).Y, S.Control), name .. " control height " .. size(c).Y)
						end
					end
				end
				local value = f:FindFirstChild("Value")
				if value and row.Title.Visible then
					check(near(pos(value).Y, pos(row.Title).Y), name .. " value not level with title")
				end
				for _, cap in ipairs(f:GetDescendants()) do
					if cap.Name == "Capsule" and cap:IsA("Frame") then
						local h = size(cap).Y
						check(near(h, S.Button) or near(h, S.ButtonSmall) or near(h, S.ButtonLarge), name .. " capsule height " .. h)
						-- centered in its row with equal margins above and below
						check(near(pos(cap).Y - pos(f).Y, (size(f).Y - h) / 2), name .. " capsule not centered in row")
					end
				end
			end
		end
	end
end
return string.format("%d checks on tab %s, %d issues\n%s", checked, tab.Title, #issues, table.concat(issues, "\n"))
