import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {randomUUID} from "crypto";
import {assertRateLimit, clientRateKey} from "./rate_limit";
import {verifyPurchasePin} from "./purchase_guard";

const db = admin.firestore();

/**
 * شراء منتج من المخزون المحلي (بطاقات مرفوعة) على الخادم بشكل ذرّي:
 * التحقق من الحساب + رمز الشراء، اختيار الأكواد المتاحة، الخصم، تعليم الأكواد
 * مباعة، وإنشاء الطلب — كل ذلك بصلاحية الخادم بحيث لا يمكن للعميل تزويره.
 *
 * يحافظ على نفس سلوك النسخة القديمة تماماً (نفس الحقول والمبالغ).
 */
export const purchaseLocalProduct = onCall(
  {region: "europe-west1", timeoutSeconds: 60},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يلزم تسجيل الدخول");
    }
    const uid = request.auth.uid;
    await assertRateLimit(
      clientRateKey("local_purchase", request, uid),
      60,
      60 * 1000
    );

    const productId = String(request.data?.productId ?? "").trim();
    const quantity = Math.max(1, Math.floor(Number(request.data?.quantity) || 1));
    const pin =
      request.data?.pin != null ? String(request.data.pin) : undefined;
    if (!productId) {
      throw new HttpsError("invalid-argument", "معرّف المنتج مطلوب");
    }

    await verifyPurchasePin(db, uid, pin);

    const shopRef = db.collection("users").doc(uid);
    const productRef = db.collection("products").doc(productId);
    const codesCol = productRef.collection("codes");

    const availableSnap = await codesCol
      .where("status", "==", "available")
      .limit(quantity)
      .get();
    if (availableSnap.size < quantity) {
      throw new HttpsError("failed-precondition", "لا يوجد مخزون كافٍ");
    }
    const codeRefs = availableSnap.docs.map((d) => d.ref);

    const orderRef = db.collection("orders").doc(randomUUID());
    const txRef = db.collection("wallet_transactions").doc(randomUUID());

    await db.runTransaction(async (tx) => {
      // كل القراءات أولاً ثم الكتابات (شرط معاملات Firestore).
      const shopSnap = await tx.get(shopRef);
      const productSnap = await tx.get(productRef);

      const shopData = shopSnap.data();
      if (
        !shopSnap.exists ||
        shopData?.role !== "shop" ||
        shopData?.status === "suspended" ||
        shopData?.status === "rejected"
      ) {
        throw new HttpsError("permission-denied", "حساب المتجر موقوف");
      }

      const productData = productSnap.data() || {};
      const unitPrice = Number(productData.price || 0);
      const hidden = Number(productData.hiddenSalePrice);
      const chargedUnit =
        Number.isFinite(hidden) && hidden > 0 ? hidden : unitPrice;
      const total = unitPrice * quantity;
      const chargedTotal = chargedUnit * quantity;
      const balance = Number(shopData?.walletBalance || 0);
      if (balance < chargedTotal) {
        throw new HttpsError("failed-precondition", "رصيد المحفظة غير كافٍ");
      }

      const freshCodes: admin.firestore.DocumentSnapshot[] = [];
      for (const ref of codeRefs) {
        const fresh = await tx.get(ref);
        if (fresh.data()?.status !== "available") {
          throw new HttpsError("aborted", "تم بيع أحد الأكواد، أعد المحاولة");
        }
        freshCodes.push(fresh);
      }

      let companyName = "";
      const companyId = String(productData.companyId || "");
      if (companyId) {
        const companySnap = await tx.get(
          db.collection("companies").doc(companyId)
        );
        companyName = String(companySnap.data()?.name || "");
      }

      const cardItems = freshCodes.map((snap) => ({
        code: String(snap.data()?.code ?? snap.id),
        serialNumber: String(snap.data()?.serialNumber ?? ""),
      }));
      const cardCodes = cardItems.map((c) => c.code);
      const productName = String(productData.name || "");
      const after = balance - chargedTotal;

      for (const snap of freshCodes) {
        tx.update(snap.ref, {
          status: "sold",
          soldTo: uid,
          soldAt: admin.firestore.FieldValue.serverTimestamp(),
          orderId: orderRef.id,
        });
      }
      tx.update(shopRef, {walletBalance: after});
      tx.update(productRef, {
        stockCount: admin.firestore.FieldValue.increment(-quantity),
      });
      tx.set(orderRef, {
        shopId: uid,
        productId,
        productName,
        companyName,
        quantity,
        unitPrice,
        total,
        cardItems,
        cardCodes,
        paymentMethod: "wallet",
        status: "completed",
        source: "",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        printed: false,
        printCount: 0,
        chargedTotal,
        walletCharged: true,
      });
      tx.set(txRef, {
        userId: uid,
        type: "debit",
        amount: total,
        balanceAfter: after,
        reason: `شراء ${productName}`,
        orderId: orderRef.id,
        companyName,
        visibleToUser: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return {ok: true, orderId: orderRef.id};
  }
);
