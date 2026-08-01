-- Copyright © 2026 Squallqt. All rights reserved.
---Compact information dialog showing bank health indicators.
BankHealthDialog = {}
local BankHealthDialog_mt = Class(BankHealthDialog, MessageDialog)

BankHealthDialog.COLOR_GOOD       = {0.40, 0.85, 0.40, 1}
BankHealthDialog.COLOR_WARN       = {1.00, 0.66, 0.00, 1}
BankHealthDialog.COLOR_DANGER     = {1.00, 0.30, 0.30, 1}
BankHealthDialog.PORTFOLIO_COLOR  = {
    low      = {0.40, 0.85, 0.40, 1},
    moderate = {1.00, 0.82, 0.00, 1},
    high     = {1.00, 0.55, 0.10, 1},
    critical = {1.00, 0.30, 0.30, 1},
}

---Creates a new BankHealthDialog instance
-- @param table target Parent target element
-- @param table? customMt Optional custom metatable
-- @return BankHealthDialog instance
function BankHealthDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or BankHealthDialog_mt)
    return self
end

---Called when dialog opens; applies bullet labels, resizes title separator, refreshes values
function BankHealthDialog:onOpen()
    BankHealthDialog:superClass().onOpen(self)
    self:applyBulletLabels()
    self:resizeTitleSep()
    self:refresh()
end

---Closes the dialog (back button)
function BankHealthDialog:onClickBack()
    self:close()
end

BankHealthDialog.DATA_LABELS = {
    {id = "btnEquity",      key = "bank_dash_equity"},
    {id = "btnCapacity",    key = "bank_dash_capacity"},
    {id = "btnOutstanding", key = "bank_dash_outstanding_label"},
    {id = "btnUtilization", key = "bank_dash_utilization"},
    {id = "btnLeverage",    key = "bank_dash_leverage"},
    {id = "btnCoverage",    key = "bank_dash_coverage"},
    {id = "btnProvision",   key = "bank_dash_provision"},
}

---Prefixes data-label buttons with a middle-dot bullet for visual alignment
function BankHealthDialog:applyBulletLabels()
    for _, entry in ipairs(BankHealthDialog.DATA_LABELS) do
        local btn = self[entry.id]
        if btn ~= nil then
            btn:setText("\xC2\xB7  " .. g_i18n:getText(entry.key))
        end
    end
end

---Resizes title separator to match title text width
function BankHealthDialog:resizeTitleSep()
    if self.titleSep == nil or self.mainTitleText == nil then return end

    if self._titleSepHeight == nil then
        self._titleSepHeight = self.titleSep.absSize[2]
    end
    if self._titleSepBaseWidth == nil then
        self._titleSepBaseWidth = self.titleSep.absSize[1]
    end

    local text = self.mainTitleText.text or ""
    local textWidth = getTextWidth(self.mainTitleText.textSize, text)
    local padding = 20 * 2 * g_pixelSizeScaledX
    local newWidth = math.max(self._titleSepBaseWidth, textWidth + padding)

    self.titleSep:setSize(newWidth, self._titleSepHeight)
    if self.titleSep.parent ~= nil and self.titleSep.parent.invalidateLayout ~= nil then
        self.titleSep.parent:invalidateLayout()
    end
end

-- unsetFocus leaves currentFocusData.focusElement unchanged, so move focus
-- before Gui caches and restores it around InfoDialog.

---Opens an InfoDialog with localized text and resets hover/press state on all info buttons
-- @param string textKey l10n key to display
function BankHealthDialog:showInfo(textKey)
    if self.btnClose ~= nil then
        FocusManager:setFocus(self.btnClose)
    end

    local buttons = {
        self.btnBalance, self.btnRisk, self.btnPortfolio,
        self.btnEquity, self.btnCapacity, self.btnOutstanding, self.btnUtilization,
        self.btnLeverage, self.btnCoverage, self.btnProvision
    }
    for _, btn in ipairs(buttons) do
        if btn ~= nil then
            btn.inputEntered = false
            btn.inputDown = false
        end
    end

    InfoDialog.show(g_i18n:getText(textKey))
end

---Opens the balance information dialog
function BankHealthDialog:onClickInfoBalance()
    self:showInfo("bank_info_balance")
end

---Opens the risk information dialog
function BankHealthDialog:onClickInfoRisk()
    self:showInfo("bank_info_risk")
end

---Opens the portfolio information dialog
function BankHealthDialog:onClickInfoPortfolio()
    self:showInfo("bank_info_portfolio")
end

---Opens the equity information dialog
function BankHealthDialog:onClickInfoEquity()
    self:showInfo("bank_info_equity")
end

---Opens the capacity information dialog
function BankHealthDialog:onClickInfoCapacity()
    self:showInfo("bank_info_capacity")
end

---Opens the outstanding credit information dialog
function BankHealthDialog:onClickInfoOutstanding()
    self:showInfo("bank_info_outstanding")
end

---Opens the utilization information dialog
function BankHealthDialog:onClickInfoUtilization()
    self:showInfo("bank_info_utilization")
end

---Opens the leverage information dialog
function BankHealthDialog:onClickInfoLeverage()
    self:showInfo("bank_info_leverage")
end

---Opens the coverage information dialog
function BankHealthDialog:onClickInfoCoverage()
    self:showInfo("bank_info_coverage")
end

---Opens the provision information dialog
function BankHealthDialog:onClickInfoProvision()
    self:showInfo("bank_info_provision")
end

---Refreshes all bank health indicators (equity, capacity, utilization, leverage, coverage, provision, portfolio)
function BankHealthDialog:refresh()
    local manager = g_currentMission.bankManager
    if manager == nil then return end

    local ledger      = manager.ledger
    local bankService = manager.bankService

    if self.healthEquityValue then
        self.healthEquityValue:setText(g_i18n:formatMoney(ledger.equity, 0, true, false))
    end

    if self.healthCapacityValue then
        self.healthCapacityValue:setText(g_i18n:formatMoney(bankService:getTotalCapacity(), 0, true, false))
    end

    if self.healthOutstandingValue then
        self.healthOutstandingValue:setText(g_i18n:formatMoney(ledger.totalOutstanding, 0, true, false))
    end

    if self.healthUtilizationValue then
        local capacity = bankService:getTotalCapacity()
        local pct = 0
        if capacity > 0 then
            pct = ledger.totalOutstanding / capacity * 100
        end
        self.healthUtilizationValue:setText(string.format("%d%%", math.floor(pct + 0.5)))
        local color
        if pct < 50 then
            color = BankHealthDialog.COLOR_GOOD
        elseif pct < 80 then
            color = BankHealthDialog.COLOR_WARN
        else
            color = BankHealthDialog.COLOR_DANGER
        end
        self.healthUtilizationValue:setTextColor(unpack(color))
    end

    if self.healthLeverageValue then
        self.healthLeverageValue:setText(string.format("%dx", bankService:getLeverageRatio()))
    end

    if self.healthCoverageValue then
        local ratio = bankService:getCoverageRatio()
        local text, color
        if ratio == math.huge or ratio > 50 then
            text  = ">50x"
            color = BankHealthDialog.COLOR_GOOD
        else
            text = string.format("%.0fx", ratio)
            if ratio > 1.5 then
                color = BankHealthDialog.COLOR_GOOD
            elseif ratio >= 1.0 then
                color = BankHealthDialog.COLOR_WARN
            else
                color = BankHealthDialog.COLOR_DANGER
            end
        end
        self.healthCoverageValue:setText(text)
        self.healthCoverageValue:setTextColor(unpack(color))
    end

    if self.healthProvisionValue then
        self.healthProvisionValue:setText(g_i18n:formatMoney(bankService:getLossProvision(), 0, true, false))
    end

    local health = bankService:getPortfolioHealth()
    local lowVal  = math.floor((health.low or 0) + 0.5)
    local modVal  = math.floor((health.moderate or 0) + 0.5)
    local highVal = math.floor((health.high or 0) + 0.5)
    local critVal = math.floor((health.critical or 0) + 0.5)

    -- Weighted health score: low=100, moderate=60, high=20, critical=0.
    local score = math.floor((lowVal * 100 + modVal * 60 + highVal * 20) / 100 + 0.5)

    -- Bar fill uses (100 - score)% of the bar width: full = critical, empty = safe
    local bg = self.healthPortfolioBarBg
    if bg ~= nil then
        local fill = self.healthPortfolioBarFill
        if fill ~= nil then
            if fill._baseHeight == nil then fill._baseHeight = fill.absSize[2] end
            fill:setSize(math.max(0, bg.absSize[1] * math.min(100, 100 - score) / 100), fill._baseHeight)
        end
    end

    local statusKey, statusColor
    if score >= 80 then
        statusKey   = "bank_risk_low"
        statusColor = BankHealthDialog.PORTFOLIO_COLOR.low
    elseif score >= 50 then
        statusKey   = "bank_risk_moderate"
        statusColor = BankHealthDialog.PORTFOLIO_COLOR.moderate
    elseif score >= 20 then
        statusKey   = "bank_risk_high"
        statusColor = BankHealthDialog.PORTFOLIO_COLOR.high
    else
        statusKey   = "bank_risk_critical"
        statusColor = BankHealthDialog.PORTFOLIO_COLOR.critical
    end

    if self.healthPortfolioStatus ~= nil then
        self.healthPortfolioStatus:setText(g_i18n:getText(statusKey))
        self.healthPortfolioStatus:setTextColor(unpack(statusColor))
    end
end
