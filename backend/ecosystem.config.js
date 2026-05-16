module.exports = {
  apps: [
    {
      name: 'bestie-api',
      script: 'src/app.js',
      instances: 'max',
      exec_mode: 'cluster',
      max_memory_restart: '512M',
      env: { NODE_ENV: 'production' },
      out_file: './logs/api.out.log',
      error_file: './logs/api.err.log',
      time: true,
    },
    {
      // Run as a separate process so a hot media job doesn't slow the API.
      // When `QUEUE_DRIVER=bullmq` the worker drains Redis-backed queues;
      // otherwise it runs the in-memory queue handlers for this process only
      // (and the API also registers its own handlers — fine for dev, weird
      // for prod, so keep them as distinct processes).
      name: 'bestie-worker',
      script: 'src/worker.js',
      instances: 1,
      exec_mode: 'fork',
      max_memory_restart: '512M',
      env: { NODE_ENV: 'production', QUEUE_DRIVER: 'bullmq' },
      out_file: './logs/worker.out.log',
      error_file: './logs/worker.err.log',
      time: true,
    },
  ],
};
