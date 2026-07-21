'use strict';

const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const prisma = require('../database/prisma');
const config = require('../config');
const email = require('./email');
const { BadRequest, Unauthorized } = require('../utils/errors');

const OTP_TTL_MS = 10 * 60 * 1000;
const OTP_PURPOSES = new Set(['org_register']);

function generateCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

async function sendOtp({ email: emailAddress, phone, purpose }) {
  if (!OTP_PURPOSES.has(purpose)) throw BadRequest('Invalid OTP purpose');
  const normalizedEmail = String(emailAddress || '').trim().toLowerCase();
  if (!normalizedEmail.includes('@')) throw BadRequest('Valid email is required');
  const normalizedPhone = String(phone || '').replace(/\D/g, '');
  if (normalizedPhone.length < 10) throw BadRequest('Valid phone number is required');

  const code = generateCode();
  const codeHash = await bcrypt.hash(code, 10);
  const expiresAt = new Date(Date.now() + OTP_TTL_MS);

  await prisma.emailOtp.create({
    data: {
      email: normalizedEmail,
      phone: normalizedPhone,
      codeHash,
      purpose,
      expiresAt,
    },
  });

  await email.send({
    to: normalizedEmail,
    subject: 'MyTaskKing verification code',
    text: `Your MyTaskKing verification code is ${code}. It expires in 10 minutes.`,
    html: `<p>Your MyTaskKing verification code is <strong>${code}</strong>.</p><p>Registered phone: ${normalizedPhone}</p><p>Expires in 10 minutes.</p>`,
    tags: ['otp', purpose],
  });

  return { ok: true, expiresInSec: OTP_TTL_MS / 1000 };
}

async function verifyOtp({ email: emailAddress, code, purpose }) {
  if (!OTP_PURPOSES.has(purpose)) throw BadRequest('Invalid OTP purpose');
  const normalizedEmail = String(emailAddress || '').trim().toLowerCase();
  const otp = await prisma.emailOtp.findFirst({
    where: {
      email: normalizedEmail,
      purpose,
      verifiedAt: null,
      expiresAt: { gt: new Date() },
    },
    orderBy: { createdAt: 'desc' },
  });
  if (!otp) throw Unauthorized('OTP expired or not found');
  const ok = await bcrypt.compare(String(code || ''), otp.codeHash);
  if (!ok) throw Unauthorized('Invalid OTP code');

  await prisma.emailOtp.update({
    where: { id: otp.id },
    data: { verifiedAt: new Date() },
  });

  const token = jwt.sign(
    { email: normalizedEmail, phone: otp.phone, purpose, otpId: otp.id },
    config.jwt.accessSecret,
    { expiresIn: '30m', subject: 'otp-verification' },
  );

  return { verificationToken: token, phone: otp.phone, email: normalizedEmail };
}

function assertVerificationToken(token, purpose = 'org_register') {
  try {
    const payload = jwt.verify(token, config.jwt.accessSecret);
    if (payload.sub !== 'otp-verification' || payload.purpose !== purpose) {
      throw Unauthorized('Invalid verification token');
    }
    return payload;
  } catch {
    throw Unauthorized('Invalid or expired verification token');
  }
}

module.exports = { sendOtp, verifyOtp, assertVerificationToken };
