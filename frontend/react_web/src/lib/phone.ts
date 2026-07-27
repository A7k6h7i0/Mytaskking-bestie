export type PhoneCountryRule = {
  iso: string;
  name: string;
  dial: string;
  min: number;
  max: number;
  pattern?: RegExp;
};

export type ParsedPhone = {
  dial: string;
  national: string;
  e164: string;
};

export const DEFAULT_PHONE_DIAL = '91';

export const PHONE_COUNTRIES: PhoneCountryRule[] = [
  { iso: 'IN', name: 'India', dial: '91', min: 10, max: 10, pattern: /^[6-9]\d{9}$/ },
  { iso: 'US', name: 'United States', dial: '1', min: 10, max: 10, pattern: /^\d{10}$/ },
  { iso: 'GB', name: 'United Kingdom', dial: '44', min: 10, max: 10, pattern: /^\d{10}$/ },
  { iso: 'AE', name: 'UAE', dial: '971', min: 9, max: 9, pattern: /^\d{9}$/ },
  { iso: 'SA', name: 'Saudi Arabia', dial: '966', min: 9, max: 9, pattern: /^\d{9}$/ },
  { iso: 'SG', name: 'Singapore', dial: '65', min: 8, max: 8, pattern: /^\d{8}$/ },
  { iso: 'AU', name: 'Australia', dial: '61', min: 9, max: 9, pattern: /^\d{9}$/ },
  { iso: 'BD', name: 'Bangladesh', dial: '880', min: 10, max: 10, pattern: /^\d{10}$/ },
  { iso: 'LK', name: 'Sri Lanka', dial: '94', min: 9, max: 9, pattern: /^\d{9}$/ },
  { iso: 'NP', name: 'Nepal', dial: '977', min: 10, max: 10, pattern: /^\d{10}$/ },
  { iso: 'PK', name: 'Pakistan', dial: '92', min: 10, max: 10, pattern: /^\d{10}$/ },
  { iso: 'QA', name: 'Qatar', dial: '974', min: 8, max: 8, pattern: /^\d{8}$/ },
  { iso: 'KW', name: 'Kuwait', dial: '965', min: 8, max: 8, pattern: /^\d{8}$/ },
  { iso: 'OM', name: 'Oman', dial: '968', min: 8, max: 8, pattern: /^\d{8}$/ },
  { iso: 'BH', name: 'Bahrain', dial: '973', min: 8, max: 8, pattern: /^\d{8}$/ },
];

const DIAL_SORTED = [...PHONE_COUNTRIES].sort((a, b) => b.dial.length - a.dial.length);

export function phoneCountryByDial(dial: string) {
  const code = dial.replace(/\D/g, '');
  return PHONE_COUNTRIES.find((c) => c.dial === code) ?? null;
}

export function defaultPhoneCountry() {
  return phoneCountryByDial(DEFAULT_PHONE_DIAL) ?? PHONE_COUNTRIES[0];
}

export function phoneDigitsOnly(value: string) {
  return String(value || '').replace(/\D/g, '');
}

export function validateNationalPhone(country: PhoneCountryRule, nationalDigits: string) {
  const digits = phoneDigitsOnly(nationalDigits);
  if (digits.length < country.min || digits.length > country.max) return false;
  if (country.pattern && !country.pattern.test(digits)) return false;
  return true;
}

export function buildPhoneE164(dialCode: string, national: string) {
  const country = phoneCountryByDial(dialCode) ?? defaultPhoneCountry();
  const digits = phoneDigitsOnly(national);
  if (!validateNationalPhone(country, digits)) return null;
  return `+${country.dial}${digits}`;
}

export function parseStoredPhone(raw?: string | null): ParsedPhone | null {
  const trimmed = String(raw || '').trim();
  if (!trimmed) return null;

  let digits = trimmed.replace(/[\s\-().]/g, '');
  const hasPlus = digits.startsWith('+');
  if (hasPlus) digits = digits.slice(1);
  digits = phoneDigitsOnly(digits);
  if (!digits) return null;

  for (const country of DIAL_SORTED) {
    if (digits.startsWith(country.dial)) {
      const national = digits.slice(country.dial.length);
      if (validateNationalPhone(country, national)) {
        return { dial: country.dial, national, e164: `+${country.dial}${national}` };
      }
    }
  }

  const india = defaultPhoneCountry();
  if (digits.length === 11 && digits.startsWith('0')) {
    const national = digits.slice(1);
    if (validateNationalPhone(india, national)) {
      return { dial: india.dial, national, e164: `+${india.dial}${national}` };
    }
  }
  if (validateNationalPhone(india, digits)) {
    return { dial: india.dial, national: digits, e164: `+${india.dial}${digits}` };
  }
  return null;
}

export function normalizePhoneValue(raw?: string | null) {
  return parseStoredPhone(raw)?.e164 ?? null;
}

export function normalizeLeadPhone(raw: string) {
  const parsed = parseStoredPhone(raw);
  if (!parsed) return null;
  if (parsed.dial === DEFAULT_PHONE_DIAL) return parsed.national;
  return parsed.e164;
}

export function validatePhoneFields({
  dialCode,
  national,
  required = false,
}: {
  dialCode: string;
  national: string;
  required?: boolean;
}) {
  const nationalDigits = phoneDigitsOnly(national);
  if (!nationalDigits) return required ? 'Phone number is required' : null;
  const country = phoneCountryByDial(dialCode) ?? defaultPhoneCountry();
  if (!validateNationalPhone(country, nationalDigits)) {
    const range = country.min === country.max ? `${country.min}` : `${country.min}-${country.max}`;
    return `Enter a valid ${range}-digit mobile number`;
  }
  return null;
}

export function phoneValueFromFields({
  dialCode,
  national,
  required = false,
}: {
  dialCode: string;
  national: string;
  required?: boolean;
}) {
  if (validatePhoneFields({ dialCode, national, required })) return null;
  const nationalDigits = phoneDigitsOnly(national);
  if (!nationalDigits) return null;
  return buildPhoneE164(dialCode, nationalDigits);
}
