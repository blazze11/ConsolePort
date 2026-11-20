local env = CPAPI.GetEnv(...)
---------------------------------------------------------------
local _, _, CLUSTER_BUTTON = env.Const.Cluster.Types();
local Cooldowns = {}; env.ClusterCooldownMixin = Cooldowns;
---------------------------------------------------------------
local COOLDOWN_REVEAL_DELAY = 2;
local LOSS_OF_CONTROL_RED   = 0.17;
local LOCKOUT_EDGE_TEXTURE = CPAPI.IsModernVersion and [[Interface\Cooldown\UI-HUD-ActionBar-LoC]]
	or [[Interface\Cooldown\edge-LoC]];
local YELLOW_EDGE_TEXTURE  = env.GetAsset[[Textures\Cluster\GCDEdge.png]];
local GCD_EDGE_COLOR       = CreateColor(1, 1, 1, 1);
local COOLDOWN_EDGE_COLOR  = CreateColor(0.72, 0.76, 1, 1);
local GCD_SPELL_ID         = (CPAPI.IsAnniVersion or CPAPI.IsClassicEraVersion or CPAPI.IsWrathVersion) and 29515 or 61304;
local FULL_ROTATION        = 2 * math.pi;
local edgeRotation         = C_CurveUtil and C_CurveUtil.CreateCurve and C_CurveUtil.CreateCurve();
if edgeRotation then
	edgeRotation:AddPoint(0, 0)
	edgeRotation:AddPoint(1, -FULL_ROTATION)
end

---------------------------------------------------------------
-- Timer setup and flyout visibility
---------------------------------------------------------------

local function isCooldownShown(cooldown)
	local shown = cooldown and cooldown:IsShown();
	return not CPAPI.IsSecret(shown) and shown;
end

local function getForeverLossOfControlInfo(button)
	if button._state_type == 'action' then
		return C_ActionBar.GetActionLossOfControlCooldownInfo(button._state_action);
	end
	return CPAPI.Index(button).GetLoCCooldownInfo(button);
end

function Cooldowns:GetCooldownWithoutGCD()
	local kind, action = self._state_type, self._state_action;
	if ( kind == 'action' and C_ActionBar and C_ActionBar.GetActionCooldownDuration ) then
		return C_ActionBar.GetActionCooldownDuration(action, true);
	elseif ( kind == 'spell' and C_Spell and C_Spell.GetSpellCooldownDuration ) then
		return C_Spell.GetSpellCooldownDuration(action, true);
	end
end

local function setCooldownReveal(cooldown, show)
	if cooldown.revealTimer then
		cooldown.revealTimer:Cancel()
		cooldown.revealTimer = nil;
	end
	cooldown.revealFlyout = show;
	cooldown.revealRestricted = nil;
end

local function updateCooldownVisibility(button)
	local normal = button.cooldown;
	button.cooldownVisibilityPending = nil;
	if not isCooldownShown(normal) then
		setCooldownReveal(normal, false)
	end
	local show = normal.revealFlyout or isCooldownShown(button.chargeCooldown) or isCooldownShown(button.lossOfControlCooldown);
	local flag = button.AlphaState.OnCooldown;
	if flag(button.alpha, show) ~= button.alpha then
		button:UpdateAlpha(flag, show)
	end
end

local function queueCooldownVisibility(cooldown)
	local button = cooldown:GetParent();
	if button.cooldownVisibilityPending then return end;
	button.cooldownVisibilityPending = true;
	-- LAB updates the three timers in sequence. Check visibility after all three settle.
	CPAPI.Next(updateCooldownVisibility, button)
end

local function onNumericCooldownSet(cooldown, _, duration)
	local isLockout = COOLDOWN_TYPE_LOSS_OF_CONTROL
		and cooldown.currentCooldownType == COOLDOWN_TYPE_LOSS_OF_CONTROL;
	setCooldownReveal(cooldown, isLockout or (not CPAPI.IsSecret(duration) and duration > COOLDOWN_REVEAL_DELAY))
	queueCooldownVisibility(cooldown)
end

local function onDurationCooldownSet(cooldown, duration)
	local actual = cooldown:GetParent():GetCooldownWithoutGCD();
	if actual then
		local zero = actual:IsZero();
		if not CPAPI.IsSecret(zero) then
			setCooldownReveal(cooldown, not zero)
			return queueCooldownVisibility(cooldown);
		end
	end
	if not duration:HasSecretValues() then
		return onNumericCooldownSet(cooldown, nil, duration:GetTotalDuration());
	end
	if cooldown.revealRestricted then return end;
	-- Give a restricted GCD time to finish, even if the previous cooldown revealed the flyout.
	cooldown.revealRestricted = true;
	cooldown.revealFlyout = false;
	queueCooldownVisibility(cooldown)
	cooldown.revealTimer = C_Timer.NewTimer(COOLDOWN_REVEAL_DELAY, function()
		cooldown.revealTimer = nil;
		cooldown.revealFlyout = isCooldownShown(cooldown);
		queueCooldownVisibility(cooldown)
	end);
end

local function onNormalCooldownCleared(cooldown)
	setCooldownReveal(cooldown, false)
	queueCooldownVisibility(cooldown)
end

local function watchCooldownVisibility(cooldown, onClear)
	onClear = onClear or queueCooldownVisibility;
	cooldown:HookScript('OnShow', queueCooldownVisibility)
	cooldown:HookScript('OnHide', onClear)
	cooldown:HookScript('OnCooldownDone', queueCooldownVisibility)
	hooksecurefunc(cooldown, 'Clear', onClear)
end

local function initializeChargeCooldown(button)
	if not button.chargeCooldown then
		-- On Classic, use LAB's native layout so the first recharge can be masked.
		local cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate');
		cooldown:SetHideCountdownNumbers(true)
		cooldown:SetDrawSwipe(false)
		cooldown:SetPoint('TOPLEFT', button.icon, 'TOPLEFT', 2, -2)
		cooldown:SetPoint('BOTTOMRIGHT', button.icon, 'BOTTOMRIGHT', -2, 2)
		cooldown:SetFrameLevel(button:GetFrameLevel())
		button.chargeCooldown = cooldown;
	end
end

function Cooldowns:InitializeCooldowns()
	initializeChargeCooldown(self)
	-- LAB skips action-slot lockouts on Forever, where current clients supply them.
	if ( CPAPI.IsCamelotVersion and self.lossOfControlCooldown and C_ActionBar
		and C_ActionBar.GetActionLossOfControlCooldownInfo and C_ActionBar.GetActionLossOfControlCooldownDuration ) then
		self.GetLoCCooldownInfo = getForeverLossOfControlInfo;
	end
	self.clusterCooldowns = {self.cooldown; self.chargeCooldown; self.lossOfControlCooldown;};
end

function Cooldowns:WatchCooldownVisibility()
	watchCooldownVisibility(self.cooldown, onNormalCooldownCleared)
	watchCooldownVisibility(self.chargeCooldown)
	if self.lossOfControlCooldown then
		watchCooldownVisibility(self.lossOfControlCooldown)
	end
	hooksecurefunc(self.cooldown, 'SetCooldown', onNumericCooldownSet)
	if self.cooldown.SetCooldownFromDurationObject then
		hooksecurefunc(self.cooldown, 'SetCooldownFromDurationObject', onDurationCooldownSet)
	end
end

---------------------------------------------------------------
-- Swipe tint and masked edges
---------------------------------------------------------------

local function isClassicLockout(cooldown)
	return COOLDOWN_TYPE_LOSS_OF_CONTROL and cooldown.currentCooldownType == COOLDOWN_TYPE_LOSS_OF_CONTROL;
end

local function isSwipeHidden(cooldown, isLossOfControl)
	return cooldown.clusterSwipeHidden or (cooldown.clusterCasting and not isLossOfControl);
end

local function getSwipeTint(cooldown, isLossOfControl)
	if isSwipeHidden(cooldown, isLossOfControl) then return 0, 0, 0, 0 end;
	if isLossOfControl then return LOSS_OF_CONTROL_RED, 0, 0, 0.64 end;
	return env:GetColorRGBA('clusterSwipeColor');
end

local function applySwipeTint(cooldown, isLossOfControl)
	-- Call the native method directly to avoid invoking the LAB color hook again.
	CPAPI.Index(cooldown).SetSwipeColor(cooldown, getSwipeTint(cooldown, isLossOfControl))
end

local function onSwipeColorChanged(cooldown, red, _, _, alpha)
	cooldown.clusterSwipeHidden = alpha == 0;
	if not cooldown.clusterSwipeHidden then
		-- Classic LAB sets the lockout red before updating the cooldown type.
		applySwipeTint(cooldown, red == LOSS_OF_CONTROL_RED)
	end
end

function Cooldowns:SetCastingSwipe(casting)
	local cooldown = self.cooldown;
	cooldown.clusterCasting = casting;
	applySwipeTint(cooldown, isClassicLockout(cooldown))
end

local function setCooldownBounds(cooldown, mask)
	cooldown:ClearAllPoints()
	cooldown:SetAllPoints(mask)
end

local function isGlobalCooldown(cooldown, start, duration)
	local timer = cooldown.clusterEdgeDuration;
	if timer then
		local actual = cooldown:GetParent():GetCooldownWithoutGCD();
		if actual then return actual:IsZero() end;
		start, duration = timer:GetStartTime(), timer:GetTotalDuration();
	end
	if CPAPI.IsSecret(start) or CPAPI.IsSecret(duration) or not start or not duration or start <= 0 or duration <= 0 then
		return false;
	end

	-- Compare the actual timer on clients that expose numeric cooldowns.
	local gcdStart, gcdDuration;
	if C_Spell and C_Spell.GetSpellCooldown then
		local gcd = C_Spell.GetSpellCooldown(GCD_SPELL_ID);
		if not CPAPI.IsSecret(gcd) and gcd then
			gcdStart, gcdDuration = gcd.startTime, gcd.duration;
		end
	elseif GetSpellCooldown then
		gcdStart, gcdDuration = GetSpellCooldown(GCD_SPELL_ID);
	end
	return not CPAPI.IsSecret(gcdStart) and not CPAPI.IsSecret(gcdDuration)
		and gcdStart and gcdDuration and gcdDuration > 0
		and math.abs(start - gcdStart) <= 0.001 and math.abs(duration - gcdDuration) <= 0.001;
end

local function setNormalEdge(cooldown, start, duration)
	local edge = cooldown.clusterEdge;
	if isClassicLockout(cooldown) then
		edge:SetTexture(LOCKOUT_EDGE_TEXTURE)
		edge:SetVertexColor(1, 1, 1, 1)
		return;
	end

	edge:SetTexture(YELLOW_EDGE_TEXTURE)
	local gcd = isGlobalCooldown(cooldown, start, duration);
	if CPAPI.IsSecret(gcd) then
		if edge.SetVertexColorFromBoolean then
			return edge:SetVertexColorFromBoolean(gcd, GCD_EDGE_COLOR, COOLDOWN_EDGE_COLOR);
		end
		gcd = false;
	end
	local color = gcd and GCD_EDGE_COLOR or COOLDOWN_EDGE_COLOR;
	edge:SetVertexColor(color:GetRGBA())
end

local function updateCooldownEdge(cooldown)
	local edge, duration = cooldown.clusterEdge, cooldown.clusterEdgeDuration;
	if isSwipeHidden(cooldown, isClassicLockout(cooldown)) then
		if edge:IsShown() then edge:Hide() end;
		return;
	end
	local rotation;
	if duration then
		rotation = duration:EvaluateElapsedPercent(edgeRotation);
	else
		local start, total = cooldown:GetCooldownTimes();
		if CPAPI.IsSecret(start) or CPAPI.IsSecret(total) or not start or not total or total <= 0 then
			return edge:Hide();
		end
		rotation = -FULL_ROTATION * math.max(0, math.min(1, (GetTime() * 1000 - start) / total));
	end
	edge:SetRotation(rotation)
	edge:Show()
end

local function hideCooldownEdge(cooldown)
	cooldown.clusterEdge:Hide()
end

local function maskCooldownEdge(cooldown, parent, mask, texture, setEdge)
	local edge = parent:CreateTexture(nil, parent == cooldown and 'OVERLAY' or 'ARTWORK', nil, 1);
	edge:SetAllPoints(mask)
	edge:SetTexture(texture)
	edge:AddMaskTexture(mask)
	edge:Hide()
	cooldown.clusterEdge = edge;

	-- Keep LAB's timer and use the stock edge art on a maskable texture.
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	hooksecurefunc(cooldown, 'SetDrawEdge', function(frame, enabled)
		if enabled then frame:SetDrawEdge(false) end;
	end)
	cooldown:HookScript('OnUpdate', updateCooldownEdge)
	cooldown:HookScript('OnHide', hideCooldownEdge)
	hooksecurefunc(cooldown, 'Clear', function(frame)
		frame.clusterEdgeDuration = nil;
		hideCooldownEdge(frame)
	end)
	hooksecurefunc(cooldown, 'SetCooldown', function(frame, start, duration)
		frame.clusterEdgeDuration = nil;
		if setEdge then setEdge(frame, start, duration) end;
	end)
	if edgeRotation and cooldown.SetCooldownFromDurationObject then
		hooksecurefunc(cooldown, 'SetCooldownFromDurationObject', function(frame, duration)
			frame.clusterEdgeDuration = duration;
			if setEdge then setEdge(frame) end;
		end)
	end
	return edge;
end

local function extendCooldownEdges(button, mask, scale)
	-- The streak fades before the texture ends. Extend it past the inner
	-- rim so the mask can clip it cleanly, even near the square corners.
	local width, height = mask:GetSize();
	if width <= 0 or height <= 0 then return end;
	for _, cooldown in ipairs(button.clusterCooldowns) do
		local edge = cooldown.clusterEdge;
		edge:ClearAllPoints()
		edge:SetPoint('CENTER', mask, 'CENTER')
		edge:SetSize(width * scale, height * scale)
	end
end

local function maskCooldownEdges(button, mask)
	local chargeEdge = maskCooldownEdge(button.chargeCooldown, button, mask, YELLOW_EDGE_TEXTURE);
	chargeEdge:SetVertexColor(1, 0.78, 0.43)
	maskCooldownEdge(button.cooldown, button.cooldown, mask, YELLOW_EDGE_TEXTURE, setNormalEdge)

	local lockout = button.lossOfControlCooldown;
	if lockout then
		maskCooldownEdge(lockout, lockout, mask, LOCKOUT_EDGE_TEXTURE)
	end
	hooksecurefunc(button.cooldown, 'SetSwipeColor', onSwipeColorChanged)

	if not CPAPI.IsModernVersion then
		-- Classic LAB re-enables bling when refreshing the normal timer.
		hooksecurefunc(button.cooldown, 'SetDrawBling', function(cooldown, enabled)
			if enabled then cooldown:SetDrawBling(false) end;
		end)
	end
end

function Cooldowns:SetCooldownSwipeTexture(texture)
	local normal, lockout = self.cooldown, self.lossOfControlCooldown;
	normal:SetSwipeTexture(texture, getSwipeTint(normal, isClassicLockout(normal)))
	if lockout then
		lockout:SetSwipeTexture(texture, getSwipeTint(lockout, true))
	end
end

function Cooldowns:SetCooldownFrameLevel(level)
	for _, cooldown in ipairs({self.cooldown; self.lossOfControlCooldown;}) do
		if cooldown.SetUsingParentLevel then
			cooldown:SetUsingParentLevel(false)
		end
		cooldown:SetFrameLevel(level)
	end
end

function Cooldowns:LayoutCooldowns(mask, edgeScale)
	setCooldownBounds(self.cooldown, mask)
	if self.lossOfControlCooldown then
		setCooldownBounds(self.lossOfControlCooldown, mask)
	end
	if not self.cooldown.clusterEdge then
		maskCooldownEdges(self, mask)
	end
	if edgeScale then
		extendCooldownEdges(self, mask, edgeScale)
	end
end

env:RegisterCallback('Settings/clusterSwipeColor', function()
	env:Map(CLUSTER_BUTTON, nil, function(button)
		applySwipeTint(button.cooldown, isClassicLockout(button.cooldown))
	end)
end)
