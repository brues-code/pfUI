CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or {
  ["WARRIOR"]     = {0, 0.25, 0, 0.25},
  ["MAGE"]        = {0.25, 0.49609375, 0, 0.25},
  ["ROGUE"]       = {0.49609375, 0.7421875, 0, 0.25},
  ["DRUID"]       = {0.7421875, 0.98828125, 0, 0.25},
  ["HUNTER"]      = {0, 0.25, 0.25, 0.5},
  ["SHAMAN"]      = {0.25, 0.49609375, 0.25, 0.5},
  ["PRIEST"]      = {0.49609375, 0.7421875, 0.25, 0.5},
  ["WARLOCK"]     = {0.7421875, 0.98828125, 0.25, 0.5},
  ["PALADIN"]     = {0, 0.25, 0.5, 0.75},
  ["DEATHKNIGHT"] = {0.25, .5, 0.5, .75},
  ["GM"]          = {0.5, 0.73828125, 0.5, .75},
}

-- race icons live in Interface\Glues\CharacterCreate\UI-CharacterCreate-Races
-- keyed by RACEKEY_GENDER (englishRace .. sex); mirrors the GlueXML table,
-- which isn't loaded in-world. includes the Turtle-specific BloodElf/Goblin.
RACE_ICON_TCOORDS = RACE_ICON_TCOORDS or {
  ["HUMAN_MALE"]      = {0,     0.125, 0,    0.25},
  ["DWARF_MALE"]      = {0.125, 0.25,  0,    0.25},
  ["GNOME_MALE"]      = {0.25,  0.375, 0,    0.25},
  ["NIGHTELF_MALE"]   = {0.375, 0.5,   0,    0.25},
  ["TAUREN_MALE"]     = {0,     0.125, 0.25, 0.5},
  ["SCOURGE_MALE"]    = {0.125, 0.25,  0.25, 0.5},
  ["TROLL_MALE"]      = {0.25,  0.375, 0.25, 0.5},
  ["ORC_MALE"]        = {0.375, 0.5,   0.25, 0.5},
  ["BLOODELF_MALE"]   = {0.5,   0.625, 0.25, 0.5},
  ["GOBLIN_MALE"]     = {0.5,   0.625, 0,    0.25},

  ["HUMAN_FEMALE"]    = {0,     0.125, 0.5,  0.75},
  ["DWARF_FEMALE"]    = {0.125, 0.25,  0.5,  0.75},
  ["GNOME_FEMALE"]    = {0.25,  0.375, 0.5,  0.75},
  ["NIGHTELF_FEMALE"] = {0.375, 0.5,   0.5,  0.75},
  ["TAUREN_FEMALE"]   = {0,     0.125, 0.75, 1.0},
  ["SCOURGE_FEMALE"]  = {0.125, 0.25,  0.75, 1.0},
  ["TROLL_FEMALE"]    = {0.25,  0.375, 0.75, 1.0},
  ["ORC_FEMALE"]      = {0.375, 0.5,   0.75, 1.0},
  ["BLOODELF_FEMALE"] = {0.5,   0.625, 0.75, 1.0},
  ["GOBLIN_FEMALE"]   = {0.5,   0.625, 0.5,  0.75},
}

-- barlength = {[formfactor]={cols, rows}}
pfGridmath = {
  [1] = {{1,1}},
  [2] = {{2,1},{1,2}},
  [3] = {{3,1},{1,3}},
  [4] = {{4,1},{2,2},{1,4}},
  [5] = {{5,1},{1,5}},
  [6] = {{6,1},{3,2},{2,3},{1,6}},
  [7] = {{7,1},{1,7}},
  [8] = {{8,1},{4,2},{2,4},{1,8}},
  [9] = {{9,1},{3,3},{1,9}},
  [10] = {{10,1},{5,2},{2,5},{1,10}},
  [11] = {{11,1},{1,11}},
  [12] = {{12,1},{6,2},{4,3},{3,4},{2,6},{1,12}}
}

-- list of valid unitstrings
pfValidUnits = {}
pfValidUnits["pet"] = true
pfValidUnits["player"] = true
pfValidUnits["target"] = true
pfValidUnits["mouseover"] = true

pfValidUnits["focus"] = true
pfValidUnits["focustarget"] = true
pfValidUnits["focustargettarget"] = true

pfValidUnits["pettarget"] = true
pfValidUnits["playertarget"] = true
pfValidUnits["targettarget"] = true
pfValidUnits["mouseovertarget"] = true
pfValidUnits["targettargettarget"] = true

for i=1,4 do
  pfValidUnits["party" .. i] = true
  pfValidUnits["party" .. i .. "target"] = true
  pfValidUnits["partypet" .. i] = true
  pfValidUnits["partypet" .. i .. "target"] = true
end

for i=1,40 do
  pfValidUnits["raid" .. i] = true
  pfValidUnits["raid" .. i .. "target"] = true

  pfValidUnits["raidpet" .. i] = true
  pfValidUnits["raidpet" .. i .. "target"] = true

  pfValidUnits["nameplate" .. i] = true
  pfValidUnits["nameplate" .. i .. "target"] = true
end

-- Vendor-buy prices. env\selldata.lua fills this in on stock clients; on
-- Turtle, modules\turtle-wow.lua supplies the server's own table. Declared
-- empty here so modules\sellvalue.lua always has a table to index, even with
-- the turtle-wow module disabled.
pfSellData = {}
