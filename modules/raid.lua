pfUI:RegisterModule("raid", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  -- tell RaidFrame.lua pfUI replaces party frames
  HookAddonOrVariable("Blizzard_RaidUI", function()
    GROUP_REPLACE_PARTY = "1"
  end)

  pfUI.uf.raid = CreateFrame("Frame", "pfRaidUpdater", UIParent)

  local maxraid = tonumber(C.unitframes.maxraid)
  local rawborder, default_border = GetBorderSize("chat")
  local cluster = CreateFrame("Frame", "pfRaidCluster", UIParent)
  cluster:SetFrameLevel(20)
  cluster:SetSize(120, 10)
  cluster:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", default_border*2, C.chat.left.height + default_border*5)
  UpdateMovable(cluster)

  -- Separate, independently-movable block that mirrors the raid grid layout
  -- for pet frames (raidpet1..40). Defaults to the right of the raid grid.
  local petcluster = CreateFrame("Frame", "pfRaidPetCluster", UIParent)
  petcluster:SetFrameLevel(20)
  petcluster:SetSize(120, 10)
  petcluster:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", default_border*2 + 300, C.chat.left.height + default_border*5)
  UpdateMovable(petcluster)

  -- flat pool of pet frames, laid out by LayoutPets (mirror or collapsed)
  pfUI.uf.raid.pets = {}

  -- 1-based grid slot -> (row, col) for the current fill direction, matching
  -- the raid grid's own fill loops.
  local function SlotToCoord(slot, fill, x, y)
    slot = slot - 1
    if fill == "VERTICAL" then
      return floor(slot / y) + 1, mod(slot, y) + 1
    else
      return mod(slot, x) + 1, floor(slot / x) + 1
    end
  end

  pfUI.uf.raid.tanksfirst = {
    ["PF_TANK_TOGGLE"] = { T["Toggle as Tank"], "toggleTank" }
  }

  -- no tank order for now, just "all tanks first"
  pfUI.uf.raid.tankrole = { }

  function pfUI.uf.raid:UpdateConfig()
    local rawborder, default_border = GetBorderSize("unitframes")
    maxraid = tonumber(C.unitframes.maxraid)
    local showpets = C.unitframes.raidpet.visible == "1"
    self.showpets = showpets

    for i=1,maxraid do
      pfUI.uf.raid[i] = pfUI.uf.raid[i] or pfUI.uf:CreateUnitFrame("Raid", i, C.unitframes.raid)
      pfUI.uf.raid[i]:SetParent(cluster)
      pfUI.uf.raid[i]:SetFrameLevel(5)

      pfUI.uf.raid[i]:UpdateConfig()
      pfUI.uf.raid[i]:UpdateFrameSize()

      if showpets then
        self.pets[i] = self.pets[i] or pfUI.uf:CreateUnitFrame("RaidPet", i, C.unitframes.raidpet, 0.5)
        self.pets[i]:SetParent(petcluster)
        self.pets[i]:SetFrameLevel(5)
        self.pets[i]:UpdateConfig()
        self.pets[i]:UpdateFrameSize()
      elseif self.pets[i] then
        self.pets[i]:UpdateConfig()
        self.pets[i]:Hide()
        RemoveMovable(self.pets[i])
      end
    end

    local i = 1
    local width = pfUI.uf.raid[1]:GetWidth()+2*default_border
    local height = pfUI.uf.raid[1]:GetHeight()+2*default_border
    local layout = pfUI.uf.raid[1].config.raidlayout
    local padding = tonumber(pfUI.uf.raid[1].config.raidpadding)*GetPerfectPixel()
    local fill = pfUI.uf.raid[1].config.raidfill
    local _, _, x, y = string.find(layout,"(.+)x(.+)")
    x, y = tonumber(x), tonumber(y)

    if showpets then
      local petcfg = C.unitframes.raidpet
      local _, _, px, py = string.find(petcfg.raidlayout, "(.+)x(.+)")
      self.petgrid = {
        fill = petcfg.raidfill, x = tonumber(px), y = tonumber(py),
        pad = tonumber(petcfg.raidpadding) * GetPerfectPixel(),
        w = self.pets[1]:GetWidth()+2*default_border,
        h = self.pets[1]:GetHeight()+2*default_border,
      }
    end

    if fill == "VERTICAL" then
      for r=1, x do for g=1, y do
        if pfUI.uf.raid[i] then
          pfUI.uf.raid[i]:ClearAllPoints()
          pfUI.uf.raid[i]:SetPoint("BOTTOMLEFT", (r-1)*(padding+width), (g-1)*(padding+height))
          UpdateMovable(pfUI.uf.raid[i], true)
        end
        i = i + 1
      end end
    else
      for g=1, y do for r=1, x do
        if pfUI.uf.raid[i] then
          pfUI.uf.raid[i]:ClearAllPoints()
          pfUI.uf.raid[i]:SetPoint("BOTTOMLEFT", (r-1)*(padding+width), (g-1)*(padding+height))
          UpdateMovable(pfUI.uf.raid[i], true)
        end
        i = i + 1
      end end
    end

    self:LayoutPets()

    self:Show()
  end

  function pfUI.uf.raid:LayoutPets()
    if not self.showpets or not self.petgrid then return end
    local grid = self.petgrid

    local function place(pet, cell, id)
      pet.id = id
      local r, g = SlotToCoord(cell, grid.fill, grid.x, grid.y)
      pet:ClearAllPoints()
      pet:SetPoint("BOTTOMLEFT", petcluster, "BOTTOMLEFT", (r-1)*(grid.pad+grid.w), (g-1)*(grid.pad+grid.h))
      UpdateMovable(pet, true)
      pet:UpdateVisibility()
    end

    if C.unitframes.raidpet.collapse == "1" then
      -- Pack the pets that exist into the leading cells, no gaps.
      local k = 0
      for id = 1, maxraid do
        if UnitExists("raidpet"..id) and self.pets[k+1] then
          k = k + 1
          place(self.pets[k], k, id)
        end
      end
      for j = k+1, maxraid do
        if self.pets[j] then self.pets[j].id = 0 self.pets[j]:Hide() end
      end
    else
      -- Mirror: cell N always shows raidpet<N> at a fixed position.
      for id = 1, maxraid do
        if self.pets[id] then place(self.pets[id], id, id) end
      end
    end
  end

  pfUI.uf.raid:UpdateConfig()

  local function SetRaidIndex(frame, id)
    frame.id = id
    frame.label = "raid"
    frame:UpdateVisibility()
  end

  -- add units to their groups; collapse packs everyone into the leading slots
  function pfUI.uf.raid:AddUnitToGroup(index, group)
    if C.unitframes.raid.collapse == "1" then
      for ids = 1, maxraid do
        if pfUI.uf.raid[ids] and pfUI.uf.raid[ids].id == 0 and pfUI.uf.raid[ids].config.visible == "1" then
          SetRaidIndex(pfUI.uf.raid[ids], index)
          return
        end
      end
    else
      for subindex = 1, 5 do
        local ids = subindex + 5*(group-1)
        if pfUI.uf.raid[ids] and pfUI.uf.raid[ids].id == 0 and pfUI.uf.raid[ids].config.visible == "1" then
          SetRaidIndex(pfUI.uf.raid[ids], index)
          return
        end
      end
    end
  end

  pfUI.uf.raid:Hide()
  pfUI.uf.raid:RegisterEvent("RAID_ROSTER_UPDATE")
  pfUI.uf.raid:RegisterEvent("PARTY_MEMBERS_CHANGED")
  pfUI.uf.raid:RegisterEvent("PARTY_LEADER_CHANGED")
  pfUI.uf.raid:RegisterEvent("VARIABLES_LOADED")
  pfUI.uf.raid:RegisterEvent("UNIT_PET")
  pfUI.uf.raid:SetScript("OnEvent", function()
    if event == "UNIT_PET" then
      if this.showpets and C.unitframes.raidpet.collapse == "1" then
        this:LayoutPets()
      end
      return
    end
    this:Show()
    -- Debounce: delay update by 0.5s to batch rapid roster changes (mass swaps)
    this.pendingUpdate = GetTime() + 0.5
  end)
  pfUI.uf.raid:SetScript("OnUpdate", function()
    -- Wait for debounce: don't update until 0.5s after last event
    if this.pendingUpdate and GetTime() < this.pendingUpdate then return end
    -- Throttle raid roster updates to 1 FPS max
    if (this.tick or 0) > GetTime() then return end
    this.tick = GetTime() + 1.0
    this.pendingUpdate = nil

    -- don't proceed without raid
    if not IsInRaid() then return end

    -- clear all existing frames
    for i=1, maxraid do SetRaidIndex(pfUI.uf.raid[i], 0) end

    -- sort tanks into their groups
    for i=1, GetNumRaidMembers() do
      local name, _, subgroup  = GetRaidRosterInfo(i)
      if name and pfUI.uf.raid.tankrole[name] then
        pfUI.uf.raid:AddUnitToGroup(i, subgroup)
      end
    end

    -- sort players into roster
    for i=1, GetNumRaidMembers() do
      local name, _, subgroup  = GetRaidRosterInfo(i)
      if name and not pfUI.uf.raid.tankrole[name] then
        pfUI.uf.raid:AddUnitToGroup(i, subgroup)
      end
    end

    this:LayoutPets()

    -- Smart GUID-based updates: only refresh frames where unit changed
    if pfUI.uf.guidTracker then
      local tracker = pfUI.uf.guidTracker
      
      for i = 1, maxraid do
        local frame = pfUI.uf.raid[i]
        if frame and frame.id and frame.id > 0 then
          local unit = "raid" .. frame.id
          local newGuid = UnitGUID(unit)
          local oldGuid = tracker.frameToGuid[frame]
          
          if newGuid ~= oldGuid then
            -- GUID changed = different player = need full update
            tracker.frameToGuid[frame] = newGuid
            frame.update_full = true
            frame.update_aura = true  -- Force aura refresh!
          end
        end
      end
    end

    -- rebuild unitmap after frame IDs are assigned
    if pfUI.uf.RebuildUnitmap then
      pfUI.uf.RebuildUnitmap()
    end

    this:Hide()
  end)

  -- raid popup option to toggle tank role
  for _, menu in pairs({"RAID", "PARTY"}) do
    for label, data in pairs(pfUI.uf.raid.tanksfirst) do
      UnitPopupButtons[label] = { text = TEXT(data[1]), dist = 0 }
      table.insert(UnitPopupMenus[menu], 3, label)
    end
  end

  hooksecurefunc("UnitPopup_OnClick", function()
    local dropdownFrame = UIDROPDOWNMENU_INIT_MENU and _G[UIDROPDOWNMENU_INIT_MENU]
    if not dropdownFrame then return end
    local button = this.value
    local unit = dropdownFrame.unit
    local name = dropdownFrame.name

    if button and pfUI.uf.raid.tanksfirst[button] and name then
      pfUI.uf.raid.tankrole[name] = not pfUI.uf.raid.tankrole[name]
      pfUI.uf.raid:Show()
    end
  end)
end)