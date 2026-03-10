import api from "./axiosInstance";

export const getJournalEntries = () => api.get("/api/journal").then((r) => r.data);
export const getJournalEntry = (entryId) => api.get(`/api/journal/${entryId}`).then((r) => r.data);
