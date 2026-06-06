Scriptname MTF_Plugin_Dragonborn extends MTF_Plugin_Base
{Dragonborn module — Thu'um voice + dragon-soul reactive conditions
 (shout.cooldown / shout.equipped / shout.learned, dragonsoul.unspent /
 dragonsoul.absorbed, word.unlocked). Thin subclass of MTF_Plugin_Base: all
 dispatch is id-keyed and inherited unchanged; only the plugin identity differs.
 Split out of mtf.magic in v0.4 so the Dragonborn fantasy can be toggled on its
 own. Catalog: mtf.dragonborn.json (tools/build_base_catalog.py).}

string Function GetPluginId()
    return "mtf.dragonborn"
EndFunction
