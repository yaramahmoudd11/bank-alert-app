import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as jose from "https://deno.land/x/jose@v5.2.3/index.ts";

serve(async (req) => {
  try {
    const payload = await req.json();
    const alert = payload.record;

    if (!alert) {
      return new Response("No alert record found", { status: 400 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: devices, error } = await supabase
      .from("device_tokens")
      .select("id, token");

    if (error) {
      console.log("Supabase device_tokens error:", error);
      throw error;
    }

    if (!devices || devices.length === 0) {
      console.log("No device tokens found");
      return new Response("No device tokens found", { status: 200 });
    }

    const serviceAccountBase64 = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_BASE64")!;
    const serviceAccountText = atob(serviceAccountBase64);
    const serviceAccount = JSON.parse(serviceAccountText);
    console.log("ENV FIREBASE_PROJECT_ID:", Deno.env.get("FIREBASE_PROJECT_ID"));
    console.log("SERVICE ACCOUNT PROJECT:", serviceAccount.project_id);
    console.log("SERVICE ACCOUNT EMAIL:", serviceAccount.client_email);
    const projectId = serviceAccount.project_id;

    console.log("=== DEBUG ===");
    console.log("Project ID from service account:", projectId);
    console.log("Client email:", serviceAccount.client_email);
    console.log("Number of devices:", devices.length);
    console.log("=============");

    const accessToken = await getAccessToken(serviceAccount);

    const title = getTitle(String(alert.category ?? ""));
    const body = String(alert.message ?? "New security alert received");

    let successCount = 0;
    let failCount = 0;

    for (const device of devices) {
      console.log(`Sending to token id ${device.id}, token: ${device.token.substring(0, 20)}...`);

      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: {
                title,
                body,
              },
              data: {
                alert_id: String(alert.id ?? ""),
                category: String(alert.category ?? ""),
                location: String(alert.location ?? ""),
                image_path: String(alert.image_path ?? ""),
              },
              android: {
                priority: "HIGH",
                notification: {
                  channel_id: "bank_alerts_channel",
                  sound: "default",
                },
              },
              apns: {
                payload: {
                  aps: {
                    sound: "default",
                  },
                },
              },
            },
          }),
        }
      );

      const resultText = await res.text();

      if (res.ok) {
        successCount++;
        console.log(`FCM sent successfully to token id ${device.id}:`, resultText);
      } else {
        failCount++;
        console.log(`FCM error for token id ${device.id}:`, resultText);
      }
    }

    return new Response(
      `Notifications done. Success: ${successCount}, Failed: ${failCount}`,
      { status: 200 }
    );
  } catch (e) {
    console.log("Function error:", e);
    return new Response(`Error: ${e.message}`, { status: 500 });
  }
});

async function getAccessToken(serviceAccount: any) {
  const privateKey = await jose.importPKCS8(
    serviceAccount.private_key,
    "RS256"
  );

  const now = Math.floor(Date.now() / 1000);

  const jwt = await new jose.SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(serviceAccount.client_email)
    .setSubject(serviceAccount.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const data = await res.json();

  if (!data.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(data)}`);
  }

  return data.access_token;
}

function getTitle(category: string) {
  switch (category) {
    case "access":
      return "Unauthorized Access";
    case "intrusion":
      return "After-Hours Intrusion";
    case "power":
      return "Power Alert";
    default:
      return "Bank Security Alert";
  }
}