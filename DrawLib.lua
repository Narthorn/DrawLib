--- TODO
--
--- Test other Vector3 interpolation methods
--- Fix WorldLocToScreenPoint outside-of-screen bugging
--- Allow re-interpolation of curved path with fewer points based on distance to player
--- Make a proper Path object

DrawLib = {
	name = "DrawLib",
	version = {0,0,11},
	tPaths = {},
	tStyle = {
		nLineWidth = 3,
		crLineColor = ApolloColor.new(0/255, 160/255,  200/255):ToTable(),
		bOutline = true,
	},

	-- Cached circle vectors
	tCircle = setmetatable({}, {__index = function(self, nSides)
		local tVectors = DrawLib:CalcCircleVectors(nSides)
		self[nSides] = tVectors
		return tVectors
	end}),
}

function DrawLib:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("DrawLib.xml")
	self.wndOverlay = Apollo.LoadForm(self.xmlDoc, "Overlay", "InWorldHudStratum", self)
end

-- API

function DrawLib:UnitLine(unitSrc, unitDst, tStyle)
	if unitSrc and unitSrc:IsValid() then
		if unitDst and unitDst:IsValid() then
			return self:Path({{unit = unitSrc}, {unit = unitDst}}, tStyle or self.tStyle)
		else
		 	Print("DrawLib: Invalid destination unit in DrawLib:UnitLine()")
		end
	else
		Print("DrawLib: Invalid source unit in DrawLib:UnitLine()")
	end
end

function DrawLib:UnitText(unit, text)
	if unit and unit:IsValid() then
		local wndMark = Apollo.LoadForm(self.xmlDoc, "unitMark", "FixedHudStratumHigh", self)
		wndMark:FindChild("Text"):SetText(text)
		return self:Path({{unit = unit, wndMark = wndMark}})
	else
		Print("DrawLib: Invalid unit in DrawLib:UnitText()")
	end
end

function DrawLib:Text(pos, text, style)
	local wndMark = Apollo.LoadForm(self.xmlDoc, "unitMark", "FixedHudStratumHigh", self)
	local wndText = wndMark:FindChild("Text")
	wndText:SetText(text)
	if style and style.color then wndText:SetColor(style.color) end
	if style and style.font  then wndText:SetFont(style.font) end
	return self:Path({{vPos = Vector3.New(pos), wndMark = wndMark}})
end

function DrawLib:UnitCircle(unit, fRadius, nSides, tStyle)
	nSides = nSides or 10
	fRadius = fRadius or 5

	local tCircle = self.tCircle[nSides]
	
	local tVertices = {}
	for i=1,#tCircle do tVertices[i] = {vPos = tCircle[i]*fRadius} end
	
	local tPath = self:Path(tVertices, tStyle)
	tPath.unit = unit
	
	return tPath
end

function DrawLib:Path(tVertices, tStyle)
	if #self.tPaths == 0 then Apollo.RegisterEventHandler("NextFrame", "OnFrame", DrawLib) end
	local tPath = {tVertices = tVertices, tStyle = setmetatable(tStyle or {}, {__index = self.tStyle})}
	self.tPaths[#self.tPaths+1] = tPath
	return tPath
end

function DrawLib:Destroy(tPath)
	for i=#self.tPaths,1,-1 do
		if self.tPaths[i] == tPath then
			for _,tVertex in pairs(tPath.tVertices) do
				if tVertex.wndMark then
					tVertex.wndMark:Destroy()
					tVertex.wndMark = nil
				end
			end

			if tPath.tPixies        then self:UpdatePixies(tPath.tPixies, {})        end
			if tPath.tPixiesOutline then self:UpdatePixies(tPath.tPixiesOutline, {}) end
			table.remove(self.tPaths,i)
		end
	end
	if #self.tPaths == 0 then Apollo.RemoveEventHandler("NextFrame", self) end
end

-- Draw Handlers

function DrawLib:OnFrame()
	for i=#self.tPaths,1,-1 do
		self:DrawPath(self.tPaths[i])
	end
end

function DrawLib:DrawPath(tPath)
	local tScreenPoints = {}
	local vOffset = tPath.vOffset
	local fRotation
	
	if tPath.unit then
		if tPath.unit:IsValid() then
			if vOffset then
				vOffset = vOffset + Vector3.New(tPath.unit:GetPosition())
			else
				vOffset = Vector3.New(tPath.unit:GetPosition())
			end
			fRotation = math.pi + tPath.unit:GetHeading()
		else
			self:Destroy(tPath)
			return
		end
	end
	
	if self:UpdateVertices(tPath.tVertices, vOffset, fRotation) then
		if tPath.tStyle.bOutline then
			tPath.tPixiesOutline = tPath.tPixiesOutline or {}
			self:UpdatePixies(tPath.tPixiesOutline, tPath.tVertices, tPath.tStyle, true)
		elseif tPath.tPixiesOutline then
			self:UpdatePixies(tPath.tPixiesOutline, {})
		end
		
		tPath.tPixies = tPath.tPixies or {}
		self:UpdatePixies(tPath.tPixies, tPath.tVertices, tPath.tStyle)
	else
		self:Destroy(tPath)
	end
end

function DrawLib:UpdateVertices(tVertices, vOffset, fRotation)
	local fRotate = fRotation and self:Rotate(fRotation)
	
	for i=1,#tVertices do
		local vPoint
		local tVertex = tVertices[i]
		local unit = tVertex.unit
		
		if unit then
			if unit:IsValid() then
				if tVertex.wndMark then tVertex.wndMark:SetUnit(unit) end
				vPoint = Vector3.New(unit:GetPosition())
			else
				return false
			end
		else 
			vPoint = tVertex.vPos or Vector3.New(0,0,0)
			if tVertex.vOffset then vPoint = vPoint + tVertex.vOffset end
			if fRotate then vPoint = fRotate(vPoint) end
			if vOffset then vPoint = vPoint + vOffset end
			if tVertex.wndMark then tVertex.wndMark:SetWorldLocation(vPoint) end
		end
		tVertex.vPoint = vPoint
		tVertex.tScreenPoint = GameLib.WorldLocToScreenPoint(vPoint)
	end
	
	return true
end

function DrawLib:UpdatePixies(tPixies, tVertices, tStyle, bOutline)
	local overlay = self.wndOverlay
	local length = math.max(#tPixies, #tVertices-1)

	local sc = Apollo.GetDisplaySize() -- maybe move this out for performance
	local scdiag = (sc.nWidth^2 + sc.nHeight^2)

	for i=1,length do
		if not tPixies[i] then tPixies[i] = {} end
		local tPixie = tPixies[i]
		local bDestroy = false

		if tVertices[i] and tVertices[i+1] then
			local pA = tVertices[i].tScreenPoint
			local pB = tVertices[i+1].tScreenPoint

			if pA.z < 0 and pB.z < 0 then bDestroy = true -- both points behind camera, nothing to draw
			else
				if pA.z < 0 and pB.z > 0 then pA,pB = pB,pA end -- swap

				if pB.z < 0 and pA.z > 0 then
					-- here, pB is the projection of a point behind the camera, where perspective projection breaks down;
					-- to fix it, instead of drawing a line from pA to pB, we draw a line starting at pA going away from
					-- the reflection of pB wrt to the center of the screen, and stopping somewhere off-screen.
					--
					-- ...don't ask me why it works. I'm no longer exactly sure myself.

					local p = Vector3.New(sc.nWidth-pB.x, sc.nHeight-pB.y, 1)
					-- to ensure we go off-screen, line length should be at least bigger than the length of screen diagonal,
					-- but not too much, otherwise artifacts start to appear if pB is too far out

					-- pB = pA + (pA-p)*100
					pB = pA + (pA-p):NormalFast()*scdiag -- this might be overkill
				end

				local tConfig = tPixie.pixieConfig or {bLine = true, loc = {}}
				tConfig.loc.nOffsets = {pA.x, pA.y, pB.x, pB.y}

				if bOutline then
					tConfig.fWidth = tStyle.nLineWidth + 2
					tConfig.cr = "black"
				else
					tConfig.fWidth = tStyle.nLineWidth
					tConfig.cr = tStyle.crLineColor
				end

				if tPixie.pixie then
					overlay:UpdatePixie(tPixie.pixie, tPixie.pixieConfig)
				else
					tPixie.pixieConfig = tConfig
					tPixie.pixie = overlay:AddPixie(tPixie.pixieConfig)
				end
			end
		else
			bDestroy = true
		end

		if bDestroy and tPixie.pixie then
			overlay:DestroyPixie(tPixie.pixie)
			tPixie.pixie = nil
		end
	end
end

-- Helpers

function DrawLib:CalcCircleVectors(nSides, fOffset)
	local tVectors = {}
	for i=0,nSides do
		local angle = 2*i*math.pi/nSides + (fOffset or 0)
		tVectors[i+1] = Vector3.New(-math.sin(angle), 0, -math.cos(angle))
	end
	return tVectors
end

function DrawLib:Rotate(fAngle)
	local angleCos = math.cos(fAngle)
	local angleSin = math.sin(fAngle)

	return function(vPoint)
		return Vector3.New(
			angleCos*vPoint.x + angleSin*vPoint.z,
			0,
			-angleSin*vPoint.x + angleCos*vPoint.z
		)
	end
end

-- Leftover stuff

function DrawLib:CurvePath(tPath) -- native catmull-rom with 10 segments
	local tCurvedPath = {}
	for i=0,#tPath-2 do
		local vA = (i>0) and tPath[i] or tPath[i+1]
		local vB = tPath[i+1]
		local vC = tPath[i+2]
		local vD = (i<#tPath-2) and tPath[i+3] or tPath[i+2]
		for j=1,10 do tCurvedPath[10*i+j] = Vector3.InterpolateCatmullRom(vA,vB,vC,vD,j/10)	end
	end
	return tCurvedPath
end

function DrawLib:GetSqDistanceToSeg(vP,vA,vB)
	local vC = vA
	if vA ~= vB then 
		local vDir = vB - vA
		local fSqLen = vDir:LengthSq()
		local t = Vector3.Dot(vDir, vP - vA) / fSqLen
		if t > 1 then vC = vB elseif t > 0 then vC = vA + vDir*t end
	end
	return (vP-vC):LengthSq()
end

function DrawLib:SimplifyPath(tPath, fTolerance) -- Ramer-Douglas-Peucker 
	local tSimplePath = {}
	local tMarkers = {[1] = true, [#tPath] = true}
	local index
	
	local tStack = {#tPath, 1}
	
	while #tStack > 0 do
		
		local maxDist = 0
		
		local first = tStack[#tStack]
		tStack[#tStack] = nil
		local last = tStack[#tStack]
		tStack[#tStack] = nil
		
		for i=first+1,last-1 do
			local SqDist = self:GetSqDistanceToSeg(tPath[i],tPath[first],tPath[last])
			if SqDist > maxDist then
				maxDist = SqDist
				index = i
			end
		end
		
		if maxDist > fTolerance then
			tMarkers[index] = true
			tStack[#tStack+1] = last
			tStack[#tStack+1] = index
			tStack[#tStack+1] = index
			tStack[#tStack+1] = first
		end
		
	end
	
	for i=1,#tPath do
		if tMarkers[i] then
			tSimplePath[#tSimplePath+1] = tPath[i]
		end
	end
	
	return tSimplePath
end

Apollo.RegisterAddon(DrawLib)
