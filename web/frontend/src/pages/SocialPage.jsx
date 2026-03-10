import { Link } from "react-router-dom";
import { useFriends } from "../hooks/useFriends";
import FriendSearch from "../components/social/FriendSearch";
import FriendRequestCard from "../components/social/FriendRequestCard";
import FriendListItem from "../components/social/FriendListItem";
import LoadingSpinner from "../components/shared/LoadingSpinner";

export default function SocialPage() {
  const { friends, requests, loading, refresh } = useFriends();

  return (
    <div className="page-container">
      <h2 style={{ fontSize: 22, fontWeight: 800, marginBottom: 20 }}>Social</h2>

      {/* Quick links */}
      <div style={{ display: "flex", gap: 10, marginBottom: 20 }}>
        <Link to="/leaderboard" style={{ flex: 1 }}>
          <div
            style={{
              background: "linear-gradient(135deg, #2E6B10 0%, #56AB2F 100%)",
              borderRadius: 14,
              padding: "16px 18px",
              color: "white",
              display: "flex",
              alignItems: "center",
              gap: 12,
              transition: "transform 0.15s",
            }}
            onMouseEnter={(e) => (e.currentTarget.style.transform = "scale(1.02)")}
            onMouseLeave={(e) => (e.currentTarget.style.transform = "scale(1)")}
          >
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round">
              <path d="M8 21V11M16 21V3M12 21V7" />
            </svg>
            <div>
              <div style={{ fontWeight: 700, fontSize: 15 }}>Leaderboard</div>
              <div style={{ fontSize: 11, opacity: 0.85 }}>See rankings</div>
            </div>
          </div>
        </Link>

        <Link to="/chat" style={{ flex: 1 }}>
          <div
            style={{
              background: "linear-gradient(135deg, #7B1FA2 0%, #CE93D8 100%)",
              borderRadius: 14,
              padding: "16px 18px",
              color: "white",
              display: "flex",
              alignItems: "center",
              gap: 12,
              transition: "transform 0.15s",
            }}
            onMouseEnter={(e) => (e.currentTarget.style.transform = "scale(1.02)")}
            onMouseLeave={(e) => (e.currentTarget.style.transform = "scale(1)")}
          >
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round">
              <path d="M21 15C21 15.53 20.79 16.04 20.41 16.41C20.04 16.79 19.53 17 19 17H7L3 21V5C3 4.47 3.21 3.96 3.59 3.59C3.96 3.21 4.47 3 5 3H19C19.53 3 20.04 3.21 20.41 3.59C20.79 3.96 21 4.47 21 5V15Z" />
            </svg>
            <div>
              <div style={{ fontWeight: 700, fontSize: 15 }}>Messages</div>
              <div style={{ fontSize: 11, opacity: 0.85 }}>Chat with friends</div>
            </div>
          </div>
        </Link>
      </div>

      {/* Search */}
      <div className="card" style={{ marginBottom: 20 }}>
        <h3 className="section-title">Find Friends</h3>
        <FriendSearch onRequestSent={refresh} />
      </div>

      {loading ? (
        <div className="loading-center"><LoadingSpinner /></div>
      ) : (
        <>
          {/* Pending requests */}
          {requests.length > 0 && (
            <div className="card" style={{ marginBottom: 20 }}>
              <h3 className="section-title">Friend Requests ({requests.length})</h3>
              {requests.map((req) => (
                <FriendRequestCard key={req.requestId} req={req} onUpdate={refresh} />
              ))}
            </div>
          )}

          {/* Friends list */}
          <div className="card">
            <h3 className="section-title">Your Friends ({friends.length})</h3>
            {friends.length === 0 ? (
              <p style={{ color: "#5A7A3A", fontSize: 14 }}>No friends yet. Search for people above!</p>
            ) : (
              friends.map((friend) => (
                <FriendListItem key={friend.userId} friend={friend} onRemove={refresh} />
              ))
            )}
          </div>
        </>
      )}
    </div>
  );
}
