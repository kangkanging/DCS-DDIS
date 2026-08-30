local EmptyPage = {}
EmptyPage.__index = EmptyPage

------------------------------------------------------------
-- Constructor
------------------------------------------------------------

function EmptyPage.new()

    return
        setmetatable(
            {},
            EmptyPage
        )
end

------------------------------------------------------------
-- Page lifecycle
------------------------------------------------------------

function EmptyPage:onEnter(params)
end

function EmptyPage:onExit()
end

------------------------------------------------------------
-- Input
------------------------------------------------------------

function EmptyPage:onInput(event)

    --------------------------------------------------------
    -- Empty page consumes no input.
    --
    -- BACK:
    -- PageManager returns to previous page.
    --
    -- HOME:
    -- PageManager returns to MAIN.
    --------------------------------------------------------

    return false
end

------------------------------------------------------------
-- Render
------------------------------------------------------------

function EmptyPage:render(renderer)

    renderer:setLine(1, "test1")
    renderer:setLine(2, "")
    renderer:setLine(3, "")
    renderer:setLine(4, "")
    renderer:setLine(5, "")
    renderer:setLine(6, "")
    renderer:setLine(7, "")
    renderer:setLine(8, "")
    renderer:setLine(9, "")
    renderer:setLine(10, "")
    renderer:setLine(11, "")
    renderer:setLine(12, "")
    renderer:setLine(13, "")
    renderer:setLine(14, "")
end

------------------------------------------------------------
-- Export
------------------------------------------------------------

return EmptyPage