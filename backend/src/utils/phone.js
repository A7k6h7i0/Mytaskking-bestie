'use strict';

const Joi = require('joi');

/** @type {{ iso: string, name: string, dial: string, min: number, max: number, pattern?: RegExp }[]} */
const PHONE_COUNTRIES = [
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

const DEFAULT_DIAL = '91';
const DIAL_SORTED = [...PHONE_COUNTRIES].sort((a, b) => b.dial.length - a.dial.length);

function countryByDial(dial) {
  const code = String(dial || '').replace(/\D/g, '');
  return PHONE_COUNTRIES.find((c) => c.dial === code) || null;
}

function defaultCountry() {
  return countryByDial(DEFAULT_DIAL) || PHONE_COUNTRIES[0];
}

function digitsOnly(value) {
  return String(value || '').replace(/\D/g, '');
}

function validateNational(country, nationalDigits) {
  if (!country) return false;
  const digits = digitsOnly(nationalDigits);
  if (digits.length < country.min || digits.length > country.max) return false;
  if (country.pattern && !country.pattern.test(digits)) return false;
  return true;
}

/**
 * Build E.164 phone (+<dial><national>) or return null if invalid.
 */
function buildPhone(dialCode, nationalNumber) {
  const country = countryByDial(dialCode) || defaultCountry();
  const national = digitsOnly(nationalNumber);
  if (!validateNational(country, national)) return null;
  return `+${country.dial}${national}`;
}

/**
 * Parse stored / pasted phone into dial + national for UI, or null.
 */
function parsePhoneInput(raw) {
  const trimmed = String(raw || '').trim();
  if (!trimmed) return null;

  let digits = trimmed.replace(/[\s\-().]/g, '');
  const hasPlus = digits.startsWith('+');
  if (hasPlus) digits = digits.slice(1);
  digits = digits.replace(/\D/g, '');
  if (!digits) return null;

  for (const country of DIAL_SORTED) {
    if (digits.startsWith(country.dial)) {
      const national = digits.slice(country.dial.length);
      if (validateNational(country, national)) {
        return { dial: country.dial, national, e164: `+${country.dial}${national}` };
      }
    }
  }

  const india = countryByDial(DEFAULT_DIAL);
  if (digits.length === 11 && digits.startsWith('0')) {
    const national = digits.slice(1);
    if (validateNational(india, national)) {
      return { dial: india.dial, national, e164: `+${india.dial}${national}` };
    }
  }
  if (validateNational(india, digits)) {
    return { dial: india.dial, national: digits, e164: `+${india.dial}${digits}` };
  }

  return null;
}

/**
 * Normalize any accepted phone string to E.164, or null if invalid.
 */
function normalizePhoneValue(raw) {
  if (raw == null) return null;
  const text = String(raw).trim();
  if (!text) return null;
  const parsed = parsePhoneInput(text);
  return parsed ? parsed.e164 : null;
}

function normalizePhoneNumber(value) {
  const normalized = normalizePhoneValue(value);
  if (normalized) return normalized;
  return String(value || '').trim().replace(/[^\d+]/g, '');
}

/** @deprecated alias kept for telecaller imports */
function normalizeLeadPhone(value) {
  const parsed = parsePhoneInput(value);
  if (!parsed) return null;
  if (parsed.dial === DEFAULT_DIAL) return parsed.national;
  return parsed.e164;
}

function joiPhone({ required = false } = {}) {
  let schema = Joi.string().trim().max(24);
  if (required) schema = schema.required();
  else schema = schema.allow('', null);

  return schema.custom((value, helpers) => {
    if (value === '' || value == null) {
      return required ? helpers.error('any.required') : null;
    }
    const normalized = normalizePhoneValue(value);
    if (!normalized) {
      return helpers.error('any.custom', {
        message: 'Enter a valid mobile number with country code',
      });
    }
    return normalized;
  });
}

module.exports = {
  PHONE_COUNTRIES,
  DEFAULT_DIAL,
  countryByDial,
  defaultCountry,
  digitsOnly,
  validateNational,
  buildPhone,
  parsePhoneInput,
  normalizePhoneValue,
  normalizePhoneNumber,
  normalizeLeadPhone,
  joiPhone,
};
