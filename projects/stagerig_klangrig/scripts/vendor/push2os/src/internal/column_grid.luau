--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
-- Bounded row viewport shared by parameter choice editors. No host state or writes.
local G={}
function G.window(count: number,columns: number,rows: number,offset: number,focus: number?): any
    local total=math.ceil(count/columns)
    offset=math.clamp(math.floor(offset),0,math.max(0,total-rows))
    if focus and focus>=1 and focus<=count then
        local row=math.floor((focus-1)/columns)
        if row<offset then offset=row elseif row>=offset+rows then offset=row-rows+1 end
    end
    return {offset=offset,first=offset*columns+1,last=math.min(count,(offset+rows)*columns),total=total}
end
return G

end
