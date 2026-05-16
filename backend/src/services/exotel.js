'use strict';

const axios = require('axios');
const config = require('../config');
const logger = require('../utils/logger');

function exotelClient() {
  if (!config.exotel.sid || !config.exotel.apiKey || !config.exotel.apiToken) {
    return null;
  }
  return axios.create({
    baseURL: `https://${config.exotel.apiKey}:${config.exotel.apiToken}@api.exotel.com/v1/Accounts/${config.exotel.sid}`,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    timeout: 10_000,
  });
}

async function connectCall({ from, to, callerId, statusCallback }) {
  const client = exotelClient();
  if (!client) {
    logger.warn('exotel.disabled — returning mock call');
    return { Sid: `mock_${Date.now()}`, Status: 'queued', mock: true };
  }
  const params = new URLSearchParams();
  params.append('From', from);
  params.append('To', to);
  params.append('CallerId', callerId || config.exotel.virtualNumber);
  if (statusCallback) params.append('StatusCallback', statusCallback);
  params.append('Record', 'true');

  const { data } = await client.post('/Calls/connect.json', params);
  return data.Call || data;
}

module.exports = { connectCall };
