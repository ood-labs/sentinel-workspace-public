# StateTree - Unified State Access

The StateTree provides a single source of truth for all controllable state via OSC-style paths.

## Path Convention

`/sentinel/<category>/<instance>/<property>`

## Path Structure

```
/sentinel
├── sources/{source_id}
│   ├── name, type, state (readonly)
│   ├── senderName (writable)
│   ├── currentWidth, currentHeight, currentFps (readonly)
│   └── actions/connect, actions/disconnect
├── pipelines/{pipeline_id}
│   ├── type, name, version (readonly)
│   ├── enabled (writable)
│   ├── parameters/{param_name} (writable)
│   └── actions/start, stop, relaunch, reset
└── outputs/{sink_id}
    ├── name, type, state, width, height, framesSent (readonly)
    └── actions/start, stop
```

## Usage Example

```python
from ipc.client import IPCClient

client = IPCClient()
client.connect()

# Discover what's available
tree = client.get_tree("/sentinel")
print(tree['children'].keys())  # ['sources', 'pipelines', 'outputs']

# Create a source and see it in the tree
source = client.create_source("pattern", name="Test")
source_values = client.list_values(f"/sentinel/sources/{source['id']}")
# ['/sentinel/sources/source_0/senderName']

# Connect source via StateTree action
client.invoke_action(f"/sentinel/sources/{source['id']}/actions/connect")

# Create pipeline and modify parameter via tree
pipeline = client.create_pipeline("colorcorrect")
client.set_state_value(f"/sentinel/pipelines/{pipeline['id']}/parameters/brightness", 0.75)

# Read back with metadata
info = client.get_state_value(f"/sentinel/pipelines/{pipeline['id']}/parameters/brightness")
print(f"Value: {info['value']}, Type: {info['valueType']}, Range: {info['min']}-{info['max']}")

# List all available actions
actions = client.list_actions("/sentinel")
for action in actions:
    print(action)  # /sentinel/sources/source_0/actions/connect, etc.

# Invoke pipeline action
client.invoke_action(f"/sentinel/pipelines/{pipeline['id']}/actions/stop")

client.disconnect()
```

## Key Benefits

- **Discovery**: Find all controllable parameters without knowing the API
- **Uniformity**: Same pattern for sources, pipelines, and outputs
- **Validation**: Values are automatically clamped to valid ranges
- **Actions**: Invoke operations like connect/disconnect/start/stop via paths
