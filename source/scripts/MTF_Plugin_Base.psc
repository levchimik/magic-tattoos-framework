Scriptname MTF_Plugin_Base extends MTF_Plugin
{Built-in conditions and effects. Metadata is JSON-driven via the base class.}

; ── Metadata catalog ────────────────────────────────────────────────────────
; All Get* metadata getters (33 conditions, 36 effects, every menu and paramN
; field) used to live as ~566-elseif chains here. They now read from
; Data/SKSE/Plugins/StorageUtilData/MagicTattoosFramework/plugins/mtf.base.json
; via the JsonUtil-driven defaults in MTF_Plugin. The JSON is built from
; tools/build_base_catalog.py — edit that script (not the JSON by hand) when
; you add or change a condition/effect, then re-run it.
;
; What stays in Papyrus, and why:
;   • GetPluginId — the base class reads it to derive the catalog path.
;   • checkCondition (and its scan/check helpers) — runs at slot-eval time
;     and reads live engine state; pure data couldn't capture it.
;   • checkCondition / onActivate / onDeactivate / onTick — dispatch into
;     the per-effect behaviour, keyed on the catalog id string (cid/eid).
;     The category-dispatch predicates (_isAbsShift, _isToggle) are
;     prefix-matched on eid and live next to them; _avNameFor is keyed on
;     idx because it's only called from internal helpers that already have
;     idx in scope for storage keying.
;   • _apply* / _remove* / _recompute* / _tick* runtime helpers, spell+
;     keyword+faction property resolvers, shader and sound FormID resolvers.
;
; If you add an effect: extend tools/build_base_catalog.py, regenerate the
; JSON, then add the matching behaviour branch in onActivate (+ onDeactivate
; / onTick if applicable) keyed on `eid == "your.new.id"`, and any
; _avNameFor entry if the effect modifies an AV.

Spell  Property _costPenaltySpell        Auto Hidden
Spell  Property _fleshSpell               Auto Hidden
Spell  Property _waterBreathingSpell      Auto Hidden
Spell  Property _waterWalkingSpell        Auto Hidden
Spell  Property _resistFireSpell          Auto Hidden
Spell  Property _resistFrostSpell         Auto Hidden
Spell  Property _resistShockSpell         Auto Hidden
Spell  Property _resistMagicSpell         Auto Hidden
Spell  Property _resistDiseaseSpell       Auto Hidden
Spell  Property _resistPoisonSpell        Auto Hidden
Spell  Property _muffleSpell              Auto Hidden
Spell  Property _detectAllSpell           Auto Hidden
Spell  Property _slowTimeSpell            Auto Hidden
Spell  Property _flameCloakSpell          Auto Hidden
Spell  Property _flameCloakDmgSpell       Auto Hidden
Spell  Property _frostCloakSpell          Auto Hidden
Spell  Property _frostCloakDmgSpell       Auto Hidden
Spell  Property _lightningCloakSpell      Auto Hidden
Spell  Property _lightningCloakDmgSpell   Auto Hidden

; Override OnUpdate to handle (a) plugin registration (parent behavior) and
; (b) deferred cloak Cast(). Cast() engages the cloak archetype's periodic
; damage dispatch but freezes MCM if called from the MCM thread. Deferring
; via RegisterForSingleUpdate runs Cast on the Quest's update thread after
; MCM returns control to the user.
Event OnUpdate()
    _tryRegister()
    ; Drain the pending-Cast queue. Stored via StorageUtil FormLists (NOT
    ; script-level vars) because plain Papyrus vars added to a script after
    ; a save was made don't always attach to the saved instance — writes
    ; silently no-op. StorageUtil is independent of script-instance storage.
    int n = StorageUtil.FormListCount(self, "mtf.pendCast.spells")
    int actN = StorageUtil.FormListCount(self, "mtf.pendCast.actors")
    if actN < n
        n = actN
    endif
    MTF_MainQuest hostDbg = _host()
    if n > 0 && hostDbg != None && hostDbg.DebugMode
        Debug.Notification("[MTF] queue drain: " + n + " spell(s)")
    endif
    Spell daSpell = _resolveDetectAllSpell()
    int i = 0
    while i < n
        Spell s = StorageUtil.FormListGet(self, "mtf.pendCast.spells", i) as Spell
        Actor t = StorageUtil.FormListGet(self, "mtf.pendCast.actors", i) as Actor
        if s != None && t != None
            if s == daSpell
                ; DetectLife archetype runtime — the engine loop that scans
                ; actors within Magnitude feet and paints HitShader on each
                ; through walls — only engages via the full Cast() pipeline.
                ; DoCombatSpellApply applies the MGEF but the engine then
                ; falls back to "paint HitShader on the spell target" (the
                ; caster, for Self spells), so the player glows red and
                ; everyone else stays invisible. Cast() needs the caster to
                ; know the spell, so AddSpell first.
                if !t.HasSpell(s)
                    t.AddSpell(s, false)
                endif
                s.Cast(t, None)
            else
                ; DoCombatSpellApply applies the spell's magic effects directly,
                ; no animation, no MCM freeze, no AddSpell needed, no spellbook
                ; clutter. Unlike Spell.Cast() it doesn't require the caster to
                ; "know" the spell.
                t.DoCombatSpellApply(s, t)
            endif
        endif
        i += 1
    endwhile
    if n > 0
        StorageUtil.FormListClear(self, "mtf.pendCast.spells")
        StorageUtil.FormListClear(self, "mtf.pendCast.actors")
    endif
    ; Papyrus-driven cloak damage tick. The engine cloak archetype dispatches
    ; the inner damage SPL at a hardcoded short radius (~5-12 ft) that ignores
    ; SetNthEffectArea, so to support large user-configurable radii we
    ; dispatch the inner SPL ourselves on every active cloak.
    bool anyCloak = _cloakTickAll()
    if anyCloak
        RegisterForSingleUpdate(1.0)
    endif
EndEvent

; Returns true if at least one cloak is active and the tick scheduled work.
; Iterates the player AND every tracked actor — supports NPC-emitted cloaks
; (e.g. dungeon boss with weak large-radius AoE). Per-source distance check
; in _cloakTickOne keeps each cloak's reach independent.
bool Function _cloakTickAll()
    bool any = false
    Actor pl = Game.GetPlayer()
    if pl != None
        any = _cloakTickSubject(pl) || any
    endif
    MTF_MainQuest mq = _host()
    if mq != None
        int n = StorageUtil.FormListCount(mq, "mtf.tracked")
        int i = 0
        while i < n
            Actor a = StorageUtil.FormListGet(mq, "mtf.tracked", i) as Actor
            if a != None && a != pl
                any = _cloakTickSubject(a) || any
            endif
            i += 1
        endwhile
    endif
    return any
EndFunction

bool Function _cloakTickSubject(Actor src)
    bool any = false
    if StorageUtil.GetFloatValue(src, "mtf.shift.flameCloak.active", 0.0) > 0.5
        _cloakTickOne(src, _resolveFlameCloakDmgSpell(), "mtf.shift.flameCloak")
        any = true
    endif
    if StorageUtil.GetFloatValue(src, "mtf.shift.frostCloak.active", 0.0) > 0.5
        _cloakTickOne(src, _resolveFrostCloakDmgSpell(), "mtf.shift.frostCloak")
        any = true
    endif
    if StorageUtil.GetFloatValue(src, "mtf.shift.lightningCloak.active", 0.0) > 0.5
        _cloakTickOne(src, _resolveLightningCloakDmgSpell(), "mtf.shift.lightningCloak")
        any = true
    endif
    return any
EndFunction

; Per-cloak per-tick dispatch: refresh inner damage SPL magnitude from
; StorageUtil (in case slider changed mid-fight), then DoCombatSpellApply
; on every hostile alive actor within paramRadius feet of the source.
Function _cloakTickOne(Actor source, Spell inner, string key)
    if source == None || inner == None
        return
    endif
    float dmg = StorageUtil.GetFloatValue(source, key, 0.0)
    float radFt = StorageUtil.GetFloatValue(source, key + ".radius", 0.0)
    if dmg <= 0.0 || radFt <= 0.0
        return
    endif
    ; v0.2.6: Gate the PO3 actor scan on combat state. Cloaks only damage
    ; IsHostileToActor() targets, so an out-of-combat scan iterates then
    ; no-ops on every entry. The gate is also a cosmetic-log fix:
    ; PO3_SKSEFunctions.GetActorsByProcessingLevel(0) returns None when no
    ; high-process actors are loaded, and the typed-Actor[] local assignment
    ; logs "Cannot cast from None to Actor[]" (see memory note
    ; project_papyrus_array_none_cast_noise). IsInCombat covers ~all cases
    ; where a hostile target is actually nearby.
    if !source.IsInCombat()
        return
    endif
    inner.SetNthEffectMagnitude(0, dmg)
    float radUnits = radFt * 21.336
    Actor[] near = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    if near == None
        return
    endif
    int i = 0
    while i < near.Length
        Actor a = near[i]
        if a != None && a != source && !a.IsDead()
            if a.IsHostileToActor(source)
                if a.GetDistance(source) <= radUnits
                    source.DoCombatSpellApply(inner, a)
                endif
            endif
        endif
        i += 1
    endwhile
EndFunction

; Append a (spell, target) pair to the pending-Cast queue and schedule the
; OnUpdate that drains it. Use this anywhere you need to defer Spell.Cast
; off the MCM thread (Cast() blocks while the game is paused, freezing MCM).
Function _queueCast(Spell s, Actor t)
    if s == None || t == None
        return
    endif
    MTF_MainQuest hostDbg = _host()
    if hostDbg != None && hostDbg.DebugMode
        Debug.Notification("[MTF] queueCast spell")
    endif
    StorageUtil.FormListAdd(self, "mtf.pendCast.spells", s)
    StorageUtil.FormListAdd(self, "mtf.pendCast.actors", t)
    RegisterForSingleUpdate(0.1)
EndFunction

; Lazy-resolved location keywords (Skyrim.esm, no master needed).
Keyword Property _kwPlayerHouse Auto Hidden
Keyword Property _kwDungeon     Auto Hidden
Keyword Property _kwCity        Auto Hidden
Keyword Property _kwTown        Auto Hidden
Keyword Property _kwInn         Auto Hidden
Keyword Property _kwJail        Auto Hidden

; Lazy-resolved spells.
Spell Property _loversComfort Auto Hidden

; Lazy-resolved factions (vanilla Skyrim.esm).
Faction Property _facCurrentFollower  Auto Hidden
Faction Property _facThievesGuild     Auto Hidden
Faction Property _facDarkBrotherhood  Auto Hidden
Faction Property _facCompanionsCircle Auto Hidden

; Lazy-resolved keywords for magiceffect.kw.* and worn.* conditions.
Keyword Property _kwMgefFire        Auto Hidden
Keyword Property _kwMgefFrost       Auto Hidden
Keyword Property _kwMgefShock       Auto Hidden
Keyword Property _kwMgefInvisibility Auto Hidden
Keyword Property _kwArmorHeavy      Auto Hidden
Keyword Property _kwArmorLight      Auto Hidden

; Lazy-resolved races.
Race Property _raceWerewolf Auto Hidden

; Cached gold form (Skyrim.esm 0xF).
Form Property _goldForm Auto Hidden

; Location-keyword enum → Skyrim Location Keyword. Values 0..5 match
; LOCATION_KW_MENU in tools/build_base_catalog.py and location.kw's
; param1 dropdown. Caches each keyword on first resolve.
Keyword Function _locKwByIdx(int idx)
    if idx == 0
        if _kwPlayerHouse == None
            _kwPlayerHouse = Game.GetForm(0x0FC1A3) as Keyword
        endif
        return _kwPlayerHouse
    elseif idx == 1
        if _kwDungeon == None
            _kwDungeon = Game.GetForm(0x18EF1) as Keyword
        endif
        return _kwDungeon
    elseif idx == 2
        if _kwCity == None
            _kwCity = Game.GetForm(0x13167) as Keyword
        endif
        return _kwCity
    elseif idx == 3
        if _kwTown == None
            _kwTown = Game.GetForm(0x192BD) as Keyword
        endif
        return _kwTown
    elseif idx == 4
        if _kwInn == None
            _kwInn = Game.GetForm(0x1929F) as Keyword
        endif
        return _kwInn
    elseif idx == 5
        if _kwJail == None
            _kwJail = Game.GetForm(0x5254C) as Keyword
        endif
        return _kwJail
    endif
    return None
EndFunction

; Hit-class counter storage uses PapyrusUtil StorageUtil (see MainQuest).
; Auto Hidden array properties added post-release do not get attached to
; existing script instances — even on a "fresh new game" if any prior save
; touched the quest, indexed-property and whole-array writes silently no-op.
; StorageUtil persists in the cosave and sidesteps the OnInit-once trap.

float Function HIT_VISIBLE_SECONDS() global
    return 8.0
EndFunction

string Function GetPluginId()
    return "mtf.base"
EndFunction

; ── Conditions ──────────────────────────────────────────────────────────────
; Metadata (id/label/description/param) lives in mtf.base.json — see top-of-
; file header. Only the runtime evaluator stays here.
;
; _host() lifted to MTF_Plugin base class.

; Called by MTF_HitListener on each player OnHit event.
Function _onHit(int classIdx)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    h.IncHitCount(classIdx)
EndFunction
bool Function _checkSlot(Actor target, int slotMask, Keyword kw)
    Form f = target.GetWornForm(slotMask)
    return f != None && f.HasKeyword(kw)
EndFunction

bool Function _wornHasArmorKw(Actor target, Keyword kw)
    if target == None || kw == None
        return false
    endif
    if _checkSlot(target, 0x00000004, kw)
        return true
    endif
    if _checkSlot(target, 0x00000008, kw)
        return true
    endif
    if _checkSlot(target, 0x00000080, kw)
        return true
    endif
    if _checkSlot(target, 0x00001000, kw)
        return true
    endif
    if _checkSlot(target, 0x00000040, kw)
        return true
    endif
    if _checkSlot(target, 0x00000010, kw)
        return true
    endif
    return false
EndFunction

bool Function _scanNearbyFollower(Actor target, int paramMeters)
    float radius = (paramMeters as float) * 70.0
    if radius <= 0.0
        return false
    endif
    Actor[] nearby = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    if nearby == None
        return false
    endif
    int i = 0
    while i < nearby.Length
        Actor a = nearby[i]
        if a != None && a != target && !a.IsDead() && a.IsPlayerTeammate()
            if a.GetDistance(target) <= radius
                return true
            endif
        endif
        i += 1
    endwhile
    return false
EndFunction

float Function _avPercent(Actor target, string av)
    float maxV = target.GetActorValueMax(av)
    if maxV <= 0.0
        return -1.0
    endif
    return (target.GetActorValue(av) / maxV) * 100.0
EndFunction

bool Function _checkHit(int classIdx, int param)
    MTF_MainQuest h = _host()
    if h == None
        return false
    endif
    float now = Utility.GetCurrentRealTime()
    int cnt = h.GetHitCount(classIdx)
    int rolled = h.GetHitRolled(classIdx)
    if cnt > rolled
        h.SetHitRolled(classIdx, cnt)
        if Utility.RandomInt(1, 100) <= param
            h.SetHitArmedRT(classIdx, now + HIT_VISIBLE_SECONDS())
        endif
    endif
    return now < h.GetHitArmedRT(classIdx)
EndFunction

bool Function checkCondition(Actor target, int param, string cid)
    if target == None
        return false
    endif
    ; Dispatch by catalog id (cid) — robust against JSON reorder. Group
    ; ordering matters in one place: location.indoors/outdoors must come
    ; BEFORE the generic "location.*" prefix branch (otherwise the prefix
    ; branch swallows them with a kw lookup that misses).
    if cid == "magicka"
        float p = _avPercent(target, "Magicka")
        return p >= 0.0 && p >= param as float
    elseif cid == "magicka.below"
        float p = _avPercent(target, "Magicka")
        return p >= 0.0 && p <= param as float
    elseif cid == "stamina"
        float p = _avPercent(target, "Stamina")
        return p >= 0.0 && p >= param as float
    elseif cid == "stamina.below"
        float p = _avPercent(target, "Stamina")
        return p >= 0.0 && p <= param as float
    elseif cid == "combat.in"
        return target.IsInCombat()
    elseif cid == "combat.alerted"
        return _scanNearbyCombat(target, param)
    elseif cid == "combat.hostile"
        return _scanNearbyHostile(target, param)
    elseif cid == "combat.hit"
        ; param1 = hit class enum (0=Any, 1=Blunt, 2=Bladed, 3=Ranged,
        ; 4=Fire, 5=Frost, 6=Shock — values match _checkHit's classIdx
        ; AND host-side hit-counter storage keys). param2 = chance % per
        ; matching hit. Pre-v0.2.5 used 7 separate combat.hit.* conditions.
        int hitClass = param
        if hitClass < 0 || hitClass > 6
            return false
        endif
        return _checkHit(hitClass, _host().GetEvalParam2())
    elseif cid == "health"
        float p = _avPercent(target, "Health")
        return p >= 0.0 && p >= param as float
    elseif cid == "health.below"
        float p = _avPercent(target, "Health")
        return p >= 0.0 && p <= param as float
    elseif cid == "location.indoors"
        Cell c = target.GetParentCell()
        return c != None && c.IsInterior()
    elseif cid == "location.outdoors"
        Cell c = target.GetParentCell()
        return c != None && !c.IsInterior()
    elseif cid == "location.kw"
        ; param1 = location type enum (0=Player Home, 1=Dungeon, 2=City,
        ; 3=Town, 4=Inn, 5=Jail). Pre-v0.2.5 used 6 separate
        ; location.{playerHome,dungeon,city,town,inn,jail} conditions.
        Location loc = target.GetCurrentLocation()
        if loc == None
            return false
        endif
        Keyword kw = _locKwByIdx(param)
        if kw == None
            return false
        endif
        return loc.HasKeyword(kw)
    elseif cid == "weather"
        ; param1 = weather class (0=Pleasant, 1=Cloudy, 2=Rainy, 3=Snowy)
        ; — matches Weather.GetClassification. Pre-v0.2.5 used 4 separate
        ; weather.{pleasant,cloudy,rainy,snowy} conditions.
        Weather w = Weather.GetCurrentWeather()
        if w == None
            return false
        endif
        return w.GetClassification() == param
    elseif cid == "state.sprinting"
        return target.IsSprinting()
    elseif cid == "state.running"
        ; "Running" without the sprint state — distinct condition.
        return target.IsRunning() && !target.IsSprinting()
    elseif cid == "state.weaponDrawn"
        return target.IsWeaponDrawn()
    elseif cid == "state.loversEmbrace"
        if _loversComfort == None
            _loversComfort = Game.GetForm(0x000CDA1D) as Spell
        endif
        if _loversComfort == None
            return false
        endif
        return target.HasSpell(_loversComfort)
    elseif cid == "state.sneaking"
        return target.IsSneaking()
    elseif cid == "state.swimming"
        return target.IsSwimming()
    elseif cid == "state.mounted"
        return target.IsOnMount()
    elseif cid == "state.bleedingOut"
        return target.IsBleedingOut()
    elseif cid == "time.range"
        ; param=from hour, param2=till hour. Wraps if from > till.
        float t36 = Utility.GetCurrentGameTime()
        float h36 = (t36 - Math.Floor(t36)) * 24.0
        int fromH = param
        int tillH = _host().GetEvalParam2()
        if fromH == tillH
            return false
        elseif fromH < tillH
            return h36 >= fromH as float && h36 < tillH as float
        else
            ; Wrap-around (e.g. 22-6 = night)
            return h36 >= fromH as float || h36 < tillH as float
        endif
    elseif cid == "faction.playerFollower"
        if _facCurrentFollower == None
            _facCurrentFollower = Game.GetForm(0x0005C84D) as Faction
        endif
        return _facCurrentFollower != None && target.IsInFaction(_facCurrentFollower)
    elseif cid == "magiceffect.kw.fire"
        if _kwMgefFire == None
            _kwMgefFire = Game.GetForm(0x0001CEAD) as Keyword
        endif
        return _kwMgefFire != None && target.HasMagicEffectWithKeyword(_kwMgefFire)
    elseif cid == "magiceffect.kw.frost"
        if _kwMgefFrost == None
            _kwMgefFrost = Game.GetForm(0x0001CEAE) as Keyword
        endif
        return _kwMgefFrost != None && target.HasMagicEffectWithKeyword(_kwMgefFrost)
    elseif cid == "magiceffect.kw.shock"
        if _kwMgefShock == None
            _kwMgefShock = Game.GetForm(0x0001CEAF) as Keyword
        endif
        return _kwMgefShock != None && target.HasMagicEffectWithKeyword(_kwMgefShock)
    elseif cid == "magiceffect.kw.invisibility"
        ; Use the Invisibility actor value (set by ANY source — potion, spell,
        ; racial). HasMagicEffectWithKeyword(MagicInvisibility) misses some
        ; effects since not all invisibility-applying effects carry the keyword.
        return target.GetActorValue("Invisibility") > 0.0
    elseif cid == "followers.any"
        return _scanNearbyFollower(target, param)
    elseif cid == "gold.aboveThousand"
        if _goldForm == None
            _goldForm = Game.GetForm(0x0000000F)
        endif
        return _goldForm != None && target.GetItemCount(_goldForm) >= (param * 1000)
    elseif cid == "worn.heavyArmor"
        if _kwArmorHeavy == None
            _kwArmorHeavy = Game.GetForm(0x0006BBD2) as Keyword
        endif
        return _kwArmorHeavy != None && _wornHasArmorKw(target, _kwArmorHeavy)
    elseif cid == "worn.lightArmor"
        if _kwArmorLight == None
            _kwArmorLight = Game.GetForm(0x0006BBD3) as Keyword
        endif
        return _kwArmorLight != None && _wornHasArmorKw(target, _kwArmorLight)
    elseif cid == "combat.casting"
        ; Continuous "is the actor mid-cast" check. State is maintained by
        ; MTF_CastListener (animvar polling — see KB entry). Currently
        ; player-only because the listener is on the player alias; NPCs
        ; always read false here (StorageUtil default).
        MTF_MainQuest h = _host()
        return h != None && h.IsCasting(target)
    endif
    return false
EndFunction

bool Function _scanNearbyCombat(Actor target, int paramMeters)
    float radius = (paramMeters as float) * 70.0
    if radius <= 0.0
        return false
    endif
    Actor[] nearby = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    if nearby == None
        return false
    endif
    int i = 0
    while i < nearby.Length
        Actor a = nearby[i]
        if a != None && a != target && !a.IsDead()
            if a.GetCombatState() > 0
                if a.GetDistance(target) <= radius
                    return true
                endif
            endif
        endif
        i += 1
    endwhile
    return false
EndFunction

bool Function _scanNearbyHostile(Actor target, int paramMeters)
    float radius = (paramMeters as float) * 70.0
    if radius <= 0.0
        return false
    endif
    Actor[] nearby = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    if nearby == None
        return false
    endif
    int i = 0
    while i < nearby.Length
        Actor a = nearby[i]
        if a != None && a != target && !a.IsDead()
            if a.IsHostileToActor(target)
                if a.GetDistance(target) <= radius
                    return true
                endif
            endif
        endif
        i += 1
    endwhile
    return false
EndFunction
; Signed-convention classifiers. Positive param = buff, negative = penalty.
; Applied magnitudes stored in mtf.shift.<idx> on the target so
; deactivate/recompute can roll them back precisely.
bool Function _isAbsShift(string eid)
    ; Additive AV shifts — every per-AV "modify.*" effect except:
    ;   • modify.skill (consolidated; param1 picks skill, param2 the shift)
    ;   • modify.resist (consolidated; param1 picks resist, param2 the shift)
    ;   • the two float-mult ones (modify.attackDamage / modify.weaponSpeed)
    ;     are still abs-shift but with /100 scaling inside the helper
    ;     (handled by _isAbsShiftFloatMult).
    ; Prefix-matched on the catalog id so adding a new per-AV modify.*
    ; effect just works; runtime path picked by name, not JSON position.
    if eid == "modify.skill" || eid == "modify.resist"
        return false
    endif
    return StringUtil.Find(eid, "modify.") == 0
EndFunction

bool Function _isAbsShiftFloatMult(string eid)
    ; AttackDamageMult / WeaponSpeedMult: vanilla baseline 1.0, not 100.
    ; param is interpreted as percent-point shift so param=20 → +0.2 on the
    ; mult (= +20% damage / +20% swing speed). Same idea as vanilla
    ; "Smithing — Damage" perk which does ModActorValue(AttackDamageMult, 0.2).
    return eid == "modify.attackDamage" || eid == "modify.weaponSpeed"
EndFunction

bool Function _isToggle(string eid)
    return StringUtil.Find(eid, "toggle.") == 0
EndFunction

; eid → Skyrim AV name for the eid-keyed modify.* set. The 17 skill modifies
; (modify.<oneHanded..pickpocket>) and 6 resist modifies (modify.resist*) are
; NOT here — they were consolidated into modify.skill and modify.resist
; (v0.2.5) and route through _skillAVForIdx / _resolveResistSpellByIdx
; from explicit branches in onActivate.
string Function _avNameFor(string eid)
    if eid == "modify.magickaRegen"
        return "MagickaRateMult"
    elseif eid == "modify.carryWeight"
        return "CarryWeight"
    elseif eid == "modify.sneak"
        return "Sneak"
    elseif eid == "modify.movementSpeed"
        return "SpeedMult"
    elseif eid == "modify.staminaRegen"
        return "StaminaRateMult"
    elseif eid == "modify.attackDamage"
        return "AttackDamageMult"
    elseif eid == "modify.healthRegen"
        return "HealRateMult"
    elseif eid == "modify.maxMagicka"
        return "Magicka"
    elseif eid == "modify.maxStamina"
        return "Stamina"
    elseif eid == "modify.weaponSpeed"
        return "WeaponSpeedMult"
    elseif eid == "modify.unarmedDamage"
        return "UnarmedDamage"
    elseif eid == "modify.criticalChance"
        return "CriticalChance"
    elseif eid == "modify.bowSpeed"
        return "BowSpeedBonus"
    elseif eid == "modify.absorbChance"
        return "AbsorbChance"
    elseif eid == "modify.reflectDamage"
        return "ReflectDamage"
    ; Toggle AVs (used by _recomputeToggle for the non-spell-routed branch).
    elseif eid == "toggle.muffle"
        return "Muffled"
    elseif eid == "toggle.waterbreathing"
        return "WaterBreathing"
    elseif eid == "toggle.waterWalking"
        return "WaterWalking"
    endif
    return ""
EndFunction

; Per-actor applied state via StorageUtil. Keys: "mtf.shift.<eid>" (signed).
; Stores the SIGNED amount we applied via ModActorValue. Deactivate/recompute
; reverts by ModActorValue(av, -prev). Per-actor so NPC subjects don't thrash
; each other. (v0.2.4 switched key from idx → eid; older saves' "mtf.shift.<N>"
; entries are orphaned and harmless — the next session of activity on that
; effect just establishes the new key. Pre-v0.0.35 also used "mtf.applied.<idx>"
; with positive magnitude; those orphans are equally harmless.)
float Function _getApplied(string eid, Actor target)
    if target == None
        return 0.0
    endif
    return StorageUtil.GetFloatValue(target, "mtf.shift." + eid, 0.0)
EndFunction

Function _setApplied(string eid, Actor target, float v)
    if target == None
        return
    endif
    if v == 0.0
        StorageUtil.UnsetFloatValue(target, "mtf.shift." + eid)
    else
        StorageUtil.SetFloatValue(target, "mtf.shift." + eid, v)
    endif
EndFunction

; abs shift: signed `param` in AV points (no scaling, except _isAbsShiftFloatMult).
; Wrapper over _recomputeAbsShiftAV for eid-keyed effects (the per-AV
; modify.* set). Resist-routed and skill-routed effects bypass this and
; call _recomputeAbsShiftAV / _absShiftSpellByKey directly via the
; consolidated modify.skill / modify.resist branches in onActivate.
Function _recomputeAbsShift(string eid, Actor target, int param)
    if target == None
        return
    endif
    string av = _avNameFor(eid)
    if av == ""
        return
    endif
    _recomputeAbsShiftAV(av, eid, target, param, _isAbsShiftFloatMult(eid))
EndFunction

; toggle: bind/unbind sets AV ±1 (or AddSpell/RemoveSpell for engine-managed
; AVs like WaterBreathing/WaterWalking that don't respond to direct ModAV).
; `param` is ignored; `on` = activate.
Function _recomputeToggle(string eid, Actor target, bool on)
    if target == None
        return
    endif
    ; Engine-managed AVs need an ability spell (constant-effect ability).
    ; Direct ModActorValue silently no-ops on Muffled/WaterBreathing/WaterWalking.
    if eid == "toggle.muffle"
        _toggleSpell(_resolveMuffleSpell(), target, on, eid)
        return
    elseif eid == "toggle.waterbreathing"
        _toggleSpell(_resolveWaterBreathingSpell(), target, on, eid)
        return
    elseif eid == "toggle.waterWalking"
        _toggleSpell(_resolveWaterWalkingSpell(), target, on, eid)
        return
    endif
    string av = _avNameFor(eid)
    if av == ""
        return
    endif
    float prev = _getApplied(eid, target)
    if on
        if prev > 0.0
            return ; already applied
        endif
        if prev < 0.0
            target.ModActorValue(av, -prev)
        endif
        target.ModActorValue(av, 1.0)
        _setApplied(eid, target, 1.0)
    else
        if prev != 0.0
            target.ModActorValue(av, -prev)
        endif
        _setApplied(eid, target, 0.0)
    endif
EndFunction

Function _toggleSpell(Spell s, Actor target, bool on, string eid)
    if s == None
        return
    endif
    float prev = _getApplied(eid, target)
    if on
        if prev > 0.0
            return ; already applied
        endif
        target.AddSpell(s, false)
        _setApplied(eid, target, 1.0)
    else
        target.RemoveSpell(s)
        _setApplied(eid, target, 0.0)
    endif
EndFunction

Spell Function _resolveWaterBreathingSpell()
    if _waterBreathingSpell == None
        _waterBreathingSpell = Game.GetFormFromFile(0x833, "MagicTattoosFramework.esp") as Spell
    endif
    return _waterBreathingSpell
EndFunction

Spell Function _resolveWaterWalkingSpell()
    if _waterWalkingSpell == None
        _waterWalkingSpell = Game.GetFormFromFile(0x835, "MagicTattoosFramework.esp") as Spell
    endif
    return _waterWalkingSpell
EndFunction

Spell Function _resolveMuffleSpell()
    if _muffleSpell == None
        _muffleSpell = Game.GetFormFromFile(0x83F, "MagicTattoosFramework.esp") as Spell
    endif
    return _muffleSpell
EndFunction

; one-shot burst: signed % of BASE AV. + → RestoreActorValue, - → Damage.
Function _burstDelta(string av, Actor target, int param)
    if target == None || param == 0 || av == ""
        return
    endif
    float base = target.GetBaseActorValue(av)
    if base <= 0.0
        return
    endif
    float amt = base * param / 100.0
    if amt > 0.0
        target.RestoreActorValue(av, amt)
    else
        target.DamageActorValue(av, -amt)
    endif
EndFunction

; Apply a signed-magnitude resist via an Ability spell, keyed on an
; arbitrary storage key (not necessarily the eid). Used by both
; eid-keyed effects and the consolidated modify.resist (which uses
; "modify.resist.<typeIdx>" as the key so per-type stored deltas don't
; collide across resist types within one effect slot).
;
; Removes first to clear stale magnitude, mutates the spell's effect
; magnitude, then re-adds. Early-outs when the desired magnitude already
; matches what we last applied — without this, onTick's 10 Hz cadence
; does RemoveSpell+AddSpell every poll, which keeps lazy AVs like
; PoisonResist flickering 0/+N for ~2-3s before the engine settles.
Function _absShiftSpellByKey(Spell s, Actor target, int param, string key)
    if s == None
        return
    endif
    float prev = _getApplied(key, target)
    float mag  = param as float
    if prev == mag
        return
    endif
    ; CRITICAL ORDER: write storage BEFORE the suspending RemoveSpell /
    ; AddSpell calls so concurrent stacks see prev=mag and hit the early-out
    ; above. Same race as _recomputeAbsShift; see comment there for details.
    if param == 0
        _setApplied(key, target, 0.0)
    else
        _setApplied(key, target, mag)
    endif
    target.RemoveSpell(s)
    if param == 0
        return
    endif
    s.SetNthEffectMagnitude(0, mag)
    target.AddSpell(s, false)
EndFunction

; Resist type enum → Ability Spell. Values 0..5 match RESIST_TYPE_MENU
; in tools/build_base_catalog.py and modify.resist's param1 dropdown.
Spell Function _resolveResistSpellByIdx(int idx)
    if idx == 0
        if _resistFireSpell == None
            _resistFireSpell = Game.GetFormFromFile(0x837, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistFireSpell
    elseif idx == 1
        if _resistFrostSpell == None
            _resistFrostSpell = Game.GetFormFromFile(0x839, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistFrostSpell
    elseif idx == 2
        if _resistShockSpell == None
            _resistShockSpell = Game.GetFormFromFile(0x83B, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistShockSpell
    elseif idx == 3
        if _resistMagicSpell == None
            _resistMagicSpell = Game.GetFormFromFile(0x83D, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistMagicSpell
    elseif idx == 4
        if _resistDiseaseSpell == None
            _resistDiseaseSpell = Game.GetFormFromFile(0x851, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistDiseaseSpell
    elseif idx == 5
        if _resistPoisonSpell == None
            _resistPoisonSpell = Game.GetFormFromFile(0x853, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistPoisonSpell
    endif
    return None
EndFunction

; Skill enum → Skyrim AV name. Values 0..16 match SKILL_AV_MENU in
; tools/build_base_catalog.py and modify.skill's param1 dropdown.
; Same AV naming quirks as _avNameFor (Marksman = Archery, Speechcraft
; = Speech — both Morrowind holdovers).
string Function _skillAVForIdx(int idx)
    if idx == 0
        return "OneHanded"
    elseif idx == 1
        return "TwoHanded"
    elseif idx == 2
        return "Marksman"
    elseif idx == 3
        return "Block"
    elseif idx == 4
        return "HeavyArmor"
    elseif idx == 5
        return "LightArmor"
    elseif idx == 6
        return "Smithing"
    elseif idx == 7
        return "Enchanting"
    elseif idx == 8
        return "Alchemy"
    elseif idx == 9
        return "Destruction"
    elseif idx == 10
        return "Restoration"
    elseif idx == 11
        return "Alteration"
    elseif idx == 12
        return "Illusion"
    elseif idx == 13
        return "Conjuration"
    elseif idx == 14
        return "Speechcraft"
    elseif idx == 15
        return "Lockpicking"
    elseif idx == 16
        return "Pickpocket"
    endif
    return ""
EndFunction

; AV-keyed variant of _recomputeAbsShift. Caller supplies the AV name and
; storage key directly (no eid lookup). Used by the consolidated
; modify.skill effect — each skill enum needs its own storage key so
; per-skill deltas don't collide when the user changes the dropdown.
Function _recomputeAbsShiftAV(string av, string key, Actor target, int param, bool isFloatMult)
    if target == None || av == ""
        return
    endif
    float prev = _getApplied(key, target)
    float amt  = param as float
    if isFloatMult
        amt = amt / 100.0
    endif
    if prev == amt
        return
    endif
    if param == 0
        _setApplied(key, target, 0.0)
    else
        _setApplied(key, target, amt)
    endif
    if prev != 0.0
        target.ModActorValue(av, -prev)
    endif
    if param == 0
        return
    endif
    target.ModActorValue(av, amt)
EndFunction

; Consolidated modify.skill / modify.resist apply.
;
; Both effects put the TYPE on param1 (dropdown) and the SHIFT on param2.
; Per-skill / per-resist independent storage keys
; (`mtf.shift.modify.skill.<idx>`, `mtf.shift.modify.resist.<idx>`) keep
; deltas independent when slot bindings differ.
;
; Per-(slot, eff) `lastApplied` tracker stores which type enum was active
; on this slot last tick. When the user moves the param1 dropdown from
; Smithing→Alteration (or Fire→Frost), the old enum's stored delta is
; reverted before the new one is applied — otherwise the previous AV
; would stay buffed silently.
Function _recomputeSkillShift(Actor target, int currentSkill, int delta)
    if target == None || currentSkill < 0 || currentSkill > 16
        return
    endif
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot = h._getDispatchSlot()
    int eff  = h._getDispatchEffectIdx()
    if slot < 0 || eff < 0
        return
    endif
    string lastKey = "mtf.skill.last." + slot + "." + eff
    int prevSkill = StorageUtil.GetIntValue(target, lastKey, -1)
    if prevSkill >= 0 && prevSkill != currentSkill
        string prevAv = _skillAVForIdx(prevSkill)
        if prevAv != ""
            _recomputeAbsShiftAV(prevAv, "modify.skill." + prevSkill, target, 0, false)
        endif
    endif
    StorageUtil.SetIntValue(target, lastKey, currentSkill)
    string av = _skillAVForIdx(currentSkill)
    _recomputeAbsShiftAV(av, "modify.skill." + currentSkill, target, delta, false)
EndFunction

Function _removeSkillShift(Actor target)
    if target == None
        return
    endif
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot = h._getDispatchSlot()
    int eff  = h._getDispatchEffectIdx()
    if slot < 0 || eff < 0
        return
    endif
    string lastKey = "mtf.skill.last." + slot + "." + eff
    int prevSkill = StorageUtil.GetIntValue(target, lastKey, -1)
    if prevSkill >= 0
        string prevAv = _skillAVForIdx(prevSkill)
        if prevAv != ""
            _recomputeAbsShiftAV(prevAv, "modify.skill." + prevSkill, target, 0, false)
        endif
        StorageUtil.UnsetIntValue(target, lastKey)
    endif
EndFunction

Function _recomputeResistShift(Actor target, int currentResist, int delta)
    if target == None || currentResist < 0 || currentResist > 5
        return
    endif
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot = h._getDispatchSlot()
    int eff  = h._getDispatchEffectIdx()
    if slot < 0 || eff < 0
        return
    endif
    string lastKey = "mtf.resist.last." + slot + "." + eff
    int prevResist = StorageUtil.GetIntValue(target, lastKey, -1)
    if prevResist >= 0 && prevResist != currentResist
        Spell prevSpell = _resolveResistSpellByIdx(prevResist)
        if prevSpell != None
            _absShiftSpellByKey(prevSpell, target, 0, "modify.resist." + prevResist)
        endif
    endif
    StorageUtil.SetIntValue(target, lastKey, currentResist)
    Spell s = _resolveResistSpellByIdx(currentResist)
    if s != None
        _absShiftSpellByKey(s, target, delta, "modify.resist." + currentResist)
    endif
EndFunction

Function _removeResistShift(Actor target)
    if target == None
        return
    endif
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot = h._getDispatchSlot()
    int eff  = h._getDispatchEffectIdx()
    if slot < 0 || eff < 0
        return
    endif
    string lastKey = "mtf.resist.last." + slot + "." + eff
    int prevResist = StorageUtil.GetIntValue(target, lastKey, -1)
    if prevResist >= 0
        Spell prevSpell = _resolveResistSpellByIdx(prevResist)
        if prevSpell != None
            _absShiftSpellByKey(prevSpell, target, 0, "modify.resist." + prevResist)
        endif
        StorageUtil.UnsetIntValue(target, lastKey)
    endif
EndFunction

; one-shot bounty: add signed `param` gold to the crime faction of the hold
; the actor is currently in. Actor.GetCrimeFaction() is unreliable — it only
; returns the faction the actor last committed a crime against, which is
; None for a fresh player. Robust path: walk Location.ParentLocation up the
; chain until we find one with UnreportedCrimeFaction set (every hold's
; parent Location has this set to the hold's crime faction).
Function _modBounty(Actor target, int param)
    if target == None || param == 0
        return
    endif
    Faction f = _resolveCrimeFaction(target)
    if f == None
        f = target.GetCrimeFaction() ; fallback to last-committed
    endif
    if f == None
        return
    endif
    f.ModCrimeGold(param, false) ; non-violent bounty bucket
EndFunction

; Resolves the hold crime faction for the actor's current location. Papyrus
; doesn't expose Location.GetCrimeFaction(), so we iterate the 9 known hold
; Locations and use Actor.IsInLocation (which walks the parent chain). All
; FormIDs verified from Skyrim.esm.
Faction Function _resolveCrimeFaction(Actor target)
    if target == None
        return None
    endif
    Faction f
    f = _checkHold(target, 0x016772, 0x0267EA) ; Whiterun
    if f != None
        return f
    endif
    f = _checkHold(target, 0x01676A, 0x0267E3) ; Eastmarch
    if f != None
        return f
    endif
    f = _checkHold(target, 0x01676F, 0x028170) ; Falkreath
    if f != None
        return f
    endif
    f = _checkHold(target, 0x016770, 0x029DB0) ; Haafingar (Solitude)
    if f != None
        return f
    endif
    f = _checkHold(target, 0x01676E, 0x02816D) ; Hjaalmarch (Morthal)
    if f != None
        return f
    endif
    f = _checkHold(target, 0x01676D, 0x02816E) ; Pale (Dawnstar)
    if f != None
        return f
    endif
    f = _checkHold(target, 0x016769, 0x02816C) ; Reach (Markarth)
    if f != None
        return f
    endif
    f = _checkHold(target, 0x01676C, 0x02816B) ; Rift (Riften)
    if f != None
        return f
    endif
    f = _checkHold(target, 0x01676B, 0x02816F) ; Winterhold
    if f != None
        return f
    endif
    return None
EndFunction

Faction Function _checkHold(Actor target, int locFID, int factFID)
    Location loc = Game.GetFormFromFile(locFID, "Skyrim.esm") as Location
    if loc != None && target.IsInLocation(loc)
        return Game.GetFormFromFile(factFID, "Skyrim.esm") as Faction
    endif
    return None
EndFunction

Spell Function _resolveCostPenaltySpell()
    if _costPenaltySpell == None
        _costPenaltySpell = Game.GetFormFromFile(0x815, "MagicTattoosFramework.esp") as Spell
    endif
    return _costPenaltySpell
EndFunction

Function _applyCostPenalty(Actor target, int param)
    if target == None
        return
    endif
    Spell s = _resolveCostPenaltySpell()
    if s == None
        return
    endif
    ; `param` is the slider value: "spells cost N% of their original cost".
    ; Clamp 0..400 — below 0 would mean spells *refund* magicka (no);
    ; 100 is no change; up to 400 means a 4× penalty.
    if param < 0
        param = 0
    elseif param > 400
        param = 400
    endif
    ; Convert to engine magnitude: positive value on each school's `*Modifier`
    ; AV makes spells cheaper, negative makes them more expensive.
    ; So mag = (100 - param). param=100 → mag=0 (no change), param=0 → mag=+100
    ; (free), param=400 → mag=-300 (4× cost).
    float mag = (100 - param) as float
    ;
    ; SetNthEffectMagnitude does not affect already-added abilities;
    ; must remove → mutate → re-add. Also does not persist across save/load
    ; — onTick re-applies if applied magnitude drifts from current param.
    ;
    ; NOTE: SetNthEffectMagnitude mutates the *shared* spell form. If two
    ; actors have this effect with different params, the most recent
    ; activation's magnitude is what every actor's instance of the ability
    ; will use until re-applied. Per-actor `mtf.shift.spellcost` tracking
    ; keeps onTick stable per actor, but cross-actor magnitude conflicts are
    ; a known limitation (would need per-actor cloned spell forms to fix).
    target.RemoveSpell(s)
    int i = 0
    while i < 5
        s.SetNthEffectMagnitude(i, mag)
        i += 1
    endwhile
    target.AddSpell(s, false)
    StorageUtil.SetFloatValue(target, "mtf.shift.spellcost", mag)
EndFunction

Function _removeCostPenalty(Actor target)
    if target == None
        return
    endif
    Spell s = _resolveCostPenaltySpell()
    if s == None
        return
    endif
    target.RemoveSpell(s)
    StorageUtil.UnsetFloatValue(target, "mtf.shift.spellcost")
EndFunction

Spell Function _resolveFleshSpell()
    if _fleshSpell == None
        _fleshSpell = Game.GetFormFromFile(0x831, "MagicTattoosFramework.esp") as Spell
    endif
    return _fleshSpell
EndFunction

; Flesh: timed Fire-and-Forget self spell with ValueModifier on DamageResist.
; Constant-effect abilities can't write to DamageResist (the engine recomputes
; it from worn armor every frame); a timed spell sneaks in via the normal
; armor-stack pipeline. Magnitude = armor points. We re-cast on every onTick
; to refresh the 30s duration so the buff stays active while the tier is on.
Function _applyFlesh(Actor target, int param)
    if target == None
        return
    endif
    Spell s = _resolveFleshSpell()
    if s == None
        return
    endif
    float mag = param as float
    ; Constant-effect Ability + PeakValueModifier archetype (like vanilla
    ; Lord/Steed Stones). Abilities don't appear in the spell menu UI, and
    ; RemoveSpell cleanly dispels. For magnitude changes, RemoveSpell first
    ; to clear, then SetNthEffectMagnitude, then AddSpell to re-apply.
    target.RemoveSpell(s)
    s.SetNthEffectMagnitude(0, mag)
    target.AddSpell(s, false)
    StorageUtil.SetFloatValue(target, "mtf.shift.flesh", mag)
EndFunction

Function _removeFlesh(Actor target)
    if target == None
        return
    endif
    Spell s = _resolveFleshSpell()
    if s == None
        return
    endif
    target.RemoveSpell(s)
    StorageUtil.UnsetFloatValue(target, "mtf.shift.flesh")
    StorageUtil.UnsetFloatValue(target, "mtf.shift.flesh.cast")
EndFunction

; ── Detect All / Slow Time / Cloaks ──────────────────────────────────────────

Spell Function _resolveDetectAllSpell()
    if _detectAllSpell == None
        _detectAllSpell = Game.GetFormFromFile(0x841, "MagicTattoosFramework.esp") as Spell
    endif
    return _detectAllSpell
EndFunction

; Detect All: ability + ValueModifier on DetectLifeRange. Magnitude = radius
; in game units (param in feet × 21.336). Shows ALL nearby actors (alive +
; dead) through walls. Vanilla werewolf-vision pattern.
Function _applyDetectAll(Actor target, int paramFeet)
    if target == None
        return
    endif
    Spell s = _resolveDetectAllSpell()
    if s == None
        return
    endif
    ; DetectLife archetype is FAF + Duration like Aura Whisper. Magnitude is
    ; range in feet.
    float mag = paramFeet as float
    s.SetNthEffectMagnitude(0, mag)
    StorageUtil.SetFloatValue(target, "mtf.shift.detectAll", paramFeet as float)
    StorageUtil.SetFloatValue(target, "mtf.shift.detectAll.cast", Utility.GetCurrentRealTime())
    ; Dispel first so the periodic refresh produces a fresh 60s instance —
    ; without this, re-casting while the previous DetectLife is still active
    ; can be a no-op and the effect ends at original Duration.
    target.DispelSpell(s)
    ; Defer Cast via OnUpdate. Same MCM-thread-blocking issue as cloaks.
    _queueCast(s, target)
EndFunction

Function _removeDetectAll(Actor target)
    if target == None
        return
    endif
    Spell s = _resolveDetectAllSpell()
    if s == None
        return
    endif
    target.DispelSpell(s)
    target.RemoveSpell(s)
    StorageUtil.UnsetFloatValue(target, "mtf.shift.detectAll")
    StorageUtil.UnsetFloatValue(target, "mtf.shift.detectAll.cast")
EndFunction

Spell Function _resolveSlowTimeSpell()
    if _slowTimeSpell == None
        _slowTimeSpell = Game.GetFormFromFile(0x843, "MagicTattoosFramework.esp") as Spell
    endif
    return _slowTimeSpell
EndFunction

; Slow Time: FAF Self spell with SlowTime archetype, Duration 30. Refresh
; every ~25s via onTick. param = % time speed (lower = slower; vanilla shout
; uses 30 = 30% normal speed = 70% slowdown).
Function _applySlowTime(Actor target, int paramPercent)
    if target == None
        return
    endif
    Spell s = _resolveSlowTimeSpell()
    if s == None
        return
    endif
    float mag = (paramPercent as float) / 100.0
    if mag <= 0.0
        mag = 0.05
    endif
    s.SetNthEffectMagnitude(0, mag)
    StorageUtil.SetFloatValue(target, "mtf.shift.slowTime", paramPercent as float)
    StorageUtil.SetFloatValue(target, "mtf.shift.slowTime.cast", Utility.GetCurrentRealTime())
    ; SlowTime archetype ignores a re-cast while the previous instance is
    ; still ticking, so the periodic refresh would be a no-op and the effect
    ; would end at the original Duration. Dispel first to force a fresh
    ; engine instance with a full 30s duration.
    target.DispelSpell(s)
    ; Defer Cast via OnUpdate. Calling s.Cast() directly from MCM thread
    ; blocks the menu until exit; deferring runs Cast on the quest update
    ; thread instead.
    _queueCast(s, target)
EndFunction

Function _removeSlowTime(Actor target)
    if target == None
        return
    endif
    Spell s = _resolveSlowTimeSpell()
    if s == None
        return
    endif
    target.DispelSpell(s)
    StorageUtil.UnsetFloatValue(target, "mtf.shift.slowTime")
    StorageUtil.UnsetFloatValue(target, "mtf.shift.slowTime.cast")
EndFunction

Spell Function _resolveFlameCloakSpell()
    if _flameCloakSpell == None
        _flameCloakSpell = Game.GetFormFromFile(0x847, "MagicTattoosFramework.esp") as Spell
    endif
    return _flameCloakSpell
EndFunction
Spell Function _resolveFlameCloakDmgSpell()
    if _flameCloakDmgSpell == None
        _flameCloakDmgSpell = Game.GetFormFromFile(0x845, "MagicTattoosFramework.esp") as Spell
    endif
    return _flameCloakDmgSpell
EndFunction
Spell Function _resolveFrostCloakSpell()
    if _frostCloakSpell == None
        _frostCloakSpell = Game.GetFormFromFile(0x84B, "MagicTattoosFramework.esp") as Spell
    endif
    return _frostCloakSpell
EndFunction
Spell Function _resolveFrostCloakDmgSpell()
    if _frostCloakDmgSpell == None
        _frostCloakDmgSpell = Game.GetFormFromFile(0x849, "MagicTattoosFramework.esp") as Spell
    endif
    return _frostCloakDmgSpell
EndFunction
Spell Function _resolveLightningCloakSpell()
    if _lightningCloakSpell == None
        _lightningCloakSpell = Game.GetFormFromFile(0x84F, "MagicTattoosFramework.esp") as Spell
    endif
    return _lightningCloakSpell
EndFunction
Spell Function _resolveLightningCloakDmgSpell()
    if _lightningCloakDmgSpell == None
        _lightningCloakDmgSpell = Game.GetFormFromFile(0x84D, "MagicTattoosFramework.esp") as Spell
    endif
    return _lightningCloakDmgSpell
EndFunction

; Cloak: outer FAF Self spell with Cloak archetype + Association → inner
; damage spell. param = damage per second (mutates inner spell magnitude).
; param2 = radius in feet (mutates outer spell Area). 60s duration, refresh
; every ~50s via onTick.
Function _applyCloak(Spell outer, Spell inner, Actor target, int paramDmg, int paramRadius, string key)
    if target == None || outer == None || inner == None
        return
    endif
    ; Engine-managed cloak via deferred Cast(). Cloak archetype dispatches
    ; inner damage spell to all actors in radius. paramRadius is in CK feet;
    ; convert to game units (21.336 units/ft) and write to outer spell's
    ; effect Area via SetNthEffectArea. Magnitude on BOTH outer and inner —
    ; engine may read from either. Inner has Duration=0 for predictable
    ; instant per-tick damage.
    float mag = paramDmg as float
    inner.SetNthEffectMagnitude(0, mag)
    outer.SetNthEffectMagnitude(0, mag)
    int areaUnits = ((paramRadius as float) * 21.336) as int
    if areaUnits < 1
        areaUnits = 1
    endif
    outer.SetNthEffectArea(0, areaUnits)
    StorageUtil.SetFloatValue(target, key, mag)
    StorageUtil.SetFloatValue(target, key + ".radius", paramRadius as float)
    StorageUtil.SetFloatValue(target, key + ".active", 1.0)
    StorageUtil.SetFloatValue(target, key + ".cast", Utility.GetCurrentRealTime())
    ; Dispel any existing cloak instance so the engine re-reads area on
    ; recast; if we don't dispel, an active cloak may keep its cached radius.
    target.DispelSpell(outer)
    _queueCast(outer, target)
    ; Begin/continue Papyrus damage polling (OnUpdate → _cloakTickAll). The
    ; engine cloak still dispatches the inner SPL at its hardcoded short
    ; radius, so close-up actors may take overlapping hits — that's accepted.
    RegisterForSingleUpdate(1.0)
EndFunction

Function _removeCloak(Spell outer, Actor target, string key)
    if target == None || outer == None
        return
    endif
    target.DispelSpell(outer)
    StorageUtil.UnsetFloatValue(target, key)
    StorageUtil.UnsetFloatValue(target, key + ".radius")
    StorageUtil.UnsetFloatValue(target, key + ".active")
    StorageUtil.UnsetFloatValue(target, key + ".cast")
EndFunction

Function _tickCloak(Spell outer, Spell inner, Actor target, int paramDmg, int paramRadius, string key)
{`key` is the StorageUtil base key (e.g. "mtf.shift.flameCloak") — caller
 disambiguates between fire/frost/lightning. No idx/eid parameter needed:
 the storage namespace is fully encoded by the key string.}
    if target == None || outer == None
        return
    endif
    float storedDmg = StorageUtil.GetFloatValue(target, key, -1.0)
    float storedRad = StorageUtil.GetFloatValue(target, key + ".radius", -1.0)
    float lastCast = StorageUtil.GetFloatValue(target, key + ".cast", 0.0)
    float now = Utility.GetCurrentRealTime()
    float delta = now - lastCast
    ; Re-apply on slider change, on duration expiry approach (>50s of 60s),
    ; or on session restart (delta < 0 because GetCurrentRealTime resets).
    if storedDmg != (paramDmg as float) || storedRad != (paramRadius as float) || delta > 50.0 || delta < 0.0
        _applyCloak(outer, inner, target, paramDmg, paramRadius, key)
    endif
EndFunction

; ── Flash on Hit (v0.1.3 effect-binding) ────────────────────────────────────
; The flash.onhit effect (idx 34) configures the C++ pulse roster's additive
; emissive lane. param=classmask, param2=peak (% of 1.0 additive). The 3
; envelope timings (ramp/decay/retrig) live in extras keyed by the slot
; and effect index — host context comes from MainQuest's dispatch context
; setters (set by _activateSlotEffects et al before calling onActivate).
;
; The roster keys flash by (actor, base_slot) so at most one flash effect
; per slot drives the lane. Binding multiple flash.onhit rows to the same
; slot is allowed (no MCM block), but only one will end up in C++ — last
; activation wins on the same tick.

Function _applyFlashOnHit(Actor target, int classMask, int peakPct)
{`classMask` is the int param stored on the slot. v0.1.3 moved C++ flash
 dispatch from bitmask to string tags, but the MCM param stays int as a
 stable opaque preset ID — easier to author, easier to round-trip through
 JSON presets. _classMaskToTags maps the int to the tag CSV the C++ side
 wants.}
    if target == None
        return
    endif
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot      = h._getDispatchSlot()
    int effectIdx = h._getDispatchEffectIdx()
    if slot < 0 || effectIdx < 0
        ; Called outside a dispatch (e.g. direct invocation). Nothing to do.
        return
    endif
    ; param3/4/5 — flash.onhit envelope timings (was extras rampms/decayms/retrigms).
    int rampMs   = h.GetSlotEffectParamN(slot, effectIdx, 3)
    int decayMs  = h.GetSlotEffectParamN(slot, effectIdx, 4)
    int retrigMs = h.GetSlotEffectParamN(slot, effectIdx, 5)
    if rampMs   <= 0
        rampMs = 150
    endif
    if decayMs  <= 0
        decayMs = 500
    endif
    if retrigMs <= 0
        retrigMs = 800
    endif
    string tags = _classMaskToTags(classMask)
    ; Push flash params to the actor's actual base overlay slot — for
    ; the player single-preset path this equals h.OverlaySlot, but for
    ; NPCs and stacked player presets it's the per-preset base set by
    ; _evalAndDrawPresetForActor via _setDispatchBaseSlot. Using
    ; h.OverlaySlot blindly here was the v0.1.3 NPC-flash bug —
    ; SetActorFlash wrote to the wrong roster slot, the right slot's
    ; tags stayed empty, hits silently no-op'd.
    int dispatchBase = h._getDispatchBaseSlot()
    ; v0.1.17 Phase 3 (multi-area): area mirrors dispatch base — set in
    ; lockstep by the per-area iteration in _evalAndDrawPresetForActor.
    int dispatchArea = h._getDispatchArea()
    MTFPulse.SetActorFlash(target, dispatchBase, peakPct, rampMs, decayMs, retrigMs, tags, dispatchArea)
EndFunction

string Function _classMaskToTags(int classMask)
{Map the legacy int preset ID to the C++ string-tag CSV. Flat if/return —
 long elseIf chains in Quest-extending scripts silently return "" past
 the first branch on this VM build. Values keep the pre-v0.1.3 bit-pattern
 shape so presets authored against the old bitmask design still mean what
 they meant.}
    if classMask == 0
        return ""
    endif
    if classMask == 1
        return "*"
    endif
    if classMask == 2
        return "blunt"
    endif
    if classMask == 4
        return "bladed"
    endif
    if classMask == 8
        return "ranged"
    endif
    if classMask == 16
        return "fire"
    endif
    if classMask == 32
        return "frost"
    endif
    if classMask == 64
        return "shock"
    endif
    if classMask == 6
        return "blunt,bladed"
    endif
    if classMask == 14
        return "blunt,bladed,ranged"
    endif
    if classMask == 112
        return "fire,frost,shock"
    endif
    if classMask == 126
        return "blunt,bladed,ranged,fire,frost,shock"
    endif
    if classMask == 128
        ; v0.1.29: spell-cast trigger. Bit 7 (next free above the 0-6
        ; combat-class bitmask). MTF_CastListener dispatches the "cast"
        ; tag on cast start + every 0.1s while held.
        return "cast"
    endif
    ; Any unrecognised int → wildcard fallback so hand-edited presets with
    ; out-of-band values still flash on something rather than silently
    ; nothing. (Stricter alternative: return "" for unknown — but the user
    ; explicitly typed an int that meant "I want this to fire", so map to
    ; the safest match-everything option.)
    return "*"
EndFunction

Function _removeFlashOnHit(Actor target)
    if target == None
        return
    endif
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    MTFPulse.ClearActorFlash(target, h._getDispatchBaseSlot(), h._getDispatchArea())
EndFunction

Function _alertNearby(Actor target, int paramFeet)
    if target == None || paramFeet <= 0
        return
    endif
    ; 1 CK foot ≈ 21.336 game units (1 meter ≈ 70 units, 1m ≈ 3.281 ft)
    float radius = (paramFeet as float) * 21.336
    Actor[] nearby = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    if nearby == None
        return
    endif
    int i = 0
    while i < nearby.Length
        Actor a = nearby[i]
        if a != None && a != target && !a.IsDead()
            if a.IsHostileToActor(target)
                if a.GetDistance(target) <= radius
                    a.StartCombat(target)
                endif
            endif
        endif
        i += 1
    endwhile
EndFunction
int Function _shaderFormId(int idx)
    if idx == 0
        return 0x0002acd8  ; Fire Cloak
    endif
    if idx == 1
        return 0x0001b212  ; Fire Burst
    endif
    if idx == 2
        return 0x0001f03a  ; Frost
    endif
    if idx == 3
        return 0x0010a043  ; Frost Chillrend
    endif
    if idx == 4
        return 0x00057c67  ; Shock
    endif
    if idx == 5
        return 0x0003bf79  ; Shock Storm
    endif
    if idx == 6
        return 0x00094161  ; Stoneflesh
    endif
    if idx == 7
        return 0x00094162  ; Ebonyflesh
    endif
    if idx == 8
        return 0x000e9ac8  ; Dragonhide
    endif
    if idx == 9
        return 0x000506d7  ; Soul Trap
    endif
    if idx == 10
        return 0x0003b6cb  ; Ghost (Ethereal)
    endif
    if idx == 11
        return 0x000fe68c  ; Ghost Red
    endif
    if idx == 12
        return 0x0002df92  ; Invisibility
    endif
    if idx == 13
        return 0x000bcf25  ; Muffle
    endif
    if idx == 14
        return 0x0001c858  ; Ward Shield
    endif
    if idx == 15
        return 0x00075272  ; Reanimate
    endif
    if idx == 16
        return 0x000e7557  ; Turn Undead Flames
    endif
    if idx == 17
        return 0x00012fd9  ; Heal
    endif
    if idx == 18
        return 0x000abeff  ; Absorb Health
    endif
    if idx == 19
        return 0x000fd804  ; Vampire Change
    endif
    if idx == 20
        return 0x000ebec5  ; Werewolf Transform
    endif
    if idx == 21
        return 0x00000146  ; Detect Life
    endif
    return 0
EndFunction
EffectShader Function _resolveShader(int shaderIdx)
    int fid = _shaderFormId(shaderIdx)
    if fid == 0
        return None
    endif
    return Game.GetFormFromFile(fid, "Skyrim.esm") as EffectShader
EndFunction

Function _playShader(Actor target, int shaderIdx, int durationSec)
    if target == None
        return
    endif
    EffectShader es = _resolveShader(shaderIdx)
    if es == None
        return
    endif
    float dur = -1.0
    if durationSec > 0
        dur = durationSec as float
    endif
    es.Play(target, dur)
EndFunction

Function _stopShader(Actor target, int shaderIdx)
    if target == None
        return
    endif
    EffectShader es = _resolveShader(shaderIdx)
    if es == None
        return
    endif
    es.Stop(target)
EndFunction

; ── shader.play session-resume re-Play tracking ─────────────────────────────
; A short note on what's NOT here. Earlier iterations carried a Sound /
; SoundDescriptor catalog so each shader could play an auxiliary SNDR loop
; alongside the visual. In testing the "muted" preset was indistinguishable
; from the loud one: vanilla EffectShader records have their ambient audio
; baked into the visual itself (FireCloakFXShader brings the fire crackle,
; FrostCloakFXShader brings the freeze hiss). Sound.Play() can only ADD on
; top, never silence the base layer, so the toggle was UX-noise — removed.
; If a future need arises for an additive SNDR per row, the extras-dropdown
; API on MTF_Plugin is still in place; just wire it back up.
;
; What remains: a per-(baseSlot,slot,effectIdx) timestamp of the last
; EffectShader.Play call. _tickShaderRow uses it to detect session resume
; (GetCurrentRealTime resets to a small value on load) and re-Play the
; shader so the visual survives save/load — the engine doesn't persist
; EffectShader.Play state.
;
;   mtf.shaderFx.<baseSlot>.<slot>.<eff>.time  — last Play's real-time

string Function _shaderPlayKeyTime(int baseSlot, int slot, int eff)
    return "mtf.shaderFx." + baseSlot + "." + slot + "." + eff + ".time"
EndFunction

Function _activateShaderRow(Actor target, int shaderIdx, int durationSec)
    _playShader(target, shaderIdx, durationSec)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot      = h._getDispatchSlot()
    int eff       = h._getDispatchEffectIdx()
    int baseSlot  = h._getDispatchBaseSlot()
    if slot < 0 || eff < 0
        return
    endif
    ; Stamp the shader play time so onTick's session-resume check has a
    ; baseline. Without this, lastPlay reads 0 every tick and delta is huge
    ; positive → no re-Play; that's actually correct, but stamping makes the
    ; intent explicit and lets the negative-delta detector fire on load.
    StorageUtil.SetFloatValue(target, _shaderPlayKeyTime(baseSlot, slot, eff), Utility.GetCurrentRealTime())
EndFunction

Function _deactivateShaderRow(Actor target, int shaderIdx)
    _stopShader(target, shaderIdx)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot      = h._getDispatchSlot()
    int eff       = h._getDispatchEffectIdx()
    int baseSlot  = h._getDispatchBaseSlot()
    if slot < 0 || eff < 0
        return
    endif
    StorageUtil.UnsetFloatValue(target, _shaderPlayKeyTime(baseSlot, slot, eff))
EndFunction

Function _tickShaderRow(Actor target, int shaderIdx, int param2)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot      = h._getDispatchSlot()
    int eff       = h._getDispatchEffectIdx()
    int baseSlot  = h._getDispatchBaseSlot()
    if slot < 0 || eff < 0
        return
    endif
    ; Shader re-Play — STRICTLY session-resume only. EffectShader.Play stacks
    ; on the same target instead of replacing, so re-Playing every slow-tick
    ; piles up dozens of fire layers within seconds (visible as a bonfire,
    ; observed in testing). GetCurrentRealTime resets on load, so a negative
    ; delta from the stored stamp = stale; that's our only re-Play trigger.
    ; Finite-mode (param2 > 0) shaders are one-shot, never refreshed.
    if param2 > 0
        return
    endif
    float now = Utility.GetCurrentRealTime()
    float lastFxPlay = StorageUtil.GetFloatValue(target, _shaderPlayKeyTime(baseSlot, slot, eff), 0.0)
    if (now - lastFxPlay) < 0.0
        _playShader(target, shaderIdx, 0)
        StorageUtil.SetFloatValue(target, _shaderPlayKeyTime(baseSlot, slot, eff), now)
    endif
EndFunction
int Function _soundFormId(int idx)
    ; MTF_SND_* wrapper SOUN records in MagicTattoosFramework.esp. Each wraps
    ; a Skyrim.esm SNDR via SDSC (SoundDescriptor reference). The vanilla
    ; Papyrus `Sound` script type covers ONLY SOUN, not SNDR — SNDR records
    ; cast to None and Sound.Play silently no-ops on them. Hence the wrapper
    ; layer. See _resolveSound for the GetFormFromFile + cast pattern.
    if idx == 0
        return 0x900
    endif
    if idx == 1
        return 0x901
    endif
    if idx == 2
        return 0x902
    endif
    if idx == 3
        return 0x903
    endif
    if idx == 4
        return 0x904
    endif
    if idx == 5
        return 0x905
    endif
    if idx == 6
        return 0x906
    endif
    if idx == 7
        return 0x907
    endif
    if idx == 8
        return 0x908
    endif
    if idx == 9
        return 0x909
    endif
    if idx == 10
        return 0x90A
    endif
    if idx == 11
        return 0x90B
    endif
    if idx == 12
        return 0x90C
    endif
    if idx == 13
        return 0x90D
    endif
    if idx == 14
        return 0x90E
    endif
    if idx == 15
        return 0x90F
    endif
    if idx == 16
        return 0x910
    endif
    if idx == 17
        return 0x911
    endif
    if idx == 18
        return 0x912
    endif
    if idx == 19
        return 0x913
    endif
    if idx == 20
        return 0x914
    endif
    if idx == 21
        return 0x915
    endif
    if idx == 22
        return 0x916
    endif
    if idx == 23
        return 0x917
    endif
    if idx == 24
        return 0x918
    endif
    if idx == 25
        return 0x919
    endif
    if idx == 26
        return 0x91A
    endif
    if idx == 27
        return 0x91B
    endif
    if idx == 28
        return 0x91C
    endif
    if idx == 29
        return 0x91D
    endif
    if idx == 30
        return 0x91E
    endif
    if idx == 31
        return 0x91F
    endif
    if idx == 32
        return 0x920
    endif
    if idx == 33
        return 0x921
    endif
    return 0
EndFunction
Sound Function _resolveSound(int soundIdx)
    int fid = _soundFormId(soundIdx)
    if fid == 0
        return None
    endif
    return Game.GetFormFromFile(fid, "MagicTattoosFramework.esp") as Sound
EndFunction

string Function _soundFxKeyId(int baseSlot, int slot, int eff)
    return "mtf.soundFx." + baseSlot + "." + slot + "." + eff + ".id"
EndFunction

string Function _soundFxKeyTime(int baseSlot, int slot, int eff)
    return "mtf.soundFx." + baseSlot + "." + slot + "." + eff + ".time"
EndFunction

Function _stopSound(Actor target, int baseSlot, int slot, int eff)
    if target == None || slot < 0 || eff < 0
        return
    endif
    string keyId   = _soundFxKeyId(baseSlot, slot, eff)
    string keyTime = _soundFxKeyTime(baseSlot, slot, eff)
    int handle = StorageUtil.GetIntValue(target, keyId, -1)
    if handle > 0
        Sound.StopInstance(handle)
    endif
    StorageUtil.UnsetIntValue(target, keyId)
    StorageUtil.UnsetFloatValue(target, keyTime)
EndFunction

Function _playSoundLoop(Actor target, int baseSlot, int slot, int eff, int soundIdx)
    if target == None || slot < 0 || eff < 0
        return
    endif
    ; Stop any prior handle before re-Playing — overlapping handles stack
    ; on the same target and StopInstance only kills one.
    _stopSound(target, baseSlot, slot, eff)
    Sound s = _resolveSound(soundIdx)
    if s == None
        return
    endif
    int handle = s.Play(target)
    if handle <= 0
        return
    endif
    ; Apply per-row volume mixer (param3, 0..100 percent — was the legacy
    ; "volume" extra). sound.play's params: 1 = sound idx, 2 = duration,
    ; 3 = volume %.
    ; Default to 100 if missing so unconfigured rows still play at full volume.
    MTF_MainQuest h = _host()
    if h != None
        int volPct = h.GetSlotEffectParamN(slot, eff, 3)
        if volPct <= 0
            ; Either explicit 0 (mute) or unset (treat as 100 unless the user
            ; wrote 0). We can't tell unset apart from 0 cleanly via GetIntValue,
            ; but the populated default is 100, so any ≤0 here means either
            ; fresh-default-not-stamped or explicit mute. Either way, skip
            ; SetInstanceVolume — Play() already runs at the SNDR's intrinsic
            ; volume.
        else
            Sound.SetInstanceVolume(handle, (volPct as float) / 100.0)
        endif
    endif
    StorageUtil.SetIntValue(target,   _soundFxKeyId(baseSlot, slot, eff),   handle)
    StorageUtil.SetFloatValue(target, _soundFxKeyTime(baseSlot, slot, eff), Utility.GetCurrentRealTime())
EndFunction

Function _activateSoundRow(Actor target, int soundIdx, int param2)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot      = h._getDispatchSlot()
    int eff       = h._getDispatchEffectIdx()
    int baseSlot  = h._getDispatchBaseSlot()
    if slot < 0 || eff < 0
        return
    endif
    ; Always go through _playSoundLoop (which stops any prior handle first).
    ; param2 only affects onTick's session-resume policy, not whether we
    ; track the handle. Several "one-shot looking" SNDRs in the curated
    ; catalog are actually Loop-type sounds (Detect Life pulse, the
    ; concentration loops). Playing those as fire-and-forget would loop
    ; forever with no way to stop them. So we track ALL handles and stop
    ; ALL on deactivate; mode only changes session-resume behavior.
    _playSoundLoop(target, baseSlot, slot, eff, soundIdx)
EndFunction

Function _deactivateSoundRow(Actor target, int soundIdx, int param2)
    ; Always stop, regardless of mode. See _activateSoundRow comment for
    ; why one-shot still needs the cleanup path.
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot      = h._getDispatchSlot()
    int eff       = h._getDispatchEffectIdx()
    int baseSlot  = h._getDispatchBaseSlot()
    if slot < 0 || eff < 0
        return
    endif
    _stopSound(target, baseSlot, slot, eff)
EndFunction

Function _tickSoundRow(Actor target, int soundIdx, int param2)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot      = h._getDispatchSlot()
    int eff       = h._getDispatchEffectIdx()
    int baseSlot  = h._getDispatchBaseSlot()
    if slot < 0 || eff < 0
        return
    endif
    float now      = Utility.GetCurrentRealTime()
    float lastPlay = StorageUtil.GetFloatValue(target, _soundFxKeyTime(baseSlot, slot, eff), 0.0)
    float elapsed  = now - lastPlay
    ; Timed mode (param2 > 0): auto-stop once the requested duration elapses.
    ; Idempotent — _stopSound clears the keys so subsequent ticks see lastPlay
    ; = 0 and skip past this branch. (elapsed > 60 years for cleared keys
    ; because now stays positive while lastPlay is 0.)
    if param2 > 0 && lastPlay > 0.0 && elapsed >= (param2 as float)
        _stopSound(target, baseSlot, slot, eff)
        return
    endif
    ; Session resume re-Play, INFINITE mode only (param2 == 0). For timed
    ; sounds we don't restart on load — the user picked a finite duration,
    ; so the simplest semantic is "this stamp is dead after a load." If the
    ; tier is still active they can re-trigger by re-applying the preset.
    ; (Looped SNDRs self-continue while their handle is alive, so we don't
    ; stomp every tick even in infinite mode — only on session resume.)
    if elapsed < 0.0 && param2 == 0
        _playSoundLoop(target, baseSlot, slot, eff, soundIdx)
    endif
EndFunction

Function onActivate(Actor target, int param, int param2, string eid)
    ; Outer dispatch by `eid` — robust against JSON reorder. Inner helpers
    ; (_recomputeAbsShift, _setApplied, _avNameFor, etc.) also take eid so
    ; per-actor StorageUtil keys are stable across catalog edits.
    ;
    ; Consolidated effects come first: modify.skill / modify.resist read
    ; the type from param1 (dropdown) and the shift from param2, so they
    ; route through dedicated wrappers that handle per-slot lastApplied
    ; tracking (revert old type on dropdown change).
    if eid == "modify.skill"
        _recomputeSkillShift(target, param, param2)
    elseif eid == "modify.resist"
        _recomputeResistShift(target, param, param2)
    elseif _isAbsShift(eid)
        _recomputeAbsShift(eid, target, param)
    elseif _isToggle(eid)
        _recomputeToggle(eid, target, true)
    elseif eid == "damage.magicka"
        _burstDelta("Magicka", target, param)
    elseif eid == "damage.stamina"
        _burstDelta("Stamina", target, param)
    elseif eid == "burst.stagger"
        if target != None
            Debug.SendAnimationEvent(target, "staggerStart")
        endif
    elseif eid == "burst.blowCover"
        _alertNearby(target, param)
    elseif eid == "scale.magickaCost"
        _applyCostPenalty(target, param)
    elseif eid == "damage.health"
        _burstDelta("Health", target, param)
    elseif eid == "burst.bounty"
        _modBounty(target, param)
    elseif eid == "spell.modifyArmor"
        _applyFlesh(target, param)
    elseif eid == "spell.detectLife"
        _applyDetectAll(target, param)
    elseif eid == "spell.slowTime"
        _applySlowTime(target, param)
    elseif eid == "spell.flameCloak"
        _applyCloak(_resolveFlameCloakSpell(), _resolveFlameCloakDmgSpell(), target, param, param2, "mtf.shift.flameCloak")
    elseif eid == "spell.frostCloak"
        _applyCloak(_resolveFrostCloakSpell(), _resolveFrostCloakDmgSpell(), target, param, param2, "mtf.shift.frostCloak")
    elseif eid == "spell.lightningCloak"
        _applyCloak(_resolveLightningCloakSpell(), _resolveLightningCloakDmgSpell(), target, param, param2, "mtf.shift.lightningCloak")
    elseif eid == "flash.onhit"
        _applyFlashOnHit(target, param, param2)
    elseif eid == "shader.play"
        _activateShaderRow(target, param, param2)
    elseif eid == "sound.play"
        _activateSoundRow(target, param, param2)
    endif
EndFunction

Function onDeactivate(Actor target, int param, int param2, string eid)
    if eid == "modify.skill"
        _removeSkillShift(target)
    elseif eid == "modify.resist"
        _removeResistShift(target)
    elseif _isAbsShift(eid)
        _recomputeAbsShift(eid, target, 0)
    elseif _isToggle(eid)
        _recomputeToggle(eid, target, false)
    elseif eid == "scale.magickaCost"
        _removeCostPenalty(target)
    elseif eid == "spell.modifyArmor"
        _removeFlesh(target)
    elseif eid == "spell.detectLife"
        _removeDetectAll(target)
    elseif eid == "spell.slowTime"
        _removeSlowTime(target)
    elseif eid == "spell.flameCloak"
        _removeCloak(_resolveFlameCloakSpell(), target, "mtf.shift.flameCloak")
    elseif eid == "spell.frostCloak"
        _removeCloak(_resolveFrostCloakSpell(), target, "mtf.shift.frostCloak")
    elseif eid == "spell.lightningCloak"
        _removeCloak(_resolveLightningCloakSpell(), target, "mtf.shift.lightningCloak")
    elseif eid == "flash.onhit"
        _removeFlashOnHit(target)
    elseif eid == "shader.play"
        _deactivateShaderRow(target, param)
    elseif eid == "sound.play"
        _deactivateSoundRow(target, param, param2)
    endif
EndFunction

Function onTick(Actor target, int param, int param2, string eid)
    if eid == "modify.skill"
        _recomputeSkillShift(target, param, param2)
    elseif eid == "modify.resist"
        _recomputeResistShift(target, param, param2)
    elseif _isAbsShift(eid)
        _recomputeAbsShift(eid, target, param)
    elseif _isToggle(eid)
        _recomputeToggle(eid, target, true)
    elseif eid == "scale.magickaCost"
        ; Re-apply if param changed (slider) or after save/load (magnitude
        ; reverts to ESP default which is 0). Skip when already in sync.
        ; Storage tracks the engine magnitude (= 100 - param), so compare in
        ; that space — and apply the same clamp _applyCostPenalty uses so
        ; an out-of-range param doesn't loop here.
        float applied = StorageUtil.GetFloatValue(target, "mtf.shift.spellcost", 0.0)
        int  clamped = param
        if clamped < 0
            clamped = 0
        elseif clamped > 400
            clamped = 400
        endif
        float wantMag = (100 - clamped) as float
        if applied != wantMag
            _applyCostPenalty(target, clamped)
        endif
    elseif eid == "spell.modifyArmor"
        ; Constant-effect ability — no time-based refresh needed. Just
        ; re-apply if magnitude (param) changed since last application.
        float stored = StorageUtil.GetFloatValue(target, "mtf.shift.flesh", -99999.0)
        if stored != (param as float)
            _applyFlesh(target, param)
        endif
    elseif eid == "spell.detectLife"
        ; FAF DetectLife only scans actors at cast time — new actors entering
        ; the radius mid-duration don't get painted. Refresh on EVERY slow
        ; tick (≤2s) so newcomers get picked up. _applyDetectAll dispels
        ; first, so each call produces a fresh engine scan.
        float storedDA = StorageUtil.GetFloatValue(target, "mtf.shift.detectAll", -1.0)
        float lastCastDA = StorageUtil.GetFloatValue(target, "mtf.shift.detectAll.cast", 0.0)
        float nowDA = Utility.GetCurrentRealTime()
        float deltaDA = nowDA - lastCastDA
        if storedDA != (param as float) || deltaDA > 1.5 || deltaDA < 0.0
            _applyDetectAll(target, param)
        endif
    elseif eid == "spell.slowTime"
        ; FAF spell with 30s Duration. Refresh every ~25s by re-casting OR on
        ; slider change OR after save/load (delta < 0 because GetCurrentRealTime
        ; resets to a small value on session start).
        float storedMag = StorageUtil.GetFloatValue(target, "mtf.shift.slowTime", -1.0)
        float lastCast = StorageUtil.GetFloatValue(target, "mtf.shift.slowTime.cast", 0.0)
        float now = Utility.GetCurrentRealTime()
        float delta = now - lastCast
        if storedMag != (param as float) || delta > 25.0 || delta < 0.0
            _applySlowTime(target, param)
        endif
    elseif eid == "spell.flameCloak"
        _tickCloak(_resolveFlameCloakSpell(), _resolveFlameCloakDmgSpell(), target, param, param2, "mtf.shift.flameCloak")
    elseif eid == "spell.frostCloak"
        _tickCloak(_resolveFrostCloakSpell(), _resolveFrostCloakDmgSpell(), target, param, param2, "mtf.shift.frostCloak")
    elseif eid == "spell.lightningCloak"
        _tickCloak(_resolveLightningCloakSpell(), _resolveLightningCloakDmgSpell(), target, param, param2, "mtf.shift.lightningCloak")
    elseif eid == "flash.onhit"
        ; Re-push flash params every slow tick. Cheap (one Roster lookup +
        ; field write) and means MCM slider edits on ramp/decay/retrig/peak
        ; take effect within ~2s without needing a tier rebuild.
        _applyFlashOnHit(target, param, param2)
    elseif eid == "shader.play"
        ; Re-Play shader on slow-tick to survive save/load (the engine
        ; doesn't persist EffectShader.Play state), and re-Play the bound
        ; sound when its handle is stale (session resume) or when the
        ; user opted into re-trigger mode for short SNDRs.
        _tickShaderRow(target, param, param2)
    elseif eid == "sound.play"
        ; Loop-mode SNDRs need a re-Play after session resume (same engine
        ; quirk as shaders: Sound.Play handles don't persist across save/load).
        _tickSoundRow(target, param, param2)
    endif
EndFunction

