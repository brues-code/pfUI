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
