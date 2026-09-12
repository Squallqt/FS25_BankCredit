-- Copyright © 2026 Squallqt. All rights reserved.
---Network event for notifying a client that its vanilla loan was cleared.
VanillaLoanClearedEvent = {}
local VanillaLoanClearedEvent_mt = Class(VanillaLoanClearedEvent, Event)

InitEventClass(VanillaLoanClearedEvent, "VanillaLoanClearedEvent")

---Creates an empty event instance for deserialization
-- @return VanillaLoanClearedEvent instance
function VanillaLoanClearedEvent.emptyNew()
    local self = Event.new(VanillaLoanClearedEvent_mt)
    return self
end

---Creates a new event carrying the farm id and cleared loan amount
-- @param integer farmId Farm identifier
-- @param number amount Cleared vanilla loan amount
-- @return VanillaLoanClearedEvent instance
function VanillaLoanClearedEvent.new(farmId, amount)
    local self = VanillaLoanClearedEvent.emptyNew()
    self.farmId = farmId or 0
    self.amount = amount or 0
    return self
end

---Reads event payload from the network stream and runs the handler
-- @param integer streamId Network stream id
-- @param Connection connection Sending connection
function VanillaLoanClearedEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.amount = streamReadFloat32(streamId)
    self:run(connection)
end

---Writes event payload to the network stream
-- @param integer streamId Network stream id
-- @param Connection connection Receiving connection
function VanillaLoanClearedEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.amount)
end

---Shows the vanilla-loan popup on the targeted client
-- @param Connection connection Sending connection (must be server)
function VanillaLoanClearedEvent:run(connection)
    if not connection:getIsServer() then
        return
    end

    BankCredit.showVanillaLoanPopup(self.amount)
end
