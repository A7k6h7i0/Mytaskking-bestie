'use strict';

const assert = require('assert');
const {
  buildPhone,
  parsePhoneInput,
  normalizePhoneValue,
  normalizeLeadPhone,
  validateNational,
  countryByDial,
} = require('../src/utils/phone');

function run() {
  assert.strictEqual(buildPhone('91', '7076119520'), '+917076119520');
  assert.strictEqual(buildPhone('91', '5076119520'), null);
  assert.strictEqual(buildPhone('971', '501234567'), '+971501234567');

  const parsed = parsePhoneInput('+917076119520');
  assert.deepStrictEqual(parsed, {
    dial: '91',
    national: '7076119520',
    e164: '+917076119520',
  });
  assert.deepStrictEqual(parsePhoneInput('07076119520'), parsed);
  assert.deepStrictEqual(parsePhoneInput('7076119520'), parsed);

  assert.strictEqual(normalizePhoneValue('7076119520'), '+917076119520');
  assert.strictEqual(normalizeLeadPhone('7076119520'), '7076119520');
  assert.strictEqual(normalizeLeadPhone('+971501234567'), '+971501234567');
  assert.strictEqual(normalizePhoneValue('invalid'), null);

  const india = countryByDial('91');
  assert.strictEqual(validateNational(india, '7076119520'), true);
  assert.strictEqual(validateNational(india, '123'), false);

  console.log('phone.test.js: all passed');
}

run();
