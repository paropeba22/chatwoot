import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import CatalogMultiSelect from '../components/CatalogMultiSelect.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, fallback) => fallback || key }),
}));

const options = Array.from({ length: 8 }, (_, index) => ({
  value: `service_${index}`,
  label: `Service ${index}`,
  label_key: `service.${index}`,
}));

describe('CatalogMultiSelect', () => {
  it('supports searchable, keyboard-focusable options and emits canonical values', async () => {
    const wrapper = mount(CatalogMultiSelect, {
      props: {
        modelValue: [],
        options,
        label: 'Affected services',
        inputId: 'services',
      },
    });

    const search = wrapper.find('input[type="search"]');
    await search.setValue('Service 7');
    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(1);
    await wrapper.find('input[type="checkbox"]').trigger('change');
    expect(wrapper.emitted('update:modelValue')).toEqual([[['service_7']]]);
  });

  it('shows selected values as readable chips', () => {
    const wrapper = mount(CatalogMultiSelect, {
      props: {
        modelValue: ['service_1'],
        options,
        label: 'Affected services',
        inputId: 'services',
      },
    });

    expect(wrapper.text()).toContain('Service 1');
    expect(wrapper.text()).not.toContain('["service_1"]');
  });

  it('keeps unknown legacy values visible instead of silently dropping them', () => {
    const wrapper = mount(CatalogMultiSelect, {
      props: {
        modelValue: ['retired_service'],
        options,
        label: 'Affected services',
        inputId: 'services',
      },
    });

    expect(wrapper.text()).toContain('retired_service');
  });
});
