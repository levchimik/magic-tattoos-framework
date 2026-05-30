ScriptName OThread
{MTF build-time import stub — signature-only subset of OStim Standalone's
 OThread script. Only the natives MTF_Plugin_OStim calls live here; the real
 OThread.pex ships with OStim and is what resolves at runtime. Keep signatures
 byte-identical to OStimNG/data/Scripts/Source/OThread.psc.}

Actor[] Function GetActors(int ThreadID) Global Native

; Scene id of the scene currently running in the thread ("" if startup/ended).
; Needed by mtf.ostim:scene.tag to resolve the scene for OMetadata.HasSceneTag.
string Function GetScene(int ThreadID) Global Native

; Index of the actor within the thread, -1 if not present. Needed by
; mtf.ostim:scene.action to resolve the actor's scene position for OMetadata.
int Function GetActorPosition(int ThreadID, Actor Act) Global Native
