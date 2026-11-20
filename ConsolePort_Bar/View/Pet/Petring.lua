local env, db = CPAPI.GetEnv(...)
local FadeIn, FadeOut = db.Alpha.FadeIn, db.Alpha.FadeOut;
---------------------------------------------------------------
local PET_STATUS_TEXTURE      = env.GetAsset[[Textures\PetRing\StatusFill.png]];
local TEXTURED_RIM_BRIGHTNESS = 0.86;
local STATUS_UPDATE_INTERVAL  = 0.1;

local function getPetRingTextures(style)
	local path = env.GetAsset([[Textures\PetRing\%s]], style);
	return {
		Portrait = path .. 'Portrait.png';
		Wheel    = path .. 'Wheel.png';
		Status   = path .. 'Status.png';
		Slot     = path .. 'Slot.png';
	};
end

local PET_RING_TEXTURES = {
	Original = getPetRingTextures('RoundSilver');
	Beveled  = getPetRingTextures('BeveledSilver');
	Gold     = getPetRingTextures('Gold');
};
---------------------------------------------------------------
CPPetRingButton = Mixin({
---------------------------------------------------------------
	ActiveIconVertex   = CreateColor(1.0, 1.0, 1.0);
	InactiveIconVertex = CreateColor(0.4, 0.4, 0.4);
	CornerVertexOffset = {
		[UPPER_LEFT_VERTEX]  = {-10; -4;};
		[UPPER_RIGHT_VERTEX] = { 10; -4;};
		[LOWER_LEFT_VERTEX]  = {  0; -4;};
		[LOWER_RIGHT_VERTEX] = {  0; -4;};
	};
}, CPActionButtonMixin);
---------------------------------------------------------------

local function onCooldownDone(self)
	local button = self:GetParent()
	button.onCooldown = nil;
	button:SetChecked(false)
	if not button:GetParent():IsOpaque() then
		FadeOut(button, 0.1, button:GetAlpha(), 0)
	end
end

function CPPetRingButton:Init(i)
	local x, y, r = 0, 0, 68; -- index, xOffset, yOffset, radius
	local angle = ( i - 4 ) * rad( 360 / (NUM_PET_ACTION_SLOTS) );

	self.textureRotation = rad(270) - angle;
	self:SetAttribute('action', i)
	self:SetPoint('CENTER', x + r * math.cos(angle), -(y + r * math.sin(angle)))

	local name = self:GetName()
	self.cooldown       = self.cooldown or _G[name..'Cooldown'];
	self.AutoCastable   = self.AutoCastable or _G[name..'AutoCastable']
	self.Shine          = self.Shine or _G[name..'Shine']
	self.NormalTexture  = self.NormalTexture or _G[name..'NormalTexture']
	self.NormalTexture2 = _G[name..'NormalTexture2'] or self.NormalTexture

	if self.SlotBackground then
		self.SlotBackground:SetTexture(nil)
		self.SlotBackground:ClearAllPoints()
		self.SlotBackground:Hide()
	end

	self.Flash:SetMask('Interface\\Minimap\\UI-Minimap-Background')
	self.Flash:SetAlpha(0.25)

	self.HotKey:SetAlpha(0)

	if self.IconMask then
		self.icon:RemoveMaskTexture(self.IconMask)
	end
	self.icon:AddMaskTexture(self:GetParent().Ring.Mask)
	self.icon:SetRotation(self.textureRotation)
	self.icon:SetAllPoints()

	if self.AutoCastable then
		self.AutoCastable:SetRotation(self.textureRotation)
		self.AutoCastable:Hide()
	elseif self.AutoCastOverlay then
		if self.AutoCastOverlay.Shine then
			self.AutoCastOverlay.Shine:SetRotation(self.textureRotation)
		end
		self.AutoCastOverlay.Corners:SetRotation(self.textureRotation)
		for vertexIndex, offset in pairs(self.CornerVertexOffset) do
			self.AutoCastOverlay.Corners:SetVertexOffset(vertexIndex, unpack(offset))
		end
	end

	self.NormalTexture:SetTexture(nil)
	self.NormalTexture:ClearAllPoints()
	self.NormalTexture:SetPoint('CENTER', 0, 0)

	self.NormalTexture2:SetTexture(nil)
	self.NormalTexture2:ClearAllPoints()
	self.NormalTexture2:SetPoint('CENTER', 0, 0)

	self.PushedTexture    = self:GetPushedTexture()
	self.HighlightTexture = self:GetHighlightTexture()
	self.CheckedTexture   = self:GetCheckedTexture()

	self.PushedTexture:SetPoint('TOPLEFT', -6, 6)
	self.PushedTexture:SetPoint('BOTTOMRIGHT', 6, -6)
	self.PushedTexture:SetRotation(self.textureRotation)
	self.PushedTexture:SetBlendMode('BLEND')

	self.HighlightTexture:SetPoint('TOPLEFT', -6, 6)
	self.HighlightTexture:SetPoint('BOTTOMRIGHT', 6, -6)
	self.HighlightTexture:SetRotation(self.textureRotation)
	self.HighlightTexture:SetBlendMode('ADD')

	self.CheckedTexture:SetPoint('TOPLEFT', -6, 6)
	self.CheckedTexture:SetPoint('BOTTOMRIGHT', 6, -6)
	self.CheckedTexture:SetRotation(self.textureRotation)
	self.CheckedTexture:SetBlendMode('ADD')

	self.cooldown:SetDrawSwipe(false)
	self.cooldown:SetDrawBling(false)
	self.cooldown:SetHideCountdownNumbers(false)
	self.cooldown:SetScript('OnCooldownDone', onCooldownDone)
end

function CPPetRingButton:UpdateEmptySlotColor(goldBorders)
	if self.hasPetAction then return end;
	local color = goldBorders and env.Const.Cluster.GoldEmptySlotColor or self.ActiveIconVertex;
	self.icon:SetVertexColor(color:GetRGBA())
end

function CPPetRingButton:OnEnter()
	self:GetParent():UpdateFade()
	if not self.tooltipName then return end;
	local uber = GetCVarBool('UberTooltips')
	if not uber then
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		local bindingText = GetBindingText(GetBindingKey('BONUSACTIONBUTTON'..self:GetID()))
		if ( bindingText and bindingText ~= '' ) then
			GameTooltip:SetText(self.tooltipName..NORMAL_FONT_COLOR_CODE..' ('..bindingText..')'..FONT_COLOR_CODE_CLOSE, 1.0, 1.0, 1.0)
		else
			GameTooltip:SetText(self.tooltipName, 1.0, 1.0, 1.0)
		end
		GameTooltip:Show()
		self.UpdateTooltip = nil;
	else
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		if ( GameTooltip:SetPetAction(self:GetID()) ) then
			self.UpdateTooltip = self.OnEnter;
		else
			self.UpdateTooltip = nil;
		end
	end
end

function CPPetRingButton:OnLeave()
	self:GetParent():UpdateFade()
end

function CPPetRingButton:StartFlash()
	self.flashing  = true;
	self.flashtime = 0;
end

function CPPetRingButton:StopFlash()
	self.flashing = false;
	self.Flash:Hide()
end

function CPPetRingButton:OnSizeChanged(width, height)
	local normalX, normalY = width * (46/32), height * (46/32);
	self.PushedTexture:SetSize(normalX, normalY)
	self.NormalTexture:SetSize(normalX, normalY)
	self.NormalTexture2:SetSize(normalX, normalY)
end

function CPPetRingButton:Update()
	local i = self:GetID()
	local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled = GetPetActionInfo(i)
	self.hasPetAction = not not texture;
	if ( not isToken ) then
		self:SetIcon(texture)
		self.tooltipName = name;
	else
		self:SetIcon(_G[texture])
		self.tooltipName = _G[name];
	end
	if ( isActive ) then
		if ( IsPetAttackAction(i) ) then
			self:StartFlash()
			-- the checked texture looks a little confusing at full alpha (looks like you have an extra ability selected)
			self:GetCheckedTexture():SetAlpha(0.5)
		else
			self:StopFlash()
			self:GetCheckedTexture():SetAlpha(1.0)
		end
		self:SetChecked(true)
	else
		self:StopFlash()
		self:SetChecked(false)
	end
	if ( autoCastEnabled ) then
		CPAPI.AutoCastStart(self, autoCastAllowed, CPAPI.GetClassColor())
	else
		CPAPI.AutoCastStop(self, autoCastAllowed)
	end
	if ( texture ) then
		local color = GetPetActionSlotUsable(i) and self.ActiveIconVertex or self.InactiveIconVertex;
		self.icon:SetVertexColor(color:GetRGBA())
	else
		self:UpdateEmptySlotColor(env:IsGoldClusterDesign())
	end
	self:UpdateCooldown()
end

function CPPetRingButton:UpdateCooldown(time) time = time or GetTime();
	local start, duration, enable = GetPetActionCooldown(self:GetID())
	CooldownFrame_Set(self.cooldown, start, duration, enable)
	if (time < start + duration) then
		self.onCooldown = true;
		self:SetChecked(true)
		FadeIn(self, 0.1, self:GetAlpha(), 1)
	end
	if GameTooltip:IsOwned(self) then
		self:OnEnter()
	end
end

---------------------------------------------------------------
CPPetRingPower = {};
---------------------------------------------------------------
local SQRT2 = 2 ^ 0.5;
local PI    = math.pi;
local HALF  = PI / 2;

function CPPetRingPower:SetFillTexture(texture)
	self.Fill:SetTexture(texture)
	local width, height = self:GetSize()
	local maskSize = math.max(width, height) * SQRT2;
	self.HalfMask:SetSize(maskSize, maskSize)
	self.FillMask:SetSize(maskSize, maskSize)
end

function CPPetRingPower:SetHalfRotation(rotation)
	self.HalfMask:SetRotation(rotation)
end

function CPPetRingPower:SetFillColor(r, g, b, a)
	self.Fill:SetVertexColor(r, g, b, a or 1)
end

function CPPetRingPower:SetValue(rotation)
	self.FillMask:SetRotation(rotation)
end

---------------------------------------------------------------
CPPetRing = Mixin({
---------------------------------------------------------------
	OnEvent = CPAPI.EventMixin.OnEvent;
	Events  = {
		'PET_BAR_UPDATE_COOLDOWN';
		'PET_BAR_UPDATE';
		'PET_SPECIALIZATION_CHANGED';
		'PLAYER_CONTROL_GAINED';
		'PLAYER_CONTROL_LOST';
		'PLAYER_FARSIGHT_FOCUS_CHANGED';
	};
	PetEvents = {
		'UNIT_AURA';
		'UNIT_FLAGS';
		'UNIT_PORTRAIT_UPDATE';
	};
	PlayerEvents = {
		'UNIT_PET';
	};
}, env.ConfigurableWidgetMixin);

function CPPetRing:OnLoad()
	CPAPI.RegisterFrameForEvents(self, self.Events)
	CPAPI.RegisterFrameForUnitEvents(self, self.PetEvents, 'pet')
	CPAPI.RegisterFrameForUnitEvents(self, self.PlayerEvents, 'player')

	for i, button in ipairs(self.Buttons) do
		button:Init(i)
	end

	self.Power:SetFillTexture(PET_STATUS_TEXTURE)
	self.Health:SetFillTexture(PET_STATUS_TEXTURE)

	self.Health:SetHalfRotation(HALF)
	self.Power:SetHalfRotation(-HALF)

	self:UpdatePowerType()
	self.Health:SetFillColor(0, 1, 0, 1)

	env:RegisterCallback('OnLoadoutConfigShown', self.OnLoadoutConfigShown, self)
	env:RegisterCallbacks(self.OnVariableChanged, self,
		'Settings/borderColor',
		'Settings/clusterDesign'
	);
end

function CPPetRing:SetProps(props)
	self:SetDynamicProps(props)

	local showStatus = props.status;
	local hri = showStatus and -4 or 0;
	self:SetHitRectInsets(hri, hri, hri, hri)
	self.Power:SetShown(showStatus)
	self.Health:SetShown(showStatus)
	self.Background:SetShown(showStatus)
	self.Center.Separator:SetShown(showStatus)
	self.Center.OuterBorder:SetShown(showStatus)
	self:SetScript('OnUpdate', showStatus and self.OnUpdate or nil)

	db.Layers:RegisterStateDriver(self, 'visibility', env.ConvertDriver(
		(not props.vehicle and '[vehicleui] hide; ' or '') .. props.visibility));

	self:Update()
	self:UpdateCooldowns()
	self:OnVariableChanged()
	self:FadeIn()
	self:FadeOut()
end

function CPPetRing:OnPropsUpdated()
	self:FadeIn()
	self:SetProps(self.props)
end

local function setRimTexture(region, texture, r, g, b, a)
	region:SetTexture(texture)
	region:SetVertexColor(r, g, b, a)
	if region.SetTexelSnappingBias and region.SetSnapToPixelGrid then
		region:SetTexelSnappingBias(0)
		region:SetSnapToPixelGrid(false)
	end
end

function CPPetRing:OnVariableChanged()
	local goldBorders = env:IsGoldClusterDesign();
	local beveled     = env('clusterDesign') == env.Const.ClusterDesign.Beveled;
	local textures    = goldBorders and PET_RING_TEXTURES.Gold or beveled and PET_RING_TEXTURES.Beveled or PET_RING_TEXTURES.Original;
	local r, g, b, a  = env:GetColorRGBA('borderColor');
	local rest = (goldBorders or beveled) and TEXTURED_RIM_BRIGHTNESS or 1;
	local rimR, rimG, rimB = r * rest, g * rest, b * rest;
	setRimTexture(self.Center.InnerBorder, textures.Portrait, rimR, rimG, rimB, a)
	setRimTexture(self.Center.OuterBorder, textures.Status, rimR, rimG, rimB, a)
	setRimTexture(self.Ring.Border, textures.Wheel, rimR, rimG, rimB, a)

	local background = self.Background.Background;
	if goldBorders then
		background:SetVertexColor(env.Const.Cluster.GoldEmptySlotColor:GetRGBA())
	else
		background:SetVertexColor(0.5, 0.5, 0.5, 1)
	end
	for _, button in ipairs(self.Buttons) do
		setRimTexture(button.PushedTexture, textures.Slot, r * 0.60, g * 0.60, b * 0.60, a)
		setRimTexture(button.HighlightTexture, textures.Slot, r, g, b, a * 0.55)
		setRimTexture(button.CheckedTexture, textures.Slot, r, g, b, a * 0.72)
		button:UpdateEmptySlotColor(goldBorders)
	end
end

function CPPetRing:OnShow()
	self:UNIT_PORTRAIT_UPDATE()
	FadeIn(self, 0.2, 0, 1)
end

function CPPetRing:OnEnter()
	UnitFrame_UpdateTooltip(self)
	self:UpdateFade()
end

function CPPetRing:OnLeave()
	self.UpdateTooltip = nil;
	GameTooltip:Hide()
	self:FadeOut()
end

do local UnitExists = UnitExists;
	function CPPetRing:OnUpdate(elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed;
		if self.elapsed < STATUS_UPDATE_INTERVAL then return end;
		self.elapsed = self.elapsed % STATUS_UPDATE_INTERVAL;
		local unit, powerType = self.unit, self.powerType;
		if not UnitExists(unit) then return end;
		self:UpdateHealth(unit)
		if not powerType then return end;
		self:UpdatePower(unit, powerType)
	end
end

if CPAPI.IsModernVersion then
	local UnitHealthPercent, UnitPowerPercent = UnitHealthPercent, UnitPowerPercent;

	local healthCurve = C_CurveUtil.CreateCurve();
	healthCurve:SetType(Enum.LuaCurveType.Linear);
	healthCurve:AddPoint(0.0, PI + HALF);
	healthCurve:AddPoint(1.0, HALF);

	local powerCurve = C_CurveUtil.CreateCurve();
	powerCurve:SetType(Enum.LuaCurveType.Linear);
	powerCurve:AddPoint(0.0, -PI - HALF);
	powerCurve:AddPoint(1.0, -HALF);

	function CPPetRing:UpdateHealth(unit)
		local usePredicted = false;
		local health = UnitHealthPercent(unit, usePredicted, healthCurve)
		self.Health:SetValue(health)
	end

	function CPPetRing:UpdatePower(unit, powerType)
		local unmodified = false;
		local power = UnitPowerPercent(unit, powerType, unmodified, powerCurve)
		self.Power:SetValue(power)
	end
else
	local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax;
	local UnitPower,  UnitPowerMax  = UnitPower, UnitPowerMax;

	function CPPetRing:UpdateHealth(unit)
		local health = UnitHealth(unit) / UnitHealthMax(unit);
		if ( self.health ~= health ) then
			self.health = health;
			self.Health:SetValue(HALF + PI * (1 - health))
		end
	end

	function CPPetRing:UpdatePower(unit, powerType)
		local maxPower = UnitPowerMax(unit, powerType)
		local curPower = UnitPower(unit, powerType);
		local power = maxPower > 0 and curPower / maxPower or 1;
		if ( self.power ~= power ) then
			self.power = power;
			self.Power:SetValue(-HALF - PI * (1 - power))
		end
	end
end

function CPPetRing:OnRelease()
	UnregisterStateDriver(self, 'visibility')
end

---------------------------------------------------------------
-- Events
---------------------------------------------------------------
function CPPetRing:Update()
	for _, button in ipairs(self.Buttons) do
		button:Update()
	end
end

CPPetRing.PET_BAR_UPDATE               = CPPetRing.Update;
CPPetRing.PET_SPECIALIZATION_CHANGED   = CPPetRing.Update;
CPPetRing.PLAYER_CONTROL_GAINED        = CPPetRing.Update;
CPPetRing.PLAYER_CONTROL_LOST          = CPPetRing.Update;
CPPetRing.PLAYER_FARSIGHT_FOCUS_CHANGED = CPPetRing.Update;
CPPetRing.UNIT_AURA                    = CPPetRing.Update;
CPPetRing.UNIT_FLAGS                   = CPPetRing.Update;

function CPPetRing:UpdateCooldowns()
	local time = GetTime()
	for _, button in ipairs(self.Buttons) do
		button:UpdateCooldown(time)
	end
end

function CPPetRing:UpdatePowerType()
	local powerType = UnitPowerType(self.unit)
	if not powerType then return end;

	local powerColor = PowerBarColor[powerType];
	self.powerType = powerType;
	self.Power:SetFillColor(powerColor.r, powerColor.g, powerColor.b, 1)
end

function CPPetRing:UNIT_PORTRAIT_UPDATE()
	SetPortraitTexture(self.Center.Portrait, 'pet')
end

function CPPetRing:PET_BAR_UPDATE_COOLDOWN()
	self:UpdateCooldowns()
end

function CPPetRing:UNIT_PET()
	self:UNIT_PORTRAIT_UPDATE()
	self:Update()
	self:UpdatePowerType()
end

---------------------------------------------------------------
-- Display
---------------------------------------------------------------
function CPPetRing:FadeIn()
	for _, button in ipairs(self.Buttons) do
		FadeIn(button, 0.2, button:GetAlpha(), 1)
	end
	FadeIn(self.Ring, 0.2, self.Ring:GetAlpha(), 1)
	self.isOpaque = true;
end

function CPPetRing:FadeOut()
	if not self.props.fade then return end;
	for _, button in ipairs(self.Buttons) do
		if not button.onCooldown then
			FadeOut(button, 0.2, button:GetAlpha(), 0)
		end
	end
	FadeOut(self.Ring, 0.2, self.Ring:GetAlpha(), 0)
	self.isOpaque = false;
end

function CPPetRing:IsOpaque()
	return self.isOpaque;
end

function CPPetRing:UpdateFade()
	local isMouseOver = self:IsMouseMotionFocus()
	if isMouseOver then return self:FadeIn() end;
	for _, button in ipairs(self.Buttons) do
		if button:IsMouseMotionFocus() then
			return self:FadeIn()
		end
	end
	self:FadeOut()
end

function CPPetRing:OnLoadoutConfigShown(show)
	if show then
		self:FadeIn()
	else
		self:FadeOut()
	end
end

---------------------------------------------------------------
-- Factory
---------------------------------------------------------------
env:AddFactory('Petring', function(id)
	local name = ConsolePortBarPetRing and env.MakeID('ConsolePortBarPetRing%s', id) or 'ConsolePortBarPetRing';
	return CreateFrame('Button', name, env.Manager, 'CPPetRing')
end, env.Interface.Petring)
