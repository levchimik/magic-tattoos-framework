Scriptname MTF_Plugin_Magic extends MTF_Plugin_Base
{Magic module — ability-spell-backed effects (cloaks, resists, flesh, detect
 life, slow time, spell-cost, alteration toggles) plus "under a magic effect"
 afflictions. Thin subclass of MTF_Plugin_Base: all dispatch is id-keyed and
 inherited unchanged. This is the instance that owns the cloak damage tick —
 MTF_Plugin_Base.OnUpdate gates _cloakTickAll on GetPluginId() == "mtf.magic"
 (the actor-attached cloak flag is shared, so only one instance may tick it).
 Catalog: mtf.magic.json (tools/build_base_catalog.py). Part of the v0.3.9
 mtf.base split.}

string Function GetPluginId()
    return "mtf.magic"
EndFunction
