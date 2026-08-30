local MainPage = {}
MainPage.__index = MainPage

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

------------------------------------------------------------
-- Main Page
------------------------------------------------------------

function MainPage.new(context)
    context = context or {}
    local sourceItems = context.items or {}
    local items = {}

    --------------------------------------------------------
    -- Copy menu data.
    -- MainPage does not keep references to module metadata.
    --------------------------------------------------------

    for _, item in ipairs(sourceItems) do
        table.insert(items, {
            label = tostring(item.label or ""),
            page = item.page,
        })
    end

    return setmetatable({
        items = items,
        selected = 1,
        topIndex = 1,
        visibleCount = 9,
    }, MainPage)
end

------------------------------------------------------------
-- Selection
------------------------------------------------------------

function MainPage:_normalizeSelection()
    local count = #self.items

    if count <= 0 then
        self.selected = 1
        self.topIndex = 1
        return
    end

    self.selected = clamp(self.selected, 1, count)

    local maxTop = math.max(1, count - self.visibleCount + 1)
    self.topIndex = clamp(self.topIndex, 1, maxTop)

    --------------------------------------------------------
    -- Selection above viewport
    --------------------------------------------------------

    if self.selected < self.topIndex then
        self.topIndex = self.selected
    end

    --------------------------------------------------------
    -- Selection below viewport
    --------------------------------------------------------

    local bottom = self.topIndex + self.visibleCount - 1

    if self.selected > bottom then
        self.topIndex = self.selected - self.visibleCount + 1
    end
end

------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------

function MainPage:onEnter(params)
    self:_normalizeSelection()
end

function MainPage:onExit()
end

------------------------------------------------------------
-- Input
------------------------------------------------------------

function MainPage:onInput(event)
    if event.type ~= "KEY" then
        return false
    end

    local count = #self.items

    --------------------------------------------------------
    -- UP
    --------------------------------------------------------

    if event.value == "UP" then
        if count > 0 and self.selected > 1 then
            self.selected = self.selected - 1
            self:_normalizeSelection()
        end
        return true
    end

    --------------------------------------------------------
    -- DOWN
    --------------------------------------------------------

    if event.value == "DOWN" then
        if count > 0 and self.selected < count then
            self.selected = self.selected + 1
            self:_normalizeSelection()
        end
        return true
    end

    --------------------------------------------------------
    -- ENTER
    --------------------------------------------------------

    if event.value == "ENTER" then
        local item = self.items[self.selected]

        if item and item.page then
            return true, {
                type = "SWITCH_PAGE",
                page = item.page,
            }
        end

        return true
    end

    --------------------------------------------------------
    -- FN1
    --------------------------------------------------------

    if event.value == "FN1" then
        return true, {
            type = "SWITCH_PAGE",
            page = "MAIN_HELP",
        }
    end

    --------------------------------------------------------
    -- BACK falls through to PageManager
    --------------------------------------------------------

    return false
end

------------------------------------------------------------
-- Render
------------------------------------------------------------

function MainPage:render(renderer, graphics)
    renderer:setLine(1, "DCS-DDIS PAGE SYSTEM")
    renderer:setLine(2, "MAIN MENU")

    local count = #self.items

    --------------------------------------------------------
    -- Upper continuation indicator
    --------------------------------------------------------

    if self.topIndex > 1 then
        renderer:setLine(3, "              /\\")
    end

    --------------------------------------------------------
    -- No modules
    --------------------------------------------------------

    if count == 0 then
        renderer:setLine(7, "NO MODULES INSTALLED")
        renderer:setLine(14, "FN1:HELP")
        return
    end

    --------------------------------------------------------
    -- Menu rows 4-12
    --------------------------------------------------------

    for visibleIndex = 1, self.visibleCount do
        local itemIndex = self.topIndex + visibleIndex - 1
        local item = self.items[itemIndex]

        if item then
            local prefix = (itemIndex == self.selected) and ">" or " "
            renderer:setLine(3 + visibleIndex, prefix .. tostring(item.label))
        end
    end

    --------------------------------------------------------
    -- Lower continuation indicator
    --------------------------------------------------------

    local bottomIndex = self.topIndex + self.visibleCount - 1

    if bottomIndex < count then
        renderer:setLine(13, "              \\/")
    end

    renderer:setLine(14, "FN1:HELP")
end

------------------------------------------------------------
-- Help Page
------------------------------------------------------------

local HelpPage = {}
HelpPage.__index = HelpPage

function HelpPage.new()
    return setmetatable({}, HelpPage)
end

function HelpPage:onEnter(params)
end

function HelpPage:onExit()
end

function HelpPage:onInput(event)
    return false
end

function HelpPage:render(renderer, graphics)
    renderer:setLine(1, "DCS-DDIS v0.1")
    renderer:setLine(2, "------------------------------")
    renderer:setLine(3, "CTRL+SHIFT+M : SHOW/HIDE")
    renderer:setLine(4, "UP/DOWN      : SELECT")
    renderer:setLine(5, "ENTER        : OPEN/CONFIRM")
    renderer:setLine(6, "BACK         : RETURN")
    renderer:setLine(7, "HOME         : MAIN MENU")
    renderer:setLine(8, "DEL          : DELETE")
    renderer:setLine(9, "FN1          : HELP")
    renderer:setLine(10, "A-Z / 0-9    : INPUT")
    renderer:setLine(11, " ")
    renderer:setLine(12, "KEY FUNCTIONS VARY BY PAGE")
    renderer:setLine(13, "FLIGHT DATA REQUIRES MISSION")
    renderer:setLine(14, "BACK:RETURN   HOME:MAIN")
end

MainPage.HelpPage = HelpPage

return MainPage