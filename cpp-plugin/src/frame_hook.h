#pragma once

namespace MTFPulse::frame_hook {

    // Install a per-frame hook by detouring BSInputDeviceManager::PollInputDevices,
    // which the game calls exactly once per frame from Main::Update().
    //
    // After install, Roster::Tick() runs on the main thread immediately after
    // the original PollInputDevices completes. Idempotent — calling twice is
    // a no-op (logged).
    //
    // Must be called AFTER kPostLoad (the SKSE address library binding only
    // resolves after that). kDataLoaded is a safe time.
    void Install();

}  // namespace MTFPulse::frame_hook
