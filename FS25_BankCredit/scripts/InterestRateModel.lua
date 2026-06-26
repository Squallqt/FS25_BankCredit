-- Copyright © 2026 Squallqt. All rights reserved.
-- Domain model: bank base interest rate with mean-reversion evolution, risk surcharge, and XML/stream serialization.
InterestRateModel = {}
local InterestRateModel_mt = Class(InterestRateModel)

InterestRateModel.DEFAULT_RATE  = 3.5
InterestRateModel.MIN_RATE      = 1.0
InterestRateModel.MAX_RATE      = 12.0
InterestRateModel.STEP          = 0.25
InterestRateModel.HISTORY_MAX   = 5
InterestRateModel.GRAVITY_BAND  = 1.0  -- deviation beyond which gravity fully kicks in

InterestRateModel.TYPE_SPREAD = {
    [1] = 0.0,   -- ANNUITY
    [2] = 0.75,  -- BULLET
    [3] = 5.0,   -- REVOLVING
}

---Create InterestRateModel instance
-- @param float? initialRate Starting interest rate (defaults to DEFAULT_RATE)
-- @return InterestRateModel instance
function InterestRateModel.new(initialRate)
    local self = setmetatable({}, InterestRateModel_mt)
    self.currentRate = initialRate or InterestRateModel.DEFAULT_RATE
    self.rateHistory = {}
    return self
end

---Advance interest rate by one step using mean-reversion.
-- The further currentRate deviates from baseRate, the stronger the pull back.
-- Called every 3 periods (quarterly) when dynamicRate is enabled.
-- @param integer currentYear Current game year
-- @param float baseRate Admin-configured base rate (anchor for mean-reversion)
function InterestRateModel:update(currentYear, baseRate)
    local anchor = baseRate or InterestRateModel.DEFAULT_RATE
    local deviation = self.currentRate - anchor
    local r = math.random(1, 20)
    local move

    if deviation >= InterestRateModel.GRAVITY_BAND * 1.5 then
        -- Extreme high (dev >= +1.5%): 10% up | 20% stable | 70% down
        if r <= 2 then
            move = 1
        elseif r <= 6 then
            move = 0
        else
            move = -1
        end
    elseif deviation >= InterestRateModel.GRAVITY_BAND then
        -- Too high (+1% <= dev < +1.5%): 20% up | 15% stable | 65% down
        if r <= 4 then
            move = 1
        elseif r <= 7 then
            move = 0
        else
            move = -1
        end
    elseif deviation >= InterestRateModel.GRAVITY_BAND * 0.5 then
        -- Slightly high (+0.5% <= dev < +1%): 25% up | 30% stable | 45% down
        if r <= 5 then
            move = 1
        elseif r <= 11 then
            move = 0
        else
            move = -1
        end
    elseif deviation <= -InterestRateModel.GRAVITY_BAND * 1.5 then
        -- Extreme low (dev <= -1.5%): 70% up | 20% stable | 10% down
        if r <= 14 then
            move = 1
        elseif r <= 18 then
            move = 0
        else
            move = -1
        end
    elseif deviation <= -InterestRateModel.GRAVITY_BAND then
        -- Too low (-1.5% < dev <= -1%): 65% up | 15% stable | 20% down
        if r <= 13 then
            move = 1
        elseif r <= 16 then
            move = 0
        else
            move = -1
        end
    elseif deviation <= -InterestRateModel.GRAVITY_BAND * 0.5 then
        -- Slightly low (-1% < dev <= -0.5%): 45% up | 30% stable | 25% down
        if r <= 9 then
            move = 1
        elseif r <= 15 then
            move = 0
        else
            move = -1
        end
    else
        -- Near anchor (|dev| < 0.5%): 30% up | 40% stable | 30% down
        if r <= 6 then
            move = 1
        elseif r <= 14 then
            move = 0
        else
            move = -1
        end
    end

    local newRate = self.currentRate + move * InterestRateModel.STEP
    newRate = math.max(InterestRateModel.MIN_RATE, math.min(InterestRateModel.MAX_RATE, newRate))
    self.currentRate = math.floor(newRate * 100 + 0.5) / 100

    table.insert(self.rateHistory, { year = currentYear, rate = self.currentRate })
    while #self.rateHistory > InterestRateModel.HISTORY_MAX do
        table.remove(self.rateHistory, 1)
    end
end

---Get current base interest rate
-- @return float Current rate in percent
function InterestRateModel:getRate()
    return self.currentRate
end

---Get direction indicator string based on last history entry vs previous
-- @return string "↑", "→", or "↓"
function InterestRateModel:getDirection()
    if #self.rateHistory < 2 then return "\xe2\x86\x92" end
    local last = self.rateHistory[#self.rateHistory].rate
    local prev = self.rateHistory[#self.rateHistory - 1].rate
    if last > prev then
        return "\xe2\x86\x91"
    elseif last < prev then
        return "\xe2\x86\x93"
    else
        return "\xe2\x86\x92"
    end
end

---Get type spread for a given loan type
-- @param integer loanType Loan.TYPE constant
-- @return float Spread in percent
function InterestRateModel:getTypeSpread(loanType)
    return InterestRateModel.TYPE_SPREAD[loanType] or 0.0
end

---Get effective interest rate for a given borrower risk level and loan type
-- @param integer riskLevel Risk tier (1=low, 2=medium, 3=high, 4=very high)
-- @param integer loanType Loan.TYPE constant
-- @return float Adjusted rate in percent
function InterestRateModel:getRateForRiskAndType(riskLevel, loanType)
    local surcharge = { [1]=0.0, [2]=0.75, [3]=2.0, [4]=5.0 }
    return self.currentRate + (surcharge[riskLevel] or 0.0) + (InterestRateModel.TYPE_SPREAD[loanType] or 0.0)
end

---Serialize interest rate model to XML file
-- @param integer xmlFile XML file handle
-- @param string key XML key path
function InterestRateModel:writeToXML(xmlFile, key)
    setXMLFloat(xmlFile, key .. "#currentRate", self.currentRate)
    for i, entry in ipairs(self.rateHistory) do
        local hKey = string.format("%s.history(%d)", key, i - 1)
        setXMLInt(xmlFile,   hKey .. "#year", entry.year)
        setXMLFloat(xmlFile, hKey .. "#rate", entry.rate)
    end
end

---Deserialize interest rate model from XML file
-- @param integer xmlFile XML file handle
-- @param string key XML key path
function InterestRateModel:readFromXML(xmlFile, key)
    self.currentRate = getXMLFloat(xmlFile, key .. "#currentRate") or InterestRateModel.DEFAULT_RATE

    self.rateHistory = {}
    local i = 0
    while true do
        local hKey = string.format("%s.history(%d)", key, i)
        if not hasXMLProperty(xmlFile, hKey) then
            break
        end
        table.insert(self.rateHistory, {
            year = getXMLInt(xmlFile,   hKey .. "#year") or 0,
            rate = getXMLFloat(xmlFile, hKey .. "#rate") or InterestRateModel.DEFAULT_RATE
        })
        i = i + 1
    end
end

---Serialize interest rate model to network stream
-- @param integer streamId Network stream identifier
function InterestRateModel:writeStream(streamId)
    streamWriteFloat32(streamId, self.currentRate)
    streamWriteInt8(streamId,    #self.rateHistory)
    for _, entry in ipairs(self.rateHistory) do
        streamWriteInt16(streamId,   entry.year)
        streamWriteFloat32(streamId, entry.rate)
    end
end

---Deserialize interest rate model from network stream
-- @param integer streamId Network stream identifier
function InterestRateModel:readStream(streamId)
    self.currentRate = streamReadFloat32(streamId)

    self.rateHistory = {}
    local count = streamReadInt8(streamId)
    for _ = 1, count do
        table.insert(self.rateHistory, {
            year = streamReadInt16(streamId),
            rate = streamReadFloat32(streamId)
        })
    end
end
