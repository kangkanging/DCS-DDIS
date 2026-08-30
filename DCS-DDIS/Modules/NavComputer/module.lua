local Module = {}

Module.id =
"NAV_COMPUTER"

Module.menu = {
    label =
    "NAV COMPUTER",

    page =
    "NAV_COMPUTER",

    order =
        30,
}

function Module.createPages(context)
    local NavComputer =
        context:load(
            "NavComputer.lua"
        )

    if
        type(NavComputer) ~= "table" or
        type(NavComputer.new) ~= "function"
    then
        error(
            "Invalid NavComputer.lua"
        )
    end

    return {
        NAV_COMPUTER =
            NavComputer.new({
                aircraftData =
                    context.aircraftData,
            }),
    }
end

return Module
