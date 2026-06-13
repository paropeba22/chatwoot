import fs from 'node:fs';
import path from 'node:path';

describe('SidebarAccountSwitcher', () => {
  it('does not expose an email used as the account name', () => {
    const source = fs.readFileSync(
      path.resolve(
        process.cwd(),
        'app/javascript/dashboard/components-next/sidebar/SidebarAccountSwitcher.vue'
      ),
      'utf8'
    );

    expect(source).toContain("!name.includes('@')");
    expect(source).toContain("name : 'Grupo Telecom'");
    expect(source).not.toContain('{{ currentAccount.name }}');
    expect(source).not.toContain('{{ account.name }}');
    expect(source).not.toContain(':title="currentAccount.name"');
    expect(source).not.toContain(':title="account.name"');
    expect(source).toContain('/brand-assets/logo_thumbnail.png');
    expect(source).not.toContain("import Logo from 'next/icon/Logo.vue'");
  });
});
