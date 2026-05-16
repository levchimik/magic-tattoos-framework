#pragma once

#include <RE/Skyrim.h>
#include <SKSE/SKSE.h>
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/spdlog.h>

namespace MTFPulse::log {

    inline void Setup()
    {
        auto path = SKSE::log::log_directory();
        if (!path) {
            return;
        }
        *path /= "MTFPulse.log";

        auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(path->string(), true);
        auto logger = std::make_shared<spdlog::logger>("global", std::move(sink));

#ifdef NDEBUG
        logger->set_level(spdlog::level::info);
        logger->flush_on(spdlog::level::warn);
#else
        logger->set_level(spdlog::level::trace);
        logger->flush_on(spdlog::level::trace);
#endif

        spdlog::set_default_logger(std::move(logger));
        spdlog::set_pattern("%H:%M:%S.%e [%^%l%$] %v");
    }

}  // namespace MTFPulse::log
