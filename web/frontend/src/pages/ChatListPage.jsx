import { useState, useEffect } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { getChatThreads } from "../api/chatApi";
import { useGroups } from "../hooks/useGroups";
import { createGroup } from "../api/groupsApi";
import { getFriends } from "../api/friendsApi";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";

function ThreadItem({ to, avatar, name, subtitle, timestamp, isGroup }) {
  return (
    <Link to={to} className="list-item">
      <div className="chat-header__title">
        <div
          style={{
            width: 42,
            height: 42,
            borderRadius: isGroup ? 14 : "50%",
            background: isGroup
              ? "linear-gradient(135deg, #7B1FA2, #CE93D8)"
              : "linear-gradient(135deg, #56AB2F, #A8E063)",
            display: "grid",
            placeItems: "center",
            color: "white",
            fontWeight: 700,
            flexShrink: 0,
          }}
        >
          {(avatar || "?")[0].toUpperCase()}
        </div>
        <div className="list-item__copy">
          <div className="list-item__title">{name}</div>
          <div className="list-item__meta">{subtitle || "No messages yet"}</div>
        </div>
      </div>
      <div className="compact-meta">
        {isGroup && <span className="status-pill">Group</span>}
        {timestamp && (
          <span className="list-item__meta">
            {new Date(timestamp).toLocaleDateString()}
          </span>
        )}
      </div>
    </Link>
  );
}

export default function ChatListPage() {
  const { user } = useAuth();
  const [threads, setThreads] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showNewGroup, setShowNewGroup] = useState(false);
  const [friends, setFriends] = useState([]);
  const [groupName, setGroupName] = useState("");
  const [selectedMembers, setSelectedMembers] = useState([]);
  const groups = useGroups(user?.uid);

  useEffect(() => {
    getChatThreads()
      .then(setThreads)
      .finally(() => setLoading(false));
    getFriends().then(setFriends).catch(() => {});
  }, []);

  const toggleMember = (userId) => {
    setSelectedMembers((prev) =>
      prev.includes(userId) ? prev.filter((id) => id !== userId) : [...prev, userId]
    );
  };

  const handleCreateGroup = async (event) => {
    event.preventDefault();
    if (!groupName.trim() || selectedMembers.length === 0) return;

    const memberDisplayNames = {};
    if (user?.uid) {
      memberDisplayNames[user.uid] = user.displayName || user.email?.split("@")[0] || "";
    }

    friends.filter((friend) => selectedMembers.includes(friend.userId)).forEach((friend) => {
      memberDisplayNames[friend.userId] = friend.displayName;
    });

    await createGroup({
      name: groupName,
      memberIds: selectedMembers,
      memberDisplayNames,
    });

    setGroupName("");
    setSelectedMembers([]);
    setShowNewGroup(false);
  };

  return (
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <h1 className="page-title">Messages</h1>
                <div className="toolbar-actions">
                  <button className="btn btn-secondary" onClick={() => setShowNewGroup((value) => !value)}>
                    {showNewGroup ? "Close Group" : "New Group"}
                  </button>
                </div>
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Direct</div>
                  <div className="metric-value">{threads.length}</div>
                  <div className="metric-meta">threads</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Groups</div>
                  <div className="metric-value">{groups.length}</div>
                  <div className="metric-meta">chats</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {showNewGroup && (
          <Card variant="accent">
            <CardHeader>
              <CardTitle>New Group</CardTitle>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleCreateGroup} className="stack">
                <input
                  placeholder="Group name"
                  value={groupName}
                  onChange={(event) => setGroupName(event.target.value)}
                  required
                />
                <div className="list">
                  {friends.length === 0 ? (
                    <div className="empty-state">No friends to add.</div>
                  ) : (
                    friends.map((friend) => (
                      <label key={friend.userId} className="list-item" style={{ cursor: "pointer" }}>
                        <div className="list-item__copy">
                          <div className="list-item__title">{friend.displayName}</div>
                        </div>
                        <input
                          type="checkbox"
                          checked={selectedMembers.includes(friend.userId)}
                          onChange={() => toggleMember(friend.userId)}
                          style={{ width: 18, height: 18 }}
                        />
                      </label>
                    ))
                  )}
                </div>
                <div className="toolbar-actions">
                  <button type="submit" className="btn btn-primary btn-sm">Create</button>
                  <button type="button" className="btn btn-secondary btn-sm" onClick={() => setShowNewGroup(false)}>Cancel</button>
                </div>
              </form>
            </CardContent>
          </Card>
        )}

        {loading ? (
          <div className="loading-center"><LoadingSpinner /></div>
        ) : (
          <Card>
            <CardContent>
              {groups.length === 0 && threads.length === 0 ? (
                <div className="empty-state">No conversations yet.</div>
              ) : (
                <div className="list">
                  {groups.map((group) => (
                    <ThreadItem
                      key={group.id}
                      to={`/group/${group.id}`}
                      avatar={group.name}
                      name={group.name}
                      subtitle={group.lastMessageText}
                      timestamp={group.lastMessageAt?.toDate?.()?.toISOString() ?? group.lastMessageAt}
                      isGroup
                    />
                  ))}
                  {threads.map((thread) => (
                    <ThreadItem
                      key={thread.friendId}
                      to={`/chat/${thread.friendId}`}
                      avatar={thread.displayName}
                      name={thread.displayName}
                      subtitle={thread.lastMessage?.content}
                      timestamp={thread.lastMessage?.timestamp}
                      isGroup={false}
                    />
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
