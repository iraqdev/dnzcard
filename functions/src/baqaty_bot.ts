import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

const db = admin.firestore();
const BAQATY_BASE = "https://api.ebaqaty.com/card/api/index.php/Api/";

type BaqatyCreds = {
  user_id: string;
  username: string;
  password: string;
  imei: string;
  secret_key: string;
};

type PinItem = {
  pin: string;
  serial: string;
  card_name?: string;
  order_no?: string;
};

async function requireAdmin(uid: string): Promise<void> {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists || snap.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "يتطلب صلاحية أدمن");
  }
}

async function loadCreds(): Promise<BaqatyCreds> {
  const snap = await db.collection("app_settings").doc("baqaty_account").get();
  if (!snap.exists) {
    throw new HttpsError(
      "failed-precondition",
      "حساب Baqaty غير مُعد — احفظ بيانات الدخول أولاً"
    );
  }
  const d = snap.data() || {};
  const creds: BaqatyCreds = {
    user_id: String(d.user_id || ""),
    username: String(d.username || ""),
    password: String(d.password || ""),
    imei: String(d.imei || "121212"),
    secret_key: String(d.secret_key || ""),
  };
  if (!creds.user_id || !creds.username || !creds.password) {
    throw new HttpsError("failed-precondition", "بيانات Baqaty ناقصة");
  }
  return creds;
}

async function saveCredsPatch(patch: Partial<BaqatyCreds>): Promise<void> {
  await db.collection("app_settings").doc("baqaty_account").set(
    {
      ...patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
}

function cleanFields(fields: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(fields)) {
    if (v === undefined || v === null) continue;
    const s = String(v);
    // لا نرسل secret_key فارغ — يسبب Not Allow / ردود غريبة
    if (k === "secret_key" && !s.trim()) continue;
    out[k] = s;
  }
  return out;
}

function summarizeRaw(text: string): string {
  const t = (text || "").replace(/\s+/g, " ").trim();
  if (!t) return "(empty)";
  const lower = t.toLowerCase();
  if (lower.includes("<html") || lower.includes("<!doctype")) {
    if (lower.includes("cloudflare")) return "html:cloudflare";
    if (lower.includes("access denied") || lower.includes("forbidden")) {
      return "html:forbidden";
    }
    return `html:${t.slice(0, 80)}`;
  }
  return t.slice(0, 160);
}

async function baqatyPost(
  endpoint: string,
  fields: Record<string, string>
): Promise<Record<string, unknown>> {
  const body = new URLSearchParams(cleanFields(fields)).toString();
  const res = await fetch(`${BAQATY_BASE}${endpoint}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json, text/plain, */*",
      "User-Agent": "okhttp/4.9.0",
      "Connection": "close",
    },
    body,
  });
  const text = await res.text();
  const trimmed = text.replace(/^\uFEFF/, "").trim();
  try {
    return JSON.parse(trimmed) as Record<string, unknown>;
  } catch {
    return {
      status: false,
      message: `non-json http=${res.status} ctype=${res.headers.get("content-type") || "?"} body=${summarizeRaw(trimmed)}`,
      raw: trimmed.slice(0, 400),
      http_status: res.status,
    };
  }
}

function authFields(c: BaqatyCreds): Record<string, string> {
  return {
    username: c.username,
    password: c.password,
    imei: c.imei,
    secret_key: c.secret_key,
  };
}

async function ensureLogin(creds: BaqatyCreds): Promise<BaqatyCreds> {
  const login = await baqatyPost("pos_login_sec", {
    acc_name: creds.username,
    password: creds.password,
    imei_number: creds.imei,
    secret_key: creds.secret_key,
    latitude: "33.3",
    longitude: "44.4",
  });

  if (login.status === true) {
    const data = (login.data || {}) as Record<string, unknown>;
    const user = (data.user || {}) as Record<string, unknown>;
    const nextKey = String(user.secretKey || user.secret_key || creds.secret_key);
    const nextUserId = String(user.id || creds.user_id);
    const next: BaqatyCreds = {
      ...creds,
      user_id: nextUserId || creds.user_id,
      secret_key: nextKey || creds.secret_key,
    };
    if (next.secret_key !== creds.secret_key || next.user_id !== creds.user_id) {
      await saveCredsPatch({
        secret_key: next.secret_key,
        user_id: next.user_id,
      });
    }
    return next;
  }

  // retry without secret (some servers reissue)
  const login2 = await baqatyPost("pos_login_sec", {
    acc_name: creds.username,
    password: creds.password,
    imei_number: creds.imei,
    latitude: "33.3",
    longitude: "44.4",
  });
  if (login2.status === true) {
    const data = (login2.data || {}) as Record<string, unknown>;
    const user = (data.user || {}) as Record<string, unknown>;
    const next: BaqatyCreds = {
      ...creds,
      user_id: String(user.id || creds.user_id),
      secret_key: String(user.secretKey || user.secret_key || creds.secret_key),
    };
    await saveCredsPatch({
      secret_key: next.secret_key,
      user_id: next.user_id,
    });
    return next;
  }

  throw new HttpsError(
    "unauthenticated",
    `فشل دخول Baqaty: ${String(
      login.message || login2.message || "unknown"
    )} | detail=${String(login.raw || login2.raw || "").slice(0, 120)}`
  );
}

function extractPins(response: Record<string, unknown>): PinItem[] {
  const pins: PinItem[] = [];
  const data = response.data;
  const items: unknown[] = Array.isArray(data) ?
    data :
    data && typeof data === "object" ?
      [data] :
      [];

  for (const raw of items) {
    if (!raw || typeof raw !== "object") continue;
    const item = raw as Record<string, unknown>;
    const pin = String(
      item.pincode || item.pin_code || item.pin || item.code || ""
    ).trim();
    const serial = String(
      item.sno ||
        item.serial ||
        item.serialNumber ||
        item.usr_card_id ||
        item.print_card_id ||
        ""
    ).trim();
    if (!pin && !serial) continue;
    pins.push({
      pin,
      serial: serial || pin,
      card_name: String(item.card_name || item.name || ""),
      order_no: String(item.print_order || item.order_no || ""),
    });
  }
  return pins;
}

async function purchaseOne(
  creds: BaqatyCreds,
  catId: string,
  cardId: string
): Promise<{pins: PinItem[]; response: Record<string, unknown>}> {
  const base = {
    user_id: creds.user_id,
    card_id: cardId,
    cardtype_id: cardId,
    quantity: "1",
    cat_id: catId,
    category_id: catId,
    ...authFields(creds),
  };

  for (const mode of ["2", "1"]) {
    const resp = await baqatyPost("pos_print_card", {
      ...base,
      mode,
      print_mode: mode,
    });
    const pins = extractPins(resp);
    if (pins.length) return {pins, response: resp};
    if (resp.status === false) {
      const msg = String(resp.message || "").toLowerCase();
      if (
        msg.includes("balance") ||
        msg.includes("allow") ||
        msg.includes("incorrect") ||
        msg.includes("cant") ||
        msg.includes("dont")
      ) {
        return {pins: [], response: resp};
      }
    }
  }

  const resp2 = await baqatyPost("print_image", base);
  return {pins: extractPins(resp2), response: resp2};
}

async function uploadPins(productId: string, pins: PinItem[]): Promise<number> {
  const productRef = db.collection("products").doc(productId);
  const productSnap = await productRef.get();
  const productData = productSnap.data() || {};
  const productName = String(productData.name || "");
  const companyId = String(productData.companyId || "");
  const unitCost = Number(productData.costPrice || 0);
  let companyName = "";
  if (companyId) {
    const companySnap = await db.collection("companies").doc(companyId).get();
    companyName = String(companySnap.data()?.name || "");
  }

  const batch = db.batch();
  let added = 0;
  for (const p of pins) {
    const pin = (p.pin || "").trim();
    const serial = (p.serial || pin).trim();
    if (!pin) continue;
    const ref = productRef.collection("codes").doc();
    batch.set(ref, {
      code: pin,
      serialNumber: serial,
      status: "available",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "baqaty_bot",
    });
    added++;
  }
  if (added === 0) return 0;
  batch.update(productRef, {
    stockCount: admin.firestore.FieldValue.increment(added),
  });
  batch.set(db.collection("stock_uploads").doc(), {
    productId,
    productName,
    companyId,
    companyName,
    count: added,
    unitCost,
    totalCost: unitCost * added,
    source: "baqaty_bot",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return added;
}

async function withPurchaseLock<T>(fn: () => Promise<T>): Promise<T> {
  const lockRef = db.collection("bot_locks").doc("baqaty_purchase");
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(lockRef);
    const lockedUntil = Number(snap.data()?.lockedUntil || 0);
    if (lockedUntil > now) {
      throw new HttpsError(
        "resource-exhausted",
        "عملية شراء أخرى قيد التنفيذ — أعد المحاولة بعد لحظات"
      );
    }
    tx.set(
      lockRef,
      {
        lockedUntil: now + 120000,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  });

  try {
    return await fn();
  } finally {
    await lockRef.set(
      {
        lockedUntil: 0,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  }
}

async function writeBotLog(entry: Record<string, unknown>): Promise<void> {
  await db.collection("bot_logs").add({
    ...entry,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/** حالة البوت السحابي + دخول Baqaty */
export const baqatyBotStatus = onCall(
  {region: "europe-west1", timeoutSeconds: 60},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);
    try {
      const creds0 = await loadCreds();
      const creds = await ensureLogin(creds0);
      const remain = await baqatyPost("remain_report", {
        user_id: creds.user_id,
        ...authFields(creds),
      });
      return {
        ok: true,
        bot_running: true,
        mode: "cloud",
        user_id: creds.user_id,
        username: creds.username,
        remain,
        message: "البوت السحابي جاهز",
      };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return {ok: false, bot_running: false, mode: "cloud", message: msg};
    }
  }
);

/** حفظ/تحديث حساب Baqaty (أدمن فقط) */
export const baqatySaveAccount = onCall(
  {region: "europe-west1"},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);
    const d = request.data || {};
    const patch: BaqatyCreds = {
      user_id: String(d.user_id || "").trim(),
      username: String(d.username || "").trim(),
      password: String(d.password || "").trim(),
      imei: String(d.imei || "121212").trim(),
      secret_key: String(d.secret_key || "").trim(),
    };
    if (!patch.user_id || !patch.username || !patch.password) {
      throw new HttpsError("invalid-argument", "user_id/username/password مطلوبة");
    }
    await db.collection("app_settings").doc("baqaty_account").set(
      {
        ...patch,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    const logged = await ensureLogin(patch);
    return {ok: true, user_id: logged.user_id, message: "تم حفظ الحساب وتأكيد الدخول"};
  }
);

/** كتالوج Baqaty من السحابة */
export const baqatyFetchCatalog = onCall(
  {region: "europe-west1", timeoutSeconds: 120, memory: "512MiB"},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);
    const creds = await ensureLogin(await loadCreds());
    const catsResp = await baqatyPost("category_list", {
      user_id: creds.user_id,
      ...authFields(creds),
    });
    const cats = Array.isArray(catsResp.data) ? catsResp.data : [];
    const cards: Array<Record<string, string>> = [];
    for (const cat of cats) {
      if (!cat || typeof cat !== "object") continue;
      const c = cat as Record<string, unknown>;
      const catId = String(c.id || "");
      const catName = String(c.cat_name || "");
      if (!catId) continue;
      let listResp = await baqatyPost("card_by_catid_balance", {
        user_id: creds.user_id,
        cat_id: catId,
        category_id: catId,
        ...authFields(creds),
      });
      let list = Array.isArray(listResp.data) ? listResp.data : [];
      if (!list.length) {
        listResp = await baqatyPost("card_by_catid_GB", {
          user_id: creds.user_id,
          cat_id: catId,
          category_id: catId,
          ...authFields(creds),
        });
        list = Array.isArray(listResp.data) ? listResp.data : [];
      }
      for (const card of list) {
        if (!card || typeof card !== "object") continue;
        const x = card as Record<string, unknown>;
        cards.push({
          cat_id: catId,
          cat_name: catName,
          card_id: String(x.card_id || ""),
          card_name: String(x.card_name || ""),
          enabled: "true",
          kushk_product_id: "",
        });
      }
    }
    return {ok: true, cards, count: cards.length};
  }
);

/** شراء كروت ورفعها لمخزن Kushk — يعمل بدون جهاز محلي */
export const baqatyBuyCards = onCall(
  {region: "europe-west1", timeoutSeconds: 300, memory: "512MiB"},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);

    const productId = String(request.data?.productId || "").trim();
    const cardId = String(request.data?.cardId || "").trim();
    const catId = String(request.data?.catId || "").trim();
    const quantity = Math.max(1, Math.min(20, Number(request.data?.quantity || 1)));
    const source = String(request.data?.source || "cloud_admin");

    if (!productId || !cardId || !catId) {
      throw new HttpsError("invalid-argument", "productId/cardId/catId مطلوبة");
    }

    return withPurchaseLock(async () => {
      const creds = await ensureLogin(await loadCreds());
      const purchased: PinItem[] = [];
      const errors: string[] = [];

      for (let i = 0; i < quantity; i++) {
        const {pins, response} = await purchaseOne(creds, catId, cardId);
        if (pins.length) {
          purchased.push(...pins);
        } else {
          const msg = String(response.message || JSON.stringify(response)).slice(0, 300);
          errors.push(msg);
          const low = msg.toLowerCase();
          if (
            low.includes("balance") ||
            low.includes("allow") ||
            low.includes("incorrect")
          ) {
            break;
          }
        }
      }

      let uploaded = 0;
      if (purchased.length) {
        uploaded = await uploadPins(productId, purchased);
      }

      await db.collection("bot_maps").doc(productId).set(
        {
          lastStatus: purchased.length ? "ok" : "error",
          lastMessage: purchased.length ?
            `bought=${purchased.length} uploaded=${uploaded}` :
            errors[0] || "no pins",
          lastRequestAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      await writeBotLog({
        productId,
        cardId,
        catId,
        quantity,
        ok: purchased.length > 0,
        source,
        bought: purchased.length,
        uploaded,
        errors,
        mode: "cloud",
        // لا نخزّن pin كاملاً في اللوج العام إن أمكن — نخزّن العدد فقط
      });

      return {
        ok: purchased.length > 0,
        bought: purchased.length,
        uploaded,
        errors,
        cards: purchased.map((p) => ({
          pin: p.pin,
          serial: p.serial,
          card_name: p.card_name || "",
        })),
        message: purchased.length ?
          `تم شراء ${purchased.length} ورفع ${uploaded}` :
          errors[0] || "فشل الشراء",
      };
    });
  }
);

/** فحص دوري: تعبئة المنتجات منخفضة المخزون تلقائياً */
export const baqatyAutoRefill = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 5 minutes",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const settingsSnap = await db.collection("app_settings").doc("card_bot").get();
    const settings = settingsSnap.data() || {};
    if (settings.enabled === false || settings.autoRefill === false) {
      return;
    }
    if (settings.useCloudMode === false) {
      return;
    }

    const mapsSnap = await db.collection("bot_maps").get();
    for (const doc of mapsSnap.docs) {
      const map = doc.data();
      if (!map.enabled) continue;
      const cardId = String(map.cardId || "");
      const catId = String(map.catId || "");
      if (!cardId || !catId) continue;
      const minStock = Number(map.minStock ?? 3);
      const refillQty = Math.max(1, Math.min(10, Number(map.refillQty ?? 5)));

      const productSnap = await db.collection("products").doc(doc.id).get();
      const stock = Number(productSnap.data()?.stockCount ?? 0);
      if (stock > minStock) continue;

      try {
        await withPurchaseLock(async () => {
          const creds = await ensureLogin(await loadCreds());
          const purchased: PinItem[] = [];
          for (let i = 0; i < refillQty; i++) {
            const {pins, response} = await purchaseOne(creds, catId, cardId);
            if (pins.length) purchased.push(...pins);
            else {
              const msg = String(response.message || "").toLowerCase();
              if (msg.includes("balance") || msg.includes("allow")) break;
            }
          }
          const uploaded = purchased.length ?
            await uploadPins(doc.id, purchased) :
            0;
          await doc.ref.set(
            {
              lastStatus: purchased.length ? "ok" : "error",
              lastMessage: `auto bought=${purchased.length} uploaded=${uploaded}`,
              lastRequestAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true}
          );
          await writeBotLog({
            productId: doc.id,
            cardId,
            catId,
            quantity: refillQty,
            ok: purchased.length > 0,
            source: "cloud_auto_schedule",
            bought: purchased.length,
            uploaded,
            mode: "cloud",
          });
        });
      } catch (e) {
        await writeBotLog({
          productId: doc.id,
          cardId,
          catId,
          ok: false,
          source: "cloud_auto_schedule",
          message: e instanceof Error ? e.message : String(e),
          mode: "cloud",
        });
      }
    }
  }
);
