-- Regression: 3 attackers on a wounded leader; healthy warriors are ready,
-- yet explicit/stale target tasks used to leave the planner with no action.
local new=dofile("tests/support_harness.lua")
local M=dofile("src/chimeraxp/tactics_model.lua")
local T=dofile("src/chimeraxp/tactics.lua")
local I=dofile("src/chimeraxp/integration.lua")

local function hp(h,id,value)
    for _,list in ipairs({h.p.group.members,h.p.entities.entities}) do
        for _,m in ipairs(list) do
            if m.id==id then m.hp=value;m.maxhp=100 end
        end
    end
    if id=="me" then h.p.vitals.hp=value end
end
local function fixture()
    local h=new()
    hp(h,"me",54)
    hp(h,"petone",100)
    hp(h,"pettwo",100)
    h.p.combat.relations={
        {attacker="enemy1",defender="me"},
        {attacker="enemy2",defender="me"},
        {attacker="enemy3",defender="me"},
        {attacker="me",defender="enemy3"},
        {attacker="petone",defender="enemy3"},
        {attacker="pettwo",defender="enemy3"},
    }
    h.saved.tactics={
        role="asekuracja",team_orders=false,team_broadcast=false,retreat=false,
        minions={
            {id="petone",task="protect",target_id="friend",target_name="friend"},
            {id="pettwo",task="protect",target_id="friend",target_name="friend"},
        },
        profiles={
            petone=M.profile_defaults({name="petone",kind="npc",role="standard"}),
            pettwo=M.profile_defaults({name="pettwo",kind="npc",role="standard"}),
        },
    }
    h.xp={started=false}
    h.api=T.new(h.ctx,M,I.new(h.ctx),
        {status=function() return h.xp end},function() end)
    return h
end
do
    local h=fixture()
    local c=M.defaults(h.saved.tactics)
    local s=assert(M.snapshot(h.gmcp))
    assert(#s.attackers.me==3 and s.relations_count==6)
    s.risk={me={level="warning",hp=54}}
    local decision=M.plan(s,c,{true,true,true,false})
    assert(decision and decision.kind=="cover" and decision.protected=="me",
        "critical-low HP leader must override stale protection tasks")
    assert(decision.actor=="petone" or decision.actor=="pettwo")
    assert(M.command(decision,s):match("^rozkaz pet%a+ zaslonic ciebie$"))
    -- Actual engine processing must send the same order on updated GMCP.
    assert(h.api.toggle(true))
    h.fresh();h.advance(.3)
    assert(h.sent[1] and h.sent[1]:match("^rozkaz pet%a+ zaslonic ciebie$"),
        "urgent self defense must work without awaiting 5-second startup barrier")
    h.dispose()
end

do
    local h=fixture()
    local c=M.defaults(h.saved.tactics)
    local s=assert(M.snapshot(h.gmcp))
    s.risk={me={level="warning",hp=54}}
    -- With no incoming edges, do not invent an attacker or send a cover.
    h.p.combat.relations={}
    s=assert(M.snapshot(h.gmcp));s.risk={me={level="warning",hp=54}}
    local decision=M.plan(s,c,{true,true,true,false})
    assert(not decision)
    local reason=M.explain_cover(s,c,{true,true,true,false},{},s.self_id)
    assert(reason:find("GMCP: 0 napastnikow",1,true),
        "diagnostic must reveal missing Combat.State incoming attackers")
    assert(reason:find("brak napastnikow celu wg GMCP",1,true))
    h.dispose()
end

do
    local h=fixture()
    local c=M.defaults(h.saved.tactics)
    for _,e in ipairs(h.p.entities.entities) do
        if e.id=="petone" then e.relation="group" end
    end
    local s=assert(M.snapshot(h.gmcp))
    s.risk={me={level="warning",hp=54}}
    local reason=M.explain_cover(s,c,{true,true,true,false},{},s.self_id)
    assert(reason:find("kind=npc, relation=group",1,true),
        "when a member is not marked ally, diagnostic must say so")
    -- Still use verified second NPC; never command an incorrectly tagged first.
    local d=M.plan(s,c,{true,true,true,false})
    assert(d and d.actor=="pettwo",
        "planner must not issue orders to unverified party members")
    h.dispose()
end

do
    local h=fixture()
    local c=M.defaults(h.saved.tactics)
    local s=assert(M.snapshot(h.gmcp))
    s.risk={me={level="warning",hp=54}}
    local result=M.explain_cover(s,c,{true,true,true,false},{},s.self_id)
    assert(result:find("GMCP: 3 napastnikow",1,true))
    assert(result:find("zadanie=protect/protect",1,true))
    assert(result:find("warunki spelnione",1,true),
        "give factual reasons and do not pretend assigned roles are cooldowns")
    h.dispose()
end

print("PASS Defense no-plan: 3 attackers, 54% HP, explicit tasks, no GMCP edges and NPC identity")
