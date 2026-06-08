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

#include <cstddef>
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
    using skee_i8  = std::int8_t;

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

    // Concrete SetVariant for a single 32-bit signed integer value. Used by
    // properties like kParam_ShaderTintColor and kParam_ShaderEmissiveColor
    // (packed 0x00RRGGBB).
    class IntVariant : public IOverrideInterface::SetVariant
    {
    public:
        explicit IntVariant(skee_i32 v) noexcept : _v(v) {}
        Type     GetType() override { return Type::Int; }
        skee_i32 Int()     override { return _v; }
    private:
        skee_i32 _v;
    };

    // ───────────────────────── v1 (legacy) ABI ─────────────────────────
    // RaceMenu 0.4.19.x (skee64 before the Jun-2023 "wrapper interface"
    // commit 7694eab) exposes the *internal* concrete OverrideInterface
    // class under QueryInterface("Override"), reporting GetVersion()==1.
    // Its vtable and SetNodeProperty signature are COMPLETELY different
    // from the v2 IOverrideInterface above — there is no SetVariant
    // wrapper; the key + index are packed INSIDE an OverrideVariant struct
    // passed by pointer, and nodeName is a BSFixedString (one interned
    // pointer) passed by value.
    //
    // Layout transcribed from skee64/OverrideVariant.h @ 8adc4b6. We only
    // ever pack int/float/color values, so `str` (a 16-byte StringTableItem
    // = std::shared_ptr) stays zero and SKEE never reads it for numeric
    // types — only the offset of `data` (8) has to be exact, which standard
    // struct layout guarantees.
    struct OverrideVariantV1
    {
        enum : skee_u8 { kType_None = 0, kType_String = 2, kType_Int = 3, kType_Float = 4, kType_Bool = 5 };

        skee_u16 key   = 0;   // + 0
        skee_u8  type  = 0;   // + 2
        skee_i8  index = -1;  // + 3   (-1 == "no controller", == v2's kIndexMax byte 0xFF)
        // 4 bytes padding -> union is 8-byte aligned (contains void*)
        union { skee_i32 i; skee_u32 u; float f; bool b; void* p; } data{};  // + 8
        void* _str0 = nullptr;  // +16  } StringTableItem (shared_ptr) — must
        void* _str1 = nullptr;  // +24  } stay null for numeric variants

        void SetFloat(skee_u16 k, skee_i8 idx, float v) { key = k; type = kType_Float; index = idx; data.f = v; }
        void SetInt  (skee_u16 k, skee_i8 idx, skee_i32 v) { key = k; type = kType_Int;   index = idx; data.i = v; }
    };
    static_assert(sizeof(OverrideVariantV1) == 32, "OverrideVariant v1 layout drift");
    static_assert(offsetof(OverrideVariantV1, data) == 8, "OverrideVariant v1 data offset");

    // v1 vtable shim. Only slot 1 (GetVersion) and slot 14 (SetNodeProperty)
    // are ever called; the intervening slots are placeholders that exist
    // solely to position SetNodeProperty at the correct offset. Order/count
    // verified against skee64/OverrideInterface.h @ 8adc4b6, with the
    // virtual destructor occupying slot 0 (confirmed empirically: MTF's v2
    // IPluginInterface — dtor@0, GetVersion@1 — reads a clean version==1
    // from this very object). DO NOT reorder or remove slots.
    //
    // nodeName is a BSFixedString passed BY VALUE (one pointer); we type it
    // as void* and hand SKEE the raw interned pointer. value is an
    // OverrideVariantV1* (key/index live inside it).
    class IOverrideInterfaceV1
    {
    public:
        virtual ~IOverrideInterfaceV1() = default;                  // 0  ~dtor
        virtual skee_u32 GetVersion() = 0;                          // 1  GetVersion
        virtual void _vf02() = 0;  // Save                          // 2
        virtual void _vf03() = 0;  // Load                          // 3
        virtual void _vf04() = 0;  // Revert                        // 4
        virtual void _vf05() = 0;  // LoadOverrides                 // 5
        virtual void _vf06() = 0;  // LoadNodeOverrides             // 6
        virtual void _vf07() = 0;  // LoadWeaponOverrides           // 7
        virtual void _vf08() = 0;  // AddRawOverride                // 8
        virtual void _vf09() = 0;  // AddOverride                   // 9
        virtual void _vf10() = 0;  // AddRawNodeOverride            // 10
        virtual void _vf11() = 0;  // AddNodeOverride               // 11
        virtual void _vf12() = 0;  // SetArmorAddonProperty         // 12
        virtual void _vf13() = 0;  // GetArmorAddonProperty         // 13
        virtual void SetNodeProperty(TESObjectREFR* refr, void* nodeName, OverrideVariantV1* value, bool immediate) = 0;  // 14
    };

}  // namespace MTFPulse::skee
