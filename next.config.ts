import type { NextConfig } from 'next';
import withPWAInit from '@ducanh2912/next-pwa';
const withPWA = withPWAInit({ dest: 'public', disable: process.env.NODE_ENV === 'development', cacheOnFrontEndNav: false, aggressiveFrontEndNavCaching: false, workboxOptions: { importScripts: ['/push-worker.js'], runtimeCaching: [{ urlPattern: /\/api\//, handler: 'NetworkOnly' }, { urlPattern: ({ request }) => request.mode === 'navigate', handler: 'NetworkFirst', options: { cacheName: 'fintrack-pages', networkTimeoutSeconds: 5 } }] } });
const nextConfig: NextConfig = { turbopack: {} };
export default withPWA(nextConfig);
