-- Copyright © 2026 Squallqt. All rights reserved.
---Bootstraps source loading, mission lifecycle hooks, and finance statistics.
local modDirectory = g_currentModDirectory
local modName = g_currentModName

source(modDirectory .. "scripts/Loan.lua")
source(modDirectory .. "scripts/BankLedger.lua")
source(modDirectory .. "scripts/IncomeTracker.lua")
source(modDirectory .. "scripts/InterestRateModel.lua")
source(modDirectory .. "scripts/CreditService.lua")
source(modDirectory .. "scripts/BankService.lua")
source(modDirectory .. "scripts/AnnualReport.lua")
source(modDirectory .. "scripts/LoanService.lua")
source(modDirectory .. "scripts/BankRepository.lua")
source(modDirectory .. "scripts/BankSettings.lua")
source(modDirectory .. "events/LoanCreateEvent.lua")
source(modDirectory .. "events/LoanPaymentEvent.lua")
source(modDirectory .. "events/BankSyncEvent.lua")
source(modDirectory .. "events/AnnualReportSyncEvent.lua")
source(modDirectory .. "events/BankSettingsEvent.lua")
source(modDirectory .. "events/LoanRequestEvent.lua")
source(modDirectory .. "events/LoanRepayEvent.lua")
source(modDirectory .. "events/RevolvingDrawEvent.lua")
source(modDirectory .. "events/VanillaLoanClearedEvent.lua")
source(modDirectory .. "events/VanillaLoanSyncEvent.lua")
source(modDirectory .. "events/BankPeriodSyncEvent.lua")
source(modDirectory .. "gui/BankFrame.lua")
source(modDirectory .. "gui/AnnualReportDialog.lua")
source(modDirectory .. "gui/BankHealthDialog.lua")
source(modDirectory .. "gui/LoanDetailDialog.lua")
source(modDirectory .. "gui/TakeLoanWizard.lua")
source(modDirectory .. "gui/NumericInputDialog.lua")

BankCredit = {}
BankCredit.modDirectory = modDirectory
BankCredit.modName = modName
BankCredit.manager = nil

local IN_GAME_MENU_PAGE_FIELD = "pageBankCredit"
local IN_GAME_MENU_FRAME_NAME = "BankFrame"
local IN_GAME_MENU_ICON_SLICE_ID = "bankCredit.menuIcon"

---Register finance stat entry
-- @param string statName Name of stat to register
local function registerFinanceStat(statName)
    if FinanceStats.statNameToIndex[statName] == nil then
        table.insert(FinanceStats.statNames, statName)
        FinanceStats.statNameToIndex[statName] = #FinanceStats.statNames
    end
end

registerFinanceStat("bankLoanInterest")
registerFinanceStat("bankLoanPrincipal")

---Load shared GUI assets once before creating bank screens
local function loadGuiAssets()
    if not BankCredit._guiProfilesLoaded then
        g_gui:loadProfiles(BankCredit.modDirectory .. "gui/guiProfiles.xml")
        BankCredit._guiProfilesLoaded = true
    end

    if g_overlayManager ~= nil
        and (g_overlayManager.textureConfigs == nil or g_overlayManager.textureConfigs.bankCredit == nil) then
        g_overlayManager:addTextureConfigFile(BankCredit.modDirectory .. "images/menuIcon.xml", "bankCredit")
    end
end

---Load mission lifecycle initiation
local function loadedMission()
    MoneyType.LOAN_INTEREST  = MoneyType.register("bankLoanInterest",  "bank_label_interest")
    MoneyType.LOAN_PRINCIPAL = MoneyType.register("bankLoanPrincipal", "bank_label_principal")

    local ledger        = BankLedger.new()
    g_currentMission.bankSettings = BankSettings.load()
    local rateModel     = InterestRateModel.new(g_currentMission.bankSettings.baseInterestRate)
    local incomeTracker = IncomeTracker.new()
    local repository    = BankRepository.new()
    local bankService   = BankService.new(ledger)
    local creditService = CreditService.new(incomeTracker)
    local annualReport  = AnnualReport.new()
    local loanService   = LoanService.new(bankService, creditService, repository, rateModel, annualReport)

    BankCredit.manager = {
        ledger        = ledger,
        rateModel     = rateModel,
        incomeTracker = incomeTracker,
        repository    = repository,
        bankService   = bankService,
        creditService = creditService,
        loanService   = loanService,
        annualReport  = annualReport,
    }

    g_currentMission.bankManager = BankCredit.manager

    local savePath = g_currentMission.missionInfo.savegameDirectory
    if savePath == nil then
        savePath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end
    savePath = savePath .. "/"

    repository:loadFromXML(savePath, ledger, g_currentMission.bankSettings, incomeTracker, rateModel, annualReport)
    incomeTracker:initialize()
    bankService:initializeLedger(g_currentMission.bankSettings.initialCapital)

    BankSettings:applySettings(g_currentMission.bankSettings, false)

    ---Processes monthly loan collection and market rate changes
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, function()
        if g_currentMission:getIsServer() then
            loanService:collectAll()

            local settings = g_currentMission.bankSettings
            if settings.dynamicRate then
                rateModel:update(g_currentMission.environment.currentYear)
            end

            g_server:broadcastEvent(BankPeriodSyncEvent.new())
        end
    end, BankCredit)

    loadGuiAssets()
    BankSettings:injectMenu()

    if g_currentMission:getIsServer() then
        ---Clears a player's vanilla loan after a farm change
        -- @param table player Player instance
        g_messageCenter:subscribe(MessageType.PLAYER_FARM_CHANGED, function(player)
            if player == nil or not LoanService.isValidFarmId(player.farmId) then return end
            BankCredit.clearVanillaLoan(g_farmManager:getFarmById(player.farmId))
        end, BankCredit)

        -- Defer the local-host clear until its farm is available.
        BankCredit.hostVanillaLoanCheck = {
            elapsed = 0,
            ---Checks whether the local host has joined a valid farm
            -- @param table self Mod event listener
            -- @param float dt Elapsed time in milliseconds
            update = function(self, dt)
                self.elapsed = self.elapsed + dt
                local hostFarmId = g_currentMission:getFarmId()
                if LoanService.isValidFarmId(hostFarmId) then
                    BankCredit.clearVanillaLoan(g_farmManager:getFarmById(hostFarmId))
                    removeModEventListener(self)
                    BankCredit.hostVanillaLoanCheck = nil
                elseif self.elapsed > 60000 then
                    removeModEventListener(self)
                    BankCredit.hostVanillaLoanCheck = nil
                end
            end,
        }
        addModEventListener(BankCredit.hostVanillaLoanCheck)
    end
end

---Apply a one-time tab list alignment reset before native tab rebuilds
local function applyTabListAlignmentFix()
    if BankCredit._tabListFixApplied then
        return
    end

    if InGameMenu == nil or InGameMenu.rebuildTabList == nil then
        return
    end

    ---Resets the native tab alignment before rebuilding the tab list
    -- @param table self InGameMenu instance
    InGameMenu.rebuildTabList = Utils.prependedFunction(InGameMenu.rebuildTabList, function(self)
        if self.pagingTabList ~= nil then
            self.pagingTabList.listItemAlignmentOffset = 0
        end
    end)

    BankCredit._tabListFixApplied = true
end

---Clears a lingering vanilla loan on the farm and notifies the owner.
-- Idempotent: a second call is a no-op because farm.loan is reset to 0.
-- Uses MoneyType.LOAN_PRINCIPAL so the deduction appears as a readable line
-- in the Finance tab (registered at mission load).
-- @param table farm Farm instance
-- @param table? targetConnection Optional direct popup connection
function BankCredit.clearVanillaLoan(farm, targetConnection)
    if farm == nil then return end
    if not LoanService.isValidFarmId(farm.farmId) then return end
    if farm.loan == nil or farm.loan <= 0 then return end

    local amount = farm.loan
    local farmId = farm.farmId
    farm.loan = 0
    g_currentMission:addMoney(-amount, farmId, MoneyType.LOAN_PRINCIPAL, true, true)

    -- Keep every client's Finance tab aligned with the server-side clear.
    if g_server ~= nil then
        g_server:broadcastEvent(VanillaLoanSyncEvent.new(farmId), false)
    end

    if targetConnection ~= nil then
        targetConnection:sendEvent(VanillaLoanClearedEvent.new(farmId, amount))
        return
    end

    -- Notify the listen-server host locally; remote players are mapped below.
    local hostFarmId = g_currentMission:getFarmId()
    if LoanService.isValidFarmId(hostFarmId) and farmId == hostFarmId then
        BankCredit.showVanillaLoanPopup(amount)
        return
    end

    for conn, p in pairs(g_currentMission.connectionsToPlayer) do
        if p.farmId == farmId then
            conn:sendEvent(VanillaLoanClearedEvent.new(farmId, amount))
            return
        end
    end
end

---Shows the vanilla-loan clearing popup
-- @param number amount Cleared loan amount
function BankCredit.showVanillaLoanPopup(amount)
    local popup = {
        delay = 2000,
        amount = amount,
        ---Displays the popup when the HUD is available
        -- @param table self Mod event listener
        -- @param float dt Elapsed time in milliseconds
        update = function(self, dt)
            if g_gui:getIsGuiVisible() or g_currentMission.hud == nil then
                self.delay = 500
                return
            end
            self.delay = self.delay - dt
            if self.delay < 0 then
                InfoDialog.show(string.format(g_i18n:getText("bank_vanilla_loan_cleared"), g_i18n:formatMoney(self.amount, 0, true, false)))
                removeModEventListener(self)
            end
        end,
    }
    addModEventListener(popup)
end

---Check whether the bank InGameMenu page should be enabled
-- @return boolean isEnabled True when the page is safe to show
local function getIsBankPageEnabled()
    return true
end

---Find the desired InGameMenu position before Statistics
-- @param table inGameMenu InGameMenu instance
-- @return integer position Target page position
local function getBankPagePosition(inGameMenu)
    local position = 1

    if inGameMenu.pageFrames ~= nil then
        position = #inGameMenu.pageFrames + 1

        for i, page in ipairs(inGameMenu.pageFrames) do
            if page == inGameMenu.pageStatistics then
                return i
            end
        end
    end

    return position
end

---Add bank frame to InGameMenu using the same controller for pageFrames and PagingElement
-- @param table inGameMenu InGameMenu instance
-- @return table|nil frame Registered frame, or nil on failure
function BankCredit.addInGameMenuPage(inGameMenu)
    inGameMenu = inGameMenu or g_inGameMenu or g_gui.screenControllers[InGameMenu]

    if inGameMenu == nil then
        Logging.warning("[BankCredit] Cannot add InGameMenu page: g_inGameMenu is nil")
        return nil
    end

    if inGameMenu.pageBankCredit ~= nil then
        BankCredit.frame = inGameMenu.pageBankCredit
        return inGameMenu.pageBankCredit
    end

    if inGameMenu.registerPage == nil or inGameMenu.addPageTab == nil then
        Logging.warning("[BankCredit] Cannot add InGameMenu page: TabbedMenu registration API is unavailable")
        return nil
    end

    if inGameMenu.pagingElement == nil then
        Logging.warning("[BankCredit] Cannot add InGameMenu page: pagingElement is nil")
        return nil
    end

    if inGameMenu.pagingElement.addPage == nil or inGameMenu.pagingElement.removePageByElement == nil then
        Logging.warning("[BankCredit] Cannot add InGameMenu page: PagingElement page API is unavailable")
        return nil
    end

    local frameRefPath = BankCredit.modDirectory .. "gui/BankFrameRef.xml"
    local xmlFile = loadXMLFile("BankFrameRefXML", frameRefPath)
    if xmlFile == nil or xmlFile == 0 then
        Logging.error("[BankCredit] Failed to load FrameReference XML: %s", tostring(frameRefPath))
        return nil
    end

    applyTabListAlignmentFix()

    inGameMenu.controlIDs[IN_GAME_MENU_PAGE_FIELD] = nil
    g_gui:loadGuiRec(xmlFile, "FrameReferences", inGameMenu.pagingElement, inGameMenu)
    inGameMenu:exposeControlsAsFields(IN_GAME_MENU_PAGE_FIELD)
    inGameMenu.pagingElement:updatePageMapping()
    delete(xmlFile)

    local frame = g_gui:resolveFrameReference(inGameMenu[IN_GAME_MENU_PAGE_FIELD])
    if frame == nil or frame.initialize == nil then
        Logging.error("[BankCredit] Failed to resolve InGameMenu frame reference '%s'", IN_GAME_MENU_PAGE_FIELD)
        return nil
    end

    if frame.elements == nil or frame.elements[1] == nil then
        Logging.warning("[BankCredit] Cannot add InGameMenu page: frame root element is missing")
        return nil
    end

    frame.elements[1].title = g_i18n:getText("bank_menu_title")
    inGameMenu[IN_GAME_MENU_PAGE_FIELD] = frame

    inGameMenu.pagingElement:removePageByElement(frame)

    local _, actualPosition = inGameMenu:registerPage(
        frame,
        getBankPagePosition(inGameMenu),
        getIsBankPageEnabled
    )

    inGameMenu:addPageTab(frame, nil, nil, IN_GAME_MENU_ICON_SLICE_ID)
    inGameMenu.pagingElement:addPage(
        string.upper(IN_GAME_MENU_PAGE_FIELD),
        frame,
        g_i18n:getText("bank_menu_title"),
        actualPosition
    )

    frame:onGuiSetupFinished()
    frame:initialize()
    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()

    if inGameMenu.rebuildTabList ~= nil then
        inGameMenu:rebuildTabList()
    else
        Logging.warning("[BankCredit] InGameMenu page added, but rebuildTabList is unavailable")
    end

    BankCredit.frame = frame
    return frame
end

---Load and register bank GUI when InGameMenu has finished map setup
-- @param table inGameMenu InGameMenu instance
-- @return table|nil frame Registered frame, or nil
function BankCredit.loadInGameMenuGui(inGameMenu)
    if inGameMenu == nil then
        Logging.warning("[BankCredit] Cannot load InGameMenu GUI: inGameMenu is nil")
        return nil
    end

    if inGameMenu.pageBankCredit ~= nil then
        BankCredit.frame = inGameMenu.pageBankCredit
        return inGameMenu.pageBankCredit
    end

    loadGuiAssets()

    local frameTemplate = BankFrame.new(g_i18n, g_messageCenter)
    g_gui:loadGui(BankCredit.modDirectory .. "gui/BankFrame.xml", IN_GAME_MENU_FRAME_NAME, frameTemplate, true)

    local frame = BankCredit.addInGameMenuPage(inGameMenu)
    if frame == nil then
        return nil
    end

    local detailDialog = LoanDetailDialog.new(frame)
    g_gui:loadGui(BankCredit.modDirectory .. "gui/LoanDetailDialog.xml", "LoanDetailDialog", detailDialog)

    local healthDialog = BankHealthDialog.new(frame)
    g_gui:loadGui(BankCredit.modDirectory .. "gui/BankHealthDialog.xml", "BankHealthDialog", healthDialog)

    local reportDialog = AnnualReportDialog.new(frame)
    g_gui:loadGui(BankCredit.modDirectory .. "gui/AnnualReportDialog.xml", "AnnualReportDialog", reportDialog)

    local wizardDialog = TakeLoanWizard.new(frame)
    g_gui:loadGui(BankCredit.modDirectory .. "gui/TakeLoanWizard.xml", "TakeLoanWizard", wizardDialog)

    local numericDialog = NumericInputDialog.new(frame)
    g_gui:loadGui(BankCredit.modDirectory .. "gui/NumericInputDialog.xml", "NumericInputDialog", numericDialog)

    return frame
end

---Save bank state to XML on savegame write
local function onSaveToXMLFile()
    if not g_currentMission:getIsServer() then return end
    if BankCredit.manager == nil then return end

    local savePath = g_currentMission.missionInfo.savegameDirectory
    if savePath == nil then
        savePath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end
    savePath = savePath .. "/"

    local m = BankCredit.manager
    m.repository:saveToXML(savePath, m.ledger, g_currentMission.bankSettings, m.incomeTracker, m.rateModel, m.annualReport)
end

---Send initial bank state to client on connection
-- @param table self Mission instance
-- @param table connection Network connection
-- @param table user User data
-- @param table farm Farm data
local function sendInitialClientState(self, connection, user, farm)
    if g_server == nil then return end
    if connection == nil then
        return
    end
    if BankCredit.manager == nil then
        return
    end
    connection:sendEvent(BankSyncEvent.new())
    connection:sendEvent(BankSettingsEvent.new(g_currentMission.bankSettings, false))

    -- Handle the joining player's vanilla loan while its connection is available.
    local player = g_currentMission.connectionsToPlayer[connection]
    if player ~= nil and LoanService.isValidFarmId(player.farmId) then
        BankCredit.clearVanillaLoan(g_farmManager:getFarmById(player.farmId), connection)
    end
end

---Cleanup bank state on mission end
local function onMissionDelete()
    if BankCredit.hostVanillaLoanCheck ~= nil then
        removeModEventListener(BankCredit.hostVanillaLoanCheck)
        BankCredit.hostVanillaLoanCheck = nil
    end
    if BankCredit.manager then
        if BankCredit.manager.incomeTracker then
            BankCredit.manager.incomeTracker:cleanup()
        end
        BankCredit.manager = nil
    end
    BankCredit.frame = nil
    if g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(BankCredit)
    end
    if g_currentMission ~= nil then
        g_currentMission.bankManager = nil
    end
end

---Initialize BankCredit mod: register lifecycle hooks
local function initBankCredit()
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)
    ---Loads the bank GUI after the in-game menu map setup
    -- @param table inGameMenu InGameMenu instance
    InGameMenu.onLoadMapFinished = Utils.appendedFunction(InGameMenu.onLoadMapFinished, function(inGameMenu)
        BankCredit.loadInGameMenuGui(inGameMenu)
    end)
    FSBaseMission.saveSavegame      = Utils.appendedFunction(FSBaseMission.saveSavegame, onSaveToXMLFile)
    FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, sendInitialClientState)
    BaseMission.delete              = Utils.appendedFunction(BaseMission.delete, onMissionDelete)

    -- Disable vanilla loan UI: BankCredit replaces the native loan system entirely
    ---Disables the native loan controls
    -- @return boolean hasPermission Always false
    InGameMenuStatisticsFrame.hasPlayerLoanPermission = Utils.overwrittenFunction(
        InGameMenuStatisticsFrame.hasPlayerLoanPermission,
        function() return false end
    )

    -- Hide vanilla "loanInterest" line from Finances tab
    local idx = FinanceStats.statNameToIndex["loanInterest"]
    if idx ~= nil then
        table.remove(FinanceStats.statNames, idx)
        FinanceStats.statNameToIndex["loanInterest"] = nil
        for i = idx, #FinanceStats.statNames do
            FinanceStats.statNameToIndex[FinanceStats.statNames[i]] = i
        end
    end
end

initBankCredit()

-- I18N extension: resolve selected mod keys without modEnv across the Finance tab and bank UI.
local BankCreditI18NTexts = {
    ["finance_bankLoanInterest"]  = true,
    ["finance_bankLoanPrincipal"] = true,
    ["bank_label_interest"]       = true,
    ["bank_label_principal"]      = true,
    ["bank_modTitle"]             = true,
    ["bank_revolving_draw"]       = true,
    ["bank_revolving_status_open"]      = true,
    ["bank_revolving_status_available"] = true,
    ["bank_revolving_noDuration"]       = true,
    ["bank_revolving_variablePayment"]  = true,
    ["bank_revolving_estimatedInterest"] = true,
    ["bank_confirm_draw"]         = true,
    ["bank_confirm_closeLine"]    = true,
    ["bank_detail_revolving_limit"]     = true,
    ["bank_detail_revolving_drawn"]     = true,
    ["bank_detail_revolving_available"] = true,
    ["bank_tab_active"]                 = true,
    ["bank_tab_paid"]                   = true,
    ["bank_empty_paid"]                 = true,
    ["bank_report_title"]               = true,
    ["bank_report_interestPaid"]        = true,
    ["bank_report_principalPaid"]       = true,
    ["bank_report_loansOpened"]         = true,
    ["bank_report_loansClosed"]         = true,
    ["bank_report_noData"]              = true,
    ["bank_vanilla_loan_cleared"]       = true,
}

---Resolve selected mod translation keys without modEnv
-- @param table self I18N instance
-- @param function superFunc Original getText function
-- @param string text Translation key
-- @param string? modEnv Mod environment name; nil uses BankCredit for selected keys
-- @return string text Localized text
local function bankCreditGetText(self, superFunc, text, modEnv)
    if modEnv == nil and BankCreditI18NTexts[text] then
        return superFunc(self, text, modName)
    end
    return superFunc(self, text, modEnv)
end

I18N.getText = Utils.overwrittenFunction(I18N.getText, bankCreditGetText)
