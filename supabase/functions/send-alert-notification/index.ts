import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as jose from "https://deno.land/x/jose@v5.2.3/index.ts";

serve(async (req) => {
  try {
    const payload = await req.json();
    const alert = payload.record;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: devices, error } = await supabase
      .from("device_tokens")
      .select("token");

    if (error) throw error;

    if (!devices || devices.length === 0) {
      return new Response("No devices found", { status: 200 });
    }

    const accessToken = await getAccessToken();
    const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;

    const title = getTitle(alert.category);
    const body = alert.message ?? "New security alert received";

    for (const device of devices) {
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

      if (!res.ok) {
        const errorText = await res.text();
        console.log("FCM error:", errorText);
      }
    }

    return new Response("Notifications sent", { status: 200 });
  } catch (e) {
    return new Response(`Error: ${e.message}`, { status: 500 });
  }
});

async function getAccessToken() {
  const serviceAccountBase64 = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_BASE64")!;
  const serviceAccountText = atob(serviceAccountBase64);
  const serviceAccount = JSON.parse(serviceAccountText);

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