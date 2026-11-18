-- Regression: an assigned guard at exactly 50% HP is endangered,
-- not "healthy". The leader's asekuracja rescue must not be vetoed by
-- the guard's auto task. This is the case reported from live combat.
local new=dofile("tests/support_harness.lua")
local M=dofile("src/chimeraxp/tactics_model.lua")
local T=dofile("src/chimeraxp/tactics.lua")
local I=dofile("src/chimeraxp/integration.lua")

local function health(h,id,percent)
    for _,list in ipairs({h.p.group.members,h.p.entities.entities}) do
        for _,member in ipairs(list) do
            if member.id==id then
                member.hp=percent;member.maxhp=100
            end
        end
    end
    if id=="me" then h.p.vitals.hp=percent end
end
local function fixture()
    local h=new()
    health(h,"me",100)
    health(h,"petone",90)
    health(h,"pettwo",100)
    h.p.combat.relations={{attacker="enemy1",defender="petone"}}
    h.saved.tactics={
        role="asekuracja",team_orders=false,team_broadcast=false,
        retreat=false,minions={{id="petone",task="auto"},
            {id="pettwo",task="auto"}},
        self_profile=M.profile_defaults({name="me",kind="player",role="asekuracja"}),
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
    assert(c.minions[1].task==nil and c.role=="asekurant",
        "legacy guard tasks do not survive migration")
    local only_leader_and_guard={true,true,false,false}
    -- A designated healthy guard should not be rearranged routinely.
    s.risk={petone={level="stable",hp=90}}
    assert(M.plan(s,c,only_leader_and_guard)==nil,
        "preserve routine guard task when its owner is safe")

    health(h,"petone",50)
    s=assert(M.snapshot(h.gmcp))
    for _,level in ipairs({"warning","critical"}) do
        s.risk={petone={level=level,hp=50}}
        local d=M.plan(s,c,only_leader_and_guard)
        assert(d and d.channel==1 and d.kind=="cover" and d.actor=="me"
            and d.protected=="petone" and d.enemy=="enemy1",
            "endangered guard at 50% must be rescued by available leader: "..level)
        assert(M.command(d,s)=="zaslon petone przed enemy1",
            "leader uses own direct cover, not an order")
    end

    -- Still protect the rescuer: too little HP or an exhausted max-load
    -- cannot be bypassed by risk classification.
    health(h,"me",65)
    s=assert(M.snapshot(h.gmcp))
    s.risk={petone={level="critical",hp=50}}
    assert(not M.plan(s,c,only_leader_and_guard),
        "don't force the asekurant leader below her own 70% HP floor")
    h.dispose()
end

do
    local h=fixture()
    -- Isolate the player's rescue decision: a second healthy warrior could
    -- legitimately rebalance a single weak attacker before the injury.
    assert(h.api.configure("pettwo","enabled",false))
    assert(h.api.toggle(true))
    h.fresh();h.advance(5.2)
    assert(#h.sent==0,"do not rearrange an uninjured auto guard: "..table.concat(h.sent," | "))
    health(h,"petone",50)
    h.emit("chimera.group.state")
    h.emit("chimera.room.entities")
    h.advance(.3)
    assert(h.api.status().threat and h.api.status().threat.level=="critical",
        "GMCP 40pp injury puts guard in critical danger")
    assert(h.sent[1]=="zaslon petone przed enemy1",
        "Obrona must attempt an own cover when first auto guard drops to 50%")
    h.dispose()
end

do
    local h=fixture()
    health(h,"me",65)
    assert(h.api.configure("pettwo","enabled",false))
    assert(h.api.toggle(true))
    h.fresh();h.advance(5.2)
    health(h,"petone",50)
    h.emit("chimera.group.state")
    h.emit("chimera.room.entities")
    h.advance(.3)
    assert(#h.sent==0,"unsafe rescuer must not be forced to take a hit")
    assert(h.api.status().detail:find("HP 65 < 70%%"),
        "no-plan diagnosis must report actual 70% Asekurant HP floor")
    h.dispose()
end

print("PASS wounded guard: risk overrides routine role, leader rescues at exactly 50% HP")
