Scriptname _JSW_BB_Storage extends Quest ; Wnutts Updates

Actor			Property		PlayerRef						Auto		; Reference to the player character Was this in the ESM

GlobalVariable 	Property		CycleDuration					Auto		; Full duration of the menstrual cycle, eg. 28 days
GlobalVariable 	Property		BirthRace						Auto		; The race inheritance of the baby (mother = 0, father = 1, random = 2, specific = 3)
GlobalVariable 	Property		BirthRaceSpecific				Auto		; The specific unconditional race of the child
GlobalVariable	Property		VerboseMode						Auto		; Toggle for developer debug messages
GlobalVariable	Property		EventMessages					Auto		; Toggle for specific event messages (conception, birth, death, etc.)
GlobalVariable	Property		EggLife							Auto		; Duration an egg remains viable after ovulation
GlobalVariable	Property		RecoveryDuration				Auto		; Post-birth recovery duration
GlobalVariable	Property		BabyDuration					Auto		; Duration baby armor is worn before child spawn

; REMOVED: DeathMonitorAbility - replaced by Po3DeathListener (global OnActorKilled event)
; Spell			Property		DeathMonitorAbility				Auto
; REMOVED: DetectFertilityLoaderAbility - replaced by centralized _JSW_BB_DetectFertilityScript
; Spell			Property		DetectFertilityLoaderAbility	Auto		; Ability that applies shaders when Detect Fertility is cast
Spell			Property		LocationTrackerAbility			Auto		; Ability that tracks player location changes for auto-cleanup (player only)

; Animation Mods Compatibility - Single faction for DAR/OAR and other external mods
; Faction ranks: 1-100 (pregnancy), 101-115 (recovery), 116-119 (cycle phases), 0 (cleared)
; Labor is handled via FertilityModeLabor ModEvent (brief seconds-duration event, not faction rank)
; Addon mods listen for "FMR_ActorStatus" ModEvent: (Form akActor, int factionRank)
; DEPRECATED: PregnantFaction ghost record kept in ESP for save compatibility - DO NOT USE
Faction			Property		ImmersiveEffectsFaction			Auto		; Pregnancy (1-100), Recovery (101-115), Cycle (116-119), Cleared (0)

Form[] 			Property		TrackedActors					Auto		; Currently tracked female actors
Form[] 			Property		TrackedFathers					Auto		; Currently tracked male actors
Form[] 			Property		ActorBlackList					Auto		; Actors that should not be tracked
string[] 		Property		CurrentFather					Auto		; The father name of the current insemination or pregnancy
string[] 		Property		LastFather						Auto		; The father name of the previous completed pregnancy
int[] 			Property		FatherRaceId					Auto		; The current father's Race form ID from the last completed pregnancy

int[] 			Property		LastGameHoursDelta				Auto		; Random adjustment to the game hours so actors don't all have synchronized cycles

string[] 		Property		LastMotherLocation				Auto		; The last location where the female actor was encountered
string[] 		Property		LastFatherLocation				Auto		; The last location where the male actor was encountered
float[]			Property		LocationLeftTime				Auto		; Game time when player LEFT this NPC's location (0.0 = never left or currently in same location)

float[] 		Property		LastGameHours					Auto		; Game time when the actor was last updated
float[] 		Property		LastInsemination				Auto		; Game time when the actor was last inseminated (0.0 when no sperm is present)
float[] 		Property		LastOvulation					Auto		; Game time when the actor released an egg
float[] 		Property		LastConception					Auto		; Game time when the actor conceived (0.0 when not pregnant)
float[] 		Property		LastBirth						Auto		; Game time when the actor last gave birth
float[] 		Property		SpermCount						Auto		; The total amount of sperm currently active in any given female
float[] 		Property		BabyAdded						Auto		; Game time when the actor was given a baby item
bool[]			Property		ActorDead						Auto		; Tracks if actor is confirmed dead (set during polling while loaded)

string[] 		Property		PlayerChildName					Auto		; The given name of the child
int[] 			Property		PlayerChildActorIndex			Auto		; Adult actor base index for identifying which NPC to spawn
int[] 			Property		PlayerChildGender				Auto		; The gender of the child
string[] 		Property		PlayerChildRace					Auto		; The race of the child
string[] 		Property		PlayerChildClass				Auto		; The randomly selected training class for the child (Mage, Warrior, Thief, Assassin)

; Adding Training System Arrays to Narue's storage
int[] Property PlayerChildTrainingStatus Auto      ; 0=small child (available), 1=in training, 2=adult (summonable)
string[] Property PlayerChildTrainingLocation Auto ; "Jorrvaskr", "College", "Cistern", "Sanctuary"
float[] Property PlayerChildTrainingStartTime Auto ; GameTime when training started
string[] Property PlayerChildFatherName Auto       ; Father's name for appearance inheritance
int[] Property PlayerChildRaceSource Auto          ; Which parent's race was used: 0=mother, 1=father

; === NEW: Active Follower Tracking ===
Form[] Property ActiveFollowers Auto               ; Currently summoned adult followers (stored as Form)
int[] Property ActiveFollowerIndices Auto          ; Indices mapping to PlayerChildActorIndex

; === CRITICAL FIX: Persistent Spawned Actor Storage (prevents PlaceAtMe duplicates) ===
Actor[] Property SpawnedChildActorRefs Auto        ; Permanent actor references (1:1 with AdultChildren indices)

Race[]			Property		RaceBlackList					Auto		; Races excluded from tracking
Race[]			Property		BirthMotherRace					Auto		; Supported mother races (normal races only, 10 entries)
Race[]			Property		BirthMotherRaceVampire			Auto		; Supported vampire mother races (10 entries, same order as BirthMotherRace)
Race[]			Property		BirthChildRace					Auto		; Supported child races (matches BirthMotherRace)
Armor[]			Property		BirthBabyRace					Auto		; Supported baby races (matches BirthMotherRace)
ActorBase[]		Property		Children						Auto		; Supported child actor NPC bases
ActorBase[]		Property		AdultChildren					Auto		; Supported adult actor NPC bases (220 total: 11 classes × 10 races × 2 genders)

int[]			Property		EventLock						Auto		; Lock codes to avoid double-firing actor events such as labor and child spawns
bool[]			Property		FatherInseminationLock			Auto		; Lock flag to avoid multiple inseminations per father per poll

int				Property		BabyHealth = 100				Auto		; Scalar health percentage for the player's baby
int				Property		LastBabyDamage = 0				Auto		; Last damage amount taken by baby (for widget display)
float			Property		LastBabyDamageTime = 0.0		Auto		; Game time when baby last took damage (for widget display)
float			Property		LastSleep = 0.0					Auto		; The time of the last sleep for the player to assist in managing the baby's health

; Player cycle effect stat deltas (persisted through save/load)
float			Property		PlayerStaminaDelta = 0.0		Auto		; Stamina modifier applied by current cycle effect
float			Property		PlayerMagickaDelta = 0.0		Auto		; Magicka modifier applied by current cycle effect

string _updatedToVersion = ""

function UpdateStorage()
{Dynamic update for storage in the latest version}
    ; CRITICAL FIX: ALL arrays linked to TrackedActors MUST be +1 larger to prevent index desync
    ; Check if each array is the CORRECT size (TrackedActors + 1), not just different

    ; Core tracking arrays
    if (CurrentFather.Length != (TrackedActors.Length + 1))
        CurrentFather = Utility.ResizeStringArray(CurrentFather, TrackedActors.Length + 1, "")
    endIf

    if (LastFather.Length != (TrackedActors.Length + 1))
        LastFather = Utility.ResizeStringArray(LastFather, TrackedActors.Length + 1, "")
    endIf

    if (FatherRaceId.Length != (TrackedActors.Length + 1))
    	FatherRaceId = Utility.ResizeIntArray(FatherRaceId, TrackedActors.Length + 1, -1)
    endIf

    if (LastMotherLocation.Length != (TrackedActors.Length + 1))
        LastMotherLocation = Utility.ResizeStringArray(LastMotherLocation, TrackedActors.Length + 1, "")
    endIf

    if (LocationLeftTime.Length != (TrackedActors.Length + 1))
        LocationLeftTime = Utility.ResizeFloatArray(LocationLeftTime, TrackedActors.Length + 1, 0.0)
    endIf

    ; Time tracking arrays
    if (LastGameHoursDelta.Length != (TrackedActors.Length + 1))
        LastGameHoursDelta = Utility.ResizeIntArray(LastGameHoursDelta, TrackedActors.Length + 1, 0)
    endIf

    if (LastGameHours.Length != (TrackedActors.Length + 1))
        LastGameHours = Utility.ResizeFloatArray(LastGameHours, TrackedActors.Length + 1, 0.0)
    endIf

    ; Fertility cycle arrays
    if (LastInsemination.Length != (TrackedActors.Length + 1))
        LastInsemination = Utility.ResizeFloatArray(LastInsemination, TrackedActors.Length + 1, 0.0)
    endIf

    if (LastOvulation.Length != (TrackedActors.Length + 1))
        LastOvulation = Utility.ResizeFloatArray(LastOvulation, TrackedActors.Length + 1, 0.0)
    endIf

    if (LastConception.Length != (TrackedActors.Length + 1))
        LastConception = Utility.ResizeFloatArray(LastConception, TrackedActors.Length + 1, 0.0)
    endIf

    if (LastBirth.Length != (TrackedActors.Length + 1))
        LastBirth = Utility.ResizeFloatArray(LastBirth, TrackedActors.Length + 1, 0.0)
    endIf

    ; Sperm and pregnancy tracking
    if (SpermCount.Length != (TrackedActors.Length + 1))
        SpermCount = Utility.ResizeFloatArray(SpermCount, TrackedActors.Length + 1, 0.0)
    endIf

    if (BabyAdded.Length != (TrackedActors.Length + 1))
        BabyAdded = Utility.ResizeFloatArray(BabyAdded, TrackedActors.Length + 1, 0.0)
    endIf

    ; Death tracking
    if (ActorDead.Length != (TrackedActors.Length + 1))
        ActorDead = Utility.ResizeBoolArray(ActorDead, TrackedActors.Length + 1, false)
    endIf

    ; Event lock
    if (EventLock.Length != (TrackedActors.Length + 1))
        EventLock = Utility.ResizeIntArray(EventLock, TrackedActors.Length + 1, 0)
    endIf
    
    ; Add father insemination lock to current tracked fathers
    if (FatherInseminationLock.Length != TrackedFathers.Length)
    	FatherInseminationLock = Utility.ResizeBoolArray(FatherInseminationLock, TrackedFathers.Length, false)
    endIf
    
    ; === NEW: Initialize training arrays for existing children ===
    if (PlayerChildTrainingStatus.Length != PlayerChildName.Length)
        PlayerChildTrainingStatus = Utility.ResizeIntArray(PlayerChildTrainingStatus, PlayerChildName.Length, 0)
    endIf
    
    if (PlayerChildTrainingLocation.Length != PlayerChildName.Length)
        PlayerChildTrainingLocation = Utility.ResizeStringArray(PlayerChildTrainingLocation, PlayerChildName.Length, "")
    endIf
    
    if (PlayerChildTrainingStartTime.Length != PlayerChildName.Length)
        PlayerChildTrainingStartTime = Utility.ResizeFloatArray(PlayerChildTrainingStartTime, PlayerChildName.Length, 0.0)
    endIf
    
    if (PlayerChildFatherName.Length != PlayerChildName.Length)
        PlayerChildFatherName = Utility.ResizeStringArray(PlayerChildFatherName, PlayerChildName.Length, "")
    endIf

    if (PlayerChildRaceSource.Length != PlayerChildName.Length)
        PlayerChildRaceSource = Utility.ResizeIntArray(PlayerChildRaceSource, PlayerChildName.Length, 0)
    endIf

    if (PlayerChildClass.Length != PlayerChildName.Length)
        PlayerChildClass = Utility.ResizeStringArray(PlayerChildClass, PlayerChildName.Length, "Untrained")
    endIf

    if (PlayerChildActorIndex.Length != PlayerChildName.Length)
        PlayerChildActorIndex = Utility.ResizeIntArray(PlayerChildActorIndex, PlayerChildName.Length, -1)
    endIf

    if (PlayerChildRace.Length != PlayerChildName.Length)
        ; For old saves, try to infer race from the player's race as fallback
        int i = PlayerChildRace.Length
        while (i < PlayerChildName.Length)
            PlayerChildRace = Utility.ResizeStringArray(PlayerChildRace, PlayerChildRace.Length + 1, "Nord")
            i += 1
        endWhile
    endIf

    ; Initialize active follower tracking arrays if they don't exist
    if (ActiveFollowers.Length == 0)
        ActiveFollowers = Utility.ResizeFormArray(ActiveFollowers, 0)
        ActiveFollowerIndices = Utility.ResizeIntArray(ActiveFollowerIndices, 0)
    endIf

    ; Initialize persistent spawned actor storage to match AdultChildren array size
    if (SpawnedChildActorRefs.Length != AdultChildren.Length)
        Actor[] newArray = new Actor[128]  ; Max size array
        int i = 0
        ; Copy existing references
        while (i < SpawnedChildActorRefs.Length && i < newArray.Length)
            newArray[i] = SpawnedChildActorRefs[i]
            i += 1
        endWhile
        SpawnedChildActorRefs = newArray
        Debug.Trace("[FertilityMode] Initialized SpawnedChildActorRefs array with " + newArray.Length + " slots")
    endIf

    _updatedToVersion = "3.0.0"
endFunction

; === AUTO-CLEANUP handled by LocationTrackerAbility (OnLocationChange event) ===
; See _JSW_BB_LocationTrackerEffect.psc for implementation
; LocationLeftTime property still used by the location tracker

Actor function TrackedActorGet(int index)
{Get the tracked actor at the specified index}
    return TrackedActors[index] as Actor
endFunction

Actor function TrackedFatherGet(int index)
{Get the tracked father at the specified index}
    return TrackedFathers[index] as Actor
endFunction

Actor function TrackedFatherGetByName(string fatherName)
{Get the tracked father with a given display name, or None if not found}
    int index = TrackedFathers.Length
    
    while (index)
        index -= 1
        
        if ((TrackedFathers[index] as Actor).GetDisplayName() == fatherName)
            return TrackedFathers[index] as Actor
        endIf
    endWhile
    
    return none
endFunction

function TrackedActorBlock(Actor akActor)
	if (ActorBlackList.Find(akActor) != -1)
		; The specified actor is already blocked
		return
	endIf
	
	int index = ActorBlackList.Find(none)
    
    if (index == -1)
    	ActorBlackList = Utility.ResizeFormArray(ActorBlackList, ActorBlackList.Length + 1, none)
    	index = ActorBlackList.Find(none)
    endIf
    
    ActorBlackList[index] = akActor
endFunction

function TrackedActorUnblock(Actor akActor)
	int index = ActorBlackList.Find(akActor)
	
	if (index == -1)
		; The specified actor is not currently blocked
		return
	endIf
	
	ActorBlackList[index] = none
endFunction

int function TrackedActorAdd(Actor akActor)
{Try to add the specified actor to the tracking list}
    int index = TrackedActors.Find(akActor)

    ; Don't add if the actor is already being tracked
    if (index != -1)
        return index
    endIf

    ; Count actual tracked actors (non-None entries)
    int trackedCount = 0
    int countIdx = 0
    while (countIdx < TrackedActors.Length)
        if (TrackedActors[countIdx] != None)
            trackedCount += 1
        endIf
        countIdx += 1
    endWhile

    ; I'm putting a hard limit, thought about it, think it's for the best to force users to keep it cleaned up. 128 is enough
    if (trackedCount >= 128)
        Debug.Notification("[FMR] Tracking limit (128). Clean up your FMR tracking list in MCM.")
        return -1
    endIf

    index = TrackedActors.Find(none)
    
    if (index == -1)
        TrackedActors = Utility.ResizeFormArray(TrackedActors, TrackedActors.Length + 1, none)
        LastMotherLocation = Utility.ResizeStringArray(LastMotherLocation, LastMotherLocation.Length + 1, "")
        CurrentFather = Utility.ResizeStringArray(CurrentFather, CurrentFather.Length + 1, "")
        LastFather = Utility.ResizeStringArray(LastFather, LastFather.Length + 1, "")
        LastGameHoursDelta = Utility.ResizeIntArray(LastGameHoursDelta, LastGameHoursDelta.Length + 1, 0)
        LastGameHours = Utility.ResizeFloatArray(LastGameHours, LastGameHours.Length + 1, 0.0)
        LastInsemination = Utility.ResizeFloatArray(LastInsemination, LastInsemination.Length + 1, 0.0)
        LastOvulation = Utility.ResizeFloatArray(LastOvulation, LastOvulation.Length + 1, 0.0)
        LastConception = Utility.ResizeFloatArray(LastConception, LastConception.Length + 1, 0.0)
        LastBirth = Utility.ResizeFloatArray(LastBirth, LastBirth.Length + 1, 0.0)
        FatherRaceId = Utility.ResizeIntArray(FatherRaceId, FatherRaceId.Length + 1, -1)
        SpermCount = Utility.ResizeFloatArray(SpermCount, SpermCount.Length + 1, 0.0)
        BabyAdded = Utility.ResizeFloatArray(BabyAdded, BabyAdded.Length + 1, 0.0)
        EventLock = Utility.ResizeIntArray(EventLock, EventLock.Length + 1, 0)
        index = TrackedActors.Find(none)
    endIf
    
    TrackedActors[index] = akActor
    LastMotherLocation[index] = akActor.GetCurrentLocation().GetName()
    CurrentFather[index] = ""
    LastFather[index] = ""
    LastGameHoursDelta[index] = Utility.RandomInt(0, CycleDuration.GetValueInt())
    LastGameHours[index] = Utility.GetCurrentGameTime()  ; Store in DAYS (used by cycle calculations)
    LastInsemination[index] = 0.0
    LastOvulation[index] = 0.0
    LastConception[index] = 0.0
    LastBirth[index] = 0.0
    FatherRaceId[index] = -1
    SpermCount[index] = 0.0
    BabyAdded[index] = 0.0
    EventLock[index] = 0

    ; Apply monitoring abilities
    ; REMOVED: DeathMonitorAbility - Po3DeathListener handles death detection globally
    ; REMOVED: DetectFertilityLoaderAbility - replaced by centralized _JSW_BB_DetectFertilityScript
    ; The centralized script is cast as a spell effect and handles ALL actors in one loop

    ; LocationTrackerAbility applied in HandlerQuestAliasScript OnInit/OnPlayerLoadGame
    ; (Needed for both male and female players for auto-cleanup)

    ; WARNING: Check if tracking list is approaching/at limit (trackedCount already calculated above, +1 for newly added)
    trackedCount += 1
    if (trackedCount >= 90 && trackedCount < 128)
        Debug.Notification("[FM] Tracking " + trackedCount + "/128 women. Consider lowering cleanup threshold (MCM > Automation)")
    elseIf (trackedCount >= 128)
        Debug.Notification("[FM] Tracking is at MAX! Clean up Tracking List!")
    endIf

    return index
endFunction

int function TrackedFatherAdd(Actor akActor)
{Try to add the specified actor to the tracking list}
    int index = TrackedFathers.Find(akActor)
    
    ; Don't add if the actor is already being tracked
    if (index != -1)
        return index
    endIf
    
    index = TrackedFathers.Find(none)
    
    if (index == -1)
        TrackedFathers = Utility.ResizeFormArray(TrackedFathers, TrackedFathers.Length + 1, none)
        LastFatherLocation = Utility.ResizeStringArray(LastFatherLocation, LastFatherLocation.Length + 1, "")
        FatherInseminationLock = Utility.ResizeBoolArray(FatherInseminationLock, FatherInseminationLock.Length + 1, false)
        index = TrackedFathers.Find(none)
    endIf
    
    TrackedFathers[index] = akActor
    LastFatherLocation[index] = akActor.GetCurrentLocation().GetName()
    FatherInseminationLock[index] = false
    
    return index
endFunction

bool function TrackedActorRemove(int index, string callingFunction = "UNKNOWN")
{Remove the tracked actor at the specified index}
    if (index >= 0 && index < TrackedActors.Length)
        Actor removedActor = TrackedActors[index] as Actor

        ; PROTECTION: Block removal for pregnant or inseminated women UNLESS they are dead
        ; Death overrides all protection
        bool allowRemoval = false

        if (removedActor)
            ; Actor is loaded - check if dead
            if (removedActor.IsDead())
                allowRemoval = true
                ActorDead[index] = true  ; Store death status for later when unloaded
                if (VerboseMode.GetValueInt())
                    Debug.Trace("[FertilityMode] Actor is DEAD - death overrides protection - " + callingFunction)
                endIf
            endIf
        else
            ; Actor is None/unloaded - check stored death flag
            if (ActorDead[index])
                allowRemoval = true
                if (VerboseMode.GetValueInt())
                    Debug.Trace("[FertilityMode] Actor UNLOADED but marked DEAD - death overrides protection - " + callingFunction)
                endIf
            elseIf (VerboseMode.GetValueInt())
                Debug.Trace("[FertilityMode] Actor is None/unloaded - checking protection status - " + callingFunction)
            endIf
        endIf

        ; If NOT explicitly allowed (dead), check protection status
        if (!allowRemoval)
            if (LastConception[index] > 0.0)
                if (VerboseMode.GetValueInt())
                    Debug.Trace("[FertilityMode] REMOVAL BLOCKED: Actor is PREGNANT - " + callingFunction)
                    Debug.Notification("REMOVAL BLOCKED: PREGNANT woman cannot be removed!")
                endIf
                return false
            endIf

            if (LastInsemination[index] > 0.0 && CurrentFather[index] != "")
                if (VerboseMode.GetValueInt())
                    Debug.Trace("[FertilityMode] REMOVAL BLOCKED: Actor has SPERM + FATHER - " + callingFunction)
                    Debug.Notification("REMOVAL BLOCKED: Woman with father cannot be removed (Sperm: " + (SpermCount[index] as int) + ", Father: " + CurrentFather[index] + ")")
                endIf
                return false
            endIf
        endIf

        string actorName = "NONE/UNLOADED"
        string statusMsg = ""

        ; Build status message from data arrays (works even if actor is None/unloaded)
        if (LastConception[index] > 0.0)
            float daysPregnant = (Utility.GetCurrentGameTime() - LastConception[index])
            statusMsg = " [PREGNANT " + (daysPregnant as int) + " days]"
        elseIf (LastInsemination[index] > 0.0)
            statusMsg = " [Inseminated, Sperm:" + (SpermCount[index] as int) + "]"
        elseIf (LastOvulation[index] > 0.0)
            statusMsg = " [Ovulating]"
        endIf

        ; Get actor name if loaded, otherwise use father name as hint
        if (removedActor)
            actorName = removedActor.GetDisplayName()
        elseIf (CurrentFather[index] != "")
            actorName = "UNLOADED (Father:" + CurrentFather[index] + ")"
        endIf

        ; EventMessages death notifications handled by CleanupDeadActor only
        ; ("X has perished", "X and their child have perished")

        ; VerboseMode: Technical debug info for modders
        if (VerboseMode.GetValueInt())
            Debug.Notification("REMOVED: " + actorName + statusMsg + " | Reason:" + callingFunction)
            Debug.Trace("[FertilityMode] ===== ACTOR REMOVED ===== ")
            Debug.Trace("[FertilityMode]   Actor: " + actorName)
            Debug.Trace("[FertilityMode]   Status: " + statusMsg)
            Debug.Trace("[FertilityMode]   CallingFunction: " + callingFunction)
            Debug.Trace("[FertilityMode]   Index: " + index)
            Debug.Trace("[FertilityMode]   CurrentFather: " + CurrentFather[index])
            Debug.Trace("[FertilityMode]   LastFather: " + LastFather[index])
            Debug.Trace("[FertilityMode]   SpermCount: " + (SpermCount[index] as int))
            Debug.Trace("[FertilityMode]   LastConception: " + LastConception[index])
            Debug.Trace("[FertilityMode]   LastOvulation: " + LastOvulation[index])
            Debug.Trace("[FertilityMode] ======================= ")
        endIf

        TrackedActors[index] = none
        return true
    endIf

    return false
endFunction

bool function TrackedFatherRemove(int index)
{Remove the tracked actor at the specified index}
    if (index >= 0 && index < TrackedFathers.Length)
        TrackedFathers[index] = none
        return true
    endIf
    
    return false
endFunction

function TrackedActorClear()
{Removes all entries and shrinks arrays to 0 length}
	TrackedActors = Utility.ResizeFormArray(TrackedActors, 0, none)
    LastMotherLocation = Utility.ResizeStringArray(LastMotherLocation, 0, "")
    CurrentFather = Utility.ResizeStringArray(CurrentFather, 0, "")
    LastFather = Utility.ResizeStringArray(LastFather, 0, "")
    LastGameHoursDelta = Utility.ResizeIntArray(LastGameHoursDelta, 0, 0)
    LastGameHours = Utility.ResizeFloatArray(LastGameHours, 0, 0.0)
    LastInsemination = Utility.ResizeFloatArray(LastInsemination, 0, 0.0)
    LastOvulation = Utility.ResizeFloatArray(LastOvulation, 0, 0.0)
    LastConception = Utility.ResizeFloatArray(LastConception, 0, 0.0)
    LastBirth = Utility.ResizeFloatArray(LastBirth, 0, 0.0)
    FatherRaceId = Utility.ResizeIntArray(FatherRaceId, 0, -1)
    SpermCount = Utility.ResizeFloatArray(SpermCount, 0, 0.0)
    BabyAdded = Utility.ResizeFloatArray(BabyAdded, 0, 0.0)
    EventLock = Utility.ResizeIntArray(EventLock, 0, 0)
endFunction

function TrackedFatherClear()
{Removes all entries and shrinks arrays to 0 length}
	TrackedFathers = Utility.ResizeFormArray(TrackedFathers, 0, none)
	LastFatherLocation = Utility.ResizeStringArray(LastFatherLocation, 0, "")
	FatherInseminationLock = Utility.ResizeBoolArray(FatherInseminationLock, 0, false)
endFunction

function PlayerChildAdd(Actor akActor, string name, int gender, string fatherName, int raceIndex, int raceSource)
{Adds a child birth record - now supports all 4 classes and stores father info and race source}

    ; Add child name
    PlayerChildName = Utility.ResizeStringArray(PlayerChildName, PlayerChildName.Length + 1, name)
    PlayerChildGender = Utility.ResizeIntArray(PlayerChildGender, PlayerChildGender.Length + 1, gender)

    ; Store father name for tracking
    PlayerChildFatherName = Utility.ResizeStringArray(PlayerChildFatherName, PlayerChildFatherName.Length + 1, fatherName)

    ; Store which parent's race was used (0=mother, 1=father, 2=random, 3=specific)
    PlayerChildRaceSource = Utility.ResizeIntArray(PlayerChildRaceSource, PlayerChildRaceSource.Length + 1, raceSource)

    ; Initialize training status as "small child" (0)
    PlayerChildTrainingStatus = Utility.ResizeIntArray(PlayerChildTrainingStatus, PlayerChildTrainingStatus.Length + 1, 0)
    PlayerChildTrainingLocation = Utility.ResizeStringArray(PlayerChildTrainingLocation, PlayerChildTrainingLocation.Length + 1, "")
    PlayerChildTrainingStartTime = Utility.ResizeFloatArray(PlayerChildTrainingStartTime, PlayerChildTrainingStartTime.Length + 1, 0.0)

    ; Store class as placeholder (will be set during training selection)
    ; For now, default to "Untrained"
    PlayerChildClass = Utility.ResizeStringArray(PlayerChildClass, PlayerChildClass.Length + 1, "Untrained")

    ; Store race name and placeholder actor index
    Race childRace = BirthMotherRace[raceIndex]
    string childRaceName = childRace.GetName()

    ; Actor index will be determined when training is selected
    ; For now, use -1 as placeholder
    PlayerChildActorIndex = Utility.ResizeIntArray(PlayerChildActorIndex, PlayerChildActorIndex.Length + 1, -1)
    PlayerChildRace = Utility.ResizeStringArray(PlayerChildRace, PlayerChildRace.Length + 1, childRaceName)
endFunction

function PlayerChildRemove(int childIndex)
{Removes a child from all tracking arrays (e.g., sent to Honorhall Orphanage)}

    ; Validate index
    if (childIndex < 0 || childIndex >= PlayerChildName.Length)
        Debug.Trace("[FertilityMode] PlayerChildRemove: Invalid child index " + childIndex)
        return
    endIf

    ; Get current array length
    int oldLength = PlayerChildName.Length
    int newLength = oldLength - 1

    ; If removing the only child, just clear all arrays
    if (newLength == 0)
        PlayerChildName = Utility.ResizeStringArray(PlayerChildName, 0, "")
        PlayerChildGender = Utility.ResizeIntArray(PlayerChildGender, 0, 0)
        PlayerChildFatherName = Utility.ResizeStringArray(PlayerChildFatherName, 0, "")
        PlayerChildRaceSource = Utility.ResizeIntArray(PlayerChildRaceSource, 0, 0)
        PlayerChildTrainingStatus = Utility.ResizeIntArray(PlayerChildTrainingStatus, 0, 0)
        PlayerChildTrainingLocation = Utility.ResizeStringArray(PlayerChildTrainingLocation, 0, "")
        PlayerChildTrainingStartTime = Utility.ResizeFloatArray(PlayerChildTrainingStartTime, 0, 0.0)
        PlayerChildClass = Utility.ResizeStringArray(PlayerChildClass, 0, "")
        PlayerChildActorIndex = Utility.ResizeIntArray(PlayerChildActorIndex, 0, 0)
        PlayerChildRace = Utility.ResizeStringArray(PlayerChildRace, 0, "")
        return
    endIf

    ; Create new arrays without the removed child
    string[] newNames = Utility.CreateStringArray(newLength, "")
    int[] newGenders = Utility.CreateIntArray(newLength, 0)
    string[] newFatherNames = Utility.CreateStringArray(newLength, "")
    int[] newRaceSources = Utility.CreateIntArray(newLength, 0)
    int[] newTrainingStatus = Utility.CreateIntArray(newLength, 0)
    string[] newTrainingLocations = Utility.CreateStringArray(newLength, "")
    float[] newTrainingStartTimes = Utility.CreateFloatArray(newLength, 0.0)
    string[] newClasses = Utility.CreateStringArray(newLength, "")
    int[] newActorIndices = Utility.CreateIntArray(newLength, 0)
    string[] newRaces = Utility.CreateStringArray(newLength, "")

    ; Copy all data except the removed index
    int newIndex = 0
    int i = 0
    while (i < oldLength)
        if (i != childIndex)
            newNames[newIndex] = PlayerChildName[i]
            newGenders[newIndex] = PlayerChildGender[i]
            newFatherNames[newIndex] = PlayerChildFatherName[i]
            newRaceSources[newIndex] = PlayerChildRaceSource[i]
            newTrainingStatus[newIndex] = PlayerChildTrainingStatus[i]
            newTrainingLocations[newIndex] = PlayerChildTrainingLocation[i]
            newTrainingStartTimes[newIndex] = PlayerChildTrainingStartTime[i]
            newClasses[newIndex] = PlayerChildClass[i]
            newActorIndices[newIndex] = PlayerChildActorIndex[i]
            newRaces[newIndex] = PlayerChildRace[i]
            newIndex += 1
        endIf
        i += 1
    endWhile

    ; Replace old arrays with new ones
    PlayerChildName = newNames
    PlayerChildGender = newGenders
    PlayerChildFatherName = newFatherNames
    PlayerChildRaceSource = newRaceSources
    PlayerChildTrainingStatus = newTrainingStatus
    PlayerChildTrainingLocation = newTrainingLocations
    PlayerChildTrainingStartTime = newTrainingStartTimes
    PlayerChildClass = newClasses
    PlayerChildActorIndex = newActorIndices
    PlayerChildRace = newRaces

    Debug.Trace("[FertilityMode] Removed child at index " + childIndex + " from tracking")
endFunction

; === NEW: Follower Management Functions ===

bool function IsChildCurrentlyFollowing(int childActorIndex)
{Check if a child with the given actor index is currently summoned}
    return ActiveFollowerIndices.Find(childActorIndex) != -1
endFunction

function AddFollower(Actor follower, int childActorIndex)
{Add a follower to the active tracking}
    ActiveFollowers = Utility.ResizeFormArray(ActiveFollowers, ActiveFollowers.Length + 1)
    ActiveFollowers[ActiveFollowers.Length - 1] = follower as Form

    ActiveFollowerIndices = Utility.ResizeIntArray(ActiveFollowerIndices, ActiveFollowerIndices.Length + 1)
    ActiveFollowerIndices[ActiveFollowerIndices.Length - 1] = childActorIndex
endFunction

function RemoveFollower(int childActorIndex)
{Dismiss a specific follower - uses vanilla dismiss logic, then disables for re-summoning}
    int index = ActiveFollowerIndices.Find(childActorIndex)

    if (index != -1)
        Actor follower = ActiveFollowers[index] as Actor

        if (follower)
            ; Remove from follower faction using SetPlayerTeammate
            ; Setting both params to false = dismisses without dialogue
            follower.SetPlayerTeammate(false, false)
            follower.EvaluatePackage()  ; Make them evaluate their AI package

            ; Disable the actor so they don't wander around (keeps them in memory for re-summoning)
            follower.Disable()
            ; DO NOT DELETE - actor stored in SpawnedChildActorRefs for re-summoning

            Debug.Trace("[FertilityMode] Dismissed follower at childActorIndex=" + childActorIndex + ", removed from follower faction")
        endIf

        ; Remove from active tracking arrays
        ActiveFollowers[index] = none
        ActiveFollowerIndices[index] = -1
    endIf
endFunction

function RemoveAllFollowers()
{Dismiss all currently summoned followers - uses vanilla dismiss logic, then disables for re-summoning}
    int i = ActiveFollowers.Length

    while (i > 0)
        i -= 1

        Actor follower = ActiveFollowers[i] as Actor
        if (follower)
            ; Remove from follower faction using SetPlayerTeammate
            follower.SetPlayerTeammate(false, false)
            follower.EvaluatePackage()

            ; Disable the actor
            follower.Disable()
            ; DO NOT DELETE - actors stored in SpawnedChildActorRefs for re-summoning
        endIf
    endWhile

    ; Clear active tracking arrays
    ActiveFollowers = Utility.ResizeFormArray(ActiveFollowers, 0)
    ActiveFollowerIndices = Utility.ResizeIntArray(ActiveFollowerIndices, 0)

    Debug.Trace("[FertilityMode] Dismissed all followers, follower count reset")
endFunction

int function GetFollowerCount()
{Return the number of currently active followers}
    int count = 0
    int i = ActiveFollowers.Length
    
    while (i > 0)
        i -= 1
        
        if (ActiveFollowers[i])
            count += 1
        endIf
    endWhile
    
    return count
endFunction

function CleanupDeadActor(Actor deadActor, int actorIndex)
{Centralized cleanup for dead/inactive actors - called by Po3 death listener}

    ; Validate index
    if (actorIndex < 0 || actorIndex >= TrackedActors.Length)
        Debug.Trace("[FM-Cleanup] ERROR: Invalid index " + actorIndex)
        return
    endIf

    ; Get actor info for logging/notifications
    string actorName = "Unknown"
    if (deadActor)
        actorName = deadActor.GetDisplayName()
    endIf

    string fatherName = ""
    bool wasPregnant = false
    bool hadBaby = false

    ; Check pregnancy/baby status BEFORE clearing (for notifications)
    if (actorIndex < LastConception.Length && LastConception[actorIndex] > 0.0)
        wasPregnant = true
        if (actorIndex < CurrentFather.Length)
            fatherName = CurrentFather[actorIndex]
        endIf
    endIf

    if (actorIndex < BabyAdded.Length && BabyAdded[actorIndex] > 0.0)
        hadBaby = true
    endIf

    ; Clear all pregnancy data (bounds-checked for safety)
    if (actorIndex < LastConception.Length)
        LastConception[actorIndex] = 0.0
    endIf
    if (actorIndex < LastBirth.Length)
        LastBirth[actorIndex] = 0.0
    endIf
    if (actorIndex < LastInsemination.Length)
        LastInsemination[actorIndex] = 0.0
    endIf
    if (actorIndex < LastOvulation.Length)
        LastOvulation[actorIndex] = 0.0
    endIf
    if (actorIndex < LastFather.Length)
        LastFather[actorIndex] = ""
    endIf
    if (actorIndex < CurrentFather.Length)
        CurrentFather[actorIndex] = ""
    endIf
    if (actorIndex < SpermCount.Length)
        SpermCount[actorIndex] = 0.0
    endIf
    if (actorIndex < LastGameHours.Length)
        LastGameHours[actorIndex] = 0.0
    endIf
    if (actorIndex < LastGameHoursDelta.Length)
        LastGameHoursDelta[actorIndex] = 0
    endIf
    if (actorIndex < LastMotherLocation.Length)
        LastMotherLocation[actorIndex] = ""
    endIf
    if (actorIndex < ActorDead.Length)
        ActorDead[actorIndex] = true
    endIf
    if (actorIndex < BabyAdded.Length)
        BabyAdded[actorIndex] = 0.0
    endIf
    if (actorIndex < FatherRaceId.Length)
        FatherRaceId[actorIndex] = -1
    endIf

    ; Remove baby armor from corpse (if actor still exists and is dead)
    if (deadActor && deadActor.IsDead())
        int n = BirthBabyRace.Length
        while (n)
            n -= 1
            if (deadActor.GetItemCount(BirthBabyRace[n]) > 0)
                deadActor.RemoveItem(BirthBabyRace[n], 1, true)  ; Silent removal
            endIf
        endWhile
    endIf

    ; Remove from tracking array
    TrackedActors[actorIndex] = None

    ; EVENT MESSAGE #7: Mother/child death
    if (deadActor && deadActor.IsDead() && EventMessages.GetValueInt())
        bool isPlayerChild = (fatherName == PlayerRef.GetDisplayName())

        if (wasPregnant && fatherName != "")
            if (isPlayerChild)
                Debug.Notification(actorName + " and your child have perished.")
            else
                Debug.Notification(actorName + " and their child have perished.")
            endIf
        elseIf (hadBaby)
            Debug.Notification(actorName + " and their baby have perished.")
        else
            Debug.Notification(actorName + " has perished.")
        endIf
    endIf

    ; Clear faction rank for DAR/OAR
    if (deadActor && ImmersiveEffectsFaction)
        deadActor.SetFactionRank(ImmersiveEffectsFaction, 0)
    endIf

    ; Fire mother death event for external mods (2 second delay to avoid cascade with Po3)
    if (deadActor)
        int deathHandle = ModEvent.Create("FMR_MotherDeath")
        if (deathHandle)
            ModEvent.PushForm(deathHandle, deadActor)
            ModEvent.PushInt(deathHandle, wasPregnant as int)   ; Was pregnant
            ModEvent.PushInt(deathHandle, hadBaby as int)       ; Had baby
            ModEvent.Send(deathHandle)
        endIf
    endIf

    Debug.Trace("[FM-Cleanup] Cleaned up actor: " + actorName + " (index=" + actorIndex + ")")
endFunction

int function GetCycleDay(Actor akActor)
{Returns the current cycle day (0 to CycleDuration) for a tracked actor}
    int index = TrackedActors.Find(akActor)
    if (index == -1)
        return 0
    endIf

    return Math.Ceiling(LastGameHours[index] + LastGameHoursDelta[index]) % (CycleDuration.GetValueInt() + 1)
endFunction