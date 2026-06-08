import fs from 'node:fs';
import path from 'node:path';

describe('SidebarProfileMenu privacy', () => {
  it('does not render or use the operator email as a visual fallback', () => {
    const source = fs.readFileSync(
      path.resolve(
        process.cwd(),
        'app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue'
      ),
      'utf8'
    );

    expect(source).not.toContain('currentUser.value?.email');
    expect(source).not.toContain('{{ currentUser.email }}');
    expect(source).toContain("t('SIDEBAR_ITEMS.OPERATOR')");
  });
});
