import { Page, Title } from '@/components/retro/Shell'
import { ChatListView } from '@/components/retro/ChatView'

export default function ChatPage() {
  return (
    <Page>
      <Title t="Chat" />
      <ChatListView />
    </Page>
  )
}
