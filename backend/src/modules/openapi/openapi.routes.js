'use strict';

const { Router } = require('express');
const fs = require('fs');
const path = require('path');

const router = Router();

/**
 * Serves the hand-curated OpenAPI 3.1 spec from disk plus a tiny embedded
 * Swagger UI page so consumers don't need any extra tooling. We deliberately
 * curate the spec rather than auto-generating from routes — keeps responses
 * accurate for a hand-written API and avoids a heavy generation dependency.
 */

const SPEC_PATH = path.join(__dirname, 'openapi.json');

router.get('/openapi.json', (_req, res) => {
  if (!fs.existsSync(SPEC_PATH)) {
    return res.status(404).json({ error: { code: 'not_found', message: 'spec not built' } });
  }
  res.setHeader('Content-Type', 'application/json');
  fs.createReadStream(SPEC_PATH).pipe(res);
});

router.get('/docs', (_req, res) => {
  res.setHeader('Content-Type', 'text/html');
  res.send(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <title>MyTaskKing API · Reference</title>
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
  </head>
  <body>
    <div id="swagger" style="margin:0"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script>
      window.ui = SwaggerUIBundle({
        url: '/api/v1/openapi.json',
        dom_id: '#swagger',
        deepLinking: true,
        layout: 'BaseLayout',
      });
    </script>
  </body>
</html>`);
});

module.exports = router;
