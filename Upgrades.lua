-- QuestPlanner: recommends quests whose rewards are gear upgrades for you.
--
-- With Pawn installed, every reward is scored by Pawn's own upgrade check
-- (PawnIsItemAnUpgrade): your enabled scales, your best armor type, one- vs two-handers,
-- and the best items Pawn has seen you own. Without Pawn it falls back to item level
-- against what you wear, only for the same armor or weapon type as the item you wear in that slot.

local _, QP = ...
local D = QP.Data
local pcallret = D.pcallret
local max = math.max

local U = { state = "idle", progress = 0, results = {}, byQuest = {}, dirty = true, method = nil }
QP.Upgrades = U

local DEFAULT_AHEAD = 3   -- levels above you to look
local LEVEL_FLOOR = 10    -- ignore quests more than this many levels below you
local MAX_WAIT = 8        -- seconds to wait for item data from the server
local RETRY_EVERY = 0.5
local BUDGET_MS = 6
local BIG = 100           -- Pawn's "big upgrade" value (empty slot); shown as "Empty slot"
U.BIG = BIG

local GEAR_CLASS = { [2] = true, [4] = true } -- weapon, armor

local listeners = {}
function U.OnUpdate(fn) listeners[#listeners + 1] = fn end
local function notify() for _, fn in ipairs(listeners) do pcall(fn) end end

function U.Settings()
  local db = QP.db or {}
  db.upgrades = db.upgrades or {}
  local s = db.upgrades
  if s.ahead == nil then s.ahead = DEFAULT_AHEAD end
  if s.availableOnly == nil then s.availableOnly = false end
  return s
end

function U.UsingPawn()
  if not (PawnIsReady and PawnGetItemData and PawnIsItemAnUpgrade) then return false end
  return pcallret(PawnIsReady) and true or false
end

local function itemInfo(item)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return pcallret(fn, item)
end

local function requestItem(itemId)
  if C_Item and C_Item.RequestLoadItemDataByID then pcallret(C_Item.RequestLoadItemDataByID, itemId) end
end

---------------------------------------------------------------------------
-- Scoring. Each returns: table (upgrade), false (not an upgrade), nil (data not loaded yet)
---------------------------------------------------------------------------
local function scorePawn(itemId)
  local name, link = itemInfo(itemId)
  if not name or not link then return nil end
  local item = pcallret(PawnGetItemData, link)
  if not item then return false end      -- an item that can't have stats
  if not item.Link then return nil end   -- stats not loaded yet
  local info = pcallret(PawnIsItemAnUpgrade, item)
  if type(info) ~= "table" or not info[1] then return false end
  local best
  for _, u in ipairs(info) do
    if type(u) == "table" and (not best or (u.PercentUpgrade or 0) > (best.PercentUpgrade or 0)) then best = u end
  end
  if not best then return false end
  return { pct = best.PercentUpgrade or 0, scale = best.LocalizedScaleName or best.ScaleName, existing = best.ExistingItemLink, link = link }
end

-- Item-level fallback
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}
local ANY_TYPE = { INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_CLOAK = true }

local wornArmorType -- most common armor subclass you wear (for empty slots)
local function refreshWorn()
  local counts, best, bestN = {}, nil, 0
  for _, slot in ipairs({ 1, 3, 5, 6, 7, 8, 9, 10 }) do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if link then
      local _, _, _, _, _, _, _, _, _, _, _, classID, subID = itemInfo(link)
      if classID == 4 and subID then
        counts[subID] = (counts[subID] or 0) + 1
        if counts[subID] > bestN then best, bestN = subID, counts[subID] end
      end
    end
  end
  wornArmorType = best
end

local function scoreItemLevel(itemId)
  local name, link, _, ilvl, _, _, _, _, equipLoc, _, _, classID, subID = itemInfo(itemId)
  if not name then return nil end
  local slots = SLOTS[equipLoc or ""]
  if not slots or not ilvl or ilvl <= 0 then return false end
  local best
  for _, slot in ipairs(slots) do
    local curLink = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if curLink then
      local cname, _, _, cur, _, _, _, _, _, _, _, cClass, cSub = itemInfo(curLink)
      if not cname then return nil end
      local sameType = ANY_TYPE[equipLoc] or (classID == cClass and subID == cSub)
      if sameType and cur and ilvl > cur then
        local pct = (ilvl - cur) / max(1, cur)
        if not best or pct > best.pct then best = { pct = pct, ilvlGain = ilvl - cur, existing = curLink, link = link } end
      end
    elseif ANY_TYPE[equipLoc] or (classID == 4 and subID == wornArmorType) then
      best = { pct = BIG, existing = nil, link = link }
    end
  end
  return best or false
end

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------
local worker

-- Results stay visible until the next scan replaces them.
function U.MarkDirty() U.dirty = true end

function U.Get(questId) return U.byQuest[questId] end

local function gearRewards(questId)
  local out
  for _, itemId in ipairs(D.RewardItems(questId)) do
    if GEAR_CLASS[D.I("class", itemId) or -1] then
      out = out or {}
      out[#out + 1] = itemId
    end
  end
  return out
end

function U.Scan(force)
  if U.state == "scanning" then return end
  if not D.IndexReady() then U.dirty = true; return end
  if not force and not U.dirty and U.state == "ready" then return end
  D.RefreshPlayer()
  D.RefreshCompleted()
  refreshWorn()
  U.dirty = false
  U.state = "scanning"
  U.progress = 0
  U.method = U.UsingPawn() and "pawn" or "ilvl"
  local score = U.method == "pawn" and scorePawn or scoreItemLevel
  local s = U.Settings()
  local lvl = D.player.level or 1
  local maxReq = lvl + (s.ahead or DEFAULT_AHEAD)

  -- Candidates: quests you can take (race/class), not done, in range, with weapon/armor rewards
  local queue = {}
  for _, e in ipairs(D.AllEntries()) do
    local id = e[1]
    if e[7] and e[5] <= maxReq and e[4] >= lvl - LEVEL_FLOOR and not D.IsCompleted(id) then
      local items = gearRewards(id)
      if items then
        queue[#queue + 1] = { id = id, entry = e, items = items }
        for _, itemId in ipairs(items) do
          if not itemInfo(itemId) then requestItem(itemId) end
        end
      end
    end
  end

  local total = #queue
  local cache, results, byQuest = {}, {}, {}
  local retry, qi, done = {}, 1, 0
  local started = GetTime and GetTime() or 0
  local nextPass = 0
  worker = worker or CreateFrame("Frame")
  worker:SetScript("OnUpdate", function(self)
    local now = GetTime and GetTime() or (started + MAX_WAIT + 1)
    local t0 = debugprofilestop()
    if qi > #queue and #retry > 0 then
      -- Second and later passes over quests whose items were still loading. After MAX_WAIT
      -- the pass below finalises them with whatever loaded.
      if now < nextPass and now - started < MAX_WAIT then return end
      queue, retry, qi = retry, {}, 1
    end
    while qi <= #queue and debugprofilestop() - t0 < BUDGET_MS do
      local c = queue[qi]
      qi = qi + 1
      local pending, best = false, nil
      for _, itemId in ipairs(c.items) do
        local r = cache[itemId]
        if r == nil then
          r = score(itemId)
          if r == nil then pending = true; requestItem(itemId) else cache[itemId] = r end
        end
        if r and (not best or r.pct > best.pct) then
          best = { itemId = itemId, pct = r.pct, scale = r.scale, existing = r.existing, link = r.link, ilvlGain = r.ilvlGain }
        end
      end
      if pending and now - started < MAX_WAIT then
        retry[#retry + 1] = c
      else
        done = done + 1
        byQuest[c.id] = best or false
        if best then
          best.id = c.id
          best.entry = c.entry
          results[#results + 1] = best
        end
      end
    end
    if qi > #queue and #retry > 0 then nextPass = now + RETRY_EVERY end
    U.progress = total > 0 and done / total or 1
    if qi > #queue and #retry == 0 then
      self:SetScript("OnUpdate", nil)
      table.sort(results, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        if a.entry[5] ~= b.entry[5] then return a.entry[5] < b.entry[5] end
        return a.id < b.id
      end)
      U.results, U.byQuest = results, byQuest
      U.state = "ready"
      U.progress = 1
    end
    notify()
  end)
  notify()
end

-- Results filtered for display (status re-checked: done/unavailable drop out)
function U.List()
  local s = U.Settings()
  local out = {}
  for _, r in ipairs(U.results) do
    local st = D.Status(r.id)
    local ok = st ~= "done" and st ~= "unavailable"
    if ok and s.availableOnly then ok = (st == "available" or st == "active") end
    if ok then out[#out + 1] = r end
  end
  return out
end

-- "+12.4%", "Empty slot", or "+5 item levels"
function U.Label(r)
  if not r then return "" end
  if r.pct >= BIG then return "Empty slot" end
  if U.method == "ilvl" and r.ilvlGain then return ("+%d item level%s"):format(r.ilvlGain, r.ilvlGain == 1 and "" or "s") end
  return ("+%.1f%%"):format(r.pct * 100)
end
