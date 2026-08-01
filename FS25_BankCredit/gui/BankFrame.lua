-- Copyright © 2026 Squallqt. All rights reserved.
---InGameMenu frame for the bank dashboard and loan lists.
BankFrame = {}
BankFrame._mt = Class(BankFrame, TabbedMenuFrameElement)

BankFrame.TAB = {
    ACTIVE = 1,
    PAID   = 2,
}

BankFrame.SCREEN_EDGE_SLIDER_MARGIN_X = 0
BankFrame.NATIVE_DOCKED_SLIDER_OFFSET_Y = 10

BankFrame.COLOR_ACTIVE = {1.00, 0.82, 0.00, 1}
BankFrame.COLOR_PAID   = {0.40, 0.85, 0.40, 1}

BankFrame.RISK_NAME_KEYS = {
    [Loan.RISK.LOW]      = "bank_risk_low",
    [Loan.RISK.MODERATE] = "bank_risk_moderate",
    [Loan.RISK.HIGH]     = "bank_risk_high",
    [Loan.RISK.CRITICAL] = "bank_risk_critical",
    [Loan.RISK.REFUSED]  = "bank_risk_refused",
}

BankFrame.TYPE_NAME_KEYS = {
    [Loan.TYPE.ANNUITY]   = "bank_loanType_annuity",
    [Loan.TYPE.BULLET]    = "bank_loanType_bullet",
    [Loan.TYPE.REVOLVING] = "bank_loanType_revolving",
}

---Creates new bank frame instance
-- @param table i18n Internationalization context
-- @param table messageCenter Message center instance
-- @return BankFrame instance The new frame instance
function BankFrame.new(i18n, messageCenter)
    local self = BankFrame:superClass().new(nil, BankFrame._mt)

    self.name          = "BankFrame"
    self.i18n          = i18n
    self.messageCenter = messageCenter

    self.currentTab    = BankFrame.TAB.ACTIVE
    self.selectedLoan  = nil
    self.loansList     = {}

    return self
end

---Performs GUI setup after elements are initialized
function BankFrame:onGuiSetupFinished()
    BankFrame:superClass().onGuiSetupFinished(self)

    if self.listLoans then
        self.listLoans:setDataSource(self)
        self.listLoans:setDelegate(self)
    end
    if self.listPaidLoans then
        self.listPaidLoans:setDataSource(self)
        self.listPaidLoans:setDelegate(self)
    end
end

---Initializes frame buttons, tabs, and menu button info
function BankFrame:initialize()
    BankFrame:superClass().initialize(self)

    for i, tab in pairs(self.subCategoryTabs) do
        tab:getDescendantByName("background").getIsSelected = function()
            return i == self.subCategoryPaging:getState()
        end
        function tab.getIsSelected()
            return i == self.subCategoryPaging:getState()
        end
    end

    self.btnBack = {
        inputAction = InputAction.MENU_BACK
    }

    self.btnNewLoan = {
        text = self.i18n:getText("bank_btn_newLoan"),
        inputAction = InputAction.MENU_ACTIVATE,
        callback = function() self:onClickNewLoan() end
    }

    self.btnDetails = {
        text = self.i18n:getText("bank_btn_details"),
        inputAction = InputAction.MENU_EXTRA_1,
        disabled = true,
        callback = function() self:onClickDetails() end
    }

    self.btnRepay = {
        text = self.i18n:getText("bank_btn_earlyRepay"),
        inputAction = InputAction.MENU_ACCEPT,
        disabled = true,
        callback = function() self:onClickEarlyRepay() end
    }

    self.btnDraw = {
        text = self.i18n:getText("bank_revolving_draw"),
        inputAction = InputAction.MENU_ACCEPT,
        disabled = true,
        callback = function() self:onClickDraw() end
    }

    self.btnRepayRevolving = {
        text = self.i18n:getText("bank_btn_repayLine"),
        inputAction = InputAction.MENU_CANCEL,
        disabled = true,
        callback = function() self:onClickEarlyRepay() end
    }

    self.btnCloseLine = {
        text = self.i18n:getText("bank_btn_close"),
        inputAction = InputAction.MENU_CANCEL,
        disabled = true,
        callback = function() self:onClickCloseLine() end
    }

    self.btnIndicators = {
        text = self.i18n:getText("bank_btn_indicators"),
        inputAction = InputAction.MENU_EXTRA_2,
        callback = function() self:onClickBankHealth() end
    }

    self.btnReport = {
        text = self.i18n:getText("bank_btn_report"),
        inputAction = InputAction.MENU_CANCEL,
        callback = function() self:onClickReport() end
    }

    self.menuButtonInfoByTab = {
        [BankFrame.TAB.ACTIVE] = { self.btnBack, self.btnNewLoan, self.btnIndicators, self.btnReport, self.btnDetails, self.btnRepay },
        [BankFrame.TAB.PAID]   = { self.btnBack, self.btnNewLoan, self.btnIndicators, self.btnReport, self.btnDetails },
    }
end

---Returns menu button info for the current tab
-- @return table buttonInfo Array of button definitions
function BankFrame:getMenuButtonInfo()
    if self.menuButtonInfoByTab == nil then
        return {}
    end
    return self.menuButtonInfoByTab[self.currentTab] or {}
end

---Called when frame is opened, loads dashboard and list
function BankFrame:onFrameOpen()
    BankFrame:superClass().onFrameOpen(self)
    g_currentMission.bankFrame = self

    self.currentTab = BankFrame.TAB.ACTIVE

    if self.subCategoryPaging and self.subCategoryBox then
        local texts = {}
        local tabLabels = {
            g_i18n:getText("bank_tab_active"),
            g_i18n:getText("bank_tab_paid"),
        }
        for k, tab in pairs(self.subCategoryTabs) do
            tab:setVisible(true)
            table.insert(texts, tabLabels[k] or tostring(k))
        end
        self.subCategoryBox:invalidateLayout()
        self.subCategoryPaging:setTexts(texts)
        self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)
    end

    self:updateBalanceDisplay()
    self:refreshDashboard()

    self.subCategoryPaging:setState(self.currentTab, true)
    for k, v in pairs(self.subCategoryPages) do
        v:setVisible(k == self.currentTab)
    end

    self:refreshList()
    self:updateScreenEdgeSliders()

    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.onMoneyChanged, self)
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    g_messageCenter:subscribe(MessageType.FARMLAND_OWNER_CHANGED, self.onFarmlandOwnerChanged, self)

    self:setMenuButtonInfoDirty()
end

---Called when frame is closed, unsubscribes from events
function BankFrame:onFrameClose()
    BankFrame:superClass().onFrameClose(self)
    g_messageCenter:unsubscribeAll(self)
    g_currentMission.bankFrame = nil
end

---Updates the frame and docked slider positions
-- @param float dt Elapsed time in milliseconds
function BankFrame:update(dt)
    BankFrame:superClass().update(self, dt)
    self:updateScreenEdgeSliders()
end

---Called when player money changes
function BankFrame:onMoneyChanged()
    self:updateBalanceDisplay()
    self:refreshDashboard()
end

---Called at each period change (monthly collection)
function BankFrame:onPeriodChanged()
    self:refreshDashboard()
    self:refreshList()
end

---Called when farmland ownership changes
function BankFrame:onFarmlandOwnerChanged()
    self:refreshDashboard()
end

---Switches to active loans tab
function BankFrame:onClickTabActive()
    self.subCategoryPaging:setState(BankFrame.TAB.ACTIVE, true)
    self:setMenuButtonInfoDirty()
end

---Switches to paid loans tab
function BankFrame:onClickTabPaid()
    self.subCategoryPaging:setState(BankFrame.TAB.PAID, true)
    self:setMenuButtonInfoDirty()
end

---Updates page visibility based on current tab
function BankFrame:updateSubCategoryPages()
    self.currentTab = self.subCategoryPaging:getState()

    for k, v in pairs(self.subCategoryPages) do
        v:setVisible(k == self.currentTab)
    end

    self:refreshList()
    self:setMenuButtonInfoDirty()
end

---Returns the current player farm ID
-- @return integer farmId
function BankFrame:getCurrentFarmId()
    if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
        return g_localPlayer.farmId
    end
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if farm then return farm.farmId end
    return -1
end

---Returns the bank manager, or nil if unavailable
-- @return table|nil manager
function BankFrame:getManager()
    return g_currentMission.bankManager
end

---Updates all dashboard labels from current bank state
function BankFrame:refreshDashboard()
    local manager = self:getManager()
    if manager == nil then return end

    local bankService   = manager.bankService
    local creditService = manager.creditService
    local rateModel     = manager.rateModel
    local farmId        = self:getCurrentFarmId()

    local bankAvail      = bankService:getAvailableCapacity()
    local effectiveLimit = creditService:getEffectiveLimit(farmId, bankAvail, manager.repository, bankService)
    local farmExposure   = bankService:getFarmExposure(farmId, manager.repository)

    if self.dashAvailableValue then
        self.dashAvailableValue:setText(g_i18n:formatMoney(effectiveLimit, 0, true, false))
    end

    if self.dashOutstandingValue then
        self.dashOutstandingValue:setText(g_i18n:formatMoney(farmExposure, 0, true, false))
    end
    if self.dashOutstandingSubValue then
        local personalCap = farmExposure + effectiveLimit
        local pct = 0
        if personalCap > 0 then
            pct = farmExposure / personalCap * 100
        end
        self.dashOutstandingSubValue:setText(string.format(g_i18n:getText("bank_dash_outstanding_sub"), math.floor(pct + 0.5)))
    end

    if self.dashMonthlyTotalValue then
        local total = 0
        local allLoans = manager.repository:getByFarm(farmId)
        for _, loan in ipairs(allLoans) do
            if not loan.paidOff then
                if loan.type == Loan.TYPE.REVOLVING then
                    if loan.restAmount > 0 then
                        total = total + loan.restAmount * (loan.interestRate / 100) / 12
                    end
                else
                    total = total + loan.monthlyPayment
                end
            end
        end
        self.dashMonthlyTotalValue:setText(g_i18n:formatMoney(total, 0, true, false))
    end

    if self.dashRateValue then
        self.dashRateValue:setText(string.format("%.2f%% %s", rateModel:getRate(), rateModel:getDirection()))
    end
end

---Updates balance display with current farm money (native shop widget)
function BankFrame:updateBalanceDisplay()
    if self.currentBalanceText == nil then return end
    if g_localPlayer ~= nil then
        local farm = g_farmManager:getFarmById(g_localPlayer.farmId)
        if farm then
            if farm.money <= -1 then
                self.currentBalanceText:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY_NEGATIVE, nil, true)
            else
                self.currentBalanceText:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY, nil, true)
            end
            local moneyText = g_i18n:formatMoney(farm.money, 0, true, false)
            self.currentBalanceText:setText(moneyText)
            if self.shopMoneyBox ~= nil then
                self.shopMoneyBox:invalidateLayout()
                self.shopMoneyBoxBg:setSize(self.shopMoneyBox.flowSizes[1] + 60 * g_pixelSizeScaledX)
            end
        end
    end
end

---Reloads loan list for current farm based on active tab
function BankFrame:refreshList()
    self.selectedLoan = nil

    local manager = self:getManager()
    if manager == nil then
        self.loansList = {}
        if self.listLoans then self.listLoans:reloadData() end
        if self.listPaidLoans then self.listPaidLoans:reloadData() end
        self:refreshLoanSliders()
        self:updateEmptyState()
        self:updateButtonStates()
        self:updateSliderVisibility()
        return
    end

    local farmId   = self:getCurrentFarmId()
    local allLoans = manager.repository:getByFarm(farmId)

    if self.currentTab == BankFrame.TAB.ACTIVE then
        local filtered = {}
        for _, loan in ipairs(allLoans) do
            if not loan.paidOff then
                table.insert(filtered, loan)
            end
        end
        table.sort(filtered, function(a, b) return a.id > b.id end)
        self.loansList = filtered
        if self.listLoans then self.listLoans:reloadData() end

    elseif self.currentTab == BankFrame.TAB.PAID then
        local filtered = {}
        for _, loan in ipairs(allLoans) do
            if loan.paidOff then
                table.insert(filtered, loan)
            end
        end
        table.sort(filtered, function(a, b) return a.id > b.id end)
        self.loansList = filtered
        if self.listPaidLoans then self.listPaidLoans:reloadData() end
    end

    self:refreshLoanSliders()
    self:updateEmptyState()
    self:updateButtonStates()
    self:updateSliderVisibility()
end

---Refreshes the loan list slider bindings
function BankFrame:refreshLoanSliders()
    if self.loansSlider ~= nil and self.listLoans ~= nil then
        self.loansSlider:onBindUpdate(self.listLoans)
    end
    if self.paidSlider ~= nil and self.listPaidLoans ~= nil then
        self.paidSlider:onBindUpdate(self.listPaidLoans)
    end
end

---Shows the docked slider for the current tab
function BankFrame:updateSliderVisibility()
    if self.loansSliderBox then
        self.loansSliderBox:setVisible(self.currentTab == BankFrame.TAB.ACTIVE)
    end
    if self.paidSliderBox then
        self.paidSliderBox:setVisible(self.currentTab == BankFrame.TAB.PAID)
    end
end

---Positions docked loan sliders at the screen edge
function BankFrame:updateScreenEdgeSliders()
    local sliderBoxes = {
        self.loansSliderBox,
        self.paidSliderBox
    }

    for _, sliderBox in ipairs(sliderBoxes) do
        if sliderBox ~= nil
            and sliderBox.absPosition ~= nil
            and sliderBox.absSize ~= nil
            and sliderBox.absSize[1] ~= nil then
            sliderBox:updateAbsolutePosition()

            local x = 1 - sliderBox.absSize[1] - BankFrame.SCREEN_EDGE_SLIDER_MARGIN_X
            local y = sliderBox.absPosition[2] + BankFrame.NATIVE_DOCKED_SLIDER_OFFSET_Y * (g_pixelSizeScaledY or 0)

            sliderBox:setAbsolutePosition(x, y)

            for _, child in ipairs(sliderBox.elements) do
                child:updateAbsolutePosition()
            end
        end
    end
end

---Shows or hides empty state based on current tab
function BankFrame:updateEmptyState()
    if self.currentTab == BankFrame.TAB.ACTIVE then
        local hasLoans = #self.loansList > 0
        if self.loansListContainer then self.loansListContainer:setVisible(hasLoans) end
        if self.emptyListContainer then self.emptyListContainer:setVisible(not hasLoans) end
    elseif self.currentTab == BankFrame.TAB.PAID then
        local hasLoans = #self.loansList > 0
        if self.paidLoansListContainer then self.paidLoansListContainer:setVisible(hasLoans) end
        if self.emptyPaidListContainer then self.emptyPaidListContainer:setVisible(not hasLoans) end
    end
end

---Updates button enabled/disabled states based on selection and tab
function BankFrame:updateButtonStates()
    if self.btnNewLoan == nil then return end

    local farmId      = self:getCurrentFarmId()
    local isSpectator = farmId == FarmManager.SPECTATOR_FARM_ID or farmId < 1

    self.btnNewLoan.disabled = isSpectator
    self.btnDetails.disabled = self.selectedLoan == nil

    if self.currentTab == BankFrame.TAB.ACTIVE then
        local isRevolving = self.selectedLoan ~= nil and self.selectedLoan.type == Loan.TYPE.REVOLVING

        if isRevolving and not self.selectedLoan.paidOff then
            self.btnDraw.disabled = isSpectator or self.selectedLoan.restAmount >= self.selectedLoan.amount
            if self.selectedLoan.restAmount > 0 then
                self.btnRepayRevolving.disabled = isSpectator
                self.menuButtonInfoByTab[BankFrame.TAB.ACTIVE] = { self.btnBack, self.btnNewLoan, self.btnIndicators, self.btnDraw, self.btnDetails, self.btnRepayRevolving }
            else
                self.btnCloseLine.disabled = isSpectator
                self.menuButtonInfoByTab[BankFrame.TAB.ACTIVE] = { self.btnBack, self.btnNewLoan, self.btnIndicators, self.btnDraw, self.btnDetails, self.btnCloseLine }
            end
        else
            self.btnRepay.disabled = self.selectedLoan == nil or self.selectedLoan.paidOff or isSpectator
            self.menuButtonInfoByTab[BankFrame.TAB.ACTIVE] = { self.btnBack, self.btnNewLoan, self.btnIndicators, self.btnReport, self.btnDetails, self.btnRepay }
        end
    elseif self.currentTab == BankFrame.TAB.PAID then
        self.menuButtonInfoByTab[BankFrame.TAB.PAID] = { self.btnBack, self.btnNewLoan, self.btnIndicators, self.btnReport, self.btnDetails }
    end

    self:setMenuButtonInfoDirty()
end

---Returns number of list sections
-- @return integer count Always 1
function BankFrame:getNumberOfSections()
    return 1
end

---Returns number of items in section
-- @param table list SmoothList element
-- @param integer section Section index
-- @return integer count Number of loans
function BankFrame:getNumberOfItemsInSection(list, section)
    return #self.loansList
end

---Returns section header title
-- @param table list SmoothList element
-- @param integer section Section index
-- @return string|nil title
function BankFrame:getTitleForSectionHeader(list, section)
    return nil
end

---Returns section header height
-- @param table list SmoothList element
-- @param integer section Section index
-- @return number height
function BankFrame:getSectionHeaderHeight(list, section)
    return 0
end

---Populates cell with loan data
-- @param table list SmoothList element
-- @param integer section Section index
-- @param integer index Item index
-- @param table cell Cell element to populate
function BankFrame:populateCellForItemInSection(list, section, index, cell)
    local loan = self.loansList[index]
    if loan == nil then return end

    local typeKey  = BankFrame.TYPE_NAME_KEYS[loan.type] or "bank_loanType_annuity"
    local typeStr  = g_i18n:getText(typeKey)
    local amountStr     = g_i18n:formatMoney(loan.amount, 0, true, false)
    local rateStr       = string.format("%.2f%%", loan.interestRate)

    local isRevolving = (loan.type == Loan.TYPE.REVOLVING)

    local monthlyStr, durationStr, restStr, statusStr, statusColor

    if isRevolving then
        if loan.restAmount > 0 then
            local monthlyInterest = loan.restAmount * (loan.interestRate / 100) / 12
            monthlyStr = g_i18n:formatMoney(monthlyInterest, 0, true, false)
        else
            monthlyStr = "—"
        end
        durationStr = "—"
        restStr     = g_i18n:formatMoney(loan.restAmount, 0, true, false)
        if loan.paidOff then
            statusStr   = g_i18n:getText("bank_status_paid")
            statusColor = BankFrame.COLOR_PAID
        elseif loan.restAmount > 0 then
            statusStr   = g_i18n:getText("bank_revolving_status_open")
            statusColor = BankFrame.COLOR_ACTIVE
        else
            statusStr   = g_i18n:getText("bank_revolving_status_available")
            statusColor = {0.40, 0.85, 0.40, 1}
        end
    else
        monthlyStr = g_i18n:formatMoney(loan.monthlyPayment, 0, true, false)
        local restYears = loan.restDuration / 12
        durationStr = string.format(g_i18n:getText("bank_format_monthsShort"), loan.restDuration)
        if restYears >= 1 then
            durationStr = string.format(g_i18n:getText("bank_format_yearsMonths"),
                math.floor(restYears), loan.restDuration % 12)
        end
        restStr = g_i18n:formatMoney(loan.restAmount, 0, true, false)
        if loan.paidOff then
            statusStr   = g_i18n:getText("bank_status_paid")
            statusColor = BankFrame.COLOR_PAID
        else
            statusStr   = g_i18n:getText("bank_status_active")
            statusColor = BankFrame.COLOR_ACTIVE
        end
    end

    local cellType     = cell:getDescendantByName("cellType")
    local cellAmount   = cell:getDescendantByName("cellAmount")
    local cellMonthly  = cell:getDescendantByName("cellMonthly")
    local cellRate     = cell:getDescendantByName("cellRate")
    local cellDuration = cell:getDescendantByName("cellDuration")
    local cellRest     = cell:getDescendantByName("cellRest")
    local cellStatus   = cell:getDescendantByName("cellStatus")

    if cellType     then cellType:setText(typeStr)         end
    if cellAmount   then cellAmount:setText(amountStr)     end
    if cellMonthly  then cellMonthly:setText(monthlyStr)   end
    if cellRate     then cellRate:setText(rateStr)         end
    if cellDuration then cellDuration:setText(durationStr) end
    if cellRest     then cellRest:setText(restStr)         end
    if cellStatus then
        cellStatus:setText(statusStr)
        cellStatus:setTextColor(unpack(statusColor))
    end
end

---Called when list selection changes
-- @param table list SmoothList element
-- @param integer section Section index
-- @param integer index Selected item index
function BankFrame:onListSelectionChanged(list, section, index)
    if index > 0 and index <= #self.loansList then
        self.selectedLoan = self.loansList[index]
    else
        self.selectedLoan = nil
    end
    self:updateButtonStates()
end

---Opens the annual report dialog
function BankFrame:onClickReport()
    local dialog = g_gui:showDialog("AnnualReportDialog")
    if dialog and dialog.target then
        dialog.target:loadYears()
        dialog.target:refresh()
    end
end

---Opens the bank health dialog
function BankFrame:onClickBankHealth()
    local dialog = g_gui:showDialog("BankHealthDialog")
    if dialog and dialog.target then
        dialog.target:refresh()
    end
end

---Opens the take-loan wizard
function BankFrame:onClickNewLoan()
    local manager = self:getManager()
    if manager == nil then return end

    local farmId      = self:getCurrentFarmId()
    local isSpectator = farmId == FarmManager.SPECTATOR_FARM_ID or farmId < 1
    if isSpectator then
        InfoDialog.show(g_i18n:getText("bank_error_noFarm"))
        return
    end

    local dialog = g_gui:showDialog("TakeLoanWizard")
    if dialog and dialog.target then
        dialog.target:reset(farmId)
    end
end

---Opens the loan detail dialog
function BankFrame:onClickDetails()
    if self.selectedLoan == nil then return end

    local dialog = g_gui:showDialog("LoanDetailDialog")
    if dialog and dialog.target then
        dialog.target:setLoan(self.selectedLoan)
    end
end

---Shows early repayment confirmation dialog
function BankFrame:onClickEarlyRepay()
    if self.selectedLoan == nil then return end
    if self.selectedLoan.paidOff then return end

    local manager = self:getManager()
    if manager == nil then return end

    local loan = self.selectedLoan

    if loan.type == Loan.TYPE.REVOLVING then
        if loan.restAmount <= 0 then return end
        local maxRepay = loan.restAmount
        local maxRepayDisplay = BankCredit.toDisplayMoney(maxRepay)
        local title = string.format(g_i18n:getText("bank_confirm_repay_revolving"),
            g_i18n:formatMoney(maxRepay, 0, true, false))
        NumericInputDialog.show(self.onRevolvingRepayAmountEntered, self,
            tostring(maxRepayDisplay), title, nil, math.max(10, string.len(tostring(maxRepayDisplay))), g_i18n:getText("button_ok"),
            nil, maxRepayDisplay)
        return
    end

    local minRepay = math.floor(loan.amount * 0.10)
    local maxRepay = loan.restAmount
    local minValue = loan.restAmount > minRepay and minRepay or nil
    local minPromptRepay = minValue or maxRepay
    local minValueDisplay = minValue ~= nil and BankCredit.toDisplayMoney(minValue) or nil
    local maxRepayDisplay = BankCredit.toDisplayMoney(maxRepay)
    local prompt = string.format(g_i18n:getText("bank_confirm_partialRepay_amount"),
        g_i18n:formatMoney(minPromptRepay, 0, true, false),
        g_i18n:formatMoney(maxRepay, 0, true, false))
    NumericInputDialog.show(self.onPartialAmountEntered, self,
        tostring(maxRepayDisplay), prompt, nil, math.max(12, string.len(tostring(maxRepayDisplay))), g_i18n:getText("button_ok"),
        minValueDisplay, maxRepayDisplay)
end

---Handles amount input for partial early repayment (non-revolving only)
-- @param string text The entered principal amount
-- @param boolean confirmed True if user confirmed
function BankFrame:onPartialAmountEntered(text, confirmed)
    if not confirmed or self.selectedLoan == nil then return end

    local loan    = self.selectedLoan
    local manager = self:getManager()
    if manager == nil then return end

    local repayAmount = BankCredit.fromDisplayMoney(tonumber(text) or 0)
    if repayAmount <= 0 then return end
    if Loan.isPayoffAmount(loan.restAmount, repayAmount) then
        repayAmount = loan.restAmount
    else
        local minRepay = math.floor(loan.amount * 0.10)
        if repayAmount < minRepay then
            InfoDialog.show(string.format(g_i18n:getText("bank_error_partialRepayMin"),
                g_i18n:formatMoney(minRepay, 0, true, false)))
            return
        end
    end

    local bankSettings = g_currentMission ~= nil and g_currentMission.bankSettings or nil
    local penaltyPct = (bankSettings and bankSettings.earlyRepaymentPenalty) or 0
    local penalty    = repayAmount * (penaltyPct / 100)
    local total      = repayAmount + penalty

    local farmId = self:getCurrentFarmId()
    local farm   = g_farmManager:getFarmById(farmId)
    if farm == nil or farm.money < total then
        InfoDialog.show(g_i18n:getText("bank_error_insufficientFunds"))
        return
    end

    self.pendingRepayAmount = repayAmount

    local confirmText = string.format(g_i18n:getText("bank_confirm_earlyRepay"),
        g_i18n:formatMoney(repayAmount, 0, true, false),
        g_i18n:formatMoney(penalty,     0, true, false),
        g_i18n:formatMoney(total,       0, true, false))

    YesNoDialog.show(self.onEarlyRepayConfirmed, self, confirmText)
end

---Handles early repay confirmation result (non-revolving only)
-- @param boolean confirmed True if user confirmed
function BankFrame:onEarlyRepayConfirmed(confirmed)
    if not confirmed or self.selectedLoan == nil then return end

    local loan    = self.selectedLoan
    local manager = self:getManager()
    if manager == nil then return end

    local amount = self.pendingRepayAmount or loan.restAmount
    self.pendingRepayAmount = nil

    if g_currentMission:getIsServer() then
        manager.loanService:earlyRepayment(loan, amount)
    elseif g_client ~= nil and g_client.getServerConnection ~= nil then
        g_client:getServerConnection():sendEvent(LoanRepayEvent.new(loan.id, amount))
    end

    self:refreshDashboard()
    self:refreshList()
end

---Handles revolving repayment amount input result
-- @param string text The entered amount text
-- @param boolean confirmed True if user confirmed
function BankFrame:onRevolvingRepayAmountEntered(text, confirmed)
    if not confirmed or self.selectedLoan == nil then return end

    local loan    = self.selectedLoan
    local manager = self:getManager()
    if manager == nil then return end

    local amount = BankCredit.fromDisplayMoney(tonumber(text))
    if amount == nil or amount <= 0 then return end

    if amount > loan.restAmount then
        amount = loan.restAmount
    end
    if Loan.isPayoffAmount(loan.restAmount, amount) then
        amount = loan.restAmount
    end

    local farmId = self:getCurrentFarmId()
    local farm   = g_farmManager:getFarmById(farmId)
    if farm == nil or farm.money < amount then
        InfoDialog.show(g_i18n:getText("bank_error_insufficientFunds"))
        return
    end

    if g_currentMission:getIsServer() then
        manager.loanService:repayRevolving(loan, amount)
    elseif g_client ~= nil and g_client.getServerConnection ~= nil then
        g_client:getServerConnection():sendEvent(LoanRepayEvent.new(loan.id, amount))
    end

    self:refreshDashboard()
    self:refreshList()
end

---Shows draw amount input dialog for revolving credit line
function BankFrame:onClickDraw()
    if self.selectedLoan == nil then return end
    if self.selectedLoan.paidOff then return end
    if self.selectedLoan.type ~= Loan.TYPE.REVOLVING then return end

    local loan      = self.selectedLoan
    local maxDraw   = loan.amount - loan.restAmount
    if maxDraw <= 0 then
        InfoDialog.show(g_i18n:getText("bank_wizard_warn_limitExceeded"))
        return
    end

    local title = string.format(g_i18n:getText("bank_confirm_draw"),
        g_i18n:formatMoney(maxDraw, 0, true, false))

    local maxDrawDisplay = BankCredit.toDisplayMoney(maxDraw)
    NumericInputDialog.show(self.onDrawAmountEntered, self, tostring(maxDrawDisplay), title, nil,
        math.max(10, string.len(tostring(maxDrawDisplay))), g_i18n:getText("button_ok"), nil, maxDrawDisplay)
end

---Handles draw amount input result
-- @param string text The entered amount text
-- @param boolean confirmed True if user confirmed
function BankFrame:onDrawAmountEntered(text, confirmed)
    if not confirmed or self.selectedLoan == nil then return end

    local loan    = self.selectedLoan
    local manager = self:getManager()
    if manager == nil then return end

    local amount = BankCredit.fromDisplayMoney(tonumber(text))
    if amount == nil or amount <= 0 then return end

    local maxDraw = loan.amount - loan.restAmount
    if amount > maxDraw then
        amount = maxDraw
    end
    if g_currentMission:getIsServer() then
        manager.loanService:drawRevolving(loan, amount)
    elseif g_client ~= nil and g_client.getServerConnection ~= nil then
        g_client:getServerConnection():sendEvent(RevolvingDrawEvent.new(loan.id, amount, false))
    end

    self:refreshDashboard()
    self:refreshList()
end

---Shows close line confirmation dialog for revolving
function BankFrame:onClickCloseLine()
    if self.selectedLoan == nil then return end
    if self.selectedLoan.type ~= Loan.TYPE.REVOLVING then return end
    if self.selectedLoan.restAmount > 0 then return end
    if self.selectedLoan.paidOff then return end

    local text = g_i18n:getText("bank_confirm_closeLine")
    YesNoDialog.show(self.onCloseLineConfirmed, self, text)
end

---Handles close line confirmation result
-- @param boolean confirmed True if user confirmed
function BankFrame:onCloseLineConfirmed(confirmed)
    if not confirmed or self.selectedLoan == nil then return end

    local loan    = self.selectedLoan
    local manager = self:getManager()
    if manager == nil then return end

    if g_currentMission:getIsServer() then
        manager.loanService:closeRevolving(loan)
    elseif g_client ~= nil and g_client.getServerConnection ~= nil then
        g_client:getServerConnection():sendEvent(RevolvingDrawEvent.new(loan.id, 0, true))
    end

    self:refreshDashboard()
    self:refreshList()
end

---Copies frame attributes from source element
-- @param table src Source element
function BankFrame:copyAttributes(src)
    BankFrame:superClass().copyAttributes(self, src)
    self.i18n          = src.i18n
    self.messageCenter = src.messageCenter
end

---Deletes frame and cleans up references
function BankFrame:delete()
    self.loansList          = nil
    self.selectedLoan       = nil
    self.menuButtonInfoByTab = nil
    BankFrame:superClass().delete(self)
end
