'use strict'

const https = require('https')

const FIGMA_API_HOST = 'api.figma.com'

function request (path, token) {
  return new Promise((resolve, reject) => {
    const req = https.request({
      host: FIGMA_API_HOST,
      path: path,
      method: 'GET',
      headers: {
        'X-Figma-Token': token
      }
    }, (res) => {
      let body = ''
      res.on('data', (chunk) => { body += chunk })
      res.on('end', () => {
        let data
        try {
          data = body ? JSON.parse(body) : {}
        } catch (e) {
          return reject(new Error(`Invalid JSON from Figma (status ${res.statusCode})`))
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          return reject(new Error(data.err || `Figma API error (status ${res.statusCode})`))
        }
        resolve(data)
      })
    })
    req.on('error', reject)
    req.end()
  })
}

function client (token) {
  token = token || process.env.FIGMA_TOKEN
  if (!token) {
    throw new Error('FIGMA_TOKEN is required')
  }
  return {
    getFile: (fileKey) => request(`/v1/files/${encodeURIComponent(fileKey)}`, token),
    getComments: (fileKey) => request(`/v1/files/${encodeURIComponent(fileKey)}/comments`, token),
    getMe: () => request('/v1/me', token)
  }
}

module.exports = client
