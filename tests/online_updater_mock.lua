-- Run from ChimeraXP repository root (Lua >= 5.1 compatible).
local os_execute = os.execute
local dir = "/tmp/chimera_xp_updater_smoke_" .. os.time()
assert(os_execute('mkdir -p "' .. dir .. '"'))
getMudletHomeDir = function() return dir end
package.preload.lfs = function()
    return {
        attributes = function(path, field)
            local p = io.popen('test -d "' .. path .. '" && printf yes')
            local s = p:read("*a"); p:close()
            return s == "yes" and "directory" or nil
        end,
        mkdir = function(path)
            return os_execute('mkdir -p "' .. path .. '"')
        end,
    }
end
local function contents(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read('*a'); f:close(); return data
end
local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end
local logs={}
cecho=function(s) logs[#logs+1]=s end
local events, next_id = {},0
registerAnonymousEventHandler=function(event,handler)
    next_id=next_id+1
    events[next_id]={name=event,fn=handler}
    return next_id
end
killAnonymousEventHandler=function(id) events[id]=nil end
local function emit(name,...)
    local arr={}
    for _,record in pairs(events) do if record.name==name then arr[#arr+1]=record.fn end end
    for _,fn in ipairs(arr) do fn(name,...) end
end
local manifest = contents('manifest.json')
local plugin = contents('plugins/chimera_autoexp/init.lua')
local missing=false
local urls={}
downloadFile=function(destination,url)
    urls[#urls+1]=url
    if missing then
        emit('sysDownloadError',"offline",destination,url)
        return true
    end
    local body
    if url:find('manifest.json',1,true) then body=manifest
    elseif url:find('plugins/chimera_autoexp/init.lua',1,true) then body=plugin
    else error('Unexpected '+ url) end
    local f=assert(io.open(destination,'wb'));f:write(body);f:close()
    emit('sysDownloadDone',destination,#body,url)
    return true
end
tempTimer=function(_,fn) fn() end
assert(loadfile('installer/mudlet_updater.lua'))()
local target=dir..'/chimera_wtyczki/chimera_autoexp/init.lua'
assert(contents(target)==plugin,'initial install must use public GitHub version')
assert(#urls==2,'installer fetches manifest then plugin')
local U=chimera_xp_updater
assert(not U.busy,'download completes')
assert(U:check(true),'manual update request starts')
assert(contents(target)==plugin,'noop update retains current source')
assert(#urls==3,'no need to redownload source when already on version')
-- A newer public release must replace plugin with a backup.
manifest=manifest:gsub('0%.6%.0%-beta%.2','0.6.0-beta.3')
plugin=plugin:gsub('version = "0%.6%.0%-beta%.2"','version = "0.6.0-beta.3"',1)
assert(U:check(true),'new release download')
assert(contents(target)==plugin,'updated source')
local old=io.popen('find "'..dir..'/ChimeraXP/backups" -type f | head -1')
local backup=old:read('*l');old:close()
assert(backup and contents(backup):find('version = "0.6.0-beta.2"',1,true),'backups work')
-- Network errors must not touch working code.
missing=true
assert(U:check(true),'offline check attempted')
assert(contents(target)==plugin,'offline update must preserve installed source')
-- Unknown file in the plugin location must not be overwritten.
missing=false
local f=assert(io.open(target,'wb'));f:write('-- foreign package, not AutoExp');f:close()
manifest=manifest:gsub('0%.6%.0%-beta%.3','0.6.0-beta.4')
plugin=plugin:gsub('version = "0%.6%.0%-beta%.3"','version = "0.6.0-beta.4"',1)
assert(U:check(true),'foreign target check attempted')
assert(contents(target)=='-- foreign package, not AutoExp','foreign file must not be touched')
print('online-updater smoke tests PASS: initial install, noop, upgrade + backup, offline, foreign file',#urls)
os_execute('rm -rf "'..dir..'"')
