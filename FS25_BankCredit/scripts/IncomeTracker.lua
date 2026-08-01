-- Copyright © 2026 Squallqt. All rights reserved.
---Tracks farm income over a 12-period rolling window for DSCR calculations.
IncomeTracker = {}
local IncomeTracker_mt = Class(IncomeTracker)

---Create a new IncomeTracker instance
-- @return IncomeTracker instance
function IncomeTracker.new()
    local self = setmetatable({}, IncomeTracker_mt)

    self.history            = {}
    self.currentPeriodIndex = 0

    return self
end

---Register the Farm.changeBalance hook and subscribe to PERIOD_CHANGED.
-- Must be called after MoneyType.LOAN_PRINCIPAL and MoneyType.LOAN_INTEREST are registered.
-- The hook is applied at most once per session regardless of how many times
-- initialize() is called (prevents double-counting on save-A → save-B reload in same session).
function IncomeTracker:initialize()
    self.currentPeriodIndex = self:getCurrentPeriodIndex()

    -- Uses moneyType.statistic (string) for lookup — table identity is unreliable
    -- because the C++ engine may pass different table instances than MoneyType constants.
    -- Asset sales (vehicles, buildings, land) are excluded to avoid inflating DSCR.
    if IncomeTracker.TRACKED_STATS == nil then
        IncomeTracker.TRACKED_STATS = {
            ["harvestIncome"]  = true,  -- crop sales
            ["soldProducts"]   = true,  -- processed products (wool, flour…)
            ["soldWood"]       = true,  -- forestry
            ["soldAnimals"]    = true,  -- livestock sales
            ["soldMilk"]       = true,  -- dairy sales
            ["propertyIncome"] = true,  -- passive building income
            ["incomeBga"]      = true,  -- biogas plant income
            ["missionIncome"]  = true,  -- contract missions
            ["soldBales"]      = true,  -- bale sales
            -- FS25_Invoices interop
            ["invoiceIncome"]  = true,
            -- FS25_RedTape interop
            ["schemePayout"]   = true,
            ["grantReceived"]  = true,
        }
    end

    if not IncomeTracker._moneyPatched then
        IncomeTracker._moneyPatched = true

        -- Farm.changeBalance also receives C++ pathways such as selling stations,
        -- animal systems and the BGA.
        -- Signature: Farm:changeBalance(amount, moneyType)
        Farm.changeBalance = Utils.appendedFunction(
            Farm.changeBalance,
            function(farm, amount, moneyType)
                if BankCredit.manager ~= nil and farm ~= nil then
                    BankCredit.manager.incomeTracker:onMoneyChange(amount, farm.farmId, moneyType)
                end
            end
        )
    end

    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
end

---Handle a money change event. Records only recurring operating income; ignores
-- asset sales, loan flows, and other non-recurring items to avoid inflating DSCR.
-- @param float  amount    Money delta (positive = income)
-- @param integer farmId   Farm that received the money
-- @param table moneyType MoneyType instance
function IncomeTracker:onMoneyChange(amount, farmId, moneyType)
    if amount <= 0 then return end
    if farmId == nil or farmId <= 0 then return end
    local stat = moneyType and moneyType.statistic
    if stat == nil or not IncomeTracker.TRACKED_STATS[stat] then return end

    self:recordIncome(amount, farmId)
end

---Records an income amount for the current period.
-- On server, schedules debounced sync to connected clients.
-- @param float  amount  Income amount (positive)
-- @param integer farmId  Farm identifier
function IncomeTracker:recordIncome(amount, farmId)
    local periodIndex = self:getCurrentPeriodIndex()
    self.history[farmId] = self.history[farmId] or {}
    self.history[farmId][periodIndex] = (self.history[farmId][periodIndex] or 0) + amount

    if g_currentMission:getIsServer() then
        self:scheduleDebouncedSync()
    end
end

---Schedules a debounced BankPeriodSyncEvent broadcast (500ms after last income tick).
-- Ensures clients see updated income without waiting for the next PERIOD_CHANGED.
function IncomeTracker:scheduleDebouncedSync()
    if self._syncTimerActive then return end
    self._syncTimerActive = true

    local listener = {
        _tracker = self,
        _elapsed = 0,
        update = function(selfL, dt)
            selfL._elapsed = selfL._elapsed + dt
            if selfL._elapsed >= 500 then
                removeModEventListener(selfL)
                selfL._tracker._syncTimerActive = false
                if g_server ~= nil then
                    g_server:broadcastEvent(BankPeriodSyncEvent.new())
                end
            end
        end,
    }
    addModEventListener(listener)
end

---Returns the absolute period index for the current game time.
-- @return integer periodIndex
function IncomeTracker:getCurrentPeriodIndex()
    local env = g_currentMission.environment
    return (env.currentYear * 12) + env.currentPeriod
end

---Returns the decay-weighted average income over the N most recent periods.
-- Iterates backwards from the current period, using 0 for periods without income.
-- This ensures the average naturally decays when the farm stops earning.
-- @param integer farmId      Farm identifier
-- @param integer periodCount Number of periods to look back
-- @param float?  decay       Weight multiplier per older period; nil uses 0.8
-- @return float weightedAvg
function IncomeTracker:getWeightedAvg(farmId, periodCount, decay)
    decay = decay or 0.8
    local farmHistory = self.history[farmId]
    if farmHistory == nil then return 0 end

    local currentIdx = self:getCurrentPeriodIndex()
    local weightedSum = 0
    local weightSum   = 0
    local weight      = 1.0

    for i = 0, periodCount - 1 do
        local amount = farmHistory[currentIdx - i] or 0
        weightedSum = weightedSum + amount * weight
        weightSum   = weightSum   + weight
        weight      = weight * decay
    end

    if weightSum == 0 then return 0 end
    return weightedSum / weightSum
end

---Returns true if at least one income entry exists for the farm.
-- @param integer farmId Farm identifier
-- @return boolean
function IncomeTracker:hasHistory(farmId)
    local h = self.history[farmId]
    if h == nil then return false end
    for _ in pairs(h) do return true end
    return false
end

---Returns the income estimate used by CreditService.
-- Uses the 12-period decay-weighted average to accommodate seasonal selling patterns.
-- @param integer farmId Farm identifier
-- @return float safeAvg
function IncomeTracker:getSafeAvgIncome(farmId)
    return self:getWeightedAvg(farmId, 12, 0.8)
end

---Update the current period index and purge entries older than 12 periods.
-- Subscribed to MessageType.PERIOD_CHANGED. Server-only: clients receive
-- already-pruned history via BankPeriodSyncEvent.
function IncomeTracker:onPeriodChanged()
    if not g_currentMission:getIsServer() then return end

    self.currentPeriodIndex = self:getCurrentPeriodIndex()
    local cutoff = self.currentPeriodIndex - 11  -- keep current + 11 prior = 12 max

    for _, farmHistory in pairs(self.history) do
        for idx in pairs(farmHistory) do
            if idx < cutoff then
                farmHistory[idx] = nil
            end
        end
    end
end

---Persist income history to XML.
-- @param integer xmlFile XML file handle
-- @param string  key     XML key path prefix
function IncomeTracker:writeToXML(xmlFile, key)
    local farmN = 0
    for farmId, farmHistory in pairs(self.history) do
        local farmKey = string.format("%s.farm(%d)", key, farmN)
        setXMLInt(xmlFile, farmKey .. "#farmId", farmId)

        local periodN = 0
        for idx, amount in pairs(farmHistory) do
            local periodKey = string.format("%s.period(%d)", farmKey, periodN)
            setXMLInt(xmlFile,   periodKey .. "#index",  idx)
            setXMLFloat(xmlFile, periodKey .. "#amount", amount)
            periodN = periodN + 1
        end

        farmN = farmN + 1
    end
end

---Restore income history from XML.
-- @param integer xmlFile XML file handle
-- @param string  key     XML key path prefix
function IncomeTracker:readFromXML(xmlFile, key)
    self.history = {}

    local farmN = 0
    while true do
        local farmKey = string.format("%s.farm(%d)", key, farmN)
        if not hasXMLProperty(xmlFile, farmKey) then break end

        local farmId = getXMLInt(xmlFile, farmKey .. "#farmId") or 0
        if farmId > 0 then
            self.history[farmId] = {}

            local periodN = 0
            while true do
                local periodKey = string.format("%s.period(%d)", farmKey, periodN)
                if not hasXMLProperty(xmlFile, periodKey) then break end

                local idx    = getXMLInt(xmlFile,   periodKey .. "#index")  or 0
                local amount = getXMLFloat(xmlFile, periodKey .. "#amount") or 0
                self.history[farmId][idx] = amount

                periodN = periodN + 1
            end
        end

        farmN = farmN + 1
    end
end

---Serialize income history to network stream.
-- Format: farmCount(Int8) × [ farmId(Int16), periodCount(Int8) × [ periodIndex(Int32), amount(Float32) ] ]
-- @param integer streamId Network stream identifier
function IncomeTracker:writeStream(streamId)
    local farmIds = {}
    for farmId, farmHistory in pairs(self.history) do
        for _ in pairs(farmHistory) do
            table.insert(farmIds, farmId)
            break
        end
    end

    streamWriteInt8(streamId, #farmIds)
    for _, farmId in ipairs(farmIds) do
        local farmHistory = self.history[farmId]
        streamWriteInt16(streamId, farmId)

        local periods = {}
        for idx, amount in pairs(farmHistory) do
            table.insert(periods, { index = idx, amount = amount })
        end
        streamWriteInt8(streamId, #periods)
        for _, p in ipairs(periods) do
            streamWriteInt32(streamId,   p.index)
            streamWriteFloat32(streamId, p.amount)
        end
    end
end

---Deserialize income history from network stream.
-- @param integer streamId Network stream identifier
function IncomeTracker:readStream(streamId)
    self.history = {}
    local farmCount = streamReadInt8(streamId)
    for _ = 1, farmCount do
        local farmId     = streamReadInt16(streamId)
        local periodCount = streamReadInt8(streamId)
        self.history[farmId] = {}
        for _ = 1, periodCount do
            local idx    = streamReadInt32(streamId)
            local amount = streamReadFloat32(streamId)
            self.history[farmId][idx] = amount
        end
    end
end

---Release all state and unsubscribe from message center.
function IncomeTracker:cleanup()
    g_messageCenter:unsubscribeAll(self)
    self.history = {}
    self._syncTimerActive = false
end
