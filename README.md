# eid_ccid

[![Pub Version](https://img.shields.io/pub/v/eid_ccid?color=0175C2)](https://pub.dev/packages/eid_ccid)
[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/eid_ccid/ci.yml?branch=main&label=build)](https://github.com/raphrmx/eid_ccid/actions/workflows/ci.yml)
![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-733d90)
[![Licence](https://img.shields.io/badge/Licence-MIT-8C6A3F)](LICENSE)
![Platforms](https://img.shields.io/badge/Platforms-Android,_iOS,_macOS,_Windows,_Linux-22375C.svg)
[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=ZN6D382YQAV5N)

Reads electronic identity cards through a USB or PC/SC card reader in
Flutter: the `eid` transport for the [ccid](https://pub.dev/packages/ccid)
plugin.

## Install

```yaml
dependencies:
  eid_ccid: ^0.1.0
  eid_belgium: ^0.1.0 # or another country
```

| Platform | Through | Setup |
| --- | --- | --- |
| Windows | PC/SC | None |
| Linux | PC/SC | `pcscd` and `libpcsclite1` |
| macOS, iOS | CryptoTokenKit | The `com.apple.security.smartcard` entitlement |
| Android | USB host mode | A reader on USB OTG |

Browsers cannot reach a card reader.

## Read a card

```dart
final readers = await CcidTransport.listReaders();
final transport = await CcidTransport.connect(readers.first);
try {
  final eid = await BelgianEidReader(transport).read();
} finally {
  await transport.disconnect();
}
```

## Read on insertion

```dart
final watcher = BelgianEidWatcher(CcidTerminal.any())..start();
```

`CcidTerminal.any()` watches every reader, those plugged in later included;
`CcidTerminal.list()` gives each one.

## License

Released under the [MIT licence](https://pub.dev/packages/eid_ccid/license).

## More from COMAPPS

Electronic identity cards in Dart:

| Package | What it does |
| --- | --- |
| [eid](https://pub.dev/packages/eid) | APDUs, ISO 7816-4 file reading and the values national cards share. |
| [eid_belgium](https://pub.dev/packages/eid_belgium) | Reads the Belgian eID, Kids ID and residence cards. |

Every package COMAPPS publishes is listed at
[packages.comapps.be](https://packages.comapps.be).
