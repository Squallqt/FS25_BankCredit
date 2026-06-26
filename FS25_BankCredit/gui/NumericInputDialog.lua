-- Copyright © 2026 Squallqt. All rights reserved.
NumericInputDialog = {}
local NumericInputDialog_mt = Class(NumericInputDialog, MessageDialog)

NumericInputDialog.CONTROLS = {
    "promptText",
    "inputField",
    "btnOk",
}

function NumericInputDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or NumericInputDialog_mt)
    self.callback        = nil
    self.callbackTarget  = nil
    self.minValue        = nil
    self.maxValue        = nil
    return self
end

function NumericInputDialog:onLoad()
    NumericInputDialog:superClass().onLoad(self)
    self:registerControls(NumericInputDialog.CONTROLS)
end

function NumericInputDialog:onOpen()
    NumericInputDialog:superClass().onOpen(self)
    self.callback       = self.pendingCallback
    self.callbackTarget = self.pendingCallbackTarget
    self.minValue       = self.pendingMinValue
    self.maxValue       = self.pendingMaxValue

    if self.promptText then
        self.promptText:setText(self.pendingPrompt or "")
    end
    if self.inputField then
        if self.pendingMaxChars ~= nil then
            self.inputField.maxCharacters = self.pendingMaxChars
        end
        self.inputField:setText(self.pendingDefaultText or "")
    end
    if self.btnOk then
        self.btnOk:setText(self.pendingConfirmText or g_i18n:getText("button_ok"))
    end
end

---TextInput live filter: strip non-numeric characters and clamp to max
-- @param table element TextInput element
-- @param string text Current text content
function NumericInputDialog:onInputTextChanged(element, text)
    local filtered = string.gsub(text or "", "[^0-9]", "")
    local value = tonumber(filtered)
    if value ~= nil and self.maxValue ~= nil and value > self.maxValue then
        filtered = tostring(self.maxValue)
    end
    if filtered ~= text then element:setText(filtered) end
end

function NumericInputDialog:onClickOk()
    local raw = math.floor(tonumber(self.inputField ~= nil and self.inputField:getText() or "") or 0)
    if raw > 0 then
        if self.maxValue ~= nil and raw > self.maxValue then raw = self.maxValue end
        if self.minValue ~= nil and raw < self.minValue then raw = self.minValue end
    end
    local cb  = self.callback
    local tgt = self.callbackTarget
    self:close()
    if cb ~= nil then cb(tgt, tostring(raw), true) end
end

function NumericInputDialog:onClickBack()
    local cb  = self.callback
    local tgt = self.callbackTarget
    self:close()
    if cb ~= nil then cb(tgt, "", false) end
end

-- Drop-in for TextInputDialog.show — same parameter order.
-- @param function callback       Called as callback(callbackTarget, text, confirmed)
-- @param table   callbackTarget  Passed as first arg to callback
-- @param string  defaultText     Pre-filled value
-- @param string  promptText      Label displayed above the input
-- @param any     _               Unused (placeholder, mirrors TextInputDialog.show signature)
-- @param integer maxChars        Max character count
-- @param string  confirmBtnText  Confirm button label
function NumericInputDialog.show(callback, callbackTarget, defaultText, promptText, _, maxChars, confirmBtnText, minValue, maxValue)
    local gui = g_gui.guis["NumericInputDialog"]
    if gui == nil then return end
    local ctrl                 = gui.target
    ctrl.pendingCallback       = callback
    ctrl.pendingCallbackTarget = callbackTarget
    ctrl.pendingDefaultText    = tostring(defaultText or "")
    ctrl.pendingPrompt         = promptText or ""
    ctrl.pendingMaxChars       = maxChars
    ctrl.pendingConfirmText    = confirmBtnText
    ctrl.pendingMinValue       = minValue
    ctrl.pendingMaxValue       = maxValue
    g_gui:showDialog("NumericInputDialog")
end
