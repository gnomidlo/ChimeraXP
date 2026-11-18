-- One in-flight maneuver. Every plan is re-evaluated against current GMCP.
local T={}
function T.new(ctx,M,integration,patrol,changed)
    local gmcp=ctx:use("gmcp")
    local api={};for k,v in pairs(gmcp) do api[k]=v end
    api.char=api.char or function() return {} end
    local persisted=ctx:saved("tactics",nil)
    local imported=persisted or integration.migrate_tactics()
    local config=M.defaults(imported or {})
    if not config.self_profile then
        config.self_profile=M.profile_defaults({role=config.role,min_hp=imported and config.min_hp or nil,max_load=imported and config.max_load or nil})
    end
    config.confirmed_minions=type(persisted)=="table" and type(persisted.confirmed_minions)=="table" and persisted.confirmed_minions or {}
    -- Collective commands need live server verification before opt-in.
    if not persisted then config.team_broadcast=false end
    local S={on=false,phase="WYŁĄCZONA",detail="Automatyka po uruchomieniu jest wyłączona.",
        enabled={true,true,true,true},received={},blocked={0,0,0,0},support={0,0,0,0},
        retreat_until=0,last={},transfers={},pending=nil,barrier=0,destroyed=false,sending=false,
        actor_ready_at={},health={},threat=nil}
    local E={}
    local function now() return type(getEpoch)=="function" and getEpoch() or os.time() end
    local function notify() if not S.destroyed and changed then changed() end end
    local function save() ctx:save("tactics",config) end
    local function phase(name,detail) S.phase=name;S.detail=detail;notify() end
    local function actor_ready(id)
        return id and (S.actor_ready_at[id] or 0) or 0
    end
    local function lock_actor(id,t,duration)
        if id then S.actor_ready_at[id]=math.max(actor_ready(id),t+(duration or 15)) end
    end
    local function unlock_actor(id)
        if id then S.actor_ready_at[id]=now() end
    end
    -- Health telemetry remains session-local. A hit is a negative HP delta
    -- observed in live GMCP, not damage inferred from the number of attackers.
    local function observe_health(s,t)
        if not s or not s.members then return end
        for id,member in pairs(s.members) do
            if type(member.hp)=="number" then
                local value=math.max(0,math.min(100,member.hp))
                local h=S.health[id]
                if not h or t<h.at or t-h.at>45 then
                    S.health[id]={hp=value,at=t,hits={}}
                else
                    if value<h.hp then
                        h.hits[#h.hits+1]={at=t,damage=h.hp-value}
                    end
                    h.hp=value;h.at=t
                    local kept={}
                    for _,hit in ipairs(h.hits) do
                        if hit.at>=t-30 then kept[#kept+1]=hit end
                    end
                    h.hits=kept
                end
            end
        end
    end
    local function evaluate_health(s,t)
        local risk,most={},nil
        for id,member in pairs(s.members or {}) do
            local hp=member.hp or 100
            local h=S.health[id];local short,long=0,0
            if h then
                for _,hit in ipairs(h.hits) do
                    if hit.at>=t-5 then short=short+hit.damage end
                    if hit.at>=t-25 then long=long+hit.damage end
                end
            end
            -- Use fixed windows; a pair of near-simultaneous GMCP packets
            -- cannot create an unbounded damage-per-second estimate.
            local rate=math.max(short/5,long/25)
            local eta=rate>0 and math.max(0,(hp-35)/rate) or nil
            local level="stable"
            if hp<=35 or short>=18 or (hp<=80 and eta and eta<=15) then level="critical"
            elseif hp<=55 or short>=8 or (eta and eta<=30) then level="warning" end
            local data={level=level,hp=hp,damage5=short,damage25=long,
                rate=rate,eta=eta,attackers=#(s.attackers[id] or {})}
            risk[id]=data
            if data.attackers>0 and (not most or
                (level=="critical" and most.level~="critical") or
                (level=="warning" and most.level=="stable") or
                (level==most.level and hp<most.hp)) then
                most={id=id,name=member.name,level=level,hp=hp,rate=rate,eta=eta}
            end
        end
        S.threat=most
        return risk
    end
    local function collect_health()
        local s=M.party(api)
        if s then observe_health(s,now()) end
    end
    local function snapshot() return M.snapshot(api) end
    local function display() return snapshot() or M.party(api) end
    local function detect()
        local roster=M.roster(api)
        if not roster then return end
        S.ambiguous=#roster>2
        if S.ambiguous then return end
        local used,dirty={},false
        for _,p in ipairs(config.minions) do
            for _,member in ipairs(roster) do if member.id==p.id then used[p.id]=true end end
        end
        for i,p in ipairs(config.minions) do
            if not used[p.id] then
                local candidate
                for _,member in ipairs(roster) do
                    if not used[member.id] and (not candidate or member.name==p.name) then candidate=member end
                end
                if candidate then
                    p.id,p.name=candidate.id,candidate.name;used[p.id]=true
                    -- A changed slot must never inherit the previous owner's
                    -- 15s maneuver cooldown; those locks follow GMCP IDs.
                    S.blocked[i+1]=0;dirty=true
                    -- Discovery is not an attack attempt. Keep support's
                    -- short command guard separate from maneuver cooldown.
                    S.support[i+1]=math.max(S.support[i+1],now()+1)
                    if S.pending and S.pending.channel==i+1 then S.pending=nil end
                end
            end
        end
        if dirty then save() end
    end
    function E.stop(reason)
        S.on=false;S.pending=nil;S.received={}
        S.barrier=math.max(S.barrier,now()+3)
        phase("WYŁĄCZONA",reason or "Zatrzymano taktykę.")
    end
    function E.toggle(value)
        if S.destroyed then return false end
        if value==false or (value==nil and S.on) then E.stop();return true end
        local reason=integration.check(nil)
        if reason then phase("BLOKADA",reason);return false,reason end
        S.on=true;S.pending=nil;S.barrier=now()+5
        -- The current, room-validated GMCP snapshot is sufficient to start.
        -- Waiting for three *new* packets can stall protection indefinitely.
        local current=snapshot()
        S.received=current and {entities=now(),group=now(),combat=now()} or {}
        collect_health()
        phase("SYNCHRONIZACJA",current and "Oceniam zagrozenia druzyny." or "Czekam na aktualne dane GMCP.")
        return true
    end
    function E.rows()
        local s=display();local rows={}
        if not s then return rows end
        local function add(id)
            local m=s.members[id];local policy=M.policy(s,config,id)
            local ch=id==s.self_id and 1 or 4;local slot
            for i,p in ipairs(config.minions) do if p.id==id then ch=i+1;slot=i end end
            rows[#rows+1]={id=id,name=m.name,kind=m.kind,role=id==s.self_id and config.role or policy.role,
                enabled=policy.enabled and S.enabled[ch],channel=ch,slot=slot,
                min_hp=policy.min_hp,max_load=policy.max_load,task=slot and config.minions[slot].task,
                target_name=policy.target_name,target_id=policy.target_id,
                cooldown=math.max(0,math.ceil(math.max(S.blocked[ch] or 0,actor_ready(id))-now())),
                self=id==s.self_id}
        end
        add(s.self_id)
        local ids={};for id in pairs(s.members) do if id~=s.self_id then ids[#ids+1]=id end end
        table.sort(ids,function(a,b) if s.members[a].name==s.members[b].name then return a<b end return s.members[a].name<s.members[b].name end)
        for _,id in ipairs(ids) do add(id) end
        return rows
    end
    function E.configure(id,key,value,expected)
        if S.destroyed then return false end
        local s=display();local member=s and s.members[id]
        if not member then return false end
        if expected and (member.name~=expected.name or member.kind~=expected.kind) then return false end
        local own=id==s.self_id;local old=own and config.self_profile or config.profiles[id]
        if old and not own and (old.name~=member.name or old.kind~=member.kind) then old=nil end
        local p=M.profile_defaults(old or {name=member.name,kind=member.kind,min_hp=own and config.min_hp or 50,max_load=config.max_load})
        if key=="role" then
            if value~="auto" and not M.labels[value] then return false end
            if own and value=="auto" then return false end
            p.role=value~="auto" and value or nil
            if p.role then p.min_hp=M.presets[p.role].min_hp;p.max_load=M.presets[p.role].max_load end
            if not p.role then p.min_hp=50;p.max_load=config.max_load end
            if own then config.role=value end
        elseif key=="enabled" then p.enabled=value==true
        elseif key=="min_hp" then p.min_hp=math.max(own and 40 or 50,math.min(100,tonumber(value) or p.min_hp))
        elseif key=="max_load" then p.max_load=math.max(0,math.min(5,math.floor(tonumber(value) or p.max_load)))
        elseif key=="target_id" then
            local target=value and s.members[value]
            if value and (not target or value==id) then return false end
            p.target_id=value;p.target_name=target and target.name
            if own then config.protect=value~=nil;config.protect_id=value;config.protect_name=p.target_name end
            for _,pet in ipairs(config.minions) do if pet.id==id then pet.target_id=value;pet.target_name=p.target_name end end
        else return false end
        if own then config.self_profile=p else config.profiles[id]=p end
        for _,row in ipairs(E.rows()) do if row.id==id and key=="enabled" and row.channel<4 then S.enabled[row.channel]=p.enabled end end
        save();notify();return true
    end
    function E.option(key,value)
        if S.destroyed then return false end
        if key=="team_orders" or key=="team_broadcast" or key=="retreat" or key=="mass" then
            config[key]=value==true;save();notify();return true
        end
        return false
    end
    function E.task(id,value,expected)
        if S.destroyed or not M.task_labels[value] then return false end
        local s=display();local member=s and s.members[id]
        if not member or (expected and (member.name~=expected.name or member.kind~=expected.kind)) then return false end
        for _,p in ipairs(config.minions) do if p.id==id then p.task=value;save();notify();return true end end
        return false
    end
    function E.bind(slot,id,expected)
        if S.destroyed or (slot~=1 and slot~=2) then return false end
        local s=display();local member=s and s.minions[id]
        if not member or (expected and (member.name~=expected.name or member.kind~=expected.kind)) then return false end
        if config.minions[3-slot].id==id then return false end
        local pet=config.minions[slot];pet.id=id;pet.name=member.name
        config.confirmed_minions[slot]={id=id,name=member.name}
        S.enabled[slot+1]=false;S.blocked[slot+1]=math.max(S.blocked[slot+1],now()+15)
        save();phase("PRZYPISANO","Pachołek przypisany. Włącz jego udział po sprawdzeniu roli.");return true
    end
    function E.status()
        return {on=S.on,phase=S.phase,detail=S.detail,pending=S.pending and S.pending.kind,
            threat=S.threat,ambiguous=S.ambiguous,team_orders=config.team_orders,
            team_broadcast=config.team_broadcast,retreat=config.retreat,mass=config.mass}
    end
    local function invalid_room()
        S.received={};S.pending=nil;S.health={};S.threat=nil
        if S.on then phase("SYNCHRONIZACJA","Nowa lokacja: czekam na aktualne dane.") end
    end
    local function evaluate()
        if S.destroyed or not S.on then return end
        local reason=integration.check(nil)
        if reason then phase("BLOKADA",reason);return end
        local xp=patrol.status()
        if xp.dry then return end
        local t=now()
        for _,key in ipairs({"entities","group","combat"}) do
            if not S.received[key] then
                phase("SYNCHRONIZACJA","Brak danych: "..key);return
            end
        end
        -- Group and entity packets are event-driven, not heartbeats: an
        -- unchanged roster need not be re-sent every fifteen seconds.
        -- M.snapshot validates all three against the current room.
        local s,err=snapshot()
        if not s then phase("BLOKADA GMCP",err);return end
        observe_health(s,t)
        s.risk=evaluate_health(s,t)
        s.maneuver_locked={}
        for id in pairs(s.members) do
            if actor_ready(id)>t then s.maneuver_locked[id]=true end
        end
        if S.pending then
            local p=S.pending
            if M.confirmed(p,s) then
                S.last[p.channel]=p;S.pending=nil
                for _,enemy in ipairs(p.before_targets or {}) do
                    local target=p.kind=="retreat" and p.protected or p.actor
                    if s.targets[enemy]==target then S.transfers[enemy]={from=p.kind=="retreat" and p.actor or p.protected,until_at=t+12} end
                end
                phase("POTWIERDZONA","Wynik manewru potwierdzony przez dane walki.")
            elseif t-p.sent_at<3 then phase("PRÓBA","Czekam na wynik manewru.")
            else S.pending=nil;phase("NIEPOTWIERDZONA","Brak potwierdzenia; zachowuję odstęp przed kolejną próbą.") end
            return
        end
        -- Emergency protection does not wait for initial idle-sync delay.
        -- Normal orders keep the original five-second safety barrier.
        if t<S.barrier and not (S.threat and S.threat.level=="critical") then return end
        local blocked={math.max(S.blocked[1],actor_ready(s.self_id))>t,
            {cover=math.max(S.blocked[2],actor_ready(config.minions[1].id))>t,
             support=S.support[2]>t},
            {cover=math.max(S.blocked[3],actor_ready(config.minions[2].id))>t,
             support=S.support[3]>t},
            {cover=S.blocked[4]>t,support=S.support[4]>t}}
        if S.ambiguous then
            for i,pet in ipairs(config.minions) do
                local confirmed=config.confirmed_minions[i]
                local current=s.minions[pet.id]
                if not confirmed or confirmed.id~=pet.id or not current or current.name~=confirmed.name then blocked[i+1]=true end
            end
        end
        -- AutoExp already issues the initial party attack order when enabled.
        -- Keep automatic covers, but never duplicate its target alignment.
        local suppress_attack = xp.started and patrol.party_attack_enabled
            and patrol.party_attack_enabled()
        if xp.defensive_only then
            for ch=2,4 do
                if type(blocked[ch])=="table" then blocked[ch].support=true end
            end
            suppress_attack=true
        end
        local d=M.plan(s,config,S.enabled,blocked,nil,suppress_attack)
        if not d then
            local detail=S.ambiguous and "Niejednoznaczne pachołki: wymagane jawne przypisanie do P1/P2."
                or config.team_orders and s.leader~=s.self_id and "Rozkazy graczom czekają: nie prowadzisz drużyny."
                or "Nie potrzeba zmiany szyku."
            local target=s.targets[s.self_id]
            local missing={}
            if target and s.enemies[target] then
                for id,member in pairs(s.members) do
                    if id~=s.self_id and s.targets[id]~=target then missing[#missing+1]=member.name end
                end
            end
            if #missing>0 then
                table.sort(missing)
                local wait=math.ceil(math.max(0,S.blocked[4]-t,S.support[4]-t))
                local why=not config.team_orders and "włącz Rozkazy graczom"
                    or not config.team_broadcast and "włącz Rozkazy zbiorowe"
                    or s.leader~=s.self_id and "nie prowadzisz drużyny"
                    or wait>0 and ("odnowienie/ręczna blokada: "..wait.." s")
                    or "sprawdź udział jednostek, rezerwę i blokady pachołków"
                detail="Inny cel lub brak ataku: "..table.concat(missing,", ").."; "..why.."."
            end
            if S.threat and S.threat.level~="stable" then
                detail=(S.threat.level=="critical" and "ALARM: " or "Uwaga: ")
                    ..S.threat.name.." "..math.floor(S.threat.hp+0.5)
                    .."% HP; brak bezpiecznego manewru lub wykonawcy."
            elseif detail=="Nie potrzeba zmiany szyku." then
                detail="Szyk bezpieczny; monitoruje HP."
            end
            phase("AUTO",detail);return
        end
        for _,enemy in ipairs(d.before_targets or {}) do
            local transfer=S.transfers[enemy];local target=d.kind=="retreat" and d.protected or d.actor
            if transfer and transfer.until_at>t and transfer.from==target and not d.emergency then
                phase("STABILIZACJA","Nie odwracam świeżej zmiany szyku.");return
            end
        end
        -- Commands are built from the same validated room snapshot. No partner
        -- command may race this one for the same enemy or protected unit.
        local command=M.command(d,s)
        if not command then phase("BLOKADA","Nie można zbudować poprawnego rozkazu.");return end
        d.sent_at=t;S.pending=d
        -- A maneuver locks the *actor* for fifteen seconds, never the
        -- command issuer or the slot used to address that actor.
        if d.kind=="team_cover" then
            for _,id in ipairs(d.recipients or {}) do
                if id~=s.self_id then lock_actor(id,t,15) end
            end
        elseif d.kind=="cover" or d.kind=="mass" or d.kind=="retreat" then
            lock_actor(d.actor,t,15)
        elseif d.kind=="support" then
            S.support[d.channel]=t+1 -- command flood guard, not formation CD
        end
        if d.kind=="retreat" then S.retreat_until=t+15 end
        S.sending=true;local ok,problem=pcall(function() ctx:send(command,true) end);S.sending=false
        if not ok then S.pending=nil;S.enabled[d.channel]=false;phase("BŁĄD",tostring(problem));return end
        phase("PRÓBA",d.reason)
    end
    local queued=false
    local function schedule()
        if queued or S.destroyed then return end
        queued=true
        ctx:timer(0.08,function()
            queued=false;if S.destroyed then return end
            local ok,err=pcall(evaluate)
            if not ok then E.stop("Błąd taktyki: "..tostring(err));ctx.log.warn(S.detail) end
        end)
    end
    for _,pair in ipairs({{"entities","chimera.room.entities"},{"group","chimera.group.state"},{"combat","chimera.combat.state"}}) do
        local key,event=pair[1],pair[2]
        ctx:on(event,function()
            S.received[key]=now()
            if key=="entities" or key=="group" then collect_health() end
            detect();schedule();notify()
        end)
    end
    ctx:on("chimera.char.vitals",function() collect_health();schedule() end)
    ctx:on("chimera.room.changed",invalid_room)
    ctx:on("chimera.step.manual",function() if not S.sending then invalid_room() end end)
    ctx:on("chimera.session.end",function() E.stop("Rozłączono. Taktyka pozostaje wyłączona.") end)
    ctx:on("sysDataSendRequest",function(_,command)
        if S.sending or (patrol.issuing_attack_order and patrol.issuing_attack_order()) then return end
        local text=tostring(command or ""):lower():gsub("^%s+","")
        local manual=M.manual(command,snapshot(),config)
        if manual then
            local t=now()
            local focus=manual.kind=="support" or manual.kind=="target"
            if focus then
                -- Attacks/orders have no maneuver cooldown. Only guard
                -- against duplicate commands during the next GMCP frame.
                for ch in pairs(manual.channels) do
                    S.support[ch]=math.max(S.support[ch] or 0,t+1)
                end
            elseif manual.actor then
                lock_actor(manual.actor,t,15)
            elseif manual.group then
                -- A collective cover is performed by the recipients,
                -- never by the character issuing the order.
                local current=snapshot()
                if current then
                    for id in pairs(current.members) do
                        if id~=current.self_id then lock_actor(id,t,15) end
                    end
                end
            else
                -- Unknown target: do not guess; protect both known minions
                -- from conflicting fresh manual commands.
                for i,p in ipairs(config.minions) do
                    if manual.channels[i+1] then lock_actor(p.id,t,15) end
                end
            end
            local pending=S.pending
            if pending then
                local same=(pending.kind=="support" or pending.kind=="team_attack")== focus
                local affected=manual.channels[pending.channel]
                if pending.channel==4 then
                    for i,p in ipairs(config.minions) do
                        for _,id in ipairs(pending.recipients or {}) do
                            if p.id==id and manual.channels[i+1] then affected=true end
                        end
                    end
                end
                if same and affected then S.pending=nil end
            end
            phase("RĘCZNIE",focus and "Ręczny rozkaz ataku/wsparcia: bez odnowienia szyku."
                or "Ręczny rozkaz osłony: czekam na gotowość wykonawcy.")
        elseif text:match("^zaslon%s") or text:match("^wycofaj%s") or text:match("^przelam%s") then
            -- Manual commands never disable automation. Let the server
            -- readiness message clear the maneuver cooldown early.
            if text:match("^wycofaj%s") then S.retreat_until=math.max(S.retreat_until,now()+15) end
            local current=snapshot()
            if current then lock_actor(current.self_id,now(),15) end
            S.blocked[1]=math.max(S.blocked[1],now()+15)
            if S.pending and S.pending.channel==1 then S.pending=nil end
            phase("RĘCZNIE","Ręczny manewr: czekam na odnowienie, automatyka nadal działa.")
        end
    end)
    if type(ctx.trigger_exact)=="function" then
        for _,text in ipairs({"Jestes gotowa do zmiany w szyku.","Jestes gotowy do zmiany w szyku.",
            "Jestes gotowa do kolejnej zmiany w szyku.","Jestes gotowy do kolejnej zmiany w szyku."}) do
            ctx:trigger_exact(text,function()
                local current=snapshot()
                if current then unlock_actor(current.self_id) end
                S.retreat_until=now()
                S.blocked[1]=now()
                schedule()
            end)
        end
        ctx:trigger_exact("Musisz chwile odpoczac po ostatniej zmianie w szyku.",function()
            local current=snapshot()
            if current then lock_actor(current.self_id,now(),15) end
            S.blocked[1]=math.max(S.blocked[1],now()+15)
            if S.pending and S.pending.channel==1 then S.pending=nil end
            phase("ODNOWIENIE","MUD odmówił manewru; czekam na gotowość.")
        end)
        ctx:trigger_exact("Komu i jaki rozkaz chcesz wydac?",function()
            if S.pending and S.pending.channel==4 and now()-S.pending.sent_at<=3 then
                S.blocked[4]=math.max(S.blocked[4],now()+30);S.pending=nil
                phase("ODRZUCONY ROZKAZ","Rozkaz odrzucony przez MUD; kanał drużyny wstrzymany na 30 s.")
            end
        end)
    end
    -- A minion who regained formation readiness can maneuver immediately.
    -- Do not clear the wrong minion if names are ambiguous.
    ctx:trigger([[^(.+) jest gotow[ay] do kolejnej zmiany w szyku\.$]],function()
        local name=tostring(matches and matches[2] or ""):lower():gsub("^%s+",""):gsub("%s+$","")
        local matches_by_name={}
        for _,row in ipairs(E.rows()) do
            if not row.self and row.name:lower()==name then
                matches_by_name[#matches_by_name+1]=row
            end
        end
        if #matches_by_name==1 then
            local row=matches_by_name[1]
            unlock_actor(row.id)
            if row.channel<4 then S.blocked[row.channel]=now() end
            if S.pending and (S.pending.actor==row.id or S.pending.channel==row.channel) then S.pending=nil end
            phase("GOTOWA","Pachołek gotowy do kolejnego manewru.")
            schedule()
        elseif #matches_by_name>1 then
            phase("BLOKADA","Niejednoznaczna nazwa postaci; nie kasuję blokad.")
        end
    end)
    ctx:trigger([[^(.+) wciaz lapie rownowage po ostatniej zmianie w szyku\.$]],function()
        local name=tostring(matches and matches[2] or ""):lower():gsub("^%s+",""):gsub("%s+$","")
        local matches_by_name={}
        for _,row in ipairs(E.rows()) do
            if not row.self and row.name:lower()==name then
                matches_by_name[#matches_by_name+1]=row
            end
        end
        if #matches_by_name==1 then
            local row=matches_by_name[1]
            lock_actor(row.id,now(),15)
            if S.pending and S.pending.actor==row.id then S.pending=nil end
            phase("ODNOWIENIE","Jednostka nadal łapie równowagę; lokalny odstęp przedłużony.")
        else phase("BLOKADA","Nie rozpoznano jednoznacznie jednostki z komunikatu równowagi.") end
    end)
    ctx:timer(0.5,schedule,true)
    ctx:cleanup(function() S.destroyed=true;S.on=false;S.pending=nil end)
    detect()
    return E
end
return T
