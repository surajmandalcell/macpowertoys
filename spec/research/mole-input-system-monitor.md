# Mole, Input Devices, and System Monitor research

Research date: 2026-08-23

This note records platform and distribution constraints before implementation. It uses the
Mole project's official repository and Apple public documentation or Apple open-source
headers as primary sources.

## Decisions

1. **Integrate Mole as an optional external dependency first.** Detect a supported `mo`
   installation and offer a user-approved install of a pinned stable release. Do not embed
   Mole in MacPowerToys by default.
2. **Do not promise exact per-device scroll policies in the first Input Devices release.**
   Public APIs can enumerate exact HID devices and can modify global scroll events, but the
   mutable event does not expose a documented general mouse or trackpad device identifier.
3. **Build System Monitor from cumulative native counters.** Use one sampler, delta-based
   rates, and a minimal menu-bar mode. Start detailed collectors only while the main window
   is visible.

## Mole

### Official feature set

The official [V1.52.0 README](https://github.com/tw93/Mole/blob/V1.52.0/README.md)
documents these command families:

- `clean`: known-safe caches, logs, temporary files, developer artifacts, and orphaned
  leftovers.
- `uninstall`: an app and provably related files, with safeguards for shared data.
- `optimize`: bounded maintenance for Finder, network, databases, metadata, and supported
  macOS services.
- `analyze`: interactive disk drill-down, filtering, multi-select, Finder preview, and
  removal through Trash. External volumes are opt-in.
- `status`: CPU, GPU, memory, disk, network, power, temperature, fans, processes, and a
  health summary.
- `purge`: rebuildable project artifacts with conservative defaults.
- `installer`: DMG, PKG, MPKG, ISO, XIP, and installer ZIP discovery.
- Whitelists, operation history, custom project paths, updates, Touch ID for sudo, shell
  completion, and launcher integrations.

The project provides a useful but incomplete machine-readable surface:

- `mo analyze --json <path>` returns a disk report.
- `mo status --json` returns one status snapshot.
- `mo status --watch --interval 2s` emits NDJSON.
- `mo history --json` returns operation history.
- A piped `mo uninstall --list` returns JSON.

The official interfaces for clean, optimize, purge, and installer do not provide a stable
JSON plan-and-execute contract. A complete native GUI must not scrape ANSI/TUI output or
automate interactive sudo prompts. It needs either an upstream machine-readable contract or
a maintained GPL-compatible fork. Until then, MacPowerToys can give native views to the
documented JSON surfaces and open unsupported destructive flows in a visible terminal.

### Installation and packaging

The official install routes are Homebrew or the project's
[installer](https://github.com/tw93/Mole/blob/V1.52.0/install.sh). The installer supports a
user-owned prefix, which avoids an admin-owned default location. MacPowerToys should:

1. Detect `mo`, resolve its absolute path, and verify a supported version.
2. Offer `brew install mole` when Homebrew exists.
3. Otherwise, show the exact action and install a pinned tag into a user-owned directory
   only after explicit confirmation.
4. Verify the published digest and provenance where available. Never silently execute a
   `curl | bash` pipeline.
5. Do not use the installer's `latest` token because Mole documents it as unreleased
   `main`, not the latest stable release.

Mole is not distributed as one complete executable. The
[V1.52.0 release](https://github.com/tw93/Mole/releases/tag/V1.52.0) publishes separate
`analyze` and `status` helpers, per-architecture helper archives, and checksums. The cleanup
engine remains a shell source tree installed with supporting `bin/` and `lib/` files. This
makes a single embedded-binary design impractical and adds nested-code signing, update, and
provenance work.

### License, name, and distribution

Mole's root [license](https://github.com/tw93/Mole/blob/V1.52.0/LICENSE) is GNU GPL version
3. The README and repository metadata label it `GPL-3.0`; upstream does not state a precise
`only` versus `or-later` SPDX choice consistently enough for a stricter SBOM identifier.

GPLv3 permits object-code redistribution, but a distributor must preserve notices and the
license, provide the exact Corresponding Source and relevant build/install scripts through
a permitted method, mark modifications, license Mole-derived changes under GPLv3, and add
no further restrictions. A separate unmodified subprocess may be an independent aggregate,
but the license alone does not settle whether a purpose-built, tightly coupled GUI and Mole
form one combined work. That product-specific question needs legal review before a
proprietary MacPowerToys distribution embeds Mole. This is an engineering risk assessment, not
legal advice.

The official [trademark policy](https://github.com/tw93/Mole/blob/V1.52.0/TRADEMARK.md)
reserves the Mole name and logo, requires forks to use a different name and icon, and
prohibits implying endorsement. Use a MacPowerToys-owned product name such as **System Care**
and identify “Mole CLI” only as an attributed dependency.

**Recommendation:** keep Mole optional and external. This avoids shipping a third-party GPL
payload, reduces signing and source-offer obligations, and lets MacPowerToys support a tested
version range. If MacPowerToys later ships a fork, complete legal, trademark, dependency-license,
Corresponding Source, signing, notarization, and update reviews first.

Mole's [security audit](https://github.com/tw93/Mole/blob/V1.52.0/SECURITY_AUDIT.md)
describes explicit privilege boundaries, path guards, dry runs, confirmations, and operation
logging. Most cleanup actions have no undo; analyze and the default uninstall flow use
Trash. The GUI must always show the preview, scope, exclusions, privilege requirement, and
irreversibility before execution. It must never collect a sudo password itself.

## Input Devices

### Public API map

| Need | Public API | Important constraint |
|---|---|---|
| Enumerate mouse-like and digitizer devices | [`IOHIDManagerSetDeviceMatching`](https://developer.apple.com/documentation/iokit/1438371-iohidmanagersetdevicematching), [`kIOHIDDeviceUsagePairsKey`](https://developer.apple.com/documentation/iokit/kiohiddeviceusagepairskey) | Match complete usage pairs. Apple warns that a primary usage alone may not describe a composite device. |
| Read identity and connection properties | [`IOHIDDeviceGetProperty`](https://developer.apple.com/documentation/iokit/1588648-iohiddevicegetproperty), [`kIOHIDTransportKey`](https://developer.apple.com/documentation/iokit/kiohidtransportkey), [`kIOHIDLocationIDKey`](https://developer.apple.com/documentation/iokit/kiohidlocationidkey), [`kIOHIDBuiltInKey`](https://developer.apple.com/documentation/hiddriverkit/kiohidbuiltinkey) | Product/vendor/location and built-in status support inventory and defaults. IDs can change after reconnects, so persistence needs a stable composite key plus fallback. |
| Receive values with exact HID-device provenance | [`IOHIDManagerRegisterInputValueCallback`](https://developer.apple.com/documentation/iokit/1438367-iohidmanagerregisterinputvalueca), [`IOHIDElementGetDevice`](https://developer.apple.com/documentation/iokit/1564139-iohidelementgetdevice) | This layer identifies the device, but it does not directly provide the mutable Quartz event delivered to applications. |
| Observe and modify global scroll events | [`CGEvent.tapCreate`](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29), [scroll event fields](https://developer.apple.com/documentation/coregraphics/cgeventfield) | An active session tap can replace or suppress events. An [`NSEvent` global monitor](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29) only observes copies and cannot modify delivery. |
| Read vertical, horizontal, precise, and phase data | [`NSEvent`](https://developer.apple.com/documentation/appkit/nsevent), [`hasPreciseScrollingDeltas`](https://developer.apple.com/documentation/appkit/nsevent/hasprecisescrollingdeltas), [`scrollWheelEventIsContinuous`](https://developer.apple.com/documentation/coregraphics/cgeventfield/scrollwheeleventiscontinuous) | Apple states that some mice and trackpads provide precise deltas. Precision or continuity is therefore not a reliable hardware classifier. |

### Identity gap and feasible scope

**Platform inference:** public `CGEvent` scroll fields expose scroll values, phases, momentum,
and continuity, but no documented general HID source identifier. `NSEvent.deviceID` is
documented for tablet proximity, not as a general mouse/trackpad ID. Exact HID identity is
available in the separate IOHID callback. Joining the streams by timestamp is heuristic and
can fail when devices are used together.

[`kIOHIDOptionsTypeSeizeDevice`](https://developer.apple.com/documentation/iokit/1556660-anonymous/kiohidoptionstypeseizedevice)
can prevent other clients, including the system, from receiving a HID device. It could form
part of an exact per-device engine, but MacPowerToys would then have to recreate all affected
input and gestures and could leave a device unusable while active. Do not use seizure as the
default design. A virtual HID or DriverKit-based design has much higher signing, entitlement,
compatibility, and recovery risk and needs a separate architecture review.

The first release should use an honest, bounded model:

- Show distinct **Mouse** and **Trackpad** sections based on HID inventory and built-in
  properties.
- Apply vertical and horizontal inversion to the corresponding Quartz axes.
- Apply smooth scrolling only to coarse, mouse-like wheel events. Suppress the original,
  emit timed pixel events, preserve phases, and tag synthetic events so they are not handled
  twice.
- Provide `Auto`, `Mouse-like`, and `Trackpad-like` classification overrides. State that the
  policy is based on event characteristics, not guaranteed per-device provenance.
- Preserve native precise deltas and momentum for trackpad-like events.
- Do not promise arbitrary global multitouch gesture remapping. Apple documents app event
  delivery, but no public global multitouch remapping API. Scroll-axis controls are the safe
  initial scope.

Exact independent settings for two simultaneous external mice, or for a precise mouse and a
trackpad that emit similar events, are not reliable with this public-event design.

### Permissions and recovery

Apple describes [Input Monitoring](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)
as permission to monitor keyboard, mouse, or trackpad input across other apps. Accessibility
allows an app to control the Mac. Use the public preflight/request APIs instead of inferring
permission state:

- [`CGPreflightListenEventAccess`](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess%28%29)
  and `CGRequestListenEventAccess` for listening.
- [`CGPreflightPostEventAccess`](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess%28%29)
  and `CGRequestPostEventAccess` for posting.
- [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
  for Accessibility trust.
- [`IOHIDCheckAccess`](https://developer.apple.com/documentation/iokit/3181573-iohidcheckaccess)
  and [`IOHIDRequestAccess`](https://developer.apple.com/documentation/iokit/3181574-iohidrequestaccess)
  for HID listen access.

Ask only when the user enables a feature that needs the permission. Explain the reason before
the system prompt, show live permission status and an Open System Settings action, and leave
the feature safely disabled after denial or revocation. Never request these permissions at
first launch merely to populate the settings UI.

## System Monitor

### Public metric sources

| Metric | Public source | Sampling rule |
|---|---|---|
| Aggregate CPU | [`host_statistics64`](https://developer.apple.com/documentation/kernel/1502863-host_statistics64) with [`HOST_CPU_LOAD_INFO`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/host_info.h) | Calculate user/system/idle/nice tick deltas. The first sample only establishes a baseline. |
| Memory | [`HOST_VM_INFO64`](https://developer.apple.com/documentation/kernel/vm_statistics64_data_t) plus [`DispatchSourceMemoryPressure`](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure) | Report active, inactive, wired, compressed, free, and swap-aware summaries. Prefer the event source for pressure changes. |
| Disk capacity | [Foundation volume-capacity keys](https://developer.apple.com/documentation/foundation/checking-volume-storage-capacity) | Use the important/opportunistic capacity keys as appropriate. Disk-space APIs are subject to Apple's [required-reason API declaration](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api) rules and must be covered in `PrivacyInfo.xcprivacy`. |
| Disk throughput | IORegistry block-storage [`Statistics`](https://github.com/apple-oss-distributions/IOStorageFamily/blob/main/IOBlockStorageDriver.h) read with [`IORegistryEntryCreateCFProperties`](https://developer.apple.com/documentation/iokit/1514310-ioregistryentrycreatecfpropertie) | Delta cumulative byte counters. Select physical leaves carefully so virtual/nested registry nodes are not double-counted. |
| Network throughput | `PF_ROUTE`/`NET_RT_IFLIST2` and [`if_msghdr2`](https://developer.apple.com/documentation/kernel/if_msghdr2/1563988-ifm_data) | Delta 64-bit `if_data64` counters for active interfaces. [`NWPathMonitor`](https://developer.apple.com/documentation/network/nwpathmonitor) reports path state, not traffic bytes. |
| Thermal state | [`ProcessInfo.thermalState`](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property) | Event-driven state is sufficient for the menu; do not poll undocumented sensors. |

Free RAM alone is not a useful health signal. Apple's
[Activity Monitor guide](https://support.apple.com/en-ca/guide/activity-monitor/-actmntr34865/mac)
explains that memory pressure incorporates free memory, swap, wired memory, and cached files.
Use the same user-facing model.

Apple does not document a stable high-level API for system CPU temperature, fan speeds, or
complete system-wide GPU utilization. Treat these as unavailable in the guaranteed public-API
scope. Do not make undocumented SMC/private frameworks a core dependency.

### Low-overhead collection design

- Use one serial background sampler and one timer. Publish display state on the main actor.
- Offer 1, 2, 3, and 5 second menu intervals; default to 2 or 3 seconds. Set timer leeway to
  at least 10 percent. Apple's [timer energy guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)
  recommends tolerance because timer wakeups consume energy.
- When a [`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra)
  is enabled, sample only the aggregate counters needed by its selected label. Do not run
  process scans, file walks, treemap generation, SMART/SMC probes, or GPU collectors.
- Start the detailed dashboard collectors only while the main window is visible. Stop and
  release them when the window closes. Keep history in a bounded ring buffer.
- Stop the menu timer completely when the user removes the menu item. Do not keep an idle
  repeating timer.
- Prime cumulative counters on the first sample and show a placeholder until the second.
- Reset baselines after sleep/wake, interface changes, counter wrap/reset, or device removal.
  Never render a negative rate or a reconnect spike.
- Coalesce UI refreshes and pause expensive visualization updates when the window is occluded.
- Add self-observation tests using [`task_info`](https://developer.apple.com/documentation/kernel/1537934-task_info)
  to catch resource growth during long menu-bar runs.

This architecture keeps the configurable live menu useful while honoring the requirement
that detailed monitoring exists only when the main System Monitor window is open.
