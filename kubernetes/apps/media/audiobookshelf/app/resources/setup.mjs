// Idempotent first-run setup: root user from 1Password, then the Audiobooks library.
const base = process.env.ABS_URL
const username = process.env.ABS_ROOT_USERNAME
const password = process.env.ABS_ROOT_PASSWORD
const libraryPath = process.env.ABS_LIBRARY_PATH

if (!username || !password) throw new Error('ABS_ROOT_USERNAME / ABS_ROOT_PASSWORD not set')

async function call(path, { method = 'GET', token, body } = {}) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token && { Authorization: `Bearer ${token}` })
    },
    body: body && JSON.stringify(body)
  })
  if (!res.ok) throw new Error(`${method} ${path}: HTTP ${res.status}`)
  const type = res.headers.get('content-type') || ''
  return type.includes('json') ? res.json() : res.text()
}

let status
for (let i = 0; ; i++) {
  try {
    status = await call('/status')
    break
  } catch (err) {
    if (i >= 60) throw err
    await new Promise((r) => setTimeout(r, 5000))
  }
}

if (status.isInit) {
  console.log('root user exists, skipping init')
} else {
  await call('/init', { method: 'POST', body: { newRoot: { username, password } } })
  console.log(`created root user ${username}`)
}

const { user } = await call('/login', { method: 'POST', body: { username, password } })
const token = user.accessToken

const { libraries } = await call('/api/libraries', { token })
if (libraries.some((lib) => lib.folders.some((f) => f.fullPath === libraryPath))) {
  console.log(`library for ${libraryPath} exists, skipping`)
} else {
  await call('/api/libraries', {
    method: 'POST',
    token,
    body: {
      name: 'Audiobooks',
      folders: [{ fullPath: libraryPath }],
      mediaType: 'book',
      provider: 'audible',
      // Listenarr writes over NFS from another pod; inotify never sees it, so scan on a schedule
      settings: { autoScanCronExpression: '*/30 * * * *', disableWatcher: true }
    }
  })
  console.log(`created library Audiobooks at ${libraryPath}`)
}
