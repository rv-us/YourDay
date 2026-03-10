import {
  GoogleAuthProvider,
  linkWithPopup,
  reauthenticateWithPopup,
} from "firebase/auth";
import { auth } from "../firebase";

const GOOGLE_CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar";
const STORAGE_KEY_PREFIX = "yourday:google-calendar-token:";

function getStorageKey(uid) {
  return `${STORAGE_KEY_PREFIX}${uid}`;
}

function buildProvider() {
  const provider = new GoogleAuthProvider();
  provider.addScope(GOOGLE_CALENDAR_SCOPE);
  provider.setCustomParameters({
    prompt: "consent select_account",
  });
  return provider;
}

function persistToken(uid, accessToken) {
  if (!uid || !accessToken) return;
  window.localStorage.setItem(
    getStorageKey(uid),
    JSON.stringify({
      accessToken,
      savedAt: Date.now(),
    }),
  );
}

export function getStoredCalendarAccessToken(uid) {
  if (!uid) return null;

  try {
    const raw = window.localStorage.getItem(getStorageKey(uid));
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return parsed?.accessToken || null;
  } catch {
    return null;
  }
}

export function clearStoredCalendarAccessToken(uid) {
  if (!uid) return;
  window.localStorage.removeItem(getStorageKey(uid));
}

export async function connectGoogleCalendar() {
  const currentUser = auth.currentUser;
  if (!currentUser) {
    throw new Error("You must be signed in before connecting Google Calendar.");
  }

  const provider = buildProvider();
  let result;

  try {
    result = currentUser.providerData.some((providerInfo) => providerInfo.providerId === "google.com")
      ? await reauthenticateWithPopup(currentUser, provider)
      : await linkWithPopup(currentUser, provider);
  } catch (error) {
    if (error.code === "auth/provider-already-linked") {
      result = await reauthenticateWithPopup(currentUser, provider);
    } else {
      throw error;
    }
  }

  const credential = GoogleAuthProvider.credentialFromResult(result);
  const accessToken = credential?.accessToken;

  if (!accessToken) {
    throw new Error("Google Calendar access token was not returned.");
  }

  persistToken(currentUser.uid, accessToken);
  return accessToken;
}

export async function fetchGoogleCalendarEvents({ accessToken, start, end }) {
  if (!accessToken) {
    throw new Error("Google Calendar is not connected.");
  }

  const url = new URL("https://www.googleapis.com/calendar/v3/calendars/primary/events");
  url.searchParams.set("timeMin", start.toISOString());
  url.searchParams.set("timeMax", end.toISOString());
  url.searchParams.set("singleEvents", "true");
  url.searchParams.set("orderBy", "startTime");

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    const error = new Error("Unable to fetch calendar events.");
    error.status = response.status;
    error.detail = await response.text();
    throw error;
  }

  const payload = await response.json();
  return payload.items || [];
}
