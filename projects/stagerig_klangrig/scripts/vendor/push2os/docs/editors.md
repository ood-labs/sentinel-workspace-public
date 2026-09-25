# Bounded grid and list editors

Page factories receive `api.editor.new(spec)`. Both modes share the same API:

```luau
local editor = api.editor.new({
    id = "choice", mode = "grid", -- or "list"
    bounds = {x=120, y=18, w=118, h=84},
    columns = 3, rows = 3, -- list always uses one column
    items = {{id="one", label="01", value=1}},
    selected_id = "one",
    on_select = function(id, value) -- explicit show-owned binding
    end,
})
```

`move(integer_delta)` and `focus(stable_item_id)` change navigation only.
`commit()` invokes the selection binding once, then updates the selected ID.
`selected(id)` updates the external selection highlight without committing.
`status()` exposes focus/selection IDs and the first/last visible item. `render()`
draws only the visible cells using bounded rectangles and clipped JetBrains Mono
text. It performs no StateTree or sink writes. No clipping API is assumed.

Bounds are copied and validated inside the 960x160 display; cells must be at
least 24x16. Choose bounds inside the page's assigned hardware column and above
the readout strip. Navigation saturates at the first/last item and keeps focus
visible. Twelve grid items in three columns/three rows show 1..9 initially and
4..12 at the final item. List mode uses the identical row-window calculation.

`examples/editors.luau` is the full two-page native Runtime example. Encoder 2
browses; top button 2 commits. Top button 3 opens a two-option menu in only its
occupied top cells. Its new, isolated project explicitly permits an absent bank;
do not copy that opt-in into an existing show. The selection binding and telemetry
belong to the example, not to a truck/fixture catalog in the shared framework.
