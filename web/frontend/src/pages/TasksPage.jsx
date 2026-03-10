import { useState } from "react";
import { useTasks } from "../hooks/useTasks";
import TaskListItem from "../components/tasks/TaskListItem";
import NewTaskModal from "../components/tasks/NewTaskModal";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";

export default function TasksPage() {
  const [filter, setFilter] = useState("today");
  const [showNewTask, setShowNewTask] = useState(false);
  const { tasks, loading, error, addTask, toggleDone, editTask, removeTask } = useTasks(filter);

  const inProgress = tasks.filter((task) => !task.isDone);
  const completed = tasks.filter((task) => task.isDone);
  const completionPct = tasks.length ? Math.round((completed.length / tasks.length) * 100) : 0;

  const handleMove = async (taskId, newOrigin) => {
    await editTask(taskId, { origin: newOrigin });
  };

  return (
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <h1 className="page-title">Tasks</h1>
                <div className="toolbar-actions">
                  <button className="btn btn-secondary" onClick={() => setShowNewTask(true)}>
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true">
                      <path d="M8 3V13M3 8H13" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
                    </svg>
                    Add Task
                  </button>
                  <div className="segmented-control">
                    {[
                      ["today", "Today"],
                      ["master", "Master List"],
                    ].map(([value, label]) => (
                      <button
                        key={value}
                        type="button"
                        className={`segmented-control__button${filter === value ? " segmented-control__button--active" : ""}`}
                        onClick={() => setFilter(value)}
                      >
                        {label}
                      </button>
                    ))}
                  </div>
                </div>
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Total</div>
                  <div className="metric-value">{tasks.length}</div>
                  <div className="metric-meta">{filter}</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Completed</div>
                  <div className="metric-value">{completed.length}</div>
                  <div className="metric-meta">{completionPct}% completion rate</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="task-summary-grid">
          <Card variant="accent">
            <CardHeader>
              <div>
                <CardTitle>{filter === "today" ? "Today Board" : "Master Board"}</CardTitle>
              </div>
            </CardHeader>
            <CardContent>
              <div className="stack">
                <div className="progress">
                  <div className="progress__fill" style={{ width: `${completionPct}%` }} />
                </div>
                <div className="card-grid card-grid--three">
                  <div className="mini-stat">
                    <span className="metric-label">Open</span>
                    <span className="mini-stat__value">{inProgress.length}</span>
                    <span className="mini-stat__label">in progress</span>
                  </div>
                  <div className="mini-stat">
                    <span className="metric-label">Done</span>
                    <span className="mini-stat__value">{completed.length}</span>
                    <span className="mini-stat__label">completed</span>
                  </div>
                  <div className="mini-stat">
                    <span className="metric-label">Mode</span>
                    <span className="mini-stat__value" style={{ fontSize: "1.1rem" }}>
                      {filter === "today" ? "Sprint" : "Backlog"}
                    </span>
                    <span className="mini-stat__label">view</span>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent>
              <div className="mini-stat">
                <span className="metric-label">Completion</span>
                <span className="mini-stat__value">{completionPct}%</span>
                <span className="mini-stat__label">{filter === "today" ? "today board" : "master board"}</span>
              </div>
            </CardContent>
          </Card>
        </div>

        {loading ? (
          <div className="loading-center">
            <LoadingSpinner size={48} />
          </div>
        ) : error ? (
          <Card>
            <CardContent>
              <div className="error-banner">Failed to load tasks. Check that the backend is running.</div>
            </CardContent>
          </Card>
        ) : (
          <div className="dashboard-grid dashboard-grid--two">
            <Card>
              <CardHeader>
                <div className="task-group__header">
                  <div>
                    <CardTitle>In Progress</CardTitle>
                  </div>
                  <div className="task-group__title">
                    <span className="task-dot task-dot--progress" />
                    {inProgress.length}
                  </div>
                </div>
              </CardHeader>
              <CardContent>
                <div className="task-group">
                  {inProgress.length === 0 ? (
                    <div className="empty-state">No active tasks.</div>
                  ) : (
                    inProgress.map((task) => (
                      <TaskListItem
                        key={task.localTaskId}
                        task={task}
                        onToggle={toggleDone}
                        onDelete={removeTask}
                        onMove={handleMove}
                      />
                    ))
                  )}
                </div>
              </CardContent>
            </Card>

            <Card variant="muted">
              <CardHeader>
                <div className="task-group__header">
                  <div>
                    <CardTitle>Done Queue</CardTitle>
                  </div>
                  <div className="task-group__title">
                    <span className="task-dot task-dot--complete" />
                    {completed.length}
                  </div>
                </div>
              </CardHeader>
              <CardContent>
                <div className="task-group">
                  {completed.length === 0 ? (
                    <div className="empty-state">Nothing completed yet.</div>
                  ) : (
                    completed.map((task) => (
                      <TaskListItem
                        key={task.localTaskId}
                        task={task}
                        onToggle={toggleDone}
                        onDelete={removeTask}
                        onMove={handleMove}
                      />
                    ))
                  )}
                </div>
              </CardContent>
            </Card>
          </div>
        )}
      </div>

      {showNewTask && (
        <NewTaskModal
          origin={filter}
          onSave={addTask}
          onClose={() => setShowNewTask(false)}
        />
      )}
    </div>
  );
}
