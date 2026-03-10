import { useState, useEffect, useCallback } from "react";
import { getTasks, createTask, updateTask, deleteTask } from "../api/tasksApi";

export function useTasks(origin) {
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    getTasks(origin)
      .then(setTasks)
      .catch(setError)
      .finally(() => setLoading(false));
  }, [origin]);

  useEffect(() => {
    const timeout = setTimeout(load, 0);
    return () => clearTimeout(timeout);
  }, [load]);

  const addTask = async (task) => {
    const result = await createTask(task);
    load();
    return result;
  };

  const toggleDone = async (taskId, isDone) => {
    await updateTask(taskId, { isDone });
    setTasks((prev) =>
      prev.map((t) =>
        t.localTaskId === taskId ? { ...t, isDone, completedAt: isDone ? new Date().toISOString() : null } : t
      )
    );
  };

  const editTask = async (taskId, updates) => {
    await updateTask(taskId, updates);
    load();
  };

  const removeTask = async (taskId) => {
    await deleteTask(taskId);
    setTasks((prev) => prev.filter((t) => t.localTaskId !== taskId));
  };

  return { tasks, loading, error, refresh: load, addTask, toggleDone, editTask, removeTask };
}
