'use strict';

const { BadRequest } = require('../utils/errors');

const validate = (schemas) => (req, _res, next) => {
  try {
    for (const key of ['body', 'query', 'params']) {
      if (schemas[key]) {
        const { error, value } = schemas[key].validate(req[key], { abortEarly: false, stripUnknown: true });
        if (error) {
          return next(BadRequest('Validation failed', error.details.map((d) => d.message)));
        }
        req[key] = value;
      }
    }
    next();
  } catch (e) {
    next(e);
  }
};

module.exports = validate;
