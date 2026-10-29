-- Read-only compatibility boundary for official Chimera 5 and older addons.
-- No global send interception and no silent changes to the player's settings.
local I={}
function I.new(ctx)
    local function old_automation()
        for _,name in ipairs({"tacticus","tactician","tacticus_ng"}) do
            local old=rawget(_G,name)
            if type(old)=="table" then
                if old.mode=="auto" or (type(old.state)=="table" and old.state.on) then
                    return "Wyłącz poprzedni Tacticus przed uruchomieniem ChimeraXP."
                end
            end
        end
    end
    local function setting(module,key)
        local config=ctx.app and ctx.app.config
        if config and type(config.get)=="function" then
            local ok,value=pcall(config.get,config,module,key)
            if not ok then return nil,"Nie można sprawdzić ustawień: "..module end
            return value
        end
    end
    local function status(name,method)
        local records=ctx.app and ctx.app.loader and ctx.app.loader.records
        local record=records and records[name]
        if record and record.status=="running" and record.api and type(record.api[method])=="function" then
            local ok,value=pcall(record.api[method])
            if not ok then return nil,"Nie można sprawdzić modułu "..name end
            return value
        end
    end
    return {
        check=function(patrol)
            local reason=old_automation();if reason then return reason end
            local bot,err=status("bots","status")
            if err then return err end
            if bot then return "Działa oficjalny bot. Zatrzymaj go przed automatyką ChimeraXP." end
            local chase,why=setting("team","autopogon")
            if why then return why end
            if patrol and chase then return "Wyłącz /autopogon przed patrolem ChimeraXP." end
            local support,e=setting("team","autowsparcie")
            if e then return e end
            if support then return "Wyłącz /autowsparcie: celami ma sterować jeden automat." end
            if patrol then
                local hooks,problem=status("automation","summary")
                if problem then return problem end
                if type(hooks)=="table" and #hooks>0 then
                    return "Aktywne /pre_walk, /post_walk lub /post_fight. Wyłącz je przed patrolem."
                end
                local collect,err2=setting("collect","zbieranie")
                if err2 then return err2 end
                if collect and patrol.economy and patrol.economy.enabled and #(patrol.loot or {})>0 then
                    return "Wyłącz oficjalne /zbieranie: łupy tego profilu obsługuje ChimeraXP."
                end
            end
        end,
        migrate_tactics=function()
            local storage=ctx.app and ctx.app.storage
            if storage and type(storage.get_state)=="function" then
                local ok,config=pcall(storage.get_state,storage,"tacticus_ng","config")
                if ok and type(config)=="table" then return config end
            end
        end,
    }
end
return I
