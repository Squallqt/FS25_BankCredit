-- Copyright © 2026 Squallqt. All rights reserved.
-- Broadcast from server to all clients at each PERIOD_CHANGED.
-- Syncs rateModel state and full income history so DSCR and the rate dashboard stay accurate.
BankPeriodSyncEvent = {}
local BankPeriodSyncEvent_mt = Class(BankPeriodSyncEvent, Event)

InitEventClass(BankPeriodSyncEvent, "BankPeriodSyncEvent")

---Creates empty event instance
-- @return BankPeriodSyncEvent instance
function BankPeriodSyncEvent.emptyNew()
    return Event.new(BankPeriodSyncEvent_mt)
end

---Creates initialized event for broadcast
-- @return BankPeriodSyncEvent instance
function BankPeriodSyncEvent.new()
    return BankPeriodSyncEvent.emptyNew()
end

---Reads rateModel + income history from stream and applies them to the local manager
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function BankPeriodSyncEvent:readStream(streamId, connection)
    local rateModel = InterestRateModel.new()
    rateModel:readStream(streamId)

    local incomeTracker = IncomeTracker.new()
    incomeTracker:readStream(streamId)

    local manager = BankCredit.manager
    if manager == nil then return end

    manager.rateModel.currentRate = rateModel.currentRate
    manager.rateModel.rateHistory = rateModel.rateHistory

    manager.incomeTracker.history = incomeTracker.history

    if g_currentMission ~= nil and g_currentMission.bankFrame ~= nil then
        g_currentMission.bankFrame:refreshDashboard()
    end
end

---Writes rateModel + income history to stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function BankPeriodSyncEvent:writeStream(streamId, connection)
    local manager = BankCredit.manager
    if manager == nil then
        InterestRateModel.new():writeStream(streamId)
        IncomeTracker.new():writeStream(streamId)
        return
    end

    manager.rateModel:writeStream(streamId)
    manager.incomeTracker:writeStream(streamId)
end
