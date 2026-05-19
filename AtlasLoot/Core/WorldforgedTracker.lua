--[[
    WorldforgedTracker.lua
    Détecte les items Worldforged depuis la fenêtre de loot (LOOT_OPENED),
    les enregistre avec leur localisation (zone + coordonnées), et construit
    les menus AtlasLoot organisés par slot d'équipement.

    Commandes :
      /wfdebug                    → état SubMenus + log buffer
      /wfexport                   → exporte les découvertes vers AtlasLootWF_ExportBuffer
      /run AtlasLootWF_DumpDB()   → afficher les items enregistrés
      /run AtlasLootWF_Debug = true/false
]]

AtlasLootWF_Debug    = false
AtlasLootWF_LogBuffer = AtlasLootWF_LogBuffer or {}

local function WFLog(msg)
    if not AtlasLootWF_Debug then return end
    AtlasLootWF_LogBuffer = AtlasLootWF_LogBuffer or {}
    table.insert(AtlasLootWF_LogBuffer, msg)
end

function AtlasLootWF_DumpDB()
    local db = AtlasLootWorldforgedDB
    if not db or not db.items then
        print("[WF] DB vide ou non initialisée")
        return
    end
    local count = 0
    for itemID, data in pairs(db.items) do
        count = count + 1
        local loc = data.locations and data.locations[1]
        local locStr = loc and (loc.zone .. " (" .. loc.x .. "," .. loc.y .. ")") or "?"
        print("[WF] #" .. itemID .. " " .. tostring(data.name)
              .. " [" .. tostring(data.slot) .. "] @ " .. locStr)
    end
    if count == 0 then print("[WF] Aucun item Worldforged enregistré") end
end

-- ============================================================
-- Mapping slot équipement → catégorie lisible
-- ============================================================
local SLOT_CATEGORY = {
    INVTYPE_HEAD           = "Head",
    INVTYPE_NECK           = "Neck",
    INVTYPE_SHOULDER       = "Shoulders",
    INVTYPE_CLOAK          = "Back",
    INVTYPE_CHEST          = "Chest",
    INVTYPE_ROBE           = "Chest",
    INVTYPE_WRIST          = "Wrist",
    INVTYPE_HAND           = "Hands",
    INVTYPE_WAIST          = "Waist",
    INVTYPE_LEGS           = "Legs",
    INVTYPE_FEET           = "Feet",
    INVTYPE_FINGER         = "Finger",
    INVTYPE_TRINKET        = "Trinket",
    INVTYPE_WEAPON         = "One-Hand",
    INVTYPE_WEAPONOFFHAND  = "Off-Hand",
    INVTYPE_WEAPONMAINHAND = "Main-Hand",
    INVTYPE_2HWEAPON       = "Two-Hand",
    INVTYPE_SHIELD         = "Off-Hand",
    INVTYPE_HOLDABLE       = "Off-Hand",
    INVTYPE_RANGED         = "Ranged",
    INVTYPE_THROWN         = "Ranged",
    INVTYPE_RELIC          = "Ranged",
    INVTYPE_AMMO           = "Ammo",
    INVTYPE_BODY           = "Shirt",
    INVTYPE_TABARD         = "Tabard",
}

local SLOT_ORDER = {
    "Head", "Neck", "Shoulders", "Back", "Chest",
    "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Finger", "Trinket",
    "Main-Hand", "One-Hand", "Off-Hand", "Two-Hand",
    "Ranged", "Ammo", "Shirt", "Tabard", "Other",
}

-- ============================================================
-- Zone -> Extension (Classic / TBC / Wrath)
-- ============================================================
local ZONE_EXPANSION = {
    -- Classic – Kalimdor
    ["Durotar"] = "CLASSIC",              ["Mulgore"] = "CLASSIC",
    ["The Barrens"] = "CLASSIC",          ["Ashenvale"] = "CLASSIC",
    ["Stonetalon Mountains"] = "CLASSIC", ["Desolace"] = "CLASSIC",
    ["Feralas"] = "CLASSIC",              ["Dustwallow Marsh"] = "CLASSIC",
    ["Thousand Needles"] = "CLASSIC",     ["Tanaris"] = "CLASSIC",
    ["Un'Goro Crater"] = "CLASSIC",       ["Silithus"] = "CLASSIC",
    ["Winterspring"] = "CLASSIC",         ["Felwood"] = "CLASSIC",
    ["Azshara"] = "CLASSIC",              ["Darkshore"] = "CLASSIC",
    ["Teldrassil"] = "CLASSIC",           ["Moonglade"] = "CLASSIC",
    ["Bloodmyst Isle"] = "CLASSIC",       ["Azuremyst Isle"] = "CLASSIC",
    -- Classic – Eastern Kingdoms
    ["Elwynn Forest"] = "CLASSIC",        ["Dun Morogh"] = "CLASSIC",
    ["Tirisfal Glades"] = "CLASSIC",      ["Silverpine Forest"] = "CLASSIC",
    ["Hillsbrad Foothills"] = "CLASSIC",  ["The Hinterlands"] = "CLASSIC",
    ["Alterac Mountains"] = "CLASSIC",    ["Arathi Highlands"] = "CLASSIC",
    ["Wetlands"] = "CLASSIC",             ["Loch Modan"] = "CLASSIC",
    ["Badlands"] = "CLASSIC",             ["Searing Gorge"] = "CLASSIC",
    ["Burning Steppes"] = "CLASSIC",      ["Redridge Mountains"] = "CLASSIC",
    ["Duskwood"] = "CLASSIC",             ["Westfall"] = "CLASSIC",
    ["Stranglethorn Vale"] = "CLASSIC",   ["Swamp of Sorrows"] = "CLASSIC",
    ["Blasted Lands"] = "CLASSIC",        ["Western Plaguelands"] = "CLASSIC",
    ["Eastern Plaguelands"] = "CLASSIC",  ["Deadwind Pass"] = "CLASSIC",
    ["Eversong Woods"] = "CLASSIC",       ["Ghostlands"] = "CLASSIC",
    -- TBC – Outland
    ["Hellfire Peninsula"] = "TBC",       ["Zangarmarsh"] = "TBC",
    ["Terokkar Forest"] = "TBC",          ["Nagrand"] = "TBC",
    ["Blade's Edge Mountains"] = "TBC",   ["Netherstorm"] = "TBC",
    ["Shadowmoon Valley"] = "TBC",        ["Isle of Quel'Danas"] = "TBC",
    -- Wrath – Northrend
    ["Howling Fjord"] = "WRATH",          ["Borean Tundra"] = "WRATH",
    ["Dragonblight"] = "WRATH",           ["Grizzly Hills"] = "WRATH",
    ["Zul'Drak"] = "WRATH",               ["Sholazar Basin"] = "WRATH",
    ["Crystalsong Forest"] = "WRATH",     ["The Storm Peaks"] = "WRATH",
    ["Icecrown"] = "WRATH",               ["Wintergrasp"] = "WRATH",
}

local function GetExpansionForZone(zone)
    return ZONE_EXPANSION[zone] or "CLASSIC"
end

-- ============================================================
-- Tooltip scanner pour fenêtre de loot
-- ============================================================
local scanTooltip

local function GetScanner()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "AtlasLootWFScanTooltip", UIParent, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return scanTooltip
end

local function IsLootSlotWorldforged(slot)
    local tt = GetScanner()
    tt:ClearLines()
    tt:SetLootItem(slot)
    local numLines = tt:NumLines()
    if AtlasLootWF_Debug and numLines == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[WF scan]|r slot " .. slot .. ": 0 lignes tooltip (item pas encore dans cache?)")
    end
    for i = 1, numLines do
        local left = _G["AtlasLootWFScanTooltipTextLeft" .. i]
        if left then
            local text = left:GetText()
            WFLog("  scan L" .. i .. ": " .. (text or "nil"))
            if text and text:find("Worldforged", 1, true) then
                return true
            end
        end
    end
    return false
end

-- ============================================================
-- Localisation du joueur
-- ============================================================
local function GetPlayerLocation()
    local zone    = GetRealZoneText() or GetZoneText() or "Unknown"
    local subzone = GetSubZoneText() or ""
    local x, y   = 0, 0
    local ok, rx, ry = pcall(function()
        SetMapToCurrentZone()
        return GetPlayerMapPosition("player")
    end)
    local c, z = 0, 0
    if ok and rx then
        x = math.floor(rx * 10000 + 0.5) / 100
        y = math.floor(ry * 10000 + 0.5) / 100
        c = GetCurrentMapContinent() or 0
        z = GetCurrentMapAreaID()    or 0
    end
    return { zone = zone, subzone = subzone, x = x, y = y, c = c, z = z }
end

-- ============================================================
-- Migration ancienne DB (items[zone][itemID] → items[itemID])
-- ============================================================
local function MigrateDB()
    local db = AtlasLootWorldforgedDB
    if not db or not db.items then return end
    local firstKey = next(db.items)
    if firstKey == nil or type(firstKey) == "number" then return end
    -- Ancien format : clés = noms de zones
    WFLog("Migration ancienne DB...")
    local newItems = {}
    for zone, items in pairs(db.items) do
        if type(items) == "table" then
            for itemID in pairs(items) do
                if type(itemID) == "number" and not newItems[itemID] then
                    local itemName, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemID)
                    local slotCat = SLOT_CATEGORY[itemEquipLoc or ""] or "Other"
                    newItems[itemID] = {
                        name      = itemName or "Unknown",
                        slot      = slotCat,
                        expansion = GetExpansionForZone(zone),
                        locations = { { zone = zone, x = 0, y = 0 } },
                    }
                end
            end
        end
    end
    db.items = newItems
    local count = 0; for _ in pairs(newItems) do count = count + 1 end
    WFLog("Migration: " .. count .. " items migrés")
end

-- ============================================================
-- Fixup : corriger le slot des items stockés comme "Other" ou nom inconnu
-- ============================================================
local function FixupSlots()
    local db = AtlasLootWorldforgedDB and AtlasLootWorldforgedDB.items
    if not db then return end
    local fixed = 0
    for itemID, data in pairs(db) do
        if data.slot == "Other" or data.name == "Unknown" then
            local itemName, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemID)
            if itemEquipLoc then
                data.slot = SLOT_CATEGORY[itemEquipLoc] or "Other"
                data.name = itemName or data.name
                fixed = fixed + 1
            end
        end
    end
    if fixed > 0 then WFLog("FixupSlots: " .. fixed .. " slots corrigés") end
end

-- ============================================================
-- Sauvegarde d'un item Worldforged détecté au loot
-- ============================================================
local function SaveWorldforgedItem(itemLink, location)
    if not itemLink then return end
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return end

    AtlasLootWorldforgedDB = AtlasLootWorldforgedDB or { items = {} }
    local db = AtlasLootWorldforgedDB.items

    if not db[itemID] then
        local itemName, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)
        local slotCat   = SLOT_CATEGORY[itemEquipLoc or ""] or "Other"
        local expansion = GetExpansionForZone(location.zone)
        db[itemID] = {
            name      = itemName or "Unknown",
            slot      = slotCat,
            expansion = expansion,
            locations = {},
        }
        WFLog("Nouveau: " .. tostring(itemName) .. " [" .. slotCat .. "] " .. expansion)
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ff66[WF]|r Worldforged découvert: " .. itemLink
            .. " à |cffffff00" .. location.zone .. "|r")
    end

    -- Ajouter la localisation si zone nouvelle
    local locs  = db[itemID].locations
    local found = false
    for _, loc in ipairs(locs) do
        if loc.zone == location.zone then found = true; break end
    end
    if not found then
        table.insert(locs, location)
        WFLog("Localisation: " .. location.zone .. " (" .. location.x .. "," .. location.y .. ")")
    end

    local ok, err = pcall(AtlasLoot_BuildWorldforgedTables)
    if not ok then
        WFLog("ERREUR BuildWorldforgedTables: " .. tostring(err))
    end
end

-- ============================================================
-- Tooltip hook : afficher la localisation sur tous les items WF
-- ============================================================
local function AddLocationToTooltip(tooltip, link)
    if not link then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end
    local data = AtlasLootWF_GetItemData(itemID)
    if not data or not data.locations or #data.locations == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ff66[Worldforged] Trouvé à :|r")
    for _, loc in ipairs(data.locations) do
        local coords = (loc.x > 0 or loc.y > 0)
                       and (" (" .. loc.x .. ", " .. loc.y .. ")") or ""
        tooltip:AddLine("  " .. loc.zone .. coords, 1, 1, 0)
    end
end

hooksecurefunc(GameTooltip, "SetHyperlink", function(self, link)
    AddLocationToTooltip(self, link)
end)

hooksecurefunc(GameTooltip, "SetLootItem", function(self, slot)
    AddLocationToTooltip(self, GetLootSlotLink(slot))
end)

-- ============================================================
-- Accès unifié : DB statique + SavedVariables (union des locations)
-- ============================================================

-- ============================================================
-- Résolution de slot avec cache persisté
-- ============================================================

--- Retourne le slot lisible pour un itemID.
--- Vérifie d'abord slotCache (SavedVariable), puis GetItemInfo.
--- Persiste automatiquement les nouvelles résolutions.
local function ResolveSlot(itemID)
    if not AtlasLootWorldforgedDB then return nil end
    AtlasLootWorldforgedDB.slotCache = AtlasLootWorldforgedDB.slotCache or {}
    local cache = AtlasLootWorldforgedDB.slotCache

    if cache[itemID] then return cache[itemID] end

    local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(itemID)
    if equipSlot and equipSlot ~= "" and SLOT_CATEGORY[equipSlot] then
        cache[itemID] = SLOT_CATEGORY[equipSlot]
        return cache[itemID]
    end
    return nil
end

--- Si data est une version upgrade (possède upgradeOf), hérite les locations de l'item de base.
--- Permet à TomTom et au menu de trouver où farmer l'item de base.
local function WF_FollowUpgradeOf(data)
    if not data or not data.upgradeOf then return data end
    if data.locations and #data.locations > 0 then return data end  -- déjà des locations

    local baseID = data.upgradeOf
    local baseSt = AtlasLootWF_StaticDB  and AtlasLootWF_StaticDB.items  and AtlasLootWF_StaticDB.items[baseID]
    local baseRt = AtlasLootWorldforgedDB and AtlasLootWorldforgedDB.items and AtlasLootWorldforgedDB.items[baseID]
    local locs   = (baseRt and baseRt.locations and #baseRt.locations > 0 and baseRt.locations)
               or  (baseSt and baseSt.locations and #baseSt.locations > 0 and baseSt.locations)
    if not locs then return data end

    local copy = {}
    for k, v in pairs(data) do copy[k] = v end
    copy.locations = locs
    return copy
end

--- Retourne les données fusionnées pour un itemID, ou nil s'il est inconnu.
--- Appelée aussi depuis LootButtons.lua pour le menu TomTom.
function AtlasLootWF_GetItemData(itemID)
    if not itemID then return nil end
    local static  = AtlasLootWF_StaticDB  and AtlasLootWF_StaticDB.items  and AtlasLootWF_StaticDB.items[itemID]
    local runtime = AtlasLootWorldforgedDB and AtlasLootWorldforgedDB.items and AtlasLootWorldforgedDB.items[itemID]

    if not static and not runtime then return nil end

    -- Si les deux existent, fusionner les locations (pas de doublon de zone)
    if static and runtime then
        local merged = {
            name        = runtime.name      ~= "Unknown" and runtime.name      or static.name,
            slot        = runtime.slot      ~= "Other"   and runtime.slot      or static.slot,
            expansion   = runtime.expansion or static.expansion,
            upgradeOf   = runtime.upgradeOf or static.upgradeOf,
            upgradeID   = runtime.upgradeID or static.upgradeID,
            isNPCUpgrade = runtime.isNPCUpgrade or static.isNPCUpgrade,
            locations   = {},
        }
        -- Ajouter toutes les locations (static en premier, runtime en deuxième si zone nouvelle)
        local seen = {}
        for _, loc in ipairs(static.locations or {}) do
            if not seen[loc.zone] then
                seen[loc.zone] = true
                table.insert(merged.locations, loc)
            end
        end
        for _, loc in ipairs(runtime.locations or {}) do
            if not seen[loc.zone] then
                seen[loc.zone] = true
                table.insert(merged.locations, loc)
            end
        end
        -- Résolution de slot via cache ou GetItemInfo si toujours "Unknown"
        if merged.slot == "Unknown" or merged.slot == "Other" then
            local resolved = ResolveSlot(itemID)
            if resolved then merged.slot = resolved end
        end
        return WF_FollowUpgradeOf(merged)
    end

    -- Un seul des deux existe : tenter la résolution de slot aussi
    local single = static or runtime
    if single and (single.slot == "Unknown" or single.slot == "Other") then
        local resolved = ResolveSlot(itemID)
        if resolved then
            local copy = {}
            for k, v in pairs(single) do copy[k] = v end
            copy.slot = resolved
            return WF_FollowUpgradeOf(copy)
        end
    end
    return WF_FollowUpgradeOf(single)
end

-- ============================================================
-- Export vers WorldforgedDB.lua (via SavedVariables)
-- ============================================================

local function WF_DoExport()
    local runtimeItems = AtlasLootWorldforgedDB and AtlasLootWorldforgedDB.items or {}
    local staticItems  = AtlasLootWF_StaticDB   and AtlasLootWF_StaticDB.items  or {}

    -- Union static + runtime
    local allItemIDs = {}
    for id in pairs(runtimeItems) do allItemIDs[id] = true end
    for id in pairs(staticItems)  do allItemIDs[id] = true end

    local itemLines = {}
    local count = 0

    for itemID in pairs(allItemIDs) do
        local mergedData = AtlasLootWF_GetItemData(itemID) or runtimeItems[itemID] or staticItems[itemID]
        local locs = {}
        for _, loc in ipairs(mergedData.locations or {}) do
            local locStr = string.format(
                '{ zone="%s", x=%.2f, y=%.2f, c=%d, z=%d }',
                (loc.zone or "Unknown"):gsub('"', '\\"'),
                loc.x or 0, loc.y or 0,
                loc.c or 0, loc.z or 0
            )
            table.insert(locs, locStr)
        end
        local name = (mergedData.name or "Unknown"):gsub('"', '\\"')
        local extraFields = ""
        if mergedData.upgradeOf then extraFields = extraFields .. string.format(", upgradeOf=%d", mergedData.upgradeOf) end
        if mergedData.upgradeID then extraFields = extraFields .. string.format(", upgradeID=%d", mergedData.upgradeID) end
        local line = string.format(
            '    [%d] = { name="%s", slot="%s", expansion="%s"%s, locations={ %s } },',
            itemID, name,
            mergedData.slot or "Other",
            mergedData.expansion or "CLASSIC",
            extraFields,
            table.concat(locs, ", ")
        )
        table.insert(itemLines, line)
        count = count + 1
    end

    -- Générer le fichier complet (sera lu par generate-wf-db.ps1)
    local fileLines = {
        "-- WorldforgedDB.lua",
        "-- DB statique des items Worldforged (generee par /wfexport)",
        "-- Commitez sur Git pour partager avec d'autres joueurs.",
        "",
        "AtlasLootWF_StaticDB = {",
        "    items = {",
    }
    for _, l in ipairs(itemLines) do
        table.insert(fileLines, l)
    end
    table.insert(fileLines, "    },")
    table.insert(fileLines, "}")
    table.insert(fileLines, "")

    AtlasLootWF_ExportBuffer = table.concat(fileLines, "\n")

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF Export]|r " .. count .. " item(s) — fais |cffff9900/reload|r puis lance |cffff9900generate-wf-db.ps1|r")
end

-- /wfadd <lien item>
-- Enregistre manuellement un item Worldforged à la position actuelle.
-- Utile pour les items obtenus via PNJ (pas de LOOT_OPENED).
-- Usage: shift-clic sur l'item → copier le lien → /wfadd [lien]
SLASH_WFADD1 = "/wfadd"
SlashCmdList["WFADD"] = function(msg)
    local link = msg:match("|%x+|Hitem:%d+[^|]*|h%[.-%]|h|r")
    if not link then
        local id = tonumber(msg:match("(%d+)"))
        if not id then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[WF]|r Usage: /wfadd [lien item]")
            DEFAULT_CHAT_FRAME:AddMessage("  Shift-clic sur l'item pour obtenir le lien, puis collez-le après /wfadd")
            return
        end
        link = "item:" .. id .. ":0:0:0:0:0:0:0"
    end
    local location = GetPlayerLocation()
    SaveWorldforgedItem(link, location)
end

-- /wfdebug
-- Affiche le log buffer WF et l'état des tables
SLASH_WFDEBUG1 = "/wfdebug"
SlashCmdList["WFDEBUG"] = function()
    local buf = AtlasLootWF_LogBuffer or {}
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF Debug]|r " .. #buf .. " ligne(s) de log:")
    local start = math.max(1, #buf - 19)  -- 20 dernières lignes
    for i = start, #buf do
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[WF]|r " .. tostring(buf[i]))
    end
    local rtCount, stCount = 0, 0
    if AtlasLootWorldforgedDB and AtlasLootWorldforgedDB.items then
        for _ in pairs(AtlasLootWorldforgedDB.items) do rtCount = rtCount + 1 end
    end
    if AtlasLootWF_StaticDB and AtlasLootWF_StaticDB.items then
        for _ in pairs(AtlasLootWF_StaticDB.items) do stCount = stCount + 1 end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r StaticDB: " .. stCount .. "  RuntimeDB: " .. rtCount)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r Debug mode: " .. tostring(AtlasLootWF_Debug))
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r RPGItemStore hook\u00e9e: " .. tostring(rpgStoreHooked))
end

-- /wfrpgscan
-- Force un scan manuel du RPGItemStore (utile si OnShow n'a pas d\u00e9clench\u00e9).

-- /wfscanbags
-- Scanne tous les sacs pour d\u00e9tecter les items Worldforged d\u00e9j\u00e0 dans l'inventaire.
SLASH_WFSCANBAGS1 = "/wfscanbags"
SlashCmdList["WFSCANBAGS"] = function()
    local location = GetPlayerLocation()
    local tt = GetScanner()
    local found, skipped = 0, 0
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                tt:ClearLines()
                tt:SetHyperlink(link)
                local isWF = false
                for i = 1, tt:NumLines() do
                    local left = _G["AtlasLootWFScanTooltipTextLeft" .. i]
                    if left then
                        local text = left:GetText()
                        if text and text:find("Worldforged", 1, true) then
                            isWF = true
                            break
                        end
                    end
                end
                if isWF then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    local db = AtlasLootWorldforgedDB.items
                    if itemID and db[itemID] then
                        skipped = skipped + 1
                    else
                        SaveWorldforgedItem(link, location)
                        found = found + 1
                    end
                end
            end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r Scan sacs termin\u00e9: |cff00ff00" .. found .. " nouveau(x)|r, " .. skipped .. " d\u00e9j\u00e0 enregistr\u00e9(s)")
    if found == 0 and skipped == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[WF]|r Aucun item Worldforged d\u00e9tect\u00e9 dans les sacs (tooltip ne contient pas 'Worldforged'?)")
    end
end

SLASH_WFEXPORT1 = "/wfexport"
SlashCmdList["WFEXPORT"] = function()
    local ok, err = pcall(WF_DoExport)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[WF Export] ERREUR:|r " .. tostring(err))
    end
end

-- /wfexportcontrib [NomJoueur]
-- Exporte les items vers AtlasLootWF_ContribExport (table Lua) dans les SavedVariables.
-- Après /reload, ouvrir AtlasLoot.lua, copier AtlasLootWF_ContribExport = { ... },
-- renommer en  AtlasLootWF_Contribs["NomJoueur"] = {  et sauver en WorldforgedData/NOM.lua
SLASH_WFEXPORTCONTRIB1 = "/wfexportcontrib"
SlashCmdList["WFEXPORTCONTRIB"] = function(arg)
    local contribName = (arg and arg:match("^(%S+)")) or UnitName("player") or "Unknown"
    local db = AtlasLootWorldforgedDB and AtlasLootWorldforgedDB.items
    if not db then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[WF]|r DB runtime vide — rien à exporter")
        return
    end

    AtlasLootWF_ContribExport = {}
    local count = 0
    for itemID, data in pairs(db) do
        local merged = AtlasLootWF_GetItemData(itemID) or data
        local locs = {}
        for _, loc in ipairs(merged.locations or {}) do
            if loc.zone ~= "Localisation inconnue" then
                table.insert(locs, { zone=loc.zone, x=loc.x, y=loc.y, c=loc.c, z=loc.z })
            end
        end
        local entry = {
            name      = merged.name      or "Unknown",
            slot      = merged.slot      or "Other",
            expansion = merged.expansion or "CLASSIC",
            locations = locs,
        }
        if merged.upgradeOf then entry.upgradeOf = merged.upgradeOf end
        if merged.upgradeID  then entry.upgradeID  = merged.upgradeID  end
        AtlasLootWF_ContribExport[itemID] = entry
        count = count + 1
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF Contrib]|r " .. count .. " item(s) exportés pour |cffff9900" .. contribName)
    DEFAULT_CHAT_FRAME:AddMessage("  |cffff9900/reload|r → ouvrir AtlasLoot.lua → copier |cffff9900AtlasLootWF_ContribExport|r")
    DEFAULT_CHAT_FRAME:AddMessage("  Renommer la 1ère ligne en : |cffaaaaaa AtlasLootWF_Contribs[\"" .. contribName .. "\"] = {")
    DEFAULT_CHAT_FRAME:AddMessage("  Sauver en : |cffaaaaaa WorldforgedData/" .. contribName .. ".lua")
end

-- /wflink <baseID> <upgradeID>
-- Enregistre le lien entre un item de base (loote en exploration) et sa version 60 (obtenue au PNJ).
-- Exemple : /wflink 454212 1388204
SLASH_WFLINK1 = "/wflink"
SlashCmdList["WFLINK"] = function(args)
    local baseID, upgradeID = args:match("(%d+)%s+(%d+)")
    baseID    = tonumber(baseID)
    upgradeID = tonumber(upgradeID)
    if not baseID or not upgradeID then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[WF]|r Usage : /wflink <baseID> <upgradeID>")
        DEFAULT_CHAT_FRAME:AddMessage("  ex: /wflink 454212 1388204")
        return
    end

    local db = AtlasLootWorldforgedDB.items

    -- Enregistrer upgradeID sur l'item de base
    if db[baseID] then
        db[baseID].upgradeID = upgradeID
    else
        local bName, _, _, _, _, _, _, _, bSlot = GetItemInfo(baseID)
        db[baseID] = {
            name      = bName or "Unknown",
            slot      = (bSlot and SLOT_CATEGORY[bSlot]) or ResolveSlot(baseID) or "Unknown",
            expansion = "CLASSIC",
            upgradeID = upgradeID,
            locations = {},
        }
    end

    -- Créer/mettre à jour l'entrée de la version 60
    local uName, _, _, _, _, _, _, _, uSlot = GetItemInfo(upgradeID)
    db[upgradeID] = db[upgradeID] or {}
    db[upgradeID].name      = (uName and uName ~= "") and uName or db[upgradeID].name or "Unknown"
    db[upgradeID].slot      = (uSlot and uSlot ~= "" and SLOT_CATEGORY[uSlot])
                           or ResolveSlot(upgradeID)
                           or db[upgradeID].slot or "Unknown"
    db[upgradeID].expansion = db[upgradeID].expansion or "CLASSIC"
    db[upgradeID].upgradeOf = baseID
    db[upgradeID].locations = db[upgradeID].locations or {}

    local baseName    = db[baseID].name
    local upgradeName = db[upgradeID].name
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r Lien enregistré :")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00" .. baseName .. "|r (" .. baseID .. ") → |cff00ccff" .. upgradeName .. "|r (" .. upgradeID .. ")")
    DEFAULT_CHAT_FRAME:AddMessage("  Lance |cffff9900/wfexport|r pour sauvegarder.")
end

-- ============================================================
-- Construction des tables AtlasLoot (par slot d'équipement)
-- ============================================================
local MAX_ITEMS_PER_COL = 18

-- Construit des paires (base | upgrade) comme l'affichage forge d'AtlasLoot.
-- col1 = item de base (ou standalone), col2 = item upgradé correspondant (ou 0).
local function BuildPairedRows(itemIDs)
    local col1, col2 = {}, {}
    local seen = {}

    -- Pass 1 : items de base (sans upgradeOf, et pas un upgrade NPC non-lié)
    -- contentsPreview = { upgradeID } → L-Click ouvre le popup avec l'upgrade
    for _, id in ipairs(itemIDs) do
        if not seen[id] then
            local data = AtlasLootWF_GetItemData(id)
            if data and not data.upgradeOf and not data.isNPCUpgrade then
                seen[id] = true
                local upgradeID = data.upgradeID
                if upgradeID then
                    seen[upgradeID] = true
                    table.insert(col1, { itemID = id, contentsPreview = { upgradeID } })
                else
                    table.insert(col1, { itemID = id })
                end
            end
        end
    end

    -- Pass 2 : upgrades orphelins (upgradeOf set mais base absente de cette liste)
    for _, id in ipairs(itemIDs) do
        if not seen[id] then
            seen[id] = true
            table.insert(col1, { itemID = id })
        end
    end

    return col1, col2
end

function AtlasLoot_BuildWorldforgedTables()
    -- Fusionner DB statique + SavedVariables
    local allItemIDs = {}
    local staticItems  = (AtlasLootWF_StaticDB   or {}).items or {}
    local runtimeItems = (AtlasLootWorldforgedDB  or {}).items or {}
    for id in pairs(staticItems)  do allItemIDs[id] = true end
    for id in pairs(runtimeItems) do allItemIDs[id] = true end

    -- Grouper par expansion → slot (avec données fusionnées)
    local byExpSlot = {}
    for itemID in pairs(allItemIDs) do
        local data = AtlasLootWF_GetItemData(itemID)
        if data then
            local exp  = data.expansion or "CLASSIC"
            local slot = data.slot or "Other"
            byExpSlot[exp] = byExpSlot[exp] or {}
            byExpSlot[exp][slot] = byExpSlot[exp][slot] or {}
            table.insert(byExpSlot[exp][slot], itemID)
        end
    end

    for _, exp in ipairs({ "CLASSIC", "TBC", "WRATH" }) do
        local menuKey = "Worldforged" .. exp
        -- La clé dans AtlasLoot_Data porte le même nom (tables différentes, pas de conflit)
        local dataKey = menuKey

        local slots = byExpSlot[exp] or {}

        -- Vérifier s'il y a des items pour cette expansion
        local hasItems = false
        for _, slotName in ipairs(SLOT_ORDER) do
            if slots[slotName] and #slots[slotName] > 0 then
                hasItems = true
                break
            end
        end

        if not hasItems then
            -- Pas d'items : SubMenu factice + table vide
            local emptyKey = "Worldforged_NoItems_" .. exp
            AtlasLoot_SubMenus[menuKey] = {
                Module  = "AtlasLoot",
                SubMenu = menuKey,
                { "", emptyKey, "", "No items discovered yet" },
            }
            AtlasLoot_Data[emptyKey] = {
                Module = "AtlasLoot",
                Name   = "Worldforged - No items discovered yet",
                { Name = "Worldforged", {} },
            }
        else
            -- Construire AtlasLoot_Data[dataKey] avec une entrée par slot
            -- → le panneau de droite affichera automatiquement la liste des slots
            local dataTable = {
                Module = "AtlasLoot",
                Name   = "Worldforged",
            }
            for _, slotName in ipairs(SLOT_ORDER) do
                local itemIDs = slots[slotName]
                if itemIDs and #itemIDs > 0 then
                    -- Trier pour cohérence (bases d'abord, upgrades ensuite via les données)
                    table.sort(itemIDs)
                    local col1, col2 = BuildPairedRows(itemIDs)
                    table.insert(dataTable, { Name = slotName, col1, col2 })
                end
            end
            AtlasLoot_Data[dataKey] = dataTable

            -- SubMenu : une seule entrée vers la table de données
            AtlasLoot_SubMenus[menuKey] = {
                Module  = "AtlasLoot",
                SubMenu = menuKey,
                { "", dataKey },
            }
        end
    end

    WFLog("BuildWorldforgedTables terminé")
end

-- ============================================================
-- Hook RPGItemStore (fenêtre upgrade Worldforged — Guardian of Time)
-- Les boutons RPGItemStoreItem1..N ont un champ .itemID
-- ============================================================

--- Cherche dans static+runtime DB un item avec le même nom mais un ID différent.
--- Retourne baseID si on trouve un candidat "item de base" (a des locations, ou ilvl plus bas).
local function FindBaseItemByName(upgradeID, upgradeName)
    if not upgradeName or upgradeName == "Unknown" then return nil end
    local _, _, _, upgradeIlvl = GetItemInfo(upgradeID)

    local staticItems  = (AtlasLootWF_StaticDB   or {}).items or {}
    local runtimeItems = (AtlasLootWorldforgedDB  or {}).items or {}

    local bestID, bestScore = nil, -1
    local function check(baseID, data)
        if baseID == upgradeID then return end
        if data.name ~= upgradeName then return end
        -- Score : +2 si a des locations (trouvé en terrain), +1 si ilvl plus bas
        local score = 0
        if data.locations and #data.locations > 0 then score = score + 2 end
        local _, _, _, baseIlvl = GetItemInfo(baseID)
        if baseIlvl and upgradeIlvl and baseIlvl < upgradeIlvl then score = score + 1 end
        if score > bestScore then bestScore = score; bestID = baseID end
    end
    for id, data in pairs(staticItems)  do check(id, data) end
    for id, data in pairs(runtimeItems) do check(id, data) end

    return bestID  -- nil si aucun candidat
end

-- Cherche dans les sacs du joueur un item avec le même nom (pas l'upgrade lui-même).
-- Le PNJ ne montre des upgrades que pour les items que le joueur POSSÈDE → la base est en sac.
local function FindBaseItemInBags(name, excludeID)
    if not name then return nil end
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = tonumber(link:match("item:(%d+)"))
                if id and id ~= excludeID then
                    local iName = GetItemInfo(id)
                    if iName == name then
                        return id
                    end
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- Auto-lien par nom + ilvl : le plus petit ilvl = parent (base)
-- Appelé après chaque ajout d'items (loot, scan NPC, sacs au démarrage)
-- ============================================================
local function AutoLinkByName()
    local db = AtlasLootWorldforgedDB and AtlasLootWorldforgedDB.items
    if not db then return 0 end
    local staticItems = (AtlasLootWF_StaticDB or {}).items or {}

    -- Grouper tous les items connus par nom → { {id, ilvl}, ... }
    local byName = {}
    local function addEntry(id, data)
        local name = data.name
        if not name or name == "Unknown" or name:find("^ID:") then return end
        byName[name] = byName[name] or {}
        local _, _, _, ilvl = GetItemInfo(id)
        table.insert(byName[name], { id = id, ilvl = ilvl or 0 })
    end
    for id, data in pairs(db)          do addEntry(id, data) end
    for id, data in pairs(staticItems) do if not db[id] then addEntry(id, data) end end

    local linked = 0
    for name, items in pairs(byName) do
        if #items >= 2 then
            -- Trier par ilvl croissant → ilvl min = parent
            table.sort(items, function(a, b) return (a.ilvl or 0) < (b.ilvl or 0) end)
            local baseID = items[1].id
            for i = 2, #items do
                local upgradeID = items[i].id
                local baseEntry    = db[baseID]
                local upgradeEntry = db[upgradeID]
                if baseEntry and not baseEntry.upgradeID then
                    baseEntry.upgradeID = upgradeID
                    linked = linked + 1
                    WFLog("AutoLink base→upgrade: "..baseID.." → "..upgradeID.." ["..name.."]")
                end
                if upgradeEntry and not upgradeEntry.upgradeOf then
                    upgradeEntry.upgradeOf   = baseID
                    upgradeEntry.isNPCUpgrade = true
                    linked = linked + 1
                end
            end
        end
    end

    if linked > 0 then
        WFLog("AutoLinkByName: "..linked.." lien(s) créé(s)")
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r "..linked.." lien(s) base↔upgrade auto-détecté(s)")
    end
    return linked
end

-- ============================================================
-- Scan des sacs au démarrage — délai 5s pour le cache client
-- ============================================================
local function StartupBagScan()
    local elapsed = 0
    local scanFrame = CreateFrame("Frame")
    scanFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 5 then return end
        self:SetScript("OnUpdate", nil)

        local db = AtlasLootWorldforgedDB and AtlasLootWorldforgedDB.items
        if not db then return end
        local tt       = GetScanner()
        local location = { zone = "Localisation inconnue", subzone = "", x = 0, y = 0, c = 0, z = 0 }
        local found    = 0

        for bag = 0, 4 do
            for slot = 1, GetContainerNumSlots(bag) do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    if itemID and not db[itemID] then
                        tt:ClearLines()
                        tt:SetHyperlink(link)
                        for i = 1, tt:NumLines() do
                            local left = _G["AtlasLootWFScanTooltipTextLeft" .. i]
                            if left then
                                local text = left:GetText()
                                if text and text:find("Worldforged", 1, true) then
                                    SaveWorldforgedItem(link, location)
                                    found = found + 1
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        local newLinks = AutoLinkByName()
        if found > 0 or newLinks > 0 then
            pcall(AtlasLoot_BuildWorldforgedTables)
            if found > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r Scan sacs démarrage: |cff00ff00"..found.." nouveau(x)|r")
            end
        end
        WFLog("StartupBagScan terminé: "..found.." trouvé(s), "..newLinks.." lien(s)")
    end)
end

-- Force le cache client pour un item via tooltip invisible, puis retourne GetItemInfo
local function GetItemInfoCached(id)
    local name, lnk, q, lvl, minLvl, t, sub, ms, es, tex, sv = GetItemInfo(id)
    if not name then
        -- Déclenche la requête serveur
        local tt = GetScanner()
        tt:ClearLines()
        tt:SetItemByID(id)
        name, lnk, q, lvl, minLvl, t, sub, ms, es, tex, sv = GetItemInfo(id)
    end
    return name, es  -- nom + equipSlot suffisent pour la DB
end

local function ScanRPGItemStore()
    local db = AtlasLootWorldforgedDB and AtlasLootWorldforgedDB.items
    if not db then
        WFLog("ScanRPGItemStore: DB nil, abandon")
        return
    end
    WFLog("ScanRPGItemStore: début scan")
    local found, updated, skipped = 0, 0, 0
    for i = 1, 20 do
        local btn = _G["RPGItemStoreItem" .. i]
        if btn then
            local rawID = btn.itemID
            if rawID then
                local id = tonumber(rawID)
                if id then
                    local existing = db[id]
                    if not existing then
                        -- Nouvel item
                        local name, equipSlot = GetItemInfoCached(id)
                        local slotCat = (equipSlot and SLOT_CATEGORY[equipSlot]) or "Other"
                        db[id] = {
                            name         = name or ("ID:"..id),
                            slot         = slotCat,
                            expansion    = "CLASSIC",
                            locations    = {},
                            isNPCUpgrade = true,  -- vient du scan PNJ Guardian of Time
                        }
                        found = found + 1
                        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r +NPC upgrade: ["..(name or id).."]")

                        -- Cherche l'item de BASE dans les sacs (le PNJ ne montre que les items possédés)
                        local bagBaseID = FindBaseItemInBags(name, id)
                        if bagBaseID then
                            local bName, bEquipSlot = GetItemInfoCached(bagBaseID)
                            local bSlot = (bEquipSlot and SLOT_CATEGORY[bEquipSlot]) or slotCat
                            if not db[bagBaseID] then
                                db[bagBaseID] = {
                                    name      = bName or name,
                                    slot      = bSlot,
                                    expansion = "CLASSIC",
                                    locations = {},  -- base trouvée en sac : localisation inconnue
                                    upgradeID = id,
                                }
                                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r  └ base en sac: ["..(bName or name).."] ("..bagBaseID..")")
                                found = found + 1
                            elseif not db[bagBaseID].upgradeID then
                                db[bagBaseID].upgradeID = id
                            end
                            db[id].upgradeOf = bagBaseID
                        else
                            -- Fallback : cherche dans DB existante par nom
                            local baseID = name and FindBaseItemByName(id, name)
                            if baseID then
                                db[id].upgradeOf = baseID
                                local baseEntry = db[baseID] or (AtlasLootWF_StaticDB and AtlasLootWF_StaticDB.items and AtlasLootWF_StaticDB.items[baseID])
                                if baseEntry then baseEntry.upgradeID = id end
                                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r  └ auto-lien DB: base="..baseID)
                            else
                                DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[WF]|r  └ base introuvable — /wflink "..id)
                            end
                        end
                    elseif existing.name == "Unknown" or existing.name:find("^ID:") then
                        -- Item déjà en DB mais sans nom : retenter
                        local name, equipSlot = GetItemInfoCached(id)
                        if name then
                            existing.name = name
                            if equipSlot then existing.slot = SLOT_CATEGORY[equipSlot] or existing.slot end
                            updated = updated + 1
                            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r ~MàJ: ["..name.."] ("..id..")")
                        else
                            skipped = skipped + 1
                        end
                    else
                        skipped = skipped + 1
                    end
                end
            end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r Scan NPC: |cff00ff00"..found.." nouveau(x)|r, "..updated.." mis à jour, "..skipped.." déjà OK")
    if found + updated > 0 then
        AutoLinkByName()
        pcall(AtlasLoot_BuildWorldforgedTables)
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[WF]|r Ferme et rouvre AtlasLoot pour voir les changements")
    end
end

-- Attend que les boutons RPGItemStoreItem aient leur itemID, puis scanne.
-- Délai fixe insuffisant à la 1ère ouverture (données serveur pas encore arrivées).
local function ScanRPGItemStoreDelayed()
    local ticker  = CreateFrame("Frame")
    local elapsed = 0
    local total   = 0
    ticker:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        total   = total   + dt
        if elapsed < 0.1 then return end  -- check toutes les 0.1s
        elapsed = 0

        -- Est-ce qu'au moins un bouton a son itemID ?
        local hasItems = false
        for i = 1, 20 do
            local btn = _G["RPGItemStoreItem" .. i]
            if btn and btn.itemID then hasItems = true; break end
        end

        if hasItems or total >= 5 then  -- scan dès que prêt, ou abandon après 5s
            self:SetScript("OnUpdate", nil)
            if hasItems then
                ScanRPGItemStore()
            else
                WFLog("ScanRPGItemStoreDelayed: timeout 5s, aucun itemID trouvé")
            end
        end
    end)
end

local rpgStoreHooked = false
local function HookRPGItemStore()
    if rpgStoreHooked then return true end
    local store = _G["RPGItemStore"]
    if not store then
        WFLog("RPGItemStore introuvable")
        return false
    end
    store:HookScript("OnShow", ScanRPGItemStoreDelayed)  -- délai 2 frames car itemID pas dispo au OnShow
    local nextBtn = _G["RPGItemStoreNextPageButton"]
    local prevBtn = _G["RPGItemStorePreviousPageButton"]
    if nextBtn then nextBtn:HookScript("OnClick", ScanRPGItemStoreDelayed) end
    if prevBtn then prevBtn:HookScript("OnClick", ScanRPGItemStoreDelayed) end
    rpgStoreHooked = true
    WFLog("RPGItemStore hookée (" .. (nextBtn and "avec" or "sans") .. " pagination)")
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r RPGItemStore hookée — ouverture du PNJ auto-scannée")

    -- Si la fenêtre est DÉJÀ visible quand on pose le hook (cas fréquent : le retry
    -- détecte la frame APRÈS que le joueur a ouvert le PNJ), on scanne immédiatement.
    if store:IsVisible() then
        WFLog("RPGItemStore déjà visible — scan immédiat")
        ScanRPGItemStoreDelayed()
    end

    return true
end

-- Retry si RPGItemStore n'existait pas encore au PLAYER_LOGIN (frame lazy Ascension)
local function StartRPGStoreRetry()
    local retryFrame = CreateFrame("Frame")
    local lastCheck  = 0

    -- GOSSIP_SHOW = le joueur vient d'ouvrir un dialogue NPC → on force un check immédiat
    -- car RPGItemStore peut apparaître dans les secondes qui suivent (clic sur l'option upgrade)
    retryFrame:RegisterEvent("GOSSIP_SHOW")
    retryFrame:SetScript("OnEvent", function(self, event)
        lastCheck = 0  -- prochain OnUpdate = check immédiat
    end)

    retryFrame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        if now - lastCheck < 0.5 then return end
        lastCheck = now
        if HookRPGItemStore() then
            self:SetScript("OnUpdate", nil)
            self:UnregisterEvent("GOSSIP_SHOW")
        end
    end)
end

-- /wfrpgscan — scan manuel (défini ICI car ScanRPGItemStore est local au-dessus)
SLASH_WFRPGSCAN1 = "/wfrpgscan"
SlashCmdList["WFRPGSCAN"] = function()
    if not _G["RPGItemStore"] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[WF]|r RPGItemStore introuvable — ouvre d'abord la fenêtre du PNJ")
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r Scan RPGItemStore forcé...")
    ScanRPGItemStore()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r Scan terminé — utilise /wfdebug pour voir les logs")
end

-- /wfrpgdump — inspecte les enfants de RPGItemStore pour trouver les vrais noms de boutons
SLASH_WFRPGDUMP1 = "/wfrpgdump"
SlashCmdList["WFRPGDUMP"] = function()
    local store = _G["RPGItemStore"]
    if not store then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[WF]|r RPGItemStore introuvable")
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r RPGItemStore children ("..(store:GetNumChildren()).." enfants, "..(store:GetNumRegions()).." régions):")
    for i = 1, store:GetNumChildren() do
        local child = select(i, store:GetChildren())
        if child then
            local n = child:GetName() or "(sans nom)"
            local t = child:GetObjectType() or "?"
            local rawID = child.itemID
            DEFAULT_CHAT_FRAME:AddMessage("  ["..i.."] "..t.." '"..n.."' itemID="..tostring(rawID))
        end
    end
end

-- ============================================================
-- Event handler principal
-- ============================================================
local wfFrame = CreateFrame("Frame", "AtlasLootWFFrame")
wfFrame:RegisterEvent("PLAYER_LOGIN")
wfFrame:RegisterEvent("LOOT_OPENED")

wfFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        AtlasLootWF_LogBuffer = {}
        WFLog("PLAYER_LOGIN")
        AtlasLootWorldforgedDB = AtlasLootWorldforgedDB or {}
        AtlasLootWorldforgedDB.items     = AtlasLootWorldforgedDB.items     or {}
        AtlasLootWorldforgedDB.slotCache = AtlasLootWorldforgedDB.slotCache or {}
        MigrateDB()
        FixupSlots()
        local count = 0; for _ in pairs(AtlasLootWorldforgedDB.items) do count = count + 1 end
        WFLog("DB : " .. count .. " item(s) enregistré(s)")
        local ok, err = pcall(AtlasLoot_BuildWorldforgedTables)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[WF] ERREUR BuildWorldforgedTables: |r" .. tostring(err))
        end
        if not HookRPGItemStore() then
            StartRPGStoreRetry()  -- RPGItemStore pas encore créée, on réessaie toutes les 2s
        end
        StartupBagScan()  -- scan des sacs après 5s (cache client)
        self:UnregisterEvent("PLAYER_LOGIN")

    elseif event == "LOOT_OPENED" then
        local n = GetNumLootItems()
        WFLog("LOOT_OPENED : " .. n .. " slot(s)")
        if AtlasLootWF_Debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff66[WF]|r LOOT_OPENED: " .. n .. " slot(s)")
        end
        if n == 0 then return end
        local location = GetPlayerLocation()
        local wfFound = false
        for slot = 1, n do
            local link = GetLootSlotLink(slot)
            if link then   -- seuls les items ont un lien (pas les money/currency)
                if IsLootSlotWorldforged(slot) then
                    WFLog("Worldforged slot " .. slot .. ": " .. link)
                    SaveWorldforgedItem(link, location)
                    wfFound = true
                elseif AtlasLootWF_Debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[WF]|r slot " .. slot .. ": " .. link .. " — pas Worldforged")
                end
            end
        end
        if wfFound then
            local newLinks = AutoLinkByName()
            if newLinks > 0 then
                pcall(AtlasLoot_BuildWorldforgedTables)
            end
        end
    end
end)
