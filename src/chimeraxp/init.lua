return function(module)
    local Engine=module("engine")
    local Model=module("tactics_model")
    local Tactics=module("tactics")
    local Integration=module("integration")
    local Tower=module("tower")
    local TowerLoot=module("tower_loot")
    local HUD=module("hud")
    local setup=Engine.setup
    Engine.title="ChimeraXP — wyprawy i taktyka"
    Engine.description="Zwięzły HUD, role drużyny, patrol, auto-zarobek i Wieża"
    Engine.setup=function(ctx)
        local view,tactics,patrol,tower,control
        local integration=Integration.new(ctx)
        local function changed() if view then view:render() end end
        patrol=setup(ctx,{
            changed=changed, safety=module("safety").new(),
            control=function(name,arg) if control then return control(name,arg) end end,
            open=function() if view then return view:open("areas") end return false end,
            on_stop=function() if tactics then tactics.stop("STOP ChimeraXP") end end,
            before_start=function(profile)
                if tower then
                    local t=tower.status()
                    if t.started or t.pending or tower.in_tower() then
                        return "W Kregach Shoona uzyj Wiezy, nie klasycznego EXP."
                    end
                end
                return integration.check(profile or {})
            end,
            stop_tower=function()
                if tower then
                    local t=tower.status()
                    if t.started or t.pending or t.done then tower.stop("STOP /exp") end
                end
            end,
            set_party_attack=function(setting)
                if not tower then return false end
                local state=tower.status()
                if not (state.started or state.pending or tower.in_tower()) then return false end
                -- The real CLI and graphical HUD must both edit the Tower
                -- setting, not the unrelated selected classic EXP profile.
                tower.set_party_attack(setting)
                return true
            end,
        })
        local base_status=patrol.status
        local base_snapshot=patrol.snapshot
        local base_request=patrol.request
        local base_issuing=patrol.issuing_attack_order
        local base_party=patrol.party_attack_enabled
        tower=Tower.new(ctx,base_status,integration,changed,TowerLoot)
        -- The tower and patrol share one ownership/status contract for Tacticus
        -- and HUD, but never run both movement planners simultaneously.
        local function tower_status()
            local t=tower.status()
            if t.started or t.pending or (tower.in_tower() and not base_status().started) then return t end
        end
        patrol.status=function()
            local s=base_status()
            local t=tower_status()
            if t then
                s.started=t.started or t.pending or false;s.paused=t.paused;s.phase=t.phase
                s.defensive_only=t.defensive_only;s.tower=true
                s.reason=t.reason;s.economy=nil
            end
            return s
        end
        patrol.snapshot=function()
            local snap=base_snapshot()
            local t=tower_status()
            if t then
                snap.status=patrol.status()
                snap.profile={name="Wieza / poziom "..tostring(t.level or "?"),partyAttack=t.partyAttack,
                    economy={enabled=false},route={},targets={},avoid={},loot={},rules={}}
                snap.status.elapsed=0
                snap.status.xp=0
                snap.status.selected="wieza"
            end
            return snap
        end
        patrol.issuing_attack_order=function()
            return base_issuing() or tower.issuing_attack_order()
        end
        patrol.party_attack_enabled=function()
            if tower_status() then return tower.party_attack_enabled() end
            return base_party()
        end
        local stop_patrol=patrol.stop
        -- One dispatcher for the CLI, toolbar, dropdown and API requests.
        -- A classic run already active remains its own owner; START in Shoona
        -- explicitly clears the stale classic patrol before verifying entrance.
        control=function(name,arg)
            local t=tower.status()
            local classic=base_status()
            if name=="stop" then
                if t.started or t.pending or t.done then
                    tower.stop("STOP Wieza")
                    if classic.started then stop_patrol("STOP AutoExp") end
                    return true,true
                end
                if tower.in_tower() and not classic.started then return true,true end
                return false
            end
            if name~="start" and name~="pauza" and name~="wznow" then return false end
            if t.started or t.pending then
                if name=="pauza" then
                    if t.pending and not t.started then tower.stop("Anulowano start Wiezy")
                    else tower.pause("Pauza uzytkownika") end
                    return true,true
                end
                if name=="wznow" then return true,tower.resume() end
                if t.paused then return true,tower.resume() end
                return true,tower.start()
            end
            if tower.in_tower() then
                if name=="start" or name=="wznow" then
                    if classic.started then stop_patrol("Zatrzymano klasyczny EXP przed startem Wiezy") end
                    return true,tower.start()
                end
                if not classic.started then return true,false end
            end
            return false
        end
        patrol.request=base_request
        -- Same STOP semantics as /exp stop, leaving Defense untouched.
        local function stop()
            return base_request("stop")
        end
        local function stop_all()
            tactics.stop("STOP ChimeraXP")
            stop()
        end
        patrol.stop=stop
        patrol.pause=function(reason)
            local t=tower.status()
            if t.started then return tower.pause(reason) end
            if t.pending then return tower.stop(reason) end
            return base_request("pauza")
        end
        tactics=Tactics.new(ctx,Model,integration,patrol,changed)
        view=HUD.new(ctx,patrol,tactics,stop)
        ctx:command{"exp taktyka",args="[on|off|status]",help="Taktyka drużyny",fn=function(arg)
            if arg=="on" then tactics.toggle(true)
            elseif arg=="off" or arg=="stop" then tactics.stop()
            else ctx:report("Taktyka",{{"Stan",tactics.status().phase},{"Powód",tactics.status().detail}}) end
        end}
        ctx:command{"exp hud",args="[on|off]",help="Widoczność górnego paska",fn=function(arg) view:visible(arg~="off") end}
        ctx:command{"exp okno reset",help="Przywróć zwięzły HUD",fn=function() view:visible(true);view:open("areas") end}
        ctx:command{"exp rola",args="<ID rola>",help="Rola obecnej jednostki",fn=function(arg)
            local id,role=tostring(arg or ""):match("^(%S+)%s+(%S+)$")
            if not tactics.configure(id,"role",role) then ctx.log.warn("Użycie: /exp rola ID obronca|asekurant|zrownowazony|chroniony") end
        end}
        patrol.stop_all=stop_all
        patrol.tactics=tactics
        patrol.hud=view
        patrol.tower=tower
        return patrol
    end
    return Engine
end