// USB readers need `dart:ffi`; the web build shows the simulated card only.
export 'package:eid_ccid_example/src/hardware/hardware_none.dart'
    if (dart.library.ffi) 'package:eid_ccid_example/src/hardware/hardware_ccid.dart';
