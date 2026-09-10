import { defineConfig } from 'vite'
import fs from 'node:fs'
import path from 'node:path'

function copyRootPublicFiles() {
  const files = ['manifest.json', 'sw.js', 'icon-192.svg', 'icon-512.svg']
  return {
    name: 'copy-root-public-files',
    closeBundle() {
      const outDir = path.resolve(process.cwd(), 'dist')
      for (const file of files) {
        const source = path.resolve(process.cwd(), file)
        const target = path.join(outDir, file)
        if (fs.existsSync(source)) fs.copyFileSync(source, target)
      }
    },
  }
}

export default defineConfig({
  plugins: [copyRootPublicFiles()],
  build: { outDir: 'dist', sourcemap: false },
})
