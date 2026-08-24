# NetToys: Angry IP parity and SSH Anchor

Research date: 2026-08-24. This note defines product scope. It does not
authorize scanning a network without its owner's approval.

## Decision

Build a native macOS clean-room implementation. The workspace has exactly
three pages, in this order:

1. **IP Scanner**
2. **SSH Anchor**
3. **Network History**

Preferences, help, and export options use sheets, menus, or toolbars. They do
not become workspace pages.

## Clean-room boundary

Angry IP Scanner labels its source as GPLv2 and publishes the full GPLv2 text.
Treat the upstream source, tests, resources, strings, layouts, artwork, and
plugin binary format as GPL material. Do not copy, translate, link, bundle, or
derive implementation code from them. Use this behavior inventory, Apple APIs,
OpenSSH manuals, and existing MacPowerToys patterns to implement independent
Swift code. [Upstream README](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/README.md#L1-L9),
[GPLv2 license](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/LICENSE)

The clean-room parity target is independently implemented behavior. It is
reasonable to reproduce the product categories below with native Apple APIs:
target/range generation, bounded host and TCP probing, result columns and
filters, comments and favorites, safe openers, import/export, history, and
native extension points. Do not copy Java/SWT code or tests, strings or
translations, icons or layouts, the plugin ABI, serialized preferences,
sample output, or bundled vendor/OUI data. Define MacPowerToys-owned types,
formats, UI, fixtures, and names from this requirements note. If the product
ever embeds, modifies, or distributes Angry IP code, stop for a GPL packaging
and legal review; this note is engineering guidance, not legal advice.

## Page 1: IP Scanner

The official product describes local and Internet scanning, range, random, and
file inputs, multiple export formats, fetcher extensions, and a command-line
interface. Its documentation also defines feeders, fetchers, pingers,
exporters, openers, and bounded parallel work. [Official feature list](https://angryip.org/),
[official documentation](https://angryip.org/documentation/)

NetToys parity includes:

- **Targets:** one host, start/end range, CIDR or netmask, random addresses
  with a base/mask/count, and text-file import. File import accepts hostnames,
  IP addresses, and optional `host:port` targets. Accept configured TCP port
  lists/ranges and per-target ports. Save and manage favorite target sets. The
  current upstream UI registers range, random, and file feeders. [Feeder
  registration](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/config/GUIRegistry.java#L23-L31)
- **Scan controls:** Start, Stop, progress, elapsed time, live worker count,
  scan confirmation, and complete statistics. Allow bounded worker count,
  launch delay, liveness method, probe count, liveness timeout, TCP timeout,
  adaptive TCP timeout, scanning nonresponding hosts, and skipping likely
  broadcast addresses. Upstream exposes Java/ICMP reachability, UDP, TCP,
  combined unprivileged, and ARP pingers. [Pinger registry](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/core/net/PingerRegistry.java#L37-L72),
  [scanner settings](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/config/ScannerConfig.java#L13-L42)
- **Fetchers and columns:** IP, alive state and round-trip time, TTL, packet
  loss, hostname, requested TCP open ports, filtered ports, persistent
  comments, HTTP server detection, custom request/regular-expression text
  protocol detection, HTTP proxy detection, NetBIOS information, MAC address,
  and MAC vendor. Users choose and order columns and configure fetcher
  settings. The pinned registry is the source of the current built-in list.
  [Fetcher and exporter registry](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/config/ComponentRegistry.java#L20-L28)
- **Results:** sortable multi-select table; all, alive, and open-port filters;
  find; next/previous alive, dead, or open-port host; details; persistent
  comments; copy IP/details; delete; rescan; and scan statistics. Support safe
  built-in openers and user-defined openers with an explicit command preview.
  [Current command actions](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/gui/menu/CommandsMenu.java#L15-L30),
  [selection and statistics](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/gui/menu/ToolsMenu.java#L11-L34),
  [result navigation](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/gui/menu/GotoMenu.java#L8-L30)
- **Persistence and exchange:** load saved results; export all or selected rows
  as TXT, CSV, XML, IP:port list, and SQL; append when the format supports it;
  and offer equivalent CLI start, export, append, and quit-after-export
  behavior. [Load and export actions](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/gui/menu/ScanMenu.java#L8-L29),
  [CLI contract](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/config/CommandLineProcessor.java#L63-L130)
- **Ancillary parity:** saved favorites; built-in and editable openers;
  persistent scanning, port, fetcher, display, and language preferences;
  localization; user-controlled version checks and anonymous error reporting;
  and native light/dark and Retina behavior. Keep these in menus, sheets, and
  app settings, not extra workspace pages. [Favorites](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/gui/actions/FavoritesMenuActions.java#L27-L96),
  [default openers](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/config/OpenersConfig.java#L17-L37),
  [preferences](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/gui/PreferencesDialog.java#L33-L67),
  [update check](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/gui/actions/HelpMenuActions.java#L96-L150),
  [localization, dark-mode, and Retina history](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/CHANGELOG#L108-L120)
- **Extensions:** define native NetToys extension points for target generators,
  fetchers, liveness checks, exporters, and openers. Do not load Angry IP Java
  plugins. The upstream product supports plugin-supplied components, including
  pingers, but its Java ABI is outside clean-room scope. [Plugin registration](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/src/net/azib/ipscan/config/ComponentRegistry.java#L34-L45)

IPv6 parity is explicitly partial. Upstream introduced it as experimental and
incomplete, then added range progress, interface/netmask listing, file input,
and SQL export incrementally. Capability-gate each pinger and fetcher and show
**Unsupported**, rather than inventing an IPv6 value. SSH Anchor remains
IPv4-only. [IPv6 history](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/CHANGELOG#L83-L93),
[3.9.3 IPv6 additions](https://github.com/angryip/ipscan/blob/d6806bc592685c4298b82af6ec4f1fc92614093b/CHANGELOG#L9-L20)

Use `NWConnection` for nonprivileged TCP connects. It provides endpoint/port
construction, asynchronous state changes, and cancellation. [Apple
`NWConnection`](https://developer.apple.com/documentation/network/nwconnection)
Read active network state and subscribe to changes through the System
Configuration dynamic store; IPv4 interface dictionaries expose parallel
address and subnet-mask arrays. [Apple `SCDynamicStore`](https://developer.apple.com/documentation/systemconfiguration/scdynamicstore-gb2),
[Apple IPv4 entity keys](https://developer.apple.com/documentation/systemconfiguration/ipv4-entity-keys)
Version 1 does not instantiate CoreWLAN or request SSID/BSSID, so it does not
need Location authorization. If Wi-Fi details are added later, remember that
`CWInterface.bssid()` is the access point's BSSID, not a candidate device's
MAC. [Apple `CWInterface`](https://developer.apple.com/documentation/corewlan/cwinterface)

## Page 2: SSH Anchor

### Enrollment record

Each enabled anchor stores:

- SSH alias, effective target, and effective numeric port.
- A fingerprint for one eligible top-level `~/.ssh/config` `Host` stanza.
- Identity mode: **stable MAC** or **randomized MAC**.
- Stable exact MAC, or user-confirmed MAC addresses scoped to one local
  network.
- User-confirmed hostname and its normalized form.
- Last good IP, last check, last recovery, and latest exact backup reference.

The learned-MAC network scope is the active BSD interface plus its IPv4 CIDR.
A MAC learned on another scope never qualifies as same-network evidence.

Normalize a loose hostname by lowercasing it, removing one trailing dot, and
removing only a terminal `.local`. Do not use substring, edit-distance, vendor,
or SSID-only matches. In stable mode, accept only the exact canonical MAC. In
randomized mode, require both the normalized hostname and an exact MAC already
in that anchor's learned set for the current local network. A never-seen
rotated MAC can be a suggestion, but it becomes learned only after the user
confirms the device. Hostname alone never permits an automatic edit. MAC
discovery is local-link evidence; Angry IP also limits its MAC fetch to the
local network. [Official MAC fetcher description](https://angryip.org/documentation/#fetchers)

### State flow

On helper launch, wake, manual Check, and a stable active-interface/subnet
change, or config-file event, parse the raw bytes and apply the eligibility
rules below before starting any process. Each timer tick checks the enrolled
file identity/metadata; a change forces a full digest and reparse, and pauses
automatic edits until the same eligible stanza and device enrollment are
confirmed again. Then run `/usr/bin/ssh -G -F <absolute-config-path>
<alias>` with an argument array (no shell and no option-like alias). Require
its effective `hostname` and `port` to equal the two selected literal values;
also read `proxycommand` and `proxyjump` and block automatic recovery when
either changes the direct route. `-G` prints evaluated configuration and `-F`
selects the given user config instead of the system-wide file. [OpenSSH
`ssh(1)`](https://man.openbsd.org/ssh#-G), [OpenSSH
`-F`](https://man.openbsd.org/ssh#-F)

Then run this loop:

1. Every **2.5 seconds**, measured on a monotonic clock, start one direct TCP
   probe of the selected stanza's current literal IPv4 `HostName` and literal
   `Port`. Allow modest timer leeway and stagger anchors, but do not overlap
   probes for one anchor. A 1.5-second connection deadline keeps each probe
   inside its polling period. `NWConnection.State.ready` means the connection
   is established; cancel it immediately and record **Healthy**. [Apple
   `NWConnection.State.ready`](https://developer.apple.com/documentation/network/nwconnection/state-swift.enum/ready)
2. Treat refused, unreachable, and timeout as port failure. If the system path
   changed or has no usable local network, cancel and restart after the new
   path stabilizes; do not scan an obsolete subnet. If Local Network access is
   denied, record that state and stop recovery. Apple documents the
   `localNetworkDenied` path reason and retry behavior. [Apple local-network
   technote](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
3. On a real port failure, scan the active local IPv4 subnet on that exact port
   only. Try the old IP and known neighbor addresses first, then the remaining
   addresses with the limits below. Do not ping, scan common ports, send an SSH
   banner, or scan any other port. Resolve a hostname only for endpoints whose
   port connected.
4. After each successful TCP probe, run `/usr/sbin/arp -n -i <interface>
   <ipv4>` with an argument array, never a shell, and parse only a complete
   numeric neighbor-table MAC. Do not use CoreWLAN BSSID, the local interface
   MAC, vendor/OUI, or SSID as peer identity. Apple's `arp` manual defines this
   table as Internet-to-Ethernet address translations. [Apple
   `arp(8)`](https://github.com/apple-oss-distributions/network_cmds/blob/main/arp.tproj/arp.8#L34-L55)
5. Apply the enrolled evidence rule. Stable mode requires the one exact MAC.
   Randomized mode requires both the normalized hostname and a MAC already
   learned for this anchor and network. Reverse lookup can return a hostname,
   but Apple warns that a name service may supply malicious names, so a name
   never qualifies alone. [Apple `getnameinfo(3)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getnameinfo.3.html)
6. Zero matches means **Not found**; more than one means **Ambiguous**. A
   missing/incomplete neighbor entry, proxy ARP, conflicting MAC, or unseen
   randomized MAC also requires review. None permits an automatic edit.
7. For one qualifying match, recheck that the path/subnet is unchanged, the
   candidate port succeeds twice, and the old IP still fails. Re-read and
   compare the config transaction preconditions, then stage the one-token edit.
8. Atomically replace the file as below. Run the same `ssh -G -F` command
   again and require every effective field except `hostname` to match its
   pre-write value. Probe the new IP and unchanged port.
9. On success, record **Recovered**. On failure, atomically restore the backup
   only when the current hash still equals the helper-written hash. Otherwise
   preserve the user's newer edit and record **Recovery needs review**.

OpenSSH uses the first specified value for most directives. It applies
conditional `Host` and `Match` sections, and `HostName` accepts a real hostname
or numeric address. Its `Port` default is 22. [OpenSSH config precedence and
grammar](https://man.openbsd.org/ssh_config#DESCRIPTION),
[`HostName`](https://man.openbsd.org/ssh_config#HostName),
[`Port`](https://man.openbsd.org/ssh_config#Port)

### Config edit contract

- Edit only the top-level `~/.ssh/config`. It must be a user-owned, writable,
  regular file with link count one. It must not be a symbolic link. Never edit
  an included file, `/etc/ssh/ssh_config`, a generated file, or any other path.
- The selected block must be outside `Match`. It must have exactly one literal
  `Host` alias, no wildcard or negation, and exactly one unquoted literal
  numeric IPv4 `HostName` token **and exactly one direct literal `Port` in
  1...65535**. A default or inherited port is not enough. A multi-pattern
  `Host`, duplicate `HostName` or `Port`, hostname or `%` token, IPv6 target,
  included source, or value selected through `Match` is read-only. Report the
  exact reason.
- Preflight the `Include` graph only to detect conflicts before `ssh -G`.
  OpenSSH permits multiple paths, globs, relative paths, tokens, environment
  variables, and includes inside `Host` or `Match` blocks. Treat unresolved
  tokens, paths outside the user's `.ssh` directory, symlinks, nonregular
  files, unsafe ownership/mode, excess depth, and **any `Match exec` in the
  traversed graph** as blocked. Never run `ssh -G` after such a finding because
  evaluating `Match exec` runs the configured command. [OpenSSH
  `Include`](https://man.openbsd.org/ssh_config#Include), [OpenSSH
  `Match`](https://man.openbsd.org/ssh_config#Match)
- OpenSSH applies a `Host` block when a positive pattern matches and no negated
  pattern matches. NetToys intentionally blocks every multi-pattern, wildcard,
  or negated block from automatic edits. [OpenSSH `Host` patterns](https://man.openbsd.org/ssh_config#Host)
- Replace only the selected `HostName` value bytes. Preserve all other bytes,
  including indentation, keyword case, spaces or `=`, quotes, comments, line
  endings, encoding bytes, and final-newline state. Never rewrite `Host`,
  `Port`, `User`, identity, proxy, forwarding, or unknown directives. Store the
  value's raw byte range and assert
  `newData == oldPrefix + newIPv4ASCII + oldSuffix`; a test must compare every
  byte outside that range.
- Open the user's `.ssh` directory and `config` relative to a directory file
  descriptor with no-follow semantics. Reject an unsafe directory, a symlink,
  nonregular file, wrong owner, group/world-writable file, or link count other
  than one. `O_NOFOLLOW` makes `open` fail when the final component is a
  symlink. [Apple `open(2)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html)
- On the open descriptor, capture device, inode, owner/group, mode, ACLs,
  extended attributes, size, modification/change times, and a SHA-256 of the
  exact bytes. OpenSSH rejects a user config owned by neither root nor the user
  or writable by group/others. [OpenSSH permission
  check](https://github.com/openssh/openssh-portable/blob/0ef0f5a839831c213f24e3f2ae434765c607fb50/readconf.c#L2635-L2643)
- The helper is the sole NetToys writer and serializes transactions. File
  coordination is cooperative only; correctness comes from reopening with
  no-follow semantics and comparing identity, metadata, and the full digest
  immediately before commit. Any mismatch means **Concurrent edit** and no
  replacement.
- Before commit, create a transaction journal and an exact 0600 backup under
  the app's private Application Support directory. Back up bytes and the
  metadata needed for an exact restore; never log config contents. Create a
  sibling temporary file with `mkstemp`, write all bytes, apply and verify the
  original owner/mode/ACLs/xattrs, and `fsync` it. `mkstemp` uses an exclusive
  create and initially sets mode 0600. [Apple
  `mkstemp(3)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/mkstemp.3.html),
  [Apple `fsync(2)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html)
- Atomically swap the sibling temp and `config` with descriptor-relative
  `renameatx_np(..., RENAME_SWAP | RENAME_NOFOLLOW_ANY |
  RENAME_RESOLVE_BENEATH)`. If the file system cannot support the safe swap,
  refuse automatic editing. After the swap, hash the displaced original; if
  it is not the expected preimage, swap it back only while the destination is
  still the helper's exact new image. Apple's current manual defines the swap
  as atomic and the no-follow/beneath flags as path protections. [Apple
  `renameatx_np(2)`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/renameatx_np.2)
- Keep the latest 10 exact backups for 30 days, except unresolved transactions
  and their only recovery point. On launch, recover the journal: old digest
  means no commit, new digest means finish validation, and any third digest
  means preserve it and request review. Restore through the same temp/swap
  transaction and only while the current digest equals the helper-written
  digest.

### Always-bundled helper

Bundle one non-root `NetToysHelper.app` in
`Contents/Library/LoginItems`; never download or install a separate
executable. Use `SMAppService.loginItem(identifier:)`. Registration starts the
item immediately and at future logins; a crash or nonzero exit is eligible for
relaunch. [Apple login-item service](https://developer.apple.com/documentation/servicemanagement/smappservice/loginitem%28identifier%3A%29),
[Apple `register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)

Enabling NetToys is a transaction: register, require service status
`enabled`, and complete an authenticated XPC version/health handshake. Until
all three succeed, show **Needs Login Item Approval** or the exact error and do
not call NetToys enabled. `requiresApproval` opens the Login Items explanation
and System Settings route; there is no main-app monitoring or write fallback.
The helper owns scheduled probes, recovery scans, SSH config transactions, and
history; the app is an XPC UI client. Apple exposes `notRegistered`, `enabled`,
`requiresApproval`, and `notFound` states. [Apple service
status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum)

On disable, ask the helper to quiesce, cancel probes/scans, finish or recover
the current file transaction, flush history, then unregister and verify
`notRegistered`; unregistering stops the item and prevents future launches.
[Apple `unregister()`](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister%28%29)
On app update or helper version mismatch, quiesce and re-register the bundled
version, then repeat the handshake. If the user disables the item in System
Settings, mark NetToys **Needs Approval** and stop automatic work. This is the
only valid lifecycle whenever NetToys is enabled. [Apple helper update
guide](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)

## Page 3: Network History

Store local, bounded records for scanner runs and SSH Anchor transitions:

- Time, source page, trigger, interface, subnet, targets, and scanned port set.
- Result counts and saved result rows, with hostname, MAC, ports, and comments.
- Anchor pre-check, evidence, decision, config file, old/new IP, post-check,
  backup, rollback, and error. Never store private keys or SSH file contents.
- Search, filters, run comparison, details, rescan, export, clear, and Restore
  when the compare-and-swap recovery rule permits it.

Default to 30 days and at most 500 runs/events. Let the user disable retention,
clear all history, or pin selected runs. Keep history on the Mac. Do not sync or
upload it by default.

## Resource and privacy limits

- Cap enabled anchors at 16, stagger their 2.5-second checks, keep one probe in
  flight per anchor, and run only one recovery scan globally. Cancel a scan on
  path change. After failed recovery, back off rescans at 30, 60, 120, 240,
  then 300 seconds while continuing the cheap scheduled check.
- Automatic recovery may enumerate at most 1,024 addresses (an IPv4 `/22`) and
  use at most 64 concurrent TCP connects with a 400 ms discovery deadline. If
  the active subnet is larger, require a user-approved child CIDR. Always show
  address and port counts before a manual IP Scanner run.
- Use one connect per address and only the anchor's one configured port. Do not
  send application payloads during SSH Anchor discovery. Cap learned randomized
  MACs at eight per anchor/network, history at 500 unpinned events or 30 days,
  and recoverable backups at ten plus unresolved transactions.
- Ask for Local Network access only when the user starts a local scan or
  enables SSH Anchor. Add `NSLocalNetworkUsageDescription`; Apple requires it
  for direct local unicast connections on current macOS and presents the
  prompt on first local access. Trigger that first operation from the
  long-lived bundled helper so the prompt is attributed to MacPowerToys and
  the helper can observe denial/retry; Apple warns that very short-lived launch
  agents can exit before the alert is shown. [Apple local-network usage
  key](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription),
  [Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- Version 1 never reads SSID/BSSID and never asks for Location. The peer MAC
  comes only from same-link neighbor evidence after a successful TCP probe.
- Explain the helper before registration. Registering a background service
  notifies the user, and the user can disable it in Login Items settings.
  [Apple background-process guidance](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac)
- Before each new target scope, require the user to confirm that they may scan
  it. Show subnet, address count, ports, timeout, and expected traffic. Do not
  claim that scanning is lawful in every jurisdiction.

## Verification contract

1. **Parity fixtures:** cover every target type, pinger, fetcher, filter,
   result action, favorite, opener, exporter, loader, CLI mode, and native
   extension point listed above.
2. **Network fixtures:** verify IP Scanner IPv4 and IPv6 behavior; open, closed,
   timeout, and cancellation; Local Network denial; interface change; wake;
   exact 2.5-second anchor scheduling with no overlap; and the 1,024-address
   and 64-connection limits. Verify that SSH Anchor never automatically scans
   or rewrites an IPv6 target and never requests Location.
3. **Anchor state:** verify reachable means no scan/write; stable exact-MAC
   recovery; randomized loose-hostname plus learned-MAC recovery; unlearned MAC
   suggestion requiring manual confirmation; hostname-only and port-closed
   no-write; zero/duplicate candidate no-write; explicit non-22 configured
   port; absent/inherited/duplicate port read-only; exact `/usr/sbin/arp`
   evidence after TCP success; and proxy route read-only behavior.
4. **Config corpus:** first run the NetToys parser over comments, blank lines,
   CRLF, no final newline, tabs, `=`, quoted values, mixed keyword case,
   first-value precedence, safe `Include` globs/order and nesting, `Host`
   multi-patterns/negation/wildcards, `Match`, symlinks, hard links,
   permissions, and missing files. Assert that unsafe includes and every
   `Match exec` in the traversed graph are rejected before any `ssh -G`
   process starts.
   Assert that Include- or Match-selected values, multi-pattern blocks, and
   duplicate `HostName` directives are read-only. Only after that preflight,
   use `ssh -G -F <safe-fixture> <alias>` to verify the effective hostname and
   port. For a successful eligible top-level edit, the raw diff changes only
   the chosen `HostName` value bytes and every other effective SSH field stays
   equal.
5. **Write faults:** inject failure before backup, after backup, during temp
   write, before swap, after swap, before post-check, and during rollback. Kill
   the helper at each point and replay the journal. The path must contain one
   complete old or new file, and the original or exact backup must remain
   recoverable.
6. **Concurrency:** edit the config externally during discovery, coordination,
   and post-check. NetToys must abort or preserve the newer user edit. It must
   never overwrite it silently.
7. **Helper lifecycle:** verify transactional enable, register, login launch,
   version/health handshake, needs-approval, System Settings revoke, app quit,
   crash relaunch, wake, network change, update, quiesced disable, unregister,
   and no orphan or main-app fallback.
8. **Privacy and retention:** verify just-in-time prompts, denial paths, no
   secrets or file contents in history/logs, local-only storage, expiry,
   clearing, and no network work while NetToys is disabled.

## Source gaps

- The official long-form Angry IP documentation is old. It labels some
  fetchers as planned and says the UI is IPv4-only, while the current source
  and 3.9.3 release add newer behavior, including IPv6 file input. Treat the
  pinned current source as the feature inventory and verify the latest released
  binary before declaring exact parity. [Current release notes](https://github.com/angryip/ipscan/releases/tag/3.9.3)
- Apple documents CoreWLAN, Local Network privacy, and Service Management, but
  it does not provide an SSH-config editor. The byte-preserving grammar and
  recovery rules above are product constraints. Validate them against the
  macOS-shipped `/usr/bin/ssh -G`, not only the newest upstream OpenSSH manual.
- MAC and hostname evidence cannot prove device identity. The design therefore
  refuses ambiguous or unseen evidence and never changes SSH trust data.
