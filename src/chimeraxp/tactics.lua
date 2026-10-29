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
        last={},transfers={},pending=nil,barrier=0,destroyed=false,sending=false}
    local E={}
    local function now() return type(getEpoch)=="function" and getEpoch() or os.time() end
    local function notify() if not S.destroyed and changed then changed() end end
    local function save() ctx:save("tactics",config) end
    local function phase(name,detail) S.phase=name;S.detail=detail;notify() end
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
                    S.blocked[i+1]=math.max(S.blocked[i+1],now()+15);dirty=true
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
        S.on=true;S.received={};S.pending=nil;S.barrier=math.max(S.barrier,now()+5)
        phase("SYNCHRONIZACJA","Czekam na nowe dane drużyny i walki.")
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
            ambiguous=S.ambiguous,team_orders=config.team_orders,team_broadcast=config.team_broadcast,
            retreat=config.retreat,mass=config.mass}
    end
    local function invalid_room()
        S.received={};S.pending=nil
        if S.on then phase("SYNCHRONIZACJA","Nowa lokacja: czekam na aktualne dane.") end
    end
    local function evaluate()
        if S.destroyed or not S.on then return end
        local reason=integration.check(nil)
        if reason then E.stop(reason);return end
        local xp=patrol.status()
        if xp.started and (xp.paused or xp.dry or xp.phase~="COMBAT") then
            phase("WSTRZYMANA","Taktyka czeka na walkę podczas wyprawy.");return
        end
        local t=now()
        for _,key in ipairs({"entities","group","combat"}) do
            if not S.received[key] or t-S.received[key]>15 then
                phase("SYNCHRONIZACJA","Brak świeżych danych: "..key);return
            end
        end
        local s,err=snapshot()
        if not s then phase("BLOKADA GMCP",err);return end
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
        if t<S.barrier then return end
        local blocked={S.blocked[1]>t,{cover=S.blocked[2]>t,support=S.support[2]>t},
            {cover=S.blocked[3]>t,support=S.support[3]>t},S.blocked[4]>t}
        if S.ambiguous then
            for i,pet in ipairs(config.minions) do
                local confirmed=config.confirmed_minions[i]
                local current=s.minions[pet.id]
                if not confirmed or confirmed.id~=pet.id or not current or current.name~=confirmed.name then blocked[i+1]=true end
            end
        end
        local d=M.plan(s,config,S.enabled,blocked)
        if not d then
            local detail=S.ambiguous and "Niejednoznaczne pachołki: wymagane jawne przypisanie do P1/P2."
                or config.team_orders and s.leader~=s.self_id and "Rozkazy graczom czekają: nie prowadzisz drużyny."
                or "Nie potrzeba zmiany szyku."
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
        if d.kind=="support" then S.support[d.channel]=t+4
        else S.blocked[d.channel]=t+(d.channel==1 and 8 or 15) end
        if d.kind=="team_cover" or d.kind=="team_attack" then
            for i,p in ipairs(config.minions) do
                for _,id in ipairs(d.recipients or {}) do if p.id==id then
                    if d.kind=="team_cover" then S.blocked[i+1]=math.max(S.blocked[i+1],t+15)
                    else S.support[i+1]=math.max(S.support[i+1],t+4) end
                end end
            end
            if d.kind=="team_cover" and d.protected~=s.self_id then S.blocked[1]=math.max(S.blocked[1],t+8) end
        end
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
        ctx:on(event,function() S.received[key]=now();detect();schedule();notify() end)
    end
    ctx:on("chimera.char.vitals",schedule)
    ctx:on("chimera.room.changed",invalid_room)
    ctx:on("chimera.step.manual",function() if not S.sending then invalid_room() end end)
    ctx:on("chimera.session.end",function() E.stop("Rozłączono. Taktyka pozostaje wyłączona.") end)
    ctx:on("sysDataSendRequest",function(_,command)
        if S.sending then return end
        local text=tostring(command or ""):lower():gsub("^%s+","")
        if text:match("^parozkaz%s") then
            S.enabled[2]=false;S.enabled[3]=false;S.blocked[2]=now()+15;S.blocked[3]=now()+15
            if S.pending and (S.pending.channel==2 or S.pending.channel==3) then S.pending=nil end
            phase("RĘCZNIE","Zewnętrzny rozkaz: kanały pachołków wyłączone.")
        elseif text:match("^rozkaz%s") then S.blocked[4]=math.max(S.blocked[4],now()+15)
        elseif text:match("^zaslon%s") or text:match("^wycofaj%s") or text:match("^przelam%s") then
            S.enabled[1]=false;S.blocked[1]=now()+8
            if S.pending and S.pending.channel==1 then S.pending=nil end
            phase("RĘCZNIE","Ręczny manewr: kanał postaci wyłączony.")
        end
    end)
    if type(ctx.trigger_exact)=="function" then
        for _,text in ipairs({"Jestes gotowa do zmiany w szyku.","Jestes gotowy do zmiany w szyku."}) do
            ctx:trigger_exact(text,function() S.blocked[1]=0;schedule() end)
        end
        ctx:trigger_exact("Musisz chwile odpoczac po ostatniej zmianie w szyku.",function()
            S.blocked[1]=now()+8;if S.pending and S.pending.channel==1 then S.pending=nil end
            phase("ODNOWIENIE","MUD odmówił manewru; czekam na gotowość.")
        end)
        ctx:trigger_exact("Komu i jaki rozkaz chcesz wydac?",function()
            if S.pending and S.pending.channel==4 and now()-S.pending.sent_at<=3 then
                S.blocked[4]=math.max(S.blocked[4],now()+30);S.pending=nil
                phase("ODRZUCONY ROZKAZ","Rozkaz odrzucony przez MUD; kanał drużyny wstrzymany na 30 s.")
            end
        end)
    end
    ctx:trigger([[^(.+) wciaz lapie rownowage po ostatniej zmianie w szyku\.$]],function()
        local name=tostring(matches and matches[2] or ""):lower():gsub("^%s+",""):gsub("%s+$","")
        local channels={}
        for _,row in ipairs(E.rows()) do
            if not row.self and row.name:lower()==name then channels[#channels+1]=row.channel end
        end
        if #channels==1 then
            local channel=channels[1];S.blocked[channel]=math.max(S.blocked[channel],now()+15)
            if S.pending and S.pending.channel==channel then S.pending=nil end
            phase("ODNOWIENIE","Jednostka nadal łapie równowagę; lokalny odstęp przedłużony.")
        else phase("BLOKADA","Nie rozpoznano jednoznacznie jednostki z komunikatu równowagi.") end
    end)
    ctx:timer(0.5,schedule,true)
    ctx:cleanup(function() S.destroyed=true;S.on=false;S.pending=nil end)
    detect()
    return E
end
return T
