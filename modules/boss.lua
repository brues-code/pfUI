pfUI:RegisterModule("boss", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  -- ClassicAPI's boss1..boss5: the world bosses of the encounter your group
  -- fights, in the order they joined it. A boss keeps its token until the
  -- encounter ends, dead or not, and every unit event fires for the token.
  local MAX_BOSS_FRAMES = 5

  pfUI.uf.boss = {}

  function pfUI.uf.boss:UpdateConfig()
    for i = 1, MAX_BOSS_FRAMES do
      self[i] = self[i] or pfUI.uf:CreateUnitFrame("Boss", i, C.unitframes.boss)
      self[i]:UpdateFrameSize()
      self[i]:ClearAllPoints()

      -- the frames stack below the first one, which unlock mode drags with
      -- them, until one gets a position of its own
      if i == 1 then
        self[i]:SetPoint("RIGHT", UIParent, "RIGHT", -120, 150)
      else
        self[i]:SetPoint("TOP", self[i-1], "BOTTOM", 0, -20)
        self[i].attachTo = self[i-1]
      end

      self[i]:UpdateConfig()
      UpdateMovable(self[i])
    end
  end

  pfUI.uf.boss:UpdateConfig()

  -- A boss getting or losing its token is the only change to which unit a
  -- frame shows; between these the token's unit events keep it current.
  pfUI.events:RegisterFrameEventAndCallback("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
    for i = 1, MAX_BOSS_FRAMES do
      pfUI.uf:RefreshUnit(pfUI.uf.boss[i], "all")
    end
  end)
end)
