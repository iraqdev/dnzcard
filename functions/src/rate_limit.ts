import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";

const db = admin.firestore();

/** حد معدّل الطلبات البسيط (Firestore) — يمنع إساءة الاستخدام دون Redis. */
export async function assertRateLimit(
  key: string,
  maxAttempts: number,
  windowMs: number,
): Promise<void> {
  const safeKey = key.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 120);
  const ref = db.collection("_rate_limits").doc(safeKey);
  const now = Date.now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? {count: 0, windowStart: now};
    let count = Number(data.count) || 0;
    let windowStart = Number(data.windowStart) || now;

    if (now - windowStart > windowMs) {
      count = 0;
      windowStart = now;
    }

    count += 1;
    if (count > maxAttempts) {
      throw new HttpsError(
        "resource-exhausted",
        "محاولات كثيرة. حاول لاحقاً",
      );
    }

    tx.set(ref, {count, windowStart, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  });
}

export function clientRateKey(prefix: string, request: {auth?: {uid?: string}; rawRequest?: {ip?: string}}, extra = ""): string {
  const uid = request.auth?.uid ?? "anon";
  const ip = request.rawRequest?.ip ?? "unknown";
  return `${prefix}:${uid}:${ip}:${extra}`.slice(0, 120);
}
