-- Compact ChimeraVIP-style top bar. Party health belongs to Kondycje.
local H={}
-- Obsidian: single palette and explicit control styles shared by every menu.
-- Icons are Unicode glyphs rendered by Qt, not downloaded images or font files.
local P={bg="#151922",panel="#1D2430",card="#222B39",raised="#303B4C",line="#343E50",
    text="#F4F6FA",muted="#C2CCDB",soft="#AEBBD0",mint="#A8DCC2",
    lavender="#C7B9E8",rose="#F0A8B8",yellow="#EFD8A6",green="#315746"}
local ICON={party="☷",shield="◇",attack="⚔",area="⌖",gear="⚙",close="×",
    back="‹",next="›",role="✦",member="◆",npc="◆",player="●",star="★",
    ready="✓",wait="◷",sliders="☷",safety="✚",loot="◇",trade="◆",
    session="◷",map="⌖",reset="↺",play="▶",pause="Ⅱ",stop="■",
    auto="✧",target="◎",support="✚"}
local STYLES={
    base={radius=6,pad=2,font=9},
    bar={radius=0,pad=0,font=10},
    nav={radius=7,pad=3,font=9,hover=P.raised},
    toolbar={radius=9,pad=3,font=12,hover=P.raised},
    danger={radius=9,pad=3,font=12,hover="#593440"},
    panel={radius=10,pad=0,border=P.line},
    title={radius=0,pad=0,font=10,bold=true},
    subtitle={radius=0,pad=0,font=8},
    section={radius=0,pad=1,font=8,bold=true},
    card={radius=8,pad=1,border=P.line},
    row={radius=8,pad=3,hover=P.raised},
    label={radius=0,pad=1,font=9},
    detail={radius=0,pad=1,font=9},
    icon={radius=7,pad=0,font=11,bold=true},
    chip={radius=7,pad=1,font=8,bold=true},
    ["switch-track"]={radius=10,pad=0},
    ["switch-knob"]={radius=8,pad=0},
    ["slider-track"]={radius=5,pad=0},
    ["slider-hit"]={radius=0,pad=0},
    ["slider-thumb"]={radius=8,pad=0,border="#DFFBE9"},
    button={radius=7,pad=1,font=10,hover=P.card},
    footer={radius=0,pad=1,font=8},
    divider={radius=0,pad=0}
}
local function esc(v) return tostring(v or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;") end
local function short(v,n)
    local chars={};for c in tostring(v or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1]=c end
    if #chars<=n then return table.concat(chars) end
    if n<=1 then return "…" end
    local out={};for i=1,math.max(1,n-1) do out[#out+1]=chars[i] end;return table.concat(out).."…"
end
local function clock(n) n=math.max(0,math.floor(tonumber(n) or 0));return string.format("%02d:%02d:%02d",math.floor(n/3600),math.floor(n%3600/60),n%60) end
local ROLES={tank="Obrońca",offtank="Drugi obrońca",standard="Wojownik",asekuracja="Ochrona innych",support="Wsparcie"}
local ROLE_DETAILS={tank="Przejmuje zagrożenia i odciąża sojuszników.",offtank="Pomaga głównemu obrońcy przy przeciążeniu.",standard="Walczy i pomaga, gdy to bezpieczne.",asekuracja="Osłania szczególnie zagrożonych sojuszników.",support="Unika przejmowania przeciwników."}
local ROLE_ORDER={"tank","offtank","standard","asekuracja","support","auto"}
local TASKS={"auto","self","protect","support","reserve"}
local TASK_LABEL={auto="Automatycznie",self="Chroń mnie",protect="Chroń wybraną osobę",support="Wspieraj mój cel",reserve="Rezerwa"}
function H.new(ctx,patrol,tactics,stop)
    local self={labels={},widgets={},menu=nil,page=1,shown=true,destroyed=false}
    local settings=ctx:saved("hud",{});if type(settings)~="table" then settings={} end
    self.shown=settings.visible~=false
    ctx.state.hud_generation=(ctx.state.hud_generation or 0)+1
    local prefix="chimeraxp."..ctx.state.hud_generation.."."
    -- A single, dependable bar height; the old "Większy pasek" toggle was cosmetic.
    settings.large=nil
    local height=44
    local before,owned
    local function available() return type(Geyser)=="table" and type(Geyser.Container)=="table" and type(Geyser.Label)=="table" end
    local function screen()
        if type(getMainWindowSize)=="function" then local w,h=getMainWindowSize();return math.max(1,tonumber(w) or 1000),math.max(1,tonumber(h) or 800) end
        return 1000,800
    end
    local function border()
        if type(getBorderTop)=="function" then local ok,v=pcall(getBorderTop);if ok then return tonumber(v) or 0 end end
        return 0
    end
    local function release()
        if owned and type(setBorderTop)=="function" and (type(getBorderTop)~="function" or border()==owned) then setBorderTop(before or 0) end
        owned=nil
    end
    local function save() settings.visible=self.shown;ctx:save("hud",settings) end
    local function widget(key,parent,x,y,w,h,text,tint,background,fn,html_override,style)
        local item=self.labels[key]
        local name=prefix..key
        if not item then
            item={widget=Geyser.Label:new({name=name,x=x,y=y,width=w,height=h},parent),parent=parent}
            self.labels[key]=item;self.widgets[#self.widgets+1]=key
        else
            if item.x~=x or item.y~=y then item.widget:move(x,y) end
            if item.w~=w or item.h~=h then item.widget:resize(w,h) end
        end
        item.x,item.y,item.w,item.h=x,y,w,h
        local st=STYLES[style or "base"] or STYLES.base
        local bg=background or P.panel
        local css="QLabel {background:"..bg..";color:"..(tint or P.text)
            ..";font-family:'"..(style=="icon" and "Segoe UI Symbol" or "Segoe UI")
            .."';font-size:"..(st.font or 10).."pt;font-weight:"..(st.bold and "600" or "400")
            ..";border:"..(st.border and "1px solid "..st.border or "0")
            ..";border-radius:"..(st.radius or 0).."px;padding:"..(st.pad or 0).."px;}"
        if fn and st.hover then
            css=css.." QLabel:hover {background:"..st.hover..";}"
        end
        local html=html_override or "<font color='"..(tint or P.text).."'>"..esc(text).."</font>"
        if item.css~=css then item.widget:setStyleSheet(css);item.css=css end
        if item.html~=html then item.widget:echo(html);item.html=html end
        local callback=function() if not self.destroyed and fn then fn() end end
        if type(item.widget.setClickCallback)=="function" then item.widget:setClickCallback(callback)
        elseif type(setLabelClickCallback)=="function" then setLabelClickCallback(name,callback) end
        if type(item.widget.show)=="function" then item.widget:show() end
        self.used[key]=true
    end
    local function prefill(command)
        if type(setCmdLine)=="function" then setCmdLine("/exp "..command) else ctx.log.info("/exp "..command) end
    end
    local function request(name,arg) patrol.request(name,arg);self:render() end
    function self:open(name)
        if self.destroyed then return end
        if not available() then return false end
        self.shown=true;save()
        -- An `and nil or name` expression cannot close a Lua menu.
        if self.menu==name or (self.menu and self.anchor==name) then self.menu=nil else self.menu=name end
        self.page=1
        if name=="areas" then self.nearby=nil end
        if name=="party" or name=="tactics" or name=="areas" or name=="settings" then self.anchor=name end
        if name~="member" and name~="roles" and name~="targets" and name~="member_advanced" then self.selected=nil end
        self:render()
    end
    function self:visible(value) if self.destroyed then return false end;self.shown=value~=false;self.menu=nil;save();self:render() end
    local function find_row(rows,id) for _,r in ipairs(rows) do if r.id==id then return r end end end
    local function items_for(snap,rows,ts)
        local items={};local title="ChimeraXP";local note=""
        local function add(text,fn,tint,kind,extra)
            local item={text=text,fn=fn,tint=tint,kind=kind}
            for key,value in pairs(extra or {}) do item[key]=value end
            items[#items+1]=item
        end
        local function toggle(label,value,fn,description,icon)
            add(label,fn,P.text,"toggle",{enabled=value==true,description=description,
                icon=icon or ICON.shield})
        end
        local function slider(label,value,minimum,maximum,step,fn,unit)
            add(label,fn,P.text,"slider",{value=value,min=minimum,max=maximum,step=step,
                change=fn,unit=unit or ""})
        end
        local selected=find_row(rows,self.selected)
        if (self.menu=="member" or self.menu=="roles" or self.menu=="targets" or self.menu=="member_advanced") and not selected then self.menu="party" end
        local p=snap.profile;local st=snap.status
        if self.menu=="party" then
            title="Drużyna"
            toggle("Automatyczna ochrona",ts.on,function() tactics.toggle(not ts.on) end,
                "Zasłania zagrożonych członków drużyny",ICON.shield)
            if p then
                toggle("Wspólny cel ataku",p.partyAttack,
                    function() request("druzyna",p.partyAttack and "off" or "on") end,
                    "Dowódca wydaje rozkaz ataku podczas expienia",ICON.attack)
            else add(ICON.attack.." Wspólny cel: wybierz expowisko",nil,P.muted,"hint") end
            add("CZŁONKOWIE DRUŻYNY",nil,P.lavender,"section")
            for _,r in ipairs(rows) do
                local id=r.id
                local role=ROLES[r.role] or "Automatycznie"
                local icon=r.self and ICON.star or r.kind=="npc" and ICON.npc or ICON.player
                add(r.name,
                    function() self.selected=id;self.menu="member";self.page=1;self:render() end,
                    r.enabled and P.text or P.muted,"member",
                    {role=role,active=r.enabled,cooldown=r.cooldown or 0,portrait=icon})
            end
            if #rows==0 then add("Oczekiwanie na aktualny skład GMCP.",nil,P.yellow) end
            add("Dodatkowe ustawienia drużyny",function()
                self.menu="tactics";self.page=1;self:render()
            end,P.lavender,"action",{icon=ICON.gear})
            note=""
        elseif self.menu=="member" then
            title=(selected and selected.name or "Postać").." · zachowanie"
            add("Wróć do drużyny",function() self.menu="party";self:render() end,P.muted,"back",{icon=ICON.back})
            if selected then
                local id=selected.id
                toggle("Automatyczna ochrona tej postaci",selected.enabled,
                    function() tactics.configure(id,"enabled",not selected.enabled,selected) end,
                    "Pozostałe postacie zachowują swoje ustawienia")
                add("Rola: "..(ROLES[selected.role] or "Automatycznie"),
                    function() self.menu="roles";self.page=1;self:render() end,
                    P.lavender,"action",{icon=ICON.role})
                if selected.slot then
                    add("Zadanie pachołka: "..(TASK_LABEL[selected.task] or "Automatycznie").."  ↻",
                        function()
                            local current=1
                            for i,v in ipairs(TASKS) do if v==selected.task then current=i end end
                            local value=TASKS[current%#TASKS+1]
                            tactics.task(id,value,selected)
                            if value=="protect" then self.menu="targets";self.page=1 end
                            self:render()
                        end)
                end
                add("Kogo chronić: "..(selected.target_name or "decyduje automat"),
                    function() self.menu="targets";self.page=1;self:render() end,
                    P.text,"action",{icon=ICON.shield})
                add("Zaawansowane: HP i limit zagrożeń",
                    function() self.menu="member_advanced";self.page=1;self:render() end,
                    P.lavender,"action",{icon=ICON.sliders})
                if selected.kind=="npc" and not selected.slot then
                    add("Przypisz jako pachołka 1",function() tactics.bind(1,id,selected) end)
                    add("Przypisz jako pachołka 2",function() tactics.bind(2,id,selected) end)
                end
            end
            note="Rola dobiera domyślne progi. Szczegóły są opcjonalne."
        elseif self.menu=="member_advanced" then
            title=(selected and selected.name or "Postać").." · bezpieczeństwo"
            add("Wróć do postaci",function() self.menu="member";self:render() end,P.muted,"back",{icon=ICON.back})
            if selected then
                local id=selected.id
                slider("Minimalne HP do manewru",selected.min_hp,selected.self and 40 or 50,100,5,
                    function(v) tactics.configure(id,"min_hp",v,selected) end,"%")
                slider("Limit przejmowanych przeciwników",selected.max_load,0,5,1,
                    function(v) tactics.configure(id,"max_load",v,selected) end,"")
            end
            note="Progi dotyczą manewrów taktycznych, nie poziomu HP na HUD."
        elseif self.menu=="roles" then
            title=(selected and selected.name or "Postać").." · wybierz rolę"
            add("‹ Wróć do postaci",function() self.menu="member";self:render() end,P.muted)
            if selected then
                local id=selected.id
                for _,role in ipairs(ROLE_ORDER) do
                    if role~="auto" or not selected.self then
                        local desc=ROLE_DETAILS[role] or "Bez przypisanej roli."
                        add(ROLES[role] or "Automatycznie",
                            function() tactics.configure(id,"role",role,selected);self.menu="member";self:render() end,
                            P.text,"choice",{selected=selected.role==role,description=desc,
                                icon=(role=="tank" or role=="offtank") and ICON.shield or
                                    role=="support" and ICON.support or role=="asekuracja" and ICON.safety or ICON.attack})
                    end
                end
            end
            note="Zmiana roli ustawia też domyślne progi bezpieczeństwa."
        elseif self.menu=="targets" then
            title=(selected and selected.name or "Postać").." · kogo chronić"
            add("‹ Wróć do postaci",function() self.menu="member";self:render() end,P.muted)
            if selected then
                local id=selected.id
                add("Automatyczny wybór",function() tactics.configure(id,"target_id",nil,selected);self.menu="member";self:render() end,
                    P.text,"choice",{selected=not selected.target_id,icon=ICON.auto})
                for _,r in ipairs(rows) do if r.id~=id then
                    local target=r.id
                    add("Chroń: "..r.name,function() tactics.configure(id,"target_id",target,selected);self.menu="member";self:render() end,
                        P.text,"choice",{selected=selected.target_id==target,icon=ICON.shield})
                end end
            end
        elseif self.menu=="tactics" then
            title="Taktyka drużyny"
            add("Wróć do drużyny",function() self.menu="party";self:render() end,P.muted,"back",{icon=ICON.back})
            toggle("Automatyczna ochrona",ts.on,function() tactics.toggle(not ts.on) end,
                "Reaguje na zagrożenia drużyny",ICON.shield)
            for _,entry in ipairs({{"team_orders","Ochrona innych graczy"},
                {"team_broadcast","Wspólna zasłona drużyny"},
                {"retreat","Wycofanie za sojusznika"},
                {"mass","Zasłona kilku wrogów"}}) do
                local key=entry[1]
                toggle(entry[2],ts[key],function() tactics.option(key,not ts[key]) end,
                    nil,key=="team_orders" and ICON.party or key=="team_broadcast" and ICON.shield
                        or key=="retreat" and ICON.back or ICON.safety)
            end
            add("Stan silnika: "..ts.phase,nil,P.muted)
            note="Zaawansowane opcje zmieniają manewry osłony, nie komendy ataku."
        elseif self.menu=="areas" or self.menu=="allareas" then
            local all=self.menu=="allareas"
            title=all and "Wszystkie expowiska" or "Najbliższe expowiska"
            local profiles={}
            if all then
                for key,v in pairs(snap.profiles) do profiles[#profiles+1]={key=key,value=v} end
                table.sort(profiles,function(a,b)
                    if a.value.name~=b.value.name then return a.value.name<b.value.name end
                    return a.key<b.key
                end)
            else
                if not self.nearby then self.nearby=patrol.nearest_profiles(3) end
                for _,near in ipairs(self.nearby) do
                    if snap.profiles[near.key] then profiles[#profiles+1]={key=near.key,value=snap.profiles[near.key],cost=near.cost} end
                end
            end
            for _,entry in ipairs(profiles) do
                local key,name=entry.key,entry.value.name
                add((st.selected==key and "● " or "○ ")..name.." · "..#entry.value.route.." lok."..(entry.cost and " · "..entry.cost.." kr." or ""),function()
                    if st.started then ctx.log.warn("Zatrzymaj AutoEXP przed zmianą terenu.") else request("wybierz",name) end
                end)
                local earn=entry.value.economy and entry.value.economy.enabled
                items[#items].economy={enabled=earn,fn=function() patrol.set_economy(key,not earn);self:render() end}
            end
            if #profiles==0 then add(all and "Brak zapisanych terenów." or "Brak osiągalnych terenów na mapie.",nil,P.muted) end
            if not all then
                add("Wszystkie expowiska…",function() self.menu="allareas";self.page=1;self:render() end,P.lavender)
                add(st.started and (st.paused and "▶ Wznów AutoEXP" or "Ⅱ Wstrzymaj AutoEXP") or "▶ Uruchom AutoEXP",function() request(st.started and (st.paused and "wznow" or "pauza") or "start") end,P.mint)
            end
            note="Kliknij teren, aby wybrać. Zarobek przełączysz obok nazwy."
        elseif self.menu=="settings" then
            title="Ustawienia ChimeraXP"
            for _,entry in ipairs({{"combat","Walka i cele",ICON.attack},{"safety","Schronienie i powrót",ICON.safety},
                {"loot","Łupy",ICON.loot},{"trade","Auto-zarobek",ICON.trade},
                {"profiles","Zarządzanie terenami",ICON.map},{"session","Sesja i komunikaty",ICON.session}}) do
                local key=entry[1]
                add(entry[2],function() self.menu=key;self.page=1;self:render() end,
                    P.text,"action",{icon=entry[3]})
            end
            note="Zmiany wyglądu nie zmieniają zachowania automatyki."
        elseif self.menu=="profiles" then
            title="Zarządzanie terenami"
            add("Mapuj nowy teren…",function() prefill("mapuj ") end)
            add("Zakończ mapowanie",function() request("mapuj",p and p.name or "") end)
            add("Zmień nazwę wybranego…",function() prefill("nazwa ") end)
            add("Anuluj mapowanie",function() request("mapuj-") end)
            add("Importuj poprzednie profile",function() request("import") end)
            add("Podgląd decyzji bez wysyłania",function() request("test") end)
            note="Tekstowe nazwy uzupełnij w linii komend."
        elseif self.menu=="combat" then
            title="Cele i zasady walki"
            add("Cele: "..(p and table.concat(p.targets,", ") or "brak"))
            add("Dodaj cel…",function() prefill("cel ") end);add("Usuń cel…",function() prefill("cel- ") end)
            add("Unikane: "..(p and table.concat(p.avoid,", ") or "brak"))
            add("Dodaj unikany NPC…",function() prefill("unikaj ") end);add("Usuń unikany NPC…",function() prefill("unikaj- ") end)
            add("Limit NPC: "..(p and p.rules.maxEnemies or "—").."  +",function() request("limit+") end)
            add("Zmniejsz limit NPC",function() request("limit-") end)
        elseif self.menu=="safety" then
            title="Schronienie i powrót"
            add("Schronienie: "..(p and p.safeRoom or "brak"))
            add("Ustaw obecną lokację jako schronienie",function() request("bezpieczna") end)
            add("HP odwrót / powrót: "..(p and p.rules.retreatHP.." / "..p.rules.returnHP or "—").."%")
            add("Zmień progi…",function() prefill("hp ") end)
            add("Odnowa lokacji…",function() prefill("odnowa ") end)
            note="Powrót do schronienia to ruch; wycofanie w szyku to osobny manewr."
        elseif self.menu=="loot" then
            title="Łupy z expowiska"
            add("Lista: "..(p and table.concat(p.loot or {},", ") or "brak"))
            add("Dodaj łup…",function() prefill("lup dodaj ") end)
            add("Usuń łup…",function() prefill("lup usun ") end)
            note="Zbieraniem ma sterować jeden wykonawca; nie dubluj oficjalnego /zbieranie."
        elseif self.menu=="trade" then
            title="Auto-zarobek"
            local earn=p and p.economy and p.economy.enabled
            add("Zarobek: "..(earn and "WŁ." or "WYŁ."),function() if st.selected then patrol.set_economy(st.selected,not earn);self:render() end end)
            add("Próg obciążenia: "..(p and p.rules.economyLoadThreshold or 75).."%")
            add("Zmień próg…",function() prefill("zarobek prog ") end)
            add("Zmień tempo operacji…",function() prefill("zarobek tempo ") end)
            add("Sprawdź trasę sklep → bank → powrót",function() request("zarobek trasa") end)
            add("Diagnostyka handlu",function() request("zarobek diagnoza") end)
            note="Sprzedaż według listy łupów profilu: "..table.concat(p and p.loot or {},", ")..". Obejmuje niesione przedmioty tych kategorii."
        elseif self.menu=="session" then
            title="Sesja wyprawy"
            add("Teren: "..(p and p.name or "brak"));add("Czas działania: "..clock(st.elapsed))
            add("XP z komunikatów: +"..tostring(st.xp or 0))
            add("Stan: "..(st.economy and "HANDEL / "..st.economy or st.phase))
            add("Ostatnie zdarzenia",function() request("log") end)
            for _,mode in ipairs({"quiet","normal","debug"}) do
                add("Komunikaty: "..mode..(snap.verbosity==mode and " ✓" or ""),function() request("glosnosc",mode) end)
            end
            note=st.reason
        end
        return items,title,note
    end
    local function draw()
        if self.destroyed then return end
        if not self.shown then
            if self.root then self.root:hide();self.overlay:hide();if self.catalog then self.catalog:hide() end end
            release();return
        end
        if not available() then return end
        local w,h=screen()
        if owned and type(getBorderTop)=="function" and border()~=owned then
            self.shown=false;self.menu=nil
            ctx.log.warn("Inny dodatek zmienił górny margines. HUD ChimeraXP ukryty; /exp hud on przywraca pasek.")
            patrol.pause("Konflikt układu HUD: przejmij sterowanie.")
            tactics.stop("Konflikt układu HUD.")
            if self.root then self.root:hide();self.overlay:hide();if self.catalog then self.catalog:hide() end end
            release();return
        end
        if not self.root then
            before=border()
            self.root=Geyser.Container:new({name=prefix.."bar",x=0,y=0,width="100%",height=height})
            self.overlay=Geyser.Container:new({name=prefix.."overlay",x=0,y=height,width=w,height=1})
        end
        local snap=patrol.snapshot();local st=snap.status;local ts=tactics.status();local rows=tactics.rows()
        if type(setBorderTop)=="function" then
            if not owned then before=border() end
            -- The border reserves console space; it is not a Geyser y offset.
            owned=math.max(before or 0,height)
            if border()~=owned then setBorderTop(owned) end
        end
        self.root:move(0,0);self.root:resize(w,height)
        self.used={}
        widget("background",self.root,0,0,w,height,"",P.text,P.bg,nil,nil,"bar")
        local small=w<500
        local tight=w<390 or (st.started and w<700)
        local cw=32
        cw=math.min(cw,math.max(3,math.floor(w*.09)))
        local right=w-8-cw*3
        local y=5;local bh=height-10
        local widths=tight and {28,40,44} or small and {83,90,72} or {128,110,120}
        local scale=math.min(1,math.max(.01,(right-20)/(widths[1]+widths[2]+widths[3])))
        local x=8
        local function nav(key,symbol,text,width,indicator)
            width=math.max(1,math.floor(width*scale))
            local selected=self.menu and self.anchor==key
            local label=tight and symbol or (small and short(text,9) or text)
            local html="<font color='"..(indicator or P.lavender).."'>"..esc(symbol).."</font>"
                ..(tight and "" or "  <font color='"..P.text.."'>"..esc(label).."</font>")
                ..(tight and "" or " <font color='"..P.soft.."'>⌄</font>")
            widget(key,self.root,x,y,width,bh,label,P.text,
                selected and P.raised or P.bg,function() self:open(key) end,html,"nav")
            x=x+width+4
        end
        local xpcolor=not st.started and P.muted or st.paused and P.yellow or P.mint
        local tacticscolor=not ts.on and P.muted or
            ((st.started and st.paused) or ts.phase=="WSTRZYMANA") and P.yellow or P.mint
        nav("party",ICON.party,"Drużyna",widths[1],nil)
        nav("tactics",ICON.shield,"Ochrona",widths[2],tacticscolor)
        nav("areas",ICON.area,"Expowiska",widths[3],xpcolor)
        widget("pause",self.root,right,y,cw-3,bh,
            (not st.started or st.paused) and ICON.play or ICON.pause,
            st.paused and P.yellow or P.mint,P.card,
            function() request(not st.started and "start" or st.paused and "wznow" or "pauza") end,nil,"toolbar")
        widget("stop",self.root,right+cw,y,cw-3,bh,ICON.stop,
            P.rose,"#382A35",stop,nil,"danger")
        widget("settings",self.root,right+cw*2,y,cw-3,bh,ICON.gear,
            P.text,self.menu and self.anchor=="settings" and P.raised or P.bg,
            function() self:open("settings") end,nil,"toolbar")
        if st.started then
            local name=snap.profile and snap.profile.name or "Brak terenu"
            local earn=snap.profile and snap.profile.economy and snap.profile.economy.enabled
            local label=st.paused and "PAUZA" or st.emergency and "ODWRÓT" or
                st.phase=="COMBAT" and "WALKA" or st.economy and "HANDEL" or
                st.phase=="LOOTING" and "ŁUPY" or "PATROL"
            local tint=st.paused and P.yellow or st.emergency and P.rose or
                st.phase=="COMBAT" and P.mint or P.lavender
            local space=math.max(1,right-x-12)
            local chipw=w>=850 and space>230 and 82 or 0
            local badgewidth=math.max(1,space-chipw-(chipw>0 and 8 or 0))
            local badge_x=right-badgewidth-8
            if chipw>0 then
                widget("stage",self.root,badge_x-chipw-8,y+4,chipw,bh-8,
                    "● "..label,tint,P.card,
                    function() self:open("session") end,nil,"chip")
            end
            local reserved=earn and w>=960 and 13 or 0
            local clipped=short(name,math.max(1,math.floor((badgewidth-106)/7)-reserved))
            local html="<font color='"..P.text.."'><b>"..esc(clipped).."</b></font>"
                .."  <font face='Consolas' color='"..P.mint.."'>"..clock(st.elapsed).."</font>"
                ..(earn and w>=960 and "<font color='"..P.soft.."'> · zarobek</font>" or "")
                ..(chipw==0 and " <font color='"..tint.."'>· "..esc(label).."</font>" or "")
            widget("badge",self.root,badge_x,y,badgewidth,bh,"",tint,P.bg,
                function() self:open("session") end,html,"nav")
            self.badge=self.labels.badge.widget
        end
        if self.menu then
            local items,title,note=items_for(snap,rows,ts)
            local catalog=self.menu=="allareas"
            local decorated=self.menu=="party" or self.menu=="member" or self.menu=="member_advanced"
                or self.menu=="tactics" or self.menu=="settings"

            -- Keep the entire party panel compact even on high-DPI Qt displays.
            local mw=math.max(1,math.min(catalog and 620 or decorated and 420 or 440,w-16))
            local function item_height(item)
                if item.kind=="section" then return 25 end
                if item.kind=="toggle" then return 43 end
                if item.kind=="member" then return 40 end
                if item.kind=="slider" then return 76 end
                if item.kind=="choice" and item.description then return 48 end
                return 35
            end
            local header_height=46
            local footer_height=note~="" and 24 or 8
            local fixed_height=math.max(1,math.min(h-height-12,catalog and 490 or decorated and 450 or 440))
            -- Compute pages using real item heights instead of reserving a full
            -- 59-pixel row for short headings. No scrolling/console resizing.
            local maxcontent=math.max(10,fixed_height-header_height-footer_height-30)
            local pages={{}};local used=0
            for i,item in ipairs(items) do
                local rh=item_height(item)
                if used+rh>maxcontent and #pages[#pages]>0 then
                    pages[#pages+1]={};used=0
                end
                pages[#pages][#pages[#pages]+1]={index=i,item=item,height=rh}
                used=used+rh
            end
            self.page=math.min(math.max(1,self.page),#pages)
            local visible=pages[self.page]
            local content_height=0
            for _,entry in ipairs(visible) do content_height=content_height+entry.height end
            local mh=math.max(1,math.min(fixed_height,header_height+content_height+
                (#pages>1 and 30 or 0)+footer_height))
            local anchor=self.labels[self.anchor or "party"]
            local mx=math.max(8,math.min(anchor and anchor.x or 8,w-mw-8))
            if catalog and not self.catalog then
                self.catalog=Geyser.Container:new({name=prefix.."catalog",x=0,y=0,width=mw,height=mh})
            end
            local panel=catalog and self.catalog or self.overlay
            if catalog then
                self.overlay:hide()
                mx=math.max(8,math.floor((w-mw)/2))
            elseif self.catalog then self.catalog:hide() end
            panel:move(mx,catalog and math.max(height+8,math.floor((h-mh)/2)) or height+5)
            panel:resize(mw,mh)
            local function menu_widget(key,xx,yy,ww,hh,text,tint,bg,fn,html,style)
                widget((catalog and "catalog_" or "")..key,panel,xx,yy,
                    math.max(1,ww),math.max(1,hh),text,tint,bg,fn,html,style)
            end
            local menu_meta={
                party=ICON.party,member=ICON.member,member_advanced=ICON.sliders,
                roles=ICON.role,targets=ICON.target,tactics=ICON.shield,
                areas=ICON.area,allareas=ICON.map,settings=ICON.gear,
                combat=ICON.attack,safety=ICON.safety,loot=ICON.loot,
                trade=ICON.trade,profiles=ICON.map,session=ICON.session
            }
            menu_widget("menu_bg",0,0,mw,mh,"",P.text,P.panel,nil,nil,"panel")
            menu_widget("header_icon",12,10,24,24,menu_meta[self.menu] or ICON.gear,
                P.lavender,P.raised,nil,nil,"icon")
            menu_widget("menu_title",44,9,mw-84,26,title,P.text,P.panel,nil,
                "<font color='"..P.text.."'><b>"..esc(short(title,36)).."</b></font>","title")
            menu_widget("menu_close",mw-36,10,24,24,ICON.close,P.muted,P.card,
                function() self.menu=nil;self:render() end,nil,"button")
            menu_widget("header_line",10,40,mw-20,1,"",P.line,P.line,nil,nil,"divider")
            local yy=header_height
            for index,entry in ipairs(visible) do
                local item=entry.item;local rh=entry.height;local fn=item.fn
                local key="item"..index
                local ew=item.economy and 90 or 0
                local mainw=mw-16-(ew>0 and ew+5 or 0)
                if item.kind=="section" then
                    menu_widget(key,15,yy+4,mainw-12,19,item.text,
                        P.lavender,P.panel,nil,
                        "<font color='"..P.lavender.."'><b>"..esc(item.text).."</b></font>","section")
                elseif item.kind=="toggle" then
                    local active=item.enabled
                    menu_widget(key.."_bg",8,yy+2,mw-16,rh-4,"",P.text,P.card,fn,nil,"card")
                    menu_widget(key.."_icon",16,yy+10,23,23,item.icon or ICON.shield,
                        active and P.mint or P.muted,P.raised,fn,nil,"icon")
                    local labelw=math.max(1,mw-104)
                    local maxchars=math.max(7,math.floor(labelw/6.8))
                    local html="<font color='"..P.text.."'><b>"..esc(short(item.text,maxchars))..
                        "</b></font>"..
                        (item.description and "<br><font color='"..P.muted.."'>"..
                            esc(short(item.description,maxchars)).."</font>" or "")
                    menu_widget(key,46,yy+5,labelw,rh-10,item.text,
                        P.text,P.card,fn,html,"detail")
                    local tx=mw-54
                    menu_widget(key.."_switch",tx,yy+12,35,20,"",
                        active and P.mint or P.muted,
                        active and P.green or "#485465",fn,nil,"switch-track")
                    menu_widget(key.."_knob",tx+(active and 18 or 3),yy+15,14,14,"",
                        P.text,active and "#D7F6E6" or "#D2D9E3",fn,nil,"switch-knob")
                elseif item.kind=="member" then
                    local inactive=not item.active
                    local ready=not inactive and (item.cooldown or 0)<=0
                    local accent=inactive and P.soft or ready and P.mint or P.yellow
                    local status=inactive and "WYŁ." or ready and ICON.ready.." gotowy"
                        or ICON.wait.." "..tostring(item.cooldown).." s"
                    menu_widget(key.."_bg",8,yy+2,mw-16,rh-4,"",P.text,P.card,fn,nil,"card")
                    menu_widget(key.."_accent",9,yy+8,2,rh-16,"",accent,accent,nil,nil,"divider")
                    menu_widget(key.."_icon",16,yy+8,24,24,item.portrait or ICON.member,
                        P.lavender,P.raised,fn,nil,"icon")
                    local textw=math.max(1,mw-149)
                    local html="<font color='"..(inactive and P.muted or P.text).."'><b>"..
                        esc(short(item.text,math.max(6,math.floor(textw/6.7)))).."</b></font>"..
                        "<br><font color='"..P.muted.."'>"..
                        esc(short(item.role,math.max(6,math.floor(textw/6.7)))).."</font>"
                    menu_widget(key,47,yy+4,textw,rh-8,item.text,
                        P.text,P.card,fn,html,"detail")
                    menu_widget(key.."_state",mw-101,yy+9,78,22,status,
                        accent,P.card,fn,nil,"chip")
                    menu_widget(key.."_chevron",mw-22,yy+10,12,19,ICON.next,
                        P.soft,P.card,fn,nil,"subtitle")
                elseif item.kind=="slider" then
                    local minimum,maximum,step=item.min,item.max,item.step
                    local value=math.max(minimum,math.min(maximum,tonumber(item.value) or minimum))
                    local steps=math.max(1,math.floor((maximum-minimum)/step))
                    menu_widget(key.."_bg",8,yy+2,mw-16,rh-4,"",P.text,P.card,nil,nil,"card")
                    menu_widget(key.."_icon",16,yy+8,21,21,ICON.sliders,
                        P.lavender,P.raised,nil,nil,"icon")
                    menu_widget(key,43,yy+7,mw-125,25,item.text,P.text,P.card,nil,
                        "<font color='"..P.text.."'><b>"..
                        esc(short(item.text,math.max(8,math.floor((mw-134)/7))))..
                        "</b></font>","label")
                    menu_widget(key.."_number",mw-74,yy+7,55,23,
                        tostring(value)..item.unit,P.mint,P.card,nil,nil,"chip")
                    local track_x=49;local track_width=math.max(12,mw-100)
                    local track_y=yy+47
                    local pct=math.max(0,math.min(1,(value-minimum)/math.max(1,maximum-minimum)))
                    menu_widget(key.."_track",track_x,track_y,track_width,6,"",
                        P.muted,"#445167",nil,nil,"slider-track")
                    if pct>0 then
                        menu_widget(key.."_fill",track_x,track_y,
                            math.max(2,math.floor(track_width*pct)),6,"",
                            P.mint,P.green,nil,nil,"slider-track")
                    end
                    for i=0,steps do
                        local target=minimum+i*step
                        local lx=track_x+math.floor(i*track_width/(steps+1))
                        local rx=track_x+math.floor((i+1)*track_width/(steps+1))
                        menu_widget(key.."_tick"..i,lx,track_y-8,
                            math.max(1,rx-lx),23,"",P.text,"transparent",
                            function() item.change(target) end,nil,"slider-hit")
                    end
                    local knob_x=math.max(track_x,math.min(track_x+track_width-14,
                        track_x+math.floor(track_width*pct)-7))
                    menu_widget(key.."_thumb",knob_x,track_y-4,14,14,"",
                        P.mint,"#E2FAEC",function() item.change(value) end,nil,"slider-thumb")
                    menu_widget(key.."_minus",14,yy+38,24,24,"−",P.text,P.raised,
                        function() item.change(math.max(minimum,value-step)) end,nil,"button")
                    menu_widget(key.."_plus",mw-38,yy+38,24,24,"+",P.text,P.raised,
                        function() item.change(math.min(maximum,value+step)) end,nil,"button")
                else
                    local ischoice=item.kind=="choice"
                    local isback=item.kind=="back"
                    local tint=item.tint or P.text
                    local section_icons={
                        areas=ICON.area,allareas=ICON.map,combat=ICON.attack,
                        safety=ICON.safety,loot=ICON.loot,trade=ICON.trade,
                        profiles=ICON.map,session=ICON.session,settings=ICON.gear
                    }
                    local symbol=item.icon or (ischoice and ICON.role or isback and ICON.back or
                        item.kind=="hint" and ICON.auto or section_icons[self.menu] or ICON.next)
                    local hasdetail=ischoice and item.description
                    local selected=item.selected==true
                    menu_widget(key.."_bg",8,yy+2,mw-16,rh-4,"",
                        P.text,selected and "#283B3D" or P.card,fn,nil,"card")
                    menu_widget(key.."_icon",15,yy+7,22,rh-14,symbol,
                        selected and P.mint or P.lavender,P.raised,fn,nil,"icon")
                    local labelw=math.max(1,mainw-54)
                    local maxchars=math.max(6,math.floor(labelw/7))
                    local html="<font color='"..tint.."'><b>"..
                        esc(short(item.text,maxchars)).."</b></font>"..
                        (hasdetail and "<br><font color='"..P.muted.."'>"..
                            esc(short(item.description,maxchars)).."</font>" or "")
                    menu_widget(key,43,yy+4,labelw,rh-8,
                        item.text,tint,selected and "#283B3D" or P.card,fn,html,
                        hasdetail and "detail" or "label")
                    if item.economy then
                        menu_widget(key.."_economy",mw-12-ew,yy+7,ew,rh-14,
                            (item.economy.enabled and "● " or "○ ")..
                                (item.economy.enabled and "Zarobek" or "Bez zarobku"),
                            item.economy.enabled and P.mint or P.muted,
                            P.panel,item.economy.fn,nil,"chip")
                    elseif selected or fn then
                        menu_widget(key.."_end",mw-27,yy+8,17,rh-16,
                            selected and ICON.ready or (isback and "" or ICON.next),
                            selected and P.mint or P.soft,P.card,fn,nil,"subtitle")
                    end
                end
                yy=yy+rh
            end
            if #pages>1 then
                menu_widget("previous",12,yy+2,27,24,ICON.back,P.text,P.card,
                    function() self.page=math.max(1,self.page-1);self:render() end,nil,"button")
                menu_widget("page",43,yy+2,mw-86,24,
                    self.page.." / "..#pages,P.muted,P.panel,nil,nil,"footer")
                menu_widget("next",mw-39,yy+2,27,24,ICON.next,P.text,P.card,
                    function() self.page=math.min(#pages,self.page+1);self:render() end,nil,"button")
            end
            if note~="" and mh>=header_height+footer_height then
                menu_widget("footer_line",10,mh-24,mw-20,1,"",P.line,P.line,nil,nil,"divider")
                menu_widget("note",13,mh-22,mw-26,20,
                    short(note,math.max(1,math.floor((mw-36)/6.5))),
                    P.muted,P.panel,nil,nil,"footer")
            end
            panel:show();if type(panel.raiseAll)=="function" then panel:raiseAll() end
        else self.overlay:hide();if self.catalog then self.catalog:hide() end end
        for key,item in pairs(self.labels) do if not self.used[key] and type(item.widget.hide)=="function" then item.widget:hide() end end
        self.root:show()
    end
    function self:render()
        if self.destroyed or self.rendering then return end
        self.rendering=true
        local ok,err=pcall(draw)
        self.rendering=false
        if not ok then error(err,0) end
    end
    ctx:on("sysWindowResizeEvent",function() self:render() end)
    ctx:on("chimera.group.state",function() self:render() end)
    ctx:on("chimera.room.entities",function() self:render() end)
    ctx:on("chimera.room.changed",function() self.nearby=nil;self:render() end)
    ctx:cleanup(function()
        self.destroyed=true;release()
        for _,item in pairs(self.labels) do pcall(function() if item.widget.delete then item.widget:delete() elseif type(deleteLabel)=="function" then deleteLabel(item.widget.name) end end) end
        for _,container in ipairs({self.root,self.overlay,self.catalog}) do if container then pcall(function() container:hide();if container.delete then container:delete() end end) end end
    end)
    self:render()
    return self
end
return H
