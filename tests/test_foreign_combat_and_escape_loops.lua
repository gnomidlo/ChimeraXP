-- Regression: foreign combat ownership and bounded escape across adjacent hazards.
local P = assert(loadfile("plugins/chimera_autoexp/init.lua"))()
local function trial(case)
  local handlers, commands, timers, sent, logs = {}, {}, {}, {}, {}
  local now=100
  local original_time=os.time; os.time=function() return now end
  getRoomIDbyHash=function(id) return ({s=1,d=2,a=3,safe=4})[id] or -1 end
  getRoomHashByID=function(id) return ({[1]="s",[2]="d",[3]="a",[4]="safe"})[id] end
  getPath=function(from,to) speedWalkPath={to}; return from~=to end
  local mob={id="mob",name="zielony goblin",kind="npc"}
  local spider={id="spider",name="wielki pajak",kind="npc"}
  local visitor={id="visitor",name="obcy",kind="player",relation="neutral"}
  local room={id="s",exits={zachod="d"}}
  if case=="alternate" then room.exits.poludnie="a" end
  local world={
    room=room,current=1,entities={room="s",entities={
      {id="me",self=1,relation="self",kind="player"},spider}},
    group={members={{id="me",self=1,here=1,hp=100,maxhp=100}}},
    vitals={hp=100},combat={self_active=0,relations={}}
  }
  local function emit(key,value) for _,f in ipairs(handlers[key] or {}) do f(value) end end
  local ctx={
    state={},log={info=function(t) logs[#logs+1]=t end,warn=function(t) logs[#logs+1]=t end},
    saved=function(_,k,d)
      if k=="selected" then return "test" end
      if k=="profiles" then return {test={name="test",route={"d","s","a"},
        targets={"goblin"},avoid={"pajak"},safeRoom="safe",rules={
        escapeWait=4,escapeMaxTries=3,maxEnemies=3,retreatHP=35,returnHP=85,
        minRoomRevisit=60,syncWait=4,attackWait=3,lootGrace=7}}} end
      return d
    end,
    save=function() end,
    use=function(_,key)
      return ({
        gmcp={room=function() return world.room end,entities=function() return world.entities end,
          group=function() return world.group end,combat=function() return world.combat end,
          vitals=function() return world.vitals end,connected=function() return true end},
        mapper={current_room=function() return world.current end},
        walker={go=function() emit("chimera.walk.started",{});return true end,
          stop=function(msg) emit("chimera.walk.stopped",{reason=msg});return true end}
      })[key]
    end,
    on=function(_,k,fn) handlers[k]=handlers[k] or {};table.insert(handlers[k],fn) end,
    command=function(_,o) commands[o[1]]=o.fn end,
    timer=function(_,d,fn,repeat_) local id=#timers+1;timers[id]={fn=fn,active=true,repeating=repeat_};return id end,
    cancel=function(_,id) if timers[id] then timers[id].active=false end end,
    cleanup=function() end,
    send=function(_,txt) sent[#sent+1]=txt; if ({w=1,e=1,s=1,n=1})[txt] then
      emit("chimera.step.manual",{direction=txt}) end end,
    report=function() end
  }
  local api=P.setup(ctx)
  local function tick()
    local due={}
    for i,t in ipairs(timers) do if t.active and not t.repeating then due[#due+1]=i end end
    for _,i in ipairs(due) do local t=timers[i]; t.active=false;t.fn() end
  end
  local function place(id,exits,ents)
    world.room={id=id,exits=exits}
    world.current=({s=1,d=2,a=3,safe=4})[id]
    world.entities={room=id,entities={{id="me",self=1,relation="self",kind="player"}}}
    for _,e in ipairs(ents) do table.insert(world.entities.entities,e) end
    emit("chimera.room.changed",{id=id,how="reczny"})
    emit("chimera.room.entities",world.entities)
    tick()
  end
  if case=="loop" or case=="alternate" then
    commands["exp start"]();tick()
    assert(sent[#sent]=="w" and not api.status().paused,"initial spider exit")
    local four={}
    for i=1,4 do four[#four+1]={id="crowd"..i,name="goblin",kind="npc"} end
    place("d",{wschod="s"},four)
    if case=="loop" then
      assert(api.status().paused, "two hazardous rooms with no alternative MUST pause")
      assert(#sent==1, "do not consume stamina bouncing in a hazard loop")
      assert(table.concat(logs,";"):find("petl",1,true),"clear loop warning")
    else
      assert(not api.status().paused and sent[#sent]=="e","backtrack allowed if previous hazard has an unused exit")
      place("s",{zachod="d",poludnie="a"},{spider})
      assert(not api.status().paused and sent[#sent]=="s","choose fresh exit after backtracking")
      assert(#sent==3,"only three moves across two hazardous rooms")
    end
  elseif case=="preexisting" then
    world.entities.entities={world.entities.entities[1],visitor,mob}
    world.combat={self_active=0,relations={{attacker="visitor",defender="mob"}}}
    commands["exp start"]();tick()
    assert(sent[#sent]=="w","leave an occupied fight detected on entry")
    assert(api.status().phase=="AVOID_ESCAPE","occupied fight escape")
  elseif case=="joins" then
    world.entities.entities={world.entities.entities[1],mob}
    world.combat={self_active=1,relations={{attacker="me",defender="mob"}}}
    commands["exp start"]();tick()
    assert(api.status().phase=="COMBAT" and #sent==0,"own ongoing combat")
    table.insert(world.entities.entities,visitor)
    table.insert(world.combat.relations,{attacker="visitor",defender="mob"})
    emit("chimera.room.entities",world.entities)
    emit("chimera.combat.state",world.combat);tick()
    assert(api.status().phase=="COMBAT" and #sent==0 and not api.status().paused,
      "do not flee when outside player joins own combat")
  elseif case=="pending" then
    world.entities.entities={world.entities.entities[1],mob}
    commands["exp start"]();tick()
    assert(sent[1]=="zabij mob","engagement command sent")
    table.insert(world.entities.entities,visitor)
    world.combat={self_active=0,relations={{attacker="visitor",defender="mob"}}}
    emit("chimera.room.entities",world.entities)
    emit("chimera.combat.state",world.combat);tick()
    assert(#sent==1 and not api.status().paused,"foreign callback before own combat GMCP update must not trigger escape")
  end
  commands["exp stop"]()
  os.time=original_time
  print("PASS foreign/loop",case)
end
for _,name in ipairs({"preexisting","joins","pending","loop","alternate"}) do trial(name) end
