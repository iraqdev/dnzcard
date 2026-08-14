import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {assertRateLimit, clientRateKey} from "./rate_limit";
import {verifyPurchasePin} from "./purchase_guard";

const db = admin.firestore();
const fazerApiKey = defineSecret("FAZER_API_KEY");
const FAZER_BASE = "https://api.fzr.cards/api/v2";

type JsonMap = Record<string, unknown>;

function offerDocId(categoryId: string, cardId: string): string {
  return `${categoryId}__${cardId}`.replace(/[/#]/g, "_");
}

/**
 * فئات العملات الرقمية (كربتو) المحجوبة عن الظهور في التطبيق.
 * تُستثنى من المزامنة والشراء (حالياً عائلة Binance).
 */
function isBlockedCryptoCategory(categoryId: string, name = ""): boolean {
  const id = categoryId.toLowerCase();
  const n = name.toLowerCase();
  return id.startsWith("binance_") || n.includes("binance");
}

/** رقم تسلسلي محايد للإيصال (لا يكشف مزوّد البطاقات). */
function makeReceiptSerial(): string {
  const t = Date.now().toString(36).toUpperCase();
  const r = Math.floor(Math.random() * 46656)
    .toString(36)
    .toUpperCase()
    .padStart(3, "0");
  return `DN-${t}${r}`;
}

/** يحذف عروض الفئة غير الموجودة في آخر استجابة من فايزر. */
async function deleteStaleCategoryOffers(
  categoryId: string,
  liveIds: Set<string>
): Promise<number> {
  const existing = await db
    .collection("fazer_offers")
    .where("categoryId", "==", categoryId)
    .get();
  let deleted = 0;
  let batch = db.batch();
  let ops = 0;
  for (const doc of existing.docs) {
    if (liveIds.has(doc.id)) continue;
    batch.delete(doc.ref);
    deleted++;
    ops++;
    if (ops >= 400) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
  return deleted;
}

async function requireAdmin(uid: string): Promise<void> {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists || snap.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "يتطلب صلاحية أدمن");
  }
}

async function requireAdminOrActiveShop(uid: string): Promise<void> {
  const snap = await db.collection("users").doc(uid).get();
  const data = snap.data();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "الحساب غير موجود");
  }
  if (data?.role === "admin") return;
  if (
    data?.role === "shop" &&
    data?.status !== "suspended" &&
    data?.status !== "rejected"
  ) {
    return;
  }
  throw new HttpsError("permission-denied", "غير مخوّل");
}

const DEFAULT_GAME_KEY_IQD_RATE = 1470;

async function gameKeySaleRate(): Promise<number> {
  const snap = await db.collection("app_settings").doc("main").get();
  const n = Number(snap.data()?.gameKeySaleRate);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_GAME_KEY_IQD_RATE;
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
    throw new HttpsError("permission-denied", "الحساب غير مخوّل للشراء");
  }
  return {ref: snap.ref, data: data!};
}

async function fazerFetch(
  apiKey: string,
  path: string,
  init?: {
    method?: string;
    body?: unknown;
    idempotencyKey?: string;
  }
): Promise<JsonMap> {
  const headers: Record<string, string> = {
    "X-API-Key": apiKey,
    Accept: "application/json",
  };
  if (init?.body !== undefined) {
    headers["Content-Type"] = "application/json";
  }
  if (init?.idempotencyKey) {
    headers["Idempotency-Key"] = init.idempotencyKey;
  }

  const res = await fetch(`${FAZER_BASE}${path}`, {
    method: init?.method ?? "GET",
    headers,
    body: init?.body !== undefined ? JSON.stringify(init.body) : undefined,
  });

  let json: JsonMap = {};
  try {
    json = (await res.json()) as JsonMap;
  } catch {
    json = {};
  }

  if (!res.ok || json.ok === false) {
    const message =
      String(json.error ?? json.message ?? "").trim() ||
      `تعذر تنفيذ الطلب (${res.status})`;
    throw new HttpsError(
      res.status === 401 || res.status === 403
        ? "permission-denied"
        : res.status === 404
          ? "not-found"
          : "failed-precondition",
      message
    );
  }
  return json;
}

function asString(value: unknown): string {
  return value == null ? "" : String(value);
}

function asNumber(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function steamCoverUrl(appid: unknown): string {
  const id = Math.floor(asNumber(appid));
  if (id <= 0) return "";
  return `https://cdn.cloudflare.steamstatic.com/steam/apps/${id}/library_600x900.jpg`;
}

function extractImageUrl(item: JsonMap): string {
  const direct =
    asString(item.imageurl) ||
    asString(item.imageUrl) ||
    asString(item.image_url) ||
    asString(item.cover);
  if (direct && direct !== "null") return direct;
  return steamCoverUrl(item.appid);
}

function extractCodes(order: JsonMap): string[] {
  const cards = order.cards;
  if (Array.isArray(cards)) {
    return cards
      .map((c) => {
        if (typeof c === "string") return c.trim();
        if (c && typeof c === "object") {
          const m = c as JsonMap;
          return (
            asString(m.code) ||
            asString(m.card) ||
            asString(m.pin) ||
            asString(m.value)
          ).trim();
        }
        return "";
      })
      .filter((c) => c.length > 0);
  }
  const keys = order.keys;
  if (Array.isArray(keys)) {
    return keys
      .map((k) => {
        if (typeof k === "string") return k.trim();
        if (k && typeof k === "object") {
          const m = k as JsonMap;
          return (
            asString(m.key) ||
            asString(m.code) ||
            asString(m.value)
          ).trim();
        }
        return "";
      })
      .filter((k) => k.length > 0);
  }
  const single = asString(order.code || order.pin || order.key).trim();
  return single ? [single] : [];
}

function displayTitleOf(categoryName: string, offerName: string): string {
  const cat = categoryName.trim();
  const n = offerName.trim();
  if (cat && n && !n.toLowerCase().includes(cat.toLowerCase())) {
    return `${cat} ${n}`;
  }
  return n || cat;
}

async function commitCategoryPages(params: {
  apiKey: string;
  pathBase: string;
  kind: string;
  idField: string;
  maxPages?: number;
}): Promise<{synced: number; pages: number}> {
  let cursor: string | null = null;
  let synced = 0;
  let pages = 0;
  do {
    const q = new URLSearchParams({limit: "50", include_ui: "1"});
    if (cursor) q.set("cursor", cursor);
    const data = await fazerFetch(
      params.apiKey,
      `${params.pathBase}?${q.toString()}`
    );
    const items = Array.isArray(data.items) ? (data.items as JsonMap[]) : [];
    const batch = db.batch();
    for (const item of items) {
      const categoryId = asString(item[params.idField]).trim();
      if (!categoryId) continue;
      const categoryName = asString(item.name) || asString(item.GameName);
      // حجب فئات الكربتو (Binance) عن الظهور في التطبيق.
      if (isBlockedCryptoCategory(categoryId, categoryName)) continue;
      const ref = db.collection("fazer_categories").doc(categoryId);
      batch.set(
        ref,
        {
          categoryId,
          name: categoryName,
          note: [
            asString(item.note),
            asString(item.region) ? `Region: ${asString(item.region)}` : "",
            asString(item.platform) ? `Platform: ${asString(item.platform)}` : "",
          ]
            .filter(Boolean)
            .join("\n"),
          imageUrl: extractImageUrl(item),
          kind: params.kind,
          region: asString(item.region),
          platform: asString(item.platform),
          appid: Math.floor(asNumber(item.appid)) || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      synced++;
    }
    await batch.commit();
    pages++;
    const meta = (data.meta as JsonMap) ?? {};
    cursor = meta.has_more ? asString(meta.next_cursor) || null : null;
    if (pages > (params.maxPages ?? 40)) break;
  } while (cursor);
  return {synced, pages};
}

/** يربط فئات الشحن بالـ ID بحقول التحقق (validate-id) من فايزر. */
async function linkTopupValidateFields(apiKey: string): Promise<void> {
  try {
    const validateData = await fazerFetch(apiKey, "/topups/validate-id");
    const items = Array.isArray(validateData.items)
      ? (validateData.items as JsonMap[])
      : [];
    const byName = new Map<string, JsonMap>();
    for (const item of items) {
      const name = asString(item.name).trim().toLowerCase();
      if (name) byName.set(name, item);
    }
    if (byName.size === 0) return;
    const cats = await db
      .collection("fazer_categories")
      .where("kind", "==", "topup")
      .get();
    let batch = db.batch();
    let ops = 0;
    for (const doc of cats.docs) {
      const name = asString(doc.data().name).trim().toLowerCase();
      const match = byName.get(name);
      if (!match) continue;
      const fields = Array.isArray(match.fields)
        ? (match.fields as JsonMap[]).map((f) => ({
            key: asString(f.key),
            label: asString(f.label) || asString(f.key),
            type: asString(f.type) || "text",
          }))
        : [];
      batch.set(
        doc.ref,
        {
          validateCategoryId: asString(match.category_id) || doc.id,
          validateFields: fields,
          supportsValidateId: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
  } catch {
    // التحقق اختياري — المزامنة الأساسية نجحت.
  }
}

/** مزامنة كتالوج تليجرام (Stars + Premium) — منطق مشترك. */
async function syncTelegramCatalogCore(
  apiKey: string
): Promise<{synced: number; deleted: number}> {
  const stars = await fazerFetch(apiKey, "/telegram/stars");
  const premium = await fazerFetch(apiKey, "/telegram/premium");
  const pricePerStar = asNumber(stars.price_per_star);
  const minAmount = Math.max(50, Math.floor(asNumber(stars.min_amount) || 50));
  const maxAmount = Math.max(
    minAmount,
    Math.floor(asNumber(stars.max_amount) || 10000)
  );

  await db.collection("fazer_categories").doc("telegram_stars").set(
    {
      categoryId: "telegram_stars",
      name: "Telegram Stars",
      note: "شحن نجوم تيليجرام لحساب المستخدم",
      imageUrl: "",
      kind: "telegram_stars",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
  await db.collection("fazer_categories").doc("telegram_premium").set(
    {
      categoryId: "telegram_premium",
      name: "Telegram Premium",
      note: "اشتراك تيليجرام بريميوم (3 / 6 / 12 شهر)",
      imageUrl: "",
      kind: "telegram_premium",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );

  const starPacks = [50, 100, 250, 500, 1000, 2500, 5000].filter(
    (n) => n >= minAmount && n <= maxAmount
  );
  const batch = db.batch();
  let synced = 0;
  const liveStarIds = new Set<string>();
  for (const amount of starPacks) {
    const id = offerDocId("telegram_stars", String(amount));
    liveStarIds.add(id);
    batch.set(
      db.collection("fazer_offers").doc(id),
      {
        id,
        categoryId: "telegram_stars",
        cardId: String(amount),
        categoryName: "Telegram Stars",
        name: `${amount} Stars`,
        priceUsd: Number((pricePerStar * amount).toFixed(4)),
        stock: 9999,
        minOrderQuantity: 1,
        maxOrderQuantity: 1,
        imageUrl: "",
        kind: "telegram_stars",
        telegramQuantity: amount,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    synced++;
  }

  const plans = Array.isArray(premium.plans)
    ? (premium.plans as JsonMap[])
    : [];
  const livePremiumIds = new Set<string>();
  for (const plan of plans) {
    const months = Math.floor(asNumber(plan.months));
    if (![3, 6, 12].includes(months)) continue;
    const id = offerDocId("telegram_premium", String(months));
    livePremiumIds.add(id);
    batch.set(
      db.collection("fazer_offers").doc(id),
      {
        id,
        categoryId: "telegram_premium",
        cardId: String(months),
        categoryName: "Telegram Premium",
        name: `${months} شهر`,
        priceUsd: asNumber(plan.price_usd),
        stock: 9999,
        minOrderQuantity: 1,
        maxOrderQuantity: 1,
        imageUrl: "",
        kind: "telegram_premium",
        telegramMonths: months,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    synced++;
  }
  await batch.commit();
  const deletedStars = await deleteStaleCategoryOffers(
    "telegram_stars",
    liveStarIds
  );
  const deletedPremium = await deleteStaleCategoryOffers(
    "telegram_premium",
    livePremiumIds
  );
  return {synced, deleted: deletedStars + deletedPremium};
}

/** مزامنة عروض فئة واحدة — منطق مشترك (يحافظ على سعر كشك ويحذف العروض الغائبة). */
async function syncCategoryOffersCore(
  apiKey: string,
  categoryId: string,
  catData: JsonMap
): Promise<{
  categoryName: string;
  kind: string;
  synced: number;
  deleted: number;
  buyerFields: Array<Record<string, unknown>>;
}> {
  const kind = asString(catData?.kind) || "gift_card";
  const path =
    kind === "game_key"
      ? `/gamekeys/keys?game_id=${encodeURIComponent(categoryId)}`
      : kind === "topup"
        ? `/topups/offers?category_id=${encodeURIComponent(categoryId)}`
        : `/giftcards/cards?category_id=${encodeURIComponent(categoryId)}`;
  const data = await fazerFetch(apiKey, path);
  const categoryName =
    asString(data.name) || asString(catData?.name) || categoryId;
  const offers = Array.isArray(data.offers)
    ? (data.offers as JsonMap[])
    : Array.isArray(data.keys)
      ? (data.keys as JsonMap[])
      : Array.isArray(data.items)
        ? (data.items as JsonMap[])
        : [];

  const imageUrl = extractImageUrl(data) || asString(catData?.imageUrl);

  const buyerFields = Array.isArray(data.fields)
    ? (data.fields as JsonMap[]).map((f) => ({
        key: asString(f.key),
        label: asString(f.label) || asString(f.key),
        type: asString(f.type) || "text",
        options: Array.isArray(f.options)
          ? (f.options as JsonMap[]).map((o) => ({
              value: asString(o.value) || asString(o.id) || asString(o.key),
              label: asString(o.label) || asString(o.value) || asString(o.id),
            })).filter((o) => o.value)
          : [],
      }))
    : [];

  if (kind === "topup" && buyerFields.length > 0) {
    await db.collection("fazer_categories").doc(categoryId).set(
      {
        buyerFields,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  }

  const batch = db.batch();
  let synced = 0;
  const liveIds = new Set<string>();
  for (const offer of offers) {
    const cardId = (
      asString(offer.card_id) ||
      asString(offer.key_id) ||
      asString(offer.offer_id) ||
      asString(offer.id)
    ).trim();
    if (!cardId) continue;
    const id = offerDocId(categoryId, cardId);
    liveIds.add(id);
    const ref = db.collection("fazer_offers").doc(id);
    batch.set(
      ref,
      {
        id,
        categoryId,
        cardId,
        categoryName,
        name: asString(offer.name) || asString(offer.title) || cardId,
        priceUsd: asNumber(offer.price_usd ?? offer.price),
        stock: asNumber(offer.stock) || (kind === "topup" ? 9999 : 0),
        minOrderQuantity: asNumber(offer.min_order_quantity) || 1,
        maxOrderQuantity: asNumber(offer.max_order_quantity) || 1,
        imageUrl: extractImageUrl(offer) || imageUrl,
        kind,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    synced++;
  }
  await batch.commit();
  const deleted = await deleteStaleCategoryOffers(categoryId, liveIds);
  return {categoryName, kind, synced, deleted, buyerFields};
}

type FazerOrderState = "completed" | "failed" | "pending";

const FAZER_FAILED_STATES = new Set([
  "failed",
  "refund",
  "refunded",
  "canceled",
  "cancelled",
  "rejected",
]);

/** يقرأ حالة الطلب من فايزر ويصنّفها: مكتمل / فاشل / قيد التنفيذ. */
function classifyFazerOrder(
  order: JsonMap,
  requireCodes: boolean
): FazerOrderState {
  const status = asString(order.status).toLowerCase();
  if (status === "completed") {
    if (!requireCodes || extractCodes(order).length > 0) return "completed";
    return "pending";
  }
  if (FAZER_FAILED_STATES.has(status)) return "failed";
  return "pending";
}

/**
 * يتابع الطلب حتى يُحسم أو تنتهي المدة، دون رمي استثناء.
 * "pending" تعني غير محسوم: يُمنع إرجاع الرصيد لأن فايزر قد يكمل الشحن لاحقاً.
 */
async function waitForFazerOrder(
  apiKey: string,
  orderId: string,
  options?: {timeoutMs?: number; requireCodes?: boolean}
): Promise<{order: JsonMap; state: FazerOrderState}> {
  const timeoutMs = options?.timeoutMs ?? 45000;
  const requireCodes = options?.requireCodes === true;
  const started = Date.now();
  let last: JsonMap = {};
  do {
    try {
      const data = await fazerFetch(
        apiKey,
        `/orders/${encodeURIComponent(orderId)}`
      );
      const order = (data.order as JsonMap) ?? data;
      last = order;
      const state = classifyFazerOrder(order, requireCodes);
      if (state !== "pending") return {order, state};
    } catch {
      // خطأ شبكة أو مؤقت: لا يُعتبر فشلاً في الشحن.
    }
    await new Promise((r) => setTimeout(r, 2000));
  } while (Date.now() - started < timeoutMs);
  return {order: last, state: "pending"};
}

/** يخصم مبلغ الطلب من المحفظة مرة واحدة فقط (يرمي عند عدم كفاية الرصيد). */
async function chargeFazerOrder(
  orderRef: admin.firestore.DocumentReference,
  uid: string,
  amount: number,
  labels: {reason: string; companyName: string}
): Promise<void> {
  const shopRef = db.collection("users").doc(uid);
  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (orderSnap.data()?.walletCharged === true) return;
    const shopSnap = await tx.get(shopRef);
    const balance = asNumber(shopSnap.data()?.walletBalance);
    if (balance < amount) {
      throw new HttpsError("failed-precondition", "رصيد المحفظة غير كافٍ");
    }
    const after = balance - amount;
    const txRef = db.collection("wallet_transactions").doc();
    tx.update(shopRef, {walletBalance: after});
    tx.set(txRef, {
      userId: uid,
      type: "debit",
      amount,
      balanceAfter: after,
      reason: labels.reason,
      orderId: orderRef.id,
      companyName: labels.companyName,
      visibleToUser: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(
      orderRef,
      {
        walletCharged: true,
        walletTransactionId: txRef.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  });
}

/** يرجّع مبلغ الطلب إلى المحفظة مرة واحدة فقط عند رفض فايزر للطلب. */
async function refundFazerOrder(
  orderRef: admin.firestore.DocumentReference,
  reason: string
): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    const data = orderSnap.data();
    if (!data) return false;
    if (data.walletCharged !== true) return false;
    if (asString(data.fazerRefundTransactionId)) return false;
    const uid = asString(data.shopId);
    const amount = asNumber(data.total);
    if (!uid || amount <= 0) return false;

    const shopRef = db.collection("users").doc(uid);
    const shopSnap = await tx.get(shopRef);
    const after = asNumber(shopSnap.data()?.walletBalance) + amount;
    const txRef = db.collection("wallet_transactions").doc();
    tx.update(shopRef, {walletBalance: after});
    tx.set(txRef, {
      userId: uid,
      type: "credit",
      amount,
      balanceAfter: after,
      reason: `إرجاع مبلغ طلب غير منفَّذ: ${asString(data.productName)}`,
      orderId: orderRef.id,
      companyName: asString(data.companyName),
      visibleToUser: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(
      orderRef,
      {
        walletCharged: false,
        fazerRefundTransactionId: txRef.id,
        fazerRefundReason: reason,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    return true;
  });
}

/** رصيد حساب فايزر (أدمن فقط). */
export const fazerGetBalance = onCall(
  {secrets: [fazerApiKey], timeoutSeconds: 30},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);
    const data = await fazerFetch(fazerApiKey.value(), "/balance");
    return {
      ok: true,
      balance: asString(data.balance),
      currency: asString(data.currency) || "USD",
    };
  }
);

/** مزامنة فئات بطاقات الهدايا من فايزر إلى Firestore. */
export const fazerSyncGiftCategories = onCall(
  {secrets: [fazerApiKey], timeoutSeconds: 300},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);
    const result = await commitCategoryPages({
      apiKey: fazerApiKey.value(),
      pathBase: "/giftcards",
      kind: "gift_card",
      idField: "category_id",
    });
    return {ok: true, ...result};
  }
);

/** مزامنة فئات مفاتيح الألعاب من فايزر. */
export const fazerSyncGameKeyCategories = onCall(
  {secrets: [fazerApiKey], timeoutSeconds: 300},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    await requireAdminOrActiveShop(request.auth.uid);
    const result = await commitCategoryPages({
      apiKey: fazerApiKey.value(),
      pathBase: "/gamekeys",
      kind: "game_key",
      idField: "game_id",
    });
    return {ok: true, ...result};
  }
);

/** مزامنة فئات الشحن بالـ ID من فايزر. */
export const fazerSyncTopupCategories = onCall(
  {secrets: [fazerApiKey], timeoutSeconds: 300},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    await requireAdminOrActiveShop(request.auth.uid);
    const apiKey = fazerApiKey.value();
    const result = await commitCategoryPages({
      apiKey,
      pathBase: "/topups",
      kind: "topup",
      idField: "category_id",
    });

    // ربط فئات التحقق من الـ ID (إن وُجدت) بأسماء الألعاب.
    await linkTopupValidateFields(apiKey);

    return {ok: true, ...result};
  }
);

/** مزامنة كتالوج تليجرام (Stars + Premium). */
export const fazerSyncTelegramCatalog = onCall(
  {secrets: [fazerApiKey], timeoutSeconds: 60},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);
    const apiKey = fazerApiKey.value();
    const result = await syncTelegramCatalogCore(apiKey);
    return {ok: true, ...result};
  }
);

/** مزامنة عروض فئة واحدة مع الحفاظ على سعر كشك الحالي، وحذف العروض الغائبة عن فايزر. */
export const fazerSyncCategoryOffers = onCall(
  {secrets: [fazerApiKey], timeoutSeconds: 120},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const categoryId = asString(request.data?.categoryId).trim();
    if (!categoryId) {
      throw new HttpsError("invalid-argument", "معرّف الفئة مطلوب");
    }

    const catSnap = await db.collection("fazer_categories").doc(categoryId).get();
    if (!catSnap.exists) {
      throw new HttpsError("not-found", "الفئة غير موجودة — زامن الكتالوج أولاً");
    }
    const kind = asString(catSnap.data()?.kind) || "gift_card";
    await requireAdminOrActiveShop(request.auth.uid);
    if (isBlockedCryptoCategory(categoryId, asString(catSnap.data()?.name))) {
      throw new HttpsError(
        "failed-precondition",
        "هذه الفئة غير متاحة"
      );
    }
    if (kind === "telegram_stars" || kind === "telegram_premium") {
      throw new HttpsError(
        "failed-precondition",
        "فئات تليجرام تُزامن عبر زر مزامنة تليجرام"
      );
    }

    const apiKey = fazerApiKey.value();
    const result = await syncCategoryOffersCore(
      apiKey,
      categoryId,
      catSnap.data() as JsonMap
    );
    return {ok: true, categoryId, ...result};
  }
);

/** التحقق من معرّف اللاعب قبل الشحن. */
export const fazerValidateTopupId = onCall(
  {secrets: [fazerApiKey], timeoutSeconds: 30},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    await requireAdminOrActiveShop(request.auth.uid);
    const categoryId = asString(request.data?.categoryId).trim();
    const fieldsRaw = request.data?.fields;
    if (!categoryId) {
      throw new HttpsError("invalid-argument", "معرّف الفئة مطلوب");
    }
    if (!fieldsRaw || typeof fieldsRaw !== "object") {
      throw new HttpsError("invalid-argument", "حقول اللاعب مطلوبة");
    }
    const fields: Record<string, string> = {};
    for (const [key, value] of Object.entries(fieldsRaw as Record<string, unknown>)) {
      const v = asString(value).trim();
      if (v) fields[key] = v;
    }
    if (Object.keys(fields).length < 1) {
      throw new HttpsError("invalid-argument", "أدخل بيانات اللاعب");
    }

    const catSnap = await db.collection("fazer_categories").doc(categoryId).get();
    const validateCategoryId =
      asString(catSnap.data()?.validateCategoryId).trim() || categoryId;

    const data = await fazerFetch(fazerApiKey.value(), "/topups/validate-id", {
      method: "POST",
      body: {category_id: validateCategoryId, fields},
    });
    return {
      ok: true,
      valid: data.valid === true,
      playerName: asString(data.player_name),
      region: asString(data.region),
      categoryId: asString(data.category_id) || validateCategoryId,
    };
  }
);

/** تعيين سعر كشك للعرض (0 أو فارغ = لا يظهر للمستخدم). */
export const fazerSetOfferKushkPrice = onCall(
  {timeoutSeconds: 30},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);
    const offerId = asString(request.data?.offerId).trim();
    const raw = request.data?.kushkPrice;
    if (!offerId) {
      throw new HttpsError("invalid-argument", "معرّف العرض مطلوب");
    }

    const ref = db.collection("fazer_offers").doc(offerId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "العرض غير موجود — زامن الفئة أولاً");
    }

    if (raw === null || raw === undefined || raw === "") {
      await ref.update({
        kushkPrice: admin.firestore.FieldValue.delete(),
        pricedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {ok: true, offerId, kushkPrice: null};
    }

    const price = Number(raw);
    if (!Number.isFinite(price) || price < 0) {
      throw new HttpsError("invalid-argument", "سعر كشك غير صالح");
    }
    if (price === 0) {
      await ref.update({
        kushkPrice: admin.firestore.FieldValue.delete(),
        pricedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {ok: true, offerId, kushkPrice: null};
    }

    await ref.update({
      kushkPrice: price,
      pricedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {ok: true, offerId, kushkPrice: price};
  }
);

/**
 * شراء عرض فايزر (بطاقة / مفتاح لعبة / تليجرام / شحن):
 * 1) التحقق من السعر والرصيد
 * 2) خصم المحفظة فوراً
 * 3) الطلب من فايزر
 * 4) إكمال الطلب أو إبقاءه قيد المراجعة مع إرجاع الرصيد فقط عند رفض فايزر
 */
export const fazerPurchaseGiftCard = onCall(
  {secrets: [fazerApiKey], timeoutSeconds: 120},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const uid = request.auth.uid;
    await requireActiveShop(uid);
    await assertRateLimit(
      clientRateKey("fazer_purchase", request, uid),
      40,
      60 * 1000,
    );

    const purchasePin =
      request.data?.pin != null ? String(request.data.pin) : undefined;
    await verifyPurchasePin(db, uid, purchasePin);

    const offerId = asString(request.data?.offerId).trim();
    const quantity = Math.max(1, Math.floor(Number(request.data?.quantity) || 1));
    const telegramUsernameRaw = asString(request.data?.telegramUsername)
      .trim()
      .replace(/^@+/, "");
    const telegramUsername = telegramUsernameRaw
      ? `@${telegramUsernameRaw}`
      : "";
    const topupFieldsRaw = request.data?.fields;
    const topupFields: Record<string, string> = {};
    if (topupFieldsRaw && typeof topupFieldsRaw === "object") {
      for (const [key, value] of Object.entries(
        topupFieldsRaw as Record<string, unknown>
      )) {
        const v = asString(value).trim();
        if (v) topupFields[key] = v;
      }
    }
    if (!offerId) {
      throw new HttpsError("invalid-argument", "معرّف العرض مطلوب");
    }

    const offerRef = db.collection("fazer_offers").doc(offerId);
    const offerSnap = await offerRef.get();
    if (!offerSnap.exists) {
      throw new HttpsError("not-found", "العرض غير متوفر");
    }
    const offer = offerSnap.data()!;
    const kind = asString(offer.kind) || "gift_card";
    const isTopup = kind === "topup";
    const isGameKey = kind === "game_key";
    const isTelegram =
      kind === "telegram_stars" || kind === "telegram_premium";
    // بطاقات الهدايا/تيليجرام: kushkPrice > 0 يعني مفعّلة للعرض فقط (ليس سعر البيع).
    const listedPrice = Number(offer.kushkPrice);
    const requiresListing = !isTopup && !isGameKey;
    if (
      requiresListing &&
      !(Number.isFinite(listedPrice) && listedPrice > 0)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "هذا العرض غير مسعّر للبيع"
      );
    }
    // كل عروض فايزر: دولار × سعر البيع من الإعدادات.
    const kushkPrice = Math.round(
      asNumber(offer.priceUsd) * (await gameKeySaleRate())
    );
    if (!Number.isFinite(kushkPrice) || kushkPrice <= 0) {
      throw new HttpsError(
        "failed-precondition",
        isGameKey
          ? "سعر مفتاح اللعبة غير صالح"
          : isTopup
            ? "سعر الشحن غير صالح"
            : "سعر البطاقة غير صالح"
      );
    }
    if (isTelegram) {
      if (!telegramUsernameRaw || telegramUsernameRaw.length < 3) {
        throw new HttpsError(
          "invalid-argument",
          "يلزم إدخال يوزرنيم تيليجرام صالح"
        );
      }
      if (quantity !== 1) {
        throw new HttpsError(
          "invalid-argument",
          "كمية تليجرام يجب أن تكون 1"
        );
      }
    }
    if (isTopup) {
      if (Object.keys(topupFields).length < 1) {
        throw new HttpsError(
          "invalid-argument",
          "يلزم إدخال معرّف اللاعب / بيانات الشحن"
        );
      }
      if (quantity !== 1) {
        throw new HttpsError(
          "invalid-argument",
          "كمية الشحن يجب أن تكون 1"
        );
      }
    }

    const categoryId = asString(offer.categoryId);
    const cardId = asString(offer.cardId);
    // حجب شراء فئات الكربتو (Binance) حتى لو وصل الطلب بطريقة ما.
    if (isBlockedCryptoCategory(categoryId, asString(offer.categoryName))) {
      throw new HttpsError("failed-precondition", "هذا المنتج غير متاح");
    }
    const chargedTotal = kushkPrice * quantity;

    const shopRef = db.collection("users").doc(uid);
    const shopSnap = await shopRef.get();
    const balance = Number(shopSnap.data()?.walletBalance ?? 0);
    if (balance < chargedTotal) {
      throw new HttpsError("failed-precondition", "رصيد المحفظة غير كافٍ");
    }

    const categoryName = asString(offer.categoryName);
    const offerName = asString(offer.name);
    const displayTitle = displayTitleOf(categoryName, offerName);

    const orderRef = db.collection("orders").doc();
    const idempotencyKey = `kushk-${orderRef.id}`;

    await orderRef.set({
      shopId: uid,
      productId: offerId,
      productName: displayTitle,
      companyName: categoryName || (isTopup ? "شحن بالاي دي" : "جميع البطاقات"),
      quantity,
      unitPrice: kushkPrice,
      total: chargedTotal,
      cardItems: [],
      cardCodes: [],
      paymentMethod: "wallet",
      status: "ordering",
      source: "fazer",
      fazerKind: kind,
      fazerCategoryId: categoryId,
      fazerCardId: cardId,
      fazerPriceUsd: Number(offer.priceUsd) || 0,
      telegramUsername: isTelegram ? telegramUsername : null,
      topupFields: isTopup ? topupFields : null,
      idempotencyKey,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      printed: false,
      printCount: 0,
      walletCharged: false,
      fazerFinal: false,
      fazerNeedsCheck: false,
    });

    // الخصم قبل الطلب: يمنع شحن اللعبة بدون استقطاع، ويُرجَع فوراً إن رفض فايزر.
    await chargeFazerOrder(orderRef, uid, chargedTotal, {
      reason: `شراء: ${displayTitle}`,
      companyName: categoryName,
    });

    const apiKey = fazerApiKey.value();
    let createdOrder: JsonMap;
    let fazerOrderId = "";
    try {
      let orderPath = "/giftcards/order";
      let body: JsonMap = {category_id: categoryId, card_id: cardId, quantity};
      if (kind === "game_key") {
        orderPath = "/gamekeys/order";
        body = {game_id: categoryId, key_id: cardId, quantity};
      } else if (kind === "topup") {
        orderPath = "/topups/order";
        body = {
          category_id: categoryId,
          offer_id: cardId,
          fields: topupFields,
        };
      } else if (kind === "telegram_stars") {
        orderPath = "/telegram/stars/buy";
        const quantityStars =
          Math.floor(asNumber(offer.telegramQuantity)) ||
          Math.floor(Number(cardId)) ||
          0;
        body = {
          telegram_username: telegramUsername,
          quantity: quantityStars,
        };
      } else if (kind === "telegram_premium") {
        orderPath = "/telegram/premium/buy";
        const months =
          Math.floor(asNumber(offer.telegramMonths)) ||
          Math.floor(Number(cardId)) ||
          0;
        body = {telegram_username: telegramUsername, months};
      }

      const created = await fazerFetch(apiKey, orderPath, {
        method: "POST",
        idempotencyKey,
        body,
      });
      createdOrder = (created.order as JsonMap) ?? created;
      fazerOrderId = asString(createdOrder.id);
      if (!fazerOrderId) {
        throw new HttpsError("internal", "تعذر إنشاء الطلب");
      }
      await orderRef.set(
        {
          fazerOrderId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    } catch (error) {
      const message =
        error instanceof Error ? error.message : String(error);
      // رفض صريح من فايزر → إرجاع. خطأ شبكة/غير محسوم → الخصم يبقى والمصالحة تعيد المحاولة بمفتاح التكرار.
      if (error instanceof HttpsError) {
        await refundFazerOrder(orderRef, message);
        await orderRef.set(
          {
            status: "failed",
            error: "تعذر تنفيذ الطلب — تم إرجاع المبلغ",
            adminError: message,
            fazerFinal: true,
            fazerNeedsCheck: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
        throw new HttpsError(
          error.code,
          "تعذر تنفيذ الطلب حالياً، وتم إرجاع المبلغ إلى محفظتك"
        );
      }
      await orderRef.set(
        {
          status: "processing",
          error: "الطلب قيد التنفيذ",
          adminError: message,
          fazerFinal: false,
          fazerNeedsCheck: true,
          idempotencyKey,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      const pendingSnap = await orderRef.get();
      return {
        ok: true,
        pending: true,
        orderId: orderRef.id,
        order: pendingSnap.data(),
      };
    }

    const requireCodes = !isTelegram && !isTopup;
    let state = classifyFazerOrder(createdOrder, requireCodes);
    let fazerOrder = createdOrder;
    if (state === "pending") {
      const waited = await waitForFazerOrder(apiKey, fazerOrderId, {
        timeoutMs: 45000,
        requireCodes,
      });
      fazerOrder = waited.order;
      state = waited.state;
    }
    fazerOrder.id = fazerOrderId;

    if (state === "failed") {
      const st = asString(fazerOrder.status) || "failed";
      await refundFazerOrder(orderRef, `فشل تنفيذ الطلب (${st})`);
      await orderRef.set(
        {
          status: "failed",
          fazerOrderId,
          error: "تعذر تنفيذ الطلب — تم إرجاع المبلغ",
          adminError: `فشل تنفيذ الطلب (${st})`,
          fazerFinal: true,
          fazerNeedsCheck: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      throw new HttpsError(
        "failed-precondition",
        "تعذر تنفيذ الطلب حالياً، وتم إرجاع المبلغ إلى محفظتك"
      );
    }

    let codes = extractCodes(fazerOrder);
    if (codes.length < 1 && isTelegram && state === "completed") {
      codes = [
        kind === "telegram_stars"
          ? `تم شحن Stars إلى ${telegramUsername}`
          : `تم تفعيل Premium لـ ${telegramUsername}`,
      ];
    }
    if (codes.length < 1 && isTopup && state === "completed") {
      const playerLabel =
        Object.values(topupFields).filter(Boolean).join(" / ") || "اللاعب";
      codes = [`تم شحن ${offerName || displayTitle} إلى ${playerLabel}`];
    }

    if (state === "completed" && codes.length > 0) {
      const serial = makeReceiptSerial();
      const cardItems = codes.map((code) => ({
        code,
        serialNumber: serial,
      }));
      await orderRef.set(
        {
          status: "completed",
          cardItems,
          cardCodes: codes,
          fazerOrderId,
          fazerFinal: true,
          fazerNeedsCheck: false,
          error: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      const finalSnap = await orderRef.get();
      return {ok: true, orderId: orderRef.id, order: finalSnap.data()};
    }

    // فايزر قبل الطلب لكن النتيجة لم تُحسم بعد: الخصم باقٍ، والمصالحة تكمل لاحقاً.
    const pendingCodes = isTopup
      ? [
          `جاري شحن ${offerName || displayTitle} — سيُحدَّث الطلب تلقائياً`,
        ]
      : isTelegram
        ? [
            `جاري تنفيذ طلب تيليجرام لـ ${telegramUsername} — سيُحدَّث تلقائياً`,
          ]
        : [
            "الطلب قيد التنفيذ — سيظهر الرمز تلقائياً عند الاكتمال",
          ];
    const serial = makeReceiptSerial();
    const pendingItems = pendingCodes.map((code) => ({
      code,
      serialNumber: serial,
    }));
    await orderRef.set(
      {
        status: "processing",
        cardItems: pendingItems,
        cardCodes: pendingCodes,
        fazerOrderId,
        fazerFinal: false,
        fazerNeedsCheck: true,
        error: "الطلب قيد التنفيذ",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    const pendingSnap = await orderRef.get();
    return {
      ok: true,
      pending: true,
      orderId: orderRef.id,
      order: pendingSnap.data(),
    };
  }
);

/** يبني رموز الإيصال النهائية حسب نوع الطلب. */
function buildFazerReceiptCodes(
  orderData: admin.firestore.DocumentData,
  fazerOrder: JsonMap,
  state: FazerOrderState
): string[] {
  let codes = extractCodes(fazerOrder);
  if (codes.length > 0 || state !== "completed") return codes;

  const kind = asString(orderData.fazerKind);
  if (kind === "telegram_stars" || kind === "telegram_premium") {
    const user = asString(orderData.telegramUsername) || "المستخدم";
    return [
      kind === "telegram_stars"
        ? `تم شحن Stars إلى ${user}`
        : `تم تفعيل Premium لـ ${user}`,
    ];
  }
  if (kind === "topup") {
    const fields = (orderData.topupFields as Record<string, string>) || {};
    const playerLabel =
      Object.values(fields).filter(Boolean).join(" / ") || "اللاعب";
    const title =
      asString(orderData.productName) || asString(orderData.companyName);
    return [`تم شحن ${title} إلى ${playerLabel}`];
  }
  return codes;
}

/**
 * يصالح طلباً واحداً من فايزر:
 * - مكتمل: يكمل الطلب ويخصم إن لم يُخصم سابقاً (طلبات قديمة)
 * - فاشل: يرجّع الرصيد إن كان مخصوماً
 * - معلّق: يتركه للمراجعة التالية
 */
async function reconcileOneFazerOrder(
  apiKey: string,
  orderRef: admin.firestore.DocumentReference,
  orderData: admin.firestore.DocumentData
): Promise<"completed" | "failed" | "pending" | "skipped"> {
  if (orderData.fazerFinal === true) return "skipped";
  let fazerOrderId = asString(orderData.fazerOrderId);
  const kind = asString(orderData.fazerKind);
  const requireCodes =
    kind !== "topup" &&
    kind !== "telegram_stars" &&
    kind !== "telegram_premium";

  // طلب مخصوم بلا رقم فايزر: أعد الإرسال بنفس مفتاح التكرار لاسترجاع رقم الطلب.
  if (!fazerOrderId && orderData.walletCharged === true) {
    const idempotencyKey =
      asString(orderData.idempotencyKey) || `kushk-${orderRef.id}`;
    try {
      const categoryId = asString(orderData.fazerCategoryId);
      const cardId = asString(orderData.fazerCardId);
      const quantity = Math.max(1, Math.floor(asNumber(orderData.quantity) || 1));
      let orderPath = "/giftcards/order";
      let body: JsonMap = {
        category_id: categoryId,
        card_id: cardId,
        quantity,
      };
      if (kind === "game_key") {
        orderPath = "/gamekeys/order";
        body = {game_id: categoryId, key_id: cardId, quantity};
      } else if (kind === "topup") {
        orderPath = "/topups/order";
        body = {
          category_id: categoryId,
          offer_id: cardId,
          fields: (orderData.topupFields as Record<string, string>) || {},
        };
      } else if (kind === "telegram_stars") {
        orderPath = "/telegram/stars/buy";
        body = {
          telegram_username: asString(orderData.telegramUsername),
          quantity:
            Math.floor(Number(cardId)) ||
            Math.floor(asNumber(orderData.telegramQuantity)) ||
            0,
        };
      } else if (kind === "telegram_premium") {
        orderPath = "/telegram/premium/buy";
        body = {
          telegram_username: asString(orderData.telegramUsername),
          months:
            Math.floor(Number(cardId)) ||
            Math.floor(asNumber(orderData.telegramMonths)) ||
            0,
        };
      }
      const created = await fazerFetch(apiKey, orderPath, {
        method: "POST",
        idempotencyKey,
        body,
      });
      const createdOrder = (created.order as JsonMap) ?? created;
      fazerOrderId = asString(createdOrder.id);
      if (!fazerOrderId) return "pending";
      await orderRef.set(
        {
          fazerOrderId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      const stateNow = classifyFazerOrder(createdOrder, requireCodes);
      if (stateNow !== "pending") {
        orderData = {...orderData, fazerOrderId};
        // تابع المعالجة أدناه بنفس المسار.
      } else {
        orderData = {...orderData, fazerOrderId};
      }
    } catch (error) {
      if (error instanceof HttpsError) {
        const message = error.message;
        await refundFazerOrder(orderRef, message);
        await orderRef.set(
          {
            status: "failed",
            error: message,
            fazerFinal: true,
            fazerNeedsCheck: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
        return "failed";
      }
      return "pending";
    }
  }

  if (!fazerOrderId) return "skipped";

  let fazerOrder: JsonMap;
  try {
    const data = await fazerFetch(
      apiKey,
      `/orders/${encodeURIComponent(fazerOrderId)}`
    );
    fazerOrder = (data.order as JsonMap) ?? data;
  } catch {
    return "pending";
  }
  fazerOrder.id = fazerOrderId;
  const state = classifyFazerOrder(fazerOrder, requireCodes);

  if (state === "pending") {
    await orderRef.set(
      {
        status: "processing",
        fazerNeedsCheck: true,
        fazerFinal: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    return "pending";
  }

  if (state === "failed") {
    const st = asString(fazerOrder.status) || "failed";
    await refundFazerOrder(orderRef, `فشل تنفيذ الطلب (${st})`);
    await orderRef.set(
      {
        status: "failed",
        error: "تعذر تنفيذ الطلب — تم إرجاع المبلغ",
        adminError: `فشل تنفيذ الطلب (${st})`,
        fazerFinal: true,
        fazerNeedsCheck: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    return "failed";
  }

  const codes = buildFazerReceiptCodes(orderData, fazerOrder, state);
  if (codes.length < 1) {
    await orderRef.set(
      {
        status: "processing",
        fazerNeedsCheck: true,
        fazerFinal: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    return "pending";
  }

  const receiptSerial = makeReceiptSerial();
  const uid = asString(orderData.shopId);
  const amount = asNumber(orderData.total);
  // طلبات قديمة: شُحنت ولم تُخصم → نخصم الآن.
  if (orderData.walletCharged !== true && uid && amount > 0) {
    try {
      await chargeFazerOrder(orderRef, uid, amount, {
        reason: `شراء: ${asString(orderData.productName)}`,
        companyName: asString(orderData.companyName),
      });
    } catch (error) {
      await orderRef.set(
        {
          status: "needs_settlement",
          cardItems: codes.map((code) => ({
            code,
            serialNumber: receiptSerial,
          })),
          cardCodes: codes,
          fazerOrderId,
          error: "تعذر إكمال الطلب — راجع الإدارة",
          adminError: error instanceof Error ? error.message : String(error),
          fazerNeedsCheck: true,
          fazerFinal: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      return "pending";
    }
  }

  await orderRef.set(
    {
      status: "completed",
      cardItems: codes.map((code) => ({
        code,
        serialNumber: receiptSerial,
      })),
      cardCodes: codes,
      fazerOrderId,
      fazerFinal: true,
      fazerNeedsCheck: false,
      error: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
  return "completed";
}

/**
 * مصالحة دورية لطلبات فايزر المعلّقة والفاشلة القديمة التي لها رقم طلب.
 * تخصم الطلبات القديمة المكتملة إن لم تُخصم، وترجع الرصيد عند الفشل الحقيقي فقط.
 */
export const fazerReconcileOrders = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 2 minutes",
    timeoutSeconds: 300,
    secrets: [fazerApiKey],
  },
  async () => {
    const apiKey = fazerApiKey.value();
    const statuses = ["processing", "ordering", "failed", "needs_settlement"];
    const seen = new Set<string>();

    for (const status of statuses) {
      const snap = await db
        .collection("orders")
        .where("source", "==", "fazer")
        .where("status", "==", status)
        .limit(40)
        .get();
      for (const doc of snap.docs) {
        if (seen.has(doc.id)) continue;
        seen.add(doc.id);
        const data = doc.data();
        if (data.fazerFinal === true) continue;
        const hasFazerId = Boolean(asString(data.fazerOrderId));
        const canRetry =
          data.walletCharged === true && !hasFazerId;
        if (!hasFazerId && !canRetry) continue;
        // الطلبات الفاشلة القديمة بدون رقم فايزر لا تُمس؛ مع رقم فقط نراجعها.
        try {
          await reconcileOneFazerOrder(apiKey, doc.ref, data);
        } catch {
          // لا نوقف الحلقة بسبب طلب واحد.
        }
      }
    }

    // طلبات معلّمة صراحة للمراجعة.
    const flagged = await db
      .collection("orders")
      .where("source", "==", "fazer")
      .where("fazerNeedsCheck", "==", true)
      .limit(40)
      .get();
    for (const doc of flagged.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const data = doc.data();
      if (data.fazerFinal === true) continue;
      const hasFazerId = Boolean(asString(data.fazerOrderId));
      const canRetry = data.walletCharged === true && !hasFazerId;
      if (!hasFazerId && !canRetry) continue;
      try {
        await reconcileOneFazerOrder(apiKey, doc.ref, data);
      } catch {
        // تجاهل خطأ طلب واحد.
      }
    }
  }
);

/**
 * مزامنة تلقائية كاملة لفايزر مرتين يومياً (00:00 و 12:00 بتوقيت بغداد):
 * الفئات (بطاقات/مفاتيح/شحن بالـ ID) + كتالوج تليجرام + عروض كل فئة،
 * مع تجاهل فئات الكربتو المحجوبة. تُبقي الأسعار والمخزون محدّثة دون تدخّل يدوي.
 */
export const fazerAutoSync = onSchedule(
  {
    region: "europe-west1",
    schedule: "0 0,12 * * *",
    timeZone: "Asia/Baghdad",
    timeoutSeconds: 540,
    memory: "512MiB",
    secrets: [fazerApiKey],
  },
  async () => {
    const apiKey = fazerApiKey.value();

    // 1) مزامنة الفئات الرئيسية.
    try {
      await commitCategoryPages({
        apiKey,
        pathBase: "/giftcards",
        kind: "gift_card",
        idField: "category_id",
      });
    } catch (e) {
      console.error("fazerAutoSync gift categories", e);
    }
    try {
      await commitCategoryPages({
        apiKey,
        pathBase: "/gamekeys",
        kind: "game_key",
        idField: "game_id",
      });
    } catch (e) {
      console.error("fazerAutoSync gamekey categories", e);
    }
    try {
      await commitCategoryPages({
        apiKey,
        pathBase: "/topups",
        kind: "topup",
        idField: "category_id",
      });
      await linkTopupValidateFields(apiKey);
    } catch (e) {
      console.error("fazerAutoSync topup categories", e);
    }

    // 2) مزامنة كتالوج تليجرام.
    try {
      await syncTelegramCatalogCore(apiKey);
    } catch (e) {
      console.error("fazerAutoSync telegram", e);
    }

    // 3) مزامنة عروض كل فئة (تجاهل تليجرام والكربتو المحجوب).
    const cats = await db.collection("fazer_categories").get();
    let syncedCategories = 0;
    let syncedOffers = 0;
    for (const doc of cats.docs) {
      const data = doc.data() as JsonMap;
      const categoryId = doc.id;
      const kind = asString(data.kind);
      if (kind === "telegram_stars" || kind === "telegram_premium") continue;
      if (isBlockedCryptoCategory(categoryId, asString(data.name))) continue;
      try {
        const r = await syncCategoryOffersCore(apiKey, categoryId, data);
        syncedCategories++;
        syncedOffers += r.synced;
      } catch (e) {
        console.error("fazerAutoSync offers", categoryId, e);
      }
    }
    console.info(
      `fazerAutoSync done: ${syncedCategories} categories, ` +
        `${syncedOffers} offers`
    );
  }
);
