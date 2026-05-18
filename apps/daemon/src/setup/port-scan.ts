import { createServer } from 'node:net';

const DEFAULT_PORT = 7456;
const MAX_SCAN = 100;

export async function findAvailablePort(preferred: number = DEFAULT_PORT): Promise<number> {
  if (await isPortAvailable(preferred)) return preferred;
  for (let p = preferred + 1; p <= preferred + MAX_SCAN; p++) {
    if (await isPortAvailable(p)) return p;
  }
  return preferred;
}

function isPortAvailable(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = createServer();
    server.unref();
    server.on('error', () => resolve(false));
    server.listen(port, '127.0.0.1', () => {
      server.close(() => resolve(true));
    });
  });
}
