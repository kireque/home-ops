# HA Migration Progress Update Instructions

## Obsidian vault path

The progress tracker lives at:

```
/run/user/1000/gvfs/smb-share:server=gladius.home.econline.nl,share=home/erik/obsidian/testVault/Home Ops/Applications/🏠 Home Assistant Migration — Progress Tracker.md
```

The SMB share is mounted via GVFS. Verify it's accessible before editing:

```bash
ls "/run/user/1000/gvfs/smb-share:server=gladius.home.econline.nl,share=home/erik/obsidian/testVault/Home Ops/Applications/"
```

## Status legend

| Symbol | Meaning |
|---|---|
| ✅ **Done** | Re-imagined on the new instance |
| 🟡 **Partial** | Hardware migrated, automations/scenes still to do |
| ⬜ **Todo** | Nothing on the new instance yet |
| 🗑️ **Drop** | Explicitly not migrating |
| ❓ **Decide** | Needs a decision before work |

## What to update after completing a room migration

### 1. Per-room status table

Find the room row and update:

| Column | When ✅ Done |
|---|---|
| Hardware | ✅ (if all devices present) |
| Automations | ✅ |
| Scenes | ✅ or `n/a` (n/a when AL replaces them) |
| Status | `✅ **Done**` |
| Notes | Concise summary: what controls it (wall switch payloads, NSPanel, motion), AL entry name, labels, area |

Example (dining):
```
| **Dining** | ✅ | ✅ | n/a | ✅ **Done** | AL replaces scenes; MQTT wall switch (press_1/2 on kitchen_wall_switch) + motion + bedtime_mode; labels: lighting+dining; area: dining |
```

### 2. Headline metrics table

Update the **Automations** count (and Scenes if applicable) to reflect the new
total on the new instance. Recalculate the percentage migrated:

```
~{(new_count / gladius_count) * 100:.0f}% migrated, but fully reworked
```

### 3. Per-subsystem status table

If the room belongs to a cross-cutting subsystem (e.g. "Lighting
scene-controller pattern"), update the Notes column to reflect progress:

- Mark the room as done within the subsystem note.
- Example: "Kitchen done; Living/Dining/Sunroom still to migrate"
  → "Kitchen + Dining done; Living/Sunroom still to migrate"

### 4. Suggested order of attack

Strike through completed rooms using Markdown:

```markdown
~~Kitchen~~ ✅ → ~~Dining~~ ✅ → Living Room → Sunroom
```

## What NOT to update

- Do not change `status: in-progress` in the frontmatter until ALL rooms + subsystems are done.
- Do not update the "Re-running this comparison" section — it's static documentation.
- Do not touch the Decisions section unless a decision was actually made during the migration.
