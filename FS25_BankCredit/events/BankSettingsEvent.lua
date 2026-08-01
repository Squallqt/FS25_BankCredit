-- Copyright © 2026 Squallqt. All rights reserved.
---Network event for synchronizing bank settings changes to all clients.
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
-- @param boolean? applyRateState Whether clients should apply the rate reset associated with these settings
-- @return BankSettingsEvent instance The new event instance
function BankSettingsEvent.new(settings, applyRateState)
    local self = BankSettingsEvent.emptyNew()
    self.settings = settings or {}
    self.applyRateState = applyRateState ~= false
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
    self.applyRateState                 = streamReadInt8(streamId) == 1
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
    streamWriteInt8   (streamId, self.applyRateState and 1 or 0)
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
        -- Global settings require master-user authority rather than farm-manager permission.
        local user = g_currentMission.userManager ~= nil
            and g_currentMission.userManager:getUserByConnection(connection)
            or nil
        if user == nil or not user:getIsMasterUser() then
            return
        end

        -- Network values remain untrusted until every field matches its whitelist.
        for _, id in ipairs(BankSettings.menuItems) do
            if not isValidSettingValue(id, src[id]) then
                return
            end
        end

        self.applyRateState = true
        g_server:broadcastEvent(self, nil, connection)
    end

    if g_currentMission == nil then return end
    g_currentMission.bankSettings = g_currentMission.bankSettings or {}
    local s = g_currentMission.bankSettings
    local prevBaseRate = s.baseInterestRate  -- capture before overwrite to detect actual change
    local prevDynamicRate = s.dynamicRate
    s.initialCapital        = src.initialCapital
    s.baseInterestRate      = src.baseInterestRate
    s.leverageRatio         = src.leverageRatio
    s.earlyRepaymentPenalty = src.earlyRepaymentPenalty
    s.dynamicRate           = src.dynamicRate

    -- Apply the capital delta to live equity so the change takes effect immediately on all peers
    if manager.bankService ~= nil and src.initialCapital ~= nil then
        manager.bankService:applyInitialCapitalDelta(src.initialCapital)
    end

    -- Client requests always apply rate changes; the flag only prevents an
    -- initial settings sync from overwriting the full rate state sent to a late joiner.
    local shouldApplyRateState = not connection:getIsServer() or self.applyRateState
    if shouldApplyRateState then
        BankSettings.applyRateConfiguration(prevBaseRate, prevDynamicRate, false)
    end

    if g_currentMission ~= nil and g_currentMission.bankFrame ~= nil then
        g_currentMission.bankFrame:refreshDashboard()
    end
end
