-- Prepares the screen for documentation screenshots: hides other players' name
-- tags (locally) and replaces your own name and avatar in LiquidGlass windows.
-- getgenv().LGDocShot.restore() puts everything back.
local Players = game:GetService("Players")
local me = Players.LocalPlayer
local D = getgenv().LGDocShot or {}
getgenv().LGDocShot = D
D.saved = D.saved or {}

function D.hideTags()
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		if ch then
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if hum and D.saved[hum] == nil then
				D.saved[hum] = hum.DisplayDistanceType
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			for _, b in ipairs(ch:GetDescendants()) do
				if b:IsA("BillboardGui") and D.saved[b] == nil then
					D.saved[b] = b.Enabled
					b.Enabled = false
				end
			end
		end
	end
end

-- the game's own screen UI (banners, HUD) hidden locally
function D.hideGameGui()
	for _, g in ipairs(me.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and D.saved[g] == nil then
			D.saved[g] = true
			g.Enabled = false
		end
	end
end

function D.cleanNames(lib)
	lib = lib or getgenv().LiquidGlass
	for _, w in ipairs(lib.Windows) do
		for _, d in ipairs(w.Root:GetDescendants()) do
			if d:IsA("TextLabel") then
				d.Text = d.Text:gsub(me.DisplayName, "Player"):gsub("@" .. me.Name, "@player"):gsub(me.Name, "player")
			elseif d:IsA("ImageLabel") and d.Image:find("id=" .. me.UserId) then
				d.Image = d.Image:gsub("id=" .. me.UserId, "id=156")
			end
		end
	end
end

function D.restore()
	for inst, v in pairs(D.saved) do
		if inst.Parent then
			if inst:IsA("Humanoid") then
				inst.DisplayDistanceType = v
			else
				inst.Enabled = v
			end
		end
	end
	table.clear(D.saved)
end

return D
