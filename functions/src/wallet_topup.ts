import * as admin from "firebase-admin";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";
import jwt from "jsonwebtoken";
import {
  createQiPayment,
  getQiPaymentStatus,
  qiPassword,
  qiStatusToInternal,
  qiTerminalId,
  qiUsername,
} from "./qicard";

const db = admin.firestore();
const qiSecrets = [qiUsername, qiPassword, qiTerminalId];
const FEE_RATE = 0.01;
const ZAIN_CASH_FEE_RATE = 0.007;

/** بيانات زين كاش للإنتاج (نفس حساب سجل الدرجات). */
const ZAIN_LIVE = {
  apiUrl: "https://api.zaincash.iq",
  merchantId: "6947d77ec0833ade1b4ea6f1",
  merchantSecret:
    "$2y$10$hzMLdPt/vbCbpKb.c2vN6e0Sf34Q7GCBIU0gxSIj2e2kZoTi1VUuS",
  msisdn: "9647811098146",
};

/** ترويسات تحاكي متصفحاً لتجاوز فحص Cloudflare على api.zaincash.iq. */
const ZAIN_HTTP_HEADERS: Record<string, string> = {
  "Content-Type": "application/x-www-form-urlencoded",
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Accept": "application/json, text/plain, */*",
  "Accept-Language": "ar,en;q=0.9",
};

export function computeTopupFee(
  requestedAmount: number,
  feeRate: number = FEE_RATE
): {
  requestedAmount: number;
  feeAmount: number;
  chargedAmount: number;
  feeRate: number;
} {
  if (!Number.isFinite(requestedAmount) || requestedAmount <= 0) {
    throw new Error("المبلغ غير صالح");
  }
  const amount = Math.floor(requestedAmount);
  if (amount !== requestedAmount || amount < 1000) {
    throw new Error("أدخل مبلغاً صحيحاً بالدينار (1000 فأكثر)");
  }
  const feeAmount = Math.ceil(amount * feeRate);
  return {
    requestedAmount: amount,
    feeAmount,
    chargedAmount: amount + feeAmount,
    feeRate,
  };
}

async function requireActiveShop(uid: string) {
  const snap = await db.collection("users").doc(uid).get();
  const data = snap.data();
  if (
    !snap.exists ||
    data?.role !== "shop" ||
    data?.status === "suspended" ||
    data?.status === "rejected"
  ) {
    throw new HttpsError("permission-denied", "الحساب غير مخوّل للشحن");
  }
  return data;
}

async function qiCreatePaymentForTopup(params: {
  productName: string;
  amount: number;
  description: string;
}) {
  try {
    return await createQiPayment(params);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    throw new HttpsError(
      "unavailable",
      `تعذر الاتصال ببوابة كي من الخادم: ${msg}`
    );
  }
}

async function qiPaymentStatusForTopup(paymentId: string) {
  try {
    return await getQiPaymentStatus(paymentId);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    throw new HttpsError(
      "unavailable",
      `تعذر التحقق من حالة الدفع عبر كي: ${msg}`
    );
  }
}

async function creditTopupIfNeeded(topupId: string): Promise<{
  status: string;
  credited: boolean;
  requestedAmount: number;
}> {
  const topupRef = db.collection("wallet_topups").doc(topupId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(topupRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "عملية الشحن غير موجودة");
    }
    const data = snap.data()!;
    const requestedAmount = Number(data.requestedAmount ?? 0);
    if (data.creditedAt) {
      return {status: "success", credited: false, requestedAmount};
    }
    if (data.status !== "success") {
      return {
        status: String(data.status ?? "pending"),
        credited: false,
        requestedAmount,
      };
    }

    const userRef = db.collection("users").doc(String(data.userId));
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "المستخدم غير موجود");
    }
    const balance = Number(userSnap.data()?.walletBalance ?? 0);
    const after = balance + requestedAmount;
    const txRef = db.collection("wallet_transactions").doc();
    const provider = String(data.provider ?? "dnz");
    const isZain = provider === "zaincash";
    tx.update(userRef, {walletBalance: after});
    tx.set(txRef, {
      userId: data.userId,
      type: "credit",
      amount: requestedAmount,
      balanceAfter: after,
      reason: isZain ? "شحن محفظة عبر زين كاش" : "شحن محفظة عبر DNZ",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      companyName: isZain ? "زين كاش" : "DNZ",
      visibleToUser: true,
      depositMethod: "online",
      topupId,
      provider,
      dnzPaymentId: data.dnzPaymentId ?? null,
      zainTransactionId: data.zainTransactionId ?? null,
    });
    tx.update(topupRef, {
      creditedAt: admin.firestore.FieldValue.serverTimestamp(),
      walletTransactionId: txRef.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {status: "success", credited: true, requestedAmount};
  });
}

/** إنشاء رابط دفع كي لشحن المحفظة. */
export const createWalletTopup = onCall(
  {
    secrets: qiSecrets,
    region: "me-west1",
    timeoutSeconds: 60,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const uid = request.auth.uid;
    await requireActiveShop(uid);

    let fees;
    try {
      fees = computeTopupFee(Number(request.data?.amount));
    } catch (error) {
      throw new HttpsError(
        "invalid-argument",
        error instanceof Error ? error.message : "المبلغ غير صالح"
      );
    }

    const topupRef = db.collection("wallet_topups").doc();
    const qi = await qiCreatePaymentForTopup({
      productName: `شحن محفظة كشك #${topupRef.id.slice(0, 8)}`,
      amount: fees.chargedAmount,
      description: `شحن ${fees.requestedAmount} د.ع + رسم ${fees.feeAmount}`,
    });
    const dnzPaymentId = qi.paymentId;
    const checkoutUrl = qi.formUrl;

    await topupRef.set({
      userId: uid,
      requestedAmount: fees.requestedAmount,
      feeAmount: fees.feeAmount,
      chargedAmount: fees.chargedAmount,
      currency: "IQD",
      feeRate: fees.feeRate,
      provider: "dnz",
      dnzPaymentId,
      checkoutUrl,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      topupId: topupRef.id,
      provider: "dnz",
      dnzPaymentId,
      checkoutUrl,
      requestedAmount: fees.requestedAmount,
      feeAmount: fees.feeAmount,
      chargedAmount: fees.chargedAmount,
      status: "pending",
    };
  }
);

/** التحقق من حالة الدفع من كي وإضافة الرصيد مرة واحدة فقط عند النجاح. */
export const checkWalletTopupStatus = onCall(
  {
    secrets: qiSecrets,
    region: "me-west1",
    timeoutSeconds: 60,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const uid = request.auth.uid;
    const topupId = String(request.data?.topupId ?? "").trim();
    if (!topupId) {
      throw new HttpsError("invalid-argument", "معرّف الشحن مطلوب");
    }

    const topupRef = db.collection("wallet_topups").doc(topupId);
    const snap = await topupRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "عملية الشحن غير موجودة");
    }
    const data = snap.data()!;
    if (data.userId !== uid) {
      throw new HttpsError("permission-denied", "غير مسموح");
    }

    if (data.creditedAt) {
      return {
        topupId,
        status: "success",
        credited: false,
        requestedAmount: data.requestedAmount,
        feeAmount: data.feeAmount,
        chargedAmount: data.chargedAmount,
        checkoutUrl: data.checkoutUrl,
      };
    }

    if (String(data.provider ?? "dnz") === "zaincash") {
      const txId = String(data.zainTransactionId ?? "").trim();
      if (!txId) {
        return {
          topupId,
          status: "pending",
          credited: false,
          requestedAmount: data.requestedAmount,
          feeAmount: data.feeAmount,
          chargedAmount: data.chargedAmount,
          checkoutUrl: data.checkoutUrl,
        };
      }
      const zain = await zainCashGetStatus(txId);
      const status = normalizeZainStatus(zain?.status);
      await topupRef.update({
        status,
        zainStatusRaw: zain?.status ?? null,
        lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (status === "success") {
        const credit = await creditTopupIfNeeded(topupId);
        return {
          topupId,
          status: "success",
          credited: credit.credited,
          requestedAmount: data.requestedAmount,
          feeAmount: data.feeAmount,
          chargedAmount: data.chargedAmount,
          checkoutUrl: data.checkoutUrl,
        };
      }
      return {
        topupId,
        status,
        credited: false,
        requestedAmount: data.requestedAmount,
        feeAmount: data.feeAmount,
        chargedAmount: data.chargedAmount,
        checkoutUrl: data.checkoutUrl,
      };
    }

    const qi = await qiPaymentStatusForTopup(String(data.dnzPaymentId));
    const status = qiStatusToInternal(qi.status);

    await topupRef.update({
      status,
      dnzStatusRaw: qi.status ?? null,
      lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (status === "success") {
      const credit = await creditTopupIfNeeded(topupId);
      return {
        topupId,
        status: "success",
        credited: credit.credited,
        requestedAmount: data.requestedAmount,
        feeAmount: data.feeAmount,
        chargedAmount: data.chargedAmount,
        checkoutUrl: data.checkoutUrl,
      };
    }

    return {
      topupId,
      status,
      credited: false,
      requestedAmount: data.requestedAmount,
      feeAmount: data.feeAmount,
      chargedAmount: data.chargedAmount,
      checkoutUrl: data.checkoutUrl,
    };
  }
);

/** إعادة فحص كل عمليات الشحن المعلقة للمستخدم الحالي. */
export const reconcilePendingWalletTopups = onCall(
  {
    secrets: qiSecrets,
    region: "me-west1",
    timeoutSeconds: 120,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const uid = request.auth.uid;
    const pending = await db
      .collection("wallet_topups")
      .where("userId", "==", uid)
      .where("status", "==", "pending")
      .limit(20)
      .get();

    const results = [];
    for (const doc of pending.docs) {
      const data = doc.data();
      try {
        if (String(data.provider ?? "dnz") === "zaincash") {
          const zainId = String(data.zainTransactionId ?? "").trim();
          if (!zainId) {
            results.push({
              topupId: doc.id,
              status: "pending",
              credited: false,
              error: "missing_zain_id",
            });
            continue;
          }
          const zain = await zainCashGetStatus(zainId);
          const status = normalizeZainStatus(zain?.status);
          await doc.ref.update({
            status,
            zainStatusRaw: zain?.status ?? null,
            lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          if (status === "success") {
            const credit = await creditTopupIfNeeded(doc.id);
            results.push({
              topupId: doc.id,
              status: "success",
              credited: credit.credited,
            });
          } else {
            results.push({topupId: doc.id, status, credited: false});
          }
          continue;
        }

        const qi = await qiPaymentStatusForTopup(String(data.dnzPaymentId));
        const status = qiStatusToInternal(qi.status);
        await doc.ref.update({
          status,
          dnzStatusRaw: qi.status ?? null,
          lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        if (status === "success") {
          const credit = await creditTopupIfNeeded(doc.id);
          results.push({
            topupId: doc.id,
            status: "success",
            credited: credit.credited,
          });
        } else {
          results.push({topupId: doc.id, status, credited: false});
        }
      } catch (error) {
        results.push({
          topupId: doc.id,
          status: "pending",
          credited: false,
          error: error instanceof Error ? error.message : "check_failed",
        });
      }
    }
    return {ok: true, results};
  }
);

/** إشعار كي بعد الدفع. الرصيد لا يُضاف إلا بعد التحقق من API كي. */
export const qiPaymentWebhook = onRequest(
  {
    secrets: qiSecrets,
    region: "me-west1",
    invoker: "public",
  },
  async (req, res) => {
    const body =
      req.body && typeof req.body === "object"
        ? (req.body as Record<string, unknown>)
        : {};
    const paymentId = String(body.paymentId || body.payment_id || "").trim();
    if (!paymentId) {
      res.status(200).json({ok: true, ignored: true});
      return;
    }
    try {
      const pending = await db
        .collection("wallet_topups")
        .where("dnzPaymentId", "==", paymentId)
        .limit(1)
        .get();
      if (pending.empty) {
        res.status(200).json({ok: true, ignored: true});
        return;
      }
      const doc = pending.docs[0];
      const qi = await getQiPaymentStatus(paymentId);
      const status = qiStatusToInternal(qi.status);
      await doc.ref.update({
        status,
        dnzStatusRaw: qi.status ?? null,
        lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (status === "success") {
        await creditTopupIfNeeded(doc.id);
      }
      res.status(200).json({ok: true, status});
    } catch (error) {
      console.error(
        "qiPaymentWebhook",
        error instanceof Error ? error.message : String(error)
      );
      res.status(200).json({ok: false});
    }
  }
);

function normalizeZainStatus(raw: unknown): "pending" | "success" | "failed" {
  const value = String(raw ?? "pending").toLowerCase();
  if (["success", "successful", "completed", "complete", "paid"].includes(value)) {
    return "success";
  }
  if (["failed", "fail", "error", "cancelled", "canceled", "rejected"].includes(value)) {
    return "failed";
  }
  return "pending";
}

async function zainCashSign(payload: Record<string, unknown>): Promise<string> {
  return jwt.sign(payload, ZAIN_LIVE.merchantSecret);
}

async function zainCashGetStatus(
  transactionId: string
): Promise<Record<string, unknown> | null> {
  const now = Math.floor(Date.now() / 1000);
  const token = await zainCashSign({
    id: transactionId,
    msisdn: ZAIN_LIVE.msisdn,
    iat: now,
    exp: now + 60 * 60 * 4,
  });
  const body = new URLSearchParams({
    token,
    merchantId: ZAIN_LIVE.merchantId,
  });
  const response = await fetch(`${ZAIN_LIVE.apiUrl}/transaction/get`, {
    method: "POST",
    headers: ZAIN_HTTP_HEADERS,
    body: body.toString(),
    signal: AbortSignal.timeout(30000),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new HttpsError(
      "unavailable",
      `تعذر التحقق من زين كاش (${response.status})`
    );
  }
  try {
    return text ? (JSON.parse(text) as Record<string, unknown>) : null;
  } catch {
    throw new HttpsError("unavailable", "استجابة زين كاش غير صالحة");
  }
}

async function zainCashInit(params: {
  amount: number;
  orderId: string;
  serviceType: string;
  redirectUrl: string;
}): Promise<{transactionId: string; paymentUrl: string}> {
  const now = Math.floor(Date.now() / 1000);
  const token = await zainCashSign({
    amount: params.amount,
    serviceType: params.serviceType,
    msisdn: ZAIN_LIVE.msisdn,
    orderId: params.orderId,
    redirectUrl: params.redirectUrl,
    iat: now,
    exp: now + 60 * 60 * 4,
  });
  const body = new URLSearchParams({
    token,
    merchantId: ZAIN_LIVE.merchantId,
    lang: "ar",
  });
  console.info(
    "zaincash init request",
    JSON.stringify({
      url: `${ZAIN_LIVE.apiUrl}/transaction/init`,
      amount: params.amount,
      orderId: params.orderId,
    })
  );
  let response: Response;
  try {
    response = await fetch(`${ZAIN_LIVE.apiUrl}/transaction/init`, {
      method: "POST",
      headers: ZAIN_HTTP_HEADERS,
      body: body.toString(),
      signal: AbortSignal.timeout(30000),
    });
  } catch (err) {
    console.error(
      "zaincash init fetch failed",
      err instanceof Error ? `${err.name}: ${err.message}` : String(err)
    );
    throw new HttpsError(
      "unavailable",
      "تعذر الاتصال ببوابة زين كاش، حاول لاحقاً"
    );
  }
  const text = await response.text();
  console.info(
    "zaincash init response",
    JSON.stringify({
      status: response.status,
      contentType: response.headers.get("content-type"),
      bodyPreview: (text || "").slice(0, 500),
      amount: params.amount,
      orderId: params.orderId,
    })
  );
  let json: Record<string, unknown> = {};
  try {
    json = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  } catch {
    throw new HttpsError("unavailable", "استجابة زين كاش غير صالحة");
  }
  if (!response.ok) {
    const message =
      String(json.err ?? json.msg ?? "") ||
      `تعذر إنشاء دفع زين كاش (${response.status})`;
    throw new HttpsError("failed-precondition", message);
  }
  const id = String(json.id ?? "").trim();
  if (!id) {
    const message =
      String(json.err ?? json.msg ?? "") || "لم يتم استلام معرّف معاملة زين كاش";
    throw new HttpsError("failed-precondition", message);
  }
  return {
    transactionId: id,
    paymentUrl: `${ZAIN_LIVE.apiUrl}/transaction/pay?id=${id}`,
  };
}

/**
 * إنشاء معاملة دفع زين كاش على الخادم (التوقيع بالسر يبقى في الخادم فقط).
 * يُستدعى بعد createZainCashTopup ويعيد رابط الدفع ومعرّف المعاملة.
 */
export const startZainCashPayment = onCall(
  {
    region: "me-west1",
    timeoutSeconds: 60,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const uid = request.auth.uid;
    const topupId = String(request.data?.topupId ?? "").trim();
    if (!topupId) {
      throw new HttpsError("invalid-argument", "معرّف الشحن مطلوب");
    }

    const topupRef = db.collection("wallet_topups").doc(topupId);
    const snap = await topupRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "عملية الشحن غير موجودة");
    }
    const data = snap.data()!;
    if (data.userId !== uid) {
      throw new HttpsError("permission-denied", "غير مسموح");
    }
    if (String(data.provider) !== "zaincash") {
      throw new HttpsError("failed-precondition", "ليست عملية زين كاش");
    }

    const existingId = String(data.zainTransactionId ?? "").trim();
    const existingUrl = String(data.checkoutUrl ?? "").trim();
    if (existingId && existingUrl) {
      return {
        topupId,
        zainTransactionId: existingId,
        checkoutUrl: existingUrl,
      };
    }

    const amount = Number(data.chargedAmount ?? 0);
    if (!(amount > 0)) {
      throw new HttpsError("failed-precondition", "مبلغ الشحن غير صالح");
    }

    console.info(
      "startZainCashPayment invoked",
      JSON.stringify({uid, topupId, amount})
    );
    const init = await zainCashInit({
      amount,
      orderId: topupId,
      serviceType: "شحن محفظة DNZ card",
      redirectUrl: "https://payment-success.com/callback",
    });

    await topupRef.update({
      zainTransactionId: init.transactionId,
      checkoutUrl: init.paymentUrl,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      topupId,
      zainTransactionId: init.transactionId,
      checkoutUrl: init.paymentUrl,
    };
  }
);

/** إنشاء سجل شحن زين كاش (العميل ينشئ رابط الدفع بنفس ترتيب سجل الدرجات). */
export const createZainCashTopup = onCall(
  {
    region: "me-west1",
    timeoutSeconds: 60,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const uid = request.auth.uid;
    await requireActiveShop(uid);

    let fees;
    try {
      fees = computeTopupFee(Number(request.data?.amount), ZAIN_CASH_FEE_RATE);
    } catch (error) {
      throw new HttpsError(
        "invalid-argument",
        error instanceof Error ? error.message : "المبلغ غير صالح"
      );
    }

    const topupRef = db.collection("wallet_topups").doc();
    await topupRef.set({
      userId: uid,
      requestedAmount: fees.requestedAmount,
      feeAmount: fees.feeAmount,
      chargedAmount: fees.chargedAmount,
      currency: "IQD",
      feeRate: fees.feeRate,
      provider: "zaincash",
      zainTransactionId: null,
      checkoutUrl: null,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      topupId: topupRef.id,
      provider: "zaincash",
      requestedAmount: fees.requestedAmount,
      feeAmount: fees.feeAmount,
      chargedAmount: fees.chargedAmount,
      status: "pending",
    };
  }
);

/** ربط معرّف معاملة زين كاش بعد إنشائها من التطبيق. */
export const registerZainCashTransaction = onCall(
  {
    region: "me-west1",
    timeoutSeconds: 30,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const uid = request.auth.uid;
    const topupId = String(request.data?.topupId ?? "").trim();
    const zainTransactionId = String(
      request.data?.zainTransactionId ?? ""
    ).trim();
    const checkoutUrl = String(request.data?.checkoutUrl ?? "").trim();
    if (!topupId || !zainTransactionId) {
      throw new HttpsError("invalid-argument", "بيانات المعاملة ناقصة");
    }

    const topupRef = db.collection("wallet_topups").doc(topupId);
    const snap = await topupRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "عملية الشحن غير موجودة");
    }
    const data = snap.data()!;
    if (data.userId !== uid) {
      throw new HttpsError("permission-denied", "غير مسموح");
    }
    if (String(data.provider) !== "zaincash") {
      throw new HttpsError("failed-precondition", "ليست عملية زين كاش");
    }

    await topupRef.update({
      zainTransactionId,
      checkoutUrl: checkoutUrl || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {ok: true, topupId, zainTransactionId};
  }
);

/** التحقق من دفع زين كاش وإضافة الرصيد مرة واحدة فقط. */
export const completeZainCashTopup = onCall(
  {
    region: "me-west1",
    timeoutSeconds: 60,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const uid = request.auth.uid;
    const topupId = String(request.data?.topupId ?? "").trim();
    const zainTransactionId = String(
      request.data?.zainTransactionId ?? ""
    ).trim();
    if (!topupId) {
      throw new HttpsError("invalid-argument", "معرّف الشحن مطلوب");
    }

    const topupRef = db.collection("wallet_topups").doc(topupId);
    const snap = await topupRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "عملية الشحن غير موجودة");
    }
    const data = snap.data()!;
    if (data.userId !== uid) {
      throw new HttpsError("permission-denied", "غير مسموح");
    }
    if (String(data.provider) !== "zaincash") {
      throw new HttpsError("failed-precondition", "ليست عملية زين كاش");
    }

    if (data.creditedAt) {
      return {
        topupId,
        status: "success",
        credited: false,
        requestedAmount: data.requestedAmount,
        feeAmount: data.feeAmount,
        chargedAmount: data.chargedAmount,
      };
    }

    const txId = zainTransactionId || String(data.zainTransactionId ?? "").trim();
    if (!txId) {
      throw new HttpsError("failed-precondition", "معرّف زين كاش غير موجود");
    }

    if (zainTransactionId && !data.zainTransactionId) {
      await topupRef.update({
        zainTransactionId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    const zain = await zainCashGetStatus(txId);
    const status = normalizeZainStatus(zain?.status);

    await topupRef.update({
      status,
      zainStatusRaw: zain?.status ?? null,
      zainTransactionId: txId,
      lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (status === "success") {
      const credit = await creditTopupIfNeeded(topupId);
      return {
        topupId,
        status: "success",
        credited: credit.credited,
        requestedAmount: data.requestedAmount,
        feeAmount: data.feeAmount,
        chargedAmount: data.chargedAmount,
      };
    }

    return {
      topupId,
      status,
      credited: false,
      requestedAmount: data.requestedAmount,
      feeAmount: data.feeAmount,
      chargedAmount: data.chargedAmount,
      message: zain?.msg ?? null,
    };
  }
);
