'use strict';

const cloudinary = require('cloudinary').v2;
const config = require('../config');

let initialized = false;
function init() {
  if (initialized) return cloudinary;
  if (!config.cloudinary.cloudName) return null;
  cloudinary.config({
    cloud_name: config.cloudinary.cloudName,
    api_key: config.cloudinary.apiKey,
    api_secret: config.cloudinary.apiSecret,
    secure: true,
  });
  initialized = true;
  return cloudinary;
}

async function uploadBuffer(buffer, { folder = 'bestie', publicId } = {}) {
  const c = init();
  if (!c) throw new Error('Cloudinary not configured');
  return new Promise((resolve, reject) => {
    const stream = c.uploader.upload_stream(
      { folder, public_id: publicId, resource_type: 'auto' },
      (err, result) => (err ? reject(err) : resolve(result))
    );
    stream.end(buffer);
  });
}

function signUploadParams({ folder = 'bestie' } = {}) {
  const c = init();
  if (!c) return null;
  const timestamp = Math.round(Date.now() / 1000);
  const signature = c.utils.api_sign_request({ timestamp, folder }, config.cloudinary.apiSecret);
  return { timestamp, folder, signature, apiKey: config.cloudinary.apiKey, cloudName: config.cloudinary.cloudName };
}

function isConfigured() {
  return !!config.cloudinary.cloudName;
}

module.exports = { uploadBuffer, signUploadParams, isConfigured };
