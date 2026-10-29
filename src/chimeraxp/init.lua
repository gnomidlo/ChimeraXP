return function(module)
    local Engine=module("engine")
    local Model=module("tactics_model")
    local Tactics=module("tactics")
    local Integration=module("integration")
    local HUD=module("hud")
    local setup=Engine.setup
    Engine.title="ChimeraXP — wyprawy i taktyka"
    Engine.description="Zwięzły HUD, role drużyny, patrol i auto-zarobek"
    Engine.setup=function(ctx)
        local view,tactics,patrol
        local integration=Integration.new(ctx)
        local function changed() if view then view:render() end end
        patrol=setup(ctx,{
            changed=changed,
            open=function() if view then return view:open("areas") end return false end,
            on_stop=function() if tactics then tactics.stop("STOP ChimeraXP") end end,
            before_start=function(profile)
                return integration.check(profile or {})
            end,
        })
        tactics=Tactics.new(ctx,Model,integration,patrol,changed)
        local stop_patrol=patrol.stop
        local function stop()
            tactics.stop("STOP ChimeraXP");stop_patrol("STOP ChimeraXP")
        end
        patrol.stop=stop
        view=HUD.new(ctx,patrol,tactics,stop)
        -- All entry points share the same engines and validation.
        ctx:command{"exp taktyka",args="[on|off|status]",help="Taktyka drużyny",fn=function(arg)
            if arg=="on" then tactics.toggle(true)
            elseif arg=="off" or arg=="stop" then tactics.stop()
            else ctx:report("Taktyka",{{"Stan",tactics.status().phase},{"Powód",tactics.status().detail}}) end
        end}
        ctx:command{"exp hud",args="[on|off]",help="Widoczność górnego paska",fn=function(arg) view:visible(arg~="off") end}
        ctx:command{"exp okno reset",help="Przywróć zwięzły HUD",fn=function() view:visible(true);view:open("areas") end}
        ctx:command{"exp rola",args="<ID rola>",help="Rola obecnej jednostki",fn=function(arg)
            local id,role=tostring(arg or ""):match("^(%S+)%s+(%S+)$")
            if not tactics.configure(id,"role",role) then ctx.log.warn("Użycie: /exp rola ID tank|offtank|standard|asekuracja|support") end
        end}
        -- The engine's CLI stop must stop tactics too, not just HUD/API clicks.
        -- Register only one alias by supplying this hook at engine construction.
        patrol.stop_all=stop
        patrol.tactics=tactics
        patrol.hud=view
        return patrol
    end
    return Engine
end
