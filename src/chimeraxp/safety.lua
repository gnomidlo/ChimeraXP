-- Session-local evidence for navigating without a current exit list.
-- A directed edge is confirmed only after observing both ends of a move.
local S = {}
function S.new()
    local s = {edges={}, visited={}, skipped={}}
    function s.observe(r)
        if not r or not r.id then return end
        local key = r.key or r.id
        local previous = s.last
        if previous and previous.key ~= key then
            local direction
            for cmd, target in pairs(previous.exits) do
                if target == r.id and s.outgoing and (cmd==s.outgoing or s.normalize(cmd)==s.outgoing) then
                    if direction then direction=nil; break end
                    direction=cmd
                end
            end
            if direction and previous.id ~= r.id then
                local edges=s.edges[previous.key] or {}
                edges[key]={command=direction, id=r.id, key=key}
                s.edges[previous.key]=edges
            end
            s.outgoing=nil
        end
        s.last={id=r.id,key=key,exits=r.exits or {}}
    end
    function s.return_step(r, target)
        local key=r.key or r.id
        local queue,first,seen={key},{},{[key]=true}
        local i=1
        while i<=#queue do
            local from=queue[i]
            for dest,edge in pairs(s.edges[from] or {}) do
                if not seen[dest] then
                    local step=first[from] or edge
                    -- Current positive evidence overrides historical evidence.
                    local live=(r.exits or {})[step.command]
                    if not next(r.exits or {}) or live==step.id then
                        if dest==target then return step.command,step.id,step.key end
                        first[dest],seen[dest]=step,true
                        queue[#queue+1]=dest
                    end
                end
            end
            i=i+1
        end
    end
    return s
end
return S
