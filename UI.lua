-- QuestPlanner: user interface.
-- Built on Blizzard templates and atlases from the WoW Forever client. Every atlas is checked
-- at runtime (C_Texture.GetAtlasInfo) and falls back to a plain texture, so nothing breaks
-- if Blizzard renames one. No libraries.

local _, QP = ...
local D = QP.Data
local U = QP.Upgrades
local pcallret = D.pcallret
local floor, max, min = math.floor, math.max, math.min

local W, H = 880, 600
local LIST_W = 340
local ROW_H = 34
local PAD_TOP, PAD_BOTTOM = 62, 30

local frame, tabs, list, detail, statusText, progressBar
local TAB_BROWSE, TAB_NEAR, TAB_UPGRADES, TAB_PLAN = 1, 2, 3, 4
local activeTab = TAB_BROWSE
local selectedId
local history = {}
local filters = { mineOnly = true, hideDone = true, gearOnly = false, zoneOnly = false }
local refreshList, reorderUpdate -- forward declarations

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function create(ftype, name, parent, ...)
  for i = 1, select("#", ...) do
    local tpl = select(i, ...)
    local ok, f = pcall(CreateFrame, ftype, name, parent, tpl)
    if ok and f then return f, tpl end
  end
  return CreateFrame(ftype, name, parent)
end

local function setFont(fs, ...)
  for i = 1, select("#", ...) do
    local obj = _G[select(i, ...)]
    if obj then fs:SetFontObject(obj); return end
  end
end

local function colorText(text, r, g, b)
  if type(r) == "table" then r, g, b = r[1], r[2], r[3] end
  return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

local function levelColor(level)
  local c = GetQuestDifficultyColor and GetQuestDifficultyColor(level or 0)
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

local function fmtNumber(n)
  local s = tostring(floor(n or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

local function fmtMoney(copper)
  if not copper or copper <= 0 then return nil end
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  return ("%dg %ds %dc"):format(copper / 10000, (copper / 100) % 100, copper % 100)
end

local function fmtCoords(area, x, y)
  if not area then return "Location unknown" end
  if x and x >= 0 then return ("%s  %.1f, %.1f"):format(D.ZoneName(area), x, y) end
  return D.ZoneName(area)
end

local function playerXPMax()
  local m = UnitXPMax and pcallret(UnitXPMax, "player")
  return (m and m > 0) and m or nil
end

---------------------------------------------------------------------------
-- Icons. { atlas, fallback file }. Atlases verified in the Forever 1.60.1 UI source.
---------------------------------------------------------------------------
local atlasOK = {}
local function hasAtlas(name)
  if not name then return false end
  local ok = atlasOK[name]
  if ok == nil then
    ok = (C_Texture and C_Texture.GetAtlasInfo and pcallret(C_Texture.GetAtlasInfo, name)) and true or false
    atlasOK[name] = ok
  end
  return ok
end

local ICON = {
  giver      = { "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon" },
  turnin     = { "QuestTurnin", "Interface\\GossipFrame\\ActiveQuestIcon" },
  pin        = { "Waypoint-MapPin-Untracked" },
  pinHi      = { "Waypoint-MapPin-Highlight" },
  objectives = { "questlog-icon-checkmark-yellow", "Interface\\RaidFrame\\ReadyCheck-Ready" },
  nub        = { "ui-questtracker-objective-nub" },
  check      = { "ui-questtracker-tracker-check", "Interface\\RaidFrame\\ReadyCheck-Ready" },
  combat     = { "GarrMission_MissionIcon-Combat" },
  rewards    = { "ParagonReputation_Bag", "Interface\\Icons\\INV_Misc_Coin_01" },
  lock       = { "QuestSharing-Padlock" },
  chain      = { "questlog-storylineicon", "Interface\\Icons\\INV_Misc_Book_08" },
  star       = { "PetJournal-FavoritesIcon" },
  note       = { "Pencil-Icon" },
  back       = { "common-icon-backarrow" },
  upgrade    = { "bags-greenarrow" },
  xp         = { nil, "Interface\\Icons\\XP_Icon" },
  coin       = { nil, "Interface\\Icons\\INV_Misc_Coin_01" },
  book       = { nil, "Interface\\Icons\\INV_Misc_Book_08" },
}

-- Returns true when a plain file texture was used (icons look better cropped).
local function setIcon(tex, spec)
  tex:SetTexCoord(0, 1, 0, 1)
  if spec and hasAtlas(spec[1]) then tex:SetAtlas(spec[1]) return false end
  if spec and spec[2] then tex:SetTexture(spec[2]) return true end
  tex:SetTexture(nil)
  return false
end

local function iconMarkup(spec, size)
  size = size or 14
  if spec and hasAtlas(spec[1]) then return ("|A:%s:%d:%d|a"):format(spec[1], size, size) end
  if spec and spec[2] then return ("|T%s:%d:%d|t"):format(spec[2], size, size) end
  return ""
end

local function statusIcon(status)
  local s = D.STATUS_STYLE[status] or D.STATUS_STYLE.available
  return { s.atlas, s.file }, s
end

local function itemIcon(itemId)
  return (C_Item and C_Item.GetItemIconByID and pcallret(C_Item.GetItemIconByID, itemId))
    or (GetItemIcon and pcallret(GetItemIcon, itemId)) or 134400
end

---------------------------------------------------------------------------
-- Detail palette: dark ink on parchment, or light text when the player uses
-- a dark Quest Text Contrast setting (or the parchment atlas is missing).
---------------------------------------------------------------------------
local T
local function pickTheme(forceLight)
  local light = forceLight or (QuestTextContrast and QuestTextContrast.UseLightText and pcallret(QuestTextContrast.UseLightText))
  if light then
    T = { light = true, ink = { 1, 1, 1 }, head = { 1, 0.82, 0 }, sub = { 0.9, 0.78, 0.5 }, muted = { 0.62, 0.62, 0.62 },
      link = { 0.55, 0.8, 1 }, good = { 0.45, 0.9, 0.45 }, bad = { 1, 0.45, 0.45 }, warn = { 1, 0.65, 0.25 },
      line = { 1, 0.82, 0, 0.3 }, band = { 1, 1, 1, 0.05 }, hover = { 1, 1, 1, 0.07 } }
  else
    T = { ink = { 0, 0, 0 }, head = { 0.24, 0.13, 0 }, sub = { 0.30, 0.18, 0 }, muted = { 0.38, 0.30, 0.20 },
      link = { 0.04, 0.22, 0.48 }, good = { 0.06, 0.38, 0.06 }, bad = { 0.55, 0.08, 0.08 }, warn = { 0.58, 0.28, 0 },
      line = { 0.30, 0.18, 0, 0.35 }, band = { 0.30, 0.18, 0, 0.09 }, hover = { 0.55, 0.38, 0.05, 0.16 } }
  end
end

---------------------------------------------------------------------------
-- Main frame
---------------------------------------------------------------------------
local function savePosition()
  local p, _, rp, x, y = frame:GetPoint()
  QP.db.pos = { p, rp, x, y }
end

local function buildFrame()
  frame = create("Frame", "QuestPlannerFrame", UIParent, "ButtonFrameTemplate", "BasicFrameTemplateWithInset")
  frame:SetSize(W, H)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); savePosition() end)
  local pos = QP.db.pos
  if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER") end
  frame:Hide()
  tinsert(UISpecialFrames, "QuestPlannerFrame")

  if frame.SetTitle then frame:SetTitle("QuestPlanner")
  else
    local t = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, -5)
    t:SetText("QuestPlanner")
  end
  if frame.SetPortraitToAsset then pcall(frame.SetPortraitToAsset, frame, ICON.book[2])
  elseif frame.portrait then frame.portrait:SetTexture(ICON.book[2]) end
  if frame.Inset then frame.Inset:Hide() end

  -- Left: quest list on the quest log background
  local left = create("Frame", nil, frame, "InsetFrameTemplate", "BackdropTemplate")
  left:SetPoint("TOPLEFT", 10, -PAD_TOP)
  left:SetPoint("BOTTOMLEFT", 10, PAD_BOTTOM)
  left:SetWidth(LIST_W)
  frame.left = left
  local lbg = left:CreateTexture(nil, "BACKGROUND", nil, 1)
  lbg:SetPoint("TOPLEFT", 3, -3)
  lbg:SetPoint("BOTTOMRIGHT", -3, 3)
  if hasAtlas("QuestLog-main-background") then lbg:SetAtlas("QuestLog-main-background")
  else lbg:SetColorTexture(0.05, 0.05, 0.07, 0.92) end

  -- Right: quest details on parchment
  local right = create("Frame", nil, frame, "InsetFrameTemplate", "BackdropTemplate")
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
  right:SetPoint("BOTTOMRIGHT", -10, PAD_BOTTOM)
  frame.right = right
  local bg = right:CreateTexture(nil, "BACKGROUND", nil, 1)
  bg:SetPoint("TOPLEFT", 3, -3)
  bg:SetPoint("BOTTOMRIGHT", -3, 3)
  local atlas = QuestTextContrast and QuestTextContrast.GetDefaultDetailsBackgroundAtlas
    and pcallret(QuestTextContrast.GetDefaultDetailsBackgroundAtlas)
  if not hasAtlas(atlas) then
    atlas = (hasAtlas("QuestDetailsBackgrounds") and "QuestDetailsBackgrounds") or (hasAtlas("QuestBG-Parchment") and "QuestBG-Parchment") or nil
  end
  if atlas then bg:SetAtlas(atlas); pickTheme(false)
  else bg:SetColorTexture(0.10, 0.08, 0.05, 0.95); pickTheme(true) end
end

---------------------------------------------------------------------------
-- Toolbar (search + filters) above the list
---------------------------------------------------------------------------
local searchBox, minBox, maxBox, planBar, upBar

local function tooltipFor(widget, text, anchor)
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, anchor or "ANCHOR_TOP")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function makeCheck(parent, label, key, tip)
  local cb = create("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  local text = cb.Text or cb.text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:ClearAllPoints()
  text:SetPoint("LEFT", cb, "RIGHT", 0, 1)
  setFont(text, "GameFontHighlightSmall")
  text:SetText(label)
  cb:SetChecked(filters[key])
  cb:SetScript("OnClick", function(self)
    filters[key] = self:GetChecked() and true or false
    refreshList()
  end)
  tooltipFor(cb, tip)
  cb.label = text
  return cb
end

local refreshTimer
local function scheduleRefresh()
  if refreshTimer then refreshTimer:Cancel() end
  refreshTimer = C_Timer.NewTimer(0.25, function() refreshTimer = nil; refreshList() end)
end

local function buildToolbar()
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", 64, -28)
  bar:SetPoint("TOPRIGHT", -12, -28)
  bar:SetHeight(30)
  frame.toolbar = bar

  searchBox = create("EditBox", "QuestPlannerSearchBox", bar, "SearchBoxTemplate", "InputBoxTemplate")
  searchBox:SetSize(230, 20)
  searchBox:SetPoint("LEFT", 8, 0)
  searchBox:SetAutoFocus(false)
  if searchBox.Instructions then searchBox.Instructions:SetText("Quest name, ID or zone") end
  searchBox:HookScript("OnTextChanged", function(_, user) if user then scheduleRefresh() end end)
  searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); refreshList() end)

  local lvlLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lvlLabel:SetPoint("LEFT", searchBox, "RIGHT", 14, 0)
  lvlLabel:SetText("Level")

  local function numBox(anchor, dx)
    local b = create("EditBox", nil, bar, "InputBoxTemplate")
    b:SetSize(28, 20)
    b:SetPoint("LEFT", anchor, "RIGHT", dx, 0)
    b:SetAutoFocus(false)
    b:SetNumeric(true)
    b:SetMaxLetters(2)
    b:SetJustifyH("CENTER")
    b:SetScript("OnTextChanged", function(_, user) if user then scheduleRefresh() end end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    b:SetScript("OnTabPressed", function(self) self:ClearFocus() end)
    return b
  end
  minBox = numBox(lvlLabel, 10)
  local dash = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dash:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
  dash:SetText("-")
  maxBox = numBox(dash, 8)

  local prev = maxBox
  local specs = {
    { "For me", "mineOnly", "Only quests your race and class can take." },
    { "Hide done", "hideDone", "Hide quests you have already completed." },
    { "Gear", "gearOnly", "Only quests that reward a weapon or armor." },
    { "This zone", "zoneOnly", "Only quests in the zone you are in." },
  }
  for i, s in ipairs(specs) do
    local cb = makeCheck(bar, s[1], s[2], s[3])
    cb:SetPoint("LEFT", prev, "RIGHT", i == 1 and 14 or (prev.label:GetStringWidth() + 6), 0)
    prev = cb
  end

  -- Plan tab toolbar (replaces the filters)
  planBar = CreateFrame("Frame", nil, frame)
  planBar:SetAllPoints(bar)
  planBar:Hide()
  local function pbtn(label, w, fn, tip, anchor)
    local b = create("Button", nil, planBar, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(label)
    if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else b:SetPoint("LEFT", 8, 0) end
    b:SetScript("OnClick", fn)
    tooltipFor(b, tip)
    return b
  end
  local b1 = pbtn("Sort by zone", 100, function() QP.SortPlan("zone") end, "Group your plan by zone, then level.")
  local b2 = pbtn("Sort by level", 100, function() QP.SortPlan("level") end, "Order your plan by required level.", b1)
  local b3 = pbtn("Clear completed", 120, function() QP.ClearDone() end, "Remove quests you have turned in.", b2)
  planBar.summary = planBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  planBar.summary:SetPoint("LEFT", b3, "RIGHT", 14, 0)
  planBar.summary:SetPoint("RIGHT", -8, 0)
  planBar.summary:SetJustifyH("LEFT")

  -- Upgrades tab toolbar
  upBar = CreateFrame("Frame", nil, frame)
  upBar:SetAllPoints(bar)
  upBar:Hide()
  local aheadLabel = upBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  aheadLabel:SetPoint("LEFT", 10, 0)
  aheadLabel:SetText("Quests up to")
  local ahead = create("EditBox", nil, upBar, "InputBoxTemplate")
  ahead:SetSize(24, 20)
  ahead:SetPoint("LEFT", aheadLabel, "RIGHT", 10, 0)
  ahead:SetAutoFocus(false)
  ahead:SetNumeric(true)
  ahead:SetMaxLetters(2)
  ahead:SetJustifyH("CENTER")
  local aheadTail = upBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  aheadTail:SetPoint("LEFT", ahead, "RIGHT", 6, 0)
  aheadTail:SetText("levels above you")
  local function applyAhead(self)
    local n = tonumber(self:GetText())
    if n and n ~= U.Settings().ahead then U.Settings().ahead = n; U.MarkDirty(); refreshList() end
  end
  ahead:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  ahead:SetScript("OnEditFocusLost", applyAhead)
  tooltipFor(ahead, "How many levels above you a quest's required level may be. Press Enter to apply.")
  upBar.ahead = ahead

  local avail = create("CheckButton", nil, upBar, "UICheckButtonTemplate")
  avail:SetSize(22, 22)
  avail:SetPoint("LEFT", aheadTail, "RIGHT", 14, 0)
  local atext = avail.Text or avail.text or avail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  atext:ClearAllPoints()
  atext:SetPoint("LEFT", avail, "RIGHT", 0, 1)
  setFont(atext, "GameFontHighlightSmall")
  atext:SetText("Available now")
  avail:SetScript("OnClick", function(self) U.Settings().availableOnly = self:GetChecked() and true or false; refreshList() end)
  tooltipFor(avail, "Hide quests you can't take yet (level too low or prerequisites missing).")
  upBar.avail = avail

  local rescan = create("Button", nil, upBar, "UIPanelButtonTemplate")
  rescan:SetSize(80, 22)
  rescan:SetText("Rescan")
  rescan:SetPoint("LEFT", atext, "RIGHT", 12, 0)
  rescan:SetScript("OnClick", function() U.Scan(true); refreshList() end)
  tooltipFor(rescan, "Score every quest reward again (it also rescans by itself after gear changes, level-ups and turn-ins).")

  upBar.summary = upBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  upBar.summary:SetPoint("LEFT", rescan, "RIGHT", 12, 0)
  upBar.summary:SetPoint("RIGHT", -8, 0)
  upBar.summary:SetJustifyH("LEFT")
end

---------------------------------------------------------------------------
-- Virtual list (two-line rows)
---------------------------------------------------------------------------
local rows, data, offset = {}, {}, 0
local slider

local function rowTooltip(row)
  local e = row.item
  if not e then return end
  local _, style = statusIcon(e.status)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(e.name, 1, 0.82, 0)
  GameTooltip:AddLine(("Level %d  -  requires %d"):format(e.qLevel, e.rLevel), 1, 1, 1)
  GameTooltip:AddLine(D.ZoneName(e.zone), 0.8, 0.8, 0.8)
  GameTooltip:AddLine(style.label, style.color[1], style.color[2], style.color[3])
  if e.note then GameTooltip:AddLine(iconMarkup(ICON.note, 12) .. " " .. e.note, 0.6, 0.9, 1, true) end
  local up = U.Get(e.id)
  if up then
    GameTooltip:AddLine(("Upgrade: %s  %s"):format(D.I("name", up.itemId) or "item", U.Label(up)), 0.3, 1, 0.3)
    if up.scale then GameTooltip:AddLine("Pawn scale: " .. up.scale, 0.7, 0.7, 0.7) end
  elseif e.gearItem then
    GameTooltip:AddLine("Rewards gear: " .. (D.I("name", e.gearItem) or "item"), 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: details   Right-click: add/remove from plan", 0.6, 0.6, 0.6)
  GameTooltip:AddLine("Shift-click: link in chat", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function updateRows()
  local maxOffset = max(0, #data - #rows)
  if offset > maxOffset then offset = maxOffset end
  for i, row in ipairs(rows) do
    local e = data[i + offset]
    row.item = e
    if e then
      local spec = statusIcon(e.status)
      setIcon(row.icon, spec)
      local r, g, b = levelColor(e.qLevel)
      row.level:SetText(e.qLevel > 0 and e.qLevel or "?")
      row.level:SetTextColor(r, g, b)
      row.chipEdge:SetColorTexture(r, g, b, 0.9)
      row.name:SetText(e.name)
      if e.status == "done" then row.name:SetTextColor(0.5, 0.5, 0.5)
      elseif e.status == "unavailable" then row.name:SetTextColor(0.85, 0.4, 0.4)
      elseif e.status == "active" then row.name:SetTextColor(1, 0.82, 0)
      else row.name:SetTextColor(1, 1, 1) end
      row.sub:SetText(e.sub or "")

      if e.gearItem == nil then e.gearItem = D.GearRewardItem(e.id) or false end
      local up = U.Get(e.id)
      row.upArrow:SetShown(up and true or false)
      local shown = up and up.itemId or e.gearItem
      if shown then
        row.reward:SetTexture(itemIcon(shown))
        row.reward:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.reward:Show(); row.rewardEdge:Show()
      else
        row.reward:Hide(); row.rewardEdge:Hide()
      end
      row.star:SetShown(activeTab ~= TAB_PLAN and QP.IsPlanned(e.id))
      local sel = e.id == selectedId
      row.sel:SetShown(sel)
      row.selBar:SetShown(sel)
      row:Show()
    else
      row:Hide()
    end
  end
  slider:SetMinMaxValues(0, maxOffset)
  slider:SetValue(offset)
  slider:SetShown(maxOffset > 0)
end

local function buildRow(i)
  local row = CreateFrame("Button", nil, list)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local stripe = row:CreateTexture(nil, "BACKGROUND")
  stripe:SetAllPoints()
  stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0)
  row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(1, 0.82, 0, 0.13)
  row.selBar = row:CreateTexture(nil, "ARTWORK")
  row.selBar:SetPoint("TOPLEFT")
  row.selBar:SetPoint("BOTTOMLEFT")
  row.selBar:SetWidth(3)
  row.selBar:SetColorTexture(1, 0.82, 0, 0.95)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.55)

  -- Level chip
  row.chip = row:CreateTexture(nil, "ARTWORK")
  row.chip:SetSize(28, 22)
  row.chip:SetPoint("LEFT", 8, 0)
  row.chip:SetColorTexture(0, 0, 0, 0.6)
  row.chipEdge = row:CreateTexture(nil, "ARTWORK", nil, 1)
  row.chipEdge:SetPoint("BOTTOMLEFT", row.chip, "BOTTOMLEFT")
  row.chipEdge:SetPoint("BOTTOMRIGHT", row.chip, "BOTTOMRIGHT")
  row.chipEdge:SetHeight(2)
  row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.level:SetPoint("CENTER", row.chip, "CENTER", 0, 1)

  row.icon = row:CreateTexture(nil, "OVERLAY")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row.chip, "RIGHT", 6, 0)

  -- Right side: gear reward icon + plan star
  row.reward = row:CreateTexture(nil, "ARTWORK", nil, 1)
  row.reward:SetSize(20, 20)
  row.reward:SetPoint("RIGHT", -6, 0)
  row.rewardEdge = row:CreateTexture(nil, "ARTWORK")
  row.rewardEdge:SetPoint("TOPLEFT", row.reward, "TOPLEFT", -1, 1)
  row.rewardEdge:SetPoint("BOTTOMRIGHT", row.reward, "BOTTOMRIGHT", 1, -1)
  row.rewardEdge:SetColorTexture(0, 0, 0, 0.8)
  row.upArrow = row:CreateTexture(nil, "OVERLAY", nil, 2)
  row.upArrow:SetSize(14, 14)
  row.upArrow:SetPoint("BOTTOMLEFT", row.reward, "BOTTOMLEFT", -5, -3)
  setIcon(row.upArrow, ICON.upgrade)
  row.upArrow:Hide()
  row.star = row:CreateTexture(nil, "OVERLAY")
  row.star:SetSize(14, 14)
  row.star:SetPoint("RIGHT", row.reward, "LEFT", -5, 0)
  setIcon(row.star, ICON.star)

  local textX = 8 + 28 + 6 + 16 + 6
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -4)
  row.name:SetPoint("RIGHT", row.star, "LEFT", -4, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", textX, 5)
  row.sub:SetPoint("RIGHT", row.star, "LEFT", -4, 0)
  row.sub:SetJustifyH("LEFT")
  row.sub:SetWordWrap(false)

  row:SetScript("OnClick", function(self, button)
    local e = self.item
    if not e then return end
    if IsShiftKeyDown() then QP.InsertLink(e.id) return end
    if button == "RightButton" then QP.TogglePlan(e.id) return end
    QP.ShowQuest(e.id)
  end)
  row:SetScript("OnEnter", rowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

local function buildList()
  local parent = frame.left
  list = CreateFrame("Frame", nil, parent)
  list:SetPoint("TOPLEFT", 4, -4)
  list:SetPoint("BOTTOMRIGHT", -18, 24)

  local count = floor((H - PAD_TOP - PAD_BOTTOM - 8 - 24) / ROW_H)
  for i = 1, count do rows[i] = buildRow(i) end

  slider = CreateFrame("Slider", nil, parent)
  slider:SetPoint("TOPRIGHT", -5, -6)
  slider:SetPoint("BOTTOMRIGHT", -5, 26)
  slider:SetWidth(8)
  slider:SetOrientation("VERTICAL")
  slider:SetValueStep(1)
  slider:SetObeyStepOnDrag(true)
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(0, 0, 0, 0.45)
  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(0.85, 0.68, 0.25, 0.9)
  thumb:SetSize(8, 34)
  slider:SetThumbTexture(thumb)
  slider:SetScript("OnValueChanged", function(_, v)
    v = floor(v + 0.5)
    if v ~= offset then offset = v; updateRows() end
  end)

  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    offset = max(0, offset - delta * 3)
    updateRows()
  end)

  local foot = parent:CreateTexture(nil, "ARTWORK")
  foot:SetPoint("BOTTOMLEFT", 4, 22)
  foot:SetPoint("BOTTOMRIGHT", -4, 22)
  foot:SetHeight(1)
  foot:SetColorTexture(1, 0.82, 0, 0.25)

  statusText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statusText:SetPoint("BOTTOMLEFT", 10, 7)
  statusText:SetPoint("BOTTOMRIGHT", -10, 7)
  statusText:SetJustifyH("LEFT")

  progressBar = CreateFrame("StatusBar", nil, parent)
  progressBar:SetPoint("BOTTOMLEFT", 10, 6)
  progressBar:SetPoint("BOTTOMRIGHT", -10, 6)
  progressBar:SetHeight(12)
  progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  progressBar:SetStatusBarColor(0.85, 0.65, 0.15)
  progressBar:SetMinMaxValues(0, 1)
  local pbg = progressBar:CreateTexture(nil, "BACKGROUND")
  pbg:SetAllPoints()
  pbg:SetColorTexture(0, 0, 0, 0.55)
  progressBar.text = progressBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  progressBar.text:SetPoint("CENTER", 0, 1)
  progressBar:Hide()
end

---------------------------------------------------------------------------
-- Detail panel: small layout engine over pooled widgets
---------------------------------------------------------------------------
local P = { pools = {}, used = {} }
local scroll, child, CHILD_W
local y

local function take(kind, factory)
  local pool = P.pools[kind]
  if not pool then pool = {}; P.pools[kind] = pool end
  local n = (P.used[kind] or 0) + 1
  P.used[kind] = n
  local w = pool[n]
  if not w then w = factory(); pool[n] = w end
  w:ClearAllPoints()
  w:Show()
  return w
end

function P.Reset()
  for kind, pool in pairs(P.pools) do
    for _, w in ipairs(pool) do w:Hide() end
    P.used[kind] = 0
  end
  if P.note then P.note:Hide() end
  y = -12
end

local function newFS() return child:CreateFontString(nil, "OVERLAY") end
local function newTex() return child:CreateTexture(nil, "ARTWORK") end
local function newBand() return child:CreateTexture(nil, "BACKGROUND", nil, 2) end

local function styleFS(fs, font, color, shadow)
  setFont(fs, font or "QuestFont", "GameFontBlack", "GameFontHighlight")
  local c = color or T.ink
  fs:SetTextColor(c[1], c[2], c[3])
  if shadow then fs:SetShadowOffset(1, -1)
  elseif T.light then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
  else fs:SetShadowOffset(0, 0) end
end

-- opts: font, x, color, gap, width, justify, shadow
function P.Text(text, opts)
  opts = opts or {}
  local x = opts.x or 16
  local fs = take("fs", newFS)
  styleFS(fs, opts.font, opts.color, opts.shadow)
  fs:SetJustifyH(opts.justify or "LEFT")
  fs:SetWordWrap(true)
  fs:SetWidth(opts.width or (CHILD_W - x - 16))
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  y = y - fs:GetStringHeight() - (opts.gap or 4)
  return fs
end

function P.Line(x, alpha)
  local line = take("tex", newTex)
  line:SetColorTexture(T.line[1], T.line[2], T.line[3], alpha or T.line[4])
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", x or 14, y)
  line:SetPoint("TOPRIGHT", child, "TOPRIGHT", -14, y)
  return line
end

-- Section header: icon + title + rule
function P.Header(spec, text)
  y = y - 12
  local ic = take("tex", newTex)
  ic:SetSize(20, 20)
  setIcon(ic, spec)
  ic:SetPoint("TOPLEFT", 14, y + 2)
  P.Text(text, { font = "QuestFontNormalLarge", x = 40, color = T.head, gap = 4 })
  P.Line(14)
  y = y - 8
end

local function chipFactory()
  local f = CreateFrame("Frame", nil, child)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0, 0, 0, 0.62)
  f.edge = f:CreateTexture(nil, "BORDER")
  f.edge:SetPoint("BOTTOMLEFT")
  f.edge:SetPoint("BOTTOMRIGHT")
  f.edge:SetHeight(2)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(12, 12)
  f.icon:SetPoint("LEFT", 5, 1)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

-- chips: list of { text, r, g, b, tip, iconSpec }
function P.Chips(chips, x)
  x = x or 16
  local cx = x
  for _, s in ipairs(chips) do
    local c = take("chips", chipFactory)
    c.text:SetText(s[1])
    c.text:SetTextColor(s[2], s[3], s[4])
    c.text:ClearAllPoints()
    local iw = 0
    if s[6] then setIcon(c.icon, s[6]); c.icon:Show(); iw = 15 else c.icon:Hide() end
    c.text:SetPoint("LEFT", 7 + iw, 1)
    local w = floor(c.text:GetStringWidth() + 14 + iw)
    if cx + w > CHILD_W - 14 and cx > x then cx = x; y = y - 22 end
    c:SetSize(w, 19)
    c:SetPoint("TOPLEFT", cx, y)
    c.edge:SetColorTexture(s[2], s[3], s[4], 0.85)
    if s[5] then
      c:EnableMouse(true)
      c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(s[5], 1, 1, 1, 1, true); GameTooltip:Show()
      end)
    else
      c:EnableMouse(false)
      c:SetScript("OnEnter", nil)
    end
    cx = cx + w + 6
  end
  y = y - 25
end

function P.Buttons(specs)
  local x = 14
  local rowH = 26
  for _, s in ipairs(specs) do
    local b = take("buttons", function()
      local btn = create("Button", nil, child, "UIPanelButtonTemplate")
      btn:SetHeight(22)
      btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
      return btn
    end)
    b:SetText(s[1])
    local w = max(70, (b:GetFontString() and b:GetFontString():GetStringWidth() or 60) + 26)
    if x + w > CHILD_W - 14 then x = 14; y = y - rowH end
    b:SetWidth(w)
    b:SetPoint("TOPLEFT", x, y)
    b:SetScript("OnClick", s[2])
    b:SetScript("OnEnter", function(self)
      if not s[3] then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(s[3], 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    x = x + w + 4
  end
  y = y - rowH - 2
end

-- Location row: icon, name, zone + coords, map pin. Click sets a waypoint.
local function placeFactory()
  local b = CreateFrame("Button", nil, child)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("LEFT", 4, 0)
  b.name = b:CreateFontString(nil, "OVERLAY")
  b.name:SetJustifyH("LEFT")
  b.name:SetWordWrap(false)
  b.where = b:CreateFontString(nil, "OVERLAY")
  b.where:SetJustifyH("LEFT")
  b.where:SetWordWrap(false)
  b.pin = b:CreateTexture(nil, "ARTWORK")
  b.pin:SetSize(16, 20)
  b.pin:SetPoint("RIGHT", -8, 0)
  setIcon(b.pin, ICON.pin)
  b.pinHi = b:CreateTexture(nil, "HIGHLIGHT")
  b.pinHi:SetAllPoints(b.pin)
  setIcon(b.pinHi, ICON.pinHi)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- o: { icon = spec | iconFile = fileId, name, area, x, y, count, indent, compact, label (waypoint title) }
function P.Place(o)
  local indent = o.indent or 14
  local compact = o.compact
  local h = compact and 30 or 36
  local b = take("places", placeFactory)
  b:SetPoint("TOPLEFT", indent, y)
  b:SetSize(CHILD_W - indent - 14, h)
  b.hl:SetColorTexture(T.hover[1], T.hover[2], T.hover[3], T.hover[4])

  local isz = compact and 16 or 20
  b.icon:SetSize(isz, isz)
  if o.iconFile then
    b.icon:SetTexture(o.iconFile)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  else
    setIcon(b.icon, o.icon)
  end

  local tx = 4 + isz + 8
  b.name:ClearAllPoints()
  b.name:SetPoint("TOPLEFT", b, "TOPLEFT", tx, compact and -2 or -3)
  b.name:SetPoint("RIGHT", b, "RIGHT", -30, 0)
  styleFS(b.name, compact and "GameFontBlack" or "QuestFont", T.ink)
  b.name:SetText(o.name or "")

  local hasCoords = o.x and o.x >= 0
  local where = o.whereText or fmtCoords(o.area, o.x, o.y)
  if o.count and o.count > 1 then where = where .. colorText(("   %d spawns"):format(o.count), T.muted) end
  b.where:ClearAllPoints()
  b.where:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", tx, compact and 2 or 3)
  b.where:SetPoint("RIGHT", b, "RIGHT", -30, 0)
  styleFS(b.where, "GameFontBlackSmall", (hasCoords or o.whereText) and (o.whereText and T.sub or T.link) or T.muted)
  b.where:SetText(where)

  b.pin:SetShown(hasCoords and true or false)
  b.pinHi:SetShown(hasCoords and true or false)
  b:EnableMouse(true)
  b:SetScript("OnClick", function()
    if hasCoords then QP.SetWaypoint(o.area, o.x, o.y, o.label or o.name) end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(o.name or "", 1, 0.82, 0)
    if o.whereText then GameTooltip:AddLine(o.whereText, 1, 1, 1)
    else
      GameTooltip:AddLine(fmtCoords(o.area, o.x, o.y), 1, 1, 1)
      if o.count and o.count > 1 then GameTooltip:AddLine(("%d spawn points"):format(o.count), 0.8, 0.8, 0.8) end
      GameTooltip:AddLine(hasCoords and "Click to set a waypoint" or "No coordinates in the database", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
  end)
  y = y - h - 2
  return b
end

local function barFactory()
  local s = CreateFrame("StatusBar", nil, child)
  s:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  s.edge = s:CreateTexture(nil, "BACKGROUND")
  s.edge:SetPoint("TOPLEFT", -1, 1)
  s.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  s.edge:SetColorTexture(0, 0, 0, 0.75)
  s.bg = s:CreateTexture(nil, "BACKGROUND", nil, 1)
  s.bg:SetAllPoints()
  s.bg:SetColorTexture(0.15, 0.12, 0.08, 0.85)
  s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  s.text:SetPoint("CENTER", 0, 0)
  return s
end

function P.Bar(x, width, value, maxValue, r, g, b, label)
  local s = take("bars", barFactory)
  s:SetPoint("TOPLEFT", x, y)
  s:SetSize(width, 12)
  s:SetMinMaxValues(0, max(1, maxValue))
  s:SetValue(min(value, maxValue))
  s:SetStatusBarColor(r, g, b)
  s.text:SetText(label or "")
  y = y - 18
  return s
end

-- Objective line with a tracker-style bullet, and an optional progress bar.
function P.Objective(text, done, cur, req)
  local ic = take("tex", newTex)
  ic:SetSize(14, 14)
  setIcon(ic, done and ICON.check or ICON.nub)
  ic:SetPoint("TOPLEFT", 18, y - 1)
  P.Text(text, { x = 38, color = done and T.good or T.ink, gap = 3 })
  if req and req > 1 and not done then
    P.Bar(38, min(240, CHILD_W - 70), cur or 0, req, 0.85, 0.62, 0.1, ("%d / %d"):format(cur or 0, req))
  end
  y = y - 2
end

-- Reward item tile (Blizzard LargeItemButtonTemplate, rebuilt if the template is missing)
local function itemFactory()
  local b = create("Button", nil, child, "LargeItemButtonTemplate")
  if type(b.Icon) ~= "table" then
    b:SetSize(147, 41)
    b.Icon = b:CreateTexture(nil, "BACKGROUND")
    b.Icon:SetSize(39, 39)
    b.Icon:SetPoint("TOPLEFT")
    b.NameFrame = b:CreateTexture(nil, "BACKGROUND")
    b.NameFrame:SetTexture("Interface\\QuestFrame\\UI-QuestItemNameFrame")
    b.NameFrame:SetSize(128, 64)
    b.NameFrame:SetPoint("LEFT", b.Icon, "RIGHT", -10, 0)
    b.Name = b:CreateFontString(nil, "BORDER", "GameFontHighlight")
    b.Name:SetSize(90, 36)
    b.Name:SetPoint("LEFT", b.NameFrame, "LEFT", 15, 0)
    b.Name:SetJustifyH("LEFT")
  end
  if type(b.IconBorder) ~= "table" then
    b.IconBorder = b:CreateTexture(nil, "OVERLAY")
    b.IconBorder:SetAllPoints(b.Icon)
    if hasAtlas("auctionhouse-itemicon-border-white") then b.IconBorder:SetAtlas("auctionhouse-itemicon-border-white")
    else b.IconBorder:SetTexture("Interface\\Common\\WhiteIconFrame") end
  end
  b.arrow = b:CreateTexture(nil, "OVERLAY", nil, 3)
  b.arrow:SetSize(16, 16)
  b.arrow:SetPoint("TOPLEFT", b.Icon, "TOPLEFT", -3, 3)
  setIcon(b.arrow, ICON.upgrade)
  b.hlTex = b:CreateTexture(nil, "HIGHLIGHT")
  b.hlTex:SetAllPoints(b.Icon)
  b.hlTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  b.hlTex:SetBlendMode("ADD")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.link then GameTooltip:SetHyperlink(self.link) elseif self.itemId then GameTooltip:SetItemByID(self.itemId) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    local link = self.link
    if link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then HandleModifiedItemClick(link) end
  end)
  return b
end

local function fillItem(b, itemId, link)
  b.itemId, b.link = itemId, link
  b.Icon:SetTexture(itemIcon(itemId))
  b.IconBorder:SetVertexColor(1, 1, 1)
  b.IconBorder:Show()
  b.arrow:SetShown(b.forceArrow and true or false)
  b.Name:SetTextColor(1, 1, 1)
  b.Name:SetText(D.I("name", itemId) or "")
  if not Item or not Item.CreateFromItemID then return end
  local item = Item:CreateFromItemID(itemId)
  item:ContinueOnItemLoad(function()
    if b.itemId ~= itemId then return end
    local q = item:GetItemQuality()
    local l = b.link or item:GetItemLink()
    b.link = l
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then b.IconBorder:SetVertexColor(c.r, c.g, c.b); b.Name:SetTextColor(c.r, c.g, c.b) end
    b.Name:SetText(item:GetItemName() or b.Name:GetText())
    if l and PawnShouldItemLinkHaveUpgradeArrow then
      local up = pcallret(PawnShouldItemLinkHaveUpgradeArrow, l, true)
      if up ~= nil then b.arrow:SetShown(up or b.forceArrow or false) end
    end
  end)
end

-- items: list of itemIds or item links, two tiles per row
function P.Items(items, upgradeItemId)
  local col, cols = 0, 2
  local colW = (CHILD_W - 32) / cols
  for _, it in ipairs(items) do
    local itemId, link = it, nil
    if type(it) == "string" then link = it; itemId = tonumber(it:match("item:(%d+)")) end
    if itemId then
      local b = take("items", itemFactory)
      b:SetPoint("TOPLEFT", 18 + col * colW, y)
      b.forceArrow = (upgradeItemId and itemId == upgradeItemId) or nil
      fillItem(b, itemId, link)
      col = col + 1
      if col >= cols then col = 0; y = y - 46 end
    end
  end
  if col > 0 then y = y - 46 end
end

-- Icon + label + value row (XP, money, reputation)
function P.Stat(spec, label, value, valueColor, extra)
  local ic = take("tex", newTex)
  ic:SetSize(22, 22)
  if setIcon(ic, spec) then ic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  ic:SetPoint("TOPLEFT", 18, y)
  local top = y
  local fs = P.Text(label, { font = "GameFontBlackSmall", x = 48, color = T.muted, gap = 1 })
  P.Text(value .. (extra and ("  " .. colorText(extra, T.muted)) or ""), { font = "GameFontBlackMedium", x = 48, color = valueColor or T.ink, gap = 2 })
  y = min(y, top - 26) - 4
  return fs
end

function P.Finish()
  child:SetHeight(max(-y + 14, 10))
end

local function buildDetail()
  local parent = frame.right
  scroll = create("ScrollFrame", "QuestPlannerDetailScroll", parent, "UIPanelScrollFrameTemplate", "ScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  CHILD_W = W - LIST_W - 20 - 6 - 30
  child = CreateFrame("Frame", nil, scroll)
  child:SetSize(CHILD_W, 10)
  scroll:SetScrollChild(child)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local maxS = max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(min(maxS, max(0, cur - delta * 40)))
  end)

  -- Plan note box, with a dark backing so it reads on parchment
  P.note = create("EditBox", nil, child, "InputBoxTemplate")
  P.note:SetHeight(20)
  P.note:SetAutoFocus(false)
  P.note:SetMaxLetters(200)
  P.note:SetTextInsets(4, 4, 0, 0)
  local nbg = P.note:CreateTexture(nil, "BACKGROUND")
  nbg:SetPoint("TOPLEFT", -4, 1)
  nbg:SetPoint("BOTTOMRIGHT", 0, -1)
  nbg:SetColorTexture(0, 0, 0, 0.55)
  P.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  P.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  P.note:SetScript("OnEditFocusLost", function(self)
    if self.questId then QP.SetNote(self.questId, self:GetText()); QP.FirePlanChanged() end
  end)
  P.note:Hide()

  detail = parent
end

---------------------------------------------------------------------------
-- Render a quest
---------------------------------------------------------------------------
local function placeFor(s, iconSpec, indent, compact)
  local label = s.label or s.name
  local name = label
  if s.sub then name = name .. colorText("  <" .. s.sub .. ">", T.muted) end
  local spec, file = iconSpec, nil
  if s.kind == "vendor" then spec = ICON.coin
  elseif s.kind == "npc" and compact then spec = ICON.combat
  elseif s.kind == "object" and compact then spec = ICON.nub end
  return P.Place({ icon = spec, iconFile = file, name = name, label = label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
    area = s.area, x = s.x, y = s.y, count = s.count, indent = indent, compact = compact })
end

local function renderWelcome(text)
  P.Reset()
  y = -36
  local ic = take("tex", newTex)
  ic:SetSize(52, 52)
  ic:SetTexture(ICON.book[2])
  ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  ic:SetPoint("TOP", child, "TOP", 0, y)
  y = y - 62
  P.Text("QuestPlanner", { font = "QuestTitleFont", x = 16, justify = "CENTER", color = T.light and T.head or T.ink, shadow = true, gap = 4 })
  P.Text(text, { font = "QuestFont", x = 16, justify = "CENTER", color = T.sub, gap = 18 })
  P.Line(60, 0.25)
  y = y - 14
  local tips = {
    { ICON.giver, "Click a quest to see who gives it, what to do, and where." },
    { ICON.star, "Right-click a quest to add it to your plan." },
    { ICON.pin, "Click any location to set a waypoint." },
    { ICON.chain, "\"Plan chain\" adds every quest a chain needs, in order." },
    { ICON.note, "Add notes to planned quests. Shift-click links in chat." },
  }
  for _, t in ipairs(tips) do
    local tic = take("tex", newTex)
    tic:SetSize(18, 18)
    setIcon(tic, t[1])
    tic:SetPoint("TOPLEFT", 54, y + 1)
    P.Text(t[2], { x = 80, width = CHILD_W - 130, gap = 10 })
  end
  y = y - 6
  P.Text("/qp near  -  quests around you        /qp plan  -  your plan", { font = "GameFontBlackSmall", x = 16, justify = "CENTER", color = T.muted })
  P.Finish()
end

local renderedId
local function render(id)
  local keep = (renderedId == id) and scroll:GetVerticalScroll() or 0
  renderedId = id
  P.Reset()
  local name = D.Q("name", id)
  if not name then renderWelcome("Quest " .. id .. " is not in Questie's database."); return end
  D.RefreshPlayer()

  local status, reason = D.Status(id)
  local spec, style = statusIcon(status)
  local qLevel, rLevel = D.Q("questLevel", id) or 0, D.Q("requiredLevel", id) or 0
  local area = D.Q("zoneOrSort", id)
  local planned = QP.IsPlanned(id)

  -- Header card
  local band = take("bands", newBand)
  band:SetColorTexture(T.band[1], T.band[2], T.band[3], T.band[4])
  band:SetPoint("TOPLEFT", 4, -4)
  band:SetPoint("RIGHT", child, "RIGHT", -4, 0)
  if #history > 0 then
    P.Buttons({ { iconMarkup(ICON.back, 12) .. " Back", function()
      local prev = table.remove(history)
      if prev then selectedId = prev; render(prev); updateRows() end
    end, "Previous quest" } })
  end
  local top = y
  local big = take("tex", newTex)
  big:SetSize(40, 40)
  local headSpec = status == "available" and ICON.giver or (status == "active" and ICON.turnin) or spec
  setIcon(big, headSpec)
  big:SetPoint("TOPLEFT", 14, y - 2)
  P.Text(name, { font = "QuestTitleFont", x = 64, color = T.light and T.head or T.ink, shadow = true, gap = 6 })
  local lr, lg, lb = levelColor(qLevel)
  local sc = style.color
  local chips = {
    { "Level " .. qLevel, lr, lg, lb, "Quest level. Colour shows difficulty for you." },
    { "Requires " .. rLevel, 0.9, 0.9, 0.9, "Minimum level to accept." },
    { D.ZoneName(area), 0.75, 0.85, 1, "Zone" },
    { style.label, sc[1], sc[2], sc[3], reason, spec },
  }
  if planned then chips[#chips + 1] = { "In plan", 1, 0.82, 0, "This quest is in your plan.", ICON.star } end
  local up = U.Get(id)
  if up then
    local tip = ("%s is an upgrade for you: %s"):format(D.I("name", up.itemId) or "A reward", U.Label(up))
    if up.scale then tip = tip .. " (Pawn: " .. up.scale .. ")" end
    chips[#chips + 1] = { "Upgrade " .. U.Label(up), 0.35, 1, 0.35, tip, ICON.upgrade }
  end
  P.Chips(chips, 64)
  y = min(y, top - 48)
  if reason then P.Text(reason, { font = "GameFontBlack", x = 64, color = T.warn, gap = 4 }) end
  y = y - 4
  band:SetHeight(-y - 4)

  -- Actions
  y = y - 6
  local starters = D.Starters(id)
  local first = starters[1]
  local btns = {
    { (planned and "Remove from plan" or (iconMarkup(ICON.star, 13) .. " Add to plan")), function() QP.TogglePlan(id) end, "Save this quest to your plan." },
    { iconMarkup(ICON.chain, 13) .. " Plan chain", function() QP.AddChainToPlan(id) end, "Add this quest and every unfinished quest before it." },
    { "Link", function() QP.InsertLink(id) end, "Put a quest link in chat." },
  }
  if first and first.x then
    btns[#btns + 1] = { iconMarkup(ICON.pin, 14) .. " Go to start", function() QP.SetWaypoint(first.area, first.x, first.y, first.name) end,
      "Waypoint to the quest giver." }
  end
  P.Buttons(btns)

  if planned then
    local entry = QP.char.plan[QP.PlanIndex(id)]
    local nic = take("tex", newTex)
    nic:SetSize(16, 16)
    setIcon(nic, ICON.note)
    nic:SetPoint("TOPLEFT", 16, y - 2)
    P.note:ClearAllPoints()
    P.note:SetPoint("TOPLEFT", 42, y)
    P.note:SetWidth(CHILD_W - 70)
    P.note.questId = id
    P.note:SetText(entry and entry.note or "")
    P.note:Show()
    y = y - 28
  end

  -- Quest giver
  P.Header(ICON.giver, "Quest giver")
  if #starters == 0 then P.Text("Unknown, or the quest starts automatically.", { x = 18, color = T.muted }) end
  for _, s in ipairs(starters) do
    if s.kind == "item" then
      P.Place({ iconFile = itemIcon(s.id), name = "Starts from item: " .. s.name, indent = 14,
        whereText = (#(s.sources or {}) > 0) and "Drops from:" or "Source unknown" })
      for _, src in ipairs(s.sources or {}) do placeFor(src, ICON.combat, 40, true) end
    else
      local _, _, _, count = D.PickSpawn(s.kind == "npc" and D.N("spawns", s.id) or D.O("spawns", s.id), s.area)
      s.count = count
      placeFor(s, ICON.giver)
    end
  end

  -- Objectives
  P.Header(ICON.objectives, "Objectives")
  local live = D.IsOnQuest(id) and C_QuestLog and pcallret(C_QuestLog.GetQuestObjectives, id)
  local descr = D.Q("objectivesText", id) or {}
  for _, line in ipairs(descr) do P.Text(line, { x = 18, gap = 6 }) end
  if type(live) == "table" and #live > 0 then
    if #descr > 0 then y = y - 2 end
    for _, o in ipairs(live) do P.Objective(o.text or "", o.finished, o.numFulfilled, o.numRequired) end
  end
  local objs = D.Objectives(id)
  if #objs > 0 then
    y = y - 4
    for _, o in ipairs(objs) do
      if o.kind == "item" then
        P.Place({ iconFile = itemIcon(o.itemId), name = o.text, indent = 14,
          whereText = (#(o.sources or {}) > 0) and "Found at:" or "No known source" })
        for _, src in ipairs(o.sources or {}) do placeFor(src, ICON.combat, 40, true) end
        if (o.totalSources or 0) > #(o.sources or {}) then
          P.Text(("+ %d more places drop this"):format(o.totalSources - #o.sources), { font = "GameFontBlackSmall", x = 46, color = T.muted })
        end
      else
        local ic = (o.kind == "kill" and ICON.combat) or (o.kind == "explore" and ICON.pin) or ICON.nub
        P.Place({ icon = ic, name = o.text, area = o.area, x = o.x, y = o.y, indent = 14 })
      end
    end
  elseif #descr == 0 and not live then
    P.Text("No objectives listed.", { x = 18, color = T.muted })
  end

  -- Turn in
  P.Header(ICON.turnin, "Turn in")
  local finishers = D.Finishers(id)
  if #finishers == 0 then P.Text("Unknown.", { x = 18, color = T.muted }) end
  for _, f in ipairs(finishers) do placeFor(f, ICON.turnin) end

  -- Rewards
  P.Header(ICON.rewards, "Rewards")
  local baseXP, atLevel = D.XPAtLevel(id)
  local logRewards = D.LogRewards(id)
  local xp = logRewards and logRewards.xp or baseXP
  local any = false
  if xp and xp > 0 then
    any = true
    local yours = (logRewards and xp) or atLevel or xp
    local extra = (atLevel and not logRewards and atLevel ~= xp) and ("about " .. fmtNumber(atLevel) .. " at your level") or nil
    P.Stat(ICON.xp, "Experience", fmtNumber(xp) .. " XP", T.ink, extra)
    local xpMax = playerXPMax()
    if xpMax and yours > 0 then
      local pct = yours / xpMax * 100
      P.Bar(48, min(260, CHILD_W - 80), yours, xpMax, 0.58, 0.0, 0.55, ("%.0f%% of level %d"):format(pct, D.player.level or 0))
      y = y - 2
    end
  end
  local money = logRewards and fmtMoney(logRewards.money)
  if money then any = true; P.Stat(ICON.coin, "Money", money) end
  for _, rep in ipairs(D.Q("reputationReward", id) or {}) do
    if rep[1] then
      any = true
      P.Stat(ICON.rewards, "Reputation", ("%s %+d"):format(D.FactionName(rep[1]), rep[2] or 0), T.link)
    end
  end
  if up then
    any = true
    P.Stat(ICON.upgrade, up.scale and ("Upgrade for you  -  Pawn: " .. up.scale) or "Upgrade for you",
      (D.I("name", up.itemId) or "Reward") .. "  " .. U.Label(up), T.good, nil)
    if up.existing then P.Text("Replaces " .. up.existing, { font = "GameFontBlackSmall", x = 48, color = T.muted, gap = 6 }) end
  end
  local upItem = up and up.itemId
  if logRewards and (#logRewards.choices > 0 or #logRewards.fixed > 0) then
    any = true
    if #logRewards.choices > 0 then
      P.Text("Choose one of these rewards:", { font = "GameFontBlack", x = 18, color = T.sub, gap = 6 })
      P.Items(logRewards.choices, upItem)
    end
    if #logRewards.fixed > 0 then
      P.Text("You will also receive:", { font = "GameFontBlack", x = 18, color = T.sub, gap = 6 })
      P.Items(logRewards.fixed, upItem)
    end
  else
    local items = D.RewardItems(id)
    if #items > 0 then
      any = true
      P.Text(#items > 1 and "Item rewards (usually choose one):" or "Item reward:", { font = "GameFontBlack", x = 18, color = T.sub, gap = 6 })
      P.Items(items, upItem)
    elseif not D.IndexReady() then
      P.Text("Item rewards appear once indexing finishes.", { font = "GameFontBlackSmall", x = 18, color = T.muted })
    end
  end
  if not any and D.IndexReady() then P.Text("No rewards listed.", { x = 18, color = T.muted }) end

  -- Requirements
  local reqs = D.Requirements(id)
  if #reqs > 0 then
    P.Header(ICON.lock, "Requirements")
    for _, rq in ipairs(reqs) do P.Objective(rq, false) end
  end

  -- Chain timeline
  local chain = D.Chain(id)
  if #chain > 1 then
    P.Header(ICON.chain, ("Quest chain  (%d quests)"):format(#chain))
    local rowH = 26
    local prevNode
    for _, e in ipairs(chain) do
      local qid = e[1]
      local cst = (D.Status(qid))
      local cspec, cstyle = statusIcon(cst)
      local ql = D.Q("questLevel", qid) or 0
      local qname = D.Q("name", qid) or ("Quest " .. qid)
      local current = qid == id
      if current then
        local cb = take("bands", newBand)
        cb:SetColorTexture(1, 0.82, 0, T.light and 0.10 or 0.18)
        cb:SetPoint("TOPLEFT", 12, y + 3)
        cb:SetSize(CHILD_W - 26, rowH)
      end
      local node = take("tex", newTex)
      node:SetSize(16, 16)
      setIcon(node, cspec)
      node:SetPoint("TOPLEFT", 22, y - 2)
      if prevNode then
        local link = take("tex", newTex)
        link:SetColorTexture(T.line[1], T.line[2], T.line[3], 0.6)
        link:SetWidth(2)
        link:SetPoint("TOP", prevNode, "BOTTOM", 0, -1)
        link:SetPoint("BOTTOM", node, "TOP", 0, 1)
      end
      prevNode = node
      local cr, cg, cb2 = levelColor(ql)
      local saveY = y
      P.Chips({ { tostring(ql), cr, cg, cb2 } }, 46)
      y = saveY
      local label = qname .. ((QP.IsPlanned(qid) and not current) and ("  " .. iconMarkup(ICON.star, 12)) or "")
      if current then
        P.Text(label .. colorText("   this quest", T.muted), { font = "GameFontBlackMedium", x = 84, color = T.head, gap = 0 })
        y = min(y - 4, saveY - rowH)
      else
        local b = take("chainLinks", function()
          local btn = CreateFrame("Button", nil, child)
          btn.text = btn:CreateFontString(nil, "OVERLAY")
          btn.text:SetPoint("LEFT")
          btn.text:SetJustifyH("LEFT")
          btn.text:SetWordWrap(false)
          btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
          btn.hl:SetAllPoints()
          btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
          return btn
        end)
        styleFS(b.text, "QuestFont", cst == "done" and T.muted or T.ink)
        b.text:SetWidth(CHILD_W - 84 - 18)
        b.text:SetText(label)
        b.hl:SetColorTexture(T.hover[1], T.hover[2], T.hover[3], T.hover[4])
        b:SetPoint("TOPLEFT", 80, y + 2)
        b:SetSize(CHILD_W - 80 - 14, rowH - 4)
        b:SetScript("OnClick", function() QP.ShowQuest(qid) end)
        b:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:AddLine(qname, 1, 0.82, 0)
          GameTooltip:AddLine(cstyle.label .. "  -  " .. D.ZoneName(D.Q("zoneOrSort", qid)), 1, 1, 1)
          GameTooltip:AddLine(e[2] < 0 and "Comes before this quest" or "Comes after this quest", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("Click to view", 0.6, 0.6, 0.6)
          GameTooltip:Show()
        end)
        y = saveY - rowH
      end
    end
  end

  y = y - 14
  P.Line(14, 0.2)
  y = y - 6
  P.Text(("Quest ID %d"):format(id), { font = "GameFontBlackSmall", x = 16, color = T.muted })
  P.Finish()
  scroll:SetVerticalScroll(min(keep, max(0, child:GetHeight() - scroll:GetHeight())))
end

---------------------------------------------------------------------------
-- Tabs and refresh
---------------------------------------------------------------------------
local SEP = "  |cff808080-|r  "

local function entryFromIndex(e, sub)
  return { id = e[1], name = e[3], qLevel = e[4], rLevel = e[5], zone = e[6], status = (D.Status(e[1])), sub = sub }
end

local function currentFilters()
  D.RefreshPlayer()
  local opts = {
    text = searchBox:GetText(),
    minLevel = tonumber(minBox:GetText()),
    maxLevel = tonumber(maxBox:GetText()),
    mineOnly = filters.mineOnly,
    hideDone = filters.hideDone,
    gearOnly = filters.gearOnly,
  }
  if filters.zoneOnly then
    local _, area = D.PlayerPosition()
    opts.areaId = area or -999
  end
  if opts.text and opts.text ~= "" then opts.minLevel, opts.maxLevel = nil, nil end
  return opts
end

local function refreshBrowse()
  local results = D.Search(currentFilters())
  wipe(data)
  for _, e in ipairs(results) do
    data[#data + 1] = entryFromIndex(e, "Requires " .. e[5] .. SEP .. D.ZoneName(e[6]))
  end
  statusText:SetText(#results >= 400 and "400+ quests  -  narrow your search" or (#results .. " quests"))
end

local function refreshNear()
  local results, area = D.NearMe()
  wipe(data)
  for _, r in ipairs(results) do
    local dist = r.dist and (r.dist >= 1000 and ("%.1fk yards"):format(r.dist / 1000) or ("%d yards"):format(r.dist))
    data[#data + 1] = entryFromIndex(r.entry, "Requires " .. r.entry[5] .. SEP .. (dist or D.ZoneName(r.entry[6])))
  end
  statusText:SetText(area and (#results .. " quests you can pick up in " .. D.ZoneName(area)) or "Your zone is not mapped.")
end

local function refreshUpgrades()
  wipe(data)
  local s = U.Settings()
  if upBar.ahead and not upBar.ahead:HasFocus() then upBar.ahead:SetText(s.ahead) end
  upBar.avail:SetChecked(s.availableOnly)
  if U.state ~= "ready" then
    statusText:SetText("Checking quest rewards...")
    upBar.summary:SetText("")
    return
  end
  for _, r in ipairs(U.List()) do
    local e = entryFromIndex(r.entry, colorText(U.Label(r), 0.3, 1, 0.3) .. "  " .. (D.I("name", r.itemId) or "") ..
      SEP .. "Requires " .. r.entry[5] .. SEP .. D.ZoneName(r.entry[6]))
    e.gearItem = r.itemId
    data[#data + 1] = e
  end
  upBar.summary:SetText(U.method == "pawn" and "Scored with Pawn" or "Scored by item level  -  install Pawn for stat-based scoring")
  statusText:SetText(#data == 0 and "No upgrade rewards found in this level range." or
    (#data .. " quests reward an upgrade  -  right-click to plan"))
end

local function refreshPlan()
  wipe(data)
  local totalXP, todo = 0, 0
  for i, p in ipairs(QP.char.plan) do
    local qid = p.id
    local e = { id = qid, name = D.Q("name", qid) or ("Quest " .. qid), qLevel = D.Q("questLevel", qid) or 0,
      rLevel = D.Q("requiredLevel", qid) or 0, zone = D.Q("zoneOrSort", qid), note = p.note }
    e.status = p.done and "done" or (D.Status(qid))
    e.name = ("%d. %s"):format(i, e.name)
    e.sub = D.ZoneName(e.zone)
    if p.note and p.note ~= "" then e.sub = e.sub .. SEP .. iconMarkup(ICON.note, 11) .. " " .. p.note end
    data[#data + 1] = e
    if not p.done then
      todo = todo + 1
      local _, at = D.XPAtLevel(qid)
      totalXP = totalXP + (at or 0)
    end
  end
  local levels = ""
  local xpMax = playerXPMax()
  if xpMax and totalXP > 0 then levels = ("  (about %.1f levels)"):format(totalXP / xpMax) end
  planBar.summary:SetText(("|cffffd100%d|r to do  -  |cffffd100%s|r XP%s"):format(todo, fmtNumber(totalXP), levels))
  statusText:SetText(#data == 0 and "Right-click any quest to add it to your plan." or
    "Right-click to remove. Select a quest, then use Up/Down to reorder.")
end

local function showIndexState()
  if D.error then
    progressBar:Hide()
    statusText:Show()
    statusText:SetText(colorText(D.error, 1, 0.4, 0.4))
    return false
  end
  if D.state ~= "ready" then
    progressBar:Show()
    statusText:Hide()
    progressBar:SetValue(D.progress or 0)
    progressBar.text:SetText(("Indexing quests...  %d%%"):format((D.progress or 0) * 100))
    return false
  end
  if activeTab == TAB_UPGRADES and U.state == "scanning" then
    progressBar:Show()
    statusText:Hide()
    progressBar:SetValue(U.progress or 0)
    progressBar.text:SetText(("Checking quest rewards...  %d%%"):format((U.progress or 0) * 100))
    return true
  end
  progressBar:Hide()
  statusText:Show()
  return true
end

refreshList = function()
  if not frame or not frame:IsShown() then return end
  if D.IndexReady() and U.dirty and U.state ~= "scanning" then U.Scan() end
  local ready = showIndexState()
  frame.toolbar:SetShown(activeTab == TAB_BROWSE or activeTab == TAB_NEAR)
  planBar:SetShown(activeTab == TAB_PLAN)
  upBar:SetShown(activeTab == TAB_UPGRADES)
  if activeTab == TAB_PLAN then refreshPlan()
  elseif ready then
    if activeTab == TAB_BROWSE then refreshBrowse()
    elseif activeTab == TAB_NEAR then refreshNear()
    else refreshUpgrades() end
  else
    wipe(data)
  end
  if tabs and tabs[TAB_PLAN] then
    tabs[TAB_PLAN]:SetText(("My Plan (%d)"):format(#QP.char.plan))
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tabs[TAB_PLAN], 0) end
  end
  updateRows()
  if reorderUpdate then reorderUpdate() end
end

function QP.Refresh()
  if not frame or not frame:IsShown() then return end
  refreshList()
  if selectedId and detail then render(selectedId) end
end

local function selectTab(i)
  activeTab = i
  offset = 0
  if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, frame, i) end
  for j, t in ipairs(tabs) do
    if not PanelTemplates_SetTab then
      if j == i then t:LockHighlight() else t:UnlockHighlight() end
    end
  end
  refreshList()
end

local function buildTabs()
  tabs = {}
  local labels = { "Browse", "Near Me", "Upgrades", "My Plan" }
  for i, label in ipairs(labels) do
    local t = create("Button", "QuestPlannerFrameTab" .. i, frame, "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate", "UIPanelButtonTemplate")
    t:SetID(i)
    t:SetText(label)
    if i == 1 then t:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
    else t:SetPoint("LEFT", tabs[i - 1], "RIGHT", -14, 0) end
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, t, 0) end
    if not t:GetWidth() or t:GetWidth() < 40 then t:SetSize(100, 24) end
    t:SetScript("OnClick", function() selectTab(i) end)
    tabs[i] = t
  end
  frame.Tabs = tabs
  if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, frame, #tabs) end
end

-- Up/Down reorder for the plan tab
local function buildPlanReorder()
  local up = create("Button", nil, frame.right, "UIPanelButtonTemplate")
  up:SetSize(64, 20)
  up:SetText("Up")
  up:SetPoint("BOTTOMRIGHT", frame.right, "TOPRIGHT", -72, 4)
  local down = create("Button", nil, frame.right, "UIPanelButtonTemplate")
  down:SetSize(64, 20)
  down:SetText("Down")
  down:SetPoint("LEFT", up, "RIGHT", 4, 0)
  up:SetScript("OnClick", function() if selectedId then QP.MovePlan(selectedId, -1) end end)
  down:SetScript("OnClick", function() if selectedId then QP.MovePlan(selectedId, 1) end end)
  tooltipFor(up, "Move the selected quest earlier in your plan.")
  tooltipFor(down, "Move the selected quest later in your plan.")
  frame.reorder = { up, down }
  reorderUpdate = function()
    local show = activeTab == TAB_PLAN and selectedId and QP.IsPlanned(selectedId)
    up:SetShown(show and true or false); down:SetShown(show and true or false)
  end
end

local function ensureFrame()
  if frame then return end
  buildFrame()
  buildToolbar()
  buildList()
  buildDetail()
  buildTabs()
  buildPlanReorder()
  D.RefreshPlayer()
  local lvl = D.player.level or 1
  minBox:SetText(max(1, lvl - 3))
  maxBox:SetText(lvl + 2)
  frame:SetScript("OnShow", function()
    if D.Init() and D.state == "idle" then D.BuildIndex() end
    QP.Refresh()
  end)
  D.OnIndexUpdate(function()
    if not frame:IsShown() then return end
    if D.state == "ready" then QP.Refresh() else showIndexState() end
  end)
  QP.OnPlanChanged(function() QP.Refresh() end)
  U.OnUpdate(function()
    if not frame:IsShown() then return end
    if U.state == "ready" then QP.Refresh()
    elseif activeTab == TAB_UPGRADES then showIndexState() end
  end)
  selectTab(1)
  renderWelcome("Plan your next quests.")
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function QP.Toggle()
  ensureFrame()
  frame:SetShown(not frame:IsShown())
end

function QP.ShowTab(i)
  ensureFrame()
  frame:Show()
  selectTab(i)
end

function QP.ShowSearch(text)
  ensureFrame()
  frame:Show()
  searchBox:SetText(text or "")
  selectTab(1)
end

function QP.ShowQuest(id)
  ensureFrame()
  frame:Show()
  if selectedId and selectedId ~= id then
    history[#history + 1] = selectedId
    if #history > 30 then table.remove(history, 1) end
  end
  selectedId = id
  if not D.Init() then renderWelcome(D.error or "QuestieDB unavailable.") return end
  render(id)
  updateRows()
  if reorderUpdate then reorderUpdate() end
end
