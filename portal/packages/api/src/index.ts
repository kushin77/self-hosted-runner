import { createApp } from './app'
import { logger } from '@nexus/core'

/**
 * Start the API server
 */
async function start(): Promise<void> {
  try {
    const app = createApp()
    const port = parseInt(process.env.PORT || '5000', 10)
    const host = process.env.HOST || 'localhost'

    app.listen(port, host, () => {
      logger.info(`🚀 Portal API running at http://${host}:${port}`)
      logger.info(`📊 Health check: http://${host}:${port}/health`)
      logger.info(`📦 API docs: http://${host}:${port}/api/version`)
    })
  } catch (error) {
    logger.error({ error }, 'Failed to start API')
    process.exit(1)
  }
}

start()
