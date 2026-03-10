import api from "./axiosInstance";

export const getPlayerStats = () => api.get("/api/player/stats").then((r) => r.data);
