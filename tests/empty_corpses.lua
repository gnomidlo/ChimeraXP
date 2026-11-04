-- A foe can leave after combat starts, without leaving a corpse.
local new=dofile("tests/support_harness.lua")
local P=dofile("plugins/chimera_autoexp/init.lua")
local EMPTY=[[^Nie widzisz tu niczego takiego\.$]]
local function fixture(loot)
    local h=new()
    h.p.vitals.hp=100;h.p.vitals.encumbrance=0
    for _,m in ipairs(h.p.group.members) do m.hp=100 end
    for _,m in ipairs(h.p.entities.entities) do m.hp=100 end
    h.saved.profiles={test={name="Gnolle",route={"rooma","safe"},targets={"Goblin"},avoid={},loot=loot or {"bronie"},
        safeRoom="rooma",rules={maxEnemies=5},economy={enabled=true}}};h.saved.selected="test"
    getRoomIDbyHash=function(id) return id=="rooma" and 1 or 2 end
    getPath=function() return true end
    h.api=P.setup(h.ctx)
    assert(h.triggers[EMPTY],"empty count response is recognized")
    h.api.request("start");h.advance(.1)
    return h
end
local function leave_without_corpse(h)
    h.p.combat.relations={{attacker="enemy1",defender="me"}}
    h.emit("chimera.combat.state",h.p.combat);h.advance(.1)
    assert(h.api.status().phase=="COMBAT",h.api.status().phase.." / "..table.concat(h.messages,"; "))
    h.p.combat.relations={}
    for i=#h.p.entities.entities,1,-1 do
        if h.p.entities.entities[i].relation=="hostile" then table.remove(h.p.entities.entities,i) end
    end
    h.emit("chimera.room.entities",h.p.entities)
    h.emit("chimera.combat.state",h.p.combat);h.advance(2.5)
    assert(h.sent[#h.sent]=="policz ciala","count after the foe disappears")
end
do
    local h=fixture()
    local sent=#h.sent
    h.triggers[EMPTY]();assert(#h.sent==sent,"unrelated empty response before counting has no effect")
    leave_without_corpse(h)
    h.triggers[EMPTY]()
    local after=#h.sent
    h.triggers[EMPTY]();assert(#h.sent==after,"duplicate empty response cannot restart loot")
    h.advance(6)
    assert(h.api.status().started and not h.api.status().paused,"empty count cancels its timeout")
    assert(h.moves[#h.moves]==2,"patrol continues to the next route room")
    local ground=0
    for _,command in ipairs(h.sent) do
        assert(not command:match(" z %d+%. ciala$"),"no taking from nonexistent corpses")
        if command=="wez bronie" then ground=ground+1 end
    end
    assert(ground==1,"ground loot is attempted even with zero corpses")
    h.dispose()
end
do
    local h=fixture();leave_without_corpse(h)
    h.triggers[ [[^Doliczyl(?:as|es) sie dwoch sztuk\.$]] ]()
    h.triggers[EMPTY]();h.advance(6)
    local taken=0
    for _,command in ipairs(h.sent) do if command:match("^wez ") then taken=taken+1 end end
    assert(taken==3 and not h.api.status().paused,"empty ground/take response cannot overwrite an already confirmed corpse count")
    h.dispose()
end
do
    local h=fixture();leave_without_corpse(h)
    h.api.stop_all();local sent=#h.sent
    h.triggers[EMPTY]();h.advance(6)
    assert(#h.sent==sent and not h.api.status().started,"late empty count cannot undo STOP")
    h.dispose()
end
do
    local h=fixture();leave_without_corpse(h)
    h.p.room={id="elsewhere",key="elsewhere#1",exits={}}
    local sent=#h.sent;h.triggers[EMPTY]()
    assert(#h.sent==sent,"a count response from another room is ignored")
    h.dispose()
end
do
    local h=fixture({"bronie","zbroje","kamienie"});leave_without_corpse(h)
    local before=#h.sent
    h.triggers[ [[^Doliczyl(?:as|es) sie jednej sztuki\.$]] ]()
    assert(h.sent[before+1]=="wez bronie")
    h.advance(.6);assert(#h.sent==before+1,"ground commands observe pacing")
    h.advance(.11);assert(h.sent[before+2]=="wez zbroje")
    h.advance(.71);assert(h.sent[before+3]=="wez kamienie")
    h.advance(.71);assert(h.sent[before+4]=="wez bronie z 1. ciala","corpses follow the entire ground list")
    h.dispose()
end
for _,mode in ipairs({"stop","room","error"}) do
    local h=fixture({"bronie","zbroje","kamienie"});leave_without_corpse(h)
    if mode=="error" then h.ctx.send=function()error("simulated send failure")end end
    h.triggers[EMPTY]()
    local sent=#h.sent
    if mode=="stop" then h.api.stop_all()
    elseif mode=="room" then h.p.room={id="elsewhere",key="elsewhere#1",exits={}} end
    h.advance(5)
    assert(#h.sent==sent,"ground queue stops on "..mode)
    h.dispose()
end
print("PASS ground and corpse loot: ordered categories, zero corpses, pacing, duplicate replies, STOP, room guards and send failure")
