'use strict';

const nodemailer = require('nodemailer');
const logger = require('../../utils/logger');

const FROM = process.env.EMAIL_FROM || 'no-reply@mytaskking.com';

let transporter;

function getTransporter() {
  if (transporter) return transporter;
  transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: Number(process.env.SMTP_PORT || 587),
    secure: process.env.SMTP_SECURE === 'true',
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
  return transporter;
}

async function sendMail(payload) {
  const transport = getTransporter();
  if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
    logger.warn({ to: payload.to, subject: payload.subject }, 'email.nodemailer.missing_smtp_creds');
    return { ok: true, provider: 'nodemailer-dev-log' };
  }
  const info = await transport.sendMail({
    from: FROM,
    to: payload.to,
    subject: payload.subject,
    text: payload.text,
    html: payload.html,
  });
  logger.info({ to: payload.to, messageId: info.messageId }, 'email.nodemailer.sent');
  return { ok: true, provider: 'nodemailer', messageId: info.messageId };
}

module.exports = { sendMail };
