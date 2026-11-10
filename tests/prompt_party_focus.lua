local new=dofile('tests/support_harness.lua')
local M=dofile('src/chimeraxp/tactics_model.lua')
local T=dofile('src/chimeraxp/tactics.lua')
local function start(h)
    h.saved.tactics={team_orders=true,team_broadcast=true}
    h.api=T.new(h.ctx,M,{check=function()end},{status=function()return {started=false}end},function()end)
    h.api.toggle(true);h.fresh();h.advance(6)
end
do
    local h=new()
    -- Reconstruct the later user report from the preceding captured room:
    -- only the three players attack the new gnoll; Chasstana is idle.
    local dump=dofile('tests/fixtures/party-focus-20261101.lua')
    local prefix='e72d4042788c06f9e-'
    h.p.char=dump.Char.Info;h.p.vitals={hp=97,mana=100,fatigue=26}
    h.p.room={id='6c2ad9afa786bd63',key='6c2ad9afa786bd63'}
    h.p.group=dump.Chimera.Group.State
    local health={['1']=1792,['169']=1558,['173']=820,['182']=300}
    for _,member in ipairs(h.p.group.members) do member.hp=health[member.id:match('%-(%d+)$')] end
    h.p.entities={room=h.p.room.id,entities={}}
    for _,entity in ipairs(dump.Chimera.Room.Entities.entities) do
        local hp=health[entity.id:match('%-(%d+)$')]
        if hp then entity.hp=hp;h.p.entities.entities[#h.p.entities.entities+1]=entity end
    end
    h.p.entities.entities[#h.p.entities.entities+1]={id=prefix..'189',name='Silny grozny gnoll',kind='npc',relation='hostile',hp=937,maxhp=1060,states={}}
    h.p.combat={room=h.p.room.id,primary=prefix..'189',covers=dump.Chimera.Combat.State.covers,relations={}}
    for _,id in ipairs({'1','173','169'}) do
        h.p.combat.relations[#h.p.combat.relations+1]={attacker=prefix..id,defender=prefix..'189'}
    end
    h.p.combat.relations[4]={attacker=prefix..'189',defender=prefix..'169'}
    start(h)
    assert(h.sent[1]=='rozkaz druzynie zaatakowac '..prefix..'189','idle Chasstana joins on first eligible evaluation')
    assert(#h.sent==1,'discovery does not impose a 15s wait or duplicate orders')
    h.api.stop();h.dispose()
end
do
    local h=new();start(h)
    -- A new ID during an already-running session must not stall focus for 15s.
    for _,list in ipairs({h.p.group.members,h.p.entities.entities}) do
        for _,m in ipairs(list) do if m.id=='petone' then m.id='pet-new' end end
    end
    h.p.combat.relations={{attacker='me',defender='enemy1'}}
    h.fresh();h.advance(.9);assert(#h.sent==0)
    h.advance(.7);assert(h.sent[1]=='rozkaz druzynie zaatakowac enemy1')
    h.advance(4)
    assert(h.sent[2]==h.sent[1],'unconfirmed attack retries without formation cooldown')
    h.fresh();h.advance(5);h.fresh();h.advance(4)
    assert(#h.sent<=6,'0.5s monitoring must not flood commands between confirmation waits')
    h.dispose()
end
do
    local h=new()
    local c=M.defaults({team_orders=true,team_broadcast=true,minions={{id='petone'},{id='pettwo'}}})
    h.p.combat.relations={{attacker='me',defender='enemy1'},{attacker='enemy1',defender='me'},{attacker='enemy2',defender='me'}}
    local function plan()return M.plan(assert(M.snapshot(h.gmcp)),c,{true,true,true,true})end
    assert(plan().kind=='team_attack','focus precedes routine balancing that would consume the team cooldown')
    h.p.vitals.hp=30
    assert(plan().kind~='team_attack' and plan().priority>98,'emergency protection remains first')
    h.dispose()
end
print('PASS prompt focus: idle Chasstana, new IDs, periodic checks, attack confirmation wait, emergency priority')
