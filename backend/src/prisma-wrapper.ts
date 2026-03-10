declare global {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  var __prisma: any;
}

function makeNoopProxy() {
  const handler: ProxyHandler<any> = {
    get() {
      return (..._args: any[]) => Promise.resolve(null);
    },
    apply() {
      return Promise.resolve(null);
    },
  };
  return new Proxy(function () {}, handler) as any;
}

export function getPrisma() {
  if (process.env.DATABASE_TYPE === 'firestore') {
    return makeNoopProxy();
  }

  try {
    if ((global as any).__prisma) return (global as any).__prisma;
    // lazy-require to avoid build-time dependency on generated client
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { PrismaClient } = require('@prisma/client');
    (global as any).__prisma = new PrismaClient();
    return (global as any).__prisma;
  } catch (err) {
    // If prisma client isn't generated, return a proxy that rejects calls
    // with a clear message so startup doesn't crash unexpectedly.
    // eslint-disable-next-line no-console
    console.error('Prisma client unavailable:', err && err.message ? err.message : err);
    const handler: ProxyHandler<any> = {
      get() {
        return () => Promise.reject(new Error('Prisma client not initialized'));
      },
    };
    return new Proxy({}, handler) as any;
  }
}

export default getPrisma;
