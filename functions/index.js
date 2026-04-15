/**
 * YourDay Cloud Functions
 *
 * sendChatNotification: Triggered when a new DM is written to `chat_messages`.
 * Reads the receiver's FCM tokens from Firestore and sends a push via FCM v1 REST API.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { GoogleAuth } = require("google-auth-library");
const https = require("https");

initializeApp();

const db = getFirestore();
const MAX_PREVIEW_LENGTH = 120;
const PROJECT_ID = "yourday-2998f";

// Reuse the auth client across warm invocations
let _authClient = null;
async function getAccessToken() {
  if (!_authClient) {
    _authClient = new GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
  }
  return _authClient.getAccessToken();
}

function sendFcmRequest(accessToken, payload) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ message: payload });
    const options = {
      hostname: "fcm.googleapis.com",
      path: `/v1/projects/${PROJECT_ID}/messages:send`,
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
      },
    };
    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => resolve({ status: res.statusCode, body: JSON.parse(data) }));
    });
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

exports.sendChatNotification = onDocumentCreated(
  "chat_messages/{messageId}",
  async (event) => {
    const message = event.data.data();
    if (!message) return;

    const { senderId, receiverId, content } = message;

    if (!receiverId || !senderId || receiverId === senderId) return;

    // Fetch receiver's FCM tokens
    const tokensSnap = await db
      .collection("users")
      .doc(receiverId)
      .collection("fcmTokens")
      .get();

    if (tokensSnap.empty) {
      console.log(`No FCM tokens for receiver ${receiverId}`);
      return;
    }

    const tokens = tokensSnap.docs.map((doc) => doc.id);

    // Fetch sender display name
    let senderName = "Someone";
    try {
      const senderFriendDoc = await db
        .collection("users")
        .doc(receiverId)
        .collection("friends")
        .doc(senderId)
        .get();
      if (senderFriendDoc.exists) {
        senderName = senderFriendDoc.data().displayName || senderName;
      }
    } catch (e) {
      console.warn("Could not fetch sender display name:", e);
    }

    const preview =
      (content || "").length > MAX_PREVIEW_LENGTH
        ? content.slice(0, MAX_PREVIEW_LENGTH - 3) + "..."
        : content || "Tap to open chat.";

    const accessToken = await getAccessToken();
    console.log(`Got access token (prefix: ${accessToken.slice(0,20)}), sending to ${tokens.length} token(s)...`);

    let successCount = 0;
    let failureCount = 0;
    const staleTokens = [];

    for (const token of tokens) {
      console.log(`Sending to token prefix: ${token.slice(0, 20)}...`);
      const payload = {
        token,
        notification: {
          title: `New message from ${senderName}`,
          body: preview,
        },
        data: {
          type: "chatMessage",
          senderId,
        },
        apns: {
          headers: {
            "apns-push-type": "alert",
            "apns-environment": "development",
          },
          payload: {
            aps: { sound: "default" },
          },
        },
      };

      const result = await sendFcmRequest(accessToken, payload);
      if (result.status === 200) {
        successCount++;
      } else {
        failureCount++;
        const errCode = result.body?.error?.details?.[0]?.errorCode || result.body?.error?.status;
        console.error(`FCM error for token: status=${result.status} code=${errCode} body=${JSON.stringify(result.body)}`);
        if (
          errCode === "UNREGISTERED" ||
          errCode === "INVALID_ARGUMENT"
        ) {
          staleTokens.push(token);
        }
      }
    }

    console.log(`FCM: ${successCount} sent, ${failureCount} failed for receiver ${receiverId}`);

    if (staleTokens.length > 0) {
      const batch = db.batch();
      staleTokens.forEach((token) => {
        batch.delete(
          db.collection("users").doc(receiverId).collection("fcmTokens").doc(token)
        );
      });
      await batch.commit();
      console.log(`FCM: Cleaned up ${staleTokens.length} stale token(s)`);
    }
  }
);
