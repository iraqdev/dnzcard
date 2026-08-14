/**
 * خصم يدوي لطلبات فايزر غير المخصومة (مرة واحدة).
 * لا يطبع أسرار.
 */
const path = require("path");
const fs = require("fs");
const ftBase = path.join(
  process.env.APPDATA,
  "npm",
  "node_modules",
  "firebase-tools"
);
const auth = require(path.join(ftBase, "lib", "auth.js"));
const {getCredentialPathAsync} = require(
  path.join(ftBase, "lib", "defaultCredentials.js")
);
const admin = require(path.join(
  __dirname,
  "..",
  "functions",
  "node_modules",
  "firebase-admin"
));

const ORDER_IDS = [
  "1ta4JsopLSP8NaFuLYvo",
  "4ToNHB54D8lt9he9iq0g",
  "7sV9y2h3SJ1xlHn6VSFA",
  "qdS3Xoc5Jwmc7etCnxYN",
];

async function main() {
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error("لا يوجد تسجيل دخول Firebase CLI");
  const credPath = await getCredentialPathAsync(account);
  if (!credPath || !fs.existsSync(credPath)) {
    throw new Error("تعذر إنشاء اعتماد ADC");
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = credPath;
  admin.initializeApp({projectId: "kushk-eb02a"});
  const db = admin.firestore();

  const results = [];
  for (const orderId of ORDER_IDS) {
    const orderRef = db.collection("orders").doc(orderId);
    try {
      const existingDebit = await db
        .collection("wallet_transactions")
        .where("orderId", "==", orderId)
        .where("type", "==", "debit")
        .limit(1)
        .get();
      if (!existingDebit.empty) {
        results.push({orderId, ok: false, reason: "debit_exists"});
        continue;
      }

      const outcome = await db.runTransaction(async (tx) => {
        const orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) return {ok: false, reason: "order_missing"};
        const order = orderSnap.data() || {};

        if (order.walletCharged === true || order.walletTransactionId) {
          return {ok: false, reason: "already_charged"};
        }

        const uid = String(order.shopId || "");
        const amount = Number(order.total || 0);
        if (!uid || !(amount > 0)) {
          return {ok: false, reason: "invalid_order_amount"};
        }

        const shopRef = db.collection("users").doc(uid);
        const shopSnap = await tx.get(shopRef);
        if (!shopSnap.exists) return {ok: false, reason: "shop_missing"};
        const bal = Number(shopSnap.data()?.walletBalance ?? 0);
        if (bal < amount) {
          return {
            ok: false,
            reason: "insufficient_balance",
            balance: bal,
            amount,
          };
        }
        const after = bal - amount;
        const txRef = db.collection("wallet_transactions").doc();
        const productName = String(order.productName || "");
        const companyName = String(order.companyName || "");
        const fields = order.topupFields || {};
        const playerLabel =
          Object.values(fields).filter(Boolean).join(" / ") || "اللاعب";
        const codes = [`تم شحن ${productName} إلى ${playerLabel}`];
        const cardItems = codes.map((code) => ({
          code,
          serialNumber: String(order.fazerOrderId || orderId),
        }));

        tx.update(shopRef, {walletBalance: after});
        tx.set(txRef, {
          userId: uid,
          type: "debit",
          amount,
          balanceAfter: after,
          reason: `شراء كشk (تسوية يدوية): ${productName}`,
          orderId,
          companyName,
          visibleToUser: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          manualSettlement: true,
        });
        tx.set(
          orderRef,
          {
            status: "completed",
            walletCharged: true,
            walletTransactionId: txRef.id,
            cardItems,
            cardCodes: codes,
            fazerFinal: true,
            fazerNeedsCheck: false,
            error: admin.firestore.FieldValue.delete(),
            settledManuallyAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
        return {
          ok: true,
          amount,
          balanceAfter: after,
          txId: txRef.id,
          shopId: uid,
          productName,
        };
      });

      results.push({orderId, ...outcome});
    } catch (e) {
      results.push({
        orderId,
        ok: false,
        reason: e && e.message ? e.message : String(e),
      });
    }
  }

  const charged = results.filter((r) => r.ok);
  const failed = results.filter((r) => !r.ok);
  const total = charged.reduce((s, r) => s + Number(r.amount || 0), 0);
  console.log(`CHARGED=${charged.length}`);
  console.log(`FAILED=${failed.length}`);
  console.log(`TOTAL_IQD=${total}`);
  for (const r of results) {
    console.log(JSON.stringify(r));
  }
}

main().catch((e) => {
  console.error("FAILED", e && e.message ? e.message : e);
  process.exit(1);
});
