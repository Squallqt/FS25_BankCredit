-- Copyright © 2026 Squallqt. All rights reserved.
---Annual report dialog showing yearly financial summary.
AnnualReportDialog = {}
local AnnualReportDialog_mt = Class(AnnualReportDialog, MessageDialog)

---Creates a new AnnualReportDialog instance
-- @param table target Parent target element
-- @param table? customMt Optional custom metatable
-- @return AnnualReportDialog instance
function AnnualReportDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or AnnualReportDialog_mt)
    self.years     = {}
    self.yearIndex = 0
    return self
end

---Called when dialog opens; resizes title separator, loads available years, refreshes values
function AnnualReportDialog:onOpen()
    AnnualReportDialog:superClass().onOpen(self)
    self:resizeTitleSep()
    self:loadYears()
    self:refresh()
end

---Closes the dialog (back button)
function AnnualReportDialog:onClickBack()
    self:close()
end

---Resolves the local player's farm id, falling back to farmManager lookup
-- @return integer Farm id, or -1 if unresolved
function AnnualReportDialog:getCurrentFarmId()
    if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
        return g_localPlayer.farmId
    end
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if farm then return farm.farmId end
    return -1
end

---Loads available report years for the current farm and clamps yearIndex to a valid entry
function AnnualReportDialog:loadYears()
    local manager = g_currentMission.bankManager
    if manager == nil or manager.annualReport == nil then
        self.years = {}
        self.yearIndex = 0
        return
    end

    local farmId = self:getCurrentFarmId()
    self.years = manager.annualReport:getYears(farmId)

    if #self.years == 0 then
        self.yearIndex = 0
        return
    end

    if self.yearIndex <= 0 or self.yearIndex > #self.years then
        self.yearIndex = #self.years
    end
end

---Resizes title separator to match title text width
function AnnualReportDialog:resizeTitleSep()
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

---Refreshes all displayed report values for the selected year and updates prev/next button states
function AnnualReportDialog:refresh()
    if self.btnPrevYear then self.btnPrevYear:setDisabled(self.yearIndex <= 1) end
    if self.btnNextYear  then self.btnNextYear:setDisabled(self.yearIndex >= #self.years) end

    if #self.years == 0 then return end

    local manager = g_currentMission.bankManager
    if manager == nil then return end

    local farmId = self:getCurrentFarmId()
    local year   = self.years[self.yearIndex]
    local report = manager.annualReport:getReport(farmId, year)
    if report == nil then return end

    local farm     = g_farmManager:getFarmById(farmId)
    local farmName = farm and farm.name or tostring(farmId)

    if self.mainTitleText then
        self.mainTitleText:setText(string.format(g_i18n:getText("bank_report_title"), year, farmName))
        self:resizeTitleSep()
    end

    if self.reportInterestValue then
        self.reportInterestValue:setText(g_i18n:formatMoney(report.interestPaid, 0, true, false))
    end
    if self.reportPrincipalValue then
        self.reportPrincipalValue:setText(g_i18n:formatMoney(report.principalPaid, 0, true, false))
    end
    if self.reportAvgMonthlyValue then
        local total = report.interestPaid + report.principalPaid
        self.reportAvgMonthlyValue:setText(g_i18n:formatMoney(total / 12, 0, true, false))
    end
    if self.reportTotalValue then
        self.reportTotalValue:setText(g_i18n:formatMoney(report.interestPaid + report.principalPaid, 0, true, false))
    end

    if self.reportLoansOpenedValue then
        self.reportLoansOpenedValue:setText(tostring(report.loansOpened))
    end
    if self.reportLoansClosedValue then
        self.reportLoansClosedValue:setText(tostring(report.loansClosed))
    end

    if self.reportLoansActiveValue then
        local activeCount = 0
        local allLoans = manager.repository:getByFarm(farmId)
        for _, loan in ipairs(allLoans) do
            if not loan.paidOff then
                activeCount = activeCount + 1
            end
        end
        self.reportLoansActiveValue:setText(tostring(activeCount))
    end

    if self.reportOutstandingValue then
        local farmOutstanding = manager.bankService:getFarmExposure(farmId, manager.repository)
        self.reportOutstandingValue:setText(g_i18n:formatMoney(farmOutstanding, 0, true, false))
    end

end

---Navigates to the previous year's report
function AnnualReportDialog:onClickPrevYear()
    if self.yearIndex > 1 then
        self.yearIndex = self.yearIndex - 1
        self:refresh()
    end
end

---Navigates to the next year's report
function AnnualReportDialog:onClickNextYear()
    if self.yearIndex < #self.years then
        self.yearIndex = self.yearIndex + 1
        self:refresh()
    end
end
