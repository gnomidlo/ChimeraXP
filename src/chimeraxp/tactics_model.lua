-- ChimeraXP tactical planner, derived from Tacticus NG beta.15.
-- Pure normalization and planning. Never sends commands or reads global GMCP.
local M = {}
-- One role per character. Legacy names are normalized once on load,
-- never consulted by combat planning after migration.
M.roles={"obronca","asekurant","zrownowazony","chroniony"}
M.labels={obronca="OBRONCA",asekurant="ASEKURANT",
    zrownowazony="ZROWNOWAZONY",chroniony="CHRONIONY"}
M.presets={
    obronca={min_hp=55,max_load=4,weight=0.65},
    asekurant={min_hp=70,max_load=2,weight=0.90},
    zrownowazony={min_hp=65,max_load=2,weight=1},
    chroniony={min_hp=80,max_load=0,weight=2.0},
}
local legacy_roles={tank="obronca",offtank="asekurant",standard="zrownowazony",
    asekuracja="asekurant",support="chroniony"}
local legacy_presets={
    tank={min_hp=55,max_load=4},offtank={min_hp=60,max_load=3},
    standard={min_hp=65,max_load=2},asekuracja={min_hp=75,max_load=1},
    support={min_hp=80,max_load=0},
}
function M.role(value)
    local role=legacy_roles[value] or value
    return M.labels[role] and role or "zrownowazony"
end
function M.id(v)
    if type(v) ~= "string" or v == "" or v:find("[^%w_%-]")
        or v:match("^%d+$") or v:match("^ob_%d+$") then return nil end
    return v
end
local function yes(v) return v == true or v == 1 or v == "1" end
local function pct(h,m)
    h,m=tonumber(h),tonumber(m)
    if not h or not m or m<=0 then return nil end
    return math.max(0,math.min(100,h*100/m))
end
local function profile(raw,migrating)
    raw=type(raw)=="table" and raw or {}
    local role=M.role(raw.role)
    local preset=M.presets[role]
    local previous=migrating and legacy_presets[raw.role]
    local function threshold(field)
        local value=tonumber(raw[field])
        -- A value equal to the old role default is not a user override.
        if previous and value==previous[field] then value=nil end
        return value or preset[field]
    end
    return {name=raw.name,kind=raw.kind,role=role,enabled=raw.enabled~=false,
        min_hp=math.max(40,math.min(100,math.floor(threshold("min_hp")))),
        max_load=math.max(0,math.min(5,math.floor(threshold("max_load"))))}
end
M.profile_defaults=profile

function M.defaults(raw)
    raw=type(raw)=="table" and raw or {}
    local migrating=raw.schema~=3
    local role=M.role(raw.role)
    local c={schema=3,team_broadcast=raw.team_broadcast==true,
        team_orders=raw.team_orders==true,role=role,
        mass=raw.mass==true,mass_min=math.max(2,math.min(5,math.floor(tonumber(raw.mass_min) or 2))),
        mass_max=math.max(2,math.min(5,math.floor(tonumber(raw.mass_max) or 5))),
        retreat=raw.retreat==true,minions={},profiles={},
        self_profile=type(raw.self_profile)=="table" and profile(raw.self_profile,migrating) or nil}
    if c.mass_min>c.mass_max then c.mass_max=c.mass_min end
    for i=1,2 do
        local p=type(raw.minions)=="table" and raw.minions[i] or {}
        p=type(p)=="table" and p or {}
        c.minions[i]={id=M.id(p.id),name=p.name}
    end
    for id,p in pairs(type(raw.profiles)=="table" and raw.profiles or {}) do
        if M.id(id) and type(p)=="table" and type(p.name)=="string" then
            c.profiles[id]=profile(p,migrating)
        end
    end
    if migrating then
        -- Old task/target selections must not survive as hidden vetoes.
        -- An explicitly reserved helper is opted out until the user enables
        -- it again. All other former tasks defer to the one role.
        for _,p in ipairs(type(raw.minions)=="table" and raw.minions or {}) do
            if p.task=="reserve" and M.id(p.id) then
                local saved=c.profiles[p.id] or profile({name=p.name,kind="npc"})
                saved.enabled=false
                c.profiles[p.id]=saved
            end
        end
    end
    return c
end
function M.policy(s,c,id)
    local member=s.members[id]
    local p=id==s.self_id and c.self_profile or c.profiles and c.profiles[id]
    if p and id~=s.self_id and (not member or p.name~=member.name or p.kind~=member.kind) then p=nil end
    local role=p and M.role(p.role) or (id==s.self_id and M.role(c.role) or "zrownowazony")
    local preset=M.presets[role]
    return {role=role,enabled=not p or p.enabled~=false,
        min_hp=p and p.min_hp or preset.min_hp,
        max_load=p and p.max_load or preset.max_load,
        weight=preset.weight}
end
-- Roster detection is deliberately independent from Combat.State (also works out of combat).
function M.roster(api)
    local room,e,g=api.room(),api.entities(),api.group()
    if not api.connected() or type(room)~="table" or type(e)~="table" or type(g)~="table"
        or type(room.id)~="string" or type(e.room)~="string" or e.room:lower()~=room.id:lower()
        or type(e.entities)~="table" or type(g.members)~="table" then return nil end
    local entities,out={},{}
    for _,v in ipairs(e.entities) do if M.id(v.id) then entities[v.id]=v end end
    for _,v in ipairs(g.members) do
        local entity=entities[v.id]
        if entity and yes(v.here) and not yes(v.self) and entity.kind=="npc" and entity.relation=="ally" then
            out[#out+1]={id=v.id,name=tostring(v.name or entity.name or v.id)}
        end
    end
    table.sort(out,function(a,b) if a.name~=b.name then return a.name<b.name end return a.id<b.id end)
    return out
end
function M.snapshot(api)
    if not api.connected() then return nil,"Brak połączenia." end
    local room, entities, combat, group=api.room(),api.entities(),api.combat(),api.group()
    if type(room)~="table" or not room.id or type(entities)~="table" or type(combat)~="table"
        or type(group)~="table" or type(group.members)~="table" then return nil,"Czekam na komplet GMCP." end
    local function same_room(v) return type(v)=="string" and v:lower()==room.id:lower() end
    if not same_room(entities.room) or not same_room(combat.room) then return nil,"Niezgodna lokacja danych walki." end
    if type(entities.entities)~="table" or type(combat.relations)~="table" then return nil,"Niepełny stan walki." end
    local s={room=room.key or room.id, members={}, entities={}, attackers={}, targets={}, enemies={}, minions={},leader=M.id(group.leader),covers={},group_complete=true,relations_count=#combat.relations}
    local char=api.char() or {}
    s.self_id=M.id(char.id)
    for _,e in ipairs(entities.entities) do
        local id=M.id(e.id)
        if id then
            s.entities[id]={id=id,name=tostring(e.name or id),kind=e.kind,relation=e.relation,
                hp=pct(e.hp,e.maxhp),stunned=false,casting=false}
            for _,v in ipairs(e.states or {}) do if v=="stunned" then s.entities[id].stunned=true elseif v=="casting" then s.entities[id].casting=true end end
            if yes(e.self) or e.relation=="self" then s.self_id=id end
        end
    end
    for _,g in ipairs(group.members) do
        local id=M.id(g.id)
        if yes(g.self) and id then s.self_id=id end
        if not id or not yes(g.here) or not s.entities[id] then s.group_complete=false end
        if id and yes(g.here) and s.entities[id] then
            local e=s.entities[id]
            local group_hp=pct(g.hp,g.maxhp)
            -- Without per-member timestamps, conflicting HP must not make a wounded ally look healthy.
            local hp=group_hp and e.hp and math.min(group_hp,e.hp) or group_hp or e.hp
            s.members[id]={id=id,name=tostring(g.name or e.name),hp=hp,
                stamina=pct(g.stamina,g.maxstamina),mana=pct(g.mana,g.maxmana),
                stunned=e.stunned,casting=e.casting,kind=e.kind, minion=e.kind=="npc" and e.relation=="ally"}
        end
    end
    if not s.self_id or not s.entities[s.self_id] then return nil,"Brak postaci w aktualnej lokacji." end
    local own=s.entities[s.self_id]
    s.members[s.self_id]=s.members[s.self_id] or {id=s.self_id,name=own.name,hp=own.hp,stunned=own.stunned}
    -- Char.Vitals.hp is a percentage, Group/Entities use actual points.
    local vitals=api.vitals() or {}
    if tonumber(vitals.hp) then
        local value=math.max(0,math.min(100,tonumber(vitals.hp)))
        s.members[s.self_id].hp=s.members[s.self_id].hp and math.min(s.members[s.self_id].hp,value) or value
    end
    if tonumber(vitals.mana) then s.members[s.self_id].mana=math.max(0,math.min(100,tonumber(vitals.mana))) end
    if tonumber(vitals.fatigue) then s.members[s.self_id].fatigue=math.max(0,math.min(100,tonumber(vitals.fatigue))) end
    for id,m in pairs(s.members) do
        s.attackers[id]={}
        if m.minion and id~=s.self_id then s.minions[id]=m end
    end
    for _,cover in ipairs(combat.covers or {}) do
        if s.members[cover.guard] and s.members[cover.guarded] then
            s.covers[cover.guard]=s.covers[cover.guard] or {};s.covers[cover.guard][cover.guarded]=true
        end
    end
    local seen={}
    for _,r in ipairs(combat.relations) do
        local a,d=M.id(r.attacker),M.id(r.defender)
        if not a or not d or not s.entities[a] or not s.entities[d] then
            return nil,"Relacje walki czekają na aktualne istoty."
        end
        local key=a..">"..d
        if not seen[key] then
            seen[key]=true
            s.targets[a]=d
            if s.members[d] and not s.members[a] then
                -- First beta is PvE only. Unknown/player attackers do not trigger maneuvers.
                if s.entities[a].kind~="npc" then return nil,"Walka z graczem lub nierozpoznanym napastnikiem: blokada." end
                s.enemies[a]=s.entities[a]
                s.attackers[d][#s.attackers[d]+1]=a
            end
            if s.members[a] and not s.members[d] then
                if s.entities[d].kind~="npc" then return nil,"Cel poza zakresem PvE: blokada." end
                s.enemies[d]=s.entities[d]
            end
        end
    end
    for _,list in pairs(s.attackers) do table.sort(list) end
    return s
end
-- Display-only party snapshot also works before the first combat packet.
function M.party(api)
    local room=api.room()
    if not room then return nil end
    local proxy={};for k,v in pairs(api) do proxy[k]=v end
    proxy.combat=function() return {room=room.id,relations={}} end
    return M.snapshot(proxy)
end
local function count(s,id) return #(s.attackers[id] or {}) end
local function ready_member(m) return m and m.hp and m.hp>0 and not m.stunned end
local function can_take(s,id,n,c)
    local m=s.members[id]
    local policy=M.policy(s,c,id)
    -- Do not save a threatened member by transferring attackers onto another
    -- member who is already losing HP at a critical rate.
    local danger=s.risk and s.risk[id]
    return policy.enabled and ready_member(m) and m.hp>=policy.min_hp
        and not (danger and danger.level=="critical")
        and count(s,id)+n<=policy.max_load
end
local function risk(s,id,n)
    local m=s.members[id]
    return (n/math.max(1,m and m.hp or 1))^2 * (s.weights and s.weights[id] or 1)
end
local function gain(s,from,to,n)
    local a,b=count(s,from),count(s,to)
    local before=risk(s,from,a)+risk(s,to,b)
    local after=risk(s,from,math.max(0,a-n))+risk(s,to,b+n)
    return before>0 and (before-after)/before or 0
end
local function ordered(t)
    local out={};for id in pairs(t) do out[#out+1]=id end;table.sort(out);return out
end
-- The defensive brain has one responsibility: choose the safest legal
-- maneuver for the most endangered member. Roles are preferences and hard
-- physical capacities; there are no independent per-pet task programs.
function M.main_tank(s,c)
    for _,id in ipairs(ordered(s.members)) do
        local p=M.policy(s,c,id)
        if p.role=="obronca" and p.enabled and ready_member(s.members[id])
            and s.members[id].hp>=p.min_hp then return id end
    end
    return nil
end

local function blocked_for(blocked,channel,kind)
    local b=blocked and blocked[channel]
    return b==true or (type(b)=="table" and b[kind]==true)
end

local function urgency(s,c,protected)
    local m=s.members[protected]
    if not m or not m.hp then return 0 end
    local p=M.policy(s,c,protected)
    local data=s.risk and s.risk[protected]
    local level=data and data.level or "stable"
    local incoming=count(s,protected)
    if incoming==0 then return 0 end
    local base=level=="critical" and 205 or level=="warning" and 128
        or m.hp<=40 and 190 or m.hp<=55 and 122
        or 46+math.min(22,incoming*5)
    -- A protected character should be evacuated early, not only at 35% HP.
    if p.role=="chroniony" then base=base+42 end
    if m.hp<=55 then base=base+math.floor((55-m.hp)/3) end
    return base
end

function M.explain_cover(s,c,enabled,blocked,protected)
    enabled,blocked=enabled or {},blocked or {}
    local incoming=count(s,protected)
    local lines={string.format("GMCP: %d napastnikow (%d relacji)",incoming,s.relations_count or 0)}
    local actors={{id=s.self_id,channel=1}}
    for i,p in ipairs(c.minions or {}) do
        actors[#actors+1]={id=p.id,channel=i+1,name=p.name,pet=true}
    end
    for _,actor in ipairs(actors) do
        local id=actor.id
        if id~=protected then
            local m=id and s.members[id]
            local policy=m and M.policy(s,c,id)
            local entity=id and s.entities[id]
            local reason
            if not id then reason="brak przypisanego ID"
            elseif not m then reason="nieobecna w GMCP"
            elseif actor.pet and not s.minions[id] then
                reason="niezweryfikowany NPC (kind="..tostring(entity and entity.kind)
                    ..", relation="..tostring(entity and entity.relation)..")"
            elseif not enabled[actor.channel] or not policy.enabled then reason="wylaczona"
            elseif blocked_for(blocked,actor.channel,"cover")
                or (s.maneuver_locked and s.maneuver_locked[id]) then reason="odnowienie manewru"
            elseif not ready_member(m) then reason="niegotowa/ogluszona"
            elseif policy.role=="chroniony" then reason="rola Chroniony: nie przejmuje napastnikow"
            elseif m.hp<policy.min_hp then
                reason=string.format("HP %.0f < %.0f%%",m.hp,policy.min_hp)
            elseif count(s,id)+1>policy.max_load then
                reason=string.format("limit %d/%d",count(s,id),policy.max_load)
            elseif incoming==0 then reason="brak napastnikow celu wg GMCP"
            else reason="gotowa — brak uzasadnionej zmiany szyku"
            end
            lines[#lines+1]=(m and m.name or actor.name or "JA")..
                " ["..(policy and policy.role or "bez profilu").."]: "..reason
        end
    end
    return table.concat(lines,"; ")
end

function M.plan(s,c,enabled,blocked,focus,suppress_team_attack)
    enabled,blocked=enabled or {},blocked or {}
    local me=s.self_id
    local out={}
    s.weights={}
    for id in pairs(s.members) do s.weights[id]=M.policy(s,c,id).weight end
    local actors={{id=me,channel=1}}
    for i,p in ipairs(c.minions) do
        if p.id and s.minions[p.id] then
            actors[#actors+1]={id=p.id,channel=i+1}
        end
    end

    local function proposal(actor,protected,reason)
        local id,ch=actor.id,actor.channel
        if id==protected or blocked_for(blocked,ch,"cover")
            or (s.maneuver_locked and s.maneuver_locked[id])
            or not enabled[ch] or not M.policy(s,c,id).enabled then return end
        local victim=s.members[protected]
        local performer=s.members[id]
        if not victim or not performer or not ready_member(victim)
            or victim.hp==nil or not can_take(s,id,1,c) then return end
        local enemies=s.attackers[protected] or {}
        if #enemies==0 then return end
        if focus and (focus.protected~=protected or
            not s.enemies[focus.enemy]) then return end
        local victim_risk=s.risk and s.risk[protected]
        local urgent=victim_risk and victim_risk.level~="stable"
            or victim.hp<=55
        local victim_role=M.policy(s,c,protected).role
        local role=M.policy(s,c,id).role
        local improvement=gain(s,protected,id,1)
        -- No routine oscillation for a stable group. Defenders are slightly
        -- more willing to redistribute; everybody helps with real danger.
        if not urgent and victim_role~="chroniony" then
            if role=="obronca" then
                if count(s,protected)<=count(s,id) and improvement<0.12 then return end
            elseif improvement<0.12 then return end
        end
        local score=urgency(s,c,protected)
        if role=="obronca" then score=score+22
        elseif role=="asekurant" then score=score+13 end
        if victim_role=="chroniony" then score=score+10 end
        local enemy=enemies[1]
        if focus then enemy=focus.enemy end
        local is_mass=ch==1 and c.mass and #enemies>=c.mass_min
            and #enemies<=c.mass_max and can_take(s,id,#enemies,c)
        local kind=is_mass and "mass" or "cover"
        local before=is_mass and enemies or {enemy}
        out[#out+1]={kind=kind,channel=ch,actor=id,protected=protected,
            enemy=enemy,before_targets=before,room=s.room,
            confirmation_targets=ch>1 and protected==me and s.leader==me
                and enemies or nil,
            priority=score+(is_mass and 2 or 0),
            safety_gain=improvement,
            emergency=urgent,reason=reason or
                ("Osłona "..victim.name.." — "..(victim_risk and victim_risk.level or "rola"))}
    end
    -- No second controller for protect/self/support; every ready unit is
    -- evaluated against the same threats on the same GMCP snapshot.
    for _,actor in ipairs(actors) do
        for _,protected in ipairs(ordered(s.members)) do
            proposal(actor,protected)
        end
    end

    if c.retreat and enabled[1] and not blocked_for(blocked,1,"cover")
        and not (s.maneuver_locked and s.maneuver_locked[me])
        and count(s,me)>0 and ready_member(s.members[me]) then
        local endangered=s.risk and s.risk[me]
        local danger=endangered and endangered.level~="stable"
            or s.members[me].hp<=55
        if danger then
            for _,actor in ipairs(actors) do
                local id=actor.id
                if id~=me and can_take(s,id,count(s,me),c)
                    and not blocked_for(blocked,actor.channel,"cover")
                    and enabled[actor.channel] and M.policy(s,c,id).enabled then
                    out[#out+1]={kind="retreat",channel=1,actor=me,
                        protected=id,room=s.room,priority=urgency(s,c,me)-3,
                        before_targets=s.attackers[me],
                        reason="Wycofanie za "..s.members[id].name}
                end
            end
        end
    end

    -- Optional group-wide order only when EVERY actual recipient can
    -- safely accept all current attackers. No gamble with 8-enemy aggro.
    if c.team_orders and c.team_broadcast and enabled[4]
        and s.leader==me and s.group_complete
        and not blocked_for(blocked,4,"cover") and not focus then
        for _,protected in ipairs(ordered(s.members)) do
            local enemies=s.attackers[protected] or {}
            if #enemies>1 then
                local recipients={}
                local safe=true
                for _,id in ipairs(ordered(s.members)) do
                    if id~=protected and id~=me then
                        local p=M.policy(s,c,id)
                        local ch=4
                        for i,pet in ipairs(c.minions) do
                            if pet.id==id then ch=i+1 end
                        end
                        if not p.enabled or not ready_member(s.members[id])
                            or not can_take(s,id,#enemies,c)
                            or (s.maneuver_locked and s.maneuver_locked[id])
                            or blocked_for(blocked,ch,"cover")
                            or not enabled[ch] or s.members[id].casting then
                            safe=false
                        end
                        recipients[#recipients+1]=id
                    end
                end
                if safe and #recipients>=2 then
                    local risk=s.risk and s.risk[protected]
                    local urgent=risk and risk.level=="critical"
                        or s.members[protected].hp<=45
                    out[#out+1]={kind="team_cover",channel=4,actor=me,
                        protected=protected,room=s.room,broad=true,
                        before_targets=enemies,recipients=recipients,
                        priority=urgency(s,c,protected)+(urgent and 65 or -10),
                        safety_gain=0,emergency=urgent,
                        reason="Wspólna osłona "..s.members[protected].name}
                end
            end
        end
    end

    -- Attack alignment is deliberately lower priority than any rescue.
    -- "wesprzyj" and team attack orders do not consume maneuver cooldowns.
    if not focus then
        local target=s.targets[me]
        local valid_target=target and s.enemies[target]
            and s.enemies[target].relation=="hostile"
        if valid_target and ready_member(s.members[me]) then
            for _,actor in ipairs(actors) do
                if actor.channel>1 and enabled[actor.channel]
                    and M.policy(s,c,actor.id).enabled
                    and not blocked_for(blocked,actor.channel,"support")
                    and not s.members[actor.id].casting
                    and s.targets[actor.id] and s.targets[actor.id]~=target
                    and s.enemies[s.targets[actor.id]] then
                    out[#out+1]={kind="support",channel=actor.channel,
                        actor=actor.id,enemy=target,room=s.room,
                        priority=40,reason="Wspieram wspólny cel"}
                end
            end
        end
        if valid_target and c.team_orders and c.team_broadcast
            and s.group_complete and s.leader==me and enabled[4]
            and not blocked_for(blocked,4,"support") and not suppress_team_attack then
            local mismatch=false
            local recipients={}
            for _,id in ipairs(ordered(s.members)) do
                if id~=me then
                    recipients[#recipients+1]=id
                    if s.targets[id]~=target then mismatch=true end
                end
            end
            if mismatch and #recipients>0 then
                out[#out+1]={kind="team_attack",channel=4,actor=me,
                    enemy=target,room=s.room,recipients=recipients,
                    priority=45,reason="Wspólny cel walki"}
            end
        end
    end

    table.sort(out,function(a,b)
        if a.priority~=b.priority then return a.priority>b.priority end
        if (a.safety_gain or 0)~=(b.safety_gain or 0) then
            return (a.safety_gain or 0)>(b.safety_gain or 0) end
        local ka=a.channel.."|"..a.actor.."|"..a.kind.."|"..(a.protected or "")
            .."|"..(a.enemy or "")
        local kb=b.channel.."|"..b.actor.."|"..b.kind.."|"..(b.protected or "")
            .."|"..(b.enemy or "")
        return ka<kb
    end)
    return out[1]
end
function M.command(d,s)
    if not d or d.room~=s.room or not M.id(d.actor) then return nil end
    if d.channel==4 then
        if s.leader~=s.self_id then return nil end
        if d.kind=="team_cover" and M.id(d.protected) and s.members[d.protected] then
            return "rozkaz druzynie zaslonic "..(d.protected==s.self_id and "ciebie" or d.protected)
        end
        if d.kind=="team_attack" and M.id(d.enemy) and s.enemies[d.enemy] then return "rozkaz druzynie zaatakowac "..d.enemy end
        if d.kind=="cover" and M.id(d.protected) and s.members[d.protected] and M.id(d.enemy)
            and s.leader==s.self_id and s.members[d.actor] and s.members[d.actor].kind=="player" then
            if d.protected~=s.self_id then return "rozkaz "..d.actor.." zaslonic "..d.protected end
            return "rozkaz "..d.actor.." zaslonic ciebie"
        end
        return nil
    elseif d.channel==1 then
        if not M.id(d.protected) then return nil end
        if d.kind=="retreat" then return "wycofaj sie za "..d.protected end
        if d.kind=="mass" then return "zaslon "..d.protected end
        if d.kind=="cover" and M.id(d.enemy) then return "zaslon "..d.protected.." przed "..d.enemy end
    else
        local prefix="parozkaz "..d.actor.." "
        if d.kind=="support" and M.id(d.enemy) then return prefix.."wesprzyj" end
        if d.kind=="cover" and M.id(d.enemy) and M.id(d.protected) then
            if d.protected==s.self_id and s.leader==s.self_id then
                return "rozkaz "..d.actor.." zaslonic ciebie"
            end
            return prefix.."zaslon "..d.protected.." przed "..d.enemy
        end
    end
end
function M.confirmed(d,s)
    if s.room~=d.room then return false end
    if d.kind=="team_attack" then
        for _,id in ipairs(d.recipients) do if s.targets[id]~=d.enemy then return false end end
        return true
    end
    if d.kind=="team_cover" then
        for _,enemy in ipairs(d.before_targets) do
            for _,id in ipairs(d.recipients) do if s.targets[enemy]==id then return true end end
        end
        return false
    end
    if d.kind=="support" then return s.targets[d.actor]==d.enemy end
    if d.kind=="cover" and not d.broad then
        if d.confirmation_targets then
            for _,enemy in ipairs(d.confirmation_targets) do
                if s.targets[enemy]==d.actor then return true end
            end
            return false
        end
        return s.targets[d.enemy]==d.actor
    end
    local target=d.kind=="retreat" and d.protected or d.actor
    for _,enemy in ipairs(d.before_targets or {}) do if s.targets[enemy]==target then return true end end
    return false
end
-- Interpret outgoing game commands, never persisted IDs or UI row numbers.
-- Unknown/omitted recipients conservatively lock both retainers, not disable them.
function M.manual(command,s,c)
    local text=tostring(command or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    local verb,rest=text:match("^(%S+)%s*(.*)$")
    -- Attacks have no formation cooldown. Neither kill nor team attack orders
    -- should lock cover/break channels. Support remains a distinct action.
    local kinds={zaslon="cover",zaslonic="cover",wycofaj="cover",przelam="cover",
        wesprzyj="support",wesprzec="support",zabij="target",zaatakowac="target"}
    if verb=="parozkaz" or verb=="rozkaz" then
        local recipient,action=rest:match("^(%S+)%s+(%S+)")
        local first=rest:match("^(%S+)")
        local kind=kinds[first] or kinds[action]
        if not kind then return nil end -- inventory/status and other non-combat orders
        if kinds[first] then recipient=nil end
        local channels={}
        if verb=="rozkaz" then channels[4]=true end
        local found={}
        for i,p in ipairs(c.minions) do
            local m=s and s.minions[p.id]
            if m and recipient and (p.id:lower()==recipient or m.name:lower()==recipient) then found[#found+1]=i+1 end
        end
        if #found==1 then channels[found[1]]=true
        elseif verb=="parozkaz" or recipient=="druzynie" or not s then channels[2]=true;channels[3]=true
        elseif not (recipient and s.members[recipient]) then channels[2]=true;channels[3]=true end
        return {kind=kind,channels=channels,
            actor=recipient and s and s.members[recipient] and recipient or nil,
            group=recipient=="druzynie"}
    end
    if kinds[verb]=="support" then return {kind="support",channels={[2]=true,[3]=true,[4]=true}} end
end
return M
