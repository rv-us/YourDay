import { useState, useEffect, useCallback } from "react";
import { getLeaderboard, getFriendsLeaderboard } from "../api/leaderboardApi";

export function useLeaderboard(mode = "all") {
  const [entries, setEntries] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetch = useCallback(() => {
    setLoading(true);
    const fetcher = mode === "friends" ? getFriendsLeaderboard : getLeaderboard;
    fetcher()
      .then(setEntries)
      .catch(setError)
      .finally(() => setLoading(false));
  }, [mode]);

  useEffect(() => {
    const timeout = setTimeout(fetch, 0);
    const interval = setInterval(fetch, 60000);
    return () => {
      clearTimeout(timeout);
      clearInterval(interval);
    };
  }, [fetch]);

  return { entries, loading, error, refetch: fetch };
}
