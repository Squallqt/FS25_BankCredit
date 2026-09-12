-- Copyright © 2026 Squallqt. All rights reserved.
---Network event for authoritative revolving credit draw and close requests.
RevolvingDrawEvent = {}
local RevolvingDrawEvent_mt = Class(RevolvingDrawEvent, Event)

InitEventClass(RevolvingDrawEvent, "RevolvingDrawEvent")

---Creates empty event instance
-- @return RevolvingDrawEvent instance Empty event
function RevolvingDrawEvent.emptyNew()
    local self = Event.new(RevolvingDrawEvent_mt)
    return self
end

---Creates a revolving draw request event
-- @param integer loanId Loan identifier
-- @param number amount Amount to draw (ignored when isClose is true)
-- @param boolean? isClose If true, request is a line-close instead of a draw (default false)
-- @return RevolvingDrawEvent instance The new event instance
function RevolvingDrawEvent.new(loanId, amount, isClose)
    local self = RevolvingDrawEvent.emptyNew()
    self.loanId  = loanId or 0
    self.amount  = amount or 0
    self.isClose = isClose == true
    return self
end

---Reads draw request from network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function RevolvingDrawEvent:readStream(streamId, connection)
    self.loanId  = streamReadInt32(streamId)
    self.amount  = streamReadFloat32(streamId)
    self.isClose = streamReadBool(streamId)
    self:run(connection)
end

---Writes draw request to network stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function RevolvingDrawEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId,   self.loanId)
    streamWriteFloat32(streamId, self.amount)
    streamWriteBool(streamId,    self.isClose)
end

---Server-side handler: validates ownership and executes draw
-- @param Connection connection Network connection
function RevolvingDrawEvent:run(connection)
    if g_server == nil then return end

    local manager = BankCredit.manager
    if manager == nil then
        Logging.warning("[BankCredit] RevolvingDrawEvent: manager unavailable")
        return
    end

    if not g_currentMission:getHasPlayerPermission("farmManager", connection) then
        return
    end

    local loan = manager.repository:getById(self.loanId)
    if loan == nil then
        return
    end

    -- Resolve farmId from connection — never trust the client-supplied value
    local player = g_currentMission.connectionsToPlayer[connection]
    if player == nil then return end
    local farmId = player.farmId
    if not LoanService.isValidFarmId(farmId) then return end
    if loan.farmId ~= farmId then
        return
    end

    if self.isClose then
        manager.loanService:closeRevolving(loan)
    elseif self.amount > 0 then
        manager.loanService:drawRevolving(loan, self.amount)
    end

    -- The server applies the request locally, so refresh its GUI after the change.
    if BankCredit.frame ~= nil and BankCredit.frame.refreshList ~= nil then
        BankCredit.frame:refreshList()
    end
end
