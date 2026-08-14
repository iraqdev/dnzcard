import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";
import {createHash} from "crypto";

/**
 * التحقق من رمز الشراء (PIN) على الخادم مع قفل بعد محاولات خاطئة.
 *
 * - إذا كانت الحماية غير مفعّلة للمستخدم: يمر دون تحقق.
 * - إذا أُرسل الرمز: يُتحقق منه بصرامة، ويُقفل مؤقتاً بعد عدة محاولات خاطئة.
 * - إذا لم يُرسل الرمز (نسخ التطبيق القديمة): يُسمح مؤقتاً حتى لا تنكسر النسخ
 *   الحالية. بعد انتشار التحديث الإجباري فعّل REQUIRE_PIN_WHEN_ENABLED = true
 *   ليصبح الرمز إلزامياً على الخادم لكل من فعّل الحماية.
 *
 * ⚠️ لا تُحوّل REQUIRE_PIN_WHEN_ENABLED إلى true قبل انتشار التحديث، لأن النسخ
 *    القديمة لا ترسل الرمز وستُرفض مشترياتها.
 */
const REQUIRE_PIN_WHEN_ENABLED = false;

/** أقصى عدد محاولات خاطئة متتالية قبل القفل المؤقت. */
const MAX_PIN_FAILS = 5;
/** مدة القفل المؤقت بعد تجاوز المحاولات (بالملّي ثانية). */
const PIN_LOCK_MS = 5 * 60 * 1000;

export async function verifyPurchasePin(
  db: admin.firestore.Firestore,
  uid: string,
  pin: string | undefined
): Promise<void> {
  const userSnap = await db.collection("users").doc(uid).get();
  const data = userSnap.data() || {};
  if (data.purchasePinEnabled !== true) return;

  const hash = String(data.purchasePinHash || "");
  const clean = (pin ?? "").trim();

  if (!clean) {
    if (REQUIRE_PIN_WHEN_ENABLED) {
      throw new HttpsError("failed-precondition", "يلزم إدخال رمز الشراء");
    }
    return;
  }

  const guardRef = db.collection("_pin_guard").doc(uid);
  const now = Date.now();
  const guard = (await guardRef.get()).data() || {};

  if (Number(guard.lockedUntil || 0) > now) {
    throw new HttpsError(
      "resource-exhausted",
      "تم قفل رمز الشراء مؤقتاً بسبب محاولات خاطئة. حاول بعد قليل"
    );
  }

  const computed = /^\d{4}$/.test(clean)
    ? createHash("sha256").update(clean, "utf8").digest("hex")
    : "";
  const ok = hash !== "" && computed === hash;

  if (ok) {
    if (guard.fails || guard.lockedUntil) {
      await guardRef.set(
        {
          fails: 0,
          lockedUntil: 0,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    }
    return;
  }

  const fails = Number(guard.fails || 0) + 1;
  const locked = fails >= MAX_PIN_FAILS;
  await guardRef.set(
    {
      fails: locked ? 0 : fails,
      lockedUntil: locked ? now + PIN_LOCK_MS : Number(guard.lockedUntil || 0),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );

  throw new HttpsError(
    locked ? "resource-exhausted" : "permission-denied",
    locked
      ? "تم قفل رمز الشراء مؤقتاً بسبب محاولات خاطئة. حاول بعد قليل"
      : "رمز الشراء غير صحيح"
  );
}
