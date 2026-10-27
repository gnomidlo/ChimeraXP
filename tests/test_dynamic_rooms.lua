-- Dynamic NPC occupancy: no time-based room bans, only skip current encounter.
local P = assert(loadfile('plugins/chimera_autoexp/init.lua'))()
local function scenario(kind)
    local handlers, commands, timers, sent, walker_moves, log = {}, {}, {}, {}, {}, {}
    local clock = 100
    local previous_time = os.time
    os.time = function() return clock end
    local map = {s=1, d=2, a=3, c=4, safe=5}
    getRoomIDbyHash = function(hash) return map[hash] or -1 end
    getRoomHashByID = function(id) for k, v in pairs(map) do if v == id then return k end end end
    getPath = function(a,b)
        if a == map.d and b == map.c then speedWalkPath = {map.s,map.c}; return true end
        if a == map.d and b == map.a then speedWalkPath = {map.s,map.a}; return true end
        if a == map.d and b == map.s then speedWalkPath = {map.s}; return true end
        if a == map.s and b == map.c then speedWalkPath = {map.c}; return true end
        if a ~= b then speedWalkPath={b}; return true end
        return false
    end
    local world = {
        room={id='s',exits={zachod='d',['polnocny-wschod']='a',poludnie='c'}}, current=map.s,
        entities={room='s',entities={{id='me',relation='self',kind='player'}}},
        combat={self_active=0,relations={}},
        group={members={{id='me',self=1,here=1,hp=100,maxhp=100}}},
        vitals={hp=100},
    }
    local function emit(key, val) for _,f in ipairs(handlers[key] or {}) do f(val) end end
    local local_targets = (kind=='wildlife' or kind=='gnollpack' or kind=='avoided') and {'gnoll'} or {'goblin'}
    local local_limit = (kind=='wildlife' or kind=='gnollpack' or kind=='avoided') and 1 or 3
    local ctx={state={},log={info=function(s)log[#log+1]=s end,warn=function(s)log[#log+1]=s end},
        saved=function(_,key,default) return ({profiles={test={name='test',route={'a','s','d','c'},
            targets=local_targets,avoid={'pajak'},safeRoom='safe',
            rules={maxEnemies=local_limit,minRoomRevisit=60,escapeWait=4,syncWait=4,attackWait=3,lootGrace=7,retreatHP=35,returnHP=85}}},selected='test'})[key] or default end,
        save=function() end,
        use=function(_,key)
          return ({
              gmcp={room=function()return world.room end,entities=function()return world.entities end,
                  group=function()return world.group end,combat=function()return world.combat end,
                  vitals=function()return world.vitals end,connected=function()return true end},
              mapper={current_room=function()return world.current end},
              walker={go=function(id)
                walker_moves[#walker_moves+1]=id;emit('chimera.walk.started',{map_room=id});return true
                end,stop=function(msg)emit('chimera.walk.stopped',{reason=msg});return true end},
          })[key]
        end,
        trigger=function() end,
        on=function(_,key,fn)handlers[key]=handlers[key] or {};handlers[key][#handlers[key]+1]=fn end,
        command=function(_,x)commands[x[1]]=x.fn end,
        timer=function(_,delay,fn,repeating)local id=#timers+1;timers[id]={fn=fn,active=true,repeating=repeating};return id end,
        cancel=function(_,id)if timers[id] then timers[id].active=false end end,
        cleanup=function()end,
        send=function(_,s)sent[#sent+1]=s; if (s=='w' or s=='s' or s=='ne') then emit('chimera.step.manual',{direction=s}) end end,
        report=function()end,
    }
    local api=P.setup(ctx)
    local function tick()
        local ready={}
        for i,t in ipairs(timers) do if t.active and not t.repeating then ready[#ready+1]=i end end
        for _,i in ipairs(ready) do local t=timers[i];t.active=false;t.fn() end
    end
    local function place(id,exits,npcs,how)
        world.room={id=id,exits=exits};world.current=map[id]
        world.entities={room=id,entities={{id='me',relation='self',kind='player'}}}
        for _, e in ipairs(npcs or {}) do world.entities.entities[#world.entities.entities+1]=e end
        emit('chimera.room.changed',{id=id,how=how or 'chodzik'})
        emit('chimera.room.entities',world.entities)
        tick()
    end
    local spider={id='spider',name='gigantyczny pajak',kind='npc'}
    local goblin={id='goblin',name='zielony goblin',kind='npc'}
    if kind=='spider' then
        world.entities.entities[#world.entities.entities+1]=spider
    elseif kind=='wildlife' or kind=='gnollpack' or kind=='avoided' then
        world.entities.entities[#world.entities.entities+1]={id='hare1',name='zwinny dlugouchy zajac',kind='npc'}
        world.entities.entities[#world.entities.entities+1]={id='hare2',name='szarawy chudy zajac',kind='npc'}
        world.entities.entities[#world.entities.entities+1]={id='gnoll1',name='silny przebiegly gnoll',kind='npc'}
        if kind=='gnollpack' then
            world.entities.entities[#world.entities.entities+1]={id='gnoll2',name='wsciekly gnoll',kind='npc'}
        elseif kind=='avoided' then
            world.entities.entities[#world.entities.entities+1]=spider
        end
    else
        for i=1,4 do world.entities.entities[#world.entities.entities+1]={id='mob'..i,name='goblin',kind='npc'} end
    end
    commands['exp start']();tick()
    if kind=='wildlife' then
        assert(not api.status().paused and api.status().phase~='AVOID_ESCAPE',
            'two rabbits must not count against /exp limit 1')
        assert(sent[#sent]=='zabij gnoll1',
            'one gnoll with two harmless rabbits should be attacked')
        commands['exp stop']()
        os.time=previous_time
        print('PASS dynamic NPC target limit wildlife')
        return
    elseif kind=='gnollpack' then
        assert(api.status().phase=='AVOID_ESCAPE',
            'two gnolls exceed the configured target limit 1')
        assert(table.concat(log,';'):find('zbyt wiele celow EXP (2/1)',1,true),
            'limit log must count exactly gnolls (not rabbits)')
        assert(sent[#sent]=='w','too many gnolls must escape')
        commands['exp stop']()
        os.time=previous_time
        print('PASS dynamic NPC target limit gnollpack')
        return
    elseif kind=='avoided' then
        assert(api.status().phase=='AVOID_ESCAPE' and sent[#sent]=='w',
            'one avoided spider must trigger escape independently of target limit')
        commands['exp stop']()
        os.time=previous_time
        print('PASS dynamic NPC separately avoided spider')
        return
    end
    assert(not api.status().paused and api.status().phase=='AVOID_ESCAPE',kind..': first hazard should be skipped')
    assert(sent[#sent]=='w','first escape should prefer route neighbour (deep forest)')
    -- The room reached is a dead end. The only route to continue is THROUGH
    -- the previously unsafe room (it must remain valid for the mapper).
    place('d',{wschod='s'}, {})
    assert(not api.status().paused,kind..': dead end must not pause')
    assert(walker_moves[#walker_moves]==map.c,kind..': getPath via skipped room must still work')
    if kind=='spider' then
        world.combat={self_active=1,relations={{attacker='spider',defender='me'}}}
        emit('chimera.walk.stopped',{reason='atak'})
        place('s',{zachod='d',['polnocny-wschod']='a',poludnie='c'},{spider})
        assert(not api.status().paused,'revisiting spider room must still escape')
        assert(sent[#sent]=='s','second visit must choose an alternative exit, not return to dead end: '..tostring(sent[#sent]))
        assert(not table.concat(sent,';'):find('zabij',1,true),'never attack avoided NPC')
    else
        emit('chimera.walk.stopped',{reason='atak'})
        world.combat={self_active=0,relations={}}
        place('s',{zachod='d',['polnocny-wschod']='a',poludnie='c'},{goblin})
        assert(not api.status().paused,'return with fewer NPC must resume without waiting')
        assert(sent[#sent]=='zabij goblin','a room with lower NPC count must immediately be eligible for fighting')
    end
    commands['exp stop']()
    os.time = previous_time
    print('PASS dynamic skip room '..kind)
end
scenario('spider')
scenario('crowded')
scenario('wildlife')
scenario('gnollpack')
scenario('avoided')
