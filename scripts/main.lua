-- ============================================================================
-- 空项目脚手架
-- 用途: 最小化项目起点，按需扩展
-- UI 系统: urhox-libs/UI (Yoga Flexbox + NanoVG, 40+ 内置控件)
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- 全局变量
-- ============================================================================
local uiRoot_ = nil

local CONFIG = {
    Title = "My Game",
}

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = CONFIG.Title

    -- 初始化 UI 系统
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 创建游戏内容
    CreateGameContent()

    -- 创建 UI
    CreateUI()

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print("=== Game Started: " .. CONFIG.Title .. " ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 游戏逻辑（在这里填充）
-- ============================================================================

function CreateGameContent()
    -- TODO: 初始化游戏状态、数据等
end

function CreateUI()
    uiRoot_ = UI.Panel {
        id = "gameUI",
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Label {
                text = CONFIG.Title,
                fontSize = 24,
                fontColor = { 255, 255, 255, 255 },
            },
        }
    }

    UI.SetRoot(uiRoot_)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()
    -- TODO: 更新游戏逻辑
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    -- TODO: 处理按键输入
end
