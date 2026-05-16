'use strict';

const logger = require('../utils/logger');
const { HttpError } = require('../utils/errors');

function notFound(req, res, next) {
  res.status(404).json({ error: { code: 'not_found', message: `Route ${req.method} ${req.path} not found` } });
}

function errorHandler(err, req, res, _next) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({
      error: { code: err.code, message: err.message, details: err.details },
    });
  }

  if (err && err.name === 'ValidationError') {
    return res.status(400).json({ error: { code: 'validation_error', message: err.message, details: err.details } });
  }

  if (err && err.code === 'P2002') {
    return res.status(409).json({ error: { code: 'duplicate', message: 'Duplicate value', details: err.meta } });
  }

  logger.error({ err, path: req.path }, 'unhandled.error');
  return res.status(500).json({ error: { code: 'internal_error', message: 'Internal server error' } });
}

module.exports = { notFound, errorHandler };
