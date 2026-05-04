-- ============================================================================
-- 等距地图渲染器
-- UI 系统: urhox-libs/UI (Yoga Flexbox + NanoVG, 40+ 内置控件)
-- 地图渲染: 独立 NanoVG 上下文（低 renderOrder，绘制在 UI 下方）
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

-- NanoVG 地图渲染上下文
local vg_ = nil
---@type table<string, integer>
local nvgImageCache = {}   -- imagePath -> nvg image handle

local viewMode = "topdown"
local BASE_TILE_W_HALF = 32
local BASE_TILE_H_HALF = 16
local BASE_TD_TILE_W = 40
local BASE_TD_TILE_H = 40
local zoom = 1.0
local tileWH = BASE_TILE_W_HALF * zoom
local tileHH = BASE_TILE_H_HALF * zoom
local tdTileW = BASE_TD_TILE_W * zoom
local tdTileH = BASE_TD_TILE_H * zoom

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = CONFIG.Title

    -- 1. 创建地图渲染用的 NanoVG 上下文（低 renderOrder，绘制在 UI 下方）
    vg_ = nvgCreate(1)
    if not vg_ then
        print("ERROR: Failed to create NanoVG context for map")
        return
    end
    nvgSetRenderOrder(vg_, 0)  -- UI 是 999990，地图在最底层

    -- 2. 初始化 UI 系统（UI 的 NVG 上下文由 UI.Init 内部创建，renderOrder=999990）
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 3. 创建游戏内容（加载地图数据）
    CreateGameContent()

    -- 4. 创建 UI
    CreateUI()

    -- 5. 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent(vg_, "NanoVGRender", "HandleMapRender")

    print("=== Game Started: " .. CONFIG.Title .. " ===")
end

function Stop()
    -- 清理 NanoVG 图片缓存
    if vg_ then
        for _, handle in pairs(nvgImageCache) do
            nvgDeleteImage(vg_, handle)
        end
        nvgImageCache = {}
        nvgDelete(vg_)
        vg_ = nil
    end
    UI.Shutdown()
end

-- ============================================================================
-- 游戏逻辑
-- ============================================================================

function CreateGameContent()
    local path = "map.json"
    local f = cache:GetFile(path)
    if not f then
        print("ERROR: Failed to open " .. path .. " from ResourceCache")
        return
    end

    local jsonStr = f:ReadString()
    f:Close()
    mapData = cjson.decode(jsonStr)

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
        pointerEvents = "box-none"
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
-- NanoVG 地图渲染
-- ============================================================================

--- 获取或创建 NanoVG 图片句柄
---@param imagePath string
---@return integer  -- nvg image handle, 0 表示加载失败
local function getNvgImage(imagePath)
    if nvgImageCache[imagePath] then
        return nvgImageCache[imagePath]
    end
    local handle = nvgCreateImage(vg_, imagePath, 0)
    if handle <= 0 then
        print("WARN: Failed to load image: " .. imagePath)
        nvgImageCache[imagePath] = 0
        return 0
    end
    nvgImageCache[imagePath] = handle
    return handle
end

local function mapToScreen(mx, my, camX, camY)
    local ix = mx - 1
    local iy = my - 1
    if viewMode == "topdown" then
        return ix * tdTileW + camX, iy * tdTileH + camY
    else
        local sx = (ix - iy) * tileWH + camX
        local sy = (ix + iy) * tileHH + camY
        return sx, sy
    end
end

--- 使用 NanoVG 绘制单个瓦片贴图
local function drawImageTile(cx, cy, imgInfo, tileType, flipH)
    if not tileType.imagePath then return end

    local imgHandle = getNvgImage(tileType.imagePath)
    if imgHandle <= 0 then return end

    -- 确定源矩形（动画帧或静态）
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

    local pxScale
    if viewMode == "topdown" then
        pxScale = (tdTileW / 64) * scaleFactor
    else
        pxScale = (tileWH * 2 / 64) * scaleFactor
    end

    -- 获取整张图片的实际尺寸
    local fullW, fullH = nvgImageSize(vg_, imgHandle)
    if fullW == 0 or fullH == 0 then return end

    -- 源区域参数
    local srcX = sourceRect and sourceRect.x or 0
    local srcY = sourceRect and sourceRect.y or 0
    local srcW = sourceRect and sourceRect.w or fullW
    local srcH = sourceRect and sourceRect.h or fullH

    local drawW = srcW * pxScale
    local drawH = srcH * pxScale

    -- flat 渲染模式：等距投影变换
    if renderMode == "flat" and viewMode == "iso" then
        nvgSave(vg_)
        nvgTranslate(vg_, cx, cy)
        nvgScale(vg_, 1, 0.5)
        nvgScale(vg_, 0.70710678, 0.70710678)
        nvgRotate(vg_, -math.pi / 4)
        if flipH then nvgScale(vg_, -1, 1) end

        -- 绘制图片：映射源区域到目标矩形
        local patScaleX = drawW / srcW
        local patScaleY = drawH / srcH
        local patOX = -srcX * patScaleX - drawW / 2
        local patOY = -srcY * patScaleY - drawH / 2
        local imgPaint = nvgImagePattern(vg_, patOX, patOY,
            fullW * patScaleX, fullH * patScaleY, 0, imgHandle, 1)
        nvgBeginPath(vg_)
        nvgRect(vg_, -drawW / 2, -drawH / 2, drawW, drawH)
        nvgFillPaint(vg_, imgPaint)
        nvgFill(vg_)

        nvgRestore(vg_)
        return
    end

    -- 普通绘制
    local drawX = cx - drawW / 2
    local drawY
    if renderMode == "floor" or (renderMode == "flat" and viewMode == "topdown") then
        drawY = cy - drawH / 2
    else
        if viewMode == "topdown" then
            drawY = (cy + tdTileH / 2) - drawH
        else
            drawY = (cy + tileHH) - drawH
        end
    end

    nvgSave(vg_)
    if flipH then
        -- 水平翻转：以绘制中心为轴
        nvgTranslate(vg_, drawX + drawW, drawY)
        nvgScale(vg_, -1, 1)
        nvgTranslate(vg_, 0, 0)
    end

    -- 用 nvgImagePattern 将 spritesheet 中的源区域映射到目标矩形
    local patScaleX = drawW / srcW
    local patScaleY = drawH / srcH
    local patOX = (flipH and 0 or drawX) - srcX * patScaleX
    local patOY = (flipH and 0 or drawY) - srcY * patScaleY
    local imgPaint = nvgImagePattern(vg_, patOX, patOY,
        fullW * patScaleX, fullH * patScaleY, 0, imgHandle, 1)
    nvgBeginPath(vg_)
    if flipH then
        nvgRect(vg_, 0, 0, drawW, drawH)
    else
        nvgRect(vg_, drawX, drawY, drawW, drawH)
    end
    nvgFillPaint(vg_, imgPaint)
    nvgFill(vg_)

    nvgRestore(vg_)
end

--- NanoVGRender 事件回调 - 绘制等距地图
function HandleMapRender(eventType, eventData)
    if not vg_ or not mapData then return end

    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logicalW = screenW / dpr
    local logicalH = screenH / dpr

    nvgBeginFrame(vg_, logicalW, logicalH, dpr)

    local camX = logicalW / 2
    local camY = logicalH / 4
    local ox, oy = 0, 0

    local width = mapData.width
    local height = mapData.height

    -- Pass 1: 渲染地面层
    if mapData.layers and #mapData.layers > 0 then
        local groundLayer = mapData.layers[1]

        for diag = 0, width + height - 2 do
            for ix = 0, diag do
                local iy = diag - ix
                if ix < width and iy < height then
                    local mx, my = ix + 1, iy + 1
                    for _, tile in ipairs(groundLayer.tiles) do
                        if tile.x == mx and tile.y == my then
                            local sx, sy = mapToScreen(tile.x, tile.y, camX, camY)
                            local tileType = tileDict[tile.id] or {}
                            local imgInfo = { w = 64, h = 64 }
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

    -- Pass 2: 渲染物体层（深度排序）
    local sortList = {}

    if mapData.layers then
        for li = 2, #mapData.layers do
            for _, tile in ipairs(mapData.layers[li].tiles) do
                local sx, sy = mapToScreen(tile.x, tile.y, camX, camY)
                local cx, cy = sx + ox, sy + oy

                local tileType = tileDict[tile.id] or {}
                local renderMode = tileType.renderMode or "vertical"

                local isFlat = (renderMode == "flat" or renderMode == "floor")
                local footYVal
                if viewMode == "topdown" then
                    if isFlat then
                        local scaleFactor = tileType.scale or 1.0
                        if not tileType.scale then scaleFactor = scaleFactor * 1.015 end
                        local pxScale = (tdTileW / 64) * scaleFactor
                        local srcH = 64
                        if tileType.rect then srcH = tileType.rect.h end
                        local drawH = srcH * pxScale
                        footYVal = cy + drawH / 2
                    else
                        footYVal = cy + tdTileH / 2
                    end
                else
                    footYVal = cy + tileHH
                end

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
            if viewMode == "topdown" and a.footY ~= b.footY then return a.footY < b.footY end
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

    nvgEndFrame(vg_)
end
