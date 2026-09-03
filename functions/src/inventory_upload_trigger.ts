import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

const db = admin.firestore();

const SKIP_SOURCES = new Set(["manual", "scan"]);

function normalizeSource(raw: unknown): string {
  const source = String(raw || "").trim().toLowerCase();
  if (!source) return "bot";
  if (source === "cloud_function") return "baqaty_bot";
  if (source === "card_buyer_bot") return "baqaty_bot";
  return source;
}

async function loadProductMeta(productId: string) {
  const productSnap = await db.collection("products").doc(productId).get();
  const productData = productSnap.data() || {};
  const productName = String(productData.name || "");
  const companyId = String(productData.companyId || "");
  const unitCost = Number(productData.costPrice || 0);
  let companyName = "";
  if (companyId) {
    const companySnap = await db.collection("companies").doc(companyId).get();
    companyName = String(companySnap.data()?.name || "");
  }
  return {productName, companyId, companyName, unitCost};
}

/** يسجّل رفع البوتات (آسيا / أثير / غيرها) إذا لم يُكتب stock_uploads مسبقاً. */
export const onInventoryCodeCreated = onDocumentCreated(
  {
    document: "products/{productId}/codes/{codeId}",
    region: "europe-west1",
  },
  async (event) => {
    const productId = event.params.productId;
    const data = event.data?.data();
    if (!data) return;

    const source = normalizeSource(data.source);
    if (SKIP_SOURCES.has(source)) return;

    const windowStart = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 8000)
    );

    const recentLogged = await db
      .collection("stock_uploads")
      .where("productId", "==", productId)
      .where("createdAt", ">=", windowStart)
      .limit(1)
      .get();
    if (!recentLogged.empty) return;

    const {productName, companyId, companyName, unitCost} =
      await loadProductMeta(productId);

    const recentSameSource = await db
      .collection("stock_uploads")
      .where("productId", "==", productId)
      .where("source", "==", source)
      .where("createdAt", ">=", windowStart)
      .orderBy("createdAt", "desc")
      .limit(1)
      .get();

    if (!recentSameSource.empty) {
      const ref = recentSameSource.docs[0].ref;
      await ref.update({
        count: admin.firestore.FieldValue.increment(1),
        totalCost: admin.firestore.FieldValue.increment(unitCost),
      });
      return;
    }

    await db.collection("stock_uploads").add({
      productId,
      productName,
      companyId,
      companyName,
      count: 1,
      unitCost,
      totalCost: unitCost,
      source,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);
