Scriptname MTF_Plugin_World extends MTF_Plugin_Base
{World & Exploration module — environment (location/weather/time), social and
 economy conditions, body-state conditions, and crime/stealth utility effects
 (blow cover, bounty). Thin subclass of MTF_Plugin_Base: all dispatch is
 id-keyed and inherited unchanged; only the plugin identity differs. Catalog:
 mtf.world.json (tools/build_base_catalog.py). Part of the v0.3.9 mtf.base split.}

string Function GetPluginId()
    return "mtf.world"
EndFunction
