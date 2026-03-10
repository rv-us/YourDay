import api from "./axiosInstance";

export const getNotes = () => api.get("/api/notes").then((r) => r.data);
export const saveNote = (data) => api.post("/api/notes", data).then((r) => r.data);
export const deleteNote = (noteId) => api.delete(`/api/notes/${noteId}`).then((r) => r.data);
