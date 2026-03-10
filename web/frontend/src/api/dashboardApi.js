import api from "./axiosInstance";

export function getFriendStats() {
  return api.get("/api/dashboard/friend-stats").then((r) => r.data);
}
