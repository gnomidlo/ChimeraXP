-- Defense 3.0: one risk planner, exactly four roles, no stale task/target
-- gates, profile persistence and safe migration.
local new=dofile("tests/support_harness.lua")
local M=dofile("src/chimeraxp/tactics_model.lua")
local T=dofile("src/chimeraxp/tactics.lua")
local I=dofile("src/chimeraxp/integration.lua")
local function hp(h,id,value)
    for _,list in ipairs({h.p.group.members,h.p.entities.entities}) do
        for _,m in ipairs(list) do
            if m.id==id then m.hp=value;m.maxhp=100 end
        end
    end
    if id=="me" then h.p.vitals.hp=value end
end
local function configured()
    local h=new()
    h.saved.tactics={
        role="asekuracja",team_orders=false,team_broadcast=false,
        minions={
            {id="petone",name="petone",task="protect",target_id="friend"},
            {id="pettwo",name="pettwo",task="self"},
        },
        profiles={
            petone={name="petone",kind="npc",role="tank",min_hp=55,max_load=4},
            pettwo={name="pettwo",kind="npc",role="standard",min_hp=65,max_load=2},
        }
    }
    h.xp={started=false}
    h.api=T.new(h.ctx,M,I.new(h.ctx),
        {status=function() return h.xp end},function() end)
    return h
end

do
    local c=M.defaults({role="support",minions={{id="petone",task="reserve"},
        {id="pettwo",task="protect",target_id="me"}},
        profiles={
            petone={name="petone",kind="npc",role="tank",min_hp=55,max_load=4},
            pettwo={name="pettwo",kind="npc",role="offtank",min_hp=60,max_load=3}
        },
        protect=true,protect_id="pettwo",tank_id="petone",schema=2})
    assert(c.schema==3 and c.role=="chroniony")
    assert(c.minions[1].task==nil and c.minions[2].target_id==nil)
    assert(c.protect==nil and c.protect_id==nil and c.tank_id==nil)
    assert(c.profiles.petone.role=="obronca" and not c.profiles.petone.enabled,
        "legacy reserve is disabled, role preserved")
    assert(c.profiles.pettwo.role=="asekurant"
        and c.profiles.pettwo.min_hp==70 and c.profiles.pettwo.max_load==2,
        "old default role thresholds convert to the new preset")
    local defaults=M.defaults({})
    assert(defaults.role=="zrownowazony" and #M.roles==4)
end

do
    local h=configured()
    hp(h,"me",54);hp(h,"petone",100);hp(h,"pettwo",100)
    h.p.combat.relations={{attacker="enemy1",defender="me"},
        {attacker="enemy2",defender="me"},
        {attacker="enemy3",defender="me"}}
    assert(h.api.toggle(true));h.fresh();h.advance(5.2)
    assert(h.sent[1] and h.sent[1]:match("^rozkaz pet%a+ zaslonic ciebie$"),
        "no stale 'protect' task may block a rescue of the wounded leader")
    local rows=h.api.rows()
    for _,r in ipairs(rows) do
        if r.id=="petone" then assert(r.role=="obronca") end
        if r.id=="pettwo" then assert(r.role=="zrownowazony") end
    end
    assert(h.saved.tactics==nil or h.saved.tactics.minions[1].task,
        "in-memory migration doesn't mutate saved preferences until explicitly saved")
    h.dispose()
end

do
    local h=configured()
    h.fresh()
    assert(h.api.configure("petone","role","asekurant"))
    assert(h.saved.tactics.profiles.petone.role=="asekurant")
    -- Server ID changes on the next summon; name remains unique.
    for _,list in ipairs({h.p.group.members,h.p.entities.entities}) do
        for _,m in ipairs(list) do
            if m.id=="petone" then m.id="petone2" end
        end
    end
    h.fresh()
    assert(h.saved.tactics.profiles.petone2
        and h.saved.tactics.profiles.petone2.role=="asekurant",
        "name+kind identity restores previous pet role after entity ID change")
    assert(not h.saved.tactics.profiles.petone,"avoid ambiguous history")
    local row
    for _,r in ipairs(h.api.rows()) do if r.id=="petone2" then row=r end end
    assert(row and row.role=="asekurant")
    h.dispose()
end

do
    local h=configured()
    h.fresh()
    assert(h.api.configure("pettwo","role","chroniony"))
    local c=h.saved.tactics
    local s=assert(M.snapshot(h.gmcp))
    hp(h,"me",90)
    s=assert(M.snapshot(h.gmcp))
    h.p.combat.relations={{attacker="enemy1",defender="petone"}}
    s=assert(M.snapshot(h.gmcp))
    s.risk={petone={level="critical",hp=30}}
    local plan=M.plan(s,c,{false,false,true,false})
    assert(not (plan and plan.kind=="cover" and plan.actor=="pettwo"),
        "Protected role must not take attackers even for critical rescue")
    local reason=M.explain_cover(s,c,{false,false,true,false},{}, "petone")
    assert(reason:find("rola Chroniony",1,true),
        "explicit role and safety limit are visible in diagnostics")
    h.dispose()
end

print("PASS Defense 3.0: unified decisions, four roles, disabled legacy reserve and persistent pet roles")
