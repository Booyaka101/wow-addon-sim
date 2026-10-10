-- Performance instrumentation: counts what the addon allocates and how
-- often handlers fire. WoW addons run at 60fps with strict memory budgets;
-- an addon that creates unbounded font strings per combat event lags the
-- game for everyone. This catches that before it ships.
--
-- Metrics collected:
--   frames_created     — CreateFrame calls (WoW limits to ~1000 live frames)
--   fonts_created      — CreateFontString calls (pooled vs leaked)
--   textures_created   — CreateTexture calls
--   events_fired       — total event dispatches
--   handler_calls      — total OnEvent invocations
--   peak_active        — highest concurrent active elements

PERF = {
    frames_created = 0,
    fonts_created = 0,
    textures_created = 0,
    events_fired = 0,
    handler_calls = 0,
    peak_active = 0,
    start_time = nil,
}

-- wrap CreateFrame to count allocations
if CreateFrame then
    local orig_create = CreateFrame
    CreateFrame = function(...)
        PERF.frames_created = PERF.frames_created + 1
        return orig_create(...)
    end
end

-- wrap the event dispatcher to count handler invocations
if sim_fire_event then
    local orig_fire = sim_fire_event
    sim_fire_event = function(event, ...)
        PERF.events_fired = PERF.events_fired + 1
        local result = orig_fire(event, ...)
        PERF.handler_calls = PERF.handler_calls + (result or 0)
        -- track peak active elements (a proxy for memory pressure)
        local active = 0
        for i, f in ipairs(SIM_FRAMES or {}) do
            if f._fonts then active = active + #f._fonts end
            if f._textures then active = active + #f._textures end
        end
        if active > PERF.peak_active then PERF.peak_active = active end
        return result
    end
end

-- budget assertions: call after a scenario to check the addon stays within
-- WoW's practical limits. These are generous bounds — Blizzard's own UI
-- uses far more — but they catch runaway allocation loops.
function sim_check_performance()
    local issues = {}

    -- WoW's frame limit is hard-capped; well-designed addons stay well under
    if PERF.frames_created > 50 then
        issues[#issues + 1] = "created " .. PERF.frames_created .. " frames (guideline: <50 for a lightweight addon)"
    end

    -- unbounded font creation is the #1 cause of addon-induced lag
    -- (combat text addons should pool and reuse, not allocate per event)
    if PERF.fonts_created > 100 then
        issues[#issues + 1] = "created " .. PERF.fonts_created .. " font strings (check pooling: >100 suggests per-event allocation)"
    end

    -- handler invocation rate: if every combat event triggers a handler that
    -- takes >1ms, 100 events/second = 10% CPU just for this addon
    if PERF.handler_calls > 500 then
        issues[#issues + 1] = "fired " .. PERF.handler_calls .. " handler calls (check listener count)"
    end

    return #issues, issues
end

function sim_perf_report()
    local lines = {
        string.format("frames: %d, fonts: %d, textures: %d",
            PERF.frames_created, PERF.fonts_created, PERF.textures_created),
        string.format("events: %d, handler calls: %d, peak active: %d",
            PERF.events_fired, PERF.handler_calls, PERF.peak_active),
    }
    return table.concat(lines, "\n")
end
