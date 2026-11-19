-- Mock-API smoke tests for QuestPlanner. Usage: lua5.1 tests/run_tests.lua [addonDir]
local dir = (arg and arg[1]) or "."
local failures = 0
local function check(cond, msg) if not cond then failures = failures + 1; io.write("FAIL: ", msg, "\n") end end

local function run(atlases, pawn)
  -- fresh global state per run
  dofile(dir .. "/tests/wowmock.lua")
  __atlasesPresent = atlases
  if pawn then for k, v in pairs(__PawnMock) do _G[k] = v end end
  QuestPlannerDB, QuestPlannerChar = nil, nil
  local before = {}
  for k in pairs(_G) do before[k] = true end
  local leaks = {}
  setmetatable(_G, { __newindex = function(t, k, v)
    if not tostring(k):match("^QuestPlanner") and not tostring(k):match("^SLASH_") and not tostring(k):match("^__") then leaks[#leaks + 1] = k end
    rawset(t, k, v)
  end })

  local QP = {}
  for _, f in ipairs({ "Data.lua", "Upgrades.lua", "Core.lua", "UI.lua" }) do
    local chunk = assert(loadfile(dir .. "/" .. f))
    chunk("QuestPlanner", QP)
  end
  local function fire(ev, ...) for _, fr in ipairs(__frames) do local s = fr._scripts and fr._scripts.OnEvent if s then s(fr, ev, ...) end end end
  local function pump(n) for _ = 1, n do __now = __now + 0.1 for _, fr in ipairs(__frames) do local s = fr._scripts and fr._scripts.OnUpdate if s then s(fr, 0.1) end end end end

  fire("ADDON_LOADED", "QuestPlanner")
  fire("PLAYER_LOGIN")
  QP.Toggle()
  pump(50)
  check(QP.Data.state == "ready", "index ready (atlases=" .. tostring(atlases) .. ")")
  check(#QP.Data.Search({ text = "", mineOnly = true, hideDone = true }) >= 1, "search returns quests")
  check(#QP.Data.Search({ text = "den" }) == 1, "name search")
  check(#QP.Data.Search({ gearOnly = true }) == 1, "gear filter")
  check(QP.Data.Status(100) == "done", "completed status")
  check(QP.Data.Status(103) == "unavailable", "faction filter")
  check(QP.Data.GearRewardItem(102) == 7001, "gear reward item")
  -- Upgrades
  QP.ShowTab(3)
  pump(30)
  local U = QP.Upgrades
  check(U.state == "ready", "upgrade scan finished")
  local list = U.List()
  check(#list == 1 and list[1].id == 102 and list[1].itemId == 7001, "upgrade found for quest 102 (" .. #list .. ")")
  local label = list[1] and U.Label(list[1])
  if pawn then check(label == "+12.4%", "pawn label " .. tostring(label)) else check(label == "+10 item levels", "ilvl label " .. tostring(label)) end
  check(U.Get(102) ~= nil, "byQuest lookup")
  QP.ShowQuest(102)
  fire("PLAYER_EQUIPMENT_CHANGED", 16)
  check(U.dirty or U.state == "scanning", "equipment change marks dirty")
  QP.Refresh()
  pump(30)
  check(U.state == "ready" and not U.dirty, "rescan after equipment change")
  QP.ShowTab(1)
  local chain = QP.Data.Chain(101)
  check(#chain == 3, "chain has ancestor and follower")
  for _, id in ipairs({ 100, 101, 102, 103, 104, 99999 }) do QP.ShowQuest(id) end
  QP.AddToPlan(101)
  QP.AddChainToPlan(102)
  check(#QP.char.plan == 2, "plan size")
  QP.SetNote(101, "bring pelts")
  QP.ShowQuest(101)
  for _, tab in ipairs({ 4, 3, 2, 1 }) do QP.ShowTab(tab) end
  QP.SortPlan("level"); QP.SortPlan("zone"); QP.MovePlan(102, -1)
  QP.SetWaypoint(44, 50, 52, "Bob")
  QP.InsertLink(101)
  check(__lastLink and __lastLink:find("101"), "quest link")
  SlashCmdList.QUESTPLANNER("wolves")
  SlashCmdList.QUESTPLANNER("101")
  SlashCmdList.QUESTPLANNER("near")
  SlashCmdList.QUESTPLANNER("plan")
  fire("QUEST_TURNED_IN", 101)
  QP.ClearDone()
  fire("PLAYER_LOGOUT")
  local saved = QuestPlannerDB.backup and QuestPlannerDB.backup["Constable-Smithers"]
  check(saved and #saved == 1, "backup written")
  QuestPlannerChar = nil
  fire("ADDON_LOADED", "QuestPlanner")
  check(#QP.char.plan == 1, "plan restored from backup")
  check(#leaks == 0, "no global leaks: " .. table.concat(leaks, ", "))
  setmetatable(_G, nil)
  for k in pairs(__PawnMock) do _G[k] = nil end
end

for _, cfg in ipairs({ { true, true }, { false, false }, { true, false } }) do
  local ok, err = pcall(run, cfg[1], cfg[2])
  check(ok, ("run (atlases=%s, pawn=%s): %s"):format(tostring(cfg[1]), tostring(cfg[2]), tostring(err)))
end
if failures > 0 then io.write(failures, " failure(s)\n"); os.exit(1) end
io.write("All tests passed\n")
