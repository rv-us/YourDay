import api from "./axiosInstance";

export const getMyGroups = () => api.get("/api/groups").then((r) => r.data);
export const createGroup = (data) => api.post("/api/groups", data).then((r) => r.data);
export const getGroup = (groupId) => api.get(`/api/groups/${groupId}`).then((r) => r.data);
export const getGroupMessages = (groupId, limit = 50) =>
  api.get(`/api/groups/${groupId}/messages`, { params: { limit } }).then((r) => r.data);
export const sendGroupMessage = (groupId, content, senderDisplayName) =>
  api.post(`/api/groups/${groupId}/messages`, { content, senderDisplayName }).then((r) => r.data);
export const getGroupMembers = (groupId) =>
  api.get(`/api/groups/${groupId}/members`).then((r) => r.data);
export const leaveGroup = (groupId) =>
  api.delete(`/api/groups/${groupId}/leave`).then((r) => r.data);
