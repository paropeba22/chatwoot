import types from '../../../mutation-types';
import { mutations } from '../../conversationStats';

describe('#mutations', () => {
  describe('#SET_CONV_TAB_META', () => {
    it('set conversation stats correctly', () => {
      const state = {};
      mutations[types.SET_CONV_TAB_META](state, {
        mine_count: 1,
        unassigned_count: 1,
        all_count: 2,
      });
      expect(state).toEqual({
        mineCount: 1,
        unAssignedCount: 1,
        allCount: 2,
        updatedOn: expect.any(Date),
      });
    });

    it('preserves previous counts when payload is partial', () => {
      const state = {
        mineCount: 10,
        unAssignedCount: 85,
        allCount: 200,
      };

      mutations[types.SET_CONV_TAB_META](state, {
        all_count: 201,
      });

      expect(state).toEqual({
        mineCount: 10,
        unAssignedCount: 85,
        allCount: 201,
        updatedOn: expect.any(Date),
      });
    });
  });
});
