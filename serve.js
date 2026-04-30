'use strict'

// Minimal zero-dependency static file server for the prototype in ./public
// Run with: `node serve.js` or `npm start`

const http = require('http')
const fs = require('fs')
const path = require('path')

const PORT = process.env.PORT || 5173
const ROOT = path.join(__dirname, 'public')

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js':   'application/javascript; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg':  'image/svg+xml',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif':  'image/gif',
  '.webp': 'image/webp',
  '.ico':  'image/x-icon',
  '.woff': 'font/woff',
  '.woff2':'font/woff2'
}

function send (res, status, body, headers) {
  res.writeHead(status, Object.assign({ 'Cache-Control': 'no-store' }, headers || {}))
  res.end(body)
}

const server = http.createServer((req, res) => {
  // Strip query string, decode, normalise.
  let urlPath = decodeURIComponent(req.url.split('?')[0])
  if (urlPath === '/') urlPath = '/index.html'

  // Resolve and prevent path traversal outside ROOT.
  const filePath = path.normalize(path.join(ROOT, urlPath))
  if (!filePath.startsWith(ROOT)) return send(res, 403, 'Forbidden')

  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) return send(res, 404, 'Not found')
    const ext = path.extname(filePath).toLowerCase()
    const type = TYPES[ext] || 'application/octet-stream'
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' })
    fs.createReadStream(filePath).pipe(res)
  })
})

server.listen(PORT, () => {
  console.log(`Frosted-glass prototype running at http://localhost:${PORT}`)
})
