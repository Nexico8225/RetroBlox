import { Page } from '@/components/retro/Shell'
import { ChatThreadView } from '@/components/retro/ChatView'

export default async function ChatThreadPage({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params
  return (
    <Page>
      <ChatThreadView userId={userId} />
    </Page>
  )
}
