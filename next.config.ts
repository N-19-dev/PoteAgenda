import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // node-ical (via temporal-polyfill/rrule-temporal) breaks under Turbopack's
  // bundling of Route Handlers ("e.BigInt is not a function") — run it as a
  // native Node require instead.
  serverExternalPackages: ["node-ical"],
};

export default nextConfig;
