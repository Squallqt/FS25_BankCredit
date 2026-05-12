-- Copyright © 2026 Squallqt. All rights reserved.
-- Per-farm annual statistics: interest paid, principal repaid, loans opened/closed.
AnnualReport = {}
local AnnualReport_mt = Class(AnnualReport)

---Create a new AnnualReport instance
-- @return AnnualReport instance
function AnnualReport.new()
    local self = setmetatable({}, AnnualReport_mt)

    -- { [farmId] = { [year] = { interestPaid, principalPaid, loansOpened, loansClosed } } }
    self.data = {}

    return self
end

---Ensures a stats table exists for the given farm and year
-- @param integer farmId Farm identifier
-- @param integer year Game year
-- @return table stats The year stats table
function AnnualReport:getOrCreate(farmId, year)
    if self.data[farmId] == nil then
        self.data[farmId] = {}
    end
    if self.data[farmId][year] == nil then
        self.data[farmId][year] = {
            interestPaid  = 0,
            principalPaid = 0,
            loansOpened   = 0,
            loansClosed   = 0,
        }
    end
    return self.data[farmId][year]
end

---Records an interest payment for a farm in a given year
-- @param integer farmId Farm identifier
-- @param integer year Game year
-- @param number amount Interest amount paid
function AnnualReport:recordInterest(farmId, year, amount)
    local stats = self:getOrCreate(farmId, year)
    stats.interestPaid = stats.interestPaid + amount
end

---Records a principal repayment for a farm in a given year
-- @param integer farmId Farm identifier
-- @param integer year Game year
-- @param number amount Principal amount repaid
function AnnualReport:recordPrincipal(farmId, year, amount)
    local stats = self:getOrCreate(farmId, year)
    stats.principalPaid = stats.principalPaid + amount
end

---Records a loan opening for a farm in a given year
-- @param integer farmId Farm identifier
-- @param integer year Game year
function AnnualReport:recordLoanOpened(farmId, year)
    local stats = self:getOrCreate(farmId, year)
    stats.loansOpened = stats.loansOpened + 1
end

---Records a loan closure for a farm in a given year
-- @param integer farmId Farm identifier
-- @param integer year Game year
function AnnualReport:recordLoanClosed(farmId, year)
    local stats = self:getOrCreate(farmId, year)
    stats.loansClosed = stats.loansClosed + 1
end

---Returns the report for a specific farm and year, or nil
-- @param integer farmId Farm identifier
-- @param integer year Game year
-- @return table|nil stats
function AnnualReport:getReport(farmId, year)
    if self.data[farmId] == nil then return nil end
    return self.data[farmId][year]
end

---Returns a sorted list of years with data for a given farm
-- @param integer farmId Farm identifier
-- @return table list of year integers (ascending)
function AnnualReport:getYears(farmId)
    local years = {}
    if self.data[farmId] == nil then return years end
    for year, _ in pairs(self.data[farmId]) do
        table.insert(years, year)
    end
    table.sort(years)
    return years
end

---Serialize annual report data to XML
-- @param integer xmlFile XML file handle
-- @param string key XML key path
function AnnualReport:writeToXML(xmlFile, key)
    local n = 0
    for farmId, yearMap in pairs(self.data) do
        for year, stats in pairs(yearMap) do
            local entryKey = string.format("%s.entry(%d)", key, n)
            setXMLInt(xmlFile,   entryKey .. "#farmId",        farmId)
            setXMLInt(xmlFile,   entryKey .. "#year",          year)
            setXMLFloat(xmlFile, entryKey .. "#interestPaid",  stats.interestPaid)
            setXMLFloat(xmlFile, entryKey .. "#principalPaid", stats.principalPaid)
            setXMLInt(xmlFile,   entryKey .. "#loansOpened",   stats.loansOpened)
            setXMLInt(xmlFile,   entryKey .. "#loansClosed",   stats.loansClosed)
            n = n + 1
        end
    end
end

---Deserialize annual report data from XML
-- @param integer xmlFile XML file handle
-- @param string key XML key path
function AnnualReport:readFromXML(xmlFile, key)
    self.data = {}
    local i = 0
    while true do
        local entryKey = string.format("%s.entry(%d)", key, i)
        if not hasXMLProperty(xmlFile, entryKey) then break end

        local farmId        = getXMLInt(xmlFile,   entryKey .. "#farmId")        or 0
        local year          = getXMLInt(xmlFile,   entryKey .. "#year")          or 0
        local interestPaid  = getXMLFloat(xmlFile, entryKey .. "#interestPaid")  or 0
        local principalPaid = getXMLFloat(xmlFile, entryKey .. "#principalPaid") or 0
        local loansOpened   = getXMLInt(xmlFile,   entryKey .. "#loansOpened")   or 0
        local loansClosed   = getXMLInt(xmlFile,   entryKey .. "#loansClosed")   or 0

        if farmId > 0 and year > 0 then
            if self.data[farmId] == nil then
                self.data[farmId] = {}
            end
            self.data[farmId][year] = {
                interestPaid  = interestPaid,
                principalPaid = principalPaid,
                loansOpened   = loansOpened,
                loansClosed   = loansClosed,
            }
        end

        i = i + 1
    end
end
