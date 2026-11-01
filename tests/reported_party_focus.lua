local M=dofile('src/chimeraxp/tactics_model.lua')
local dump=dofile('tests/fixtures/party-focus-20261101.lua')
local api={connected=function()return true end,
    room=function()return dump.Room.Info end,
    char=function()return dump.Char.Info end,
    vitals=function()return dump.Char.Vitals end,
    entities=function()return dump.Chimera.Room.Entities end,
    group=function()return dump.Chimera.Group.State end,
    combat=function()return dump.Chimera.Combat.State end}
local prefix='e72d4042788c06f9e-'
local c=M.defaults({team_orders=true,team_broadcast=true,minions={{id=prefix..'182'}}})
local enabled={true,true,true,true}
local s=assert(M.snapshot(api))
assert(s.group_complete and s.leader==prefix..'1')
for _,suffix in ipairs({'1','169','173','182'}) do
    assert(s.targets[prefix..suffix]==prefix..'187','actual dump records everyone attacking')
end
local d=M.plan(s,c,enabled)
assert(not d or d.kind~='team_attack','aligned party needs no new order')
for _,suffix in ipairs({'169','173','182'}) do
    local id=prefix..suffix
    for _,target in ipairs({false,prefix..'188'}) do
        local copy=assert(M.snapshot(api));copy.targets[id]=target or nil
        local planned=assert(M.plan(copy,c,enabled),'idle or divergent member must trigger an order')
        assert(planned.kind=='team_attack')
        assert(M.command(planned,copy)=='rozkaz druzynie zaatakowac '..prefix..'187')
        local waiting=M.plan(copy,c,enabled,{[4]={cover=true,support=true}})
        assert(not waiting or waiting.kind~='team_attack','team cooldown still applies')
    end
end
print('PASS reported GMCP: all four aligned; each idle/divergent member triggers team focus after cooldown')
