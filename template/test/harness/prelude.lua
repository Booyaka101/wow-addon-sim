-- WoW client stubs: copy this file and customise for your addon's needs.
-- See wow-addon-sim for the full-featured version generated from real captures.

local OUT = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    OUT[#OUT + 1] = table.concat(parts, " ")
end

strlower = string.lower
strtrim = function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end

FRAMES = {}
CreateFrame = function(kind, name)
    local f = { kind = kind, name = name, events = {}, scripts = {}, _shown = false, _points = {} }
    FRAMES[#FRAMES + 1] = f
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.UnregisterEvent = function(self, e) self.events[e] = nil end
    f.SetScript = function(self, name, fn) self.scripts[name] = fn end
    f.HookScript = function(self, name, fn)
        self.scripts[name] = self.scripts[name] or {}
        if type(self.scripts[name]) == "table" then table.insert(self.scripts[name], fn) end
    end
    f.Show = function(self) self._shown = true end
    f.Hide = function(self) self._shown = false end
    f.IsShown = function(self) return self._shown end
    f.SetSize = function() end
    f.SetMovable = function() end
    f.EnableMouse = function() end
    f.SetClampedToScreen = function() end
    f.SetPoint = function(self, ...) self._points[#self._points + 1] = {...} end
    f.ClearAllPoints = function(self) self._points = {} end
    f.CreateTexture = function(self)
        return { SetAllPoints = function() end, SetTexture = function() end, SetColorTexture = function() end, SetSize = function() end, SetPoint = function() end }
    end
    f.CreateFontString = function(self)
        return { SetText = function() end, SetFont = function() end, SetAllPoints = function() end, SetTextColor = function() end, SetJustifyH = function() end, Show = function() end, Hide = function() end, SetPoint = function() end }
    end
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
SlashCmdList = {}

GetTime = function() return 1000.0 end
MyAddonDB = {}
