-- Tests GMCP-only paths, breadcrumb fallback, free-exit escape and fail-closed.
local plugin = assert(loadfile('plugins/chimera_autoexp/init.lua'))()
local function trial(which)
  local prevtime=os.time
  local clock=100
  os.time=function()return clock end
  local world={room={id='entry',exits={polnoc='middle'}}, current=1,
    entities={room='entry',entities={{id='me',self=true,kind='player',relation='self'},
      {id='mob',kind='npc',name='goblin'}}},
    combat={self_active=1,relations={{attacker='mob',defender='me'}}},
    group={members={{id='me',self=true,here=true,hp=20,maxhp=100}}},vitals={hp=20}}
  local storage={profiles={test={name='Test',route={'entry','middle','safe'},targets={'goblin'},
    avoid={'pajak'},safeRoom='safe',rules={retreatHP=60,returnHP=90,maxEnemies=3}}},selected='test'}
  local commands,handlers,timers,sent,logs={}, {}, {}, {}, {}
  local function emit(event,data)
    for _,cb in ipairs(handlers[event] or {}) do cb(data) end
  end
  local map_lookup={entry=1,middle=2,safe=3,first=4,other=5}
  getRoomIDbyHash=function(id) return (which=='unmapped_safe' and id=='safe') and -1 or map_lookup[id] or -1 end
  getRoomHashByID=function(id) for k,v in pairs(map_lookup) do if id==v then return k end end end
  getPath=function(from,dest) speedWalkPath={} return false end
  local gmcp={room=function()return world.room end,entities=function()return world.entities end,
    vitals=function()return world.vitals end,combat=function()return world.combat end,
    group=function()return world.group end,connected=function()return true end}
  local ctx={state={},log={warn=function(s)logs[#logs+1]=s end,info=function(s)logs[#logs+1]=s end},
    saved=function(_,key,def)return storage[key] or def end,
    save=function(_,key,value)storage[key]=value end,
    use=function(_,key) return ({gmcp=gmcp,mapper={current_room=function() return world.current end},
      walker={go=function()error('should not walker.go') end,stop=function()return true end}})[key] end,
    command=function(_,conf)commands[conf[1]]=conf.fn end,
    on=function(_,event,cb)handlers[event]=handlers[event] or {};table.insert(handlers[event],cb) end,
    timer=function(_,delay,cb,repeating)local idx=#timers+1;timers[idx]={fn=cb,active=true,repeating=repeating};return idx end,
    cancel=function(_,idx)if timers[idx] then timers[idx].active=false end end,
    send=function(_,command) sent[#sent+1]=command; emit('chimera.step.manual',{direction=command}) end,
    cleanup=function()end,
    report=function()end}
  local api=plugin.setup(ctx)
  local function tick()
    local current={}
    for i,t in ipairs(timers) do if t.active and not t.repeating then current[#current+1]=i end end
    for _,i in ipairs(current) do local t=timers[i];t.active=false;t.fn() end
  end
  local function move(room,exits)
    world.room={id=room,exits=exits};world.current=map_lookup[room] or -1
    world.entities={room=room,entities={{id='me',self=true,kind='player',relation='self'}}}
    emit('chimera.room.changed',{id=room,exits=exits,how='reczny'})
    emit('chimera.room.entities',world.entities)
    tick()
  end
  if which=='known_graph' or which=='unmapped_safe' or which=='unexpected_location' then
    -- Pre-record the route: the player had once visited safe, then returned.
    emit('chimera.room.info',{id='middle',exits={polnoc='safe',poludnie='entry'}})
    emit('chimera.room.info',{id='safe',exits={poludnie='middle'}})
  elseif which=='breadcrumb' then
    -- Start at middle, previously visited entry (no GMCP link to safe).
    emit('chimera.room.info',{id='entry',exits={polnoc='middle'}})
    world.room={id='middle',exits={poludnie='entry'}};world.current=2
    world.entities.room='middle'
    emit('chimera.room.changed',{id='middle',exits={poludnie='entry'}})
  elseif which=='random_exit' then
    world.room={id='entry',exits={wschod='other'}}
  elseif which=='no_exits' then
    world.room={id='entry',exits={}}
  end
  commands['exp start']();tick()
  local status=api.status()
  if which=='known_graph' or which=='unmapped_safe' then
    assert(not status.paused and sent[1]=='n',which..' must route to middle without mapper; got '..tostring(sent[1])..' '..table.concat(logs,';'))
    if which=='unexpected_location' then
      move('other',{polnoc='safe',poludnie='entry'})
    else
      move('middle',{polnoc='safe',poludnie='entry'})
    end
    assert(not api.status().paused and sent[2]=='n',which..' must continue to safe')
    move('safe',{poludnie='middle'})
    assert(api.status().phase=='RECOVERY', which..' must arrive safe')
  elseif which=='breadcrumb' then
    assert(not status.paused and sent[1]=='s',which..' must backtrack to entry')
    move('entry',{polnoc='middle'})
    assert(not api.status().paused,'not pause immediately on reaching previous room')
  elseif which=='random_exit' then
    assert(not status.paused and sent[1]=='e','fallback must take actual exit even if safeRoom not mapped')
  elseif which=='no_exits' then
    assert(status.paused and #sent==0, 'no exits must alarm, cannot invent one')
  end
  os.time=prevtime
  print('PASS emergency fallback: '..which)
end
for _,what in ipairs({'known_graph','unmapped_safe','unexpected_location','breadcrumb','random_exit','no_exits'}) do trial(what) end
