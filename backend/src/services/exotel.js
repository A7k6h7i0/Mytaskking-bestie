'use strict';

const axios = require('axios');
const config = require('../config');

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
    throw new Error('Exotel is not configured');
  }
  const params = new URLSearchParams();
  params.append('From', from);
  params.append('To', to);
  params.append('CallerId', callerId || config.exotel.virtualNumber);
  if (statusCallback) params.append('StatusCallback', statusCallback);
  params.append('Record', 'true');

  const { data } = await client.post('/Calls/connect.json', params);
  if (data?.RestException) {
    const message = data.RestException.Message || data.RestException.message || 'Exotel rejected the call request';
    throw new Error(message);
  }
  const call = data.Call || data;
  const sid = call.Sid || call.sid;
  if (!sid) {
    throw new Error('Exotel did not return a call SID');
  }
  return call;
}

module.exports = { connectCall };
