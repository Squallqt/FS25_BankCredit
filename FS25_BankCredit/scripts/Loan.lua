-- Copyright © 2026 Squallqt. All rights reserved.
-- Data model for a single loan contract (principal, rate, schedule, status).
Loan = {}
local Loan_mt = Class(Loan)

Loan.TYPE = { ANNUITY = 1, BULLET = 2, REVOLVING = 3 }
Loan.RISK = { LOW = 1, MODERATE = 2, HIGH = 3, CRITICAL = 4, REFUSED = 5 }

---Create a new Loan instance
-- @param table? customMt Optional custom metatable
-- @return Loan instance
function Loan.new(customMt)
    local self = setmetatable({}, customMt or Loan_mt)

    self.id             = 0
    self.farmId         = 0
    self.type           = Loan.TYPE.ANNUITY
    self.amount         = 0
    self.restAmount     = 0
    self.interestRate   = 0
    self.riskLevel      = Loan.RISK.LOW
    self.duration       = 0
    self.restDuration   = 0
    self.dscr           = 0
    self.ltv            = 0
    self.paidOff        = false
    self.createdDay     = 0
    self.monthlyPayment = 0

    return self
end

---Serialize loan data to XML file
-- @param integer xmlFile XML file handle
-- @param string key XML key path
function Loan:writeToXML(xmlFile, key)
    setXMLInt(xmlFile,   key .. "#id",             self.id)
    setXMLInt(xmlFile,   key .. "#farmId",          self.farmId)
    setXMLInt(xmlFile,   key .. "#type",            self.type)
    setXMLFloat(xmlFile, key .. "#amount",          self.amount)
    setXMLFloat(xmlFile, key .. "#restAmount",      self.restAmount)
    setXMLFloat(xmlFile, key .. "#interestRate",    self.interestRate)
    setXMLInt(xmlFile,   key .. "#riskLevel",       self.riskLevel)
    setXMLInt(xmlFile,   key .. "#duration",        self.duration)
    setXMLInt(xmlFile,   key .. "#restDuration",    self.restDuration)
    setXMLFloat(xmlFile, key .. "#dscr",            self.dscr == math.huge and -1 or self.dscr)
    setXMLFloat(xmlFile, key .. "#ltv",             self.ltv  == math.huge and -1 or self.ltv)
    setXMLBool(xmlFile,  key .. "#paidOff",         self.paidOff)
    setXMLInt(xmlFile,   key .. "#createdDay",      self.createdDay)
    setXMLFloat(xmlFile, key .. "#monthlyPayment",  self.monthlyPayment)
end

---Deserialize loan from XML file
-- @param XMLFile xmlFile XML file handle
-- @param string key XML key path
function Loan:readFromXML(xmlFile, key)
    self.id             = getXMLInt(xmlFile,   key .. "#id")             or 0
    self.farmId         = getXMLInt(xmlFile,   key .. "#farmId")         or 0
    self.type           = getXMLInt(xmlFile,   key .. "#type")           or Loan.TYPE.ANNUITY
    self.amount         = getXMLFloat(xmlFile, key .. "#amount")         or 0
    self.restAmount     = getXMLFloat(xmlFile, key .. "#restAmount")     or 0
    self.interestRate   = getXMLFloat(xmlFile, key .. "#interestRate")   or 0
    self.riskLevel      = getXMLInt(xmlFile,   key .. "#riskLevel")      or Loan.RISK.LOW
    self.duration       = getXMLInt(xmlFile,   key .. "#duration")       or 0
    self.restDuration   = getXMLInt(xmlFile,   key .. "#restDuration")   or 0
    self.dscr           = getXMLFloat(xmlFile, key .. "#dscr")           or 0
    if self.dscr < 0 then self.dscr = math.huge end
    self.ltv            = getXMLFloat(xmlFile, key .. "#ltv")            or 0
    if self.ltv < 0 then self.ltv = math.huge end
    self.paidOff        = getXMLBool(xmlFile,  key .. "#paidOff")        or false
    self.createdDay     = getXMLInt(xmlFile,   key .. "#createdDay")     or 0
    self.monthlyPayment = getXMLFloat(xmlFile, key .. "#monthlyPayment") or 0

    if self.type < Loan.TYPE.ANNUITY or self.type > Loan.TYPE.REVOLVING then
        Logging.warning("[BankCredit] Invalid loan type %d for loan %d, defaulting to ANNUITY", self.type, self.id)
        self.type = Loan.TYPE.ANNUITY
    end

    if self.riskLevel < Loan.RISK.LOW or self.riskLevel > Loan.RISK.REFUSED then
        Logging.warning("[BankCredit] Invalid risk level %d for loan %d, defaulting to LOW", self.riskLevel, self.id)
        self.riskLevel = Loan.RISK.LOW
    end
end

---Serialize loan data to network stream
-- @param integer streamId Network stream identifier
function Loan:writeStream(streamId)
    streamWriteInt32(streamId,   self.id)
    streamWriteInt32(streamId,   self.farmId)
    streamWriteInt8(streamId,    self.type)
    streamWriteFloat32(streamId, self.amount)
    streamWriteFloat32(streamId, self.restAmount)
    streamWriteFloat32(streamId, self.interestRate)
    streamWriteInt8(streamId,    self.riskLevel)
    streamWriteInt16(streamId,   self.duration)
    streamWriteInt16(streamId,   self.restDuration)
    streamWriteFloat32(streamId, self.dscr == math.huge and -1 or self.dscr)
    streamWriteFloat32(streamId, self.ltv  == math.huge and -1 or self.ltv)
    streamWriteFloat32(streamId, self.monthlyPayment)
    streamWriteBool(streamId,    self.paidOff)
    streamWriteInt32(streamId,   self.createdDay)
end

---Deserialize loan data from network stream
-- @param integer streamId Network stream identifier
function Loan:readStream(streamId)
    self.id             = streamReadInt32(streamId)
    self.farmId         = streamReadInt32(streamId)
    self.type           = streamReadInt8(streamId)
    self.amount         = streamReadFloat32(streamId)
    self.restAmount     = streamReadFloat32(streamId)
    self.interestRate   = streamReadFloat32(streamId)
    self.riskLevel      = streamReadInt8(streamId)
    self.duration       = streamReadInt16(streamId)
    self.restDuration   = streamReadInt16(streamId)
    self.dscr           = streamReadFloat32(streamId)
    if self.dscr < 0 then self.dscr = math.huge end
    self.ltv            = streamReadFloat32(streamId)
    if self.ltv < 0 then self.ltv = math.huge end
    self.monthlyPayment = streamReadFloat32(streamId)
    self.paidOff        = streamReadBool(streamId)
    self.createdDay     = streamReadInt32(streamId)
end
