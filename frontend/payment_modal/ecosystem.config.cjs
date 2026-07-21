'use strict';

module.exports = {
  apps: [
    {
      name: 'mytaskking-payment',
      cwd: __dirname,
      script: './node_modules/vite/bin/vite.js',
      args: 'preview --port 4003 --host 0.0.0.0',
      env: {
        NODE_ENV: 'production',
      },
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_memory_restart: '256M',
    },
  ],
};
