std = "lua51"
max_line_length = false
exclude_files = { "tests/**", ".release/**" }
ignore = { "212", "213", "432", "542" } -- unused args/loop vars, shadowed self, empty if branch
globals = {
  "QuestPlanner", "QuestPlannerDB", "QuestPlannerChar",
  "SLASH_QUESTPLANNER1", "SLASH_QUESTPLANNER2", "SlashCmdList", "SetItemRef",
  "QuestPlanner_OnCompartmentClick", "QuestPlanner_OnCompartmentEnter", "QuestPlanner_OnCompartmentLeave",
}
read_globals = {
  -- Questie database
  "LibQuestieDB", "QuestDB", "NpcDB", "ObjectDB", "ItemDB",
  -- optional addons
  "TomTom", "PawnShouldItemLinkHaveUpgradeArrow", "PawnIsReady", "PawnGetItemData", "PawnIsItemAnUpgrade",
  -- WoW API
  "CreateFrame", "UIParent", "Minimap", "GameTooltip", "DEFAULT_CHAT_FRAME", "UISpecialFrames",
  "C_Timer", "C_Map", "C_Item", "C_QuestLog", "C_SuperTrack", "C_Texture", "C_AddOns", "UiMapPoint", "Item",
  "GetQuestDifficultyColor", "GetCoinTextureString", "GetItemIcon", "GetMaxPlayerLevel", "GetCursorPosition",
  "GetQuestLogRewardXP", "GetQuestLogRewardMoney", "GetNumQuestLogChoices", "GetNumQuestLogRewards", "GetQuestLogItemLink",
  "GetRealmName", "UnitName", "UnitLevel", "UnitClass", "UnitRace", "UnitFactionGroup", "UnitXP", "UnitXPMax",
  "IsShiftKeyDown", "IsAltKeyDown", "IsModifiedClick", "HandleModifiedItemClick", "ChatEdit_InsertLink", "ChatFrame_OpenChat",
  "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab", "PanelTemplates_TabResize", "QuestTextContrast",
  "ITEM_QUALITY_COLORS", "LOCALIZED_CLASS_NAMES_MALE", "hooksecurefunc", "debugprofilestop", "wipe", "tinsert",
  "time", "date", "bit", "strsplit", "strtrim", "CopyTable", "GetFactionInfoByID", "C_Reputation", "C_CreatureInfo",
  "GetAreaInfo", "Enum", "ChatFrameUtil", "ChatEdit_ChooseBoxForSend", "ChatEdit_ActivateChat", "LoadAddOn",
  "GetQuestsCompleted", "GetQuestLogIndexByID", "C_TradeSkillUI", "GetQuestLink", "GetInventoryItemLink", "GetTime", "GetItemInfo",
}
