ScriptName OThread
{MTF build-time import stub — signature-only subset of OStim Standalone's
 OThread script. Only the natives MTF_Plugin_OStim calls live here; the real
 OThread.pex ships with OStim and is what resolves at runtime. Keep signatures
 byte-identical to OStimNG/data/Scripts/Source/OThread.psc.}

Actor[] Function GetActors(int ThreadID) Global Native
