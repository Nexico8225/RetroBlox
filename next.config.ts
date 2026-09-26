import type { NextConfig } from "next";

// Netlify's @netlify/plugin-nextjs runtime rejects a user-set
// `output: "standalone"` (it manages its own serverless bundling and the
// standalone .next layout breaks its onBuild packaging). Vercel likewise
// runs its own serverless builder and expects the default layout. Both
// platforms set their own env flag (NETLIFY=true / VERCEL=1), so only
// self-hosted / local runs get standalone.
const isServerlessPlatform =
  process.env.NETLIFY === "true" || process.env.VERCEL === "1";

const nextConfig: NextConfig = {
  output: isServerlessPlatform ? undefined : "standalone",
  // Ship the SQLite database (and its schema) inside EVERY serverless
  // function bundle. Without this, Netlify/Vercel lambdas have no
  // db/custom.db at runtime and every account lookup 500s.
  outputFileTracingIncludes: {
    "/**": ["./db/custom.db", "./prisma/schema.prisma"],
  },
  /* config options here */
  typescript: {
    ignoreBuildErrors: true,
  },
  reactStrictMode: false,
};

export default nextConfig;
