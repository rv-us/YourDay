import api from "./axiosInstance";

export const getLeaderboard = (limit = 100, orderBy = "gardenValue") =>
  api.get("/api/leaderboard", { params: { limit, orderBy } }).then((r) => r.data);

export const getFriendsLeaderboard = () =>
  api.get("/api/leaderboard/friends").then((r) => r.data);
