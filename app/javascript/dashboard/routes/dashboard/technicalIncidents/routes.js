import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.TECHNICAL_INCIDENTS,
  permissions: ['administrator', 'technical_incident_view'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/technical-incidents'),
    name: 'technical_incidents_index',
    component: () => import('./pages/Index.vue'),
    meta: commonMeta,
  },
  {
    path: frontendURL('accounts/:accountId/technical-incidents/new'),
    name: 'technical_incidents_new',
    component: () => import('./pages/Form.vue'),
    meta: {
      ...commonMeta,
      permissions: ['administrator', 'technical_incident_create'],
    },
  },
  {
    path: frontendURL(
      'accounts/:accountId/technical-incidents/:incidentId/edit'
    ),
    name: 'technical_incidents_edit',
    component: () => import('./pages/Form.vue'),
    meta: {
      ...commonMeta,
      permissions: ['administrator', 'technical_incident_update'],
    },
  },
  {
    path: frontendURL('accounts/:accountId/technical-incidents/:incidentId'),
    name: 'technical_incidents_show',
    component: () => import('./pages/Show.vue'),
    meta: commonMeta,
  },
];
