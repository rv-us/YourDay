import { useState, useEffect } from "react";
import { collection, query, where, orderBy, onSnapshot, or, and } from "firebase/firestore";
import { firestoreDb } from "../firebase";

export function useSharedTasks(friendId, currentUserId) {
  const [tasks, setTasks] = useState([]);

  useEffect(() => {
    if (!friendId || !currentUserId) return;

    const q = query(
      collection(firestoreDb, "shared_tasks"),
      or(
        and(where("senderId", "==", currentUserId), where("receiverId", "==", friendId)),
        and(where("senderId", "==", friendId), where("receiverId", "==", currentUserId))
      ),
      orderBy("createdAt", "desc")
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      setTasks(snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })));
    });

    return () => unsubscribe();
  }, [friendId, currentUserId]);

  return tasks;
}
