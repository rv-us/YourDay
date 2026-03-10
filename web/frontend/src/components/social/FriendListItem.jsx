import { Link } from "react-router-dom";
import { removeFriend } from "../../api/friendsApi";

export default function FriendListItem({ friend, onRemove }) {
  const handleRemove = async () => {
    if (!confirm(`Remove ${friend.displayName}?`)) return;
    await removeFriend(friend.userId);
    onRemove();
  };

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "12px 16px",
        background: "white",
        borderRadius: 10,
        border: "1px solid #C8DDB0",
        marginBottom: 8,
      }}
    >
      <div style={{ fontWeight: 600, fontSize: 14 }}>{friend.displayName}</div>
      <div style={{ display: "flex", gap: 8 }}>
        <Link to={`/chat/${friend.userId}`}>
          <button className="btn btn-secondary btn-sm">Chat</button>
        </Link>
        <button className="btn btn-danger btn-sm" onClick={handleRemove}>Remove</button>
      </div>
    </div>
  );
}
