-- Defense 2.0: GMCP health velocity, protection priorities and actor-owned
-- readiness. Assertions use simulated Lua and server state, not live combat.
local new=dofile("tests/support_harness.lua")
local M=dofile("src/chimeraxp/tactics_model.lua")
local T=dofile("src/chimeraxp/tactics.lua")
local I=dofile("src/chimeraxp/integration.lua")

local function change_hp(h,id,value)
    for _,list in ipairs({h.p.group.members,h.p.entities.entities}) do
        for _,m in ipairs(list) do
            if m.id==id then m.hp=value;m.maxhp=100 end
        end
    end
    if id=="me" then h.p.vitals.hp=value end
end
local function fixture(extra)
    local h=new()
    h.saved.tactics={
        role="asekuracja",team_orders=false,team_broadcast=false,
        retreat=false,minions={{id="petone",task="auto"},{id="pettwo",task="auto"}},
        profiles={
            petone=M.profile_defaults({name="petone",kind="npc",role="standard"}),
            pettwo=M.profile_defaults({name="pettwo",kind="npc",role="standard"}),
        },
    }
    if extra then extra(h.saved.tactics) end
    h.xp={started=false}
    h.api=T.new(h.ctx,M,I.new(h.ctx),{status=function() return h.xp end},function() end)
    return h
end
local function report(h) h.fresh();h.advance(.6) end

do
    local h=fixture()
    -- The unchanged GMCP roster stays usable after fifteen seconds.
    assert(h.api.toggle(true))
    h.fresh();h.advance(20)
    assert(h.api.status().phase~="SYNCHRONIZACJA",
        "Stable roster must not halt active protection after 15 seconds")
    -- A leader receives a heavy hit against a single enemy. Dynamic
    -- urgency must override the asekuracja role's old >=3 attackers rule.
    h.p.combat.relations={{attacker="enemy1",defender="me"}}
    change_hp(h,"me",95);report(h)
    change_hp(h,"me",65);report(h)
    assert(#h.sent>=1,"danger causes a protective action")
    assert(h.sent[1]:match("^rozkaz petone zaslonic ciebie$")
        or h.sent[1]:match("^rozkaz pettwo zaslonic ciebie$"),
        "Leader must address NPC protection with 'rozkaz ID zaslonic ciebie'")
    assert(h.api.status().threat and h.api.status().threat.level=="critical")
    local first=h.sent[1]:match("^rozkaz (%S+)")
    local second=first=="petone" and "pettwo" or "petone"
    local rows=h.api.rows()
    for _,row in ipairs(rows) do
        if row.id=="me" then assert(row.cooldown==0,"issuer did not attempt a maneuver") end
        if row.id==first then assert(row.cooldown>0,"actual performer is cooling down") end
        if row.id==second then assert(row.cooldown==0,"other retainer is still ready") end
    end
    -- Confirm the first transfer, add a second attacker and keep HP falling.
    h.p.combat.relations={{attacker="enemy1",defender=first},
        {attacker="enemy2",defender="me"}}
    change_hp(h,"me",46)
    report(h);report(h)
    assert(#h.sent>=2 and h.sent[2]=="rozkaz "..second.." zaslonic ciebie",
        "second ready NPC rescues without waiting for the first NPC's cooldown")
    h.dispose()
end

do
    local h=fixture()
    local c=M.defaults(h.saved.tactics)
    local s=assert(M.snapshot(h.gmcp))
    s.risk={friend={level="critical",hp=30},me={level="stable",hp=80}}
    h.p.combat.relations={{attacker="enemy1",defender="friend"}}
    s=assert(M.snapshot(h.gmcp));s.risk={friend={level="critical",hp=30},
        me={level="stable",hp=80}}
    local d=M.plan(s,c,{true,false,false,false})
    assert(d and d.actor=="me" and d.protected=="friend",
        "asekuracja must save an endangered ally with only one attacker")
    assert(M.command(d,s):match("^zaslon friend przed enemy1$"))
    h.dispose()
end

do
    local h=fixture(function(c) c.team_orders=true;c.team_broadcast=true end)
    local c=M.defaults(h.saved.tactics)
    h.p.combat.relations={{attacker="enemy1",defender="me"},
        {attacker="enemy2",defender="me"}}
    local s=assert(M.snapshot(h.gmcp))
    s.risk={me={level="critical",hp=60}}
    local d=M.plan(s,c,{true,true,true,true})
    assert(d and d.kind=="team_cover","collective cover available for multiple enemies")
    assert(M.command(d,s)=="rozkaz druzynie zaslonic ciebie")
    assert(#d.recipients==2)
    h.dispose()
end

do
    local h=fixture()
    assert(h.api.toggle(true))
    h.p.combat.relations={{attacker="enemy1",defender="me"}}
    h.fresh()
    -- A manual NPC order locks ONLY that retainer, not the player.
    h.emit("sysDataSendRequest",nil,"rozkaz petone zaslonic ciebie")
    local me,pet
    for _,row in ipairs(h.api.rows()) do
        if row.id=="me" then me=row end
        if row.id=="petone" then pet=row end
    end
    assert(me.cooldown==0 and pet.cooldown>0)
    local trigger=[[ ^(.+) jest gotow[ay] do kolejnej zmiany w szyku\.$ ]]
    trigger=trigger:gsub("^%s+",""):gsub("%s+$","")
    matches={[2]="petone"}
    assert(h.triggers[trigger]);h.triggers[trigger]()
    for _,row in ipairs(h.api.rows()) do
        if row.id=="petone" then assert(row.cooldown==0) end
    end
    -- Attacks are not maneuvers and never create a formation cooldown.
    h.emit("sysDataSendRequest",nil,"rozkaz druzynie zaatakowac enemy1")
    for _,row in ipairs(h.api.rows()) do
        if row.id=="me" then assert(row.cooldown==0) end
    end
    h.dispose()
end

print("PASS Defense 2.0: GMCP damage trend, emergency cover, issuer readiness, correct orders")
