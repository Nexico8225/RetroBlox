import type { NextConfig } from "next";
import fs from "fs";

// Netlify's @netlify/plugin-nextjs runtime rejects a user-set
// `output: "standalone"` (it manages its own serverless bundling and the
// standalone .next layout breaks its onBuild packaging). Vercel likewise
// runs its own serverless builder and expects the default layout. Both
// platforms set their own env flag (NETLIFY=true / VERCEL=1), so only
// self-hosted / local runs get standalone.
const isServerlessPlatform =
  process.env.NETLIFY === "true" || process.env.VERCEL === "1";

const ZIP_HEADERS = [
  { key: "Content-Disposition", value: 'attachment; filename="retroblox-godot-player.zip"' },
  { key: "Cache-Control", value: "public, max-age=0, must-revalidate" },
];

const nextConfig: NextConfig = {
  output: isServerlessPlatform ? undefined : "standalone",
  // Ship the SQLite database (and its schema) inside EVERY serverless
  // function bundle — but only when a db file actually exists in the
  // working tree. The tracked copy was removed from git (a 16.8MB stale
  // user DB with password hashes has no place in a public repo); correct
  // cloud deployments (DATABASE_URL = libsql://) never read the bundled
  // file anyway, and with no file to trace fresh clones still build fine.
  outputFileTracingIncludes: {
    "/**": [
      ...(fs.existsSync("./db/custom.db") ? ["./db/custom.db"] : []),
      "./prisma/schema.prisma",
    ],
  },
  // Every "SDK" download IS the Godot player kit — always force a real
  // download (never navigate/open) and never let an edge cache serve a
  // stale kit after a redeploy.
  async headers() {
    return [
      {
        source: "/godot/retroblox-godot-player.zip",
        headers: ZIP_HEADERS,
      },
      {
        source: "/godot/retroblox-player-system.zip",
        headers: ZIP_HEADERS,
      },
      {
        source: "/sdk/retroblox-sdk.zip",
        headers: ZIP_HEADERS,
      },
    ];
  },
  /* config options here */
  typescript: {
    ignoreBuildErrors: true,
  },
  reactStrictMode: false,
};

export default nextConfig;
