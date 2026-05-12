-- Copyright © 2026 Squallqt. All rights reserved.
-- CRUD + XML persistence for loans, ledger, settings, incomeTracker, and rateModel.
BankRepository = {}
local BankRepository_mt = Class(BankRepository)

BankRepository.SAVE_VERSION = 1
BankRepository.FILENAME     = "bankCredit.xml"

---Create a new BankRepository instance
-- @param table? customMt Optional custom metatable
-- @return BankRepository instance
function BankRepository.new(customMt)
    local self = setmetatable({}, customMt or BankRepository_mt)

    self.loans  = {}
    self.nextId = 1

    return self
end

---Clears all loans and resets the id sequence
function BankRepository:clear()
    self.loans  = {}
    self.nextId = 1
end

---Returns the next loan id and advances the sequence
-- @return integer id
function BankRepository:generateId()
    local id = self.nextId
    self.nextId = self.nextId + 1
    return id
end

---Returns the next loan id and advances the sequence (alias for generateId)
-- @return integer id
function BankRepository:getNextId()
    return self:generateId()
end

---Inserts a loan into the repository
-- @param table loan Loan instance (with id already set)
function BankRepository:add(loan)
    if loan == nil or loan.id == nil or loan.id <= 0 then
        Logging.warning("[BankCredit] BankRepository:add rejected loan with invalid id")
        return
    end
    self.loans[loan.id] = loan
    if loan.id >= self.nextId then
        self.nextId = loan.id + 1
    end
end

---Returns a loan by id (or nil)
-- @param integer id Loan identifier
-- @return table|nil loan
function BankRepository:getById(id)
    return self.loans[id]
end

---Returns all non-paid-off loans as a list
-- @return table list of loans
function BankRepository:getActive()
    local list = {}
    for _, loan in pairs(self.loans) do
        if not loan.paidOff then
            table.insert(list, loan)
        end
    end
    return list
end

---Returns all loans owned by a given farm as a list
-- @param integer farmId Farm identifier
-- @return table list of loans
function BankRepository:getByFarm(farmId)
    local list = {}
    for _, loan in pairs(self.loans) do
        if loan.farmId == farmId then
            table.insert(list, loan)
        end
    end
    return list
end

---Save all bank state to XML file
-- @param string savegamePath Path to savegame directory
-- @param table ledger BankLedger instance
-- @param table settings BankSettings instance
-- @param table incomeTracker IncomeTracker instance
-- @param table rateModel InterestRateModel instance
-- @param table? annualReport AnnualReport instance (optional)
function BankRepository:saveToXML(savegamePath, ledger, settings, incomeTracker, rateModel, annualReport)
    local filePath = savegamePath .. BankRepository.FILENAME
    local xmlFile  = createXMLFile("bankcredit", filePath, "bankcredit")

    if xmlFile == nil then
        Logging.error("[BankCredit] Failed to create save file: %s", filePath)
        return
    end

    setXMLInt(xmlFile, "bankcredit#version", BankRepository.SAVE_VERSION)
    setXMLInt(xmlFile, "bankcredit#nextId",  self.nextId)
    setXMLInt(xmlFile, "bankcredit#periodCounter", self.periodCounter or 0)

    ledger:writeToXML(xmlFile, "bankcredit.ledger")

    setXMLFloat  (xmlFile, "bankcredit.settings#initialCapital",        settings.initialCapital)
    setXMLFloat  (xmlFile, "bankcredit.settings#baseInterestRate",      settings.baseInterestRate)
    setXMLFloat  (xmlFile, "bankcredit.settings#leverageRatio",         settings.leverageRatio)
    setXMLFloat  (xmlFile, "bankcredit.settings#earlyRepaymentPenalty", settings.earlyRepaymentPenalty)
    setXMLInt    (xmlFile, "bankcredit.settings#dynamicRate",           settings.dynamicRate and 1 or 0)

    incomeTracker:writeToXML(xmlFile, "bankcredit.incomeTracker")
    rateModel:writeToXML(xmlFile, "bankcredit.rateModel")

    local n = 0
    for _, loan in pairs(self.loans) do
        local key = string.format("bankcredit.loan(%d)", n)
        loan:writeToXML(xmlFile, key)
        n = n + 1
    end

    if annualReport ~= nil then
        annualReport:writeToXML(xmlFile, "bankcredit.annualReport")
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

---Load all bank state from XML file
-- @param string savegamePath Path to savegame directory
-- @param table ledger BankLedger instance
-- @param table settings BankSettings instance
-- @param table incomeTracker IncomeTracker instance
-- @param table rateModel InterestRateModel instance
-- @param table? annualReport AnnualReport instance (optional)
function BankRepository:loadFromXML(savegamePath, ledger, settings, incomeTracker, rateModel, annualReport)
    local filePath = savegamePath .. BankRepository.FILENAME

    if not fileExists(filePath) then
        Logging.info("[BankCredit] No save file found, starting fresh")
        return
    end

    local xmlFile = loadXMLFile("bankcredit", filePath)
    if xmlFile == nil then
        Logging.warning("[BankCredit] Failed to load save file: %s", filePath)
        return
    end

    local version = getXMLInt(xmlFile, "bankcredit#version") or 1

    if version > BankRepository.SAVE_VERSION then
        Logging.warning("[BankCredit] Save file version %d is newer than supported %d", version, BankRepository.SAVE_VERSION)
    end

    self.nextId        = getXMLInt(xmlFile, "bankcredit#nextId")        or 1
    self.periodCounter = getXMLInt(xmlFile, "bankcredit#periodCounter") or 0

    ledger:readFromXML(xmlFile, "bankcredit.ledger")

    settings.initialCapital        = getXMLFloat(xmlFile, "bankcredit.settings#initialCapital")        or BankSettings.DEFAULTS.initialCapital
    settings.baseInterestRate      = getXMLFloat(xmlFile, "bankcredit.settings#baseInterestRate")      or BankSettings.DEFAULTS.baseInterestRate
    settings.leverageRatio         = getXMLFloat(xmlFile, "bankcredit.settings#leverageRatio")         or BankSettings.DEFAULTS.leverageRatio
    settings.earlyRepaymentPenalty = getXMLFloat(xmlFile, "bankcredit.settings#earlyRepaymentPenalty") or BankSettings.DEFAULTS.earlyRepaymentPenalty
    local dynRaw = getXMLInt(xmlFile, "bankcredit.settings#dynamicRate")
    settings.dynamicRate = dynRaw == nil and BankSettings.DEFAULTS.dynamicRate or (dynRaw == 1)

    incomeTracker:readFromXML(xmlFile, "bankcredit.incomeTracker")
    rateModel:readFromXML(xmlFile, "bankcredit.rateModel")

    if annualReport ~= nil then
        annualReport:readFromXML(xmlFile, "bankcredit.annualReport")
    end

    self.loans = {}
    local i = 0
    while true do
        local key = string.format("bankcredit.loan(%d)", i)
        if not hasXMLProperty(xmlFile, key) then break end

        local loan = Loan.new()
        loan:readFromXML(xmlFile, key)
        self.loans[loan.id] = loan
        if loan.id >= self.nextId then
            self.nextId = loan.id + 1
        end

        i = i + 1
    end

    Logging.info("[BankCredit] Loaded %d loans from %s (format v%d)", i, filePath, version)
    delete(xmlFile)
end

---Save settings to bankcredit XML file (creates or updates)
-- @param string savegamePath Path to savegame directory
-- @param table settings BankSettings instance
-- @return boolean success True if saved
function BankRepository:saveSettingsToXML(savegamePath, settings)
    local filePath = savegamePath .. BankRepository.FILENAME
    local xmlFile  = nil

    if fileExists(filePath) then
        xmlFile = loadXMLFile("bankcredit", filePath)
    else
        xmlFile = createXMLFile("bankcredit", filePath, "bankcredit")
    end

    if xmlFile == nil then
        Logging.warning("[BankCredit] Failed to save settings to %s", filePath)
        return false
    end

    if getXMLInt(xmlFile, "bankcredit#version") == nil then
        setXMLInt(xmlFile, "bankcredit#version", BankRepository.SAVE_VERSION)
    end
    if getXMLInt(xmlFile, "bankcredit#nextId") == nil then
        setXMLInt(xmlFile, "bankcredit#nextId", self.nextId or 1)
    end

    setXMLFloat(xmlFile, "bankcredit.settings#initialCapital",        settings.initialCapital)
    setXMLFloat(xmlFile, "bankcredit.settings#baseInterestRate",      settings.baseInterestRate)
    setXMLFloat(xmlFile, "bankcredit.settings#leverageRatio",         settings.leverageRatio)
    setXMLFloat(xmlFile, "bankcredit.settings#earlyRepaymentPenalty", settings.earlyRepaymentPenalty)
    setXMLInt  (xmlFile, "bankcredit.settings#dynamicRate",           settings.dynamicRate and 1 or 0)

    saveXMLFile(xmlFile)
    delete(xmlFile)
    return true
end

---Load settings from bankcredit XML file
-- @param string savegamePath Path to savegame directory
-- @return table|nil settings Loaded settings or nil if not found
function BankRepository:loadSettingsFromXML(savegamePath)
    local filePath = savegamePath .. BankRepository.FILENAME

    if not fileExists(filePath) then
        return nil
    end

    local xmlFile = loadXMLFile("bankcredit", filePath)
    if xmlFile == nil then
        Logging.warning("[BankCredit] Failed to load settings from %s", filePath)
        return nil
    end

    local hasAny = hasXMLProperty(xmlFile, "bankcredit.settings#initialCapital")
        or hasXMLProperty(xmlFile, "bankcredit.settings#baseInterestRate")
        or hasXMLProperty(xmlFile, "bankcredit.settings#leverageRatio")
        or hasXMLProperty(xmlFile, "bankcredit.settings#earlyRepaymentPenalty")

    if not hasAny then
        delete(xmlFile)
        return nil
    end

    local dynRaw = getXMLInt(xmlFile, "bankcredit.settings#dynamicRate")
    local settings = {
        initialCapital        = getXMLFloat(xmlFile, "bankcredit.settings#initialCapital")        or BankSettings.DEFAULTS.initialCapital,
        baseInterestRate      = getXMLFloat(xmlFile, "bankcredit.settings#baseInterestRate")      or BankSettings.DEFAULTS.baseInterestRate,
        leverageRatio         = getXMLFloat(xmlFile, "bankcredit.settings#leverageRatio")         or BankSettings.DEFAULTS.leverageRatio,
        earlyRepaymentPenalty = getXMLFloat(xmlFile, "bankcredit.settings#earlyRepaymentPenalty") or BankSettings.DEFAULTS.earlyRepaymentPenalty,
        dynamicRate           = dynRaw == nil and BankSettings.DEFAULTS.dynamicRate or (dynRaw == 1),
    }

    delete(xmlFile)
    return settings
end
