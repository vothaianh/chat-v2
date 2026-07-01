/**
 * Push service interface. Implementations deliver push notifications to devices
 * (FCM for Android/iOS/web). The default wiring uses Firebase Admin; when no
 * credentials are configured, the implementation logs instead of sending.
 */
export interface PushPayload {
  title: string;
  body: string;
  /** Arbitrary data for the client (e.g. conversationId, message type, sender). */
  data?: Record<string, string>;
}

export interface PushService {
  send(tokens: string[], payload: PushPayload): Promise<void>;
}

export const PUSH_SERVICE = Symbol('PUSH_SERVICE');