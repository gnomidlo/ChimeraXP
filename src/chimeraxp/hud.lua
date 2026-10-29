-- Compact ChimeraVIP-style top bar. Party health belongs to Kondycje.
local H={}
local P={bg="#181C26",panel="#232938",raised="#2E3749",text="#D8DCE6",muted="#AEB6C5",
    mint="#A8DCC2",lavender="#C7B9E8",rose="#F0A8B8",yellow="#EFD8A6"}
local function esc(v) return tostring(v or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;") end
local function short(v,n)
    local chars={};for c in tostring(v or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1]=c end
    if #chars<=n then return table.concat(chars) end
    local out={};for i=1,math.max(1,n-1) do out[#out+1]=chars[i] end;return table.concat(out).."…"
end
local function clock(n) n=math.max(0,math.floor(tonumber(n) or 0));return string.format("%02d:%02d:%02d",math.floor(n/3600),math.floor(n%3600/60),n%60) end
local ROLES={tank="Tank",offtank="Off tank",standard="Standard",asekuracja="Asekuracja",support="Support"}
local ROLE_ORDER={"tank","offtank","standard","asekuracja","support","auto"}
local TASKS={"auto","self","protect","support","reserve"}
local TASK_LABEL={auto="Automatycznie",self="Chroń mnie",protect="Chroń wybraną osobę",support="Wspieraj mój cel",reserve="Rezerwa"}
function H.new(ctx,patrol,tactics,stop)
    local self={labels={},widgets={},menu=nil,page=1,shown=true,destroyed=false}
    local settings=ctx:saved("hud",{});if type(settings)~="table" then settings={} end
    self.shown=settings.visible~=false
    ctx.state.hud_generation=(ctx.state.hud_generation or 0)+1
    local prefix="chimeraxp."..ctx.state.hud_generation.."."
    local height=settings.large and 52 or 44
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
    local function widget(key,parent,x,y,w,h,text,tint,background,fn,html_override)
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
        local css="QLabel {background:"..(background or P.panel)..";color:"..(tint or P.text)..";font-family:'Segoe UI';font-size:"..(settings.large and 11 or 9).."pt;border:0;border-radius:3px;padding:2px;}"
        if fn then css=css.." QLabel:hover {background:"..P.raised..";}" end
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
        self.menu=self.menu==name and nil or name;self.page=1
        if name=="party" or name=="tactics" or name=="areas" or name=="settings" then self.anchor=name end
        if name~="member" and name~="roles" and name~="targets" then self.selected=nil end
        self:render()
    end
    function self:visible(value) if self.destroyed then return false end;self.shown=value~=false;self.menu=nil;save();self:render() end
    local function find_row(rows,id) for _,r in ipairs(rows) do if r.id==id then return r end end end
    local function items_for(snap,rows,ts)
        local items={};local title="ChimeraXP";local note=""
        local function add(text,fn,tint) items[#items+1]={text=text,fn=fn,tint=tint} end
        local selected=find_row(rows,self.selected)
        if (self.menu=="member" or self.menu=="roles" or self.menu=="targets") and not selected then self.menu="party" end
        local p=snap.profile;local st=snap.status
        if self.menu=="party" then
            title="Drużyna i role"
            for _,r in ipairs(rows) do
                local id=r.id
                add(r.name.." · "..(ROLES[r.role] or "Automat")..(r.enabled and "  ●" or "  ○"),function() self.selected=id;self.menu="member";self.page=1;self:render() end)
            end
            if #rows==0 then add("Czekam na aktualny skład drużyny.") end
            note="Kondycje pozostają w osobnym oknie."
        elseif self.menu=="member" then
            title=selected.name.." · ustawienia"
            add("‹ Drużyna",function() self.menu="party";self:render() end,P.muted)
            add("Rola: "..(ROLES[selected.role] or "Automat").."  ▾",function() self.menu="roles";self.page=1;self:render() end)
            local id=selected.id
            add("Udział w automatyce: "..(selected.enabled and "WŁ." or "WYŁ."),function() tactics.configure(id,"enabled",not selected.enabled,selected) end)
            add("Minimalne HP wykonawcy: "..selected.min_hp.."%  ↻",function() tactics.configure(id,"min_hp",selected.min_hp>=100 and (selected.self and 40 or 50) or selected.min_hp+5,selected) end)
            add("Limit przejmowanych przeciwników: "..selected.max_load.."  ↻",function() tactics.configure(id,"max_load",(selected.max_load+1)%6,selected) end)
            add("Chroń: "..(selected.target_name or "automatycznie").."  ▾",function() self.menu="targets";self.page=1;self:render() end)
            if selected.slot then
                add("Zadanie: "..(TASK_LABEL[selected.task] or "Automatycznie").."  ↻",function()
                    local current=1;for i,v in ipairs(TASKS) do if v==selected.task then current=i end end
                    local value=TASKS[current%#TASKS+1];tactics.task(id,value,selected)
                    if value=="protect" then self.menu="targets";self.page=1;self:render() end
                end)
            end
            if selected.kind=="npc" then
                for slot=1,2 do
                    local n=slot
                    add("Przypisz jako mój pachołek P"..n,function() tactics.bind(n,id,selected) end)
                end
            end
            note="Progi określają zgodę na manewr, a nie pomiar obrony."
        elseif self.menu=="roles" then
            title=selected.name.." · rola"
            local id=selected.id
            for _,role in ipairs(ROLE_ORDER) do
                if role~="auto" or not selected.self then
                    add((ROLES[role] or "Automat")..(selected.role==role and "  ✓" or ""),function() tactics.configure(id,"role",role,selected);self.menu="member";self:render() end)
                end
            end
            note="Wybranie roli ustawia jej progi; AUTO nie włącza się samo."
        elseif self.menu=="targets" then
            title=selected.name.." · chroniona osoba"
            local id=selected.id
            add("Automatyczny wybór",function() tactics.configure(id,"target_id",nil,selected);self.menu="member";self:render() end)
            for _,r in ipairs(rows) do if r.id~=id then
                local target=r.id;add(r.name,function() tactics.configure(id,"target_id",target,selected);self.menu="member";self:render() end)
            end end
        elseif self.menu=="tactics" then
            title="Taktyka drużyny"
            add("Taktyka: "..(ts.on and "AUTO" or "WYŁ."),function() tactics.toggle(not ts.on) end,ts.on and P.mint or P.text)
            for _,entry in ipairs({{"team_orders","Rozkazy graczom"},{"team_broadcast","Rozkazy zbiorowe"},{"retreat","Wycofanie w szyku"},{"mass","Zasłona masowa"}}) do
                local key=entry[1];add(entry[2]..": "..(ts[key] and "WŁ." or "WYŁ."),function() tactics.option(key,not ts[key]) end)
            end
            add("Stan: "..ts.phase,nil,P.muted)
            note=ts.detail
        elseif self.menu=="areas" then
            title="Expowiska i auto-zarobek"
            local profiles={};for key,v in pairs(snap.profiles) do profiles[#profiles+1]={key=key,value=v} end
            table.sort(profiles,function(a,b) return a.value.name<b.value.name end)
            for _,entry in ipairs(profiles) do
                local key,name=entry.key,entry.value.name
                add((st.selected==key and "● " or "○ ")..name.." · "..#entry.value.route.." lok.",function()
                    if st.started then ctx.log.warn("Zatrzymaj AutoEXP przed zmianą terenu.") else request("wybierz",name) end
                end)
                local earn=entry.value.economy and entry.value.economy.enabled
                add(name.." · Zarobek: "..(earn and "WŁ." or "WYŁ."),function() patrol.set_economy(key,not earn);self:render() end,earn and P.mint or P.muted)
            end
            if #profiles==0 then add("Mapuj nowe expowisko…",function() prefill("mapuj ") end) end
            add(st.started and (st.paused and "▶ Wznów AutoEXP" or "Ⅱ Wstrzymaj AutoEXP") or "▶ Uruchom AutoEXP",function() request(st.started and (st.paused and "wznow" or "pauza") or "start") end,P.mint)
            add("■ Zatrzymaj automatykę",stop,P.rose)
            note="Teren zmienisz po STOP; auto-zarobek również w pauzie."
        elseif self.menu=="settings" then
            title="Ustawienia ChimeraXP"
            for _,entry in ipairs({{"combat","Walka i cele"},{"safety","Schronienie i powrót"},{"loot","Łupy"},{"trade","Auto-zarobek"},{"profiles","Zarządzanie terenami"},{"session","Sesja i komunikaty"}}) do
                local key=entry[1];add(entry[2].."  ›",function() self.menu=key;self.page=1;self:render() end)
            end
            add("Większy pasek: "..(settings.large and "WŁ." or "WYŁ."),function()
                settings.large=not settings.large;height=settings.large and 52 or 44;save();self:render()
            end)
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
            note="Sprzedaż obejmuje bronie i zbroje. Zachowaj prywatne wyposażenie poza zakresem sprzedaży."
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
            if self.root then self.root:hide();self.overlay:hide();self.badge:hide() end
            release();return
        end
        if not available() then return end
        local w,h=screen()
        if owned and type(getBorderTop)=="function" and border()~=owned then
            self.shown=false;self.menu=nil
            ctx.log.warn("Inny dodatek zmienił górny margines. HUD ChimeraXP ukryty; /exp hud on przywraca pasek.")
            patrol.pause("Konflikt układu HUD: przejmij sterowanie.")
            tactics.stop("Konflikt układu HUD.")
            if self.root then self.root:hide();self.overlay:hide();self.badge:hide() end
            release();return
        end
        if not self.root then
            before=border()
            self.root=Geyser.Container:new({name=prefix.."bar",x=0,y=0,width="100%",height=height})
            self.overlay=Geyser.Container:new({name=prefix.."overlay",x=0,y=height,width=w,height=1})
            self.badge=Geyser.Container:new({name=prefix.."run",x=8,y=height+12,width=math.max(1,math.min(420,w-16)),height=29})
        end
        local snap=patrol.snapshot();local st=snap.status;local ts=tactics.status();local rows=tactics.rows()
        if type(setBorderTop)=="function" then
            if not owned then before=border() end
            -- The border reserves console space; it is not a Geyser y offset.
            owned=math.max(before or 0,height+(st.started and 49 or 0))
            if border()~=owned then setBorderTop(owned) end
        end
        self.root:move(0,0);self.root:resize(w,height)
        self.used={}
        widget("background",self.root,0,0,w,height,"",P.text,P.bg)
        local small=w<500;local cw=settings.large and 36 or 32
        cw=math.min(cw,math.max(3,math.floor(w*.09)))
        local right=w-8-cw*3;local y=5;local bh=height-10
        local widths=small and {83,84,58} or {128,132,104}
        local scale=math.min(1,math.max(0.01,(right-20)/(widths[1]+widths[2]+widths[3])))
        local x=8
        local function nav(key,text,tint,width)
            width=math.max(1,math.floor(width*scale))
            widget(key,self.root,x,y,width,bh,text,tint,self.menu and self.anchor==key and P.raised or P.bg,function() self:open(key) end)
            x=x+width+4
        end
        nav("party",small and "Drużyna ▾" or "Drużyna i role ▾",P.text,widths[1])
        nav("tactics",small and "Taktyka ▾" or "Taktyka "..(ts.on and "AUTO" or "WYŁ.").." ▾",ts.on and P.mint or P.muted,widths[2])
        nav("areas",small and "EXP ▾" or "Expowiska ▾",P.text,widths[3])
        widget("pause",self.root,right,y,cw-3,bh,st.paused and "▶" or "Ⅱ",P.muted,P.bg,function() request(st.paused and "wznow" or "pauza") end)
        widget("stop",self.root,right+cw,y,cw-3,bh,"■",P.rose,"#392A35",stop)
        widget("settings",self.root,right+cw*2,y,cw-3,bh,"⚙",P.muted,self.menu and self.anchor=="settings" and P.raised or P.bg,function() self:open("settings") end)
        if st.started then
            local name=snap.profile and snap.profile.name or "Brak terenu"
            local earn=snap.profile and snap.profile.economy and snap.profile.economy.enabled
            local lead=st.paused and "Ⅱ PAUZA" or st.dry and "TEST" or "● AutoEXP"
            local suffix=earn and not small and " · Zarobek" or ""
            local charwidth=settings.large and 8 or 7
            local _,namechars=name:gsub("[%z\1-\127\194-\244][\128-\191]*","")
            local width=math.max(1,math.min(w-16,(namechars+#lead+#suffix+17)*charwidth))
            local clipped=short(name,math.max(1,math.floor(width/charwidth)-#lead-#suffix-17))
            local tint=st.paused and P.yellow or P.mint
            local html="<font color='"..tint.."'>"..esc(lead).."</font><font color='"..P.text.."'> · "..esc(clipped).." · </font><font face='Consolas' color='"..tint.."'>"..clock(st.elapsed).."</font><font color='"..P.muted.."'>"..esc(suffix).."</font>"
            self.badge:move(8,height+12);self.badge:resize(width,29)
            widget("badge",self.badge,0,0,width,29,"",tint,st.paused and "#302B24" or "#202D2B",function() self:open("session") end,html)
            self.badge:show()
        else self.badge:hide() end
        if self.menu then
            local items,title,note=items_for(snap,rows,ts)
            local mw=math.max(1,math.min(470,w-16));local rowh=settings.large and 32 or 27
            local capacity=math.max(1,math.floor((h-height-96)/rowh))
            local pages=math.max(1,math.ceil(#items/capacity));self.page=math.min(self.page,pages)
            local first=(self.page-1)*capacity+1;local last=math.min(#items,first+capacity-1)
            local mh=math.min(math.max(1,h-height-8),64+math.max(0,last-first+1)*rowh+(pages>1 and 27 or 0))
            local anchor=self.labels[self.anchor or "party"]
            local mx=math.max(8,math.min(anchor and anchor.x or 8,w-mw-8))
            self.overlay:move(mx,height+5);self.overlay:resize(mw,mh)
            widget("menu_bg",self.overlay,0,0,mw,mh,"",P.text,P.panel)
            widget("menu_title",self.overlay,8,3,mw-42,25,title,P.lavender,P.panel)
            widget("menu_close",self.overlay,mw-30,3,23,25,"×",P.muted,P.panel,function() self.menu=nil;self:render() end)
            local yy=31
            for index=first,last do
                local item=items[index];local fn=item.fn
                if yy+rowh<=mh then widget("item"..(index-first+1),self.overlay,8,yy,mw-16,rowh-3,short(item.text,math.max(1,math.floor((mw-22)/6))),item.tint,P.raised,fn);yy=yy+rowh end
            end
            if pages>1 and yy+26<=mh then
                widget("previous",self.overlay,8,yy,30,24,"‹",P.text,nil,function() self.page=math.max(1,self.page-1);self:render() end)
                widget("page",self.overlay,42,yy,mw-84,24,self.page.." / "..pages,P.muted,P.panel)
                widget("next",self.overlay,mw-38,yy,30,24,"›",P.text,nil,function() self.page=math.min(pages,self.page+1);self:render() end)
                yy=yy+27
            end
            if yy+25<=mh then widget("note",self.overlay,8,yy,mw-16,24,short(note or "",math.max(1,math.floor((mw-22)/5.5))),P.muted,P.panel) end
            self.overlay:show();if type(self.overlay.raiseAll)=="function" then self.overlay:raiseAll() end
        else self.overlay:hide() end
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
    ctx:cleanup(function()
        self.destroyed=true;release()
        for _,item in pairs(self.labels) do pcall(function() if item.widget.delete then item.widget:delete() elseif type(deleteLabel)=="function" then deleteLabel(item.widget.name) end end) end
        for _,container in ipairs({self.root,self.overlay,self.badge}) do if container then pcall(function() container:hide();if container.delete then container:delete() end end) end end
    end)
    self:render()
    return self
end
return H
