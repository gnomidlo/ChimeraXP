-- Real shop/bank economy state machine: mock GMCP + walker, no live game.
local P=assert(loadfile("plugins/chimera_autoexp/init.lua"))()
local function scenario(confirm, automatic)
  local clock=100
  local oldtime=os.time
  os.time=function() return clock end
  local commands,handlers,triggers,timers,moves,sent,log={},{},{},{},{},{},{}
  local map={home=1,shop=2,bank=3}
  getRoomIDbyHash=function(h) return map[h] or -1 end
  getRoomHashByID=function(id) for h,n in pairs(map) do if n==id then return h end end end
  getPath=function(from,to) speedWalkPath={to};return from~=to end
  local data={
    room={id="home",exits={wschod="shop"}},current=1,
    entities={room="home",entities={{id="me",kind="player",relation="self"}}},
    vitals={hp=100,encumbrance=80},
    combat={self_active=0,relations={}},
    group={members={{id="me",self=1,here=1,hp=100,maxhp=100}}}
  }
  local function emit(ev,msg)
    for _,fn in ipairs(handlers[ev] or {}) do fn(msg) end
  end
  expandAlias=function(command,send) sent[#sent+1]="ALIAS:"..command end
  local profile={name="Test",route={"home"},targets={"goblin"},avoid={},
     loot={"bronie"},safeRoom="home",rules={retreatHP=35,returnHP=85,
       maxEnemies=3,syncWait=4,attackWait=3,lootGrace=7,
       minRoomRevisit=60,escapeWait=4,escapeMaxTries=3,
       economyLoadThreshold=75}}
  local ctx={
    state={},log={info=function(t) log[#log+1]=t end,warn=function(t) log[#log+1]=t end},
    saved=function(_,key,default)
      if key=="selected" then return "test" end
      if key=="profiles" then return {test=profile} end
      return default
    end,
    save=function() end,
    use=function(_,name)
      return ({
        gmcp={room=function()return data.room end,
          vitals=function()return data.vitals end,
          entities=function()return data.entities end,
          combat=function()return data.combat end,
          group=function()return data.group end,
          connected=function()return true end},
        mapper={current_room=function()return data.current end},
        walker={cost=function(a,b)return math.abs(a-b) end,
          go=function(dest)
            moves[#moves+1]=dest
            emit("chimera.walk.started",{map_room=dest})
            return true
          end,
          stop=function(reason)emit("chimera.walk.stopped",{reason=reason});return true end},
        locations={targets=function(tag) return
          ({sklep={"shop"},bank={"bank"}})[tag] or {} end}
      })[name]
    end,
    on=function(_,name,fn)
      handlers[name]=handlers[name] or {}
      handlers[name][#handlers[name]+1]=fn
    end,
    command=function(_,r) commands[r[1]]=r.fn end,
    trigger=function(_,pattern,fn) triggers[#triggers+1]={pattern=pattern,fn=fn} end,
    timer=function(_,seconds,fn,repeating)
      local i=#timers+1
      timers[i]={when=clock+seconds,fn=fn,active=true,repeating=repeating}
      return i
    end,
    cancel=function(_,i) if timers[i] then timers[i].active=false end end,
    cleanup=function()end,
    send=function(_,msg)sent[#sent+1]=msg end,
    report=function()end,
  }
  local api=P.setup(ctx)
  local function advance(seconds)
    clock=clock+seconds
    for rounds=1,100 do
      local ready={}
      for i,t in ipairs(timers) do
        if t.active and not t.repeating and t.when<=clock then ready[#ready+1]=i end
      end
      if #ready==0 then return end
      for _,i in ipairs(ready) do local t=timers[i]; t.active=false; t.fn() end
    end
    error("runaway timer loop")
  end
  local function travel(where)
    assert(moves[#moves]==map[where],"wrong walker destination: "..tostring(moves[#moves]))
    data.current=map[where]
    data.room={id=where,exits={}}
    data.entities={room=where,entities={{id="me",kind="player",relation="self"}}}
    emit("chimera.room.changed",{id=where,how="chodzik"})
    emit("chimera.room.entities",data.entities)
    emit("chimera.walk.arrived",{map_room=map[where],target=where})
    advance(0)
  end
  local base=0
  if automatic then
    profile.economy={enabled=true}
    data.vitals.encumbrance=60
    table.insert(data.entities.entities,{id="goblin",kind="npc",name="zielony goblin"})
    commands["exp start"]()
    advance(0)
    assert(sent[1]=="zabij goblin","normal patrol fights before loot")
    data.combat={self_active=1,relations={{attacker="me",defender="goblin"}}}
    emit("chimera.combat.state",data.combat);advance(0)
    assert(api.status().phase=="COMBAT","own fight")
    data.combat={self_active=0,relations={}}
    data.entities.entities={{id="me",kind="player",relation="self"}}
    emit("chimera.combat.state",data.combat);advance(0)
    clock=clock+7
    emit("chimera.char.vitals",data.vitals);advance(0)
    assert(sent[2]=="wez bronie z ciala","collect configured loot after combat")
    advance(2)
    data.vitals.encumbrance=80
    emit("chimera.char.vitals",data.vitals);advance(0)
    assert(moves[#moves]==2,"overload triggers shop trip")
    base=2
  else
    commands["exp zarobek kurs"]()
    advance(0)
    assert(moves[#moves]==2 and #sent==0,"manual trade starts with shop walk")
  end
  travel("shop")
  assert(sent[base+1]=="sprzedaj bronie","weapons first")
  advance(3)
  assert(sent[base+2]=="sprzedaj zbroje","armors second")
  advance(3)
  assert(moves[#moves]==3,"must travel to bank after shop")
  travel("bank")
  assert(sent[base+3]=="ALIAS:wem","deposit alias")
  advance(3)
  assert(sent[base+4]=="zdenominuj","denomination after wem")
  assert(#sent==base+4,"must wait for bank confirmation before wlm")
  if confirm then
    for _,t in ipairs(triggers) do
      if t.pattern:find("zostaly zdenominowane",1,true) then t.fn() end
    end
    assert(sent[base+5]=="ALIAS:wlm","withdraw alias must wait for confirmation")
    advance(3)
    assert(moves[#moves]==1,"return to original GMCP room")
    if automatic then data.vitals.encumbrance=20 end
    travel("home")
    if automatic then
      assert(not api.status().paused and api.status().phase~="OFF",
          "auto mode resumes patrol after successful shop/bank")
    else
      assert(api.status().phase=="OFF","manual test must stop after return")
    end
  else
    advance(21)
    assert(api.status().paused,"no denomination ack -> fail closed")
    assert(#sent==base+4,"never withdraw after unconfirmed denomination")
  end
  os.time=oldtime
  print("PASS economy live course",automatic and "automatic" or "manual",confirm and "complete" or "timeout")
end
scenario(true)
scenario(false)
scenario(true,true)
