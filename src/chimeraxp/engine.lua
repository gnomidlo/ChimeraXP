-- Chimera AutoExp 5 / standalone plugin for official Chimera 5.x.
-- Not compatible with the legacy AutoExp XML package: disable that package.
-- Native APIs only: gmcp, mapper, walker and the chimera.* event bus.
-- Opt-in patrol and commerce; movement behavior retained from beta.2.
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
        partyAttack = bool(old.partyAttack),
        economy = { enabled = type(old.economy) == "table" and bool(old.economy.enabled) },
        safeKey = valid_id(old.safeKey) and old.safeKey or nil,
        safeRoom = valid_id(old.safeRoom) and old.safeRoom or nil,
        safeMap = type(old.safeMap) == "number" and old.safeMap > 0
            and old.safeMap % 1 == 0 and old.safeMap or nil,
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
    version = "0.7.0-beta.38",
    title = "ChimeraXP / AutoExp 5",
    section = "automatyzacja",
    description = "Ostrozny patrol PvE oparty na oficjalnym mapperze i GMCP",
    deps = { "gmcp", "mapper", "walker", "locations" },
    setup = function(ctx, hooks)
        hooks = hooks or {}
        local safety = assert(hooks.safety)
        local destroyed = false
        local requests = {}
        local gmcp_api = ctx:use("gmcp")
        local mapper = ctx:use("mapper")
        local walker = ctx:use("walker")
        -- The official loader grants ctx:use() only to declared deps.
        -- Chimera's built-in /room uses this same locations service.
        local locations = ctx:use("locations")
        local state = ctx.state
        local areas = ctx:saved("profiles", {})
        if type(areas) ~= "table" then areas = {} end
        local normalized_areas = {}
        for key,value in pairs(areas) do
            if type(key)=="string" and type(value)=="table" then
                normalized_areas[key]=normalize_profile(value,value.name or key)
            end
        end
        areas=normalized_areas
        local selected = ctx:saved("selected", nil)
        local verbosity = ctx:saved("verbosity", "quiet")
        if verbosity ~= "quiet" and verbosity ~= "normal" and verbosity ~= "debug" then
            verbosity = "quiet"
        end
        local event_log, event_log_max = {}, 40
        local session = {elapsed=0, xp=0}
        local ui_refresh = function() if not destroyed and hooks.changed then hooks.changed() end end
        local started, paused, dry = false, false, false
        local function session_clock()
            if started and not paused and not dry then
                session.elapsed = session.elapsed + 1
            end
            ui_refresh()
        end
        local phase = "OFF"
        local mapping = nil
        local patrol_leg -- final waypoint and rooms crossed on the way to it
        local move = nil -- { id, map, purpose }
        local pending_attack = nil -- { id, room, since }
        local attacked_in_room = {}
        local last_seen = {} -- room ID -> time at which room was checked and empty
        -- Temporary, session-only quarantine: moving NPCs may leave again.
        local recent_rooms = {}
        local recent_room = nil
        local skip_exit_history = {} -- room ID -> { command = count }
        local fallback, fallback_count = nil, 0
        local begin_fallback
        local function hazardous(id)
            return safety.skipped[id] ~= nil
        end
        local function has_hazards()
            return next(safety.skipped) ~= nil
        end
        local engaged_here = false -- our party has already engaged this room
        -- Remember real, GMCP-confirmed routes even when Mudlet's mapped
        -- getPath() is unavailable or returns a path through an avoided room.
        -- This is session state only; the history is NOT guessed from exits.
        local known_exits = state.emergency_known_exits or {}
        local trail = state.emergency_trail or {}
        state.emergency_known_exits, state.emergency_trail = known_exits, trail
        local function record_room(r)
            if type(r) ~= "table" or not valid_id(r.id) then return end
            if recent_room ~= r.id then
                recent_rooms[r.id], recent_room = os.time(), r.id
            end
            if type(r.exits) == "table" then
                local links = {}
                for direction, id in pairs(r.exits) do
                    if valid_id(direction) and valid_id(id) then links[direction] = id end
                end
                if next(links) then known_exits[r.id] = links end
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
        local native_retreat = nil -- temporary walker settings for a mapped safe retreat
        local last_visited = nil
        local entities_ready = false
        local observed_room = nil
        local observed_key = nil
        local post_combat_at = nil
        local last_reason = ""
        local pending = nil
        local stop_ours = false
        local last_group = nil
        local external_walk = false
        local evaluate
        local fatigue_rest = nil
        -- Economy mode is opt-in. Session callbacks are explicitly cancellable.
        local economy_run, economy_timer, process_economy, begin_economy
        local loot_run, loot_timer = nil, nil
        local function cancel_economy_timers()
            if economy_timer then ctx:cancel(economy_timer); economy_timer=nil end
            if loot_timer then ctx:cancel(loot_timer); loot_timer=nil end
        end

        local function note(message, level)
            local msg = tostring(message)
            event_log[#event_log + 1] = {time = os.date("%H:%M:%S"), msg = msg, level = level}
            if #event_log > event_log_max then table.remove(event_log, 1) end
            local essential = level == "warn" or level == "error"
                or msg:find("WSTRZYMANY",1,true) or msg:find("ALARM",1,true)
            local noisy = msg:find("AutoExp LUP:",1,true)
                or msg:find("AutoExp HANDEL [",1,true)
                or msg:find("AutoExp: kurs do sklepu",1,true)
            if verbosity == "quiet" and not essential and noisy then return end
            local fn = level == "warn" and ctx.log.warn or ctx.log.info
            fn(msg)
        end
        local function announce(label)
            if phase ~= label then
                phase = label
                if started then
                    if verbosity == "debug" or (verbosity == "normal"
                        and label ~= "WAIT_ENTITIES" and label ~= "COOLDOWN"
                        and label ~= "READY" and label ~= "MOVING") then
                        note("AutoExp: " .. phase)
                    end
                end
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
        local function clock()
            return type(getEpoch) == "function" and getEpoch() or os.time()
        end

        -- Prefer the stored mapper number, but allow old profiles that only
        -- contained the GMCP hash. Never trust a stale map number after a remap.
        local function mapped_shelter(p)
            if not p or not valid_id(p.safeRoom) then return nil end
            local function verified(id)
                return type(id) == "number" and id > 0 and id % 1 == 0
                    and type(getRoomHashByID) == "function"
                    and getRoomHashByID(id) == p.safeRoom and id or nil
            end
            return verified(p.safeMap) or verified(
                type(getRoomIDbyHash) == "function" and getRoomIDbyHash(p.safeRoom) or nil)
        end

        local function restore_native_retreat()
            if not native_retreat then return end
            local saved = native_retreat
            native_retreat = nil
            if saved.cfg and type(saved.cfg.set) == "function" then
                -- Restore the player's original walker preferences, including
                -- the attack response (never leave "ignoruj" enabled).
                pcall(saved.cfg.set, saved.cfg, "walker", "przy_ataku", saved.attack)
                pcall(saved.cfg.set, saved.cfg, "walker", "opoznienie", saved.delay)
            end
            ctx:save("walker_restore", nil)
        end

        -- A client may have crashed in the middle of an emergency walk.
        -- Restore settings from the durable checkpoint before starting again.
        do
            local stale = ctx:saved("walker_restore", nil)
            local cfg = ctx.app and ctx.app.config
            if type(stale) == "table" and cfg and type(cfg.set) == "function" then
                if stale.attack ~= nil then pcall(cfg.set, cfg, "walker", "przy_ataku", stale.attack) end
                if stale.delay ~= nil then pcall(cfg.set, cfg, "walker", "opoznienie", stale.delay) end
                ctx:save("walker_restore", nil)
            end
        end

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
            if combat.room and combat.room~=room_id() then return nil,false end
            if combat.self_active==nil and type(combat.relations)~="table" then return nil,false end
            local active = bool(combat.self_active) or (type(combat.primary)=="string" and combat.primary~="")
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
            local found, count, best_rank, best_health = nil, 0, math.huge, nil
            local me = me_and_group()
            local current
            local combat = gmcp_api.combat() or {}
            local our_targets = {}
            for _, rel in ipairs(combat.relations or {}) do
                if me and tostring(rel.attacker) == tostring(me.id) then
                    local id = tostring(rel.defender or "")
                    if valid_id(id) then
                        our_targets[id] = true
                        current = id
                    end
                end
            end
            -- In multi-target combat relations the primary is the most
            -- meaningful current focus, provided it belongs to our attacks.
            local primary = tostring(combat.primary or "")
            if our_targets[primary] then current = primary end
            for _, e in ipairs(entities) do
                local id = e.id and tostring(e.id) or nil
                local friendly = bool(e.self) or e.relation == "self"
                    or e.relation == "group" or e.relation == "ally"
                    or e.group_role == "leader" or e.group_role == "member"
                    or (id and group_ids and group_ids[id])
                if e.kind == "npc" and not friendly and not bool(e.dead)
                    and contains(e.name, p.targets)
                    and not contains(e.name, p.avoid) then
                    count = count + 1
                    -- Overlapping names still use the longest matching rule;
                    -- only NPCs of the SAME list rank compete on wounded HP.
                    local rank, length = math.huge, 0
                    local name = normalized(e.name)
                    for index,pattern in ipairs(p.targets) do
                        pattern=normalized(pattern)
                        if name:find(pattern,1,true) and #pattern>length then
                            rank,length=index,#pattern
                        end
                    end
                    local hp,maxhp=tonumber(e.hp),tonumber(e.maxhp)
                    local health=hp and maxhp and maxhp>0
                        and math.max(0,math.min(1,hp/maxhp)) or nil
                    if id and valid_id(id) then
                        local better = not found or rank < best_rank
                        if found and rank == best_rank then
                            if health and best_health then
                                if health < best_health then better=true
                                elseif health == best_health then
                                    -- Same health: prefer confirmed focus, then stable ID.
                                    better = (id==current and tostring(found.id)~=current)
                                        or (id~=current and tostring(found.id)~=current
                                            and id<tostring(found.id))
                                end
                            elseif health then
                                better=true -- comparable GMCP HP wins over missing data
                            elseif not best_health then
                                better=(id==current and tostring(found.id)~=current)
                                    or (id~=current and tostring(found.id)~=current
                                        and id<tostring(found.id))
                            end
                        end
                        if better then found,best_rank,best_health=e,rank,health end
                    end
                end
            end
            return found, count, current
        end

        -- A combat target is not necessarily reachable: a guard may intercept
        -- 'zabij'. Align everyone on the ACTUAL target when the leader's
        -- priority change did not land. Never use this to command non-leaders.
        function safety.order_party_target(p, id, force)
            if not (p.partyAttack and started and not paused and not dry) or
                safety.blind or safety.dark or not valid_id(id) or not ready_entities() then return end
            local packet=gmcp_api.entities()
            local enemy
            for _,e in ipairs(packet.entities) do
                if tostring(e.id or "")==id and e.kind=="npc" and not bool(e.dead)
                    and e.relation~="self" and e.relation~="group"
                    and e.relation~="ally" then enemy=true;break end
            end
            if not enemy then return end
            local group=gmcp_api.group() or {}
            local members=type(group.members)=="table" and group.members or {}
            local me=me_and_group()
            if not me or tostring(group.leader)~=tostring(me.id) or
                os.time()<(safety.manual_party_until or 0) then return end
            local party,aligned=false,true
            local relations=(gmcp_api.combat() or {}).relations or {}
            for _,member in ipairs(members) do
                if not bool(member.self) and bool(member.here) and valid_id(tostring(member.id or "")) then
                    party=true
                    local matching,other=false,false
                    for _,rel in ipairs(relations) do
                        if tostring(rel.attacker)==tostring(member.id) then
                            if tostring(rel.defender)==id then matching=true else other=true end
                        end
                    end
                    if not matching or other then aligned=false end
                end
            end
            if not party or (not force and aligned) then return end
            local previous=safety.last_party_order
            if previous and previous.room==room_id() and previous.target==id
                and os.time()-previous.at<7 then return end
            safety.ordering=true
            local ok,err=pcall(ctx.send,ctx,"rozkaz druzynie zaatakowac "..id,true)
            safety.ordering=false
            if ok then
                safety.last_party_order={room=room_id(),target=id,at=os.time()}
            else
                note("AutoExp: nie udalo sie skierowac druzyny: "..tostring(err),"warn")
            end
        end

        local function attack_target(p, id, order_now)
            if not valid_id(id) then return false, "Niepoprawne ID celu" end
            safety.attacking=true
            local ok,err=pcall(ctx.send,ctx,"zabij "..id,true)
            safety.attacking=false
            if not ok then return false,tostring(err) end
            if not safety.dark and not paused and started and order_now then
                safety.order_party_target(p,id,true)
            end
            return true
        end
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
            safety.outgoing=command
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
        local function exit_command(direction)
            if type(direction) ~= "string" or direction == "" or direction:find("[;%c]") then return nil end
            return EXIT_COMMANDS[direction] or direction
        end
        safety.normalize=exit_command
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
                        local command = exit_command(direction)
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
            local safe = mapped_shelter(p)
            if from and safe and safe > 0 and type(getPath) == "function" then
                local ok, found = pcall(getPath, from, safe)
                if ok and found then
                    local path = type(speedWalkPath) == "table" and speedWalkPath or {}
                    local next_id = type(getRoomHashByID) == "function"
                        and getRoomHashByID(path[1]) or nil
                    if valid_id(next_id) then
                        for direction, hash in pairs(type(r.exits) == "table" and r.exits or {}) do
                            local command = exit_command(direction)
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
                    local command = exit_command(direction)
                    if command and hash == previous then return command, hash, "cofanie" end
                end
            end

            -- Priority 4: when neither safe route nor breadcrumb exists, an
            -- actual GMCP exit is safer than standing still in lethal combat.
            -- Avoid known dangerous rooms and loops; never invent an exit.
            local options = {}
            for direction, id in pairs(type(r.exits) == "table" and r.exits or {}) do
                local command = exit_command(direction)
                if command and (valid_id(id) or id == false) then
                    local n = emergency and emergency.visits[id] or 0
                    options[#options + 1] = {command=command, id=id, visits=n or 0}
                end
            end
            table.sort(options, function(a,b)
                if a.visits ~= b.visits then return a.visits < b.visits end
                if a.id ~= b.id then return tostring(a.id) < tostring(b.id) end
                return a.command < b.command
            end)
            if #options > 0 then return options[1].command, options[1].id, "wyjscie GMCP" end
            return nil
        end
        -- The enemy limit controls engagement. All live exits remain usable,
        -- including the only exit back to another occupied room.
        local function escape_exit(p,r,tried)
            local exits={}
            local attempts=skip_exit_history[r.id] or {}
            for exit,dest in pairs(r.exits or {}) do
                local command=exit_command(exit)
                if command and (valid_id(dest) or dest==false) and not tried[command] then
                    exits[#exits+1]={command=command,id=dest}
                end
            end
            table.sort(exits,function(a,b)
                local av,bv=attempts[a.command] or 0,attempts[b.command] or 0
                if av~=bv then return av<bv end
                if hazardous(a.id)~=hazardous(b.id) then return not hazardous(a.id) end
                local ar,br=recent_rooms[a.id] or -math.huge,recent_rooms[b.id] or -math.huge
                if ar~=br then return ar<br end
                return a.command<b.command
            end)
            local position=0
            for i,id in ipairs(p.route) do
                if id==r.id then position=i; break end
            end
            local from=mapper.current_room()
            for offset=1,#p.route do
                local target=p.route[(position+offset-1)%#p.route+1]
                if target~=r.id and not safety.visited[target] then
                    for _,option in ipairs(exits) do
                        if option.id==target then return option.command end
                    end
                    local dest=getRoomIDbyHash(target)
                    if from and dest and dest>0 and getPath(from,dest) and
                        type(speedWalkPath)=="table" and speedWalkPath[1] and type(getRoomHashByID)=="function" then
                        local next_id=getRoomHashByID(speedWalkPath[1])
                        for _,option in ipairs(exits) do
                            if valid_id(next_id) and option.id==next_id then return option.command end
                        end
                    end
                end
            end
            return exits[1] and exits[1].command
        end
        local function queue(delay)
            if not started or paused or pending then return end
            local generation=safety.generation
            pending = ctx:timer(delay or 0, function()
                if safety.generation~=generation then return end
                pending = nil
                if started and not paused then evaluate() end
            end)
        end
        local function halt(reason)
            patrol_leg=nil
            safety.generation=(safety.generation or 0)+1
            safety.dark,safety.awaiting,safety.manual_at,safety.manual_target_until=nil,nil,nil,nil
            safety.after_walk,safety.swim_until,safety.hp_since,safety.manual_party_until=nil,nil,nil,nil
            fatigue_rest=nil
            expected_manual = nil
            if pending then ctx:cancel(pending); pending = nil end
            cancel_economy_timers()
            economy_run, loot_run = nil, nil
            started, paused, dry = false, false, false
            fallback, fallback_count = nil, 0
            engaged_here = false
            recent_rooms, recent_room = {}, nil
            phase, pending_attack, move, escape, emergency = "OFF", nil, nil, nil, nil
            safety.priority_hold, safety.last_party_order = nil, nil
            post_combat_at = nil
            last_reason = reason or "Zatrzymano"
            if stop_ours == false and state.owns_walk then
                stop_ours = true
                walker.stop("AutoExp: stop")
                stop_ours = false
            end
            state.owns_walk = false
            restore_native_retreat()
            note("AutoExp: " .. last_reason)
        end
        local function pause(reason)
            patrol_leg=nil
            if not started or paused then return end
            fatigue_rest=nil
            expected_manual = nil
            safety.generation=(safety.generation or 0)+1
            paused = true
            safety.manual_at=nil
            if not safety.dark then fallback=nil end
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
            restore_native_retreat()
            move, pending_attack, escape, emergency = nil, nil, nil, nil
            safety.priority_hold, safety.last_party_order = nil, nil
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
        local DISCARD_DAMAGED = {
            "odloz zlamane bronie",
            "odloz zniszczone zbroje",
        }
        local function next_counted_loot(run)
            loot_timer = nil
            if loot_run ~= run or not started or paused then return end
            if room_id() ~= run.origin then
                pause("Lupy: pokoj zmienil sie podczas zbierania")
                return
            end
            if run.phase == "GROUND" then
                local item=run.list[run.item]
                if item then
                    run.item=run.item+1
                    local command="wez "..item
                    note("AutoExp LUP: "..command)
                    local ok,err=pcall(ctx.send,ctx,command)
                    if not ok then pause("Lupy: blad podnoszenia z ziemi: "..tostring(err));return end
                    loot_timer=ctx:timer(economy_command_delay(),function() next_counted_loot(run) end)
                    return
                end
                run.phase,run.item="TAKING",1
            end
            if run.phase == "TAKING" and run.corpse > run.count then
                -- Discard untradeable broken gear before reading encumbrance.
                -- Keep loot_run active: no patrol/trade departure mid-cleanup.
                run.phase, run.discard_index = "DISCARDING", 1
            end
            if run.phase == "DISCARDING" then
                local discard = DISCARD_DAMAGED[run.discard_index]
                if not discard then
                    loot_run = nil
                    note("AutoExp LUP: obsluzono " .. run.count ..
                        " cial; odlozono uszkodzone przedmioty (proby).")
                    local p = profile()
                    queue(tonumber(p and p.rules.economyWeightWait)
                        or DEFAULT.economyWeightWait)
                    return
                end
                run.discard_index = run.discard_index + 1
                note("AutoExp LUP: " .. discard)
                local ok, err = pcall(ctx.send, ctx, discard)
                if not ok then
                    pause("Lupy: blad odkladania uszkodzonego sprzetu: " .. tostring(err))
                    return
                end
                loot_timer = ctx:timer(economy_command_delay(), function()
                    next_counted_loot(run)
                end)
                return
            end
            if run.phase ~= "TAKING" then return end
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
            run.count, run.corpse, run.item, run.phase = count, 1, 1, "GROUND"
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
        -- A defeated enemy may have left instead of dying. With no physical
        -- corpses, `policz ciala` also returns this ordinary empty result.
        -- counted_corpses accepts it only during our pending count in this room.
        ctx:trigger([[^Nie widzisz tu niczego takiego\.$]],
            function() counted_corpses(0) end)
        local function begin_counted_loot(p, r)
            local list=unique_names(p.loot)
            for _,item in ipairs(list) do
                if #item>80 or item:find("[;%c]") then pause("Lupy: nieprawidlowa kategoria");return end
            end
            local run = {origin=r.id, list=list, phase="COUNTING"}
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
                begin_fallback("Brak lokacji na mapie: " .. tostring(id))
                return false
            end
            if current == destination then return true end
            if state.owns_walk then return false end
            if getRoomIDbyHash(room_id())~=current then
                pause("Pozycja mapy rozni sie od GMCP"); return false
            end
            if not getPath(current,destination) or type(speedWalkPath)~="table" or not speedWalkPath[1] then
                pause("Nie mozna potwierdzic pierwszego kroku trasy do "..id)
                return false
            end
            if purpose=="patrol" and not patrol_leg then patrol_leg={target=id,crossed={}} end
            local adjacent=tonumber(speedWalkPath[1])
            if adjacent~=destination then
                id=adjacent and getRoomHashByID(adjacent)
                if not valid_id(id) then pause("Nieznany identyfikator kroku"); return false end
                destination=adjacent
            end
            if purpose=="patrol" then
                if patrol_leg.crossed[id] then
                    pause("Mapa prowadzi ponownie z "..room_id().." do "..id..
                        " w drodze do punktu "..patrol_leg.target)
                    return false
                end
            else
                patrol_leg=nil
            end
            move = { id = id, map = destination, purpose = purpose, origin=room_id() }
            state.owns_walk = true -- BEFORE go: native walker emits synchronously
            announce(purpose == "safe" and "RETREAT" or "MOVING")
            local ok, reason = walker.go(destination)
            if not ok then
                move, state.owns_walk = nil, false
                if fallback then fallback.health=false end
                begin_fallback("Chodzik odmowil ruchu: " .. tostring(reason))
                return false
            end
            if ok == "tutaj" then
                move, state.owns_walk = nil, false
                queue(0)
            end
            return true
        end
        -- One native mapped step at a time. Even if combat stops the official
        -- walker, the next call replans from CONFIRMED mapper/GMCP position.
        local function start_native_retreat(p, r)
            local destination = mapped_shelter(p)
            if not destination then return false, "Brak zweryfikowanego numeru schronienia na mapie" end
            local from = mapper.current_room()
            local expected = type(getRoomIDbyHash) == "function"
                and getRoomIDbyHash(r.id) or nil
            if not from or from ~= expected then
                return false, "Pozycja mappera nie zgadza sie z GMCP"
            end
            if from == destination or state.owns_walk then return true end

            local nav = native_retreat
            local now = clock()
            if nav then
                if nav.origin ~= r.id then
                    nav.origin = r.id
                    nav.attempts = 0
                    nav.wait_from, nav.wait_target, nav.wait_until = nil, nil, nil
                    nav.visits[r.id] = (nav.visits[r.id] or 0) + 1
                    if nav.visits[r.id] > 3 then
                        pause("ALARM: odwrot chodzikiem wraca wielokrotnie do "..r.id)
                        return true
                    end
                end
                if nav.wait_until and now < nav.wait_until then
                    announce("RETREAT")
                    queue(math.max(0.05, nav.wait_until - now))
                    return true
                end
                nav.wait_from, nav.wait_target, nav.wait_until = nil, nil, nil
                if nav.attempts >= 4 then
                    pause("ALARM: chodzik 4 razy przerwal odwrot w tym samym pokoju ("..r.id..")")
                    return true
                end
            end

            if type(getPath) ~= "function" or not getPath(from, destination)
                or type(speedWalkPath) ~= "table" then
                return false, "Mapper nie zna trasy do schronienia"
            end
            local hop = tonumber(speedWalkPath[1])
            local hop_hash = type(getRoomHashByID) == "function"
                and hop and getRoomHashByID(hop) or nil
            if not hop or hop == from or not valid_id(hop_hash) then
                return false, "Brak potwierdzonego pierwszego pokoju trasy"
            end

            if not nav then
                local cfg = ctx.app and ctx.app.config
                if not cfg or type(cfg.get) ~= "function" or type(cfg.set) ~= "function" then
                    return false, "Nie mozna bezpiecznie zmienic ustawien chodzika"
                end
                local ok1, old_delay = pcall(cfg.get, cfg, "walker", "opoznienie")
                local ok2, old_attack = pcall(cfg.get, cfg, "walker", "przy_ataku")
                if not ok1 or not ok2 or old_delay == nil or old_attack == nil then
                    return false, "Nie udalo sie odczytac ustawien chodzika"
                end
                -- Save BEFORE editing; restore options even after Mudlet crash.
                ctx:save("walker_restore", {delay=old_delay, attack=old_attack})
                nav = {cfg=cfg, delay=old_delay, attack=old_attack,
                    origin=r.id, attempts=0, visits={[r.id]=1}}
                native_retreat = nav
                local ok3, changed_delay = pcall(cfg.set, cfg, "walker", "opoznienie", 0.6)
                local ok4, changed_attack = pcall(cfg.set, cfg, "walker", "przy_ataku", "ignoruj")
                if not ok3 or changed_delay ~= true or not ok4 or changed_attack ~= true then
                    restore_native_retreat()
                    return false, "Nie udalo sie ustawic awaryjnego tempa chodzika"
                end
                note("AutoExp: odwrot do /idz "..destination..
                     "; jeden krok na raz, 0.6 s, ponawianie po ataku.", "warn")
            end

            nav.attempts = nav.attempts + 1
            move = {id=hop_hash, map=hop, purpose="safe_native", origin=r.id}
            state.owns_walk = true -- walker emits started synchronously
            announce("RETREAT")
            local sent, result, detail = pcall(walker.go, hop)
            if not sent or result ~= true then
                state.owns_walk, move = false, nil
                restore_native_retreat()
                return false, "Chodzik odmowil kroku "..tostring(hop)..
                    ": "..tostring(detail or result)
            end
            return true
        end

        begin_fallback = function(reason)
            patrol_leg=nil
            if dry then pause("TEST: odwrot do saferoom: " .. reason); return end
            if fallback then return end
            fallback_count = math.min(fallback_count + 1, 5)
            fallback = { reason = reason, wait = 30 * fallback_count }
            pending_attack, post_combat_at, escape = nil, nil, nil
            cancel_economy_timers()
            economy_run, loot_run = nil, nil
            if state.owns_walk then
                stop_ours = true
                walker.stop("AutoExp: powrot do saferoom")
                stop_ours = false
            end
            state.owns_walk, move = false, nil
            note("AutoExp: " .. reason .. "; wracam do saferoom, odpoczywam i ponawiam patrol.", "warn")
            queue(0)
        end
        local function escape_avoided(p, r, name)
            patrol_leg=nil
            local now = os.time()
            safety.skipped[r.id]=true
            safety.visited[r.id]=true
            if not escape or escape.origin ~= r.id then
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
                pause("Brak potwierdzenia ominiecia lokacji: " .. name)
                return
            end
            -- A pass can consist entirely of transit rooms.
            local complete=true
            for _,id in ipairs(p.route) do
                if not safety.visited[id] then complete=false; break end
            end
            if complete then
                safety.visited,safety.skipped={[r.id]=true},{[r.id]=true}
            end
            local command = escape_exit(p, r, escape.tried)
            if not command then
                pause("Brak dostepnego lub potwierdzonego przejscia z "..r.id.." ("..name..")")
                return
            end
            if dry then
                note("AutoExp TEST: omijam " .. name .. " -> " .. command)
                pause("Zakonczono test - zadnej komendy nie wyslano")
                return
            end
            escape.tries = escape.tries + 1

            local history = skip_exit_history[r.id] or {}
            history[command] = (history[command] or 0) + 1
            skip_exit_history[r.id] = history
            if history[command] > 2 and (history[command] % 3) == 0 then
                note("AutoExp: ponowny przejazd przez nieodpowiednia lokacje; sprawdz trase patrolu.", "warn")
            end
            escape.tried[command] = true
            escape.sent_at = now
            for exit,id in pairs(r.exits or {}) do
                if exit_command(exit)==command then escape.destination=id; break end
            end
            announce("AVOID_ESCAPE")
            local ok, err = send_owned_direction(command)
            if not ok then begin_fallback("Blad wyslania kroku omijania NPC: " .. tostring(err)) end
        end
        -- Emergency retreat remains available when an attack interrupts walking.
        -- Issue ONE mapped direction at a time and await Room.Info confirmation.
        -- This cannot overcome a server-side ban on fleeing from combat.
        local function retreat_wait(reason)
            pause("ALARM: "..reason.." ("..tostring(room_id())..")")
            fallback={reason=reason,wait=30}
            announce("INTERVENTION")
        end
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
                announce("RETREAT")
                return
            end
            local now = os.time()
            if not emergency then
                emergency = { destination = p.safeRoom, tries = 0, steps = 0,
                    fallback_steps = 0, visits = { [r.id] = 1 }, warned_fallback = false }
                pending_attack, post_combat_at, escape = nil, nil, nil
                note("AutoExp: Awaryjny odwrot do bezpiecznej lokacji, krok po kroku.", "warn")
            end
            if emergency.step and emergency.step.origin == r.id then
                if now - emergency.step.sent_at <
                    (tonumber(p.rules.safeMoveWait) or DEFAULT.safeMoveWait) then
                    announce("EMERGENCY_RETREAT")
                    return
                end
                if emergency.tries >=
                    (tonumber(p.rules.safeMoveTries) or DEFAULT.safeMoveTries) then
                    retreat_wait("Serwer nie potwierdzil ruchu. Przejmij sterowanie, jesli to mozliwe")
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
                if not ok then retreat_wait("Blad powtorzenia kroku awaryjnego: " .. tostring(err)) end
                return
            end
            -- A new room is now confirmed. Plan just the next step, not a
            -- multi-command speedwalk that might race against GMCP combat.
            emergency.step, emergency.tries = nil, 0
            if (emergency.visits[r.id] or 0) > 2 then
                retreat_wait("Wykryto petle odwrotu; nie bede biegac miedzy pokojami")
                return
            end
            local command, next_id, source = emergency_step(p, r)
            if not command then
                retreat_wait("Brak dostepnego wyjscia GMCP podczas odwrotu")
                return
            end
            if source ~= "GMCP" and source ~= "mapper" then
                if emergency.fallback_steps >= (tonumber(p.rules.emergencyFallbackSteps)
                    or DEFAULT.emergencyFallbackSteps) then
                    retreat_wait("Wyczerpano limit szukania drogi do schronienia")
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
            if not ok then retreat_wait("Blad wyslania kroku awaryjnego: " .. tostring(err)) end
        end
        local function darkness(reason)
            safety.blind=true
            if not started or safety.dark then return end
            safety.dark_visits={}
            safety.dark_native_warning=nil
            safety.dark=reason
            if paused then return end
            local in_flight=(move and move.sent and move) or safety.after_walk or (emergency and emergency.step) or (escape and escape.sent_at and escape)
                or (economy_run and economy_run.direct_step)
            if in_flight and not fatigue_rest and (in_flight.origin or observed_room)==room_id() then
                safety.awaiting={origin=room_id(),until_at=os.time()+25}
            end
            if pending then ctx:cancel(pending); pending=nil end
            safety.generation=(safety.generation or 0)+1
            if state.owns_walk then
                stop_ours=true; walker.stop("AutoExp: ciemnosc"); stop_ours=false
            end
            state.owns_walk=false
            move,escape,emergency,pending_attack,post_combat_at=nil,nil,nil,nil,nil
            cancel_economy_timers()
            economy_run,loot_run=nil,nil
            fallback={reason=reason,stop_on_arrival=true}
            announce("DARK_RETREAT")
            note("Ciemnosc: odwrot do schronienia i zatrzymanie.", "warn")
            queue(0)
        end
        local function dark_return(p,r)
            local key=r.key or r.id
            local step=safety.awaiting
            if step then
                if step.origin==r.id then
                    if os.time()>=step.until_at then
                        pause("ALARM: brak potwierdzenia ruchu w ciemnosci w "..key); announce("INTERVENTION")
                    end
                    return
                end
                safety.awaiting=nil
                if (step.destination and step.destination~=r.id) or (step.key and step.key~=key) then
                    pause("ALARM: nieoczekiwana pozycja po kroku odwrotu: "..key); announce("INTERVENTION"); return
                end
            end
            if key==(p.safeKey or p.safeRoom) then
                halt("Ciemnosc: osiagnieto schronienie. Wymagany reczny start.")
                phase="DARK_STOP"; ui_refresh(); return
            end
            if state.owns_walk and native_retreat then
                announce("DARK_RETREAT")
                return
            end
            if not state.owns_walk and not safety.awaiting then
                local ok, why = start_native_retreat(p, r)
                if ok then return end
                if not safety.dark_native_warning then
                    safety.dark_native_warning = true
                    note("AutoExp: chodzik nie moze odwrocic w ciemnosci ("..tostring(why)..
                         "); probuje tylko potwierdzone przejscia GMCP.", "warn")
                end
            end
            local target=p.safeKey or p.safeRoom
            local command,dest,expected_key=safety.return_step(r,target)
            if not command then
                for exit,id in pairs(r.exits or {}) do
                    if id==p.safeRoom then command,dest,expected_key=exit,id,target; break end
                end
            end
            if not command and target==p.safeRoom and not r.instance then
                command,dest=known_step_toward(r,target)
            end
            if not command and type(getRoomIDbyHash)=="function" and type(getRoomHashByID)=="function" then
                local from,to=mapper.current_room(),getRoomIDbyHash(p.safeRoom)
                if from and to and to>0 and from==getRoomIDbyHash(r.id) and getPath(from,to)
                    and type(speedWalkPath)=="table" and speedWalkPath[1] then
                    local adjacent=getRoomHashByID(speedWalkPath[1])
                    for exit,id in pairs(r.exits or {}) do
                        if valid_id(adjacent) and id==adjacent then command,dest=exit,id; break end
                    end
                end
            end
            if not command or not exit_command(command) then
                pause("ALARM: brak potwierdzonej drogi odwrotu z "..key); announce("INTERVENTION"); return
            end
            if dry then pause("TEST: odwrot przez "..command); return end
            safety.dark_visits=safety.dark_visits or {}
            if safety.dark_visits[key] then
                pause("ALARM: powrot w ciemnosci prowadzi ponownie do "..key);announce("INTERVENTION");return
            end
            safety.dark_visits[key]=true
            safety.awaiting={origin=r.id,destination=dest,key=expected_key,until_at=os.time()+25}
            announce("DARK_RETREAT")
            local ok=send_owned_direction(exit_command(command))
            if not ok then pause("ALARM: blad kroku odwrotu z "..key) end
        end
        local function select_next(p, current)
            local route, now = p.route, os.time()
            local position = 0
            for i, id in ipairs(route) do
                if id == current then position = i; break end
            end
            -- Cykl stabilny: nie przeliczamy 200 tras przy kazdym GMCP.
            local minimum_wait, blocked = nil, false
            for step = 1, #route do
                local idx = ((position + step - 1) % #route) + 1
                local id = route[idx]
                local revisit = last_seen[id] and (last_seen[id] + p.rules.minRoomRevisit) or 0
                local eligible_at = revisit
                if hazardous(id) or safety.visited[id] then
                    blocked = true
                elseif now >= eligible_at then
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
            return nil, minimum_wait, blocked
        end
        local function maybe_record(room_info)
            if not mapping or not room_info or not valid_id(room_info.id) then return end
            if not mapping.seen[room_info.id] then
                mapping.seen[room_info.id] = true
                mapping.route[#mapping.route + 1] = room_info.id
            end
        end
        evaluate = function()
            if destroyed then return end
            if hooks.before_start then
                local reason=hooks.before_start(profile())
                if reason then pause(reason);ui_refresh();return end
            end
            local p = profile()
            local r = room()
            if not p or not r or not valid_id(r.id) then
                pause("Brak profilu lub lokacji GMCP")
                return
            end
            -- Guard against triggering on stale room/Entities after a fast move.
            if safety.after_walk and not safety.dark then
                if r.id==safety.after_walk.origin then
                    if os.time()>=safety.after_walk.deadline then
                        pause("ALARM: niepotwierdzone cofniecie chodzika")
                    end
                    return
                end
                safety.after_walk=nil
            end
            if state.owns_walk and move and r.id~=move.origin and not safety.dark then
                return
            end
            if safety.swim_until and os.time()<safety.swim_until and not safety.dark then
                return
            end
            if observed_room ~= r.id then
                observed_room, entities_ready = r.id, false
                attacked_in_room = {}
                safety.priority_hold, safety.last_party_order = nil, nil
                last_visited = os.time()
            end
            if safety.dark and not fatigue_rest then dark_return(p,r); return end
            if safety.blind and not safety.dark then
                announce("WAIT_VISIBILITY"); last_reason="Brak potwierdzenia widocznosci"; return
            end
            local hp, weakest, group_ids = health()
            if not hp then
                safety.hp_since=safety.hp_since or os.time()
                if os.time()-safety.hp_since>=30 then pause("Brak aktualnego HP od 30 s");return end
                announce("WAIT_HP"); return
            end
            safety.hp_since=nil
            local danger = hp <= p.rules.retreatHP or
                (weakest and weakest.hp <= p.rules.retreatHP)
            local active, foreign = combat_status(group_ids)
            if active then engaged_here = true end
            if fatigue_rest then
                local rest=fatigue_rest
                local fatigue=tonumber((gmcp_api.vitals() or {}).fatigue)
                local strength=fatigue and fatigue>=0 and fatigue<=100 and 100-fatigue or nil
                local threshold=active==true and 10 or 30
                if not rest.fresh or active==nil or not strength or strength<threshold or os.time()<rest.until_at then
                    announce("REST_FATIGUE")
                    last_reason="Odpoczynek: sily "..tostring(strength or "?").."%, wymagane "..threshold.."%."
                    return
                end
                fatigue_rest=nil;announce(rest.phase)
                if safety.dark then dark_return(p,r);return end
                note("AutoExp: odzyskano sily; ponawiam ocene ruchu.")
                if rest.move and not active and not danger and not economy_run and not emergency and not escape then
                    local goal=rest.move.purpose=="patrol" and patrol_leg and patrol_leg.target or rest.move.id
                    move_to(goal,rest.move.purpose);return
                end
            end
            if danger and not fallback then
                begin_fallback("Prog odwrotu HP")
                if paused then return end
                if fallback then fallback.health=true end
            end
            if fallback then
                if r.id==p.safeRoom and p.safeKey and (r.key or r.id)~=p.safeKey then
                    retreat_wait("Niewlasciwa instancja schronienia")
                    return
                end
                if r.id ~= p.safeRoom then
                    if state.owns_walk and native_retreat then
                        announce("RETREAT")
                    elseif not state.owns_walk then
                        local ok, why = start_native_retreat(p, r)
                        if not ok then
                            -- If the official mapper cannot supply a path, use
                            -- the older evidence-based single-step rescue, but
                            -- never allow its previous unbounded A-B oscillation.
                            if not fallback.native_warned then
                                fallback.native_warned = true
                                note("AutoExp: /idz do schronienia niedostepny ("..
                                     tostring(why).."); awaryjne kroki GMCP.", "warn")
                            end
                            if active == false then
                                -- Outside combat the ordinary native patrol
                                -- walker can retreat without a temporary
                                -- override of the user's attack setting.
                                move_to(p.safeRoom, "safe")
                            else
                                retreat_in_combat(p, r)
                            end
                        end
                    end
                    return
                end
                if native_retreat and not state.owns_walk then restore_native_retreat() end
                local fatigue=tonumber((gmcp_api.vitals() or {}).fatigue)
                local missing=active==nil or not ready_entities() or not fatigue or fatigue<0 or fatigue>100
                if missing then
                    fallback.missing_since=fallback.missing_since or os.time()
                    if os.time()-fallback.missing_since>=30 then
                        retreat_wait("Brak aktualnych danych regeneracji: "..last_reason)
                        return
                    end
                else fallback.missing_since=nil end
                if not fallback.poll_at or os.time() >= fallback.poll_at then
                    fallback.poll_at = os.time() + 5
                    if not ready_entities() and type(gmcp_api.refresh_entities) == "function" then
                        pcall(gmcp_api.refresh_entities)
                        if not started or paused or not fallback then return end
                    end
                end
                emergency = nil
                -- The configured shelter is trusted, even with a weak aggressor.
                -- Keep defensive tactics available; never initiate an EXP fight here.
                if active ~= false then
                    fallback.ready_at = nil
                    announce(active and "COMBAT" or "WAIT_COMBAT")
                    last_reason = active and "Saferoom: GMCP nadal wskazuje walke." or "Saferoom: brak danych walki GMCP."
                    return
                end
                local reason
                if hp < p.rules.returnHP then reason="HP postaci "..hp.."%, wymagane "..p.rules.returnHP.."%."
                elseif weakest and weakest.hp < p.rules.returnHP then reason="HP druzyny: "..weakest.name.." "..weakest.hp.."%, wymagane "..p.rules.returnHP.."%."
                elseif not fatigue or fatigue < 0 or fatigue > 100 then reason="Brak poprawnych danych zmeczenia GMCP."
                elseif fatigue > 70 then reason="Sily "..(100-fatigue).."%, wymagane 30%."
                elseif not ready_entities() then reason="Brak aktualnych istot saferoom; odswiezam GMCP." end
                if reason then
                    fallback.ready_at = nil
                    announce("RECOVERY")
                    last_reason="Saferoom: "..reason
                    return
                end
                fallback.ready_at = fallback.ready_at or (os.time() + fallback.wait)
                if os.time() < fallback.ready_at then
                    announce("RECOVERY")
                    last_reason="Saferoom: regeneracja zakonczona; wznowienie za "..(fallback.ready_at-os.time()).." s."
                    return
                end
                note("AutoExp: regeneracja i oczekiwanie zakonczone; wznawiam patrol.")
                fallback, escape = nil, nil
                skip_exit_history = {}
                announce("READY")
            end
            -- When low HP forces retreat while in combat, safety takes
            -- precedence over ordinary avoided-NPC routing and attacking.
            if emergency then
                retreat_in_combat(p, r)
                return
            end
            -- A commercial trip owns its destination across incidental fights.
            -- The native walker stops on attack, so resume via confirmed
            -- GMCP single steps until ordinary walking becomes possible.
            -- Critical HP still takes priority above this branch.
            if economy_run then
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
            if active == nil then announce("WAIT_COMBAT"); return end
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
            local target, npc_count, current_target = target_info(p, group_ids)
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
            -- A room excluded in this pass remains transit-only until the next pass.
            if hazardous(r.id) then
                escape_avoided(p,r,"pominieta w tym obiegu"); return
            end
            escape = nil
            if not has_hazards() then
                skip_exit_history = {}
            end
            if active then
                post_combat_at = nil
                announce("COMBAT")
                if pending_attack and pending_attack.room==r.id then
                    if tostring(pending_attack.id)==current_target then
                        -- GMCP confirmed that our attack actually switched.
                        pending_attack=nil
                        safety.priority_hold=nil
                    elseif os.time()-pending_attack.since<p.rules.attackWait
                        and not pending_attack.blocked then
                        -- Keep the actual party focus while waiting, but do not
                        -- send a second 'zabij' until this one has settled.
                        safety.order_party_target(p,current_target,false)
                        return
                    else
                        -- Interception / missing confirmation is NOT a reason to
                        -- flee. The current combat stays in charge for 15 s.
                        local failed=pending_attack
                        pending_attack=nil
                        safety.priority_hold={room=r.id,id=failed.id,until_at=os.time()+15}
                        note("AutoExp: cel "..failed.id..
                             " niedostepny lub oslaniany; kontynuuje walke z biezacym celem.", "warn")
                    end
                end
                if safety.priority_hold and safety.priority_hold.room==r.id then
                    if safety.priority_hold.until_at>os.time() and current_target
                        and target and tostring(target.id)==safety.priority_hold.id then
                        -- This is a temporary tactical choice, not a permanent
                        -- blacklist: a dead guard may expose the priority later.
                        target=nil
                    elseif safety.priority_hold.until_at<=os.time() then
                        safety.priority_hold=nil
                    end
                end
                if target and tostring(target.id)~=current_target and
                    os.time()>=(safety.manual_target_until or 0) then
                    if dry then return end
                    pending_attack={id=tostring(target.id),room=r.id,since=os.time()}
                    local ok,err=attack_target(p,tostring(target.id),false)
                    if not ok then
                        pending_attack=nil
                        note("AutoExp: nie udalo sie zmienic celu: "..tostring(err),"warn")
                    end
                else
                    pending_attack=nil
                    -- Align the party with the currently fought NPC. A failed
                    -- attempt to reach the best-ranked enemy does not override
                    -- the server's real combat target.
                    safety.order_party_target(p,current_target,false)
                end
                return
            end
            if phase == "COMBAT" then
                post_combat_at = os.time()
                announce("POST_COMBAT")
            end
            if post_combat_at then
                -- Only loot collection needs a post-combat grace period.
                -- With zarobek off (or an empty loot list), GMCP already
                -- confirms the fight ended: advance on THIS evaluation.
                local collecting = p.economy and p.economy.enabled and not dry
                    and type(p.loot) == "table" and #p.loot > 0
                if collecting then
                    local grace = tonumber(p.rules.economyLootGrace) or DEFAULT.economyLootGrace
                    if os.time() - post_combat_at < grace then return end
                end
                post_combat_at = nil
                if collecting then
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
                -- When a corpse has already disappeared from Room.Entities,
                -- the opening target was resolved without a fresh Combat.State:
                -- continue to the next enemy instead of pausing.
                local still_here=false
                for _,e in ipairs(gmcp_api.entities().entities or {}) do
                    if tostring(e.id or "")==tostring(pending_attack.id)
                        and not bool(e.dead) then still_here=true; break end
                end
                if still_here then
                    -- No combat and target still alive: this is not a reason
                    -- to flee, but neither may we blindly keep issuing kills.
                    pause("Nie potwierdzono rozpoczecia walki z "..pending_attack.id..
                        "; sprawdz cel lub oslone.")
                    return
                end
                pending_attack=nil
                announce("READY")
            end
            if r.id == p.safeRoom and hp < p.rules.returnHP then
                announce("RECOVERY"); return
            end
            if weakest and weakest.hp < p.rules.returnHP and r.id == p.safeRoom then
                announce("RECOVERY"); return
            end
            if target and os.time()<(safety.manual_target_until or 0) then announce("MANUAL_TARGET");return end
            if target then
                if dry then
                    note("AutoExp TEST: atak -> " .. target.name .. " [" .. target.id .. "]")
                    pause("Zakonczono test - zadnej komendy nie wyslano")
                    return
                end
                announce("ENGAGING")
                engaged_here = true
                skip_exit_history = {}
                pending_attack = { id = target.id, room = r.id, since = os.time() }
                attacked_in_room[target.id] = true
                local ok, err = attack_target(p, target.id, true)
                if not ok then begin_fallback("Blad ataku: " .. tostring(err)); return end
                queue(0)
                return
            end
            safety.visited[r.id]=true
            local complete=true
            for _,id in ipairs(p.route) do
                if not safety.visited[id] and not hazardous(id) then complete=false; break end
            end
            if complete then
                if has_hazards() then
                    safety.pass_until=safety.pass_until or os.time()+math.max(1,p.rules.minRoomRevisit)
                    if os.time()<safety.pass_until then
                        announce("COOLDOWN");last_reason="Obieg zakonczony; czekam przed nastepnym.";return
                    end
                end
                safety.pass_until=nil
                safety.visited,safety.skipped={},{}
            end
            last_seen[r.id] = os.time()
            local next_id, wait_time, blocked
            if patrol_leg and patrol_leg.target~=r.id then
                next_id=patrol_leg.target
            else
                patrol_leg=nil
                next_id,wait_time,blocked=select_next(p,r.id)
            end
            if not next_id then
                if blocked and not wait_time then
                    pause("Koniec obiegu: pozostale punkty niedostepne bez przejscia przez zagrozenie")
                    return
                end
                if dry then
                    note("AutoExp TEST: brak gotowego pokoju / trasy")
                    pause("Zakonczono test")
                    return
                end
                announce("COOLDOWN")
                if not wait_time then pause("Koniec obiegu: nie ma dostepnej trasy patrolu") end
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
            if hooks.before_start then
                local reason = hooks.before_start(profile())
                if reason then note(reason, "warn"); return false end
            end
            if safety.blind or (room() and type(room().exits)=="table" and not next(room().exits)) then note("Brak widocznosci. Sprawdz swiatlo i odswiez lokacje.", "warn"); return false end
            if not started then
                session.elapsed, session.xp = 0, 0
            end
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
            observed_key=room() and (room().key or room().id)
            local entities = gmcp_api.entities()
            if type(entities) == "table" and entities.room == current then entities_ready = true end
            if not entities_ready then
                note("Nie ma swiezych danych Entities. Zrob krok / odswiez lokacje.", "warn")
                return
            end
            record_room(room())
            safety.observe(room())
            safety.skipped,safety.visited,safety.pass_until={},{},nil
            safety.hp_since=nil
            started, paused, dry = true, false, test_mode == true
            fallback, fallback_count = nil, 0
            pending_attack, move, post_combat_at, escape, emergency = nil, nil, nil, nil, nil
            safety.priority_hold, safety.last_party_order = nil, nil
            cancel_economy_timers()
            economy_run, loot_run = nil, nil
            attacked_in_room, last_seen, skip_exit_history = {}, {}, {}
            engaged_here = false
            recent_rooms, recent_room = {}, nil
            record_room(room())
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
        -- A shield interception is a tactical setback, not a reason to flee.
        ctx:trigger([[^Rzucasz sie na .+, lecz droge zastepuje ci .+\.$]],function()
            if not started or paused or not pending_attack or pending_attack.room~=room_id() then return end
            -- Leave a brief GMCP grace period before treating it as confirmed.
            pending_attack.blocked=true
            pending_attack.since=os.time()-(tonumber(profile() and profile().rules.attackWait) or 3)+1
            note("AutoExp: przeciwnik oslania priorytet; zostaje przy rzeczywistym celu.", "warn")
            queue(1)
        end)
        ctx:trigger([[^[ >]*Ciemne miejsce\.$]],function()
            safety.text_dark=room() and (room().key or room().id)
            safety.relit=nil; darkness("Ciemne miejsce")
        end)
        ctx:on("chimera.lamp.changed",function(event)
            if event and event.lit==false then
                safety.text_dark=room() and (room().key or room().id)
                safety.relit=nil; darkness("Lampa zgasla")
            elseif event and event.lit==true then safety.relit=true end
        end)
        ctx:trigger([[^[ >]*Umierasz\.$]],function()
            halt("Smierc postaci")
            if hooks.on_stop then hooks.on_stop() end
            safety.edges,safety.last,safety.outgoing={},nil,nil
            known_exits,trail={},{}
            state.emergency_known_exits,state.emergency_trail=known_exits,trail
        end)
        ctx:on("sysDataSendRequest",function(_,command)
            if type(command)~="string" then return end
            command=normalized(command)
            local here=room()
            if state.owns_walk and move and command~="stan" then move.sent=true end
            for exit in pairs(here and here.exits or {}) do
                if command==exit or command==exit_command(exit) then
                    safety.outgoing=command
                    break
                end
            end
            if not safety.ordering and command:match("^rozkaz%s+druzynie%s+zaatakowac%s") then
                safety.manual_party_until=os.time()+15
            end
            if command:match("^zabij%s") and not safety.attacking then
                safety.manual_target_until=os.time()+15
            end
        end)
        ctx:on("chimera.room.info", function(r)
            if not r or not r.id then return end
            local previous=safety.last
            local same_room = previous and previous.key == (r.key or r.id)
            local p = profile()
            local exp_room = started and not economy_run and p and
                (function()
                    for _, id in ipairs(p.route) do
                        if id == r.id then return true end
                    end
                    return false
                end)()
            if next(r.exits or {}) then
                if not safety.text_dark or safety.text_dark~=(r.key or r.id) or safety.relit then
                    safety.blind=false; safety.text_dark=nil; safety.relit=nil
                end
            elseif exp_room and same_room and next(previous.exits or {}) then
                darkness("Zniknely wyjscia GMCP")
            elseif not safety.dark then
                -- A different room (notably on a shop/bank route) may have
                -- an empty GMCP exits list without the light going out.
                safety.blind = exp_room
            end
            safety.observe(r)
            if safety.dark and paused and phase=="INTERVENTION" and not safety.awaiting then
                local p=profile()
                local key=r.key or r.id
                if p and (key==(p.safeKey or p.safeRoom) or
                    (not (safety.dark_visits or {})[key] and safety.return_step(r,p.safeKey or p.safeRoom))) then
                    paused=false
                end
            end
            record_room(r)
            if started and not paused then queue(0) end
            maybe_record(r)
        end)
        ctx:trigger([[^[ >]*Zaczynasz plynac.*$]],function()
            safety.swim_until=os.time()+25
        end)
        ctx:on("chimera.room.changed", function(r)
            safety.swim_until=nil
            if safety.manual_at then safety.manual_confirmed=true end
            expected_manual = nil -- room has changed; step ownership expired
            record_room(r)
            -- The changed event has only {id,how,...}; complete exits live in
            -- gmcp.room() and were updated before official Chimera emitted it.
            local latest = room()
            if latest then safety.observe(latest) end
            local key=latest and (latest.key or latest.id)
            if latest and observed_room==latest.id and observed_key and observed_key~=key then
                observed_key=key;entities_ready=false
                pause("Zmiana instancji lokacji: przejmij sterowanie.")
                ui_refresh();return
            end
            observed_key=key
            entities_ready=false
            if r and latest and latest.id == r.id then record_room(latest) end
            local late_native = native_retreat and r and native_retreat.wait_from
                and native_retreat.wait_target == r.id
                and clock() <= (native_retreat.wait_until or 0) + 0.2
            if late_native then
                native_retreat.wait_from, native_retreat.wait_target, native_retreat.wait_until = nil, nil, nil
                -- The earlier retry timer belongs to the PREVIOUS room. A
                -- confirmed late arrival can replan immediately, not in 3 s.
                if pending then ctx:cancel(pending); pending = nil end
            end
            if emergency and r and valid_id(r.id) then
                emergency.visits[r.id] = (emergency.visits[r.id] or 0) + 1
            end
            local was_escaping = escape and r and r.id ~= escape.origin
            local was_emergency = emergency and emergency.step and r
                and r.id ~= emergency.step.origin
            if was_emergency and valid_id(emergency.step.destination) and r.id ~= emergency.step.destination then
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
                if escape.destination and r.id~=escape.destination then
                    pause("Nieoczekiwana lokacja po kroku omijania: "..r.id); return
                end
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
                safety.priority_hold, safety.last_party_order = nil, nil
                last_visited = os.time()
            end
            maybe_record(room())
            if started and not paused and not state.owns_walk then
                -- Manual navigation while running is not treated as a patrol step.
                if r and r.how == "reczny" and not was_escaping
                    and not was_emergency and not was_trade_step
                    and not late_native and not safety.dark then
                    pause("Wykryto ruch reczny gracza")
                    safety.manual_at=os.time(); safety.manual_confirmed=true
                    announce("MANUAL_MOVE")
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
        ctx:on("chimera.char.vitals", function()
            if fatigue_rest then fatigue_rest.fresh=true end
            queue(0)
        end)
        ctx:on("chimera.combat.state", function() queue(0) end)
        ctx:on("chimera.group.state", function(packet)
            local ids = {}
            for _, member in ipairs(packet and packet.members or {}) do
                if member.id and not bool(member.self) then ids[tostring(member.id)] = true end
            end
            if started and not paused and not safety.dark and last_group then
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
            if move.purpose=="patrol" and patrol_leg then
                patrol_leg.crossed[move.origin]=true
                if move.id==patrol_leg.target then patrol_leg=nil end
            end
            local native_hop = move.purpose == "safe_native"
            state.owns_walk = false
            move = nil
            if native_hop then
                if native_retreat then
                    native_retreat.wait_from = nil
                    native_retreat.wait_target = nil
                    native_retreat.wait_until = nil
                end
                if room_id() == (profile() and profile().safeRoom) then
                    restore_native_retreat()
                end
                announce("RETREAT")
                queue(0.6)
            else
                restore_native_retreat()
                announce("WAIT_ENTITIES")
                queue(0)
            end
            last_visited = os.time()
        end)
        ctx:on("chimera.walk.stopped", function(event)
            external_walk = false
            if not state.owns_walk or stop_ours then return end
            local last = move
            local native_hop = native_retreat and last and last.purpose == "safe_native"
            local interrupted_attack = event and event.reason == "atak"

            if native_hop then
                state.owns_walk, move = false, nil
                if interrupted_attack then
                    local nav = native_retreat
                    -- The MUD may confirm a step AFTER its walker stops.
                    -- Wait for Room.Info instead of dispatching a second direction.
                    if last.sent and last.origin == room_id() then
                        nav.wait_from, nav.wait_target = last.origin, last.id
                        nav.wait_until = clock() + 3
                    else
                        nav.wait_from, nav.wait_target = nil, nil
                        nav.wait_until = clock() + 0.6
                    end
                    announce("RETREAT")
                    note("AutoExp: chodzik przerwany atakiem; przelicze kolejny krok po GMCP.", "warn")
                    queue(0.6)
                    return
                end
                restore_native_retreat()
                if started and not paused then
                    retreat_wait("Chodzik przerwal awaryjny krok: "..
                        tostring(event and event.reason or "przerwanie reczne"))
                end
                return
            end

            if interrupted_attack and last and last.sent and last.origin==room_id() then
                safety.after_walk={origin=room_id(),deadline=os.time()+25}
            end
            state.owns_walk = false
            move = nil
            restore_native_retreat()
            if started and not paused then
                if fallback then fallback.health=false end
                if interrupted_attack then
                    local cfg=ctx.app and ctx.app.config
                    if cfg and type(cfg.get)=="function" then
                        local ok,mode=pcall(cfg.get,cfg,"walker","przy_ataku")
                        if ok and mode=="cofnij" then
                            safety.after_walk={origin=room_id(),deadline=os.time()+25}
                        end
                    end
                    if economy_run then
                        economy_run.combat_transit = true
                        note("AutoExp HANDEL: atak przerwal chodzik; zachowuje cel kursu i kontynuuje krokami GMCP.", "warn")
                    end
                    queue(0)
                else
                    if event and event.reason then
                        begin_fallback("Chodzik przerwany: " .. tostring(event.reason))
                    else
                        pause("Chodzik przerwany recznie")
                    end
                end
            end
        end)
        ctx:on("chimera.session.end", function()
            halt("Rozlaczono - automat zatrzymany")
            known_exits,trail={},{}
            state.emergency_known_exits,state.emergency_trail=known_exits,trail
            safety.last,safety.blind,safety.edges,safety.outgoing,safety.text_dark=nil,nil,{},nil,nil
        end)
        ctx:trigger([[^Jestes tak zmeczon[ay], ze nie mozesz isc w tym kierunku\.$]],function()
            if not started or paused or dry or fatigue_rest then return end
            local step=expected_manual
            local own_step=step and step.room==room_id() and os.time()-step.time<=5
            if not state.owns_walk and not own_step and not safety.awaiting then return end
            safety.awaiting=nil
            if safety.dark_visits and room() then safety.dark_visits[room().key or room_id()]=nil end
            fatigue_rest={fresh=false,until_at=os.time()+2,phase=phase,move=move}
            if state.owns_walk then
                stop_ours=true;walker.stop("AutoExp: odpoczynek po odmowie ruchu");stop_ours=false
                state.owns_walk=false;move=nil
            end
            -- An explicit refusal is not an unconfirmed movement attempt.
            if emergency and emergency.step then
                emergency.tries=math.max(0,emergency.tries-1);emergency.step.sent_at=-math.huge
            end
            if economy_run and economy_run.direct_step then
                economy_run.direct_step.tries=math.max(0,economy_run.direct_step.tries-1)
                economy_run.direct_step.sent_at=-math.huge
            end
            if escape and own_step then
                escape.sent_at=nil;escape.tries=math.max(0,escape.tries-1);escape.tried[step.direction]=nil
                local history=skip_exit_history[room_id()]
                if history then history[step.direction]=math.max(0,(history[step.direction] or 0)-1) end
            end
            expected_manual=nil
            announce("REST_FATIGUE");note("AutoExp: odmowa ruchu ze zmeczenia; czekam na sily.","warn")
            queue(0)
        end)
        ctx:on("chimera.step.manual", function(manual)
            if safety.manual_at then safety.manual_at=os.time();safety.manual_confirmed=false end
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
            announce("MANUAL_MOVE")
            safety.manual_at=os.time();safety.manual_confirmed=false
        end)
        ctx:timer(1, function()
            session_clock()
            if safety.manual_at and safety.manual_confirmed and paused and not external_walk and os.time()-safety.manual_at>=3
                and ready_entities() and room() and room().id==observed_room then
                safety.manual_at=nil
                paused=false
                announce("READY")
            end
            if started and not paused then queue(0) end
        end, true)
        ctx:cleanup(function()
            destroyed = true
            cancel_economy_timers()
            economy_run, loot_run = nil, nil
            if state.owns_walk then walker.stop("AutoExp: przeladowanie") end
            state.owns_walk = false
        end)
        -- XP awarded for our party's kills; session-only. Captures server
        -- '[4120xp]' markers on kill lines, not nominal mob XP estimates.
        ctx:trigger([[^(?:Zabilas|Zabiles|.+ zabil(?:a|) .+) .+ \[([0-9]+)xp\]$]], function()
            if not started or paused or dry then return end
            local value = type(matches)=="table" and tonumber(matches[2])
            if value and value > 0 and value < 100000000 then
                session.xp = session.xp + value
                ui_refresh()
            end
        end)
        -- Commands intentionally share the old /exp interface only after the
        -- OLD XML package has been disabled. New /exp endpoints are explicit.
        local function command(name, args, fn, help)
            local function invoke(arg)
                if destroyed then return false end
                local result = fn(arg)
                ui_refresh()
                return result
            end
            requests[name] = invoke
            ctx:command{ "exp " .. name, args = args, help = help or "AutoExp 5", fn = invoke }
        end
        -- Console-first UI: native Mudlet cechoLink when available, ordinary
        -- text fallback in CI / terminal clients. Never inject profile names
        -- into executable Lua: clickable links use callback closures.
        local function ui_line(value)
            if type(cecho) == "function" then
                cecho("<white>" .. tostring(value) .. "\n")
            else
                ctx.log.info(tostring(value))
            end
        end
        local function ui_link(label, alias, hint)
            if type(cechoLink) == "function" then
                local ok = pcall(cechoLink, "<cyan>" .. label .. "<reset>",
                    function()
                        if type(expandAlias) == "function" then
                            expandAlias(alias, false)
                        end
                    end, hint or alias, true)
                if ok then return end
            end
            ui_line(label .. " (" .. alias .. ")")
        end
        local function ui_row(name, command_name, explanation)
            ui_link("[ " .. name .. " ]", "/exp " .. command_name, explanation)
            ui_line("  " .. explanation)
        end
        local function nearest_profiles(limit)
            local from = mapper.current_room()
            local result = {}
            if type(from) ~= "number" or type(getRoomIDbyHash) ~= "function"
                or type(walker.cost) ~= "function" then return result end
            for key,p in pairs(areas) do
                local best
                for _, hash in ipairs(p.route or {}) do
                    local id = getRoomIDbyHash(hash)
                    if type(id) == "number" and id > 0 then
                        local distance
                        if id == from then
                            distance = 0
                        else
                            local ok,cost = pcall(walker.cost, from, id)
                            if ok and type(cost) == "number" and cost >= 0
                                and cost < math.huge then distance = cost end
                        end
                        if distance and (not best or distance < best) then best = distance end
                    end
                end
                if best then result[#result + 1] = {key=key, name=p.name, cost=best} end
            end
            table.sort(result, function(a,b)
                if a.cost ~= b.cost then return a.cost < b.cost end
                return a.name < b.name
            end)
            while #result > limit do table.remove(result) end
            return result
        end
        local function panel(section)
            local p=profile()
            section=normalized(section)
            ui_line("---- CHIMERA XP 0.7.0-beta.38 | "..(section=="" and "PANEL" or section:upper()).." ----")
            if section == "" then
                ui_line("Stan: "..(economy_run and "HANDEL/"..economy_run.stage or phase)..
                    " | Expowisko: "..(p and p.name or "brak"))
                ui_row("START", "start", "Uruchom patrol")
                ui_row("PAUZA / WZNOW", paused and "wznow" or "pauza",
                    paused and "Wznow wstrzymany patrol" or "Wstrzymaj")
                ui_row("STOP", "stop", "Zatrzymaj calkowicie")
                ui_line("Najblizsze expowiska (koszt trasy mappera):")
                local near=nearest_profiles(3)
                if #near==0 then ui_line("  Brak osiagalnych profili w mapie") end
                for _,item in ipairs(near) do
                    ui_link((item.key==selected and "* " or "  ")..item.name..
                        " ["..item.cost.."]", "/exp wybierz "..item.name,
                        "Wybierz to expowisko (patrol musi byc zatrzymany)")
                    if type(cechoLink) == "function" then ui_line("") end
                end
                ui_line("USTAWIENIA:")
                ui_row("Expowiska", "panel profile", "Wybor, mapa i bezpieczna lokacja")
                ui_row("Walka", "panel walka", "Cele, omijanie, liczba NPC")
                ui_row("Bezpieczenstwo", "panel bezpieczenstwo", "Progi HP i odwrot")
                ui_row("Lupy i handel", "panel handel", "Zbieranie, sklep, bank, tempo")
                ui_row("Komunikaty", "panel komunikaty", "Dyskretny / normalny / diagnostyka")
                ui_row("Historia", "log", "Ostatnie zdarzenia automatu")
                return
            end
            if section=="profile" then
                ui_line("Wybrano: "..(p and p.name or "brak")..
                    " | pokoi: "..(p and #p.route or 0))
                ui_line("Najblizsze:");for _,it in ipairs(nearest_profiles(3)) do
                    ui_link(it.name.." ("..it.cost..")", "/exp wybierz "..it.name,
                        "Ustaw aktywny profil")
                    if type(cechoLink)=="function" then ui_line("") end
                end
                ui_row("Wszystkie profile","obszary","Lista zapisanych expowisk")
                ui_row("Bezpieczna tutaj","bezpieczna","Ustaw obecny pokoj jako bezpieczny")
                ui_line("Dodaj profil: /exp mapuj NAZWA; ponow polecenie, aby zapisac")
            elseif section=="walka" then
                ui_line("Cele: "..(p and table.concat(p.targets,", ") or "brak"))
                ui_line("Omijane: "..(p and table.concat(p.avoid,", ") or "brak"))
                ui_line("Limit celow EXP w pokoju: "..(p and p.rules.maxEnemies or "-"))
                ui_row("Limit -","limit-", "Zmniejsz limit o 1 (min. 1)")
                ui_row("Limit +","limit+", "Zwieksz limit o 1 (maks. 20)")
                ui_line("Dodawanie: /exp cel TEKST | /exp unikaj TEKST")
                ui_line("Usuwanie: /exp cel- TEKST | /exp unikaj- TEKST")
                ui_line("Limit liczy TYLKO cele, nie zające i inne NPC.")
            elseif section=="bezpieczenstwo" then
                ui_line("Odwort HP: "..(p and p.rules.retreatHP or "-")..
                    "% | powrot HP: "..(p and p.rules.returnHP or "-").."%")
                ui_line("Bezpieczny pokoj GMCP: "..(p and tostring(p.safeRoom) or "brak")..
                        " | mapper: "..(p and tostring(mapped_shelter(p) or "brak") or "brak"))
                ui_row("Bezpieczna tutaj","bezpieczna","Zapisz obecna lokacje")
                ui_line("Zmiana progow: /exp hp 35 85")
                ui_line("Odwrot i alarmy maja pierwszenstwo przed handlem.")
            elseif section=="handel" then
                ui_line("Zarobek: "..(p and p.economy and p.economy.enabled and "WLACZONY" or "wylaczony"))
                ui_row("Wlacz handel","zarobek wlacz","Automatyczny sklep, bank i powrot")
                ui_row("Wylacz handel","zarobek wylacz","Wylacz automatyczne kursy")
                ui_line("Lupy: "..(p and table.concat(p.loot,", ") or "brak"))
                ui_line("Prog: "..(p and p.rules.economyLoadThreshold or 75)..
                    "% | Tempo: "..string.format("%.2f",economy_command_delay()).." s")
                ui_line("Dodaj/usun: /exp lup dodaj TEKST | /exp lup usun TEKST")
                ui_line("Próg: /exp zarobek prog 75 | Tempo: /exp zarobek tempo 0.7")
                ui_row("Sprawdz trase","zarobek trasa","Trasa do sklepu i banku (bez handlu)")
                ui_line("UWAGA: masowa sprzedaz obejmuje takze wlasny ekwipunek.")
            elseif section=="komunikaty" then
                ui_line("Tryb: "..verbosity)
                ui_row("Dyskretny","glosnosc quiet","Tylko istotne alerty")
                ui_row("Normalny","glosnosc normal","Etapy walki i handlu")
                ui_row("Diagnostyka","glosnosc debug","Pelny log stanow i krokow")
                ui_row("Historia","log","40 ostatnich zdarzen, nawet wyciszonych")
                ui_line("Alerty bezpieczenstwa zawsze pozostaja widoczne.")
            else
                ui_line("Nieznana sekcja. Dostepne: profile, walka, bezpieczenstwo, handel, komunikaty")
            end
            ui_link("[ Powrot do /exp ]", "/exp", "Glowny panel")
            if type(cechoLink)=="function" then ui_line("") end
        end
        local function print_log()
            ui_line("---- AUTOEXP | OSTATNIE ZDARZENIA ("..#event_log..") ----")
            for _,entry in ipairs(event_log) do
                ui_line(entry.time.." "..entry.msg)
            end
        end

        command("nazwa","<nowa nazwa>",function(value)
            if started then note("Zmiana nazwy wymaga /exp stop","warn");return end
            local p=profile()
            value=trim(value)
            if not p or value=="" or #value>80 or value:find("[%c;]") then
                note("Uzycie: /exp nazwa NOWA NAZWA","warn");return
            end
            local key=normalized(value)
            if areas[key] and key~=selected then note("Taka nazwa juz istnieje","warn");return end
            areas[selected]=nil
            p.name=value
            areas[key]=p
            selected=key
            remember()
            note("Zmieniono nazwe: "..value)
            ui_refresh()
        end)
        command("panel", "<sekcja>", panel)
        command("log", nil, print_log)
        command("glosnosc", "<quiet|normal|debug>", function(mode)
            mode=normalized(mode)
            if mode~="quiet" and mode~="normal" and mode~="debug" then
                note("Tryb: /exp glosnosc quiet | normal | debug","warn");return
            end
            verbosity=mode
            ctx:save("verbosity",mode)
            note("Komunikaty AutoExp: "..mode)
            panel("komunikaty")
        end)
        local function adjust_target_limit(step)
            if not allowed_config() then return end
            local p=profile()
            if not p then note("Wybierz expowisko", "warn");return end
            p.rules.maxEnemies=math.min(20,math.max(1,p.rules.maxEnemies+step))
            remember()
            panel("walka")
        end
        command("limit+",nil,function() adjust_target_limit(1) end)
        command("limit-",nil,function() adjust_target_limit(-1) end)
        local function print_status()
            local p = profile()
            ctx:report("AutoExp 5", {
                {"Wersja", "0.7.0-beta.38"},
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
        ctx:command{ "exp", help = "ChimeraXP - Geyser", fn = function() if not hooks.open or hooks.open()==false then panel("") end end }
        command("status", nil, print_status)
        command("pomoc", nil, function()
            ctx.log.info("/exp obszary | wybierz NAZWA | mapuj NAZWA | mapuj! NAZWA | mapuj-")
            ctx.log.info("/exp cel TEKST | cel- TEKST | unikaj TEKST | unikaj- TEKST")
            ctx.log.info("Limit NPC z /exp limit N liczy tylko cele /exp cel, nie inne zwierzeta; /exp unikaj dziala niezaleznie.")
            ctx.log.info("/exp bezpieczna | hp ODWROT POWROT | limit NPC | odnowa SEK | start | test | odwrot-test | pauza | wznow | stop")
            ctx.log.info("/exp import (jednorazowo ze starej bazy, tylko gdy w nowej brak profili)")
            ctx.log.info("/exp aktualizuj (pobierz najnowsza ChimeraXP z publicznego GitHuba)")
            ctx.log.info("/exp lup dodaj TEKST | lup usun TEKST | lup lista | zarobek prog 75 | zarobek diagnoza | zarobek trasa")
            ctx.log.info("Lupy: po walce policz ciala, wez TEKST z ziemi, potem wez TEKST z 1./2. ciala; nastepnie odloz zlamane bronie i zniszczone zbroje")
            ctx.log.info("/exp zarobek wlacz | zarobek wylacz | zarobek kurs (REALNY sklep-bank-powrot)")
            ctx.log.info("/exp zarobek tempo 0.7 (odstep polecen lupow, sprzedazy i banku: 0.3-3 s)")
            ctx.log.info("Sprzedaz: sprzedaj KATEGORIA z listy lupow profilu; kamienie cztery razy, pozostale raz; wem i wlm to globalne aliasy.")
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
        -- When an attack interrupts the native walker during a
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
        local function economy_sell_next(run)
            if economy_run~=run or not started or paused then return end
            if room_id()~=run.shop.hash then pause("Opuszczono sklep w czasie handlu");return end
            local category=run.sales[run.sale_index]
            if not category then
                note("AutoExp: wyslano sprzedaz kategorii lupow: "..table.concat(run.sales,", ").." (bez potwierdzenia serwera).", "warn")
                economy_travel(run,"TO_BANK",run.bank.hash)
                return
            end
            if not economy_do_send(run,"sprzedaj "..category) then return end
            run.sale_repeat=(run.sale_repeat or 0)+1
            local repeats=normalized(category)=="kamienie" and 4 or 1
            if run.sale_repeat>=repeats then
                run.sale_index=run.sale_index+1
                run.sale_repeat=0
            end
            economy_delay(run,"SALE_LOOT",economy_command_delay(),function() economy_sell_next(run) end)
        end
        process_economy=function(r, active)
            local run=economy_run
            if not run or state.owns_walk then return end
            if run.stage=="TO_SHOP" then
                if not economy_continue_route(run, r, active, run.shop.hash) then return end
                run.stage="SALE_LOOT";run.sale_index=1
                economy_sell_next(run)
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
            local sales=unique_names(profile().loot)
            if #sales==0 then pause("Zarobek: brak kategorii lupow do sprzedazy");return false end
            for _,category in ipairs(sales) do
                if #category>80 or category:find("[;%c]") then
                    pause("Zarobek: nieprawidlowa kategoria lupow");return false
                end
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
            local run={origin=r.id,shop=shop,bank=bank,sales=sales,
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
            note("EXP+ZAROBEK WLACZONY. Sprzedaz obejmuje niesione przedmioty kategorii z listy lupow profilu.", "warn")
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
            note("TEST REALNY: sprzedaje niesione przedmioty kategorii z listy lupow profilu. /exp stop przerwie kurs.", "warn")
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
            local map = mapped_shelter(p)
            if map and mapper.current_room() and type(getPath) == "function"
                and getPath(mapper.current_room(), map) then
                note("AutoExp TEST ODWROTU: /opoz 0.6; /idz "..map..
                     " (pelna trasa oficjalnego chodzika, bez ruchu).", "warn")
                return
            end
            local command, next_id, source = emergency_step(p, r)
            if command then
                note("AutoExp TEST ODWROTU: " .. command .. " -> " .. tostring(next_id or "nieznany cel") ..
                    " (" .. source .. "); nie wyslano ruchu" ..
                    ((source == "mapper" or source == "GMCP") and "" or
                    ". UWAGA: to tylko awaryjne wyjscie, nie potwierdzona trasa do schronienia!"),
                    "warn")
            else
                note("AutoExp TEST ODWROTU: ALARM, brak znanego dostepnego wyjscia GMCP!", "warn")
            end
        end)
        command("stop", nil, function()
            if hooks.stop_tower then hooks.stop_tower() end
            halt("Zatrzymano recznie")
        end)
        command("pauza", nil, function()
            safety.manual_at=nil
            if paused then phase="PAUSED"; last_reason="Pauza uzytkownika"
            else pause("Pauza uzytkownika") end
        end)
        command("wznow", nil, function()
            if started and paused then
                if hooks.before_start then
                    local reason = hooks.before_start(profile())
                    if reason then note(reason, "warn"); return false end
                end
                if safety.dark then
                    safety.awaiting=nil; safety.dark_visits={}
                    fallback={reason=safety.dark,stop_on_arrival=true}
                elseif safety.blind then note("Brak widocznosci", "warn"); return end
                safety.manual_at=nil; paused, phase = false, "READY"
                observed_room, entities_ready = room_id(), false
                observed_key=room() and (room().key or room().id)
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
            if started then note("Zatrzymaj /exp przed zmiana terenu.", "warn"); return false end
            if not allowed_config() then return end
            local key = normalized(name)
            if not areas[key] then
                local found
                for id,value in pairs(areas) do
                    if normalized(value.name)==key then
                        if found then note("Niejednoznaczna nazwa terenu; wybierz jego zapisany klucz.","warn");return false end
                        found=id
                    end
                end
                key=found or key
            end
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
            local map = mapper.current_room()
            local hashed = type(getRoomIDbyHash) == "function" and getRoomIDbyHash(id) or nil
            if type(map) ~= "number" or map <= 0 or map % 1 ~= 0 or hashed ~= map
                or (type(getRoomHashByID) == "function" and getRoomHashByID(map) ~= id) then
                note("Brak zgodnosci GMCP z mapperem; nie zapisuje bezpiecznej lokacji.", "warn")
                return
            end
            p.safeRoom, p.safeKey, p.safeMap = id, room().key or id, map
            remember()
            note("Bezpieczna lokacja: "..id.." | mapper: "..map..
                 " (awaryjnie /opoz 0.6, /idz "..map..")")
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
        command("druzyna", "<on|off>", function(s)
            -- Safe runtime switch: affects only future attack commands.
            local p = profile()
            if not p then note("Wybierz expowisko.", "warn"); return end
            s = normalized(s)
            if s ~= "on" and s ~= "off" then
                note("Uzycie: /exp druzyna on lub /exp druzyna off", "warn"); return
            end
            p.partyAttack = s == "on"
            remember()
            note("AutoExp: rozkazy ataku druzyny " .. (p.partyAttack and "WLACZONE" or "WYLACZONE"))
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
        local function copy(value)
            if type(value) ~= "table" then return value end
            local out = {}; for k,v in pairs(value) do out[k] = copy(v) end; return out
        end
        local function status()
            return {defensive_only=safety.blind or safety.dark~=nil or phase=="DARK_STOP" or
                    (started and (paused or phase~="COMBAT" or fallback~=nil)),
                phase=phase, started=started, paused=paused, dry=dry,
                selected=selected, moving=move and move.id, mapping=mapping and mapping.name,
                escaping=escape and escape.origin, emergency=emergency and emergency.destination,
                fallback=fallback and fallback.reason,
                economy=economy_run and economy_run.stage, elapsed=session.elapsed,
                xp=session.xp, reason=last_reason, destroyed=destroyed}
        end
        return {
            status=status,
            issuing_attack_order=function() return safety.ordering==true end,
            party_attack_enabled=function()
                local p=profile()
                return p and p.partyAttack==true or false
            end,
            nearest_profiles=function(limit)
                if destroyed then return {} end
                return nearest_profiles(math.max(1,math.floor(tonumber(limit) or 3)))
            end,
            snapshot=function()
                return copy({status=status(), profiles=areas, profile=profile(),
                    session=session, verbosity=verbosity, log=event_log})
            end,
            request=function(name, arg)
                if destroyed or not requests[name] then return false, "Nieznana operacja" end
                return requests[name](arg)
            end,
            set_economy=function(key, value)
                if destroyed or not allowed_config() then return false end
                local p=areas[key]
                if not p then return false end
                p.economy=p.economy or {}; p.economy.enabled=value==true
                if value then note("Auto-zarobek sprzedaje kategorie z listy łupów profilu; obejmuje niesione przedmioty tych kategorii.","warn") end
                remember(); ui_refresh(); return true
            end,
            stop=function(reason) if not destroyed then halt(reason or "STOP"); ui_refresh() end end,
            pause=function(reason) if not destroyed then pause(reason or "Pauza"); ui_refresh() end end,
            import_old_profiles=import_old_profiles,
        }
    end,
}
