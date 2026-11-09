local env, db = CPAPI.GetEnv(...)
---------------------------------------------------------------
local NOMOD, _, _, _, ALT = env.Const.Cluster.ModNames();
local CLUSTER_BAR, CLUSTER_HANDLE, CLUSTER_BUTTON, CLUSTER_SHADOW = env.Const.Cluster.Types();
local ClusterLayout = env.Const.Cluster.Layout;
local GOLD_SHAPES   = env.Const.Cluster.GoldShapes;
-- Outward axis and the side occupied by Shift in the original cluster.
local FLYOUT_AXES = {
	UP    = { 0;  1; -1;};
	RIGHT = { 1;  0;  1;};
	DOWN  = { 0; -1;  1;};
	LEFT  = {-1;  0;  1;};
};
---------------------------------------------------------------
local Cluster = CreateFromMixins(env.DynamicWidgetMixin, env.MovableWidgetMixin);
---------------------------------------------------------------

function Cluster:OnLoad(buttonID, parent)
	self.buttonID = buttonID;
	self.header   = parent;
	-- Keep the saved position and mover on the configured footprint.
	self.anchor = CreateFrame('Frame', nil, parent);
	self.anchor:SetFrameLevel(self:GetMainButton():GetFrameLevel())
	self:OnVariableChanged()
	env:RegisterCallbacks(self.OnVariableChanged, self,
		'Settings/swipeColor',
		'Settings/borderColor',
		'Settings/disableDND'
	);
end

function Cluster:OnVariableChanged()
	self:SetSwipeColor(env:GetColor('swipeColor'))
	self:SetBorderColor(env:GetColor('borderColor'))
	for _, button in self:Enumerate() do
		button:DisableDragNDrop(env('disableDND'))
	end
end

function Cluster:Enumerate()
	return pairs(self.buttons)
end

function Cluster:Show()
	self.anchor:Show()
	for _, button in self:Enumerate() do
		button:ToggleShown(true)
	end
end

function Cluster:Hide()
	self.anchor:Hide()
	for _, button in self:Enumerate() do
		button:ToggleShown(false)
	end
end

function Cluster:SetPoint(...)
	local p, _, _, x, y = ...;
	self.anchor:ClearAllPoints()
	if p and x and y then
		-- Preset changes clear anchors on cached buttons as well as the handle.
		local main = self:GetMainButton();
		main:ClearAllPoints()
		main:SetPoint('CENTER', self.anchor, 'CENTER')
		return self.anchor:SetPoint(...)
	end
end

function Cluster:ClearAllPoints()
	self.anchor:ClearAllPoints()
end

function Cluster:SetSize(size)
	local main     = self:GetMainButton();
	local shape    = GOLD_SHAPES[env('clusterDesign')];
	local mainSize = size * (shape and shape.MainSize or 1);
	self.anchor:SetSize(size, size)
	if ( main.Hotkey1 and (shape or main.clusterShape) ) then
		main.Hotkey1:ClearAllPoints()
		if shape then
			main.Hotkey1:SetPoint('CENTER', 0, mainSize * 0.30)
		else
			main.Hotkey1:SetPoint(unpack(main.layoutData.Hotkey[1][3]))
		end
	end
	for _, button in self:Enumerate() do
		local layoutData        = button.layoutData;
		local objSize           = layoutData.Size and size * layoutData.Size or mainSize;
		local relativePointData = layoutData[button.direction];
		local axes              = shape and FLYOUT_AXES[button.direction];
		button.clusterShape = shape;
		if axes then
			-- Convert outward and sideways offsets to the cluster's screen direction.
			local x, y, shiftSide = unpack(axes);
			local prefix          = layoutData.Prefix;
			local isMiddle        = prefix == 'M3';
			local outward         = isMiddle and shape.Middle or shape.Outward;
			local side            = isMiddle and 0 or shape.Side * (prefix == 'M1' and shiftSide or -shiftSide);
			button:ClearAllPoints()
			button:SetPoint('CENTER', main, 'CENTER', size * (x * outward + y * side), size * (y * outward - x * side))
			objSize = size * shape.Size;
		elseif relativePointData then
			local p, rel, x, y = unpack(relativePointData);
			local offset = layoutData.Offset or 1;
			button:ClearAllPoints()
			button:SetPoint(p, main, rel, x * offset, y * offset)
		end
		button:SetSize(objSize, objSize)
		button:UpdateLocal(true)
	end
end

function Cluster:SetSwipeColor(color)
	for _, button in self:Enumerate() do
		button.cooldown:SetSwipeColor(color:GetRGBA())
		button.swipeColor = color;
	end
end

function Cluster:SetBorderColor(color)
	for _, button in self:Enumerate() do
		button:SetBorderColor(color)
	end
end

function Cluster:GetParent()
	return self.header;
end

function Cluster:GetMainButton()
	return self.buttons[NOMOD];
end

function Cluster:SetParent(parent)
	self.header = parent;
	self.anchor:SetParent(parent)
	for _, button in self:Enumerate() do
		button:NewHeader(parent) -- TODO: do we need to unwrap the LAB button scripts?
	end
end

function Cluster:SetDirection(direction)
	for modifier, button in self:Enumerate() do
		button.clusterDirection = direction;
		if modifier == NOMOD then
			button:SetAttribute('flyoutDirection', 'DOWN')
		else
			button:SetAttribute('flyoutDirection', direction)
			button.direction = direction;
		end
	end
end

function Cluster:SetProps(props)
	self:SetDynamicProps(props)
	self:OnPropsUpdated()
end

function Cluster:ToggleFlyouts(enabled)
	local main = self:GetMainButton()
	for _, button in self:Enumerate() do
		if ( button ~= main ) then
			button:OnEnabledChanged(enabled)
		end
	end
end

function Cluster:OnPropsUpdated()
	local props = self.props;
	local pos = props.pos;
	self:Show()
	self:SetPoint(pos.point, self:GetParent(), pos.relPoint, pos.x, pos.y)
	self:SetDirection(props.dir)
	self:SetSize(props.size) -- TODO: flyout size is not consistent
	self:ToggleFlyouts(not not props.showFlyouts)

	local bindings = env.Manager:GetBindings(self.buttonID);
	if bindings then
		self:SetBindings(bindings)
	end
end

function Cluster:SetBindings(bindings)
	for modifier, button in self:Enumerate() do
		button:SetBindings(bindings[modifier], bindings)
	end
end

function Cluster:GetMoveTarget()
	return self.anchor;
end

Cluster.GetSnapSize   = CPAPI.Static(env.Const.Cluster.SnapPixels);

---------------------------------------------------------------
local Shadow = {};
local SHAPED_SHADOW_Y_OFFSET = 3;
---------------------------------------------------------------

function Shadow:OnLoad(owner, relativeSize, alpha, texture, point)
	local update = GenerateClosure(self.Update, self)
	self.owner        = owner;
	self.point        = point;
	self.relativeSize = relativeSize;
	self.baseTexture  = texture;
	self:SetAlpha(alpha)
	self:SetTexture(texture)
	owner:HookScript('OnShow', update)
	owner:HookScript('OnHide', update)
	owner:HookScript('OnSizeChanged', update)
end

function Shadow:SetShapeTexture(texture)
	if ( self.shapeTexture == texture ) then return end;
	self.shapeTexture = texture;
	self:SetTexture(texture or self.baseTexture)
	self:Update()
end

function Shadow:Update()
	local size = self.owner:GetSize() * self.relativeSize;
	local pt, x, y = unpack(self.point)
	self:SetShown(self.owner:IsShown())
	self:SetParent(self.owner:GetParent())
	self:SetSize(size, size)
	self:SetPoint(pt, self.owner, pt, x, y + (self.shapeTexture and SHAPED_SHADOW_Y_OFFSET or 0))
end

---------------------------------------------------------------
local FlyoutCooldown = CreateFromMixins(env.ProxyCooldown);
---------------------------------------------------------------

function FlyoutCooldown:OnLoad()
	env.ProxyCooldown.OnLoad(self)
	self.text = self:GetRegions()
	-- Flyout cluster buttons should have smaller CD font
	local file, height, flags = self.text:GetFont()
	self.text:SetFont(file, height * 0.75, flags)
	self:HookScript('OnShow', self.UpdateModifierIcons)
	self:HookScript('OnHide', self.UpdateModifierIcons)
	hooksecurefunc(self, 'SetHideCountdownNumbers', self.UpdateModifierIcons)
end

function FlyoutCooldown:UpdateModifierIcons()
	-- The modifier glyphs share space with the cooldown number.
	local button = self:GetParent();
	local showCountdown;
	if self.GetHideCountdownNumbers then
		showCountdown = not self:GetHideCountdownNumbers();
	else
		showCountdown = GetCVarBool('countdownForCooldowns');
	end
	button:ToggleHotkeys(button.showFlyoutIcons and not (self:IsShown() and showCountdown))
end

function FlyoutCooldown:SetDrawBling(enabled, force)
	if force then return CPAPI.Index(self).SetDrawBling(self, enabled) end
end


---------------------------------------------------------------
local FlyoutArrow = {};
---------------------------------------------------------------

do -- Flyout arrow owner check, report to parent
	local function CheckSpellFlyoutOwnership(self)
		local native, custom = SpellFlyout, env.LAB:GetSpellFlyoutFrame();
		return (native and native:IsShown() and native:GetParent() == self)
			or (custom and custom:IsShown() and custom:GetParent() == self)
	end

	function FlyoutArrow:Show()
		local parent = self:GetParent()
		parent:OnSpellFlyout(CheckSpellFlyoutOwnership(parent))
		return CPAPI.Index(self).Show(self)
	end

	function FlyoutArrow:Hide()
		self:GetParent():OnSpellFlyout(false)
		return CPAPI.Index(self).Hide(self)
	end
end

---------------------------------------------------------------
local FlyoutButton = { FadeIn = db.Alpha.FadeIn, FadeOut = db.Alpha.FadeOut, alpha = 0, shown = 0};
---------------------------------------------------------------
do  -- Alpha update closures
	FlyoutButton.AlphaState = CPAPI.CreateFlagClosures({
		AlwaysShow    = 0x01;
		OnCooldown    = 0x02;
		OverlayActive = 0x04;
		MouseOver     = 0x08;
		ShowGrid      = 0x10;
		Flyout        = 0x20;
		ConfigShown   = 0x40;
		LockHighlight = 0x80;
	});

	FlyoutButton.AlphaEvents = {
		ACTIONBAR_SHOWGRID = { FlyoutButton.AlphaState.ShowGrid, true  };
		ACTIONBAR_HIDEGRID = { FlyoutButton.AlphaState.ShowGrid, false };
	};

	FlyoutButton.VisibilityState = CPAPI.CreateFlagClosures({
		NoBinding     = 0x01;
		Disabled	  = 0x02;
	});
end

function FlyoutButton:OnShowAll(showAll)
	self:UpdateAlpha(self.AlphaState.AlwaysShow, showAll)
end

function FlyoutButton:OnOverlayGlow(state)
	self:UpdateAlpha(self.AlphaState.OverlayActive, state)
end

function FlyoutButton:OnMouseMotionFocus()
	self:UpdateAlpha(self.AlphaState.MouseOver, true)
	self:SetIgnoreParentAlpha(true)
end

function FlyoutButton:OnMouseMotionClear()
	self:UpdateAlpha(self.AlphaState.MouseOver, false)
	self:SetIgnoreParentAlpha(false)
end

function FlyoutButton:OnSpellFlyout(enabled)
	self:UpdateAlpha(self.AlphaState.Flyout, enabled)
end

function FlyoutButton:OnConfigShown(shown)
	self:UpdateAlpha(self.AlphaState.ConfigShown, shown)
end

function FlyoutButton:LockHighlight()
	self:UpdateAlpha(self.AlphaState.LockHighlight, true)
	CPAPI.Index(self).LockHighlight(self)
end

function FlyoutButton:UnlockHighlight()
	self:UpdateAlpha(self.AlphaState.LockHighlight, false)
	CPAPI.Index(self).UnlockHighlight(self)
end

function FlyoutButton:OnEnabledChanged(enabled)
	self:UpdateVisibility(self.VisibilityState.Disabled, not enabled)
end

function FlyoutButton:OnAlphaEvent(event)
	local eventClosure = self.AlphaEvents[event];
	if eventClosure then
		self:UpdateAlpha(unpack(eventClosure))
	end
end

function FlyoutButton:OnLoad()
	env:RegisterCallback('Settings/clusterShowAll', self.OnShowAll, self)
	env:RegisterCallback('Settings/clusterShowFlyoutIcons', self.OnShowFlyoutIcons, self)
	env:RegisterCallback('OnLoadoutConfigShown', self.OnConfigShown, self)

	Mixin(self.cooldown, FlyoutCooldown):OnLoad()
	self:OnShowAll(env('clusterShowAll'))
	self:OnShowFlyoutIcons(env('clusterShowFlyoutIcons'))

	local flyoutArrow = self.FlyoutArrowContainer or self.FlyoutArrow or self.Arrow;
	if flyoutArrow then
		Mixin(flyoutArrow, FlyoutArrow)
	end

	self:HookScript('OnEnter', self.OnMouseMotionFocus)
	self:HookScript('OnLeave', self.OnMouseMotionClear)
	self:HookScript('OnEvent', self.OnAlphaEvent)
	for event in pairs(self.AlphaEvents) do
		self:RegisterEvent(event)
	end
end

function FlyoutButton:OnCooldownSet(cooldown, _, duration)
	local onCooldown = (cooldown and duration and duration > 0);
	local fadeInForCD = onCooldown and duration > 2;
	if cooldown then
		cooldown:SetDrawEdge(false)
	end
	self:UpdateAlpha(self.AlphaState.OnCooldown, fadeInForCD)
end

function FlyoutButton:OnCooldownClear()
	self:ToggleHotkeys(self.showFlyoutIcons)
	self:UpdateAlpha(self.AlphaState.OnCooldown, false)
end

function FlyoutButton:OnShowFlyoutIcons(enabled)
	self.showFlyoutIcons = enabled;
	self.cooldown:UpdateModifierIcons()
end

function FlyoutButton:SetAlpha(alpha, force)
	if force then return CPAPI.Index(self).SetAlpha(self, alpha) end
end

function FlyoutButton:UpdateAlpha(closure, state)
	self.alpha = closure(self.alpha, state);
	local fadeOut = self.alpha == 0;
	if fadeOut then
		self:FadeOut(0.25, self:GetAlpha())
	else
		self:FadeIn(0.25, self:GetAlpha())
	end
end

function FlyoutButton:UpdateVisibility(closure, state)
	self.shown = closure(self.shown, state);
	self:ToggleShown(self.shown == 0)
end

function FlyoutButton:SetBindings(primary, allBindings)
	local emulation = db.Gamepad.Index.Modifier.Owner[self.id];
	if emulation and env.IsModSubset(emulation, self.mod) then
		return self:UpdateVisibility(self.VisibilityState.NoBinding, true)
	end
	for modifier in pairs(allBindings) do
		if not env.IsModSubset(self.mod, modifier) then
			self:RefreshBinding(modifier, primary)
		else
			self:RefreshBinding(modifier, emulation and allBindings[NOMOD] or primary)
		end
	end
	self:RefreshBinding(self.mod, allBindings[NOMOD])
	self:RefreshBinding(ALT..self.mod, allBindings[ALT..self.mod])
	self:UpdateVisibility(self.VisibilityState.NoBinding, false)
end

function FlyoutButton:GetEffectiveCombination()
	return self.mod, self.id;
end

---------------------------------------------------------------
local MainButton = { OnCooldownClear = nop };
---------------------------------------------------------------

function MainButton:OnLoad()
	env:RegisterCallback('Settings/showMainIcons', self.ToggleHotkeys, self)
	self:ToggleHotkeys(env('showMainIcons'))

	self:HookScript('OnEnter', self.OnMouseMotionFocus)
	self:HookScript('OnLeave', self.OnMouseMotionClear)
	self:HookScript('PostClick', self.OnControllerClick)
	self:HookScript('OnHide', self.ClearControllerPress)

	Mixin(self.cooldown, env.ProxyCooldown):OnLoad()
end

function MainButton:OnControllerClick(button, down)
	if button ~= 'ControllerInput' or not self.texturedBorder then return end;
	if not (down and self:IsVisible()) then
		return self:ClearControllerPress();
	end
	-- Bound controller clicks do not use the native mouse press path.
	self.controllerPressed = true;
	self:SetButtonState('PUSHED')
end

function MainButton:ClearControllerPress()
	if not self.controllerPressed then return end;
	self.controllerPressed = nil;
	self:SetButtonState('NORMAL')
end

function MainButton:OnMouseMotionFocus()
	if self.mouseMotionTimeout then
		self.mouseMotionTimeout = self.mouseMotionTimeout:Cancel()
	end
	self:SetIgnoreParentAlpha(true)
end

function MainButton:OnMouseMotionClear()
	if self.mouseMotionTimeout then
		self.mouseMotionTimeout = self.mouseMotionTimeout:Cancel()
	end
	self.mouseMotionTimeout = C_Timer.NewTimer(5, function()
		self:SetIgnoreParentAlpha(false)
	end)
end

function MainButton:OnCooldownSet()
	self:Skin(false)
end

function MainButton:SetBindings(_, allBindings)
	local emulation = db.Gamepad.Index.Modifier.Owner[self.id];
	for modifier, binding in pairs(allBindings) do
		if not emulation then
			self:RefreshBinding(modifier, binding)
		else
			self:RefreshBinding(modifier, allBindings[env.ModComplement(modifier, emulation)])
		end
	end
end

function MainButton:ShouldOverrideActionBarBinding()
	return true;
end

function MainButton:GetOverrideBinding(modifier)
	return modifier..self.id;
end

---------------------------------------------------------------
local Button = Mixin({ SetNormalTexture = nop }, env.ProxyButton);
-- Textured border tuning values range from 0 to 1.
local BORDER_TUNING = {
	RestingBrightness      = 0.86; -- Fraction of Border Vertex Color used at rest.
	HoverWhiteMix          = 0.20; -- Amount of white mixed into the hover tint.
	PressedBrightness      = 0.68; -- Fraction of the border color used while held.
	GoldHoverOpacity       = 0.55; -- Strength of the hover highlight on gold designs.
	BeveledHoverOpacity    = 0.72; -- Strength of the hover highlight on Beveled Silver.
	ToggledOpacityBonus    = 0.12; -- Extra opacity over hover for the checked border.
	ToggledHoverMultiplier = 0.25; -- Fraction of normal hover opacity while toggled on.
};
---------------------------------------------------------------

local function updateBorderState(button)
	if not button.texturedBorder then return end;
	local pressed      = button:GetButtonState() == 'PUSHED';
	local hoverAlpha   = env:IsGoldClusterDesign() and BORDER_TUNING.GoldHoverOpacity or BORDER_TUNING.BeveledHoverOpacity;
	local checkedAlpha = math.min(1, hoverAlpha + BORDER_TUNING.ToggledOpacityBonus);
	if button:GetChecked() then
		hoverAlpha = hoverAlpha * BORDER_TUNING.ToggledHoverMultiplier;
	end
	button.HighlightTexture:SetAlpha(pressed and 0 or hoverAlpha)
	button.CheckedTexture:SetAlpha(pressed and 0 or checkedAlpha)
end

local function updateBorderStateAfterMouse(button)
	if not button.texturedBorder then return end;
	-- Mouse scripts can run before the native button state changes.
	CPAPI.Next(updateBorderState, button)
end

function Button:OnLoad(modifier, layoutData)
	env.ProxyButton.OnLoad(self)
	self:SetAttribute(CPAPI.SkipHotkeyRender, true)
	self:SetAttribute('id', self.id)
	self:SetAttribute('mod', modifier)

	self.CheckedTexture = self.CheckedTexture or self:GetCheckedTexture()
	self.PushedTexture  = self.PushedTexture  or self:GetPushedTexture()
	self.NormalTexture  = self.NormalTexture  or self:GetNormalTexture()
	self.HighlightTexture = self.HighlightTexture or self:GetHighlightTexture()
	self:HookScript('OnMouseDown', updateBorderStateAfterMouse)
	self:HookScript('OnMouseUp', updateBorderStateAfterMouse)
	self:HookScript('OnEnter', updateBorderState)
	hooksecurefunc(self, 'SetButtonState', updateBorderState)
	hooksecurefunc(self, 'SetChecked', updateBorderState)

	self.mod = modifier;
	self.layoutData = layoutData;
	if ( layoutData.Level ) then
		self:SetFrameLevel(layoutData.Level)
	end

	Mixin(self, modifier == NOMOD and MainButton or FlyoutButton):OnLoad()
	self:UpdateSkin()
end

function Button:ToggleHotkeys(enabled)
	local hotkey1, hotkey2 = self.Hotkey1, self.Hotkey2;
	if hotkey1 then hotkey1:SetShown(enabled) end;
	if hotkey2 then hotkey2:SetShown(enabled) end;
end

function Button:ToggleShown(enabled)
	self:SetShown(enabled)
	self:SetAttribute(env.Attributes.Hidden, not enabled)
end

function Button:SetBorderColor(color)
	self.borderColor = color;
	if env('clusterDesign') == env.Const.ClusterDesign.Original then
		self.NormalTexture:SetVertexColor(color:GetRGBA())
		if self.texturedBorder then
			-- Clear the textured state overrides when returning to the original border.
			self.texturedBorder = nil;
			if self.controllerPressed then self:ClearControllerPress() end;
			self.HighlightTexture:SetVertexColor(1, 1, 1, 1)
			self.PushedTexture:SetVertexColor(1, 1, 1, 1)
			self.CheckedTexture:SetVertexColor(1, 1, 1, 1)
			self.HighlightTexture:SetAlpha(1)
			self.CheckedTexture:SetAlpha(1)
		end
		return;
	end
	self.texturedBorder = true;
	local r, g, b, a  = color:GetRGBA();
	local rest        = BORDER_TUNING.RestingBrightness;
	local lighten     = BORDER_TUNING.HoverWhiteMix;
	local pressed     = BORDER_TUNING.PressedBrightness;
	local hr, hg, hb  = r + (1 - r) * lighten, g + (1 - g) * lighten, b + (1 - b) * lighten;
	self.NormalTexture:SetVertexColor(r * rest, g * rest, b * rest, a)
	self.HighlightTexture:SetVertexColor(hr, hg, hb, a)
	self.PushedTexture:SetVertexColor(r * pressed, g * pressed, b * pressed, a)
	self.CheckedTexture:SetVertexColor(hr, hg, hb, a)
	updateBorderState(self)
end

function Button:UpdateLocal(force)
	if self.Skin then
		self:Skin(force)
	end
end

function Button:UpdateSkin()
	self.UpdateLocal = Button.UpdateLocal;
	self.Skin = env.LIB.Skin.ClusterBar[self.mod] or nop; -- Skins.lua
	self:Skin(true)
end

function Button:GetOverlayColor()
	return env:GetColorRGBA('procColor')
end

---------------------------------------------------------------
-- Spell proc glow
-- Main buttons play the intro before the loop. Flyouts pulse during the burst.
---------------------------------------------------------------
local PROC_GLOW_PADDING  = 1 / 14; -- eight pixels around the 112-pixel border art
local PROC_LOOP_PADDING  = 0.2;
local PROC_INTRO_PADDING = 0.6;

local function createProcFade(group, texture, toAlpha, duration, smoothing)
	local fade = group:CreateAnimation('Alpha');
	fade:SetTarget(texture)
	fade:SetOrder(1)
	fade:SetFromAlpha(1)
	fade:SetToAlpha(toAlpha)
	fade:SetDuration(duration)
	fade:SetSmoothing(smoothing)
end

local function createProcFlipBook(group, texture, duration)
	local flipBook = group:CreateAnimation('FlipBook');
	flipBook:SetTarget(texture)
	flipBook:SetOrder(1)
	flipBook:SetDuration(duration)
	flipBook:SetFlipBookRows(4)
	flipBook:SetFlipBookColumns(8)
	flipBook:SetFlipBookFrames(30)
	flipBook:SetFlipBookFrameWidth(0)
	flipBook:SetFlipBookFrameHeight(0)
end

local function createFlyoutProcAnimations(glow, burst, loop, intro)
	glow:SetVertexColor(1, 0.82, 0.42)
	burst:SetVertexColor(1, 0.94, 0.70)
	loop:SetLooping('BOUNCE')
	createProcFade(loop, glow, 0.6, 0.5, 'IN_OUT')

	local duration = 0.28;
	local scale = intro:CreateAnimation('Scale');
	scale:SetTarget(burst)
	scale:SetOrder(1)
	scale:SetDuration(duration)
	scale:SetOrigin('CENTER', 0, 0)
	scale:SetSmoothing('OUT')
	scale:SetScale(1.28, 1.28)
	createProcFade(intro, burst, 0, duration, 'OUT')
end

local function createProcGlow(button)
	local glow  = button:CreateTexture(nil, 'OVERLAY', nil, 6);
	local burst = button:CreateTexture(nil, 'OVERLAY', nil, 7);
	glow:SetBlendMode('ADD')
	burst:SetBlendMode('ADD')
	glow:Hide()
	burst:Hide()

	local isMain = button.mod == NOMOD;
	local loop   = button:CreateAnimationGroup();
	local intro  = button:CreateAnimationGroup();
	if isMain then
		loop:SetLooping('REPEAT')
		createProcFlipBook(loop, glow, 1)
		createProcFlipBook(intro, burst, 0.4)
	else
		createFlyoutProcAnimations(glow, burst, loop, intro)
	end
	intro:SetScript('OnFinished', function()
		burst:Hide()
		if ( isMain and button.procGlowActive ) then
			glow:Show()
			loop:Play()
		end
	end)
	button.procGlow, button.procGlowLoop = glow, loop;
	button.procGlowBurst, button.procGlowIntro = burst, intro;
end

local function setProcGlowBounds(glow, border, padding)
	local xPadding = border:GetWidth() * padding;
	local yPadding = border:GetHeight() * padding;
	glow:ClearAllPoints()
	glow:SetPoint('TOPLEFT', border, 'TOPLEFT', -xPadding, yPadding)
	glow:SetPoint('BOTTOMRIGHT', border, 'BOTTOMRIGHT', xPadding, -yPadding)
end

local function setProcFlipBookTexture(region, texture)
	if region.procTexture ~= texture then
		region:SetTexture(texture)
		region.procTexture = texture;
	end
end

local function showProcGlow(button)
	if not button.procGlow then
		createProcGlow(button)
	end
	local glow, burst = button.procGlow, button.procGlowBurst;
	local border  = button.SpellHighlightTexture or button.NormalTexture;
	local texture = button.procGlowTexture;
	local isMain  = button.mod == NOMOD;
	setProcGlowBounds(glow, border, isMain and PROC_LOOP_PADDING or PROC_GLOW_PADDING)
	setProcGlowBounds(burst, border, isMain and PROC_INTRO_PADDING or PROC_GLOW_PADDING)
	if isMain then
		setProcFlipBookTexture(glow, texture.Loop)
		setProcFlipBookTexture(burst, texture.Start)
	else
		glow:SetTexture(texture)
		burst:SetTexture(texture)
		-- Wedge glows follow the same rotation and mirroring as the border.
		glow:SetTexCoord(border:GetTexCoord())
		burst:SetTexCoord(border:GetTexCoord())
	end
	if not (glow:IsShown() or burst:IsShown()) then
		burst:Show()
		button.procGlowIntro:Play()
		if not isMain then
			glow:Show()
			button.procGlowLoop:Play()
		end
	end
end

function Button:ShowOverlayGlow()
	self.procGlowActive = true;
	if self.procGlowTexture then
		showProcGlow(self)
	end
end

function Button:HideOverlayGlow()
	self.procGlowActive = nil;
	if self.procGlow then
		self.procGlowLoop:Stop()
		self.procGlowIntro:Stop()
		self.procGlow:Hide()
		self.procGlowBurst:Hide()
	end
end

function Button:SetProcGlowTexture(texture)
	self.procGlowTexture = texture;
	if self.procGlowActive then
		showProcGlow(self)
	end
end

---------------------------------------------------------------
CPClusterBar = CreateFromMixins(CPActionBar, env.MovableWidgetMixin);
---------------------------------------------------------------

function CPClusterBar:OnLoad()
	CPActionBar.OnLoad(self)

	env:RegisterSafeCallback('OnNewBindings', self.OnNewBindings, self)
	env:RegisterSafeCallback('Settings/clusterFullStateModifier', self.OnDriverChanged, self)
	db:RegisterSafeCallback('OnModifierChanged', self.OnDriverChanged, self)

	self:OnDriverChanged()
	self:RegisterPageResponse([[
		local newstate = ...;
		self:ChildUpdate('actionpage', newstate)
	]])
end

function CPClusterBar:SetProps(props)
	self:SetDynamicProps(props)
	self:UpdateClusters(props.children or {})
	CPActionBar.OnDriverChanged(self)
	CPActionBar.OnHierarchyChanged(self)
end

function CPClusterBar:OnPropsUpdated()
	self:SetProps(self.props)
end

function CPClusterBar:OnNewBindings(bindings)
	if not env:IsActive(self) then return end;
	for buttonID, set in pairs(bindings) do
		env:Map(CLUSTER_HANDLE, buttonID, function(cluster)
			if ( cluster:GetParent() == self ) then
				cluster:SetBindings(set)
			end
		end)
	end
	self:RunAttribute(env.Attributes.OnPage, self:GetAttribute('actionpage'))
	self:RunDriver('modifier')
end

function CPClusterBar:OnDriverChanged()
	local driver = env('clusterFullStateModifier') and env.Const.Cluster.ModDriver
		or db('Gamepad/Index/Modifier/Driver');
	self:RegisterModifierDriver(driver, [[
		self:SetAttribute('state', newstate)
		control:ChildUpdate('state', newstate)
		cursor::OwnerChanged(self:GetName())
	]])
end

function CPClusterBar:UpdateClusters(clusters)
	self:OnRelease()
	for buttonID, props in pairs(clusters) do
		local cluster = env:Acquire(CLUSTER_HANDLE, buttonID, self)
		if ( cluster:GetParent() ~= self ) then
			cluster:SetParent(self)
		end
		cluster:Show()
		cluster:SetProps(props)
	end
end

function CPClusterBar:OnRelease()
	self:UnregisterVisibilityDriver()
	env:Map(CLUSTER_HANDLE, nil, function(cluster)
		if ( cluster:GetParent() == self ) then
			env:Release(cluster)
		end
	end)
end

function CPClusterBar:GetSnapSize()
	return env.Const.Cluster.SnapPixels * 4;
end

---------------------------------------------------------------
-- Cluster bar factory
---------------------------------------------------------------

env:AddFactory(CLUSTER_BAR, function(id)
	local frame = CreateFrame('Frame', env.MakeID('ConsolePortBar%s', id), env.Manager, 'CPClusterBar')
	frame:OnLoad()
	return frame;
end, env.Interface.Cluster)

env:AddFactory(CLUSTER_HANDLE, function(id, parent)
	local buttons = {};
	local cluster = CPAPI.Proxy({buttons = buttons}, CPAPI.Proxy(buttons, Cluster))

	for modifier, layoutData in pairs(ClusterLayout) do
		local name = env.MakeID('CPB_%s_%s', id, modifier)
		local button = env:Acquire(CLUSTER_BUTTON, name, id, modifier, parent, layoutData)
		cluster.buttons[modifier] = button;
	end
	cluster:OnLoad(id, parent)
	return cluster;
end, env.Interface.ClusterHandle)

env:AddFactory(CLUSTER_BUTTON, function(id, buttonID, modifier, parent, layoutData)
	local button = Mixin(env.LAB:CreateButton(buttonID, id, parent, env.Button:GetConfig()), Button)
	env.LIB.SkinUtility.PreventSkinning(button)
	for i, hotkeyData in ipairs(layoutData.Hotkey) do
		local hotkeyID = env.MakeID('%s_%s_%d', id, modifier, i)
		local hotkey = Mixin(CreateFrame('Frame', hotkeyID, button), env.ProxyHotkey)
		hotkey.icon = hotkey:CreateTexture(nil, 'OVERLAY', nil, 7)
		hotkey.icon:SetAllPoints()
		hotkey:OnLoad(buttonID, unpack(hotkeyData))
		button['Hotkey'..i] = hotkey;
	end
	if ( layoutData.Shadow ) then
		button.Shadow = env:Acquire(CLUSTER_SHADOW, buttonID, parent, button, layoutData.Shadow)
	end
	button:OnLoad(modifier, layoutData)
	return button;
end)

env:AddFactory(CLUSTER_SHADOW, function(_, parent, owner, layoutData)
	local shadow = Mixin(parent:CreateTexture(nil, 'BACKGROUND', nil, 7), Shadow)
	shadow:OnLoad(owner, unpack(layoutData))
	return shadow;
end)

env:RegisterSafeCallback('Settings/clusterDesign', function(self)
	self:Map(CLUSTER_HANDLE, nil, function(cluster)
		cluster:SetSize(cluster.props.size)
	end)
end, env)
