local new=dofile("tests/support_harness.lua")
local plugin=dofile("plugins/chimera_autoexp/init.lua")
local DARK=[[^[ >]*Ciemne miejsce\.$]]
local DEAD=[[^[ >]*Umierasz\.$]]
local function fixture()
    local h=new()
    h.saved.selected="test"
    h.saved.profiles={test={name="Test",route={"a","b","c"},safeRoom="safe",safeKey="safe",
        targets={"goblin"},avoid={"ettin"},rules={minRoomRevisit=30}}}
    local rooms={a=1,b=2,c=3,safe=4}
    getRoomIDbyHash=function(id)return rooms[id] end
    getRoomHashByID=function(id)for hash,num in pairs(rooms) do if id==num then return hash end end end
    getPath=function(from,to)
        if from==1 and to==3 then speedWalkPath={2,3} else speedWalkPath={to} end
        return true
    end
    local native=h.ctx.use
    h.ctx.use=function(ctx,name)
        if name=="mapper" then return {current_room=function()return rooms[h.p.room.id] end} end
        return native(ctx,name)
    end
    h.api=plugin.setup(h.ctx)
    function h.place(id,exits,how)
        h.p.room={id=id,key=id,exits=exits}
        h.p.combat={room=id,self_active=0,relations={}}
        h.p.entities={room=id,entities={}}
        h.emit("chimera.room.info",h.p.room)
        h.emit("chimera.room.changed",{id=id,how=how or "chodzik"})
        h.emit("chimera.room.entities",h.p.entities)
        h.emit("chimera.combat.state",h.p.combat)
    end
    h.place("a",{wyjscie="safe",wschod="b"})
    return h
end
-- Record an actual directed return passage, walk back, then lose every exit.
do
    local h=fixture()
    h.emit("sysDataSendRequest",nil,"wyjscie")
    h.place("safe",{wejscie="a"})
    h.emit("sysDataSendRequest",nil,"wejscie")
    h.place("a",{wyjscie="safe",wschod="b"})
    h.api.request("start")
    h.p.room.exits={}
    h.emit("chimera.room.info",h.p.room)
    h.advance(.1)
    assert(#h.moves==0 and #h.sent==1 and h.sent[1]=="wyjscie","use confirmed named passage")
    h.triggers[DARK]();h.advance(10)
    assert(#h.sent==1,"single outstanding return step")
    h.place("safe",{})
    h.advance(300)
    assert(h.api.status().phase=="DARK_STOP" and not h.api.status().started)
    h.emit("chimera.lamp.changed",{lit=true})
    h.advance(30);assert(#h.moves==0 and #h.sent==1)
    h.dispose()
end
-- Replay the relevant text events in order, without private session details.
-- Supply no trusted return edge; expect one alarm followed by silence until death.
do
    local h=fixture()
    h.place("a",{n=false})
    h.api.request("start")
    local saw_dark,saw_death,alarms=false,false,0
    for line in io.lines("tests/fixtures/darkness-events.txt") do
        if line=="Ciemne miejsce." then saw_dark=true;h.triggers[DARK]()
        elseif line=="Umierasz." then saw_death=true;h.triggers[DEAD]() end
        h.advance(.1)
        if saw_dark then assert(#h.sent==0,"no combat or invented exit during replay") end
    end
    for _,line in ipairs(h.messages) do if line:find("ALARM:",1,true) then alarms=alarms+1 end end
    assert(saw_dark and saw_death and alarms==1)
    assert(not h.api.status().started and not h.api.tactics.status().on)
    local n=#h.moves;h.advance(300);assert(#h.moves==n)
    h.dispose()
end
-- An already issued movement can still complete after stop. Wait for the
-- actual landing before deciding the first return direction.
do
    local h=fixture()
    h.api.request("start");h.advance(.1)
    assert(h.moves[1]==2)
    h.emit("sysDataSendRequest",nil,"e")
    h.triggers[DARK]();h.advance(2)
    assert(#h.sent==0)
    h.place("b",{n="safe"})
    h.emit("chimera.walk.arrived",{map_room=2,target="b"})
    h.advance(1)
    assert(#h.sent==1 and h.sent[1]=="n" and #h.moves==1)
    h.place("safe",{s="b"});h.advance(90)
    assert(h.api.status().phase=="DARK_STOP" and #h.moves==1)
    h.dispose()
end
-- Repeated room.info must not clear a text darkness warning in the same room.
do
    local h=fixture()
    h.place("safe",{s="b"})
    h.api.request("start");h.triggers[DARK]();h.advance(.1)
    h.emit("chimera.room.info",h.p.room)
    h.api.request("start");assert(not h.api.status().started)
    h.emit("chimera.lamp.changed",{lit=true});h.emit("chimera.room.info",h.p.room)
    h.api.request("start");assert(h.api.status().started)
    h.dispose()
end
-- Manual step yields until confirmed; manual pause cancels the automatic resume.
for _,explicit in ipairs({false,true}) do
    local h=fixture();h.api.request("start")
    h.emit("chimera.step.manual",{direction="e"})
    h.advance(10);assert(h.api.status().paused and #h.moves==0)
    h.place("b",{n="c"},"reczny")
    if explicit then h.api.request("pauza") end
    h.advance(4)
    assert(h.api.status().paused==explicit)
    h.dispose()
end
-- Two different crowded rooms in succession with a forward exit.
do
    local h=fixture()
    local crowd={}
    for i=1,4 do crowd[i]={id="g"..i,kind="npc",name="goblin"} end
    h.p.room.exits={wschod="b"}
    h.p.entities.entities=crowd
    h.api.request("start");h.advance(.1)
    h.place("b",{zachod="a",wschod="c"},"reczny")
    h.p.entities.entities=crowd
    h.emit("chimera.room.entities",h.p.entities);h.advance(.1)
    assert(#h.sent==2 and h.sent[1]=="e" and h.sent[2]=="e" and not h.api.status().fallback)
    h.dispose()
end
print("PASS darkness replay, return evidence, late arrival, safe stop, operator leases and consecutive hazards")
-- Combat callbacks depend on the native walker's attack option. A direction
-- already dispatched by the walker must settle before XP chooses another.
for _,mode in ipairs({"zatrzymaj","cofnij","ignoruj"}) do
    local h=fixture();h.settings["walker.przy_ataku"]=mode
    h.api.request("start");h.advance(.1)
    h.emit("sysDataSendRequest",nil,"e")
    h.p.combat={room="a",self_active=1,relations={}}
    if mode~="ignoruj" then h.emit("chimera.walk.stopped",{reason="atak"}) end
    h.emit("chimera.combat.state",h.p.combat);h.advance(.5)
    assert(#h.moves==1 and #h.sent==0)
    h.place("b",{n="safe"})
    if mode=="ignoruj" then h.emit("chimera.walk.arrived",{target="b",map_room=2}) end
    h.triggers[DARK]();h.advance(1)
    assert(#h.sent==1 and h.sent[1]=="n")
    h.dispose()
end
-- A confirmed refusal while escaping darkness preserves the original intent.
do
    local h=fixture();h.p.vitals.fatigue=100
    h.api.request("start");h.triggers[DARK]();h.advance(.1)
    assert(h.sent[1]=="wyjscie")
    h.triggers[ [[^Jestes tak zmeczon[ay], ze nie mozesz isc w tym kierunku\.$]] ]()
    h.advance(3);assert(#h.sent==1)
    h.p.vitals.fatigue=10;h.emit("chimera.char.vitals");h.advance(.1)
    assert(h.sent[2]=="wyjscie" and #h.moves==0)
    h.place("safe",{});h.advance(1);assert(h.api.status().phase=="DARK_STOP")
    h.dispose()
end

-- Reported limit 2: three trolls at the junction and three in the pit.
do
    local h=fixture()
    local crowd={}
    for i=1,3 do crowd[i]={id="t"..i,kind="npc",name="goblin troll"} end
    h.api.request("limit","2")
    h.place("safe",{poludnie="a"})
    h.place("a",{polnoc="safe",wschod="b",zachod="c"})
    h.p.entities.entities=crowd
    h.api.request("start");h.advance(.1)
    assert(h.sent[1]=="e")
    h.place("b",{zachod="a"},"reczny");h.p.entities.entities=crowd
    h.advance(.1);assert(h.sent[2]=="w","leave the pit")
    h.place("a",{polnoc="safe",wschod="b",zachod="c"},"reczny")
    h.p.entities.entities=crowd
    h.p.combat.self_active=1
    h.advance(.1)
    assert(h.sent[3]=="w" and #h.sent==3 and not h.api.status().paused,"take western branch")
    h.dispose()
end
