local Module = {}

Module.id = "FLIGHT_INFO"

Module.menu = {
    label = "FLIGHT INFO",
    page = "FLIGHT_INFO",
    order = 10,
}

function Module.createPages(context)
    local FlightInfo =
        context:load(
            "FlightInfo.lua"
        )

    if
        type(FlightInfo) ~= "table" or
        type(FlightInfo.new) ~= "function"
    then
        error(
            "Invalid FlightInfo.lua"
        )
    end

    return {
        FLIGHT_INFO =
            FlightInfo.new({
                aircraftData =
                    context.aircraftData,
            }),
    }
end

return Module
