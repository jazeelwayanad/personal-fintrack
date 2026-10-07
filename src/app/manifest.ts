import type { MetadataRoute } from 'next'

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'FinTrack',
    short_name: 'FinTrack',
    description: 'Plan income, bills, budgets, and spending with FinTrack',
    start_url: '/',
    display: 'standalone',
    background_color: '#dcefe7',
    theme_color: '#dcefe7',
    orientation: 'portrait',
    icons: [
      {
        src: '/icons/icon-192.png',
        sizes: '192x192',
        type: 'image/png',
        purpose: 'any'
      },
      {
        src: '/icons/icon-512.png',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'any'
      },
    ],
  }
}
