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

-- 地图相关变量
local mapData = nil
local tileDict = {}
local textureCache = {}

local viewMode = "iso"
local BASE_TILE_W_HALF = 32
local BASE_TILE_H_HALF = 16
local zoom = 1.0
local tileWH = BASE_TILE_W_HALF * zoom
local tileHH = BASE_TILE_H_HALF * zoom

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
    SubscribeToEvent("PostRenderUpdate", "HandlePostRenderUpdate")

    print("=== Game Started: " .. CONFIG.Title .. " ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 游戏逻辑（在这里填充）
-- ============================================================================

function CreateGameContent()
    -- 初始化游戏状态、数据等
    local path = "map.json"
    local f = cache:GetFile(path)
    if not f then
        print("ERROR: Failed to open " .. path .. " from ResourceCache")
        return
    end

    local jsonStr = f:ReadString()
    f:Close()
    mapData = JsonDecode(jsonStr)

    if mapData.imageRegistry then
        for _, reg in ipairs(mapData.imageRegistry) do
            tileDict[reg.id] = reg
        end
    end
    print("Map loaded successfully!")
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

-- ============================================================================
-- 渲染逻辑
-- ============================================================================

local function mapToScreen(mx, my, camX, camY)
    local ix = mx - 1
    local iy = my - 1
    local sx = (ix - iy) * tileWH + camX
    local sy = (ix + iy) * tileHH + camY
    return sx, sy
end

local function getTexture(path)
    if not textureCache[path] then
        textureCache[path] = cache:GetResource("Texture2D", path)
    end
    return textureCache[path]
end

local function drawImageTile(cx, cy, imgInfo, tileType, flipH)
    if not tileType.imagePath then return end
    
    local texture = getTexture(tileType.imagePath)
    if not texture then return end

    local sourceRect = nil
    if tileType.frames and #tileType.frames > 0 then
        local fps = tileType.fps or 10
        local frameCount = #tileType.frames
        local t = time and time:GetElapsedTime() or 0
        local frameIndex = math.floor(t * fps) % frameCount + 1
        sourceRect = tileType.frames[frameIndex]
    else
        sourceRect = tileType.rect
    end

    local scaleFactor = tileType.scale or 1.0
    local renderMode = tileType.renderMode or "vertical"
    
    if (renderMode == "flat" or renderMode == "floor") and not tileType.scale then
        scaleFactor = scaleFactor * 1.015
    end

    local pxScale = (tileWH * 2 / 64) * scaleFactor 
    
    local drawW = (sourceRect and sourceRect.w or imgInfo.w) * pxScale
    local drawH = (sourceRect and sourceRect.h or imgInfo.h) * pxScale

    if renderMode == "flat" and viewMode == "iso" then
        graphics.Push()
        graphics.Translate(cx, cy)
        graphics.Scale(1, 0.5)
        graphics.Scale(0.70710678, 0.70710678)
        graphics.Rotate(-math.pi / 4)
        if flipH then graphics.Scale(-1, 1) end
        graphics.Draw(texture, -drawW / 2, -drawH / 2, sourceRect)
        graphics.Pop()
        return
    end

    local drawX = cx - drawW / 2
    local drawY
    if renderMode == "floor" then
        drawY = cy - drawH / 2
    else
        drawY = (cy + tileHH) - drawH
    end

    graphics.Draw(texture, drawX, drawY, sourceRect, flipH)
end

function HandlePostRenderUpdate(eventType, eventData)
    if not mapData then return end

    local camX = graphics.width / 2
    local camY = graphics.height / 4
    local ox, oy = 0, 0

    local width = mapData.width
    local height = mapData.height

    -- Pass 1: 渲染地面层
    if mapData.layers and #mapData.layers > 0 then
        local groundLayer = mapData.layers[1]
        
        -- 对角线迭代以正确排序绘制地面
        for diag = 0, width + height - 2 do
            for ix = 0, diag do
                local iy = diag - ix
                if ix < width and iy < height then
                    local mx, my = ix + 1, iy + 1
                    -- 寻找对应坐标的瓦片
                    for _, tile in ipairs(groundLayer.tiles) do
                        if tile.x == mx and tile.y == my then
                            local sx, sy = mapToScreen(tile.x, tile.y, camX, camY)
                            local tileType = tileDict[tile.id] or {}
                            local imgInfo = { w = 64, h = 64 } -- 默认 fallback 大小
                            if tileType.rect then
                                imgInfo.w = tileType.rect.w
                                imgInfo.h = tileType.rect.h
                            end
                            drawImageTile(sx + ox, sy + oy, imgInfo, tileType, tile.flipH)
                            break
                        end
                    end
                end
            end
        end
    end

    -- Pass 2: 渲染物体层 (深度排序)
    local sortList = {}
    
    if mapData.layers then
        for li = 2, #mapData.layers do
            for _, tile in ipairs(mapData.layers[li].tiles) do
                local sx, sy = mapToScreen(tile.x, tile.y, camX, camY)
                local cx, cy = sx + ox, sy + oy
                
                local tileType = tileDict[tile.id] or {}
                local renderMode = tileType.renderMode or "vertical"

                local footYVal = cy + tileHH
                local isFlat = (renderMode == "flat" or renderMode == "floor")

                table.insert(sortList, {
                    cx = cx, cy = cy,
                    footY = footYVal,
                    footX = cx,
                    li = li,
                    tile = tile,
                    tileType = tileType,
                    isFlat = isFlat,
                    pri = 0
                })
            end
        end
    end

    table.sort(sortList, function(a, b)
        if a.isFlat ~= b.isFlat then return a.isFlat end
        if a.isFlat and b.isFlat then
            if a.li ~= b.li then return a.li < b.li end
        end
        if a.footY ~= b.footY then return a.footY < b.footY end
        if a.footX ~= b.footX then return a.footX < b.footX end
        if a.pri and b.pri and a.pri ~= b.pri then return a.pri < b.pri end
        return a.li < b.li
    end)

    for _, item in ipairs(sortList) do
        local imgInfo = { w = 64, h = 64 }
        if item.tileType and item.tileType.rect then
            imgInfo.w = item.tileType.rect.w
            imgInfo.h = item.tileType.rect.h
        end
        drawImageTile(item.cx, item.cy, imgInfo, item.tileType, item.tile.flipH)
    end
end
