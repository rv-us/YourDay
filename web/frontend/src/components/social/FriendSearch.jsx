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
        placeholder="Search by display name..."
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        style={{
          width: "100%",
          padding: "10px 14px",
          borderRadius: 10,
          border: "1px solid #C8DDB0",
          fontSize: 14,
          outline: "none",
          background: "white",
        }}
      />
      {loading && <p style={{ fontSize: 12, color: "#5A7A3A", marginTop: 8 }}>Searching...</p>}
      {results.length > 0 && (
        <div
          style={{
            marginTop: 8,
            background: "white",
            borderRadius: 10,
            border: "1px solid #C8DDB0",
            overflow: "hidden",
          }}
        >
          {results.map((user) => (
            <div
              key={user.userId}
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "10px 14px",
                borderBottom: "1px solid #F0F0F0",
              }}
            >
              <div>
                <div style={{ fontWeight: 600, fontSize: 14 }}>{user.displayName}</div>
                <div style={{ fontSize: 11, color: "#5A7A3A" }}>Level {user.playerLevel}</div>
              </div>
              <button
                className="btn btn-primary btn-sm"
                onClick={() => handleSend(user.displayName)}
                disabled={sent[user.displayName]}
              >
                {sent[user.displayName] ? "Sent ✓" : "Add"}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
