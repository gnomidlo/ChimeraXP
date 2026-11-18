-- Native emergency walk must survive repeated attack stops, one mapper room per call.
local new = dofile("tests/support_harness.lua")
local plugin = dofile("plugins/chimera_autoexp/init.lua")
local ids = {entry=1, junction=2, passage=3, safe=10358}
getRoomIDbyHash=function(hash) return ids[hash] end
getRoomHashByID=function(number)
    for hash,id in pairs(ids) do if id==number then return hash end end
end
getPath=function(from,to)
    if to==10358 then
        local hops={[1]={2,3,10358},[2]={3,10358},[3]={10358}}
        speedWalkPath=hops[from] or {}
        return #speedWalkPath>0
    end
    speedWalkPath={to}
    return from~=to
end

local function fixture()
    local h=new()
    h.p.room={id="entry",key="entry",exits={wschod="junction"}}
    h.p.entities={room="entry",entities={}}
    h.p.combat={room="entry",self_active=1,primary="goblin",relations={}}
    h.p.vitals.hp=20
    h.saved.selected="test"
    h.saved.profiles={test={name="test",route={"entry","junction","passage"},
        targets={"goblin"},safeRoom="safe",safeMap=10358,safeKey="safe",
        rules={retreatHP=40,returnHP=85}}}
    local old=h.ctx.use
    h.ctx.use=function(ctx,name)
        if name=="mapper" then return {current_room=function()return ids[h.p.room.id] end} end
        return old(ctx,name)
    end
    h.settings["walker.opoznienie"]=1.25
    h.settings["walker.przy_ataku"]="zatrzymaj"
    h.ctx.app.config.set=function(_,name,key,value)
        h.settings[name.."."..key]=value
        return true
    end
    h.api=plugin.setup(h.ctx)
    function h.place(hash)
        local exits= hash=="entry" and {wschod="junction"}
            or hash=="junction" and {zachod="entry",wschod="passage"}
            or hash=="passage" and {zachod="junction",wschod="safe"}
            or {zachod="passage"}
        h.p.room={id=hash,key=hash,exits=exits}
        h.p.combat={room=hash,self_active=hash=="safe" and 0 or 1,
            primary=hash=="safe" and "" or "goblin",relations={}}
        h.p.entities={room=hash,entities={}}
        h.emit("chimera.room.info",h.p.room)
        h.emit("chimera.room.changed",{id=hash,how="reczny"})
        h.emit("chimera.room.entities",h.p.entities)
    end
    return h
end

-- Attacked immediately after dispatching movement: wait for the lagging room
-- packet, then continue from THAT room and do not treat the echo as manual.
do
    local h=fixture()
    h.api.request("start");h.advance(.1)
    assert(h.moves[1]==2 and #h.moves==1, "first hop uses mapper room 2, not full target")
    assert(h.settings["walker.przy_ataku"]=="ignoruj")
    h.emit("sysDataSendRequest",nil,"e")
    h.emit("chimera.walk.stopped",{reason="atak"})
    h.advance(.6)
    assert(#h.moves==1 and not h.api.status().paused,"no second step before GMCP confirms the first")
    h.place("junction")
    h.advance(.7)
    assert(h.moves[2]==3 and not h.api.status().paused,
        "next mapped hop after late arrival: #moves="..#h.moves..
        " phase="..tostring(h.api.status().phase)..
        " reason="..tostring(h.api.status().reason)..
        " log="..table.concat(h.messages," | "))
    -- Attack stop emitted AFTER room changed, without an arrived event.
    h.place("passage")
    h.emit("chimera.walk.stopped",{reason="atak"})
    h.advance(.7)
    assert(h.moves[3]==10358 and not h.api.status().paused,"restart despite continuing combat")
    h.place("safe")
    h.emit("chimera.walk.arrived",{target="safe",map_room=10358})
    assert(h.settings["walker.przy_ataku"]=="zatrzymaj", "restore attack mode at shelter")
    assert(h.settings["walker.opoznienie"]==1.25,"restore original cadence at shelter")
    assert(h.saved.walker_restore==nil,"clear emergency settings checkpoint")
    assert(#h.moves==3,"never return to an already completed waypoint")
    h.dispose()
end

-- A burst of combat stops without physical progress must not loop forever.
do
    local h=fixture()
    h.api.request("start");h.advance(.1)
    for n=1,4 do
        if h.api.status().paused then break end
        h.emit("chimera.walk.stopped",{reason="atak"})
        h.advance(.8)
    end
    assert(h.api.status().paused, "bounded combat stop retries in same location")
    assert(#h.moves<=4, "no unbounded walker restart")
    assert(h.settings["walker.przy_ataku"]=="zatrzymaj","restore options on safety pause")
    h.dispose()
end

-- A user cancellation / other walker error is NOT an automatic combat retry.
for _,reason in ipairs({"nie udalo sie przejsc","zejscie z trasy"}) do
    local h=fixture()
    h.api.request("start");h.advance(.1)
    h.emit("chimera.walk.stopped",{reason=reason})
    h.advance(10)
    assert(h.api.status().paused and #h.moves==1,
        "non-attack interruption must stop dangerous automatic walking")
    assert(h.settings["walker.przy_ataku"]=="zatrzymaj")
    h.dispose()
end
print("PASS one-hop mapped emergency retreat with attack reissue, late GMCP, limits and restore")
