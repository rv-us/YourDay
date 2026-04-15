/**
 * Test script: writes a chat_messages doc via Firestore REST API
 * using the Firebase CLI's cached access token — no extra auth setup needed.
 *
 * Usage (all one line):
 *   SENDER_ID=<uid> RECEIVER_ID=<uid> node test-dm.js
 */

const https = require("https");
const os = require("os");
const fs = require("fs");
const path = require("path");

const PROJECT_ID  = "yourday-2998f";
const SENDER_ID   = process.env.SENDER_ID  || "REPLACE_ME";
const RECEIVER_ID = process.env.RECEIVER_ID || "REPLACE_ME";
const MESSAGE     = process.env.MESSAGE     || "Test DM from script";

// Load the cached Firebase CLI access token
const configPath = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
const token = config?.tokens?.access_token;
if (!token) { console.error("No Firebase token found. Run: firebase login"); process.exit(1); }

const body = JSON.stringify({
  fields: {
    senderId:   { stringValue: SENDER_ID },
    receiverId: { stringValue: RECEIVER_ID },
    content:    { stringValue: MESSAGE },
    timestamp:  { timestampValue: new Date().toISOString() },
  }
});

const options = {
  hostname: "firestore.googleapis.com",
  path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents/chat_messages`,
  method: "POST",
  headers: {
    "Authorization": `Bearer ${token}`,
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  },
};

console.log(`Sending DM: ${SENDER_ID} → ${RECEIVER_ID}`);
console.log(`Message: "${MESSAGE}"`);

const req = https.request(options, (res) => {
  let data = "";
  res.on("data", chunk => data += chunk);
  res.on("end", () => {
    const parsed = JSON.parse(data);
    if (res.statusCode === 200) {
      const docId = parsed.name?.split("/").pop();
      console.log("✅ Document written:", docId);
      console.log("Watch logs: firebase functions:log --only sendChatNotification -n 10");
    } else {
      console.error("❌ Error:", JSON.stringify(parsed, null, 2));
    }
  });
});

req.on("error", e => console.error("Request failed:", e));
req.write(body);
req.end();
