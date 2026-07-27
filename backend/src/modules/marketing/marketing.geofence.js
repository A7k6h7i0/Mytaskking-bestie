'use strict';

const { BadRequest } = require('../../utils/errors');
const { distanceMeters } = require('../../utils/geo');
const { getFieldSettings } = require('./marketing.settings');
const { isManager } = require('./marketing.helpers');

async function assertVisitGeofence(req, outlet, latitude, longitude, managerOverride = false) {
  const settings = await getFieldSettings(req);
  if (settings.geofenceEnabled === false) return;

  if (latitude == null || longitude == null) {
    throw BadRequest('latitude and longitude required for visit check-in');
  }

  const outletLat =
    outlet.latitude != null && outlet.latitude !== '' ? Number(outlet.latitude) : null;
  const outletLng =
    outlet.longitude != null && outlet.longitude !== '' ? Number(outlet.longitude) : null;

  if (outletLat == null || outletLng == null || Number.isNaN(outletLat) || Number.isNaN(outletLng)) {
    throw BadRequest('Outlet has no GPS location on file — ask your manager to set it.');
  }

  if (managerOverride && isManager(req.user)) return;

  const checkLat = Number(latitude);
  const checkLng = Number(longitude);
  if (Number.isNaN(checkLat) || Number.isNaN(checkLng)) {
    throw BadRequest('Invalid check-in coordinates');
  }

  const dist = distanceMeters(outletLat, outletLng, checkLat, checkLng);
  const threshold = Number(settings.geofenceThresholdMeters) || 100;

  if (dist > threshold) {
    throw BadRequest(
      `Geofence: you are ${Math.round(dist)}m from the outlet (max ${threshold}m). Move closer to check in.`,
      {
        distanceMeters: Math.round(dist),
        thresholdMeters: threshold,
        requiresOverride: isManager(req.user),
      }
    );
  }
}

module.exports = { assertVisitGeofence };
