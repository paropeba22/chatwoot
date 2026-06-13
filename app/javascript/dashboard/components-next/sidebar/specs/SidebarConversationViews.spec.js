import fs from 'node:fs';
import path from 'node:path';

const readSource = relativePath =>
  fs.readFileSync(path.resolve(process.cwd(), relativePath), 'utf8');

describe('conversation views navigation', () => {
  it('keeps only my conversations in the main sidebar', () => {
    const sidebarSource = readSource(
      'app/javascript/dashboard/components-next/sidebar/Sidebar.vue'
    );

    expect(sidebarSource).toContain("conversationViewRoute('me')");
    expect(sidebarSource).not.toContain("conversationViewRoute('unassigned')");
    expect(sidebarSource).not.toContain("conversationViewRoute('bot')");
  });

  it('shows queue and AI views in the chat list header tabs', () => {
    const chatListSource = readSource(
      'app/javascript/dashboard/components/ChatList.vue'
    );

    expect(chatListSource).toContain('import ChatTypeTabs from');
    expect(chatListSource).toContain('<ChatTypeTabs');
    expect(chatListSource).toContain("key: 'unassigned'");
    expect(chatListSource).toContain("key: 'bot'");
  });
});
