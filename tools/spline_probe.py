import json, subprocess, sys, time
def call(tool, args):
    p = subprocess.run([sys.executable,"tools/sentinel_mcp_call.py",tool,json.dumps(args)],
                       capture_output=True,text=True)
    return json.loads(json.loads(p.stdout)["result"]["content"][0]["text"])
BASE="/sentinel/pipelines/Spline_Desk/parameters/"
def edge(name):
    call("sentinel_state",{"action":"set","path":BASE+name,"value":1}); time.sleep(0.25)
    call("sentinel_state",{"action":"set","path":BASE+name,"value":0}); time.sleep(0.25)
def knots():
    r = call("sentinel_pipeline",{"action":"capture_data_port","pipeline_id":"Spline_Desk",
                                  "port_name":"Spline Knots","max_elements":64})
    recs = r.get("records") or r.get("elements") or []
    out=[]
    for k in recs:
        if float(k.get("active",0)) > 0.5:
            out.append({"id":int(k.get("knot_id",0)),"lane":int(k.get("spline_id",0)),
                        "sel":int(k.get("flags",0)) & 1,"tan":int(k.get("tangent_mode",0)),
                        "anchor":[round(float(x),4) for x in (k.get("anchor") or [0,0])]})
    return out
def show(tag):
    ks=knots()
    print(f"{tag:22s} active={len(ks)} sel={sum(k['sel'] for k in ks)} "
          f"tangents={sorted(set(k['tan'] for k in ks))} first_anchor={ks[0]['anchor'] if ks else None}")
    return ks
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a.startswith("edge:"): edge(a[5:]); print(f"  fired {a[5:]}")
        else: show(a)
