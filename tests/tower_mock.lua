-- Simulated one-floor Kregi Shoona; real Mudlet/Qt testing remains necessary.
local root=os.getenv("CHIMERAXP_TOWER_ROOT") or "."
local Tower=assert(loadfile(root.."/src/chimeraxp/tower.lua"))()
local Loot=assert(loadfile(root.."/src/chimeraxp/tower_loot.lua"))()
local clock,real_time=1000,os.time
os.time=function() return clock end

local function scenario(opts)
    opts=opts or {}
    local rooms={
        A={id="aaaa000000000001",name=opts.start_name or "Platforma mozaiki nad pustka, poziom 2",exits={poludnie="aaaa000000000002"}},
        B={id="aaaa000000000002",name="Most",exits={polnoc="aaaa000000000001",poludnie="aaaa000000000004",wschod="aaaa000000000003"}},
        C={id="aaaa000000000003",name="Boss",exits={zachod="aaaa000000000002"}},
        D={id="aaaa000000000004",name="Bestia",exits={polnoc="aaaa000000000002"}},
    }
    if opts.guardian then
        rooms.B.exits.poludnie=rooms.C.id
        rooms.B.exits.wschod=rooms.D.id
        rooms.C.exits={polnoc=rooms.B.id}
        rooms.D.exits={zachod=rooms.B.id}
        rooms.E={id="aaaa000000000005",name="Zbedna odnoga",exits={wschod=rooms.B.id}}
        rooms.B.exits.zachod=rooms.E.id
        if opts.guardian_late then
            rooms.B.exits.poludnie=rooms.D.id
            rooms.B.exits.wschod=rooms.E.id
            rooms.B.exits.zachod=rooms.C.id
            rooms.D.exits={polnoc=rooms.B.id}
            rooms.E.exits={zachod=rooms.B.id}
            rooms.C.exits={wschod=rooms.B.id}
        end
    end
    local ids,lookup={},{}
    local level,area=2,"8e8d3415f86872c6"
    local function index_rooms()
        ids,lookup={},{}
        for i,key in ipairs({"A","B","C","D","E"}) do
            if rooms[key] then ids[rooms[key].id]=i;lookup[i]=key end
        end
    end
    index_rooms()
    local position="A"
    local alive=true
    local guardian_alive=opts.guardian==true
    local spare_alive=opts.guardian==true
    local visits={}
    local mobs={D={
        {id="enemy:91",kind="npc",relation=opts.neutral_npc and "neutral" or "hostile",
            hp=920,maxhp=1060,group_role="none"},
        {id="ally:88",kind="npc",relation="ally",group_role="member",hp=100,maxhp=100}
    }}
    mobs.C={{id="guardian:1",kind="npc",relation="neutral",hp=100,maxhp=100,group_role="none"}}
    mobs.E={{id="spare:1",kind="npc",relation="neutral",hp=100,maxhp=100,group_role="none"}}
    local group={leader="player:1",members={{id="player:1",self=1,here=1,hp=100,maxhp=100},
        {id="minion:1",self=0,here=1,hp=100,maxhp=100}}}
    local entities,combat,vitals={},nil,{hp=100,fatigue=10}
    local timers,seq,commands,handlers,triggers,report,logs={},{},{},{},{},{},{warn={},info={}}
    seq=0
    local ctx={log={info=function(s) logs.info[#logs.info+1]=s end,warn=function(s) logs.warn[#logs.warn+1]=s end}}
    local function r()
        local v=rooms[position];return {id=v.id,name=v.name,area="Kregi Shoona, poziom "..level.." #421852174",
            area_id=area,exits=v.exits}
    end
    local api={room=r,entities=function() return entities end,combat=function() return combat end,
        group=function() return group end,vitals=function() return vitals end,connected=function() return true end}
    local map={current_room=function() return ids[r().id] end}
    local emit
    local function arrive(key,kind,walker_arrival)
        position=key
        visits[#visits+1]=key
        entities={room=r().id,entities=(key=="D" and alive and mobs.D)
            or (key=="C" and guardian_alive and mobs.C) or (key=="E" and spare_alive and mobs.E) or {}}
        combat={room=r().id,relations={}}
        if opts.low_hp_on_d and key=="D" then vitals.hp=25 end
        if opts.low_hp_on_d and key=="A" then vitals.hp=100 end
        if walker_arrival and opts.walker_arrival_first then
            -- Actual Chimera: room.changed -> mapper.moved -> walker.arrived,
            -- *then* Tower's room.changed listener runs.
            emit("chimera.mapper.moved",ids[r().id],r())
            emit("chimera.walk.arrived",walker_arrival)
        end
        emit("chimera.room.changed",{id=r().id,how=kind or "reczny"})
        emit("chimera.room.entities",entities)
        emit("chimera.combat.state",combat)
        emit("chimera.char.vitals",vitals)
    end
    local function text_line(prefix)
        for _,item in ipairs(triggers) do
            if item.pat:find(prefix,1,true) then item.fn();return true end
        end
        error("No registered trigger for "..prefix)
    end
    local function score_line(level,gained,total)
        -- Mudlet tempRegexTrigger uses global matches[2..4] for captures.
        local original=rawget(_G,"matches")
        _G.matches={
            "Poziom "..level.." jest czysty. Zyskujesz "..gained..
                " punktow Kregow (razem "..total..").",
            tostring(level),tostring(gained),tostring(total)
        }
        local ok=pcall(function() text_line("^Poziom (\\d+) jest czysty") end)
        _G.matches=original
        assert(ok,"Tower score trigger not registered or failed")
    end
    local function unlock_line()
        text_line("Gdzies w komnacie straznika rozjarza sie mozaika przejscia")
    end
    local function remaining_line(n)
        if n==0 then text_line("Dosc istot padlo")
        else
            _G.matches={"server count",tostring(n)}
            text_line("Do przejscia trzeba jeszcze pokonac (\\d+)")
            _G.matches=nil
        end
    end
    ctx.use=function(_,name)
        return ({gmcp=api,mapper=map,walker=ctx.walker})[name]
    end
    ctx.saved=function(_,name,default) return opts.saved or default end
    ctx.save=function(_,name,data) opts.saved=data end
    ctx.command=function(_,def)
        -- Context:command uses optional args to create a second Mudlet alias
        -- that also matches /exp wieza start. The short command must not overlap.
        if def[1]=="exp wieza" then
            assert(def.args==nil,"/exp wieza optional arguments duplicate explicit aliases")
        end
        commands[def[1]]=def.fn
    end
    ctx.on=function(_,event,fn) handlers[event]=handlers[event] or {};table.insert(handlers[event],fn) end
    ctx.trigger=function(_,pattern,fn) triggers[#triggers+1]={pat=pattern,fn=fn} end
    ctx.cleanup=function(_,fn) end
    ctx.report=function(_,title,rows) report[title]=rows end
    ctx.timer=function(_,delay,fn) seq=seq+1;timers[seq]={due=clock+delay,fn=fn};return seq end
    ctx.cancel=function(_,id) timers[id]=nil end
    emit=function(event,payload)
        for _,fn in ipairs(handlers[event] or {}) do fn(payload) end
    end
    ctx.walker={
        go=function(target)
            local key=lookup[target]
            if not key then return nil,"Brak mapy" end
            emit("chimera.walk.started")
            arrive(key,"chodzik",{target=rooms[key].id,map_room=target})
            if not opts.walker_arrival_first then
                emit("chimera.walk.arrived",{target=r().id,map_room=target})
            end
            return true
        end,
        stop=function(reason) emit("chimera.walk.stopped",{reason=reason}) end
    }
    ctx.send=function(_,cmd)
        report.sent=report.sent or {}
        report.sent[#report.sent+1]=cmd
        if cmd=="ob mozaike" then
            if position=="A" then
                if opts.no_start_reply then return end
                text_line(opts.wrong_start_mosaic and "Nie zauwazasz niczego takiego" or "Mozaika tli sie")
            elseif position=="C" then
                local active=not opts.force_inactive and not alive and not guardian_alive
                text_line(active and "Krag mozaiki jarzy" or "Krag mozaiki jest martwy")
            else text_line("Nie zauwazasz niczego takiego") end
        elseif cmd=="stan na mozaice" then
            assert(position=="C","Ascent from wrong room")
            if opts.auto_next and level==2 then
                level=opts.wrong_level and 4 or 3
                area="9e8d3415f86872c7"
                local replacement={}
                for _,room in pairs(rooms) do
                    replacement[room.id]=room.id:gsub("^aaaa","bbbb")
                end
                for _,room in pairs(rooms) do
                    room.id=replacement[room.id]
                    for dir,id in pairs(room.exits) do room.exits[dir]=replacement[id] end
                end
                index_rooms();alive=true;guardian_alive=opts.guardian==true;spare_alive=opts.guardian==true
                arrive("A")
            end
        elseif cmd=="policz ciala" then
            if opts.two_corpses then text_line("dwoch sztuk")
            else text_line("Nie doliczyl") end
        elseif cmd=="n" or cmd=="s" or cmd=="e" or cmd=="w" then
            local dirs={n="polnoc",s="poludnie",e="wschod",w="zachod"}
            local next_id=rooms[position].exits[dirs[cmd]]
            assert(next_id,"Bad step from "..position..": "..cmd)
            local key
            for k,node in pairs(rooms) do if node.id==next_id then key=k end end
            arrive(key,"reczny")
        elseif cmd:match("^zabij ") then
            assert(position=="D" or position=="C" or position=="E")
            local victim=cmd:match("^zabij (.+)$")
            assert(victim==(position=="D" and "enemy:91" or position=="C" and "guardian:1" or "spare:1"))
            combat={room=r().id,relations={{attacker="player:1",defender=victim}}}
            emit("chimera.combat.state",combat)
            -- Kill is not immediate: send the combat completion on next tick.
            ctx:timer(0.5,function()
                if position=="D" then alive=false
                elseif position=="C" then guardian_alive=false
                else spare_alive=false end
                entities={room=r().id,entities={}}
                combat={room=r().id,relations={}}
                emit("chimera.room.entities",entities)
                emit("chimera.combat.state",combat)
                if opts.guardian and position=="D" then remaining_line(0) end
                if opts.hp_after_guardian and position=="C" then
                    vitals.hp=opts.hp_after_guardian
                    emit("chimera.char.vitals",vitals)
                end
                if opts.server_score and (not opts.guardian or position=="C") then
                    local score=opts.server_score
                    score_line(level,score.gained,score.total+(level-2)*score.gained)
                    if opts.guardian then text_line("Krag mozaiki w posadzce rozjarza") end
                    unlock_line()
                end
            end)
        end
    end
    _G.getRoomIDbyHash=function(hash) return ids[hash] end
    _G.getRoomHashByID=function(number) return rooms[lookup[number]].id end
    _G.getPath=function(from,to)
        _G.speedWalkPath={to}
        return true
    end
    local highlights, border_colors, border_widths={},{},{}
    local envs,colors={},{}
    _G.setRoomEnv=function(id,env) envs[id]=env end
    _G.setCustomEnvColor=function(id,r,g,b,a) colors[id]={r,g,b,a} end
    _G.highlightRoom=function(id,red,green,blue)
        highlights[id]={red,green,blue}
    end
    _G.unHighlightRoom=function(id) highlights[id]=nil end
    _G.getRoomBorderColor=function() return nil end
    _G.getRoomBorderThickness=function() return nil end
    _G.setRoomBorderColor=function(id,red,green,blue,alpha)
        border_colors[id]={red,green,blue,alpha}
    end
    _G.setRoomBorderThickness=function(id,width) border_widths[id]=width end
    _G.clearRoomBorderColor=function(id) border_colors[id]=nil end
    _G.clearRoomBorderThickness=function(id) border_widths[id]=nil end
    local tower=Tower.new(ctx,function() return {started=false} end,
        {check=function() if opts.conflict then return "Oficjalne zbieranie wlaczone" end end},function() end,Loot)
    arrive("A")
    local function advance(by)
        local ending=clock+(by or 0)
        local loops=0
        while true do
            local best,best_id
            for id,t in pairs(timers) do
                if t.due<=ending and (not best or t.due<best.due or (t.due==best.due and id<best_id)) then
                    best,best_id=t,id
                end
            end
            if not best then break end
            timers[best_id]=nil;clock=best.due
            best.fn();loops=loops+1
            assert(loops<5000,"Timer loop")
        end
        clock=ending
    end
    return {tower=tower,run=advance,logs=logs,opts=opts,call=function(name,arg) assert(commands[name],name)(arg) end,
        sent=function() return report.sent or {} end, report=report,position=function() return position end,
        move=function(key) arrive(key) end, alive=function() return alive end,
        emit=emit, highlights=highlights,border_colors=border_colors,border_widths=border_widths,
        score_line=score_line,unlock_line=unlock_line,remaining_line=remaining_line,
        envs=envs,colors=colors,visits=visits,
        heal=function() vitals.hp=100;emit("chimera.char.vitals",vitals) end}
end

local function contains(values,needle)
    for _,v in ipairs(values) do if v:find(needle,1,true) then return true end end
    return false
end
local function count(values,needle)
    local n=0
    for _,v in ipairs(values) do if v==needle then n=n+1 end end
    return n
end

-- A differently named entrance is allowed only when its return mosaic is verified.
local renamed=scenario({start_name="Platforma wejsciowa nad otchlania, poziom 2"})
assert(renamed.tower.start(),"Different entrance name must not block startup")
assert(renamed.tower.status().started,"Server-confirmed return mosaic starts the explorer")
assert(contains(renamed.sent(),"ob mozaike"),"Start must inspect the entrance mosaic")
print("Tower entrance validation independent of room name: PASS")

-- A non-return mosaic cannot be promoted to a safe lock.
local wrong=scenario({wrong_start_mosaic=true})
assert(wrong.tower.start(),"Preflight request should be accepted")
wrong.run(7)
assert(not wrong.tower.status().started,"Never start without confirmed return mosaic")
assert(#wrong.sent()==1 and wrong.sent()[1]=="ob mozaike","No movement on bad entrance")
print("Tower unsafe entrance denied: PASS")

local unanswered=scenario({no_start_reply=true})
assert(unanswered.tower.start())
assert(unanswered.tower.start()==false,"Only one entrance check in flight")
unanswered.run(7)
assert(not unanswered.tower.status().started and #unanswered.sent()==1,
    "Timed-out verification never attacks or walks")
print("Tower entrance timeout and deduplication: PASS")

-- Full floor: entrance -> fight -> gather -> mosaic. No auto ascent, ever.
local m=scenario()
assert(m.tower.start())
-- Entry room must be blue on the mapper, even before the first step.
local entry=m.colors[m.envs[1]]
assert(entry and entry[1]==96 and entry[2]==165 and entry[3]==250,"start room fill must be blue")
m.run(40)
local st=m.tower.status()
assert(st.phase=="COMPLETE",st.phase..": "..tostring(st.reason))
assert(m.position()=="C","Must stop in exit mosaic room")
assert(st.level==2 and st.done and st.rooms==4 and st.cleared==4)
assert(contains(m.sent(),"zabij enemy:91"),"Must attack hostile NPC")
assert(contains(m.sent(),"rozkaz druzynie zaatakowac enemy:91"),"Must focus party")
assert(contains(m.sent(),"wez zlote monety"),"Must loot ground")
assert(contains(m.sent(),"wloz monety do plecaka"),"Must pack coins")
assert(contains(m.sent(),"napelnij plecak"),"Must pack loot")
assert(count(m.sent(),"policz ciala")==1,"Only the enemy room counts corpses")
assert(count(m.sent(),"wez zlote monety")==1,"No collection in empty corridors")
assert(count(m.sent(),"wloz monety do plecaka")==1,"No packing in empty corridors")
assert(count(m.sent(),"napelnij plecak")==1,"No redundant bag fill commands")
-- Official visited/walker highlighting may replace our return-mosaic fill.
-- A mapper move event must reapply the start color, also after completion.
m.highlights[1]=nil
m.emit("chimera.mapper.moved",4,{})
m.run(0.1)
assert(m.colors[m.envs[1]][3]==250 and m.colors[m.envs[3]][2]==239,
    "start and active room fills survive highlight removal")
assert(not contains(m.sent(),"stan na mozaice"),"Never ascend")
print("Tower one-floor exploration: PASS")

-- Reproduce real mapper event ordering: walker announces arrival from inside
-- the mapper callback before Tower receives the outer room.changed event.
-- The explorer must own this step, including its return from a blind alley.
local nested=scenario({walker_arrival_first=true})
assert(nested.tower.start())
nested.run(45)
local nested_status=nested.tower.status()
assert(nested_status.phase=="COMPLETE",
    "walker event race interrupted Tower: "..nested_status.phase.." / "..tostring(nested_status.reason))
assert(nested.position()=="C")
print("Nested mapper/walker arrival and dead-end backtrack: PASS")

-- Mobs in Shoona are neutral *until* we attack them. They remain targets,
-- unlike allies and other party members.
local neutral=scenario({neutral_npc=true,walker_arrival_first=true})
assert(neutral.tower.start())
neutral.run(45)
local neutral_status=neutral.tower.status()
assert(neutral_status.phase=="COMPLETE",
    "neutral tower NPC ignored: "..neutral_status.phase.." / "..tostring(neutral_status.reason))
assert(contains(neutral.sent(),"zabij enemy:91"),"Must engage neutral dungeon creature")
assert(not contains(neutral.sent(),"zabij ally:88"),"Must never attack allied NPC")
print("Neutral Shoona NPCs and allied exclusion: PASS")

-- The Tower setting controls ACTUAL orders, independently of a selected
-- classic EXP terrain. Turning it off must not suppress personal attacks.
local nofocus=scenario({saved={partyAttack=false}})
assert(nofocus.tower.start())
nofocus.run(45)
assert(nofocus.tower.status().phase=="COMPLETE")
assert(contains(nofocus.sent(),"zabij enemy:91"),
    "player still attacks when shared target is disabled")
assert(not contains(nofocus.sent(),"rozkaz druzynie zaatakowac enemy:91"),
    "disabled shared attack must not send group target orders")
assert(nofocus.tower.status().partyAttack==false)
assert(nofocus.tower.set_party_attack("on"))
assert(nofocus.tower.status().partyAttack==true
    and nofocus.opts.saved.partyAttack==true,
    "Tower shared attack preference is persisted and exposed to UI")
print("Tower shared attack OFF/ON and actual group orders: PASS")

-- Server-issued scores are the source of truth, not estimated NPC ratios.
-- The mosaic signal is a readiness flag; it never issues a floor transition.
local scored=scenario({server_score={level=2,gained=4,total=14}})
assert(scored.tower.start())
scored.run(45)
local scored_status=scored.tower.status()
assert(scored_status.phase=="COMPLETE")
assert(scored_status.exit_ready and scored_status.server_clear)
assert(scored_status.score and scored_status.score.level==2
    and scored_status.score.gained==4 and scored_status.score.total==14)
local summary=scored.report["ChimeraXP | Wieza - koniec pietra"]
assert(summary and summary[1][2]=="2" and summary[2][2]=="+4"
    and summary[3][2]=="14","Completion summary must show server score")
scored.call("exp wieza status")
local status_report=scored.report["ChimeraXP | Wieza"]
assert(status_report and status_report[7][2]:find("poziom 2",1,true),
    "Active floor status shows score")
scored.call("exp wieza punkty")
assert(scored.report["ChimeraXP | Wieza - punkty"][3][2]=="14")
scored.call("exp wieza historia")
assert(#scored.report["ChimeraXP | Wieza - historia"]==1)
assert(#scored.opts.saved.results==1)
scored.score_line(2,4,14) -- duplicate must be idempotent
scored.score_line(3,99,99) -- stale or foreign level must be discarded
assert(#scored.opts.saved.results==1)
local restored=scenario({saved=scored.opts.saved})
restored.call("exp wieza punkty")
assert(restored.report["ChimeraXP | Wieza - punkty"][2][2]=="+4",
    "Saved results survive rebuilding the module")
assert(not contains(scored.sent(),"stan na mozaice"))
print("Server scores, persistent history, mosaic announcement and completion report: PASS")

-- The guardian room is discovered before combat and left until the server
-- says enough creatures have fallen. A spare branch must not be cleared.
local guardian=scenario({guardian=true,server_score={gained=4,total=18}})
assert(guardian.tower.start())
guardian.remaining_line(10)
assert(guardian.tower.status().remaining==10)
guardian.remaining_line(1)
assert(guardian.tower.status().remaining==1)
guardian.run(70)
assert(guardian.tower.status().phase=="COMPLETE",tostring(guardian.tower.status().reason))
local kills={}
for _,cmd in ipairs(guardian.sent()) do
    if cmd:match("^zabij ") then kills[#kills+1]=cmd end
end
assert(#kills==2 and kills[1]=="zabij enemy:91" and kills[2]=="zabij guardian:1",
    "defer guardian and skip remaining branch")
assert(not contains(guardian.visits,"E"),"Do not visit spare branch after quota")
assert(guardian.tower.status().session_points==4)
assert(guardian.envs[3]~=guardian.envs[1],"exit room has distinct real environment")
print("Guardian deferred until server quota; unnecessary branch skipped: PASS")

local late=scenario({guardian=true,guardian_late=true,server_score={gained=4,total=18}})
assert(late.tower.start())
late.run(70)
assert(late.tower.status().phase=="COMPLETE",tostring(late.tower.status().reason))
assert(contains(late.visits,"E"),"The guardian is still unknown, so inspect the next branch")
assert(not contains(late.sent(),"zabij spare:1"),"Quota met: skip neutral non-guardian")
assert(contains(late.sent(),"zabij guardian:1"))
print("Quota before guardian discovery: inspect without fighting spare neutral NPCs: PASS")

local multi=scenario({guardian=true,auto_next=true,server_score={gained=4,total=18}})
multi.call("exp wieza auto","on")
assert(multi.tower.start())
for i=1,100 do
    multi.run(1)
    if multi.tower.status().level==3 then
        multi.call("exp wieza auto","off")
        break
    end
end
assert(multi.tower.status().level==3,"Auto ascent must start next GMCP floor")
multi.run(70)
assert(multi.tower.status().phase=="COMPLETE",tostring(multi.tower.status().reason))
assert(count(multi.sent(),"stan na mozaice")==1,"Exactly one ascent")
assert(multi.tower.status().session_points==8,"Sum of both server gains")
multi.call("exp wieza sesja")
local session_report=multi.report["ChimeraXP | Wieza - sesja"]
assert(#session_report==4 and session_report[4][2]=="+8")
print("Verified auto ascent and cross-floor session points: PASS")

local timeout=scenario({server_score={gained=4,total=18}})
timeout.call("exp wieza auto","on")
assert(timeout.tower.start())
timeout.run(80)
assert(timeout.tower.status().phase=="PAUSED")
assert(count(timeout.sent(),"stan na mozaice")==1,"Never repeat unconfirmed ascent")
print("Unconfirmed ascent pauses without retry: PASS")

local weak=scenario({guardian=true,auto_next=true,hp_after_guardian=70,server_score={gained=4,total=18}})
weak.call("exp wieza auto","on")
assert(weak.tower.start())
weak.run(70)
assert(weak.tower.status().phase=="RECOVERY")
assert(count(weak.sent(),"stan na mozaice")==0,"No ascent until HP recovery")
weak.heal()
for i=1,15 do
    weak.run(1)
    if weak.tower.status().level==3 then break end
end
assert(weak.tower.status().level==3 and count(weak.sent(),"stan na mozaice")==1)
weak.tower.stop("test stop")
print("Auto ascent waits for team HP recovery: PASS")

local wrong_floor=scenario({auto_next=true,wrong_level=true,server_score={gained=4,total=18}})
wrong_floor.call("exp wieza auto","on")
assert(wrong_floor.tower.start())
wrong_floor.run(70)
assert(wrong_floor.tower.status().phase=="PAUSED")
assert(count(wrong_floor.sent(),"stan na mozaice")==1,"Unexpected destination: never retry")
print("Unexpected next level blocks auto ascent: PASS")

local bodies=scenario({two_corpses=true})
assert(bodies.tower.start())
bodies.run(80)
assert(bodies.tower.status().phase=="COMPLETE",bodies.tower.status().phase)
assert(contains(bodies.sent(),"wez mithrylowe monety z 1. ciala"))
assert(contains(bodies.sent(),"wez kamienie z 2. ciala"))
print("Ordinal corpse collection: PASS")

-- An inactive mosaic after exploring every room is not success.
local inactive=scenario({force_inactive=true})
assert(inactive.tower.start())
inactive.run(40)
assert(inactive.tower.status().phase=="PAUSED", inactive.tower.status().phase.." :: "..tostring(inactive.tower.status().reason))
assert(not contains(inactive.sent(),"stan na mozaice"))
print("Inactive mosaic stops: PASS")

-- User movement outside the robot's owned walk pauses, never guesses.
local manual=scenario()
assert(manual.tower.start())
manual.move("B")
assert(manual.tower.status().paused)
print("Manual movement pauses: PASS")

-- Low HP forces a confirmed retreat, not suicidal engagement.
local retreat=scenario({low_hp_on_d=true})
assert(retreat.tower.start())
retreat.run(12)
assert(not contains(retreat.sent(),"zabij enemy:91"),"No attack below retreat threshold")
print("Health safety/retreat: PASS")

-- Conflict with official auto-collect blocks start before any commands.
local conflict=scenario({conflict=true})
assert(conflict.tower.start()==false)
assert(#conflict.sent()==0)
print("Conflicting automations blocked: PASS")

os.time=real_time