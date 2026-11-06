local new=dofile('tests/support_harness.lua')
local P=dofile('plugins/chimera_autoexp/init.lua')
local function setup()
 local h=new()
 h.p.vitals={hp=100,fatigue=0}
 for _,m in ipairs(h.p.group.members) do m.hp=100 end
 h.p.entities.entities={{id='me',kind='player',relation='self'}}
 h.p.room.exits={polnoc='b'}
 h.saved.selected='test'
 h.saved.profiles={test={name='Test',route={'rooma','b','c'},targets={'goblin','ork','smok'},avoid={'pajak'},safeRoom='safe',rules={maxEnemies=2,minRoomRevisit=0}}}
 local ids={rooma=1,b=2,c=3,safe=4}
 getRoomIDbyHash=function(id)return ids[id]end
 getRoomHashByID=function(id)for k,v in pairs(ids)do if v==id then return k end end end
 getPath=function(a,b)speedWalkPath={b};return true end
 h.api=P.setup(h.ctx)
 function h.place(id,exits,entities)
  h.p.room={id=id,key=id,exits=exits}
  h.p.entities={room=id,entities=entities or {}}
  h.emit('chimera.room.changed',{id=id,how='chodzik'})
  h.emit('chimera.room.entities',h.p.entities)
  h.advance(.1)
 end
 return h
end
local function mob(id,name)return {id=id,name=name,kind='npc'}end
local crowd={mob('a','goblin'),mob('b','goblin'),mob('c','goblin')}
for _,stop in ipairs({false,true}) do
 local h=setup();h.p.entities.entities=crowd
 h.api.request('start');h.advance(.1)
 assert(h.sent[1]=='n','first hazard skipped')
 h.place('b',{polnoc='safe'},crowd)
 assert(h.api.status().fallback and not h.api.status().paused,'second hazard retreats')
 h.advance(.1)
 assert(h.sent[#h.sent]=='n','shelter direction sent')
 h.p.combat={self_active=1,relations={}}
 h.place('safe',{poludnie='c'},{mob('weak','pajak')})
 assert(h.api.status().phase=='COMBAT','weak shelter aggressor keeps tactics available')
 local n=#h.moves;h.advance(10)
 assert(#h.moves==n,'do not flee trusted shelter')
 h.p.combat={self_active=0,relations={}}
 h.p.entities.entities={}
 h.p.vitals.fatigue=90
 h.emit('chimera.room.entities',h.p.entities);h.advance(40)
 assert(h.api.status().fallback,'must recover stamina')
 h.p.vitals.fatigue=0;h.emit('chimera.char.vitals',h.p.vitals);h.advance(1)
 if stop then h.api.request('stop') end
 h.advance(35)
 if stop then assert(not h.api.status().started and #h.moves==n,'STOP cancels restart')
 else assert(not h.api.status().fallback and #h.moves>n,'automatic patrol restart') end
 h.dispose()
end
do
 local h=setup();h.p.entities.entities={mob('g','goblin'),mob('o','ork')}
 h.api.request('start');h.advance(5)
 assert(h.sent[1]=='zabij g' and h.api.status().fallback,'unconfirmed priority attack retreats')
 for _,s in ipairs(h.sent)do assert(s~='zabij o','never skip living priority target')end
 h.dispose()
end
do
 local h=setup();h.p.entities.entities={mob('g','goblin'),mob('o','ork'),mob('weak','szczur')}
 h.p.combat={self_active=1,relations={{attacker='weak',defender='me'}}}
 h.api.request('start');h.advance(1)
 assert(h.api.status().phase=='COMBAT' and not h.api.status().fallback,'unlisted aggressor does not count')
 h.dispose()
end
do
 local h=setup();h.p.room.exits={};h.p.vitals.hp=10
 h.p.combat={self_active=1,relations={}}
 h.api.request('start');h.advance(31)
 assert(not h.api.status().paused and h.api.status().fallback,'blocked retreat stays supervised')
 h.api.request('pauza');local n=#h.sent;h.advance(60)
 assert(#h.sent==n,'manual pause cancels retries and polling')
 h.dispose()
end
print('PASS shelter recovery, retry, STOP, priority failure and unlisted aggressor')

do
 local h=setup();h.p.entities.entities=crowd
 h.api.request('start');h.advance(.1)
 h.place('b',{polnoc='safe'},crowd);h.advance(.1)
 local refreshes=0
 h.gmcp.refresh_entities=function()
  refreshes=refreshes+1
  return true
 end
 h.p.room={id='safe',key='safe',exits={poludnie='c'}}
 h.emit('chimera.room.changed',{id='safe',how='chodzik'})
 h.advance(6)
 assert(refreshes>0 and refreshes<=2,'request missing shelter entities with bounded polling')
 assert(h.api.status().fallback,'do not bypass missing room data')
 h.p.entities={room='safe',entities={}}
 h.emit('chimera.room.entities',h.p.entities)
 h.advance(32)
 assert(not h.api.status().fallback and #h.moves>0,'fresh snapshot releases fully regenerated shelter')
 h.dispose()
end
