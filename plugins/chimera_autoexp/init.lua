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
    minRoomRevisit = 60, attackWait = 3, syncWait = 4, recoveryPoll = 3, lootGrace = 7 }
local function normalize_profile(src, name)
    local old = type(src) == "table" and src or {}
    local rules = type(old.rules) == "table" and old.rules or {}
    local p = {
        name = trim(name or old.name), route = rooms_from(old.route),
        targets = unique_names(old.targets), avoid = unique_names(old.avoid),
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
    version = "0.5.0-beta.2",
    title = "ChimeraXP / AutoExp 5",
    section = "automatyzacja",
    description = "Ostrozny patrol PvE oparty na oficjalnym mapperze i GMCP",
    deps = { "gmcp", "mapper", "walker" },
    setup = function(ctx)
        local gmcp_api = ctx:use("gmcp")
        local mapper = ctx:use("mapper")
        local walker = ctx:use("walker")
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
        local blocked_until = {} -- room ID -> time until we may try again
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
                if e.kind == "npc" and not friendly and not bool(e.dead) then
                    count = count + 1
                    if not found and id and valid_id(id)
                        and contains(e.name, p.targets) and not contains(e.name, p.avoid)
                        and not attacked_in_room[id] then
                        found = e
                    end
                end
            end
            return found, count
        end
        -- /exp unikaj is not pre-emptive pathfinding. NPCs in a destination
        -- are unknown until Room.Entities arrives, and hostile NPCs may
        -- aggro on room entry. Fail closed as soon as an avoided NPC appears.
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
        local function queue(delay)
            if not started or paused or pending then return end
            pending = ctx:timer(delay or 0, function()
                pending = nil
                if started and not paused then evaluate() end
            end)
        end
        local function halt(reason)
            if pending then ctx:cancel(pending); pending = nil end
            started, paused, dry = false, false, false
            phase, pending_attack, move = "OFF", nil, nil
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
            paused = true
            phase = "PAUSED"
            last_reason = reason
            if pending then ctx:cancel(pending); pending = nil end
            if state.owns_walk then
                stop_ours = true
                walker.stop("AutoExp: pauza")
                stop_ours = false
            end
            state.owns_walk = false
            move, pending_attack = nil, nil
            note("AutoExp WSTRZYMANY: " .. reason, "warn")
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
                local eligible_at = math.max(revisit, blocked_until[id] or 0)
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
            if active == nil then announce("WAIT_COMBAT"); return end
            -- Safety comes before the COMBAT/RETREAT branches. With the old
            -- order, an aggressive avoided mob simply put us in COMBAT and
            -- the autoexp never applied the avoid rule.
            local forbidden = avoided_npc(p, group_ids)
            if forbidden then
                pause("Wykryto omijanego NPC: " .. forbidden
                    .. ". Nie da sie przewidziec agresji NPC przed wejsciem na lokacje.")
                return
            end
            if danger then
                if active then
                    pause(string.format("Niskie HP (%.0f%%); walka trwa. Konieczna interwencja.", hp))
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
                -- The official collect module sends several commands on kill;
                -- allow a grace period before moving away from the corpse.
                if os.time() - post_combat_at < (tonumber(p.rules.lootGrace) or DEFAULT.lootGrace) then return end
                post_combat_at = nil
            end
            if state.owns_walk then return end
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
            if not ready_entities() then
                announce("WAIT_ENTITIES")
                if observed_room and last_visited
                    and os.time() - last_visited > p.rules.syncWait then
                    pause("Brak aktualnego Chimera.Room.Entities dla tej lokacji")
                end
                return
            end
            if foreign and os.time() >= (blocked_until[r.id] or 0) then
                blocked_until[r.id] = os.time() + p.rules.minRoomRevisit
                note("AutoExp: obcy gracz walczy z NPC; omijam lokacje.")
            end
            local target, npc_count = target_info(p, group_ids)
            if npc_count > p.rules.maxEnemies then
                if os.time() >= (blocked_until[r.id] or 0) then
                    blocked_until[r.id] = os.time() + p.rules.minRoomRevisit
                    note("AutoExp: zbyt wiele NPC (" .. npc_count .. "); pomijam lokacje.")
                end
                target = nil
            end
            if not foreign and target and os.time() >= (blocked_until[r.id] or 0) then
                if dry then
                    note("AutoExp TEST: atak -> " .. target.name .. " [" .. target.id .. "]")
                    pause("Zakonczono test - zadnej komendy nie wyslano")
                    return
                end
                announce("ENGAGING")
                pending_attack = { id = target.id, room = r.id, since = os.time() }
                attacked_in_room[target.id] = true -- never retry the same ID in this room
                -- State is armed BEFORE send() - GMCP may return synchronously.
                ctx:send("zabij " .. target.id, true)
                queue(0)
                return
            end
            if os.time() >= (blocked_until[r.id] or 0) then last_seen[r.id] = os.time() end
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
            if started then note("AutoExp juz dziala (uzyj /exp stop).", "warn"); return end
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
            started, paused, dry = true, false, test_mode == true
            pending_attack, move, post_combat_at = nil, nil, nil
            attacked_in_room, last_seen, blocked_until = {}, {}, {}
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
            maybe_record(r)
        end)
        ctx:on("chimera.room.changed", function(r)
            if r and r.id ~= observed_room then
                observed_room, entities_ready = r.id, false
                attacked_in_room = {}
                last_visited = os.time()
            end
            maybe_record(room())
            if started and not paused and not state.owns_walk then
                -- Manual navigation while running is not treated as a patrol step.
                if r and r.how == "reczny" then
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
            if event.map_room ~= move.map or event.target ~= move.id then
                pause("Chodzik dotarl do innego pokoju")
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
                pause("Chodzik przerwany: " .. tostring(event and event.reason or "brak powodu"))
            end
        end)
        ctx:on("chimera.session.end", function() halt("Rozlaczono - automat zatrzymany") end)
        ctx:on("chimera.step.manual", function()
            if started and not paused then pause("Gracz przejal sterowanie") end
        end)
        ctx:timer(1, function()
            if started and not paused then queue(0) end
        end, true)
        ctx:cleanup(function()
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
                {"Stan", phase .. (dry and " [TEST]" or "")},
                {"Profil", p and p.name or "brak"},
                {"Lokacje", p and tostring(#p.route) or "0"},
                {"Cele", p and table.concat(p.targets, ", ") or "brak"},
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
            ctx.log.info("/exp bezpieczna | hp ODWROT POWROT | limit NPC | odnowa SEK | start | test | pauza | wznow | stop")
            ctx.log.info("/exp import (jednorazowo ze starej bazy, tylko gdy w nowej brak profili)")
        end)
        command("start", nil, function() start(false) end)
        command("test", nil, function() start(true) end)
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
            selected = selected, moving = move and move.id, mapping = mapping and mapping.name } end,
            import_old_profiles = import_old_profiles }
    end,
}