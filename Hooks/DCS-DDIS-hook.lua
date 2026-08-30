local lfs = require("lfs")
package.path = package.path .. ";.\\Scripts\\?.lua;.\\Scripts\\UI\\?.lua;"

local DialogLoader = require("DialogLoader")
local dxgui = require("dxgui")

------------------------------------------------------------
-- Configuration
------------------------------------------------------------

local WINDOW_W, WINDOW_H = 600, 1000

local DISPLAY_X, DISPLAY_Y = 80, 70
local DISPLAY_W, DISPLAY_H = 450, 370

local GRAPHIC_W, GRAPHIC_H = 440, 360
local GRAPHIC_LAYER_COUNT = 10

local DISPLAY_ROWS, DISPLAY_COLS = 14, 30

local DISPLAY_FONT = "CONSOLA.TTF"
local DISPLAY_FONT_SIZE = 25
local DISPLAY_LINE_HEIGHT = 25
local DISPLAY_TEXT_COLOR = "0x0a9f1aff"

local BUTTON_COUNT = 56
local BUTTON_ATLAS_W, BUTTON_ATLAS_H = 800, 350

------------------------------------------------------------
-- Aircraft data: 20 Hz
------------------------------------------------------------

local DATA_UPDATE_INTERVAL = 0.05

------------------------------------------------------------
-- Default dynamic page: 5 Hz
------------------------------------------------------------

local DEFAULT_PAGE_UPDATE_INTERVAL = 0.20

local CREATE_FRAME = 300
local HOTKEY = "Ctrl+Shift+M"

------------------------------------------------------------
-- Project Paths
--
-- IMPORTANT:
-- Hook: Saved Games\DCS\Scripts\Hooks\DCS-DDIS-hook.lua
-- Project root: Saved Games\DCS\Scripts\DCS-DDIS\
------------------------------------------------------------

local rootPath = lfs.writedir() .. "Scripts\\DCS-DDIS\\"
local dlgPath = rootPath .. "DCS-DDIS-dxgui.dlg"
local imagePath = rootPath .. "Images\\bak.dds"
local buttonAtlasPath = rootPath .. "Images\\buttonAtlas1.png"
local pagesPath = rootPath .. "Pages\\"
local dataPath = rootPath .. "Data\\"
local modulesPath = rootPath .. "Modules\\"

------------------------------------------------------------
-- Runtime
------------------------------------------------------------

local window
local imagePanel
local displayArea

local displayLines = {}
local graphicLayers = {}
local buttons = {}

local frameCounter = 0
local shown = false

local dragging = false
local dragMouseX = 0
local dragMouseY = 0
local dragWindowX = 0
local dragWindowY = 0

local aircraftData
local pageManager

local lastRuntimeTime
local lastDataUpdateTime

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function logInfo(text)
    net.log("[DCS-DDIS] " .. tostring(text))
end

local function fileExists(path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

local function requireFile(path)
    if not fileExists(path) then
        error("File not found: " .. tostring(path))
    end
end

local function loadLuaFile(path)
    requireFile(path)

    local chunk, loadError = loadfile(path)
    if not chunk then
        error("Failed to load Lua file: " .. tostring(path) .. " / " .. tostring(loadError))
    end

    local ok, result = pcall(chunk)
    if not ok then
        error("Failed to execute Lua file: " .. tostring(path) .. " / " .. tostring(result))
    end

    return result
end

local function transparentBkg()
    return {
        left_top      = "0x00000000",
        center_top    = "0x00000000",
        right_top     = "0x00000000",
        left_center   = "0x00000000",
        center_center = "0x00000000",
        right_center  = "0x00000000",
        left_bottom   = "0x00000000",
        center_bottom = "0x00000000",
        right_bottom  = "0x00000000",
    }
end

------------------------------------------------------------
-- DisplayRenderer
------------------------------------------------------------

local DisplayRenderer = {}
DisplayRenderer.__index = DisplayRenderer

function DisplayRenderer.new(rows, cols)
    local self = setmetatable({
        rows = rows,
        cols = cols,
        buffer = {},
        adapter = nil,
    }, DisplayRenderer)

    for row = 1, rows do
        self.buffer[row] = {}
        for col = 1, cols do
            self.buffer[row][col] = " "
        end
    end

    return self
end

function DisplayRenderer:setAdapter(adapter)
    self.adapter = adapter
end

function DisplayRenderer:clear()
    for row = 1, self.rows do
        for col = 1, self.cols do
            self.buffer[row][col] = " "
        end
    end
end

function DisplayRenderer:clearLine(row)
    if row < 1 or row > self.rows then return end
    for col = 1, self.cols do
        self.buffer[row][col] = " "
    end
end

function DisplayRenderer:setChar(row, col, char)
    if row < 1 or row > self.rows then return end
    if col < 1 or col > self.cols then return end
    self.buffer[row][col] = (char and char ~= "") and char or " "
end

function DisplayRenderer:getChar(row, col)
    if row < 1 or row > self.rows then return nil end
    if col < 1 or col > self.cols then return nil end
    return self.buffer[row][col]
end

function DisplayRenderer:setLine(row, text)
    if row < 1 or row > self.rows then return end
    self:clearLine(row)
    text = tostring(text or "")
    for col = 1, math.min(#text, self.cols) do
        self.buffer[row][col] = text:sub(col, col)
    end
end

function DisplayRenderer:write(row, col, text)
    if row < 1 or row > self.rows then return end
    if col < 1 or col > self.cols then return end
    text = tostring(text or "")
    local source = 1
    while source <= #text and col <= self.cols do
        self.buffer[row][col] = text:sub(source, source)
        source = source + 1
        col = col + 1
    end
end

function DisplayRenderer:getLine(row)
    if row < 1 or row > self.rows then return "" end
    return table.concat(self.buffer[row])
end

function DisplayRenderer:flush()
    if self.adapter then
        self.adapter:render(self)
    end
end

------------------------------------------------------------
-- Display Adapter
------------------------------------------------------------

local function createDisplayAdapter(lines)
    return {
        render = function(self, renderer)
            for row = 1, renderer.rows do
                lines[row]:setText(renderer:getLine(row))
            end
        end,
    }
end

local renderer = DisplayRenderer.new(DISPLAY_ROWS, DISPLAY_COLS)

------------------------------------------------------------
-- GraphicRenderer
--
-- All GraphicLayers: 440 x 360
-- Atlas source: 1-based
-- DXGUI picture translation: offset = -(source - 1)
------------------------------------------------------------

local GraphicRenderer = {}
GraphicRenderer.__index = GraphicRenderer

function GraphicRenderer.new(layerCount, viewportW, viewportH)
    local self = setmetatable({
        layerCount = layerCount,
        viewportW = viewportW,
        viewportH = viewportH,
        layers = {},
        adapter = nil,
    }, GraphicRenderer)

    for index = 1, layerCount do
        self.layers[index] = {
            visible = false,
            file = nil,
            textureWidth = 0,
            textureHeight = 0,
            sourceX = 1,
            sourceY = 1,
            dirty = true,
        }
    end

    return self
end

function GraphicRenderer:setAdapter(adapter)
    self.adapter = adapter
end

function GraphicRenderer:_getLayer(index)
    if type(index) ~= "number" or index < 1 or index > self.layerCount then
        error("Invalid graphic layer: " .. tostring(index))
    end
    return self.layers[index]
end

------------------------------------------------------------
-- Texture
------------------------------------------------------------

function GraphicRenderer:setTexture(index, file, textureWidth, textureHeight)
    local layer = self:_getLayer(index)

    if type(file) ~= "string" or file == "" then
        error("Graphic texture path required")
    end

    if type(textureWidth) ~= "number" or type(textureHeight) ~= "number" or
       textureWidth < self.viewportW or textureHeight < self.viewportH then
        error("Graphic texture must be at least " .. self.viewportW .. "x" .. self.viewportH)
    end

    if layer.file ~= file or layer.textureWidth ~= textureWidth or layer.textureHeight ~= textureHeight then
        layer.file = file
        layer.textureWidth = textureWidth
        layer.textureHeight = textureHeight
        layer.dirty = true
    end
end

------------------------------------------------------------
-- Absolute 1-based Atlas source
------------------------------------------------------------

function GraphicRenderer:setSource(index, sourceX, sourceY)
    local layer = self:_getLayer(index)

    sourceX = math.floor(tonumber(sourceX) or 1)
    sourceY = math.floor(tonumber(sourceY) or 1)

    local maxX = 1
    local maxY = 1

    if layer.textureWidth >= self.viewportW then
        maxX = layer.textureWidth - self.viewportW + 1
    end

    if layer.textureHeight >= self.viewportH then
        maxY = layer.textureHeight - self.viewportH + 1
    end

    sourceX = math.max(1, math.min(sourceX, maxX))
    sourceY = math.max(1, math.min(sourceY, maxY))

    if layer.sourceX ~= sourceX or layer.sourceY ~= sourceY then
        layer.sourceX = sourceX
        layer.sourceY = sourceY
        layer.dirty = true
    end
end

function GraphicRenderer:getSource(index)
    local layer = self:_getLayer(index)
    return layer.sourceX, layer.sourceY
end

------------------------------------------------------------
-- Low-level Frame
------------------------------------------------------------

function GraphicRenderer:setFrame(index, file, textureWidth, textureHeight, sourceX, sourceY)
    self:setTexture(index, file, textureWidth, textureHeight)
    self:setSource(index, sourceX, sourceY)
    self:show(index)
end

------------------------------------------------------------
-- High-level Atlas Frame
------------------------------------------------------------

function GraphicRenderer:setAtlasFrame(index, atlas, frameIndex, frameOffsetX, frameOffsetY)
    if type(atlas) ~= "table" then
        error("Atlas descriptor required")
    end

    local file = atlas.file
    local width = tonumber(atlas.width)
    local height = tonumber(atlas.height)
    local frameWidth = tonumber(atlas.frameWidth)
    local frameHeight = tonumber(atlas.frameHeight)
    local columns = tonumber(atlas.columns)

    if not file or not width or not height or not frameWidth or not frameHeight or not columns then
        error("Invalid Atlas descriptor")
    end

    columns = math.floor(columns)

    if columns < 1 or frameWidth < self.viewportW or frameHeight < self.viewportH then
        error("Atlas frame smaller than graphic viewport")
    end

    local rows = math.floor(height / frameHeight)
    local physicalCount = columns * rows
    local frameCount = math.floor(tonumber(atlas.frameCount) or physicalCount)
    frameCount = math.min(frameCount, physicalCount)

    frameIndex = math.floor(tonumber(frameIndex) or 1)
    frameIndex = math.max(1, math.min(frameIndex, frameCount))

    local zeroIndex = frameIndex - 1
    local column = zeroIndex % columns
    local row = math.floor(zeroIndex / columns)

    local baseX = 1 + column * frameWidth
    local baseY = 1 + row * frameHeight

    local maxOffsetX = frameWidth - self.viewportW
    local maxOffsetY = frameHeight - self.viewportH

    frameOffsetX = math.floor(tonumber(frameOffsetX) or 0)
    frameOffsetY = math.floor(tonumber(frameOffsetY) or 0)

    frameOffsetX = math.max(0, math.min(frameOffsetX, maxOffsetX))
    frameOffsetY = math.max(0, math.min(frameOffsetY, maxOffsetY))

    local sourceX = baseX + frameOffsetX
    local sourceY = baseY + frameOffsetY

    self:setFrame(index, file, width, height, sourceX, sourceY)

    return frameIndex, sourceX, sourceY, frameOffsetX, frameOffsetY
end

------------------------------------------------------------
-- Visibility
------------------------------------------------------------

function GraphicRenderer:show(index)
    local layer = self:_getLayer(index)
    if not layer.visible then
        layer.visible = true
        layer.dirty = true
    end
end

function GraphicRenderer:hide(index)
    local layer = self:_getLayer(index)
    if layer.visible then
        layer.visible = false
        layer.dirty = true
    end
end

function GraphicRenderer:hideAll()
    for index = 1, self.layerCount do
        self:hide(index)
    end
end

function GraphicRenderer:isVisible(index)
    return self:_getLayer(index).visible
end

function GraphicRenderer:flush()
    if self.adapter then
        self.adapter:render(self)
    end
end

local graphics = GraphicRenderer.new(GRAPHIC_LAYER_COUNT, GRAPHIC_W, GRAPHIC_H)

------------------------------------------------------------
-- Graphic DXGUI Adapter
------------------------------------------------------------

local function makeGraphicPicture(layer)
    return {
        color = "0xffffffff",
        file = layer.file,
        size = {
            horz = layer.textureWidth,
            vert = layer.textureHeight,
        },
        horzAlign = {
            offset = -(layer.sourceX - 1),
            type = "min",
        },
        vertAlign = {
            offset = -(layer.sourceY - 1),
            type = "min",
        },
    }
end

local function configureGraphicControl(control)
    local skin = control:getSkin()
    if not skin or not skin.skinData or not skin.skinData.states then
        error("Graphic layer skin states not found")
    end

    for _, stateList in pairs(skin.skinData.states) do
        if type(stateList) == "table" then
            for _, state in pairs(stateList) do
                if type(state) == "table" then
                    state.bkg = transparentBkg()
                    state.text = state.text or {}
                    state.text.color = "0x00000000"
                end
            end
        end
    end

    control:setSkin(skin)
    control:setVisible(false)
end

local function applyGraphicLayer(control, layer)
    if not layer.file then
        control:setVisible(false)
        layer.dirty = false
        return
    end

    local skin = control:getSkin()
    if not skin or not skin.skinData or not skin.skinData.states then
        error("Graphic layer skin states not found")
    end

    for _, stateList in pairs(skin.skinData.states) do
        if type(stateList) == "table" then
            for _, state in pairs(stateList) do
                if type(state) == "table" then
                    state.bkg = transparentBkg()
                    state.picture = makeGraphicPicture(layer)
                end
            end
        end
    end

    control:setSkin(skin)
    control:setVisible(layer.visible)
    layer.dirty = false
end

local function createGraphicAdapter(controls)
    return {
        render = function(self, graphicRenderer)
            for index = 1, graphicRenderer.layerCount do
                local layer = graphicRenderer.layers[index]
                if layer.dirty then
                    applyGraphicLayer(controls[index], layer)
                end
            end
        end,
    }
end

------------------------------------------------------------
-- Input Router
------------------------------------------------------------

local INPUT_CHAR = "CHAR"
local INPUT_KEY = "KEY"

local function C(value)
    return { type = INPUT_CHAR, value = value }
end

local function K(value)
    return { type = INPUT_KEY, value = value }
end

------------------------------------------------------------
-- Physical Button -> Semantic Input
------------------------------------------------------------

local ButtonInputMap = {
    [1]=C("1"),  [2]=C("2"),  [3]=C("3"),  [4]=C("4"),  [5]=C("5"),
    [6]=K("DEL"), [7]=K("UP"),  [8]=K("HOME"),
    [9]=C("6"),  [10]=C("7"), [11]=C("8"), [12]=C("9"), [13]=C("0"),
    [14]=K("LEFT"), [15]=K("DOWN"), [16]=K("RIGHT"),
    [17]=C("A"), [18]=C("B"), [19]=C("C"), [20]=C("D"), [21]=C("E"), [22]=C("F"),
    [23]=K("ENTER"), [24]=K("BACK"),
    [25]=C("G"), [26]=C("H"), [27]=C("I"), [28]=C("J"), [29]=C("K"), [30]=C("L"),
    [31]=K("FN1"), [32]=K("FN2"),
    [33]=C("M"), [34]=C("N"), [35]=C("O"), [36]=C("P"), [37]=C("Q"), [38]=C("R"),
    [39]=K("FN3"), [40]=K("FN4"),
    [41]=C("S"), [42]=C("T"), [43]=C("U"), [44]=C("V"), [45]=C("W"), [46]=C("X"),
    [49]=C("Y"), [50]=C("Z"),
}

local InputRouter = {}
InputRouter.__index = InputRouter

function InputRouter.new(buttonMap)
    return setmetatable({
        buttonMap = buttonMap or {},
        handler = nil,
    }, InputRouter)
end

function InputRouter:setHandler(handler)
    if handler ~= nil and type(handler) ~= "function" then
        error("InputRouter handler must be a function or nil")
    end
    self.handler = handler
end

function InputRouter:dispatchButton(index)
    local mapping = self.buttonMap[index]
    if not mapping then
        logInfo("Input ignored: unmapped Button " .. tostring(index))
        return
    end

    local event = {
        type = mapping.type,
        value = mapping.value,
    }

    if not self.handler then
        logInfo("Input dropped: no handler")
        return
    end

    self.handler(event)
end

local inputRouter = InputRouter.new(ButtonInputMap)

------------------------------------------------------------
-- PageManager
------------------------------------------------------------

local PageManager = {}
PageManager.__index = PageManager

function PageManager.new(rendererObject, graphicsObject, homePageId)
    return setmetatable({
        renderer = rendererObject,
        graphics = graphicsObject,
        pages = {},
        currentPage = nil,
        currentPageId = nil,
        history = {},
        homePageId = homePageId,
        updateAccumulator = 0,
    }, PageManager)
end

function PageManager:register(id, page)
    if type(id) ~= "string" or id == "" then
        error("Page id is required")
    end
    if type(page) ~= "table" then
        error("Page must be a table: " .. tostring(id))
    end
    if type(page.render) ~= "function" then
        error("Page render() missing: " .. tostring(id))
    end
    if type(page.onInput) ~= "function" then
        error("Page onInput() missing: " .. tostring(id))
    end
    if self.pages[id] then
        error("Page already registered: " .. tostring(id))
    end

    self.pages[id] = page
    logInfo("Page registered: " .. tostring(id))
end

function PageManager:render()
    if not self.currentPage then return end

    self.renderer:clear()
    self.currentPage:render(self.renderer, self.graphics)
    self.renderer:flush()

    if self.graphics then
        self.graphics:flush()
    end
end

function PageManager:_activate(id, params, pushHistory)
    local target = self.pages[id]
    if not target then
        error("Page not registered: " .. tostring(id))
    end

    if self.currentPageId == id then
        self:render()
        return
    end

    if pushHistory and self.currentPageId then
        table.insert(self.history, self.currentPageId)
    end

    if self.currentPage and type(self.currentPage.onExit) == "function" then
        self.currentPage:onExit()
    end

    -- Shared graphic layers must not leak between pages.
    if self.graphics then
        self.graphics:hideAll()
    end

    self.updateAccumulator = 0
    self.currentPageId = id
    self.currentPage = target

    if type(target.onEnter) == "function" then
        target:onEnter(params)
    end

    logInfo("Page active: " .. tostring(id))
    self:render()
end

function PageManager:start(id)
    self.history = {}
    self.currentPage = nil
    self.currentPageId = nil
    self.updateAccumulator = 0
    self:_activate(id, nil, false)
end

function PageManager:switch(id, params)
    self:_activate(id, params, true)
end

function PageManager:goHome()
    self.history = {}
    self:_activate(self.homePageId, nil, false)
end

function PageManager:back()
    local previous = table.remove(self.history)
    if previous then
        self:_activate(previous, nil, false)
        return
    end

    self:goHome()
end

function PageManager:executeAction(action)
    if not action then return false end

    if action.type == "SWITCH_PAGE" then
        self:switch(action.page, action.params)
        return true
    end

    error("Unknown page action: " .. tostring(action.type))
end

function PageManager:handleInput(event)
    if not self.currentPage then return false end

    -- HOME is global
    if event.type == INPUT_KEY and event.value == "HOME" then
        self:goHome()
        return true
    end

    local handled, action = self.currentPage:onInput(event)

    if action then
        self:executeAction(action)
        return true
    end

    if handled then
        self:render()
        return true
    end

    -- BACK fallback
    if event.type == INPUT_KEY and event.value == "BACK" then
        self:back()
        return true
    end

    return false
end

function PageManager:update(dt)
    if not self.currentPage then return end
    if type(self.currentPage.update) ~= "function" then return end

    local interval = tonumber(self.currentPage.updateInterval) or DEFAULT_PAGE_UPDATE_INTERVAL
    self.updateAccumulator = self.updateAccumulator + (dt or 0)

    if interval > 0 and self.updateAccumulator < interval then
        return
    end

    local elapsed = self.updateAccumulator
    self.updateAccumulator = 0

    local dirty = self.currentPage:update(elapsed)
    if dirty then
        self:render()
    end
end

------------------------------------------------------------
-- Aircraft Data System
------------------------------------------------------------

local function createDataSystem()
    local AircraftData = loadLuaFile(dataPath .. "AircraftData.lua")

    if type(AircraftData) ~= "table" or type(AircraftData.new) ~= "function" then
        error("Invalid AircraftData.lua")
    end

    aircraftData = AircraftData.new()
    aircraftData:update()

    logInfo("AircraftData ready")
end

------------------------------------------------------------
-- Module System
------------------------------------------------------------

local function createModuleContext(modulePath)
    local context = {
        modulePath = modulePath,
        aircraftData = aircraftData,
    }

    function context:path(relativePath)
        return self.modulePath .. relativePath
    end

    function context:asset(relativePath)
        local path = self:path(relativePath)
        requireFile(path)
        return path
    end

    function context:load(relativePath)
        return loadLuaFile(self:path(relativePath))
    end

    return context
end

------------------------------------------------------------
-- Discover Modules
------------------------------------------------------------

local function discoverModules()
    local attributes = lfs.attributes(modulesPath)
    if not attributes or attributes.mode ~= "directory" then
        error("Modules directory not found: " .. modulesPath)
    end

    local result = {}

    for name in lfs.dir(modulesPath) do
        if name ~= "." and name ~= ".." then
            local modulePath = modulesPath .. name .. "\\"
            local attr = lfs.attributes(modulePath)

            if attr and attr.mode == "directory" then
                local entryPath = modulePath .. "module.lua"

                if fileExists(entryPath) then
                    table.insert(result, {
                        folder = name,
                        path = modulePath,
                        entryPath = entryPath,
                    })
                else
                    logInfo("Module folder ignored (module.lua missing): " .. name)
                end
            end
        end
    end

    table.sort(result, function(a, b) return a.folder < b.folder end)
    return result
end

------------------------------------------------------------
-- Load / Register Modules
------------------------------------------------------------

local function registerModules(manager)
    local discovered = discoverModules()
    local registeredModules = {}
    local menuItems = {}

    for _, entry in ipairs(discovered) do
        logInfo("Loading module: " .. entry.folder)

        local module = loadLuaFile(entry.entryPath)
        if type(module) ~= "table" then
            error("Invalid module.lua: " .. entry.entryPath)
        end

        if type(module.id) ~= "string" or module.id == "" then
            error("Module id missing: " .. entry.folder)
        end

        if registeredModules[module.id] then
            error("Duplicate module id: " .. module.id)
        end

        if type(module.createPages) ~= "function" then
            error("Module createPages() missing: " .. module.id)
        end

        local context = createModuleContext(entry.path)
        local pages = module.createPages(context)

        if type(pages) ~= "table" then
            error("Module createPages() must return a table: " .. module.id)
        end

        local pageCount = 0
        for pageId, page in pairs(pages) do
            manager:register(pageId, page)
            pageCount = pageCount + 1
        end

        if pageCount == 0 then
            error("Module contains no pages: " .. module.id)
        end

        registeredModules[module.id] = true

        if module.menu then
            if type(module.menu) ~= "table" then
                error("Invalid module menu: " .. module.id)
            end

            local label = module.menu.label
            local page = module.menu.page
            local order = tonumber(module.menu.order) or 100

            if type(label) ~= "string" or label == "" then
                error("Module menu label missing: " .. module.id)
            end

            if type(page) ~= "string" or page == "" then
                error("Module menu page missing: " .. module.id)
            end

            if not manager.pages[page] then
                error("Module menu page not registered: " .. module.id .. " / " .. page)
            end

            table.insert(menuItems, {
                label = label,
                page = page,
                order = order,
            })
        end

        logInfo("Module registered: " .. module.id .. " / pages=" .. tostring(pageCount))
    end

    table.sort(menuItems, function(a, b)
        if a.order == b.order then
            return a.label < b.label
        end
        return a.order < b.order
    end)

    logInfo("Modules loaded: " .. tostring(#discovered))
    return menuItems
end

------------------------------------------------------------
-- Page System
------------------------------------------------------------

local function createPageSystem()
    local MainPage = loadLuaFile(pagesPath .. "MainPage.lua")

    if type(MainPage) ~= "table" or type(MainPage.new) ~= "function" then
        error("Invalid MainPage.lua")
    end

    if type(MainPage.HelpPage) ~= "table" or type(MainPage.HelpPage.new) ~= "function" then
        error("Invalid MainPage.HelpPage")
    end

    pageManager = PageManager.new(renderer, graphics, "MAIN")

    local menuItems = registerModules(pageManager)

    pageManager:register("MAIN", MainPage.new({ items = menuItems }))
    pageManager:register("MAIN_HELP", MainPage.HelpPage.new())

    logInfo("Page system ready")
end

------------------------------------------------------------
-- Application Input
------------------------------------------------------------

local function installApplicationInputHandler()
    inputRouter:setHandler(function(event)
        local ok, err = pcall(function()
            pageManager:handleInput(event)
        end)

        if not ok then
            logInfo("PAGE ERROR: " .. tostring(err))
        end
    end)

    logInfo("Application input handler installed")
end

------------------------------------------------------------
-- Window Position
------------------------------------------------------------

local function clampPosition(x, y)
    local screenW, screenH = dxgui.GetScreenSize()

    x = math.max(0, math.min(x, math.max(0, screenW - WINDOW_W)))
    y = math.max(0, math.min(y, math.max(0, screenH - WINDOW_H)))

    return x, y
end

local function centerWindow()
    local screenW, screenH = dxgui.GetScreenSize()

    local x = math.floor((screenW - WINDOW_W) / 2)
    local y = math.floor((screenH - WINDOW_H) / 2)

    x, y = clampPosition(x, y)
    window:setPosition(x, y)
end

------------------------------------------------------------
-- Display Controls
------------------------------------------------------------

local function configureDisplayLine(line)
    local skin = line:getSkin()
    if not skin or not skin.skinData or not skin.skinData.states then
        error("Display line skin states not found")
    end

    for _, stateList in pairs(skin.skinData.states) do
        if type(stateList) == "table" then
            for _, state in pairs(stateList) do
                if type(state) == "table" then
                    state.text = state.text or {}
                    state.text.color = DISPLAY_TEXT_COLOR
                    state.text.font = DISPLAY_FONT
                    state.text.fontSize = DISPLAY_FONT_SIZE
                    state.text.lineHeight = DISPLAY_LINE_HEIGHT
                    state.bkg = transparentBkg()
                end
            end
        end
    end

    line:setSkin(skin)
end

local function collectDisplayLines()
    displayLines = {}

    for row = 1, DISPLAY_ROWS do
        local name = string.format("DisplayLine%02d", row)
        local line = displayArea[name]

        if not line then
            error(name .. " not found")
        end

        displayLines[row] = line
        configureDisplayLine(line)
    end

    logInfo(DISPLAY_ROWS .. " display lines installed")
end

------------------------------------------------------------
-- Graphic Controls
------------------------------------------------------------

local function collectGraphicLayers()
    graphicLayers = {}

    for index = 1, GRAPHIC_LAYER_COUNT do
        local name = string.format("GraphicLayer%02d", index)
        local layer = displayArea[name]

        if not layer then
            error(name .. " not found")
        end

        graphicLayers[index] = layer
        configureGraphicControl(layer)
    end

    logInfo(GRAPHIC_LAYER_COUNT .. " graphic layers installed")
end

------------------------------------------------------------
-- Drag
------------------------------------------------------------

local function endDrag()
    dragging = false
end

local function beginDrag(x, y)
    dragging = true
    dragMouseX = x
    dragMouseY = y
    dragWindowX, dragWindowY = window:getPosition()
end

local function moveDrag(x, y)
    if not dragging then return end

    local rawX = dragWindowX + x - dragMouseX
    local rawY = dragWindowY + y - dragMouseY

    local newX, newY = clampPosition(rawX, rawY)

    window:setPosition(newX, newY)

    if newX ~= rawX then
        dragWindowX = newX
        dragMouseX = x
    end

    if newY ~= rawY then
        dragWindowY = newY
        dragMouseY = y
    end
end

local function installDragSurface(surface)
    surface:addMouseDownCallback(function(self, x, y, button)
        if button == 1 and shown then
            beginDrag(x, y)
        end
    end)

    surface:addMouseMoveCallback(function(self, x, y)
        moveDrag(x, y)
    end)

    surface:addMouseUpCallback(function(self, x, y, button)
        if button == 1 then endDrag() end
    end)
end

------------------------------------------------------------
-- Drag Cancellation
------------------------------------------------------------

local function isInsideDisplayArea(x, y)
    return x >= DISPLAY_X and x < DISPLAY_X + DISPLAY_W and
           y >= DISPLAY_Y and y < DISPLAY_Y + DISPLAY_H
end

local function installDragCancelSurface(surface)
    surface:addMouseMoveCallback(function(self, x, y)
        if dragging and not isInsideDisplayArea(x, y) then
            endDrag()
        end
    end)

    surface:addMouseDownCallback(function(self, x, y, button)
        if button == 1 and not isInsideDisplayArea(x, y) then
            endDrag()
        end
    end)

    surface:addMouseUpCallback(function(self, x, y, button)
        if button == 1 then endDrag() end
    end)
end

------------------------------------------------------------
-- Visibility
------------------------------------------------------------

local function setShown(value)
    endDrag()

    if value then
        local x, y = window:getPosition()
        x, y = clampPosition(x, y)
        window:setPosition(x, y)
    end

    imagePanel:setVisible(value)
    displayArea:setVisible(value)

    for _, button in ipairs(buttons) do
        button:setVisible(value)
    end

    window:setHasCursor(value)
    shown = value

    logInfo(value and "Window shown" or "Window hidden")
end

local function installHotkey()
    window:addHotKeyCallback(HOTKEY, function()
        setShown(not shown)
    end)
end

------------------------------------------------------------
-- Button Visual Map
------------------------------------------------------------

local function V(rx, ry, px, py, dx, dy)
    return {
        released = { x = rx, y = ry },
        pressed  = { x = px, y = py },
        disabled = { x = dx or rx, y = dy or ry },
    }
end

local ButtonVisualMap = {
    [1]=V(1,1,401,1),     [2]=V(51,1,451,1),    [3]=V(101,1,501,1),   [4]=V(151,1,551,1),
    [5]=V(201,1,601,1),   [6]=V(251,1,651,1),   [7]=V(301,1,701,1),   [8]=V(351,1,751,1),

    [9]=V(1,51,401,51),   [10]=V(51,51,451,51), [11]=V(101,51,501,51), [12]=V(151,51,551,51),
    [13]=V(201,51,601,51),[14]=V(251,51,651,51),[15]=V(301,51,701,51),[16]=V(351,51,751,51),

    [17]=V(1,101,401,101),[18]=V(51,101,451,101),[19]=V(101,101,501,101),[20]=V(151,101,551,101),
    [21]=V(201,101,601,101),[22]=V(251,101,651,101),[23]=V(301,101,701,101),[24]=V(351,101,751,101),

    [25]=V(1,151,401,151),[26]=V(51,151,451,151),[27]=V(101,151,501,151),[28]=V(151,151,551,151),
    [29]=V(201,151,601,151),[30]=V(251,151,651,151),[31]=V(301,151,701,151),[32]=V(351,151,751,151),

    [33]=V(1,201,401,201),[34]=V(51,201,451,201),[35]=V(101,201,501,201),[36]=V(151,201,551,201),
    [37]=V(201,201,601,201),[38]=V(251,201,651,201),[39]=V(301,201,701,201),[40]=V(351,201,751,201),

    [41]=V(1,251,401,251),[42]=V(51,251,451,251),[43]=V(101,251,501,251),[44]=V(151,251,551,251),
    [45]=V(201,251,601,251),[46]=V(251,251,651,251),[47]=V(301,251,701,251),[48]=V(351,251,751,251),

    [49]=V(1,301,401,301),[50]=V(51,301,451,301),[51]=V(101,301,501,301),[52]=V(151,301,551,301),
    [53]=V(201,301,601,301),[54]=V(251,301,651,301),[55]=V(301,301,701,301),[56]=V(351,301,751,301),
}

------------------------------------------------------------
-- Button Graphics
------------------------------------------------------------

local function makeAtlasPicture(sourceX, sourceY)
    return {
        color = "0xffffffff",
        file = buttonAtlasPath,
        size = {
            horz = BUTTON_ATLAS_W,
            vert = BUTTON_ATLAS_H,
        },
        horzAlign = {
            offset = -sourceX,
            type = "min",
        },
        vertAlign = {
            offset = -sourceY,
            type = "min",
        },
    }
end

local function configureButtonState(stateList, visual)
    if not stateList or not visual then return end

    for _, state in pairs(stateList) do
        if type(state) == "table" then
            state.bkg = { center_center = "0x00000000" }
            state.picture = makeAtlasPicture(visual.x, visual.y)
        end
    end
end

local function configureButton(button, index)
    local skin = button:getSkin()
    if not skin or not skin.skinData or not skin.skinData.states then
        error("Button native skin states not found")
    end

    local visual = ButtonVisualMap[index]
    if not visual then
        error("ButtonVisualMap missing: " .. tostring(index))
    end

    local states = skin.skinData.states
    configureButtonState(states.released, visual.released)
    configureButtonState(states.pressed, visual.pressed)
    configureButtonState(states.disabled, visual.disabled)

    button:setSkin(skin)
end

------------------------------------------------------------
-- Buttons Installation
------------------------------------------------------------

local function installButton(button, index)
    configureButton(button, index)
    local armed = false

    button:addMouseDownCallback(function(self, x, y, mouseButton)
        if mouseButton ~= 1 then return end
        endDrag()
        armed = true
    end)

    button:addMouseMoveCallback(function(self, x, y)
        if dragging then
            armed = false
            endDrag()
        end
    end)

    button:addMouseUpCallback(function(self, x, y, mouseButton)
        if mouseButton ~= 1 then return end
        endDrag()
        if armed then
            inputRouter:dispatchButton(index)
        end
        armed = false
    end)
end

local function collectButtons()
    buttons = {}

    for index = 1, BUTTON_COUNT do
        local name = "TestButton" .. index
        local button = window[name]

        if not button then
            error(name .. " not found")
        end

        buttons[index] = button
    end

    logInfo(BUTTON_COUNT .. " buttons collected")
end

local function installButtons()
    for index, button in ipairs(buttons) do
        installButton(button, index)
    end

    logInfo(BUTTON_COUNT .. " buttons installed")
end

------------------------------------------------------------
-- Window Creation
------------------------------------------------------------

local function createWindow()
    if window then return end

    requireFile(dlgPath)
    requireFile(imagePath)
    requireFile(buttonAtlasPath)

    window = DialogLoader.spawnDialogFromFile(dlgPath)
    if not window then
        error("Failed to create DXGUI window")
    end

    window:setBounds(0, 0, WINDOW_W, WINDOW_H)

    imagePanel = window.ImagePanel
    displayArea = window.DisplayArea

    if not imagePanel then error("ImagePanel not found") end
    if not displayArea then error("DisplayArea not found") end

    collectGraphicLayers()
    collectDisplayLines()
    collectButtons()

    local skin = imagePanel:getSkin()
    skin.skinData.states.released[1].picture.file = imagePath
    imagePanel:setSkin(skin)

    renderer:setAdapter(createDisplayAdapter(displayLines))
    renderer:clear()
    renderer:flush()

    graphics:setAdapter(createGraphicAdapter(graphicLayers))
    graphics:hideAll()
    graphics:flush()

    createDataSystem()
    createPageSystem()

    installApplicationInputHandler()

    installDragSurface(displayArea)
    installDragCancelSurface(imagePanel)

    installButtons()
    installHotkey()

    pageManager:start("MAIN")
    centerWindow()

    imagePanel:setVisible(false)
    displayArea:setVisible(false)

    for _, button in ipairs(buttons) do
        button:setVisible(false)
    end

    window:setHasCursor(false)
    window:setVisible(true)
    shown = false

    logInfo("Initialized")
    logInfo("Project root: " .. rootPath)
    logInfo("Modules root: " .. modulesPath)
end

------------------------------------------------------------
-- DCS Callback
------------------------------------------------------------

local callbacks = {}

function callbacks.onSimulationFrame()
    if not window then
        frameCounter = frameCounter + 1
        if frameCounter < CREATE_FRAME then return end

        local ok, err = pcall(createWindow)
        if not ok then
            logInfo("ERROR: " .. tostring(err))
            return
        end

        local now = DCS.getRealTime()
        lastRuntimeTime = now
        lastDataUpdateTime = now
        return
    end

    local now = DCS.getRealTime()
    if not now then return end

    if not lastRuntimeTime then
        lastRuntimeTime = now
        return
    end

    local dt = now - lastRuntimeTime
    lastRuntimeTime = now

    if dt < 0 then dt = 0 end
    if dt > 1 then dt = 1 end

    if aircraftData and (not lastDataUpdateTime or now - lastDataUpdateTime >= DATA_UPDATE_INTERVAL) then
        lastDataUpdateTime = now
        local ok, err = pcall(function()
            aircraftData:update()
        end)

        if not ok then
            logInfo("AIRCRAFT DATA ERROR: " .. tostring(err))
        end
    end

    if pageManager then
        local ok, err = pcall(function()
            pageManager:update(dt)
        end)

        if not ok then
            logInfo("PAGE UPDATE ERROR: " .. tostring(err))
        end
    end
end

DCS.setUserCallbacks(callbacks)
logInfo("Hook loaded")