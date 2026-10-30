local new=dofile("tests/support_harness.lua")
local models={dofile("src/chimeraxp/tactics_model.lua")}
-- Optional sibling addon parity check; the repository suite stays standalone.
if os.getenv("TACTICUS_MODEL") then models[#models+1]=dofile(os.getenv("TACTICUS_MODEL")) end
for _,M in ipairs(models) do
    local h=new()
    local c=M.defaults({minions={{id="petone"},{id="pettwo"}}})
    local enabled={true,true,true,true}
    h.p.combat.relations={{attacker="me",defender="enemy1"},{attacker="petone",defender="enemy2"}}
    local function plan(blocked) return M.plan(assert(M.snapshot(h.gmcp)),c,enabled,blocked) end
    assert(plan().kind=="support","AUTO aligns an already engaged retainer")
    assert(M.command(plan(),assert(M.snapshot(h.gmcp)))=="parozkaz petone wesprzyj")
    assert(plan({[2]={cover=true}}).kind=="support","formation cooldown does not suppress support")
    assert(not plan({[2]={support=true}}),"manual target hold suppresses support")
    h.p.combat.relations[2]=nil
    assert(not plan(),"AUTO must not engage idle retainers")
    c.minions[1].task="support";assert(plan(),"explicit support task retains its opt-in semantics")
    c.minions[1].task="auto";h.p.combat.relations[2]={attacker="petone",defender="enemy2"}
    h.p.entities.entities[4].states={"casting"};assert(not plan());h.p.entities.entities[4].states={}
    h.p.entities.entities[6].relation="neutral";assert(not plan());h.p.entities.entities[6].relation="hostile"
    h.p.combat.relations[2].defender="enemy1";assert(not plan(),"aligned retainers receive no repeated support order")
    h.p.combat.relations[2].defender="enemy2"
    enabled[2]=false;assert(not plan(),"manual disable is still respected");enabled[2]=true
    c.minions[1].task="reserve";assert(not plan(),"reserves are never drafted into focus");c.minions[1].task="auto"
    h.p.combat.relations[#h.p.combat.relations+1]={attacker="enemy3",defender="me"}
    h.p.combat.relations[#h.p.combat.relations+1]={attacker="enemy4",defender="me"}
    assert(plan().kind=="cover","protection outranks focus")
    h.p.combat.relations={{attacker="me",defender="enemy1"},{attacker="petone",defender="enemy2"},
        {attacker="pettwo",defender="enemy2"},{attacker="tank",defender="enemy2"},{attacker="friend",defender="enemy2"}}
    c.team_orders=true;c.team_broadcast=true
    assert(plan().kind=="team_attack","one safe broadcast outranks serial supports")
    assert(M.command(plan(),assert(M.snapshot(h.gmcp)))=="rozkaz druzynie zaatakowac enemy1")
    h.p.combat.relations[5]=nil
    assert(plan().kind=="support","idle teammate blocks broadcast but not safe retainer alignment")
    h.p.combat.relations[5]={attacker="friend",defender="enemy2"}
    assert(plan({[4]={support=true}}).kind=="support","team focus hold is respected")
    local s=assert(M.snapshot(h.gmcp))
    local d=M.manual("  parozkaz PETONE zabij enemy2",s,c)
    assert(d.kind=="support" and d.channels[2] and not d.channels[3])
    d=M.manual("parozkaz wesprzyj",s,c);assert(d.channels[2] and d.channels[3])
    d=M.manual("parozkaz old-id zaslon",s,c);assert(d.kind=="cover" and d.channels[2] and d.channels[3])
    assert(not M.manual("parozkaz petone inwentarz",s,c))
    d=M.manual("rozkaz druzynie zaatakowac enemy2",s,c);assert(d.channels[2] and d.channels[3] and d.channels[4])
    d=M.manual("zabij enemy2",s,c);assert(d.channels[2] and d.channels[3] and d.channels[4])
    s.minions.petone.name="same";s.minions.pettwo.name="same"
    d=M.manual("parozkaz same wesprzyj",s,c);assert(d.channels[2] and d.channels[3])
    h.dispose()
end

local M=models[1];local T=dofile("src/chimeraxp/tactics.lua")
local function fixture()
    local h=new();h.saved.tactics={minions={{id="petone"},{id="pettwo"}}}
    local send=h.ctx.send
    h.ctx.send=function(ctx,command)
        send(ctx,command)
        h.emit("sysDataSendRequest","sysDataSendRequest",command)
    end
    h.api=T.new(h.ctx,M,{check=function()end},{status=function()return {started=false}end},function()end)
    h.api.toggle(true);h.fresh();h.advance(5.2)
    return h
end
do
    local h=fixture()
    h.p.combat.relations={{attacker="me",defender="enemy1"},{attacker="petone",defender="enemy2"},
        {attacker="pettwo",defender="enemy2"}}
    h.fresh();h.advance(.2);assert(h.sent[1]=="parozkaz petone wesprzyj")
    h.p.combat.relations[2].defender="enemy1"
    h.fresh();h.advance(.7)
    assert(h.sent[2]=="parozkaz pettwo wesprzyj","own commands do not install manual target holds")
    h.p.combat.relations[3].defender="enemy1"
    h.fresh();h.advance(5);assert(#h.sent==2,"confirmed focus is not spammed")
    h.api.stop();h.fresh();h.advance(20);assert(#h.sent==2,"STOP prevents further focus orders")
    h.dispose()
end
do
    local h=fixture()
    h.p.combat.relations={{attacker="me",defender="enemy1"},{attacker="petone",defender="enemy2"},
        {attacker="pettwo",defender="enemy3"}}
    h.emit("sysDataSendRequest","sysDataSendRequest","parozkaz petone zabij enemy2")
    h.fresh();h.advance(.2)
    assert(h.sent[1]=="parozkaz pettwo wesprzyj","a named manual focus holds only that retainer")
    h.dispose()
end
do
    local h=fixture()
    h.emit("sysDataSendRequest","sysDataSendRequest","parozkaz petone zabij enemy2")
    h.p.combat.relations={{attacker="enemy1",defender="me"},{attacker="enemy2",defender="me"}}
    h.fresh();h.advance(.2)
    assert(h.sent[1]=="parozkaz petone zaslon me przed enemy1","manual attack does not disable protection")
    for _,r in ipairs(h.api.rows()) do assert(r.enabled) end
    h.dispose()
end
do
    local h=fixture()
    h.emit("sysDataSendRequest","sysDataSendRequest","parozkaz petone zaslon")
    h.p.combat.relations={{attacker="me",defender="enemy1"},{attacker="petone",defender="enemy2"}}
    h.fresh();h.advance(.2);assert(h.sent[1]=="parozkaz petone wesprzyj","manual cover preserves support")
    h.dispose()
end
do
    local h=fixture()
    h.emit("sysDataSendRequest","sysDataSendRequest","rozkaz druzynie zaatakowac enemy2")
    h.p.combat.relations={{attacker="me",defender="enemy1"},{attacker="petone",defender="enemy2"}}
    h.fresh();h.advance(14);assert(#h.sent==0,"old GMCP cannot immediately reverse manual focus")
    h.fresh();h.advance(2);assert(h.sent[1]=="parozkaz petone wesprzyj","automatic reassessment resumes after hold: "..h.api.status().detail)
    h.dispose()
end
do
    local h=fixture()
    h.p.combat.relations={{attacker="me",defender="enemy1"},{attacker="petone",defender="enemy2"}}
    h.fresh();h.advance(.2);assert(#h.sent==1)
    for _,packet in ipairs({h.p.group.members,h.p.entities.entities}) do
        for _,m in ipairs(packet) do if m.id=="petone" then m.id="e9-new" end end
    end
    h.fresh();h.advance(.2);assert(#h.sent==1,"mixed old/new IDs block commands")
    h.p.combat.relations[2].attacker="e9-new"
    h.fresh();h.advance(14);assert(#h.sent==1,"new identity waits before support")
    h.fresh();h.advance(2);assert(h.sent[2]=="parozkaz e9-new wesprzyj","only current ID is sent")
    h.dispose()
end
print("PASS focus: both planners, safety gates, manual scope and timed runtime arbitration")
