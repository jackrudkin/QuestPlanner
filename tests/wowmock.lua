-- Permissive WoW API mock for smoke-testing QuestPlanner
local unpack = unpack or table.unpack
local frames = {}
NIL_FIELDS = { Inset = true, TitleText = true, portrait = true, Instructions = true, Text = true, text = true, label = true,
  Icon = true, Name = true, NameFrame = true, IconBorder = true, Count = true }
local function newObj(kind)
  local o = { _kind = kind, _shown = (kind ~= "Frame-top"), _scripts = {}, _text = "", _w = 100, _h = 100, _checked = false, _scroll = 0 }
  local mt = {}
  mt.__index = function(t, k)
    if k:sub(1,1) == "_" or NIL_FIELDS[k] then return nil end
    local f = function(self, ...)
      local a = { ... }
      if k == "SetScript" then self._scripts[a[1]] = a[2]; return end
      if k == "HookScript" then local old = self._scripts[a[1]]; self._scripts[a[1]] = function(...) if old then old(...) end a[2](...) end; return end
      if k == "GetScript" then return self._scripts[a[1]] end
      if k == "Show" then self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end return end
      if k == "Hide" then self._shown = false; return end
      if k == "SetShown" then if a[1] then self:Show() else self:Hide() end return end
      if k == "IsShown" or k == "IsVisible" then return self._shown end
      if k == "SetText" then self._text = a[1] and tostring(a[1]) or ""; return end
      if k == "GetText" then return self._text end
      if k == "SetWidth" then self._w = a[1]; return end
      if k == "SetHeight" then self._h = a[1]; return end
      if k == "SetSize" then self._w, self._h = a[1], a[2]; return end
      if k == "GetWidth" then return self._w end
      if k == "GetHeight" then return self._h end
      if k == "GetStringHeight" then return 12 end
      if k == "GetStringWidth" then return 50 end
      if k == "GetVerticalScroll" then return self._scroll end
      if k == "SetVerticalScroll" then self._scroll = a[1]; return end
      if k == "GetChecked" then return self._checked end
      if k == "SetChecked" then self._checked = a[1]; return end
      if k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0 end
      if k == "CreateFontString" then return newObj("FontString") end
      if k == "CreateTexture" then return newObj("Texture") end
      if k == "GetFontString" then local fs = rawget(self, "_fsobj") or newObj("FontString"); rawset(self, "_fsobj", fs); return fs end
      if k == "GetName" then return self._name end
      if k == "GetCenter" then return 0, 0 end
      if k == "GetEffectiveScale" then return 1 end
      if k == "Cancel" then return end
      return nil
    end
    rawset(t, k, f)
    return f
  end
  return setmetatable(o, mt)
end
function CreateFrame(ftype, name, parent, tpl)
  local o = newObj(ftype)
  o._name = name
  if name then _G[name] = o end
  frames[#frames + 1] = o
  if tpl == "UICheckButtonTemplate" then o.Text = newObj("FontString") end
  return o
end
_G.__frames = frames
UIParent = newObj("Frame"); Minimap = newObj("Frame"); GameTooltip = newObj("Frame")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
hooksecurefunc = function(a, b, c) if type(a) == "string" then local old = _G[a]; _G[a] = function(...) local r = { old(...) } b(...) return unpack(r) end end end
SetItemRef = function() end
bit = { band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a = math.floor(a / 2) b = math.floor(b / 2) p = p * 2 end return r end }
loadstring = loadstring or load
local clock = 0
debugprofilestop = function() clock = clock + 0.5; return clock end
time = os.time; date = os.date
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end io.write(table.concat(t, " "), "\n") end
UnitLevel = function() return 41 end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitRace = function() return "Human", "Human", 1 end
UnitFactionGroup = function() return "Alliance" end
UnitName = function() return "Constable" end
GetRealmName = function() return "Smithers" end
IsAltKeyDown = function() return false end
IsShiftKeyDown = function() return false end
GetQuestDifficultyColor = function(l) return { r = 1, g = 1, b = 0 } end
C_Timer = { NewTimer = function(d, fn) fn(); return { Cancel = function() end } end, After = function(d, fn) fn() end }
C_QuestLog = {
  GetAllCompletedQuestIDs = function() return { 100 } end,
  IsQuestFlaggedCompleted = function(id) return id == 100 end,
  IsOnQuest = function(id) return id == 102 end,
  GetQuestObjectives = function(id) return { { text = "Wolves slain: 3/8", finished = false } } end,
  SetSelectedQuest = function() end,
}
GetQuestLogRewardXP = function() return 3150 end
GetQuestLogRewardMoney = function() return 12345 end
GetNumQuestLogChoices = function() return 2 end
GetNumQuestLogRewards = function() return 0 end
GetQuestLogItemLink = function(kind, i) return "|cff1eff00|Hitem:" .. (5000 + i) .. "::::|h[Choice " .. i .. "]|h|r" end
C_Map = {
  GetBestMapForUnit = function() return 1433 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end,
  GetAreaInfo = function(a) local n = { [44] = "Redridge Mountains", [16591] = "Riverglades" } return n[a] end,
  GetMapInfo = function() return nil end,
  GetMapWorldSize = function() return 2000, 1300 end,
  SetUserWaypoint = function() end,
}
UiMapPoint = { CreateFromCoordinates = function(...) return { ... } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
C_Item = { GetItemIconByID = function() return 133000 end }
Item = { CreateFromItemID = function(_, id) return { ContinueOnItemLoad = function(self, cb) cb() end, GetItemQuality = function() return 2 end,
  GetItemLink = function() return "|Hitem:" .. id .. "|h[x]|h" end, GetItemName = function() return "Item " .. id end } end }
ITEM_QUALITY_COLORS = { [2] = { r = 0, g = 1, b = 0 } }
PawnShouldItemLinkHaveUpgradeArrow = function() return true end
GetCoinTextureString = function(c) return c .. "c" end
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior" }
ChatEdit_InsertLink = function(l) _G.__lastLink = l return true end
PanelTemplates_SetNumTabs = function() end
PanelTemplates_SetTab = function() end
PanelTemplates_TabResize = function() end
SlashCmdList = {}

-- Mock LibQuestieDB
local quests = {
  [100] = { name = "The First Step", questLevel = 38, requiredLevel = 35, zoneOrSort = 44, startedBy = { { 1 } }, finishedBy = { { 1 } }, objectivesText = { "Talk to Bob." }, objectives = {} },
  [101] = { name = "Wolves at the Door", questLevel = 41, requiredLevel = 37, zoneOrSort = 44, preQuestSingle = { 100 }, startedBy = { { 1 } }, finishedBy = { { 2 } },
    objectivesText = { "Kill 8 Wolves." }, objectives = { { { 3, nil, 8 } }, nil, { { 900, nil, 5 } } }, reputationReward = { { 72, 250 } }, requiredRaces = 77 },
  [102] = { name = "Into the Den", questLevel = 42, requiredLevel = 38, zoneOrSort = 44, preQuestSingle = { 101 }, startedBy = { { 2 } }, finishedBy = { { 2 } }, objectivesText = { "Clear the den." }, objectives = {} },
  [103] = { name = "Horde Business", questLevel = 40, requiredLevel = 36, zoneOrSort = 44, requiredRaces = 178, startedBy = { { 1 } }, finishedBy = { { 1 } } },
  [104] = { name = "Riverglades Patrol", questLevel = 43, requiredLevel = 40, zoneOrSort = 16591, startedBy = { { 4 } }, finishedBy = { { 4 } }, triggerEnd = { "Scout the ridge", { [16591] = { { 30, 40 } } } } },
}
local npcs = {
  [1] = { name = "Bob", subName = "Guard", spawns = { [44] = { { 50.1, 52.3 } } }, zoneID = 44, minLevel = 40, maxLevel = 40 },
  [2] = { name = "Captain Rhea", spawns = { [44] = { { 60, 40 } } }, zoneID = 44 },
  [3] = { name = "Dire Wolf", spawns = { [44] = { { 70, 70 } } }, zoneID = 44, minLevel = 39, maxLevel = 41 },
  [4] = { name = "Watcher Cornelius", spawns = { [16591] = { { 66, 80 } } }, zoneID = 16591 },
}
local items = { [900] = { name = "Wolf Pelt", npcDrops = { 3 } }, [7001] = { name = "Den Cleaver", questRewards = { 102 }, class = 2 }, [7002] = { name = "Den Shield", questRewards = { 102 }, class = 4 } }
local function entity(rows)
  local e = {}
  setmetatable(e, { __index = function(t, field) return function(id) local r = rows[id] return r and r[field] end end })
  e.GetAllIds = function() local ids = {} for id in pairs(rows) do ids[#ids + 1] = id end table.sort(ids) return ids end
  e.GetAll = function(id, keys) local r = rows[id]; if not r then return nil end local out = { n = #keys } for i, k in ipairs(keys) do out[i] = r[k] end return out end
  return e
end
LibQuestieDB = {
  Quest = entity(quests), Npc = entity(npcs), Object = entity({}), Item = entity(items),
  RequireContract = function(v) return v <= 4 end,
  Enum = { raceMaskById = { [1] = 1 }, classKeys = { WARRIOR = 1, ALL_CLASSES = 0 }, factionRaceMasks = { Alliance = 77, Horde = 178 } },
  Support = { Get = function(name)
    if name == "ZoneDB" then return { private = { uiMapIdToAreaId = "return { [1433] = 44, [2548] = 16591 }", areaIdToUiMapId = "return { [44] = 1433 }" } } end
    if name == "QuestXP" then return { db = { [101] = { 41, 3150 }, [100] = { 38, 2000 } } } end
  end },
}

-- Atlas lookups: toggled by the test runner to exercise both the atlas and fallback paths
__atlasesPresent = true
C_Texture = { GetAtlasInfo = function(name) if __atlasesPresent then return { width = 16, height = 16 } end end }
UnitXP = function() return 12000 end
UnitXPMax = function() return 98000 end
QuestTextContrast = { UseLightText = function() return false end, GetDefaultDetailsBackgroundAtlas = function() return "QuestDetailsBackgrounds" end }
