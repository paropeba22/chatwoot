import { describe, expect, it } from 'vitest';
import { routes } from 'dashboard/routes/dashboard/technicalIncidents/routes';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

describe('technical incident routes', () => {
  it('protects every route with the feature flag and a permission', () => {
    routes.forEach(route => {
      expect(route.meta.featureFlag).toBe(FEATURE_FLAGS.TECHNICAL_INCIDENTS);
      expect(route.meta.permissions).toContain('administrator');
      expect(route.meta.permissions.length).toBeGreaterThan(1);
    });
  });

  it('requires create and update permissions for mutating screens', () => {
    expect(
      routes.find(route => route.name === 'technical_incidents_new').meta
        .permissions
    ).toContain('technical_incident_create');
    expect(
      routes.find(route => route.name === 'technical_incidents_edit').meta
        .permissions
    ).toContain('technical_incident_update');
  });
});
