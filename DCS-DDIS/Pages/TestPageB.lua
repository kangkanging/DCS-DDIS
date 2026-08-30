local TestPageB = {}
TestPageB.__index = TestPageB

------------------------------------------------------------
-- Constructor
------------------------------------------------------------

function TestPageB.new()

    return
        setmetatable(
            {
                text = "",

                lastInput =
                    "NONE",
            },
            TestPageB
        )
end

------------------------------------------------------------
-- Page lifecycle
------------------------------------------------------------

function TestPageB:onEnter(params)

    self.lastInput =
        "PAGE ENTER"
end

function TestPageB:onExit()
end

------------------------------------------------------------
-- Input
------------------------------------------------------------

function TestPageB:onInput(event)

    --------------------------------------------------------
    -- Character input
    --------------------------------------------------------

    if event.type == "CHAR" then

        if #self.text < 24 then

            self.text =
                self.text ..
                event.value
        end

        self.lastInput =
            "CHAR " ..
            event.value

        return true
    end

    --------------------------------------------------------
    -- Ignore unknown event types
    --------------------------------------------------------

    if event.type ~= "KEY" then
        return false
    end

    --------------------------------------------------------
    -- DEL
    --------------------------------------------------------

    if event.value == "DEL" then

        if #self.text > 0 then

            self.text =
                self.text:sub(
                    1,
                    #self.text - 1
                )
        end

        self.lastInput =
            "DEL"

        return true
    end

    --------------------------------------------------------
    -- Direction keys
    --------------------------------------------------------

    if event.value == "UP" then

        self.lastInput =
            "UP"

        return true
    end

    if event.value == "DOWN" then

        self.lastInput =
            "DOWN"

        return true
    end

    if event.value == "LEFT" then

        self.lastInput =
            "LEFT"

        return true
    end

    if event.value == "RIGHT" then

        self.lastInput =
            "RIGHT"

        return true
    end

    --------------------------------------------------------
    -- ENTER
    --------------------------------------------------------

    if event.value == "ENTER" then

        self.lastInput =
            "ENTER"

        return true
    end

    --------------------------------------------------------
    -- Function keys
    --------------------------------------------------------

    if event.value == "FN1" then

        self.lastInput =
            "FN1"

        return true
    end

    if event.value == "FN2" then

        self.lastInput =
            "FN2"

        return true
    end

    if event.value == "FN3" then

        self.lastInput =
            "FN3"

        return true
    end

    if event.value == "FN4" then

        self.lastInput =
            "FN4"

        return true
    end

    --------------------------------------------------------
    -- BACK intentionally not consumed.
    --------------------------------------------------------

    if event.value == "BACK" then
        return false
    end

    return false
end

------------------------------------------------------------
-- Render
------------------------------------------------------------

function TestPageB:render(renderer)

    renderer:setLine(
        1,
        "PAGE B"
    )

    renderer:setLine(
        3,
        "TEXT:"
    )

    renderer:setLine(
        4,
        self.text
    )

    renderer:setLine(
        6,
        "LAST INPUT:"
    )

    renderer:setLine(
        7,
        self.lastInput
    )

    renderer:setLine(
        10,
        "TYPE CHAR / DEL"
    )

    renderer:setLine(
        11,
        "ARROWS / ENTER / FN"
    )

    renderer:setLine(
        13,
        "BACK : PREVIOUS"
    )

    renderer:setLine(
        14,
        "HOME : MAIN"
    )
end

------------------------------------------------------------
-- Module export
------------------------------------------------------------

return TestPageB