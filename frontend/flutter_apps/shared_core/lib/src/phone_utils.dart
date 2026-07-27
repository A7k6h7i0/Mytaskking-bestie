class PhoneCountryRule {
  PhoneCountryRule({
    required this.iso,
    required this.name,
    required this.dial,
    required this.min,
    required this.max,
    this.mobilePattern,
  });

  final String iso;
  final String name;
  final String dial;
  final int min;
  final int max;
  final RegExp? mobilePattern;

  String get label => '$name (+$dial)';
}

class ParsedPhone {
  const ParsedPhone({
    required this.dial,
    required this.national,
    required this.e164,
  });

  final String dial;
  final String national;
  final String e164;
}

const defaultPhoneDial = '91';

final phoneCountries = <PhoneCountryRule>[
  PhoneCountryRule(
    iso: 'IN',
    name: 'India',
    dial: '91',
    min: 10,
    max: 10,
    mobilePattern: RegExp(r'^[6-9]\d{9}$'),
  ),
  PhoneCountryRule(
    iso: 'US',
    name: 'United States',
    dial: '1',
    min: 10,
    max: 10,
    mobilePattern: RegExp(r'^\d{10}$'),
  ),
  PhoneCountryRule(
    iso: 'GB',
    name: 'United Kingdom',
    dial: '44',
    min: 10,
    max: 10,
    mobilePattern: RegExp(r'^\d{10}$'),
  ),
  PhoneCountryRule(
    iso: 'AE',
    name: 'UAE',
    dial: '971',
    min: 9,
    max: 9,
    mobilePattern: RegExp(r'^\d{9}$'),
  ),
  PhoneCountryRule(
    iso: 'SA',
    name: 'Saudi Arabia',
    dial: '966',
    min: 9,
    max: 9,
    mobilePattern: RegExp(r'^\d{9}$'),
  ),
  PhoneCountryRule(
    iso: 'SG',
    name: 'Singapore',
    dial: '65',
    min: 8,
    max: 8,
    mobilePattern: RegExp(r'^\d{8}$'),
  ),
  PhoneCountryRule(
    iso: 'AU',
    name: 'Australia',
    dial: '61',
    min: 9,
    max: 9,
    mobilePattern: RegExp(r'^\d{9}$'),
  ),
  PhoneCountryRule(
    iso: 'BD',
    name: 'Bangladesh',
    dial: '880',
    min: 10,
    max: 10,
    mobilePattern: RegExp(r'^\d{10}$'),
  ),
  PhoneCountryRule(
    iso: 'LK',
    name: 'Sri Lanka',
    dial: '94',
    min: 9,
    max: 9,
    mobilePattern: RegExp(r'^\d{9}$'),
  ),
  PhoneCountryRule(
    iso: 'NP',
    name: 'Nepal',
    dial: '977',
    min: 10,
    max: 10,
    mobilePattern: RegExp(r'^\d{10}$'),
  ),
  PhoneCountryRule(
    iso: 'PK',
    name: 'Pakistan',
    dial: '92',
    min: 10,
    max: 10,
    mobilePattern: RegExp(r'^\d{10}$'),
  ),
  PhoneCountryRule(
    iso: 'QA',
    name: 'Qatar',
    dial: '974',
    min: 8,
    max: 8,
    mobilePattern: RegExp(r'^\d{8}$'),
  ),
  PhoneCountryRule(
    iso: 'KW',
    name: 'Kuwait',
    dial: '965',
    min: 8,
    max: 8,
    mobilePattern: RegExp(r'^\d{8}$'),
  ),
  PhoneCountryRule(
    iso: 'OM',
    name: 'Oman',
    dial: '968',
    min: 8,
    max: 8,
    mobilePattern: RegExp(r'^\d{8}$'),
  ),
  PhoneCountryRule(
    iso: 'BH',
    name: 'Bahrain',
    dial: '973',
    min: 8,
    max: 8,
    mobilePattern: RegExp(r'^\d{8}$'),
  ),
];

final _countriesByDialLength = [...phoneCountries]
  ..sort((a, b) => b.dial.length.compareTo(a.dial.length));

PhoneCountryRule? phoneCountryByDial(String dial) {
  final code = dial.replaceAll(RegExp(r'\D'), '');
  for (final country in phoneCountries) {
    if (country.dial == code) return country;
  }
  return null;
}

PhoneCountryRule get defaultPhoneCountry =>
    phoneCountryByDial(defaultPhoneDial) ?? phoneCountries.first;

String phoneDigitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

bool validateNationalPhone(PhoneCountryRule country, String nationalDigits) {
  final digits = phoneDigitsOnly(nationalDigits);
  if (digits.length < country.min || digits.length > country.max) return false;
  if (country.mobilePattern != null && !country.mobilePattern!.hasMatch(digits)) {
    return false;
  }
  return true;
}

String? buildPhoneE164({required String dialCode, required String national}) {
  final country = phoneCountryByDial(dialCode) ?? defaultPhoneCountry;
  final digits = phoneDigitsOnly(national);
  if (!validateNationalPhone(country, digits)) return null;
  return '+${country.dial}$digits';
}

ParsedPhone? parseStoredPhone(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;

  var digits = trimmed.replaceAll(RegExp(r'[\s\-().]'), '');
  final hasPlus = digits.startsWith('+');
  if (hasPlus) digits = digits.substring(1);
  digits = phoneDigitsOnly(digits);
  if (digits.isEmpty) return null;

  for (final country in _countriesByDialLength) {
    if (digits.startsWith(country.dial)) {
      final national = digits.substring(country.dial.length);
      if (validateNationalPhone(country, national)) {
        return ParsedPhone(
          dial: country.dial,
          national: national,
          e164: '+${country.dial}$national',
        );
      }
    }
  }

  final india = defaultPhoneCountry;
  if (digits.length == 11 && digits.startsWith('0')) {
    final national = digits.substring(1);
    if (validateNationalPhone(india, national)) {
      return ParsedPhone(
        dial: india.dial,
        national: national,
        e164: '+${india.dial}$national',
      );
    }
  }
  if (validateNationalPhone(india, digits)) {
    return ParsedPhone(
      dial: india.dial,
      national: digits,
      e164: '+${india.dial}$digits',
    );
  }
  return null;
}

String? normalizePhoneValue(String? raw) => parseStoredPhone(raw)?.e164;

/// Telecaller legacy format: 10-digit India or E.164 for other countries.
String? normalizeLeadPhone(String raw) {
  final parsed = parseStoredPhone(raw);
  if (parsed == null) return null;
  if (parsed.dial == defaultPhoneDial) return parsed.national;
  return parsed.e164;
}

String? validatePhoneFields({
  required String dialCode,
  required String national,
  bool required = false,
}) {
  final nationalDigits = phoneDigitsOnly(national);
  if (nationalDigits.isEmpty) {
    return required ? 'Phone number is required' : null;
  }
  final country = phoneCountryByDial(dialCode) ?? defaultPhoneCountry;
  if (!validateNationalPhone(country, nationalDigits)) {
    return 'Enter ${country.min}${country.max != country.min ? '-${country.max}' : ''} digit mobile number';
  }
  return null;
}

String? phoneValueFromFields({
  required String dialCode,
  required String national,
  bool required = false,
}) {
  final error = validatePhoneFields(
    dialCode: dialCode,
    national: national,
    required: required,
  );
  if (error != null) return null;
  final nationalDigits = phoneDigitsOnly(national);
  if (nationalDigits.isEmpty) return null;
  return buildPhoneE164(dialCode: dialCode, national: nationalDigits);
}
