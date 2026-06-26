-- Copyright © 2026 Squallqt. All rights reserved.
-- Two-step dialog guiding the player through loan configuration and recap / confirm.
TakeLoanWizard = {}
local TakeLoanWizard_mt = Class(TakeLoanWizard, MessageDialog)

TakeLoanWizard.CONTROLS = {
    "mainTitleText",
    "titleSep",
    "stepPanel1",
    "stepPanel2",
    -- Step 1
    "optLoanType",
    "textTypeDescription",
    "inputAmount",
    "textAmountLimit",
    "cardDuration",
    "inputDuration",
    "textMonthlyPreview",
    "textTotalCostPreview",
    "textTotalInterestPreview",
    -- Step 2 — values
    "textRecapBaseRate",
    "textRecapTypeSurcharge",
    "textRecapSurcharge",
    "textRecapRate",
    "textRecapMonthly",
    "textRecapTotalInterest",
    "textRecapTotalCost",
    "textRecapDSCR",
    "textRecapLTV",
    "textRecapRisk",
    "textRecapWarning",
    "textRecapHint",
    "textAmountComparison",
    -- Step 2 — clickable labels
    "btnRecapRates",
    "btnRecapBaseRate",
    "btnRecapTypeSpread",
    "btnRecapSurcharge",
    "btnRecapEffRate",
    "btnRecapRiskSection",
    "btnRecapDSCR",
    "btnRecapLTV",
    "btnRecapRisk",
    "btnRecapCost",
    "btnRecapMonthly",
    "btnRecapTotalInterest",
    "btnRecapTotalCost",
    -- Buttons
    "btnPrev",
    "btnNext",
    "btnConfirm",
    "sepLeft",
    "sepRight",
    -- Dialog root (for dynamic resize)
    "dialogElement",
}

TakeLoanWizard.COLOR_RISK = {
    [Loan.RISK.LOW]      = {0.40, 0.85, 0.40, 1},
    [Loan.RISK.MODERATE] = {1.00, 0.82, 0.00, 1},
    [Loan.RISK.HIGH]     = {1.00, 0.55, 0.10, 1},
    [Loan.RISK.CRITICAL] = {1.00, 0.30, 0.30, 1},
    [Loan.RISK.REFUSED]  = {1.00, 0.20, 0.20, 1},
}

TakeLoanWizard.LOAN_TYPES = {
    Loan.TYPE.ANNUITY,
    Loan.TYPE.BULLET,
    Loan.TYPE.REVOLVING,
}

TakeLoanWizard.AMOUNT_MIN        = 10000
TakeLoanWizard.DURATION_MIN_YEARS = 1
TakeLoanWizard.DURATION_MAX_YEARS = 20

---Creates new take-loan wizard dialog instance
-- @param target Parent target element
-- @param table? customMt Optional custom metatable
-- @return TakeLoanWizard instance
function TakeLoanWizard.new(target, customMt)
    local self = MessageDialog.new(target, customMt or TakeLoanWizard_mt)

    self.currentStep     = 1
    self.farmId          = -1
    self.selectedType    = Loan.TYPE.ANNUITY
    self.selectedAmount  = 0
    self.durationMonths  = 120
    self.amountLimit     = 0
    self.lastEvaluation  = nil
    self.lastCanDisburse = nil

    return self
end

---Loads dialog controls
function TakeLoanWizard:onLoad()
    TakeLoanWizard:superClass().onLoad(self)
    self:registerControls(TakeLoanWizard.CONTROLS)
end

---Finalizes GUI setup and wires control callbacks
function TakeLoanWizard:onGuiSetupFinished()
    TakeLoanWizard:superClass().onGuiSetupFinished(self)

    if self.optLoanType then
        self.optLoanType:setTexts({
            g_i18n:getText("bank_loanType_annuity"),
            g_i18n:getText("bank_loanType_bullet"),
            g_i18n:getText("bank_loanType_revolving"),
        })
    end

    self:applyBulletLabels()

    -- Cache base dialog size for dynamic resize (Revolving has no duration card)
    if self.dialogElement then
           self.baseDialogW = self.dialogElement.size[1]
           self.baseDialogH = self.dialogElement.size[2]
    end
end

function TakeLoanWizard:onOpen()
    TakeLoanWizard:superClass().onOpen(self)
    self:resizeTitleSep()

    if FocusManager.currentFocusData ~= nil then
        FocusManager.currentFocusData.focusElement = nil
        FocusManager.currentFocusData.initialFocusElement = nil
    end

    if self.btnNext ~= nil then
        FocusManager:setFocus(self.btnNext)
    end
end

function TakeLoanWizard:resizeTitleSep()
    if self.titleSep == nil or self.mainTitleText == nil then return end

    if self._titleSepHeight == nil then
        self._titleSepHeight = self.titleSep.absSize[2]
    end

    local text = self.mainTitleText.text or ""
    local textWidth = getTextWidth(self.mainTitleText.textSize, text)
    local newWidth = textWidth + 20 * 2 * g_pixelSizeScaledX

    self.titleSep:setSize(newWidth, self._titleSepHeight)
    if self.titleSep.parent ~= nil and self.titleSep.parent.invalidateLayout ~= nil then
        self.titleSep.parent:invalidateLayout()
    end
end

function TakeLoanWizard:onClose()
    if self.inputAmount ~= nil then
        self.inputAmount:abortIme()
    end
    if self.inputDuration ~= nil then
        self.inputDuration:abortIme()
    end

    if FocusManager.currentFocusData ~= nil then
        local focusEl = FocusManager.currentFocusData.focusElement
        if focusEl ~= nil then
            FocusManager:unsetFocus(focusEl)
        end
        FocusManager.currentFocusData.focusElement = nil
        FocusManager.currentFocusData.initialFocusElement = nil
    end

    TakeLoanWizard:superClass().onClose(self)
end

-- ===================== PREFIXED DATA LABELS =====================

TakeLoanWizard.DATA_LABELS = {
    {id = "btnRecapBaseRate",      key = "bank_wizard_recap_baseRate"},
    {id = "btnRecapTypeSpread",    key = "bank_wizard_recap_typeSpread"},
    {id = "btnRecapSurcharge",     key = "bank_wizard_recap_surcharge"},
    {id = "btnRecapEffRate",       key = "bank_wizard_recap_effectiveRate"},
    {id = "btnRecapDSCR",          key = "bank_wizard_recap_dscr"},
    {id = "btnRecapLTV",           key = "bank_wizard_recap_ltv"},
    {id = "btnRecapRisk",          key = "bank_wizard_recap_risk"},
    {id = "btnRecapMonthly",       key = "bank_wizard_recap_monthly"},
    {id = "btnRecapTotalInterest", key = "bank_wizard_recap_totalInterest"},
    {id = "btnRecapTotalCost",     key = "bank_wizard_recap_totalCost"},
}

---Prefixes recap data-label buttons with a middle-dot bullet for visual alignment
function TakeLoanWizard:applyBulletLabels()
    for _, entry in ipairs(TakeLoanWizard.DATA_LABELS) do
        local btn = self[entry.id]
        if btn ~= nil then
            btn:setText("\xC2\xB7  " .. g_i18n:getText(entry.key))
        end
    end
end

---Resets the wizard state for a new session
-- @param integer farmId Farm identifier
function TakeLoanWizard:reset(farmId)
    self.farmId         = farmId or self.farmId
    self.currentStep    = 1
    self.selectedType   = Loan.TYPE.ANNUITY
    self.durationMonths = 120
    self.lastEvaluation = nil
    self.lastCanDisburse = nil

    if self.optLoanType ~= nil then
        self.optLoanType:setState(1, false)
    end

    local manager = g_currentMission.bankManager
    if manager ~= nil then
        local bankAvail  = manager.bankService:getAvailableCapacity()
        self.amountLimit = manager.creditService:getEffectiveLimit(self.farmId, bankAvail, manager.repository, manager.bankService)
    else
        self.amountLimit = 0
    end

    self.selectedAmount = math.min(self.amountLimit, 100000)

    if self.inputAmount   then self.inputAmount:setText(tostring(math.floor(self.selectedAmount))) end
    if self.inputDuration then self.inputDuration:setText(tostring(math.floor(self.durationMonths / 12))) end
    self:syncStepPanels()
    self:updateStep1()
end


---Toggles visibility of the two step panels to match current step
function TakeLoanWizard:syncStepPanels()
    if self.stepPanel1 then self.stepPanel1:setVisible(self.currentStep == 1) end
    if self.stepPanel2 then self.stepPanel2:setVisible(self.currentStep == 2) end

    if self.btnPrev    then self.btnPrev:setVisible(self.currentStep > 1) end
    if self.btnNext    then self.btnNext:setVisible(self.currentStep < 2) end
    if self.btnConfirm then self.btnConfirm:setVisible(self.currentStep == 2) end
    if self.sepLeft    then self.sepLeft:setVisible(self.currentStep == 2) end

    self:updateDialogSize()
end

---Resizes the dialog height to match visible content: smaller on step 1 for Revolving (no duration card)
function TakeLoanWizard:updateDialogSize()
    if self.dialogElement == nil or self.baseDialogH == nil or self.cardDuration == nil then return end
    local isSmall = (self.currentStep == 1) and (self.selectedType == Loan.TYPE.REVOLVING)
    if isSmall then
    local cardH    = self.cardDuration.size[2]
    local gapH     = 18 / 1440  -- vertical gap between Amount card and Duration card (layout constant)
        self.dialogElement:setSize(self.baseDialogW, self.baseDialogH - cardH - gapH)
    else
        self.dialogElement:setSize(self.baseDialogW, self.baseDialogH)
    end
end

-- ===================== STEP 1 — TYPE + AMOUNT + DURATION =====================

---Updates step 1 dynamic labels (type description, amount limit, duration/monthly preview)
function TakeLoanWizard:updateStep1()
    local isRevolving = (self.selectedType == Loan.TYPE.REVOLVING)

    -- Type description
    if self.textTypeDescription then
        local descKey
        if self.selectedType == Loan.TYPE.ANNUITY then
            descKey = "bank_loanType_annuity_desc"
        elseif self.selectedType == Loan.TYPE.BULLET then
            descKey = "bank_loanType_bullet_desc"
        else
            descKey = "bank_loanType_revolving_desc"
        end

        local desc = g_i18n:getText(descKey)

        local manager = g_currentMission.bankManager
        if manager ~= nil and self.selectedAmount > 0 then
            local typeSpread = manager.rateModel:getTypeSpread(self.selectedType)
            local indicativeRate = manager.rateModel:getRate() + typeSpread
            desc = desc .. "\n" .. string.format(
                g_i18n:getText("bank_wizard_indicativeRate"),
                string.format("%.2f%%", indicativeRate))
        end

        self.textTypeDescription:setText(desc)
    end

    -- Amount limit
    if self.textAmountLimit then
        self.textAmountLimit:setText(string.format(
            g_i18n:getText("bank_wizard_limit"),
            g_i18n:formatMoney(self.amountLimit, 0, true, false)))
    end

    -- Duration card visibility (hidden for Revolving) + dialog resize
    if self.cardDuration then
        self.cardDuration:setVisible(not isRevolving)
    end
    self:updateDialogSize()

    -- Monthly preview (live update)
    if self.textMonthlyPreview and not isRevolving then
        local manager = g_currentMission.bankManager
        if manager ~= nil and self.selectedAmount > 0 then
            local rate    = manager.rateModel:getRate()
            local monthly = manager.loanService:getMonthlyPayment(
                self.selectedAmount, rate, self.durationMonths, self.selectedType)
            self.textMonthlyPreview:setText(string.format(
                g_i18n:getText("bank_wizard_monthlyPreview"),
                g_i18n:formatMoney(monthly, 0, true, false)))

            -- Total cost preview
            local totalCost     = monthly * self.durationMonths
            local totalInterest = math.max(0, totalCost - self.selectedAmount)
            if self.textTotalCostPreview then
                self.textTotalCostPreview:setText(string.format(
                    g_i18n:getText("bank_wizard_totalCostPreview"),
                    g_i18n:formatMoney(totalCost, 0, true, false)))
            end
            if self.textTotalInterestPreview then
                self.textTotalInterestPreview:setText(string.format(
                    g_i18n:getText("bank_wizard_totalInterestPreview"),
                    g_i18n:formatMoney(totalInterest, 0, true, false)))
            end
        else
            self.textMonthlyPreview:setText("—")
            if self.textTotalCostPreview    then self.textTotalCostPreview:setText("—") end
            if self.textTotalInterestPreview then self.textTotalInterestPreview:setText("") end
        end
    end
end

---MultiTextOption callback for loan type selection
-- @param integer state New state index
function TakeLoanWizard:onLoanTypeChanged(state)
    self.selectedType = TakeLoanWizard.LOAN_TYPES[state] or Loan.TYPE.ANNUITY
    self:updateStep1()
end

---TextInput live filter: strip non-numeric characters from amount field
-- @param table element TextInput element
-- @param string text Current text content
function TakeLoanWizard:onAmountTextChanged(element, text)
    local filtered = string.gsub(text or "", "[^0-9]", "")
    if filtered ~= text then element:setText(filtered) end
end

---TextInput commit: clamp amount to [AMOUNT_MIN, amountLimit] on Enter or focus leave
-- @param table element TextInput element
function TakeLoanWizard:onAmountEnterPressed(element)
    local value   = tonumber(element:getText() or "") or 0
    local clamped = math.floor(math.max(TakeLoanWizard.AMOUNT_MIN, math.min(value, self.amountLimit)))
    self.selectedAmount = clamped
    element:setText(tostring(clamped))
    self:updateStep1()
end

---TextInput live filter: strip non-numeric characters and clamp to max years
-- @param table element TextInput element
-- @param string text Current text content
function TakeLoanWizard:onDurationTextChanged(element, text)
    local filtered = string.gsub(text or "", "[^0-9]", "")
    local value = tonumber(filtered)
    if value ~= nil and value > TakeLoanWizard.DURATION_MAX_YEARS then
        filtered = tostring(TakeLoanWizard.DURATION_MAX_YEARS)
    end
    if filtered ~= text then element:setText(filtered) end
end

---TextInput commit: clamp duration to [DURATION_MIN_YEARS, DURATION_MAX_YEARS] on Enter or focus leave
-- @param table element TextInput element
function TakeLoanWizard:onDurationEnterPressed(element)
    local years   = tonumber(element:getText() or "") or 0
    local clamped = math.max(TakeLoanWizard.DURATION_MIN_YEARS, math.min(years, TakeLoanWizard.DURATION_MAX_YEARS))
    self.durationMonths = clamped * 12
    element:setText(tostring(clamped))
    self:updateStep1()
end

-- ===================== STEP 2 — RECAP + CONFIRM =====================

---Evaluates the loan request and populates recap labels
function TakeLoanWizard:updateStep2()
    local manager = g_currentMission.bankManager
    if manager == nil then return end

    local effectiveDuration = self.selectedType == Loan.TYPE.REVOLVING and 0 or self.durationMonths

    local check = manager.loanService:canDisburse(
        self.farmId, self.selectedAmount, self.selectedType, effectiveDuration)
    self.lastCanDisburse = check

    local baseRate = manager.rateModel:getRate()
    local evaluation = check.evaluation
    if evaluation == nil then
        local ltv  = manager.creditService:getLTV(self.farmId, self.selectedAmount, manager.repository)
        local monthlyPreview = manager.loanService:getMonthlyPayment(
            self.selectedAmount, baseRate, effectiveDuration, self.selectedType)
        local dscr = manager.creditService:getDSCR(self.farmId, monthlyPreview)
        local risk = manager.creditService:scoreRisk(dscr, ltv)
        evaluation = {
            risk            = risk,
            effectiveAmount = self.selectedAmount * risk.amountCapRatio,
            effectiveRate   = manager.rateModel:getRateForRiskAndType(risk.level, self.selectedType),
            typeSpread      = manager.rateModel:getTypeSpread(self.selectedType),
            dscr            = dscr,
            ltv             = ltv,
        }
    end
    self.lastEvaluation = evaluation

    local effectiveRate  = evaluation.effectiveRate
    local typeSpread     = evaluation.typeSpread or 0
    local riskSurcharge  = effectiveRate - baseRate - typeSpread

    local isRevolving = (self.selectedType == Loan.TYPE.REVOLVING)

    if isRevolving then
        local estimatedInterest1yr = evaluation.effectiveAmount * (effectiveRate / 100)

        if self.textRecapBaseRate      then self.textRecapBaseRate:setText(string.format("%.2f%%", baseRate)) end
        if self.textRecapTypeSurcharge then self.textRecapTypeSurcharge:setText(string.format("+%.2f%%", typeSpread)) end
        if self.textRecapSurcharge     then self.textRecapSurcharge:setText(string.format("+%.2f%%", riskSurcharge)) end
        if self.textRecapRate          then self.textRecapRate:setText(string.format("%.2f%%", effectiveRate)) end
        local commitmentFeeAnnual = evaluation.effectiveAmount * LoanService.COMMITMENT_FEE_RATE

        if self.textRecapMonthly       then self.textRecapMonthly:setText(g_i18n:getText("bank_revolving_variablePayment")) end
        if self.btnRecapTotalInterest  then self.btnRecapTotalInterest:setText("\xC2\xB7  " .. g_i18n:getText("bank_revolving_estimatedInterest")) end
        if self.textRecapTotalInterest then self.textRecapTotalInterest:setText(g_i18n:formatMoney(estimatedInterest1yr, 0, true, false)) end
        if self.btnRecapTotalCost      then self.btnRecapTotalCost:setText("\xC2\xB7  " .. g_i18n:getText("bank_revolving_commitmentFee")) end
        if self.textRecapTotalCost     then self.textRecapTotalCost:setText(g_i18n:formatMoney(commitmentFeeAnnual, 0, true, false) .. g_i18n:getText("bank_revolving_commitmentFeeSuffix")) end
    else
        local monthly = manager.loanService:getMonthlyPayment(
            evaluation.effectiveAmount, effectiveRate, effectiveDuration, self.selectedType)
        local totalPaid
        if self.selectedType == Loan.TYPE.BULLET then
            totalPaid = monthly * effectiveDuration + evaluation.effectiveAmount
        else
            totalPaid = monthly * effectiveDuration
        end
        local totalInterest = math.max(0, totalPaid - evaluation.effectiveAmount)

        if self.textRecapBaseRate      then self.textRecapBaseRate:setText(string.format("%.2f%%", baseRate)) end
        if self.textRecapTypeSurcharge then self.textRecapTypeSurcharge:setText(string.format("+%.2f%%", typeSpread)) end
        if self.textRecapSurcharge     then self.textRecapSurcharge:setText(string.format("+%.2f%%", riskSurcharge)) end
        if self.textRecapRate          then self.textRecapRate:setText(string.format("%.2f%%", effectiveRate)) end
        if self.textRecapMonthly       then self.textRecapMonthly:setText(g_i18n:formatMoney(monthly, 0, true, false)) end
        if self.btnRecapTotalInterest  then self.btnRecapTotalInterest:setText("\xC2\xB7  " .. g_i18n:getText("bank_wizard_recap_totalInterest")) end
        if self.textRecapTotalInterest then self.textRecapTotalInterest:setText(g_i18n:formatMoney(totalInterest, 0, true, false)) end
        if self.btnRecapTotalCost      then self.btnRecapTotalCost:setText("\xC2\xB7  " .. g_i18n:getText("bank_wizard_recap_totalCost")) end
        if self.textRecapTotalCost     then self.textRecapTotalCost:setText(g_i18n:formatMoney(totalPaid, 0, true, false)) end
    end

    if self.textRecapDSCR then
        if evaluation.dscr == math.huge then
            self.textRecapDSCR:setText("N/A")
        else
            self.textRecapDSCR:setText(string.format("%.2f", evaluation.dscr))
        end
    end
    if self.textRecapLTV then
        if evaluation.ltv == math.huge then
            self.textRecapLTV:setText("N/A")
        else
            self.textRecapLTV:setText(string.format("%.0f%%", evaluation.ltv * 100))
        end
    end

    if self.textRecapRisk then
        local key = BankFrame.RISK_NAME_KEYS[evaluation.risk.level] or "bank_risk_low"
        self.textRecapRisk:setText(g_i18n:getText(key))
        local color = TakeLoanWizard.COLOR_RISK[evaluation.risk.level] or TakeLoanWizard.COLOR_RISK[Loan.RISK.LOW]
        self.textRecapRisk:setTextColor(unpack(color))
    end

    -- Warnings & confirm availability
    local warningText = ""
    local canConfirm  = check.ok
    if not check.ok then
        if check.reason == "limit_exceeded" then
            warningText = g_i18n:getText("bank_wizard_warn_limitExceeded")
        elseif check.reason == "concentration_exceeded" then
            warningText = g_i18n:getText("bank_wizard_warn_concentrationExceeded")
        elseif check.reason == "risk_refused" then
            warningText = g_i18n:getText("bank_wizard_warn_refused")
        elseif check.reason == "invalid_amount" then
            warningText = g_i18n:getText("bank_wizard_warn_invalidAmount")
        else
            warningText = g_i18n:getText("bank_wizard_warn_refused")
        end
    elseif evaluation.risk.level == Loan.RISK.CRITICAL then
        warningText = g_i18n:getText("bank_wizard_warn_critical50")
    end

    if self.textRecapWarning then
        self.textRecapWarning:setText(warningText)
        self.textRecapWarning:setVisible(warningText ~= "")
    end
    if self.textRecapHint then
        self.textRecapHint:setVisible(true)
        if not check.ok then
            self.textRecapHint:setText(g_i18n:getText("bank_wizard_hint_refused"))
        else
            self.textRecapHint:setText(g_i18n:getText("bank_info_hint"))
        end
    end

    -- Amount cap comparison block
    if self.textAmountComparison then
        local isCapped = evaluation.effectiveAmount < self.selectedAmount
        self.textAmountComparison:setVisible(isCapped)
        if isCapped then
            self.textAmountComparison:setText(string.format(
                g_i18n:getText("bank_wizard_amountCapped"),
                g_i18n:formatMoney(self.selectedAmount,        0, true, false),
                g_i18n:formatMoney(evaluation.effectiveAmount, 0, true, false)))
        end
    end

    if self.btnConfirm then
        self.btnConfirm:setDisabled(not canConfirm)
    end

end

-- ===================== NAVIGATION =====================

---Advances to the next step
function TakeLoanWizard:onClickNext()
    if self.currentStep >= 2 then return end
    if self.inputAmount   then self:onAmountEnterPressed(self.inputAmount) end
    if self.inputDuration and self.selectedType ~= Loan.TYPE.REVOLVING then
        self:onDurationEnterPressed(self.inputDuration)
    end
    if self.btnPrev ~= nil then FocusManager:setFocus(self.btnPrev) end
    self.currentStep = 2
    self:syncStepPanels()
    self:updateStep2()
end

---Goes back to the previous step
function TakeLoanWizard:onClickPrev()
    if self.currentStep <= 1 then return end
    if self.btnNext ~= nil then FocusManager:setFocus(self.btnNext) end
    self.currentStep = 1
    self:syncStepPanels()
    self:updateStep1()
end

---Confirms and dispatches the loan request (server call or network event)
function TakeLoanWizard:onClickConfirm()
    if self.lastCanDisburse == nil or not self.lastCanDisburse.ok then
        return
    end
    if self.lastEvaluation == nil then return end

    local amount = g_i18n:formatMoney(self.lastEvaluation.effectiveAmount, 0, true, false)
    local rate   = string.format("%.2f%%", self.lastEvaluation.effectiveRate)
    local text   = string.format(g_i18n:getText("bank_wizard_confirm_msg"), amount, rate)

    YesNoDialog.show(self.onLoanConfirmed, self, text)
end

---Handles loan confirmation result
-- @param boolean confirmed True if user confirmed
function TakeLoanWizard:onLoanConfirmed(confirmed)
    if not confirmed then return end
    if self.lastCanDisburse == nil or not self.lastCanDisburse.ok then return end

    local manager = g_currentMission.bankManager
    if manager == nil then return end

    local effectiveDuration = self.selectedType == Loan.TYPE.REVOLVING and 0 or self.durationMonths

    if g_currentMission:getIsServer() then
        manager.loanService:disburse(
            self.farmId, self.selectedAmount, self.selectedType, effectiveDuration)
    elseif g_client ~= nil and g_client.getServerConnection ~= nil then
        g_client:getServerConnection():sendEvent(
            LoanRequestEvent.new(self.farmId, self.selectedType, self.selectedAmount, effectiveDuration))
    end

    local frame = g_currentMission.bankFrame
    if frame ~= nil then
        frame:refreshDashboard()
        frame:refreshList()
    end

    self:close()
end

---Closes the dialog (back button)
function TakeLoanWizard:onClickBack()
    self:close()
end

-- ===================== STEP 2 — INFO CLICK HANDLERS =====================

---Opens an InfoDialog with localized text and resets hover/press state on all recap info buttons
-- @param string textKey l10n key to display
function TakeLoanWizard:showRecapInfo(textKey)
    if self.btnConfirm ~= nil then
        FocusManager:setFocus(self.btnConfirm)
    end

    local buttons = {
        self.btnRecapRates, self.btnRecapBaseRate, self.btnRecapTypeSpread,
        self.btnRecapSurcharge, self.btnRecapEffRate,
        self.btnRecapRiskSection, self.btnRecapDSCR, self.btnRecapLTV, self.btnRecapRisk,
        self.btnRecapCost, self.btnRecapMonthly, self.btnRecapTotalInterest, self.btnRecapTotalCost
    }
    for _, btn in ipairs(buttons) do
        if btn ~= nil then
            btn.inputEntered = false
            btn.inputDown = false
        end
    end

    InfoDialog.show(g_i18n:getText(textKey))
end

-- ===================== SECTION TITLES =====================

---Shows info dialog for the Rates section header
function TakeLoanWizard:onClickInfoRecapRates() self:showRecapInfo("bank_wizard_info_rates") end
---Shows info dialog for the Risk section header
function TakeLoanWizard:onClickInfoRecapRiskSection() self:showRecapInfo("bank_wizard_info_risk_section") end
---Shows info dialog for the Cost section header
function TakeLoanWizard:onClickInfoRecapCost() self:showRecapInfo("bank_wizard_info_cost") end

-- ===================== RATES DATA =====================

---Shows info dialog explaining the base rate
function TakeLoanWizard:onClickInfoRecapBaseRate() self:showRecapInfo("bank_wizard_info_baseRate") end
---Shows info dialog explaining the product-type spread
function TakeLoanWizard:onClickInfoRecapTypeSpread() self:showRecapInfo("bank_wizard_info_typeSpread") end
---Shows info dialog explaining the risk surcharge
function TakeLoanWizard:onClickInfoRecapSurcharge() self:showRecapInfo("bank_wizard_info_surcharge") end
---Shows info dialog explaining the effective rate (TEG)
function TakeLoanWizard:onClickInfoRecapEffRate() self:showRecapInfo("bank_wizard_info_effectiveRate") end

-- ===================== RISK DATA =====================

---Shows info dialog explaining the DSCR metric
function TakeLoanWizard:onClickInfoRecapDSCR() self:showRecapInfo("bank_detail_info_dscr") end
---Shows info dialog explaining the LTV metric
function TakeLoanWizard:onClickInfoRecapLTV() self:showRecapInfo("bank_detail_info_ltv") end
---Shows info dialog explaining the risk level
function TakeLoanWizard:onClickInfoRecapRisk() self:showRecapInfo("bank_detail_info_risk") end

-- ===================== COST DATA =====================

---Shows info dialog explaining the monthly payment
function TakeLoanWizard:onClickInfoRecapMonthly() self:showRecapInfo("bank_wizard_info_monthly") end
---Shows info dialog explaining the total interest
function TakeLoanWizard:onClickInfoRecapTotalInterest() self:showRecapInfo("bank_wizard_info_totalInterest") end
---Shows info dialog explaining the total cost
function TakeLoanWizard:onClickInfoRecapTotalCost() self:showRecapInfo("bank_wizard_info_totalCost") end
