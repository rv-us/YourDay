import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { getTasks } from "../api/tasksApi";
import { getNotes } from "../api/notesApi";
import { getFriendStats } from "../api/dashboardApi";
import FriendActivityCard from "../components/dashboard/FriendActivityCard";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "../components/ui/card";

function getGreeting(name) {
  const hour = new Date().getHours();
  let time;
  if (hour < 12) time = "Good morning";
  else if (hour < 17) time = "Good afternoon";
  else time = "Good evening";
  return `${time}, ${name}.`;
}

function formatNoteDate(iso) {
  if (!iso) return "Freshly added";
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

export default function DashboardPage() {
  const { user } = useAuth();
  const displayName = user?.displayName || user?.email?.split("@")[0] || "there";

  const [todayTasks, setTodayTasks] = useState([]);
  const [notes, setNotes] = useState([]);
  const [friendCards, setFriendCards] = useState([]);
  const [friendCardIndex, setFriendCardIndex] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      getTasks("today").catch(() => []),
      getNotes().catch(() => []),
      getFriendStats().catch(() => []),
    ]).then(([tasks, notesData, friends]) => {
      setTodayTasks(tasks);
      setNotes(notesData);
      setFriendCards(friends);
      setLoading(false);
    });
  }, []);

  useEffect(() => {
    if (friendCards.length <= 1) return undefined;
    const timer = setInterval(() => {
      setFriendCardIndex((prev) => (prev + 1) % friendCards.length);
    }, 3200);
    return () => clearInterval(timer);
  }, [friendCards.length]);

  if (loading) {
    return (
      <div className="loading-center">
        <LoadingSpinner size={48} />
      </div>
    );
  }

  const pendingToday = todayTasks.filter((task) => !task.isDone);
  const completedToday = todayTasks.filter((task) => task.isDone);
  const recentNotes = notes.slice(0, 4);
  const activeFriends = friendCards.filter((friend) => !friend.isNoActivityYesterday).length;
  const completionPct = todayTasks.length ? Math.round((completedToday.length / todayTasks.length) * 100) : 0;

  return (
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <p className="page-title page-title--serif">{getGreeting(displayName)}</p>
                <div className="toolbar-actions">
                  <Link to="/tasks" className="btn btn-secondary">
                    Tasks
                  </Link>
                  <Link to="/garden" className="btn btn-ghost" style={{ color: "#f8f5ee", borderColor: "rgba(255,255,255,0.16)" }}>
                    Garden
                  </Link>
                </div>
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Open</div>
                  <div className="metric-value">{pendingToday.length}</div>
                  <div className="metric-meta">today</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Completion</div>
                  <div className="metric-value">{completionPct}%</div>
                  <div className="metric-meta">{completedToday.length} done</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Notes</div>
                  <div className="metric-value">{notes.length}</div>
                  <div className="metric-meta">saved</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Friends</div>
                  <div className="metric-value">{activeFriends}</div>
                  <div className="metric-meta">active</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="dashboard-grid dashboard-grid--two">
          <div className="stack">
            <Card>
              <CardHeader>
                <div>
                  <CardTitle>Focus Board</CardTitle>
                </div>
                <span className={`status-pill${pendingToday.length ? "" : " status-pill--warm"}`}>
                  {pendingToday.length ? `${pendingToday.length} in motion` : "cleared"}
                </span>
              </CardHeader>
              <CardContent>
                <div className="stack">
                  <div className="progress">
                    <div className="progress__fill" style={{ width: `${completionPct}%` }} />
                  </div>

                  {pendingToday.length === 0 ? (
                    <div className="empty-state">No tasks due today.</div>
                  ) : (
                    <div className="list">
                      {pendingToday.slice(0, 5).map((task) => (
                        <Link key={task.localTaskId} to="/tasks" className="list-item">
                          <div className="list-item__copy">
                            <span className="list-item__title">{task.title}</span>
                            <span className="list-item__meta">
                              {task.detail ? task.detail : task.dueDate ? `Due ${formatNoteDate(task.dueDate)}` : "Task ready"}
                            </span>
                          </div>
                          <span className="status-pill status-pill--warm">
                            {task.origin === "master" ? "Master" : "Today"}
                          </span>
                        </Link>
                      ))}
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <div>
                  <CardTitle>Recent Notes</CardTitle>
                </div>
                <Link to="/notes" className="section-link">
                  Notes
                </Link>
              </CardHeader>
              <CardContent>
                {recentNotes.length === 0 ? (
                  <div className="empty-state">No notes yet.</div>
                ) : (
                  <div className="list">
                    {recentNotes.map((note) => (
                      <Link key={note.id || note.localNoteId} to="/notes" className="list-item">
                        <div className="list-item__copy">
                          <span className="list-item__title">
                            {(note.content || "Untitled note").slice(0, 92)}
                            {note.content?.length > 92 ? "..." : ""}
                          </span>
                          <span className="list-item__meta">{formatNoteDate(note.createdAt)}</span>
                        </div>
                        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
                          <path d="M4.5 2.5L9 7L4.5 11.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
                        </svg>
                      </Link>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>

          <div className="stack">
            <Card variant="accent">
              <CardHeader>
                <div>
                  <CardTitle>Friends Activity</CardTitle>
                </div>
                {friendCards.length > 1 && (
                  <span className="status-pill">{friendCardIndex + 1} / {friendCards.length}</span>
                )}
              </CardHeader>
              <CardContent>
                {friendCards.length === 0 ? (
                  <div className="empty-state">No friend activity yet.</div>
                ) : (
                  <div className="stack--sm">
                    <FriendActivityCard card={friendCards[friendCardIndex]} />
                    {friendCards.length > 1 && (
                      <div style={{ display: "flex", gap: "0.45rem", justifyContent: "center" }}>
                        {friendCards.map((_, index) => (
                          <button
                            key={index}
                            type="button"
                            aria-label={`Show friend ${index + 1}`}
                            onClick={() => setFriendCardIndex(index)}
                            style={{
                              width: 10,
                              height: 10,
                              padding: 0,
                              borderRadius: "50%",
                              border: "none",
                              background: index === friendCardIndex ? "var(--moss-600)" : "rgba(77,129,52,0.18)",
                            }}
                          />
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>

            <Card variant="muted">
              <CardHeader>
                <div>
                  <CardTitle>Daily Summary</CardTitle>
                </div>
              </CardHeader>
              <CardContent>
                <div className="card-grid card-grid--two">
                  <div className="metric-card metric-card--light">
                    <div className="metric-label">Done</div>
                    <div className="metric-value" style={{ fontSize: "1.5rem", color: "var(--moss-700)" }}>
                      {completedToday.length}
                    </div>
                    <div className="metric-meta" style={{ color: "var(--text-secondary)" }}>
                      completed
                    </div>
                  </div>
                  <div className="metric-card metric-card--light">
                    <div className="metric-label">Captured</div>
                    <div className="metric-value" style={{ fontSize: "1.5rem", color: "var(--gold-500)" }}>
                      {notes.length}
                    </div>
                    <div className="metric-meta" style={{ color: "var(--text-secondary)" }}>
                      captured
                    </div>
                  </div>
                </div>
                <div style={{ marginTop: "1rem" }}>
                  <Link to="/journal" className="btn btn-primary" style={{ width: "100%" }}>
                    Journal
                  </Link>
                </div>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
