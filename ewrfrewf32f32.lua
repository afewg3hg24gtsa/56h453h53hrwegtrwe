local Lighting          = game:GetService("Lighting")
local camera			= workspace.CurrentCamera

local BLUR_SIZE         = Vector2.new(5, 5)
local PART_SIZE         = 0.01
local PART_TRANSPARENCY = 1 - 1e-7
local START_INTENSITY	= 0.3

local BLUR_OBJ          = Instance.new("DepthOfFieldEffect")
BLUR_OBJ.FarIntensity   = 0
BLUR_OBJ.NearIntensity  = START_INTENSITY
BLUR_OBJ.FocusDistance  = 0.25
BLUR_OBJ.InFocusRadius  = 0
BLUR_OBJ.Parent         = Lighting

local PartsList         = {}
local BlursList         = {}
local BlurObjects       = {}
local BlurredGui        = {}

BlurredGui.__index      = BlurredGui

local function rayPlaneIntersect(planePos, planeNormal, rayOrigin, rayDirection)
	local n = planeNormal
	local d = rayDirection
	local v = rayOrigin - planePos

	local num = n:Dot(v)
	local den = n:Dot(d)
	local a = -num / den

	return rayOrigin + a * rayDirection, a
end

local function rebuildPartsList()
	PartsList = {}
	BlursList = {}
	for blurObj, part in pairs(BlurObjects) do
		table.insert(PartsList, part)
		table.insert(BlursList, blurObj)
	end
end

function BlurredGui.new(frame)
	local blurPart        = Instance.new("Part")
	blurPart.Size         = Vector3.new(PART_SIZE, PART_SIZE, PART_SIZE)
	blurPart.Anchored     = true
	blurPart.CanCollide   = false
	blurPart.CanTouch     = false
	blurPart.Material     = Enum.Material.Glass
	blurPart.Transparency = PART_TRANSPARENCY
	blurPart.Parent       = workspace.CurrentCamera

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent   = blurPart

	local ignoreInset = false
	local currentObj  = frame
	while currentObj do
		if currentObj:IsA("ScreenGui") then
			ignoreInset = currentObj.IgnoreGuiInset
			break
		end
		currentObj = currentObj.Parent
	end

	local corner = frame:FindFirstChildOfClass("UICorner")
	local cornerRadius = corner and corner.CornerRadius or UDim.new(0,0)

	local new = setmetatable({
		Frame          = frame;
		Part           = blurPart;
		Mesh           = mesh;
		IgnoreGuiInset = ignoreInset;
		CornerRadius   = cornerRadius;
	}, BlurredGui)

	BlurObjects[new] = blurPart
	rebuildPartsList()

	game:GetService("RunService"):BindToRenderStep("BlurGuiUpdate", Enum.RenderPriority.Camera.Value + 1, function()
		blurPart.CFrame = camera.CFrame
		BlurredGui.updateAll()
	end)

	return new
end

local function updateGui(blurObj)
	local frame  = blurObj.Frame
	local part   = blurObj.Part
	local mesh   = blurObj.Mesh

	if not frame.Visible then
		part.Transparency = 1
		return
	end

	part.Transparency = PART_TRANSPARENCY

	local corner0 = frame.AbsolutePosition
	local corner1 = corner0 + frame.AbsoluteSize

	local ray0, ray1
	if blurObj.IgnoreGuiInset then
		ray0 = camera:ViewportPointToRay(corner0.X, corner0.Y, 1)
		ray1 = camera:ViewportPointToRay(corner1.X, corner1.Y, 1)
	else
		ray0 = camera:ScreenPointToRay(corner0.X, corner0.Y, 1)
		ray1 = camera:ScreenPointToRay(corner1.X, corner1.Y, 1)
	end

	local planeOrigin = camera.CFrame.Position + camera.CFrame.LookVector * (0.05 - camera.NearPlaneZ)
	local planeNormal = camera.CFrame.LookVector

	local pos0 = rayPlaneIntersect(planeOrigin, planeNormal, ray0.Origin, ray0.Direction)
	local pos1 = rayPlaneIntersect(planeOrigin, planeNormal, ray1.Origin, ray1.Direction)

	pos0 = camera.CFrame:PointToObjectSpace(pos0)
	pos1 = camera.CFrame:PointToObjectSpace(pos1)

	local size   = pos1 - pos0
	local center = (pos0 + pos1)/2

	mesh.Offset = center
	mesh.Scale  = Vector3.new(size.X, size.Y, 1) / PART_SIZE

	if blurObj.CornerRadius then
		local absR = blurObj.CornerRadius.Offset > 0 and blurObj.CornerRadius.Offset or blurObj.CornerRadius.Scale * math.min(frame.AbsoluteSize.X, frame.AbsoluteSize.Y)
		mesh.Scale = Vector3.new(size.X - absR*2, size.Y - absR*2, 1) / PART_SIZE
	end
end

function BlurredGui.updateAll()
	BLUR_OBJ.NearIntensity = START_INTENSITY
	for i = 1, #BlursList do
		updateGui(BlursList[i])
	end
	local cframes = table.create(#BlursList, workspace.CurrentCamera.CFrame)
	workspace:BulkMoveTo(PartsList, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	BLUR_OBJ.FocusDistance = 0.25 - camera.NearPlaneZ
end

function BlurredGui:Destroy()
	self.Part:Destroy()
	BlurObjects[self] = nil
	rebuildPartsList()
end

return BlurredGui
