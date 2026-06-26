-- Copyright © 2026 Squallqt. All rights reserved.
-- Network event: client requests loan disbursement; server validates and disburses authoritatively.
LoanRequestEvent = {}
local LoanRequestEvent_mt = Class(LoanRequestEvent, Event)

InitEventClass(LoanRequestEvent, "LoanRequestEvent")

---Creates empty event instance
-- @return LoanRequestEvent instance Empty event
function LoanRequestEvent.emptyNew()
    local self = Event.new(LoanRequestEvent_mt)
    return self
end

---Creates a loan request event
-- @param integer farmId Farm identifier
-- @param integer loanType Loan.TYPE constant
-- @param number amount Requested principal
-- @param integer durationMonths Duration in months
-- @return LoanRequestEvent instance The new event instance
function LoanRequestEvent.new(farmId, loanType, amount, durationMonths)
    local self = LoanRequestEvent.emptyNew()
    self.farmId         = farmId or 0
    self.loanType       = loanType or Loan.TYPE.ANNUITY
    self.amount         = amount or 0
    self.durationMonths = durationMonths or 0
    return self
end

---Reads request data from network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function LoanRequestEvent:readStream(streamId, connection)
    self.farmId         = streamReadInt32(streamId)
    self.loanType       = streamReadInt8(streamId)
    self.amount         = streamReadFloat32(streamId)
    self.durationMonths = streamReadInt16(streamId)
    self:run(connection)
end

---Writes request data to network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function LoanRequestEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,   self.farmId)
    streamWriteInt8(streamId,    self.loanType)
    streamWriteFloat32(streamId, self.amount)
    streamWriteInt16(streamId,   self.durationMonths)
end

---Server-side handler: validates and disburses; client send is silently ignored
-- @param Connection connection Network connection
function LoanRequestEvent:run(connection)
    if g_server == nil then return end

    local manager = BankCredit.manager
    if manager == nil then
        Logging.warning("[BankCredit] LoanRequestEvent: manager unavailable")
        return
    end

    if not g_currentMission:getHasPlayerPermission("farmManager", connection) then
        return
    end

    -- Resolve farmId from connection — never trust the client-supplied value
    local player = g_currentMission.connectionsToPlayer[connection]
    if player == nil then return end
    local farmId = player.farmId
    if not LoanService.isValidFarmId(farmId) then
        return
    end

    manager.loanService:disburse(farmId, self.amount, self.loanType, self.durationMonths)
end
