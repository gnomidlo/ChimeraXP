-- ChimeraXP tactical planner, derived from Tacticus NG beta.15.
-- Pure normalization and planning. Never sends commands or reads global GMCP.
local M = {}
M.roles = {"tank", "offtank", "standard", "asekuracja", "support"}
M.labels = {tank="TANK", offtank="OFF TANK", standard="STANDARD", asekuracja="ASEKURACJA", support="SUPPORT"}
M.presets={tank={min_hp=55,max_load=4,weight=0.65},offtank={min_hp=60,max_load=3,weight=0.85},
    standard={min_hp=65,max_load=2,weight=1},asekuracja={min_hp=75,max_load=1,weight=1.25},support={min_hp=80,max_load=0,weight=2}}
local function profile(raw)
    raw=type(raw)=="table" and raw or {}
    local preset=M.presets[raw.role]
    return {name=raw.name,kind=raw.kind,role=preset and raw.role or nil,enabled=raw.enabled~=false,
        min_hp=math.max(40,math.min(100,math.floor(tonumber(raw.min_hp) or (preset and preset.min_hp or 50)))),
        max_load=math.max(0,math.min(5,math.floor(tonumber(raw.max_load) or (preset and preset.max_load or 3)))),
        target_id=M.id(raw.target_id),target_name=raw.target_name}
end
M.profile_defaults=profile
M.tasks = {"auto", "self", "protect", "support", "reserve"}
M.task_labels = {auto="Dobieraj automatycznie",self="Chroń mnie", protect="Chroń wybraną osobę", support="Wspieraj mój cel", reserve="Rezerwa"}
function M.id(v)
    if type(v) ~= "string" or v == "" or v:find("[^%w_%-]") or v:match("^%d+$") or v:match("^ob_%d+$") then return nil end
    return v
end
local function yes(v) return v == true or v == 1 or v == "1" end
local function pct(h, m)
    h, m = tonumber(h), tonumber(m)
    if not h or not m or m <= 0 then return nil end
    return math.max(0, math.min(100, h * 100 / m))
end
function M.defaults(raw)
    raw = type(raw)=="table" and raw or {}
    local c = {schema=2, team_broadcast=raw.team_broadcast==true, team_orders=raw.team_orders==true, auto_minions=true, role=M.labels[raw.role] and raw.role or "standard",
        protect=raw.protect==true, protect_id=M.id(raw.protect_id), protect_name=raw.protect_name,
        tank_id=M.id(raw.tank_id), tank_name=raw.tank_name,
        mass=raw.mass==true, mass_min=math.max(2, math.min(5, math.floor(tonumber(raw.mass_min) or 2))),
        mass_max=math.max(2, math.min(5, math.floor(tonumber(raw.mass_max) or 5))),
        retreat=raw.retreat==true, min_hp=40, minion_cover_hp=50, max_load=3, minions={},profiles={},self_profile=type(raw.self_profile)=="table" and profile(raw.self_profile) or nil}
    if c.mass_min>c.mass_max then c.mass_max=c.mass_min end
    for i=1,2 do
        local p=type(raw.minions)=="table" and raw.minions[i] or {}
        p=type(p)=="table" and p or {}
        c.minions[i]={id=M.id(p.id), name=p.name, task=M.task_labels[p.task] and p.task or "auto",
            target_id=M.id(p.target_id), target_name=p.target_name}
    end
    for id,p in pairs(type(raw.profiles)=="table" and raw.profiles or {}) do
        if M.id(id) and type(p)=="table" and type(p.name)=="string" then c.profiles[id]=profile(p) end
    end
    return c
end
function M.policy(s,c,id)
    local member=s.members[id]
    local p=id==s.self_id and c.self_profile or c.profiles and c.profiles[id]
    if p and id~=s.self_id and (not member or p.name~=member.name or p.kind~=member.kind) then p=nil end
    local preset=p and M.presets[p.role]
    local floor=id==s.self_id and c.min_hp or 50
    return {role=p and p.role,enabled=not p or p.enabled~=false,min_hp=math.max(floor,p and p.min_hp or floor),
        max_load=p and (p.role=="support" and 0 or p.max_load) or c.max_load,
        weight=preset and preset.weight or 1,target_id=p and p.target_id,target_name=p and p.target_name}
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
    local s={room=room.key or room.id, members={}, entities={}, attackers={}, targets={}, enemies={}, minions={},leader=M.id(group.leader),covers={},group_complete=true}
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
    return policy.enabled and ready_member(m) and m.hp>=policy.min_hp and count(s,id)+n<=policy.max_load
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
function M.main_tank(s,c)
    local function eligible(id)
        local m=s.members[id];local p=M.policy(s,c,id)
        return m and p.enabled and p.role~="support" and ready_member(m) and m.hp>=p.min_hp
    end
    if c.tank_id and eligible(c.tank_id) and (not c.tank_name or s.members[c.tank_id].name==c.tank_name) then return c.tank_id end
    for _,id in ipairs(ordered(s.members)) do
        local p=M.policy(s,c,id)
        if p.role=="tank" and p.enabled and ready_member(s.members[id]) and s.members[id].hp>=p.min_hp then return id end
    end
    local best
    for _,id in ipairs(ordered(s.members)) do
        local m=s.members[id]
        if id~=s.self_id and not m.minion and eligible(id) then
            if not best or count(s,id)>count(s,best) or
                (count(s,id)==count(s,best) and m.hp>s.members[best].hp) then best=id end
        end
    end
    return best
end
function M.task(s,c,i)
    local task=c.minions[i].task
    if task=="reserve" then return task end
    local policy=M.policy(s,c,c.minions[i].id)
    if policy.role=="support" then return "support" end
    if task~="auto" then return task end
    if c.role=="support" or c.role=="asekuracja" or c.role=="standard" then
        if count(s,s.self_id)>0 then return "self" end
        -- Retain guard assignment even once the successful cover removed our last attacker.
        if i==1 then return "self" end
    end
    return "support"
end
function M.plan(s,c,enabled,blocked,focus)
    blocked=blocked or {}
    local function unavailable(ch,kind)
        return blocked[ch]==true or (type(blocked[ch])=="table" and blocked[ch][kind]==true)
    end
    local out={};s.weights={}
    for id in pairs(s.members) do s.weights[id]=M.policy(s,c,id).weight end
    local tank_id=M.main_tank(s,c)
    local function cover(channel,actor,protected,priority,why,allow_mass)
        if unavailable(channel,"cover") or actor==protected or not ready_member(s.members[protected]) then return end
        if channel==1 and priority<100 and s.members[protected].hp>=c.min_hp then
            for i,p in ipairs(c.minions) do
                local task=M.task(s,c,i)
                if enabled[i+1] and p.id==protected and s.members[protected].hp>=c.minion_cover_hp
                    and not (c.role=="standard" and p.task=="auto") and (task=="self" or task=="protect") then
                    return -- Do not reclaim enemies deliberately assigned to our healthy guard.
                end
            end
        end
        local policy=M.policy(s,c,actor)
        if not policy.enabled then return end
        if policy.target_id==protected and policy.target_name==s.members[protected].name then priority=priority+5 end
        if M.policy(s,c,protected).role=="support" then priority=priority+5 end
        if channel>1 and c.protect and c.protect_id==actor and protected==s.self_id then
            return -- Explicit JA protection takes precedence over the reciprocal guard task.
        end
        if focus and protected~=focus.protected then return end
        local enemies=s.attackers[protected] or {}
        if #enemies==0 or not can_take(s,actor,1,c) then return end
        local broad=channel==4 and protected~=s.self_id
        if broad and not can_take(s,actor,#enemies,c) then return end
        local improvement=gain(s,protected,actor,1)
        if broad then improvement=math.min(improvement,gain(s,protected,actor,#enemies)) end
        if channel>1 and (channel==4 or c.minions[channel-1].task=="auto") and (c.role=="standard" or policy.role) and improvement<0.12 then return end
        local enemy=enemies[1]
        if focus then
            local found=false;for _,id in ipairs(enemies) do if id==focus.enemy then found=true end end
            if not found then return end;enemy=focus.enemy
        end
        local mass=allow_mass and c.mass and #enemies>=c.mass_min and #enemies<=c.mass_max
            and can_take(s,actor,#enemies,c)
        if mass and c.role=="standard" and priority<100 and gain(s,protected,actor,#enemies)<0.12 then mass=false end
        local emergency=s.members[protected].minion and s.members[protected].hp<c.minion_cover_hp and improvement>=0.12
        out[#out+1]={channel=channel,actor=actor,protected=protected,enemy=enemy,emergency=emergency,broad=broad,
            kind=mass and "mass" or "cover",priority=s.members[protected].hp<40 and improvement>=0.12 and 120 or (emergency and math.max(priority,110) or priority),safety_gain=broad and improvement or gain(s,protected,actor,mass and #enemies or 1),reason=why,room=s.room,
            before_targets=(mass or broad) and enemies or {enemy}}
    end
    local me=s.self_id
    if enabled[1] and M.policy(s,c,me).enabled and not blocked[1] and ready_member(s.members[me]) then
        if c.protect and s.members[c.protect_id] and (not c.protect_name or s.members[c.protect_id].name==c.protect_name) then
            cover(1,me,c.protect_id,100,"Ochrona priorytetowa: "..s.members[c.protect_id].name,true)
        end
        if c.role~="support" and c.role~="asekuracja" then
            for _,id in ipairs(ordered(s.members)) do
                if id~=me and count(s,id)>0 then
                    local g=gain(s,id,me,1)
                    local accept=c.role=="tank" or (c.role=="standard" and g>=0.12)
                    if c.role=="offtank" then
                        accept=tank_id and
                            ((id==tank_id and count(s,id)>=count(s,me)+2)
                            or (id~=tank_id and count(s,me)<count(s,tank_id)))
                    end
                    if accept then cover(1,me,id,60+math.min(20,count(s,id)*4),"Odciążenie: "..s.members[id].name,true) end
                end
            end
        elseif c.role=="asekuracja" and count(s,me)==0 then
            for _,id in ipairs(ordered(s.members)) do
                if count(s,id)>=3 and gain(s,id,me,1)>=0.12 then cover(1,me,id,60,"Asekuracja przeciążonego sojusznika.",false) end
            end
        end
        if c.retreat and count(s,me)>0 then
            for _,id in ipairs(ordered(s.members)) do
                -- In this beta we conservatively assume retreat can transfer ALL attackers.
                if id~=me and can_take(s,id,count(s,me),c) then
                    local accept=c.role=="support" or (c.role=="asekuracja" and count(s,me)>1)
                        or (c.role=="standard" and gain(s,me,id,count(s,me))>=0.18)
                        or (c.role=="offtank" and id==tank_id and count(s,me)>count(s,id)+1)
                        or s.members[me].hp<c.min_hp
                    if accept then out[#out+1]={channel=1,actor=me,protected=id,kind="retreat",
                        room=s.room,priority=s.members[me].hp<c.min_hp and 110 or 80,
                        before_targets=s.attackers[me],reason="Wycofanie za "..s.members[id].name} end
                end
            end
        end
    end
    for i=1,2 do
        local p=c.minions[i];local actor=p.id;local ch=i+1
        local task=M.task(s,c,i)
        if enabled[ch] and M.policy(s,c,actor).enabled and blocked[ch]~=true and actor and s.minions[actor] and ready_member(s.minions[actor]) then
            if p.task=="auto" and M.policy(s,c,actor).role~="support" and (c.role=="standard" or M.policy(s,c,actor).role) then
                for _,protected in ipairs(ordered(s.members)) do
                    cover(ch,actor,protected,95,"Pachołek "..i..": odciążenie "..s.members[protected].name..".",false)
                end
            elseif task=="self" then cover(ch,actor,me,95,"Pachołek "..i..": ochrona postaci.",false)
            elseif task=="protect" and s.members[p.target_id] and (not p.target_name or s.members[p.target_id].name==p.target_name) then cover(ch,actor,p.target_id,95,"Pachołek "..i..": ochrona wskazanej osoby.",false)
            elseif task=="support" and not unavailable(ch,"support") then
                local target=s.targets[me]
                if target and s.enemies[target] and s.targets[actor]~=target and s.minions[actor].hp>=M.policy(s,c,actor).min_hp then
                    out[#out+1]={channel=ch,actor=actor,enemy=target,kind="support",priority=40,room=s.room,
                        reason="Pachołek "..i..": wsparcie celu postaci."}
                end
            end
        end
    end
    if c.team_orders and enabled[4] and s.leader==me then
        for _,id in ipairs(ordered(s.members)) do
            local member=s.members[id]
            if id~=me and M.policy(s,c,id).enabled and (M.policy(s,c,id).role or (c.role~="tank" and c.role~="offtank"))
                and member.kind=="player" and member.hp and member.hp>=50 and not member.casting then
                for _,protected in ipairs(ordered(s.members)) do
                    if (c.role=="standard" or M.policy(s,c,id).role or protected==me)
                        and not (s.covers[protected] and s.covers[protected][id]) then
                        cover(4,id,protected,95,"Rozkaz drużynie: "..member.name.." osłania "..s.members[protected].name..".",false)
                    end
                end
            end
        end
    end
    local function available_for_broadcast(id,covering)
        if not M.policy(s,c,id).enabled then return false end
        if id==me then return not covering or (enabled[1] and not blocked[1]) end
        if s.members[id].minion then
            for slot,p in ipairs(c.minions) do
                if p.id==id then return enabled[slot+1] and not unavailable(slot+1,covering and "cover" or "support") and p.task~="reserve" end
            end
            return false
        end
        return true
    end
    if s.group_complete and c.team_orders and c.team_broadcast and enabled[4] and not unavailable(4,"cover") and s.leader==me and not focus then
        for _,protected in ipairs(ordered(s.members)) do
            local enemies=s.attackers[protected] or {}
            local recipients={};local safe=#enemies>0 and (c.role=="standard" or protected==me)
            local benefit=1
            for _,id in ipairs(ordered(s.members)) do
                if id~=protected then
                    local m=s.members[id]
                    -- Include issuer in safety checks: never rely on the server excluding a wounded member.
                    if not available_for_broadcast(id,true) or not ready_member(m) or m.hp<50 or m.casting or not can_take(s,id,#enemies,c)
                        or (s.covers[protected] and s.covers[protected][id]) then safe=false end
                    local improvement=math.min(gain(s,protected,id,1),gain(s,protected,id,#enemies))
                    if improvement<0.12 then safe=false end
                    benefit=math.min(benefit,improvement)
                    if id~=me then recipients[#recipients+1]=id end
                end
            end
            if safe and #recipients>1 then
                out[#out+1]={channel=4,actor=me,protected=protected,kind="team_cover",broad=true,
                    priority=s.members[protected].hp<40 and 121 or 96,safety_gain=benefit,room=s.room,
                    recipients=recipients,before_targets=enemies,reason="Drużyna: wspólna osłona "..s.members[protected].name.."."}
            end
        end
        local target=s.targets[me];local recipients={};local safe=target and s.enemies[target] and s.enemies[target].relation=="hostile"
        local mismatch=false
        for _,id in ipairs(ordered(s.members)) do
            local m=s.members[id]
            if not available_for_broadcast(id,false) or not ready_member(m) or m.hp<math.max(50,M.policy(s,c,id).min_hp) or m.casting then safe=false end
            if id~=me then
                recipients[#recipients+1]=id
                -- Only align units already fighting; do not start combat for idle companions.
                if not s.targets[id] then safe=false end
                if s.targets[id]~=target then mismatch=true end
            end
        end
        if safe and mismatch and #recipients>1 then
            out[#out+1]={channel=4,actor=me,enemy=target,kind="team_attack",priority=35,room=s.room,
                recipients=recipients,reason="Drużyna: wspólny cel walki."}
        end
    end
    table.sort(out,function(a,b)
        if a.priority~=b.priority then return a.priority>b.priority end
        if (a.safety_gain or 0)~=(b.safety_gain or 0) then return (a.safety_gain or 0)>(b.safety_gain or 0) end
        local ka=a.channel.."|"..a.actor.."|"..a.kind.."|"..(a.protected or "").."|"..(a.enemy or "")
        local kb=b.channel.."|"..b.actor.."|"..b.kind.."|"..(b.protected or "").."|"..(b.enemy or "")
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
            return "rozkaz "..d.actor.." zaslonic ciebie przed "..d.enemy
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
    if d.kind=="cover" and not d.broad then return s.targets[d.enemy]==d.actor end
    local target=d.kind=="retreat" and d.protected or d.actor
    for _,enemy in ipairs(d.before_targets or {}) do if s.targets[enemy]==target then return true end end
    return false
end
return M
