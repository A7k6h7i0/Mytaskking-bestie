'use strict';

/** Org-wide caller voice prompts — merged into GET /settings (calls scope). */
module.exports = {
  ttsVoiceGender: 'female',
  ttsOnAnotherCall: '{name} is busy with another call. Please call again later.',
  ttsOnAnotherCallWaiting:
    '{name} is busy on another call. Waiting for them to respond.',
  ttsCurrentlyOnAnotherCall:
    '{name} is currently on another call. Please call again later.',
  ttsCurrentlyOnAnotherCallLeaveMessage:
    '{name} is currently on another call. Please leave a message.',
  ttsMeeting: 'Sorry {name} is in a meeting from {start} to {end}',
  ttsMeetingFallback: 'Sorry {name} is in a meeting',
  ttsLunch: '{name} is at lunch. Please leave a message.',
  ttsLeave: '{name} is on leave. Please leave a message.',
  ttsBusy: '{name} is busy. Please leave a message.',
  ttsAway: '{name} is away. Please leave a message.',
  ttsGenericUnavailable: '{name} is {status}. Please leave a message.',
  ttsIncomingWaitingCall:
    '{caller} is calling while you are on another call. Accept to add them, or reject.',
};

module.exports.TTS_KEYS = Object.keys(module.exports).filter(
  (k) => k !== 'TTS_KEYS',
);

module.exports.TTS_VOICE_GENDERS = ['male', 'female'];

module.exports.sanitizeTtsPatch = (key, value) => {
  if (!module.exports.TTS_KEYS.includes(key)) return value;
  if (key === 'ttsVoiceGender') {
    const v = String(value || '').toLowerCase();
    return module.exports.TTS_VOICE_GENDERS.includes(v) ? v : 'female';
  }
  const text = String(value ?? '').trim();
  if (!text) return module.exports[key];
  return text.slice(0, 240);
};
