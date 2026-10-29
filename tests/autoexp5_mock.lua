local path = "plugins/chimera_autoexp/init.lua"
local P = dofile(path)
assert(P.name == "autoexp" and #P.deps == 4 and P.deps[4] == "locations",
  "locations must be declared as an official Chimera module dependency")
local declared_deps={}
for _, name in ipairs(P.deps) do declared_deps[name]=true end
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
  cost=function(from, destination) return math.abs(destination - from) end,
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
      assert(declared_deps[key], "undeclared ctx:use dependency: "..tostring(key))
      return ({
        gmcp=gmcp,mapper={current_room=function() return world.current end},
        walker=walker,
        locations={targets=function(tag)
          return ({sklep={"r3"},bank={"safe"}})[tag] or {}
        end}
      })[key]
    end,
    saved=function(_,key,default) return storage[key] or default end,
    save=function(_,key,value) storage[key] = value end,
    trigger=function() end,
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
-- Economy phase 1 is configuration + read-only diagnostics.
cmd("exp lup dodaj","miecz")
cmd("exp lup dodaj","miecz")
cmd("exp lup dodaj","tarcze")
cmd("exp lup lista")
assert(#storage.profiles.test.loot==2 and storage.profiles.test.loot[1]=="miecz",
  "loot wishlist deduplicated and saved per exp profile")
cmd("exp zarobek prog","75")
assert(storage.profiles.test.rules.economyLoadThreshold==75,"saved economy limit")
local saved_global_gmcp=_G.gmcp
_G.gmcp={Char={Vitals={weight=75,max_weight=100}}}
cmd("exp zarobek diagnoza")
cmd("exp zarobek trasa")
_G.gmcp={Char={Vitals={hp=100}}}
cmd("exp zarobek diagnoza")
assert(table.concat(messages,";"):find("Obciazenie GMCP: 0 (brak pola encumbrance = 0)",1,true),
  "diagnostics must treat absent field in otherwise valid Vitals as zero")
_G.gmcp={Char={Vitals={hp=100,encumbrance="bledna"}}}
cmd("exp zarobek diagnoza")
assert(table.concat(messages,";"):find("Brak poprawnego pakietu Char.Vitals / encumbrance.",1,true),
  "explicit malformed encumbrance must not be silently interpreted as zero")
_G.gmcp=saved_global_gmcp
assert(#sent==0 and #moves==0, "economy diagnostics and planning cannot move, loot or sell")
assert(table.concat(messages,";"):find("Sklep: mapa 3, GMCP r3",1,true),
  "route planner selects tagged shop")
assert(table.concat(messages,";"):find("Bank: mapa 5, GMCP safe",1,true),
  "route planner selects bank from selected shop")
assert(table.concat(messages,";"):find("gmcp.Char.Vitals.weight = 75",1,true),
  "diagnostics display a candidate weight field but do not infer %")
cmd("exp lup usun","miecz")
assert(#storage.profiles.test.loot==1 and storage.profiles.test.loot[1]=="tarcze",
  "loot wishlist remove")

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
assert(#moves==moves_before+1 and moves[#moves]==2, "transit through previously avoided spider room must remain possible")
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
-- New console panel: closest profiles are ranked by walker route cost,
-- links execute the original /exp wybierz alias, and quiet mode preserves history.
local links,rendered={},{}
local old_cechoLink,old_cecho,old_expandAlias=cechoLink,cecho,expandAlias
cecho=function(value) rendered[#rendered+1]=value end
cechoLink=function(label,fn,hint) links[#links+1]={label=label,fn=fn,hint=hint} end
expandAlias=function(alias)
  local name=alias:match("^/exp wybierz (.+)$")
  if name then cmd("exp wybierz",name) end
end
-- Add two distinct profiles by recording separate current rooms.
world.room={id="r3",name="Trzeci"};world.current=3
cmd("exp mapuj","Bliskie")
cmd("exp mapuj","Bliskie")
world.room={id="safe",name="Piate"};world.current=5
cmd("exp mapuj","Dalekie")
cmd("exp mapuj","Dalekie")
world.room={id="r2",name="Drugie"};world.current=2
links,rendered={},{}
cmd("exp")
local nearest={}
for _,v in ipairs(links) do
  local plain=v.label:gsub("<[^>]+>","")
  local name=plain:match("^%s*(.-)%s*%[(%d+)%]$")
  if name then nearest[#nearest+1]=name end
end
assert(#nearest==3,"/exp must expose exactly three reachable expowiska")
assert(nearest[1]:find("Test",1,true) and nearest[2]:find("Bliskie",1,true)
  and nearest[3]:find("Dalekie",1,true),
  "nearest list must rank by actual minimum cost across route rooms")
for _,v in ipairs(links) do
  if v.label:find("Bliskie",1,true) and v.label:find("[1]",1,true) then
    v.fn()
    break
  end
end
assert(api.status().selected=="bliskie","profile click switches using existing alias")
cmd("exp glosnosc","quiet")
assert(storage.verbosity=="quiet","verbosity should persist globally")
local before_messages=#messages
cmd("exp panel","walka")
assert(#rendered>0,"console panel should render native Mudlet links and text")
cmd("exp log")
assert(#rendered>0 and #messages>=before_messages,"event history should be accessible")
cmd("exp glosnosc","debug")
assert(storage.verbosity=="debug","diagnostics mode must persist")
cechoLink,cecho,expandAlias=old_cechoLink,old_cecho,old_expandAlias
-- Responsive Geyser.Container regression: drag, mini, resize, cached labels.
local oldGeyser,oldSetCmdLine,oldGetMousePosition=Geyser,setCmdLine,getMousePosition
local oldMove,oldRelease,oldClick=setLabelMoveCallback,setLabelReleaseCallback,setLabelClickCallback
local oldScreen=getMainWindowSize
local labels,callbacks,moves,releases={}, {}, {}, {}
local roots,created= {},0
getMainWindowSize=function()return 1000,800 end
local mouse={100,100}
getMousePosition=function()return mouse[1],mouse[2] end
setLabelClickCallback=function(name,fn)callbacks[name]=fn end
setLabelMoveCallback=function(name,fn)moves[name]=fn end
setLabelReleaseCallback=function(name,fn)releases[name]=fn end
setCmdLine=function(value)world.input=value end
Geyser={
 Container={new=function(_,opt)
  local root={opt=opt,x=opt.x,y=opt.y,w=opt.width,h=opt.height}
  function root:move(x,y)self.x,self.y=x,y end
  function root:resize(w,h)self.w,self.h=w,h end
  function root:hide()self.hidden=true end
  function root:show()self.hidden=false end
  function root:delete()self.deleted=true end
  roots[#roots+1]=root
  return root
 end},
 Label={new=function(_,opt,root)
   local item={name=opt.name,root=root,text=""}
   created=created+1
   function item:move(x,y)self.x,self.y=x,y end
   function item:resize(w,h)self.w,self.h=w,h end
   function item:setStyleSheet(css)self.css=css end
   function item:echo(html)self.text=html end
   function item:delete()self.deleted=true end
   function item:hide()self.hidden=true end
   function item:show()self.hidden=false end
   function item:setClickCallback(cb)callbacks[self.name]=cb end
   labels[item.name]=item
   return item
 end}
}
cmd("exp")
assert(#roots==3 and roots[1].w==1000 and roots[1].h==40,
 "opening /exp creates the compact bar, overlay and small run label")
assert(api.hud.labels.party and api.hud.labels.areas and api.hud.labels.stop,"main controls exist")
local oldcreated=created
cmd("exp")
assert(created==oldcreated,"rendering unchanged UI must reuse cached labels")
getMainWindowSize=function()return 320,400 end
emit("sysWindowResizeEvent")
assert(roots[1].w==320 and roots[1].h==40,"HUD adapts without a large floating window")
cmd("exp hud","off");assert(roots[1].hidden,"HUD can be hidden")
cmd("exp hud","on")
api.hud:open("profiles")
local renamed=false
for _,item in pairs(api.hud.labels) do
 if item.html and item.html:find("Zmień nazwę",1,true) then callbacks[item.widget.name]();renamed=true end
end
assert(renamed,"profile name editor exists")
assert(world.input=="/exp nazwa ","rename should prefill command line")
local previous=api.status().selected
local rooms=#storage.profiles[previous].route
cmd("exp nazwa","Nowa nazwa")
assert(api.status().selected=="nowa nazwa" and not storage.profiles[previous]
 and #storage.profiles["nowa nazwa"].route==rooms,
 "rename should migrate selected profile without losing route")
Geyser,setCmdLine,getMousePosition=oldGeyser,oldSetCmdLine,oldGetMousePosition
setLabelMoveCallback,setLabelReleaseCallback,setLabelClickCallback=oldMove,oldRelease,oldClick
getMainWindowSize=oldScreen
-- Online updater command delegates to the Mudlet package bootstrap.
local update_calls = 0
chimera_xp_updater = {check=function(_, verbose)
  assert(verbose == true)
  update_calls = update_calls + 1
end}
cmd("exp aktualizuj")
assert(update_calls == 1,"/exp aktualizuj should invoke online updater")
chimera_xp_updater = nil
print("AutoExp 5: integration mock tests PASS; commands",#sent,"moves",#moves)

