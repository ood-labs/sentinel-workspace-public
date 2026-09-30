--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
local display=host.display
local Window = get("pad_window")
local C = get("conventions")
local M = {}
function M.make(spec: any, root: () -> string, lit: (any) -> boolean, fire: (any,boolean) -> (), color: ((any) -> number?)?): any
    local w=Window.new(spec.id,spec.row,spec.col)
    w.name,w.spec=spec.name,spec
    w.refresh=function()
        Window.read(w,root())
        local r=Window.rect(w,spec.width or 4,spec.height)
        w.pixels,w.mapping={},{}
        for n,cell in ipairs(spec.cells) do
            local row,col=math.floor((n-1)/r.width),(n-1)%r.width
            if row<r.height then
                local index=(r.row-row)*8+r.col+col
                w.mapping[index]=cell
                w.pixels[index]=(if color then color(cell) else nil) or (if lit(cell) then spec.on else spec.off)
            end
        end
    end
    w.on_pad=function(ev: any,cell: any) if cell then fire(cell,ev.pressed==true) end end
    return w
end
function M.render(ctx: any,windows: {any},focused: any,lit: (any) -> boolean,label: (any) -> string)
    for i,w in ipairs(windows) do
        local width=960/#windows-16
        local x=(i-1)*(width+16)+8;local color=w.spec.color
        display.rect(x,ctx.cy,width,16,if w==focused then color else C.INK.window,true)
        C.text(x+5,ctx.cy+3,w.name,10,if w==focused then 0x080C12 else color)
        local cols=w.spec.width or 4;local cellWidth=width/cols
        for n,cell in ipairs(w.spec.cells) do
            local px,py=x+((n-1)%cols)*cellWidth,ctx.cy+20+math.floor((n-1)/cols)*12
            local active=lit(cell)
            display.rect(px,py,cellWidth-2,10,if active then color else C.INK.window_cell,true)
            C.text(px+3,py+1,label(cell),8,if active then 0x080C12 else color)
        end
    end
end
return M
end
