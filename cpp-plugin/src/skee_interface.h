// SKEE / NiOverride interface declarations.
//
// Transcribed from expired6978/SKSE64Plugins (skee64/IPluginInterface.h,
// IPluginInterface.h, OverrideVariant.h). We vendor only what we use, but
// we MUST keep the full virtual-function list of IOverrideInterface in
// order — the vtable layout is part of the ABI SKEE exposes to us.
//
// Types like TESObjectREFR are forward-declared inside our `skee` namespace
// as opaque (we never dereference them through these types). At call sites
// we reinterpret_cast RE::TESObjectREFR* → skee::TESObjectREFR*; both point
// at the same underlying game object, so the vtable dispatch into NiOverride
// works correctly regardless of how *we* name the type.

#pragma once

#include <cstdint>

namespace MTFPulse::skee {

    // Opaque forwards — never dereferenced through these pointers.
    class TESObjectREFR;
    class TESObjectARMO;
    class TESObjectARMA;
    class NiAVObject;
    class NiNode;
    class NiTransform;
    class TESForm;
    class BGSTextureSet;
    class Actor;
    class BaseExtraList;

    using skee_u64 = std::uint64_t;
    using skee_u32 = std::uint32_t;
    using skee_i32 = std::int32_t;
    using skee_u16 = std::uint16_t;
    using skee_u8  = std::uint8_t;

    class IPluginInterface
    {
    public:
        IPluginInterface() {}
        virtual ~IPluginInterface() {}
        virtual skee_u32 GetVersion() = 0;
        virtual void     Revert()     = 0;
    };

    class IInterfaceMap
    {
    public:
        virtual IPluginInterface* QueryInterface(const char* name) = 0;
        virtual bool AddInterface(const char* name, IPluginInterface* pluginInterface) = 0;
        virtual IPluginInterface* RemoveInterface(const char* name) = 0;
    };

    struct InterfaceExchangeMessage
    {
        enum : std::uint32_t {
            kMessage_ExchangeInterface = 0x9E3779B9
        };
        IInterfaceMap* interfaceMap = nullptr;
    };

    // From OverrideVariant.h. We only need kParam_ShaderEmissiveMultiple
    // and kIndexMax, but transcribe the rest for documentation.
    namespace OverrideParam {
        enum : skee_u16 {
            kParam_ShaderEmissiveColor      = 0,
            kParam_ShaderEmissiveMultiple   = 1,
            kParam_ShaderGlossiness         = 2,
            kParam_ShaderSpecularStrength   = 3,
            kParam_ShaderLightingEffect1    = 4,
            kParam_ShaderLightingEffect2    = 5,
            kParam_ShaderTextureSet         = 6,
            kParam_ShaderTintColor          = 7,
            kParam_ShaderAlpha              = 8,
            kParam_ShaderTexture            = 9,
        };
        constexpr skee_u8 kIndexMax = 0xFF;  // apply to all geometry under node
    }

    // IOverrideInterface — vtable layout MUST match SKEE's exactly. Order
    // of virtual declarations here directly determines which SKEE function
    // gets called. Do not reorder, do not omit.
    class IOverrideInterface : public IPluginInterface
    {
    public:
        enum
        {
            kPluginVersion1       = 1,
            kPluginVersion2       = 2,
            kCurrentPluginVersion = kPluginVersion2,
        };

        class GetVariant
        {
        public:
            virtual void Int(const skee_i32 i) = 0;
            virtual void Float(const float f) = 0;
            virtual void String(const char* str) = 0;
            virtual void Bool(const bool b) = 0;
            virtual void TextureSet(const BGSTextureSet* textureSet) = 0;
        };

        class SetVariant
        {
        public:
            enum class Type { None, Int, Float, String, Bool, TextureSet };
            virtual Type           GetType()    { return Type::None; }
            virtual skee_i32       Int()        { return 0; }
            virtual float          Float()      { return 0.0f; }
            virtual const char*    String()     { return nullptr; }
            virtual bool           Bool()       { return false; }
            virtual BGSTextureSet* TextureSet() { return nullptr; }
        };

        // ── Armor overrides (vtable slots — keep in order) ─────────────
        virtual bool HasArmorAddonNode(TESObjectREFR* refr, bool firstPerson, TESObjectARMO* armor, TESObjectARMA* addon, const char* nodeName, bool debug) = 0;

        virtual bool HasArmorOverride(TESObjectREFR* refr, bool isFemale, TESObjectARMO* armor, TESObjectARMA* addon, const char* nodeName, skee_u16 key, skee_u8 index) = 0;
        virtual void AddArmorOverride(TESObjectREFR* refr, bool isFemale, TESObjectARMO* armor, TESObjectARMA* addon, const char* nodeName, skee_u16 key, skee_u8 index, SetVariant& value) = 0;
        virtual bool GetArmorOverride(TESObjectREFR* refr, bool isFemale, TESObjectARMO* armor, TESObjectARMA* addon, const char* nodeName, skee_u16 key, skee_u8 index, GetVariant& visitor) = 0;
        virtual void RemoveArmorOverride(TESObjectREFR* refr, bool isFemale, TESObjectARMO* armor, TESObjectARMA* addon, const char* nodeName, skee_u16 key, skee_u8 index) = 0;
        virtual void SetArmorProperties(TESObjectREFR* refr, bool immediate) = 0;
        virtual void SetArmorProperty(TESObjectREFR* refr, bool firstPerson, TESObjectARMO* armor, TESObjectARMA* addon, const char* nodeName, skee_u16 key, skee_u8 index, SetVariant& value, bool immediate) = 0;
        virtual bool GetArmorProperty(TESObjectREFR* refr, bool firstPerson, TESObjectARMO* armor, TESObjectARMA* addon, const char* nodeName, skee_u16 key, skee_u8 index, GetVariant& value) = 0;
        virtual void ApplyArmorOverrides(TESObjectREFR* refr, TESObjectARMO* armor, TESObjectARMA* addon, NiAVObject* object, bool immediate) = 0;
        virtual void RemoveAllArmorOverrides() = 0;
        virtual void RemoveAllArmorOverridesByReference(TESObjectREFR* reference) = 0;
        virtual void RemoveAllArmorOverridesByArmor(TESObjectREFR* refr, bool isFemale, TESObjectARMO* armor) = 0;
        virtual void RemoveAllArmorOverridesByAddon(TESObjectREFR* refr, bool isFemale, TESObjectARMO* armor, TESObjectARMA* addon) = 0;
        virtual void RemoveAllArmorOverridesByNode(TESObjectREFR* refr, bool isFemale, TESObjectARMO* armor, TESObjectARMA* addon, const char* nodeName) = 0;

        // ── Node overrides ─────────────────────────────────────────────
        virtual bool HasNodeOverride(TESObjectREFR* refr, bool isFemale, const char* nodeName, skee_u16 key, skee_u8 index) = 0;
        virtual void AddNodeOverride(TESObjectREFR* refr, bool isFemale, const char* nodeName, skee_u16 key, skee_u8 index, SetVariant& value) = 0;
        virtual bool GetNodeOverride(TESObjectREFR* refr, bool isFemale, const char* nodeName, skee_u16 key, skee_u8 index, GetVariant& visitor) = 0;
        virtual void RemoveNodeOverride(TESObjectREFR* refr, bool isFemale, const char* nodeName, skee_u16 key, skee_u8 index) = 0;
        virtual void SetNodeProperties(TESObjectREFR* refr, bool immediate) = 0;
        // This is the one we actually use:
        virtual void SetNodeProperty(TESObjectREFR* refr, bool firstPerson, const char* nodeName, skee_u16 key, skee_u8 index, SetVariant& value, bool immediate) = 0;
        virtual bool GetNodeProperty(TESObjectREFR* refr, bool firstPerson, const char* nodeName, skee_u16 key, skee_u8 index, GetVariant& value) = 0;
        virtual void ApplyNodeOverrides(TESObjectREFR* refr, NiAVObject* object, bool immediate) = 0;
        virtual void RemoveAllNodeOverrides() = 0;
        virtual void RemoveAllNodeOverridesByReference(TESObjectREFR* reference) = 0;
        virtual void RemoveAllNodeOverridesByNode(TESObjectREFR* refr, bool isFemale, const char* nodeName) = 0;

        // ── Skin overrides ─────────────────────────────────────────────
        virtual bool HasSkinOverride(TESObjectREFR* refr, bool isFemale, bool firstPerson, skee_u32 slotMask, skee_u16 key, skee_u8 index) = 0;
        virtual void AddSkinOverride(TESObjectREFR* refr, bool isFemale, bool firstPerson, skee_u32 slotMask, skee_u16 key, skee_u8 index, SetVariant& value) = 0;
        virtual bool GetSkinOverride(TESObjectREFR* refr, bool isFemale, bool firstPerson, skee_u32 slotMask, skee_u16 key, skee_u8 index, GetVariant& visitor) = 0;
        virtual void RemoveSkinOverride(TESObjectREFR* refr, bool isFemale, bool firstPerson, skee_u32 slotMask, skee_u16 key, skee_u8 index) = 0;
        virtual void SetSkinProperties(TESObjectREFR* refr, bool immediate) = 0;
        virtual void SetSkinProperty(TESObjectREFR* refr, bool firstPerson, skee_u32 slotMask, skee_u16 key, skee_u8 index, SetVariant& value, bool immediate) = 0;
        virtual bool GetSkinProperty(TESObjectREFR* refr, bool firstPerson, skee_u32 slotMask, skee_u16 key, skee_u8 index, GetVariant& value) = 0;
        virtual void ApplySkinOverrides(TESObjectREFR* refr, bool firstPerson, TESObjectARMO* armor, TESObjectARMA* addon, skee_u32 slotMask, NiAVObject* object, bool immediate) = 0;
        virtual void RemoveAllSkinOverrides() = 0;
        virtual void RemoveAllSkinOverridesByReference(TESObjectREFR* reference) = 0;
        virtual void RemoveAllSkinOverridesBySlot(TESObjectREFR* refr, bool isFemale, bool firstPerson, skee_u32 slotMask) = 0;
    };

    // Concrete SetVariant for a single float value.
    class FloatVariant : public IOverrideInterface::SetVariant
    {
    public:
        explicit FloatVariant(float v) noexcept : _v(v) {}
        Type  GetType() override { return Type::Float; }
        float Float()   override { return _v; }
    private:
        float _v;
    };

}  // namespace MTFPulse::skee
