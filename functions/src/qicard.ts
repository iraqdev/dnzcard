import {randomUUID} from "crypto";
import {defineSecret} from "firebase-functions/params";
import {onRequest} from "firebase-functions/v2/https";

export const qiUsername = defineSecret("QICARD_USERNAME");
export const qiPassword = defineSecret("QICARD_PASSWORD");
export const qiTerminalId = defineSecret("QICARD_TERMINAL_ID");

const QI_BASE = "https://3ds-api.qi.iq/api/v1";
const QI_REGION = "me-west1";

/** نطاق مسجّل عند كي على التيرمنال. Firebase غير مسموح في هذه الحقول. */
const QI_ALLOWED_FINISH_URL =
  "https://gateway.dnzteam.online/payment/finish.html";
const QI_ALLOWED_NOTIFICATION_URL =
  "https://gateway.dnzteam.online/api/webhooks/qicard";

export class QiCardAPIError extends Error {
  statusCode: number;
  body: unknown;
  constructor(message: string, statusCode: number, body: unknown) {
    super(message);
    this.name = "QiCardAPIError";
    this.statusCode = statusCode;
    this.body = body;
  }
}

function authHeaders(): Record<string, string> {
  const token = Buffer.from(
    `${qiUsername.value()}:${qiPassword.value()}`
  ).toString("base64");
  return {
    Authorization: `Basic ${token}`,
    "X-Terminal-Id": String(qiTerminalId.value()),
    Accept: "application/json",
    "Content-Type": "application/json",
  };
}

function apiUrl(path: string): string {
  return `${QI_BASE}${path.startsWith("/") ? path : `/${path}`}`;
}

async function parseResponse(r: Response): Promise<Record<string, unknown>> {
  const text = await r.text();
  let data: Record<string, unknown> = {};
  try {
    data = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  } catch {
    data = {raw: text};
  }
  if (!r.ok) {
    const err = data.error;
    const nested =
      err && typeof err === "object"
        ? (err as Record<string, unknown>)
        : undefined;
    const msg =
      (nested?.description as string) ||
      (nested?.message as string) ||
      (data.errorMessage as string) ||
      `Qi Card API error (${r.status})`;
    throw new QiCardAPIError(msg, r.status, data);
  }
  return data;
}

export function formatAmount(amount: number): number {
  return Math.round(Number(amount) * 100) / 100;
}

export function qiStatusToInternal(
  status: unknown
): "pending" | "success" | "failed" {
  const s = String(status || "")
    .trim()
    .toUpperCase();
  if (s === "SUCCESS") return "success";
  if (["FAILED", "AUTHENTICATION_FAILED", "EXPIRED", "ERROR"].includes(s)) {
    return "failed";
  }
  return "pending";
}

export async function createQiPayment(params: {
  amount: number;
  productName: string;
  description: string;
}): Promise<{
  paymentId: string;
  formUrl: string;
  status: string;
  requestId: string;
}> {
  const requestId = randomUUID();
  const payload = {
    requestId,
    amount: formatAmount(params.amount),
    currency: "IQD",
    locale: "ar",
    finishPaymentUrl: QI_ALLOWED_FINISH_URL,
    notificationUrl: QI_ALLOWED_NOTIFICATION_URL,
    additionalInfo: {
      productName: String(params.productName || "منتج").slice(0, 250),
      description: String(params.description || "").slice(0, 1024),
    },
    appChannel: false,
  };

  const r = await fetch(apiUrl("/payment"), {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(30000),
  });
  const data = await parseResponse(r);
  const paymentId = String(data.paymentId || data.payment_id || "").trim();
  const formUrl = String(
    data.formUrl || data.form_url || data.checkoutUrl || data.url || ""
  ).trim();
  if (!paymentId) {
    throw new QiCardAPIError("معرّف الدفع غير موجود في استجابة كي", 502, data);
  }
  if (!formUrl.startsWith("http")) {
    throw new QiCardAPIError("رابط الدفع غير موجود في استجابة كي", 502, data);
  }
  return {
    paymentId,
    formUrl,
    status: String(data.status || "CREATED"),
    requestId,
  };
}

export async function getQiPaymentStatus(
  paymentId: string
): Promise<Record<string, unknown>> {
  const r = await fetch(
    apiUrl(`/payment/${encodeURIComponent(paymentId)}/status`),
    {
      method: "GET",
      headers: authHeaders(),
      signal: AbortSignal.timeout(30000),
    }
  );
  return parseResponse(r);
}

/** صفحة عودة بعد الدفع داخل WebView. الرصيد يُضاف عبر التحقق من كي. */
export const qiPaymentFinish = onRequest(
  {
    region: QI_REGION,
    invoker: "public",
  },
  (_req, res) => {
    res
      .status(200)
      .type("html")
      .send(`<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>اكتمال الدفع</title>
  <style>
    body{font-family:sans-serif;background:#f5f7fb;color:#12203a;
      display:flex;min-height:100vh;align-items:center;justify-content:center;
      margin:0;padding:24px;text-align:center}
    .card{background:#fff;border-radius:16px;padding:28px 22px;
      max-width:360px;box-shadow:0 8px 28px rgba(18,32,58,.08)}
    h1{font-size:20px;margin:0 0 8px}
    p{margin:0;color:#5b6b82;line-height:1.6}
  </style>
</head>
<body>
  <div class="card">
    <h1>اكتملت عملية الدفع</h1>
    <p>ارجع إلى التطبيق. سيتم إضافة الرصيد تلقائياً بعد التأكيد.</p>
  </div>
</body>
</html>`);
  }
);
