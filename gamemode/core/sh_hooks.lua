nut.util.Include("sv_hooks.lua")
nut.util.Include("cl_hooks.lua")

--[[
	Purpose: Similar to an entity's SetupDataTables, this prepares any variables that
	are to be networked. This can be called on the schema to make custom variables, but
	is used on the framework for default variables. You should not edit this.
--]]
function GM:CreateCharVars(character)
	character:NewVar("charname", "John Doe", CHAR_PUBLIC)
	character:NewVar("description", "An unknown person.", CHAR_PUBLIC)
	character:NewVar("money", 0, CHAR_PRIVATE)
	character:NewVar("inv", {}, CHAR_PRIVATE)
	character:NewVar("chardata", {}, CHAR_PRIVATE)
	character:NewVar("gender", "male", CHAR_PUBLIC)
	character:NewVar("id", 0, CHAR_PUBLIC, true)
end

function GM:GetPlayerName(client, mode)
	return client:Name()
end

WEAPON_LOWERED = 1
WEAPON_RAISED = 2

local math_NormalizeAngle = math.NormalizeAngle
local string_find = string.find
local string_lower = string.lower
local getAnimClass = nut.anim.GetClass
local getHoldType = nut.util.GetHoldType
local config = nut.config

local Length2D = FindMetaTable("Vector").Length2D

function GM:CalcMainActivity(client, velocity)
	local model = string_lower(client:GetModel())
	local class = getAnimClass(model)

	if (string_find(model, "/player/") or string_find(model, "/playermodel") or class == "player") then
		return self.BaseClass:CalcMainActivity(client, velocity)
	end

	if (client.character and client:Alive()) then
		client.CalcSeqOverride = -1

		local weapon = client:GetActiveWeapon()
		local holdType = "normal"
		local action = "idle"
		local length2D = Length2D(velocity)

		if (length2D >= config.runSpeed - 10) then
			action = "run"
		elseif (length2D >= 5) then
			action = "walk"
		end

		if (client:Crouching()) then
			action = action.."_crouch"
		end

		local state = WEAPON_LOWERED

		if (IsValid(weapon)) then
			holdType = getHoldType(weapon)

			if (weapon.AlwaysRaised or config.alwaysRaised[weapon:GetClass()]) then
				state = WEAPON_RAISED
			end
		end

		if (client:WepRaised()) then
			state = WEAPON_RAISED
		end
		
		local animClass = nut.anim[class]

		if (!animClass) then
			class = "citizen_male"
		end

		if (!animClass[holdType]) then
			holdType = "normal"
		end

		if (!animClass[holdType][action]) then
			action = "idle"
		end

		local animation = animClass[holdType][action]
		local value = ACT_IDLE

		if (!client:OnGround()) then
			client.CalcIdeal = animClass.glide or ACT_GLIDE
		elseif (client:InVehicle()) then
			client.CalcIdeal = animClass.normal.idle_crouch[1]
		elseif (animation) then
			value = animation[state]

			if (type(value) == "string") then
				client.CalcSeqOverride = client:LookupSequence(value)
			else
				client.CalcIdeal = value
			end
		end

		local override = client:GetNetVar("seq")

		if (override) then
			client.CalcSeqOverride = client:LookupSequence(override)
		end

		if (CLIENT) then
			client:SetIK(false)
		end

		local eyeAngles = client:EyeAngles()
		local yaw = velocity:Angle().yaw
		local normalized = math_NormalizeAngle(yaw - eyeAngles.y)

		client:SetPoseParameter("move_yaw", normalized)

		return client.CalcIdeal or ACT_IDLE, client.CalcSeqOverride or -1
	end
end

function GM:PhysgunPickup(client, entity)
	if (client:IsAdmin()) then
		if (entity:IsPlayer()) then
			entity:SetMoveType(MOVETYPE_NOCLIP)

			return true
		end
	end

	if (entity.PhysgunDisable) then
		if (entity.PhysgunAllowAdmin and client:IsAdmin()) then
			return  true
		end
		
		return false
	end

	return client:IsAdmin() or (!entity:IsPlayer() and !entity:IsNPC())
end

function GM:PhysgunDrop(client, entity)
	if (entity:IsPlayer()) then
		entity:SetMoveType(MOVETYPE_WALK)
	end
end

function GM:DoAnimationEvent(client, event, data)
	local model = string_lower(client:GetModel())
	local class = getAnimClass(model)

	if (string_find(model, "/player/") or string_find(model, "/playermodel") or class == "player") then
		return self.BaseClass:DoAnimationEvent(client, event, data)
	end

	local weapon = client:GetActiveWeapon()
	local holdType = "normal"
	local class = nut.anim.GetClass(model)

	if (!nut.anim[class]) then
		class = "citizen_male"
	end

	if (IsValid(weapon)) then
		holdType = nut.util.GetHoldType(weapon)
	end

	if (!nut.anim[class][holdType]) then
		holdType = "normal"
	end

	local animation = nut.anim[class][holdType]

	if (event == PLAYERANIMEVENT_ATTACK_PRIMARY) then
		client:AnimRestartGesture(GESTURE_SLOT_ATTACK_AND_RELOAD, animation.attack or ACT_GESTURE_RANGE_ATTACK_SMG1, true)

		return ACT_VM_PRIMARYATTACK
	elseif (event == PLAYERANIMEVENT_ATTACK_SECONDARY) then
		client:AnimRestartGesture(GESTURE_SLOT_ATTACK_AND_RELOAD, animation.attack or ACT_GESTURE_RANGE_ATTACK_SMG1, true)

		return ACT_VM_SECONDARYATTACK
	elseif (event == PLAYERANIMEVENT_RELOAD) then
		client:AnimRestartGesture(GESTURE_SLOT_ATTACK_AND_RELOAD, animation.reload or ACT_GESTURE_RELOAD_SMG1, true)

		return ACT_INVALID
	elseif (event == PLAYERANIMEVENT_JUMP) then
		client.m_bJumping = true
		client.m_bFistJumpFrame = true
		client.m_flJumpStartTime = CurTime()

		client:AnimRestartMainSequence()

		return ACT_INVALID
	elseif (event == PLAYERANIMEVENT_CANCEL_RELOAD) then
		client:AnimResetGestureSlot(GESTURE_SLOT_ATTACK_AND_RELOAD)

		return ACT_INVALID
	end

	return nil
end

function GM:PlayerNoClip(client)
	return client:IsAdmin()
end

function GM:CanProperty(client, property, entity)
	return client:IsAdmin()
end

function GM:PlayerCanUseItem(client, item)
	if (client:GetNetVar("tied") and !item.allowUseOnTied) then
		return false
	end
end