local AircraftData = {}
AircraftData.__index = AircraftData

------------------------------------------------------------
-- DCS-DDIS AircraftData
--
-- 用途：
-- 集中读取 DCS 常用基础飞行数据，供功能模块统一使用。
--
-- 规则：
-- 1. Page / Module 不直接调用 Export.*。
-- 2. 已确认、通用的数据在这里读取。
-- 3. 未确认或机型相关 API 只保留扩展说明，不默认读取。
-- 4. 所有 API 调用必须经过安全调用。
-- 5. 字段可能为 nil，模块必须自行容错。
-- 6. 保存 DCS 原始单位，单位换算由具体模块完成。
------------------------------------------------------------

------------------------------------------------------------
-- DCS API Access
------------------------------------------------------------

local function getExportFunction(name)
    if type(Export) == "table" and type(Export[name]) == "function" then
        return Export[name]
    end

    if type(_G[name]) == "function" then
        return _G[name]
    end

    return nil
end

local function safeCall(func)
    if type(func) ~= "function" then return nil end

    local ok, result = pcall(func)
    if not ok then return nil end

    return result
end

local function safeExportCall(name)
    return safeCall(getExportFunction(name))
end

local function safeCall3(func)
    if type(func) ~= "function" then
        return nil, nil, nil
    end

    local ok, a, b, c = pcall(func)
    if not ok then
        return nil, nil, nil
    end

    return a, b, c
end

local function safeExportCall3(name)
    return safeCall3(getExportFunction(name))
end

------------------------------------------------------------
-- Constructor
------------------------------------------------------------

function AircraftData.new()
    return setmetatable({
        ----------------------------------------------------
        -- 00. 数据状态
        ----------------------------------------------------
        available = false,

        ----------------------------------------------------
        -- 01. 飞机身份
        ----------------------------------------------------
        name = nil,              -- DCS 飞机类型名称
        unitName = nil,          -- 任务编辑器 Unit Name
        groupName = nil,         -- 任务编辑器 Group Name
        typeInfo = nil,          -- LoGetSelfData().Type
        country = nil,           -- 国家信息
        coalition = nil,         -- 阵营信息
        coalitionId = nil,       -- 阵营编号
        pilotName = nil,         -- LoGetPilotName()
        playerPlaneId = nil,     -- LoGetPlayerPlaneId()

        ----------------------------------------------------
        -- 02. 地理位置
        ----------------------------------------------------
        latitude = nil,          -- 纬度，度
        longitude = nil,         -- 经度，度
        selfDataAltitude = nil,  -- SelfData 中的高度
        positionX = nil,         -- DCS 世界坐标
        positionY = nil,
        positionZ = nil,

        ----------------------------------------------------
        -- 03. 飞机姿态，单位：弧度
        ----------------------------------------------------
        heading = nil,           -- 真航向
        pitch = nil,             -- 俯仰
        bank = nil,              -- 横滚
        magneticHeading = nil,   -- LoGetMagneticYaw()

        ----------------------------------------------------
        -- 04. ADI 姿态
        ----------------------------------------------------
        adiPitch = nil,
        adiBank = nil,
        adiYaw = nil,

        ----------------------------------------------------
        -- 05. 高度，单位：米
        ----------------------------------------------------
        altitudeMSL = nil,
        altitudeAGL = nil,

        ----------------------------------------------------
        -- 06. 空速
        ----------------------------------------------------
        indicatedAirSpeed = nil, -- IAS，m/s
        trueAirSpeed = nil,      -- TAS，m/s
        mach = nil,

        ----------------------------------------------------
        -- 07. 飞行动力学
        ----------------------------------------------------
        verticalVelocity = nil,  -- m/s
        angleOfAttack = nil,     -- 弧度

        ----------------------------------------------------
        -- 08. 三维运动数据
        ----------------------------------------------------
        vectorVelocity = nil,    -- {x,y,z}，m/s
        accelerationUnits = nil, -- {x,y,z}，G
        angularVelocity = nil,   -- {x,y,z}，通常 rad/s

        ----------------------------------------------------
        -- 09. 导航基础数据
        ----------------------------------------------------
        glideDeviation = nil,
        sideDeviation = nil,
        slipBallPosition = nil,

        ----------------------------------------------------
        -- 10. 时间
        ----------------------------------------------------
        modelTime = nil,
        missionStartTime = nil,
    }, AircraftData)
end

------------------------------------------------------------
-- Clear
------------------------------------------------------------

function AircraftData:clear()
    self.available = false

    -- 身份
    self.name = nil
    self.unitName = nil
    self.groupName = nil
    self.typeInfo = nil
    self.country = nil
    self.coalition = nil
    self.coalitionId = nil
    self.pilotName = nil
    self.playerPlaneId = nil

    -- 位置
    self.latitude = nil
    self.longitude = nil
    self.selfDataAltitude = nil
    self.positionX = nil
    self.positionY = nil
    self.positionZ = nil

    -- 姿态
    self.heading = nil
    self.pitch = nil
    self.bank = nil
    self.magneticHeading = nil

    -- ADI
    self.adiPitch = nil
    self.adiBank = nil
    self.adiYaw = nil

    -- 高度
    self.altitudeMSL = nil
    self.altitudeAGL = nil

    -- 空速
    self.indicatedAirSpeed = nil
    self.trueAirSpeed = nil
    self.mach = nil

    -- 飞行动力学
    self.verticalVelocity = nil
    self.angleOfAttack = nil

    -- 运动
    self.vectorVelocity = nil
    self.accelerationUnits = nil
    self.angularVelocity = nil

    -- 导航
    self.glideDeviation = nil
    self.sideDeviation = nil
    self.slipBallPosition = nil

    -- 时间
    self.modelTime = nil
    self.missionStartTime = nil
end

------------------------------------------------------------
-- Update
------------------------------------------------------------

function AircraftData:update()
    --------------------------------------------------------
    -- LoGetSelfData 是判断当前是否存在玩家飞机的基础入口。
    --------------------------------------------------------

    local selfData = safeExportCall("LoGetSelfData")

    if not selfData then
        self:clear()
        return false
    end

    self.available = true

    --------------------------------------------------------
    -- 01. 飞机身份
    --------------------------------------------------------

    self.name = selfData.Name
    self.unitName = selfData.UnitName
    self.groupName = selfData.GroupName
    self.typeInfo = selfData.Type
    self.country = selfData.Country
    self.coalition = selfData.Coalition
    self.coalitionId = selfData.CoalitionID

    self.pilotName = safeExportCall("LoGetPilotName")
    self.playerPlaneId = safeExportCall("LoGetPlayerPlaneId")

    --------------------------------------------------------
    -- 02. 经纬度
    --------------------------------------------------------

    if type(selfData.LatLongAlt) == "table" then
        self.latitude = selfData.LatLongAlt.Lat
        self.longitude = selfData.LatLongAlt.Long
        self.selfDataAltitude = selfData.LatLongAlt.Alt
    else
        self.latitude = nil
        self.longitude = nil
        self.selfDataAltitude = nil
    end

    --------------------------------------------------------
    -- 03. DCS 世界坐标
    --------------------------------------------------------

    if type(selfData.Position) == "table" then
        self.positionX = selfData.Position.x
        self.positionY = selfData.Position.y
        self.positionZ = selfData.Position.z
    else
        self.positionX = nil
        self.positionY = nil
        self.positionZ = nil
    end

    --------------------------------------------------------
    -- 04. 飞机姿态，单位：弧度
    --------------------------------------------------------

    self.heading = selfData.Heading
    self.pitch = selfData.Pitch
    self.bank = selfData.Bank
    self.magneticHeading = safeExportCall("LoGetMagneticYaw")

    --------------------------------------------------------
    -- 05. ADI 姿态
    --------------------------------------------------------

    self.adiPitch, self.adiBank, self.adiYaw =
        safeExportCall3("LoGetADIPitchBankYaw")

    --------------------------------------------------------
    -- 06. 高度
    --------------------------------------------------------

    self.altitudeMSL = safeExportCall("LoGetAltitudeAboveSeaLevel")
    self.altitudeAGL = safeExportCall("LoGetAltitudeAboveGroundLevel")

    --------------------------------------------------------
    -- 07. 空速
    --------------------------------------------------------

    self.indicatedAirSpeed = safeExportCall("LoGetIndicatedAirSpeed")
    self.trueAirSpeed = safeExportCall("LoGetTrueAirSpeed")
    self.mach = safeExportCall("LoGetMachNumber")

    --------------------------------------------------------
    -- 08. 飞行动力学
    --------------------------------------------------------

    self.verticalVelocity = safeExportCall("LoGetVerticalVelocity")
    self.angleOfAttack = safeExportCall("LoGetAngleOfAttack")

    --------------------------------------------------------
    -- 09. 三维运动数据
    --------------------------------------------------------

    self.vectorVelocity = safeExportCall("LoGetVectorVelocity")
    self.accelerationUnits = safeExportCall("LoGetAccelerationUnits")
    self.angularVelocity = safeExportCall("LoGetAngularVelocity")

    --------------------------------------------------------
    -- 10. 导航基础数据
    --------------------------------------------------------

    self.glideDeviation = safeExportCall("LoGetGlideDeviation")
    self.sideDeviation = safeExportCall("LoGetSideDeviation")
    self.slipBallPosition = safeExportCall("LoGetSlipBallPosition")

    --------------------------------------------------------
    -- 11. 时间
    --------------------------------------------------------

    self.modelTime = safeExportCall("LoGetModelTime")
    self.missionStartTime = safeExportCall("LoGetMissionStartTime")

    return true
end

------------------------------------------------------------
-- Availability
------------------------------------------------------------

function AircraftData:isAvailable()
    return self.available
end

------------------------------------------------------------
-- ========================================================
-- 开发者扩展指南
-- ========================================================
--
-- 新模块如果需要当前没有的 DCS 数据：
--
-- 1. 不要在 Page / Module 中直接调用 Export.*。
--
-- 2. 先确认目标 API 在当前 DCS 版本、目标机型中可用。
--
-- 3. 在 new() 中增加字段：
--
--      someData = nil,
--
-- 4. 在 clear() 中清空：
--
--      self.someData = nil
--
-- 5. 在 update() 中通过安全接口读取：
--
--      self.someData = safeExportCall("LoGetSomeData")
--
-- 6. 如果 API 返回 table，先确认真实返回结构。
--
-- 7. 如果 API 只适用于特定机型，应在字段附近注明。
--
-- 8. 如果 API 可能受到多人服务器 Export 权限限制，
--    模块必须允许结果为 nil。
--
-- 9. AircraftData 只负责读取原始数据。
--    计算逻辑仍应放在具体 Module 中。
--
------------------------------------------------------------

------------------------------------------------------------
-- 已知但当前不主动读取的可选 API
--
-- 以下接口只有在实际模块需要时才建议加入 update()。
-- 不要为了“以后可能有用”而全部以 20Hz 默认读取。
------------------------------------------------------------

------------------------------------------------------------
-- A. 发动机 / 燃油
------------------------------------------------------------

-- LoGetEngineInfo()
--
-- 可能包含：
-- 发动机转速、温度、燃油等。
--
-- 适合：
-- ENGINE PAGE
-- FUEL PAGE
--
-- 注意不同机型返回结构可能不同。

------------------------------------------------------------
-- B. 机械系统
------------------------------------------------------------

-- LoGetMechInfo()
--
-- 可能包含：
-- 起落架、襟翼、减速板、轮刹等状态。
--
-- 适合：
-- LANDING PAGE
-- CONFIGURATION PAGE

------------------------------------------------------------
-- C. 武器 / 挂载
------------------------------------------------------------

-- LoGetPayloadInfo()
--
-- 用于：
-- 当前飞机挂载、武器、外挂油箱等。
--
-- 返回结构通常较复杂，使用前应针对目标机型验证。

------------------------------------------------------------
-- D. 航路
------------------------------------------------------------

-- LoGetRoute()
--
-- 用于：
-- 当前任务航路与航路点。
--
-- 适合：
-- ROUTE PAGE
-- WAYPOINT PAGE
-- NAVIGATION MODULE

------------------------------------------------------------
-- E. 导航系统
------------------------------------------------------------

-- LoGetNavigationInfo()
--
-- 可能包含：
-- 导航要求速度、高度、姿态等信息。
--
-- 返回结构应在当前 DCS 版本实测。

------------------------------------------------------------
-- F. HSI / 无线电导航
------------------------------------------------------------

-- LoGetControlPanel_HSI()
--
-- 可能用于：
-- HSI、ADF、RMI、航向与无线电导航。
--
-- 机型差异可能较大。

------------------------------------------------------------
-- G. 大气压力
------------------------------------------------------------

-- LoGetBasicAtmospherePressure()
--
-- 用于：
-- 大气压力、气压高度相关计算。
--
-- 使用前确认单位。

------------------------------------------------------------
-- H. 风速向量
------------------------------------------------------------

-- LoGetVectorWindVelocity()
--
-- 用于：
-- 三维风速向量。
--
-- 适合：
-- WIND PAGE
-- WIND CORRECTION
-- NAVIGATION COMPUTER
--
-- 使用前应确认坐标轴定义。

------------------------------------------------------------
-- I. 故障 / 告警
------------------------------------------------------------

-- LoGetMCPState()
--
-- 可能包含：
-- 故障、告警、自动驾驶等状态。
--
-- 适合：
-- WARNING PAGE
-- SYSTEM STATUS PAGE

------------------------------------------------------------
-- J. 雷达 / 目标 / 传感器
------------------------------------------------------------

-- LoGetSightingSystemInfo()
-- LoGetTargetInformation()
-- LoGetLockedTargetInformation()
-- LoGetTWSInfo()
--
-- 这些数据：
-- 1. 与具体机型高度相关；
-- 2. 可能受到多人服务器 Export 权限限制；
-- 3. 不属于基础 ownship 飞行数据。
--
-- 因此当前不默认读取。

------------------------------------------------------------
-- K. 世界对象
------------------------------------------------------------

-- LoGetObjectById()
-- LoGetWorldObjects()
--
-- 涉及其他单位与世界对象。
--
-- 使用前必须考虑：
-- 1. 多人服务器限制；
-- 2. 性能开销；
-- 3. 数据量；
-- 4. 实际模块需求。
--
-- 不建议加入基础 20Hz 更新循环。

------------------------------------------------------------
-- 单位规范
--
-- AircraftData 原则上保存 DCS API 原始单位：
--
-- heading              rad
-- pitch                rad
-- bank                 rad
-- magneticHeading      rad
--
-- altitudeMSL          m
-- altitudeAGL          m
--
-- indicatedAirSpeed    m/s
-- trueAirSpeed         m/s
-- verticalVelocity     m/s
--
-- mach                 无量纲
-- angleOfAttack        rad
--
-- vectorVelocity       m/s
-- accelerationUnits    G
-- angularVelocity      通常 rad/s
--
-- glideDeviation       通常 -1 ~ +1
-- sideDeviation        通常 -1 ~ +1
-- slipBallPosition     通常 -1 ~ +1
--
-- knots / feet / degrees / fpm / NM 等显示单位
-- 统一由具体功能模块自行转换。
------------------------------------------------------------

return AircraftData