-- WorldforgedDB.lua
-- DB statique des items Worldforged (generee par /wfexport)
-- Commitez sur Git pour partager avec d'autres joueurs.

AtlasLootWF_StaticDB = {
    items = {
    [450753] = { name="Orcish Fishing Device", slot="Two-Hand", expansion="CLASSIC", locations={ { zone="Durotar", x=37.01, y=22.44, c=1, z=5 } } },
    },
}

-- ============================================================
-- Fusion des contributions communautaires (WorldforgedData/*.lua)
-- AtlasLootWF_Contribs est peuplé avant ce fichier (voir embeds.xml)
-- ============================================================
do
    local contribs = AtlasLootWF_Contribs
    if contribs then
        local static = AtlasLootWF_StaticDB.items
        for playerName, items in pairs(contribs) do
            for id, data in pairs(items) do
                if not static[id] then
                    static[id] = data
                else
                    -- Item déjà connu : fusionner les localisations uniquement
                    local existing = static[id]
                    existing.locations = existing.locations or {}
                    for _, loc in ipairs(data.locations or {}) do
                        local dupe = false
                        for _, eloc in ipairs(existing.locations) do
                            if eloc.zone == loc.zone then dupe = true; break end
                        end
                        if not dupe then
                            table.insert(existing.locations, loc)
                        end
                    end
                end
            end
        end
    end
end

