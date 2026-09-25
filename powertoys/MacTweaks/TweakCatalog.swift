import Foundation

enum TweakKind: String {
    case preference = "Hidden preference"
    case versioned = "Version-specific"
    case candidate = "Needs verification"
    case advanced = "System control"
    case native = "Apple setting"
    case helper = "Needs a running helper"
    case historical = "Historical recipe"
}

struct TweakItem: Identifiable {
    let id: String
    let title: String
    let category: String
    let kind: TweakKind
    let summary: String
    let keywords: [String]
    let patterns: [String]

    var researchCoverage: String {
        switch kind {
        case .preference: "Documented for macOS 15, 26, and 27"
        case .native: "Apple setting on macOS 15, 26, and 27"
        case .versioned:
            switch id {
            case "finder.column-sizing": "Hidden on 15 and 26.0; native from 26.1"
            case _ where id.hasPrefix("launchpad."): "Legacy Launchpad on macOS 15 only"
            case "appearance.corners", "appearance.sidebars": "Documented from macOS 26.4 and on 27"
            case "appearance.menu-icons": "Documented on 26; 27 unverified"
            case "windows.edge-grab", "input.text-drag": "Documented on 15 and 26; 27 unverified"
            case "input.layout-popup", "safari.bookmarks": "Documented on 26 and 27; 15 unverified"
            default: "Documented on 15; 26 and 27 unverified"
            }
        case .advanced: id == "hardware.auto-start" ? "Apple documents macOS 15 or later on Apple silicon laptops" : "Apple documents 15 and 26; 27 unverified"
        case .candidate: "Behavior unverified on the target systems"
        case .helper: "Requires a running implementation; target-system support unverified"
        case .historical: "No supported three-version recipe"
        }
    }
}

enum TweakCatalog {
    // Each record has private search terms and natural-language patterns. These are not shown as labels.
    // Fields: kind | category | id | title | summary | keywords | patterns.
    private static let rows = """
P|Dock|dock.reveal-delay|Reveal delay|Wait before a hidden Dock appears.|autohide hover timing latency|dock takes too long;show dock faster
P|Dock|dock.animation-duration|Hide and show duration|Set the Dock animation time separately from reveal delay.|autohide speed transition|dock animation speed;instant dock
P|Dock|dock.hidden-app-dimming|Dim hidden apps|Dim Dock icons for hidden applications.|showhidden faded transparent|which apps are hidden;fade hidden icons
P|Dock|dock.spacers|Dock separators|Add regular or compact gaps between Dock items.|spacer gap divider separator|space out dock icons;add dock gap
P|Dock|dock.lock-size|Lock Dock icon size|Prevent accidental resizing of Dock icons.|immutable resize fixed|stop dock resizing;dock size keeps changing
P|Dock|dock.lock-contents|Lock Dock layout|Prevent accidental rearrangement of Dock items.|immutable pin order fixed|stop moving dock icons;lock dock icons
P|Dock|dock.stack-selection|Highlight stack selection|Mark the hovered item in a grid stack.|mouse over hilite hover grid|highlight dock stack item
P|Dock|dock.minimize-effect|Extra minimize effect|Choose the hidden Suck effect alongside Apple's normal choices.|suck genie scale animation|minimize animation;window suck effect
P|Dock|dock.slow-motion|Shift slow motion|Use the Shift key for a slow minimize animation.|slow motion minimize shift|slow minimize windows
P|Dock|dock.switcher-displays|Cmd-Tab on every display|Show the application switcher on every screen.|app switcher monitor multiple screens|cmd tab second monitor;app switcher all displays
P|Finder|finder.hidden-files|Show hidden files|Keep dotfiles visible in Finder.|dotfiles invisible files apple show all|show dot files;hidden files finder
P|Finder|finder.quit|Quit Finder|Add a Quit command to Finder's menu.|exit close finder quit menu|quit finder app;stop finder
P|Finder|finder.path-title|Path in window title|Show the full folder path in a Finder title.|posix directory location titlebar|finder full path;folder path title
P|Finder|finder.sounds|Finder sounds|Turn Finder operation sounds on or off.|audio effects beep trash|mute finder;disable finder sounds
P|Finder|finder.open-animation|Open animations|Control Finder icon and information panel opening effects.|desktop icon get info animation|finder animations;disable get info animation
P|Finder|finder.info-animation|Inspector transitions|Control expansion animation inside Finder information panels.|get info inspector section animation|disable finder info animation
P|Finder|finder.network-metadata|Network metadata files|Limit Finder .DS_Store use on SMB shares.|ds store smb network share|stop ds_store network;network folder metadata
P|Finder|finder.wait-for-network|Complete network listing|Wait for network folder details before showing contents.|smb listing metadata wait|network files appear slowly;wait for network folder
P|Finder|finder.restrict-connect|Connect to Server restriction|Hide Finder's Connect to Server command.|server smb network menu restriction|block connect to server
P|Finder|finder.restrict-eject|Eject restriction|Restrict Finder's Eject action.|disk volume drive removable|hide eject finder
P|Finder|finder.restrict-burn|Burning restriction|Restrict disc burning commands in Finder.|dvd cd disc optical|disable burn disc
P|Finder|finder.restrict-go|Go to Folder restriction|Restrict Finder path navigation through Go to Folder.|folder path command shift g|block go to folder
P|Input|input.press-hold|Repeat instead of accents|Choose key repeat instead of the accent popup.|keyboard diacritics hold key|hold key repeats;disable accent menu
P|Windows and dialogs|dialogs.expanded-save|Expanded Save panel|Open native Save dialogs in expanded mode.|file picker browse save as|always expand save dialog
P|Windows and dialogs|windows.scroll-animation|Page scroll animation|Control animated scrolling in compatible native views.|document page transition|disable scroll animation
P|Windows and dialogs|dialogs.recent-limit|Recent document limit|Choose the Open Recent menu limit in native apps.|history recent files|more recent documents
P|Windows and dialogs|dialogs.tooltip-delay|Tooltip delay|Choose how quickly native help tags appear.|hover help popup|tooltips faster;tooltip timing
P|Menu bar|menubar.spacing|Menu bar item spacing|Adjust status item separation and selection padding.|status icons notch padding|more menu bar icons;menu bar spacing
P|Windows and dialogs|spaces.drag-delay|Space drag delay|Change the wait when dragging a window between Spaces.|mission control desktop move|drag window between desktops
P|Screenshots|screenshots.format|Screenshot format|Choose the file format for new screenshots.|capture png jpg jpeg pdf tiff heic|save screenshot as jpeg;change capture type
P|Screenshots|screenshots.shadow|Window capture shadow|Include or omit window shadows in screenshots.|capture drop shadow|remove screenshot shadow
P|Screenshots|screenshots.date|Screenshot timestamp|Include or omit date and time in screenshot filenames.|capture filename date|screenshot name no date
P|Built-in apps|terminal.pointer-focus|Terminal pointer focus|Focus Terminal windows by moving the pointer.|focus follows mouse shell|terminal focus follows mouse
P|Built-in apps|mail.custom-sound|Custom Mail sound|Choose an AIFF sound for incoming mail.|notification audio inbox|mail incoming sound
P|Built-in apps|music.half-stars|Music half stars|Enable half-star ratings in Music.|apple music rating songs|rate music half star
P|Appearance|appearance.app-light|Per-app light appearance|Keep selected Apple apps light when the system is dark.|dark mode override|light safari dark mac
P|Appearance|appearance.font-defaults|Preferred font defaults|Choose font defaults for compatible app categories.|system fonts typography sizes|change default font
P|Appearance|appearance.font-smoothing|Font smoothing|Set smoothing where apps still respect the preference.|text antialiasing|smooth fonts;disable font smoothing
P|Regional formats|formats.numbers|Numeric separators|Customize decimal and grouping symbols.|thousands comma decimal point|change decimal separator
P|Regional formats|formats.currency|Currency formatting|Customize currency symbols and separators.|money regional locale|change currency symbol
P|Regional formats|formats.date-time|Date and time templates|Customize short and long date and time formats.|calendar clock locale|change date format
P|Diagnostics|diagnostics.handling|Crash handling|Choose how macOS presents application crashes.|reporter diagnostics crash|quiet crash reporter
P|Diagnostics|diagnostics.notification|Crash notifications|Choose crash notification presentation.|reporter notification center|disable crash notifications
P|Diagnostics|diagnostics.exceptions|Exception notices|Control uncaught exception warnings.|developer diagnostic warning|show exception notices
P|Diagnostics|diagnostics.reporter-dock|Reporter Dock icon|Show the problem reporter in the Dock.|crash reporter icon|show crash reporter dock
P|Built-in apps|safari.backspace|Safari Backspace navigation|Use Backspace for page navigation outside text fields.|browser back key delete|backspace goes back safari
P|Built-in apps|safari.zoom|Fine Safari zoom|Set an initial Safari page zoom between presets.|browser page scale|custom safari zoom
V|Finder|finder.column-sizing|Automatic column width|Fit Finder columns to filenames where the hidden control still exists.|autosize column view|finder columns fit names
V|Launchpad|launchpad.grid|Launchpad grid|Set rows and columns in legacy Launchpad.|icons rows columns|launchpad grid size
V|Launchpad|launchpad.fade-in|Launchpad entry animation|Adjust legacy Launchpad opening transition.|fade open launcher|launchpad opens slowly
V|Launchpad|launchpad.fade-out|Launchpad exit animation|Adjust legacy Launchpad closing transition.|fade close launcher|launchpad closes slowly
V|Launchpad|launchpad.page|Launchpad page animation|Adjust legacy Launchpad page transitions.|swipe launcher page|launchpad page speed
V|Appearance|appearance.corners|Window corner shape|Use earlier window corner rounding on supported releases.|radius rounded square|old window corners
V|Appearance|appearance.sidebars|Floating sidebars|Control floating sidebar presentation on supported releases.|liquid glass sidebar|disable floating sidebar
V|Appearance|appearance.menu-icons|Extra menu icons|Reduce Tahoe decorative menu icons.|symbols menu items|remove menu icons
V|Windows and dialogs|windows.edge-grab|Resize edge tolerance|Make window borders easier to grab.|resize hit area edge|easier window resize
V|Input|input.text-drag|Text drag threshold|Tune the delay before selected text drags.|selection drag delay|disable text dragging
V|Input|input.layout-popup|Input source popup|Hide the input indicator when switching layouts.|typing assistant language flag|hide language popup
V|Built-in apps|safari.bookmarks|Hierarchical Safari bookmarks|Restore the bookmark tree editor on supported Safari builds.|browser favorites folders|safari bookmark hierarchy
V|Built-in apps|timemachine.disk-prompt|Backup disk suggestion|Control prompts for newly connected backup drives.|time machine external disk|stop backup disk prompt
V|Built-in apps|apps.automatic-termination|Unused app termination|Opt out of native automatic termination where supported.|app lifecycle memory|stop auto quitting apps
V|Dock|dock.recent-count|Recent app count|Choose the number of suggested Dock apps where supported.|recents suggestions|dock recent apps number
C|Dock|dock.running-only|Running apps only|Show open applications rather than all pinned apps.|static only active dock|dock only open apps
C|Developer controls|security.sudo-touchid|Touch ID for sudo|Use biometric authentication for sudo with a dedicated policy change.|pam terminal fingerprint|sudo fingerprint
C|Input|input.hid-remap|Simple key remapping|Map individual hardware keys with lifecycle handling.|hidutil keyboard mapping|remap keys
C|Windows and dialogs|windows.drag-anywhere|Drag windows from anywhere|Investigate the modifier drag preference.|window move control command|move window anywhere
C|Input|input.repeat-timing|Precise key repeat|Set repeat delay and speed beyond native slider steps.|initial key repeat keyboard timing|faster key repeat
C|Windows and dialogs|dialogs.expanded-print|Expanded Print panel|Open native Print dialogs in expanded mode.|printer dialog options|expand print dialog
C|Input|input.control-characters|Visible control characters|Show control notation in compatible text views.|nonprinting characters|show control chars
C|Windows and dialogs|windows.focus-ring|Focus ring animation|Control animated keyboard focus outlines.|accessibility tab highlight|disable focus ring animation
C|Finder|finder.proxy-delay|Title icon delay|Set when a titlebar proxy icon appears.|rollover document icon|show titlebar file icon sooner
C|Continuity|continuity.clipboard|Clipboard Continuity|Investigate a clipboard-only Continuity choice.|universal clipboard handoff|disable shared clipboard
C|Appearance|appearance.extra-accents|Extra accent colors|Investigate additional hardware accent choices.|theme color|more accent colors
C|Built-in apps|quicklook.mute|Muted Quick Look video|Investigate muted video previews.|preview video audio|quicklook no sound
C|Built-in apps|textedit.blank-document|TextEdit blank startup|Investigate starting with a new blank document.|text editor chooser|textedit new document at launch
C|Menu bar|menubar.input-devices|Sound menu input devices|Investigate showing input devices in the Sound menu.|audio microphone menu|switch microphone menu bar
A|Power and hardware|hardware.auto-start|Lid and power startup|Choose which events start a powered-off Apple silicon laptop.|nvram boot preference|stop mac starting when lid opens
A|Power and hardware|power.schedule|Power event schedule|Schedule wake, sleep, restart, or shutdown events.|pmset timer automatic|scheduled mac shutdown
N|Dock|native.dock-basic|Dock size and position|Open Apple's Dock size, position, and magnification controls.|icons left right bottom|move dock;resize dock
N|Dock|native.dock-behavior|Dock behavior|Open Dock autohide, recents, and indicator controls.|recent apps dots|hide dock;show dock indicators
N|Dock|native.dock-minimize|Dock minimize choices|Open minimize destination and standard effect controls.|genie scale application icon|minimize to dock icon
N|Finder|native.finder-extensions|Filename extensions|Open Finder's extension visibility and warning controls.|file suffix rename warning|show file extensions
N|Finder|native.finder-bars|Finder path and status bars|Open Finder view bar controls.|breadcrumbs status|show path bar
N|Finder|native.finder-start|Finder start and search|Open Finder's new window and search scope controls.|home folder search|new finder window folder
N|Finder|native.finder-sort|Finder sorting|Open default view and folders-first controls.|directory order|folders on top
N|Finder|native.finder-desktop|Desktop items|Open desktop file and drive visibility controls.|external disk desktop|hide desktop icons
N|Finder|native.finder-trash|Trash cleanup|Open Apple's 30-day Trash setting.|delete old trash|empty trash after month
N|Finder|native.finder-sidebar|Finder sidebar|Open sidebar sizing and title icon controls.|favorites sidebar|sidebar icons size
N|Screenshots|native.screenshot-location|Screenshot destination|Open the native Screenshot destination selector.|capture save folder|where screenshots go
N|Screenshots|native.screenshot-thumbnail|Screenshot thumbnail|Open the floating preview choice.|capture preview floating|turn off screenshot thumbnail
N|Screenshots|native.screenshot-memory|Screenshot selection memory|Open the remembered selection choice.|capture selection region|remember screenshot area
N|Windows and dialogs|native.spaces-order|Spaces ordering|Open Mission Control ordering and grouping settings.|desktops rearrange|spaces move automatically
N|Windows and dialogs|native.spaces-switch|Spaces and displays|Open app activation and separate display Spaces settings.|monitor mission control|separate spaces each display
N|Windows and dialogs|native.tiling|Window tiling|Open edge, Option, and margin settings.|snap windows layout|tile windows at edges
N|Windows and dialogs|native.desktop-click|Wallpaper click behavior|Open Apple's desktop reveal choice.|click background show desktop|disable desktop click
N|Windows and dialogs|native.stage-manager|Stage Manager layout|Open recent strip and grouped-window settings.|window groups strip|stage manager options
N|Windows and dialogs|native.hot-corners|Hot corners|Open corner action choices.|screen corner shortcut|configure hot corner
N|Input|native.text-assists|Text assistance|Open quotes, spelling, capitalization, and prediction choices.|autocorrect smart quotes|disable text prediction
N|Input|native.keyboard-functions|Function keys|Open function key and keyboard navigation modes.|fn key tab focus|use f keys
N|Input|native.trackpad|Trackpad gestures|Open tapping and dragging choices.|three finger tap click|trackpad dragging
N|Appearance|native.appearance|Appearance and accessibility|Open dark mode, transparency, motion, and scroll bar choices.|theme contrast reduce motion|dark mode;reduce transparency
N|Regional formats|native.units|Regional units and clock|Open units, temperature, language, and clock choices.|metric fahrenheit 24 hour|change temperature units
N|Built-in apps|native.app-options|Built-in app settings|Open preferences in Safari, TextEdit, Activity Monitor, or Messages.|full url plain text refresh|safari full url;messages subject
H|Enhancements|helper.dock-click|Dock click actions|Change what clicking the active Dock icon does.|cycle hide minimize|click dock active app
H|Enhancements|helper.restore-minimized|Restore minimized windows|Customize activation of minimized windows.|unminimize|restore minimized app
H|Enhancements|helper.traffic-lights|Window button overrides|Change red, yellow, or green window button actions.|close zoom minimize|traffic light buttons
H|Enhancements|helper.quit-guard|Accidental quit protection|Add hold or confirmation behavior for selected apps.|cmd q confirmation|prevent accidental quit
H|Enhancements|helper.finder-keys|Finder key remapping|Add alternate cut, rename, delete, and navigation shortcuts.|windows shortcuts|finder f2 rename
H|Enhancements|helper.finder-context|Finder context actions|Add templates, paths, or terminal actions.|right click new file|finder new file menu
H|Enhancements|helper.finder-tabs|Finder tab actions|Reopen closed tabs or change sidebar clicks.|command t reopen tab|restore finder tab
H|Enhancements|helper.clipboard-files|Clipboard to file|Save clipboard text or images to a file on demand.|pasteboard export|save clipboard image
H|Enhancements|helper.window-layout|Window layout shortcuts|Apply layout and display moves by shortcut.|snap windows monitors|move window other display
H|Enhancements|helper.mission-actions|Mission Control actions|Add actions to window previews.|expose preview|mission control close window
H|Enhancements|helper.inactive-rules|Inactive app rules|Hide or quit selected inactive apps.|idle apps auto quit|hide app after idle
H|Enhancements|helper.hyper-key|Hyper key|Turn Caps Lock into a modifier combination.|caps lock shortcut|hyper key mapping
H|Enhancements|helper.middle-click|Trackpad middle click|Add a middle-button gesture to trackpads.|three finger click|middle mouse trackpad
H|Enhancements|helper.media-keys|Media key routing|Choose which player responds to media keys.|play pause spotify music|media buttons wrong app
H|Enhancements|helper.clipboard-clear|Clipboard expiry|Clear clipboard content after a time or lock.|pasteboard timer privacy|auto clear clipboard
H|Power and hardware|helper.keep-awake|Temporary keep awake|Prevent sleep for a chosen period while the helper runs.|caffeinate sleep timer|keep mac awake
H|Continuity|helper.airdrop-workflow|AirDrop workflow|Organize received files and focus behavior.|wireless transfer downloads|move airdrop files
H|Input|helper.mouse-scroll|Separate scroll directions|Set mouse and trackpad scrolling independently.|natural reverse scrolling|mouse scroll opposite trackpad
H|Input|helper.pointer-profiles|Pointer profiles|Tune pointer acceleration per device, app, or display.|mouse speed sensitivity|disable mouse acceleration
H|Input|helper.mouse-buttons|Mouse buttons and scroll|Map extra buttons and scroll gestures.|side button mouse mapping|mouse back button
X|Historical|avoid.glass-off|Old Glass off switch|The 26.0-only mechanism has side effects and does not apply to current Tahoe.|liquid glass transparent|disable liquid glass
X|Historical|avoid.icloud-save|Old local save default|The old iCloud save preference is no longer a reliable control.|cloud documents save|default save on mac
X|Historical|avoid.scroll-stacks|Old Dock scroll recipe|The older stack-scroll behavior lacks current support evidence.|dock stack scroll|scroll to open stack
X|Historical|avoid.single-app|Old single app Dock mode|Older defaults recipes do not establish current behavior.|show one app dock|single application mode
X|Historical|avoid.help-top|Old Help window switch|The always-on-top Help recipe lacks modern behavior evidence.|help viewer floating|help window always on top
X|Historical|avoid.all-animation|Global animation removal|A blanket animation switch cannot promise to affect all windows.|disable every animation|remove all mac animations
X|Historical|avoid.split-dark|Split dark appearance|The separate menu and app darkness recipe can harm notification contrast.|dark menu light apps|dark dock light windows
"""

    static let items: [TweakItem] = rows.split(separator: "\n").compactMap { line in
        let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 7 else { return nil }
        let kind: TweakKind
        switch fields[0] {
        case "P": kind = .preference
        case "V": kind = .versioned
        case "C": kind = .candidate
        case "A": kind = .advanced
        case "N": kind = .native
        case "H": kind = .helper
        default: kind = .historical
        }
        return TweakItem(id: fields[2], title: fields[3], category: fields[1], kind: kind,
                         summary: fields[4], keywords: fields[5].split(separator: " ").map(String.init),
                         patterns: fields[6].split(separator: ";").map(String.init))
    }

    static let categories = ["Input", "Dock", "Finder", "Windows and dialogs", "Screenshots",
                             "Menu bar", "Built-in apps", "Appearance", "Regional formats",
                             "Diagnostics", "Launchpad", "Power and hardware", "Continuity",
                             "Developer controls", "Enhancements", "Historical"]
}
