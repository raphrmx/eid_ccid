import 'package:eid_belgium/eid_belgium.dart';

/// The three 30-character lines of the TD1 MRZ (ICAO 9303) on the back.
List<String> mrzLines(BelgianIdentity identity) {
  final number = _clean(identity.cardNumber);
  // Over nine characters, the number overflows into the optional data.
  final String documentField;
  if (number.length > 9) {
    documentField =
        '${number.substring(0, 9)}<${number.substring(9)}${_check(number)}';
  } else {
    documentField = '${_pad(number, 9)}${_check(_pad(number, 9))}';
  }
  final line1 = _pad('IDBEL$documentField', 30);

  final birth = _date(identity.birthDate);
  final expiry = _date(PartialDate(
    identity.validUntil.year,
    identity.validUntil.month,
    identity.validUntil.day,
  ));
  final sex = switch (identity.sex) {
    Sex.male => 'M',
    Sex.female => 'F',
    Sex.unspecified => '<',
  };
  // Fillers where the national number goes when it was not read.
  final optional = _pad(_clean(identity.nationalNumber ?? ''), 11);
  final birthField = '$birth${_check(birth)}';
  final expiryField = '$expiry${_check(expiry)}';
  final composite = _check(
    '${line1.substring(5)}$birthField$expiryField$optional',
  );
  final line2 = '$birthField$sex${expiryField}BEL$optional$composite';

  final names = '${_clean(identity.lastName)}<<'
      '${_clean(identity.firstNames)}';
  final line3 = _pad(names, 30).substring(0, 30);

  return [line1, line2, line3];
}

String _date(PartialDate? date) {
  if (date == null) return '<<<<<<';
  final year = (date.year % 100).toString().padLeft(2, '0');
  final month = date.month?.toString().padLeft(2, '0') ?? '<<';
  final day = date.day?.toString().padLeft(2, '0') ?? '<<';
  return '$year$month$day';
}

/// ICAO 9303 check digit: weights 7, 3, 1; A is 10, the filler 0.
int _check(String field) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < field.length; i++) {
    final unit = field.codeUnitAt(i);
    final value = switch (unit) {
      >= 0x30 && <= 0x39 => unit - 0x30,
      >= 0x41 && <= 0x5A => unit - 0x41 + 10,
      _ => 0,
    };
    sum += value * weights[i % 3];
  }
  return sum % 10;
}

String _pad(String text, int length) =>
    text.length >= length ? text : text.padRight(length, '<');

/// Upper case, accents dropped, anything else a filler.
String _clean(String text) {
  const accents = {
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ä': 'A', 'Ç': 'C', 'È': 'E', 'É': 'E', //
    'Ê': 'E', 'Ë': 'E', 'Î': 'I', 'Ï': 'I', 'Ô': 'O', 'Ö': 'O', 'Ù': 'U',
    'Û': 'U', 'Ü': 'U', 'Ÿ': 'Y',
  };
  final buffer = StringBuffer();
  for (final char in text.toUpperCase().split('')) {
    final plain = accents[char] ?? char;
    buffer.write(RegExp('[A-Z0-9]').hasMatch(plain) ? plain : '<');
  }
  return buffer.toString();
}
