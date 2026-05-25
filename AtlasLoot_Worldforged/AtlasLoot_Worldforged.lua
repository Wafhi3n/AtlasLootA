-------------------------------------------------------------------------------
-- AtlasLoot_Worldforged.lua
-- Injects a "Worldforged" browse category into AtlasLoot using
-- community discovery data from LootCollector (hard dependency).
--
-- Architecture:
--   Phase 1 (file scope) : register the top-level menu category and
--                          placeholder sub-menus so AtlasLoot can draw
--                          the sidebar before the DB is queried.
--   Phase 2 (PLAYER_LOGIN + 1 s delay) : read LootCollector's per-realm
--                          discoveries table, build AtlasLoot_Data entries
--                          grouped by zone, then replace the placeholders
--                          with real entries.
-------------------------------------------------------------------------------

local ADDON_NAME = "AtlasLoot_Worldforged"

-- LootCollector discovery-type constant (Constants.lua)
local DISCOVERY_TYPE_WORLDFORGED = 1

-- ContinentID → AtlasLoot expansion key
-- (LootCollector ZoneList: 1=Kalimdor, 2=EasternKingdoms, 3=Outland, 4=Northrend)
local CONTINENT_TO_EXPANSION = {
    [1] = "CLASSIC",
    [2] = "CLASSIC",
    [3] = "TBC",
    [4] = "WRATH",
}

-- Sanitise a zone name into a safe Lua table key
local function SafeKey(name)
    return name:gsub("[^%w]", "_")
end

-- Build one AtlasLoot_Data entry for a list of itemIDs.
-- Items are split into pages of 32 (16 left column + 16 right column).
local function BuildDataEntry(zoneName, itemIDs)
    local entry = {
        Module = ADDON_NAME,
        Name   = zoneName,
    }
    local pageNum  = 0
    local leftCol, rightCol
    for i, itemID in ipairs(itemIDs) do
        local pos = (i - 1) % 32
        if pos == 0 then
            pageNum = pageNum + 1
            leftCol  = {}
            rightCol = {}
            entry[pageNum] = { Name = zoneName .. " " .. pageNum, leftCol, rightCol }
        end
        if pos < 16 then
            leftCol[#leftCol + 1]   = { itemID = itemID }
        else
            rightCol[#rightCol + 1] = { itemID = itemID }
        end
    end
    return entry
end

-- Build one AtlasLoot_SubMenus entry from a sorted list of { displayName, dataKey } pairs.
local function BuildSubMenu(subMenuKey, header, zoneList)
    local t = {
        Module  = ADDON_NAME,
        SubMenu = subMenuKey,
        { header, "", "Header" },
    }
    for _, entry in ipairs(zoneList) do
        -- { displayName, dataKey, mapName }
        t[#t + 1] = { entry[1], entry[2], "" }
    end
    return t
end

-------------------------------------------------------------------------------
-- Phase 1 — register menus at file-scope load time
-------------------------------------------------------------------------------

-- Add "Worldforged" as a top-level category with expansion tabs (flag = 2).
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
-- Phase 2 — read LootCollector DB after PLAYER_LOGIN
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    -- Delay 1 second so LootCollector can finish merging its bundled discoveries.
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

        -- Accumulate: byExpansion[expansion][zoneName] = { itemID = true, ... }
        local byExpansion = {
            CLASSIC = {},
            TBC     = {},
            WRATH   = {},
        }

        for _, disc in pairs(discoveries) do
            -- Only Worldforged, skip Stale entries
            if disc.dt == DISCOVERY_TYPE_WORLDFORGED and disc.st ~= "STALE" then
                local zoneID = disc.z
                local itemID = disc.i

                if zoneID and itemID then
                    local zoneInfo   = mapData[zoneID]
                    local zoneName   = zoneInfo and zoneInfo.name or ("Zone_" .. zoneID)
                    local contID     = zoneInfo and zoneInfo.continentID
                    local expansion  = CONTINENT_TO_EXPANSION[contID] or "CLASSIC"

                    local expBucket = byExpansion[expansion]
                    if not expBucket[zoneName] then
                        expBucket[zoneName] = {}
                    end
                    -- deduplicate by itemID within this zone
                    expBucket[zoneName][itemID] = true
                end
            end
        end

        -- Build AtlasLoot_Data entries and collect submenu rows per expansion
        local subRows = { CLASSIC = {}, TBC = {}, WRATH = {} }

        for expansion, zones in pairs(byExpansion) do
            -- Collect and sort zone names
            local sortedZones = {}
            for zoneName in pairs(zones) do
                sortedZones[#sortedZones + 1] = zoneName
            end
            table.sort(sortedZones)

            for _, zoneName in ipairs(sortedZones) do
                local itemSet = zones[zoneName]
                -- Convert set to sorted array
                local itemIDs = {}
                for itemID in pairs(itemSet) do
                    itemIDs[#itemIDs + 1] = itemID
                end
                table.sort(itemIDs)

                if #itemIDs > 0 then
                    local dataKey = "WF_" .. SafeKey(zoneName)
                    AtlasLoot_Data[dataKey] = BuildDataEntry(zoneName, itemIDs)
                    subRows[expansion][#subRows[expansion] + 1] = { zoneName, dataKey }
                end
            end
        end

        -- Replace placeholder sub-menus with populated ones
        local headers = {
            CLASSIC = "Classic Zones",
            TBC     = "Outland Zones",
            WRATH   = "Northrend Zones",
        }
        for _, expansion in ipairs({ "CLASSIC", "TBC", "WRATH" }) do
            local key  = "Worldforged" .. expansion
            local rows = subRows[expansion]
            if #rows > 0 then
                AtlasLoot_SubMenus[key] = BuildSubMenu(key, headers[expansion], rows)
            else
                AtlasLoot_SubMenus[key] = {
                    Module  = ADDON_NAME,
                    SubMenu = key,
                    { "No Worldforged data for this expansion", "", "Header" },
                }
            end
        end

        -- Brief confirmation in chat (remove if too noisy)
        local total = 0
        for _, rows in pairs(subRows) do total = total + #rows end
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ccffAtlasLoot Worldforged:|r " .. total .. " zones loaded from LootCollector."
        )

    end)  -- C_Timer.After
end)      -- OnEvent
