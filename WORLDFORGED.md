# Worldforged Items — Guide & Contribution

## Overview

The Worldforged system is an AtlasLoot extension for Ascension.gg.  
It catalogs and displays **Worldforged** items (items with a base version and an upgraded version at ilvl 60 via the Guardian of Time).

AtlasLoot shows these items in a dedicated menu: **"Worldforged" > CLASSIC / TBC / WRATH**, organized by equipment slot. Each base item is linked to its upgraded version via L-Click (popup).

---

## Automatic detection

### In-game detection (no action required)

| Trigger | What happens |
|---|---|
| **Login** (`PLAYER_LOGIN`) | Scans all bags 5s after login — all owned Worldforged items are registered |
| **Looting** (`LOOT_OPENED`) | Each looted Worldforged item is automatically registered with the player's coordinates |
| **Guardian of Time** (NPC) | When the RPGItemStore window opens, available upgrades are scanned and linked to their base |

### Auto-link base ↔ upgrade

When two items share the **same name** but have different ilvls, the system links them automatically:
- The item with the lower ilvl → **base**
- The item with the higher ilvl → **upgrade** (`upgradeOf` + `isNPCUpgrade = true`)

---

## Static database

Known items are stored in two places:

| File | Role |
|---|---|
| `AtlasLoot/Core/WorldforgedDB.lua` | Static DB bundled with the addon (source code) |
| `AtlasLoot/WorldforgedData/*.lua` | Community contributions (one file per player) |
| `AtlasLootWorldforgedDB` (SavedVariables) | Player's personal DB — items discovered in-game |

---

## Useful slash commands

| Command | Description |
|---|---|
| `/wfexportcontrib [NAME]` | Exports your discoveries to `AtlasLootWF_ContribExport` (SavedVariables) |
| `/wfexport` | Exports in text format (legacy WorldforgedDB.lua format) |
| `/wflink <baseID> <upgradeID>` | Manually creates a base→upgrade link |
| `/wfadd <ID>` | Manually adds an item to the DB |
| `/wfscanbags` | Manually re-runs the bag scan |
| `/wfrpgscan` | Manually re-runs the Guardian of Time scan |
| `/wfrpgdump` | Displays the IDs read from the RPGItemStore window |
| `/wfdebug` | Toggles debug mode (logs in chat) |

---

## Contributing your discoveries

### Requirements
- Have discovered Worldforged items in-game (loot, bags, or visiting the Guardian of Time)
- Have a GitHub account and a fork of the repo

### Steps

**1. Export your data in-game**
```
/wfexportcontrib
/reload
```

**2. Retrieve the SavedVariables file**

Open the file:
```
WTF/Account/<YOUR_ACCOUNT>/SavedVariables/AtlasLoot.lua
```

Find the block:
```lua
AtlasLootWF_ContribExport = {
    ...
}
```

**3. Create your contribution file**

Create `AtlasLoot/WorldforgedData/YOURNAME.lua` with this content,  
**replacing the first line**:

```lua
-- BEFORE (copied from SavedVariables):
AtlasLootWF_ContribExport = {

-- AFTER (in your .lua file):
AtlasLootWF_Contribs["YOURNAME"] = {
```

Final example:
```lua
AtlasLootWF_Contribs["Wafhien"] = {
    [450860] = {
        expansion = "CLASSIC",
        name = "Rosebud Ring",
        slot = "Finger",
        upgradeID = 1388758,
        locations = {
            { zone = "Tirisfal Glades", x = 61.2, y = 48.3, c = 0, z = 0 },
        },
    },
    -- ...
}
```

> **Note:** Items with no location (discovered via the Guardian of Time) will have `locations = {}` — this is expected.

**4. Register your file in WorldforgedData.xml**

Add the line in `AtlasLoot/WorldforgedData/WorldforgedData.xml`:
```xml
<Script file="YOURNAME.lua"/>
```

**5. Submit a Pull Request**

```
git add AtlasLoot/WorldforgedData/YOURNAME.lua
git add AtlasLoot/WorldforgedData/WorldforgedData.xml
git commit -m "contrib: add Worldforged data from YOURNAME"
git push
```

Then open a Pull Request on GitHub.

---

## Data structure

```lua
-- An item in the DB
[itemID] = {
    name      = "Item Name",
    slot      = "Finger",           -- Slot category (see SLOT_CATEGORY)
    expansion = "CLASSIC",          -- "CLASSIC" | "TBC" | "WRATH"
    locations = {                   -- Can be empty
        { zone = "Tirisfal Glades", subzone = "", x = 61.2, y = 48.3, c = 0, z = 0 },
    },
    upgradeID    = 1388758,         -- (optional) ID of the upgraded version
    upgradeOf    = 450860,          -- (optional) ID of the base item
    isNPCUpgrade = true,            -- (optional) true if ilvl 60 version from Guardian of Time
}
```

---

## Contribution merging

On addon load, `WorldforgedDB.lua` automatically merges all contributions:
- If an item doesn't exist yet → it is added
- If an item already exists → locations are merged (no duplicates per zone)

Priority order: **static DB** > **contributions** > **player SavedVariables**
