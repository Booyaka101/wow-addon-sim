-- strict-stubs.lua — API stubs that VALIDATE calls against real client behavior.
--
-- The sim's original stubs accepted everything (permissive). The live test proved
-- this is the wrong default: GameTooltip:HookScript("OnTooltipSetUnit", ...) was
-- accepted by the stub but crashes on the real Forever client because that script
-- doesn't exist on the Midnight tooltip system.
--
-- These stubs are STRICT: they validate argument types, script names, method
-- existence, and return shapes. An addon that passes the strict sim has a much
-- higher probability of working on the real client.

-- ---------------------------------------------------------------------------
-- valid script names per widget type (from the WoW UI source)
-- Addons can only hook/set scripts that the widget type supports.

local VALID_SCRIPTS = {
    Frame = {
        "OnLoad", "OnEvent", "OnUpdate", "OnShow", "OnHide", "OnSizeChanged",
        "OnMouseDown", "OnMouseUp", "OnMouseWheel", "OnKeyDown", "OnKeyUp",
        "OnDragStart", "OnDragStop", "OnEnter", "OnLeave", "OnAttributeChanged",
        "OnChar", "OnTooltipCleared", "OnTooltipSetUnit", "OnTooltipSetItem",
        "OnTooltipSetSpell", "OnTooltipSetDefaultAnchor", "OnTooltipAddMoney",
        "OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave",
        "OnReceiveDrag", "OnCharComposition",
    },
    Button = {
        "OnClick", "OnDoubleClick", "PostClick", "PreClick",
        -- inherits Frame scripts
        "OnLoad", "OnEvent", "OnUpdate", "OnShow", "OnHide", "OnEnter", "OnLeave",
    },
    EditBox = {
        "OnTextChanged", "OnTextSet", "OnInputLanguageChanged", "OnEditFocusGained",
        "OnEditFocusLost", "OnEnterPressed", "OnEscapePressed", "OnTabPressed",
        "OnSpacePressed", "OnArrowPressed", "OnCursorPositionChanged",
        "OnEditFocusGained", "OnEditFocusLost", "OnChar", "OnKeyDown", "OnKeyUp",
    },
    ScrollFrame = { "OnVerticalScroll", "OnHorizontalScroll", "OnScrollRangeChanged" },
    Slider = { "OnValueChanged", "OnMinMaxChanged" },
    CheckButton = { "OnClick" },
    ColorSelect = { "OnColorSelect" },
    MessageFrame = { "OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave" },
    SimpleHTML = { "OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave" },
    GameTooltip = {
        -- Midnight+ tooltip system: OnTooltipSetUnit may NOT be available
        "OnTooltipCleared", "OnTooltipAddMoney",
        "OnTooltipSetItem", "OnTooltipSetSpell", "OnTooltipSetDefaultAnchor",
        -- OnTooltipSetUnit is NOT in this list: it was removed in Midnight's
        -- tooltip rewrite and HookScript will error if it doesn't exist.
        -- To detect if it's available: GameTooltip:HasScript("OnTooltipSetUnit")
    },
}

-- expand: child types inherit parent scripts
local INHERITS = {
    Button = { "Frame" },
    CheckButton = { "Button", "Frame" },
    EditBox = { "Frame" },
}

local function get_valid_scripts(widget_type)
    local scripts = {}
    local function add_from(t)
        if not t then return end
        for _, s in ipairs(VALID_SCRIPTS[t] or {}) do scripts[s] = true end
        for _, parent in ipairs(INHERITS[t] or {}) do add_from(parent) end
    end
    add_from(widget_type)
    return scripts
end

-- ---------------------------------------------------------------------------
-- strict frame factory

local function strict_create_frame(kind, name, parent, template)
    local f = {
        _kind = kind or "Frame",
        _name = name or "unnamed",
        _strict = true,
        _scripts = {}, _hooks = {}, _points = {}, _size = {w = 100, h = 100},
        _shown = false, _events = {}, _fonts = {}, _textures = {}, _children = {},
    }

    local valid_scripts = get_valid_scripts(f._kind)

    -- validate and store: SetScript / HookScript REJECT unknown script names
    f.SetScript = function(self, script_name, fn)
        if not valid_scripts[script_name] then
            SIM_ERRORS[#SIM_ERRORS + 1] = string.format(
                "STRICT: %s:SetScript(%q) — %q is not a valid script for %s (has it been removed in this client?)",
                self._name, script_name or "?", script_name or "?", self._kind)
            return
        end
        self._scripts[script_name] = fn
    end

    f.HookScript = function(self, script_name, fn)
        if not valid_scripts[script_name] then
            SIM_ERRORS[#SIM_ERRORS + 1] = string.format(
                "STRICT: %s:HookScript(%q) — %q is not a valid script for %s (has it been removed in this client?)",
                self._name, script_name or "?", script_name or "?", self._kind)
            return
        end
        self._hooks[script_name] = self._hooks[script_name] or {}
        table.insert(self._hooks[script_name], fn)
    end

    f.GetScript = function(self, script_name)
        return self._scripts[script_name]
    end

    f.HasScript = function(self, script_name)
        return valid_scripts[script_name] ~= nil
    end

    -- RegisterEvent validates event names
    local KNOWN_EVENTS = {
        PLAYER_LOGIN = true, PLAYER_LOGOUT = true, PLAYER_ENTERING_WORLD = true,
        PLAYER_LEAVING_WORLD = true, ADDON_LOADED = true, PLAYER_REGEN_ENABLED = true,
        PLAYER_REGEN_DISABLED = true, PLAYER_TARGET_CHANGED = true,
        UPDATE_MOUSEOVER_UNIT = true, UNIT_HEALTH = true, UNIT_POWER_UPDATE = true,
        COMBAT_TEXT_UPDATE = true, UNIT_AURA = true, ZONE_CHANGED_NEW_AREA = true,
        ZONE_CHANGED = true, MINIMAP_ZONE_CHANGED = true, PLAYER_LEVEL_UP = true,
        UNIT_EXITING_VEHICLE = true, UNIT_ENTERING_VEHICLE = true, UNIT_PET = true,
        GROUP_ROSTER_UPDATE = true, PARTY_MEMBERS_CHANGED = true,
        CHAT_MSG_ADDON = true, VARIABLES_LOADED = true, PLAYER_ALIVE = true,
        PLAYER_DEAD = true, PLAYER_UNGHOST = true, CURRENCY_DISPLAY_UPDATE = true,
        QUEST_ACCEPTED = true, QUEST_COMPLETE = true, QUEST_LOG_UPDATE = true,
        BAG_UPDATE = true, BAG_UPDATE_DELAYED = true, ITEM_LOCKED = true,
        MERCHANT_SHOW = true, MERCHANT_CLOSED = true, TRADE_SHOW = true,
        PET_BATTLE_OPENING_START = true, PET_BATTLE_CLOSE = true,
        PLAYER_SPECIALIZATION_CHANGED = true, ACTIVE_TALENT_GROUP_CHANGED = true,
        INSPECT_READY = true, UNIT_INVENTORY_CHANGED = true,
    }

    f.RegisterEvent = function(self, event)
        if not KNOWN_EVENTS[event] then
            -- don't error on unknown events — Blizzard adds new ones — but log it
            SIM_LOG[#SIM_LOG + 1] = "[strict] unknown event registered: " .. tostring(event) .. " (may be new in this client)"
        end
        self._events[event] = true
        SIM_EVENT_SCRIPTS[event] = SIM_EVENT_SCRIPTS[event] or {}
        SIM_EVENT_SCRIPTS[event][self] = true
    end

    -- standard frame methods (non-validating for speed, these are stable)
    f.UnregisterEvent = function(self, event) self._events[event] = nil end
    f.IsEventRegistered = function(self, event) return self._events[event] or false end
    f.Show = function(self) self._shown = true end
    f.Hide = function(self) self._shown = false end
    f.IsShown = function(self) return self._shown end
    f.IsVisible = function(self) return self._shown end
    f.SetSize = function(self, w, h)
        if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
            SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetSize(" .. tostring(w) .. "," .. tostring(h) .. ") — must be positive numbers"
            return
        end
        self._size = {w = w, h = h}
    end
    f.SetWidth = function(self, w) self._size.w = w end
    f.SetHeight = function(self, h) self._size.h = h end
    f.GetWidth = function(self) return self._size.w end
    f.GetHeight = function(self) return self._size.h end
    f.SetPoint = function(self, ...) self._points[#self._points + 1] = {...} end
    f.ClearAllPoints = function(self) self._points = {} end
    f.GetPoint = function(self, i)
        local p = self._points[i or #self._points]
        if p then return p[1], self, p[3] or "CENTER", p[4] or 0, p[5] or 0 end
        return nil
    end
    f.GetNumPoints = function(self) return #self._points end
    f.SetMovable = function() end
    f.EnableMouse = function(self, ...) self._mouse = ... end
    f.SetClampedToScreen = function() end
    f.RegisterForDrag = function() end
    f.RegisterForClicks = function() end
    f.SetFrameStrata = function() end
    f.SetFrameLevel = function() end
    f.SetScale = function(self, s)
        if type(s) ~= "number" or s <= 0 then
            SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetScale(" .. tostring(s) .. ") — must be positive"
        end
    end
    f.SetAlpha = function(self, a)
        if type(a) ~= "number" or a < 0 or a > 1 then
            SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetAlpha(" .. tostring(a) .. ") — must be in [0,1]"
        end
        self._alpha = a
    end
    f.GetAlpha = function(self) return self._alpha or 1 end
    f.StartMoving = function() end
    f.StopMovingOrSizing = function() end
    f.SetNormalTexture = function() end
    f.SetPushedTexture = function() end
    f.SetHighlightTexture = function() end
    f.SetBackdrop = function() end
    f.SetBackdropColor = function() end
    f.SetBackdropBorderColor = function() end
    f.EnableDrawLayer = function() end
    f.SetID = function(self, id) self._id = id end
    f.GetID = function(self) return self._id end
    f.SetParent = function(self, p) self._parent = p end
    f.GetParent = function(self) return self._parent end
    f.GetName = function(self) return self._name end
    f.GetFrameType = function(self) return self._kind end
    f.IsObjectType = function(self, t) return self._kind == t end
    f.GetEffectiveScale = function(self) return 1 end
    f.GetScale = function(self) return 1 end
    f.IsMouseOver = function(self) return false end
    f.GetCenter = function(self) return 0, 0 end
    f.GetRect = function(self) return 0, 0, self._size.w, self._size.h end
    f.IsShown = function(self) return self._shown end
    f.CreateTexture = function(self)
        return { SetAllPoints = function() end, SetSize = function() end,
            SetTexture = function() end, SetColorTexture = function() end,
            SetTexCoord = function() end, SetVertexColor = function() end,
            SetDrawLayer = function() end, Show = function() end, Hide = function() end,
            SetPoint = function() end, ClearAllPoints = function() end,
            SetBlendMode = function() end, SetDesaturated = function() end }
    end
    f.CreateFontString = function(self)
        local fs = { _text = "", _shown = false, _points = {} }
        fs.SetText = function(s, t)
            if type(t) ~= "string" and type(t) ~= "number" then
                SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetText(" .. type(t) .. ") — expected string or number"
            end
            s._text = tostring(t or "")
        end
        fs.GetText = function(s) return s._text end
        fs.SetFont = function() end
        fs.GetFont = function() return "Font.ttf", 16, "" end
        fs.SetFontObject = function() end
        fs.SetTextColor = function(s, r, g, b, a)
            if type(r) ~= "number" or r < 0 or r > 1 then
                SIM_ERRORS[#SIM_ERRORS + 1] = "STRICT: " .. self._name .. ":SetTextColor r=" .. tostring(r) .. " — must be in [0,1]"
            end
        end
        fs.SetJustifyH = function() end
        fs.SetJustifyV = function() end
        fs.SetPoint = function(...) fs._points[#fs._points + 1] = {...} end
        fs.ClearAllPoints = function() fs._points = {} end
        fs.GetPoint = function(s, i)
            local p = s._points[i or #s._points]
            if p then return p[1], f, p[3] or "CENTER", p[4] or 0, p[5] or 0 end
        end
        fs.SetSize = function() end
        fs.SetWidth = function() end
        fs.SetHeight = function() end
        fs.Show = function(s) s._shown = true end
        fs.Hide = function(s) s._shown = false end
        fs.SetAlpha = function() end
        fs.SetShadowColor = function() end
        fs.SetShadowOffset = function() end
        fs.SetSpacing = function() end
        fs.SetAllPoints = function() end
        fs.SetWordWrap = function() end
        fs.SetMaxLines = function() end
        fs.GetStringWidth = function() return 100 end
        fs.GetStringHeight = function() return 20 end
        return fs
    end
    f.CreateAnimationGroup = function(self)
        return { CreateAnimation = function()
            return { SetDuration = function() end, SetTarget = function() end }
        end }
    end

    return f
end

-- install strict CreateFrame
StrictCreateFrame = strict_create_frame

-- strict GameTooltip: does NOT list OnTooltipSetUnit as hookable
-- (matches the Midnight+ tooltip system behavior on Forever build 70338)
StrictGameTooltip = strict_create_frame("GameTooltip", "GameTooltip")
StrictGameTooltip.AddLine = function(self, text)
    SIM_LOG[#SIM_LOG + 1] = "[tooltip] " .. tostring(text)
end
StrictGameTooltip.AddDoubleLine = function(self, l, r)
    SIM_LOG[#SIM_LOG + 1] = "[tooltip] " .. tostring(l) .. " | " .. tostring(r)
end
StrictGameTooltip.GetUnit = function(self) return "SimUnit", "target" end
StrictGameTooltip.GetSpell = function(self) return nil end
StrictGameTooltip.GetItem = function(self) return nil end
StrictGameTooltip.SetOwner = function() end
