import type { Metadata } from 'next'
import { ColorWorldView } from '@/components/retro/ColorWorldView'

export const metadata: Metadata = {
  title: 'ColorWorld — paint the whole world | RetroBlox',
  description: 'Every map starts white with a black outline. Grab a brush, fill it with color, use your hints wisely — and upload your own GLB maps for the community.',
}

export default function ColorWorldPage() {
  return <ColorWorldView />
}
