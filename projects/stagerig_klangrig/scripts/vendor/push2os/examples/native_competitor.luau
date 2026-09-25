--!strict
return {
    on_start=function()
        local result=surface.claim()
        state.register("refused",not result.ok)
        assert(not result.ok,"simultaneous owner was admitted")
    end,
}
