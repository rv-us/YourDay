import { useState } from "react";
import { useTasks } from "../hooks/useTasks";
import TaskListItem from "../components/tasks/TaskListItem";
import NewTaskModal from "../components/tasks/NewTaskModal";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../components/ui/card";

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
                <span className="eyebrow">Task Studio</span>
                <div className="stack--sm">
                  <h1 className="page-title">Keep the board disciplined.</h1>
                  <p className="page-summary">
                    Your work queue now reads like a real dashboard: focused lists, quick progress cues, and clean
                    separation between today and the longer-term master list.
                  </p>
                </div>
                <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
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
                  <div className="metric-label">Queue size</div>
                  <div className="metric-value">{tasks.length}</div>
                  <div className="metric-meta">items in the active board</div>
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
                <span className="eyebrow">Overview</span>
                <CardTitle>{filter === "today" ? "Today Board" : "Master Board"}</CardTitle>
                <CardDescription>
                  {filter === "today"
                    ? "A compact set of tasks that should move before the day ends."
                    : "Longer-horizon work staged outside the daily sprint."}
                </CardDescription>
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
                    <span className="mini-stat__label">tasks still in motion</span>
                  </div>
                  <div className="mini-stat">
                    <span className="metric-label">Done</span>
                    <span className="mini-stat__value">{completed.length}</span>
                    <span className="mini-stat__label">already completed</span>
                  </div>
                  <div className="mini-stat">
                    <span className="metric-label">Mode</span>
                    <span className="mini-stat__value" style={{ fontSize: "1.1rem" }}>
                      {filter === "today" ? "Sprint" : "Backlog"}
                    </span>
                    <span className="mini-stat__label">current planning lens</span>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div>
                <span className="eyebrow">Operating rule</span>
                <CardTitle>Board discipline</CardTitle>
                <CardDescription>
                  Keep the daily list narrow. Move overflow into the master board instead of diluting focus.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent>
              <div className="list">
                <div className="list-item">
                  <div className="list-item__copy">
                    <span className="list-item__title">Today should stay shippable</span>
                    <span className="list-item__meta">Only move urgent or high-confidence work into the sprint.</span>
                  </div>
                </div>
                <div className="list-item">
                  <div className="list-item__copy">
                    <span className="list-item__title">Master is for sequencing</span>
                    <span className="list-item__meta">Use it to stage follow-on work without losing momentum.</span>
                  </div>
                </div>
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
                    <span className="eyebrow">Work queue</span>
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
                    <div className="empty-state">No active tasks. Add one to start shaping the board.</div>
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
                    <span className="eyebrow">Completed</span>
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
                    <div className="empty-state">Completed tasks will collect here as you clear the board.</div>
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
