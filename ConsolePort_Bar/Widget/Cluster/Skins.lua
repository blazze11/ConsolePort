local _, env = ...;
---------------------------------------------------------------
local Skins = {}; env.LIB.Skin.ClusterBar = Skins;
---------------------------------------------------------------
local Masks = env.Const.Cluster.Masks;
local Swipes = env.Const.Cluster.Swipes;
local Assets = env.Const.Cluster.Assets;
local AdjustTextures = env.Const.Cluster.AdjustTextures;
local GetIconMask = env.LIB.SkinUtility.GetIconMask;
local GetSlotBackground = env.LIB.SkinUtility.GetSlotBackground;
---------------------------------------------------------------

local CLUSTER_DESIGN       = env.Const.ClusterDesign;
local FLYOUT_BORDER_SHAPES = {M1 = 'Side'; M2 = 'Side'; M3 = 'Middle';};
local FULL_TEX_COORDS      = {0; 1; 0; 1;};
local MIDDLE_MASK_INSET    = 1 / 46; -- one pixel per side at the default flyout size

local function getBorderTextures(normal, highlight, main)
	return {
		NormalTexture         = normal;
		Border                = highlight;
		PushedTexture         = normal;
		HighlightTexture      = highlight;
		CheckedTexture        = highlight;
		NewActionTexture      = highlight;
		SpellHighlightTexture = highlight;
		Flash                 = main and highlight or nil;
	};
end

local function getGoldBorderTextures(name, extension, main)
	local normal    = env.GetAsset([[Textures\Cluster\Gold%s.%s]], name, extension);
	local highlight = env.GetAsset([[Textures\Cluster\Gold%sHighlight.%s]], name, extension);
	return getBorderTextures(normal, highlight, main);
end

local goldMainTextures = getGoldBorderTextures('Main', 'tga', true);

local beveledFlyouts = {};
for _, shape in ipairs({'Side'; 'Middle';}) do
	local path = env.GetAsset([[Textures\Cluster\Beveled%s]], shape);
	beveledFlyouts[shape] = getBorderTextures(path .. '.png', path .. 'Highlight.png');
end

local function getProcFlipBook(asset)
	local path = env.GetAsset([[Textures\Cluster\Glow\Flipbooks\%s]], asset);
	return {Start = path .. 'Start.png'; Loop = path .. 'Loop.png';};
end

local roundProcGlow = getProcFlipBook('Round');

local function getShapeSkins(asset)
	local slots = {Shadow = env.GetAsset([[Textures\Cluster\Shapes\%sShadow.tga]], asset);};
	for _, slot in ipairs({'Main'; 'Flyout';}) do
		local path   = env.GetAsset([[Textures\Cluster\Shapes\%s%s]], asset, slot);
		local isMain = slot == 'Main';
		slots[slot] = {
			Border   = getBorderTextures(path .. '.tga', path .. 'Highlight.tga', isMain);
			Mask     = path .. 'Mask.tga';
			Swipe    = path .. 'Swipe.tga';
			ProcGlow = isMain and getProcFlipBook(asset) or env.GetAsset([[Textures\Cluster\Glow\%sFlyout.tga]], asset);
		};
	end
	return slots;
end

local shapeSkins = {};
for _, shape in pairs(env.Const.Cluster.GoldShapes) do
	local slots = getShapeSkins(shape.Asset);
	if shape.HorizontalAsset then
		slots.Horizontal = getShapeSkins(shape.HorizontalAsset);
	end
	shapeSkins[shape] = slots;
end

local function SetRotatedMaskTexture(self, mask, prefix, direction)
	local maskTexture = Masks[prefix][direction];
	-- The wedge masks have opaque pixels at the texture edges.
	mask:SetTexture(maskTexture, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
	self.Flash:SetTexture(maskTexture)
end

local function setCooldownBounds(cooldown, bounds)
	cooldown:ClearAllPoints()
	cooldown:SetAllPoints(bounds)
end

---------------------------------------------------------------
-- The native edge ignores the swipe texture's alpha.
---------------------------------------------------------------
local FULL_ROTATION = 2 * math.pi;
local EDGE_SCALE    = math.sqrt(2); -- reach the corners before masking
local edgeAngle     = C_CurveUtil and C_CurveUtil.CreateCurve and C_CurveUtil.CreateCurve();
if edgeAngle then
	edgeAngle:AddPoint(0, 0)
	edgeAngle:AddPoint(1, -FULL_ROTATION)
end

local function clearEdgeDuration(cooldown)
	cooldown.clusterEdgeDuration = nil;
end

local function hideMaskedEdge(cooldown)
	if not cooldown.clusterEdgeShown then return end;
	cooldown.clusterEdgeShown = nil;
	cooldown.clusterEdge:Hide()
end

local function updateMaskedEdge(cooldown)
	local edge, duration = cooldown.clusterEdge, cooldown.clusterEdgeDuration;
	-- Retail duration objects can drive the rotation without reading secret times.
	if duration then
		edge:SetRotation(duration:EvaluateElapsedPercent(edgeAngle))
	else
		local start, total = cooldown:GetCooldownTimes();
		if ( CPAPI.IsSecret(start) or CPAPI.IsSecret(total) or not start or not total or total <= 0 ) then
			return hideMaskedEdge(cooldown);
		end
		local progress = math.max(0, math.min(1, (GetTime() * 1000 - start) / total));
		edge:SetRotation(-FULL_ROTATION * progress)
	end
	if not cooldown.clusterEdgeShown then
		cooldown.clusterEdgeShown = true;
		edge:Show()
	end
end

local function setMaskedEdge(cooldown, button)
	local edge = cooldown.clusterEdge;
	local icon = button.icon;
	if not edge then
		if button.layoutData.Prefix then
			-- Draw the sweep between the icon and the button's border art.
			edge = button:CreateTexture(nil, 'BORDER', nil, -1);
		else
			edge = cooldown:CreateTexture(nil, 'OVERLAY');
		end
		edge:SetPoint('CENTER', icon, 'CENTER')
		edge:SetTexture(Assets.CooldownEdge)
		edge:SetBlendMode('ADD')
		edge:AddMaskTexture(GetIconMask(button))
		edge:Hide()
		cooldown.clusterEdge = edge;
		cooldown:HookScript('OnHide', hideMaskedEdge)
		cooldown:HookScript('OnUpdate', updateMaskedEdge)
		if ( edgeAngle and cooldown.SetCooldownFromDurationObject ) then
			hooksecurefunc(cooldown, 'SetCooldownFromDurationObject', function(frame, duration)
				frame.clusterEdgeDuration = duration;
			end)
			hooksecurefunc(cooldown, 'SetCooldown', clearEdgeDuration)
			hooksecurefunc(cooldown, 'Clear', clearEdgeDuration)
		end
	end
	edge:SetSize(icon:GetWidth() * EDGE_SCALE, icon:GetHeight() * EDGE_SCALE)
	if cooldown:IsShown() then
		updateMaskedEdge(cooldown)
	end
end

local function setCooldownSwipe(self, swipe, bounds)
	local cooldown = self.cooldown;
	if swipe then
		setCooldownBounds(cooldown, bounds)
		cooldown:SetSwipeTexture(swipe)
		cooldown:SetUseCircularEdge(false)
	end
	-- LibActionButton can change the draw flags and tint before setting a timer.
	cooldown:SetDrawEdge(false)
	if self.swipeColor then
		cooldown:SetSwipeColor(self.swipeColor:GetRGBA())
	end

	if self.layoutData.Prefix then
		return cooldown:SetDrawBling(false, true);
	end
	cooldown:SetDrawBling(false)
end

local textureSnapping = {}; -- restore the original sampling when switching back

local function setTextureSnapping(texture, smoothSampling)
	local snapping = textureSnapping[texture];
	if smoothSampling then
		if not ( texture.GetTexelSnappingBias and texture.IsSnappingToPixelGrid ) then return end;
		textureSnapping[texture] = snapping or {
			bias = texture:GetTexelSnappingBias();
			snap = texture:IsSnappingToPixelGrid();
		};
		texture:SetTexelSnappingBias(0)
		texture:SetSnapToPixelGrid(false)
	elseif snapping then
		texture:SetTexelSnappingBias(snapping.bias)
		texture:SetSnapToPixelGrid(snapping.snap)
		textureSnapping[texture] = nil;
	end
end

local function SetTextures(self, adjustTextures, coords, texSize, smoothSampling)
	for key, file in pairs(adjustTextures) do
		local texture = self[key];
		if texture then
			if coords then
				texture:SetTexCoord(unpack(coords))
			end
			texture:SetTexture(file)
			setTextureSnapping(texture, smoothSampling)
			texture:ClearAllPoints()
			if texSize then
				texture:SetPoint('CENTER', 0, 0)
				texture:SetSize(texSize, texSize)
			else
				texture:SetAllPoints(self.icon)
			end
		else
			print('Texture not found:', key)
		end
	end

	self.HighlightTexture:SetBlendMode('ADD')
	self.PushedTexture:SetBlendMode(env('clusterDesign') == CLUSTER_DESIGN.Original and 'ADD' or 'BLEND')
	self.CheckedTexture:SetBlendMode('ADD')
	self.PushedTexture:SetDrawLayer('OVERLAY', 2)
	self.CheckedTexture:SetDrawLayer('OVERLAY', 1)
	if self.borderColor then
		self:SetBorderColor(self.borderColor)
	end
	if self.BorderShadow then
		self.BorderShadow:SetTexture(nil)
	end
end

local function raiseButtonName(button)
	-- Put macro text above the hover border, using the native text frame when available.
	local overlay = button.TextOverlayContainer or button.clusterTextOverlay;
	if not overlay then
		overlay = CreateFrame('Frame', nil, button);
		overlay:SetAllPoints(button)
		overlay:SetFrameLevel(button:GetFrameLevel() + 1)
		button.clusterTextOverlay = overlay;
	end
	button.Name:SetParent(overlay)
end

local function SetBackground(self, mask, goldBorders, insetMask)
	local bg = GetSlotBackground(self)
	bg:SetDrawLayer('BACKGROUND', -8)
	bg:SetAllPoints(self.icon)
	bg:SetTexture(Assets.EmptyIcon)
	bg:AddMaskTexture(mask)
	bg:SetDesaturated(true)
	if goldBorders then
		bg:SetVertexColor(env.Const.Cluster.GoldEmptySlotColor:GetRGBA())
	else
		bg:SetVertexColor(0.5, 0.5, 0.5, 1)
	end
	mask:ClearAllPoints()
	if insetMask then
		local x = self.icon:GetWidth() * MIDDLE_MASK_INSET;
		local y = self.icon:GetHeight() * MIDDLE_MASK_INSET;
		mask:SetPoint('TOPLEFT', self.icon, 'TOPLEFT', x, -y)
		mask:SetPoint('BOTTOMRIGHT', self.icon, 'BOTTOMRIGHT', -x, y)
	else
		mask:SetAllPoints(self.icon)
	end
end

local function skinChargeCooldown(cooldown, button)
	setCooldownBounds(cooldown, button.icon)
	cooldown:SetUseCircularEdge(false)
	cooldown:SetDrawEdge(false)
	-- Classic can re-enable drawing whenever it updates the charge timer.
	cooldown:SetEdgeTexture(Assets.CooldownEdge, 1, 1, 1, 0)
	if ( not cooldown.clusterEdge and edgeAngle and cooldown.SetCooldownFromDurationObject ) then
		cooldown:HookScript('OnCooldownDone', clearEdgeDuration)
	end
	setMaskedEdge(cooldown, button)
end

---------------------------------------------------------------
-- Skins by modifier slot
---------------------------------------------------------------
for mod, data in pairs(env.Const.Cluster.Layout) do
	local prefix          = data.Prefix;
	local coords          = data.Coords;
	local offset          = data.TexSize or 1;
	local adjust          = AdjustTextures[mod];
	local beveledTextures = beveledFlyouts[FLYOUT_BORDER_SHAPES[prefix]];
	local goldByDirection = {};
	local procGlow        = prefix and env.GetAsset([[Textures\Cluster\Glow\%s.tga]], prefix == 'M3' and 'M3' or 'M1')
		or roundProcGlow;
	if prefix then
		for direction in pairs(env.Const.Cluster.Directions) do
			goldByDirection[direction] = getGoldBorderTextures(('%s_%s'):format(prefix, direction), 'png');
		end
	end

	Skins[mod] = function(self, force)
		local direction = self.direction;
		local slots     = force and shapeSkins[self.clusterShape];
		-- Turn the hex so the side flyouts meet a flat edge of the main button.
		if ( slots and slots.Horizontal and (self.clusterDirection == 'LEFT' or self.clusterDirection == 'RIGHT') ) then
			slots = slots.Horizontal;
		end
		local shape = slots and (prefix and slots.Flyout or slots.Main);
		local swipe = force and (shape and shape.Swipe or direction and Swipes[prefix][direction] or Assets.MainSwipe);
		-- The Round Silver middle wedge's mask extends past its smaller rim.
		local insetMask = force and prefix == 'M3' and env('clusterDesign') == CLUSTER_DESIGN.Original;
		local mask = force and GetIconMask(self);
		local swipeBounds = insetMask and mask or self.icon;
		setCooldownSwipe(self, swipe, swipeBounds)
		local charge = self.chargeCooldown;
		if ( charge and (force or not charge.clusterEdge) ) then
			skinChargeCooldown(charge, self)
		end

		if not force then return end;
		if self.lossOfControlCooldown then
			local cooldown = self.lossOfControlCooldown;
			setCooldownBounds(cooldown, swipeBounds)
			cooldown:SetSwipeTexture(swipe)
			cooldown:SetDrawEdge(false)
		end
		if ( data.Shadow and self.Shadow ) then
			self.Shadow:SetShapeTexture(slots and slots.Shadow)
		end
		local size        = self:GetSize();
		local tcoords     = coords or direction and data[direction].Coords;
		local goldBorders = env:IsGoldClusterDesign();
		if direction then
			self.icon:SetDrawLayer('BACKGROUND')
			self.NormalTexture:SetDrawLayer('OVERLAY')
		end
		raiseButtonName(self)
		if shape then
			SetTextures(self, shape.Border, FULL_TEX_COORDS, nil, true)
			mask:SetTexture(shape.Mask)
			if direction then
				self.Flash:SetTexture(shape.Mask)
			end
		else
			local beveled  = beveledTextures and env('clusterDesign') == CLUSTER_DESIGN.Beveled;
			local gold     = not prefix and goldMainTextures or goldByDirection[direction or 'DOWN'];
			local textures = goldBorders and gold
				or beveled and beveledTextures or adjust or env:GetClusterBorderStyle();
			SetTextures(self, textures, tcoords, size * offset, goldBorders or beveled)
			if direction then
				SetRotatedMaskTexture(self, mask, prefix, direction)
			elseif not prefix then
				mask:SetTexture(Assets.MainMask)
			end
		end
		SetBackground(self, mask, goldBorders, insetMask)
		setMaskedEdge(self.cooldown, self)
		self:SetProcGlowTexture(shape and shape.ProcGlow or procGlow)
		self.Name:SetWidth(size)
	end;
end
