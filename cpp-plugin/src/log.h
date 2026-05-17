#pragma once

#include <RE/Skyrim.h>
#include <SKSE/SKSE.h>
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/spdlog.h>

#ifndef NOMINMAX
#define NOMINMAX  // ShlObj → windows.h would otherwise #define max/min and shadow std::max/std::min.
#endif
#include <ShlObj.h>
#include <filesystem>

namespace MTFPulse::log {

    // Resolve <Documents>/My Games/Skyrim Special Edition/SKSE.
    //
    // CommonLibSSE-NG v3.7.0's SKSE::log::log_directory() reads the install
    // name from an address-library relocation that, on AE 1.6.1170, points
    // at "Skyrim.INI" instead of "Skyrim Special Edition". skse64 itself
    // gets the right path, so we just hardcode the SE/AE folder name — this
    // plugin is AE-only anyway (see CMakeLists.txt comment).
    inline std::optional<std::filesystem::path> ResolveLogDir()
    {
        PWSTR raw = nullptr;
        if (FAILED(SHGetKnownFolderPath(FOLDERID_Documents, 0, nullptr, &raw)) || !raw) {
            if (raw) CoTaskMemFree(raw);
            return std::nullopt;
        }
        std::filesystem::path p{ raw };
        CoTaskMemFree(raw);
        p /= L"My Games";
        p /= L"Skyrim Special Edition";
        p /= L"SKSE";
        std::error_code ec;
        std::filesystem::create_directories(p, ec);  // no-op if exists
        return p;
    }

    inline void Setup()
    {
        auto dir = ResolveLogDir();
        if (!dir) {
            return;
        }
        const auto path = *dir / "MTFPulse.log";

        auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(path.string(), true);
        auto logger = std::make_shared<spdlog::logger>("global", std::move(sink));

        // Flush on every info+ so we can tail the log while the game's running.
        // The hot loop will be debug-level once wired, so this won't thrash.
        logger->set_level(spdlog::level::info);
        logger->flush_on(spdlog::level::info);

        spdlog::set_default_logger(std::move(logger));
        spdlog::set_pattern("%H:%M:%S.%e [%^%l%$] %v");
    }

}  // namespace MTFPulse::log
