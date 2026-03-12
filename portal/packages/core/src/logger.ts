import pino from 'pino'

/**
 * Portal logger
 */
export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: {
    target: 'pino-pretty',
    options: {
      colorize: true,
      singleLine: false
    }
  }
})

export type Logger = typeof logger
