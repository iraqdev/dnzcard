import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {setGlobalOptions} from "firebase-functions/v2";
import {formatIqd, writeNotification} from "./notifications";
import {assertRateLimit, clientRateKey} from "./rate_limit";

admin.initializeApp();
setGlobalOptions({
  region: "europe-west1",
  enforceAppCheck: false,
});

const db = admin.firestore();
const auth = admin.auth();

function normalizePhone(phone: string): string {
  let normalized = phone.trim().replace(/[\s\-()]/g, "");
  if (normalized.startsWith("+")) return normalized;
  if (normalized.startsWith("00")) return `+${normalized.substring(2)}`;
  if (normalized.startsWith("0")) return `+964${normalized.substring(1)}`;
  return normalized;
}

function phoneToAuthEmail(phone: string): string {
  let normalized = normalizePhone(phone);
  if (normalized.startsWith("+")) normalized = normalized.substring(1);
  return `${normalized}@kushk.app`;
}

async function requireAdmin(uid: string): Promise<void> {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists || snap.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "يتطلب صلاحية أدمن");
  }
}

async function findUserByPhone(phone: string) {
  const normalized = normalizePhone(phone);
  const snap = await db
    .collection("users")
    .where("phone", "==", normalized)
    .limit(1)
    .get();
  if (!snap.empty) {
    return {id: snap.docs[0].id, data: snap.docs[0].data()};
  }
  // توافق مع أرقام مخزّنة بدون +
  const alt = await db
    .collection("users")
    .where("phone", "==", phone.trim())
    .limit(1)
    .get();
  if (!alt.empty) {
    return {id: alt.docs[0].id, data: alt.docs[0].data()};
  }
  return null;
}

async function trustDevice(
  userId: string,
  deviceId: string,
  deviceName: string
) {
  await db
    .collection("users")
    .doc(userId)
    .collection("devices")
    .doc(deviceId)
    .set(
      {
        deviceId,
        deviceName,
        trusted: true,
        revoked: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
}

/** إنشاء طلب استعادة كلمة المرور — بدون حفظ كلمة المرور. */
export const createPasswordResetRequest = onCall(
  {
    // يُستدعى قبل تسجيل الدخول؛ لا يعتمد على Auth/Anonymous.
    invoker: "public",
  },
  async (request) => {
  const phone = String(request.data?.phone ?? "");
  const deviceId = String(request.data?.deviceId ?? "");
  const deviceName = String(request.data?.deviceName ?? "جهاز");
  if (!phone || !deviceId) {
    throw new HttpsError("invalid-argument", "الهاتف ومعرّف الجهاز مطلوبان");
  }
  await assertRateLimit(
    clientRateKey("pwd_reset_create", request, normalizePhone(phone)),
    5,
    15 * 60 * 1000,
  );
  const user = await findUserByPhone(phone);
  if (!user) {
    throw new HttpsError("not-found", "لا يوجد حساب بهذا الرقم");
  }
  if (
    user.data.status === "suspended" ||
    user.data.status === "rejected"
  ) {
    throw new HttpsError("failed-precondition", "الحساب موقوف");
  }

  const pending = await db
    .collection("password_reset_requests")
    .where("userId", "==", user.id)
    .where("status", "==", "pending")
    .limit(1)
    .get();
  if (!pending.empty) {
    return {requestId: pending.docs[0].id, status: "pending"};
  }

  const ref = db.collection("password_reset_requests").doc();
  await ref.set({
    userId: user.id,
    phone: normalizePhone(phone),
    shopName: user.data.shopName ?? "",
    deviceId,
    deviceName,
    status: "pending",
    serverApproved: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {requestId: ref.id, status: "pending"};
});

/** موافقة/رفض الأدمن لطلب الاستعادة. */
export const reviewPasswordResetRequest = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
  }
  await requireAdmin(request.auth.uid);
  const requestId = String(request.data?.requestId ?? "");
  const approve = Boolean(request.data?.approve);
  if (!requestId) {
    throw new HttpsError("invalid-argument", "معرّف الطلب مطلوب");
  }
  const ref = db.collection("password_reset_requests").doc(requestId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "الطلب غير موجود");
  if (snap.data()?.status !== "pending") {
    throw new HttpsError("failed-precondition", "الطلب ليس معلّقاً");
  }
  const data = snap.data()!;
  await ref.update({
    status: approve ? "approved" : "rejected",
    serverApproved: approve,
    reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    reviewedBy: request.auth.uid,
  });
  if (approve) {
    const userId = String(data.userId ?? "");
    if (userId) {
      await writeNotification({
        userId,
        type: "password_reset_approved",
        title: "تمت الموافقة على كلمة السر",
        body: "تمت الموافقة على الرقم السري الخاص بك يرجى تسجيل الدخول",
        badgeEnabled: true,
        meta: {requestId},
      });
    }
  }
  return {ok: true};
});

/** حالة طلب الاستعادة للجهاز الطالب (بدون Auth). */
export const getPasswordResetStatus = onCall(
  {invoker: "public"},
  async (request) => {
    const requestId = String(request.data?.requestId ?? "").trim();
    const deviceId = String(request.data?.deviceId ?? "").trim();
    if (!requestId || !deviceId) {
      throw new HttpsError("invalid-argument", "بيانات غير مكتملة");
    }
    await assertRateLimit(
      clientRateKey("pwd_reset_status", request, requestId),
      30,
      15 * 60 * 1000,
    );
    const snap = await db
      .collection("password_reset_requests")
      .doc(requestId)
      .get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "الطلب غير موجود");
    }
    const data = snap.data()!;
    if (String(data.deviceId ?? "") !== deviceId) {
      throw new HttpsError("permission-denied", "الجهاز غير مطابق للطلب");
    }
    return {
      ok: true,
      status: String(data.status ?? "pending"),
      serverApproved: data.serverApproved === true,
      phone: String(data.phone ?? ""),
    };
  }
);

/**
 * إكمال الاستعادة من جهاز طالب الطلب بعد موافقة الأدمن.
 * يستقبل كلمة المرور عبر TLS فقط ولا يخزّنها في Firestore.
 */
export const completePasswordReset = onCall(
  {
    invoker: "public",
  },
  async (request) => {
  const requestId = String(request.data?.requestId ?? "");
  const password = String(request.data?.password ?? "");
  const deviceId = String(request.data?.deviceId ?? "");
  const deviceName = String(request.data?.deviceName ?? "جهاز");
  if (!requestId || password.length < 6 || !deviceId) {
    throw new HttpsError("invalid-argument", "بيانات غير مكتملة");
  }
  await assertRateLimit(
    clientRateKey("pwd_reset_complete", request, requestId),
    10,
    15 * 60 * 1000,
  );
  const ref = db.collection("password_reset_requests").doc(requestId);
  const snap = await ref.get();
  const data = snap.data();
  if (!snap.exists || !data) {
    throw new HttpsError("not-found", "الطلب غير موجود");
  }
  if (data.status !== "approved" || data.serverApproved !== true) {
    throw new HttpsError("failed-precondition", "الطلب غير معتمد من الخادم");
  }
  if (data.deviceId !== deviceId) {
    throw new HttpsError("permission-denied", "الجهاز غير مطابق للطلب");
  }
  if (data.completedAt) {
    throw new HttpsError("already-exists", "تم إكمال الطلب مسبقاً");
  }

  const userId = String(data.userId);
  const phone = String(data.phone ?? "");
  const authEmail = phone ? phoneToAuthEmail(phone) : "";
  try {
    await auth.updateUser(userId, {
      password,
      ...(authEmail ? {email: authEmail, emailVerified: true} : {}),
    });
  } catch (e: unknown) {
    const code = (e as {code?: string})?.code ?? "";
    // إن تعذّر تعيين البريد (تعارض)، نحدّث كلمة المرور فقط.
    if (authEmail && code.includes("email")) {
      await auth.updateUser(userId, {password});
    } else {
      throw e;
    }
  }
  await trustDevice(userId, deviceId, deviceName);
  await writeNotification({
    userId,
    type: "password_changed",
    title: "تم تغيير كلمة المرور",
    body: "تم تغيير كلمة المرور الخاصة بك بنجاح. يمكنك تسجيل الدخول الآن.",
    badgeEnabled: true,
    meta: {requestId},
  });
  await ref.update({
    status: "completed",
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  const token = await auth.createCustomToken(userId, {
    deviceId,
    passwordReset: true,
  });
  return {customToken: token};
});

/**
 * توافق مع إصدارات التطبيق القديمة: السماح بأي جهاز مباشرةً
 * دون إنشاء طلبات وصول أو إلغاء اعتماد أي جهاز آخر.
 */
export const registerOrRequestDevice = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
  }
  const uid = request.auth.uid;
  const deviceId = String(request.data?.deviceId ?? "");
  const deviceName = String(request.data?.deviceName ?? "جهاز");
  if (!deviceId) {
    throw new HttpsError("invalid-argument", "معرّف الجهاز مطلوب");
  }

  await trustDevice(uid, deviceId, deviceName);
  return {status: "trusted"};
});

/** إرسال رسالة أدمن تظهر كإشعار داخل التطبيق. */
export const sendAdminMessage = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
  }
  await requireAdmin(request.auth.uid);
  const userId = String(request.data?.userId ?? "");
  const title = String(request.data?.title ?? "").trim();
  const body = String(request.data?.body ?? "").trim();
  if (!userId || !title || !body) {
    throw new HttpsError("invalid-argument", "الحقول مطلوبة");
  }
  const notificationId = await writeNotification({
    userId,
    type: "admin_message",
    title,
    body,
    badgeEnabled: true,
    meta: {fromAdminId: request.auth.uid},
  });
  return {notificationId};
});

/** حذف مستخدم من Auth وFirestore بواسطة الأدمن. */
export const adminDeleteUser = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
  }
  await requireAdmin(request.auth.uid);
  const targetUserId = String(request.data?.userId ?? "").trim();
  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "معرّف المستخدم مطلوب");
  }
  if (targetUserId === request.auth.uid) {
    throw new HttpsError("failed-precondition", "لا يمكنك حذف حسابك الحالي");
  }

  const userRef = db.collection("users").doc(targetUserId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "المستخدم غير موجود");
  }

  // حذف أسعار خاصة وأجهزة موثوقة
  for (const sub of ["customPrices", "devices"] as const) {
    const docs = await userRef.collection(sub).limit(400).get();
    if (!docs.empty) {
      const batch = db.batch();
      for (const doc of docs.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
    }
  }

  // حذف حالة الإشعارات
  await db.collection("user_notification_state").doc(targetUserId).delete()
    .catch(() => undefined);

  await userRef.delete();

  try {
    await auth.deleteUser(targetUserId);
  } catch (error: unknown) {
    const code = (error as {code?: string})?.code;
    if (code !== "auth/user-not-found") {
      throw new HttpsError(
        "internal",
        "تم حذف بيانات Firestore وتعذر حذف حساب الدخول",
      );
    }
  }

  return {ok: true, userId: targetUserId};
});

/**
 * تغيير كلمة مرور مستخدم بواسطة الأدمن (عبر Auth Admin SDK).
 * لا تُخزَّن كلمة المرور في Firestore.
 */
export const adminSetUserPassword = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
  }
  await requireAdmin(request.auth.uid);
  const targetUserId = String(request.data?.userId ?? "").trim();
  const password = String(request.data?.password ?? "");
  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "معرّف المستخدم مطلوب");
  }
  if (password.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "كلمة المرور يجب أن تكون 6 أحرف على الأقل",
    );
  }

  const userSnap = await db.collection("users").doc(targetUserId).get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "المستخدم غير موجود");
  }

  try {
    await auth.updateUser(targetUserId, {password});
  } catch (error: unknown) {
    const code = (error as {code?: string})?.code ?? "";
    if (code === "auth/user-not-found") {
      throw new HttpsError("not-found", "حساب الدخول غير موجود");
    }
    throw new HttpsError("internal", "تعذر تغيير كلمة المرور");
  }

  await writeNotification({
    userId: targetUserId,
    type: "password_changed",
    title: "تم تغيير كلمة المرور",
    body: "قام الأدمن بتغيير كلمة المرور الخاصة بحسابك.",
    badgeEnabled: true,
    meta: {fromAdminId: request.auth.uid},
  });

  return {ok: true, userId: targetUserId};
});

/**
 * تحديث بيانات مستخدم بواسطة الأدمن.
 * عند تغيير الهاتف يُحدَّث بريد Auth المستخدم للدخول.
 */
export const adminUpdateUser = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
  }
  await requireAdmin(request.auth.uid);

  const targetUserId = String(request.data?.userId ?? "").trim();
  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "معرّف المستخدم مطلوب");
  }

  const name = String(request.data?.name ?? "").trim();
  const shopName = String(request.data?.shopName ?? "").trim();
  const phone = String(request.data?.phone ?? "").trim();
  const email = String(request.data?.email ?? "").trim();
  const role = String(request.data?.role ?? "").trim();
  const status = String(request.data?.status ?? "").trim();
  const walletBalanceRaw = request.data?.walletBalance;
  const walletBalance = Number(walletBalanceRaw);
  const deferredOwedRaw = request.data?.deferredOwed;
  const deferredOwed = Number(deferredOwedRaw);

  if (!name || !phone) {
    throw new HttpsError("invalid-argument", "الاسم والهاتف مطلوبان");
  }
  if (role !== "admin" && role !== "shop") {
    throw new HttpsError("invalid-argument", "الدور غير صالح");
  }
  if (!["approved", "suspended", "rejected"].includes(status)) {
    throw new HttpsError("invalid-argument", "الحالة غير صالحة");
  }
  if (!Number.isFinite(walletBalance) || walletBalance < 0) {
    throw new HttpsError("invalid-argument", "الرصيد غير صالح");
  }
  if (!Number.isFinite(deferredOwed) || deferredOwed < 0) {
    throw new HttpsError("invalid-argument", "رقم الآجل غير صالح");
  }

  const userRef = db.collection("users").doc(targetUserId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "المستخدم غير موجود");
  }

  const previousPhone = String(userSnap.data()?.phone ?? "");
  const storedDeferred = userSnap.data()?.deferredOwed;
  const previousDeferredRaw = request.data?.previousDeferredOwed;
  const previousDeferred = previousDeferredRaw == null
    ? (storedDeferred == null ? null : Number(storedDeferred))
    : Number(previousDeferredRaw);

  await userRef.update({
    name,
    shopName,
    phone,
    email,
    role,
    status,
    walletBalance,
    deferredOwed,
  });

  if (
    previousDeferred != null &&
    Number.isFinite(previousDeferred) &&
    previousDeferred > deferredOwed
  ) {
    await writeNotification({
      userId: targetUserId,
      type: "deferred_updated",
      title: "تحديث الآجل",
      body:
        `تم تقليل الدين من ${formatIqd(previousDeferred)} ` +
        `إلى ${formatIqd(deferredOwed)}`,
      badgeEnabled: true,
      meta: {
        fromAdminId: request.auth.uid,
        previousDeferred,
        deferredOwed,
      },
    });
  }

  if (phone && phone !== previousPhone) {
    const authEmail = phoneToAuthEmail(phone);
    try {
      await auth.updateUser(targetUserId, {
        email: authEmail,
        emailVerified: true,
      });
    } catch (error: unknown) {
      const code = (error as {code?: string})?.code ?? "";
      if (code === "auth/email-already-exists") {
        throw new HttpsError(
          "already-exists",
          "رقم الهاتف مرتبط بحساب دخول آخر",
        );
      }
      if (code !== "auth/user-not-found") {
        throw new HttpsError(
          "internal",
          "تم حفظ البيانات وتعذر مزامنة حساب الدخول",
        );
      }
    }
  }

  return {ok: true, userId: targetUserId};
});

/** تعليم إشعارات المستخدم المقروءة (مع تصفير العداد). */
export const markNotificationsRead = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
  }
  const uid = request.auth.uid;
  const snap = await db
    .collection("notifications")
    .where("userId", "==", uid)
    .where("read", "==", false)
    .where("badgeEnabled", "==", true)
    .get();
  const batch = db.batch();
  for (const doc of snap.docs) {
    batch.update(doc.ref, {
      read: true,
      readAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  batch.set(
    db.collection("user_notification_state").doc(uid),
    {
      unreadCount: 0,
      lastReadAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
  await batch.commit();
  return {ok: true, marked: snap.size};
});

export const phoneEmailHelper = {phoneToAuthEmail, normalizePhone};

export {adminSendCampaign, onWalletCreditCreated} from "./notifications";

export {
  createWalletTopup,
  checkWalletTopupStatus,
  reconcilePendingWalletTopups,
  qiPaymentWebhook,
  createZainCashTopup,
  startZainCashPayment,
  registerZainCashTransaction,
  completeZainCashTopup,
  computeTopupFee,
} from "./wallet_topup";

export {qiPaymentFinish} from "./qicard";

export {
  baqatyBotStatus,
  baqatySaveAccount,
  baqatyFetchCatalog,
  baqatyBuyCards,
  baqatyAutoRefill,
} from "./baqaty_bot";

export {scanCardImage} from "./card_ocr";

export {purchaseLocalProduct} from "./local_purchase";
export {adminBackfillOrderSnapshots} from "./order_snapshots_backfill";

export {onInventoryCodeCreated} from "./inventory_upload_trigger";

export {
  fazerGetBalance,
  fazerSyncGiftCategories,
  fazerSyncGameKeyCategories,
  fazerSyncTopupCategories,
  fazerSyncTelegramCatalog,
  fazerSyncCategoryOffers,
  fazerValidateTopupId,
  fazerSetOfferKushkPrice,
  fazerPurchaseGiftCard,
  fazerReconcileOrders,
  fazerAutoSync,
} from "./fazer_cards";
