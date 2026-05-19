--[[
    WorldforgedMenus.lua
    Initialise les sous-menus Worldforged au chargement (avant PLAYER_LOGIN)
    pour que DewDropClick ne trouve jamais un SubMenu nil.
    Structure : une entrée "No items" par expansion.
    WorldforgedTracker.lua reconstruit les entrées par slot au PLAYER_LOGIN.
]]

-- Initialisation au chargement
local function WF_InitSubMenus()
    for _, _wf_exp in ipairs({ "CLASSIC", "TBC", "WRATH" }) do
        local _wf_menuKey  = "Worldforged" .. _wf_exp
        local _wf_emptyKey = "Worldforged_NoItems_" .. _wf_exp

        AtlasLoot_SubMenus[_wf_menuKey] = {
            Module  = "AtlasLoot",
            SubMenu = _wf_menuKey,
            { "", _wf_emptyKey, "", "No items discovered yet" },
        }

        AtlasLoot_Data[_wf_emptyKey] = {
            Module = "AtlasLoot",
            Name   = "Worldforged - No items discovered yet",
            { Name = "Worldforged", {} },
        }
    end
end

WF_InitSubMenus()

-- Commande de diagnostic rapide
SLASH_WFDEBUG1 = "/wfdebug"
SlashCmdList["WFDEBUG"] = function()
    for _, exp in ipairs({ "CLASSIC", "TBC", "WRATH" }) do
        local key = "Worldforged" .. exp
        local t = AtlasLoot_SubMenus[key]
        if t then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[WF]|r " .. key .. " OK (Module=" .. tostring(t.Module) .. ", #entries=" .. tostring(#t) .. ")")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[WF]|r " .. key .. " = nil !")
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[WF]|r Expac actuel: " .. tostring(AtlasLoot and AtlasLoot.Expac or "?"))
    local buf = AtlasLootWF_LogBuffer
    if buf and #buf > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[WF]|r Log buffer (" .. #buf .. " lignes) :")
        for i, line in ipairs(buf) do
            DEFAULT_CHAT_FRAME:AddMessage("  " .. i .. ": " .. tostring(line))
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[WF]|r Log buffer vide.")
    end
end

-- Filet de sécurité : re-garantir les SubMenus après PLAYER_LOGIN
-- (au cas où BuildWorldforgedTables aurait échoué)
local _wf_guardFrame = CreateFrame("Frame")
_wf_guardFrame:RegisterEvent("PLAYER_LOGIN")
_wf_guardFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    for _, exp in ipairs({ "CLASSIC", "TBC", "WRATH" }) do
        local menuKey = "Worldforged" .. exp
        if not AtlasLoot_SubMenus[menuKey] or not AtlasLoot_SubMenus[menuKey].Module then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[WF]|r SubMenu " .. menuKey .. " absent, réinitialisation.")
            local emptyKey = "Worldforged_NoItems_" .. exp
            AtlasLoot_SubMenus[menuKey] = {
                Module  = "AtlasLoot",
                SubMenu = menuKey,
                { "", emptyKey, "", "No items discovered yet" },
            }
            AtlasLoot_Data[emptyKey] = AtlasLoot_Data[emptyKey] or {
                Module = "AtlasLoot",
                Name   = "Worldforged - No items discovered yet",
                { Name = "Worldforged", {} },
            }
        end
    end
end)
