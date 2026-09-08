import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

const db = admin.firestore();

async function requireAdmin(uid: string): Promise<void> {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists || snap.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "يتطلب صلاحية أدمن");
  }
}

/**
 * يثبّت أسعار الطلبات القديمة (تكلفة/بيع) في مستند الطلب مرة واحدة
 * حتى لا تتأثر إحصائيات الماضي بتغيير أسعار المنتج لاحقاً.
 */
export const adminBackfillOrderSnapshots = onCall(
  {region: "europe-west1", timeoutSeconds: 540},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);

    const ordersSnap = await db.collection("orders").get();
    let updated = 0;
    let skipped = 0;

    let batch = db.batch();
    let ops = 0;

    for (const doc of ordersSnap.docs) {
      const data = doc.data();
      if (data.source === "fazer") {
        skipped++;
        continue;
      }

      const qty = Math.max(1, Math.floor(Number(data.quantity) || 1));
      let unitCostPrice = Number(data.unitCostPrice) || 0;
      let chargedUnitPrice = Number(data.chargedUnitPrice) || 0;
      const chargedTotal = Number(data.chargedTotal) || 0;

      if (chargedUnitPrice <= 0 && chargedTotal > 0) {
        chargedUnitPrice = chargedTotal / qty;
      }

      const productId = String(data.productId || "").trim();
      if (productId) {
        const productSnap = await db.collection("products").doc(productId).get();
        const productData = productSnap.data() || {};

        if (unitCostPrice <= 0) {
          unitCostPrice = Number(productData.costPrice) || 0;
        }
        if (chargedUnitPrice <= 0) {
          const visible = Number(productData.price) || 0;
          const hidden = Number(productData.hiddenSalePrice);
          chargedUnitPrice =
            Number.isFinite(hidden) && hidden > 0 ? hidden : visible;
        }
      }

      if (unitCostPrice <= 0 && chargedUnitPrice <= 0) {
        skipped++;
        continue;
      }

      const patch: Record<string, number> = {};
      const existingUnitCost = Number(data.unitCostPrice) || 0;
      const existingChargedUnit = Number(data.chargedUnitPrice) || 0;
      if (existingUnitCost <= 0 && unitCostPrice > 0) {
        patch.unitCostPrice = unitCostPrice;
      }
      if (existingChargedUnit <= 0 && chargedUnitPrice > 0) {
        patch.chargedUnitPrice = chargedUnitPrice;
      }

      if (Object.keys(patch).length === 0) {
        skipped++;
        continue;
      }

      batch.update(doc.ref, patch);
      ops++;
      updated++;

      if (ops >= 400) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }

    if (ops > 0) {
      await batch.commit();
    }

    return {ok: true, updated, skipped, total: ordersSnap.size};
  }
);
