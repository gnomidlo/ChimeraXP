local new=dofile("tests/support_harness.lua")
local P=dofile("plugins/chimera_autoexp/init.lua")
local function fixture(initial_border,configure)
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
    if configure then configure(h) end
    h.api=P.setup(h.ctx)
    return h
end
local function visible_item(h,text)
    for _,item in pairs(h.api.hud.labels) do
        if not item.widget.hidden and item.html:find(text,1,true) then return item end
    end
end
do
    local h=fixture();local api=h.api
    for _,name in ipairs({"party","tactics","areas","settings"}) do
        api.hud.labels[name].widget.click();assert(api.hud.menu==name)
        api.hud.labels[name].widget.click();assert(api.hud.menu==nil and api.hud.overlay.hidden,"second tab click closes its dropdown")
    end
    api.hud:open("settings");visible_item(h,"Walka i cele").widget.click()
    api.hud.labels.settings.widget.click();assert(not api.hud.menu,"parent tab closes an open submenu")
    assert(api.hud.labels.areas.html:find("#C2CCDB",1,true),"stopped expedition has a grey indicator")
    assert(api.hud.labels.tactics.html:find("#C2CCDB",1,true),"disabled tactics have a grey indicator")
    api.tactics.toggle(true)
    assert(api.hud.labels.tactics.html:find("#A8DCC2",1,true),"enabled tactics have a green indicator")
    api.hud.labels.pause.widget.click();assert(api.status().started,"play starts the selected terrain")
    assert(api.hud.labels.areas.html:find("#A8DCC2",1,true))
    api.hud.labels.pause.widget.click();assert(api.status().paused)
    assert(api.hud.labels.areas.html:find("#EFD8A6",1,true) and api.hud.labels.tactics.html:find("#EFD8A6",1,true),"paused automation has yellow indicators")
    assert(h.border==44 and #h.roots==2,"pause never adds a separate status strip")
    api.hud.labels.pause.widget.click();assert(not api.status().paused)
    api.stop_all();h.dispose()
end
do
    local h=fixture(nil,function(h)
        h.saved.profiles={};h.maproom=1;h.costcalls=0
        for i=1,6 do h.saved.profiles["p"..i]={name="Teren "..i,route={"p"..i.."0"},targets={},avoid={},loot={},rules={},economy={enabled=false}} end
        h.saved.profiles.p1.route={"p10","p11"};h.saved.selected="p1"
        getRoomIDbyHash=function(hash) return tonumber(hash:match("^p(%d+)$")) or -1 end
        local use=h.ctx.use
        h.ctx.use=function(ctx,name)
            if name=="mapper" then return {current_room=function() return h.maproom end} end
            if name=="walker" then return {cost=function(from,to)
                h.costcalls=h.costcalls+1
                return ({[10]=20,[11]=2,[20]=1,[30]=5,[40]=4})[to]
            end} end
            return use(ctx,name)
        end
    end)
    local api=h.api
    api.hud:open("areas")
    assert(visible_item(h,"Teren 2").y<visible_item(h,"Teren 1").y and visible_item(h,"Teren 1").y<visible_item(h,"Teren 4").y,"three nearest are sorted by the cheapest reachable route point")
    assert(not visible_item(h,"Teren 3") and not visible_item(h,"Teren 5"),"dropdown excludes farther and unreachable areas")
    local row=visible_item(h,"Teren 2");local economy=api.hud.labels.item1_economy
    assert(economy.y>=row.y and economy.y+economy.h<=row.y+row.h and economy.x>=row.x+row.w,
        "economy status chip is vertically centered beside the terrain card")
    economy.widget.click();assert(api.snapshot().profiles.p2.economy.enabled and not api.snapshot().profiles.p1.economy.enabled)
    local calls=h.costcalls;api.hud:render();assert(h.costcalls==calls,"clock updates do not recompute all paths")
    visible_item(h,"Wszystkie expowiska").widget.click()
    assert(api.hud.catalog and not api.hud.catalog.hidden and api.hud.overlay.hidden,"full list opens a separate floating window")
    assert(visible_item(h,"Teren 6"),"full list includes areas with unknown paths")
    visible_item(h,"Teren 3").widget.click();assert(api.status().selected=="p3","full-list rows can select terrain")
    api.hud.labels.catalog_menu_close.widget.click();assert(api.hud.catalog.hidden)
    api.hud:open("areas");h.maproom=30;h.emit("chimera.room.changed")
    assert(visible_item(h,"Teren 3").y<visible_item(h,"Teren 2").y,"nearest list updates after moving")
    h.maproom=nil;h.emit("chimera.room.changed")
    assert(visible_item(h,"Brak osiągalnych") and visible_item(h,"Wszystkie expowiska"),"unknown position keeps the full catalog accessible")
    h.dispose();assert(api.hud.catalog.deleted,"floating catalog is cleaned up")
end
do
    local h=fixture(nil,function(h)
        for i=1,80 do h.saved.profiles["extra"..i]={name=string.format("Teren %03d",i),route={"safe"},rules={},economy={enabled=false}} end
    end)
    h.api.hud:open("areas");visible_item(h,"Wszystkie expowiska").widget.click()
    assert(visible_item(h,"Teren 001") and not visible_item(h,"Teren 080"),"large catalogs render one page at a time")
    local next_page=h.api.hud.labels.catalog_next
    assert(next_page and not next_page.widget.hidden)
    next_page.widget.click();assert(h.api.hud.page==2 and not visible_item(h,"Teren 001"))
    local created=h.created;h.api.hud:render();assert(h.created==created,"catalog rows are reused")
    h.dispose()
end
do
    local h=fixture();local api=h.api
    assert(h.border==44 and api.hud.root.y==0 and not api.status().started,"bar starts at viewport top and reserves console space")
    assert(api.hud.labels.party.w<150 and api.hud.labels.areas.x+api.hud.labels.areas.w<450,"menus keep compact natural widths")
    assert(api.hud.labels.pause.x>850,"controls stay at the right edge")
    assert(api.hud.labels.party.css:find("background:#151922",1,true),"idle menus share the bar background")
    local writes=h.border_writes;api.hud:render();assert(h.border_writes==writes,"unchanged border must not trigger resize loops")
    api.hud:open("tactics");assert(api.hud.overlay.x==api.hud.labels.tactics.x,"dropdown anchors to its menu")
    api.hud:open("settings");assert(api.hud.overlay.x+api.hud.overlay.w==h.width-8,"right dropdown fits the viewport")
    api.hud:open("party")
    for _,label in pairs(api.hud.labels) do
        if not label.widget.hidden then assert(not label.html:find("%%"),"party list must not duplicate health") end
    end
    api.hud:open("settings")
    assert(not visible_item(h,"Większy pasek"),"obsolete large-bar control is removed")
    assert(h.border==44,"Obsidian keeps the top bar at 44px")
    assert(api.hud.labels.menu_bg.css:find("border-radius:10px",1,true),
        "all popup menus share a rounded Obsidian container")
    assert(api.hud.labels.header_icon and api.hud.labels.header_icon.html:find("⚙",1,true),
        "settings menu has a dedicated icon")
    api.hud:open("party")
    assert(api.hud.labels.item1_state.css:find("border-radius:7px",1,true),
        "toggle uses the compact status-chip style")
    assert(api.hud.overlay.w<=420,"compact party panel never exceeds 420 logical pixels")
    assert(api.hud.labels.item1_state.w<=41 and api.hud.labels.item1_state.h<=20,
        "toggles use small, unobtrusive state badges")
    assert(api.hud.labels.item4_state.h<=22,"member status chip does not dominate the row")
    assert(not api.hud.labels.menu_subtitle or api.hud.labels.menu_subtitle.widget.hidden,
        "duplicate large menu subtitles are removed")
    assert(not api.hud.labels.note or api.hud.labels.note.widget.hidden,
        "self-explanatory party view has no oversized footer")

    local copy=api.snapshot();copy.profiles.alpha.route[1]="corrupt"
    assert(api.snapshot().profiles.alpha.route[1]=="rooma","snapshots cannot mutate saved profiles")
    assert(api.set_economy("alpha",true));assert(api.snapshot().profiles.beta.economy.enabled)
    api.request("start");h.advance(2.1)
    assert(api.status().started and api.status().elapsed==2)
    assert(api.hud.labels.badge.html:find("Jaskinie grimloków",1,true))
    assert(api.hud.labels.badge.html:find("00:00:02",1,true))
    assert(api.hud.badge.parent==api.hud.root and h.border==44,"active label belongs to the bar without extra console space")
    assert(api.hud.badge.x+api.hud.badge.w<api.hud.labels.pause.x,"run details sit beside the controls")
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
    for _,width in ipairs({320,500,700,1000}) do
        h.width=width;h.emit("sysWindowResizeEvent")
        local terrain=api.hud.labels.badge;local areas=api.hud.labels.areas
        assert(terrain.x>=areas.x+areas.w and terrain.x+terrain.w<api.hud.labels.pause.x,"inline run details do not overlap menus or controls")
        assert(terrain.y+terrain.h<=api.hud.root.h and h.border==180,"run details stay within the existing bar")
    end
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
-- Graphical controls must call the same validated APIs as CLI/menu actions.
do
    local h=fixture();local api=h.api
    api.hud:open("party")
    assert(api.hud.labels.item1_state and api.hud.labels.item2_state,
        "party controls render state badges")
    assert(not api.hud.labels.item1_switch and not api.hud.labels.item1_knob,
        "legacy switch track and knob are not created")
    assert(api.hud.labels.item1_state.html:find("WYŁ.",1,true),
        "disabled protection is shown as a gray badge")
    assert(api.hud.labels.item1_state.css:find("#353F4E",1,true),
        "disabled badge has the neutral background")
    local was=api.tactics.status().on
    api.hud.labels.item1_state.widget.click()
    assert(api.tactics.status().on~=was,"badge toggles the tactic engine")
    assert(api.hud.labels.item1_state.html:find("WŁ.",1,true),
        "enabled protection is displayed as ON")
    assert(api.hud.labels.item1_state.css:find("#2C4B3F",1,true),
        "enabled badge uses the green background")
    api.hud.labels.item1_state.widget.click()
    assert(api.tactics.status().on==was,
        "a second click returns the tactic engine to its previous state")
    local old=api.snapshot().profile.partyAttack
    api.hud.labels.item2_state.widget.click()
    assert(api.snapshot().profile.partyAttack~=old,
        "attack badge uses the existing per-profile command")
    api.hud.labels.item2_state.widget.click()
    assert(api.snapshot().profile.partyAttack==old,
        "attack badge can return to its original state")
    assert(api.hud.labels.item4_state,"party renders a member status chip")
    api.hud.labels.item4.widget.click()
    assert(api.hud.menu=="member","member card opens its details")
    -- Default member configuration has an advanced section.
    for key,item in pairs(api.hud.labels) do
        if item.html and item.html:find("Zaawansowane",1,true) and not item.widget.hidden then
            item.widget.click();break
        end
    end
    assert(api.hud.menu=="member_advanced","advanced controls accessible from member card")
    local before=api.tactics.rows()[1].min_hp
    assert(api.hud.labels.item2_tick0,"HP has a segmented interactive slider")
    api.hud.labels.item2_plus.widget.click()
    assert(api.tactics.rows()[1].min_hp==math.min(100,before+5),"HP increment persists through tactics.configure")
    local load=api.tactics.rows()[1].max_load
    api.hud.labels.item3_minus.widget.click()
    assert(api.tactics.rows()[1].max_load==math.max(0,load-1),"load slider decrements through tactics.configure")
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
