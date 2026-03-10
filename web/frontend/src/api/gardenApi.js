import api from "./axiosInstance";

export const getGarden = () => api.get("/api/garden").then((r) => r.data);
export const getFriendGarden = (friendId) => api.get(`/api/garden/friend/${friendId}`).then((r) => r.data);
