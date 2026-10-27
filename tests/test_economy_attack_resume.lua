-- Beta.17: attacked while transporting loot must retain the shop/bank/return goal.
-- Native walker stops on 'atak'; AutoExp uses verified single GMCP exits,
-- then returns to walker after the fight ends, without initiating attacks.
local P=assert(loadfile("plugins/chimera_autoexp/init.lua"))()
local function trial(combat_remains)
    local old_time=os.time
    local now=100
    os.time=function() return now end
    local handlers, commands, triggers, timers, sent, walked, logs={},{},{},{},{},{},{}
    local map={home=1,cross=2,shop=3,bank=4}
    getRoomIDbyHash=function(hash) return map[hash] or -1 end
    getRoomHashByID=function(id)
        for hash, number in pairs(map) do if number==id then return hash end end
    end
    getPath=function(from,to)
        if from==to then return false end
        speedWalkPath={}
        local direction=to>from and 1 or -1
        for id=from+direction,to,direction do speedWalkPath[#speedWalkPath+1]=id end
        return true
    end
    local room_exits={
        home={wschod="cross"},
        cross={zachod="home",wschod="shop"},
        shop={zachod="cross",wschod="bank"},
        bank={zachod="shop"},
    }
    local world={
        room={id="home",exits=room_exits.home},current=1,
        entities={room="home",entities={{id="me",kind="player",relation="self"}}},
        combat={self_active=0,relations={}},vitals={hp=100,encumbrance=80},
        group={members={{id="me",self=1,here=1,hp=100,maxhp=100}}},
    }
    local function emit(name,data)
        for _,cb in ipairs(handlers[name] or {}) do cb(data) end
    end
    expandAlias=function(name)
        sent[#sent+1]="ALIAS:"..name
    end
    local ctx={
        state={},log={info=function(s)logs[#logs+1]=s end,warn=function(s)logs[#logs+1]=s end},
        saved=function(_,key,default)
            if key=="selected" then return "test" end
            if key=="profiles" then return {test={name="test",
                route={"home","cross","shop"},targets={"gnoll"},avoid={},
                loot={"bronie"},safeRoom="home",rules={
                maxEnemies=1,retreatHP=35,returnHP=85,attackWait=3,
                lootGrace=7,minRoomRevisit=60,syncWait=4,escapeWait=4,
                economyCommandDelay=0.7}}} end
            return default
        end,
        save=function() end,
        use=function(_,key)
            return ({
                gmcp={room=function()return world.room end,
                    entities=function()return world.entities end,
                    combat=function()return world.combat end,
                    group=function()return world.group end,
                    vitals=function()return world.vitals end,
                    connected=function()return true end},
                mapper={current_room=function()return world.current end},
                walker={cost=function(a,b)return math.abs(a-b) end,
                    go=function(destination)
                        assert(world.combat.self_active==0,
                            "never restart walker into active combat")
                        walked[#walked+1]=destination
                        emit("chimera.walk.started",{map_room=destination})
                        return true
                    end,
                    stop=function(reason)
                        emit("chimera.walk.stopped",{reason=reason})
                        return true
                    end},
                locations={targets=function(tag)
                    return ({sklep={"shop"},bank={"bank"}})[tag] or {}
                end}
            })[key]
        end,
        on=function(_,key,fn)
            handlers[key]=handlers[key] or {}
            handlers[key][#handlers[key]+1]=fn
        end,
        command=function(_,entry)commands[entry[1]]=entry.fn end,
        trigger=function(_,pattern,fn)triggers[#triggers+1]={pattern=pattern,fn=fn} end,
        timer=function(_,seconds,fn,repeating)
            local id=#timers+1
            timers[id]={fn=fn,when=now+seconds,active=true,repeating=repeating}
            return id
        end,
        cancel=function(_,id) if timers[id] then timers[id].active=false end end,
        cleanup=function() end,
        send=function(_,cmd)
            sent[#sent+1]=cmd
            if cmd=="e" or cmd=="w" then
                emit("chimera.step.manual",{direction=cmd})
            end
        end,
        report=function() end,
    }
    local api=P.setup(ctx)
    local function advance(seconds)
        now=now+seconds
        for tries=1,60 do
            local due={}
            for id,t in ipairs(timers) do
                if t.active and not t.repeating and t.when<=now then
                    due[#due+1]=id
                end
            end
            if #due==0 then return end
            for _,id in ipairs(due) do
                local t=timers[id]
                t.active=false
                t.fn()
            end
        end
        error("timer loop")
    end
    local function place(where, how, native_arrival)
        world.current=map[where]
        world.room={id=where,exits=room_exits[where]}
        world.entities={room=where,entities={{id="me",kind="player",relation="self"}}}
        emit("chimera.room.changed",{id=where,how=how})
        emit("chimera.room.entities",world.entities)
        if native_arrival then
            emit("chimera.walk.arrived",{map_room=map[where],target=where})
        end
        advance(0)
    end
    commands["exp zarobek kurs"]()
    advance(0)
    assert(walked[1]==map.shop,"course starts toward shop")
    emit("chimera.walk.stopped",{reason="atak"})
    -- Simulate walker stop event preceding GMCP Combat update.
    advance(0)
    assert(sent[1]=="e","after walker attack stop, send a verified east step")
    assert(not api.status().paused,"attack must not pause the merchant course")
    if combat_remains then
        world.combat={self_active=1,relations={{attacker="gnoll",defender="me"}}}
    end
    place("cross","reczny",false)
    assert(not api.status().paused,"owned step must not be mistaken for manual input")
    if combat_remains then
        assert(sent[2]=="e","keep stepping from cross while combat remains active")
        assert(#walked==1,"walker must remain off during active combat")
        world.combat={self_active=0,relations={}}
        place("shop","reczny",false)
        assert(not api.status().paused,"arrival during a fight must be accepted")
    else
        emit("chimera.combat.state",world.combat)
        advance(0)
        assert(walked[#walked]==map.shop,
            "restart native walker from confirmed cross location after combat")
        place("shop","chodzik",true)
    end
    local offset=combat_remains and 2 or 1
    assert(sent[offset]=="sprzedaj bronie","shop sales continue after attack; sent="..table.concat(sent,",").."; logs="..table.concat(logs,";").."; phase="..api.status().phase)
    advance(0.71)
    assert(sent[offset+1]=="sprzedaj zbroje","armor sale is not cancelled")
    advance(0.71)
    assert(walked[#walked]==map.bank,"continue to bank after combat")
    place("bank","chodzik",true)
    assert(sent[offset+2]=="ALIAS:wem","deposit completes")
    advance(0.71)
    assert(sent[offset+3]=="zdenominuj","denomination completes")
    for _,entry in ipairs(triggers) do
        if entry.pattern:find("zostaly zdenominowane",1,true) then entry.fn() end
    end
    assert(sent[offset+4]=="ALIAS:wlm","withdraw after acknowledged denom")
    advance(0.71)
    assert(walked[#walked]==map.home,"return to original EXP room")
    place("home","chodzik",true)
    assert(api.status().phase=="OFF","one-shot merchant trip completed")
    assert(not table.concat(sent,";"):find("zabij",1,true),
        "commerce must never start incidental fighting")
    commands["exp stop"]()
    os.time=old_time
    print("PASS economy attack transit",combat_remains and "during-combat" or "delayed-GMCP")
end
trial(false)
trial(true)
