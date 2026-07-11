--[[
  Mine Hub v4 — Axel Hub style
  All logic defined first, UI second
]]

local player = game.Players.LocalPlayer
local rs = game:GetService("ReplicatedStorage")
local tw = game:GetService("TweenService")
local ws = workspace
local rs2 = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local remotes = rs.Remotes

local DigRequest = remotes:FindFirstChild("DigRequest")
local CrystalMinePrompt = remotes:FindFirstChild("CrystalMinePrompt")
local CrystalHoldComplete = remotes:FindFirstChild("CrystalHoldComplete")
local CrystalDroppedPickup = remotes:FindFirstChild("CrystalDroppedPickup")
local SellRequest = remotes:FindFirstChild("SellRequest")
local SellResult = remotes:FindFirstChild("SellResult")
local BombBuyRequest = remotes:FindFirstChild("BombBuyRequest")
local BombShopQuery = remotes:FindFirstChild("BombShopQuery")
local BombShopRestocked = remotes:FindFirstChild("BombShopRestocked")

local ls = player:FindFirstChild("leaderstats")
local cashVal
if ls then
  for _, v in pairs(ls:GetChildren()) do
    local n = v.Name:lower()
    if n:find("cash") or n:find("coin") or n:find("money") then cashVal = v end
  end
end

-- ══════════════════════════════════════════════════════════════
--  DATA & CONFIG
-- ══════════════════════════════════════════════════════════════

local bombs = {
  {id="ClassicBomb", name="Classic Bomb", rarity="Common", price=50000, r=180,g=180,b=180},
  {id="WindBomb", name="Wind Bomb", rarity="Common", price=400000, r=135,g=206,b=235},
  {id="IceBomb", name="Ice Bomb", rarity="Uncommon", price=2000000, r=0,g=191,b=255},
  {id="FireBomb", name="Fire Bomb", rarity="Uncommon", price=5000000, r=255,g=69,b=0},
  {id="ThunderBomb", name="Thunder Bomb", rarity="Rare", price=15000000, r=255,g=215,b=0},
  {id="PoisonBomb", name="Poison Bomb", rarity="Epic", price=40000000, r=148,g=0,b=211},
  {id="TimeBomb", name="Time Bomb", rarity="Legendary", price=175000000, r=0,g=255,b=127},
  {id="AgonyBomb", name="Agony Bomb", rarity="Mythic", price=600000000, r=255,g=0,b=60},
}

local autoBombConfig = {Epic="PoisonBomb", Legendary="TimeBomb", Mythic="AgonyBomb"}
local autoBombEnabled = false
local farming = false
local noCrystalTimer = 0
local skippedCrystals = {}
local failedCrystals = {}
local failedCount = {}
local statsCrystals = 0
local statsValue = 0
local statsBombs = 0
local statsStart = 0
local digTimeoutTicks = 500
local espEnabled = false
local hopEnabled = false
local hopTimer = 0
local sellOn = false
local smartSellOn = false
local antiRagdollEnabled = false
local antiRagdollCons = {}
local rarityTogState = {}
local sizeTogState = {}
local bombTogState = {}

local espFolder = Instance.new("Folder"); espFolder.Name = "CrystalESP"; espFolder.Parent = player.PlayerGui
local highlightBox = Instance.new("SelectionBox"); highlightBox.Color3 = Color3.fromRGB(80,210,130); highlightBox.LineThickness = 0.03; highlightBox.SurfaceColor3 = Color3.fromRGB(80,210,130); highlightBox.Visible = false; highlightBox.Parent = player.PlayerGui

local gui -- set when GUI is created

-- ══════════════════════════════════════════════════════════════
--  ALL UTILITY FUNCTIONS
-- ══════════════════════════════════════════════════════════════

local function getMoney()
  if not cashVal then return 999999999 end
  local v = cashVal.Value
  if type(v) == "number" then return v end
  local s = tostring(v):gsub("%$",""):gsub(",","")
  if s:find("T") then return tonumber(s:match("([%d%.]+)T"))*1e12
  elseif s:find("B") then return tonumber(s:match("([%d%.]+)B"))*1e9
  elseif s:find("M") then return tonumber(s:match("([%d%.]+)M"))*1e6
  elseif s:find("K") then return tonumber(s:match("([%d%.]+)K"))*1e3
  else return tonumber(s) or 0 end
end

local function fmtPrice(n)
  if n >= 1e12 then return string.format("%.1fT", n/1e12)
  elseif n >= 1e9 then return string.format("%.1fB", n/1e9)
  elseif n >= 1e6 then return string.format("%.0fM", n/1e6)
  elseif n >= 1e3 then return string.format("%.0fK", n/1e3)
  else return tostring(n) end
end

local function getMaxWeight()
  local pd = player:FindFirstChild("PlayerData")
  local s = pd and pd:FindFirstChild("RealStats")
  local cw = s and s:FindFirstChild("CarryWeight")
  return cw and cw.Value or 100
end

local function getUsedWeight()
  local bp = player:FindFirstChild("Backpack")
  if not bp then return 0 end
  local t = 0
  for _, tool in pairs(bp:GetChildren()) do t = t + (tonumber(tool:GetAttribute("WeightKg")) or 0) end
  return t
end

local SIZE_RANK = {["Tiny"]=1, ["Small"]=2, ["S"]=2, ["Medium"]=3, ["M"]=3, ["Large"]=4, ["L"]=4, ["XL"]=5, ["Huge"]=6, ["Giant"]=7, ["Colossal"]=8, ["Leviathan"]=9, ["Titan"]=10}
local function getCrystalSizes()
  local sz = {}
  for _, obj in pairs(ws:GetDescendants()) do
    if (obj:IsA("MeshPart") or obj:IsA("Part")) and obj:GetAttribute("TierName") then
      local p = obj:GetFullName()
      if p:find("Plots") or p:find("PlacedCrystals") then continue end
      local s = obj:GetAttribute("SizeClass")
      if s then sz[tostring(s)] = true end
    end
  end
  local sorted = {}
  for s in pairs(sz) do table.insert(sorted, s) end
  table.sort(sorted, function(a, b)
    local rA = SIZE_RANK[a] or 99
    local rB = SIZE_RANK[b] or 99
    if rA ~= rB then return rA > rB end
    return a < b
  end)
  return sorted
end

local function findBombInBackpack(bid)
  local bp = player:FindFirstChild("Backpack")
  if bp then for _, t in pairs(bp:GetChildren()) do if t:IsA("Tool") and t.Name == bid then return t end end end
  local ch = player.Character
  if ch then for _, t in pairs(ch:GetChildren()) do if t:IsA("Tool") and t.Name == bid then return t end end end
  return nil
end

local function equipBomb(bid)
  local tool = findBombInBackpack(bid)
  if not tool then return false end
  local ch = player.Character
  if not ch then return false end
  tool.Parent = ch; wait(0.2); return true
end

local function useBomb(pos)
  local ch = player.Character
  local root = ch and ch:FindFirstChild("HumanoidRootPart")
  if not root then return false end
  local eq = nil
  for _, t in pairs(ch:GetChildren()) do if t:IsA("Tool") then eq = t; break end end
  if not eq then return false end
  root.CFrame = CFrame.new(pos + Vector3.new(0,3,0))
  root.Velocity = Vector3.new(0,0,0)
  wait(0.1)
  pcall(function() eq:Activate() end)
  print("[Hub] Bomb armed: "..eq.Name)
  wait(3)
  return true
end

local function unequipBomb()
  local ch = player.Character; if not ch then return end
  local bp = player:FindFirstChild("Backpack"); if not bp then return end
  for _, t in pairs(ch:GetChildren()) do
    if t:IsA("Tool") then for _, bm in ipairs(bombs) do if t.Name == bm.id then t.Parent = bp; return end end end
  end
end

local function buyBomb(id)
  if not BombBuyRequest then return end
  local ok, res = pcall(function() return BombBuyRequest:InvokeServer(id) end)
  if ok and res and res.ok then print("[Hub] Bought "..id) end
end

local function scoreCrystal(c) return tonumber(c:GetAttribute("Value") or 0) or 0 end

local function findBestCrystal()
  local bestScore, bestCrystal = -1, nil
  local char = player.Character
  local root = char and char:FindFirstChild("HumanoidRootPart")
  if not root then return nil end
  local maxW, used = getMaxWeight(), getUsedWeight()
  local now = tick()
  for obj, expire in pairs(skippedCrystals) do if now >= expire then skippedCrystals[obj] = nil end end
  for _, obj in pairs(ws:GetDescendants()) do
    if (obj:IsA("MeshPart") or obj:IsA("Part")) and obj:GetAttribute("TierName") then
      local path = obj:GetFullName()
      if path:find("Plots") or path:find("PlacedCrystals") or skippedCrystals[obj] or failedCrystals[obj] then continue end
      local tier = obj:GetAttribute("TierName")
      if tier and rarityTogState[tier] then
        local sz = obj:GetAttribute("SizeClass")
        if sz and sizeTogState[tostring(sz)] then
          local weight = tonumber(obj:GetAttribute("WeightKg") or 0) or 0
          if used + weight > maxW then continue end
          local s = scoreCrystal(obj)
          if s > bestScore then bestScore = s; bestCrystal = obj end
        end
      end
    end
  end
  return bestCrystal, bestScore
end

local sellPos = nil
local function findSellArea()
  if sellPos then return sellPos end
  for _, obj in pairs(ws:GetDescendants()) do
    if obj:IsA("Model") then
      local n = obj.Name:lower()
      if n:find("sell") or n:find("buyer") or n:find("vendor") or n:find("crystalbuyer") then
        local ok, cf = pcall(obj.GetBoundingBox, obj)
        if ok then sellPos = cf.Position; return sellPos end
      end
    elseif obj:IsA("Part") then
      local n = obj.Name:lower()
      if n:find("sell") or n:find("buyer") or n:find("vendor") or n:find("crystalbuyer") then
        sellPos = obj.Position; return sellPos
      end
    end
  end
  for _, p in pairs(ws:GetDescendants()) do
    if p:IsA("SpawnLocation") then sellPos = p.Position; return sellPos end
  end
  return nil
end

local sellPart, sellPrompt = nil, nil
local function getSellPrompt()
  if sellPart and sellPrompt then return sellPart, sellPrompt end
  for _, v in pairs(workspace:GetDescendants()) do
    if v:IsA("BasePart") and v.Name:lower():find("sellprox") then
      sellPart = v
      for _, c in pairs(v:GetDescendants()) do if c:IsA("ProximityPrompt") then sellPrompt = c end end
      return sellPart, sellPrompt
    end
  end
  return nil, nil
end

local statusText = "Idle"
local bpText = "0 / 0 kg"

local function doSell()
  local used = getUsedWeight()
  if used <= 0 then return false end
  local char = player.Character
  local root = char and char:FindFirstChild("HumanoidRootPart")
  if not root then return false end
  statusText = "Selling..."
  print("[Hub] Selling...")
  local sp, prompt = getSellPrompt()
  if not sp then
    local area = findSellArea()
    if not area then print("[Hub] No sell area found"); return false end
    root.CFrame = CFrame.new(area + Vector3.new(0, 3, 0))
    root.Velocity = Vector3.new(0,0,0)
  else
    root.CFrame = CFrame.new(sp.Position + Vector3.new(0, 0, 2))
    root.Velocity = Vector3.new(0,0,0)
  end
  wait(0.1)
  local resultCount = 0
  local con
  if SellResult then
    con = SellResult.OnClientEvent:Connect(function(...)
      resultCount = resultCount + 1
    end)
  end
  if prompt then
    pcall(function() fireproximityprompt(prompt) end)
    wait(0.1)
    if resultCount == 0 then
      pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        wait(0.02)
        vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
      end)
      wait(0.15)
    end
  end
  local waited = 0
  while resultCount < 1 and waited < 1.5 do wait(0.1); waited = waited + 0.1 end
  if resultCount == 0 and prompt then pcall(function() fireproximityprompt(prompt) end) end
  if SellRequest then
    pcall(function() SellRequest:FireServer() end)
    pcall(function() SellRequest:FireServer({action = "all"}) end)
    pcall(function() SellRequest:FireServer("all") end)
    pcall(function() SellRequest:FireServer("SellAll") end)
  end
  wait(0.1)
  waited = 0
  while resultCount < 2 and waited < 0.8 do wait(0.05); waited = waited + 0.05 end
  if con then pcall(con.Disconnect, con); con = nil end
  statusText = getUsedWeight() < used and "Sold!" or "Sell failed"
  return getUsedWeight() < used
end

local function waitForRespawn()
  for i = 1, 60 do
    if not farming then return false end
    local char = player.Character
    if char and char:FindFirstChild("Humanoid") then
      local hum = char:FindFirstChild("Humanoid")
      if hum and hum.Health > 0 then return true end
    end
    pcall(function()
      for _, g in pairs(player.PlayerGui:GetDescendants()) do
        if g:IsA("TextButton") and g.Visible and g.AbsoluteSize.X > 0 then
          local t = (g.Text or ""):lower()
          if t:find("respawn") or t:find("revive") or t:find("spawn") then
            local vim = game:GetService("VirtualInputManager")
            local x, y = g.AbsolutePosition.X + g.AbsoluteSize.X/2, g.AbsolutePosition.Y + g.AbsoluteSize.Y/2
            vim:SendMouseButtonEvent(x, y, 0, true, game, 0); wait(0.05)
            vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
          end
        end
      end
    end)
    pcall(function() player:LoadCharacter() end)
    wait(0.5)
  end
  return false
end

local function applyAntiRagdoll()
  for _, c in pairs(antiRagdollCons) do pcall(c.Disconnect, c) end
  antiRagdollCons = {}
  local char = player.Character
  if not char then return end
  local hum = char:FindFirstChild("Humanoid")
  local root = char:FindFirstChild("HumanoidRootPart")
  if not hum then return end
  antiRagdollEnabled = true
  local hb
  hb = rs2.Heartbeat:Connect(function()
    if not antiRagdollEnabled or not hum or not hum.Parent then if hb then hb:Disconnect() end; return end
    pcall(function()
      hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
      hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
      hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
      hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
      local s = hum:GetState()
      if s ~= Enum.HumanoidStateType.Running and s ~= Enum.HumanoidStateType.RunningNoPhysics then hum:ChangeState(Enum.HumanoidStateType.Running) end
      if hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end
      if root and root.Velocity.Y < -20 then root.Velocity = Vector3.new(root.Velocity.X, -10, root.Velocity.Z) end
    end)
  end)
  table.insert(antiRagdollCons, hb)
end

local function clearAntiRagdoll()
  antiRagdollEnabled = false
  for _, c in pairs(antiRagdollCons) do pcall(c.Disconnect, c) end
  antiRagdollCons = {}
end

local function updateESP()
  for _, c in pairs(espFolder:GetChildren()) do c:Destroy() end
  if not espEnabled then return end
  local char = player.Character
  local root = char and char:FindFirstChild("HumanoidRootPart")
  if not root then return end
  for _, obj in pairs(ws:GetDescendants()) do
    if (obj:IsA("MeshPart") or obj:IsA("Part")) and obj:GetAttribute("TierName") then
      local path = obj:GetFullName()
      if not path:find("Plots") and not path:find("PlacedCrystals") then
        local tier = obj:GetAttribute("TierName") or "?"
        local val = obj:GetAttribute("Value") or 0
        local dist = math.floor((obj.Position - root.Position).Magnitude)
        if dist <= 200 then
          local rarityColors = {
            Common=Color3.fromRGB(160,160,175), Uncommon=Color3.fromRGB(60,180,255),
            Rare=Color3.fromRGB(60,230,200), Epic=Color3.fromRGB(160,80,255),
            Legendary=Color3.fromRGB(255,200,50), Mythic=Color3.fromRGB(255,60,80),
          }
          local bb = Instance.new("BillboardGui")
          bb.Size = UDim2.new(0, 140, 0, 26)
          bb.StudsOffset = Vector3.new(0, 3, 0)
          bb.AlwaysOnTop = true
          bb.Adornee = obj
          bb.Parent = espFolder
          local tl = Instance.new("TextLabel")
          tl.Size = UDim2.new(1, 0, 1, 0)
          tl.BackgroundTransparency = 0.3
          tl.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
          tl.Text = tier.."  $"..fmtPrice(val).."  ["..dist.."m]"
          tl.TextColor3 = rarityColors[tier] or Color3.new(1,1,1)
          tl.TextSize = 11
          tl.Font = Enum.Font.GothamBold
          tl.Parent = bb
          local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = tl
        end
      end
    end
  end
end

-- MAIN FARM LOOP
local function farmLoop()
  while farming do
    local char = player.Character
    local hum = char and char:FindFirstChild("Humanoid")
    if not char or not hum or hum.Health <= 0 then
      statusText = "Dead — respawning"
      if waitForRespawn() then statusText = "Respawned"; wait(1)
      else statusText = "Respawn failed" end
      continue
    end
    local maxW = getMaxWeight()
    local used = getUsedWeight()
    bpText = string.format("%.1f / %d kg", used, maxW)
    if used >= maxW then
      if sellOn and doSell() then statusText = "Sold!"
      else statusText = "Backpack full"; wait(0.5) end
      continue
    end
    local crystal = findBestCrystal()
    if not crystal then
      noCrystalTimer = noCrystalTimer + 0.5
      if noCrystalTimer >= 20 then
        if sellOn and getUsedWeight() > 0 then doSell() end
        noCrystalTimer = 0; continue
      end
      statusText = "No qualified crystals"; wait(0.5); continue
    end
    noCrystalTimer = 0
    local tier = crystal:GetAttribute("TierName") or "?"
    local sz = crystal:GetAttribute("SizeClass") or "?"

    -- Smart auto sell: if best target won't fit due to weight, sell lesser carried items
    if smartSellOn then
      local targetWeight = tonumber(crystal:GetAttribute("WeightKg") or 0) or 0
      local targetValue = scoreCrystal(crystal)
      local used = getUsedWeight()
      local max = getMaxWeight()
      if used + targetWeight > max then
        -- Collect backpack tools with their value/weight
        local bp = player:FindFirstChild("Backpack")
        if bp then
          local held = {}
          for _, t in pairs(bp:GetChildren()) do
            if t:IsA("Tool") then
              held[#held+1] = {tool=t, value=tonumber(t:GetAttribute("Value")) or 0, weight=tonumber(t:GetAttribute("WeightKg")) or 0}
            end
          end
          -- Score each: drop lowest value-per-weight first
          table.sort(held, function(a, b)
            local sA = a.value / math.max(a.weight, 0.001)
            local sB = b.value / math.max(b.weight, 0.001)
            return sA < sB
          end)
          -- Sell target's divinity: target value should be >= sum of lowest held items to justify it
          local freedWeight = 0
          local soldValue = 0
          local toSell = {}
          for _, item in ipairs(held) do
            if used - freedWeight + targetWeight <= max then break end
            toSell[#toSell+1] = item.tool
            freedWeight = freedWeight + item.weight
            soldValue = soldValue + item.value
          end
          -- Only smart-sell if target's value (with priority: value + weight*10) exceeds the sold items
          local targetScore = targetValue + targetWeight * 10
          if targetScore > soldValue and #toSell > 0 then
            statusText = "Smart sell " .. #toSell .. " items"
            doSell()
            wait(0.3)
            -- Re-evaluate targets
            local newCrystal = findBestCrystal()
            if newCrystal then crystal = newCrystal end
          end
        end
      end
    end

    if autoBombEnabled then
      local bombId = autoBombConfig[tier]
      if bombId then
        local bombData = nil
        for _, bm in ipairs(bombs) do if bm.id == bombId then bombData = bm; break end end
        if bombData then
          local owned = findBombInBackpack(bombId)
          if not owned and getMoney() >= bombData.price then
            statusText = "Buying "..bombData.name; buyBomb(bombId); wait(0.5)
          end
          owned = findBombInBackpack(bombId)
          if owned then
            statusText = "Bombing "..tier
            if equipBomb(bombId) then useBomb(crystal.Position); statsBombs = statsBombs + 1; wait(1); unequipBomb(); wait(0.5) end
            highlightBox.Visible = false; continue
          end
        end
      end
    end

    statusText = "Moving to "..tier.." ("..sz..")"
    highlightBox.Adornee = crystal; highlightBox.Visible = true
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then highlightBox.Visible = false; wait(1); continue end
    -- Direct TP to crystal position (no ground snap) — bypasses barriers, gates, walls
    local digPos = crystal.Position + Vector3.new(0, 2, 0)
    root.CFrame = CFrame.new(digPos)
    root.Velocity = Vector3.new(0,0,0)
    wait(0.5)
    -- Verify teleport actually took: if character didn't move close to digPos, region is likely unloaded/slow-streaming — skip with long timeout
    if not root or not root.Parent or not root:IsDescendantOf(workspace) then
      highlightBox.Visible = false; continue
    end
    local tpDist = (root.Position - digPos).Magnitude
    if tpDist > 100 then
      statusText = "Region not loaded — skip 60s"
      skippedCrystals[crystal] = tick() + 60
      highlightBox.Visible = false; continue
    end
    -- Snap to exact digPos if landed nearby (server sometimes nudges by a few studs)
    root.CFrame = CFrame.new(digPos); root.Velocity = Vector3.new(0,0,0)
    statusText = "Digging "..tier
    local holdPos = true
    spawn(function()
      while holdPos and root and root.Parent do
        if (root.Position - digPos).Magnitude > 3 then
          -- Check if character is "stuck" far away (region stream failed mid-dig) — don't keep snapping
          local d = (root.Position - digPos).Magnitude
          if d > 100 then
            break
          end
          root.CFrame = CFrame.new(digPos)
          root.Velocity = Vector3.new(0,0,0)
        end
        wait(0.15)
      end
    end)
    if CrystalMinePrompt then pcall(function() CrystalMinePrompt:FireServer(crystal) end) end
    if CrystalHoldComplete then pcall(function() CrystalHoldComplete:FireServer(crystal) end) end
    if DigRequest then for _ = 1, 5 do pcall(function() DigRequest:FireServer(crystal) end) end end
    local lastMinedHP = crystal:GetAttribute("MinedHP") or 0
    local noChangeTick, dug = 0, false
    -- Scale timeout by crystal size: bigger crystals need way more hits
    local sizeKey = crystal:GetAttribute("SizeClass") or ""
    local sizeMult = 1
    if sizeKey == "Titan" then sizeMult = 3
    elseif sizeKey == "Leviathan" or sizeKey == "Colossal" then sizeMult = 2.5
    elseif sizeKey == "Giant" then sizeMult = 2
    elseif sizeKey == "XL" then sizeMult = 1.5
    elseif sizeKey == "Large" or sizeKey == "L" then sizeMult = 1.2
    end
    local scaledTimeout = math.floor(digTimeoutTicks * sizeMult)
    for tick = 1, 1500 do
      wait(0.15)
      if not farming then break end
      if getUsedWeight() >= getMaxWeight() then dug = true; break end
      local hp = crystal:GetAttribute("MinedHP")
      if hp and hp < lastMinedHP then
        lastMinedHP = hp
        noChangeTick = 0
      end
      if hp and hp <= 0 then dug = true; break end
      noChangeTick = noChangeTick + 1
      if noChangeTick > scaledTimeout then break end
      if DigRequest then for _ = 1, 5 do pcall(function() DigRequest:FireServer(crystal) end) end end
      if CrystalHoldComplete then pcall(function() CrystalHoldComplete:FireServer(crystal) end) end
    end
    holdPos = false
    if dug then statsCrystals = statsCrystals + 1; statsValue = statsValue + scoreCrystal(crystal)
    else
      failedCount[crystal] = (failedCount[crystal] or 0) + 1
      if failedCount[crystal] >= 3 then
        failedCrystals[crystal] = true
      elseif failedCount[crystal] == 2 then
        skippedCrystals[crystal] = tick() + 60
      else
        skippedCrystals[crystal] = tick() + 15
      end
    end
    highlightBox.Visible = false
  end
end

-- ══════════════════════════════════════════════════════════════
--  UI LAYER — Axel Hub 1:1
-- ══════════════════════════════════════════════════════════════

local BG       = Color3.fromRGB(17, 17, 24)
local SIDEBAR  = Color3.fromRGB(13, 13, 19)
local HEADER   = Color3.fromRGB(11, 11, 16)
local CARD     = Color3.fromRGB(22, 22, 30)
local CARD2    = Color3.fromRGB(28, 28, 38)
local BORDER   = Color3.fromRGB(35, 35, 48)
local ACCENT   = Color3.fromRGB(212, 165, 71)
local GREEN    = Color3.fromRGB(80, 210, 130)
local RED      = Color3.fromRGB(235, 65, 75)
local TXT      = Color3.fromRGB(240, 240, 248)
local TXTDIM   = Color3.fromRGB(150, 150, 170)
local TXTMUTE  = Color3.fromRGB(80, 80, 105)
local DIVIDER  = Color3.fromRGB(30, 30, 42)

local FT = Enum.Font.Highway
local FB = Enum.Font.GothamBold
local FR = Enum.Font.Gotham
local FM = Enum.Font.GothamMedium
local FC = Enum.Font.Code

local function corner(p, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=p; return c end
local function padding(p, t, b, l, r)
  local p2=Instance.new("UIPadding")
  p2.PaddingTop=UDim.new(0,t or 0); p2.PaddingBottom=UDim.new(0,b or 0)
  p2.PaddingLeft=UDim.new(0,l or 0); p2.PaddingRight=UDim.new(0,r or 0)
  p2.Parent=p; return p2
end

gui = Instance.new("ScreenGui")
gui.Name = "AxelHub"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
gui.Parent = player.PlayerGui

-- ═══ MAIN FRAME (compact: 480x380, like original but 22% smaller) ═══
local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 480, 0, 380)
main.Position = UDim2.new(0.5, -240, 0.5, -190)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Active = true
main.Parent = gui
corner(main, 10)

-- ═══ HEADER BAR (compact: 36px, rounded to match main) ═══
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = HEADER
header.BorderSizePixel = 0
header.ZIndex = 10
header.Parent = main
header.ClipsDescendants = true
corner(header, 10)

-- 1px divider at the very bottom of the header (placed OUTSIDE header so corner clipping is clean)
local headerShadow = Instance.new("Frame")
headerShadow.Name = "HeaderShadow"
headerShadow.Size = UDim2.new(1, -20, 0, 1)
headerShadow.Position = UDim2.new(0, 10, 0, 36)
headerShadow.BackgroundColor3 = BORDER
headerShadow.BorderSizePixel = 0
headerShadow.ZIndex = 9
headerShadow.Parent = main

local logoIcon = Instance.new("Frame")
logoIcon.Size = UDim2.new(0, 24, 0, 24)
logoIcon.Position = UDim2.new(0, 10, 0.5, -12)
logoIcon.BackgroundColor3 = ACCENT
logoIcon.BorderSizePixel = 0
logoIcon.ZIndex = 12
logoIcon.Parent = header
corner(logoIcon, 6)

local logoIconTxt = Instance.new("TextLabel")
logoIconTxt.Size = UDim2.new(1, 0, 1, 0)
logoIconTxt.BackgroundTransparency = 1
logoIconTxt.Text = "M"
logoIconTxt.TextColor3 = Color3.fromRGB(17, 17, 24)
logoIconTxt.TextSize = 13
logoIconTxt.Font = FT
logoIconTxt.ZIndex = 13
logoIconTxt.Parent = logoIcon

local logoText = Instance.new("TextLabel")
logoText.Size = UDim2.new(0, 150, 0, 14)
logoText.Position = UDim2.new(0, 40, 0, 5)
logoText.BackgroundTransparency = 1
logoText.Text = "Sporplut's Hub"
logoText.TextColor3 = TXT
logoText.TextSize = 12
logoText.Font = FT
logoText.TextXAlignment = Enum.TextXAlignment.Left
logoText.TextYAlignment = Enum.TextYAlignment.Center
logoText.ZIndex = 12
logoText.Parent = header

local logoVer = Instance.new("TextLabel")
logoVer.Size = UDim2.new(0, 150, 0, 11)
logoVer.Position = UDim2.new(0, 40, 0, 20)
logoVer.BackgroundTransparency = 1
logoVer.Text = "by Sporplut"
logoVer.TextColor3 = TXTMUTE
logoVer.TextSize = 9
logoVer.Font = FR
logoVer.TextXAlignment = Enum.TextXAlignment.Left
logoVer.TextYAlignment = Enum.TextYAlignment.Center
logoVer.ZIndex = 12
logoVer.Parent = header

-- Right side: green pill + version pill + min + close (compact)
local greenPill = Instance.new("Frame")
greenPill.Size = UDim2.new(0, 46, 0, 18)
greenPill.Position = UDim2.new(1, -164, 0.5, -9)
greenPill.BackgroundColor3 = Color3.fromRGB(30, 70, 45)
greenPill.BorderSizePixel = 0
greenPill.ZIndex = 12
greenPill.Parent = header
corner(greenPill, 5)

local greenTxt = Instance.new("TextLabel")
greenTxt.Size = UDim2.new(1, 0, 1, 0)
greenTxt.BackgroundTransparency = 1
greenTxt.Text = "Hub"
greenTxt.TextColor3 = GREEN
greenTxt.TextSize = 9
greenTxt.Font = FB
greenTxt.TextYAlignment = Enum.TextYAlignment.Center
greenTxt.ZIndex = 13
greenTxt.Parent = greenPill

local verPill = Instance.new("Frame")
verPill.Size = UDim2.new(0, 48, 0, 18)
verPill.Position = UDim2.new(1, -114, 0.5, -9)
verPill.BackgroundColor3 = Color3.fromRGB(30, 60, 80)
verPill.BorderSizePixel = 0
verPill.ZIndex = 12
verPill.Parent = header
corner(verPill, 5)

local verIcon = Instance.new("TextLabel")
verIcon.Size = UDim2.new(0, 12, 0, 12)
verIcon.Position = UDim2.new(0, 5, 0.5, -6)
verIcon.BackgroundTransparency = 1
verIcon.Text = "⚙"
verIcon.TextSize = 9
verIcon.TextColor3 = Color3.fromRGB(100, 180, 220)
verIcon.TextYAlignment = Enum.TextYAlignment.Center
verIcon.ZIndex = 13
verIcon.Parent = verPill

local verTxt = Instance.new("TextLabel")
verTxt.Size = UDim2.new(1, -22, 1, 0)
verTxt.Position = UDim2.new(0, 20, 0, 0)
verTxt.BackgroundTransparency = 1
verTxt.Text = "1.0.0"
verTxt.TextColor3 = Color3.fromRGB(100, 180, 220)
verTxt.TextSize = 9
verTxt.Font = FB
verTxt.TextXAlignment = Enum.TextXAlignment.Left
verTxt.TextYAlignment = Enum.TextYAlignment.Center
verTxt.ZIndex = 13
verTxt.Parent = verPill

local minimized = false
local fullHeight = 380
local headerHeight = 36

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 24, 0, 24)
minBtn.Position = UDim2.new(1, -62, 0.5, -12)
minBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
minBtn.BackgroundTransparency = 0.5
minBtn.Text = ""
minBtn.ZIndex = 13
minBtn.Parent = header
corner(minBtn, 12)

local minLine = Instance.new("Frame")
minLine.Size = UDim2.new(0, 9, 0, 1.6)
minLine.Position = UDim2.new(0.5, -4.5, 0.5, -0.8)
minLine.BackgroundColor3 = TXTDIM
minLine.BorderSizePixel = 0
minLine.ZIndex = 14
minLine.Parent = minBtn

local minLineV = Instance.new("Frame")
minLineV.Size = UDim2.new(0, 1.6, 0, 0)
minLineV.Position = UDim2.new(0.5, -0.8, 0.5, -4)
minLineV.BackgroundColor3 = TXTDIM
minLineV.BorderSizePixel = 0
minLineV.ZIndex = 14
minLineV.Parent = minBtn

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -32, 0.5, -12)
closeBtn.BackgroundColor3 = RED
closeBtn.BackgroundTransparency = 0.7
closeBtn.Text = ""
closeBtn.ZIndex = 13
closeBtn.Parent = header
corner(closeBtn, 12)

local closeX1 = Instance.new("Frame")
closeX1.Size = UDim2.new(0, 10, 0, 1.6)
closeX1.Position = UDim2.new(0.5, -5, 0.5, -0.8)
closeX1.BackgroundColor3 = RED
closeX1.BorderSizePixel = 0
closeX1.Rotation = 45
closeX1.ZIndex = 14
closeX1.Parent = closeBtn

local closeX2 = Instance.new("Frame")
closeX2.Size = UDim2.new(0, 10, 0, 1.6)
closeX2.Position = UDim2.new(0.5, -5, 0.5, -0.8)
closeX2.BackgroundColor3 = RED
closeX2.BorderSizePixel = 0
closeX2.Rotation = -45
closeX2.ZIndex = 14
closeX2.Parent = closeBtn

closeBtn.Activated:Connect(function() farming = false; gui:Destroy() end)

minBtn.Activated:Connect(function()
  minimized = not minimized
  if minimized then
    tw:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 480, 0, headerHeight)}):Play()
    if sidebar then sidebar.Visible = false end
    if contentArea then contentArea.Visible = false end
    tw:Create(minLineV, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 1.6, 0, 9), Position = UDim2.new(0.5, -0.8, 0.5, -4)}):Play()
  else
    tw:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 480, 0, fullHeight)}):Play()
    delay(0.15, function()
      if sidebar then sidebar.Visible = true end
      if contentArea then contentArea.Visible = true end
    end)
    tw:Create(minLineV, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 1.6, 0, 0), Position = UDim2.new(0.5, -0.8, 0.5, -4)}):Play()
  end
end)

-- ═══ CUSTOM DRAG (header-based) ═══
do
  local dragging, dragStart, startPos
  header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging = true
      dragStart = input.Position
      startPos = main.Position
    end
  end)
  uis.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
      local delta = input.Position - dragStart
      main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
  end)
  uis.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging = false
    end
  end)
end

-- ═══ RESIZE GRIP (bottom-right, click & drag to resize) ═══
do
  -- 28x28 visible button with diagonal stripes (whole thing is the hit zone)
  local resizeBtn = Instance.new("TextButton")
  resizeBtn.Name = "ResizeGrip"
  resizeBtn.Size = UDim2.new(0, 28, 0, 28)
  resizeBtn.Position = UDim2.new(1, -28, 1, -28)
  resizeBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
  resizeBtn.BackgroundTransparency = 0.4
  resizeBtn.BorderSizePixel = 0
  resizeBtn.Text = ""
  resizeBtn.AutoButtonColor = false
  resizeBtn.Active = true
  resizeBtn.ZIndex = 60
  resizeBtn.Parent = main
  corner(resizeBtn, 8)

  -- Diagonal grip stripes (children of the button, so click-friendly)
  for i = 0, 2 do
    local line = Instance.new("Frame")
    line.Name = "GripLine"
    line.Size = UDim2.new(0, 14, 0, 1.6)
    line.Position = UDim2.new(1, -(22 - i * 5), 1, -(9 + i * 5))
    line.BackgroundColor3 = Color3.fromRGB(210, 210, 225)
    line.BorderSizePixel = 0
    line.Rotation = -45
    line.ZIndex = 61
    line.Parent = main
  end

  local resizing = false
  local resizeStart, sizeStart
  local MIN_W, MIN_H = 360, 280
  local MAX_W, MAX_H = 900, 700

  -- PRIMARY: input on the button itself
  resizeBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      resizing = true
      resizeStart = Vector2.new(input.Position.X, input.Position.Y)
      sizeStart = main.Size
    end
  end)

  -- FALLBACK: catch press on the button's bbox via uis.InputBegan (always works)
  uis.InputBegan:Connect(function(input)
    if resizing then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    if minimized then return end
    if not resizeBtn.Visible then return end
    local ap = resizeBtn.AbsolutePosition
    local as = resizeBtn.AbsoluteSize
    if input.Position.X >= ap.X and input.Position.X <= ap.X + as.X and
       input.Position.Y >= ap.Y and input.Position.Y <= ap.Y + as.Y then
      resizing = true
      resizeStart = Vector2.new(input.Position.X, input.Position.Y)
      sizeStart = main.Size
    end
  end)

  -- Drag updates
  uis.InputChanged:Connect(function(input)
    if not resizing then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local dx = input.Position.X - resizeStart.X
    local dy = input.Position.Y - resizeStart.Y
    local newW = math.clamp(sizeStart.X.Offset + dx, MIN_W, MAX_W)
    local newH = math.clamp(sizeStart.Y.Offset + dy, MIN_H, MAX_H)
    main.Size = UDim2.new(0, newW, 0, newH)
  end)

  uis.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      resizing = false
    end
  end)

  -- Track grip parts to hide when minimized
  local gripParts = {resizeBtn}
  for _, c in pairs(main:GetChildren()) do
    if c.Name == "GripLine" then table.insert(gripParts, c) end
  end
  -- Also hide the header divider shadow when minimized (would otherwise be clipped by main's rounded bottom corner)
  local hs = main:FindFirstChild("HeaderShadow")
  if hs then table.insert(gripParts, hs) end

  spawn(function()
    while gui and gui.Parent do
      rs2.RenderStepped:Wait()
      local showGrip = not minimized
      for _, g in ipairs(gripParts) do
        if g and g.Parent then g.Visible = showGrip end
      end
    end
  end)
end

-- ═══ SIDEBAR (compact: 130px) ═══
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, 130, 1, -36)
sidebar.Position = UDim2.new(0, 0, 0, 36)
sidebar.BackgroundColor3 = SIDEBAR
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 3
sidebar.Parent = main
corner(sidebar, 10)

local sideSep = Instance.new("Frame")
sideSep.Size = UDim2.new(0, 1, 1, 0)
sideSep.Position = UDim2.new(1, -1, 0, 0)
sideSep.BackgroundColor3 = BORDER
sideSep.BorderSizePixel = 0
sideSep.ZIndex = 4
sideSep.Parent = sidebar

-- Section header (compact)
local sectionHeader = Instance.new("Frame")
sectionHeader.Size = UDim2.new(1, 0, 0, 26)
sectionHeader.BackgroundTransparency = 1
sectionHeader.ZIndex = 4
sectionHeader.Parent = sidebar

local sectionIcon = Instance.new("TextLabel")
sectionIcon.Size = UDim2.new(0, 20, 0, 14)
sectionIcon.Position = UDim2.new(0, 10, 0.5, -7)
sectionIcon.BackgroundTransparency = 1
sectionIcon.Text = "⛰"
sectionIcon.TextSize = 11
sectionIcon.TextColor3 = TXTDIM
sectionIcon.ZIndex = 5
sectionIcon.Parent = sectionHeader

local sectionLabel = Instance.new("TextLabel")
sectionLabel.Size = UDim2.new(1, -50, 0, 14)
sectionLabel.Position = UDim2.new(0, 30, 0.5, -7)
sectionLabel.BackgroundTransparency = 1
sectionLabel.Text = "Menu"
sectionLabel.TextColor3 = TXTDIM
sectionLabel.TextSize = 10
sectionLabel.Font = FB
sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
sectionLabel.TextYAlignment = Enum.TextYAlignment.Center
sectionLabel.ZIndex = 5
sectionLabel.Parent = sectionHeader

local sectionChevron = Instance.new("TextLabel")
sectionChevron.Size = UDim2.new(0, 14, 0, 14)
sectionChevron.Position = UDim2.new(1, -18, 0.5, -7)
sectionChevron.BackgroundTransparency = 1
sectionChevron.Text = "▲"
sectionChevron.TextColor3 = TXTMUTE
sectionChevron.TextSize = 8
sectionChevron.ZIndex = 5
sectionChevron.Parent = sectionHeader

local sectionSep = Instance.new("Frame")
sectionSep.Size = UDim2.new(0.7, 0, 0, 1)
sectionSep.Position = UDim2.new(0.15, 0, 0, 26)
sectionSep.BackgroundColor3 = BORDER
sectionSep.BorderSizePixel = 0
sectionSep.ZIndex = 4
sectionSep.Parent = sidebar

-- Nav items
local navItems = {
  {name="Farm",    icon="⛏", page="farm"},
  {name="Bombs",   icon="💣", page="bomb"},
  {name="Player",  icon="👤", page="player"},
}

local navBtns = {}
local navHighlight = Instance.new("Frame")
navHighlight.Name = "NavHighlight"
navHighlight.Size = UDim2.new(1, -14, 0, 26)
navHighlight.BackgroundColor3 = CARD
navHighlight.BackgroundTransparency = 0.3
navHighlight.BorderSizePixel = 0
navHighlight.ZIndex = 4
navHighlight.Visible = false
navHighlight.Parent = sidebar
corner(navHighlight, 5)

for i, item in ipairs(navItems) do
  local y = 32 + (i-1)*30
  local btn = Instance.new("TextButton")
  btn.Name = item.page
  btn.Size = UDim2.new(1, -12, 0, 26)
  btn.Position = UDim2.new(0, 6, 0, y)
  btn.BackgroundTransparency = 1
  btn.Text = ""
  btn.ZIndex = 5
  btn.Parent = sidebar

  local iconLbl = Instance.new("TextLabel")
  iconLbl.Size = UDim2.new(0, 20, 0, 16)
  iconLbl.Position = UDim2.new(0, 6, 0.5, -8)
  iconLbl.BackgroundTransparency = 1
  iconLbl.Text = item.icon
  iconLbl.TextSize = 12
  iconLbl.ZIndex = 6
  iconLbl.Parent = btn

  local nameLbl = Instance.new("TextLabel")
  nameLbl.Size = UDim2.new(1, -32, 1, 0)
  nameLbl.Position = UDim2.new(0, 28, 0, 0)
  nameLbl.BackgroundTransparency = 1
  nameLbl.Text = item.name
  nameLbl.TextColor3 = TXTDIM
  nameLbl.TextSize = 11
  nameLbl.Font = FB
  nameLbl.TextXAlignment = Enum.TextXAlignment.Left
  nameLbl.TextYAlignment = Enum.TextYAlignment.Center
  nameLbl.ZIndex = 6
  nameLbl.Parent = btn

  navBtns[item.page] = {btn = btn, nameLbl = nameLbl, iconLbl = iconLbl, y = y}
end

-- User info at bottom (compact)
local userSep = Instance.new("Frame")
userSep.Size = UDim2.new(0.7, 0, 0, 1)
userSep.Position = UDim2.new(0.15, 0, 1, -44)
userSep.BackgroundColor3 = BORDER
userSep.BorderSizePixel = 0
userSep.ZIndex = 4
userSep.Parent = sidebar

local userFrame = Instance.new("Frame")
userFrame.Size = UDim2.new(1, 0, 0, 38)
userFrame.Position = UDim2.new(0, 0, 1, -42)
userFrame.BackgroundTransparency = 1
userFrame.ZIndex = 4
userFrame.Parent = sidebar

local userDot = Instance.new("Frame")
userDot.Size = UDim2.new(0, 26, 0, 26)
userDot.Position = UDim2.new(0, 10, 0.5, -13)
userDot.BackgroundColor3 = CARD2
userDot.BorderSizePixel = 0
userDot.ZIndex = 5
userDot.Parent = userFrame
corner(userDot, 13)

local userIcon = Instance.new("TextLabel")
userIcon.Size = UDim2.new(1, 0, 1, 0)
userIcon.BackgroundTransparency = 1
userIcon.Text = string.sub(player.Name, 1, 1):upper()
userIcon.TextColor3 = ACCENT
userIcon.TextSize = 12
userIcon.Font = FT
userIcon.TextYAlignment = Enum.TextYAlignment.Center
userIcon.ZIndex = 6
userIcon.Parent = userDot

local userName = Instance.new("TextLabel")
userName.Size = UDim2.new(1, -42, 0, 14)
userName.Position = UDim2.new(0, 40, 0, 6)
userName.BackgroundTransparency = 1
userName.Text = player.Name
userName.TextColor3 = TXT
userName.TextSize = 11
userName.Font = FB
userName.TextXAlignment = Enum.TextXAlignment.Left
userName.TextYAlignment = Enum.TextYAlignment.Center
userName.TextTruncate = Enum.TextTruncate.AtEnd
userName.ZIndex = 5
userName.Parent = userFrame

local userSub = Instance.new("TextLabel")
userSub.Size = UDim2.new(1, -42, 0, 11)
userSub.Position = UDim2.new(0, 40, 0, 21)
userSub.BackgroundTransparency = 1
userSub.Text = "● Online"
userSub.TextColor3 = GREEN
userSub.TextSize = 8
userSub.Font = FR
userSub.TextXAlignment = Enum.TextXAlignment.Left
userSub.TextYAlignment = Enum.TextYAlignment.Center
userSub.ZIndex = 5
userSub.Parent = userFrame

-- ═══ CONTENT AREA (compact, on the right of sidebar) ═══
local contentArea = Instance.new("Frame")
contentArea.Name = "Content"
contentArea.Size = UDim2.new(1, -140, 1, -42)
contentArea.Position = UDim2.new(0, 134, 0, 40)
contentArea.BackgroundTransparency = 1
contentArea.ClipsDescendants = true
contentArea.ZIndex = 3
contentArea.Parent = main

local function makePage(name)
  local sf = Instance.new("ScrollingFrame")
  sf.Name = name
  sf.Size = UDim2.new(1, 0, 1, 0)
  sf.BackgroundTransparency = 1
  sf.BorderSizePixel = 0
  sf.ScrollBarThickness = 2
  sf.ScrollBarImageColor3 = ACCENT
  sf.CanvasSize = UDim2.new(0, 0, 0, 0)
  sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
  sf.Visible = false
  sf.ZIndex = 3
  sf.Parent = contentArea
  local lay = Instance.new("UIListLayout")
  lay.Padding = UDim.new(0, 5)
  lay.SortOrder = Enum.SortOrder.LayoutOrder
  lay.Parent = sf
  padding(sf, 5, 10, 5, 5)
  return sf
end

local pages = {farm=makePage("farm"), bomb=makePage("bomb"), player=makePage("player")}

-- ═══ UI COMPONENTS ═══

local _activeDropdowns = {}

local function pageTitle(parent, title, subtitle, order)
  local f = Instance.new("Frame")
  f.Size = UDim2.new(1, 0, 0, 38); f.BackgroundTransparency = 1; f.LayoutOrder = order or 0; f.ZIndex = 4; f.Parent = parent
  local t = Instance.new("TextLabel")
  t.Size = UDim2.new(1, 0, 0, 20); t.BackgroundTransparency = 1; t.Text = title; t.TextColor3 = TXT; t.TextSize = 16; t.Font = FT
  t.TextXAlignment = Enum.TextXAlignment.Left; t.TextYAlignment = Enum.TextYAlignment.Center; t.ZIndex = 4; t.Parent = f
  if subtitle then
    local s = Instance.new("TextLabel")
    s.Size = UDim2.new(1, 0, 0, 14); s.Position = UDim2.new(0, 0, 0, 22); s.BackgroundTransparency = 1; s.Text = subtitle; s.TextColor3 = TXTMUTE; s.TextSize = 10; s.Font = FR
    s.TextXAlignment = Enum.TextXAlignment.Left; s.TextYAlignment = Enum.TextYAlignment.Center; s.ZIndex = 4; s.Parent = f
  end
end

local function card(parent, order)
  local f = Instance.new("Frame")
  f.Size = UDim2.new(1, 0, 0, 0); f.AutomaticSize = Enum.AutomaticSize.Y
  f.BackgroundTransparency = 1; f.BorderSizePixel = 0; f.LayoutOrder = order or 0; f.ZIndex = 4; f.Parent = parent
  local lay = Instance.new("UIListLayout"); lay.Padding = UDim.new(0, 6); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = f
  padding(f, 0, 0, 0, 0)
  return f
end

local function cardHeader(parent, text, order)
  local f = Instance.new("Frame")
  f.Size = UDim2.new(1, 0, 0, 28); f.BackgroundTransparency = 1; f.LayoutOrder = order or 0; f.ZIndex = 4; f.Parent = parent
  local t = Instance.new("TextLabel")
  t.Size = UDim2.new(1, -16, 1, 0); t.Position = UDim2.new(0, 12, 0, 0)
  t.BackgroundTransparency = 1; t.Text = text; t.TextColor3 = TXTMUTE; t.TextSize = 10; t.Font = FB
  t.TextXAlignment = Enum.TextXAlignment.Left; t.ZIndex = 4; t.Parent = f
  return f
end

local function cardDivider(parent, order)
  local d = Instance.new("Frame")
  d.Size = UDim2.new(1, -24, 0, 1); d.Position = UDim2.new(0, 12, 0, 0)
  d.BackgroundColor3 = DIVIDER; d.BorderSizePixel = 0; d.LayoutOrder = order or 0; d.ZIndex = 4; d.Parent = parent
  return d
end

local function settingRow(parent, order)
  local f = Instance.new("Frame")
  f.Size = UDim2.new(1, 0, 0, 40); f.BackgroundTransparency = 1; f.LayoutOrder = order or 0; f.ZIndex = 4; f.Parent = parent
  return f
end

local function toggleRow(parent, text, sub, default, order, callback)
  local f = Instance.new("Frame")
  f.Size = UDim2.new(1, 0, 0, 50); f.BackgroundColor3 = CARD
  f.BorderSizePixel = 0; f.LayoutOrder = order or 0; f.ZIndex = 4; f.Parent = parent
  corner(f, 10)

  local lbl = Instance.new("TextLabel")
  if sub then
    lbl.Size = UDim2.new(1, -64, 0, 16); lbl.Position = UDim2.new(0, 14, 0, 8)
  else
    lbl.Size = UDim2.new(1, -64, 0, 16); lbl.Position = UDim2.new(0, 14, 0.5, -8)
  end
  lbl.BackgroundTransparency = 1; lbl.Text = text; lbl.TextColor3 = TXT; lbl.TextSize = 13; lbl.Font = FM
  lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center; lbl.ZIndex = 5; lbl.Parent = f

  if sub then
    local sl = Instance.new("TextLabel")
    sl.Size = UDim2.new(1, -64, 0, 12); sl.Position = UDim2.new(0, 14, 0, 28)
    sl.BackgroundTransparency = 1; sl.Text = sub; sl.TextColor3 = TXTMUTE; sl.TextSize = 10; sl.Font = FR
    sl.TextXAlignment = Enum.TextXAlignment.Left; sl.TextYAlignment = Enum.TextYAlignment.Center; sl.ZIndex = 5; sl.Parent = f
  end

  local checkBg = Instance.new("Frame")
  checkBg.Size = UDim2.new(0, 28, 0, 28); checkBg.Position = UDim2.new(1, -42, 0.5, -14)
  checkBg.BackgroundColor3 = Color3.fromRGB(35, 35, 48); checkBg.BorderSizePixel = 0; checkBg.ZIndex = 5; checkBg.Parent = f
  corner(checkBg, 14)

  local checkStroke = Instance.new("UIStroke")
  checkStroke.Color = default and ACCENT or Color3.fromRGB(60, 60, 75)
  checkStroke.Thickness = 2
  checkStroke.Parent = checkBg

  local checkMark = Instance.new("TextLabel")
  checkMark.Size = UDim2.new(1, 0, 1, 0); checkMark.BackgroundTransparency = 1
  checkMark.Text = default and "✓" or ""
  checkMark.TextColor3 = ACCENT; checkMark.TextSize = 14; checkMark.Font = FT
  checkMark.ZIndex = 6; checkMark.Parent = checkBg

  local on = default or false

  local function animate()
    if on then
      checkMark.Text = "✓"
      tw:Create(checkStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Color = ACCENT}):Play()
    else
      checkMark.Text = ""
      tw:Create(checkStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Color = Color3.fromRGB(60, 60, 75)}):Play()
    end
  end

  local btn = Instance.new("TextButton")
  btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = ""; btn.ZIndex = 7; btn.Parent = f
  btn.Activated:Connect(function()
    on = not on
    animate()
    if callback then callback(on) end
  end)

  return {
    get = function() return on end,
    set = function(v) on = v; animate() end,
    lbl = lbl,
  }
end

local function valueRow(parent, label, valText, order)
  local f = Instance.new("Frame")
  f.Size = UDim2.new(1, 0, 0, 42); f.BackgroundColor3 = CARD
  f.BorderSizePixel = 0; f.LayoutOrder = order or 0; f.ZIndex = 4; f.Parent = parent
  corner(f, 10)
  local lbl = Instance.new("TextLabel")
  lbl.Size = UDim2.new(1, -90, 1, 0); lbl.Position = UDim2.new(0, 14, 0, 0)
  lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = TXT; lbl.TextSize = 12; lbl.Font = FM
  lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center; lbl.ZIndex = 5; lbl.Parent = f
  local val = Instance.new("TextLabel")
  val.Size = UDim2.new(0, 72, 1, 0); val.Position = UDim2.new(1, -84, 0, 0)
  val.BackgroundTransparency = 1; val.Text = valText or ""; val.TextColor3 = TXTDIM; val.TextSize = 11; val.Font = FC
  val.TextXAlignment = Enum.TextXAlignment.Right; val.TextYAlignment = Enum.TextYAlignment.Center; val.ZIndex = 5; val.Parent = f
  return f, val
end

local function dropdownRow(parent, label, sub, values, defaultIdx, order, callback)
  local f = Instance.new("Frame")
  f.Size = UDim2.new(1, 0, 0, 50); f.BackgroundColor3 = CARD
  f.BorderSizePixel = 0; f.LayoutOrder = order or 0; f.ZIndex = 4; f.Parent = parent
  corner(f, 10)

  local lbl = Instance.new("TextLabel")
  if sub then
    lbl.Size = UDim2.new(1, -130, 0, 16); lbl.Position = UDim2.new(0, 14, 0, 10)
  else
    lbl.Size = UDim2.new(1, -130, 0, 16); lbl.Position = UDim2.new(0, 14, 0.5, -8)
  end
  lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = TXT; lbl.TextSize = 13; lbl.Font = FB
  lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center; lbl.ZIndex = 5; lbl.Parent = f

  if sub then
    local sl = Instance.new("TextLabel")
    sl.Size = UDim2.new(1, -130, 0, 12); sl.Position = UDim2.new(0, 14, 0, 28)
    sl.BackgroundTransparency = 1; sl.Text = sub; sl.TextColor3 = TXTMUTE; sl.TextSize = 10; sl.Font = FR
    sl.TextXAlignment = Enum.TextXAlignment.Left; sl.TextYAlignment = Enum.TextYAlignment.Center; sl.ZIndex = 5; sl.Parent = f
  end

  local idx = defaultIdx or 1
  local isOpen = false
  local menuFrame = nil

  local DROP_W = 116
  local DROP_H = 32
  local ITEM_H = 32

  local dropBg = Instance.new("Frame")
  dropBg.Size = UDim2.new(0, DROP_W, 0, DROP_H)
  dropBg.Position = UDim2.new(1, -(DROP_W + 12), 0.5, -(DROP_H / 2))
  dropBg.BackgroundColor3 = CARD2
  dropBg.BorderSizePixel = 0
  dropBg.ZIndex = 5
  dropBg.Parent = f
  corner(dropBg, 8)

  local valLbl = Instance.new("TextLabel")
  valLbl.Size = UDim2.new(1, -26, 1, 0); valLbl.Position = UDim2.new(0, 10, 0, 0)
  valLbl.BackgroundTransparency = 1; valLbl.Text = values[idx]
  valLbl.TextColor3 = TXT; valLbl.TextSize = 11; valLbl.Font = FB
  valLbl.TextXAlignment = Enum.TextXAlignment.Left; valLbl.TextYAlignment = Enum.TextYAlignment.Center; valLbl.ZIndex = 6; valLbl.Parent = dropBg

  local arrow = Instance.new("TextLabel")
  arrow.Size = UDim2.new(0, 18, 1, 0); arrow.Position = UDim2.new(1, -22, 0, 0)
  arrow.BackgroundTransparency = 1; arrow.Text = "▼"
  arrow.TextColor3 = ACCENT; arrow.TextSize = 9; arrow.Font = FR
  arrow.ZIndex = 6; arrow.Parent = dropBg

  local renderConn = nil

  local function closeMenu()
    isOpen = false
    _activeDropdowns[dropBg] = nil
    if renderConn then renderConn:Disconnect(); renderConn = nil end
    if menuFrame then
      tw:Create(menuFrame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0, DROP_W, 0, 0)}):Play()
      wait(0.12)
      if menuFrame then menuFrame:Destroy(); menuFrame = nil end
    end
    arrow.Text = "▼"
  end

  local function openMenu()
    if isOpen then closeMenu(); return end
    isOpen = true
    arrow.Text = "▲"

    local absPos = dropBg.AbsolutePosition
    local absSize = dropBg.AbsoluteSize

    menuFrame = Instance.new("Frame")
    menuFrame.Name = "DropdownMenu"
    menuFrame.Size = UDim2.new(0, DROP_W, 0, 0)
    menuFrame.Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y + 4)
    menuFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
    menuFrame.BorderSizePixel = 0
    menuFrame.ZIndex = 200
    menuFrame.ClipsDescendants = true
    menuFrame.Parent = gui
    corner(menuFrame, 8)

    local menuStroke = Instance.new("UIStroke")
    menuStroke.Color = Color3.fromRGB(45, 45, 60)
    menuStroke.Thickness = 1
    menuStroke.Parent = menuFrame

    local menuLayout = Instance.new("UIListLayout")
    menuLayout.Padding = UDim.new(0, 2)
    menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
    menuLayout.Parent = menuFrame

    local menuPad = Instance.new("UIPadding")
    menuPad.PaddingTop = UDim.new(0, 4)
    menuPad.PaddingBottom = UDim.new(0, 4)
    menuPad.PaddingLeft = UDim.new(0, 4)
    menuPad.PaddingRight = UDim.new(0, 4)
    menuPad.Parent = menuFrame

    for i, val in ipairs(values) do
      local itemBtn = Instance.new("TextButton")
      itemBtn.Size = UDim2.new(1, 0, 0, ITEM_H)
      itemBtn.BackgroundColor3 = i == idx and ACCENT or Color3.new(0, 0, 0)
      itemBtn.BackgroundTransparency = i == idx and 0.8 or 1
      itemBtn.Text = ""
      itemBtn.ZIndex = 201
      itemBtn.LayoutOrder = i
      itemBtn.Parent = menuFrame
      corner(itemBtn, 6)

      local itemLbl = Instance.new("TextLabel")
      itemLbl.Size = UDim2.new(1, -16, 1, 0); itemLbl.Position = UDim2.new(0, 12, 0, 0)
      itemLbl.BackgroundTransparency = 1; itemLbl.Text = val
      itemLbl.TextColor3 = i == idx and ACCENT or Color3.fromRGB(180, 180, 195)
      itemLbl.TextSize = 11; itemLbl.Font = i == idx and FB or FM
      itemLbl.TextXAlignment = Enum.TextXAlignment.Left; itemLbl.TextYAlignment = Enum.TextYAlignment.Center
      itemLbl.ZIndex = 202; itemLbl.Parent = itemBtn

      itemBtn.Activated:Connect(function()
        idx = i
        valLbl.Text = val
        closeMenu()
        if callback then callback(val, idx) end
      end)
    end

    local targetH = #values * (ITEM_H + 2) + 8
    tw:Create(menuFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, DROP_W, 0, targetH)}):Play()
    _activeDropdowns[dropBg] = closeMenu

    if renderConn then renderConn:Disconnect() end
    renderConn = rs2.RenderStepped:Connect(function()
      if menuFrame and menuFrame.Parent and isOpen then
        local curPos = dropBg.AbsolutePosition
        local curSize = dropBg.AbsoluteSize
        menuFrame.Position = UDim2.new(0, curPos.X, 0, curPos.Y + curSize.Y + 4)
      end
    end)
  end

  local dropBtn = Instance.new("TextButton")
  dropBtn.Size = UDim2.new(0, DROP_W, 0, DROP_H)
  dropBtn.Position = UDim2.new(1, -(DROP_W + 12), 0.5, -(DROP_H / 2))
  dropBtn.BackgroundTransparency = 1; dropBtn.Text = ""; dropBtn.ZIndex = 7; dropBtn.Parent = f
  dropBtn.Activated:Connect(function() openMenu() end)

  uis.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      if isOpen and menuFrame then
        local absPos = menuFrame.AbsolutePosition
        local absSize = menuFrame.AbsoluteSize
        local inpPos = input.Position
        local dropAbsPos = dropBg.AbsolutePosition
        local dropAbsSize = dropBg.AbsoluteSize
        local inMenu = inpPos.X >= absPos.X and inpPos.X <= absPos.X + absSize.X and inpPos.Y >= absPos.Y and inpPos.Y <= absPos.Y + absSize.Y
        local inDrop = inpPos.X >= dropAbsPos.X and inpPos.X <= dropAbsPos.X + dropAbsSize.X and inpPos.Y >= dropAbsPos.Y and inpPos.Y <= dropAbsPos.Y + dropAbsSize.Y
        if not inMenu and not inDrop then closeMenu() end
      end
    end
  end)

  return {
    get = function() return values[idx], idx end,
    set = function(v) for i, val in ipairs(values) do if val == v then idx = i; valLbl.Text = v; return end end end,
  }
end

local function cycleRow(parent, label, sub, values, defaultIdx, order, callback)
  return dropdownRow(parent, label, sub, values, defaultIdx, order, callback)
end

local function sliderRow(parent, label, sub, min, max, default, order, callback)
  local f = Instance.new("Frame")
  f.Size = UDim2.new(1, 0, 0, 60); f.BackgroundColor3 = CARD
  f.BorderSizePixel = 0; f.LayoutOrder = order or 0; f.ZIndex = 4; f.Parent = parent
  corner(f, 10)

  local lbl = Instance.new("TextLabel")
  lbl.Size = UDim2.new(1, -100, 0, 16); lbl.Position = UDim2.new(0, 14, 0, 6)
  lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = TXT; lbl.TextSize = 13; lbl.Font = FM
  lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center; lbl.ZIndex = 5; lbl.Parent = f

  if sub then
    local sl = Instance.new("TextLabel")
    sl.Size = UDim2.new(1, -100, 0, 12); sl.Position = UDim2.new(0, 14, 0, 24)
    sl.BackgroundTransparency = 1; sl.Text = sub; sl.TextColor3 = TXTMUTE; sl.TextSize = 10; sl.Font = FR
    sl.TextXAlignment = Enum.TextXAlignment.Left; sl.TextYAlignment = Enum.TextYAlignment.Center; sl.ZIndex = 5; sl.Parent = f
  end

  local valLbl = Instance.new("TextLabel")
  valLbl.Size = UDim2.new(0, 40, 0, 16); valLbl.Position = UDim2.new(1, -52, 0, 6)
  valLbl.BackgroundTransparency = 1; valLbl.Text = tostring(default); valLbl.TextColor3 = ACCENT; valLbl.TextSize = 12; valLbl.Font = FC
  valLbl.TextXAlignment = Enum.TextXAlignment.Right; valLbl.TextYAlignment = Enum.TextYAlignment.Center; valLbl.ZIndex = 5; valLbl.Parent = f

  local track = Instance.new("Frame")
  track.Size = UDim2.new(1, -28, 0, 4); track.Position = UDim2.new(0, 14, 0, 44)
  track.BackgroundColor3 = Color3.fromRGB(40, 40, 55); track.BorderSizePixel = 0; track.ZIndex = 5; track.Parent = f
  corner(track, 2)

  local fill = Instance.new("Frame")
  local pct = (default - min) / (max - min)
  fill.Size = UDim2.new(pct, 0, 1, 0)
  fill.BackgroundColor3 = ACCENT; fill.BorderSizePixel = 0; fill.ZIndex = 6; fill.Parent = track
  corner(fill, 2)

  local knob = Instance.new("Frame")
  knob.Size = UDim2.new(0, 14, 0, 14); knob.Position = UDim2.new(pct, -7, 0.5, -7)
  knob.BackgroundColor3 = ACCENT; knob.BorderSizePixel = 0; knob.ZIndex = 7; knob.Parent = track
  corner(knob, 7)

  local dragging = false
  local curVal = default

  local function updateSlider(inputX)
    local rel = math.clamp((inputX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
    curVal = math.floor(min + rel * (max - min))
    fill.Size = UDim2.new(rel, 0, 1, 0)
    knob.Position = UDim2.new(rel, -7, 0.5, -7)
    valLbl.Text = tostring(curVal)
    if callback then callback(curVal) end
  end

  knob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging = true
    end
  end)

  uis.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
      updateSlider(input.Position.X)
    end
  end)

  uis.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging = false
    end
  end)

  track.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      updateSlider(input.Position.X)
      dragging = true
    end
  end)

  return {
    get = function() return curVal end,
    set = function(v) curVal = v; local rel = (v - min)/(max - min); fill.Size = UDim2.new(rel,0,1,0); knob.Position = UDim2.new(rel,-7,0.5,-7); valLbl.Text = tostring(v) end,
  }
end

local function buttonRow(parent, text, color, order, callback)
  local f = Instance.new("Frame")
  f.Size = UDim2.new(1, 0, 0, 42); f.BackgroundColor3 = color
  f.BorderSizePixel = 0; f.LayoutOrder = order or 0; f.ZIndex = 4; f.Parent = parent
  corner(f, 10)
  local btn = Instance.new("TextButton")
  btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = text; btn.TextColor3 = Color3.new(1,1,1); btn.TextSize = 13; btn.Font = FT
  btn.TextXAlignment = Enum.TextXAlignment.Center; btn.TextYAlignment = Enum.TextYAlignment.Center
  btn.ZIndex = 5; btn.Parent = f
  if callback then btn.Activated:Connect(callback) end
  return btn
end

-- ═══ TAB SWITCHING (sidebar nav with highlight slide) ═══
local activePage = "farm"
local function switchPage(name)
  activePage = name
  for key, page in pairs(pages) do page.Visible = (key == name) end
  for key, data in pairs(navBtns) do
    if key == name then
      data.nameLbl.TextColor3 = ACCENT
      data.iconLbl.TextColor3 = ACCENT
      navHighlight.Visible = true
      tw:Create(navHighlight, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(0, 6, 0, data.y)}):Play()
    else
      data.nameLbl.TextColor3 = TXTDIM
      data.iconLbl.TextColor3 = TXTDIM
    end
  end
end

for key, data in pairs(navBtns) do
  data.btn.Activated:Connect(function() switchPage(key) end)
end
switchPage("farm")

-- ══════════════════════════════════════════════════════════════
--  FARM PAGE
-- ══════════════════════════════════════════════════════════════

pageTitle(pages.farm, "Farm", "Auto farm crystals by rarity & size", 0)

local sCard = card(pages.farm, 1)
cardHeader(sCard, "STATUS", 1)
local _, statusVal = valueRow(sCard, "Status", "Idle", 2)
local _, bpVal = valueRow(sCard, "Backpack", "0 / 0 kg", 3)
local _, farmCryst = valueRow(sCard, "Crystals Mined", "0", 4)
local _, farmValue = valueRow(sCard, "Total Value", "$0", 5)
local _, farmBombs = valueRow(sCard, "Bombs Used", "0", 6)
local _, farmElapsed = valueRow(sCard, "Elapsed", "0:00", 7)

local rarCard = card(pages.farm, 2)
cardHeader(rarCard, "RARITY FILTER", 1)

local rarities = {"Common","Uncommon","Rare","Epic","Legendary","Mythic"}
local rarityTog = {}
for i, r in ipairs(rarities) do
  rarityTog[r] = toggleRow(rarCard, r, nil, false, i + 1, function(v) rarityTogState[r] = v end)
end

local szCard = card(pages.farm, 3)
cardHeader(szCard, "SIZE FILTER", 1)

local sizeTog = {}

local function addSizeToggle(sz, order)
  if sizeTog[sz] then return end
  local preserved = sizeTogState[sz]
  sizeTog[sz] = toggleRow(szCard, sz, nil, preserved == nil and true or preserved, order, function(v) sizeTogState[sz] = v end)
  if preserved == nil then sizeTogState[sz] = true end
end

local function refreshNewSizes()
  local found = getCrystalSizes()
  local foundSet = {}
  for _, sz in ipairs(found) do foundSet[sz] = true end

  -- Remove widgets for sizes that no longer exist in workspace
  for sz, widget in pairs(sizeTog) do
    if not foundSet[sz] then
      if widget and widget.lbl and widget.lbl.Parent then
        widget.lbl.Parent:Destroy()
      end
      sizeTog[sz] = nil
    end
  end

  -- Create or reorder widgets for current sizes
  for i, sz in ipairs(found) do
    if sizeTog[sz] then
      sizeTog[sz].lbl.Parent.LayoutOrder = 100 + i
    else
      addSizeToggle(sz, 100 + i)
    end
  end
end

refreshNewSizes()

local optCard = card(pages.farm, 4)
cardHeader(optCard, "OPTIONS", 1)
local sellRow = toggleRow(optCard, "Auto Sell", "Sell when backpack is full", false, 2, function(v) sellOn = v end)
toggleRow(optCard, "Smart Auto Sell", "Sell lesser crystals to mine higher-value ones", false, 3, function(v) smartSellOn = v end)

local ctrlCard = card(pages.farm, 5)
local startBtn, stopBtn
startBtn = buttonRow(ctrlCard, "START FARMING", GREEN, 1, function()
  if farming then return end
  local anyR, anyS = false, false
  for _, t in pairs(rarityTog) do if t.get() then anyR = true; break end end
  for _, t in pairs(sizeTog) do if t.get() then anyS = true; break end end
  if not anyR or not anyS then print("[Hub] Enable at least one rarity AND one size"); return end
  farming = true; statsCrystals = 0; statsValue = 0; statsBombs = 0; statsStart = tick()
  startBtn.Text = "RUNNING"; startBtn.BackgroundColor3 = CARD2
  statusText = "Farming..."; print("[Hub] Farm started")
  spawn(farmLoop)
end)
stopBtn = buttonRow(ctrlCard, "STOP", CARD2, 2, function()
  if not farming then return end
  farming = false
  startBtn.Text = "START FARMING"; startBtn.BackgroundColor3 = GREEN
  statusText = "Stopped"; print("[Hub] Farm stopped")
end)

-- ══════════════════════════════════════════════════════════════
--  BOMBS PAGE
-- ══════════════════════════════════════════════════════════════

pageTitle(pages.bomb, "Bombs", "Buy bombs & configure auto-detonation", 10)

local abCard = card(pages.bomb, 11)
cardHeader(abCard, "AUTO-BOMB", 1)
local abTog = toggleRow(abCard, "Auto-Bomb", "Detonate near crystals automatically", false, 2, function(v)
  autoBombEnabled = v
  if v then print("[Hub] Auto-bomb ON") else print("[Hub] Auto-bomb OFF") end
end)

local abBombOrder = {"ClassicBomb","WindBomb","IceBomb","FireBomb","ThunderBomb","PoisonBomb","TimeBomb","AgonyBomb"}
local abBombNames = {}
for _, bm in ipairs(bombs) do abBombNames[bm.id] = bm.name end
local abRarities = {"Epic","Legendary","Mythic"}

for i, rarity in ipairs(abRarities) do
  local names = {}
  for _, id in ipairs(abBombOrder) do table.insert(names, abBombNames[id]) end
  local currentId = autoBombConfig[rarity]
  local defaultIdx = 1
  if currentId then for j, id in ipairs(abBombOrder) do if id == currentId then defaultIdx = j; break end end end
  dropdownRow(abCard, rarity, "Bomb to use", names, defaultIdx, 2 + i, function(name, idx)
    autoBombConfig[rarity] = abBombOrder[idx]
  end)
end

local shopCard = card(pages.bomb, 12)
cardHeader(shopCard, "BOMB SHOP", 1)

local bombTog = {}
local bombStk = {}
for i, bm in ipairs(bombs) do
  local row = toggleRow(shopCard, bm.name, "$"..fmtPrice(bm.price), false, i + 1, function(v) bombTogState[bm.id] = v end)
  bombTog[bm.id] = row
  local stkLbl = Instance.new("TextLabel")
  stkLbl.Size = UDim2.new(0, 60, 0, 12); stkLbl.Position = UDim2.new(1, -100, 0, 28)
  stkLbl.BackgroundTransparency = 1; stkLbl.Text = "Stock: --"; stkLbl.TextColor3 = TXTMUTE; stkLbl.TextSize = 10; stkLbl.Font = FC
  stkLbl.TextXAlignment = Enum.TextXAlignment.Left; stkLbl.TextYAlignment = Enum.TextYAlignment.Center; stkLbl.ZIndex = 5; stkLbl.Parent = row.lbl.Parent
  bombStk[bm.id] = stkLbl
end

local function queryAndBuyBombs()
  if not BombShopQuery then return end
  local ok, q = pcall(function() return BombShopQuery:InvokeServer() end)
  if ok and q and type(q) == "table" then
    local stock = nil
    if type(q.stock) == "table" then stock = q.stock
    elseif type(q.Stock) == "table" then stock = q.Stock
    elseif type(q[1]) == "table" then stock = q end
    for _, bm in ipairs(bombs) do
      if bombTogState[bm.id] then
        local s = 0
        if stock and type(stock) == "table" then
          s = stock[bm.id] or stock[bm.name] or 0
        end
        if bombStk[bm.id] then bombStk[bm.id].Text = "Stock: "..tostring(s) end
        if s > 0 and getMoney() >= bm.price then
          buyBomb(bm.id)
        end
      end
    end
  end
end

spawn(function()
  while gui and gui.Parent do
    local anyOn = false
    for _, bm in ipairs(bombs) do if bombTogState[bm.id] then anyOn = true; break end end
    if anyOn then queryAndBuyBombs() end
    wait(3)
  end
end)

if BombShopRestocked then
  BombShopRestocked.OnClientEvent:Connect(function()
    print("[Hub] Restock! Buying now...")
    queryAndBuyBombs()
  end)
end

spawn(function()
  while gui and gui.Parent do
    local char = player.Character
    if char then
      local root = char:FindFirstChild("HumanoidRootPart")
      if root and CrystalDroppedPickup then
        for _, obj in pairs(workspace:GetChildren()) do
          if obj:IsA("Tool") and obj:FindFirstChild("Handle") then
            if (obj.Handle.Position - root.Position).Magnitude <= 12 then
              pcall(function() CrystalDroppedPickup:FireServer(obj) end)
            end
          end
        end
      end
    end
    wait(0.5)
  end
end)

-- ══════════════════════════════════════════════════════════════
--  PLAYER PAGE
-- ══════════════════════════════════════════════════════════════

pageTitle(pages.player, "Player", "Player utilities & settings", 20)

local pCard = card(pages.player, 21)
cardHeader(pCard, "UTILITIES", 1)
local arRow
arRow = toggleRow(pCard, "Anti-Ragdoll", "Prevents ragdoll and physics states", false, 2, function(v)
  if v then applyAntiRagdoll()
  else clearAntiRagdoll() end
  if arRow and arRow.lbl then arRow.lbl.TextColor3 = v and GREEN or TXT end
end)
local espRow = toggleRow(pCard, "Crystal ESP", "Show crystal labels within 200m", false, 3, function(v)
  espEnabled = v
  if v then print("[Hub] ESP ON") else for _, c in pairs(espFolder:GetChildren()) do c:Destroy() end; print("[Hub] ESP OFF") end
end)

player.CharacterAdded:Connect(function()
  if antiRagdollEnabled then delay(0.5, applyAntiRagdoll) end
end)

local setCard = card(pages.player, 22)
cardHeader(setCard, "SETTINGS", 1)
sliderRow(setCard, "Dig Timeout", "Skip crystal if no HP change (seconds)", 10, 40, 30, 2, function(val)
  digTimeoutTicks = math.floor(val / 0.15)
end)
local hopRow = toggleRow(setCard, "Server Hop", "Hop after 5min with no crystals", false, 3, function(v)
  hopEnabled = v; hopTimer = 0
  if v then print("[Hub] Server hop ON") else print("[Hub] Server hop OFF") end
end)

-- ═══ Background loops ═══
spawn(function()
  while gui and gui.Parent do
    wait(1)
    statusVal.Text = statusText
    bpVal.Text = bpText
    farmCryst.Text = tostring(statsCrystals)
    farmValue.Text = "$"..fmtPrice(statsValue)
    farmBombs.Text = tostring(statsBombs)
    farmElapsed.Text = statsStart > 0 and string.format("%d:%02d", math.floor((tick() - statsStart)/60), math.floor((tick() - statsStart)%60)) or "0:00"
  end
end)

spawn(function() while gui and gui.Parent do updateESP(); wait(2) end end)

spawn(function()
  while gui and gui.Parent do
    wait(1)
    if hopEnabled and farming then
      local crystal = findBestCrystal()
      if crystal then hopTimer = 0
      else
        hopTimer = hopTimer + 1
        if hopTimer >= 300 then
          local TeleportService = game:GetService("TeleportService")
          local HttpService = game:GetService("HttpService")
          local ok, servers = pcall(function()
            return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
          end)
          if ok and servers and servers.data then
            for _, s in ipairs(servers.data) do
              if s.id ~= game.JobId and s.playing < s.maxPlayers then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, player); break
              end
            end
          end
          hopTimer = 0
        end
      end
    end
  end
end)

spawn(function()
  local VirtualUser = game:GetService("VirtualUser")
  player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
  end)
end)

-- Sizes: known list pre-created at init (default ON), new size classes auto-add during session (default ON, user choices preserved)
spawn(function() while gui and gui.Parent do wait(3); pcall(refreshNewSizes) end end)

print("[Hub] Ready — Mine Hub v7 (Axel Hub 1:1)")
