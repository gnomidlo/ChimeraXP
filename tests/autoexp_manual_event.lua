local source = 'plugins/chimera_autoexp/init.lua'
local P = dofile(source)
local function trial(hazard, delayed, same_direction)
    local sent, handlers, timers, messages, moves = {}, {}, {}, {}, {}
    local clock = 0
    os.time = function() return clock end
    local world = {
        room = {id='r1',exits={polnoc='safe'}}, current=1,
        entities={room='r1',entities={{id='p',kind='player',relation='self'},{id='spider',kind='npc',name='ogromny pajak'}}},
        combat={self_active=1,relations={{attacker='spider',defender='p'}}},
        group={members={{id='p',self=1,here=1,hp=100,maxhp=100}}},
        vitals={hp=hazard and 80 or 18},
    }
    local function emit(event,data)
       for _,fn in ipairs(handlers[event] or {}) do fn(data) end
    end
    getRoomIDbyHash=function(id) return ({r1=1,safe=2})[id] or -1 end
    getRoomHashByID=function(id) return ({[1]='r1',[2]='safe'})[id] end
    getPath=function(a,b) if a==1 and b==2 then speedWalkPath={2};return true end;return false end
    local state={profiles={alpha={name='alpha',route={'r1','safe'},targets={'goblin'},avoid={'pajak'},safeRoom='safe',rules={
    retreatHP=35,returnHP=85,maxEnemies=3, minRoomRevisit=60,attackWait=3,syncWait=4,recoveryPoll=3,lootGrace=7,
    avoidRoomCooldown=600,escapeWait=4,escapeMaxTries=3,safeMoveWait=3,safeMoveTries=2
    }}},selected='alpha'}
    local commands={}
    local ctx={state={}, log={info=function(msg) messages[#messages+1]=msg end,warn=function(msg) messages[#messages+1]='WARN:'..msg end},
      saved=function(_,key,default) return state[key] or default end,save=function(_,key,value) state[key]=value end,
      use=function(_,key)
        local gmcp={room=function() return world.room end,entities=function() return world.entities end,
        combat=function() return world.combat end, vitals=function() return world.vitals end,
        group=function() return world.group end,connected=function() return true end}
        return ({gmcp=gmcp,mapper={current_room=function() return world.current end},
        walker={go=function(dest) moves[#moves+1]=dest;return true end,stop=function()return true end}})[key]
      end,
      trigger=function() end,
      on=function(_,event,fn) handlers[event]=handlers[event] or {};handlers[event][#handlers[event]+1]=fn end,
      command=function(_,opts) commands[opts[1]]=opts.fn end,
      timer=function(_,delay,fn,repeating) local id=#timers+1;timers[id]={fn=fn,active=true,repeating=repeating};return id end,
      cancel=function(_,id) timers[id].active=false end,
      cleanup=function() end,
      send=function(_,text)
        -- official numpad.lua fires this synchronously in sysDataSendRequest
        if not delayed and (text=='n' or text=='s') then
            emit('chimera.step.manual',{direction=text,before={}})
        end
        sent[#sent+1]=text
      end,
      report=function() end}
    local api=P.setup(ctx)
    local function tick()
      local current={}
      for i,t in ipairs(timers) do if t.active and not t.repeating then current[#current+1]=i end end
      for _,i in ipairs(current) do timers[i].active=false;timers[i].fn() end
    end
    assert(commands['exp start'],'start missing')
    commands['exp start']();tick()
    assert(sent[1]=='n','expected direct step n, got '..tostring(sent[1]))
    assert(not api.status().paused, 'BUG: internal n should not pause XP: '..table.concat(messages,' / '))
    assert(#moves==0,'no walker during combat')
    if delayed then
        clock = clock + 1 -- event delivered one second after ctx:send
        emit('chimera.step.manual',{direction='n',before={}})
        assert(not api.status().paused, 'BUG: deferred internal n should not pause XP: '..table.concat(messages,' / '))
    end
    emit('chimera.step.manual',{direction=same_direction and 'n' or 's',before={}})
    assert(api.status().paused,'true manual movement must pause')
    assert(api.status().phase=='PAUSED','manual pause phase')
    commands['exp start']()
    assert(messages[#messages]:find('WSTRZYMANY',1,true),'/exp start should explain how to resume')
    return hazard and 'avoided NPC' or 'emergency HP'
end
trial(false, false, false)
trial(true, false, true)
trial(false, true, false)
trial(true, true, true)
print('PASS: synchronous and deferred own-step manual events; second manual still stops')
