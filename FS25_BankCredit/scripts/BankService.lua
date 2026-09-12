-- Copyright © 2026 Squallqt. All rights reserved.
---Provides bank capacity, equity, provision, and portfolio operations.
BankService = {}
local BankService_mt = Class(BankService)

BankService.DEFAULT_LEVERAGE = 10
BankService.CONCENTRATION_CAP = 0.25

BankService.LOSS_RATES = {
    [1] = 0.005,  -- LOW      : 0.5%
    [2] = 0.015,  -- MODERATE : 1.5%
    [3] = 0.040,  -- HIGH     : 4.0%
    [4] = 0.100,  -- CRITICAL : 10.0%
}

---Creates a new BankService instance
-- @param table ledger BankLedger instance
-- @return BankService instance
function BankService.new(ledger)
    local self = setmetatable({}, BankService_mt)

    self.ledger = ledger

    return self
end

---Initializes the ledger for a new game or leaves it untouched for a loaded save
-- @param number initialCapital Starting equity for a new game
function BankService:initializeLedger(initialCapital)
    if self.ledger.equity == 0 then
        self.ledger.equity         = initialCapital
        self.ledger.initialCapital = initialCapital
    end
end

---Applies a capital recapitalization: adjusts live equity by the delta between the new and
-- the previously recorded initial capital. Safe to call at any time — the bank keeps operating.
-- @param number newCapital New initial capital value set by the admin
function BankService:applyInitialCapitalDelta(newCapital)
    local delta = newCapital - self.ledger.initialCapital
    self.ledger.equity         = math.max(0, self.ledger.equity + delta)
    self.ledger.initialCapital = newCapital
end

---Returns the configured leverage ratio
-- @return number leverageRatio
function BankService:getLeverageRatio()
    local s = g_currentMission ~= nil and g_currentMission.bankSettings or nil
    return (s ~= nil and s.leverageRatio) or BankService.DEFAULT_LEVERAGE
end

---Returns the maximum loan portfolio the bank can support
-- @return number totalCapacity
function BankService:getTotalCapacity()
    return self.ledger.equity * self:getLeverageRatio()
end

---Returns the expected loss provision across all risk tiers
-- @return number provision
function BankService:getLossProvision()
    local provision = 0
    for riskLevel, amount in pairs(self.ledger.portfolioByRisk) do
        local rate = BankService.LOSS_RATES[riskLevel]
        if rate ~= nil then
            provision = provision + amount * rate
        end
    end
    return provision
end

---Returns how much additional lending capacity is available right now
-- @return number availableCapacity
function BankService:getAvailableCapacity()
    return math.max(0, self:getTotalCapacity() - self.ledger.totalOutstanding - self:getLossProvision())
end

---Records interest income into bank equity
-- @param number amount Interest amount received
function BankService:onInterestReceived(amount)
    self.ledger.equity              = self.ledger.equity + amount
    self.ledger.totalInterestEarned = self.ledger.totalInterestEarned + amount
end

---Records a newly disbursed loan against the portfolio
-- @param table loan Loan instance with .amount and .riskLevel
function BankService:onLoanDisbursed(loan)
    self.ledger.totalOutstanding = self.ledger.totalOutstanding + loan.amount
    self.ledger.portfolioByRisk[loan.riskLevel] = (self.ledger.portfolioByRisk[loan.riskLevel] or 0) + loan.amount
end

---Records a principal repayment and reduces portfolio exposure
-- @param number principalAmount Principal amount being repaid
-- @param integer riskLevel Risk tier of the repaid loan
function BankService:onRepaymentReceived(principalAmount, riskLevel)
    self.ledger.totalOutstanding        = math.max(0, self.ledger.totalOutstanding - principalAmount)
    self.ledger.portfolioByRisk[riskLevel] = math.max(0, (self.ledger.portfolioByRisk[riskLevel] or 0) - principalAmount)
end

---Returns the ratio of equity to loss provision (solvency indicator)
-- @return number coverageRatio (math.huge when provision is zero)
function BankService:getCoverageRatio()
    local provision = self:getLossProvision()
    if provision <= 0 then
        return math.huge
    end
    return self.ledger.equity / provision
end

---Returns total outstanding exposure for a specific farm
-- @param number farmId Farm identifier
-- @param table repository BankRepository instance
-- @return number farmExposure
function BankService:getFarmExposure(farmId, repository)
    local total = 0
    for _, loan in pairs(repository:getByFarm(farmId)) do
        if not loan.paidOff then
            total = total + loan.restAmount
        end
    end
    return total
end

---Returns the maximum exposure allowed for any single farm (concentration cap)
-- @return number concentrationLimit
function BankService:getConcentrationLimit()
    return self:getTotalCapacity() * BankService.CONCENTRATION_CAP
end

---Returns portfolio composition by risk tier as percentages of totalOutstanding
-- @return table { low=%, moderate=%, high=%, critical=% }
function BankService:getPortfolioHealth()
    local total = self.ledger.totalOutstanding
    if total == 0 then
        return { low = 100, moderate = 0, high = 0, critical = 0 }
    end
    return {
        low      = self.ledger.portfolioByRisk[1] / total * 100,
        moderate = self.ledger.portfolioByRisk[2] / total * 100,
        high     = self.ledger.portfolioByRisk[3] / total * 100,
        critical = self.ledger.portfolioByRisk[4] / total * 100,
    }
end
