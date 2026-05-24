Scriptname MTF_Plugin_Base extends MTF_Plugin
{Built-in conditions and effects. See GetConditionId/GetEffectId.}

; LEGACY (pre-v0.0.33): per-quest applied state. Replaced by per-actor
; StorageUtil keyed on target. Properties retained for save-file
; compatibility and one-shot migration in _migrateLegacyApplied.
; Do NOT read or write these from new code — use _getApplied/_setApplied.
float Property _appliedMana       = 0.0 Auto Hidden
float Property _appliedCarry      = 0.0 Auto Hidden
float Property _appliedSneak      = 0.0 Auto Hidden
float Property _appliedSpeed      = 0.0 Auto Hidden
float Property _appliedStamRate   = 0.0 Auto Hidden
float Property _appliedAtkDmg     = 0.0 Auto Hidden
float Property _appliedDmgResist  = 0.0 Auto Hidden
float Property _appliedSpellCost  = 0.0 Auto Hidden
bool  Property _legacyMigrated    = false Auto Hidden

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
    if n > 0
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
    Debug.Notification("[MTF] queueCast spell")
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

Keyword Function _locKw(int idx)
    if idx == 18
        if _kwPlayerHouse == None
            _kwPlayerHouse = Game.GetForm(0x0FC1A3) as Keyword
        endif
        return _kwPlayerHouse
    elseif idx == 19
        if _kwDungeon == None
            _kwDungeon = Game.GetForm(0x18EF1) as Keyword
        endif
        return _kwDungeon
    elseif idx == 20
        if _kwCity == None
            _kwCity = Game.GetForm(0x13167) as Keyword
        endif
        return _kwCity
    elseif idx == 21
        if _kwTown == None
            _kwTown = Game.GetForm(0x192BD) as Keyword
        endif
        return _kwTown
    elseif idx == 22
        if _kwInn == None
            _kwInn = Game.GetForm(0x1929F) as Keyword
        endif
        return _kwInn
    elseif idx == 23
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
string Function GetPluginLabel()
    return "Base"
EndFunction

MTF_MainQuest Function _host()
    return Game.GetFormFromFile(0x803, "MagicTattoosFramework.esp") as MTF_MainQuest
EndFunction

; Called by MTF_HitListener on each player OnHit event.
Function _onHit(int classIdx)
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    h.IncHitCount(classIdx)
EndFunction

; ── Conditions ────────────────────────────────────────────────────────────────

int Function GetConditionCount()
    return 47
EndFunction

string Function GetConditionId(int idx)
    if idx == 0
        return "magicka"
    elseif idx == 1
        return "magicka.below"
    elseif idx == 2
        return "stamina"
    elseif idx == 3
        return "stamina.below"
    elseif idx == 4
        return "combat.in"
    elseif idx == 5
        return "combat.alerted"
    elseif idx == 6
        return "combat.hostile"
    elseif idx == 7
        return "combat.hit"
    elseif idx == 8
        return "combat.hit.blunt"
    elseif idx == 9
        return "combat.hit.bladed"
    elseif idx == 10
        return "combat.hit.ranged"
    elseif idx == 11
        return "combat.hit.magic.fire"
    elseif idx == 12
        return "combat.hit.magic.frost"
    elseif idx == 13
        return "combat.hit.magic.shock"
    elseif idx == 14
        return "health"
    elseif idx == 15
        return "health.below"
    elseif idx == 16
        return "location.indoors"
    elseif idx == 17
        return "location.outdoors"
    elseif idx == 18
        return "location.playerHome"
    elseif idx == 19
        return "location.dungeon"
    elseif idx == 20
        return "location.city"
    elseif idx == 21
        return "location.town"
    elseif idx == 22
        return "location.inn"
    elseif idx == 23
        return "location.jail"
    elseif idx == 24
        return "weather.pleasant"
    elseif idx == 25
        return "weather.cloudy"
    elseif idx == 26
        return "weather.rainy"
    elseif idx == 27
        return "weather.snowy"
    elseif idx == 28
        return "state.sprinting"
    elseif idx == 29
        return "state.running"
    elseif idx == 30
        return "state.weaponDrawn"
    elseif idx == 31
        return "state.loversEmbrace"
    elseif idx == 32
        return "state.sneaking"
    elseif idx == 33
        return "state.swimming"
    elseif idx == 34
        return "state.mounted"
    elseif idx == 35
        return "state.bleedingOut"
    elseif idx == 36
        return "time.range"
    elseif idx == 37
        return "faction.playerFollower"
    elseif idx == 38
        return "magiceffect.kw.fire"
    elseif idx == 39
        return "magiceffect.kw.frost"
    elseif idx == 40
        return "magiceffect.kw.shock"
    elseif idx == 41
        return "magiceffect.kw.invisibility"
    elseif idx == 42
        return "followers.any"
    elseif idx == 43
        return "gold.aboveThousand"
    elseif idx == 44
        return "worn.heavyArmor"
    elseif idx == 45
        return "worn.lightArmor"
    elseif idx == 46
        return "combat.casting"
    endif
    return ""
EndFunction

string Function GetConditionLabel(int idx)
    if idx == 0
        return "Above Magicka %"
    elseif idx == 1
        return "Below Magicka %"
    elseif idx == 2
        return "Above Stamina %"
    elseif idx == 3
        return "Below Stamina %"
    elseif idx == 4
        return "In Combat"
    elseif idx == 5
        return "Enemies Alerted"
    elseif idx == 6
        return "Hostile Nearby"
    elseif idx == 7
        return "On Hit (Any)"
    elseif idx == 8
        return "On Hit (Blunt: mace/warhammer/fist)"
    elseif idx == 9
        return "On Hit (Bladed)"
    elseif idx == 10
        return "On Hit (Ranged)"
    elseif idx == 11
        return "On Hit (Fire)"
    elseif idx == 12
        return "On Hit (Frost)"
    elseif idx == 13
        return "On Hit (Shock)"
    elseif idx == 14
        return "Above Health %"
    elseif idx == 15
        return "Below Health %"
    elseif idx == 16
        return "Indoors"
    elseif idx == 17
        return "Outdoors"
    elseif idx == 18
        return "In Player Home"
    elseif idx == 19
        return "In Dungeon"
    elseif idx == 20
        return "In City"
    elseif idx == 21
        return "In Town"
    elseif idx == 22
        return "In Inn"
    elseif idx == 23
        return "In Jail"
    elseif idx == 24
        return "Weather: Clear / Sunny"
    elseif idx == 25
        return "Weather: Cloudy"
    elseif idx == 26
        return "Weather: Rainy"
    elseif idx == 27
        return "Weather: Snowy"
    elseif idx == 28
        return "Sprinting"
    elseif idx == 29
        return "Running"
    elseif idx == 30
        return "Weapon Drawn"
    elseif idx == 31
        return "Lover's Embrace"
    elseif idx == 32
        return "Sneaking"
    elseif idx == 33
        return "Swimming"
    elseif idx == 34
        return "Mounted"
    elseif idx == 35
        return "Bleeding Out"
    elseif idx == 36
        return "Time of Day Range"
    elseif idx == 37
        return "Is Player's Follower"
    elseif idx == 38
        return "Burning (fire MGEF)"
    elseif idx == 39
        return "Frozen (frost MGEF)"
    elseif idx == 40
        return "Shocked (shock MGEF)"
    elseif idx == 41
        return "Invisible"
    elseif idx == 42
        return "Has Active Follower"
    elseif idx == 43
        return "Gold >= N x 1000"
    elseif idx == 44
        return "Wearing Heavy Armor"
    elseif idx == 45
        return "Wearing Light Armor"
    elseif idx == 46
        return "While Casting Spell"
    endif
    return ""
EndFunction

string Function GetConditionDescription(int idx)
    ; Authors: {param1} / {param2} placeholders are substituted at SkyrimNet
    ; render time via _resolveConditionParamValueLabel. Dropdown menu options
    ; resolve to their label; numeric params apply GetConditionParamFormat
    ; (default "{0}"). Embed units like "%" inline OR override the Format
    ; accessor — both work; inline is easier when the unit varies by idx.
    if idx == 0
        return "Triggers when the actor's magicka is at or above {param1}%."
    elseif idx == 1
        return "Triggers when the actor's magicka drops below {param1}%."
    elseif idx == 2
        return "Triggers when the actor's stamina is at or above {param1}%."
    elseif idx == 3
        return "Triggers when the actor's stamina drops below {param1}%."
    elseif idx == 4
        return "Triggers while the actor is in combat (engaged in active fight)."
    elseif idx == 5
        return "Triggers when hostile NPCs within {param1}m are alerted to the actor."
    elseif idx == 6
        return "Triggers when at least one hostile NPC is within {param1}m."
    elseif idx == 7
        return "Triggers with a {param1}% chance per incoming hit (any type)."
    elseif idx == 8
        return "Triggers with a {param1}% chance per blunt-weapon hit (mace, warhammer, unarmed)."
    elseif idx == 9
        return "Triggers with a {param1}% chance per bladed-weapon hit."
    elseif idx == 10
        return "Triggers with a {param1}% chance per ranged hit (arrow or bolt)."
    elseif idx == 11
        return "Triggers with a {param1}% chance per fire-school damage hit."
    elseif idx == 12
        return "Triggers with a {param1}% chance per frost-school damage hit."
    elseif idx == 13
        return "Triggers with a {param1}% chance per shock-school damage hit."
    elseif idx == 14
        return "Triggers when the actor's health is at or above {param1}%."
    elseif idx == 15
        return "Triggers when the actor's health drops below {param1}%."
    elseif idx == 16
        return "Triggers whenever the actor is inside any interior cell."
    elseif idx == 17
        return "Triggers whenever the actor is in an exterior worldspace."
    elseif idx == 18
        return "Triggers when the actor is inside a location flagged as the player's home."
    elseif idx == 19
        return "Triggers when the actor is inside a dungeon-type location."
    elseif idx == 20
        return "Triggers when the actor is inside a city worldspace (Whiterun, Solitude, etc.)."
    elseif idx == 21
        return "Triggers when the actor is inside a town-type location."
    elseif idx == 22
        return "Triggers when the actor is inside an inn or tavern."
    elseif idx == 23
        return "Triggers when the actor is held in a jail cell."
    elseif idx == 24
        return "Triggers when the current weather is clear or sunny."
    elseif idx == 25
        return "Triggers when the current weather is cloudy."
    elseif idx == 26
        return "Triggers when the current weather is rainy."
    elseif idx == 27
        return "Triggers when the current weather is snowy."
    elseif idx == 28
        return "Triggers while the actor is sprinting."
    elseif idx == 29
        return "Triggers while the actor is running (not walking, not sprinting)."
    elseif idx == 30
        return "Triggers while the actor has a weapon or spell drawn."
    elseif idx == 31
        return "Triggers while the actor has the Lover's Embrace rested bonus active."
    elseif idx == 32
        return "Triggers while the actor is sneaking."
    elseif idx == 33
        return "Triggers while the actor is swimming."
    elseif idx == 34
        return "Triggers while the actor is mounted on a horse or other steed."
    elseif idx == 35
        return "Triggers while the actor is downed and bleeding out."
    elseif idx == 36
        return "Triggers between in-game hours {param1} and {param2} (wraps midnight if end is earlier than start)."
    elseif idx == 37
        return "Triggers when the actor is one of the player's current followers."
    elseif idx == 38
        return "Triggers while a fire-keyword magic effect is active on the actor (burning)."
    elseif idx == 39
        return "Triggers while a frost-keyword magic effect is active on the actor (frozen)."
    elseif idx == 40
        return "Triggers while a shock-keyword magic effect is active on the actor (shocked)."
    elseif idx == 41
        return "Triggers while the actor is invisible."
    elseif idx == 42
        return "Triggers when at least one follower NPC is within {param1}m."
    elseif idx == 43
        return "Triggers when the actor's gold is at or above {param1},000."
    elseif idx == 44
        return "Triggers when the actor is wearing a heavy-armor cuirass."
    elseif idx == 45
        return "Triggers when the actor is wearing a light-armor cuirass."
    elseif idx == 46
        return "Triggers while the actor is charging or holding a spell mid-cast."
    endif
    return ""
EndFunction

string Function GetConditionParamLabel(int idx)
    if idx <= 3 || idx == 14 || idx == 15
        return "Health/Magicka/Stamina % threshold"
    elseif idx == 5 || idx == 6
        return "Scan radius (meters)"
    elseif idx >= 7 && idx <= 13
        return "Chance % per hit"
    elseif idx == 36
        return "From (hour)"
    elseif idx == 42
        return "Scan radius (meters)"
    elseif idx == 43
        return "Gold threshold (x 1000)"
    endif
    return ""
EndFunction

int Function GetConditionParamMin(int idx)
    if idx == 5 || idx == 6
        return 1
    elseif idx >= 7 && idx <= 13
        return 1
    elseif idx == 42
        return 1
    endif
    return 0
EndFunction

int Function GetConditionParamMax(int idx)
    if idx == 36
        return 24
    elseif idx == 43
        return 1000
    endif
    return 100
EndFunction

int Function GetConditionParamDefault(int idx)
    if idx == 0 || idx == 2 || idx == 14
        return 50
    elseif idx == 1 || idx == 3 || idx == 15
        return 30
    elseif idx == 5
        return 40
    elseif idx == 6
        return 25
    elseif idx >= 7 && idx <= 13
        return 25
    elseif idx == 36
        return 6   ; Day starts at 6h
    elseif idx == 42
        return 80
    elseif idx == 43
        return 5
    endif
    return 0
EndFunction

; Second parameter for time.range (till hour).
string Function GetConditionParam2Label(int idx)
    if idx == 36
        return "Till (hour, wrap if < From)"
    endif
    return ""
EndFunction
int Function GetConditionParam2Min(int idx)
    return 0
EndFunction
int Function GetConditionParam2Max(int idx)
    if idx == 36
        return 24
    endif
    return 100
EndFunction
int Function GetConditionParam2Default(int idx)
    if idx == 36
        return 20  ; Day ends at 20h
    endif
    return 0
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

int Function _hitClassFor(int idx)
    ; 7=ANY 8=BLUNT 9=BLADED 10=RANGED 11=FIRE 12=FROST 13=SHOCK
    if idx == 7
        return 0
    elseif idx == 8
        return 1
    elseif idx == 9
        return 2
    elseif idx == 10
        return 3
    elseif idx == 11
        return 4
    elseif idx == 12
        return 5
    elseif idx == 13
        return 6
    endif
    return -1
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

bool Function checkCondition(int idx, Actor target, int param)
    if target == None
        return false
    endif
    if idx == 0
        float p = _avPercent(target, "Magicka")
        return p >= 0.0 && p >= param as float
    elseif idx == 1
        float p = _avPercent(target, "Magicka")
        return p >= 0.0 && p <= param as float
    elseif idx == 2
        float p = _avPercent(target, "Stamina")
        return p >= 0.0 && p >= param as float
    elseif idx == 3
        float p = _avPercent(target, "Stamina")
        return p >= 0.0 && p <= param as float
    elseif idx == 4
        return target.IsInCombat()
    elseif idx == 5
        return _scanNearbyCombat(target, param)
    elseif idx == 6
        return _scanNearbyHostile(target, param)
    elseif idx >= 7 && idx <= 13
        int c = _hitClassFor(idx)
        if c < 0
            return false
        endif
        return _checkHit(c, param)
    elseif idx == 14
        float p = _avPercent(target, "Health")
        return p >= 0.0 && p >= param as float
    elseif idx == 15
        float p = _avPercent(target, "Health")
        return p >= 0.0 && p <= param as float
    elseif idx == 16
        Cell c = target.GetParentCell()
        return c != None && c.IsInterior()
    elseif idx == 17
        Cell c = target.GetParentCell()
        return c != None && !c.IsInterior()
    elseif idx >= 18 && idx <= 23
        Location loc = target.GetCurrentLocation()
        if loc == None
            return false
        endif
        Keyword kw = _locKw(idx)
        if kw == None
            return false
        endif
        return loc.HasKeyword(kw)
    elseif idx >= 24 && idx <= 27
        Weather w = Weather.GetCurrentWeather()
        if w == None
            return false
        endif
        return w.GetClassification() == (idx - 24)
    elseif idx == 28
        return target.IsSprinting()
    elseif idx == 29
        ; "Running" without the sprint state — distinct condition.
        return target.IsRunning() && !target.IsSprinting()
    elseif idx == 30
        return target.IsWeaponDrawn()
    elseif idx == 31
        if _loversComfort == None
            _loversComfort = Game.GetForm(0x000CDA1D) as Spell
        endif
        if _loversComfort == None
            return false
        endif
        return target.HasSpell(_loversComfort)
    elseif idx == 32
        return target.IsSneaking()
    elseif idx == 33
        return target.IsSwimming()
    elseif idx == 34
        return target.IsOnMount()
    elseif idx == 35
        return target.IsBleedingOut()
    elseif idx == 36
        ; time.range — param=from hour, param2=till hour. Wraps if from > till.
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
    elseif idx == 37
        if _facCurrentFollower == None
            _facCurrentFollower = Game.GetForm(0x0005C84D) as Faction
        endif
        return _facCurrentFollower != None && target.IsInFaction(_facCurrentFollower)
    elseif idx == 38
        if _kwMgefFire == None
            _kwMgefFire = Game.GetForm(0x0001CEAD) as Keyword
        endif
        return _kwMgefFire != None && target.HasMagicEffectWithKeyword(_kwMgefFire)
    elseif idx == 39
        if _kwMgefFrost == None
            _kwMgefFrost = Game.GetForm(0x0001CEAE) as Keyword
        endif
        return _kwMgefFrost != None && target.HasMagicEffectWithKeyword(_kwMgefFrost)
    elseif idx == 40
        if _kwMgefShock == None
            _kwMgefShock = Game.GetForm(0x0001CEAF) as Keyword
        endif
        return _kwMgefShock != None && target.HasMagicEffectWithKeyword(_kwMgefShock)
    elseif idx == 41
        ; Use the Invisibility actor value (set by ANY source — potion, spell,
        ; racial). HasMagicEffectWithKeyword(MagicInvisibility) misses some
        ; effects since not all invisibility-applying effects carry the keyword.
        return target.GetActorValue("Invisibility") > 0.0
    elseif idx == 42
        return _scanNearbyFollower(target, param)
    elseif idx == 43
        if _goldForm == None
            _goldForm = Game.GetForm(0x0000000F)
        endif
        return _goldForm != None && target.GetItemCount(_goldForm) >= (param * 1000)
    elseif idx == 44
        if _kwArmorHeavy == None
            _kwArmorHeavy = Game.GetForm(0x0006BBD2) as Keyword
        endif
        return _kwArmorHeavy != None && _wornHasArmorKw(target, _kwArmorHeavy)
    elseif idx == 45
        if _kwArmorLight == None
            _kwArmorLight = Game.GetForm(0x0006BBD3) as Keyword
        endif
        return _kwArmorLight != None && _wornHasArmorKw(target, _kwArmorLight)
    elseif idx == 46
        ; combat.casting: continuous "is the actor mid-cast" check. State is
        ; maintained by MTF_CastListener (animvar polling — see KB entry).
        ; Currently player-only because the listener is on the player alias;
        ; NPCs always read false here (StorageUtil default).
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

; ── Effects ───────────────────────────────────────────────────────────────────

int Function GetEffectCount()
    return 58
EndFunction

string Function GetEffectId(int idx)
    if idx < 13
        return _effectIdLow(idx)
    endif
    return _effectIdHigh(idx)
EndFunction

; v0.1.10: idx 8 (was "modify.armor", direct DamageResist) was removed
; because direct ModActorValue on DamageResist is unreliable — engine
; recomputes per frame. Use idx 27 (spell.modifyArmor) instead. After
; removal the idx 9-55 range was shifted down to 8-54 to close the gap;
; all key strings (modify.sneak etc.) are unchanged so presets remain
; valid, but any code referencing old idx numbers had to be updated.
string Function _effectIdLow(int idx)
    if idx == 0
        return "modify.magickaRegen"
    elseif idx == 1
        return "modify.carryWeight"
    elseif idx == 2
        return "modify.sneak"
    elseif idx == 3
        return "damage.magicka"
    elseif idx == 4
        return "damage.stamina"
    elseif idx == 5
        return "modify.movementSpeed"
    elseif idx == 6
        return "modify.staminaRegen"
    elseif idx == 7
        return "modify.attackDamage"
    elseif idx == 8
        return "burst.stagger"
    elseif idx == 9
        return "burst.blowCover"
    elseif idx == 10
        return "scale.magickaCost"
    elseif idx == 11
        return "modify.healthRegen"
    elseif idx == 12
        return "modify.maxMagicka"
    endif
    return ""
EndFunction

string Function _effectIdHigh(int idx)
    if idx == 13
        return "modify.maxStamina"
    elseif idx == 14
        return "modify.weaponSpeed"
    elseif idx == 15
        return "modify.unarmedDamage"
    elseif idx == 16
        return "modify.criticalChance"
    elseif idx == 17
        return "modify.bowSpeed"
    elseif idx == 18
        return "modify.resistFire"
    elseif idx == 19
        return "modify.resistFrost"
    elseif idx == 20
        return "modify.resistShock"
    elseif idx == 21
        return "modify.resistMagic"
    elseif idx == 22
        return "toggle.muffle"
    elseif idx == 23
        return "toggle.waterbreathing"
    elseif idx == 24
        return "toggle.waterWalking"
    elseif idx == 25
        return "damage.health"
    elseif idx == 26
        return "burst.bounty"
    elseif idx == 27
        return "spell.modifyArmor"
    elseif idx == 28
        return "spell.detectLife"
    elseif idx == 29
        return "spell.slowTime"
    elseif idx == 30
        return "spell.flameCloak"
    elseif idx == 31
        return "spell.frostCloak"
    elseif idx == 32
        return "spell.lightningCloak"
    elseif idx == 33
        return "flash.onhit"
    elseif idx == 34
        return "modify.resistDisease"
    elseif idx == 35
        return "modify.resistPoison"
    elseif idx == 36
        return "modify.absorbChance"
    elseif idx == 37
        return "modify.reflectDamage"
    elseif idx == 38
        return "modify.oneHanded"
    elseif idx == 39
        return "modify.twoHanded"
    elseif idx == 40
        return "modify.archery"
    elseif idx == 41
        return "modify.block"
    elseif idx == 42
        return "modify.heavyArmor"
    elseif idx == 43
        return "modify.lightArmor"
    elseif idx == 44
        return "modify.smithing"
    elseif idx == 45
        return "modify.enchanting"
    elseif idx == 46
        return "modify.alchemy"
    elseif idx == 47
        return "modify.destruction"
    elseif idx == 48
        return "modify.restoration"
    elseif idx == 49
        return "modify.alteration"
    elseif idx == 50
        return "modify.illusion"
    elseif idx == 51
        return "modify.conjuration"
    elseif idx == 52
        return "modify.speech"
    elseif idx == 53
        return "modify.lockpicking"
    elseif idx == 54
        return "modify.pickpocket"
    elseif idx == 55
        return "shader.play"
    elseif idx == 56
        return "sound.play"
    elseif idx == 57
        return "flash.oncast"
    endif
    return ""
EndFunction

string Function GetEffectLabel(int idx)
    if idx < 13
        return _effectLabelLow(idx)
    endif
    return _effectLabelHigh(idx)
EndFunction

string Function _effectLabelLow(int idx)
    if idx == 0
        return "Modify Magicka Regen"
    elseif idx == 1
        return "Modify Carry Weight"
    elseif idx == 2
        return "Modify Sneak"
    elseif idx == 3
        return "[!] Damage Magicka"
    elseif idx == 4
        return "[!] Damage Stamina"
    elseif idx == 5
        return "Modify Movement Speed"
    elseif idx == 6
        return "Modify Stamina Regen"
    elseif idx == 7
        return "Modify Attack Damage"
    elseif idx == 8
        return "[!] Stagger"
    elseif idx == 9
        return "[!] Blow Cover"
    elseif idx == 10
        return "Scale Magicka Cost"
    elseif idx == 11
        return "Modify Health Regen"
    elseif idx == 12
        return "Modify Max Magicka"
    endif
    return ""
EndFunction

string Function _effectLabelHigh(int idx)
    if idx == 13
        return "Modify Max Stamina"
    elseif idx == 14
        return "Modify Weapon Speed"
    elseif idx == 15
        return "Modify Unarmed Damage"
    elseif idx == 16
        return "Modify Critical Chance"
    elseif idx == 17
        return "Modify Bow Speed"
    elseif idx == 18
        return "Modify Fire Resist"
    elseif idx == 19
        return "Modify Frost Resist"
    elseif idx == 20
        return "Modify Shock Resist"
    elseif idx == 21
        return "Modify Magic Resist"
    elseif idx == 22
        return "[+] Muffle"
    elseif idx == 23
        return "[+] Waterbreathing"
    elseif idx == 24
        return "[+] Water Walking"
    elseif idx == 25
        return "[!] Damage Health"
    elseif idx == 26
        return "[!] Add Bounty"
    elseif idx == 27
        return "[+] Modify Armor"
    elseif idx == 28
        return "[+] Detect Life"
    elseif idx == 29
        return "[+] Slow Time"
    elseif idx == 30
        return "[+] Flame Cloak"
    elseif idx == 31
        return "[+] Frost Cloak"
    elseif idx == 32
        return "[+] Lightning Cloak"
    elseif idx == 33
        return "[!] Flash on Hit"
    elseif idx == 34
        return "Modify Disease Resist"
    elseif idx == 35
        return "Modify Poison Resist"
    elseif idx == 36
        return "Modify Spell Absorb"
    elseif idx == 37
        return "Modify Reflect Damage"
    elseif idx == 38
        return "Modify One-Handed"
    elseif idx == 39
        return "Modify Two-Handed"
    elseif idx == 40
        return "Modify Archery"
    elseif idx == 41
        return "Modify Block"
    elseif idx == 42
        return "Modify Heavy Armor"
    elseif idx == 43
        return "Modify Light Armor"
    elseif idx == 44
        return "Modify Smithing"
    elseif idx == 45
        return "Modify Enchanting"
    elseif idx == 46
        return "Modify Alchemy"
    elseif idx == 47
        return "Modify Destruction"
    elseif idx == 48
        return "Modify Restoration"
    elseif idx == 49
        return "Modify Alteration"
    elseif idx == 50
        return "Modify Illusion"
    elseif idx == 51
        return "Modify Conjuration"
    elseif idx == 52
        return "Modify Speech"
    elseif idx == 53
        return "Modify Lockpicking"
    elseif idx == 54
        return "Modify Pickpocket"
    elseif idx == 55
        return "[+] Vanilla Shader"
    elseif idx == 56
        return "[+] Vanilla Sound"
    elseif idx == 57
        return "[+] Flash on Cast"
    endif
    return ""
EndFunction

string Function GetEffectDescription(int idx)
    if idx < 13
        return _effectDescriptionLow(idx)
    endif
    return _effectDescriptionHigh(idx)
EndFunction

string Function _effectDescriptionLow(int idx)
    if idx == 0
        return "Shifts the actor's magicka regeneration rate by {param1}%."
    elseif idx == 1
        return "Shifts the actor's carry-weight cap by {param1}."
    elseif idx == 2
        return "Shifts the actor's Sneak skill by {param1}."
    elseif idx == 3
        return "Burst — damages or restores {param1}% of the actor's base magicka when the tier activates."
    elseif idx == 4
        return "Burst — damages or restores {param1}% of the actor's base stamina when the tier activates."
    elseif idx == 5
        return "Shifts the actor's movement-speed multiplier by {param1}%."
    elseif idx == 6
        return "Shifts the actor's stamina regeneration rate by {param1}%."
    elseif idx == 7
        return "Shifts the actor's outgoing attack damage by {param1}%."
    elseif idx == 8
        return "Burst — staggers the actor when the tier activates."
    elseif idx == 9
        return "Burst — alerts every hostile NPC within {param1}ft to the actor's presence (blows stealth)."
    elseif idx == 10
        return "Spells cost {param1}% of their original across all schools."
    elseif idx == 11
        return "Shifts the actor's health regeneration rate by {param1}%."
    elseif idx == 12
        return "Shifts the actor's maximum magicka by {param1}."
    endif
    return ""
EndFunction

string Function _effectDescriptionHigh(int idx)
    if idx == 13
        return "Shifts the actor's maximum stamina by {param1}."
    elseif idx == 14
        return "Shifts the actor's weapon-swing speed by {param1}%."
    elseif idx == 15
        return "Shifts the actor's unarmed melee damage by {param1}."
    elseif idx == 16
        return "Shifts the actor's critical-strike chance by {param1}%."
    elseif idx == 17
        return "Shifts the actor's bow draw and release speed by {param1}."
    elseif idx == 18
        return "Shifts the actor's fire resistance by {param1}%."
    elseif idx == 19
        return "Shifts the actor's frost resistance by {param1}%."
    elseif idx == 20
        return "Shifts the actor's shock resistance by {param1}%."
    elseif idx == 21
        return "Shifts the actor's magic resistance by {param1}%."
    elseif idx == 22
        return "Toggles silenced footsteps on the actor while active."
    elseif idx == 23
        return "Toggles waterbreathing on the actor while active."
    elseif idx == 24
        return "Toggles water-walking on the actor while active."
    elseif idx == 25
        return "Burst — damages or restores {param1}% of the actor's base health when the tier activates."
    elseif idx == 26
        return "Burst — adjusts the actor's bounty in their current hold by {param1} gold (positive adds, negative pays off)."
    elseif idx == 27
        return "Toggles a flat armor-rating bonus of {param1} while active."
    elseif idx == 28
        return "Toggles a Detect Life aura that highlights living NPCs within {param1}ft while active."
    elseif idx == 29
        return "Toggles a slow-time effect that drags everything around the actor to {param1}% of normal speed while active."
    elseif idx == 30
        return "Toggles a flame cloak that burns enemies within {param2}ft for {param1} damage/s while active."
    elseif idx == 31
        return "Toggles a frost cloak that chills enemies within {param2}ft for {param1} damage/s while active."
    elseif idx == 32
        return "Toggles a lightning cloak that shocks enemies within {param2}ft for {param1} damage/s while active."
    elseif idx == 33
        return "Flashes the tattoo's emissive layer to {param2}% brightness on every {param1} hit."
    elseif idx == 34
        return "Shifts the actor's disease resistance by {param1}%."
    elseif idx == 35
        return "Shifts the actor's poison resistance by {param1}%."
    elseif idx == 36
        return "Shifts the actor's chance to absorb incoming spells by {param1}%."
    elseif idx == 37
        return "Shifts the actor's chance to reflect incoming melee damage by {param1}%."
    elseif idx == 38
        return "Shifts the actor's One-Handed weapon skill by {param1}."
    elseif idx == 39
        return "Shifts the actor's Two-Handed weapon skill by {param1}."
    elseif idx == 40
        return "Shifts the actor's Archery (Marksman) skill by {param1}."
    elseif idx == 41
        return "Shifts the actor's Block skill by {param1}."
    elseif idx == 42
        return "Shifts the actor's Heavy Armor skill by {param1}."
    elseif idx == 43
        return "Shifts the actor's Light Armor skill by {param1}."
    elseif idx == 44
        return "Shifts the actor's Smithing skill by {param1}."
    elseif idx == 45
        return "Shifts the actor's Enchanting skill by {param1}."
    elseif idx == 46
        return "Shifts the actor's Alchemy skill by {param1}."
    elseif idx == 47
        return "Shifts the actor's Destruction magic skill by {param1}."
    elseif idx == 48
        return "Shifts the actor's Restoration magic skill by {param1}."
    elseif idx == 49
        return "Shifts the actor's Alteration magic skill by {param1}."
    elseif idx == 50
        return "Shifts the actor's Illusion magic skill by {param1}."
    elseif idx == 51
        return "Shifts the actor's Conjuration magic skill by {param1}."
    elseif idx == 52
        return "Shifts the actor's Speech (persuasion / barter) skill by {param1}."
    elseif idx == 53
        return "Shifts the actor's Lockpicking skill by {param1}."
    elseif idx == 54
        return "Shifts the actor's Pickpocket skill by {param1}."
    elseif idx == 55
        return "Plays the {param1} effect shader on the actor while active (duration {param2}s; 0 = until removed)."
    elseif idx == 56
        return "Plays the {param1} looping sound on the actor while active (duration {param2}s; 0 = until removed)."
    elseif idx == 57
        return "Flashes the tattoo's emissive layer to {param1}% brightness while the actor is casting a spell."
    endif
    return ""
EndFunction

string Function GetEffectParamLabel(int idx)
    if idx < 13
        return _effectParamLabelLow(idx)
    endif
    return _effectParamLabelHigh(idx)
EndFunction

string Function _effectParamLabelLow(int idx)
    if idx == 0
        return "Magicka regen rate shift (mult points; + faster, - slower)"
    elseif idx == 1
        return "Carry weight shift (points; + buff, - drain)"
    elseif idx == 2
        return "Sneak skill shift (points; + buff, - drain)"
    elseif idx == 3
        return "Burst % of base Magicka (+ restore, - damage)"
    elseif idx == 4
        return "Burst % of base Stamina (+ restore, - damage)"
    elseif idx == 5
        return "Movement speed shift (mult points; + faster, - slower)"
    elseif idx == 6
        return "Stamina regen rate shift (mult points; + faster, - slower)"
    elseif idx == 7
        return "Attack damage shift (% points; + buff, - drain)"
    elseif idx == 8
        return ""
    elseif idx == 9
        return "Alert radius (feet)"
    elseif idx == 10
        return "Spell cost (% of original)"
    elseif idx == 11
        return "Health regen rate shift (mult points; + faster, - slower)"
    elseif idx == 12
        return "Max magicka shift (points; + buff, - drain)"
    endif
    return ""
EndFunction

string Function _effectParamLabelHigh(int idx)
    if idx == 13
        return "Max stamina shift (points; + buff, - drain)"
    elseif idx == 14
        return "Weapon speed shift (% points; + faster, - slower)"
    elseif idx == 15
        return "Unarmed damage shift (points; + buff, - drain)"
    elseif idx == 16
        return "Critical chance shift (points; + buff, - drain)"
    elseif idx == 17
        return "Bow speed bonus shift (units; + faster draw, - slower)"
    elseif idx == 18
        return "Fire resist shift (points; + resist, - weakness)"
    elseif idx == 19
        return "Frost resist shift (points; + resist, - weakness)"
    elseif idx == 20
        return "Shock resist shift (points; + resist, - weakness)"
    elseif idx == 21
        return "Magic resist shift (points; + resist, - weakness)"
    elseif idx == 22 || idx == 23 || idx == 24
        return ""
    elseif idx == 25
        return "Burst % of base Health (+ restore, - damage)"
    elseif idx == 26
        return "Bounty change (gold; + add, - remove)"
    elseif idx == 27
        return "Armor rating points"
    elseif idx == 28
        return "Detect radius (feet)"
    elseif idx == 29
        return "Time speed % (lower = slower; 100 = normal)"
    elseif idx == 30 || idx == 31 || idx == 32
        return "Damage per second"
    elseif idx == 33
        return "Trigger event"
    elseif idx == 34
        return "Disease resist shift (points; + resist, - weakness)"
    elseif idx == 35
        return "Poison resist shift (points; + resist, - weakness)"
    elseif idx == 36
        return "Spell absorb chance shift (points; + absorb, - vulnerable)"
    elseif idx == 37
        return "Reflect damage chance shift (points; + reflect, - vulnerable)"
    elseif idx == 38
        return "One-Handed skill shift (points; + buff, - drain)"
    elseif idx == 39
        return "Two-Handed skill shift (points; + buff, - drain)"
    elseif idx == 40
        return "Archery skill shift (points; + buff, - drain)"
    elseif idx == 41
        return "Block skill shift (points; + buff, - drain)"
    elseif idx == 42
        return "Heavy Armor skill shift (points; + buff, - drain)"
    elseif idx == 43
        return "Light Armor skill shift (points; + buff, - drain)"
    elseif idx == 44
        return "Smithing skill shift (points; + buff, - drain)"
    elseif idx == 45
        return "Enchanting skill shift (points; + buff, - drain)"
    elseif idx == 46
        return "Alchemy skill shift (points; + buff, - drain)"
    elseif idx == 47
        return "Destruction skill shift (points; + buff, - drain)"
    elseif idx == 48
        return "Restoration skill shift (points; + buff, - drain)"
    elseif idx == 49
        return "Alteration skill shift (points; + buff, - drain)"
    elseif idx == 50
        return "Illusion skill shift (points; + buff, - drain)"
    elseif idx == 51
        return "Conjuration skill shift (points; + buff, - drain)"
    elseif idx == 52
        return "Speech skill shift (points; + buff, - drain)"
    elseif idx == 53
        return "Lockpicking skill shift (points; + buff, - drain)"
    elseif idx == 54
        return "Pickpocket skill shift (points; + buff, - drain)"
    elseif idx == 55
        return "Shader"
    elseif idx == 56
        return "Sound"
    elseif idx == 57
        return "Peak emissive (additive, % of 1.0)"
    endif
    return ""
EndFunction

int Function GetEffectParamMin(int idx)
    if idx == 8 || idx == 22 || idx == 23 || idx == 24
        return 0
    elseif idx == 9 || idx == 28
        return 5
    elseif idx == 10
        return 0   ; 0% of original cost = free spells (max discount)
    elseif idx == 26
        return -10000
    elseif idx == 27
        return 0
    elseif idx == 29
        return 5
    elseif idx == 30 || idx == 31 || idx == 32
        return 1
    elseif idx == 33
        return 0
    elseif idx == 55
        return 0  ; shader index; rendered as dropdown via Menu APIs
    elseif idx == 56
        return 0  ; sound index; rendered as dropdown via Menu APIs
    elseif idx == 57
        return 0  ; flash.oncast: 0 = disabled (no peak → no flash)
    endif
    return -100
EndFunction
int Function GetEffectParamMax(int idx)
    if idx == 8 || idx == 22 || idx == 23 || idx == 24
        return 0
    elseif idx == 9
        return 300
    elseif idx == 10
        return 400   ; 400% of original cost = 4× penalty (slider top)
    elseif idx == 26
        return 10000
    elseif idx == 27
        return 500
    elseif idx == 28
        return 500
    elseif idx == 29
        return 100
    elseif idx == 30 || idx == 31 || idx == 32
        return 200
    elseif idx == 33
        return 127
    elseif idx == 55
        return _shaderCount() - 1
    elseif idx == 56
        return _soundCount() - 1
    elseif idx == 57
        return 1000  ; same scale as flash.onhit param2: 1000 = +10.0 additive
    endif
    return 100
EndFunction
int Function GetEffectParamDefault(int idx)
    if idx == 9
        return 80
    elseif idx == 10
        return 100  ; default to "no change" — user dials down for discount
    elseif idx == 27
        return 100
    elseif idx == 28
        return 100
    elseif idx == 29
        return 50
    elseif idx == 30 || idx == 31 || idx == 32
        return 8
    elseif idx == 33
        return 1  ; ANY wildcard — fires on every hit
    elseif idx == 55
        return 0  ; first shader in catalog
    elseif idx == 56
        return 0  ; first sound in catalog
    elseif idx == 57
        return 300  ; +3.0 additive emissive while casting — visible glow
    endif
    return 0
EndFunction

int Function GetEffectParamStep(int idx)
    if idx == 10
        return 5
    elseif idx == 26
        return 50
    elseif idx == 9
        return 5
    elseif idx == 27
        return 10
    elseif idx == 28
        return 10
    elseif idx == 29
        return 5
    elseif idx == 30 || idx == 31 || idx == 32
        return 1
    elseif idx == 33
        return 1
    elseif idx == 55
        return 1
    elseif idx == 56
        return 1
    elseif idx == 57
        return 10
    endif
    return 1
EndFunction

string Function GetEffectParamFormat(int idx)
    ; All percentage units now live in the description text
    ; (e.g. "Spells cost {param1}% of their original ..."). Keeping
    ; both description-side and Format-side `%` produced "100%%" in the
    ; bio — see KNOWLEDGEBASE: "Bridge must funnel ALL state mutations".
    return "{0}"
EndFunction

string Function GetEffectParam2Label(int idx)
    ; Cloak radius slider (idx 30-32). Outer spell Area is written via
    ; SetNthEffectArea in _applyCloak, converting feet → game units.
    if idx == 30 || idx == 31 || idx == 32
        return "Radius (feet)"
    elseif idx == 33
        return "Peak emissive (additive, % of 1.0)"
    elseif idx == 55
        return "Duration (s, 0 = until removed)"
    elseif idx == 56
        return "Duration (s, 0 = until removed)"
    endif
    return ""
EndFunction
int Function GetEffectParam2Min(int idx)
    if idx == 30 || idx == 31 || idx == 32
        return 3
    elseif idx == 33
        return 0
    elseif idx == 55
        return 0
    elseif idx == 56
        return 0
    endif
    return 0
EndFunction
int Function GetEffectParam2Max(int idx)
    if idx == 30 || idx == 31 || idx == 32
        return 500
    elseif idx == 33
        return 1000
    elseif idx == 55
        return 60
    elseif idx == 56
        return 60
    endif
    return 100
EndFunction
int Function GetEffectParam2Default(int idx)
    if idx == 30 || idx == 31 || idx == 32
        return 5
    elseif idx == 33
        return 300  ; +3.0 additive emissive at peak — visible spike
    elseif idx == 55
        return 0  ; until-removed; tick re-Plays after save/load
    elseif idx == 56
        return 0  ; until-removed; tick re-Plays after save/load
    endif
    return 0
EndFunction
int Function GetEffectParam2Step(int idx)
    if idx == 33
        return 10
    endif
    return 1
EndFunction
string Function GetEffectParam2Format(int idx)
    ; All percentage units now live in the description text — idx 33's
    ; "to {param2}% brightness" was double-formatting to "300%%" with
    ; this override AND the description-side `%` both active.
    return "{0}"
EndFunction

; ── Dropdown options (v0.1.3) — param/param2 as menus ────────────────────────
int Function GetEffectParamMenuOptionCount(int idx)
    if idx == 33
        return 11
    elseif idx == 55
        return _shaderCount()
    elseif idx == 56
        return _soundCount()
    endif
    return 0
EndFunction

int Function GetEffectParamMenuOptionValue(int idx, int optionIdx)
    ; Flat if/return — preset value the option stores. Wildcard ("*",
    ; classMask=1) is intentionally NOT in the MCM list anymore — it's
    ; reserved for hand-edited presets and external-mod tag broadcasters
    ; (see _classMaskToTags). MCM users pick from explicit combat classes.
    if idx == 55
        ; shader.play — value IS the shader catalog index, identity map.
        return optionIdx
    endif
    if idx == 56
        ; sound.play — value IS the sound catalog index, identity map.
        return optionIdx
    endif
    if idx != 33
        return 0
    endif
    if optionIdx == 0
        return 0
    endif
    if optionIdx == 1
        return 2
    endif
    if optionIdx == 2
        return 4
    endif
    if optionIdx == 3
        return 8
    endif
    if optionIdx == 4
        return 16
    endif
    if optionIdx == 5
        return 32
    endif
    if optionIdx == 6
        return 64
    endif
    if optionIdx == 7
        return 6
    endif
    if optionIdx == 8
        return 14
    endif
    if optionIdx == 9
        return 112
    endif
    if optionIdx == 10
        return 126
    endif
    return 0
EndFunction

string Function GetEffectParamMenuOptionLabel(int idx, int optionIdx)
    ; flash.onhit trigger-event presets. Each preset maps (in
    ; _classMaskToTags below) to a C++ tag CSV. Hand-edited preset JSON
    ; with off-list ints still works (MCM shows "Custom: N").
    if idx == 55
        return _shaderLabel(optionIdx)
    endif
    if idx == 56
        return _soundLabel(optionIdx)
    endif
    if idx != 33
        return ""
    endif
    if optionIdx == 0
        return "Disabled"
    endif
    if optionIdx == 1
        return "Blunt only"
    endif
    if optionIdx == 2
        return "Bladed only"
    endif
    if optionIdx == 3
        return "Ranged only"
    endif
    if optionIdx == 4
        return "Fire only"
    endif
    if optionIdx == 5
        return "Frost only"
    endif
    if optionIdx == 6
        return "Shock only"
    endif
    if optionIdx == 7
        return "Melee (Blunt + Bladed)"
    endif
    if optionIdx == 8
        return "Physical (Blunt + Bladed + Ranged)"
    endif
    if optionIdx == 9
        return "Magic (Fire + Frost + Shock)"
    endif
    if optionIdx == 10
        return "All combat classes"
    endif
    return ""
EndFunction

; ── Extras (v0.1.3) — per-effect extra fields ────────────────────────────────
; flash.onhit (idx 33) declares three envelope timing extras:
;   rampms    — 0→1 intensity ramp (1..2000 ms, default 80)
;   decayms   — 1→0 intensity decay after retrigger expires (1..5000 ms, default 350)
;   retrigms  — sustain window; while now − lastHit < retrigms, intensity holds
;               at 1.0. New hits inside the window reset lastHit, keeping the
;               flash alight. Outside the window, decay runs. (0..2000 ms,
;               default 150)
; sound.play (idx 56) declares one mixer extra:
;   volume    — 0..100% multiplier on Sound.SetInstanceVolume after Play
;               (default 100). Range chosen percent-friendly so MCM slider
;               reads naturally — internal mult is volume/100.0.
int Function GetEffectExtraFieldCount(int idx)
    if idx == 33
        return 3
    endif
    if idx == 56
        return 1
    endif
    if idx == 57
        return 3
    endif
    return 0
EndFunction

string Function GetEffectExtraFieldName(int idx, int fieldIdx)
    if idx == 33
        if fieldIdx == 0
            return "rampms"
        endif
        if fieldIdx == 1
            return "decayms"
        endif
        if fieldIdx == 2
            return "retrigms"
        endif
    endif
    if idx == 56
        if fieldIdx == 0
            return "volume"
        endif
    endif
    if idx == 57
        if fieldIdx == 0
            return "rampms"
        endif
        if fieldIdx == 1
            return "decayms"
        endif
        if fieldIdx == 2
            return "retrigms"
        endif
    endif
    return ""
EndFunction

string Function GetEffectExtraFieldLabel(int idx, int fieldIdx)
    if idx == 33
        if fieldIdx == 0
            return "Ramp up (ms)"
        endif
        if fieldIdx == 1
            return "Decay (ms)"
        endif
        if fieldIdx == 2
            return "Sustain window (ms)"
        endif
    endif
    if idx == 56
        if fieldIdx == 0
            return "Volume (%)"
        endif
    endif
    if idx == 57
        if fieldIdx == 0
            return "Ramp up (ms)"
        endif
        if fieldIdx == 1
            return "Decay (ms)"
        endif
        if fieldIdx == 2
            return "Sustain window (ms)"
        endif
    endif
    return ""
EndFunction

int Function GetEffectExtraFieldMin(int idx, int fieldIdx)
    if idx == 33
        if fieldIdx == 0
            return 1
        endif
        if fieldIdx == 1
            return 1
        endif
        if fieldIdx == 2
            return 0
        endif
    endif
    if idx == 56
        return 0
    endif
    if idx == 57
        if fieldIdx == 0
            return 1
        endif
        if fieldIdx == 1
            return 1
        endif
        if fieldIdx == 2
            return 0
        endif
    endif
    return 0
EndFunction

int Function GetEffectExtraFieldMax(int idx, int fieldIdx)
    if idx == 33
        if fieldIdx == 0
            return 2000
        endif
        if fieldIdx == 1
            return 5000
        endif
        if fieldIdx == 2
            return 2000
        endif
    endif
    if idx == 56
        return 100
    endif
    if idx == 57
        if fieldIdx == 0
            return 2000
        endif
        if fieldIdx == 1
            return 5000
        endif
        if fieldIdx == 2
            return 2000
        endif
    endif
    return 100
EndFunction

int Function GetEffectExtraFieldStep(int idx, int fieldIdx)
    if idx == 33
        return 10
    endif
    if idx == 56
        return 5
    endif
    if idx == 57
        return 10
    endif
    return 1
EndFunction

int Function GetEffectExtraFieldDefault(int idx, int fieldIdx)
    if idx == 33
        if fieldIdx == 0
            return 150
        endif
        if fieldIdx == 1
            return 500
        endif
        if fieldIdx == 2
            return 800
        endif
    endif
    if idx == 56
        return 100
    endif
    if idx == 57
        ; CastListener re-dispatches at 0.1s; retrig 250ms gives ~2.5x safety
        ; margin so a slow Papyrus tick doesn't let the lane decay mid-cast.
        if fieldIdx == 0
            return 200  ; rampms — quicker glow-on than hits
        endif
        if fieldIdx == 1
            return 600  ; decayms — smooth fade once cast ends
        endif
        if fieldIdx == 2
            return 250  ; retrigms — must exceed 100ms re-dispatch interval
        endif
    endif
    return 0
EndFunction

; Extras-as-dropdown API (v0.1.x) — plugins return >0 from
; GetEffectExtraFieldMenuOptionCount(idx, fieldIdx) to render an extra
; field as a dropdown rather than a numeric slider. Currently unused (the
; shader.play `sound` toggle that originally motivated this API was dropped
; once we discovered vanilla EffectShader audio is baked into the visual
; itself — see KNOWLEDGEBASE). Hooks kept on the abstract MTF_Plugin base
; so any future plugin's enum-style extra can adopt the dropdown UI without
; another schema change.
int Function GetEffectExtraFieldMenuOptionCount(int idx, int fieldIdx)
    return 0
EndFunction

int Function GetEffectExtraFieldMenuOptionValue(int idx, int fieldIdx, int optionIdx)
    return 0
EndFunction

string Function GetEffectExtraFieldMenuOptionLabel(int idx, int fieldIdx, int optionIdx)
    return ""
EndFunction

; Signed-convention classifiers. Positive param = buff, negative = penalty.
; Applied magnitudes stored in mtf.shift.<idx> on the target so
; deactivate/recompute can roll them back precisely.
bool Function _isAbsShift(int idx)
    ; Additive AV shifts. Three underlying paths inside _recomputeAbsShift:
    ;   • Spell-routed (idx 18-21, 34-35): engine-managed Resist* AVs that
    ;     ignore direct ModActorValue — Fire/Frost/Shock/Magic + Disease/
    ;     Poison. Each has a paired MGEF+Spell in MagicTattoosFramework.esp;
    ;     SetNthEffectMagnitude carries the signed param.
    ;   • Direct ModActorValue, integer units: most AVs accept param as-is.
    ;     MagickaRegen/StaminaRegen/HealRegen/SpeedMult (the vanilla
    ;     *RateMult / SpeedMult set whose baseline is 100, so +N = +N
    ;     percentage points), CarryWeight, Magicka, Stamina (raw points),
    ;     all vanilla skill AVs (38-54), plus Sneak (2) for legacy slot
    ;     reasons, plus UnarmedDamage/CritChance/BowSpeed (15-17),
    ;     AbsorbChance/ReflectDamage (36-37).
    ;   • Direct ModActorValue, float-mult units (idx 7, 14 —
    ;     AttackDamageMult / WeaponSpeedMult): vanilla baseline 1.0, so
    ;     param is divided by 100 inside _recomputeAbsShift via
    ;     _absShiftMagnitude. param=20 means +0.2 (=20%) on the mult.
    ;
    ; Pre-v0.1.10 these were pct shifts via _recomputeShift; converted to
    ; abs to close the double-apply race. See project_papyrus_storage_before
    ; _suspend memory note. v0.1.10 also dropped the old idx 8 (modify.armor
    ; — direct DamageResist, unreliable because the engine recomputes it per
    ; frame) and shifted everything past it down by one. Use idx 27
    ; (spell.modifyArmor) for armor changes.
    return idx <= 2 || (idx >= 5 && idx <= 7) || (idx >= 11 && idx <= 21) || (idx >= 34 && idx <= 54)
EndFunction

bool Function _isAbsShiftFloatMult(int idx)
    ; AttackDamageMult / WeaponSpeedMult: vanilla baseline 1.0, not 100.
    ; param is interpreted as percent-point shift so param=20 → +0.2 on the
    ; mult (= +20% damage / +20% swing speed). Same idea as vanilla
    ; "Smithing — Damage" perk which does ModActorValue(AttackDamageMult, 0.2).
    return idx == 7 || idx == 14
EndFunction

bool Function _isToggle(int idx)
    return idx >= 22 && idx <= 24
EndFunction

bool Function _isBurstAV(int idx)
    return idx == 3 || idx == 4 || idx == 25
EndFunction

string Function _avNameFor(int idx)
    if idx < 13
        return _avNameForLow(idx)
    endif
    return _avNameForHigh(idx)
EndFunction

string Function _avNameForLow(int idx)
    if idx == 0
        return "MagickaRateMult"
    elseif idx == 1
        return "CarryWeight"
    elseif idx == 2
        return "Sneak"
    elseif idx == 3
        return "Magicka"
    elseif idx == 4
        return "Stamina"
    elseif idx == 5
        return "SpeedMult"
    elseif idx == 6
        return "StaminaRateMult"
    elseif idx == 7
        return "AttackDamageMult"
    elseif idx == 11
        return "HealRateMult"
    elseif idx == 12
        return "Magicka"
    endif
    return ""
EndFunction

string Function _avNameForHigh(int idx)
    if idx == 13
        return "Stamina"
    elseif idx == 14
        return "WeaponSpeedMult"
    elseif idx == 15
        return "UnarmedDamage"
    elseif idx == 16
        return "CriticalChance"
    elseif idx == 17
        return "BowSpeedBonus"
    elseif idx == 18
        return "ResistFire"
    elseif idx == 19
        return "ResistFrost"
    elseif idx == 20
        return "ResistShock"
    elseif idx == 21
        return "ResistMagic"
    elseif idx == 22
        return "Muffled"
    elseif idx == 23
        return "WaterBreathing"
    elseif idx == 24
        return "WaterWalking"
    elseif idx == 25
        return "Health"
    elseif idx == 34
        return "ResistDisease"
    elseif idx == 35
        ; Skyrim AV naming quirk — poison resist is "PoisonResist", not
        ; "ResistPoison" (inverted vs. ResistFire/Frost/Shock/Magic). The
        ; MGEF in the ESP uses ActorValue: PoisonResist for the same reason.
        return "PoisonResist"
    elseif idx == 36
        return "AbsorbChance"
    elseif idx == 37
        return "ReflectDamage"
    elseif idx == 38
        return "OneHanded"
    elseif idx == 39
        return "TwoHanded"
    elseif idx == 40
        ; Skyrim AV naming quirk — the Archery skill's AV is "Marksman",
        ; a leftover Morrowind/Oblivion name. The skill-tree UI says
        ; Archery; GetActorValue/ModActorValue need "Marksman".
        return "Marksman"
    elseif idx == 41
        return "Block"
    elseif idx == 42
        return "HeavyArmor"
    elseif idx == 43
        return "LightArmor"
    elseif idx == 44
        return "Smithing"
    elseif idx == 45
        return "Enchanting"
    elseif idx == 46
        return "Alchemy"
    elseif idx == 47
        return "Destruction"
    elseif idx == 48
        return "Restoration"
    elseif idx == 49
        return "Alteration"
    elseif idx == 50
        return "Illusion"
    elseif idx == 51
        return "Conjuration"
    elseif idx == 52
        ; Skyrim AV naming quirk — the Speech skill's AV is "Speechcraft",
        ; another Morrowind/Oblivion holdover. UI says Speech.
        return "Speechcraft"
    elseif idx == 53
        return "Lockpicking"
    elseif idx == 54
        return "Pickpocket"
    endif
    return ""
EndFunction

; Per-actor applied state via StorageUtil. Keys: "mtf.shift.<idx>" (signed).
; Stores the SIGNED amount we applied via ModActorValue. Deactivate/recompute
; reverts by ModActorValue(av, -prev). Per-actor so NPC subjects don't thrash
; each other. (Pre-v0.0.35 used "mtf.applied.<idx>" with positive magnitude;
; those orphaned entries are harmless under the signed convention.)
float Function _getApplied(int idx, Actor target)
    if target == None
        return 0.0
    endif
    return StorageUtil.GetFloatValue(target, "mtf.shift." + idx, 0.0)
EndFunction

Function _setApplied(int idx, Actor target, float v)
    if target == None
        return
    endif
    if v == 0.0
        StorageUtil.UnsetFloatValue(target, "mtf.shift." + idx)
    else
        StorageUtil.SetFloatValue(target, "mtf.shift." + idx, v)
    endif
EndFunction

; abs shift: signed `param` in AV points (no scaling, except _isAbsShiftFloatMult).
Function _recomputeAbsShift(int idx, Actor target, int param)
    if target == None
        return
    endif
    ; Engine-managed Resist* AVs ignore direct ModActorValue. Route through
    ; an Ability spell with ValueModifier archetype (vanilla AbResistFire
    ; pattern). Magnitude is set per-cast, signed via SetNthEffectMagnitude.
    ; idx 18-21: elemental (Fire/Frost/Shock/Magic). idx 34-35: Disease/
    ; Poison — same engine-managed quirk, same routing.
    if (idx >= 18 && idx <= 21) || idx == 34 || idx == 35
        _absShiftSpell(_resolveResistSpell(idx), target, param, idx)
        return
    endif
    string av = _avNameFor(idx)
    if av == ""
        return
    endif
    float prev = _getApplied(idx, target)
    float amt  = param as float
    if _isAbsShiftFloatMult(idx)
        ; AttackDamageMult / WeaponSpeedMult are float multipliers (baseline
        ; 1.0), not percent-baselined like the *RateMult set (baseline 100).
        ; Treat the int param as percent points → divide by 100 so param=20
        ; means +0.2 on the mult (= +20%). Storage is in the SAME float-mult
        ; units so revert math stays simple.
        amt = amt / 100.0
    endif
    ; Early-out: onTick fires every poll (10 Hz default). Without this guard
    ; we'd revert+re-apply every tick, which is wasteful and — for laggy
    ; engine-managed AVs like PoisonResist — keeps the value flickering at
    ; the poll cadence so reads return stale values for a few seconds before
    ; the engine settles.
    if prev == amt
        return
    endif
    ; CRITICAL ORDER: write _setApplied (synchronous StorageUtil) BEFORE the
    ; suspending ModActorValue calls. Without this, two concurrent stacks
    ; (e.g. spell-driven initial apply + slow-tick re-eval running its own
    ; _tickSlotEffectsForActor on the same preset) both read prev=0 from
    ; storage and both call ModActorValue(+amt), doubling the AV shift.
    ; Storage-then-mutate means the second stack reads prev=amt, hits the
    ; early-out above, and skips. The half-finished AV state during A's
    ; suspension is fine because ±amt deltas sum correctly regardless of
    ; interleaving — the invariant is "applied delta == stored value", and
    ; storage is the synchronization point. See 2026-05-21 partial-revert
    ; diag where idx 51-54 (Illusion/Conjuration/Speechcraft/Lockpicking)
    ; double-applied during TestAllNewEffects preset apply.
    if param == 0
        _setApplied(idx, target, 0.0)
    else
        _setApplied(idx, target, amt)
    endif
    if prev != 0.0
        target.ModActorValue(av, -prev)
    endif
    if param == 0
        return
    endif
    target.ModActorValue(av, amt)
EndFunction

; toggle: bind/unbind sets AV ±1 (or AddSpell/RemoveSpell for engine-managed
; AVs like WaterBreathing/WaterWalking that don't respond to direct ModAV).
; `param` is ignored; `on` = activate.
Function _recomputeToggle(int idx, Actor target, bool on)
    if target == None
        return
    endif
    ; Engine-managed AVs need an ability spell (constant-effect ability).
    ; Direct ModActorValue silently no-ops on Muffled/WaterBreathing/WaterWalking.
    if idx == 22
        _toggleSpell(_resolveMuffleSpell(), target, on, idx)
        return
    elseif idx == 23
        _toggleSpell(_resolveWaterBreathingSpell(), target, on, idx)
        return
    elseif idx == 24
        _toggleSpell(_resolveWaterWalkingSpell(), target, on, idx)
        return
    endif
    string av = _avNameFor(idx)
    if av == ""
        return
    endif
    float prev = _getApplied(idx, target)
    if on
        if prev > 0.0
            return ; already applied
        endif
        if prev < 0.0
            target.ModActorValue(av, -prev)
        endif
        target.ModActorValue(av, 1.0)
        _setApplied(idx, target, 1.0)
    else
        if prev != 0.0
            target.ModActorValue(av, -prev)
        endif
        _setApplied(idx, target, 0.0)
    endif
EndFunction

Function _toggleSpell(Spell s, Actor target, bool on, int idx)
    if s == None
        return
    endif
    float prev = _getApplied(idx, target)
    if on
        if prev > 0.0
            return ; already applied
        endif
        target.AddSpell(s, false)
        _setApplied(idx, target, 1.0)
    else
        target.RemoveSpell(s)
        _setApplied(idx, target, 0.0)
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

; Apply a signed-magnitude resist via an Ability spell. Removes first to
; clear stale magnitude, mutates the spell's effect magnitude, then re-adds.
; Early-outs when the desired magnitude already matches what we last
; applied — without this, onTick's 10 Hz cadence does RemoveSpell+AddSpell
; every poll, which keeps lazy AVs like PoisonResist flickering 0/+N for
; ~2-3s before the engine settles. Idempotent re-add was also pure churn.
Function _absShiftSpell(Spell s, Actor target, int param, int idx)
    if s == None
        return
    endif
    float prev = _getApplied(idx, target)
    float mag  = param as float
    if prev == mag
        return
    endif
    ; CRITICAL ORDER: write storage BEFORE the suspending RemoveSpell /
    ; AddSpell calls so concurrent stacks see prev=mag and hit the early-out
    ; above. Same race as _recomputeAbsShift; see comment there for details.
    if param == 0
        _setApplied(idx, target, 0.0)
    else
        _setApplied(idx, target, mag)
    endif
    target.RemoveSpell(s)
    if param == 0
        return
    endif
    s.SetNthEffectMagnitude(0, mag)
    target.AddSpell(s, false)
EndFunction

Spell Function _resolveResistSpell(int idx)
    if idx == 18
        if _resistFireSpell == None
            _resistFireSpell = Game.GetFormFromFile(0x837, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistFireSpell
    elseif idx == 19
        if _resistFrostSpell == None
            _resistFrostSpell = Game.GetFormFromFile(0x839, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistFrostSpell
    elseif idx == 20
        if _resistShockSpell == None
            _resistShockSpell = Game.GetFormFromFile(0x83B, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistShockSpell
    elseif idx == 21
        if _resistMagicSpell == None
            _resistMagicSpell = Game.GetFormFromFile(0x83D, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistMagicSpell
    elseif idx == 34
        if _resistDiseaseSpell == None
            _resistDiseaseSpell = Game.GetFormFromFile(0x851, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistDiseaseSpell
    elseif idx == 35
        if _resistPoisonSpell == None
            _resistPoisonSpell = Game.GetFormFromFile(0x853, "MagicTattoosFramework.esp") as Spell
        endif
        return _resistPoisonSpell
    endif
    return None
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

Function _tickCloak(int idx, Spell outer, Spell inner, Actor target, int paramDmg, int paramRadius, string key)
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
    int rampMs   = h.GetSlotEffectExtra(slot, effectIdx, "rampms")   as int
    int decayMs  = h.GetSlotEffectExtra(slot, effectIdx, "decayms")  as int
    int retrigMs = h.GetSlotEffectExtra(slot, effectIdx, "retrigms") as int
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

; ── Flash on Cast (v0.1.25) ─────────────────────────────────────────────────
; Mirror of _applyFlashOnHit but with a fixed "cast" tag. No class mask —
; MCM param is the peak% directly (same 0..1000 scale as flash.onhit's
; param2: 1000 = +10.0 additive at peak). Triggered by MTF_CastListener
; via MainQuest.DispatchFlashCast("cast") which calls TriggerActorFlash
; with the "cast" tag; the C++ pulse roster matches against the registered
; tag CSV. Listener re-dispatches at 0.1s while the cast is held, so the
; retrigms sustain window (default 250ms) keeps the lane lit during
; concentration/charge-and-hold casts.
Function _applyFlashOnCast(Actor target, int peakPct)
    if target == None || peakPct <= 0
        return
    endif
    MTF_MainQuest h = _host()
    if h == None
        return
    endif
    int slot      = h._getDispatchSlot()
    int effectIdx = h._getDispatchEffectIdx()
    if slot < 0 || effectIdx < 0
        return
    endif
    int rampMs   = h.GetSlotEffectExtra(slot, effectIdx, "rampms")   as int
    int decayMs  = h.GetSlotEffectExtra(slot, effectIdx, "decayms")  as int
    int retrigMs = h.GetSlotEffectExtra(slot, effectIdx, "retrigms") as int
    if rampMs   <= 0
        rampMs = 200
    endif
    if decayMs  <= 0
        decayMs = 600
    endif
    if retrigMs <= 0
        retrigMs = 250
    endif
    int dispatchBase = h._getDispatchBaseSlot()
    int dispatchArea = h._getDispatchArea()
    MTFPulse.SetActorFlash(target, dispatchBase, peakPct, rampMs, decayMs, retrigMs, "cast", dispatchArea)
EndFunction

Function _removeFlashOnCast(Actor target)
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

; ── shader.play (idx 55) — vanilla EffectShader playback ────────────────────
; param  = shader index into the curated _shaderFormId/_shaderLabel catalog
; param2 = duration in whole seconds; 0 = "until removed" (re-Play every tick
;          to survive save/load — Skyrim's EffectShader instance does not
;          persist across save load even when the engine flag says it should)
;
; All entries are vanilla Skyrim.esm SHAD (xEdit signature EFSH) records.
; FormIDs are 6-hex; load index 00 is always Skyrim.esm so GetFormFromFile
; with the bare ID + "Skyrim.esm" resolves regardless of load order.
;
; The catalog is intentionally hand-curated for visual variety — fire/frost
; cloaks, soultrap, ghost, flesh tints, healing motes, vampire/werewolf
; bursts, ward shield. Adding entries: append to BOTH _shaderFormId and
; _shaderLabel ladders and bump _shaderCount.

int Function _shaderCount()
    return 22
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

string Function _shaderLabel(int idx)
    if idx == 0
        return "Fire Cloak"
    endif
    if idx == 1
        return "Fire Burst"
    endif
    if idx == 2
        return "Frost"
    endif
    if idx == 3
        return "Frost Chillrend"
    endif
    if idx == 4
        return "Shock"
    endif
    if idx == 5
        return "Shock Storm"
    endif
    if idx == 6
        return "Stoneflesh"
    endif
    if idx == 7
        return "Ebonyflesh"
    endif
    if idx == 8
        return "Dragonhide"
    endif
    if idx == 9
        return "Soul Trap"
    endif
    if idx == 10
        return "Ghost (Ethereal)"
    endif
    if idx == 11
        return "Ghost Red"
    endif
    if idx == 12
        return "Invisibility"
    endif
    if idx == 13
        return "Muffle"
    endif
    if idx == 14
        return "Ward Shield"
    endif
    if idx == 15
        return "Reanimate"
    endif
    if idx == 16
        return "Turn Undead Flames"
    endif
    if idx == 17
        return "Heal"
    endif
    if idx == 18
        return "Absorb Health"
    endif
    if idx == 19
        return "Vampire Change"
    endif
    if idx == 20
        return "Werewolf Transform"
    endif
    if idx == 21
        return "Detect Life"
    endif
    return "Shader #" + idx
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

; ── sound.play (idx 56) — vanilla SoundDescriptor playback ──────────────────
; Curated set of 34 sounds from Skyrim.esm in two bands:
;   idx 0..17 — ambient SNDR loops (elemental concentration / hazard families).
;   idx 18..33 — short-stinger SOUNs (UI progression cues, dragon roars,
;                conjure pops).
; param picks the catalog index; param2 is duration in seconds (0 = until
; tier deactivates).
;
; The extras field "volume" (0..100%) multiplies the SNDR's intrinsic volume
; via Sound.SetInstanceVolume after Play. 100 = no change, 0 = effectively
; muted.
;
; Handle tracking is always on — Bethesda concentration SNDRs are Loop-flagged
; and would play forever without StopInstance on deactivate. Even most "sting"
; SNDRs are short enough to be safe as one-shots, but a few (Hagraven shriek,
; portal whoosh) have audible tails — tracking the handle lets the tier exit
; cut them off cleanly.
;
; Per-actor state under StorageUtil, keyed by (baseSlot, slot, effectIdx):
;   mtf.soundFx.<baseSlot>.<slot>.<eff>.id    — Sound.Play instance handle
;   mtf.soundFx.<baseSlot>.<slot>.<eff>.time  — last Play's real-time
; baseSlot inclusion keeps stacked presets from clobbering each other's
; handles when two presets bind sound.play on the same per-preset slot but
; live on different overlay bases.

int Function _soundCount()
    return 34
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

string Function _soundLabel(int idx)
    if idx == 0
        return "Fire — ready loop"
    endif
    if idx == 1
        return "Fire — secondary ready"
    endif
    if idx == 2
        return "Fire — body on fire"
    endif
    if idx == 3
        return "Fire — medium crackle"
    endif
    if idx == 4
        return "Frost — ready loop"
    endif
    if idx == 5
        return "Frost — concentration"
    endif
    if idx == 6
        return "Frost — wall hum"
    endif
    if idx == 7
        return "Shock — concentration"
    endif
    if idx == 8
        return "Shock — projectile arc"
    endif
    if idx == 9
        return "Shock — wall hum"
    endif
    if idx == 10
        return "Soul Trap — active hum"
    endif
    if idx == 11
        return "Ward — shimmer (stereo)"
    endif
    if idx == 12
        return "Ward — shimmer (mono)"
    endif
    if idx == 13
        return "Restoration — heal beam"
    endif
    if idx == 14
        return "Restoration — circle hum"
    endif
    if idx == 15
        return "Detect Life — pulse"
    endif
    if idx == 16
        return "Alteration — ready hum"
    endif
    if idx == 17
        return "Illusion — ready hum"
    endif
    ; ── Stings (one-shot stinger SOUNs, idx 18+) ────────────────────────────
    ; UI / progression cues, dragon roars, conjure pops. Short bursts, no
    ; loop tail. Pair with param2 > 0 (timed) for repeating beats, or
    ; param2 = 0 (sustain) to let the engine play once and stay quiet
    ; until the tier deactivates.
    if idx == 18
        return "UI — Level up"
    endif
    if idx == 19
        return "UI — Skill up"
    endif
    if idx == 20
        return "UI — New quest"
    endif
    if idx == 21
        return "UI — Quest update"
    endif
    if idx == 22
        return "UI — Quest complete"
    endif
    if idx == 23
        return "UI — Shout learned"
    endif
    if idx == 24
        return "UI — Shout pop (big)"
    endif
    if idx == 25
        return "UI — Perk select"
    endif
    if idx == 26
        return "UI — Journal open"
    endif
    if idx == 27
        return "Dragon — flight roar"
    endif
    if idx == 28
        return "Dragon — kill roar"
    endif
    if idx == 29
        return "Hagraven shriek"
    endif
    if idx == 30
        return "Conjure — portal open"
    endif
    if idx == 31
        return "Conjure — portal close"
    endif
    if idx == 32
        return "Conjure — bound weapon"
    endif
    if idx == 33
        return "Conjure — impact"
    endif
    return "Sound #" + idx
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
    ; Apply per-row volume mixer (extras "volume", 0..100 percent).
    ; Read from dispatch context — slot/eff already known. Default to 100
    ; if missing so unconfigured rows still play at full volume.
    MTF_MainQuest h = _host()
    if h != None
        float volPct = h.GetSlotEffectExtra(slot, eff, "volume")
        if volPct <= 0.0
            ; Either explicit 0 (mute) or unset extra (treat as 100 unless
            ; the user wrote 0). We can't tell unset apart from 0 cleanly
            ; via GetFloatValue, but the populated default is 100, so any
            ; ≤0 here means either fresh-default-not-stamped or explicit
            ; mute. Either way, skip SetInstanceVolume — Play() already
            ; runs at the SNDR's intrinsic volume.
        else
            Sound.SetInstanceVolume(handle, volPct / 100.0)
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

Function onActivate(int idx, Actor target, int param, int param2)
    if _isAbsShift(idx)
        _recomputeAbsShift(idx, target, param)
    elseif _isToggle(idx)
        _recomputeToggle(idx, target, true)
    elseif idx == 3
        _burstDelta("Magicka", target, param)
    elseif idx == 4
        _burstDelta("Stamina", target, param)
    elseif idx == 8
        if target != None
            Debug.SendAnimationEvent(target, "staggerStart")
        endif
    elseif idx == 9
        _alertNearby(target, param)
    elseif idx == 10
        _applyCostPenalty(target, param)
    elseif idx == 25
        _burstDelta("Health", target, param)
    elseif idx == 26
        _modBounty(target, param)
    elseif idx == 27
        _applyFlesh(target, param)
    elseif idx == 28
        _applyDetectAll(target, param)
    elseif idx == 29
        _applySlowTime(target, param)
    elseif idx == 30
        _applyCloak(_resolveFlameCloakSpell(), _resolveFlameCloakDmgSpell(), target, param, param2, "mtf.shift.flameCloak")
    elseif idx == 31
        _applyCloak(_resolveFrostCloakSpell(), _resolveFrostCloakDmgSpell(), target, param, param2, "mtf.shift.frostCloak")
    elseif idx == 32
        _applyCloak(_resolveLightningCloakSpell(), _resolveLightningCloakDmgSpell(), target, param, param2, "mtf.shift.lightningCloak")
    elseif idx == 33
        _applyFlashOnHit(target, param, param2)
    elseif idx == 55
        _activateShaderRow(target, param, param2)
    elseif idx == 56
        _activateSoundRow(target, param, param2)
    elseif idx == 57
        _applyFlashOnCast(target, param)
    endif
EndFunction

Function onDeactivate(int idx, Actor target, int param, int param2)
    if _isAbsShift(idx)
        _recomputeAbsShift(idx, target, 0)
    elseif _isToggle(idx)
        _recomputeToggle(idx, target, false)
    elseif idx == 10
        _removeCostPenalty(target)
    elseif idx == 27
        _removeFlesh(target)
    elseif idx == 28
        _removeDetectAll(target)
    elseif idx == 29
        _removeSlowTime(target)
    elseif idx == 30
        _removeCloak(_resolveFlameCloakSpell(), target, "mtf.shift.flameCloak")
    elseif idx == 31
        _removeCloak(_resolveFrostCloakSpell(), target, "mtf.shift.frostCloak")
    elseif idx == 32
        _removeCloak(_resolveLightningCloakSpell(), target, "mtf.shift.lightningCloak")
    elseif idx == 33
        _removeFlashOnHit(target)
    elseif idx == 55
        _deactivateShaderRow(target, param)
    elseif idx == 56
        _deactivateSoundRow(target, param, param2)
    elseif idx == 57
        _removeFlashOnCast(target)
    endif
EndFunction

Function onTick(int idx, Actor target, int param, int param2)
    if _isAbsShift(idx)
        _recomputeAbsShift(idx, target, param)
    elseif _isToggle(idx)
        _recomputeToggle(idx, target, true)
    elseif idx == 10
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
    elseif idx == 27
        ; Constant-effect ability — no time-based refresh needed. Just
        ; re-apply if magnitude (param) changed since last application.
        float stored = StorageUtil.GetFloatValue(target, "mtf.shift.flesh", -99999.0)
        if stored != (param as float)
            _applyFlesh(target, param)
        endif
    elseif idx == 28
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
    elseif idx == 29
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
    elseif idx == 30
        _tickCloak(idx, _resolveFlameCloakSpell(), _resolveFlameCloakDmgSpell(), target, param, param2, "mtf.shift.flameCloak")
    elseif idx == 31
        _tickCloak(idx, _resolveFrostCloakSpell(), _resolveFrostCloakDmgSpell(), target, param, param2, "mtf.shift.frostCloak")
    elseif idx == 32
        _tickCloak(idx, _resolveLightningCloakSpell(), _resolveLightningCloakDmgSpell(), target, param, param2, "mtf.shift.lightningCloak")
    elseif idx == 33
        ; Re-push flash params every slow tick. Cheap (one Roster lookup +
        ; field write) and means MCM slider edits on ramp/decay/retrig/peak
        ; take effect within ~2s without needing a tier rebuild.
        _applyFlashOnHit(target, param, param2)
    elseif idx == 55
        ; Re-Play shader on slow-tick to survive save/load (the engine
        ; doesn't persist EffectShader.Play state), and re-Play the bound
        ; sound when its handle is stale (session resume) or when the
        ; user opted into re-trigger mode for short SNDRs.
        _tickShaderRow(target, param, param2)
    elseif idx == 56
        ; Loop-mode SNDRs need a re-Play after session resume (same engine
        ; quirk as shaders: Sound.Play handles don't persist across save/load).
        _tickSoundRow(target, param, param2)
    elseif idx == 57
        ; Same re-push pattern as flash.onhit: cheap roster write keeps the
        ; lane's params in sync with MCM slider edits within one slow tick.
        _applyFlashOnCast(target, param)
    endif
EndFunction

; ── Legacy migration (v0.0.32 → v0.0.33) ─────────────────────────────────────
; Pre-v0.0.33, applied magnitudes lived on this script's quest as plain
; floats (_appliedMana, _appliedCarry, …). v0.0.33 moves them to per-actor
; StorageUtil so NPC subjects can carry independent state. On the version
; bump there's a one-shot: any leftover magnitude that was modded onto the
; *player's* actor values via those legacy floats must be backed out from
; the player and the legacy floats zeroed, otherwise on first recompute
; under the new code prev=0 (new key empty) and we'd stack a fresh delta on
; top of the already-applied legacy delta. Called by MTF_MainQuest version
; migration. Safe to call repeatedly — _legacyMigrated guards re-runs.
Function _migrateLegacyApplied(Actor player)
    if _legacyMigrated
        return
    endif
    if player == None
        return
    endif
    _migrateLegacyOne(0, "MagickaRateMult",  _appliedMana,      player)
    _migrateLegacyOne(1, "CarryWeight",      _appliedCarry,     player)
    _migrateLegacyOne(2, "Sneak",            _appliedSneak,     player)
    _migrateLegacyOne(5, "SpeedMult",        _appliedSpeed,     player)
    _migrateLegacyOne(6, "StaminaRateMult",  _appliedStamRate,  player)
    _migrateLegacyOne(7, "AttackDamageMult", _appliedAtkDmg,    player)
    _migrateLegacyOne(8, "DamageResist",     _appliedDmgResist, player)

    ; Spell-cost: back out any in-flight magnitude by removing the spell;
    ; onTick re-applies cleanly under per-actor tracking next loop.
    if _appliedSpellCost != 0.0
        Spell s = _resolveCostPenaltySpell()
        if s != None
            player.RemoveSpell(s)
        endif
        _appliedSpellCost = 0.0
    endif

    _appliedMana      = 0.0
    _appliedCarry     = 0.0
    _appliedSneak     = 0.0
    _appliedSpeed     = 0.0
    _appliedStamRate  = 0.0
    _appliedAtkDmg    = 0.0
    _appliedDmgResist = 0.0
    _legacyMigrated   = true
EndFunction

Function _migrateLegacyOne(int idx, string av, float legacyVal, Actor player)
    if legacyVal == 0.0
        return
    endif
    player.ModActorValue(av, legacyVal)
    StorageUtil.UnsetFloatValue(player, "mtf.applied." + idx)
EndFunction
