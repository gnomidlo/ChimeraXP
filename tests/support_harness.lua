-- Pure deterministic Mudlet/GMCP fixture; no networking or game commands.
local function new()
    local h={time=0,sent={},timers={},events={},commands={},triggers={},cleanups={},saved={},settings={},messages={},moves={}}
    h.p={room={id="rooma",key="rooma#1",exits={n="safe"}},char={id="me"},vitals={hp=80},connected=true,
        group={leader="me",members={}},entities={room="rooma",entities={}},combat={room="rooma",relations={}}}
    for _,id in ipairs({"me","tank","friend","petone","pettwo"}) do
        local npc=id:match("^pet")~=nil;local hp=id=="me" and 80 or 90
        h.p.group.members[#h.p.group.members+1]={id=id,name=id,hp=hp,maxhp=100,here=1,self=id=="me" and 1 or 0}
        h.p.entities.entities[#h.p.entities.entities+1]={id=id,name=id,hp=hp,maxhp=100,kind=npc and "npc" or "player",relation=id=="me" and "self" or npc and "ally" or "group",states={}}
    end
    for i=1,4 do h.p.entities.entities[#h.p.entities.entities+1]={id="enemy"..i,name="Goblin",kind="npc",relation="hostile",hp=100,maxhp=100} end
    h.gmcp={connected=function() return h.p.connected end}
    for _,field in ipairs({"room","char","vitals","group","entities","combat"}) do local key=field;h.gmcp[key]=function() return h.p[key] end end
    getEpoch=function() return h.time end
    os.time=function() return math.floor(h.time) end
    local function log(v) h.messages[#h.messages+1]=v end
    h.ctx={state={},log={info=log,warn=log,error=log},
        app={loader={records={}},config={get=function(_,m,k) return h.settings[m.."."..k] end}},
        use=function(_,name)
            return ({gmcp=h.gmcp,mapper={current_room=function() return 1 end},
                walker={cost=function() return 1 end,go=function(id) h.moves[#h.moves+1]=id;return true end,stop=function() return true end},
                locations={targets=function() return {"safe"} end}})[name]
        end,
        saved=function(_,key,default) local v=h.saved[key];if v==nil then return default end;return v end,
        save=function(_,key,value) h.saved[key]=value end,
        on=function(_,event,fn) h.events[event]=h.events[event] or {};table.insert(h.events[event],fn) end,
        command=function(_,spec) assert(not h.commands[spec[1]],"duplicate command "..spec[1]);h.commands[spec[1]]=spec.fn end,
        trigger=function(_,pattern,fn) h.triggers[pattern]=fn end,
        trigger_exact=function(_,text,fn) h.triggers[text]=fn end,
        timer=function(_,delay,fn,repeating)
            local t={at=h.time+delay,delay=delay,fn=fn,repeating=repeating,active=true};h.timers[#h.timers+1]=t;return t
        end,
        cancel=function(_,timer) if timer then timer.active=false end end,
        cleanup=function(_,fn) h.cleanups[#h.cleanups+1]=fn end,
        send=function(_,command) h.sent[#h.sent+1]=command end,
        report=function() end,
    }
    function h.emit(event,...)
        local list={};for _,fn in ipairs(h.events[event] or {}) do list[#list+1]=fn end
        for _,fn in ipairs(list) do fn(...) end
    end
    function h.fresh() for _,event in ipairs({"chimera.room.entities","chimera.group.state","chimera.combat.state"}) do h.emit(event) end end
    function h.advance(seconds)
        local target=h.time+seconds
        for _=1,10000 do
            local next_timer
            for _,timer in ipairs(h.timers) do if timer.active and timer.at<=target and (not next_timer or timer.at<next_timer.at) then next_timer=timer end end
            if not next_timer then h.time=target;return end
            h.time=next_timer.at
            if next_timer.repeating then next_timer.at=h.time+next_timer.delay else next_timer.active=false end
            next_timer.fn()
        end
        error("timer loop")
    end
    function h.dispose() for i=#h.cleanups,1,-1 do h.cleanups[i]() end;for _,t in ipairs(h.timers) do t.active=false end end
    return h
end
return new
