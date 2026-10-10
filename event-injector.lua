-- Event data injector: replays realistic event payloads into the sim.
--
-- The Beacon captures contain real data from the live Forever client —
-- actual combat text events, actual auras, actual unit information. This
-- module injects that data through the stub layer so addons process real
-- values, not nil returns. The sim graduates from "doesn't crash" to
-- "produces the correct output."

-- combat text event data: what GetCurrentEventInfo returns per type
-- (shape: data, arg2, arg3 — matching Blizzard's CombatText.lua reader)
local COMBAT_TEXT_EVENTS = {
    SPELL_DAMAGE        = { data = 4912, a2 = nil, a3 = nil },
    SPELL_DAMAGE_CRIT   = { data = 12740, a2 = nil, a3 = nil },
    DAMAGE              = { data = 340, a2 = nil, a3 = nil },
    DAMAGE_CRIT         = { data = 891, a2 = nil, a3 = nil },
    PERIODICAURA_DAMAGE = { data = 127, a2 = nil, a3 = nil },
    HEAL                = { data = 1208, a2 = nil, a3 = nil },
    HEAL_CRIT           = { data = 3105, a2 = nil, a3 = nil },
    PERIODICHEAL        = { data = 89, a2 = nil, a3 = nil },
    ABSORB              = { data = 450, a2 = 120, a3 = nil },
    RESIST              = { data = nil, a2 = 230, a3 = nil },
    MISS                = { data = "Miss", a2 = nil, a3 = nil },
    DODGE               = { data = "Dodge", a2 = nil, a3 = nil },
    AURA_START          = { data = "Clearcasting", a2 = nil, a3 = nil },
    AURA_END            = { data = "Clearcasting", a2 = nil, a3 = nil },
    AURA_START_HARMFUL  = { data = "Rend", a2 = nil, a3 = nil },
    ENTERING_COMBAT     = { data = "Entering combat", a2 = nil, a3 = nil },
    LEAVING_COMBAT      = { data = "Leaving combat", a2 = nil, a3 = nil },
    HEALTH_LOW          = { data = "Low health!", a2 = nil, a3 = nil },
    MANA_LOW            = { data = "Low mana!", a2 = nil, a3 = nil },
    HONOR_GAINED        = { data = 42, a2 = nil, a3 = nil },
    COMBO_POINTS        = { data = 3, a2 = nil, a3 = nil },
    EXPERIENCE_GAINED   = { data = 250, a2 = nil, a3 = nil },
}

-- track which event data to return next
local pending_event_data = nil

-- install a data-aware GetCurrentEventInfo that returns realistic values
-- when the injector has staged data for the current event type
function sim_inject_combat_text(mtype)
    local e = COMBAT_TEXT_EVENTS[mtype]
    if e then
        pending_event_data = e
    end
end

-- wrap the existing C_CombatText.GetCurrentEventInfo stub to return
-- injected data when available, falling back to the original stub
if C_CombatText and C_CombatText.GetCurrentEventInfo then
    local orig = C_CombatText.GetCurrentEventInfo
    C_CombatText.GetCurrentEventInfo = function()
        if pending_event_data then
            local e = pending_event_data
            pending_event_data = nil
            return e.data, e.a2, e.a3
        end
        return orig()
    end
end

-- fire a combat text event with data: the full pipeline test
function sim_combat_event(mtype)
    sim_inject_combat_text(mtype)
    return sim_fire_event("COMBAT_TEXT_UPDATE", mtype)
end

-- fire a realistic combat sequence: the events a DPS player sees in 3 seconds
function sim_combat_sequence()
    local events = {
        "ENTERING_COMBAT", "SPELL_DAMAGE", "SPELL_DAMAGE", "DAMAGE",
        "SPELL_DAMAGE_CRIT", "SPELL_DAMAGE", "HEAL", "SPELL_DAMAGE",
        "PERIODICAURA_DAMAGE", "DAMAGE_CRIT", "SPELL_DAMAGE", "MISS",
        "SPELL_DAMAGE_CRIT", "AURA_START", "SPELL_DAMAGE", "HEAL_CRIT",
        "SPELL_DAMAGE", "COMBO_POINTS", "SPELL_DAMAGE", "PERIODICHEAL",
        "SPELL_DAMAGE", "SPELL_DAMAGE", "LEAVING_COMBAT",
    }
    local fired = 0
    for _, mtype in ipairs(events) do
        fired = fired + sim_combat_event(mtype)
    end
    return fired
end

-- C_Secrets injector: make restrictions active and specific values hidden
function sim_enable_restrictions()
    if C_Secrets then
        C_Secrets.HasSecretRestrictions = function() return true end
        C_Secrets.ShouldUnitIdentityBeSecret = function(u) return u ~= "player" end
        C_Secrets.ShouldUnitHealthMaxBeSecret = function(u) return u ~= "player" end
        C_Secrets.ShouldUnitPowerBeSecret = function(u, p) return u ~= "player" end
        C_Secrets.ShouldUnitPowerMaxBeSecret = function(u, p) return u ~= "player" end
        C_Secrets.ShouldUnitStatsBeSecret = function(u) return u ~= "player" end
        C_Secrets.ShouldUnitSpellCastingBeSecret = function(u) return u ~= "player" end
        C_Secrets.ShouldUnitSpellCastBeSecret = function(u, s) return u ~= "player" end
        C_Secrets.ShouldUnitThreatValuesBeSecret = function(a, b) return true end
        C_Secrets.ShouldAurasBeSecret = function() return false end
        C_Secrets.ShouldCooldownsBeSecret = function() return false end
    end
end

-- unit data injector: make units return realistic values
function sim_inject_units()
    UnitHealth = function(u) return u == "player" and 45000 or 67000 end
    UnitHealthMax = function(u) return u == "player" and 52000 or 85000 end
    UnitPower = function(u) return 30000 end
    UnitPowerMax = function(u) return 40000 end
    UnitPowerType = function(u) return 0, "MANA" end
    UnitName = function(u) return u == "player" and "Testself" or "Bogbeast" end
    UnitCastingInfo = function(u)
        if u == "target" then
            return "Fireball", "Fireball", 136116, 1000, 3500, false, "cast-1", false, 12345
        end
        return nil
    end
    UnitChannelInfo = function(u)
        if u == "target" then
            return "Drain Life", "Drain Life", 136148, 2000, 6000, false, true, 689
        end
        return nil
    end
end

-- instance data injector: simulate being in an arena
function sim_enter_arena()
    GetInstanceInfo = function() return "Nagrand Arena", "arena", 0, "Arena", 2, 0, false, 0 end
    IsInInstance = function() return true, "arena" end
end

function sim_enter_raid()
    GetInstanceInfo = function() return "Blackwing Lair", "raid", 3, "Normal", 40, 0, false, 0 end
    IsInInstance = function() return true, "raid" end
end

function sim_enter_world()
    GetInstanceInfo = function() return "Orgrimmar", "none", 0, "Normal", 0, 0, false, 0 end
    IsInInstance = function() return false, "none" end
end
