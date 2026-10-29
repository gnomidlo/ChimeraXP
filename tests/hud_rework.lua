local new=dofile("tests/support_harness.lua")
local P=dofile("plugins/chimera_autoexp/init.lua")
local function fixture(initial_border)
    local h=new();h.width=1000;h.height=700;h.border=initial_border or 12;h.labels={};h.roots={};h.created=0
    h.saved.profiles={
        alpha={name="Jaskinie grimloków",route={"rooma","safe"},targets={"Goblin"},avoid={},loot={},safeRoom="safe",rules={maxEnemies=5},economy={enabled=false}},
        beta={name="Las",route={"rooma","safe"},targets={"Goblin"},avoid={},loot={},safeRoom="safe",rules={maxEnemies=5},economy={enabled=true}},
    };h.saved.selected="alpha"
    getRoomIDbyHash=function(id) return id=="rooma" and 1 or 2 end
    getMainWindowSize=function() return h.width,h.height end
    getBorderTop=function() return h.border end
    setBorderTop=function(value)
        h.border=value;h.border_writes=(h.border_writes or 0)+1
        h.emit("sysWindowResizeEvent")
    end
    setCmdLine=function(value) h.input=value end
    Geyser={
        Container={new=function(_,o)
            local w={name=o.name,x=o.x,y=o.y,w=o.width,h=o.height}
            function w:move(x,y) self.x,self.y=x,y end
            function w:resize(x,y) self.w,self.h=x,y end
            function w:show() self.hidden=false end
            function w:hide() self.hidden=true end
            function w:delete() self.deleted=true end
            function w:raiseAll() end
            h.roots[#h.roots+1]=w;return w
        end},
        Label={new=function(_,o,parent)
            local w={name=o.name,x=o.x,y=o.y,w=o.width,h=o.height,parent=parent};h.created=h.created+1
            function w:move(x,y) self.x,self.y=x,y end
            function w:resize(x,y) self.w,self.h=x,y end
            function w:show() self.hidden=false end
            function w:hide() self.hidden=true end
            function w:delete() self.deleted=true end
            function w:setStyleSheet(css) self.css=css end
            function w:echo(text) self.text=text end
            function w:setClickCallback(fn) self.click=fn end
            h.labels[w.name]=w;return w
        end},
    }
    h.api=P.setup(h.ctx)
    return h
end
do
    local h=fixture();local api=h.api
    assert(h.border==44 and api.hud.root.y==0 and not api.status().started,"bar starts at viewport top and reserves console space")
    assert(api.hud.labels.party.w<150 and api.hud.labels.areas.x+api.hud.labels.areas.w<450,"menus keep compact natural widths")
    assert(api.hud.labels.pause.x>850,"controls stay at the right edge")
    assert(api.hud.labels.party.css:find("background:#181C26",1,true),"idle menus share the bar background")
    local writes=h.border_writes;api.hud:render();assert(h.border_writes==writes,"unchanged border must not trigger resize loops")
    api.hud:open("tactics");assert(api.hud.overlay.x==api.hud.labels.tactics.x,"dropdown anchors to its menu")
    api.hud:open("settings");assert(api.hud.overlay.x+api.hud.overlay.w==h.width-8,"right dropdown fits the viewport")
    api.hud:open("party")
    for _,label in pairs(api.hud.labels) do
        if not label.widget.hidden then assert(not label.html:find("%%"),"party list must not duplicate health") end
    end
    local copy=api.snapshot();copy.profiles.alpha.route[1]="corrupt"
    assert(api.snapshot().profiles.alpha.route[1]=="rooma","snapshots cannot mutate saved profiles")
    assert(api.set_economy("alpha",true));assert(api.snapshot().profiles.beta.economy.enabled)
    api.request("start");h.advance(2.1)
    assert(api.status().started and api.status().elapsed==2)
    assert(api.hud.labels.badge.html:find("Jaskinie grimloków",1,true))
    assert(api.hud.labels.badge.html:find("00:00:02",1,true))
    assert(api.hud.badge.y==56 and h.border>=api.hud.badge.y+api.hud.badge.h,"active label reserves its own console space")
    assert(not api.set_economy("alpha",false),"active profile editing is guarded")
    api.request("pauza");local elapsed=api.status().elapsed;h.advance(3)
    assert(api.status().elapsed==elapsed,"paused time is excluded")
    assert(api.set_economy("alpha",false),"economy settings can change in pause")
    assert(api.snapshot().profiles.beta.economy.enabled,"per-area switch must not affect another profile")
    api.request("wybierz","Las");assert(api.status().selected=="alpha","pause does not permit switching terrain")
    api.tactics.toggle(true);assert(api.tactics.status().on)
    h.commands["exp stop"]();assert(not api.status().started and not api.tactics.status().on,"CLI STOP stops both engines")
    assert(api.hud.badge.hidden,"run label disappears after STOP")
    api.request("wybierz","Las");assert(api.status().selected=="beta")
    api.request("start");assert(api.status().elapsed==0,"new expedition resets elapsed time")
    api.stop_all();h.dispose();assert(h.border==12,"original top margin restored on disposal")
    api.request("start");for _,timer in ipairs(h.timers) do timer.fn() end
    assert(not api.status().started,"disposed API and queued callbacks cannot restart")
end
do
    local h=fixture(180);local api=h.api
    assert(api.hud.root.y==0 and h.border==180,"existing margin never offsets the bar")
    api.hud:visible(false);assert(h.border==180)
    api.hud:visible(true);h.emit("sysWindowResizeEvent")
    assert(api.hud.root.y==0 and h.border==180,"show and resize preserve the absolute top anchor")
    h.saved.profiles.alpha.name=string.rep("Żółć",40)
    h.width=320;api.request("start");h.advance(2.1)
    assert(api.hud.labels.badge.html:find("00:00:02",1,true),"long terrain names cannot truncate the clock")
    api.stop_all();h.dispose();assert(h.border==180)
end
do
    local h=fixture();local api=h.api
    h.width,h.height=320,360;h.emit("sysWindowResizeEvent");api.hud:open("areas")
    for key,label in pairs(api.hud.labels) do
        local w=label.widget
        if not w.hidden then
            assert(w.x>=0 and w.y>=0 and w.w>0 and w.h>0,"invalid geometry "..key)
            assert(w.x+w.w<=w.parent.w+1,"horizontal clipping "..key)
            assert(w.y+w.h<=w.parent.h+1,"vertical clipping "..key)
        end
    end
    local created=h.created;api.hud:render();assert(h.created==created,"widgets are cached")
    api.hud:open("profiles")
    local found
    for _,item in pairs(api.hud.labels) do if item.html:find("Zmień nazwę",1,true) and not item.widget.hidden then found=item.widget.click end end
    assert(found);found();assert(h.input=="/exp nazwa ","text editing never sends a game command")
    api.request("start");api.tactics.toggle(true)
    h.border=100;api.hud:render()
    assert(h.border==100 and api.status().paused and not api.tactics.status().on,"foreign margin is preserved and automation paused")
    h.dispose();assert(h.border==100,"cleanup must not clear another addon's margin")
end
do
    local h=fixture();local api=h.api
    h.settings["team.autopogon"]=true;api.request("start")
    assert(not api.status().started and #h.sent==0,"guard applies to API start")
    h.settings["team.autopogon"]=false;api.request("start");api.request("pauza")
    h.settings["team.autowsparcie"]=true;h.commands["exp wznow"]()
    assert(api.status().paused,"guard applies to CLI resume")
    h.settings["team.autowsparcie"]=false;api.request("wznow")
    h.settings["team.autopogon"]=true;h.fresh();h.advance(1)
    assert(api.status().paused,"conflicts enabled during an expedition cause pause")
    h.dispose()
end
Geyser=nil
do
    local h=fixture();h.api.request("start")
    h.p.room.key="rooma#2";h.emit("chimera.room.changed",{id="rooma",how="przeniesienie"})
    h.advance(1)
    assert(h.api.status().paused and #h.sent==0,"same world ID in a new instance cannot reuse the previous execution context")
    h.dispose()
end
Geyser=nil
print("PASS compact HUD: no party health, roles, terrain, per-area economy, elapsed, STOP, lifecycle, geometry, guarded entry points")
