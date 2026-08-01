-- Copyright © 2026 Squallqt. All rights reserved.
---Network event for broadcasting a loan repayment delta to all clients.
LoanPaymentEvent = {}
local LoanPaymentEvent_mt = Class(LoanPaymentEvent, Event)

InitEventClass(LoanPaymentEvent, "LoanPaymentEvent")

---Creates empty event instance
-- @return LoanPaymentEvent instance Empty event
function LoanPaymentEvent.emptyNew()
    local self = Event.new(LoanPaymentEvent_mt)
    return self
end

---Creates initialized loan payment event
-- @param integer loanId Loan identifier
-- @param float newRestAmount Updated remaining principal
-- @param integer newRestDuration Updated remaining months
-- @param boolean paidOff Whether the loan is now fully paid
-- @param float interestPortion Interest portion of the payment
-- @param float principalPortion Principal portion of the payment (always ≥ 0)
-- @param integer riskLevel Risk tier of the loan
-- @param float? drawAmount Revolving draw amount; values above zero identify a disbursement
-- @return LoanPaymentEvent instance The new event instance
function LoanPaymentEvent.new(loanId, newRestAmount, newRestDuration, paidOff, interestPortion, principalPortion, riskLevel, drawAmount)
    local self = LoanPaymentEvent.emptyNew()
    self.loanId           = loanId
    self.newRestAmount    = newRestAmount
    self.newRestDuration  = newRestDuration
    self.paidOff          = paidOff
    self.interestPortion  = interestPortion  or 0
    self.principalPortion = principalPortion or 0
    self.riskLevel        = riskLevel        or Loan.RISK.LOW
    self.drawAmount       = drawAmount       or 0
    return self
end

---Reads payment delta from network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function LoanPaymentEvent:readStream(streamId, connection)
    self.loanId           = streamReadInt32(streamId)
    self.newRestAmount    = streamReadFloat32(streamId)
    self.newRestDuration  = streamReadInt16(streamId)
    self.paidOff          = streamReadBool(streamId)
    self.interestPortion  = streamReadFloat32(streamId)
    self.principalPortion = streamReadFloat32(streamId)
    self.drawAmount       = streamReadFloat32(streamId)
    self.riskLevel        = streamReadInt8(streamId)
    self:run(connection)
end

---Writes payment delta to network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function LoanPaymentEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,   self.loanId)
    streamWriteFloat32(streamId, self.newRestAmount)
    streamWriteInt16(streamId,   self.newRestDuration)
    streamWriteBool(streamId,    self.paidOff)
    streamWriteFloat32(streamId, self.interestPortion)
    streamWriteFloat32(streamId, self.principalPortion)
    streamWriteFloat32(streamId, self.drawAmount)
    streamWriteInt8(streamId,    self.riskLevel)
end

---Applies payment delta to the local loan record and updates the bank ledger
-- @param Connection connection Network connection
function LoanPaymentEvent:run(connection)
    if not connection:getIsServer() then return end

    local manager = BankCredit.manager
    if manager == nil then return end

    local loan = manager.repository:getById(self.loanId)
    if loan == nil then
        Logging.warning("[BankCredit] LoanPaymentEvent: loan #%d not found", self.loanId)
        return
    end

    loan.restAmount   = self.newRestAmount
    loan.restDuration = self.newRestDuration
    loan.paidOff      = self.paidOff

    manager.bankService:onInterestReceived(self.interestPortion)
    if self.drawAmount > 0 then
        manager.bankService:onLoanDisbursed({ amount = self.drawAmount, riskLevel = self.riskLevel })
    else
        manager.bankService:onRepaymentReceived(self.principalPortion, self.riskLevel)
    end

    if BankCredit.frame ~= nil and BankCredit.frame.refreshList ~= nil then
        BankCredit.frame:refreshList()
    end
end
