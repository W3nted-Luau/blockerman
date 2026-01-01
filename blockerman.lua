-- SRC CUSTOM MADE BY W3NTEDD

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local config = {
    Enabled = true,
    GuiEnabled = true,
    GuessHelper = true,
    AutoComplete = false,
    AutoTeleportDelay = 0.1,
    TeleportHeight = 3,
    Debug = true,
    TotalMines = 100,
    DistanceWeight = 0.1,
    EdgePenalty = 0.05
}

local state = {
    cells = {
        grid = {},
        numbered = {},
        toFlag = {},
        toClear = {}
    },
    grid = { w = 0, h = 0 },
    lastPartCount = -1,
    lastNumberedCount = 0,
    statusGui = nil,
    statusLabel = nil,
    lastGuiUpdate = 0,
    bestGuessCell = nil,
    bestGuessScore = nil,
    lastAutoAction = 0,
    actionQueue = {}
}

local highlightFolder = workspace:FindFirstChild("MinesweeperHighlights")
if not highlightFolder then
    highlightFolder = Instance.new("Folder")
    highlightFolder.Name = "MinesweeperHighlights"
    highlightFolder.Parent = workspace
end

local COLOR_SAFE = Color3.fromRGB(0, 255, 0)
local COLOR_MINE = Color3.fromRGB(170, 0, 0)
local COLOR_GUESS = Color3.fromRGB(0, 170, 255)

local abs, floor, huge = math.abs, math.floor, math.huge
local tsort = table.sort

local function isTrulySafe(cell)
    return cell ~= nil and state.cells.toClear[cell] == true and cell.state ~= "flagged"
end

local function isNumber(str)
    return tonumber(str) ~= nil
end

local function createBorders(cell)
    local thickness = 0.08
    local inset = 0.05
    local function newPart()
        local p = Instance.new("Part")
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.CastShadow = false
        p.Transparency = 1
        p.Material = Enum.Material.Neon
        p.Size = Vector3.new(1,1,1)
        return p
    end
    local borders = {
        top = newPart(),
        bottom = newPart(),
        left = newPart(),
        right = newPart()
    }
    cell.borders = borders
    cell._borderThickness = thickness
    cell._borderInset = inset
    for _, border in pairs(borders) do
        border.Parent = highlightFolder
    end
    return borders
end

local function updateBorderPositions(cell)
    if not cell.part or not cell.borders then return end
    local sz = cell.part.Size
    local th = cell._borderThickness or 0.08
    local ins = cell._borderInset or 0.05
    local hx = sz.X / 2 - ins
    local hz = sz.Z / 2 - ins
    local t, b, l, r = cell.borders.top, cell.borders.bottom, cell.borders.left, cell.borders.right
    t.Size = Vector3.new(sz.X - ins*2, th, th)
    b.Size = Vector3.new(sz.X - ins*2, th, th)
    l.Size = Vector3.new(th, th, sz.Z - ins*2)
    r.Size = Vector3.new(th, th, sz.Z - ins*2)
    local yoff = sz.Y / 2 + 0.01
    t.CFrame = cell.part.CFrame * CFrame.new(0, yoff, -hz)
    b.CFrame = cell.part.CFrame * CFrame.new(0, yoff, hz)
    l.CFrame = cell.part.CFrame * CFrame.new(-hx, yoff, 0)
    r.CFrame = cell.part.CFrame * CFrame.new(hx, yoff, 0)
end

local function removeAllHighlights(cell)
    if not cell.borders then return end
    for _, b in pairs(cell.borders) do
        b.Transparency = 1
    end
    cell.isHighlightedMine = false
    cell.isHighlightedSafe = false
    cell.isHighlightedGuess = false
end

local function applyHighlight(cell, color)
    if not cell.borders then
        createBorders(cell)
        updateBorderPositions(cell)
    end
    for _, b in pairs(cell.borders) do
        b.Color = color
        b.Transparency = 0
    end
end

local function clearAllCellBorders()
    for x = 0, state.grid.w - 1 do
        local column = state.cells.grid[x]
        if column then
            for z = 0, state.grid.h - 1 do
                local cell = column[z]
                if cell and cell.borders then
                    for _, b in pairs(cell.borders) do
                        b:Destroy()
                    end
                    cell.borders = nil
                end
            end
        end
    end
end

local function isEligibleForClick(cell)
    return cell ~= nil and not (cell.state == "number" or cell.state == "flagged") and cell.covered ~= false
end

local function teleportToCell(cell)
    local player = Players.LocalPlayer
    local hrp = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp or not cell or not cell.part then return false end
    hrp.CFrame = CFrame.new(cell.part.Position + Vector3.new(0, config.TeleportHeight, 0))
    return true
end

local function processActionQueue()
    if not config.AutoComplete then return end
    if #state.actionQueue == 0 then return end
    if tick() - state.lastAutoAction < config.AutoTeleportDelay then return end
    local action = table.remove(state.actionQueue, 1)
    if not action then return end
    local cell = action.cell
    if not cell or not isEligibleForClick(cell) or not isTrulySafe(cell) then return end
    if teleportToCell(cell) then
        state.lastAutoAction = tick()
    end
end

local function buildActionQueue()
    if not config.AutoComplete then return end
    state.actionQueue = {}
    local player = Players.LocalPlayer
    local hrp = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local origin = hrp.Position
    local candidates = {}
    for x = 0, state.grid.w - 1 do
        local col = state.cells.grid[x]
        if col then
            for z = 0, state.grid.h - 1 do
                local cell = col[z]
                if cell and cell.part and isEligibleForClick(cell) and isTrulySafe(cell) then
                    table.insert(candidates, cell)
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        return (a.pos - origin).Magnitude < (b.pos - origin).Magnitude
    end)
    for _, cell in ipairs(candidates) do
        table.insert(state.actionQueue, { type = "teleport", cell = cell })
    end
end

local function estimateSpacing(sorted)
    if #sorted < 2 then return 1 end
    local diffs = {}
    for i = 2, #sorted do
        local d = math.abs(sorted[i] - sorted[i-1])
        if d > 0.01 then
            diffs[#diffs+1] = d
        end
    end
    table.sort(diffs)
    return diffs[math.ceil(#diffs / 2)] or diffs[1] or 1
end

local function clusterAndAverage(sorted, threshold)
    local clusters = {}
    for _, v in ipairs(sorted) do
        local placed = false
        for _, c in ipairs(clusters) do
            if math.abs(c.sum / c.count - v) <= threshold then
               c.sum = c.sum + v
               c.count = c.count + 1
               placed = true
               break
            end
        end
        if not placed then
            clusters[#clusters+1] = {sum = v, count = 1}
        end
    end
    local result = {}
    for _, c in ipairs(clusters) do
        result[#result+1] = c.sum / c.count
    end
    table.sort(result)
    return result
end

local function findClosestIndex(value, list)
    local best = 1
    local bestDist = math.huge
    for i, v in ipairs(list) do
        local d = math.abs(v - value)
        if d < bestDist then
            bestDist = d
            best = i
        end
    end
    return best - 1
end

local function hasFlagChild(part)
    if not part then return false end
    for _, c in ipairs(part:GetChildren()) do
        if c.Name:lower():find("flag") then
            return true
        end
    end
    return false
end

local function rebuildGridFromParts(folder)
    clearAllCellBorders()
    state.cells.grid = {}
    state.grid.w = 0
    state.grid.h = 0
    local parts = folder:GetChildren()
    if #parts == 0 then return end
    local allPositions = {}
    local sumY = 0
    for _, part in ipairs(parts) do
        local pos = part.Position
        table.insert(allPositions, {part = part, pos = pos})
        sumY = sumY + pos.Y
    end
    local xs, zs = {}, {}
    for _, data in ipairs(allPositions) do
        xs[#xs + 1] = data.pos.X
        zs[#zs + 1] = data.pos.Z
    end
    tsort(xs)
    tsort(zs)
    local cellWidth = estimateSpacing(xs) * 0.6
    local cellHeight = estimateSpacing(zs) * 0.6
    local uniqueX = clusterAndAverage(xs, cellWidth)
    local uniqueZ = clusterAndAverage(zs, cellHeight)
    state.grid.w = #uniqueX
    state.grid.h = #uniqueZ
    if state.grid.w == 0 or state.grid.h == 0 then return end
    local avgY = sumY / #parts
    for x = 0, state.grid.w - 1 do
        state.cells.grid[x] = {}
        for z = 0, state.grid.h - 1 do
            state.cells.grid[x][z] = {
                ix = x,
                iz = z,
                pos = Vector3.new(uniqueX[x+1], avgY, uniqueZ[z+1]),
                part = nil,
                state = "unknown",
                number = nil,
                covered = true,
                color = nil,
                neigh = nil,
                borders = nil,
                isHighlightedMine = false,
                isHighlightedSafe = false,
                isHighlightedGuess = false,
                lastHighlightChange = 0
            }
        end
    end
    for _, data in ipairs(allPositions) do
        local pos = data.pos
        local part = data.part
        local xIdx = findClosestIndex(pos.X, uniqueX)
        local zIdx = findClosestIndex(pos.Z, uniqueZ)
        local cell = state.cells.grid[xIdx][zIdx]
        if not cell.part then
            cell.part = part
            cell.pos = pos
        else
            local currDist = (cell.part.Position - Vector3.new(uniqueX[xIdx+1], cell.part.Position.Y, uniqueZ[zIdx+1])).Magnitude
            local newDist = (pos - Vector3.new(uniqueX[xIdx+1], pos.Y, uniqueZ[zIdx+1])).Magnitude
            if newDist < currDist then
                cell.part = part
                cell.pos = pos
            end
        end
    end
    for z = 0, state.grid.h - 1 do
        for x = 0, state.grid.w - 1 do
            local cell = state.cells.grid[x][z]
            local neighbors = {}
            for dz = -1, 1 do
                for dx = -1, 1 do
                    if dx ~= 0 or dz ~= 0 then
                        local nx, nz = x + dx, z + dz
                        if nx >= 0 and nx < state.grid.w and nz >= 0 and nz < state.grid.h then
                            neighbors[#neighbors + 1] = state.cells.grid[nx][nz]
                        end
                    end
                end
            end
            cell.neigh = neighbors
        end
    end
end

local function updateCellStates(folder)
    state.cells.numbered = {}
    if state.grid.w == 0 then return end
    for x = 0, state.grid.w - 1 do
        local column = state.cells.grid[x]
        if column then
            for z = 0, state.grid.h - 1 do
                local cell = column[z]
                if cell and cell.part then
                    cell.state = "unknown"
                    cell.number = nil
                    cell.covered = true
                    cell.color = nil
                    local partColor = cell.part.Color
                    if partColor then
                        local r = (partColor.R <= 1) and floor(partColor.R * 255 + 0.5) or partColor.R
                        local g = (partColor.G <= 1) and floor(partColor.G * 255 + 0.5) or partColor.G
                        local b = (partColor.B <= 1) and floor(partColor.B * 255 + 0.5) or partColor.B
                        cell.color = {R = r, G = g, B = b}
                    end
                    local numberGui = cell.part:FindFirstChild("NumberGui")
                    if numberGui then
                        local label = numberGui:FindFirstChild("TextLabel")
                        if label and isNumber(label.Text) then
                            cell.number = tonumber(label.Text)
                            cell.covered = false
                        end
                    end
                    local color = cell.color
                    local hasGui = cell.part:FindFirstChild("NumberGui") ~= nil
                    local isRevealed = hasGui
                    if color and not hasGui then
                        local r = color.R
                        local g = color.G
                        local b = color.B
                        if r >= 180 and g >= 180 and b >= 180 and math.abs(r-g)<=50 and math.abs(g-b)<=50 and math.abs(r-b)<=50 then
                            isRevealed = true
                        end
                        if r >= 200 and g >= 220 and b >= 240 then
                            isRevealed = false
                        end
                    end
                    cell.covered = not isRevealed
                    if hasFlagChild(cell.part) then
                        cell.state = "flagged"
                    end
                    if cell.number and not cell.covered then
                        cell.state = "number"
                        table.insert(state.cells.numbered, cell)
                    end
                end
            end
        end
    end
end


local function getUnknownNeighborsExcluding(cell, flaggedSet, safeSet)
    local result = {}
    for _, n in ipairs(cell.neigh) do
        if not flaggedSet[n] and not safeSet[n] and isEligibleForClick(n) then
            table.insert(result, n)
        end
    end
    return result
end

local function countRemainingMines(cell, flaggedSet)
    local remaining = cell.number or 0
    for _, n in ipairs(cell.neigh) do
        if flaggedSet[n] == true then
            remaining = remaining - 1
        end
    end
    return remaining
end

local function applySimpleDeductionRule(cellA, cellB, unknownsA, unknownsB, flaggedSet, safeSet)
    local intersection = {}
    local onlyA = {}
    local onlyB = {}
    local setA = {}
    for _, u in ipairs(unknownsA) do setA[u] = true end
    for _, u in ipairs(unknownsB) do
        if setA[u] then
            table.insert(intersection, u)
            setA[u] = nil
        else
            table.insert(onlyB, u)
        end
    end
    for u in pairs(setA) do
        table.insert(onlyA, u)
    end
    local minesA = countRemainingMines(cellA, flaggedSet)
    local minesB = countRemainingMines(cellB, flaggedSet)
    if #onlyA == 0 and #onlyB > 0 then
        local diff = minesB - minesA
        if diff == 0 then
            for _, u in ipairs(onlyB) do safeSet[u] = true end
        elseif diff == #onlyB then
            for _, u in ipairs(onlyB) do flaggedSet[u] = true end
        end
    end
    if #onlyB == 0 and #onlyA > 0 then
        local diff = minesA - minesB
        if diff == 0 then
            for _, u in ipairs(onlyA) do safeSet[u] = true end
        elseif diff == #onlyA then
            for _, u in ipairs(onlyA) do flaggedSet[u] = true end
        end
    end
end

local function checkAdjacentNumberedCells(flaggedSet, safeSet)
    local numbered = state.cells.numbered
    local grid = state.cells.grid
    for _, cell in ipairs(numbered) do
        for dz = -1, 1 do
            for dx = -1, 1 do
                if dx ~= 0 or dz ~= 0 then
                    local nx = cell.ix + dx
                    local nz = cell.iz + dz
                    if nx >= 0 and nx < state.grid.w and nz >= 0 and nz < state.grid.h then
                        local adj = grid[nx][nz]
                        if adj and adj.state == "number" then
                            local unknownsThis = getUnknownNeighborsExcluding(cell, flaggedSet, safeSet)
                            local unknownsAdj = getUnknownNeighborsExcluding(adj, flaggedSet, safeSet)
                            if #unknownsThis > 0 and #unknownsAdj > 0 then
                                applySimpleDeductionRule(cell, adj, unknownsThis, unknownsAdj, flaggedSet, safeSet)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function isPartRevealed(part)
    if not part then return false end
    if part:FindFirstChild("NumberGui") then return true end
    local t = part.Transparency
    if t and t < 0.5 then return true end
    if part:FindFirstChild("Revealed") then return true end
    return false
end

local function syncFlagStateFromParts()
    for x = 0, state.grid.w - 1 do
        local col = state.cells.grid[x]
        if col then
            for z = 0, state.grid.h - 1 do
                local cell = col[z]
                if cell and cell.part then
                    if hasFlagChild(cell.part) then
                        cell.state = "flagged"
                        cell.covered = false
                    else
                        if isPartRevealed(cell.part) then
                            local ng = cell.part:FindFirstChild("NumberGui")
                            if ng then
                                local label = ng:FindFirstChild("TextLabel")
                                if label and tonumber(label.Text) then
                                    cell.number = tonumber(label.Text)
                                    cell.state = "number"
                                    cell.covered = false
                                else
                                    cell.state = "unknown"
                                    cell.covered = false
                                end
                            else
                                cell.state = cell.state == "flagged" and "unknown" or cell.state
                                cell.covered = false
                            end
                        else
                            cell.covered = true
                            if cell.state == "number" then cell.state = "unknown" end
                        end
                    end
                end
            end
        end
    end
end

local function debugValidateFlagSet(knownFlags, toClear)
    for _, cell in ipairs(state.cells.numbered) do
        local required = cell.number or 0
        local flagCount = 0
        local unknownPossible = 0
        for _, nb in ipairs(cell.neigh) do
            if nb.state == "flagged" or knownFlags[nb] == true then
                flagCount = flagCount + 1
            elseif not toClear[nb] and isEligibleForClick(nb) then
                unknownPossible = unknownPossible + 1
            end
        end
        if flagCount > required then
            if config.Debug then print("validate fail: too many flags at", cell.ix, cell.iz, "req", required, "flags", flagCount) end
            return false
        end
        if flagCount + unknownPossible < required then
            if config.Debug then print("validate fail: not enough possible flags at", cell.ix, cell.iz, "req", required, "flags", flagCount, "poss", unknownPossible) end
            return false
        end
    end
    return true
end



local function updateLogic()
    if state.grid.w == 0 then
        state.cells.toFlag = {}
        state.cells.toClear = {}
        return
    end

    local numbered = state.cells.numbered
    if #numbered == 0 then
        state.cells.toFlag = {}
        state.cells.toClear = {}
        return
    end

    local knownFlags = {}
    for x = 0, state.grid.w - 1 do
        local col = state.cells.grid[x]
        if col then
            for z = 0, state.grid.h - 1 do
                local cell = col[z]
                if cell and cell.state == "flagged" then
                    knownFlags[cell] = true
                end
            end
        end
    end

    local changed = true
    local iterations = 0
    state.cells.toClear = {}

    while changed and iterations < 64 do
        changed = false
        iterations = iterations + 1

        for _, cell in ipairs(numbered) do
            local unknowns = {}
            local flagCount = 0
            for _, n in ipairs(cell.neigh) do
                if knownFlags[n] == true or n.state == "flagged" then
                    flagCount = flagCount + 1
                elseif isEligibleForClick(n) then
                    table.insert(unknowns, n)
                end
            end

            local remaining = (cell.number or 0) - flagCount
            if remaining == 0 then
                for _, u in ipairs(unknowns) do
                    if not state.cells.toClear[u] then
                        state.cells.toClear[u] = true
                        changed = true
                    end
                end
            elseif remaining == #unknowns then
                for _, u in ipairs(unknowns) do
                    if not knownFlags[u] then
                        knownFlags[u] = true
                        changed = true
                    end
                end
            end
        end

        checkAdjacentNumberedCells(knownFlags, state.cells.toClear)
    end

    if debugValidateFlagSet(knownFlags, state.cells.toClear) then
        state.cells.toFlag = knownFlags
    else
        state.cells.toFlag = {}
    end
end




local function updateGuess()
    state.bestGuessCell = nil
    state.bestGuessScore = nil
    if not config.GuessHelper then return end
    if state.grid.w == 0 or state.grid.h == 0 then return end
    local knownFlagsCount = 0
    local unknownCount = 0
    for x = 0, state.grid.w - 1 do
        local col = state.cells.grid[x]
        if col then
            for z = 0, state.grid.h - 1 do
                local cell = col[z]
                if cell.state == "flagged" or state.cells.toFlag[cell] then
                    knownFlagsCount = knownFlagsCount + 1
                elseif isEligibleForClick(cell) and not state.cells.toClear[cell] then
                    unknownCount = unknownCount + 1
                end
            end
        end
    end
    local remainingMines = config.TotalMines - knownFlagsCount
    local globalDensity = unknownCount > 0 and (remainingMines / unknownCount) or 0
    local player = Players.LocalPlayer
    local playerPos = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position
    local maxDistance = playerPos and math.sqrt((state.grid.w * 5)^2 + (state.grid.h * 5)^2) or 1
    local bestCell = nil
    local bestScore = nil
    for x = 0, state.grid.w - 1 do
        local col = state.cells.grid[x]
        if col then
            for z = 0, state.grid.h - 1 do
                local cell = col[z]
                if cell and cell.part and isEligibleForClick(cell) and not hasFlagChild(cell.part) and not state.cells.toFlag[cell] and not state.cells.toClear[cell] then
                    local validCount = 0
                    local probSum = 0
                    for _, n in ipairs(cell.neigh) do
                        if n.state == "number" and n.number and n.number > 0 then
                            local flaggedCount = 0
                            local unknownCountLocal = 0
                            for _, nn in ipairs(n.neigh) do
                                if (nn.part and hasFlagChild(nn.part)) or state.cells.toFlag[nn] then
                                    flaggedCount = flaggedCount + 1
                                elseif isEligibleForClick(nn) and not state.cells.toFlag[nn] and not state.cells.toClear[nn] then
                                    unknownCountLocal = unknownCountLocal + 1
                                end
                            end
                            local remaining = n.number - flaggedCount
                            if remaining <= 0 then
                                validCount = validCount + 1
                            elseif unknownCountLocal > 0 then
                                probSum = probSum + (remaining / unknownCountLocal)
                                validCount = validCount + 1
                            end
                        end
                    end
                    local localScore = validCount > 0 and (probSum / validCount) or globalDensity
                    local score = 0.5 * localScore + 0.5 * globalDensity
                    local isEdge = (x == 0 or x == state.grid.w - 1 or z == 0 or z == state.grid.h - 1)
                    if isEdge then
                        score = score + config.EdgePenalty
                    end
                    if playerPos then
                        local distance = (cell.pos - playerPos).Magnitude
                        local normalizedDistance = distance / maxDistance
                        score = score + normalizedDistance * config.DistanceWeight
                    end
                    if not bestScore or score < bestScore then
                        bestScore = score
                        bestCell = cell
                    end
                end
            end
        end
    end
    state.bestGuessCell = bestCell
    state.bestGuessScore = bestScore
end

local function updateHighlights()
    local now = tick()
    local bestGuess = state.bestGuessCell
    for x = 0, state.grid.w - 1 do
        local col = state.cells.grid[x]
        if col then
            for z = 0, state.grid.h - 1 do
                local cell = col[z]
                if cell and cell.part then
                    local isMine = state.cells.toFlag[cell] ~= nil
                    local isSafe = state.cells.toClear[cell] == true
                    local isGuess = bestGuess and cell == bestGuess and config.GuessHelper and not isSafe and not isMine

                    local changed = (isMine ~= cell.isHighlightedMine) or
                                    (isSafe ~= cell.isHighlightedSafe) or
                                    (isGuess ~= cell.isHighlightedGuess)

                    if changed then
                        cell.lastHighlightChange = now
                        cell.isHighlightedMine = isMine
                        cell.isHighlightedSafe = isSafe
                        cell.isHighlightedGuess = isGuess
                    end

                    if isMine or isSafe or isGuess then
                        local color
                        if isSafe then
                            color = COLOR_SAFE
                        elseif isMine then
                            color = COLOR_MINE
                        else
                            color = COLOR_GUESS
                        end
                        local timeSince = now - (cell.lastHighlightChange or 0)
                        local finalColor = color
                        if timeSince < 0.15 then
                            local boost = 1.2
                            finalColor = Color3.new(
                                math.clamp(color.R * boost, 0, 1),
                                math.clamp(color.G * boost, 0, 1),
                                math.clamp(color.B * boost, 0, 1)
                            )
                        end
                        applyHighlight(cell, finalColor)
                    else
                        removeAllHighlights(cell)
                    end
                end
            end
        end
    end
end


local function createGUI()
    if not config.GuiEnabled then return end
    if state.statusGui and state.statusLabel then return end
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MinesweeperSolverGui"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = playerGui
    local label = Instance.new("TextLabel")
    label.Name = "StatusLabel"
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(1, -540, 1, -150)
    label.Size = UDim2.new(0, 520, 0, 140)
    label.TextColor3 = Color3.new(1,1,1)
    label.RichText = true
    label.Text = ""
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Font = Enum.Font.Code
    label.TextSize = 14
    label.Parent = screenGui
    state.statusGui = screenGui
    state.statusLabel = label
end

local function updateGUI()
    if not config.GuiEnabled then return end
    if not state.statusLabel then return end
    local now = tick()
    if now - state.lastGuiUpdate < 0.1 then return end
    state.lastGuiUpdate = now
    local w, h = state.grid.w, state.grid.h
    local numCount = #state.cells.numbered
    local flagCount = 0
    local safeCount = 0
    for _ in pairs(state.cells.toFlag) do flagCount = flagCount + 1 end
    for _ in pairs(state.cells.toClear) do safeCount = safeCount + 1 end
    local hasLogic = next(state.cells.toClear) ~= nil
    local hasGuess = state.bestGuessCell and state.bestGuessScore
    local stateText
    if hasLogic and hasGuess then
        stateText = "State: <font color='#00FF00'>LOGIC + GUESS</font> (safe moves + best guess available)"
    elseif hasLogic then
        stateText = "State: <font color='#00FF00'>LOGIC</font> (safe moves available)"
    elseif hasGuess then
        stateText = "State: <font color='#00AFFF'>GUESS</font> (no certain safe tiles)"
    else
        stateText = "State: <font color='#FFAA00'>UNKNOWN</font> (no info; pure guess)"
    end
    local guessText
    if hasGuess then
        local risk = math.clamp(state.bestGuessScore * 100, 0, 100)
        guessText = string.format("Best guess: ix=%d, iz=%d (~%.1f%%%% mine risk)", 
            state.bestGuessCell.ix, state.bestGuessCell.iz, risk)
    elseif config.GuessHelper then
        guessText = "Best guess: none (all resolved or no info)"
    else
        guessText = "Best guess: disabled (press F8 to enable)"
    end
    local autoText
    if config.AutoComplete then
        autoText = string.format("<font color='#00FF00'>AUTO-TP</font> | Queue: %d tiles", #state.actionQueue)
    else
        autoText = "<font color='#888888'>MANUAL</font> (press F5 to enable auto-tp)"
    end
    local text = string.format(
        "<b>Minesweeper Solver</b>\n" ..
        "Mode: <font color='#%s'>%s</font> | Guess: <font color='#%s'>%s</font> | %s\n" ..
        "Board: %dx%d | Numbered: %d\n" ..
        "Suggestions: %d mines, %d safe\n" ..
        "%s\n" ..
        "%s\n" ..
        "[F6] Toggle Solver | [F8] Guess | [F5] Auto-Teleport",
        config.Enabled and "00FF00" or "FF5555",
        config.Enabled and "ON" or "OFF",
        config.GuessHelper and "00AFFF" or "888888",
        config.GuessHelper and "ON" or "OFF",
        autoText,
        w, h, numCount,
        flagCount, safeCount,
        stateText,
        guessText
    )
    state.statusLabel.Text = text
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F6 then
        config.Enabled = not config.Enabled
        if not config.Enabled then
            clearAllCellBorders()
            config.AutoComplete = false
            state.actionQueue = {}
        end
    elseif input.KeyCode == Enum.KeyCode.F8 then
        config.GuessHelper = not config.GuessHelper
        if not config.GuessHelper then
            state.bestGuessCell = nil
            state.bestGuessScore = nil
        end
    elseif input.KeyCode == Enum.KeyCode.F5 then
        config.AutoComplete = not config.AutoComplete
        if not config.AutoComplete then
            state.actionQueue = {}
        end
    end
end)

RunService.Heartbeat:Connect(function()
    local flagFolder = workspace:FindFirstChild("Flag")
    if not flagFolder then return end
    local partsFolder = flagFolder:FindFirstChild("Parts")
    if not partsFolder then return end
    local partCount = #partsFolder:GetChildren()
    local stateChanged = partCount ~= state.lastPartCount
    if stateChanged then
        state.lastPartCount = partCount
        rebuildGridFromParts(partsFolder)
    end
    if state.grid.w == 0 or state.grid.h == 0 then return end
    if not config.Enabled then
        state.cells.toFlag = {}
        state.cells.toClear = {}
        state.bestGuessCell = nil
        state.bestGuessScore = nil
        state.actionQueue = {}
        updateHighlights()
        createGUI()
        updateGUI()
        return
    end
    updateCellStates(partsFolder)
    local currentNumberedCount = #state.cells.numbered
    local shouldUpdate = stateChanged or currentNumberedCount ~= state.lastNumberedCount
    if shouldUpdate then
        state.lastNumberedCount = currentNumberedCount
        updateLogic()
        updateGuess()
    end
    if config.AutoComplete then
        buildActionQueue()
    end
    processActionQueue()
    updateHighlights()
    createGUI()
    updateGUI()
    
       local player = game.Players.LocalPlayer

local function setupCharacter(character)
    local humanoid = character:WaitForChild("Humanoid")

    task.spawn(function()
        while humanoid.Parent do
            task.wait(0.1)
            if config.AutoComplete then
            if humanoid.FloorMaterial ~= Enum.Material.Air then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end
        end
    end)
end


if player.Character then
    setupCharacter(player.Character)
end


    player.CharacterAdded:Connect(setupCharacter)
end)

print("Custom minesweeper script made by W3ntedd")
