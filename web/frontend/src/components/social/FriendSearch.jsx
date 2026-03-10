import { useState, useEffect, useRef } from "react";
import { searchUsers, sendFriendRequest } from "../../api/friendsApi";

export default function FriendSearch({ onRequestSent }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState({});
  const debounceRef = useRef(null);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    if (query.length < 2) {
      debounceRef.current = setTimeout(() => setResults([]), 0);
      return;
    }

    debounceRef.current = setTimeout(() => {
      setLoading(true);
      searchUsers(query)
        .then(setResults)
        .catch(() => setResults([]))
        .finally(() => setLoading(false));
    }, 500);

    return () => clearTimeout(debounceRef.current);
  }, [query]);

  const handleSend = async (displayName) => {
    try {
      await sendFriendRequest(displayName);
      setSent((prev) => ({ ...prev, [displayName]: true }));
      onRequestSent?.();
    } catch {
      alert("Could not send request. They may already be your friend.");
    }
  };

  return (
    <div>
      <input
        type="text"
        placeholder="Search display name"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
      />
      {loading && <p className="list-item__meta" style={{ marginTop: 8 }}>Searching...</p>}
      {results.length > 0 && (
        <div className="list" style={{ marginTop: 8 }}>
          {results.map((user) => (
            <div key={user.userId} className="list-item">
              <div className="list-item__copy">
                <div className="list-item__title">{user.displayName}</div>
                <div className="list-item__meta">Level {user.playerLevel}</div>
              </div>
              <button
                className="btn btn-primary btn-sm"
                onClick={() => handleSend(user.displayName)}
                disabled={sent[user.displayName]}
              >
                {sent[user.displayName] ? "Sent" : "Add"}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
