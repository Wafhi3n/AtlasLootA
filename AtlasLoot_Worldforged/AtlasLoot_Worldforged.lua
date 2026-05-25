-------------------------------------------------------------------------------
-- AtlasLoot_Worldforged.lua
-- Injects a "Worldforged" browse category into AtlasLoot using
-- community discovery data from LootCollector (hard dependency).
--
-- Architecture:
--   Phase 1 (file scope)  : register top-level menu + placeholder sub-menus.
--   Phase 2 (PLAYER_LOGIN + 1 s) : read LootCollector DB, group items by
--     (expansion, slot), sort by item level desc, all zones merged in one
--     flat paginated list.  Zone name shown as desc on each item button.
--     Category dropdown  = equipment slot  (Head, Chest, Neck ...)
--     Right sidebar      = page numbers only (Page 1, Page 2 ...)
-------------------------------------------------------------------------------

local ADDON_NAME = "AtlasLoot_Worldforged"

-- LootCollector discovery-type constant
local DISCOVERY_TYPE_WORLDFORGED = 1

-- ContinentID -> AtlasLoot expansion key
local CONTINENT_TO_EXPANSION = {
    [1] = "CLASSIC",   -- Kalimdor
    [2] = "CLASSIC",   -- Eastern Kingdoms
    [3] = "TBC",       -- Outland
    [4] = "WRATH",     -- Northrend
}

-- INVTYPE_* -> readable slot category
local SLOT_CATEGORY = {
    INVTYPE_HEAD           = "Head",
    INVTYPE_NECK           = "Neck",
    INVTYPE_SHOULDER       = "Shoulder",
    INVTYPE_CHEST          = "Chest",
    INVTYPE_ROBE           = "Chest",
    INVTYPE_WAIST          = "Waist",
    INVTYPE_LEGS           = "Legs",
    INVTYPE_FEET           = "Feet",
    INVTYPE_WRIST          = "Wrist",
    INVTYPE_HAND           = "Hands",
    INVTYPE_FINGER         = "Ring",
    INVTYPE_TRINKET        = "Trinket",
    INVTYPE_BACK           = "Back",
    INVTYPE_CLOAK          = "Back",
    INVTYPE_WEAPON         = "Weapon",
    INVTYPE_WEAPONMAINHAND = "Weapon",
    INVTYPE_2HWEAPON       = "Weapon",
    INVTYPE_WEAPONOFFHAND  = "Off-Hand",
    INVTYPE_SHIELD         = "Off-Hand",
    INVTYPE_HOLDABLE       = "Off-Hand",
    INVTYPE_RANGED         = "Ranged",
    INVTYPE_THROWN         = "Ranged",
    INVTYPE_RANGEDRIGHT    = "Ranged",
}

-- Ordered slot list for consistent sub-menu display
local SLOT_ORDER = {
    "Head", "Neck", "Shoulder", "Back", "Chest",
    "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Ring", "Trinket", "Weapon", "Off-Hand", "Ranged", "Other",
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

-- Build one AtlasLoot_Data entry for a slot/expansion.
-- flatItems = { { id=itemID, ilvl=N, zone=zoneName }, ... } already deduped.
-- Items are sorted by ilvl descending; zone shown as desc on each button.
-- Right sidebar shows "Page 1", "Page 2", etc.
local function BuildSlotEntry(slotName, flatItems)
    -- Sort by ilvl descending; uncached items (ilvl=0) fall to the bottom
    table.sort(flatItems, function(a, b)
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        return a.id < b.id
    end)

    local entry    = { Module = ADDON_NAME, Name = slotName }
    local pageNum  = 0
    local i        = 1
    while i <= #flatItems do
        pageNum = pageNum + 1
        local leftCol, rightCol = {}, {}
        for j = 0, 31 do
            local item = flatItems[i + j]
            if not item then break end
            local btn = { itemID = item.id, desc = "|cff00ccff" .. item.zone }
            if j < 16 then
                leftCol[#leftCol + 1]  = btn
            else
                rightCol[#rightCol + 1] = btn
            end
        end
        entry[#entry + 1] = { Name = "Page " .. pageNum, leftCol, rightCol }
        i = i + 32
    end
    return entry
end

-------------------------------------------------------------------------------
-- Phase 1 — register menus at file-scope (after AtlasLoot + LootCollector load)
-------------------------------------------------------------------------------

-- AtlasLoot_Modules is iterated with ipairs so table.insert is safe.
table.insert(AtlasLoot_Modules, { "Worldforged", "Worldforged", 2 })

-- Placeholder sub-menus (replaced in Phase 2 with real data).
AtlasLoot_SubMenus["WorldforgedCLASSIC"] = {
    Module  = ADDON_NAME,
    SubMenu = "WorldforgedCLASSIC",
    { "Loading Worldforged data...", "", "Header" },
}
AtlasLoot_SubMenus["WorldforgedTBC"] = {
    Module  = ADDON_NAME,
    SubMenu = "WorldforgedTBC",
    { "Loading Worldforged data...", "", "Header" },
}
AtlasLoot_SubMenus["WorldforgedWRATH"] = {
    Module  = ADDON_NAME,
    SubMenu = "WorldforgedWRATH",
    { "Loading Worldforged data...", "", "Header" },
}

-------------------------------------------------------------------------------
-- Phase 2 — build data from LootCollector after PLAYER_LOGIN
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    C_Timer.After(1, function()

        local discoveries = LootCollector:GetDiscoveriesDB()
        if not discoveries then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff6600AtlasLoot_Worldforged:|r LootCollector DB not ready.")
            return
        end

        local zoneListModule = LootCollector:GetModule("ZoneList")
        if not zoneListModule then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff6600AtlasLoot_Worldforged:|r ZoneList module not found.")
            return
        end
        local mapData = zoneListModule.MapDataByID

        -- bySlotExp[expansion][slot] = { {id, ilvl, zone}, ... } flat list
        local bySlotExp = { CLASSIC = {}, TBC = {}, WRATH = {} }
        local seen = {}  -- dedup key: "expansion:slot:itemID" (one entry per item)

        for _, disc in pairs(discoveries) do
            if disc.dt == DISCOVERY_TYPE_WORLDFORGED and disc.st ~= "STALE" then
                local zoneID = disc.z
                local itemID = disc.i
                if zoneID and itemID then
                    local zoneInfo  = mapData[zoneID]
                    local zoneName  = zoneInfo and zoneInfo.name or ("Zone_" .. zoneID)
                    local contID    = zoneInfo and zoneInfo.continentID
                    local expansion = CONTINENT_TO_EXPANSION[contID] or "CLASSIC"

                    -- Resolve slot + ilvl via GetItemInfo (cached items only)
                    local _, _, _, iLevel, _, _, _, _, equipSlot = GetItemInfo(itemID)
                    local slot = (equipSlot and SLOT_CATEGORY[equipSlot]) or "Other"
                    local ilvl = iLevel or 0

                    -- Dedup per (expansion, slot, itemID) — same item can appear in multiple zones,
                    -- keep the first occurrence for the zone label
                    local key = expansion .. ":" .. slot .. ":" .. itemID
                    if not seen[key] then
                        seen[key] = true
                        local expBucket = bySlotExp[expansion]
                        expBucket[slot] = expBucket[slot] or {}
                        local t = expBucket[slot]
                        t[#t + 1] = { id = itemID, ilvl = ilvl, zone = zoneName }
                    end
                end
            end
        end

        -- Build AtlasLoot_Data + SubMenu entries per expansion
        local expHeaders = {
            CLASSIC = "Classic Slots",
            TBC     = "Outland Slots",
            WRATH   = "Northrend Slots",
        }

        local totalSlots = 0
        for _, expansion in ipairs({ "CLASSIC", "TBC", "WRATH" }) do
            local subMenuKey = "Worldforged" .. expansion
            local slotData   = bySlotExp[expansion]
            local rows       = {}

            -- Iterate in SLOT_ORDER for a consistent menu order
            for _, slot in ipairs(SLOT_ORDER) do
                local flatItems = slotData[slot]
                if flatItems and #flatItems > 0 then
                    local dataKey = "WF_" .. slot:gsub("[^%w]", "_") .. "_" .. expansion
                    AtlasLoot_Data[dataKey] = BuildSlotEntry(slot, flatItems)
                    rows[#rows + 1] = { slot, dataKey, "" }
                    totalSlots = totalSlots + 1
                end
            end

            if #rows > 0 then
                local t = {
                    Module  = ADDON_NAME,
                    SubMenu = subMenuKey,
                    { expHeaders[expansion], "", "Header" },
                }
                for _, row in ipairs(rows) do t[#t + 1] = row end
                AtlasLoot_SubMenus[subMenuKey] = t
            else
                AtlasLoot_SubMenus[subMenuKey] = {
                    Module  = ADDON_NAME,
                    SubMenu = subMenuKey,
                    { "No Worldforged data for this expansion", "", "Header" },
                }
            end
        end

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ccffAtlasLoot Worldforged:|r " .. totalSlots .. " slot categories loaded from LootCollector."
        )

    end)  -- C_Timer.After
end)      -- OnEvent
