-- Copyright © 2026 Squallqt. All rights reserved.
---Network event for synchronizing the annual report state to clients.
AnnualReportSyncEvent = {}
local AnnualReportSyncEvent_mt = Class(AnnualReportSyncEvent, Event)

InitEventClass(AnnualReportSyncEvent, "AnnualReportSyncEvent")

---Creates empty event instance
-- @return AnnualReportSyncEvent instance
function AnnualReportSyncEvent.emptyNew()
    return Event.new(AnnualReportSyncEvent_mt)
end

---Creates initialized event
-- @param table annualReport AnnualReport instance
-- @return AnnualReportSyncEvent instance
function AnnualReportSyncEvent.new(annualReport)
    local self = AnnualReportSyncEvent.emptyNew()
    self.annualReport = annualReport
    return self
end

---Reads annual report data from stream and applies it locally
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function AnnualReportSyncEvent:readStream(streamId, connection)
    if not connection:getIsServer() then return end

    local annualReport = AnnualReport.new()
    annualReport:readStream(streamId)

    local manager = BankCredit.manager
    if manager == nil or manager.annualReport == nil then return end

    manager.annualReport.data = annualReport.data
end

---Writes annual report data to stream
-- @param integer streamId Network stream identifier
-- @param Connection connection Network connection
function AnnualReportSyncEvent:writeStream(streamId, connection)
    local annualReport = self.annualReport or AnnualReport.new()
    annualReport:writeStream(streamId)
end
