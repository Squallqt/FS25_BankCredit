-- Copyright © 2026 Squallqt. All rights reserved.
-- Tracks the bank's internal balance sheet: reserves, equity, and outstanding credit.
BankLedger = {}
local BankLedger_mt = Class(BankLedger)

---Create a new BankLedger instance
-- @param table? customMt Optional custom metatable
-- @return BankLedger instance
function BankLedger.new(customMt)
    local self = setmetatable({}, customMt or BankLedger_mt)

    self.equity              = 0
    self.initialCapital      = 0
    self.totalInterestEarned = 0
    self.portfolioByRisk     = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    self.totalOutstanding    = 0

    return self
end

---Serialize ledger data to XML file
-- @param integer xmlFile XML file handle
-- @param string key XML key path
function BankLedger:writeToXML(xmlFile, key)
    setXMLFloat(xmlFile, key .. "#equity",              self.equity)
    setXMLFloat(xmlFile, key .. "#initialCapital",      self.initialCapital)
    setXMLFloat(xmlFile, key .. "#totalInterestEarned", self.totalInterestEarned)
    setXMLFloat(xmlFile, key .. "#totalOutstanding",    self.totalOutstanding)
    setXMLFloat(xmlFile, key .. "#portfolioLow",        self.portfolioByRisk[1])
    setXMLFloat(xmlFile, key .. "#portfolioModerate",   self.portfolioByRisk[2])
    setXMLFloat(xmlFile, key .. "#portfolioHigh",       self.portfolioByRisk[3])
    setXMLFloat(xmlFile, key .. "#portfolioCritical",   self.portfolioByRisk[4])
end

---Deserialize ledger from XML file
-- @param XMLFile xmlFile XML file handle
-- @param string key XML key path
function BankLedger:readFromXML(xmlFile, key)
    self.equity              = getXMLFloat(xmlFile, key .. "#equity")              or 0
    self.initialCapital      = getXMLFloat(xmlFile, key .. "#initialCapital")      or 0
    self.totalInterestEarned = getXMLFloat(xmlFile, key .. "#totalInterestEarned") or 0
    self.totalOutstanding    = getXMLFloat(xmlFile, key .. "#totalOutstanding")    or 0
    self.portfolioByRisk = {
        [1] = getXMLFloat(xmlFile, key .. "#portfolioLow")      or 0,
        [2] = getXMLFloat(xmlFile, key .. "#portfolioModerate") or 0,
        [3] = getXMLFloat(xmlFile, key .. "#portfolioHigh")     or 0,
        [4] = getXMLFloat(xmlFile, key .. "#portfolioCritical") or 0,
    }
end

---Serialize ledger data to network stream
-- @param integer streamId Network stream identifier
function BankLedger:writeStream(streamId)
    streamWriteFloat32(streamId, self.equity)
    streamWriteFloat32(streamId, self.initialCapital)
    streamWriteFloat32(streamId, self.totalInterestEarned)
    streamWriteFloat32(streamId, self.totalOutstanding)
    streamWriteFloat32(streamId, self.portfolioByRisk[1])
    streamWriteFloat32(streamId, self.portfolioByRisk[2])
    streamWriteFloat32(streamId, self.portfolioByRisk[3])
    streamWriteFloat32(streamId, self.portfolioByRisk[4])
end

---Deserialize ledger data from network stream
-- @param integer streamId Network stream identifier
function BankLedger:readStream(streamId)
    self.equity              = streamReadFloat32(streamId)
    self.initialCapital      = streamReadFloat32(streamId)
    self.totalInterestEarned = streamReadFloat32(streamId)
    self.totalOutstanding    = streamReadFloat32(streamId)
    self.portfolioByRisk = {
        [1] = streamReadFloat32(streamId),
        [2] = streamReadFloat32(streamId),
        [3] = streamReadFloat32(streamId),
        [4] = streamReadFloat32(streamId),
    }
end
