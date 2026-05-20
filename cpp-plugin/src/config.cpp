#include "config.h"
#include "log.h"

#include <REL/Relocation.h>
#include <SKSE/SKSE.h>

#include <filesystem>
#include <mutex>
#include <string>

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

namespace MTFPulse::Config {

    namespace {
        std::mutex     g_iniMutex;
        std::wstring   g_iniPath;   // absolute path to MagicTattoosFramework.ini
        bool           g_loaded = false;

        // Resolve Data/SKSE/Plugins/MagicTattoosFramework.ini relative to
        // the running Skyrim install. The DLL itself lives in that same
        // folder, so we anchor on the DLL's own path — robust to MO2 /
        // Vortex / loose-file installs without needing the Skyrim root.
        std::wstring ResolveIniPath()
        {
            wchar_t buf[MAX_PATH] = {};
            HMODULE self = nullptr;
            // Use the address of ResolveIniPath itself to find the module
            // we live in. GetModuleFileName(nullptr, ...) returns the EXE,
            // not the DLL.
            ::GetModuleHandleExW(
                GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                reinterpret_cast<LPCWSTR>(&ResolveIniPath),
                &self);
            ::GetModuleFileNameW(self, buf, MAX_PATH);
            std::filesystem::path p(buf);
            p = p.parent_path() / L"MagicTattoosFramework.ini";
            return p.wstring();
        }

        // Parse "section.key" → ("section", "key"). If no dot, returns
        // ("General", key). Section/key are returned as wide strings since
        // GetPrivateProfileIntW wants PCWSTR.
        void SplitKey(std::string_view key,
                      std::wstring&    section,
                      std::wstring&    name)
        {
            auto dot = key.find('.');
            std::string_view sec;
            std::string_view nm;
            if (dot == std::string_view::npos) {
                sec = "General";
                nm  = key;
            } else {
                sec = key.substr(0, dot);
                nm  = key.substr(dot + 1);
            }
            section.assign(sec.begin(), sec.end());
            name.assign(nm.begin(),  nm.end());
        }
    }

    void Load()
    {
        std::lock_guard lock(g_iniMutex);
        g_iniPath = ResolveIniPath();
        g_loaded  = true;
        // Touch the file once so a missing INI is logged loudly. We don't
        // bail — every GetInt call has its own default that takes over
        // when the file is absent.
        const DWORD attrs = ::GetFileAttributesW(g_iniPath.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES) {
            spdlog::warn("Config: INI not found at '{}', defaults will apply",
                         std::filesystem::path(g_iniPath).string());
        } else {
            spdlog::info("Config: loaded INI from '{}'",
                         std::filesystem::path(g_iniPath).string());
        }
    }

    std::int32_t GetInt(std::string_view key, std::int32_t defaultValue)
    {
        std::lock_guard lock(g_iniMutex);
        if (!g_loaded) {
            // Defensive: GetInt called before Load(). Pull the path now
            // so we don't return the default forever.
            g_iniPath = ResolveIniPath();
            g_loaded  = true;
        }
        std::wstring section, name;
        SplitKey(key, section, name);
        const UINT v = ::GetPrivateProfileIntW(
            section.c_str(), name.c_str(),
            static_cast<INT>(defaultValue),
            g_iniPath.c_str());
        return static_cast<std::int32_t>(v);
    }

}  // namespace MTFPulse::Config
