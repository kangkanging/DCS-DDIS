local FlightDisplay = {}
FlightDisplay.__index = FlightDisplay

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local DEG_TO_RAD = math.pi / 180
local RAD_TO_DEG = 180 / math.pi
local FT_TO_M = 0.3048
local M_TO_NM = 1 / 1852

local M_TO_FT = 1 / FT_TO_M
local THREE_DEGREE_GLIDE_TAN = math.tan(3 * DEG_TO_RAD)

local VIEWPORT_W, VIEWPORT_H = 440, 360

local MODE_NORMAL = "NORMAL"
local MODE_LANDING_INPUT = "LANDING_INPUT"
local MODE_LANDING_ACTIVE = "LANDING_ACTIVE"

local NORMAL_PIXELS_PER_DEG = 8
local LANDING_PIXELS_PER_DEG = 16
local LANDING_TEXTURE_OFFSET_Y = 90

local BANK_STEP_DEG = 2
local BANK_DIRECTION = -1
local PITCH_DIRECTION = 1
local PITCH_LIMIT_DEG = 45
local VECTOR_LIMIT_DEG = 45
local MIN_FORWARD_SPEED = 5.0

local HORIZON_ATLAS = {
    width = 4400,
    height = 6480,
    frameWidth = 440,
    frameHeight = 720,
    columns = 10,
    frameCount = 90,
}

local VECTOR_ATLAS = {
    width = 440,
    height = 720,
    frameWidth = 440,
    frameHeight = 720,
    columns = 1,
    frameCount = 1,
}

local MARKER_ATLAS = {
    width = 440,
    height = 720,
    frameWidth = 440,
    frameHeight = 720,
    columns = 1,
    frameCount = 1,
}

local AIRPORT_ATLAS = {
    width = 880,
    height = 720,
    frameWidth = 880,
    frameHeight = 720,
    columns = 1,
    frameCount = 1,
}

local YAW_ATLAS = {
    width = 880,
    height = 720,
    frameWidth = 880,
    frameHeight = 720,
    columns = 1,
    frameCount = 1,
}

local DEGREE_MARKER_ATLAS = {
    width = 880,
    height = 720,
    frameWidth = 440,
    frameHeight = 720,
    columns = 2,
    frameCount = 2,
}

local HORIZON_NEUTRAL_Y = (HORIZON_ATLAS.frameHeight - VIEWPORT_H) / 2
local VECTOR_NEUTRAL_Y = (VECTOR_ATLAS.frameHeight - VIEWPORT_H) / 2
local MARKER_NEUTRAL_Y = (MARKER_ATLAS.frameHeight - VIEWPORT_H) / 2
local AIRPORT_NEUTRAL_X = (AIRPORT_ATLAS.frameWidth - VIEWPORT_W) / 2
local AIRPORT_NEUTRAL_Y = (AIRPORT_ATLAS.frameHeight - VIEWPORT_H) / 2
local YAW_NEUTRAL_X = (YAW_ATLAS.frameWidth - VIEWPORT_W) / 2
local YAW_NEUTRAL_Y = (YAW_ATLAS.frameHeight - VIEWPORT_H) / 2

local FIELD_LATITUDE, FIELD_LONGITUDE = 1, 2
local FIELD_ALTITUDE, FIELD_COURSE, FIELD_COUNT = 3, 4, 4

------------------------------------------------------------
-- DCS terrain coordinate API
------------------------------------------------------------

local terrainApi = nil

do
    local ok, module = pcall(require, "terrain")
    if ok and type(module) == "table" then terrainApi = module end

    if not terrainApi then
        local globalTerrain = rawget(_G, "terrain")
        if type(globalTerrain) == "table" then terrainApi = globalTerrain end
    end
end

------------------------------------------------------------
-- General helpers
------------------------------------------------------------

local function clamp(value, minimum, maximum)
    return value < minimum and minimum
        or (value > maximum and maximum or value)
end

local function round(value)
    return value >= 0
        and math.floor(value + 0.5)
        or math.ceil(value - 0.5)
end

local function atan2(y, x)
    if type(math.atan2) == "function" then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

local function normalizeLineAngle(angle)
    angle = angle % 180
    return angle < 0 and angle + 180 or angle
end

local function normalizeSignedDegrees(angle)
    angle = (angle + 180) % 360 - 180
    return angle == -180 and 180 or angle
end

local function formatHeading(value)
    if value == nil then return "---" end
    local rounded = math.floor((value % 360) + 0.5)
    return string.format("%03d", rounded >= 360 and 0 or rounded)
end

local function bindAtlas(file, definition)
    return {
        file = file,
        width = definition.width,
        height = definition.height,
        frameWidth = definition.frameWidth,
        frameHeight = definition.frameHeight,
        columns = definition.columns,
        frameCount = definition.frameCount,
    }
end

local function hideLayers(graphics, firstIndex, lastIndex)
    for index = firstIndex, lastIndex do graphics:hide(index) end
end

------------------------------------------------------------
-- Attitude and flight vector
------------------------------------------------------------

local function bankToFrame(bankDeg)
    local angle = normalizeLineAngle(bankDeg * BANK_DIRECTION)
    local quantized = math.floor(angle / BANK_STEP_DEG + 0.5) * BANK_STEP_DEG
    if quantized >= 180 then quantized = 0 end
    return math.floor(quantized / BANK_STEP_DEG) + 1, quantized
end

local function pitchToOffset(pitchDeg, pixelsPerDeg, centerOffsetY)
    local limited = clamp(pitchDeg, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)
    local movement = round(limited * pixelsPerDeg * PITCH_DIRECTION)
    local offsetY = clamp(
        HORIZON_NEUTRAL_Y + (centerOffsetY or 0) - movement,
        0,
        HORIZON_ATLAS.frameHeight - VIEWPORT_H
    )
    return offsetY, limited
end

-- 只计算实际使用的前向和上向速度。
local function worldVelocityToBody(velocity, heading, pitch, bank)
    if not velocity then return nil end

    local vx = tonumber(velocity.x)
    local vy = tonumber(velocity.y)
    local vz = tonumber(velocity.z)
    if not vx or not vy or not vz then return nil end

    heading, pitch, bank = heading or 0, pitch or 0, bank or 0

    local ch, sh = math.cos(heading), math.sin(heading)
    local cp, sp = math.cos(pitch), math.sin(pitch)
    local cb, sb = math.cos(bank), math.sin(bank)

    local fx, fy, fz = cp * ch, sp, cp * sh
    local r0x, r0y, r0z = -sh, 0, ch
    local u0x, u0y, u0z = -sp * ch, cp, -sp * sh

    local ux = r0x * sb + u0x * cb
    local uy = r0y * sb + u0y * cb
    local uz = r0z * sb + u0z * cb

    local forward = vx * fx + vy * fy + vz * fz
    local up = vx * ux + vy * uy + vz * uz
    return forward, up
end

local function getVerticalVectorAngle(forward, up)
    if not forward or not up or forward < MIN_FORWARD_SPEED then return nil end
    return atan2(up, forward) * RAD_TO_DEG
end

local function vectorAngleToOffset(angleDeg, pixelsPerDeg, centerOffsetY)
    local limited = clamp(angleDeg, -VECTOR_LIMIT_DEG, VECTOR_LIMIT_DEG)
    local movement = round(limited * pixelsPerDeg)
    local offsetY = clamp(
        VECTOR_NEUTRAL_Y + (centerOffsetY or 0) + movement,
        0,
        VECTOR_ATLAS.frameHeight - VIEWPORT_H
    )
    return offsetY, limited
end

------------------------------------------------------------
-- Input helpers
------------------------------------------------------------

local function getFieldValue(self)
    if self.selectedField == FIELD_LATITUDE then return self.latitudeInput end
    if self.selectedField == FIELD_LONGITUDE then return self.longitudeInput end
    if self.selectedField == FIELD_ALTITUDE then return self.altitudeInput end
    return self.courseInput
end

local function setFieldValue(self, value)
    if self.selectedField == FIELD_LATITUDE then
        self.latitudeInput = value
    elseif self.selectedField == FIELD_LONGITUDE then
        self.longitudeInput = value
    elseif self.selectedField == FIELD_ALTITUDE then
        self.altitudeInput = value
    else
        self.courseInput = value
    end
end

local function getFieldMaxLength(field)
    if field == FIELD_LATITUDE then return 7 end  -- NDDMMSS
    if field == FIELD_LONGITUDE then return 8 end -- EDDDMMSS
    if field == FIELD_ALTITUDE then return 5 end  -- 0～99999 ft
    return 4                                      -- DDDd：最后一位为0.1°；DDD仍兼容整数航向
end

local function appendCharacter(self, character)
    if type(character) ~= "string" or character == "" then return false end
    character = character:upper()

    local value = getFieldValue(self)
    local field = self.selectedField
    local maxLength = getFieldMaxLength(field)

    local isDirection =
        (field == FIELD_LATITUDE and (character == "N" or character == "S")) or
        (field == FIELD_LONGITUDE and (character == "E" or character == "W"))

    if isDirection then
        local first = value:sub(1, 1)
        local hasDirection = first == "N" or first == "S" or first == "E" or first == "W"
        value = hasDirection and (character .. value:sub(2)) or (character .. value)
        if #value > maxLength then value = value:sub(1, maxLength) end
        setFieldValue(self, value)
        self.inputError = nil
        return true
    end

    if character < "0" or character > "9" then return false end
    if #value < maxLength then setFieldValue(self, value .. character) end
    self.inputError = nil
    return true
end

local function deleteCharacter(self)
    local value = getFieldValue(self)
    if #value > 0 then setFieldValue(self, value:sub(1, #value - 1)) end
    self.inputError = nil
end

------------------------------------------------------------
-- Coordinate parsing and DCS local conversion
------------------------------------------------------------

local function parseCoordinate(value, isLatitude)
    if type(value) ~= "string" then return nil end

    local pattern = isLatitude
        and "^([NS])(%d%d)(%d%d)(%d%d)$"
        or "^([EW])(%d%d%d)(%d%d)(%d%d)$"

    local direction, degText, minText, secText = value:match(pattern)
    if not direction then return nil end

    local degrees = tonumber(degText)
    local minutes = tonumber(minText)
    local seconds = tonumber(secText)
    local maximumDegrees = isLatitude and 90 or 180

    if degrees > maximumDegrees or minutes >= 60 or seconds >= 60 then return nil end
    if degrees == maximumDegrees and (minutes > 0 or seconds > 0) then return nil end

    local result = degrees + minutes / 60 + seconds / 3600
    return (direction == "S" or direction == "W") and -result or result
end

-- DCS API参数顺序为经度、纬度。转换只在激活LANDING时执行一次。
local function readLocalResult(x, z)
    if type(x) == "table" then
        local position = x
        x = position.x or position[1]
        z = position.z or position[2]
    end

    x, z = tonumber(x), tonumber(z)
    return x, z
end

local function geoToLocal(latitude, longitude)
    local exportConverter = rawget(_G, "LoGeoCoordinatesToLoCoordinates")

    if type(exportConverter) == "function" then
        local ok, x, z = pcall(exportConverter, longitude, latitude)
        if ok then
            x, z = readLocalResult(x, z)
            if x and z then return x, z, nil end
        end
    end

    if terrainApi and type(terrainApi.convertLatLonToMeters) == "function" then
        local ok, x, z = pcall(
            terrainApi.convertLatLonToMeters,
            latitude,
            longitude
        )

        if ok then
            x, z = readLocalResult(x, z)
            if x and z then return x, z, nil end
        end
    end

    local coordApi = rawget(_G, "coord")

    if type(coordApi) == "table" and type(coordApi.LLtoLO) == "function" then
        local ok, position = pcall(coordApi.LLtoLO, latitude, longitude)

        if ok and type(position) == "table" then
            local x, z = tonumber(position.x), tonumber(position.z)
            if x and z then return x, z, nil end
        end
    end

    return nil, nil, "NO GEO CONVERTER"
end


-- N413005 -> N-41°30′05″
-- E0413005 -> E-041°30′05″
local function formatCoordinate(value, isLatitude)
    if value == "" then
        return isLatitude and "N-DD°MM′SS″" or "E-DDD°MM′SS″"
    end

    local degreeEnd = isLatitude and 3 or 4
    local minuteStart, minuteEnd = degreeEnd + 1, degreeEnd + 2
    local secondStart, secondEnd = minuteEnd + 1, minuteEnd + 2
    local result = value:sub(1, 1) .. "-"

    if #value >= 2 then result = result .. value:sub(2, math.min(#value, degreeEnd)) end
    if #value >= degreeEnd then result = result .. "°" end
    if #value >= minuteStart then result = result .. value:sub(minuteStart, math.min(#value, minuteEnd)) end
    if #value >= minuteEnd then result = result .. "′" end
    if #value >= secondStart then result = result .. value:sub(secondStart, math.min(#value, secondEnd)) end
    if #value >= secondEnd then result = result .. "″" end
    return result
end

local function parseCourse(value)
    if type(value) ~= "string" then return nil end

    local course
    if #value == 3 then
        course = tonumber(value)
    elseif #value == 4 then
        course = tonumber(value) / 10
    else
        return nil
    end

    if not course or course < 0 or course >= 360 then return nil end
    return course
end

local function formatCourseInput(value)
    if value == "" then return "---.-" end
    if #value <= 3 then return value end
    return value:sub(1, 3) .. "." .. value:sub(4, 4)
end

local function formatCourse(value)
    if value == nil then return "---.-" end
    return string.format("%05.1f", value % 360)
end

local function getLandingInputs(self)
    local latitude = parseCoordinate(self.latitudeInput, true)
    if not latitude then return nil, "INVALID LAT" end

    local longitude = parseCoordinate(self.longitudeInput, false)
    if not longitude then return nil, "INVALID LON" end

    local altitudeFeet = tonumber(self.altitudeInput)
    if not altitudeFeet or altitudeFeet < 0 or altitudeFeet > 99999 then
        return nil, "INVALID ALT"
    end

    local course = parseCourse(self.courseInput)
    if not course then return nil, "INVALID CRS" end

    local positionX, positionZ, positionError = geoToLocal(latitude, longitude)
    if not positionX then return nil, positionError end

    -- F10量取值直接作为DCS网格航向，不再进行真航向二次转换。
    local courseRad = course * DEG_TO_RAD
    local courseX = math.cos(courseRad)
    local courseZ = math.sin(courseRad)

    return {
        latitude = latitude,
        longitude = longitude,
        positionX = positionX,
        positionZ = positionZ,
        courseX = courseX,
        courseZ = courseZ,
        altitude = altitudeFeet * FT_TO_M,
        altitudeFeet = altitudeFeet,
        course = course,
    }, nil
end

------------------------------------------------------------
-- Airport direction in DCS local coordinates
------------------------------------------------------------

local function getAircraftAltitude(aircraft)
    return tonumber(aircraft.altitudeMSL)
        or tonumber(aircraft.selfDataAltitude)
        or tonumber(aircraft.positionY)
end

local function getAircraftLocalPosition(aircraft)
    -- 优先把飞机经纬度转换到与机场完全相同的坐标系。
    local latitude = tonumber(aircraft.latitude)
    local longitude = tonumber(aircraft.longitude)

    if latitude and longitude then
        local x, z = geoToLocal(latitude, longitude)
        if x and z then return x, z end
    end

    -- 转换不可用时才退回LoGetSelfData().Position。
    return tonumber(aircraft.positionX), tonumber(aircraft.positionZ)
end

local function calculateAirportDirection(aircraft, airport, result)
    local aircraftX, aircraftZ = getAircraftLocalPosition(aircraft)
    local aircraftAlt = getAircraftAltitude(aircraft)

    if not aircraftX or not aircraftZ then return nil, "NO LOCAL POSITION" end
    if not aircraftAlt then return nil, "NO ALTITUDE" end
    if not airport.positionX or not airport.positionZ then return nil, "NO AP POSITION" end

    local deltaX = airport.positionX - aircraftX
    local deltaZ = airport.positionZ - aircraftZ
    local horizontalDistance = math.sqrt(deltaX * deltaX + deltaZ * deltaZ)

    -- DCS本地坐标：+X为北，+Z为东；0°为北、90°为东。
    local bearing = (atan2(deltaZ, deltaX) * RAD_TO_DEG) % 360
    local heading = (tonumber(aircraft.heading) or 0) * RAD_TO_DEG
    local pitch = (tonumber(aircraft.pitch) or 0) * RAD_TO_DEG

    local altitudeDifference = airport.altitude - aircraftAlt
    local elevation = atan2(
        altitudeDifference,
        math.max(horizontalDistance, 0.01)
    ) * RAD_TO_DEG

    result.bearing = bearing
    result.distance = horizontalDistance
    result.altitudeDifference = altitudeDifference
    result.horizontalAngle = normalizeSignedDegrees(bearing - heading)
    result.verticalAngle = elevation - pitch

    -- 飞机指向跑道入口的方向相对进场中心线的角偏差。
    -- 正值表示中心线位于飞机右侧，Layer 5向右移动。
    local courseForward = deltaX * airport.courseX + deltaZ * airport.courseZ
    local courseRight = deltaX * (-airport.courseZ) + deltaZ * airport.courseX
    result.courseDeviation = atan2(courseRight, courseForward) * RAD_TO_DEG
    return result, nil
end

local function airportAnglesToOffset(horizontalAngle, verticalAngle)
    -- 超出视场时钳制在对应边缘，不再隐藏机场标记。
    local movementX = clamp(
        round(horizontalAngle * LANDING_PIXELS_PER_DEG),
        -AIRPORT_NEUTRAL_X,
        AIRPORT_NEUTRAL_X
    )

    local movementY = clamp(
        round(verticalAngle * LANDING_PIXELS_PER_DEG),
        -AIRPORT_NEUTRAL_Y,
        AIRPORT_NEUTRAL_Y
    )

    local offsetY = clamp(
        AIRPORT_NEUTRAL_Y + movementY + LANDING_TEXTURE_OFFSET_Y,
        0,
        AIRPORT_ATLAS.frameHeight - VIEWPORT_H
    )

    return AIRPORT_NEUTRAL_X - movementX, offsetY
end

local function courseDeviationToOffset(angle)
    local movement = clamp(
        round(angle * LANDING_PIXELS_PER_DEG),
        -YAW_NEUTRAL_X,
        YAW_NEUTRAL_X
    )

    return YAW_NEUTRAL_X - movement
end

------------------------------------------------------------
-- Constructor and lifecycle
------------------------------------------------------------

function FlightDisplay.new(context)
    if not context or not context.aircraftData or
        not context.horizonTexturePath or not context.vectorTexturePath or
        not context.markerTexturePath or not context.airportTexturePath or
        not context.yawTexturePath or not context.degreeMarkerTexturePath then
        error("FlightDisplay context incomplete")
    end

    return setmetatable({
        aircraft = context.aircraftData,
        horizonAtlas = bindAtlas(context.horizonTexturePath, HORIZON_ATLAS),
        vectorAtlas = bindAtlas(context.vectorTexturePath, VECTOR_ATLAS),
        markerAtlas = bindAtlas(context.markerTexturePath, MARKER_ATLAS),
        airportAtlas = bindAtlas(context.airportTexturePath, AIRPORT_ATLAS),
        yawAtlas = bindAtlas(context.yawTexturePath, YAW_ATLAS),
        degreeMarkerAtlas = bindAtlas(context.degreeMarkerTexturePath, DEGREE_MARKER_ATLAS),

        updateInterval = 0.05,
        mode = MODE_NORMAL,
        selectedField = FIELD_LATITUDE,

        latitudeInput = "",
        longitudeInput = "",
        altitudeInput = "",
        courseInput = "",

        inputError = nil,
        airport = nil,
        _flightCache = {},
        _directionCache = {},
    }, FlightDisplay)
end

function FlightDisplay:onEnter(params)
end

function FlightDisplay:onExit()
end

function FlightDisplay:update(dt)
    return true
end

------------------------------------------------------------
-- Flight graphics
------------------------------------------------------------

function FlightDisplay:drawFlightGraphics(graphics, pixelsPerDeg)
    -- Layer 4、5、6由当前页面模式管理。
    hideLayers(graphics, 7, 10)

    if not self.aircraft:isAvailable() then
        hideLayers(graphics, 1, 3)
        graphics:hide(6)
        return nil
    end

    local heading = tonumber(self.aircraft.heading) or 0
    local pitch = tonumber(self.aircraft.pitch) or 0
    local bank = tonumber(self.aircraft.bank) or 0
    local pitchDeg, bankDeg = pitch * RAD_TO_DEG, bank * RAD_TO_DEG
    local landingOffsetY = self.mode == MODE_NORMAL and 0 or LANDING_TEXTURE_OFFSET_Y

    --------------------------------------------------------
    -- Layer 1: Horizon
    --------------------------------------------------------

    local horizonFrame, horizonAngle = bankToFrame(bankDeg)
    local horizonOffsetY = pitchToOffset(pitchDeg, pixelsPerDeg, landingOffsetY)
    graphics:setAtlasFrame(1, self.horizonAtlas, horizonFrame, 0, horizonOffsetY)

    --------------------------------------------------------
    -- Layer 6: Pitch scale
    -- Frame 1：普通模式；Frame 2：降落模式。
    -- 复用地平线俯仰偏移，保持完全同步。
    --------------------------------------------------------

    local degreeMarkerFrame = self.mode == MODE_NORMAL and 1 or 2
    graphics:setAtlasFrame(
        6,
        self.degreeMarkerAtlas,
        degreeMarkerFrame,
        0,
        horizonOffsetY
    )

    --------------------------------------------------------
    -- Layer 2: Flight vector
    --------------------------------------------------------

    local forward, up = worldVelocityToBody(
        self.aircraft.vectorVelocity,
        heading,
        pitch,
        bank
    )

    local vectorAngle = getVerticalVectorAngle(forward, up)
    local vectorOffsetY = nil

    if vectorAngle then
        vectorOffsetY = vectorAngleToOffset(vectorAngle, pixelsPerDeg, landingOffsetY)
        graphics:setAtlasFrame(2, self.vectorAtlas, 1, 0, vectorOffsetY)
    else
        graphics:hide(2)
    end

    --------------------------------------------------------
    -- Layer 3: Nose marker
    --------------------------------------------------------

    graphics:setAtlasFrame(
        3,
        self.markerAtlas,
        1,
        0,
        MARKER_NEUTRAL_Y + landingOffsetY
    )

    local cache = self._flightCache
    cache.pitchDeg = pitchDeg
    cache.bankDeg = bankDeg
    cache.horizonFrame = horizonFrame
    cache.horizonAngle = horizonAngle
    cache.forward = forward
    cache.up = up
    cache.vectorAngle = vectorAngle
    cache.vectorOffsetY = vectorOffsetY
    return cache
end

------------------------------------------------------------
-- Input
------------------------------------------------------------

function FlightDisplay:onInput(event)
    if event.type == "CHAR" then
        if self.mode ~= MODE_LANDING_INPUT then return false end
        return appendCharacter(self, event.value)
    end

    if event.type ~= "KEY" then return false end
    local key = event.value

    if key == "FN1" then
        if self.mode == MODE_NORMAL then
            self.mode = MODE_LANDING_INPUT
            self.selectedField = FIELD_LATITUDE
            self.inputError = nil
        end
        return true
    end

    if key == "FN4" and self.mode ~= MODE_NORMAL then
        self.mode = MODE_NORMAL
        self.inputError = nil
        return true
    end

    if self.mode == MODE_LANDING_ACTIVE then
        if key == "FN2" then
            self.mode = MODE_LANDING_INPUT
            self.selectedField = FIELD_LATITUDE
            self.inputError = nil
            return true
        end
        return false
    end

    if self.mode ~= MODE_LANDING_INPUT then return false end

    if key == "UP" or key == "LEFT" then
        if self.selectedField > 1 then self.selectedField = self.selectedField - 1 end
        self.inputError = nil
        return true
    end

    if key == "DOWN" or key == "RIGHT" then
        if self.selectedField < FIELD_COUNT then self.selectedField = self.selectedField + 1 end
        self.inputError = nil
        return true
    end

    if key == "DEL" then
        deleteCharacter(self)
        return true
    end

    if key == "FN2" then
        setFieldValue(self, "")
        self.inputError = nil
        return true
    end

    if key == "ENTER" then
        if self.selectedField < FIELD_COUNT then
            self.selectedField = self.selectedField + 1
        else
            local airport, inputError = getLandingInputs(self)
            if airport then
                self.airport = airport
                self.mode = MODE_LANDING_ACTIVE
                self.inputError = nil
            else
                self.inputError = inputError
            end
        end
        return true
    end

    -- HOME和BACK继续交给框架处理。
    return false
end

------------------------------------------------------------
-- Render helpers
------------------------------------------------------------

local function fieldPrefix(self, field)
    return self.selectedField == field and ">" or " "
end

local function displayInput(value, placeholder)
    return value ~= "" and value or placeholder
end

local function renderNormal(self, renderer, graphics, flight)
    graphics:hide(4)
    graphics:hide(5)
    renderer:setLine(1, "FLIGHT DISPLAY")

    if not flight then
        renderer:setLine(7, "NO AIRCRAFT DATA")
        renderer:setLine(14, "FN1:LANDING")
        return
    end

    renderer:setLine(2, string.format("BANK :%+06.1f DEG", flight.bankDeg))
    renderer:setLine(3, string.format("PITCH:%+06.1f DEG", flight.pitchDeg))
    renderer:setLine(4, string.format("H FRM:%02d ANG:%03d", flight.horizonFrame, flight.horizonAngle))

    if flight.vectorAngle then
        renderer:setLine(5, string.format("FV ANG:%+06.1f DEG", flight.vectorAngle))
        renderer:setLine(6, string.format("FV Y  :%03d", flight.vectorOffsetY))
        renderer:setLine(7, string.format("VF:%+.1f VU:%+.1f", flight.forward, flight.up))
    else
        renderer:setLine(5, "FV:UNAVAILABLE")
    end

    renderer:setLine(12, "MODE:NORMAL 8PX/DEG")
    renderer:setLine(13, "L1:HR L2:FV L3:NOSE")
    renderer:setLine(14, "FN1:LANDING")
end

local function renderLandingInput(self, renderer, graphics)
    graphics:hide(4)
    graphics:hide(5)
    renderer:setLine(1, "LANDING INPUT 16PX/DEG")
    renderer:setLine(2, fieldPrefix(self, FIELD_LATITUDE) .. "LAT:" .. formatCoordinate(self.latitudeInput, true))
    renderer:setLine(3, fieldPrefix(self, FIELD_LONGITUDE) .. "LON:" .. formatCoordinate(self.longitudeInput, false))
    renderer:setLine(4, fieldPrefix(self, FIELD_ALTITUDE) .. "ALT:" .. displayInput(self.altitudeInput, "-----") .. " FT")
    renderer:setLine(5, fieldPrefix(self, FIELD_COURSE) .. "CRS:" .. formatCourseInput(self.courseInput) .. " DEG GRID")

    if self.inputError then renderer:setLine(8, self.inputError) end
    renderer:setLine(13, "FN2:CLEAR FN4:NORMAL")
    renderer:setLine(14, "ENT:NEXT / ACTIVATE")
end

local function renderLandingActive(self, renderer, graphics, flight)
    renderer:setLine(1, "LANDING ACTIVE 16PX/DEG")
    renderer:setLine(2, string.format(
        "RWY CRS:%sG AP ALT:%.0fFT",
        formatCourse(self.airport.course),
        self.airport.altitudeFeet
    ))

    if not flight then
        graphics:hide(4)
        graphics:hide(5)
        renderer:setLine(7, "NO AIRCRAFT DATA")
        renderer:setLine(14, "FN2:EDT               FN4:NORM")
        return
    end

    local direction, errorText = calculateAirportDirection(
        self.aircraft,
        self.airport,
        self._directionCache
    )

    if not direction then
        graphics:hide(4)
        graphics:hide(5)
        renderer:setLine(7, errorText or "NO POSITION")
        renderer:setLine(14, "FN2:EDT               FN4:NORM")
        return
    end

    local offsetX, offsetY = airportAnglesToOffset(
        direction.horizontalAngle,
        direction.verticalAngle
    )

    graphics:setAtlasFrame(4, self.airportAtlas, 1, offsetX, offsetY)

    local yawOffsetX = courseDeviationToOffset(direction.courseDeviation)
    graphics:setAtlasFrame(
        5,
        self.yawAtlas,
        1,
        yawOffsetX,
        YAW_NEUTRAL_Y + LANDING_TEXTURE_OFFSET_Y
    )

    local recommendedRadarAltitude = direction.distance * THREE_DEGREE_GLIDE_TAN * M_TO_FT
    renderer:setLine(3, string.format(
        "AP B:%s R:%5.1fNM RA:%5.0fFT",
        formatHeading(direction.bearing),
        direction.distance * M_TO_NM,
        recommendedRadarAltitude
    ))
    renderer:setLine(14, "FN2:EDT               FN4:NORM")
end

------------------------------------------------------------
-- Render
------------------------------------------------------------

function FlightDisplay:render(renderer, graphics)
    local pixelsPerDeg = self.mode == MODE_NORMAL
        and NORMAL_PIXELS_PER_DEG
        or LANDING_PIXELS_PER_DEG

    local flight = self:drawFlightGraphics(graphics, pixelsPerDeg)

    if self.mode == MODE_LANDING_INPUT then
        renderLandingInput(self, renderer, graphics)
    elseif self.mode == MODE_LANDING_ACTIVE then
        renderLandingActive(self, renderer, graphics, flight)
    else
        renderNormal(self, renderer, graphics, flight)
    end
end

return FlightDisplay
