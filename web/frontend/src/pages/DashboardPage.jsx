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
  CardDescription,
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
                <span className="eyebrow">Garden Control Center</span>
                <div className="stack--sm">
                  <p className="page-title page-title--serif">{getGreeting(displayName)}</p>
                  <p className="page-summary">
                    Keep today tight: clear priorities, watch your garden momentum, and stay synced with the people
                    pushing alongside you.
                  </p>
                </div>
                <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
                  <Link to="/tasks" className="btn btn-secondary">
                    Review Today
                  </Link>
                  <Link to="/garden" className="btn btn-ghost" style={{ color: "#f8f5ee", borderColor: "rgba(255,255,255,0.16)" }}>
                    Visit Garden
                  </Link>
                </div>
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Today queue</div>
                  <div className="metric-value">{pendingToday.length}</div>
                  <div className="metric-meta">tasks still need attention</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Completion</div>
                  <div className="metric-value">{completionPct}%</div>
                  <div className="metric-meta">{completedToday.length} finished today</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Notes captured</div>
                  <div className="metric-value">{notes.length}</div>
                  <div className="metric-meta">thoughts saved in your workspace</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Social pulse</div>
                  <div className="metric-value">{activeFriends}</div>
                  <div className="metric-meta">friends showed movement yesterday</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="stats-grid">
          <Card variant="accent">
            <CardContent>
              <div className="mini-stat">
                <span className="metric-label">Focus load</span>
                <span className="mini-stat__value">{pendingToday.length || "0"}</span>
                <span className="mini-stat__label">
                  {pendingToday.length > 0 ? "Top priority items still open" : "You are clear for today"}
                </span>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent>
              <div className="mini-stat">
                <span className="metric-label">Notes bank</span>
                <span className="mini-stat__value">{notes.length}</span>
                <span className="mini-stat__label">Ideas and references ready to pull from</span>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent>
              <div className="mini-stat">
                <span className="metric-label">Friends active</span>
                <span className="mini-stat__value">{activeFriends}</span>
                <span className="mini-stat__label">Recent activity from your circle</span>
              </div>
            </CardContent>
          </Card>

          <Card variant="muted">
            <CardContent>
              <div className="mini-stat">
                <span className="metric-label">Journal cadence</span>
                <span className="mini-stat__value">{notes.length + completedToday.length}</span>
                <span className="mini-stat__label">Signals worth carrying into your summary</span>
              </div>
            </CardContent>
          </Card>
        </div>

        <div className="dashboard-grid dashboard-grid--two">
          <div className="stack">
            <Card>
              <CardHeader>
                <div>
                  <span className="eyebrow">Today</span>
                  <CardTitle>Focus Board</CardTitle>
                  <CardDescription>
                    Prioritized tasks for the current day, kept intentionally narrow.
                  </CardDescription>
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
                    <div className="empty-state">No tasks due today. Use this time to plan ahead or tend the garden.</div>
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
                  <span className="eyebrow">Capture</span>
                  <CardTitle>Recent Notes</CardTitle>
                  <CardDescription>Quick references and ideas worth keeping close.</CardDescription>
                </div>
                <Link to="/notes" className="section-link">
                  Open Notes
                </Link>
              </CardHeader>
              <CardContent>
                {recentNotes.length === 0 ? (
                  <div className="empty-state">No notes yet. Start a note to build your workspace memory.</div>
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
                  <span className="eyebrow">Social</span>
                  <CardTitle>Friends Activity</CardTitle>
                  <CardDescription>Momentum snapshots from the rest of your garden circle.</CardDescription>
                </div>
                {friendCards.length > 1 && (
                  <span className="status-pill">{friendCardIndex + 1} / {friendCards.length}</span>
                )}
              </CardHeader>
              <CardContent>
                {friendCards.length === 0 ? (
                  <div className="empty-state">Add friends to compare streaks, completed tasks, and daily movement.</div>
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
                  <span className="eyebrow">Reflection</span>
                  <CardTitle>Daily Summary</CardTitle>
                  <CardDescription>What you should carry into journaling before the day closes.</CardDescription>
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
                      tasks completed
                    </div>
                  </div>
                  <div className="metric-card metric-card--light">
                    <div className="metric-label">Captured</div>
                    <div className="metric-value" style={{ fontSize: "1.5rem", color: "var(--gold-500)" }}>
                      {notes.length}
                    </div>
                    <div className="metric-meta" style={{ color: "var(--text-secondary)" }}>
                      notes logged
                    </div>
                  </div>
                </div>
                <div style={{ marginTop: "1rem" }}>
                  <Link to="/journal" className="btn btn-primary" style={{ width: "100%" }}>
                    Open Daily Journal
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
