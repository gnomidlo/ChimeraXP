-- Real shop/bank economy state machine: mock GMCP + walker, no live game.
local P=assert(loadfile("plugins/chimera_autoexp/init.lua"))()
local function scenario(confirm, automatic, configured_delay, cancel_in_shop, no_encumbrance, two_corpses)
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
  if configured_delay then
    commands["exp zarobek tempo"](tostring(configured_delay))
    assert(profile.rules.economyCommandDelay==configured_delay,
        "economy tempo command persists the selected interval")
  end
  local delay=configured_delay or 0.7
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
    if two_corpses then profile.loot={"bronie","zbroje"} end
    profile.economy={enabled=true}
    if no_encumbrance then
      data.vitals.encumbrance=nil
    else
      data.vitals.encumbrance=60
    end
    table.insert(data.entities.entities,{id="goblin",kind="npc",name="zielony goblin"})
    commands["exp start"]()
    advance(0)
    assert(sent[1]=="zabij goblin","normal patrol fights before loot")
    assert(not api.status().paused,
      "absent encumbrance field is zero; never pause active exp")
    data.combat={self_active=1,relations={{attacker="me",defender="goblin"}}}
    emit("chimera.combat.state",data.combat);advance(0)
    assert(api.status().phase=="COMBAT","own fight")
    data.combat={self_active=0,relations={}}
    data.entities.entities={{id="me",kind="player",relation="self"}}
    emit("chimera.combat.state",data.combat);advance(0)
    clock=clock+2
    emit("chimera.char.vitals",data.vitals);advance(0)
    assert(sent[2]=="policz ciala","count corpses before taking any loot")
    assert(#sent==2,"do not take from unspecified corpse before server count")
    local response=two_corpses and "dwoch sztuk" or "jednej sztuki"
    local count_ack=false
    for _,t in ipairs(triggers) do
      if t.pattern:find(response,1,true) then t.fn(); count_ack=true; break end
    end
    assert(count_ack,"server count phrase must have a registered trigger")
    local expected={}
    if two_corpses then
      expected={
        "wez bronie z 1. ciala", "wez zbroje z 1. ciala",
        "wez bronie z 2. ciala", "wez zbroje z 2. ciala"
      }
    else
      expected={"wez bronie z 1. ciala"}
    end
    for index,text in ipairs(expected) do
      assert(sent[index+2]==text, "corpse/item sequence wrong at step "..index)
      advance(delay*0.5)
      assert(#sent==index+2,"next loot command must not overlap")
      advance(delay*0.5+0.001)
    end
    assert(#sent==2+#expected,"no duplicate item take across corpses")
    data.vitals.encumbrance=80
    emit("chimera.char.vitals",data.vitals)
    advance(0.71) -- GMCP weight synchronization grace (0.7s)
    assert(moves[#moves]==2,"overload triggers shop trip")
    base=2+(two_corpses and 4 or 1)
  else
    commands["exp zarobek kurs"]()
    advance(0)
    assert(moves[#moves]==2 and #sent==0,"manual trade starts with shop walk")
  end
  travel("shop")
  assert(sent[base+1]=="sprzedaj bronie","weapons first")
  if cancel_in_shop then
    commands["exp stop"]()
    advance(10)
    assert(#sent==base+1 and #moves==1,
        "stopping during shop sale cancels all future commands and travel")
    os.time=oldtime
    print("PASS economy fast cancellation")
    return
  end
  advance(delay*0.5)
  assert(#sent==base+1,"armor command must not overlap weapons command")
  advance(delay*0.5+0.001)
  assert(sent[base+2]=="sprzedaj zbroje","armors second")
  advance(delay+0.001)
  assert(moves[#moves]==3,"must travel to bank immediately after configured delay")
  travel("bank")
  assert(sent[base+3]=="ALIAS:wem","deposit alias")
  advance(delay*0.5)
  assert(#sent==base+3,"denomination must wait for deposit interval")
  advance(delay*0.5+0.001)
  assert(sent[base+4]=="zdenominuj","denomination after wem")
  assert(#sent==base+4,"must wait for bank confirmation before wlm")
  if confirm then
    for _,t in ipairs(triggers) do
      if t.pattern:find("zostaly zdenominowane",1,true) then t.fn() end
    end
    assert(sent[base+5]=="ALIAS:wlm","withdraw alias must wait for confirmation")
    advance(delay*0.5)
    assert(moves[#moves]==3,"return must not start before withdrawal grace")
    advance(delay*0.5+0.001)
    assert(moves[#moves]==1,"return to original GMCP room")
    if automatic then
      if no_encumbrance then
        data.vitals.encumbrance=nil
      else
        data.vitals.encumbrance=20
      end
    end
    travel("home")
    if automatic then
      assert(not api.status().paused and api.status().phase~="OFF",
          "auto mode resumes patrol after successful shop/bank when encumbrance absent")
      if no_encumbrance then
        assert(table.concat(log,";"):find("wznowienie patrolu (0)",1,true),
          "missing encumbrance after bank must become zero, logs="..table.concat(log,";")..", phase="..api.status().phase)
      end
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
scenario(true,false,1.2)
scenario(true,false,nil,true)
scenario(true,true,nil,false,true)
scenario(true,true,nil,false,false,true)
