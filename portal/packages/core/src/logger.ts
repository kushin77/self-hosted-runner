import pino from 'pino'

/**
 * Portal logger
 */
const transport = process.env.NODE_ENV === 'production' || process.env.SKIP_PRETTY_LOG === 'true'
  ? undefined
  : {
      target: 'pino-pretty',
      options: {
        colorize: true,
        singleLine: false
      }
    }

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  ...(transport && { transport })
})

export type Logger = typeof logger
