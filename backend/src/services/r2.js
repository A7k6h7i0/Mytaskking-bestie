'use strict';

const { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { nanoid } = require('nanoid');
const config = require('../config');

let client;
function getClient() {
  if (client) return client;
  if (!config.r2.endpoint || !config.r2.accessKeyId) return null;
  client = new S3Client({
    region: 'auto',
    endpoint: config.r2.endpoint,
    credentials: {
      accessKeyId: config.r2.accessKeyId,
      secretAccessKey: config.r2.secretAccessKey,
    },
  });
  return client;
}

function publicUrlFor(key) {
  if (config.r2.publicBaseUrl) return `${config.r2.publicBaseUrl.replace(/\/$/, '')}/${key}`;
  return `${config.r2.endpoint}/${config.r2.bucket}/${key}`;
}

async function putBuffer({ buffer, key, contentType }) {
  const c = getClient();
  if (!c) throw new Error('Cloudflare R2 not configured');
  await c.send(
    new PutObjectCommand({
      Bucket: config.r2.bucket,
      Key: key,
      Body: buffer,
      ContentType: contentType,
    })
  );
  return { key, url: publicUrlFor(key) };
}

async function presignPut({ filename, contentType, folder = 'files' }) {
  const c = getClient();
  if (!c) return null;
  const key = `${folder}/${Date.now()}-${nanoid(10)}-${filename}`;
  const cmd = new PutObjectCommand({ Bucket: config.r2.bucket, Key: key, ContentType: contentType });
  const url = await getSignedUrl(c, cmd, { expiresIn: 900 });
  return { key, uploadUrl: url, publicUrl: publicUrlFor(key) };
}

async function presignGet({ key }) {
  const c = getClient();
  if (!c) return null;
  const cmd = new GetObjectCommand({ Bucket: config.r2.bucket, Key: key });
  return getSignedUrl(c, cmd, { expiresIn: 900 });
}

async function remove(key) {
  const c = getClient();
  if (!c) return;
  await c.send(new DeleteObjectCommand({ Bucket: config.r2.bucket, Key: key }));
}

function isConfigured() {
  return !!(config.r2.endpoint && config.r2.accessKeyId);
}

module.exports = { putBuffer, presignPut, presignGet, remove, publicUrlFor, isConfigured };
