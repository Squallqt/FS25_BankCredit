-- Copyright © 2026 Squallqt. All rights reserved.
-- Evaluates loan eligibility via DSCR and LTV risk metrics before credit approval.
CreditService = {}
local CreditService_mt = Class(CreditService)

CreditService.LIQUIDITY = {
    ["tractor"]   = 0.40,
    ["tool"]      = 0.50,
    ["building"]  = 0.55,
    ["livestock"] = 0.60,
    ["inventory"] = 0.50,
    ["farmland"]  = 0.70,
    ["cash"]      = 0.30,
    ["default"]   = 0.45,
}

CreditService.INCOME_PROJECTION_MONTHS = 24

---Creates new CreditService instance
-- @param table incomeTracker IncomeTracker instance
-- @return CreditService instance
function CreditService.new(incomeTracker)
    local self = setmetatable({}, CreditService_mt)

    self.incomeTracker = incomeTracker

    return self
end

---Returns the liquidity factor for a vehicle based on its store category
-- @param table vehicle Vehicle instance
-- @return number Liquidity factor (0.40–0.50, default 0.45)
function CreditService:getLiquidityFactor(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        return CreditService.LIQUIDITY["default"]
    end

    local cat = (storeItem.categoryName or ""):upper()

    if cat:find("TRACTOR") then
        return CreditService.LIQUIDITY["tractor"]
    end

    if cat:find("TOOL") or cat:find("CULTIVAT") or cat:find("PLOW") or cat:find("HARVEST")
    or cat:find("MOWER") or cat:find("BALER") or cat:find("HEADER") or cat:find("SPRAY")
    or cat:find("SPREAD") or cat:find("SOW") or cat:find("SEED") or cat:find("TEDDER")
    or cat:find("RAKE") or cat:find("TRAILER") or cat:find("LOADER") or cat:find("PICKUP") then
        return CreditService.LIQUIDITY["tool"]
    end

    return CreditService.LIQUIDITY["default"]
end

---Returns total liquidated asset value for a farm (vehicles + farmlands + buildings + livestock + inventory)
-- @param number farmId Farm identifier
-- @param table? repository BankRepository instance (optional; when provided, outstanding is deducted from cash)
-- @return number Liquidated asset total
function CreditService:getLiquidatedAssets(farmId, repository)
    local total = 0

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.ownerFarmId == farmId
        and vehicle.propertyState == VehiclePropertyState.OWNED
        and vehicle.getSellPrice ~= nil then
            local sellPrice = vehicle:getSellPrice()
            if sellPrice ~= nil then
                total = total + sellPrice * self:getLiquidityFactor(vehicle)
            end
        end
    end

    for _, farmland in pairs(g_farmlandManager:getFarmlands()) do
        if g_farmlandManager:getFarmlandOwner(farmland.id) == farmId then
            total = total + farmland.price * CreditService.LIQUIDITY["farmland"]
        end
    end

    if g_currentMission.placeableSystem ~= nil then
        for _, placeable in pairs(g_currentMission.placeableSystem.placeables) do
            if placeable.ownerFarmId == farmId
            and placeable.getSellPrice ~= nil then
                local sellPrice = placeable:getSellPrice()
                if sellPrice ~= nil and sellPrice > 0 then
                    total = total + sellPrice * CreditService.LIQUIDITY["building"]
                end
            end
        end
    end

    total = total + self:getLivestockValue(farmId)
    total = total + self:getInventoryValue(farmId)

    local cash = g_currentMission:getMoney(farmId)
    if cash ~= nil and cash > 0 then
        -- Deduct existing loan outstanding from cash so that disbursed loan proceeds
        -- do not artificially inflate the asset base for LTV and borrower-limit calculations
        if repository ~= nil then
            local outstanding = self:getCurrentOutstanding(farmId, repository)
            cash = math.max(0, cash - outstanding)
        end
        if cash > 0 then
            total = total + cash * CreditService.LIQUIDITY["cash"]
        end
    end

    return total
end

---Returns total livestock value for a farm (livestock collateral)
-- @param number farmId Farm identifier
-- @return number Livestock value after liquidity haircut
function CreditService:getLivestockValue(farmId)
    local total = 0
    if g_currentMission.placeableSystem == nil then return 0 end

    for _, placeable in pairs(g_currentMission.placeableSystem.placeables) do
        if placeable.spec_husbandryAnimals ~= nil
        and placeable:getOwnerFarmId() == farmId then
            local clusters = placeable:getClusters()
            if clusters ~= nil then
                for _, cluster in ipairs(clusters) do
                    local price = cluster:getSellPrice()
                    local count = cluster:getNumAnimals()
                    if price ~= nil and price > 0 and count ~= nil and count > 0 then
                        total = total + price * count
                    end
                end
            end
        end
    end

    return total * CreditService.LIQUIDITY["livestock"]
end

---Returns total stored goods value for a farm (commodity-backed collateral)
-- @param number farmId Farm identifier
-- @return number Inventory value after liquidity haircut
function CreditService:getInventoryValue(farmId)
    local total = 0
    if g_currentMission.placeableSystem == nil then return 0 end

    for _, placeable in pairs(g_currentMission.placeableSystem.placeables) do
        local storages = {}

        if placeable.spec_silo ~= nil then
            for _, storage in ipairs(placeable.spec_silo.storages) do
                table.insert(storages, storage)
            end
        end
        if placeable.spec_siloExtension ~= nil and placeable.spec_siloExtension.storage ~= nil then
            table.insert(storages, placeable.spec_siloExtension.storage)
        end

        for _, storage in ipairs(storages) do
            if storage:getOwnerFarmId() == farmId then
                for fillTypeIndex, fillLevel in pairs(storage:getFillLevels()) do
                    if fillLevel > 0 then
                        local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
                        if fillType ~= nil and fillType.pricePerLiter ~= nil and fillType.pricePerLiter > 0 then
                            total = total + fillLevel * fillType.pricePerLiter
                        end
                    end
                end
            end
        end
    end

    return total * CreditService.LIQUIDITY["inventory"]
end

---Returns the Loan-to-Value ratio for a requested amount against farm assets
-- @param number farmId Farm identifier
-- @param number requestedAmount Loan amount requested
-- @param table? repository BankRepository instance (optional; includes existing outstanding in numerator)
-- @return number LTV ratio (math.huge if no assets)
function CreditService:getLTV(farmId, requestedAmount, repository)
    local assets = self:getLiquidatedAssets(farmId, repository)
    if assets <= 0 then
        return math.huge
    end
    -- Include existing outstanding so the LTV reflects total leverage,
    -- not just the new request in isolation
    local outstanding = repository and self:getCurrentOutstanding(farmId, repository) or 0
    return (outstanding + requestedAmount) / assets
end

---Returns the Debt-Service Coverage Ratio for a monthly payment
-- @param number farmId Farm identifier
-- @param number monthlyPayment Monthly payment amount
-- @return number DSCR (math.huge if payment <= 0 or no income history, 0 if history exists but income is zero)
function CreditService:getDSCR(farmId, monthlyPayment)
    if monthlyPayment <= 0 then
        return math.huge
    end
    local income = self.incomeTracker:getSafeAvgIncome(farmId)
    if income <= 0 then
        if not self.incomeTracker:hasHistory(farmId) then
            return math.huge
        end
        return 0
    end
    return income / monthlyPayment
end

---Returns the total outstanding loan balance for a farm
-- @param number farmId Farm identifier
-- @param table repository BankRepository instance
-- @return number Outstanding balance
function CreditService:getCurrentOutstanding(farmId, repository)
    local total = 0
    for _, loan in pairs(repository:getByFarm(farmId)) do
        if not loan.paidOff then
            total = total + loan.restAmount
        end
    end
    return total
end

---Returns the maximum amount a farm can borrow (assets + income projection - outstanding)
-- @param number farmId Farm identifier
-- @param table repository BankRepository instance
-- @return number Borrower limit
function CreditService:getBorrowerLimit(farmId, repository)
    local assets      = self:getLiquidatedAssets(farmId, repository)
    local income      = self.incomeTracker:getSafeAvgIncome(farmId)
    local outstanding = self:getCurrentOutstanding(farmId, repository)
    return math.max(0, assets + income * CreditService.INCOME_PROJECTION_MONTHS - outstanding)
end

---Scores risk level from DSCR and LTV inputs
-- @param number dscr Debt-service coverage ratio
-- @param number ltv Loan-to-value ratio
-- @return table { level, amountCapRatio }
function CreditService:scoreRisk(dscr, ltv)
    if dscr >= 1.50 and ltv <= 0.60 then
        return { level = Loan.RISK.LOW,      amountCapRatio = 1.00 }
    end
    if dscr >= 1.25 and ltv <= 0.75 then
        return { level = Loan.RISK.MODERATE, amountCapRatio = 1.00 }
    end
    if dscr >= 1.00 and ltv <= 0.90 then
        return { level = Loan.RISK.HIGH,     amountCapRatio = 1.00 }
    end
    if dscr >= 0.80 and ltv <= 0.95 then
        return { level = Loan.RISK.CRITICAL, amountCapRatio = 0.50 }
    end
    return { level = Loan.RISK.REFUSED,      amountCapRatio = 0.00 }
end

---Evaluates a loan application and returns risk scoring with effective terms
-- @param number farmId Farm identifier
-- @param number requestedAmount Loan amount requested
-- @param number monthlyPayment Estimated monthly payment
-- @param table rateModel InterestRateModel instance
-- @param table repository BankRepository instance
-- @param integer loanType Loan.TYPE constant
-- @return table { risk, effectiveAmount, effectiveRate, typeSpread, dscr, ltv }
function CreditService:evaluateLoan(farmId, requestedAmount, monthlyPayment, rateModel, repository, loanType)
    local ltv  = self:getLTV(farmId, requestedAmount, repository)
    local dscr = self:getDSCR(farmId, monthlyPayment)
    local risk = self:scoreRisk(dscr, ltv)

    local effectiveAmount = requestedAmount * risk.amountCapRatio
    local typeSpread      = rateModel:getTypeSpread(loanType or 1)
    local effectiveRate   = rateModel:getRateForRiskAndType(risk.level, loanType or 1)

    return {
        risk            = risk,
        effectiveAmount = effectiveAmount,
        effectiveRate   = effectiveRate,
        typeSpread      = typeSpread,
        dscr            = dscr,
        ltv             = ltv,
    }
end

---Returns the effective loan limit considering borrower capacity, bank availability, and concentration cap
-- @param number farmId Farm identifier
-- @param number bankAvailableCapacity Bank's current available lending capacity
-- @param table repository BankRepository instance
-- @param table bankService BankService instance (optional, enables concentration cap)
-- @return number Effective limit
function CreditService:getEffectiveLimit(farmId, bankAvailableCapacity, repository, bankService)
    local borrowerLimit = self:getBorrowerLimit(farmId, repository)
    local limit = math.min(borrowerLimit, bankAvailableCapacity)

    if bankService ~= nil then
        local concentrationLimit = bankService:getConcentrationLimit()
        local farmExposure       = bankService:getFarmExposure(farmId, repository)
        local concentrationRoom  = math.max(0, concentrationLimit - farmExposure)
        limit = math.min(limit, concentrationRoom)
    end

    return limit
end
