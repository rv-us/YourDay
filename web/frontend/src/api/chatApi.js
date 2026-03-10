import api from "./axiosInstance";

export const getChatThreads = () => api.get("/api/chat/threads").then((r) => r.data);
export const getMessages = (friendId, limit = 50) =>
  api.get(`/api/chat/${friendId}/messages`, { params: { limit } }).then((r) => r.data);
export const sendMessage = (friendId, content) =>
  api.post(`/api/chat/${friendId}/messages`, { content }).then((r) => r.data);
