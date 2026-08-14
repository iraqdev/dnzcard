import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {GoogleAuth} from "google-auth-library";

const db = admin.firestore();

async function requireAdmin(uid: string): Promise<void> {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists || snap.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "يتطلب صلاحية أدمن");
  }
}

function normalizeCodeValue(value: string): string {
  // نحافظ على الأحرف (صغير/كبير) والأرقام والرموز، ونزيل المسافات فقط.
  return value
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/\s+/g, "")
    .trim();
}

type GeminiResponse = {
  candidates?: Array<{
    content?: {parts?: Array<{text?: string}>};
  }>;
  error?: {message?: string};
};

async function extractWithVertex(params: {
  imageBase64: string;
  mimeType: string;
}): Promise<{code: string; serialNumber: string}> {
  const projectId =
    process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    admin.app().options.projectId ||
    "kushk-eb02a";

  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  const client = await auth.getClient();
  const url =
    `https://us-central1-aiplatform.googleapis.com/v1/projects/` +
    `${projectId}/locations/us-central1/publishers/google/models/` +
    `gemini-2.5-flash:generateContent`;

  const prompt =
    "Extract recharge card PIN and serial number from this receipt image.\n" +
    "Look for Arabic labels:\n" +
    "- كود رمز التعريف الشخصي = code (PIN)\n" +
    "- الرقم التسلسلي = serialNumber\n" +
    "IMPORTANT: Preserve the EXACT value as printed, including:\n" +
    "- digits (0-9)\n" +
    "- letters (A-Z and a-z)\n" +
    "- symbols (such as - _ * # @ . / +)\n" +
    "- mixed values like Ab12#X\n" +
    "Do NOT convert letters to digits. Do NOT remove letters or symbols. " +
    "Do not invent values. If a field is unreadable, return an empty string for it.";

  const res = await client.request<GeminiResponse>({
    url,
    method: "POST",
    data: {
      contents: [
        {
          role: "user",
          parts: [
            {text: prompt},
            {
              inlineData: {
                mimeType: params.mimeType,
                data: params.imageBase64,
              },
            },
          ],
        },
      ],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: "application/json",
        responseSchema: {
          type: "OBJECT",
          properties: {
            code: {type: "STRING"},
            serialNumber: {type: "STRING"},
          },
          required: ["code", "serialNumber"],
        },
      },
    },
  });

  const text =
    res.data?.candidates?.[0]?.content?.parts
      ?.map((p) => p.text || "")
      .join("")
      .trim() || "";

  if (!text) {
    throw new HttpsError("internal", "لم تُرجع القراءة أي نتيجة");
  }

  let parsed: {code?: string; serialNumber?: string};
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpsError("internal", "نتيجة القراءة غير صالحة");
  }

  return {
    code: normalizeCodeValue(String(parsed.code || "")),
    serialNumber: normalizeCodeValue(String(parsed.serialNumber || "")),
  };
}

/**
 * قراءة PIN والرقم التسلسلي من صورة إيصال (أدمن فقط).
 * يعمل عبر Vertex AI من السيرفر لتجاوز مشاكل App Check على العميل.
 */
export const scanCardImage = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }
    await requireAdmin(request.auth.uid);

    const imageBase64 = String(request.data?.imageBase64 || "").trim();
    const mimeType = String(request.data?.mimeType || "image/jpeg").trim();
    const fileName = String(request.data?.fileName || "image").trim();

    if (!imageBase64) {
      throw new HttpsError("invalid-argument", "الصورة مطلوبة");
    }
    // حدود حماية تقريباً ~4MB base64
    if (imageBase64.length > 5_500_000) {
      throw new HttpsError("invalid-argument", "حجم الصورة كبير جداً");
    }
    if (!mimeType.startsWith("image/")) {
      throw new HttpsError("invalid-argument", "نوع الملف يجب أن يكون صورة");
    }

    try {
      const result = await extractWithVertex({imageBase64, mimeType});
      if (!result.code || !result.serialNumber) {
        return {
          ok: false,
          fileName,
          code: result.code,
          serialNumber: result.serialNumber,
          error: "تعذر قراءة PIN أو الرقم التسلسلي من الصورة",
        };
      }
      return {
        ok: true,
        fileName,
        code: result.code,
        serialNumber: result.serialNumber,
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      const msg = e instanceof Error ? e.message : String(e);
      throw new HttpsError(
        "internal",
        `تعذر قراءة الصورة: ${msg}`
      );
    }
  }
);
