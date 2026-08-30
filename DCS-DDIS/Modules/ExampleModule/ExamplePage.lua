local ExamplePage = {}
ExamplePage.__index =
    ExamplePage

------------------------------------------------------------
-- Constructor
------------------------------------------------------------

function ExamplePage.new(context)
    context =
        context or {}

    return
        setmetatable(
            {
                ------------------------------------------------
                -- Shared project services
                ------------------------------------------------

                aircraft =
                    context.aircraftData,

                ------------------------------------------------
                -- Optional module asset
                ------------------------------------------------

                imagePath =
                    context.imagePath,

                ------------------------------------------------
                -- Page-local state
                ------------------------------------------------

                value =
                    0,

                ------------------------------------------------
                -- Optional dynamic refresh interval
                --
                -- 0.20 = 5 Hz
                -- 0.05 = 20 Hz
                --
                -- 如果页面没有 update()，这个字段没有意义。
                ------------------------------------------------

                updateInterval =
                    0.20,
            },
            ExamplePage
        )
end

------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------

function ExamplePage:onEnter(params)
    --------------------------------------------------------
    -- 页面被激活时调用。
    --
    -- params 来自 SWITCH_PAGE action。
    --------------------------------------------------------
end

function ExamplePage:onExit()
    --------------------------------------------------------
    -- 页面离开时调用。
    --------------------------------------------------------
end

------------------------------------------------------------
-- Dynamic Update
--
-- 静态页面可以直接删除整个 update()。
------------------------------------------------------------

function ExamplePage:update(dt)
    --------------------------------------------------------
    -- dt:
    -- 距离上一次该页面 update() 的时间，单位秒。
    --
    -- return true:
    -- 要求 PageManager 重新 render()
    --
    -- return false / nil:
    -- 不重绘
    --------------------------------------------------------

    return false
end

------------------------------------------------------------
-- Input
------------------------------------------------------------

function ExamplePage:onInput(event)

    --------------------------------------------------------
    -- CHAR example
    --------------------------------------------------------

    if
        event.type == "CHAR"
    then
        local char =
            event.value

        -- 处理字符输入

        return true
    end

    --------------------------------------------------------
    -- KEY example
    --------------------------------------------------------

    if
        event.type == "KEY"
    then

        if event.value == "UP" then
            self.value =
                self.value + 1

            return true
        end

        if event.value == "DOWN" then
            self.value =
                self.value - 1

            return true
        end

        if event.value == "ENTER" then
            return true
        end

        ----------------------------------------------------
        -- BACK 不处理
        --
        -- 返回 false 后由 PageManager 自动执行历史返回。
        ----------------------------------------------------
    end

    return false
end

------------------------------------------------------------
-- Render
------------------------------------------------------------

function ExamplePage:render(
    renderer,
    graphics
)

    --------------------------------------------------------
    -- Text
    --------------------------------------------------------

    renderer:setLine(
        1,
        "EXAMPLE MODULE"
    )

    renderer:setLine(
        3,
        "VALUE:" ..
        tostring(
            self.value
        )
    )

    renderer:setLine(
        14,
        "BACK:RETURN HOME:MAIN"
    )

    --------------------------------------------------------
    -- Graphics
    --
    -- 当前没有图像时无需操作。
    --------------------------------------------------------
end

return ExamplePage