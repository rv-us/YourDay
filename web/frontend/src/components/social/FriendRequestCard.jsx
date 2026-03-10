import { acceptFriendRequest, declineFriendRequest } from "../../api/friendsApi";

export default function FriendRequestCard({ req, onUpdate }) {
  const handleAccept = async () => {
    await acceptFriendRequest(req.fromUserId);
    onUpdate();
  };

  const handleDecline = async () => {
    await declineFriendRequest(req.fromUserId);
    onUpdate();
  };

  return (
    <div className="list-item">
      <div className="list-item__copy">
        <div className="list-item__title">{req.displayName}</div>
        <div className="list-item__meta">sent a request</div>
      </div>
      <div className="toolbar-actions">
        <button className="btn btn-primary btn-sm" onClick={handleAccept}>Accept</button>
        <button className="btn btn-danger btn-sm" onClick={handleDecline}>Decline</button>
      </div>
    </div>
  );
}
