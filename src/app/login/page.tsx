'use client'

import { Suspense, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useSearchParams } from 'next/navigation'
import { useRetro } from '@/lib/store'
import { BootScreen, Title } from '@/components/retro/Shell'
import { SignInView } from '@/components/retro/AuthPages'

export default function LoginPage() {
  return (
    <Suspense fallback={<BootScreen />}>
      <LoginInner />
    </Suspense>
  )
}

function LoginInner() {
  const { booted, user } = useRetro()
  const router = useRouter()
  const params = useSearchParams()
  const next = params.get('next') || undefined

  useEffect(() => {
    document.title = 'Login - RetroBlox'
  }, [])

  useEffect(() => {
    if (booted && user) {
      router.replace(next && next.startsWith('/') ? next : '/')
    }
  }, [booted, user, router, next])

  if (!booted) return <BootScreen />
  if (user) return null
  return (
    <>
      <Title t="Login" />
      <SignInView next={next} />
    </>
  )
}
