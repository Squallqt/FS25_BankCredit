-- Copyright © 2026 Squallqt. All rights reserved.
---Network event for broadcasting a new loan creation to all clients.
LoanCreateEvent = {}
local LoanCreateEvent_mt = Class(LoanCreateEvent, Event)

InitEventClass(LoanCreateEvent, "LoanCreateEvent")

---Creates empty event instance
-- @return LoanCreateEvent instance Empty event
function LoanCreateEvent.emptyNew()
    local self = Event.new(LoanCreateEvent_mt)
    return self
end

---Creates initialized loan create event
-- @param table loan Loan instance
-- @return LoanCreateEvent instance The new event instance
function LoanCreateEvent.new(loan)
    local self = LoanCreateEvent.emptyNew()
    self.loan = loan
    return self
end

---Reads loan data from network stream and applies it to the repository
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function LoanCreateEvent:readStream(streamId, connection)
    if not connection:getIsServer() then return end

    self.loan = Loan.new()
    self.loan:readStream(streamId)

    local manager = BankCredit.manager
    if manager == nil then
        Logging.warning("[BankCredit] LoanCreateEvent: manager not available, loan #%d discarded", self.loan.id)
        return
    end

    -- Guard against late-join race: BankSyncEvent may have already applied this loan
    -- to the ledger as part of the snapshot. Re-running onLoanDisbursed would double-count.
    local alreadyPresent = manager.repository:getById(self.loan.id) ~= nil
    manager.repository:add(self.loan)
    if not alreadyPresent and self.loan.type ~= Loan.TYPE.REVOLVING then
        manager.bankService:onLoanDisbursed(self.loan)
    end

    if BankCredit.frame ~= nil and BankCredit.frame.refreshList ~= nil then
        BankCredit.frame:refreshList()
    end
end

---Writes loan data to network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function LoanCreateEvent:writeStream(streamId, connection)
    self.loan:writeStream(streamId)
end

---Executes loan create event (state already applied in readStream)
-- @param Connection connection Network connection
function LoanCreateEvent:run(connection)
end
