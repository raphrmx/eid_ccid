import 'dart:convert';
import 'dart:typed_data';

import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_ccid_example/src/eid_session.dart';
import 'package:eid_ccid_example/src/palette.dart';
import 'package:flutter/material.dart';

/// Where the holder lives, which only the contact chip holds.
class AddressPanel extends StatelessWidget {
  const AddressPanel({super.key, required this.eid});

  final BelgianEid eid;

  @override
  Widget build(BuildContext context) {
    final address = eid.address;
    final identity = eid.identity;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title(Icons.home_outlined, 'Address'),
          const SizedBox(height: 14),
          if (address == null)
            const Text(
              'Not read: parts leaves the address out',
              style: TextStyle(fontSize: 15, color: Palette.muted),
            )
          else ...[
            Text(
              address.streetAndNumber,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Palette.ink,
              ),
            ),
            Text(
              '${address.postalCode} ${address.municipality}',
              style: const TextStyle(fontSize: 16, color: Palette.ink),
            ),
          ],
          const SizedBox(height: 18),
          const Caption('Born in'),
          Text(identity.birthPlace, style: const TextStyle(color: Palette.ink)),
          const SizedBox(height: 10),
          const Caption('Card issued in'),
          Text(
            identity.issuingMunicipality,
            style: const TextStyle(color: Palette.ink),
          ),
        ],
      ),
    );
  }
}

/// What the app could check on its own, with no server.
class ChecksPanel extends StatelessWidget {
  const ChecksPanel({super.key, required this.session});

  final EidSession session;

  @override
  Widget build(BuildContext context) {
    final eid = session.eid!;
    final identity = eid.identity;
    final info = session.cardInfo;
    final time = session.readTime;
    final nationalNumber = identity.nationalNumber;
    final age = identity.age;
    final photoMatches = session.photoMatches;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title(Icons.fact_check_outlined, 'Checks'),
          const SizedBox(height: 12),
          _Check(
            ok: photoMatches,
            label: eid.photo == null
                ? 'Photo not read'
                : photoMatches
                    ? 'Photo matches the signed hash'
                    : 'Photo does not match its hash',
          ),
          _Check(
            ok: eid.signaturesVerified,
            pending: !eid.signaturesVerified,
            label: eid.signaturesVerified
                ? 'Signed by the national register'
                : 'Signatures not checked',
          ),
          _Check(
            ok: eid.authenticity == BelgianCardAuthenticity.genuine,
            pending: eid.authenticity != BelgianCardAuthenticity.genuine,
            label: switch (eid.authenticity) {
              BelgianCardAuthenticity.genuine =>
                'Genuine chip: it proved its basic key',
              BelgianCardAuthenticity.notSupported =>
                'Older card: its chip cannot prove itself',
              _ => 'Chip not asked to prove itself',
            },
          ),
          _Check(
            ok: !identity.isExpired,
            label: identity.isExpired
                ? 'Card expired on ${_day(identity.validUntil)}'
                : 'Card valid until ${_day(identity.validUntil)}',
          ),
          _Check(
            ok: identity.isAdult,
            label: identity.isAdult
                ? 'Holder is 18 or older'
                : 'Holder is not known to be 18',
          ),
          _Check(
            ok: nationalNumber != null &&
                isValidBelgianNationalNumber(nationalNumber),
            pending: nationalNumber == null,
            label: nationalNumber == null
                ? 'National number not read'
                : 'National number check digits',
          ),
          _Check(
            ok: session.holderVerified,
            pending: !session.holderVerified,
            label: session.holderVerified
                ? 'PIN checked by the card'
                : 'PIN not checked yet',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (info != null)
                _Tag(
                    'Applet ${info.appletVersion >> 4}.${info.appletVersion & 0xF}'),
              _Tag(_documentType(identity)),
              if (age != null) _Tag('Age $age'),
              if (session.pinTriesLeft case final tries?)
                _Tag('PIN: $tries ${tries == 1 ? 'try' : 'tries'} left'),
              if (eid.photo != null && !session.photoFromCard)
                const _Tag('Photo from cache'),
              if (time != null)
                _Tag(
                    'Read in ${(time.inMilliseconds / 1000).toStringAsFixed(1)} s'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Every field and certificate, to check a real card against the docs.
class DetailsPanel extends StatelessWidget {
  const DetailsPanel({super.key, required this.session});

  final EidSession session;

  @override
  Widget build(BuildContext context) {
    final eid = session.eid!;
    return Panel(
      padding: 8,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Column(
          children: [
            ExpansionTile(
              leading: const Icon(Icons.data_object, color: Palette.accent),
              title: const Text('Raw fields'),
              subtitle: Text(
                '${eid.identity.fields.length} identity, '
                '${eid.address?.fields.length ?? 0} address',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _fields('Identity file', eid.identity.fields, _identityTags),
                if (eid.address case final address?) ...[
                  const SizedBox(height: 12),
                  _fields('Address file', address.fields, _addressTags),
                ],
              ],
            ),
            ExpansionTile(
              leading: const Icon(Icons.workspace_premium_outlined,
                  color: Palette.accent),
              title: const Text('Certificates'),
              subtitle: Text(_certificatesSummary(session)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (session.certificates case final certificates?)
                  for (final (label, certificate) in [
                    ('Authentication', certificates.authentication),
                    ('Signature', certificates.signing),
                    ('CA', certificates.ca),
                    ('Root', certificates.root),
                    ('National register', certificates.nationalRegister),
                  ])
                    _CertificateRow(
                      label: label,
                      certificate: certificate,
                      failure: session.certificateFailures[certificate],
                      isRoot: label == 'Root',
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: session.busy ? null : session.readCertificates,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Read the certificates'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fields(
    String title,
    Map<int, Uint8List> fields,
    Map<int, String> names,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Caption(title),
        const SizedBox(height: 6),
        for (final MapEntry(key: tag, value: bytes) in fields.entries)
          _Row(
            '${hexString([tag])}  ${names[tag] ?? 'unknown'}',
            bytes.isEmpty ? '(empty)' : _printable(bytes),
          ),
      ],
    );
  }
}

String _certificatesSummary(EidSession session) {
  final certificates = session.certificates;
  if (certificates == null) return 'Not read yet';
  final count = [
    certificates.authentication,
    certificates.signing,
    certificates.ca,
    certificates.root,
    certificates.nationalRegister,
  ].nonNulls.length;
  return session.certificateFailures.isEmpty
      ? '$count on this card, all from a trusted root'
      : '$count on this card, ${session.certificateFailures.length} untrusted';
}

/// One certificate: subject, issuer, expiry and whether it chains up.
class _CertificateRow extends StatelessWidget {
  const _CertificateRow({
    required this.label,
    required this.certificate,
    required this.failure,
    required this.isRoot,
  });

  final String label;
  final BelgianCertificate? certificate;
  final BelgianSignatureException? failure;

  /// The card's own copy of its root, which is shown but never trusted.
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    final certificate = this.certificate;
    if (certificate == null) return _Row(label, 'none on this card');
    final until = certificate.notAfter;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Text(
              label,
              style: const TextStyle(color: Palette.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  certificate.subject.commonName ?? '$certificate',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Palette.ink,
                  ),
                ),
                Text(
                  'By ${certificate.issuer.commonName}, until '
                  '${_day(until)}, ${certificate.keyAlgorithm}',
                  style: const TextStyle(fontSize: 12, color: Palette.muted),
                ),
                if (!isRoot)
                  Text(
                    failure == null
                        ? 'Chains up to a trusted root'
                        : failure!.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: failure == null ? Palette.success : Palette.danger,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Palette.accent),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Palette.ink,
          ),
        ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.label, this.pending = false});

  final bool ok;
  final bool pending;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = pending
        ? Palette.muted
        : ok
            ? Palette.success
            : Palette.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              pending
                  ? Icons.radio_button_unchecked
                  : ok
                      ? Icons.check_circle
                      : Icons.cancel,
              key: ValueKey('$pending$ok'),
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(color: Palette.ink)),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Palette.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.line),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Palette.muted),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Text(
              label,
              style: const TextStyle(color: Palette.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: Palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _day(DateTime date) =>
    formatBelgianDate(date, BelgianLanguage.en, numeric: true);

String _documentType(BelgianIdentity identity) =>
    identity.documentType?.label(BelgianLanguage.en) ??
    'Type ${identity.documentTypeCode}';

String _printable(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final isText = text.runes.every((r) => r >= 0x20 && r != 0xFFFD);
  return isText ? '"$text"' : hexString(bytes);
}

const _identityTags = {
  0x00: 'file structure version',
  0x01: 'card number',
  0x02: 'chip number',
  0x03: 'valid from',
  0x04: 'valid until',
  0x05: 'issuing municipality',
  0x06: 'national number',
  0x07: 'last name',
  0x08: 'first names',
  0x09: 'third name initial',
  0x0A: 'nationality',
  0x0B: 'birth place',
  0x0C: 'birth date',
  0x0D: 'sex',
  0x0E: 'noble condition',
  0x0F: 'document type',
  0x10: 'special status',
  0x11: 'photo hash',
  0x12: 'duplicate',
  0x13: 'special organisation',
  0x14: 'member of family',
  0x15: 'date and country of protection',
  0x16: 'work permit mention',
  0x17: 'employer VAT number 1',
  0x18: 'employer VAT number 2',
  0x19: 'regional file number',
  0x1A: 'basic key hash',
  0x1B: 'Brexit mention 1',
  0x1C: 'Brexit mention 2',
  0x1D: 'A-card mention 1',
  0x1E: 'A-card mention 2',
  0x1F: 'registration date',
};

const _addressTags = {
  0x00: 'file structure version',
  0x01: 'street and number',
  0x02: 'postal code',
  0x03: 'municipality',
};
