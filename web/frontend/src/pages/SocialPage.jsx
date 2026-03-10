import { Link } from "react-router-dom";
import { useFriends } from "../hooks/useFriends";
import FriendSearch from "../components/social/FriendSearch";
import FriendRequestCard from "../components/social/FriendRequestCard";
import FriendListItem from "../components/social/FriendListItem";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";

export default function SocialPage() {
  const { friends, requests, loading, refresh } = useFriends();

  return (
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <h1 className="page-title">Social</h1>
                <div className="toolbar-actions">
                  <Link to="/leaderboard" className="btn btn-secondary">
                    Leaderboard
                  </Link>
                  <Link to="/chat" className="btn btn-ghost" style={{ color: "#f8f5ee", borderColor: "rgba(255,255,255,0.16)" }}>
                    Messages
                  </Link>
                </div>
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Friends</div>
                  <div className="metric-value">{friends.length}</div>
                  <div className="metric-meta">connected</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Requests</div>
                  <div className="metric-value">{requests.length}</div>
                  <div className="metric-meta">pending</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Find Friends</CardTitle>
          </CardHeader>
          <CardContent>
            <FriendSearch onRequestSent={refresh} />
          </CardContent>
        </Card>

        {loading ? (
          <div className="loading-center"><LoadingSpinner /></div>
        ) : (
          <div className="dashboard-grid dashboard-grid--two">
            <Card variant="accent">
              <CardHeader>
                <CardTitle>Friend Requests</CardTitle>
              </CardHeader>
              <CardContent>
                {requests.length === 0 ? (
                  <div className="empty-state">No pending requests.</div>
                ) : (
                  <div className="list">
                    {requests.map((req) => (
                      <FriendRequestCard key={req.requestId} req={req} onUpdate={refresh} />
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Your Friends</CardTitle>
              </CardHeader>
              <CardContent>
                {friends.length === 0 ? (
                  <div className="empty-state">No friends yet.</div>
                ) : (
                  <div className="list">
                    {friends.map((friend) => (
                      <FriendListItem key={friend.userId} friend={friend} onRemove={refresh} />
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        )}
      </div>
    </div>
  );
}
