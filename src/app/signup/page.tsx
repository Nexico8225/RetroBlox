'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useRetro } from '@/lib/store'
import { BootScreen, Title } from '@/components/retro/Shell'
import { SignUpView } from '@/components/retro/AuthPages'

export default function SignUpPage() {
  const { booted, user } = useRetro()
  const router = useRouter()

  useEffect(() => {
    document.title = 'Sign Up - RetroBlox'
  }, [])

  useEffect(() => {
    if (booted && user) {
      router.replace('/')
    }
  }, [booted, user, router])

  if (!booted) return <BootScreen />
  if (user) return null
  return (
    <>
      <Title t="Sign Up" />
      <SignUpView />
    </>
  )
}
