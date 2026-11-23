-- Kregi Shoona: loot from the ground and ordinal corpses, without sale/bank.
-- One exclusive request at a time: the count response must belong to our room.
local L = {}

local COUNTS = {
    [1]="jednej sztuki",[2]="dwoch sztuk",[3]="trzech sztuk",[4]="czterech sztuk",
    [5]="pieciu sztuk",[6]="szesciu sztuk",[7]="siedmiu sztuk",[8]="osmiu sztuk",
    [9]="dziewieciu sztuk",[10]="dziesieciu sztuk",[11]="jedenastu sztuk",
    [12]="dwunastu sztuk",[13]="trzynastu sztuk",[14]="czternastu sztuk",
    [15]="pietnastu sztuk",[16]="szesnastu sztuk",[17]="siedemnastu sztuk",
    [18]="osiemnastu sztuk",[19]="dziewietnastu sztuk",[20]="dwudziestu sztuk",
    [21]="dwudziestu jednej sztuki",[22]="dwudziestu dwoch sztuk",
    [23]="dwudziestu trzech sztuk",[24]="dwudziestu czterech sztuk",
    [25]="dwudziestu pieciu sztuk",[26]="dwudziestu szesciu sztuk",
    [27]="dwudziestu siedmiu sztuk",[28]="dwudziestu osmiu sztuk",
    [29]="dwudziestu dziewieciu sztuk",[30]="trzydziestu sztuk"
}

function L.new(ctx, gmcp_api, say)
    local active, timer
    local function cancel_timer()
        if timer then ctx:cancel(timer); timer=nil end
    end
    local function stop()
        cancel_timer()
        active=nil
    end
    local function valid()
        return active and gmcp_api.room() and gmcp_api.room().id==active.room
            and not active.cancelled
    end
    local function failure(reason)
        local old=active
        stop()
        if old and old.fail then old.fail(reason) end
    end
    local function schedule(seconds, fn)
        cancel_timer()
        timer=ctx:timer(seconds,function()
            timer=nil
            if valid() then fn() elseif active then failure("Zmiana pokoju podczas zbierania") end
        end)
    end
    local next_command
    next_command=function()
        if not valid() then failure("Zmiana pokoju podczas zbierania");return end
        local a=active
        local command
        if a.ground<=#a.items then
            command="wez "..a.items[a.ground]
            a.ground=a.ground+1
        elseif a.corpse<=a.count then
            command="wez "..a.items[a.item].." z "..a.corpse..". ciala"
            a.item=a.item+1
            if a.item>#a.items then a.item=1;a.corpse=a.corpse+1 end
        elseif a.finish<=2 then
            command=({"wloz monety do plecaka","napelnij plecak"})[a.finish]
            a.finish=a.finish+1
        else
            local done=a.done
            stop()
            if done then done() end
            return
        end
        local ok,err=pcall(ctx.send,ctx,command)
        if not ok then failure("Blad komendy '"..command.."': "..tostring(err));return end
        schedule(a.delay,next_command)
    end
    local function counted(count)
        if not valid() or active.phase~="COUNTING" then return end
        cancel_timer()
        active.count,active.phase=count,"TAKING"
        active.ground,active.item,active.corpse,active.finish=1,1,1,1
        next_command()
    end
    for count,words in pairs(COUNTS) do
        local n=count
        ctx:trigger("^Doliczyl(?:as|es) sie "..words..[[\.$]],function() counted(n) end)
        ctx:trigger("^Doliczyl(?:as|es) sie "..n.." "..(n==1 and "sztuki" or "sztuk")..[[\.$]],function() counted(n) end)
    end
    ctx:trigger([[^Nie doliczyl(?:as|es) sie (?:ani jednej|zadnej) sztuki\.$]],function() counted(0) end)
    ctx:trigger([[^Nie widzisz tu niczego takiego\.$]],function() counted(0) end)
    return {
        start=function(room_id,items,delay,done,fail)
            if active then return false,"Zbieranie juz trwa" end
            local copy={}
            for _,item in ipairs(items or {}) do
                if type(item)~="string" or item=="" or #item>80 or item:find("[;%c]") then
                    return false,"Nieprawidlowa kategoria lupow"
                end
                copy[#copy+1]=item
            end
            active={room=room_id,items=copy,delay=delay or 0.7,phase="COUNTING",done=done,fail=fail}
            schedule(5,function() failure("Brak odpowiedzi na 'policz ciala' po 5 s") end)
            local ok,err=pcall(ctx.send,ctx,"policz ciala")
            if not ok then failure("Nie mozna policzyc cial: "..tostring(err));return false,err end
            return true
        end,
        stop=stop,
        active=function() return active~=nil end,
    }
end
return L