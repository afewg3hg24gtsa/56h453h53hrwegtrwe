-- RoundedBlur.lua
local module = {}

function module.dobluridk(frame) -- pass the GuiObject (Frame, ImageLabel, etc.)
	local RunService = game:GetService('RunService')
	local camera = workspace.CurrentCamera
	local MTREL = "Glass"

	-- root folder in workspace camera so parts follow camera
	local root = Instance.new('Folder', camera)
	root.Name = 'BlurSnox_' .. tostring(math.random(1,99999998))

	-- DepthOfField (kept from your original script)
	local DepthOfField = Instance.new('DepthOfFieldEffect', game:GetService('Lighting'))
	DepthOfField.FarIntensity = 0
	DepthOfField.FocusDistance = 51.6
	DepthOfField.InFocusRadius = 50
	DepthOfField.NearIntensity = 1
	DepthOfField.Name = "DPT_"..tostring(math.random(1,99999998))

	-- returned blur control
	local blur = {
		rounding = 0,   -- pixels (like UICorner Radius). Change at runtime.
		segments = 8,   -- how many segments per corner (higher = smoother)
		_transparent = 0.98,
		_color = BrickColor.new('Institutional white'),
		_parts = {},
		_destroyed = false
	}

	-- Unique id for BindToRenderStep
	local uid = ('neon::%d'):format(math.random(1,1e9))

	-- Wait for camera to be ready (same safety check you had)
	do
		local function IsNotNaN(x) return x == x end
		local continue = IsNotNaN(camera:ScreenPointToRay(0,0).Origin.x)
		while not continue do
			RunService.RenderStepped:Wait()
			continue = IsNotNaN(camera:ScreenPointToRay(0,0).Origin.x)
		end
	end

	-- =============== Geometry helpers (adapted from your original) ===============
	local acos, max, pi, sqrt = math.acos, math.max, math.pi, math.sqrt

	-- DrawTriangle: creates (or re-uses) two wedge parts that visually cover one triangle
	-- returns p0, p1
	local function DrawTriangle(v1, v2, v3, p0, p1)
		-- robust triangle -> two wedges routine (kept from your original source)
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

		local para = ( (B-A).x*(C-A).x + (B-A).y*(C-A).y + (B-A).z*(C-A).z ) / (A-B).magnitude
		local perp = sqrt((C-A).magnitude^2 - para*para)
		local dif_para = (A - B).magnitude - para

		local st = CFrame.new(B, A)
		local za = CFrame.Angles(pi/2,0,0)

		local cf0 = st

		local Top_Look = (cf0 * za).lookVector
		local Mid_Point = A + CFrame.new(A, B).lookVector * para
		local Needed_Look = CFrame.new(Mid_Point, C).lookVector
		local dot = Top_Look.x*Needed_Look.x + Top_Look.y*Needed_Look.y + Top_Look.z*Needed_Look.z

		local ac = CFrame.Angles(0, 0, acos(math.clamp(dot, -1, 1)))

		cf0 = cf0 * ac
		if ((cf0 * za).lookVector - Needed_Look).magnitude > 0.01 then
			cf0 = cf0 * CFrame.Angles(0, 0, -2*acos(math.clamp(dot, -1, 1)))
		end
		cf0 = cf0 * CFrame.new(0, perp/2, -(dif_para + para/2))

		local cf1 = st * ac * CFrame.Angles(0, pi, 0)
		if ((cf1 * za).lookVector - Needed_Look).magnitude > 0.01 then
			cf1 = cf1 * CFrame.Angles(0, 0, 2*acos(math.clamp(dot, -1, 1)))
		end
		cf1 = cf1 * CFrame.new(0, perp/2, dif_para/2)

		if not p0 then
			p0 = Instance.new('Part')
			-- try to be compatible with modern properties:
			p0.Anchored = true
			p0.CanCollide = false
			p0.CastShadow = false
			p0.Material = MTREL
			p0.Size = Vector3.new(0.2, 0.2, 0.2)
			local mesh = Instance.new('SpecialMesh', p0)
			mesh.MeshType = Enum.MeshType.Wedge
		end
		p0.Mesh.Scale = Vector3.new(0, perp/0.2, para/0.2)
		p0.CFrame = cf0

		if not p1 then
			p1 = p0:Clone()
		end
		p1.Mesh.Scale = Vector3.new(0, perp/0.2, dif_para/0.2)
		p1.CFrame = cf1

		return p0, p1
	end

	-- helper to add two triangles that form a quad: (a,b,c) and (c,b,d)
	local function DrawQuad(a,b,c,d, parts, nextIndex)
		-- parts is the blur._parts table; nextIndex is integer index for reuse
		-- returns new nextIndex
		local p0, p1 = DrawTriangle(a,b,c, parts[nextIndex], parts[nextIndex+1])
		parts[nextIndex], parts[nextIndex+1] = p0, p1
		nextIndex = nextIndex + 2

		local p2, p3 = DrawTriangle(c,b,d, parts[nextIndex], parts[nextIndex+1])
		parts[nextIndex], parts[nextIndex+1] = p2, p3
		nextIndex = nextIndex + 2

		return nextIndex
	end

	-- Reusable layout: compute 3D origin for a screen point
	local function ScreenToWorld(x, y, zIndex)
		-- FIX: Use a fixed distance from camera instead of zIndex-based offset
		-- This prevents camera jittering and ensures consistent positioning
		local ray = camera:ScreenPointToRay(x, y)
		return ray.Origin + ray.Direction * 0.5 -- Fixed distance of 0.5 studs from camera
	end

	-- get parents chain rotation handling (copied from your original)
	local parents = {}
	do
		local function add(child)
			if not child then return end
			if child:IsA'GuiObject' then
				parents[#parents + 1] = child
				add(child.Parent)
			end
		end
		add(frame)
	end

	-- Track previous part count so we can destroy extras
	local prevPartCount = 0

	-- UpdateOrientation will recompute all geometry each frame
	local function UpdateOrientation()
		if blur._destroyed then return end

		local properties = {
			Transparency = blur._transparent,
			BrickColor = blur._color
		}

		-- compute 2D corner points of the frame in screen-space
		local tl = frame.AbsolutePosition
		local br = frame.AbsolutePosition + frame.AbsoluteSize
		local tr = Vector2.new(br.x, tl.y)
		local bl = Vector2.new(tl.x, br.y)
		
		-- FIX: Use a consistent z-index that doesn't cause camera movement
		local zIndex = 0.5 -- Fixed value instead of frame.ZIndex dependent

		-- handle rotation of GUI (sum of parent rotations, same as you did)
		local rot = 0
		for _, v in ipairs(parents) do rot = rot + v.Rotation end
		if rot ~= 0 and rot % 180 ~= 0 then
			local mid = tl:lerp(br, 0.5)
			local s, c = math.sin(math.rad(rot)), math.cos(math.rad(rot))
			local function rotPoint(p)
				return Vector2.new(
					c*(p.x - mid.x) - s*(p.y - mid.y),
					s*(p.x - mid.x) + c*(p.y - mid.y)
				) + mid
			end
			tl = rotPoint(tl)
			tr = rotPoint(tr)
			bl = rotPoint(bl)
			br = rotPoint(br)
		end

		-- clamp rounding to reasonable value (half smallest dimension)
		local frameW = math.abs(br.x - tl.x)
		local frameH = math.abs(br.y - tl.y)
		local maxR = math.floor(math.min(frameW, frameH) / 2)
		local r = math.max(0, math.min(blur.rounding or 0, maxR))

		-- FIX: More precise inner rectangle calculation to prevent oversizing
		-- Use exact pixel boundaries to match the frame exactly
		local ctl = tl + Vector2.new(r, r)
		local ctr = tr + Vector2.new(-r, r)
		local cbr = br + Vector2.new(-r, -r)
		local cbl = bl + Vector2.new(r, -r)

		-- prepare parts table and an index pointer for reuse
		local parts = blur._parts
		local nextIndex = 1

		-- Helper to push a quad to parts (reusing DrawQuad)
		local function pushQuad(pA, pB, pC, pD)
			-- convert to world points using fixed zIndex
			local a = ScreenToWorld(pA.x, pA.y, zIndex)
			local b = ScreenToWorld(pB.x, pB.y, zIndex)
			local c = ScreenToWorld(pC.x, pC.y, zIndex)
			local d = ScreenToWorld(pD.x, pD.y, zIndex)
			nextIndex = DrawQuad(a,b,c,d, parts, nextIndex)
		end

		-- 1) center rectangle (if r is small it becomes full rect)
		if r > 0 then
			pushQuad(ctl, ctr, cbl, cbr)
		else
			-- When no rounding, draw the full rectangle as a single quad
			pushQuad(tl, tr, bl, br)
		end

		-- 2) edge rectangles (top, bottom, left, right)
		if r > 0 then
			-- FIX: Ensure edge rectangles exactly match frame boundaries
			-- top strip
			pushQuad(Vector2.new(tl.x, tl.y), Vector2.new(tr.x, tr.y), ctl, ctr)
			-- bottom strip
			pushQuad(cbl, cbr, Vector2.new(bl.x, bl.y), Vector2.new(br.x, br.y))
			-- left strip
			pushQuad(Vector2.new(tl.x, tl.y), ctl, Vector2.new(bl.x, bl.y), cbl)
			-- right strip
			pushQuad(ctr, Vector2.new(tr.x, tr.y), cbr, Vector2.new(br.x, br.y))
		end

		-- 3) corner quarter-circles (approximate by triangle fans)
		if r > 0 then
			local segs = math.max(1, math.floor(blur.segments or 8))
			-- define corner centers in screen-space (these are the inner rectangle corners)
			local centers = {
				{ center = ctl, angleStart = pi,        angleEnd = 3*pi/2 }, -- top-left (180 -> 270)
				{ center = ctr, angleStart = 3*pi/2,   angleEnd = 2*pi     }, -- top-right (270 -> 360)
				{ center = cbr, angleStart = 0,        angleEnd = pi/2    }, -- bottom-right (0 -> 90)
				{ center = cbl, angleStart = pi/2,     angleEnd = pi      }, -- bottom-left (90 -> 180)
			}

			for _, corner in ipairs(centers) do
				local C = corner.center
				local a0 = corner.angleStart
				local a1 = corner.angleEnd
				local step = (a1 - a0) / segs

				-- build arc points (screen-space)
				local arc = {}
				for i = 0, segs do
					local ang = a0 + step * i
					local px = C.x + math.cos(ang) * r
					local py = C.y + math.sin(ang) * r
					arc[#arc + 1] = Vector2.new(px, py)
				end

				-- triangle fan: center -> arc[i] -> arc[i+1]
				local center3 = ScreenToWorld(C.x, C.y, zIndex)
				for i = 1, #arc - 1 do
					local a3 = ScreenToWorld(arc[i].x, arc[i].y, zIndex)
					local b3 = ScreenToWorld(arc[i+1].x, arc[i+1].y, zIndex)
					-- use DrawTriangle directly (it returns two parts)
					local p0, p1 = DrawTriangle(center3, a3, b3, parts[nextIndex], parts[nextIndex+1])
					parts[nextIndex], parts[nextIndex+1] = p0, p1
					nextIndex = nextIndex + 2
				end
			end
		end

		-- destroy excess parts from previous frame if we used fewer this frame
		local used = nextIndex - 1
		if prevPartCount > used then
			for i = used + 1, prevPartCount do
				local p = parts[i]
				if p and p.Parent then
					p.Parent = nil
					-- prefer to destroy to avoid clutter in workspace
					p:Destroy()
				end
				parts[i] = nil
			end
		end
		prevPartCount = used

		-- set parents & visuals for all used parts
		for i = 1, used do
			local p = parts[i]
			if p then
				if not p.Parent then p.Parent = root end
				-- apply visual props
				p.Transparency = blur._transparent
				p.BrickColor = blur._color
			end
		end
	end

	-- bind the render step (low priority number is fine)
	RunService:BindToRenderStep(uid, Enum.RenderPriority.Camera.Value + 1, UpdateOrientation)

	-- cleanup method
	function blur:Destroy()
		if blur._destroyed then return end
		blur._destroyed = true
		-- unbind render step
		pcall(function() RunService:UnbindFromRenderStep(uid) end)
		-- destroy parts and folder
		for _, p in ipairs(blur._parts) do
			if p and p.Parent then p.Parent = nil end
			if p and p.Destroy then
				p:Destroy()
			end
		end
		blur._parts = {}
		if root and root.Parent then root:Destroy() end
		-- also remove the DepthOfField effect we created (optional safety)
		pcall(function()
			if DepthOfField and DepthOfField.Parent then DepthOfField:Destroy() end
		end)
	end

	-- expose a quick function to force an immediate update (useful after changing properties)
	function blur:Refresh()
		UpdateOrientation()
	end

	-- initial update
	UpdateOrientation()

	return blur
end

return module
