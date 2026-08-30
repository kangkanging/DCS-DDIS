local NavComputer = {}
NavComputer.__index = NavComputer

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local MPS_TO_KNOT = 1.943844492
local DEG_TO_RAD = math.pi / 180
local RAD_TO_DEG = 180 / math.pi

------------------------------------------------------------
-- Input fields
------------------------------------------------------------

local FIELD_COURSE = 1
local FIELD_WIND_DIR = 2
local FIELD_WIND_SPEED = 3
local FIELD_COUNT = 3

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function normalizeDegrees(value)
    value = value % 360
    if value < 0 then
        value = value + 360
    end
    return value
end

local function displayInput(value)
    if value == nil or value == "" then
        return "---"
    end
    return value
end

local function parseInput(value)
    if value == nil or value == "" then
        return nil
    end
    return tonumber(value)
end

local function formatHeading(value)
    if value == nil then
        return "---"
    end

    value = normalizeDegrees(value)
    local rounded = math.floor(value + 0.5)

    if rounded >= 360 then
        rounded = 0
    end

    return string.format("%03d", rounded)
end

local function formatSpeed(value)
    if value == nil then
        return "---"
    end
    return string.format("%.0f", value)
end

local function formatWCA(value)
    if value == nil then
        return "---"
    end

    if math.abs(value) < 0.05 then
        return "0.0"
    end

    local direction
    if value > 0 then
        direction = "R"
    else
        direction = "L"
    end

    return string.format("%.1f %s", math.abs(value), direction)
end

------------------------------------------------------------
-- Constructor
------------------------------------------------------------

function NavComputer.new(context)
    if not context or not context.aircraftData then
        error("NavComputer requires aircraftData")
    end

    return setmetatable({
        aircraft = context.aircraftData,

        -- Currently selected input field
        selectedField = FIELD_COURSE,

        -- User input stored as text (e.g. "090", "005")
        courseInput = "",
        windDirInput = "",
        windSpeedInput = "",
    }, NavComputer)
end

------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------

function NavComputer:onEnter(params)
end

function NavComputer:onExit()
end

------------------------------------------------------------
-- Dynamic update
------------------------------------------------------------

function NavComputer:update(dt)
    return true
end

------------------------------------------------------------
-- Get / Set selected input string
------------------------------------------------------------

local function getSelectedValue(self)
    if self.selectedField == FIELD_COURSE then
        return self.courseInput
    elseif self.selectedField == FIELD_WIND_DIR then
        return self.windDirInput
    elseif self.selectedField == FIELD_WIND_SPEED then
        return self.windSpeedInput
    end
    return ""
end

local function setSelectedValue(self, value)
    if self.selectedField == FIELD_COURSE then
        self.courseInput = value
    elseif self.selectedField == FIELD_WIND_DIR then
        self.windDirInput = value
    elseif self.selectedField == FIELD_WIND_SPEED then
        self.windSpeedInput = value
    end
end

------------------------------------------------------------
-- Input Modification Helpers
------------------------------------------------------------

local function appendDigit(self, digit)
    if digit < "0" or digit > "9" then
        return
    end

    local value = getSelectedValue(self)
    if #value >= 3 then
        return
    end

    value = value .. digit
    setSelectedValue(self, value)
end

local function deleteDigit(self)
    local value = getSelectedValue(self)
    if #value == 0 then
        return
    end

    value = value:sub(1, #value - 1)
    setSelectedValue(self, value)
end

local function clearSelectedField(self)
    setSelectedValue(self, "")
end

local function previousField(self)
    if self.selectedField > 1 then
        self.selectedField = self.selectedField - 1
    end
end

local function nextField(self)
    if self.selectedField < FIELD_COUNT then
        self.selectedField = self.selectedField + 1
    end
end

------------------------------------------------------------
-- Validate inputs
------------------------------------------------------------

local function getInputs(self)
    local course = parseInput(self.courseInput)
    local windDirection = parseInput(self.windDirInput)
    local windSpeed = parseInput(self.windSpeedInput)

    if course == nil or windDirection == nil or windSpeed == nil then
        return nil, "INCOMPLETE"
    end

    if course < 0 or course > 359 then
        return nil, "INVALID CRS"
    end

    if windDirection < 0 or windDirection > 360 then
        return nil, "INVALID WIND"
    end

    if windSpeed < 0 or windSpeed > 999 then
        return nil, "INVALID WSPD"
    end

    if windDirection == 360 then
        windDirection = 0
    end

    return {
        course = course,
        windDirection = windDirection,
        windSpeed = windSpeed,
    }, nil
end

------------------------------------------------------------
-- Wind triangle
------------------------------------------------------------

local function calculateWindTriangle(course, tas, windDirection, windSpeed)
    if tas == nil or tas <= 0 then
        return nil, "NO TAS"
    end

    local windAngle = (windDirection - course) * DEG_TO_RAD
    local ratio = (windSpeed * math.sin(windAngle)) / tas

    if ratio > 1 or ratio < -1 then
        return nil, "NO SOLUTION"
    end

    local wcaRad = math.asin(ratio)
    local wcaDeg = wcaRad * RAD_TO_DEG
    local trueHeading = normalizeDegrees(course + wcaDeg)
    local groundSpeed = tas * math.cos(wcaRad) - windSpeed * math.cos(windAngle)

    if groundSpeed <= 0 then
        return nil, "NO SOLUTION"
    end

    return {
        trueHeading = trueHeading,
        wca = wcaDeg,
        groundSpeed = groundSpeed,
    }, nil
end

------------------------------------------------------------
-- Input
------------------------------------------------------------

function NavComputer:onInput(event)
    if event.type == "CHAR" then
        if event.value >= "0" and event.value <= "9" then
            appendDigit(self, event.value)
            return true
        end
        return false
    end

    if event.type ~= "KEY" then
        return false
    end

    if event.value == "UP" then
        previousField(self)
        return true
    end

    if event.value == "DOWN" then
        nextField(self)
        return true
    end

    if event.value == "LEFT" then
        previousField(self)
        return true
    end

    if event.value == "RIGHT" then
        nextField(self)
        return true
    end

    if event.value == "ENTER" then
        nextField(self)
        return true
    end

    if event.value == "DEL" then
        deleteDigit(self)
        return true
    end

    if event.value == "FN2" then
        clearSelectedField(self)
        return true
    end

    return false
end

------------------------------------------------------------
-- Render
------------------------------------------------------------

function NavComputer:render(renderer)
    renderer:setLine(1, "NAV COMPUTER")

    local coursePrefix = (self.selectedField == FIELD_COURSE) and ">" or " "
    local windPrefix = (self.selectedField == FIELD_WIND_DIR) and ">" or " "
    local windSpeedPrefix = (self.selectedField == FIELD_WIND_SPEED) and ">" or " "

    renderer:setLine(3, coursePrefix .. "CRS :" .. displayInput(self.courseInput) .. " DEG T")
    renderer:setLine(4, windPrefix .. "WIND:" .. displayInput(self.windDirInput) .. " DEG FROM")
    renderer:setLine(5, windSpeedPrefix .. "WSPD:" .. displayInput(self.windSpeedInput) .. " KT")

    local ias = nil
    local tas = nil

    if self.aircraft:isAvailable() then
        if self.aircraft.indicatedAirSpeed then
            ias = self.aircraft.indicatedAirSpeed * MPS_TO_KNOT
        end
        if self.aircraft.trueAirSpeed then
            tas = self.aircraft.trueAirSpeed * MPS_TO_KNOT
        end
    end

    renderer:setLine(7, " IAS :" .. formatSpeed(ias) .. " KT")
    renderer:setLine(8, " TAS :" .. formatSpeed(tas) .. " KT")

    local inputs, inputError = getInputs(self)

    if not inputs then
        if inputError == "INCOMPLETE" then
            renderer:setLine(10, " THDG:--- DEG T")
            renderer:setLine(11, " WCA :---")
            renderer:setLine(12, " GS  :--- KT")
        else
            renderer:setLine(10, " " .. inputError)
        end

        renderer:setLine(14, "ENT:NEXT  FN2:CLEAR")
        return
    end

    if tas == nil or tas <= 0 then
        renderer:setLine(10, " NO AIRCRAFT DATA")
        renderer:setLine(14, "ENT:NEXT  FN2:CLEAR")
        return
    end

    local result, calculationError = calculateWindTriangle(
        inputs.course,
        tas,
        inputs.windDirection,
        inputs.windSpeed
    )

    if not result then
        renderer:setLine(10, " " .. calculationError)
        renderer:setLine(14, "ENT:NEXT  FN2:CLEAR")
        return
    end

    renderer:setLine(10, " THDG:" .. formatHeading(result.trueHeading) .. " DEG T")
    renderer:setLine(11, " WCA :" .. formatWCA(result.wca))
    renderer:setLine(12, " GS  :" .. formatSpeed(result.groundSpeed) .. " KT")

    renderer:setLine(14, "ENT:NEXT  FN2:CLEAR")
end

------------------------------------------------------------
-- Export
------------------------------------------------------------

return NavComputer