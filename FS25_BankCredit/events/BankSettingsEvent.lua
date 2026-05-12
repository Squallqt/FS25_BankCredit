-- Copyright © 2026 Squallqt. All rights reserved.
-- Network event for synchronizing bank settings changes to all clients.
BankSettingsEvent = {}
local BankSettingsEvent_mt = Class(BankSettingsEvent, Event)

InitEventClass(BankSettingsEvent, "BankSettingsEvent")

---Creates empty event instance
-- @return BankSettingsEvent instance Empty event
function BankSettingsEvent.emptyNew()
    local self = Event.new(BankSettingsEvent_mt)
    return self
end

---Creates initialized settings event
-- @param table settings BankSettings instance
-- @return BankSettingsEvent instance The new event instance
function BankSettingsEvent.new(settings)
    local self = BankSettingsEvent.emptyNew()
    self.settings = settings or {}
    return self
end

---Reads settings data from network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function BankSettingsEvent:readStream(streamId, connection)
    self.settings = {}
    self.settings.initialCapital        = streamReadFloat32(streamId)
    self.settings.baseInterestRate      = streamReadFloat32(streamId)
    self.settings.leverageRatio         = streamReadFloat32(streamId)
    self.settings.earlyRepaymentPenalty = streamReadFloat32(streamId)
    self.settings.dynamicRate           = streamReadInt8(streamId) == 1
    self:run(connection)
end

---Writes settings data to network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function BankSettingsEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.settings.initialCapital        or BankSettings.DEFAULTS.initialCapital)
    streamWriteFloat32(streamId, self.settings.baseInterestRate      or BankSettings.DEFAULTS.baseInterestRate)
    streamWriteFloat32(streamId, self.settings.leverageRatio         or BankSettings.DEFAULTS.leverageRatio)
    streamWriteFloat32(streamId, self.settings.earlyRepaymentPenalty or BankSettings.DEFAULTS.earlyRepaymentPenalty)
    streamWriteInt8   (streamId, (self.settings.dynamicRate ~= false) and 1 or 0)
end

---Returns true if the candidate value is in the whitelist for this setting id
-- @param string id Setting identifier
-- @param any candidate Value to validate
-- @return boolean ok
local function isValidSettingValue(id, candidate)
    local def = BankSettings.SETTINGS[id]
    if def == nil then return false end
    for _, v in ipairs(def.values) do
        if candidate == v then return true end
    end
    return false
end

---Executes settings event
-- @param Connection connection Network connection
function BankSettingsEvent:run(connection)
    if connection == nil then return end

    local manager = BankCredit.manager
    if manager == nil then return end

    local src = self.settings

    if not connection:getIsServer() then
        -- Client-initiated change: require masterUser (not farmManager — these are global settings)
        local user = g_currentMission.userManager ~= nil
            and g_currentMission.userManager:getUserByConnection(connection)
            or nil
        if user == nil or not user:getIsMasterUser() then
            Logging.warning("[BankSettingsEvent] Server rejected: player is not master user")
            return
        end

        -- Validate every field against the whitelist before trusting and rebroadcasting
        for _, id in ipairs(BankSettings.menuItems) do
            if not isValidSettingValue(id, src[id]) then
                Logging.warning("[BankSettingsEvent] Server rejected: invalid value for '%s'", id)
                return
            end
        end

        g_server:broadcastEvent(self, nil, connection)
    end

    if g_currentMission == nil then return end
    g_currentMission.bankSettings = g_currentMission.bankSettings or {}
    local s = g_currentMission.bankSettings
    local prevBaseRate = s.baseInterestRate  -- capture before overwrite to detect actual change
    s.initialCapital        = src.initialCapital
    s.baseInterestRate      = src.baseInterestRate
    s.leverageRatio         = src.leverageRatio
    s.earlyRepaymentPenalty = src.earlyRepaymentPenalty
    s.dynamicRate           = src.dynamicRate

    -- Apply the capital delta to live equity so the change takes effect immediately on all peers
    if manager.bankService ~= nil and src.initialCapital ~= nil then
        manager.bankService:applyInitialCapitalDelta(src.initialCapital)
    end

    -- Only snap currentRate if baseInterestRate itself changed.
    -- This avoids resetting a drifted dynamic rate when the admin changes an unrelated setting.
    if src.baseInterestRate ~= nil and src.baseInterestRate ~= prevBaseRate then
        local rm = manager.rateModel
        if rm ~= nil then
            local prev = rm.currentRate
            rm.currentRate = src.baseInterestRate
            if rm.currentRate ~= prev then
                local year = g_currentMission ~= nil and g_currentMission.environment ~= nil
                    and g_currentMission.environment.currentYear or 0
                table.insert(rm.rateHistory, { year = year, rate = rm.currentRate })
                while #rm.rateHistory > rm.HISTORY_MAX do
                    table.remove(rm.rateHistory, 1)
                end
            end
        end
    end

    if g_currentMission ~= nil and g_currentMission.bankFrame ~= nil then
        g_currentMission.bankFrame:refreshDashboard()
    end
end
