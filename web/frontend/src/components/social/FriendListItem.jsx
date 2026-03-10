import { Link } from "react-router-dom";
import { removeFriend } from "../../api/friendsApi";

export default function FriendListItem({ friend, onRemove }) {
  const handleRemove = async () => {
    if (!confirm(`Remove ${friend.displayName}?`)) return;
    await removeFriend(friend.userId);
    onRemove();
  };

  return (
    <div className="list-item">
      <div className="list-item__copy">
        <div className="list-item__title">{friend.displayName}</div>
      </div>
      <div className="toolbar-actions">
        <Link to={`/chat/${friend.userId}`}>
          <button className="btn btn-secondary btn-sm">Chat</button>
        </Link>
        <button className="btn btn-danger btn-sm" onClick={handleRemove}>Remove</button>
      </div>
    </div>
  );
}
