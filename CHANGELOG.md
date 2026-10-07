## 0.1.1

- The README opens on a picture of which packages to add for each document,
  and lists eid_icao and eid_nfc among the other eid packages. pub.dev shows
  the same picture as a screenshot.
- The example reads with eid_belgium 0.1.1 and offers its
  `showPrivateData` option, so the national register number is shown only
  when asked for.
- The example no longer hangs on Android when the card or the reader is
  drawn at zero size before the first frame.

## 0.1.0

- First release: `CcidTransport` reaches the card in a USB or PC/SC reader
  on Android, iOS, macOS, Windows and Linux.
- `CcidTerminal` for a watcher, `CcidTerminal.any()` for every reader at
  once.
- The example reads a simulated or real Belgian eID, in the browser too.
