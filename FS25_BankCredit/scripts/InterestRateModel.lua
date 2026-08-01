-- Copyright © 2026 Squallqt. All rights reserved.
---Models bank interest rates, market trends, and risk surcharges.
InterestRateModel = {}
local InterestRateModel_mt = Class(InterestRateModel)

InterestRateModel.DEFAULT_RATE  = 3.5
InterestRateModel.MIN_RATE      = 1.25
InterestRateModel.MAX_RATE      = 5.75
InterestRateModel.STEP          = 0.25
InterestRateModel.HISTORY_MAX   = 5

InterestRateModel.TREND_DOWN   = 0
InterestRateModel.TREND_STABLE = 1
InterestRateModel.TREND_UP     = 2

InterestRateModel.TREND_DIRECTION = {
    [InterestRateModel.TREND_DOWN]   = -1,
    [InterestRateModel.TREND_STABLE] = 0,
    [InterestRateModel.TREND_UP]     = 1,
}

InterestRateModel.TREND_MIN_MONTHS = 2
InterestRateModel.TREND_MAX_MONTHS = 6

InterestRateModel.RNG_MODULUS    = 2147483647
InterestRateModel.RNG_MULTIPLIER = 48271

InterestRateModel.TYPE_SPREAD = {
    [1] = 0.0,   -- ANNUITY
    [2] = 0.75,  -- BULLET
    [3] = 5.0,   -- REVOLVING
}

---Clamp a base rate to the supported market range.
-- @param float rate Rate to clamp
-- @return float rate Clamped rate
function InterestRateModel.clampRate(rate)
    return math.max(InterestRateModel.MIN_RATE, math.min(InterestRateModel.MAX_RATE, rate))
end

---Create InterestRateModel instance
-- @param float? initialRate Starting interest rate (defaults to DEFAULT_RATE)
-- @param integer? randomSeed Initial private random state (defaults to current game time)
-- @return InterestRateModel instance
function InterestRateModel.new(initialRate, randomSeed)
    local self = setmetatable({}, InterestRateModel_mt)
    self.currentRate = InterestRateModel.clampRate(initialRate or InterestRateModel.DEFAULT_RATE)
    self.rateHistory = {}
    self.trend = InterestRateModel.TREND_STABLE
    self.trendMonthsRemaining = 0
    self.randomState = math.floor(randomSeed or g_time) % (InterestRateModel.RNG_MODULUS - 1) + 1
    return self
end

---Advance and return the private pseudo-random sequence.
-- @param integer maxValue Inclusive upper bound
-- @return integer value Integer between 1 and maxValue
function InterestRateModel:nextRandom(maxValue)
    self.randomState = (self.randomState * InterestRateModel.RNG_MULTIPLIER)
        % InterestRateModel.RNG_MODULUS
    return self.randomState % maxValue + 1
end

---Start a new unbiased market trend lasting two to six months.
function InterestRateModel:startTrend()
    self.trend = self:nextRandom(3) - 1
    self.trendMonthsRemaining = self:nextRandom(
        InterestRateModel.TREND_MAX_MONTHS - InterestRateModel.TREND_MIN_MONTHS + 1
    ) + InterestRateModel.TREND_MIN_MONTHS - 1
end

---Return the signed number of 0.25-point units for the current month.
-- Trending phases use 20% stable, 55% normal, 20% strong, and 5% shock moves.
-- Stable phases use 70% stable and 30% balanced minor moves.
-- @return integer units Signed step count between -3 and 3
function InterestRateModel:getMonthlyMove()
    local direction = InterestRateModel.TREND_DIRECTION[self.trend]
    local roll = self:nextRandom(20)

    if direction == 0 then
        if roll <= 14 then
            return 0
        end
        return self:nextRandom(2) == 1 and -1 or 1
    end

    if roll <= 4 then
        return 0
    elseif roll <= 15 then
        return direction
    elseif roll <= 19 then
        return direction * 2
    end
    return direction * 3
end

---Append the current rate to the bounded history.
-- @param integer currentYear Current game year
function InterestRateModel:recordRate(currentYear)
    table.insert(self.rateHistory, { year = currentYear, rate = self.currentRate })
    while #self.rateHistory > InterestRateModel.HISTORY_MAX do
        table.remove(self.rateHistory, 1)
    end
end

---Advance interest rate by one monthly market step.
-- Called on every period change when dynamicRate is enabled.
-- @param integer currentYear Current game year
function InterestRateModel:update(currentYear)
    if self.trendMonthsRemaining == 0 then
        self:startTrend()
    end

    if self.currentRate == InterestRateModel.MIN_RATE and self.trend == InterestRateModel.TREND_DOWN then
        self.trend = InterestRateModel.TREND_UP
    elseif self.currentRate == InterestRateModel.MAX_RATE and self.trend == InterestRateModel.TREND_UP then
        self.trend = InterestRateModel.TREND_DOWN
    end

    local newRate = self.currentRate + self:getMonthlyMove() * InterestRateModel.STEP
    newRate = InterestRateModel.clampRate(newRate)
    self.currentRate = math.floor(newRate * 100 + 0.5) / 100
    self.trendMonthsRemaining = self.trendMonthsRemaining - 1

    self:recordRate(currentYear)
end

---Reset the live rate and market phase after an administrator rate change.
-- @param float rate New configured rate
-- @param integer currentYear Current game year
function InterestRateModel:resetToRate(rate, currentYear)
    local newRate = InterestRateModel.clampRate(rate)
    local rateChanged = newRate ~= self.currentRate

    self.currentRate = newRate
    self.trend = InterestRateModel.TREND_STABLE
    self.trendMonthsRemaining = 0

    if rateChanged then
        self:recordRate(currentYear)
    end
end

---Copy all synchronized model state while preserving the receiving instance.
-- @param InterestRateModel other Source model
function InterestRateModel:copyFrom(other)
    self.currentRate = other.currentRate
    self.rateHistory = other.rateHistory
    self.trend = other.trend
    self.trendMonthsRemaining = other.trendMonthsRemaining
    self.randomState = other.randomState
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
    setXMLInt(xmlFile, key .. "#trend", self.trend)
    setXMLInt(xmlFile, key .. "#trendMonthsRemaining", self.trendMonthsRemaining)
    setXMLInt(xmlFile, key .. "#randomState", self.randomState)
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
    local savedRate = getXMLFloat(xmlFile, key .. "#currentRate") or InterestRateModel.DEFAULT_RATE
    self.currentRate = InterestRateModel.clampRate(savedRate)
    self.trend = getXMLInt(xmlFile, key .. "#trend") or InterestRateModel.TREND_STABLE
    self.trendMonthsRemaining = getXMLInt(xmlFile, key .. "#trendMonthsRemaining") or 0
    self.randomState = getXMLInt(xmlFile, key .. "#randomState") or self.randomState

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
    streamWriteInt8(streamId, self.trend)
    streamWriteInt8(streamId, self.trendMonthsRemaining)
    streamWriteInt32(streamId, self.randomState)
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
    self.trend = streamReadInt8(streamId)
    self.trendMonthsRemaining = streamReadInt8(streamId)
    self.randomState = streamReadInt32(streamId)

    self.rateHistory = {}
    local count = streamReadInt8(streamId)
    for _ = 1, count do
        table.insert(self.rateHistory, {
            year = streamReadInt16(streamId),
            rate = streamReadFloat32(streamId)
        })
    end
end
