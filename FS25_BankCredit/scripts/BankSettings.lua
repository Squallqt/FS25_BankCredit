-- Copyright © 2026 Squallqt. All rights reserved.
---Provides bank settings, InGameMenu controls, and authoritative synchronization.
BankSettings = {}
BankSettings.CONTROLS = {}
BankSettings._menuInjected = false

BankSettings.menuItems = {
    'initialCapital',
    'leverageRatio',
    'dynamicRate',
    'baseInterestRate',
    'earlyRepaymentPenalty',
}

---Creates an integer range
-- @param integer from First value
-- @param integer to Last value
-- @param integer step Increment between values
-- @return table values Integer values
local function intRange(from, to, step)
    local t = {}
    for v = from, to, step do
        table.insert(t, v)
    end
    return t
end

---Creates a floating-point range
-- @param float from First value
-- @param float to Last value
-- @param float step Increment between values
-- @return table values Floating-point values
local function floatRange(from, to, step)
    local t = {}
    local n = math.floor((to - from) / step + 0.5) + 1
    for i = 0, n - 1 do
        table.insert(t, math.floor((from + i * step) * 10000 + 0.5) / 10000)
    end
    return t
end

local capitalValues  = intRange(100000, 5000000, 100000)   -- 50 entries; index 5  = 500 000
local leverageValues = intRange(5, 20, 1)                   -- 16 entries; index 6  = 10
local rateValues     = floatRange(InterestRateModel.MIN_RATE, InterestRateModel.MAX_RATE, 0.25)
local penaltyValues  = floatRange(0.0, 5.0, 0.5)            -- 11 entries; index 1  = 0.0

local capitalStrings, leverageStrings, rateStrings, penaltyStrings = {}, {}, {}, {}
for _, v in ipairs(capitalValues)  do table.insert(capitalStrings,  string.format("%d k€", v / 1000)) end
for _, v in ipairs(leverageValues) do table.insert(leverageStrings, tostring(v) .. "x") end
for _, v in ipairs(rateValues)     do table.insert(rateStrings,     string.format("%.2f %%", v)) end
for _, v in ipairs(penaltyValues)  do table.insert(penaltyStrings,  string.format("%.1f %%", v)) end

BankSettings.SETTINGS = {}

BankSettings.SETTINGS.initialCapital = {
    ['default']    = 5,
    ['serverOnly'] = true,
    ['type']       = 'multi',
    ['values']     = capitalValues,
    ['strings']    = capitalStrings,
}

BankSettings.SETTINGS.leverageRatio = {
    ['default']    = 6,
    ['serverOnly'] = true,
    ['type']       = 'multi',
    ['values']     = leverageValues,
    ['strings']    = leverageStrings,
}

BankSettings.SETTINGS.dynamicRate = {
    ['default']    = 2,
    ['serverOnly'] = true,
    ['type']       = 'binary',
    ['values']     = { false, true },
    ['strings']    = { "ui_off", "ui_on" },
}

BankSettings.SETTINGS.baseInterestRate = {
    ['default']    = 10,       -- index 10 = 3.50
    ['serverOnly'] = true,
    ['type']       = 'multi',
    ['values']     = rateValues,
    ['strings']    = rateStrings,
}

BankSettings.SETTINGS.earlyRepaymentPenalty = {
    ['default']    = 7,        -- index 7 = 3.0%
    ['serverOnly'] = true,
    ['type']       = 'multi',
    ['values']     = penaltyValues,
    ['strings']    = penaltyStrings,
}

-- Flat default values table — used as fallback in BankRepository load paths
BankSettings.DEFAULTS = {}
for id, def in pairs(BankSettings.SETTINGS) do
    BankSettings.DEFAULTS[id] = def.values[def.default]
end

---Returns state index for a setting value
-- @param string id Setting identifier
-- @param any? value Current value to look up
-- @return integer index State index
function BankSettings.getStateIndex(id, value)
    local current = value
    if current == nil and g_currentMission ~= nil and g_currentMission.bankSettings ~= nil then
        current = g_currentMission.bankSettings[id]
    end

    local values = BankSettings.SETTINGS[id].values

    for i, v in ipairs(values) do
        if current == v then
            return i
        end
    end

    return BankSettings.SETTINGS[id].default
end

---Apply the effects of a base-rate or dynamic-rate setting change.
-- @param float previousBaseRate Base rate before applying the settings
-- @param boolean previousDynamicRate Dynamic-rate state before applying the settings
-- @param boolean forceStaticRate Restore a disabled dynamic rate during initial load
function BankSettings.applyRateConfiguration(previousBaseRate, previousDynamicRate, forceStaticRate)
    local manager = BankCredit.manager
    local settings = g_currentMission.bankSettings
    local baseRateChanged = settings.baseInterestRate ~= previousBaseRate
    local dynamicRateChanged = settings.dynamicRate ~= previousDynamicRate
    local resetRate = baseRateChanged
        or (not settings.dynamicRate and (dynamicRateChanged or forceStaticRate))

    if resetRate then
        manager.rateModel:resetToRate(
            settings.baseInterestRate,
            g_currentMission.environment.currentYear
        )
    end
end

BankSettingsControls = {}

---Called when a menu option changes, applies locally and broadcasts to server
-- @param table self Settings callback target
-- @param integer state New state index
-- @param table menuOption Menu option element
function BankSettingsControls.onMenuOptionChanged(self, state, menuOption)
    local id = menuOption.id
    local value = BankSettings.SETTINGS[id].values[state]
    local previousBaseRate = g_currentMission.bankSettings.baseInterestRate
    local previousDynamicRate = g_currentMission.bankSettings.dynamicRate

    if value ~= nil and g_currentMission ~= nil and g_currentMission.bankSettings ~= nil then
        g_currentMission.bankSettings[id] = value
    end

    if g_client ~= nil and g_client.getServerConnection ~= nil then
        g_client:getServerConnection():sendEvent(BankSettingsEvent.new(g_currentMission.bankSettings))
    end

    -- The sender is excluded from the server rebroadcast, so apply both effects locally.
    if id == 'initialCapital' and value ~= nil then
        local bs = BankCredit.manager ~= nil and BankCredit.manager.bankService or nil
        if bs ~= nil then
            bs:applyInitialCapitalDelta(value)
        end
    end

    if BankCredit.manager ~= nil then
        BankSettings.applyRateConfiguration(previousBaseRate, previousDynamicRate, false)
    end
    if g_currentMission ~= nil and g_currentMission.bankFrame ~= nil then
        g_currentMission.bankFrame:refreshDashboard()
    end
end

---Applies settings, validates each value, and broadcasts if authoritative
-- @param table newSettings Settings table to apply
-- @param boolean isAuthoritative If true saves to XML and broadcasts to clients
function BankSettings:applySettings(newSettings, isAuthoritative)
    if g_currentMission == nil then return end

    g_currentMission.bankSettings = g_currentMission.bankSettings or {}
    local s = g_currentMission.bankSettings
    local previousBaseRate = s.baseInterestRate
    local previousDynamicRate = s.dynamicRate

    for _, id in ipairs(self.menuItems) do
        local def = self.SETTINGS[id]
        local candidate = nil
        if newSettings ~= nil then
            candidate = newSettings[id]
        end

        local ok = false
        for _, v in ipairs(def.values) do
            if candidate == v then
                ok = true
                break
            end
        end

        if ok then
            s[id] = candidate
        elseif s[id] == nil then
            s[id] = def.values[def.default]
        end
    end

    for _, id in ipairs(self.menuItems) do
        local ctrl = self.CONTROLS[id]
        if ctrl ~= nil then
            ctrl:setState(self.getStateIndex(id, s[id]))
        end
    end

    if BankCredit.manager ~= nil then
        -- Applying only the delta lets administrators recapitalize a live bank.
        local bs = BankCredit.manager.bankService
        if bs ~= nil and s.initialCapital ~= nil then
            bs:applyInitialCapitalDelta(s.initialCapital)
        end
        BankSettings.applyRateConfiguration(previousBaseRate, previousDynamicRate, not s.dynamicRate)
    end

    if isAuthoritative and g_currentMission:getIsServer() then
        self:saveToXMLFile()

        if g_server ~= nil then
            g_server:broadcastEvent(BankSettingsEvent.new(s), false)
        end
    end
end

---Saves current settings to savegame XML file
function BankSettings:saveToXMLFile()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_currentMission.missionInfo == nil then return end

    local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
    if savegameDirectory == nil then
        savegameDirectory = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end

    local manager = g_currentMission.bankManager
    if manager ~= nil and manager.repository ~= nil then
        manager.repository:saveSettingsToXML(savegameDirectory .. "/", g_currentMission.bankSettings or {})
    end
end

---Injects bank settings into the in-game settings menu
function BankSettings:injectMenu()
    if BankSettings._menuInjected then return end

    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil then return end

    local settingsPage = inGameMenu.pageSettings
    if settingsPage == nil then return end

    BankSettings._menuInjected = true
    BankSettingsControls.name = settingsPage.name

    ---Adds a multi-value bank setting control
    -- @param string id Setting identifier
    local function addMultiMenuOption(id)
        local i18n_title   = "bank_setting_" .. id
        local i18n_tooltip = "bank_toolTip_" .. id

        local menuOptionBox = BitmapElement.new()
        menuOptionBox:loadProfile(g_gui:getProfile("fs25_multiTextOptionContainer"), true)

        local menuMultiOption = MultiTextOptionElement.new()
        menuMultiOption:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOption"), true)
        menuMultiOption.id     = id
        menuMultiOption.target = BankSettingsControls
        menuMultiOption:setCallback("onClickCallback", "onMenuOptionChanged")

        local setting = TextElement.new()
        setting:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOptionTitle"), true)
        setting:setText(g_i18n:getText(i18n_title))

        local toolTip = TextElement.new()
        toolTip.name = "ignore"
        toolTip:loadProfile(g_gui:getProfile("fs25_multiTextOptionTooltip"), true)
        toolTip:setText(g_i18n:getText(i18n_tooltip))

        menuMultiOption:addElement(toolTip)
        menuOptionBox:addElement(menuMultiOption)
        menuOptionBox:addElement(setting)

        menuMultiOption:onGuiSetupFinished()
        setting:onGuiSetupFinished()
        toolTip:onGuiSetupFinished()

        menuMultiOption:setTexts(self.SETTINGS[id].strings)

        settingsPage.gameSettingsLayout:addElement(menuOptionBox)
        menuOptionBox:onGuiSetupFinished()

        menuMultiOption:setState(self.getStateIndex(id))

        self.CONTROLS[id] = menuMultiOption
    end

    ---Adds a binary bank setting control
    -- @param string id Setting identifier
    local function addBinaryMenuOption(id)
        local i18n_title   = "bank_setting_" .. id
        local i18n_tooltip = "bank_toolTip_" .. id

        local menuOptionBox = BitmapElement.new()
        menuOptionBox:loadProfile(g_gui:getProfile("fs25_multiTextOptionContainer"), true)

        local menuBinaryOption = BinaryOptionElement.new()
        menuBinaryOption:loadProfile(g_gui:getProfile("fs25_settingsBinaryOption"), true)
        menuBinaryOption.id     = id
        menuBinaryOption.target = BankSettingsControls
        menuBinaryOption:setCallback("onClickCallback", "onMenuOptionChanged")

        local setting = TextElement.new()
        setting:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOptionTitle"), true)
        setting:setText(g_i18n:getText(i18n_title))

        local toolTip = TextElement.new()
        toolTip.name = "ignore"
        toolTip:loadProfile(g_gui:getProfile("fs25_multiTextOptionTooltip"), true)
        toolTip:setText(g_i18n:getText(i18n_tooltip))

        menuBinaryOption:addElement(toolTip)
        menuOptionBox:addElement(menuBinaryOption)
        menuOptionBox:addElement(setting)

        menuBinaryOption:onGuiSetupFinished()
        setting:onGuiSetupFinished()
        toolTip:onGuiSetupFinished()

        settingsPage.gameSettingsLayout:addElement(menuOptionBox)
        menuOptionBox:onGuiSetupFinished()

        menuBinaryOption:setState(self.getStateIndex(id))

        self.CONTROLS[id] = menuBinaryOption
    end

    local sectionTitle = TextElement.new()
    sectionTitle.name = "sectionHeader"
    sectionTitle:loadProfile(g_gui:getProfile("fs25_settingsSectionHeader"), true)
    sectionTitle:setText(g_i18n:getText("bank_settings_section_title"))
    settingsPage.gameSettingsLayout:addElement(sectionTitle)
    sectionTitle:onGuiSetupFinished()

    for _, id in ipairs(self.menuItems) do
        if self.SETTINGS[id].type == 'binary' then
            addBinaryMenuOption(id)
        else
            addMultiMenuOption(id)
        end
    end

    settingsPage.gameSettingsLayout:invalidateLayout()
    settingsPage:updateAlternatingElements(settingsPage.gameSettingsLayout)
    settingsPage:updateGeneralSettings(settingsPage.gameSettingsLayout)
end

---Returns a flat table of default setting values
-- @return table settings
function BankSettings.load()
    local result = {}
    for id, def in pairs(BankSettings.SETTINGS) do
        result[id] = def.values[def.default]
    end
    return result
end
