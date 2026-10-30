-- A foe can leave after combat starts, without leaving a corpse.
local new=dofile("tests/support_harness.lua")
local P=dofile("plugins/chimera_autoexp/init.lua")
local EMPTY=[[^Nie widzisz tu niczego takiego\.$]]
local function fixture()
    local h=new()
    h.p.vitals.hp=100;h.p.vitals.encumbrance=0
    for _,m in ipairs(h.p.group.members) do m.hp=100 end
    for _,m in ipairs(h.p.entities.entities) do m.hp=100 end
    h.saved.profiles={test={name="Gnolle",route={"rooma","safe"},targets={"Goblin"},avoid={},loot={"bronie"},
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
    for _,command in ipairs(h.sent) do assert(not command:match("^wez "),"no taking from nonexistent corpses") end
    h.dispose()
end
do
    local h=fixture();leave_without_corpse(h)
    h.triggers[ [[^Doliczyl(?:as|es) sie dwoch sztuk\.$]] ]()
    h.triggers[EMPTY]();h.advance(6)
    local taken=0
    for _,command in ipairs(h.sent) do if command:match("^wez ") then taken=taken+1 end end
    assert(taken==2 and not h.api.status().paused,"empty take response cannot overwrite an already confirmed corpse count")
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
print("PASS empty corpse response: escaped foe, patrol resume, no take, duplicate, unrelated, STOP and room guards")
