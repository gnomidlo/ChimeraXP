-- Simulated one-floor Kregi Shoona; real Mudlet/Qt testing remains necessary.
local root=os.getenv("CHIMERAXP_TOWER_ROOT") or "."
local Tower=assert(loadfile(root.."/src/chimeraxp/tower.lua"))()
local Loot=assert(loadfile(root.."/src/chimeraxp/tower_loot.lua"))()
local clock,real_time=1000,os.time
os.time=function() return clock end

local function scenario(opts)
    opts=opts or {}
    local rooms={
        A={id="aaaa000000000001",name="Platforma mozaiki nad pustka, poziom 2",exits={poludnie="aaaa000000000002"}},
        B={id="aaaa000000000002",name="Most",exits={polnoc="aaaa000000000001",poludnie="aaaa000000000004",wschod="aaaa000000000003"}},
        C={id="aaaa000000000003",name="Boss",exits={zachod="aaaa000000000002"}},
        D={id="aaaa000000000004",name="Bestia",exits={polnoc="aaaa000000000002"}},
    }
    local ids,lookup={},{}
    for i,key in ipairs({"A","B","C","D"}) do ids[rooms[key].id]=i;lookup[i]=key end
    local position="A"
    local alive=true
    local mobs={D={{id="enemy:91",kind="npc",relation="hostile",hp=920,maxhp=1060}}}
    local group={leader="player:1",members={{id="player:1",self=1,here=1,hp=100,maxhp=100},
        {id="minion:1",self=0,here=1,hp=100,maxhp=100}}}
    local entities,combat,vitals={},nil,{hp=100,fatigue=10}
    local timers,seq,commands,handlers,triggers,report,logs={},{},{},{},{},{},{warn={},info={}}
    seq=0
    local ctx={log={info=function(s) logs.info[#logs.info+1]=s end,warn=function(s) logs.warn[#logs.warn+1]=s end}}
    local function r()
        local v=rooms[position];return {id=v.id,name=v.name,area="Kregi Shoona, poziom 2 #421852174",
            area_id="8e8d3415f86872c6",exits=v.exits}
    end
    local api={room=r,entities=function() return entities end,combat=function() return combat end,
        group=function() return group end,vitals=function() return vitals end,connected=function() return true end}
    local map={current_room=function() return ids[r().id] end}
    local emit
    local function arrive(key,kind)
        position=key
        entities={room=r().id,entities=key=="D" and alive and mobs.D or {}}
        combat={room=r().id,relations={}}
        if opts.low_hp_on_d and key=="D" then vitals.hp=25 end
        if opts.low_hp_on_d and key=="A" then vitals.hp=100 end
        emit("chimera.room.changed",{id=r().id,how=kind or "reczny"})
        emit("chimera.room.entities",entities)
        emit("chimera.combat.state",combat)
        emit("chimera.char.vitals",vitals)
    end
    local function text_line(prefix)
        for _,item in ipairs(triggers) do
            if item.pat:find(prefix,1,true) then item.fn();return true end
        end
        error("No registered trigger for "..prefix)
    end
    ctx.use=function(_,name)
        return ({gmcp=api,mapper=map,walker=ctx.walker})[name]
    end
    ctx.saved=function(_,name,default) return opts.saved or default end
    ctx.save=function(_,name,data) opts.saved=data end
    ctx.command=function(_,def) commands[def[1]]=def.fn end
    ctx.on=function(_,event,fn) handlers[event]=handlers[event] or {};table.insert(handlers[event],fn) end
    ctx.trigger=function(_,pattern,fn) triggers[#triggers+1]={pat=pattern,fn=fn} end
    ctx.cleanup=function(_,fn) end
    ctx.report=function(_,title,rows) report[title]=rows end
    ctx.timer=function(_,delay,fn) seq=seq+1;timers[seq]={due=clock+delay,fn=fn};return seq end
    ctx.cancel=function(_,id) timers[id]=nil end
    emit=function(event,payload)
        for _,fn in ipairs(handlers[event] or {}) do fn(payload) end
    end
    ctx.walker={
        go=function(target)
            local key=lookup[target]
            if not key then return nil,"Brak mapy" end
            emit("chimera.walk.started")
            arrive(key,"chodzik")
            emit("chimera.walk.arrived",{target=r().id,map_room=target})
            return true
        end,
        stop=function(reason) emit("chimera.walk.stopped",{reason=reason}) end
    }
    ctx.send=function(_,cmd)
        report.sent=report.sent or {}
        report.sent[#report.sent+1]=cmd
        if cmd=="ob mozaike" then
            if position=="A" then text_line("Mozaika tli sie")
            elseif position=="C" then
                local active=not opts.force_inactive and not alive
                text_line(active and "Krag mozaiki jarzy" or "Krag mozaiki jest martwy")
            else text_line("Nie zauwazasz niczego takiego") end
        elseif cmd=="policz ciala" then
            if opts.two_corpses then text_line("dwoch sztuk")
            else text_line("Nie doliczyl") end
        elseif cmd=="n" or cmd=="s" or cmd=="e" or cmd=="w" then
            local dirs={n="polnoc",s="poludnie",e="wschod",w="zachod"}
            local next_id=rooms[position].exits[dirs[cmd]]
            assert(next_id,"Bad step from "..position..": "..cmd)
            local key
            for k,node in pairs(rooms) do if node.id==next_id then key=k end end
            arrive(key,"reczny")
        elseif cmd:match("^zabij ") then
            assert(position=="D")
            combat={room=r().id,relations={{attacker="player:1",defender="enemy:91"}}}
            emit("chimera.combat.state",combat)
            -- Kill is not immediate: send the combat completion on next tick.
            ctx:timer(0.5,function()
                alive=false
                entities={room=r().id,entities={}}
                combat={room=r().id,relations={}}
                emit("chimera.room.entities",entities)
                emit("chimera.combat.state",combat)
            end)
        end
    end
    _G.getRoomIDbyHash=function(hash) return ids[hash] end
    _G.getRoomHashByID=function(number) return rooms[lookup[number]].id end
    _G.getPath=function(from,to)
        _G.speedWalkPath={to}
        return true
    end
    _G.highlightRoom=function() end
    _G.unHighlightRoom=function() end
    local tower=Tower.new(ctx,function() return {started=false} end,
        {check=function() if opts.conflict then return "Oficjalne zbieranie wlaczone" end end},function() end,Loot)
    arrive("A")
    local function advance(by)
        local ending=clock+(by or 0)
        local loops=0
        while true do
            local best,best_id
            for id,t in pairs(timers) do
                if t.due<=ending and (not best or t.due<best.due or (t.due==best.due and id<best_id)) then
                    best,best_id=t,id
                end
            end
            if not best then break end
            timers[best_id]=nil;clock=best.due
            best.fn();loops=loops+1
            assert(loops<5000,"Timer loop")
        end
        clock=ending
    end
    return {tower=tower,run=advance,logs=logs,opts=opts,call=function(name,arg) assert(commands[name],name)(arg) end,
        sent=function() return report.sent or {} end, report=report,position=function() return position end,
        move=function(key) arrive(key) end, alive=function() return alive end}
end

local function contains(values,needle)
    for _,v in ipairs(values) do if v:find(needle,1,true) then return true end end
    return false
end

-- Full floor: entrance -> fight -> gather -> mosaic. No auto ascent, ever.
local m=scenario()
assert(m.tower.start())
m.run(40)
local st=m.tower.status()
assert(st.phase=="COMPLETE",st.phase..": "..tostring(st.reason))
assert(m.position()=="C","Must stop in exit mosaic room")
assert(st.level==2 and st.done and st.rooms==4 and st.cleared==4)
assert(contains(m.sent(),"zabij enemy:91"),"Must attack hostile NPC")
assert(contains(m.sent(),"rozkaz druzynie zaatakowac enemy:91"),"Must focus party")
assert(contains(m.sent(),"wez zlote monety"),"Must loot ground")
assert(contains(m.sent(),"wloz monety do plecaka"),"Must pack coins")
assert(contains(m.sent(),"napelnij plecak"),"Must pack loot")
assert(not contains(m.sent(),"stan na mozaice"),"Never ascend")
print("Tower one-floor exploration: PASS")

local bodies=scenario({two_corpses=true})
assert(bodies.tower.start())
bodies.run(80)
assert(bodies.tower.status().phase=="COMPLETE",bodies.tower.status().phase)
assert(contains(bodies.sent(),"wez mithrylowe monety z 1. ciala"))
assert(contains(bodies.sent(),"wez kamienie z 2. ciala"))
print("Ordinal corpse collection: PASS")

-- An inactive mosaic after exploring every room is not success.
local inactive=scenario({force_inactive=true})
assert(inactive.tower.start())
inactive.run(40)
assert(inactive.tower.status().phase=="PAUSED", inactive.tower.status().phase.." :: "..tostring(inactive.tower.status().reason))
assert(not contains(inactive.sent(),"stan na mozaice"))
print("Inactive mosaic stops: PASS")

-- User movement outside the robot's owned walk pauses, never guesses.
local manual=scenario()
assert(manual.tower.start())
manual.move("B")
assert(manual.tower.status().paused)
print("Manual movement pauses: PASS")

-- Low HP forces a confirmed retreat, not suicidal engagement.
local retreat=scenario({low_hp_on_d=true})
assert(retreat.tower.start())
retreat.run(12)
assert(not contains(retreat.sent(),"zabij enemy:91"),"No attack below retreat threshold")
print("Health safety/retreat: PASS")

-- Conflict with official auto-collect blocks start before any commands.
local conflict=scenario({conflict=true})
assert(conflict.tower.start()==false)
assert(#conflict.sent()==0)
print("Conflicting automations blocked: PASS")

os.time=real_time