--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
-- Select + short tap moves. Holding a pad arms two-corner resizing.
local Pe = get("persist")
local M = {}

function M.new(): any
    return { window = nil, armed = false, down = false, row = 0, col = 0, since = 0 }
end

function M.cancel(g: any)
    if g.window then g.window.resizing = false end
    g.window, g.armed, g.down = nil, false, false
    g.before = nil
end

function M.tick(g: any, now: number)
    if g.window and g.down and now-g.since >= 0.65 then
        g.armed = true
        g.window.resizing = true
    end
end

function M.press(g: any, w: any, row: number, col: number, now: number)
    if g.armed and g.window == w then
        if row==g.row and col==g.col then
            for _,name in ipairs({"row","col","width","height"}) do
                w[name].value=g.before[name]; Pe.publish(w[name],now)
            end
            w.message,w.until_time="RESIZE CANCELLED",now+2
            M.cancel(g)
            return
        end
        w.row.value, w.col.value = math.max(g.row,row), math.min(g.col,col)
        w.width.value, w.height.value = math.abs(g.col-col)+1, math.abs(g.row-row)+1
        for _, rec in ipairs({w.row,w.col,w.width,w.height}) do Pe.publish(rec,now) end
        w.message = string.format("SIZE SET: %d x %d",w.width.value,w.height.value)
        w.until_time = now+2
        M.cancel(g)
    else
        M.cancel(g)
        g.before={row=w.row.value or w.row.default,col=w.col.value or w.col.default,
            width=w.width.value or w.width.default,height=w.height.value or w.height.default}
        g.window, g.row, g.col, g.since, g.down = w, row, col, now, true
        w.row.value, w.col.value = row, col
        Pe.publish(w.row,now); Pe.publish(w.col,now)
        w.message, w.until_time = "MOVED | KEEP PAD HELD TO RESIZE", now+2
    end
end

function M.release(g: any, row: number, col: number)
    if g.row == row and g.col == col then
        g.down = false
        if not g.armed then M.cancel(g) end
    end
end

function M.paint(g: any, frame: { [number]: number }, now: number)
    if g.armed then frame[g.row*8+g.col] = if math.floor(now*6)%2 == 0 then 122 else 0 end
end

return M

end
