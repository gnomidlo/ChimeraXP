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
        local view,tactics,patrol,tower
        local integration=Integration.new(ctx)
        local function changed() if view then view:render() end end
        patrol=setup(ctx,{
            changed=changed, safety=module("safety").new(),
            open=function() if view then return view:open("areas") end return false end,
            on_stop=function() if tactics then tactics.stop("STOP ChimeraXP") end end,
            before_start=function(profile)
                if tower and tower.status().started then
                    return "Wieza prowadzi eksploracje. Zatrzymaj ja przed klasycznym EXP."
                end
                return integration.check(profile or {})
            end,
            stop_tower=function()
                if tower and tower.status().started then tower.stop("STOP /exp") end
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
            if t.started or t.done then return t end
        end
        patrol.status=function()
            local s=base_status()
            local t=tower_status()
            if t then
                s.started=t.started;s.paused=t.paused;s.phase=t.phase
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
                snap.profile={name="Wieza / poziom "..tostring(t.level),economy={enabled=false},route={}}
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
        patrol.request=function(name,arg)
            if tower.status().started then
                if name=="pauza" then tower.pause("Pauza z HUD");return true end
                if name=="wznow" then return tower.resume() end
                if name=="stop" then tower.stop("STOP ChimeraXP");return true end
                if name=="start" then return false,"Wieza juz dziala" end
            end
            return base_request(name,arg)
        end
        local stop_patrol=patrol.stop
        -- Stopping an expedition must not disable independently enabled Defense.
        local function stop()
            if tower.status().started then tower.stop("STOP ChimeraXP") end
            stop_patrol("STOP AutoExp")
        end
        local function stop_all()
            tactics.stop("STOP ChimeraXP")
            stop()
        end
        patrol.stop=stop
        patrol.pause=function(reason)
            if tower.status().started then return tower.pause(reason) end
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