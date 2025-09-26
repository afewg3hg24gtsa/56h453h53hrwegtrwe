-- RoundedBlurFixed.lua
local module = {}

-- Usage:
-- local blur = require(path.to.RoundedBlurFixed).dobluridk(myFrame)
-- blur.rounding = 12
-- blur.segments = 12
-- blur.distance = 8
-- blur.enabled = true
-- blur:Destroy()

function module.dobluridk(frame, opts)
	local RunService = game:GetService("RunService")
	local camera = workspace.CurrentCamera

	-- Options with sensible defaults
	opts = opts or {}
	local MTREL = opts.material or Enum.Material.Glass
	local createDOF = opts.createDepthOfField or false -- default: false (avoid camera tweaks)
	local defaultDistance = opts.distance or 8 -- studs in front of camera where overlay is placed

	-- folder parented to camera so parts follow camera movement/rotation
	local root = Instance.new("Folder")
	root.Name = "BlurSnox_" .. tostring(math.random(1, 99999999))
	root.Parent = camera

	-- optional DOF (disabled by default to avoid camera changes)
	local DepthOfField
	if createDOF then
		DepthOfField = Instance.new("DepthOfFieldEffect")
		DepthOfField.FarIntensity = 0
		DepthOfField.FocusDistance = 51.6
		DepthOfField.InFocusRadius = 50
		DepthOfField.NearIntensity = 1
		DepthOfField.Name = "DPT_" .. tostring(math.random(1, 99999999))
		DepthOfField.Parent = game:GetService("Lighting")
	end

	-- The publicly returned blur controller
	local blur = {
		rounding = opts.rounding or 0,   -- pixels (like UICorner radius)
		segments = opts.segments or 8,   -- number of segments per corner
		distance = defaultDistance,      -- studs in front of camera to place the overlay
		_transparent = (opts.transparency ~= nil) and opts.transparency or 0.98,
		_color = opts.color or BrickColor.new("Institutional white"),
		enabled = true,
		_parts = {},
		_destroyed = false
	}

	-- small epsilon for mesh X scale (avoid zero because some renderers behave oddly)
	local EPS = 1e-4
	local WEDGE_BASE = 0.2 -- base part size used to compute mesh scale (kept small)

	-- wait until camera is ready (same safety check you've used)
	do
		local function IsNotNaN(x) return x == x end
		local ok = IsNotNaN(camera:ScreenPointToRay(0, 0).Origin.x)
		while not ok do
			RunService.RenderStepped:Wait()
			ok = IsNotNaN(camera:ScreenPointToRay(0, 0).Origin.x)
		end
	end

	-- Geometry helpers (adapted from your original routine)
	local acos, max, pi, sqrt = math.acos, math.max, math.pi, math.sqrt

	local function DrawTriangle(v1, v2, v3, p0, p1)
		local s1 = (v1 - v2).magnitude
		local s2 = (v2 - v3).magnitude
		local s3 = (v3 - v1).magnitude
		local smax = max(s1, s2, s3)
		local A, B, C
		if s1 == smax then
			A, B, C = v1, v2, v3
		elseif s2 == smax then
			A, B, C = v2, v3, v1
		else
			A, B, C = v3, v1, v2
		end

		local denom = (A - B).magnitude
		-- avoid division by zero
		if denom == 0 then denom = 1 end

		local para = (((B - A).x * (C - A).x) + ((B - A).y * (C - A).y) + ((B - A).z * (C - A).z)) / denom
		local perp = sqrt(math.max(0, (C - A).magnitude ^ 2 - para * para))
		local dif_para = (A - B).magnitude - para

		local st = CFrame.new(B, A)
		local za = CFrame.Angles(pi / 2, 0, 0)

		local cf0 = st

		local Top_Look = (cf0 * za).lookVector
		local Mid_Point = A + CFrame.new(A, B).lookVector * para
		local Needed_Look = CFrame.new(Mid_Point, C).lookVector
		local dot = Top_Look.x * Needed_Look.x + Top_Look.y * Needed_Look.y + Top_Look.z * Needed_Look.z

		local ac = CFrame.Angles(0, 0, acos(math.clamp(dot, -1, 1)))

		cf0 = cf0 * ac
		if ((cf0 * za).lookVector - Needed_Look).magnitude > 0.01 then
			cf0 = cf0 * CFrame.Angles(0, 0, -2 * acos(math.clamp(dot, -1, 1)))
		end
		cf0 = cf0 * CFrame.new(0, perp / 2, -(dif_para + para / 2))

		local cf1 = st * ac * CFrame.Angles(0, pi, 0)
		if ((cf1 * za).lookVector - Needed_Look).magnitude > 0.01 then
			cf1 = cf1 * CFrame.Angles(0, 0, 2 * acos(math.clamp(dot, -1, 1)))
		end
		cf1 = cf1 * CFrame.new(0, perp / 2, dif_para / 2)

		-- create or reuse parts and their wedge meshes
		if not p0 or not p0:IsA("Part") then
			p0 = Instance.new("Part")
			p0.Anchored = true
			p0.CanCollide = false
			p0.CastShadow = false
			p0.Size = Vector3.new(WEDGE_BASE, WEDGE_BASE, WEDGE_BASE)
			p0.Name = "BlurPart"
			p0.Material = MTREL
			local mesh = Instance.new("SpecialMesh", p0)
			mesh.MeshType = Enum.MeshType.Wedge
			mesh.Name = "WedgeMesh"
		end
		-- access the special mesh safely
		local m0 = p0:FindFirstChild("WedgeMesh")
		if m0 then
			m0.Scale = Vector3.new(EPS, math.max(perp / WEDGE_BASE, EPS), math.max(para / WEDGE_BASE, EPS))
		end
		p0.CFrame = cf0

		if not p1 or not p1:IsA("Part") then
			p1 = p0:Clone()
		end
		local m1 = p1:FindFirstChild("WedgeMesh")
		if m1 then
			m1.Scale = Vector3.new(EPS, math.max(perp / WEDGE_BASE, EPS), math.max(dif_para / WEDGE_BASE, EPS))
		end
		p1.CFrame = cf1

		return p0, p1
	end

	local function DrawQuad(a, b, c, d, parts, nextIndex)
		-- returns nextIndex
		local p0, p1 = DrawTriangle(a, b, c, parts[nextIndex], parts[nextIndex + 1])
		parts[nextIndex], parts[nextIndex + 1] = p0, p1
		nextIndex = nextIndex + 2

		local p2, p3 = DrawTriangle(c, b, d, parts[nextIndex], parts[nextIndex + 1])
		parts[nextIndex], parts[nextIndex + 1] = p2, p3
		nextIndex = nextIndex + 2

		return nextIndex
	end

	-- Convert screen x,y to a world point placed at a fixed distance from the camera
	local function ScreenToWorld(x, y, dist)
		-- use a ray then place at camera + direction * dist
		local ray = camera:ScreenPointToRay(x, y, 0)
		local dir = ray.Direction.Unit
		local camPos = camera.CFrame.Position
		return camPos + dir * dist
	end

	-- parents chain rotation handling (same approach as earlier)
	local parents = {}
	do
		local function add(child)
			if not child then return end
			if child:IsA("GuiObject") then
				parents[#parents + 1] = child
				add(child.Parent)
			end
		end
		add(frame)
	end

	local prevPartCount = 0

	-- UpdateOrientation recomputes everything each frame
	local function UpdateOrientation()
		-- early exits
		if blur._destroyed then return end
		if not blur.enabled then return end

		-- Auto-destroy if the gui no longer exists or was removed from the hierarchy
		-- (IsDescendantOf is robust)
		local ok = pcall(function() return frame and frame:IsDescendantOf(game) end)
		if not ok or not frame or not frame:IsDescendantOf(game) then
			blur:Destroy()
			return
		end

		-- compute screen-space corners (tl,tr,bl,br)
		local tl = frame.AbsolutePosition
		local br = frame.AbsolutePosition + frame.AbsoluteSize
		local tr = Vector2.new(br.x, tl.y)
		local bl = Vector2.new(tl.x, br.y)

		-- account for GUI rotation (sum of parent rotations like your original)
		local rot = 0
		for _, v in ipairs(parents) do rot = rot + v.Rotation end
		if rot ~= 0 and rot % 180 ~= 0 then
			local mid = tl:lerp(br, 0.5)
			local s, c = math.sin(math.rad(rot)), math.cos(math.rad(rot))
			local function rotPoint(p)
				return Vector2.new(
					c * (p.x - mid.x) - s * (p.y - mid.y),
					s * (p.x - mid.x) + c * (p.y - mid.y)
				) + mid
			end
			tl = rotPoint(tl)
			tr = rotPoint(tr)
			bl = rotPoint(bl)
			br = rotPoint(br)
		end

		-- clamp rounding
		local frameW = math.abs(br.x - tl.x)
		local frameH = math.abs(br.y - tl.y)
		local maxR = math.floor(math.min(frameW, frameH) / 2)
		local r = math.max(0, math.min(blur.rounding or 0, maxR))

		-- inner rectangle inset by r
		local ctl = tl + Vector2.new(r, r)
		local ctr = tr + Vector2.new(-r, r)
		local cbr = br + Vector2.new(-r, -r)
		local cbl = bl + Vector2.new(r, -r)

		-- prepare carves
		local parts = blur._parts
		local nextIndex = 1

		local function pushQuad(pA, pB, pC, pD)
			local a = ScreenToWorld(pA.x, pA.y, blur.distance)
			local b = ScreenToWorld(pB.x, pB.y, blur.distance)
			local c = ScreenToWorld(pC.x, pC.y, blur.distance)
			local d = ScreenToWorld(pD.x, pD.y, blur.distance)
			nextIndex = DrawQuad(a, b, c, d, parts, nextIndex)
		end

		-- center rect (or full rect if r == 0)
		pushQuad(ctl, ctr, cbl, cbr)

		-- edge strips
		if r > 0 then
			-- top
			pushQuad(Vector2.new(ctl.x, tl.y), Vector2.new(ctr.x, tr.y), ctl, ctr)
			-- bottom
			pushQuad(cbl, cbr, Vector2.new(cbl.x, br.y), Vector2.new(cbr.x, br.y))
			-- left
			pushQuad(Vector2.new(tl.x, ctl.y), ctl, Vector2.new(bl.x, cbl.y), cbl)
			-- right
			pushQuad(ctr, Vector2.new(tr.x, ctr.y), cbr, Vector2.new(br.x, cbr.y))
		end

		-- corner quarter-circles approximated with triangle fans
		if r > 0 then
			local segs = math.max(1, math.floor(blur.segments or 8))
			local centers = {
				{ center = ctl, angleStart = pi,      angleEnd = 3 * pi / 2 }, -- top-left
				{ center = ctr, angleStart = 3*pi/2,  angleEnd = 2 * pi     }, -- top-right
				{ center = cbr, angleStart = 0,       angleEnd = pi / 2     }, -- bottom-right
				{ center = cbl, angleStart = pi/2,    angleEnd = pi         }, -- bottom-left
			}

			for _, corner in ipairs(centers) do
				local C = corner.center
				local a0, a1 = corner.angleStart, corner.angleEnd
				local step = (a1 - a0) / segs
				-- build arc points
				local arc = {}
				for i = 0, segs do
					local ang = a0 + step * i
					arc[#arc + 1] = Vector2.new(C.x + math.cos(ang) * r, C.y + math.sin(ang) * r)
				end

				-- triangle fan center (inner corner)
				local center3 = ScreenToWorld(C.x, C.y, blur.distance)
				for i = 1, #arc - 1 do
					local a3 = ScreenToWorld(arc[i].x, arc[i].y, blur.distance)
					local b3 = ScreenToWorld(arc[i + 1].x, arc[i + 1].y, blur.distance)
					local p0, p1 = DrawTriangle(center3, a3, b3, parts[nextIndex], parts[nextIndex + 1])
					parts[nextIndex], parts[nextIndex + 1] = p0, p1
					nextIndex = nextIndex + 2
				end
			end
		end

		-- destroy excess parts from previous frame
		local used = nextIndex - 1
		if prevPartCount > used then
			for i = used + 1, prevPartCount do
				local p = parts[i]
				if p then
					if p.Parent then p.Parent = nil end
					p:Destroy()
				end
				parts[i] = nil
			end
		end
		prevPartCount = used

		-- assign parents + visuals
		for i = 1, used do
			local p = parts[i]
			if p then
				if not p.Parent then p.Parent = root end
				p.Transparency = blur._transparent
				p.BrickColor = blur._color
				p.Material = MTREL
			end
		end
	end

	-- Bind with a stable priority (higher than camera so it updates after camera movement)
	local uid = "BlurFixed::" .. tostring(math.random(1, 1e9))
	RunService:BindToRenderStep(uid, Enum.RenderPriority.Camera.Value + 1, UpdateOrientation)

	-- Public methods
	function blur:Destroy()
		if blur._destroyed then return end
		blur._destroyed = true
		-- unbind
		pcall(function() RunService:UnbindFromRenderStep(uid) end)
		-- destroy parts
		for _, p in ipairs(blur._parts) do
			if p and p.Parent then p.Parent = nil end
			if p and p.Destroy then p:Destroy() end
		end
		blur._parts = {}
		-- destroy root
		if root and root.Parent then root:Destroy() end
		-- remove optional DOF if we created it
		if DepthOfField and DepthOfField.Parent then
			pcall(function() DepthOfField:Destroy() end)
		end
	end

	function blur:Refresh()
		UpdateOrientation()
	end

	-- initial update
	UpdateOrientation()

	return blur
end

return module
