-- ============================================================
-- CoAAbilityTrainer - Core Engine
-- Central state manager: tracks active class/spec, combat state,
-- dispatches updates to UI modules
-- ============================================================

CoAAT_Engine = {}

-- Internal state
local state = {
    classId      = nil,   -- e.g. "felsworn"
    specId       = nil,   -- e.g. "infernal_assault"
    inCombat     = false,
    aoeMode      = false,  -- false = Single Target, true = AoE
    resource     = 0,
    resourceMax  = 100,
    targetExists = false,
    targetHP     = 100,   -- % 0-100
    playerHP     = 100,   -- % 0-100
    petAlive     = false,
    -- Tracked buffs/debuffs (name → { active, remaining, applied })
    buffs    = {},
    debuffs  = {},
    -- Tracked cooldowns (abilityId → { start, duration })
    cooldowns = {},
    -- Tracked procs (procName → { active, remaining })
    procs = {},
    -- Ability objects for the active spec
    abilities = {},
    rotationRules = {},
}
CoAAT_Engine._state = state

-- ─────────────────────────────────────────────
-- Init / Setup
-- ─────────────────────────────────────────────
function CoAAT_Engine.Init()
    local db = CoAAT_DB
    if not db then return end

    if db.selectedClass and CoAAT_Abilities[db.selectedClass] then
        CoAAT_Engine.SetClass(db.selectedClass, db.selectedSpec)
    else
        -- Auto-read character class
        local _, classToken = UnitClass("player")
        if classToken then
            local detectId = classToken:lower()
            -- Replace spaces (if any class names have spaces, e.g. "Knight of Xoroth" -> "knight_of_xoroth")
            detectId = detectId:gsub(" ", "_")
            
            if CoAAT_Abilities[detectId] then
                local specId = nil
                if detectId == "felsworn" then
                    specId = "slayer"
                elseif detectId == "necromancer" then
                    specId = "reanimation"
                elseif detectId == "witch_hunter" then
                    specId = "inquisitor"
                else
                    local classDef = CoAAT_Abilities[detectId]
                    if classDef and classDef.specs then
                        for sId, _ in pairs(classDef.specs) do
                            specId = sId
                            break
                        end
                    end
                end

                if specId then
                    CoAAT_Engine.SetClass(detectId, specId)
                end
            end
        end
    end
end

-- ─────────────────────────────────────────────
-- Set active class + spec
-- ─────────────────────────────────────────────
function CoAAT_Engine.SetClass(classId, specId)
    if not CoAAT_Abilities[classId] then
        print("|cffff4444[CoAT]|r Unknown class: " .. tostring(classId))
        return
    end

    state.classId = classId
    state.specId  = specId

    local classDef = CoAAT_Abilities[classId]
    state.resourceMax  = classDef.resourceMax
    state.resourceColor = classDef.resourceColor

    -- Gather abilities for this spec
    state.abilities = {}
    if specId and classDef.specs and classDef.specs[specId] then
        local specDef = classDef.specs[specId]
        for _, ab in ipairs(specDef.abilities) do
            state.abilities[ab.id] = ab
        end
    end

    -- Gather rotation rules
    state.rotationRules = {}
    if CoAAT_RotationRules[classId] and specId and CoAAT_RotationRules[classId][specId] then
        state.rotationRules = CoAAT_RotationRules[classId][specId]
    end

    -- Save selection
    if CoAAT_DB then
        CoAAT_DB.selectedClass = classId
        CoAAT_DB.selectedSpec  = specId
    end

    -- Notify UI
    if CoAAT_CombatHUD.OnClassChanged then
        CoAAT_CombatHUD.OnClassChanged(classId, specId)
    end
    if CoAAT_RotationHelper.OnClassChanged then
        CoAAT_RotationHelper.OnClassChanged(classId, specId)
    end

    print("|cff00ccff[CoA Trainer]|r Class set to: |cffFFD700" ..
        (CoAAT_Abilities[classId].resource and (classId .. " (" .. specId .. ")") or classId) .. "|r")
end

-- ─────────────────────────────────────────────
-- Resource tracking (simulated for CoA custom resources)
-- Since CoA custom resources can't be read via UnitPower directly,
-- we simulate based on ability usage events + CLEU parsing
-- ─────────────────────────────────────────────
function CoAAT_Engine.SetResource(val)
    state.resource = math.max(0, math.min(state.resourceMax, val))
    if CoAAT_ResourceBar.Update then
        CoAAT_ResourceBar.Update(state.resource, state.resourceMax, state.resourceColor)
    end
end

function CoAAT_Engine.ModifyResource(delta)
    CoAAT_Engine.SetResource(state.resource + delta)
end

function CoAAT_Engine.GetResource()
    return state.resource, state.resourceMax
end

-- ─────────────────────────────────────────────
-- Buff / Debuff tracking
-- ─────────────────────────────────────────────
function CoAAT_Engine.SetBuff(name, remaining)
    state.buffs[name] = { active = true, remaining = remaining or 9999 }
end

function CoAAT_Engine.RemoveBuff(name)
    state.buffs[name] = { active = false, remaining = 0 }
end

function CoAAT_Engine.HasBuff(name)
    return state.buffs[name] and state.buffs[name].active
end

function CoAAT_Engine.SetDebuff(name, remaining)
    state.debuffs[name] = { active = true, remaining = remaining or 0 }
end

function CoAAT_Engine.RemoveDebuff(name)
    state.debuffs[name] = { active = false, remaining = 0 }
end

function CoAAT_Engine.HasDebuff(name)
    return state.debuffs[name] and state.debuffs[name].active
end

function CoAAT_Engine.GetDebuffRemaining(name)
    if state.debuffs[name] then return state.debuffs[name].remaining end
    return 0
end

-- ─────────────────────────────────────────────
-- Cooldown tracking
-- ─────────────────────────────────────────────
function CoAAT_Engine.StartCooldown(abilityId, duration)
    state.cooldowns[abilityId] = { start = GetTime(), duration = duration }
    if CoAAT_CooldownTracker.OnCooldownStart then
        CoAAT_CooldownTracker.OnCooldownStart(abilityId, duration)
    end
end

function CoAAT_Engine.IsReady(abilityId)
    local cd = state.cooldowns[abilityId]
    if not cd then return true end
    return (GetTime() - cd.start) >= cd.duration
end

function CoAAT_Engine.GetRemaining(abilityId)
    local cd = state.cooldowns[abilityId]
    if not cd then return 0 end
    local elapsed = GetTime() - cd.start
    return math.max(0, cd.duration - elapsed)
end

-- ─────────────────────────────────────────────
-- Proc tracking
-- ─────────────────────────────────────────────
function CoAAT_Engine.TriggerProc(procName, duration)
    state.procs[procName] = { active = true, expires = GetTime() + (duration or 5) }
    if CoAAT_ProcAlert.OnProc then
        CoAAT_ProcAlert.OnProc(procName, duration)
    end
    -- Also update rotation helper
    if CoAAT_RotationHelper.OnProcTriggered then
        CoAAT_RotationHelper.OnProcTriggered(procName)
    end
end

function CoAAT_Engine.HasProc(procName)
    local p = state.procs[procName]
    if not p or not p.active then return false end
    if GetTime() > p.expires then
        state.procs[procName].active = false
        return false
    end
    return true
end

function CoAAT_Engine.ConsumeProc(procName)
    if state.procs[procName] then
        state.procs[procName].active = false
    end
end

-- ─────────────────────────────────────────────
-- Combat state
-- ─────────────────────────────────────────────
function CoAAT_Engine.SetCombat(inCombat)
    state.inCombat = inCombat
    if CoAAT_CombatHUD.OnCombatChange then
        CoAAT_CombatHUD.OnCombatChange(inCombat)
    end
    if CoAAT_RotationHelper.OnCombatChange then
        CoAAT_RotationHelper.OnCombatChange(inCombat)
    end
end

function CoAAT_Engine.IsInCombat()
    return state.inCombat
end

-- ─────────────────────────────────────────────
-- Unit state
-- ─────────────────────────────────────────────
function CoAAT_Engine.UpdateUnitState()
    -- Player HP %
    local hp   = UnitHealth("player")
    local hpMax = UnitHealthMax("player")
    state.playerHP = (hpMax > 0) and math.floor((hp / hpMax) * 100) or 100

    -- Target exists?
    state.targetExists = UnitExists("target") and not UnitIsDead("target")

    -- Target HP %
    if state.targetExists then
        local thp    = UnitHealth("target")
        local thpMax = UnitHealthMax("target")
        state.targetHP = (thpMax > 0) and math.floor((thp / thpMax) * 100) or 100
    else
        state.targetHP = 100
    end

    -- Pet alive?
    state.petAlive = UnitExists("pet") and not UnitIsDead("pet")
end

function CoAAT_Engine.GetPlayerHP()   return state.playerHP   end
function CoAAT_Engine.GetTargetHP()   return state.targetHP   end
function CoAAT_Engine.HasTarget()     return state.targetExists end
function CoAAT_Engine.IsPetAlive()    return state.petAlive   end

-- ─────────────────────────────────────────────
-- Rotation evaluator
-- Returns the highest-priority ability to use right now
-- ─────────────────────────────────────────────
local function GetPlayerInterruptSpell()
    local interrupts = {
        ["kick"] = true, ["pummel"] = true, ["wind shear"] = true, ["counterspell"] = true,
        ["shield bash"] = true, ["mind freeze"] = true, ["silence"] = true, 
        ["arcane binding"] = true, ["whip crack"] = true, ["spear hand strike"] = true
    }
    for id, ab in pairs(state.abilities) do
        if interrupts[ab.name:lower()] and CoAAT_Engine.IsReady(id) then
            return id, ab
        end
    end
    return nil
end

local function GetPlayerPurgeSpell()
    local purges = {
        ["purge"] = true, ["dispel magic"] = true, ["devour magic"] = true,
        ["spellsteal"] = true, ["cleanse"] = true
    }
    for id, ab in pairs(state.abilities) do
        if purges[ab.name:lower()] and CoAAT_Engine.IsReady(id) then
            return id, ab
        end
    end
    return nil
end

function CoAAT_Engine.EvaluateRotation()
    if not state.classId then return nil end

    -- ── Counter Engine: Real-Time Interrupt & Dispel Checks ──
    if UnitExists("target") and not UnitIsDead("target") and not UnitIsPlayer("target") then
        local targetGUID = UnitGUID("target")
        local npcID = targetGUID and tonumber(string.sub(targetGUID, 9, 12), 16) or 0
        
        -- 1. Check target casting (Interrupt)
        local castName, _, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("target")
        if castName then
            local isDangerous = false
            if CoAAT_DB and CoAAT_DB.combatLearn and CoAAT_DB.combatLearn[npcID] then
                if CoAAT_DB.combatLearn[npcID].dangerousCasts[castName] then
                    isDangerous = true
                end
            end
            
            if not notInterruptible then
                local intId, intDef = GetPlayerInterruptSpell()
                if intId then
                    return {
                        abilityId = intId,
                        urgency = isDangerous and "critical" or "high",
                        abilityDef = intDef,
                        counterType = "interrupt",
                        counterText = "INTERRUPT: " .. castName
                    }
                end
            end
        end

        -- 2. Check target buffs (Purge/Dispel)
        local purgeId, purgeDef = GetPlayerPurgeSpell()
        if purgeId then
            for k = 1, 40 do
                local buffName, _, _, _, debuffType = UnitBuff("target", k)
                if not buffName then break end
                
                local shouldPurge = (debuffType == "Magic")
                if CoAAT_DB and CoAAT_DB.combatLearn and CoAAT_DB.combatLearn[npcID] then
                    if CoAAT_DB.combatLearn[npcID].purgeBuffs[buffName] then
                        shouldPurge = true
                    end
                end
                
                if shouldPurge then
                    return {
                        abilityId = purgeId,
                        urgency = "high",
                        abilityDef = purgeDef,
                        counterType = "purge",
                        counterText = "PURGE: " .. buffName
                    }
                end
            end
        end
    end

    local function IsSpellAvailable(ab)
        if not ab then return false end
        local name = GetSpellInfo(ab.name)
        if not name then return false end
        
        local playerLevel = UnitLevel("player") or 1
        if playerLevel < 60 then
            if CoAAT_RotationHelper and CoAAT_RotationHelper.IsSpellOnHotbar then
                if not CoAAT_RotationHelper.IsSpellOnHotbar(ab.name) then
                    return false
                end
            end
        end
        return true
    end

    local res, resMax = state.resource, state.resourceMax
    local rules = state.rotationRules

    local matches = {}
    local seen = {}

    for _, rule in ipairs(rules) do
        -- Filter based on AoE / Single Target mode if specified
        local skipRule = false
        if rule.mode == "aoe" and not state.aoeMode then
            skipRule = true
        elseif rule.mode == "single" and state.aoeMode then
            skipRule = true
        end

        if not skipRule then
            local matched = false

            if rule.condition == "always" then
                matched = true
            elseif rule.condition == "buff_missing" then
                matched = not CoAAT_Engine.HasBuff(rule.buffName)
            elseif rule.condition == "debuff_missing" then
                matched = not CoAAT_Engine.HasDebuff(rule.debuffName)
            elseif rule.condition == "debuff_expiring" then
                matched = CoAAT_Engine.HasDebuff(rule.debuffName) and
                          CoAAT_Engine.GetDebuffRemaining(rule.debuffName) <= 2.5
            elseif rule.condition == "cd_ready" then
                matched = CoAAT_Engine.IsReady(rule.abilityId)
            elseif rule.condition == "proc_active" then
                matched = CoAAT_Engine.HasProc(rule.procName)
            elseif rule.condition == "resource_gte" then
                matched = res >= rule.threshold
            elseif rule.condition == "pet_dead" then
                matched = not CoAAT_Engine.IsPetAlive()
            elseif rule.condition == "health_lt" then
                matched = CoAAT_Engine.GetPlayerHP() < rule.threshold
            end

            if matched then
                local aId = rule.abilityId
                local abDef = state.abilities[aId]
                if abDef and IsSpellAvailable(abDef) then
                    if not seen[aId] then
                        seen[aId] = true
                        table.insert(matches, {
                            abilityId = aId,
                            urgency = rule.urgency,
                            abilityDef = abDef
                        })
                        if #matches >= 3 then
                            break
                        end
                    end
                end
            end
        end
    end

    return matches[1], matches[2], matches[3]
end

-- ─────────────────────────────────────────────
-- Tick: called every 0.1s OnUpdate
-- ─────────────────────────────────────────────
local tickAccum = 0
function CoAAT_Engine.OnUpdate(dt)
    tickAccum = tickAccum + dt
    if tickAccum < 0.1 then return end
    tickAccum = 0

    CoAAT_Engine.UpdateUnitState()

    -- Update debuff remaining timers
    local now = GetTime()
    for name, db in pairs(state.debuffs) do
        if db.active and db.remaining then
            db.remaining = db.remaining - 0.1
            if db.remaining <= 0 then
                db.active = false
            end
        end
    end

    -- Update proc expirations
    for name, proc in pairs(state.procs) do
        if proc.active and now > proc.expires then
            proc.active = false
            if CoAAT_ProcAlert.OnProcExpired then
                CoAAT_ProcAlert.OnProcExpired(name)
            end
        end
    end

    -- Evaluate rotation and push to helper
    local m1, m2, m3 = CoAAT_Engine.EvaluateRotation()
    if CoAAT_RotationHelper.SetNextAbilities then
        CoAAT_RotationHelper.SetNextAbilities(m1, m2, m3)
    end

    -- Update cooldown tracker
    if CoAAT_CooldownTracker.Tick then
        CoAAT_CooldownTracker.Tick(state.cooldowns, state.abilities)
    end
end

-- ─────────────────────────────────────────────
-- CLEU event parser: detect ability usage
-- ─────────────────────────────────────────────
function CoAAT_Engine.OnCLEU(...)
    local ts, event, _, srcGUID, _, _, _, destGUID, _, _, _,
          spellId, spellName = ...

    -- Only care about player-sourced events
    local playerGUID = UnitGUID("player")
    
    -- ── CLE Learning Loop ──
    -- 1. SPELL_DAMAGE from target to player
    if event == "SPELL_DAMAGE" and destGUID == playerGUID then
        local amount = select(15, ...)
        if amount and type(amount) == "number" then
            local maxHealth = UnitHealthMax("player")
            if maxHealth > 0 and (amount / maxHealth) >= 0.15 then
                local sourceName = select(5, ...)
                if sourceName and srcGUID then
                    local npcID = tonumber(string.sub(srcGUID, 9, 12), 16)
                    if npcID and CoAAT_DB and CoAAT_DB.combatLearn then
                        if not CoAAT_DB.combatLearn[npcID] then
                            CoAAT_DB.combatLearn[npcID] = { dangerousCasts = {}, purgeBuffs = {} }
                        end
                        if not CoAAT_DB.combatLearn[npcID].dangerousCasts[spellName] then
                            CoAAT_DB.combatLearn[npcID].dangerousCasts[spellName] = true
                            print("|cffFFD700[CoAAT] Learned: |r|cffFF4444" .. spellName .. "|r is dangerous from " .. sourceName .. "!")
                        end
                    end
                end
            end
        end
    end

    -- 2. SPELL_AURA_APPLIED (CCs on player, or Magic buffs on target)
    if event == "SPELL_AURA_APPLIED" then
        if destGUID == playerGUID then
            local spellName = select(13, ...)
            local ccNames = {
                ["polymorph"] = true, ["fear"] = true, ["stun"] = true, ["silence"] = true,
                ["psychic scream"] = true, ["seduction"] = true, ["freezing trap"] = true,
                ["repentance"] = true, ["hammer of justice"] = true, ["death coil"] = true,
                ["howl of terror"] = true, ["fel prison"] = true
            }
            local lowerSpell = spellName and spellName:lower() or ""
            if ccNames[lowerSpell] or string.find(lowerSpell, "stun") or string.find(lowerSpell, "fear") or string.find(lowerSpell, "silence") then
                local sourceName = select(5, ...)
                if sourceName and srcGUID then
                    local npcID = tonumber(string.sub(srcGUID, 9, 12), 16)
                    if npcID and CoAAT_DB and CoAAT_DB.combatLearn then
                        if not CoAAT_DB.combatLearn[npcID] then
                            CoAAT_DB.combatLearn[npcID] = { dangerousCasts = {}, purgeBuffs = {} }
                        end
                        if not CoAAT_DB.combatLearn[npcID].dangerousCasts[spellName] then
                            CoAAT_DB.combatLearn[npcID].dangerousCasts[spellName] = true
                            print("|cffFFD700[CoAAT] Learned: |r|cffFF4444" .. spellName .. "|r (CC) is dangerous from " .. sourceName .. "!")
                        end
                    end
                end
            end
        elseif destGUID ~= playerGUID and srcGUID ~= playerGUID then
            -- Target gets a magic buff
            local spellName = select(13, ...)
            local magicBuffs = {
                ["power infusion"] = true, ["bloodlust"] = true, ["heroism"] = true,
                ["divine shield"] = true, ["ice barrier"] = true, ["mana shield"] = true,
                ["inner fire"] = true, ["rejuvenation"] = true, ["renew"] = true
            }
            local lowerSpell = spellName and spellName:lower() or ""
            if magicBuffs[lowerSpell] or string.find(lowerSpell, "barrier") or string.find(lowerSpell, "shield") or string.find(lowerSpell, "infusion") then
                local destName = select(9, ...)
                if destGUID then
                    local npcID = tonumber(string.sub(destGUID, 9, 12), 16)
                    if npcID and CoAAT_DB and CoAAT_DB.combatLearn then
                        if not CoAAT_DB.combatLearn[npcID] then
                            CoAAT_DB.combatLearn[npcID] = { dangerousCasts = {}, purgeBuffs = {} }
                        end
                        if not CoAAT_DB.combatLearn[npcID].purgeBuffs[spellName] then
                            CoAAT_DB.combatLearn[npcID].purgeBuffs[spellName] = true
                            print("|cffFFD700[CoAAT] Learned: |r|cff00ffff" .. spellName .. "|r is purgeable on " .. (destName or "Target") .. "!")
                        end
                    end
                end
            end
        end
    end

    if srcGUID ~= playerGUID then return end

    local lowerName = spellName and spellName:lower() or ""

    -- Spell cast: start cooldown + resource change
    if event == "SPELL_CAST_SUCCESS" then
        -- Find matching ability by name fragment
        for id, ab in pairs(state.abilities) do
            if ab.name:lower() == lowerName then
                -- Start cooldown if it has one
                if ab.cooldown and ab.cooldown > 0 then
                    CoAAT_Engine.StartCooldown(id, ab.cooldown)
                end
                -- Apply resource cost/gain
                if ab.resourceCost then
                    CoAAT_Engine.ModifyResource(-ab.resourceCost)
                end
                if ab.resourceGain then
                    CoAAT_Engine.ModifyResource(ab.resourceGain)
                end
                -- Apply buff/debuff tracking
                if ab.type == "buff" then
                    CoAAT_Engine.SetBuff(ab.name, ab.duration)
                elseif ab.type == "debuff" then
                    CoAAT_Engine.SetDebuff(ab.name, ab.duration)
                end
                -- Consume proc if this ability was a proc spend
                if ab.type == "proc" then
                    CoAAT_Engine.ConsumeProc(ab.name)
                end
                break
            end
        end
    end

    -- Buff/debuff gain on player
    if event == "SPELL_AURA_APPLIED" and destGUID == playerGUID then
        CoAAT_Engine.SetBuff(spellName, 10)
        -- Check if this is a proc
        for id, ab in pairs(state.abilities) do
            if ab.type == "proc" and ab.name:lower() == lowerName then
                CoAAT_Engine.TriggerProc(ab.name, 8)
            end
        end
    end

    -- Buff removed
    if event == "SPELL_AURA_REMOVED" and destGUID == playerGUID then
        CoAAT_Engine.RemoveBuff(spellName)
    end

    -- Debuff applied on target
    if event == "SPELL_AURA_APPLIED" and destGUID ~= playerGUID and srcGUID == playerGUID then
        for id, ab in pairs(state.abilities) do
            if ab.type == "debuff" and ab.name:lower() == lowerName then
                CoAAT_Engine.SetDebuff(ab.name, ab.duration or 10)
            end
        end
    end
end

-- Get all abilities for the active spec
function CoAAT_Engine.GetAbilities()
    return state.abilities
end

function CoAAT_Engine.GetClassId()  return state.classId end
function CoAAT_Engine.GetSpecId()   return state.specId  end
function CoAAT_Engine.GetClassDef()
    if state.classId then return CoAAT_Abilities[state.classId] end
    return nil
end
function CoAAT_Engine.GetSpecDef()
    if state.classId and state.specId then
        local c = CoAAT_Abilities[state.classId]
        if c and c.specs then return c.specs[state.specId] end
    end
    return nil
end

-- ─────────────────────────────────────────────
-- AoE Mode management
-- ─────────────────────────────────────────────
function CoAAT_Engine.ToggleAoEMode()
    state.aoeMode = not state.aoeMode
    if CoAAT_RotationHelper.OnAoEToggled then
        CoAAT_RotationHelper.OnAoEToggled(state.aoeMode)
    end
    print("|cff00ccff[CoAAT] Combat Mode set to: " .. (state.aoeMode and "|cff00ffff[AOE]|r" or "|cff22ff22[Single Target]|r"))
end

function CoAAT_Engine.GetAoEMode()
    return state.aoeMode
end
