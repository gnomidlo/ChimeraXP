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
-- Fight begins; low hp means fail-closed pause (native walker won't retreat midfight).
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
print("AutoExp 5: integration mock tests PASS; commands",#sent,"moves",#moves)