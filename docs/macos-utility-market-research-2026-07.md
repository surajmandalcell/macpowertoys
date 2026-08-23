# macOS Power Utility Market: TL;DR Research

**Snapshot:** 13 July 2026
**Question:** Which tools could make PowerToys unusually compelling and shareable?
**Product context:** PowerToys is already a native SwiftUI utility shell with modular tools, menu bar presence, App Intents, background services, logs, and file-transfer infrastructure.

## Executive recommendation

No feature can guarantee instant popularity. The best evidence-backed bet is a **Share Shelf** rather than a generic launcher or a bag of unrelated mini-tools:

> Drag or copy anything, briefly shake the pointer or invoke a hotkey, then drop it on a floating shelf that suggests useful local actions: compress, convert, strip metadata, clean a URL, OCR, checksum, rename, copy a path, create a QR code, or send to another device.

This combines three proven jobs into one coherent, highly demonstrable loop:

1. **Hold it:** Dropover's floating shelf has a 4.9/5 score from 8K US App Store ratings and claims hundreds of thousands of users. Its US unlock is $6.99. Reviews repeatedly describe the shelf as something that should have been native to macOS. ([App Store listing](https://apps.apple.com/us/app/dropover-easier-drag-drop/id1355679052), [ratings and reviews](https://apps.apple.com/us/app/dropover-easier-drag-drop/id1355679052?mt=12&platform=mac&see-all=reviews))
2. **Act on it:** Clop automatically optimizes copied images and created image, video, and PDF files. Its $15 lifetime license and free mode prove demand for an invisible "copy large, paste small" workflow. ([official product page](https://lowtechguys.com/clop/), [official press kit](https://lowtechguys.com/clop/presskit))
3. **Send it:** LocalSend reports over 8 million downloads, has about 85K GitHub stars, and solves encrypted local transfer across macOS, iOS, Android, Windows, and Linux without an account or cloud. PowerToys already has an rclone transfer engine, and rclone supports more than 70 storage systems plus expiring public links on compatible providers. That creates a faster route to a differentiated "drop, transform, upload, copy link" loop. ([App Store listing](https://apps.apple.com/us/app/localsend/id1661733229?platform=iphone), [GitHub repository](https://github.com/localsend/localsend), [rclone overview](https://rclone.org/), [rclone link](https://rclone.org/commands/rclone_link/))

The winning product sentence is therefore closer to **"the place you drop anything to do the next thing"** than **"PowerToys for Mac."** The latter describes architecture; the former sells an outcome.

Two adjacent bets fit the codebase unusually well:

- **Mac Setup Vault:** snapshot a Mac's Homebrew packages, installed apps, selected app preferences, dotfiles, and PowerToys configuration; diff versions; then encrypt and sync the snapshot to any rclone remote. Homebrew already provides declarative `Brewfile` dump and restore, Apple Migration Assistant is all-or-nothing compared with this selective workflow, and rclone already supplies provider breadth and client-side encryption. ([Homebrew Bundle](https://docs.brew.sh/Brew-Bundle-and-Brewfile), [Apple Migration Assistant](https://support.apple.com/en-gb/guide/mac-help/mchla14c784b/mac), [rclone crypt](https://rclone.org/crypt/))
- **Agent Time Machine:** expand AI History into a local recovery tool for Claude Code, Codex, and Gemini sessions. Generic browsing is crowded, so the wedge should be repairing stale or corrupt indexes, finding sessions that disappeared from official pickers, showing storage hogs, safely archiving/compressing logs, and connecting a session to its file changes and commits. Codex issue reports document missing sessions despite intact SQLite/JSONL data and individual logs growing to hundreds of megabytes or gigabytes. ([missing Codex history](https://github.com/openai/codex/issues/20340), [large Codex logs](https://github.com/openai/codex/issues/24948))

## Ranked feature bets

Scores are directional judgment, not measured market size. `Demand` weighs first-party user counts, ratings, or open-source adoption. `Demo` estimates how easily the value travels in a 10-second clip. `Fit` estimates compatibility with the current native modular app. `Headroom` rewards areas where PowerToys can offer a distinct workflow rather than a clone. Each is scored out of 5.

| Rank | Candidate | Demand | Demo | Fit | Headroom | Recommendation |
|---:|---|---:|---:|---:|---:|---|
| 1 | **Share Shelf + Smart Actions** | 5 | 5 | 4 | 4 | Build as the flagship |
| 2 | **Mac Setup Vault** | 4 | 5 | 5 | 4 | Build after the Shelf proves demand |
| 3 | **Agent Time Machine + Repair** | 4 | 4 | 5 | 3 | Evolve the existing Claude tool |
| 4 | **Clipboard-aware Developer Lab** | 4 | 4 | 5 | 3 | Build as Shelf actions, not a separate catalog race |
| 5 | **Nearby Send, LocalSend-compatible** | 5 | 5 | 3 | 4 | Prototype protocol interoperability |
| 6 | **Capture to Action** | 5 | 5 | 3 | 2 | Add narrowly through the Shelf |
| 7 | **Finder Batch Actions** | 4 | 4 | 5 | 3 | Fold into Smart Actions |
| 8 | **Selection Actions** | 4 | 4 | 4 | 3 | Make every action available in Services, Shortcuts, and Spotlight |
| 9 | **Advanced Clipboard** | 5 | 4 | 4 | 1 | Only build differentiated layers |
| 10 | **Window Management** | 5 | 4 | 3 | 1 | Defer, saturated |
| 11 | **Menu Bar Management** | 4 | 4 | 2 | 2 | Avoid as a core promise |
| 12 | **General Launcher / Automation Canvas** | 5 | 3 | 2 | 1 | Do not lead with it |

### 1. Share Shelf + Smart Actions

**MVP**

- Summon a temporary shelf by hotkey and pointer shake; accept files, folders, text, URLs, and images.
- Suggest actions from content type, with no setup: compress, convert, remove metadata, clean tracking parameters, copy path, hash, rename, OCR, QR, and zip.
- Let users drag the result back out. Preserve originals and make every operation reversible.
- Keep recent shelves locally for a short, user-controlled retention period.
- Expose the same actions through Finder Quick Actions, Share extensions, App Intents, and Shortcuts.

**Why it can spread:** the interaction is visual, surprising, and useful to non-developers. Dropover's reviews specifically praise Shortcuts, context menu, and Share Sheet integration, so integration depth matters as much as the shelf itself. ([App Store reviews](https://apps.apple.com/us/app/dropover-easier-drag-drop/id1355679052?mt=12&platform=mac&see-all=reviews))

**Differentiation:** do not clone Dropover's shelf feature-for-feature. Make *automatic local actions* the hero and use PowerToys modules as action providers. BetterTouchTool now advertises a notch drop zone, while Dropover supports notch drops and custom actions, so a plain shelf is no longer enough. ([BetterTouchTool](https://folivora.ai/), [Dropover](https://dropoverapp.com/))

### 2. Mac Setup Vault

Create versioned, portable setup snapshots containing a reviewable `Brewfile`, Mac App Store/app inventory, selected preferences, dotfiles, editor extensions, shell configuration, and PowerToys settings. Let users preview exactly what will be captured or restored, exclude secrets by default, diff two snapshots, and restore component by component.

The current rclone module is the unfair advantage: snapshots can target Google Drive, S3, Dropbox, WebDAV, SFTP, or another configured remote without building a new storage layer. An optional rclone `crypt` wrapper keeps configuration encrypted before upload. This is a better fit than a generic backup tool because the promise is a clean, reproducible Mac setup rather than a full disk clone.

**Guardrails:** never collect Keychain items, browser profiles, auth tokens, SSH private keys, or license material automatically. Restores need a dry run, conflict preview, OS-version checks, and granular approval. App preferences are not standardized, so support should start with a curated compatibility catalog.

### 3. Agent Time Machine + Repair

The existing AI History module solves a real problem, but plain browsing is no longer enough. Claulog provides a free native Claude browser with search, cost tracking, and resume. Agent Sessions covers Claude, Codex, Cursor, OpenCode, Copilot CLI, and other agents with unified search, images, quota tracking, resume, saved-session recovery, and a live cockpit; its repository reached roughly 700 stars within months. ([Claulog](https://claulog.com/), [Agent Sessions](https://github.com/jazzyalex/agent-sessions))

Build the missing safety and provenance layer:

- detect session files missing from an agent's visible index and offer a previewed repair;
- validate JSONL/SQLite health and recover readable records from partial corruption;
- find duplicated compaction/tool-output payloads and show reclaimable disk space;
- archive or compress old sessions reversibly, with explicit retention rules;
- show a prompt, tool-call, file-change, test, commit, and PR timeline;
- generate a compact handoff from selected past sessions for a new agent;
- expose read-only search to agents through a local MCP tool, with per-project boundaries.

**Guardrail:** keep the default mode read-only. Never rewrite an agent's source data without a backup, a dry-run diff, and explicit confirmation. Format churn across agent releases makes parser fixtures and versioned adapters essential.

### 4. Clipboard-aware Developer Lab

Ship a keyboard-first, local toolbox that detects the current clipboard and opens the right operation. Start with JSON/YAML formatting and conversion, JWT inspection, Base64 and URL encoding, hashes, UUID/ULID, timestamps, regex testing, text diff, and QR generation.

The official DevToys product promises automatic clipboard-based tool detection and common JSON/YAML, JWT, and hashing tools; its repository has roughly 31.8K GitHub stars. That is strong demand for a toolbox, but the opportunity is a more native Mac interaction and system-wide invocation rather than a larger catalog. ([DevToys](https://devtoys.app/), [GitHub](https://github.com/DevToys-app/DevToys))

**Guardrail:** keep secrets local, warn before decoding credentials, and never send clipboard contents to analytics. Clipboard trust is unusually salient in July 2026 because Jamf documented malware impersonating Maccy to steal credentials and clipboard contents. ([Jamf Threat Labs](https://www.jamf.com/blog/pamstealer-macos-infostealer-applescript-rust/))

### 5. Nearby Send, compatible with LocalSend

A native SwiftUI LocalSend-compatible client could make "send this to the Android/Windows machine beside me" a shelf action. LocalSend's 85K GitHub stars, reported 8 million downloads, and 4.5/5 US App Store rating are the strongest quantitative demand signals in this scan. Its official protocol is public, REST-based, and uses HTTPS on the local network. ([repository](https://github.com/localsend/localsend), [protocol](https://github.com/localsend/protocol), [App Store](https://apps.apple.com/us/app/localsend/id1661733229?platform=iphone))

**Caveat:** this is higher effort and network edge cases are real. Interoperate with the installed LocalSend ecosystem before considering companion apps. Treat LocalSend as a protocol/ecosystem partner, not merely a feature to copy.

### 6. Capture to Action

Avoid trying to replace all of CleanShot X. Add a narrow capture loop to the shelf:

- region capture to floating preview;
- OCR and QR detection;
- fast redact/blur and annotation;
- compress and strip metadata;
- pin temporarily or send.

CleanShot X already charges $29 one-time with one year of updates, includes 1 GB cloud storage, and covers screenshot, recording, OCR, and sharing. It is also rated 99% inside Setapp. This validates willingness to pay but signals a powerful incumbent. ([CleanShot pricing](https://cleanshot.com/pricing), [Setapp catalog](https://setapp.com/apps))

Apple's ScreenCaptureKit provides high-performance screen and audio capture plus a system content picker, making a narrow native implementation feasible. ([Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit))

### 7. Finder Batch Actions

Implement the shelf's action engine as reusable file operations:

- template rename with preview and undo;
- image conversion and resize;
- archive/extract;
- checksum and duplicate comparison;
- PDF merge, split, compress, and page extraction;
- metadata inspection/removal;
- copy POSIX path, file URL, or Markdown link.

Clop validates demand for automatic image/video/PDF optimization and documents the open-source components it uses, including pngquant, jpegoptim, gifsicle, ffmpeg, libvips, and Ghostscript. ([Clop technical details](https://lowtechguys.com/clop/))

### 8. Selection Actions everywhere

Let a user select text or files and invoke transformations from the macOS Services menu, a hotkey, Spotlight, Shortcuts, or the Shelf. Useful initial actions are clean link, change case, Markdown conversion, quote/unquote, line sort/deduplicate, summarize locally or with BYOK, translate, and open with a named tool.

BetterTouchTool explicitly markets text-selection actions and 600+ built-in triggers/actions. Raycast's free tier includes custom extensions, developer tooling, snippets, calculator, quicklinks, and window management. Competing on the invocation layer alone is therefore difficult; PowerToys should compete on polished, local, reusable actions. ([BetterTouchTool](https://folivora.ai/), [Raycast pricing](https://www.raycast.com/pricing))

Apple now lets App Intents surface app actions through Spotlight, Shortcuts, Siri, widgets, and other system experiences. Every PowerToys action should use that distribution surface. ([Apple App Intents](https://developer.apple.com/documentation/appintents))

## Where *not* to spend the first year

### Basic clipboard history

Clipboard managers clearly have demand: Maccy has about 20.7K GitHub stars and is free/open source or $9.99 through the App Store; Paste sells at $29.99/year or $89.99 lifetime and offers iCloud sync, OCR search, pinboards, rules, and sequential paste. ([Maccy](https://maccy.app/), [Maccy GitHub](https://github.com/p0deje/Maccy), [Paste](https://pasteapp.io/), [Paste App Store](https://apps.apple.com/us/app/paste-limitless-clipboard/id967805235))

However, macOS Tahoe now includes searchable clipboard history in Spotlight, with text, images, links, and files. Apple's own App Store editorial positions dedicated apps as the advanced layer for longer retention, previews, organization, transformations, and sync. ([Apple Support](https://support.apple.com/en-ie/guide/mac-help/mchl40d5b86b/mac), [App Store editorial](https://apps.apple.com/us/mac/story/id1655204803))

**Decision:** do not build "history in a popup." If clipboard functionality is added, focus on semantic search/OCR, paste queues, sensitive-app rules, pinned reusable items, transformations, and transparent local retention.

### Window manager

Rectangle is free, open source, actively released, and has roughly 29.5K GitHub stars. It already offers keyboard shortcuts, snap areas, URL actions, import/export, multiple displays, and many positions; Rectangle Pro adds custom layouts and richer gestures. ([Rectangle GitHub](https://github.com/rxhanson/Rectangle), [Rectangle Pro](https://rectangleapp.com/pro/))

**Decision:** demand is strong but headroom is low. Integrate with Rectangle's URL scheme if useful instead of recreating it.

### Menu bar manager

Ice has roughly 28.8K GitHub stars and offers hidden sections, a secondary bar, search, spacing, and appearance customization. Yet its repository's last push was September 2025 in the GitHub API snapshot, with hundreds of open issues, while current macOS changes repeatedly break this category. Bartender 6 and several newer entrants continue to compete. ([Ice GitHub](https://github.com/jordanbaird/Ice), [GitHub API](https://api.github.com/repos/jordanbaird/Ice), [Bartender](https://www.macbartender.com/))

**Decision:** this can attract attention but carries ongoing private-API and OS-compatibility risk. It is a poor foundation for the bundle's reputation.

### Generic launcher or automation platform

Raycast gives away its core launcher, clipboard, snippets, quicklinks, calculator, emoji picker, window management, extensions, and developer tooling. Pro is $10/month or $8/month annually. Alfred Powerpack starts at £34 and has mature workflows, clipboard, snippets, file navigation, terminal commands, and a large community. BetterTouchTool starts at $15, has operated for 16+ years, claims hundreds of thousands of users, and advertises 600+ triggers and actions. ([Raycast pricing](https://www.raycast.com/pricing), [Alfred Powerpack](https://www.alfredapp.com/powerpack/), [BetterTouchTool pricing](https://folivora.ai/buy))

macOS Tahoe Spotlight now browses apps, files, clipboard, and actions, while invoking hundreds of app and system actions. ([Apple macOS Tahoe update](https://support.apple.com/en-gb/122868))

**Decision:** expose actions *into* Spotlight and Shortcuts. Do not spend the launch window building a replacement launcher UI.

## Incumbent map

| Product | Current proposition and price signal | Market lesson |
|---|---|---|
| Raycast | Free core with thousands of extensions; Pro $8/month annually | A launcher and basic utility bundle is already free |
| Alfred | £34 v5 or £59 lifetime upgrades | Deep workflow ecosystems retain loyal power users |
| BetterTouchTool | $15 standard, $25 lifetime; 600+ actions/triggers | Automation breadth takes years and creates configuration complexity |
| Setapp | Hundreds of apps for $14.99/month on one Mac | Users pay for a curated bundle, but PowerToys cannot win by count alone |
| CleanShot X | $29 one-time, one year updates | Polished capture is a paid category with a high bar |
| Paste | $29.99/year or $89.99 lifetime | Clipboard revenue lives above basic history: sync, organization, search, and collaboration |
| Maccy | Free direct/open source; $9.99 App Store; ~20.7K stars | Native, fast, private, and focused wins affection |
| Rectangle | Free/open source; ~29.5K stars; paid Pro | Window snapping is validated and crowded |
| Dropover | $6.99 US unlock; 4.9/5 from 8K ratings | Tiny, visual interaction improvements can reach a broad audience |
| Clop | Free mode; $15 lifetime; ~1.6K stars | Invisible automatic processing creates daily habit |
| Ice | Free/open source; ~28.8K stars | Strong demand, but OS fragility and maintenance risk |
| LocalSend | Free/open source; ~85K stars; reported 8M downloads | Cross-platform, account-free local sharing is a major unresolved job |
| DevToys | Free/open source; ~31.8K stars | Clipboard-aware developer tools are a credible audience wedge |

Sources: [Raycast](https://www.raycast.com/pricing), [Alfred](https://www.alfredapp.com/powerpack/), [BetterTouchTool](https://folivora.ai/), [Setapp](https://setapp.com/pricing), [CleanShot](https://cleanshot.com/pricing), [Paste](https://pasteapp.io/), [Maccy](https://maccy.app/), [Rectangle](https://github.com/rxhanson/Rectangle), [Dropover](https://apps.apple.com/us/app/dropover-easier-drag-drop/id1355679052), [Clop](https://lowtechguys.com/clop/), [Ice](https://github.com/jordanbaird/Ice), [LocalSend](https://github.com/localsend/localsend), [DevToys](https://github.com/DevToys-app/DevToys).

## Product principles implied by the evidence

1. **One magic loop, many modules.** Users should discover PowerToys through the Shelf, then gain more actions as tools are installed or enabled.
2. **Local-first is a feature, not fine print.** Show exactly where data lives, make retention visible, exclude password managers by default, and require explicit consent for any network or model call.
3. **System-wide beats app-window usage.** Finder, Share Sheet, Services, Shortcuts, Spotlight, menu bar, drag/drop, and URL schemes are distribution channels.
4. **Automatic, but reversible.** Suggest or perform low-risk transformations, preserve originals, show the result, and offer undo.
5. **Do not compete by tool count.** Setapp already offers hundreds of apps, Raycast thousands of extensions, and BetterTouchTool 600+ actions. Win on coherence, speed, native polish, and discoverability.
6. **One-time purchase has market support.** The surveyed focused utilities commonly use low one-time prices or perpetual use with paid update windows. A free core Shelf plus a reasonably priced Pro action pack is more category-consistent than an AI-heavy subscription.

## Positioning risk: rename before public launch

Microsoft PowerToys is the official Windows utility suite, contains more than 30 tools, and has roughly 135K GitHub stars. Keeping the name **PowerToys** makes search discovery, word of mouth, package naming, and press coverage unnecessarily difficult, even before considering trademark review. ([Microsoft documentation](https://learn.microsoft.com/en-us/windows/powertoys/), [official repository](https://github.com/microsoft/PowerToys))

Choose a distinct product name before investing in launch marketing. Keep "power tools for Mac" as descriptive copy, not the brand. This positioning change is likely to matter more to popularity than adding the tenth or twentieth utility.

## Suggested 90-day sequence

### Weeks 1-4: validate the magic loop

- Build a shelf that accepts files, URLs, text, and images.
- Ship five actions: clean URL, copy path, hash, resize/compress image, and zip.
- Add Finder Quick Action, Share extension, and App Intents for those actions.
- Instrument only aggregate action counts, opt-in, with no filenames, content, clipboard data, or paths.

**Success signal:** new users complete three different actions in their first week and at least one-third return weekly. Shareable clips should show the full drag, suggestion, result loop in under 10 seconds.

### Weeks 5-8: developer wedge

- Add clipboard content detection and JSON/YAML, JWT, Base64/URL, timestamp, UUID, regex, and diff tools.
- Make every operation callable from Spotlight/Shortcuts and usable as a Shelf action.

### Weeks 9-12: share and capture experiments

- Prototype LocalSend protocol discovery/send as a Shelf destination.
- Add region capture to Shelf with OCR, redact, and compress.
- Test which of Nearby Send and Capture has stronger repeat use before expanding either.

## Caveats

- GitHub stars, ratings, developer-reported users/downloads, and prices are adoption signals, not comparable active-user or revenue measurements.
- App Store counts differ by storefront and device. For example, Paste's website advertises 16K+ ratings while its current US universal listing shows about 1.3K; do not combine those values.
- Product pages naturally emphasize strengths. Review excerpts were used only as qualitative pain signals, not representative survey results.
- GitHub counts are point-in-time values from the public API on 13 July 2026 and will change.
- Feasibility estimates are preliminary. Global drag detection, Finder/Share extensions, Screen Recording, Accessibility, network discovery, sandboxing, notarization, and App Store rules require dedicated technical spikes.

## Niche micro-tool shortlist

This pass deliberately excludes launchers, clipboard managers, window managers,
screenshot tools, file shelves, menu bar managers, cleaners, and broad media or
PDF suites. Rankings favor a single annoying moment, a one-action outcome, and
an implementation small enough for a solo developer to validate in days rather
than months. "Gap" means the focused-product scan found room between macOS and
broader incumbents, not that no competing app exists.

### Top 10

| Rank | Micro-tool | One-sentence job | Mac gap and saturation | Likely effort |
|---:|---|---|---|---|
| 1 | **Eject Detective** | Select a stubborn external disk, see the exact processes and open files blocking it, close or reveal them, then retry eject. | Apple says its warning identifies the app only "in some cases" and otherwise tells users to hunt and quit apps; Sloth can inspect every open file, but it is a broad process tool rather than this guided action. ([Apple](https://support.apple.com/guide/mac-help/mh27076/mac), [Sloth repository](https://github.com/sveinbjornt/Sloth)) | 3-6 days |
| 2 | **Sleep Blocker Finder** | Answer "why won't my Mac sleep?" with the responsible app, assertion reason, age, and a safe reveal/quit action. | Activity Monitor exposes only a Preventing Sleep yes/no column; keep-awake apps are saturated, but explaining unwanted wakefulness is the inverse and much narrower job. ([Apple](https://support.apple.com/guide/activity-monitor/actmntr43697/mac), [KeepingYouAwake repository](https://github.com/newmarcel/KeepingYouAwake)) | 4-7 days |
| 3 | **Time Machine Dev Excluder** | Find generated folders such as `node_modules`, `.build`, `DerivedData`, and virtual environments, then preview and apply Time Machine exclusions. | Apple makes exclusions manual, item by item; `tmutil` supports inspectable add/remove operations, while Asimov validates this developer-specific niche without making it a crowded consumer category. ([Apple UI](https://support.apple.com/guide/mac-help/exclude-files-from-a-time-machine-backup-mh15622/mac), [`tmutil`](https://keith.github.io/xcode-man-pages/tmutil.8.html), [Asimov repository](https://github.com/stevegrunwell/asimov)) | 5-10 days |
| 4 | **Background Item Explainer** | Translate a cryptic login item or helper into its parent app, developer, executable path, signature, and current running state. | macOS lists registered items, but Apple itself points administrators to `sfltool dumpbtm`, Console filters, and a private attribution file for real diagnosis; the focused consumer-tool field appears thin. ([Apple deployment guide](https://support.apple.com/guide/deployment/depdca572563/web)) | 7-12 days |
| 5 | **Broken Link Doctor** | Drop an alias or symbolic link to see its full target chain, identify the broken hop, and repair it by choosing a replacement target. | Finder can create aliases and offers "Select New Original" only after an alias fails; a compact tool can cover aliases and symlinks together with no broad incumbent category. ([Apple](https://support.apple.com/guide/mac-help/create-and-remove-aliases-on-mac-mchlp1046/mac)) | 4-7 days |
| 6 | **File Type Card** | Show a selected file's UTI, MIME type, extension, conformance tree, and extension/content mismatch, with copy buttons. | Apple's UTType framework exposes these relationships, preferred MIME types, and extensions, but Finder does not present them; Apparency is app-bundle focused, leaving a small general-file niche. ([Apple UTType reference](https://developer.apple.com/documentation/uniformtypeidentifiers/uttypereference), [Apparency](https://www.mothersruin.com/software/Apparency/)) | 3-5 days |
| 7 | **Package Receipt Lookup** | Select an installed file or app and answer which installer package placed it there, including package ID, version, and receipt status. | macOS ships receipt data and `pkgutil`, but the workflow is command-line oriented; Suspicious Package inspects packages before installation, so reverse lookup remains a distinct micro-job. ([`pkgutil`](https://keith.github.io/xcode-man-pages/pkgutil.1.html), [Suspicious Package](https://www.mothersruin.com/software/SuspiciousPackage/)) | 4-8 days |
| 8 | **Default App Repair** | Select a file type, see every app that actually declares support, set the default, and remove stale duplicate choices from Open With. | Finder can change one document or all documents of a type, but offers little diagnosis when handlers are stale; SwiftDefaultApps exists but its narrow open-source project shows limited rather than mass-market saturation. ([Apple](https://support.apple.com/guide/mac-help/choose-an-app-to-open-a-file-mh35597/mac), [SwiftDefaultApps repository](https://github.com/Lord-Kamina/SwiftDefaultApps)) | 6-10 days |
| 9 | **Download Trust Card** | Quick Look a downloaded app or installer to explain signer, notarization, quarantine source, architecture, and minimum macOS version before launch. | Gatekeeper performs these checks but usually reduces them to an allow/block dialog; Apparency is an excellent incumbent, so compete only with a simpler plain-language preflight rather than a full inspector. ([Apple Platform Security](https://support.apple.com/guide/security/sec5599b66df/web), [Apparency](https://www.mothersruin.com/software/Apparency/)) | 7-14 days |
| 10 | **Filename Travel Check** | Preview and repair filenames that will break or become ambiguous on Windows, cloud drives, archives, shells, or case-insensitive volumes. | Finder validates names mainly for the current Mac volume; Microsoft's official rules still reserve characters and device names, creating a practical cross-platform handoff gap with few focused Mac products. ([Apple File System Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemDetails/FileSystemDetails.html), [Microsoft naming rules](https://learn.microsoft.com/windows/win32/fileio/naming-a-file)) | 5-9 days |

### More small candidates

| Candidate | One-action job | Saturation call |
|---|---|---|
| **Time Machine Inclusion Check** | Finder action says whether the selected item is backed up, why it is excluded, and offers include/exclude. | Very low; a smaller companion or MVP slice of rank 3. ([`tmutil`](https://keith.github.io/xcode-man-pages/tmutil.8.html)) |
| **Quarantine Trail** | Show when and by which app a download was quarantined, then remove that one attribute only after a clear warning. | Low as a standalone; Apparency already does this well for app bundles. ([Apparency guide](https://www.mothersruin.com/software/Apparency/use.html)) |
| **App Architecture Check** | Tell whether an app is Apple silicon, Intel/Rosetta, or universal and whether it can run on this Mac. | Low, but System Information and Apparency already expose adjacent details; useful mainly as a Finder badge. ([Apple Rosetta](https://support.apple.com/en-us/102527), [Apparency](https://www.mothersruin.com/software/Apparency/)) |
| **Relative Path Copier** | Copy selected paths relative to a chosen project root as plain text, quoted shell paths, Markdown links, or file URLs. | Low competition but developer-only; keep it one Finder action, not a toolbox. |
| **Executable Bit Fixer** | Explain why a script will not run, preview its shebang and permissions, then set the user executable bit. | Low competition; tiny developer/support niche with careful scope. |
| **Text Encoding Card** | Detect encoding, BOM, and line endings for one text file and normalize a copy to UTF-8/LF. | Editors already solve it, so value depends on Finder-level speed and batch-free simplicity. |
| **Deep-Link Tester** | Save and launch custom URL schemes, show the handling app, and keep a small local test history. | Low consumer demand but useful for Mac/iOS developers and QA; avoid becoming an API client. ([Apple URL scheme guidance](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)) |
| **Port Owner** | Enter a local port to reveal its owning app/process and quit it gracefully before escalating to force quit. | Terminal and broad process inspectors cover it, but the exact "port already in use" moment remains a clean micro-tool. ([Sloth repository](https://github.com/sveinbjornt/Sloth)) |
| **Alias-to-Symlink Converter** | Convert a selected Finder alias to a relative or absolute symlink, with a preview of portability consequences. | Very low and very niche; natural add-on to Broken Link Doctor. ([Apple aliases](https://support.apple.com/guide/mac-help/create-and-remove-aliases-on-mac-mchlp1046/mac)) |
| **Hidden File Peek** | Reveal hidden files in one Finder window for a timed interval, then restore the prior state automatically. | Low, but it risks feeling trivial unless bundled with other Finder diagnostics. |
| **Launch Handler Card** | Drop a URL scheme or file extension to see which installed apps claim it and which app macOS will choose. | Low; overlaps Default App Repair and File Type Card, so merge if both validate. ([Apple document type declarations](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app)) |
| **File Flags Card** | Inspect and safely toggle locked, hidden, immutable, and append-only flags on a selected item. | Very low; useful to support staff, but some flags require elevated privileges and strong warnings. |

**Best first validation:** prototype Eject Detective, Sleep Blocker Finder, and
Time Machine Inclusion Check as three independent Finder/menu actions. Each has
an obvious before/after demo, uses system information already present on macOS,
and can be tested without committing the product to a large platform feature.
