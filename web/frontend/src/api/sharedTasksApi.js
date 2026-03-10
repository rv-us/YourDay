import api from "./axiosInstance";

export const getSharedTasks = (friendId) =>
  api.get(`/api/shared-tasks/${friendId}`).then((r) => r.data);
export const createSharedTask = (data) =>
  api.post("/api/shared-tasks", data).then((r) => r.data);
export const acceptSharedTask = (taskId) =>
  api.patch(`/api/shared-tasks/${taskId}/accept`).then((r) => r.data);
export const completeSharedTask = (taskId, isCompleted) =>
  api.patch(`/api/shared-tasks/${taskId}/complete`, { isCompleted }).then((r) => r.data);
export const updateSharedSubtasks = (taskId, subtasks) =>
  api.patch(`/api/shared-tasks/${taskId}/subtasks`, { subtasks }).then((r) => r.data);
export const deleteSharedTask = (taskId) =>
  api.delete(`/api/shared-tasks/${taskId}`).then((r) => r.data);
