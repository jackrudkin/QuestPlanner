-- QuestPlanner: saved plan, events, waypoints, slash commands, minimap button.

local ADDON, QP = ...
local D = QP.Data
local pcallret = D.pcallret

QP.version = "1.0.0"

local function msg(text) print("|cffffd100QuestPlanner|r: " .. text) end
QP.Print = msg

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local defaults = { minimap = { angle = 200, hide = false }, waypoint = "auto" }

local function charKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function copyPlan(plan)
  local out = {}
  for i, e in ipairs(plan or {}) do
    out[i] = { id = e.id, note = e.note, added = e.added, done = e.done }
  end
  return out
end

function QP.LoadSaved()
  QuestPlannerDB = type(QuestPlannerDB) == "table" and QuestPlannerDB or {}
  for k, v in pairs(defaults) do
    if QuestPlannerDB[k] == nil then QuestPlannerDB[k] = type(v) == "table" and CopyTable(v) or v end
  end
  QuestPlannerDB.backup = QuestPlannerDB.backup or {}
  QuestPlannerChar = type(QuestPlannerChar) == "table" and QuestPlannerChar or {}
  QuestPlannerChar.plan = QuestPlannerChar.plan or {}

  -- The Forever client can fail to load a SavedVariables file and then overwrite it.
  -- Keep a copy of each character's plan in the account file and restore from it.
  local backup = QuestPlannerDB.backup[charKey()]
  if #QuestPlannerChar.plan == 0 and backup and #backup > 0 then
    QuestPlannerChar.plan = copyPlan(backup)
    msg(("restored %d planned quests from backup."):format(#backup))
  end
  QP.db, QP.char = QuestPlannerDB, QuestPlannerChar
end

function QP.SaveBackup()
  if QP.char and #QP.char.plan > 0 then
    QuestPlannerDB.backup[charKey()] = copyPlan(QP.char.plan)
  end
end

---------------------------------------------------------------------------
-- Plan
---------------------------------------------------------------------------
local callbacks = {}
function QP.OnPlanChanged(fn) callbacks[#callbacks + 1] = fn end
local function changed() for _, fn in ipairs(callbacks) do pcall(fn) end end
QP.FirePlanChanged = changed

function QP.PlanIndex(id)
  for i, e in ipairs(QP.char.plan) do if e.id == id then return i end end
end

function QP.IsPlanned(id) return QP.PlanIndex(id) ~= nil end

function QP.AddToPlan(id, silent)
  if QP.IsPlanned(id) then return end
  table.insert(QP.char.plan, { id = id, added = time(), done = D.IsCompleted(id) or nil })
  if not silent then msg("planned " .. D.QuestLink(id)) end
  changed()
end

function QP.RemoveFromPlan(id)
  local i = QP.PlanIndex(id)
  if i then table.remove(QP.char.plan, i); changed() end
end

function QP.TogglePlan(id)
  if QP.IsPlanned(id) then QP.RemoveFromPlan(id) else QP.AddToPlan(id) end
end

-- Add a quest plus every prerequisite you have not done, in chain order.
function QP.AddChainToPlan(id)
  local added = 0
  for _, e in ipairs(D.Chain(id)) do
    local qid, depth = e[1], e[2]
    if depth <= 0 and not D.IsCompleted(qid) and not QP.IsPlanned(qid) and D.Status(qid) ~= "unavailable" then
      table.insert(QP.char.plan, { id = qid, added = time() })
      added = added + 1
    end
  end
  msg(("added %d quest(s) from the chain up to %s."):format(added, D.QuestLink(id)))
  changed()
end

function QP.MovePlan(id, delta)
  local i = QP.PlanIndex(id)
  local j = i and i + delta
  local plan = QP.char.plan
  if not j or j < 1 or j > #plan then return end
  plan[i], plan[j] = plan[j], plan[i]
  changed()
end

function QP.SortPlan(mode)
  local plan = QP.char.plan
  local function key(e)
    local area = D.Q("zoneOrSort", e.id) or 0
    return D.ZoneName(area), D.Q("requiredLevel", e.id) or 0, D.Q("name", e.id) or ""
  end
  table.sort(plan, function(a, b)
    if (a.done and true or false) ~= (b.done and true or false) then return not a.done end
    local za, la, na = key(a)
    local zb, lb, nb = key(b)
    if mode == "level" then
      if la ~= lb then return la < lb end
      return na < nb
    end
    if za ~= zb then return za < zb end
    if la ~= lb then return la < lb end
    return na < nb
  end)
  changed()
end

function QP.ClearDone()
  local plan, kept = QP.char.plan, {}
  for _, e in ipairs(plan) do if not e.done then kept[#kept + 1] = e end end
  local removed = #plan - #kept
  QP.char.plan = kept
  msg(("cleared %d completed quest(s)."):format(removed))
  changed()
end

function QP.SetNote(id, note)
  local i = QP.PlanIndex(id)
  if i then QP.char.plan[i].note = (note and note ~= "") and note or nil end
end

local function syncDone()
  local any = false
  for _, e in ipairs(QP.char.plan) do
    local done = D.IsCompleted(e.id) or nil
    if done ~= e.done then e.done = done; any = true end
  end
  if any then changed() end
end

---------------------------------------------------------------------------
-- Waypoints
---------------------------------------------------------------------------
function QP.SetWaypoint(areaId, x, y, title)
  if not (areaId and x and y) or x < 0 then msg("no coordinates for that location."); return end
  local ui = D.UiMapForArea(areaId)
  if not ui then msg(("%s is at %.1f, %.1f in %s (no map for that zone)."):format(title or "Target", x, y, D.ZoneName(areaId))); return end
  local useTomTom = TomTom and TomTom.AddWaypoint and QP.db.waypoint ~= "blizzard"
  if useTomTom then
    pcallret(TomTom.AddWaypoint, TomTom, ui, x / 100, y / 100, { title = title, persistent = false, minimap = true, world = true })
  elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
    local point = UiMapPoint.CreateFromCoordinates(ui, x / 100, y / 100)
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
      pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    if not ok then msg("this map does not allow a map pin.") return end
  end
  msg(("waypoint: %s - %s (%.1f, %.1f)"):format(title or "Target", D.ZoneName(areaId), x, y))
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
function QP.InsertLink(id)
  local link = D.QuestLink(id)
  local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
  if not (insert and insert(link)) then
    local eb = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()
    if eb then
      if ChatEdit_ActivateChat then ChatEdit_ActivateChat(eb) end
      eb:Insert(link)
    end
  end
end

-- Alt-click a quest link in chat to open it in QuestPlanner.
local function hookLinks()
  if type(SetItemRef) ~= "function" then return end
  hooksecurefunc("SetItemRef", function(link)
    if type(link) ~= "string" or not IsAltKeyDown() then return end
    local id = tonumber(link:match("^quest:(%d+)"))
    if id and QP.ShowQuest then QP.ShowQuest(id) end
  end)
end

---------------------------------------------------------------------------
-- Minimap button (no libraries)
---------------------------------------------------------------------------
local mmButton
local function updateMinimapPos()
  if not mmButton then return end
  local angle = math.rad(QP.db.minimap.angle or 200)
  local r = (Minimap:GetWidth() / 2) + 5
  mmButton:ClearAllPoints()
  mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function createMinimapButton()
  local b = CreateFrame("Button", "QuestPlannerMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Book_08")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then QP.ShowTab(3) else QP.Toggle() end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      QP.db.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
      updateMinimapPos()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("QuestPlanner")
    GameTooltip:AddLine("Left-click: open", 1, 1, 1)
    GameTooltip:AddLine("Right-click: my plan", 1, 1, 1)
    GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  mmButton = b
  updateMinimapPos()
  if QP.db.minimap.hide then b:Hide() end
end

function QuestPlanner_OnCompartmentClick() QP.Toggle() end
function QuestPlanner_OnCompartmentEnter(_, button)
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:AddLine("QuestPlanner")
  GameTooltip:AddLine("Click to open", 1, 1, 1)
  GameTooltip:Show()
end
function QuestPlanner_OnCompartmentLeave() GameTooltip:Hide() end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_QUESTPLANNER1 = "/qp"
SLASH_QUESTPLANNER2 = "/questplanner"
SlashCmdList.QUESTPLANNER = function(input)
  input = input or ""
  local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then QP.Toggle()
  elseif cmd == "plan" then QP.ShowTab(3)
  elseif cmd == "near" then QP.ShowTab(2)
  elseif cmd == "add" and tonumber(rest) then QP.AddToPlan(tonumber(rest))
  elseif cmd == "minimap" then
    QP.db.minimap.hide = not QP.db.minimap.hide
    if mmButton then mmButton:SetShown(not QP.db.minimap.hide) end
    msg("minimap button " .. (QP.db.minimap.hide and "hidden" or "shown") .. ".")
  elseif cmd == "waypoints" then
    QP.db.waypoint = QP.db.waypoint == "blizzard" and "auto" or "blizzard"
    msg("waypoints use " .. (QP.db.waypoint == "blizzard" and "the game map pin" or "TomTom when installed, else the map pin") .. ".")
  elseif tonumber(cmd) then QP.ShowQuest(tonumber(cmd))
  else
    QP.ShowSearch(input)
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_REMOVED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then QP.LoadSaved() end
  elseif event == "PLAYER_LOGIN" then
    createMinimapButton()
    hookLinks()
    D.Init()
    D.RefreshPlayer()
    D.RefreshCompleted()
    syncDone()
  elseif event == "PLAYER_LOGOUT" then
    QP.SaveBackup()
  elseif event == "QUEST_TURNED_IN" then
    if arg1 then D.completed[arg1] = true end
    syncDone()
    if QP.Refresh then QP.Refresh() end
  elseif event == "PLAYER_LEVEL_UP" then
    D.player.level = arg1 or UnitLevel("player")
    if QP.Refresh then QP.Refresh() end
  else
    if QP.Refresh then QP.Refresh() end
  end
end)
