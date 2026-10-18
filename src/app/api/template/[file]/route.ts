import { NextRequest, NextResponse } from 'next/server'
import { readFile } from 'fs/promises'
import path from 'path'

// v7: serve the downloadable game templates with a real attachment header —
// the /download starter page points its iframe here, so the browser starts
// the download and never "navigates" to a raw file page.
// .retroplace = the game file for the RetroBlox studio player;
// .zip = a whole Godot 4.5 project (open in Godot, edit, run).
const ALLOWED = /^[a-z0-9-]+\.(retroplace|zip)$/i

export async function GET(req: NextRequest, { params }: { params: Promise<{ file: string }> }) {
  const { file } = await params
  if (!ALLOWED.test(file)) {
    return NextResponse.json({ error: 'Not a template file' }, { status: 400 })
  }
  try {
    const buf = await readFile(path.join(process.cwd(), 'public', 'templates', file))
    return new NextResponse(new Uint8Array(buf), {
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Length': String(buf.length),
        'Content-Disposition': `attachment; filename="${file}"`,
        'Cache-Control': 'public, max-age=300',
      },
    })
  } catch {
    return NextResponse.json({ error: 'Template not found' }, { status: 404 })
  }
}
