import { useEffect, useMemo, useState } from 'react';
import clsx from 'clsx';
import {
  DEFAULT_PHONE_DIAL,
  PHONE_COUNTRIES,
  parseStoredPhone,
  phoneCountryByDial,
  phoneDigitsOnly,
  phoneValueFromFields,
  validatePhoneFields,
} from '@/lib/phone';
import './phone-input.css';

type PhoneInputProps = {
  label?: string;
  hint?: string;
  error?: string;
  required?: boolean;
  initialStoredPhone?: string | null;
  national: string;
  dialCode?: string;
  onNationalChange: (value: string) => void;
  onDialCodeChange?: (value: string) => void;
  className?: string;
};

export function PhoneInput({
  label,
  hint,
  error,
  required = false,
  initialStoredPhone,
  national,
  dialCode,
  onNationalChange,
  onDialCodeChange,
  className,
}: PhoneInputProps) {
  const parsedInitial = useMemo(
    () => parseStoredPhone(initialStoredPhone),
    [initialStoredPhone]
  );
  const [internalDial, setInternalDial] = useState(
    dialCode ?? parsedInitial?.dial ?? DEFAULT_PHONE_DIAL
  );

  useEffect(() => {
    if (dialCode != null) setInternalDial(dialCode);
  }, [dialCode]);

  useEffect(() => {
    if (parsedInitial && !national.trim()) {
      onNationalChange(parsedInitial.national);
      setInternalDial(parsedInitial.dial);
      onDialCodeChange?.(parsedInitial.dial);
    }
  }, [parsedInitial, national, onDialCodeChange, onNationalChange]);

  const country = phoneCountryByDial(internalDial) ?? PHONE_COUNTRIES[0];
  const localError =
    error ??
    validatePhoneFields({ dialCode: internalDial, national, required }) ??
    undefined;

  return (
    <label className={clsx('bpi', localError && 'bpi--error', className)}>
      {label && <span className="bpi__label">{label}</span>}
      <span className="bpi__row">
        <select
          className="bpi__country"
          value={internalDial}
          onChange={(e) => {
            setInternalDial(e.target.value);
            onDialCodeChange?.(e.target.value);
          }}
        >
          {PHONE_COUNTRIES.map((entry) => (
            <option key={entry.iso} value={entry.dial}>
              +{entry.dial}
            </option>
          ))}
        </select>
        <input
          className="bpi__number"
          inputMode="numeric"
          pattern="[0-9]*"
          maxLength={country.max}
          placeholder={`${country.min}-digit number`}
          value={national}
          onChange={(e) => onNationalChange(phoneDigitsOnly(e.target.value))}
        />
      </span>
      {(localError || hint) && <span className="bpi__hint">{localError || hint}</span>}
    </label>
  );
}

export function usePhoneField(initialStoredPhone?: string | null) {
  const parsed = parseStoredPhone(initialStoredPhone);
  const [dialCode, setDialCode] = useState(parsed?.dial ?? DEFAULT_PHONE_DIAL);
  const [national, setNational] = useState(parsed?.national ?? '');

  const value = phoneValueFromFields({ dialCode, national, required: false });
  const error = validatePhoneFields({ dialCode, national, required: false });

  function validate(required = false) {
    return validatePhoneFields({ dialCode, national, required });
  }

  function buildValue(required = false) {
    return phoneValueFromFields({ dialCode, national, required });
  }

  return {
    dialCode,
    setDialCode,
    national,
    setNational,
    value,
    error,
    validate,
    buildValue,
  };
}
