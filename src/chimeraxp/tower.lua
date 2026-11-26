-- ChimeraXP: Kregi Shoona, server-driven exploration and opt-in ascent.
local T={}
local DIRECTIONS={
    polnoc="n",poludnie="s",wschod="e",zachod="w",
    ["polnocny-wschod"]="ne",["polnocny-zachod"]="nw",
    ["poludniowy-wschod"]="se",["poludniowy-zachod"]="sw",
    gora="u",dol="d",
}
local COLORS={ start={96,165,250}, ["return"]={147,197,253},
    inactive={253,186,116}, active={134,239,172} }
local ENV={start=61001,["return"]=61001,inactive=61002,active=61003}
local DEFAULT_LOOT={"zlote monety","mithrylowe monety","kamienie","szkatulki"}
local function trim(s) return tostring(s or ""):gsub("^%s+",""):gsub("%s+$","") end
local function tower_info(r)
    if not r or type(r.area)~="string" then return end
    local level,seed=r.area:match("^Kregi Shoona, poziom (%d+) #(%S+)$")
    if not level or not seed or type(r.area_id)~="string" or r.area_id=="" then return end
    return tonumber(level),seed
end
local function friendly(e,group)
    local id=tostring(e.id or "")
    return e.relation=="self" or e.relation=="ally" or e.relation=="group"
        or e.group_role=="leader" or e.group_role=="member" or group[id]
end
local function path(rooms,origin,destination)
    if origin==destination then return {} end
    local queue,seen,first={origin},{[origin]=true},{}
    local index=1
    while index<=#queue do
        local from=queue[index];index=index+1
        local node=rooms[from]
        local ordered={}
        for direction,target in pairs(node and node.exits or {}) do
            if rooms[target] and rooms[target].visited then
                ordered[#ordered+1]={direction=direction,target=target}
            end
        end
        table.sort(ordered,function(a,b) return a.direction<b.direction end)
        for _,edge in ipairs(ordered) do
            if not seen[edge.target] then
                seen[edge.target]=true
                first[edge.target]={from=from,direction=edge.direction}
                if edge.target==destination then
                    local reversed={};local current=destination
                    while current~=origin do
                        local entry=first[current]
                        if not entry then return end
                        table.insert(reversed,1,{from=entry.from,dir=entry.direction,to=current})
                        current=entry.from
                    end
                    return reversed
                end
                queue[#queue+1]=edge.target
            end
        end
    end
end
-- Select a frontier by shortest *confirmed* path, not by a stale Mudlet map stub.
local function frontier(rooms,current)
    local best
    for origin,node in pairs(rooms) do
        if node.visited and (node.cleared or node.deferred) then
            for dir,target in pairs(node.exits) do
                if type(target)=="string" and target~="" and not rooms[target]
                    and not (node.blocked and node.blocked[dir]) then
                    local route=path(rooms,current,origin)
                    if route then
                        local candidate={origin=origin,direction=dir,target=target,steps=#route}
                        if not best or candidate.steps<best.steps
                            or (candidate.steps==best.steps and
                                (candidate.origin..candidate.direction)<(best.origin..best.direction)) then
                            best=candidate
                        end
                    end
                end
            end
        end
    end
    return best
end

function T.new(ctx,patrol_status,integration,changed,Loot)
    local gmcp_api,mapper,walker=ctx:use("gmcp"),ctx:use("mapper"),ctx:use("walker")
    local config=ctx:saved("tower",{})
    if type(config)~="table" then config={} end
    if type(config.loot)~="table" then config.loot=DEFAULT_LOOT end
    config.retreat=tonumber(config.retreat) or 35
    config.returnHP=tonumber(config.returnHP) or 85
    config.limit=tonumber(config.limit) or 8
    config.delay=tonumber(config.delay) or 0.7
    -- Tower and classic patrol have independent group-focus settings.
    -- Existing Tower sessions have always sent a group attack order.
    if type(config.partyAttack)~="boolean" then config.partyAttack=true end
    config.autoAscent=config.autoAscent==true
    -- Small persistent history of scores issued by the server, not a local
    -- estimate from the number of mobs or a guessed boss threshold.
    if type(config.results)~="table" then config.results={} end
    local run,ours,stop_walk,deleted=nil,false,false,false
    -- Entrance verification is independent of the active explorer. Never
    -- trust an exact room title: the game changes its phrasing between floors.
    local start_pending, start_verified, begin_entry, auto_advance, poll_transition, queue
    local session
    local function notify() if changed then changed() end end
    local function message(msg,warn)
        if warn then ctx.log.warn("[Wieza] "..msg)
        else ctx.log.info("[Wieza] "..msg) end
        notify()
    end
    local function persist() ctx:save("tower",config) end
    local function cancel(r)
        if r and r.timer then ctx:cancel(r.timer);r.timer=nil end
    end
    local function cancel_start_pending()
        if start_pending and start_pending.timer then
            ctx:cancel(start_pending.timer)
        end
        start_pending=nil
    end
    local function timer(r,seconds,callback)
        cancel(r)
        r.timer=ctx:timer(seconds,function()
            r.timer=nil
            if run==r and r.started and not r.paused then callback() end
        end)
    end
    local function current() return gmcp_api.room() end
    local function this_floor(r)
        local level=tower_info(r)
        return run and level==run.level and r.area_id==run.area_id
    end
    local function recorded_score(area_id)
        if not area_id then return end
        for i=#config.results,1,-1 do
            local rec=config.results[i]
            if type(rec)=="table" and rec.area_id==area_id then return rec end
        end
    end
    local function session_floor(a)
        if not session or not a then return end
        local row=session.by_area[a.area_id]
        if not row then
            row={area_id=a.area_id,level=a.level}
            session.by_area[a.area_id]=row
            session.rows[#session.rows+1]=row
        end
        return row
    end
    local function session_totals()
        local floors,points,missing=0,0,0
        for _,row in ipairs(session and session.rows or {}) do
            if row.finished then floors=floors+1 end
            if row.score then points=points+row.score.gained
            elseif row.finished then missing=missing+1 end
        end
        return floors,points,missing
    end
    local function report_session()
        local floors,points,missing=session_totals()
        local rows={}
        for _,row in ipairs(session and session.rows or {}) do
            if row.finished or row.score then
                rows[#rows+1]={"Poziom "..row.level,row.score and
                    ("+"..row.score.gained.." pkt | razem "..row.score.total) or "brak nowego wyniku serwera"}
            end
        end
        rows[#rows+1]={"Pietra zakonczone",tostring(floors)}
        rows[#rows+1]={"Punkty w sesji","+"..points..(missing>0 and " (niepelne dane)" or "")}
        ctx:report("ChimeraXP | Wieza - sesja",rows)
    end
    local function score_text(rec)
        if not rec then return "punktacja: brak komunikatu serwera" end
        return "poziom "..rec.level..": +"..rec.gained.." pkt Kregow (razem "..rec.total..")"
    end
    local function record_score(level,gained,total)
        local r=current()
        local actual_level,seed=tower_info(r)
        level,gained,total=tonumber(level),tonumber(gained),tonumber(total)
        -- Ignore stale/foreign lines and refuse to infer totals ourselves.
        if not r or not actual_level or actual_level~=level or not gained or not total
            or gained<0 or total<0 or gained>total then return end
        local prior=recorded_score(r.area_id)
        if prior then
            if prior.level~=level then return end
            if prior.gained==gained and prior.total==total then
                if run and this_floor(r) then
                    run.score=prior;run.server_clear=true
                end
                return
            end
            prior.gained,prior.total=gained,total
        else
            prior={area_id=r.area_id,level=level,seed=seed,gained=gained,total=total,
                at=os.time()}
            config.results[#config.results+1]=prior
            while #config.results>50 do table.remove(config.results,1) end
        end
        if run and this_floor(r) then
            run.score=prior
            run.server_clear=true
            local row=session_floor(run)
            if row then row.score=prior end
            if queue then queue(0) end
        end
        persist()
        message("Serwer: "..score_text(prior))
    end
    local function report_score(rec,title)
        ctx:report(title or "ChimeraXP | Wieza - punkty",{
            {"Poziom",rec and tostring(rec.level) or "-"},
            {"Punkty zdobyte",rec and ("+"..rec.gained) or "brak komunikatu"},
            {"Punkty razem",rec and tostring(rec.total) or "brak komunikatu"}
        })
    end
    local function map_id(id)
        local number=type(getRoomIDbyHash)=="function" and getRoomIDbyHash(id)
        if type(number)~="number" or number<=0 then return end
        if type(getRoomHashByID)=="function" and getRoomHashByID(number)~=id then return end
        return number
    end
    local function paint(id,kind)
        if not run then return end
        local number,color,env=map_id(id),COLORS[kind],ENV[kind]
        if not number or not color then return end
        if type(setRoomEnv)=="function" and type(setCustomEnvColor)=="function" then
            setCustomEnvColor(env,color[1],color[2],color[3],255)
            setRoomEnv(number,env)
            if type(updateMap)=="function" then updateMap() end
        elseif type(highlightRoom)=="function" then
            highlightRoom(number,color[1],color[2],color[3],color[1],color[2],color[3],0.85,180,0)
        end
    end
    local function paint_start()
        if run then paint(run.safe,"start") end
    end
    local function marks()
        if not run or not this_floor(current()) then return end
        for id,node in pairs(run.rooms) do
            if id~=run.safe and node.mosaic and COLORS[node.mosaic] then paint(id,node.mosaic) end
        end
        paint_start()
    end
    local function clear_marks(r)
        -- Real room colours survive STOP and manual movement. Official mapper
        -- deletes old generated rooms on a new area_id.
        if type(setRoomEnv)=="function" and type(setCustomEnvColor)=="function" then return end
        if not r or type(unHighlightRoom)~="function" then return end
        for id,node in pairs(r.rooms) do
            if id==r.safe or node.mosaic then
                local number=map_id(id)
                if number then unHighlightRoom(number) end
            end
        end
    end
    local function observe(r)
        if not this_floor(r) then return end
        local node=run.rooms[r.id]
        if not node then
            node={visited=true,cleared=false,scanned=false,exits={},blocked={}}
            run.rooms[r.id]=node
        end
        node.visited=true
        if type(r.exits)=="table" then
            node.exits={}
            for dir,id in pairs(r.exits) do
                if type(dir)=="string" and type(id)=="string" and id~="" then
                    node.exits[dir]=id
                end
            end
        end
    end
    local loot
    local evaluate
    queue=function(delay)
        if not run or not run.started or run.paused or run.pending or run.moving or run.transition then return end
        if run.timer then return end
        local r=run
        timer(r,delay or 0,function() evaluate() end)
    end
    local function pause(reason)
        if not run or run.paused or not run.started then return end
        local r=run
        cancel(r)
        loot.stop()
        r.pending=nil
        r.transition=nil
        cancel_start_pending()
        if r.moving and r.moving.kind=="walk" then
            stop_walk=true;walker.stop("Wieza: pauza");stop_walk=false
        end
        r.moving=nil
        r.paused=true;r.phase="PAUSED";r.reason=reason
        message("WSTRZYMANA: "..reason,true)
    end
    local function stop(reason)
        if start_pending then
            cancel_start_pending()
            if not run then
                message(reason or "Anulowano sprawdzanie mozaiki wejściowej.")
                return
            end
        end
        if not run then return end
        local r=run
        cancel(r)
        loot.stop()
        r.started=false;r.paused=false
        if r.moving and r.moving.kind=="walk" then
            stop_walk=true;walker.stop("Wieza: stop");stop_walk=false
        end
        clear_marks(r)
        run=nil
        if session then report_session() end
        message(reason or "Zatrzymano")
    end
    local function valid_entities(r)
        local pack=gmcp_api.entities()
        return run and run.entities_confirmed and type(pack)=="table"
            and pack.room==r.id and type(pack.entities)=="table"
    end
    local function health()
        local vitals=gmcp_api.vitals()
        local hp=vitals and tonumber(vitals.hp)
        if not hp or hp<0 or hp>100 then return end
        local group=gmcp_api.group()
        if type(group)~="table" or type(group.members)~="table" then return end
        local weakest=hp
        for _,member in ipairs(group.members) do
            if member.here==1 or member.here==true then
                local value,max=tonumber(member.hp),tonumber(member.maxhp)
                if not value or not max or max<=0 then return end
                weakest=math.min(weakest,100*value/max)
            end
        end
        return weakest
    end
    local function enemies(r)
        local group=gmcp_api.group() or {}
        local own={}
        for _,member in ipairs(group.members or {}) do
            own[tostring(member.id or "")]=true
        end
        local result={}
        for _,entity in ipairs(gmcp_api.entities().entities or {}) do
            if entity.kind=="npc"
                -- Tower creatures are neutral until explicitly attacked.
                -- Exclude group/allies/players; accept hostile or neutral NPCs.
                and (entity.relation=="hostile" or entity.relation=="neutral")
                and not friendly(entity,own) and entity.dead~=true and entity.dead~=1
                and type(entity.id)=="string" and entity.id~="" then
                result[#result+1]=entity
            end
        end
        table.sort(result,function(a,b)
            local ah=(tonumber(a.maxhp) or 0)>0 and (tonumber(a.hp) or 0)/a.maxhp or 1
            local bh=(tonumber(b.maxhp) or 0)>0 and (tonumber(b.hp) or 0)/b.maxhp or 1
            if ah~=bh then return ah<bh end
            return a.id<b.id
        end)
        return result,own
    end
    local function combat(r)
        local state=gmcp_api.combat()
        if not state or state.room~=r.id or type(state.relations)~="table" then return end
        return #state.relations>0,state
    end
    local function send_own(cmd,as_alias)
        ours=true
        local ok,err=pcall(ctx.send,ctx,cmd,as_alias)
        ours=false
        if not ok then pause("Nie udalo sie wyslac '"..cmd.."': "..tostring(err));return false end
        return true
    end
    local function send_step(dir,target,purpose)
        local r=current()
        if not r or type(r.exits)~="table" or r.exits[dir]~=target then
            pause("Wyjscie zmienilo sie przed krokiem");return
        end
        local command=DIRECTIONS[dir] or dir
        run.moving={kind="step",origin=r.id,target=target,command=command,purpose=purpose}
        run.phase=purpose=="retreat" and "RETREAT" or "EXPLORING"
        local owner=run
        timer(owner,7,function()
            if owner.moving and owner.moving.kind=="step" then
                pause("Brak potwierdzenia kroku: "..command)
            end
        end)
        send_own(command)
    end
    local function walk_to(target,purpose)
        local r=current()
        local map=map_id(target)
        if not r or not map or not mapper.current_room()
            or map_id(r.id)~=mapper.current_room() then
            pause("Mapper nie potwierdza pozycji lub celu");return
        end
        if r.id==target then queue(0);return end
        -- Do not let the native shortest path take a shortcut through an
        -- unvisited room. Only our explicit frontier steps may do that.
        if type(getPath)~="function" or not getPath(map_id(r.id),map)
            or type(speedWalkPath)~="table" or #speedWalkPath==0 then
            pause("Nie mozna wyznaczyc trasy po odwiedzonych pokojach");return
        end
        for _,number in ipairs(speedWalkPath) do
            local hash=type(getRoomHashByID)=="function" and getRoomHashByID(tonumber(number))
            if not hash or not run.rooms[hash] or not run.rooms[hash].visited then
                pause("Chodzik planuje skrot przez niezbadany pokoj. Zatrzymuje nawigacje.");return
            end
        end
        -- A native walker finishes from inside the mapper's room.changed
        -- callback. Its arrived event can precede OUR room.changed callback,
        -- so retain one confirmed-arrival token for that event.
        run.walk_arrival=nil
        run.moving={kind="walk",origin=r.id,target=target,map=map,purpose=purpose,
            seen_final_room=false}
        run.phase=purpose=="retreat" and "RETREAT" or "MOVING"
        local ok,why=walker.go(map)
        if not ok then
            run.moving=nil
            pause("Chodzik: "..tostring(why));return
        end
        if ok=="tutaj" then run.moving=nil;queue(0);return end
        -- Watchdog resets whenever the official walker confirms another room.
        local owner=run
        if owner.moving and owner.moving.kind=="walk" then
            timer(owner,20,function()
                if owner.moving and owner.moving.kind=="walk" then pause("Chodzik nie zrobil postepu przez 20 s") end
            end)
        end
    end
    local function start_mosaic(verify)
        local r=current()
        run.pending={kind="mosaic",room=r.id,verify=verify}
        run.phase=verify and "VERIFY_EXIT" or "MOSAIC"
        local owner=run
        timer(owner,5,function()
            if owner.pending and owner.pending.kind=="mosaic" then
                pause("Brak odpowiedzi na 'ob mozaike'")
            end
        end)
        send_own("ob mozaike")
    end
    local function mosaic_answer(kind)
        if start_pending then
            local pending=start_pending
            local here=current()
            if not here or here.id~=pending.room or here.area_id~=pending.area_id
                or tower_info(here)~=pending.level then
                cancel_start_pending()
                message("Nie moge potwierdzic mozaiki: zmieniono pokoj lub pietro.",true)
                return
            end
            cancel_start_pending()
            if kind=="return" then
                start_verified(pending)
            else
                message("Start wymaga mozaiki POWROTNEJ. Odpowiedz 'ob mozaike': "..kind..".",true)
            end
            return
        end
        local r=run
        if not r or not r.started or r.paused or not r.pending
            or r.pending.kind~="mosaic" or not current()
            or current().id~=r.pending.room then return end
        local verify=r.pending.verify
        cancel(r);r.pending=nil
        local node=r.rooms[current().id]
        if not node then return pause("Nieznany pokoj mozaiki") end
        node.scanned=true
        node.mosaic=kind~="none" and kind or nil
        if kind=="return" and current().id~=r.safe then
            return pause("Mozaika powrotna poza pokojem startowym")
        elseif (kind=="active" or kind=="inactive") and current().id==r.safe then
            return pause("Mozaika wyjsciowa w pokoju startowym")
        elseif kind=="active" or kind=="inactive" then
            if r.exit and r.exit~=current().id then
                return pause("Wykryto wiecej niz jedna mozaike wyjsciowa")
            end
            r.exit=current().id
            if kind=="active" then r.exit_ready=true;node.deferred=nil end
        end
        if kind=="return" and current().id==r.safe then paint_start()
        elseif kind=="active" or kind=="inactive" then paint(current().id,kind) end
        -- The known entrance is a safe lock; no reason to count or loot it.
        if kind=="return" and current().id==r.safe then node.cleared=true end
        if verify then
            if kind=="active" and r.exit==current().id then
                local fighting=combat(current())
                if fighting~=false or not valid_entities(current()) then queue(0);return end
                r.done=true;r.phase="COMPLETE";r.reason="Mozaika aktywna"
                local row=session_floor(r)
                if row then row.finished=true end
                report_score(r.score,"ChimeraXP | Wieza - koniec pietra")
                report_session()
                if config.autoAscent then auto_advance(r)
                else
                    r.started=false
                    message("Mozaika aktywna; "..score_text(r.score)..
                        ". Przejdz recznie: stan na mozaice.")
                end
            else
                pause("Mozaika nie jest aktywna mimo zamknietej eksploracji. Sprawdz przejscia.")
            end
            return
        end
        queue(0)
    end
    local function begin_loot(node,r)
        run.pending={kind="loot",room=r.id}
        run.phase="LOOTING"
        local owner=run
        local ok,why=loot.start(r.id,config.loot,config.delay,function()
            if run~=owner or not owner.started or owner.paused then return end
            owner.pending=nil
            node.cleared=true
            node.loot_due=false
            owner.phase="READY"
            queue(0)
        end,function(reason)
            if run==owner then pause("Zbieranie: "..reason) end
        end)
        if not ok then
            run.pending=nil
            pause("Zbieranie: "..tostring(why))
        end
    end
    local function attack(r,enemies_list,combat_state,in_combat)
        local best=enemies_list[1]
        local active_target
        local group=gmcp_api.group() or {}
        for _,member in ipairs(group.members or {}) do
            if member.self==1 or member.self==true then
                for _,rel in ipairs(combat_state and combat_state.relations or {}) do
                    if rel.attacker==member.id then active_target=tostring(rel.defender) end
                end
            end
        end
        local actual
        for _,e in ipairs(enemies_list) do if e.id==active_target then actual=e;break end end
        if actual then
            -- Shield interception: keep the confirmed target instead of spamming 'zabij'.
            run.pending_attack=nil
            run.phase="COMBAT"
            return
        end
        if run.pending_attack and run.pending_attack.room==r.id then
            local pending=run.pending_attack
            if os.time()-pending.at<4 then
                run.phase="ENGAGING";queue(1);return
            end
            run.pending_attack=nil
            if not in_combat then
                pause("Niepotwierdzony atak na "..pending.id);return
            end
        end
        run.pending_attack={room=r.id,id=best.id,at=os.time()}
        run.phase=in_combat and "COMBAT" or "ENGAGING"
        if not send_own("zabij "..best.id,true) then return end
        local group_members=group.members or {}
        local me
        for _,member in ipairs(group_members) do if member.self==1 or member.self==true then me=member.id end end
        if me and tostring(group.leader)==tostring(me) then
            local others=0
            for _,member in ipairs(group_members) do
                if member.id and member.id~=me and (member.here==1 or member.here==true) then others=others+1 end
            end
            if others>0 and config.partyAttack then
                send_own("rozkaz druzynie zaatakowac "..best.id,true)
            end
        end
        queue(1)
    end
    local function route_to_safe(r,in_combat)
        if r.id==run.safe then return end
        local route=path(run.rooms,r.id,run.safe)
        if not route or #route==0 then pause("ALARM HP: brak potwierdzonej drogi do komnaty startowej");return end
        if in_combat then
            local step=route[1]
            send_step(step.dir,step.to,"retreat")
        else
            walk_to(run.safe,"retreat")
        end
    end
    evaluate=function()
        local a=run
        if deleted or not a or not a.started or a.paused or a.pending or a.transition then return end
        local r=current()
        if not r or not this_floor(r) then pause("Zmiana pietra lub losowania; nie kontynuuje automatycznie");return end
        if not map_id(r.id) or map_id(r.id)~=mapper.current_room() then
            pause("Pozycja GMCP nie zgadza sie z mapperem");return
        end
        observe(r)
        if not valid_entities(r) then
            a.phase="WAIT_ENTITIES"
            a.entities_wait=a.entities_wait or os.time()
            if os.time()-a.entities_wait>=6 then
                pause("Brak swiezych Chimera.Room.Entities")
            else queue(1) end
            return
        end
        a.entities_wait=nil
        local in_combat,combat_state=combat(r)
        if in_combat==nil then
            a.phase="WAIT_COMBAT"
            a.combat_wait=a.combat_wait or os.time()
            if os.time()-a.combat_wait>=6 then pause("Brak zgodnych z pokojem danych Combat.State")
            else queue(1) end
            return
        end
        a.combat_wait=nil
        local hp=health()
        if not hp then pause("Brak poprawnych danych HP druzyny");return end
        if hp<=config.retreat and not a.retreat then
            a.retreat=true
            if r.id~=a.safe then
                a.retreat_counts=a.retreat_counts or {}
                local attempts=(a.retreat_counts[r.id] or 0)+1
                a.retreat_counts[r.id]=attempts
                if attempts>2 then
                    pause("Powtarzajacy sie krytyczny HP w tym samym pokoju; dalsza proba wymaga interwencji")
                    return
                end
            end
        end
        if a.retreat then
            if a.moving then
                if a.moving.kind=="walk" then
                    stop_walk=true;walker.stop("Wieza: niski HP");stop_walk=false
                end
                a.moving=nil
            end
            if r.id~=a.safe then
                a.phase="RETREAT"
                route_to_safe(r,in_combat)
                return
            end
            if in_combat then pause("ALARM: walka w komnacie bezpiecznej");return end
            if hp<config.returnHP then
                a.phase="RECOVERY";queue(3);return
            end
            a.retreat=false;a.pending_attack=nil
            message("Druzyna zregenerowana; wracam do eksploracji.")
        end
        if a.moving then return end
        local enemies_list=enemies(r)
        local node=a.rooms[r.id]
        -- Inspect before initiating combat; active attacks and HP take priority.
        if not node.scanned and not in_combat then start_mosaic(false);return end
        local hostile=false
        for _,e in ipairs(enemies_list) do if e.relation=="hostile" then hostile=true end end
        local quota_met=a.remaining==0 or a.server_clear or a.exit_ready
        local defer_guardian=r.id==a.exit and not quota_met and not a.guardian_force
            and not in_combat and not hostile and #enemies_list>0
        local exit_priority=a.exit and quota_met and not in_combat and not hostile
            and not a.pending_attack and (r.id~=a.exit or a.exit_ready)
        if defer_guardian then
            node.deferred=true;node.cleared=false
        elseif #enemies_list>0 and not exit_priority then
            node.deferred=nil
        end
        if #enemies_list>config.limit and not defer_guardian and not exit_priority then
            pause("Zbyt wielu przeciwnikow ("..#enemies_list.."/"..config.limit.."). Zwieksz /exp wieza limit lub interweniuj.")
            return
        end
        if #enemies_list>0 and not defer_guardian and not exit_priority then
            if r.id==a.safe then pause("Przeciwnicy w bezpiecznej komnacie startowej");return end
            a.rooms[r.id].cleared=false
            -- Only rooms containing a hostile encounter can need corpse/ground
            -- collection. Empty corridor scans must not issue 'policz ciala'.
            a.rooms[r.id].loot_due=true
            a.post_combat_at=nil
            attack(r,enemies_list,combat_state,in_combat)
            return
        end
        if in_combat then
            a.phase="COMBAT"
            queue(1)
            return
        end
        if a.pending_attack then
            if os.time()-a.pending_attack.at<4 then queue(1);return end
            a.pending_attack=nil
        end
        if not node.scanned then start_mosaic(false);return end
        if not node.cleared and not defer_guardian and (not exit_priority or node.loot_due) then
            if not node.loot_due then
                -- No detected hostile, combat or party kill: clean room,
                -- without counting corpses or sending any loot commands.
                node.cleared=#enemies_list==0
                a.phase="READY"
                queue(0)
                return
            end
            if a.last_combat==r.id and not a.post_combat_at then
                a.post_combat_at=os.time()+2
            end
            if a.post_combat_at and os.time()<a.post_combat_at then
                a.phase="POST_COMBAT";queue(2);return
            end
            a.post_combat_at=nil
            begin_loot(node,r)
            return
        end
        if r.id==a.safe and hp<config.returnHP then
            a.phase="RECOVERY";queue(3);return
        end
        if a.exit and quota_met then
            if r.id~=a.exit then walk_to(a.exit,"exit");return end
            if a.exit_ready or #enemies_list==0 then start_mosaic(true);return end
        end
        -- A known intermediate walker room may have been crossed without
        -- inspection. Return and clear it before declaring this floor done.
        local candidate=frontier(a.rooms,r.id)
        local nearest_unprocessed
        for id,node in pairs(a.rooms) do
            if id~=r.id and node.visited and not node.cleared and not node.deferred then
                local route=path(a.rooms,r.id,id)
                if route and (not nearest_unprocessed or #route<nearest_unprocessed.steps
                    or (#route==nearest_unprocessed.steps and id<nearest_unprocessed.target)) then
                    nearest_unprocessed={target=id,steps=#route}
                end
            end
        end
        if nearest_unprocessed and (not candidate or nearest_unprocessed.steps<=candidate.steps) then
            walk_to(nearest_unprocessed.target,"revisit")
            return
        end
        if candidate then
            if r.id==candidate.origin then
                a.phase="EXPLORING"
                send_step(candidate.direction,candidate.target,"frontier")
            else
                walk_to(candidate.origin,"frontier")
            end
            return
        end
        -- If no other reachable room remains, revisit the deferred guardian.
        if a.exit and a.rooms[a.exit].deferred then
            a.guardian_force=true
            if r.id~=a.exit then walk_to(a.exit,"guardian") else queue(0) end
            return
        end
        -- No reachable frontier left: only the *server* can confirm completion.
        if not a.exit then
            pause("Nie znalazlam mozaiki wyjsciowej. Sprawdz ukryte/niedostepne przejscia.")
        elseif r.id~=a.exit then
            walk_to(a.exit,"exit")
        else
            start_mosaic(true)
        end
    end
    loot=Loot.new(ctx,gmcp_api,message)
    local function status()
        local a=run
        if not a then return {started=false,paused=false,phase="OFF",defensive_only=true,partyAttack=false} end
        local rooms,cleared=0,0
        for _,n in pairs(a.rooms) do rooms=rooms+1;if n.cleared then cleared=cleared+1 end end
        return {started=a.started,paused=a.paused,phase=a.phase,defensive_only=
            not a.started or a.paused or (a.phase~="COMBAT" and a.phase~="ENGAGING"),
            partyAttack=config.partyAttack,level=a.level,area_id=a.area_id,rooms=rooms,cleared=cleared,
            exit=a.exit,mosaic=a.exit and a.rooms[a.exit] and a.rooms[a.exit].mosaic,
            safe=a.safe,reason=a.reason,done=a.done or false,
            score=a.score,server_clear=a.server_clear or false,
            exit_ready=a.exit_ready or false,remaining=a.remaining,autoAscent=config.autoAscent,
            session_points=select(2,session_totals())}
    end
    local function print_status()
        local s=status()
        ctx:report("ChimeraXP | Wieza",{
            {"Stan",s.phase},{"Poziom",tostring(s.level or "-")},
            {"Odkryte",tostring(s.rooms or 0)},{"Oczyszczone",tostring(s.cleared or 0)},
            {"Mozaika",tostring(s.mosaic or "nieodkryta")},
            {"Przejscie odblokowane",s.exit_ready and "TAK (komunikat serwera)" or "niepotwierdzone"},
            {"Wynik serwera",score_text(s.score)},
            {"Start (GMCP)",tostring(s.safe or "-")},
            {"Powod",tostring(s.reason or "-")},
            {"HP odwrot/powrot",config.retreat.."% / "..config.returnHP.."%"},
            {"Limit przeciwnikow",tostring(config.limit)},
            {"Lupy",table.concat(config.loot,", ")},
            {"Istoty do pokonania",s.remaining~=nil and tostring(s.remaining) or "brak komunikatu"},
            {"Automatyczny awans",config.autoAscent and "WL." or "WYL."},
            {"Punkty w sesji","+"..select(2,session_totals())}
        })
    end
    local function print_score()
        local r=current()
        local rec=recorded_score(r and r.area_id)
            or config.results[#config.results]
        report_score(rec)
    end
    local function print_score_history()
        local rows={}
        for i=#config.results,math.max(1,#config.results-9),-1 do
            local rec=config.results[i]
            rows[#rows+1]={tostring(rec.level),score_text(rec)}
        end
        if #rows==0 then rows={{"Wyniki","Brak zapisanych wynikow"}} end
        ctx:report("ChimeraXP | Wieza - historia",rows)
    end
    start_verified=function(pending)
        local r=current()
        if not r or r.id~=pending.room or r.area_id~=pending.area_id then
            message("Zmiana lokacji podczas potwierdzania startu.",true)
            return
        end
        run={started=true,paused=false,phase="READY",level=pending.level,seed=pending.seed,
            area_id=pending.area_id,safe=r.id,rooms={},exit=nil,entities_confirmed=true,kills=0,
            score=recorded_score(pending.area_id)}
        observe(r)
        local node=run.rooms[r.id]
        node.scanned=true
        node.mosaic="return"
        node.cleared=true
        paint_start()
        message("Potwierdzona mozaika powrotna. Poziom "..run.level..
            ". Rozpoczynam eksploracje; NIE przejde automatycznie dalej.")
        queue(0)
    end
    local function start()
        if run and run.started then message("Wieza dziala lub jest w pauzie; uzyj /exp wieza wznow albo stop.",true);return false end
        if start_pending then message("Juz sprawdzam mozaike wejscia; czekam na odpowiedz.",true);return false end
        if run and run.done then clear_marks(run);run=nil end
        if patrol_status().started then message("Najpierw zatrzymaj klasyczny EXP.",true);return false end
        local r=current()
        local level,seed=tower_info(r)
        if not level or not r or not r.id then message("Nie jestes w Kregach Shoona.",true);return false end
        if not gmcp_api.connected() or not map_id(r.id) or map_id(r.id)~=mapper.current_room() then
            message("Brak potwierdzenia GMCP i mappera.",true);return false
        end
        if not gmcp_api.combat() or not gmcp_api.group() or not gmcp_api.vitals() then
            message("Czekam na dane walki, druzyny i HP.",true);return false
        end
        local packet=gmcp_api.entities()
        if not packet or packet.room~=r.id or type(packet.entities)~="table" then
            message("Brak aktualnego Room.Entities - odswiez lokacje.",true);return false
        end
        local reason=integration and integration.check and integration.check({economy={enabled=true},loot=config.loot})
        if reason then message(reason,true);return false end
        -- A return mosaic is the only reliable evidence of the entrance.
        -- Verify its live server response BEFORE assigning the safe lock.
        local pending={room=r.id,area_id=r.area_id,level=level,seed=seed}
        start_pending=pending
        pending.timer=ctx:timer(5,function()
            if start_pending==pending then
                cancel_start_pending()
                message("Brak odpowiedzi na 'ob mozaike' (5 s). Start anulowany.",true)
            end
        end)
        message("Sprawdzam mozaike powrotna przed uruchomieniem...")
        local ok,err=pcall(ctx.send,ctx,"ob mozaike")
        if not ok then
            if start_pending==pending then cancel_start_pending() end
            message("Nie udalo sie sprawdzic mozaiki: "..tostring(err),true)
            return false
        end
        return true
    end
    local function resume()
        if not run or not run.started or not run.paused then
            message("Brak wstrzymanej eksploracji.",true);return false
        end
        if not this_floor(current()) then
            message("Nie mozna wznowic: zmienila sie instancja lub poziom.",true);return false
        end
        if patrol_status().started then message("Zatrzymaj klasyczny EXP.",true);return false end
        local reason=integration and integration.check and integration.check({economy={enabled=true},loot=config.loot})
        if reason then message(reason,true);return false end
        run.paused=false;run.phase="READY";run.reason=nil
        run.entities_confirmed=(gmcp_api.entities() or {}).room==current().id
        run.pending_attack=nil;run.post_combat_at=nil
        message("Wznawiam eksploracje.")
        queue(0)
        return true
    end
    local function set_party_attack(value)
        local setting=trim(value):lower()
        if setting~="on" and setting~="off" then
            message("Uzycie: /exp druzyna on lub /exp druzyna off.",true)
            return false
        end
        config.partyAttack=setting=="on"
        persist()
        message("Wspolny cel ataku "..(config.partyAttack and "WLACZONY" or "WYLACZONY")..
            " (Wieza)")
        return true
    end
    local function edit_loot(action,name)
        if run and run.started and not run.paused then
            message("Zmiana listy lupow wymaga pauzy.",true);return
        end
        if action=="lista" then message("Lupy: "..table.concat(config.loot,", "));return end
        name=trim(name)
        if name=="" or #name>80 or name:find("[;%c]") then
            message("Niepoprawna kategoria lupow.",true);return
        end
        if action=="dodaj" then
            for _,item in ipairs(config.loot) do
                if item:lower()==name:lower() then message("Lup juz jest na liscie.");return end
            end
            config.loot[#config.loot+1]=name
        elseif action=="usun" then
            for i,item in ipairs(config.loot) do
                if item:lower()==name:lower() then table.remove(config.loot,i);break end
            end
        end
        persist();message("Lupy: "..table.concat(config.loot,", "))
    end
    -- No optional args here! Otherwise Mudlet matches BOTH /exp wieza
    -- and /exp wieza start and invokes the action twice.
    ctx:command{"exp wieza",help="Status eksploracji Kregow Shoona",fn=print_status}
    ctx:command{"exp wieza punkty",help="Ostatni zapisany wynik Kregow",fn=print_score}
    ctx:command{"exp wieza historia",help="Historia punktow za poziomy Kregow",fn=print_score_history}
    for _,action in ipairs({"start","pauza","wznow","stop","status"}) do
        local command=action
        ctx:command{"exp wieza "..command,help="Wieza: "..command,fn=function()
            if command=="start" then start()
            elseif command=="pauza" then pause("Pauza uzytkownika")
            elseif command=="wznow" then resume()
            elseif command=="stop" then stop("Zatrzymano recznie")
            else print_status() end
        end}
    end
    for _,action in ipairs({"dodaj","usun","lista"}) do
        local a=action
        ctx:command{"exp wieza lup "..a,args=a=="lista" and nil or "<kategoria>",help="Wieza: lup "..a,
            fn=function(arg) edit_loot(a,arg) end}
    end
    ctx:command{"exp wieza hp",args="<odwrot> <powrot>",help="Progi HP Wiezy (procent)",fn=function(value)
        local a,b=tostring(value or ""):match("^(%d+)%s+(%d+)$")
        a,b=tonumber(a),tonumber(b)
        if not a or not b or a<10 or b>100 or a>=b then
            message("Uzyj /exp wieza hp 35 85 (10 <= odwrot < powrot <= 100).",true);return
        end
        config.retreat,config.returnHP=a,b;persist()
        message("Progi HP: odwrot "..a.."%, powrot "..b.."%.")
    end}
    ctx:command{"exp wieza limit",args="<1..30>",help="Limit przeciwnikow w pokoju",fn=function(value)
        local n=tonumber(value)
        if not n or n%1~=0 or n<1 or n>30 then message("Uzyj /exp wieza limit 8 (1..30).",true);return end
        config.limit=n;persist();message("Limit przeciwnikow: "..n)
    end}
    -- Repaint special rooms after mapper/visited highlights have run.
    -- The timer avoids depending on event listener registration order.
    ctx:on("chimera.mapper.moved",function()
        if not run or not (run.started or run.done) then return end
        local owner=run
        ctx:timer(0.05,function()
            if run==owner and this_floor(current()) then marks() end
        end)
    end)
    ctx:on("chimera.room.entities",function(packet)
        if not run or not run.started or run.paused then return end
        local r=current()
        if r and packet and packet.room==r.id and this_floor(r) then
            run.entities_confirmed=true;queue(0)
        end
    end)
    ctx:on("chimera.room.info",function(r)
        if run and run.started and not run.paused and this_floor(r) then
            observe(r)
        end
    end)
    ctx:on("chimera.room.changed",function(event)
        if start_pending then
            local here=current()
            if not here or here.id~=start_pending.room or here.area_id~=start_pending.area_id then
                cancel_start_pending()
                message("Zmiana pokoju przed potwierdzeniem mozaiki; start anulowany.",true)
            end
        end
        local a=run
        if not a or not a.started or a.paused then return end
        local r=current()
        if not r or not this_floor(r) then
            pause("Opuszczono pietro lub zmienilo sie losowanie.");return
        end
        a.entities_confirmed=false
        a.entities_wait=nil;a.combat_wait=nil
        local moving=a.moving
        if not moving and a.walk_arrival and a.walk_arrival.id==r.id then
            -- The mapper and walker handled this change before our listener.
            -- Consume only the exact, one-shot walker destination.
            a.walk_arrival=nil
            observe(r)
            queue(0)
            return
        end
        a.walk_arrival=nil
        if moving and moving.kind=="step" then
            if r.id~=moving.target then pause("Krok prowadzil do innego pokoju niz GMCP");return end
            cancel(a);a.moving=nil
        elseif moving and moving.kind=="walk" then
            -- Official walker owns intermediate steps; reset watchdog after each.
            if r.id==moving.target then moving.seen_final_room=true end
            cancel(a)
            timer(a,20,function() if a.moving then pause("Chodzik utknal podczas eksploracji") end end)
        else
            pause("Ruch poza kontrola Wiezy. Wznow recznie.");return
        end
        observe(r)
        queue(0)
    end)
    ctx:on("chimera.walk.started",function()
        if run and run.started and not run.paused
            and (not run.moving or run.moving.kind~="walk") then
            pause("Inny chodzik przejal sterowanie")
        end
    end)
    ctx:on("chimera.walk.arrived",function(event)
        local a=run
        if not a or not a.started or a.paused or not a.moving or a.moving.kind~="walk" then return end
        local expected=a.moving
        if not current() or current().id~=expected.target or event.map_room~=expected.map then
            pause("Niepotwierdzone dotarcie chodzika")
            return
        end
        cancel(a);a.moving=nil
        -- The official mapper emits chimera.walk.arrived synchronously inside
        -- chimera.room.changed. At that point, OUR room.changed handler may
        -- not have run yet and must not classify the step as manual.
        if not expected.seen_final_room then
            a.walk_arrival={id=expected.target}
        end
        marks();queue(0)
    end)
    ctx:on("chimera.walk.stopped",function(event)
        local a=run
        if stop_walk or not a or not a.started or a.paused or not a.moving or a.moving.kind~="walk" then return end
        local expected=a.moving
        cancel(a);a.moving=nil
        if current() and current().id==expected.target then
            if not expected.seen_final_room then a.walk_arrival={id=expected.target} end
            queue(0);return
        end
        if event and event.reason=="atak" then
            -- Interrupted in an intermediate room; claim the room-change
            -- callback only when the mapper has already confirmed it.
            local here=current()
            if here and here.id~=expected.origin and not expected.seen_final_room
                and run.rooms[here.id] then a.walk_arrival={id=here.id} end
            queue(0);return
        end
        pause("Chodzik zatrzymany poza celem: "..tostring(event and event.reason or "brak powodu"))
    end)
    ctx:on("chimera.combat.state",function(packet)
        if run and run.started and not run.paused then
            local r=current()
            if r and packet and packet.room==r.id then
                local active=type(packet.relations)=="table" and #packet.relations>0
                if active then
                    run.last_combat=r.id
                    local node=run.rooms[r.id]
                    if node then
                        node.loot_due=true
                        node.cleared=false
                    end
                    if run.pending and run.pending.kind=="loot" then
                        loot.stop();run.pending=nil
                        local node=run.rooms[r.id]
                        if node then node.cleared=false end
                    elseif run.pending and run.pending.kind=="mosaic" then
                        cancel(run);run.pending=nil
                    end
                end
            end
            queue(0)
        end
    end)
    ctx:on("chimera.char.vitals",function()
        if run and run.started and not run.paused then
            local hp=health()
            if hp and hp<=config.retreat then
                run.urgent=true
                -- A native multi-room walk can still be stopped before combat.
                if run.moving and run.moving.kind=="walk" then
                    stop_walk=true;walker.stop("Wieza: niski HP");stop_walk=false
                    cancel(run);run.moving=nil
                end
            end
        end
        queue(0)
    end)
    ctx:on("chimera.group.state",function() queue(0) end)
    ctx:on("chimera.combat.kill",function(kill)
        if run and run.started and not run.paused and current() and kill and kill.room==current().id then
            local group=gmcp_api.group() or {}
            for _,member in ipairs(group.members or {}) do
                if kill.killer and tostring(kill.killer.id)==tostring(member.id) then
                    run.kills=run.kills+1
                    local node=run.rooms[current().id]
                    if node then node.loot_due=true;node.cleared=false end
                    break
                end
            end
        end
    end)
    -- Global text signals are scoped to a GMCP-confirmed tower instance.
    -- Score text: "Poziom 6 jest czysty. Zyskujesz 4 punktow Kregow (razem 14)."
    ctx:trigger([[^Poziom (\d+) jest czysty\. Zyskujesz (\d+) punkt(?:ow|y)? Kregow \(razem (\d+)\)\.$]],function()
        local m=rawget(_G,"matches")
        if type(m)=="table" then record_score(m[2],m[3],m[4]) end
    end)
    -- This names the guardian's chamber but NOT its map ID. Do not guess a
    -- room, simulate an 80% threshold or trigger "stan na mozaice".
    ctx:trigger([[^Gdzies w komnacie straznika rozjarza sie mozaika przejscia\.$]],function()
        local r=current()
        if not run or not this_floor(r) or run.exit_ready then return end
        run.exit_ready=true
        message("Serwer odblokowal mozaike przejscia w komnacie straznika."..
            " Kontynuuje bezpieczna eksploracje; przejscie pozostaje reczne.")
    end)
    ctx:trigger([[^Nie zauwazasz niczego takiego\.$]],function() mosaic_answer("none") end)
    ctx:trigger([[^Mozaika tli sie zimnym blaskiem\.]],function() mosaic_answer("return") end)
    ctx:trigger([[^Krag mozaiki jest martwy\.]],function() mosaic_answer("inactive") end)
    ctx:trigger([[^Krag mozaiki jarzy sie jasno\.]],function() mosaic_answer("active") end)
    ctx:on("chimera.walker.unhighlighted",function() marks() end)
    ctx:on("chimera.session.end",function()
        if start_pending or run then stop("Rozlaczono; wymagany nowy start") end
    end)
    ctx:trigger([[^[ >]*(?:)Umierasz\.$]],function()
        if start_pending or run then stop("Smierc postaci") end
    end)
    ctx:cleanup(function()
        deleted=true
        cancel_start_pending()
        if run then
            cancel(run);loot.stop()
            if run.moving and run.moving.kind=="walk" then
                stop_walk=true;walker.stop("Wieza: przeladowanie");stop_walk=false
            end
        end
    end)
    return {status=status,start=start,pause=pause,resume=resume,stop=stop,
        issuing_attack_order=function() return ours end,
        party_attack_enabled=function()
            return run and run.started and not run.paused and config.partyAttack or false
        end,
        set_party_attack=set_party_attack,
        path=path,frontier=frontier}
end
return T