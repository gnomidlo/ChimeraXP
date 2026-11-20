-- "Wspolny cel ataku" belongs to the XP profile, not to the
-- separately named "Wspolna zaslona druzyny" switch.
local new=dofile("tests/support_harness.lua")
local M=dofile("src/chimeraxp/tactics_model.lua")
local T=dofile("src/chimeraxp/tactics.lua")

local function fixture(running, disabled)
    local h=new()
    h.saved.tactics={team_orders=false,team_broadcast=false,
        minions={{id="petone",name="petone"},{id="pettwo",name="pettwo"}},
        profiles=disabled and {petone={name="petone",kind="npc",
            enabled=false,role="zrownowazony"}} or {}}
    h.p.combat.relations={{attacker="me",defender="enemy1"},
        {attacker="petone",defender="enemy2"},
        {attacker="pettwo",defender="enemy1"}}
    local xp={status=function() return {started=running,dry=false,phase="COMBAT"} end,
        party_attack_enabled=function() return true end,
        party_focus_state=function()
            return {last_target="enemy1",last_at=0,last_room="rooma"}
        end}
    h.api=T.new(h.ctx,M,{check=function()end},xp,function()end)
    h.api.toggle(true);h.fresh();h.advance(5.3)
    return h
end

do
    local h=fixture(false,false)
    assert(h.sent[1]=="rozkaz druzynie zaatakowac enemy1",
        "independent Obrona must obey opted-in common attack in manual combat")
    assert(#h.sent==1,"single shared focus order, no per-minion duplication")
    h.p.combat.relations[2].defender="enemy1"
    h.fresh();h.advance(.4)
    assert(#h.sent==1,"confirmed aligned party never needs repeat order")
    h.dispose()
end

do
    local h=fixture(false,false)
    h.advance(4)
    assert(#h.sent==1,"unconfirmed group order does not flood the server")
    h.advance(4)
    assert(h.sent[2]=="rozkaz druzynie zaatakowac enemy1",
        "still-divergent party may retry only after bounded 7s window")
    h.dispose()
end

do
    local h=fixture(true,false)
    assert(h.sent[1]=="parozkaz petone wesprzyj",
        "running XP owns group broadcast, but verified pet may still support")
    assert(#h.sent==1,"tactics must not duplicate XP group attack command")
    h.dispose()
end

do
    local h=fixture(true,true)
    assert(#h.sent==0,"never override a disabled pet with an individual order")
    local detail=h.api.status().detail
    assert(detail:find("petone %(udział w Obronie wyłączony%)"),
        "diagnose which minion is disabled: "..detail)
    assert(detail:find("rozkaz AutoExp",1,true),
        "report which controller owns party focus: "..detail)
    h.dispose()
end

do
    local h=fixture(false,true)
    assert(h.sent[1]=="rozkaz druzynie zaatakowac enemy1",
        "explicit team focus still applies to whole party, even if pet is opted out of protective maneuvers")
    h.dispose()
end

print("PASS party focus ownership: stopped patrol, running XP, clear per-pet reason")
