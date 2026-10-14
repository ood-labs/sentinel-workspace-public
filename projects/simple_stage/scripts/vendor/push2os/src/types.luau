--!strict
export type Diagnostic = {ok: boolean, code: string, message: string, context: {[string]: any}}
export type Bounds = {x: number, y: number, width: number, height: number}
export type Editor = {
    id: string, bounds: Bounds, navigation: any,
    render: (any) -> (), input: (any) -> (),
}
export type ParamRecord = {
    id: string, persist: string, default: number?, min: number?, max: number?,
    sink: any?, editor: Editor?, legacy_key: string?, state_path: string?,
}
export type PageDescriptor = {
    id: string, label: string, params: {ParamRecord}?, records: {ParamRecord}?,
    windows: {any}?, render: (any) -> (), legacy_id: string?, legacy_window_id: string?,
}
export type ShowConfig = {
    id: string, root: string, midi_output_port: string,
    persistence: {group: string, preset: string, schema_version: number},
    pages: {(any) -> PageDescriptor},
}
return {}
