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
      <div>
        <div style={{ fontWeight: 600, fontSize: 14 }}>{req.displayName}</div>
        <div style={{ fontSize: 11, color: "#5A7A3A" }}>wants to be your friend</div>
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <button className="btn btn-primary btn-sm" onClick={handleAccept}>Accept</button>
        <button className="btn btn-danger btn-sm" onClick={handleDecline}>Decline</button>
      </div>
    </div>
  );
}
