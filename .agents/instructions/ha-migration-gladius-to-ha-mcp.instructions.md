# Room Migration Instructions — Gladius → ha-mcp

## Context

Two Home Assistant instances:
- **ha-mcp-gladius** (`ha-mcp-gladius` MCP connection) — OLD instance, being terminated. Read-only reference.
- **ha-mcp** (`ha-mcp` MCP connection) — NEW instance. All new entities/automations/helpers go here.

---

## Migration Checklist for a New Room

### 1. Inventory on Gladius

Search `ha-mcp-gladius` for:
- Automations: `ha_search_entities(query="{room}", domain_filter="automation")`
- Lights: `ha_search_entities(query="{room}", domain_filter="light")`
- Scenes: `ha_search_entities(query="{room}_lights", domain_filter="scene")` — **skip these**, do not recreate
- Helpers: `ha_search_entities(query="{room}", domain_filter="input_select/input_boolean/input_number")`
- Scripts: `ha_search_entities(query="{room}", domain_filter="script")`
- Adaptive Lighting: `ha_get_integration(domain="adaptive_lighting")`
- Get full config of active automations (use `_2` versions if present)

### 2. Check What Exists on ha-mcp

- Search `ha-mcp` for the same entities — note what's missing vs already migrated
- Check Zigbee devices: `ha_get_device(integration="zigbee2mqtt", area_id="{room}")` → note device IDs and friendly names for MQTT topics
- Check AL: `ha_get_integration(domain="adaptive_lighting")` — find the room entry, check lights list

### 3. Adaptive Lighting — Add Lights (Manual UI Step)

**Settings → Devices & Services → Adaptive Lighting → {Room} → Configure → add light entities → Submit**

Verify: `ha_get_integration(entry_id="{entry_id}")` → lights list not empty

### 4. Create Automation on ha-mcp

Base on the Gladius `_2` automation config, applying these replacements:

| Gladius pattern | ha-mcp pattern |
|---|---|
| Scene actions | AL direct control (see pattern below) |
| MQTT device_id triggers | MQTT topic triggers |
| `input_select.select_option` calls | `light.turn_on/off` + AL sleep mode |
| No bedtime trigger | Add `input_boolean.home_modes_bedtime_mode` → `on` trigger to OFF branch |

**Automation template (5-branch pattern, all downstairs rooms):**

```yaml
mode: restart
max_exceeded: silent
trigger:
  # Wall switch ON
  - platform: state
    attribute: event_type
    entity_id: event.{room}_wall_switch_action
    to: press_1
    id: press_on
  # Wall switch OFF
  - platform: state
    attribute: event_type
    entity_id: event.{room}_wall_switch_action
    to: press_2
    id: press_off
  # Motion
  - platform: state
    entity_id: binary_sensor.{room}_motion_sensor_occupancy
    to: "on"
    id: occupancy_on
  # Bedtime
  - platform: state
    entity_id: input_boolean.home_modes_bedtime_mode
    to: "on"
    id: bedtime
  # No presence downstairs for 30 minutes (aggregate sensor)
  - platform: state
    entity_id: binary_sensor.downstairs_presence
    to: "off"
    for: "00:30:00"
    id: downstairs_no_presence
action:
  - choose:
      # Branch 1 — Manual ON (wall switch)
      - conditions:
          - condition: trigger
            id: [press_on]
        sequence:
          - action: switch.turn_off
            target:
              entity_id: switch.adaptive_lighting_{room}_adaptive_lighting_sleep_mode_{room}
          - action: light.turn_on
            target:
              entity_id: light.{room}_lights
          - action: adaptive_lighting.apply
            data:
              entity_id: switch.{room}_adaptive_lighting_{room}
              transition: 1
      # Branch 2 — Motion ON, normal hours (07:00–00:30), dark (< 100 lux)
      - conditions:
          - condition: trigger
            id: [occupancy_on]
          - condition: numeric_state
            entity_id: sensor.sunroom_lux
            below: 100
          - condition: time
            after: "07:00:00"
            before: "00:30:00"
        sequence:
          - action: switch.turn_off
            target:
              entity_id: switch.adaptive_lighting_{room}_adaptive_lighting_sleep_mode_{room}
          - action: light.turn_on
            target:
              entity_id: light.{room}_lights
          - action: adaptive_lighting.apply
            data:
              entity_id: switch.{room}_adaptive_lighting_{room}
              transition: 1
      # Branch 3 — Motion ON, late night (00:30–07:00), dark (< 100 lux)
      - conditions:
          - condition: trigger
            id: [occupancy_on]
          - condition: numeric_state
            entity_id: sensor.sunroom_lux
            below: 100
          - condition: time
            after: "00:30:00"
            before: "07:00:00"
        sequence:
          - action: switch.turn_on
            target:
              entity_id: switch.adaptive_lighting_{room}_adaptive_lighting_sleep_mode_{room}
          - action: light.turn_on
            target:
              entity_id: light.{room}_lights
          - action: adaptive_lighting.apply
            data:
              entity_id: switch.{room}_adaptive_lighting_{room}
              transition: 1
      # Branch 4 — Motion, lux unavailable: reset sleep mode during normal hours
      - alias: "Motion detected - reset sleep mode (lux unavailable)"
        conditions:
          - condition: trigger
            id: [occupancy_on]
          - condition: time
            after: "07:00:00"
            before: "00:30:00"
        sequence:
          - action: switch.turn_off
            target:
              entity_id: switch.adaptive_lighting_{room}_adaptive_lighting_sleep_mode_{room}
      # Branch 5 — OFF: wall switch / no downstairs presence / bedtime
      - conditions:
          - condition: trigger
            id: [press_off, downstairs_no_presence, bedtime]
        sequence:
          - action: switch.turn_off
            target:
              entity_id: switch.adaptive_lighting_{room}_adaptive_lighting_sleep_mode_{room}
          - action: light.turn_off
            target:
              entity_id: light.{room}_lights
```

> **Note on triggers:** Downstairs rooms share `binary_sensor.downstairs_presence`
> for the no-motion OFF trigger (aggregate of dining/living/sunroom occupancy sensors).
> Per-room occupancy sensors fire only the ON branches (branch 2/3/4).
> NSPanel rooms use `binary_sensor.{room}_nspanel_left_button` / `..._right_button`
> state triggers instead of MQTT event triggers.

Assign `area_id: {room}` and `labels: ["{room_label}", "lighting"]`.

### 5. Disable Old Automations on Gladius

```python
ha_call_service(domain="automation", service="turn_off", entity_id="automation.{room}_*_2")
```

### 6. Migrate Helpers

For each `input_select` / `input_boolean` / `input_number` on Gladius:

- **Scene selector** → skip (scenes replaced by AL)
- **Mode/state helper** → recreate on ha-mcp with same `entity_id`:
  1. `ha_config_set_helper()` to create
  2. `ha_set_entity(new_entity_id=...)` to match original entity ID
  3. Apply labels and area (see Labels section)

### 7. Labels and Areas

| Target | labels | area_id |
|---|---|---|
| Automation | `["{room_label}", "lighting"]` | `{room}` |
| Room-specific helpers | `["{room_label}"]` | `{room}` |
| Global helpers | `["home_modes"]` | *(none)* |

### 8. Scenes — Skip

Scenes are replaced by Adaptive Lighting. **Do not recreate** `scene.{room}_lights_*` on ha-mcp. Leave old scenes on Gladius to die with the instance.

---

## Known Labels

| label_id | Name | Usage |
|---|---|---|
| `lighting` | Lighting | All light-related automations |
| `kitchen` | Kitchen | Kitchen entities |
| `home_modes` | Home Modes | Global mode helpers |
| `eva_s_bedroom` | Eva's Bedroom | Eva's bedroom entities |
| `job_s_bedroom` | Job's Bedroom | Job's bedroom entities |
| `alarm` | Alarm | Alarm/wake-up system |
| `nebula` | Nebula | Nebula device group |
| `rocket` | Rocket | Rocket entities |

Create new room labels as needed: `label_id` = room name in snake_case matching the area.

## Known Areas (already exist on ha-mcp)

`kitchen`, `dining`, `living_room`, `sunroom`, `hallway`, `toilet`, `bedroom`, `bedroom_eva`, `bedroom_job`, `bathroom`, `landing`, `office`, `outdoor`, `front_garden`, `back_garden`, `garage`

## Global Helpers Status

| Helper | Status |
|---|---|
| `input_boolean.home_modes_bedtime_mode` | ✓ migrated |
| `input_boolean.home_modes_away_mode` | pending |
| `input_boolean.home_modes_guest_mode` | pending |
| `input_boolean.home_modes_vacation_mode` | pending |
| `input_number.home_modes_vacation_mode_replay_days` | pending |

---

## Key Entity ID Patterns on ha-mcp

### Adaptive Lighting Switches

Always verify entity IDs on ha-mcp:
```python
ha_search_entities(query="adaptive_lighting_{room}", limit=10)
```

Pattern: `switch.{al_title}_adaptive_lighting_{sub_switch}_{al_title}`  
where `al_title` = the AL config entry title in snake_case.

| Switch | Entity ID pattern |
|---|---|
| Main | `switch.{room}_adaptive_lighting_{room}` |
| Sleep mode | `switch.adaptive_lighting_{room}_adaptive_lighting_sleep_mode_{room}` |
| Adapt brightness | `switch.adaptive_lighting_{room}_adaptive_lighting_adapt_brightness_{room}` |
| Adapt color | `switch.adaptive_lighting_{room}_adaptive_lighting_adapt_color_{room}` |

> AL lights list is empty by default — must be added via UI (step 3).

### Zigbee Devices (Z2M via MQTT)

- Light entities: same names as Gladius (`light.{room}_spots`, `light.{room}_ledstrip`, etc.)
- MQTT trigger topic: `zigbee2mqtt/{z2m_friendly_name}/action`
- Get friendly name: `ha_get_device(integration="zigbee2mqtt", area_id="{room}")` → `mqtt_topic_hint` field
- **Use MQTT topic triggers, not `device_id` or event entity triggers**

### NSPanel (ESPHome)

- Left button: `binary_sensor.{room}_nspanel_left_button` → `to: "on"`
- Right button: `binary_sensor.{room}_nspanel_right_button` → `to: "on"`
- Separate from Zigbee wall switches

---

## Dark Condition

Motion-triggered ON actions use `sensor.sunroom_lux` — a `min_max` helper
averaging the two Zigbee lux sensors in the sunroom (mean of
`sensor.downstairs_sunroom_lux_sensor_1_illuminance` and
`sensor.downstairs_sunroom_lux_sensor_2_illuminance`):

```yaml
- condition: numeric_state
  entity_id: sensor.sunroom_lux
  below: 100
```

Threshold 100 lux covers dusk, twilight, heavy overcast, and night. Daytime
sunroom readings are typically 200–2000 lux depending on weather and sun angle.

> **Why not the outdoor rain sensor?**
> `sensor.0xa4c138547dd4c333_illuminance_average_20min` reports a raw analog
> voltage (unit: mV, today's max ~166) — *not* lux. Threshold 1000 is never
> reached and lights would never turn on from motion. Do not use it for
> dark-condition checks.
