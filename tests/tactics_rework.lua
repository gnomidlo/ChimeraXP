local new=dofile("tests/support_harness.lua")
local M=dofile("src/chimeraxp/tactics_model.lua")
local T=dofile("src/chimeraxp/tactics.lua")
local I=dofile("src/chimeraxp/integration.lua")
local function fixture()
    local h=new();h.saved.tactics={team_orders=true,minions={{id="petone"},{id="pettwo"}}}
    h.xp={started=false,phase="OFF"}
    h.api=T.new(h.ctx,M,I.new(h.ctx),{status=function() return h.xp end},function() end)
    return h
end
do
    local h=fixture();h.p.combat.relations={{attacker="enemy1",defender="me"}}
    assert(not h.api.status().on and #h.sent==0,"startup never enables tactics")
    assert(h.api.toggle(true));h.fresh();h.advance(5.2)
    assert(#h.sent==1,"one executor per protection attempt; no parallel partner")
    h.advance(0.8);assert(#h.sent==1,"no second command while pending")
    local actor=h.sent[1]:match("^parozkaz (%S+)") or h.sent[1]:match("^rozkaz (%S+)")
    assert(actor);h.p.combat.relations[1].defender=actor;h.fresh();h.advance(0.2)
    h.api.stop();h.advance(20);assert(#h.sent==1,"STOP blocks future decisions")
    h.dispose()
end
do
    local h=fixture();h.p.combat.relations={{attacker="enemy1",defender="me"}}
    h.api.toggle(true);h.xp={started=true,phase="MOVING"};h.fresh();h.advance(6)
    assert(#h.sent==0,"no formation changes during patrol movement")
    h.xp.phase="COMBAT";h.fresh();h.advance(0.2);assert(#h.sent==1,"formation cooperates only in combat")
    h.xp.paused=true;h.api.stop();h.api.toggle(true);h.fresh();h.advance(6)
    assert(#h.sent==1,"paused expedition blocks tactics")
    h.dispose()
end
do
    local h=fixture();h.api.toggle(true);h.fresh();h.advance(4)
    h.p.combat.relations={{attacker="enemy1",defender="me"}}
    h.emit("chimera.room.changed");h.advance(2)
    assert(#h.sent==0,"room invalidation requires fresh packets")
    h.fresh();h.advance(0.2);assert(#h.sent==1)
    h.emit("chimera.session.end");h.fresh();h.advance(20)
    assert(not h.api.status().on and #h.sent==1,"reconnect never re-enables AUTO")
    h.dispose()
end
do
    local h=fixture();h.api.configure("me","role","tank");h.api.option("team_orders",false)
    h.api.configure("petone","enabled",false);h.api.configure("pettwo","enabled",false)
    h.p.combat.relations={{attacker="enemy1",defender="friend"}}
    h.api.toggle(true);h.fresh();h.advance(5.2);assert(#h.sent==1)
    h.triggers["Musisz chwile odpoczac po ostatniej zmianie w szyku."]()
    h.advance(7);assert(#h.sent==1,"server refusal extends lock")
    h.triggers["Jestes gotova do zmiany w szyku."]=nil -- only known spellings are accepted
    h.triggers["Jestes gotowa do zmiany w szyku."]();h.fresh();h.advance(0.2)
    assert(#h.sent==2,"readiness can release the local maneuver lock")
    h.emit("sysDataSendRequest","sysDataSendRequest","zaslon friend")
    h.fresh();h.advance(10);assert(#h.sent==2,"manual command relinquishes player channel")
    h.dispose()
end
do
    local h=fixture();local old=h.api.rows()[2]
    for _,member in ipairs(h.p.group.members) do if member.id==old.id then member.name="someone_else" end end
    for _,member in ipairs(h.p.entities.entities) do if member.id==old.id then member.name="someone_else" end end
    assert(not h.api.configure(old.id,"role","tank",old),"stale identity must not receive a role")
    h.api.stop();h.api.toggle(true);h.fresh();h.dispose()
    for _,timer in ipairs(h.timers) do timer.fn() end
    assert(#h.sent==0,"queued callbacks remain inert after disposal")
end
do
    local h=fixture();h.api.configure("tank","role","support");h.api.configure("tank","enabled",false)
    h.p.combat.relations={{attacker="enemy1",defender="tank"},{attacker="enemy2",defender="tank"}}
    local c=M.defaults(h.saved.tactics);local s=assert(M.snapshot(h.gmcp))
    assert(M.main_tank(s,c)~="tank","disabled Support cannot become fallback tank")
    c.tank_id="tank";assert(M.main_tank(s,c)~="tank","legacy manual choice obeys safety too")
    assert(M.command({channel=4,kind="team_cover",actor="me",protected="me",room=s.room},s)=="rozkaz druzynie zaslonic ciebie")
    h.api.configure("friend","role","support");h.api.configure("friend","role","auto")
    for _,r in ipairs(h.api.rows()) do if r.id=="friend" then assert(r.max_load==3,"Automat restores the generic load policy") end end
    h.dispose()
end
do
    local h=fixture();local integration=I.new(h.ctx)
    h.settings["team.autopogon"]=true;assert(integration.check({}))
    h.settings["team.autopogon"]=false;h.settings["collect.zbieranie"]=true
    assert(integration.check({economy={enabled=true},loot={"miecz"}}),"two loot executors conflict")
    assert(not integration.check({economy={enabled=false}}),"official collector can coexist when XP doesn't loot")
    h.settings["collect.zbieranie"]=false;h.settings["team.autowsparcie"]=true;assert(integration.check(nil))
    h.settings["team.autowsparcie"]=false
    h.ctx.app.loader.records.bots={status="running",api={status=function() return "bank" end}}
    assert(integration.check({}),"official bot owns movement")
    h.ctx.app.loader.records.bots=nil
    _G.tacticus_ng={state={on=true}};assert(not h.api.toggle(true),"old addon must be off");_G.tacticus_ng=nil
    h.dispose()
end
do
    local h=fixture();h.api.option("team_orders",false)
    h.p.group.members[#h.p.group.members+1]={id="petthree",name="petthree",here=1,hp=90,maxhp=100}
    h.p.entities.entities[#h.p.entities.entities+1]={id="petthree",name="petthree",kind="npc",relation="ally",hp=90,maxhp=100}
    h.p.combat.relations={{attacker="enemy1",defender="me"}}
    h.api.toggle(true);h.fresh();h.advance(5.2)
    assert(#h.sent==0,"ambiguous ownership does not guess a retainer")
    assert(h.api.bind(1,"petone"));h.api.configure("petone","enabled",true)
    h.advance(14.9);h.fresh();h.advance(0.7)
    assert(#h.sent==1 and h.sent[1]:find("^parozkaz petone "),"explicit binding can authorize one retainer in a larger party")
    h.dispose()
end
do
    local h=new();local old={role="support",minions={{id="petone"}},team_orders=true}
    h.ctx.app.storage={get_state=function(_,module,key) assert(module=="tacticus_ng" and key=="config");return old end}
    local api=T.new(h.ctx,M,I.new(h.ctx),{status=function() return {started=false} end},function() end)
    assert(not api.status().on and not api.status().team_broadcast,"migration copies settings, never AUTO or collective commands")
    local me=api.rows()[1];assert(me.role=="support" and me.max_load==0,"legacy Support role remains non-tanking")
    api.configure("me","role","tank");assert(old.role=="support","old addon settings remain intact")
    h.dispose()
end
print("PASS tactical rework: sequential decisions, patrol cooperation, readiness, identity, STOP, binding and migration")
