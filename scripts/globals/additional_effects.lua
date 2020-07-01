------------------------------------------------------------------------------
-- This global is intended to handle additional effects from item sources of:
-- melee attacks, ranged attacks, auto-spikes
-- Notes:
-- Ranged versions get bonus from int/mnd, melee does NOT.
-- No matter how much INT you stack that fire sword doesn't hit any harder.
-- No matter how much MND you stack that holy mace doesn't hit any harder.
-- But Ice Arrows and Bloody Bolts will gain damage from INT and Holy bolts will gain damage from MND.
-- Melee weapon proc also do not appear to adjust for level, only resistance.
-- In testing my fire sword had the same damage ranges no matter my level vs same mob.
-- Weakness/resistance to element would swing damage range a lot
-- For status effects is it possible to land on highly resistant mobs because of flooring.
------------------------------------------------------------------------------
require("scripts/globals/teleports") -- For warp weapon proc.
require("scripts/globals/status")
require("scripts/globals/magic") -- For resist functions
require("scripts/globals/utils") -- For clamping function
require("scripts/globals/msg")
--------------------------------------

tpz = tpz or {}
tpz.addEffect = tpz.addEffect or {}

tpz.addEffect.isRanged = function(item)
    -- Archery/Marksmanship/Throwing
    return math.abs(item:getSkillType() - tpz.skill.MARKSMANSHIP) < 2
end

tpz.addEffect.calcRangeBonus = function(attacker, defender, element, damage)
    -- Copied from existing scripts.
    local bonus = 0
    if element == tpz.magic.ele.LIGHT then
        bonus = attacker:getStat(tpz.mod.MND) - defender:getStat(tpz.mod.MND)
        if bonus > 40 then
            bonus = bonus + (bonus -40) /2;
            damage = damage + bonus
        end
    else
        bonus = attacker:getStat(tpz.mod.INT) - defender:getStat(tpz.mod.INT)
        if bonus > 20 then
            bonus = bonus + (bonus -20) /2;
            damage = damage + bonus
        end
    end

    return damage
end

tpz.addEffect.levelCorrection = function(dLV, aLV, chance)
    -- Level correction of proc chance (copied from existing bolt/arrow scripts, looks wrong..)
    if dLV > aLV then
        chance = utils.clamp(chance - 5 * (dLV - aLV), 5, 95)
    end

    return chance
end

tpz.addEffect.statusAttack = function(addStatus)
    local effectList =
    {
        [tpz.effect.DEFENSE_DOWN] = {tick = 0, strip = tpz.effect.DEFENSE_BOOST},
        [tpz.effect.EVASION_DOWN] = {tick = 0, strip = tpz.effect.EVASION_BOOST},
        [tpz.effect.ATTACK_DOWN]  = {tick = 0, strip = tpz.effect.ATTACK_BOOST},
        [tpz.effect.POISON]       = {tick = 3, strip = nil},
        [tpz.effect.CHOKE]        = {tick = 3, strip = nil},
    }
    local delEffect = effectList[addStatus]
    defender:delStatusEffect(delEffect.strip)
    return tick
end

tpz.addEffect.calcDamage = function(attacker, element, defender, damage)
    local params = {}
    params.bonusmab = 0
    params.includemab = false
    damage = addBonusesAbility(attacker, element, defender, damage, params)
    damage = damage * applyResistanceAddEffect(attacker, defender, element, 0)
    damage = adjustForTarget(defender, damage, element)
    damage = finalMagicNonSpellAdjustments(attacker, defender, element, damage)
    return damage
end

-- paralyze on hit, fire damage on hit, etc..
function additionalEffectAttack(attacker, defender, baseAttackDamage, item)
    local addType = item:getMod(tpz.mod.ITEM_ADDEFFECT_TYPE)
    local subEffect = item:getMod(tpz.mod.ITEM_SUBEFFECT)
    local damage = item:getMod(tpz.mod.ITEM_ADDEFFECT_DMG)
    local chance = item:getMod(tpz.mod.ITEM_ADDEFFECT_CHANCE)
    local element = item:getMod(tpz.mod.ITEM_ADDEFFECT_ELEMENT)
    local addStatus = item:getMod(tpz.mod.ITEM_ADDEFFECT_STATUS)
    local power = item:getMod(tpz.mod.ITEM_ADDEFFECT_POWER)
    local duration = item:getMod(tpz.mod.ITEM_ADDEFFECT_DURATION)
    local msgID = 0
    local msgValue = 0
    local procType =
    {
        -- These are arbitrary, make up new ones as needed.
        NORMAL = 1,
        HP_HEAL = 2,
        MP_HEAL = 3,
        HP_DRAIN = 4,
        MP_DRAIN = 5,
        TP_DRAIN = 6,
        HPMPTP_DRAIN = 7,
        DISPEL = 8,
        SELF_BUFF = 9,
        DEATH = 10,
    }

    -- If we're not going to proc, lets not execute all those checks!
    if chance < math.random(100) then
        return 0,0,0
    end

    --------------------------------------
    -- Modifications for proc's sourced from ranged attacks. See notes at top of script.
    if tpz.addEffect.isRanged(item) then
        if element then
            damage = tpz.addEffect.calcRangeBonus(attacker, defender, element, damage)
        end
        chance = ltpz.addEffect.evelCorrection(defender:getMainLvl(), attacker:getMainLvl(), chance)
    end
    --------------------------------------

    if addType == procType.NORMAL then
        if addStatus and addStatus > 0 then
            local tick = tpz.addEffect.statusAttack(addStatus)
            msgID = tpz.msg.basic.ADD_EFFECT_STATUS
            defender:addStatusEffect(addStatus, power, tick, duration)
            msgValue = addStatus
        end

        if damage > 0 then
            -- local damage = damage * (math.random(90, 110)/100) -- Artificially forcing 20% variance.
            damage = tpz.addEffect.calcDamage(attacker, element, defender, damage)

            if subEffect == tpz.subEffect.HP_DRAIN then
                msgID = tpz.msg.basic.ADD_EFFECT_HP_DRAIN
                if damage < 0 then
                    damage = 0
                end
            else
                msgID = tpz.msg.basic.ADD_EFFECT_damage
                if damage < 0 then
                    msgID = tpz.msg.basic.ADD_EFFECT_HEAL
                end
            end
            msgValue = damage
        end

    elseif addType == procType.HP_HEAL then -- Its not a drain and works vs undead. https://www.bg-wiki.com/bg/Dominion_Mace
        local HP = 10 -- need actual calculation here!

        msgID = tpz.msg.basic.ADD_EFFECT_HP_HEAL
        attacker:addHP(HP)
        -- We have to fake this or it will say the defender was healed rather than the attacker.
        attacker:messageBasic(tpz.msg.basic.ADD_EFFECT_HP_HEAL)
        -- We're faking it, so return zeros!
        msgID = 0
        msgValue = 0

    elseif addType == procType.MP_HEAL then -- Mjollnir does this
        local MP = 10 -- need actual calculation here!
        attacker:addMP(MP)
        -- We have to fake this or it will say the defender was healed rather than the attacker.
        attacker:messageBasic(tpz.msg.basic.ADD_EFFECT_MP_HEAL)
        -- We're faking it, so return zeros!
        msgID = 0
        msgValue = 0

    elseif addType == procType.HP_DRAIN or (addType == procType.HPMPTP_DRAIN and math.random(1,3) == 1) then -- procType.HP_DRAIN
        damage = damage * applyResistanceAddEffect(attacker, defender, element, 0)
        if damage > defender:getHP() then
            damage = defender:getHP()
        end

        msgID = tpz.msg.basic.ADD_EFFECT_HP_DRAIN
        msgValue = damage
        defender:addHP(-damage)
        attacker:addHP(damage)

    elseif addType == procType.MP_DRAIN or (addType == procType.HPMPTP_DRAIN and math.random(1,3) == 2) then
        -- damage = damage * (math.random(90, 110)/100) -- Artificially forcing 20% variance.
        damage = damage * applyResistanceAddEffect(attacker, defender, element, 0)
        if damage > defender:getMP() then
            damage = defender:getMP()
        end
        msgID = tpz.msg.basic.ADD_EFFECT_MP_DRAIN
        msgValue = damage
        defender:addMP(-damage)
        attacker:addMP(damage)

    elseif addType == procType.TP_DRAIN or (addType == procType.HPMPTP_DRAIN and math.random(1,3) == 3) then
        -- damage = damage * (math.random(90, 110)/100) -- Artificially forcing 20% variance.
        damage = damage * applyResistanceAddEffect(attacker, defender, element, 0)
        if damage > defender:getTP() then
            damage = defender:getTP()
        end
        msgID = tpz.msg.basic.ADD_EFFECT_TP_DRAIN
        msgValue = damage
        defender:addTP(-damage)
        attacker:addTP(damage)

    elseif addType == procType.DISPEL then
        local dispel = defender:dispelStatusEffect()
        -- Resistance check should be in dispelStatusEffect() itself
        if dispel == tpz.effect.NONE then
            return 0, 0, 0
        else
            msgID = tpz.msg.basic.ADD_EFFECT_DISPEL
            msgValue = dispel
        end

    elseif addType == procType.SELF_BUFF then
        if addStatus == tpz.effect.TELEPORT then -- WARP
            attacker:addStatusEffectEx(tpz.effect.TELEPORT, 0, tpz.teleport.id.WARP, 0, 1)
            msgID = tpz.msg.basic.ADD_EFFECT_WARP
            msgValue = 0
        elseif addStatus == tpz.effect.BLINK then -- BLINK http://www.ffxiah.com/item/18830/gusterion
            -- Does not stack with or replace other shadows
            if attacker:hasStatusEffect(tpz.effect.BLINK) or attacker:hasStatusEffect(tpz.effect.UTSUSEMI) then
                return 0, 0, 0
            else
                attacker:addStatusEffect(tpz.effect.BLINK, power, 0, duration)
                -- We're faking it, so return zeros!
                msgID = 0
                msgValue = 0
            end
        else
            -- Only known one to go here so far is HASTE (not haste samba) http://www.ffxiah.com/search/item?q=blurred
            attacker:addStatusEffect(tpz.effect.HASTE, power, 0, duration, 0, 0) -- Todo: verify power/duration/tier
            -- We're faking it, so return zeros!
            msgID = 0
            msgValue = 0
        end

    elseif addType == procType.DEATH then
        -- Todo: Resistance?
        if defender:isNM() then
            return 0, 0, 0 -- NMs immune, so return out
        end
        msgID = tpz.msg.basic.ADD_EFFECT_STATUS
        msgValue = tpz.effect.KO
        defender:setHP(0)
    end

    --[[ Why did I do this??
    if msgValue == nil then
        return 0,0,0
    end
    ]]

    return subEffect, msgID, msgValue
end

function additionalEffectSpikes(attacker, defender, damage, spikeEffect, power, chance)
    --[[ Todo..
    local procType =
    {
        -- These are arbitrary, make up new ones as needed.
    }
    ]]
end
