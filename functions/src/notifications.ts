import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

function normalizePhone(phone: string): string {
  let normalized = phone.trim().replace(/[\s\-()]/g, "");
  if (normalized.startsWith("+")) return normalized;
  if (normalized.startsWith("00")) return `+${normalized.substring(2)}`;
  if (normalized.startsWith("0")) return `+964${normalized.substring(1)}`;
  return normalized;
}

export function formatIqd(amount: number): string {
  const value = Math.round(Number(amount) || 0);
  return `${value.toLocaleString("en-US")} د.ع`;
}

async function requireAdmin(uid: string): Promise<void> {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists || snap.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "يتطلب صلاحية أدمن");
  }
}

export async function getUserTokens(userId: string): Promise<string[]> {
  const snap = await db.collection("users").doc(userId).get();
  const tokens = snap.data()?.fcmTokens;
  if (!Array.isArray(tokens)) return [];
  return [...new Set(
    tokens.map((item) => String(item ?? "").trim()).filter(Boolean)
  )];
}

async function removeInvalidTokens(userId: string, invalid: string[]) {
  if (!invalid.length) return;
  await db.collection("users").doc(userId).update({
    fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalid),
  });
}

export interface PushPayload {
  title: string;
  body: string;
  imageUrl?: string;
  iconUrl?: string;
  type?: string;
}

export async function sendPushToUser(
  userId: string,
  payload: PushPayload
): Promise<number> {
  const tokens = await getUserTokens(userId);
  if (!tokens.length) return 0;

  const imageUrl = payload.imageUrl || payload.iconUrl || "";
  const invalid: string[] = [];
  let success = 0;

  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    const response = await messaging.sendEachForMulticast({
      tokens: chunk,
      notification: {
        title: payload.title,
        body: payload.body,
        ...(imageUrl ? {imageUrl} : {}),
      },
      data: {
        type: payload.type ?? "message",
        title: payload.title,
        body: payload.body,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        ...(payload.imageUrl ? {imageUrl: payload.imageUrl} : {}),
        ...(payload.iconUrl ? {iconUrl: payload.iconUrl} : {}),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "kushk_default",
          icon: "ic_stat_kushk",
          color: "#0B3B4A",
          sound: "default",
          defaultSound: true,
          defaultVibrateTimings: true,
          ...(imageUrl ? {imageUrl} : {}),
        },
      },
      apns: {
        payload: {aps: {sound: "default", badge: 1}},
        ...(imageUrl ? {fcmOptions: {imageUrl}} : {}),
      },
    });

    response.responses.forEach((item, index) => {
      if (item.success) {
        success += 1;
        return;
      }
      const code = item.error?.code ?? "";
      if (
        code.includes("registration-token-not-registered") ||
        code.includes("invalid-registration-token") ||
        code.includes("mismatched-credential")
      ) {
        invalid.push(chunk[index]);
      }
    });
  }

  await removeInvalidTokens(userId, invalid);
  return success;
}

export async function writeNotification(params: {
  userId: string;
  type: string;
  title: string;
  body: string;
  badgeEnabled?: boolean;
  imageUrl?: string;
  iconUrl?: string;
  meta?: Record<string, unknown>;
  sendPush?: boolean;
}) {
  const ref = db.collection("notifications").doc();
  const badgeEnabled = params.badgeEnabled !== false;
  const imageUrl = params.imageUrl?.trim() || "";
  const iconUrl = params.iconUrl?.trim() || "";
  await ref.set({
    userId: params.userId,
    type: params.type,
    title: params.title,
    body: params.body,
    badgeEnabled,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(imageUrl ? {imageUrl} : {}),
    ...(iconUrl ? {iconUrl} : {}),
    meta: {
      ...(params.meta ?? {}),
      ...(imageUrl ? {imageUrl} : {}),
      ...(iconUrl ? {iconUrl} : {}),
    },
  });
  if (badgeEnabled) {
    await db.collection("user_notification_state").doc(params.userId).set(
      {
        unreadCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  }
  if (params.sendPush !== false) {
    await sendPushToUser(params.userId, {
      title: params.title,
      body: params.body,
      imageUrl: imageUrl || undefined,
      iconUrl: iconUrl || undefined,
      type: params.type,
    });
  }
  return ref.id;
}

async function resolveCampaignRecipients(data: {
  target?: string;
  phones?: unknown;
  minBalance?: unknown;
  userIds?: unknown;
}): Promise<string[]> {
  const target = String(data.target ?? "all").trim();
  const snap = await db.collection("users").get();
  const shops = snap.docs.filter((doc) => {
    const role = String(doc.data()?.role ?? "shop");
    return role !== "admin";
  });

  if (target === "all") {
    return shops.map((doc) => doc.id);
  }

  if (target === "balance") {
    const minBalance = Number(data.minBalance);
    if (!Number.isFinite(minBalance) || minBalance < 0) {
      throw new HttpsError("invalid-argument", "حد الرصيد غير صالح");
    }
    return shops
      .filter((doc) => Number(doc.data()?.walletBalance ?? 0) > minBalance)
      .map((doc) => doc.id);
  }

  if (target === "phones") {
    const raw = Array.isArray(data.phones) ? data.phones : [];
    const wanted = new Set(
      raw
        .map((item) => normalizePhone(String(item ?? "")))
        .filter((item) => item.length >= 8)
    );
    if (!wanted.size) {
      throw new HttpsError("invalid-argument", "أدخل أرقام هواتف صحيحة");
    }
    return shops
      .filter((doc) => {
        const phone = normalizePhone(String(doc.data()?.phone ?? ""));
        const plain = String(doc.data()?.phone ?? "").trim();
        return wanted.has(phone) || wanted.has(plain) || wanted.has(normalizePhone(plain));
      })
      .map((doc) => doc.id);
  }

  if (target === "users") {
    const raw = Array.isArray(data.userIds) ? data.userIds : [];
    const wanted = new Set(raw.map((item) => String(item ?? "").trim()).filter(Boolean));
    if (!wanted.size) {
      throw new HttpsError("invalid-argument", "اختر مستخدمين أولاً");
    }
    return shops.filter((doc) => wanted.has(doc.id)).map((doc) => doc.id);
  }

  throw new HttpsError("invalid-argument", "نوع التخصيص غير صالح");
}

export const adminSendCampaign = onCall(
  {region: "europe-west1", timeoutSeconds: 300, memory: "512MiB"},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);

    const title = String(request.data?.title ?? "").trim();
    const body = String(request.data?.body ?? "").trim();
    const imageUrl = String(request.data?.imageUrl ?? "").trim();
    const iconUrl = String(request.data?.iconUrl ?? "").trim();
    if (!title || !body) {
      throw new HttpsError("invalid-argument", "العنوان والنص مطلوبان");
    }

    const userIds = await resolveCampaignRecipients(request.data ?? {});
    if (!userIds.length) {
      throw new HttpsError("failed-precondition", "لا يوجد مستلمون مطابقون");
    }

    let delivered = 0;
    for (const userId of userIds) {
      await writeNotification({
        userId,
        type: "admin_campaign",
        title,
        body,
        badgeEnabled: true,
        imageUrl: imageUrl || undefined,
        iconUrl: iconUrl || undefined,
        meta: {fromAdminId: request.auth.uid, target: request.data?.target},
      });
      delivered += 1;
    }

    await db.collection("notification_campaigns").add({
      title,
      body,
      imageUrl: imageUrl || null,
      iconUrl: iconUrl || null,
      target: String(request.data?.target ?? "all"),
      recipientCount: userIds.length,
      createdBy: request.auth.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {ok: true, recipients: userIds.length, delivered};
  }
);

export const onWalletCreditCreated = onDocumentCreated(
  {
    document: "wallet_transactions/{txId}",
    region: "europe-west1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    if (data.type !== "credit") return;
    if (data.topupId) return;
    if (data.orderId) return;

    const userId = String(data.userId ?? "").trim();
    const amount = Number(data.amount ?? 0);
    if (!userId || !Number.isFinite(amount) || amount <= 0) return;

    const body = `تم إيداع مبلغ ${formatIqd(amount)} شكرا لثقتكم`;
    await writeNotification({
      userId,
      type: "wallet_deposit",
      title: "تم الإيداع",
      body,
      badgeEnabled: true,
      meta: {
        amount,
        transactionId: event.params.txId,
        depositMethod: data.depositMethod ?? null,
      },
    });
  }
);
