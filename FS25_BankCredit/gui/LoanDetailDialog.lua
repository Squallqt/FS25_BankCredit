-- Copyright © 2026 Squallqt. All rights reserved.
-- Dialog showing loan summary header and full amortization schedule.
LoanDetailDialog = {}
local LoanDetailDialog_mt = Class(LoanDetailDialog, MessageDialog)

LoanDetailDialog.CONTROLS = {
    "mainTitleText",
    "titleSep",
    "btnAmount",
    "btnRate",
    "btnType",
    "btnRisk",
    "btnDSCR",
    "btnLTV",
    "textAmount",
    "textRate",
    "textType",
    "textRisk",
    "textDSCR",
    "textLTV",
    "listSchedule",
    "sliderBox",
    "scheduleHeaders",
    -- Revolving panel
    "revolvingPanel",
    "revBarFill",
    "textRevUtilPct",
    "btnRevUtilSection",
    "btnRevLimit",
    "textRevLimit",
    "btnRevDrawn",
    "textRevDrawn",
    "btnRevAvailable",
    "textRevAvailable",

    "btnRevCondSection",
    "btnRevRate",
    "textRevRate",
    "btnRevInterestMonth",
    "textRevInterestMonth",
    "btnRevInterestYear",
    "textRevInterestYear",
    "btnRevCommitmentFee",
    "textRevCommitmentFee",
    "btnRevDuration",
    "textRevDuration",
    "btnRevPayment",
    "textRevPayment",
    "mainHint",
    -- Revolving action buttons
    "btnRevRepay",
    "sepRevRepay",
    "btnRevClose",
    "sepRevClose",
    "btnRevDraw",
    "sepRevDraw",
    "dialogElement",
}

LoanDetailDialog.COLOR_RISK = {
    [Loan.RISK.LOW]      = {0.40, 0.85, 0.40, 1},
    [Loan.RISK.MODERATE] = {1.00, 0.82, 0.00, 1},
    [Loan.RISK.HIGH]     = {1.00, 0.55, 0.10, 1},
    [Loan.RISK.CRITICAL] = {1.00, 0.30, 0.30, 1},
    [Loan.RISK.REFUSED]  = {1.00, 0.20, 0.20, 1},
}

LoanDetailDialog.COLOR_CURRENT_ROW = {1.00, 0.82, 0.00, 1}
LoanDetailDialog.COLOR_PAST_ROW    = {0.22, 0.22, 0.22, 1}

---Creates new loan detail dialog instance
-- @param table target Parent target element
-- @param table? customMt Optional custom metatable
-- @return LoanDetailDialog instance The new dialog instance
function LoanDetailDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or LoanDetailDialog_mt)

    self.loan          = nil
    self.scheduleRows  = {}
    self.currentRowIdx = -1

    return self
end

---Loads dialog controls
function LoanDetailDialog:onLoad()
    LoanDetailDialog:superClass().onLoad(self)
    self:registerControls(LoanDetailDialog.CONTROLS)
end

---Finalizes GUI setup
function LoanDetailDialog:onGuiSetupFinished()
    LoanDetailDialog:superClass().onGuiSetupFinished(self)

    if self.listSchedule ~= nil then
        self.listSchedule:setDataSource(self)
        self.listSchedule:setDelegate(self)
    end
end

---Called when dialog opens
function LoanDetailDialog:onOpen()
    LoanDetailDialog:superClass().onOpen(self)
end

---Resizes title separator to match title text width
function LoanDetailDialog:resizeTitleSep()
    if self.titleSep == nil or self.mainTitleText == nil then return end

    if self._titleSepHeight == nil then
        self._titleSepHeight = self.titleSep.absSize[2]
    end

    local text = self.mainTitleText.text or ""
    local textWidth = getTextWidth(self.mainTitleText.textSize, text)
    local padding = 20 * 2 * g_pixelSizeScaledX
    local newWidth = textWidth + padding

    self.titleSep:setSize(newWidth, self._titleSepHeight)
    if self.titleSep.parent ~= nil and self.titleSep.parent.invalidateLayout ~= nil then
        self.titleSep.parent:invalidateLayout()
    end
end

---Sets the loan to display and rebuilds the amortization schedule
-- @param table loan Loan instance
function LoanDetailDialog:setLoan(loan)
    self.loan = loan
    self:buildSchedule()

    if loan == nil then return end

    if self.mainTitleText then
        self.mainTitleText:setText(string.format(g_i18n:getText("bank_detail_title"), loan.id))
        self:resizeTitleSep()
    end
    if self.textAmount then
        self.textAmount:setText(g_i18n:formatMoney(loan.amount, 0, true, false))
    end
    if self.textRate then
        self.textRate:setText(string.format("%.2f%%", loan.interestRate))
    end
    if self.textType then
        local key = BankFrame.TYPE_NAME_KEYS[loan.type] or "bank_loanType_annuity"
        self.textType:setText(g_i18n:getText(key))
    end
    if self.textRisk then
        local key = BankFrame.RISK_NAME_KEYS[loan.riskLevel] or "bank_risk_low"
        self.textRisk:setText(g_i18n:getText(key))
        local color = LoanDetailDialog.COLOR_RISK[loan.riskLevel] or LoanDetailDialog.COLOR_RISK[Loan.RISK.LOW]
        self.textRisk:setTextColor(unpack(color))
    end
    if self.textDSCR then
        if loan.dscr == math.huge then
            self.textDSCR:setText("N/A")
        else
            self.textDSCR:setText(string.format("%.2f", loan.dscr))
        end
    end
    if self.textLTV then
        if loan.ltv == math.huge then
            self.textLTV:setText("N/A")
        else
            self.textLTV:setText(string.format("%.0f%%", loan.ltv * 100))
        end
    end

    -- Reset revolving action buttons (dialog is reused across loans)
    self:resetRevolvingButtons()

    -- Revolving: show structured panel instead of schedule
    if loan.type == Loan.TYPE.REVOLVING then
        if self.listSchedule    then self.listSchedule:setVisible(false) end
        if self.sliderBox       then self.sliderBox:setVisible(false) end
        if self.scheduleHeaders then self.scheduleHeaders:setVisible(false) end
        if self.revolvingPanel  then self.revolvingPanel:setVisible(true) end
        if self.mainHint        then self.mainHint:setVisible(false) end
        if self.dialogElement   then self.dialogElement:setSize(1000 * g_pixelSizeScaledX, 600 * g_pixelSizeScaledY) end
        self:updateRevolvingPanel(loan)
        self:updateRevolvingButtons(loan)
    else
        if self.listSchedule    then self.listSchedule:setVisible(true) end
        if self.scheduleHeaders then self.scheduleHeaders:setVisible(true) end
        if self.revolvingPanel  then self.revolvingPanel:setVisible(false) end
        if self.mainHint        then self.mainHint:setVisible(true) end
        if self.dialogElement   then self.dialogElement:setSize(1000 * g_pixelSizeScaledX, 760 * g_pixelSizeScaledY) end
    end

    if self.listSchedule then
        self.listSchedule:reloadData()
        self:scrollToCurrentRow()
    end

    self:updateSliderVisibility()
end

---Scrolls the schedule list to position the current month row at the top
function LoanDetailDialog:scrollToCurrentRow()
    if self.listSchedule == nil then return end
    if self.currentRowIdx == nil or self.currentRowIdx <= 0 then return end

    local sections = self.listSchedule.sections
    if sections == nil or sections[1] == nil or sections[1].itemOffsets == nil then return end

    local offset = sections[1].itemOffsets[self.currentRowIdx]
    if offset == nil then return end

    self.listSchedule:smoothScrollTo(offset)
end

---Shows or hides scroll slider based on item count
function LoanDetailDialog:updateSliderVisibility()
    if self.sliderBox then
        local maxVisibleItems = math.floor(430 / 32)
        self.sliderBox:setVisible(#self.scheduleRows > maxVisibleItems)
    end
end

---Builds the amortization schedule rows by simulating month-by-month payments
function LoanDetailDialog:buildSchedule()
    self.scheduleRows = {}
    self.currentRowIdx = -1

    local loan = self.loan
    if loan == nil then return end
    if loan.type == Loan.TYPE.REVOLVING then return end

    local manager = g_currentMission.bankManager
    if manager == nil then return end
    local loanService = manager.loanService

    local balance  = loan.amount
    local rate     = loan.interestRate
    local duration = loan.duration
    local monthly  = loanService:getMonthlyPayment(balance, rate, duration, loan.type)

    local currentPeriod = math.max(1, duration - loan.restDuration + 1)

    for period = 1, duration do
        local interest  = balance * (rate / 100) / 12
        local principal
        if loan.type == Loan.TYPE.ANNUITY then
            principal = monthly - interest
            if period == duration or principal > balance then
                principal = balance
            end
        elseif loan.type == Loan.TYPE.BULLET then
            if period == duration then
                principal = balance
                monthly   = interest + principal
            else
                principal = 0
                monthly   = interest
            end
        end

        local payment = principal + interest
        balance       = math.max(0, balance - principal)

        table.insert(self.scheduleRows, {
            period    = period,
            payment   = payment,
            interest  = interest,
            principal = principal,
            balance   = balance,
        })
    end

    self.currentRowIdx = currentPeriod
end

-- ===================== SMOOTHLIST DATA SOURCE / DELEGATE =====================

---Returns number of list sections
-- @return integer count Always 1
function LoanDetailDialog:getNumberOfSections()
    return 1
end

---Returns number of items in section
-- @param table list SmoothList element
-- @param integer section Section index
-- @return integer count Number of schedule rows
function LoanDetailDialog:getNumberOfItemsInSection(list, section)
    return #self.scheduleRows
end

---Returns section header title
-- @param table list SmoothList element
-- @param integer section Section index
-- @return string|nil title
function LoanDetailDialog:getTitleForSectionHeader(list, section)
    return nil
end

---Returns section header height
-- @param table list SmoothList element
-- @param integer section Section index
-- @return number height
function LoanDetailDialog:getSectionHeaderHeight(list, section)
    return 0
end

---Populates cell with schedule row data
-- @param table list SmoothList element
-- @param integer section Section index
-- @param integer index Item index
-- @param table cell Cell element to populate
function LoanDetailDialog:populateCellForItemInSection(list, section, index, cell)
    local row = self.scheduleRows[index]
    if row == nil then return end

    local cellPeriod    = cell:getDescendantByName("cellPeriod")
    local cellPayment   = cell:getDescendantByName("cellPayment")
    local cellInterest  = cell:getDescendantByName("cellInterest")
    local cellPrincipal = cell:getDescendantByName("cellPrincipal")
    local cellBalance   = cell:getDescendantByName("cellBalance")

    if cellPeriod    then cellPeriod:setText(tostring(row.period))                               end
    if cellPayment   then cellPayment:setText(g_i18n:formatMoney(row.payment, 0, true, false))   end
    if cellInterest  then cellInterest:setText(g_i18n:formatMoney(row.interest, 0, true, false)) end
    if cellPrincipal then cellPrincipal:setText(g_i18n:formatMoney(row.principal, 0, true, false))end
    if cellBalance   then cellBalance:setText(g_i18n:formatMoney(row.balance, 0, true, false))   end

    local isCurrent = (index == self.currentRowIdx)
    local isPast    = (index < self.currentRowIdx)
    local color
    if isCurrent then
        color = LoanDetailDialog.COLOR_CURRENT_ROW
    elseif isPast then
        color = LoanDetailDialog.COLOR_PAST_ROW
    else
        color = {0.85, 0.85, 0.85, 1}
    end
    if cellPeriod    then cellPeriod:setTextColor(unpack(color))    end
    if cellPayment   then cellPayment:setTextColor(unpack(color))   end
    if cellInterest  then cellInterest:setTextColor(unpack(color))  end
    if cellPrincipal then cellPrincipal:setTextColor(unpack(color)) end
    if cellBalance   then cellBalance:setTextColor(unpack(color))   end
end

---Called when list selection changes
-- @param table list SmoothList element
-- @param integer section Section index
-- @param integer index Item index
function LoanDetailDialog:onListSelectionChanged(list, section, index)
end

-- ===================== INFO HELPER =====================

---Opens an InfoDialog with localized text and resets hover/press state on all info buttons
-- @param string textKey l10n key to display
function LoanDetailDialog:showInfo(textKey)
    local allButtons = {
        self.btnAmount, self.btnRate, self.btnType, self.btnRisk, self.btnDSCR, self.btnLTV,
        self.btnRevUtilSection, self.btnRevLimit, self.btnRevDrawn, self.btnRevAvailable,
        self.btnRevCondSection, self.btnRevRate, self.btnRevInterestMonth, self.btnRevInterestYear,
        self.btnRevDuration, self.btnRevPayment
    }
    for _, btn in ipairs(allButtons) do
        if btn ~= nil then
            btn.inputEntered = false
            btn.inputDown = false
        end
    end

    InfoDialog.show(g_i18n:getText(textKey))
end

---Shows info dialog explaining the loan amount
function LoanDetailDialog:onClickInfoAmount()   self:showInfo("bank_detail_info_amount") end
---Shows info dialog explaining the interest rate
function LoanDetailDialog:onClickInfoRate()     self:showInfo("bank_detail_info_rate")   end
---Shows info dialog explaining the loan type
function LoanDetailDialog:onClickInfoType()     self:showInfo("bank_detail_info_type")   end
---Shows info dialog explaining the risk level
function LoanDetailDialog:onClickInfoRisk()     self:showInfo("bank_detail_info_risk")   end
---Shows info dialog explaining the DSCR metric
function LoanDetailDialog:onClickInfoDSCR()     self:showInfo("bank_detail_info_dscr")   end
---Shows info dialog explaining the LTV metric
function LoanDetailDialog:onClickInfoLTV()      self:showInfo("bank_detail_info_ltv")    end

-- ===================== REVOLVING PANEL =====================

LoanDetailDialog.REV_BULLET_LABELS = {
    {id = "btnRevLimit",         key = "bank_detail_revolving_limit"},
    {id = "btnRevDrawn",         key = "bank_detail_revolving_drawn"},
    {id = "btnRevAvailable",     key = "bank_detail_revolving_available"},
    {id = "btnRevRate",          key = "bank_detail_label_rate"},
    {id = "btnRevInterestMonth", key = "bank_detail_rev_interest_month"},
    {id = "btnRevInterestYear",  key = "bank_detail_rev_interest_year"},
    {id = "btnRevCommitmentFee", key = "bank_revolving_commitmentFee"},
    {id = "btnRevDuration",      key = "bank_detail_rev_duration"},
    {id = "btnRevPayment",       key = "bank_detail_rev_payment"},
}

---Prefixes revolving panel bullet labels with a middle-dot for visual alignment
function LoanDetailDialog:applyRevBulletLabels()
    for _, entry in ipairs(LoanDetailDialog.REV_BULLET_LABELS) do
        local btn = self[entry.id]
        if btn ~= nil then
            btn:setText("\xC2\xB7  " .. g_i18n:getText(entry.key))
        end
    end
end

---Refreshes the revolving-loan panel values (limit, drawn, available, rate, interest, utilization bar)
-- @param table loan Revolving loan instance
function LoanDetailDialog:updateRevolvingPanel(loan)
    self:applyRevBulletLabels()

    local available = loan.amount - loan.restAmount
    local utilPct   = (loan.amount > 0) and (loan.restAmount / loan.amount * 100) or 0
    local interestYear  = loan.restAmount * (loan.interestRate / 100)
    local interestMonth = interestYear / 12

    -- Data values
    if self.textRevLimit        then self.textRevLimit:setText(g_i18n:formatMoney(loan.amount, 0, true, false)) end
    if self.textRevDrawn        then self.textRevDrawn:setText(g_i18n:formatMoney(loan.restAmount, 0, true, false)) end
    if self.textRevAvailable    then self.textRevAvailable:setText(g_i18n:formatMoney(available, 0, true, false)) end

    if self.textRevRate         then self.textRevRate:setText(string.format("%.2f%%", loan.interestRate)) end
    if self.textRevInterestMonth then self.textRevInterestMonth:setText(g_i18n:formatMoney(interestMonth, 0, true, false)) end
    if self.textRevInterestYear  then self.textRevInterestYear:setText(g_i18n:formatMoney(interestYear, 0, true, false)) end
    local commitmentFeeYear = loan.amount * LoanService.COMMITMENT_FEE_RATE
    if self.textRevCommitmentFee then self.textRevCommitmentFee:setText(g_i18n:formatMoney(commitmentFeeYear, 0, true, false) .. "/an max") end
    if self.textRevDuration      then self.textRevDuration:setText(g_i18n:getText("bank_revolving_noDuration")) end
    if self.textRevPayment      then self.textRevPayment:setText(g_i18n:getText("bank_revolving_variablePayment")) end

    -- Progress bar: fill width & color
    if self.revBarFill then
        local maxWidth = 397 * g_pixelSizeScaledX
        local fillWidth = maxWidth * math.min(1, utilPct / 100)

        if self.revBarFill._baseHeight == nil then
            self.revBarFill._baseHeight = self.revBarFill.absSize[2]
        end
        self.revBarFill:setSize(fillWidth, self.revBarFill._baseHeight)
    end

    -- Progress bar percentage text
    if self.textRevUtilPct then
        self.textRevUtilPct:setText(string.format("%.0f%%", utilPct))
    end
end

-- ===================== REVOLVING CLICK HANDLERS =====================

---Shows info dialog explaining revolving utilization
function LoanDetailDialog:onClickInfoRevUtil()      self:showInfo("bank_detail_info_rev_utilization") end
---Shows info dialog explaining revolving credit limit
function LoanDetailDialog:onClickInfoRevLimit()      self:showInfo("bank_detail_info_rev_limit") end
---Shows info dialog explaining revolving drawn amount
function LoanDetailDialog:onClickInfoRevDrawn()      self:showInfo("bank_detail_info_rev_drawn") end
---Shows info dialog explaining revolving available amount
function LoanDetailDialog:onClickInfoRevAvail()      self:showInfo("bank_detail_info_rev_available") end
---Shows info dialog explaining revolving conditions section
function LoanDetailDialog:onClickInfoRevCond()       self:showInfo("bank_detail_info_rev_conditions") end
---Shows info dialog explaining the interest rate
function LoanDetailDialog:onClickInfoRevRate()       self:showInfo("bank_detail_info_rate") end
---Shows info dialog explaining revolving monthly interest estimate
function LoanDetailDialog:onClickInfoRevIntMonth()   self:showInfo("bank_detail_info_rev_interest_month") end
---Shows info dialog explaining revolving yearly interest estimate
function LoanDetailDialog:onClickInfoRevIntYear()       self:showInfo("bank_detail_info_rev_interest_year") end
---Shows info dialog explaining revolving commitment fee
function LoanDetailDialog:onClickInfoRevCommitmentFee() self:showInfo("bank_detail_info_rev_commitment_fee") end
---Shows info dialog explaining revolving duration (no fixed term)
function LoanDetailDialog:onClickInfoRevDuration()   self:showInfo("bank_detail_info_rev_duration") end
---Shows info dialog explaining revolving payment model
function LoanDetailDialog:onClickInfoRevPayment()    self:showInfo("bank_detail_info_rev_payment") end

---Resets all revolving action buttons to hidden
function LoanDetailDialog:resetRevolvingButtons()
    local els = { self.btnRevRepay, self.sepRevRepay, self.btnRevClose, self.sepRevClose, self.btnRevDraw, self.sepRevDraw }
    for _, el in ipairs(els) do
        if el then el:setVisible(false) end
    end
end

---Shows revolving action buttons based on loan state
-- @param table loan Revolving loan instance
function LoanDetailDialog:updateRevolvingButtons(loan)
    if loan.paidOff then return end

    if self.btnRevDraw then
        self.btnRevDraw:setVisible(true)
        self.btnRevDraw.disabled = loan.restAmount >= loan.amount
    end
    if self.sepRevDraw then self.sepRevDraw:setVisible(true) end

    if loan.restAmount > 0 then
        if self.btnRevRepay then self.btnRevRepay:setVisible(true) end
        if self.sepRevRepay then self.sepRevRepay:setVisible(true) end
    else
        if self.btnRevClose then self.btnRevClose:setVisible(true) end
        if self.sepRevClose then self.sepRevClose:setVisible(true) end
    end
end

---Closes the dialog and forwards the draw action to the parent frame
function LoanDetailDialog:onClickRevDraw()
    local frame = self.target
    self:close()
    if frame then frame:onClickDraw() end
end

---Closes the dialog and forwards the early-repay action to the parent frame
function LoanDetailDialog:onClickRevRepay()
    local frame = self.target
    self:close()
    if frame then frame:onClickEarlyRepay() end
end

---Closes the dialog and forwards the close-line action to the parent frame
function LoanDetailDialog:onClickRevClose()
    local frame = self.target
    self:close()
    if frame then frame:onClickCloseLine() end
end

---Closes the dialog
function LoanDetailDialog:onClickBack()
    self:close()
end
