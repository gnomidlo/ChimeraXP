-- Screenshot regression: one wounded leader with eight attackers, two
-- healthy retainers. A room transition does not guarantee a new Group.State
-- packet, and untargeted 'rozkaz ... zaslonic ciebie' may transfer ANY mob.
local new=dofile("tests/support_harness.lua")
local M=dofile("src/chimeraxp/tactics_model.lua")
local T=dofile("src/chimeraxp/tactics.lua")
local I=dofile("src/chimeraxp/integration.lua")
local attackers={"enemy1","enemy2","enemy3","enemy4","enemy6","enemy7","enemy8","enemy9"}
local function health(h,id,pct)
    for _,list in ipairs({h.p.group.members,h.p.entities.entities}) do
        for _,v in ipairs(list) do
            if v.id==id then v.hp=pct;v.maxhp=100 end
        end
    end
    if id=="me" then h.p.vitals.hp=pct end
end
local function fixture()
    local h=new()
    local function keep(id) return id=="me" or id=="petone" or id=="pettwo" end
    local members={}
    for _,v in ipairs(h.p.group.members) do if keep(v.id) then members[#members+1]=v end end
    h.p.group.members=members
    local entities={}
    for _,v in ipairs(h.p.entities.entities) do
        if keep(v.id) or v.relation=="hostile" then entities[#entities+1]=v end
    end
    h.p.entities.entities=entities
    for _,id in ipairs(attackers) do
        local found=false
        for _,v in ipairs(entities) do if v.id==id then found=true end end
        if not found then entities[#entities+1]={id=id,name="Goblin",kind="npc",
            relation="hostile",hp=100,maxhp=100,states={}} end
    end
    health(h,"me",73)
    health(h,"petone",100);health(h,"pettwo",100)
    h.p.combat.relations={}
    for _,id in ipairs(attackers) do
        h.p.combat.relations[#h.p.combat.relations+1]={attacker=id,defender="me"}
    end
    h.saved.tactics={
        role="asekuracja",team_orders=false,team_broadcast=false,
        minions={{id="petone",task="auto"},{id="pettwo",task="auto"}},
        profiles={
            petone=M.profile_defaults({name="petone",kind="npc",role="standard"}),
            pettwo=M.profile_defaults({name="pettwo",kind="npc",role="standard"}),
        },
    }
    h.xp={started=false}
    h.api=T.new(h.ctx,M,I.new(h.ctx),{status=function() return h.xp end},function() end)
    return h
end
do
    local h=fixture()
    assert(h.api.toggle(true));h.fresh()
    h.advance(5.2)
    assert(h.sent[1] and h.sent[1]:match("^rozkaz pet%a+ zaslonic ciebie$"),
        "eight attackers must trigger an individual protection order")
    local s=assert(M.snapshot(h.gmcp))
    assert(#s.attackers.me==8)
    assert(h.api.status().threat and h.api.status().threat.level=="warning",
        "73% HP and eight enemies must be classified as threatened")

    local first=h.sent[1]:match("^rozkaz (%S+)")
    local next_actor=first=="petone" and "pettwo" or "petone"
    local pending=M.plan(s,M.defaults(h.saved.tactics),{true,true,true,false})
    assert(pending and pending.confirmation_targets
        and #pending.confirmation_targets==8,
        "bad plan: "..tostring(pending and pending.kind)
            .." protected="..tostring(pending and pending.protected)
            .." leader="..tostring(s.leader)
            .." role="..tostring(c and c.role)
            .." targets="..tostring(pending and pending.confirmation_targets and #pending.confirmation_targets))
    -- The MUD chooses enemy9, NOT the first enemy chosen locally.
    for _,r in ipairs(h.p.combat.relations) do
        if r.attacker=="enemy9" then r.defender=first end
    end
    assert(M.confirmed(pending,assert(M.snapshot(h.gmcp))),
        "untargeted command is confirmed by ANY transferred enemy")
    h.emit("chimera.combat.state")
    h.advance(.12)
    health(h,"me",50)
    h.emit("chimera.group.state")
    h.emit("chimera.room.entities")
    h.advance(.6)
    assert(h.sent[2]=="rozkaz "..next_actor.." zaslonic ciebie",
        "second, still-ready helper must rescue immediately after first transfer")
    for _,row in ipairs(h.api.rows()) do
        if row.id==first then assert(row.cooldown>0,"first helper is cooling down") end
        if row.id=="me" then assert(row.cooldown==0,"issuer remains ready") end
    end
    assert(h.api.status().threat and h.api.status().threat.level=="critical",
        "50% HP with seven attackers is critical without waiting for more damage")
    h.dispose()
end
do
    local h=fixture()
    -- No new group data after walking: roster is valid but unchanged.
    assert(h.api.toggle(true));h.fresh();h.advance(5.2)
    h.sent={}
    h.p.room.id="newroom";h.p.room.key="newroom#1"
    h.p.entities.room="newroom";h.p.combat.room="newroom"
    h.emit("chimera.room.changed")
    h.emit("chimera.room.entities")
    h.emit("chimera.combat.state")
    -- Intentionally never emit chimera.group.state.
    h.advance(.2)
    assert(h.sent[1] and h.sent[1]:match("^rozkaz pet%a+ zaslonic ciebie$"),
        "unchanged Group.State must not keep Defense in SYNCHRONIZACJA")
    assert(h.api.status().phase~="SYNCHRONIZACJA")
    h.dispose()
end
do
    local h=fixture()
    local c=M.defaults(h.saved.tactics)
    c.team_orders=true;c.team_broadcast=true
    local s=assert(M.snapshot(h.gmcp))
    s.risk={me={level="critical",hp=50}}
    local d=M.plan(s,c,{true,true,true,true})
    assert(d and d.kind=="cover" and d.protected=="me",
        "do not issue a collective 8-enemy cover to max-load-2 warriors")
    assert(M.command(d,s):match("^rozkaz pet%a+ zaslonic ciebie$"))
    h.dispose()
end
print("PASS Defense massive aggro: 8 attackers, 73->50 HP, group GMCP gap, untargeted confirmation")
