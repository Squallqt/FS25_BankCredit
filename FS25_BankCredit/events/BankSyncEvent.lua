-- Copyright © 2026 Squallqt. All rights reserved.
---Network event for full bank state synchronization on client late-join.
BankSyncEvent = {}
local BankSyncEvent_mt = Class(BankSyncEvent, Event)

InitEventClass(BankSyncEvent, "BankSyncEvent")

---Creates empty event instance
-- @return BankSyncEvent instance Empty event
function BankSyncEvent.emptyNew()
    local self = Event.new(BankSyncEvent_mt)
    return self
end

---Creates initialized sync event for late-join clients
-- @return BankSyncEvent instance The new event instance
function BankSyncEvent.new()
    local self = BankSyncEvent.emptyNew()
    return self
end

---Reads full bank state from network stream and reconstructs local state
-- Must read ALL stream data even if manager is nil (prevents stream corruption)
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function BankSyncEvent:readStream(streamId, connection)
    if not connection:getIsServer() then return end

    local ledger = BankLedger.new()
    ledger:readStream(streamId)

    local rateModel = InterestRateModel.new()
    rateModel:readStream(streamId)

    local count = streamReadInt16(streamId)
    local loans = {}
    for _ = 1, count do
        local loan = Loan.new()
        loan:readStream(streamId)
        table.insert(loans, loan)
    end

    local incomeTracker = IncomeTracker.new()
    incomeTracker:readStream(streamId)

    local annualReport = AnnualReport.new()
    annualReport:readStream(streamId)

    local manager = BankCredit.manager
    if manager == nil then
        Logging.warning("[BankCredit] BankSyncEvent: manager not available, %d loans discarded", count)
        return
    end

    -- Preserve the synchronized model instances referenced by dependent services.
    manager.ledger.equity              = ledger.equity
    manager.ledger.initialCapital      = ledger.initialCapital
    manager.ledger.totalInterestEarned = ledger.totalInterestEarned
    manager.ledger.totalOutstanding    = ledger.totalOutstanding
    manager.ledger.portfolioByRisk     = ledger.portfolioByRisk

    manager.rateModel:copyFrom(rateModel)

    manager.repository:clear()
    for _, loan in ipairs(loans) do
        manager.repository:add(loan)
    end

    manager.incomeTracker.history = incomeTracker.history
    manager.annualReport.data = annualReport.data
end

---Writes full bank state to network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function BankSyncEvent:writeStream(streamId, connection)
    local manager = BankCredit.manager
    if manager == nil then
        -- Write empty but valid payload to prevent stream desync on client
        BankLedger.new():writeStream(streamId)
        InterestRateModel.new():writeStream(streamId)
        streamWriteInt16(streamId, 0)
        IncomeTracker.new():writeStream(streamId)
        AnnualReport.new():writeStream(streamId)
        return
    end

    manager.ledger:writeStream(streamId)
    manager.rateModel:writeStream(streamId)

    local loans = {}
    for _, loan in pairs(manager.repository.loans) do
        table.insert(loans, loan)
    end

    streamWriteInt16(streamId, #loans)
    for _, loan in ipairs(loans) do
        loan:writeStream(streamId)
    end

    manager.incomeTracker:writeStream(streamId)
    manager.annualReport:writeStream(streamId)
end
