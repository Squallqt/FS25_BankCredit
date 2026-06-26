-- Copyright © 2026 Squallqt. All rights reserved.
-- Network event: client requests early repayment on a loan; server processes authoritatively.
LoanRepayEvent = {}
local LoanRepayEvent_mt = Class(LoanRepayEvent, Event)

InitEventClass(LoanRepayEvent, "LoanRepayEvent")

---Creates empty event instance
-- @return LoanRepayEvent instance Empty event
function LoanRepayEvent.emptyNew()
    local self = Event.new(LoanRepayEvent_mt)
    return self
end

---Creates an early repayment request event
-- @param integer loanId Loan identifier
-- @param number amount Principal amount to repay early
-- @return LoanRepayEvent instance The new event instance
function LoanRepayEvent.new(loanId, amount)
    local self = LoanRepayEvent.emptyNew()
    self.loanId = loanId or 0
    self.amount = amount or 0
    return self
end

---Reads repay data from network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function LoanRepayEvent:readStream(streamId, connection)
    self.loanId = streamReadInt32(streamId)
    self.amount = streamReadFloat32(streamId)
    self:run(connection)
end

---Writes repay data to network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function LoanRepayEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,   self.loanId)
    streamWriteFloat32(streamId, self.amount)
end

---Server-side handler: validates and processes early repayment
-- @param Connection connection Network connection
function LoanRepayEvent:run(connection)
    if g_server == nil then return end

    local manager = BankCredit.manager
    if manager == nil then
        Logging.warning("[BankCredit] LoanRepayEvent: manager unavailable")
        return
    end

    if not g_currentMission:getHasPlayerPermission("farmManager", connection) then
        return
    end

    local loan = manager.repository:getById(self.loanId)
    if loan == nil then
        return
    end

    -- Verify that the loan belongs to the requesting player's farm
    local player = g_currentMission.connectionsToPlayer[connection]
    if player == nil then return end
    local farmId = player.farmId
    if not LoanService.isValidFarmId(farmId) then return end
    if loan.farmId ~= farmId then
        return
    end

    if self.amount == nil or self.amount <= 0 then return end

    if loan.type == Loan.TYPE.REVOLVING then
        manager.loanService:repayRevolving(loan, self.amount)
    else
        manager.loanService:earlyRepayment(loan, self.amount)
    end

    -- broadcastEvent(false) does not loop back to the server player; refresh the host GUI explicitly
    if BankCredit.frame ~= nil and BankCredit.frame.refreshList ~= nil then
        BankCredit.frame:refreshList()
    end
end
