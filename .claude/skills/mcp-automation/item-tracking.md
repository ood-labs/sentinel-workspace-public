# Adding Item Tracking to New Panels

Enable widget-level automation in new panels.

## Automation Code Structure

```
src/automation/
├── AutomationBridge.h/cpp    # ZMQ listener, command routing
├── UITreeSerializer.h/cpp    # ImGui state → JSON
├── ActionHandler.h/cpp       # Click/key injection, state manipulation
└── ItemTracker.h/cpp         # Track item positions for widget clicks
```

## Basic Tracking

```cpp
#ifdef ENABLE_AUTOMATION
#include "automation/ItemTracker.h"
#endif

// For selectables:
if (ImGui::Selectable(item.name.c_str(), selected)) {
    // ... selection logic ...
}
#ifdef ENABLE_AUTOMATION
TRACK_SELECTABLE("PanelName", "Category/" + item.name, selected);
#endif

// For tree nodes (tracks expanded state):
bool isOpen = ImGui::TreeNodeEx(category, flags);
#ifdef ENABLE_AUTOMATION
TRACK_TREENODE("PanelName", category, isOpen);
#endif

// For sliders:
if (ImGui::SliderFloat(param.name.c_str(), &value, minVal, maxVal)) {
    // ... handle change ...
}
#ifdef ENABLE_AUTOMATION
TRACK_SLIDER("PanelName", "Group/" + param.name, value, minVal, maxVal, false);
#endif
```

## Direct State Manipulation Pattern

The "pending value" pattern enables state changes without window focus:

```cpp
// In panel render code, BEFORE the widget:
#ifdef ENABLE_AUTOMATION
auto pending = ItemTracker::get().consumePendingFloat("Properties", itemPath);
if (pending.has_value()) {
    value = std::clamp(*pending, minVal, maxVal);
    // Apply to underlying data
}
#endif

// Then render the widget normally
if (ImGui::SliderFloat(label, &value, minVal, maxVal)) { ... }
```

This allows the MCP server to set values even when Sentinel is in the background.

## Testing Automation

```python
from src.ipc.client import IPCClient

client = IPCClient()
client.connect()

# Test connection
print(client.ping())  # True

# Get UI tree
tree = client.get_ui_tree()
print(tree)

# Click an element
client.click("Sources/Patterns/Test Pattern")

# Set a slider value (works in background!)
client.set_slider("Properties/Parameters/Brightness", 0.5)

client.disconnect()
```

## Pipeline Introspection

```python
# List all active pipelines
pipelines = client.get_pipelines()
for p in pipelines:
    print(f"{p['id']}: {p['fps']:.1f} FPS, {p['framesProcessed']} frames")

# Get detailed info with parameters
info = client.get_pipeline_info("colorcorrect_0")
print(f"Pipeline: {info['name']} v{info['version']}")

for param in info['parameters']:
    print(f"  {param['name']}: {param['value']} (range: {param['min']}-{param['max']})")
```

## Verifying Your Work with MCP Tools

**After making UI changes:**
```
sentinel_screenshot action="window"                              → See full app state
sentinel_screenshot action="element" element_name="Sources"      → Check specific panel
sentinel_ui action="get_tree"                                    → Verify elements tracked
```

**After adding new controls:**
```
get_ui_hierarchy              → Confirm new items appear in the tree
click_element "Panel/NewItem" → Test that clicking works
set_input_value "Panel/Slider" 0.5 → Test direct manipulation
```

**When debugging issues:**
```
capture_frames count=10 interval_ms=100  → Capture sequence to analyze
compare_frames frame1=... frame2=...     → Check for unexpected changes
analyze_sequence frames=[...] type="stability" → Verify static content
```

## Debugging Tips

1. **`get_app_logs` returns buffered stdout** - May be stale. Screenshot the Log panel for real-time values.
2. **Pipeline creation via IPC** - StreamDiffusion takes 6-30 seconds to load TensorRT engines.
3. **ZMQ can become unresponsive** - If ping fails, restart the app.
4. **Automation bridge needs warm-up** - Wait 3-5 seconds after launch before sending commands.

## MCP Test Setup Sequence (Manual)

```python
from src.ipc.client import IPCClient
import time

client = IPCClient()
client.connect()

# 1. Create Spout source
client.click('Sources/+')
time.sleep(0.3)
client.click('Sources/Add Source/Spout')
time.sleep(0.5)

# 2. Refresh available senders
client.click('Properties/Source/Refresh')
time.sleep(0.5)

# 3. Select Spout sender (index 1 = first sender)
client.set_combo('Properties/Source/Spout Sender', 1)
time.sleep(0.3)

# 4. Connect the source
client.click('Properties/Source/Connect')
time.sleep(1)

# 5. Create pipeline
result = client.create_pipeline('facetrack')
time.sleep(2)

# 6. Route source to pipeline (index 2 = first actual source)
client.set_combo('Facetrack - facetrack_0/Slot0', 2)

client.disconnect()
```

## Available Automation Scripts (dev only)

These scripts live in the dev repo and are not shipped in the distribution. Distribution users should drive Sentinel via MCP tools instead.

| Script | Purpose |
|--------|---------|
| `setup_facetrack_test.py` | Spout + Face Tracking + route |
