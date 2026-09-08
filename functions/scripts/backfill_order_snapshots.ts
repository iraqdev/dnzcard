/**
 * تثبيت أسعار الطلبات القديمة (مرة واحدة).
 * التشغيل: npm run backfill-order-snapshots (من مجلد functions)
 */
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp({projectId: "kushk-eb02a"});
}

const db = admin.firestore();

async function main() {
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

    const patch: Record<string, number> = {};
    if (Number(data.unitCostPrice) <= 0 && unitCostPrice > 0) {
      patch.unitCostPrice = unitCostPrice;
    }
    if (Number(data.chargedUnitPrice) <= 0 && chargedUnitPrice > 0) {
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
      console.log(`... ${updated} updated so far`);
    }
  }

  if (ops > 0) {
    await batch.commit();
  }

  console.log(
    JSON.stringify(
      {ok: true, updated, skipped, total: ordersSnap.size},
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
