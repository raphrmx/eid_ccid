# eid_ccid example

Reads a Belgian eID through a USB card reader, or a simulated card (PIN
1234), and shows every option of `eid_belgium`.

```bash
flutter run -d windows   # or macos, linux, android, chrome
```

The web build has the simulated card only. Its holder and photo are fictional.
The command log can be copied to report a card that reads wrong; it never
shows the PIN.
