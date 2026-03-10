import api from "./axiosInstance";

export const getFriends = () => api.get("/api/friends").then((r) => r.data);
export const getFriendRequests = () => api.get("/api/friends/requests").then((r) => r.data);
export const searchUsers = (q) => api.get("/api/friends/search", { params: { q } }).then((r) => r.data);
export const sendFriendRequest = (toDisplayName) =>
  api.post("/api/friends/request", { toDisplayName }).then((r) => r.data);
export const acceptFriendRequest = (fromUserId) =>
  api.post("/api/friends/accept", { fromUserId }).then((r) => r.data);
export const declineFriendRequest = (fromUserId) =>
  api.post("/api/friends/decline", { fromUserId }).then((r) => r.data);
export const removeFriend = (friendId) =>
  api.delete(`/api/friends/${friendId}`).then((r) => r.data);
