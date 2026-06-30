'use strict';

const { Router } = require('express');

// Tier-1 modules — the core platform from the first build.
const auth = require('./auth/auth.routes');
const employees = require('./employees/employees.routes');
const clients = require('./clients/clients.routes');
const channels = require('./channels/channels.routes');
const chat = require('./chat/chat.routes');
const tasks = require('./tasks/tasks.routes');
const reports = require('./reports/reports.routes');
const calls = require('./calls/calls.routes');
const telecaller = require('./telecaller/telecaller.routes');
const notifications = require('./notifications/notifications.routes');
const dashboard = require('./dashboard/dashboard.routes');
const files = require('./files/files.routes');

// Tier-2 modules — audit, search, saved, settings, calendar, announcements.
const audit = require('./audit/audit.routes');
const search = require('./search/search.routes');
const saved = require('./saved/saved.routes');
const settings = require('./settings/settings.routes');
const calendar = require('./calendar/calendar.routes');
const attendance = require('./attendance/attendance.routes');
const announcements = require('./announcements/announcements.routes');

// Tier-3 modules — sessions, advanced RBAC, presence, analytics, automations, openapi.
const sessions = require('./sessions/sessions.routes');
const permissions = require('./permissions/permissions.routes');
const presence = require('./presence/presence.routes');
const analytics = require('./analytics/analytics.routes');
const automations = require('./automations/automations.routes');
const openapi = require('./openapi/openapi.routes');

// Tier-4 modules — flags, meetings, workspace customization.
const flags = require('./flags/flags.routes');
const meetings = require('./meetings/meetings.routes');
const workspace = require('./workspace/workspace.routes');
const unfurl = require('./unfurl/unfurl.routes');
const recordings = require('./recordings/recordings.routes');
const tenants = require('./tenants/tenants.routes');
const emergency = require('./emergency/emergency.routes');
const workActivity = require('./workActivity/workActivity.routes');

module.exports = function buildRouter() {
  const router = Router();

  router.use('/auth', auth);
  router.use('/employees', employees);
  router.use('/clients', clients);
  router.use('/channels', channels);
  router.use('/chat', chat);
  router.use('/tasks', tasks);
  router.use('/reports', reports);
  router.use('/calls', calls);
  router.use('/telecaller', telecaller);
  router.use('/notifications', notifications);
  router.use('/dashboard', dashboard);
  router.use('/files', files);

  router.use('/audit', audit);
  router.use('/search', search);
  router.use('/saved', saved);
  router.use('/settings', settings);
  router.use('/calendar', calendar);
  router.use('/attendance', attendance);
  router.use('/announcements', announcements);

  router.use('/sessions', sessions);
  router.use('/permissions', permissions);
  router.use('/presence', presence);
  router.use('/analytics', analytics);
  router.use('/automations', automations);

  router.use('/flags', flags);
  router.use('/meetings', meetings);
  router.use('/workspace', workspace);
  router.use('/unfurl', unfurl);
  router.use('/recordings', recordings);
  router.use('/tenants', tenants);
  router.use('/emergency', emergency);
  router.use('/work-activity', workActivity);

  // openapi serves /openapi.json + /docs at the root of /api/v1
  router.use('/', openapi);

  return router;
};
