-- Copyright © 2026 Squallqt. All rights reserved.
-- Orchestrates loan creation, repayment processing, and default handling.
LoanService = {}
local LoanService_mt = Class(LoanService)

-- Annual commitment fee rate on the undrawn portion of a revolving credit line (1%/year)
LoanService.COMMITMENT_FEE_RATE = 0.01

---Validates a farmId for loan operations.
-- Rejects nil, non-positive, and spectator farms so no loan is ever disbursed,
-- collected, or mutated against a farm that does not exist. Prevents orphan
-- loans at new-game startup when the player has not yet been assigned a farm.
-- @param integer|nil farmId Farm identifier to validate
-- @return boolean valid True if farmId is a real farm
function LoanService.isValidFarmId(farmId)
    if farmId == nil then return false end
    if farmId <= 0 then return false end
    if farmId == FarmManager.SPECTATOR_FARM_ID then return false end
    return true
end

---Creates new LoanService instance
-- @param table bankService BankService instance
-- @param table creditService CreditService instance
-- @param table repository BankRepository instance
-- @param table rateModel InterestRateModel instance
-- @param table? annualReport AnnualReport instance (optional)
-- @return LoanService instance
function LoanService.new(bankService, creditService, repository, rateModel, annualReport)
    local self = setmetatable({}, LoanService_mt)

    self.bankService   = bankService
    self.creditService = creditService
    self.repository    = repository
    self.rateModel     = rateModel
    self.annualReport  = annualReport

    return self
end

---Computes the standard annuity payment for a fixed-rate loan
-- @param number amount Principal amount
-- @param number annualRate Annual rate in percent
-- @param number durationMonths Duration in months
-- @return number Monthly payment (float, never truncated)
function LoanService:calculateAnnuityPayment(amount, annualRate, durationMonths)
    local r = annualRate / 100 / 12
    if r == 0 then
        return amount / durationMonths
    end
    return amount * r * (1 + r)^durationMonths / ((1 + r)^durationMonths - 1)
end

---Computes the interest-only monthly payment for a bullet loan
-- @param number amount Principal amount
-- @param number annualRate Annual rate in percent
-- @return number Monthly interest payment
function LoanService:calculateBulletPayment(amount, annualRate)
    return amount * (annualRate / 100) / 12
end

---Returns the monthly payment for a loan based on its type
-- @param number amount Principal amount
-- @param number annualRate Annual rate in percent
-- @param number durationMonths Duration in months
-- @param integer loanType Loan.TYPE constant
-- @return number Monthly payment
function LoanService:getMonthlyPayment(amount, annualRate, durationMonths, loanType)
    if loanType == Loan.TYPE.ANNUITY then
        return self:calculateAnnuityPayment(amount, annualRate, durationMonths)
    end
    if loanType == Loan.TYPE.BULLET then
        return self:calculateBulletPayment(amount, annualRate)
    end
    -- REVOLVING: no fixed instalment — return interest on full limit for DSCR worst-case
    return amount * (annualRate / 100) / 12
end

---Checks whether a loan can be disbursed to a farm
-- @param number farmId Farm identifier
-- @param number requestedAmount Loan amount requested
-- @param integer loanType Loan.TYPE constant
-- @param number durationMonths Duration in months
-- @return table { ok=bool, reason=string|nil, evaluation=table|nil }
function LoanService:canDisburse(farmId, requestedAmount, loanType, durationMonths)
    if not LoanService.isValidFarmId(farmId) then
        return { ok = false, reason = "invalid_farm" }
    end
    if requestedAmount == nil or requestedAmount <= 0 then
        return { ok = false, reason = "invalid_amount" }
    end

    local availableCapacity = self.bankService:getAvailableCapacity()
    local effectiveLimit    = self.creditService:getEffectiveLimit(farmId, availableCapacity, self.repository, self.bankService)

    if requestedAmount > effectiveLimit then
        return { ok = false, reason = "limit_exceeded" }
    end

    local concentrationLimit = self.bankService:getConcentrationLimit()
    local farmExposure       = self.bankService:getFarmExposure(farmId, self.repository)
    if farmExposure + requestedAmount > concentrationLimit then
        return { ok = false, reason = "concentration_exceeded" }
    end

    local monthlyPayment = self:getMonthlyPayment(requestedAmount, self.rateModel:getRate(), durationMonths, loanType)
    local evaluation     = self.creditService:evaluateLoan(farmId, requestedAmount, monthlyPayment, self.rateModel, self.repository, loanType)

    if evaluation.risk.level == Loan.RISK.REFUSED then
        return { ok = false, reason = "risk_refused", evaluation = evaluation }
    end

    -- Re-evaluate with effective rate: the surcharge increases the monthly payment,
    -- which lowers the DSCR, which may push the risk level higher.
    -- Only run if pass1 did NOT cap the amount: if it already capped, re-evaluating
    -- the smaller amount would artificially improve the score.
    -- Also: only keep the pass2 result if it is WORSE or equal — pass2 must never
    -- downgrade the risk level (e.g. DSCR=N/A with higher rate still resolves as LOW).
    if evaluation.effectiveRate ~= self.rateModel:getRate() and evaluation.risk.amountCapRatio == 1.0 then
        local pass1Level = evaluation.risk.level
        local effectivePayment = self:getMonthlyPayment(evaluation.effectiveAmount, evaluation.effectiveRate, durationMonths, loanType)
        local pass2 = self.creditService:evaluateLoan(farmId, evaluation.effectiveAmount, effectivePayment, self.rateModel, self.repository, loanType)
        if pass2.risk.level >= pass1Level then
            evaluation = pass2
        end
    end

    if evaluation.risk.level == Loan.RISK.REFUSED then
        return { ok = false, reason = "risk_refused", evaluation = evaluation }
    end

    return { ok = true, evaluation = evaluation }
end

---Disburses a loan to a farm. Server-authoritative.
-- @param number farmId Farm identifier
-- @param number requestedAmount Loan amount requested
-- @param integer loanType Loan.TYPE constant
-- @param number durationMonths Duration in months
-- @return Loan|nil Disbursed loan or nil if refused
function LoanService:disburse(farmId, requestedAmount, loanType, durationMonths)
    if not LoanService.isValidFarmId(farmId) then
        return nil
    end

    local check = self:canDisburse(farmId, requestedAmount, loanType, durationMonths)
    if not check.ok then
        return nil
    end

    local evaluation    = check.evaluation
    local effectiveAmt  = evaluation.effectiveAmount
    local effectiveRate = evaluation.effectiveRate

    local isRevolving = (loanType == Loan.TYPE.REVOLVING)

    local loan = Loan.new()
    loan.id             = self.repository:getNextId()
    loan.farmId         = farmId
    loan.type           = loanType
    loan.amount         = effectiveAmt
    loan.restAmount     = isRevolving and 0 or effectiveAmt
    loan.interestRate   = effectiveRate
    loan.riskLevel      = evaluation.risk.level
    loan.duration       = isRevolving and 0 or durationMonths
    loan.restDuration   = isRevolving and 0 or durationMonths
    loan.dscr           = evaluation.dscr
    loan.ltv            = evaluation.ltv
    loan.paidOff        = false
    loan.createdDay     = (g_currentMission.environment and g_currentMission.environment.currentDay) or 0
    loan.monthlyPayment = isRevolving and 0 or self:getMonthlyPayment(effectiveAmt, effectiveRate, durationMonths, loanType)

    if not isRevolving then
        g_currentMission:addMoney(effectiveAmt, farmId, MoneyType.LOAN_PRINCIPAL, true, true)
        self.bankService:onLoanDisbursed(loan)
    end

    self.repository:add(loan)

    -- Annual report: record loan opened
    if self.annualReport ~= nil then
        local currentYear = g_currentMission.environment.currentYear
        self.annualReport:recordLoanOpened(farmId, currentYear)
    end

    if g_server ~= nil then
        g_server:broadcastEvent(LoanCreateEvent.new(loan), false)
        if self.annualReport ~= nil then
            g_server:broadcastEvent(AnnualReportSyncEvent.new(self.annualReport), false)
        end
    end

    return loan
end

---Processes one monthly payment collection for a loan. Server-authoritative.
-- @param table loan Loan instance
function LoanService:collectMonthlyPayment(loan)
    if not g_currentMission:getIsServer() then return end
    if loan.paidOff then return end
    if not LoanService.isValidFarmId(loan.farmId) then
        Logging.warning("[BankCredit] collectMonthlyPayment: skipping loan #%d with invalid farmId=%s",
            loan.id or -1, tostring(loan.farmId))
        return
    end

    -- REVOLVING: interest-only on drawn balance + commitment fee on undrawn portion
    if loan.type == Loan.TYPE.REVOLVING then
        local interestPortion = 0
        local commitmentFee   = 0

        if loan.restAmount > 0 then
            interestPortion = loan.restAmount * (loan.interestRate / 100) / 12
        end

        local undrawn = loan.amount - loan.restAmount
        if undrawn > 0 then
            commitmentFee = undrawn * LoanService.COMMITMENT_FEE_RATE / 12
        end

        local totalCharge = interestPortion + commitmentFee
        if totalCharge <= 0 then return end

        if g_server ~= nil then
            g_server:broadcastEvent(LoanPaymentEvent.new(loan.id, loan.restAmount, 0, false, totalCharge, 0, loan.riskLevel), false)
        end

        if interestPortion > 0 then
            g_currentMission:addMoney(-interestPortion, loan.farmId, MoneyType.LOAN_INTEREST, true, true)
            self.bankService:onInterestReceived(interestPortion)
        end
        if commitmentFee > 0 then
            g_currentMission:addMoney(-commitmentFee, loan.farmId, MoneyType.LOAN_INTEREST, true, true)
            self.bankService:onInterestReceived(commitmentFee)
        end

        -- Annual report: record revolving interest (drawn interest + commitment fee)
        if self.annualReport ~= nil then
            local currentYear = g_currentMission.environment.currentYear
            self.annualReport:recordInterest(loan.farmId, currentYear, totalCharge)
            if g_server ~= nil then
                g_server:broadcastEvent(AnnualReportSyncEvent.new(self.annualReport), false)
            end
        end

        return
    end

    local interestPortion  = loan.restAmount * (loan.interestRate / 100) / 12
    local totalPayment     = loan.monthlyPayment
    local principalPortion = totalPayment - interestPortion

    -- Bullet loan at final period: collect full principal (interest-only payments carry no principal)
    if loan.type == Loan.TYPE.BULLET and loan.restDuration == 1 then
        principalPortion = loan.restAmount
        totalPayment     = principalPortion + interestPortion
    end

    -- Final payment: clamp principal to remaining balance to avoid overshoot
    if Loan.isPayoffAmount(loan.restAmount, principalPortion) then
        principalPortion  = loan.restAmount
        totalPayment      = principalPortion + interestPortion
        loan.paidOff      = true
        loan.restDuration = 0
        loan.restAmount   = 0
    else
        loan.restAmount   = math.floor((loan.restAmount - principalPortion) * 100 + 0.5) / 100
        loan.restDuration = loan.restDuration - 1
        if loan.restDuration <= 0 then
            loan.paidOff = true
        end
    end

    if g_server ~= nil then
        g_server:broadcastEvent(LoanPaymentEvent.new(loan.id, loan.restAmount, loan.restDuration, loan.paidOff, interestPortion, principalPortion, loan.riskLevel), false)
    end

    g_currentMission:addMoney(-interestPortion,  loan.farmId, MoneyType.LOAN_INTEREST,  true, true)
    if principalPortion > 0 then
        g_currentMission:addMoney(-principalPortion, loan.farmId, MoneyType.LOAN_PRINCIPAL, true, true)
    end

    self.bankService:onInterestReceived(interestPortion)
    self.bankService:onRepaymentReceived(principalPortion, loan.riskLevel)

    -- Annual report: record interest, principal, and loan closure
    if self.annualReport ~= nil then
        local currentYear = g_currentMission.environment.currentYear
        self.annualReport:recordInterest(loan.farmId, currentYear, interestPortion)
        self.annualReport:recordPrincipal(loan.farmId, currentYear, principalPortion)
        if loan.paidOff then
            self.annualReport:recordLoanClosed(loan.farmId, currentYear)
        end
        if g_server ~= nil then
            g_server:broadcastEvent(AnnualReportSyncEvent.new(self.annualReport), false)
        end
    end
end

---Collects monthly payments on every active loan. Server-only. Called on PERIOD_CHANGED.
function LoanService:collectAll()
    if not g_currentMission:getIsServer() then return end

    for _, loan in pairs(self.repository:getActive()) do
        self:collectMonthlyPayment(loan)
    end
end

---Processes an early repayment on a loan. Server-authoritative.
-- @param table loan Loan instance
-- @param number amount Principal amount being repaid early
-- @return number penalty The penalty amount charged (0 if none)
function LoanService:earlyRepayment(loan, amount)
    if not g_currentMission:getIsServer() then return 0 end
    if loan.paidOff then return 0 end
    if amount == nil or amount <= 0 then return 0 end
    amount = math.min(amount, loan.restAmount)
    if Loan.isPayoffAmount(loan.restAmount, amount) then
        amount = loan.restAmount
    end
    if not LoanService.isValidFarmId(loan.farmId) then
        Logging.warning("[BankCredit] earlyRepayment: rejected on loan #%d with invalid farmId=%s",
            loan.id or -1, tostring(loan.farmId))
        return 0
    end

    local bankSettings = g_currentMission ~= nil and g_currentMission.bankSettings or nil
    local penaltyPct = (bankSettings and bankSettings.earlyRepaymentPenalty) or 0
    local penalty    = amount * (penaltyPct / 100)
    local riskLevel  = loan.riskLevel
    local principalPortion = amount

    g_currentMission:addMoney(-amount,   loan.farmId, MoneyType.LOAN_PRINCIPAL, true, true)
    if penalty > 0 then
        g_currentMission:addMoney(-penalty, loan.farmId, MoneyType.LOAN_INTEREST, true, true)
        self.bankService:onInterestReceived(penalty)
    end

    if amount >= loan.restAmount then
        loan.paidOff      = true
        loan.restAmount   = 0
        loan.restDuration = 0
    else
        loan.restAmount = math.floor((loan.restAmount - amount) * 100 + 0.5) / 100
        if loan.monthlyPayment > 0 and loan.type == Loan.TYPE.ANNUITY then
            local r = loan.interestRate / 100 / 12
            if r > 0 then
                local x = loan.restAmount * r / loan.monthlyPayment
                if x >= 1 then
                    loan.restDuration = 1
                else
                    loan.restDuration = math.ceil(-math.log(1 - x) / math.log(1 + r))
                end
            else
                loan.restDuration = math.ceil(loan.restAmount / loan.monthlyPayment)
            end
        elseif loan.type == Loan.TYPE.REVOLVING then
            -- Revolving: no duration recalculation; restDuration stays 0
        end
        -- BULLET: restDuration unchanged — maturity date is fixed, only the final bullet amount shrinks
    end

    self.bankService:onRepaymentReceived(amount, loan.riskLevel)

    -- Annual report: record principal repaid (+ penalty as interest) and potential closure
    if self.annualReport ~= nil then
        local currentYear = g_currentMission.environment.currentYear
        self.annualReport:recordPrincipal(loan.farmId, currentYear, amount)
        if penalty > 0 then
            self.annualReport:recordInterest(loan.farmId, currentYear, penalty)
        end
        if loan.paidOff then
            self.annualReport:recordLoanClosed(loan.farmId, currentYear)
        end
    end

    if g_server ~= nil then
        g_server:broadcastEvent(
            LoanPaymentEvent.new(loan.id, loan.restAmount, loan.restDuration, loan.paidOff, penalty, principalPortion, riskLevel),
            false
        )
        if self.annualReport ~= nil then
            g_server:broadcastEvent(AnnualReportSyncEvent.new(self.annualReport), false)
        end
    end

    return penalty
end

---Draws an amount from a revolving credit line. Server-authoritative.
-- @param table loan Loan instance (must be REVOLVING, not paidOff)
-- @param number amount Amount to draw
function LoanService:drawRevolving(loan, amount)
    if not g_currentMission:getIsServer() then return end
    if loan.paidOff then return end
    if loan.type ~= Loan.TYPE.REVOLVING then return end
    if amount == nil or amount <= 0 then return end
    if loan.restAmount + amount > loan.amount then return end
    if not LoanService.isValidFarmId(loan.farmId) then
        Logging.warning("[BankCredit] drawRevolving: rejected on loan #%d with invalid farmId=%s",
            loan.id or -1, tostring(loan.farmId))
        return
    end

    local concentrationLimit = self.bankService:getConcentrationLimit()
    local farmExposure       = self.bankService:getFarmExposure(loan.farmId, self.repository)
    if farmExposure + amount > concentrationLimit then return end

    loan.restAmount = math.floor((loan.restAmount + amount) * 100 + 0.5) / 100

    g_currentMission:addMoney(amount, loan.farmId, MoneyType.LOAN_PRINCIPAL, true, true)

    self.bankService:onLoanDisbursed({ amount = amount, riskLevel = loan.riskLevel })

    if g_server ~= nil then
        g_server:broadcastEvent(
            LoanPaymentEvent.new(loan.id, loan.restAmount, 0, false, 0, 0, loan.riskLevel, amount),
            false
        )
    end
end

---Repays an amount on a revolving credit line. Server-authoritative.
-- @param table loan Loan instance (must be REVOLVING, not paidOff)
-- @param number amount Amount to repay
function LoanService:repayRevolving(loan, amount)
    if not g_currentMission:getIsServer() then return end
    if loan.paidOff then return end
    if loan.type ~= Loan.TYPE.REVOLVING then return end
    if amount == nil or amount <= 0 then return end
    if amount > loan.restAmount then amount = loan.restAmount end
    if Loan.isPayoffAmount(loan.restAmount, amount) then
        amount = loan.restAmount
    end
    if not LoanService.isValidFarmId(loan.farmId) then
        Logging.warning("[BankCredit] repayRevolving: rejected on loan #%d with invalid farmId=%s",
            loan.id or -1, tostring(loan.farmId))
        return
    end

    loan.restAmount = math.floor((loan.restAmount - amount) * 100 + 0.5) / 100

    g_currentMission:addMoney(-amount, loan.farmId, MoneyType.LOAN_PRINCIPAL, true, true)

    self.bankService:onRepaymentReceived(amount, loan.riskLevel)

    -- Annual report: record revolving principal repaid
    if self.annualReport ~= nil then
        local currentYear = g_currentMission.environment.currentYear
        self.annualReport:recordPrincipal(loan.farmId, currentYear, amount)
    end

    if g_server ~= nil then
        g_server:broadcastEvent(
            LoanPaymentEvent.new(loan.id, loan.restAmount, 0, false, 0, amount, loan.riskLevel),
            false
        )
        if self.annualReport ~= nil then
            g_server:broadcastEvent(AnnualReportSyncEvent.new(self.annualReport), false)
        end
    end
end

---Closes a revolving credit line. Server-authoritative.
-- @param table loan Loan instance (must be REVOLVING, restAmount == 0, not paidOff)
function LoanService:closeRevolving(loan)
    if not g_currentMission:getIsServer() then return end
    if loan.paidOff then return end
    if loan.type ~= Loan.TYPE.REVOLVING then return end
    if loan.restAmount > 0 then return end

    loan.paidOff = true

    -- Annual report: record revolving line closure
    if self.annualReport ~= nil then
        local currentYear = g_currentMission.environment.currentYear
        self.annualReport:recordLoanClosed(loan.farmId, currentYear)
    end

    if g_server ~= nil then
        g_server:broadcastEvent(
            LoanPaymentEvent.new(loan.id, 0, 0, true, 0, 0, loan.riskLevel),
            false
        )
        if self.annualReport ~= nil then
            g_server:broadcastEvent(AnnualReportSyncEvent.new(self.annualReport), false)
        end
    end
end
