local path = "plugins/chimera_autoexp/init.lua"
local P = dofile(path)
assert(P.name == "autoexp" and #P.deps == 3)
local storage, commands, handlers, timers, sent, moves, messages = {}, {}, {}, {}, {}, {}, {}
local time = 0
os.time = function() return time end
getRoomIDbyHash = function(id) return ({r1=1,r2=2,r3=3,safe=5})[id] or -1 end
getPath = function(from, dest) return from ~= dest end
getMudletHomeDir = function() return "/fake" end
local world = {
  room={id="r1",name="Poczatek"},current=1,
  entities={room="r1",entities={ {id="me", name="ja", relation="self",kind="player"},
    {id="mob-a", name="Straszny czarny ork", relation="neutral",kind="npc"}}},
  group={members={{id="me",self=1,here=1,hp=100,maxhp=100}}},
  combat={self_active=0,relations={}},vitals={hp=100},connected=true,
}
local function emit(event,data)
  for _,fn in ipairs(handlers[event] or {}) do fn(data) end
end
local gmcp = {
  room=function() return world.room end,
  entities=function() return world.entities end,
  group=function() return world.group end,
  vitals=function() return world.vitals end,
  combat=function() return world.combat end,
  connected=function() return world.connected end,
}
local walker = {
  go=function(dest)
    moves[#moves+1] = dest
    emit("chimera.walk.started",{map_room=dest})
    return true
  end,
  stop=function(reason)
    emit("chimera.walk.stopped",{reason=reason})
    return true
  end
}
local ctx = {
    state={},log={info=function(m) messages[#messages+1] = m end,warn=function(m) messages[#messages+1] = "WARN:"..m end},
    use=function(_,key)
      return ({gmcp=gmcp,mapper={current_room=function() return world.current end},walker=walker})[key]
    end,
    saved=function(_,key,default) return storage[key] or default end,
    save=function(_,key,value) storage[key] = value end,
    on=function(_,event,fn) handlers[event]=handlers[event] or {};table.insert(handlers[event],fn) end,
    command=function(_,p) commands[p[1]] = p.fn end,
    timer=function(_,delay,fn,repeating)
      local id = #timers+1
      timers[id] = {fn=fn,active=true,repeating=repeating,delay=delay}
      return id
    end,
    cancel=function(_,id) if timers[id] then timers[id].active=false end end,
    cleanup=function() end,
    send=function(_,s) sent[#sent+1]=s end,
    report=function() end,
}
local api=P.setup(ctx)
local function tick()
  local list={}
  for id,t in ipairs(timers) do if t.active and not t.repeating then list[#list+1]=id end end
  for _,id in ipairs(list) do local t=timers[id];t.active=false;t.fn() end
end
local function cmd(k,arg) assert(commands[k],k)(arg) end
-- Input import old shape, profile defaults and compatibility.
local converted=api.import_old_profiles({areas={runa={name="RunA",route={"r1","r1","r2"},
  targets={"ork","ORK"},avoid={"smok"},safeRoom="safe",rules={retreatHP=32}}}})
assert(#converted.runa.route == 2 and #converted.runa.targets == 1 and converted.runa.rules.retreatHP == 32)
-- Map a new area including room change and profile edits.
cmd("exp mapuj","Test")
assert(api.status().mapping=="Test")
world.room={id="r2",name="Drugie"};world.current=2
emit("chimera.room.changed",{id="r2",how="reczny"})
emit("chimera.room.info",world.room)
cmd("exp mapuj","Test")
cmd("exp wybierz","Test")
cmd("exp cel","ork")
cmd("exp cel","snotling")
assert(#storage.profiles.test.targets == 2,"target appending")
assert(#storage.profiles.test.route==2,"map route saving")
cmd("exp bezpieczna")
-- No matching target in room r2, patrol should pick r1.
world.entities={room="r2",entities={{id="me",relation="self",kind="player"}}}
cmd("exp test")
tick()
assert(#sent==0 and #moves==0, "simulation cannot send anything")
assert(api.status().paused==true,"simulation stops after explaining decision")
cmd("exp stop")
-- Return to initial room with enemy, one attack by ID.
world.room={id="r1"};world.current=1
world.entities={room="r1",entities={{id="me",kind="player",relation="self"},
  {id="mob-a",name="czarny ork",kind="npc",relation="neutral"}}}
cmd("exp start")
tick()
assert(sent[1]=="zabij mob-a","attack ID")
assert(api.status().phase=="ENGAGING")
-- Event cascade should not duplicate attack.
emit("chimera.room.entities",world.entities)
emit("chimera.char.vitals",world.vitals)
tick()
assert(#sent==1, "only one attack pending")
-- When an emergency route is not available, fail closed with an alarm.
world.combat={self_active=1,relations={{attacker="me",defender="mob-a"}}}
emit("chimera.combat.state",world.combat)
tick()
assert(api.status().phase=="COMBAT")
world.vitals.hp=23
emit("chimera.char.vitals",world.vitals)
tick()
assert(api.status().paused==true)
assert(#moves==0)
cmd("exp stop")
-- Low HP outside combat retreats through official walker API.
world.combat={self_active=0,relations={}}
world.vitals.hp=23
cmd("exp start")
tick()
assert(moves[1]==2 and api.status().phase=="RETREAT","safe room move")
-- unrelated arrival should fail shut
emit("chimera.walk.arrived",{map_room=3,target="r3"})
assert(api.status().paused,"destination mismatch")
cmd("exp stop")
-- no duplicate commands and no resume on disconnected session
cmd("exp start")
emit("chimera.session.end")
assert(api.status().started==false)
-- Avoided NPC is a room hazard, not an excuse to stop patrolling.
world.room={id="r2", exits={polnoc="r1", poludnie="r3"}};world.current=2
world.vitals.hp=100
world.combat={self_active=0,relations={}}
world.entities={room="r2",entities={{id="me",kind="player",relation="self"},
  {id="mob-ork",name="wsciekly ork",kind="npc"},
  {id="mob-spider",name="gigantyczny pajak",kind="npc"}}}
cmd("exp unikaj","pajak")
local sent_before,moves_before=#sent,#moves
cmd("exp start")
tick()
assert(not api.status().paused and api.status().phase=="AVOID_ESCAPE", "avoid must attempt escape")
assert(#sent==sent_before+1 and sent[#sent]=="n", "escape through patrol-facing GMCP exit")
assert(#moves==moves_before, "do not start official walker during emergency escape")
-- Events from combat must not create duplicate escape attempts.
world.combat={self_active=1,relations={{attacker="mob-spider",defender="me"}}}
emit("chimera.combat.state",world.combat)
emit("chimera.room.entities",world.entities)
tick()
assert(#sent==sent_before+1, "only one movement command pending")
-- Confirm exit; an automatic step may be tagged 'reczny' by upstream GMCP.
world.room={id="r1",exits={poludnie="r2"}};world.current=1
world.entities={room="r1",entities={{id="me",kind="player",relation="self"}}}
world.combat={self_active=0,relations={}}
emit("chimera.room.changed",{id="r1",how="reczny"})
emit("chimera.room.entities",world.entities)
emit("chimera.combat.state",world.combat)
tick()
assert(not api.status().paused, "successful escape must not be confused with manual movement")
assert(#moves==moves_before, "patrol must not immediately return to blocked spider room")
cmd("exp stop")
-- Even if attacked BEFORE starting patrol, escape without attacking spider.
world.room={id="r2",exits={polnoc="r1",poludnie="r3"}};world.current=2
world.entities={room="r2",entities={{id="me",kind="player",relation="self"},
  {id="mob-spider",name="gigantyczny pajak",kind="npc"}}}
world.combat={self_active=1,relations={{attacker="mob-spider",defender="me"}}}
sent_before=#sent
cmd("exp start")
tick()
assert(not api.status().paused and api.status().phase=="AVOID_ESCAPE", "escape already active combat")
assert(#sent==sent_before+1 and sent[#sent]=="n", "attack never initiates a kill command")
-- Failure to leave should be bounded: second distinct exit, then pause.
time=time+5;emit("chimera.combat.state",world.combat);tick()
assert(#sent==sent_before+2 and sent[#sent]=="s", "retry a different safe exit")
time=time+5;emit("chimera.combat.state",world.combat);tick()
assert(api.status().paused, "no available unused exit should stop safely")
assert(#sent==sent_before+2, "do not spam escape commands")
cmd("exp stop")
-- An upstream walker stopped by attack must not prematurely pause AutoExp.
world.room={id="r1",exits={poludnie="r2"}};world.current=1
world.entities={room="r1",entities={{id="me",kind="player",relation="self"}}}
world.combat={self_active=0,relations={}}
sent_before=#sent
local before_moves=#moves
cmd("exp start")
tick()
assert(#moves==before_moves+1, "patrol began walking")
emit("chimera.walk.stopped",{reason="atak"})
assert(not api.status().paused, "walker attack interruption is not a manual pause")
world.room={id="r2",exits={polnoc="r1",poludnie="r3"}};world.current=2
world.entities={room="r2",entities={{id="mob-spider",name="gigantyczny pajak",kind="npc"}}}
world.combat={self_active=1,relations={{attacker="mob-spider",defender="me"}}}
emit("chimera.room.changed",{id="r2",how="chodzik"})
emit("chimera.room.entities",world.entities)
emit("chimera.combat.state",world.combat)
tick()
assert(not api.status().paused and sent[#sent]=="n", "escape even after walker stopped on attack")
cmd("exp stop")
-- A retreat in progress must not restart whenever fresh vitals arrive.
world.room={id="r1"};world.current=1
world.entities={room="r1",entities={{id="me",kind="player",relation="self"}}}
world.combat={self_active=0,relations={}}
world.vitals.hp=20
local moves_prev=#moves
cmd("exp start")
tick()
assert(#moves==moves_prev+1 and api.status().phase=="RETREAT", "retreat starts")
emit("chimera.char.vitals",world.vitals)
tick()
assert(#moves==moves_prev+1 and api.status().phase=="RETREAT", "retreat is not restarted")
cmd("exp stop")
-- Beta.4: low HP in COMBAT -> direct, confirmed-step retreat toward saved safe room.
-- The native walker would stop on combat, but a direct exit may still work.
getRoomHashByID=function(id) return ({[1]="r1",[2]="r2",[3]="r3",[5]="safe"})[id] end
getPath=function(from,to)
  speedWalkPath={}
  if from==1 and to==2 then speedWalkPath={2}; return true end
  if from==2 and to==5 then speedWalkPath={5}; return true end
  return false
end
world.room={id="r1",exits={poludnie="r2"}};world.current=1
world.entities={room="r1",entities={{id="me",kind="player",relation="self"},
  {id="danger",name="rozzloszczony goblin",kind="npc"}}}
world.combat={self_active=1,relations={{attacker="danger",defender="me"}}}
world.vitals.hp=22
local before_moves,before_sent=#moves,#sent
cmd("exp start")
tick()
assert(api.status().phase=="EMERGENCY_RETREAT" and not api.status().paused,
  "battle low hp must trigger emergency retreat")
assert(#sent==before_sent+1 and sent[#sent]=="s", "only mapped next step is sent")
assert(#moves==before_moves, "do not use walker.go while in battle")
emit("chimera.char.vitals",world.vitals);emit("chimera.combat.state",world.combat);tick()
assert(#sent==before_sent+1, "no double movement before GMCP confirmation")
world.room={id="r2",exits={polnoc="r1"}};world.current=2
world.entities={room="r2",entities={{id="me",kind="player",relation="self"}}}
emit("chimera.room.changed",{id="r2",how="reczny"})
emit("chimera.room.entities",world.entities)
tick()
assert(not api.status().paused and api.status().phase=="RECOVERY",
  "reaching configured safe room must end emergency even if fight flag lags")
assert(#sent==before_sent+1, "safe room should not cause another step")
cmd("exp stop")
-- If server ignores the step, there is one bounded retry and an explicit alarm.
world.room={id="r1",exits={poludnie="r2"}};world.current=1
world.entities={room="r1",entities={{id="me",kind="player",relation="self"},
  {id="danger",name="rozzloszczony goblin",kind="npc"}}}
world.combat={self_active=1,relations={{attacker="danger",defender="me"}}}
world.vitals.hp=21
before_sent=#sent
cmd("exp start");tick()
assert(#sent==before_sent+1,"rescue first command")
time=time+4;emit("chimera.combat.state",world.combat);tick()
assert(#sent==before_sent+2,"one retry after timeout")
time=time+4;emit("chimera.combat.state",world.combat);tick()
assert(api.status().paused,"abort after bounded failure")
assert(#sent==before_sent+2,"no movement command spam")
cmd("exp stop")
-- Continue a multi-room emergency route even if combat remains active.
storage.profiles.test.safeRoom="safe"
getPath=function(from,to)
  speedWalkPath={}
  if from==1 and to==5 then speedWalkPath={2,5}; return true end
  if from==2 and to==5 then speedWalkPath={5}; return true end
  return false
end
world.room={id="r1",exits={poludnie="r2"}};world.current=1
world.entities={room="r1",entities={{id="me",kind="player",relation="self"},
  {id="danger",name="rozzloszczony goblin",kind="npc"}}}
world.combat={self_active=1,relations={{attacker="danger",defender="me"}}}
world.vitals.hp=22
before_sent=#sent
cmd("exp start");tick()
assert(sent[#sent]=="s" and #sent==before_sent+1,"first emergency step")
world.room={id="r2",exits={wschod="safe",polnoc="r1"}};world.current=2
world.entities={room="r2",entities={{id="me",kind="player",relation="self"}}}
emit("chimera.room.changed",{id="r2",how="reczny"});tick()
assert(#sent==before_sent+2 and sent[#sent]=="e" and not api.status().paused,
  "second emergency step even with active combat")
world.room={id="safe",exits={zachod="r2"}};world.current=5
world.entities={room="safe",entities={{id="me",kind="player",relation="self"}}}
emit("chimera.room.changed",{id="safe",how="reczny"});tick()
assert(api.status().phase=="RECOVERY" and not api.status().paused,
  "two-step retreat should arrive at designated safe room")
cmd("exp stop")
print("AutoExp 5: integration mock tests PASS; commands",#sent,"moves",#moves)
