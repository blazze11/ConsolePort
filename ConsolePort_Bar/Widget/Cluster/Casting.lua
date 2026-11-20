local CPAPI, env = CPAPI, CPAPI.GetEnv(...);
local CreateFrame, GenerateClosure = CreateFrame, GenerateClosure;
local _, _, CLUSTER_BUTTON = env.Const.Cluster.Types();
---------------------------------------------------------------
-- Cluster spellcast and channel effects
---------------------------------------------------------------
-- Values used by Blizzard's ActionButtonCastingAnimFrameTemplate.
local CAST, CHANNEL, EMPOWER   = 1, 2, 3;
local CHANNEL_END_TOLERANCE_MS = 150;
local getItemSpell             = C_Item and C_Item.GetItemSpell or GetItemSpell;

-- Cast type, transition, and position of castBarID after the spell ID.
local CAST_EVENTS = {
	UNIT_SPELLCAST_START          = {CAST; 'start'};
	UNIT_SPELLCAST_DELAYED        = {CAST; 'update'};
	UNIT_SPELLCAST_STOP           = {CAST; 'stop'};
	UNIT_SPELLCAST_SUCCEEDED      = {CAST; 'finish'};
	UNIT_SPELLCAST_FAILED         = {CAST; 'cancel'};
	UNIT_SPELLCAST_INTERRUPTED    = {CAST; 'cancel'; 2};
	UNIT_SPELLCAST_CHANNEL_START  = {CHANNEL; 'start'};
	UNIT_SPELLCAST_CHANNEL_UPDATE = {CHANNEL; 'update'};
	UNIT_SPELLCAST_CHANNEL_STOP   = {CHANNEL; 'finish'; 2};
	UNIT_SPELLCAST_EMPOWER_START  = {EMPOWER; 'start'};
	UNIT_SPELLCAST_EMPOWER_UPDATE = {EMPOWER; 'update'};
	UNIT_SPELLCAST_EMPOWER_STOP   = {EMPOWER; 'finish'; 3};
};
local activeCast, pendingCast;

---------------------------------------------------------------
-- Cast identity and timing
---------------------------------------------------------------
local function publicCastValue(value)
	if not CPAPI.IsSecret(value) then return value end;
end

local function sameCastIdentity(cast, guid, castBarID)
	if cast.castBarID and castBarID then return cast.castBarID == castBarID end;
	if cast.guid and guid then return cast.guid == guid end;
end

local function getEmpowerStages(numStages)
	if CPAPI.IsSecret(numStages) or not numStages or numStages <= 0 then return end;
	local hold = GetUnitEmpowerHoldAtMaxTime('player');
	if CPAPI.IsSecret(hold) or not hold or hold < 0 then return end;
	local stages, total = {}, 0;
	for rank = 1, numStages do
		local duration = GetUnitEmpowerStageDuration('player', rank - 1);
		if CPAPI.IsSecret(duration) or not duration or duration < 0 then return end;
		total = total + duration;
		stages[rank] = total;
	end
	if total > 0 then return stages, hold end;
end

local function readClusterCast(cast)
	local _;
	local startTime, endTime, guid, spellID, castBarID, empowered, numStages;
	if cast.castType == CAST then
		_, _, _, startTime, endTime, _, guid, _, spellID, castBarID = UnitCastingInfo('player');
	else
		_, _, _, startTime, endTime, _, _, spellID, empowered, numStages, castBarID = UnitChannelInfo('player');
	end
	if CPAPI.IsSecret(startTime) or CPAPI.IsSecret(endTime) then return end;
	if not (startTime and endTime and endTime > startTime) then return end;
	if cast.castType == CHANNEL and publicCastValue(empowered) then return end;

	guid, spellID, castBarID = publicCastValue(guid), publicCastValue(spellID), publicCastValue(castBarID);
	local sameCast = sameCastIdentity(cast, guid, castBarID);
	local knownSpell = cast.spellID or cast.eventSpellID;
	if ( sameCast == false or (not sameCast and knownSpell and spellID and knownSpell ~= spellID) ) then return end;
	if cast.castType == CAST and not (guid or castBarID or cast.guid or cast.castBarID) then return end;
	if not (spellID or knownSpell) then return end;
	-- A missing event spell can only be recovered from a matching live cast.
	if not (knownSpell or sameCast) then return end;

	if cast.castType == EMPOWER then
		local stages, hold = getEmpowerStages(numStages);
		if not stages then return end;
		cast.stages  = stages;
		cast.holdEnd = math.max(endTime, startTime + stages[#stages]) + hold;
	end
	cast.startTime, cast.endTime = startTime, endTime;
	cast.guid, cast.castBarID    = cast.guid or guid, cast.castBarID or castBarID;
	cast.spellID                = spellID or knownSpell;
	return true;
end

---------------------------------------------------------------
-- Action matching
---------------------------------------------------------------
local function getClusterCastAction(button)
	-- The secure slot can change before LAB updates its cached action.
	local kind   = publicCastValue(button:GetAttribute('type')) or button._state_type;
	local action = kind == button._state_type and publicCastValue(button._state_action) or nil;
	if kind == 'action' then
		action = publicCastValue(button:GetAttribute('action')) or action;
		if type(action) ~= 'number' or action < 1 then return kind end;
	end
	return kind, action;
end

local function getClusterCastSpell(button, kind, action)
	if kind == 'action' and not action then return end;
	if kind == button._state_type and action == publicCastValue(button._state_action) then
		local spellID = publicCastValue(button:GetSpellId());
		if spellID then return spellID end;
	end
	if not action then return end;
	local item;
	if kind == 'action' then
		local actionType, id, subType = GetActionInfo(action);
		if CPAPI.IsSecret(actionType) or CPAPI.IsSecret(id) or CPAPI.IsSecret(subType) then return end;
		if actionType == 'spell' or (actionType == 'macro' and subType == 'spell') then
			return id;
		elseif actionType == 'item' or (actionType == 'macro' and subType == 'item') then
			item = id;
		elseif actionType == 'macro' and id and not subType then
			-- Older clients can report a macro index instead of the resolved item.
			local spellID = publicCastValue((GetMacroSpell(id)));
			if spellID then return spellID end;
			item = select(2, GetMacroItem(id));
		end
	elseif kind == 'item' then
		item = action;
	elseif kind == 'macro' then
		item = select(2, GetMacroItem(action));
	end
	if not getItemSpell or CPAPI.IsSecret(item) or not item then return end;
	return publicCastValue((select(2, getItemSpell(item))));
end

local function matchesCastSpell(cast, spellID)
	if not spellID then return false end;
	if spellID == cast.spellID or spellID == cast.eventSpellID then return true end;
	if not (C_Spell and C_Spell.GetOverrideSpell) then return false end;
	local override = publicCastValue(C_Spell.GetOverrideSpell(spellID));
	return override and (override == cast.spellID or override == cast.eventSpellID);
end

local function matchesCurrentRank(cast, spellID, slot)
	-- Forever can keep ranked spells on separate slots. Only accept a
	-- same-name rank fallback when the native action slot is in use.
	if CPAPI.IsCamelotVersion and slot and spellID and C_ActionBar
		and C_ActionBar.IsCurrentAction and C_Spell and C_Spell.GetSpellName
		and publicCastValue(C_ActionBar.IsCurrentAction(slot)) then
		local name = publicCastValue(C_Spell.GetSpellName(spellID));
		return name and name == publicCastValue(C_Spell.GetSpellName(cast.spellID));
	end
end

---------------------------------------------------------------
-- Empower animation
---------------------------------------------------------------
local VIOLET = {.70; .34; 1};
local EMBER  = {1; .43; .17};
local GOLD   = {1; .80; .34};
local EMPOWER_BLEND_MS, EMPOWER_PULSE_MS, EMPOWER_PULSE_PEAK_MS = 220, 350, 80;

local function empowerRank(cast, elapsed)
	local rank = #cast.stages;
	while rank > 0 and elapsed < cast.stages[rank] do rank = rank - 1 end;
	return rank;
end

local function empowerColor(rank, count)
	if rank > 0 and rank == count then return unpack(GOLD) end;
	if rank < 2 then return unpack(VIOLET) end;
	local blend = (rank - 2) / (count - 2);
	return Lerp(EMBER[1], GOLD[1], blend), Lerp(EMBER[2], GOLD[2], blend), Lerp(EMBER[3], GOLD[3], blend);
end

local function stopClusterEmpower(frame)
	local effect = frame.clusterEmpower;
	if not effect then return end;
	frame:SetScript('OnUpdate', nil)
	effect.Fill:Hide()
	effect.Inner:Hide()
	effect.Pulse:Hide()
end

local function updateClusterEmpower(frame)
	local cast, effect = frame.clusterCast, frame.clusterEmpower;
	local now = GetTime() * 1000;
	if now > cast.holdEnd + CHANNEL_END_TOLERANCE_MS then return frame:Hide() end;

	local elapsed = math.max(0, now - cast.startTime);
	local total = cast.stages[#cast.stages];
	local rank = empowerRank(cast, elapsed);
	local stageTime = cast.stages[rank];
	local age = stageTime and elapsed - stageTime or math.huge;
	local progress = math.min(1, elapsed / total);
	local r, g, b = empowerColor(rank, #cast.stages);
	if rank > 0 and age < EMPOWER_BLEND_MS then
		local pr, pg, pb = empowerColor(rank - 1, #cast.stages);
		local t = age / EMPOWER_BLEND_MS;
		local blend = t * t * (3 - 2 * t);
		r, g, b = Lerp(pr, r, blend), Lerp(pg, g, blend), Lerp(pb, b, blend);
	end

	local mask          = effect.Mask;
	local scale         = frame:GetScale();
	local width, height = mask:GetSize();
	local button        = frame:GetParent();
	local shape         = button.clusterShape;
	local inset         = not button.layoutData.Prefix and shape and shape.MainHitInset or 0;
	local geometry      = (1 - 2 * inset) / scale;
	width, height       = width * geometry, height * geometry;
	local fillHeight = height * 1.24;
	local front      = height * (1.08 * progress - .55);
	effect.Fill:SetSize(width * 1.13, fillHeight)
	effect.Fill:SetPoint('CENTER', mask, 'CENTER', 0, front - fillHeight * .42)
	effect.Fill:SetVertexColor(r, g, b)
	effect.Inner:SetSize(width * 1.13, height * 1.12)
	effect.Inner:SetVertexColor(r, g, b)
	effect.Inner:SetAlpha(.56 * math.min(1, progress * 10))

	local pulse = effect.Pulse;
	pulse:SetShown(age < EMPOWER_PULSE_MS)
	if pulse:IsShown() then
		-- Keep the flare at the crossed threshold while the cast fill keeps moving.
		local spread = age / EMPOWER_PULSE_MS;
		local peak = age < EMPOWER_PULSE_PEAK_MS and age / EMPOWER_PULSE_PEAK_MS
			or ((EMPOWER_PULSE_MS - age) / (EMPOWER_PULSE_MS - EMPOWER_PULSE_PEAK_MS)) ^ 1.55;
		local nr, ng, nb = empowerColor(rank, #cast.stages);
		pulse:SetSize(width * (.89 + spread * .29), height * (.32 + spread * .25))
		pulse:SetPoint('CENTER', mask, 'CENTER', 0, height * (math.min(.92, stageTime / total) - .5))
		pulse:SetVertexColor(Lerp(nr, 1, .55), Lerp(ng, 1, .55), Lerp(nb, 1, .55))
		pulse:SetAlpha(peak * Lerp(.73, 1, rank / #cast.stages))
	end
end

local function createEmpowerTexture(frame, mask, subLevel)
	local texture = frame:CreateTexture(nil, 'ARTWORK', nil, subLevel);
	texture:SetBlendMode('ADD')
	texture:SetDesaturated(true)
	texture:AddMaskTexture(mask)
	texture:SetPoint('CENTER', mask, 'CENTER')
	return texture;
end

local function startClusterEmpower(button, frame, cast)
	local effect = frame.clusterEmpower;
	if not effect then
		local atlas = C_Texture.GetAtlasInfo('UI-HUD-ActionBar-Cast-Fill');
		if not atlas then return end;
		local mask = env.LIB.SkinUtility.GetIconMask(button);
		effect = {
			Mask  = mask;
			Fill  = createEmpowerTexture(frame, mask, 1);
			Inner = createEmpowerTexture(frame, mask, 0);
			Pulse = createEmpowerTexture(frame, mask, 2);
		};
		-- Map the atlas's bright right edge to the top without shrinking the sprite.
		local l, r, t, b = atlas.leftTexCoord, atlas.rightTexCoord, atlas.topTexCoord, atlas.bottomTexCoord;
		effect.Fill:SetTexture(atlas.file or atlas.filename)
		effect.Fill:SetTexCoord(r, t, l, t, r, b, l, b)
		effect.Inner:SetAtlas('UI-HUD-ActionBar-Casting-InnerGlow')
		effect.Pulse:SetAtlas('cast-empowered-pipflare')
		frame.clusterEmpower = effect;
	end
	frame.clusterCast = cast;
	frame.Fill.CastingAnim:Stop()
	frame.EndBurst.FinishCastAnim:Stop()
	frame.Fill:Hide()
	frame.EndBurst:Hide()
	effect.Fill:Show()
	effect.Inner:Show()
	frame:SetScript('OnUpdate', updateClusterEmpower)
	updateClusterEmpower(frame)
	frame:Show()
end

---------------------------------------------------------------
-- Button animation
---------------------------------------------------------------
local function syncClusterCast(button, timingChanged, checkLive)
	local frame     = button.SpellCastAnimFrame;
	local shownCast = frame and frame.clusterCast;
	local cast      = activeCast or shownCast;
	if not ( frame and cast and button:IsVisible() ) then return end;
	local kind, action = getClusterCastAction(button);
	local slot         = kind == 'action' and action or nil;
	local buttonSpell  = getClusterCastSpell(button, kind, action);
	local matches      = matchesCastSpell(cast, buttonSpell);
	if not matches and slot and C_ActionBar and C_ActionBar.GetSpell then
		-- The client can resolve a spell from this slot differently from GetActionInfo.
		local slotSpell = publicCastValue(C_ActionBar.GetSpell(slot));
		if slotSpell and slotSpell > 0 and matchesCastSpell(cast, slotSpell) then
			buttonSpell, matches = slotSpell, true;
		end
	end
	local sameButton = shownCast == cast and frame.clusterCastSpell == buttonSpell and frame.clusterCastAction == action
		and frame.clusterCastActionType == kind;
	matches = matches or sameButton or matchesCurrentRank(cast, buttonSpell, slot);
	if ( shownCast and (shownCast ~= cast or not matches) ) then
		frame:Hide()
	end
	if not (activeCast and matches) then return end;
	if checkLive and not sameButton and not readClusterCast(cast) then return end;

	local now = GetTime();
	if now * 1000 >= (cast.holdEnd or cast.endTime) then return end;
	local starting = frame.clusterCast ~= cast;
	frame.clusterCastSpell, frame.clusterCastAction, frame.clusterCastActionType = buttonSpell, action, kind;
	if cast.castType == EMPOWER then
		if starting then startClusterEmpower(button, frame, cast) end;
		return;
	end
	if not (starting or timingChanged) then return end;
	if starting then
		frame.clusterCast = cast;
		frame.EndBurst.FinishCastAnim:Stop()
		frame.EndBurst:Hide()
		-- Match Blizzard's stock art and travel using the same cast snapshot
		-- for every button, including buttons that become visible mid-cast.
		local fill      = frame.Fill;
		local isChannel = cast.castType == CHANNEL;
		local direction = isChannel and -1 or 1;
		fill.CastFill:ClearAllPoints()
		fill.CastFill:SetAtlas(isChannel and 'UI-HUD-ActionBar-Channel-Fill' or 'UI-HUD-ActionBar-Cast-Fill', true)
		fill.InnerGlowTexture:SetAtlas(isChannel and 'UI-HUD-ActionBar-Channel-InnerGlow' or 'UI-HUD-ActionBar-Casting-InnerGlow', true)
		fill.CastFill:SetPoint('CENTER', -45 * direction, 0)
		fill.CastingAnim.CastFillTranslation:SetOffset(43 * direction, 0)
		fill:Show()
		frame:Show()
	end

	local animation = frame.Fill.CastingAnim;
	animation:Stop()
	animation.CastFillTranslation:SetDuration((cast.endTime - cast.startTime) / 1000)
	animation:Play(false, math.max(0, now - cast.startTime / 1000))
end

local function refreshClusterCast(button)
	syncClusterCast(button, false, true)
end

local function onCastActionAttributeChanged(button, attribute)
	if activeCast and (attribute == 'type' or attribute == 'action') then
		CPAPI.Next(refreshClusterCast, button)
	end
end

local function finishClusterCast(button, cast, finished)
	local frame = button.SpellCastAnimFrame;
	if not frame or frame.clusterCast ~= cast then return end;
	if not finished then return frame:Hide() end;
	if frame.EndBurst:IsShown() then return end;
	if cast.castType == EMPOWER then
		stopClusterEmpower(frame)
		local ring = frame.EndBurst.GlowRing;
		local rank = empowerRank(cast, GetTime() * 1000 - cast.startTime);
		ring:SetDesaturated(true)
		ring:SetVertexColor(empowerColor(rank, #cast.stages))
	end
	frame:FinishAnimAndPlayBurst()
	frame.Fill:Hide()
end

---------------------------------------------------------------
-- Player cast events
---------------------------------------------------------------
local function matchesCastEvent(cast, castType, guid, spellID, castBarID)
	if not cast or cast.castType ~= castType then return false end;
	local sameCast = sameCastIdentity(cast, guid, castBarID);
	if sameCast ~= nil then return sameCast end;
	return spellID and (spellID == cast.spellID or spellID == cast.eventSpellID);
end

local function applyClusterCast(cast)
	-- A queued retry can outlive the cast that scheduled it.
	if cast ~= activeCast and cast ~= pendingCast then return end;
	local startTime, endTime = cast.startTime, cast.endTime;
	if not readClusterCast(cast) then return end;
	if pendingCast == cast then pendingCast = nil end;
	if activeCast and activeCast ~= cast then
		env:Map(CLUSTER_BUTTON, nil, finishClusterCast, activeCast, false)
	end
	activeCast = cast;
	env:Map(CLUSTER_BUTTON, nil, syncClusterCast, startTime ~= cast.startTime or endTime ~= cast.endTime)
end

local function clearClusterCast(cast, finished)
	if activeCast ~= cast then return end;
	activeCast = nil;
	env:Map(CLUSTER_BUTTON, nil, finishClusterCast, cast, finished)
end

local function onClusterCastEvent(info, _, _, guid, spellID, ...)
	guid, spellID = publicCastValue(guid), publicCastValue(spellID);
	local castType, transition, barPosition = unpack(info);
	local castBarID = publicCastValue((select(barPosition or 1, ...)));
	local matchesPending = matchesCastEvent(pendingCast, castType, guid, spellID, castBarID);
	local matchesActive = matchesCastEvent(activeCast, castType, guid, spellID, castBarID);
	if transition == 'start' or transition == 'update' then
		local existing = matchesPending and pendingCast or matchesActive and activeCast;
		if existing then return applyClusterCast(existing) end;
		if transition == 'update' and activeCast then return end;
		if not (guid or spellID or castBarID) then return end;
		local cast = {
			castType     = castType;
			guid         = guid;
			eventSpellID = spellID;
			castBarID    = castBarID;
		};
		pendingCast = cast;
		applyClusterCast(cast)
		-- The live cast and action slots can settle after the event.
		CPAPI.Next(applyClusterCast, cast)
		return;
	end

	if matchesPending then pendingCast = nil end;
	if not matchesActive then return end;
	local cast = activeCast;
	if transition == 'stop' then
		-- A success notification can follow STOP in the same frame.
		return CPAPI.Next(clearClusterCast, cast, false);
	end
	local finished = transition == 'finish';
	local result = ...;
	if castType == EMPOWER then
		finished = publicCastValue(result) == true;
	elseif castType == CHANNEL then
		finished = not CPAPI.IsSecret(result) and not result
			and GetTime() * 1000 + CHANNEL_END_TOLERANCE_MS >= cast.endTime;
	end
	clearClusterCast(cast, finished)
end

local CastHandler;
local function initializeCastHandler()
	if CastHandler then return end;
	CastHandler = CPAPI.CreateEventHandler({'Frame'});
	local events = {};
	local canEmpower = GetUnitEmpowerStageDuration and GetUnitEmpowerHoldAtMaxTime and C_Texture and C_Texture.GetAtlasInfo;
	for event, info in pairs(CAST_EVENTS) do
		if ( info[1] ~= EMPOWER or canEmpower ) then
			CastHandler[event] = GenerateClosure(onClusterCastEvent, info);
			events[#events + 1] = event;
		end
	end
	CPAPI.RegisterFrameForUnitEvents(CastHandler, events, 'player')
end

---------------------------------------------------------------
-- Button initialization
---------------------------------------------------------------
local function setCasting(button, casting)
	button:SetCastingSwipe(casting)
	if button.AlphaState then button:UpdateAlpha(button.AlphaState.Casting, casting) end;
end

local function onCastFrameShow(frame)
	setCasting(frame:GetParent(), true)
end

local function onCastFrameHide(frame)
	if frame.clusterEmpower then
		stopClusterEmpower(frame)
		frame.EndBurst.GlowRing:SetDesaturated(false)
		frame.EndBurst.GlowRing:SetVertexColor(1, 1, 1)
		frame.EndBurst:Hide()
	end
	frame.Fill.CastingAnim:Stop()
	frame.EndBurst.FinishCastAnim:Stop()
	frame.clusterCast, frame.clusterCastSpell = nil, nil;
	frame.clusterCastAction, frame.clusterCastActionType = nil, nil;
	frame:Hide()
	setCasting(frame:GetParent(), false)
end

local function onCastAnimationFinished(animation)
	animation:GetParent():GetParent():Hide()
end

function env:InitializeClusterCast(button)
	local frame = button.SpellCastAnimFrame;
	-- Classic loads the shared template, but its action buttons do not inherit it.
	if not frame and ActionButtonCastingAnimFrameMixin then
		frame = CreateFrame('Frame', nil, button, 'ActionButtonCastingAnimFrameTemplate');
		frame:SetScript('OnHide', nil)
		frame:Hide()
		button.SpellCastAnimFrame = frame;
	end
	if not frame then return end;

	frame:SetScript('OnShow', onCastFrameShow)
	frame:SetScript('OnHide', onCastFrameHide)
	-- The native fill normally starts a finish burst on its own. Only play it
	-- from the confirmed finish path so an interrupted cast can't flash late.
	frame.Fill.CastingAnim:SetScript('OnFinished', onCastAnimationFinished)
	frame.EndBurst.FinishCastAnim:SetScript('OnFinished', onCastAnimationFinished)
	hooksecurefunc(button, 'UpdateAction', refreshClusterCast)
	hooksecurefunc(button, 'OnActionBarSlotChanged', refreshClusterCast)
	button:HookScript('OnShow', refreshClusterCast)
	button:HookScript('OnAttributeChanged', onCastActionAttributeChanged)
	initializeCastHandler()
end
