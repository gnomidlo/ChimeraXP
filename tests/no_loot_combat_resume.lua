-- After confirmed combat end the XP walker must not wait for a loot
-- grace period unless auto-commerce actually has loot to collect.
local new=dofile("tests/support_harness.lua")
local P=dofile("plugins/chimera_autoexp/init.lua")

local function setup(economy_enabled, loot)
    local h=new()
    h.p.vitals={hp=100,fatigue=0,encumbrance=0}
    for _,m in ipairs(h.p.group.members) do m.hp=m.maxhp end
    for _,e in ipairs(h.p.entities.entities) do e.hp=e.maxhp end
    h.p.room={id="rooma",key="rooma",exits={wschod="roomnext"}}
    h.p.combat={room="rooma",primary="enemy1",self_active=1,
        relations={{attacker="me",defender="enemy1"},{attacker="enemy1",defender="me"}}}
    h.saved.selected="test"
    h.saved.profiles={test={name="Test",route={"rooma","roomnext"},
        targets={"goblin"},safeRoom="safe",loot=loot or {"kamienie"},
        economy={enabled=economy_enabled},
        rules={maxEnemies=8,retreatHP=35,returnHP=85,minRoomRevisit=0,
            economyLootGrace=2,lootGrace=7}}}
    local ids={rooma=1,roomnext=2,safe=3}
    getRoomIDbyHash=function(id) return ids[id] end
    getRoomHashByID=function(id)
        for hash,num in pairs(ids) do if num==id then return hash end end
    end
    getPath=function(from,to) speedWalkPath={to};return from~=to end
    h.api=P.setup(h.ctx)
    h.api.request("start")
    h.advance(.1)
    assert(h.api.status().phase=="COMBAT", "fixture must begin during confirmed combat")
    assert(#h.moves==0,"no patrol movement while fighting")

    function h.finish()
        for i=#h.p.entities.entities,1,-1 do
            if h.p.entities.entities[i].relation=="hostile" then
                table.remove(h.p.entities.entities,i)
            end
        end
        h.p.combat={room="rooma",primary="",self_active=0,relations={}}
        h.emit("chimera.combat.state",h.p.combat)
        h.emit("chimera.room.entities",h.p.entities)
        h.advance(.1)
    end
    return h
end

do
    local h=setup(false,{"kamienie"})
    h.finish()
    assert(h.moves[1]==2, "disabled economy must walk on first post-combat GMCP evaluation")
    assert(#h.sent==0, "disabled economy must never count or collect corpses")
    assert(not h.api.status().fallback and not h.api.status().paused,"no safety fallback")
    h.dispose()
end
do
    local h=setup(true,{})
    h.finish()
    assert(h.moves[1]==2, "empty loot list must not impose a post-combat delay")
    assert(#h.sent==0, "empty loot list does not count corpses")
    h.dispose()
end
do
    local h=setup(true,{"kamienie"})
    h.finish()
    assert(#h.moves==0 and #h.sent==0, "configured loot grace must still apply")
    h.advance(1.1)
    assert(#h.moves==0 and #h.sent==0, "do not collect before grace expires")
    h.advance(1.2)
    assert(h.sent[1]=="policz ciala", "economy continues corpse counting after its grace")
    assert(#h.moves==0, "do not leave before collecting")
    h.dispose()
end
print("PASS no-loot post-combat path immediate; economy loot retains grace")
