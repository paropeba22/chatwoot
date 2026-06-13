import fs from 'node:fs';
import path from 'node:path';

const readSource = relativePath =>
  fs.readFileSync(path.resolve(process.cwd(), relativePath), 'utf8');

describe('conversation views navigation', () => {
  it('keeps queue and AI views in the main sidebar', () => {
    const sidebarSource = readSource(
      'app/javascript/dashboard/components-next/sidebar/Sidebar.vue'
    );

    expect(sidebarSource).toContain("conversationViewRoute('me')");
    expect(sidebarSource).toContain("conversationViewRoute('unassigned')");
    expect(sidebarSource).toContain("conversationViewRoute('bot')");
  });

  it('does not duplicate conversation views inside the chat list', () => {
    const chatListSource = readSource(
      'app/javascript/dashboard/components/ChatList.vue'
    );

    expect(chatListSource).not.toContain('import ChatTypeTabs from');
    expect(chatListSource).not.toContain('<ChatTypeTabs');
  });
});
