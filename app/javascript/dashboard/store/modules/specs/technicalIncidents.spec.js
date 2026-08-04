import { beforeEach, describe, expect, it, vi } from 'vitest';
import { actions, mutations } from 'dashboard/store/modules/technicalIncidents';
import TechnicalIncidentsAPI from 'dashboard/api/technicalIncidents';

vi.mock('dashboard/api/technicalIncidents', () => ({
  default: {
    list: vi.fn(),
    show: vi.fn(),
    options: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    transition: vi.fn(),
    delete: vi.fn(),
  },
}));

describe('technicalIncidents store', () => {
  const commit = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('wraps create payloads in the account API contract', async () => {
    TechnicalIncidentsAPI.create.mockResolvedValue({
      data: { id: 1, title: 'Incident' },
    });

    const result = await actions.create(
      { commit },
      { title: 'Incident', customer_message: '<script>alert(1)</script>' }
    );

    expect(TechnicalIncidentsAPI.create).toHaveBeenCalledWith({
      technical_incident: {
        title: 'Incident',
        customer_message: '<script>alert(1)</script>',
      },
    });
    expect(commit).toHaveBeenCalledWith('SET_CURRENT', result);
    expect(commit).toHaveBeenLastCalledWith('SET_UI_FLAG', { saving: false });
  });

  it('passes lifecycle attributes without mutating the status contract', async () => {
    TechnicalIncidentsAPI.transition.mockResolvedValue({
      data: { id: 1, status: 'active' },
    });

    await actions.transition(
      { commit },
      {
        id: 1,
        status: 'active',
        attributes: { expires_at: '2026-07-17T20:00:00Z' },
      }
    );

    expect(TechnicalIncidentsAPI.transition).toHaveBeenCalledWith(1, {
      status: 'active',
      expires_at: '2026-07-17T20:00:00Z',
    });
  });

  it('updates flags without discarding unrelated loading state', () => {
    const state = {
      uiFlags: { fetching: true, saving: false, transitioning: false },
    };

    mutations.SET_UI_FLAG(state, { saving: true });

    expect(state.uiFlags).toEqual({
      fetching: true,
      saving: true,
      transitioning: false,
    });
  });

  it('exposes loading and a sanitized error instead of converting metadata failures into empty success', async () => {
    TechnicalIncidentsAPI.options.mockRejectedValue({
      response: { status: 403, data: { secret: 'must-not-be-exposed' } },
    });

    await expect(actions.fetchOptions({ commit })).rejects.toBeTruthy();

    expect(commit).toHaveBeenCalledWith('SET_UI_FLAG', {
      fetchingOptions: true,
      optionsError: null,
    });
    expect(commit).toHaveBeenCalledWith('SET_UI_FLAG', { optionsError: 403 });
    expect(commit).not.toHaveBeenCalledWith('SET_OPTIONS', []);
    expect(commit).toHaveBeenLastCalledWith('SET_UI_FLAG', {
      fetchingOptions: false,
    });
  });

  it('commits only the latest metadata response when requests finish out of order', async () => {
    let resolveFirst;
    TechnicalIncidentsAPI.options
      .mockReturnValueOnce(
        new Promise(resolve => {
          resolveFirst = resolve;
        })
      )
      .mockResolvedValueOnce({ data: { metadata_version: 2 } });

    const first = actions.fetchOptions({ commit });
    const second = actions.fetchOptions({ commit });
    await second;
    resolveFirst({ data: { metadata_version: 1 } });
    await first;

    expect(commit).toHaveBeenCalledWith('SET_OPTIONS', { metadata_version: 2 });
    expect(commit).not.toHaveBeenCalledWith('SET_OPTIONS', {
      metadata_version: 1,
    });
  });
});
