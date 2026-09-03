/**
 * تشخيص: البحث عن محل «اسواق العلي» وطلباته وخصوماته.
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

  const usersSnap = await db.collection("users").where("role", "==", "shop").get();
  const shops = [];
  for (const doc of usersSnap.docs) {
    const d = doc.data();
    const shopName = String(d.shopName || d.name || "").trim();
    if (
      /علي|العلي|aswaq/i.test(shopName) ||
      shopName.includes("العلي") ||
      shopName.includes("علي")
    ) {
      shops.push({
        id: doc.id,
        shopName,
        phone: d.phone,
        balance: d.walletBalance,
      });
    }
  }
  console.log("MATCHING_SHOPS");
  console.log(JSON.stringify(shops, null, 2));

  for (const shop of shops) {
    let ordersSnap;
    try {
      ordersSnap = await db
        .collection("orders")
        .where("shopId", "==", shop.id)
        .orderBy("createdAt", "desc")
        .limit(30)
        .get();
    } catch (e) {
      const all = await db.collection("orders").where("shopId", "==", shop.id).get();
      ordersSnap = {
        docs: all.docs.sort((a, b) => {
          const ta = a.data().createdAt?.toMillis?.() ?? 0;
          const tb = b.data().createdAt?.toMillis?.() ?? 0;
          return tb - ta;
        }).slice(0, 30),
      };
    }

    const orders = ordersSnap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        productName: d.productName,
        companyName: d.companyName,
        total: d.total,
        status: d.status,
        source: d.source || "",
        walletCharged: d.walletCharged,
        createdAt: d.createdAt?.toDate?.()?.toISOString?.() || null,
        cardCodes: d.cardCodes,
      };
    });
    console.log(`ORDERS_FOR ${shop.shopName}`);
    console.log(JSON.stringify(orders, null, 2));

    let txs;
    try {
      txs = await db
        .collection("wallet_transactions")
        .where("userId", "==", shop.id)
        .where("type", "==", "debit")
        .orderBy("createdAt", "desc")
        .limit(30)
        .get();
    } catch (e) {
      const all = await db
        .collection("wallet_transactions")
        .where("userId", "==", shop.id)
        .get();
      txs = {
        docs: all.docs
          .filter((d) => d.data().type === "debit")
          .sort((a, b) => {
            const ta = a.data().createdAt?.toMillis?.() ?? 0;
            const tb = b.data().createdAt?.toMillis?.() ?? 0;
            return tb - ta;
          })
          .slice(0, 30),
      };
    }

    console.log(`DEBITS_FOR ${shop.shopName}`);
    console.log(
      JSON.stringify(
        txs.docs.map((doc) => {
          const d = doc.data();
          return {
            id: doc.id,
            amount: d.amount,
            reason: d.reason,
            orderId: d.orderId,
            createdAt: d.createdAt?.toDate?.()?.toISOString?.() || null,
          };
        }),
        null,
        2
      )
    );
  }

  const prodSnap = await db.collection("products").get();
  const prods = prodSnap.docs
    .filter((doc) => {
      const d = doc.data();
      const n = String(d.name || "");
      const p = Number(d.price || 0);
      return n.includes("100000") || p === 100000;
    })
    .map((doc) => ({
      id: doc.id,
      name: doc.data().name,
      price: doc.data().price,
      companyId: doc.data().companyId,
    }));
  console.log("PRODUCTS_100000");
  console.log(JSON.stringify(prods, null, 2));

  const totalOrders = (await db.collection("orders").count().get()).data().count;
  console.log("TOTAL_ORDERS_COUNT", totalOrders);

  const targetId = process.argv[2];
  const shopIdArg = process.argv[3] || "FfemKU6roreEJ8kukyb4LlzTLRu2";

  let walletTxs;
  try {
    walletTxs = await db
      .collection("wallet_transactions")
      .where("userId", "==", shopIdArg)
      .orderBy("createdAt", "desc")
      .limit(60)
      .get();
  } catch (e) {
    const all = await db
      .collection("wallet_transactions")
      .where("userId", "==", shopIdArg)
      .get();
    walletTxs = {
      docs: all.docs.sort((a, b) => {
        const ta = a.data().createdAt?.toMillis?.() ?? 0;
        const tb = b.data().createdAt?.toMillis?.() ?? 0;
        return tb - ta;
      }).slice(0, 60),
    };
  }

  console.log(`WALLET_TX_FOR ${shopIdArg} (count ${walletTxs.docs.length})`);
  for (const doc of walletTxs.docs) {
    const d = doc.data();
    console.log(
      JSON.stringify({
        id: doc.id,
        type: d.type,
        amount: d.amount,
        reason: d.reason,
        orderId: d.orderId || null,
        visibleToUser: d.visibleToUser ?? true,
        depositMethod: d.depositMethod || null,
        createdAt: d.createdAt?.toDate?.()?.toISOString?.() || null,
      })
    );
  }

  const credit200 = walletTxs.docs.filter(
    (d) =>
      Number(d.data().amount) === 200 ||
      String(d.data().reason || "").includes("200")
  );
  console.log("CREDITS_MATCHING_200", credit200.length);
  for (const doc of credit200) {
    const d = doc.data();
    console.log(
      "CREDIT200",
      JSON.stringify({
        id: doc.id,
        amount: d.amount,
        reason: d.reason,
        createdAt: d.createdAt?.toDate?.()?.toISOString?.(),
      })
    );
  }

  const debit100k = walletTxs.docs.filter(
    (d) =>
      d.data().type === "debit" &&
      (Number(d.data().amount) === 100300 ||
        String(d.data().reason || "").includes("100000"))
  );
  console.log("DEBITS_MATCHING_100000", debit100k.length);

  if (targetId) {
    const targetSnap = await db.collection("orders").doc(targetId).get();
    if (!targetSnap.exists) {
      console.log("TARGET_NOT_FOUND", targetId);
      return;
    }
    const all = await db.collection("orders").orderBy("createdAt", "desc").get();
    const idx = all.docs.findIndex((d) => d.id === targetId);
    console.log("GLOBAL_RANK", idx + 1, "of", all.size);
    console.log(
      "TARGET_ORDER",
      JSON.stringify(
        {
          id: targetId,
          shopId: targetSnap.data().shopId,
          productName: targetSnap.data().productName,
          total: targetSnap.data().total,
          createdAt: targetSnap.data().createdAt?.toDate?.()?.toISOString?.(),
        },
        null,
        2
      )
    );
    console.log("VISIBLE_IN_DASH_LIMIT_200", idx >= 0 && idx < 200);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
