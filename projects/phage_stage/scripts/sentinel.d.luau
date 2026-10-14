-- Generated from ScriptBindingRegistry.h/.def. Do not edit.
-- Sentinel host API. Definition file for editor tooling; do not require it.
-- Configure this file in the editor's Luau definition-file settings.

export type Scalar = number | boolean | string
export type PadMode = "momentary" | "toggle" | "radio" | "go"
export type PadState = "empty" | "loaded" | "active" | "selected" | "fading"
export type Role = "neutral" | "accent" | "go" | "kill" | "warn" | "freeze" | "link" | "expression"
export type EdgeKind = "press" | "release"
export type EventRecord = {
    source_id: number, sequence: number, timestamp_ns: number,
    intra_frame_offset: number, event_type: number, payload_len: number,
    payload: {number},
}
export type EventWrite = {event_type: number, timestamp_ns: number?, payload: {number}?}
export type Pin = {name: string, type: "signal" | "event" | "display"}
export type Parameter = {
    name: string, type: "float" | "int" | "bool" | "string" | "enum",
    default: Scalar?, min: number?, max: number?, values: {string}?, transient: boolean?,
}
export type Manifest = {name: string, inputs: {Pin}?, outputs: {Pin}?, params: {Parameter}?}
export type Context = {tick: number, dt: number, time: number}
export type DisplayOutput = {}
export type Node = {
    state: {[any]: any}, params: {[string]: Scalar},
    inputs: {[string]: SignalInput | EventInput},
    outputs: {[string]: SignalOutput | EventOutput | DisplayOutput},
}
export type Script = {
    manifest: Manifest,
    init: ((node: Node) -> ())?,
    control_process: ((node: Node, ctx: Context) -> ())?,
    serialize: ((node: Node) -> {[any]: any})?,
    deserialize: ((node: Node, saved: {[any]: any}) -> ())?,
    render: ((node: Node, ui: Ui) -> ())?,
    render_display: ((node: Node, d: Display) -> ())?,
    stop: ((node: Node) -> ())?,
}

export type SignalInput = {
    get: (self: SignalInput) -> number,
    stale: (self: SignalInput) -> boolean,
    age: (self: SignalInput) -> number,
}

export type EventInput = {
    read_events: (self: EventInput) -> {EventRecord},
}

export type SignalOutput = {
    set: (self: SignalOutput, value: number) -> (),
}

export type EventOutput = {
    emit: (self: EventOutput, event: EventWrite) -> (),
}

export type Display = {
    clear: (rgb: number) -> boolean,
    rect: (x: number, y: number, width: number, height: number, rgb: number, fill: boolean?, thickness: number?) -> boolean,
    line: (x1: number, y1: number, x2: number, y2: number, rgb: number, thickness: number?) -> boolean,
    circle: (x: number, y: number, radius: number, rgb: number, fill: boolean?, thickness: number?) -> boolean,
    polyline: (points: {{number}}, rgb: number, thickness: number?) -> boolean,
    text: (x: number, y: number, text: string, scale: number?, rgb: number?, font: string?, tracking: number?) -> boolean,
    text_vector: (x: number, y: number, text: string, size_px: number?, rgb: number?) -> boolean,
    meter: (x: number, y: number, width: number, height: number, value: number, foreground: number?, background: number?, orientation: string?) -> boolean,
    skip: () -> boolean,
}

declare display: {
    begin_frame: (rgb: number) -> boolean,
    complete_frame: () -> boolean,
    abort_frame: () -> boolean,
    clear: (rgb: number) -> boolean,
    rect: (x: number, y: number, width: number, height: number, rgb: number, fill: boolean?) -> boolean,
    line: (x1: number, y1: number, x2: number, y2: number, rgb: number, thickness: number?) -> boolean,
    text: (x: number, y: number, text: string, size_hint: number?, rgb: number?, font: string?, tracking: number?) -> boolean,
    text_vector: (x: number, y: number, text: string, size_px: number?, rgb: number?, font: string?) -> boolean,
}

declare sentinel: {
    subscribe: (path: string) -> boolean,
    get: (path: string) -> Scalar?,
    set: (path: string, value: Scalar) -> boolean,
    invoke: (path: string, args: {[any]: any}?) -> boolean,
}

declare panel: {
    label: (pipeline_id: string, control_id: string, text: string) -> boolean,
}

declare log: {
    info: (message: string) -> boolean,
    warn: (message: string) -> boolean,
    error: (message: string) -> boolean,
}

declare time: {
    now: () -> number,
}

declare osc: {
    listen: (name: string, port: number, enabled: boolean) -> boolean,
    receive: (name: string, max_count: number?) -> {any},
    input_status: (name: string) -> {[string]: any}?,
}

declare windows_audio: {
    define: (name: string, match_type: string, value: string, mode: string?) -> boolean,
    status: (name: string) -> {[string]: any}?,
    set_volume: (name: string, volume: number) -> boolean,
    set_mute: (name: string, mute: boolean) -> boolean,
}

declare surface: {
    capabilities: () -> {api_version: number, capabilities: {[string]: boolean}},
    claim: () -> {ok: boolean, token: number, code: string},
    stop: (token: number) -> boolean,
}

declare state: {
    register: (relative_path: string, default_value: Scalar) -> (),
    get: (path: string) -> Scalar?,
    set: (path: string, value: Scalar) -> (),
    root: () -> string,
    begin_restore: (use_registered_values: boolean?) -> (),
    complete_restore: () -> (),
}

declare preset: {
    read_snapshot: (group: string, name: string) -> {[string]: any},
    save: (group: string, name: string, options: {paths: {string}, merge_existing: boolean}) -> boolean,
    recall: (group: string, name: string) -> boolean,
    active: (group: string) -> string?,
    list: (group: string) -> {[string]: any},
    programmer: (request: {[string]: any}) -> {[string]: any},
    create: (group: string, name: string, options: {[string]: any}) -> {[string]: any},
    recall_confirmed: (group: string, name: string) -> {[string]: any},
}

declare midi: {
    on: (id: string, kind: string, callback: (any) -> ()) -> (),
    send: ((id: string, value: number) -> boolean) & ((port: string, kind: string, channel: number, data1: number, data2: number?) -> boolean),
    send_many: (port: string, messages: {any}) -> {sent_count: number, failed_count: number, errors: {{index: number, msg: string}}},
    send_sysex: (port: string, bytes: {number}) -> boolean,
    ports: () -> {string},
    output_ports: () -> {string},
    controllers: () -> {any},
    semantic_ids: () -> {string},
    clear_notes: (port: string, channel: number, notes: {number}) -> {sent_count: number, failed_count: number, errors: {{index: number, msg: string}}},
}

export type Ui = {
    text: (id: string, text: string) -> (boolean, number?),
    button: (id: string, label: string) -> (boolean, boolean?),
    slider_float: (id: string, label: string, value: number, min: number, max: number) -> (boolean, number?),
    slider_int: (id: string, label: string, value: number, min: number, max: number) -> (boolean, number?),
    checkbox: (id: string, label: string, value: boolean) -> (boolean, boolean?),
    combo: (id: string, label: string, index: number, labels: {string}) -> (boolean, number?),
    input_text: (id: string, label: string, value: string) -> (boolean, string?),
    same_line: () -> (boolean, number?),
    separator: () -> (boolean, number?),
    line: (x1: number, y1: number, x2: number, y2: number, color: number, thickness: number?) -> (boolean, number?),
    rect: (x1: number, y1: number, x2: number, y2: number, color: number, thickness: number?) -> (boolean, number?),
    rect_filled: (x1: number, y1: number, x2: number, y2: number, color: number) -> (boolean, number?),
    circle: (x: number, y: number, radius: number, color: number, thickness: number?) -> (boolean, number?),
    circle_filled: (x: number, y: number, radius: number, color: number) -> (boolean, number?),
    text_at: (x: number, y: number, color: number, text: string) -> (boolean, number?),
    polyline: (points: {{number}}, color: number, thickness: number?) -> (boolean, number?),
    pad: (id: string, label: string, mode: PadMode?, state: PadState?, role_or_color: (Role | number)?, icon: string?, fade: number?, width: number?, height: number?) -> (boolean, boolean, boolean),
    next_edge: () -> (string?, EdgeKind?, number?),
    grid_begin: (id: string, cols: number, rows: number, cell_width: number, cell_height: number, gap_x: number?, gap_y: number?) -> (),
    grid_cell: (col: number, row: number) -> (),
    grid_end: () -> (),
    strip_begin: (id: string, direction: "horizontal" | "vertical", item_size: number, gap: number?) -> (),
    strip_end: () -> (),
    section: (id: string, title: string, icon: string?) -> (),
    row: (label: string) -> (),
    bank_header: (id: string, title: string, page: number, pages: number, live_mask: number?, labels: {string}?) -> number?,
    pad_grid: (id: string, cols: number, rows: number, cell_width: number, cell_height: number, labels: {string}, states: {PadState}?, colors: {Role | number}?, mode: PadMode?, fades: {number}?) -> (number?, number?, number?),
    tap_tempo: (id: string, beat_phase: number?, width: number?, height: number?) -> (boolean, number?),
    transport: (id: string, running: boolean) -> (boolean, boolean, boolean),
    readout: (id: string, text: string, size: number?, role_or_color: (Role | number)?) -> (),
    fader: (id: string, label: string, value: number, default: number, min: number, max: number, direction: ("vertical" | "horizontal")?, role_or_color: (Role | number)?, flags: string?, width: number?, height: number?) -> (boolean, number),
    knob: (id: string, label: string, value: number, default: number, min: number, max: number, size: number?, role_or_color: (Role | number)?, flags: string?) -> (boolean, number),
    crossfader: (id: string, value: number, default: number?, width: number?, role_or_color: (Role | number)?) -> (boolean, number),
    xy: (id: string, label: string, x: number, y: number, default_x: number?, default_y: number?, min: number?, max: number?, size: number?) -> (boolean, number, number),
    meter: (id: string, level: number, peak: number?, direction: ("vertical" | "horizontal")?, width: number?, height: number?, role_or_color: (Role | number)?) -> (),
    lamp: (id: string, on: boolean, role_or_color: (Role | number)?, label: string?, size: number?) -> (),
    value_tile: (id: string, label: string, text: string, role_or_color: (Role | number)?, width: number?, height: number?) -> (),
    meter_bound: (id: string, path: string, min: number?, max: number?, direction: ("vertical" | "horizontal")?, width: number?, height: number?, role_or_color: (Role | number)?) -> (),
    readout_bound: (id: string, path: string, format: string?, size: number?, role_or_color: (Role | number)?) -> (),
    lamp_bound: (id: string, path: string, role_or_color: (Role | number)?, label: string?, size: number?) -> (),
    submaster: (id: string, label: string, level: number, meter: number?, role_or_color: (Role | number)?, on: boolean?, width: number?, height: number?) -> (boolean, number),
    guarded: (id: string, label: string, style: ("hold" | "arm")?, role_or_color: (Role | number)?, width: number?, height: number?) -> boolean,
    get: (id: string) -> (boolean, Scalar),
}

declare ui: Ui
declare require: (name: string) -> any
