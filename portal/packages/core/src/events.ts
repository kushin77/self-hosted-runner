import { EventEmitter } from 'events'
import { v4 as uuidv4 } from 'uuid'
import type { IEvent, IEventListener } from './types'

/**
 * Global event system for Portal
 */
export class EventBus extends EventEmitter {
  private static instance: EventBus

  private constructor() {
    super()
    this.setMaxListeners(100)
  }

  static getInstance(): EventBus {
    if (!EventBus.instance) {
      EventBus.instance = new EventBus()
    }
    return EventBus.instance
  }

  emit(event: IEvent): boolean {
    return super.emit(event.type, event)
  }

  on(eventType: string, listener: IEventListener): this {
    return super.on(eventType, listener)
  }

  once(eventType: string, listener: IEventListener): this {
    return super.once(eventType, listener)
  }

  off(eventType: string, listener: IEventListener): this {
    return super.off(eventType, listener)
  }
}

/**
 * Event emitter helper
 */
export function createEvent(type: string, source: string, data: Record<string, unknown>): IEvent {
  return {
    id: uuidv4(),
    type,
    source,
    timestamp: new Date(),
    data,
  }
}

export function emitEvent(event: IEvent): void {
  EventBus.getInstance().emit(event)
}

export function onEvent(eventType: string, listener: IEventListener): void {
  EventBus.getInstance().on(eventType, listener)
}
