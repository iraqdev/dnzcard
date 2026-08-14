/**
 * يدرج طلبات فايزر التي لها رقم طلب ولم يُخصم مبلغها من المحفظة.
 * لا يطبع أسرار/توكنات.
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

async function main() {
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error("لا يوجد تسجيل دخول Firebase CLI");

  const credPath = await getCredentialPathAsync(account);
  if (!credPath || !fs.existsSync(credPath)) {
    throw new Error("تعذر إنشاء اعتماد ADC من تسجيل Firebase");
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = credPath;

  admin.initializeApp({projectId: "kushk-eb02a"});
  const db = admin.firestore();

  const statuses = ["failed", "ordering", "processing", "needs_settlement"];
  const candidates = [];
  const seen = new Set();

  for (const status of statuses) {
    let snap;
    try {
      snap = await db
        .collection("orders")
        .where("source", "==", "fazer")
        .where("status", "==", status)
        .get();
    } catch (e) {
      // إن نقص الفهرس المركّب: اجلب حسب المصدر وصفِّ محلياً
      if (!snap) {
        const all = await db.collection("orders").where("source", "==", "fazer").get();
        snap = {
          docs: all.docs.filter((d) => d.data().status === status),
        };
      }
    }
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const d = doc.data();
      const fazerOrderId = String(d.fazerOrderId || "").trim();
      if (!fazerOrderId) continue;
      if (d.walletCharged === true) continue;
      candidates.push({id: doc.id, ref: doc.ref, ...d});
    }
  }

  const report = [];
  for (const order of candidates) {
    const txSnap = await db
      .collection("wallet_transactions")
      .where("orderId", "==", order.id)
      .where("type", "==", "debit")
      .limit(5)
      .get();
    if (!txSnap.empty) continue;

    let shopPhone = "";
    let shopName = "";
    try {
      const userSnap = await db.collection("users").doc(String(order.shopId)).get();
      if (userSnap.exists) {
        const u = userSnap.data() || {};
        shopPhone = String(u.phone || "");
        shopName = String(u.shopName || u.name || "");
      }
    } catch (_) {}

    const createdAt =
      order.createdAt && typeof order.createdAt.toDate === "function"
        ? order.createdAt.toDate()
        : null;

    report.push({
      orderId: order.id,
      fazerOrderId: String(order.fazerOrderId || ""),
      status: String(order.status || ""),
      productName: String(order.productName || ""),
      companyName: String(order.companyName || ""),
      fazerKind: String(order.fazerKind || ""),
      totalIqd: Number(order.total || 0),
      shopId: String(order.shopId || ""),
      shopPhone,
      shopName,
      error: String(order.error || ""),
      createdAt: createdAt ? createdAt.toISOString() : "",
      topupFields: order.topupFields || null,
    });
  }

  report.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
  const totalAmount = report.reduce(
    (s, r) => s + (Number.isFinite(r.totalIqd) ? r.totalIqd : 0),
    0
  );

  const outPath = path.join(__dirname, "uncharged_fazer_orders_report.json");
  fs.writeFileSync(
    outPath,
    JSON.stringify({count: report.length, totalAmount, orders: report}, null, 2),
    "utf8"
  );
  console.log(`COUNT=${report.length}`);
  console.log(`TOTAL_IQD=${totalAmount}`);
  console.log(`REPORT=${outPath}`);
  for (const r of report) {
    console.log(
      [
        r.createdAt || "-",
        r.orderId,
        r.fazerOrderId,
        r.status,
        r.totalIqd,
        r.shopPhone || r.shopId,
        r.shopName,
        r.productName,
        r.error,
      ].join(" | ")
    );
  }
}

main().catch((e) => {
  console.error("FAILED", e && e.message ? e.message : e);
  process.exit(1);
});
