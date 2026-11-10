-- Party attack is opt-in, per-profile, and follows each actual AutoExp kill command.
local new=dofile('tests/support_harness.lua')
local P=dofile('plugins/chimera_autoexp/init.lua')
local function fixture(enabled)
    local h=new()
    h.p.vitals={hp=100,fatigue=0,encumbrance=0}
    h.p.room.exits={polnoc='safe'}
    for _,m in ipairs(h.p.group.members) do m.hp=m.maxhp end
    for _,m in ipairs(h.p.entities.entities) do m.hp=m.maxhp end
    for i=#h.p.entities.entities,1,-1 do
        local ent=h.p.entities.entities[i]
        if ent.relation=='hostile' and ent.id~='enemy1' then table.remove(h.p.entities.entities,i) end
    end
    h.saved.profiles={test={name='Test',route={'rooma','safe'},targets={'goblin'},
        safeRoom='safe',partyAttack=enabled,rules={maxEnemies=6,minRoomRevisit=0}}}
    h.saved.selected='test'
    getRoomIDbyHash=function(id) return id=='rooma' and 1 or 2 end
    getRoomHashByID=function(id) return id==1 and 'rooma' or 'safe' end
    getPath=function() speedWalkPath={2};return true end
    h.api=P.setup(h.ctx)
    return h
end
do
    local h=fixture(false)
    h.api.request('start');h.advance(.1)
    assert(#h.sent==1 and h.sent[1]=='zabij enemy1','default: no party order')
    h.dispose()
end
do
    local h=fixture(true)
    h.api.request('start');h.advance(.1)
    assert(h.sent[1]=='zabij enemy1' and h.sent[2]=='rozkaz druzynie zaatakowac enemy1',
        'party order must immediately follow kill')
    h.emit('chimera.room.entities',h.p.entities);h.advance(.2)
    assert(#h.sent==2,'GMCP refresh must not duplicate order')
    h.dispose()
end
do
    local h=fixture(false)
    assert(h.api.request('druzyna','on')~=false)
    assert(h.saved.profiles.test.partyAttack==true,'option persisted per profile')
    h.api.request('start');h.advance(.1)
    assert(h.sent[2]=='rozkaz druzynie zaatakowac enemy1')
    h.dispose()
end
do
    local h=fixture(true)
    h.p.group.leader='tank'
    h.api.request('start');h.advance(.1)
    assert(#h.sent==1 and h.sent[1]=='zabij enemy1','non-leader must not order')
    h.dispose()
end
do
    local h=fixture(true)
    for i=#h.p.group.members,1,-1 do if not (h.p.group.members[i].self==1) then
        table.remove(h.p.group.members,i)
    end end
    h.api.request('start');h.advance(.1)
    assert(#h.sent==1,'no orders when solo')
    h.dispose()
end
do
    local h=fixture(true)
    h.api.request('test');h.advance(.1)
    assert(#h.sent==0,'dry run must not send any combat commands')
    h.dispose()
end
print('PASS party attack: default off, leader, dedupe, toggle, solo, dry run')
