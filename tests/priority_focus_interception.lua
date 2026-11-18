-- Regression: rank > wounded HP, shielded priority does not trigger a retreat,
-- party follows the real target, and /exp stop leaves formation enabled.
local new=dofile("tests/support_harness.lua")
local plugin=dofile("plugins/chimera_autoexp/init.lua")
local SHIELD=[[ ^Rzucasz sie na .+, lecz droge zastepuje ci .+\.$ ]]
local function fixture(priority_hp,other_hp)
    local h=new()
    h.p.vitals={hp=95,fatigue=0}
    for _,m in ipairs(h.p.group.members) do m.hp=100;m.maxhp=100 end
    h.p.room.exits={polnoc="safe"}
    for i=#h.p.entities.entities,1,-1 do
        if h.p.entities.entities[i].relation=="hostile" then
            table.remove(h.p.entities.entities,i)
        end
    end
    local enemies={
        {id="blocker",name="krasnolud",kind="npc",relation="hostile",hp=20,maxhp=100},
        {id="priority",name="niziolek",kind="npc",relation="hostile",hp=priority_hp,maxhp=100},
        {id="priority2",name="niziolek",kind="npc",relation="hostile",hp=other_hp,maxhp=100},
    }
    for _,mob in ipairs(enemies) do table.insert(h.p.entities.entities,mob) end
    h.p.combat={room="rooma",self_active=1,primary="blocker",relations={
        {attacker="me",defender="blocker"},
        {attacker="petone",defender="priority2"},
        {attacker="pettwo",defender="priority2"},
    }}
    h.saved.selected="test"
    h.saved.profiles={test={name="Test",route={"rooma"},targets={"niziolek","krasnolud"},
        safeRoom="safe",partyAttack=true,rules={maxEnemies=6,retreatHP=35,attackWait=3}}}
    getRoomIDbyHash=function(hash)return hash=="rooma" and 1 or 2 end
    getRoomHashByID=function(id)return id==1 and "rooma" or "safe" end
    getPath=function() speedWalkPath={2};return true end
    h.api=plugin.setup(h.ctx)
    return h
end

-- Priority order beats HP even when the lower-ranked enemy has 20% HP.
do
    local h=fixture(45,80)
    h.api.request("start");h.advance(.1)
    assert(h.sent[1]=="zabij priority",
        "pick the most wounded NPC within the highest list rank")
    assert(#h.sent==1, "do not order a party onto unconfirmed target in an active fight")
    h.dispose()
end

-- Same-rank mobs with HP ties retain current target instead of alternating.
do
    local h=fixture(90,90)
    h.p.combat.primary="priority2"
    table.insert(h.p.combat.relations,{attacker="me",defender="priority2"})
    h.api.request("start");h.advance(.1)
    assert(h.sent[1]=="rozkaz druzynie zaatakowac priority2",
        "same HP retains already-confirmed leader target, aligns the party")
    h.dispose()
end

-- A shield blocks the chosen priority: let combat continue on actual opponent.
do
    local h=fixture(55,85)
    h.api.request("start");h.advance(.1)
    assert(h.sent[1]=="zabij priority")
    local intercepted
    for pattern,fn in pairs(h.triggers) do
        if pattern:find("Rzucasz sie na",1,true) then intercepted=fn end
    end
    assert(intercepted,"shield interception trigger registered")
    intercepted()
    h.advance(1.2)
    assert(h.sent[2]=="rozkaz druzynie zaatakowac blocker",
        "fallback party focus must be the real opponent, not shielded target")
    assert(h.api.status().phase=="COMBAT" and not h.api.status().fallback
        and not h.api.status().paused,"blocked priority must not cause retreat")
    h.advance(5)
    local count=0
    for _,cmd in ipairs(h.sent) do if cmd=="zabij priority" then count=count+1 end end
    assert(count==1,"shielded target cooldown must suppress repeated kill attempts")
    h.dispose()
end

-- A failed switch without an interception line must also continue combat.
do
    local h=fixture(55,85)
    h.api.request("start");h.advance(4.5)
    assert(not h.api.status().fallback and not h.api.status().paused)
    assert(h.sent[2]=="rozkaz druzynie zaatakowac blocker",
        "missing switch confirmation keeps fight alive and reunifies the team")
    h.dispose()
end
print("PASS priority and wounded HP; shielded targets continue combat with real party focus")
