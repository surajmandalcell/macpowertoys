# Mac Tweaks request list

## Current request

- [x] Add Mac Tweaks as an on-demand MacPowerToys window with a searchable list of tweaks. Do not add a Mac Tweaks menu-bar item or tab.
- [x] Add Mic Lock as the first tweak. Keep the selected macOS input on a saved primary microphone, then three ordered fallbacks, then a safe non-wireless input.
- [x] Let users turn Mic Lock on or off, select inputs by stable device UID, and see saved devices while disconnected.
- [x] React to input changes, device connection, and wake; debounce reconnect bursts. Keep enforcement active while the app runs, even when the window is closed.
- [x] Show the current input, live mute and input volume when the device supports them, and an input-level meter only while the window is open.
- [~] Provide Refresh Devices and Revive Audio recovery actions with clear results. Revive Audio currently uses a current-user restart; protected systems need a privileged helper.
- [x] Offer MacPowerToys launch at login so an enabled Mic Lock can resume after sign-in.
- [ ] Verify device changes, permission states, and the current installed app without adding microphone controls to any menu bar.

Release and test bundles compile. The local desktop policy does not allow launching XCTest here.

Reference: [MicLock](https://github.com/WantbeFree/MicLock), whose public README describes the input order and recovery actions.
