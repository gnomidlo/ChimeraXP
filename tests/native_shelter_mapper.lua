-- Regression: mapped shelter, native walker settings and missing GMCP exits outside EXP.
local new = dofile("tests/support_harness.lua")
local plugin = dofile("plugins/chimera_autoexp/init.lua")
local ids = {danger=1, safe=7, shop=9}
getRoomIDbyHash = function(hash) return ids[hash] end
getRoomHashByID = function(id)
    for hash, number in pairs(ids) do if number == id then return hash end end
end
getPath = function(from, destination)
    speedWalkPath={destination}
    return from ~= destination
end

local function fixture()
    local h = new()
    h.p.room={id="safe",key="safe",exits={poludnie="danger"}}
    h.p.entities={room="safe",entities={}}
    h.saved.selected="test"
    h.saved.profiles={test={name="test",route={"danger"},targets={"goblin"},
        safeRoom="safe",safeKey="safe",rules={retreatHP=40,returnHP=85}}}
    local original=h.ctx.use
    h.ctx.use=function(ctx,name)
        if name=="mapper" then
            return {current_room=function() return ids[h.p.room.id] end}
        end
        return original(ctx,name)
    end
    h.settings["walker.opoznienie"]=1.4
    h.settings["walker.przy_ataku"]="zatrzymaj"
    h.ctx.app.config.set=function(_,name,key,value)
        h.settings[name.."."..key]=value
        return true
    end
    h.api=plugin.setup(h.ctx)
    return h
end

local h=fixture()
h.commands["exp bezpieczna"]()
assert(h.saved.profiles.test.safeMap==7, "save mapper room with GMCP hash")
h.p.room={id="danger",key="danger",exits={polnoc="safe"}}
h.p.entities={room="danger",entities={}}
h.p.combat={room="danger",self_active=1,primary="goblin",relations={}}
h.p.vitals.hp=20
h.api.request("start")
h.advance(.1)
assert(h.moves[1]==7, "full retreat to mapped shelter should use native walker.go (same as /idz 7)")
assert(#h.sent==0, "native emergency walk should not guess raw GMCP exit")
assert(h.settings["walker.opoznienie"]==0.6, "set safe movement cadence")
assert(h.settings["walker.przy_ataku"]=="ignoruj", "walker must not stop on attack")
assert(h.saved.walker_restore and h.saved.walker_restore.delay==1.4, "persist settings for crash restore")
h.p.room={id="safe",key="safe",exits={poludnie="danger"}}
h.p.entities={room="safe",entities={}}
h.p.combat={room="safe",self_active=0,relations={}}
h.emit("chimera.room.changed",{id="safe",how="chodzik"})
h.emit("chimera.walk.arrived",{target="safe",map_room=7})
assert(h.settings["walker.opoznienie"]==1.4, "restore original cadence after arrival")
assert(h.settings["walker.przy_ataku"]=="zatrzymaj", "restore original attack policy")
assert(h.saved.walker_restore==nil, "remove crash recovery checkpoint")
h.api.request("stop")
h.dispose()

-- The same GMCP room suddenly losing exits while patrolling is a safety alert.
local e=fixture()
e.p.room={id="danger",key="danger",exits={polnoc="safe",wschod="shop"}}
e.p.entities={room="danger",entities={}}
e.p.combat={room="danger",self_active=0,relations={}}
e.p.vitals.hp=95
e.emit("chimera.room.info",e.p.room)
e.api.request("start")
e.p.room={id="danger",key="danger",exits={}}
e.emit("chimera.room.info",e.p.room)
assert(e.api.status().fallback~=nil, "exits disappearing in an EXP room must cause dark retreat")
e.api.request("stop")
e.dispose()

-- A different room with empty exits en route to the shop is NOT proof of darkness.
local s=fixture()
s.p.room={id="danger",key="danger",exits={wschod="shop"}}
s.p.entities={room="danger",entities={}}
s.p.combat={room="danger",self_active=0,relations={}}
s.p.vitals.hp=95
s.emit("chimera.room.info",s.p.room)
s.api.request("start")
s.p.room={id="shop",key="shop",exits={}}
s.emit("chimera.room.info",s.p.room)
assert(s.api.status().fallback==nil, "empty exits outside EXP may be legitimate")
s.api.request("stop")
s.dispose()
print("PASS mapped shelter, native retreat, darkness scoped to EXP")
