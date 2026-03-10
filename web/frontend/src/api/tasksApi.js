import api from "./axiosInstance";

export function getTasks(origin) {
  const params = origin ? { origin } : {};
  return api.get("/api/tasks", { params }).then((r) => r.data);
}

export function createTask(task) {
  return api.post("/api/tasks", task).then((r) => r.data);
}

export function updateTask(taskId, updates) {
  return api.patch(`/api/tasks/${taskId}`, updates).then((r) => r.data);
}

export function deleteTask(taskId) {
  return api.delete(`/api/tasks/${taskId}`).then((r) => r.data);
}
