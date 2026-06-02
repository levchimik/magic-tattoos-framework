Scriptname MTF_Plugin_Fx extends MTF_Plugin_Base
{Visual & Sound module — cosmetic effects only (flash on hit, vanilla effect
 shaders, vanilla looping sounds). Thin subclass of MTF_Plugin_Base: all
 dispatch is id-keyed and inherited unchanged; only the plugin identity differs.
 NOTE: the host's flash pulse-roster check keys on "mtf.fx:flash.onhit"
 (MTF_MainQuest._slotHasFlashEffect) — keep flash.onhit in this module unless
 you update that string too. Catalog: mtf.fx.json (tools/build_base_catalog.py).
 Part of the v0.3.9 mtf.base split.}

string Function GetPluginId()
    return "mtf.fx"
EndFunction
