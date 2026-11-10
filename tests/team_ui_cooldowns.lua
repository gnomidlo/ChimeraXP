-- Regression: player maneuvers only enter cooldown, never disable automation.
local new=dofile('tests/support_harness.lua')
local P=dofile('plugins/chimera_autoexp/init.lua')
local M=dofile('src/chimeraxp/tactics_model.lua')
local h=new()
h.api=P.setup(h.ctx)
local tactics=h.api.tactics
local function find(name)
    for _,row in ipairs(tactics.rows()) do if row.name==name then return row end end
    error('missing member '..name)
end
assert(tactics.toggle(true))
assert(find('me').enabled,'self automation starts enabled')
h.emit('sysDataSendRequest',nil,'zaslon tank przed enemy1')
assert(tactics.status().on and find('me').enabled,'manual cover must not disable auto')
assert(find('me').cooldown>0,'manual cover must start formation cooldown')
local before=find('me').cooldown
h.emit('sysDataSendRequest',nil,'zabij enemy1')
assert(find('me').cooldown==before,'ordinary attack must not reset maneuver cooldown')
assert(M.manual('zabij enemy1',nil,{minions={{},{}}})==nil)
assert(M.manual('rozkaz druzynie zaatakowac enemy1',nil,{minions={{},{}}})==nil)
assert(M.manual('rozkaz druzynie zaslonic ciebie',nil,{minions={{},{}}}).kind=='cover')
local pet=find('petone')
assert(pet.channel==2,'first minion auto-discovered')
h.emit('sysDataSendRequest',nil,'parozkaz petone zaslon me przed enemy1')
assert(find('petone').cooldown>0,'manual pet cover sets individual cooldown')
local trigger=[[^( . )$]]
trigger=[[ ^(.+) jest gotow[ay] do kolejnej zmiany w szyku\.$ ]]
trigger=trigger:gsub('^%s+',''):gsub('%s+$','')
assert(h.triggers[trigger],'readiness trigger is registered')
matches={[2]='petone'}
h.triggers[trigger]()
assert(find('petone').cooldown==0,'readiness immediately clears pet cooldown')
assert(tactics.status().on,'readiness never disables tactic engine')
h.dispose()
print('PASS team manual cooldown, instant readiness and attack without maneuver cooldown')
