'use strict';

const asyncHandler = require('../../utils/asyncHandler');
const billing = require('../../services/billing.service');

module.exports = asyncHandler(async (req, res) => {
  const signature = req.headers['x-razorpay-signature'];
  const result = await billing.handleRazorpayWebhook(req.body, signature);
  res.status(200).json(result);
});
