-------------------------------------------------------------------
-- Smoothen View
-------------------------------------------------------------------

-- You now have only a 4-direction hat: U(8), D(2), L(4), R(6).
-- Diagonals UL(7), UR(9), DR(3), DL(1) are reached by quickly switching between
-- the two adjacent cardinals within COMBO_MS (either order):
--   U + L -> UL (7)
--   U + R -> UR (9)
--   D + R -> DR (3)
--   D + L -> DL (1)
-- When a diagonal is triggered, it is frozen (input blocked) for FREEZE_MS.

-- QuickLook numbering offset:
--   QuickLook 1 == sim/view/quick_look_0

local function log_safe(msg)
    if type(logMsg) == "function" then logMsg(msg) end
end

local function ql_cmd(n)
    return string.format("sim/view/quick_look_%d", n - 1)
end

-- Direction -> your QuickLook numbers
local DIR_NUM = {
    UL = 7,
    U  = 8,
    UR = 9,
    L  = 4,
    R  = 6,
    DL = 1,
    D  = 2,
    DR = 3,
}

local function now_ms()
    return math.floor(os.clock() * 1000)
end

-- ====== COMBO + FREEZE SETTINGS ======
local COMBO_MS  = 1000
local FREEZE_MS = 500

-- ====== STATE ======
local last_dir = nil              -- last fired view dir (including diagonals)
local freeze_until_ms = 0

local last_card_dir = nil         -- last cardinal input (U/D/L/R)
local last_card_ms = 0

local function fire_quicklook(dir)
    local n = DIR_NUM[dir]
    if not n then return false end

    if type(command_once) ~= "function" then
        log_safe("[Smoothen view] ERROR: command_once() not available.")
        return false
    end

    command_once(ql_cmd(n))
    last_dir = dir
    return true
end

local function combo_to_diag(a, b)
    -- a,b are cardinals (U/D/L/R), order-independent
    if (a == "U" and b == "L") or (a == "L" and b == "U") then return "UL" end
    if (a == "U" and b == "R") or (a == "R" and b == "U") then return "UR" end
    if (a == "D" and b == "R") or (a == "R" and b == "D") then return "DR" end
    if (a == "D" and b == "L") or (a == "L" and b == "D") then return "DL" end
    return nil
end

-- BEGIN handler (press/deflection)
function smoothview_handle_dir(dir)
    local t = now_ms()

    -- Freeze: while active, ignore any attempt to change to a different view
    if freeze_until_ms > t and dir ~= last_dir then
        return
    end

    -- Mutual blocker between 2 (D) and 1 (DL) at the VIEW level
    -- (DL is only reachable via combo, but once in DL we also block going straight to D)
    if (last_dir == "D" and dir == "DL") or (last_dir == "DL" and dir == "D") then
        return
    end

    -- Only cardinals are expected from the 4-way hat.
    -- If a diagonal is somehow called directly, still honor it (but keep freeze behavior).
    if dir == "UL" or dir == "UR" or dir == "DL" or dir == "DR" then
        fire_quicklook(dir)
        freeze_until_ms = t + FREEZE_MS
        last_card_dir = nil
        last_card_ms = 0
        return
    end

    -- Combo detection: if two adjacent cardinals are toggled quickly, trigger diagonal.
    if last_card_dir ~= nil and (t - last_card_ms) <= COMBO_MS then
        local diag = combo_to_diag(last_card_dir, dir)
        if diag then
            fire_quicklook(diag)
            freeze_until_ms = t + FREEZE_MS
            last_card_dir = nil
            last_card_ms = 0
            return
        end
    end

    -- No combo: fire the cardinal view normally and arm for a possible combo.
    fire_quicklook(dir)
    last_card_dir = dir
    last_card_ms = t
end

-- END handler (release/back to center)
function smoothview_handle_end(dir)
    -- no-op
end

-- ====== COMMAND CREATION ======
if type(create_command) ~= "function" then
    log_safe("[Smoothen view] ERROR: create_command() not available. Script disabled.")
    return
end

local function mk(name, desc, dir)
    create_command(
        name,
        desc,
        string.format("smoothview_handle_dir('%s')", dir),
        "",
        string.format("smoothview_handle_end('%s')", dir)
    )
end

-- Guard against duplicate-command errors on Reload Scripts.
if not _G.__smoothview4way_cmds_created then
    -- 4-way hat commands
    -- Create BOTH namespaces so existing bindings continue to work:
    --   1) FlyWithLua/smoothview/hat_..
    --   2) smoothview/hat_..

    -- Down (2)
    mk("FlyWithLua/smoothview/hat_02", "SmoothView: D  -> QuickLook 2", "D")
    mk("FlyWithLua/smoothview/hat_2",  "SmoothView: D  -> QuickLook 2", "D")

    -- Left (4)
    mk("FlyWithLua/smoothview/hat_04", "SmoothView: L  -> QuickLook 4", "L")
    mk("FlyWithLua/smoothview/hat_4",  "SmoothView: L  -> QuickLook 4", "L")

    -- Right (6)
    mk("FlyWithLua/smoothview/hat_06", "SmoothView: R  -> QuickLook 6", "R")
    mk("FlyWithLua/smoothview/hat_6",  "SmoothView: R  -> QuickLook 6", "R")


    -- Up (8)
    mk("FlyWithLua/smoothview/hat_08", "SmoothView: U  -> QuickLook 8", "U")
    mk("FlyWithLua/smoothview/hat_8",  "SmoothView: U  -> QuickLook 8", "U")

    _G.__smoothview4way_cmds_created = true
end
