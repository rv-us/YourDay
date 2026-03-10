import { useState, useEffect } from "react";
import { getFriends, getFriendRequests } from "../api/friendsApi";

export function useFriends() {
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);

  const refresh = () => {
    setLoading(true);
    Promise.all([getFriends(), getFriendRequests()])
      .then(([f, r]) => {
        setFriends(f);
        setRequests(r);
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    const timeout = setTimeout(refresh, 0);
    return () => clearTimeout(timeout);
  }, []);

  return { friends, requests, loading, refresh };
}
