if Player.CharName ~= "Nidalee" then return end
local scriptName = "FengshuiNidalee"
local scriptCreator = "thedude"
local scriptVersion = "0.1.0"
local scriptColor = 0x3CBBFFFF

module(scriptName, package.seeall, log.setup)
clean.module(scriptName, clean.seeall, log.setup)

local insert, sort = table.insert, table.sort
local huge, pow, min, max, floor = math.huge, math.pow, math.min, math.max, math.floor

local SDK = _G.CoreEx
local ObjManager = SDK.ObjectManager
local EventManager = SDK.EventManager
local Geometry = SDK.Geometry
local Renderer = SDK.Renderer
local Enums = SDK.Enums
local Game = SDK.Game
local Input = SDK.Input
local Evade = SDK.EvadeAPI
local Vector = Geometry.Vector
local Cone = Geometry.Cone
local Libs = _G.Libs
local Menu = Libs.NewMenu
local Orbwalker = Libs.Orbwalker
local Collision = Libs.CollisionLib
local Prediction = Libs.Prediction
local Spell = Libs.Spell
local DmgLib = Libs.DamageLib
local TS = Libs.TargetSelector()
local Profiler = Libs.Profiler
local summSlots = {Enums.SpellSlots.Summoner1, Enums.SpellSlots.Summoner2}

local slots = {
    Q = Enums.SpellSlots.Q,
    W = Enums.SpellSlots.W,
    E = Enums.SpellSlots.E,
    R = Enums.SpellSlots.R
}

local dmgTypes = {
    Physical = Enums.DamageTypes.Physical,
    Magical = Enums.DamageTypes.Magical,
    True = Enums.DamageTypes.True
}

-- human 

local damageHuman = {
    Q = {
        Base = {70, 90, 110, 130, 150},
        TotalAP = 0.50,
        Type = dmgTypes.Magical
    },
    W = {
        Base = {40, 80, 120, 160, 200},
        TotalAP  = 0.20,
        Type = dmgTypes.Magical
    }
}

-- mana manger will get included by FengshuiLib.lua
local manaHuman = {
    Q = {
        Cost = {50, 55, 60, 65, 70}
    },
    W = {
        Cost = {50, 55, 60, 65, 70}
    },
    E = {
        Cost = {50, 55, 60, 65, 70}
    }
}

local spellsHuman = {
    Q = Spell.Skillshot({
        Slot = slots.Q,
        Delay = 0.25,
        Speed = 1300,
        Range = 1500,
        Width = 10, -- 8
        LastCastT = 0,
        Type = "Linear",
        Collisions = {Heroes = true, Minions = true, Windwall = true, Wall = false},
    }),
    W = Spell.Skillshot({
        Slot = slots.W,
        Delay = 0.25,
        Speed = math.huge,
        Range = 900,
        Radius = 150,
        Type = "Circular",
        IsTrap = true,
        LastCastT = 0,
    }),
    E = Spell.Targeted({
        Slot = slots.E,
        Delay = 0.25,
        Range = 900,
        LastCastT = 0,
    })
}

local spellsCougar = {
    Q = Spell.Active({
        Slot = slots.Q,
        Delay = 0.0,
        Range = 125,
        LastCastT = 0,
    }),
    W = Spell.Skillshot({
        Slot = slots.W,
        Delay = 0.0,
        Range = 750,
        Radius = 200,
        LastCastT = 0,
        Type = "Linear",
        Collisions = {Heroes = false, Minions = false, Windwall = false, Wall = false},
    }),
    WE = Spell.Skillshot({
        Slot = slots.W,
        Delay = 0.0,
        Range = 125,
        Radius = 200,
        LastCastT = 0,
        Type = "Linear",
        Collisions = {Heroes = false, Minions = false, Windwall = false, Wall = false},
    }),
    E = Spell.Skillshot({
        Slot = slots.E,
        Delay = 0.0,
        Range = 310,
        Radius = 310,
        Angle = 180,
        LastCastT = 0,
        Type = "Radius",
        Collisions = {Heroes = false, Minions = false, Windwall = false, Wall = false},
    })
}

local spells = {
    R = Spell.Active({
        Slot = slots.R,
        Delay = 0.0,
        LastCastT = 0,
    }),
    Flash = {
        Slot = nil,
        LastCastT = 0,
        LastCheckT = 0,
        Range = 400
    }
}

local slotToDamageTableHuman = {
    [slots.Q] = damageHuman.Q,
    [slots.W] = damageHuman.W,
    [slots.R] = damageHuman.R
}

local events = {}
local combatVariants = {}
local Engine = {}
local champName = Player.CharName

local Nidalee = {}
Nidalee.Human = {}
Nidalee.Human.Q = {}
Nidalee.Human.Q.CD = 6
Nidalee.Human.Q.LastCastT = nil
Nidalee.Human.W = {}
Nidalee.Human.W.CD = 13
Nidalee.Human.W.LastCastT = nil
Nidalee.Human.E = {}
Nidalee.Human.E.CD = 11.45
Nidalee.Human.E.LastCastT = nil
Nidalee.Cougar = {}
Nidalee.Cougar.W = {}
Nidalee.Cougar.W.LastCastT = nil
Nidalee.Buffmanager = {}
Nidalee.Buffmanager.HuntedTarget = nil
Nidalee.Buffmanager.HuntedEndT = nil

function Engine.GetMenu(menuId, nothrow)
    return Menu.Get(champName .. "." .. menuId, nothrow)
end

function Engine.GetAARange(unit)
    local unit = unit or Player
    return Orbwalker.GetTrueAutoAttackRange(unit, nil)
end

function Engine.ShouldRunScript()
    return not (Game.IsChatOpen() or Game.IsMinimized() or Player.IsDead or Player.IsRecalling)
end

function Engine.CanCast(slot)
    return Player:GetSpellState(slot) == Enums.SpellStates.Ready
end

function Engine.CanCastSpell(slot, menuId)
    if Engine.GetMenu(menuId) then
        return Engine.CanCast(slot)
    end
    return false
end

function Engine.IsPosUnderTurret(pos)
    local enemyTurrets = ObjManager.GetNearby("enemy", "turrets")

    local boundingRadius = Player.BoundingRadius

    for _, obj in ipairs(enemyTurrets) do
        local turret = obj.AsTurret

        if turret and turret.IsValid and not turret.IsDead and pos:DistanceSqr(turret) <= pow(900 + boundingRadius, 2) then
            return true
        end
    end

    return false
end

function Engine.GetPercentHealth(unit)
    unit = unit or Player
    return unit.HealthPercent * 100
end

function Engine.GetPercentMana(unit)
    unit = unit or Player
    return unit.ManaPercent * 100
end

function Engine.IsInRange(source, destination, Min, Max)
    local Distance = source:Distance(destination)
    return Distance > Min and Distance <= Max
end

function Engine.HasBuff(buffName, unit)
    local unit = unit or Player
    if unit:GetBuff(buffName) ~= nil then
        return true
    else
        return false
    end
end

function Engine.GetSpellCooldown(slot)
    return Player:GetSpell(slot).TotalCooldown
end

function Engine.GetLowestAlly(range)
    local lowHero = nil
    local heroes = ObjManager.GetNearby("ally", "heroes")
    for index, obj in ipairs(heroes) do
        local hero = obj.AsHero

        if hero.IsValid and Engine.IsInRange(Player.Position, hero.Position, 0, range) and not hero.IsMe then
            if not lowHero then
                lowHero = hero
            elseif lowHero.Health > hero.Health then
                lowHero = hero
            end
        end        
    end
    return lowHero
end

---
-- NIDALEE
---

function Nidalee.CastHumanQ(target)
    if not target then
        target = spellsHuman.Q:GetTarget()
    end

    if target and target.IsValid then
        if spellsHuman.Q:CastOnHitChance(target, (Engine.GetMenu("hitchance.humanQ") / 100)) then 
            return true
        end
    end
    return false
end

function Nidalee.CastHumanE(target)
    if not target then
        target = Player
    end
    spellsHuman.E:Cast(target)
end

function Nidalee.GetHumanDamage(target, slot)
    local rawDamage = 0
    local damageType = nil
    local spellLevel = Player:GetSpell(slot).Level

    if spellLevel >= 1 then
        local data = slotToDamageTableHuman[slot]

        if data then
            damageType = data.Type
            rawDamage = rawDamage + data.Base[spellLevel]

            if data.TotalAD then
                rawDamage = rawDamage + (data.TotalAD * Player.TotalAD)
            end

            if data.TotalAP then
                rawDamage = rawDamage + (data.TotalAP * Player.TotalAP)
            end

            if damageType == dmgTypes.Physical then
                return DmgLib.CalculatePhysicalDamage(Player, target, rawDamage)
            elseif damageType == dmgTypes.Magical then
                return DmgLib.CalculateMagicalDamage(Player, target, rawDamage)
            else
                return rawDamage
            end
        end
    end

    return 0
end

-- this needs to be fixed
function Nidalee.GetCougarDamage(target, slot)
    local rawDamage = 0
    local damageType = nil
    local spellLevel = Player:GetSpell(slot).Level
    if spellLevel >= 1 then
            --local data = slotToDamageTableCougar[slot]

            damageType = dmgTypes.Magical

            if slots == slots.Q then
                local qD = {5, 30, 55, 80}
                rawDamage = rawDamage + qD[spellLevel]
                rawDamage = rawDamage + (0.40 * Player.TotalAD)
                rawDamage = rawDamage + (0.75 * Player.TotalAP)
            elseif slots == slots.W then
                local wD = {60, 110, 160, 210}
                rawDamage = rawDamage + wD[spellLevel]
                rawDamage = rawDamage + (0.30 * Player.TotalAP)
            elseif slots == slots.E then
                local eD = {80, 140, 200, 260}
                rawDamage = rawDamage + eD[spellLevel]
                rawDamage = rawDamage + (0.45 * Player.TotalAP)
            end

            if damageType == dmgTypes.Physical then
                return DmgLib.CalculatePhysicalDamage(Player, target, rawDamage)
            elseif damageType == dmgTypes.Magical then
                return DmgLib.CalculateMagicalDamage(Player, target, rawDamage)
            else
                return rawDamage
            end
    end

    return 0
end

function Nidalee.SwitchForm()
    if Engine.CanCast(slots.R) then
        if spells.R:Cast() then
            return
        end
    end
    return false
end

function Nidalee.IsHuman()
    return Engine.GetAARange() >= 525
end

function Nidalee.CanHeal()
    if Nidalee.IsHuman() then
        return Engine.CanCast(slots.E)
    else
        if Nidalee.Human.E.LastCastT == nil or (Game.GetTime() - Nidalee.Human.E.LastCastT) >= Nidalee.Human.E.CD then
            return true
        end
    end
    return false
end

--  auto heal logic
function Nidalee.AutoHeal(LagFree)
    if Orbwalker.IsWindingUp() or LagFree == 1 or LagFree >= 4 then -- experimental lag free
        return
    end

    if Engine.GetMenu("misc.AutoHeal") and Nidalee.CanHeal() then
        -- self
        if Engine.GetPercentHealth(Player) <= Engine.GetMenu("misc.AutoHealSelf") then
            
            -- auto on turret
            if Engine.GetMenu("misc.AutoHealSelfTurret") and Nidalee.IsHuman() and Orbwalker.HasTurretTargetting(Player) and Engine.GetPercentHealth() < 90 then
                if Engine.CanCast(slots.E) then
                    if Nidalee.CastHumanE() then
                        return
                    end
                end
            end

            -- try to save self before you die
            if Engine.GetMenu("misc.AutoHealSelfSave") and Engine.GetPercentHealth() < 8 and Nidalee.CanHeal() then
                local target = spellsHuman.E:GetTarget()
                if target and target.IsValid and Engine.IsInRange(Player.Position, target.Position, 0, 300) then
                    if not Nidalee.IsHuman() and Engine.CanCast(slots.R) then
                        Nidalee.SwitchForm()
                        delay(25, function() 
                            if Nidalee.CastHumanE() then
                                return
                            end
                        end) 
                    elseif Nidalee.IsHuman() then
                        if Nidalee.CastHumanE() then
                            return
                        end
                    end
                end
            end
            
            -- default logic
            if Engine.GetMenu("misc.AutoHealSelfMana") < Engine.GetPercentMana(Player)  then
                -- switch to human
                if not Nidalee.IsHuman() and Player.Mana >= 70 then -- mana lvl needed
                    if Player:CountEnemiesInRange(spellsHuman.E.Range) <= 0 or not Orbwalker.GetMode() == "Combo" then
                        Nidalee.SwitchForm()
                        return
                    end
                end

                -- cast on self
                if Engine.CanCast(slots.E) then
                    Nidalee.CastHumanE()
                    return
                end
            end
        end
        
        -- ally
        if Engine.GetMenu("misc.AutoHealAlly") >= 1 then
            -- get lowest ally in range
            local ally = Engine.GetLowestAlly(spellsHuman.E.Range)
            if ally and Engine.GetPercentHealth(ally) <= Engine.GetMenu("misc.AutoHealAlly") then
                
                -- switch to human
                if Engine.GetMenu("misc.AutoHealAllySwitchForm") and not Nidalee.IsHuman() then
                    -- switch dont care if enemy is close
                    if Engine.GetMenu("misc.AutoHealAllySwitchFormEnemy") then
                        Nidalee.SwitchForm()
                        return

                    -- switch if no enemy close
                    elseif Player:CountEnemiesInRange(spellsHuman.Q.Range - 250) == 0 then
                        Nidalee.SwitchForm()
                        return 
                    end
                end

                -- cast on ally
                if Nidalee.IsHuman() and Engine.CanCast(slots.E) and Engine.GetMenu("misc.AutoHealAllyMana") < Engine.GetPercentMana(Player) then
                    Nidalee.CastHumanE(ally)
                    return       
                end
            end
        end
    end      
end

function Nidalee.CanSpear()
    if Nidalee.Human.Q.LastCastT == nil or (Game.GetTime() - Nidalee.Human.Q.LastCastT) >= Nidalee.Human.Q.CD then
        return true
    end
    return false
end

function Nidalee.ShouldSwitchToHuman()
    if not Nidalee.IsHuman() then
        if not Engine.CanCast(slots.Q) and not Engine.CanCast(slots.W) and not Engine.CanCast(slots.E) and Player.Mana >= 50 then
            if Nidalee.CanSpear() or Nidalee.CanHeal() and (Game.GetTime() - Nidalee.Cougar.W.LastCastT) >= 0.5 or Nidalee.Cougar.W.LastCastT == nil then
                return true
            end
        end

        if not Nidalee.Buffmanager.HuntedTarget and Player:CountEnemiesInRange(spellsHuman.Q.Range) >= 1 and Player:CountEnemiesInRange(275) <= 0 and Player.Mana >= 50  then
            if Nidalee.CanSpear() or Nidalee.CanHeal() and (Game.GetTime() - Nidalee.Cougar.W.LastCastT) >= 0.5 or Nidalee.Cougar.W.LastCastT == nil then
                return true
            end
        end
    end
    return false
end

function Nidalee.ShouldSwitchToCougar()
    if Nidalee.IsHuman() then
        if not Engine.CanCast(slots.Q) or Player.Mana < 35 then
            return true
        end
    end
    return false
end

local drawData = {
    {slot = slots.Q, id = "Q", displayText = "[Q] Javelin Toss / Takedown", range = spellsHuman.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Bushwhack / Pounce", range = spellsHuman.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Primal Surge / Swipe", range = spellsHuman.E.Range},
}

local drawDataAlt = {
    {slot = slots.Q, id = "Q", displayText = "[Q] Javelin Toss / Takedown", range = spellsCougar.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Bushwhack / Pounce", range = spellsCougar.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Primal Surge / Swipe", range = spellsCougar.E.Range},
}

function Nidalee.GetDrawData()
    if Nidalee.IsHuman() then
        return drawData
    else
        return drawDataAlt
    end
end

function Nidalee.UpdateSpells()
    if not Nidalee.IsHuman() then
        return
    end
    
    Nidalee.Human.Q.CD = Engine.GetSpellCooldown(slots.Q)
    Nidalee.Human.W.CD = Engine.GetSpellCooldown(slots.W)
    Nidalee.Human.E.CD = Engine.GetSpellCooldown(slots.E)
end

function Nidalee.CastHumanW(target)
    if Orbwalker.IsWindingUp() or not Nidalee.IsHuman() then return false end

    if Engine.CanCast(slots.W) then
        local target = target or spellsHuman.W:GetTarget()
        if target then
            return spellsHuman.W:Cast(target.ServerPos)
        end
    end
    
    return false
end

function Nidalee.CastCougarW(target)
    if Nidalee.IsHuman() or Orbwalker.IsWindingUp() then return false end
    
    if spells.R.LastCastT == nil or (Game.GetTime() - spells.R.LastCastT) <= 0.25 then -- delay to prevent casting as human and as cougar LOL
        return false
    end

    if not Player:IsFacing(target.Position, 180) then
        Orbwalker.Orbwalk(target.ServerPos)
    end
    
    return spellsCougar.W:Cast(target)
end

---
-- NIDALEE
---

function combatVariants.Combo(LagFree)
    -- human combo
    if Nidalee.IsHuman() and LagFree <= 2 then

        -- use q
        if Engine.GetMenu("combo.useHumanQ") and Engine.CanCast(slots.Q) and LagFree == 1 then -- experimental lagfree
            if Nidalee.CastHumanQ() then
                return
            end
        end

        -- use e 
        if Engine.GetMenu("combo.useHumanE") and Engine.CanCast(slots.Q) then
            if not Engine.CanCast(slots.Q) and not Engine.CanCast(slots.R) and Player:CountEnemiesInRange(Engine.GetAARange()) > 1 then
                if Engine.GetPercentMana() >= Engine.GetMenu("combo.useHumanEMana") and Engine.GetPercentHealth() >= Engine.GetMenu("useHumanEHealth") then
                    if Nidalee.CastHumanE() then
                        return
                    end
                end
            end
        end

        -- check for hunted
        if Nidalee.Buffmanager.HuntedTarget and Engine.CanCast(slots.R) and Player:IsFacing(Nidalee.Buffmanager.HuntedTarget, 120) then
            local range = 375
            if Engine.GetMenu("combo.useWifHunted") then
                range = 750
            end
            
            -- switch form
            if Nidalee.Buffmanager.HuntedTarget.IsValid and Engine.IsInRange(Player.Position, Nidalee.Buffmanager.HuntedTarget.Position, 0, range) then
                Nidalee.SwitchForm()
                return
            end
        end

        -- switch form
        if Nidalee.ShouldSwitchToCougar() and Engine.GetMenu("combo.autoR") then
            local target = spellsCougar.W:GetTarget()

            if target and Engine.IsInRange(Player.Position, target.Position, 0, 375) then
                Nidalee.SwitchForm()
                return
            end
        end

    -- cougar combo
    elseif LagFree <= 3 and not Nidalee.IsHuman() then
        
        -- w combo
        if Engine.CanCast(slots.W) and Engine.GetMenu("combo.useCougarW") and LagFree <= 2 then -- experimental lagfree
            local target = Nidalee.Buffmanager.HuntedTarget or spellsCougar.W:GetTarget()

            if target and target.IsValid and Engine.GetMenu("combo.useWifHunted") and Evade.IsPointSafe(target.Position) and Player:IsFacing(target, 120) then
                Nidalee.CastCougarW(target)
                return
            elseif target and target.IsValid and Engine.IsInRange(Player.Position, target.Position, 0, 375) and Evade.IsPointSafe(target.Position) and Player:IsFacing(target, 120) then
                Nidalee.CastCougarW(target.ServerPos)
                return
            end
        end

        -- q combo
        if Engine.CanCast(slots.Q) and Engine.GetMenu("combo.useCougarQ") then
            local target = spellsCougar.Q:GetTarget()
            
            if target and target.IsValid then
                spellsCougar.Q:Cast(nil)
                return
            end
        end

        -- cast e
        if Engine.CanCast(slots.E) and Engine.GetMenu("combo.useCougarE") then
            local target = spellsCougar.E:GetTarget()
            
            if target and target.IsValid then
                spellsCougar.E:Cast(target.Position)
                return
            end
        end

        -- should switch form
        if Nidalee.ShouldSwitchToHuman() and Engine.GetMenu("combo.autoR") then
            local target = spellsHuman.Q:GetTarget()

            if target and target.IsValid then
                Nidalee.SwitchForm()
                return
            end
        end
    end
end

function combatVariants.Harass(LagFree)
    if LagFree >= 4 then return end

    local target = spellsCougar.W:GetTarget()
    if not target or not target.IsValid then return end

    if Nidalee.IsHuman() then
        -- use q
        if Engine.GetMenu("harass.useHumanQ") and Engine.CanCast(slots.Q) then
            if Nidalee.CastHumanQ() then
                return
            end
        end

        -- switch to cougar if close
        if Engine.CanCast(slots.R) and Engine.IsInRange(Player.Position, target.Position, 0, Engine.GetAARange()) and Engine.GetMenu("harass.SwitchForm") then
            Nidalee.SwitchForm()
            return
        end
    else
        -- use q
        if Engine.GetMenu("harass.useCougarQ") and Engine.CanCast(slots.Q) then
            if spellsCougar.Q:Cast() then
                return
            end
        -- use e
        elseif Engine.GetMenu("harass.useCougarE") and Engine.CanCast(slots.E) then
            if spellsCougar.E:Cast(target.Position) then
                return
            end   
        end

        -- gapclose w
        if Engine.GetMenu("harass.useCougarW") and Engine.CanCast(slots.W) and spellsCougar.WE:IsLeavingRange(target) and Player:IsFacing(target, 120) and Evade.IsPointSafe(target.Position) and not Engine.IsPosUnderTurret(target.Position) then
            if spellsCougar.W:Cast(target) then
                return
            end   
        end

        if Nidalee.ShouldSwitchToHuman() and Engine.GetMenu("harass.SwitchForm") then
            Nidalee.SwitchForm()
            return
        end
    end
end

function Nidalee.JnglClear()
    local targets = ObjManager.GetNearby("neutral", "minions")
    if Nidalee.IsHuman() then
        for i, obj in ipairs(targets) do
            if obj.IsValid and obj.MaxHealth > 6 then
                if Engine.CanCastSpell(slots.Q, "jngl.humanQ") and Engine.IsInRange(Player.Position, obj.Position, 10, spellsHuman.Q.Range) then
                    return Nidalee.CastHumanQ(obj)
                --w
                elseif Engine.CanCastSpell(slots.W, "jngl.humanW") and Engine.IsInRange(Player.Position, obj.Position, 0 , spellsHuman.W.Range) then
                    return spellsHuman.W:Cast(obj.Position)
                end
                -- r
                if Engine.CanCastSpell(slots.R, "jngl.SwitchForm") and Engine.IsInRange(Player.Position, obj.Position, 0 , 275) then
                    if not Engine.CanCast(slots.Q) and not Engine.CanCast(slots.W) or Player.Mana < 50 then
                        return Nidalee.SwitchForm()
                    end
                end
            end
        end
    else
        for i, obj in ipairs(targets) do
            if obj.IsValid and obj.MaxHealth > 6 then
                
                -- get w range
                local wRange = 275
                if Nidalee.Buffmanager.HuntedTarget then
                    wRange = 750
                end

                if Engine.CanCastSpell(slots.W, "jngl.cougarW") and Engine.IsInRange(Player.Position, obj.Position, 0 , wRange) then
                    return Nidalee.CastCougarW(obj)
                -- q
                elseif Engine.CanCastSpell(slots.Q, "jngl.cougarQ") and Engine.IsInRange(Player.Position, obj.Position, 0 , spellsCougar.Q.Range) then
                    if spellsCougar.Q:Cast() then
                        Orbwalker.Attack(obj)
                        return
                    end
                -- e                                                
                elseif Engine.CanCastSpell(slots.E, "jngl.cougarE") and Engine.IsInRange(Player.Position, obj.Position, 0 , spellsCougar.E.Range) then
                    return spellsCougar.E:Cast(obj.Position) 
                end
                -- r
                if Engine.CanCastSpell(slots.R, "jngl.SwitchForm") and Engine.IsInRange(Player.Position, obj.Position, 0 , spellsHuman.Q.Range) then
                    if not Engine.CanCast(slots.Q) and not Engine.CanCast(slots.W) and not Engine.CanCast(slots.E) and Player.Mana > 50 and Nidalee.CanSpear() then
                        return Nidalee.SwitchForm()
                    end
                end
            end
        end
    end
end
-- 

function combatVariants.Waveclear(LagFree)
    if Orbwalker.IsWindingUp() or LagFree >= 3 then return end
    
    Nidalee.JnglClear() -- needs to be improved
    -- lane clear will be added to in the future ;)
end

function combatVariants.Flee(LagFree)
    if LagFree >= 4 or Orbwalker.IsWindingUp() then return end
    
    Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

    if Nidalee.IsHuman() then
        if Engine.CanCast(slots.R) and Engine.GetMenu("flee.useCougarW") and Player:GetSpell(slots.W).IsLearned then
            Nidalee.SwitchForm() 
            return
        end
    else
        if Engine.CanCastSpell(slots.W, "flee.useCougarW") then
            return spellsCougar.W:Cast(Renderer.GetMousePos(nil))
        end
    end
end

function Nidalee.KillSteal(LagFree)
    if LagFree >= 3 or Orbwalker.IsWindingUp() then return end

    if Nidalee.IsHuman() then
        if Engine.CanCastSpell(slots.Q, "killsteal.HumanQ") and LagFree == 1 then
            local targets = spellsHuman.Q:GetTargets()
            for iKS, objKS in ipairs(targets) do
                local enemyHero = objKS.AsHero
                if enemyHero and enemyHero.IsValid then
                    local damage = Nidalee.GetHumanDamage(enemyHero, slots.Q)
                    local healthPred = spellsHuman.Q:GetHealthPred(objKS)
                    if healthPred > 0 and healthPred < floor(damage - 50) then
                        if Nidalee.CastHumanQ(enemyHero) then
                            return
                        end
                    end
                end
            end             
        end
    else
        if Engine.CanCastSpell(slots.E, "killsteal.CougarE") then        
            local targets = spellsCougar.E:GetTargets()
            for iKS, objKS in ipairs(targets) do
                local enemyHero = objKS.AsHero
                if enemyHero and enemyHero.IsValid then
                    local damage = Nidalee.GetCougarDamage(enemyHero, slots.E)
                    local healthPred = spellsHuman.E:GetHealthPred(objKS)
                    if healthPred > 0 and healthPred < floor(damage - 50) then
                        if spellsCougar.E:Cast(enemyHero.Position) then
                            return
                        end
                    end
                end
            end
        elseif Engine.CanCastSpell(slots.Q, "killsteal.CougarQ") then
            local targets = spellsHuman.Q:GetTargets()
            for iKS, objKS in ipairs(targets) do
                local enemyHero = objKS.AsHero
                if enemyHero and enemyHero.IsValid then
                    local damage = Nidalee.GetCougarDamage(enemyHero, slots.Q)
                    local healthPred = spellsHuman.Q:GetHealthPred(objKS)
                    if healthPred > 0 and healthPred < floor(damage - 50) then
                        if spellsCougar.Q:Cast() then
                            Orbwalker.Attack(enemyHero)
                            return
                        end
                    end
                end
            end                          
        elseif Engine.CanCastSpell(slots.W, "killsteal.CougarW") then
            local targets = spellsCougar.W:GetTargets()
            for iKS, objKS in ipairs(targets) do
                local enemyHero = objKS.AsHero
                if enemyHero and enemyHero.IsValid and Engine.IsInRange(Player.Position, enemyHero.Position, 0, 275) then
                    local damage = Nidalee.GetCougarDamage(enemyHero, slots.W)
                    local healthPred = spellsHuman.W:GetHealthPred(objKS)
                    if healthPred > 0 and healthPred < floor(damage - 50) then
                        if Nidalee.CastCougarW(enemyHero) then
                            return
                        end
                    end
                end
            end             
        end
    end
end

function events.OnCastSpell(data) -- Process, Slot, TargetPosition, TargetEndPosition, Target
    if data then
        if Nidalee.IsHuman() then
            if data.Slot == slots.Q then
                Nidalee.Human.Q.LastCastT = Game.GetTime()
            elseif data.Slot == slots.W then
                Nidalee.Human.W.LastCastT = Game.GetTime()
            elseif data.Slot == slots.E then
                Nidalee.Human.E.LastCastT = Game.GetTime() + 0.25
            end
        else
            if data.Slot == slots.W then
                Nidalee.Cougar.W.LastCastT = Game.GetTime()
            end
        end

        if data.Slot == slots.R then
            spells.R.LastCastT = Game.GetTime()
        end
    end
end

function events.OnTick(LagFree)
    if not Engine.ShouldRunScript() then
        return
    end

    local OrbwalkerState = Orbwalker.GetMode()

    if OrbwalkerState == "Combo" then
        combatVariants.Combo(LagFree)
    elseif OrbwalkerState == "Harass" then
        combatVariants.Harass(LagFree)
    elseif OrbwalkerState == "Waveclear" then
        combatVariants.Waveclear(LagFree)
    elseif OrbwalkerState == "Flee" then
        combatVariants.Flee(LagFree)
    end

    Nidalee.AutoHeal(LagFree)
    Nidalee.KillSteal(LagFree)

     if LagFree >= 3 then
        Nidalee.UpdateSpells() -- not the best solution
    end
end

function events.OnDraw()
    if Player.IsDead then
        return
    end

    local myPos = Player.Position

    for _, drawInfo in ipairs(Nidalee.GetDrawData()) do
        local slot = drawInfo.slot
        local id = drawInfo.id
        local range = drawInfo.range

        if type(range) == "function" then
            range = range()
        end

        if not Engine.GetMenu("draw.alwaysDraw") then
            if Engine.CanCastSpell(slot, "draw." .. id) then
                Renderer.DrawCircle3D(myPos, range, 30, 2, Engine.GetMenu("draw." .. id .. ".color"))
            end
        else
            if Player:GetSpell(slot).IsLearned then
                Renderer.DrawCircle3D(myPos, range, 30, 2, Engine.GetMenu("draw." .. id .. ".color"))
            end
        end
    end
end

function events.OnBuffGain(obj, buffInst)
    if not obj or not buffInst then return end

    if obj.IsEnemy and obj.IsValid then
        if buffInst.Name == "NidaleePassiveHunted" then
            Nidalee.Buffmanager.HuntedTarget = obj 
            Nidalee.Buffmanager.HuntedEndT = buffInst.EndTime
        end
    end
end

function events.OnBuffLost(obj, buffInst)
    if not obj or not buffInst then return end

    if obj.IsEnemy and obj.IsValid then
        if buffInst.Name == "NidaleePassiveHunted" then
            Nidalee.Buffmanager.HuntedTarget = nil
            Nidalee.Buffmanager.HuntedEndT = nil
        end
    end
end

function events.OnTeleport(obj, name, duration_secs, status)
    if not obj or obj.IsAlly then return end

    if not Nidalee.IsHuman() then
        return
    end

    -- cast auto human w
    if Engine.GetMenu("misc.AutoHumanW") and obj.IsValid and obj.IsEnemy and Engine.IsInRange(Player.Position, obj.Position, 0, spellsHuman.W.Range) then
        if Nidalee.CastHumanW(obj) then
            DEBUG("W OnTeleport")
            return
        end
    end

    -- cast auto human q
    if Engine.GetMenu("misc.AutoHumanQ") and obj.IsValid and obj.IsEnemy and Engine.IsInRange(Player.Position, obj.Position, 0, spellsHuman.Q.Range) then
        if Nidalee.CastHumanQ(obj) then
            DEBUG("Q OnTeleport")
            return
        end
    end
end

function events.OnInterruptibleSpell(Source, SpellCast, Danger, EndTime, CanMoveDuringChannel)
    if not Source or not Source.IsValid or Source.IsAlly or Source.Health <= 6 then return end
    
    if not Nidalee.IsHuman() then
        return
    end

    -- cast auto human w
    if Engine.GetMenu("misc.AutoHumanW") and not CanMoveDuringChannel and Engine.IsInRange(Player.Position, Source.Position, 0 , spellsHuman.W.Range) then 
        if Nidalee.CastHumanW(Source) then
            DEBUG("W OnInterruptibleSpell")
            return
        end
    end

    -- cast auto human q
    if Engine.GetMenu("misc.AutoHumanQ") and not CanMoveDuringChannel and Engine.IsInRange(Player.Position, Source.Position, 0 , spellsHuman.Q.Range) then 
        if Nidalee.CastHumanQ(Source) then
            DEBUG("Q OnInterruptibleSpell")
            return
        end
    end

end

function events.OnHeroImmobilized(Source, EndTime, IsStasis)
    if not Source or not Source.IsValid or Source.IsAlly or Source.Health <= 6 then return end
    
    if not Nidalee.IsHuman() then
        return
    end

    -- cast auto human w
    if Engine.GetMenu("misc.AutoHumanW") and IsStasis and Engine.IsInRange(Player.Position, Source.Position, 0 , spellsHuman.W.Range) then 
        if Nidalee.CastHumanW(Source) then
            DEBUG("W OnHeroImmobilized")
            return
        end
    end

    -- cast auto human q
    if Engine.GetMenu("misc.AutoHumanQ") and IsStasis and Engine.IsInRange(Player.Position, Source.Position, 0 , spellsHuman.Q.Range) then
        if Nidalee.CastHumanQ(Source) then
            DEBUG("Q OnHeroImmobilized")
            return
        end
    end
end

function Engine.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
            INFO("Registered event " .. eventName ..  ".")
        end
    end
end


function Engine.AddDrawMenu(data)
    for _, element in ipairs(data) do
        local id = element.id
        local displayText = element.displayText

        Menu.Checkbox(champName .. ".draw." .. id, "Draw " .. displayText .. " range", true)
        Menu.Indent(function()
            Menu.ColorPicker(champName .. ".draw." .. id .. ".color", "Color", scriptColor)
        end)
    end

    Menu.Checkbox("Nidalee.draw.alwaysDraw", "Always show spell range", true)
end

function Engine.LoadMenu()
    local function NidaleeMenu()

        -- header
        Menu.Text("", true)
        Menu.Separator()
        Menu.Text("FengshuiEngine for " .. champName ..  " loaded.", true)
        Menu.Text("Made by the_dude.", true)
        Menu.Text("This is a alpha release and still in WIP!", true)
        Menu.Separator()
        Menu.Text("", true)  

        -- combo
        Menu.Separator()
        Menu.NewTree("Nidalee.combo", "Combo settings", function()
            Menu.Checkbox("Nidalee.combo.autoR", "Enable R logic", true)   
            Menu.Separator()
            Menu.Text("Human form", true)
            Menu.Separator()
            Menu.Checkbox("Nidalee.combo.useHumanQ", "Use Human Q in combo", true)   
            Menu.Checkbox("Nidalee.combo.useHumanE", "Use Human E after form switch", true) 
            Menu.Text("Use if self have x Health", true)
            Menu.Slider("Nidalee.combo.useHumanEHealth", "%", 65, 0, 100, 1)
            Menu.Text("Use if have x mana left", true)
            Menu.Slider("Nidalee.combo.useHumanEMana", "%", 35, 0, 100, 1)
            Menu.Separator()
            Menu.Text("Cougar form", true)
            Menu.Separator()
            Menu.Checkbox("Nidalee.combo.useCougarQ", "Use Q", true)  
            Menu.Checkbox("Nidalee.combo.useCougarW", "Use W", true)  
            Menu.Checkbox("Nidalee.combo.useWifHunted", "Use W extended if Hunted", true)   
            Menu.Checkbox("Nidalee.combo.useCougarE", "Use E", true)
        end)

        -- harass
        Menu.Separator()
        Menu.NewTree("Nidalee.harass", "Harass settings", function()
            Menu.Checkbox("Nidalee.harass.useHumanQ", "Use human Q", true)
            Menu.Checkbox("Nidalee.harass.useCougarQ", "Use cougar Q", true)  
            Menu.Checkbox("Nidalee.harass.useCougarW", "Use cougar W", true)
            Menu.Checkbox("Nidalee.harass.useCougarE", "Use cougar E", true)  
            Menu.Checkbox("Nidalee.harass.SwitchForm", "Switch form in harass (R)", true)  
        end)

        
        -- clear
        Menu.Separator()
        Menu.NewTree("Nidalee.jngl", "Clear settings", function()
            Menu.Checkbox("Nidalee.jngl.SwitchForm", "Switch form in jngl clear (R)", true)  
            Menu.Text("Human jungle settings")
            Menu.Checkbox("Nidalee.jngl.humanQ", "Use human Q", true)
            Menu.Checkbox("Nidalee.jngl.humanW", "Use human W", true)
            Menu.Text("Cougar jungle settings")
            Menu.Checkbox("Nidalee.jngl.cougarQ", "Use cougar Q", true)  
            Menu.Checkbox("Nidalee.jngl.cougarW", "Use cougar W", true)
            Menu.Checkbox("Nidalee.jngl.cougarE", "Use cougar E", true)  
        end)

        -- KillSteal
        Menu.Separator()
        Menu.NewTree("Nidalee.killsteal", "Killsteal settings", function()
            Menu.Checkbox("Nidalee.killsteal.HumanQ", "Use human Q", true)
            Menu.Checkbox("Nidalee.killsteal.CougarQ", "Use cougar Q", true)  
            Menu.Checkbox("Nidalee.killsteal.CougarW", "Use cougar W", true)
            Menu.Checkbox("Nidalee.killsteal.CougarE", "Use cougar E", true)  
        end)

        -- flee
        Menu.Separator()
        Menu.NewTree("Nidalee.flee", "Flee settings", function()
            Menu.Checkbox("Nidalee.flee.useCougarW", "Flee with cougar W", true)   
        end)

        -- misc
        Menu.Separator()
        Menu.NewTree("Nidalee.misc", "Misc settings", function()
            Menu.Separator()
            Menu.Text("Global options", true)
            Menu.Checkbox("Nidalee.misc.AutoHumanQ", "Enable auto human Q", true)  
            Menu.Checkbox("Nidalee.misc.AutoHumanW", "Enable auto human W", true)   
            Menu.Checkbox("Nidalee.misc.AutoHeal", "Enable autoheal logic (human E)", true)   
            Menu.Separator()
            
            Menu.Text("Autoheal self options", true)
            Menu.Text("Heal self at X Health", true)
            Menu.Checkbox("Nidalee.misc.AutoHealSelfTurret", "On turret targeting", true) 
            Menu.Checkbox("Nidalee.misc.AutoHealSelfSave", "Try to heal before you die", true)  
            Menu.Slider("Nidalee.misc.AutoHealSelf", "% health", 50, 0, 100, 1)
            Menu.Slider("Nidalee.misc.AutoHealSelfMana", "% mana", 30, 0, 100, 1)

            Menu.Separator()
            Menu.Text("Autoheal ally options", true)
            Menu.Slider("Nidalee.misc.AutoHealAlly", "% health", 20, 0, 100, 1)
            Menu.Slider("Nidalee.misc.AutoHealAllyMana", "% mana", 35, 0, 100, 1)
            Menu.Checkbox("Nidalee.misc.AutoHealAllySwitchForm", "Switch form to heal ally", true)
            Menu.Checkbox("Nidalee.misc.AutoHealAllySwitchFormEnemy", "Switch form for ally if enemy is close", false)
        end)

        -- hitchance
        Menu.Separator()
        Menu.NewTree("Nidalee.hitchance", "Hitchance settings", function()
            Menu.Text("Human Q hitchance", true)
            Menu.Slider("Nidalee.hitchance.humanQ", "%", 20, 1, 100, 1)
        end)

        -- draw
        Menu.Separator()
        Menu.NewTree("Nidalee.draw", "Draw Settings", function()
            Engine.AddDrawMenu(Nidalee.GetDrawData())
        end)
    end
    INFO("Loaded Fengshui Menu.")
    Menu.RegisterMenu(scriptName, scriptName, NidaleeMenu)
end

function OnLoad()
    Engine.LoadMenu()
    Engine.RegisterEvents()
    INFO("Successfully loaded FengshuiNidalee.")
    return true
end
