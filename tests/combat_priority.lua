local new=dofile('tests/support_harness.lua')
local P=dofile('plugins/chimera_autoexp/init.lua')
local h=new()
h.p.vitals={hp=100,fatigue=0}
for _,m in ipairs(h.p.group.members)do m.hp=100 end
h.saved.selected='test'
h.saved.profiles={test={name='Test',route={'rooma'},safeRoom='safe',targets={'yuan-ti','ettin'},avoid={},rules={maxEnemies=3}}}
getRoomIDbyHash=function()return 1 end
getPath=function()return false end
local function mob(id,name)return {id=id,name=name,kind='npc'}end
local e1,e2,y1,y2,g=mob('e1','ettin'),mob('e2','ettin'),mob('y1','yuan-ti'),mob('y2','yuan-ti'),mob('g','goblinka')
h.p.entities.entities={e1,e2,g}
h.p.combat={self_active=1,relations={{attacker='me',defender='e2'}}}
h.api=P.setup(h.ctx);h.api.request('start');h.advance(.1)
assert(#h.sent==0,'keep current equal-priority ettin')
h.p.entities.entities={e1,e2,g,y1}
h.emit('chimera.room.entities',h.p.entities);h.advance(.1)
assert(h.sent[1]=='zabij y1','arrival of higher priority changes active target')
h.emit('chimera.combat.state',h.p.combat);h.advance(.1)
assert(#h.sent==1,'no duplicate pending attack')
h.p.combat.relations={{attacker='me',defender='y1'}}
h.emit('chimera.combat.state',h.p.combat);h.advance(.1)
h.p.entities.entities={e1,g,y2,y1}
h.emit('chimera.room.entities',h.p.entities);h.advance(.1)
assert(#h.sent==1,'retain current yuan-ti despite entity order')
h.p.entities.entities={e1,g,y2}
h.p.combat.relations={{attacker='me',defender='g'}}
h.emit('chimera.room.entities',h.p.entities);h.advance(.1)
assert(h.sent[2]=='zabij y2','after death correct server-selected goblinka')
h.p.combat.relations={{attacker='me',defender='y2'}}
h.emit('chimera.combat.state',h.p.combat);h.advance(.1)
h.p.entities.entities={e1,e2,mob('e3','ettin'),mob('e4','ettin'),mob('e5','ettin'),g}
h.emit('chimera.room.entities',h.p.entities);h.advance(.1)
assert(h.api.status().fallback and not h.api.status().paused,'five targets exceed limit during combat at full HP')
h.dispose()
print('PASS active combat priority, stable ties, arrivals, deaths and limit')
