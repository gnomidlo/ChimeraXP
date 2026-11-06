local new=dofile('tests/support_harness.lua')
local P=dofile('plugins/chimera_autoexp/init.lua')
local TIRED=[[^Jestes tak zmeczon[ay], ze nie mozesz isc w tym kierunku\.$]]
local function fixture(avoid,empty)
    local h=new()
    h.polls=0
    local send=h.ctx.send
    h.ctx.send=function(ctx,cmd,...)
        if cmd=='stan' then h.polls=h.polls+1;return end
        return send(ctx,cmd,...)
    end
    h.p.vitals={hp=100,fatigue=0,encumbrance=0}
    h.p.room.exits={polnoc='safe'}
    for _,m in ipairs(h.p.group.members)do m.hp=m.maxhp end
    for _,m in ipairs(h.p.entities.entities)do m.hp=m.maxhp end
    if empty then for i=#h.p.entities.entities,1,-1 do
        if h.p.entities.entities[i].relation=='hostile' then table.remove(h.p.entities.entities,i)end
    end end
    h.saved.profiles={test={name='Test',route={'rooma','safe'},targets={'goblin','goblinka','smok'},avoid=avoid or {},
        safeRoom='safe',rules={maxEnemies=6,minRoomRevisit=0}}};h.saved.selected='test'
    getRoomIDbyHash=function(id)return id=='rooma' and 1 or 2 end
    getRoomHashByID=function(id)return id==1 and 'rooma' or 'safe'end
    getPath=function()speedWalkPath={2};return true end
    h.api=P.setup(h.ctx)
    return h
end
do
    local h=fixture()
    local names={'smok','goblinka','goblin','goblin'}
    for i=1,4 do h.p.entities.entities[i+5].name=names[i] end
    h.api.request('start');h.advance(.1)
    for index,id in ipairs({'enemy3','enemy4','enemy2','enemy1'})do
        assert(h.sent[index]=='zabij '..id,'target priority mismatch: '..table.concat(h.sent,','))
        for i=#h.p.entities.entities,1,-1 do if h.p.entities.entities[i].id==id then table.remove(h.p.entities.entities,i)end end
        h.emit('chimera.room.entities',h.p.entities);h.advance(4.1)
    end
    h.dispose()
end
local function strength(h,value)
    h.p.vitals.fatigue=value and 100-value or nil
    h.emit('chimera.char.vitals',h.p.vitals);h.advance(.1)
end
do
    local h=fixture({'goblin'});h.api.request('start');h.advance(.1)
    assert(h.sent[1]=='n')
    h.triggers[TIRED]();h.advance(10)
    assert(#h.sent==1 and not h.api.status().paused,'stale full stamina must not retry')
    assert(h.polls==0,'rest consumes GMCP without sending stan')
    strength(h,29);assert(#h.sent==1)
    strength(h,nil);assert(#h.sent==1,'missing stamina never authorizes movement')
    strength(h,30);assert(h.sent[2]=='n','resume same exit when rested')
    h.triggers[TIRED]();h.advance(3)
    h.p.combat.relations={{attacker='enemy1',defender='me'}}
    strength(h,9);assert(#h.sent==2)
    strength(h,10);assert(h.sent[3]=='n','10 percent is enough in combat')
    -- Repeated explicit refusals must not exhaust the retry/loop allowance.
    for i=1,4 do
        h.triggers[TIRED]();h.advance(3);strength(h,10)
        assert(#h.sent==3+i and not h.api.status().paused)
    end
    h.triggers[TIRED]();h.api.stop_all();strength(h,100);h.advance(10)
    assert(#h.sent==7 and not h.api.status().started,'STOP never resumes from rest')
    h.dispose()
end
do
    local h=fixture(nil,true);h.api.request('start');h.advance(.1)
    assert(#h.moves==1,'patrol owns walker')
    h.triggers[TIRED]();h.advance(3);strength(h,29)
    assert(#h.moves==1)
    strength(h,30);assert(#h.moves==2,'normal walker resumes original destination')
    h.dispose()
end
do
    local h=fixture();h.p.vitals.hp=20
    h.p.combat.relations={{attacker='enemy1',defender='me'}}
    h.api.request('start');h.advance(.1);assert(h.sent[1]=='n',table.concat(h.sent,',')..' / '..table.concat(h.messages,';'))
    h.triggers[TIRED]();h.advance(10);strength(h,9);assert(#h.sent==1)
    strength(h,10);assert(h.sent[2]=='n' and not h.api.status().paused,'emergency retry survives rest')
    h.dispose()
end
print('PASS target order and fatigue: overlap, fresh vitals, 30/10 thresholds, retry budget, walker, emergency, STOP')

