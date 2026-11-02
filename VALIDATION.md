# Validation and limits

The initial driver was developed and physically tested on 1 November 2026. The public package was prepared on 2 November 2026.

## Physically verified

* Native Apple Silicon Mac reporting macOS 26.7.2 (25G332), USB HP LaserJet P1008 (VID 03f0, PID 4917).
* A clear physical test page was confirmed by the printer’s owner.
* The on-demand backend reloaded the HP1006 RAM firmware following a power cycle, then successfully printed.
* A single running USB-monitor process detected unplug and reconnect, changed the CUPS offline reason, and showed Offline / Idle in macOS Print Centre.

## Offline checks

* ARM64 executables and ad-hoc code signatures; system library dependencies only.
* CUPS PPD validation.
* Equivalent padded K1/W1/K8/W8 raster fixtures produced identical XQX output; the earlier validation decoded the pages and passed AddressSanitizer/UndefinedBehaviorSanitizer checks.
* Truncated raster rejected before page emission; two requested copies emitted two pages.
* USB helper self-test checks preservation of unrelated queue reasons and addition/removal of only offline-report.
* Public firmware importer tested against the original HP disk image; converted firmware matches the previously printed image’s SHA-256.
* Public release archive checked for firmware exclusion, source inclusion and absence of local device/account identifiers. Installer scripts checked for shell syntax.

## Important limits

The public setup adds firmware import and safer installation preflight checks around the same tested printing components. A clean installation of this public archive on another Mac, including Gatekeeper/quarantine behavior, has not been physically validated. No additional printer job was sent while preparing the public release.

Only one P1008 and one Apple Silicon Mac combination has been physically verified. Intel Macs, other HP models, earlier macOS versions, manual feed and all media options have not been validated. Binaries are ad-hoc signed and are not notarized. CUPS/USB behavior may change after a macOS update.
