--[[
	================================================================
	Xeno · Визуал + Оптимизация  (только клиент, без читов на игру)
	----------------------------------------------------------------
	Визуал:
	  • ESP — подсветка, имя, полоска HP (проверка команды и дистанции)
	  • Трассеры от низа экрана к игрокам
	  • Прицел
	  • Fullbright — яркое освещение
	Оптимизация:
	  • Минимальное качество рендера + отключение теней
	  • Отключение частиц, трясок, лучей и пост-эффектов (чанками, без фризов)
	  • Адаптивный троттлинг: чем ниже FPS — тем реже обновляется ESP
	  • Кулдаун: далеко стоящие и те, кто вне кадре, не обновляются
	Управление: RightShift — показать / скрыть панель
	================================================================
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Lighting         = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================== КОНФИГ ==============================
local Config = {
	ESP         = true,
	Tracers     = true,
	Crosshair   = true,
	Fullbright  = false,
	NoFX        = false,
	Optimization = true,

	TeamCheck   = true,
	MaxDistance  = 900,

	UpdateRate   = 0.10, -- базовый интервал обновления ESP (сек)
	SlowRate     = 0.20, -- FPS ниже 45
	CriticalRate = 0.35, -- FPS ниже 25

	EnemyColor = Color3.fromRGB(255, 70, 70),
	TeamColor  = Color3.fromRGB(80, 160, 255),
	FillTransparency = 0.78,
}

-- ====================== ПРОВЕРКА DRAWING API ========================
local HasDrawing = false
do
	local ok, obj = pcall(function() return Drawing.new("Line") end)
	if ok and obj then
		HasDrawing = true
		pcall(function() obj:Remove() end)
	end
end

-- ============================ GUI / UI ==============================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "XenoVisualsUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- если скрипт запускали повторно — убираем старую копию
pcall(function()
	local old = CoreGui:FindFirstChild(screenGui.Name)
	if old then old:Destroy() end
end)
pcall(function()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	local old = pg and pg:FindFirstChild(screenGui.Name)
	if old then old:Destroy() end
end)

if not pcall(function() screenGui.Parent = CoreGui end) then
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- ======================= ХЕЛПЕРЫ / ДАННЫЕ ===========================
local cache = {} -- [player] = { hl, bill, nameLabel, hpFill, line, char }

local function charInfo(player)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		return char, hrp, hum
	end
end

local function isEnemy(player)
	if Config.TeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
		return false
	end
	return true
end

local function colorFor(player)
	return isEnemy(player) and Config.EnemyColor or Config.TeamColor
end

local function getEntry(player)
	local e = cache[player]
	if not e then
		e = {}
		cache[player] = e
	end
	return e
end

local function killEsp(entry)
	if entry.hl then pcall(function() entry.hl:Destroy() end); entry.hl = nil end
	if entry.bill then pcall(function() entry.bill:Destroy() end); entry.bill = nil end
	entry.nameLabel, entry.hpFill, entry.char = nil, nil, nil
end

local function killTracer(entry)
	if entry.line then pcall(function() entry.line:Remove() end); entry.line = nil end
end

local function trimEntry(player, e)
	if not e.hl and not e.bill and not e.line then
		cache[player] = nil
	end
end

-- ============================ ЭСП ===================================
local function makeHighlight()
	local hl = Instance.new("Highlight")
	hl.Name = "XenoESP"
	hl.FillColor = Config.EnemyColor
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.FillTransparency = Config.FillTransparency
	hl.OutlineTransparency = 0.15
	hl.Enabled = false
	if not pcall(function() hl.Parent = CoreGui end) then
		hl.Parent = screenGui
	end
	return hl
end

local function makeBillboard()
	local bill = Instance.new("BillboardGui")
	bill.Name = "XenoESPName"
	bill.Size = UDim2.fromOffset(120, 24)
	bill.StudsOffset = Vector3.new(0, 2.3, 0)
	bill.AlwaysOnTop = true
	bill.LightInfluence = 0
	bill.Enabled = false
	bill.ResetOnSpawn = false

	local main = Instance.new("Frame")
	main.Size = UDim2.new(1, 0, 1, 0)
	main.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	main.BackgroundTransparency = 0.35
	main.BorderSizePixel = 0
	main.Parent = bill

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 14)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = ""
	nameLabel.Parent = main

	local hpBack = Instance.new("Frame")
	hpBack.Position = UDim2.new(0, 3, 0, 16)
	hpBack.Size = UDim2.new(1, -6, 0, 5)
	hpBack.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
	hpBack.BorderSizePixel = 0
	hpBack.Parent = main

	local hpFill = Instance.new("Frame")
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(60, 255, 120)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBack

	bill.Parent = screenGui
	return bill, nameLabel, hpFill
end

local function refreshESP()
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or nil

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local entry = cache[player]
			local char, hrp, hum = charInfo(player)

			-- ЭСП выключен — сносим визуал
			if entry and not Config.ESP then
				killEsp(entry)
				trimEntry(player, entry)
			elseif Config.ESP then
				if not entry then entry = getEntry(player) end
				if not entry.hl then
					entry.hl = makeHighlight()
					entry.bill, entry.nameLabel, entry.hpFill = makeBillboard()
				end

				-- видимость: своя команда + дистанция + живой персонаж
				local visible = false
				if char and camPos then
					local dist = (hrp.Position - camPos).Magnitude
					visible = isEnemy(player) and dist <= Config.MaxDistance
				end

				entry.hl.Enabled = visible
				entry.bill.Enabled = visible

				if visible then
					if entry.char ~= char then
						entry.char = char
						entry.hl.Adornee = char
						entry.bill.Adornee = char:FindFirstChild("Head") or char
					end
					entry.hl.FillColor = colorFor(player)
					entry.nameLabel.Text = player.DisplayName
					local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
					entry.hpFill.Size = UDim2.fromScale(ratio, 1)
					entry.hpFill.BackgroundColor3 =
						Color3.fromRGB(60, 255, 120):Lerp(Color3.fromRGB(255, 60, 60), 1 - ratio)
				end
			end
		end
	end
end

-- ========================== ТРАССЕРЫ ================================
local function makeLine()
	local ok, line = pcall(function()
		local l = Drawing.new("Line")
		l.Thickness = 1.5
		l.Transparency = 0.85
		l.Visible = false
		return l
	end)
	if ok then return line end
	return nil
end

local function updateTracers()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local entry = cache[player]

			if Config.Tracers and HasDrawing then
				if not entry then entry = getEntry(player) end
				if not entry.line then entry.line = makeLine() end
				local line = entry.line

				if line then
					local cam = Workspace.CurrentCamera
					local visible = false

					if cam then
						local char, hrp = charInfo(player)
						local camPos = cam.CFrame.Position
						if char and (hrp.Position - camPos).Magnitude <= Config.MaxDistance then
							local sp = cam:WorldToViewportPoint(hrp.Position)
							if sp.Z > 0 then
								local vp = cam.ViewportSize
								line.From = Vector2.new(vp.X / 2, vp.Y)
								line.To = Vector2.new(sp.X, sp.Y)
								line.Color = colorFor(player)
								visible = true
							end
						end
					end
					line.Visible = visible
				end
			elseif entry and entry.line then
				killTracer(entry)
				trimEntry(player, entry)
			end
		end
	end
end

-- ============================ ПРИЦЕЛ ================================
local cross = {}

local function updateCrosshair()
	local show = Config.Crosshair and HasDrawing

	if show and #cross == 0 then
		for i = 1, 4 do
			local ok, l = pcall(function()
				local obj = Drawing.new("Line")
				obj.Color = Color3.fromRGB(0, 255, 220)
				obj.Thickness = 1.5
				obj.Visible = false
				return obj
			end)
			if ok then cross[i] = l end
		end
	end

	if not show then
		for _, l in ipairs(cross) do l.Visible = false end
		return
	end

	local cam = Workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local cx, cy = math.floor(vp.X / 2), math.floor(vp.Y / 2)
	local gap, len = 5, 9

	cross[1].From = Vector2.new(cx - gap - len, cy); cross[1].To = Vector2.new(cx - gap, cy)
	cross[2].From = Vector2.new(cx + gap, cy);       cross[2].To = Vector2.new(cx + gap + len, cy)
	cross[3].From = Vector2.new(cx, cy - gap - len); cross[3].To = Vector2.new(cx, cy - gap)
	cross[4].From = Vector2.new(cx, cy + gap);       cross[4].To = Vector2.new(cx, cy + gap + len)
	for i = 1, 4 do cross[i].Visible = true end
end

-- ======================== ОПТИМИЗАЦИЯ ===============================
local Opt = { applied = false, saved = {} }

function Opt.Apply()
	if Opt.applied then return end
	Opt.applied = true

	-- минимальное качество рендера
	pcall(function()
		local rs = settings().Rendering
		Opt.saved.quality = rs.QualityLevel
		rs.QualityLevel = Enum.QualityLevel.Level01
	end)

	-- тени дают серьёзную нагрузку
	Opt.saved.shadows = Lighting.GlobalShadows
	Lighting.GlobalShadows = false
end

function Opt.Restore()
	if not Opt.applied then return end
	Opt.applied = false
	pcall(function()
		if Opt.saved.quality then
			settings().Rendering.QualityLevel = Opt.saved.quality
		end
	end)
	if Opt.saved.shadows ~= nil then
		Lighting.GlobalShadows = Opt.saved.shadows
	end
end

-- ==================== ОТКЛЮЧЕНИЕ ЭФФЕКТОВ ==========================
local FX = { on = false, disabled = {}, conns = {} }

local LIGHT_CLASSES = {
	BloomEffect = true,
	BlurEffect = true,
	ColorCorrectionEffect = true,
	DepthOfFieldEffect = true,
	SunRaysEffect = true,
}
local LEGACY_FX = { Fire = true, Smoke = true, Sparkles = true }

local function isFx(d)
	if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then return true end
	if LEGACY_FX[d.ClassName] or LIGHT_CLASSES[d.ClassName] then return true end
	return false
end

local function tryDisable(d)
	if FX.disabled[d] then return end
	pcall(function()
		if isFx(d) and d.Enabled then
			FX.disabled[d] = true
			d.Enabled = false
		end
	end)
end

local function connectNew()
	for _, conn in ipairs(FX.conns) do conn:Disconnect() end
	FX.conns = {}
	table.insert(FX.conns, Workspace.DescendantAdded:Connect(tryDisable))
	table.insert(FX.conns, Lighting.DescendantAdded:Connect(tryDisable))
end

function FX.Enable()
	if FX.on then return end
	FX.on = true

	task.spawn(function()
		local all, light = {}, {}
		pcall(function() all = Workspace:GetDescendants() end)
		pcall(function() light = Lighting:GetDescendants() end)

		-- сканируем чанками, чтобы не словить фриз на большой карте
		local i = 1
		while i <= #all do
			if not FX.on then return end
			local last = math.min(i + 1999, #all)
			for k = i, last do tryDisable(all[k]) end
			i = last + 1
			if i <= #all then task.wait() end
		end

		for _, d in ipairs(light) do tryDisable(d) end
		connectNew()
	end)
end

function FX.Disable()
	if not FX.on then return end
	FX.on = false

	for _, conn in ipairs(FX.conns) do conn:Disconnect() end
	FX.conns = {}

	for inst in pairs(FX.disabled) do
		pcall(function()
			if inst.Parent then inst.Enabled = true end
		end)
	end
	FX.disabled = {}
end

-- =========================== FULLBRIGHT =============================
local FB = { on = false, saved = {} }

function FB.Set(on)
	if on and not FB.on then
		FB.on = true
		FB.saved.ambient    = Lighting.Ambient
		FB.saved.outdoor    = Lighting.OutdoorAmbient
		FB.saved.brightness = Lighting.Brightness
		Lighting.Ambient        = Color3.fromRGB(130, 130, 130)
		Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
		Lighting.Brightness     = 2
	elseif not on and FB.on then
		FB.on = false
		Lighting.Ambient        = FB.saved.ambient
		Lighting.OutdoorAmbient = FB.saved.outdoor
		Lighting.Brightness     = FB.saved.brightness
	end
end

-- ============================= ПАНЕЛЬ ===============================
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(200, 300)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = screenGui

local function round(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
end
round(panel, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 70)
stroke.Transparency = 0.4
stroke.Thickness = 1
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.new(0, 12, 0, 8)
title.Size = UDim2.new(1, -24, 0, 18)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(0, 255, 220)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "XENO · VISUALS + FPS"
title.Parent = panel

local fpsLabel = Instance.new("TextLabel")
fpsLabel.Position = UDim2.new(0, 12, 0, 28)
fpsLabel.Size = UDim2.new(1, -24, 0, 16)
fpsLabel.BackgroundTransparency = 1
fpsLabel.Font = Enum.Font.Gotham
fpsLabel.TextSize = 12
fpsLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
fpsLabel.TextXAlignment = Enum.TextXAlignment.Left
fpsLabel.Text = "FPS: --"
fpsLabel.Parent = panel

local toggles = {}

local function addToggle(text, available, getKey, setKey)
	local index = #toggles + 1
	local btn = Instance.new("TextButton")
	btn.Position = UDim2.new(0, 10, 0, 50 + (index - 1) * 36)
	btn.Size = UDim2.new(1, -20, 0, 30)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamSemibold
	btn.TextSize = 13
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.AutoButtonColor = available
	round(btn, 6)

	local function sync()
		local on = available and getKey() or false
		btn.BackgroundColor3 = on and Color3.fromRGB(24, 82, 56) or Color3.fromRGB(34, 34, 42)
		btn.TextColor3 = not available and Color3.fromRGB(90, 90, 95)
			or (on and Color3.fromRGB(120, 255, 175) or Color3.fromRGB(175, 175, 182))
		btn.Text = "   " .. text .. (not available and "  [н/д]" or (on and "  [ON]" or "  [OFF]"))
	end

	if available then
		btn.MouseButton1Click:Connect(function()
			setKey(not getKey())
			sync()
		end)
	end

	sync()
	btn.Parent = panel
	table.insert(toggles, btn)
	return btn
end

addToggle("ESP (имя + HP)", true,
	function() return Config.ESP end,
	function(v) Config.ESP = v end)

addToggle("Трассеры", HasDrawing,
	function() return Config.Tracers end,
	function(v) Config.Tracers = v end)

addToggle("Прицел", HasDrawing,
	function() return Config.Crosshair end,
	function(v) Config.Crosshair = v end)

addToggle("Fullbright", true,
	function() return Config.Fullbright end,
	function(v)
		Config.Fullbright = v
		FB.Set(v)
	end)

addToggle("Убрать эффекты (FPS)", true,
	function() return Config.NoFX end,
	function(v)
		Config.NoFX = v
		if v then FX.Enable() else FX.Disable() end
	end)

addToggle("Оптимизация (качество)", true,
	function() return Config.Optimization end,
	function(v)
		Config.Optimization = v
		if v then Opt.Apply() else Opt.Restore() end
	end)

local panelHeight = 50 + #toggles * 36 + 38
panel.Size = UDim2.fromOffset(200, panelHeight)
panel.Position = UDim2.new(0, 14, 0.5, -math.floor(panelHeight / 2))

local hint = Instance.new("TextLabel")
hint.Position = UDim2.new(0, 10, 1, -32)
hint.Size = UDim2.new(1, -20, 0, 24)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextColor3 = Color3.fromRGB(110, 110, 120)
hint.Text = "RightShift — скрыть панель"
hint.Parent = panel

-- перетаскивание панели
local dragging, dragStart, startPos = false, nil, nil
panel.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = panel.Position
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		panel.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
		panel.Visible = not panel.Visible
	end
end)

-- ====================== ОЧИСТКА ПРИ ВЫХОДЕ ==========================
Players.PlayerRemoving:Connect(function(player)
	local entry = cache[player]
	if entry then
		killEsp(entry)
		killTracer(entry)
		cache[player] = nil
	end
end)

-- ========================= ГЛАВНЫЙ ЦИКЛ =============================
local fps, frames, clockAcc = 60, 0, 0
local espAcc, espRate = 0, Config.UpdateRate

RunService.RenderStepped:Connect(function(dt)
	-- --- FPS + адаптивный троттлинг ---
	frames = frames + 1
	clockAcc = clockAcc + dt
	if clockAcc >= 1 then
		fps = frames / clockAcc
		frames = 0
		clockAcc = 0
		fpsLabel.Text = "FPS: " .. math.floor(fps + 0.5)

		if Config.Optimization then
			if fps < 25 then
				espRate = Config.CriticalRate
			elseif fps < 45 then
				espRate = Config.SlowRate
			else
				espRate = Config.UpdateRate
			end
		else
			espRate = Config.UpdateRate
		end
	end

	-- --- визуал ---
	updateCrosshair()
	updateTracers()

	espAcc = espAcc + dt
	if espAcc >= espRate then
		espAcc = 0
		refreshESP()
	end
end)

-- ============================= СТАРТ ================================
if Config.Optimization then Opt.Apply() end
if Config.NoFX then FX.Enable() end
if Config.Fullbright then FB.Set(true) end
refreshESP()
