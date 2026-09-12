-- Copyright © 2026 Squallqt. All rights reserved.
---Network event for mirroring a cleared vanilla loan on every client.
VanillaLoanSyncEvent = {}
local VanillaLoanSyncEvent_mt = Class(VanillaLoanSyncEvent, Event)

InitEventClass(VanillaLoanSyncEvent, "VanillaLoanSyncEvent")

---Creates an empty event instance for deserialization
-- @return VanillaLoanSyncEvent instance
function VanillaLoanSyncEvent.emptyNew()
    local self = Event.new(VanillaLoanSyncEvent_mt)
    return self
end

---Creates a new event carrying the cleared farm id
-- @param integer farmId Farm identifier
-- @return VanillaLoanSyncEvent instance
function VanillaLoanSyncEvent.new(farmId)
    local self = VanillaLoanSyncEvent.emptyNew()
    self.farmId = farmId or 0
    return self
end

---Reads event payload from the network stream and runs the handler
-- @param integer streamId Network stream id
-- @param Connection connection Sending connection
function VanillaLoanSyncEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self:run(connection)
end

---Writes event payload to the network stream
-- @param integer streamId Network stream id
-- @param Connection connection Receiving connection
function VanillaLoanSyncEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
end

---Handles the event on the client: mirrors farm.loan = 0 locally.
-- @param Connection connection Sending connection (must be server)
function VanillaLoanSyncEvent:run(connection)
    if not connection:getIsServer() then
        return
    end

    if g_farmManager == nil then return end
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm ~= nil then
        farm.loan = 0
    end
end
