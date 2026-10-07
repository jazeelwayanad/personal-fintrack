import { createRequire } from 'node:module';
import { cp, mkdir } from 'node:fs/promises';
import path from 'node:path';

const fromTsx = createRequire(import.meta.resolve('tsx'));
const esbuild = fromTsx('esbuild');
const destination = path.resolve('build/fintrack-preview');
await mkdir(destination, { recursive: true });
await Promise.all(['index.html', 'style.css', 'assets'].map(file => cp(path.resolve('design-preview', file), path.join(destination, file), { recursive: true })));
await esbuild.build({ entryPoints: ['design-preview/main.tsx'], bundle: true, outfile: path.join(destination, 'preview.js'), platform: 'browser', target: 'es2020', jsx: 'automatic', minify: true, define: { 'process.env.NODE_ENV': '"production"' } });
console.log(`Preview built at ${destination}`);
