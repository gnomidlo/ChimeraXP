-- Chimera AutoExp 5 / standalone plugin for official Chimera 5.x.
-- Not compatible with the legacy AutoExp XML package: disable that package.
-- Native APIs only: gmcp, mapper, walker and the chimera.* event bus.
-- A conservative, opt-in combat PATROL (no unattended loot/selling yet).
local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$")
end
local function normalized(s)
    return trim(s):lower()
end
local function bool(v)
    return v == true or v == 1 or v == "1"
end
local function pct(value, maximum)
    local a, b = tonumber(value), tonumber(maximum)
    if a and b and b > 0 then return a * 100 / b end
    return nil
end
local function valid_id(value)
    return type(value) == "string" and #value > 0
        and #value < 128 and not value:find("[%s;\r\n]")
end
local function contains(name, words)
    name = normalized(name)
    for _, pattern in ipairs(words or {}) do
        if name:find(normalized(pattern), 1, true) then return true end
    end
    return false
end
local function unique_names(raw)
    local out, seen = {}, {}
    for _, name in ipairs(type(raw) == "table" and raw or {}) do
        name = trim(name)
        if name ~= "" and not seen[normalized(name)] then
            seen[normalized(name)] = true
            out[#out + 1] = name
        end
    end
    return out
end
local function rooms_from(raw)
    local out, seen = {}, {}
    for _, room in ipairs(type(raw) == "table" and raw or {}) do
        local id = type(room) == "table" and room.id or room
        if valid_id(id) and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end
local DEFAULT = { retreatHP = 35, returnHP = 85, maxEnemies = 3,
    minRoomRevisit = 60, attackWait = 3, syncWait = 4, recoveryPoll = 3, lootGrace = 7,
    escapeWait = 4, escapeMaxTries = 3,
    safeMoveWait = 3, safeMoveTries = 2, emergencyFallbackSteps = 40,
    economyLoadThreshold = 75, economyCommandDelay = 0.7,
    economyLootGrace = 2, economyWeightWait = 0.7 }
local function normalize_profile(src, name)
    local old = type(src) == "table" and src or {}
    local rules = type(old.rules) == "table" and old.rules or {}
    local p = {
        name = trim(name or old.name), route = rooms_from(old.route),
        targets = unique_names(old.targets), avoid = unique_names(old.avoid),
        loot = unique_names(old.loot),
        economy = { enabled = type(old.economy) == "table" and bool(old.economy.enabled) },
        safeRoom = valid_id(old.safeRoom) and old.safeRoom or nil,
        rules = {},
    }
    for key, default in pairs(DEFAULT) do
        p.rules[key] = tonumber(rules[key]) or default
    end
    return p
end
local function import_old_profiles(old)
    local areas = {}
    for key, profile in pairs(type(old.areas) == "table" and old.areas or {}) do
        if type(profile) == "table" then
            local p = normalize_profile(profile, profile.name or key)
            if p.name ~= "" then areas[normalized(p.name)] = p end
        end
    end
    return areas
end

return {
    name = "autoexp",
    version = "0.5.0-beta.19",
    title = "ChimeraXP / AutoExp 5",
    section = "automatyzacja",
    description = "Ostrozny patrol PvE oparty na oficjalnym mapperze i GMCP",
    deps = { "gmcp", "mapper", "walker", "locations" },
    setup = function(ctx)
        local gmcp_api = ctx:use("gmcp")
        local mapper = ctx:use("mapper")
        local walker = ctx:use("walker")
        -- The official loader grants ctx:use() only to declared deps.
        -- Chimera's built-in /room uses this same locations service.
        local locations = ctx:use("locations")
        local state = ctx.state
        local areas = ctx:saved("profiles", {})
        if type(areas) ~= "table" then areas = {} end
        local selected = ctx:saved("selected", nil)
        local started, paused, dry = false, false, false
        local phase = "OFF"
        local mapping = nil
        local move = nil -- { id, map, purpose }
        local pending_attack = nil -- { id, room, since }
        local attacked_in_room = {}
        local last_seen = {} -- room ID -> time at which room was checked and empty
        -- NPCs move. We never put a room on a time-based navigation blacklist.
        -- Count directions taken from unsuitable rooms in this patrol only,
        -- to avoid choosing the same dead-end exit again when alternatives exist.
        local skip_exit_history = {} -- room ID -> { command = count }
        -- Session-only hazardous escape episode: do not blacklist rooms.
        local hazard_chain = nil -- hazards, steps, safe_rooms, safe_count
        local engaged_here = false -- our party has already engaged this room
        -- Remember real, GMCP-confirmed routes even when Mudlet's mapped
        -- getPath() is unavailable or returns a path through an avoided room.
        -- This is session state only; the history is NOT guessed from exits.
        local known_exits = state.emergency_known_exits or {}
        local trail = state.emergency_trail or {}
        state.emergency_known_exits, state.emergency_trail = known_exits, trail
        local function record_room(r)
            if type(r) ~= "table" or not valid_id(r.id) then return end
            if type(r.exits) == "table" then
                local links = {}
                for direction, id in pairs(r.exits) do
                    if valid_id(direction) and valid_id(id) then links[direction] = id end
                end
                known_exits[r.id] = links
            end
            if trail[#trail] == r.id then return end
            if #trail >= 2 and trail[#trail - 1] == r.id then
                table.remove(trail)  -- confirmed backtrack, do not bounce back
            else
                trail[#trail + 1] = r.id
                if #trail > 160 then table.remove(trail, 1) end
            end
        end
        local escape = nil -- { origin, sent_at, tries, tried = { cmd = true } }
        local emergency = nil -- { step = {origin, destination, command, sent_at}, tries, destination }
        local last_visited = nil
        local entities_ready = false
        local observed_room = nil
        local post_combat_at = nil
        local last_reason = ""
        local pending = nil
        local stop_ours = false
        local last_group = nil
        local external_walk = false
        local evaluate
        -- Economy mode is opt-in. Session callbacks are explicitly cancellable.
        local economy_run, economy_timer, process_economy, begin_economy
        local loot_run, loot_timer = nil, nil
        local function cancel_economy_timers()
            if economy_timer then ctx:cancel(economy_timer); economy_timer=nil end
            if loot_timer then ctx:cancel(loot_timer); loot_timer=nil end
        end

        local function note(message, level)
            local fn = level == "warn" and ctx.log.warn or ctx.log.info
            fn(tostring(message))
        end
        local function announce(label)
            if phase ~= label then
                phase = label
                if started then note("AutoExp: " .. phase) end
            end
        end
        local function remember()
            ctx:save("profiles", areas)
            ctx:save("selected", selected)
        end
        local function allowed_config()
            if started and not paused then
                note("Wstrzymaj lub zatrzymaj /exp przed zmiana konfiguracji.", "warn")
                return false
            end
            return true
        end
        local function profile()
            return selected and areas[selected] or nil
        end
        -- The trade commands have no reliable success messages yet; serialize
        -- them with a short adjustable delay, never as one multi-command send.
        local function economy_command_delay()
            local p = profile()
            local value = tonumber(p and p.rules and p.rules.economyCommandDelay)
            return math.max(0.3, math.min(value or DEFAULT.economyCommandDelay, 3))
        end
        -- Chimera omits encumbrance when the character carries no load.
        -- Missing FIELD is 0; missing whole Vitals packet or malformed
        -- PRESENT field is a different issue and must not silently mean 0.
        local function economy_encumbrance(vitals)
            if type(vitals) ~= "table" then return nil end
            if vitals.encumbrance == nil then return 0 end
            return tonumber(vitals.encumbrance)
        end
        local function room()
            return gmcp_api.room()
        end
        local function room_id()
            local r = room()
            return r and r.id or nil
        end
        local function ready_entities()
            local packet = gmcp_api.entities()
            local here = room_id()
            return entities_ready and type(packet) == "table" and packet.room == here
                and type(packet.entities) == "table"
        end
        local function me_and_group()
            local members = (gmcp_api.group() or {}).members
            if type(members) ~= "table" then return nil, nil end
            local ids, me = {}, nil
            for _, m in ipairs(members) do
                if m.id ~= nil then ids[tostring(m.id)] = true end
                if bool(m.self) then me = m end
            end
            return me, ids
        end
        local function health()
            local vitals = gmcp_api.vitals() or {}
            local hp = tonumber(vitals.hp)
            local me, group_ids = me_and_group()
            if hp == nil and me then hp = pct(me.hp, me.maxhp) end
            local lowest = nil
            local group = gmcp_api.group() or {}
            local members = type(group.members) == "table" and group.members or {}
            for _, m in ipairs(members) do
                if not bool(m.self) and bool(m.here) then
                    local value = pct(m.hp, m.maxhp)
                    if value and (not lowest or value < lowest.hp) then
                        lowest = { hp = value, name = m.name or tostring(m.id) }
                    end
                end
            end
            return hp, lowest, group_ids, me
        end
        local function combat_status(group_ids)
            local combat = gmcp_api.combat()
            if type(combat) ~= "table" then return nil, false end
            local active = bool(combat.self_active)
            local foreign = false
            local by_id = {}
            local packet = gmcp_api.entities()
            if ready_entities() then
                for _, e in ipairs(packet.entities) do
                    if e.id then by_id[tostring(e.id)] = e end
                end
            end
            for _, rel in ipairs(type(combat.relations) == "table" and combat.relations or {}) do
                local a, b = tostring(rel.attacker), tostring(rel.defender)
                if group_ids and (group_ids[a] or group_ids[b]) then
                    active = true
                else
                    local ae, be = by_id[a], by_id[b]
                    if ae and be and (
                        (ae.kind == "player" and be.kind == "npc") or
                        (ae.kind == "npc" and be.kind == "player")) then
                        foreign = true
                    end
                end
            end
            return active, foreign
        end
        local function target_info(p, group_ids)
            if not ready_entities() then return nil, nil end
            local entities = gmcp_api.entities().entities
            local found, count = nil, 0
            for _, e in ipairs(entities) do
                local id = e.id and tostring(e.id) or nil
                local friendly = bool(e.self) or e.relation == "self"
                    or e.relation == "group" or e.relation == "ally"
                    or e.group_role == "leader" or e.group_role == "member"
                    or (id and group_ids and group_ids[id])
                -- Limit counts only configured EXP targets, not harmless
                -- wildlife or unrelated NPCs in the same room. An avoided
                -- NPC triggers its own escape rule in avoided_npc().
                if e.kind == "npc" and not friendly and not bool(e.dead)
                    and contains(e.name, p.targets)
                    and not contains(e.name, p.avoid) then
                    count = count + 1
                    if not found and id and valid_id(id)
                        and not attacked_in_room[id] then
                        found = e
                    end
                end
            end
            return found, count
        end
        -- NPCs on the NEXT room are not known from GMCP. On spotting an
        -- avoided NPC in our current room, leave immediately without issuing
        -- a combat command. During combat the native walker auto-stops, so
        -- this escape uses a single direct room exit (GMCP), not walker.go().
        local function avoided_npc(p, group_ids)
            if not ready_entities() then return nil end
            for _, e in ipairs(gmcp_api.entities().entities) do
                local id = e.id and tostring(e.id) or nil
                local friendly = bool(e.self) or e.relation == "self"
                    or e.relation == "group" or e.relation == "ally"
                    or (id and group_ids and group_ids[id])
                if e.kind == "npc" and not friendly and not bool(e.dead)
                    and contains(e.name, p.avoid) then
                    return tostring(e.name or e.id or "NPC")
                end
            end
            return nil
        end
        -- Commands used by Chimera.Room.Info.exits; other named exits
        -- ("wrota", "wejscie", etc.) are sent unchanged.
        local EXIT_COMMANDS = {
            polnoc = "n", poludnie = "s", wschod = "e", zachod = "w",
            ["polnocny-wschod"] = "ne", ["polnocny-zachod"] = "nw",
            ["poludniowy-wschod"] = "se", ["poludniowy-zachod"] = "sw",
            gora = "u", dol = "d", up = "u", down = "d",
        }
        -- Numpad emits chimera.step.manual for any directional send,
        -- including our ctx:send; ownership lasts only during that call.
        local owned_direction = nil
        local expected_manual = nil -- one pending numpad echo of our own step
        local function send_owned_direction(command)
            local direction = EXIT_COMMANDS[command] or command
            -- A "chimera.step.manual" callback may follow ctx:send() instead
            -- of happening inside it. Keep ONE matching expected event while
            -- still in the source room (max two seconds).
            expected_manual = {
                direction = direction, room = room_id(), time = os.time(), consumed = false,
            }
            local previous = owned_direction
            owned_direction = direction
            local ok, err = pcall(ctx.send, ctx, command)
            owned_direction = previous
            if not ok then expected_manual = nil end
            return ok, err
        end
        local function known_step_toward(r, target)
            -- BFS through exits observed in previously visited rooms. Unlike
            -- the Mudlet map, this needs no saved mapper rooms/coordinates.
            if not valid_id(target) or r.id == target then return nil end
            local queue_ids = { r.id }
            local head, seen = 1, { [r.id] = true }
            local first = {}
            while head <= #queue_ids and head <= 600 do
                local id = queue_ids[head]
                head = head + 1
                local links = (id == r.id and r.exits) or known_exits[id]
                if type(links) == "table" then
                    local options = {}
                    for direction, dest in pairs(links) do
                        local command = EXIT_COMMANDS[direction]
                        if command and valid_id(dest) and not seen[dest] then
                            options[#options + 1] = { command = command, id = dest }
                        end
                    end
                    table.sort(options, function(a, b)
                        if a.id == b.id then return a.command < b.command end
                        return a.id < b.id
                    end)
                    for _, link in ipairs(options) do
                        seen[link.id] = true
                        first[link.id] = id == r.id and link or first[id]
                        if link.id == target then
                            local result = first[link.id]
                            return result.command, result.id
                        end
                        queue_ids[#queue_ids + 1] = link.id
                    end
                end
            end
            return nil
        end
        local function emergency_step(p, r)
            -- Priority 1: direct GMCP way to the saved safe room. No map needed.
            local direct, dest = known_step_toward(r, p.safeRoom)
            if direct then return direct, dest, "GMCP" end

            -- Priority 2: Mudlet getPath. Some clients have only a partial
            -- mapper graph, or mapper.current_room() updates after Room.Info.
            local from = type(getRoomIDbyHash) == "function" and getRoomIDbyHash(r.id)
                or mapper.current_room()
            if type(from) ~= "number" or from <= 0 then from = mapper.current_room() end
            local safe = type(getRoomIDbyHash) == "function" and getRoomIDbyHash(p.safeRoom) or nil
            if from and safe and safe > 0 and type(getPath) == "function" then
                local ok, found = pcall(getPath, from, safe)
                if ok and found then
                    local path = type(speedWalkPath) == "table" and speedWalkPath or {}
                    local next_id = type(getRoomHashByID) == "function"
                        and getRoomHashByID(path[1]) or nil
                    if valid_id(next_id) then
                        for direction, hash in pairs(type(r.exits) == "table" and r.exits or {}) do
                            local command = EXIT_COMMANDS[direction]
                            if command and hash == next_id then return command, hash, "mapper" end
                        end
                    end
                end
            end

            -- Priority 3: retrace confirmed rooms, not a guessed route.
            -- Two last trail rooms: [..., previous, current].
            if trail[#trail] == r.id and #trail >= 2 then
                local previous = trail[#trail - 1]
                for direction, hash in pairs(type(r.exits) == "table" and r.exits or {}) do
                    local command = EXIT_COMMANDS[direction]
                    if command and hash == previous then return command, hash, "cofanie" end
                end
            end

            -- Priority 4: when neither safe route nor breadcrumb exists, an
            -- actual GMCP exit is safer than standing still in lethal combat.
            -- Avoid known dangerous rooms and loops; never invent an exit.
            local options = {}
            for direction, id in pairs(type(r.exits) == "table" and r.exits or {}) do
                local command = EXIT_COMMANDS[direction]
                if command and valid_id(id) then
                    local n = emergency and emergency.visits[id] or 0
                    options[#options + 1] = {command=command, id=id, visits=n or 0}
                end
            end
            table.sort(options, function(a,b)
                if a.visits ~= b.visits then return a.visits < b.visits end
                if a.id ~= b.id then return a.id < b.id end
                return a.command < b.command
            end)
            if #options > 0 then return options[1].command, options[1].id, "wyjscie GMCP" end
            return nil
        end
        local function has_new_way_after_backtrack(destination, origin)
            -- Returning to an observed hostile room is only worthwhile if
            -- it has an exit besides our current room that was never tried.
            local links = known_exits[destination]
            if type(links) ~= "table" then return false end
            local used = skip_exit_history[destination] or {}
            for direction, id in pairs(links) do
                local command = EXIT_COMMANDS[direction] or direction
                if valid_id(id) and valid_id(command) and id ~= origin
                    and (used[command] or 0) == 0 then
                    return true
                end
            end
            return false
        end
        local function escape_exit(p, r, tried)
            local exits = type(r.exits) == "table" and r.exits or {}
            local options, attempts = {}, skip_exit_history[r.id] or {}
            local position = 0
            for i, hash in ipairs(p.route) do
                if hash == r.id then position = i; break end
            end
            -- An avoided/crowded room is a transit-only room, not a blocked
            -- room. Prefer an exit we have not yet tried from this particular
            -- unsuitable room, then a direction further along patrol.
            local priority = {}
            for step = 1, #p.route do
                local index = ((position + step - 1) % #p.route) + 1
                local hash = p.route[index]
                if hash ~= r.id and priority[hash] == nil then priority[hash] = step end
            end
            for exit, hash in pairs(exits) do
                local command = EXIT_COMMANDS[exit] or exit
                if valid_id(hash) and valid_id(command) and not tried[command] then
                    local previous_hazard = hazard_chain and hazard_chain.hazards[hash] or 0
                    -- Do not bounce into a hazardous room unless we know
                    -- an untried onward route out of that room.
                    if previous_hazard == 0 or
                        has_new_way_after_backtrack(hash, r.id) then
                        options[#options + 1] = {
                            command = command, id = hash,
                            rank = priority[hash] or 1000,
                            visits = attempts[command] or 0,
                            hazard_visits = previous_hazard,
                        }
                    end
                end
            end
            table.sort(options, function(a, b)
                if a.hazard_visits ~= b.hazard_visits then
                    return a.hazard_visits < b.hazard_visits
                end
                if a.visits ~= b.visits then return a.visits < b.visits end
                if a.rank ~= b.rank then return a.rank < b.rank end
                return a.command < b.command
            end)
            if #options == 0 then return nil end
            if options[1].rank < 1000 or options[1].visits > 0
                or options[1].hazard_visits > 0 then
                return options[1].command
            end
            -- Prefer a mapped route ahead if it also has the least number of
            -- unsuccessful traversals. No room is excluded because of NPCs.
            local from = mapper.current_room()
            if from and type(getPath) == "function" then
                for step = 1, #p.route do
                    local index = ((position + step - 1) % #p.route) + 1
                    local hash = p.route[index]
                    local dest = type(getRoomIDbyHash) == "function" and getRoomIDbyHash(hash) or nil
                    if dest and dest > 0 and dest ~= from then
                        local ok, found = pcall(getPath, from, dest)
                        if ok and found then
                            local path = type(speedWalkPath) == "table" and speedWalkPath or {}
                            local next_hash = type(getRoomHashByID) == "function"
                                and getRoomHashByID(path[1]) or nil
                            for _, option in ipairs(options) do
                                if option.id == next_hash
                                    and option.visits == options[1].visits
                                    and option.hazard_visits == options[1].hazard_visits then
                                    return option.command
                                end
                            end
                        end
                    end
                end
            end
            return options[1].command
        end
        local function queue(delay)
            if not started or paused or pending then return end
            pending = ctx:timer(delay or 0, function()
                pending = nil
                if started and not paused then evaluate() end
            end)
        end
        local function halt(reason)
            expected_manual = nil
            if pending then ctx:cancel(pending); pending = nil end
            cancel_economy_timers()
            economy_run, loot_run = nil, nil
            started, paused, dry = false, false, false
            hazard_chain, engaged_here = nil, false
            phase, pending_attack, move, escape, emergency = "OFF", nil, nil, nil, nil
            post_combat_at = nil
            last_reason = reason or "Zatrzymano"
            if stop_ours == false and state.owns_walk then
                stop_ours = true
                walker.stop("AutoExp: stop")
                stop_ours = false
            end
            state.owns_walk = false
            note("AutoExp: " .. last_reason)
        end
        local function pause(reason)
            if not started or paused then return end
            expected_manual = nil
            paused = true
            phase = "PAUSED"
            last_reason = reason
            if pending then ctx:cancel(pending); pending = nil end
            cancel_economy_timers()
            economy_run, loot_run = nil, nil
            if state.owns_walk then
                stop_ours = true
                walker.stop("AutoExp: pauza")
                stop_ours = false
            end
            state.owns_walk = false
            move, pending_attack, escape, emergency = nil, nil, nil, nil
            note("AutoExp WSTRZYMANY: " .. reason, "warn")
        end
        -- Room.Entities does not reliably contain corpses. Ask the MUD to
        -- count them after combat, then loot each ordinal corpse exactly once.
        -- The server uses Polish genitive number phrases in its response.
        local CORPSE_COUNTS = {
            [1] = "jednej sztuki", [2] = "dwoch sztuk",
            [3] = "trzech sztuk", [4] = "czterech sztuk",
            [5] = "pieciu sztuk", [6] = "szesciu sztuk",
            [7] = "siedmiu sztuk", [8] = "osmiu sztuk",
            [9] = "dziewieciu sztuk", [10] = "dziesieciu sztuk",
            [11] = "jedenastu sztuk", [12] = "dwunastu sztuk",
            [13] = "trzynastu sztuk", [14] = "czternastu sztuk",
            [15] = "pietnastu sztuk", [16] = "szesnastu sztuk",
            [17] = "siedemnastu sztuk", [18] = "osiemnastu sztuk",
            [19] = "dziewietnastu sztuk", [20] = "dwudziestu sztuk",
            [21] = "dwudziestu jednej sztuki", [22] = "dwudziestu dwoch sztuk",
            [23] = "dwudziestu trzech sztuk", [24] = "dwudziestu czterech sztuk",
            [25] = "dwudziestu pieciu sztuk", [26] = "dwudziestu szesciu sztuk",
            [27] = "dwudziestu siedmiu sztuk", [28] = "dwudziestu osmiu sztuk",
            [29] = "dwudziestu dziewieciu sztuk", [30] = "trzydziestu sztuk",
        }
        local function next_counted_loot(run)
            loot_timer = nil
            if loot_run ~= run or not started or paused then return end
            if room_id() ~= run.origin then
                pause("Lupy: pokoj zmienil sie podczas zbierania z cial")
                return
            end
            if run.phase ~= "TAKING" then return end
            if run.corpse > run.count then
                loot_run = nil
                note("AutoExp LUP: obsluzono " .. run.count .. " cial.")
                local p = profile()
                queue(tonumber(p and p.rules.economyWeightWait)
                    or DEFAULT.economyWeightWait)
                return
            end
            local item = run.list[run.item]
            local command = "wez " .. item .. " z " .. run.corpse .. ". ciala"
            run.item = run.item + 1
            if run.item > #run.list then
                run.item = 1
                run.corpse = run.corpse + 1
            end
            note("AutoExp LUP: " .. command)
            local ok, err = pcall(ctx.send, ctx, command)
            if not ok then
                pause("Lupy: blad wysylania: " .. tostring(err))
                return
            end
            loot_timer = ctx:timer(economy_command_delay(), function()
                next_counted_loot(run)
            end)
        end
        local function counted_corpses(count)
            local run = loot_run
            if not run or run.phase ~= "COUNTING" or not started or paused
                or room_id() ~= run.origin then return end
            if loot_timer then ctx:cancel(loot_timer); loot_timer = nil end
            run.count, run.corpse, run.item, run.phase = count, 1, 1, "TAKING"
            note("AutoExp LUP: policzono " .. count .. " cial.")
            next_counted_loot(run)
        end
        for count, words in pairs(CORPSE_COUNTS) do
            local n = count
            ctx:trigger("^Doliczyl(?:as|es) sie " .. words .. [[\.$]],
                function() counted_corpses(n) end)
        end
        -- Some builds print a numerical rather than a written count.
        for count = 1, 30 do
            local n = count
            local noun = count == 1 and "sztuki" or "sztuk"
            ctx:trigger("^Doliczyl(?:as|es) sie " .. count .. " " .. noun .. [[\.$]],
                function() counted_corpses(n) end)
        end
        ctx:trigger([[^Nie doliczyl(?:as|es) sie (?:ani jednej|zadnej) sztuki\.$]],
            function() counted_corpses(0) end)
        local function begin_counted_loot(p, r)
            local run = {origin=r.id, list=p.loot, phase="COUNTING"}
            loot_run = run
            announce("COUNT_CORPSES")
            loot_timer = ctx:timer(5, function()
                loot_timer = nil
                if loot_run == run and run.phase == "COUNTING" then
                    pause("Lupy: brak potwierdzenia 'policz ciala' po 5 s. Sprawdz odpowiedz serwera.")
                end
            end)
            note("AutoExp LUP: policz ciala")
            local ok, err = pcall(ctx.send, ctx, "policz ciala")
            if not ok then
                pause("Lupy: nie udalo sie policzyc cial: " .. tostring(err))
            end
        end
        local function move_to(id, purpose)
            local current = mapper.current_room()
            local destination = type(getRoomIDbyHash) == "function" and getRoomIDbyHash(id) or nil
            if not current or not destination or destination <= 0 then
                pause("Brak lokacji na mapie: " .. tostring(id))
                return false
            end
            if current == destination then return true end
            if state.owns_walk then return false end
            move = { id = id, map = destination, purpose = purpose }
            state.owns_walk = true -- BEFORE go: native walker emits synchronously
            announce(purpose == "safe" and "RETREAT" or "MOVING")
            local ok, reason = walker.go(destination)
            if not ok then
                move, state.owns_walk = nil, false
                pause("Chodzik odmowil ruchu: " .. tostring(reason))
                return false
            end
            if ok == "tutaj" then
                move, state.owns_walk = nil, false
                queue(0)
            end
            return true
        end
        local function escape_avoided(p, r, name)
            local now = os.time()
            if not escape or escape.origin ~= r.id then
                if not hazard_chain then
                    hazard_chain = {hazards = {}, steps = 0, safe_rooms = {}, safe_count = 0}
                end
                hazard_chain.hazards[r.id] = (hazard_chain.hazards[r.id] or 0) + 1
                if hazard_chain.hazards[r.id] > 2 or hazard_chain.steps >= 8 then
                    pause("ALARM: petla miedzy niebezpiecznymi lokacjami. Zatrzymano ruch, aby nie wyczerpac sil!")
                    return
                end
                escape = { origin = r.id, tried = {}, tries = 0 }
                pending_attack, post_combat_at = nil, nil
                note("AutoExp: niebezpieczna lokacja (" .. name .. ") - opuszczam!", "warn")
            end
            if state.owns_walk then
                stop_ours = true
                walker.stop("AutoExp: wyjscie z lokacji z omijanym NPC")
                stop_ours = false
                state.owns_walk, move = false, nil
            end
            if escape.sent_at and now - escape.sent_at <
                (tonumber(p.rules.escapeWait) or DEFAULT.escapeWait) then
                announce("AVOID_ESCAPE")
                return
            end
            if escape.tries >= (tonumber(p.rules.escapeMaxTries) or DEFAULT.escapeMaxTries) then
                pause("Nie udalo sie opuscic lokacji z omijanym NPC: " .. name)
                return
            end
            local command = escape_exit(p, r, escape.tried)
            if not command then
                pause("ALARM: wszystkie wyjscia prowadza do petli przez niebezpieczne pokoje (" .. name .. "). Przejmij sterowanie!")
                return
            end
            if dry then
                note("AutoExp TEST: omijam " .. name .. " -> " .. command)
                pause("Zakonczono test - zadnej komendy nie wyslano")
                return
            end
            escape.tries = escape.tries + 1
            if hazard_chain then hazard_chain.steps = hazard_chain.steps + 1 end
            local history = skip_exit_history[r.id] or {}
            history[command] = (history[command] or 0) + 1
            skip_exit_history[r.id] = history
            if history[command] > 2 and (history[command] % 3) == 0 then
                note("AutoExp: ponowny przejazd przez nieodpowiednia lokacje; sprawdz trase patrolu.", "warn")
            end
            escape.tried[command] = true
            escape.sent_at = now
            announce("AVOID_ESCAPE")
            local ok, err = send_owned_direction(command)
            if not ok then pause("Blad wyslania kroku omijania NPC: " .. tostring(err)) end
        end
        -- Emergency retreat: the official walker deliberately stops on combat.
        -- Issue ONE mapped direction at a time and await Room.Info confirmation.
        -- This cannot overcome a server-side ban on fleeing from combat.
        local function retreat_in_combat(p, r)
            if not valid_id(p.safeRoom) then
                pause("Niskie HP w walce, ale nie zapisano bezpiecznej lokacji (/exp bezpieczna)!")
                return
            end
            if r.id == p.safeRoom then
                emergency = nil
                announce("RECOVERY")
                return
            end
            if state.owns_walk then
                stop_ours = true
                walker.stop("AutoExp: awaryjny odwrot w walce")
                stop_ours = false
                state.owns_walk, move = false, nil
            end
            local now = os.time()
            if not emergency then
                emergency = { destination = p.safeRoom, tries = 0, steps = 0,
                    fallback_steps = 0, visits = { [r.id] = 1 }, warned_fallback = false }
                pending_attack, post_combat_at, escape = nil, nil, nil
                note("AutoExp: ALARM HP! Awaryjny odwrot do bezpiecznej lokacji, krok po kroku.", "warn")
            end
            if emergency.step and emergency.step.origin == r.id then
                if now - emergency.step.sent_at <
                    (tonumber(p.rules.safeMoveWait) or DEFAULT.safeMoveWait) then
                    announce("EMERGENCY_RETREAT")
                    return
                end
                if emergency.tries >=
                    (tonumber(p.rules.safeMoveTries) or DEFAULT.safeMoveTries) then
                    pause("ALARM: serwer nie potwierdzil ruchu w walce! Przejmij sterowanie natychmiast.")
                    return
                end
                -- Retry the same mapped exit; switching destinations while
                -- the previous movement may be delayed is too risky.
                emergency.tries = emergency.tries + 1
                emergency.step.sent_at = now
                note("AutoExp: ruch niepotwierdzony; powtarzam wyjscie do bezpiecznej lokacji ("
                     .. emergency.tries .. "/" .. p.rules.safeMoveTries .. ").", "warn")
                announce("EMERGENCY_RETREAT")
                local ok, err = send_owned_direction(emergency.step.command)
                if not ok then pause("Blad powtorzenia kroku awaryjnego: " .. tostring(err)) end
                return
            end
            -- A new room is now confirmed. Plan just the next step, not a
            -- multi-command speedwalk that might race against GMCP combat.
            emergency.step, emergency.tries = nil, 0
            local command, next_id, source = emergency_step(p, r)
            if not command then
                pause("ALARM: brak potwierdzonego, dostepnego wyjscia GMCP podczas odwrotu! Przejmij sterowanie!")
                return
            end
            if source ~= "GMCP" and source ~= "mapper" then
                if emergency.fallback_steps >= (tonumber(p.rules.emergencyFallbackSteps)
                    or DEFAULT.emergencyFallbackSteps) then
                    pause("ALARM: przekroczono limit szukania schronienia bez znanej trasy. Przejmij sterowanie!")
                    return
                end
                emergency.fallback_steps = emergency.fallback_steps + 1
                if not emergency.warned_fallback then
                    emergency.warned_fallback = true
                    note("AutoExp ALARM: brak drogi do schronienia; cofanie/wyjscie awaryjne (" .. source .. ").", "warn")
                end
            else
                emergency.fallback_steps = 0 -- known route; do not cap long safe routes
            end
            if dry then
                note("AutoExp TEST: awaryjny odwrot w walce -> " .. command)
                pause("Zakonczono test - zadnej komendy nie wyslano")
                return
            end
            emergency.step = { origin = r.id, destination = next_id,
                command = command, sent_at = now }
            emergency.tries = 1
            emergency.steps = emergency.steps + 1
            announce("EMERGENCY_RETREAT")
            local ok, err = send_owned_direction(command)
            if not ok then pause("Blad wyslania kroku awaryjnego: " .. tostring(err)) end
        end
        local function select_next(p, current)
            local route, now = p.route, os.time()
            local position = 0
            for i, id in ipairs(route) do
                if id == current then position = i; break end
            end
            -- Cykl stabilny: nie przeliczamy 200 tras przy kazdym GMCP.
            local minimum_wait = nil
            for step = 1, #route do
                local idx = ((position + step - 1) % #route) + 1
                local id = route[idx]
                local revisit = last_seen[id] and (last_seen[id] + p.rules.minRoomRevisit) or 0
                local eligible_at = revisit
                if now >= eligible_at then
                    if id ~= current then
                        local dest = getRoomIDbyHash(id)
                        local from = mapper.current_room()
                        if from and dest and dest > 0 and getPath(from, dest) then
                            return id
                        end
                    else
                        -- A one-room or otherwise exhausted route should
                        -- wait for respawn instead of stopping permanently.
                        minimum_wait = minimum_wait or p.rules.minRoomRevisit
                    end
                else
                    local remaining = math.max(1, eligible_at - now)
                    if not minimum_wait or remaining < minimum_wait then minimum_wait = remaining end
                end
            end
            return nil, minimum_wait
        end
        local function maybe_record(room_info)
            if not mapping or not room_info or not valid_id(room_info.id) then return end
            if not mapping.seen[room_info.id] then
                mapping.seen[room_info.id] = true
                mapping.route[#mapping.route + 1] = room_info.id
            end
        end
        evaluate = function()
            local p = profile()
            local r = room()
            if not p or not r or not valid_id(r.id) then
                pause("Brak profilu lub lokacji GMCP")
                return
            end
            -- Guard against triggering on stale room/Entities after a fast move.
            if observed_room ~= r.id then
                observed_room, entities_ready = r.id, false
                attacked_in_room = {}
                last_visited = os.time()
            end
            local hp, weakest, group_ids = health()
            if not hp then
                announce("WAIT_HP"); return
            end
            local danger = hp <= p.rules.retreatHP or
                (weakest and weakest.hp <= p.rules.retreatHP)
            local active, foreign = combat_status(group_ids)
            if active then engaged_here = true end
            -- When low HP forces retreat while in combat, safety takes
            -- precedence over ordinary avoided-NPC routing and attacking.
            if emergency or (danger and active) then
                retreat_in_combat(p, r)
                return
            end
            -- A commercial trip owns its destination across incidental fights.
            -- The native walker stops on attack, so resume via confirmed
            -- GMCP single steps until ordinary walking becomes possible.
            -- Critical HP still takes priority above this branch.
            if economy_run then
                if danger then
                    pause("Niskie HP w czasie kursu handlowego. Przejmij sterowanie!")
                    return
                end
                process_economy(r, active)
                return
            end
            -- Apply avoid even if already attacked; the game may have started
            -- combat before Room.Entities arrived. Never call zabij here.
            local forbidden = avoided_npc(p, group_ids)
            if forbidden then
                escape_avoided(p, r, forbidden)
                return
            end
            if escape and escape.origin == r.id and escape.sent_at
                and os.time() - escape.sent_at <
                    (tonumber(p.rules.escapeWait) or DEFAULT.escapeWait) then
                -- Movement was sent; await room change before resuming patrol.
                announce("AVOID_ESCAPE")
                return
            end
            if escape and escape.origin == r.id then escape = nil end
            if active == nil then announce("WAIT_COMBAT"); return end
            if danger then
                if active then
                    retreat_in_combat(p, r)
                    return
                end
                if r.id ~= p.safeRoom then
                    if dry then
                        note("AutoExp TEST: odwrot -> " .. tostring(p.safeRoom))
                        pause("Zakonczono test - zadnej komendy nie wyslano")
                        return
                    end
                    -- A running retreat is already heading to safety.
                    -- Do not stop/restart it on every vitals/timer callback.
                    if state.owns_walk and move and move.purpose == "safe" then
                        announce("RETREAT")
                        return
                    end
                    if state.owns_walk then
                        stop_ours = true
                        walker.stop("AutoExp: odwrot")
                        stop_ours = false
                        state.owns_walk = false
                        move = nil
                    end
                    move_to(p.safeRoom, "safe")
                    return
                end
                announce("RECOVERY"); return
            end
            if loot_run then
                announce("LOOTING")
                return
            end
            if not ready_entities() then
                announce("WAIT_ENTITIES")
                if observed_room and last_visited
                    and os.time() - last_visited > p.rules.syncWait then
                    pause("Brak aktualnego Chimera.Room.Entities dla tej lokacji")
                end
                return
            end
            local target, npc_count = target_info(p, group_ids)
            local skip_reason = nil
            if npc_count > p.rules.maxEnemies then
                skip_reason = "zbyt wiele celow EXP (" .. npc_count .. "/" ..
                    p.rules.maxEnemies .. ")"
            elseif foreign and not active and not engaged_here
                and not (pending_attack and pending_attack.room == r.id) then
                -- Leave only foreign fights met on arrival. A later outsider
                -- joining our ongoing combat must never trigger an escape.
                skip_reason = "obcy gracz walczy z NPC"
            end
            if skip_reason then
                escape_avoided(p, r, skip_reason)
                return
            end
            -- A fresh GMCP observation of acceptable room contents clears
            -- the local direction history immediately (no time-based lock).
            skip_exit_history[r.id] = nil
            if hazard_chain and not hazard_chain.safe_rooms[r.id] then
                hazard_chain.safe_rooms[r.id] = true
                hazard_chain.safe_count = hazard_chain.safe_count + 1
                if hazard_chain.safe_count >= 2 then
                    hazard_chain, skip_exit_history = nil, {}
                end
            end
            if active then
                pending_attack = nil
                post_combat_at = nil
                announce("COMBAT")
                return
            end
            if phase == "COMBAT" then
                post_combat_at = os.time()
                announce("POST_COMBAT")
            end
            if post_combat_at then
                -- Keep the existing seven-second grace for combat-only mode.
                -- Economy mode can safely start its OWN sequential loot a bit
                -- earlier, but still waits for the game to settle after a kill.
                local grace = p.economy and p.economy.enabled and not dry
                    and (tonumber(p.rules.economyLootGrace) or DEFAULT.economyLootGrace)
                    or (tonumber(p.rules.lootGrace) or DEFAULT.lootGrace)
                if os.time() - post_combat_at < grace then return end
                post_combat_at = nil
                if p.economy and p.economy.enabled and type(p.loot) == "table"
                    and #p.loot > 0 and not dry then
                    -- Count physical corpses first, since a group may leave
                    -- several and Room.Entities does not expose their IDs.
                    begin_counted_loot(p, r)
                    return
                end
            end
            if state.owns_walk then return end
            if p.economy and p.economy.enabled and not dry then
                local burden=economy_encumbrance(gmcp_api.vitals())
                if burden == nil then
                    pause("Zarobek: brak poprawnych danych Char.Vitals w GMCP")
                    return
                end
                if burden > (tonumber(p.rules.economyLoadThreshold) or 75) then
                    begin_economy(false)
                    return
                end
            end
            if phase == "ENGAGING" and pending_attack then
                if os.time() - pending_attack.since < p.rules.attackWait then return end
                if r.id == pending_attack.room then
                    attacked_in_room[pending_attack.id] = true
                end
                pending_attack = nil
                announce("READY")
            end
            if r.id == p.safeRoom and hp < p.rules.returnHP then
                announce("RECOVERY"); return
            end
            if weakest and weakest.hp < p.rules.returnHP and r.id == p.safeRoom then
                announce("RECOVERY"); return
            end
            if target then
                if dry then
                    note("AutoExp TEST: atak -> " .. target.name .. " [" .. target.id .. "]")
                    pause("Zakonczono test - zadnej komendy nie wyslano")
                    return
                end
                announce("ENGAGING")
                engaged_here = true
                hazard_chain, skip_exit_history = nil, {}
                pending_attack = { id = target.id, room = r.id, since = os.time() }
                attacked_in_room[target.id] = true
                ctx:send("zabij " .. target.id, true)
                queue(0)
                return
            end
            last_seen[r.id] = os.time()
            local next_id, wait_time = select_next(p, r.id)
            if not next_id then
                if dry then
                    note("AutoExp TEST: brak gotowego pokoju / trasy")
                    pause("Zakonczono test")
                    return
                end
                announce("COOLDOWN")
                if not wait_time then pause("Nie ma dostepnej trasy patrolu") end
                return
            end
            if dry then
                note("AutoExp TEST: patrol -> " .. next_id)
                pause("Zakonczono test - zadnej komendy nie wyslano")
                return
            end
            move_to(next_id, "patrol")
        end
        local function start(test_mode)
            if started then
                if paused then
                    note("AutoExp jest WSTRZYMANY. Uzyj /exp wznow lub /exp stop, aby zaczac od nowa.", "warn")
                else
                    note("AutoExp juz dziala (uzyj /exp stop).", "warn")
                end
                return
            end
            local p = profile()
            if not p then note("Wybierz profil: /exp wybierz NAZWA", "warn"); return end
            if #p.route == 0 or #p.targets == 0 or not p.safeRoom then
                note("Profil wymaga trasy, celow i bezpiecznej lokacji.", "warn")
                return
            end
            if not gmcp_api.connected() or not room() or not mapper.current_room() then
                note("Brak polaczenia GMCP albo pozycji na mapie.", "warn"); return
            end
            local hp = health()
            if not hp then note("Brak kondycji w GMCP.", "warn"); return end
            if not gmcp_api.combat() or not gmcp_api.group() then
                note("Czekam na GMCP walki i druzyny.", "warn"); return
            end
            if state.owns_walk or external_walk then
                note("Chodzik jest juz uruchomiony - zatrzymaj go przed AutoExp.", "warn")
                return
            end
            local current = room_id()
            observed_room, entities_ready = current, false
            local entities = gmcp_api.entities()
            if type(entities) == "table" and entities.room == current then entities_ready = true end
            if not entities_ready then
                note("Nie ma swiezych danych Entities. Zrob krok / odswiez lokacje.", "warn")
                return
            end
            record_room(room())
            started, paused, dry = true, false, test_mode == true
            pending_attack, move, post_combat_at, escape, emergency = nil, nil, nil, nil, nil
            cancel_economy_timers()
            economy_run, loot_run = nil, nil
            attacked_in_room, last_seen, skip_exit_history = {}, {}, {}
            hazard_chain, engaged_here = nil, false
            last_visited = os.time()
            last_group = {}
            for _, member in ipairs((gmcp_api.group() or {}).members or {}) do
                if member.id and not bool(member.self) then last_group[tostring(member.id)] = true end
            end
            announce(dry and "TEST" or "READY")
            queue(0)
        end
        -- Bus handlers: the new official Chimera API guarantees that gmcp_api
        -- state has been updated before these callbacks are emitted.
        ctx:on("chimera.room.info", function(r)
            record_room(r)
            maybe_record(r)
        end)
        ctx:on("chimera.room.changed", function(r)
            expected_manual = nil -- room has changed; step ownership expired
            record_room(r)
            -- The changed event has only {id,how,...}; complete exits live in
            -- gmcp.room() and were updated before official Chimera emitted it.
            local latest = room()
            if r and latest and latest.id == r.id then record_room(latest) end
            if emergency and r and valid_id(r.id) then
                emergency.visits[r.id] = (emergency.visits[r.id] or 0) + 1
            end
            local was_escaping = escape and r and r.id ~= escape.origin
            local was_emergency = emergency and emergency.step and r
                and r.id ~= emergency.step.origin
            if was_emergency and r.id ~= emergency.step.destination then
                -- A server teleport or stale mapper link is NOT grounds to
                -- abandon a lifesaving retreat. Use actual confirmed GMCP.
                note("AutoExp ALARM: trafilem do innego pokoju niz planowano; przeliczam odwrot z GMCP!", "warn")
            end
            if loot_run and r and r.id ~= loot_run.origin then
                pause("Zbieranie lupow przerwane przez zmiane pokoju")
                return
            end
            -- A single combat-transit direction is our own movement, even
            -- though the official step bus may label it 'reczny'.
            local was_trade_step = economy_run and economy_run.direct_step and r
                and r.id ~= economy_run.direct_step.origin
            if was_trade_step then
                local step = economy_run.direct_step
                if r.id ~= step.destination then
                    pause("HANDEL: niespodziewana lokacja po kroku podczas walki")
                    return
                end
                economy_run.direct_step = nil
                economy_run.direct_steps_completed =
                    (economy_run.direct_steps_completed or 0) + 1
            end
            if was_escaping then
                escape = nil -- direct step from an avoided room succeeded
                pending_attack, post_combat_at = nil, nil
            end
            if was_emergency then
                emergency.step = nil -- confirmed direct step; continue via GMCP
                pending_attack, post_combat_at = nil, nil
            end
            if r and r.id ~= observed_room then
                engaged_here = false
                observed_room, entities_ready = r.id, false
                attacked_in_room = {}
                last_visited = os.time()
            end
            maybe_record(room())
            if started and not paused and not state.owns_walk then
                -- Manual navigation while running is not treated as a patrol step.
                if r and r.how == "reczny" and not was_escaping
                    and not was_emergency and not was_trade_step then
                    pause("Wykryto ruch reczny gracza")
                else
                    queue(0)
                end
            end
        end)
        ctx:on("chimera.room.entities", function(packet)
            if packet and room_id() and packet.room == room_id() then
                entities_ready = true
                if started and not paused then queue(0) end
            end
        end)
        ctx:on("chimera.char.vitals", function() queue(0) end)
        ctx:on("chimera.combat.state", function() queue(0) end)
        ctx:on("chimera.group.state", function(packet)
            local ids = {}
            for _, member in ipairs(packet and packet.members or {}) do
                if member.id and not bool(member.self) then ids[tostring(member.id)] = true end
            end
            if started and not paused and last_group then
                for id in pairs(last_group) do
                    if not ids[id] then
                        pause("Czlonek druzyny zniknal z GMCP (" .. id .. ")")
                        break
                    end
                end
            end
            last_group = ids
            queue(0)
        end)
        ctx:on("chimera.walk.started", function()
            if not state.owns_walk then
                external_walk = true
                if started and not paused then pause("Obcy chodzik przejal ruch") end
            end
        end)
        ctx:on("chimera.walk.arrived", function(event)
            external_walk = false
            if not state.owns_walk or not move then return end
            if event.map_room ~= move.map or event.target ~= move.id
                or room_id() ~= move.id then
                pause("Chodzik: cel lub pozycja GMCP nie potwierdzily dotarcia")
                return
            end
            state.owns_walk = false
            move = nil
            announce("WAIT_ENTITIES")
            last_visited = os.time()
            queue(0)
        end)
        ctx:on("chimera.walk.stopped", function(event)
            external_walk = false
            if not state.owns_walk or stop_ours then return end
            state.owns_walk = false
            move = nil
            if started and not paused then
                if event and event.reason == "atak" then
                    -- Keep the merchant goal. During ordinary patrol a fight
                    -- starts combat; during commerce we continue with GMCP
                    -- single steps, never restarting the walker into combat.
                    if economy_run then
                        economy_run.combat_transit = true
                        note("AutoExp HANDEL: atak przerwal chodzik; zachowuje cel kursu i kontynuuje krokami GMCP.", "warn")
                    end
                    queue(0)
                else
                    pause("Chodzik przerwany: " .. tostring(event and event.reason or "brak powodu"))
                end
            end
        end)
        ctx:on("chimera.session.end", function() halt("Rozlaczono - automat zatrzymany") end)
        ctx:on("chimera.step.manual", function(manual)
            if not started or paused then return end
            local direction = type(manual) == "table" and manual.direction or nil
            direction = direction and (EXIT_COMMANDS[direction] or direction)
            -- Consume at most ONE event belonging to a step just sent by XP.
            -- Some Mudlet callbacks occur after ctx:send() has already returned.
            local expected = expected_manual
            if expected and not expected.consumed and direction
                and direction == expected.direction and room_id() == expected.room
                and os.time() - expected.time <= 2 then
                expected.consumed = true
                return
            end
            -- All other directions (and another matching manual event) are
            -- genuine user input: retain the manual-takeover safety rule.
            expected_manual = nil
            pause("Gracz przejal sterowanie")
        end)
        ctx:timer(1, function()
            if started and not paused then queue(0) end
        end, true)
        ctx:cleanup(function()
            cancel_economy_timers()
            economy_run, loot_run = nil, nil
            if state.owns_walk then walker.stop("AutoExp: przeladowanie") end
            state.owns_walk = false
        end)
        -- Commands intentionally share the old /exp interface only after the
        -- OLD XML package has been disabled. New /exp endpoints are explicit.
        local function command(name, args, fn, help)
            ctx:command{ "exp " .. name, args = args, help = help or "AutoExp 5", fn = fn }
        end
        local function print_status()
            local p = profile()
            ctx:report("AutoExp 5", {
                {"Wersja", "0.5.0-beta.19"},
                {"Stan", (economy_run and ("HANDEL/" .. economy_run.stage) or phase) ..
                    (dry and " [TEST]" or "")},
                {"Profil", p and p.name or "brak"},
                {"Lokacje", p and tostring(#p.route) or "0"},
                {"Cele", p and table.concat(p.targets, ", ") or "brak"},
                {"Planowane lupy", p and (type(p.loot) == "table" and #p.loot>0 and table.concat(p.loot, ", ") or "brak") or "brak"},
                {"Zarobek", p and p.economy and p.economy.enabled and "WLACZONY" or "wylaczony"},
                {"Tempo handlu", string.format("%.2f s", economy_command_delay())},
                {"Omijane", p and table.concat(p.avoid, ", ") or "brak"},
                {"Bezpieczna", p and tostring(p.safeRoom or "brak") or "brak"},
                {"Ostatnia uwaga", last_reason ~= "" and last_reason or "brak"},
                {"Wskazowka", "/exp pomoc"},
            })
        end
        ctx:command{ "exp", help = "AutoExp 5 - stan", fn = print_status }
        command("status", nil, print_status)
        command("pomoc", nil, function()
            ctx.log.info("/exp obszary | wybierz NAZWA | mapuj NAZWA | mapuj! NAZWA | mapuj-")
            ctx.log.info("/exp cel TEKST | cel- TEKST | unikaj TEKST | unikaj- TEKST")
            ctx.log.info("Limit NPC z /exp limit N liczy tylko cele /exp cel, nie inne zwierzeta; /exp unikaj dziala niezaleznie.")
            ctx.log.info("/exp bezpieczna | hp ODWROT POWROT | limit NPC | odnowa SEK | start | test | odwrot-test | pauza | wznow | stop")
            ctx.log.info("/exp import (jednorazowo ze starej bazy, tylko gdy w nowej brak profili)")
            ctx.log.info("/exp aktualizuj (pobierz najnowsza ChimeraXP z publicznego GitHuba)")
            ctx.log.info("/exp lup dodaj TEKST | lup usun TEKST | lup lista | zarobek prog 75 | zarobek diagnoza | zarobek trasa")
            ctx.log.info("Lupy: po walce policz ciala, potem wez TEKST z 1. ciala, 2. ciala itd. (do 30)")
            ctx.log.info("/exp zarobek wlacz | zarobek wylacz | zarobek kurs (REALNY sklep-bank-powrot)")
            ctx.log.info("/exp zarobek tempo 0.7 (odstep polecen lupow, sprzedazy i banku: 0.3-3 s)")
            ctx.log.info("UWAGA: sprzedaj bronie/zbroje obejmuje niesione przedmioty; wem i wlm to globalne aliasy.")
        end)
        command("aktualizuj", nil, function()
            local updater = rawget(_G, "chimera_xp_updater")
            if type(updater) == "table" and type(updater.check) == "function" then
                updater:check(true)
            else
                note("Nie zainstalowano internetowego instalatora ChimeraXP. Uruchom: lua installPackage(\"https://raw.githubusercontent.com/gnomidlo/ChimeraXP/main/packages/ChimeraXP.xml\")", "warn")
            end
        end)
        command("start", nil, function() start(false) end)
        command("test", nil, function() start(true) end)
        -- ECONOMY PHASE 1: configuration and read-only diagnostics only.
        -- Explicitly no loot, sales, bank or travel commands are sent.
        command("lup dodaj", "<tekst>", function(item)
            if not allowed_config() then return end
            local p = profile()
            item = trim(item)
            if not p then note("Wybierz expowisko.", "warn"); return end
            if item == "" or #item > 80 or item:find("[;%c]") then
                note("Podaj bezpieczny tekst odmiany przedmiotu, np. /exp lup dodaj miecz.", "warn")
                return
            end
            p.loot = p.loot or {}
            p.loot[#p.loot + 1] = item
            p.loot = unique_names(p.loot)
            remember()
            note("Lupy profilu: " .. table.concat(p.loot, ", "))
        end)
        command("lup usun", "<tekst>", function(item)
            if not allowed_config() then return end
            local p = profile()
            if not p then note("Wybierz expowisko.", "warn"); return end
            p.loot = p.loot or {}
            for i, value in ipairs(p.loot) do
                if normalized(value) == normalized(item) then
                    table.remove(p.loot, i)
                    remember()
                    note("Usunieto z listy lupow: " .. value)
                    return
                end
            end
            note("Nie ma takiego przedmiotu na liscie lupow.", "warn")
        end)
        command("lup lista", nil, function()
            local p = profile()
            if not p then note("Wybierz expowisko.", "warn"); return end
            note("Lupy " .. p.name .. ": " ..
                ((p.loot and #p.loot > 0) and table.concat(p.loot, ", ") or "brak"))
        end)
        command("zarobek tempo", "<sekundy>", function(value)
            if not allowed_config() then return end
            local p, seconds = profile(), tonumber(value)
            if not p then note("Wybierz expowisko.", "warn"); return end
            if not seconds or seconds ~= seconds or seconds < 0.3 or seconds > 3 then
                note("Uzycie: /exp zarobek tempo 0.7 (od 0.3 do 3.0 s).", "warn")
                return
            end
            p.rules.economyCommandDelay = seconds
            remember()
            note("Odstep polecen zarobku: " .. tostring(seconds) ..
                " s; trasy nadal sa potwierdzane przez GMCP.")
        end)
        command("zarobek prog", "<procent>", function(value)
            if not allowed_config() then return end
            local p, number = profile(), tonumber(value)
            if not p or not number or number < 1 or number >= 100 or number % 1 ~= 0 then
                note("Uzycie: /exp zarobek prog 75 (od 1 do 99)", "warn"); return
            end
            p.rules.economyLoadThreshold = number
            remember()
            note("Prog kursu handlowego: " .. number .. "%. Kursy NIE SA JESZCZE aktywne.")
        end)

        -- Read-only economy route planner. Never starts walker or sends commands.
        -- Tagged rooms are verified against GMCP hashes and current Mudlet map.
        local function economy_cost(from_map, to_map)
            if from_map == to_map then return 0 end
            if type(walker.cost) ~= "function" then return nil end
            local ok, distance = pcall(walker.cost, from_map, to_map)
            if ok and type(distance) == "number" and distance >= 0
                and distance < math.huge then return distance end
            return nil
        end
        local function economy_candidates(tag)
            if type(locations) ~= "table" or type(locations.targets) ~= "function" then
                return nil, "Modul locations nie jest dostepny w oficjalnej Chimerze."
            end
            if type(getRoomIDbyHash) ~= "function" then
                return nil, "Mapper nie udostepnia getRoomIDbyHash()."
            end
            local ok, targets = pcall(locations.targets, tag)
            if not ok or type(targets) ~= "table" then
                return nil, "Nie mozna odczytac tagu /room " .. tag
            end
            local out, unique = {}, {}
            for _, value in pairs(targets) do
                local hash = type(value) == "table" and (value.hash or value.id) or value
                if valid_id(hash) and not unique[hash] then
                    unique[hash] = true
                    local map = getRoomIDbyHash(hash)
                    if type(map) == "number" and map > 0 and map == math.floor(map) then
                        out[#out + 1] = {hash = hash, map = map}
                    end
                end
            end
            table.sort(out, function(a,b) return a.hash < b.hash end)
            if #out == 0 then
                return nil, "Brak otagowanych, znanych na mapie lokacji /room " .. tag
            end
            return out
        end
        local function economy_nearest(from_map, options)
            local best, cost
            for _, candidate in ipairs(options or {}) do
                local length = economy_cost(from_map, candidate.map)
                if length and (not best or length < cost or
                    (length == cost and candidate.map < best.map)) then
                    best, cost = candidate, length
                end
            end
            return best, cost
        end
        -- A consciously enabled, one-shot, sequential merchant/bank trip.
        -- Shop and bank confirmations are not documented yet. Those stages
        -- proceed after a grace period and are logged as UNCONFIRMED. Denomination
        -- has a known server response and MUST be confirmed to proceed.
        local function economy_delay(run, stage, seconds, callback)
            if economy_timer then ctx:cancel(economy_timer); economy_timer=nil end
            economy_timer=ctx:timer(seconds, function()
                economy_timer=nil
                if economy_run == run and started and not paused and run.stage == stage then
                    callback()
                end
            end)
        end
        local function economy_do_send(run, text, as_alias)
            note("AutoExp HANDEL [" .. run.stage .. "]: " .. text)
            local ok,err
            if as_alias then
                if type(expandAlias)~="function" then
                    pause("Brak funkcji expandAlias dla " .. text)
                    return false
                end
                ok,err=pcall(expandAlias, text, false)
            else
                ok,err=pcall(ctx.send, ctx, text)
            end
            if not ok then
                pause("Nie udalo sie wykonac " .. text .. ": " .. tostring(err))
                return false
            end
            return true
        end
        -- The official walker always stops on 'atak'. When we are on a
        -- commerce trip, use one GMCP-verified exit at a time. Do not fight
        -- or restart the full walker while the fight is active.
        local function economy_combat_step(run, r, target)
            local step = run.direct_step
            if step then
                if step.origin ~= r.id then
                    pause("HANDEL: niezgodna lokacja oczekiwanego kroku")
                    return
                end
                if os.time() - step.sent_at < 2 then return end
                if step.tries >= 3 then
                    pause("HANDEL: krok w walce nie przeszedl po 3 probach (" ..
                        tostring(step.command) .. "). Przejmij sterowanie!")
                    return
                end
                step.tries = step.tries + 1
                step.sent_at = os.time()
                local ok, err = send_owned_direction(step.command)
                if not ok then pause("HANDEL: blad ponowienia kroku: " .. tostring(err)) end
                return
            end
            local direction, next_hash
            local from = type(getRoomIDbyHash) == "function" and getRoomIDbyHash(r.id) or nil
            local dest = type(getRoomIDbyHash) == "function" and getRoomIDbyHash(target) or nil
            if type(from) == "number" and from > 0
                and type(dest) == "number" and dest > 0
                and type(getPath) == "function" then
                local ok, found = pcall(getPath, from, dest)
                if ok and found then
                    local path = type(speedWalkPath) == "table" and speedWalkPath or {}
                    local next_room = path[1]
                    local candidate = type(getRoomHashByID) == "function"
                        and getRoomHashByID(next_room) or nil
                    if valid_id(candidate) then
                        for exit, hash in pairs(type(r.exits) == "table" and r.exits or {}) do
                            local command = EXIT_COMMANDS[exit]
                            if hash == candidate and command then
                                direction, next_hash = command, hash
                                break
                            end
                        end
                    end
                end
            end
            if not direction then
                direction, next_hash = known_step_toward(r, target)
            end
            if not direction or not valid_id(next_hash) then
                pause("HANDEL: brak potwierdzonego kierunku GMCP do celu kursu podczas walki")
                return
            end
            run.direct_visits = run.direct_visits or {}
            local visits = (run.direct_visits[r.id] or 0) + 1
            run.direct_visits[r.id] = visits
            run.direct_moves = (run.direct_moves or 0) + 1
            if visits > 3 or run.direct_moves > 120 then
                pause("HANDEL: wykryto petle ruchu w walce; zatrzymano dla bezpieczenstwa")
                return
            end
            run.direct_step = {
                origin = r.id, destination = next_hash, command = direction,
                sent_at = os.time(), tries = 1,
            }
            note("AutoExp HANDEL: walka w drodze, krok " .. direction ..
                " -> " .. next_hash .. " (cel " .. target .. ")")
            local ok, err = send_owned_direction(direction)
            if not ok then pause("HANDEL: blad wyslania kroku: " .. tostring(err)) end
        end
        local function economy_continue_route(run, r, active, target)
            if r.id == target then
                run.combat_transit = false
                run.direct_step = nil
                return true
            end
            if state.owns_walk then return false end
            -- An owned direct step has to finish (or time out) before another
            -- route request, even if Combat GMCP has already switched to idle.
            if run.direct_step then
                economy_combat_step(run, r, target)
            elseif active or run.combat_transit then
                if not active and (run.direct_steps_completed or 0) > 0 then
                    -- At least one owned step succeeded, and GMCP now says
                    -- combat ended: restart native walker from this real room.
                    run.combat_transit = false
                    move_to(target, "economy")
                else
                    -- Walker can stop before the combat GMCP update arrives.
                    -- Do not start it again prematurely: make one confirmed
                    -- direct step instead of a walker-stop retry loop.
                    run.combat_transit = true
                    economy_combat_step(run, r, target)
                end
            else
                move_to(target, "economy")
            end
            return false
        end
        local function economy_travel(run, stage, target)
            if economy_run ~= run or paused then return end
            run.stage=stage
            run.direct_step, run.direct_visits, run.direct_moves = nil, {}, 0
            run.direct_steps_completed = 0
            if room_id() == target then
                queue(0)
            else
                local _, _, group_ids = health()
                local active = combat_status(group_ids)
                if active or run.combat_transit then
                    queue(0)
                else
                    move_to(target, "economy")
                end
            end
        end
        process_economy=function(r, active)
            local run=economy_run
            if not run or state.owns_walk then return end
            if run.stage=="TO_SHOP" then
                if not economy_continue_route(run, r, active, run.shop.hash) then return end
                run.stage="SALE_WEAPONS"
                if not economy_do_send(run, "sprzedaj bronie") then return end
                economy_delay(run,"SALE_WEAPONS",economy_command_delay(),function()
                    if room_id() ~= run.shop.hash then pause("Opuszczono sklep w czasie handlu");return end
                    run.stage="SALE_ARMOR"
                    if not economy_do_send(run,"sprzedaj zbroje") then return end
                    economy_delay(run,"SALE_ARMOR",economy_command_delay(),function()
                        if room_id() ~= run.shop.hash then pause("Opuszczono sklep w czasie handlu");return end
                        note("AutoExp: wyslano obie sprzedaze (brak niezawodnych potwierdzen serwera).", "warn")
                        economy_travel(run,"TO_BANK",run.bank.hash)
                    end)
                end)
            elseif run.stage=="TO_BANK" then
                if not economy_continue_route(run, r, active, run.bank.hash) then return end
                run.stage="BANK_WEM"
                if not economy_do_send(run,"wem",true) then return end
                economy_delay(run,"BANK_WEM",economy_command_delay(),function()
                    if room_id()~=run.bank.hash then pause("Opuszczono bank przed denominacja");return end
                    run.stage="BANK_DENOMINATE"
                    if not economy_do_send(run,"zdenominuj") then return end
                    if economy_run~=run or run.stage~="BANK_DENOMINATE" then return end
                    economy_delay(run,"BANK_DENOMINATE",20,function()
                        pause("Brak potwierdzenia denominacji w 20 sekund; WLМ nie wyslano")
                    end)
                end)
            elseif run.stage=="TO_RETURN" then
                if not economy_continue_route(run, r, active, run.origin) then return end
                local single=run.test_only
                economy_run=nil
                if economy_timer then ctx:cancel(economy_timer);economy_timer=nil end
                if single then
                    halt("Zakonczono probny kurs sklep -> bank -> expowisko")
                else
                    local weight=economy_encumbrance(gmcp_api.vitals())
                    local threshold=tonumber((profile().rules or {}).economyLoadThreshold) or 75
                    if weight == nil or weight>threshold then
                        pause("Kurs zakonczony, ale obciazenie nie spadlo ponizej progu (" ..
                             tostring(weight) .. "/" .. tostring(threshold) .. "). Sprawdz sprzedaz!")
                    else
                        note("AutoExp: powrot z handlu, wznowienie patrolu ("..weight..").")
                        observed_room, entities_ready=r.id,false
                        local packet=gmcp_api.entities()
                        entities_ready=packet and packet.room==r.id or false
                        queue(0)
                    end
                end
            end
        end
        begin_economy=function(test_only)
            if not started or paused or dry or economy_run then return false end
            if state.owns_walk or external_walk then
                note("Zarobek: inny chodzik jest aktywny.", "warn")
                return false
            end
            local r=room()
            local current=mapper.current_room()
            if not r or not valid_id(r.id) or type(current)~="number"
                or type(getRoomIDbyHash)~="function" or getRoomIDbyHash(r.id)~=current then
                pause("Zarobek: niespojna lokacja GMCP i mapper")
                return false
            end
            local hp, weak, group=health()
            local fighting=combat_status(group)
            if not hp or hp<=profile().rules.retreatHP or
                (weak and weak.hp<=profile().rules.retreatHP) or fighting then
                pause("Zarobek: kurs odmowiony z powodu walki lub HP")
                return false
            end
            local shops,err=economy_candidates("sklep")
            if not shops then pause("Zarobek: "..err);return false end
            local shop=economy_nearest(current,shops)
            if not shop then pause("Zarobek: brak trasy do sklepu");return false end
            local banks,err2=economy_candidates("bank")
            if not banks then pause("Zarobek: "..err2);return false end
            local bank=economy_nearest(shop.map,banks)
            if not bank then pause("Zarobek: brak trasy sklep -> bank");return false end
            if not economy_cost(bank.map,current) then
                pause("Zarobek: nie ma potwierdzonej drogi bank -> miejsce expa")
                return false
            end
            local run={origin=r.id,shop=shop,bank=bank,
                       stage="TO_SHOP",test_only=test_only}
            economy_run=run
            pending_attack,post_combat_at,escape=nil,nil,nil
            note("AutoExp: kurs do sklepu "..shop.map.." -> banku "..bank.map..
                 " -> powrotu "..current.."; test="..tostring(test_only))
            economy_travel(run,"TO_SHOP",shop.hash)
            return true
        end
        -- One exact recognized server confirmation authorizes the final
        -- withdrawal alias. Never emit wlm before denominations complete.
        local function economy_denom_confirmed()
            local run=economy_run
            if not run or run.stage~="BANK_DENOMINATE"
                or room_id()~=run.bank.hash or paused then return end
            if economy_timer then ctx:cancel(economy_timer);economy_timer=nil end
            run.stage="BANK_WLM"
            if not economy_do_send(run,"wlm",true) then return end
            economy_delay(run,"BANK_WLM",economy_command_delay(),function()
                if room_id()~=run.bank.hash then pause("Opuszczono bank przed powrotem");return end
                economy_travel(run,"TO_RETURN",run.origin)
            end)
        end
        ctx:trigger([[^Twoje pieniadze zostaly zdenominowane\.$]], economy_denom_confirmed)
        ctx:trigger([[^Twoje pieniadze juz sa maksymalnie zdenominowane\.$]], economy_denom_confirmed)
        command("zarobek wlacz",nil,function()
            if not allowed_config() then return end
            local p=profile()
            if not p then note("Wybierz expowisko", "warn");return end
            p.economy=p.economy or {}
            p.economy.enabled=true
            remember()
            note("EXP+ZAROBEK WLACZONY. UWAGA: 'sprzedaj bronie/zbroje' moze sprzedac tez PRYWATNE przedmioty!", "warn")
        end)
        command("zarobek wylacz",nil,function()
            if not allowed_config() then return end
            local p=profile()
            if not p then note("Wybierz expowisko", "warn");return end
            p.economy=p.economy or {}
            p.economy.enabled=false
            remember()
            note("EXP+ZAROBEK WYLACZONY.")
        end)
        -- Manual one-shot test drives real shop/bank commands, then STOPS.
        -- It doesn't require auto economy enabled. Start only from idle.
        command("zarobek kurs",nil,function()
            if started or state.owns_walk or external_walk then
                note("Najpierw /exp stop i zatrzymaj zewnetrzny chodzik.", "warn")
                return
            end
            note("TEST REALNY: sprzedaje WSZYSTKIE niesione bronie i zbroje! /exp stop przerwie kurs.", "warn")
            start(false)
            if not started then
                note("Nie udalo sie zainicjowac probnego kursu.", "warn")
                return
            end
            if not begin_economy(true) then
                halt("Probny kurs nie mogl wystartowac")
            end
        end)
        command("zarobek trasa", nil, function()
            note("EXP+ZAROBEK: test trasy, bez ruchu, sprzedazy i operacji bankowych.")
            local r, p = room(), profile()
            if not p or not r or not valid_id(r.id) then
                note("Brak profilu expowiska lub aktualnego pokoju GMCP.", "warn")
                return
            end
            if type(getRoomIDbyHash) ~= "function" then
                note("Brak getRoomIDbyHash w mapperze.", "warn")
                return
            end
            local from = mapper.current_room()
            if type(from) ~= "number" or from < 1 or getRoomIDbyHash(r.id) ~= from then
                note("Niespojna pozycja GMCP / mapper; nie planuje kursu.", "warn")
                return
            end
            local shops, shop_error = economy_candidates("sklep")
            if not shops then note(shop_error, "warn"); return end
            local shop, shop_cost = economy_nearest(from, shops)
            if not shop then
                note("Brak osiagalnego sklepu od obecnej lokacji.", "warn")
                return
            end
            local banks, bank_error = economy_candidates("bank")
            if not banks then note(bank_error, "warn"); return end
            local bank, bank_cost = economy_nearest(shop.map, banks)
            if not bank then
                note("Nie ma banku osiagalnego od wybranego sklepu (mapa " ..
                     tostring(shop.map) .. ").", "warn")
                return
            end
            note("Sklep: mapa " .. shop.map .. ", GMCP " .. shop.hash ..
                " (koszt trasy od aktualnej lokacji: " .. shop_cost .. ").")
            note("Bank: mapa " .. bank.map .. ", GMCP " .. bank.hash ..
                " (koszt trasy od sklepu: " .. bank_cost .. ").")
            local resume = type(p.route) == "table" and p.route[1] or nil
            if valid_id(resume) then
                local resume_map = getRoomIDbyHash(resume)
                local back = type(resume_map) == "number" and
                    economy_cost(bank.map, resume_map) or nil
                if back then
                    note("Przykladowy powrot do pierwszego pokoju trasy: mapa " ..
                        resume_map .. " (koszt: " .. back .. ").")
                else
                    note("Brak potwierdzonej drogi z banku do poczatku trasy expowiska.", "warn")
                end
            end
            note("Kurs nie jest wlaczony. Docelowy powrot bedzie do miejsca przerwania patrolu.")
        end)
        command("zarobek diagnoza", nil, function()
            local p = profile()
            note("Zarobek: diagnostyka tylko do odczytu, niczego nie wysylam do gry.")
            local vitals = type(gmcp) == "table"
                and type(gmcp.Char) == "table" and gmcp.Char.Vitals or nil
            local enc = economy_encumbrance(vitals)
            if enc ~= nil then
                note("Obciazenie GMCP: " .. enc ..
                    (type(vitals) == "table" and vitals.encumbrance == nil
                     and " (brak pola encumbrance = 0)" or
                     " (surowa wartosc; skala wymaga weryfikacji)."))
            else
                note("Brak poprawnego pakietu Char.Vitals / encumbrance.", "warn")
            end
            note("Prog: " .. tostring(p and (p.rules.economyLoadThreshold or 75) or 75)
                 .. "%; przedmioty: " .. tostring(p and #(p.loot or {}) or 0))
            local root = type(gmcp) == "table" and gmcp or {}
            local char = type(root.Char) == "table" and root.Char or {}
            local terms = {"weight", "weigh", "carry", "capacity", "encumbr", "load",
                           "udzw", "waga", "wagi", "obcia", "ciezar", "ciezk", "maxwt"}
            local found = {}
            local seen = {}
            local function scan(node, path, depth)
                if depth > 5 or type(node) ~= "table" or seen[node] then return end
                seen[node] = true
                for key, value in pairs(node) do
                    local label = tostring(key)
                    local lower = label:lower()
                    local name = path .. "." .. label
                    if (type(value) == "number" or (type(value) == "string" and tonumber(value)))
                        and #found < 25 then
                        for _, word in ipairs(terms) do
                            if lower:find(word, 1, true) then
                                found[#found + 1] = name .. " = " .. tostring(value)
                                break
                            end
                        end
                    elseif type(value) == "table" then
                        scan(value, name, depth + 1)
                    end
                end
            end
            scan(char, "gmcp.Char", 0)
            if type(root.Inventory) == "table" then scan(root.Inventory, "gmcp.Inventory", 0) end
            if type(root.Items) == "table" then scan(root.Items, "gmcp.Items", 0) end
            table.sort(found)
            if #found == 0 then
                note("Nie znaleziono numerycznego pola obciazenia w GMCP.Char/Inventory/Items. " ..
                     "Do ustalenia: rzeczywiste pole, jednostki i max udzwig.", "warn")
            else
                for _, text in ipairs(found) do note("Kandydat GMCP: " .. text) end
            end
            local packet = gmcp_api.entities()
            if type(packet) == "table" and packet.room == room_id() then
                local corpses = 0
                for _, ent in ipairs(packet.entities or {}) do
                    local kind = normalized(ent.kind)
                    local name = normalized(ent.name)
                    if kind == "corpse" or name:find("cial", 1, true) then
                        corpses = corpses + 1
                        if corpses <= 5 then
                            note("Kandydat ciala: " .. tostring(ent.name) ..
                                "; id=" .. tostring(ent.id) .. "; kind=" .. tostring(ent.kind))
                        end
                    end
                end
                if corpses == 0 then note("Brak rozpoznanych cial w GMCP Room.Entities.") end
            else
                note("Brak aktualnych Room.Entities do diagnostyki cial.")
            end
            note("Sprawdz tagi poleceniami /room lista sklep oraz /room lista bank.")
        end)
        command("odwrot-test", nil, function()
            local p, r = profile(), room()
            if not p or not r or not valid_id(r.id) or not valid_id(p.safeRoom) then
                note("AutoExp TEST ODWROTU: wybierz profil i zapisz /exp bezpieczna.", "warn")
                return
            end
            record_room(r)
            if r.id == p.safeRoom then
                note("AutoExp TEST ODWROTU: juz jestes w bezpiecznej lokacji.")
                return
            end
            local command, next_id, source = emergency_step(p, r)
            if command then
                note("AutoExp TEST ODWROTU: " .. command .. " -> " .. next_id ..
                    " (" .. source .. "); nie wyslano ruchu" ..
                    ((source == "mapper" or source == "GMCP") and "" or
                    ". UWAGA: to tylko awaryjne wyjscie, nie potwierdzona trasa do schronienia!"),
                    "warn")
            else
                note("AutoExp TEST ODWROTU: ALARM, brak znanego dostepnego wyjscia GMCP!", "warn")
            end
        end)
        command("stop", nil, function() halt("Zatrzymano recznie") end)
        command("pauza", nil, function() pause("Pauza uzytkownika") end)
        command("wznow", nil, function()
            if started and paused then
                paused, phase = false, "READY"
                observed_room, entities_ready = room_id(), false
                local packet = gmcp_api.entities()
                entities_ready = packet and packet.room == room_id() or false
                last_visited = os.time()
                last_group = {}
                for _, member in ipairs((gmcp_api.group() or {}).members or {}) do
                    if member.id and not bool(member.self) then last_group[tostring(member.id)] = true end
                end
                queue(0)
                note("AutoExp: wznowiono")
            else note("Brak pauzy do wznowienia.", "warn") end
        end)
        command("obszary", nil, function()
            local names = {}
            for _, p in pairs(areas) do names[#names + 1] = p.name .. " (" .. #p.route .. ")" end
            table.sort(names)
            note(#names == 0 and "Brak profili." or table.concat(names, " | "))
        end)
        command("wybierz", "<nazwa>", function(name)
            if not allowed_config() then return end
            local key = normalized(name)
            if not areas[key] then note("Nie ma expowiska: " .. name, "warn"); return end
            selected = key
            remember()
            note("Wybrane: " .. areas[key].name)
        end)
        local function toggle_map(name, replace)
            if not allowed_config() then return end
            if mapping then
                if normalized(name) ~= mapping.key then
                    note("Mapujesz inne expowisko. Powtorz jego nazwe lub /exp mapuj-", "warn")
                    return
                end
                if #mapping.route == 0 then note("Mapa jest pusta.", "warn"); return end
                local old = areas[mapping.key]
                local p = normalize_profile(old, mapping.name)
                if not mapping.replace then
                    local merged = {}
                    for _, id in ipairs(p.route) do merged[#merged + 1] = id end
                    for _, id in ipairs(mapping.route) do merged[#merged + 1] = id end
                    p.route = rooms_from(merged)
                else
                    p.route = mapping.route
                end
                areas[mapping.key], selected = p, mapping.key
                mapping = nil
                remember()
                note("Zapisano " .. #p.route .. " lokacji: " .. p.name)
                return
            end
            name = trim(name)
            if name == "" then note("Podaj nazwe expowiska.", "warn"); return end
            local key = normalized(name)
            mapping = { name = name, key = key, replace = replace, route = {}, seen = {} }
            maybe_record(room())
            note("Mapowanie " .. name .. " (" .. (replace and "ZASTAP" or "SCAL") .. "). Powtorz komendę, aby zapisac.")
        end
        command("mapuj", "<nazwa>", function(s) toggle_map(s, false) end)
        command("mapuj!", "<nazwa>", function(s) toggle_map(s, true) end)
        command("mapuj-", nil, function() mapping = nil; note("Mapowanie anulowane") end)
        command("cel", "<tekst>", function(value)
            if not allowed_config() then return end
            local p = profile(); if not p then note("Wybierz expowisko.", "warn"); return end
            p.targets[#p.targets + 1] = value
            p.targets = unique_names(p.targets)
            remember(); note("Cele: " .. table.concat(p.targets, ", "))
        end)
        command("unikaj", "<tekst>", function(value)
            if not allowed_config() then return end
            local p = profile(); if not p then note("Wybierz expowisko.", "warn"); return end
            p.avoid[#p.avoid + 1] = value
            p.avoid = unique_names(p.avoid)
            remember(); note("Omijane: " .. table.concat(p.avoid, ", "))
        end)
        local function remove_list(key, value)
            if not allowed_config() then return end
            local p = profile()
            if not p then note("Wybierz expowisko.", "warn"); return end
            local list = p[key]
            for i, item in ipairs(list) do
                if normalized(item) == normalized(value) then
                    table.remove(list, i)
                    remember()
                    note("Usunieto: " .. item)
                    return
                end
            end
            note("Nie ma na liscie: " .. tostring(value), "warn")
        end
        command("cel-", "<tekst>", function(value) remove_list("targets", value) end)
        command("unikaj-", "<tekst>", function(value) remove_list("avoid", value) end)
        command("bezpieczna", nil, function()
            if not allowed_config() then return end
            local p = profile(); local id = room_id()
            if not p or not valid_id(id) then note("Wybierz profil i stan na lokacji.", "warn"); return end
            p.safeRoom = id; remember(); note("Bezpieczna lokacja: " .. id)
        end)
        command("hp", "<odwrot powrot>", function(s)
            if not allowed_config() then return end
            local a, b = s:match("^(%d+)%s+(%d+)$")
            a, b = tonumber(a), tonumber(b)
            local p = profile()
            if not p or not a or not b or a < 1 or a >= b or b > 100 then
                note("Uzycie: /exp hp 35 85", "warn"); return
            end
            p.rules.retreatHP, p.rules.returnHP = a, b
            remember(); note("HP: " .. a .. "% / " .. b .. "%")
        end)
        command("limit", "<liczba>", function(s)
            if not allowed_config() then return end
            local p, n = profile(), tonumber(s)
            if not p or not n or n < 1 or n > 20 or n % 1 ~= 0 then
                note("Uzycie: /exp limit 3 (1..20)", "warn"); return
            end
            p.rules.maxEnemies = n
            remember(); note("Limit NPC: " .. n)
        end)
        command("odnowa", "<sekundy>", function(s)
            if not allowed_config() then return end
            local p, n = profile(), tonumber(s)
            if not p or not n or n < 5 or n > 3600 then
                note("Uzycie: /exp odnowa 60 (5..3600)", "warn"); return
            end
            p.rules.minRoomRevisit = n
            remember(); note("Odnowa lokacji: " .. n .. " s")
        end)
        command("import", nil, function()
            if not allowed_config() then return end
            if next(areas) then note("Import tylko do pustej nowej bazy; niczego nie nadpisuje.", "warn"); return end
            if type(table.load) ~= "function" then note("Brak table.load w Mudlecie.", "warn"); return end
            local root = getMudletHomeDir()
            local paths = { root .. "/ChimeraVIP-data/autoexp.lua", root .. "/autoexp_areas.lua" }
            for _, path in ipairs(paths) do
                local f = io.open(path, "r")
                if f then
                    f:close()
                    local loaded = {}
                    local ok, result = pcall(table.load, path, loaded)
                    if not ok or result == false then
                        note("Blad odczytu: " .. path, "warn"); return
                    end
                    local imported = import_old_profiles(loaded)
                    if not next(imported) then note("Stara baza nie zawiera expowisk.", "warn"); return end
                    areas = imported
                    if loaded.selectedArea and areas[loaded.selectedArea] then
                        selected = loaded.selectedArea
                    end
                    remember()
                    note("Zaimportowano " .. tostring((function()
                        local n = 0; for _ in pairs(areas) do n = n + 1 end; return n
                    end)()) .. " profili. Stara baza pozostala nietknieta.")
                    return
                end
            end
            note("Nie znaleziono starej bazy AutoExp.", "warn")
        end)
        -- Helpful test-only API, no shared globals or monkeypatches.
        return { status = function() return { phase = phase, started = started, paused = paused,
            selected = selected, moving = move and move.id, mapping = mapping and mapping.name,
            escaping = escape and escape.origin, emergency = emergency and emergency.destination } end,
            import_old_profiles = import_old_profiles }
    end,
}
