# DCS-DDIS
**DCS Digital Display and Input System**
* DCS-DDIS uses DXGUI as the window/input framework and PNG/DDS textures as the visual layer. By dynamically modifying DXGUI Skin textures and Texture Atlas source offsets, it enables fully customized interfaces and animated avionics displays inside DCS.

* DCS-DDIS 是一个运行于 DCS Saved Games Hook 环境中的模块化 DXGUI 显示与输入框架，用于快速开发字符页面、飞行数据显示、导航计算和动态图形模块。DCS-DDIS 采用 DXGUI 作为窗口与输入框架，并使用 PNG/DDS 纹理作为视觉层。通过动态修改 DXGUI 皮肤纹理及纹理图集（Texture Atlas）的源偏移量，它实现了 DCS 内部完全可定制的界面以及动态航空电子显示效果。
* 不要问我代码怎么写的，我也看不懂，全是codex写的。
* 我只是利用DCSWorld\Scripts\UI\InputDeviceVisualizer\Keyboard 中的内容让chatgpt反推出了贴图导入和使用的方法，然后设计了14x30的字符显示系统以及10个图层的动画系统。
* 贴图是我用Gemini Nano banana 生成并使用PS修改的。

<img width="660" height="880" alt="54c43fbddb7fde47e3c0cc4bc021ecf9" src="https://github.com/user-attachments/assets/c9fab92a-c140-4695-95e2-7ff72cf8b699" />


## Features
* 30 × 14 字符显示
* 10 × 440 × 360 图形层
* 56 键输入界面
* 页面切换与返回
* Module 自动发现与注册
* 模块独立 Lua / Images
* 统一 AircraftData 数据层
* Texture Atlas 动画
* DDS / PNG 资源支持
* `Ctrl + Shift + M` 显示 / 隐藏
* 

## Included Modules
* **Flight Info** — 基础飞行数据显示
* **Flight Display** — 人工地平线、飞行矢量及 Landing Guidance
* **Nav Computer** — 航向 / 风修正计算
* **Example Module** — 模块开发示例
<img width="1172" height="866" alt="9ed64aef-86a4-4d45-ae30-c998ea7a1b8b" src="https://github.com/user-attachments/assets/53ab648f-d22e-4c66-acd9-d34f614b18ef" />

## Installation
复制到：Saved Games\DCS\Scripts\
目录应为：
```text
Scripts\
├─ Hooks\
│  └─ DCS-DDIS-hook.lua
└─ DCS-DDIS\
   ├─ DCS-DDIS-dxgui.dlg
   ├─ Data\
   ├─ Images\
   ├─ Pages\
   └─ Modules\
```
启动 DCS 后按：
```text
Ctrl + Shift + M
```
显示或隐藏 DCS-DDIS。

## Module Development
新增功能推荐放入：
```text
DCS-DDIS\
└─ Modules\
   └─ MyModule\
      ├─ module.lua
      ├─ MyPage.lua
      └─ Images\
```
DCS-DDIS 会自动扫描：
```text
Modules/*/module.lua
```
因此普通模块无需修改核心 Hook。
最小模块入口：

```lua
local Module = {}

Module.id = "MY_MODULE"

Module.menu = {
    label = "MY MODULE",
    page = "MY_MAIN",
    order = 100,
}

function Module.createPages(context)
    local MyPage = context:load("MyPage.lua")

    return {
        MY_MAIN = MyPage.new({
            aircraftData = context.aircraftData,
        }),
    }
end

return Module
```

## Core Technique: Custom DXGUI Interface

DCS-DDIS 最核心的技术基础，是利用 **DXGUI 控件 + 自定义 Texture** 构建完全自定义的游戏内界面。

基本流程非常简单：

```text
.dlg 定义透明窗口和控件
        ↓
DialogLoader.spawnDialogFromFile()
        ↓
获取控件 Skin
        ↓
将 PNG / DDS 写入 picture.file
        ↓
setSkin()
        ↓
自定义界面显示在 DCS 中
```

项目中的核心实现本质上类似：

```lua
local window =
    DialogLoader.spawnDialogFromFile(
        dlgPath
    )

local skin =
    window.ImagePanel:getSkin()

skin.skinData.states
    .released[1]
    .picture.file =
        texturePath

window.ImagePanel:setSkin(skin)
```

因此 DXGUI 的 Window / Static / Button 主要承担**控件与交互载体**，真正的界面外观可以完全由外部 PNG / DDS 贴图决定。

DCS-DDIS 在此基础上进一步使用 **Texture Atlas + Source Offset**：

```text
Texture Atlas
      ↓
sourceX / sourceY
      ↓
horzAlign.offset / vertAlign.offset
      ↓
控件只显示贴图中的指定区域
```

项目统一采用 **1-based Source**：

```text
source(1, 1)   → offset(0, 0)
source(441, 1) → offset(-440, 0)
```

即：

```lua
offsetX = -(sourceX - 1)
offsetY = -(sourceY - 1)
```

这使 DXGUI 不仅能够使用自定义贴图制作窗口，还能够通过 Atlas 帧切换和 Source 平移实现按钮状态、动态图形、人工地平线以及其他自定义航电显示。

> **In short:** DCS-DDIS 将 DXGUI 当作窗口和输入框架，将 PNG / DDS Texture 当作真正的视觉层，并通过 Texture Atlas 的 Source Offset 扩展其动态图形能力。

## Texture Export Settings
.dds贴图文件建议使用这个设置导出
<img width="504" height="565" alt="30f2be16-0bf4-4761-b01f-aace383d9bc3" src="https://github.com/user-attachments/assets/838c14fc-2959-4348-a47a-54ee6185905d" />
