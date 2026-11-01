local new=dofile("tests/support_harness.lua")
local M=dofile("src/chimeraxp/tactics_model.lua")
local T=dofile("src/chimeraxp/tactics.lua")
local function harness(config)
    local h=new();h.saved.tactics=config
    h.api=T.new(h.ctx,M,{check=function()end},{status=function()return {started=false}end},function()end)
    h.api.toggle(true);h.fresh();return h
end
do
    local h=harness({team_orders=true,team_broadcast=true,minions={{id="petone"},{id="pettwo"}}})
    h.p.combat.relations={{attacker="me",defender="enemy1"}}
    h.fresh();h.advance(5.2)
    assert(h.sent[1]=="rozkaz druzynie zaatakowac enemy1","idle party gets collective order")
    h.advance(9);h.fresh();h.advance(5);assert(#h.sent==1,"no repeat before 15s")
    h.fresh();h.advance(1.2);assert(h.sent[2]==h.sent[1],"unconfirmed attack retried after cooldown")
    for _,id in ipairs({"tank","friend","petone","pettwo"}) do
        h.p.combat.relations[#h.p.combat.relations+1]={attacker=id,defender="enemy1"}
    end
    h.fresh();h.advance(10);h.fresh();h.advance(6);assert(#h.sent==2,"aligned team not spammed")
    h.p.group.leader="tank";h.p.combat.relations[2].defender="enemy2"
    h.fresh();h.advance(1);assert(#h.sent==2,"only leader coordinates players")
    h.dispose()
end
local function hp(h,id,value)
    for _,list in ipairs({h.p.group.members,h.p.entities.entities}) do
        for _,m in ipairs(list) do if m.id==id then m.hp=value end end
    end
end
local models={M}
if os.getenv("TACTICUS_MODEL") then models[#models+1]=dofile(os.getenv("TACTICUS_MODEL")) end
for _,model in ipairs(models) do
    local h=new();local c=model.defaults({role="support",retreat=true,minions={{id="petone",task="reserve"},{id="pettwo",task="reserve"}}})
    h.p.combat.relations={{attacker="enemy1",defender="me"}}
    hp(h,"tank",69);hp(h,"friend",69)
    local function plan()return model.plan(assert(model.snapshot(h.gmcp)),c,{true,true,true,true})end
    assert(not plan(),"wounded allies and reserves cannot receive retreat")
    hp(h,"tank",90);c.profiles.tank=model.profile_defaults({name="tank",kind="player",role="support"})
    assert(not plan(),"Support cannot receive retreat even at high HP")
    c.profiles.tank=nil;assert(plan().kind=="retreat")
    assert(model.command(plan(),assert(model.snapshot(h.gmcp)))=="wycofaj sie za tank")
    h.p.entities.entities[2].states={"casting"};assert(not plan())
    h.p.entities.entities[2].states={};c.retreat=false;assert(not plan(),"retreat requires opt-in")
    h.dispose()
end
do
    local h=harness({role="support",retreat=true,minions={{id="petone",task="reserve"},{id="pettwo",task="reserve"}}})
    h.p.combat.relations={{attacker="enemy1",defender="me"}}
    h.fresh();h.advance(5.2);assert(h.sent[1]:match("^wycofaj sie za "))
    h.triggers["Jestes gotowa do zmiany w szyku."]()
    h.advance(9);h.fresh();h.advance(5);assert(#h.sent==1,"readiness does not shorten retreat's 15s")
    h.fresh();h.advance(1.2);assert(#h.sent==2,"retreat retries after 15s")
    h.api.stop();h.fresh();h.advance(20);assert(#h.sent==2)
    h.dispose()
end
print("PASS idle party focus, 15s cadence, safe retreat recipients and readiness isolation")
