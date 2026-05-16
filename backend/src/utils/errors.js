'use strict';

class HttpError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

const BadRequest = (message, details) => new HttpError(400, 'bad_request', message, details);
const Unauthorized = (message = 'Unauthorized') => new HttpError(401, 'unauthorized', message);
const Forbidden = (message = 'Forbidden') => new HttpError(403, 'forbidden', message);
const NotFound = (message = 'Not found') => new HttpError(404, 'not_found', message);
const Conflict = (message, details) => new HttpError(409, 'conflict', message, details);
const Gone = (message = 'Access expired') => new HttpError(410, 'gone', message);
const TooMany = (message = 'Too many requests') => new HttpError(429, 'too_many_requests', message);

module.exports = {
  HttpError,
  BadRequest,
  Unauthorized,
  Forbidden,
  NotFound,
  Conflict,
  Gone,
  TooMany,
};
