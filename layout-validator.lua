-- Layout assertions that run after the sim fires events.
-- Walks the frame tree and validates that everything the addon created
-- is structurally sound: valid sizes, positions, no orphaned anchors.

local LAYOUT_ERRORS = {}

local function assert_layout(cond, msg)
    if not cond then
        LAYOUT_ERRORS[#LAYOUT_ERRORS + 1] = tostring(msg)
    end
end

function sim_validate_layout()
    for i, f in ipairs(SIM_FRAMES) do
        local name = f._name or ("frame" .. i)

        -- every visible frame should have a size
        if f._shown and f._size then
            if (f._size.w or 0) <= 0 then
                assert_layout(false, name .. ": visible but width is " .. tostring(f._size.w))
            end
            if (f._size.h or 0) <= 0 then
                assert_layout(false, name .. ": visible but height is " .. tostring(f._size.h))
            end
        end

        -- every anchored frame should have at least one point
        if f._shown and (not f._points or #f._points == 0) then
            assert_layout(false, name .. ": visible but has no anchor points")
        end

        -- alpha should be in [0, 1]
        if f._alpha ~= nil and (f._alpha < 0 or f._alpha > 1) then
            assert_layout(false, name .. ": alpha is " .. tostring(f._alpha))
        end

        -- font strings: visible ones should have text
        if f._fonts then
            for j, fs in ipairs(f._fonts) do
                if fs._shown and (not fs._text or #fs._text == 0) then
                    assert_layout(false, name .. ".font" .. j .. ": shown but empty text")
                end
            end
        end

        -- off-screen check (approximate: WoW screen is roughly 1920x1080 in layout coords)
        if f._shown and f._points and #f._points > 0 then
            local p = f._points[1]
            local x = (p[4] or p[2] or 0)
            local y = (p[5] or p[3] or 0)
            if x < -2000 or x > 2000 then
                assert_layout(false, name .. ": x offset " .. x .. " is off-screen")
            end
            if y < -2000 or y > 2000 then
                assert_layout(false, name .. ": y offset " .. y .. " is off-screen")
            end
        end
    end
    return #LAYOUT_ERRORS, LAYOUT_ERRORS
end

function sim_layout_errors_json()
    local parts = {}
    for i, e in ipairs(LAYOUT_ERRORS) do
        parts[#parts + 1] = '"' .. tostring(e):gsub('"', '\\"') .. '"'
    end
    return '[' .. table.concat(parts, ',') .. ']'
end
