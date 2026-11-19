-- QuestPlanner: data layer.
-- Reads quests, NPCs, objects, items, quest XP and zone maps from QuestieDB's public API
-- (LibQuestieDB contract 4). Nothing is bundled; a small search index is built in the
-- background the first time the window opens and lives only for the session.

local _, QP = ...
_G.QuestPlanner = QP

QP.Data = {}
local D = QP.Data

local CONTRACT = 4
local band = bit.band
local floor, sqrt = math.floor, math.sqrt

local function pcallret(fn, ...)
  if type(fn) ~= "function" then return end
  local r = { pcall(fn, ...) }
  if r[1] then return unpack(r, 2, table.maxn(r)) end
end
D.pcallret = pcallret

---------------------------------------------------------------------------
-- QuestieDB access
---------------------------------------------------------------------------
local Lib, QuestDB, NpcDB, ObjectDB, ItemDB

function D.Init()
  if Lib then return true end
  if not _G.LibQuestieDB then
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    pcallret(load, "QuestieDB")
  end
  local lib = _G.LibQuestieDB
  if not lib or not lib.Quest then
    D.error = "QuestieDB not found. QuestPlanner reads Questie's quest database - install or enable Questie."
    return false
  end
  if lib.RequireContract then
    local ok, msg = lib.RequireContract(CONTRACT)
    if not ok then D.error = msg; return false end
  end
  Lib, QuestDB, NpcDB, ObjectDB, ItemDB = lib, lib.Quest, lib.Npc, lib.Object, lib.Item
  D.error = nil
  return true
end

function D.Ready() return Lib ~= nil end

local function Q(field, id) return pcallret(QuestDB[field], id) end
local function N(field, id) return pcallret(NpcDB[field], id) end
local function O(field, id) return pcallret(ObjectDB[field], id) end
local function I(field, id) return pcallret(ItemDB[field], id) end
D.Q, D.N, D.O, D.I = Q, N, O, I

---------------------------------------------------------------------------
-- Player info
---------------------------------------------------------------------------
local player = {}
D.player = player

function D.RefreshPlayer()
  player.level = UnitLevel("player") or 1
  local _, classFile = UnitClass("player")
  local _, _, raceId = UnitRace("player")
  player.classFile = classFile
  player.raceId = raceId
  player.faction = UnitFactionGroup("player")
  if Lib then
    local enum = Lib.Enum or {}
    player.raceMask = enum.raceMaskById and enum.raceMaskById[raceId] or nil
    player.classMask = enum.classKeys and enum.classKeys[classFile] or nil
  end
end

local completed = {}
D.completed = completed

function D.RefreshCompleted()
  wipe(completed)
  local list = C_QuestLog and pcallret(C_QuestLog.GetAllCompletedQuestIDs)
  if type(list) == "table" then
    for _, id in ipairs(list) do completed[id] = true end
  else
    local t = pcallret(GetQuestsCompleted)
    if type(t) == "table" then for id in pairs(t) do completed[id] = true end end
  end
end

function D.IsCompleted(id)
  if completed[id] then return true end
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    return pcallret(C_QuestLog.IsQuestFlaggedCompleted, id) and true or false
  end
  return false
end

function D.IsOnQuest(id)
  if C_QuestLog and C_QuestLog.IsOnQuest then return pcallret(C_QuestLog.IsOnQuest, id) and true or false end
  local idx = pcallret(GetQuestLogIndexByID, id)
  return idx and idx > 0 or false
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------
local zoneMaps -- { areaToUi = {}, uiToArea = {} }

local function decodeTable(v)
  if type(v) == "table" then return v end
  if type(v) == "string" then
    local fn = loadstring(v)
    if fn then
      local ok, t = pcall(fn)
      if ok and type(t) == "table" then return t end
    end
  end
  return {}
end

local function loadZoneMaps()
  if zoneMaps then return zoneMaps end
  zoneMaps = { areaToUi = {}, uiToArea = {} }
  local zdb = Lib and Lib.Support and Lib.Support.Get and Lib.Support.Get("ZoneDB")
  local p = zdb and zdb.private
  if p then
    local uiToArea = decodeTable(p.uiMapIdToAreaId)
    for ui, area in pairs(uiToArea) do
      zoneMaps.uiToArea[ui] = area
      if area and area > 0 and not zoneMaps.areaToUi[area] then zoneMaps.areaToUi[area] = ui end
    end
    for ui, area in pairs(decodeTable(p.uiMapIdToAreaIdOverride)) do zoneMaps.uiToArea[ui] = area end
    for area, ui in pairs(decodeTable(p.areaIdToUiMapId)) do zoneMaps.areaToUi[area] = ui end
    for area, ui in pairs(decodeTable(p.areaIdToUiMapIdOverride)) do zoneMaps.areaToUi[area] = ui end
  end
  return zoneMaps
end

function D.UiMapForArea(areaId)
  local ui = loadZoneMaps().areaToUi[areaId]
  if ui and ui > 0 then return ui end
end

function D.AreaForUiMap(uiMapId)
  return loadZoneMaps().uiToArea[uiMapId]
end

local zoneNameCache = {}
function D.ZoneName(areaId)
  if not areaId then return "Unknown" end
  if areaId < 0 then return "Class / profession" end
  local cached = zoneNameCache[areaId]
  if cached then return cached end
  local name = C_Map and C_Map.GetAreaInfo and pcallret(C_Map.GetAreaInfo, areaId)
  if not name or name == "" then
    local ui = D.UiMapForArea(areaId)
    local info = ui and C_Map and pcallret(C_Map.GetMapInfo, ui)
    name = info and info.name
  end
  name = (name and name ~= "") and name or ("Zone " .. areaId)
  zoneNameCache[areaId] = name
  return name
end

function D.PlayerPosition()
  local ui = C_Map and pcallret(C_Map.GetBestMapForUnit, "player")
  if not ui then return end
  local pos = pcallret(C_Map.GetPlayerMapPosition, ui, "player")
  local x, y
  if pos and pos.GetXY then x, y = pos:GetXY() end
  return ui, D.AreaForUiMap(ui), x, y
end

-- Distance in yards between two points on the same map (0-1 coords), when the client knows the map size.
function D.Distance(uiMapId, x1, y1, x2, y2)
  if not (uiMapId and x1 and x2) then return end
  local w, h = pcallret(C_Map and C_Map.GetMapWorldSize, uiMapId)
  if not w or w == 0 then return end
  local dx, dy = (x1 - x2) * w, (y1 - y2) * h
  return sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Search index (built in the background, session only)
---------------------------------------------------------------------------
-- index[i] = { id, lowerName, name, qLevel, rLevel, zone, mine }
local index, unlocks, rewardsByQuest = nil, nil, nil
D.state = "idle" -- idle | building | ready
D.progress = 0
local listeners = {}
function D.OnIndexUpdate(fn) listeners[#listeners + 1] = fn end
local function notify() for _, fn in ipairs(listeners) do pcall(fn) end end

local function availableToPlayer(races, classes)
  if races and races ~= 0 and player.raceMask and band(races, player.raceMask) == 0 then return false end
  if classes and classes ~= 0 and player.classMask and band(classes, player.classMask) == 0 then return false end
  return true
end
D.AvailableToPlayer = availableToPlayer

local KEYS = { "name", "questLevel", "requiredLevel", "zoneOrSort", "requiredRaces", "requiredClasses",
  "preQuestGroup", "preQuestSingle" }

function D.BuildIndex()
  if D.state ~= "idle" or not D.Init() then return end
  D.RefreshPlayer()
  D.RefreshCompleted()
  D.state = "building"
  local questIds = pcallret(QuestDB.GetAllIds) or {}
  local itemIds -- fetched after quests
  local newIndex, newUnlocks, newRewards = {}, {}, {}
  local qi, ii, phase = 1, 1, 1
  local total = #questIds
  local worker = CreateFrame("Frame")
  local budget = 6 -- ms per frame
  local clock = debugprofilestop

  worker:SetScript("OnUpdate", function(self)
    local t0 = clock()
    if phase == 1 then
      while qi <= total and clock() - t0 < budget do
        local id = questIds[qi]
        local v = QuestDB.GetAll and pcallret(QuestDB.GetAll, id, KEYS)
        if not v then
          v = {}
          for k = 1, #KEYS do v[k] = Q(KEYS[k], id) end
        end
        if v and v[1] then
          local name = v[1]
          newIndex[#newIndex + 1] = { id, name:lower(), name, v[2] or 0, v[3] or 0, v[4] or 0,
            availableToPlayer(v[5], v[6]) }
          for k = 7, 8 do
            local list = v[k]
            if type(list) == "table" then
              for _, pre in ipairs(list) do
                local u = newUnlocks[pre]
                if not u then u = {}; newUnlocks[pre] = u end
                u[#u + 1] = id
              end
            end
          end
        end
        qi = qi + 1
      end
      D.progress = total > 0 and (qi - 1) / total * 0.7 or 0.7
      if qi > total then
        phase = 2
        itemIds = pcallret(ItemDB.GetAllIds) or {}
      end
    else
      local itotal = #itemIds
      while ii <= itotal and clock() - t0 < budget do
        local itemId = itemIds[ii]
        local quests = pcallret(ItemDB.questRewards, itemId)
        if type(quests) == "table" then
          for _, qid in ipairs(quests) do
            local r = newRewards[qid]
            if not r then r = {}; newRewards[qid] = r end
            r[#r + 1] = itemId
          end
        end
        ii = ii + 1
      end
      D.progress = 0.7 + (itotal > 0 and (ii - 1) / itotal * 0.3 or 0.3)
      if ii > itotal then
        self:SetScript("OnUpdate", nil)
        table.sort(newIndex, function(a, b)
          if a[5] ~= b[5] then return a[5] < b[5] end
          return a[3] < b[3]
        end)
        index, unlocks, rewardsByQuest = newIndex, newUnlocks, newRewards
        D.state = "ready"
        D.progress = 1
      end
    end
    notify()
  end)
  notify()
end

function D.IndexReady() return D.state == "ready" end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
-- Returns status, reason. status: done | active | available | locked | high | unavailable
function D.Status(id)
  if D.IsCompleted(id) then return "done" end
  if D.IsOnQuest(id) then return "active" end
  local races, classes = Q("requiredRaces", id), Q("requiredClasses", id)
  if not availableToPlayer(races, classes) then
    return "unavailable", (races and races ~= 0 and player.raceMask and band(races, player.raceMask) == 0)
      and "Not available to your race or faction" or "Not available to your class"
  end
  local excl = Q("exclusiveTo", id)
  if type(excl) == "table" then
    for _, e in ipairs(excl) do
      if D.IsCompleted(e) or D.IsOnQuest(e) then return "unavailable", "Excluded by another quest you did" end
    end
  end
  local maxLvl = Q("requiredMaxLevel", id)
  if maxLvl and maxLvl > 0 and player.level > maxLvl then return "unavailable", "Above max level " .. maxLvl end
  local group = Q("preQuestGroup", id)
  if type(group) == "table" then
    for _, pre in ipairs(group) do
      if not D.IsCompleted(pre) then return "locked", "Needs: " .. (Q("name", pre) or ("quest " .. pre)) end
    end
  end
  local single = Q("preQuestSingle", id)
  if type(single) == "table" and #single > 0 then
    local any = false
    for _, pre in ipairs(single) do if D.IsCompleted(pre) then any = true; break end end
    if not any then return "locked", "Needs: " .. (Q("name", single[1]) or ("quest " .. single[1])) end
  end
  local req = Q("requiredLevel", id) or 0
  if req > player.level then return "high", "Requires level " .. req end
  return "available"
end

-- atlas: preferred icon (checked at runtime); file: fallback; color: on dark panels; ink: on parchment
D.STATUS_STYLE = {
  done        = { label = "Completed",     color = { 0.4, 0.8, 0.4 },  ink = { 0.06, 0.38, 0.06 }, atlas = "UI-LFG-ReadyMark",     file = "Interface\\RaidFrame\\ReadyCheck-Ready" },
  active      = { label = "In quest log",  color = { 1.0, 0.82, 0.0 }, ink = { 0.45, 0.28, 0.0 },  file = "Interface\\GossipFrame\\ActiveQuestIcon" },
  available   = { label = "Available",     color = { 1.0, 1.0, 1.0 },  ink = { 0.1, 0.1, 0.1 },    file = "Interface\\GossipFrame\\AvailableQuestIcon" },
  high        = { label = "Level too low", color = { 0.9, 0.5, 0.2 },  ink = { 0.58, 0.28, 0.0 },  atlas = "UI-LFG-PendingMark",   file = "Interface\\GossipFrame\\AvailableQuestIcon" },
  locked      = { label = "Locked",        color = { 0.6, 0.6, 0.6 },  ink = { 0.36, 0.3, 0.24 },  atlas = "QuestSharing-Padlock", file = "Interface\\GossipFrame\\AvailableQuestIcon" },
  unavailable = { label = "Not for you",   color = { 0.8, 0.3, 0.3 },  ink = { 0.55, 0.08, 0.08 }, atlas = "UI-LFG-DeclineMark",   file = "Interface\\RaidFrame\\ReadyCheck-NotReady" },
}

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------
-- opts: text, minLevel, maxLevel, mineOnly, hideDone, gearOnly, areaId, limit
function D.Search(opts)
  if not index then return {} end
  local text = opts.text and opts.text:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
  local numeric = tonumber(text)
  local out, limit = {}, opts.limit or 400
  for i = 1, #index do
    local e = index[i]
    local ok = true
    if numeric then ok = (e[1] == numeric)
    elseif text ~= "" then
      ok = e[2]:find(text, 1, true) ~= nil
      if not ok and #text >= 3 then ok = D.ZoneName(e[6]):lower():find(text, 1, true) ~= nil end
    end
    if ok and opts.minLevel and e[5] < opts.minLevel and e[4] < opts.minLevel then ok = false end
    if ok and opts.maxLevel and e[5] > opts.maxLevel then ok = false end
    if ok and opts.mineOnly and not e[7] then ok = false end
    if ok and opts.areaId and e[6] ~= opts.areaId then ok = false end
    if ok and opts.hideDone and completed[e[1]] then ok = false end
    if ok and opts.gearOnly and not D.HasGearReward(e[1]) then ok = false end
    if ok then
      out[#out + 1] = e
      if #out >= limit then break end
    end
  end
  return out
end

function D.Entry(id)
  if not index then return end
  for i = 1, #index do if index[i][1] == id then return index[i] end end
end

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------
local GEAR_CLASS = { [2] = true, [4] = true } -- weapon, armor

function D.RewardItems(id)
  return rewardsByQuest and rewardsByQuest[id] or {}
end

function D.HasGearReward(id)
  local items = rewardsByQuest and rewardsByQuest[id]
  if not items then return false end
  for _, itemId in ipairs(items) do
    if GEAR_CLASS[I("class", itemId) or -1] then return true end
  end
  return false
end

-- First weapon/armor reward, for the list icon.
function D.GearRewardItem(id)
  local items = rewardsByQuest and rewardsByQuest[id]
  if not items then return end
  for _, itemId in ipairs(items) do
    if GEAR_CLASS[I("class", itemId) or -1] then return itemId end
  end
end

-- Exact rewards for a quest that is in the quest log (choice vs fixed, XP, money).
function D.LogRewards(id)
  if not D.IsOnQuest(id) then return end
  if C_QuestLog and C_QuestLog.SetSelectedQuest then pcallret(C_QuestLog.SetSelectedQuest, id) end
  local r = { choices = {}, fixed = {} }
  r.xp = pcallret(GetQuestLogRewardXP, id)
  r.money = pcallret(GetQuestLogRewardMoney, id)
  local nChoice = pcallret(GetNumQuestLogChoices, id, true) or pcallret(GetNumQuestLogChoices) or 0
  for i = 1, nChoice do
    local link = pcallret(GetQuestLogItemLink, "choice", i)
    if link then r.choices[#r.choices + 1] = link end
  end
  local nFixed = pcallret(GetNumQuestLogRewards, id) or pcallret(GetNumQuestLogRewards) or 0
  for i = 1, nFixed do
    local link = pcallret(GetQuestLogItemLink, "reward", i)
    if link then r.fixed[#r.fixed + 1] = link end
  end
  return r
end

---------------------------------------------------------------------------
-- XP
---------------------------------------------------------------------------
function D.BaseXP(id)
  local xpMod = Lib and Lib.Support and Lib.Support.Get and Lib.Support.Get("QuestXP")
  local row = xpMod and xpMod.db and xpMod.db[id]
  if row then return row[2], row[1] end
end

-- Classic-style reduction for quests well below your level.
function D.XPAtLevel(id)
  local xp, lvl = D.BaseXP(id)
  if not xp then return end
  lvl = lvl or Q("questLevel", id) or player.level
  local diff = player.level - lvl
  local mult = diff <= 5 and 1 or diff == 6 and 0.8 or diff == 7 and 0.6 or diff == 8 and 0.4 or diff == 9 and 0.2 or 0.1
  if player.level >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then mult = 0 end
  return xp, floor(xp * mult / 5 + 0.5) * 5
end

---------------------------------------------------------------------------
-- Locations
---------------------------------------------------------------------------
-- Pick one spawn: prefer the player's current zone, else the first listed zone.
local function pickSpawn(spawns, preferArea)
  if type(spawns) ~= "table" then return end
  if preferArea and spawns[preferArea] and spawns[preferArea][1] then
    local p = spawns[preferArea][1]
    return preferArea, p[1], p[2], #spawns[preferArea]
  end
  local bestArea, bestCount
  for area, pts in pairs(spawns) do
    if type(pts) == "table" and pts[1] and pts[1][1] and pts[1][1] >= 0 then
      if not bestCount or #pts > bestCount then bestArea, bestCount = area, #pts end
    end
  end
  if bestArea then
    local p = spawns[bestArea][1]
    return bestArea, p[1], p[2], bestCount
  end
end
D.PickSpawn = pickSpawn

-- Returns list of { kind = "npc"|"object"|"item", id, name, area, x, y, extra }
function D.Starters(id)
  local _, curArea = D.PlayerPosition()
  local out = {}
  local sb = Q("startedBy", id)
  if type(sb) ~= "table" then return out end
  for _, npcId in ipairs(sb[1] or {}) do
    local area, x, y = pickSpawn(N("spawns", npcId), curArea)
    out[#out + 1] = { kind = "npc", id = npcId, name = N("name", npcId) or ("NPC " .. npcId), sub = N("subName", npcId),
      area = area or N("zoneID", npcId), x = x, y = y }
  end
  for _, objId in ipairs(sb[2] or {}) do
    local area, x, y = pickSpawn(O("spawns", objId), curArea)
    out[#out + 1] = { kind = "object", id = objId, name = O("name", objId) or ("Object " .. objId),
      area = area or O("zoneID", objId), x = x, y = y }
  end
  for _, itemId in ipairs(sb[3] or {}) do
    out[#out + 1] = { kind = "item", id = itemId, name = I("name", itemId) or ("Item " .. itemId), sources = D.ItemSources(itemId) }
  end
  return out
end

function D.Finishers(id)
  local _, curArea = D.PlayerPosition()
  local out = {}
  local fb = Q("finishedBy", id)
  if type(fb) ~= "table" then return out end
  for _, npcId in ipairs(fb[1] or {}) do
    local area, x, y = pickSpawn(N("spawns", npcId), curArea)
    out[#out + 1] = { kind = "npc", id = npcId, name = N("name", npcId) or ("NPC " .. npcId), sub = N("subName", npcId),
      area = area or N("zoneID", npcId), x = x, y = y }
  end
  for _, objId in ipairs(fb[2] or {}) do
    local area, x, y = pickSpawn(O("spawns", objId), curArea)
    out[#out + 1] = { kind = "object", id = objId, name = O("name", objId) or ("Object " .. objId),
      area = area or O("zoneID", objId), x = x, y = y }
  end
  return out
end

function D.NpcLabel(npcId)
  local name = N("name", npcId) or ("NPC " .. npcId)
  local lo, hi = N("minLevel", npcId), N("maxLevel", npcId)
  local lvl = lo and (hi and hi ~= lo and (lo .. "-" .. hi) or tostring(lo)) or nil
  local rank = N("rank", npcId)
  local tag = (rank == 1 and " Elite") or (rank == 2 and " Rare Elite") or (rank == 3 and " Boss") or (rank == 4 and " Rare") or ""
  return name .. (lvl and (" (" .. lvl .. tag .. ")") or (tag ~= "" and (" (" .. tag:sub(2) .. ")") or ""))
end

-- Up to `limit` drop/vendor sources for an item.
function D.ItemSources(itemId, limit)
  limit = limit or 4
  local out = {}
  for _, npcId in ipairs(I("npcDrops", itemId) or {}) do
    if #out >= limit then break end
    local area, x, y = pickSpawn(N("spawns", npcId))
    out[#out + 1] = { kind = "npc", id = npcId, label = D.NpcLabel(npcId), area = area or N("zoneID", npcId), x = x, y = y }
  end
  for _, objId in ipairs(I("objectDrops", itemId) or {}) do
    if #out >= limit then break end
    local area, x, y = pickSpawn(O("spawns", objId))
    out[#out + 1] = { kind = "object", id = objId, label = O("name", objId) or ("Object " .. objId), area = area or O("zoneID", objId), x = x, y = y }
  end
  for _, npcId in ipairs(I("vendors", itemId) or {}) do
    if #out >= limit then break end
    local area, x, y = pickSpawn(N("spawns", npcId))
    out[#out + 1] = { kind = "vendor", id = npcId, label = "Vendor: " .. (N("name", npcId) or npcId), area = area or N("zoneID", npcId), x = x, y = y }
  end
  local total = #(I("npcDrops", itemId) or {}) + #(I("objectDrops", itemId) or {})
  return out, total
end

-- Structured objectives: { text, targets = { {label, area, x, y} } }
function D.Objectives(id)
  local out = {}
  local obj = Q("objectives", id)
  if type(obj) ~= "table" then return out end
  for _, c in ipairs(obj[1] or {}) do
    local area, x, y = pickSpawn(N("spawns", c[1]))
    out[#out + 1] = { kind = "kill", text = "Kill: " .. D.NpcLabel(c[1]), area = area or N("zoneID", c[1]), x = x, y = y }
  end
  for _, o in ipairs(obj[2] or {}) do
    local area, x, y = pickSpawn(O("spawns", o[1]))
    out[#out + 1] = { kind = "object", text = "Use: " .. (O("name", o[1]) or ("object " .. o[1])), area = area or O("zoneID", o[1]), x = x, y = y }
  end
  for _, it in ipairs(obj[3] or {}) do
    local sources, total = D.ItemSources(it[1], 3)
    out[#out + 1] = { kind = "item", itemId = it[1], text = "Collect: " .. (I("name", it[1]) or ("item " .. it[1])),
      sources = sources, totalSources = total }
  end
  for _, kc in ipairs(obj[5] or {}) do
    local root = kc[2]
    local area, x, y = pickSpawn(N("spawns", root))
    out[#out + 1] = { kind = "kill", text = "Kill: " .. (kc[3] or D.NpcLabel(root)), area = area or N("zoneID", root), x = x, y = y }
  end
  local trig = Q("triggerEnd", id)
  if type(trig) == "table" and trig[1] then
    local area, x, y = pickSpawn(trig[2])
    out[#out + 1] = { kind = "explore", text = "Go to: " .. trig[1], area = area, x = x, y = y }
  end
  return out
end

---------------------------------------------------------------------------
-- Chains
---------------------------------------------------------------------------
-- Returns ordered list of { id, depth } : ancestors (negative depth), self (0), followers (positive)
function D.Chain(id)
  local seen, before, after = { [id] = true }, {}, {}
  local function addPre(qid, depth)
    if depth < -25 then return end
    local pres = {}
    for _, f in ipairs({ "preQuestGroup", "preQuestSingle" }) do
      local l = Q(f, qid)
      if type(l) == "table" then for _, p in ipairs(l) do pres[#pres + 1] = p end end
    end
    local parent = Q("parentQuest", qid)
    if parent and parent > 0 then pres[#pres + 1] = parent end
    for _, p in ipairs(pres) do
      if not seen[p] and #before < 40 then
        seen[p] = true
        addPre(p, depth - 1)
        before[#before + 1] = { p, depth }
      end
    end
  end
  local function addNext(qid, depth)
    if depth > 25 then return end
    local nexts = {}
    local n = Q("nextQuestInChain", qid)
    if n and n > 0 then nexts[#nexts + 1] = n end
    for _, c in ipairs(unlocks and unlocks[qid] or {}) do nexts[#nexts + 1] = c end
    for _, c in ipairs(Q("childQuests", qid) or {}) do nexts[#nexts + 1] = c end
    for _, c in ipairs(nexts) do
      if not seen[c] and #after < 40 then
        seen[c] = true
        after[#after + 1] = { c, depth }
        addNext(c, depth + 1)
      end
    end
  end
  addPre(id, -1)
  addNext(id, 1)
  local out = {}
  for _, e in ipairs(before) do out[#out + 1] = e end
  out[#out + 1] = { id, 0 }
  for _, e in ipairs(after) do out[#out + 1] = e end
  return out
end

---------------------------------------------------------------------------
-- Requirements text
---------------------------------------------------------------------------
local SKILLS = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
  [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering",
  [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }

local function factionName(fid)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local d = pcallret(C_Reputation.GetFactionDataByID, fid)
    if d and d.name then return d.name end
  end
  local n = pcallret(GetFactionInfoByID, fid)
  return n or ("Faction " .. fid)
end
D.FactionName = factionName

function D.Requirements(id)
  local out = {}
  local races, classes = Q("requiredRaces", id), Q("requiredClasses", id)
  local masks = Lib and Lib.Enum and Lib.Enum.factionRaceMasks or {}
  if races and races ~= 0 then
    if races == masks.Alliance then out[#out + 1] = "Alliance only"
    elseif races == masks.Horde then out[#out + 1] = "Horde only"
    else out[#out + 1] = "Race restricted" end
  end
  if classes and classes ~= 0 then
    local names = {}
    for cls, bitv in pairs(Lib and Lib.Enum and Lib.Enum.classKeys or {}) do
      if cls ~= "ALL_CLASSES" and bitv ~= 0 and band(classes, bitv) ~= 0 then
        names[#names + 1] = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
      end
    end
    table.sort(names)
    if #names > 0 then out[#out + 1] = "Class: " .. table.concat(names, ", ") end
  end
  local sk = Q("requiredSkill", id)
  if type(sk) == "table" and sk[1] then
    local name = (C_TradeSkillUI and pcallret(C_TradeSkillUI.GetTradeSkillDisplayName, sk[1])) or SKILLS[sk[1]] or ("Skill " .. sk[1])
    out[#out + 1] = ("%s %d"):format(name, sk[2] or 0)
  end
  local rep = Q("requiredMinRep", id)
  if type(rep) == "table" and rep[1] then out[#out + 1] = ("%s reputation %d+"):format(factionName(rep[1]), rep[2] or 0) end
  local maxLvl = Q("requiredMaxLevel", id)
  if maxLvl and maxLvl > 0 then out[#out + 1] = "Max level " .. maxLvl end
  for _, itemId in ipairs(Q("requiredSourceItems", id) or {}) do
    out[#out + 1] = "Needs item: " .. (I("name", itemId) or itemId)
  end
  return out
end

---------------------------------------------------------------------------
-- Near me: available quests whose giver is in the player's zone
---------------------------------------------------------------------------
local starterZoneCache = {}
local function starterArea(id)
  local c = starterZoneCache[id]
  if c ~= nil then return c or nil end
  local sb = Q("startedBy", id)
  local area
  if type(sb) == "table" then
    if sb[1] and sb[1][1] then area = N("zoneID", sb[1][1])
    elseif sb[2] and sb[2][1] then area = O("zoneID", sb[2][1]) end
  end
  starterZoneCache[id] = area or false
  return area
end

function D.NearMe()
  if not index then return {} end
  D.RefreshPlayer()
  local ui, area, px, py = D.PlayerPosition()
  if not area then return {}, nil end
  local out = {}
  local lvl = player.level
  for i = 1, #index do
    local e = index[i]
    if e[7] and not completed[e[1]] and e[5] <= lvl and e[4] >= lvl - 8 and e[4] <= lvl + 4 then
      local sArea = starterArea(e[1])
      if sArea == area or (not sArea and e[6] == area) then
        local status = D.Status(e[1])
        if status == "available" then
          local dist
          local starters = D.Starters(e[1])
          local s = starters[1]
          if s and s.area == area and s.x then dist = D.Distance(ui, px, py, s.x / 100, s.y / 100) end
          out[#out + 1] = { entry = e, dist = dist }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.dist and b.dist then return a.dist < b.dist end
    if a.dist then return true end
    if b.dist then return false end
    return a.entry[4] < b.entry[4]
  end)
  return out, area
end

---------------------------------------------------------------------------
-- Links
---------------------------------------------------------------------------
function D.QuestLink(id)
  local name = Q("name", id) or ("Quest " .. id)
  local lvl = Q("questLevel", id) or 0
  local link = pcallret(GetQuestLink, id)
  return link or ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, lvl, name)
end
