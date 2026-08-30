local FlightInfo = {}
FlightInfo.__index = FlightInfo

------------------------------------------------------------
-- Unit conversion
------------------------------------------------------------

local METER_TO_FEET =
    3.280839895

local MPS_TO_KNOT =
    1.943844492

local MPS_TO_FPM =
    196.850394

local RAD_TO_DEG =
    180 / math.pi

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function formatNumber(
    value,
    format
)

    if value == nil then
        return "---"
    end

    return
        string.format(
            format,
            value
        )
end

local function formatDegrees(rad)

    if rad == nil then
        return "---"
    end

    local deg =
        rad *
        RAD_TO_DEG

    return
        string.format(
            "%.1f",
            deg
        )
end

local function formatHeading(rad)

    if rad == nil then
        return "---"
    end

    local deg =
        rad *
        RAD_TO_DEG

    --------------------------------------------------------
    -- Normalize heading to 0 - 359.9
    --------------------------------------------------------

    deg =
        deg % 360

    return
        string.format(
            "%03.0f",
            deg
        )
end

local function truncate(
    text,
    length
)

    text =
        tostring(
            text or ""
        )

    if #text <= length then
        return text
    end

    return
        text:sub(
            1,
            length
        )
end

------------------------------------------------------------
-- Constructor
------------------------------------------------------------

function FlightInfo.new(context)

    if
        not context or
        not context.aircraftData
    then
        error(
            "FlightInfo requires aircraftData"
        )
    end

    return
        setmetatable(
            {
                aircraft =
                    context.aircraftData,
            },
            FlightInfo
        )
end

------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------

function FlightInfo:onEnter(params)
end

function FlightInfo:onExit()
end

------------------------------------------------------------
-- Periodic update
------------------------------------------------------------

function FlightInfo:update(dt)

    --------------------------------------------------------
    -- AircraftData itself is updated by the framework.
    --
    -- Returning true tells PageManager that this dynamic
    -- page should be rendered again.
    --------------------------------------------------------

    return true
end

------------------------------------------------------------
-- Input
------------------------------------------------------------

function FlightInfo:onInput(event)

    --------------------------------------------------------
    -- No local keys yet.
    --
    -- BACK:
    -- PageManager returns to previous page.
    --
    -- HOME:
    -- global PageManager action.
    --------------------------------------------------------

    return false
end

------------------------------------------------------------
-- Render
------------------------------------------------------------

function FlightInfo:render(renderer)

    renderer:setLine(
        1,
        "FLIGHT INFO"
    )

    --------------------------------------------------------
    -- No aircraft data
    --------------------------------------------------------

    if
        not self.aircraft:isAvailable()
    then

        renderer:setLine(
            6,
            "NO AIRCRAFT DATA"
        )

        renderer:setLine(
            8,
            "ENTER COCKPIT"
        )

        return
    end

    --------------------------------------------------------
    -- Aircraft name
    --------------------------------------------------------

    renderer:setLine(
        2,
        "AC:" ..
        truncate(
            self.aircraft.name,
            27
        )
    )

    --------------------------------------------------------
    -- Position
    --------------------------------------------------------

    renderer:setLine(
        3,
        "LAT:" ..
        formatNumber(
            self.aircraft.latitude,
            "%.5f"
        )
    )

    renderer:setLine(
        4,
        "LON:" ..
        formatNumber(
            self.aircraft.longitude,
            "%.5f"
        )
    )

    --------------------------------------------------------
    -- Heading
    --------------------------------------------------------

    renderer:setLine(
        5,
        "HDG:" ..
        formatHeading(
            self.aircraft.heading
        ) ..
        " DEG"
    )

    --------------------------------------------------------
    -- Altitude
    --------------------------------------------------------

    local altitudeMSL = nil

    if
        self.aircraft.altitudeMSL
    then

        altitudeMSL =
            self.aircraft.altitudeMSL *
            METER_TO_FEET
    end

    renderer:setLine(
        6,
        "ALT MSL:" ..
        formatNumber(
            altitudeMSL,
            "%.0f"
        ) ..
        " FT"
    )

    local altitudeAGL = nil

    if
        self.aircraft.altitudeAGL
    then

        altitudeAGL =
            self.aircraft.altitudeAGL *
            METER_TO_FEET
    end

    renderer:setLine(
        7,
        "ALT AGL:" ..
        formatNumber(
            altitudeAGL,
            "%.0f"
        ) ..
        " FT"
    )

    --------------------------------------------------------
    -- Airspeed
    --------------------------------------------------------

    local ias = nil

    if
        self.aircraft.indicatedAirSpeed
    then

        ias =
            self.aircraft.indicatedAirSpeed *
            MPS_TO_KNOT
    end

    renderer:setLine(
        8,
        "IAS:" ..
        formatNumber(
            ias,
            "%.0f"
        ) ..
        " KT"
    )

    local tas = nil

    if
        self.aircraft.trueAirSpeed
    then

        tas =
            self.aircraft.trueAirSpeed *
            MPS_TO_KNOT
    end

    renderer:setLine(
        9,
        "TAS:" ..
        formatNumber(
            tas,
            "%.0f"
        ) ..
        " KT"
    )

    --------------------------------------------------------
    -- Mach
    --------------------------------------------------------

    renderer:setLine(
        10,
        "MACH:" ..
        formatNumber(
            self.aircraft.mach,
            "%.3f"
        )
    )

    --------------------------------------------------------
    -- Vertical velocity
    --------------------------------------------------------

    local verticalSpeed = nil

    if
        self.aircraft.verticalVelocity
    then

        verticalSpeed =
            self.aircraft.verticalVelocity *
            MPS_TO_FPM
    end

    renderer:setLine(
        11,
        "V/S:" ..
        formatNumber(
            verticalSpeed,
            "%.0f"
        ) ..
        " FPM"
    )

    --------------------------------------------------------
    -- Angle of attack
    --------------------------------------------------------

    renderer:setLine(
        12,
        "AOA:" ..
        formatDegrees(
            self.aircraft.angleOfAttack
        ) ..
        " DEG"
    )

    --------------------------------------------------------
    -- Pitch
    --------------------------------------------------------

    renderer:setLine(
        13,
        "PITCH:" ..
        formatDegrees(
            self.aircraft.pitch
        ) ..
        " DEG"
    )

    --------------------------------------------------------
    -- Bank
    --------------------------------------------------------

    renderer:setLine(
        14,
        "BANK:" ..
        formatDegrees(
            self.aircraft.bank
        ) ..
        " DEG"
    )
end

------------------------------------------------------------
-- Export
------------------------------------------------------------

return FlightInfo